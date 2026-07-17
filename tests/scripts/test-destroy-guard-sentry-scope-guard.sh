#!/usr/bin/env bash
# Forward-looking guard: asserts every Sentry resource TYPE that can appear in an
# apply-sentry-infra.yml plan is a type whose nested-block exposure
# destroy-guard-filter-sentry.jq has been verified to cover. Currently:
# sentry_cron_monitor, sentry_uptime_monitor, sentry_issue_alert.
#
# WHY TYPES MATTER. The jq filter counts resource-level deletes generically, but
# an ARRAY-OF-BLOCKS shrink (an `actions_v2` element removed from an alert that
# is otherwise updated, not deleted) is invisible to `resource_deletes` and needs
# a per-type clause. sentry_cron_monitor and sentry_uptime_monitor expose ZERO
# array-of-blocks (every attribute is scalar; uptime's `assertion_json` is a
# function-built string, `owner` a single-nested attribute), so the filter's
# literal `nested_deletes: 0` is correct for them. sentry_issue_alert DOES carry
# array-of-blocks and has a matching clause (#4364). A FOURTH type arriving
# without a filter clause would silently bypass the nested-block guard.
#
# ── WHERE THE TYPE SET COMES FROM (#6589) ──────────────────────────────────
# This guard used to read the types out of apply-sentry-infra.yml's `-target=`
# allow-list. #6589 deleted that list (it made deletion a silent no-op), so the
# source had to change. The naive replacement — read the .tf files — is VACUOUS
# IN EXACTLY THE DIRECTION OF THE BUG:
#
#   Under a full-root plan the universe is `state UNION config`. A type present
#   in STATE with no remaining .tf block is invisible to a .tf-only reader — and
#   that is precisely the class #6589 exists to destroy. Had
#   kb_tenant_mint_silent_fallback been the last sentry_issue_alert, a .tf-only
#   guard would have omitted that type, passed VACUOUSLY, and let an
#   array-of-blocks destroy through unchecked.
#
# So the type set is `types(.tf) UNION types(state)`. The two halves are read in
# different places, because they are available in different places:
#
#   .tf half   — here. Cheap, needs no credentials, runs on every PR via
#                scripts/test-all.sh. Catches the common case (someone adds a
#                `resource "sentry_metric_alert"` block).
#   state half — NOT readable here. The R2 s3 backend requires AWS credentials
#                (main.tf), and this script runs in test-all.sh, which has none.
#                Attempting `terraform state list` here and tolerating its
#                failure would REBUILD the vacuity: a guard that silently reads
#                nothing reports green forever. So the authoritative state-side
#                check lives in apply-sentry-infra.yml, which asserts the SAME
#                type allow-list against `terraform show -json`'s
#                .resource_changes[].type — the plan JSON *is* state UNION config,
#                so that check is exact rather than a reconstruction.
#
# Callers that DO have state (the workflow, or an operator) may inject the state
# half via SENTRY_STATE_TYPES (newline-separated type names) and get the full
# union verdict from this script.
#
# COMPENSATING CONTROL FOR BETA-PROVIDER DRIFT: this guard keys on resource TYPE,
# not on live nested-block shape. `sentry_uptime_monitor` is a beta resource
# (pinned v0.15.4 as of #6636; the beta2 → 0.15.4 bump planned no-op with no
# array-of-blocks reshape). A future provider bump could still graduate it and add
# a real array-of-blocks attribute, which a type allow-list would NOT catch on its own.
# The compensating control is the mandatory schema re-validation on every
# `terraform init -upgrade`, recorded in the uptime-monitors.tf BETA STATUS
# comment — re-confirm `block_types: []` there and extend the jq filter if that
# ever changes.
#
# Closes #4419 review-finding user-impact F2; re-sourced by #6589.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Parameterized (#6589) so the empty->FAIL posture is TESTABLE. Previously the
# input was hardcoded with no injection point, so "a guard that passes on empty
# is broken" could be asserted in prose but never exercised. AC6 points this at
# an empty dir and requires a FAIL.
SENTRY_TF_DIR="${SENTRY_TF_DIR:-$REPO_ROOT/apps/web-platform/infra/sentry}"

