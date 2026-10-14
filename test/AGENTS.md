# AGENTS.md: deribit-feed/test

Expect and property tests. `fake_ws.ml` is an in-memory websocket; `helpers.ml` is shared
setup. `fixtures/` holds recorded raw minutes, read through `fixture.ml`.
`test_bad_frames.ml` covers malformed input, `test_allocation.ml` pins word counts.

Run: `opam exec --switch 5.2.0+ox -- dune build --root .. @deribit-feed/runtest`.

Rules:
- Copy fixtures with `cp -RL`; dune's sandbox holds them as symlinks.
- Promote only after reading the diff and after a successful `@runtest` build.
- Never print an absolute path in expect output.
- A pinned allocation count changes only with a comment saying why.
