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

# The body below is a COPY of the canonical definition in plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh asserts it is byte-equal). Every writing window below that
# edits a fixture copy calls it first, so a bad <root> refuses before any write retargets it.
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

run_mutation() {
  local mb="$1" marker="$2" repo="$3" ledger="$4"
  local base_rc=0
  python3 "$SUT" --repo-sweep --repo-root "$repo" --ledger "$ledger" --today "$TODAY" >/dev/null 2>&1 || base_rc=$?
  if [[ "$base_rc" != "1" ]]; then
    fail "$mb baseline must FAIL before mutation" "baseline exit=$base_rc (expected 1) for $ledger"
    return
  fi
  local mb_safe="${mb//\//_}"
  local mutated="$TMPDIR_TEST/mutated_${mb_safe}.py"
  sed "/# MUTATION-TARGET: ${marker} start/,/# MUTATION-TARGET: ${marker} end/d" "$SUT" > "$mutated"
  if ! python3 -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" "$mutated" >/dev/null 2>&1; then
    fail "$mb mutated script must still compile" "syntax error after deleting $marker"
    return
  fi
  local mut_rc=0
  python3 "$mutated" --repo-sweep --repo-root "$repo" --ledger "$ledger" --today "$TODAY" >/dev/null 2>&1 || mut_rc=$?
  if [[ "$mut_rc" == "0" ]]; then
    pass "$mb ($marker): deleting the branch flips FAIL->PASS (branch is load-bearing)"
  else
    fail "$mb ($marker): deleting the branch flips FAIL->PASS (branch is load-bearing)" \
      "mutated exit=$mut_rc (expected 0) — branch may be VACUOUS, or another independent check still fails"
  fi
}

