#!/usr/bin/env bash
# Tests for scripts/lint-encryption-posture.py (the Layer A encryption-posture
# detector, ADR-139). This is a SECURITY GATE: the whole point is that a ledger
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

# Graceful degrade: no scripts/encryption-posture-ledger.json and no --ledger
# override -> exit 0 with a "not yet seeded" note (must not break CI pre-audit).
REPO_NOLEDGER="$TMPDIR_TEST/noledger"
mkdir -p "$REPO_NOLEDGER/scripts"
run_case_reports "repo-sweep degrades gracefully when the ledger is not yet seeded" 0 "not yet seeded" \
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

# ---------------------------------------------------------------------------
# Minimum-cardinality guard (an empty/short run must not GREEN).
# ---------------------------------------------------------------------------
MIN_CASES=30
echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]]
