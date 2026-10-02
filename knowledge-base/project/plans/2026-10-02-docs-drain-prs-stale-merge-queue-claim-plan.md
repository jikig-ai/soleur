---
title: "docs: drain-prs SKILL.md still claims the merge queue is active on main"
type: docs
date: 2026-10-02
slug: docs-drain-prs-stale-merge-queue-claim
branch: feat-one-shot-9418-drain-prs-merge-queue-claim
issue: 9418
closes: 9418
domain: engineering
priority: p3-low
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# 📚 docs: drain-prs SKILL.md still claims the merge queue is active on main

> Spec lacks a valid `lane:` (no `spec.md` exists for this branch) — defaulted to
> `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-02
**Sections enhanced:** Observability (added for deepen-plan Phase 4.7 —
`plugins/*/skills/*.md` edits are outside the pure-docs exemption), Research
Insights (live-overclaim learning disposition).

### Deepen-pass gate record

- 4.6 User-Brand Impact: **pass** (section present, threshold `none`, edited
  path does not match `SENSITIVE_PATH_RE` — verified mechanically).
- 4.7 Observability: fired — `drain-prs/SKILL.md` is `.md` inside
  `plugins/*/skills/`, outside the pure-docs exemption → `## Observability`
  added below.
- 4.8 PAT sweep: **clean** (zero matches on the four PAT shapes).
- 4.9 UI wireframe: skip — no UI-surface files.
- 4.10 Encryption posture: skip — no store or cross-component connection.
- 4.11 Guard contract: skip — no guard deliverable (a doc-freshness guard is on
  the Cut List).
- 4.12 Scope Check: **pass** — one unfenced section, all three subsections,
  every ask mapped, inferred rows justified.
- Subagent fan-outs (skills/learnings/review agents, Phases 2/3/4/5): this
  harness exposes no Task/Workflow spawn surface, so they were executed inline
  by the planning subagent; noted in `decision-challenges.md`.

## Overview

