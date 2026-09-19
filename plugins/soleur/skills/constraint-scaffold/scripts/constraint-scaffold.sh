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
#
# Exit matrix (every non-zero is a hard, fail-closed stop):
#   0   success
#   64  usage error (unknown argument)
#   65  precondition failed (target is not a Next.js app, or lacks app/ components/ server/)
#   66  refuse-if-exists (a non-baseline artifact already present; no --force)
#   67  dirty working tree (baseline capture requires a clean tree)
#   68  dependency-cruiser binary missing, or baseline capture failed
#   69  git/merge-base/worktree error, or TMPDIR resolves inside the repository
#   70  --refresh-baseline before generation (no .dependency-cruiser.cjs yet — run default mode first)
#   71  bite-proof: gate did not pass on the clean HEAD tree before the probe (config/toolchain)
#   72  bite-proof: gate did NOT reject the injected client->server-secret imports on their edges
#   73  bite-proof: gate did not return to green after the probes were removed
#   74  bite-proof: real client->server-secret violation(s) on HEAD newer than the baseline
#
# In default mode a 71/72/73/74 REMOVES every artifact this run emitted (the README and the
# pointer have not been written yet), so a failed first install is re-runnable and never
# leaves a half-installed gate. An INT/TERM mid-bite does the same and exits 143.
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
die()  { log "$1"; exit "${2:-1}"; }
# Agent runtimes surface stdout and swallow stderr, so anything the founder or the agent must
# act on is printed on STDOUT too (warn/say), and only then logged.
say()  { printf 'constraint-scaffold: %s\n' "$*"; }
warn() { printf 'constraint-scaffold: WARNING: %s\n' "$*"; }
# fail_stdout <code> <msg>: the stdout-then-die path every user-actionable failure uses.
fail_stdout() { say "FAILED ($1): $2"; die "$2" "$1"; }

