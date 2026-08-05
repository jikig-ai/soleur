#!/usr/bin/env bash
# Freshness + coherence gate for the pinned zot registry image (#7282, ADR-096).
#
# WHY THIS EXISTS: zot is the SOLE pull path since ADR-096's 2026-07-30 amendment — no
# fallback. The pin sat at v2.1.2 (2025-01-17) for 18 releases because the file's only
# freshness mechanism was a prose comment telling a human to run `crane digest`. This gate
# is the enforcement half of the replacement; the detection half is the upstream poll in
# .github/workflows/rule-audit.yml. Neither works alone: a poll with no gate lets the
# analysis rot, and a gate with no poll never notices upstream moving.
#
# WHY ARCH-KEYED (checks 2/4/5): zot-registry.tf selects with
#   local.registry_arch == "arm64" ? local.zot_image_arm64 : local.zot_image_amd64
# and registry_arch is amd64 today. If the two digests are SWAPPED — a trivial copy-paste
# error across a two-row table — the amd64 host pulls the arm64 binary, execs it, gets
# `exec format error`, zot never answers /v2/, cloud-init's readiness loop never completes,
# and THE SOLE PULL PATH GOES PERMANENTLY DARK. A set-membership or alternation
# formulation ("both digests appear in both files") passes a swap. Arch-keying is the
# entire point of these checks, not a stylistic preference. Do not "simplify" them.
#
# NO NETWORK, BY DESIGN. `crane digest` cross-checks are a documented sidecar procedure and
# a /work Phase 0 step, not a test dependency — a test that needs the network reddens on
# upstream's outage. Everything here reads committed files only.
#
# EXIT CODES (the cron step in rule-audit.yml discriminates on these; do not overload 1):
#   0  — fresh and coherent
#   10 — DRIFT: stale or incoherent (the actionable "a human must look" signal)
#   2  — DETECTOR FAILURE: inputs missing/unparseable. Never conflated with "fresh".
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/zot-registry.tf"
PROV="$DIR/zot-image.provenance.md"

# Upstream's recent release interval is ~30 days (v2.1.15 2026-03-08 -> v2.1.20 2026-08-04,
# 5 releases) and the rule-audit.yml poll runs on the 1st and 15th, so 90 days is ~3
# upstream releases and ~6 poll firings: a genuine stall, not routine lag.
MAX_AGE_DAYS=90

# ANTI-VACUITY FLOOR. Without this the terminal contract is `[[ "$FAIL" -eq 0 ]]`, so a gate
# whose assertions all silently stop running prints `RESULT: 0 passed, 0 failed` and exits 0 —
# CI green having checked NOTHING. Measured during review of this very file: neutering pass()
# and fail() to no-ops produced exactly that.
#
# The accompanying mutation battery cannot catch this class by construction: every mutation it
# applies perturbs this gate's INPUTS (the .tf, the sidecar, a follower file), so all of them
# are observed through the assertion layer. Nothing it does removes the assertion layer itself.
#
# A FLOOR, not equality. `-eq` would turn every legitimately-added assertion into a spurious
# failure, which trains people to edit the number without thinking — the opposite of a guard.
# Raise it in lockstep when assertions are added; never lower it to make a red run green.
MIN_ASSERTIONS=12

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# A detector failure is NOT a drift verdict — exit 2 so the cron can tell "I could not
# check" from "I checked and it is stale". Silence here would read as freshness.
die_detector() { echo "  DETECTOR-FAILURE: $1" >&2; echo "RESULT: $PASS passed, $FAIL failed (detector failure)"; exit 2; }

echo "--- zot image pin staleness + coherence gate (#7282) ---"

# --- 1. Inputs present -------------------------------------------------------------
[[ -s "$TF" ]]   || die_detector "zot-registry.tf missing/empty at $TF"
pass "zot-registry.tf present"
[[ -s "$PROV" ]] || die_detector "provenance sidecar missing/empty at $PROV (create zot-image.provenance.md)"
pass "provenance sidecar present"

# --- helpers ------------------------------------------------------------------------
# terraform fmt re-aligns '=' when a block gains an attribute, so match [[:space:]]* around
# it rather than a single space -- a single-space anchor goes blind after the next fmt.
tf_ref_for() { # $1=arch -> the full pinned reference for that arch's OWN local
  grep -oE "^[[:space:]]*zot_image_$1[[:space:]]*=[[:space:]]*\"ghcr\.io/project-zot/zot-linux-$1:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}\"" "$TF" 2>/dev/null || true
}
tf_ref_count() { # count of well-formed, arch-keyed pins for $1 (must be exactly 1)
  tf_ref_for "$1" | grep -c . 2>/dev/null || true
}

# --- 2. Pin form, per arch, ARCH-KEYED, exactly once --------------------------------
# The arch in the local's NAME must equal the arch in its VALUE. Exactly-once is the
# decoy-in-a-comment guard (cf. scripts/lib/in-image-copy-src.test.sh check 9): a
# commented-out pin must not satisfy the assertion.
for arch in amd64 arm64; do
  n="$(tf_ref_count "$arch")"
  if [[ "$n" == "1" ]]; then
    pass "zot_image_$arch is a well-formed arch-keyed tag+digest pin (exactly 1)"
  else
    fail "zot_image_$arch: expected exactly 1 arch-keyed pin matching zot-linux-$arch:vX.Y.Z@sha256:<64hex>, found $n -- re-run crane digest for both arches, re-read the changelog since the pinned version, and stamp $PROV (see its '## Bump procedure')"
  fi
