.PHONY: clean

export UID := $(shell id -u)
export GID := $(shell id -g)

clean:
	docker compose --profile keeper-cluster down --remove-orphans
	git clean -fxd data/
	rm -f .env

.env:
	@echo UID=$(UID) > $@
	@echo GID=$(GID) >> $@

reset: clean .env

prepare: .env
