FROM golang:1.27.4-bookworm@sha256:4fa7c968ba93f1635670522dbb01a2c78150443e1385746924566079f36570ea AS build
WORKDIR /src/backend
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/ao ./cmd/ao

FROM ubuntu:26.04@sha256:065aa8626841f16057b78b027b464cd59c4fac36c204c72dcbf48d66f5fa8a96
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
      ca-certificates git tmux && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home --shell /bin/bash worker \
    && install -d -m 0700 -o worker -g worker /home/worker/.ao /home/worker/.codex /workspace
COPY --from=build /out/ao /usr/local/bin/ao
USER 10001:10001
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/ao"]
CMD ["daemon"]