# --- MB-1: delete the unledgered-store branch -> a dedicated TS-1-derived
# fixture (a second, ledgered-under-the-wrong-address resource) must regress.
# The floor check is deliberately UNAFFECTED (same total counts) so this
# isolates the per-address branch specifically. ---
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
    },
    {
      "store": "hcloud_volume.nonexistent_luks",
      "kind": "guest-luks-volume",
      "at_rest": {
        "mechanism": "plaintext-exception",
        "evidence": "decoy row for the MB-1 fixture -- not a real *.tf resource",
        "defends_against": "n/a -- fixture decoy row exercising the count-only floor path",
        "does_not_defend": "a leaked service-role credential or a compromised host with the volume already unlocked",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:fixture decoy row",
        "exception": {
          "justification": "fixture decoy row exercising the count-only positive-work floor",
          "tracking_issue": "#1",
          "reevaluate_when": "never -- fixture decoy row",
          "expires_on": "2099-01-01"
        }
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "MB-1 fixture baseline: orphan_luks unledgered -> FAIL" 1 "unledgered store hcloud_volume.orphan_luks" \
  --repo-sweep --repo-root "$REPO_MB1" --ledger "$LEDGER_MB1" --today "$TODAY"
run_mutation "MB-1" "MB-1" "$REPO_MB1" "$LEDGER_MB1"

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

# Hermeticity (h): the SUT must never shell out to gh/curl or hit the network.
if grep -qE 'gh api|subprocess\.run\(\s*\[.?(gh|curl)|urllib\.request|requests\.(get|post)|http\.client|socket\.' "$SUT"; then
  fail "H1 hermeticity: SUT contains no network/gh/curl calls" "found a banned token in $SUT"
else
  pass "H1 hermeticity: SUT contains no network/gh/curl calls"
fi

# ===========================================================================
# #9372 / #9572 — the web-class (indexed) luks row. A `for_each` volume with its
# attachment indexed by [each.key], a key chain through the fresh-boot token, a pinned
# apparatus file. Every case below is a synthesized
# fixture (cq-test-fixtures-synthesized-only); each variant changes exactly ONE thing
# from the canonical web-class repo so a FAIL is attributable to that one guard.
# ===========================================================================

# mk_webclass_repo <dir> — web-1 (singleton luks row's apparatus) + web-2 (indexed).
mk_webclass_repo() {
  local d="$1" i="$1/apps/web-platform/infra"
  write_file "$i/variables.tf" <<'EOF'
variable "web_hosts" {
  description = "fixture host map"
  # A long comment block before the default, with a } and a # and a decoy web-9 = { x }
  type = map(object({ location = string, private_ip = string }))
  default = {
    "web-1" = { location = "hel1", private_ip = "10.0.1.10" }
    "web-2" = { location = "hel1", private_ip = "10.0.1.11" }
  }
}
EOF
  write_file "$i/server.tf" <<'EOF'
locals {
  plaintext_workspaces_hosts = { for k, v in var.web_hosts : k => v if k != "web-1" }
  host_scripts = [
    "soleur-host.sh",
    "workspaces-luks-provision.sh",
  ]
}

resource "hcloud_server" "web" {
  for_each = var.web_hosts
  name     = "web-${each.key}"
  user_data = templatefile("${path.module}/cloud-init.yml", {
    workspaces_volume_id             = contains(keys(local.plaintext_workspaces_hosts), each.key) ? hcloud_volume.workspaces[each.key].id : "retired-6604"
    workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot_web.key
  })
}

resource "hcloud_volume" "workspaces" {
  for_each = local.plaintext_workspaces_hosts
  name     = "soleur-data-${each.key}"
  # for_each key churn must not drop a volume
  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume_attachment" "workspaces" {
  for_each  = local.plaintext_workspaces_hosts
  volume_id = hcloud_volume.workspaces[each.key].id
  server_id = hcloud_server.web[each.key].id
}
EOF
  write_file "$i/workspaces-luks-fresh-boot.tf" <<'EOF'
resource "doppler_config" "workspaces_luks_web" {
  project     = "soleur"
  environment = "prd"
  name        = "prd_workspaces_luks_web"
}

resource "doppler_service_token" "workspaces_luks_fresh_boot_web" {
  project = "soleur"
  config  = doppler_config.workspaces_luks_web.name
  name    = "fresh-boot-web"
  access  = "read"
}
EOF
  write_file "$i/workspaces-luks-header-web.tf" <<'EOF'
resource "random_password" "workspaces_luks_web" {
  length  = 40
  special = false
}

resource "doppler_secret" "workspaces_luks_web_key" {
  project    = "soleur"
  config     = doppler_config.workspaces_luks_web.name
  name       = "WORKSPACES_LUKS_KEY"
  value      = random_password.workspaces_luks_web.result
  visibility = "masked"
}
EOF
  write_file "$i/workspaces-luks.tf" <<'EOF'
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
  server_id = hcloud_server.web["web-1"].id
}
EOF
  write_file "$i/workspaces-cutover.sh" <<'EOF'
#!/usr/bin/env bash
MAPPER_NAME="${WORKSPACES_MAPPER_NAME:-workspaces}"
read_key() { doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks; }
KEY="$(read_key)"
printf '%s' "$KEY" | cryptsetup luksFormat --type luks2 --key-file - "$FRESH_DEV"
printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$FRESH_DEV" "$MAPPER_NAME"
EOF
  write_file "$i/soleur-host-bootstrap.sh" <<'EOF'
#!/bin/sh
MOUNT=/mnt/data
MAPPER=/dev/mapper/workspaces
EOF
  write_file "$i/workspaces-luks-provision.sh" <<'EOF'
#!/usr/bin/env bash
# The format step (`cryptsetup luksFormat`) is reachable only through the chokepoints.
MAPPER_NAME=workspaces
MAPPER="/dev/mapper/$MAPPER_NAME"
FSTAB_LINE='/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2'
printf '%s' "$KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV" >/dev/null 2>"$ERRF"
printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" >/dev/null 2>"$ERRF"
EOF
  write_file "$i/cloud-init.yml" <<'EOF'
runcmd:
  # the provisioner runs before anything writes under /mnt/data
  - /usr/local/bin/workspaces-luks-provision.sh
EOF
}

WC_APP='"apparatus": "apps/web-platform/infra/workspaces-luks-provision.sh",'
WC_KC='"key_chain": { "consumer": "hcloud_server.web", "token": "doppler_service_token.workspaces_luks_fresh_boot_web", "secret": "doppler_secret.workspaces_luks_web_key", "password": "random_password.workspaces_luks_web" },'

# mk_webclass_ledger <out> [apparatus] [key_chain] — an argument that is
# passed EMPTY is an omission; an argument that is not passed takes the canonical value.
mk_webclass_ledger() {
  local out="$1" app="${2-$WC_APP}" kc="${3-$WC_KC}"
  write_file "$out" <<EOF
{
  "schema_version": 1,
  "store_classes": { "hcloud_volume": { "kind": "guest-luks-volume", "mechanisms": ["luks"] } },
  "non_store_types": ["hcloud_volume_attachment", "random_password", "doppler_secret", "doppler_service_token", "doppler_config", "hcloud_server"],
  "non_iac_stores": [],
  "stores": [
$(mk_workspaces_row "hcloud_volume.workspaces_luks" "hcloud_volume_attachment.workspaces_luks"),
    {
      "store": "hcloud_volume.workspaces",
      "kind": "guest-luks-volume",
      "device_binding": {
        "volume": "hcloud_volume.workspaces",
        "attachment": "hcloud_volume_attachment.workspaces",
        $app
        $kc
        "mapper": "workspaces"
      },
      "at_rest": {
        "mechanism": "luks",
        "evidence": "apps/web-platform/infra/workspaces-luks-provision.sh",
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

# wc_variant <name> — a copy of the canonical repo to edit in place.
wc_variant() {
  local dst="$TMPDIR_TEST/wc-$1"
  cp -r "$WC" "$dst"
  printf '%s' "$dst"
}
INFRA=apps/web-platform/infra

WC="$TMPDIR_TEST/wc-canonical"
mk_webclass_repo "$WC"
WC_LEDGER="$TMPDIR_TEST/wc-canonical-ledger.json"
mk_webclass_ledger "$WC_LEDGER"

run_case_reports "WC-1 canonical web-class row (indexed binding, key chain, apparatus) -> PASS" 0 \
  "encryption-posture:" --repo-sweep --repo-root "$WC" --ledger "$WC_LEDGER" --today "$TODAY"

# Guard 1 - indexed volume binding ------------------------------------------------
V="$(wc_variant lit-index)"
sed -i 's/^\(  volume_id = \)hcloud_volume.workspaces\[each.key\].id/\1hcloud_volume.workspaces["web-1"].id/' "$V/$INFRA/server.tf"
run_case_reports "WC-2 attachment indexed by a literal key -> FAIL does not attach" 1 "does not attach" \
  --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

V_FE="$(wc_variant foreach-differs)"
sed -i '/resource "hcloud_volume_attachment" "workspaces"/,/^}/ s/for_each  = local.plaintext_workspaces_hosts/for_each  = var.web_hosts/' "$V_FE/$INFRA/server.tf"
run_case_reports "WC-3 attachment and volume for_each differ -> FAIL identical for_each" 1 "make them the same expression" \
  --repo-sweep --repo-root "$V_FE" --ledger "$WC_LEDGER" --today "$TODAY"

V="$(wc_variant decoy-foreach)"
sed -i '/resource "hcloud_volume_attachment" "workspaces"/,/^}/ s|^  server_id = \(.*\)$|  server_id = \1\n  # for_each = local.some_other_expression\n  tags = "for_each = local.some_other_expression"|' "$V/$INFRA/server.tf"
run_case_reports "WC-4 a commented and a quoted for_each decoy do not count -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

V="$(wc_variant nested-foreach)"
sed -i '/resource "hcloud_volume_attachment" "workspaces"/,/^}/ s|^  server_id = \(.*\)$|  server_id = \1\n  timeouts {\n    for_each = local.plaintext_workspaces_hosts\n  }|' "$V/$INFRA/server.tf"
run_case_reports "WC-5 a for_each inside a nested block -> FAIL fail closed" 1 "nested block" \
  --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

V="$(wc_variant dup-decl)"
write_file "$V/apps/aaa/infra/server.tf" <<'EOF'
resource "hcloud_volume_attachment" "workspaces" {
  for_each  = local.plaintext_workspaces_hosts
  volume_id = hcloud_volume.workspaces[each.key].id
  server_id = hcloud_server.web[each.key].id
}
EOF
run_case_reports "WC-6 a decoy attachment declared in an earlier directory -> FAIL declared more than once" 1 \
  "the binding is ambiguous" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

V="$(wc_variant renamed-local)"
sed -i 's/plaintext_workspaces_hosts/web2_only_hosts/g' "$V/$INFRA/server.tf"
run_case_reports "WC-7 a differently named for_each local, identical on both blocks -> PASS (non-canonical)" 0 \
  "encryption-posture:" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# Guard 2 - key chain and password uniqueness --------------------------------------
V_TOK="$(wc_variant token-config)"
sed -i 's/config  = doppler_config.workspaces_luks_web.name/config  = "prd_workspaces_luks"/' "$V_TOK/$INFRA/workspaces-luks-fresh-boot.tf"
run_case_reports "WC-8 token config differs from the secret config -> FAIL key_chain token config" 1 \
  "key_chain token config" --repo-sweep --repo-root "$V_TOK" --ledger "$WC_LEDGER" --today "$TODAY"

V_SEC="$(wc_variant secret-value)"
sed -i 's/value      = random_password.workspaces_luks_web.result/value      = random_password.workspaces_luks_other.result/' "$V_SEC/$INFRA/workspaces-luks-header-web.tf"
run_case_reports "WC-9 secret value is not the keyed password -> FAIL key_chain secret value" 1 \
  "key_chain secret value" --repo-sweep --repo-root "$V_SEC" --ledger "$WC_LEDGER" --today "$TODAY"

V_UNI="$(wc_variant uniq)"
sed -i 's/random_password.workspaces_luks_web.result/random_password.workspaces_luks.result/' "$V_UNI/$INFRA/workspaces-luks-header-web.tf"
LEDGER_UNI="$TMPDIR_TEST/wc-uniq-ledger.json"
mk_webclass_ledger "$LEDGER_UNI" "$WC_APP" "${WC_KC//random_password.workspaces_luks_web/random_password.workspaces_luks}"
run_case_reports "WC-10 one random_password claimed by two luks rows -> FAIL claimed by more than one luks row" 1 \
  "claimed by more than one luks row" --repo-sweep --repo-root "$V_UNI" --ledger "$LEDGER_UNI" --today "$TODAY"

V="$(wc_variant chain-comment)"
sed -i 's|^\(    workspaces_volume_id .*\)"retired-6604"$|    # canonical: \1"retired-6604"\n    workspaces_volume_id = hcloud_volume.workspaces["web-2"].id|' "$V/$INFRA/server.tf"
run_case_reports "WC-11 the canonical consumer line only in a comment -> FAIL key_chain consumer" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# Guard 2/3/4 - mandatory when indexed ---------------------------------------------
V_NA="$(wc_variant no-apparatus)"
LEDGER_NA="$TMPDIR_TEST/wc-no-apparatus-ledger.json"
mk_webclass_ledger "$LEDGER_NA" ""
run_case_reports "WC-12 indexed row without apparatus -> FAIL requires apparatus" 1 "requires apparatus" \
  --repo-sweep --repo-root "$V_NA" --ledger "$LEDGER_NA" --today "$TODAY"

# The row without key_chain must be otherwise valid: a decoy secret pair sits in server.tf, so the
# same-file pair check alone would PASS it (the #6588 false-PASS shape).
V_NK="$(wc_variant no-keychain)"
assert_fixture_dir "$V_NK"
cat >> "$V_NK/$INFRA/server.tf" <<'EOF'

resource "random_password" "decoy" {
  length = 40
}

resource "doppler_secret" "decoy" {
  project = "soleur"
  config  = "prd_decoy"
  name    = "DECOY"
  value   = random_password.decoy.result
}
EOF
LEDGER_NK="$TMPDIR_TEST/wc-no-keychain-ledger.json"
mk_webclass_ledger "$LEDGER_NK" "$WC_APP" ""
run_case_reports "WC-13 indexed row without key_chain -> FAIL requires key_chain" 1 "requires key_chain" \
  --repo-sweep --repo-root "$V_NK" --ledger "$LEDGER_NK" --today "$TODAY"

# Guard 3 - apparatus pinned to the provisioner file --------------------------------
V="$(wc_variant app-cutover)"
sed -i 's|^    "workspaces-luks-provision.sh",|    "workspaces-luks-provision.sh",\n    "workspaces-cutover.sh",|' "$V/$INFRA/server.tf"
assert_fixture_dir "$V"
printf '  - /usr/local/bin/workspaces-cutover.sh\n' >> "$V/$INFRA/cloud-init.yml"
LEDGER_AC="$TMPDIR_TEST/wc-app-cutover-ledger.json"
mk_webclass_ledger "$LEDGER_AC" '"apparatus": "apps/web-platform/infra/workspaces-cutover.sh",'
run_case_reports "WC-15 apparatus pinned to web-1's cutover script -> FAIL no mount evidence in the pinned file" 1 \
  "mount evidence in the pinned apparatus" --repo-sweep --repo-root "$V" --ledger "$LEDGER_AC" --today "$TODAY"

V="$(wc_variant mapper-rename)"
sed -i 's/^MAPPER_NAME=workspaces$/MAPPER_NAME=other/' "$V/$INFRA/workspaces-luks-provision.sh"
run_case_reports "WC-16 the provisioner opens a different mapper -> FAIL pinned apparatus does not resolve" 1 \
  "does not resolve a cryptsetup luksFormat+luksOpen site" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

V="$(wc_variant decoy-apparatus)"
assert_fixture_dir "$V"
cp "$V/$INFRA/workspaces-luks-provision.sh" "$V/$INFRA/workspaces-luks-decoy.sh"
LEDGER_DA="$TMPDIR_TEST/wc-decoy-app-ledger.json"
mk_webclass_ledger "$LEDGER_DA" '"apparatus": "apps/web-platform/infra/workspaces-luks-decoy.sh",'
run_case_reports "WC-17 a decoy apparatus no host script list or cloud-init names -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V" --ledger "$LEDGER_DA" --today "$TODAY"

V="$(wc_variant comment-apparatus)"
write_file "$V/$INFRA/workspaces-luks-provision.sh" <<'EOF'
#!/usr/bin/env bash
# MAPPER_NAME=workspaces
# cryptsetup luksFormat --batch-mode "$DEV"
# cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME"
# FSTAB_LINE='/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2'
echo nothing
EOF
run_case_reports "WC-18 apparatus text only in comments -> FAIL pinned apparatus does not resolve" 1 \
  "does not resolve a cryptsetup luksFormat+luksOpen site" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

LEDGER_TWO="$TMPDIR_TEST/wc-two-pin-ledger.json"
mk_webclass_ledger "$LEDGER_TWO"
python3 - "$LEDGER_TWO" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["stores"][0]["device_binding"]["apparatus"] = "apps/web-platform/infra/workspaces-luks-provision.sh"
json.dump(d, open(p, "w"), indent=2)
PY
run_case_reports "WC-19 two rows pin one apparatus file -> FAIL pinned by more than one row" 1 \
  "pinned by more than one row" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_TWO" --today "$TODAY"

# The #6588 false-PASS construction: the flipped row pointed at web-1's volume and attachment.
LEDGER_FP="$TMPDIR_TEST/wc-false-pass-ledger.json"
mk_webclass_ledger "$LEDGER_FP" "" ""
python3 - "$LEDGER_FP" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
db = d["stores"][1]["device_binding"]
db["volume"] = "hcloud_volume.workspaces_luks"
db["attachment"] = "hcloud_volume_attachment.workspaces_luks"
json.dump(d, open(p, "w"), indent=2)
PY
run_case_reports "WC-25 the flipped row pointed at web-1's volume and attachment -> FAIL volume must equal the store" 1 \
  "must equal the store" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_FP" --today "$TODAY"

# Validator shape checks: a malformed new key FAILs instead of raising.
LEDGER_BAD="$TMPDIR_TEST/wc-bad-shape-ledger.json"
mk_webclass_ledger "$LEDGER_BAD" "$WC_APP" '"key_chain": "not-an-object",'
run_case_reports "WC-26 a malformed key_chain shape -> FAIL ledger schema (no traceback)" 1 \
  "ledger schema" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_BAD" --today "$TODAY"

V_M3="$(wc_variant web3)"
sed -i 's|^    "web-2" = \(.*\)$|    "web-2" = \1\n    "web-3" = { location = "hel1", private_ip = "10.0.1.12" }|' "$V_M3/$INFRA/variables.tf"

# Host-map multiplicity. The row attests web-2 only; the linter does not parse the for_each
# comprehension (the plan's slim form: a resolver for it exceeded its 40-line budget), so THIS suite is
# what turns a new web host key red until the ledger row is re-attested for it. The extractor is
# proven on a fixture that adds web-3 (positive control) before it is trusted on the real tree.
HOST_MAP_PY="$TMPDIR_TEST/host-map-instances.py"
cat > "$HOST_MAP_PY" <<'PY'
import importlib.util, json, re, sys
from pathlib import Path
infra, sut = Path(sys.argv[1]), sys.argv[2]
spec = importlib.util.spec_from_file_location("sut", sut)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
code, skel = mod.hcl_views((infra / "variables.tf").read_text())
vm = re.search(r'variable\s+"web_hosts"\s*\{', code)
dm = re.compile(r"(?<![\w.])default\s*=\s*\{").search(skel, vm.end())
depth, flat = 0, []
for i in range(dm.end() - 1, len(skel)):
    depth += (skel[i] == "{") - (skel[i] == "}")
    if depth == 0:
        break
    flat.append(code[i] if depth == 1 else " ")
keys = {a or b for a, b in re.findall(r'"([^"]+)"\s*=|\b([A-Za-z_][\w-]*)\s*=', "".join(flat))}
srv = mod.hcl_views((infra / "server.tf").read_text())[0]
loc = re.search(
    r'(?m)^\s*plaintext_workspaces_hosts\s*=\s*\{\s*for\s+k\s*,\s*v\s+in\s+var\.web_hosts\s*:\s*k\s*=>\s*v\s+if\s+(.+?)\s*\}\s*$',
    srv,
)
excluded = set(re.findall(r'k\s*!=\s*"([^"]+)"', loc.group(1))) if loc else {"__shape_not_recognised__"}
print(json.dumps(sorted(keys - excluded)))
PY
host_map_instances() { python3 "$HOST_MAP_PY" "$1/apps/web-platform/infra" "$SUT"; }
HM_CANON="$(host_map_instances "$WC")"
if [[ "$HM_CANON" == '["web-2"]' ]]; then pass "WC-27 host-map extractor: the canonical fixture yields exactly web-2"; else fail "WC-27 host-map extractor: the canonical fixture yields exactly web-2" "got $HM_CANON"; fi
HM_WEB3="$(host_map_instances "$V_M3")"
if [[ "$HM_WEB3" == '["web-2", "web-3"]' ]]; then pass "WC-28 host-map extractor sees a new web-3 key (positive control)"; else fail "WC-28 host-map extractor sees a new web-3 key (positive control)" "got $HM_WEB3"; fi
HM_REAL="$(host_map_instances "$REPO_TRUE_ROOT")"
if [[ "$HM_REAL" == '["web-2"]' ]]; then
  pass "WC-29 the real host map minus web-1 is exactly web-2 (the instances the hcloud_volume.workspaces row attests)"
else
  fail "WC-29 the real host map minus web-1 is exactly web-2 (the instances the hcloud_volume.workspaces row attests)" \
    "got $HM_REAL -> a web host key was added or removed: re-attest the hcloud_volume.workspaces ledger row (apparatus, key_chain, probe coverage) for it before changing this expectation"
fi

# --- design-review round: the guards added after the simplicity and architecture seats ------------------

# WC-30 (real tree): the real ledger with the hcloud_volume.workspaces row flipped to luks passes the
# linter against the REAL Terraform and provisioner. This is the only case that exercises the key-chain
# seam (server.tf lines, the fresh-boot token, the cloud-init invocation) on the real files, so an
# innocent rename there turns THIS suite red instead of surprising the flip PR. After the flip it is
# idempotent (it rewrites the row to the same shape).
LEDGER_REALFLIP="$TMPDIR_TEST/real-flipped-ledger.json"
python3 - "$REPO_TRUE_ROOT/scripts/encryption-posture-ledger.json" "$LEDGER_REALFLIP" <<'PY'
import json, sys
ledger = json.load(open(sys.argv[1]))
found = 0
for row in ledger["stores"]:
    if row["store"] == "hcloud_volume.workspaces":
        found += 1
        row["device_binding"] = {
            "volume": "hcloud_volume.workspaces",
            "attachment": "hcloud_volume_attachment.workspaces",
            "mapper": "workspaces",
            "apparatus": "apps/web-platform/infra/workspaces-luks-provision.sh",
            "key_chain": {
                "consumer": "hcloud_server.web",
                "token": "doppler_service_token.workspaces_luks_fresh_boot_web",
                "secret": "doppler_secret.workspaces_luks_web_key",
                "password": "random_password.workspaces_luks_web",
            },
        }
        row["at_rest"]["mechanism"] = "luks"
        row["at_rest"]["live_verification"] = "available"
        row["at_rest"]["disclosed_as"] = "not-publicly-claimed"
        row["at_rest"].pop("exception", None)
if found != 1:
    sys.exit("WC-30: the hcloud_volume.workspaces row was not found exactly once in the real ledger")
json.dump(ledger, open(sys.argv[2], "w"), indent=2)
PY
run_case_reports "WC-30 the real ledger with the web-2 row flipped to luks passes on the REAL tree" 0 \
  "0 failing checks" --repo-sweep --repo-root "$REPO_TRUE_ROOT" --ledger "$LEDGER_REALFLIP" --today "$TODAY"

# WC-31: the attachment binds a different host than the key chain's consumer.
V_SID="$(wc_variant server-id)"
sed -i 's/server_id = hcloud_server.web\[each.key\].id/server_id = hcloud_server.other[each.key].id/' "$V_SID/$INFRA/server.tf"
run_case_reports "WC-31 the attachment binds a different host than the consumer -> FAIL not the host the attachment binds" 1 \
  "is not the host the attachment binds" --repo-sweep --repo-root "$V_SID" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-32: a commented-out singleton volume_id above a wrapped live one must not satisfy the singleton
# binding (the indexed arm is skipped for `try(...)`; the singleton arm reads the CODE view).
V_DECOY="$(wc_variant comment-volume-id)"
sed -i 's|^  volume_id = hcloud_volume.workspaces\[each.key\].id$|  # volume_id = hcloud_volume.workspaces.id\n  volume_id = try(hcloud_volume.workspaces[each.key].id, "")|' "$V_DECOY/$INFRA/server.tf"
assert_fixture_dir "$V_DECOY"
cat >> "$V_DECOY/$INFRA/server.tf" <<'EOF'

resource "random_password" "decoy" {
  length = 40
}

resource "doppler_secret" "decoy" {
  project = "soleur"
  config  = "prd_decoy"
  name    = "DECOY"
  value   = random_password.decoy.result
}
EOF
LEDGER_DECOY="$TMPDIR_TEST/wc-comment-volume-id-ledger.json"
mk_webclass_ledger "$LEDGER_DECOY" "" ""
run_case_reports "WC-32 a commented singleton volume_id above a wrapped live one -> FAIL does not attach" 1 \
  "does not attach" --repo-sweep --repo-root "$V_DECOY" --ledger "$LEDGER_DECOY" --today "$TODAY"

# WC-33: a singleton (web-1) row may not carry the indexed-only keys.
LEDGER_SING="$TMPDIR_TEST/wc-singleton-keys-ledger.json"
mk_webclass_ledger "$LEDGER_SING"
python3 - "$LEDGER_SING" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["stores"][0]["device_binding"]["key_chain"] = d["stores"][1]["device_binding"]["key_chain"]
json.dump(d, open(p, "w"), indent=2)
PY
run_case_reports "WC-33 a singleton row carrying key_chain -> FAIL indexed binding only" 1 \
  "apply to an indexed" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_SING" --today "$TODAY"

# WC-34: the same file spelled two ways must not dodge the canonical-path rule.
LEDGER_SPELL="$TMPDIR_TEST/wc-spelling-ledger.json"
mk_webclass_ledger "$LEDGER_SPELL" '"apparatus": "apps/web-platform/infra/./workspaces-luks-provision.sh",'
run_case_reports "WC-34 a non-canonical apparatus spelling -> FAIL canonical relative path" 1 \
  "canonical relative path" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_SPELL" --today "$TODAY"

# --- review round: guards for the findings the full panel measured ----------------------------------------

# WC-35: a singleton-shaped decoy attachment (and a secret pair) in an earlier-sorted root must not
# route the indexed row to the singleton name join - the row would resolve through web-1's cutover.
V_DUP="$(wc_variant singleton-decoy)"
write_file "$V_DUP/apps/aaa/infra/decoy.tf" <<'EOF'
resource "hcloud_volume_attachment" "workspaces" {
  volume_id = hcloud_volume.workspaces.id
  server_id = hcloud_server.web["web-2"].id
}

resource "random_password" "decoy" {
  length = 40
}

resource "doppler_secret" "decoy" {
  project = "soleur"
  config  = "prd_decoy"
  name    = "DECOY"
  value   = random_password.decoy.result
}
EOF
LEDGER_DUP="$TMPDIR_TEST/wc-singleton-decoy-ledger.json"
mk_webclass_ledger "$LEDGER_DUP" "" ""
run_case_reports "WC-35 a singleton-shaped decoy attachment in an earlier root -> FAIL declared more than once" 1 \
  "the binding is ambiguous" --repo-sweep --repo-root "$V_DUP" --ledger "$LEDGER_DUP" --today "$TODAY"

# WC-36: a fully commented-out copy of the attachment is not a declaration (positive control).
V_GHOST="$(wc_variant ghost-decl)"
write_file "$V_GHOST/apps/aaa/infra/ghost.tf" <<'EOF'
# resource "hcloud_volume_attachment" "workspaces" {
#   volume_id = hcloud_volume.workspaces.id
# }
EOF
run_case_reports "WC-36 a commented-out copy of the attachment is not a declaration -> PASS" 0 \
  "encryption-posture:" --repo-sweep --repo-root "$V_GHOST" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-37/38: a multi-line for_each is compared whole. The two comprehensions share a first line.
mk_multiline_foreach() {
  python3 - "$1/$INFRA/server.tf" "$2" "$3" <<'PY'
import re, sys
p, vol_body, att_body = sys.argv[1:4]
t = open(p).read()
def swap(t, header, body):
    pat = re.compile(r'(resource "%s" "workspaces" \{\n)  for_each +\= +local.plaintext_workspaces_hosts\n' % header)
    assert pat.search(t), header
    return pat.sub(lambda m: m.group(1) + "  for_each = {\n    for k, v in var.web_hosts : k => v\n    " + body + "\n  }\n", t, count=1)
t = swap(t, "hcloud_volume", vol_body)
t = swap(t, "hcloud_volume_attachment", att_body)
open(p, "w").write(t)
PY
}
V_ML="$(wc_variant multiline-differs)"
mk_multiline_foreach "$V_ML" 'if k != "web-1"' 'if k == "web-2"'
run_case_reports "WC-37 two multi-line for_each comprehensions sharing a first line -> FAIL identical for_each" 1 \
  "make them the same expression" --repo-sweep --repo-root "$V_ML" --ledger "$WC_LEDGER" --today "$TODAY"
V_MLS="$(wc_variant multiline-same)"
mk_multiline_foreach "$V_MLS" 'if k != "web-1"' 'if k != "web-1"'
run_case_reports "WC-38 identical multi-line for_each on both blocks -> PASS (positive control)" 0 \
  "encryption-posture:" --repo-sweep --repo-root "$V_MLS" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-39: the pinned file must be the one the host installs (same basename in another directory is not).
V_SB="$(wc_variant same-basename)"
assert_fixture_dir "$V_SB"
mkdir -p "$V_SB/$INFRA/decoy"
cp "$V_SB/$INFRA/workspaces-luks-provision.sh" "$V_SB/$INFRA/decoy/workspaces-luks-provision.sh"
# shellcheck disable=SC2016  # literal text for the fixture, nothing to expand
printf '#!/usr/bin/env bash\nmkfs.ext4 -F "$DEV"\nmount "$DEV" /mnt/data\n' > "$V_SB/$INFRA/workspaces-luks-provision.sh"
LEDGER_SB="$TMPDIR_TEST/wc-same-basename-ledger.json"
mk_webclass_ledger "$LEDGER_SB" '"apparatus": "apps/web-platform/infra/decoy/workspaces-luks-provision.sh",'
run_case_reports "WC-39 apparatus pinned to a same-basename file in another directory -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V_SB" --ledger "$LEDGER_SB" --today "$TODAY"

# WC-40: a `;#` comment is a comment (the shell starts one after a command separator).
V="$(wc_variant semicolon-comment)"
write_file "$V/$INFRA/workspaces-luks-provision.sh" <<'EOF'
#!/usr/bin/env bash
MAPPER_NAME=workspaces
FSTAB_LINE='/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2'
mkfs.ext4 -F "$DEV"
true;#cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV"
true;#cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME"
EOF
run_case_reports "WC-40 luksFormat/luksOpen after ';#' -> FAIL pinned apparatus does not resolve" 1 \
  "does not resolve a cryptsetup luksFormat+luksOpen site" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-41..43: the install hop has three halves; each alone is not an install.
V="$(wc_variant hop-list-only)"
sed -i '/^  - \/usr\/local\/bin\/workspaces-luks-provision.sh$/d' "$V/$INFRA/cloud-init.yml"
run_case_reports "WC-41 host-script list entry without the cloud-init invocation -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant hop-init-only)"
sed -i '/^    "workspaces-luks-provision.sh",$/d' "$V/$INFRA/server.tf"
run_case_reports "WC-42 cloud-init invocation without the host-script list entry -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant hop-outside-runcmd)"
printf 'write_files:\n  - /usr/local/bin/workspaces-luks-provision.sh\n' > "$V/$INFRA/cloud-init.yml"
run_case_reports "WC-43 the invocation line outside runcmd: -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-44..47: the consumer's user_data must carry BOTH lines, as references (not strings), inside user_data.
V="$(wc_variant no-token-line)"
sed -i '/workspaces_luks_fresh_boot_token = /d' "$V/$INFRA/server.tf"
run_case_reports "WC-44 user_data without the token line -> FAIL key_chain consumer" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant reversed-ternary)"
sed -i 's|? hcloud_volume.workspaces\[each.key\].id : "retired-6604"|? "retired-6604" : hcloud_volume.workspaces[each.key].id|' "$V/$INFRA/server.tf"
run_case_reports "WC-45 the volume reference on the false branch of a ternary -> FAIL key_chain consumer" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant string-volume)"
sed -i 's|? hcloud_volume.workspaces\[each.key\].id : "retired-6604"|? "hcloud_volume.workspaces[each.key].id" : "retired-6604"|' "$V/$INFRA/server.tf"
run_case_reports "WC-46 the volume reference only inside a string literal -> FAIL key_chain consumer" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant outside-user-data)"
sed -i '/^    workspaces_volume_id /d' "$V/$INFRA/server.tf"
# shellcheck disable=SC2016  # literal text for the fixture, nothing to expand
sed -i 's|^  name     = "web-${each.key}"|  name     = "web-${each.key}"\n  labels = { workspaces_volume_id = hcloud_volume.workspaces[each.key].id }|' "$V/$INFRA/server.tf"
run_case_reports "WC-47 the volume-id line outside the user_data argument -> FAIL key_chain consumer" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-48..50: the pinned provisioner is read for what it does, not for its words.
V="$(wc_variant no-luksformat)"
sed -i '/cryptsetup luksFormat/d' "$V/$INFRA/workspaces-luks-provision.sh"
run_case_reports "WC-48 pinned provisioner with a luksOpen but no luksFormat -> FAIL does not resolve" 1 \
  "does not resolve a cryptsetup luksFormat+luksOpen site" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant no-mount-evidence)"
sed -i '/^FSTAB_LINE=/d' "$V/$INFRA/workspaces-luks-provision.sh"
run_case_reports "WC-49 pinned provisioner with a MAPPER path but no fstab line or MOUNT= -> FAIL no mount evidence" 1 \
  "no mount evidence in the pinned apparatus" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant symlink-pin)"
assert_fixture_dir "$V"
ln -s workspaces-luks-provision.sh "$V/$INFRA/workspaces-luks-link.sh"
LEDGER_LN="$TMPDIR_TEST/wc-symlink-ledger.json"
mk_webclass_ledger "$LEDGER_LN" '"apparatus": "apps/web-platform/infra/workspaces-luks-link.sh",'
run_case_reports "WC-50 apparatus pinned through a symlink -> FAIL canonical relative path" 1 \
  "canonical relative path" --repo-sweep --repo-root "$V" --ledger "$LEDGER_LN" --today "$TODAY"
LEDGER_OUT="$TMPDIR_TEST/wc-outside-infra-ledger.json"
mk_webclass_ledger "$LEDGER_OUT" '"apparatus": "scripts/lint-encryption-posture.py",'
run_case_reports "WC-51 apparatus pinned outside apps/*/infra -> FAIL canonical relative path" 1 \
  "canonical relative path" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_OUT" --today "$TODAY"

# WC-52/53: the singleton (web-1) arm reads comment-stripped text too: commented-out apparatus or mount
# evidence certifies nothing (a tightening: origin/main's linter read these arms as raw text).
V="$(wc_variant comment-cutover)"
sed -i 's/^\(printf .*cryptsetup luksOpen.*\)$/# \1/' "$V/$INFRA/workspaces-cutover.sh"
run_case_reports "WC-52 web-1's luksOpen only in a comment -> FAIL does not resolve to any apparatus" 1 \
  "does not resolve to any cryptsetup luksFormat+luksOpen apparatus" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant comment-mount)"
