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

(* Functions to directly access information from a raw 4K memory page *)

(** Abstract type for a 4K memory page *)
type t

(** Read from a page into a supplied OCaml string (offset / length) 
  * @param src -> srcoff -> dst -> dstoff -> len -> unit 
  *)
external read: t -> int -> string -> int -> int -> unit = "caml_page_read"

(** Read from a string into a supplied page
  * @param dst -> dstoff -> src -> srcoff -> len -> unit 
  *)
external write: string -> int -> t -> int -> int -> unit = "caml_page_write"

(** Read a single character from a 4K page. If the supplied offset is too
    big, it wraps around PAGE_SIZE *)
external get: t -> int -> char = "caml_page_safe_get" "noalloc"

(** Read a single byte from a 4K page, same as previous except return is int *)
external get_byte: t -> int -> int = "caml_page_safe_get" "noalloc"

(* Set a single character *)
external set: t -> int -> char -> unit = "caml_page_safe_set" "noalloc"

(* Set a single byte *)
external set_byte: t -> int -> int -> unit = "caml_page_safe_set" "noalloc"

(* Allocate a new page *)
external alloc: unit -> t = "caml_page_alloc" "noalloc"

(* A sub-page reference, with offset and length into the page *)
type sub = {
    off: int;
    len: int;
    page: t;
}

let alloc_sub () = { off=0; len=0; page=alloc() }

(* A list of sub-page references *)
type extents = sub Lwt_sequence.t

let make () : extents = Lwt_sequence.create ()
let sub page off len = { off=off; len=len; page=page }
let push ext str = ignore(Lwt_sequence.add_r ext str)
let pop ext = Lwt_sequence.take_l ext
let is_empty ext = Lwt_sequence.is_empty ext
