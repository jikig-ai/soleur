---
title: "feat: enable self-improvement loop + operator-digest 'got smarter' section"
date: 2026-07-06
issue: "#6039"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-06-self-improvement-changelog-brainstorm.md
spec: knowledge-base/project/specs/feat-self-improvement-changelog/spec.md
deferred_followup: "#6102"
scope_note: "Operator chose 'bundle both' (2026-07-06): enable the compound-promote loop AND ship the digest section, so the dogfood surfaces a real pipeline. Larger than #6039 as originally framed."
---

# Plan: Enable the self-improvement loop + operator-digest "got smarter" section ✨

## Overview

Two coupled work streams, one PR:

- **Stream A — Enable the compound-promotion loop.** Flip
  `knowledge-base/project/promotion-config.yml` `enabled: false → true`. This
  turns on the weekly Inngest cron (`cron-compound-promote`) that clusters
  learnings and opens **human-gated draft PRs** (never auto-merged) proposing
  `AGENTS.core.md` / `SKILL.md` edits, capped 2/week. Without this, the digest
  section (Stream B) renders empty forever — the loop has never produced a
  promotion because it is switched off, not quiet.
- **Stream B — "What got smarter this week" digest section.** Add a fifth
  section to `operator-digest/SKILL.md` surfacing *completed* self-improvements
  (merged `self-healing/auto` PRs) to the operator in plain, platform-truthful
  language, with an honest empty state.

Bundling makes the dogfood real: enabling creates the pipeline (draft PRs → the
operator reviews/merges → the digest surfaces the merge), so the operator can
watch the loop actually work. The founder-facing surface remains deferred to
#6102.

