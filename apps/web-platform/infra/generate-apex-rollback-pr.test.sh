#!/usr/bin/env bash
# generate-apex-rollback-pr.test.sh — unit tests for the ADR-194 apex rollback
# generator (#7640 PR4b, plan 4b.2 / AC70).
#
# The strongest assertion, per AC70, is that the generated `dns.tf` returns to
# `dns.tf` as PR4a left it — a state that actually shipped, so the claim is
# checkable rather than self-referential.
#
# AC70 asks for that byte-identity AND for a reverse `moved` block, which cannot
# both hold literally: PR4a's file carries no `moved` block. The block is not
# optional — without it the rollback emits exactly the two-address plan that
# `git revert` produces, i.e. the 81053 collision in reverse. So the guarantee
# under test is byte-identity MODULO that block, asserted through the generator's
# own `--emit-tf-stripped` mode, plus a separate assertion that the only
# difference between the two modes IS the block.
#
# REFUSALS ARE ASSERTED, NOT ASSUMED. A generator that emits confidently against
# the wrong tree is worse than one that refuses: its output looks like a correct
# rollback and gets applied during an incident. Each refusal is fixtured alone,
# in the direction where a missing check would emit rather than abort.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/generate-apex-rollback-pr.sh"
BASELINE="$SCRIPT_DIR/fixtures/dns.tf.pr4a-baseline"
LIVE="$SCRIPT_DIR/dns.tf"

[[ -x "$GEN" ]]      || { printf '[FATAL] generator not executable: %s\n' "$GEN" >&2; exit 2; }
[[ -r "$BASELINE" ]] || { printf '[FATAL] baseline missing: %s\n' "$BASELINE" >&2; exit 2; }
[[ -r "$LIVE" ]]     || { printf '[FATAL] dns.tf missing: %s\n' "$LIVE" >&2; exit 2; }

# TMPDIR default: a direct invocation of this suite inherits the bare /tmp, a
# machine-global tmpfs shared by every parallel worktree. The registered runners
# set /var/tmp; this makes the direct loop match them.
export TMPDIR="${TMPDIR:-/var/tmp}"
SBX="$(mktemp -d -t apex-rollback-gen.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SBX"' EXIT INT TERM HUP

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi; }

# INSTRUMENT SELF-TEST (ADR-193): drive the WRAPPER's both arms once each and
# refuse to continue unless both counters moved. A wrapper rewritten to send
# every verdict to the PASS arm is the mutation a helper-level control misses.
_p0=$PASS; _f0=$FAIL; _c0=$CASES
verdict 0 "instrument self-test: the PASS arm records"
verdict 1 "instrument self-test: the FAIL arm records (EXPECTED — subtracted below)"
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) || "$CASES" -ne $((_c0 + 2)) ]]; then
  printf '[FATAL] instrument self-test: verdict did not route both arms\n' >&2; exit 2
fi
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); CASES=$((CASES - 2))

run_gen() { # <dns.tf> <baseline> <args...>
  local d="$1" b="$2"; shift 2
  env APEX_ROLLBACK_DNS_TF="$d" APEX_ROLLBACK_BASELINE="$b" bash "$GEN" "$@" >"$SBX/out.txt" 2>&1
  printf '%s' "$?"
}

# ---------------------------------------------------------------------------------------
# THE BYTE-IDENTITY CONTRACT (AC70)
# ---------------------------------------------------------------------------------------
rc="$(run_gen "$LIVE" "$BASELINE" --emit-tf-stripped "$SBX/rollback-stripped.tf")"
verdict "$rc" "the generator emits a stripped rollback dns.tf (exit $rc)"

if cmp -s "$SBX/rollback-stripped.tf" "$BASELINE"; then rc=0; else rc=1; fi
verdict "$rc" "AC70: the rollback dns.tf, minus the reverse moved block, is BYTE-IDENTICAL to dns.tf as PR4a left it"

rc="$(run_gen "$LIVE" "$BASELINE" --emit-tf "$SBX/rollback.tf")"
verdict "$rc" "the generator emits the full rollback dns.tf (exit $rc)"

