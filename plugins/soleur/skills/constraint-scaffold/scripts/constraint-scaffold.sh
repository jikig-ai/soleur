#!/usr/bin/env bash
# constraint-scaffold — deterministic generator for the Layer-1 client->server-secret
# import-boundary gate (ADR-071, Option D). Emits a dependency-cruiser config, a
# shared runner, and a CI workflow into the target Next.js app, captures the
# known-violations baseline, PROVES the emitted gate bites on a detached worktree of
# HEAD (pass -> fail -> pass), then appends a README block next to the governed path
# and one pointer line to the repo's agent-instructions file. v1 target =
# apps/web-platform (Next.js-only).
# <!-- Inspired by mattpocock/skills/skills/in-progress/setup-ts-deep-modules/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->
#
# Modes:
#   (default)            detect Next.js -> require app/ components/ server/ -> emit
#                        config + runner + workflows (refuse if any already exists;
#                        NO --force) -> capture baseline -> bite-proof -> README block
#                        + instructions pointer (append-once, written LAST).
#   --refresh-baseline   clean-tree guard, then re-capture the baseline against the
#                        origin/main merge-base (so a same-PR violation is NOT
#                        grandfathered), then bite-proof. Never writes README/pointer.
#                        Agent-only; never shown to the founder.
#   --refresh-stage-a    re-emit ONE file, the Stage A auto-recovery workflow
#                        (fix-constraints-stage-a.yml), when the installed copy is byte-identical
#                        to a historical emission listed in
#                        references/fix-constraints-stage-a.emitted.sha256. Anything else (edited,
#                        unknown version, newer than this plugin's template) is refused with 75
#                        and left untouched. Needs a committed workflow and a clean tree. No
#                        bite-proof: the swap changes none of config, runner or baseline. ADR-071
#                        amendment 2026-11-05. Agent-only; never shown to the founder.
#
# Base ref: origin/main when it exists, else the remote's default branch (origin/HEAD, e.g. a
# founder repo on master). Neither present -> 69 BEFORE anything is written.
#
# Exit matrix (every non-zero is a hard, fail-closed stop; every message is printed on STDOUT
# first — agent runtimes surface stdout and swallow stderr — then on stderr):
#   0   success
#   2   CONSTRAINT_SCAFFOLD_REPO_ROOT override is empty, "/", or relative (refused before any git call)
#   64  usage error (unknown argument)
#   65  precondition failed (target is not a Next.js app, or lacks app/ components/ server/)
#   66  refuse-if-exists (a non-baseline artifact already present; no --force)
#   67  dirty working tree (baseline capture requires a clean tree)
#   68  dependency-cruiser binary missing, or baseline capture failed
#   69  git/base-ref/worktree/temp-dir error, TMPDIR resolves inside the repository, or another
#       scaffold run holds the run lock (<git-common-dir>/constraint-scaffold.lock, owner pid inside;
#       a live owner, or a lock younger than a minute that has no owner pid yet, is held). In
#       --refresh-stage-a also: no sha256 tool, a repository under /proc, /sys or /dev, a failed
#       mktemp/render/chmod/mv, or a digest that is not 64 hex.
#   70  --refresh-baseline / --refresh-stage-a before generation (no .dependency-cruiser.cjs yet, or
#       no fix-constraints-stage-a.yml to refresh — run default mode first)
#   71  bite-proof: gate did not pass on the clean HEAD tree before the probe (config/toolchain)
#   72  bite-proof: gate did NOT reject the injected client->server-secret imports on their edges
#   73  bite-proof: gate did not return to green after the probes were removed
#   74  bite-proof: real client->server-secret violation(s) on HEAD newer than the baseline
#   75  --refresh-stage-a refused, file left byte-unchanged (merge by hand, update the plugin, or fix
#       the named precondition and re-run): the installed workflow is not a known
#       pristine emission (edited, or a version the ledger does not know), is NEWER than this
#       plugin's template (update the plugin; never downgrade), is a symlink or sits behind one,
#       the target has no tracked package-lock.json (the current template installs with `npm ci`), this
#       plugin's ledger lacks its own template's emission, or the file changed during the run.
#
# (--refresh-stage-a has its own, smaller window: it removes only its own temp file
# `.fix-constraints-stage-a.XXXXXX` and its run lock, via the same trap. Only a SIGKILL leaves
# either behind; the recovery is to delete the untracked temp file, never `git add -A`; a stale
# lock clears itself on the next run.)
#
# In default mode the self-cleanup is armed BEFORE the first artifact is written and disarmed
# only after the bite has passed: every failure in between (67..74, a failed `mktemp`, a
# `set -e` abort) REMOVES every artifact this run emitted, so a failed first install is
# re-runnable and never leaves a half-installed gate. The README and the pointer are written
# after the disarm. An INT/TERM mid-run does the same and exits 143; a runner interrupted by a
# terminal Ctrl-C (rc 130) is treated as an interrupt, never as a verdict. Only a SIGKILL can
# leave residue (the six files plus a stale `.git/worktrees` registration) — the 66 message
# names the recovery.
#
# Portable: POSIX tools only (no `realpath -m`, no `sed -i`) — the generator runs on founder hosts
# including stock macOS (bash 3.2, BSD sed). Tool errors (git worktree add, dependency-cruiser)
# are carried into the 68/69 message, never discarded.
#
# No test seams: this script reads no test-only environment variable. The self-tests
# drive every failure arm through a fixture-owned stub `depcruise` reached via the target's
# node_modules symlink (bite-proof.test.sh). CONSTRAINT_SCAFFOLD_REPO_ROOT (below) only
# re-roots the generator at a synthesized repo; it changes no branch of the logic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="$(cd "$SCRIPT_DIR/../references" && pwd)"
# REPO_ROOT defaults to the skill's own repo. CONSTRAINT_SCAFFOLD_REPO_ROOT points
# the generator at a synthesized fixture repo (apps/web-platform-shaped) for the
# hermetic generator self-tests; in normal use it is unset. Templates (REF_DIR)
# always come from the real skill.
REPO_ROOT="${CONSTRAINT_SCAFFOLD_REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
# CONSTRAINT_SCAFFOLD_REPO_ROOT is caller-supplied. The `:-` default is absolute
# (`rev-parse --show-toplevel`), but an override is not, and every `git -C "$REPO_ROOT"` below —
# including a `worktree add`/`worktree remove` pair — would then resolve against CWD instead.
case "$REPO_ROOT" in
  "")            printf 'FATAL: REPO_ROOT is empty; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
  /|//|/.)       printf 'FATAL: REPO_ROOT resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
  /*)            : ;;
  *)             printf 'FATAL: REPO_ROOT %s is RELATIVE; refusing\n' "$REPO_ROOT" >&2; exit 2 ;;
esac
# physdir <dir>: the physical path of an EXISTING directory (`pwd -P`), POSIX — the generator runs
# on founder hosts where `realpath -m` does not exist (BSD/macOS). Prints nothing on a missing dir.
physdir() { ( cd -- "$1" 2>/dev/null && pwd -P ); }
# physpath <path>: physical path of a file that may not exist yet, via its (existing) parent.
physpath() { local d; d="$(physdir "$(dirname -- "$1")")" || return 1; [[ -n "$d" ]] || return 1; printf '%s/%s' "$d" "$(basename -- "$1")"; }
# assert_fixture_dir: the CANONICAL copy (byte-for-byte; fixture-dir-operand-assert.test.sh pins every copy). It refuses an
# empty, relative, `..`-bearing or filesystem-root operand; the stage-a refresh calls it before each write.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
# Canonical form once (a trailing slash would defeat every `${f#"$REPO_ROOT"/}` display and the
# TMPDIR containment case below), re-guarded: the value now comes from a command substitution.
REPO_ROOT="$(physdir "$REPO_ROOT")"
case "$REPO_ROOT" in
  /|//|/.) printf 'FATAL: REPO_ROOT canonicalises to the filesystem root; refusing\n' >&2; exit 2 ;;
  /*)      : ;;
  *)       printf 'FATAL: REPO_ROOT %s did not canonicalise to an absolute path; refusing\n' "$REPO_ROOT" >&2; exit 2 ;;
esac

# v1: the one supported target.
TARGET_REL="apps/web-platform"
TARGET="$REPO_ROOT/$TARGET_REL"

CFG="$TARGET/.dependency-cruiser.cjs"
RUNNER="$TARGET/scripts/constraint-gates.sh"
WORKFLOW="$TARGET/.github/workflows/constraint-gates.yml"
# Two-stage recovery dispatcher (ADR-074, #5814): an UNTRUSTED pull_request producer
# (Stage A) + a PRIVILEGED workflow_run consumer (Stage B). Replaces the single held
# issue_comment dispatcher — the privileged trigger no longer co-locates with untrusted
# PR-code execution.
FIXWORKFLOW_A="$TARGET/.github/workflows/fix-constraints-stage-a.yml"
FIXWORKFLOW_B="$TARGET/.github/workflows/fix-constraints-stage-b.yml"
BASELINE="$TARGET/.dependency-cruiser-known-violations.json"
DEPCRUISE="$TARGET/node_modules/.bin/depcruise"
README="$TARGET/server/README.md"

# The two rules the emitted config defines (bite-proof.test.sh pins these literals equal to
# the `name:` fields of depcruise-config.template) and the four probe paths the bite injects —
# top-level scalars, no array, no `$( )`.
RULE_DIRECT="no-client-to-server-secret"
RULE_TRANSITIVE="no-client-to-server-secret-transitive"
PROBE_DIRECT="components/__constraint_scaffold_bite_probe__/direct.tsx"
PROBE_HOP="components/__constraint_scaffold_bite_probe__/hop.ts"
PROBE_VIA_HOP="components/__constraint_scaffold_bite_probe__/via-hop.tsx"
PROBE_SERVER="server/__constraint_scaffold_bite_probe__.ts"

log()  { printf 'constraint-scaffold: %s\n' "$*" >&2; }
# Agent runtimes surface stdout and swallow stderr, so anything the founder or the agent must
# act on is printed on STDOUT (warn/say) and only then logged. `die` is the ONE failure path:
# every non-zero exit prints `FAILED (<code>): <msg>` on stdout, then the message on stderr.
say()  { printf 'constraint-scaffold: %s\n' "$*"; }
warn() { printf 'constraint-scaffold: WARNING: %s\n' "$*"; }
die()  { say "FAILED (${2:-1}): $1"; log "$1"; exit "${2:-1}"; }
# fail_stdout <code> <msg>: kept as the named form the tests and the header cite; same path.
fail_stdout() { die "$2" "$1"; }

MODE="default"
case "${1:-}" in
  "") MODE="default" ;;
  --refresh-baseline) MODE="refresh" ;;
  --refresh-stage-a) MODE="stage-a" ;;
  *) die "unknown argument: $1 (expected none, --refresh-baseline or --refresh-stage-a)" 64 ;;
esac

# --- Precondition: target is a Next.js app -----------------------------------
detect_nextjs() {
  # next.config.* present AND an anchored "next": dependency key (the anchor
  # avoids matching "next-themes" etc.).
  compgen -G "$TARGET/next.config.*" >/dev/null 2>&1 || return 1
  grep -qE '"next"[[:space:]]*:' "$TARGET/package.json" 2>/dev/null || return 1
}
detect_nextjs || die "target $TARGET_REL is not a Next.js app (need next.config.* + anchored \"next\": in package.json)" 65

# --- Default-mode self-cleanup ------------------------------------------------
# Removes every artifact a default-mode run emits and prints the list it removed. The script
# refuses to start when any of these exists, so at cleanup time each one present was written by
# THIS run. Also `rmdir`s the two `mkdir -p` directories when empty. The list below is pinned by
# bite-proof.test.sh against the refuse-if-exists loop: a new artifact cannot be left behind on a
# failed bite without also being left out of the refuse loop, and vice-versa.
remove_emitted_artifacts() {
  local removed="" f
  for f in "$CFG" "$RUNNER" "$WORKFLOW" "$FIXWORKFLOW_A" "$FIXWORKFLOW_B" "$BASELINE"; do
    [[ -e "$f" ]] || continue
    rm -f -- "$f"
    removed="$removed ${f#"$REPO_ROOT"/}"
  done
  rmdir "$TARGET/scripts" "$TARGET/.github/workflows" "$TARGET/.github" >/dev/null 2>&1 || true
  printf '%s' "${removed# }"
}

# --- Detached-worktree helper (the ONE trap owner, ADR-129) --------------------
# with_detached_worktree <ref> <fn>: creates a mktemp dir, refuses one that resolves inside the
# repository (the worktree and its logs must never land in the founder's tree as untracked
# files), installs the EXIT and INT/TERM traps BEFORE `worktree add --detach`, calls <fn> "$WT",
# removes the worktree, clears the traps. The signal arm clears EXIT inside itself so cleanup
# runs once and exits 143 (the precedent is scripts/rotate-sentry-actions-ro-token.sh; 143 for
# both signals because the distinction buys nothing here). Both the baseline capture and the
# bite-proof are callers, so there is exactly one trap owner and no ordering hazard.
WT=""
# The Stage A refresh's temp file (initialised here so an early `die` under `set -u` cannot trip an
# unbound variable inside the EXIT trap and replace the intended exit code).
STAGE_A_TMP=""
# _wt_cleanup [interrupted]: the ONE trap handler. Removes the worktree if one is open and, in
# default mode, every artifact this run emitted. The word "interrupted" is printed only when a
# signal arrived; a failed step says "run aborted".
_wt_cleanup() {
  local why="${1:-run aborted}"
  release_run_lock
  if [[ -n "${STAGE_A_TMP:-}" ]]; then
    rm -f -- "$STAGE_A_TMP"
  fi
  if [[ -n "${WT:-}" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf -- "$WT"
  fi
  # Default mode: a TERM (or a die anywhere after the first write) must not leave the repo at 66.
  if [[ "$MODE" == "default" ]]; then
    local removed
    removed="$(remove_emitted_artifacts)"
    [[ -n "$removed" ]] && say "$why; removed: $removed"
  elif [[ "$why" == "interrupted" && "$MODE" == "stage-a" ]]; then
    say "interrupted (stage-a refresh): the workflow is replaced only by the final atomic rename; review it with \`git diff\` before deciding"
  elif [[ "$why" == "interrupted" ]]; then
    say "interrupted (refresh mode): nothing removed; the committed baseline may already have been rewritten — review it with \`git diff\` before deciding"
  fi
  return 0
}
# Run lock: two scaffold runs in one repo (a default run and a --refresh-baseline, or two
# sessions) would each `mv` into the same baseline and one run's cleanup would delete the other's
# staged inputs mid-bite. One `mkdir` lock in the git common dir, holding the owner pid; a stale
# lock (owner gone) is taken over, a live one is a 69 with the pid named, and so is a lock with no
# owner pid yet that is under a minute old (a run between its mkdir and its pid write). Released by
# the handler.
RUN_LOCK=""
take_run_lock() {
  local common
  common="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)" || common=".git"
  [[ "$common" == /* ]] || common="$REPO_ROOT/$common"
  RUN_LOCK="$common/constraint-scaffold.lock"
  if ! mkdir "$RUN_LOCK" 2>/dev/null; then
    local owner
    owner="$(cat "$RUN_LOCK/pid" 2>/dev/null || true)"
    # `kill -0` fails with EPERM for a live process owned by another user, so "gone" needs `ps -p` too.
    if [[ -n "$owner" ]] && { kill -0 "$owner" 2>/dev/null || ps -p "$owner" >/dev/null 2>&1; }; then
      RUN_LOCK=""
      fail_stdout 69 "another constraint-scaffold run (pid $owner) is in progress in this repository; wait for it"
    fi
    # A lock directory with no owner yet is a run caught between its `mkdir` and its pid write, not a
    # stale lock: honour it while the directory is under a minute old (`find -mmin` exists on GNU and BSD).
    if [[ -z "$owner" && -n "$(find "$RUN_LOCK" -prune -mmin -1 -print 2>/dev/null || true)" ]]; then
      RUN_LOCK=""
      fail_stdout 69 "another constraint-scaffold run is starting in this repository (the run lock has no owner pid yet); wait a moment and re-run"
    fi
    rm -rf -- "$RUN_LOCK"
    mkdir "$RUN_LOCK" 2>/dev/null || { local lockpath="$RUN_LOCK"; RUN_LOCK=""; fail_stdout 69 "cannot take the run lock at $lockpath"; }
  fi
  printf '%s\n' "$$" > "$RUN_LOCK/pid"
}
release_run_lock() {
  [[ -n "${RUN_LOCK:-}" && -d "$RUN_LOCK" ]] && rm -rf -- "$RUN_LOCK"
  RUN_LOCK=""
  return 0
}
# TMPDIR containment, checked before the first write (a `mktemp -d` under a TMPDIR inside the
# repo would land the bite worktree — and its logs — in the founder's tree as untracked files).
check_tmpdir_outside_repo() {
  local t
  t="$(physdir "${TMPDIR:-/tmp}")" || t=""
  # A TMPDIR that does not exist cannot be inside the repo; mktemp reports it (69) at first use.
  [[ -n "$t" ]] || return 0
  case "$t" in
    "$REPO_ROOT"|"$REPO_ROOT"/*)
      fail_stdout 69 "TMPDIR ($t) resolves inside the repository; refusing to create the bite worktree there" ;;
  esac
}
with_detached_worktree() {
  local ref="$1" fn="$2"
  trap '_wt_cleanup' EXIT
  trap '_wt_cleanup interrupted; trap - EXIT; exit 143' INT TERM
  WT="$(mktemp -d)" || fail_stdout 69 "cannot create a temp dir under TMPDIR=${TMPDIR:-/tmp}"
  case "$(physdir "$WT")" in
    "$REPO_ROOT"/*)
      fail_stdout 69 "TMPDIR resolves inside the repository; refusing to create the bite worktree there" ;;
  esac
  # Keep git's own reason (a failing post-checkout hook, LFS, a corrupt object): a 69 whose
  # message ends in "failed" with the cause discarded is a question the founder cannot answer.
  local git_err
  git_err="$(git -C "$REPO_ROOT" worktree add --detach "$WT" "$ref" 2>&1 >/dev/null)" \
    || fail_stdout 69 "git worktree add at ${ref:0:12} failed: $(printf '%s' "$git_err" | tail -n 3 | tr '\n' ' ')"
  "$fn" "$WT"
  git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf -- "$WT"
  WT=""
  # Leave the handler armed while the default-mode tail owns it (CLEANUP_ARMED=1).
  [[ "${CLEANUP_ARMED:-0}" == 1 ]] || trap - EXIT INT TERM
}

# --- Baseline capture (shared) -----------------------------------------------
# Captures the value-violations of the tree rooted at $1 into $BASELINE. Scans
# only the client dirs (app/components) that actually exist plus server/, so a
# single-client-dir app does not error on a missing dir.
capture_baseline() {
  local app_root="$1"
  [[ -x "$DEPCRUISE" ]] || fail_stdout 68 "dependency-cruiser not found at ${DEPCRUISE#"$REPO_ROOT"/} — run 'npm ci --ignore-scripts' in $TARGET_REL first"
  local scan_dirs=()
  local d
  for d in app components server; do
    [[ -d "$app_root/$d" ]] && scan_dirs+=("$d")
  done
  [[ "${#scan_dirs[@]}" -gt 0 ]] || fail_stdout 68 "no app/components/server dirs under $app_root — cannot capture baseline"
  local tmp dc_err
  tmp="$(mktemp)"
  if ! dc_err="$( ( cd "$app_root" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type baseline "${scan_dirs[@]}" ) 2>&1 > "$tmp" )"; then
    rm -f "$tmp"
    fail_stdout 68 "baseline capture failed — dependency-cruiser said: $(printf '%s' "$dc_err" | tail -n 5 | tr '\n' ' ') (config error, or the hoisted node_modules symlink did not resolve?)"
  fi
  mv "$tmp" "$BASELINE"
  log "captured baseline: $(grep -c '"rule"' "$BASELINE" 2>/dev/null || true) known violation(s) -> ${BASELINE#"$REPO_ROOT"/}"
}

_capture_baseline_in_worktree() {
  local wt="$1"
  local wt_target="$wt/$TARGET_REL"
  [[ -d "$wt_target/app" || -d "$wt_target/components" ]] \
    || fail_stdout 69 "base tree ($BASE_REF) has no $TARGET_REL/app|components — cannot capture baseline"
  # The merge-base may predate the gate: ensure the current config is present, and
  # reuse the installed node_modules (depcruise binary + resolver) via symlink.
  cp "$CFG" "$wt_target/.dependency-cruiser.cjs"
  [[ -e "$wt_target/node_modules" ]] || ln -s "$TARGET/node_modules" "$wt_target/node_modules"
  capture_baseline "$wt_target"
}

# resolve_base_ref: sets BASE_REF (origin/main, else the remote's default branch via
# origin/HEAD) and MB (its merge-base with HEAD). Runs BEFORE the first write in both modes, so
# a founder repo without origin/main fails 69 with nothing to clean up. Read-only.
resolve_base_ref() {
  if git -C "$REPO_ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1; then
    BASE_REF="origin/main"
  elif BASE_REF="$(git -C "$REPO_ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" && [[ -n "$BASE_REF" ]]; then
    :
  else
    fail_stdout 69 "no origin/main and no origin/HEAD — fetch the default branch first (git fetch origin main, or git remote set-head origin -a)"
  fi
  if ! MB="$(git -C "$REPO_ROOT" merge-base "$BASE_REF" HEAD 2>/dev/null)"; then
    local shallow=""
    [[ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]] \
      && shallow=" — this is a SHALLOW clone: run \`git fetch --unshallow\` first"
    fail_stdout 69 "could not compute merge-base of $BASE_REF and HEAD (unrelated histories, or $BASE_REF not fetched?)$shallow"
  fi
}

# Capture the baseline against the base-ref merge-base in a detached worktree,
# so a violation introduced in the SAME PR (branch-added) is NOT grandfathered —
# only violations pre-existing on the base land in the baseline. Used by BOTH modes:
# first adoption (default) must not grandfather a same-PR leak any more than a
# refresh does. Requires a clean tree (committed state == reviewable baseline).
# require_clean_tree <when>: 67 on a dirty tree (committed state == reviewable baseline).
require_clean_tree() {
  if ! { git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet; }; then
    die "working tree is dirty — commit or discard changes $1" 67
  fi
}

capture_baseline_mergebase() {
  require_clean_tree "before capturing the baseline"
  log "capturing baseline against $BASE_REF merge-base ${MB:0:12} (same-PR violations excluded)"
  with_detached_worktree "$MB" _capture_baseline_in_worktree
}

# --- Bite-proof ------------------------------------------------------------------
# verdict_fail <code> <msg> [<log-file>] [<extra stdout lines>]: prints the verdict on STDOUT,
# then the last 40 lines of the captured runner log, then (default mode) removes every artifact
# this run emitted and says so; then dies with <code>. Refresh mode removes nothing (the
# artifacts are committed) and says the baseline was rewritten.
verdict_fail() {
  local code="$1" msg="$2" logf="${3:-}" extra="${4:-}"
  say "bite-proof FAILED ($code): $msg"
  if [[ -n "$extra" ]]; then printf '%s\n' "$extra"; fi
  if [[ -n "$logf" && -f "$logf" ]]; then
    printf -- '--- last 40 lines of %s ---\n' "$(basename "$logf")"
    tail -n 40 "$logf"
    printf -- '--- end of log ---\n'
  fi
  if [[ "$MODE" == "default" ]]; then
    local removed
    removed="$(remove_emitted_artifacts)"
    say "removed the artifacts this run emitted (${removed:-none}); the repo is as it was (a SIGKILL may leave a stale registration: \`git worktree prune\`); re-run after fixing the cause"
  else
    say "refresh mode: the baseline was rewritten by this run — review it with \`git diff\` before deciding; no artifact was removed"
  fi
  # The verdict line above IS the stdout copy; log to stderr and exit (not `die`, which would
  # print a second FAILED line). The EXIT trap removes the worktree.
  log "$msg"
  exit "$code"
}

# Run the emitted runner against the worktree copy, capturing stdout+stderr to a file (so a
# failure can show its evidence before the worktree is removed). Sets RC; never aborts under
# `set -e` (a bare non-zero runner call would end the scaffold before the arm dispatch).
_run_gate() {
  local wt_target="$1" logf="$2"
  RC=0
  CONSTRAINT_GATES_DIR="$wt_target" bash "$wt_target/scripts/constraint-gates.sh" >"$logf" 2>&1 || RC=$?
  # A terminal Ctrl-C reaches the node child first: it exits 130 and bash never sees the
  # signal, so without this arm the interrupted run would be dispatched as a 71/72/73 verdict.
  if [[ "$RC" -eq 130 ]]; then
    _wt_cleanup interrupted; trap - EXIT; exit 130
  fi
  # Belt and braces with the runner's NO_COLOR=1: a FORCE_COLOR environment decorates
  # depcruise's `error <rule>:` lines and both anchors below would match nothing.
  sed $'s/\e\\[[0-9;]*m//g' "$logf" > "$logf.plain" && mv -f "$logf.plain" "$logf"
}

_depcruise_version() {
  local wt_target="$1"
  node -p 'require(process.argv[1] + "/node_modules/dependency-cruiser/package.json").version' "$wt_target" 2>/dev/null \
    || printf 'unknown'
}

_prove_bite_in_worktree() {
  local wt="$1"
  local wt_target="$wt/$TARGET_REL"
  # 1. Stage. Copy the three artifacts that may be uncommitted into the HEAD worktree. Ordering
  #    dependency: the clean-tree guard in capture_baseline_mergebase ran first, so for tracked
  #    files the working tree == HEAD and these copies are no-ops by content; the untracked case
  #    (first install) is exactly what the copy exists for. node_modules is reused via symlink,
  #    exactly as the baseline capture does.
  mkdir -p "$wt_target/scripts"
  cp "$CFG" "$wt_target/.dependency-cruiser.cjs"
  cp "$RUNNER" "$wt_target/scripts/constraint-gates.sh"
  chmod +x "$wt_target/scripts/constraint-gates.sh"
  cp "$BASELINE" "$wt_target/.dependency-cruiser-known-violations.json"
  [[ -e "$wt_target/node_modules" ]] || ln -s "$TARGET/node_modules" "$wt_target/node_modules"
  local ver
  ver="$(_depcruise_version "$wt_target" | tr -cd 'A-Za-z0-9.+-' | cut -c1-40)"

  # 2. Pass on the clean tree.
  _run_gate "$wt_target" "$wt/bite-1.log"
  if [[ "$RC" -ne 0 ]]; then
    local violations n
    violations="$(grep -E '^[[:space:]]*error [^:]+: ' "$wt/bite-1.log" || true)"
    if [[ -n "$violations" ]]; then
      n="$(printf '%s\n' "$violations" | grep -c . || true)"
      verdict_fail 74 "$n real client->server-secret violation(s) on HEAD newer than the merge-base baseline — the gate is live; fix the listed imports, then re-run" "$wt/bite-1.log" "$violations"
    fi
    verdict_fail 71 "gate did not pass on the clean tree before the probe (rc=$RC) — config or toolchain error; see the log tail" "$wt/bite-1.log"
  fi

  # 3. Inject — each rule on the edge it exists for. A symlinked server/ or components/ would
  #    route the probes OUTSIDE the worktree (a checked-out link resolves the same as in the
  #    founder's tree): refuse rather than write through it.
  local d
  for d in server components; do
    [[ -L "$wt_target/$d" ]] && verdict_fail 71 "$TARGET_REL/$d is a symlink; refusing to write the bite probes through it"
  done
  #    Each rule on the edge it exists for. direct.tsx is a "use client" module
  #    value-importing the probe server module (direct rule); hop.ts is a NON-client helper that
  #    value-imports it; via-hop.tsx is a "use client" module value-importing ./hop (transitive
  #    rule). The server module exports one string that is visibly not a secret.
  mkdir -p "$wt_target/$(dirname "$PROBE_DIRECT")"
  printf 'export const BITE_PROBE_MARKER = "constraint-scaffold bite probe (not a secret)";\n' > "$wt_target/$PROBE_SERVER"
  printf '"use client";\nimport { BITE_PROBE_MARKER } from "@/server/__constraint_scaffold_bite_probe__";\nexport const Direct = () => BITE_PROBE_MARKER;\n' > "$wt_target/$PROBE_DIRECT"
  printf 'import { BITE_PROBE_MARKER } from "@/server/__constraint_scaffold_bite_probe__";\nexport const hop = () => BITE_PROBE_MARKER;\n' > "$wt_target/$PROBE_HOP"
  printf '"use client";\nimport { hop } from "./hop";\nexport const ViaHop = () => hop();\n' > "$wt_target/$PROBE_VIA_HOP"

  # 4. Fail, naming both rules on their own edges. Anchored on depcruise's `error <rule>: `
  #    call-form on the captured stream, never a bare rule name (the runner's zero-reachability
  #    prose carries the bare transitive token, and a `warn` line must not satisfy it).
  _run_gate "$wt_target" "$wt/bite-2.log"
  local named=""
  if grep -qE "^[[:space:]]*error $RULE_DIRECT: .*direct\.tsx" "$wt/bite-2.log"; then
    named="$named $RULE_DIRECT@direct"
  fi
  if grep -qE "^[[:space:]]*error $RULE_TRANSITIVE: .*via-hop\.tsx" "$wt/bite-2.log"; then
    named="$named $RULE_TRANSITIVE@via-hop"
  fi
  if [[ "$RC" -eq 0 || "$named" != " $RULE_DIRECT@direct $RULE_TRANSITIVE@via-hop" ]]; then
    verdict_fail 72 "the gate did NOT reject the injected client->server-secret import (rc=$RC; depcruise=$ver; rules named on their edges:${named:- none}) — a gate that cannot fail is not a gate" "$wt/bite-2.log"
  fi

  # 5. Revert.
  rm -f -- "$wt_target/$PROBE_DIRECT" "$wt_target/$PROBE_HOP" "$wt_target/$PROBE_VIA_HOP" "$wt_target/$PROBE_SERVER"
  rmdir "$wt_target/$(dirname "$PROBE_DIRECT")" >/dev/null 2>&1 || true

  # 6. Pass again.
  _run_gate "$wt_target" "$wt/bite-3.log"
  if [[ "$RC" -ne 0 ]]; then
    verdict_fail 73 "gate did not return to green after the probes were removed (rc=$RC) — non-deterministic gate" "$wt/bite-3.log"
  fi

  # 7. One verdict line on STDOUT (ASCII arrows so an AC can grep it).
  printf 'constraint-scaffold: bite-proof pass -> fail(%s@direct, %s@via-hop) -> pass depcruise=%s\n' "$RULE_DIRECT" "$RULE_TRANSITIVE" "$ver"
}

# prove_bite: called at the tail of BOTH modes. Runs the emitted gate on a detached worktree of
# HEAD through the shared helper; the helper removes the worktree afterwards.
prove_bite() {
  with_detached_worktree HEAD _prove_bite_in_worktree
}

# --- README block + agent-instructions pointer (append-once, written LAST) ---------
# append_once <file> <marker> <content>: refuses a symlinked target first (a
# `CLAUDE.md -> ~/.claude/CLAUDE.md` link is a common founder shape and `>>` would write into
# their GLOBAL instructions — CWE-59); idempotent on <marker>; guards the trailing newline of the
# existing file; then appends. Returns non-zero on refusal or a failed write so the callers can
# warn rather than die (after a successful bite, prose is not the gate).
append_once() {
  local f="$1" marker="$2" content="$3"
  [[ -L "$f" ]] && { warn "refusing to append through a symlink: ${f#"$REPO_ROOT"/} -> $(readlink "$f")"; return 1; }
  # A symlinked PARENT (server/ -> outside) passes `-L` on the file: require containment.
  local phys
  phys="$(physpath "$f")" || phys=""
  case "$phys" in
    "$REPO_ROOT"/*) ;;
    *) warn "refusing to append outside the repository: ${f#"$REPO_ROOT"/} resolves to ${phys:-<unresolvable>}"; return 1 ;;
  esac
  grep -qF -- "$marker" "$f" 2>/dev/null && return 0
  [[ -s "$f" && -n "$(tail -c 1 "$f")" ]] && printf '\n' >> "$f"
  printf '%s\n' "$content" >> "$f" || return 1
  return 0
}

emit_readme() {
  local content
  content="$(sed -e '1{/^<!-- Inspired by /d;}' -e "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/boundary-readme.template" 2>/dev/null || true)"
  if [[ -n "$content" ]] && append_once "$README" "<!-- constraint-scaffold:readme:start -->" "$content"; then
    log "README block present in ${README#"$REPO_ROOT"/}"
  else
    warn "could not append the boundary README block to ${README#"$REPO_ROOT"/} — the gate is installed and proven; the missing doc is references/boundary-readme.template of soleur:constraint-scaffold (add it by hand)"
  fi
}

emit_pointer() {
  # Pointer file: repo-root CLAUDE.md if present, else AGENTS.md (created if absent). Plain,
  # informational prose with a repo-relative path — never the `@path` import form, which would
  # load the README into every session and promote an unpinned markdown file to instructions.
  local f
  if [[ -e "$REPO_ROOT/CLAUDE.md" || -L "$REPO_ROOT/CLAUDE.md" ]]; then
    f="$REPO_ROOT/CLAUDE.md"
  else
    f="$REPO_ROOT/AGENTS.md"
  fi
  local line="The client/server import boundary and its CI gate are documented in $TARGET_REL/server/README.md (generated by soleur:constraint-scaffold). <!-- constraint-scaffold:pointer -->"
  if append_once "$f" "<!-- constraint-scaffold:pointer -->" "$line"; then
    log "instructions pointer present in ${f#"$REPO_ROOT"/}"
  else
    warn "could not append the instructions pointer to ${f#"$REPO_ROOT"/} — the gate is installed and proven; the missing line points at $TARGET_REL/server/README.md (add it by hand)"
  fi
}

# --- --refresh-stage-a ------------------------------------------------------------------------
# Re-emit ONE file, the Stage A workflow, over an installed copy that is byte-identical to a
# historical emission. The clobber control is a sha256 LEDGER of every historical substituted
# emission (references/fix-constraints-stage-a.emitted.sha256, rows in chronological order, newest
# last); the tree guard only makes the result reviewable. The pin is read from the template at run
# time, so this script carries no action pin of its own (claude-pin-lockstep.test.ts stays whole).
STAGE_A_TEMPLATE="$REF_DIR/fix-constraints-stage-a.template"
STAGE_A_LEDGER="$REF_DIR/fix-constraints-stage-a.emitted.sha256"

# sha256_hex <file>: the bare 64-hex digest on stdout, or nothing when the tool printed none. Never
# dies (it runs inside command substitutions); the caller validates the shape.
sha256_hex() {
  local out=""
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum "$1" 2>/dev/null || true)"
  elif command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 "$1" 2>/dev/null || true)"
  fi
  printf '%s' "${out%% *}"
}
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }

# ledger_rank <sha>: the 1-based rank of the row among the ledger's data rows, or nothing. Exact
# equality on the FIRST field only (a substring or prefix match would admit a different hash), so a
# missing, empty or comment-only ledger matches nothing. Always returns 0: the caller tests the OUTPUT.
ledger_rank() {
  [[ -f "$STAGE_A_LEDGER" ]] || return 0
  awk -v h="$1" '/^[[:space:]]*#/ || !NF {next} {n++} ($1 "") == (h "") {print n; exit}' "$STAGE_A_LEDGER" || true
  return 0
}

# stage_a_report: the template-side lines only, bounded in width and count. The user's own file is
# NEVER printed (a secret pasted into an edited workflow must not reach an agent transcript); the
# agent reads its own file when it merges by hand. Wrapped so SIGPIPE from `head` cannot abort.
stage_a_report() {
  { diff -- "$FIXWORKFLOW_A" "$STAGE_A_TMP" | grep -v '^< ' | cut -c1-200 | head -60 || true; }
  return 0
}

refresh_stage_a() {
  local dest="$FIXWORKFLOW_A" dest_dir want_dir want have want_rank have_rank now
  # 1. Existence first, before every check that can fail for another reason or write a lock. A
  #    dangling symlink is not a file, so it is also 70.
  [[ -f "$CFG" ]] || die "no .dependency-cruiser.cjs at $TARGET_REL — run the default mode first to generate the gate" 70
  [[ -f "$dest" ]] || die "no fix-constraints-stage-a.yml at $TARGET_REL/.github/workflows to refresh — restore it from git if it was deleted (git checkout -- <path>); an install that predates the two-stage split has no Stage A file and is not covered by this flag" 70
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    die "no sha256 tool (sha256sum or shasum) on PATH" 69
  fi
  # 2. Path safety. A symlinked FILE is refused; so is any destination whose PHYSICAL directory is
  #    not exactly <target>/.github/workflows (a symlinked .github passes a repo-containment check
  #    and would redirect the write). The expected directory is built from the physical REPO_ROOT
  #    and the literal target, not resolved from TARGET, so a symlinked apps/ or apps/web-platform/
  #    cannot satisfy it. After the check `dest` is rebound to its physical form, so the recheck and
  #    the mv use the same directory the check approved.
  if [[ -L "$dest" ]]; then
    die "fix-constraints-stage-a.yml is a symlink; refusing to refresh through it (left unchanged)" 75
  fi
  dest_dir="$(physdir "$(dirname -- "$dest")")" || dest_dir=""
  want_dir="$REPO_ROOT/$TARGET_REL/.github/workflows"
  case "$dest_dir" in
    /proc/*|/sys/*|/dev/*) die "the repository sits under a synthetic filesystem ($dest_dir); refusing (left unchanged)" 69 ;;
  esac
  if [[ -z "$dest_dir" || "$dest_dir" != "$want_dir" ]]; then
    die "the physical directory of fix-constraints-stage-a.yml (${dest_dir:-unresolvable}) is not $TARGET_REL/.github/workflows; refusing to write through a redirected directory (left unchanged)" 75
  fi
  dest="$dest_dir/${dest##*/}"

  # 3. Reviewable: tracked and clean. The hash gate below, not this, is the clobber control.
  if ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "${dest#"$REPO_ROOT"/}" >/dev/null 2>&1; then
    die "fix-constraints-stage-a.yml is not tracked by git — commit the workflow first so the refresh is reviewable with git diff" 67
  fi
  require_clean_tree "before refreshing the stage-a workflow"
  # 4. Arm the single trap owner, THEN take the lock (a failed take never removes another run's lock).
  trap '_wt_cleanup' EXIT
  trap '_wt_cleanup interrupted; trap - EXIT; exit 143' INT TERM
  take_run_lock
  # 5. Fresh emission to a temp file next to the destination (same filesystem: atomic rename).
  STAGE_A_TMP="$(mktemp "$dest_dir/.fix-constraints-stage-a.XXXXXX")" || die "cannot create a temp file next to fix-constraints-stage-a.yml" 69
  # assert_fixture_dir is called at each write operand because the repo-wide fixture-relative
  # ratchet counts an unproven operand; both operands are already physical absolute paths here.
  assert_fixture_dir "$STAGE_A_TMP"
  sed "s|__TARGET_DIR__|$TARGET_REL|g" "$STAGE_A_TEMPLATE" > "$STAGE_A_TMP" || die "cannot render the stage-a template" 69
  want="$(sha256_hex "$STAGE_A_TMP")"
  have="$(sha256_hex "$dest")"
  # An empty or malformed digest must never reach classification: with both digests empty,
  # `have == want` below would print "already current" over a tool that measured nothing.
  if ! is_sha256 "$want" || ! is_sha256 "$have"; then
    die "could not compute a sha256 for the stage-a workflow (the hash tool printed no digest); left unchanged" 69
  fi
  # 6. Already current: the one outcome that never consults the ledger, and writes nothing.
  if [[ "$have" == "$want" ]]; then
    say "fix-constraints-stage-a.yml already current; nothing to do"
    exit 0
  fi
  # 7. Classify against the ledger.
  want_rank="$(ledger_rank "$want")"
  have_rank="$(ledger_rank "$have")"
  if [[ -z "$want_rank" ]]; then
    die "this plugin's ledger (references/fix-constraints-stage-a.emitted.sha256) is missing, empty or lacks its own template's emission; update the plugin. Left unchanged" 75
  fi
  if [[ -z "$have_rank" ]]; then
    say "FAILED (75): fix-constraints-stage-a.yml differs from every known emission (edited, or a version this ledger does not know); left unchanged"
    say "template-side differences follow (your file is not printed; read it yourself and merge by hand; limited to 60 lines):"
    stage_a_report
    say "full target: references/fix-constraints-stage-a.template with __TARGET_DIR__ replaced by $TARGET_REL. After a hand merge this flag keeps refusing: the file is no longer a known emission"
    log "fix-constraints-stage-a.yml is not a known pristine emission; left unchanged"
    exit 75
  fi
  if [[ "$have_rank" -gt "$want_rank" ]]; then
    die "the installed fix-constraints-stage-a.yml is newer than this plugin's template (ledger row $have_rank of $want_rank); update the plugin, do not downgrade. Left unchanged" 75
  fi
  # The current template installs with `npm ci` in the target; a repo whose gate predates that (the
  # earliest emissions installed with bun) may have no package-lock.json, and the refreshed job
  # would then fail at its install step on the first PR that needs recovery. Checked only when a
  # write is about to happen (an already-current file exited above), and the lockfile must be
  # tracked: an untracked or gitignored one is absent on a clean CI clone.
  if [[ ! -f "$TARGET/package-lock.json" ]] \
     || ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "$TARGET_REL/package-lock.json" >/dev/null 2>&1; then
    die "$TARGET_REL/package-lock.json is missing or not tracked by git and the current stage-a template installs with \`npm ci\`; commit a lockfile there, or merge the template into your workflow by hand (left unchanged)" 75
  fi
  # 8. Pre-write recheck (narrows the window; the residual is a microsecond-wide race with an editor.
  #    The committed copy stays recoverable with `git checkout -- <file>`; an edit saved inside that
  #    window and not yet committed would be lost), then the one write.
  now="$(sha256_hex "$dest")"
  if [[ ! -f "$dest" || -d "$dest" || -L "$dest" || "$now" != "$have" ]]; then
    die "fix-constraints-stage-a.yml changed during the run; left unchanged — re-run" 75
  fi
  chmod 0644 "$STAGE_A_TMP" || die "cannot set the mode on the refreshed workflow (left unchanged)" 69
  assert_fixture_dir "$dest"
  mv -f -- "$STAGE_A_TMP" "$dest" || die "could not replace fix-constraints-stage-a.yml (the original is intact)" 69
  STAGE_A_TMP=""
  say "refreshed fix-constraints-stage-a.yml (ledger row $have_rank -> $want_rank); review the change with \`git diff\` and commit it"
  exit 0
}

