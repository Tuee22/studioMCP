.PHONY: build test test-integration repl docs validate-dag validate-fixtures cluster-up cluster-down cluster-status cluster-deploy-sidecars cluster-deploy-server

# Build artifacts must stay outside the repository tree.
BUILDDIR := /opt/build/studiomcp

build:
	cabal --builddir=$(BUILDDIR) build all

test:
	cabal --builddir=$(BUILDDIR) test unit-tests

test-integration:
	cabal --builddir=$(BUILDDIR) test integration-tests

repl:
	cabal --builddir=$(BUILDDIR) repl

docs:
	cabal --builddir=$(BUILDDIR) run studiomcp -- validate docs

validate-dag:
	cabal --builddir=$(BUILDDIR) run studiomcp -- validate-dag examples/dags/transcode-basic.yaml

validate-fixtures:
	cabal --builddir=$(BUILDDIR) run studiomcp -- dag validate-fixtures

cluster-up:
	cabal --builddir=$(BUILDDIR) run studiomcp -- cluster up

cluster-down:
	cabal --builddir=$(BUILDDIR) run studiomcp -- cluster down

cluster-status:
	cabal --builddir=$(BUILDDIR) run studiomcp -- cluster status

cluster-deploy-sidecars:
	cabal --builddir=$(BUILDDIR) run studiomcp -- cluster deploy sidecars

cluster-deploy-server:
	cabal --builddir=$(BUILDDIR) run studiomcp -- cluster deploy server