# Types covered by destroy-guard-filter-sentry.jq. Adding a type here without a
# matching filter clause re-opens the nested-block bypass.
COVERED_TYPES='sentry_cron_monitor|sentry_uptime_monitor|sentry_issue_alert'

if [[ ! -d "$SENTRY_TF_DIR" ]]; then
  echo "[FAIL] SENTRY_TF_DIR does not exist: $SENTRY_TF_DIR" >&2
  exit 1
fi

# ── .tf half ────────────────────────────────────────────────────────────────
# `resource "<type>" "<name>"` only — `data "sentry_project"` is deliberately not
# matched (data sources are never destroyed). Comment lines are stripped first so
# a commented-out resource block is not counted as live scope.
tf_types=$(
  find "$SENTRY_TF_DIR" -maxdepth 1 -name '*.tf' -print0 2>/dev/null \
    | xargs -0 -r grep -hE '^[[:space:]]*resource[[:space:]]+"' 2>/dev/null \
    | sed -E 's/^[[:space:]]*resource[[:space:]]+"([^"]+)".*/\1/' \
    | sort -u || true
)

# ── state half (injected; see header) ───────────────────────────────────────
# `terraform state list` emits `<type>.<name>` (and `<type>.<name>["key"]`);
# reduce to the bare type. Absent => this run checks the .tf half only, which is
# stated LOUDLY below rather than passing silently as if state had been read.
state_types=""
if [[ -n "${SENTRY_STATE_TYPES:-}" ]]; then
  state_types=$(printf '%s\n' "$SENTRY_STATE_TYPES" \
    | sed -E 's/^([a-z0-9_]+)\..*$/\1/' \
    | grep -E '^[a-z0-9_]+$' \
    | sort -u || true)
fi

types=$(printf '%s\n%s\n' "$tf_types" "$state_types" | grep -vE '^$' | sort -u || true)

# Empty => FAIL. A guard that passes when it discovered nothing is broken: it
# would report green after a parser regression, a moved directory, or an empty
# SENTRY_TF_DIR — exactly when its verdict matters most.
if [[ -z "$types" ]]; then
  echo "[FAIL] no sentry resource types discovered under $SENTRY_TF_DIR (and no SENTRY_STATE_TYPES injected)." >&2
  echo "       A guard that passes on an empty discovery is not a guard — failing closed." >&2
  exit 1
fi

unexpected=$(echo "$types" | grep -vxE "$COVERED_TYPES" || true)
if [[ -n "$unexpected" ]]; then
  echo "[FAIL] apps/web-platform/infra/sentry declares resource type(s) the destroy filter does not cover:" >&2
  printf '  %s\n' "$unexpected" >&2
  echo "" >&2
  echo "Before this PR can land, extend tests/scripts/lib/destroy-guard-filter-sentry.jq" >&2
  echo "with a path-specific nested-clause for the new type — see the" >&2
  echo "destroy-guard-filter-web-platform.jq pattern. Then add a corresponding" >&2
  echo "fixture + test case to tests/scripts/test-destroy-guard-counter-sentry.sh." >&2
  exit 1
fi

n=$(echo "$types" | wc -l | tr -d ' ')
if [[ -n "$state_types" ]]; then
  echo "[ok] all $n sentry resource type(s) in .tf UNION state are covered by the destroy filter"
else
  echo "[ok] all $n sentry resource type(s) declared in $SENTRY_TF_DIR are covered by the destroy filter"
  echo "     (.tf half only — no SENTRY_STATE_TYPES injected. The state half is asserted"
  echo "      authoritatively by apply-sentry-infra.yml against the plan JSON, which is"
  echo "      state UNION config; this run cannot reach the R2 backend.)"
fi
