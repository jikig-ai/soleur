#!/usr/bin/env bash
# Tests for scripts/lint-encryption-posture.py (the Layer A encryption-posture
# detector, ADR-140). This is a SECURITY GATE: the whole point is that a ledger
# row cannot false-PASS by citing a sibling volume's LUKS apparatus (the #6588
# class — see R1 in knowledge-base/project/plans/
# 2026-07-23-feat-encryption-posture-design-time-default-plan.md). Every fixture
# below is SYNTHESIZED under mktemp (cq-test-fixtures-synthesized-only) — no real
# secrets, no real device paths.
#
# Two kinds of proof:
#   1. TS-N fixture cases: exit code AND the exact FAIL-message needle (R10's
#      failure-message contract), not just pass/fail counts.
#   2. MB-N mutation battery: copy the SUT, sed-delete the marked branch, assert
#      the SAME fixture that FAILed at baseline PASSes after the deletion —
#      proving the branch was load-bearing, not vacuous. Diffed PER-CASE, never
#      by suite pass-count.
#
# Exit contract of the SUT: 0 PASS/skip, 1 FAIL, 2 argument/IO error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-encryption-posture.py"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

TODAY="2026-07-24"

# write_file <path> — writes stdin to <path>, creating parent dirs.
write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

# ---------------------------------------------------------------------------
# Fixture builders — repo trees (apps/*/infra/*) synthesized per scenario.
# ---------------------------------------------------------------------------

# mk_git_data_base <dir> — a correctly-wired git-data LUKS apparatus (mirrors
# git-data-luks.tf + cloud-init-git-data.yml's LUKS block, literal mapper
# "git-data").
mk_git_data_base() {
  local d="$1"
  write_file "$d/apps/web-platform/infra/git-data-luks.tf" <<'EOF'
resource "random_password" "git_data_luks" {
  length  = 40
  special = false
}

resource "doppler_secret" "git_data_luks_key" {
  project = "soleur"
  config  = "prd_git_data"
  name    = "GIT_DATA_LUKS_KEY"
  value   = random_password.git_data_luks.result
}

resource "hcloud_volume" "git_data_luks" {
  name = "soleur-git-data-luks-store"
}

resource "hcloud_volume_attachment" "git_data_luks" {
  volume_id = hcloud_volume.git_data_luks.id
  server_id = hcloud_server.git_data.id
}
EOF
  write_file "$d/apps/web-platform/infra/cloud-init-git-data.yml" <<'EOF'
runcmd:
  - |
    set -euo pipefail
    DEV="/dev/disk/by-id/scsi-0HC_Volume_x"
    if ! cryptsetup isLuks "$DEV"; then
      printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV"
    fi
    if [ ! -e /dev/mapper/git-data ]; then
      printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksOpen --key-file - "$DEV" git-data
    fi
    grep -q '/dev/mapper/git-data' /etc/fstab || echo '/dev/mapper/git-data /mnt/git-data-luks ext4 defaults,nofail 0 2' >> /etc/fstab
EOF
}

# mk_git_data_ledger <path> — the single-store ledger matching mk_git_data_base.
mk_git_data_ledger() {
  local out="$1"
  write_file "$out" <<EOF
{
  "schema_version": 1,
  "store_classes": {
    "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks"] }
  },
  "non_store_types": ["hcloud_volume_attachment", "random_password", "doppler_secret"],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "hcloud_volume.git_data_luks",
      "kind": "guest-luks-volume",
      "device_binding": {
        "volume": "hcloud_volume.git_data_luks",
        "attachment": "hcloud_volume_attachment.git_data_luks",
        "mapper": "git-data"
      },
      "at_rest": {
        "mechanism": "luks",
        "evidence": "apps/web-platform/infra/cloud-init-git-data.yml",
        "defends_against": "a seized or RMA'd disk; a raw volume snapshot",
        "does_not_defend": "a leaked service-role credential or a compromised host with the volume already unlocked",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no host probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF
}

# mk_workspaces_repo <dir> — BOTH the plaintext hcloud_volume.workspaces (a
# real /mnt/data-shaped attachment, no key material) AND the encrypted sibling
# hcloud_volume.workspaces_luks — the adversarial namespace R1 exists for.
mk_workspaces_repo() {
  local d="$1"
  write_file "$d/apps/web-platform/infra/server.tf" <<'EOF'
resource "hcloud_volume" "workspaces" {
  name = "soleur-web-platform-data"
}

resource "hcloud_volume_attachment" "workspaces" {
  volume_id = hcloud_volume.workspaces.id
  server_id = hcloud_server.web.id
}
EOF
  write_file "$d/apps/web-platform/infra/workspaces-luks.tf" <<'EOF'
resource "random_password" "workspaces_luks" {
  length  = 40
  special = false
}

resource "doppler_secret" "workspaces_luks_key" {
  project = "soleur"
  config  = "prd_workspaces_luks"
  name    = "WORKSPACES_LUKS_KEY"
  value   = random_password.workspaces_luks.result
}

resource "hcloud_volume" "workspaces_luks" {
  name = "soleur-web-platform-data-luks"
}

resource "hcloud_volume_attachment" "workspaces_luks" {
  volume_id = hcloud_volume.workspaces_luks.id
  server_id = hcloud_server.web.id
}
EOF
  write_file "$d/apps/web-platform/infra/workspaces-cutover.sh" <<'EOF'
#!/usr/bin/env bash
MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-workspaces}"
read_key() { doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks; }
KEY="$(read_key)"
printf '%s' "$KEY" | cryptsetup luksFormat --type luks2 --key-file - "$FRESH_DEV"
printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME"
EOF
  write_file "$d/apps/web-platform/infra/soleur-host-bootstrap.sh" <<'EOF'
#!/bin/sh
MOUNT=/mnt/data
MAPPER=/dev/mapper/workspaces
EOF
}

# mk_workspaces_row <store> <attach> — one at_rest:luks row JSON fragment.
mk_workspaces_row() {
  local store="$1" attach="$2"
  cat <<EOF
    {
      "store": "$store",
      "kind": "guest-luks-volume",
      "device_binding": {
        "volume": "$store",
        "attachment": "$attach",
        "mapper": "workspaces"
      },
      "at_rest": {
        "mechanism": "luks",
        "evidence": "apps/web-platform/infra/workspaces-cutover.sh",
        "defends_against": "a seized or RMA'd disk; a raw volume snapshot",
        "does_not_defend": "a leaked service-role credential or a compromised host with the volume already unlocked",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no host probe in this fixture"
      }
    }
EOF
}

# ---------------------------------------------------------------------------
# TS-1: luks row with device_binding whose apparatus resolves -> PASS
# ---------------------------------------------------------------------------
REPO_TS1="$TMPDIR_TEST/ts1"
mk_git_data_base "$REPO_TS1"
LEDGER_TS1="$TMPDIR_TEST/ts1-ledger.json"
mk_git_data_ledger "$LEDGER_TS1"

run_case() {
  local name="$1" expected="$2"; shift 2
  local actual=0
  python3 "$SUT" "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then pass "$name"; else fail "$name" "expected exit=$expected actual=$actual"; fi
}

run_case_reports() {
  local name="$1" expected="$2" needle="$3"; shift 3
  local actual=0 out
  out="$(python3 "$SUT" "$@" 2>&1)" || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    fail "$name" "expected exit=$expected actual=$actual; output: $out"
    return
  fi
  if grep -qF "$needle" <<<"$out"; then pass "$name"; else fail "$name" "report did not mention '$needle'. output: $out"; fi
}

# Positive control (ADR-193): the verdict helpers must be able to FAIL.
# Reported via printf + exit, never through them; then unwound.
_pc_fail0=$FAIL; _pc_total0=$TOTAL
run_case "positive control (expected to FAIL): wrong rc" 7 \
  --repo-sweep --repo-root "$REPO_TS1" --ledger "$LEDGER_TS1" --today "$TODAY" >/dev/null
run_case_reports "positive control (expected to FAIL): absent needle" 0 "NEEDLE-THAT-NEVER-APPEARS" \
  --repo-sweep --repo-root "$REPO_TS1" --ledger "$LEDGER_TS1" --today "$TODAY" >/dev/null
if [[ $((FAIL - _pc_fail0)) -ne 2 ]]; then
  printf 'GUARD FAIL: run_case/run_case_reports could not record a failure\n' >&2
  exit 2
fi
FAIL=$_pc_fail0; TOTAL=$_pc_total0

run_case_reports "TS-1 luks row resolves via device_binding -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_TS1" --ledger "$LEDGER_TS1" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-2: the luksFormat site deleted -> FAIL unresolvable citation
# ---------------------------------------------------------------------------
REPO_TS2="$TMPDIR_TEST/ts2"
mk_git_data_base "$REPO_TS2"
sed -i '/luksFormat/d' "$REPO_TS2/apps/web-platform/infra/cloud-init-git-data.yml"
LEDGER_TS2="$LEDGER_TS1"  # same ledger; the apparatus is what's broken

run_case_reports "TS-2 luksFormat site deleted -> FAIL unresolvable" 1 \
  "does not resolve to any cryptsetup luksFormat+luksOpen apparatus" \
  --repo-sweep --repo-root "$REPO_TS2" --ledger "$LEDGER_TS2" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-3: mapper in the mount evidence != mapper in luksOpen -> FAIL mismatch
# ---------------------------------------------------------------------------
REPO_TS3="$TMPDIR_TEST/ts3"
mk_git_data_base "$REPO_TS3"
sed -i 's#/dev/mapper/git-data#/dev/mapper/git-data-old#g' "$REPO_TS3/apps/web-platform/infra/cloud-init-git-data.yml"
LEDGER_TS3="$LEDGER_TS1"

run_case_reports "TS-3 mount mapper != luksOpen mapper -> FAIL mismatch" 1 "mapper mismatch" \
  --repo-sweep --repo-root "$REPO_TS3" --ledger "$LEDGER_TS3" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-4: provider-managed "the provider handles it" -> FAIL boilerplate
#       (attestation_url + fresh retrieved_on ARE present, so the ONLY reason
#       this fixture fails is the ban-list — needed for MB-3 to cleanly flip it)
# ---------------------------------------------------------------------------
REPO_TS4="$TMPDIR_TEST/ts4"
write_file "$REPO_TS4/apps/web-platform/infra/r2.tf" <<'EOF'
resource "cloudflare_r2_bucket" "assets" {
  name = "soleur-assets"
}
EOF
LEDGER_TS4="$TMPDIR_TEST/ts4-ledger.json"
write_file "$LEDGER_TS4" <<EOF
{
  "schema_version": 1,
  "store_classes": { "cloudflare_r2_bucket": { "kind": "provider-bucket", "mechanisms": ["provider-managed"] } },
  "non_store_types": [],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "cloudflare_r2_bucket.assets",
      "kind": "provider-bucket",
      "at_rest": {
        "mechanism": "provider-managed: the provider handles it",
        "evidence": "operator assertion, no citation",
        "attestation_url": "https://www.cloudflare.com/trust-hub/compliance-resources/",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked API token or a compromised application server",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF

run_case_reports "TS-4 provider-managed boilerplate -> FAIL ban-list" 1 "boilerplate" \
  --repo-sweep --repo-root "$REPO_TS4" --ledger "$LEDGER_TS4" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-5: provider-managed named attestation + URL + fresh retrieved_on -> PASS
# ---------------------------------------------------------------------------
REPO_TS5="$REPO_TS4"
LEDGER_TS5="$TMPDIR_TEST/ts5-ledger.json"
write_file "$LEDGER_TS5" <<EOF
{
  "schema_version": 1,
  "store_classes": { "cloudflare_r2_bucket": { "kind": "provider-bucket", "mechanisms": ["provider-managed"] } },
  "non_store_types": [],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "cloudflare_r2_bucket.assets",
      "kind": "provider-bucket",
      "at_rest": {
        "mechanism": "provider-managed:Cloudflare-R2-SOC2-Type-II",
        "evidence": "Cloudflare Trust Hub compliance resources page",
        "attestation_url": "https://www.cloudflare.com/trust-hub/compliance-resources/",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked API token or a compromised application server",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF

run_case_reports "TS-5 provider-managed named attestation + url + fresh date -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_TS5" --ledger "$LEDGER_TS5" --today "$TODAY"

# ---------------------------------------------------------------------------
# Shared exception-fixture repo (TS-6, TS-7, TS-16): a single plaintext-
# exception store, mirroring hcloud_volume.inngest_redis.
# ---------------------------------------------------------------------------
REPO_EXC="$TMPDIR_TEST/exc"
write_file "$REPO_EXC/apps/web-platform/infra/inngest-redis.tf" <<'EOF'
resource "hcloud_volume" "inngest_redis" {
  name = "soleur-inngest-redis"
}
EOF

mk_exception_ledger() {
  local out="$1" exception_json="$2"
  write_file "$out" <<EOF
{
  "schema_version": 1,
  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks", "plaintext-exception"] } },
  "non_store_types": [],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "hcloud_volume.inngest_redis",
      "kind": "guest-luks-volume",
      "at_rest": {
        "mechanism": "plaintext-exception",
        "evidence": "no LUKS apparatus provisioned for this volume yet",
        "defends_against": "nothing at rest; the AOF is plaintext ext4",
        "does_not_defend": "a seized or RMA'd disk; a raw volume snapshot",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture",
        "exception": $exception_json
      }
    }
  ],
  "connections": []
}
EOF
}

# ---------------------------------------------------------------------------
# TS-6: plaintext-exception, no tracking_issue -> FAIL
# ---------------------------------------------------------------------------
LEDGER_TS6="$TMPDIR_TEST/ts6-ledger.json"
mk_exception_ledger "$LEDGER_TS6" '{
          "justification": "Redis AOF encryption lands in a follow-up; the job payloads are short-lived",
          "reevaluate_when": "when the Redis-to-LUKS cutover (mirrors #6588) ships",
          "expires_on": "2099-01-01"
        }'

run_case_reports "TS-6 plaintext-exception missing tracking_issue -> FAIL" 1 "tracking_issue" \
  --repo-sweep --repo-root "$REPO_EXC" --ledger "$LEDGER_TS6" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-7: plaintext-exception, all four exception fields present, future
# expires_on -> PASS
# ---------------------------------------------------------------------------
LEDGER_TS7="$TMPDIR_TEST/ts7-ledger.json"
mk_exception_ledger "$LEDGER_TS7" '{
          "justification": "Redis AOF encryption lands in a follow-up; the job payloads are short-lived",
          "tracking_issue": "#6600",
          "reevaluate_when": "when the Redis-to-LUKS cutover (mirrors #6588) ships",
          "expires_on": "2099-01-01"
        }'

run_case_reports "TS-7 plaintext-exception all fields + future expires_on -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_EXC" --ledger "$LEDGER_TS7" --today "$TODAY"