done

tf_digest_amd64="$(tf_ref_for amd64 | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
tf_digest_arm64="$(tf_ref_for arm64 | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
tf_ver_amd64="$(tf_ref_for amd64 | grep -oE ':v[0-9]+\.[0-9]+\.[0-9]+@' | tr -d ':@' | head -1 || true)"
tf_ver_arm64="$(tf_ref_for arm64 | grep -oE ':v[0-9]+\.[0-9]+\.[0-9]+@' | tr -d ':@' | head -1 || true)"

# --- 3. Cross-arch VERSION coherence ------------------------------------------------
# Catches a half-landed bump where only one arch moved (upstream sometimes publishes one
# arch minutes before the other).
if [[ -n "$tf_ver_amd64" && "$tf_ver_amd64" == "$tf_ver_arm64" ]]; then
  pass "both arches pin the same version ($tf_ver_amd64)"
else
  fail "cross-arch version mismatch: amd64='$tf_ver_amd64' arm64='$tf_ver_arm64'. If upstream has published only one arch, WAIT for the other -- do NOT stamp the sidecar with mismatched arches"
fi

# --- 4. Cross-arch DIGEST distinctness ----------------------------------------------
# Two arches never share a manifest digest. Equality means one value was pasted into both
# slots, which boots the wrong-arch binary on whichever host loses the coin flip.
if [[ -n "$tf_digest_amd64" && "$tf_digest_amd64" != "$tf_digest_arm64" ]]; then
  pass "amd64 and arm64 digests are distinct"
else
  fail "amd64 and arm64 digests are IDENTICAL ($tf_digest_amd64) -- one arch's digest was pasted into both slots; the wrong-arch binary will exec-format-error and dark the registry"
fi

# --- sidecar section extraction ------------------------------------------------------
# Scope to the '## Current pin' section: '## Previous known-good pin' also carries
# zot-linux-<arch> references, so an unscoped grep would match either non-deterministically.
cur_section="$(awk '/^## Current pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
[[ -n "$cur_section" ]] || die_detector "could not find a '## Current pin' section in $PROV"

prov_ref_for() { # $1=arch -> that arch's reference inside the Current pin section only
  printf '%s\n' "$cur_section" | grep -oE "zot-linux-$1:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}" | head -1 || true
}
prov_digest_amd64="$(prov_ref_for amd64 | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
prov_digest_arm64="$(prov_ref_for arm64 | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
prov_ver="$(prov_ref_for amd64 | grep -oE ':v[0-9]+\.[0-9]+\.[0-9]+@' | tr -d ':@' | head -1 || true)"

# --- 5. Sidecar <-> pin coherence, ARCH-KEYED ---------------------------------------
# Two SEPARATE per-arch equalities, never set membership over the pair. Set membership
# ("both sidecar digests appear among both tf digests") is satisfied by a swap.
if [[ -n "$prov_digest_amd64" && "$prov_digest_amd64" == "$tf_digest_amd64" ]]; then
  pass "sidecar amd64 digest matches zot_image_amd64"
else
  fail "sidecar amd64 digest ('$prov_digest_amd64') != zot_image_amd64 ('$tf_digest_amd64') -- the pin moved without the analysis being redone; see '## Bump procedure' in $PROV"
fi
if [[ -n "$prov_digest_arm64" && "$prov_digest_arm64" == "$tf_digest_arm64" ]]; then
  pass "sidecar arm64 digest matches zot_image_arm64"
else
  fail "sidecar arm64 digest ('$prov_digest_arm64') != zot_image_arm64 ('$tf_digest_arm64') -- the pin moved without the analysis being redone; see '## Bump procedure' in $PROV"
fi
if [[ -n "$prov_ver" && "$prov_ver" == "$tf_ver_amd64" ]]; then
  pass "sidecar version matches the pinned version ($prov_ver)"
else
  fail "sidecar version ('$prov_ver') != pinned version ('$tf_ver_amd64')"
fi

# --- 6. Capture-age gate -------------------------------------------------------------
# Same row shape as cosign-trusted-root.provenance.md so the two sidecars share one format
# rather than each inventing its own.
capture_date="$(grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PROV" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
if [[ -z "$capture_date" ]]; then
  # Reported as DRIFT (exit 10), not as a detector failure (exit 2), and the distinction is
  # deliberate: an unparseable date is a defect in a COMMITTED file that a human fixes, which
  # is exactly what the idempotent issue is for -- unlike a missing input or a dead upstream
  # poll, which mean "I could not check". Either way it is non-zero: an unreadable date must
  # never be indistinguishable from a fresh one.
  fail "could not parse 'Capture date (UTC) | **YYYY-MM-DD**' from $PROV"
