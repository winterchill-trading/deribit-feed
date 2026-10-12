open! Core

let streams = Market_data.Stream.[ Trades; Bbo; L2; Funding ]
let data_dir = "fixtures"
let date = Date.of_string "2026-10-12"

let path stream =
  sprintf
    "%s/raw/deribit/%s/BTC-PERPETUAL/2026/10/12/16-54.ndjson"
    data_dir
    (Market_data.Stream.to_string stream)
;;

let lines stream =
  In_channel.read_lines (path stream)
  |> List.map ~f:(fun line -> Market_data.Raw_minute.Line.parse line |> Or_error.ok_exn)
;;