# An exception within 14 days of expiry WARNS and still passes (#6907). Once the
# sweep is merge-blocking, an expiry is a repo-wide merge freeze on the day it
# lands; the warning is the only advance notice. The far-future control proves
# the warning is date-driven rather than always printed.
run_case_reports "TS-7b exception expiring in 7 days -> PASS with an advance warning" 0 "expires in 7 day(s)" \
  --repo-sweep --repo-root "$REPO_EXC" --ledger "$LEDGER_TS7" --today "2098-12-25"
TS7C_OUT="$(python3 "$SUT" --repo-sweep --repo-root "$REPO_EXC" --ledger "$LEDGER_TS7" --today "$TODAY" 2>&1)" || true
if grep -qF "expires in" <<<"$TS7C_OUT"; then fail "TS-7c far-future exception prints no expiry warning" "output: $TS7C_OUT"; else pass "TS-7c far-future exception prints no expiry warning"; fi

# ---------------------------------------------------------------------------
# TS-8: unknown resource type absent from store_classes/non_store_types
#       -> FAIL fail-closed
# ---------------------------------------------------------------------------
REPO_TS8="$TMPDIR_TEST/ts8"
write_file "$REPO_TS8/apps/web-platform/infra/mystery.tf" <<'EOF'
resource "cloudflare_r2_bucket" "mystery" {
  name = "soleur-mystery"
}
EOF
LEDGER_TS8="$TMPDIR_TEST/ts8-ledger.json"
write_file "$LEDGER_TS8" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": [],
  "stores": [],
  "connections": []
}
EOF

run_case_reports "TS-8 unknown resource type -> FAIL fail-closed" 1 "unknown resource type" \
  --repo-sweep --repo-root "$REPO_TS8" --ledger "$LEDGER_TS8" --today "$TODAY"

# R7 companion: a KNOWN non_store_type does NOT fail.
REPO_TS8B="$TMPDIR_TEST/ts8b"
write_file "$REPO_TS8B/apps/web-platform/infra/dns.tf" <<'EOF'
resource "cloudflare_record" "app" {
  name = "app"
}
EOF
LEDGER_TS8B="$TMPDIR_TEST/ts8b-ledger.json"
write_file "$LEDGER_TS8B" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": ["cloudflare_record"],
  "non_iac_stores": [],
  "stores": [],
  "connections": []
}
EOF
run_case "TS-8 companion: known non_store_type does NOT fail" 0 \
  --repo-sweep --repo-root "$REPO_TS8B" --ledger "$LEDGER_TS8B" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-15 (R1 headline): row `store: hcloud_volume.workspaces, mechanism: luks`
# whose device_binding cites the workspaces_luks apparatus (mapper `workspaces`)
# but volume/attachment are the PLAINTEXT workspaces -> FAIL: citation belongs
# to a different volume.
# ---------------------------------------------------------------------------
REPO_TS15="$TMPDIR_TEST/ts15"
mk_workspaces_repo "$REPO_TS15"
LEDGER_TS15="$TMPDIR_TEST/ts15-ledger.json"
{
  echo '{'
  echo '  "schema_version": 1,'
  echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks"] } },'
  echo '  "non_store_types": ["hcloud_volume_attachment", "random_password", "doppler_secret"],'
  echo '  "non_iac_stores": [],'
  echo '  "stores": ['
  mk_workspaces_row "hcloud_volume.workspaces_luks" "hcloud_volume_attachment.workspaces_luks"
  echo '    ,'
  mk_workspaces_row "hcloud_volume.workspaces" "hcloud_volume_attachment.workspaces"
  echo '  ],'
  echo '  "connections": []'
  echo '}'
} > "$LEDGER_TS15"

# ---------------------------------------------------------------------------
# AC33 (real-repo calibration): a synthetic mirror of workspaces-cutover.sh's
# ACTUAL two-hop shape, found by running the detector against the real seed
# ledger — TS-15/TS-1 used a literal mapper or a single luksOpen and missed
# this. The real file has: (1) a `MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-
# workspaces}"` assignment on its own line, (2) the mapper-bearing luksOpen
# wrapped with a trailing shell line-continuation backslash, and (3) a SECOND,
# EARLIER-OR-LATER sibling `luksOpen --test-passphrase` escrow probe with NO
# mapper operand at all (device-only). A first-match-only scan either locks
# onto the wrong site or aborts entirely on the continuation backslash.
# ---------------------------------------------------------------------------
REPO_AC33="$TMPDIR_TEST/ac33"
write_file "$REPO_AC33/apps/web-platform/infra/workspaces-luks.tf" <<'EOF'
resource "random_password" "workspaces_luks" {
  length  = 40
  special = false
}

resource "doppler_secret" "workspaces_luks_key" {
  project = "soleur"
  config  = "prd_workspaces_luks"
  name    = "WORKSPACES_LUKS_KEY"
  value   = random_password.workspaces_luks.result
}

resource "hcloud_volume" "workspaces_luks" {
  name = "soleur-web-platform-data-luks"
}

resource "hcloud_volume_attachment" "workspaces_luks" {
  volume_id = hcloud_volume.workspaces_luks.id
  server_id = hcloud_server.web.id
}
EOF
write_file "$REPO_AC33/apps/web-platform/infra/workspaces-cutover.sh" <<'EOF'
#!/usr/bin/env bash
MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-workspaces}"
MAPPER="/dev/mapper/${MAPPER_NAME}"

prepare_luks_target() {
  KEY="$(read_key)"
  [ "$DRY_RUN" = "1" ] || printf '%s' "$KEY" | cryptsetup luksFormat --type luks2 --key-file - "$FRESH_DEV" \
    || die "luksFormat failed"
  printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME" \
    || die "luksOpen failed"
}

escrow_proof() {
  # A SIBLING luksOpen with NO mapper operand -- a passphrase test only.
  if printf '%s' "$KEY" | cryptsetup luksOpen --test-passphrase --key-file - "$FRESH_DEV" >/dev/null 2>&1; then
    log "escrow proof OK"
  fi
}
EOF
write_file "$REPO_AC33/apps/web-platform/infra/soleur-host-bootstrap.sh" <<'EOF'
#!/bin/sh
MOUNT=/mnt/data
MAPPER=/dev/mapper/workspaces
EOF
LEDGER_AC33="$TMPDIR_TEST/ac33-ledger.json"
write_file "$LEDGER_AC33" <<'EOF'
{
  "schema_version": 1,
  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks"] } },
  "non_store_types": ["hcloud_volume_attachment", "random_password", "doppler_secret"],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "hcloud_volume.workspaces_luks",
      "kind": "guest-luks-volume",
      "device_binding": {
        "volume": "hcloud_volume.workspaces_luks",
        "attachment": "hcloud_volume_attachment.workspaces_luks",
        "mapper": "workspaces"
      },
      "at_rest": {
        "mechanism": "luks",
        "evidence": "apps/web-platform/infra/workspaces-cutover.sh",
        "defends_against": "a seized or RMA'd disk; a raw volume snapshot",
        "does_not_defend": "a leaked service-role credential or a compromised host with the volume already unlocked",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no host probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "AC33 real-repo-shaped two-hop mapper (line-continuation + sibling --test-passphrase) certifies" 0 \
  "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_AC33" --ledger "$LEDGER_AC33" --today "$TODAY"

run_case_reports "TS-15 plaintext workspaces citing workspaces_luks apparatus -> FAIL (different volume)" 1 \
  "citation belongs to a different volume" \
  --repo-sweep --repo-root "$REPO_TS15" --ledger "$LEDGER_TS15" --today "$TODAY"

# Companion: the REAL workspaces_luks row, in the SAME ledger, independently
# PASSes (proves the false-PASS blocker doesn't also false-FAIL the legitimate
# row) — exit is still 1 overall (the sibling row fails), but the failing-line
# set must NOT include a message naming workspaces_luks.
out_ts15="$(python3 "$SUT" --repo-sweep --repo-root "$REPO_TS15" --ledger "$LEDGER_TS15" --today "$TODAY" 2>&1 || true)"
if grep -q 'FAIL:.*hcloud_volume\.workspaces_luks ' <<<"$out_ts15"; then
  fail "TS-15 companion: workspaces_luks row must not independently FAIL" "found a FAIL line naming workspaces_luks: $out_ts15"
else
  pass "TS-15 companion: workspaces_luks row must not independently FAIL"
fi

# ---------------------------------------------------------------------------
# TS-16: plaintext-exception with expires_on in the PAST -> FAIL expired
# ---------------------------------------------------------------------------
LEDGER_TS16="$TMPDIR_TEST/ts16-ledger.json"
mk_exception_ledger "$LEDGER_TS16" '{
          "justification": "Redis AOF encryption lands in a follow-up; the job payloads are short-lived",
          "tracking_issue": "#6600",
          "reevaluate_when": "when the Redis-to-LUKS cutover (mirrors #6588) ships",
          "expires_on": "2020-01-01"
        }'

run_case_reports "TS-16 plaintext-exception expires_on in the past -> FAIL expired" 1 "is in the past" \
  --repo-sweep --repo-root "$REPO_EXC" --ledger "$LEDGER_TS16" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-17: plaintext-exception disclosed_as a docs/legal fixture asserting
# "LUKS-encrypted" -> FAIL disclosed-as-encrypted (the exact #6588 join gap)
# ---------------------------------------------------------------------------
REPO_TS17="$TMPDIR_TEST/ts17"
write_file "$REPO_TS17/apps/web-platform/infra/inngest-redis.tf" <<'EOF'
resource "hcloud_volume" "inngest_redis" {
  name = "soleur-inngest-redis"
}
EOF
write_file "$REPO_TS17/docs/legal/privacy-policy.md" <<'EOF'
# Privacy Policy

## Job Queue Storage

In-flight job payloads are held in a LUKS-encrypted volume before processing.
EOF
LEDGER_TS17="$TMPDIR_TEST/ts17-ledger.json"
write_file "$LEDGER_TS17" <<'EOF'
{
  "schema_version": 1,
  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks", "plaintext-exception"] } },
  "non_store_types": [],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "hcloud_volume.inngest_redis",
      "kind": "guest-luks-volume",
      "at_rest": {
        "mechanism": "plaintext-exception",
        "evidence": "no LUKS apparatus provisioned for this volume yet",
        "defends_against": "nothing at rest; the AOF is plaintext ext4",
        "does_not_defend": "a seized or RMA'd disk; a raw volume snapshot",
        "disclosed_as": "docs/legal/privacy-policy.md:Job Queue Storage",
        "live_verification": "unavailable:no probe in this fixture",
        "exception": {
          "justification": "Redis AOF encryption lands in a follow-up; the job payloads are short-lived",
          "tracking_issue": "#6600",
          "reevaluate_when": "when the Redis-to-LUKS cutover (mirrors #6588) ships",
          "expires_on": "2099-01-01"
        }
      }
    }
  ],
  "connections": []
}
EOF

run_case_reports "TS-17 disclosed_as asserts encryption for a plaintext-exception -> FAIL" 1 \
  "asserts encryption" \
  --repo-sweep --repo-root "$REPO_TS17" --ledger "$LEDGER_TS17" --today "$TODAY"

# ---------------------------------------------------------------------------
# TS-18: plaintext-exception disclosed_as an UNRESOLVABLE docs/legal anchor
# -> FAIL closed (a moved/bogus disclosure anchor must not pass silently; the
# review-found fail-open where resolve_disclosed_as()==None short-circuited).
# ---------------------------------------------------------------------------
LEDGER_TS18="$TMPDIR_TEST/ts18-ledger.json"
sed 's#docs/legal/privacy-policy.md:Job Queue Storage#docs/legal/privacy-policy.md:No Such Anchor Xyzzy#' \
  "$LEDGER_TS17" > "$LEDGER_TS18"
run_case_reports "TS-18 disclosed_as anchor does not resolve for a plaintext-exception -> FAIL closed" 1 \
  "does not resolve" \
  --repo-sweep --repo-root "$REPO_TS17" --ledger "$LEDGER_TS18" --today "$TODAY"

# ===========================================================================
# Mutation battery — each MB copies the SUT, sed-deletes ONE marked branch,
# and asserts the paired fixture (already proven FAIL above) flips to PASS.
# A mutation that does NOT flip its fixture means the branch was vacuous.
# ===========================================================================

# run_mutation <label> <markers> <repo> <ledger> [want_rc] [needle] [base_rc]
#   base_rc (default 1): the UNMUTATED SUT's exit on this fixture.
#   want_rc (default 0): the mutant's exit. want_rc=1 on a base_rc=1 fixture
#     proves the REMAINING check holds the verdict alone; then `needle` must
#     name that check's FAIL, so a crash (also rc 1) cannot pass for it.
# Each marker must bracket exactly one non-empty region, end after start; the
# mutant must differ from the SUT and must print the sweep's summary line, so
# a truncated or unchanged mutant is never scored.
run_mutation() {
  local mb="$1" markers="$2" repo="$3" ledger="$4" want="${5:-0}" needle="${6:-}" base_want="${7:-1}"
  local base_rc=0
  python3 "$SUT" --repo-sweep --repo-root "$repo" --ledger "$ledger" --today "$TODAY" >/dev/null 2>&1 || base_rc=$?
  if [[ "$base_rc" != "$base_want" ]]; then
    fail "$mb baseline exits $base_want before mutation" "baseline exit=$base_rc for $ledger"
    return
  fi
  local mb_safe="${mb//\//_}"
  local mutated="$TMPDIR_TEST/mutated_${mb_safe// /_}.py"
  cp "$SUT" "$mutated"
  local m ns ne ls le
  for m in $markers; do
    ns=$(grep -cF "# MUTATION-TARGET: ${m} start" "$mutated" || true)
    ne=$(grep -cF "# MUTATION-TARGET: ${m} end" "$mutated" || true)
    if [[ "$ns" != "1" || "$ne" != "1" ]]; then
      fail "$mb marker $m brackets exactly one region" "start markers=$ns end markers=$ne"
      return
    fi
    ls=$(grep -nF "# MUTATION-TARGET: ${m} start" "$mutated" | cut -d: -f1) || true
    le=$(grep -nF "# MUTATION-TARGET: ${m} end" "$mutated" | cut -d: -f1) || true
    if (( le <= ls + 1 )); then
      fail "$mb marker $m brackets a non-empty region" "start line=$ls end line=$le"
      return
    fi
    sed -i "${ls},${le}d" "$mutated"
  done
  if cmp -s "$SUT" "$mutated"; then
    fail "$mb the mutant differs from the SUT" "no bytes changed"
    return
  fi
  if ! python3 -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" "$mutated" >/dev/null 2>&1; then
    fail "$mb mutated script must still compile" "syntax error after deleting $markers"
    return
  fi
  local mut_rc=0 out
  out="$(python3 "$mutated" --repo-sweep --repo-root "$repo" --ledger "$ledger" --today "$TODAY" 2>&1)" || mut_rc=$?
  if ! grep -qE '^encryption-posture: ' <<<"$out"; then
    fail "$mb the mutant ran to its summary line" "no summary line; output: ${out:0:300}"
    return
  fi
  local label
  if [[ "$base_want" == "1" && "$want" == "0" ]]; then
    label="$mb ($markers): deleting the branch flips FAIL->PASS (branch is load-bearing)"
  elif [[ "$base_want" == "0" ]]; then
    label="$mb ($markers): deleting the branch flips PASS->FAIL (the must-PASS fixture depends on it)"
  else
    label="$mb ($markers): the mutant still FAILs (the remaining check holds the verdict alone)"
  fi
  if [[ "$mut_rc" != "$want" ]]; then
    fail "$label" "mutated exit=$mut_rc (expected $want)"
  elif [[ -n "$needle" ]] && ! grep -qF "$needle" <<<"$out"; then
    fail "$label" "mutant output lacks the surviving check's FAIL '$needle'; output: ${out:0:300}"
  else
    pass "$label"
  fi
}

