open! Core

let near ?tolerance ~expected actual =
  let tolerance =
    match tolerance with
    | Some tolerance -> tolerance
    | None -> Int.max 8 (expected * 3 / 100)
  in
  let approx = Sexp.Atom (sprintf "~%d" expected) in
  if abs (actual - expected) <= tolerance
  then approx
  else [%message "" (actual : int) ~expected:(approx : Sexp.t)]
;;
