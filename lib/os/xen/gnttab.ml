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

type r (* Grant ref and its memory page *)
type num = int (* Grant ref number *)
type perm = RO |RW

external gnttab_init : unit -> unit = "caml_gnttab_init"
external gnttab_fini : unit -> unit = "caml_gnttab_fini"
external gnttab_new : num -> r = "caml_gnttab_new"
external gnttab_ref : r -> num = "caml_gnttab_ref"
external gnttab_grant_access : r -> int -> bool -> unit = "caml_gnttab_grant_access"
external gnttab_nr_entries : unit -> int = "caml_gnttab_nr_entries"
external gnttab_nr_reserved : unit -> int = "caml_gnttab_reserved"
external gnttab_end_access : r -> unit = "caml_gnttab_end_access"
external gnttab_read : r -> int -> int -> string = "caml_gnttab_read"
external gnttab_write : r -> string -> int -> int -> unit = "caml_gnttab_write"

module Reserved = struct
    let xenstore () = gnttab_new 1
    let console () = gnttab_new 2
end

let free_list = Queue.create ()
let free_list_condition = Lwt_condition.create ()

let put_free_entry r =
    Queue.push r free_list;
    Lwt_condition.signal free_list_condition ()

let rec get_free_entry () =
    match Queue.is_empty free_list with
    | true ->
        Lwt_condition.wait free_list_condition >>
        get_free_entry ()
    | false ->
        return (Queue.pop free_list)

let to_string (r:r) = string_of_int (gnttab_ref r)

let grant_access r domid perm =
    gnttab_grant_access r domid (match perm with RO -> true |RW -> false)

let end_access r =
    gnttab_end_access r

external release_page: r -> Hw_page.t = "caml_gnt_release_page"
external attach_page: Hw_page.t -> r -> unit = "caml_gnt_attach_page"

(* Read/write bytes directly to a grant page *)
let read r off sz = gnttab_read r off sz
let write r buf off sz = gnttab_write r buf off sz

(* Detach a grant into a separate sub-page *)
let detach gnt off len = { Hw_page.page=(release_page gnt); off; len }
(* Attach a subpage to a grant entry *)
let attach sub gnt = attach_page sub.Hw_page.page gnt

let _ =
    Printf.printf "gnttab_init: %d\n%!" (gnttab_nr_entries () - 1);
    for i = gnttab_nr_reserved () to gnttab_nr_entries () - 1 do
        put_free_entry (gnttab_new i);
    done;
    gnttab_init ()
