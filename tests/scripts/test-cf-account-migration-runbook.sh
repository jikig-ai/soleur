#!/usr/bin/env bash
# test-cf-account-migration-runbook.sh — the text contract of the #12931 Cloudflare account-migration
# runbook, against the tools it tells an agent to run (CTO rulings D3, D4, D5, D11, 2026-11-19).
#
# PROPERTIES (each row is a function over a runbook path, so a mutant copy can be fed to it):
#   R1 (D4) no line runs `terraform state push`: the full revert is withdrawn, the backup is DR
#      evidence only; and a `## Halt` section exists;
#   R2 (D5) in the Phase 3 reopen step the `git log … -- apps/web-platform/infra` line and the
#      scheduled-terraform-drift read both come BEFORE the `apply_target=manual-rerun` dispatch;
#   R3 (D3) the reopen step's expected output names a `cloudflare_ruleset.cache_shared_binaries`
#      create, and the redirects-dns expectation says the cache rule is not in that phase;
#   R4 (D11) every stage bootstrap.sh declares is named in the runbook, and every
#      `--stage <name>` the runbook issues is a declared stage;
#   R5 the probe verdict the runbook expects is the one cf-token-scope.sh prints
#      (`probe=<phase> verdict=pass`), and the withdrawn `verdict=authorized` / "plus a live
#      connector" wording is gone;
#   R6 the agent-never-approves-its-own-environment line and the revoke read-back are present.
#
# MUTATIONS (each proven to land, then must turn its row RED):
#   M1 append a `terraform state push -force` line            -> R1
#   M2 move the manual-rerun dispatch above the git-log line   -> R2
#   M3 delete the reopen step's cache_shared_binaries create   -> R3
#   M4 rename one runbook mention of branch-copies-tokens      -> R4
#   M5 reintroduce `verdict=authorized`                        -> R5
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)" || { echo "HARNESS: not in a git work tree" >&2; exit 2; }
RUNBOOK="${REPO_ROOT}/knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md"
BOOTSTRAP="$(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard --full-name '*feat-one-shot-12931-cf-account-migration/bootstrap.sh' | head -1)"
SCOPE_TOOL="${REPO_ROOT}/plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh"
[[ -r "$RUNBOOK" && -n "$BOOTSTRAP" && -r "${REPO_ROOT}/${BOOTSTRAP}" && -r "$SCOPE_TOOL" ]] \
  || { echo "HARNESS: runbook, bootstrap or cf-token-scope.sh missing" >&2; exit 2; }
BOOTSTRAP="${REPO_ROOT}/${BOOTSTRAP}"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi; }

check "instrument self-test (pass arm)" 0 >/dev/null
check "instrument self-test (fail arm)" 1 >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then echo "INSTRUMENT SELF-TEST FAILED" >&2; exit 2; fi
PASS=0; FAIL=0

