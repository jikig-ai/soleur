---
title: "compliance: CLO attestation for the Art. 33(5) breach register was not obtained (AC14 unmet)"
date: 2026-09-04
slug: compliance-clo-attestation-art-33-5-register
branch: feat-one-shot-7791-clo-attestation-art-33-5-register
issue: 7791
closes: 7791
type: compliance
domain: legal
priority: p2-medium
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> No `knowledge-base/project/specs/<branch>/spec.md` exists for this branch, so `lane:` could not be
> carried forward and defaults to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-04
**Halt gates:** 4.6 User-Brand Impact PASS · 4.7 Observability PASS (5/5 fields, verb `bash`, no SSH)
· 4.9 UI-wireframe SKIP (no UI surface) · 4.10 Encryption Posture SKIP (no store or new connection)
· 4.11 Guard Contract PASS (`lint-guard-contract.py` green; Assembly is structural — it names the
run-time producer and the two waiver copies, not today's six members)

### Verification performed at deepen time

| Check | Result |
|---|---|
| Cited AGENTS rule ids active | 3/3 active (`cq-cite-content-anchor-not-line-number`, `wg-block-pr-ready-on-undeferred-operator-steps`, `wg-ui-feature-requires-pen-wireframe`); none in `scripts/retired-rule-ids.txt` |
| Cited commit attribution | `5d8a12736` resolves, **is an ancestor of `origin/main`**, is PR #7782, and its diff adds 3 lines citing `sentry-migration-audit-2026-05-15` to the register — the B1-remediation claim holds |
| Cited issue/PR states | 7/7 resolve as asserted — #7717 CLOSED, #7782 MERGED, #7787/#7786/#7791 OPEN, #7347/#7349 CLOSED |
| Grep-AC self-match sweep | **One hazard found and fixed.** AC10's unscoped `grep -rl` matched this plan and the #7717 `session-state.md`, both of which quote the 529 request IDs — it would have read as coverage that does not exist. Now scoped with `--exclude-dir=specs --exclude='*-plan.md'` and re-measured |
| Guard arithmetic | Final state simulated in a sandbox: `produced=10 waived=6 waiver-parity=ok`, `(c) all 10 … indexed or waived` green |

### Key improvements from the review rounds

1. **The ordering was circular and would have redded CI.** The waiver cannot precede the file, the
   deletion cannot precede the waiver removal, and the guard is green only after all three. Now a
   two-pass CLO interaction with a stated atomic-commit requirement.
2. **`produced=11` was unreachable in any passing state** — corrected to `produced=10` at six sites
   after simulating the swap rather than reasoning about it.
3. **Three of the issue's own premises were inverted**, one of which ("apply Ruling 1 as given")
   would have reopened a blocking finding.
4. **A false claim was inherited from a signed document**: R-e asserted four stale `102` sites; only
   three are stale. The correctness pass caught it by running the greps.

### New considerations discovered

- The register **defers to #7791 by name** in places the issue never mentions, and carries a live
  admission of its own incompleteness that its contents falsify — the highest-severity item here,
  and absent from the issue's four scope items.
- The counsel review's own frontmatter is stale `BLOCKED` over a tree meeting all three of its
  self-declared re-issue conditions.
- Ship Phase 5.5 will write a second audit into the same directory and re-trip the same guard check.

## Overview

The Art. 33(5) breach register landed without its CLO attestation. The gap is procedural, not
substantive: the attestation was attempted and the invocation terminated on repeated server-side
overload responses, and the gap was recorded rather than filled by a hand-written record carrying a
signature the writer does not hold. This plan produces the missing attestation under CLO authority,
carries the two prior binding rulings forward at their final state, gives a sibling determination
its own attestation pass, and retires the superseded implementation record together with its lint
waiver — swapping in a waiver for the attestation itself, without which the register guard fails.

Research inverted three of the issue's own premises: one binding ruling's arithmetic was superseded
the same day it was given, the cell this plan was asked to ratify has since been corrected twice
more, and the "internal divergence" it was asked to resolve was formally withdrawn before this issue
was written. The plan is built on the measured state, not the issue's description of it.

**Domain review then enlarged the scope, and the enlargement is the point.** The CLO's verdict is
**DISCHARGED against a corrected tree — BLOCKED if the corrections do not land in this PR**, because
the register carries five statements its own contents falsify. The most serious is a live admission
that *"this register is incomplete against its own stated predicate"* — untrue since the remediation
landed in the same commit as the annotation, and an admission against interest in the document an
Art. 58(1)(a) reader is handed. Two further items surfaced that the issue never mentions: the
counsel review's own frontmatter still reads `BLOCKED` over a tree meeting all three of its
self-declared re-issue conditions, and the 2026-08-06 determination has never received a per-artifact
verdict from any CLO instrument. Closing #7791 honestly means closing those too.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the task cites was probed. Four premises are **stale or inverted**, and three of
those four would cause a regression if implemented "as given".

| # | Premise as stated | Measured state | Disposition |
|---|---|---|---|
| P1 | Issue #7791 open; AC14 unmet | `gh issue view 7791` → OPEN, labels `compliance/critical`, `domain/legal`, `priority/p2-medium` | HOLDS |
| P2 | Attestation path absent | `test -f …2026-09-03-clo-attestation-7717-art-33-5-register.md` → ABSENT | HOLDS |
| P3 | Implementation record present | PRESENT, 14274 bytes | HOLDS |
| P4 | Register `status: draft-requires-counsel-review`, `controller:` set | Both confirmed in frontmatter | HOLDS |
| P5 | `NOT_TRANSCRIBED` holds the implementation-record waiver | Confirmed; array has **6** entries, not 1 | HOLDS |
| P6 | **Binding ruling (a): the set is "4 indexed / 3 waived, not 7" — apply as given** | **SUPERSEDED SAME-DAY.** The register now carries **5 indexed rows / 6 waived**, measured. `sentry-migration-audit-2026-05-15.md` moved waived → indexed under counsel-review finding B1 | **INVERTED — do not apply as given** |
| P7 | Scope 2: "the cell now reads `Partially`" | The 2026-05-16 cell contains **both** `Partially` **and** `No`, and correction **C2** ruled the headline is **No** | **STALE** |
| P8 | Scope 2: "names the T3 granular-causal residual" | Correction **C5**: T3 was **RESOLVED 2026-05-21 and promoted to T4** (`t3_resolved_at: 2026-05-21T07:00:00Z`) | **STALE** |
| P9 | Scope 3: 2026-08-06 carries "a performed CLO internal sign-off" | Correction **C4** **withdrew** this. The file has **zero** occurrences of `signed off`/`SIGNED-OFF`/`attested` and no `signed_off_at`/`signed_off_by`. Its text *allocates* authority ("the CLO agent **performs**"), it does not record an act | **INVERTED — there is no divergence to resolve** |
| P10 | Waiver set exists twice | Confirmed: `NOT_TRANSCRIBED` array + register `§Excluded records` table, and lint check (d) asserts equality | HOLDS |

**P6 is the dangerous one.** Ruling 1 ("4 indexed / 3 waived") was superseded the same day by the
CLO's own counsel review (B1), which held that **inclusion-predicate limb 2 is substantive, not
citational** — a file does not become a determination by quoting the article number, nor stop being
one by omitting it. Applying Ruling 1 verbatim would **un-index `sentry-migration-audit-2026-05-15.md`
and reopen the blocking finding**. The rulings bind as *reasoning*, at their final state — not as
the arithmetic each first carried.

### Measured baseline (commands run against the untouched tree)

- `bash scripts/lint-legal-registers.sh` → **exit 0**, `7 assertion(s), 0 failed
  (registers=4 rows=5 produced=10 waived=6 waiver-parity=ok)`.
- Index table data rows: **5** — `2026-05-15`, `2026-05-16`, `2026-06-29`, `2026-08-06`, `2026-08-17`.
- `sentry-migration-audit-2026-05-15.md` in `NOT_TRANSCRIBED`: **0 hits** → it is indexed, not waived.
  B1's remediation **has landed**. (A research agent reported the opposite by reading the register's
  own stale supersession prose; the measurement governs — learning §38, "an agent's number is a
  claim, not a measurement".)

### The load-bearing discovery the brief does not contain

**Adding the attestation file to `audits/` fails the lint unless it is *also* waived.** Measured by
planting a probe file carrying `Art. 33(5)` and `Art. 4(12)` and running the guard:

```
::error::(c) determination-shaped file is neither indexed nor waived:
  knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md
lint-legal-registers: 7 assertion(s), 1 failed (… produced=11 waived=6 …)   EXIT_CODE=1
# NOTE: produced=11 is the PROBE state (attestation added, record not yet deleted).
# The FINAL state is produced=10 -- the swap conserves cardinality. Measured below.
```

The guard's producer is `find audits/ -name '*.md' | xargs grep -lE
'4[[:space:]]*\(12\)|33[[:space:]]*\(5\)|Art\.?[[:space:]]*33|Article[[:space:]]+33|…'`. Any
attestation of an Art. 33(5) register necessarily matches it. So the waiver arithmetic is a
**swap, not a subtraction**: remove the implementation-record waiver, add an attestation waiver,
net **6 → 6** with different membership — in **both** copies, in the **same commit**.

### Guard mechanics — `scripts/lint-legal-registers.sh`

Four lettered checks (header says three; (d) was added later):

- **(a)** unresolved-marker scan over the 4 register files, inline-code spans stripped first.
- **(b)** every canonical-source pointer in `§Index of determinations` resolves on disk, is tracked,
  is not a symlink, and the pinned out-of-producer-scope post-mortem row is present.
- **(c)** every determination-shaped file under `audits/**` is indexed **or** waived, and the two
  sets are **disjoint**. Fails closed on a zero-file producer result.
- **(d)** `NOT_TRANSCRIBED` path-halves `sort -u` **string-equal** the `§Excluded records` table's
  File column (parsed by `awk`, block-scoped to the heading, header/separator rows skipped,
  backticks trimmed, `^knowledge-base/` filter). Fails closed if the register parse yields zero rows.

Invocation: `scripts/test-all.sh` runs both `lint-legal-registers.test.sh` (unit, blocking) and
`lint-legal-registers.sh --advisory` (live). `test-all.sh scripts` runs in ci.yml job `test-scripts`,
which feeds the synthetic aggregator job `test` — a required check per `scripts/required-checks.txt`.
`--advisory` downgrades findings to exit 0 but does **not** downgrade a fail-closed `die2` (exit 2).
Promotion to blocking is tracked at **#7787**.

### Inbound references to the file being deleted (all 9 sites)

`grep -rn '2026-09-03-implementation-record-7717' --exclude-dir=.git`:

| # | Site | Treatment |
|---|---|---|
| 1 | `scripts/lint-legal-registers.sh` — `NOT_TRANSCRIBED` entry | **Remove** |
| 2 | `knowledge-base/legal/breach-register.md` — `§Excluded records` row | **Remove** |
| 3 | `…/2026-09-counsel-review-7717.md` — `related:` frontmatter | **Leave it** (CLO F7). Repointing would make a dated audit's related-set describe a corpus it never reviewed. No lint covers audit `related:` pointers — check (b) walks only the register's index column |
| 4 | `…/2026-09-counsel-review-7717.md` — prose reference | Historical (signed record — append-only) |
| 5 | `…/2026-09-counsel-review-7717.md` — verdict-table row A4 (**APPROVED**) | Historical (signed verdict — must not be edited) |
| 6 | `…/learnings/2026-09-03-four-ways-i-destroyed-evidence….md` | Historical |
| 7 | `…/specs/feat-one-shot-7716-7717-7718-supabase-followups/tasks.md:47` | Historical migration artifact |
| 8 | `…/specs/feat-one-shot-7716-7717-7718-supabase-followups/session-state.md:187` | Historical |
| 9 | `knowledge-base/INDEX.md:461` | **Replace** with the attestation entry |

Sites 4 and 5 sit inside a **counsel-review audit that carries a signed per-artifact verdict**.
Editing them is amending a signed instrument. They stay, and the attestation records that the
artifact they name was superseded — that is what an append-only corpus does with a retired record.

### Content unique to the implementation record (lost on deletion unless carried forward)

1. The **three API 529 request IDs** and the reasoning that an attestation is an act of authority.
2. The full **AC1–AC13 implementation-verification table** (engineering verification, not legal).
3. The **narrative** of the Sentry-cell correction: drafted from a pre-Phase-9 L150 statement,
   corrected against Sentry's 2026-05-19 written confirmation, and expressly **CLO-unratified**.
4. `## Disposition` — "**Implementation: VERIFIED.** AC1–AC13 all pass against their literal commands."

The two binding rulings and the corrected cell text already live in the register. Items 1–4 do not.
**Deletion is safe only if the attestation is a content-superset of these four.** The record's own
frontmatter pre-authorises its retirement: `re_evaluation_triggers: ["On CLO attestation being
obtained — this file is then superseded by it and should be deleted, not annotated."]` — which
resolves the tension with the append-only rule: retirement here is *pre-declared*, not a silent edit.

### Precedent attestation shape

`knowledge-base/legal/audits/2026-08-09-clo-attestation-7347-operator-assisted-scope.md` is the
structural template: `type: clo-attestation`, `attestation-authority: clo`,
`status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`, `disposition: DISCHARGED`,
`brand_survival_threshold`, `attested_commit_range`, `rulings_of_record`, `re_evaluation_triggers`.
Body: DRAFT disclaimer → **Authority.**/**Method.** preamble → findings-at-attestation →
`## Per-artifact verdict` table (`| Artifact | Verdict | Basis |`) → constraint compliance →
explicit carve-outs → `## Disposition` with a bolded standalone verdict word. It carries **no**
`signed_off_by:` field; the sibling `2026-08-17-clo-ruling-…` does. The CLO chooses.

### Prior CLO record this attestation must reckon with

`knowledge-base/legal/audits/2026-09-counsel-review-7717.md` — `status: BLOCKED`, `signed_off_at: null`,
`blocking_findings: [B1]`, `required_before_merge: [R1]`, five corrections C1–C5 appended.
**Both are closed, and both were re-measured rather than assumed.** **B1** — remediated
(measured above). **R1** — `knowledge-base/legal/compliance-posture.md:96` reads
`NOT EXECUTED — no Art. 28(3) instrument recorded` under a `[2026-09-03 CORRECTION (#7717)]` marker,
and `article-30-register.md:446` carries the matching retraction; both present on `origin/main`.

> **[Reversed 2026-09-04 by CLO domain review, finding F5.]** An earlier draft of this plan recorded
> R1 as open and directed the attestation to carve it out. That was wrong, and the CLO named the
> defect class: carving out a **closed** finding "asserts a compliance gap that does not exist… in a
> regulator-facing instrument a false negative is the same defect class as a false positive." The
> attestation records R1 as **DISCHARGED, with the measurement**.

What *is* open is the counsel review's own frontmatter — it still reads `BLOCKED` /
`signed_off_at: null` over a tree that satisfies all three of its self-declared re-issue conditions.
Handled at Phase 3.6.

### Institutional learnings that bind

| Learning | Mechanic applied here |
|---|---|
| `2026-09-03-four-ways-i-destroyed-evidence-in-the-pr-that-exists-to-preserve-it.md` §1 | Never write `signed_off_by: CLO agent` by hand. If the agent is unreachable, record the absence under a *different* filename with `attested_by: "NOBODY"` |
| same, §40 | On HTTP 529: **resume, not respawn**. No backoff convention exists — "capacity is upstream". Record degraded coverage in the trailer |
| same, §2 | A dated record is append-only; an in-place "correction" is destruction. Supersede with `> **Superseded YYYY-MM-DD (#N):**` quoting prior text |
| same, §3 | A correction that reaches only the canonical copy is still a false record — grep the claim's **subject** corpus-wide, read every hit |
| same, §4 | GFM discards table cells past the header count, **inside backticks too**. Assert `cells == header_cells` for every row added or edited. The register's index table header is **9** columns; `§Excluded records` is **2** |
| `workflow-patterns/2026-08-09-legal-decisions-route-to-clo-not-operator.md` | Hand the CLO the findings, the governing records **and** the binding constraints, and require **drafted replacement wording**, not a bare verdict. Prompt it to **not** use AskUserQuestion — domain leaders default to orchestrator mode and hang a headless run |
| same | "A negative predicate does not quantify over obligations" — build the verification from the ruling's **obligation list** (one grep per required item), never from a list of things that must stay unchanged |
| `best-practices/2026-05-12-task-subagent-prompt-text-only.md` | A Task subagent sees **prompt text only**. Every disqualifying fact must be **pasted**, not referenced, or the ruling is made on an incomplete record by construction |
| `workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md` | The CLO agent is the v1 attestation authority; sign-off never routes to the non-lawyer operator |

### Conventions

- `plugins/soleur/agents/legal/clo.md` Sharp Edges: the CLO "performs the review and returns a
  per-artifact verdict + a DISCHARGED/BLOCKED disposition, **writing the audit to
  `knowledge-base/legal/audits/`**". The agent authors the file itself — the orchestrator must not.
- `model: inherit` in the CLO frontmatter. A retry must **not** silently downgrade the tier; the
  ruling's quality is the deliverable (ADR-053 never-downgrade judgment paths).
- ADR-200 governs the register and is unchanged by this plan.

### Property List (Phase 0.6b)

| # | Property (observable outcome) |
|---|---|
| PR-1 | An attestation exists at the named path carrying per-artifact verdicts and a DISCHARGED/BLOCKED disposition, authored by the CLO agent under its own authority |
| PR-2 | The Sentry-row correction made without sign-off is ratified or overruled on the record, against the cell's **current** text |
| PR-3 | The 2026-08-06 determination has an attestation pass on the record, reckoning with C4's withdrawal |
| PR-4 | Exactly one record of the #7717 implementation event survives in the corpus |
| PR-5 | `bash scripts/lint-legal-registers.sh` exits 0 |
| PR-6 | Nothing unique to the retired record is lost |
| PR-7 | The register's `status:` field is byte-identical to `origin/main` |
| PR-8 | No CLO instrument in the corpus contradicts another about the same artifact set *(added at plan review — see §PR-8; the list was written before domain review and could not contain what domain review found)* |

### Cut List (Phase 0.6b)

| Mechanism considered | Property | Already covered by |
|---|---|---|
| A new lint check asserting the attestation exists | PR-1 | Nothing — **CUT**. Check (c) already forces the attestation into the declared set; a second check would restate it |
| A bespoke retry/backoff wrapper for the CLO spawn | PR-1 | **CUT.** The documented mechanic is *resume, not respawn* (`SendMessage` to the agent id). No backoff convention exists to implement |
| A verification script for attestation frontmatter shape | PR-1 | **CUT.** No frontmatter-schema check exists in the guard by design; the precedent file is the template |
| Editing the counsel-review's signed verdict rows to repoint them | PR-4 | **CUT.** Amending a signed instrument to tidy a path is the defect class this register exists to close |
| A follow-up issue to "resolve" the 2026-08-06 divergence | PR-3 | **CUT.** C4 already withdrew the divergence; there is nothing to resolve |

## Research Reconciliation — Issue text vs. codebase

| Issue claim | Reality on `main` | Plan response |
|---|---|---|
| Ruling 1 binds as "4 indexed / 3 waived" | 5 indexed / 6 waived after counsel-review B1 | Bind the rulings as **reasoning at final state**; never restore the superseded arithmetic |
| Sentry cell "now reads Partially" | Cell carries **both** `Partially` and `No`; C2 ruled headline **No**, recorded as an append-only supersession, not applied in-cell | Put the *current* cell text to the CLO; ask whether C2 is applied in-cell or left as supersession |
| Cell "names the T3 residual" | C5: T3 RESOLVED 2026-05-21, promoted to **T4** | Ratification subject is the current text, not the T3 draft |
| 2026-08-06 carries "a performed CLO internal sign-off" | Zero `signed off`/`attested` hits; C4 **withdrew** the claim; register retracted it in `§Register maintenance` | Scope item 3 reduces to *recording* the withdrawal under CLO authority |
| Waiver set exists twice; remove both | True — **and** the attestation file itself must be **added** to both, or check (c) fails (measured, exit 1) | Waiver swap: 6 → 6, membership changed |
| (absent from issue) | `§Excluded records` preamble, its supersession blockquote, and the 2026-05-17 "row above" anchor are all stale, and two of them **defer to #7791 by name** | Discharge them, subject to CLO ruling F6 |
| (absent from issue) | Ship Phase 5.5 will fire on this PR and may write a second audit file into `audits/`, re-tripping check (c) | Pre-declared and handled in Phase 6 |

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` → 63 issues; none names any file in this
plan's edit set. **None.**

## Files to Create

| Path | Author | Notes |
|---|---|---|
| `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md` | **The `clo` agent — never this pipeline** | Per-artifact verdicts + DISCHARGED/BLOCKED. Date in the filename is the attested subject's date (#7717 work), matching the issue's specified path |

## Files to Edit

| Path | Change |
|---|---|
| `scripts/lint-legal-registers.sh` | `NOT_TRANSCRIBED`: remove the implementation-record entry, add an attestation entry citing `#7791`. Net 6 → 6 |
| `knowledge-base/legal/breach-register.md` | `§Excluded records` table: same swap. Plus the stale preamble / supersession / "row above" anchor, subject to CLO ruling. **`status:` untouched** |
| `knowledge-base/INDEX.md` | Replace the line-461 implementation-record entry with the attestation entry, matching the line-454 `CLO attestation — …` shape |
| `knowledge-base/legal/audits/2026-09-counsel-review-7717.md` | **Frontmatter re-issue only** (`status`, `signed_off_at`, `signed_off_by`, `disposition`, empty `blocking_findings`/`required_before_merge`) plus an appended `## Discharge on re-issue` section. Self-authorised by that audit's own disposition. **Signed verdict rows A1–A9 and corrections C1–C5 untouched** |

## Files to Delete

| Path | Precondition |
|---|---|
| `knowledge-base/legal/audits/2026-09-03-implementation-record-7717-art-33-5-register.md` | **Only after** the attestation exists and is verified a content-superset of the four unique items. Pre-authorised by the file's own `re_evaluation_triggers` |

## Implementation Phases

### Phase 0 — Preconditions

0.1 Re-run the baseline: `bash scripts/lint-legal-registers.sh` → exit 0, `waived=6`.
0.2 `git fetch origin && git diff origin/main --stat -- knowledge-base/legal/` → confirm no drift
   (`work` Phase 0.5 check 6 FAILs hard on `knowledge-base/legal/**` drift).
0.3 Capture the byte-exact `status:` line of `breach-register.md` from `origin/main` for the AC7 diff.

### Ordering — the CLO signs LAST, and this is load-bearing

The CLO's verdict is *DISCHARGED against a corrected tree*. An attestation written before the
corrections land would certify a tree that later phases change — and an attestation of a
superseded tree is exactly the "record asserting what it does not hold" defect this issue exists
to close. So the CLO interaction is **two passes**, which is precisely the 7347 precedent's shape:

> `## 1. Finding at attestation — one blocking defect, found and fixed before signing`
> **This attestation would have been BLOCKED had the diff been signed as presented.**

| Pass | Phase | Act |
|---|---|---|
| **1 — read and rule** | Phase 1 | The CLO reads the corpus, issues findings and **drafted replacement wording**. It does not sign |
| *(corrections land)* | Phases 3.1–3.7 | The pipeline applies that wording |
| **2 — sign** | Phase 3.8 | The CLO re-reads the corrected tree and **writes the attestation**, whose §1 records what it found and required fixed before signing |

**Section numbers below are stable identifiers, not an execution order.** The real order is
constrained by a circularity the guard creates, and getting it wrong reds CI:

- the attestation's waiver may not be added until the attestation **file exists** — the guard
  hard-fails `die2 "NOT_TRANSCRIBED waives a path that does not exist"`, **exit 2**, which
  `--advisory` does not downgrade (verified at `scripts/lint-legal-registers.sh`, the
  `[[ -f "$REPO_ROOT/$wpath" ]] || die2` line);
- the implementation record's waiver may not be removed while the record is still on disk, or
  check (c) flags it as neither indexed nor waived;
- so the tree is guard-green **only after all three of** {attestation written, waivers swapped,
  record deleted}. Every intermediate state fails. **They therefore land in ONE commit.**

Execution order:

| # | Step | Why here |
|---|---|---|
| 1 | Phase 0 | Preconditions |
| 2 | Phase 1 (CLO pass 1) | Rules and drafts. Writes nothing |
| 3 | Phase 3.3, 3.5, 3.6 | Prose corrections, using the CLO's drafted wording |
| 4 | **Phase 3.8 (CLO pass 2)** | The CLO re-reads the corrected tree and **writes the attestation**. The file now exists |
| 5 | Phase 3.1, 3.2 | Waiver swap — legal only now that the attestation exists |
| 6 | Phase 4 | Retire the record — legal only now that its waiver is gone |
| 7 | Phase 3.7 | Run the guard. **First moment it can be green** |
| 8 | Phase 2 | Verify the signed artifact |
| 9 | Phase 5, Phase 6 | Sweep, then the ship-gate handoff |

**Breaking the circularity without a third CLO write.** Phase 3.7's measured exit code cannot exist
when the CLO signs at step 4, and the pipeline may never write into the attestation. So the CLO's
Method section states the guard output it **certifies against** (`exit 0`,
`7 assertion(s), 0 failed … produced=10 waived=6`); Phase 3.7 runs the guard and **AC4 asserts the
actual matches the stated**. If they diverge, the attestation is void by its own terms. No third
invocation, and no pipeline write into a CLO-authored file.

### Phase 1 — Brief the CLO and obtain findings plus drafted wording (pass 1)

1.1 **Assemble the brief as ALLEGATIONS PLUS PATHS — not as pasted conclusions.**
   `plugins/soleur/agents/legal/clo.md` declares no `tools:` key, so the agent inherits the full
   tool set and **can read the corpus itself** (verified). The
   `2026-05-12-task-subagent-prompt-text-only` learning says a subagent does not inherit *this
   session's context* — it does **not** say the subagent cannot read files, and treating it that
   way is what breaks this phase.

   **Why paste-only is structurally wrong here.** Under a paste-only brief the ruling becomes a
   function of what this pipeline chose to paste, and this pipeline has already reached
   conclusions. That is the fabricated-signature defect moved one layer back: an attestation *of
   the brief* rather than *of the register*. It also makes CPO condition C1 — the CLO must
   **re-verify** that B1 and R1 are closed — unsatisfiable by construction, because nothing can be
   re-verified from a paste.

   The brief therefore carries, for each item, **the claim, the path, and the instruction to
   check**, never the claim alone:

- that the 2026-05-16 cell answers its own column twice → `knowledge-base/legal/breach-register.md`, `§Index of determinations`;
- that corrections C1–C5 were appended → same file, `§Counsel-review corrections`;
- that the pendency was discharged → same file, `§Rulings on the two waivers recorded as pending`;
- that Ruling 1's arithmetic was superseded by B1 → `knowledge-base/legal/audits/2026-09-counsel-review-7717.md`;
- that the 2026-08-06 "divergence" was withdrawn → `knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md` plus the register's `§Register maintenance`;
- that B1 and R1 are now closed → the index table, `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/article-30-register.md`;
- that the attestation must itself be waived → `scripts/lint-legal-registers.sh` and the measured check-(c) failure.

1.2 **Enumerate the disqualifying facts, as questions rather than findings.** The plan-skill Sharp
   Edge requires naming, for each disposition the pipeline is not proposing, the fact that would
   make it unavailable — otherwise the agent rules confidently on a filtered record. The advisor
   consult's refinement: state each as an allegation to test, not a conclusion to adopt, so the
   discipline is preserved without pre-arguing the case. The ten framing contradictions in
   §Premise Validation carry across in that form.

1.1b **The brief must also carry every DELIVERABLE the later phases require — not just the facts
   to check.** Plan review found the 1.1 list stale: it briefed the CLO on what to verify but never
   asked it to produce most of what Phases 2 and 3 then expect to exist. The brief therefore also
   instructs the CLO to draft, in pass 1:

- **replacement wording for the five stale sites** of Phase 3.3, each marked *correct-in-place*
  or *stack-a-marker* per the rule in that phase;
- **the C2+C3 replacement text** for the 2026-05-16 cell (Phase 3.5);
- the scope of the **2026-08-06 per-artifact verdict** (Phase 2.5), including the hard
  constraint that its `status:` and `BLOCKED` disposition do not move;
- the **frontmatter it will use** at pass 2: three `rulings_of_record` (2.4), the
  `date:`/`attested:` split (AC27), and the carve-outs of AC20;
- the **re-issue frontmatter and `## Discharge on re-issue` text** for the counsel review (3.6);
- which of the four unique items it will carry and how it will label the annex (2.2 / AC10);
- the **conditional disposition rule of AC18**: what it will do if B1 or R1 turns out open.

   Phases 2 and 3 state requirements *about* the attestation; without this step nothing puts those
   requirements *into* the brief the CLO actually receives.

1.2b **Require content anchors.** Every fact the attestation relies on cites a content anchor —
   a heading or a quoted line — never a bare line number (`cq-cite-content-anchor-not-line-number`),
   and the attestation states **which files it read** to confirm B1 and R1 closed.

1.2c **Scope the write.** Instruct the agent that the only file it may create or modify is the
   attestation path. `breach-register.md`'s `status:` in particular is out of bounds. This is an
   instruction, not a sandbox — AC7a/AC7b are the enforcement.

1.3 **Instruct explicitly:** return **drafted replacement wording**, not a bare verdict
   (`workflow-patterns/2026-08-09-legal-decisions-route-to-clo-not-operator.md`); do **not** use
   `AskUserQuestion` (headless). On **pass 1 it does not write the attestation** — it rules and
   drafts. The file is authored by the agent itself at **Phase 3.8**, never by this pipeline: the agent's
   own spec assigns it that act, and the pipeline authoring it would reproduce the
   fabricated-signature defect.

1.4 **Failure arm.** On HTTP 529 or any termination: **first check for a partially-written
   attestation file** — a half-written determination-shaped file under `audits/` is exactly what
   the guard and the fail-closed halt exist to prevent, and resuming on top of one produces a
   record whose provenance nobody can state. Remove it, then **resume the same agent** via
   `SendMessage`; do not respawn (`…four-ways…` §40 — "each was resumed rather than respawned";
   no backoff convention exists, capacity is upstream). Do **not** downgrade the model tier on
   retry — `clo.md` is `model: inherit` and re-tiering a judgment path is itself a
   `clo-attestation`-class change (ADR-053 never-downgrade list).

1.5 **Fail-closed halt.** If the CLO remains unreachable after resume attempts, **no later phase
   runs** — no corrections, no signature, no retirement.

   **Run the 1.4 cleanup once more immediately before declaring the halt.** The cleanup is bound to
   the *pre-resume* step, so a final resume that dies mid-write would otherwise leave a partial,
   unwaived, Art. 33-matching file under `audits/` — check (c)'s RED case, which is precisely the
   guard-failing terminal state this halt is supposed to avoid. Assert `bash
   scripts/lint-legal-registers.sh` exits 0 on the halted tree before stopping.

   **Terminal state, stated rather than left to inference:** leave the PR in **draft**; do not mark
   it ready (`wg-block-pr-ready-on-undeferred-operator-steps`); comment on #7791 recording the
   attempt, the request IDs of every 529, and that AC14 remains unmet; leave #7791 **open**. The
   degraded coverage goes in the review trailer, not the summary (`…four-ways…` §40).

1.6 **The CLO returned, but the artifact is deficient.** Distinct from unreachable. If Phase 2's
   obligation checklist finds a required element missing, **re-brief and resume the same agent**
   naming the specific gap — do not hand-fill it, and do not treat a deficient artifact as a halt.
   Only a genuinely unreachable agent reaches 1.5. The implementation record stays, the plan halts, and the degraded coverage is recorded in
   the review trailer rather than the summary. Deleting the record without an attestation to
   supersede it would be evidence destruction with nothing replacing it. Under no circumstance does
   this pipeline write `signed_off_by: CLO agent`.

### Phase 2 — Verify the attestation against its obligations

*Executes after Phase 3.8, against the signed artifact. The requirements below double as the
brief for what Phase 3.8 must produce.*

2.1 Build the checklist from the CLO's **obligation list** — one grep per required item, hit/miss
   printed. A sweep built from prohibitions ("`status:` unchanged", "record untouched") passes
   while silently missing every obligation.
2.2 **Carry all four unique items into the attestation — CLO ruling F9, which overrules the advisor
   consult's re-homing proposal.** The advisor argued engineering evidence should not pass through
   counsel's signature. The CLO overruled it on a ground the advisor lacked: the attestation's
   per-artifact verdicts **rest** on the AC1-AC13 table, so dropping it leaves the verdicts with no
   stated basis, and A4's APPROVED verdict already *cites* `Implementation: VERIFIED` rather than
   restating it - deleting it leaves A4 pointing at nothing.

   | Item | Verdict | Ground |
   |---|---|---|
   | Three 529 request IDs + act-of-authority reasoning | **MUST, verbatim, ids included** | The whole evidentiary basis for why AC14 was unmet and why no signature was fabricated. Without it the corpus records an unexplained gap, and the *refusal* - the behaviour this issue exists to institutionalise - becomes invisible |
   | The CLO-**unratified** narrative | **MUST** | It is the predicate for the ratification; without it the ratification has no recorded subject |
   | `**Implementation: VERIFIED.**` | **MUST, as an adopted finding** | The only statement in the corpus that AC1-AC13 passed; A4 cites it |
   | The AC1-AC13 table | **MUST, as a labelled annex** | Labelled *"engineering verification, adopted by the CLO as evidence, not as legal finding"* - adopted-as-evidence is not signed-as-finding, which meets the advisor's concern without losing the verdicts' basis |

   Not required to survive: the record's second open item (the post-mortem's stale L110 checkbox) -
   its conclusion is already mirrored in the register's §Register maintenance ("Verified
   2026-09-03"); only the verification method is lost, and that is not load-bearing.
