#!/usr/bin/env bash
# The repo-write boundary: what `scripts/test-all.sh` inspects when it claims a suite wrote to the
# live repository, and — equally — what it does not (#7652).
#
# WHY THIS IS A LIB AND NOT FOUR MORE LINES IN THE RUNNER.
#
# The runner's boundary check has always printed `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY`
# while inspecting `git rev-parse HEAD` and `git status --porcelain` and nothing else. Those two
# are blind to the write that motivated the message: on 2026-08-20 a fixture put
# `commit.gpgsign=false` into the SHARED bare-repo config — no HEAD move, no porcelain entry — and
# six commits were then silently created unsigned, across every worktree on the machine, for as
# long as nobody audited signatures. A message that names a cause the run did not measure is an
# AP-021/ADR-166 violation, and it is the same claim-outruns-check defect #7652 is about, sitting
# inside the guard filed to close it.
#
# So the claim has to be RENDERED FROM THE CHECK. `_repo_state` records a manifest of the
# dimensions it actually captured, and `repo_boundary_render_inspected` renders the operator-facing
# "inspected:" list from that manifest — never from a literal list in the runner. A stale copy of
# this lib measuring three dimensions therefore prints a three-dimension claim; it cannot print a
# four-dimension claim over a three-dimension check, which is precisely the failure one layer up
# across this new module seam.
#
# WHY VALUES ARE DIGESTED. This output is operator-facing and gets pasted into issues. A config
# projection that printed values would print `credential.helper` and, in CI, `http.*.extraheader`
# — which is how GitHub Actions injects its token. Digesting every value means there is no
# redaction allowlist that can be incomplete. The salt is per-run because a bare digest of a
# low-entropy value (`credential.helper` ranges over a handful of strings) is dictionary-reversible
# and comparable across logs; the digest only has to be stable WITHIN one before/after pair.
#
# WHOLE-FUNCTION DEGRADE-OPEN. If HEAD is unreadable, `_repo_state` returns non-zero and the caller
# prints an honest "this run is not evidence" NOTE. A per-dimension degrade is representable in the
# manifest — and that is exactly why it is safe: the rendered claim shrinks with it, so a partial
# measurement can never sit beneath a whole-coverage claim.

