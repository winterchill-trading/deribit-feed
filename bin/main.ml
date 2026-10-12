(* Prints normalized Deribit market data, e.g.

   deribit-feed feed -symbol BTC-PERPETUAL -streams trades,bbo,l2,funding -count 20 *)

open! Core
open Async
open Deribit_feed

let config_param =
  let%map_open.Command url =
    flag "url" (optional string) ~doc:"URL websocket endpoint (default mainnet)"
  and testnet = flag "testnet" no_arg ~doc:" use wss://test.deribit.com"
  and interval =
    flag
      "interval"
      (optional string)
      ~doc:"I notification interval: 100ms (default), agg2"
  and debug = flag "debug" no_arg ~doc:" log at debug level" in
  if debug then Log.Global.set_level `Debug;
  let url =
    match url, testnet with
    | Some url, _ -> Some (Uri.of_string url)
    | None, true -> Some Config.testnet_url
    | None, false -> None
  in
  Config.create ?url ?interval ()
;;

let feed_command =
  Command.async
    ~summary:"Print normalized market data (Market_data.Event.t sexps)"
    (let%map_open.Command config = config_param
     and symbols =
       flag
         "symbol"
         (one_or_more_as_list string)
         ~doc:"SYMBOL instrument, e.g. BTC-PERPETUAL (repeat or comma-separate)"
     and streams =
       flag
         "streams"
         (optional_with_default
            [ Market_data.Stream.Trades; Bbo ]
            (Arg_type.comma_separated
               ~allow_empty:false
               (Arg_type.create Market_data.Stream.of_string)))
         ~doc:"LIST trades, bbo, l2, funding (default trades,bbo)"
     and count = flag "count" (optional int) ~doc:"N exit after N events"
     and raw = flag "raw" no_arg ~doc:" also print raw frames to stderr" in
     fun () ->
       let symbols = List.concat_map symbols ~f:(String.split ~on:',') in
       let on_raw =
         Option.some_if raw (fun ~stream ~recv_ts:_ frame ->
           Core.eprintf "%s %s\n%!" (Market_data.Stream.to_string stream) frame)
       in
       let%bind feed = Live_feed.create ?on_raw config ~symbols ~streams in
       let module Feed = (val feed : Market_data.Feed.S) in
       let printed = ref 0 in
       let done_ = Ivar.create () in
       let print (event : Market_data.Event.t) =
         if Ivar.is_empty done_
         then (
           print_s [%sexp (event : Market_data.Event.t)];
           incr printed;
           match count with
           | Some count when !printed >= count -> Ivar.fill_if_empty done_ ()
           | _ -> ())
       in
       let iter pipe ~f = Pipe.iter_without_pushback pipe ~f:(fun x -> print (f x)) in
       don't_wait_for
         (let%map () =
            Deferred.all_unit
              [ iter Feed.trades ~f:(fun x -> Market_data.Event.Trade x)
              ; iter Feed.bbo ~f:(fun x -> Market_data.Event.Bbo x)
              ; iter Feed.l2 ~f:(fun x -> Market_data.Event.L2 x)
              ; iter Feed.funding ~f:(fun x -> Market_data.Event.Funding x)
              ]
          in
          Ivar.fill_if_empty done_ ());
       let%bind () = Ivar.read done_ in
       Feed.close ())
;;

let () =
  Command.group ~summary:"Read-only Deribit public market data" [ "feed", feed_command ]
  |> Command_unix.run
;;
