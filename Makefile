PREFIX ?= $(HOME)/.local
NAME   := castnix
ROOT   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
DIST   := $(ROOT)/../$(NAME)-$(shell date +%Y%m%d).tar.gz

.PHONY: install uninstall dist test clean

install:
	./install.sh

uninstall:
	./uninstall.sh

dist:
	cd "$(ROOT)/.." && tar -czf "$(DIST)" \
		--exclude='.git' \
		--exclude='doubletake-src/bin' \
		--exclude='*.tar.gz' \
		"$(notdir $(ROOT))"
	@echo "Creado $(DIST)"

test:
	bash -n install.sh
	bash -n uninstall.sh
	bash -n bin/compartir-tv
	bash -n bin/check-tv-share.sh
	cd doubletake-src && go test ./...

clean:
	rm -f "$(DIST)" doubletake-src/bin/doubletake doubletake-src/bin/doubletake-ctl