# Guard against double-sourcing: the runner sources this once, but the SUT sandbox suites build
# runners that may source it again.
if [[ -n "${_REPO_BOUNDARY_LIB_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_REPO_BOUNDARY_LIB_LOADED=1

# Per-run salt. Deliberately NOT derived from anything stable across runs.
: "${REPO_BOUNDARY_SALT:=$(head -c 32 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n')}"
: "${REPO_BOUNDARY_SALT:=fallback-$$-${RANDOM:-0}}"

# Populated by _repo_state. One line per dimension: `<dim>\t<measured|not-measured>`.
_REPO_BOUNDARY_MANIFEST=""

repo_boundary_dimensions() {
  printf 'head\nworktree\nconfig\nrefs\n'
}

# Emits `<dim>\t<status>`, read FROM A SNAPSHOT when one is passed.
#
# The stored form carries a `manifest\t` prefix so that manifest lines and body lines cannot
# collide inside the snapshot: without it `refs\tmeasured` parses as a ref named "measured", which
# produced a phantom DELETED + created FATAL pair on every classify.
#
# Taking the snapshot as an ARGUMENT is not a convenience. Every real caller invokes
# `before="$(_repo_state)"` — a command substitution, i.e. a SUBSHELL — so the global this used to
# read is discarded before the caller can render anything from it, and the rendered claim silently
# degenerated to whichever dimensions happened to survive. That is the same "a subshell ate the
# assignment" defect this branch exists to close, reproduced inside its own fix; it was caught by
# the runner-integration arm and not by reading. The snapshot embeds its own manifest precisely so
# the claim travels with the measurement.
repo_boundary_manifest() { # repo_boundary_manifest [snapshot]
  if [[ $# -gt 0 ]]; then
    printf '%s' "$1" | sed -n 's/^manifest\t//p'
  else
    printf '%s' "$_REPO_BOUNDARY_MANIFEST" | sed -n 's/^manifest\t//p'
  fi
}

_repo_boundary_digest() { # _repo_boundary_digest <value>
  printf '%s\0%s' "$REPO_BOUNDARY_SALT" "${1-}" | sha256sum | cut -c1-16
}

# --- the four dimensions ---------------------------------------------------------------------

_repo_boundary_dim_head() {
  git rev-parse HEAD 2>/dev/null
}

_repo_boundary_dim_worktree() {
  # Digested rather than printed: a porcelain listing of a dirty tree can be hundreds of lines and
  # the boundary only ever compares it for equality.
  local p
  p="$(git status --porcelain 2>/dev/null)" || return 1
  _repo_boundary_digest "$p"
}

_repo_boundary_dim_config() {
  # `--local` in a worktree reads the SHARED config file — which is the file the 2026-08-20 write
  # landed in, and the reason this dimension exists. `--list -z` is NUL-terminated so a value
  # containing newlines cannot forge an entry boundary.
  #
  # Carve-out is exactly ONE key family: `branch.*.vscode-merge-base`, which the VS Code git
  # extension rewrites as the user navigates and which no escape would produce. It is NOT
  # `branch.*`: `branch.<n>.remote` and `.merge` are written as a side effect of `git push -u` and
  # `git checkout -b --track`, so they are the single config trace a `git -C "" checkout -b`
  # escape leaves behind. Cutting the whole family — individually defensible — composes with the
  # refs REPORT class to make that escape invisible in both dimensions at once.
  # Routed through a FILE, never `out="$(git config --list -z)"`. Command substitution strips NUL
  # bytes — bash even warns — so the `-z` framing is destroyed and every entry collapses into one
  # unsplittable blob. The dimension then reports a single constant and goes silently blind to
  # exactly the write it exists to catch. Caught by this lib's own test, not by reading.
  local kv key val tmpf
  tmpf="$(mktemp)" || return 1
  if ! git config --local --list -z >"$tmpf" 2>/dev/null; then rm -f "$tmpf"; return 1; fi
  while IFS= read -r -d '' kv; do
    if [[ "$kv" == *$'\n'* ]]; then
      key="${kv%%$'\n'*}"
      val="${kv#*$'\n'}"
    else
      # A valueless key (`[section]\n\tkey`) is a real, distinguishable state.
      key="$kv"
      val=$'\1valueless'
    fi
    case "$key" in
      *.vscode-merge-base) continue ;;
    esac
    printf '%s\t%s\n' "$key" "$(_repo_boundary_digest "$val")"
  done <"$tmpf" | LC_ALL=C sort
  rm -f "$tmpf"
}

_repo_boundary_dim_refs() {
  # `--heads --tags` excludes `refs/remotes/**` by construction: a fetch is the only thing that
  # writes it and an escape has no reason to.
  #
  # `git show-ref` exits 1 on NO REFS, which is a legitimate empty result rather than a capture
  # failure. Conflating the two would make ref DELETION — the dimension's most destructive
  # outcome — read as not-measured, i.e. fail open exactly where it must fail closed. So rc=1 with
  # empty stdout is measured-and-empty; any other failure is a capture failure.
  local out rc
  out="$(git show-ref --heads --tags 2>/dev/null)"; rc=$?
  if (( rc != 0 )) && [[ -n "$out" ]]; then return 1; fi
  if (( rc > 1 )); then return 1; fi
  printf '%s' "$out" | LC_ALL=C sort
}

# --- the snapshot ------------------------------------------------------------------------------

_repo_state() {
  local head worktree config refs manifest="" body=""
  # HEAD is the liveness probe for the whole function. If it cannot be read there is no repository
  # to have a boundary around, and the caller must degrade to an honest NOTE.
  head="$(_repo_boundary_dim_head)" || { _REPO_BOUNDARY_MANIFEST=""; return 1; }
  [[ -n "$head" ]] || { _REPO_BOUNDARY_MANIFEST=""; return 1; }
  manifest+=$'manifest\thead\tmeasured\n'
  body+="head"$'\t'"$head"$'\n'

  if worktree="$(_repo_boundary_dim_worktree)"; then
    manifest+=$'manifest\tworktree\tmeasured\n'
    body+="worktree"$'\t'"$worktree"$'\n'
  else
    manifest+=$'manifest\tworktree\tnot-measured\n'
  fi

  if config="$(_repo_boundary_dim_config)"; then
    manifest+=$'manifest\tconfig\tmeasured\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      body+="config"$'\t'"$line"$'\n'
    done <<<"$config"
  else
    manifest+=$'manifest\tconfig\tnot-measured\n'
  fi

  if refs="$(_repo_boundary_dim_refs)"; then
    manifest+=$'manifest\trefs\tmeasured\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      body+="refs"$'\t'"$line"$'\n'
    done <<<"$refs"
  else
    manifest+=$'manifest\trefs\tnot-measured\n'
  fi

  _REPO_BOUNDARY_MANIFEST="$manifest"
  # The manifest is emitted INSIDE the snapshot as well as kept in the global: a before/after pair
  # taken across a lib swap must show the dimension set itself changing, not silently compare a
  # four-dimension reading against a three-dimension one.
  printf '%s' "$manifest"
  printf '%s' "$body"
}

# --- harm classification -------------------------------------------------------------------------

_repo_boundary_default_branch() {
  local d
  d="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" && { printf '%s' "${d#origin/}"; return 0; }
  printf 'main'
}

# Branches checked out in a worktree OTHER than this one. A measured read of the ref store via
# `git worktree list`, not a concurrency sniff — which is what disqualified the `${CI:-}` tier.
_repo_boundary_branches_elsewhere() {
  local here line path_ branch
  here="$(git rev-parse --show-toplevel 2>/dev/null)" || here=""
  git worktree list --porcelain 2>/dev/null | {
    path_=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) path_="${line#worktree }" ;;
        "branch "*)
          branch="${line#branch }"
          [[ -n "$here" && "$path_" == "$here" ]] || printf '%s\n' "$branch"
          ;;
      esac
    done
  }
}

# repo_boundary_classify <before> <after>
# Prints zero or more `<SEVERITY>\t<dimension>\t<detail>` lines. Silent when there is no delta.
repo_boundary_classify() {
  local before="${1-}" after="${2-}"
  local bfile afile
  bfile="$(mktemp)" || return 1
  afile="$(mktemp)" || { rm -f "$bfile"; return 1; }
  printf '%s' "$before" > "$bfile"
  printf '%s' "$after"  > "$afile"

  local default_branch elsewhere
  default_branch="$(_repo_boundary_default_branch)"
  elsewhere="$(_repo_boundary_branches_elsewhere)"
  local own_branch; own_branch="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || own_branch=""

  local dim
  for dim in head worktree config; do
    if ! diff -q <(grep "^${dim}"$'\t' "$bfile" || true) <(grep "^${dim}"$'\t' "$afile" || true) >/dev/null; then
      printf 'FATAL\t%s\tthis dimension changed between the first suite and the end of the run\n' "$dim"
    fi
  done

  # Refs are classified per ref, by harm, so a sibling worktree's branch advancing does not carry
  # the same severity as this worktree's own branch moving under it.
  local brefs arefs
  brefs="$(grep "^refs"$'\t' "$bfile" | sed 's/^refs\t//' || true)"
  arefs="$(grep "^refs"$'\t' "$afile" | sed 's/^refs\t//' || true)"
  if [[ "$brefs" != "$arefs" ]]; then
    local ref name bsha asha
    # Deletions first: FATAL unconditionally, including the all-refs-gone case that makes
    # `show-ref` exit 1.
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      name="${ref#* }"
      if ! grep -qF -- " $name" <<<"$arefs"; then
        printf 'FATAL\trefs\t%s was DELETED\n' "$name"
      fi
    done <<<"$brefs"
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      name="${ref#* }"; asha="${ref%% *}"
      bsha="$(grep -F -- " $name" <<<"$brefs" | head -n1 | cut -d' ' -f1)"
      [[ "$bsha" == "$asha" ]] && continue
      case "$name" in
        refs/tags/*)
          printf 'FATAL\trefs\t%s (tag) was created or moved\n' "$name" ;;
        "$own_branch")
          printf 'FATAL\trefs\t%s is this worktree'"'"'s checked-out branch and it moved\n' "$name" ;;
        "refs/heads/$default_branch")
          printf 'FATAL\trefs\t%s is the default branch and it moved\n' "$name" ;;
        *)
          if [[ -n "$elsewhere" ]] && grep -qxF -- "$name" <<<"$elsewhere"; then
            printf 'REPORT\trefs\t%s is checked out in another worktree; created or moved\n' "$name"
          else
            # Fail closed: a local head this run had no business touching.
            printf 'FATAL\trefs\t%s was created or moved\n' "$name"
          fi ;;
      esac
    done <<<"$arefs"
  fi

  rm -f "$bfile" "$afile"
}

# --- the rendered claim --------------------------------------------------------------------------

_repo_boundary_dim_prose() {
  case "$1" in
    head)     printf 'HEAD' ;;
    worktree) printf "this worktree's tree and index" ;;
    config)   printf "local (shared) config, except branch.*.vscode-merge-base" ;;
    refs)     printf 'local heads and tags, by harm class' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# The operator-facing "inspected:" list, rendered FROM THE MANIFEST. This is the whole point of the
# manifest: the claim cannot outrun the check, because it is generated by it.
repo_boundary_render_inspected() { # repo_boundary_render_inspected [snapshot]
  local dim status
  while IFS=$'\t' read -r dim status; do
    [[ -n "$dim" ]] || continue
    [[ "$status" == "measured" ]] || continue
    printf '          - %s\n' "$(_repo_boundary_dim_prose "$dim")"
  done <<<"$(repo_boundary_manifest "$@")"
}

repo_boundary_render_not_inspected() { # repo_boundary_render_not_inspected [snapshot]
  local dim status
  # A dimension the manifest marks not-measured is named HERE rather than silently dropped, so a
  # partial reading is never presented as whole coverage.
  while IFS=$'\t' read -r dim status; do
    [[ -n "$dim" ]] || continue
    [[ "$status" == "not-measured" ]] || continue
    printf '          - %s (COULD NOT BE MEASURED on this run)\n' "$(_repo_boundary_dim_prose "$dim")"
  done <<<"$(repo_boundary_manifest "$@")"
  cat <<'EOF'
          - the content of a push to a remote (though `push -u` leaves a local
            branch.*.remote/.merge artifact, which IS inspected)
          - loose or packed objects with no ref change
          - the contents of .git/hooks (so `lefthook install` does not fire here)
          - branch.*.vscode-merge-base
          - remote-tracking refs (refs/remotes/**)
          - reflogs
          - the relative order of a multivalued config key (the projection sorts, so a
            reordering of repeated http.* or remote.*.fetch entries is invisible)
          - any entry point other than runs of this runner
          - any suite this runner did not start
EOF
}

# Per-dimension next action. The old text offered `git reflog` and `git log origin/main..main` for
# every outcome — HEAD/worktree instructions that say nothing at all about a config flip.
repo_boundary_next_action() {
  case "$1" in
    head)     printf 'git reflog -25   # the commit that moved HEAD is reachable there' ;;
    worktree) printf 'git status && git diff   # UNCOMMITTED work is what is at risk' ;;
    config)   printf 'git config --local --list   # then unset the key named above; it is the SHARED file every worktree inherits' ;;
    refs)     printf 'git show-ref --heads --tags   # compare against git reflog <ref>; a DELETED ref is recoverable from the reflog until gc' ;;
    *)        printf 'git status' ;;
  esac
}
