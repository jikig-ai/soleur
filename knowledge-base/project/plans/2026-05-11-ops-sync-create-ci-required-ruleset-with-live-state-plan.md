---
title: "ops(ci): sync scripts/create-ci-required-ruleset.sh with live ruleset state (R15 follow-up D4)"
type: ops-remediation
classification: code-only
date: 2026-05-11
issue: 3547
branch: feat-one-shot-3547-create-ruleset-sync
requires_cpo_signoff: false
---

# ops(ci): sync `scripts/create-ci-required-ruleset.sh` with live ruleset state

## Overview

`scripts/create-ci-required-ruleset.sh` hard-codes a 3-entry `required_status_checks` array (`test`, `dependency-review`, `e2e`). The live "CI Required" ruleset (#14145388) now has 5 entries: the original three plus `CodeQL` (integration_id `57789`, github-advanced-security) and `skill-security-scan PR gate` (integration_id `15368`, github-actions[bot]) added by #3543 / #3542 (R15 mitigation for the skill-install code-execution gap originating at #2719).

If an operator deletes and re-creates the ruleset using the current script (drift recovery, disaster recovery, or accidental delete via the GitHub UI), `CodeQL` and `skill-security-scan PR gate` silently drop. The R15 mitigation is undone with zero repo-side trace; the only surface that would surface it is the daily audit (`scheduled-ruleset-bypass-audit.yml`, #3544) — but that audit currently only checks `bypass_actors`, not `required_status_checks`. So a cold-create regression is invisible until the next merged skill-install PR loses code-execution containment.

This plan adopts the precedent established by #3555 / #3544 for `bypass_actors`: extract the required_status_checks array into a canonical in-repo JSON file (`scripts/ci-required-ruleset-canonical-required-status-checks.json`), source it from `create-ci-required-ruleset.sh` via `jq --slurpfile`, extend the existing daily audit to diff live required_status_checks against the canonical, and add a post-PUT canonical fast-path to `update-ci-required-ruleset.sh` symmetric to the bypass_actors fast-path. One PR closes the cold-create regression and the same-PUT-cycle drift hole, in the same place a future operator already expects to look.

## User-Brand Impact

- **If this lands broken, the user experiences:** A re-created "CI Required" ruleset that silently omits `CodeQL` and `skill-security-scan PR gate`, allowing a malicious skill-install PR to merge to `main` without the security gate. Any operator who pulls `main` after the malicious skill lands installs the malicious skill on their next `claude` invocation — code execution as the operator user. Same brand-survival class as #2719 / #3542 (one merged skill-install = installable-skill code-execution on every operator).
- **If this leaks, the user's [data / workflow] is exposed via:** Operator workstation compromise (skill-install runs with the operator's shell privileges; reads `~/.ssh`, `~/.aws`, `~/.doppler`, all Soleur credentials). The leak is the data the skill chooses to read, exfiltrate, or use to pivot.
- **Brand-survival threshold:** `single-user incident`

The threshold carries forward from the parent #3542 (R15) / #2719 framing — `create-ci-required-ruleset.sh` is part of the load-bearing R15 defense path, so its silent-drop regression must be weighed on the same axis as the original gate, not on technical-convenience axes. Mitigation in this plan: the canonical JSON extraction makes drop-on-create impossible (the script reads from disk, not from a hand-edited heredoc), and the audit extension closes the post-PUT drift hole symmetrically with the bypass_actors fast-path that already runs daily. `requires_cpo_signoff: false` because the plan does not propose a behavior change at the user-brand-survival boundary — it propagates the existing R15 defense one layer deeper into the create path. The CPO sign-off captured at #3542 plan time covers this.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Codebase reality | Plan response |
|---|---|---|
| "Hard-codes 3 required checks" | Confirmed: `scripts/create-ci-required-ruleset.sh` lines 75-87 hard-code `test`, `dependency-review`, `e2e` with integration_id 15368 each. | Extract to canonical JSON. |
| "Live ruleset has 5 (post #3542 merge)" | Confirmed via `gh api repos/jikig-ai/soleur/rulesets/14145388` at plan time: 5 entries, two integration_ids (15368 ×4, 57789 ×1 for CodeQL). | Canonical JSON must encode both integration_ids; cannot factor to a single constant. |
| "Either (a) hard-code 5 or (b) fetch live state" | The (a)/(b) framing in the issue body omits option (c): extract to canonical JSON, the pattern #3555 already established for bypass_actors and #3544 audits daily. | Choose (c) — same pattern, same canonical-file directory, audit extends in place. |
| Issue body: "(b) chicken-and-egg risk on cold create" | Accurate. The create path runs BEFORE any ruleset exists; a "fetch live" approach cannot bootstrap. | Canonical JSON is the only design that boots cold AND drifts neither forward (new check added → JSON updated → audit catches stale create) nor backward (admin UI edit between PUTs → audit catches). |
| Issue body conjecture: "daily bypass-actors audit could grow a sibling required_status_checks audit, OR (simpler) the audit script just compares the live ruleset against both canonical files" | The two phrasings are the same design under the surface — the audit script reads a second canonical file and emits a second `failure_mode`. Workflow YAML stays single. | Adopt: extend `scripts/audit-ruleset-bypass.sh` to diff both arrays in one run, with two distinct `failure_mode` codes. |
| Implicit assumption: `update-ci-required-ruleset.sh` is unchanged by this work | Not quite. The existing post-PUT canonical fast-path (lines 226-239) compares `bypass_actors` only. The same-PUT-cycle attack on `required_status_checks` (admin renames `e2e` → `e2e-renamed` via UI; next PUT preserves the rename because it reads from live snapshot) is open. | Add a symmetric post-PUT canonical fast-path for `required_status_checks` in `update-ci-required-ruleset.sh`. Same canonical file, same shape of check. |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` for `scripts/create-ci-required-ruleset.sh`, `scripts/update-ci-required-ruleset.sh`, `scripts/audit-ruleset-bypass.sh`, `.github/workflows/scheduled-ruleset-bypass-audit.yml`, `scripts/ci-required-ruleset-canonical-bypass-actors.json`, `scripts/required-checks.txt`, `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`, `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`, `tests/scripts/test-audit-ruleset-bypass.sh`.

Result: None — no open code-review issue touches the files this plan will modify.

## Hypotheses

Not applicable — this is not a network-outage symptom plan. The fix mechanism is fully determined by the codebase precedent (#3555/#3544). The only design dimension is whether to extend the existing audit or fork a sibling audit; the issue body and the trust model both favor extension (one canonical-file directory, one cron job, two failure modes — same shape as `scheduled-github-app-drift-guard.yml` whose 3-output model is mirrored in `audit-ruleset-bypass.sh`).

## Constraints & Invariants

1. **`integration_id` heterogeneity is load-bearing.** The canonical JSON MUST preserve `integration_id: 57789` for `CodeQL` and `integration_id: 15368` for the four github-actions[bot] checks. A naive "factor to a single constant" would silently allow `github-actions[bot]` to spoof a `CodeQL` check-run (per `scripts/required-checks.txt` lines 17-23, the integration_id pin is what prevents the spoof). Tests MUST assert both integration_ids exist in the canonical and that any future hand-edit cannot collapse them.

2. **Cold-create boot path.** `scripts/create-ci-required-ruleset.sh` runs when no ruleset exists. It MUST NOT depend on `gh api repos/.../rulesets/14145388` returning live state. The canonical JSON is the only source of truth at cold-boot.

3. **PUT-replaces-entire-payload semantics carry over.** Per `knowledge-base/project/learnings/2026-04-03-github-ruleset-put-replaces-entire-payload.md`, every PUT MUST include `bypass_actors`, `conditions`, `rules`. This plan adds a second canonical source for the `required_status_checks` slot inside `rules` — `update-ci-required-ruleset.sh` still preserves the entire payload (and now verifies BOTH canonical projections post-PUT).

4. **Audit deterministic-order canonicalization.** Mirror `scripts/lib/canonicalize-bypass-actors.sh`'s `map({context, integration_id}) | sort_by(.context, .integration_id)` projection. GitHub's API may emit fields in any order; without sort_by the audit false-positives on cosmetic reordering. Number-vs-string `integration_id` (e.g., hand-edit accidentally quoting `"15368"`) is intentionally preserved as drift — that IS an attacker signal (string and number are not API-equivalent in the ruleset payload).

5. **Cron schedule unchanged.** Re-using `scheduled-ruleset-bypass-audit.yml` keeps cron at `13 6 * * *` (off-peak, no thundering-herd with `0 6 * * *`). No new workflow file; no second cron entry.

6. **Workflow rename caution.** The workflow file is named `scheduled-ruleset-bypass-audit.yml`. After this plan, it audits BOTH `bypass_actors` AND `required_status_checks`. Renaming to `scheduled-ruleset-canonical-audit.yml` would force a `concurrency:` group update and break any cross-workflow `workflow_run:` dependencies (none exist today, but a rename is a side-track). Decision: keep the filename, update the workflow's `name:` header and `concurrency:` comment block to read "Canonical Ruleset Audit". Defer file rename to a follow-up if anyone asks.

## Architecture

```
scripts/
├── ci-required-ruleset-canonical-bypass-actors.json          (#3555/#3544 — existing)
├── ci-required-ruleset-canonical-required-status-checks.json (NEW — this plan)
├── create-ci-required-ruleset.sh                             (refactored: --slurpfile both)
├── update-ci-required-ruleset.sh                             (extended: symmetric fast-path)
├── audit-ruleset-bypass.sh                                   (extended: diff both arrays)
└── lib/
    ├── canonicalize-bypass-actors.sh                         (existing)
    └── canonicalize-required-status-checks.sh                (NEW — same shape as bypass)

.github/workflows/
└── scheduled-ruleset-bypass-audit.yml                        (sparse-checkout extended)

tests/scripts/
└── test-audit-ruleset-bypass.sh                              (extended: 8 new T-cases)

knowledge-base/engineering/ops/runbooks/
├── ruleset-bypass-drift.md                                   (extended: required_status_checks section)
└── skill-security-scan-required-check.md                     (refreshed: canonical-JSON path)
```

## Implementation Phases

### Phase 0 — Pre-flight (no code)

- [ ] Confirm live ruleset shape via `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks'` — must show 5 entries with integration_ids matching the table below. Plan-time snapshot (2026-05-11):

  | context | integration_id |
  |---|---|
  | `test` | 15368 |
  | `dependency-review` | 15368 |
  | `e2e` | 15368 |
  | `CodeQL` | 57789 |
  | `skill-security-scan PR gate` | 15368 |

- [ ] Confirm `scripts/lib/canonicalize-bypass-actors.sh` exists and pattern is single-`. "$SCRIPT_DIR/lib/..."` source.
- [ ] Confirm `tests/scripts/test-audit-ruleset-bypass.sh` exists and uses the `_run` / `_report` / `_mode` / `_label` / `_detail` helpers — the new tests will follow the same shape.
- [ ] Verify GitHub label `compliance/critical` exists (it's defensively created by the workflow; confirm via `gh label list --limit 200 | grep -E '^compliance/critical\b'`). If absent, no action needed — the workflow re-creates it idempotently.

### Phase 1 — Extract canonical JSON (RED)

**File: `scripts/ci-required-ruleset-canonical-required-status-checks.json` (NEW)**

Write the canonical file verbatim from the Phase 0 snapshot:

```json
[
  {"context": "CodeQL", "integration_id": 57789},
  {"context": "dependency-review", "integration_id": 15368},
  {"context": "e2e", "integration_id": 15368},
  {"context": "skill-security-scan PR gate", "integration_id": 15368},
  {"context": "test", "integration_id": 15368}
]
```

Sorted by `context` so diffs from canonicalized live state read cleanly. Two integration_ids preserved verbatim.

**File: `scripts/lib/canonicalize-required-status-checks.sh` (NEW)**

```bash
# shellcheck shell=bash
# Shared canonical projection for CI Required ruleset required_status_checks arrays.
# Used by scripts/audit-ruleset-bypass.sh and scripts/update-ci-required-ruleset.sh
# (post-PUT fast-path). Both consumers MUST canonicalize through this exact jq
# filter so API-side field reordering does not surface as false drift.
#
# Number-vs-string integration_id IS preserved as drift (a hand-edit that
# quoted "15368" would let github-actions[bot] spoof a check whose ruleset
# entry expects an integer match — that's a real signal).
#
# Ref #3547.

# shellcheck disable=SC2034
CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ='map({context, integration_id}) | sort_by(.context, (.integration_id | tostring))'
```

### Phase 2 — Refactor `create-ci-required-ruleset.sh` (RED → GREEN)

**File: `scripts/create-ci-required-ruleset.sh`**

Replace the heredoc-embedded `required_status_checks` array with a `jq --slurpfile` merge symmetric to the existing `bypass_actors` merge.

Mechanics:

1. Add `CANONICAL_RSC_FILE="${SCRIPT_DIR}/ci-required-ruleset-canonical-required-status-checks.json"` next to the existing `CANONICAL_BYPASS_FILE` line.
2. Add the same pre-flight existence + array-shape check that exists for `CANONICAL_BYPASS_FILE` (lines 27-34) — copy verbatim, swap the variable name.
3. Rewrite the heredoc body to leave `required_status_checks` as a placeholder, then chain two `jq --slurpfile` calls (or one `jq --slurpfile bypass --slurpfile rsc`) to inject both canonical arrays.

```bash
# Skeleton with both arrays as placeholders:
cat > "$skeleton" << 'EOF'
{
  "name": "CI Required",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": []
      }
    }
  ]
}
EOF

# Merge both canonicals in one jq pass.
jq --slurpfile bypass "$CANONICAL_BYPASS_FILE" \
   --slurpfile rsc "$CANONICAL_RSC_FILE" '
  . + {bypass_actors: $bypass[0]}
  | .rules = (.rules | map(
      if .type == "required_status_checks"
      then .parameters.required_status_checks = $rsc[0]
      else . end
    ))
' "$skeleton" > "$payload"
```

The header comment at the top of the script MUST be updated to reflect both canonical files; the existing comment lines 20-26 names only `bypass_actors`. Rewrite to:

> `required_status_checks` AND `bypass_actors` source-of-truth lives in sibling JSON files (`ci-required-ruleset-canonical-required-status-checks.json`, `ci-required-ruleset-canonical-bypass-actors.json`) shared with the daily audit (#3544 + #3547). Editing the arrays here is a workflow violation — update the JSON instead so the audit's canonical reference stays in sync.

Also update lines 4-5 ("adds the `test`, `dependency-review`, and `e2e` status checks") to point to the canonical JSON rather than naming three checks. The script no longer "knows" the contents of the array.

### Phase 3 — Extend `update-ci-required-ruleset.sh` post-PUT fast-path (GREEN)

**File: `scripts/update-ci-required-ruleset.sh`**

After the existing `bypass_actors` fast-path block (lines 226-239), add a symmetric `required_status_checks` fast-path. The trigger condition is `--update on success` — same place. Same `::error::` shape, same `drift=1` flag, same canonical-file existence guard.

```bash
# Audit fast-path (#3547): diff round-tripped required_status_checks against
# the canonical in-repo JSON, not just the pre-mutation snapshot. The PUT API
# copies bypass_actors verbatim from $before, but required_status_checks is
# the field this script intentionally mutates — so the before/after diff
# legitimately reports the new check, hiding any same-PUT-cycle attacker edit
# (admin renames a context via UI between two operator PUTs). Only the
# canonical comparison surfaces that.
# shellcheck source=scripts/lib/canonicalize-required-status-checks.sh
. "${SCRIPT_DIR}/lib/canonicalize-required-status-checks.sh"
CANONICAL_RSC_FILE="${SCRIPT_DIR}/ci-required-ruleset-canonical-required-status-checks.json"
if [[ -f "$CANONICAL_RSC_FILE" ]]; then
  rsc_canonical_norm=$(jq -S "$CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ" "$CANONICAL_RSC_FILE")
  rsc_after_norm=$(jq -S "${rsc_rule_jq}.parameters.required_status_checks | $CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ" "$after")
  if [[ "$rsc_canonical_norm" != "$rsc_after_norm" ]]; then
    echo "::error::required_status_checks after PUT does not match canonical at ${CANONICAL_RSC_FILE}" >&2
    echo "         canonical: ${rsc_canonical_norm}" >&2
    echo "         after PUT: ${rsc_after_norm}" >&2
    echo "         If the check change is intentional, update the canonical JSON FIRST," >&2
    echo "         then re-run; the daily audit reads the same file." >&2
    drift=1
  fi
else
  echo "::warning::canonical RSC file missing at ${CANONICAL_RSC_FILE} — skipping audit fast-path check" >&2
fi
```

**Subtle correctness note:** The script's primary purpose (per its header) is to ADD a new check (`skill-security-scan PR gate`). On the first run of this script after this plan ships, the canonical JSON already names that check (Phase 1 wrote it in). On a hypothetical future run that adds a 6th check (e.g., `disk-io-budget gate`), the operator MUST update the canonical JSON BEFORE running the script — otherwise the post-PUT fast-path will surface drift and exit 2 (per the existing exit-2 convention for "post-PUT integrity drift"). This is the right behavior: it forces the operator to keep the canonical and the live ruleset in lock-step. Document this in the runbook (Phase 6).

**Workflow order for adding a 6th check (post-plan):**

1. Edit `scripts/ci-required-ruleset-canonical-required-status-checks.json` to add the new entry.
2. Edit `scripts/required-checks.txt` to add the new check name.
3. Edit `scripts/update-ci-required-ruleset.sh` to set `NEW_CHECK` to the new context (or generalize via `--check NAME` flag — out of scope for this plan; track as follow-up #SCOPE-OUT-1).
4. Run `update-ci-required-ruleset.sh` per `hr-menu-option-ack-not-prod-write-auth`.

### Phase 4 — Extend `audit-ruleset-bypass.sh` (GREEN)

**File: `scripts/audit-ruleset-bypass.sh`**

Add a second canonical-diff block after the existing bypass_actors block. Use a NEW `failure_mode` code (`required_status_checks_drift`) routed to the SAME label as the bypass drift (`ci/auth-broken`, `compliance/critical`) — same brand-survival class.

Order of operations:

1. Source `lib/canonicalize-required-status-checks.sh` next to the existing `lib/canonicalize-bypass-actors.sh` source.
2. Add `CANONICAL_RSC_FILE="${AUDIT_CANONICAL_RSC_FILE_OVERRIDE:-${SCRIPT_DIR}/ci-required-ruleset-canonical-required-status-checks.json}"` next to the existing `CANONICAL_FILE` (rename `CANONICAL_FILE` → `CANONICAL_BYPASS_FILE` in the same commit; grep both `audit-ruleset-bypass.sh` and `tests/scripts/test-audit-ruleset-bypass.sh` for `CANONICAL_FILE` usage and update everywhere — count of sites at plan time: 4 in audit, 1 in test).
3. After the live fetch is established, run TWO canonical-diff blocks (bypass + rsc) in sequence. Use `record_failure` for each independently — the existing emit-once `record_failure` means whichever drift fires first will be the one reported, but that's correct (operator triage is the same runbook either way, and `failure_detail` names both fields).

   Refinement: actually, the issue body's phrasing — "the audit script just compares the live ruleset against both canonical files" — supports a different emit shape. Two independent diffs, each calling `record_failure` with a distinct `failure_mode` value (`bypass_actors_drift`, `required_status_checks_drift`). The existing first-write-wins behavior means only one fires per run; the SECOND drift would still surface on the next run (after operator remediates the first), so no signal is lost — the workflow's `concurrency: cancel-in-progress: false` and 24h detection window absorb it.

   This matches the bypass code path's existing semantic. No structural change to `record_failure` is needed.

4. Add `failure_mode=required_status_checks_drift` to the workflow YAML's failure-routing case statement (Phase 5).

5. The workflow's sparse-checkout list must add the new canonical file path.

### Phase 5 — Extend the audit workflow YAML (GREEN)

**File: `.github/workflows/scheduled-ruleset-bypass-audit.yml`**

Three edits:

1. **`sparse-checkout` block** (line 57 area) — add `scripts/ci-required-ruleset-canonical-required-status-checks.json` and `scripts/lib/canonicalize-required-status-checks.sh`.

2. **Failure-routing case statement** — wherever the workflow inspects `failure_mode` to choose between `ci/auth-broken` and `ci/guard-broken`, add the new `required_status_checks_drift` mode mapped to `ci/auth-broken` + `compliance/critical` (same as `bypass_actors_drift`).

3. **Workflow `name:` and header comment** — update to reflect the canonical-audit scope, e.g., `name: "Scheduled: Canonical Ruleset Audit (bypass_actors + required_status_checks)"`. Keep the FILE name (`scheduled-ruleset-bypass-audit.yml`) for the reason in Constraint 6.

4. **Comment block (lines 1-29)** — refresh to name both audit surfaces and add `#3547` to the `Ref` line.

### Phase 6 — Tests (GREEN)

**File: `tests/scripts/test-audit-ruleset-bypass.sh`**

Add a parallel set of T-cases for `required_status_checks_drift`. Mirror the existing T1-Tn structure for `bypass_actors`. At minimum:

- **T-rsc-1 (identity):** canonical RSC === live RSC → no drift on either field.
- **T-rsc-2 (drift — missing CodeQL):** canonical has 5 entries, live has 4 (CodeQL stripped) → `failure_mode=required_status_checks_drift`, `failure_label=ci/auth-broken`.
- **T-rsc-3 (drift — wrong integration_id):** canonical has `CodeQL` w/ `integration_id: 57789`, live has `CodeQL` w/ `integration_id: 15368` (the github-actions[bot]-spoof attack) → `failure_mode=required_status_checks_drift`.
- **T-rsc-4 (drift — string-vs-number integration_id):** canonical has `integration_id: 15368` (int), live has `integration_id: "15368"` (string) → MUST drift. Asserts the `(.integration_id | tostring)` projection preserves the int-vs-string signal.
- **T-rsc-5 (drift — extra check):** canonical has 5 entries, live has 6 (admin added a new context via UI without updating canonical) → MUST drift. This is the legitimate-but-uncoordinated-edit case; the audit catches it and forces the operator to update the canonical.
- **T-rsc-6 (no drift on cosmetic reorder):** canonical and live have identical sets but in different order — MUST NOT drift (sort_by canonicalization).
- **T-rsc-7 (canonical file missing):** `AUDIT_CANONICAL_RSC_FILE_OVERRIDE` points to a non-existent file → `failure_mode=canonical_rsc_file_missing`, `failure_label=ci/guard-broken`.
- **T-rsc-8 (canonical file malformed):** `AUDIT_CANONICAL_RSC_FILE_OVERRIDE` points to a non-array JSON → `failure_mode=canonical_rsc_file_malformed`, `failure_label=ci/guard-broken`.
- **T-rsc-9 (independent of bypass drift):** canonical RSC matches, canonical bypass diverges → only `bypass_actors_drift` fires (existing T-case shape). And the symmetric: bypass matches, RSC diverges → only `required_status_checks_drift`. Together they prove the two diffs are independent.

Also add `AUDIT_CANONICAL_RSC_FILE_OVERRIDE` to the documented test-only env vars block in the script header.

**File: `tests/scripts/test-create-ci-required-ruleset.sh` (NEW)**

Defensive: a small test that runs `scripts/create-ci-required-ruleset.sh` with `--dry-run` (the script does NOT have `--dry-run` today; either add one for testability or shim by stubbing `gh api`). The existing `update-ci-required-ruleset.sh` has `--dry-run`; symmetrize on create.

Sub-scope decision: **add `--dry-run` to `scripts/create-ci-required-ruleset.sh`** as part of this plan. It's a 5-line change (early-exit before the POST), and without it Phase 6 has no deterministic way to test the payload synthesis. Tests:

- **T-create-1:** with both canonical files present, `--dry-run` emits a payload whose `required_status_checks` deep-equals the canonical RSC array.
- **T-create-2:** with the canonical RSC file deleted, the script exits 1 with a clear error before any synthesis.
- **T-create-3:** with the canonical RSC file containing non-array JSON, exit 1 with a clear error.
- **T-create-4:** the `bypass_actors` and `required_status_checks` in the dry-run output are independent — modifying the RSC canonical changes only one slot, not the other.

### Phase 7 — Runbook updates

**File: `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`**

Rename the title from "CI Required Ruleset `bypass_actors` Drift" to "CI Required Ruleset Canonical Drift (`bypass_actors` + `required_status_checks`)". Add a top-level section for the new `required_status_checks_drift` triage flow, mirroring the existing bypass section structure:

- "Why this audit exists" — reference #3547 and the cold-create regression.
- "What to do when the issue fires" — read live state, diff vs canonical, decide whether the live state or the canonical is wrong, remediate.
- "When to widen the canonical" — only when adding a new check legitimately (e.g., new CI surface lands). Operator MUST update the canonical in a PR FIRST, then run the corresponding script.

**File: `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`**

Update the cross-reference list at the bottom (or wherever scripts are named) to point to the canonical JSON file as the source-of-truth for the required_status_checks array. The runbook's pre-mutation gates currently verify `scripts/required-checks.txt` contains the new check; add a parallel gate that verifies `scripts/ci-required-ruleset-canonical-required-status-checks.json` does too.

### Phase 8 — Documentation cross-references

**File: `scripts/required-checks.txt`**

Update the comment block (lines 27-32) to reference BOTH canonical files. Today it names only the bypass canonical; after this plan it must point operators at the RSC canonical too, with the same "edit the JSON, not bypass arrays inlined anywhere else" language extended.

Specifically the block:

> bypass_actors for the "CI Required" ruleset are canonicalized in `scripts/ci-required-ruleset-canonical-bypass-actors.json`. Both `scripts/create-ci-required-ruleset.sh` (via jq --slurpfile) and the daily audit (.github/workflows/scheduled-ruleset-bypass-audit.yml, #3544) read from that file as the single source of truth. Edit the JSON, not bypass arrays inlined anywhere else.

becomes (paraphrased):

> bypass_actors AND required_status_checks for the "CI Required" ruleset are canonicalized in sibling JSON files (`scripts/ci-required-ruleset-canonical-{bypass-actors,required-status-checks}.json`). Both `scripts/create-ci-required-ruleset.sh` (via jq --slurpfile) and the daily audit (.github/workflows/scheduled-ruleset-bypass-audit.yml, #3544 + #3547) read from those files as single sources of truth. Edit the JSON, not arrays inlined anywhere else.

## Files to Edit

- `scripts/create-ci-required-ruleset.sh` (extract RSC array via jq --slurpfile; add --dry-run; refresh header comment)
- `scripts/update-ci-required-ruleset.sh` (add symmetric post-PUT canonical fast-path)
- `scripts/audit-ruleset-bypass.sh` (extend to diff RSC; add new failure_mode; rename CANONICAL_FILE → CANONICAL_BYPASS_FILE for clarity)
- `.github/workflows/scheduled-ruleset-bypass-audit.yml` (sparse-checkout, failure-routing, name/header refresh)
- `scripts/required-checks.txt` (comment block refresh)
- `tests/scripts/test-audit-ruleset-bypass.sh` (add 9 T-cases for RSC + 1 cross-independence case; rename `CANONICAL_REAL`)
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` (title rename + new section)
- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` (add canonical-JSON pre-mutation gate)

## Files to Create

- `scripts/ci-required-ruleset-canonical-required-status-checks.json` (5-entry canonical array)
- `scripts/lib/canonicalize-required-status-checks.sh` (shared jq projection)
- `tests/scripts/test-create-ci-required-ruleset.sh` (4 T-cases for create-path)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `scripts/ci-required-ruleset-canonical-required-status-checks.json` exists and deep-equals the live ruleset's `required_status_checks` array as of `gh api repos/jikig-ai/soleur/rulesets/14145388` at PR-creation time. Verified inline in the PR body via the `gh api` snapshot.
- [ ] `scripts/create-ci-required-ruleset.sh --dry-run` emits a payload whose `required_status_checks` array equals the canonical JSON byte-for-byte (after `jq -S` normalization).
- [ ] `scripts/create-ci-required-ruleset.sh` no longer contains a hard-coded `required_status_checks` array. Verified by `grep -nF '"context": "test"' scripts/create-ci-required-ruleset.sh` returning zero hits.
- [ ] `scripts/update-ci-required-ruleset.sh --dry-run` against the live ruleset emits a payload whose `required_status_checks` array equals the canonical (post-PUT it would surface as no-op vs canonical).
- [ ] `bash tests/scripts/test-audit-ruleset-bypass.sh` and `bash tests/scripts/test-create-ci-required-ruleset.sh` exit 0. All T-cases listed above pass.
- [ ] `bash -n scripts/create-ci-required-ruleset.sh scripts/update-ci-required-ruleset.sh scripts/audit-ruleset-bypass.sh scripts/lib/canonicalize-required-status-checks.sh` exits 0 (syntax check).
- [ ] `actionlint .github/workflows/scheduled-ruleset-bypass-audit.yml` exits 0; for embedded shell, extract the relevant `run:` blocks and `bash -c '<snippet>'` them.
- [ ] `yamllint .github/workflows/scheduled-ruleset-bypass-audit.yml` exits 0.
- [ ] `gh label list --limit 200 | grep -E '^(ci/auth-broken|ci/guard-broken|compliance/critical)\b'` returns all three (defensively created by the workflow either way; verify they exist).
- [ ] `grep -rn 'ci-required-ruleset-canonical-required-status-checks' scripts/ .github/workflows/ knowledge-base/engineering/ops/runbooks/ tests/scripts/` returns hits in: `scripts/create-ci-required-ruleset.sh`, `scripts/update-ci-required-ruleset.sh`, `scripts/audit-ruleset-bypass.sh`, `scripts/required-checks.txt`, `.github/workflows/scheduled-ruleset-bypass-audit.yml`, `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`, `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`, and both test files. (Mechanically enforces that the new canonical file is referenced everywhere it's load-bearing.)
- [ ] Audit script's three failure-routing cases (`canonical_file_*`, `github_api_*`, drift) extended to cover RSC-equivalents (`canonical_rsc_file_missing`, `canonical_rsc_file_malformed`, `required_status_checks_drift`).
- [ ] PR body uses `Closes #3547`.

### Post-merge (operator)

- [ ] Manually trigger `.github/workflows/scheduled-ruleset-bypass-audit.yml` via `gh workflow run scheduled-ruleset-bypass-audit.yml`. Poll `gh run list --workflow=scheduled-ruleset-bypass-audit.yml --limit=1 --json databaseId,status,conclusion`. Run MUST complete with `conclusion=success` AND emit no `failure_mode=*_drift` output (the canonical JSON in the PR was derived from live state, so identity-equality is expected).
- [ ] (Optional regression check) Synthetically simulate a cold-create by running `scripts/create-ci-required-ruleset.sh --dry-run` and confirming the printed payload's `required_status_checks` contains all 5 contexts including `CodeQL` (integration_id 57789) and `skill-security-scan PR gate` (integration_id 15368). Compare to the live ruleset via `diff <(jq -S '.rules[0].parameters.required_status_checks' <dry-run-output>) <(gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks' | jq -S '.')` — diff must be empty.

## Test Scenarios

Derive from acceptance criteria:

- **Cold-create regression closed:** Given the live ruleset is deleted, when an operator runs `scripts/create-ci-required-ruleset.sh`, then the resulting ruleset has all 5 required_status_checks with correct integration_ids (CodeQL=57789, others=15368).
- **Same-PUT-cycle attack surfaces:** Given an admin renames the `test` context to `test-spoof` via the GitHub UI, when the daily audit runs, then it emits `failure_mode=required_status_checks_drift` within 24 h. Verified via the T-rsc-2 / T-rsc-3 / T-rsc-4 unit tests against fixture inputs.
- **Integration_id spoof surfaces:** Given an admin (or a bug in a future PR) changes `CodeQL` integration_id from 57789 to 15368 in the live ruleset, when the audit runs, then it drifts (T-rsc-3).
- **Cosmetic reorder is not drift:** Given the GitHub API returns the array in a different order than the canonical, when the audit runs, then it does NOT drift (T-rsc-6).
- **Adding a new check workflow:** Given an operator wants to add a 6th check, when they update the canonical JSON, `required-checks.txt`, and `NEW_CHECK` in `update-ci-required-ruleset.sh`, then `update-ci-required-ruleset.sh` succeeds and the post-PUT canonical fast-path passes. If the operator skips the canonical edit, the post-PUT fast-path fires with exit code 2.
- **Independence of two drift signals:** Given bypass_actors drifts but required_status_checks is clean (or vice-versa), when the audit runs, then exactly one `failure_mode` fires (T-rsc-9).

## Risks

1. **Canonical-file editing slips past code review.** Mitigation: the audit fires daily, so any drift between canonical and live surfaces within 24 h. The canonical file format is small and human-readable; a malicious edit (e.g., dropping CodeQL from the canonical) is visible in PR diff. CODEOWNERS does not currently cover `scripts/ci-required-ruleset-canonical-*.json` — out-of-scope for this plan but worth filing as a follow-up.
2. **Operator workflow friction when adding a 6th check.** The 4-step procedure (canonical → required-checks.txt → script flag → PUT) is more ceremony than the current 2-step (edit script → PUT). Mitigation: documented in the runbook and in the script's header comment. The friction IS the safety — uncoordinated edits are precisely the attack class the canonical closes.
3. **The audit workflow's sparse-checkout adding a new path could break the workflow.** Mitigation: Phase 0 manually-triggered run before merge verifies. Sparse-checkout `cone-mode: false` mode (already in use) accepts arbitrary path lists.
4. **The audit script renames `CANONICAL_FILE` → `CANONICAL_BYPASS_FILE` for clarity.** This is an internal variable name. The TEST-only env var `AUDIT_CANONICAL_FILE_OVERRIDE` is exported and consumed by `tests/scripts/test-audit-ruleset-bypass.sh` — renaming it `AUDIT_CANONICAL_BYPASS_FILE_OVERRIDE` would be cleaner but breaks the test. Decision: keep the env var name (backward compat); rename ONLY the internal variable. The new env var for the RSC canonical is `AUDIT_CANONICAL_RSC_FILE_OVERRIDE`, naming-consistent with the new variable.
5. **GitHub introduces a 3rd integration_id for some future check.** Mitigation: the canonical JSON is array-shaped and accepts arbitrary integration_ids. No code change needed; just update the canonical when the new check lands. The canonicalize jq filter does not reify integration_ids.
6. **`jq --slurpfile` runtime cost in CI.** Negligible — both files are <2 KB. No mitigation needed.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Carried forward; this plan's section is populated.)
- **Cap-coupling caution:** `scripts/required-checks.txt` and the new canonical JSON both enumerate the required checks. They will drift if a future edit touches one but not the other. Mitigation: add a CI lint that fails if the two lists disagree — out-of-scope for this plan, file as follow-up #SCOPE-OUT-2.
- **Test-fixture realism:** Test fixtures for T-rsc-* MUST encode the two integration_ids (15368 and 57789) faithfully. A fixture that flattens to one integration_id would let a real heterogeneity bug slip past the suite. Tests MUST assert both integration_ids are present in at least one fixture.
- **YAML-as-bash trap:** Per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`, never run `bash -n` on an embedded-shell YAML file. Phase 6 prescribes `bash -c '<snippet>'` for the workflow's `run:` blocks.
- **Phase ordering load-bearing:** Per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`, contract-changing edits MUST precede consumer edits. This plan orders: canonical JSON (Phase 1) → consumers (Phases 2-5). Tests (Phase 6) consume both. Runbooks (Phase 7) and docs (Phase 8) consume the consumers. Order is preserved.
- **CLI-verification gate:** `gh api repos/.../rulesets/{id}` (verified at plan time, 2026-05-11) and `gh api repos/.../rulesets/{id} -X PUT --input <file>` (verified usage in `scripts/update-ci-required-ruleset.sh`) are real. `jq --slurpfile` (used at scripts/create-ci-required-ruleset.sh:96, verified to work). `jq -S` for sort-keys canonicalization (used in `audit-ruleset-bypass.sh`, verified). No fabricated tokens.
- **Foundations-PR contract risk (per `2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`):** This PR is NOT a foundations PR — the canonical JSON ships AND every consumer (create, update, audit, tests, runbooks) is wired in the same merge. No downstream "wire it later" PR exists; the contract IS the delivery.

## Domain Review

**Domains relevant:** Engineering (CTO carry-forward), Security (R15 mitigation surface)

### CTO (Engineering)

**Status:** reviewed (carry-forward from #3542 / #3544)
**Assessment:** Pattern-faithful extension of the canonical-JSON precedent established in #3555 (bypass_actors) and audited daily in #3544. No new architectural surface. The two integration_ids (15368 + 57789) constitute a real heterogeneity that the canonical encodes faithfully; tests assert preservation. Operator workflow gets one new step (edit canonical before running update script), justified by the brand-survival threshold.

### Security (R15 mitigation surface)

**Status:** reviewed (carry-forward from #2719 / #3542)
**Assessment:** This plan closes a regression vector in the R15 mitigation (cold-create silent drop of `CodeQL` and `skill-security-scan PR gate`) and adds a same-PUT-cycle drift detector for `required_status_checks` symmetric to the one already running for `bypass_actors`. The brand-survival threshold (single-user incident) carries forward unchanged. No new attack surface introduced; the canonical JSON file is committed to git and code-reviewed like every other source-of-truth.

### Product/UX Gate

Not relevant — infrastructure/tooling change with no user-facing surface. Skipped per the `## Domain Review` heading contract (NONE tier).

## GDPR / Compliance Gate

Skipped — the diff touches `scripts/`, `.github/workflows/`, `knowledge-base/engineering/ops/runbooks/`, `tests/scripts/`. None match the `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex (no schemas, no migrations, no auth flows, no API routes handling PII, no `.sql` files). No regulated-data surface.

## References

- Issue: #3547 (this plan)
- R15 mitigation parent: #3542, PR #3543, origin #2719
- Canonical-bypass precedent: #3555, daily audit #3544
- CodeQL coverage audit: #3545
- lint-bot-statuses runbook: #3546
- PUT-replaces semantics: `knowledge-base/project/learnings/2026-04-03-github-ruleset-put-replaces-entire-payload.md`
- Heterogeneous integration_id rationale: `scripts/required-checks.txt` lines 17-23
- Pattern source files:
  - `scripts/ci-required-ruleset-canonical-bypass-actors.json` (canonical JSON shape)
  - `scripts/lib/canonicalize-bypass-actors.sh` (jq projection shape)
  - `scripts/audit-ruleset-bypass.sh` (failure-routing shape)
  - `tests/scripts/test-audit-ruleset-bypass.sh` (test harness shape)
