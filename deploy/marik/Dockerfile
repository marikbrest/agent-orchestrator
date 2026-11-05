FROM golang:1.27.3-bookworm@sha256:b08bc99468058b6d8a0ada17fa54996b910d5e82a7e95bee0372e3bd98415258 AS build
WORKDIR /src/backend
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/ao ./cmd/ao

FROM debian:13-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git tmux && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home --shell /bin/bash worker \
    && install -d -m 0700 -o worker -g worker /home/worker/.ao /home/worker/.codex /workspace
COPY --from=build /out/ao /usr/local/bin/ao
USER 10001:10001
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/ao"]
CMD ["daemon"]
