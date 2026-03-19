.PHONY: build test test-integration format lint dev repl smoke kind-create kind-delete helm-template

build:
	cabal build all

test:
	./scripts/test.sh

test-integration:
	./scripts/test-integration.sh

format:
	./scripts/format.sh

lint:
	./scripts/lint.sh

dev:
	./scripts/dev.sh

repl:
	cabal repl

kind-create:
	./scripts/kind_create_cluster.sh

kind-delete:
	./scripts/kind_delete_cluster.sh

helm-template:
	./scripts/helm_template.sh

smoke:
	./scripts/smoke-test.sh
