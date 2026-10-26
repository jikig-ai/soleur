---
title: "feat(harness): WikiSkill Phase 2 - gated new-skill creation"
date: 2026-10-26
slug: wikiskill-phase-2-gated-new-skill-creation
branch: feat-one-shot-10550-wikiskill-phase-2-new-skill-creation
issue: 10550
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(harness): WikiSkill Phase 2 - gated new-skill creation

## Overview

Phase 2 of the WikiSkill work split out of #8281 (issue #10550, `Ref` only, never `Closes`). It lets
the weekly `cron-compound-promote` proposer open a human-reviewed DRAFT PR that creates a brand-new
skill when a mature pattern in `knowledge-base/project/patterns/` has no skill that owns it. The
issue names four gates: free skill-description budget first, markdown-only skills with a required
`PURPOSE.md`, `soleur:skill-security-scan` on every generated skill, and no net growth in total
description words.

The arm is **dark-launched**, following the Phase 1 shape (ADR-300): it is reachable only on a manual
trigger with `input: "patterns"` AND `allow_create: true` (default off). The scheduled path and a
manual `input: "corpus"` run are unchanged. **This PR creates no skill in production.** A live create
is a separate, operator-authorized production act and is out of scope (CTO ruling T8).

**Evidence used (not edited, not closed, not commented on).** Draft PRs #11230 and #11231, opened by the
proposer on 2026-10-26 from the pattern index, satisfy the issue's re-evaluation criterion 2. Both are
`Tier: skill` PATCHES to existing skills (`git-worktree/SKILL.md` +1 bullet, `pencil-setup/SKILL.md`
+2 bullets). They prove the loop is visible and the prefer-patch path works; neither exercised a create.
They are used here as **synthesized** regression fixtures (cluster hash plus patch target only; no real
content copied, per `cq-test-fixtures-synthesized-only`): a cluster whose nearest skill is
`git-worktree` or `pencil-setup` must be refused as `prefer-patch`, not turned into a create.

**What changes, in six commits (CTO ruling T1 named three groups: budget freeing = commits 1-2, pure modules = 3-4, wiring = 5-6; cut line PR A = 1-2, PR B = 3-6):**

1. **Free the budget first.** Five human-reviewed description trims free 34 words, the cap constant is
   LOWERED from 2443 to the measured pre-trim total (2436), and the five Cursor stubs that embed those
   descriptions are regenerated. The cap is lowered, never bumped.
2. **Contracts and pure modules.** An ADR-092 create-only amendment, an ADR-300 addendum, the
   `PURPOSE.md` template, and two server modules (pure rendering/validation, plus the spawn-based gates).
3. **Wiring.** One `create-propose` step in the handler, one persistence call in `exactPaths` mode, one
   closed-vocabulary marker addition, runbook rows, register notes.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #10550 is OPEN. Its criterion 1 (Phase 1 shipped) holds: PR #10970 (`cf468c6d84`) is on `origin/main`;
  ADR-300 is `adopting`; `compound-promote-patterns.ts`, `compound-promote-ledger.ts` and 7 pattern pages
  exist. #8293 still shows OPEN with no closing PR (it is the flip tracker); that does not block this plan.
- Criterion 2 holds: #11230 and #11231 are open, `isDraft: true`, branches `self-healing/auto-<hash>-2026-10-26`.
  The cron default is still `input: corpus` (ADR-300); which input path produced them was not verified and does
  not matter here, because the create arm is gated independently.
- **Stale references in the issue:** the brainstorm and spec paths cited by the issue have since been archived
  to `knowledge-base/project/brainstorms/archive/20260918-160549-2026-09-18-wikiskill-skill-evolution-brainstorm.md`
  and `knowledge-base/project/specs/archive/20260918-160549-feat-wikiskill-skill-evolution/spec.md`. This plan
  cites the archive paths. The code comment at `cron-compound-promote.ts` (~L480) labels new-file creation
  "Phase 2 (#8293)"; the tracking issue is #10550 and the comment is updated in the wiring commit.
- Off-limits issues #10551 (Phase 3), #10552, #8443 were read nowhere in planning beyond the state check and
  are not touched or commented on. #8274 is CLOSED by #8276.
- **ADR corpus (mechanism check):** ADR-092 `## Decision` item 1 already calls "a new skill section" the safe
  primitive; its 2026-10-19 amendment covers only in-place insertion into an existing target, so a
  create-only amendment is required (not a rejected alternative). ADR-054 (`safeCommitAndPr` sole write path)
  and ADR-236 (budget counts model-visible skills only) are honoured, not changed. ADR-300 notes the
  patterns path is manual-only; this plan reuses its ledger and hash shapes unchanged.

### Measured state (Phase 1.8, 2026-10-26)

- 104 skill directories, 8 `disable-model-invocation: true`. Model-visible description words: **2436**
  against `SKILL_DESCRIPTION_WORD_BUDGET = 2443` (`plugins/soleur/test/components.test.ts:21`) =
  **7 words of headroom**, below the 10-word floor of `cq-skill-description-budget-headroom`.
  Command: a scratch script calling `discoverSkills()` / `parseComponent()` from
  `plugins/soleur/test/helpers.ts`, skipping `disable-model-invocation === true`, `split(/\s+/)`.
  (A `grep | wc -w` survey over-counts by about 5 words per skill and is not the gate.)
- `README.md` says "104 skills", `plugins/soleur/README.md` says "| Skills | 104 |"; CI `lint-bot-statuses`
  runs `scripts/sync-readme-counts.sh --check` and goes red unless both move in the same PR.

### Repo facts that shaped the design (file anchors, all re-derived)

- The proposer cannot create a file today; it is refused at nine independent sites in
  `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`: target menu `listEligibleTargets`;
  `TARGET_ALLOW_RE` (never admits `PURPOSE.md`); `readEditTarget` ls-tree (absent target); `deriveDiff`
  (requires an LF-terminated base); `checkDiffPaths` `status !== "M"` -> `structural-op`;
  `diff-path-off-target`; `target-missing`; `allowedPaths = [target, promotion-log.md]`; the shrink floor.
  The create arm adds its OWN admission path (`checkCreate`) and does not loosen any edit-arm check.
