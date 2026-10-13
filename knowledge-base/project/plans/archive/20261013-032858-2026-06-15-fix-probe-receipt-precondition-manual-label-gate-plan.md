---
title: "fix: probe-receipt precondition for hr-never-label-any-step-as-manual-without"
date: 2026-06-15
type: fix
branch: feat-one-shot-probe-receipt-manual-label-gate
lane: procedural
status: deepened
brand_survival_threshold: none
---

# fix: Probe-receipt precondition for `hr-never-label-any-step-as-manual-without`

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** byte-budget feasibility, proposed rule body, acceptance criteria, learnings cross-refs

### Key improvements from deepen-plan (deepen-plan caught a budget bust)
1. **The original draft rule body was 698 bytes — 164 over the current 534-B line.** It would have
   breached BOTH the 600-B per-rule cap (`lint-agents-rule-budget.py`) AND the 23000-B B_ALWAYS
   ceiling (projected 23141, REJECT). The verify-the-negative pass measured it; a budget-feasible
   549-byte body (`v10`, measured below) replaces it. Net B_ALWAYS impact = +15 B → 22992 ≤ 23000.
2. **AC2 was measuring characters, not bytes.** The budget linter measures UTF-8 bytes
   (`lint-agents-rule-budget.py:101` → `len(line.encode("utf-8"))`), but the original AC used
   `awk '{print length}'` (char count). The current line is 534 B / 532 chars (multibyte `≡`, `→`,
   curly quotes), so the metrics diverge. AC2 now measures bytes via a Python one-liner that
   mirrors the linter exactly. The chosen body is ASCII-only (drops `≡`/`→`/curly quotes), so byte
   count == char count, eliminating the drift class entirely (also satisfies
   `cq-regex-unicode-separators-escape-only` by avoiding unicode in the rule line).
3. **AC list trimmed 10 → 6** (code-simplicity-reviewer): AC4/AC5/AC10 were subsumed by AC6
   (`test-all.sh` already runs `lint-rule-ids-live` + `lint-agents-rule-budget-{live,unit}` +
   `lint-agents-enforcement-tags`) or tested an unedited file.
4. **A fourth orphan reference exists:** `provision-hetzner/SKILL.md` also cites the id (not just
   ship/work). Renaming the id would orphan three skill files — reinforces "do not touch `[id:]`".
5. **AC9 globstar fix:** `ls knowledge-base/.../**/<slug>.md` degrades to one level without
   `shopt -s globstar`; pinned to the `workflow-patterns/` dir (where the file lands).

## Overview

Tighten hard rule `hr-never-label-any-step-as-manual-without` in `AGENTS.core.md` so an
agent cannot label a browser/portal/UI step operator-gated **by assumption**. This is a
workflow-gap fix (`wg-when-a-workflow-gap-causes-a-mistake-fix`): the rule's current soft
phrasing — "re-verify a plan's 'not feasible' claim at execution time" — let an agent
rationalize past the gate. The fix replaces that soft re-verify clause with a **hard,
checkable probe-receipt precondition**: you may not write an auth-gated/manual/no-session
label for a browser step UNLESS the session transcript already holds a Playwright MCP
`browser_navigate` + `browser_snapshot` against that exact surface evidencing the blocker.

The rule's `[id]` is immutable (`cq-rule-ids-are-immutable`) and stays `hr-never-label-any-step-as-manual-without`.
The pointer line in `AGENTS.md` stays `→ core`. A learning file dated 2026-06-15 documents the
incident and is cited in the rule's `**Why:**`.

### The incident (premise — validated)

During a LinkedIn MDP-access task, an agent wrote "auth-gated — no persisted session to drive
headlessly" into a **user message and two GitHub issues WITHOUT ever invoking Playwright**. A
later probe showed the Playwright MCP session was already authenticated: "My apps" listed
**Soleur Community** (app `229658411`) and **Soleur** (app `229637496`), both Jikigai Company
verified. The agent asserted an unprobed auth state; that assertion *was* the violation.