2.3 Assert every markdown row the attestation adds satisfies `cells == header_cells`.

2.4 Carry `clo_rulings_obtained` into `rulings_of_record`, **extended to three rulings** (F1) - the
   counsel review ratified a third (the producer-scoping decision) that the issue, the plan and the
   implementation record all omit.

2.5 **Give the 2026-08-06 determination its first per-artifact verdict.** Verified: it is absent
   from the counsel review's A1-A9 table and was only ever ruled *indexable* under Ruling 1, so no
   CLO instrument has ever issued a verdict on it. The verdict is confined to (a) the register
   row's accuracy against the source and (b) the coherence of the file's own three-part status,
   plus a recital that the divergence claim was withdrawn and why. **Hard constraint:** it must
   **not** flip that file's `status:` or its `BLOCKED` disposition - conditions C1-C7 and C9 are
   REQUIRED and unresolved. The 7347 precedent is directly on point: it signed DISCHARGED while
   expressly leaving C2/C3/C6 "not discharged, and not addressed by this PR".

### Phase 3 - Corrections and the waiver swap

Every waiver-set change moves **both** copies in the **same commit**. That invariant is per-change,
not per-PR: Phase 6's ship-time waiver is a second such change and obeys it independently.

3.1 `scripts/lint-legal-registers.sh`: remove the implementation-record entry; add the attestation
   entry with a reason citing `#7791` (a reason with no `#NNNN` is a fail-closed refusal, exit 2).
