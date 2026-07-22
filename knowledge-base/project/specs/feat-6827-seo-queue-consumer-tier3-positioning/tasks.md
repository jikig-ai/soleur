---
feature: seo-refresh-queue producer/consumer contract + competitor-claim substantiation
issue: 6827
branch: feat-6827-seo-queue-consumer-tier3-positioning
pr: 6830
plan: knowledge-base/project/plans/2026-07-22-feat-seo-queue-contract-and-competitor-claim-substantiation-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-07-22
---

# Tasks — SEO Queue Contract + Competitor-Claim Substantiation

Derived from the finalized plan. **Phase order is load-bearing**: the contract change (Phase 2)
precedes its consumers (Phase 3), and 3.1 + 3.2 are ONE commit (AC9).

## Phase 0 — Preconditions

- [ ] **0.1** Capture artifact-age baseline: `bash scripts/cron-artifact-age.sh --all; echo "rc=$?"`
- [ ] **0.2** Confirm cron tests green **before** editing:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-content-generator.test.ts`
      (vitest — NOT `bun test`; `bunfig.toml` blocks bun discovery)
- [ ] **0.3** Record the FR6 baseline metric:
      `grep -c 'generated_date' knowledge-base/marketing/seo-refresh-queue.md` — write the number
      into the PR body; AC10 and AC16 both compare against it
- [ ] **0.4** Confirm ADR ordinal still free:
      `ls knowledge-base/engineering/architecture/decisions/ | grep -c ADR-133` → `0`
- [ ] **0.5** Re-run the FR2 sweep and diff against the plan's §FR2 Sweep Result table; report any
      delta (the plan's table is the expected result, not a method to re-derive)

## Phase 1 — FR1 + FR2: correction sweep

- [ ] **1.1** Correct all **seven** stale figures in
      `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`
      (`:13`, `:25`, `:45`, **`:53`**, `:76`, `:98`, `:136`) to the `74,000+` soft-floor form.
      `:53` is the `14,600+` comma form the spec's six-line list missed.
- [ ] **1.2** Preserve each sentence's surrounding clause — do not re-point a dependent clause onto
      the new figure (the `#6538` additive class, `review/SKILL.md:1055`)
- [ ] **1.3** Add a dated correction note mirroring the blog twin's `:17` disclosure pattern
      (`**Updated 2026-07-22:**` + figure + verification source)
- [ ] **1.4** Verify AC1: `grep -rniE '14\.6k|14,600|14600' knowledge-base/marketing/` → zero

## Phase 2 — FR3: producer write-target (contract side FIRST)

- [ ] **2.1** Edit the Cascade Delegation Table row in
      `plugins/soleur/agents/product/competitive-intelligence.md:54`: replace
      `Append stale pages list to …` with an in-place §2.1/§2.2 row-update instruction
      (set `Status` to `Stale — Update` / `Create`, clear `generated_date`, add a new §2.1 row when
      none matches)
- [ ] **2.2** Add an explicit prohibition on appending a new
      `## Stale Comparison Pages Flagged for Regeneration (…)` block below `## Refresh Schedule`
- [ ] **2.3** Add a one-line ADR-133 pointer for rationale

## Phase 3 — FR4 + FR5: consumer predicate + backfill — **ONE ATOMIC COMMIT**

- [ ] **3.1** (FR4) In `apps/web-platform/server/inngest/functions/cron-content-generator.ts`,
      replace the STEP 1 selection sentence with the positive predicate: `Status` contains `Stale`
      or `Create` **AND** no `generated_date`, drawn from §2.1/§2.2 only, with §1.1–§1.7 explicitly
      never selectable
- [ ] **3.2** (FR4) Keep the `Priority 1 first, then Priority 2 pillar, then Priority 2 comparison`
      ordering clause verbatim; touch **none** of the ten asserted anchors
- [ ] **3.3** (FR4) Mark the `// Verbatim prompt extracted from .github/workflows/…` comment
      `[superseded]` — the workflow was deleted in #4483; the TS file is now the sole source
- [ ] **3.4** (FR5) Backfill `knowledge-base/marketing/seo-refresh-queue.md` per the plan's Phase 3
      disposition table:
      - [ ] Polsia + Paperclip → update `generated_date` to `2026-07-20` (drained, not eligible)
      - [ ] Notion, Cursor, Best-Plugins → `Stale — Update`, clear `generated_date` (**eligible ×3**)
      - [ ] NanoCorp, OpenAI Codex, Replit Agent → **new** §2.1 rows, `Won't do (2026-07-22)` + reason
      - [ ] Tanka, CrewAI → `Won't do (2026-07-22)` + reason in `Status`, retain `generated_date`
- [ ] **3.5** (FR5) Annotate BOTH dated blocks
      `[SUPERSEDED — migrated to §2.1/§2.2 on 2026-07-22; retained as audit trail]`; do **not** delete
