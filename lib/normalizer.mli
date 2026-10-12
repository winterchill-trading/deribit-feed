(** Converts Deribit websocket frames into {!Market_data} records. Pure apart from
    logging; the Async driver is {!Live_feed}.

    - [trades.*] gives one {!Market_data.Trade.t} per print ([exch_ts] = trade
      [timestamp], side = taker [direction], [trade_id] = Deribit's [trade_id]).
    - [quote.*] gives a {!Market_data.Bbo.t} while both sides are present.
    - [book.*] is sequenced per instrument: a snapshot (re)starts the book and becomes an
      [L2] [Snapshot] (levels sorted best first); a change whose [prev_change_id] is the
      last [change_id] becomes a [Delta] ([delete] levels have size zero). A change before
      any snapshot is dropped. A change that does not join the last one drops the book and
      asks for [Resubscribe]; changes are then dropped until the next snapshot.
    - [ticker.*] gives a {!Market_data.Funding.t} with [rate = funding_8h] whenever the
      rate, mark or index price changes. Deribit funding accrues continuously, so
      [next_funding_time] is the next 8-hour boundary (00:00, 08:00, 16:00 UTC) after
      [exch_ts]. Tickers without [funding_8h] (non-perpetuals) give nothing.

    Amounts are Deribit's: USD for perpetuals and futures. *)

open! Core

module Output : sig
  type t =
    | Event of Market_data.Event.t
    | Resubscribe of Wire.Channel.t (** the book of this channel hit a gap *)
    | Answer_test_request (** the server sent [test_request]; reply with [public/test] *)
  [@@deriving sexp_of]
end

type t

val create : unit -> t

(** Forgets every book and the last funding values, e.g. after a reconnect. *)
val reset : t -> unit

val instrument : string -> Market_data.Instrument.t

(** Decodes one text frame received at [recv_ts]. Responses and informational heartbeats
    give [[]]; JSON-RPC errors, undecodable frames and unknown notifications give [Error]. *)
val frame : t -> recv_ts:Time_ns.t -> string -> Output.t list Or_error.t

val message : t -> recv_ts:Time_ns.t -> Wire.Message.t -> Output.t list Or_error.t

(** The 8-hour funding boundary strictly after [time]. *)
val next_funding_time : Time_ns.t -> Time_ns.t
