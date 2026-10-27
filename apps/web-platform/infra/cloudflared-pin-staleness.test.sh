#!/usr/bin/env bash
# Freshness + coherence gate for the pinned cloudflared release binary
# (2026-10-27 eMudhra intermediate-CA compromise remediation).
#
# WHY THIS EXISTS: cloudflared is the CI bridge client AND the prod tunnel
# connector. Cloudflare's 2026-10-20 advisory disclosed that eight eMudhra
# (emSign) intermediate CA private keys are compromised — any holder can mint
# certificates for any hostname, so a client that still trusts them is MITM'd.
# The repo pin sat at 2026.5.0 for ~5 months with NO freshness mechanism — the
# same gap class #7308/#7463 named for inngest and #7282 for zot. This gate is
# the enforcement half; the detection half is the `Detect cloudflared pin
# staleness` poll step in .github/workflows/rule-audit.yml. Neither works alone:
# a poll with no gate lets the analysis rot, and a gate with no poll never
# notices upstream moving.
#
# WHAT THESE CHECKS DO AND DO NOT COVER. They catch an incoherence confined to
# ONE file, a missing sidecar row, a stale capture date, and version-scoped
# claims that name a version we no longer pin. They CANNOT catch a pin+sidecar
# edited coherently to a wrong/older release — nothing in the committed file set
# binds a sha to upstream ground truth. Bounds on that hole: the rule-audit poll
# catches a coherent move (delta/age), and a wrong-sha pin dies at the bridge's
# own sha256sum verify (fail-closed, before any prod contact). Do not read these
# checks as closing the whole class; they close the half that is closable
# offline. Deliberately there is NO version floor here: a coherent two-file
# revert to the previous-known-good pin is the SANCTIONED rollback path (see the
# sidecar's '## Previous known-good pin'), and a floor would fight it. The
# advisory floor lives in scripts/cloudflared-compliance-probe.sh and the census
# monitor's client_version classifier instead. CROSS-SITE PARITY is also not
# re-asserted here — the terraform-target-parity census (Guard 1) pins every
# .github/ site equal to the canonical env pair read below.
#
# NO NETWORK, BY DESIGN. Asset re-hashes and release-list walks are a documented
# sidecar procedure and a /work step, not a test dependency — a test that needs
# the network reddens on upstream's outage. Everything here reads committed
# files only.
#
# EXIT CODES (the rule-audit.yml poll step discriminates on these; do not overload 1):
#   0  — fresh and coherent
#   10 — DRIFT: stale or incoherent (the actionable "a human must look" signal)
#   2  — DETECTOR FAILURE: inputs missing/unparseable. Never conflated with "fresh".
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
PROV="$DIR/cloudflared.provenance.md"

# cloudflared ships ~monthly (2026.5.0 -> 2026.10.4 spanned ~5 months at ~6
# releases) and the rule-audit.yml poll runs on the 1st and 15th, so 60 days is
# ~2 upstream releases and ~4 poll firings: a genuine stall, not routine lag.
# This is the backstop for the poll's OWN failure — the two mechanisms are
# different failures, not redundancy. Same number the inngest sibling carries.
MAX_AGE_DAYS=60

# ANTI-VACUITY FLOOR. Without this the terminal contract is `[[ "$FAIL" -eq 0 ]]`,
# so a gate whose assertions all silently stop running prints `RESULT: 0 passed,
# 0 failed` and exits 0 — CI green having checked NOTHING. A FLOOR, not equality:
# `-eq` would turn every legitimately-added assertion into a spurious failure.
# Raise it in lockstep when assertions are added; never lower it to make a red
# run green. The MIN_ASSERTIONS binding itself sits adjacent to the check at the
# bottom of the file — see the note there.
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# A detector failure is NOT a drift verdict — exit 2 so the poll can tell "I could
# not check" from "I checked and it is stale". Silence here would read as freshness.
die_detector() { echo "  DETECTOR-FAILURE: $1" >&2; echo "RESULT: $PASS passed, $FAIL failed (detector failure)"; exit 2; }

# POSITIVE CONTROL. MIN_ASSERTIONS counts PASS+FAIL, so neutering fail() ALONE
# leaves the count intact while the gate becomes permanently incapable of
# reporting drift — green forever, floor satisfied. Prove both counters move
# before trusting any verdict, then reset.
_ctl_p="$PASS"; _ctl_f="$FAIL"
pass "self-test" >/dev/null 2>&1; fail "self-test" >/dev/null 2>&1
if [[ "$PASS" -ne $((_ctl_p + 1)) || "$FAIL" -ne $((_ctl_f + 1)) ]]; then
  echo "  DETECTOR-FAILURE: the assertion counters do not increment (pass/fail neutered) -- every verdict from this run would be meaningless" >&2
  exit 2
