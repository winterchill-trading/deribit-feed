(** Printing normalizer output with UTC timestamps, so expect output does not depend on
    the machine's time zone. *)

open! Core

val recv_ts : Time_ns.t
val utc : Time_ns.t -> string
val print_output : Deribit_feed.Normalizer.Output.t -> unit

(** Feeds [frame] through [normalizer] and prints each output, or the error. *)
val feed : Deribit_feed.Normalizer.t -> string -> unit