**Why enabling is safe now (verified live):** the loop shipped and was closed
via #2720/#3559; its GDPR gate ran at build time (audit
`knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`),
its Anthropic-DPA blocker #3594 is **CLOSED** (row present at
`compliance-posture.md:81`; DPA effective 2025-02-24, SCCs M2+3), it is
registered in the Article 30 register (PA-22 scope), it never auto-merges
(draft PRs, `mergeMode "none"`), and a `PII_REGEX` pre-pass excludes
email/IP/IBAN/key-shaped learnings before the Anthropic call + redacts the
diff if PII appears in LLM output. The one deferred item — a DPIA
re-evaluation (Art. 35) at week-4 of operation — is started (not blocked) by
enabling, and is enrolled as a soak follow-through below.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| 0 promotions = loop is quiet | `promotion-config.yml` is `enabled: false` — loop is **off**, never run | Stream A enables it (operator's "bundle both" decision) |
| Digest queries PRs via a §5-own `gh pr list --label` | `gh pr list --label` cross-repo under the App token is **unproven** (§4 proves the *issues* endpoint, a different code path; §1's proven call is bare `gh pr list --state merged`) | **Reuse §1's proven call**, add `number,url` to its `--json`, and filter `labels[].name=="self-healing/auto" && mergedAt>=$SINCE` client-side. §5 makes **no** `gh` call → no `--search`, no routing assumption, inherits §1's read + ⚠️ failure handling. |
| Source = merged self-healing PRs **+ retired rules** | retired-rules (`git log -p scripts/retired-rule-ids.txt`) is a second source that exits 0 on a wrong path (indistinguishable from empty — FR3/FR4 breach), untested by ACs, and creates a 3×3 state space | **Cut retired-rules for v1** (code-simplicity + spec-flow). Single source (merged self-healing PRs) → clean 3-state model (populated / empty / ⚠️). Re-add when the loop proves productive (track on #6102). |
| TR3 "real-shape fixture test" | operator-digest is prose-only (no code to run a fixture through) | Document the production PR-title/label shape in §5 as the LLM's grounding example; empty is the current real state. Satisfies `cq-test-fixtures-synthesized-only`. |
| `## The four sections` appears at 3 sites | Also at **SKILL.md:72** (`## The four sections` heading) — 4th site (Kieran P0) | Phase 2 edits all four: intro (14-15), scope L1 (54), heading (72), output (205) |
| `compliance-posture.md:120` shows #3594 OPEN | #3594 is **CLOSED** (#3596) — Active-Items row is stale | Fold a one-line status fix into Stream A (directly on-point: it was the enable blocker) |

## Implementation Phases

### Phase 1 (Stream A) — Enable the loop

1. `knowledge-base/project/promotion-config.yml`: `enabled: false` → `enabled: true` (per runbook `compound-promote-runbook.md` "Opt in"). This is the committed flip operators review.
2. `knowledge-base/legal/compliance-posture.md:120`: update the stale #3594 Active-Items row from `OPEN` to `CLOSED (#3596 — Anthropic DPA row added; loop enable unblocked 2026-07-06)`.
3. (Post-merge, automatable) trigger the first run via the existing `/soleur:trigger-cron` path or `curl -X POST .../api/inngest -d '{"name":"cron/compound-promote.manual-trigger"}'` — do NOT wait for Sunday. See AC-post.

### Phase 2 (Stream B) — Digest section (hardened v1, single source)

Edit `plugins/soleur/skills/operator-digest/SKILL.md`:
1. Intro (14-15): "four sources … four sections" → "five sources … five sections."
2. Scope L1 (54): "four named sources" → "five named sources."
3. Section heading (72): `## The four sections` → `## The five sections`.
4. §1 data call: add `number,url` to its `--json` (`title,labels,mergedAt,number,url`). These fields are used **only** by §5's substantiation links; §1's own prose rules are unchanged (still no PR numbers, no author field per register L3).
5. New `### 5. What got smarter this week` after §4, before "Deterministic fallback":

   ```markdown
   ### 5. What got smarter this week

   Source: the self-improvements the loop **completed** in the window —
   promotion PRs merged into how your agents work. Reuse §1's already-fetched
   PR list (do NOT run another `gh` call, and NEVER `--search` — the Search API
   is empty cross-repo under the App token). From that list keep PRs whose
   `labels` contains `self-healing/auto` AND whose `mergedAt >= $SINCE`.
   Production shape: title `self-healing(auto): promote cluster <hash> <date>`,
   label `self-healing/auto`.

   Render as a **platform-level outcome**, never per-tenant: "Soleur got
   sharper this week — N improvements shipped to the shared brain your agents
   run on," followed by a compact `details:` line linking each PR (`url`) as
   substantiation. Do NOT invent per-item descriptions from the cluster-hash
   title (it carries no human summary; reading PR bodies would breach L2).
   **Never write "your workspace got smarter"** — the improvement is to the
   shared Soleur harness, not the operator's own workspace.
   ```
6. Deterministic fallback list (175-178): add "Section 5 → \"Nothing was promoted to the shared harness this week.\""
7. Output (205): "four `##` sections" → "five `##` sections."

§5 inherits the skill's existing Read-failure handling (a §1 read failure → ⚠️,
FR4) and L2 summaries-only (FR: no raw bodies/records). Single source → the
9-state explosion spec-flow flagged does not arise.

## Files to Edit

- `knowledge-base/project/promotion-config.yml` — enable flip (Stream A).
- `knowledge-base/legal/compliance-posture.md` — stale #3594 row fix (Stream A).
- `plugins/soleur/skills/operator-digest/SKILL.md` — the 7 edits above (Stream B).
- `scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` — **new**, week-4 DPIA re-eval follow-through (see Observability §Soak).
- `.github/workflows/scheduled-followthrough-sweeper.yml` — wire the new follow-through's secrets if any (likely none — a date-gated reminder).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `promotion-config.yml` reads `enabled: true` (`grep -c '^enabled: true' <file>` == 1).
- [ ] AC2 — `compliance-posture.md` #3594 row no longer shows OPEN (`awk '/#3594/{print}' <file> | grep -c OPEN` == 0).
- [ ] AC3 — operator-digest/SKILL.md has a `### 5. What got smarter this week` heading (`grep -c '### 5. What got smarter this week' <file>` == 1).
- [ ] AC4 — §5 makes no independent `gh` call (it reuses §1's data): `awk '/### 5\./{f=1;next}/^## [^#]/{f=0}f' <file> | grep -cE '^\s*gh '` == 0. (This also guarantees no `--search` in §5.)
- [ ] AC5 — the platform-framing guardrail line is present: `grep -c 'Never write "your workspace got smarter"' <file>` ≥ 1. *(Assert the guardrail's presence — do NOT grep for absence of "your workspace", which false-fails because the guardrail line itself contains the phrase — Kieran P0.)*
- [ ] AC6 — §1's `--json` includes `number,url`: `grep -cE 'gh pr list.*--json' <file>` shows the field list contains `number` and `url`.
- [ ] AC7 — fallback list has the Section 5 line: `grep -c 'Nothing was promoted to the shared harness' <file>` == 1.
- [ ] AC8 — all four "four sections/sources" sites updated: "four" appears in the skill ONLY in those references, so `grep -ciw four <file>` == 0 AND `grep -c 'five' <file>` ≥ 3.
- [ ] AC9 — skill still parses / budget intact: `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] AC10 — DPIA follow-through enrolled: `scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` exists, is executable, and a `follow-through`-labelled tracker carries the `<!-- soleur:followthrough script=… earliest=<enable+28d> -->` directive.

### Post-merge (operator)
- [ ] AC11 — Trigger the first loop run (automatable via `/soleur:trigger-cron cron/compound-promote.manual-trigger` — no SSH, no waiting for Sunday). Confirm the run fired via the `scheduled-compound-promote` Sentry monitor.
- [ ] AC12 — On the next operator-digest run, §5 renders "Nothing was promoted to the shared harness this week." (until the operator merges a promotion draft PR) OR the ⚠️ read-failure line — never blank. Verify by reading the next `Digest:` issue.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing (brainstorm carry-forward + this plan's enable-the-loop delta).

### Product (CPO)
**Status:** reviewed (brainstorm carry-forward). **Assessment:** Dogfood-first; "bundle both" makes the dogfood surface a real pipeline. Per-tenant framing must not ship (enforced AC5). CPO sign-off carried (`requires_cpo_signoff: true`).

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward + live compliance verification). **Assessment:** Enabling activates an **already-registered** processing activity (Art 30 PA-22; Anthropic DPA effective, #3594 CLOSED), not a new one. Data-minimization is built in (PII_REGEX pre-pass + diff redaction + draft-only human gate). Digest §5 is platform-framed (AC5), sanitized (L2), count+link only. Deltas: fix stale compliance row; enroll week-4 DPIA re-eval follow-through.

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward + plan research). **Assessment:** §5 reuses §1's proven List-API call (client-side label filter) — avoids the unproven `--label`-on-`gh pr list` routing and the Search-API-under-App-token trap. Enabling is a config flip on built infra; the loop's Sentry monitor (`scheduled-compound-promote`) already provides liveness. No new infra, no ADR (see below).

### Marketing (CMO)
**Status:** reviewed (brainstorm carry-forward). **Assessment:** "Soleur / your agents / shared brain got sharper" framing; honest empty state (not filler). Founder channel deferred to #6102.

### Product/UX Gate
**Tier:** none — no UI surface (config flip + doc edits + prose SKILL.md; digest output is markdown in a private issue). No `components/**/*.tsx` / `app/**/page.tsx`. **Pencil:** N/A.

## User-Brand Impact

**If this lands broken, the user experiences:** either the loop opens low-quality/unwanted self-edit PRs the operator must wade through (mitigated: human-gated draft PRs, 2/week cap, kill switch), or the digest §5 renders a false "nothing" off a silently-failed read (mitigated: reuse §1's proven call + inherited ⚠️).
**If this leaks, the user's data is exposed via:** a learning containing un-regex-caught named PII being summarized to Anthropic (mitigated: PII_REGEX pre-pass + operator's own DPA-covered key + draft-PR human review), or a raw record copied into the digest (mitigated: L2 summaries-only + count+link-only render).
**Brand-survival threshold:** single-user incident. CPO sign-off carried from brainstorm; `user-impact-reviewer` runs at PR review.

## Observability

**Stream A (loop):** liveness already exists — Sentry monitor `scheduled-compound-promote` (per runbook); `pii-excluded`/`retired-excluded`/`branch-name-shape-failed` structured log lines already emit. No new observability code needed; cite the existing monitor.

**Stream B (digest):** pure prose skill (no code-class file) — inherits operator-digest's ⚠️ read-failure contract as the operator-facing signal. Phase 2.9 skip criteria met for the prose edits.

### Soak follow-through (Phase 2.9.1)
Enabling starts the #2720 **DPIA re-evaluation** clock (Art. 35, deferred to week-4 of operation per `compliance-posture.md:119`). Enroll:
- **Script:** `scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` — exit 0 before `enable-commit + 28d`; after, exit non-zero to surface "run the #2720 DPIA re-evaluation (cluster count / false-positive rate / operator merge-ratio now available)."
- **Tracker:** a `follow-through`-labelled issue carrying `<!-- soleur:followthrough script=scripts/followthroughs/dpia-reeval-compound-promote-2720.sh earliest=<enable-commit-date + 28d> -->`.
- **Sweeper:** `.github/workflows/scheduled-followthrough-sweeper.yml` picks it up; no new secrets (date-gated reminder).

## Architecture Decision (ADR/C4)

**No new ADR.** Enabling a built, ADR-covered loop (ADR-027 stateless self-modifying cron; ADR-033 cron invariants) is not a new architectural decision, and adding a prose digest section changes no substrate/tenancy/resolver. A competent engineer reading existing ADRs + C4 is not misled. The **founder-surface** architecture (delivery + tenant attribution) remains #6102's ADR.

## Open Code-Review Overlap

**None** — no open `code-review` issue references `operator-digest`, `promotion-config`, or `compliance-posture` (checked 2026-07-06).

## GDPR / Compliance Gate

Trigger (a)+(b) fire (LLM processing of operator data + single-user-incident threshold). **Assessment cites the completed #2720 gate** rather than re-deriving: the loop's Phase-2.7 gate ran at build time (audit `2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`); findings folded as #2720 AC23/AC26/AC27; Anthropic DPA row added (#3594 CLOSED, present at `compliance-posture.md:81`); Art 30 PA-22 registration covers the Jikigai-keyed clustering call; PII_REGEX pre-pass + draft-only human gate are the data-minimization controls. **Incremental deltas this plan adds:** (1) fix the stale #3594 row; (2) enroll the week-4 DPIA re-evaluation follow-through (the one deferred Art. 35 item, started — not blocked — by enabling). No new full gate run needed; no unmitigated finding.

## Test Scenarios

1. **Empty week (current + post-enable-until-first-merge):** 0 merged `self-healing/auto` PRs → §5 renders "Nothing was promoted to the shared harness this week." (not blank).
2. **Populated week:** ≥1 merged `self-healing/auto` PR in §1's window → §5 renders "Soleur got sharper this week — N improvements … details: [PR links]" with no cluster-hash jargon and no "your workspace".
3. **§1 read failure:** §1's `gh pr list` exits non-zero → the ⚠️ read-failure line fires for §1 AND §5 (shared read) — NOT a quiet-week fallback.
4. **Enable + kill switch:** after flip, `cron/compound-promote.manual-trigger` fires a run (Sentry monitor green); flipping `enabled: false` makes the next tick exit no-op.

## Sharp Edges

- **Never `gh pr list --search` in §5.** Under the operator-digest App token the Search API is empty cross-repo (renders a false "0 improvements" = silent read failure). §5 reuses §1's proven List-API call and filters client-side. Enforced by AC4. (Note for future editors: `cron-compound-promote.ts:349` uses the Search API for `self-healing/auto` successfully — but under a *different* token; that is NOT license to use `--search` in the digest.)
- **Enable is human-gated by design** — the loop opens *draft* PRs (`mergeMode "none"`); the operator's merge is the gate. Do not add auto-merge.
- The DPIA re-eval is a real Art. 35 commitment deferred to week-4; the follow-through enrollment (AC10) is what keeps it from rotting — do not drop it.
- This plan's `## User-Brand Impact` is filled (passes deepen-plan Phase 4.6).
