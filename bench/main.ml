(* Normalizer per frame on the recorded mainnet minute (test/fixtures).

   [trades], [bbo] and [funding] cycle through their recorded frames, one frame per run.
   [l2 replay] is the whole book recording per run: a fresh normalizer, the responses, the
   full-depth snapshot and 37 changes (40 frames). *)

open! Core
open Core_bench
open Deribit_feed

let frames text =
  String.split_lines text
  |> List.filter_map ~f:(fun line ->
    match Market_data.Raw_minute.Line.parse line |> Or_error.ok_exn with
    | Frame { recv_ts; payload } -> Some (recv_ts, payload)
    | Disconnect -> None)
;;

let per_frame name text =
  let frames = Array.of_list (frames text) in
  let t = Normalizer.create () in
  let i = ref 0 in
  Bench.Test.create ~name (fun () ->
    let recv_ts, payload = frames.(!i) in
    i := (!i + 1) % Array.length frames;
    ignore (Normalizer.frame t ~recv_ts payload : Normalizer.Output.t list Or_error.t))
;;

let l2_replay () =
  let frames = frames Frames.l2 in
  Bench.Test.create ~name:"l2 replay" (fun () ->
    let t = Normalizer.create () in
    List.iter frames ~f:(fun (recv_ts, payload) ->
      ignore (Normalizer.frame t ~recv_ts payload : Normalizer.Output.t list Or_error.t)))
;;

let () =
  Command_unix.run
    (Bench.make_command
       [ per_frame "trades" Frames.trades
       ; per_frame "bbo" Frames.bbo
       ; per_frame "funding" Frames.funding
       ; l2_replay ()
       ])
;;
