#!/usr/bin/env bash
# sentry-alert-reference-gate.sh — the committed `alert-reference.json` equals
# the projection of the plan this PR would apply (#8050).
#
# WHY THIS EXISTS. The daily drift probe (scheduled-sentry-alert-drift.yml) has
# no Terraform access, so it compares live Sentry against a COMMITTED projection
# of the plan. A committed copy can go stale the moment a `sentry_alert` block is
# added, edited or removed — and a stale reference makes the probe report a
# correctly-applied rule as UNMANAGED, DELETED or DRIFT. This gate runs in the
# PR-time `plan_pr` job and holds the committed copy equal to the plan, so `main`
# cannot merge a `.tf` change without the matching reference. The post-apply
# probe in the `apply` job does NOT read the committed copy: it projects its own
# reference from the plan it applies, so this gate's blast radius is the daily
# job only.
#
# ONE CALL SITE, deliberately: `plan_pr`. An earlier draft also ran it in the
# `apply` job before the apply; both review panels fired on that copy — its red
# would route to a tracking issue whose remedy ("re-run") cannot fix a stale
# committed file. Do not add it back.
#
# Usage: sentry-alert-reference-gate.sh <terraform-show-json-file> <alert-reference.json>
# Exit 0 = projection(plan) == normalise(reference), with >= 1 rule compared.
# Exit 1 = a difference, or a floor tripped (nothing compared is never a PASS).
#
# Reads no credential; not in scripts/lint-shell-trace-credential-refusal-d.baseline.txt.
set -uo pipefail

PLAN="${1:?usage: sentry-alert-reference-gate.sh <plan.json> <alert-reference.json>}"
REFERENCE="${2:?usage: sentry-alert-reference-gate.sh <plan.json> <alert-reference.json>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ="$REPO_ROOT/tests/scripts/lib/sentry-alert-projection.jq"
# Relative, as the operator would type it from the repo root.
REGEN_CMD="jq -S --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq <plan.json> > apps/web-platform/infra/sentry/alert-reference.json"

if [[ ! -r "$PROJ" ]]; then
  echo "::error::sentry alert reference gate: projection module not readable at '$PROJ'." >&2
  exit 1
fi
# `-s`, not `-r`: an EMPTY plan file is readable and would reach the projection
# as "not a terraform show -json document" — true, but the operator's fix is
# different (the plan step wrote nothing), so name it here.
if [[ ! -s "$PLAN" ]]; then
  echo "::error::sentry alert reference gate: plan JSON not readable or empty at '$PLAN' — the plan step wrote nothing; refusing to report a verdict." >&2
  exit 1
fi
if [[ ! -s "$REFERENCE" ]]; then
  echo "::error::sentry alert reference gate: alert-reference.json not readable or empty at '$REFERENCE'. Regenerate: ${REGEN_CMD}" >&2
  exit 1
fi

# ── Floor 1: the plan projects. Any jq `error` (not a plan/state document, a
# child module, an unknown leaf, an excluded trigger, an unmapped action kind,
# a duplicate name, a sensitive leaf) reaches here as exit 5 with jq's message.
# rc captured on its OWN LINE; `$(...) || …` would test the substitution, and
# a `| head` would report head's status.
planned=$(jq -S -c --arg side tf -f "$PROJ" "$PLAN" 2>"${TMPDIR:-/tmp}/sentry-ref-gate-proj.err")
rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "::error::sentry alert reference gate: projecting the plan failed (jq rc=$rc): $(tr '\n' ' ' <"${TMPDIR:-/tmp}/sentry-ref-gate-proj.err" | cut -c1-600)" >&2
  echo "::error::A projected attribute that is unknown at plan time, or a rule shape the projection does not map, is a provider limitation or a new shape — set the attribute explicitly in the block, or extend tests/scripts/lib/sentry-alert-projection.jq on BOTH sides. Nothing is compared until the plan projects." >&2
  rm -f "${TMPDIR:-/tmp}/sentry-ref-gate-proj.err"
  exit 1
fi
rm -f "${TMPDIR:-/tmp}/sentry-ref-gate-proj.err"

# ── Floor 2: the projection yielded at least one rule. `jq length` on `{}` is
# 0 and `-e` exits 0 on a numeric 0, so the count is read as text and compared.
planned_count=$(jq -r 'if type == "object" then length else "not-an-object" end' <<<"$planned")
rc=$?
if [[ "$rc" -ne 0 || ! "$planned_count" =~ ^[0-9]+$ ]]; then
  echo "::error::sentry alert reference gate: the projection did not yield a name-indexed object (got '${planned_count}')." >&2
  exit 1
fi
if [[ "$planned_count" -eq 0 ]]; then
  echo "::error::sentry alert reference gate: the projection yielded 0 rules from '$PLAN' — a plan with no sentry_alert resources (a targeted or truncated plan document, or the Sentry root without its alert blocks). A gate that compared nothing must not pass." >&2
  exit 1
fi

