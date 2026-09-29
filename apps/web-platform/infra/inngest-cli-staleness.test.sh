#!/usr/bin/env bash
# Freshness + coherence gate for the pinned inngest CLI (#7463, absorbs the
# freshness-owner half of #7308).
#
# WHY THIS EXISTS: inngest-server is the background-job substrate, and its CLI pin
# (`inngest_cli_version` + two arch checksums in inngest.tf) sat at v1.19.4 for
# ~4.5 months with NO freshness mechanism — the gap #7308 named. This gate is the
# enforcement half; the detection half is the `Detect inngest CLI pin drift` poll
# step in .github/workflows/rule-audit.yml (PR-B). Neither works alone: a poll with
# no gate lets the analysis rot, and a gate with no poll never notices upstream
# moving.
#
# WHY ARCH-KEYED (checks 3/4/8): `local.inngest_arch` selects amd64 vs arm64 via a
# ternary on the dedicated host (inngest-host.tf), and the live host is amd64. If
# the two checksums are SWAPPED — a trivial copy-paste error across a two-row table —
# the pin stays well-formed and fails only on the unused-today arm arm, or worse on
# the NEXT cax provision. Both shas come from ONE release `checksums.txt`, so the
# sidecar records that file's URL as the provenance anchor. The selector ternary
# itself is pinned byte-exact by inngest-host.test.sh — deliberately not re-asserted
# here (the zot sibling carries its own selector check; coverage lives next door).
#
# WHAT THESE CHECKS DO AND DO NOT COVER. They catch a swap or incoherence confined
# to ONE file, a missing sidecar row, a stale capture date, and version-scoped
# claims that name a version we no longer pin. They CANNOT catch a pin+sidecar
# edited coherently to a wrong/older release — nothing in the committed file set
# binds a sha to upstream ground truth. Bounds on that hole: the PR-B poll catches
# a coherent ROLLBACK (delta/age), and a same-version sha swap dies at the
# bootstrap image build's sha256 verify (amd64) or the host's own verify
# (fail-closed, either arch). Do not read these checks as closing
# the whole class; they close the half that is closable offline. Deliberately there
# is NO version floor: a coherent two-file revert to the previous-known-good pin is
# the SANCTIONED rollback path (see the sidecar's '## Previous known-good pin'), and
# a floor would fight it.
#
# NO NETWORK, BY DESIGN. Tarball re-hashes and release-list walks are a documented
# sidecar procedure and a /work Phase 0 step, not a test dependency — a test that
# needs the network reddens on upstream's outage. Everything here reads committed
# files only.
#
# EXIT CODES (the rule-audit.yml poll step discriminates on these; do not overload 1):
#   0  — fresh and coherent
#   10 — DRIFT: stale or incoherent (the actionable "a human must look" signal)
#   2  — DETECTOR FAILURE: inputs missing/unparseable. Never conflated with "fresh".
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/inngest.tf"
PROV="$DIR/inngest-cli.provenance.md"

# Upstream ships ~weekly (v1.19.4..v1.45.1 spans ~4.5 months at ~5.8 days/release) and
# the rule-audit.yml poll runs on the 1st and 15th, so 60 days is ~10 upstream releases
# and ~4 poll firings: a genuine stall, not routine lag. This is the backstop for the
# poll's OWN failure — the two mechanisms are different failures, not redundancy.
MAX_AGE_DAYS=60

# ANTI-VACUITY FLOOR. Without this the terminal contract is `[[ "$FAIL" -eq 0 ]]`, so a
# gate whose assertions all silently stop running prints `RESULT: 0 passed, 0 failed`
# and exits 0 — CI green having checked NOTHING. A FLOOR, not equality: `-eq` would
# turn every legitimately-added assertion into a spurious failure. Raise it in
# lockstep when assertions are added; never lower it to make a red run green.
MIN_ASSERTIONS=19

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# A detector failure is NOT a drift verdict — exit 2 so the poll can tell "I could not
# check" from "I checked and it is stale". Silence here would read as freshness.
die_detector() { echo "  DETECTOR-FAILURE: $1" >&2; echo "RESULT: $PASS passed, $FAIL failed (detector failure)"; exit 2; }

