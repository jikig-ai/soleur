# chore: Bundle-fix 12 Open Compound Route-to-Definition Proposals

**Branch:** `feat-one-shot-fix-compound-issues`
**Type:** chore (documentation / meta-workflow)
**Effort:** Medium (12 issues, ~7 distinct target files, mechanical edits)
**Closes:** #2116, #2228, #2237, #2248, #2266, #2273, #2363, #2364, #2365, #2366, #2471, #2522

## Overview

Twelve open GitHub issues prefixed `compound:` propose promoting one-shot session learnings into durable workflow definitions (AGENTS.md rules, skill SKILL.md sharp edges, agent files, hook scripts). Each is a thin route-to-definition edit — most are a single bullet append — and they do not conflict. They can ship as one bundled PR.

Goal: apply each proposal to its target file (with light quality tightening where proposals are verbose), respect AGENTS.md byte budget (rule `cq-agents-md-why-single-line`, rule `cq-rule-ids-are-immutable`), and close all 12 issues in one commit history.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue) | Reality (verified 2026-04-18) | Plan response |
|---|---|---|
| #2522 targets `plugins/soleur/hooks/security_reminder_hook.py` as a Soleur-repo hook | The triggering hook is the user-installed `claude-plugins-official/security-guidance/hooks/security_reminder_hook.py` under `~/.claude/plugins/marketplaces/`. Soleur's own `.claude/hooks/security_reminder_hook.py` is a different file that handles only GitHub Actions workflow injection and has no child-token detector. | Close #2522 with a comment: the fix belongs upstream in the security-guidance plugin, not in Soleur. If a Soleur-local workaround is desired, add an `ENABLE_SECURITY_REMINDER=0` override in `.claude/settings.local.json` for learning files or markdown writes — but out of scope for this bundled PR. |
| #2471 target `plugins/soleur/agents/engineering/review/data-integrity-guardian.md` has a "Sharp Edges" section | File is 70 lines with no "Sharp Edges" heading; it ends with a numbered priority list + closing reminder | Add a new `## Sharp Edges` heading before the final "Remember:" line and insert the two bullets there. |
| #2237 item 3 target "reviewer-agent prompt references" | Natural home is the existing `## Common Pitfalls to Avoid` section in `plugins/soleur/skills/review/SKILL.md` (line 528) | Apply there, not a new section. |
| #2237 items 1 & 2 target "plan skill's task-template reference" | No canonical task-template reference file exists; `soleur:spec-templates` is a separate skill | Apply both as bullets in plan SKILL.md `## Sharp Edges` (line 606). |
| #2363, #2364 target "Sharp Edges or fixture/data-plane section" | Plan SKILL.md has Sharp Edges but no fixture/data-plane section | Apply both as Sharp Edges bullets (consolidate to avoid section proliferation). |
| #2266 target plan SKILL.md | Verified `## Sharp Edges` at line 606 | Apply directly. |

## Open Code-Review Overlap

None verified. The files edited (AGENTS.md, four skill SKILL.md files, one skill reference, one agent file) are not named in any open `code-review` issue bodies. Verification query (run at Phase 1 start to confirm no new overlaps):

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in AGENTS.md \
  plugins/soleur/skills/work/SKILL.md \
  plugins/soleur/skills/plan/SKILL.md \
  plugins/soleur/skills/review/SKILL.md \
  plugins/soleur/skills/review/references/review-todo-structure.md \
  plugins/soleur/agents/engineering/review/data-integrity-guardian.md; do
  jq -r --arg p "$f" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

If any matches surface, add a row to this section with an explicit disposition (fold-in / acknowledge / defer).

## Files to Edit

