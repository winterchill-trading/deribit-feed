(** {!Normalizer} as a {!Market_data.Normalizer.S}, so that [Market_data.Rebuild_norm] can
    rebuild event logs from recorded Deribit raw minutes.

    [frame] keeps only the [Event] outputs: a [Resubscribe] of the live feed shows up in a
    recording as the fresh snapshot that followed it, and [test_request]s need no answer
    offline. [disconnect] is {!Normalizer.reset}. *)

open! Core
include Market_data.Normalizer.S with type t = Normalizer.t
