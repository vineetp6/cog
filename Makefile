SHELL := bash

DESTDIR ?=
PREFIX = /usr/local
BINDIR = $(PREFIX)/bin

INSTALL := install -m 0755

GO ?= go
GORELEASER := $(GO) run github.com/goreleaser/goreleaser/v2@latest

PYTHON ?= python
PYTEST := $(PYTHON) -m pytest
PYRIGHT := $(PYTHON) -m pyright
RUFF := $(PYTHON) -m ruff

# If cog's wheel has been prebuilt, it can be specified with the COG_WHEEL
# environment variable and we will not attempt to build it.
ifndef COG_WHEEL
COG_PYTHON_VERSION := $(shell $(PYTHON) -m setuptools_scm 2>/dev/null)
ifndef COG_PYTHON_VERSION
$(error Could not determine a version for cog! Did you `pip install -e '.[dev]'` first?)
endif
COG_WHEEL := dist/cog-$(COG_PYTHON_VERSION)-py3-none-any.whl
endif

COG_GO_SOURCE := $(shell find cmd pkg -type f)
COG_PYTHON_SOURCE := $(shell find python/cog -type f -name '*.py')
COG_EMBEDDED_WHEEL := pkg/dockerfile/embed/$(notdir $(COG_WHEEL))

COG_BINARIES := cog base-image

default: all

.PHONY: all
all: cog

.PHONY: wheel
wheel: $(COG_EMBEDDED_WHEEL)

$(COG_EMBEDDED_WHEEL): $(COG_WHEEL)
	@mkdir -p pkg/dockerfile/embed
	@rm -f pkg/dockerfile/embed/*.whl # there can only be one embedded wheel
	cp $< $@

$(COG_WHEEL): $(COG_PYTHON_SOURCE)
	$(PYTHON) -m build

$(COG_BINARIES): $(COG_GO_SOURCE) $(COG_EMBEDDED_WHEEL)
	$(GORELEASER) build --clean --snapshot --single-target --id $@ --output $@

.PHONY: install
install: $(COG_BINARIES)
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL) $< $(DESTDIR)$(BINDIR)/$<

.PHONY: clean
clean:
	rm -rf build dist pkg/dockerfile/embed
	rm -f $(COG_BINARIES)

.PHONY: test-go
test-go: $(COG_EMBEDDED_WHEEL) | check-fmt vet lint-go
	$(GO) get gotest.tools/gotestsum
	$(GO) run gotest.tools/gotestsum -- -timeout 1200s -parallel 5 ./... $(ARGS)

.PHONY: test-integration
test-integration: $(COG_BINARIES)
	$(MAKE) -C test-integration PATH="$(PWD):$(PATH)" test

.PHONY: test-python
test-python:
	$(PYTEST) -n auto -vv --cov=python/cog  --cov-report term-missing  python/tests $(if $(FILTER),-k "$(FILTER)",)

.PHONY: test
test: test-go test-python test-integration

.PHONY: fmt
fmt:
	$(GO) run golang.org/x/tools/cmd/goimports -w -d .

.PHONY: generate
generate:
	$(GO) generate ./...

.PHONY: vet
vet:
	$(GO) vet ./...

.PHONY: check-fmt
check-fmt:
	$(GO) run golang.org/x/tools/cmd/goimports -d .
	@test -z $$($(GO) run golang.org/x/tools/cmd/goimports -l .)

.PHONY: lint-go
lint-go:
	$(GO) run github.com/golangci/golangci-lint/cmd/golangci-lint run ./...

.PHONY: lint-python
lint-python:
	$(RUFF) check python/cog
	$(RUFF) format --check python
	@$(PYTHON) -c 'import sys; sys.exit("Warning: python >=3.10 is needed (not installed) to pass linting (pyright)") if sys.version_info < (3, 10) else None'
	$(PYRIGHT)

.PHONY: lint
lint: lint-go lint-python

.PHONY: run-docs-server
run-docs-server:
	pip install mkdocs-material
	sed 's/docs\///g' README.md > ./docs/README.md
	cp CONTRIBUTING.md ./docs/
	mkdocs serve