sed -i 's/^MAPPER=/# MAPPER=/' "$V/$INFRA/soleur-host-bootstrap.sh"
run_case_reports "WC-53 web-1's mount evidence only in a comment -> FAIL no mount evidence" 1 \
  "no /etc/fstab or MAPPER=/MOUNT= gate evidence" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# WC-54: the validator rejects a non-string binding field and an unknown device_binding key (no traceback).
LEDGER_TY="$TMPDIR_TEST/wc-type-ledger.json"
mk_webclass_ledger "$LEDGER_TY"
python3 - "$LEDGER_TY" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["stores"][1]["device_binding"]["attachment"] = 5
json.dump(d, open(p, "w"), indent=2)
PY
run_case_reports "WC-54 a non-string device_binding.attachment -> FAIL ledger schema (no traceback)" 1 \
  "device_binding.attachment must be a non-empty string" --repo-sweep --repo-root "$WC" --ledger "$LEDGER_TY" --today "$TODAY"

# WC-55: hcl_views blanks what it must (block comment, heredoc body, brace inside a string, # comment)
# and keeps strings in the code view. Drives the function directly.
HCL_VIEWS_PY="$TMPDIR_TEST/hcl-views-arms.py"
cat > "$HCL_VIEWS_PY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sut", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
text = 'a = 1 /* x { */\nb = "}{"\nc = <<EOT\n}\nEOT\nd = 2 # }\n'
code, skel = mod.hcl_views(text)
ok = (
    len(code) == len(text) == len(skel)
    and "{" not in skel and "}" not in skel
    and '"}{"' in code and "<<EOT" in code and "d = 2" in code
    and "x {" not in code and "# }" not in code and code.count("}") == 1
)
print("ok" if ok else f"bad code={code!r} skel={skel!r}")
PY
HV_OUT="$(python3 "$HCL_VIEWS_PY" "$SUT" 2>&1)"
if [[ "$HV_OUT" == "ok" ]]; then pass "WC-55 hcl_views blanks block comments, heredoc bodies, string braces and # comments"; else fail "WC-55 hcl_views blanks block comments, heredoc bodies, string braces and # comments" "$HV_OUT"; fi

