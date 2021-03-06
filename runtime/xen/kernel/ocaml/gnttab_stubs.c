/*
 * Copyright (c) 2010 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2006 Steven Smith <sos22@cam.ac.uk>
 * Copyright (c) 2006 Grzegorz Milos <gm281@cam.ac.uk>
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
 */

#include <mini-os/x86/os.h>
#include <mini-os/mm.h>
#include <mini-os/gnttab.h>

static grant_entry_t *gnttab_table;
static grant_ref_t gnttab_list[NR_GRANT_ENTRIES];

/* Return the size of the grant table */
CAMLprim value
caml_gnttab_nr_entries(value unit)
{
    CAMLparam1(unit);
    CAMLreturn(Val_int(NR_GRANT_ENTRIES));
}

/* Return the number of reserved grant entries at the start */
CAMLprim value
caml_gnttab_reserved(value unit)
{
    CAMLparam1(unit);
    CAMLreturn(Val_int(NR_RESERVED_ENTRIES));
}

static gnttab_wrap *
gnttab_wrap_alloc(grant_ref_t ref)
{
    gnttab_wrap *gw = caml_stat_alloc(sizeof(gnttab_wrap));
    gw->ref = ref;
    gw->page = NULL;
    return gw;
}

static void 
gnttab_finalize(value v_gw)
{
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    printk("gnttab_finalize %d\n", gw->ref);
    if (gw->page != NULL) {
        free_page(gw->page);
        gw->page = NULL;
    }
    free(gw);
}

CAMLprim value
caml_gnttab_new(value v_ref)
{
    CAMLparam1(v_ref);
    CAMLlocal1(v_gw);
    gnttab_wrap *gw;
    //printk("%d\n", Int_val(v_ref));
    v_gw = caml_alloc_final(2, gnttab_finalize, 1, 100);
    Gnttab_wrap_val(v_gw) = NULL;
    gw = gnttab_wrap_alloc(Int_val(v_ref));
    Gnttab_wrap_val(v_gw) = gw;
    CAMLreturn(v_gw);
}

CAMLprim value
caml_gnttab_ref(value v_gw)
{
    CAMLparam1(v_gw);
    CAMLreturn(Val_int(Gnttab_wrap_val(v_gw)->ref));
}

CAMLprim value
caml_gnttab_grant_access(value v_gw, value v_domid, value v_readonly)
{
    CAMLparam3(v_gw, v_domid, v_readonly);
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    if (gw->page == NULL)
       gw->page = (void *)alloc_page();
    //printk("gnttab_grant_access: ref=%d pg=%p domid=%d ro=%d\n", 
     //   gw->ref, gw->page, Int_val(v_domid), Int_val(v_readonly));
    gnttab_table[gw->ref].frame = virt_to_mfn(gw->page);
    gnttab_table[gw->ref].domid = Int_val(v_domid);
    wmb();
    gnttab_table[gw->ref].flags = GTF_permit_access | (Bool_val(v_readonly) * GTF_readonly);
    CAMLreturn(Val_unit);
}

CAMLprim value
caml_gnttab_read(value v_gw, value v_off, value v_size)
{
    CAMLparam3(v_gw, v_off, v_size);
    CAMLlocal1(v_ret);
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    BUG_ON(gw->page == NULL);
    v_ret = caml_alloc_string(Int_val(v_size));
    memcpy(String_val(v_ret), gw->page + Int_val(v_off), Int_val(v_size));
    CAMLreturn(v_ret);
}

CAMLprim value
caml_gnttab_write(value v_gw, value v_str, value v_off, value v_size)
{
    CAMLparam4(v_gw, v_str, v_off, v_size);
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    if (gw->page == NULL)
        gw->page = (void *)alloc_page();
    memcpy(gw->page + Int_val(v_off), String_val(v_str), Int_val(v_size));
    CAMLreturn(Val_unit);
}

CAMLprim value
caml_gnttab_end_access(value v_gw)
{
    CAMLparam1(v_gw);
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    grant_ref_t ref = gw->ref;
    uint16_t flags, nflags;

    BUG_ON(ref >= NR_GRANT_ENTRIES || ref < NR_RESERVED_ENTRIES);

    nflags = gnttab_table[ref].flags;
    do {
        if ((flags = nflags) & (GTF_reading|GTF_writing)) {
            printk("WARNING: g.e. %d still in use! (%x)\n", ref, flags);
            CAMLreturn(Val_unit);
        }
    } while ((nflags = synch_cmpxchg(&gnttab_table[ref].flags, flags, 0)) !=
            flags);

    CAMLreturn(Val_unit);
}


/* Initialise grant tables and map machine frames to a VA */
CAMLprim value
caml_gnttab_init(value unit)
{
    CAMLparam1(unit);
    struct gnttab_setup_table setup;
    unsigned long frames[NR_GRANT_FRAMES];

    setup.dom = DOMID_SELF;
    setup.nr_frames = NR_GRANT_FRAMES;
    set_xen_guest_handle(setup.frame_list, frames);

    HYPERVISOR_grant_table_op(GNTTABOP_setup_table, &setup, 1);
    gnttab_table = map_frames(frames, NR_GRANT_FRAMES);
    printk("gnttab_table mapped at %p\n", gnttab_table);

    CAMLreturn(Val_unit); 
}

/* Disable grant tables */
CAMLprim value
caml_gnttab_fini(value unit)
{
    CAMLparam1(unit);
    struct gnttab_setup_table setup;

    setup.dom = DOMID_SELF;
    setup.nr_frames = 0;

    HYPERVISOR_grant_table_op(GNTTABOP_setup_table, &setup, 1);
    CAMLreturn(Val_unit);
}

/* Generate a Hw_page.t from a grant reference.  Be careful to remove
   any external grants before calling this as it dissociates the
   underlying page from the grant reference structure. */
CAMLprim value
caml_gnt_release_page(value v_gw)
{
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    void *page = gw->page;
    gw->page = NULL;
    if (page == NULL)
        page = (void *)alloc_page();
    return (value)page;
}

/* Attaches a raw page to a grant entry. Panics as a sanity check
   if another page is already part of the grant */
CAMLprim value
caml_gnt_attach_page(value v_page, value v_gw)
{
    gnttab_wrap *gw = Gnttab_wrap_val(v_gw);
    void *page = (void *)v_page;
    BUG_ON(gw->page != NULL);
    gw->page = page;
    return Val_unit;
}

