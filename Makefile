CWEAVE:=$(shell which cweave)
CTANGLE:=$(shell which ctangle)
TEX:=$(shell which tex)
CC:=$(shell which gcc) -Wall -g
DVIPS:=$(shell which dvips)
MPOST:=$(shell which mpost)
PDFTEX:=$(shell which pdftex)
DVITOTXT:=$(shell which dvitotxt)
TXTTODVI:=$(shell which txttodvi)
SOURCES:=Makefile newsletter.w test.tex newsmac.tex testing \
	letterhead.mp letterhead.tex tags myconfig.vim

all: newsletter.ps newsletter.pdf

test: newsletter
	$(MPOST) letterhead
	$(TEX) test
	$(DVITOTXT) -f test.dvi -i 0 > test.txt
	./newsletter -c ./testing/config -i ./test.txt -o ./test2.txt \
		-t /home/nwp/tfm_files
	$(TXTTODVI) -f ./test2.txt -o ./test2.dvi -repage
	$(DVIPS) test2 -o

newsletter.o: newsletter.c
	$(CC) -c $^ -o $@

newsletter: %: %.o
	$(CC) $^ -o $@ -L/usr/X11R6/lib -lX11

%.tex: %.w
	$(CWEAVE) -bhp $*

%.c: %.w
	$(CTANGLE) -bhp $*

%.dvi: %.tex
	$(TEX) $*

%.ps: %.dvi
	$(DVIPS) $* -o

%.pdf: %.tex
	$(PDFTEX) $*

clean:
	/bin/rm -f $(filter-out $(SOURCES),$(shell /bin/ls))
