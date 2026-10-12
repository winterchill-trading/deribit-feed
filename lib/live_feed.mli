(** A live {!Market_data.Feed.t} over Deribit's public JSON-RPC websocket. Read-only, no
    credentials.

    Each requested stream gets its own connection, so every frame is known to belong to
    one stream before it is parsed. Per stream and symbol the channel is:

    - [Trades]: [trades.<symbol>.<interval>]
    - [Bbo]: [quote.<symbol>]
    - [L2]: [book.<symbol>.<interval>] (full depth, sequenced by [change_id])
    - [Funding]: [ticker.<symbol>.<interval>]

    See {!Normalizer} for the field mapping. All of a connection's channels are subscribed
    with one [public/subscribe] (the method is limited to about 3 requests per second).
    Each connection sends [public/test] every 15 s as a keepalive, enables server
    heartbeats ([public/set_heartbeat], 30 s) and answers [test_request]s.

    [recv_ts] is the time source's [now] when the frame is received; [on_raw] gets the
    frame unparsed, first, including responses and heartbeats. Undecodable frames and
    JSON-RPC errors are logged and skipped.

    On a disconnect the connection is re-established with exponential backoff
    ({!Venue_net.Ws_client}); the stream's book state is dropped and the channels are
    subscribed again, so the book restarts with a fresh [Snapshot]. A book gap
    unsubscribes and resubscribes just that channel.

    Breaks are reported on {!feed_with_gaps}'s [gaps] pipe, always with reason [Resync],
    [venue = Deribit] and the stream set:
    - a reconnect of a stream's connection: [instrument = None] (every symbol of that
      connection), written before any event of the new connection;
    - a book [change_id] break that resubscribes a channel: [instrument] set, written
      before the new snapshot.

    Pipes of streams that were not requested stay empty until [close]. Writes do not wait
    for readers. *)

open! Core
open Async

(** [time_source] (default the wall clock) stamps [recv_ts] and drives the keepalive, the
    silence watchdog and the reconnection backoff, so tests can step them.

    Raises if a first connection fails, or if [streams] contains [Private]. *)
val create
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?time_source:Time_source.t
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> Market_data.Feed.t Deferred.t

(** A running feed with its counters. *)
type t

(** Like {!create}, keeping the handle for {!stats}. *)
val start
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?time_source:Time_source.t
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> t Deferred.t

val feed : t -> Market_data.Feed.t

(** The same feed with its [gaps] pipe (see above). *)
val feed_with_gaps : t -> Market_data.Feed.With_gaps.t

module Stats : sig
  type t =
    { frames : int
    (** websocket text frames received, responses and heartbeats included *)
    ; parse_errors : int
    (** frames that did not decode, JSON-RPC errors and unknown notifications, dropped *)
    ; reconnects : int (** successful reconnections, summed over the connections *)
    }
  [@@deriving sexp_of]
end

val stats : t -> Stats.t

(** The channel subscribed for a stream and symbol. Raises for [Private]. *)
val channel : Config.t -> Market_data.Stream.t -> string -> Wire.Channel.t