if [[ "$MODE" == "stage-a" ]]; then
  refresh_stage_a
fi

if [[ "$MODE" == "refresh" ]]; then
  [[ -f "$CFG" ]] || die "no .dependency-cruiser.cjs at $TARGET_REL — run the default mode first to generate the gate" 70
  require_clean_tree "before capturing the baseline"
  resolve_base_ref
  check_tmpdir_outside_repo
  trap '_wt_cleanup' EXIT
  trap '_wt_cleanup interrupted; trap - EXIT; exit 143' INT TERM
  CLEANUP_ARMED=1
  take_run_lock
  capture_baseline_mergebase
  prove_bite
  release_run_lock
  CLEANUP_ARMED=0
  trap - EXIT INT TERM
  log "refresh complete — review the baseline diff before merging."
  exit 0
fi

# --- Default mode: emit artifacts (non-destructive) --------------------------
# Clean-tree guard FIRST — the baseline is captured against the origin/main
# merge-base (below), and we refuse to emit onto a dirty tree so the resulting
# baseline + artifact diff is reviewable and deterministic.
require_clean_tree "before generating the gate"

for f in "$CFG" "$RUNNER" "$WORKFLOW" "$FIXWORKFLOW_A" "$FIXWORKFLOW_B"; do
  [[ -e "$f" ]] && die "refuse-if-exists: ${f#"$REPO_ROOT"/} already present (no --force). Committed gate: re-baseline via --refresh-baseline; a committed, stale fix-constraints-stage-a.yml: --refresh-stage-a. Untracked leftovers of a killed first install: delete them (\`git clean -n $TARGET_REL\` lists them), run \`git worktree prune\`, re-run" 66
