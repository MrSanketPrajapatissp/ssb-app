# syntax=docker/dockerfile:1.7
# ============================================================
# Stage 1: Build
# Uses official Go image pinned to specific tag for reproducibility.
# golang:1.22.3-alpine3.20 — slim builder, no CGO needed.
# ============================================================
FROM golang:1.22.3-alpine3.20 AS builder

# Security: run build as non-root inside the builder stage.
RUN addgroup -g 10001 appgroup && \
    adduser -u 10001 -G appgroup -D -H appuser

WORKDIR /build

# Cache dependency downloads separately from source code changes.
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Copy source and build a statically linked binary.
COPY . .

# Build flags:
#   -trimpath         removes local file paths from binary (security)
#   -ldflags          inject version info; disable DWARF + symbol table (size)
#   CGO_ENABLED=0     pure Go binary, no glibc dependency
#   GOARCH/GOOS       explicit targets (reproducible cross-compile)
ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_TIME=unknown

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -trimpath \
    -ldflags="-s -w \
      -X main.version=${VERSION} \
      -X main.gitCommit=${GIT_COMMIT} \
      -X main.buildTime=${BUILD_TIME}" \
    -o /build/ssb-app \
    .

# ============================================================
# Stage 2: Runtime
# Distroless image — no shell, no package manager, minimal attack surface.
# gcr.io/distroless/static-debian12:nonroot is the smallest safe base.
# ============================================================
FROM gcr.io/distroless/static-debian12:nonroot

# Metadata labels following OCI image spec.
LABEL org.opencontainers.image.title="ssb-app" \
      org.opencontainers.image.description="SSB Digital minimal HTTP service" \
      org.opencontainers.image.vendor="SSB Digital Private Limited" \
      org.opencontainers.image.source="https://github.com/ssb-digital/ssb-app" \
      org.opencontainers.image.licenses="Proprietary"

# nonroot user/group is pre-created in distroless:nonroot (uid=65532).
USER nonroot:nonroot

WORKDIR /app

# Copy only the compiled binary from the builder stage.
COPY --from=builder --chown=nonroot:nonroot /build/ssb-app ./ssb-app

# Service listens on 8080. Non-privileged port — no CAP_NET_BIND_SERVICE needed.
EXPOSE 8080

# Health check — Docker daemon periodically checks /health via -health-check flag.
HEALTHCHECK --interval=10s --timeout=5s --retries=3 --start-period=5s \
    CMD ["/app/ssb-app", "-health-check"]

ENTRYPOINT ["/app/ssb-app"]
