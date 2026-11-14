.PHONY: build test run lint fmt docker clean

build:
	go build -o bin/gateway ./cmd/gateway

test:
	go test ./...

fmt:
	gofmt -w ./cmd ./internal

vet:
	go vet ./...

run:
	go run ./cmd/gateway

docker:
	docker build -t trackerone/push-gateway:latest .

clean:
	rm -rf bin