done
[[ -e "$BASELINE" ]] && die "refuse-if-exists: ${BASELINE#"$REPO_ROOT"/} already present (re-baseline via --refresh-baseline)" 66

# Three-dirs precondition, BEFORE anything is emitted: the emitted runner cruises all three
# and would fail its own CI on a target missing one; the README names the requirement.
for d in app components server; do
  [[ -d "$TARGET/$d" ]] || fail_stdout 65 "target $TARGET_REL lacks $d/ (the emitted runner cruises app/ components/ server/ and would fail its own CI)"
done

# Base ref and temp dir, BEFORE anything is emitted: the two first-install failures a founder
# repo actually hits (no origin/main; an IDE TMPDIR inside the repo) must not write first.
resolve_base_ref
check_tmpdir_outside_repo

# Arm the self-cleanup before the first write (single handler: _wt_cleanup). Disarmed only
# after prove_bite returns — the worktree helper re-installs the same handler and leaves it
# armed while CLEANUP_ARMED=1. The run lock is taken inside the armed window so the handler
# releases it on every exit.
CLEANUP_ARMED=1
trap '_wt_cleanup' EXIT
trap '_wt_cleanup interrupted; trap - EXIT; exit 143' INT TERM
take_run_lock
mkdir -p "$TARGET/scripts" "$TARGET/.github/workflows"

