#!/bin/sh
# Extracted from deploy/marik/smoke.sh. Local Git only; no AO/provider credentials.
set -eu
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ao-worktree-conflict.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
# Discard inherited repository/config context; all writes stay in scratch.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
HOME="$scratch/home"
XDG_CONFIG_HOME="$HOME/.config"
GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=/dev/null
GIT_TERMINAL_PROMPT=0
export HOME XDG_CONFIG_HOME GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_TERMINAL_PROMPT
mkdir -p "$HOME" "$scratch/no-hooks" "$scratch/template"
git init -q --template="$scratch/template" -b main "$scratch/repo"
cd "$scratch/repo"
git config user.name 'Synthetic Test'
git config user.email 'synthetic@example.invalid'
git config commit.gpgsign false
git config core.hooksPath "$scratch/no-hooks"
printf '%s\n' baseline > shared.txt
git add shared.txt
git commit -qm baseline
git worktree add -qb task "$scratch/task" main
printf '%s\n' worker > "$scratch/task/shared.txt"
git -C "$scratch/task" commit -qam task
task_head=$(git rev-parse task)
printf '%s\n' publisher > shared.txt
git commit -qam 'advance main'
main_head=$(git rev-parse main)
git worktree add -q --detach "$scratch/review" main
if git -C "$scratch/review" -c merge.gpgsign=false merge --no-edit task; then
  echo 'FAIL: expected merge conflict' >&2
  exit 1
fi
test "$(git -C "$scratch/review" diff --name-only --diff-filter=U)" = shared.txt
git -C "$scratch/review" merge --abort
test -z "$(git -C "$scratch/review" status --porcelain)"
test "$(git -C "$scratch/review" rev-parse HEAD)" = "$main_head"
test "$(git rev-parse main)" = "$main_head"
test "$(git rev-parse task)" = "$task_head"
test "$(cat shared.txt)" = publisher
test "$(cat "$scratch/task/shared.txt")" = worker
printf '%s\n' 'PASS: detached conflict aborted; main/task refs and files preserved.'
