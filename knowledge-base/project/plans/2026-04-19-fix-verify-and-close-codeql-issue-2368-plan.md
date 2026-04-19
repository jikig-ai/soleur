# fix(web-platform): verify and close CodeQL issue #2368 (already remediated by #2417)

**Date:** 2026-04-19
**Issue:** #2368
**Branch:** `feat-one-shot-codeql-2368`
**Worktree:** `.worktrees/feat-one-shot-codeql-2368/`
**Type:** verify-and-close (no production code changes expected)

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** 5 (Overview, Workflow Learning, Research Insights, Risks, Files to Edit)
**Live verifications performed:**

- `gh pr view 2416 --json mergedAt,mergeCommit` → merged 2026-04-16T11:14:55Z, mergeCommit `dd36190573e0ae84c62b1dcb100c19eab29868a3`.
- `gh pr view 2421 --json mergedAt` → merged 2026-04-16T11:42:50Z (threat-model switch follow-up).
- `gh issue view 2368 --json createdAt` → 2026-04-15T17:22:29Z.
- `gh pr view 2346 --json mergedAt` → 2026-04-15T17:25:09Z.
- `gh api '/repos/jikig-ai/soleur/code-scanning/alerts?state=open&severity=critical'` → length 0; same for `high`.
- `find knowledge-base/project/learnings -name "*codeql*"` → 4 prior CodeQL learnings (2026-04-10, 2026-04-13 ×3) plus the brainstorm dated 2026-04-16.
- `cat .github/workflows/codeql-to-issues.yml` → workflow already filters `state=open` (line 30) before issuing; the bug is NOT in this filter.

### Key Improvements (vs. initial draft)

1. **Root cause corrected.** Initial plan said "issue filed before checking alerts API." Live timeline check proves #2368 was filed 2 minutes BEFORE PR #2346 merged and 18 hours BEFORE the bulk dismissal PR #2416. The issue was legitimate at filing time. The actual gap is **post-bulk-dismissal orphan audit**: when a PR dismisses N alerts, recently-filed CodeQL-derived issues become orphans and must be auto-closed.
2. **Phase 4 retargeted.** The `codeql-to-issues.yml` workflow already filters `state=open` (verified at line 30). The skill edit therefore lands NOT in a pre-filing gate but in a **post-dismissal sweep** added to that same workflow (or a sibling), which after every bulk-dismiss event scans recent `type/security` issues whose body contains a now-dismissed alert URL/number and auto-closes them with a pointer to the dismissing PR.
3. **Drift mapping precision.** Plan now matches alerts by `(rule_id, file)` AND distance-of-line tolerance ≤ 50 lines, not exact line. Live data shows several alert lines drifted (kb-reader.ts:366→405; ws-handler.ts:148→180, :227→259) due to refactors between PR-scan time and dismissal time.
4. **Dismissed-reason audit.** Confirmed every one of the 9 alerts uses an AGENTS.md `hr-github-api-endpoints-with-enum`-compliant value (`"false positive"` or `"used in tests"`). Recorded the `dismissed_comment` excerpts so verification.md doesn't need to re-fetch them at GREEN time.
5. **Learning category corrected.** Filed under `best-practices/` (workflow gap), not `bug-fixes/` (no bug shipped).

### New Considerations Discovered

- **CI ordering matters.** The CodeQL check on PR #2346 surfaced 9 "new" alerts that were really pre-existing on main; this is GitHub's PR-scoped re-scan behavior, not a bug. The right gate is on the human (don't file a triage issue from a PR-scoped CodeQL summary without cross-checking `state=open&ref=refs/heads/main`), but the more reliable gate is automated post-dismissal sweep.
- **`codeql-to-issues.yml` does the right thing already.** It uses `gh search issues` for dedup AND filters `state=open`. The orphan window in #2368's case is the human-triage path, not the auto-issue path.
- **No production-code changes survive review.** The 2026-04-16 brainstorm + CTO assessment are authoritative; re-litigating would be a workflow violation per `rf-when-a-reviewer-or-user-says-to-keep-a` (CTO endorsed API-only dismissal).

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

### Phase 4 — Workflow Learning + Skill Edit (≤ 15 min)

**Corrected root cause** (verified via timeline):

- 2026-04-15 13:25 UTC — PR #2346 created.
- 2026-04-15 17:22 UTC — Issue #2368 filed (CodeQL on PR #2346 reported 9 new alerts).
- 2026-04-15 17:25 UTC — PR #2346 merged (3 minutes after #2368 filed; expected race).
- 2026-04-16 11:14 UTC — PR #2416 merged: bulk-dismissed all 9 alerts as false positives + tests-only.
- 2026-04-16 11:42 UTC — PR #2421 merged: switched CodeQL threat model to `remote` only.

Issue #2368 was a **legitimate filing at filing time**. It became an orphan when PR #2416 dismissed the alerts the next day. The gap is therefore **not** a pre-filing check; it is a **post-dismissal orphan sweep**: when a PR dismisses CodeQL alerts in bulk, any open `type/security` issue whose body references those alert numbers (or files+rules) becomes redundant work and should be auto-closed with a pointer to the dismissing PR.

