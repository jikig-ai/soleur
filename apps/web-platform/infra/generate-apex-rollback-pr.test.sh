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
# THE SAFETY CONTRACT: THE ROLLBACK TOUCHES THE APEX AND NOTHING ELSE
# ---------------------------------------------------------------------------------------
# This replaces an earlier byte-identity-to-the-baseline assertion that was
# TAUTOLOGICAL: `emit_tf` was `cp "$BASELINE" "$out"`, and the row then asserted
# `cmp "$out" "$BASELINE"` — i.e. that `cp` copies. It could not see a baseline
# that had drifted from the file PR4a shipped, and the generator it certified
# would revert the WHOLE of dns.tf to a frozen snapshot, deleting every record
# merged since (app.soleur.ai, the Protonmail MX/DKIM set, DMARC, DNSSEC) under
# a pre-baked [ack-destroy].
#
# The property that actually matters is scope: every declaration live in dns.tf
# survives the rollback except the apex address being moved.
rc="$(run_gen "$LIVE" "$BASELINE" --emit-tf "$SBX/rollback.tf")"
verdict "$rc" "the generator emits the full rollback dns.tf (exit $rc)"

live_labels="$(grep -oE '^resource "[a-z_]+" "[a-z_0-9]+"' "$LIVE" | grep -v '"pages_apex"' | sort -u)"
gen_labels="$(grep -oE '^resource "[a-z_]+" "[a-z_0-9]+"' "$SBX/rollback.tf" | sort -u)"
dropped="$(comm -23 <(printf '%s\n' "$live_labels") <(printf '%s\n' "$gen_labels"))"
rc=1; [[ -z "$dropped" ]] && rc=0
verdict "$rc" "every non-apex declaration live in dns.tf survives the rollback (dropped: ${dropped//$'\n'/ })"

# THE REGRESSION THAT MOTIVATED THE REWRITE, fixtured directly: a record added
# after PR4b must still be present in a rollback generated later. Under the old
# whole-file copy this record simply vanished, and the generated commit carried
# [ack-destroy], so Terraform destroyed it without a gate.
{ cat "$LIVE"; printf '\nresource "cloudflare_record" "added_after_pr4b" {\n  zone_id = var.cf_zone_id\n  name    = "newthing"\n  content = "192.0.2.7"\n  type    = "A"\n  proxied = false\n  ttl     = 1\n}\n'; } > "$SBX/live-plus-one.tf"
rc="$(run_gen "$SBX/live-plus-one.tf" "$BASELINE" --emit-tf "$SBX/rollback-plus-one.tf")"
r2=1; [[ "$rc" == "0" ]] && grep -qE '^resource "cloudflare_record" "added_after_pr4b"' "$SBX/rollback-plus-one.tf" && r2=0
verdict "$r2" "a record added AFTER the cutover survives the rollback (the whole-file-copy regression)"

# THE BASELINE IS ANCHORED TO THE COMMIT PR4a SHIPPED, not to whatever the file
# happens to contain. Without this the fixture is its own oracle: truncate it or
# delete a record from it and every other row here still passes.
PR4A_SHA="428e1ec78a23b2d4425a5f48d170eefb777d37e3"
if git -C "$SCRIPT_DIR" cat-file -e "$PR4A_SHA:apps/web-platform/infra/dns.tf" 2>/dev/null; then
  if git -C "$SCRIPT_DIR" show "$PR4A_SHA:apps/web-platform/infra/dns.tf" | cmp -s - "$BASELINE"; then rc=0; else rc=1; fi
  verdict "$rc" "the baseline fixture is byte-identical to dns.tf as PR4a ($PR4A_SHA) shipped it"
else
  # A shallow clone cannot reach the blob. That is a coverage gap, not a pass —
  # never let "could not look" read as "looked and it was fine".
  verdict 1 "the PR4a blob is unreachable in this checkout — the baseline's provenance was NOT verified (fetch depth?)"
fi

# ---------------------------------------------------------------------------------------
# THE REVERSE BLOCK ITSELF — the half that makes this not a `git revert`
# ---------------------------------------------------------------------------------------
rc=1; grep -qE '^  from = cloudflare_record\.pages_apex$' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the reverse moved block moves FROM cloudflare_record.pages_apex"

# The restored resource carries NO `for_each` — that meta-argument was an
# artifact of the pre-PR4a four-address config — so the reverse move targets a
# plain address. That keeps the rollback a single-address replace, exactly as
# the forward cutover was.
rc=1; grep -qE '^  to   = cloudflare_record\.github_pages$' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the reverse moved block moves TO a single-address cloudflare_record.github_pages"

rc=1; grep -qE '^  content = "185\.199\.108\.153"$' "$SBX/rollback.tf" && rc=0
verdict "$rc" "the restored record carries the survivor IP as a literal"

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

# SCOPED to the github_pages block. A bare `type = "A"` matches cloudflare_record.app
# (the web-1 ingress) too, so the unscoped form passed on a record the rollback
# has nothing to do with.
rc=1
awk '/^resource "cloudflare_record" "github_pages"/,/^}/' "$SBX/rollback.tf" \
  | grep -qE '^  type    = "A"$' && rc=0
verdict "$rc" "the apex record itself returns to type A"

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
# 26 `verdict` calls execute per run — 30 are written, but the terraform-present
# and PR4a-blob-reachable forks each contribute one of their two rows — minus the
# 2 instrument self-test rows the harness subtracts above.
EXPECTED_CASES=24
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