SB="$(mktemp -d -t cfam-runbook.XXXXXXXX)" || { echo "HARNESS: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT

# The reopen step: from its bold title to the next numbered step.
reopen_block() { awk '/\*\*Reopen the routine path\*\*/{on=1} on && /^7\. /{exit} on' "$1"; }

row_r1() {
  ! grep -nE 'terraform[[:space:]]+state[[:space:]]+push' "$1" >/dev/null && grep -qx '## Halt' "$1"
}
row_r2() {
  local b gl dr mr
  b="$(reopen_block "$1")"; [[ -n "$b" ]] || return 1
  gl="$(grep -nF 'git log --oneline <PR1-merge-sha>..origin/main -- apps/web-platform/infra' <<<"$b" | head -1 | cut -d: -f1)"
  dr="$(grep -nF 'gh run list --workflow scheduled-terraform-drift.yml' <<<"$b" | head -1 | cut -d: -f1)"
  mr="$(grep -nF 'apply_target=manual-rerun' <<<"$b" | head -1 | cut -d: -f1)"
  [[ -n "$gl" && -n "$dr" && -n "$mr" && "$gl" -lt "$mr" && "$dr" -lt "$mr" ]]
}
row_r3() {
  reopen_block "$1" | grep -qF '`cloudflare_ruleset.cache_shared_binaries` create' \
    && grep -qF '`cache_shared_binaries` is not in this phase (CTO ruling D3)' "$1"
}
declared_stages() { grep -a '^# SOLEUR-STAGE ' "$BOOTSTRAP" | sed 's/^# SOLEUR-STAGE //' | cut -d'|' -f1; }
row_r4() {
  local s n bad=0
  for s in $(declared_stages); do grep -qF "\`${s}\`" "$1" || grep -qF -- "--stage ${s}" "$1" || { echo "    undeclared in runbook: $s" >&2; bad=1; }; done
  n="$(declared_stages | wc -l)"; [[ "$n" -ge 9 ]] || bad=1
  for s in $(grep -oE -- '--stage [a-z0-9-]+' "$1" | awk '{print $2}' | sort -u); do
    declared_stages | grep -qx "$s" || { echo "    runbook issues an undeclared stage: $s" >&2; bad=1; }
  done
  # every numbered stage item in Phase 2 ("1. `prev-0a`: …") is a declared stage
  for s in $(grep -oE '^[0-9]+\. `[a-z0-9-]+`:' "$1" | sed -E 's/^[0-9]+\. `([a-z0-9-]+)`:/\1/' | sort -u); do
    declared_stages | grep -qx "$s" || { echo "    numbered stage not declared: $s" >&2; bad=1; }
  done
  [[ "$bad" -eq 0 ]]
}
row_r5() {
  grep -qF 'probe=<phase> verdict=pass' "$1" \
    && ! grep -qE 'verdict=authorized|plus a live connector' "$1"
}
row_r6() {
  grep -qF '**The agent never approves its own environment gate.**' "$1" \
    && grep -qF 'Expected: `.success` is `false`' "$1"
}

echo "== the tool side of R5 =="
grep -qxF 'echo "probe=$PROFILE verdict=pass"' "$SCOPE_TOOL"
check "cf-token-scope.sh prints the run line probe=<profile> verdict=pass" $?
grep -qF -- '--staged' "$SCOPE_TOOL" && grep -qF 'redirects-dns' "$SCOPE_TOOL" && grep -qF 'zone-rest' "$SCOPE_TOOL"
check "cf-token-scope.sh has --staged and the redirects-dns and zone-rest profiles" $?

echo "== the runbook =="
row_r1 "$RUNBOOK"; check "R1 no terraform state push line; a Halt section exists (D4)" $?
row_r2 "$RUNBOOK"; check "R2 git-log and drift-plan reads precede the manual-rerun dispatch (D5)" $?
row_r3 "$RUNBOOK"; check "R3 reopen step names the one cache_shared_binaries create (D3)" $?
row_r4 "$RUNBOOK"; check "R4 runbook and bootstrap.sh name the same stages (D11)" $?
row_r5 "$RUNBOOK"; check "R5 the expected probe verdict is the tool's; withdrawn wording gone" $?
row_r6 "$RUNBOOK"; check "R6 no self-approval line and the revoke read-back are present" $?

echo "== mutations =="
mutate() { # <label> <dst> — perl program on stdin
  local label="$1" dst="$2" prog; prog="$(cat)"
  cp "$RUNBOOK" "$dst"; perl -0777 -pi -e "$prog" "$dst"
  if cmp -s "$dst" "$RUNBOOK"; then fail "mutation ${label} did not land"; return 1; fi
  pass "mutation ${label} landed"
}
expect_red() { # <label> <row> <file>
  if "$2" "$3" 2>/dev/null; then fail "$1 stayed GREEN"; else pass "$1 turns its row RED"; fi
}
if mutate M1 "$SB/m1.md" <<'PERL'; then
s{\z}{\nterraform state push -force backup.tfstate\n}
PERL
  expect_red "M1 (state push line added)" row_r1 "$SB/m1.md"
fi
if mutate M2 "$SB/m2.md" <<'PERL'; then
s{(   git fetch origin main\n)}{   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='#12931 reopen'\n$1}
PERL
  expect_red "M2 (manual-rerun moved above the reads)" row_r2 "$SB/m2.md"
fi
if mutate M3 "$SB/m3.md" <<'PERL'; then
s{(\*\*Reopen the routine path\*\*.*?)`cloudflare_ruleset\.cache_shared_binaries` create}{$1cache rule}s;
s{(\*\*Reopen the routine path\*\*.*?)`cloudflare_ruleset\.cache_shared_binaries` create}{$1cache rule}s
PERL
  expect_red "M3 (reopen cache_shared_binaries create dropped)" row_r3 "$SB/m3.md"
fi
if mutate M4 "$SB/m4.md" <<'PERL'; then
s{`branch-copies-tokens`}{`branch-copy-tokens`}g
PERL
  expect_red "M4 (a stage renamed in the runbook)" row_r4 "$SB/m4.md"
fi
if mutate M5 "$SB/m5.md" <<'PERL'; then
s{probe=<phase> verdict=pass}{probe=<phase> verdict=authorized}
PERL
  expect_red "M5 (verdict=authorized reintroduced)" row_r5 "$SB/m5.md"
fi

TOTAL=$((PASS + FAIL)); FLOOR=18
if [[ "$TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$TOTAL" "$FLOOR" >&2
  echo "Total: ${TOTAL} assertions, $((FAIL + 1)) failed"; exit 1
fi
echo "Total: ${TOTAL} assertions, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