# WC-56..61: findings of the fix-round re-probe (the first line of an attribute must not vouch for the
# next, and a string must not stand in for a reference).
V="$(wc_variant n1-next-attr)"
sed -i 's|^\(    workspaces_volume_id  *= \).*$|\1"retired-6604"\n    decoy_attr = contains(keys(local.plaintext_workspaces_hosts), each.key) ? hcloud_volume.workspaces[each.key].id : "x"|' "$V/$INFRA/server.tf"
run_case_reports "WC-56 the volume reference only on a different user_data attribute -> FAIL user_data does not carry" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n2-token-string)"
sed -i 's|^\(    workspaces_luks_fresh_boot_token = \).*$|\1"none"\n    note = "workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot_web.key"|' "$V/$INFRA/server.tf"
run_case_reports "WC-57 the token line only inside a string literal -> FAIL user_data does not carry" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n2-token-compare)"
sed -i 's|^\(    workspaces_luks_fresh_boot_token = .*\.key\)$|\1 == "" ? "a" : "b"|' "$V/$INFRA/server.tf"
run_case_reports "WC-58 the token reference inside a comparison -> FAIL user_data does not carry" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n3-paren-comment)"
write_file "$V/$INFRA/workspaces-luks-provision.sh" <<'EOF'
#!/usr/bin/env bash
MAPPER_NAME=workspaces
FSTAB_LINE='/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2'
mkfs.ext4 -F "$DEV"
(true)#cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV"
(true)#cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME"
EOF
run_case_reports "WC-59 luksFormat/luksOpen after ')#' -> FAIL pinned apparatus does not resolve" 1 \
  "does not resolve a cryptsetup luksFormat+luksOpen site" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n4-write-files)"
