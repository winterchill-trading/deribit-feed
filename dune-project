(lang dune 3.17)

(name deribit-feed)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/deribit-feed))

(package
 (name deribit-feed)
 (synopsis "Read-only public market data feed for Deribit")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  async
  async_ssl
  venue-net
  market-data
  exchange-core
  ppx_jane
  ppx_yojson_conv
  yojson
  uri))
