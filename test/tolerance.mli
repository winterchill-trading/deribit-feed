(** Comparing allocation counts in expect tests. Minor-word counts differ by a few words
    between macOS and Linux CI (and between compiler versions), so tests print whether a
    count is near its expected value rather than the count itself. *)

open! Core

(** [near ~expected actual] is [~<expected>] when [actual] is within [tolerance] of
    [expected], else [((actual <actual>) (expected ~<expected>))] so that a failing diff
    shows the new value. [tolerance] defaults to the larger of 8 words and 3% of
    [expected]. *)
val near : ?tolerance:int -> expected:int -> int -> Sexp.t