`plugins/soleur/skills/drain-prs/SKILL.md` §"4. Per in-scope PR" asserts that a
GitHub merge queue is active on `main` "as the current default" and that
`gh pr merge --squash` therefore *enqueues* a PR. That is stale: the
`merge_queue` ruleset rule was adopted in PR #5800 and kill-switched the same
day (2026-06-30, PR #5811) after the CodeQL-on-`merge_group` status deadlock
(ADR-032 amendment; upstream `github/codeql-action#1537`). A drain run trusting
the doc predicts queue behavior that does not exist — e.g., waiting on queue
serialization instead of treating a "not up to date" rejection as the normal
direct-merge path. This plan corrects the claim in place (the issue explicitly
permits "drop or correct"; correcting preserves the operational guidance).

## Research Insights

### Relevant files

- `plugins/soleur/skills/drain-prs/SKILL.md` — §4 merge bullets (the stale claim
  is the first of two bullets; the second bullet already documents the real
  path and is currently mislabeled "(fallback)"), plus a residual
  "queue-inactive CI wait" phrase in the Sharp Edges section.
- `infra/github/ruleset-ci-required.tf` — the authority on the current state:
  `strict_required_status_checks_policy = true`, `merge_queue` block absent
  (`grep -c 'merge_queue {' infra/github/ruleset-ci-required.tf` → `0`), and a
  comment block recording the #5780 adoption → revert.
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md`
  §"Amendment — 2026-06-30 (#5780)" — records the deadlock and the reverted
  state; names the re-adoption preconditions.
- `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`
  — the incident record.
- `.github/workflows/codeql-1537-revisit-watch.yml` — the live watcher that
  pings the re-adoption trackers when upstream resolves.

### Git evidence (origin/main)

| Commit | Date (UTC) | Event |
|---|---|---|
| `1f041b9d6a` | 2026-06-30 21:36 | PR #5800 adopts the `merge_queue` rule |
| `5f2ec0cdc0` | 2026-06-30 22:39 | PR #5811 kill-switches it (the revert) |
| `77c2376fb6` | — | PR #5812 removes staged codeql.yml advanced setup |
| `7ef11cbb92` | — | PR #5835 records codeql-action#1537 as the real blocker |
| `4439c23c39` | 2026-07-01 09:49 | PR #5842 removes dormant PR-1 merge-queue workflows |

### Related issues / PRs

- #4856 (OPEN) — re-add tracker for the merge queue ruleset.
- #5840 (OPEN) — revisit merge queue when `codeql-action#1537` resolves.
- #9401 (CLOSED) — disjoint-delta interim policy; ADR-265 (status: active) is
  the operative pre-merge sync policy the corrected text stays consistent with.
- #9418 (OPEN) — this issue; deferred finding from the #9406 review.

### Sibling-claim sweep

`git grep` over `plugins/`, `knowledge-base/engineering/`, `docs/`, and
`.github/` for queue-activity claims found exactly ONE stale assertion —
`drain-prs/SKILL.md`'s §4 bullet. `merge-pr`, `ship`, `work`,
`monitor-pr-checks.sh`, and the `terraform-architect` agent mention the queue
only conditionally or historically. One **adjacent stale comment** was observed,
out of the issue's literal scope: `.github/workflows/scheduled-terraform-drift.yml`
(line ~44) says the drift matrix covers "the new merge_queue rule", which no
longer exists — it is a rationale comment, not behavior, so it is dispositioned
**acknowledge-and-leave** (a one-line comment tidy in the same PR is permitted
but not required).

### Premise Validation (Phase 0.6)

Checked: (a) `gh issue view 9418` → OPEN, not closed by a merged PR; (b) the
cited claim exists verbatim at `plugins/soleur/skills/drain-prs/SKILL.md` §4;
(c) the cited revert is real — ADR-032 amendment + ruleset comments + git
history above; (d) mechanism-vs-ADR check — correcting the doc aligns with
ADR-032's current decision ("CodeQL required ⇒ no merge queue"), not against
any rejected alternative. One premise correction: the issue dates the revert
"2026-07-01"; the kill-switch commit landed 2026-06-30 22:39 UTC — the
2026-07-01 commit was the dormant-workflow cleanup (#5842). The corrected doc
text should cite the revert by ADR/PR anchor, not pin the issue's date
(`cq-cite-content-anchor-not-line-number`).

### Property List (Phase 0.6b)

1. `drain-prs`'s §4 text reflects the merge mechanism actually enforced on
   `main` today: direct squash merge under strict up-to-date protection, no
   queue — so a drain run does not mis-predict `gh pr merge --squash`.
2. The text preserves the operational guidance that stays true either way
   (update-branch rejection handling, the `knowledge-base/` count carve-out,
   Monitor/AwaitShell CI wait).
3. The text points at the re-adoption authority so the next reader knows where
   the current state is decided (ADR-032 amendment; #5840 / #4856).

### Cut List (Phase 0.6b)

- A drift guard / test asserting doc-freshness of this claim — buys no property
  in the list; `codeql-1537-revisit-watch.yml` already watches the condition
  that would make the text stale again, and re-adoption lands via its own PR.
- Rewriting `merge-pr` / `ship` / `work` queue mentions — sweep verified they
  are accurate; nothing to fix.
- Any behavioral change to the drain flow — the issue is docs-only.

### External research

Skipped — the claim, the authority (`infra/github/ruleset-ci-required.tf`,
ADR-032), and the fix shape are all in-repo; local context is decisive.

### Learnings considered (deepen pass)

- `2026-07-24-holding-a-live-overclaim-pending-infra-teardown-and-drain-can-mean-keep-open.md`
  — establishes when a live over-claim may be HELD (a second, tracked
  remediation will independently cure it). Not applicable here: re-adoption is
  blocked upstream and unscheduled, and the claim asserts a *current default* —
  false today regardless of any future cure. Correct now; the re-adoption
  pointer keeps the text honest when the state changes.
- `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`
  — the merge-queue IaC episode's own learning; context only.

### Open Code-Review Overlap

`None` — 87 open `code-review`-labeled issues scanned via the Phase 1.7.5
two-stage `gh --json | jq --arg` procedure; zero bodies contain
`plugins/soleur/skills/drain-prs/SKILL.md`.

## Proposed Change

One edit region in `plugins/soleur/skills/drain-prs/SKILL.md` §"4. Per in-scope
PR — ensure green, then merge": replace the two-bullet "queue active / queue
inactive (fallback)" pair so the *direct-merge* path is the documented default
and the queue is described as reverted-with-pointer. Reference shape (the
implementer may wordsmith; semantics are the contract):

```markdown
- **No merge queue on `main`** — `gh pr merge --squash` is a **direct merge**
  under strict up-to-date protection (`strict_required_status_checks_policy` in
  `infra/github/ruleset-ci-required.tf`). A `merge_queue` rule was adopted in
  #5800 and reverted the same day (ADR-032 amendment; CodeQL reports no status
  on `merge_group`, upstream `github/codeql-action#1537`; re-adoption tracked
  in #5840 / #4856). If the merge is rejected for "not up to date", run
  `gh pr update-branch <N>` — **but never when both sides moved the
  `knowledge-base/` file count**, which a server-side merge resolves without
  the `kb-index` driver; merge `origin/main` locally and push instead (see
  [merge-pr/SKILL.md](../merge-pr/SKILL.md) §"A SERVER-SIDE update cannot run
  the driver"), then wait for CI to go green using **Claude: Monitor tool** /
  **Grok: AwaitShell** (`plugins/soleur/lib/harness.ts` `pollInstructions()`) —
  NEVER a backgrounded poll loop (`hr-monitor-not-run-in-background-for-polling`,
  hook-enforced by `background-poll-prefer-monitor.sh`), then merge. Because
  every merge re-bases the rest under strict protection, merges serialize one
  at a time.
- **If the queue is re-adopted** (#5840): `gh pr merge --squash` **enqueues**
  the PR; the queue handles `update-branch` + serialization + the final merge
  automatically — do not hand-roll update/wait loops then.
```

The second bullet's body (update-branch carve-out, kb-index driver, CI-wait
tooling) is load-bearing and must be preserved essentially verbatim — only its
"(fallback)" framing changes.

Secondary tidy in the same file: the Sharp Edges bullet reading "for the
queue-inactive CI wait" may be reworded (e.g., "for the post-`update-branch`
CI wait") since queue-inactive is no longer a special case. Optional but
recommended for consistency.

## Files to Edit

- `plugins/soleur/skills/drain-prs/SKILL.md` — §4 bullet pair (and optionally
  the Sharp Edges "queue-inactive" phrase). Estimated ~3-6 changed lines.

## Files to Create

- None (planning artifacts `tasks.md` / `session-state.md` are pipeline
  records, not deliverables).

## User-Brand Impact

- **If this lands broken, the user experiences:** a `soleur:drain-prs` session
  (operator or agent) keeps predicting queue-enqueue semantics on a repo with
  no queue — worst case it waits on `merge_group` events that never fire or
  misreads a routine "not up to date" rejection as an anomaly.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — this is a public-repo documentation line; no credential,
  data, or production surface is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** docs-only line edit inside an
  internal skill; `plugins/soleur/skills/drain-prs/SKILL.md` does not match
  preflight's canonical `SENSITIVE_PATH_RE` (verified against Check 6 Step 6.1),
  and the fix changes no runtime behavior.

## Observability

The edited file is a `.md` inside `plugins/*/skills/` — outside deepen-plan
4.7's pure-docs exemption — so the skill doc's "observability surface" is
declared here: how a reader notices the doc's merge-mechanism claim is wrong
again.

```yaml
liveness_signal:
  what: "no queue-active assertion present in drain-prs SKILL.md (content property)"
  cadence: "per-change (the AC greps in this plan); the re-adoption condition is watched by codeql-1537-revisit-watch.yml"
  alert_target: "tracking issue #5840 — the watcher comments there when upstream codeql-action#1537 resolves"
  configured_in: "plugins/soleur/skills/drain-prs/SKILL.md §4; .github/workflows/codeql-1537-revisit-watch.yml"
error_reporting:
  destination: "the operator/agent session running soleur:drain-prs — the doc is loaded into context and mis-predicts merge behavior (the #9418 defect surface)"
  fail_loud: "a 'not up to date' rejection on gh pr merge --squash is the loud runtime signal; the doc must describe it as the normal path, not a fallback"
failure_modes:
  - mode: "merge queue re-adopted (via #5840/#4856) while the doc still describes direct merge as the only path"
    detection: "the re-adoption PR is expected to update §4 in the same change; the corrected text names #5840 as the re-adoption authority so the next reader finds it"
    alert_route: "tracking-issue comment on #5840 from codeql-1537-revisit-watch.yml"
logs:
  where: "git history of the file (git log -p plugins/soleur/skills/drain-prs/SKILL.md)"
  retention: "permanent (git)"
discoverability_test:
  command: grep -c 'Merge queue active' plugins/soleur/skills/drain-prs/SKILL.md
  expected_output: "0"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a one-region documentation correction
inside a plugin skill (issue labels: `domain/engineering`, `meta/machinery`,
`type/chore`, `priority/p3-low`). Product/UX mechanical override: `## Files to
Edit`/`## Files to Create` contain no UI-surface path — gate does not fire.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Correct or drop the claim." | `plugins/soleur/skills/drain-prs/SKILL.md` §4 edit | mapped |

(Remaining issue-body text — "Deferred finding from the #9406 review", the
false-since-revert assertion, "A drain run trusting it will mis-predict merge
behavior", and the "Related: #4856 / #5840 / #9401" list — is declarative
context, not asks.)

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| §4 bullet-pair rewrite | "Correct or drop the claim." | asked |
| Sharp Edges "queue-inactive" rewording | — | inferred — justification: the only other in-file footprint of the same stale framing; leaving it preserves "queue is the default" semantics the fix removes |
| `scheduled-terraform-drift.yml` comment tidy (optional) | — | inferred — justification: same stale-claim class observed during the sibling sweep; permitted-not-required so it cannot block the ask |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur` (optionally `.github` for the
  comment tidy; still 2 roots, under threshold)
- Planned files: 1 (2 with the optional tidy) | Estimated changed lines: ~6
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git grep -c 'Merge queue active' -- plugins/soleur/skills/drain-prs/SKILL.md`
  returns `0` (the stale assertion token is gone).
- [ ] The §4 merge text no longer frames any path as "(fallback)": direct merge
  under strict up-to-date protection is the documented normal path, and
  `gh pr update-branch` handling for "not up to date" rejections — including
  the `knowledge-base/` file-count / `kb-index` carve-out — is preserved
  (`grep -c 'kb-index' plugins/soleur/skills/drain-prs/SKILL.md` ≥ 1).
- [ ] The corrected text cites the revert authority by anchor — ADR-032
  amendment and/or the `merge_queue` removal recorded in
  `infra/github/ruleset-ci-required.tf` — and asserts no date that contradicts
  git history (kill-switch #5811 landed 2026-06-30, not 2026-07-01).
- [ ] `grep -c -e 'ADR-032' -e 'codeql-action' plugins/soleur/skills/drain-prs/SKILL.md`
  ≥ 1 after the edit (the added claims trace to a named source — paired with
  the absence grep above so shape-only verification cannot pass over a false
  replacement claim).
- [ ] No other operator-facing doc asserts the queue is active:
  `git grep -n -e 'Merge queue active' -e 'merge queue is active' -- plugins/
  knowledge-base/engineering/ docs/` returns no hits (sweep verified clean of
  every file except drain-prs before the fix).
- [ ] `bash plugins/soleur/test/drain-prs.test.sh` passes (doc-only edit; the
  suite asserts tier logic, not this prose — verified it contains no
  queue-claim assertions).
- [ ] PR body uses `Closes #9418`.

## Test Scenarios

- Given the edited file, when `git grep -c 'Merge queue active'` runs against
  `plugins/soleur/skills/drain-prs/SKILL.md`, then the count is `0`.
- Given a drain session reading §4, when `gh pr merge --squash` is rejected
  "not up to date", then the documented path matches the enforced ruleset
  state: `grep -c 'merge_queue {' infra/github/ruleset-ci-required.tf` → `0`
  and `strict_required_status_checks_policy = true` present — i.e., the doc's
  "direct merge, then update-branch" description is the real behavior.
- Given a hypothetical queue re-adoption PR, when it lands, then the doc's
  conditional note tells the reader where re-adoption is tracked (#5840)
  rather than asserting a state.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (Satisfied above: threshold `none`, both artifact
  and vector lines filled.)
- Do not paraphrase the issue's "2026-07-01 revert" date into the doc — the
  kill-switch commit `5f2ec0cdc0` landed 2026-06-30 22:39 UTC; cite the
  ADR-032 amendment / #5811 anchor instead (`cq-cite-content-anchor-not-line-number`,
  and the plan's own correction class: sharp-edge "correct a factual claim —
  grep the output for the old value" applied to this plan's prose too).
- The second §4 bullet's operational content (`gh pr update-branch`,
  `knowledge-base/` count carve-out, `merge-pr` cross-reference, Monitor /
  AwaitShell wait, serialization sentence) is load-bearing for the CURRENT
  path — preserve it; the fix is a re-frame, not a deletion.
- Absence-grep ACs are shape-only checks; the paired positive AC (ADR-032 /
  codeql-action citation present, `kb-index` carve-out present) is what
  certifies the replacement text is correct, not merely gone.
- `drain-prs` is not in `skill-body-budget.json` (lifecycle skills only), so
  no byte-ceiling applies — but keep the edit minimal anyway; do not
  restructure the section.
- No test suite asserts on this prose (`drain-prs.test.sh` covers tier
  logic) — the AC greps above are the verification; do not add a prose-freshness
  guard (Cut List).

## Non-Goals

- Re-adopting or re-enabling the merge queue (tracked by #4856 / #5840).
- Editing `infra/github/ruleset-ci-required.tf`, ADR-032, or any workflow —
  they already record the reverted state correctly.
- Changing `merge-pr`, `ship`, `work`, or `monitor-pr-checks.sh` — their queue
  mentions are accurate.
- Any behavioral/code change to the drain flow.

## References

- Issue: #9418 (OPEN) — "docs: drain-prs SKILL.md still claims the merge queue
  is active on main"; labels `priority/p3-low`, `type/chore`,
  `domain/engineering`, `meta/machinery`.
- Authority: `infra/github/ruleset-ci-required.tf` (`merge_queue` absent;
  `strict_required_status_checks_policy = true`) and ADR-032 §Amendment
  2026-06-30 (#5780).
- Post-mortem:
  `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`.
- Interim merge policy: ADR-265 (disjoint-delta pre-merge sync skip; status
  active, #9401).
- Re-adoption watchers: `.github/workflows/codeql-1537-revisit-watch.yml`
  → #5840 / #4856.
