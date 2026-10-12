open! Core
open Async
module Md = Market_data
module Ws_client = Venue_net.Ws_client

let channel (config : Config.t) (stream : Md.Stream.t) instrument : Wire.Channel.t =
  let interval = config.interval in
  match stream with
  | Trades -> Trades { instrument; interval }
  | Bbo -> Quote instrument
  | L2 -> Book { instrument; interval }
  | Funding -> Ticker { instrument; interval }
  | Private -> raise_s [%message "Deribit_feed.Live_feed: no public channel for private"]
;;

let ping_interval = Time_ns.Span.of_sec 15.
let heartbeat_seconds = 30

type counters =
  { mutable frames : int
  ; mutable parse_errors : int
  ; mutable clients : Ws_client.t list
  }

type t =
  { feed : Md.Feed.t
  ; counters : counters
  }

module Stats = struct
  type t =
    { frames : int
    ; parse_errors : int
    ; reconnects : int
    }
  [@@deriving sexp_of]
end

let stats { counters = c; _ } : Stats.t =
  { frames = c.frames
  ; parse_errors = c.parse_errors
  ; reconnects = List.sum (module Int) c.clients ~f:Ws_client.reconnects
  }
;;

let feed t = t.feed

let start ?on_raw config ~symbols ~streams =
  let streams = List.dedup_and_sort streams ~compare:Md.Stream.compare in
  if List.mem streams Private ~equal:Md.Stream.equal
  then raise_s [%message "Deribit_feed.Live_feed.create: private is not a market feed"];
  let trades_r, trades_w = Pipe.create () in
  let bbo_r, bbo_w = Pipe.create () in
  let l2_r, l2_w = Pipe.create () in
  let funding_r, funding_w = Pipe.create () in
  let emit : Md.Event.t -> unit = function
    | Trade x -> Pipe.write_without_pushback_if_open trades_w x
    | Bbo x -> Pipe.write_without_pushback_if_open bbo_w x
    | L2 x -> Pipe.write_without_pushback_if_open l2_w x
    | Funding x -> Pipe.write_without_pushback_if_open funding_w x
  in
  let counters = { frames = 0; parse_errors = 0; clients = [] } in
  let next_id =
    let id = ref 0 in
    fun () ->
      incr id;
      !id
  in
  let connect stream =
    let name = Md.Stream.to_string stream in
    let channels = List.map symbols ~f:(channel config stream) in
    let normalizer = Normalizer.create () in
    let on_connect ws =
      if Ws_client.reconnects ws > 0
      then (
        Log.Global.info "deribit feed: %s reconnected, resubscribing" name;
        Normalizer.reset normalizer);
      let%bind () =
        Ws_client.send ws (Wire.set_heartbeat ~id:(next_id ()) ~seconds:heartbeat_seconds)
      in
      Ws_client.send ws (Wire.subscribe ~id:(next_id ()) channels)
    in
    let%map ws =
      Ws_client.connect
        ~ping:(`Text (Wire.test ~id:0, ping_interval))
        ~on_connect
        ~log_name:("deribit " ^ name)
        ~url:config.url
        ()
      >>| Or_error.ok_exn
    in
    let handle frame =
      let recv_ts = Time_ns.now () in
      counters.frames <- counters.frames + 1;
      Option.iter on_raw ~f:(fun on_raw -> on_raw ~stream ~recv_ts frame);
      match Normalizer.frame normalizer ~recv_ts frame with
      | Error error ->
        counters.parse_errors <- counters.parse_errors + 1;
        Log.Global.error_s
          [%message
            "deribit feed: cannot handle frame"
              ~stream:name
              (frame : string)
              (error : Error.t)]
      | Ok outputs ->
        List.iter outputs ~f:(function
          | Event event -> emit event
          | Answer_test_request ->
            don't_wait_for (Ws_client.send ws (Wire.test ~id:(next_id ())))
          | Resubscribe channel ->
            don't_wait_for
              (let%bind () =
                 Ws_client.send ws (Wire.unsubscribe ~id:(next_id ()) [ channel ])
               in
               Ws_client.send ws (Wire.subscribe ~id:(next_id ()) [ channel ])))
    in
    don't_wait_for (Pipe.iter_without_pushback (Ws_client.messages ws) ~f:handle);
    ws
  in
  let opened = ref [] in
  let close_all () = Deferred.List.iter !opened ~how:`Parallel ~f:Ws_client.close in
  let%bind () =
    match%bind
      Monitor.try_with (fun () ->
        Deferred.List.iter streams ~how:`Sequential ~f:(fun stream ->
          let%map ws = connect stream in
          opened := ws :: !opened;
          counters.clients <- !opened))
    with
    | Ok () -> return ()
    | Error exn ->
      let%map () = close_all () in
      raise exn
  in
  let closed =
    Lazy_deferred.create (fun () ->
      let%map () = close_all () in
      Pipe.close trades_w;
      Pipe.close bbo_w;
      Pipe.close l2_w;
      Pipe.close funding_w)
  in
  return
    { counters
    ; feed =
        (module struct
          let trades = trades_r
          let bbo = bbo_r
          let l2 = l2_r
          let funding = funding_r
          let close () = Lazy_deferred.force_exn closed
        end : Md.Feed.S)
    }
;;

let create ?on_raw config ~symbols ~streams =
  let%map t = start ?on_raw config ~symbols ~streams in
  feed t
;;
