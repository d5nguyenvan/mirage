ROOTDIR=../../..
include $(ROOTDIR)/mk/ocaml.mk

%.cmx: %.mli %.ml
	$(OCAMLOPT) -c $(OCAMLOPT_ALLFLAGS) $^

TARGET=nettypes
WITH_SYNTAX=yes

include ../../Makefile.common
