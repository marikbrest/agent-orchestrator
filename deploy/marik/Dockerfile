FROM golang:1.27.1-bookworm@sha256:8d48e12ec56735e9358640898b9d9b9fcca110612ed8a5567438c0a1baa24e66 AS build
WORKDIR /src/backend
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/ao ./cmd/ao

FROM debian:13.2-slim@sha256:4bcb9db66237237d03b55b969271728dd3d955eaaa254b9db8a3db94550b1885
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git tmux && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home --shell /bin/bash worker \
    && install -d -m 0700 -o worker -g worker /home/worker/.ao /home/worker/.codex /workspace
COPY --from=build /out/ao /usr/local/bin/ao
USER 10001:10001
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/ao"]
CMD ["daemon"]
