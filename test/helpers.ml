open! Core
module Md = Market_data
module Normalizer = Deribit_feed.Normalizer

let recv_ts = Time_ns.of_span_since_epoch (Time_ns.Span.of_int_sec 1_700_000_000)
let utc time = Time_ns.to_string_iso8601_basic time ~zone:Time_float.Zone.utc

let levels (levels : Md.L2_update.Level.t list) =
  List.map levels ~f:(fun { price; size } ->
    sprintf "%s@%s" (Md.Size.to_string size) (Md.Price.to_string price))
  |> String.concat ~sep:" "
;;

let print_event : Md.Event.t -> unit = function
  | Trade t ->
    printf
      "trade %s %s %s %s x %s id=%s\n"
      (Md.Instrument.to_string t.instrument)
      (utc t.exch_ts)
      (Sexp.to_string [%sexp (t.side : Md.Side.t)])
      (Md.Price.to_string t.price)
      (Md.Size.to_string t.size)
      t.trade_id
  | Bbo b ->
    printf
      "bbo %s %s %s x %s / %s x %s\n"
      (Md.Instrument.to_string b.instrument)
      (utc b.exch_ts)
      (Md.Size.to_string b.bid_size)
      (Md.Price.to_string b.bid_price)
      (Md.Price.to_string b.ask_price)
      (Md.Size.to_string b.ask_size)
  | L2 l ->
    printf
      "l2 %s %s %s\n  bids: %s\n  asks: %s\n"
      (Md.Instrument.to_string l.instrument)
      (utc l.exch_ts)
      (Sexp.to_string [%sexp (l.kind : Md.L2_update.Kind.t)])
      (levels l.bids)
      (levels l.asks)
  | Funding f ->
    printf
      "funding %s %s rate=%g next=%s mark=%s index=%s\n"
      (Md.Instrument.to_string f.instrument)
      (utc f.exch_ts)
      f.rate
      (utc f.next_funding_time)
      (Md.Price.to_string f.mark_price)
      (Md.Price.to_string f.index_price)
;;

let print_output : Normalizer.Output.t -> unit = function
  | Event event -> print_event event
  | Resubscribe channel ->
    printf "resubscribe %s\n" (Deribit_feed.Wire.Channel.to_string channel)
  | Answer_test_request -> print_endline "answer test_request"
;;

let feed normalizer frame =
  match Normalizer.frame normalizer ~recv_ts frame with
  | Ok [] -> print_endline "(nothing)"
  | Ok outputs -> List.iter outputs ~f:print_output
  | Error error -> print_s [%sexp "error", (error : Error.t)]
;;