# POSITIVE CONTROL. MIN_ASSERTIONS counts PASS+FAIL, so neutering fail() ALONE leaves
# the count intact while the gate becomes permanently incapable of reporting drift —
# green forever, floor satisfied. Prove both counters move before trusting any verdict,
# then reset.
_ctl_p="$PASS"; _ctl_f="$FAIL"
pass "self-test" >/dev/null 2>&1; fail "self-test" >/dev/null 2>&1
if [[ "$PASS" -ne $((_ctl_p + 1)) || "$FAIL" -ne $((_ctl_f + 1)) ]]; then
  echo "  DETECTOR-FAILURE: the assertion counters do not increment (pass/fail neutered) -- every verdict from this run would be meaningless" >&2
  exit 2
fi
PASS="$_ctl_p"; FAIL="$_ctl_f"

echo "--- inngest CLI pin staleness + coherence gate (#7463) ---"

# --- 1. Inputs present -------------------------------------------------------------
[[ -s "$TF" ]]   || die_detector "inngest.tf missing/empty at $TF"
pass "inngest.tf present"
[[ -s "$PROV" ]] || die_detector "provenance sidecar missing/empty at $PROV (create inngest-cli.provenance.md)"
pass "provenance sidecar present"

# --- helpers ------------------------------------------------------------------------
# terraform fmt re-aligns '=' when a block gains an attribute, so match [[:space:]]*
# around it rather than a single space. The `^[[:space:]]*` anchor is the
# decoy-in-a-comment guard: a whole-line comment (`# inngest_cli_version = …`) never
# satisfies it, and a second ACTIVE assignment fails the exactly-once count.
tf_line_for() { # $1=local name -> the full assignment line (at most one expected)
  grep -nE "^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"" "$TF" 2>/dev/null || true
}
tf_line_count() { tf_line_for "$1" | grep -c . 2>/dev/null || true; }

# --- 2. Pin form, exactly once -------------------------------------------------------
n_ver="$(tf_line_count inngest_cli_version)"
if [[ "$n_ver" == "1" ]]; then
  pass "inngest_cli_version is assigned exactly once"
else
  fail "inngest_cli_version: expected exactly 1 active assignment in $TF, found $n_ver -- a commented-out pin is a decoy, not a hit; two active assignments are ambiguous"
fi
for local in inngest_cli_sha256 inngest_cli_sha256_arm64; do
  n="$(tf_line_count "$local")"
  if [[ "$n" == "1" ]]; then
    pass "$local is assigned exactly once"
  else
    fail "$local: expected exactly 1 active assignment in $TF, found $n"
  fi
done

tf_ver="$(tf_line_for inngest_cli_version | grep -oE '"v[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | head -1 || true)"
tf_sha_amd64="$(tf_line_for inngest_cli_sha256 | grep -oE '"[0-9a-f]{64}"' | tr -d '"' | head -1 || true)"
tf_sha_arm64="$(tf_line_for inngest_cli_sha256_arm64 | grep -oE '"[0-9a-f]{64}"' | tr -d '"' | head -1 || true)"