- `safeCommitAndPr` has an `exactPaths` + `expectedContent` mode (precedent: `cron-community-monitor.ts`
  digest, #7122) that stages filter-free blobs with `hash-object --no-filters` + `update-index --add`
  and verifies index bytes before commit. It resolves the "can a new file be staged" question.
- `skill-security-scan/scripts/run-scan.sh`: verdict is line 1 of stdout (`# skill-security-scan verdict:
  LOW-RISK|REVIEW|HIGH-RISK`), exit 0 even on HIGH-RISK, EMPTY INPUT returns LOW-RISK (fail-open), the
  code-exec check scans fenced blocks only, one file per run, writes `.scan-meta.json`
  (`SKILL_SCAN_META_BASE`). Needs bash, jq, sha256sum, awk, sed, grep, find, mktemp, tr, timeout. The
  runner image adds git, jq, curl; bash/coreutils come from `node:22-slim` (inferred, verified in Phase 0).
- Every skill carries a byte-identical Grok invoke block (md5 pinned by
  `plugins/soleur/test/grok-harness-invoke.test.ts`, canonical source `plugins/soleur/skills/plan/SKILL.md`)
  and a Cursor stub `plugins/soleur/cursor/skills/soleur-<slug>/SKILL.md` produced by
  `plugins/soleur/scripts/sync-cursor-name-map.ts` and checked in CI. Both are CI-red surfaces for a new
  skill directory. The Cloud Mode block is NOT required (not in the `devin-cloud-mode` UNION).
- `docs/_data/skills.js` falls back to "Uncategorized" for an unmapped skill: not a failure; the PR body
  tells the reviewer to categorise it.
- Zero `PURPOSE.md` files exist (`git ls-files 'plugins/soleur/skills/*/PURPOSE.md'` = 0). The Phase 3
  plan (`knowledge-base/project/plans/archive/20261023-234321-2026-10-23-feat-wikiskill-phase-3-ship-purpose-md-plan.md`,
  #10551) assumes a sibling heading-keyed rationale file linked once from SKILL.md, no `[id:]` tokens.
- Pattern pages have a closed `ALLOWED_KEYS` set with no owner field (`compound-promote-patterns.ts`).
  Refusal reasons are census-enforced (`cron-compound-promote-outcome-census.test.ts`).

### Institutional learnings applied

- `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`: exact before/after trims in the
  plan, measured with the real tokenizer, not estimated.
- `2026-10-20-a-threshold-that-lives-only-in-a-prompt-is-a-request-not-a-constraint.md`: every numeric rule
  (30 words, caps, thresholds) is an exported constant read by prompt, check and trailer.
- `2026-10-19-a-model-asked-for-a-diff-it-never-saw-fails-in-a-different-mode-every-week.md`: the model never
  authors a diff or a file; the server renders from structured fields.
- `security-issues/2026-09-20-my-sink-control-was-a-denylist-over-a-string-the-model-writes.md`: controls
  over model text are shape ALLOWLISTS.
- `2026-10-26-a-caps-reachable-maximum-is-set-by-the-tightest-downstream-gate-and-a-scan-must-record-what-it-was-asked.md`:
  create-specific caps; an unscanned target is "unverifiable", never "clear".
- `2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md`: every new gate
  fails closed on unparseable input (malformed description, unparseable cap, empty render).
- `best-practices/2026-05-20-components-test-scripts-regex-catches-illustrative-paths.md`: generated prose
  contains no backticked `scripts/`, `references/`, `assets/` strings.
- `2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit.md` and
  `workflow-issues/2026-09-18-the-release-run-was-green-and-production-was-still-serving-the-previous-build.md`:
  deploy verification is `deploy-arm.sh find --wait` AND `/health build_sha` equal to the merge SHA.
- `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`: re-run anchor-keyed audits
  and census floors on the merged tree; do not carry generated indexes in the diff.

### Property List and Cut List (Phase 0.6b)

**Properties (observable outcomes):**

- P1 A create is refused unless the description budget has room, and the cap itself never rises.
- P2 Only markdown lands: the committed path set is closed and contains no script, hook, or config.
- P3 Every created skill ships a PURPOSE.md with origin, patterns addressed, nearest skill and why not patched,
  merge/retire candidates, history, and a fixed CC BY 4.0 attribution.
- P4 No file is committed unless an explicit LOW-RISK verdict was read from the scanner for BOTH files.
- P5 Total model-visible description words never exceed today's total (2436).
- P6 Prefer patch: a create must name an existing nearest skill and lose a deterministic overlap check.
- P7 Human gate retained: draft PR only, no auto-merge, ADR-092 hard-rule protections intact.
- P8 Every refusal is visible in the outcome marker and Sentry without SSH.

**Cut List (mechanism -> property -> what already covers it):**

| Cut | Property it would have bought | What covers it / why cut |
|---|---|---|
| Merge-base ratchet lint for the cap constant | P5 | CTO T2: human new-skill PRs legitimately bump the cap today; the cap is lowered once here and the proposer cannot edit `components.test.ts`. The residual (a human bumping later) is the existing ritual. |
| Proposer trims a sibling description in the same PR (literal FR14) | P5 | ADR-092 additive-only + `diff-path-off-target`; replaced by the pre-paid reserve (34 words). |
| `owner_skill` key on pattern pages | P6 | CTO T3: schema change over 7 pages for one gate; server-side overlap ranking buys it. |
| Separate Inngest function / skill-for-humans | P7 | CTO T1: re-implements clone, token, `safeCommitAndPr`, budget and census wiring. |
| Raw model-authored files | P2/P3 | CTO T4: server renders from structured fields; shape allowlist. |
| `api.osv.dev` egress allowlist entry | P4 | Created skills declare no packages, so the scanner never queries OSV. |
| PURPOSE.md lint over existing skills / backfill | P3 | Phase 3 (#10551), explicitly off limits. |
| Registering created skills in `eval-harness` | P6 | Optional per functional-overlap check; not required for a dark arm. |
| One refusal reason per cause | P8 | One reason `create-refused` + closed `class` field avoids ~5 co-moving census artifacts per reason (CTO). |

### Functional overlap (Phase 1.5b)

No community artifact is worth installing (registries returned only generic scaffolders). Reuse: `skill-creator`
templates (scaffold shape), `skill-security-scan` as-is, `compound-promote` guards (opt-in config gate, per-week
cap, PII regex, same-file skill-conflict guard from #11157), pattern-page loader. Genuinely new: ownership
overlap ranking, the budget gate, server-side rendering with a shape allowlist, the provenance file.

### Open Code-Review Overlap

Two open `code-review` issues touch planned files. #8593 ("#6793 probe gate window is narrower than the
silent-truncation property it names") names `plugins/soleur/test/components.test.ts`: **Acknowledge** - it concerns a
different test in that file; this plan edits only the `SKILL_DESCRIPTION_WORD_BUDGET` constant line. #3593
("extract post-synthetic-checks child composite") mentions compound-promote in a CI-composite context:
**Acknowledge** - no workflow file is touched. No other planned path matched.

## Problem Statement

The loop now produces visible draft PRs (#11230, #11231) but can only patch existing skills. Recurring patterns
with no owning skill stay as prose in other skills' sharp edges. The description budget is at 7 words of
headroom, so even a well-formed new skill cannot land without breaking `components.test.ts`.

## Proposed Solution

### Order of gates (fixed; every refusal is `create-refused` with a closed `class`)

```text
manual trigger {input:"patterns", allow_create:true}   (anything else: arm absent, byte-identical run)
  -> edit-arm loop runs first and ends on a clean main; create arm uses remaining - editPrsOpenedThisRun > 0   [class: week-cap]
  -> open-create check: GET /pulls (open, label self-healing/auto), body contains the fixed line; list failure refuses [class: create-open]
  STEP A  create-propose (memoized, never throws; converts failure to a returned class)
  -> pattern index empty                                                                                   [class: index-empty]
  -> input-size gate (index + skill list <= CREATE_INPUT_MAX_TOKENS = 12000, else refuse, never truncate)  [class: input-size]
  -> ONE model call, no retry -> {decision:"no_action", reason_class} | proposal                           [class: model-invalid]
  -> shape allowlist + claim-word check over EVERY model string                                            [class: shape]
  -> PII_REGEX + CREDENTIAL_RE over every model string                                                     [class: shape]
  -> ledger: hash over the chosen pattern's evidence keys (existing computeClusterHash); suppressed -> stop [existing ledger-suppressed]
  -> slug collision (skill dirs, agent names, open-PR paths via scanOpenPrSkillPaths)                       [class: slug]
  -> prefer-patch: nearest_skill exists AND in server top-3 overlap AND top-1 overlap < THRESHOLD          [class: prefer-patch]
  -> budget: MIN_WORDS <= words(description) <= 30 AND words <= cap - total (clone, same counter)          [class: budget]
  STEP B  create-persist (ONE step: clone, render, scan, sync, stub, commit; mirrors the edit arm's spawnCwd: repoRoot call)
  -> render SKILL.md + PURPOSE.md (fills the purpose.md template) + Cursor stub (Grok block read from plan/SKILL.md)
  -> PII_REGEX + CREDENTIAL_RE over the RENDERED files                                                     [class: shape]
  -> skill-security-scan on BOTH files (files are on disk first: the scanner and exactPaths staging both read disk)
     exit 0 AND first line == "# skill-security-scan verdict: LOW-RISK"; SKILL_SECURITY_SCAN_OFFLINE=1   [class: scan]
  -> sync-readme-counts.sh in the clone: changed set == {README.md, plugins/soleur/README.md}           [class: readme-sync]
  -> stub: pure renderer (default) OR the real generator when Phase 0 proves it runs (CTO G3); changed set == the one stub [class: stub-drift]
  -> safeCommitAndPr(exactPaths x6, expectedContent, syntheticChecks without "skill-security-scan PR gate" and "test")
     -> draft PR, label self-healing/auto, fixed "CREATE (new skill)" body line      [class: persist only on a genuine commit/PR failure]
```

A refused create writes NO ledger row; only a committed PR does, so a pattern refused for budget or scan retries
once headroom frees. At most one `create-propose` call and one create per run. All three repo scripts
(`run-scan.sh`, `sync-readme-counts.sh`, and the generator when used) run through ONE shared `spawnRepoScript`
helper with a scrubbed environment (no installation token, no secrets), a timeout and a regular-file check.
Replay: the branch suffix derives from the memoized `runStartedAt` date (never a fresh `Date`); Step B first looks
up its own open PR by deterministic head branch and counts a hit as success; the function keeps its existing
`concurrency` limits and `retries: 1`.

### What the model returns (one call; the server renders every byte)

`{decision: "no_action", reason_class}` or `{decision: "create", pattern_slug, slug, description,
nearest_skill, patch_rejection_reason, when_to_use[], steps[], sharp_edges[], merge_retire_candidates[],
purpose: {origin, patterns_addressed}}`. All strings are plain ASCII text; list items are `- ` bullets
rendered by the server. The server fixes frontmatter (exactly `name` and `description`), headings
(`When to use`, `Steps`, `Sharp edges`), one link to `./PURPOSE.md`, the canonical Grok block, the PURPOSE
headings and the attribution text. Constants (exported, read by prompt, check and PR-body trailer):
`CREATE_DESCRIPTION_MAX_WORDS = 30`, `CREATE_DESCRIPTION_MIN_WORDS = 12`, per-file cap 60 lines / 3 KB, at most 6 list
items per section, `CREATE_INPUT_MAX_TOKENS = 12000`, `CREATE_MAX_TOKENS = 3000`, `OVERLAP_REFUSE_THRESHOLD`
(calibrated in Phase 3 so both evidence fixtures refuse with margin AND synthetic negatives create).

### Shape allowlist (controls over model text are allowlists, never denylists)

Plain printable ASCII; no backticks, no code fences, no `](` or URLs, no `[id:`, no rule-id tokens
(`hr-`, `wg-`, `cq-`, `rf-`, `pdr-`, `cm-` followed by a slug), no `scripts/`, `references/`, `assets/` strings,
no `soleur:` token, no leading `/word` command form, no `skills/` token (harness-parity and invocation-axis censuses scan `skills/**/*.md`), no `"` or `\` in `description`; claim words refused case-insensitively and word-bounded:
`guarantee(s|d)`, `compliant`, `compliance`, `certified`, `secure`, `your workspace`. Slug `^[a-z][a-z0-9-]{2,40}$`.
The reviewer checklist in the PR body is fixed server text (positioning rule "Soleur got sharper", no
personal data, categorise in `docs/_data/skills.js`, words used / headroom left / top-1 overlap score, and a
note that after any description edit or rebase onto a main that added a skill the reviewer re-runs
`bun plugins/soleur/scripts/sync-cursor-name-map.ts` and `bash scripts/sync-readme-counts.sh`).

### Pre-paid budget reserve (CTO T2, adapted to measured text)

Five trims, redundant clauses only, trigger phrasing kept. `questionnaire-generate` (named in the ruling's
candidate list) is NOT trimmed because its parenthesised expert list IS its trigger phrasing; `reproduce-bug` and
`docs-site` replace it with larger redundant clauses. Counts measured with the real tokenizer on 2026-10-26.

| Skill | Before (words) | After (words) | Freed |
|---|---|---|---|
| invoice | "This skill should be used when the founder wants to get paid through their own Stripe account: list who owes them, create and send an invoice behind a human-approval preview, or chase an overdue one. Test-mode only in v1." (39) | "This skill should be used when the founder wants to get paid through Stripe: list who owes them, send an invoice behind a human-approval preview, or chase an overdue one. Test-mode only." (32) | 7 |
| drain-prs | "This skill should be used when draining open remote GitHub PRs: triage every open pull request into mergeable tiers, confirm scope with the operator, then fix and merge the green ones. The PR-counterpart to drain-labeled-backlog." (35) | "This skill should be used when draining open GitHub PRs: triage them into mergeable tiers, confirm scope with the operator, then fix and merge the green ones. Counterpart to drain-labeled-backlog." (30) | 5 |
| trigger-cron | "This skill should be used to fire an allowlisted cron manual-trigger on demand via POST /api/internal/trigger-cron, without SSH. Reads the secret read-only from Doppler, lists allowlisted events, supports optional event data and a dry-run." (34) | "This skill should be used to fire an allowlisted cron manual-trigger via POST /api/internal/trigger-cron, without SSH. Reads the secret read-only from Doppler; lists events; supports event data and a dry-run." (30) | 4 |
| reproduce-bug | "This skill should be used when reproducing and investigating a bug using logs, console inspection, and browser screenshots. It systematically investigates GitHub issues through log analysis, code inspection, and visual reproduction with Playwright." (33) | "This skill should be used when reproducing and investigating a GitHub issue bug using logs, console inspection, code inspection, and Playwright browser screenshots." (23) | 10 |
| docs-site | "This skill should be used when scaffolding a Markdown-based documentation site using Eleventy. It generates a complete docs setup with base layout, data files, GitHub Pages deployment workflow, and passthrough copy configuration." (32) | "This skill should be used when scaffolding a Markdown-based Eleventy documentation site: base layout, data files, GitHub Pages deployment workflow, and passthrough copy configuration." (24) | 8 |

Total freed **34** words (2436 -> 2402). `SKILL_DESCRIPTION_WORD_BUDGET` goes from 2443 to **2436** (the pre-PR measured
total, re-measured at work time after rebase; the number is whatever the tree measures before the trims), so
headroom after the PR = freed words = 34. The longest trimmed result is 32 words (under the 1024-character limit).
Each exact "before" string was verified present in its `SKILL.md` via `includes('description: "<before>"')`; the
"after" word counts were produced by `split(/\s+/).filter(Boolean)`. The 5 regenerated Cursor stubs
(`soleur-invoice`, `soleur-drain-prs`, `soleur-trigger-cron`, `soleur-reproduce-bug`, `soleur-docs-site`) come
from `bun plugins/soleur/scripts/sync-cursor-name-map.ts`; the PR body lists these paths so the diff is
explainable. A reviewer approves the exact wording (routing quality is a human judgment; CTO fork).

### PURPOSE.md contract (CTO T7, CLO attribution)

Template `plugins/soleur/skills/skill-creator/templates/purpose.md` is the single source: the renderer fills its
closed template-slot set (plan-review revision), so no second copy of the headings exists in server code. Fixed headings: Origin; Patterns addressed;
Nearest existing skill and why not patched; Merge and retire candidates; Evolution history; Attribution.
SKILL.md links `./PURPOSE.md` exactly once; no `[id:]` tokens (Phase 3 compatible). The attribution is a fixed server
string, never model text (CLO, 2026-10-26): "Provenance and attribution: the prompt and structure text behind this
skill's creation is adapted from the paper WikiSkill (Google Research), arXiv:2608.27454, licensed under CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/). The authors are credited on the source page at
https://arxiv.org/abs/2608.27454. Changes made: the text was adapted to this repository's learnings corpus and
rendered by an automated proposer; no endorsement by the authors or Google Research is implied." Author names are
not in the repo and are NOT invented; the string points at the source page. No PURPOSE.md enforcement on
pre-existing skills (that is #10551, off limits). The URLs live in server-fixed text, which is why the shape
allowlist can still forbid URLs in model text.

## Technical Considerations

- **Client/server boundary:** both new modules live under `apps/web-platform/server/` and are imported only by the
  handler and tests; `apps/web-platform/server/README.md` boundary gate is unaffected.
- **Scheduled-path invariance:** `allow_create` is parsed in the same helper that parses `input` (`readRunOptions`,
  ~L1626) and only after `trigger === "manual" && input === "patterns"` (the `readRunOptions` return type `{input}|{invalid}` grows to carry it; that is the single parse site Guard 3 depends on); a test pins that a scheduled run, a manual
  corpus run, and an event carrying `allow_create` as a non-boolean all leave the arm absent.
- **Cursor stub (CTO F1, conditional per G3):** default `renderCursorSkillStub(name, description, target)` is a small pure duplicate of the generator,
  pinned byte-for-byte by a parity test over EVERY real skill folder (test-only import of `buildCursorNameMap`
  from `plugins/soleur/scripts/sync-cursor-name-map.ts`) plus one synthetic fixture. A generator HEADER change turns
  the parity test red instead of drifting silently. **Conditional (CTO G3):** if Phase 0 shows, with command output from the
  actual runner image, that the unmodified generator runs there, the arm runs the real generator in the clone (scrubbed
  env, timeout) and requires the changed set to be exactly the one new stub (`stub-drift` otherwise); the pure renderer and
  Guard 4 are then deleted. Bun is NOT added to the image in this PR.
- **Grok block:** read at runtime from the clone's `plugins/soleur/skills/plan/SKILL.md` between the two markers
  (single source); a test pins its md5 equals the `grok-harness-invoke` pin.
- **Budget counter:** `countDescriptionWords(tree)` mirrors `components.test.ts` exactly (YAML frontmatter parse via
  the `yaml` package already in `apps/web-platform`, skip `disable-model-invocation === true`, whitespace split) and
  reads the cap by regex from `plugins/soleur/test/components.test.ts`; unparseable cap, total, or description is a
  refusal. A parity test runs it over the real tree and asserts equality with the value the bun test computes.
- **Concurrency:** `scanOpenPrSkillPaths` is extended (create arm only) to refuse when an open PR already touches
  the nearest skill or the same new slug path; headroom is recomputed from the clone at run time; CI
  `components.test` is the final backstop if main moved.
- **Cost/placement:** `cron-compound-promote` is host-affine (`execution-placement.ts`); it is absent from
  `CLAUDE_BUDGET_USD` in `cron-budgets.ts`, so no entry is invented. Phase 0 checks how the existing `input:
  patterns` call is bounded and binds `create-propose` to the same mechanism; worst case is one extra call per
  manual fire. Whether the manual-fire throttle covers this function is verified in Phase 0.
- **Persistence:** `exactPaths` (6) + `expectedContent`; `allowedPaths: []`. The six paths:
  `plugins/soleur/skills/<slug>/SKILL.md`, `plugins/soleur/skills/<slug>/PURPOSE.md`,
  `plugins/soleur/cursor/skills/soleur-<slug>/SKILL.md`, `README.md`, `plugins/soleur/README.md`,
  `knowledge-base/project/learnings/promotion-log.md`. README bytes come from running the sync script in the clone
  and reading the files back; the guard requires the changed set to be exactly the two README paths with digit-only
  line diffs. The edit arm's `safeCommitAndPr` call is untouched.
- **Marker:** add closed fields `kind: "edit" | "create"`, `create_requested: boolean` (present on EVERY manual run, so
  each switch-on is visible without SSH), `create_arm: "ran"` (emitted ONLY when the arm ran; an absent field means
  off, so the scheduled path gains no field), `create_outcome: "no_action" | "refused" | "opened"`, and ONE new refusal
  reason `create-refused` with `class ∈ {week-cap, create-open, index-empty, input-size, model-invalid, shape, slug,
  prefer-patch, budget, scan, readme-sync, stub-drift, persist}` and a closed `no_action` reason set
  (`no-pattern-qualifies`, `all-owned`, `other`). Each refusal is mirrored to Sentry with ONE op name,
  `create-refused`, plus a `class` tag. The PR body gets a fixed `CREATE (new skill)` line; no new Tier vocabulary.
- **Docs-site and loader sweep:** `plugins/soleur/docs/_data/skills.js` and the `llms.txt` templates read only
  `SKILL.md` per directory; several lint tests glob `skills/**/*.md` (`components.test.ts`, `invocation-axis.test.ts`),
  so `PURPOSE.md` must pass them. The dry-render test (Phase 5) runs all of them on a synthetic tree.
- **Attack surface (create arm):** model-supplied slug (path traversal, collision), model-supplied strings reaching
  public files (injection, claims, PII), a scanner that fails open on empty input, README edits by a script, and a
  stub that drifts from the generator. Each has a gate above and a row in the Guard Contract.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| (B) separate Inngest function for creation | Rejected (CTO T1): duplicates clone/token/`safeCommitAndPr`/budget/census wiring. |
| (C) ship only gates and a human-run skill | Rejected: spec FR12 says the proposer may open the PR. |
| (ii) amend ADR-092 so the proposer replaces one sibling `description:` line | Rejected: multi-file create+trim diff reopens the #8274 class; additive-only holds. |
| Literal FR14 net-zero in the same PR | Replaced by a pre-paid reserve with the cap lowered; total never exceeds 2436. |
| `owner_skill` pattern key | Deferred/cut (schema change over 7 pages). |
| Model writes raw SKILL.md/PURPOSE.md | Rejected (CTO T4): denylist over model prose is the weaker control. |
| Importing the stub generator at runtime | Rejected: bun-shaped script, cross-tree import unverified in the image; duplicate renderer + parity test instead. |
| Leave README/stub to the reviewer (red draft) | Rejected (CTO T6/F1): undermines "reviewer gets a ready draft". |

## User-Brand Impact

- **If this lands broken, the user experiences:** a draft PR for a model-authored skill with a claim-laden or
  misleading description, or a plugin update whose skill count and docs disagree (red `lint-bot-statuses`,
  `cursor-name-map`), or a scheduled proposer run that behaves differently from the 2026-10-25 baseline.
- **If this leaks, the user's data / workflow is exposed via:** personal data, handles or secrets quoted in a
  learning surviving the best-effort input screen into a rendered `SKILL.md`/`PURPOSE.md` that, once a human merges
  it, ships in every installed copy of the public plugin and in public git history (Art. 17 erasure impractical);
  or a created skill that restates or relaxes an `hr-*` guardrail that protects a user's repository.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried forward unchanged from the 2026-09-18 brainstorm (CPO + CLO +
  CTO assessed it there); a published skill cannot be recalled from installed copies. CPO sign-off is satisfied by
  the brainstorm carry-forward; `soleur:engineering:review:user-impact-reviewer` runs at review time.

Controls: human-reviewed draft PR in every case and no auto-merge (`mergeMode: "none"`); dark-launched manual-only
flag; server-rendered content from a shape allowlist; claim-word and PII/credential checks on input fields AND the
rendered output (CLO); scanner must return an explicit LOW-RISK for both files; closed 6-path commit set; created
skills cannot carry rule-id tokens, and the ADR states plainly that "may not restate or relax `hr-*`" is enforced
only by the token/phrase gate plus the human reviewer.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_COMPOUND_PROMOTE_OUTCOME marker with kind=create and create_arm=ran, one per manual fire with allow_create (Better Stack Logs, pino); Sentry mirror for every create-refused"
  cadence: "per manual fire; the scheduled weekly run gains no marker field and is otherwise unchanged; every manual run records create_requested"
  alert_target: "existing cron-compound-promote Sentry monitor and the existing 4-zero-output-weeks alert; create refusals route to Sentry issues tagged class"
  configured_in: "apps/web-platform/server/compound-promote-marker.ts and apps/web-platform/server/inngest/functions/cron-compound-promote.ts"
error_reporting:
  destination: "Sentry (feature cron-compound-promote, op create-refused with a class tag) via reportSilentFallback"
  fail_loud: "create-propose refusals set status and class in the marker; scanner non-zero, empty, timeout, or missing tool is a refusal with class scan, never a silent skip"
failure_modes:
  - mode: "scanner tools missing from the runner image (arm silently never creates)"
    detection: "preflight command -v check emits class=scan with detail missing-tool; Sentry op create-refused tag class=scan"
    alert_route: "Sentry issue on first manual fire; layer 2 (pino -> Sentry breadcrumb mirror) plus the marker"
  - mode: "budget gate refuses forever because headroom is exhausted"
    detection: "marker create-refused class=budget with cap/total fields (numbers only); runbook row"
    alert_route: "Better Stack query in the runbook; layer 2"
  - mode: "model proposes a create for a pattern a skill already owns"
    detection: "class=prefer-patch with overlap rank and top-1 score in the marker (numbers, no text)"
    alert_route: "Better Stack query; layer 2"
  - mode: "draft PR red on lint-bot-statuses or cursor-name-map (path set incomplete)"
    detection: "dry-render test in CI before merge; after merge the PR's own required checks"
    alert_route: "GitHub PR checks on the draft; workflow-run log (layer 6)"
  - mode: "week cap saturated by open self-healing/auto PRs (today #11230 and #11231), so every manual fire returns week-cap-reached before the arm"
    detection: "existing week-cap-reached status plus class=week-cap after the edit loop; a unit test injects cap=1 so the arm is exercised end to end"
    alert_route: "Better Stack marker query in the runbook; layer 2"
  - mode: "scheduled run changed by this PR"
    detection: "outcome-census and scheduled-path invariance tests; the scheduled-path equivalence is proven pre-merge by tests; after deploy no marker carries create_arm until the arm is fired"
    alert_route: "CI red before merge; Better Stack marker after deploy"
logs:
  where: "Better Stack Logs source for the web-platform (pino marker), Sentry for refusals"
  retention: "Better Stack source retention as configured; Sentry per project retention"
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 30d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 5
  expected_output: SOLEUR_COMPOUND_PROMOTE_OUTCOME
  credentials_required: "Better Stack Logs read token (Doppler) - the marker exists only in production logs, so no unauthenticated local probe verifies the same property"
```

Layer citations: markers and refusals ride layer 2 (pino -> Sentry breadcrumb/captureException mirror) and
layer 1 (Inngest sentry-correlation middleware tags the run); PR-check failures ride layer 6 (workflow-run
log). The arm runs on a host-affine cron worker; the in-surface probe is the marker itself, emitted from the
handler, with fields that discriminate all competing causes in one event (`class`, overlap rank, cap, total, scan
verdict class, sync changed-path count).

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-092** (`knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`)
  with a create-only amendment: exactly the closed 6-path set above, status `A` only, nothing deleted,
  `AGENTS.rules.md` untouched, `checkDiffPaths` and `isAdditiveDiff` unchanged, a new `checkCreate` with its own
  closed verdict union. State plainly that "created skills may not restate or relax `hr-*`" is enforced by the
  token/phrase gate plus the human reviewer, not provable deterministically.
- **Addendum to ADR-300** (one line): the create arm reuses the ledger, hash and branch/title shapes; `kind=create`
  distinguishes it. Status stays `adopting`. No new ADR (CTO).
- Sequencing: both written in commit 2, before the code they describe.

### C4 views

All three files (`model.c4`, `views.c4`, `spec.c4`) were read for this decision. External actors: the human
reviewer of draft PRs is already the bot-PR reviewer relationship; no new human actor. External systems: Anthropic
(`anthropic` system, `api -> anthropic`/`claude -> anthropic` edges) is already modeled and the create arm is a
second call on the same edge; GitHub is modeled (`api -> github` edge at `model.c4:741` already describes the
compound-promote Octokit reads). Data stores: none new (no table, queue, or volume). Access relationships: none
change. Cardinality prose: `model.c4:194` says "104 workflow skills" and is hand-mirrored by the periodic audit,
not gated; `c4-count-parity` (`plugins/soleur/test/c4-count-parity.test.sh`) is run in Phase 6 and must stay green.
**No C4 impact** beyond that count text, which the first merged create would move (left to the audit, noted in
the runbook).

## Encryption Posture

Skipped: no persistent store or new cross-component connection is introduced. The arm adds a second HTTPS call
on the existing, already-modeled Anthropic edge and writes through the existing GitHub App path.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings T1-T8 and F1-F3 (see `decision-challenges.md`) shaped this plan: dark-launched arm in the
existing cron, pre-paid reserve instead of a proposer-side trim, server-rendered content, `exactPaths` persistence,
Cursor stub rendered by a parity-pinned duplicate, one `create-refused` reason with a closed `class`, input ceiling
12k tokens with refuse-never-truncate, one create per run. Forks the CTO added (refusal vocabulary, trim quality,
concurrency, new-file staging, docs/loader sweep, spend, placement) are Phase 0 checks or ACs below.

### Legal (CLO)

**Status:** reviewed
**Assessment:** No new processing activity (PA-31, same processor, same screened inputs); output surface widens
from additive edits to whole new files shipped in the public plugin, so schedule a dated PA-31 note, an addendum to
`knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md`, and a frontmatter pointer, all
written conditionally ("fires on the merge"). Run `soleur:gdpr-gate` at plan time (triggers (a) and (d)); run the PII
screen on rendered output as well as input; fixed attribution string above; claim-word check and a reviewer
checklist line. Draft internal material, not legal advice.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Beneficiary is the harness; positioning "Soleur got sharper", never "your workspace got smarter";
north-star is recurrence-after-fix, not skills created. Single-user-incident sign-off carried from the brainstorm.
No UI surface: the mechanical UI-surface override does not fire (no `components/**/*.tsx`, `app/**/page.tsx`).

### GDPR gate (plan Phase 2.7, run 2026-10-26, advisory)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**
The canonical regulated-path regex matched no planned file (no migration, no `.sql`, no auth or `app/api` path); the gate ran on
triggers (a) LLM call over session-derived learnings and (d) public artifact distribution. Checks: `GDPR-Art-6` and `GDPR-Art-5e`
and `GDPR-Art-17` and `GDPR-Art-9` - no schema column is added, none apply; `GDPR-Chapter-V` - Anthropic is an existing processor
under the recorded DPA, same inputs as Phase 1, no new vendor. One `Suggestion`-level finding carried into the plan: the output
surface widens to public plugin files and public git history (Art. 17 erasure impractical), mitigated by the input and OUTPUT
PII/credential screens, the shape allowlist and the human-reviewed draft PR; and the dated conditional PA-31 note plus DPIA
addendum already scheduled in Phase 2. No Critical finding, so no `compliance-posture.md` Active Items row or issue is created now.

Brainstorm-recommended specialists: none named. Product/UX Gate: not applicable (no UI).

## Implementation Phases

### Phase 0 - Preconditions (no commit)

Rebase on `origin/main`; re-measure total/cap/headroom (record numbers); confirm no sibling merged a new skill
(re-derive the trim set if it did). Verify: runner image has `bash jq sha256sum awk sed grep find mktemp tr timeout`
(read `apps/web-platform/Dockerfile`, then prove with a container run or a CI step that execs `command -v`); vitest
in `apps/web-platform` resolves `plugins/soleur/scripts/sync-cursor-name-map.ts` and `yaml` is a dependency; how the
existing `input: patterns` model call is bounded and whether the manual-fire throttle covers this function; the
12k-token ceiling holds on the real pattern index plus skill list (measure with the repo tokenizer helper or a
documented bytes/4 bound, recorded); calibrate `OVERLAP_REFUSE_THRESHOLD` on the two evidence fixtures and at least
four synthetic negatives. Additional Phase 0 checks (plan-review and CTO): (a) command output from the ACTUAL runner image for
the tool set and for whether the unmodified Cursor generator runs there (decides G3); (b) the `trigger-cron` allowlist/event
schema passes `allow_create`; (c) enumerate holders of the internal trigger bearer secret - if it is reachable from an agent
sandbox, a tenant-facing route, or any principal other than the operator, add a server-side flag via `soleur:flag-create` in this
PR (CTO G1 flip evidence); (d) `lint-orphan-test-suites.sh` and `scripts/lib/test-affected-paths.sh` registration for every new
suite, bun suites included; (e) bun availability in the vitest CI job for the parity/dry-render tests.

### Phase 1 - Free the budget (commit 1)

Apply the five trims verbatim from the table; run `bun plugins/soleur/scripts/sync-cursor-name-map.ts`; lower
`SKILL_DESCRIPTION_WORD_BUDGET` to the pre-trim measured total and extend its history comment; run
`bun test plugins/soleur/test/components.test.ts plugins/soleur/test/cursor-name-map.test.ts`; assert headroom >= 30. Also in this commit: bump `BASELINE_DECLARED_PROBES` in
`plugins/soleur/test/preflight-discoverability-test.test.ts` (83 at planning time, re-read at work time) because this plan's
`credentials_required` declaration moves the repo-global ratchet the moment the plan file is committed.

### Phase 2 - Contracts (commit 2)

ADR-092 amendment, ADR-300 addendum, `purpose.md` template, `plugins/soleur/test/purpose-template.test.ts`
(closed template-slot set, fixed headings, single PURPOSE link slot), legal register notes and DPIA addendum
(conditional wording), runbook scaffolding rows.

### Phase 3 - Pure module, tests first (commit 3; RED then GREEN)

`compound-promote-create.ts`: output schema, shape allowlist and claim words, PII/credential checks, slug and
collision, overlap ranking, `countDescriptionWords`, `readBudgetCap`, SKILL/PURPOSE/stub renderers, `checkCreate`
verdict union. Write the Guard Contract mutation rows as failing tests first.

### Phase 4 - Gates that spawn (commit 4; RED then GREEN)

`compound-promote-create-gates.ts`: `runSkillScan` (both files, explicit first-line match, exit 0, timeout,
`SKILL_SCAN_META_BASE` outside the clone, tool preflight, non-empty and minimum-size assertion before scanning),
`syncReadmeCounts` (changed set exactly two READMEs, digit-only diff), content-bytes collector for `expectedContent`.

### Phase 5 - Handler wiring (commit 5)

`readRunOptions` parses `allow_create` only on manual+patterns; `create-propose` step; persistence in `exactPaths`
mode; PR body `CREATE (new skill)` line and fixed reviewer checklist; marker fields; `scanOpenPrSkillPaths` create
variant; update the ~L480 comment (#10550); census, marker and allowlist tests; dry-render test that builds a
synthetic tree and runs `components.test`, `cursor-name-map --check`, `grok-harness-invoke`, `sync-readme-counts
--check`, `invocation-axis`, `harness-parity-tree` (ADR-226 component-reference census), the docs `skills.js` loader and the scanner (offline, SKILL.md only, as `pr-quality-guards.yml` runs it) against it. Budget-boundary tests (`cap - total` accepted, `+1` refused) run on a FIXTURE tree because the real tree has 34 headroom against a 30-word maximum.

### Phase 6 - Registration and docs (commit 6)

Runbook + `betterstack-log-query.md` rows (`create-refused` classes); run `lint-orphan-test-suites.sh` and the affected-suite census (each new suite is registered in the commit that adds
it, so commits stay independently green; this phase only re-verifies); run `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 7 - Trackers and PR

File deferral issues (see Deferrals); PR body uses `Ref #10550` and lists the five regenerated stub paths; no
`Closes`. Then ship/merge (one `gh pr merge` per call), `deploy-arm.sh find --wait`, served `build_sha` check,
`soleur:postmerge`.

## Files to Create

- `apps/web-platform/server/compound-promote-create.ts`
- `apps/web-platform/server/compound-promote-create-gates.ts`
- `apps/web-platform/test/server/compound-promote-create.test.ts`
- `apps/web-platform/test/server/compound-promote-create-gates.test.ts`
- `apps/web-platform/test/server/compound-promote-create-parity.test.ts` (stub parity over every skill, Grok md5, budget counter parity)
- `apps/web-platform/test/server/compound-promote-create-dry-render.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts`
- `apps/web-platform/test/fixtures/compound-promote-create/` (synthetic index, skill list, golden SKILL.md/PURPOSE.md/stub; no real learning content)
- `plugins/soleur/skills/skill-creator/templates/purpose.md`
- `plugins/soleur/test/purpose-template.test.ts`
(`tasks.md` and `decision-challenges.md` under `knowledge-base/project/specs/feat-one-shot-10550-wikiskill-phase-2-new-skill-creation/` already exist from planning.)

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
- `apps/web-platform/server/compound-promote-marker.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-marker.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts` (create path set pinned; edit-arm allowlist unchanged)
- `apps/web-platform/test/repo-wide-suites.ts` and `scripts/lib/test-affected-paths.sh` (register each new suite in the commit that adds it; `lint-orphan-test-suites.sh` verifies)
- `plugins/soleur/test/components.test.ts` (cap constant line and its history comment only)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES`, re-read at work time)
- `plugins/soleur/skills/invoice/SKILL.md`, `drain-prs/SKILL.md`, `trigger-cron/SKILL.md`, `reproduce-bug/SKILL.md`, `docs-site/SKILL.md` (description line only)
- `plugins/soleur/cursor/skills/soleur-invoice/SKILL.md`, `soleur-drain-prs/SKILL.md`, `soleur-trigger-cron/SKILL.md`, `soleur-reproduce-bug/SKILL.md`, `soleur-docs-site/SKILL.md` (regenerated)
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`
- `knowledge-base/engineering/architecture/decisions/ADR-300-pattern-wiki-and-pr-state-proposal-ledger.md`
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md`, `knowledge-base/legal/compliance-posture.md` (dated, conditional notes)

All existing paths were confirmed with `git ls-files`/`git ls-tree`. This plan edits no `AGENTS.md`/`AGENTS.rules.md`.

## Deferrals (tracking issue filed in Phase 7, milestone from the roadmap)

One real deferral: the **live-fire** of the create arm, an operator-held ACTION ("fire a manual `cron-compound-promote`
with `input:patterns, allow_create:true`"), which is also where #10550 closes. Its preconditions are written into the
tracker: evidence PRs #11230 and #11231 merged or closed (the week cap counts open `self-healing/auto` PRs, so today
every manual fire returns `week-cap-reached` before reaching the arm); a server-side runtime flag created via
`soleur:flag-create` if the Phase 0 secret-reach check found a non-operator holder; deploy verified; and the
compliance-posture dated note scheduled by the CLO. The other cut items (`owner_skill`, merge-base ratchet lint,
eval-harness registration) are cuts recorded in the Cut List, not deferrals, and get no issue. The cron default flip
stays on the existing ADR-300 flip tracker (#8293). None touches #10551/#10552/#8443.

## Plan Review Revisions (2026-10-26)

A five-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) reviewed this plan; the CTO ruled the
technical forks it raised (`decision-challenges.md`, rows G1-G3). **Applied (mechanical):** the create arm must NOT inherit the
edit arm's synthetic checks (`skill-security-scan PR gate`, `test`) - a faked green scan is the #8203 class; the scan spawns
with `SKILL_SECURITY_SCAN_OFFLINE=1` as CI does; shape allowlist also bans `soleur:`, leading `/word` and `skills/` tokens; the
dry-render adds `harness-parity-tree`; `BASELINE_DECLARED_PROBES` moves to commit 1 and every suite is registered in the commit
that adds it; budget-boundary tests run on a fixture tree; Guard 1 mutation 7 is reworded and rows 8-9 added; gate order puts the
ledger before the budget and render work; classes `week-cap`, `create-open`, `index-empty`, `stub-drift`, `persist` added and
Sentry uses one op name; a two-step shape (memoized `create-propose`, single `create-persist`) with deterministic-branch replay;
`create_arm` is emitted only when the arm ran and `create_requested` on every manual run; the renderer reads `purpose.md` as its
single source; the post-merge AC no longer waits on the weekly cron; deferral issues cut to the single live-fire tracker.
**Declined (taste, recorded):** taking PR A / PR B now (CTO T1 stands; cut line kept); cutting the server-side CI duplicates
(CTO T2/T6/F1 stand - a ready draft needs them - except the CTO G3 conditional for the generator); cutting the top-3 overlap
clause and the `trigger-cron` trim (margin of 4 words kept); a server-side flag now (CTO G1: deferred to the live-fire hold unless
Phase 0 finds a non-operator secret holder).

## Guard Contract

### Guard 1 - Create admission chokepoint

**Property.** No byte reaches `safeCommitAndPr` in the create arm unless every gate in the fixed order passed and the committed path set equals the closed six-path set.

**Assembly.** One chokepoint: `checkCreate()` (verdict union) feeding `collectCreateContent()` feeding the single create-arm `safeCommitAndPr` call in `cron-compound-promote.ts`. The members that must flow through it are every model string (description, list items, nearest-skill justification, merge/retire candidates, purpose fields, slug), the rendered SKILL.md, PURPOSE.md and Cursor stub, the two README outputs of `sync-readme-counts.sh`, and the `promotion-log.md` row. The edit arm's `checkDiffPaths`, `TARGET_ALLOW_RE` and `isAdditiveDiff` are a SECOND, separate chokepoint that must stay byte-identical; the create arm is scoped to its own and a test asserts the edit arm never accepts status `A`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Skip the scan-verdict comparison (treat any exit 0 as pass) and feed a HIGH-RISK fixture | RED |
| 2 | Guard's own dispatch: make the gate run over an empty list of model strings / empty rendered file (scanner returns LOW-RISK on empty input) and exit "ok" | RED (empty input must refuse, and the suite asserts N gates ran, not zero) |
| 3 | A second model string (`merge_retire_candidates[1]`) carries a claim word after a clean first item | RED |
| 4 | Add a seventh path (or a `scripts/` file) to `exactPaths` | RED |
| 5 | Render a fenced block into PURPOSE.md after a clean SKILL.md | RED |
| 6 | README sync changes a non-digit character, or a third file | RED (`readme-sync`) |
| 7 | Reorder: call `safeCommitAndPr` before the scan verdict is read (files must be on disk first, so the window is verdict-read to commit) - a case observing INSIDE the window asserts no `safeCommitAndPr` call occurs when the scan is pending/failed | RED |
| 8 | Inherit the edit arm's `syntheticChecks` (so `skill-security-scan PR gate` is posted green without a real verdict) | RED |
| 9 | Drop `SKILL_SECURITY_SCAN_OFFLINE=1` from the scan spawn environment | RED (env pinned in a spawn spy) |

**Harness rows:** (a) delete the golden render fixture - the suite must FAIL, not skip; (b) a mutation helper
that silently returns the unmutated input must be caught by a self-check that the mutated fixture differs from the
canonical; (c) must-PASS non-canonical input: a differently worded valid proposal (different slug, 15-word
description, three list items) passes, so a gate that rejects everything is detected.

**Anchor.** The path set and word limits are exported constants compared against values in the test file and the
ADR-092 amendment text (pinned by a wording test that strips fenced blocks); a diff weakening a gate must also move
the independently reviewed ADR text and the golden fixtures. Residual: the unit suite proves consistency, not
integrity; the draft-PR human review is the integrity anchor, stated in the ADR.

### Guard 2 - Budget counter and cap

**Property.** The server's description-word count equals the count `components.test.ts` computes, and a create is refused whenever new words exceed `cap - total` or either number is unreadable.

**Assembly.** `countDescriptionWords`, `readBudgetCap`, the budget gate in `checkCreate`, the Phase 1 trim verification, and the parity test are the call sites; the chokepoint is the single exported counter. The counted population is `discoverSkills()` order and the `disable-model-invocation` filter, which both must be shared with the bun test's definition by the parity test over the real tree.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Count `disable-model-invocation: true` skills too (adds 172 words) | RED (parity test) |
| 2 | Own dispatch: counter iterates zero skills and returns 0 | RED (population floor on the real tree) |
| 3 | Second member: a new skill dir added after a compliant first whose frontmatter is malformed | RED (refuse, fail closed) |
| 4 | Change `split(/\s+/)` to `split(" ")` | RED (parity on a description with a double space / newline) |
| 5 | Cap regex returns the first digit run in the history comment instead of the constant | RED |

**Harness rows:** weaken the cap comment parse so a literal in a comment wins - suite must fail; must-PASS
non-canonical: a description of exactly `cap - total` words passes while `cap - total + 1` refuses.

**Anchor.** The cap constant is lowered in this PR and lives in `plugins/soleur/test/components.test.ts`, outside the
create arm's six paths, so the proposer cannot move it; a later human bump remains possible (ratchet lint cut by CTO
ruling T2) and is covered only by review.

### Guard 3 - Scheduled-path invariance

**Property.** A scheduled run, and a manual run with `input` other than `patterns`, execute exactly as before this PR whatever `allow_create` says.

**Assembly.** `readRunOptions` is the single parse site; the `create-propose` step is guarded by its result only.
The scheduled trigger, the manual corpus event, and the manual patterns event are the three entry shapes.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Parse `allow_create` before the manual/patterns check | RED |
| 2 | Own dispatch: emit `create_arm` (or any create field other than `create_requested`) on the scheduled path | RED (marker census) |
| 3 | A truthy non-boolean (`"true"`, `1`) after a valid `true` fixture | RED (must be ignored) |
| 4 | Run the create step on a manual corpus event | RED |

**Harness rows:** the invariance test spies the model client and asserts zero `create-propose` calls on the first
three shapes; must-PASS: manual patterns with `allow_create: true` DOES call it once.

**Anchor.** Marker closed-vocabulary census tests (already CI-required) are the anchor outside this diff's
production code.

### Guard 4 - Stub and Grok-block parity

**Property.** The rendered Cursor stub equals the generator's output and the rendered Grok block equals the pinned canonical, for every skill and for a new one.

**Assembly.** `renderCursorSkillStub`, the Grok block reader, and the per-skill loop in the parity test over all tracked skill folders.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change one character of the generator HEADER | RED |
| 2 | Own dispatch: parity loop over zero folders | RED (population floor) |
| 3 | A second skill folder whose description contains a character the renderer mishandles | RED |

**Harness rows:** drop the synthetic new-skill fixture - suite fails; must-PASS: a skill with `name` differing from
its folder still renders the generator's output.

**Anchor.** `cursor-name-map --check` and `grok-harness-invoke.test.ts` run in CI independently of this suite.

## Test Scenarios

1. Evidence fixtures: a cluster whose nearest skill is `git-worktree` (synthesized from #11230's hash) and one for
   `pencil-setup` (#11231) are refused `prefer-patch`; synthetic negatives (no owner) pass the overlap gate.
2. `no_action` from the model is a valid, clean outcome (marker `create_arm: ran`, no refusal).
3. Budget: description 31 words refused; exactly headroom accepted; unparseable cap refused; cap lowered test.
4. Shape: backtick, fence, URL, rule-id, claim word (each position, including the last list item), non-ASCII.
5. Scanner: HIGH-RISK, REVIEW, empty output, non-zero exit, timeout, missing tool each refuse; LOW-RISK passes.
6. Persistence: six exact paths; a seventh refused; `expectedContent` mismatch refuses commit.
7. Scheduled/corpus/non-boolean flag invariance (Guard 3).
8. Dry-render: all CI-red surfaces green on a synthetic new skill (components, stub, Grok, counts, axis, docs loader).
9. Concurrency: open PR touching the nearest skill or the same slug refuses.
11. Cap saturation: with cap injected as 1 the arm runs end to end; with the real saturated cap the run exits `week-cap-reached`.
12. Replay: Step B run twice finds its own open PR by deterministic branch and reports success; `create-open` refuses when another open PR carries the fixed line (list failure also refuses).
13. Edit arm unchanged: it never accepts status `A`, and a create PR does not post `skill-security-scan PR gate` or `test` as synthetic checks.
10. Ledger: an already-proposed pattern hash is suppressed for create too (#11230/#11231 hashes).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "free skill-description budget first (cq-skill-description-budget-headroom)" [issue #10550] | Phase 1, Proposed Solution trim table | mapped |
| 2 | "new skills are markdown-only and ship with a required `PURPOSE.md`" [issue #10550] | PURPOSE.md contract, shape allowlist, six-path set, Guard 1 | mapped |
| 3 | "security scan (`soleur:skill-security-scan`) on every generated skill" [issue #10550] | Phase 4 `runSkillScan`, gate order, Guard 1 rows 1-2 | mapped |
| 4 | "no net growth in total description words" [issue #10550] | Pre-paid reserve, cap lowered to 2436, Guard 2 | mapped |
| 5 | "Use those two draft PRs as input/evidence." [brief] | Overview evidence use, Test Scenarios 1 and 10 | mapped |
| 6 | "do not touch or comment on #10551, #10552 or #8443; do not start Phase 3" [brief] | Premise Validation, Deferrals, PURPOSE.md contract (no enforcement on existing skills) | mapped |
| 7 | "PR body uses "Ref #10550" unless the plan says the PR completes it" [brief] | Phase 7 (`Ref`, not `Closes`) | mapped |
| 8 | "technical forks go to the soleur:engineering:cto agent, not the operator" [brief] | `decision-challenges.md` | mapped |
| 9 | "merged PR, deploy verified (deploy-arm.sh find --wait, then served), then soleur:postmerge" [brief] | Phase 7, Acceptance Criteria Post-merge | mapped |
| 10 | "A create proposal names the nearest existing skill and justifies not patching it, and emits merge/retire candidates." [doc spec FR13] | model output fields, prefer-patch gate, PURPOSE headings | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Trim table + cap lowering | "free skill-description budget first" | asked |
| Server-rendered SKILL.md/PURPOSE.md, shape allowlist | "new skills are markdown-only and ship with a required `PURPOSE.md`" | asked |
| `runSkillScan` gate | "security scan (`soleur:skill-security-scan`) on every generated skill" | asked |
| Budget gate and counter | "no net growth in total description words" | asked |
| Evidence fixtures | "Use those two draft PRs as input/evidence." | asked |
| Dark-launch flag `allow_create` | — | inferred — justification: CTO ruling T1 and the Phase 1 precedent (ADR-300) keep the scheduled baseline clean; the brief says "do not start Phase 3" and a live production create needs operator authorization |
| Cursor stub renderer | — | inferred — justification: CI `cursor-name-map` goes red for any new skill directory (CTO F1) |
| README count sync | — | inferred — justification: CI `lint-bot-statuses` goes red unless counts move (CTO T6) |
| PII/credential screen on rendered output, claim-word check | — | inferred — justification: CLO 2026-10-26, output surface is the public plugin |
| `create-refused` marker reason + `kind` field | "emits merge/retire candidates" / observability | inferred — justification: CTO missed-fork 1; keeps census churn to one reason and makes refusals visible without SSH |
| ADR-092 amendment + ADR-300 addendum | — | inferred — justification: plan Phase 2.10 makes the ADR a deliverable of the plan that changes the boundary |
| Legal register notes | — | inferred — justification: CLO 2026-10-26 (PA-31 output surface widens) |
| Deferral issues | — | inferred — justification: `wg-when-deferring-a-capability-create-a` |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform`, `plugins/soleur`, `knowledge-base`
- Planned files: ~38 | Estimated changed lines: ~1500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - CTO ruling T1 (2026-10-26): one PR in six commits with a fixed order; cut line if review objects: PR A = commits 1-2 (budget freeing, ADR/template/legal notes), PR B = commits 3-6 (modules, wiring, registration). Over the file and line thresholds, justified by the six-commit order and the fact that commits 1-2 are independently valid.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `SKILL_DESCRIPTION_WORD_BUDGET` is lower than at branch base, equals the measured pre-trim total, and headroom after the trims is >= 30 (`bun test plugins/soleur/test/components.test.ts`).
- [ ] The five trimmed descriptions match the plan table text exactly; `cursor-name-map --check` passes; the PR body lists the five regenerated stub paths.
- [ ] A scheduled run and a manual `input: corpus` run with `allow_create` set make zero `create-propose` calls (Guard 3 tests).
- [ ] The evidence fixtures for #11230 and #11231 are refused `prefer-patch`; at least four synthetic negatives pass the overlap gate; the threshold constant is exported and read by prompt, check and PR-body trailer.
- [ ] Every Guard Contract mutation row has a test that reds when the mutation is applied (including harness rows), and `python3 scripts/lint-guard-contract.py <this plan>` passes.
- [ ] The scan gate refuses HIGH-RISK, REVIEW, empty, non-zero, timeout and missing-tool; accepts only the exact LOW-RISK first line with exit 0.
- [ ] The create arm's commit path set is exactly the six paths; a seventh is refused; the edit arm's allowlist test is unchanged and still green.
- [ ] The dry-render test passes every CI-red surface listed in Phase 5 against a synthetic new skill.
- [ ] Outcome census and marker tests pass with the new `create-refused` reason, `class` enum, `kind` and `create_arm` fields; the runbook and `betterstack-log-query.md` carry the new rows.
- [ ] ADR-092 amendment and ADR-300 addendum exist and are wording-pinned; legal register notes are dated and conditional.
- [ ] `c4-count-parity.test.sh`, `bash scripts/sync-readme-counts.sh --check`, `lint-skill-body-budget.py` and the affected-suite census are green on the merged tree.
- [ ] PR body says `Ref #10550` (no `Closes`), carries the `## Changelog` section, and does not mention #10551, #10552 or #8443 as acted-upon.

### Post-merge

- [ ] `plugins/soleur/scripts/deploy-arm.sh find --wait` returns the release/deploy arm run for the merge SHA, and the served `/health` `build_sha` equals the merge SHA.
- [ ] No marker carries `create_arm` after the deploy, and no Sentry event with op `create-refused` exists (`bash scripts/betterstack-query.sh --since 1d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME`). Observational, non-gating: the weekly cron cadence can exceed the post-merge window, so scheduled-path equivalence is proven pre-merge by the invariance tests.
- [ ] `soleur:postmerge` prints `postmerge verification complete!`.
- No production create is fired by this PR (T8); the live-fire is the tracked deferral.

## Risks

- **Image tooling unverified:** a missing tool makes the arm fail closed (safe, silent without the marker); Phase 0 proves the tool set.
- **Trim quality:** shortening routing descriptions can degrade routing; trims remove redundant clauses only and a reviewer approves the wording.
- **Overlap threshold fitted to two points:** mitigated by synthetic negatives and by choosing the stricter side; relax later.
- **Residual leakage:** the input PII screen is best-effort; the output screen and human review are the compensating controls (stated, not oversold).
- **Census/ratchet churn:** sibling PRs bump the preflight probe ratchet and census literals; re-read at work time and on every rebase.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- Cap lowered means a sibling PR adding a skill during this PR's life breaks the trim arithmetic: re-measure after every rebase.
- Generated prose must not contain backticked `scripts/`, `references/`, `assets/` strings (components test regex).
- `run-scan.sh` returns exit 0 and LOW-RISK on empty input; the gate asserts non-empty, minimum-size input before scanning.
- The Cursor stub embeds the description: any later description trim needs a stub regeneration.

## References

- Issue #10550; evidence PRs #11230, #11231; ADR-092, ADR-300, ADR-236, ADR-054.
- Brainstorm: `knowledge-base/project/brainstorms/archive/20260918-160549-2026-09-18-wikiskill-skill-evolution-brainstorm.md`;
  spec: `knowledge-base/project/specs/archive/20260918-160549-feat-wikiskill-skill-evolution/spec.md` (FR11-FR15, TR4).
- Prior plan: `knowledge-base/project/plans/archive/20261025-180706-2026-10-24-feat-wikiskill-pattern-layer-proposer-index-ledger-reader-plan.md`.