printf 'runcmd:\n  - echo hi\npower_state:\n  mode: reboot\nwrite_files:\n  - /usr/local/bin/workspaces-luks-provision.sh\n' > "$V/$INFRA/cloud-init.yml"
run_case_reports "WC-60 the invocation line after runcmd: but under another top-level key -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n6-string-volume-id)"
python3 - "$V/$INFRA/server.tf" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p).read()
t = t.replace("  volume_id = hcloud_volume.workspaces[each.key].id\n  server_id = hcloud_server.web[each.key].id\n",
              '  volume_id = element([hcloud_volume.workspaces[each.key].id], 0)\n  server_id = hcloud_server.web[each.key].id\n  labels = { note = "volume_id = hcloud_volume.workspaces.id" }\n')
t += '\nresource "random_password" "decoy" {\n  length = 40\n}\n\nresource "doppler_secret" "decoy" {\n  project = "soleur"\n  config  = "prd_decoy"\n  name    = "DECOY"\n  value   = random_password.decoy.result\n}\n'
open(p, "w").write(t)
PY
LEDGER_N6="$TMPDIR_TEST/wc-n6-ledger.json"
mk_webclass_ledger "$LEDGER_N6" "" ""
run_case_reports "WC-61 a string spelling volume_id = <volume>.id beside a wrapped live one -> FAIL does not attach" 1 \
  "does not attach" --repo-sweep --repo-root "$V" --ledger "$LEDGER_N6" --today "$TODAY"