- [ ] **3.6** (FR5) Bump `last_updated` / `last_reviewed` to `2026-07-22`
- [ ] **3.7** **TR5 guard** — do not touch `## Priority 1: Stale Pages (Update Immediately)` or any
      `### 1.x` heading (`cron-growth-execution` binds to them)
- [ ] **3.8** Commit 3.1–3.7 together. Verify AC9 per-commit (NOT `git log -- A B`, a union filter):
      `git rev-list origin/main..HEAD -- <paths>` then `git show $sha --name-only` for each

## Phase 4 — FR6: artifact-delta observability

- [ ] **4.1** Create `scripts/seo-queue-drain-delta.sh`: walk default-branch commits matching
      `^feat\(content\): auto-generate article`; per commit compute
      `git show <sha>:knowledge-base/marketing/seo-refresh-queue.md | grep -c generated_date`;
      STALE when no increase across the last N, threshold derived from `0 10 * * 2,4` (never a flat
      constant); exit 0 PASS / 1 STALE; `--report` mode for the discoverability test
- [ ] **4.2** Create `scripts/seo-queue-drain-delta.test.sh` mirroring
      `scripts/cron-artifact-age.test.sh` structure; include a fixture for the
      "committed but drained zero rows" case — that is the defect the detector exists to catch
- [ ] **4.3** Register **by name** in `scripts/test-all.sh`
      (`run_suite "scripts/seo-queue-drain-delta" bash scripts/seo-queue-drain-delta.test.sh`) —
      no glob covers `scripts/*.test.sh` (`test-all.sh:141-144`)
- [ ] **4.4** Add the detector as a **second step** in the existing
      `.github/workflows/scheduled-cron-artifact-age.yml` job; leave the existing step's `rc`
      capture and report gating untouched
- [ ] **4.5** Create `scripts/followthroughs/seo-queue-drain-6827.sh` (soak probe; sample window
      pinned strictly after the merge commit; exit 1 = still soaking, NOT failure)
- [ ] **4.6** Add the follow-through directive + `follow-through` label to #6827:
      `<!-- soleur:followthrough script=scripts/followthroughs/seo-queue-drain-6827.sh earliest=<merge+8d> -->`
- [ ] **4.7** Regression-check the shared detector: `bash scripts/cron-artifact-age.test.sh`

## Phase 5 — FR8 + contract guards

- [ ] **5.1** Add a conditional-agent path-trigger block to `plugins/soleur/skills/review/SKILL.md`,
      mirroring the `#5871` / anti-slop block form (`:274`, `:284`), keyed on
      `(^|/)plugins/soleur/docs/blog/.*vs-.*\.md$` and
      `(^|/)knowledge-base/marketing/distribution-content/.*vs-.*\.md$`
- [ ] **5.2** The block **cites** `review/SKILL.md:1055` + `brand-guide.md:97` — does not restate
      them (restating creates the replicated-literal drift class `:965` warns about)
- [ ] **5.3** Add STEP 1 block-scoped tests to `cron-content-generator.test.ts` using
      `SUT_SOURCE.match(/STEP 1 —[\s\S]*?\nSTEP 2 —/)`: positive tokens present, §1.x exclusion
      present, `without a "generated_date" annotation` absent
- [ ] **5.4** Add a cascade-table guard test asserting
      `plugins/soleur/agents/product/competitive-intelligence.md` no longer contains
      `Append stale pages list`

## Phase 6 — FR7: substantiate takeaway #7

- [ ] **6.1** Rewrite `knowledge-base/product/competitive-intelligence.md` takeaway #7 (`:120`)
      splitting **verified** (HITL approval gates — "nothing ships without your approval";
      11-domain breadth) from **unsubstantiated** (pricing, revenue-share, memory architecture,
      data ownership / "graduation"), with `Retrieved 2026-07-22 from cofounder.co`
- [ ] **6.2** Keep the `$8.7M seed / USV` funding claim (verifiable third-party signal, cited);
      flag `Pro $20/mo` as unsubstantiated per TR4
- [ ] **6.3** **Anti-half-sweep:** add one-line pointers to takeaway #7 from
      `knowledge-base/product/business-validation.md:83` and the Tier-3 table row at `:100`

## Phase 7 — ADR + verification

- [ ] **7.1** Write `ADR-133-seo-refresh-queue-canonical-section-and-positive-predicate.md` with
      `## Decision` + `## Alternatives Considered` (record the rejected "new machine-readable
      section" option). Cite ADR-126 for the FR6 extension. Ordinal is **provisional** — re-verify
      against `origin/main` and sweep `grep -rn 'ADR-133' knowledge-base/project/{plans,specs}/feat-6827-*/`
      if renumbered
- [ ] **7.2** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/`
- [ ] **7.3** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      (NOT `npm run -w …` — repo root declares no `workspaces` field)
- [ ] **7.4** `bash scripts/test-all.sh` (exit gate)
- [ ] **7.5** Walk AC1–AC15; record each verdict
- [ ] **7.6** PR body: FR2 sweep table + both scope-outs + FR6 layer name + **`Ref #6827`**
      (NOT `Closes` — the issue stays open for the two deferred checklist items)
