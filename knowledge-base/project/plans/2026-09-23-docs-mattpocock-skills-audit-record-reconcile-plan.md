---
title: "docs(ci): land the mattpocock/skills peer-plugin audit record, reconciled against the five shipped bundles"
date: 2026-09-23
slug: docs-mattpocock-skills-audit-record-reconcile
branch: feat-ci-mattpocock-skills-audit
issue: 8284
closes: none
type: docs
priority: p3-low
domain: product
brand_survival_threshold: none
requires_cpo_signoff: false
refs: [8497, 8499, 8486, 8505, 8548]
lane: cross-domain
---

# docs(ci): land the mattpocock/skills audit record, reconciled

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-23
**Sections enhanced:** Research Insights, Research Reconciliation, Proposed Solution (triage table), Implementation Phases 1/3/4, Acceptance Criteria, Domain Review, tasks.md
**Agents used:**
- plan phase: repo-research-analyst ×2, learnings-researcher, functional-discovery, and CTO, CMO, COO and CLO domain leaders;
- advisor consult (fable);
- plan-review: DHH, Kieran, code-simplicity, CPO, CMO;
- deepen: spec-flow-analyzer, git-history-analyzer, a verify-the-negative sweep (sonnet), pattern-recognition-specialist.

### Key Improvements

1. **The reconciliation now reaches every stale cell a reader can land on** (spec-flow P0):
   - two now-false "No `frontier` concept exists" sentences are corrected in place (`product-roadmap next --frontier` shipped in `#8292`);
   - a dated pointer sits under each of the §2, §3 and §4 table lead-ins;
   - a third-cell note covers the Tier 1 row's remaining gap claims.
2. **AC defects that would have passed vacuously, or failed on a correct tree, are fixed** (Kieran, pattern review, spec-flow):
   - absence greps now carry their file operand;
   - the case-sensitive `not bundled` check is corrected;
   - `$TMPDIR` is replaced by `mktemp`;
   - the stale-row coverage for "implausible" (Convergence risk) and the Tier 1 star sentence is fixed;
   - issue comments carry a `pr8284-triage` marker, so AC10 counts exactly one each.
3. **Triage traces land where each issue's owner looks.** Every one of the five issues gets a marked comment (`#8548` after merge, with the status-anchor permalink). The earlier cut of the `#8548` comment was reversed: nothing reads the `content-strategy.md` Sources cell.
4. **Three factual corrections from the verify-the-negative and attribution passes:**
   - `ANTHROPIC_ADMIN_KEY` *is* used, by `cron-anthropic-cost-report.ts`, though it cannot be minted;
   - the credit-exhaustion regex already exists on the cron path;
   - `cq-prose-issue-ref-line-start` is a retired rule id.

   All five issue→PR pairs, commits `534e916cec` and `1a5b79261`, ADR-108 and `#6297` were verified live.
5. **Merge Danger carries both mandatory fields** (`Undo`, `Blast Radius`). The PR body no longer frames the `#8505` console step as a tracked human step. That step stays `automation-status: UNVERIFIED`.

### New Considerations Discovered

- `origin/main` moved to `fc7b7dc2de` during planning. The rebase still merges cleanly. Re-run `merge-tree` right before the force-push.
- The plan-time `git push` of the plan artifacts was rejected as a non-fast-forward, because the local branch is an unpushed rebase over remote `41ea2b6a7d`. The plan commit is local only, and the work/ship phase's `--force-with-lease` push publishes it.
- Taste findings (T1–T5) are persisted in `knowledge-base/project/specs/feat-ci-mattpocock-skills-audit/decision-challenges.md` for ship to render. None were auto-applied.

## Overview

PR 8284 adds the mattpocock/skills peer-plugin audit to the Tier 1 table of the competitive-intelligence
record. It was written on 2026-09-18, before any of the five implementation bundles it recommended were
built, and it never merged. The NOTICE entry for mattpocock/skills pins that audit by SHA and date,
yet the file on main carries no mattpocock row, so the audit it refers to has no readable record there.
This plan reconciles the audit body's claims against what actually shipped, lands it, and gives a
triage verdict for each of the five open follow-ups the bundles filed.

## Research Insights

### Premise Validation (Phase 0.6)

- **PR 8284** is OPEN, not draft, `mergeable: MERGEABLE`, `mergeStateStatus: BEHIND` on the *remote* head
  `41ea2b6a7d`. The local branch is already rebased: one commit, `35bf829563`, parented on
  `origin/main` tip `251cfa650e`. `git range-diff` shows the rebased commit is content-identical (`=`)
  to the remote one. `origin/main` has since moved to `fc7b7dc2de` (1 commit ahead of the rebase base),
  and `git merge-tree --write-tree origin/main HEAD` still exits clean — re-run it immediately before the
  push, because main keeps moving. The rebase has
  **not been pushed**: publishing it needs `git push --force-with-lease=feat-ci-mattpocock-skills-audit:41ea2b6a7d`,
  because a plain push is a non-fast-forward. Every check on the old head was green, and those runs are
  stale after the force-push.
- **Upstream has not moved.** `gh api repos/mattpocock/skills/compare/c55ee46...main` reports
  `ahead_by: 0`, so the audited SHA is still the peer's HEAD, and the audit's inventory, overlap and
  pattern sections need no re-audit. Stars and forks re-read on 2026-09-23 via `gh repo view`:
  **268,223 / 22,623**, up from 264,914 / 22,339 at audit. That is still gh-reported only, and still
  unverified against an independent source.

  > **Superseded 2026-09-23 (review, PR 8284):** replaced by the GitHub-API snapshot wording in competitive-intelligence.md §1 Stars / forks; the earlier phrasing read as doubt about a named third party's repo.

- **All five bundle issues are CLOSED** by merged PRs: `#8287`→PR `#8297` (2026-09-19),
  `#8288`→`#8352` (2026-09-19), `#8289`→`#8405` (2026-09-20), `#8290`→`#8484` (2026-09-21),
  `#8292`→`#8536` (2026-09-22). `#8291` in that number range is an unrelated vector-test bug.
- **All five follow-ups are OPEN**: `#8497` p3, `#8499` p3, `#8486` p2 type/security, `#8505` p2
  type/security, `#8548` p3 content. The pipeline lead ran the collision probe: no open PR other than
  8284 touches `competitive-intelligence.md`. Re-checked here: no open PR touches NOTICE,
  `knowledge-base/project/rejected/`, eval-harness, or the flag/role script directories.