else
  cap_epoch="$(date -u -d "$capture_date" +%s 2>/dev/null || echo '')"
  now_epoch="$(date -u +%s)"
  if [[ -z "$cap_epoch" ]]; then
    fail "capture date '$capture_date' not parseable by date(1)"
  else
    age_days=$(( (now_epoch - cap_epoch) / 86400 ))
    if (( age_days < 0 )); then
      fail "capture date '$capture_date' is in the FUTURE (age=${age_days}d) -- check the sidecar"
    elif (( age_days > MAX_AGE_DAYS )); then
      # The remedy is an INVOCATION, not a description: re-reading an upstream Go changelog
      # and re-running the config-compat analysis is engineering work, and this repo's
      # operator is non-technical. Give the next reader an entry point they can actually run.
      fail "zot pin analysis is ${age_days}d old (> ${MAX_AGE_DAYS}d). Refresh it with:  /soleur:one-shot \"refresh the zot pin provenance sidecar per apps/web-platform/infra/zot-image.provenance.md section 'Bump procedure'\""
    else
      pass "zot pin analysis capture age ${age_days}d (<= ${MAX_AGE_DAYS}d)"
    fi
  fi
fi

# --- 7. Version-scoped capability claims must name the PINNED version ----------------
# The defect being fixed is `zot v2.1.2` hardcoded in prose that outlives the pin. That fix
# is one-shot and recurs at the next bump, so guard the followers rather than re-sweeping
# them by hand.
#
# The `\(?` is load-bearing, not defensive noise. The first version of this check anchored on
# a bare `zot v[0-9]...` and reported all-clear while ci-deploy.test.sh carried "reproduced
# against the pinned zot (v2.1.2)" — the PARENTHESIZED form, which the bare anchor cannot see.
# A guard that misses a live instance of the exact defect it was written for is worse than no
# guard, because its green is read as coverage. If a new phrasing appears, widen this shape.
followers=("$DIR/ci-deploy.sh" "$DIR/ci-deploy.test.sh" "$DIR/cloud-init-registry.yml")
stale_claims=""
followers_seen=0
for f in "${followers[@]}"; do
  # A MISSING follower is a detector failure, not a clean check. Without this the loop body
  # never runs, stale_claims stays empty, and the check reports PASS having examined nothing —
  # "found no stale claims" and "looked at no files" would be the same output.
  [[ -f "$f" ]] || { fail "follower file missing: $(basename "$f") -- cannot verify version-scoped claims"; continue; }
  followers_seen=$((followers_seen+1))
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    v="${hit##*zot }"; v="${v#(}"   # strip the optional opening paren
    [[ "$v" == "$tf_ver_amd64" ]] || stale_claims+="    $(basename "$f"): 'zot $v' (pinned is $tf_ver_amd64)"$'\n'
  done < <(grep -ohE 'zot \(?v[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null | sort -u || true)
done
if [[ "$followers_seen" -ne "${#followers[@]}" ]]; then
  : # already failed above; do not also emit a misleading clean verdict
elif [[ -z "$stale_claims" ]]; then
  pass "all 'zot vX.Y.Z' capability claims in ci-deploy.sh / ci-deploy.test.sh / cloud-init-registry.yml name the pinned version ($followers_seen/${#followers[@]} files examined)"
else
  fail "version-scoped claims name a version we no longer pin:"$'\n'"$stale_claims    These are MEASUREMENTS, not inferences -- re-measure by running the pinned image locally (see '## Bump procedure'), do not just re-word them"
fi

# --- 8. Previous known-good pin (the rollback target) --------------------------------
# AC1 deliberately erases the superseded digests from the .tf, so without this row the
# rollback target survives only in git history -- a git-archaeology exercise under incident
# pressure on a host with no shell. See the plan's section 'Rollback'.
prev_section="$(awk '/^## Previous known-good pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
prev_digest_amd64="$(printf '%s\n' "$prev_section" | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
if [[ -z "$prev_digest_amd64" ]]; then
  fail "no '## Previous known-good pin' section with a digest in $PROV -- the rollback target must survive the bump that erases it from the .tf"
elif [[ "$prev_digest_amd64" == "$tf_digest_amd64" ]]; then
  fail "'## Previous known-good pin' records the SAME digest as the current pin ($prev_digest_amd64) -- it was not rotated on the last bump, so there is no rollback target"
else
  pass "previous known-good pin recorded and distinct from the current pin"
fi

echo "RESULT: $PASS passed, $FAIL failed"

# Did the assertions actually RUN? A silent drop to zero checks is a DETECTOR failure (2), not
# a clean bill of health — "I asserted nothing" must never be reported as "nothing is wrong".
TOTAL=$((PASS + FAIL))
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "  DETECTOR-FAILURE: only $TOTAL assertion(s) ran, expected >= $MIN_ASSERTIONS -- checks were skipped or silently removed; this run proves nothing" >&2
  exit 2
fi

# 10 = drift (actionable). Reserved distinct from 1 so the rule-audit.yml cron step can tell
# "the pin is stale" from "the detector broke" (exit 2, above).
[[ "$FAIL" -eq 0 ]] || exit 10
