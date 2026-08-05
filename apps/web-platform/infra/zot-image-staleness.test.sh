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
# error across a two-row table — the pull FAILS and THE SOLE PULL PATH GOES DARK.
#
# MECHANISM, MEASURED 2026-08-05 (an earlier version of this comment had it wrong and said
# `exec format error`): zot-linux-amd64 and zot-linux-arm64 are DISTINCT OCI REPOSITORIES,
# and a manifest digest resolves only within its own repository. Probed anonymously against
# ghcr.io — amd64-repo <- amd64 digest = HTTP 200; amd64-repo <- arm64 digest = HTTP 404
# MANIFEST_UNKNOWN. So no wrong-arch binary is ever executed: `docker pull` 404s, the
# container is never created, and the host reports `zot_image_digest=unknown
# state_status=unknown`. Same outage, different on-host signature — and the signature is
# what an operator greps for, so getting it wrong sends them hunting the wrong telemetry.
#
# WHAT THESE CHECKS DO AND DO NOT COVER. A set-membership or alternation formulation ("both
# digests appear in both files") passes a swap; arch-keying does not, so checks 2/4/5 catch a
# swap confined to ONE file. They CANNOT catch a swap applied coherently to BOTH the .tf and
# the sidecar — nothing in the committed file set binds a digest to an arch, because a digest
# carries no intrinsic arch information. That case is caught over the network by the
# digest<->repository probe in rule-audit.yml's poll step. Do not read these checks as
# closing the whole class; they close the half that is closable offline.
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
MIN_ASSERTIONS=15

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# A detector failure is NOT a drift verdict — exit 2 so the cron can tell "I could not
# check" from "I checked and it is stale". Silence here would read as freshness.
die_detector() { echo "  DETECTOR-FAILURE: $1" >&2; echo "RESULT: $PASS passed, $FAIL failed (detector failure)"; exit 2; }

# POSITIVE CONTROL. MIN_ASSERTIONS counts PASS+FAIL, so neutering fail() ALONE leaves the
# count intact (every check still calls pass()) while the gate becomes permanently incapable
# of reporting drift — green forever, floor satisfied. Measured; the floor does not close it.
# A count cannot detect this from the inside, so prove both counters move before trusting any
# verdict, then reset. This is the same discipline as asserting a mutation LANDED.
_ctl_p="$PASS"; _ctl_f="$FAIL"
pass "self-test" >/dev/null 2>&1; fail "self-test" >/dev/null 2>&1
if [[ "$PASS" -ne $((_ctl_p + 1)) || "$FAIL" -ne $((_ctl_f + 1)) ]]; then
  echo "  DETECTOR-FAILURE: the assertion counters do not increment (pass/fail neutered) -- every verdict from this run would be meaningless" >&2
  exit 2
fi
PASS="$_ctl_p"; FAIL="$_ctl_f"

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
  fail "amd64 and arm64 digests are IDENTICAL ($tf_digest_amd64) -- one arch's digest was pasted into both slots; that digest does not exist in the other arch's OCI repository, so the pull 404s (MANIFEST_UNKNOWN), no container is created, and the sole pull path goes dark"
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
# FILE-WIDE + head -1 was a FAIL-OPEN, and the only one in this gate that failed toward
# FRESH. Every digest read here is awk-section-scoped precisely because a sibling section
# carries look-alike references -- the freshness signal got no such scoping. Measured: add a
# `## Bump log` section above the header table carrying its own capture-date row, back-date
# the real one to 2025-01-01, and the gate reports `capture age 0d`. A bump log is exactly
# what someone adds to a sidecar that documents bumps, so this is a plausible edit, not a
# contrived one -- and it bypasses the sidecar's own "do not re-stamp to clear a red gate"
# warning without anyone re-stamping anything.
#
# Two changes: scope to the header table, and REFUSE on more than one row anywhere in the
# file. A second capture-date row is never legitimate; silently preferring the first is the bug.
cap_rows="$(grep -cE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PROV" || true)"
if [[ "$cap_rows" -gt 1 ]]; then
  die_detector "found $cap_rows 'Capture date (UTC)' rows in $PROV -- exactly one is legitimate; a second shadows the freshness attestation"
fi
header_table="$(awk '/^\| Field \| Value \|/{f=1} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
capture_date="$(printf '%s\n' "$header_table" | grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
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
# A follower that still EXISTS but whose claim was reworded (`zot version 2.1.20`, `the
# pinned zot`) yields zero loop iterations, an empty stale_claims, and a PASS whose text
# asserts coverage -- "3/3 files examined" counts FILES OPENED, not CLAIMS MATCHED. Zero
# claims examined read as full coverage, which is the vacuous-green class one level down
# from the MIN_ASSERTIONS floor. The two locations the sidecar's version-scoped claim
# register names MUST each carry at least one claim.
required_claim_locations=("$DIR/ci-deploy.sh" "$DIR/cloud-init-registry.yml")
missing_claims=""
for f in "${required_claim_locations[@]}"; do
  [[ -f "$f" ]] || continue   # absence already failed above
  n_hits="$(grep -cE 'zot \(?v[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null || true)"
  [[ "$n_hits" -ge 1 ]] || missing_claims+="    $(basename "$f"): 0 version-scoped claims found"$'\n'