1. **Locate the right home.** The candidates and ranking:
    - **Best fit:** `.github/workflows/codeql-to-issues.yml` already runs daily (`cron: "0 6 * * *"`) and has `gh search issues` dedup logic. Add a second job (`close-orphans`) that, for every open issue with the `sec: CodeQL alert #N — ...` title pattern, fetches alert N's current `state` and `dismissed_at`, and if `state == "dismissed"` posts a close-out comment + `gh issue close`. This catches both auto-created issues (from this same workflow) AND human-filed issues like #2368, since both follow the `sec: CodeQL alert #N` title convention OR cite the alert number in the body.
    - **Secondary fit:** `plugins/soleur/skills/triage/SKILL.md` — add a triage-time check that any `type/security` issue's referenced alert number is `state=open` before commissioning work. Lower priority because triage is the human path; the workflow handles the bot path AND retroactively catches stale human-filed issues.
    - **Out of scope here:** `plugins/soleur/skills/fix-issue/`, `plugins/soleur/skills/one-shot/` — these consume issues, they don't audit them.

2. **Decision (GREEN-time):** Make the workflow edit the **primary** fix and the triage skill note the **secondary** fix. If the workflow edit becomes large enough to need its own PR (more than ~30 lines added to `codeql-to-issues.yml`, or a new sibling workflow file), file a separate issue and link from this PR's verification.md. Otherwise inline both.

3. **Workflow edit sketch** (do not implement until GREEN — sketch only for plan review):

    ```yaml
    # .github/workflows/codeql-to-issues.yml — new job
    close-orphans:
      runs-on: ubuntu-latest
      timeout-minutes: 5
      steps:
        - name: Close orphan CodeQL issues
          env:
            GH_TOKEN: ${{ github.token }}
            GH_REPO: ${{ github.repository }}
          run: |
            # Find every open issue mentioning a CodeQL alert number
            gh issue list --state open --label "type/security" \
              --json number,title,body --limit 200 > /tmp/sec-issues.json
            jq -c '.[]' /tmp/sec-issues.json | while IFS= read -r issue; do
              ISSUE=$(echo "$issue" | jq -r '.number')
              # Extract alert numbers from title or body (#NNN pattern after "alert")
              ALERTS=$(echo "$issue" | jq -r '.title + "\n" + .body' \
                | grep -oE 'alert #?[0-9]+' | grep -oE '[0-9]+' | sort -u)
              [ -z "$ALERTS" ] && continue
              ALL_DISMISSED=1
              REASONS=""
              for AN in $ALERTS; do
                STATE=$(gh api "/repos/${GH_REPO}/code-scanning/alerts/${AN}" \
                  --jq '.state' 2>/dev/null) || { ALL_DISMISSED=0; break; }
                [ "$STATE" != "dismissed" ] && { ALL_DISMISSED=0; break; }
                REASONS="${REASONS}- alert #${AN}: dismissed\n"
              done
              if [ "$ALL_DISMISSED" -eq 1 ]; then
                printf "All referenced CodeQL alerts are now dismissed.\n\n%b\nClosing as resolved by dismissal." "$REASONS" \
                  | gh issue comment "$ISSUE" --body-file -
                gh issue close "$ISSUE" --reason completed
              fi
            done
    ```

    Per AGENTS.md `hr-in-github-actions-run-blocks-never-use`: heredoc-free shell block, single-quote outer YAML, all multi-line content via `printf` to a pipe. Per `cq-ci-steps-polling-json-endpoints-under`: every `jq -r` against an HTTP body is wrapped (we use `--jq` server-side here so the body is never inlined).

4. **Triage-skill edit (secondary, smaller):** add one bullet to `plugins/soleur/skills/triage/SKILL.md` near the existing security-triage prose: "Before commissioning work on a CodeQL-derived issue, run `gh api '/repos/:owner/:repo/code-scanning/alerts/<N>' --jq .state`. If `dismissed`, close the issue with a link to the dismissing PR." Re-read the full SKILL.md before editing per `hr-always-read-a-file-before-editing-it`.

5. **Learning file:** `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`. Frontmatter: `category: best-practices`, `tags: [codeql, github-actions, triage, automation]`, `symptom: "Issue filed against pre-existing CodeQL alerts that were dismissed shortly after"`, `root_cause: "No automated audit ties open type/security issues back to alert state changes"`. Body: timeline (above), the workflow sketch, why this is best-practices not bug-fixes (no shipped bug; lost ~30 min of planning time).

6. **Per AGENTS.md `wg-when-fixing-a-workflow-gates-detection`:** retroactively apply the gate to the case that exposed it — close issue #2368 itself via the `Closes #2368` PR body in this PR. The workflow + skill edits prevent recurrence; the close on this PR is the retroactive remediation.