# Positive control for run_mutation: a fixture that does not FAIL at baseline
# must be scored as a failure. Reported via printf + exit, never through the
# helper under test (ADR-193), then unwound.
_pc_fail0=$FAIL; _pc_total0=$TOTAL
run_mutation "positive control (expected to FAIL)" "MB-9" "$REPO_TS1" "$LEDGER_TS1" >/dev/null
if [[ $((FAIL - _pc_fail0)) -ne 1 ]]; then
  printf 'GUARD FAIL: run_mutation could not record a failure\n' >&2
  exit 2
fi
FAIL=$_pc_fail0; TOTAL=$_pc_total0

# --- MB-1: the unledgered-store branch. Since #8532 PR-1 the floor is exact
# (check_store_id_accounted + check_non_iac_identity), so an unledgered address
# always reds the floor too and no fixture can isolate MB-1 by verdict alone.
# The old decoy row (a second row ledgered under a non-*.tf address) is now a
# FAIL in its own right. So MB-1 is proven two ways: deleting the floor alone
# leaves the FAIL standing (MB-1 holds the verdict by itself), and deleting
# both flips it. ---
REPO_MB1="$TMPDIR_TEST/mb1"
mk_git_data_base "$REPO_MB1"
cat >> "$REPO_MB1/apps/web-platform/infra/git-data-luks.tf" <<'EOF'

