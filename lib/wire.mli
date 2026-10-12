(** Deribit JSON-RPC websocket messages used by the public feed. Numbers stay as the venue
    sends them (floats, millisecond ints); {!Normalizer} converts them. Records accept
    unknown fields. *)

open! Core

(** A subscription channel name. *)
module Channel : sig
  type t =
    | Trades of
        { instrument : string
        ; interval : string
        } (** [trades.<instrument>.<interval>] *)
    | Quote of string (** [quote.<instrument>] *)
    | Book of
        { instrument : string
        ; interval : string
        } (** [book.<instrument>.<interval>], full depth with change ids *)
    | Ticker of
        { instrument : string
        ; interval : string
        } (** [ticker.<instrument>.<interval>] *)
    | Other of string
  [@@deriving sexp, compare, equal]

  val to_string : t -> string

  (** Inverse of {!to_string}; unknown shapes become [Other]. *)
  val of_string : string -> t
end

module Trade : sig
  type t =
    { trade_seq : int
    ; trade_id : string
    ; timestamp : int (** ms since the epoch *)
    ; price : float
    ; amount : float (** USD for perpetuals and futures *)
    ; direction : string (** taker side, [buy] or [sell] *)
    ; instrument_name : string
    }
  [@@deriving sexp, yojson]
end

module Quote : sig
  type t =
    { instrument_name : string
    ; timestamp : int
    ; best_bid_price : float option (** [null] when the side is empty *)
    ; best_bid_amount : float
    ; best_ask_price : float option
    ; best_ask_amount : float
    }
  [@@deriving sexp, yojson]
end

module Book : sig
  module Action : sig
    type t =
      | New
      | Change
      | Delete
    [@@deriving sexp, compare, equal]
  end

  module Level : sig
    (** [[action, price, amount]] *)
    type t =
      { action : Action.t
      ; price : float
      ; amount : float
      }
    [@@deriving sexp, yojson]
  end

  type t =
    { type_ : string option (** [snapshot] for the first notification, else [change] *)
    ; timestamp : int option
    ; instrument_name : string
    ; change_id : int
    ; prev_change_id : int option (** absent in the snapshot *)
    ; bids : Level.t list
    ; asks : Level.t list
    }
  [@@deriving sexp, yojson]

  val is_snapshot : t -> bool
end

module Ticker : sig
  type t =
    { instrument_name : string
    ; timestamp : int
    ; mark_price : float
    ; index_price : float
    ; funding_8h : float option (** perpetuals only *)
    ; current_funding : float option (** perpetuals only *)
    }
  [@@deriving sexp, yojson]
end

(** One incoming frame. *)
module Message : sig
  type t =
    | Notification of
        { channel : Channel.t
        ; data : Yojson.Safe.t
        } (** [method: "subscription"] *)
    | Heartbeat of string (** [heartbeat] or [test_request] *)
    | Result of
        { id : int option
        ; result : Yojson.Safe.t
        }
    | Rpc_error of
        { id : int option
        ; code : int option
        ; message : string
        }
  [@@deriving sexp_of]

  val of_json : Yojson.Safe.t -> t Or_error.t
  val of_string : string -> t Or_error.t
end

(** Outgoing requests. *)

val subscribe : id:int -> Channel.t list -> string
val unsubscribe : id:int -> Channel.t list -> string
val test : id:int -> string

(** [public/set_heartbeat] with an interval in seconds (at least 10). *)
val set_heartbeat : id:int -> seconds:int -> string
