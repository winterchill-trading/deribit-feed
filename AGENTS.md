# AGENTS.md: deribit-feed

## Purpose

Read-only public market data from Deribit over its JSON-RPC websocket API: trades, best bid
and offer, L2 snapshots and deltas, and perpetual funding, normalized to `Market_data`
records. No API keys and no order entry.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The library `deribit-feed` (module `Deribit_feed`): config, wire, normalizer, live feed, rebuild normalizer (see `lib/AGENTS.md`) |
| `bin/` | The `deribit-feed` command: `feed` and `rebuild-norm` (see `bin/AGENTS.md`) |
| `bench/` | Live and offline benchmarks (see `bench/AGENTS.md`) |
| `test/` | Fixture, fake websocket, bad-frame and allocation tests; `test/fixtures/` holds recorded raw minutes (see `test/AGENTS.md`) |
| `docs/` | `deribit-ws-spec.md`: the channel facts this code relies on (see `docs/AGENTS.md`) |
| `.github/` | CI workflow and the shared obj-magic check (see `.github/AGENTS.md`) |
| `README.md` | Live run, rebuilding event logs, coverage, gaps, symbols |
| `dune-project` | Package metadata; edit this, not the generated `deribit-feed.opam` |

## Build, test

Run from this repository. The workspace root is one level up, so every command takes
`--root ..`.

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @deribit-feed/all
opam exec --switch 5.2.0+ox -- dune build --root .. @deribit-feed/runtest
```

Parallel work with another agent: prefix both with `DUNE_BUILD_DIR=_build-deribit-feed`.

Standalone (outside the workspace): the org opam repository is the target for published
packages (see `../specs/repos/opam-repository.md`). Until a package is there, pin the
siblings from the CI list below in order, then `opam install . --deps-only --with-test`
and `dune build`.

## Conventions

- Format only this repository: `dune build --root .. @deribit-feed/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root.
- Every module has an `.mli`. Consume siblings by public opam name.
- Pure normalization in `Normalizer`; I/O only in `Live_feed`.
- Allocation pins in `test/test_allocation.ml` may differ between macOS arm64 and Linux
  amd64; keep the comment next to each pin current.
- Comments for humans at non-obvious choices (change-id chaining, keepalive timing).

## Dependencies and dependents

Sibling checkouts: `fixed-decimal`, `exchange-core`, `parquet`, `market-data`, `venue-net`.
CI pins them in that order (`.github/workflows/ci.yml`). `../market-recorder` and
`../market-replay` consume the raw format this repository writes.

## CI

`.github/workflows/ci.yml`: checkout, the shared `ox-setup` action (opam switch cache keyed
on the pins), `dune build`, `dune test`, then the reusable obj-magic workflow from
`../infra`. Pushes cancel the running job; push once per finished change.

To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
--exit-status`. Never poll in a loop.

## Pitfalls

- Deribit public channels have no replay. What the server published during a drop is lost,
  so the gap must be written, not inferred later.
- The `raw` interval needs authentication; use `100ms`.
- The L2 book is a full snapshot followed by deltas chained by `prev_change_id`. A broken
  chain means resubscribing that one channel, and the gap names that instrument.
- `public/test` is the keepalive; `public/set_heartbeat` sets the server interval.
- `Ws_client` runs `on_connect` before reading the new connection's first frame, so a gap
  written there always precedes that connection's events.
- Funding accrues continuously and sizes are USD notional, not contract counts. Check the
  unit fields in `../market-data` before encoding a size.

## Where to read more

- `README.md`: live run, rebuilding event logs, tests and benchmark, gaps, symbols.
- `docs/deribit-ws-spec.md`: the channel facts.
- `../specs/repos/deribit-feed.md`: key modules and status.
- `../market-data/`: the `Feed.S`, `Gap` and `Normalizer.S` types.
- `../oxcaml-claude-skills/skills/oxcaml-performance/`: scanner and allocation work.
- `../oxcaml-claude-skills/AGENTS.md`: workspace-wide guide.
- `../oxcaml-claude-skills/GOTCHAS.md`: the feed repositories sections.

## Never do

- Install opam packages that change the compiler or `core`, `base`, `async`, `ppx_jane`
  on the shared `5.2.0+ox` switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
- Publish, tag or release.
- Commit credentials or print secrets.
- Poll CI in loops.