This is the **third** bypass of the same rule class:
- PR #4227 — deferred inline-automatable steps.
- PR #5082 — deferred a browser-automatable step by asserting an MFA gate (learning
  `2026-06-10-playwright-attempt-evidence-before-operator-only.md`, which added a
  `playwright-attempt:` evidence line to work Phase 4 + ship Phase 5.5).
- **This fix** — closes the remaining hole the prior two left open: the prior gates fire on
  *deferral/operator-step classification*, but the LinkedIn incident leaked the unprobed claim
  straight into a **user message and GitHub issues** with no deferral artifact at all. The
  precondition must bind on the *act of writing the label anywhere*, not only on classifying a
  step as operator-only.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
| --- | --- | --- |
| Rule lives in `AGENTS.core.md` | Confirmed — line 13 under `## Hard Rules` | Edit in place |
| Rule body has room to extend | **534 / 600 B** per-rule cap (66 B headroom) | Per-rule cap OK, but see B_ALWAYS below |
| AGENTS.core.md can absorb net bytes | **B_ALWAYS = 22977 / 23000 B** — only **23 B** to the hard REJECT | **Net byte change MUST be ≤ 0.** Rewrite in place; trim the soft re-verify clause + tighten Why to fund the new precondition |
| Cited learning `2026-06-10-oauth-consent-screens` exists | Yes — at `learnings/workflow-patterns/2026-06-10-oauth-consent-screens-are-playwright-automatable-not-operator-only.md` (Why uses a shortened slug) | Keep; no change needed |
| Rule is referenced elsewhere | `ship/SKILL.md`, `work/SKILL.md`, **and `provision-hetzner/SKILL.md`** all cite the id | New precondition is consistent with existing enforcement sites; no edit required there. Three orphan-risk sites reinforce: do NOT rename the `[id:]` |
| OAuth-consent carve-out can be dropped from the line | Survives in learning `2026-06-10-oauth-consent-screens-...md` + work Phase 4 + ship Phase 5.5 | Safe to drop the duplicate from the always-loaded line (frees bytes) |
| Draft body fits the budget | **NO — original 698-B draft would REJECT** (per-rule 698>600; B_ALWAYS→23141>23000) | Replaced with measured 549-B body (deepen-plan verify-the-negative pass) |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator continues to receive
"this is auth-gated, do it yourself" messages for tasks the agent could have driven via the
already-authenticated Playwright session — manual work pushed onto a non-technical founder.

**If this leaks, the user's workflow is exposed via:** N/A — this is a procedural rule edit
plus a learning file; no user data, schema, auth flow, or external surface is touched.

**Brand-survival threshold:** none, reason: docs/procedural change to AGENTS.core.md + a
learning file; no code path, regulated-data surface, or runtime behavior is modified.

## The byte-budget constraint (dominant engineering fact)

`scripts/lint-agents-rule-budget.py` enforces two ceilings, both commit-blocking via lefthook
and re-run in `scripts/test-all.sh`:

1. **B_ALWAYS** = `len(AGENTS.md) + len(AGENTS.core.md)` ≤ **23000 B** (REJECT). Current:
   **22977 B** (`AGENTS.md=5792 + AGENTS.core.md=17185`). **Only 23 B of total headroom.**
2. **Per-rule cap** = each `^- ` body line under a `SECTIONS` heading ≤ **600 B**. Current
   rule line = **534 B** (66 B of per-rule headroom).

Therefore the rule rewrite **MUST be net-zero or net-negative bytes** against the current
534-B line. We cannot simply append the precondition. The funding sources inside the same line:

- **Delete the soft clause** `; re-verify a plan's "not feasible" claim at execution time` —
  this is precisely the phrasing the incident proved was a loophole; it is being *replaced*,
  not removed-and-lost. (~52 B reclaimed.)
- **Tighten the `**Why:**`** — the new learning slug is longer than the savings, so the Why
  must drop low-value tokens (e.g., compress the citation list) to stay net ≤ 0.

The Acceptance Criteria below pin the measured before/after byte counts so the work phase
knows its exact budget (per the AGENTS-rule-budget Sharp Edge).