fi
PASS="$_ctl_p"; FAIL="$_ctl_f"

echo "--- cloudflared pin staleness + coherence gate (eMudhra remediation) ---"

# --- 1. Inputs present -------------------------------------------------------------
[[ -s "$WF" ]]   || die_detector "canonical workflow missing/empty at $WF"
pass "apply-web-platform-infra.yml present"
[[ -s "$PROV" ]] || die_detector "provenance sidecar missing/empty at $PROV (create cloudflared.provenance.md)"
pass "provenance sidecar present"

# --- helpers ------------------------------------------------------------------------
# The `^[[:space:]]*` anchor is the decoy-in-a-comment guard: a whole-line comment
# (`# CLOUDFLARED_VERSION: …`) never satisfies it, and a second ACTIVE assignment
# fails the exactly-once count.
env_line_for() { # $1=env key -> the full assignment line(s) in the canonical workflow
  grep -nE "^[[:space:]]*$1[[:space:]]*:" "$WF" 2>/dev/null || true
}
env_line_count() { env_line_for "$1" | grep -c . 2>/dev/null || true; }

# --- 2. Canonical pin form, exactly once, well-formed --------------------------------
n_ver="$(env_line_count CLOUDFLARED_VERSION)"
if [[ "$n_ver" == "1" ]]; then
  pass "CLOUDFLARED_VERSION is assigned exactly once in the canonical workflow"
else
  fail "CLOUDFLARED_VERSION: expected exactly 1 active assignment in $WF, found $n_ver -- a commented-out pin is a decoy, not a hit; two active assignments are ambiguous"
fi
n_sha="$(env_line_count CLOUDFLARED_SHA256)"
if [[ "$n_sha" == "1" ]]; then
  pass "CLOUDFLARED_SHA256 is assigned exactly once in the canonical workflow"
else
  fail "CLOUDFLARED_SHA256: expected exactly 1 active assignment in $WF, found $n_sha"
fi

# cloudflared tags are BARE semver (2026.10.4) — no v prefix.
pin_ver="$(env_line_for CLOUDFLARED_VERSION | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | head -1 || true)"
pin_sha="$(env_line_for CLOUDFLARED_SHA256 | grep -oE '"[0-9a-f]{64}"' | tr -d '"' | head -1 || true)"

