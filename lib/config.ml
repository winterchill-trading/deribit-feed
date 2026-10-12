open! Core

type t =
  { url : Uri.t
  ; interval : string
  }

let sexp_of_t { url; interval } =
  [%sexp { url = (Uri.to_string url : string); interval : string }]
;;

let mainnet_url = Uri.of_string "wss://www.deribit.com/ws/api/v2"
let testnet_url = Uri.of_string "wss://test.deribit.com/ws/api/v2"

let create ?(url = mainnet_url) ?(interval = "100ms") () =
  match interval with
  | "100ms" | "agg2" | "raw" -> { url; interval }
  | _ -> raise_s [%message "Deribit_feed.Config: unknown interval" (interval : string)]
;;

let mainnet = create ()
let testnet = create ~url:testnet_url ()