[[ "$tf_ver" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && pass "inngest_cli_version is a well-formed vX.Y.Z ($tf_ver)" \
  || fail "inngest_cli_version value '$tf_ver' is not vX.Y.Z"
for pair in "amd64:$tf_sha_amd64" "arm64:$tf_sha_arm64"; do
  arch="${pair%%:*}"; sha="${pair#*:}"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] \
    && pass "$arch checksum is 64-hex" \
    || fail "$arch checksum '$sha' is not 64-hex"
done

# --- 3. Cross-arch SHA distinctness ---------------------------------------------------
# Two arches never share a tarball sha. Equality means one value was pasted into both
# slots, which fails the bootstrap's sha256 verify on whichever arch loses.
if [[ -n "$tf_sha_amd64" && -n "$tf_sha_arm64" && "$tf_sha_amd64" != "$tf_sha_arm64" ]]; then
  pass "amd64 and arm64 checksums are distinct"
else
  fail "amd64 and arm64 checksums are IDENTICAL or missing -- one arch's sha was pasted into both slots; the other arch's sha256 verify fails at bootstrap"
fi

# --- sidecar section extraction ------------------------------------------------------
# Scope to the '## Current pin' section: '## Previous known-good pin' also carries
# sha references, so an unscoped grep would match either non-deterministically.
cur_section="$(awk '/^## Current pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
[[ -n "$cur_section" ]] || die_detector "could not find a '## Current pin' section in $PROV"

prov_sha_for() { # $1=arch -> that arch's 64-hex sha inside the Current pin section only
  printf '%s\n' "$cur_section" | grep -oE "\| *$1 *\|[^|]*\`[0-9a-f]{64}\`" | grep -oE '[0-9a-f]{64}' | head -1 || true
}
prov_sha_amd64="$(prov_sha_for amd64)"
prov_sha_arm64="$(prov_sha_for arm64)"
prov_ver="$(printf '%s\n' "$cur_section" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"

# --- 4. Sidecar <-> pin coherence, ARCH-KEYED -----------------------------------------
# Two SEPARATE per-arch equalities, never set membership over the pair. Set membership
# ("both sidecar shas appear among both tf shas") is satisfied by a swap.
# The failure text names the reconciliation direction: the sidecar is the analysis of
# record and the tf locals FOLLOW it; upstream is the poll's authority. Never print a
# remedy that reduces to "make the two files agree" — the coherent-fake hole is the
# poll's job (mutation row 8).
if [[ -n "$prov_sha_amd64" && "$prov_sha_amd64" == "$tf_sha_amd64" ]]; then
  pass "sidecar amd64 checksum matches inngest_cli_sha256"
else
  fail "sidecar amd64 checksum ('$prov_sha_amd64') != inngest_cli_sha256 ('$tf_sha_amd64') -- sidecar and inngest.tf disagree; the sidecar is authoritative -- update the pin or re-derive the sidecar (see '## Bump procedure' in $PROV)"
fi
if [[ -n "$prov_sha_arm64" && "$prov_sha_arm64" == "$tf_sha_arm64" ]]; then
  pass "sidecar arm64 checksum matches inngest_cli_sha256_arm64"
else
  fail "sidecar arm64 checksum ('$prov_sha_arm64') != inngest_cli_sha256_arm64 ('$tf_sha_arm64') -- sidecar and inngest.tf disagree; the sidecar is authoritative -- update the pin or re-derive the sidecar (see '## Bump procedure' in $PROV)"
fi
if [[ -n "$prov_ver" && "$prov_ver" == "$tf_ver" ]]; then
  pass "sidecar current-pin version matches inngest_cli_version ($prov_ver)"
else
  fail "sidecar current-pin version ('$prov_ver') != inngest_cli_version ('$tf_ver')"
fi

# --- 5. Single-source checksums URL ----------------------------------------------------
# Both arch values must come from ONE release checksums.txt — the sidecar records the
# URL and the gate refuses ambiguity (zero or two+ distinct URLs are both incoherent).
csum_urls="$(printf '%s\n' "$cur_section" | grep -oE 'https://github\.com/inngest/inngest/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/checksums\.txt' | sort -u || true)"
n_csum="$(printf '%s\n' "$csum_urls" | grep -c . || true)"
if [[ "$n_csum" == "1" ]]; then
  csum_ver="$(printf '%s\n' "$csum_urls" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
  if [[ "$csum_ver" == "$tf_ver" ]]; then
    pass "sidecar names exactly one checksums.txt and it matches the pinned version ($csum_ver)"
  else
    fail "sidecar's checksums.txt is for $csum_ver but the pin is $tf_ver -- sidecar and inngest.tf disagree; the sidecar is authoritative -- update the pin or re-derive the sidecar"
  fi
else
  fail "expected exactly ONE distinct checksums.txt URL in the '## Current pin' section of $PROV, found $n_csum -- both arch checksums MUST come from one release-shipped checksums.txt"
fi

# --- 6. Capture-age gate ---------------------------------------------------------------
# Same row shape as zot-image.provenance.md so the sidecars share one format. Scoped to
# the header table; REFUSE on more than one 'Capture date (UTC)' row anywhere in the
# file — a second row (e.g. a '## Bump log') shadows the freshness attestation while
# bypassing the sidecar's own "do not re-stamp to clear a red gate" warning.
cap_rows="$(grep -cE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PROV" || true)"
if [[ "$cap_rows" -gt 1 ]]; then
  die_detector "found $cap_rows 'Capture date (UTC)' rows in $PROV -- exactly one is legitimate; a second shadows the freshness attestation"
