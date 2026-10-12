open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Channel = struct
  type t =
    | Trades of
        { instrument : string
        ; interval : string
        }
    | Quote of string
    | Book of
        { instrument : string
        ; interval : string
        }
    | Ticker of
        { instrument : string
        ; interval : string
        }
    | Other of string
  [@@deriving sexp, compare, equal]

  let to_string = function
    | Trades { instrument; interval } -> sprintf "trades.%s.%s" instrument interval
    | Quote instrument -> sprintf "quote.%s" instrument
    | Book { instrument; interval } -> sprintf "book.%s.%s" instrument interval
    | Ticker { instrument; interval } -> sprintf "ticker.%s.%s" instrument interval
    | Other s -> s
  ;;

  let of_string s =
    match String.split s ~on:'.' with
    | [ "trades"; instrument; interval ] -> Trades { instrument; interval }
    | [ "quote"; instrument ] -> Quote instrument
    | [ "book"; instrument; interval ] -> Book { instrument; interval }
    | [ "ticker"; instrument; interval ] -> Ticker { instrument; interval }
    | _ -> Other s
  ;;
end

module Trade = struct
  type t =
    { trade_seq : int
    ; trade_id : string
    ; timestamp : int
    ; price : float
    ; amount : float
    ; direction : string
    ; instrument_name : string
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]
end

module Quote = struct
  type t =
    { instrument_name : string
    ; timestamp : int
    ; best_bid_price : float option [@default None]
    ; best_bid_amount : float [@default 0.]
    ; best_ask_price : float option [@default None]
    ; best_ask_amount : float [@default 0.]
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]
end

module Book = struct
  module Action = struct
    type t =
      | New
      | Change
      | Delete
    [@@deriving sexp, compare, equal]

    let to_string = function
      | New -> "new"
      | Change -> "change"
      | Delete -> "delete"
    ;;

    let of_string = function
      | "new" -> New
      | "change" -> Change
      | "delete" -> Delete
      | s -> raise_s [%message "Deribit book: unknown level action" s]
    ;;
  end

  module Level = struct
    type t =
      { action : Action.t
      ; price : float
      ; amount : float
      }
    [@@deriving sexp]

    let t_of_yojson : Yojson.Safe.t -> t = function
      | `List [ `String action; price; amount ] ->
        { action = Action.of_string action
        ; price = float_of_yojson price
        ; amount = float_of_yojson amount
        }
      | json ->
        raise_s
          [%message
            "Deribit book: level is not [action, price, amount]"
              (Yojson.Safe.to_string json)]
    ;;

    let yojson_of_t { action; price; amount } : Yojson.Safe.t =
      `List [ `String (Action.to_string action); `Float price; `Float amount ]
    ;;
  end

  type t =
    { type_ : string option [@key "type"] [@default None]
    ; timestamp : int option [@default None]
    ; instrument_name : string
    ; change_id : int
    ; prev_change_id : int option [@default None]
    ; bids : Level.t list
    ; asks : Level.t list
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]

  let is_snapshot t =
    match t.type_, t.prev_change_id with
    | Some "snapshot", _ -> true
    | Some _, _ -> false
    | None, prev -> Option.is_none prev
  ;;
end

module Ticker = struct
  type t =
    { instrument_name : string
    ; timestamp : int
    ; mark_price : float
    ; index_price : float
    ; funding_8h : float option [@default None]
    ; current_funding : float option [@default None]
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]
end

module Message = struct
  type t =
    | Notification of
        { channel : Channel.t
        ; data : Yojson.Safe.t
        }
    | Heartbeat of string
    | Result of
        { id : int option
        ; result : Yojson.Safe.t
        }
    | Rpc_error of
        { id : int option
        ; code : int option
        ; message : string
        }

  let sexp_of_json json = Sexp.Atom (Yojson.Safe.to_string json)

  let sexp_of_t = function
    | Notification { channel; data } ->
      [%sexp Notification { channel : Channel.t; data = (sexp_of_json data : Sexp.t) }]
    | Heartbeat type_ -> [%sexp Heartbeat (type_ : string)]
    | Result { id; result } ->
      [%sexp Result { id : int option; result = (sexp_of_json result : Sexp.t) }]
    | Rpc_error { id; code; message } ->
      [%sexp Rpc_error { id : int option; code : int option; message : string }]
  ;;

  let member key = function
    | `Assoc fields -> List.Assoc.find fields key ~equal:String.equal
    | _ -> None
  ;;

  let int_member key json =
    match member key json with
    | Some (`Int i) -> Some i
    | _ -> None
  ;;

  let string_member key json =
    match member key json with
    | Some (`String s) -> Some s
    | _ -> None
  ;;

  let of_json json =
    let id = int_member "id" json in
    match member "method" json, member "params" json with
    | Some (`String "subscription"), Some params ->
      (match string_member "channel" params, member "data" params with
       | Some channel, Some data ->
         Ok (Notification { channel = Channel.of_string channel; data })
       | _ -> Or_error.error_s [%message "Deribit: subscription without channel or data"])
    | Some (`String "heartbeat"), params ->
      Ok
        (Heartbeat
           (Option.bind params ~f:(string_member "type")
            |> Option.value ~default:"heartbeat"))
    | Some (`String method_), _ ->
      Or_error.error_s [%message "Deribit: unexpected method" method_]
    | _ ->
      (match member "result" json, member "error" json with
       | Some result, _ -> Ok (Result { id; result })
       | None, Some error ->
         Ok
           (Rpc_error
              { id
              ; code = int_member "code" error
              ; message = string_member "message" error |> Option.value ~default:""
              })
       | None, None -> Or_error.error_s [%message "Deribit: not a JSON-RPC message"])
  ;;

  let of_string s =
    match Yojson.Safe.from_string s with
    | json -> of_json json
    | exception Yojson.Json_error error ->
      Or_error.error_s [%message "Deribit: invalid JSON" error]
  ;;
end

let request ~id ~method_ params =
  Yojson.Safe.to_string
    (`Assoc
      [ "jsonrpc", `String "2.0"
      ; "id", `Int id
      ; "method", `String method_
      ; "params", params
      ])
;;

let channels_params channels =
  `Assoc
    [ "channels", `List (List.map channels ~f:(fun c -> `String (Channel.to_string c))) ]
;;

let subscribe ~id channels =
  request ~id ~method_:"public/subscribe" (channels_params channels)
;;

let unsubscribe ~id channels =
  request ~id ~method_:"public/unsubscribe" (channels_params channels)
;;

let test ~id = request ~id ~method_:"public/test" (`Assoc [])

let set_heartbeat ~id ~seconds =
  request ~id ~method_:"public/set_heartbeat" (`Assoc [ "interval", `Int seconds ])
;;
