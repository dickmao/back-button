export EMACS ?= emacs

.DEFAULT_GOAL := compile
SRC := $(shell git ls-files ./*.el)
TESTSRC := $(shell git ls-files test/*.el)

.PHONY: compile
compile:
	$(EMACS) -batch -L . -L test \
          --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(SRC); \
	  (ret=$$? ; rm -f *.elc ; exit $$ret)
	$(EMACS) -batch -L . -L test \
          --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(TESTSRC); \
	  (ret=$$? ; rm -f $(TESTSRC:.el=.elc); exit $$ret)

.PHONY: test
test: compile
	$(EMACS) --batch -L . -L test $(patsubst %.el,-l %,$(notdir $(TESTSRC))) -f ert-run-tests-batch

README.rst: README.in.rst ./back-button.el Makefile
	grep ';;' ./back-button.el \
	    | awk '/;;;\s*Commentary/{within=1;next}/;;;\s*/{within=0}within' \
	    | sed -e 's/^\s*;;\s\?//g' \
	    | ./readme-sed.sh "COMMENTARY" README.in.rst > README.rst

.PHONY: dist-clean
dist-clean:
	rm -rf dist

.PHONY: dist
dist: dist-clean
	mkdir dist
	cp -p $(SRC) dist

.PHONY: install
install: dist
	$(EMACS) -Q --batch -L . --eval "(package-initialize 'no-activate)" \
	  --eval "(add-to-list 'package-archives '(\"shmelpa\" . \"https://shmelpa.commandlinesystems.com/packages/\"))" \
	  --eval "(package-refresh-contents)" \
	  --eval "(ignore-errors (apply (function package-delete) (alist-get (quote back-button) package-alist)))" \
	  --eval "(with-current-buffer (dired \"dist\") \
	            (package-install-from-buffer))"