3.2 `knowledge-base/legal/breach-register.md` §Excluded records: the identical swap, same commit.
   Check (d) exists precisely to catch a one-sided edit. The new row doubles as the **tombstone**
   for the retired record, in the copy a regulator actually reads (F8) - so it names the
   supersession expressly. **Do not create a stub file**: it would re-create two-records-of-one-
   event and would itself trip check (c) as a seventh waiver.

3.3 **Correct the five stale sites (CLO finding F6).** The CLO will not sign the register as
   presented, because the artifact being attested carries five statements its own contents falsify.

   **Not all five carry the same weight, and plan review was right to press on it.** Site (iv) is
   the fork: a DISCHARGED attestation cannot sit in a document that declares itself incomplete.
   Sites (iii)/(v) are correctness defects inside the very table 3.2 already edits, invisible to
   every gate - locality makes them near-free. Sites (i)/(ii) were already stale on `origin/main`
   independent of anything this PR changes; they ride the same-commit edit as **opportunistic
   cleanup**, and calling all five "the fork" overstated (i) and (ii).

   | # | Site | Defect | Treatment |
   |---|---|---|---|
   | i | §Excluded records preamble | Claims four rows assessed + two undetermined "pending the CLO ruling requested at #7791"; the table holds **six**, all assessed, 2026-05-15 is not among them, and **no reason cell carries any pendency marking** | **Correct in place**, prior text quoted in an appended dated marker |
   | ii | The supersession blockquote | "five assessed and outside, one ruled into the index and **not yet moved there**" - it was moved; the table holds six, not seven | **Stack** a second dated marker beneath; never edit a supersession |
   | iii | 2026-05-17 waiver reason (register copy) | "Confirm alongside the row above at #7791" - discharged, and **"the row above" resolves to `2026-08-counsel-review-7440.md`**, which it never pointed at. Check (d) compares path halves only, so a wrong referent is invisible to every gate | **Correct in place** |
   | iv | §Rulings closing paragraph | **"Until that lands, this register is incomplete against its own stated predicate."** The remediation landed **in the same commit as the annotation** (`5d8a12736`). A controller's statutory register carrying a live admission of incompleteness its own contents falsify | **Stack** a dated marker. **Highest-severity item in this plan** |
   | v | Guard copy of (iii), `scripts/lint-legal-registers.sh` | Same wrong referent, same discharge | **Correct in place** |

   **Rule the CLO drew, applied uniformly:** *current-state prose is corrected in place with its
   prior text quoted in an appended dated marker; a dated marker is never edited - a later
   correction is stacked beneath it.* The register's own §Provenance sets this boundary: it
   protects **signed text** and **the canonical record**, and an index cell is neither ("It is an
   index, not a transcription... Rows are summaries").

3.4 **Scope note (measured):** `breach-register.md` has **no** `docs/legal/` mirror - `docs/legal/`
   and `plugins/soleur/docs/pages/legal/` each hold the same nine published documents and this is
   not among them. The five CI gates over `docs/legal/**` do not apply. Do not over-engineer.

3.5 **Apply C2 AND C3 to the 2026-05-16 cell, and ratify the result.** C2 ruled the headline is
   **No**; the cell still opens **Partially** and then says **No**, handing a reader two answers to
   one question. C3 ruled the clause "which double-counts the 2 signups already inside the 10"
   names the wrong element - 8 + 2 = 10 exactly, so the surplus of one is the **operator**.
   Applying one without the other ships a second known-wrong sentence in the cell just corrected.
   The C2/C3 blockquotes stay in place: they are what makes the in-place edit append-only-compliant.
   The attestation then **ratifies the cell as it reads after C2+C3** - which no CLO instrument has
   ever done (F3).

3.6 **Re-issue the counsel review (R-b).** `2026-09-counsel-review-7717.md` carries
   `status: BLOCKED`, `signed_off_at: null`, `blocking_findings: [B1]`, `required_before_merge: [R1]`
   against a tree where all three of its own re-issue conditions are met. Verified verbatim in its
   `## Disposition`: *"Clear B1, apply R1, and re-run `bash scripts/lint-legal-registers.sh`... On
   those two, the artifact set is sound and this audit may be re-issued as SIGNED-OFF."*
   Re-issue is **self-authorised** by that sentence. Flip the frontmatter and **append** a
   `## Discharge on re-issue - 2026-09-04 (#7791)` section. The body's **signed verdict rows A1-A9
   and corrections C1-C5 are not touched** - that is the F7 line, and it holds.

3.7 `bash scripts/lint-legal-registers.sh` **without `--advisory`** -> exit 0, `waived=6`. R-g: under
   `--advisory` a waiver-parity break prints a warning and exits 0, so "CI was green" is not
   evidence of parity. Record the exit code and the summary line in the attestation's Method
   section. The bare invocation **is** the non-advisory path, so no script or flag change is needed.

   **State the honest version of R-g in the Method section (CTO review).** The blocking safety net
   is not the advisory live arm - it is `lint-legal-registers.test.sh`'s `live corpus passes the
   guard` case, which runs the guard against the real tree inside the *unit* suite, which is
   unconditionally blocking. So a broken swap would fail CI today even before #7787 promotes the
   live arm. Writing "CI was green because `--advisory` masked it" would be the very
   false-reassurance R-g warns about; the accurate statement is that a different, blocking check
   would have caught it.

3.8 **Pass 2 - the CLO signs against the corrected tree.** Resume the same agent (never a fresh
   spawn - it holds the pass-1 record) and hand it the corrected diff. It now **writes the
   attestation itself** at
   `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md`, carrying:

- a `## 1. Findings at attestation` section recording what it required fixed before signing, in
  the 7347 shape ("This attestation would have been BLOCKED had the register been signed as
  presented");
- the per-artifact verdict table, including the 2026-08-06 determination's **first** verdict (2.5);
- the ratification of the 2026-05-16 cell as it reads after C2+C3 (3.5);
- R1 recorded **DISCHARGED with the measurement** - not carved out (F5);
- the four carried items from 2.2, with the AC1-AC13 table labelled as adopted evidence;
- `date: 2026-09-03` / `attested: 2026-09-04` (R-f) and three `rulings_of_record` (2.4);
- express carve-outs: the 2026-08-06 conditions C1-C7/C9, the register's `status:`, and CNIL
  confirmation at Art. 30 counsel-review item 12 (AC20).

   **This is the only phase that creates the attestation, and the pipeline never writes it.**

3.9 **Pass-2 outage — the asymmetric failure mode.** A pass-1 outage is safe: nothing has been
   touched. A **pass-2** outage is not, and plan review found the plan did not distinguish them.
   By the time 3.8 runs, the prose corrections of 3.3/3.5/3.6 have landed. Those are self-contained
   and leave the guard green on their own — they touch prose, not the declared set — so the tree is
   **recoverable, not broken**, provided 3.1/3.2 and Phase 4 have not yet run. That is exactly why
   the execution order puts the waiver swap and the deletion **after** the signature: the only
   irreversible-looking window is one this ordering never opens.

   Protocol: apply 1.4 (remove any partial attestation, resume the same agent, never respawn,
   never downgrade). If the agent is unreachable, stop **before** 3.1 — leave the corrections in
   place (they stand on their own merits and are individually correct), leave the record and its
   waiver untouched, assert `bash scripts/lint-legal-registers.sh` exits 0, and take the 1.5
   terminal state: PR in draft, #7791 open and commented with the request IDs.

### Phase 4 — Retire the implementation record

4.1 Delete the file. 4.2 Replace the `INDEX.md` entry. 4.3 Leave sites 3–8 untouched: they are
historical narration, and two of them are rows inside a **signed** counsel-review verdict table.

### Phase 4b — The BLOCKED arm

The CLO's verdict is a **real fork**, and plan review found only the DISCHARGED arm was built. If
the CLO returns **BLOCKED** — because the Phase 3.3 corrections did not land, or because AC18's
re-verification finds B1 or R1 open after all — then:

4b.1 The attestation is still written, and still by the CLO. A BLOCKED attestation is a valid
    record; it is the *absence* of one that this issue exists to fix. `disposition: BLOCKED`,
    naming the unmet condition.
4b.2 **Phase 4 does not run.** The implementation record stays. Its retirement is conditioned on
    supersession by a *discharged* attestation; a BLOCKED one supersedes nothing, and deleting the
    record against it would be the evidence destruction Phase 1.5 also guards against.
4b.3 The waiver swap of 3.1/3.2 **still runs** — the attestation file exists and must be waived
    either way, and the implementation record keeps its waiver because it keeps existing. Net
    waivers **6 → 7**, not 6 → 6.
4b.4 The PR does not merge. #7791 stays open, retitled to the unmet condition, and the blocker is
    surfaced in the review trailer.

### Phase 5 — Corpus sweep

5.1 Grep the **subject**, not the phrasing, for every claim the attestation changes, and read every
hit (`…four-ways…` §3). 5.2 **File the C1 deferral issue** (F-4) and record its number in the attestation's deferral
sentence — AC26's deferred-branch is unsatisfiable without it. 5.3 Re-run `bash scripts/lint-legal-registers.sh` and
`bash scripts/lint-legal-registers.test.sh` — the unit suite is **blocking** and its
`live corpus passes the guard` case runs the guard against the real tree.

### Phase 6 — Ship Phase 5.5 interaction

The Counsel-Review CLO-Attestation Gate fires on this PR (`legal_touch` non-empty +
`brand_survival_threshold: single-user incident`). Its step 1 writes
`knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md`. Plan review found AC15 had no
owning step — it predicted the consequence without executing it. Numbered steps:

6.1 **Before the ship gate runs**, note that the file it will write is not yet named (its date and
   issue are known only at ship time), so its waiver cannot be pre-added. This is the one waiver
   that legitimately lands in a second commit.

6.2 **Immediately after the gate writes its audit**, add its waiver to **both** copies —
   `NOT_TRANSCRIBED` and `§Excluded records` — in one commit, with a reason citing the issue. Use
   the existing `2026-09-counsel-review-7717.md` row as the template; the ground is identical
   (it assesses no fact pattern and records no controller determination).

6.3 **Re-run `bash scripts/lint-legal-registers.sh` without `--advisory`** and confirm exit 0.
   This is what AC15 asserts.

6.4 **Instruct the ship-time CLO pass to attest the DELTA only** — this PR's diff — and hand it the
   #7717 attestation as input. Its subject is not the #7717 corpus, and without this the corpus
   acquires two records of one event, which is the drift this whole issue removes.

**The same-commit invariant is per waiver-set change, not per PR.** 6.2 is a second such change and
obeys it independently; that is consistent with Phase 3, not an exception to it.

## Guard Contract

*Plan review (DHH) called this heavy for a data-only change, and that is fair. It is kept because
`plan/SKILL.md` §2.12 mandates its shape — a dispatch row, a second-member row and harness rows —
and `scripts/lint-guard-contract.py` enforces it. **Nothing here is built**: every row is analysis
of an existing guard, and the contract's own conclusion is that no new test is needed.*

### Guard 1 — `scripts/lint-legal-registers.sh` declared-set integrity and waiver parity

**Property.** Every determination-shaped file under `knowledge-base/legal/audits/` is either indexed
in the register's index table or carries a cited waiver; the indexed and waived sets are disjoint;
and the machine-readable waiver set is string-equal to the register's human-readable mirror.

**Assembly.** *Not* the six current entries — that is a snapshot, and this PR changes it. The guard
quantifies over four structures, three of which are writable by this diff:

1. The **producer**, evaluated at run time:
   `find audits/ -name '*.md' -print0 | xargs -0 grep -lE "$DETERMINATION_PATTERN"`. Creating *any*
   file under `audits/` that cites Art. 33 / Art. 4(12) mutates this set — which is why the
   attestation and the ship-time counsel review each need a waiver.
2. `NOT_TRANSCRIBED` in `scripts/lint-legal-registers.sh`.
3. The `## Excluded records` table's **File column** in `knowledge-base/legal/breach-register.md`.
4. The `## Index of determinations` table's **canonical-source column**.

There is **no single source (2) and (3) derive from**; detecting that they have come apart is the
guard's entire purpose. So the chokepoint is a *commit-level* one: 2 and 3 must move together.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| M1 | Attestation file created, no waiver in either copy | **RED** — (c) "neither indexed nor waived", exit 1. **Already measured this session** |
| M2 | Remove the implementation-record entry from `NOT_TRANSCRIBED` only | **RED** — (d) parity diff |
| M3 | Remove the `§Excluded records` row only | **RED** — (d) parity diff, opposite direction |
| M4 | Attestation waiver added to both copies with a reason carrying no `#NNNN` | **RED** — fail-closed refusal, exit **2** (not downgraded by `--advisory`) |
| M5 | *(guard's own dispatch)* Producer resolves to zero files | **RED** — the guard must refuse, not report "0 checked" and exit 0 |
| M6 | *(second member after a compliant first)* Attestation waived correctly, then a **second** determination-shaped file added unwaived | **RED** — proves (c) does not stop at the first member |
| M7 | *(must-PASS, non-canonical)* The full intended swap applied | **GREEN**, exit 0, `waived=6` |

**Harness rows.**

| # | Mutation to the SUITE | Expected |
|---|---|---|
| H1 | Stub `lint-legal-registers.sh` to `exit 0` unconditionally | `lint-legal-registers.test.sh` must go **RED** — proves the suite exercises the guard rather than merely invoking it |
| H2 | *(must-PASS, non-canonical)* Run the guard against a synthesized corpus with a **different but valid** waiver set (2 waivers, not 6) | **GREEN** — proves the guard is not diffing against the canonical |

**Pre-existing coverage (measured, so this plan builds nothing new).**
`scripts/lint-legal-registers.test.sh` already carries an anti-vacuity floor
(`floor: dropping an assertion reds even with zero failures`), a no-break-after-first-hit case, a
disjointness case for an already-waived file, `--advisory` downgrade semantics, the fail-closed
`rc=2` case, and `live corpus passes the guard`. The swap is **data, not logic**; the existing
suite covers it. Adding a bespoke test for the swap is **CUT**.

## Observability

*Detection is strictly negative — repo-root `scripts/` is not in the gate's trigger list and no
infra surface is introduced — so this section is elective, and plan review (DHH) argued for cutting
it to one line. Kept because the diff changes a CI assertion's declared set and Phase 3's entire
risk lives in the failure modes below; a one-line version would also fail deepen-plan Phase 4.7.*

```yaml
liveness_signal:
  what: "bash scripts/lint-legal-registers.sh — 7 assertions over the 4 register files"
  cadence: "every PR"
  alert_target: "CI job test-scripts -> synthetic aggregator job `test` (required check)"
  configured_in: "scripts/test-all.sh (both the unit suite and the live --advisory arm); .github/workflows/ci.yml"
error_reporting:
  destination: "GitHub Actions ::error:: annotations, emitted per failing assertion with the remedy inline"
  fail_loud: true
failure_modes:
  - mode: "Waiver copies come apart (one-sided edit)"
    detection: "assertion (d) prints a diff of declared vs documented waivers"
    alert_route: "::error:: in job test-scripts; blocking via the unit suite's live-corpus case"
  - mode: "A new determination-shaped file is neither indexed nor waived"
    detection: "assertion (c), naming the file and both remedies"
    alert_route: "::error:: in job test-scripts"
  - mode: "A waiver carries no citing issue"
    detection: "fail-closed refusal, exit 2 — NOT downgraded by --advisory"
    alert_route: "non-zero exit propagates through test-all.sh regardless of advisory mode"
  - mode: "Register parse yields zero rows (guard cannot read its own input)"
    detection: "fail-closed die2 — the guard refuses rather than reporting a vacuous pass"
    alert_route: "exit 2"
logs:
  where: "GitHub Actions job log for test-scripts; the guard prints one [ok]/::error:: line per assertion plus a summary tallying registers/rows/produced/waived/waiver-parity"
  retention: "GitHub Actions default retention"
discoverability_test:
  command: "bash scripts/lint-legal-registers.sh"
  expected_output: "lint-legal-registers: 7 assertion(s), 0 failed (registers=4 rows=5 produced=10 waived=6 waiver-parity=ok) followed by === lint-legal-registers: all assertions passed ===, exit 0"
```

**`produced` stays at 10 — the swap conserves cardinality.** The retired implementation record leaves
the producer set and the attestation enters it, one for one. An earlier draft of this plan asserted
`produced=11` in four places; that is the *intermediate* state (attestation added, record not yet
deleted), which does not pass. Corrected at plan review after the final state was simulated in a
sandbox and measured: `produced=10 waived=6 waiver-parity=ok`, with
`(c) all 10 determination-shaped audits/ file(s) are indexed or waived` green. The ship-time counsel
review of Phase 6 then makes it 11.

## Test Scenarios

| # | Scenario | Expectation |
|---|---|---|
| T1 | Guard run on the untouched tree | exit 0, `produced=10 waived=6` |
| T2 | Attestation added, no waiver | exit 1, (c) names the file |
| T3 | Waiver removed from the array only | exit 1, (d) prints the parity diff |
| T4 | Waiver removed from the register table only | exit 1, (d) prints the parity diff |
| T5 | Attestation waiver reason with no issue citation | exit 2 |
| T6 | Full swap applied (attestation created, record deleted, both waiver copies swapped) | exit 0, `produced=10 waived=6` |
| T7 | `bash scripts/lint-legal-registers.test.sh` | all assertions pass |
| T8 | `git diff origin/main -- knowledge-base/legal/breach-register.md \| grep '^[-+]status:'` | **empty** |
| T9 | Every markdown row added or edited | `cells == header_cells` (index table 9, `§Excluded records` 2) |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Hand-write the attestation and sign it `signed_off_by: CLO agent` | The exact defect class the register exists to close. Explicitly forbidden |
| Annotate the implementation record instead of deleting it | Two records of one event — the drift the register exists to avoid. The record's own frontmatter pre-authorises deletion |
| Apply binding Ruling 1's "4 indexed / 3 waived" verbatim | Would un-index `sentry-migration-audit-2026-05-15.md` and reopen blocking finding B1 |
| Change `breach-register.md`'s `status:` to reflect the new attestation | External counsel promotes it out of draft; an internal v1 attestation does not. Expressly out of scope |
| Defer the stale `§Excluded records` preamble to a new issue | The register defers to **#7791 by name** in those very places. Deferring would leave this issue's own named pendency open |
| Let ship Phase 5.5 discover the second check-(c) trip | A predictable CI failure is cheaper to pre-declare than to debug at ship time |
| Add a frontmatter discriminator (`record_kind: attestation`) the guard's producer skips, closing the waiver churn permanently | **Advisor consult proposal — declined as out of scope.** The CLO already considered and accepted this cost: "Every future counsel review of this register will need the same waiver — that is a known cost of scoping the producer to `audits/**`, **not a defect**." Changing the producer's semantics would also amend a gate governed by ADR-200 and tracked for promotion at #7787, which would fire the ADR gate this plan otherwise skips. The advisor's underlying point is met instead by stating the same-commit invariant per *change* rather than per *PR* |
| Apply C1's corrected figures (`102` → **104**, re-measured) at the three genuinely stale sites in this PR | **Deferred, with a tracking issue filed in the work phase** (AC26). C1 is a ruled correction whose scope reaches ADR-200, the guard header and Art. 30 item 12 — three artifacts outside this issue's subject. Deferring is defensible; deferring **silently** is not, so the attestation must state it and name the issue |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The CLO agent 529s again | Resume via `SendMessage`, never respawn; never downgrade the tier. If still unreachable at pass 1, **no later phase runs** and the record stays (Phase 1.5). A **pass-2** outage is a different, worse case — Phase 3.9 |
| Deletion loses evidence | Phase 2.2 asserts content-superset before Phase 4 deletes. Ordering is load-bearing |
| The CLO rules DISCHARGED while R1 is open | The brief puts R1 to it expressly (F5) and asks whether an explicit carve-out is required, as the 7347 precedent carved out C2/C3/C6 |
| A one-sided waiver edit | Check (d), plus the same-commit constraint in Phase 3 |
| Ship Phase 5.5 writes a second record of one event | Phase 6 pre-declares both the waiver need and the delta-only instruction |
| An unescaped `\|` silently drops a verdict cell | T9 asserts `cells == header_cells` — this exact defect discarded a `CONFIRMED` verdict in a signed counsel review (`…four-ways…` §4) |
| Applying C2 in-cell breaches append-only | Put to the CLO as F2; it decides between in-cell application and supersession-only |

## Acceptance Criteria

Every AC names a literal command **and** its behaviour on the untouched tree, so none can be
satisfied by a tree that changed nothing (`…four-ways…` session error 2).

**AC13 and AC19 were cut at plan review** — AC13 restated a phase instruction with no independent
command, and AC19's `git log --follow` clause was tautologically true of any tracked deletion while
its grep duplicated AC6. The numbering keeps its gaps: AC ids are stable identifiers cited from
`## Domain Review`, and renumbering would break those references.

**Run them as one generated script, not 27 turns of copy-paste** (CTO review). Several are
order-dependent (AC7b is only meaningful once AC7a holds; AC10's file count depends on AC8 having
run), and hand-transcribing 27 commands across a session boundary is exactly where a wrong path or
a wrong baseline produces a false pass. Emit one `[ok]`/`::error::` line per assertion plus a
summary — the shape the guard itself uses — and paste the output into the review trailer. The
script is session-scoped and **not committed**: its literals (`produced=10`, specific paths) have a
shelf life of one PR.

### Pre-merge (PR)

| # | Criterion | Command | Baseline on `origin/main` |
|---|---|---|---|
| AC1 | The attestation exists | `test -f knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md` | **FAILS** (absent) |
| AC2 | It was authored by the `clo` agent, not this pipeline. The review trailer records the invocation, its outcome, and any 529/resume cycles | trailer inspection + `grep -c 'attestation-authority: clo' <attestation>` ≥ 1 | **FAILS** (no file) |
| AC3 | It carries per-artifact verdicts and a disposition | `grep -cE '^disposition:\s*(DISCHARGED\|BLOCKED)' <attestation>` = 1 **and** a `\| Artifact \| Verdict \|`-shaped table is present | **FAILS** |
| AC4 | The guard passes with the swapped set, run **without `--advisory`** (R-g: advisory downgrades a parity break to exit 0, so "CI was green" is not evidence of parity) | `bash scripts/lint-legal-registers.sh` → exit 0, summary reads `produced=10 waived=6`; exit code and summary recorded in the attestation's Method section | Baseline also exits 0 at `produced=10` — **so AC4 is load-bearing only via AC5/AC6's membership check plus T2-T5's mutation rows**; the count alone cannot distinguish baseline from the swapped set |
| AC5 | The retired record is absent from **both** waiver copies | `grep -c 'implementation-record-7717' scripts/lint-legal-registers.sh knowledge-base/legal/breach-register.md` → `0` and `0` | **FAILS** (`1` and `1`) |
| AC6 | The attestation is waived in **both** copies | same grep for `clo-attestation-7717` → ≥ `1` and ≥ `1` | **FAILS** (`0` and `0`) |
| AC7a | The register was actually edited | `git diff origin/main --name-only \| grep -c 'legal/breach-register.md'` = 1 | **FAILS** (0) |
| AC7b | …and its `status:` was **not** | `git diff origin/main -- knowledge-base/legal/breach-register.md \| grep -c '^[-+]status:'` = 0 | Passes trivially alone — **load-bearing only paired with AC7a** |
| AC8 | The implementation record is retired | `test ! -f knowledge-base/legal/audits/2026-09-03-implementation-record-7717-art-33-5-register.md` | **FAILS** (present) |
| AC9 | `INDEX.md` points at the attestation, not the retired record | `grep -c 'implementation-record-7717' knowledge-base/INDEX.md` = 0 **and** `grep -c 'clo-attestation-7717' knowledge-base/INDEX.md` = 1 | **FAILS** (`1` and `0`) |
| AC10 | Nothing unique is lost. **Per CLO ruling F9 all four items land INSIDE the attestation**, with the AC1–AC13 table carried as an annex labelled *"engineering verification, adopted by the CLO as evidence, not as legal finding"*. (An earlier draft of this AC required the opposite — re-homing them outside — and was corrected at plan review: F9 overruled that routing, and the AC had not been updated to match.) | the attestation carries the three 529 request IDs, the unratified narrative, `Implementation: VERIFIED`, and the labelled AC1–AC13 annex; the learning file survives — `grep -rl 'req_011CegcTbK6bQXipPMqhFHVS' --exclude-dir=.git --exclude-dir=specs --exclude='*-plan.md'` still returns `knowledge-base/project/learnings/2026-09-03-four-ways-…md`. **The exclusions are load-bearing**: this plan and the #7717 `session-state.md` both quote the request IDs, so an unscoped grep matches the planning artifacts and reads as coverage that does not exist | Baseline: **3** tracked files on `origin/main` carry the request IDs (`git grep -l … origin/main`), and no attestation exists — **FAILS**. An earlier draft said 4, counting this plan's own untracked prose — the same count-includes-my-own-diff mechanism as R-e |
| AC11 | Every markdown row added or edited satisfies `cells == header_cells` (index table **9**, `§Excluded records` **2**) | per-row cell count over the diff | n/a — asserted over the diff |
| AC12 | The blocking unit suite passes, including its `live corpus passes the guard` case | `bash scripts/lint-legal-registers.test.sh` | Passes at baseline; **would red** on a broken swap |
| AC14 | The counsel review's **signed verdict rows A1–A9 and corrections C1–C5 are byte-unchanged**; the only edits are the frontmatter re-issue and the appended `## Discharge on re-issue` section | `git diff origin/main -- …2026-09-counsel-review-7717.md` touches no line inside `## Per-artifact verdicts` or `## Corrections appended during this review`; `related:` unchanged | Empty at baseline — paired with AC8, which makes the reference dangle |
| AC15 | If ship Phase 5.5 writes an audit into `audits/`, it is waived in **both** copies before merge | `bash scripts/lint-legal-registers.sh` → exit 0 after that file lands | n/a — post-Phase-6 |

### Post-merge

| # | Criterion |
|---|---|
| AC16 | `#7791` closes via `Closes #7791` in the PR body |
| AC17 | The CI `test` required check is green on the merge commit |

## Gate Dispositions

| Gate | Fires? | Disposition |
|---|---|---|
| 1.4 Network-outage checklist | No | No trigger keyword; no SSH/provisioner dependency |
| 1.8 Skill-description budget | No | No `SKILL.md` `description:` edit is candidate or final |
| 2.7 GDPR / compliance | **Yes**, via trigger (b) — `single-user incident` declared | The canonical path regex does not match (`knowledge-base/legal/**` is not a schema/auth/API/`.sql` surface). The substantive review is **the deliverable itself**, performed by the `clo` agent, which is a strictly higher authority than the advisory gate. `gdpr-gate.sh` is a lefthook pre-commit breadcrumb that always exits 0 and runs at commit time |
| 2.8 IaC routing | No | No server, service, cron, vendor account, DNS record, secret, or firewall rule |
| 2.9 Observability | **Yes** (elective) | Detection is strictly negative — repo-root `scripts/` is not in the trigger list (`plugins/*/scripts/`) and no infra surface is introduced. Section supplied anyway because the diff changes a CI assertion's declared set |
| 2.9.1 Soak follow-through | No | No time-gated close criterion |
| 2.10 ADR / C4 | No | No architectural decision. ADR-200 governs the register and is unchanged; this plan neither extends nor diverges from its `## Decision` |
| 2.11 Encryption posture | No | No persistent store and no new cross-component connection |
| 2.12 Guard contract | **Yes** | Supplied above. The deliverable modifies a guard's declared set |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at runtime — this plan touches no UI, route,
schema, migration or credential. The honest path is indirect and evidentiary. An alpha tester
exercising an Art. 15 subject-access right, or a supervisory authority under Art. 58(1)(a), follows
the pointer chain `docs/legal/privacy-policy.md` → the Art. 30 register → this breach register, and
finds either (i) a **signed** CLO attestation certifying DISCHARGED over a register that
simultaneously reads `status: draft-requires-counsel-review`, with nothing explaining how the two
coexist, or (ii) that `status:` field itself flipped, implying an external counsel review that never
happened. Either way the company's compliance paperwork contradicts itself under precisely the
scrutiny this register exists to survive.

**If this leaks, the user's data is exposed via:** no new exposure vector — no data flow, credential
or access surface changes. The exposure that matters is evidentiary, not personal-data: a mis-signed
or over-scoped attestation becomes itself a discoverable document that a regulator or an alpha
tester's counsel can cite as evidence that the company's internal compliance process overstates
certainty. That is a second-order exposure of credibility, not of any user's personal data — and
saying so plainly is more useful than inventing a runtime failure mode this change cannot cause.

**Brand-survival threshold:** single-user incident

## Domain Review

**Domains relevant:** Legal, Product

### Product/UX Gate

**Tier:** none. The mechanical UI-surface override does not fire — `## Files to Create` and
`## Files to Edit` contain no path matching the UI-surface term list or glob superset (all entries
are under `knowledge-base/legal/`, `knowledge-base/INDEX.md`, or `scripts/`). No new component,
page, or layout file. `ux-design-lead` is correctly not invoked; `wg-ui-feature-requires-pen-wireframe`
does not apply to a change with no UI surface.

### Product (CPO)

**Status:** reviewed
**Verdict:** **APPROVED WITH CONDITIONS**

The CPO independently re-verified both items the prior counsel review made merge-blocking and found
**both already resolved at HEAD** — a finding this plan then re-measured rather than accepted:

- **B1** — `sentry-migration-audit-2026-05-15.md` is indexed as its own row (measured: 5 index rows,
  0 hits in `NOT_TRANSCRIBED`).
- **R1** — `knowledge-base/legal/compliance-posture.md:96` now reads
  `NOT EXECUTED — no Art. 28(3) instrument recorded`, under a `[2026-09-03 CORRECTION (#7717)]`
  marker superseding the former `PENDING (sign Vendor DPA …)`, matching the Art. 30 Vendor Mapping
  row. Verified independently by this plan.

The CPO's central finding: **the plan delegated authority to the CLO without requiring it to
re-verify the preconditions that authority depends on.** A DISCHARGED disposition is only available
because B1 and R1 happen to be closed — and nothing in the plan made the CLO check that. Folded in
as **AC18**.

Ranked blast radius, in the CPO's order:

1. **Changing `status:` is the one truly brand-destroying edit here** — a one-line frontmatter change
   in a file two public-facing legal documents point data subjects at. It would misstate the whole
   register's posture, not one row. (AC7a/AC7b.)
2. **DISCHARGED asserted over a live B1/R1 would be worse than the original defect.** A recorded
   *absence* of signature reads to a regulator as candour; a signed attestation certifying a false
   completeness claim reads as an internal control that certifies falsehoods. (AC18.)
3. **Evidence loss on deletion is low-risk by construction** — a tracked `git rm` stays recoverable
   through history, and the record's own frontmatter asks to be deleted rather than annotated. The
   real exposure is dangling citations, which must be a conscious call rather than an oversight.
   (AC14, and the site table in §Research Insights.)

On proportionality, the CPO rejected the framing that a full pipeline is disproportionate for an
issue labelled "Non-substantive": that label explains *why* the gap exists (an API 529, not a
judgment error), not what closing it is worth. The register **defers to #7791 by name**, so the
pendency is an open pointer inside a regulator-facing document with a carrying cost on every future
determination — and the custodianship model the register states for itself is half-built until the
attestation exists.

**CPO conditions C1–C5 → acceptance criteria:** C1 → AC18; C2 → AC7a + AC7b; C3 → AC8 + AC6;
C4 → AC5 + AC6 + the same-commit constraint in Phase 3; C5 → AC20. (C3's forward-pointer clause maps to **AC6** — it was briefly mapped to AC19, which plan review cut as duplicative of AC6.)

### Legal (CLO)

**Status:** reviewed
**Verdict:** **DISCHARGED against a corrected tree — BLOCKED if the §Stale-site corrections do not
land in this PR.** A real fork, not a formality.

The CLO read every file and **falsified one of this plan's premises**. Rulings on F1–F10, condensed;
each was independently re-measured by this plan before folding in.

| Ref | Ruling | Plan response |
|---|---|---|
| **F1** | **CONFIRMED** — the rulings bind at final state, as reasoning. Ruling 1 was superseded *by the same authority*; applying "4/3" verbatim is "picking which CLO instrument to obey". **And there are THREE rulings of record, not two** — the counsel review ratified a third (the producer-scoping decision). Verified: A1–A9 + §What was verified | Kept; `rulings_of_record` enumerates three (**AC21**) |
| **F2** | **Both** — ratify *and* apply C2 in-cell. Applying it **discharges** append-only rather than violating it: the register's §Provenance protects *signed text* and *the canonical record*, and an index cell is neither ("It is an index, not a transcription… Rows are summaries"). Leaving it unapplied **is** the #7349 defect | New Phase 3.5 (**AC22**) |
| **F2b** | **C3 travels with C2** — the same cell still carries "which double-counts the 2 signups already inside the 10", which C3 ruled names the wrong element. Applying one and not the other ships a second known-wrong sentence in the cell just corrected | Folded into Phase 3.5 |
| **F3** | Spent as to T3; **live as to its real subject.** No CLO instrument has ever ratified the corrected cell. Ratify the cell **as it will read after C2+C3**, on the record | Phase 3.5 + **AC22** |
| **F4** | No divergence remains — **but scope item 3 is not a recital.** The 2026-08-06 determination **is absent from the A1–A9 verdict table** (verified) and was only ever ruled *indexable*. It has never had a per-artifact verdict from any CLO instrument | New Phase 2.5 (**AC23**) |
| **F5** | **PREMISE FALSIFIED — R1 is CLOSED.** Carving out a closed finding "asserts a compliance gap that does not exist… a false negative is the same defect class as a false positive" | **Plan reversed** — see below |
| **F6** | **In scope, mandatory, and FIVE stale sites, not three** | New Phase 3.4 |
| **F7** | **CONFIRMED** — verdict rows stay; a verdict is true of the artifact as it stood, permanently. On site 3 (`related:`) the CLO differs from "decide": **leave it** | AC14 refined |
| **F8** | Pre-authorisation is **necessary but not sufficient**. Lawful on three conditions: the CLO expressly executes the trigger; content-superset; a tombstone survives **in the working tree** (git history is not one — a regulator is shown the tree). **Do not create a stub file** — it would re-create two-records-of-one-event and trip check (c) | Phase 4 + **AC6** |
| **F9** | **All four items MUST be carried** — this overrules the advisor consult on re-homing. Ground for (b): the per-artifact verdicts **rest** on the AC1–AC13 table; dropping it leaves them with no stated basis. Carry it labelled *"engineering verification, adopted by the CLO as evidence, not as legal finding"* | Phase 2.2 reconciled below |
| **F10** | Waiving the attestation is correct and **not a close call** — indexing it would be affirmatively wrong (limb 1 fails on its face) and would reintroduce the inconsistency B1 blocked on | Unchanged |

#### The premise reversal (F5)

This plan previously recorded R1 as open and directed the attestation to carve it out. **Measured and
wrong.** `knowledge-base/legal/compliance-posture.md:96` reads `NOT EXECUTED — no Art. 28(3)
instrument recorded` under a `[2026-09-03 CORRECTION (#7717)]` marker; `article-30-register.md:446`
carries the matching retraction; both present on `origin/main`. **The attestation records R1 as
DISCHARGED, with the measurement.**

The general rule survives for future use: an attestation *may* return DISCHARGED over an open
`required_before_merge` item, but only with an express carve-out naming it — the 7347 §4 shape.
A silent DISCHARGED over an open item is a false clean field.

#### R-b — the counsel review's own frontmatter is stale, and re-issuing it is self-authorised

`2026-09-counsel-review-7717.md` still carries `status: BLOCKED`, `signed_off_at: null`,
`blocking_findings: [B1]`, `required_before_merge: [R1]` against a tree where all three of its own
re-issue conditions are met. Verified verbatim in its `## Disposition`:

> **BLOCKED.** Clear B1, apply R1, and re-run `bash scripts/lint-legal-registers.sh`… On those two,
> the artifact set is sound and this audit may be re-issued as SIGNED-OFF.

B1 remediated (measured), R1 closed (measured), lint exits 0 (measured). A BLOCKED audit standing
over a remediated artifact set is the two-records-disagree defect the register exists to close — and
it is the *audit* a supervisory authority is handed. New Phase 3.6.

#### Additional risks the CLO named that this plan had not

**R-a is the most serious item in the review, and it outranks everything #7791 asked about.** The
register carries a live admission — *"**Until that lands, this register is incomplete against its own
stated predicate, and this paragraph is the record of it.**"* — which its own contents falsify, since
the remediation landed **in the same commit as the annotation** (`5d8a12736`). A controller's
statutory register asserting its own incompleteness, in the document an Art. 58(1)(a) reader is
handed, is an admission against interest that is untrue.

| Ref | Risk | Handling |
|---|---|---|
| **R-a** | False self-declaration of incompleteness, live on `main` | Phase 3.4 site (iv), **AC24** |
| **R-b** | Counsel review's stale `BLOCKED` frontmatter | Phase 3.6, **AC25** |
| **R-c** | C3 absent from the plan | Phase 3.5 |
| **R-d** | 2026-08-06 has no per-artifact verdict anywhere | Phase 2.5, **AC23** |
| **R-e** | C1's corrected figures unapplied in **three** sites (`102` in the register's §Inclusion predicate, ADR-200, the guard header). **Measured at plan review: Art. 30 counsel-review item 12 already reads `104`** — the CLO's own C1 sentence ("is wrong in both") was false when written, and this plan repeated it unmeasured until the correctness pass caught it. Live count re-measured: **104** | **Deferred with a named issue**; the attestation records the C1 mis-statement rather than editing that signed row (F7). **AC26** |
| **R-f** | Filename says 2026-09-03; the act occurs 2026-09-04 | `date:` / `attested:` split per the 7347 precedent. **AC27** |
| **R-g** | `--advisory` masks check (d) — "CI was green" is not evidence of parity | Run the lint **without** `--advisory` and record exit code + summary. **AC4** amended |
| **R-h** | `tasks.md:47` / `session-state.md` still say "AC14 unmet" | Left as historical; the attestation states AC14 is now MET and names them |
| **R-i** | `status:`-pinning covers only the register | Extended to the 2026-08-06 file's `status:` + `BLOCKED`, and ADR-200. **AC28** |
| **R-j** | Cell-count re-assertion after C2/C3 edits | **AC11** already covers; index rows are 9 cells, excluded rows 2 |

#### Reconciling F9 against the advisor consult

The advisor argued the AC1–AC13 table and `Implementation: VERIFIED` should be re-homed out of the
attestation, because pushing engineering evidence through counsel's signature is the same defect
class one layer along. The CLO — the authority on this question — **overrules that** on a ground the
advisor did not have: the attestation's per-artifact verdicts *rest* on that table, so dropping it
leaves the verdicts with no stated basis, and A4's APPROVED verdict already cites
`Implementation: VERIFIED` rather than restating it.

The advisor's concern is nonetheless met by the CLO's own remedy: the table is carried **labelled**
*"engineering verification, adopted by the CLO as evidence, not as legal finding"*. Adopted-as-evidence
is not signed-as-finding. **Phase 2.2's routing table is superseded by this.**

## Additional Acceptance Criteria (from domain review)

| # | Criterion | Command | Baseline on `origin/main` |
|---|---|---|---|
| AC18 | The attestation **re-verifies** B1 and R1 at the attested commit rather than assuming them, and states the evidence for each. If either fails, the disposition is BLOCKED, not DISCHARGED | attestation cites (i) `sentry-migration-audit-2026-05-15.md` present as an index row, (ii) the Better Stack DPA status string identical in `compliance-posture.md` and `article-30-register.md` | **FAILS** (no attestation) |
| AC20 | The DISCHARGED disposition does not read as unbounded completeness: the attestation carries forward, verbatim or by direct citation, (i) that external CNIL confirmation of the separate-instrument choice remains open at Art. 30 counsel-review item 12, and (ii) the register's bounded scope (`audits/**` plus the one pinned post-mortem) | grep the attestation for both caveats | **FAILS** |
| AC21 | `rulings_of_record` enumerates **three** CLO rulings, not two — the counsel review ratified a third (the producer-scoping decision) that the issue, the implementation record and this plan's first draft all omit | `grep -c` the attestation's `rulings_of_record` block for three distinct ruling names | **FAILS** (no attestation) |
| AC22 | C2 **and** C3 are applied in the 2026-05-16 cell, and the attestation ratifies the cell as it then reads | the cell's `Evidentiary limbs inconclusive?` column opens `**No.**`; `grep -c 'which double-counts the 2 signups already inside the 10' knowledge-base/legal/breach-register.md` = 0 outside the C3 blockquote; the C2/C3 blockquotes still present | **FAILS** — baseline cell opens `**Partially`, and the double-counts clause is live |
| AC23 | The 2026-08-06 determination receives its first per-artifact verdict, **without** its `status:` or `BLOCKED` disposition changing | verdict row present in the attestation; `git diff origin/main -- …2026-08-06-alpha-tester-controller-processor-determination.md` → **empty** | **FAILS** (no verdict exists in any CLO instrument) |
| AC24 | The register carries **no live admission of incompleteness its own contents falsify** | Three literal commands, no eyeballing: (a) `grep -c 'this register is incomplete against its own stated predicate' knowledge-base/legal/breach-register.md` = 1; (b) the occurrence is quoted **inside** a supersession — `grep -B8 'this register is incomplete' knowledge-base/legal/breach-register.md | grep -c '^> \*\*Superseded'` >= 1; (c) a stacked marker follows — `grep -A12 'this register is incomplete' knowledge-base/legal/breach-register.md | grep -c 'Superseded 2026-09-04 (#7791)'` = 1 | **FAILS** — baseline has it live and unstacked |
| AC25 | The counsel review is re-issued SIGNED-OFF with empty `blocking_findings` and `required_before_merge`, and a `## Discharge on re-issue` section citing measured evidence for B1, R1 and the lint | frontmatter greps + section present | **FAILS** (`BLOCKED`, `signed_off_at: null`) |
| AC26 | C1's corrected figures are either applied at the **three** genuinely stale sites **or** the attestation states the deferral **and cites an issue number** | Applied-branch: `grep -c '\b102\b'` = 0 in `knowledge-base/legal/breach-register.md`, the ADR-200 file, and `scripts/lint-legal-registers.sh`. Deferred-branch: `grep -cE 'C1.*#[0-9]+' <attestation>` >= 1 — an unnumbered "deferred" does not satisfy it. **Do not grep `article-30-register.md`**: item 12 already reads `104` (measured), and a whole-file `\b102\b` there returns unrelated hits (`migration 102`, `ADR-102`) while missing the datum entirely | Baseline: `102` live at the three sites, item 12 already correct — **applied-branch FAILS, so the deferred-branch must carry the issue number** |
| AC27 | The attestation's frontmatter separates `date: 2026-09-03` (the subject's date, matching the issue's named path) from `attested: 2026-09-04` (when the act occurred), per the 7347 precedent | `grep -c '^attested: 2026-09-04'` = 1 | **FAILS** — and a single `date:` alone would assert an act on a day it did not happen |
| AC28 | The `status:`-pin extends beyond the register: the 2026-08-06 file's `status:` and `BLOCKED` disposition, and ADR-200, are byte-identical to `origin/main` | `git diff origin/main -- <those paths>` → empty | Empty at baseline — load-bearing only because the PR touches the surrounding corpus |

## Sharp Edges

*Trimmed at plan review (DHH): three entries restated material already stated at full length in
Phases 1-4 and in Risks. Only the two that appear nowhere else survive.*

- **The two "binding rulings" the issue says to apply as given are not safe to apply as given.**
  Ruling 1's arithmetic was superseded the same day by the CLO's own B1 finding. A binding ruling
  binds as *reasoning at its final state*, not as the numbers it first carried. Anyone working from
  the issue body rather than this plan will re-introduce the regression — and the issue body is
  what a future reader finds first, which is why the attestation must correct it on the record.

- **A plan whose `## User-Brand Impact` section is empty, carries only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled with the CPO's
  drafted wording; do not reduce it to boilerplate.

## Plan Review — panel, coverage, and consolidated decisions

Escalated 5-agent panel (threshold `single-user incident`) plus a devex lens, since the diff edits a
CI guard. **6 of 6 returned** — two only after a `SendMessage` resume, having stalled with empty
transcripts. Resume-not-respawn is the same recovery this plan prescribes for the CLO at Phase 1.4,
and it worked here: both late reviewers returned load-bearing findings that the on-time four missed.

| Reviewer | Returned | Headline |
|---|---|---|
| `code-simplicity-reviewer` | yes | Per-mechanism pass; flagged Phase 3.6 as unbacked by the Property List, and two of the five stale sites as opportunistic |
| `dhh-rails-reviewer` | yes | Plan is ~3× its issue; Guard Contract and Observability are template ceremony; 28 ACs should be ~10 |
| `architecture-strategist` | yes | **Found the load-bearing defect**: `produced=11` is unreachable in any passing state; verified the correct value is `produced=10` by running the swap |
| `spec-flow-analyzer` | yes | **Found four flow gaps**: the ordering contradiction, AC10 contradicting F9, a stale Phase-1 brief, and a missing BLOCKED writer-path |
| `soleur:engineering:cto` | yes | Devex: the CLO invocation protocol is bespoke; proposed an `add-legal-waiver.sh` preventive control; corrected the `--advisory` framing |
| `kieran-rails-reviewer` | yes, **late** | Stalled with an empty transcript for ~10 min and returned only after a `SendMessage` resume. **Found the second load-bearing defect**: R-e/AC26 asserted four stale `102` sites when only three are stale — Art. 30 item 12 already reads `104` |

**The two defects that mattered were each found by exactly one reviewer, and both by execution
rather than reading.** `architecture-strategist` ran the swap in a sandbox and found `produced=11`
unreachable; `kieran-rails-reviewer` ran the AC commands and found R-e's fourth site already
correct. Neither is visible to a careful read — which is the argument for the one-script
verification convention now in `## Acceptance Criteria`: the work phase runs all 27 mechanically and
pastes the output, rather than trusting prose.

**Both late reviewers had to be resumed, not respawned.** That is the same protocol Phase 1.4
prescribes for the CLO, applied to the review panel, and it is the second time this session hit the
capacity failure mode the underlying issue documents.

### Consolidated decisions

| # | Finding | Source | Class | Disposition |
|---|---|---|---|---|
| 1 | `produced=11` unreachable in any passing state | architecture | mechanical | **Applied.** Corrected to `produced=10` at 6 sites; re-measured in a sandbox first. AC4's baseline column corrected too — the count alone cannot distinguish baseline from swapped, so AC4 leans on AC5/AC6 and T2–T5 |
| 2 | Ordering: waiver-swap checkpoint sequenced before the deletion reds the guard | architecture + spec-flow (+ independently by this plan) | mechanical | **Applied.** `### Ordering` now states the circularity, the atomic-commit requirement, and a 9-step execution order with Phase 3.7 after Phase 4 |
| 3 | AC10 contradicted CLO ruling F9 | spec-flow | mechanical | **Applied.** AC10 rewritten to require all four items inside the attestation |
| 4 | Phase 1 brief stale — never instructs the CLO to draft what Phases 2–3 expect | spec-flow | mechanical | **Applied** as Phase 1.1b |
| 5 | BLOCKED arm had no writer-path | spec-flow | mechanical | **Applied** as Phase 4b, including the `6 → 7` waiver arithmetic that arm implies |
| 6 | Terminal halt could leave a guard-failing tree; PR fate unstated | spec-flow | mechanical | **Applied** in Phase 1.5, plus Phase 1.6 for a returned-but-deficient artifact |
| 7 | AC15 had no owning step | spec-flow | mechanical | **Applied.** Phase 6 now has numbered sub-steps 6.1–6.4 |
| 8 | `--advisory` framing overstated the risk | cto | mechanical | **Applied.** The blocking net is the unit suite's `live corpus passes the guard` case; Phase 3.7 says so |
| 9 | 27 AC commands are a transcription hazard | cto | mechanical | **Applied.** One generated, uncommitted verification script |
| 10 | AC13, AC19 are ceremony | code-simplicity | mechanical | **Applied.** Both cut; numbering gaps kept because AC ids are cited from `## Domain Review` |
| 11 | Sharp Edges restated material stated at length elsewhere | dhh | mechanical | **Applied.** Trimmed from five entries to two |
| 12 | `#7787` cited imprecisely for producer semantics | architecture | mechanical | **Applied**, and replaced with ADR-200's stronger ground — a producer-skipped discriminator is a *silent* exclusion, which ADR-200 forbids |
| 13 | Guard Contract's M5/M6/H1/H2 are generic robustness padding | code-simplicity | mechanical | **DECLINED — verified against the gate.** `plan/SKILL.md` §2.12 *mandates* a row targeting the guard's own dispatch (M5), a second-member row (M6), and harness rows (H1/H2). Cutting them fails `lint-guard-contract.py`. The rows are analysis, not code: nothing is built |
| 14 | Guard Contract + Observability are template ceremony; cut to one line each | dhh | taste | **DECLINED with reason.** Both are gate-governed and mechanically linted; a one-line Observability block fails deepen-plan Phase 4.7. DHH is right that they are heavy for a data change, and the plan now says so where each begins |
| 15 | Phase 3.6 (counsel-review re-issue) is unbacked by the Property List | code-simplicity | taste | **KEPT — the two simplification reviewers disagree.** DHH called it "earned, and cheap… the one piece of growth genuinely proportionate". Recorded below as PR-8 rather than pretending it fitted an existing property |
| 16 | Two of the five stale sites are opportunistic, not fork-determining | code-simplicity | mechanical | **Applied** as a labelling change in Phase 3.3 — see the load-bearing/locality split there |
| 17 | 2026-08-06 verdict should be deferred, not merge-blocking | dhh | user-challenge | **KEPT, with the distinction stated.** That file is an **indexed row of the register being attested**, so a verdict on it is inside the attestation's own subject. C1's figures (deferred at AC26) reach ADR-200 and the Art. 30 register — artifacts *outside* the subject. That is the principled line DHH correctly observed was missing |
| 18 | Lift the CLO invocation protocol into `clo.md`; add an `hr-` rule | cto | taste | **Split.** The `hr-` rule is **blocked at cap** — measured: `lint-agents-rule-budget.py` reports `B_ALWAYS=46000` against the 46000-byte ratchet, so no new rule can land without retiring one. The `clo.md` lift is a plugin agent-definition change outside this issue's subject → follow-up |
| 19 | `scripts/add-legal-waiver.sh` preventive control | cto, endorsed by architecture | taste | **Follow-up.** Both reviewers independently proposed it; architecture confirmed it does not graze ADR-200 or #7787. Converts assertion (d) from detection to prevention |
| 20 | `ship/SKILL.md`'s Counsel-Review gate never tells itself to waive the file it writes | architecture | taste | **Follow-up.** Fails closed today (the required `test` check blocks), so it is an operational gap, not a corruption risk |

| 21 | R-e/AC26 asserted four stale `102` sites; only three are stale — Art. 30 item 12 already reads `104`, and the CLO's own C1 sentence was false when written | kieran | mechanical | **Applied.** Corrected at R-e, AC26 and the Alternative Approaches row. AC26's grep also rewritten: the old `\b102\b` over `article-30-register.md` returned `migration 102`/`ADR-102` and missed the datum. The attestation records the C1 mis-statement rather than editing that signed row (F7) |
| 22 | AC24 and AC26's second conjuncts named no command | kieran | mechanical | **Applied.** AC24 now carries three literal greps; AC26's deferred-branch requires an issue number, so "deferred" alone no longer satisfies it |
| 23 | AC10's baseline said 4 files; `origin/main` carries 3 | kieran | mechanical | **Applied.** The 4th was this plan's own untracked prose — the same count-includes-my-own-diff mechanism as R-e |
| 24 | Two dangling `AC19` references after the cut | kieran | mechanical | **Applied** — both now read AC6 |
| 25 | Phase 1.3 still pointed at "Phase 4" for authorship | spec-flow | mechanical | **Applied** — now Phase 3.8 |
| 26 | Pass-2 outage is a worse failure mode than pass-1 and was not distinguished | spec-flow | mechanical | **Applied** as Phase 3.9. The ordering already avoids the irreversible window; 3.9 states why and gives the stop-before-3.1 protocol |
| 27 | AC26 had no owning phase | spec-flow | mechanical | **Applied** — Phase 5.2 files the deferral issue and records its number |
| 28 | Risks table still said "Phases 3–5 do not run" | spec-flow | mechanical | **Applied** |

### PR-8 — the property Phase 3.6 satisfies

The Property List was written at Phase 0.6b, before domain review, so it could not contain the
properties domain review discovered. Rather than retrofit Phase 3.6 into an existing property or cut
a defect the CLO ruled real, the honest move is to name it:

> **PR-8.** No CLO instrument in the corpus contradicts another about the same artifact set.

A `BLOCKED` counsel review standing over a remediated set, beside a `DISCHARGED` attestation of that
same set, is the two-records-disagree defect this register exists to close — PR-4 generalised from
*records of one event* to *rulings about one artifact set*.

### Follow-ups to file in the work phase

| # | Item | Ground |
|---|---|---|
| F-1 | `scripts/add-legal-waiver.sh` — write both waiver copies atomically | Decisions 19; prevention over detection |
| F-2 | Lift the CLO invocation protocol into `plugins/soleur/agents/legal/clo.md` Sharp Edges | Decision 18; the third attestation should not re-derive it |
| F-3 | `ship/SKILL.md` Counsel-Review gate: waive the audit it writes | Decision 20 |
| F-4 | C1's corrected figures at the **three** stale sites (register §Inclusion predicate, ADR-200, guard header) — Art. 30 item 12 already reads `104` | AC26; deferred by ruling, needs the tracking issue. Phase 5.2 files it |