fi
header_table="$(awk '/^\| Field \| Value \|/{f=1} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
# The header's 'Pinned version' row is the sidecar's headline field — a bump that
# forgets it leaves the sidecar internally contradictory while the rest stays green.
hdr_ver="$(printf '%s\n' "$header_table" | grep -oE 'Pinned version *\| *\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ -n "$hdr_ver" && "$hdr_ver" == "$tf_ver" ]]; then
  pass "sidecar 'Pinned version' header row names the pinned version"
else
  fail "sidecar 'Pinned version' header row ('$hdr_ver') != pinned $tf_ver -- the headline field was left stale; see '## Bump procedure' in $PROV"
fi
capture_date="$(printf '%s\n' "$header_table" | grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
if [[ -z "$capture_date" ]]; then
  # DRIFT (10), not detector failure (2): an unparseable date is a defect in a COMMITTED
  # file that a human fixes -- unlike a missing input or a dead upstream poll. Either
  # way non-zero: an unreadable date must never read as fresh.
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
      # The remedy is an INVOCATION, not a description: re-measuring the flag surface,
      # checksums, and GQL claims against a new pin is engineering work, and this
      # repo's operator is non-technical.
      fail "inngest pin analysis is ${age_days}d old (> ${MAX_AGE_DAYS}d). Refresh it with:  /soleur:one-shot \"refresh the inngest CLI pin provenance sidecar per apps/web-platform/infra/inngest-cli.provenance.md section 'Bump procedure'\""
    else
      pass "inngest pin analysis capture age ${age_days}d (<= ${MAX_AGE_DAYS}d)"
    fi
  fi
fi

