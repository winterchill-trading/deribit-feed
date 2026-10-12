(** A trimmed minute of Deribit mainnet frames per stream, recorded by market-recorder on
    2026-10-12 for [BTC-PERPETUAL] and checked in as raw minute files
    ({!Market_data.Raw_minute}) under [fixtures/raw/deribit/<stream>/BTC-PERPETUAL/...].
    Each file starts with the [public/set_heartbeat] and [public/subscribe] responses; the
    [l2] file then has the book snapshot followed by changes. *)

open! Core

val streams : Market_data.Stream.t list

(** [fixtures], the [data_dir] holding [raw/]. *)
val data_dir : string

val date : Date.t

(** The recorded lines of one stream, in arrival order. *)
val lines : Market_data.Stream.t -> Market_data.Raw_minute.Line.t list
