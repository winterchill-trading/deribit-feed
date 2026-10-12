open! Core

type t = Normalizer.t

let venue = Market_data.Venue.Deribit
let create = Normalizer.create

let frame t ~recv_ts payload =
  Or_error.map
    (Normalizer.frame t ~recv_ts payload)
    ~f:
      (List.filter_map ~f:(fun (output : Normalizer.Output.t) ->
         match output with
         | Event event -> Some event
         | Resubscribe _ | Answer_test_request -> None))
;;

let disconnect = Normalizer.reset
