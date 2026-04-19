# fix(web-platform): verify and close CodeQL issue #2368 (already remediated by #2417)

**Date:** 2026-04-19
**Issue:** #2368
**Branch:** `feat-one-shot-codeql-2368`
**Worktree:** `.worktrees/feat-one-shot-codeql-2368/`
**Type:** verify-and-close (no production code changes expected)

## Overview

Issue #2368 asks to triage and remediate 9 pre-existing CodeQL alerts in `apps/web-platform/*` (4 critical, 5 high/medium). **All 9 alerts are already in the `dismissed` state**, remediated by PR #2416 (issue #2417, closed 2026-04-16) which dismissed 21 false-positive CodeQL alerts and added CodeQL as a required CI check. PR #2421 followed up by switching CodeQL threat model from `remote_and_local` to `remote` to reduce false-positive volume.

The plan is therefore a **verification + close** workflow, not a remediation. We will:

1. Map each of the 9 alerts named in #2368 to its current GitHub Code Scanning alert number and confirm `state == "dismissed"` with a documented `dismissed_reason` and `dismissed_comment`.
2. Verify there are zero open critical/high CodeQL alerts in `apps/web-platform/*` on `main`.
3. Post a verification comment on #2368 with the alert→state table and close the issue with `Closes #2368` on the verification PR.
4. Capture a learning: **issues filed before checking the security alerts API for active state** drift into duplicate work. Add a workflow gate to the security-triage skill family.

**No application code changes.** The single committed artifact beyond `knowledge-base/` is the verification evidence file under `knowledge-base/project/specs/feat-one-shot-codeql-2368/`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue #2368) | Reality (verified 2026-04-19 via `gh api /repos/jikig-ai/soleur/code-scanning/alerts`) | Plan response |
|---|---|---|
| 9 CodeQL alerts open in `apps/web-platform/*`, 4 critical | All 9 alerts named in issue body are `state=dismissed`. Zero open critical or high alerts in the entire repo on main. | Skip remediation. Verify and close. |
| "Per the issue: review each alert in the GitHub Security UI, dismiss with space-separated reason strings" | Already dismissed in #2416 (2026-04-16) using exactly that pattern. Comments cite specific defenses (env-var URLs, symlink guards, sandbox containment). | No re-dismissal needed; record the existing comments as evidence. |
| "File targeted fixes for real issues (SSRF in github-api.ts, path-injection in sandbox.ts, resource-exhaustion in ws-handler.ts, etc.)" | The 2026-04-16 brainstorm classified all of these as false positives with documented per-alert defense (`knowledge-base/project/brainstorms/2026-04-16-security-scanning-alerts-brainstorm.md`). CTO domain leader endorsed API-only dismissal. | Do not re-litigate the false-positive determination unless code in those files has materially changed since 2026-04-16. Spot-check via git log. |
| Issue file path `apps/web-platform/server/kb-reader.ts:366` | Closest dismissed alert is #100 (line 405). Source file was edited between issue filing (2026-04-16 per #2346 CodeQL run) and now; line numbers drift. | Map by `(rule_id, file)` not by line number. CodeQL re-runs would have created a new alert if the rule re-fired. |

**No production-code claim from the issue survives reconciliation.** The plan reduces to verification.

## Alert Inventory

The 9 alerts named in #2368, with their current state pulled from `/repos/jikig-ai/soleur/code-scanning/alerts`:

| # | Issue file:line | Current alert # | Rule | Severity | State | Reason |
|---|---|---|---|---|---|---|
| 1 | `app/api/kb/upload/route.ts:207` | #89 (line 205) | `js/http-to-file-access` | medium | dismissed | false positive |
| 2 | `server/github-api.ts:64` | #92 | `js/request-forgery` | critical | dismissed | false positive |
| 3 | `server/kb-reader.ts:366` | #100 (line 405) | `js/file-system-race` | high | dismissed | false positive |
| 4 | `server/kb-route-helpers.ts:170` | #96 (line 258) | `js/http-to-file-access` | medium | dismissed | false positive |
| 5 | `server/sandbox.ts:66` | #93 | `js/path-injection` | high | dismissed | false positive |
| 6 | `server/ws-handler.ts:148` | #88 (line 180) | `js/resource-exhaustion` | high | dismissed | false positive |
| 7 | `server/ws-handler.ts:227` | #95 (line 259) | `js/resource-exhaustion` | high | dismissed | false positive |
| 8 | `test/fixtures/qa-auth.ts:42` | #90 | `js/request-forgery` | critical | dismissed | used in tests |
| 9 | `test/workspace.test.ts:38,41` | #102, #103 | `js/path-injection` | high | dismissed | used in tests |