# The ONLY difference between the two modes must be the reverse block — a
# generator that also mutated a record while emitting would satisfy the stripped
# comparison above and still ship a wrong rollback.
only_added="$(diff "$BASELINE" "$SBX/rollback.tf" | grep -cE '^[<>]' || true)"
removed="$(diff "$BASELINE" "$SBX/rollback.tf" | grep -cE '^<' || true)"
rc=1; [[ "$removed" == "0" && "$only_added" -gt 0 ]] && rc=0
verdict "$rc" "the full rollback differs from the baseline by ADDITIONS ONLY (removed lines: $removed)"

# ---------------------------------------------------------------------------------------
# THE REVERSE BLOCK ITSELF — the half that makes this not a `git revert`
# ---------------------------------------------------------------------------------------
rc=1; grep -qE '^  from = cloudflare_record\.pages_apex$' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the reverse moved block moves FROM cloudflare_record.pages_apex"

rc=1; grep -qE '^  to   = cloudflare_record\.github_pages\["185\.199\.108\.153"\]$' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the reverse moved block moves TO the survivor key the forward cutover moved from"

# Direction matters and is the whole point: a block with the endpoints the RIGHT
# way round for the forward cutover is a no-op here, and the rollback would then
# be the two-address plan.
rc=0; grep -qE '^  from = cloudflare_record\.github_pages' "$SBX/rollback.tf" && rc=1
verdict "$rc" "the rollback carries NO forward-direction moved block (endpoints are swapped, not duplicated)"

# ---------------------------------------------------------------------------------------
# THE RESTORED RECORDS
# ---------------------------------------------------------------------------------------
rc=1; grep -qE '^resource "cloudflare_record" "github_pages" \{' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the rollback restores cloudflare_record.github_pages"

rc=0; grep -qE '^resource "cloudflare_record" "pages_apex" \{' "$SBX/rollback.tf" && rc=1
verdict "$rc" "the rollback declares no cloudflare_record.pages_apex (the address it moves away from)"

rc=1; grep -qE '^  type    = "A"$' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the apex returns to type A"

rc=1; grep -qF 'content = "jikig-ai.github.io"' "$SBX/rollback.tf" && rc=0
verdict "$rc" "www returns to the GitHub Pages origin"

rc=0; grep -qF 'cloudflare_pages_project.docs.subdomain' "$SBX/rollback.tf" && rc=1
verdict "$rc" "no reference to the Pages project survives the rollback"

# HCL VALIDITY. A rollback that does not parse is discovered during the incident.
if command -v terraform >/dev/null; then
  cp "$SBX/rollback.tf" "$SBX/fmtcheck.tf"
  if terraform fmt -check "$SBX/fmtcheck.tf" >/dev/null 2>&1; then rc=0; else rc=1; fi
  verdict "$rc" "the generated rollback is canonically formatted HCL (terraform fmt -check)"
else
  verdict 1 "terraform is unavailable — the generated rollback's HCL validity was NOT checked"
fi

# DETERMINISM. Two runs must agree, or the rollback PR's diff is unreviewable.
run_gen "$LIVE" "$BASELINE" --emit-tf "$SBX/rollback2.tf" >/dev/null
if cmp -s "$SBX/rollback.tf" "$SBX/rollback2.tf"; then rc=0; else rc=1; fi
verdict "$rc" "the generator is deterministic across runs"

# ---------------------------------------------------------------------------------------
# THE ACK (AC53) — asserted in the COMMIT BODY, which is where it must land
# ---------------------------------------------------------------------------------------
rc="$(run_gen "$LIVE" "$BASELINE" --emit-commit-msg "$SBX/msg.txt")"
verdict "$rc" "the generator emits a rollback commit message (exit $rc)"

rc=1; grep -qE '^\[ack-destroy\]$' "$SBX/msg.txt" && rc=0
verdict "$rc" "[ack-destroy] is on its OWN line in the commit body (a squash message carries the body, and gh pr view --json cannot see it)"

