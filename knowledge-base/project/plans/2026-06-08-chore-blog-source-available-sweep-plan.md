---
feature: chore-blog-source-available
issue: 5043
date: 2026-06-08
lane: single-domain
brand_survival_threshold: aggregate pattern
brainstorm: knowledge-base/project/brainstorms/2026-06-08-blog-source-available-positioning-brainstorm.md
spec: knowledge-base/project/specs/feat-chore-blog-source-available/spec.md
---

# Plan: Soleur-subject "open source" → "source-available (BSL 1.1)" in dated blog posts (#5043)

♻️ **chore / docs-content** · single-domain (marketing/legal copy) · no code-path, no infra, no new deps

## Overview

PR #5036 swept every Soleur-subject "open source" claim on **evergreen** `.njk` pages to
"source-available (BSL 1.1)" and fixed explicit Apache claims in blog bodies, but deliberately
deferred the generic Soleur-subject "open source" positioning in the **body** of the dated blog
comparison posts to a CMO call (#5043). The CMO decision (2026-06-08): **sweep Soleur-subject
"open source" → "source-available (BSL 1.1)"**, preserving the auditability/transparency claim
(true under BSL).

This plan does two things:

1. **RED/GREEN**: extend `marketing-content-drift.test.ts` Test 2c with a Soleur-subject "open
   source" ban scoped to the blog walk, mirroring Test 2b's regex shape. Update the #5043 deferral
   comments (Test 2b L160-161, Test 2c L190) to "resolved (#5043)".
2. **Sweep**: rewrite ONLY Soleur-subject "open source" / "open-source" → "source-available
   (BSL 1.1)" (compact "Source-available" where table width requires) across narrative prose,
   comparison-table rows, frontmatter, and JSON-LD in the affected blog posts. Discriminate
   per-line/per-cell: competitor & ecosystem refs (CrewAI MIT, Paperclip MIT, Spec Kit / OpenSpec,
   GitHub spec-kit) stay verbatim.

**Why this matters (brand):** comparison-table rows and JSON-LD are decision-grade / AEO surfaces;
a false Soleur-subject "open source" claim there is graded and propagated. The blog↔evergreen
inconsistency (blog says "open source", homepage says "source-available") actively erodes trust.

## Enhancement Summary

**Deepened on:** 2026-06-08
**Gates run:** 4.6 User-Brand Impact (PASS — threshold `aggregate pattern`), 4.7 Observability
(skipped — pure docs-content + content-drift test, no `apps/*/server|src|infra` or
`plugins/*/scripts/`), 4.8 PAT-shaped halt (PASS — no match), 4.9 UI-wireframe (skipped — no UI
surface).

### Key Improvements (from the deepen pass)
1. **Empirically validated the Test 2c regex** against all 11 in-scope files + a 9-line
   competitor/ecosystem KEEP oracle: **0 in-scope misses, 0 false positives.** The implementer can
   adopt the regex directly instead of tuning it blind.
2. **Caught a regex MISS via the verify-the-negative pass:** the first-draft Soleur-token-anchored
   regex missed `2026-04-23-agents-that-use-apis-not-browsers.md` entirely (its hits are
   pronoun-subject "it is open source" / sentence-lead "Open source."). Added the
   `it is open-source` + `Open source.` clauses and re-verified — now all 11 files match.
3. **Confirmed `it … open-source` is FP-safe blog-wide:** the phrase appears in exactly 3 lines,
   all Soleur-subject — zero competitor uses, so the broadened clauses add no false-positive risk.

### Research Insights

**Validated regex oracle run (reproduce at /work Phase 1):**

```text
IN-SCOPE (each ≥1 match):
  vs-anthropic-cowork:1  vs-notion:1  vs-cursor:3  vs-polsia:5  your-ai-team:1
  vs-paperclip:1  vs-devin:1  agents-apis:3  vs-tanka:1  vs-crewai:3  caas-platform:1
KEEP oracle (each 0 match): crewai L20/L74/L108, paperclip L11/L26/L84/L131/L133, speckit L39
RESULT: IN-SCOPE MISSES=0  KEEP FALSE-POSITIVES=0
```

Oracle script shape (Node, run from repo root) — adapt the `RE` to the validated `SOLEUR_OPEN_SOURCE`:
read each in-scope file, assert `lines.filter(t=>RE.test(t)).length >= 1`; read each KEEP `file:line`,
assert `RE.test(line) === false`.

**Edge case — shared-row tables are NOT regex-discriminable** (re-confirmed): the table rows
`| Open source | Yes (MIT) | Yes |` (crewai L108) and `| Open-source and local-first | Yes | Yes |`
(paperclip L84) correctly do NOT match the Soleur-subject regex (no per-line subject token). They
are swept by hand and guarded by AC1b/AC2 + manual residual eyeball, not by the test. The test's
job is the prose + JSON-LD Soleur-subject ban; the sweep's job is the table cells.

## Research Reconciliation — Spec/Brainstorm vs. Codebase

The brainstorm's "Affected files" line numbers were captured "on main"; the worktree is at HEAD
(`4f1ca296d`, PR #5036 merged) which **is** that same main, so the line numbers are current — BUT
two brainstorm claims do not survive a per-line grep and are corrected here:

| Brainstorm/Spec claim | Codebase reality (verified via `git grep -niE`) | Plan response |
|---|---|---|
| 2026-03-16: "keep Cowork's 'open source' cells" (L112, L135 framed as keep) | The Cowork file has **no Cowork open-source cells** — Cowork is the *proprietary* leftmost column. L84 `Free (open source)` and L88 `Live (open source)` are in the **Soleur** (rightmost) column; L112/L135 are Soleur-subject prose. All four are Soleur-subject → **change**. | Sweep all of L25, L84, L88, L112, L135. There is nothing to "keep" in this file. |
| Spec FR3 JSON-LD line list "vs-cursor L142, vs-polsia L157/L160, vs-crewai L163" | Confirmed present and Soleur-subject. vs-polsia also has a **second** JSON-LD hit at L160 *and* L157 (Q name + answer text). | Sweep both polsia JSON-LD hits (L157 name, L160 answer) to keep JSON-LD ↔ prose in sync. |
| Issue #5043 state | `gh issue view 5043` → **OPEN**, title "review generic 'open source' positioning in dated blog posts". Premise holds. | Proceed; PR closes #5043. |
| AC1 baseline `git grep -niE "soleur is (an )?open[- ]source" -- 'plugins/soleur/docs/blog/*.md'` | **6 hits** (vs-cursor L72/L106/L142[JSON-LD], vs-polsia L80, vs-crewai L127/L163[JSON-LD]). Non-zero before sweep, as required for a meaningful AC1. | After sweep, AC1 must return 0. |

**Premise Validation:** Checked issue #5043 (OPEN), PR #5036 (merged at HEAD), the 11 enumerated
files' actual hit locations, and table-column ownership for every shared-row "Open source" table
cell. Stale: the brainstorm's Cowork "keep cells" note (no such cells exist). Held: all other file
citations and the JSON-LD sync requirement.

## Affected Files (Files to Edit)

### Test (RED first)

- `plugins/soleur/test/marketing-content-drift.test.ts` — extend Test 2c (add Soleur-subject "open
  source" `OFFENDER` ban over the blog walk, mirroring Test 2b); update deferral comments at
  L160-161 (Test 2b) and L190 (Test 2c) from "deferred to #5043 (CMO)" → "resolved (#5043)".

### Blog sweep — verified per-line/per-cell (line numbers as of HEAD `4f1ca296d`)

Legend: **CHANGE** = Soleur-subject, rewrite to source-available. **KEEP** = competitor/ecosystem,
verbatim.

1. **`2026-03-16-soleur-vs-anthropic-cowork.md`**
   - L25 CHANGE: `**Soleur** is an open-source [Company-as-a-Service]…` → `…is a source-available (BSL 1.1) [Company-as-a-Service]…`
   - L84 CHANGE (Soleur table cell): `Free (open source). Paid tier planned.` → `Free (source-available). Paid tier planned.`
   - L88 CHANGE (Soleur table cell): `Live (open source)` → `Live (source-available)`
   - L112 CHANGE (prose bullet): `You care about open-source transparency: auditable agents…` → `…source-available transparency: auditable agents…` (keep the auditability claim)
   - L135 CHANGE (closing prose): `Open source, terminal-first, built by a solo founder…` → `Source-available, terminal-first, built by a solo founder…`
   - NOTE: L98-ish "Source availability | Proprietary | Proprietary | Source-available (BSL 1.1)…" row already correct (PR #5036) — leave.

2. **`2026-03-17-soleur-vs-notion-custom-agents.md`**
   - L24 CHANGE: `**Soleur** is an open-source [Company-as-a-Service]…` → `…is a source-available (BSL 1.1) [Company-as-a-Service]…`
   - L91 CHANGE (Soleur table cell): `Live (open source)` → `Live (source-available)`
   - L111 CHANGE (prose bullet): `open-source transparency` → `source-available transparency`
   - L129 CHANGE (closing prose): `Open source, terminal-first…` → `Source-available, terminal-first…`
   - NOTE: Pricing/Source-availability rows already swept by #5036 — leave.

3. **`2026-03-19-soleur-vs-cursor.md`**
   - L72 CHANGE: `Soleur is open-source. The platform is free.` → `Soleur is source-available (BSL 1.1). The platform is free.`
   - L106 CHANGE (prose): `Soleur is open-source and auditable: every agent prompt…` → `Soleur is source-available (BSL 1.1) and auditable: every agent prompt…`
   - L142 CHANGE (**JSON-LD**, sync with L106): same rewrite inside the `"text":` string.

4. **`2026-03-26-soleur-vs-polsia.md`**
   - L80 CHANGE: `Soleur is open-source. The platform is free.` → `Soleur is source-available (BSL 1.1). The platform is free.`
   - L122 CHANGE (Q heading prose): `Is Soleur's open-source model sustainable…` → `Is Soleur's source-available model sustainable…`
   - L124 CHANGE (answer prose): `…open-source transparency are structural advantages…` and `The open-source core means every agent…` → `source-available` in both phrasings (keep auditable/extensible claim).
   - L157 CHANGE (**JSON-LD** Question `"name"`, sync with L122): same rewrite.
   - L160 CHANGE (**JSON-LD** Answer `"text"`, sync with L124): both phrasings.

5. **`2026-03-29-your-ai-team-works-from-your-actual-codebase.md`**
   - L70 CHANGE: `…part of the Soleur open-source platform.` → `…part of the Soleur source-available (BSL 1.1) platform.`

6. **`2026-03-31-soleur-vs-paperclip.md`** — **FR2: SEPARATE the two products** (Paperclip stays open-source MIT; Soleur becomes source-available). Per-token discrimination:
   - L3 `seoTitle` CHANGE: `Soleur vs. Paperclip: Open-Source AI Company Platforms Compared` → reword to not assert Soleur is open-source while keeping search intent, e.g. `Soleur vs. Paperclip: Source-Available vs. Open-Source AI Company Platforms`.
   - L5 `description` CHANGE: `both open-source AI company platforms` → reframe to separate, e.g. `Soleur (source-available, BSL 1.1) vs. Paperclip (open-source, MIT) — two AI company platforms from opposite directions.`
   - L11 `tags: [open-source]` — **DECISION (see Decisions §):** KEEP. The tag is topical taxonomy (the post discusses open-source platforms generically incl. Paperclip), not a Soleur self-claim; AC1/AC2 do not require its removal and the Soleur-subject test regex must not match a bare frontmatter tag token.
   - L26 KEEP (Paperclip): `Paperclip is an [open-source orchestration platform…]` — verbatim.
   - L49 CHANGE (Soleur prose): `It is open-source and local-first:` → `It is source-available (BSL 1.1) and local-first:`
   - L84 table row `| Open-source and local-first | Yes | Yes |` — left col = Paperclip (Yes, accurate), right col = Soleur. **Restructure** so Soleur's cell is honest. Recommended: split into the row label staying `Open-source and local-first` with Paperclip `Yes` and Soleur `Source-available (BSL 1.1); local-first`, OR change the Soleur cell to `Source-available` and footnote. Implementer picks the table-width-fitting form; the load-bearing requirement: the Soleur (right) cell must NOT assert "open source".
   - L129 KEEP-with-care (prose): `…most complete open-source, self-hosted zero-human company stack available.` — this sentence is about the **combined Soleur+Paperclip stack**; the "open-source" there is ecosystem-category framing where Paperclip is the open-source half. **DECISION:** reword to `…most complete self-hosted zero-human company stack available.` (drop the bare category adjective rather than falsely attribute open-source to the combined stack). Non-Soleur-subject test regex must not fire here either way.
   - L131 KEEP (ecosystem Q): `What are the main open-source AI company platforms in 2026?` — category question; Paperclip qualifies. Keep the question framing.
   - L133 CHANGE-Soleur-clause-only: `…Paperclip (MIT license, 14,600+ GitHub stars, …) and Soleur (open-source, {{ stats.agents }} agents, …).` → change ONLY the Soleur parenthetical to `(source-available, BSL 1.1, …)`; keep Paperclip's clause and the sentence's `open-source, self-hosted platforms` lead-in (Paperclip is genuinely open-source). **Per-clause edit, not line-blanket.**
   - L174 KEEP (JSON-LD Q name, mirror of L131): category question — keep.
   - L177 CHANGE-Soleur-clause-only (**JSON-LD**, mirror of L133): change only `Soleur (open-source, purpose-built domain agents…)` → `Soleur (source-available, BSL 1.1…)`; keep Paperclip clause.

7. **`2026-04-21-soleur-vs-devin.md`**
   - L72 CHANGE: `Soleur: open-source, free platform.` → `Soleur: source-available (BSL 1.1), free platform.`
   - L74 CHANGE (prose): `The open-source model is lower cost for founders…` → `The source-available model is lower cost…`
   - L117 table row `| Open-source and local-first | No | Yes |` — left = Devin (No), right = Soleur (Yes). Change the Soleur (right) cell from `Yes` to `Yes (source-available)` and/or adjust the row label so it does not assert OSI-approved "open source" for Soleur. Recommended: row label `Source-available and local-first` with Devin `No` / Soleur `Yes`. Implementer's call on label vs cell; the Soleur cell must not claim "open source".

8. **`2026-04-23-agents-that-use-apis-not-browsers.md`** — NOTE: all three hits are **pronoun-subject** ("it" = Soleur's service automation), no literal "Soleur" token on the line; the validated regex catches them via the `it is open-source` + sentence-lead `Open source.` clauses.
   - L5 `description` CHANGE: `…server-side browsers. Open source. Encrypted tokens…` → `…server-side browsers. Source-available (BSL 1.1). Encrypted tokens…`
   - L14 CHANGE (prose): `Soleur's service automation shipped this week, and it is open source.` → `…and it is source-available (BSL 1.1).`
   - L67 CHANGE (prose): `It is public, it is open source, and you can read every line.` → `It is public, it is source-available, and you can read every line.` (keep "read every line" auditability claim — the true asset).

9. **`2026-05-05-soleur-vs-tanka.md`**
   - L82 CHANGE: `Soleur: open-source, free platform.` → `Soleur: source-available (BSL 1.1), free platform.`
   - L115 table row `| Open-source | No | Yes |` — left = Tanka (No), right = Soleur (Yes). Recommended: row label `Source-available` / Tanka `No` / Soleur `Yes`. Soleur cell must not claim "open source".

10. **`2026-05-07-soleur-vs-crewai.md`** — keep ALL CrewAI/MIT refs verbatim.
    - L20 KEEP (CrewAI): `CrewAI is an open-source Python framework…` — verbatim.
    - L72 heading `### Open Source Model` — section header framing both products. **DECISION:** rename to `### Licensing Model` (or `### Open Source vs. Source-Available`) so it does not assert Soleur is open-source. Either is honest; implementer picks.
    - L74 KEEP (CrewAI): `CrewAI: open-source framework (MIT license)…` — verbatim.
    - L76 CHANGE (Soleur): `Soleur: open-source platform (Claude Code plugin).` → `Soleur: source-available (BSL 1.1) platform (Claude Code plugin).`
    - L108 table row `| Open source | Yes (MIT) | Yes |` — left = CrewAI (`Yes (MIT)`, keep), right = Soleur (`Yes` → change). Recommended: keep row label `Open source` → consider relabel `Licensing` with CrewAI `Open source (MIT)` / Soleur `Source-available (BSL 1.1)`. The CrewAI cell's MIT must remain; the Soleur cell must not claim "open source".
    - L127 CHANGE (prose): `Soleur is open-source. Agent and skill definitions are Markdown files…` → `Soleur is source-available (BSL 1.1). Agent and skill definitions are Markdown files…` (keep inspectable/editable claim).
    - L163 CHANGE (**JSON-LD**, sync with L127): same rewrite inside `"text":`.

11. **`2026-05-12-company-as-a-service-platform.md`**
    - L66 CHANGE: `Soleur is the open-source CaaS platform.` → `Soleur is the source-available (BSL 1.1) CaaS platform.`

### Explicitly OUT of scope (KEEP verbatim — AC2 corpus)

- `why-most-agentic-tools-plateau.md` L39 — `[Spec Kit]…, open-sourced by GitHub…`, OpenSpec, Kiro,
  Tessl. Ecosystem refs, NOT Soleur-subject. Not in the 11-file list. The Soleur-subject test regex
  MUST NOT match "open-sourced by GitHub".
- Every CrewAI "open-source … (MIT)" and Paperclip "open-source … MIT license" mention.

## Test Design — Test 2c Soleur-subject "open source" ban

Mirror Test 2b's `OFFENDER` shape but scope to the **blog walk** (`walkMarkdown(join(DOCS_ROOT,
"blog"))`, the existing Test 2c target). Keep the existing Apache floor; AND-in the Soleur-subject
clause. The regex must fire on Soleur-subject phrasings and NOT on competitor/ecosystem ones.

**Phrasings the regex MUST match (post-grep inventory of Soleur-subject forms):**
`Soleur is open-source`, `Soleur is an open-source`, `Soleur: open-source`,
`Soleur('s)? open-source <noun>` (model / core / platform / transparency / CaaS),
`is open-source and (auditable|local-first)`, `open-source transparency`, `open-source CaaS`,
`open-source platform` (Soleur context), `Open source, terminal-first`.

**Phrasings the regex MUST NOT match (false-positive guard — verified competitor/ecosystem lines):**
`CrewAI is an open-source Python framework`, `CrewAI: open-source framework (MIT license)`,
`Paperclip is an open-source orchestration platform`, `open-sourced by GitHub` (Spec Kit),
`Yes (MIT)` table cell, the bare `- open-source` frontmatter tag, the category questions
`main open-source AI company platforms`.

**OFFENDER extension — EMPIRICALLY VALIDATED at deepen-plan time** (RED against current files,
GREEN after sweep). This exact regex was run against all 11 in-scope files (≥1 Soleur-subject match
each) AND the 9-line KEEP oracle (CrewAI L20/L74/L108, Paperclip L11/L26/L84/L131/L133, Spec Kit
L39) with **0 misses and 0 false positives** — see Research Insights below for the run output:

```ts
// Soleur-subject "open source" — resolved per CMO call (#5043). Source is BSL 1.1
// (source-available, not OSI-approved); a Soleur-subject "open source" claim is a
// misrepresentation. Competitor/ecosystem "open source" (CrewAI MIT, Paperclip MIT,
// Spec Kit "open-sourced by GitHub") stays verbatim and must NOT match.
const SOLEUR_OPEN_SOURCE =
  /Soleur(?:'s)?\s+(?:is\s+(?:an?\s+|the\s+)?)?(?:source-available\s+)?open[- ]source|Soleur:\s*open[- ]source|open[- ]source\s+(?:CaaS|transparency)|is\s+open[- ]source\s+and\s+(?:auditable|local-first)|\bit\s+is\s+(?:public,\s+it\s+is\s+)?open[- ]source\b|the\s+Soleur\s+open[- ]source|^Open source,\s|(?:^|\.\s+|browsers\.\s+)Open source\.\s/i;
```

**WHY the `it is open-source` + `Open source.` clauses are load-bearing (deepen-plan catch):** the
first-draft candidate (Soleur-token-anchored only) **missed `2026-04-23-agents-that-use-apis-not-
browsers.md` entirely** — its three Soleur-subject hits are pronoun-subject (`it is open source`,
`it is public, it is open source`) and a sentence-lead frontmatter form (`…browsers. Open source.
Encrypted tokens…`), none of which carry a literal "Soleur" token on the line. Verified across the
whole blog corpus that `it ('s/is/was) … open-source` appears in exactly 3 lines, ALL Soleur-
subject (paperclip L49, file-8 L14/L67) — zero competitor uses — so these clauses add no FP risk.

**Verification of the regex BEFORE writing the sweep (Sharp-edge guard):** the oracle script is
already written (`/tmp/regex_test2.mjs` shape, reproduced in Research Insights). Re-run it at /work
Phase 1 against (a) all 11 in-scope files — must report ≥1 hit each; (b) the KEEP oracle —
must report **zero**. The inventory above is the falsifiable oracle; do NOT freeze the regex from
memory. If the sweep later changes the prose forms, re-run before relying on GREEN.

**Deferral-comment updates:**
- Test 2b L160-161: `Dated blog-body generic positioning is deferred to #5043 (CMO) and is not
  covered by this .njk walk …` → rephrase to past tense: blog-body Soleur-subject "open source" is
  now **resolved (#5043)** and enforced by Test 2c.
- Test 2c L190: `Generic blog-body "open source" positioning is deferred to #5043 (CMO); explicit
  Apache claims are not …` → `Soleur-subject blog-body "open source" positioning is resolved
  (#5043) and banned below; explicit Apache claims (#5038) remain banned. Competitor/ecosystem
  "open source" (CrewAI MIT, Paperclip MIT, Spec Kit) is NOT matched.`

## Implementation Phases

### Phase 0 — Preconditions
- Confirm worktree CWD + branch `feat-chore-blog-source-available`.
- `bun --version` (have 1.3.11). Test command: `bun test plugins/soleur/test/marketing-content-drift.test.ts`.
- Re-grep AC1 baseline: `git grep -niE "soleur is (an )?open[- ]source" -- 'plugins/soleur/docs/blog/*.md'` → expect 6 hits (RED baseline for AC1).

### Phase 1 — RED (test first)
- Add the Soleur-subject `OFFENDER`/`SOLEUR_OPEN_SOURCE` clause to Test 2c over the blog walk.
- Verify the regex against the match / no-match oracle sets (script described above).
- Run the suite → Test 2c **fails** (current files contain Soleur-subject "open source"). Capture the offender list; it should enumerate the in-scope lines and **not** the KEEP lines. If a KEEP line appears, the regex is too broad — fix before sweeping.

### Phase 2 — GREEN (sweep the 11 files)
- Apply the per-file/per-cell edits in the Affected Files table. Read each file before editing (`hr-always-read-a-file-before-editing-it`).
- For each JSON-LD edit, edit the mirrored prose in the same pass and re-grep to confirm the `"text"`/`"name"` strings match the visible prose (FR3).
- For shared-row tables (crewai L108, paperclip L84, devin L117, tanka L115), edit ONLY the Soleur cell / row label; leave competitor cells (`Yes (MIT)`, `No`) untouched.
- Update the Test 2b L160-161 + Test 2c L190 deferral comments to "resolved (#5043)".

### Phase 3 — Verify (AC gate)
- `bun test plugins/soleur/test/marketing-content-drift.test.ts` → all green (Test 2c passes; Tests 3-5 need the Eleventy build, which `beforeAll` runs).
- AC1: `git grep -niE "soleur is (an )?open[- ]source" plugins/soleur/docs/blog/` → **0 hits**.
- AC2: `git grep -niE "crewai.*(open[- ]source|MIT)|paperclip.*(open[- ]source|MIT)|open-sourced by GitHub" plugins/soleur/docs/blog/` → unchanged from baseline (8 CrewAI + 8 Paperclip + 1 Spec Kit; competitor refs intact).
- Build: `npm run docs:build` exits 0 (no frontmatter/JSON-LD breakage). Spot-grep `_site/` for the swept JSON-LD to confirm it rendered.
- Sanity: `git grep -niE "open[- ]source" plugins/soleur/docs/blog/` should now return only KEEP (competitor/ecosystem) lines — eyeball the residual list to confirm zero Soleur-subject survivors the AC1 grep didn't catch (e.g., table cells with no "Soleur" token).

## User-Brand Impact

**If this lands broken, the user experiences:** a comparison-table cell or JSON-LD answer that now
makes a false statement about a *competitor* (e.g., a blanket find-replace that turned "CrewAI:
open-source framework (MIT)" into "source-available"), undermining the post's credibility and
exposing Soleur to a "you misrepresented our license" complaint from CrewAI/Paperclip communities.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — static marketing copy, no
user data, no runtime surface.

**Brand-survival threshold:** aggregate pattern. (No single visitor suffers a per-incident breach;
the risk is an aggregate accuracy/consistency erosion across decision-grade surfaces. Not
`single-user incident` → no CPO plan-time sign-off gate; this is a copy-accuracy chore, already
CMO-decided in the brainstorm.)

## Domain Review

**Domains relevant:** Marketing, Legal (carried forward from brainstorm `## Domain Assessments`).

### Marketing
**Status:** reviewed (brainstorm carry-forward).
**Assessment:** Honest "source-available" preserves the real positioning asset
(auditability/transparency), true under BSL; the label "open source" was never the asset. Fixing
structured surfaces (tables, JSON-LD) matters most for AEO and buying decisions and resolves the
blog↔evergreen inconsistency that erodes trust.

### Legal
**Status:** reviewed (brainstorm carry-forward).
**Assessment:** BSL 1.1 is not OSI-approved; a Soleur-subject "open source" claim is a
misrepresentation (same basis as #5038's evergreen sweep). Low individual reliance (no license
grant a visitor forks against — those were the Apache claims fixed in #5036), but comparison-table
feature claims are factual claims and should be corrected for accuracy and internal consistency.

### Product/UX Gate
Not applicable — no UI surface. The Files to Edit list contains zero paths under `components/**`,
`app/**/page.tsx`, `*.njk`, or any UI-surface glob; all edits are blog `*.md` content and one
`*.test.ts`. Mechanical UI-surface override does not fire. Tier: NONE.

## Open Code-Review Overlap

One open `code-review`-labeled issue touches the test file:
- **#3531** `[flake] marketing-content-drift.test.ts beforeAll docs:build exceeds 5s hook timeout`
  — **Acknowledge.** Different concern (flaky `beforeAll` build timeout); the test already uses a
  `30_000` ms timeout on `beforeAll` (L80), which addresses the named flake. This plan does not
  touch the `beforeAll` block. The scope-out remains open for the maintainer to close/verify
  separately; folding it in would expand scope beyond the #5043 sweep.

No open code-review issue references `plugins/soleur/docs/blog`.

## Acceptance Criteria

### Pre-merge (PR)
- [x] **AC1:** `git grep -niE "soleur is (an )?open[- ]source" plugins/soleur/docs/blog/` returns **zero** hits.
- [x] **AC1b (extended Soleur-subject sweep):** `git grep -niE "open[- ]source" plugins/soleur/docs/blog/` residual list contains ONLY competitor/ecosystem lines (CrewAI MIT, Paperclip MIT, Spec Kit "open-sourced by GitHub", and the kept frontmatter `open-source` tag) — no Soleur-subject survivor (manually verified against the KEEP set).
- [x] **AC2:** Competitor refs intact — `git grep -niE "open[- ]source"` still returns: CrewAI `open-source Python framework` + `open-source framework (MIT license)`, Paperclip `open-source orchestration platform` + `(MIT license…)`, Spec Kit `open-sourced by GitHub`. Counts unchanged from baseline (CrewAI 8, Paperclip 8, Spec Kit 1).
- [x] **AC3:** `bun test plugins/soleur/test/marketing-content-drift.test.ts` passes; Test 2c contains the new Soleur-subject assertion; the regex was verified RED-before / GREEN-after AND verified to NOT match the KEEP set (`why-most-agentic-tools-plateau.md`, CrewAI/Paperclip MIT lines).
- [x] **AC3b:** Deferral comments updated — `grep -n "deferred to #5043\|resolved (#5043)" plugins/soleur/test/marketing-content-drift.test.ts` shows the L160-161 and L190 comments now say "resolved (#5043)" and zero "deferred to #5043" remain.
- [x] **AC4:** `npm run docs:build` exits 0; swept JSON-LD blocks (`vs-cursor`, `vs-polsia`, `vs-crewai`, `vs-paperclip`) render in `_site/` with "source-available" matching their visible prose (FR3 sync).
- [x] **AC5 (FR2 separation):** In `2026-03-31-soleur-vs-paperclip.md`, Paperclip is described as open-source (MIT) and Soleur as source-available (BSL 1.1) — the two are not lumped as "both open-source"; `git grep -ni "both open-source" 2026-03-31-soleur-vs-paperclip.md` returns 0.

### Post-merge (operator)
- None. PR merge ships the docs; the `web-platform-release` container restart and Eleventy build
  are CI-driven. Issue #5043 closes via `Closes #5043` in the PR body.

## Test Scenarios

| Scenario | Expectation |
|---|---|
| Test 2c regex run against current 11 files (pre-sweep) | ≥1 offender per file's Soleur-subject lines (RED) |
| Test 2c regex run against `why-most-agentic-tools-plateau.md` | 0 offenders (ecosystem ref not matched) |
| Test 2c regex run against CrewAI L74 / Paperclip L26 KEEP lines | 0 offenders (competitor refs not matched) |
| Test 2c after sweep | 0 offenders (GREEN) |
| `npm run docs:build` after sweep | exit 0; JSON-LD parses |
| AC1 grep after sweep | 0 |

## Risks & Sharp Edges

- **Regex over- or under-matching is the dominant risk.** The Soleur-subject ban must fire on
  Soleur lines and stay silent on CrewAI/Paperclip/Spec Kit lines that legitimately say "open
  source". Mitigation: the match/no-match oracle sets above; verify the regex against BOTH before
  writing the sweep (Phase 1). A passing suite that matched a KEEP line is a false GREEN — the
  offender list must be eyeballed in RED.
- **Shared-row tables have no "Soleur" token on the line.** `| Open source | Yes (MIT) | Yes |`
  (crewai), `| Open-source and local-first | Yes | Yes |` (paperclip), `| Open-source | No | Yes |`
  (tanka/devin) — the subject is implied by column position, so the test regex cannot reliably
  discriminate these. They are enforced by the **sweep + AC1b/AC2 + manual residual eyeball**, NOT
  the regex. Do not rely on the test to catch a missed table cell.
- **Paperclip blanket-replace would create a FALSE competitor claim.** L26/L131/L133/L174 and the
  L84 left cell are Paperclip-subject (genuinely open-source MIT). Edit ONLY the Soleur clause/cell
  (per-token, not per-line). A line-blanket `s/open-source/source-available/` on L133/L177 would
  mislabel Paperclip and fail AC2.
- **JSON-LD ↔ prose drift.** Each JSON-LD `"text"`/`"name"` is a verbatim mirror of nearby prose.
  Edit both in the same pass and re-grep; a swept prose with stale JSON-LD contradicts the visible
  copy on an AEO surface (FR3).
- **`tags: [open-source]` on paperclip — KEEP (decided).** It is topical taxonomy, not a
  Soleur self-claim. The test regex must not match a bare frontmatter tag token; if a candidate
  regex would, anchor it to require a `Soleur`/`is`/`:` neighbor.
- **`### Open Source Model` heading (crewai L72) and `### Open Source vs. …` framing.** The heading
  frames both products; rename to a license-neutral form (`### Licensing Model`) so it does not
  assert Soleur is open-source. Either neutral form is honest.
- **Compact vs full source-available form.** Prose/JSON-LD use full `source-available (BSL 1.1)`;
  narrow table cells use compact `Source-available` / `Source-available (BSL 1.1)` as width allows
  (both honest, per spec G1 + brainstorm Open Question).
- **A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase
  4.6** — it is filled above (threshold: aggregate pattern).

## Out of Scope (Non-Goals)

- NG1: Competitor/ecosystem "open source" refs (CrewAI MIT, Paperclip MIT, Spec Kit / OpenSpec /
  GitHub spec-kit) — stay verbatim.
- NG2: Evergreen `.njk` / `pages/` — already handled by #5036.
- NG3: No license change, no LICENSE edits, no new positioning beyond the
  open-source→source-available label correction.
- NG4: No changes to `why-most-agentic-tools-plateau.md` (only ecosystem refs).

## Deferral Tracking

No items deferred to a later phase. #5043 is fully resolved by this PR (the deferral being resolved
IS this work). The single Acknowledged code-review overlap (#3531) is a pre-existing unrelated
flake tracked by its own open issue.
