(** Where to reach Deribit's public websocket API. No credentials: the feed only uses
    public channels. *)

open! Core

type t =
  { url : Uri.t (** JSON-RPC websocket endpoint, e.g. [wss://www.deribit.com/ws/api/v2] *)
  ; interval : string
  (** notification interval for [trades], [book] and [ticker] channels: [100ms] or [agg2]
      ([raw] needs an authenticated connection) *)
  }

val sexp_of_t : t -> Sexp.t

(** [wss://www.deribit.com/ws/api/v2] *)
val mainnet_url : Uri.t

(** [wss://test.deribit.com/ws/api/v2] *)
val testnet_url : Uri.t

(** [create ()] is mainnet with interval [100ms]; [url] overrides the endpoint, e.g. for
    testnet or a local proxy. *)
val create : ?url:Uri.t -> ?interval:string -> unit -> t

val mainnet : t
val testnet : t