## Proposed new rule body (MEASURED — 549 B, both gates pass)

The new body must (a) keep the `[id:]` and `[skill-enforced:]` tags verbatim, (b) keep the
operator-only definition, (c) add the probe-receipt precondition, (d) cite the new learning in
`**Why:**`, and (e) fit the budget. The body below was **measured at 549 UTF-8 bytes** (ASCII-only):
- per-rule cap: **549 ≤ 600** (pass, 51 B under)
- B_ALWAYS: 22977 − 534 + 549 = **22992 ≤ 23000** (pass, 8 B headroom)

**Final body to write to `AGENTS.core.md` line 13 (single line, exact):**

```
- Never label a step "manual" without first attempting automation [id: hr-never-label-any-step-as-manual-without] [skill-enforced: ship Phase 5.5]. Operator-only = CAPTCHA, credential ENTRY (login/2FA/payment), or admin-scoped mint. For ANY browser/portal/UI step, do NOT write "operator-only/auth-gated/no session" in any message, plan, or issue without prior Playwright MCP browser_navigate + browser_snapshot of that surface showing the gate; an unprobed auth state IS the violation. **Why:** learning 2026-06-15-probe-before-manual-label; #5079.
```

**Funding the byte budget** (vs the current 534-B line; trim *rationale & duplicated definition*,
never the directive — per learning `2026-05-29-agents-byte-budget-trim-from-rationale-not-directive`):
- Dropped the multibyte `≡` → ASCII `=` and removed `→`/curly quotes (byte == char now).
- **Replaced** the soft loophole clause `; re-verify a plan's "not feasible" claim at execution time`
  with the hard probe-receipt precondition (this is the whole point of the fix — the soft phrasing
  is what the incident exploited).
- **Dropped the OAuth-consent carve-out from this line.** It is preserved verbatim in the cited
  learning `2026-06-10-oauth-consent-screens-are-playwright-automatable-not-operator-only.md` AND
  enforced in work Phase 4 + ship Phase 5.5 — so the guidance survives; only the duplicate copy in
  the always-loaded line is removed. (Verified both survive: see Research Reconciliation.)
- Compressed the equivalents keyword list to the three highest-signal forms
  (`operator-only/auth-gated/no session`) — the LinkedIn incident used exactly "auth-gated" +
  "no session," so both are retained; the generalization is carried by the learning.
- Tightened the Why to one learning slug + one issue ref.

> **8-B headroom is intentionally thin.** If the work phase prefers net ≤ 0 (to leave B_ALWAYS at
> or below 22977), two further trims are available without weakening the directive: shorten the
> credential-ENTRY paren `(login/2FA/payment)` → `(login/2FA/pay)` (−4 B) and/or shorten the slug.
> But 549 B already passes both gates as measured; net ≤ 0 is a nicety, not a requirement.
> The work phase MUST re-measure the final line with the byte command in AC2 before committing —
> if the chosen learning filename differs from the slug above, the Why citation and the filename
> must stay in sync (AC6) and the line re-measured.

## Files to Edit

- `AGENTS.core.md` — rewrite the `hr-never-label-any-step-as-manual-without` body line in
  place (line 13) to the measured 549-B body above. Re-measure with the AC2 byte command before
  committing; line ≤ 600 B and resulting B_ALWAYS ≤ 23000. Do NOT touch the `[id:]` or the
  `[skill-enforced: ship Phase 5.5]` tag.
- `AGENTS.md` — **no edit.** The pointer index line for this rule already reads
  `[id: hr-never-label-any-step-as-manual-without] → core` (verified). No tier change.

## Files to Create