[[ "$pin_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && pass "CLOUDFLARED_VERSION is a well-formed bare semver ($pin_ver)" \
  || fail "CLOUDFLARED_VERSION value '$pin_ver' is not X.Y.Z"
[[ "$pin_sha" =~ ^[0-9a-f]{64}$ ]] \
  && pass "CLOUDFLARED_SHA256 is 64-hex" \
  || fail "CLOUDFLARED_SHA256 '$pin_sha' is not 64-hex"

# --- sidecar section extraction ------------------------------------------------------
# Scope to the '## Current pin' section: '## Previous known-good pin' also carries
# sha references, so an unscoped grep would match either non-deterministically.
cur_section="$(awk '/^## Current pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
[[ -n "$cur_section" ]] || die_detector "could not find a '## Current pin' section in $PROV"

prov_sha_for() { # $1=asset name -> that asset's 64-hex sha inside Current pin only
  printf '%s\n' "$cur_section" | grep -oE "\| *$1 *\| *\`[0-9a-f]{64}\`" | grep -oE '[0-9a-f]{64}' | head -1 || true
}
prov_sha_bin="$(prov_sha_for cloudflared-linux-amd64)"
prov_sha_deb="$(prov_sha_for cloudflared-linux-amd64\.deb)"
prov_ver="$(printf '%s\n' "$cur_section" | grep -oE '\*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' | tr -d '*' | head -1 || true)"

# --- 3. Sidecar <-> pin coherence -----------------------------------------------------
# The sidecar is the analysis of record; the workflow env pin FOLLOWS it; upstream
# is the poll's authority. Never print a remedy that reduces to "make the two
# files agree" — the coherent-fake hole is the poll's job.
if [[ -n "$prov_ver" && "$prov_ver" == "$pin_ver" ]]; then
  pass "sidecar current-pin version matches CLOUDFLARED_VERSION ($prov_ver)"
else
  fail "sidecar current-pin version ('$prov_ver') != CLOUDFLARED_VERSION ('$pin_ver') -- sidecar and the canonical pin disagree; the sidecar is authoritative -- update the pin or re-derive the sidecar (see '## Bump procedure' in $PROV)"
fi
if [[ -n "$prov_sha_bin" && "$prov_sha_bin" == "$pin_sha" ]]; then
  pass "sidecar cloudflared-linux-amd64 sha256 matches CLOUDFLARED_SHA256"
else
  fail "sidecar binary sha ('$prov_sha_bin') != CLOUDFLARED_SHA256 ('$pin_sha') -- sidecar and the canonical pin disagree; the sidecar is authoritative (see '## Bump procedure' in $PROV)"
fi
# The .deb row feeds the cloud-init install path — a bridge-only coherence check
# would leave it unguarded. It must be present, 64-hex, and NEVER equal the bare
# binary's sha (same-paste signature).
if [[ "$prov_sha_deb" =~ ^[0-9a-f]{64}$ && -n "$prov_sha_bin" && "$prov_sha_deb" != "$prov_sha_bin" ]]; then
  pass "sidecar cloudflared-linux-amd64.deb sha256 recorded, 64-hex, distinct from the binary sha"
else
  fail "sidecar cloudflared-linux-amd64.deb sha256 ('$prov_sha_deb') missing, malformed, or identical to the binary sha -- the .deb asset's sha is a DIFFERENT value; recompute it per '## Bump procedure' in $PROV"
fi

# --- 4. Release-asset URLs name the pinned version ------------------------------------
# The sidecar records the download URLs as the provenance anchor; both must name
# the pinned tag — a URL left at the old tag means the sha was re-hashed against
# the wrong release.
for asset in cloudflared-linux-amd64 cloudflared-linux-amd64.deb; do
  url="https://github.com/cloudflare/cloudflared/releases/download/$pin_ver/$asset"
  if printf '%s\n' "$cur_section" | grep -qF "$url"; then
    pass "sidecar records the pinned release URL for $asset"
  else
    fail "sidecar '## Current pin' does not name $url -- the recorded provenance anchor must point at the pinned tag's own asset"
  fi
done

# --- 5. Header row + capture-age gate --------------------------------------------------
# Same row shape as inngest-cli.provenance.md so the sidecars share one format.
# Scoped to the header table; REFUSE on more than one 'Capture date (UTC)' row
# anywhere in the file — a second row shadows the freshness attestation while
# bypassing the sidecar's own "do not re-stamp to clear a red gate" warning.
cap_rows="$(grep -cE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PROV" || true)"
if [[ "$cap_rows" -gt 1 ]]; then
  die_detector "found $cap_rows 'Capture date (UTC)' rows in $PROV -- exactly one is legitimate; a second shadows the freshness attestation"
fi
header_table="$(awk '/^\| Field \| Value \|/{f=1} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
# The header's 'Pinned version' row is the sidecar's headline field — a bump that
# forgets it leaves the sidecar internally contradictory while the rest stays green.
hdr_ver="$(printf '%s\n' "$header_table" | grep -oE 'Pinned version *\| *\*\*[0-9]+\.[0-9]+\.[0-9]+\*\*' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ -n "$hdr_ver" && "$hdr_ver" == "$pin_ver" ]]; then
  pass "sidecar 'Pinned version' header row names the pinned version"
else
  fail "sidecar 'Pinned version' header row ('$hdr_ver') != pinned $pin_ver -- the headline field was left stale; see '## Bump procedure' in $PROV"
fi
capture_date="$(printf '%s\n' "$header_table" | grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
if [[ -z "$capture_date" ]]; then
  # DRIFT (10), not detector failure (2): an unparseable date is a defect in a
  # COMMITTED file that a human fixes — unlike a missing input or a dead upstream
  # poll. Either way non-zero: an unreadable date must never read as fresh.
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
      # The remedy is an INVOCATION, not a description: re-hashing both assets
      # and re-verifying the claim register is engineering work, and this repo's
      # operator is non-technical.
      fail "cloudflared pin analysis is ${age_days}d old (> ${MAX_AGE_DAYS}d). Refresh it with:  /soleur:one-shot \"refresh the cloudflared pin provenance sidecar per apps/web-platform/infra/cloudflared.provenance.md section 'Bump procedure'\""
    else
      pass "cloudflared pin analysis capture age ${age_days}d (<= ${MAX_AGE_DAYS}d)"
    fi
  fi
fi

# --- 6. Version-scoped claims must name the PINNED version ----------------------------
# The two composite actions carry an `e.g. <version>` example in their
# `cloudflared-version` input description — the exact stale-prose class this
# bump just fixed. Guard the followers rather than re-sweeping them by hand.
# THE CANONICAL CLAIM SHAPE is `e.g. X.Y.Z` — a follower that rewords it becomes
# invisible to this regex AND to the claim-register requirement below.
CLAIM_RE='e\.g\. [0-9]+\.[0-9]+\.[0-9]+'
followers=(
  "$REPO_ROOT/.github/actions/cf-tunnel-ssh-bridge/action.yml"
  "$REPO_ROOT/.github/actions/cf-tunnel-registry-bridge/action.yml"
)
for f in "${followers[@]}"; do
  # A MISSING follower is drift (10) — a defect in the committed tree.
  if [[ ! -f "$f" ]]; then
    fail "follower file missing: $(basename "$f") -- cannot verify version-scoped claims"
    continue
  fi
  hits="$(grep -ohE "$CLAIM_RE" "$f" 2>/dev/null | sort -u || true)"
  if [[ -z "$hits" ]]; then
    # Zero claims examined must not read as full coverage: each registered
    # location MUST carry >= 1 claim.
    fail "$(basename "$f") carries NO 'e.g. X.Y.Z' claim -- either the claim was reworded (this guard cannot see the new phrasing; widen it) or the sidecar's claim register is stale"
    continue
  fi
  bad=""
  while IFS= read -r hit; do
    v="${hit##*e.g. }"
    [[ "$v" == "$pin_ver" ]] || bad+="    $(basename "$f"): 'e.g. $v' (pinned is $pin_ver)"$'\n'
  done <<< "$hits"
  if [[ -z "$bad" ]]; then
    pass "$(basename "$f") 'e.g.' claim names the pinned version ($pin_ver)"
  else
    fail "version-scoped claims name a version we no longer pin:"$'\n'"$bad    These are EXAMPLES, not inferences -- re-stamp them per '## Bump procedure' in $PROV"
  fi
done

# --- 7. Previous known-good pin (the rollback target) ----------------------------------
# The bump erases the superseded checksum from every .github/ site, so without
# this section the rollback target survives only in git history — a
# git-archaeology exercise under incident pressure. A MISSING section in a
# committed file is drift (10), not a detector failure (2).
prev_section="$(awk '/^## Previous known-good pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
if [[ -z "$prev_section" ]]; then
  fail "no '## Previous known-good pin' section in $PROV -- the rollback target does not survive the bump that erases it from .github/"
else
  prev_sha="$(printf '%s\n' "$prev_section" | grep -oE "\| *cloudflared-linux-amd64 *\| *\`[0-9a-f]{64}\`" | grep -oE '[0-9a-f]{64}' | head -1 || true)"
  prev_ver="$(printf '%s\n' "$prev_section" | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()' | head -1 || true)"
  if [[ -z "$prev_sha" ]]; then
    fail "no '## Previous known-good pin' sha256 for cloudflared-linux-amd64 in $PROV -- the rollback target does not survive the bump"
  elif [[ "$prev_sha" == "$pin_sha" ]]; then
    fail "'## Previous known-good pin' records the SAME sha256 as the current pin -- not rotated on the last bump, so there is no rollback target"
  else
    pass "previous known-good sha256 recorded and distinct from the current pin"
  fi
  if [[ -z "$prev_ver" ]]; then
    fail "no '## Previous known-good pin' version recorded in $PROV"
  elif [[ "$prev_ver" == "$pin_ver" ]]; then
    fail "'## Previous known-good pin' records the SAME version as the current pin ($prev_ver) -- not rotated on the last bump"
  else
    pass "previous known-good version recorded ($prev_ver) and distinct from the current pin"
  fi
fi

echo "RESULT: $PASS passed, $FAIL failed"

# Did the assertions actually RUN? A silent drop to zero checks is a DETECTOR
# failure (2), not a clean bill of health. MIN_ASSERTIONS is RE-BOUND here,
# adjacent to the check: scripts/guard-vacuity-floor.test.sh slices the floor
# plus its contiguous assignment bindings into a mutant, so a threshold bound at
# the top of the file leaves the mutant unbound and scores CONSTRUCTION instead
# of FIRES.
MIN_ASSERTIONS=17
TOTAL=$((PASS + FAIL))
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "  DETECTOR-FAILURE: only $TOTAL assertion(s) ran, expected >= $MIN_ASSERTIONS -- checks were skipped or silently removed; this run proves nothing" >&2
  exit 2
fi

# 10 = drift (actionable). Reserved distinct from 1 so the rule-audit.yml poll
# step can tell "the pin is stale" from "the detector broke" (exit 2, above).
[[ "$FAIL" -eq 0 ]] || exit 10