resource "hcloud_volume" "orphan_luks" {
  name = "soleur-orphan-luks-store"
}
EOF
LEDGER_MB1="$TMPDIR_TEST/mb1-ledger.json"
write_file "$LEDGER_MB1" <<'EOF'
{
  "schema_version": 1,
  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks", "plaintext-exception"] } },
  "non_store_types": ["hcloud_volume_attachment", "random_password", "doppler_secret"],
  "non_iac_stores": [],
  "stores": [
    {
      "store": "hcloud_volume.git_data_luks",
      "kind": "guest-luks-volume",
      "device_binding": {
        "volume": "hcloud_volume.git_data_luks",
        "attachment": "hcloud_volume_attachment.git_data_luks",
        "mapper": "git-data"
      },
      "at_rest": {
        "mechanism": "luks",
        "evidence": "apps/web-platform/infra/cloud-init-git-data.yml",
        "defends_against": "a seized or RMA'd disk; a raw volume snapshot",
        "does_not_defend": "a leaked service-role credential or a compromised host with the volume already unlocked",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no host probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "MB-1 fixture baseline: orphan_luks unledgered -> FAIL" 1 "unledgered store hcloud_volume.orphan_luks" \
  --repo-sweep --repo-root "$REPO_MB1" --ledger "$LEDGER_MB1" --today "$TODAY"
run_mutation "MB-1/floor-only" "MB-22" "$REPO_MB1" "$LEDGER_MB1" 1 "unledgered store hcloud_volume.orphan_luks"
run_mutation "MB-1" "MB-1 MB-22" "$REPO_MB1" "$LEDGER_MB1"

# --- MB-2: delete the citation-resolution step (accept the row's word) ->
# TS-2 AND TS-3 must both regress. ---
run_mutation "MB-2/TS-2" "MB-2" "$REPO_TS2" "$LEDGER_TS2"
run_mutation "MB-2/TS-3" "MB-2" "$REPO_TS3" "$LEDGER_TS3"

# --- MB-3: delete the boilerplate ban-list -> TS-4 must regress. ---
run_mutation "MB-3" "MB-3" "$REPO_TS4" "$LEDGER_TS4"

# --- MB-4: delete the tracking_issue requirement -> TS-6 must regress. ---
run_mutation "MB-4" "MB-4" "$REPO_EXC" "$LEDGER_TS6"

# --- MB-5: change unknown-type handling from FAIL to SKIP -> TS-8 must regress. ---
run_mutation "MB-5" "MB-5" "$REPO_TS8" "$LEDGER_TS8"

# --- MB-8: delete the volume-identity binding check -> TS-15 must regress
# (the R1 headline mutation: without it, the plaintext workspaces row
# false-PASSes on its sibling's apparatus). ---
run_mutation "MB-8" "MB-8" "$REPO_TS15" "$LEDGER_TS15"

# --- MB-9: delete the expires_on check -> TS-16 must regress. ---
run_mutation "MB-9" "MB-9" "$REPO_EXC" "$LEDGER_TS16"

# --- MB-11: delete the disclosed_as check -> TS-17 must regress. ---
run_mutation "MB-11" "MB-11" "$REPO_TS17" "$LEDGER_TS17"

# --- MB-12: delete a non-IaC floor row -> must red. This is a LEDGER
# mutation, not a script mutation: it proves the floor is computed from the
# committed non_iac_stores catalog, never from the ledger's own row count. ---
REPO_MB12="$TMPDIR_TEST/mb12"  # deliberately empty: no apps/ dir at all
mkdir -p "$REPO_MB12"
LEDGER_MB12_OK="$TMPDIR_TEST/mb12-ok-ledger.json"
write_file "$LEDGER_MB12_OK" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": ["supabase.prd"],
  "stores": [
    {
      "store": "supabase.prd",
      "kind": "provider-db",
      "at_rest": {
        "mechanism": "provider-managed:Supabase-SOC2-Type-II",
        "evidence": "Supabase trust center compliance page",
        "attestation_url": "https://supabase.com/security",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked service-role key or an RLS bypass",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF
LEDGER_MB12_BAD="$TMPDIR_TEST/mb12-bad-ledger.json"
write_file "$LEDGER_MB12_BAD" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": ["supabase.prd"],
  "stores": [],
  "connections": []
}
EOF
run_case_reports "MB-12 baseline: non-IaC row present -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_MB12" --ledger "$LEDGER_MB12_OK" --today "$TODAY"
run_case_reports "MB-12: deleting the non-IaC store row -> FAIL positive-work floor" 1 \
  "positive-work floor" \
  --repo-sweep --repo-root "$REPO_MB12" --ledger "$LEDGER_MB12_BAD" --today "$TODAY"

# ===========================================================================
# #8532 PR-1 — floor and anchor integrity.
#   P1-ID   check_non_iac_identity   every catalogued id names a stores[] row
#   P1-ACC  check_store_id_accounted every row is a *.tf store-class address or
#                                    a catalogued id, and no id repeats
#   P1-UNQ  resolve_disclosed_as     an anchor must occur EXACTLY once
#   P1-LUKS check_luks_disclosure    #8527: a luks row's disclosure line must
#                                    claim encryption and must not deny it
# Together ID + ACC make the positive-work floor exact: before them, deleting
# the committed supabase.prd row left the live sweep green (measured).
# ===========================================================================
REPO_P1="$TMPDIR_TEST/p1-empty"  # no apps/ dir: every row here is non-IaC
mkdir -p "$REPO_P1"

# mk_provider_row <store> — one provider-managed row JSON fragment.
mk_provider_row() {
  cat <<EOF
    {
      "store": "$1",
      "kind": "provider-db",
      "at_rest": {
        "mechanism": "provider-managed:Supabase-SOC2-Type-II",
        "evidence": "Supabase trust center compliance page",
        "attestation_url": "https://supabase.com/security",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked service-role key or an RLS bypass",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture"
      }
    }
EOF
}

# mk_catalog_ledger <out> <catalog-json-array> <row-id>... — an empty-repo
# ledger whose catalog and rows are given independently.
mk_catalog_ledger() {
  local out="$1" catalog="$2"; shift 2
  {
    echo '{ "schema_version": 1, "store_classes": {}, "non_store_types": [],'
    echo "  \"non_iac_stores\": $catalog,"
    echo '  "stores": ['
    local first=1 id
    for id in "$@"; do
      [[ "$first" == 1 ]] || echo '    ,'
      first=0
      mk_provider_row "$id"
    done
    echo '  ], "connections": [] }'
  } | write_file "$out"
}

LEDGER_P1_OK="$TMPDIR_TEST/p1-ok.json"
mk_catalog_ledger "$LEDGER_P1_OK" '["supabase.prd", "doppler.secrets"]' supabase.prd doppler.secrets
run_case_reports "P1-ID must-PASS: every catalogued id names a row" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P1_OK" --today "$TODAY"

LEDGER_P1_ID_DEL="$TMPDIR_TEST/p1-id-del.json"
mk_catalog_ledger "$LEDGER_P1_ID_DEL" '["supabase.prd", "doppler.secrets"]' doppler.secrets
run_case_reports "P1-ID catalogued row deleted -> FAIL naming the id" 1 \
  "non_iac_stores entry supabase.prd names no stores[] row" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P1_ID_DEL" --today "$TODAY"

LEDGER_P1_ID_CASE="$TMPDIR_TEST/p1-id-case.json"
mk_catalog_ledger "$LEDGER_P1_ID_CASE" '["Supabase.prd"]' supabase.prd
run_case_reports "P1-ID catalogued id differs from the row only in case -> FAIL" 1 \
  "non_iac_stores entry Supabase.prd names no stores[] row" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P1_ID_CASE" --today "$TODAY"

LEDGER_P1_ACC="$TMPDIR_TEST/p1-acc.json"
mk_catalog_ledger "$LEDGER_P1_ACC" '["supabase.prd"]' supabase.prd doppler.secrets
run_case_reports "P1-ACC row that is neither a *.tf address nor catalogued -> FAIL" 1 \
  "stores[] row doppler.secrets is not accounted for" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P1_ACC" --today "$TODAY"

LEDGER_P1_DUP="$TMPDIR_TEST/p1-dup.json"
mk_catalog_ledger "$LEDGER_P1_DUP" '["supabase.prd"]' supabase.prd supabase.prd
run_case_reports "P1-ACC duplicate stores[] id (floor slack) -> FAIL" 1 \
  "duplicate stores[] row supabase.prd" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P1_DUP" --today "$TODAY"

# A row keyed on a *.tf address whose TYPE is not a store class is outside the
# floor's tf_store_count, so it is slack exactly like an uncatalogued id.
REPO_P1_NST="$TMPDIR_TEST/p1-nst"
write_file "$REPO_P1_NST/apps/web-platform/infra/server.tf" <<'EOF'
resource "hcloud_server" "web" {
  name = "soleur-web-platform"
}
EOF
LEDGER_P1_NST="$TMPDIR_TEST/p1-nst.json"
{
  echo '{ "schema_version": 1, "store_classes": {}, "non_store_types": ["hcloud_server"],'
  echo '  "non_iac_stores": [], "stores": ['
  mk_provider_row "hcloud_server.web"
  echo '  ], "connections": [] }'
} > "$LEDGER_P1_NST"
run_case_reports "P1-ACC row keyed on a non-store-class *.tf address -> FAIL" 1 \
  "stores[] row hcloud_server.web is not accounted for" \
  --repo-sweep --repo-root "$REPO_P1_NST" --ledger "$LEDGER_P1_NST" --today "$TODAY"

# --- disclosed_as uniqueness (P1-UNQ). A plaintext-exception fixture whose
# document carries NO encryption vocabulary, so the only thing that can fail
# is the resolver itself. ---
REPO_P1_UNQ="$TMPDIR_TEST/p1-unq"
write_file "$REPO_P1_UNQ/apps/web-platform/infra/inngest-redis.tf" <<'EOF'
resource "hcloud_volume" "inngest_redis" {
  name = "soleur-inngest-redis"
}
EOF
write_file "$REPO_P1_UNQ/docs/legal/privacy-policy.md" <<'EOF'
# Privacy Policy

## Job Queue Storage

In-flight job payloads are held on a volume before processing.

## Retention

See Job Queue Storage above for where payloads are held.
EOF
LEDGER_P1_UNQ_TWICE="$TMPDIR_TEST/p1-unq-twice.json"
cp "$LEDGER_TS17" "$LEDGER_P1_UNQ_TWICE"  # the P1-UNQ document names this anchor twice
run_case_reports "P1-UNQ disclosed_as anchor occurs twice -> FAIL ambiguous" 1 \
  "is ambiguous (anchor occurs 2 times" \
  --repo-sweep --repo-root "$REPO_P1_UNQ" --ledger "$LEDGER_P1_UNQ_TWICE" --today "$TODAY"
LEDGER_P1_UNQ_ONCE="$TMPDIR_TEST/p1-unq-once.json"
sed 's|privacy-policy.md:Job Queue Storage|privacy-policy.md:## Job Queue Storage|' \
  "$LEDGER_TS17" > "$LEDGER_P1_UNQ_ONCE"
run_case_reports "P1-UNQ must-PASS: the same document, anchor occurring once" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P1_UNQ" --ledger "$LEDGER_P1_UNQ_ONCE" --today "$TODAY"
LEDGER_P1_UNQ_NONE="$TMPDIR_TEST/p1-unq-none.json"
sed 's#privacy-policy.md:Job Queue Storage#privacy-policy.md:No Such Anchor Xyzzy#' \
  "$LEDGER_TS17" > "$LEDGER_P1_UNQ_NONE"
run_case_reports "P1-UNQ disclosed_as anchor absent -> FAIL, a message distinct from ambiguous" 1 \
  "does not resolve (anchor not found" \
  --repo-sweep --repo-root "$REPO_P1_UNQ" --ledger "$LEDGER_P1_UNQ_NONE" --today "$TODAY"

# --- #8527 (P1-LUKS). The git-data apparatus fixture, its row pointed at a
# synthesized disclosure line. The anchor text itself is removed from the line
# before either predicate runs, so an anchor spelled "Encrypted …" cannot
# satisfy the claim on the body's behalf. ---
mk_luks_disclosure_case() {
  local name="$1" line="$2"
  local repo="$TMPDIR_TEST/p1-luks-$name"
  mk_git_data_base "$repo"
  printf '# Privacy Policy\n\n%s\n' "$line" | write_file "$repo/docs/legal/privacy-policy.md"
  local ledger="$TMPDIR_TEST/p1-luks-$name.json"
  mk_git_data_ledger "$TMPDIR_TEST/p1-luks-$name-base.json"
  sed 's#"disclosed_as": "not-publicly-claimed"#"disclosed_as": "docs/legal/privacy-policy.md:Encrypted storage"#' \
    "$TMPDIR_TEST/p1-luks-$name-base.json" > "$ledger"
  P1_REPO="$repo"; P1_LEDGER="$ledger"
}

mk_luks_disclosure_case ok '- **Encrypted storage:** the volume is **LUKS-encrypted (encryption at rest)**.'
run_case_reports "P1-LUKS must-PASS: disclosure line claims encryption" 0 "0 failing checks" \
  --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"

# The register's own mandated form: the naive LUKS|encrypt regex PASSES this.
mk_luks_disclosure_case absent '- **Encrypted storage:** encryption at rest is ABSENT for this volume.'
REPO_P1_LUKS_ABSENT="$P1_REPO"; LEDGER_P1_LUKS_ABSENT="$P1_LEDGER"
run_case_reports "P1-LUKS disclosure says encryption at rest is ABSENT -> FAIL denies" 1 \
  "denies encryption in its claim sentence" \
  --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"

mk_luks_disclosure_case not '- **Encrypted storage:** this volume is not encrypted.'
run_case_reports "P1-LUKS disclosure says 'not encrypted' -> FAIL denies" 1 \
  "denies encryption in its claim sentence" \
  --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"

mk_luks_disclosure_case unenc '- **Encrypted storage:** workspace data sits on an unencrypted volume.'
run_case_reports "P1-LUKS disclosure says 'unencrypted' -> FAIL denies" 1 \
  "denies encryption in its claim sentence" \
  --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"

mk_luks_disclosure_case drift '- **Encrypted storage:** workspace data is stored on a Hetzner volume.'
REPO_P1_LUKS_DRIFT="$P1_REPO"; LEDGER_P1_LUKS_DRIFT="$P1_LEDGER"
run_case_reports "P1-LUKS disclosure drifted: only the anchor says Encrypted -> FAIL no claim" 1 \
  "does not claim encryption at rest in its claim sentence" \
  --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"

mk_luks_disclosure_case dup "$(printf -- '- **Encrypted storage:** LUKS-encrypted.\n- **Encrypted storage:** LUKS-encrypted.')"
run_case_reports "P1-LUKS luks disclosure anchor occurs twice -> FAIL ambiguous" 1 \
  "is ambiguous (anchor occurs 2 times" \
  --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"

# --- Mutation rows MB-17..MB-21 (+ MB-22, the floor's own FAIL branch, which
# P1-ID shares a verdict with). ---
run_mutation "MB-17/floor-only" "MB-22" "$REPO_P1" "$LEDGER_P1_ID_DEL" 1 "non_iac_stores entry supabase.prd names no stores[] row"
run_mutation "MB-17" "MB-17 MB-22" "$REPO_P1" "$LEDGER_P1_ID_DEL"
run_mutation "MB-18" "MB-18" "$REPO_P1_UNQ" "$LEDGER_P1_UNQ_TWICE"
run_mutation "MB-19" "MB-19" "$REPO_P1_UNQ" "$LEDGER_P1_UNQ_NONE"
run_mutation "MB-20/absent" "MB-20" "$REPO_P1_LUKS_ABSENT" "$LEDGER_P1_LUKS_ABSENT"
run_mutation "MB-20/drift" "MB-20" "$REPO_P1_LUKS_DRIFT" "$LEDGER_P1_LUKS_DRIFT"
run_mutation "MB-21/uncatalogued" "MB-21" "$REPO_P1" "$LEDGER_P1_ACC"
run_mutation "MB-21/duplicate" "MB-21" "$REPO_P1" "$LEDGER_P1_DUP"
run_mutation "MB-21/non-store-type" "MB-21" "$REPO_P1_NST" "$LEDGER_P1_NST"

# ===========================================================================
# #8532 PR-2 — instance multiplicity (Guard 2), orphan rows, kind parity.
# One ledger row is keyed on <type>.<name>, but a `for_each`/`count` block is
# several devices. hcloud_volume.workspaces is for_each over var.web_hosts
# while workspaces_luks is a singleton, so web-2 has no encrypted volume and
# the ledger said nothing. Shapes:
#   for_each = var.<map> with a resolvable default literal -> instances compared
#   count, any other for_each, a module-instantiated block  -> fail CLOSED unless
#     the row declares instances: [] (nothing can verify a list) and its
#     exception's reevaluate_when names a var./local./module. gate from the
#     block's own expression
#   singleton                                              -> must NOT declare
# ===========================================================================

# mk_exc_row <store> <multiplicity-json-or-empty> <reevaluate_when>
mk_exc_row() {
  local store="$1" mult="$2" reeval="$3"
  local mline=""
  [[ -n "$mult" ]] && mline="\"multiplicity\": $mult,"
  cat <<EOF
    {
      "store": "$store",
      "kind": "guest-luks-volume",
      $mline
      "at_rest": {
        "mechanism": "plaintext-exception",
        "evidence": "fixture: no LUKS apparatus for this volume",
        "defends_against": "nothing at the volume layer",
        "does_not_defend": "a seized or RMA'd disk; a raw volume snapshot",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture",
        "exception": {
          "justification": "fixture exception exercising the multiplicity check",
          "tracking_issue": "#1",
          "reevaluate_when": "$reeval",
          "expires_on": "2099-01-01"
        }
      }
    }
EOF
}

# mk_mult_repo <dir> <web_hosts-default-body> — a TF root with a for_each
# volume over var.web_hosts, a singleton volume, and a count-gated volume.
mk_mult_repo() {
  local d="$1" body="$2"
  write_file "$d/apps/web-platform/infra/variables.tf" <<EOF
variable "web_hosts" {
  description = "fixture"
  type = map(object({
    location = string
  }))
  default = {
$body
  }
}
EOF
  write_file "$d/apps/web-platform/infra/server.tf" <<'EOF'
resource "hcloud_volume" "workspaces" {
  for_each = var.web_hosts # one per host
  name     = "soleur-${each.key}-data"
}

resource "hcloud_volume" "solo" {
  name = "soleur-solo"
  labels = {
    count = "not-a-meta-argument"
  }
}

locals {
  extra_enabled = var.enable_extra
}

resource "hcloud_volume" "extra" {
  count = local.extra_enabled ? 1 : 0
  name  = "soleur-extra"
}
EOF
}

TWO_HOSTS='    "web-1" = { location = "hel1" }
    "web-2" = {
      location = "hel1"
    }'

# mk_mult_ledger <out> <workspaces-mult> <solo-mult> <extra-mult> <extra-reeval>
mk_mult_ledger() {
  local out="$1"
  {
    echo '{ "schema_version": 1,'
    echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
    echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
    mk_exc_row "hcloud_volume.workspaces" "$2" "$REEVAL_DEF"
    echo '    ,'
    mk_exc_row "hcloud_volume.solo" "$3" "$REEVAL_DEF"
    echo '    ,'
    mk_exc_row "hcloud_volume.extra" "$4" "$5"
    echo '  ], "connections": [] }'
  } | write_file "$out"
}

REEVAL_DEF="when the fixture volume is next re-provisioned"
WS_OK='{ "instances": ["web-1", "web-2"] }'
EXTRA_OK='{ "instances": [] }'
EXTRA_REEVAL='when local.extra_enabled first turns on (var.enable_extra)'

REPO_P2="$TMPDIR_TEST/p2-mult"
mk_mult_repo "$REPO_P2" "$TWO_HOSTS"
LEDGER_P2_OK="$TMPDIR_TEST/p2-ok.json"
mk_mult_ledger "$LEDGER_P2_OK" "$WS_OK" "" "$EXTRA_OK" "$EXTRA_REEVAL"
run_case_reports "P2-MULT must-PASS: for_each instances match, singleton undeclared, count gated" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_OK" --today "$TODAY"

# Guard 2 matrix #1: a third key added to the map, row unchanged.
REPO_P2_ADD="$TMPDIR_TEST/p2-add"
mk_mult_repo "$REPO_P2_ADD" "$TWO_HOSTS
    \"web-3\" = { location = \"hel1\" }"
run_case_reports "P2-MULT a key added to the for_each map, row unchanged -> FAIL" 1 \
  "hcloud_volume.workspaces covers instances [web-1, web-2] but var.web_hosts declares [web-1, web-2, web-3]" \
  --repo-sweep --repo-root "$REPO_P2_ADD" --ledger "$LEDGER_P2_OK" --today "$TODAY"

# Guard 2 matrix #3, with the SECOND member the offender.
LEDGER_P2_SECOND="$TMPDIR_TEST/p2-second.json"
mk_mult_ledger "$LEDGER_P2_SECOND" '{ "instances": ["web-1", "web-9"] }' "" "$EXTRA_OK" "$EXTRA_REEVAL"
run_case_reports "P2-MULT declared instances disagree in the second member -> FAIL" 1 \
  "covers instances [web-1, web-9] but var.web_hosts declares [web-1, web-2]" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_SECOND" --today "$TODAY"

# Guard 2 matrix #2: multiplicity deleted from the for_each row.
LEDGER_P2_NOMULT="$TMPDIR_TEST/p2-nomult.json"
mk_mult_ledger "$LEDGER_P2_NOMULT" "" "" "$EXTRA_OK" "$EXTRA_REEVAL"
run_case_reports "P2-MULT for_each row with no multiplicity -> FAIL" 1 \
  "hcloud_volume.workspaces is for_each = var.web_hosts but declares no multiplicity" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_NOMULT" --today "$TODAY"

LEDGER_P2_SOLO="$TMPDIR_TEST/p2-solo.json"
mk_mult_ledger "$LEDGER_P2_SOLO" "$WS_OK" '{ "instances": ["a"] }' "$EXTRA_OK" "$EXTRA_REEVAL"
run_case_reports "P2-MULT singleton block declaring multiplicity -> FAIL" 1 \
  "hcloud_volume.solo declares multiplicity but its block is a singleton" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_SOLO" --today "$TODAY"

LEDGER_P2_CNT_NONE="$TMPDIR_TEST/p2-cnt-none.json"
mk_mult_ledger "$LEDGER_P2_CNT_NONE" "$WS_OK" "" "" "$EXTRA_REEVAL"
run_case_reports "P2-MULT count-gated row with no multiplicity -> FAIL closed" 1 \
  "hcloud_volume.extra is count = local.extra_enabled ? 1 : 0, which this check cannot resolve" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_CNT_NONE" --today "$TODAY"

LEDGER_P2_CNT_GATE="$TMPDIR_TEST/p2-cnt-gate.json"
mk_mult_ledger "$LEDGER_P2_CNT_GATE" "$WS_OK" "" '{ "instances": ["0"] }' "$EXTRA_REEVAL"
run_case_reports "P2-MULT a count-gated row declaring an unverifiable instance list -> FAIL" 1 \
  "whose instances this check cannot verify, yet it declares a list" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_CNT_GATE" --today "$TODAY"

LEDGER_P2_CNT_REEVAL="$TMPDIR_TEST/p2-cnt-reeval.json"
mk_mult_ledger "$LEDGER_P2_CNT_REEVAL" "$WS_OK" "" "$EXTRA_OK" "at the next quarterly review"
run_case_reports "P2-MULT reevaluate_when does not name the gate -> FAIL" 1 \
  "exception.reevaluate_when must name one of local.extra_enabled" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_CNT_REEVAL" --today "$TODAY"

# A store-class block inside a module source directory is instantiated once
# per module call: fail closed unless gated on the module call itself.
REPO_P2_MOD="$TMPDIR_TEST/p2-mod"
write_file "$REPO_P2_MOD/apps/web-platform/infra/main.tf" <<'EOF'
module "vols" {
  source = "./modules/vols"
}
EOF
write_file "$REPO_P2_MOD/apps/web-platform/infra/modules/vols/main.tf" <<'EOF'
resource "hcloud_volume" "inner" {
  name = "soleur-inner"
}
EOF
mk_mod_ledger() {
  {
    echo '{ "schema_version": 1,'
    echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
    echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
    mk_exc_row "hcloud_volume.inner" "$2" "$3"
    echo '  ], "connections": [] }'
  } | write_file "$1"
}
LEDGER_P2_MOD_BAD="$TMPDIR_TEST/p2-mod-bad.json"
mk_mod_ledger "$LEDGER_P2_MOD_BAD" "" "$REEVAL_DEF"
run_case_reports "P2-MULT module-instantiated block with no multiplicity -> FAIL closed" 1 \
  "hcloud_volume.inner is instantiated by module.vols" \
  --repo-sweep --repo-root "$REPO_P2_MOD" --ledger "$LEDGER_P2_MOD_BAD" --today "$TODAY"
LEDGER_P2_MOD_OK="$TMPDIR_TEST/p2-mod-ok.json"
mk_mod_ledger "$LEDGER_P2_MOD_OK" '{ "instances": [] }' "when module.vols gains a count or for_each"
run_case_reports "P2-MULT must-PASS: module-instantiated block gated on its module call" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P2_MOD" --ledger "$LEDGER_P2_MOD_OK" --today "$TODAY"

# 4b: a row whose address parses to a store-class type must be a real block,
# even when it is also catalogued (a catalogue entry cannot launder a ghost).
LEDGER_P2_GHOST="$TMPDIR_TEST/p2-ghost.json"
{
  echo '{ "schema_version": 1,'
  echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
  echo '  "non_store_types": [], "non_iac_stores": ["hcloud_volume.ghost"], "stores": ['
  mk_exc_row "hcloud_volume.ghost" "" "$REEVAL_DEF"
  echo '  ], "connections": [] }'
} | write_file "$LEDGER_P2_GHOST"
run_case_reports "P2-ORPHAN catalogued row at a store-class address with no *.tf block -> FAIL" 1 \
  "stores[] row hcloud_volume.ghost names a store_classes type but no *.tf block declares it" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P2_GHOST" --today "$TODAY"

# Schema parity: the validator never reads the schema file, so the two can
# drift silently. Every kind enum and the store property set must agree.
if python3 - "$SUT" "$SCRIPT_DIR/encryption-posture-ledger.schema.json" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("lep", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
s = json.load(open(sys.argv[2]))
store = s["definitions"]["store"]
checks = {
    "STORE_KIND_ENUM": (set(m.STORE_KIND_ENUM), set(store["properties"]["kind"]["enum"])),
    "STORE_CLASS_KIND_ENUM": (set(m.STORE_CLASS_KIND_ENUM),
        set(s["properties"]["store_classes"]["additionalProperties"]["properties"]["kind"]["enum"])),
    "STORE_KEYS": (set(m.STORE_KEYS), set(store["properties"])),
}
bad = [f"{k}: script={sorted(a)} schema={sorted(b)}" for k, (a, b) in checks.items() if a != b]
if "host-root-disk" not in m.STORE_CLASS_KIND_ENUM:
    bad.append("host-root-disk missing from STORE_CLASS_KIND_ENUM")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PYEOF
then pass "P2-SCHEMA script enums and store keys equal the schema's (incl. host-root-disk)"
else fail "P2-SCHEMA script enums and store keys equal the schema's (incl. host-root-disk)" "see diff above"
fi

LEDGER_P2_TYPO="$TMPDIR_TEST/p2-typo.json"
sed 's/"multiplicity": {/"multiplicty": {/' "$LEDGER_P2_OK" > "$LEDGER_P2_TYPO.tmp"
write_file "$LEDGER_P2_TYPO" < "$LEDGER_P2_TYPO.tmp"
run_case_reports "P2-SCHEMA a misspelled row key is rejected, never ignored" 1 \
  "unexpected key(s) ['multiplicty']" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_TYPO" --today "$TODAY"

# A multi-line for_each (the idiomatic `{ for k, v in var.x : k => v }`) is read
# whole, so its gate is visible; it is a shape this check cannot resolve.
REPO_P2_ML="$TMPDIR_TEST/p2-ml"
write_file "$REPO_P2_ML/apps/web-platform/infra/variables.tf" <<'EOF'
variable "web_hosts" {
  default = {
    "web-1" = { location = "hel1" }
  }
}
EOF
write_file "$REPO_P2_ML/apps/web-platform/infra/ml.tf" <<'EOF'
resource "hcloud_volume" "ml" {
  for_each = {
    for k, v in var.web_hosts : k => v
  }
  name = "soleur-${each.key}"
}
EOF
mk_ml_ledger() {
  {
    echo '{ "schema_version": 1,'
    echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
    echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
    mk_exc_row "hcloud_volume.ml" "$2" "$3"
    echo '  ], "connections": [] }'
  } | write_file "$1"
}
LEDGER_P2_ML_BAD="$TMPDIR_TEST/p2-ml-bad.json"
mk_ml_ledger "$LEDGER_P2_ML_BAD" "" "$REEVAL_DEF"
run_case_reports "P2-MULT a multi-line for_each over one var map is read whole and compared" 1 \
  "hcloud_volume.ml is for_each = { for k, v in var.web_hosts : k => v } but declares no multiplicity" \
  --repo-sweep --repo-root "$REPO_P2_ML" --ledger "$LEDGER_P2_ML_BAD" --today "$TODAY"
LEDGER_P2_ML_OK="$TMPDIR_TEST/p2-ml-ok.json"
mk_ml_ledger "$LEDGER_P2_ML_OK" '{ "instances": ["web-1"] }' "when var.web_hosts gains a host"
run_case_reports "P2-MULT must-PASS: the wrapped for_each declares the map's keys" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P2_ML" --ledger "$LEDGER_P2_ML_OK" --today "$TODAY"

# The sweep reads what is COMMITTED. In a git work tree an untracked *.tf (or a
# gitignored *.tfvars) changes nothing; the moment it is tracked, it counts.
# Outside a git tree (every other fixture here) a .terraform/ cache is skipped.
git_clean() {
  local unset_args=() v
  for v in $(compgen -e); do [[ "$v" == GIT_* ]] && unset_args+=(-u "$v"); done
  env "${unset_args[@]}" git "$@"
}
REPO_P2_GIT="$TMPDIR_TEST/p2-git"
mk_git_data_base "$REPO_P2_GIT"
git_clean -C "$REPO_P2_GIT" init -q
git_clean -C "$REPO_P2_GIT" add -A
write_file "$REPO_P2_GIT/apps/web-platform/infra/untracked.tf" <<'EOF'
resource "hcloud_volume" "untracked" {
  name = "soleur-untracked"
}
EOF
printf 'web_hosts = {}\n' | write_file "$REPO_P2_GIT/apps/web-platform/infra/terraform.tfvars"
run_case_reports "P2-HERMETIC an untracked *.tf and a *.tfvars do not change the verdict" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P2_GIT" --ledger "$LEDGER_TS1" --today "$TODAY"
git_clean -C "$REPO_P2_GIT" add apps/web-platform/infra/untracked.tf
run_case_reports "P2-HERMETIC control: the same file, tracked, is an unledgered store" 1 \
  "unledgered store hcloud_volume.untracked" \
  --repo-sweep --repo-root "$REPO_P2_GIT" --ledger "$LEDGER_TS1" --today "$TODAY"
REPO_P2_TFC="$TMPDIR_TEST/p2-tfcache"
mk_git_data_base "$REPO_P2_TFC"
write_file "$REPO_P2_TFC/apps/web-platform/infra/.terraform/modules/x/main.tf" <<'EOF'
resource "hcloud_volume" "cached" {
  name = "provider-cache-copy"
}
EOF
run_case_reports "P2-HERMETIC a .terraform/ provider cache is not scanned" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P2_TFC" --ledger "$LEDGER_TS1" --today "$TODAY"

# The floor's operands must be disjoint sets (MB-29): one address in two
# Terraform roots, a catalogued id that is also a *.tf address, a catalogue
# entry listed twice.
REPO_P2_ROOTS="$TMPDIR_TEST/p2-roots"
for r in a b; do
  write_file "$REPO_P2_ROOTS/apps/$r/infra/v.tf" <<'EOF'
resource "hcloud_volume" "v" {
  name = "soleur-v"
}
EOF
done
LEDGER_P2_ROOTS="$TMPDIR_TEST/p2-roots.json"
{
  echo '{ "schema_version": 1,'
  echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
  echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
  mk_exc_row "hcloud_volume.v" "" "$REEVAL_DEF"
  echo '  ], "connections": [] }'
} | write_file "$LEDGER_P2_ROOTS"
run_case_reports "P2-UNIQ one store address declared in two Terraform roots -> FAIL" 1 \
  "store address hcloud_volume.v is declared by 2 *.tf blocks" \
  --repo-sweep --repo-root "$REPO_P2_ROOTS" --ledger "$LEDGER_P2_ROOTS" --today "$TODAY"
LEDGER_P2_DUPCAT="$TMPDIR_TEST/p2-dupcat.json"
mk_catalog_ledger "$LEDGER_P2_DUPCAT" '["supabase.prd", "supabase.prd"]' supabase.prd
run_case_reports "P2-UNIQ a catalogue entry listed twice -> FAIL" 1 \
  "non_iac_stores entry supabase.prd is listed more than once" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_P2_DUPCAT" --today "$TODAY"
REPO_P2_OVL="$TMPDIR_TEST/p2-ovl"
write_file "$REPO_P2_OVL/apps/web-platform/infra/v.tf" <<'EOF'
resource "hcloud_volume" "v" {
  name = "soleur-v"
}
EOF
LEDGER_P2_OVL="$TMPDIR_TEST/p2-ovl.json"
sed 's/"non_iac_stores": \[\]/"non_iac_stores": ["hcloud_volume.v"]/' "$LEDGER_P2_ROOTS" > "$TMPDIR_TEST/p2-ovl.tmp"
write_file "$LEDGER_P2_OVL" < "$TMPDIR_TEST/p2-ovl.tmp"
run_case_reports "P2-UNIQ a catalogued id that is also a *.tf address -> FAIL" 1 \
  "non_iac_stores entry hcloud_volume.v is also a *.tf store address" \
  --repo-sweep --repo-root "$REPO_P2_OVL" --ledger "$LEDGER_P2_OVL" --today "$TODAY"

# A row at a store-class address conforms to that class (MB-30).
LEDGER_P2_CLS="$TMPDIR_TEST/p2-cls.json"
{
  echo '{ "schema_version": 1,'
  echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
  echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
  mk_provider_row "hcloud_volume.v"
  echo '  ], "connections": [] }'
} | write_file "$LEDGER_P2_CLS"
run_case_reports "P2-CLASS a row whose kind differs from its store class -> FAIL" 1 \
  "hcloud_volume.v kind provider-db differs from its store class kind guest-luks-volume" \
  --repo-sweep --repo-root "$REPO_P2_OVL" --ledger "$LEDGER_P2_CLS" --today "$TODAY"
run_case_reports "P2-CLASS a mechanism its store class does not admit -> FAIL" 1 \
  "is not one its store class admits (plaintext-exception)" \
  --repo-sweep --repo-root "$REPO_P2_OVL" --ledger "$LEDGER_P2_CLS" --today "$TODAY"

run_mutation "MB-14/add-key" "MB-14" "$REPO_P2_ADD" "$LEDGER_P2_OK"
run_mutation "MB-14/second-member" "MB-14" "$REPO_P2" "$LEDGER_P2_SECOND"
run_mutation "MB-14/no-multiplicity" "MB-14" "$REPO_P2" "$LEDGER_P2_NOMULT"
run_mutation "MB-23" "MB-23" "$REPO_P1" "$LEDGER_P2_GHOST"
run_mutation "MB-24/count" "MB-24" "$REPO_P2" "$LEDGER_P2_CNT_NONE"
run_mutation "MB-24/gate" "MB-24" "$REPO_P2" "$LEDGER_P2_CNT_GATE"
run_mutation "MB-24/reeval" "MB-24" "$REPO_P2" "$LEDGER_P2_CNT_REEVAL"
run_mutation "MB-24/module" "MB-24" "$REPO_P2_MOD" "$LEDGER_P2_MOD_BAD"
run_mutation "MB-25" "MB-25" "$REPO_P2" "$LEDGER_P2_SOLO"
run_mutation "MB-29/two-roots" "MB-29" "$REPO_P2_ROOTS" "$LEDGER_P2_ROOTS"
run_mutation "MB-29/dup-catalogue" "MB-29" "$REPO_P1" "$LEDGER_P2_DUPCAT"
run_mutation "MB-30" "MB-30" "$REPO_P2_OVL" "$LEDGER_P2_CLS"

# ===========================================================================
# #8532 PR-3 — record anchors (Guard 3). A record surface (the Article 30
# register, model.c4) states a store's at-rest posture through a visible,
# self-describing clause:
#   (encryption-posture ledger: <store id> — at rest: <mechanism>)
# compared by EQUALITY with the row's mechanism, never by a regex over prose.
# Forward: each stores[].records entry ("path" or "path#<heading prefix>")
# resolves to exactly one clause for that store in that section, and agrees.
# Reverse: every clause in every record_surfaces file names a live row that
# lists that section. Anchors are per SECTION: one store is stated under
# several processing activities.
# ===========================================================================
REPO_P3="$TMPDIR_TEST/p3"
write_file "$REPO_P3/apps/web-platform/infra/v.tf" <<'EOF'
resource "hcloud_volume" "v" {
  name = "soleur-v"
}

resource "hcloud_volume" "w" {
  name = "soleur-w"
}
EOF
# mk_p3_register <pa1-clause> <pa13-clause> [extra line appended to PA-1]
mk_p3_register() {
  write_file "$REPO_P3/kb/register.md" <<EOF
# Register

## Processing Activity 1 — Accounts

| **(e) At rest** | Stored on the volume. $1 |
${3:-}

## Processing Activity 13 — Queue

| **(e) At rest** | Queue data. $2 |

## Register Maintenance

A store's posture is anchored as (encryption-posture ledger: <store id> — at rest: <mechanism>).
EOF
}
write_file "$REPO_P3/kb/model.c4" <<'EOF'
model {
  vol = container "Volume" {
    // (encryption-posture ledger: hcloud_volume.v — at rest: plaintext-exception)
    description "the volume"
  }
}
EOF
CL_V='(encryption-posture ledger: hcloud_volume.v — at rest: plaintext-exception)'

# mk_p3_ledger <out> <v-records-json> [surfaces-json]
mk_p3_ledger() {
  local out="$1" recs="$2" surfaces="${3:-[\"kb/register.md\", \"kb/model.c4\"]}"
  {
    echo '{ "schema_version": 1,'
    echo "  \"record_surfaces\": $surfaces,"
    echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
    echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
    mk_exc_row "hcloud_volume.v" "" "$REEVAL_DEF" | sed "s|\"kind\": \"guest-luks-volume\",|\"kind\": \"guest-luks-volume\", \"records\": $recs,|"
    echo '    ,'
    mk_exc_row "hcloud_volume.w" "" "$REEVAL_DEF"
    echo '  ], "connections": [] }'
  } | write_file "$out"
}
RECS_OK='["kb/register.md#Processing Activity 1", "kb/register.md#Processing Activity 13", "kb/model.c4"]'
LEDGER_P3_OK="$TMPDIR_TEST/p3-ok.json"
mk_p3_ledger "$LEDGER_P3_OK" "$RECS_OK"

mk_p3_register "$CL_V" "$CL_V"
run_case_reports "P3 must-PASS: clauses agree per section; a row with no records; a template line" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P3" --ledger "$LEDGER_P3_OK" --today "$TODAY"

# Guard 3 matrix #3: the record contradicts the row's mechanism.
mk_p3_register "$CL_V" '(encryption-posture ledger: hcloud_volume.v — at rest: luks)'
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-mech"; REPO_P3_MECH="$TMPDIR_TEST/p3-mech"
run_case_reports "P3 record states a different mechanism than the row -> FAIL" 1 \
  "hcloud_volume.v record kb/register.md#Processing Activity 13 states at rest: luks but the row's mechanism is plaintext-exception" \
  --repo-sweep --repo-root "$REPO_P3_MECH" --ledger "$LEDGER_P3_OK" --today "$TODAY"

# Guard 3 matrix #2: the anchored clause duplicated inside one section.
mk_p3_register "$CL_V" "$CL_V" "| **(g) Security** | Also on the volume. $CL_V |"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-dup"; REPO_P3_DUP="$TMPDIR_TEST/p3-dup"
run_case_reports "P3 clause occurs twice in one section -> FAIL" 1 \
  "clause for hcloud_volume.v occurs 2 times in kb/register.md#Processing Activity 1" \
  --repo-sweep --repo-root "$REPO_P3_DUP" --ledger "$LEDGER_P3_OK" --today "$TODAY"

# Guard 3 matrix #1: a clause naming a store id no row has (a renamed store).
mk_p3_register "$CL_V" "$CL_V" "| **(g) Security** | Old volume. (encryption-posture ledger: hcloud_volume.gone — at rest: plaintext-exception) |"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-ghost"; REPO_P3_GHOST="$TMPDIR_TEST/p3-ghost"
run_case_reports "P3 clause names a store id with no row -> FAIL" 1 \
  "kb/register.md#Processing Activity 1 carries a clause for hcloud_volume.gone, which names no stores[] row" \
  --repo-sweep --repo-root "$REPO_P3_GHOST" --ledger "$LEDGER_P3_OK" --today "$TODAY"

# A clause in a section the row's records do not list (reverse completeness).
LEDGER_P3_PA1="$TMPDIR_TEST/p3-pa1.json"
mk_p3_ledger "$LEDGER_P3_PA1" '["kb/register.md#Processing Activity 1", "kb/model.c4"]'
mk_p3_register "$CL_V" "$CL_V"
run_case_reports "P3 clause in a section the row does not list -> FAIL" 1 \
  "kb/register.md#Processing Activity 13 carries a clause for hcloud_volume.v, which its row's records do not list" \
  --repo-sweep --repo-root "$REPO_P3" --ledger "$LEDGER_P3_PA1" --today "$TODAY"

# A listed section with no clause (forward resolution).
mk_p3_register "$CL_V" "no anchor here"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-none"; REPO_P3_NONE="$TMPDIR_TEST/p3-none"
run_case_reports "P3 listed section carries no clause -> FAIL" 1 \
  "no clause for hcloud_volume.v in kb/register.md#Processing Activity 13" \
  --repo-sweep --repo-root "$REPO_P3_NONE" --ledger "$LEDGER_P3_OK" --today "$TODAY"

# A clause-shaped token that does not parse (a hyphen where the em dash goes).
mk_p3_register "$CL_V" "$CL_V" "| **(g)** | (encryption-posture ledger: hcloud_volume.v - at rest: plaintext-exception) |"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-bad"; REPO_P3_BAD="$TMPDIR_TEST/p3-bad"
run_case_reports "P3 malformed clause -> FAIL, never skipped" 1 \
  "malformed encryption-posture clause in kb/register.md#Processing Activity 1" \
  --repo-sweep --repo-root "$REPO_P3_BAD" --ledger "$LEDGER_P3_OK" --today "$TODAY"

mk_p3_register "$CL_V" "$CL_V"
LEDGER_P3_NOSURF="$TMPDIR_TEST/p3-nosurf.json"
mk_p3_ledger "$LEDGER_P3_NOSURF" "$RECS_OK" '["kb/register.md"]'
run_case_reports "P3 a record on a file outside record_surfaces -> FAIL (the reverse check would not see it)" 1 \
  "hcloud_volume.v record kb/model.c4 names a file that is not in record_surfaces" \
  --repo-sweep --repo-root "$REPO_P3" --ledger "$LEDGER_P3_NOSURF" --today "$TODAY"
LEDGER_P3_MISSING="$TMPDIR_TEST/p3-missing.json"
mk_p3_ledger "$LEDGER_P3_MISSING" "$RECS_OK" '["kb/register.md", "kb/model.c4", "kb/gone.md"]'
run_case_reports "P3 a record surface that does not exist -> FAIL" 1 \
  "record_surfaces entry kb/gone.md is not a file" \
  --repo-sweep --repo-root "$REPO_P3" --ledger "$LEDGER_P3_MISSING" --today "$TODAY"
LEDGER_P3_AMBIG="$TMPDIR_TEST/p3-ambig.json"
mk_p3_ledger "$LEDGER_P3_AMBIG" '["kb/register.md#Processing Activity", "kb/model.c4"]'
run_case_reports "P3 a section selector matching two headings -> FAIL ambiguous" 1 \
  "matches 2 headings" \
  --repo-sweep --repo-root "$REPO_P3" --ledger "$LEDGER_P3_AMBIG" --today "$TODAY"

# Only H1/H2 headings split a section: an H3 is a sub-part of its processing
# activity, and a `#` line inside a fenced code block is code, not a heading.
mk_p3_register "$CL_V" "$CL_V" "$(printf '### Amendment note\n\n```bash\n# example query\n```')"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-sub"; REPO_P3_SUB="$TMPDIR_TEST/p3-sub"
run_case_reports "P3 must-PASS: an H3 and a fenced code comment do not split a section" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P3_SUB" --ledger "$LEDGER_P3_OK" --today "$TODAY"
# Only the one documented template, verbatim, is exempt.
mk_p3_register "$CL_V" "$CL_V" "| **(g)** | (encryption-posture ledger: <hcloud_volume.v> — at rest: luks) |"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-tpl"; REPO_P3_TPL="$TMPDIR_TEST/p3-tpl"
run_case_reports "P3 a clause starting with < that is not the exact template -> FAIL malformed" 1 \
  "malformed encryption-posture clause in kb/register.md#Processing Activity 1" \
  --repo-sweep --repo-root "$REPO_P3_TPL" --ledger "$LEDGER_P3_OK" --today "$TODAY"
mk_p3_register "$CL_V" "$CL_V"
run_mutation "MB-15" "MB-15" "$REPO_P3_MECH" "$LEDGER_P3_OK"
run_mutation "MB-26" "MB-26" "$REPO_P3_DUP" "$LEDGER_P3_OK"
run_mutation "MB-16" "MB-16" "$REPO_P3_GHOST" "$LEDGER_P3_OK"
run_mutation "MB-27" "MB-27" "$REPO_P3" "$LEDGER_P3_PA1"
run_mutation "MB-28" "MB-28" "$REPO_P3_BAD" "$LEDGER_P3_OK"

# --- Disclosure claim sentence (#8527): every denial alternative, the
# qualifier-in-a-later-sentence allowance, and single-token claims. ---
p1_luks_case() {
  local name="$1" rc="$2" needle="$3" line="$4"
  mk_luks_disclosure_case "$name" "$line"
  run_case_reports "P1-LUKS $name -> rc $rc" "$rc" "$needle" \
    --repo-sweep --repo-root "$P1_REPO" --ledger "$P1_LEDGER" --today "$TODAY"
}
DENY="denies encryption in its claim sentence"
NOCLAIM="does not claim encryption at rest in its claim sentence"
p1_luks_case never 1 "$DENY" '- **Encrypted storage:** the volume was never encrypted.'
p1_luks_case not-yet 1 "$DENY" '- **Encrypted storage:** the volume is not yet encrypted.'
p1_luks_case isnt 1 "$DENY" "- **Encrypted storage:** the volume isn't LUKS-encrypted."
p1_luks_case no-luks 1 "$DENY" '- **Encrypted storage:** the volume does not use LUKS.'
p1_luks_case cannot 1 "$DENY" '- **Encrypted storage:** the volume cannot be encrypted today.'
p1_luks_case planned 1 "$DENY" '- **Encrypted storage:** the volume will be LUKS-encrypted in a future release.'
p1_luks_case plaintext 1 "$DENY" '- **Encrypted storage:** LUKS is planned; today the data is stored in plaintext.'
p1_luks_case disabled 1 "$DENY" '- **Encrypted storage:** encryption at rest is disabled on this volume.'
p1_luks_case none 1 "$DENY" '- **Encrypted storage:** encryption at rest: none.'
p1_luks_case transit-only 1 "$NOCLAIM" '- **Encrypted storage:** data is encrypted in transit (TLS); at rest it is stored as-is.'
p1_luks_case wrapped 1 "$DENY" "$(printf -- '- **Encrypted storage:** the volume is not\n  encrypted at rest.')"
p1_luks_case later-qualifier 0 "0 failing checks" '- **Encrypted storage:** the volume is LUKS-encrypted. A credential that can fetch its key sits on the unencrypted system disk.'
p1_luks_case benign-negation 0 "0 failing checks" '- **Encrypted storage:** the volume is LUKS-encrypted and the key is not stored on the volume.'
p1_luks_case encrypted-only 0 "0 failing checks" '- **Encrypted storage:** data is encrypted at rest with AES-256.'
p1_luks_case luks-only 0 "0 failing checks" '- **Encrypted storage:** the volume is a LUKS2 container.'

# --- Guard 2: gate derivation, unresolvable variable, stale instance, gateless. ---
LEDGER_P2_WRONGGATE="$TMPDIR_TEST/p2-wronggate.json"
mk_mult_ledger "$LEDGER_P2_WRONGGATE" "$WS_OK" "" "$EXTRA_OK" "when var.some_unrelated_flag flips"
run_case_reports "P2-MULT reevaluate_when naming an unrelated gate -> FAIL" 1 \
  "exception.reevaluate_when must name one of local.extra_enabled" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_WRONGGATE" --today "$TODAY"
LEDGER_P2_PREFIXGATE="$TMPDIR_TEST/p2-prefixgate.json"
mk_mult_ledger "$LEDGER_P2_PREFIXGATE" "$WS_OK" "" "$EXTRA_OK" "when local.extra_enabled_v2 flips"
run_case_reports "P2-MULT reevaluate_when naming a prefix-colliding gate -> FAIL" 1 \
  "exception.reevaluate_when must name one of local.extra_enabled" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_PREFIXGATE" --today "$TODAY"
LEDGER_P2_STALE="$TMPDIR_TEST/p2-stale.json"
mk_mult_ledger "$LEDGER_P2_STALE" '{ "instances": ["web-1", "web-2", "web-3"] }' "" "$EXTRA_OK" "$EXTRA_REEVAL"
run_case_reports "P2-MULT a stale extra instance -> FAIL" 1 \
  "covers instances [web-1, web-2, web-3] but var.web_hosts declares [web-1, web-2]" \
  --repo-sweep --repo-root "$REPO_P2" --ledger "$LEDGER_P2_STALE" --today "$TODAY"

# mk_one_block <dir> <tf body> — one hcloud_volume "b" in apps/x/infra/b.tf,
# plus a variables.tf declaring web_hosts with two keys on ONE line.
mk_one_block() {
  local d="$1" body="$2"
  write_file "$d/apps/x/infra/variables.tf" <<'EOF'
variable "web_hosts" {
  default = { "web-1" = { location = "hel1" }, "web-2" = { location = "hel1" } }
}
EOF
  printf '%s\n' "$body" | write_file "$d/apps/x/infra/b.tf"
}
mk_b_ledger() {
  {
    echo '{ "schema_version": 1,'
    echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
    echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
    mk_exc_row "hcloud_volume.b" "$2" "$3"
    echo '  ], "connections": [] }'
  } | write_file "$1"
}
LEDGER_B_NONE="$TMPDIR_TEST/b-none.json"; mk_b_ledger "$LEDGER_B_NONE" "" "$REEVAL_DEF"
LEDGER_B_WEB="$TMPDIR_TEST/b-web.json"; mk_b_ledger "$LEDGER_B_WEB" '{ "instances": ["web-1", "web-2"] }' "$REEVAL_DEF"
LEDGER_B_EMPTY="$TMPDIR_TEST/b-empty.json"; mk_b_ledger "$LEDGER_B_EMPTY" '{ "instances": [] }' "$REEVAL_DEF"

REPO_B_SAMELINE="$TMPDIR_TEST/b-sameline"
mk_one_block "$REPO_B_SAMELINE" "$(printf 'resource "hcloud_volume" "b" {\n  for_each = var.web_hosts\n}')"
run_case_reports "P2-KEYS two map keys on one line are both read" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_B_SAMELINE" --ledger "$LEDGER_B_WEB" --today "$TODAY"
REPO_B_UNRES="$TMPDIR_TEST/b-unres"
mk_one_block "$REPO_B_UNRES" "$(printf 'resource "hcloud_volume" "b" {\n  for_each = var.no_such_map\n}')"
run_case_reports "P2-MULT a for_each over an undeclared variable fails closed" 1 \
  "exception.reevaluate_when must name one of var.no_such_map" \
  --repo-sweep --repo-root "$REPO_B_UNRES" --ledger "$LEDGER_B_EMPTY" --today "$TODAY"
REPO_B_OVR="$TMPDIR_TEST/b-override"
mk_one_block "$REPO_B_OVR" "$(printf 'resource "hcloud_volume" "b" {\n  for_each = var.web_hosts\n}')"
printf 'variable "web_hosts" {\n  default = { "web-1" = {} }\n}\n' | write_file "$REPO_B_OVR/apps/x/infra/variables_override.tf"
run_case_reports "P2-MULT an override.tf redeclaring the variable fails closed" 1 \
  "whose instances this check cannot verify" \
  --repo-sweep --repo-root "$REPO_B_OVR" --ledger "$LEDGER_B_WEB" --today "$TODAY"
REPO_B_GATELESS="$TMPDIR_TEST/b-gateless"
mk_one_block "$REPO_B_GATELESS" "$(printf 'resource "hcloud_volume" "b" {\n  count = 2\n}')"
run_case_reports "P2-MULT a gateless count -> FAIL naming no gate" 1 \
  "names no var./local./module. gate" \
  --repo-sweep --repo-root "$REPO_B_GATELESS" --ledger "$LEDGER_B_EMPTY" --today "$TODAY"
REPO_B_BRACE_CMT="$TMPDIR_TEST/b-brace-comment"
mk_one_block "$REPO_B_BRACE_CMT" "$(printf 'resource "hcloud_volume" "b" {\n  # see the {} map below }\n  for_each = var.web_hosts\n}')"
run_case_reports "P2-HCL a brace inside a comment does not truncate the block" 1 \
  "hcloud_volume.b is for_each = var.web_hosts but declares no multiplicity" \
  --repo-sweep --repo-root "$REPO_B_BRACE_CMT" --ledger "$LEDGER_B_NONE" --today "$TODAY"
REPO_B_BRACE_STR="$TMPDIR_TEST/b-brace-string"
mk_one_block "$REPO_B_BRACE_STR" "$(printf 'resource "hcloud_volume" "b" {\n  labels = { note = "}" }\n  for_each = var.web_hosts\n}')"
run_case_reports "P2-HCL a brace inside a string does not truncate the block" 1 \
  "hcloud_volume.b is for_each = var.web_hosts but declares no multiplicity" \
  --repo-sweep --repo-root "$REPO_B_BRACE_STR" --ledger "$LEDGER_B_NONE" --today "$TODAY"

# --- Scanner reach: unquoted and hyphenated labels, commented-out blocks,
# *.tf.json, a Terraform root outside apps/ and infra/. ---
LEDGER_EMPTY_HV="$TMPDIR_TEST/empty-hv.json"
{
  echo '{ "schema_version": 1,'
  echo '  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["plaintext-exception"] } },'
  echo '  "non_store_types": [], "non_iac_stores": [], "stores": [], "connections": [] }'
} | write_file "$LEDGER_EMPTY_HV"
scan_case() {
  local name="$1" rc="$2" needle="$3" rel="$4" body="$5"
  local d="$TMPDIR_TEST/scan-$name"
  printf '%s\n' "$body" | write_file "$d/$rel"
  run_case_reports "P2-SCAN $name -> rc $rc" "$rc" "$needle" \
    --repo-sweep --repo-root "$d" --ledger "$LEDGER_EMPTY_HV" --today "$TODAY"
}
scan_case unquoted 1 "unledgered store hcloud_volume.extra" apps/x/infra/a.tf 'resource hcloud_volume extra { size = 10 }'
scan_case hyphen 1 "unledgered store hcloud_volume.extra-2" apps/x/infra/a.tf 'resource "hcloud_volume" "extra-2" { size = 10 }'
scan_case commented 0 "0 failing checks" apps/x/infra/a.tf '# resource "hcloud_volume" "old" { size = 10 }'
scan_case tf-json 1 "unledgered store hcloud_volume.fromjson" apps/x/infra/a.tf.json '{"resource":{"hcloud_volume":{"fromjson":{"size":10}}}}'
scan_case other-root 1 "unledgered store hcloud_volume.elsewhere" terraform/y/main.tf 'resource "hcloud_volume" "elsewhere" { size = 10 }'

# --- Guard 3: a sub-heading and a fenced `#` line before the clause do not
# split the section; clause-shaped variants are malformed, never skipped. ---
mk_p3_register "(no clause in this cell)" "$CL_V" "$(printf '### Amendment note\n\n```bash\n# example query\n```\n\n| **(f)** | Stored. %s |' "$CL_V")"
cp -r "$REPO_P3" "$TMPDIR_TEST/p3-subafter"; REPO_P3_SUBAFTER="$TMPDIR_TEST/p3-subafter"
run_case_reports "P3 must-PASS: the clause AFTER an H3 and a fenced # line stays in its section" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REPO_P3_SUBAFTER" --ledger "$LEDGER_P3_OK" --today "$TODAY"
p3_loose_case() {
  local name="$1" clause="$2"
  mk_p3_register "$CL_V" "$CL_V" "| **(g)** | $clause |"
  cp -r "$REPO_P3" "$TMPDIR_TEST/p3-loose-$name"
  run_case_reports "P3 clause variant ($name) is malformed, never skipped" 1 \
    "malformed encryption-posture clause in kb/register.md#Processing Activity 1" \
    --repo-sweep --repo-root "$TMPDIR_TEST/p3-loose-$name" --ledger "$LEDGER_P3_OK" --today "$TODAY"
}
p3_loose_case double-space '(encryption-posture  ledger: hcloud_volume.v — at rest: luks)'
p3_loose_case capital '(Encryption-posture ledger: hcloud_volume.v — at rest: luks)'
p3_loose_case wrapped "$(printf '(encryption-posture\nledger: hcloud_volume.v — at rest: luks)')"
mk_p3_register "$CL_V" "$CL_V"
LEDGER_P3_ESC="$TMPDIR_TEST/p3-esc.json"
mk_p3_ledger "$LEDGER_P3_ESC" "$RECS_OK" '["kb/register.md", "kb/model.c4", "../outside.md"]'
run_case_reports "P3 a record surface outside the repository -> FAIL" 1 \
  "record_surfaces entry ../outside.md is not a file inside the repository" \
  --repo-sweep --repo-root "$REPO_P3" --ledger "$LEDGER_P3_ESC" --today "$TODAY"

# --- Schema: an unknown key anywhere is rejected; every disclosure anchor
# resolves, whatever the mechanism (MB-31). ---
REPO_CONN="$TMPDIR_TEST/conn"
printf '# Doc\n\nAll traffic is TLS-verified.\n' | write_file "$REPO_CONN/docs/p.md"
mk_conn_ledger() {
  {
    echo '{ "schema_version": 1, "store_classes": {}, "non_store_types": [], "non_iac_stores": [], "stores": [],'
    echo '  "connections": [ { "connection": "a -> b", "enforced_at": "fixture",'
    echo "    \"in_transit\": { \"tls\": \"1.3\", \"cert_verification\": \"on\", \"does_not_defend\": \"a compromised endpoint\", $2 } } ] }"
  } | write_file "$1"
}
LEDGER_CONN_TYPO="$TMPDIR_TEST/conn-typo.json"; mk_conn_ledger "$LEDGER_CONN_TYPO" '"disclosed_ass": "docs/p.md:TLS-verified"'
run_case_reports "P2-SCHEMA a misspelled in_transit key is rejected" 1 \
  "in_transit has unexpected key(s) ['disclosed_ass']" \
  --repo-sweep --repo-root "$REPO_CONN" --ledger "$LEDGER_CONN_TYPO" --today "$TODAY"
LEDGER_CONN_GONE="$TMPDIR_TEST/conn-gone.json"; mk_conn_ledger "$LEDGER_CONN_GONE" '"disclosed_as": "docs/p.md:No Such Anchor Xyzzy"'
run_case_reports "P2-DISC a cert-on connection's disclosure anchor must resolve" 1 \
  "a -> b disclosed_as docs/p.md:No Such Anchor Xyzzy does not resolve" \
  --repo-sweep --repo-root "$REPO_CONN" --ledger "$LEDGER_CONN_GONE" --today "$TODAY"
LEDGER_PROV_GONE="$TMPDIR_TEST/prov-gone.json"
sed 's#"disclosed_as": "not-publicly-claimed"#"disclosed_as": "docs/gone.md:Nothing"#' "$LEDGER_P1_OK" > "$TMPDIR_TEST/prov-gone.tmp"
write_file "$LEDGER_PROV_GONE" < "$TMPDIR_TEST/prov-gone.tmp"
run_case_reports "P2-DISC a provider-managed row's disclosure anchor must resolve" 1 \
  "supabase.prd disclosed_as docs/gone.md:Nothing does not resolve" \
  --repo-sweep --repo-root "$REPO_P1" --ledger "$LEDGER_PROV_GONE" --today "$TODAY"

# A two-gate for_each is the shape the multiplicity check cannot resolve.
REPO_P2_ML2="$TMPDIR_TEST/p2-ml2"
cp -r "$REPO_P2_ML" "$REPO_P2_ML2"
write_file "$REPO_P2_ML2/apps/web-platform/infra/ml.tf" <<'EOF'
resource "hcloud_volume" "ml" {
  for_each = {
    for k, v in var.web_hosts : k => v if local.on
  }
  name = "soleur-${each.key}"
}
EOF
run_case_reports "P2-MULT a two-gate for_each fails closed" 1 \
  "which this check cannot resolve" \
  --repo-sweep --repo-root "$REPO_P2_ML2" --ledger "$LEDGER_P2_ML_BAD" --today "$TODAY"

# Provider backups on a host are a derivative store no row names (MB-33).
REPO_BACKUPS="$TMPDIR_TEST/backups"
printf 'resource "hcloud_server" "h" {\n  backups = true\n}\n' | write_file "$REPO_BACKUPS/apps/x/infra/h.tf"
LEDGER_BACKUPS="$TMPDIR_TEST/backups.json"
{
  echo '{ "schema_version": 1,'
  echo '  "store_classes": { "hcloud_server": { "kind": "host-root-disk", "mechanisms": ["plaintext-exception"] } },'
  echo '  "non_store_types": [], "non_iac_stores": [], "stores": ['
  mk_exc_row "hcloud_server.h" "" "$REEVAL_DEF" | sed 's/"kind": "guest-luks-volume"/"kind": "host-root-disk"/'
  echo '  ], "connections": [] }'
} | write_file "$LEDGER_BACKUPS"
run_case_reports "P2-BACKUPS an hcloud_server with backups = true -> FAIL" 1 \
  "hcloud_server.h enables provider backups" \
  --repo-sweep --repo-root "$REPO_BACKUPS" --ledger "$LEDGER_BACKUPS" --today "$TODAY"
run_mutation "MB-33" "MB-33" "$REPO_BACKUPS" "$LEDGER_BACKUPS"
run_mutation "MB-20/planned" "MB-20" "$TMPDIR_TEST/p1-luks-planned" "$TMPDIR_TEST/p1-luks-planned.json"
run_mutation "MB-31/connection" "MB-31" "$REPO_CONN" "$LEDGER_CONN_GONE"
run_mutation "MB-31/provider" "MB-31" "$REPO_P1" "$LEDGER_PROV_GONE"
run_mutation "MB-32" "MB-32" "$REPO_P3_SUBAFTER" "$LEDGER_P3_OK" 1 "" 0
run_mutation "MB-24/two-gate" "MB-24" "$REPO_P2_ML2" "$LEDGER_P2_ML_BAD"

# ===========================================================================
# Live-coverage floor (#6902 / ADR-141): an OPTIONAL top-level
# `live_coverage_floor` integer. When >= 1, the ledger must retain at least
# that many stores whose at_rest.live_verification == "available" — the one
# coverage regression (zeroing out ALL live-measurable at-rest coverage) worth
# blocking at PR time. It is a COUNT floor keyed on the ledger's own declared
# value, NOT an identity pin, and it NO-OPs when the field is absent/0 — so
# every fixture above (which omits the field) is unaffected. Hermetic: reads
# only the committed ledger. CTO ruling (Option D) recorded in ADR-141.
# ---------------------------------------------------------------------------
REPO_LCF="$TMPDIR_TEST/lcf"  # deliberately empty: provider-managed store, no apps/ tree
mkdir -p "$REPO_LCF"

# AC3 pass-case: live_coverage_floor:1 AND one store with live_verification
# "available" -> floor satisfied -> PASS. (Mirrors the MB-12 supabase shape,
# which passes every other check; only live_verification differs.)
LEDGER_LCF_OK="$TMPDIR_TEST/lcf-ok-ledger.json"
write_file "$LEDGER_LCF_OK" <<'EOF'
{
  "schema_version": 1,
  "live_coverage_floor": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": ["supabase.prd"],
  "stores": [
    {
      "store": "supabase.prd",
      "kind": "provider-db",
      "at_rest": {
        "mechanism": "provider-managed:Supabase-SOC2-Type-II",
        "evidence": "Supabase trust center compliance page",
        "attestation_url": "https://supabase.com/security",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked service-role key or an RLS bypass",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "available"
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "AC3 live-coverage floor: floor=1 with >=1 available -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_OK" --today "$TODAY"

# AC2 fail-case: identical ledger EXCEPT the single available row is flipped to
# a valid "unavailable:<reason>" form -> 0 available < floor 1 -> FAIL. Because
# live_verification feeds no other check (only the format validator), this is a
# SINGLE-CAUSE failure — the exact-needle contract (R10) holds.
LEDGER_LCF_BAD="$TMPDIR_TEST/lcf-bad-ledger.json"
write_file "$LEDGER_LCF_BAD" <<'EOF'
{
  "schema_version": 1,
  "live_coverage_floor": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": ["supabase.prd"],
  "stores": [
    {
      "store": "supabase.prd",
      "kind": "provider-db",
      "at_rest": {
        "mechanism": "provider-managed:Supabase-SOC2-Type-II",
        "evidence": "Supabase trust center compliance page",
        "attestation_url": "https://supabase.com/security",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked service-role key or an RLS bypass",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:coverage-regression-fixture"
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "AC2 live-coverage floor: floor=1 with 0 available -> FAIL" 1 \
  "live-coverage floor" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_BAD" --today "$TODAY"

# MB-13 non-vacuity: deleting the floor's fail branch flips the AC2-bad ledger
# FAIL->PASS, proving the branch is load-bearing (not a vacuous assertion).
run_mutation "MB-13" "MB-13" "$REPO_LCF" "$LEDGER_LCF_BAD"

# Floor-absent no-op: a ledger that OMITS live_coverage_floor entirely with 0
# available rows still PASSES (the field defaults to 0 -> floor inactive). This
# is why the 7+ existing all-unavailable PASS fixtures are unaffected.
LEDGER_LCF_ABSENT="$TMPDIR_TEST/lcf-absent-ledger.json"
write_file "$LEDGER_LCF_ABSENT" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": ["supabase.prd"],
  "stores": [
    {
      "store": "supabase.prd",
      "kind": "provider-db",
      "at_rest": {
        "mechanism": "provider-managed:Supabase-SOC2-Type-II",
        "evidence": "Supabase trust center compliance page",
        "attestation_url": "https://supabase.com/security",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked service-role key or an RLS bypass",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "live-coverage floor absent (field omitted) + 0 available -> PASS (no-op)" 0 \
  "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_ABSENT" --today "$TODAY"

# --- Boundary coverage: prove the guard is a FLOOR (`available < floor`), not
# an equality pin (`!=`), and that it reads the DECLARED value (not a hardcoded
# 1). Without these, `< floor` -> `!= floor` and `floor -> literal 1` mutants
# survive (the fixtures above only ever evaluate at (floor,available) in
# {(1,1),(1,0),(0,0)}, where `<` and `!=` are indistinguishable). Derived DRY
# from LEDGER_LCF_OK so the store shape stays identical.

# Over-coverage: floor=1 with TWO available stores -> PASS (kills `!= floor`,
# which would false-FAIL legitimate over-coverage). The 2nd store also lifts the
# positive-work floor to 2, so it needs a 2nd non_iac_stores catalog entry.
LEDGER_LCF_OVER="$TMPDIR_TEST/lcf-over-ledger.json"
python3 - "$LEDGER_LCF_OK" "$LEDGER_LCF_OVER" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["live_coverage_floor"] = 1
s2 = json.loads(json.dumps(d["stores"][0]))
s2["store"] = "supabase.dr"
d["non_iac_stores"] = ["supabase.prd", "supabase.dr"]
d["stores"] = [d["stores"][0], s2]  # both live_verification: available
json.dump(d, open(sys.argv[2], "w"))
PY
run_case_reports "live-coverage floor: floor=1 with 2 available (over-coverage) -> PASS" 0 \
  "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_OVER" --today "$TODAY"

# Magnitude: floor=2 with only 1 available -> FAIL (proves the guard reads the
# declared value, not a hardcoded 1).
LEDGER_LCF_FLOOR2="$TMPDIR_TEST/lcf-floor2-ledger.json"
python3 - "$LEDGER_LCF_OK" "$LEDGER_LCF_FLOOR2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["live_coverage_floor"] = 2   # 1 available store < 2
json.dump(d, open(sys.argv[2], "w"))
PY
run_case_reports "live-coverage floor: floor=2 with 1 available -> FAIL (magnitude)" 1 \
  "live-coverage floor" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_FLOOR2" --today "$TODAY"

# --- Validator coverage for the OPTIONAL_TOP type/range gate. Without these,
# deleting `isinstance(lcf, bool)` (a JSON `true` read as floor 1) or the whole
# non-negative-integer branch (a negative floor accepted) both survive.

# bool `true` must be rejected (bool is an int subclass; the explicit guard
# stops it being read as 1).
LEDGER_LCF_BOOL="$TMPDIR_TEST/lcf-bool-ledger.json"
python3 - "$LEDGER_LCF_OK" "$LEDGER_LCF_BOOL" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["live_coverage_floor"] = True
json.dump(d, open(sys.argv[2], "w"))
PY
run_case_reports "live-coverage floor: bool true -> FAIL (non-negative integer)" 1 \
  "non-negative integer" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_BOOL" --today "$TODAY"

# negative must be rejected.
LEDGER_LCF_NEG="$TMPDIR_TEST/lcf-neg-ledger.json"
python3 - "$LEDGER_LCF_OK" "$LEDGER_LCF_NEG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["live_coverage_floor"] = -1
json.dump(d, open(sys.argv[2], "w"))
PY
run_case_reports "live-coverage floor: -1 -> FAIL (non-negative integer)" 1 \
  "non-negative integer" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_NEG" --today "$TODAY"

# floor=0 present-and-valid -> PASS (OPTIONAL_TOP allowance is reachable; 0 is
# inactive so 0 available is fine).
LEDGER_LCF_ZERO="$TMPDIR_TEST/lcf-zero-ledger.json"
python3 - "$LEDGER_LCF_ABSENT" "$LEDGER_LCF_ZERO" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["live_coverage_floor"] = 0   # explicit 0, 0 available -> inactive -> PASS
json.dump(d, open(sys.argv[2], "w"))
PY
run_case_reports "live-coverage floor: explicit 0 + 0 available -> PASS (positive control)" 0 \
  "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_LCF" --ledger "$LEDGER_LCF_ZERO" --today "$TODAY"

# ===========================================================================
# Mode coverage: --check-templates, --json, graceful ledger-absent degrade,
# explicit --ledger error, hermeticity.
# ===========================================================================

# --check-templates SKIPs gracefully (exit 0) when the templates file is
# entirely absent.
REPO_NOTPL="$TMPDIR_TEST/notpl"
mkdir -p "$REPO_NOTPL"
run_case_reports "--check-templates SKIPs when the templates file is absent" 0 "not yet present" \
  --check-templates --repo-root "$REPO_NOTPL"

# --check-templates SKIPs gracefully when the file exists but the heading
# hasn't landed yet (Phase 5).
REPO_NOTPL2="$TMPDIR_TEST/notpl2"
write_file "$REPO_NOTPL2/plugins/soleur/skills/plan/references/plan-issue-templates.md" <<'EOF'
# Plan Issue Templates

## Observability

no Encryption Posture section here yet
EOF
run_case_reports "--check-templates SKIPs when the heading is absent" 0 "not yet present" \
  --check-templates --repo-root "$REPO_NOTPL2"

# --json emits the schema-validated ledger.
run_case_reports "--json emits parsed ledger JSON" 0 '"schema_version": 1' \
  --json --repo-root "$REPO_TS1" --ledger "$LEDGER_TS1"

# --json FAILs on a schema-invalid ledger.
LEDGER_BADSCHEMA="$TMPDIR_TEST/badschema-ledger.json"
write_file "$LEDGER_BADSCHEMA" <<'EOF'
{ "schema_version": 1, "store_classes": {}, "stores": [], "connections": [] }
EOF
run_case_reports "--json FAILs on schema-invalid ledger" 1 "ledger schema" \
  --json --repo-root "$REPO_TS1" --ledger "$LEDGER_BADSCHEMA"

# A MISSING default ledger FAILs (#6907). It used to degrade to "not yet
# seeded -> PASS" while the real ledger was a separate deliverable; once the
# sweep blocks merge through `test`, that degrade made `git rm` of the ledger a
# one-line bypass of the gate.
REPO_NOLEDGER="$TMPDIR_TEST/noledger"
mkdir -p "$REPO_NOLEDGER/scripts"
run_case_reports "repo-sweep FAILs when the default ledger is missing" 1 "ledger missing" \
  --repo-sweep --repo-root "$REPO_NOLEDGER"

# An EXPLICIT --ledger that doesn't exist is a hard error (exit 2) — distinct
# from the graceful default-path skip above.
run_case "explicit --ledger missing file -> exit 2" 2 \
  --repo-sweep --repo-root "$REPO_NOLEDGER" --ledger "$TMPDIR_TEST/does-not-exist.json"

# --report prints the parity table (in addition to the summary).
run_case_reports "--report prints the parity table" 0 "encryption-posture parity" \
  --repo-sweep --report --repo-root "$REPO_TS1" --ledger "$LEDGER_TS1" --today "$TODAY"

# Live calibration: if the real plan-issue-templates.md already carries the
# heading (Phase 5 may have landed independently of this PR), --check-templates
# must validate it cleanly — a real-content smoke test alongside the synthetic
# SKIP-path fixtures above.
REPO_TRUE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
run_case "--check-templates against the real repo tree does not error" 0 \
  --check-templates --repo-root "$REPO_TRUE_ROOT"

# AC-1a against the COMMITTED ledger: deleting any catalogued row must fail
# the sweep and name the id. Before #8532 PR-1, deleting supabase.prd here
# reported "19 -> 18 stores ... 0 failing checks -> PASS".
REAL_LEDGER="$REPO_TRUE_ROOT/scripts/encryption-posture-ledger.json"
REAL_IDS="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["non_iac_stores"]))' "$REAL_LEDGER")"
REAL_N=0
while IFS= read -r rid; do
  [[ -n "$rid" ]] || continue
  REAL_N=$((REAL_N + 1))
  rl="$TMPDIR_TEST/real-minus-${REAL_N}.json"
  python3 -c 'import json,sys; l=json.load(open(sys.argv[1])); l["stores"]=[s for s in l["stores"] if s["store"]!=sys.argv[2]]; json.dump(l,open(sys.argv[3],"w"))' \
    "$REAL_LEDGER" "$rid" "$rl"
  run_case_reports "AC-1a committed ledger minus catalogued row $rid -> FAIL naming it" 1 \
    "non_iac_stores entry $rid names no stores[] row" \
    --repo-sweep --repo-root "$REPO_TRUE_ROOT" --ledger "$rl"
done <<<"$REAL_IDS"
# AC-2b/2c, Guard 2 matrix #4 and AC-3a against COPIES of the real tree. Every
# subject and needle below is DERIVED from the committed ledger and the parsed
# variables.tf default, so an unrelated edit (a server_type change, a new
# record surface, a renamed row) cannot red this suite while the sweep is green.
# The copy is the ledger's own inputs: the *.tf/infra scope, every
# record_surfaces file and every disclosed_as document.
REAL_TODAY="2026-09-23"
# mk_real_copy <name> — the copy lands at $TMPDIR_TEST/<name>.
mk_real_copy() {
  local dst="$TMPDIR_TEST/$1"
  mkdir -p "$dst"
  python3 - "$REAL_LEDGER" > "$TMPDIR_TEST/real-extra-paths" <<'PYEOF2'
import json, sys
l = json.load(open(sys.argv[1]))
paths = set(l.get("record_surfaces", []))
for s in l["stores"]:
    d = s["at_rest"].get("disclosed_as", "")
    if ":" in d:
        paths.add(d.split(":", 1)[0])
for c in l["connections"]:
    d = c["in_transit"].get("disclosed_as", "")
    if ":" in d:
        paths.add(d.split(":", 1)[0])
print("\n".join(sorted(paths)))
PYEOF2
  local extra=()
  mapfile -t extra < "$TMPDIR_TEST/real-extra-paths"
  ( cd "$REPO_TRUE_ROOT" && git_clean ls-files -z -- ':(glob)**/*.tf' ':(glob)**/*.tf.json' \
        ':(glob)apps/*/infra/**' "${extra[@]}" \
      | xargs -0 cp --parents -t "$dst/" )
}
REAL_COPY="$TMPDIR_TEST/real-copy"
mk_real_copy real-copy
run_case_reports "AC-2c baseline: the committed ledger PASSES on a faithful copy of the tree" 0 "0 failing checks" \
  --repo-sweep --repo-root "$REAL_COPY" --ledger "$REAL_LEDGER" --today "$REAL_TODAY"

# Add ONE key to the var.web_hosts default without touching the ledger. The
# expected message is built from the parsed default plus that key, and from
# each for_each row's declared instances.
python3 - "$SUT" "$REAL_COPY/apps/web-platform/infra/variables.tf" "$REAL_LEDGER" \
  > "$TMPDIR_TEST/real-webhost-needles" <<'PYEOF2'
import importlib.util, json, re, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("lep", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
tf = Path(sys.argv[2]); keys = m.resolve_var_map_keys(tf, "web_hosts", {}, sorted(tf.parent.glob("*.tf")))
assert keys, "var.web_hosts default did not resolve"
new = "web-zz9"
assert new not in keys
s = tf.read_text()
v = re.search(r'variable\s+"web_hosts"\s*\{', s)
d = re.compile(r"^(\s*)default\s*=\s*\{\s*$", re.M).search(s, v.end())
s = s[: d.end()] + f'\n    "{new}" = {{ location = "hel1", private_ip = "10.0.1.99" }}' + s[d.end():]
tf.write_text(s)
want = ", ".join(sorted(keys + [new]))
l = json.load(open(sys.argv[3]))
rows = [r for r in l["stores"] if sorted(r.get("multiplicity", {}).get("instances", [])) == sorted(keys)]
assert len(rows) >= 2, "expected the web_hosts for_each rows to declare the parsed keys"
for r in rows:
    have = ", ".join(sorted(r["multiplicity"]["instances"]))
    print(f"{r['store']} covers instances [{have}] but var.web_hosts declares [{want}]")
PYEOF2
while IFS= read -r needle; do
  run_case_reports "AC-2b/2c a key added to var.web_hosts without a ledger edit -> FAIL: ${needle%% covers*}" 1 \
    "$needle" \
    --repo-sweep --repo-root "$REAL_COPY" --ledger "$REAL_LEDGER" --today "$REAL_TODAY"
done < "$TMPDIR_TEST/real-webhost-needles"
printf '\nresource "hcloud_server" "zz_unledgered" {\n  name = "soleur-zz"\n}\n' \
  > "$REAL_COPY/apps/web-platform/infra/zz-unledgered.tf"
run_case_reports "Guard 2 #4: a new hcloud_server block with no row -> FAIL unledgered" 1 \
  "unledgered store hcloud_server.zz_unledgered" \
  --repo-sweep --repo-root "$REAL_COPY" --ledger "$REAL_LEDGER" --today "$REAL_TODAY"

# AC-3a: a store renamed in the ledger alone leaves its register clauses naming
# nothing (Guard 3 #1); a mechanism changed in the ledger alone contradicts the
# record (Guard 3 #3). Subjects are the first rows carrying a register record.
REAL_COPY_B="$TMPDIR_TEST/real-copy-b"
mk_real_copy real-copy-b
python3 - "$REAL_LEDGER" "$TMPDIR_TEST/real-rename.json" "$TMPDIR_TEST/real-flip.json" \
  > "$TMPDIR_TEST/real-3a-needles" <<'PYEOF2'
import json, sys
src = sys.argv[1]
reg = "knowledge-base/legal/article-30-register.md#"
l = json.load(open(src))
with_reg = [s for s in l["stores"] if any(r.startswith(reg) for r in s.get("records", []))]
assert with_reg, "no row carries a register record"
victim = with_reg[0]["store"]
for s in l["stores"]:
    if s["store"] == victim:
        s["store"] = victim + "_renamed"
json.dump(l, open(sys.argv[2], "w"))
l = json.load(open(src))
flip = next(s for s in l["stores"] if s in [r for r in l["stores"]
            if any(x.startswith(reg) for x in r.get("records", []))]
            and s["at_rest"]["mechanism"].startswith("provider-managed:"))
old = flip["at_rest"]["mechanism"]; new = old + "-flipped"
flip["at_rest"]["mechanism"] = new
rec = next(r for r in flip["records"] if r.startswith(reg))
json.dump(l, open(sys.argv[3], "w"))
print(f"carries a clause for {victim}, which names no stores[] row")
print(f"{flip['store']} record {rec} states at rest: {old} but the row's mechanism is {new}")
PYEOF2
{ IFS= read -r NEEDLE_RENAME; IFS= read -r NEEDLE_FLIP; } < "$TMPDIR_TEST/real-3a-needles"
run_case_reports "AC-3a a store renamed in the ledger only -> its register clauses FAIL" 1 \
  "$NEEDLE_RENAME" \
  --repo-sweep --repo-root "$REAL_COPY_B" --ledger "$TMPDIR_TEST/real-rename.json" --today "$REAL_TODAY"
run_case_reports "AC-3a a mechanism changed in the ledger only -> its record FAILS" 1 \
  "$NEEDLE_FLIP" \
  --repo-sweep --repo-root "$REAL_COPY_B" --ledger "$TMPDIR_TEST/real-flip.json" --today "$REAL_TODAY"

# Guard 3 matrix #4. Dropping a surface from record_surfaces is caught by the
# forward check for every row that still records it; what nothing else catches
# is a surface REPLACED, or dropped together with every record pointing at it.
# So pin the canonical pair by path, reported through printf + exit and never
# through the verdict helper it protects (ADR-193).
for canon in knowledge-base/legal/article-30-register.md knowledge-base/engineering/architecture/diagrams/model.c4; do
  if ! python3 -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("record_surfaces", []) else 1)' \
      "$REAL_LEDGER" "$canon"; then
    printf 'GUARD FAIL: the committed ledger record_surfaces no longer lists %s\n' "$canon" >&2
    exit 2
  fi
done
REAL_CATALOG_N="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["non_iac_stores"]))' "$REAL_LEDGER")"
if [[ "$REAL_N" -lt 1 || "$REAL_N" -ne "$REAL_CATALOG_N" ]]; then
  printf 'GUARD FAIL: AC-1a loop covered %s catalogued ids, the ledger catalogues %s\n' "$REAL_N" "$REAL_CATALOG_N" >&2
  exit 2
fi

# Hermeticity (h): the SUT must never reach the network. Checked on the AST, so
# a call split across lines or a docstring mentioning `curl` changes nothing:
# no network-library import, and no subprocess call whose argv starts with a
# network client.
if python3 - "$SUT" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
bad = []
for node in ast.walk(tree):
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        names = [a.name for a in node.names] if isinstance(node, ast.Import) else [node.module or ""]
        bad += [n for n in names if n.split(".")[0] in {"urllib", "requests", "http", "socket", "httpx", "aiohttp"}]
    if isinstance(node, ast.Call) and node.args and isinstance(node.args[0], (ast.List, ast.Tuple)):
        first = node.args[0].elts[0] if node.args[0].elts else None
        if isinstance(first, ast.Constant) and first.value in {"gh", "curl", "wget", "nc", "ssh"}:
            bad.append(f"call to {first.value} at line {node.lineno}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PYEOF
then pass "H1 hermeticity: SUT contains no network/gh/curl calls (AST)"
else fail "H1 hermeticity: SUT contains no network/gh/curl calls (AST)" "found a banned import or call in $SUT"
fi

# Minimum-cardinality guard (an empty/short run must not GREEN). The floor is
# the fixed case count plus the cases DERIVED from the committed ledger (one per
# catalogued id, one per web_hosts row), so retiring a store changes both sides
# together. Reported via printf + exit, never through the verdict helpers.
MIN_STATIC=173
WEBHOST_N="$(grep -c . "$TMPDIR_TEST/real-webhost-needles" || true)"
MIN_CASES=$((MIN_STATIC + REAL_N + WEBHOST_N))
echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]]