- `knowledge-base/project/learnings/workflow-patterns/2026-06-15-probe-before-manual-label.md` —
  the learning file documenting the LinkedIn-MDP session error and the probe-receipt prevention.
  The rule's `**Why:**` cites this exact slug (`2026-06-15-probe-before-manual-label`); AC6 binds
  the citation to the filename, so if the implementer changes the slug, the Why must change too
  and the rule line must be re-measured (slug length affects bytes). Place under
  `workflow-patterns/` beside the two sibling learnings of the same rule class:
  - `2026-06-10-playwright-attempt-evidence-before-operator-only.md` (the `playwright-attempt:`
    evidence gate — the **direct precedent**; this fix extends it from deferral-classification to
    "any message/plan/issue that writes the label").
  - `2026-06-10-oauth-consent-screens-are-playwright-automatable-not-operator-only.md` (where the
    OAuth-consent carve-out now dropped from the AGENTS line is preserved).
  - Also cross-reference `2026-06-12-resumability-claim-must-verify-workspace-lifecycle.md` and
    `2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md` — both establish the general
    pattern "a persisted *state* is a claim requiring a probe, not a fact" that this learning
    specializes to auth/session state. (Surfaced by deepen-plan learnings-researcher: the
    "no persisted session is itself a claim" insight is a *new specialization* of an existing
    pattern family, not a duplicate — worth documenting.)

  Required frontmatter (matching sibling convention):
  ```
  ---
  title: "No persisted session" is a claim requiring a Playwright probe, not an answer
  category: workflow-patterns
  tags: [playwright-mcp, operator-steps, automation-claims, linkedin, probe-receipt]
  issue: 5079
  date: 2026-06-15
  ---
  ```

  Required sections (sibling shape): `## Problem` (the LinkedIn-MDP incident — unprobed
  "auth-gated — no persisted session" written into a user message + 2 GitHub issues; later
  probe showed apps `229658411` + `229637496` already authenticated), `## Solution` (the
  probe-receipt precondition: a Playwright `browser_navigate` + `browser_snapshot` of the exact
  surface evidencing the gate is a hard precondition for any operator-only/auth-gated/no-session
  label, in ANY message/plan/issue/comment), `## Key Insight` (asserting an unprobed auth state
  IS the violation; "no persisted session" is a claim, not an answer), `## Session Errors`,
  `## Tags`.

## Acceptance Criteria

> AC list trimmed 10 → 6 in deepen-plan (code-simplicity-reviewer): the per-linter ACs are
> strict subsets of the `test-all.sh` gate (AC4), and an AC on the unedited `AGENTS.md` pointer
> is ceremony. The 6 below are the minimal load-bearing post-conditions for *this* diff.

### Pre-merge (PR)

- [ ] AC1 — id unchanged, present exactly once (rename would orphan ship/work/provision-hetzner
  SKILL.md refs): `grep -c '\[id: hr-never-label-any-step-as-manual-without\]' AGENTS.core.md`
  returns `1`.
- [ ] AC2 — **rule line ≤ 600 UTF-8 bytes (per-rule cap) AND net byte delta keeps B_ALWAYS ≤ 23000.**
  Measure bytes the way the linter does (NOT `awk length`, which counts chars):
  ```bash
  python3 -c "import sys; \
    line=[l for l in open('AGENTS.core.md',encoding='utf-8') if 'hr-never-label-any-step-as-manual-without' in l][0].rstrip(chr(10)); \
    b=len(line.encode('utf-8')); print('rule_bytes=%d (cap 600), delta_vs_534=%+d' % (b, b-534))"
  ```
  Expect `rule_bytes ≤ 600` and `delta_vs_534 ≤ +23` (so B_ALWAYS = 22977 + delta ≤ 23000).
  The measured target body is 549 B (delta +15 → B_ALWAYS 22992).
- [ ] AC3 — `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`
  exits 0 with **no `[REJECT]`** line (this is the canonical B_ALWAYS + per-rule gate; AC2 is the
  human-readable pre-check that funds it).
- [ ] AC4 — `bash scripts/test-all.sh` passes — specifically the suites `lint-rule-ids-live`,
  `lint-agents-rule-budget-live`, `lint-agents-rule-budget-unit`, `lint-agents-enforcement-tags`.
  **This is the "AGENTS structure/components test passes before marking ready" gate** and subsumes
  the individual id-lint + enforcement-tag + budget checks.