7. **Per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies`:** after PR merges, manually trigger the new `close-orphans` job (`gh workflow run codeql-to-issues.yml`), poll until complete, investigate failures. Add this to post-merge acceptance.

## Files to Edit

- `.github/workflows/codeql-to-issues.yml` — add `close-orphans` job (Phase 4 primary).
- `plugins/soleur/skills/triage/SKILL.md` — add CodeQL-derived-issue alert-state precheck bullet (Phase 4 secondary). Re-read full file before editing per `hr-always-read-a-file-before-editing-it`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json` — raw API snapshot (Phase 1).
- `knowledge-base/project/specs/feat-one-shot-codeql-2368/web-platform-alerts.json` — filtered to web-platform paths (Phase 1).
- `knowledge-base/project/specs/feat-one-shot-codeql-2368/verification.md` — human-readable evidence (Phase 3).
- `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md` — workflow learning (Phase 4 step 5; final dated filename chosen at write-time per the plan-deepen sharp edge "Do not prescribe exact learning filenames with dates in tasks.md" — date is approved here in the plan because the plan itself is dated 2026-04-19 and lands in the same commit).
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
- [ ] All 9 alerts named in #2368 are present in `web-platform-alerts.json` with `state == "dismissed"` and a `dismissed_reason` from the AGENTS.md `hr-github-api-endpoints-with-enum` allowlist (`"false positive"` or `"used in tests"`).
- [ ] `verification.md` includes the alert-state table, the drift summary, and links to PR #2416 (mergeCommit `dd36190573e0ae84c62b1dcb100c19eab29868a3`) and the 2026-04-16 brainstorm (`knowledge-base/project/brainstorms/2026-04-16-security-scanning-alerts-brainstorm.md`).
- [ ] `.github/workflows/codeql-to-issues.yml` has `close-orphans` job; YAML validates locally via `yq eval '.' .github/workflows/codeql-to-issues.yml > /dev/null` (or equivalent).
- [ ] `plugins/soleur/skills/triage/SKILL.md` has the CodeQL-alert-state precheck bullet.
- [ ] Learning file present at `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`.
- [ ] PR body contains `Closes #2368` (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] Markdownlint passes on changed `.md` files (`npx markdownlint-cli2 --fix <changed-md-files-only>` per `cq-markdownlint-fix-target-specific-paths`).
- [ ] Labels applied: `type/security`, `domain/engineering`, `app:web-platform`. Verify with `gh label list --limit 100 | grep -i security` first per `cq-gh-issue-label-verify-name`.

### Post-merge (operator)

- [ ] Issue #2368 auto-closes on merge.
- [ ] `gh issue view 2368 --json state` returns `CLOSED`.
- [ ] Trigger the new workflow job: `gh workflow run codeql-to-issues.yml`. Poll via `gh run list --workflow=codeql-to-issues.yml --limit 1 --json status,conclusion` per `wg-after-merging-a-pr-that-adds-or-modifies` and `hr-never-use-sleep-2-seconds-in-foreground` (use Monitor tool or `run_in_background`).
- [ ] CodeQL gate on the next PR continues to block on critical/high (sanity check via `gh run list --workflow=codeql.yml --limit 1`).
- [ ] No regression: `gh api '/repos/:owner/:repo/code-scanning/alerts?state=open&severity=critical' --jq length` returns 0.

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
- **Risk:** The new `close-orphans` workflow job auto-closes legitimate open issues that mention an alert number incidentally (e.g., a forensic post-mortem that says "alert #92 was the canary for X").
  - **Mitigation:** The job's title-or-body extractor matches `alert #?[0-9]+` only after the literal word `alert`; a forensic doc that says "alert #92" would still be auto-closed. Add a label-based opt-out: skip issues with the `keep-open` label (project convention). Document this in the workflow comment block. If false-close happens once, add the label and reopen — the action is reversible.
- **Risk:** The new workflow job hits GitHub API rate limits when the open security-issue list grows (per-issue alert lookup is `O(issues × alerts)`).
  - **Mitigation:** The query is bounded by `--label "type/security" --limit 200`. Per-alert lookup is one `gh api` call each; ~200 calls/day is well below the 5000/hr authenticated rate limit. If this changes, batch via the list-alerts endpoint and join client-side.
- **Risk:** Adding a job to `codeql-to-issues.yml` interacts badly with the existing `check-alerts` job (e.g., race on the same issue).
  - **Mitigation:** Sequence them via `needs:` so `close-orphans` runs after `check-alerts` completes. They operate on different sets (create vs. close), so there is no real conflict, but ordering is cheap insurance.
- **Risk:** Workflow YAML edit triggers `hr-in-github-actions-run-blocks-never-use` (heredoc-in-run-block).
  - **Mitigation:** Use `printf "...\n%b" "$VAR" | gh issue comment ... --body-file -` per the rule's prescribed pattern. The Phase 4 sketch already follows this. Lint locally with `actionlint .github/workflows/codeql-to-issues.yml` before committing.

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
