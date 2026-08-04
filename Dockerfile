FROM golang:1.26 AS builder

WORKDIR /usr/src/bigbox

# pre-copy/cache go.mod for pre-downloading dependencies and only redownloading them in subsequent builds if they change
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -v -o /usr/local/bin/bigbox ./cmd/bigbox

FROM scratch AS export
COPY --from=builder /usr/local/bin/bigbox /bigbox