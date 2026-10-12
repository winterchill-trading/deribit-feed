open! Core
open Helpers

let%expect_test "trades" =
  let t = Deribit_feed.Normalizer.create () in
  feed
    t
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"trades.BTC-PERPETUAL.100ms","data":[{"trade_seq":30289442,"trade_id":"48079269","timestamp":1590484512188,"tick_direction":2,"price":8950,"mark_price":8948.9,"instrument_name":"BTC-PERPETUAL","index_price":8955.88,"direction":"sell","amount":10,"contracts":1},{"trade_seq":30289443,"trade_id":"48079270","timestamp":1590484513004,"tick_direction":0,"price":8960.5,"mark_price":8948.9,"instrument_name":"BTC-PERPETUAL","index_price":8955.88,"direction":"buy","amount":20,"contracts":2,"liquidation":"T"}]}}|};
  [%expect
    {|
    trade deribit:BTC-PERPETUAL 2020-05-26T09:15:12.188000000Z Sell 8950 x 10 id=48079269
    trade deribit:BTC-PERPETUAL 2020-05-26T09:15:13.004000000Z Buy 8960.5 x 20 id=48079270
    |}]
;;

let%expect_test "quote" =
  let t = Deribit_feed.Normalizer.create () in
  feed
    t
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"quote.BTC-PERPETUAL","data":{"best_ask_amount":50,"best_ask_price":3996.61,"best_bid_amount":40,"best_bid_price":3914.97,"instrument_name":"BTC-PERPETUAL","timestamp":1550658624149}}}|};
  (* An empty side gives nothing. *)
  feed
    t
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"quote.BTC-PERPETUAL","data":{"best_ask_amount":0,"best_ask_price":null,"best_bid_amount":40,"best_bid_price":3914.97,"instrument_name":"BTC-PERPETUAL","timestamp":1550658624149}}}|};
  [%expect
    {|
    bbo deribit:BTC-PERPETUAL 2019-02-20T10:30:24.149000000Z 40 x 3914.97 / 3996.61 x 50
    (nothing)
    |}]
;;

let%expect_test "ticker becomes funding, deduplicated" =
  let t = Deribit_feed.Normalizer.create () in
  let ticker ~mark =
    sprintf
      {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"ticker.BTC-PERPETUAL.100ms","data":{"best_ask_amount":100,"best_ask_price":36443,"best_bid_amount":5000,"best_bid_price":36442.5,"current_funding":0,"estimated_delivery_price":36441.64,"funding_8h":0.0000211,"index_price":36441.64,"instrument_name":"BTC-PERPETUAL","interest_value":1.7362511643080387,"last_price":36457.5,"mark_price":%s,"max_price":36991.72,"min_price":35898.37,"open_interest":502097590,"settlement_price":36169.49,"state":"open","stats":{"high":36824.5,"low":35213.5,"price_change":0.7229,"volume":7871.02139035,"volume_usd":284061480},"timestamp":1623060194301}}}|}
      mark
  in
  feed t (ticker ~mark:"36446.51");
  feed t (ticker ~mark:"36446.51");
  feed t (ticker ~mark:"36447");
  (* A future has no funding. *)
  feed
    t
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"ticker.BTC-27DEC24.100ms","data":{"instrument_name":"BTC-27DEC24","timestamp":1623060194301,"mark_price":37000.5,"index_price":36441.64}}}|};
  [%expect
    {|
    funding deribit:BTC-PERPETUAL 2021-06-07T10:03:14.301000000Z rate=2.11e-05 next=2021-06-07T16:00:00.000000000Z mark=36446.51 index=36441.64
    (nothing)
    funding deribit:BTC-PERPETUAL 2021-06-07T10:03:14.301000000Z rate=2.11e-05 next=2021-06-07T16:00:00.000000000Z mark=36447 index=36441.64
    (nothing)
    |}]
;;

let%expect_test "next funding time" =
  List.iter
    [ "2026-10-12 00:00:00Z"
    ; "2026-10-12 07:59:59.999Z"
    ; "2026-10-12 08:00:00Z"
    ; "2026-10-12 23:30:00Z"
    ]
    ~f:(fun s ->
      let time = Time_ns.of_string_with_utc_offset s in
      printf "%s -> %s\n" s (utc (Deribit_feed.Normalizer.next_funding_time time)));
  [%expect
    {|
    2026-10-12 00:00:00Z -> 2026-10-12T08:00:00.000000000Z
    2026-10-12 07:59:59.999Z -> 2026-10-12T08:00:00.000000000Z
    2026-10-12 08:00:00Z -> 2026-10-12T16:00:00.000000000Z
    2026-10-12 23:30:00Z -> 2026-10-13T00:00:00.000000000Z
    |}]
;;

let%expect_test "heartbeats and responses" =
  let t = Deribit_feed.Normalizer.create () in
  feed t {|{"jsonrpc":"2.0","method":"heartbeat","params":{"type":"test_request"}}|};
  feed t {|{"jsonrpc":"2.0","method":"heartbeat","params":{"type":"heartbeat"}}|};
  feed
    t
    {|{"jsonrpc":"2.0","id":42,"result":["book.BTC-PERPETUAL.100ms"],"usIn":1,"usOut":2,"usDiff":1,"testnet":false}|};
  feed t {|{"jsonrpc":"2.0","id":7,"result":{"version":"1.2.26"}}|};
  [%expect {|
    answer test_request
    (nothing)
    (nothing)
    (nothing)
    |}]
;;