1. **`AGENTS.md`** — add two new Code Quality rules (from #2365, #2366)
2. **`plugins/soleur/skills/work/SKILL.md`** — add four bullets into Phase 2 / Phase 3 (from #2116, #2228×2, #2248)
3. **`plugins/soleur/skills/plan/SKILL.md`** — add five bullets into `## Sharp Edges` (from #2237 items 1+2, #2266, #2363, #2364)
4. **`plugins/soleur/skills/review/SKILL.md`** — add one bullet into `## Common Pitfalls to Avoid` (from #2237 item 3)
5. **`plugins/soleur/skills/review/references/review-todo-structure.md`** — add milestone-title-not-number Sharp Edges subsection (from #2273)
6. **`plugins/soleur/agents/engineering/review/data-integrity-guardian.md`** — add new `## Sharp Edges` section with two bullets (from #2471)

No repo-local edit for #2522 — close with reconciliation comment (see table above). See Phase 4 step 3.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Verify and Prepare (no code changes)

1. Re-read each issue body to confirm proposed bullet text is still current (issue bodies were snapshot on 2026-04-18; if any were edited in-flight, reconcile before applying).
2. Re-run the Open Code-Review Overlap query from the section above; append any new matches to this plan.
3. Measure current `AGENTS.md` size: verified 30617 bytes. Budget headroom before the compound 40000-byte warn gate: ~9400 bytes. Two new rules at ~450 bytes each = ~900 bytes — safe.
4. Verify no rule-ID collisions:

```bash
grep -E 'id: cq-(mutation-assertions-pin-exact-post-state|destructive-prod-tests-allowlist)' AGENTS.md || echo "IDs available"
```

5. Verify skill file section anchors are still at the expected lines (drift check — if any section moved, re-anchor at apply time):
   - `plugins/soleur/skills/plan/SKILL.md` → `## Sharp Edges` at line 606
   - `plugins/soleur/skills/review/SKILL.md` → `## Common Pitfalls to Avoid` at line 528
   - `plugins/soleur/skills/work/SKILL.md` → `### Phase 2: Execute` at line 147, `### Phase 3: Quality Check` at line 387

### Phase 2 — Apply Proposals (TDD exempt — documentation edits)

All edits are prose additions to markdown/agent definition files. No test code covers AGENTS.md rule text or skill SKILL.md content; the `lint-rule-ids.py` hook enforces rule-ID invariants and runs pre-commit.

Apply in this order:

**Step 2.1 — AGENTS.md (#2365, #2366)**

Insert both new rules in the Code Quality section after the existing `cq-cloudflare-default-bypasses-dynamic-paths` rule and before `cq-preflight-fetch-sweep-test-mocks` (keeps data-safety rules together). Target text (each under 550 bytes):

- Mutation-assertion rule: "Assertions verifying a mutation (seed, update, delete) must pin the exact post-state value [id: cq-mutation-assertions-pin-exact-post-state]. `toContain([pre, post])` is tautologically true for a no-op — use `.toBe(post)` so a silently-swallowed mutation fails the test. **Why:** #2346 seed assertion passed on no-op because the default matched the allowlist."
- Destructive-prod-test rule: "Tests that DELETE from shared production must gate on an allowlist of synthetic identifiers [id: cq-destructive-prod-tests-allowlist]. `beforeAll`/`afterAll` resets touching prod must throw if the targeted email/user-id/tenant is not on a known-synthetic allowlist. An unguarded reset is a blast-radius violation. **Why:** #2346 integration test reset caught pre-merge but demonstrated the class."

**Step 2.2 — plugins/soleur/skills/work/SKILL.md (#2116, #2228, #2248)**

Target: Phase 3 (Quality Check) for tsc + negative-space + credential-helper bullets; Phase 2 (Execute) for the reducer-extraction bullet.

Phase 3 additions (three bullets, appended after existing quality-gate bullets):

- "Run `npx tsc --noEmit` in the app package alongside the test suite. Vitest type-checks test files lazily, so TS errors in tests pass the suite locally but fail CI. A standalone tsc pass catches them at the work-phase gate instead of deferring to review."
- "When extracting enforcement logic (auth, CSRF, validation) from route files into a shared helper, update negative-space tests in the same commit. Route-level detection must prove helper invocation AND failure early-return — not just import presence. Add direct assertions on the helper file for every invariant that moved into it."
- "When adding git operations that contact remotes in Next.js API routes, include the credential helper pattern from `session-sync.ts` (search `credential.helper`). Bare `git pull`/`git push`/`git fetch` fail silently on private repos."

Phase 2 addition (one bullet, appended to Follow Existing Patterns section):

- "When extracting a pure reducer out of a React hook, migrate ALL companion state (refs the reducer reads or writes) to the reducer's state boundary in the same change. A half-extraction — pure function + mutable ref inside a `setState` updater — advertises purity the call site doesn't honor and recreates the StrictMode/concurrent-rendering hazard the extraction was meant to eliminate."

**Step 2.3 — plugins/soleur/skills/plan/SKILL.md (#2237 items 1+2, #2266, #2363, #2364)**

Append five bullets to `## Sharp Edges` (line 606). Preserve existing bullet style (terse, **Why:** pointer only when it references a PR or learning file).

1. Dated-filename prescription (from #2237 item 1): "Do not prescribe exact learning filenames with dates in tasks.md. Dates drift across session boundaries. Prescribe directory + topic only (e.g., `knowledge-base/project/learnings/bug-fixes/<topic>.md`) and let the author pick the date at write-time. **Why:** PR #2226 — plan prescribed `2026-04-14-...` but file was created on the 15th, forcing a tasks.md fix-up."
2. Pre-/post-merge acceptance criteria split (from #2237 item 2): "When a PR has post-merge operator actions (terraform apply, manual verification, external service setup), split `## Acceptance Criteria` into `### Pre-merge (PR)` and `### Post-merge (operator)` subsections. Flat lists make reviewer check-offs ambiguous. **Why:** PR #2226 P1 review finding."
3. Rule-ID rename grep (from #2266): "Before prescribing a rename of any `AGENTS.md` rule id (`[id: hr-*]`, `[id: wg-*]`, `[id: cq-*]`), grep the whole repo for the old id (`grep -rn '<old-id>' . --exclude-dir=.git`) and update every call site in the same commit. The `cq-rule-ids-are-immutable` rule covers only AGENTS.md itself — downstream references in `.claude/hooks/`, tests, docs, and `.github/workflows/` must be updated manually. **Why:** 2026-04-15 rename broke two test files because the rename was not grep-propagated."
4. Corpus pre-check (from #2363): "For any acceptance criterion that cites an external corpus (`gh issue list`, file globs, label queries, etc.), run the exact query before freezing the AC. If the corpus returns zero, either scope the AC out or file a deferral issue in the same commit — don't freeze an AC that depends on a corpus you haven't verified exists. **Why:** PR #2346 golden-set AC deferred via #2352."
5. Fixture data-plane classification (from #2364): "When a plan specifies a fixture seeding N entities, classify each entity as **DB-only** / **external service** / **hybrid** before freezing the spec. External-service entities (files in external repos, OAuth-gated resources, third-party APIs) often need separate seed strategies and may require deferral. **Why:** PR #2346 KB fixture lived in GitHub workspace, not Supabase — deferred via #2351."

**Step 2.4 — plugins/soleur/skills/review/SKILL.md (#2237 item 3)**

Append one bullet to `## Common Pitfalls to Avoid` (line 528):

- "Before reporting a broken link/missing file, reviewer agents MUST verify via Glob or Read. Unverified 'broken link' claims waste reviewer-response cycles — the file may exist at the exact path. **Why:** PR #2226 pattern-recognition-specialist false-positive on a `runtime-errors/2026-02-13-...` learning file that did exist."

**Step 2.5 — plugins/soleur/skills/review/references/review-todo-structure.md (#2273)**

Append a `## Sharp Edges` section (if one does not exist) with the milestone-title-not-number bullet:

- "`gh issue create --milestone <value>` resolves against milestone **title**, not number. `--milestone 6` fails with `could not add to milestone '6': '6' not found` even if milestone 6 exists. Retrieve the title via `gh api /repos/<owner>/<repo>/milestones --jq '.[] | {number, title}'` and pass the title. The `number` field is REST-API-only. **Why:** filing #2272 retried with `--milestone \"Post-MVP / Later\"` to succeed."

Note: AGENTS.md already has `cq-gh-issue-create-milestone-takes-title`. This skill-reference bullet is local to the review skill's issue-creation doc — not a new rule.

**Step 2.6 — plugins/soleur/agents/engineering/review/data-integrity-guardian.md (#2471)**

Insert a new `## Sharp Edges` section before the final paragraph ("Remember: In production..."):

- NOT NULL without backfill bullet: "When reviewing a migration that adds a NOT NULL column, trace whether the prior UPDATE/backfill populates the new column for ALL pre-existing rows. `alter column X set not null` after an UPDATE that only touches an adjacent column (e.g., `set revoked = true`) fails at apply time for any row, even though vitest with mocked Supabase and tsc both pass locally. Recommend scoped CHECK (`<tombstone-predicate> or X ~ ...`) over NOT NULL when pre-existing rows cannot be backfilled with a valid value."
- Partial-unique-index bullet: "For 'one active X per Y' invariants (one active share per user+path, one active session per user, etc.), reach for a partial unique index (`on table(a, b) where revoked = false`) instead of trusting application-level SELECT-then-INSERT. The race is real — two concurrent POSTs both see 'no existing row' and both insert."

### Phase 3 — Quality Check

1. Run `npx markdownlint-cli2 --fix` on the specific edited markdown files only (not repo-wide, per `cq-markdownlint-fix-target-specific-paths`). Include the plan file itself.
2. Run `bash .claude/hooks/security_reminder_hook.test.sh` to confirm Soleur's own workflow-injection hook test still passes (unrelated to #2522 but part of the pre-commit guardrail).
3. Run the rule-ID linter to verify the two new AGENTS.md IDs parse cleanly and no existing ID was rewritten:

```bash
python3 .claude/hooks/lint-rule-ids.py AGENTS.md
```

4. Measure `AGENTS.md` size post-edit — confirm under 40000 bytes:

```bash
wc -c AGENTS.md
```

5. Verify every new AGENTS.md bullet is under 600 bytes individually:

```bash
awk '/^- .*\[id: (hr|wg|cq|rf|pdr|cm)-/ { if (length($0) > 600) print length($0), $0 }' AGENTS.md
```

6. Review SKILL.md byte changes — the compound step-8 guard warns at single-rule >600 bytes for AGENTS.md; skill SKILL.md files have no per-bullet cap but should still match surrounding terseness.

### Phase 4 — PR and Close

PR body template (single commit, squash-merge):

```markdown
Bundles 12 compound route-to-definition proposals into a single commit-history entry. Each proposal was validated against its target file and applied with light editorial tightening for byte-budget compliance. Issue #2522 is closed with a reconciliation comment — the hook it targets lives in an upstream plugin marketplace, not in Soleur's repo.

Closes #2116
Closes #2228
Closes #2237
Closes #2248
Closes #2266
Closes #2273
Closes #2363
Closes #2364
Closes #2365
Closes #2366
Closes #2471
Closes #2522

## Changelog

PATCH — workflow documentation edits only; no runtime behavior change.

## Files changed

- AGENTS.md — two new Code Quality rules (mutation assertions; destructive-test allowlist)
- plugins/soleur/skills/work/SKILL.md — four bullets across Phase 2 and Phase 3
- plugins/soleur/skills/plan/SKILL.md — five Sharp Edges bullets
- plugins/soleur/skills/review/SKILL.md — one Common Pitfall bullet
- plugins/soleur/skills/review/references/review-todo-structure.md — milestone-title Sharp Edges subsection
- plugins/soleur/agents/engineering/review/data-integrity-guardian.md — new Sharp Edges section with two bullets
```

Steps:

1. Commit with `/ship` to enforce compound and review gates.
2. Label with `semver:patch`.
3. Immediately after opening the PR, post a comment on #2522 explaining the reconciliation: the targeted hook is an upstream plugin-marketplace file (`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/security-guidance/hooks/security_reminder_hook.py`), not Soleur-repo-local. Recommend either (a) upstream PR to the `claude-plugins-official` marketplace, or (b) local env override `ENABLE_SECURITY_REMINDER=0` for markdown writes via `.claude/settings.local.json`, or (c) disabling the `security-guidance` plugin if its false-positive rate outweighs its value. This comment is preserved on issue close so the next person hitting the false-positive has the three-option menu.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Steps 2.1 through 2.6 applied, bullet text verified against issue-body text (with editorial tightening noted where applied).
- [ ] `AGENTS.md` byte count under 40000; no new rule exceeds 600 bytes.
- [ ] Both new rule IDs (`cq-mutation-assertions-pin-exact-post-state`, `cq-destructive-prod-tests-allowlist`) pass `lint-rule-ids.py`.
- [ ] `npx markdownlint-cli2 --fix` passes on edited files.
- [ ] `bash .claude/hooks/security_reminder_hook.test.sh` passes.
- [ ] PR body contains `Closes #N` for each of the 12 issues.
- [ ] `semver:patch` label applied.

### Post-merge (operator)

- [ ] Verify on main that every `Closes #N` auto-closed the issue (GitHub UI — all 12 show "Closed by PR").
- [ ] On #2522, confirm the reconciliation comment is posted and the issue is closed (not reopened).
- [ ] No release/deploy workflows failed (this is docs-only — should be clean).

## Test Scenarios

This is a documentation-only change. No runtime test cases apply. Hook guardrails covered by `security_reminder_hook.test.sh` (already passing; re-run in Phase 3).

## Non-Goals

- Not expanding any proposal beyond the prescribed bullet text. Editorial tightening for byte budget only — no semantic inflation.
- Not fixing the upstream `security-guidance` marketplace hook (#2522). That is either an upstream PR or a settings-level override; out of scope for this bundled PR.
- Not adding new rule IDs beyond the two named. Re-evaluation of related patterns happens in a future compound cycle, not here.
- Not cascading the proposals into adjacent documents (e.g., not duplicating the rule-ID-rename guidance into `knowledge-base/project/constitution.md` — the skill file is the canonical home per single-source discipline).
- Not producing a separate learning file for this PR. The proposals *are* the learning; applying them closes the loop. A compound entry at ship-time will record the bundle-PR cadence (not the proposal content itself).

## Risks

- **Bundle PR review fatigue.** 12 issues × ~1 bullet each = low per-item risk, but the reviewer must cross-check each applied bullet against its source issue. Mitigation: PR body lists each file and links each bullet to its source issue via `Closes #N` plus a short description.
- **AGENTS.md byte creep.** Adding two rules pushes the file closer to the 40000-byte compound warn. Currently 30617; post-edit projected ~31500. Mitigation: Phase 3 step 4 measures and gates.
- **Stale proposal text.** Some issues reference older PR numbers or learning files that may have been archived. Mitigation: Phase 1 step 1 re-reads each issue body and the linked learning file before committing the bullet.
- **#2522 reconciliation pushback.** The founder may disagree with closing #2522 without a code change. Mitigation: the PR-comment reconciliation is explicit, lists the three alternatives, and invites reopening if a Soleur-local workaround is preferred.
- **`.claude/hooks/security_reminder_hook.py` namespace confusion.** Soleur has its own hook of the same filename (workflow-injection-only). The reconciliation comment must be precise about paths to avoid future confusion.

## Domain Review

**Domains relevant:** none — workflow definitions only, no user-facing surface, no product/marketing/legal/finance implications. Infrastructure/tooling change.

No cross-domain implications detected.

## Rollout Plan

Single PR, squash-merge, auto-close all 12 issues via `Closes #N`. No feature flags, no migrations, no deploys. Post-merge verification is a GitHub-UI scan plus confirming the #2522 reconciliation comment posted.

## References

- Canonical rules touched: `cq-agents-md-why-single-line`, `cq-rule-ids-are-immutable`, `cq-markdownlint-fix-target-specific-paths`, `wg-when-a-workflow-gap-causes-a-mistake-fix` (this PR is an instance of that rule — a learning alone wasn't enough; the edits close the gap).
- Source learnings (one per issue, verified to exist unless noted):
  - `knowledge-base/project/learnings/integration-issues/kb-upload-missing-credential-helper-20260413.md` (#2116)
  - `knowledge-base/project/learnings/best-practices/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md` (#2228)
  - `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` (#2237)
  - `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md` (#2248)
  - `knowledge-base/project/learnings/best-practices/2026-04-15-rule-utility-scoring-telemetry-patterns.md` (#2266)
  - `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md` (#2273)
  - `knowledge-base/project/learnings/2026-04-15-ux-audit-scope-cutting-and-review-hardening.md` (#2363, #2364, #2365, #2366)
  - `knowledge-base/project/learnings/2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md` (#2471)
  - `knowledge-base/project/learnings/2026-04-17-public-route-error-message-centralization-and-regex-exec-hook-trip.md` (#2522 — file presence to be confirmed in Phase 1; if absent, the issue body itself is the source)

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-18-chore-bundle-fix-compound-route-to-definition-proposals-plan.md
Branch: feat-one-shot-fix-compound-issues. Worktree: .worktrees/feat-one-shot-fix-compound-issues/.
Issues: #2116, #2228, #2237, #2248, #2266, #2273, #2363, #2364, #2365, #2366, #2471, #2522.
Plan and deepen-plan complete. Implementation next — 12 route-to-definition edits as a single bundled PR; #2522 closed by reconciliation comment.
```
