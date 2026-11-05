#!/usr/bin/env bash
set -euo pipefail

project="marik-ao-smoke-$$"
compose=(docker compose -p "$project" -f "$(dirname "$0")/docker-compose.yml" --profile fleet)
trap '"${compose[@]}" down --volumes' EXIT
"${compose[@]}" up -d --wait --wait-timeout 150

for worker in codex-a codex-b claude; do
  container=$("${compose[@]}" ps -q "$worker")
  test "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")" = none
  "${compose[@]}" exec -T "$worker" sh -eu -c '
    test "$(id -u)" = 10001
    test -w "$HOME" && test -w "$CODEX_HOME" && test -w /workspace
    if touch /usr/local/bin/root-write 2>/dev/null; then exit 1; fi
    printf "%s\n" "$1" > "$CODEX_HOME/isolation-sentinel"
    git init -q -b "$1" /workspace/repo
    git -C /workspace/repo -c user.name=Lab -c user.email=lab@example.invalid commit -q --allow-empty -m baseline
  ' sh "$worker"
done

# Stop one host. The other two should keep responding.
"${compose[@]}" stop codex-b
for worker in codex-a claude; do
  "${compose[@]}" exec -T "$worker" ao status --json | grep -E '"state":[[:space:]]*"ready"' >/dev/null
done
"${compose[@]}" up -d --wait --wait-timeout 150 codex-b

for worker in codex-a codex-b claude; do
  "${compose[@]}" exec -T "$worker" sh -eu -c '
    test "$(cat "$CODEX_HOME/isolation-sentinel")" = "$1"
    test "$(git -C /workspace/repo branch --show-current)" = "$1"
  ' sh "$worker"
done
printf '%s\n' 'Three daemons healthy; separate homes and Git repositories survived peer shutdown/restart.'
