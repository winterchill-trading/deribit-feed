# deribit-feed

A read-only public market data feed for [Deribit](https://www.deribit.com), on Async.
It speaks Deribit's JSON-RPC websocket API (no API keys, no order entry) and produces
the venue-neutral records of `market-data` (`Market_data.Feed.t`): trades, best
bid/offer, L2 book snapshots and deltas, and perpetual funding.

Part of the [winterchill-trading](https://github.com/winterchill-trading) OxCaml
ecosystem; built with the Jane Street stack.

- `Deribit_feed.Config`: endpoint (mainnet, testnet or custom) and notification interval.
- `Deribit_feed.Wire`: the JSON-RPC messages and channel names.
- `Deribit_feed.Normalizer`: pure frame -> event conversion with per-instrument book
  sequencing.
- `Deribit_feed.Live_feed.create`: the live `Feed.t`, one socket per stream, reconnects
  and resubscribes. `Live_feed.start` returns a handle whose `stats` count frames,
  parse errors and reconnects; `?time_source` (default the wall clock) stamps `recv_ts`
  and drives keepalives and reconnection backoff, so tests can step a synthetic clock.
- `Deribit_feed.Rebuild_normalizer`: the normalizer as a `Market_data.Normalizer.S`, for
  rebuilding event logs from market-recorder raw minutes.

The protocol notes are in [docs/deribit-ws-spec.md](docs/deribit-ws-spec.md).

## Live run

```
dune exec deribit-feed -- feed -symbol BTC-PERPETUAL -streams trades,bbo,l2,funding -count 20
```

`-raw` also prints each frame to stderr, `-testnet` or `-url` change the endpoint,
`-interval agg2` slows the channels down. Each stream was run against mainnet for 10
seconds on 2026-10-12 (first events shown):

```
$ deribit-feed feed -symbol BTC-PERPETUAL -streams trades
(Trade
 ((instrument ((venue Deribit) (symbol BTC-PERPETUAL)))
  (exch_ts (2026-10-12 13:48:28.136000000+01:00))
  (recv_ts (2026-10-12 13:48:28.214310000+01:00)) (price 82897.5) (size 3000)
  (side Buy) (trade_id 451454304)))

$ deribit-feed feed -symbol BTC-PERPETUAL -streams bbo
(Bbo
 ((instrument ((venue Deribit) (symbol BTC-PERPETUAL)))
  (exch_ts (2026-10-12 13:48:38.006000000+01:00))
  (recv_ts (2026-10-12 13:48:37.992721000+01:00)) (bid_price 82907.5)
  (bid_size 18020) (ask_price 82908) (ask_size 29620)))

$ deribit-feed feed -symbol BTC-PERPETUAL -streams l2
(L2
 ((instrument ((venue Deribit) (symbol BTC-PERPETUAL)))
  (exch_ts (2026-10-12 13:48:47.787000000+01:00))
  (recv_ts (2026-10-12 13:48:48.164927000+01:00)) (kind Snapshot)
  (bids
   (((price 82908) (size 18020)) ((price 82907.5) (size 5930))
    ((price 82907) (size 20720)) ((price 82906) (size 11850))
    ...
(L2
 ((instrument ((venue Deribit) (symbol BTC-PERPETUAL)))
  (exch_ts (2026-10-12 13:48:48.108000000+01:00))
  (recv_ts (2026-10-12 13:48:48.171070000+01:00)) (kind Delta)
  (bids
   (((price 82908) (size 59460)) ((price 82907.5) (size 5930))
    ((price 82907) (size 0)) ((price 82905) (size 0))
    ...

$ deribit-feed feed -symbol BTC-PERPETUAL -streams funding
(Funding
 ((instrument ((venue Deribit) (symbol BTC-PERPETUAL)))
  (exch_ts (2026-10-12 13:48:58.076000000+01:00))
  (recv_ts (2026-10-12 13:48:58.050527000+01:00)) (rate 8.315E-05)
  (next_funding_time (2026-10-12 17:00:00.000000000+01:00))
  (mark_price 82916.24) (index_price 82886.36)))
```

Timestamps print in the local zone (UTC+1 here). In 10 seconds the run produced 28
trades, 100 BBOs, 30 L2 messages and 14 funding records, with no decode errors; a
75-second L2 run applied 226 messages without a sequence gap. A combined run on
`BTC-PERPETUAL,ETH-PERPETUAL` with all four streams also worked.

## Rebuilding event logs

`deribit-feed rebuild-norm -data-dir DIR -out NEW_DIR -date YYYY-MM-DD` is
`Market_data.Rebuild_norm` with `Rebuild_normalizer`: it reads the recorder's
`raw/deribit/<stream>/<symbol>/...` minutes of the day and writes event logs. On the
checked-in fixture minute:

```
$ deribit-feed rebuild-norm -data-dir test/fixtures -out /tmp/norm -date 2026-10-12
((files 4) (frames 320) (disconnects 0) (events 370) (frame_errors 0)
 (first_errors ()) (skipped_files 0) (skipped_venues ()))
```

Over the untrimmed three-minute recording the fixture came from (12 files, 3311 frames,
4 disconnects when the recorder stopped) it wrote 3613 events with no rejected frame.
`Resubscribe` and `test_request` outputs are dropped offline: a resubscribe shows up in a
recording as the fresh snapshot that followed it.

## Tests and benchmark

- `test/fixtures/raw/deribit/<stream>/BTC-PERPETUAL/2026/10/12/16-54.ndjson`: the first
  20 to 200 frames per stream of a market-recorder minute on mainnet (240 KB in all),
  starting with the subscription responses; the `l2` file has the full-depth snapshot
  then 37 changes. `test_fixtures.ml` normalizes every frame (98 trades, 198 BBOs, 1
  snapshot and 37 deltas, 36 funding records, no errors) and `test_rebuild_norm.ml`
  rebuilds them into a temporary directory and reads the event logs back.
- `test_live_feed_stats.ml` runs `Live_feed` against a scripted local websocket server:
  a malformed frame is counted in `stats` and skipped, and a dropped connection is
  re-established on a synthetic clock (none before 0.39 s, reconnected and resubscribed
  by 0.6 s).
- `test_allocation.ml` prints minor words per message through `Tolerance.near`, which
  accepts the larger of 8 words or 3% so macOS and Linux runs agree.
- `bench/main.exe` is a core_bench of `Normalizer.frame` on the fixture frames. On an
  M-series Mac (`-quota 3`):

| Benchmark | Time/run | Minor words/run |
|---|---|---|
| trades (per frame, 1660 bytes avg, several prints) | 15.0 us | 1783 |
| bbo (per frame) | 2.3 us | 381 |
| funding (per ticker frame) | 6.2 us | 775 |
| l2 replay (40 frames incl. a full-depth snapshot) | 1.54 ms | 345 k |

## Coverage

| Stream | Deribit channel | Mapping | Verified live |
|---|---|---|---|
| `trades` | `trades.<symbol>.100ms` | one `Trade` per print; side = taker `direction`, `exch_ts` = `timestamp` | yes |
| `bbo` | `quote.<symbol>` | `Bbo` while both sides are present | yes |
| `l2` | `book.<symbol>.100ms` | `Snapshot` (full depth, best first), then `Delta`s chained by `prev_change_id`; `delete` = size 0 | yes (no gap seen; gap path unit tested) |
| `funding` | `ticker.<symbol>.100ms` | `Funding` with `rate = funding_8h`, on change of rate, mark or index | yes |
| `private` | none | rejected: public data only | n/a |

Keepalive: `public/test` every 15 s (verified live) plus `public/set_heartbeat` 30 s;
`test_request` heartbeats are answered with `public/test` (unit tested; mainnet sent none
while the client pinged on its own).

## Symbols

Deribit's own instrument names, case sensitive: `BTC-PERPETUAL`, `ETH-PERPETUAL`
(inverse, USD margined in coin), `BTC_USDC-PERPETUAL` (linear USDC), futures such as
`BTC-27DEC24`. The instrument is `deribit:<name>`. Options work for `trades`, `bbo` and
`l2`, but their amounts are in coin rather than USD.

## Limitations

- **Sizes are Deribit amounts.** For perpetuals and futures `amount` is in USD (BTC
  contracts are 10 USD), not in coin; `market-data` has no unit field to say so.
- **`next_funding_time` is synthetic.** Deribit funding accrues continuously and has no
  payment time; the feed reports the next 8-hour boundary (00:00, 08:00, 16:00 UTC) so
  that `funding_8h` reads as a rate per interval. `current_funding` (instantaneous) is
  not exposed.
- **100 ms aggregation.** The `raw` interval needs an authenticated connection, so
  trades, book and ticker are 100 ms aggregates (`-interval agg2` for slower).
  `exch_ts` has millisecond resolution; Deribit also sends a nanosecond
  `starbase_timestamp` on trades, which is ignored.
- **No checksum.** Deribit books carry only `change_id`/`prev_change_id`; a mismatch
  unsubscribes and resubscribes the channel, and changes are dropped until the new
  snapshot. After a reconnect the stream's book state is dropped and the server's
  first notification is a fresh snapshot.
- `Bbo` comes from `quote`, which is not sequenced; a side with a `null` price or a zero
  amount gives no record.
- Index-only data (`deribit_price_index.*`), `perpetual.*` (interest only) and the
  grouped `book.<symbol>.<group>.<depth>.<interval>` channel are not used.
- `public/subscribe` is rate limited (about 3 requests per second, burst 10); the feed
  sends one subscribe per stream, so a resubscribe storm across many books could hit
  the limit.

## CI

CI installs the pinned siblings and the opam dependencies through the shared
[ox-setup](https://github.com/winterchill-trading/infra/blob/main/docs/ci.md) action, which
caches the built opam switch between runs.