# .dependency-cruiser.cjs — emitted verbatim (the from-set is computed at
# require-time, never baked in).
cp "$REF_DIR/depcruise-config.template" "$CFG"

# Shared runner.
cp "$REF_DIR/shared-runner.template" "$RUNNER"
chmod +x "$RUNNER"

# CI workflow — substitute the target dir (path-check glob + working-directory +
# runner path). sed delimiter is '|' since the value contains no '|'.
sed "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/constraint-gates-workflow.template" > "$WORKFLOW"

# Two-stage recovery dispatcher (ADR-074): same __TARGET_DIR__ substitution. Stage A
# (untrusted producer) + Stage B (privileged consumer, Git Data API — no checkout/apply).
sed "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/fix-constraints-stage-a.template" > "$FIXWORKFLOW_A"
sed "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/fix-constraints-stage-b.template" > "$FIXWORKFLOW_B"

log "emitted: ${CFG#"$REPO_ROOT"/}, ${RUNNER#"$REPO_ROOT"/}, ${WORKFLOW#"$REPO_ROOT"/}, ${FIXWORKFLOW_A#"$REPO_ROOT"/}, ${FIXWORKFLOW_B#"$REPO_ROOT"/}"

# Capture the initial baseline against the origin/main merge-base — same path as
# --refresh-baseline, so a leak introduced in the SAME PR that scaffolds the gate
# is NOT grandfathered (only violations pre-existing on main are).
capture_baseline_mergebase

# Prove the gate bites on HEAD, THEN write the prose. The README block and the pointer are the
# last writes of the run: the clean-tree guard inside the baseline capture must never see them
# (a tracked CLAUDE.md or server/README.md appended earlier would exit 67 with the executables
# already emitted and leave the next run at 66), and a 71/72/73/74 never has to undo them.
prove_bite
release_run_lock
CLEANUP_ARMED=0
trap - EXIT INT TERM
emit_readme
emit_pointer

log "done. Verify green: (cd $TARGET_REL && bash scripts/constraint-gates.sh)"
exit 0
