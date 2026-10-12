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
  and resubscribes.

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