# ── Floor 3: the reference is a name-indexed projection object (shape floor).
# An API-shaped capture (an ARRAY) fails here, before any comparison.
reference=$(jq -S -c --arg side reference -f "$PROJ" "$REFERENCE" 2>"${TMPDIR:-/tmp}/sentry-ref-gate-ref.err")
rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "::error::sentry alert reference gate: '$REFERENCE' failed the reference-side projection (jq rc=$rc): $(tr '\n' ' ' <"${TMPDIR:-/tmp}/sentry-ref-gate-ref.err" | cut -c1-400)" >&2
  echo "::error::Regenerate: ${REGEN_CMD}" >&2
  rm -f "${TMPDIR:-/tmp}/sentry-ref-gate-ref.err"
  exit 1
fi
rm -f "${TMPDIR:-/tmp}/sentry-ref-gate-ref.err"

if [[ "$planned" == "$reference" ]]; then
  echo "sentry alert reference gate: PASS (${planned_count} rules, plan == alert-reference.json)"
  exit 0
fi

# ── Mismatch: name what moved, at the leaf, then the remedy. ─────────────────
echo "::error::sentry alert reference gate: apps/web-platform/infra/sentry/alert-reference.json does not match the projection of this PR's plan." >&2

diff_report=$(jq -r -n --argjson p "$planned" --argjson r "$reference" '
  ($p | keys) as $pk | ($r | keys) as $rk
  | (($pk - $rk)[] | "ADDED in .tf, missing from reference: \(.)"),
    (($rk - $pk)[] | "REMOVED from .tf, still in reference: \(.)"),
    # Common names: the LEAF paths that differ. `has`, never `// "<absent>"`: a
    # leaf whose value is `false` or `null` is falsy and the `//` form would
    # render a real `false` as absent and hide the exact flip. The walk tests
    # the TYPE, never `paths(scalars)`: `paths(f)` keeps a path only when `f` is
    # truthy on the value, so `scalars` silently DROPS every `false` and `null`
    # leaf — measured: `enabled: false` rendered as `<absent>` (suite row M7).
    ( ($pk - ($pk - $rk))[] as $n
      | def leaves($v): [ ($v | paths(type != "array" and type != "object")) as $path
                          | {k: ($path | map(tostring) | join(".")), v: ($v | getpath($path))} ]
                        | INDEX(.k);
        leaves($p[$n]) as $A | leaves($r[$n]) as $B
      | (($A | keys) + ($B | keys) | unique)[] as $k
      | (if ($A | has($k)) then ($A[$k].v | tojson) else "<absent>" end) as $pv
      | (if ($B | has($k)) then ($B[$k].v | tojson) else "<absent>" end) as $rv
      | select($pv != $rv)
      | "\($n).\($k): planned=\($pv) reference=\($rv)" )
')
rc=$?
if [[ "$rc" -ne 0 || -z "$diff_report" ]]; then
  # Unequal canonical strings but no leaf difference found means the diff
  # itself is broken. Say so rather than printing nothing and exiting 1.
  echo "::error::sentry alert reference gate: the documents differ but the leaf diff produced no lines (jq rc=$rc) — refusing to guess. planned=$(head -c 200 <<<"$planned")… reference=$(head -c 200 <<<"$reference")…" >&2
  exit 1
fi
sed 's/^/  /' <<<"$diff_report" >&2

# A detectorIds-only divergence is the issue-stream detector id moving, not an
# authoring error — the monitor-binding gate owns that invariant.
if ! grep -vE '\.detectorIds(\.[0-9]+)?: ' <<<"$diff_report" | grep -q .; then
  echo "::error::Hint: the ONLY differing leaf is detectorIds — the issue-stream detector id moved (see scripts/sentry-monitor-binding-gate.sh); this is not an authoring error, but the reference still needs regenerating." >&2
fi

echo "::error::Regenerate: ${REGEN_CMD}   (the plan.json is \`terraform show -json <tfplan>\` of the FULL Sentry root; recipe in apps/web-platform/infra/sentry/README.md §Drift detection). Commit the result in this PR." >&2
echo "::error::If this PR also REMOVES a rule, the destroy gate asks for [ack-destroy] next — a stale reference cannot be acked through; it must be regenerated." >&2

# The exact expected document, where a reviewer can fetch it without prod
# credentials: the step summary (collapsed) and a file the workflow uploads as
# an artifact.
expected_pretty=$(jq -S . <<<"$planned")
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '## sentry alert reference gate: FAIL\n\n'
    printf '`apps/web-platform/infra/sentry/alert-reference.json` does not match the projection of this PR'"'"'s plan (%s rules planned).\n\n' "$planned_count"
    printf '```text\n%s\n```\n\n' "$diff_report"
    printf 'Regenerate: `%s`\n\n' "$REGEN_CMD"
    printf '<details><summary>Expected alert-reference.json (%s rules) — copy this file verbatim</summary>\n\n```json\n%s\n```\n\n</details>\n' "$planned_count" "$expected_pretty"
  } >> "$GITHUB_STEP_SUMMARY"
fi
if [[ -n "${RUNNER_TEMP:-}" && -d "${RUNNER_TEMP}" ]]; then
  printf '%s\n' "$expected_pretty" > "${RUNNER_TEMP}/sentry-alert-reference.expected.json"
  echo "::error::The expected document was written to ${RUNNER_TEMP}/sentry-alert-reference.expected.json (uploaded as an artifact by the workflow) and to the step summary." >&2
fi
exit 1
