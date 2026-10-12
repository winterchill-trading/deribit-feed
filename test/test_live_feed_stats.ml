(* [Live_feed.stats] with frames pushed by a scripted local websocket server. *)

open! Core
open Async
open Deribit_feed

let trade =
  {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"trades.BTC-PERPETUAL.100ms","data":[{"trade_seq":30289442,"trade_id":"48079269","timestamp":1590484512188,"tick_direction":2,"price":8950,"mark_price":8948.9,"instrument_name":"BTC-PERPETUAL","index_price":8955.88,"direction":"sell","amount":10,"contracts":1}]}}|}
;;

let%expect_test "a malformed frame is counted and skipped" =
  Log.Global.set_output [];
  let%bind server = Fake_ws.start () in
  let%bind live =
    Live_feed.start
      (Fake_ws.config server)
      ~symbols:[ "BTC-PERPETUAL" ]
      ~streams:[ Trades ]
  in
  let module F = (val Live_feed.feed live : Market_data.Feed.S) in
  let%bind (_ : bool) =
    Fake_ws.wait_until (fun () -> List.length (Fake_ws.received server) >= 2)
  in
  List.iter (Fake_ws.received server) ~f:print_endline;
  [%expect
    {|
    {"jsonrpc":"2.0","id":1,"method":"public/set_heartbeat","params":{"interval":30}}
    {"jsonrpc":"2.0","id":2,"method":"public/subscribe","params":{"channels":["trades.BTC-PERPETUAL.100ms"]}}
    |}];
  Fake_ws.send server {|{"jsonrpc":"2.0","id":2,"result":["trades.BTC-PERPETUAL.100ms"]}|};
  Fake_ws.send server {|{"jsonrpc":"2.0","method":"subscription","params":{|};
  Fake_ws.send server trade;
  let%bind trade = Pipe.read F.trades in
  (match trade with
   | `Ok trade -> print_s [%sexp (trade.trade_id : string)]
   | `Eof -> print_endline "eof");
  print_s [%sexp (Live_feed.stats live : Live_feed.Stats.t)];
  [%expect {|
    48079269
    ((frames 3) (parse_errors 1) (reconnects 0))
    |}];
  let%bind () = F.close () in
  Fake_ws.close server
;;