Each dismissal carries a per-alert `dismissed_comment` (from #2416) explaining the specific defense. The verification step prints these comments into the close-out report.

## Why This Plan Is Right-Sized

This is **MINIMAL** detail level. The implementation is one verification script + one PR comment + close. Larger templates would invent work.

- **Risk**: Low. No code changes. Worst case: a re-run finds a NEW alert in one of these files that the issue did not name → spin up a separate fix issue. We pre-emptively detect this in Phase 2.
- **Reversibility**: Trivial. Reopen the issue if verification surfaces an active alert.
- **Audience**: One operator (the worktree's `/soleur:work` runner). The plan doubles as the runbook.

## Implementation Phases

### Phase 1 — Verification Sweep (≤ 10 min)

**Goal:** Produce machine-checked evidence that every alert listed in #2368 is currently dismissed AND that no NEW critical/high alert has appeared in those same files since the 2026-04-16 dismissal.

1. Pull all CodeQL alerts (states: `open`, `dismissed`, `fixed`):

    ```bash
    gh api '/repos/jikig-ai/soleur/code-scanning/alerts?per_page=100' --paginate \
      > knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json
    ```

2. Generate the verification report (`verify.sh` lives in the spec dir; not committed, just run inline):

    ```bash
    jq -r '
      [.[]
       | select(.most_recent_instance.location.path | startswith("apps/web-platform/"))
       | {number, rule: .rule.id, severity: .rule.security_severity_level,
          file: .most_recent_instance.location.path,
          line: .most_recent_instance.location.start_line,
          state, dismissed_reason, dismissed_comment}]
      | sort_by(.number)
    ' knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json \
      > knowledge-base/project/specs/feat-one-shot-codeql-2368/web-platform-alerts.json
    ```

3. **Hard assertion** (must exit 0):

    ```bash
    open_high_critical=$(jq '
      [.[]
       | select(.most_recent_instance.location.path | startswith("apps/web-platform/"))
       | select(.state == "open")
       | select(.rule.security_severity_level == "high"
                or .rule.security_severity_level == "critical")
      ] | length
    ' knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json)
    if [[ "$open_high_critical" -ne 0 ]]; then
      echo "ABORT: $open_high_critical open high/critical alerts in apps/web-platform/* — issue #2368 is NOT resolved." >&2
      exit 1
    fi
    ```

    If this exits non-zero, **stop the plan** and convert to remediation work — the plan's premise is broken. (See AGENTS.md `hr-when-a-command-exits-non-zero-or-prints`.)

4. Confirm each of the 9 issue-named alerts has a corresponding dismissed entry. Use the inventory table above as the expected manifest. Any miss → stop and re-triage.

### Phase 2 — Code-Drift Spot Check (≤ 5 min)

**Goal:** Catch the case where source code at the named locations has materially changed since 2026-04-16 (the dismissal anchor). If the underlying defense was removed, CodeQL would create a new alert — Phase 1 already detects that. This phase is a defensive secondary check.

1. For each of the 9 source files, run:

    ```bash
    git log --since=2026-04-16 --oneline -- apps/web-platform/server/github-api.ts \
      apps/web-platform/server/sandbox.ts apps/web-platform/server/ws-handler.ts \
      apps/web-platform/server/kb-reader.ts apps/web-platform/server/kb-route-helpers.ts \
      apps/web-platform/app/api/kb/upload/route.ts \
      apps/web-platform/test/fixtures/qa-auth.ts apps/web-platform/test/workspace.test.ts
    ```

2. If any file has commits, eyeball-diff those commits for changes to the **specific defense** named in the corresponding `dismissed_comment` (env-var URL allowlist, symlink guard, rate-limit unref, `randomCredentialPath()` helper, etc.). Most likely outcome: no commits or unrelated commits → no action.

3. Record outcome in the verification evidence file.

### Phase 3 — Verification Evidence + Close-Out (≤ 5 min)

1. Write `knowledge-base/project/specs/feat-one-shot-codeql-2368/verification.md` containing:
    - The Phase 1 alert-state table (rendered from `web-platform-alerts.json`).
    - The Phase 2 drift summary (commit list per file, "no defensive regression observed").
    - A pointer to PR #2416 and the 2026-04-16 brainstorm.
    - Date, branch, and the assertion exit codes.

2. Open a **doc-only** PR with the verification artifact + this plan + the workflow learning (see Phase 4). PR body uses `Closes #2368` so merge auto-closes the issue.

3. PR labels: `type/security`, `domain/engineering`, `app:web-platform`. No semver label needed (no app code change).

### Phase 4 — Workflow Learning (≤ 10 min)

This issue cost a planning cycle because nobody re-checked the alerts API before filing. Capture the gate.

1. Write `knowledge-base/project/learnings/2026-04-19-codeql-issue-pre-filing-state-check.md` with:
    - **Symptom**: Issue #2368 filed 2026-04-16 (after PR #2346 CI surfaced "9 new alerts"), but those alerts had been dismissed in PR #2416 the same day. Filing happened before reading the alerts API → the issue commissioned redundant work.
    - **Root cause**: The "CodeQL surfaced N alerts on the PR" signal in CI does not check whether those alerts are `state=open` at issue-filing time. PR-scoped checks can show pre-existing alerts that are already dismissed on `main`.
    - **Prevention** (chosen): Add a one-line check to `plugins/soleur/skills/triage/SKILL.md` (or wherever security issues are filed): before filing a CodeQL-derived issue, run `gh api '/repos/:owner/:repo/code-scanning/alerts?state=open&per_page=100' --paginate --jq '.[].number'` and only file if the alert numbers from the CI failure intersect the live open set.
    - **Why a learning vs. an AGENTS.md rule**: Triage frequency is low (~weekly); the gate belongs in the triage skill where it fires every time, not in the per-turn AGENTS.md context. (Per `wg-when-a-workflow-gap-causes-a-mistake-fix`: edit the skill, not just the learning — the skill edit is the fix; the learning is the audit trail.)

2. Edit `plugins/soleur/skills/triage/SKILL.md` (or the closest applicable triage skill) to add the pre-filing alerts-API check as a numbered step. **Decision deferred to Phase 4 GREEN**: locate the right skill at implementation time (could be `triage`, `fix-issue`, or the CodeQL-to-issues workflow under `.github/workflows/`).

3. If the gap turns out to be in the `.github/workflows/codeql-*.yml` automation (not a skill), file a separate issue with the precise workflow file and a reproduction. Do NOT inline the workflow fix in this PR — keep the PR scope to verification + learning + skill edit.

## Files to Edit

- `plugins/soleur/skills/triage/SKILL.md` — add pre-filing alerts-API state check (Phase 4 step 2; exact path TBD at GREEN time, may be `fix-issue` or a workflow file instead).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json` — raw API snapshot (Phase 1).
- `knowledge-base/project/specs/feat-one-shot-codeql-2368/web-platform-alerts.json` — filtered to web-platform paths (Phase 1).
- `knowledge-base/project/specs/feat-one-shot-codeql-2368/verification.md` — human-readable evidence (Phase 3).
- `knowledge-base/project/learnings/2026-04-19-codeql-issue-pre-filing-state-check.md` — workflow learning (Phase 4).
- `knowledge-base/project/plans/2026-04-19-fix-verify-and-close-codeql-issue-2368-plan.md` — this file.
- `knowledge-base/project/specs/feat-one-shot-codeql-2368/tasks.md` — derived task breakdown.

**Mechanical UX-Gate trigger check:** No file path matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. UX gate does not fire.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` then for each planned file path scanned bodies via standalone `jq --arg path '<path>' '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'`.

Files checked:

- `plugins/soleur/skills/triage/SKILL.md` — none.
- `knowledge-base/project/specs/feat-one-shot-codeql-2368/*.json|md` — none (new files).
- `knowledge-base/project/learnings/2026-04-19-codeql-issue-pre-filing-state-check.md` — none (new file).

**Result: None.** No open code-review issues touch the files this plan modifies.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 1 hard assertion exits 0 (zero open high/critical alerts in `apps/web-platform/*`).
- [ ] All 9 alerts named in #2368 are present in `web-platform-alerts.json` with `state == "dismissed"` and a non-null `dismissed_reason` from the AGENTS.md `hr-github-api-endpoints-with-enum` allowlist (`"false positive"` or `"used in tests"`).
- [ ] `verification.md` includes the alert-state table, the drift summary, and links to PR #2416 and the 2026-04-16 brainstorm.
- [ ] Workflow learning written and the gate applied to the relevant skill (or follow-up issue filed if the gap is in CI workflows, not a skill).
- [ ] PR body contains `Closes #2368`.
- [ ] Markdownlint passes on changed `.md` files (`npx markdownlint-cli2 --fix <changed-md-files>`).

### Post-merge (operator)

- [ ] Issue #2368 auto-closes on merge.
- [ ] `gh issue view 2368 --json state` returns `CLOSED`.
- [ ] CodeQL workflow on the next PR continues to gate on critical/high (sanity check via `gh run list --workflow=codeql.yml --limit 1`).

## Test Scenarios

- **Pre-existing-alert-still-dismissed (happy path):** Run Phase 1; assertion exits 0; verification.md generated.
- **New-alert-appeared (abort path):** Inject a synthetic alert (do not actually do this — describe behavior). Phase 1 assertion exits 1; plan halts; operator opens a separate remediation issue.
- **Defense-removed (drift path):** If Phase 2 finds a commit that removed (e.g.) `URL_ALLOWLIST` from `github-api.ts`, the corresponding alert would already have re-fired and Phase 1 would catch it. Phase 2 is the secondary safety net.

## Domain Review

**Domains relevant:** Engineering.

### Engineering (CTO)

**Status:** carried forward from `2026-04-16-security-scanning-alerts-brainstorm.md` Domain Assessments.
**Assessment:** CTO previously confirmed all 9 alerts as false positives, endorsed API-only dismissal, and recommended switching CodeQL threat model from `remote_and_local` to `remote` (delivered in #2421). No architectural change required. The verify-and-close plan is consistent with the CTO's stance.

**No new specialists required.** No Product/UX impact (no user-facing surface). No cross-domain implications (no marketing, legal, finance, ops touchpoints).

## Risks

- **Risk:** A NEW critical alert lands between Phase 1 snapshot and PR merge.
    - **Mitigation:** CI re-runs CodeQL on the verification PR; the required CodeQL check (added in #2416) blocks merge if a new critical surfaces.
- **Risk:** The 9 alert numbers in the plan inventory are stale by the time `/soleur:work` runs (e.g., GitHub renumbered or de-duplicated).
    - **Mitigation:** Phase 1 reproduces the snapshot live. The inventory is documentation; the assertion is the source of truth.
- **Risk:** The chosen "right skill" for the workflow learning (Phase 4 step 2) does not exist or is the wrong one.
    - **Mitigation:** GREEN-time decision; if no skill is the right home, file a separate workflow-improvement issue and link from the learning. **Do not** force-fit the gate into an unrelated skill.

## Non-Goals

- Changing CodeQL configuration (already done in #2421).
- Re-litigating any of the 9 false-positive determinations.
- Adding inline CodeQL suppression comments (rejected in #2417 design).
- Adding new SAST tools (Semgrep already added in #2476).
- Touching `apps/web-platform/` source code.

**Deferred items requiring tracking issues:** None. Every "non-goal" above is either already shipped or explicitly out of scope with no future re-evaluation criteria.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Re-dismiss all 9 alerts via `gh api PATCH` | Already dismissed; would be a no-op or reset the dismissal audit trail. |
| Open per-alert PRs to "fix" each false positive in code | False-positive determination already accepted by CTO; code changes would be cargo-culting. |
| Close #2368 with a single comment, no PR | Loses the workflow learning + skill edit. The PR is the carrier for the gate that prevents recurrence. |
| Convert #2368 into a tracking issue for "audit CodeQL pre-filing process" | Awkward repurposing; the new learning is cleaner and the issue genuinely is "verify the 9 alerts," which we will do. |

## Notes on Pipeline Mode

This plan is being authored inside `/soleur:one-shot`. Auto-mode is active. `/soleur:work` will execute Phases 1–4 without further user prompts unless an assertion fails.

If Phase 1 aborts: stop, post the failure on #2368, and switch to a remediation plan. Do **not** silently swallow.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-19-fix-verify-and-close-codeql-issue-2368-plan.md. Branch: feat-one-shot-codeql-2368. Worktree: .worktrees/feat-one-shot-codeql-2368/. Issue: #2368. Plan reviewed, implementation next.
```