done
if [[ "$followers_seen" -ne "${#followers[@]}" ]]; then
  : # already failed above; do not also emit a misleading clean verdict
elif [[ -n "$missing_claims" ]]; then
  fail "a registered version-scoped claim location carries NO 'zot vX.Y.Z' claim -- either the claim was reworded (this guard cannot see the new phrasing; widen it) or the sidecar's claim register is stale:"$'\n'"$missing_claims"
elif [[ -z "$stale_claims" ]]; then
  pass "all 'zot vX.Y.Z' capability claims name the pinned version (${#required_claim_locations[@]} registered locations each carry >=1 claim)"
else
  fail "version-scoped claims name a version we no longer pin:"$'\n'"$stale_claims    These are MEASUREMENTS, not inferences -- re-measure by running the pinned image locally (see '## Bump procedure'), do not just re-word them"
fi

# --- 8. Previous known-good pin (the rollback target) --------------------------------
# AC1 deliberately erases the superseded digests from the .tf, so without this row the
# rollback target survives only in git history -- a git-archaeology exercise under incident
# pressure on a host with no shell. See the plan's section 'Rollback'.
prev_section="$(awk '/^## Previous known-good pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
# ARCH-KEYED, like check 5 -- `head -1` over the whole section read the amd64 row only
# because of table ROW ORDER, and never read arm64 at all. Measured: transposing the two
# Reference cells, or copying amd64's digest onto the arm64 row, or setting arm64's previous
# to its CURRENT pin, were all green. This is the rollback artifact, consulted under incident
# pressure on a host with no shell -- half-guarding it is the same set-membership mistake the
# header calls the entire point of these checks.
prev_ref_for() { printf '%s\n' "$prev_section" | grep -oE "zot-linux-$1@sha256:[0-9a-f]{64}" | head -1 || true; }
for arch in amd64 arm64; do
  prev_d="$(prev_ref_for "$arch" | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
  cur_d="$(eval printf '%s' "\$tf_digest_$arch")"
  if [[ -z "$prev_d" ]]; then
    fail "no '## Previous known-good pin' entry for $arch in $PROV -- the rollback target for this arch does not survive the bump that erases it from the .tf"
  elif [[ "$prev_d" == "$cur_d" ]]; then
    fail "'## Previous known-good pin' records the SAME $arch digest as the current pin ($prev_d) -- not rotated on the last bump, so there is no rollback target for $arch"
  else
    pass "previous known-good $arch pin recorded and distinct from the current pin"
  fi
done

# --- 9. The ARCH SELECTOR itself ------------------------------------------------------
# Checks 2-5 guard the two VALUES. Nothing guarded the line that CHOOSES between them, so
# inverting the ternary -- or replacing it with a bare literal, e.g. a rollback someone
# forgot to revert -- reached the identical outage with all assertions green. Whole-string
# grep -qF, the same discipline registry-boot-guard.test.sh uses for the docker-inspect
# template: a per-field or regex form would let a REORDERING through, which is the failure.
SELECTOR='zot_image                = local.registry_arch == "arm64" ? local.zot_image_arm64 : local.zot_image_amd64'
if grep -qF "$SELECTOR" "$TF"; then
  pass "the arch selector is byte-exact (registry_arch chooses the matching arch's local)"
else
  fail "local.zot_image is not the expected selector. Expected exactly:  $SELECTOR  -- an inverted ternary or a hardcoded local reaches the same outage as a digest swap while every other assertion here stays green. If this changed deliberately, update SELECTOR in this gate in the same commit."
fi

# --- 10. Version FLOOR --------------------------------------------------------------
# Every check above is a COHERENCE check. Measured: a coherent downgrade of every file back
# to v2.1.2 -- the exact 18-releases-stale state this whole change exists to escape -- was
# green, because coherence is preserved by a downgrade. The one age signal reads a
# human-typed date the sidecar's own Refresh recipe sanctions re-stamping, so re-stamping
# every 89 days keeps a stale pin green forever. The sidecar declares a hard floor; read it.
floor="$(grep -oE 'Do not fall back below v[0-9]+\.[0-9]+\.[0-9]+' "$PROV" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ -z "$floor" ]]; then
  fail "could not parse the version floor ('Do not fall back below vX.Y.Z.') from $PROV -- the floor is what makes a coherent DOWNGRADE detectable offline"
elif [[ "$(printf '%s\n%s\n' "${floor#v}" "${tf_ver_amd64#v}" | sort -V | head -1)" != "${floor#v}" ]]; then
  fail "pinned version $tf_ver_amd64 is BELOW the sidecar's declared floor $floor -- a coherent downgrade is still a downgrade; every coherence check above passes on one"
else
  pass "pinned version $tf_ver_amd64 is at or above the declared floor $floor"
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