# WC-62..66: second fix-round re-probe (same-line commas, nested objects, multi-line ternary, YAML keys).
V="$(wc_variant n7-comma)"
sed -i 's|^\(    workspaces_volume_id  *= \).*$|\1"retired-6604", decoy = contains(keys(local.plaintext_workspaces_hosts), each.key) ? hcloud_volume.workspaces[each.key].id : "x"|' "$V/$INFRA/server.tf"
run_case_reports "WC-62 the volume reference on a comma-separated second attribute -> FAIL user_data does not carry" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n8-nested-object)"
sed -i 's|^\(    workspaces_volume_id  *= \).*$|\1"retired-6604"\n    unused = {\n      workspaces_volume_id = hcloud_volume.workspaces[each.key].id\n    }|' "$V/$INFRA/server.tf"
run_case_reports "WC-63 the volume line only inside a nested object -> FAIL user_data does not carry" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n9-multiline-ternary)"
sed -i 's|^\(    workspaces_volume_id  *= contains(keys(local.plaintext_workspaces_hosts), each.key) ?\) \(hcloud_volume.*\)$|\1\n      \2|' "$V/$INFRA/server.tf"
run_case_reports "WC-64 a ternary wrapped across lines (reference on the true branch) -> PASS (positive control)" 0 \
  "encryption-posture:" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n10-nested-ternary)"
