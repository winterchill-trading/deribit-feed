(* Every recorded frame of the fixture minute, decoded and normalized the way [Live_feed]
   does it, one fresh normalizer per stream. *)

open! Core
open Deribit_feed

type counts =
  { frames : int
  ; empty : int (** responses and heartbeats *)
  ; errors : int
  ; trades : int
  ; bbos : int
  ; fundings : int
  ; snapshots : int
  ; deltas : int
  ; resubscribes : int
  ; test_requests : int
  }
[@@deriving sexp_of]

let zero =
  { frames = 0
  ; empty = 0
  ; errors = 0
  ; trades = 0
  ; bbos = 0
  ; fundings = 0
  ; snapshots = 0
  ; deltas = 0
  ; resubscribes = 0
  ; test_requests = 0
  }
;;

let count_output c (output : Normalizer.Output.t) =
  match output with
  | Event (Trade _) -> { c with trades = c.trades + 1 }
  | Event (Bbo _) -> { c with bbos = c.bbos + 1 }
  | Event (Funding _) -> { c with fundings = c.fundings + 1 }
  | Event (L2 { kind = Snapshot; _ }) -> { c with snapshots = c.snapshots + 1 }
  | Event (L2 { kind = Delta; _ }) -> { c with deltas = c.deltas + 1 }
  | Resubscribe _ -> { c with resubscribes = c.resubscribes + 1 }
  | Answer_test_request -> { c with test_requests = c.test_requests + 1 }
;;

let replay stream =
  let t = Normalizer.create () in
  List.fold (Fixture.lines stream) ~init:zero ~f:(fun c line ->
    match line with
    | Disconnect ->
      Normalizer.reset t;
      c
    | Frame { recv_ts; payload } ->
      let c = { c with frames = c.frames + 1 } in
      (match Normalizer.frame t ~recv_ts payload with
       | Error _ -> { c with errors = c.errors + 1 }
       | Ok [] -> { c with empty = c.empty + 1 }
       | Ok outputs -> List.fold outputs ~init:c ~f:count_output))
;;

let%expect_test "every recorded frame decodes" =
  List.iter Fixture.streams ~f:(fun stream ->
    print_s [%message "" (stream : Market_data.Stream.t) ~_:(replay stream : counts)]);
  [%expect
    {|
    ((stream Trades)
     ((frames 20) (empty 3) (errors 0) (trades 98) (bbos 0) (fundings 0)
      (snapshots 0) (deltas 0) (resubscribes 0) (test_requests 0)))
    ((stream Bbo)
     ((frames 200) (empty 2) (errors 0) (trades 0) (bbos 198) (fundings 0)
      (snapshots 0) (deltas 0) (resubscribes 0) (test_requests 0)))
    ((stream L2)
     ((frames 40) (empty 2) (errors 0) (trades 0) (bbos 0) (fundings 0)
      (snapshots 1) (deltas 37) (resubscribes 0) (test_requests 0)))
    ((stream Funding)
     ((frames 60) (empty 24) (errors 0) (trades 0) (bbos 0) (fundings 36)
      (snapshots 0) (deltas 0) (resubscribes 0) (test_requests 0)))
    |}]
;;