MODE="default"
case "${1:-}" in
  "") MODE="default" ;;
  --refresh-baseline) MODE="refresh" ;;
  *) die "unknown argument: $1 (expected none or --refresh-baseline)" 64 ;;
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
_wt_cleanup() {
  if [[ -n "${WT:-}" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf -- "$WT"
  fi
  # Default mode: a TERM (or a die inside the helper) must not leave the repo at 66 next run.
  if [[ "$MODE" == "default" ]]; then
    local removed
    removed="$(remove_emitted_artifacts)"
    [[ -n "$removed" ]] && say "interrupted; removed: $removed"
  fi
  return 0
}
with_detached_worktree() {
  local ref="$1" fn="$2"
  WT="$(mktemp -d)"
  case "$(realpath "$WT")" in
    "$REPO_ROOT"/*|"$(realpath "$REPO_ROOT")"/*)
      _wt_cleanup
      fail_stdout 69 "TMPDIR resolves inside the repository; refusing to create the bite worktree there" ;;
  esac
  trap '_wt_cleanup' EXIT
  trap '_wt_cleanup; trap - EXIT; exit 143' INT TERM
  git -C "$REPO_ROOT" worktree add --detach "$WT" "$ref" >/dev/null 2>&1 \
    || die "git worktree add at ${ref:0:12} failed" 69
  "$fn" "$WT"
  git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf -- "$WT"
  WT=""
  trap - EXIT INT TERM
}

# --- Baseline capture (shared) -----------------------------------------------
# Captures the value-violations of the tree rooted at $1 into $BASELINE. Scans
# only the client dirs (app/components) that actually exist plus server/, so a
# single-client-dir app does not error on a missing dir.
capture_baseline() {
  local app_root="$1"
  [[ -x "$DEPCRUISE" ]] || die "dependency-cruiser not found at $DEPCRUISE — run 'npm ci --ignore-scripts' in $TARGET_REL first" 68
  local scan_dirs=()
  local d
  for d in app components server; do
    [[ -d "$app_root/$d" ]] && scan_dirs+=("$d")
  done
  [[ "${#scan_dirs[@]}" -gt 0 ]] || die "no app/components/server dirs under $app_root — cannot capture baseline" 68
  local tmp
  tmp="$(mktemp)"
  if ! ( cd "$app_root" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type baseline "${scan_dirs[@]}" ) > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "baseline capture failed (dependency-cruiser config error, or the hoisted node_modules symlink did not resolve?)" 68
  fi
  mv "$tmp" "$BASELINE"
  log "captured baseline: $(grep -c '"rule"' "$BASELINE" 2>/dev/null || echo 0) known violation(s) -> ${BASELINE#"$REPO_ROOT"/}"
}

_capture_baseline_in_worktree() {
  local wt="$1"
  local wt_target="$wt/$TARGET_REL"
  [[ -d "$wt_target/app" || -d "$wt_target/components" ]] \
    || die "merge-base tree has no $TARGET_REL/app|components — cannot capture baseline" 69
  # The merge-base may predate the gate: ensure the current config is present, and
  # reuse the installed node_modules (depcruise binary + resolver) via symlink.
  cp "$CFG" "$wt_target/.dependency-cruiser.cjs"
  [[ -e "$wt_target/node_modules" ]] || ln -s "$TARGET/node_modules" "$wt_target/node_modules"
  capture_baseline "$wt_target"
}

# Capture the baseline against the origin/main merge-base in a detached worktree,
# so a violation introduced in the SAME PR (branch-added) is NOT grandfathered —
# only violations pre-existing on main land in the baseline. Used by BOTH modes:
# first adoption (default) must not grandfather a same-PR leak any more than a
# refresh does. Requires a clean tree (committed state == reviewable baseline).
capture_baseline_mergebase() {
  if ! { git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet; }; then
    die "working tree is dirty — commit or discard changes before capturing the baseline" 67
  fi
  MB="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null)" \
    || die "could not compute merge-base with origin/main (is origin/main fetched?)" 69
  log "capturing baseline against origin/main merge-base ${MB:0:12} (same-PR violations excluded)"
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
  die "$msg" "$code"
}

# Run the emitted runner against the worktree copy, capturing stdout+stderr to a file (so a
# failure can show its evidence before the worktree is removed). Sets RC; never aborts under
# `set -e` (a bare non-zero runner call would end the scaffold before the arm dispatch).
_run_gate() {
  local wt_target="$1" logf="$2"
  RC=0
  CONSTRAINT_GATES_DIR="$wt_target" bash "$wt_target/scripts/constraint-gates.sh" >"$logf" 2>&1 || RC=$?
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
  ver="$(_depcruise_version "$wt_target")"

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

  # 3. Inject — each rule on the edge it exists for. direct.tsx is a "use client" module
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
  grep -qF -- "$marker" "$f" 2>/dev/null && return 0
  [[ -s "$f" && -n "$(tail -c 1 "$f")" ]] && printf '\n' >> "$f"
  printf '%s\n' "$content" >> "$f" || return 1
  return 0
}

emit_readme() {
  local content
  content="$(sed -e '1{/^<!-- Inspired by /d}' -e "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/boundary-readme.template" 2>/dev/null || true)"
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

if [[ "$MODE" == "refresh" ]]; then
  [[ -f "$CFG" ]] || die "no .dependency-cruiser.cjs at $TARGET_REL — run the default mode first to generate the gate" 70
  capture_baseline_mergebase
  prove_bite
  log "refresh complete — review the baseline diff before merging."
  exit 0
fi

# --- Default mode: emit artifacts (non-destructive) --------------------------
# Clean-tree guard FIRST — the baseline is captured against the origin/main
# merge-base (below), and we refuse to emit onto a dirty tree so the resulting
# baseline + artifact diff is reviewable and deterministic.
if ! { git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet; }; then
  die "working tree is dirty — commit or discard changes before generating the gate" 67
fi

for f in "$CFG" "$RUNNER" "$WORKFLOW" "$FIXWORKFLOW_A" "$FIXWORKFLOW_B"; do
  [[ -e "$f" ]] && die "refuse-if-exists: ${f#"$REPO_ROOT"/} already present (no --force; re-baseline via --refresh-baseline)" 66
done
[[ -e "$BASELINE" ]] && die "refuse-if-exists: ${BASELINE#"$REPO_ROOT"/} already present (re-baseline via --refresh-baseline)" 66

# Three-dirs precondition, BEFORE anything is emitted: the emitted runner cruises all three
# and would fail its own CI on a target missing one; the README names the requirement.
for d in app components server; do
  [[ -d "$TARGET/$d" ]] || fail_stdout 65 "target $TARGET_REL lacks one of app/ components/ server/ — the emitted runner cruises all three and would fail its own CI"
done

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
emit_readme
emit_pointer

log "done. Verify green: (cd $TARGET_REL && bash scripts/constraint-gates.sh)"
exit 0
