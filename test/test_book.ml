open! Core
open Helpers

let book ?prev ?(type_ = "change") ~change_id ~bids ~asks () =
  sprintf
    {|{"jsonrpc":"2.0","method":"subscription","params":{"channel":"book.BTC-PERPETUAL.100ms","data":{"type":"%s","timestamp":1554373962454,"instrument_name":"BTC-PERPETUAL",%s"change_id":%d,"bids":[%s],"asks":[%s]}}}|}
    type_
    (match prev with
     | None -> ""
     | Some prev -> sprintf {|"prev_change_id":%d,|} prev)
    change_id
    bids
    asks
;;

let snapshot ~change_id =
  book
    ~type_:"snapshot"
    ~change_id
    ~bids:{|["new",5041.94,20],["new",5042.34,30]|}
    ~asks:{|["new",5043.3,40],["new",5042.64,40]|}
    ()
;;

let%expect_test "snapshot then deltas" =
  let t = Deribit_feed.Normalizer.create () in
  feed t (snapshot ~change_id:297217);
  feed
    t
    (book
       ~prev:297217
       ~change_id:297218
       ~bids:{|["delete",5041.94,0],["change",5042.34,45]|}
       ~asks:{|["new",5043.0,10]|}
       ());
  feed t (book ~prev:297218 ~change_id:297219 ~bids:"" ~asks:{|["delete",5043.0,0]|} ());
  [%expect
    {|
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Snapshot
      bids: 30@5042.34 20@5041.94
      asks: 40@5042.64 40@5043.3
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Delta
      bids: 0@5041.94 45@5042.34
      asks: 10@5043
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Delta
      bids:
      asks: 0@5043
    |}]
;;

let%expect_test "deltas before the snapshot are dropped" =
  let t = Deribit_feed.Normalizer.create () in
  feed t (book ~prev:5 ~change_id:6 ~bids:{|["new",1,1]|} ~asks:"" ());
  feed t (snapshot ~change_id:7);
  feed t (book ~prev:7 ~change_id:8 ~bids:{|["new",5040,1]|} ~asks:"" ());
  [%expect
    {|
    (nothing)
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Snapshot
      bids: 30@5042.34 20@5041.94
      asks: 40@5042.64 40@5043.3
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Delta
      bids: 1@5040
      asks:
    |}]
;;

let%expect_test "a gap resubscribes once, then waits for a new snapshot" =
  let t = Deribit_feed.Normalizer.create () in
  feed t (snapshot ~change_id:100);
  (* 101 was missed. *)
  feed t (book ~prev:101 ~change_id:102 ~bids:{|["new",5040,1]|} ~asks:"" ());
  feed t (book ~prev:102 ~change_id:103 ~bids:{|["new",5039,1]|} ~asks:"" ());
  feed t (snapshot ~change_id:200);
  feed t (book ~prev:200 ~change_id:201 ~bids:{|["new",5040,2]|} ~asks:"" ());
  [%expect
    {|
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Snapshot
      bids: 30@5042.34 20@5041.94
      asks: 40@5042.64 40@5043.3
    resubscribe book.BTC-PERPETUAL.100ms
    (nothing)
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Snapshot
      bids: 30@5042.34 20@5041.94
      asks: 40@5042.64 40@5043.3
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Delta
      bids: 2@5040
      asks:
    |}]
;;

let%expect_test "a change without prev_change_id after a snapshot is a gap" =
  let t = Deribit_feed.Normalizer.create () in
  feed t (snapshot ~change_id:1);
  feed t (book ~change_id:2 ~bids:"" ~asks:"" ());
  [%expect
    {|
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Snapshot
      bids: 30@5042.34 20@5041.94
      asks: 40@5042.64 40@5043.3
    resubscribe book.BTC-PERPETUAL.100ms
    |}]
;;

let%expect_test "reset forgets the book" =
  let t = Deribit_feed.Normalizer.create () in
  feed t (snapshot ~change_id:1);
  Deribit_feed.Normalizer.reset t;
  feed t (book ~prev:1 ~change_id:2 ~bids:"" ~asks:"" ());
  [%expect
    {|
    l2 deribit:BTC-PERPETUAL 2019-04-04T10:32:42.454000000Z Snapshot
      bids: 30@5042.34 20@5041.94
      asks: 40@5042.64 40@5043.3
    (nothing)
    |}]
;;
