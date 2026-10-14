# AGENTS.md: deribit-feed/docs

`deribit-ws-spec.md` records the channel behaviour the code depends on: subscribe
messages, change-id chaining, keepalive and the snapshot shape.

Rules:
- Update it in the same commit as a change to `lib/wire.ml` or `lib/normalizer.ml` that
  depends on a channel fact.
- Record facts from live captures with the capture date.
