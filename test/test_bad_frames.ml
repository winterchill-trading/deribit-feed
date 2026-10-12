open! Core

let check frame =
  let t = Deribit_feed.Normalizer.create () in
  match Deribit_feed.Normalizer.frame t ~recv_ts:Helpers.recv_ts frame with
  | Ok outputs -> printf "ok, %d outputs\n" (List.length outputs)
  | Error error ->
    (* Decoder errors embed source paths; print only the outermost tag. *)
    let text = Error.to_string_hum error in
    print_endline ("error: " ^ List.hd_exn (String.split_lines text))
;;

let%expect_test "bad frames are errors, not exceptions" =
  check "not json";
  check {|[1,2,3]|};
  check
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"trades.BTC-PERPETUAL.100ms"}}|};
  check
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"trades.BTC-PERPETUAL.100ms","data":{"price":1}}}|};
  check
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"trades.BTC-PERPETUAL.100ms","data":[{"trade_seq":1,"trade_id":"1","timestamp":1,"price":1,"amount":10,"direction":"sideways","instrument_name":"BTC-PERPETUAL"}]}}|};
  check
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"book.BTC-PERPETUAL.100ms","data":{"type":"snapshot","instrument_name":"BTC-PERPETUAL","change_id":1,"bids":[["add",1,1]],"asks":[]}}}|};
  check
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"book.BTC-PERPETUAL.100ms","data":{"type":"snapshot","instrument_name":"BTC-PERPETUAL","change_id":1,"bids":[[1,1]],"asks":[]}}}|};
  check
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"deribit_price_index.btc_usd","data":{}}}|};
  check {|{"jsonrpc":"2.0","method":"private/buy","params":{}}|};
  check {|{"jsonrpc":"2.0","id":3,"error":{"message":"Invalid params","code":-32602}}|};
  [%expect
    {|
    error: ("Deribit: invalid JSON"  "Line 1, bytes 0-8:\
    error: "Deribit: not a JSON-RPC message"
    error: "Deribit: subscription without channel or data"
    error: ("Deribit: cannot decode notification data"
    error: ("Deribit trade: unknown direction" sideways)
    error: ("Deribit: cannot decode notification data"
    error: ("Deribit: cannot decode notification data"
    error: ("Deribit: unexpected channel" deribit_price_index.btc_usd)
    error: ("Deribit: unexpected method" private/buy)
    error: ("Deribit: JSON-RPC error" (id (3)) (code (-32602)) "Invalid params")
    |}]
;;

let%expect_test "channel names round trip" =
  List.iter
    [ "trades.BTC-PERPETUAL.100ms"
    ; "quote.ETH-PERPETUAL"
    ; "book.BTC_USDC-PERPETUAL.agg2"
    ; "ticker.BTC-PERPETUAL.100ms"
    ; "deribit_price_index.btc_usd"
    ]
    ~f:(fun s ->
      let channel = Deribit_feed.Wire.Channel.of_string s in
      print_s [%sexp (channel : Deribit_feed.Wire.Channel.t)];
      assert (String.equal s (Deribit_feed.Wire.Channel.to_string channel)));
  [%expect
    {|
    (Trades (instrument BTC-PERPETUAL) (interval 100ms))
    (Quote ETH-PERPETUAL)
    (Book (instrument BTC_USDC-PERPETUAL) (interval agg2))
    (Ticker (instrument BTC-PERPETUAL) (interval 100ms))
    (Other deribit_price_index.btc_usd)
    |}]
;;

let%expect_test "requests" =
  let open Deribit_feed.Wire in
  print_endline
    (subscribe
       ~id:1
       [ Trades { instrument = "BTC-PERPETUAL"; interval = "100ms" }
       ; Quote "BTC-PERPETUAL"
       ]);
  print_endline
    (unsubscribe ~id:2 [ Book { instrument = "BTC-PERPETUAL"; interval = "100ms" } ]);
  print_endline (set_heartbeat ~id:3 ~seconds:30);
  print_endline (test ~id:4);
  [%expect
    {|
    {"jsonrpc":"2.0","id":1,"method":"public/subscribe","params":{"channels":["trades.BTC-PERPETUAL.100ms","quote.BTC-PERPETUAL"]}}
    {"jsonrpc":"2.0","id":2,"method":"public/unsubscribe","params":{"channels":["book.BTC-PERPETUAL.100ms"]}}
    {"jsonrpc":"2.0","id":3,"method":"public/set_heartbeat","params":{"interval":30}}
    {"jsonrpc":"2.0","id":4,"method":"public/test","params":{}}
    |}]
;;
