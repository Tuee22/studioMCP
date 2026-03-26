.PHONY: build test test-integration repl docs validate-dag validate-fixtures cluster-up cluster-down cluster-status cluster-deploy-sidecars cluster-deploy-server

build:
	cabal build all

test:
	cabal test unit-tests

test-integration:
	cabal test integration-tests

repl:
	cabal repl

docs:
	cabal run studiomcp -- validate docs

validate-dag:
	cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml

validate-fixtures:
	cabal run studiomcp -- dag validate-fixtures

cluster-up:
	cabal run studiomcp -- cluster up

cluster-down:
	cabal run studiomcp -- cluster down

cluster-status:
	cabal run studiomcp -- cluster status

cluster-deploy-sidecars:
	cabal run studiomcp -- cluster deploy sidecars

cluster-deploy-server:
	cabal run studiomcp -- cluster deploy server
