#!/usr/bin/env bash
# Tests for Class D detection in apps/web-platform/scripts/sentry-monitors-audit.sh
# (#6589) — is every LIVE Sentry monitor declared by a `.tf` resource block?
#
# The whole point of Class D is the EXIT CODE. Classes A/B/C only print into a
# report; if Class D did the same it would be a detector wired to nothing —
# apply-sentry-infra.yml would stay green while undeclared monitors bill
# $0.78/mo forever. T5 is the load-bearing assertion: the clean fixture and the
# orphan fixture must NOT return the same code. If they ever do, this gate is
# worthless and every other test here is decoration.
#
# Hermetic: the audit script needs a live token + network, so every run here
# injects SENTRY_FIXTURE_MONITORS / SENTRY_FIXTURE_RULES / SENTRY_TF_DIR (the
# same seams sentry-monitors-audit.test.sh uses). The live API is NEVER called
# — SENTRY_FIXTURE_MONITORS also short-circuits the script's 4-gate block,
# which is the only other code path that would issue HTTP.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/apps/web-platform/scripts/sentry-monitors-audit.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

[[ -f "$SCRIPT" ]] || { echo "ERROR: $SCRIPT does not exist." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by the audit script." >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixtures mirror the REAL list-endpoint shape: liveness lives in
# `environments[].lastCheckIn`, and there is NO top-level `.lastCheckIn`
# (TR3). `declared-live` has checked in; `never-checked-in` carries an
# environment whose lastCheckIn is null — the shape that yields the `never`
# sentinel rather than an empty marker field.
cat > "$TMP/monitors.json" <<'JSON'
[
  {
    "slug": "declared-live",
    "name": "declared-live",
    "type": "cron_job",
    "dateCreated": "2026-01-05T09:00:00.000000Z",
    "config": { "schedule": "0 * * * *" },
    "environments": [
      { "name": "production", "status": "ok", "lastCheckIn": "2026-07-16T04:00:00Z" }
    ]
  }
]
JSON

cat > "$TMP/monitors-orphan.json" <<'JSON'
[
  {
    "slug": "declared-live",
    "name": "declared-live",
    "type": "cron_job",
    "dateCreated": "2026-01-05T09:00:00.000000Z",
    "config": { "schedule": "0 * * * *" },
    "environments": [
      { "name": "production", "status": "ok", "lastCheckIn": "2026-07-16T04:00:00Z" }
    ]
  },
  {
    "slug": "undeclared-orphan",
    "name": "undeclared-orphan",
    "type": "cron_job",
    "dateCreated": "2026-03-02T11:30:00.000000Z",
    "config": { "schedule": "0 3 * * *" },
    "environments": [
      { "name": "production", "status": "ok", "lastCheckIn": "2026-05-01T03:00:00Z" },
      { "name": "staging", "status": "ok", "lastCheckIn": "2026-06-20T03:00:00Z" }
    ]
  },
  {
    "slug": "never-checked-in",
    "name": "never-checked-in",
    "type": "cron_job",
    "dateCreated": "2026-06-11T08:15:00.000000Z",
    "config": { "schedule": "0 4 * * *" },
    "environments": [
      { "name": "production", "status": "active", "lastCheckIn": null }
    ]
  }
]
JSON

printf '[]' > "$TMP/rules.json"

# Declares `declared-live` only. `undeclared-orphan` and `never-checked-in`
# appear ONLY in a comment — a bare `grep -F "$slug" *.tf` matches this prose
# and reports zero orphans, which is the exact false-negative the block-anchored
# extraction exists to prevent. The sibling `sentry_issue_alert` block carries a
# kebab-case `name` too: if extraction is not scoped to sentry_cron_monitor, its
# name leaks into the declared set.
mkdir -p "$TMP/tf"
cat > "$TMP/tf/cron-monitors.tf" <<'TF'
# Cohort notes: undeclared-orphan and never-checked-in were retired from this
# root; see the migration log. This prose is the anchor trap.
resource "sentry_cron_monitor" "declared_live" {
  organization = var.sentry_org
  name         = "declared-live"
  schedule     = { crontab = "0 * * * *" }
}

resource "sentry_issue_alert" "some_alert" {
  organization = var.sentry_org
  name         = "undeclared-orphan"
}
TF

# _run <monitors-fixture> -> "<rc>|<stdout>"
_run() {
  local out rc=0
  out=$(SENTRY_AUTH_TOKEN=fake \
        SENTRY_ORG=jikigai \
        SENTRY_API_HOST=de.sentry.io \
        NEXT_PUBLIC_SENTRY_DSN='https://test@o123.ingest.de.sentry.io/456' \
        SENTRY_FIXTURE_MONITORS="$1" \
        SENTRY_FIXTURE_RULES="$TMP/rules.json" \
        SENTRY_TF_DIR="$TMP/tf" \
        AUDIT_OUT_DIR="$TMP/out" \
        bash "$SCRIPT" 2>/dev/null) || rc=$?
  printf '%s|%s' "$rc" "$out"
}

CLEAN_RESULT=$(_run "$TMP/monitors.json")
ORPHAN_RESULT=$(_run "$TMP/monitors-orphan.json")
CLEAN_RC="${CLEAN_RESULT%%|*}"; CLEAN_OUT="${CLEAN_RESULT#*|}"
ORPHAN_RC="${ORPHAN_RESULT%%|*}"; ORPHAN_OUT="${ORPHAN_RESULT#*|}"

# ── T1: a live monitor WITH a .tf block is not Class D ──────────────────────
t_declared_monitor_is_not_class_d() {
  if ! grep -q 'SOLEUR_SENTRY_CLASS_D_ORPHAN' <<<"$CLEAN_OUT"; then
    _report "T1 a live monitor with a .tf block emits no Class D marker" ok
  else
    _report "T1 a live monitor with a .tf block emits no Class D marker" bad "got: $CLEAN_OUT"
  fi
}

# ── T2: a live monitor with NO .tf block IS Class D, and FAILS the run ──────
t_undeclared_monitor_is_class_d_and_exits_nonzero() {
  if grep -q 'SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=undeclared-orphan' <<<"$ORPHAN_OUT" \
     && [[ "$ORPHAN_RC" -ne 0 ]]; then
    _report "T2 an undeclared live monitor emits a marker AND exits non-zero" ok
  else
    _report "T2 an undeclared live monitor emits a marker AND exits non-zero" bad \
      "rc=$ORPHAN_RC out=$ORPHAN_OUT"
  fi
}

# ── T3: a slug named only in a .tf COMMENT is still Class D ─────────────────
# Proves the extraction anchors on the resource block, not on prose. A bare
# slug grep would suppress this orphan silently.
t_comment_mention_does_not_declare() {
  if grep -q 'SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=never-checked-in' <<<"$ORPHAN_OUT"; then
    _report "T3 a slug mentioned only in a .tf comment is still Class D" ok
  else
    _report "T3 a slug mentioned only in a .tf comment is still Class D" bad "out=$ORPHAN_OUT"
  fi
}

# ── T4: exact marker format, including the `never` sentinel ─────────────────
# TR3: last_checkin comes from environments[].lastCheckIn (newest across
# environments — 06-20 beats 05-01), never from a top-level .lastCheckIn,
# which does not exist on the list endpoint and would print `null` for all.
t_marker_format_is_exact() {
  local want_orphan want_never
  want_orphan='SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=undeclared-orphan created=2026-03-02T11:30:00.000000Z last_checkin=2026-06-20T03:00:00Z cost_usd=0.78'
  want_never='SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=never-checked-in created=2026-06-11T08:15:00.000000Z last_checkin=never cost_usd=0.78'
  if grep -qxF -- "$want_orphan" <<<"$ORPHAN_OUT" && grep -qxF -- "$want_never" <<<"$ORPHAN_OUT"; then
    _report "T4 marker matches the exact contract (newest env check-in; 'never' sentinel)" ok
  else
    _report "T4 marker matches the exact contract (newest env check-in; 'never' sentinel)" bad \
      "out=$ORPHAN_OUT"
  fi
}

# ── T5: NON-VACUITY — the two fixtures must diverge on exit code ────────────
# The reason this suite exists. A gate that returns the same code either way
# gates nothing.
t_gate_discriminates_on_exit_code() {
  if [[ "$CLEAN_RC" -eq 0 && "$ORPHAN_RC" -ne 0 ]]; then
    _report "T5 exit 0 with no orphans, non-zero with an orphan (gate discriminates)" ok
  else
    _report "T5 exit 0 with no orphans, non-zero with an orphan (gate discriminates)" bad \
      "clean_rc=$CLEAN_RC orphan_rc=$ORPHAN_RC"
  fi
}

# ── T6: the report still lands before the gate fires ───────────────────────
# The operator needs the list, not just a red X — the exit must not pre-empt
# the report write.
t_report_written_even_when_gate_fails() {
  local report
  report=$(ls "$TMP/out"/sentry-migration-audit-*.md 2>/dev/null | head -1 || true)
  if [[ -n "$report" ]] && grep -q 'Class D' "$report" && grep -q 'undeclared-orphan' "$report"; then
    _report "T6 the Class D report is written even though the run exits non-zero" ok
  else
    _report "T6 the Class D report is written even though the run exits non-zero" bad \
      "report=${report:-<none>}"
  fi
}

# ── T7: sibling non-cron blocks do not declare a cron monitor ──────────────
# `undeclared-orphan` is the `name` of a sentry_issue_alert block. If the
# extraction is not scoped to sentry_cron_monitor, that name lands in the
# declared set and silently suppresses this orphan. T2 covers the marker; this
# pins the reason it must not disappear.
t_issue_alert_name_does_not_declare_cron_monitor() {
  if grep -q 'slug=undeclared-orphan' <<<"$ORPHAN_OUT"; then
    _report "T7 a sentry_issue_alert 'name' does not declare a cron monitor" ok
  else
    _report "T7 a sentry_issue_alert 'name' does not declare a cron monitor" bad "out=$ORPHAN_OUT"
  fi
}

t_declared_monitor_is_not_class_d
t_undeclared_monitor_is_class_d_and_exits_nonzero
t_comment_mention_does_not_declare
t_marker_format_is_exact
t_gate_discriminates_on_exit_code
t_report_written_even_when_gate_fails
t_issue_alert_name_does_not_declare_cron_monitor

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
