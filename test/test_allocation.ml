(* Minor words allocated per Live_feed message: what [Normalizer.frame] (JSON decode plus
   conversion, the work [Live_feed] does per websocket frame) allocates on the recorded
   mainnet minute. Counts are compared with {!Tolerance.near}; the timing benchmark is in
   bench/. *)

open! Core
open Deribit_feed

let words f =
  let before = Gc.minor_words () in
  f ();
  Gc.minor_words () - before
;;

(* Expected words per frame and the largest frame's words, per stream. The L2 maximum is
   the full-depth snapshot. *)
let expected : Market_data.Stream.t -> int * int = function
  | Trades -> 1780, 6974
  | Bbo -> 378, 380
  | L2 -> 8623, 193130
  | Funding -> 771, 809
  | Private -> 0, 0
;;

let%expect_test "minor words per Live_feed message" =
  List.iter Fixture.streams ~f:(fun stream ->
    let t = Normalizer.create () in
    let per_frame =
      List.filter_map (Fixture.lines stream) ~f:(function
        | Disconnect -> None
        | Frame { recv_ts; payload } ->
          Some
            ( words (fun () ->
                ignore
                  (Sys.opaque_identity (Normalizer.frame t ~recv_ts payload)
                   : Normalizer.Output.t list Or_error.t))
            , String.length payload ))
    in
    let n = List.length per_frame in
    let total = List.sum (module Int) per_frame ~f:fst in
    let bytes = List.sum (module Int) per_frame ~f:snd in
    let max = List.fold per_frame ~init:0 ~f:(fun acc (w, _) -> Int.max acc w) in
    let expected_per_frame, expected_max = expected stream in
    print_s
      [%message
        ""
          (stream : Market_data.Stream.t)
          ~frames:(n : int)
          ~words_per_frame:
            (Tolerance.near ~expected:expected_per_frame (total / n) : Sexp.t)
          ~max_words:(Tolerance.near ~expected:expected_max max : Sexp.t)
          ~bytes_per_frame:(bytes / n : int)]);
  [%expect
    {|
    ((stream Trades) (frames 20) (words_per_frame ~1780) (max_words ~6974)
     (bytes_per_frame 1660))
    ((stream Bbo) (frames 200) (words_per_frame ~378) (max_words ~380)
     (bytes_per_frame 252))
    ((stream L2) (frames 40) (words_per_frame ~8623) (max_words ~193130)
     (bytes_per_frame 2677))
    ((stream Funding) (frames 60) (words_per_frame ~771) (max_words ~809)
     (bytes_per_frame 671))
    |}]
;;