sed -i 's|^\(    workspaces_volume_id  *= \).*$|\1false ? "retired-6604" : var.x ? hcloud_volume.workspaces[each.key].id : "z"|' "$V/$INFRA/server.tf"
run_case_reports "WC-65 the reference on the false branch of a nested ternary -> FAIL user_data does not carry" 1 \
  "user_data does not carry" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"
V="$(wc_variant n11-quoted-key)"
printf 'runcmd:\n  - echo hi\n"write_files":\n  - /usr/local/bin/workspaces-luks-provision.sh\n' > "$V/$INFRA/cloud-init.yml"
run_case_reports "WC-66 the invocation line under a quoted top-level key after runcmd: -> FAIL not installed" 1 \
  "not installed by the consumer" --repo-sweep --repo-root "$V" --ledger "$WC_LEDGER" --today "$TODAY"

# --- mutation rows for the new guards ---------------------------------------
# run_mutation_inverse: for a PERMISSIVE arm. Baseline must PASS (exit 0) and the mutated
# SUT must FAIL (exit 1); a control proves the baseline really passes so the row cannot
# score a fixture that was never green.
run_mutation_inverse() {
  local mb="$1" marker="$2" repo="$3" ledger="$4"
  local base_rc=0
  python3 "$SUT" --repo-sweep --repo-root "$repo" --ledger "$ledger" --today "$TODAY" >/dev/null 2>&1 || base_rc=$?
  if [[ "$base_rc" != "0" ]]; then
    fail "$mb instrument control: baseline must PASS before mutation" "baseline exit=$base_rc (expected 0)"
    return
  fi
  local mutated="$TMPDIR_TEST/mutated_inv_${mb//\//_}.py"
  sed "/# MUTATION-TARGET: ${marker} start/,/# MUTATION-TARGET: ${marker} end/d" "$SUT" > "$mutated"
  if cmp -s "$SUT" "$mutated"; then
    fail "$mb mutation must land" "marker ${marker} not found in the SUT"
    return
  fi
  if ! python3 -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" "$mutated" >/dev/null 2>&1; then
    fail "$mb mutated script must still compile" "syntax error after deleting $marker"
    return
  fi
  local mut_rc=0 out
  out="$(python3 "$mutated" --repo-sweep --repo-root "$repo" --ledger "$ledger" --today "$TODAY" 2>&1)" || mut_rc=$?
  if [[ "$mut_rc" == "1" ]] && ! grep -q Traceback <<<"$out"; then
    pass "$mb ($marker): deleting the permissive arm flips PASS->FAIL (arm is load-bearing)"
  else
    fail "$mb ($marker): deleting the permissive arm flips PASS->FAIL (arm is load-bearing)" \
      "mutated exit=$mut_rc (expected 1, no traceback)"
  fi
}