# ---------------------------------------------------------------------------------------
# REFUSALS — each fixtured ALONE, in the direction where a missing check EMITS
# ---------------------------------------------------------------------------------------
cp "$BASELINE" "$SBX/preflip.tf"
rc="$(run_gen "$SBX/preflip.tf" "$BASELINE" --emit-tf "$SBX/never.tf")"
r2=1; [[ "$rc" != "0" ]] && grep -q 'not post-flip' "$SBX/out.txt" && r2=0
verdict "$r2" "refuses when dns.tf is not post-flip (nothing to roll back); exit $rc"

# A FULLY post-flip baseline is caught by the `github_pages`-absent check, which
# runs first — so it exercises THAT arm, not the pages_apex one. Asserting the
# message rather than just the exit code is what surfaced the ordering: an
# exit-code-only row would have reported this as covering a check it never
# reached.
cp "$LIVE" "$SBX/postflip-baseline.tf"
rc="$(run_gen "$LIVE" "$SBX/postflip-baseline.tf" --emit-tf "$SBX/never.tf")"
r2=1; [[ "$rc" != "0" ]] && grep -q 'not the shape PR4a left' "$SBX/out.txt" && r2=0
verdict "$r2" "refuses when the baseline is fully post-flip (caught by the github_pages-absent arm); exit $rc"

# The pages_apex arm is reachable only for a PARTIALLY migrated baseline — one
# carrying BOTH declarations. Without this fixture that check is dead code that
# reads as protective, so the row exists to keep it reachable and proven.
{ cat "$BASELINE"; printf '\nresource "cloudflare_record" "pages_apex" {\n  type = "CNAME"\n}\n'; } > "$SBX/hybrid-baseline.tf"
rc="$(run_gen "$LIVE" "$SBX/hybrid-baseline.tf" --emit-tf "$SBX/never.tf")"
r2=1; [[ "$rc" != "0" ]] && grep -q 'post-flip, not the PR4a shape' "$SBX/out.txt" && r2=0
verdict "$r2" "refuses when the baseline carries BOTH declarations (the partially-migrated shape); exit $rc"

# A baseline whose survivor key disagrees with the cutover's would `moved` into
# an address absent from state — the same silent no-op the forward guard exists
# for, reproduced by the rollback.
sed 's/185\.199\.108\.153/185.199.111.153/g' "$BASELINE" > "$SBX/wrongkey-baseline.tf"
rc="$(run_gen "$LIVE" "$SBX/wrongkey-baseline.tf" --emit-tf "$SBX/never.tf")"
r2=1; [[ "$rc" != "0" ]] && grep -q 'baseline and cutover disagree' "$SBX/out.txt" && r2=0
verdict "$r2" "refuses when the baseline's survivor key disagrees with the one dns.tf moves from; exit $rc"

grep -v 'from = cloudflare_record.github_pages' "$LIVE" > "$SBX/nomoved.tf"
rc="$(run_gen "$SBX/nomoved.tf" "$BASELINE" --emit-tf "$SBX/never.tf")"
r2=1; [[ "$rc" != "0" ]] && grep -q 'cannot determine the rollback target' "$SBX/out.txt" && r2=0
verdict "$r2" "refuses when dns.tf carries no forward moved block to invert; exit $rc"

rc="$(run_gen "$SBX/definitely-absent.tf" "$BASELINE" --emit-tf "$SBX/never.tf")"
r2=1; [[ "$rc" != "0" ]] && grep -q 'not readable' "$SBX/out.txt" && r2=0
verdict "$r2" "refuses when dns.tf is unreadable; exit $rc"

r2=1; [[ ! -e "$SBX/never.tf" ]] && r2=0
verdict "$r2" "no refusal path wrote an output file (a refusal that still emits is not a refusal)"

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR AND ACCOUNTING (AP-023 / ADR-193)
# ---------------------------------------------------------------------------------------
# Reported with printf >&2 + exit 1, never through this suite's own `fail` — a
# floor routed through `fail` is disarmed by the same edit that disarms every
# assertion it witnesses.
printf '\n'
EXPECTED_CASES=23
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] %d case(s) ran, expected exactly %d — a case was deleted, skipped or added without bumping the floor\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$((PASS + FAIL))" -ne "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d != CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

printf 'generate-apex-rollback-pr: %d passed, %d failed (%d cases)\n' "$PASS" "$FAIL" "$CASES"
[[ "$FAIL" -eq 0 ]] || exit 1
