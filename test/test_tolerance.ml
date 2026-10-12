open! Core

let%expect_test "near" =
  List.iter [ 100; 108; 109; 92; 91 ] ~f:(fun actual ->
    print_s (Tolerance.near ~expected:100 actual));
  print_s (Tolerance.near ~expected:10_000 10_250);
  print_s (Tolerance.near ~tolerance:0 ~expected:5 6);
  [%expect
    {|
    ~100
    ~100
    ((actual 109) (expected ~100))
    ~100
    ((actual 91) (expected ~100))
    ~10000
    ((actual 6) (expected ~5))
    |}]
;;