run_mutation "MB-L1" "MB-L1" "$V_FE" "$WC_LEDGER"
run_mutation_inverse "MB-L2" "MB-L2" "$WC" "$WC_LEDGER"
run_mutation "MB-L3" "MB-L3" "$V_TOK" "$WC_LEDGER"
run_mutation "MB-L4" "MB-L4" "$V_SEC" "$WC_LEDGER"
run_mutation "MB-L5" "MB-L5" "$V_UNI" "$LEDGER_UNI"
run_mutation_inverse "MB-L6" "MB-L6" "$WC" "$WC_LEDGER"
run_mutation "MB-L8a" "MB-L8a" "$V_NA" "$LEDGER_NA"
run_mutation "MB-L8b" "MB-L8b" "$V_NK" "$LEDGER_NK"
run_mutation "MB-L10" "MB-L10" "$V_SID" "$WC_LEDGER"
run_mutation "MB-L11" "MB-L11" "$V_DUP" "$LEDGER_DUP"

# ---------------------------------------------------------------------------
# Redis client dependency without a redis.* ledger row (ADR-068 Phase 4a store):
# the session Redis has no *.tf anchor, so the resource partition cannot see it.
# ---------------------------------------------------------------------------
REPO_RD_BAD="$TMPDIR_TEST/rd-bad"
write_file "$REPO_RD_BAD/apps/web-platform/package.json" <<'EOF'
{ "name": "fixture", "dependencies": { "ioredis": "5.4.1" } }
EOF
LEDGER_RD_BAD="$TMPDIR_TEST/rd-bad-ledger.json"
write_file "$LEDGER_RD_BAD" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": [],
  "stores": [],
  "connections": []
}
EOF
REPO_RD_OTEL="$TMPDIR_TEST/rd-otel"
write_file "$REPO_RD_OTEL/apps/web-platform/package.json" <<'EOF'
{ "name": "fixture", "dependencies": { "@opentelemetry/instrumentation-ioredis": "0.40.0" } }
EOF
REPO_RD_OK="$TMPDIR_TEST/rd-ok"
write_file "$REPO_RD_OK/apps/web-platform/package.json" <<'EOF'
{ "name": "fixture", "dependencies": { "ioredis": "5.4.1" } }
EOF
LEDGER_RD_OK="$TMPDIR_TEST/rd-ok-ledger.json"
write_file "$LEDGER_RD_OK" <<'EOF'
{
  "schema_version": 1,
  "store_classes": {},
  "non_store_types": [],
  "non_iac_stores": ["redis.session_store"],
  "stores": [
    {
      "store": "redis.session_store",
      "kind": "provider-db",
      "at_rest": {
        "mechanism": "provider-managed:Fixture-SOC2-Type-II",
        "evidence": "fixture trust center compliance page",
        "attestation_url": "https://example.com/security",
        "retrieved_on": "2026-06-01",
        "defends_against": "a seized or decommissioned physical disk at the provider",
        "does_not_defend": "a leaked credential or a misconfigured ACL",
        "disclosed_as": "not-publicly-claimed",
        "live_verification": "unavailable:no probe in this fixture"
      }
    }
  ],
  "connections": []
}
EOF
run_case_reports "RD-1 redis client dependency, no redis.* row -> FAIL" 1 "Redis client dependency ioredis" \
  --repo-sweep --repo-root "$REPO_RD_BAD" --ledger "$LEDGER_RD_BAD" --today "$TODAY"
run_case_reports "RD-2 redis client dependency WITH a redis.* row -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_RD_OK" --ledger "$LEDGER_RD_OK" --today "$TODAY"
run_case_reports "RD-3 otel ioredis instrumentation is not a client -> PASS" 0 "encryption-posture:" \
  --repo-sweep --repo-root "$REPO_RD_OTEL" --ledger "$LEDGER_RD_BAD" --today "$TODAY"
run_mutation "MB-R1" "MB-R1" "$REPO_RD_BAD" "$LEDGER_RD_BAD"
# Every member of the client set, in every dependency section, in any manifest; an alias of a
# client; a malformed manifest. A `redis.*` row of any kind satisfies the check by design: it
# asserts that SOME Redis is accounted for, not which one (the row names the store).
rd_case() {  # <name> <expect-exit> <needle> <relative manifest path> <manifest body>
  local name="$1" expect="$2" needle="$3" rel="$4" body="$5" repo
  repo="$(mktemp -d "$TMPDIR_TEST/rd.XXXXXXXX")"
  assert_fixture_dir "$repo"
  mkdir -p "$(dirname "$repo/$rel")"
  printf '%s\n' "$body" > "$repo/$rel"
  run_case_reports "$name" "$expect" "$needle" \
    --repo-sweep --repo-root "$repo" --ledger "$LEDGER_RD_BAD" --today "$TODAY"
}
for rd_pkg in redis ioredis iovalkey @redis/client @valkey/client @upstash/redis @keyv/redis connect-redis bullmq; do
  rd_case "RD-4 client set member $rd_pkg -> FAIL" 1 "Redis client dependency $rd_pkg" \
    apps/web-platform/package.json "{ \"dependencies\": { \"$rd_pkg\": \"1.0.0\" } }"
done
rd_case "RD-5 devDependencies-only client -> FAIL" 1 "Redis client dependency ioredis" \
  apps/web-platform/package.json '{ "devDependencies": { "ioredis": "5.4.1" } }'
rd_case "RD-5b optionalDependencies-only client -> FAIL" 1 "Redis client dependency ioredis" \
  apps/web-platform/package.json '{ "optionalDependencies": { "ioredis": "5.4.1" } }'
rd_case "RD-5c peerDependencies-only client -> FAIL" 1 "Redis client dependency ioredis" \
  apps/web-platform/package.json '{ "peerDependencies": { "ioredis": "5.4.1" } }'
rd_case "RD-6 npm: alias of a client -> FAIL" 1 "alias of ioredis" \
  apps/web-platform/package.json '{ "dependencies": { "cache": "npm:ioredis@5.4.1" } }'
rd_case "RD-6b npm: alias of a scoped client -> FAIL" 1 "alias of @upstash/redis" \
  apps/web-platform/package.json '{ "dependencies": { "cache": "npm:@upstash/redis@1.0.0" } }'
rd_case "RD-7 client in a different manifest than apps/web-platform -> FAIL" 1 "Redis client dependency ioredis" \
  packages/session/package.json '{ "dependencies": { "ioredis": "5.4.1" } }'
rd_case "RD-8 malformed package.json -> FAIL" 1 "not a valid JSON object" \
  apps/web-platform/package.json '{bad'
rd_case "RD-8b package.json that is a JSON array -> FAIL, no traceback" 1 "not a valid JSON object" \
  apps/web-platform/package.json '[]'
rd_case "RD-9 client under node_modules is skipped -> PASS" 0 "encryption-posture:" \
  node_modules/somepkg/package.json '{ "dependencies": { "ioredis": "5.4.1" } }'

# ---------------------------------------------------------------------------
# Minimum-cardinality guard (an empty/short run must not GREEN).
# ---------------------------------------------------------------------------
MIN_CASES=139  # measured TOTAL (117 at #9941 + RD-1..9 and MB-R1 for the Redis client dependency check); raise with every added case (slack is attack budget)
echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]]