# --- 7. Version-scoped capability claims must name the PINNED version -----------------
# The defect being fixed is `inngest v1.19.4` hardcoded in prose that outlives the pin.
# Guard the followers rather than re-sweeping them by hand. The `\(?` is load-bearing:
# claims are written both `inngest v1.45.1` and `inngest (v1.45.1)`. THE CANONICAL
# CLAIM SHAPE is `inngest vX.Y.Z` — phrasings like `inngest-server v…`, `pinned v…`,
# or a bare `vX.Y.Z` are INVISIBLE to this regex; a follower that silently needs
# another shape escapes the guard (the review-pass finding), so re-stamping must
# write the canonical form (the sidecar's claim register says the same).
followers=(
  "$DIR/inngest.tf"
  "$DIR/inngest-bootstrap.sh"
  "$DIR/inngest-inventory.sh"
  "$DIR/inngest-enumerate-reminders.sh"
  "$DIR/inngest-doublefire-probe.sh"
  "$DIR/inngest-wiped-volume-verify.sh"
  "$DIR/ci-deploy.sh"
  "$DIR/betterstack-logs-alerts.tf"
  "$DIR/inngest-host.tf"
  "$DIR/inngest.test.sh"
  "$DIR/inngest-inventory.test.sh"
  "$DIR/inngest-enumerate-reminders.test.sh"
  "$DIR/inngest-doublefire-probe.test.sh"
  "$DIR/inngest-wiped-volume-verify.test.sh"
)
stale_claims=""
followers_seen=0
for f in "${followers[@]}"; do
  # A MISSING follower is drift (10) — a defect in the committed tree (the claim set
  # is part of what this gate verifies), not an unparseable detector input.
  [[ -f "$f" ]] || { fail "follower file missing: $(basename "$f") -- cannot verify version-scoped claims"; continue; }
  followers_seen=$((followers_seen+1))
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    v="${hit##*inngest }"; v="${v#(}"   # strip the optional opening paren
    [[ "$v" == "$tf_ver" ]] || stale_claims+="    $(basename "$f"): 'inngest $v' (pinned is $tf_ver)"$'\n'
  done < <(grep -ohE 'inngest \(?v[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null | sort -u || true)
done
# A follower that still EXISTS but whose claim was reworded yields zero loop iterations
# and a PASS asserting coverage. Zero claims examined must not read as full coverage:
# the locations the sidecar's claim register names MUST each carry >=1 claim.
required_claim_locations=("$DIR/inngest-inventory.sh" "$DIR/inngest-doublefire-probe.sh" "$DIR/inngest-host.tf" "$DIR/betterstack-logs-alerts.tf")
missing_claims=""
for f in "${required_claim_locations[@]}"; do
  [[ -f "$f" ]] || continue   # absence already failed above
  n_hits="$(grep -cE 'inngest \(?v[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null || true)"
  [[ "$n_hits" -ge 1 ]] || missing_claims+="    $(basename "$f"): 0 version-scoped claims found"$'\n'
done
if [[ "$followers_seen" -ne "${#followers[@]}" ]]; then
  : # already failed above; do not also emit a misleading clean verdict
elif [[ -n "$missing_claims" ]]; then
  fail "a registered version-scoped claim location carries NO 'inngest vX.Y.Z' claim -- either the claim was reworded (this guard cannot see the new phrasing; widen it) or the sidecar's claim register is stale:"$'\n'"$missing_claims"
elif [[ -z "$stale_claims" ]]; then
  pass "all 'inngest vX.Y.Z' capability claims name the pinned version (${#required_claim_locations[@]} registered locations each carry >=1 claim)"
else
  fail "version-scoped claims name a version we no longer pin:"$'\n'"$stale_claims    These are MEASUREMENTS, not inferences -- re-measure against the pinned binary (see '## Bump procedure'), do not just re-word them"
fi

# --- 8. Previous known-good pin (the rollback target) ----------------------------------
# The bump erases the superseded checksums from inngest.tf, so without this section the
# rollback target survives only in git history -- a git-archaeology exercise under
# incident pressure on a host with no shell. ARCH-KEYED, like check 4.
# A MISSING section in a committed file is drift (10), not a detector failure (2) —
# the same distinction the unparseable-date row draws: a human must fix the file.
prev_section="$(awk '/^## Previous known-good pin/{f=1;next} /^## /{f=0} f' "$PROV" 2>/dev/null || true)"
prev_sha_for() {
  [[ -n "$prev_section" ]] || return 0
  printf '%s\n' "$prev_section" | grep -oE "\| *$1 *\|[^|]*\`[0-9a-f]{64}\`" | grep -oE '[0-9a-f]{64}' | head -1 || true
}
if [[ -z "$prev_section" ]]; then
  fail "no '## Previous known-good pin' section in $PROV -- the rollback target for BOTH arches does not survive the bump that erases it from inngest.tf"
else
  pa="$(prev_sha_for amd64)"; pr_="$(prev_sha_for arm64)"
  if [[ -n "$pa" && -n "$pr_" && "$pa" != "$pr_" ]]; then
    pass "previous known-good amd64 and arm64 checksums are distinct"
  elif [[ -n "$pa" && -n "$pr_" ]]; then
    fail "previous known-good amd64 and arm64 checksums are IDENTICAL -- one arch's rollback sha was pasted into both rows; the other arch has no rollback target"
  fi
fi
for arch in amd64 arm64; do
  prev_s="$(prev_sha_for "$arch")"
  cur_s="$tf_sha_amd64"; [[ "$arch" == arm64 ]] && cur_s="$tf_sha_arm64"
  if [[ -z "$prev_s" ]]; then
    fail "no '## Previous known-good pin' entry for $arch in $PROV -- the rollback target for this arch does not survive the bump that erases it from inngest.tf"
  elif [[ "$prev_s" == "$cur_s" ]]; then
    fail "'## Previous known-good pin' records the SAME $arch checksum as the current pin -- not rotated on the last bump, so there is no rollback target for $arch"
  else
    pass "previous known-good $arch checksum recorded and distinct from the current pin"
  fi
done

echo "RESULT: $PASS passed, $FAIL failed"

# Did the assertions actually RUN? A silent drop to zero checks is a DETECTOR failure
# (2), not a clean bill of health.
TOTAL=$((PASS + FAIL))
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "  DETECTOR-FAILURE: only $TOTAL assertion(s) ran, expected >= $MIN_ASSERTIONS -- checks were skipped or silently removed; this run proves nothing" >&2
  exit 2
fi

# 10 = drift (actionable). Reserved distinct from 1 so the rule-audit.yml poll step can
# tell "the pin is stale" from "the detector broke" (exit 2, above).
[[ "$FAIL" -eq 0 ]] || exit 10
