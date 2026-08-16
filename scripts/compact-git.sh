#!/usr/bin/env bash
set -Eeuo pipefail

BRANCH="${BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
BLOBLESS="${BLOBLESS:-1}"   # 1 = also omit file blobs until Git actually needs them
ASSUME_YES="${ASSUME_YES:-0}"

MOVED=0
BACKUP_ROOT=""

rollback() {
  rc="${1:-$?}"
  trap - ERR INT TERM
  if (( MOVED == 1 )); then
    printf '\nA step failed; restoring the original .git metadata...\n' >&2
    rm -rf -- "$ROOT/.git"
    if mv -- "$BACKUP_ROOT/.git" "$ROOT/.git"; then
      rmdir -- "$BACKUP_ROOT" 2>/dev/null || true
      printf 'Original .git restored successfully. Working files were not intentionally modified.\n' >&2
    else
      printf 'CRITICAL: automatic rollback failed. Original metadata should still be at: %s/.git\n' "$BACKUP_ROOT" >&2
    fi
  fi
  exit "$rc"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  if (( MOVED == 1 )); then
    rollback 1
  fi
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git is not installed or not in PATH."

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Run this from inside the Git repository you want to compact."
cd "$ROOT"

# This script intentionally supports only an ordinary repository whose metadata
# is the .git directory in its worktree. A linked worktree/submodule commonly
# has a .git *file* instead.
[[ -d .git && ! -L .git ]] || fail ".git is not a normal directory. Refusing to modify a linked worktree, submodule, or separate-git-dir repository."

# Avoid flattening valuable Git state such as conflict stages or an in-progress operation.
if [[ -n "$(git ls-files -u)" ]]; then
  fail "The index contains unresolved conflicts. Resolve/abort them first."
fi

for marker in .git/MERGE_HEAD .git/CHERRY_PICK_HEAD .git/REVERT_HEAD .git/BISECT_LOG .git/rebase-merge .git/rebase-apply .git/sequencer; do
  [[ ! -e "$marker" ]] || fail "A Git operation appears to be in progress ($marker). Finish/abort it first."
done

# Moving the main .git directory would invalidate other linked worktrees.
worktree_count="$(git worktree list --porcelain | grep -c '^worktree ' || true)"
if (( worktree_count > 1 )); then
  fail "This repository has linked worktrees. Remove them first; moving .git would break them."
fi

# Standard initialized submodules store their Git dirs under the superproject's
# .git/modules, so moving that directory would break the submodule worktrees.
submodule_status="$(git submodule status --recursive 2>/dev/null || true)"
if [[ -n "$submodule_status" ]] && grep -Eq '^[ +U]' <<<"$submodule_status"; then
  fail "Initialized submodules detected. Deinitialize them first or handle their Git metadata separately."
fi

sparse="$(git config --bool core.sparseCheckout 2>/dev/null || true)"
[[ "$sparse" != "true" ]] || fail "Sparse checkout is enabled. This script intentionally refuses that case."

# Preserve all configured fetch URLs and explicit push URLs for origin.
mapfile -t REMOTE_URLS < <(git config --get-all "remote.${REMOTE}.url" || true)
((${#REMOTE_URLS[@]} > 0)) || fail "Remote '$REMOTE' does not exist or has no URL."
mapfile -t PUSH_URLS < <(git config --get-all "remote.${REMOTE}.pushurl" || true)

if [[ "$BLOBLESS" == 1 ]]; then
  fetch_help="$(git fetch -h 2>&1 || true)"
  if ! grep -q -- 'object filtering' <<<"$fetch_help"; then
    printf 'WARNING: this Git version does not support partial-clone filtering; using shallow-only mode.\n' >&2
    BLOBLESS=0
  fi
fi

printf 'Repository : %s\n' "$ROOT"
printf 'Remote     : %s (%s)\n' "$REMOTE" "${REMOTE_URLS[0]}"
printf 'Branch     : %s\n' "$BRANCH"
printf 'Mode       : depth=1, single branch, %s\n' "$([[ "$BLOBLESS" == 1 ]] && printf 'blobless partial clone' || printf 'full blobs for current commit')"
printf '\nThe working tree itself will NOT be checked out, reset --hard, cleaned, or deleted.\n'
printf 'The old .git directory will remain as a backup until YOU remove it.\n\n'

if [[ "$ASSUME_YES" != 1 ]]; then
  read -r -p "Type 'compact' to continue: " answer
  [[ "$answer" == "compact" ]] || fail "Cancelled."
fi

PARENT="$(dirname "$ROOT")"
REPO_NAME="$(basename "$ROOT")"
BACKUP_ROOT="$(mktemp -d "$PARENT/.${REPO_NAME}.git-backup.XXXXXX")"
trap 'rollback $?' ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM

mv -- .git "$BACKUP_ROOT/.git"
MOVED=1

# New repository metadata only. No checkout is performed.
git init -q
git symbolic-ref HEAD "refs/heads/$BRANCH"

git remote add --no-tags -t "$BRANCH" "$REMOTE" "${REMOTE_URLS[0]}"
for ((i=1; i<${#REMOTE_URLS[@]}; i++)); do
  git remote set-url --add "$REMOTE" "${REMOTE_URLS[i]}"
done
for url in "${PUSH_URLS[@]}"; do
  git remote set-url --add --push "$REMOTE" "$url"
done

fetch_args=(--depth=1 --no-tags)
if [[ "$BLOBLESS" == 1 ]]; then
  # Mark the remote as a promisor so missing blobs can be fetched lazily later.
  git config "remote.${REMOTE}.promisor" true
  git config "remote.${REMOTE}.partialclonefilter" blob:none
  fetch_args+=(--filter=blob:none)
fi

git fetch "${fetch_args[@]}" "$REMOTE"

git show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH" || \
  fail "Remote branch '$REMOTE/$BRANCH' was not fetched."

# Critical safety property: --mixed updates HEAD + index, NOT working-tree files.
git reset --mixed -q "$REMOTE/$BRANCH"
git branch --set-upstream-to="$REMOTE/$BRANCH" "$BRANCH" >/dev/null

# Basic integrity/config verification. Avoid fsck here for a partial clone because
# deliberately missing blobs are expected.
[[ "$(git rev-parse --is-shallow-repository)" == "true" ]] || fail "Repository did not become shallow as expected."
[[ "$(git symbolic-ref --short HEAD)" == "$BRANCH" ]] || fail "HEAD is not on '$BRANCH'."
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "$REMOTE/$BRANCH")" ]] || fail "Local HEAD does not match '$REMOTE/$BRANCH'."

MOVED=0
trap - ERR INT TERM

printf '\nSuccess. New Git metadata is compact and tracks only %s/%s.\n' "$REMOTE" "$BRANCH"
printf 'Original Git metadata backup:\n  %s/.git\n\n' "$BACKUP_ROOT"
printf 'Current status (your pre-existing working-tree changes remain as changes):\n'
git status --short
printf '\nShallow: %s\n' "$(git rev-parse --is-shallow-repository)"
printf 'Fetch refspec: %s\n' "$(git config --get-all "remote.${REMOTE}.fetch")"
if [[ "$BLOBLESS" == 1 ]]; then
  printf 'Partial-clone filter: %s\n' "$(git config --get "remote.${REMOTE}.partialclonefilter")"
fi
printf '\nAfter you have verified everything, reclaim the old Git-history disk space with:\n'
printf '  rm -rf -- %q\n' "$BACKUP_ROOT"
printf '\nDo NOT run that rm command until you are certain the new repository is working.\n'
