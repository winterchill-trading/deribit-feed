# AGENTS.md: deribit-feed/bin

The `deribit-feed` command (`main.ml`):

- `feed -symbol SYMS -streams ... [-count N] [-testnet] [-interval I] [-raw]`: live feed.
- `rebuild-norm -data-dir DIR -out NEW_DIR -date YYYY-MM-DD`: rebuilds normalized event logs
  from recorded raw minutes.

Flag details are in `../README.md`.

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @deribit-feed/all`.

Rules:
- Read-only: no code path here may take a key or send a private request.
- `rebuild-norm` writes its output to `-out`.
