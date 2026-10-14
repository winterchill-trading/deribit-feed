# AGENTS.md: deribit-feed/lib

The `deribit-feed` library (module `Deribit_feed`).

| Module | Holds |
| --- | --- |
| `Config` | Mainnet, testnet or custom endpoint; notification interval (`100ms` default) |
| `Wire` | JSON-RPC messages and channel names |
| `Normalizer` | Pure frame to event conversion with per-instrument book sequencing |
| `Live_feed` | One socket per stream, keepalive, reconnect and resubscribe, `stats`, `feed_with_gaps`, `?time_source` |
| `Rebuild_normalizer` | `Normalizer` as a `Market_data.Normalizer.S` (several outputs per frame) for `rebuild-norm` |

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @deribit-feed/all`.

Rules:
- `Normalizer` does no I/O; time arrives as `recv_ts`.
- Book chaining uses `prev_change_id`; a break is a gap, never a silent reset.
- Public values carry odoc comments.
