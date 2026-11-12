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
    umask 077
    printf "synthetic-%s\n" "$1" > "$CODEX_HOME/credential-$1"
    printf "%s\n" "$1" > "$CODEX_HOME/isolation-sentinel"
    git init -q -b "$1" /workspace/repo
    git -C /workspace/repo -c user.name=Lab -c user.email=lab@example.invalid commit -q --allow-empty -m baseline
  ' sh "$worker"
done

# Seed all canaries before probing from any worker so a missing peer file is meaningful.
for worker in codex-a codex-b claude; do
  "${compose[@]}" exec -T "$worker" sh -eu -c '
    test "$(cat "$CODEX_HOME/credential-$1")" = "synthetic-$1"
    for peer in codex-a codex-b claude; do
      [ "$peer" != "$1" ] || continue
      if cat "$CODEX_HOME/credential-$peer" >/dev/null 2>&1; then
        printf "Worker %s could read the canary for %s\n" "$1" "$peer" >&2
        exit 1
      fi
    done
    test ! -S /var/run/docker.sock
    test -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GH_TOKEN:-}${GITHUB_TOKEN:-}"
  ' sh "$worker"
done
printf '%s\n' 'Each worker read its own synthetic credential; peer credentials were inaccessible.'

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

# Rehearse a publisher checking an agent branch against an advanced main.
"${compose[@]}" exec -T codex-a sh -eu -c '
  cd /workspace/repo
  git config user.name Lab
  git config user.email lab@example.invalid

  git switch -qc main
  printf "%s\n" baseline > shared.txt
  git add shared.txt
  git commit -qm "Add shared fixture"

  git worktree add -qb task /workspace/task main
  printf "%s\n" worker > /workspace/task/shared.txt
  git -C /workspace/task commit -qam "Change shared fixture in task"
  task_head=$(git -C /workspace/task rev-parse HEAD)

  printf "%s\n" publisher > shared.txt
  git commit -qam "Advance main independently"
  main_head=$(git rev-parse main)
  git worktree add -q --detach /workspace/review main

  if git -C /workspace/review merge --no-edit task; then
    echo "Expected a merge conflict" >&2
    exit 1
  fi
  test "$(git -C /workspace/review diff --name-only --diff-filter=U)" = shared.txt
  git -C /workspace/review merge --abort
  test -z "$(git -C /workspace/review status --porcelain)"
  test "$(git -C /workspace/review rev-parse HEAD)" = "$main_head"
  test "$(git rev-parse main)" = "$main_head"
  test "$(git rev-parse task)" = "$task_head"
'
printf '%s\n' 'Git conflict detected and aborted in a detached review worktree; main and task refs preserved.'

# Exercise the publishing contract with a disposable, local Git remote.
"${compose[@]}" exec -T codex-a sh -eu -c '
  cd /workspace/repo
  remote=/workspace/publisher.git
  git init -q --bare -b main "$remote"
  git push -q "$remote" main
  main_head=$(git --git-dir="$remote" rev-parse main)

  cat > "$remote/hooks/pre-receive" << "HOOK"
#!/bin/sh
while read -r old new ref; do
  if [ "$ref" = refs/heads/main ]; then
    echo "Protected branch: main" >&2
    exit 1
  fi
done
HOOK
  chmod +x "$remote/hooks/pre-receive"

  # Use a fast-forward candidate so Git reaches the remote protection hook.
  git branch direct-main-attempt main
  git worktree add -q /workspace/direct-main-attempt direct-main-attempt
  git -C /workspace/direct-main-attempt commit -qm "Simulate direct update" --allow-empty
  if result=$(git push "$remote" direct-main-attempt:refs/heads/main 2>&1); then
    echo "Direct push to main unexpectedly succeeded" >&2
    exit 1
  fi
  printf "%s\n" "$result" | grep -F "Protected branch: main" >/dev/null

  git push -q "$remote" task:refs/heads/task
  test "$(git --git-dir="$remote" rev-parse main)" = "$main_head"
  test "$(git --git-dir="$remote" rev-parse task)" = "$(git rev-parse task)"
'
printf '%s\n' 'Local publisher rejected a direct main push and accepted the task branch.'
