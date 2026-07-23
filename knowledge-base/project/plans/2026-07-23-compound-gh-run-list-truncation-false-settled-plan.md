---
type: docs-only
lane: cross-domain
issue: 6796
brand_survival_threshold: none
requires_cpo_signoff: false
---

# 📚 compound: land the "gh run list truncates → false ALL SETTLED" learning

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Issue #6796 asks to land a single learning file capturing a completion-monitor
defect first observed at the end of PR #6746's ship cycle: a post-merge Monitor
loop that ran `gh run list --branch main --commit <SHA> --json ...` and counted
non-completed rows reported **ALL SETTLED** while the production deploy (`Web
Platform Release`), `CI`, `CodeQL`, and `Tenant integration` were still
`in_progress`.

Nothing errored — well-formed JSON, correct `jq`, correct arithmetic. The defect
is an unstated assumption about the data source: **`gh run list` defaults to ~20
rows**; the merge commit had 38. The first 20 (the returned page) were the fast,
already-completed ones, so the not-completed count was genuinely `0` *for the
page it read*. The query answered *"are the first 20 runs done?"* not *"are all
runs done?"*.

The learning was captured but never landed as a file because PR #6746's branch
had already merged. This is the small follow-up PR that lands it.

**This is a DOC-ONLY change.** The deliverable is exactly **one** markdown
learning file under `knowledge-base/project/learnings/`. No product code, no
tests, no source changes, no edits to `ship`/`postmerge`.

## Research Reconciliation — Premise vs. Codebase

The issue body's fix snippets and the framing note ("the ship skill's own poll
loops already carry the `--limit`/floor-guard mitigation, so the learning
documents an already-partly-mitigated class") were verified against the repo.
One premise was **refined** by verification and the learning MUST cross-reference
accurately rather than parrot the original phrasing:

| Claim (as framed) | Reality (verified) | Learning's response |
|---|---|---|
| Sibling learning `2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md` exists (cross-ref) | Confirmed present at repo root | Cite it as a sibling "clean read ≠ safe conclusion" instance |
| `ship/SKILL.md` Phase 6.5 says "'No failures' and 'the checks ran' are different claims" | Confirmed at Phase 6.5 "Verify PR Mergeability" | Cite it as the sibling articulation of "empty for two different reasons" |
| ship/postmerge poll loops "already carry the `--limit`/floor-guard mitigation" | **Imprecise.** No `KNOWN_TOTAL` / floor guard exists anywhere in `ship` or `postmerge`. The poll loops are immune because they poll **by run-ID / SHA-identity** (`gh run view <id>`, `gh run list --workflow <name> --limit 1`, `gh run list --branch main --limit 3` matched by `headSha`), **not** by counting a capped filtered list. `--limit` there is on single-run/single-workflow queries where truncation is irrelevant. | Cross-reference the robust pattern as **"poll by identity, not by counting a capped source"** — do NOT claim those loops carry a `--limit`+floor-guard mitigation |
| (discovered) ship Phase 7 Step 2 completion-**count** is safe | **Latent same-class instance.** `gh run list --branch main --commit <merge-sha> ... --jq '[.[] \| select(.status != "completed")] \| length'` has no `--limit`; its empty-result fallback distinguishes only "no runs registered yet" (total=0) from "runs exist" (total>0), NOT "genuinely all done" from "truncated page all done". A 38-run merge whose first-20 page is all-completed would report false "N/N passed". | The learning notes this as a latent instance worth an operator follow-up; fixing `ship` is **out of scope** for this doc-only PR |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a
learnings-corpus doc capture. The failure mode being *documented* (a false "release
verified" letting production stay on stale code) is real, but this PR only records
the lesson; it does not change any monitor.

**If this leaks, the user's data is exposed via:** N/A — no data surface; the file
is a public-repo engineering learning containing no secrets or user data.

**Brand-survival threshold:** none — `threshold: none, reason: doc-only learnings
capture; touches no sensitive path, no code, no data surface.`

## Implementation Phases

### Phase 1 — Author the learning file (only phase)

Create `knowledge-base/project/learnings/2026-07-23-gh-run-list-truncation-reports-false-all-settled.md`
(author picks the final date at write-time; topic + directory are fixed).

Content, adapted verbatim-where-possible from the #6796 issue body:

1. **YAML frontmatter** matching the corpus convention (see any recent root
   learning, e.g. `2026-07-19-a-wall-clock-break-...md`): `module`, `date`,
   `problem_type: logic_error`, `component`, `symptoms` (list), `root_cause:
   wrong_assumption`, `severity`, `tags` (include `gh-cli`, `pagination`,
   `completion-detection`, `false-negative`, `monitoring`), `issue: 6796`,
   `synced_to: []` (no skill was edited — honest empty).
2. **# Title** — a plain-language sentence, e.g. "gh run list truncates — a
   completion-monitor built on it reports a false ALL SETTLED".
3. **## Problem** — the broken loop (fenced bash from the issue), the ~20-row
   default vs 38 actual runs, and that nothing errored.
4. **## The tell** — the defect is in the output **shape**: exactly 20 rows. A
   count landing precisely on a CLI default is the signature; reading the loop
   for a bug finds none.
5. **## Fix** — the `--limit 60` read + `KNOWN_TOTAL` **floor guard** (fenced
   bash from the issue). State that `--limit` alone only moves the cliff; the
   floor guard converts a short read from "looks complete" into "refuse to
   answer"; establish `KNOWN_TOTAL` from one full read and make it a **floor,
   never an equality** (scheduled workflows fire on `main` independently and
   legitimately grow the count — observed 38 → 47 mid-watch).