- [ ] AC5 — the semantic change landed: the probe-receipt precondition is present AND the soft
  loophole clause is gone:
  ```bash
  grep -E 'browser_navigate \+ browser_snapshot' AGENTS.core.md   # ≥1 hit on the rule line
  grep -c "re-verify a plan" AGENTS.core.md                       # returns 0
  ```
- [ ] AC6 — the learning file exists with all five required sections, AND the rule's `**Why:**`
  cites its slug, AND that slug resolves on disk (citation binding — globstar-safe, pinned dir):
  ```bash
  f=$(ls knowledge-base/project/learnings/workflow-patterns/2026-06-15-*.md)
  test -s "$f"
  for s in '## Problem' '## Solution' '## Key Insight' '## Session Errors' '## Tags'; do
    grep -qF "$s" "$f" || echo "MISSING SECTION: $s"; done
  slug=$(grep -oE 'learning 2026-06-15-[a-z0-9-]+' AGENTS.core.md | sed 's/^learning //')
  ls "knowledge-base/project/learnings/workflow-patterns/${slug}.md"   # must resolve
  ```

### Post-merge (operator)

- [ ] None. Pure docs/procedural change; merge IS the delivery. No infra, no migration, no
  external state.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — procedural/governance change to AGENTS.core.md plus a
learning file. No Product/UX surface (no file under `components/**`, `app/**/page.tsx`, etc.;
the change *describes* a Playwright-probe workflow but *implements* an AGENTS rule edit → NONE
per the "discusses UI but implements orchestration" carve-out). No regulated-data surface
(GDPR gate skipped). No new infrastructure (IaC gate skipped). No code-class file under
`apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts` (Observability gate skipped).

## Sharp Edges

- **B_ALWAYS is only 23 B from the hard REJECT (22977 / 23000).** The chosen 549-B body lands
  B_ALWAYS at 22992 — **8 B of headroom.** Any *additional* net-positive change to AGENTS.core.md
  in the same PR (a longer Why, an extra keyword, a multibyte char) will fail
  `lint-agents-rule-budget.py` at commit time. Measure with the AC2 byte command (NOT `awk length`
  — the linter counts UTF-8 bytes, the original AC counted chars) *before* committing. Budget is
  funded by replacing the soft re-verify clause + dropping the OAuth carve-out (preserved in its
  learning), not by spending headroom that does not exist. **The original deepen draft was 698 B
  and would have REJECTED — re-measure, do not trust the prose length.**
- The `[id:]` is immutable (`cq-rule-ids-are-immutable`). Renaming it would fail
  `lint-rule-ids.py` AND orphan **three** SKILL.md references (`ship`, `work`, `provision-hetzner`).
  Do not touch it. The `[skill-enforced: ship Phase 5.5]` tag must also stay verbatim
  (`lint-agents-enforcement-tags.py` resolves it).
- Do NOT prescribe the exact learning filename's date-slug in `tasks.md` — the plan pins
  `2026-06-15-probe-before-manual-label` for the Why-citation byte calculation, but if the
  implementer picks a different slug at write-time, the rule's Why MUST cite that slug AND the
  rule line MUST be re-measured (AC6 binds Why↔filename; slug length affects the 549-B count).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled:
  threshold `none` with a non-empty reason, since the diff touches no sensitive path.)
- The OAuth-consent carve-out currently in the rule line is load-bearing guidance preserved in
  the `2026-06-10-oauth-consent-screens-...` learning. If budget forces dropping it from the
  AGENTS line, confirm it survives in that learning AND in work/ship enforcement before cutting.

## Test Scenarios

- **Happy path:** write the measured 549-B body; `test-all.sh` AGENTS suites pass; learning
  file created; Why cites its slug; B_ALWAYS = 22992 ≤ 23000.
- **Budget regression (negative):** if the rewritten line is > 600 B (per-rule cap) OR B_ALWAYS
  rises above 23000, `lint-agents-rule-budget.py` rejects — the work phase must trim further
  (per the funding levers above).
- **Citation regression (negative):** if the Why cites a slug that does not resolve on disk,
  AC6's `ls` check fails — fix the slug or the filename so they match.
