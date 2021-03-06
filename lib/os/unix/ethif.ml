(*
 * Copyright (c) 2010 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Lwt
open Printf

module Tap = struct
  type t = int
  external opendev: string -> t = "tap_opendev"
  external read: t -> Hw_page.t -> int -> int -> int = "tap_read"
  external write: t -> Hw_page.t -> int -> int -> unit = "tap_write"
end

type t = {
  id: string;
  dev: Tap.t;
  rx_cond: unit Lwt_condition.t;
  mutable active: bool;
  mac: string;
}

type id = string

(* We must generate a fake MAC for the Unix "VM", as using the
   tuntap one will cause all sorts of unfortunate MAC routing 
   loops in some stacks (notably Darwin tuntap). *)
let generate_local_mac () =
  let x = String.create 6 in
  let i () = Char.chr (Random.int 256) in
  (* set locally administered and unicast bits *)
  x.[0] <- Char.chr ((((Random.int 256) lor 2) lsr 1) lsl 1);
  x.[1] <- i ();
  x.[2] <- i ();
  x.[3] <- i ();
  x.[4] <- i ();
  x.[5] <- i ();
  x

let create (id:id) =
  let dev = Tap.opendev id in
  let rx_cond = Lwt_condition.create () in
  let mac = generate_local_mac () in
  let active = true in
  let t = { id; dev; rx_cond; active; mac } in
  let cb = fun mask ->
    Lwt_condition.signal rx_cond ();
    t.active
  in
  Activations.register_read dev cb;
  return t

(* Input a frame, and block if nothing is available *)
let rec input t =
  let sub = Hw_page.alloc_sub () in
  let len = Tap.read t.dev sub.Hw_page.page 0 4096 in
  match len with
  | (-1) -> (* EAGAIN or EWOULDBLOCK *)
      Lwt_condition.wait t.rx_cond >>
      input t
  | 0 -> (* EOF *)
      t.active <- false;
      Lwt_condition.wait t.rx_cond >>
      input t
  | n ->
      let sub = { sub with Hw_page.len=len } in
      return sub

(* Loop and listen for packets permanently *)
let rec listen t fn =
  match t.active with
  |true ->
    lwt frame = input t in
    let ft = fn frame in
    listen t fn <&> ft
  |false ->
    return ()

(* Shutdown a netfront *)
let destroy nf =
  printf "tap_destroy\n%!";
  return ()

(* Transmit a packet from a Hw_page, with offset and length 
   For now, just assume the Tap write wont block for long as this
   is not a performance-critical backend
*)
let output t sub =
  Hw_page.(Tap.write t.dev sub.page sub.off sub.len);
  return ()  

(** Return a list of valid VIF IDs *)
let enumerate () =
  return [ "tap0" ]

let wait nf =
  Lwt_condition.wait nf.rx_cond

let mac t =
  t.mac
