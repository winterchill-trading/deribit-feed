(* [Market_data.Rebuild_norm] over the fixture minute with [Rebuild_normalizer], then the
   event logs read back. *)

open! Core
open Async
open Deribit_feed

let with_temp_dir f =
  let%bind dir = Unix.mkdtemp (Filename.temp_dir_name ^/ "deribit-rebuild") in
  Monitor.protect
    (fun () -> f dir)
    ~finally:(fun () ->
      Process.run_expect_no_stdout ~prog:"rm" ~args:[ "-rf"; dir ] () >>| ok_exn)
;;

let%expect_test "rebuild-norm over the fixture minute" =
  with_temp_dir (fun dir ->
    let out_dir = dir ^/ "norm" in
    let%bind stats =
      Market_data.Rebuild_norm.run
        ~normalizers:[ (module Rebuild_normalizer) ]
        ~data_dir:Fixture.data_dir
        ~out_dir
        Fixture.date
    in
    print_s [%sexp (stats : Market_data.Rebuild_norm.Stats.t Or_error.t)];
    let instrument = Normalizer.instrument "BTC-PERPETUAL" in
    let%map () =
      Deferred.List.iter Fixture.streams ~how:`Sequential ~f:(fun stream ->
        let%map events, tail =
          Market_data.Event_log.load_file
            (Market_data.Event_log.path ~dir:out_dir instrument stream Fixture.date)
        in
        let recv_ts = List.map events ~f:Market_data.Event.recv_ts in
        print_s
          [%message
            ""
              (stream : Market_data.Stream.t)
              ~events:(List.length events : int)
              ~in_order:(List.is_sorted recv_ts ~compare:Time_ns.compare : bool)
              (tail : Market_data.Framed.Tail.t)])
    in
    [%expect
      {|
      (Ok
       ((files 4) (frames 320) (disconnects 0) (events 370) (frame_errors 0)
        (first_errors ()) (skipped_files 0) (skipped_venues ())))
      ((stream Trades) (events 98) (in_order true) (tail Clean))
      ((stream Bbo) (events 198) (in_order true) (tail Clean))
      ((stream L2) (events 38) (in_order true) (tail Clean))
      ((stream Funding) (events 36) (in_order true) (tail Clean))
      |}])
;;