6. **## Key insight** — a completion detector must distinguish "nothing left"
   from "nothing visible"; any paginated/filtered/capped source returns an empty
   remainder for two different reasons and the happy path is byte-identical
   between them. Ask of any "is it done yet?" check: *what does this return when
   the source under-reports?*
7. **## Cross-references** (accuracy-critical — use the Research Reconciliation
   table above):
   - The **robust pattern already in the repo** is *poll by identity, not by
     counting a capped source*: `ship`/`postmerge` completion **poll loops**
     poll by run-ID / `headSha`-match, which is why they are immune — NOT because
     they carry a `--limit`+floor-guard (they do not).
   - `ship/SKILL.md` **Phase 6.5** ("'No failures' and 'the checks ran' are
     different claims") — sibling articulation of the same class.
   - `2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md`
     — sibling "a clean read and a safe conclusion are different claims".
   - **Latent same-class instance:** `ship` Phase 7 Step 2's completion-**count**
     (`gh run list --commit <sha> ... | length`, no `--limit`) shares this shape;
     flag as worth an operator follow-up. Fixing it is out of scope here.
8. **## Sharp edge** — the class does not respect the review boundary: this was
   reproduced in a throwaway monitoring loop by the very agent that had just
   spent hours finding the same class (existence-vs-effect gates) in the PR under
   review, because monitoring code gets none of the scrutiny reviewed code gets.

Cite content anchors (Phase names, headings), not line numbers
(`cq-cite-content-anchor-not-line-number`).

## Files to Create

- `knowledge-base/project/learnings/2026-07-23-gh-run-list-truncation-reports-false-all-settled.md` — the single learning file (the entire deliverable).

## Files to Edit

- None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Exactly one new file exists under `knowledge-base/project/learnings/` and no
      other tracked file changed except the plan/tasks artifacts:
      `git diff --name-only origin/main...HEAD -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
      lists only the learning file.
- [ ] The learning file has valid YAML frontmatter with `issue: 6796` and
      `synced_to: []` — verify frontmatter parses (delimited by `---` … `---`).
- [ ] The file contains all six content sections (Problem, The tell, Fix, Key
      insight, Cross-references, Sharp edge) — `grep -c '^## '` ≥ 5.
- [ ] The **Fix** section contains both mitigations: `grep -q -- '--limit'` AND
      `grep -q 'KNOWN_TOTAL'`.
- [ ] The cross-reference to ship/postmerge does **not** assert those poll loops
      carry a floor guard; it states the robust pattern is *poll by identity*.
      (Manual read — no automated proxy; the whole point of #6796 is that a green
      grep can certify a false claim.)
- [ ] Every `knowledge-base/` path cited in the file resolves:
      `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <file> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'`
      prints nothing. (The `2026-07-20-terraform-...` sibling is confirmed present.)
- [ ] No product code, test, or `ship`/`postmerge` SKILL.md file is touched.

## Open Code-Review Overlap

None. The deliverable is a net-new documentation file; no existing tracked file is
edited, and `gh issue list --label code-review --state open --search "gh run list
truncat"` returns `[]`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — engineering learnings-corpus doc capture.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This section is filled (threshold `none` with a scope-out reason).
- **Accuracy over fidelity to the ask:** the source framing said ship/postmerge
  "already carry the `--limit`/floor-guard mitigation." Verification refined this
  (they are immune by polling *by identity*, and no floor guard exists in-repo).
  The learning must encode the verified statement, not the original phrasing —
  the irony of this very learning is that a plausible-but-unverified claim reads
  as true until measured.
- **Do not expand scope.** The verified latent instance in `ship` Phase 7 Step 2
  is a real defect (false "release verified"), but this PR is doc-only. Record it
  in the learning as a follow-up candidate; do not edit `ship`.
