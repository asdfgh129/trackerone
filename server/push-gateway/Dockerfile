# 推送网关镜像
#
# 构建：docker build -t trackerone/push-gateway:latest .
# 运行：docker run --env-file .env -p 8080:8080 trackerone/push-gateway:latest
FROM golang:1.24-alpine AS builder

WORKDIR /src

# 先拷贝依赖清单，充分利用 Docker 层缓存。
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/gateway ./cmd/gateway

FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl \
    && adduser -D -u 10001 gateway

COPY --from=builder /out/gateway /usr/local/bin/gateway

USER gateway
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/gateway"]
