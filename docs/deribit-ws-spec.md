# Deribit public websocket: the parts this feed uses

Source: docs.deribit.com (API v2, JSON-RPC over websocket), fetched 2026-10-12.
Only public, unauthenticated market data is covered.

## Endpoints

| Environment | URL |
|---|---|
| Mainnet | `wss://www.deribit.com/ws/api/v2` |
| Testnet | `wss://test.deribit.com/ws/api/v2` |

All traffic is JSON-RPC 2.0 text frames. Requests carry an `id`; responses echo it.
Notifications have no `id`, `method` is always `"subscription"`, and `params` holds
`channel` and `data`.

## Subscribing

```json
{"jsonrpc":"2.0","method":"public/subscribe","id":42,
 "params":{"channels":["book.BTC-PERPETUAL.100ms"]}}
```

The response lists the channels actually subscribed:

```json
{"jsonrpc":"2.0","id":42,"result":["book.BTC-PERPETUAL.100ms"],
 "usIn":1728720000000000,"usOut":1728720000000100,"usDiff":100,"testnet":false}
```

Errors come back as `{"jsonrpc":"2.0","id":42,"error":{"code":...,"message":"..."}}`.
`public/unsubscribe` takes the same `params` shape.

Intervals: `raw` (every change, 1 ms aggregation), `100ms`, `agg2` (dynamic, by
default at most once per second). **`raw` requires an authenticated connection**, so
this feed uses `100ms` everywhere.

## Channels

### Trades: `trades.{instrument_name}.{interval}`

`data` is an array of trades:

```json
{"jsonrpc":"2.0","method":"subscription","params":{
 "channel":"trades.BTC-PERPETUAL.100ms",
 "data":[{"trade_seq":30289442,"trade_id":"48079269","timestamp":1590484512188,
          "tick_direction":2,"price":8950,"mark_price":8948.9,
          "instrument_name":"BTC-PERPETUAL","index_price":8955.88,
          "direction":"sell","amount":10,"contracts":1}]}}
```

- `direction` is the taker side (`buy`/`sell`).
- `trade_id` is a string; `trade_seq` is a per-instrument sequence number.
- `amount` is in USD for perpetuals and futures (contracts of 10 USD on BTC), in coin for
  options.
- Optional fields: `liquidation` (`"M"`, `"T"`, `"MT"`), `block_trade_id`, `iv`
  (options).

### Best bid/ask: `quote.{instrument_name}`

No interval; one notification per top-of-book change.

```json
{"jsonrpc":"2.0","method":"subscription","params":{
 "channel":"quote.BTC-PERPETUAL",
 "data":{"best_ask_amount":50,"best_ask_price":3996.61,"best_bid_amount":40,
         "best_bid_price":3914.97,"instrument_name":"BTC-PERPETUAL",
         "timestamp":1550658624149}}}
```

An empty side has a `null` (or `0`) price and amount `0`.

### Order book: `book.{instrument_name}.{interval}`

Full depth. The first notification is a snapshot of all price levels, later ones are
incremental:

```json
{"jsonrpc":"2.0","method":"subscription","params":{
 "channel":"book.BTC-PERPETUAL.100ms",
 "data":{"type":"snapshot","timestamp":1554373962454,
         "instrument_name":"BTC-PERPETUAL","change_id":297217,
         "bids":[["new",5042.34,30],["new",5041.94,20]],
         "asks":[["new",5042.64,40],["new",5043.3,40]]}}}

{"jsonrpc":"2.0","method":"subscription","params":{
 "channel":"book.BTC-PERPETUAL.100ms",
 "data":{"type":"change","timestamp":1554373911330,
         "prev_change_id":297217,"change_id":297218,
         "instrument_name":"BTC-PERPETUAL",
         "bids":[["delete",5041.94,0],["change",5042.34,45]],
         "asks":[["new",5043.0,10]]}}}
```

- Each level is `[action, price, amount]`, `action` one of `new`, `change`,
  `delete` (`delete` carries amount `0`).
- `amount` units as for trades (USD for perpetuals).
- Sequencing: every notification carries `change_id`; all but the snapshot also carry
  `prev_change_id`. A change applies only when its `prev_change_id` equals the previous
  notification's `change_id`. Anything else is a gap: discard the book and
  resubscribe (unsubscribe + subscribe), which makes the server send a new snapshot.
- There is no checksum.
- A depth-limited variant `book.{instrument_name}.{group}.{depth}.{interval}` sends
  full snapshots only (no actions); not used here.

### Funding and mark: `ticker.{instrument_name}.{interval}`

```json
{"jsonrpc":"2.0","method":"subscription","params":{
 "channel":"ticker.BTC-PERPETUAL.100ms",
 "data":{"best_ask_amount":100,"best_ask_price":36443,"best_bid_amount":5000,
         "best_bid_price":36442.5,"current_funding":0,
         "estimated_delivery_price":36441.64,"funding_8h":0.0000211,
         "index_price":36441.64,"instrument_name":"BTC-PERPETUAL",
         "interest_value":1.7362511643080387,"last_price":36457.5,
         "mark_price":36446.51,"max_price":36991.72,"min_price":35898.37,
         "open_interest":502097590,"settlement_price":36169.49,"state":"open",
         "stats":{"high":36824.5,"low":35213.5,"price_change":0.7229,
                  "volume":7871.02139035,"volume_usd":284061480},
         "timestamp":1623060194301}}}
```

- `funding_8h` is the funding rate over the last 8 hours, `current_funding` the
  instantaneous rate; both only on perpetuals.
- Deribit funding accrues continuously (every millisecond) and has no discrete payment
  time; there is no "next funding time" field. Realised funding is settled daily at
  08:00 UTC.
- A thinner `perpetual.{instrument_name}.{interval}` channel sends only
  `{interest, index_price, timestamp}`; it has no mark price, so the ticker is used.

## Keepalive

- `public/set_heartbeat` with `{"interval": N}` (seconds, minimum 10) enables
  server heartbeats. The server then sends
  `{"jsonrpc":"2.0","method":"heartbeat","params":{"type":"heartbeat"}}` (informational)
  and `{"jsonrpc":"2.0","method":"heartbeat","params":{"type":"test_request"}}`. A
  `test_request` must be answered with a `public/test` request or the server closes the
  connection at once.
- `public/test` (`{"jsonrpc":"2.0","method":"public/test","id":N}`) answers
  `{"result":{"version":"..."}}` and doubles as an application-level ping.
- Websocket connections have no fixed lifetime.

This feed sends `public/test` as a text ping every 15 s (the replies keep the
venue-net silence watchdog fed), and also enables `public/set_heartbeat` with 30 s and
answers any `test_request` with `public/test`.

## Rate limits

- Public, unauthenticated requests are limited per IP; exceeding the allowance gets
  requests rejected or the connection dropped.
- `public/subscribe` has its own credit bucket: cost 3,000 of 30,000 credits, about 3.3
  requests per second sustained, burst of 10. Subscribe to all of a connection's
  channels in one request, and do not resubscribe in a loop.
- A request with no credits left gets error `10028` (`too_many_requests`) and the
  session is terminated.

## Instrument naming

`BTC-PERPETUAL`, `ETH-PERPETUAL`; linear USDC perpetuals are `BTC_USDC-PERPETUAL`;
futures `BTC-27DEC24`; options `BTC-27DEC24-60000-C`. Names are case sensitive.
