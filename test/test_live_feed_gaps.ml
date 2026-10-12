(* [Live_feed.feed_with_gaps] with a scripted local websocket server on a synthetic clock:
   a dropped connection and a [change_id] break each report a [Resync] gap before the
   events that follow them. *)

open! Core
open Async
open Deribit_feed

let book ?prev ?(type_ = "change") ~change_id () =
  sprintf
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"book.BTC-PERPETUAL.100ms","data":{"type":"%s","timestamp":1554373962454,"instrument_name":"BTC-PERPETUAL",%s"change_id":%d,"bids":[["new",5042.34,30]],"asks":[["new",5043.3,40]]}}}|}
    type_
    (match prev with
     | None -> ""
     | Some prev -> sprintf {|"prev_change_id":%d,|} prev)
    change_id
;;

let snapshot ~change_id = book ~type_:"snapshot" ~change_id ()
let ms time = Time_ns.to_int_ns_since_epoch time / 1_000_000

let print_gap (gap : Market_data.Gap.t) =
  print_s
    [%message
      "gap"
        ~recv_ts_ms:(ms gap.recv_ts : int)
        ~instrument:
          (Option.map gap.instrument ~f:Market_data.Instrument.to_string : string option)
        ~stream:(gap.stream : Market_data.Stream.t option)
        ~reason:(gap.reason : Market_data.Gap.Reason.t)]
;;

let print_l2 (update : Market_data.L2_update.t) =
  print_s
    [%message
      "l2"
        ~recv_ts_ms:(ms update.recv_ts : int)
        ~kind:
          ((match update.kind with
            | Snapshot -> "snapshot"
            | Delta -> "delta")
           : string)]
;;

let%expect_test "a reconnect and a book break are gaps, written before the next events" =
  Log.Global.set_output [];
  let%bind server = Fake_ws.start () in
  let clock = Time_source.create ~now:Time_ns.epoch () in
  (* For every book frame, the number of gaps written so far (read or not): proves a gap
     is written before the frame that follows it is even parsed. *)
  let gaps_written = ref (fun () -> 0) in
  let%bind live =
    Live_feed.start
      ~on_raw:(fun ~stream:_ ~recv_ts:_ frame ->
        if String.is_substring frame ~substring:"\"change_id\""
        then
          print_s
            [%message
              "book frame"
                ~type_:
                  (if String.is_substring frame ~substring:"snapshot"
                   then "snapshot"
                   else "change"
                   : string)
                ~gaps_written:(!gaps_written () : int)])
      ~time_source:(Time_source.read_only clock)
      (Fake_ws.config server)
      ~symbols:[ "BTC-PERPETUAL" ]
      ~streams:[ L2 ]
  in
  let module F = (val Live_feed.feed_with_gaps live : Market_data.Feed.With_gaps.S) in
  let gaps_read = ref 0 in
  (gaps_written := fun () -> !gaps_read + Pipe.length F.gaps);
  (* Gaps then events, after each step; the order across pipes is checked by [on_raw]. *)
  let drain () =
    let gaps = Pipe.read_now' F.gaps in
    let l2 = Pipe.read_now' F.l2 in
    (match gaps with
     | `Ok gaps ->
       gaps_read := !gaps_read + Queue.length gaps;
       Queue.iter gaps ~f:print_gap
     | `Eof | `Nothing_available -> ());
    match l2 with
    | `Ok l2 -> Queue.iter l2 ~f:print_l2
    | `Eof | `Nothing_available -> ()
  in
  let count substring () =
    List.count (Fake_ws.received server) ~f:(String.is_substring ~substring)
  in
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> count "public/subscribe" () = 1) in
  Fake_ws.send server (snapshot ~change_id:10);
  Fake_ws.send server (book ~prev:10 ~change_id:11 ());
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> Pipe.length F.l2 = 2) in
  drain ();
  [%expect
    {|
    ("book frame" (type_ snapshot) (gaps_written 0))
    ("book frame" (type_ change) (gaps_written 0))
    (l2 (recv_ts_ms 0) (kind snapshot))
    (l2 (recv_ts_ms 0) (kind delta))
    |}];
  (* A change that does not join the last one: gap, then unsubscribe and subscribe. *)
  let%bind () = Time_source.advance_by_alarms_by clock (Time_ns.Span.of_int_ms 100) in
  Fake_ws.send server (book ~prev:12 ~change_id:13 ());
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> count "public/subscribe" () = 2) in
  Fake_ws.send server (snapshot ~change_id:20);
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> Pipe.length F.l2 = 1) in
  drain ();
  print_s
    [%message
      "after the break"
        ~unsubscribes:(count "public/unsubscribe" () : int)
        ~subscribes:(count "public/subscribe" () : int)];
  [%expect
    {|
    ("book frame" (type_ change) (gaps_written 0))
    ("book frame" (type_ snapshot) (gaps_written 1))
    (gap (recv_ts_ms 100) (instrument (deribit:BTC-PERPETUAL)) (stream (L2))
     (reason Resync))
    (l2 (recv_ts_ms 100) (kind snapshot))
    ("after the break" (unsubscribes 1) (subscribes 2))
    |}];
  (* A dropped connection: the first backoff is 0.5s +-20%, so the new connection is up by
     0.7s. Its snapshot follows the gap. *)
  let%bind () = Fake_ws.drop server in
  let%bind () = Clock_ns.after (Time_ns.Span.of_int_ms 50) in
  let%bind () = Time_source.advance_by_alarms_by clock (Time_ns.Span.of_int_ms 600) in
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> count "public/subscribe" () = 3) in
  Fake_ws.send server (snapshot ~change_id:30);
  let%bind (_ : bool) = Fake_ws.wait_until (fun () -> Pipe.length F.l2 = 1) in
  drain ();
  print_s [%sexp (Live_feed.stats live : Live_feed.Stats.t)];
  [%expect
    {|
    ("book frame" (type_ snapshot) (gaps_written 2))
    (gap (recv_ts_ms 700) (instrument ()) (stream (L2)) (reason Resync))
    (l2 (recv_ts_ms 700) (kind snapshot))
    ((frames 5) (parse_errors 0) (reconnects 1))
    |}];
  let%bind () = F.close () in
  let%bind () = Pipe.closed F.gaps in
  print_endline "gaps closed";
  [%expect {| gaps closed |}];
  Fake_ws.close server
;;
