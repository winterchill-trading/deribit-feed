open! Core
module Md = Market_data

module Output = struct
  type t =
    | Event of Md.Event.t
    | Resubscribe of Wire.Channel.t
    | Answer_test_request
  [@@deriving sexp_of]
end

module Book_state = struct
  type t =
    | Synced of int (** last applied [change_id] *)
    | Waiting_for_snapshot
end

module Funding_key = struct
  type t =
    { rate : float
    ; mark : Md.Price.t
    ; index : Md.Price.t
    }
  [@@deriving equal]
end

type t =
  { books : Book_state.t String.Table.t
  ; funding : Funding_key.t String.Table.t
  }

let create () = { books = String.Table.create (); funding = String.Table.create () }

let reset t =
  Hashtbl.clear t.books;
  Hashtbl.clear t.funding
;;

let instrument name = Md.Instrument.create Deribit name
let time ms = Time_ns.of_span_since_epoch (Time_ns.Span.of_int_ms ms)

(* Deribit sends prices and amounts as JSON numbers, which the wire types decode as
   floats, so there is no decimal text to parse. *)
let price = (Md.Price.of_float [@alert "-lossy"])
let size = (Md.Size.of_float [@alert "-lossy"])
let funding_interval = Time_ns.Span.of_hr 8.

let next_funding_time time =
  let since_epoch = Time_ns.to_span_since_epoch time in
  let intervals =
    Int63.(
      Time_ns.Span.to_int63_ns since_epoch / Time_ns.Span.to_int63_ns funding_interval)
    |> Int63.to_int_exn
  in
  Time_ns.of_span_since_epoch (Time_ns.Span.scale_int funding_interval (intervals + 1))
;;

let trade ~recv_ts (trade : Wire.Trade.t) =
  let%map.Or_error side =
    match trade.direction with
    | "buy" -> Ok Md.Side.Buy
    | "sell" -> Ok Md.Side.Sell
    | direction ->
      Or_error.error_s [%message "Deribit trade: unknown direction" direction]
  in
  Output.Event
    (Trade
       { instrument = instrument trade.instrument_name
       ; exch_ts = time trade.timestamp
       ; recv_ts
       ; price = price trade.price
       ; size = size trade.amount
       ; side
       ; trade_id = trade.trade_id
       })
;;

let quote ~recv_ts (quote : Wire.Quote.t) : Output.t list =
  match quote.best_bid_price, quote.best_ask_price with
  | Some bid, Some ask
    when Float.(quote.best_bid_amount > 0. && quote.best_ask_amount > 0.) ->
    [ Event
        (Bbo
           { instrument = instrument quote.instrument_name
           ; exch_ts = time quote.timestamp
           ; recv_ts
           ; bid_price = price bid
           ; bid_size = size quote.best_bid_amount
           ; ask_price = price ask
           ; ask_size = size quote.best_ask_amount
           })
    ]
  | _ -> []
;;

let levels (levels : Wire.Book.Level.t list) =
  List.map levels ~f:(fun { action; price = px; amount } : Md.L2_update.Level.t ->
    { price = price px
    ; size =
        (match action with
         | Delete -> Md.Size.zero
         | New | Change -> size amount)
    })
;;

let l2 ~recv_ts ~(kind : Md.L2_update.Kind.t) (book : Wire.Book.t) : Output.t =
  let bids = levels book.bids
  and asks = levels book.asks in
  let bids, asks =
    match kind with
    | Delta -> bids, asks
    | Snapshot ->
      ( List.sort bids ~compare:(fun a b -> Md.Price.compare b.price a.price)
      , List.sort asks ~compare:(fun a b -> Md.Price.compare a.price b.price) )
  in
  Event
    (L2
       { instrument = instrument book.instrument_name
       ; exch_ts = time (Option.value book.timestamp ~default:0)
       ; recv_ts
       ; kind
       ; bids
       ; asks
       })
;;

let book t ~recv_ts ~channel (book : Wire.Book.t) : Output.t list =
  let key = book.instrument_name in
  if Wire.Book.is_snapshot book
  then (
    Hashtbl.set t.books ~key ~data:(Synced book.change_id);
    [ l2 ~recv_ts ~kind:Snapshot book ])
  else (
    match Hashtbl.find t.books key, book.prev_change_id with
    | Some (Synced last), Some prev when last = prev ->
      Hashtbl.set t.books ~key ~data:(Synced book.change_id);
      [ l2 ~recv_ts ~kind:Delta book ]
    | Some (Synced last), prev ->
      Async.Log.Global.info_s
        [%message
          "deribit feed: book gap, resubscribing"
            ~instrument:key
            (last : int)
            (prev : int option)
            ~change_id:(book.change_id : int)];
      Hashtbl.set t.books ~key ~data:Waiting_for_snapshot;
      [ Resubscribe channel ]
    | (None | Some Waiting_for_snapshot), _ -> [])
;;

let ticker t ~recv_ts (ticker : Wire.Ticker.t) : Output.t list =
  match ticker.funding_8h with
  | None -> []
  | Some rate ->
    let key =
      { Funding_key.rate
      ; mark = price ticker.mark_price
      ; index = price ticker.index_price
      }
    in
    (match Hashtbl.find t.funding ticker.instrument_name with
     | Some last when Funding_key.equal last key -> []
     | Some _ | None ->
       Hashtbl.set t.funding ~key:ticker.instrument_name ~data:key;
       let exch_ts = time ticker.timestamp in
       [ Event
           (Funding
              { instrument = instrument ticker.instrument_name
              ; exch_ts
              ; recv_ts
              ; rate
              ; next_funding_time = next_funding_time exch_ts
              ; mark_price = key.mark
              ; index_price = key.index
              })
       ])
;;

let decode of_yojson data =
  Or_error.try_with (fun () -> of_yojson data)
  |> Or_error.tag ~tag:"Deribit: cannot decode notification data"
;;

let notification t ~recv_ts ~(channel : Wire.Channel.t) data =
  match channel with
  | Trades _ ->
    let%bind.Or_error trades =
      decode (Ppx_yojson_conv_lib.Yojson_conv.list_of_yojson Wire.Trade.t_of_yojson) data
    in
    List.map trades ~f:(trade ~recv_ts) |> Or_error.all
  | Quote _ ->
    let%map.Or_error q = decode Wire.Quote.t_of_yojson data in
    quote ~recv_ts q
  | Book _ ->
    let%map.Or_error b = decode Wire.Book.t_of_yojson data in
    book t ~recv_ts ~channel b
  | Ticker _ ->
    let%map.Or_error x = decode Wire.Ticker.t_of_yojson data in
    ticker t ~recv_ts x
  | Other channel -> Or_error.error_s [%message "Deribit: unexpected channel" channel]
;;

let message t ~recv_ts (message : Wire.Message.t) =
  match message with
  | Notification { channel; data } -> notification t ~recv_ts ~channel data
  | Heartbeat "test_request" -> Ok [ Output.Answer_test_request ]
  | Heartbeat _ | Result _ -> Ok []
  | Rpc_error { id; code; message } ->
    Or_error.error_s
      [%message "Deribit: JSON-RPC error" (id : int option) (code : int option) message]
;;

let frame t ~recv_ts frame =
  let%bind.Or_error message' = Wire.Message.of_string frame in
  message t ~recv_ts message'
;;
