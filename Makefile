# Bigbox Go : construction, tests et lint, à lancer sur l'hôte.
# Le binaire n'est JAMAIS exécuté sur l'hôte : uniquement dans la sandbox
# (tools/sandbox/sandbox.sh run --impl go …).

GO       ?= go
BIN_DIR  ?= bin
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT   ?= $(shell git rev-parse --short HEAD 2>/dev/null)
DATE     ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS  := -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(DATE)
GOFLAGS  := -trimpath
PLATFORMS := linux/amd64 linux/arm64

.PHONY: all build build-all test lint fmt tidy clean

all: lint test build

## build : binaire statique linux/amd64 dans bin/bigbox
build:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o $(BIN_DIR)/bigbox ./cmd/bigbox

## build-all : binaires statiques pour toutes les plateformes cibles
build-all:
	@for p in $(PLATFORMS); do \
		os=$${p%/*}; arch=$${p#*/}; \
		echo "→ $$os/$$arch"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch $(GO) build $(GOFLAGS) -ldflags '$(LDFLAGS)' \
			-o $(BIN_DIR)/bigbox-$$os-$$arch ./cmd/bigbox || exit 1; \
	done

## test : tests unitaires (aucun n'exécute apt, systemctl ni sudo)
test:
	$(GO) test -race -count=1 ./...

## lint : golangci-lint (configuration .golangci.yml) et gofmt
lint:
	@test -z "$$(gofmt -l cmd internal features)" || { gofmt -l cmd internal features; echo "gofmt : fichiers à formater"; exit 1; }
	golangci-lint run ./...

fmt:
	gofmt -w cmd internal features

tidy:
	$(GO) mod tidy

clean:
	rm -rf $(BIN_DIR)