- **The premise that the audit is "the provenance anchor every bundle's NOTICE points at" is only partly
  true.** `plugins/soleur/NOTICE` §mattpocock/skills pins the audit by SHA and date ("Audited at: HEAD
  c55ee46… (2026-09-18)"). It does **not** name `competitive-intelligence.md`, and
  `git grep competitive-intelligence origin/main -- plugins/soleur/NOTICE` returns nothing. The anchor
  is the audit event. Landing the record still gives that event a readable home on main. NOTICE stays
  untouched: it is in the plugin payload, and a `knowledge-base/` path would dangle for plugin
  installs.

### Claim-by-claim reconciliation (re-derived by the planner; subagent claims were re-checked)

The subagent's reconciliation table had five errors. It said `operator-rephrase` and `phase-boundaries`
closed under `#8289`/`#8290`; NOTICE lists both under `#8287`. It said B4 was CLOSED; the only `frontier`
hit in `brainstorm/SKILL.md` is the roadmap `--add-blocked-by` line, and there is no grilling frontier protocol. It counted "9 flagged skills"; `git grep '^disable-model-invocation: true'`
over the skills returns **8**, matching ADR-236. It said the perf branch was absent; it is present at
`reproduce-bug/SKILL.md` "**Perf branch.**". It said "No outstanding audit gaps", which is false (see
B4 and B10). The table below uses the corrected facts.

| Audit item (2026-09-18) | Status on origin/main 2026-09-23 (content anchor) | Closed by |
|---|---|---|
| G1 `wizard` / "no generator; `auto_command` 0 hits" | `plugins/soleur/skills/operator-bootstrap/` (`SKILL.md` + `template.sh`) and `scripts/lib/operator-script.sh`. `ship/SKILL.md` Phase 5.5 option 4 reads "Generate a runnable script instead — invoke `skill: soleur:operator-bootstrap`". `auto_command` now appears in `AGENTS.rules.md`, `operator-bootstrap/SKILL.md` and `ship/SKILL.md`. ADR-228 records that generated scripts are non-interactive by default. NOT adopted: the inlined-library `STAGES`-marker invariant, because scripts source a shared lib instead (NOTICE). | `#8287` / PR `#8297` |
| G5 `wait-what` | `skills/operator-rephrase/` | `#8287` |
| B9 Merge Danger | `ship/SKILL.md` `## Merge Danger` with "TWO fields, both mandatory": `**Undo:**` + `**Blast Radius:**`. The one-way/two-way **Door** verdict was deliberately NOT adopted, because on most PRs Soleur does not produce the reversibility evidence it would need (NOTICE). | `#8287` |
| B12 flow map + context tree | Tree shipped: `skills/brainstorm-techniques/references/phase-boundaries.md`, reached from `AGENTS.rules.md` and `brainstorm-techniques/SKILL.md`. **Flow-map half not shipped**: `commands/go.md` and `skills/help/SKILL.md` have no flow-map or on-ramp content. | `#8287` (partial) |
| B1 red-capable loop, B2 `[DEBUG-]` tags, B3 seam-absence | `reproduce-bug/SKILL.md`: red-capable completion gate, ranked falsifiable hypotheses, `[DEBUG-<hex4>]` probes (ADR-230), "**Perf branch.**", seam-absence routed to `legacy-code-expert`, repro minimisation. `test-fix-loop/SKILL.md` carries the probe convention. **All 6 of the "0 of 6" diagnosing-bugs mechanics now present.** | `#8288` / PR `#8352` |
| B7 constraint-scaffold bite-proof + README + pointer | `constraint-scaffold/SKILL.md` "**prove the gate bites** (see Bite-proof below)", plus `references/boundary-readme.template`. The pointer shape is live in this repo's own `CLAUDE.md` ("constraint-scaffold:pointer"). NOT adopted: the peer's four-rule deep-module scope. | `#8288` |
| G2 rejected-request KB, B11 triage pre-checks | `knowledge-base/project/rejected/README.md` ("The no-list") and `kb-glossary/references/rejected-request-register.md`. Intake pre-checks in `triage/SKILL.md`, `agents/support/ticket-triage.md` and the `.openhands` mirror. ADR-234. NOT adopted: the dotted `.out-of-scope/` location and the Confirm/Reconsider/Disagree prompt. | `#8289` / PR `#8405` |
| G3 glossary | `knowledge-base/project/glossary.md` and `skills/kb-glossary/` | `#8289` |
| G4 `to-questionnaire` | `skills/questionnaire-generate/` | `#8289` |
| §1 skill-creator defects (dangling `use-xml-tags.md`; markdown-vs-XML contradiction) | `git grep use-xml-tags origin/main -- plugins/soleur/skills/skill-creator/` returns 0. `git log -S use-xml-tags` names `534e916cec` ("heading-structured skill-creator (#8484)"). | `#8290` / PR `#8484` |
| B6 authoring levers | `skill-creator/references/authoring-levers.md`: leading words with the negation-pairing rule, the two loads, co-location, criterion demand, and the invocation axis | `#8290` |
| Invocation axis | ADR-236. 8 skills carry `disable-model-invocation: true`: admin-ip-refresh, cf-token-scope, flag-delete, provision-cloudflare/doppler/github/hetzner, user-set-role. The exact-set pin is `plugins/soleur/test/invocation-axis.test.ts`. | `#8290` |
| B5 negation rewrite of `AGENTS.rules.md` | **Not applied.** The A/B was INCONCLUSIVE (+8.0 pts, [+0.2, +15.8], 648 calls, $48.85). The post-verdict audit (issue 8497 comment, 2026-09-21) qualified it as "INCONCLUSIVE; instrument validity limited" and moved the point estimate to about +5.6. The B5 machinery was archived out of eval-harness; it can be recovered at `1a5b79261` via `pull/8484/head`. | open: `#8497` |
| B8 fog of war + native blocking | `product-roadmap/SKILL.md` `## Where Work Lives on the Roadmap` › `### Not Yet Specified` / `### Out of Scope`, plus `gh issue edit --add-blocked-by` edges read by `next --frontier`. NOT adopted: map issue, `wayfinder:*` labels, claim act, sub-issue hierarchy. | `#8292` / PR `#8536` |
| B4 `grilling` frontier protocol for `brainstorm` §1.2 | **Not bundled, not shipped.** `git grep -i frontier origin/main -- plugins/soleur/skills/brainstorm/SKILL.md` finds only the roadmap blocked-by line. | none (remains advisory) |
| B10 `retro` categories for `compound` | **Not bundled, not shipped.** `null-guardrail`, `tool economy` and `information access` return 0 hits in `plugins/soleur/skills/compound/`. | none (remains advisory) |
| Inspire-only rows (two-axis review, docs "It's working if", `to-tickets` expand–contract, HTML report for agent-native-audit) | Unchanged. None were recommended for porting. | n/a |

**Stale sentences in the landed record, quoted verbatim:**

1. Overlap Matrix row: "Recommendations are **advisory only — nothing filed**; the operator decides what gets issued."
2. Key Takeaway 4: "its `wizard` skill is the missing implementation of **two standing Soleur hard rules** … and its `diagnosing-bugs` discipline is absent from `reproduce-bug` on all six mechanics checked." This is present tense and no longer true.
3. §4 Recommendations lead-in: "**All advisory — nothing has been filed; the operator decides what gets issued.**"
4. Scope note: "**No GitHub issues filed** — every recommendation above is advisory, per the audit's operating instruction."
5. §Attribution per-target list. It names `brainstorm/SKILL.md` and `compound/SKILL.md`, which took nothing, and `commands/go.md` / `skills/help/`, where the prose actually landed in `brainstorm-techniques/references/phase-boundaries.md`. It omits `operator-bootstrap`, `operator-rephrase`, `scripts/lib/operator-script.sh`, `kb-glossary`, `questionnaire-generate`, `authoring-levers.md`, `ticket-triage.md` and the `.openhands` mirror. NOTICE's "Used in:" list is the authoritative version.
6. The in-body grep evidence ("`grep -rn 'auto_command' plugins/soleur/` = 0 hits", "`grep -rn '\[DEBUG-' plugins/soleur/` returns **zero**", "`grep -rli questionnaire plugins/soleur/` = 0", "No glossary artifact exists in Soleur") was true on 2026-09-18 and is false now. It stays as dated evidence and is covered by the status section, not edited line by line.
7. The §3 Overlap Table `diagnosing-bugs` row's verdict "**theirs, decisively** | **0 of 6 mechanics present in Soleur**" is now false. Annotate it in place, because a reader scanning the table will not reach the status section first.

### Follow-up facts (re-derived; the feasibility subagent's claims were corrected)

- **8497:** the B5 machinery is **archived**, so a rerun is not "run the config". It needs four things: restore the generator, scorer, verdict module, tasks and battery from `1a5b79261`; validate the scorer against hand labels, with empty answers scored as missing, pre-registered; add a V1-discriminating scenario for `hr-never-write-to-claude-code-memory-claude`; and at least 48 tasks per arm. At the observed $48.85 / 648 calls ≈ $0.0754 per call, the same 3 arms × 3 models × 3 repeats at 48 tasks is 1,296 calls ≈ **$98**. The subagent's "$65" assumed 2 arms; the pre-registered design has 3 (positive / prohibition / none). The spend lands on the key `#8505` says is shared with production, and that key already ran out on 2026-09-21 during the smoke test. The no-list README excludes this case twice over: an entry records a refused **concept** with an `instead`, and it is "**Not a deferral**". `knowledge-base/project/specs/archive/20260921-162911-feat-one-shot-8290-invocation-axis-budget-relief/b5-eval-results.md` `### Disposition` already says no rejected-concepts entry is written. The result's home is ADR-236's considered-options table plus the results file.
- **8499:** the post-merge re-probe already ran: an issue comment on 2026-09-21 records "**PASS on Claude Code 2.1.278**", captured from the TUI in tmux with `--plugin-dir` against the merged tree. The local Claude Code is now **2.1.280**, a later release, so the issue's own cadence ("at each Claude Code release that touches skills or plugins") makes a re-probe due. Running it is read-only (nothing runs; input is cleared) and agent-doable in tmux on this host. No workflow in the repo installs the Claude Code CLI to drive a TUI. Automation has two obstacles. A CI TUI needs onboarding and trust pre-seeding plus a credential. And `claude -p` stream-json's init `slash_commands` is a **proxy**, not the TUI autocomplete property the upstream bug is about.
- **8486:** four sites are confirmed from the issue body: `delete.sh`, `create.sh` and `set-role.sh` use `read -p … ACK`, and `flip.sh` has `--confirmed`. The subagent said "no CI check restricts `.claude/settings.json` edits". That is wrong: PR 8284's own check list includes "Block destructive .claude/settings.json edits". There is no existing UserPromptSubmit per-turn slash-command marker. `.claude/hooks/` fire on Claude Code only, while Grok, Codex and Devin reach the same scripts through their own shells. Functional-discovery names Anthropic's `hookify` as prior art to evaluate before hand-writing the hook.
- **8505:** one `secrets.ANTHROPIC_API_KEY` is shared across workflows (`ci.yml`, `claude-code-review.yml`, `fix-constraints-stage-a.yml`, `scheduled-machinery-drain.yml`, `test-pretooluse-hooks.yml` — five). eval-harness reads `process.env.ANTHROPIC_API_KEY` from the session. The credit-balance error IS named server-side, but only on the cron path: `_cron-shared.ts` exports `ANTHROPIC_CREDIT_EXHAUSTED_RE = /credit balance is too low/i`, and the hourly `cron-anthropic-credit-probe.ts` emits `op=anthropic-credit-exhausted` to Sentry (the feasibility subagent's "no handler" claim was wrong, corrected by the COO pass). The production **request** path outside `server/inngest/` has no such mirror. Doppler secrets are Terraform-managed (`doppler_secret` resources in `apps/web-platform/infra/*.tf`). `ANTHROPIC_ADMIN_KEY` is read by `cron-anthropic-cost-report.ts` but is un-mintable on this individual account (ADR-108, `#6297`), and no Terraform resource manages it.
- **8548:** the rolling-calendar row reads "Within 2 weeks of PR #8536 merging" and PR 8536 merged 2026-09-22T11:09:51Z, so the post is due by **2026-10-06**. Status: Draft. No draft for this post exists under `knowledge-base/marketing/distribution-content/`. The row's "Sources:" cell lists "PR #8536 body + the 2026-09-22 roadmap-graph learning + NOTICE Bundles 1-5" and does not list the audit record, because it was not on main.

### Property List (Phase 0.6b)

- **P1.** On main, `knowledge-base/product/competitive-intelligence.md` carries the mattpocock/skills audit: the Tier 1 row, a Key Takeaway, and the audit body. The audit event NOTICE pins by SHA then has a readable record.
- **P2.** No sentence in the landed record asserts in the present tense a gap that has since closed. For every G#/B#, a reader can tell whether it shipped, where, in what form (including what was deliberately not adopted), or that it was never bundled.
- **P3.** The record's attribution guidance does not contradict `plugins/soleur/NOTICE`, the authoritative attribution list.
- **P4.** PR 8284 is mergeable against the current `origin/main` at merge time.
- **P5.** Each of the five follow-ups has a triage verdict with a concrete reason, visible outside this session in the PR body, plus an issue comment or native edge where an action was taken.
- **P6.** The public record describes a named third party, and its repository's metrics, in neutral
  terms: no insinuation about the star count and no "Soleur is ahead" flourish. The analytic
  ours/theirs/split verdicts remain (CLO and CMO).

### Cut List (Phase 0.6b)

- Rewriting the audit body's findings into present tense. P2 comes from a dated status section plus in-place annotation of the stale sentences. The audit is a point-in-time record: the Tier 1 sota-scan row and the `[Added YYYY-MM-DD]` tags are the precedent.
- Adding an `Inspired by` comment to `competitive-intelligence.md`, or a NOTICE "Used in:" entry for it. This serves no property. The file is commentary that quotes attributed excerpts, not adapted prose. NOTICE's own carve-out says "Nothing under knowledge-base/ carries the comment at all", and it sits outside the plugin payload.
- Re-running `peer-plugin-audit` against upstream. Upstream is 0 commits ahead of the audited SHA.
- Updating the "Soleur catalog snapshot" line. It is labelled "enumerated at invocation", so it is dated evidence. Today's counts (102 skills / 68 agents / 3 commands / 98 rule ids) go only in the status section's one-line delta.
- A no-list entry for B5. The no-list README forbids it (see 8497 above).
- Plan-review cuts (DHH and code-simplicity converged; applied as Mechanical):
  - the catalog-delta line, the wording-revision log and the upstream-drift header line (git history
    records all three, and no property needs them);
  - the in-session `#8499` TUI re-probe (no property of this PR needs it; it belongs to `#8499`'s own
    cadence);
  - the post-merge `#8548` comment (the `content-strategy.md` Sources cell is what the content
    pipeline reads);
  - the draft's line-count AC (157 lines against a 500-line cap), its markdown-lint AC (the lefthook
    hook already gates staged `.md` files), and its merge-gate AC (ship's gate).
  - *Deepen-plan reversal:* the `#8548` post-merge comment is **restored**. Spec-flow found that no
    skill or workflow reads the `content-strategy.md` Sources cell — whoever runs `soleur:go #8548`
    reads the issue — so the cut's premise was false. A one-line `#8499` comment is also added so
    the verdict lands where that issue's owner looks.
- Filing issues for B4 and B10. `wg-when-deferring-a-capability-create-a` says to document in place, and the audit record *is* that place. Neither passes the `wg-defer-only-after-inline-triage` triple test, because neither has a concrete trigger.

### Applicable learnings

- `2026-09-18-re-verifying-a-stale-audit-and-six-measurement-errors-of-my-own.md`: re-verify the **mechanism** claims, not just the numbers, because a mechanism can be replaced without its old name surviving. Applied to G1: the `auto_command` grep now hits because `operator-bootstrap` exists, not because the old gap was patched in place. Applied to B9: `Undo:` replaced the recommended `Door:`.
- `2026-07-27-instrument-misreports-own-coverage-and-subagent-counts-are-claims.md`: the subagent's reconciliation table and feasibility brief each carried errors (listed above). Every row in this plan was re-derived with a planner-run command.
- `2026-04-21-peer-plugin-audit-brainstorm-patterns.md`: check the audit's framing against the CI file's existing conventions (tier placement, `[Added …]` tags, backticked issue refs per `peer-plugin-audit.md`).
- `2026-05-15-deepen-plan-must-grep-cited-attribution-on-main.md`: every "closed by PR N" cell above came from `gh issue view --json closedByPullRequestsReferences`, and every content anchor from `git grep … origin/main`.

### Conventions carried

- `competitive-analysis/references/peer-plugin-audit.md`: report body ≤ 500 lines (today 157), and every `#NNNN` wrapped in backticks.
- `cq-cite-content-anchor-not-line-number`: the status section cites headings and phrases, never line numbers.
- Commit with `LEFTHOOK_EXCLUDE=bun-test`. Never run `scripts/test-all.sh`. No `AGENTS.rules.md` edit in this PR.

## Research Reconciliation — Spec vs. Codebase

| Claim in the invocation | Reality on origin/main | Plan response |
|---|---|---|
| "All 5 implementation bundles are merged" (the parenthetical names four) | Five closed bundles: `#8287`, `#8288`, `#8289`, `#8290`, `#8292`. The parenthetical leaves out `#8288`, the reproduce-bug / constraint-scaffold bundle (PR `#8352`). | The status section lists all five, with the closing PR for each. |
| The record is "the provenance anchor every bundle's NOTICE points at" | NOTICE pins the audit by SHA and date. It does not name `competitive-intelligence.md`. | Land the record so it exists on main. Do not edit NOTICE: it ships in the plugin payload, and a `knowledge-base/` path would dangle for plugin installs. |
| "the wizard/template.sh gap … may now be stale" | Closed by `#8297`: `operator-bootstrap/` plus `scripts/lib/operator-script.sh`. | Status row for `#8287`. Annotate the Tier 1 row and Key Takeaway 4. |
| "the reproduce-bug 0-of-6 diagnosing-bugs finding … may now be stale" | 6 of 6 present, closed by `#8352`. | Status row for `#8288`. Annotate the Tier 1 row, Key Takeaway 4, and the §3 `diagnosing-bugs` row in place. |
| "the Overlap Matrix row may now be stale" | Stale in five places: "no implementing template", "`auto_command` … = 0 hits", "**0 of 6** present", "advisory only — nothing filed", and the attribution pointer. The star-count wording also needs changing. | Phase 1 step 2. |
| "Mergeability — recompute after the rebase" | Remote head `41ea2b6a7d` is BEHIND and MERGEABLE. The local rebase `35bf829563` is content-identical, still merges cleanly against `origin/main` `fc7b7dc2de`, and is **unpushed**. | Phase 4: re-run `merge-tree`, push with `--force-with-lease`, then let ship sync before merge. |
| "#8499 … Cheap; wants a scheduled check" | A manual re-probe is cheap. A scheduled check is not: the property is TUI autocomplete, and `claude -p`'s `slash_commands` list is only a proxy for it. | Defer both. The 2.1.280 re-probe is due under `#8499`'s own cadence. |
| "#8497 … a decision to drop it and record that in the rejected-request register" | The no-list README excludes deferrals and mechanism refusals, and the archived B5 results file's `### Disposition` already says no entry is written. | Take neither of the two offered options: no rerun now, and no no-list entry. Add the native blocked-by edge instead. |

## Proposed Solution

This PR stays **docs-only**. It reconciles the audit record in place, and the audit remains a dated
point-in-time record. The plan adds a short status section at the top of the audit body, so a reader
sees what shipped before any 2026-09-18 claim. It corrects the sentences that still make present-tense
claims that are no longer true. It replaces the stale per-target attribution list with a pointer to
NOTICE, and it neutralizes the star-count and "Soleur is ahead" wording (P6). The five open issues
get triage verdicts. Every verdict leaves a marked trace on its issue (one edge on `#8497`; comments on `#8497`, `#8499`,
`#8486`, `#8505`, and on `#8548` after merge), and none of these gates the PR.

### Triage verdicts for the five open issues

| Issue | Verdict | Reason | In-session action |
|---|---|---|---|
| `#8497` B5 revisit | **(c) defer.** Keep it open as the `revisit_if` tracker. | A rerun first needs four things: the archived machinery restored from `1a5b79261`, a scorer validated against hand labels with empty answers scored as missing, a V1-discriminating scenario, and at least 48 tasks per arm. That is about **1,296 calls, roughly $98**, billed to the key `#8505` says production shares, and that key ran out on 2026-09-21. The other suggested route, a no-list entry, is a mis-keying: the README says an entry records a refused *concept*, and is "Not a deferral". The result already lives in ADR-236 and the archived results file. | `gh issue edit 8497 --add-blocked-by 8505`. The flag is confirmed in `gh issue edit --help` ("--add-blocked-by number  Add 'blocked by' relationships"). Add a one-line comment giving the cost and the reason for the edge. |
| `#8499` ADR-236 re-probe | **(c) defer**, both the manual re-probe and the automation. | The last probe passed on 2.1.278. The local build is 2.1.280, so the next re-probe is due under `#8499`'s own cadence ("at each Claude Code release that touches skills or plugins"), but no property of *this* PR needs it (plan-review cut). Automation would need three things: a TUI running in CI, onboarding and trust pre-seeded, and a credential. That credential should be the separate CI key `#8505` creates, not another consumer of the shared production key. `claude -p` init `slash_commands` is a proxy, not the property. | Post a one-line comment: the 2.1.280 re-probe is due, and automation is deferred behind `#8505`. |
| `#8486` agent-drivable confirmations | **(c) defer** to its own `soleur:one-shot` run, not a sibling PR. | This is a security control, not docs, and its assembly is wider than the issue says. Only `flag-delete` and `user-set-role` are user-invoked. `flag-create` and `flag-set-role` are **model-invocable** (`flip.sh --confirmed`, three bypasses), so a guard set derived from the user-invoked frontmatter misses the biggest hole. `.claude/hooks/` fire only on Claude Code, and the Devin cloud block says "hooks do not fire in cloud". The fix needs its own Guard Contract, threat model and security review. | Post a scope-correction comment. The guard set must be "scripts that mutate production", not the user-invoked set. State the cross-harness coverage explicitly. Name Anthropic's `hookify` plugin as prior art to evaluate. |
| `#8505` CI/eval key separation | **(c) defer** to its own `soleur:one-shot` run. This is the next security item in Phase 4, and `#8497` is blocked on it. | It mixes request-path code, Terraform secret wiring and one console step. Two facts are new. First, the hourly `cron-anthropic-credit-probe` already emits `op=anthropic-credit-exhausted` and exports `ANTHROPIC_CREDIT_EXHAUSTED_RE`, so the gap is the production **request** path. Second, the Admin-API route to minting a key is closed, because this is an individual account (ADR-108, `#6297`). The console step is `automation-status: UNVERIFIED`: the 8505 run MUST attempt Playwright under an authenticated console session before any human handoff. | Post a comment with exactly those two facts and the UNVERIFIED marker. |
| `#8548` retrospective | **(a)** add a one-cell source pointer in THIS PR, then **(c) defer the post** to the content pipeline after 8284 merges. | The post should link the landed record as its provenance, and fact-checker needs that link to exist. The window runs until **2026-10-06**. A 1,500–2,000-word post is its own review surface: content-writer, fact-checker and feature-tweet. | After merge, comment with the permalink `https://github.com/jikig-ai/soleur/blob/main/knowledge-base/product/competitive-intelligence.md#reconciliation-status-2026-09-23` and the CMO framing: no star count, no competitive comparison, credit Matt Pocock by name. The Phase 2 cell edit is secondary, because no workflow reads it. |

**Filed: none.** This PR files no issue. B4 and B10 are recorded in the status section as "not
bundled — remains advisory". They were not bundled by the founder, and no concrete trigger exists, so
they fail the `wg-defer-only-after-inline-triage` triple test. The audit record is the in-place
documentation that `wg-when-deferring-a-capability-create-a` asks for. A revisit-trigger wording
proposal is in `decision-challenges.md` (T3).

## Implementation Phases

### Phase 1 — Reconcile `knowledge-base/product/competitive-intelligence.md`

The audit section runs 157 lines today, against a 500-line cap.

1. **Frontmatter:** set `last_updated: 2026-09-23`. Leave `last_reviewed: 2026-07-04` alone, because
   it tracks the full-scan clock.
2. **Tier 1 Overlap Matrix row** (`**mattpocock/skills** [Added 2026-09-18]`):
   - Tag it `[Added 2026-09-18; reconciled 2026-09-23]`.
   - Annotate the present-tense gap claims in place. After "**and no implementing template for either**
     (`grep -rn 'auto_command' plugins/soleur/` = 0 hits; …)" add
     "*[since shipped as `operator-bootstrap` — `#8287`]*". After "**0 of 6 present** in `reproduce-bug`
     + `test-fix-loop`" add "*[now 6 of 6 — `#8288`]*".
   - Replace "Recommendations are **advisory only — nothing filed**; the operator decides what gets
     issued." with a sentence saying five bundles were filed and shipped: `#8287`, `#8288`, `#8289`,
     `#8290`, `#8292`. Use **backticked bare references only**, not the sota-scan row's `[#N](url)`
     link form. Point to the audit's status section.
   - Replace "MIT → prose adaptable with the attribution comment in the audit body" with
     "MIT → per-file attribution is recorded in `plugins/soleur/NOTICE`".
   - Star-count wording (CLO). In the row's `**Stars/forks …**` sentence, drop "and implausible for the
     category", "so that is ~265k stars in 7.5 months", and the "~60,000" newsletter clause. Keep the
     gh-reported figure, the 2026-02-03 creation date and "Do not cite the figure as fact".
   - Put one note at the start of the row's third cell: "*[Reconciled 2026-09-23: every gap this cell
     names has since shipped in whole or part — see the audit's §Reconciliation status.]*" That covers
     items (3)–(5) and the "Four genuine capability gaps" sentence without annotating each one.
3. **Key Takeaway 4:** keep the `4. **[2026-09-18]` prefix unchanged, because AC4 and AC6 anchor on it. Keep the insight ("a mechanic for a rule we already wrote but never
   implemented"). Put its evidence in the past tense and cite what closed it: `operator-bootstrap`
   (`#8287`), and "now 6 of 6" diagnosing-bugs mechanics in `reproduce-bug` (`#8288`). An
   outcome-framing alternative is in `decision-challenges.md` (T1).
4. **Audit body header block:** after the Fork note, add `**Reconciled:** 2026-09-23 against origin/main — read
   §Reconciliation status first`.
5. **New `#### Reconciliation status (2026-09-23)`**, placed **before** `#### 1. Inventory Summary`.
   Use one row per bundle, plus rows for the items outside the bundles. Keep it short, and send
   "deliberately not adopted" detail to NOTICE rather than restating it (code-simplicity):

   | Items | Status | Closed by |
   |---|---|---|
   | G1, G5, B9, B12 | Shipped. B12 in part: the context tree shipped, the `go`/`help` flow map did not. B9 as `Undo:` + `Blast Radius:`, with no Door verdict. | `#8287` → PR `#8297` |
   | B1, B2, B3, B7 | Shipped: 6 of 6 diagnosing-bugs mechanics in `reproduce-bug`, and bite-proof in `constraint-scaffold` | `#8288` → `#8352` |
   | G2, G3, G4, B11 | Shipped: the no-list, glossary, `questionnaire-generate`, triage pre-checks | `#8289` → `#8405` |
   | B6, invocation axis, §1 skill-creator defects | Shipped: `authoring-levers.md` and ADR-236 (8 user-invoked skills); defects fixed | `#8290` → `#8484` |
   | B5 | Inconclusive: `AGENTS.rules.md` not rewritten | open `#8497` |
   | B8 | Shipped | `#8292` → `#8536` |
   | B4 | not bundled — remains advisory | none |
   | B10 | not bundled — remains advisory | none |

   Write every ID **individually**, never as a range such as "B1–B3", because AC2 matches IDs one by
   one. Add one sentence: "What each bundle deliberately did not adopt is recorded per bundle in
   `plugins/soleur/NOTICE`."

   Close with an "Open issues" line: `#8486`, `#8497`, `#8499`, `#8505`, `#8548`. The `#8486` entry
   must say that ADR-236's invocation axis "is a context-budget and discoverability measure, not a
   security control", so the audit cannot be read as having closed that risk.
6. **§1 Stars/forks bullet:** rewrite in the CLO's wording, adding the 2026-09-23 re-read.
   Suggested text: "**Stars / forks (gh-reported, not independently verified):** 264,914 / 22,339 on
   2026-09-18; 268,223 / 22,623 on 2026-09-23; repo created 2026-02-03. The figure is unusually high
   for the repo's age, so it is recorded for context only: do not cite it downstream, and confirm it
   against a second source before it informs any decision." A shorter CMO variant is in
   `decision-challenges.md` (T5).

   > **Superseded 2026-09-23 (review, PR 8284):** replaced by the GitHub-API snapshot wording in competitive-intelligence.md §1 Stars / forks; the earlier phrasing read as doubt about a named third party's repo.

7. **§1 "Two defects found in Soleur" bullet:** append "*[Fixed 2026-09-21 by `#8484`.]*"
8. **§2 "Explicitly NOT worth taking", the `setup-pre-commit` bullet:** change "**Reject — Soleur is
   several years ahead here.**" to "**Reject — Soleur's hooks fleet already covers this in more
   depth.**". The rationale is tone (P6). It is not the brand guide's X-engagement guardrail, which
   does not govern competitive-intelligence records. The §3 ours/theirs/split verdicts stay. The CMO's
   wording variant is T4.
9. **§4 patterns table, the `agents/openai.yaml` row:** change "**reject** — Soleur is ahead: a
   runtime adapter …" to "**reject** — covered by `plugins/soleur/lib/harness.ts`: a runtime adapter …"
   (CMO, parallel flourish).
10. **§3 Overlap Table, the `diagnosing-bugs` row:** annotate the verdict cell in place with
    "*[2026-09-23: now 6 of 6 present in Soleur — `#8288`]*".
11. **§4 Recommendations lead-in:** replace "**All advisory — nothing has been filed; the operator
    decides what gets issued.**" with "*[Reconciled 2026-09-23]* Filed as five bundles; see
    §Reconciliation status." Leave the bundle paragraphs unchanged, as the record of what was
    recommended. Their "0 of 6", "never built the template" and "keeps **no glossary**" wording is
    covered by this lead-in, which sits directly above them.
12. **§Attribution:** keep the comment-format line and the Dex Horthy / `pr/CREDITS.md` paragraph.
    Replace the per-target bullet list with one sentence: "The authoritative per-file record of what
    took peer prose is the mattpocock/skills entry in `plugins/soleur/NOTICE` ('Used in:' plus the
    per-bundle 'Portions adopted' paragraphs); files under `knowledge-base/`, this record included,
    carry no comment by NOTICE's own rule."

    > **Superseded 2026-09-23 (review, PR 8284):** NOTICE states a Bundle 3 fact, not a rule; the shipped sentence says this record carries no comment because it is commentary quoting short excerpts and sits outside the plugin payload.

13. **Convergence risk, "The star figure" bullet:** replace "it is implausible for the category and
    must not be laundered into a fact" with "Recorded as **gh-reported and unverified** (see §1 Stars /
    forks); do not cite it downstream." Keep the verify-before-next-scan sentence, and do not refer back
    to the newsletter figure in the "Distribution" bullet above it.

    > **Superseded 2026-09-23 (review, PR 8284):** replaced by the GitHub-API snapshot wording in competitive-intelligence.md §1 Stars / forks; the earlier phrasing read as doubt about a named third party's repo. The newsletter figure was dropped from the Distribution bullet at the same review.

14. **Scope note:** replace "**No GitHub issues filed** — every recommendation above is advisory, per
    the audit's operating instruction." with "The audit itself filed nothing; five bundles were filed
    afterwards and all shipped by 2026-09-22 (see §Reconciliation status)."
15. **Now-false `frontier` claims (spec-flow P0).** The §3 `grilling` row says "No `frontier` concept
    exists anywhere in `plugins/soleur/`." and the §4 B4 row says "No `frontier` concept exists in
    `plugins/soleur/`." Both are false since `product-roadmap next --frontier` shipped (`#8292`).
    Rewrite each in place as "No *grilling* frontier exists in `brainstorm` (a roadmap `next --frontier`
    shipped via `#8292`)." B4 itself stays not bundled.
16. **Table lead-ins (spec-flow P0).** Directly under the §2 lead-in ("Four capability gaps only. …"),
    the §3 lead-in ("Semantic mapping, not name mapping. …") and the §4 improvements lead-in ("Each row
    names **the exact file to edit** …"), add the line "*[Reconciled 2026-09-23 — cells below describe
    the tree on 2026-09-18; see §Reconciliation status for what shipped.]*" A reader who scans a table
    then meets the pointer before any stale cell ("Soleur has **no generator**", "Confirmed absent",
    "all zero hits", …) without each cell being annotated.

### Phase 2 — `knowledge-base/marketing/content-strategy.md` (one cell)

Find the rolling-calendar row "Within 2 weeks of PR #8536 merging | Draft 'Your Roadmap Can't Tell
Undecided from Forgotten' …". In it:

- Extend the "Sources:" list with "the mattpocock/skills audit record in
  `knowledge-base/product/competitive-intelligence.md` (§Reconciliation status — link its anchor, not
  the file top)".
- Add "no star count; no competitive comparison".

Change nothing else in the file.

### Phase 3 — In-session actions on the five issues (GitHub writes; they do not gate PR 8284)

Every comment starts with the marker `<!-- pr8284-triage -->`, so AC10 can select exactly these
comments and a re-run can skip issues that already carry one (check first with
`gh api repos/jikig-ai/soleur/issues/<N>/comments --jq '[.[] | select(.body | contains("pr8284-triage"))] | length'`).

1. `#8497`:
   - Run `gh issue edit 8497 --add-blocked-by 8505`.
   - Post a one-line comment giving the rerun cost (about $98) and the reason for the edge: the rerun
     would bill the shared production key.
2. `#8486`: post the scope-correction comment described in the triage table.
3. `#8505`: post the two-fact comment and the `automation-status: UNVERIFIED` marker described in the
   triage table.
4. `#8499`: post the one-line comment: the re-probe is due on 2.1.280 (last PASS 2.1.278), and
   automation is deferred behind `#8505`.
5. `#8548`, **after 8284 merges**: post the permalink to the `#reconciliation-status-2026-09-23` anchor
   and the CMO framing guidance. Confirm the anchor slug from the rendered heading first:
   `gh api repos/jikig-ai/soleur/contents/knowledge-base/product/competitive-intelligence.md -H 'Accept: application/vnd.github.html' | grep -o 'id="user-content-reconciliation-status[^"]*"'`.

### Phase 4 — Ship PR 8284

1. Commit with `LEFTHOOK_EXCLUDE=bun-test`. The markdown-lint hook still runs on the staged `.md`
   files.
2. Run `git fetch origin main && git merge-tree --write-tree origin/main HEAD`. It must exit 0.
3. Read the remote head with `git ls-remote origin refs/heads/feat-ci-mattpocock-skills-audit`, then
   push with `git push --force-with-lease=feat-ci-mattpocock-skills-audit:<that sha>`.
   - The advisor suggested a merge-commit sync instead. Rejected: the reconciliation commit must be
     pushed either way, and any push re-queues CI.
4. Run `soleur:ship`. It authors the PR body, full-replacing the stale one, and syncs with main before
   merge. ship reads this plan, so the body inherits:
   - the triage table, under the heading "Triage of the five open issues";
   - `Filed: none`;
   - `Refs #8497 #8499 #8486 #8505 #8548`, never `Closes`;
   - `## Merge Danger` with both mandatory fields: `**Undo:**` (ask Soleur "undo PR #8284", i.e. revert
     the squash commit) and `**Blast Radius:** docs`.

   The body must not present the `#8505` console step as a tracked human step. That step is
   `automation-status: UNVERIFIED`, and `#8505` is `type/security`, not a deferred-automation chore. Cite
   it only as `Refs #8505` inside the triage table.

## Files to Edit

- `knowledge-base/product/competitive-intelligence.md` (Phase 1)
- `knowledge-base/marketing/content-strategy.md` (Phase 2, one table cell)

## Files to Create

- none. The plan, `tasks.md` and `decision-challenges.md` are this pipeline's own artifacts.

## Non-Goals

- No NOTICE edit, no `Inspired by` comment, no `AGENTS.rules.md` edit, no code.
- No B5 rerun and no no-list entry. No fix for `#8486` or `#8505` this session: each gets its own
  pipeline run, and `#8497` is gated on `#8505` through the native edge.
- No `#8499` re-probe this session.
- No re-audit of upstream (0 commits of drift) and no specialist cascade.

## Open Code-Review Overlap

One open code-review issue names `knowledge-base/marketing/content-strategy.md`: `#3649`, a PR-A2
content brief scheduled for PR-C merge. **Acknowledge.** It covers a different calendar row and a
different concern, and this plan's one-cell edit does not touch it. No open code-review issue names
`knowledge-base/product/competitive-intelligence.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a public competitive-intelligence record that
  still tells a reader, in the present tense, that Soleur has no operator-script generator and no
  bug-reproduction discipline, when both shipped days earlier. A founder or contributor reading it
  would underrate the product and could re-file work that is already done.
- **If this leaks, the user's data / workflow / money is exposed via:** no user data is involved;
  the file is public analysis of a public MIT repository. The remaining exposure is reputational: the
  record names a real third party, Matt Pocock, and its current wording implies star inflation.
  Phase 1 steps 2, 6, 8, 9 and 13 close that.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: docs-only edits to two knowledge-base files that carry no user data and sit on no sensitive path.`

## Acceptance Criteria

All commands run from the worktree root. `F=knowledge-base/product/competitive-intelligence.md`.

- [x] **AC1** (P2). `grep -c '^#### Reconciliation status (2026-09-23)' "$F"` = 1. In the output of `grep -n -e '^#### Reconciliation status' -e '^#### 1\. Inventory Summary' "$F"`, the status heading's line number must be smaller.
- [x] **AC2** (P2). Every ID appears in the status section, and B4 and B10 are marked not bundled. Extract the section with `rs=$(mktemp); awk '/^#### Reconciliation status/{f=1;next} /^#### 1\. Inventory Summary/{f=0} f' "$F" > "$rs"`. Then `for id in G1 G2 G3 G4 G5 B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11 B12; do grep -qE "(^|[^0-9A-Za-z])$id([^0-9]|$)" "$rs" || echo "MISSING $id"; done` prints nothing. `grep -E '(^|[^0-9A-Za-z])B4([^0-9]|$)' "$rs" | grep -ci 'not bundled'` ≥ 1, and the same check for `B10` ≥ 1.
- [x] **AC3** (P2, P6). Each of these returns 0: `grep -c 'advisory only — nothing filed' "$F"`, `grep -c 'All advisory — nothing has been filed' "$F"`, `grep -c 'No GitHub issues filed' "$F"`, `grep -c 'Soleur is several years ahead' "$F"`, `grep -c 'Soleur is ahead' "$F"`, `grep -c 'fastest-starred' "$F"`, `grep -c 'laundered' "$F"`, `grep -c 'implausible' "$F"`, `grep -cE 'No .frontier. concept exists' "$F"`. Also, the table pointer is present: `awk '/^## Peer-Plugin Audit — mattpocock/,/^## Tier 2/' "$F" | grep -c 'Reconciled 2026-09-23'` ≥ 4 (three table lead-ins plus the §4 Recommendations lead-in; the header's `**Reconciled:** 2026-09-23` does not match this literal and is not counted).
- [x] **AC4** (P2). The Tier 1 row and Key Takeaway 4 carry the corrections:
  - `grep -E '^\| \*\*mattpocock/skills\*\*' "$F" | grep -c '#8287'` ≥ 1;
  - `grep -E '^\| \*\*mattpocock/skills\*\*' "$F" | grep -c 'now 6 of 6'` ≥ 1;
  - `grep -E '^4\. \*\*\[2026-09-18\]' "$F" | grep -c '6 of 6'` ≥ 1;
  - `grep -E '^\| .diagnosing-bugs. \|' "$F" | grep -c 'now 6 of 6'` = 1 (the `.` matches the cell's backticks).
- [x] **AC5** (P3). §Attribution points at NOTICE and no longer lists per-target paths:
  - `awk '/^##### Attribution/,/^#### Convergence risk/' "$F" | grep -c 'plugins/soleur/NOTICE'` ≥ 1;
  - the same range piped through `grep -c 'skills/compound/SKILL.md'` = 0;
  - `grep -E '^\| \*\*mattpocock/skills\*\*' "$F" | grep -c 'plugins/soleur/NOTICE'` ≥ 1.
- [x] **AC6.** Every issue or PR reference in the edited regions is backticked, per `peer-plugin-audit.md`'s backtick instruction (the rule id that file cites, `cq-prose-issue-ref-line-start`, is retired — its body now lives in the constitution). `{ grep -E '^\| \*\*mattpocock/skills\*\*|^4\. \*\*\[2026-09-18\]' "$F"; awk '/^## Peer-Plugin Audit — mattpocock/,/^## Tier 2/' "$F"; } | grep -nE '(^|[^`])#[0-9]{4}'` prints nothing.
- [x] **AC7.** Only knowledge-base files change, plus one review-driven line in `plugins/soleur/NOTICE` (amended at review: its Bundle 3 sentence "Nothing under knowledge-base/ carries the comment at all" was false against a generated `bootstrap.sh`, so it now reads "No Bundle 3 record under knowledge-base/ carries the comment"): `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` prints only `plugins/soleur/NOTICE`. That rules out `plugins/`, NOTICE and `AGENTS.rules.md`. Pipeline-written specs, learnings and the plan are allowed.
- [x] **AC8.** Exactly one Sources pointer is added: `grep -c 'competitive-intelligence.md' knowledge-base/marketing/content-strategy.md` = 3, against 2 on `origin/main`.
- [ ] **AC9** (P1, post-merge). `git show origin/main:"$F" | grep -c '^## Peer-Plugin Audit — mattpocock/skills'` = 1.
- [ ] **AC10** (P5; a session AC, not a merge gate). The in-session issue actions landed:
  - `gh api repos/jikig-ai/soleur/issues/8497/dependencies/blocked_by --jq '[.[].number]'` contains 8505;
  - for each N in 8497, 8499, 8486 and 8505 (and 8548 after merge), `gh api repos/jikig-ai/soleur/issues/<N>/comments --jq '[.[] | select(.body | contains("pr8284-triage"))] | length'` = 1: exactly one marked comment, so there are no duplicates.
- [ ] **AC11** (P5). `gh pr view 8284 --json body --jq .body` contains `Filed: none`, `Triage of the five open issues`, `**Undo:**` and `**Blast Radius:** docs`, and does not contain `No issues filed`. This can still be checked after merge, and `gh pr edit` works on a merged PR if it fails.

## Domain Review

**Domains relevant:** Marketing, Engineering, Operations, Legal. Product was assessed as relevant,
since CPO owns the record, but sits at Product/UX tier NONE: no user-facing UI surface is created or
modified.

### Marketing

**Status:** reviewed
**Assessment:** Brand risk is low to moderate, because the repo is public and the record names Matt
Pocock. The CMO's three wording changes are adopted as Phase 1 steps 2, 6, 8 and 13. The `#8548`
defer verdict is confirmed, with the Sources cell (Phase 2) pointing at the status anchor. The
plan-review CMO pass added the `openai.yaml` "Soleur is ahead" fix (step 9). It also noted that the
brand guide's "never what others lack" rule does not govern CI records, so the ours/theirs verdicts
stay.

### Engineering

**Status:** reviewed
**Assessment:** Land as docs-only, with no sibling PR. `#8486` is deferred, with the
model-invocable-scripts scope correction posted as a comment. `#8505` is deferred. `#8497` gets the
blocked-by edge. B4 and B10 are documented in the record as not bundled. No ADR or C4 impact, because
this is a record, not a decision.

### Operations

**Status:** reviewed
**Assessment:** `#8505` is deferred. Terraform already manages both `doppler_secret` and
`github_actions_secret`, and `cron-anthropic-credit-probe` already covers hourly detection. The
Admin-API mint route is closed (ADR-108, `#6297`), while the console route stays UNVERIFIED until a
Playwright attempt. The `expenses.md` "Anthropic API (CI)" row gets its ceiling in the `#8505` run.
The roughly $98 rerun is recorded when `#8497` runs.

### Legal

**Status:** reviewed
**Assessment:** No comment and no NOTICE change for the record: it is commentary with short
attributed excerpts, inside NOTICE's knowledge-base carve-out. The per-target list misattributed in
both directions, so it is replaced with a NOTICE pointer. The star-count wording carried tone risk
rather than legal exposure, and the CLO text is adopted. No blocker.

## Test Scenarios

- Given the reconciled file, when a reader opens the audit section, then the first subsection is
  `#### Reconciliation status (2026-09-23)` (AC1).
- Given AC3's absence greps, when any retired phrase is restored, then exactly that grep returns 1.
  This is a mutation check: each grep names the file, so none can pass on empty stdin.
- Given a status table that writes "B1–B3" as a range, when AC2 runs, then it prints `MISSING B2`.
  That is the guard against range notation.
- Given the Tier 1 row still says "0 of 6" with no annotation, AC4's second grep returns 0.
- Given `main` moves after the force-push, ship re-syncs before merge and never merges from a BEHIND
  state.

## Dependencies & Risks

- **Force-push over a reviewed head.** The rebase replaces `41ea2b6a7d`. The lease pins the expected
  remote SHA, so a concurrent push fails instead of being clobbered.
- **CI backlog.** Runs on the old head go stale. Expect long queues and at least one re-sync.
- **Subagent claims.** Both research briefs carried errors. Every fact here was re-derived with a
  planner-run command, and a deepen pass must not re-import the uncorrected claims.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty, holds only placeholder text, or omits the threshold
  fails `deepen-plan` Phase 4.6. This one declares `none`, with a scope-out reason.
- **The absence greps (AC3) must not collide with legitimate prose.** No new text may quote a retired
  phrase, for example "we removed 'implausible'". Re-run AC3 after Phase 1.
- **Write status-table IDs individually.** A range like "B1–B3" hides B2 from AC2.
- **Every AC grep names its file operand.** `grep -c X` with no file reads stdin and prints 0, so an
  absence check without a file always passes.
- **The `#8505` console key-mint is `automation-status: UNVERIFIED`, not "operator-only".** Do not
  write it as a proven human step in the PR body or in the issue comment.
- **Do not re-import the subagent errors listed in Research Insights:** $65, 9 flagged skills, B4
  closed, operator-rephrase under `#8289`, and "no CI check on settings.json edits".
- `knowledge-base/project/` is excluded from markdownlint (`.markdownlintignore`), so the plan and
  `tasks.md` are not linted. The two in-scope files are linted by the lefthook markdown-lint hook at
  commit, which is why the draft's markdown-lint AC was cut.
