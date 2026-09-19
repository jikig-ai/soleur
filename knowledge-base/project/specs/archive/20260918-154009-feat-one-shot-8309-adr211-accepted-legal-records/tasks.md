# Tasks: docs(7960) — flip ADR-211 to accepted and date the legal records

Plan: `knowledge-base/project/plans/2026-09-18-docs-flip-adr-211-accepted-date-legal-records-plan.md`.
Docs and model files only. Every append cites the probe by script name
(`scripts/followthroughs/zot-last-err-redact-7500.sh`), never by line number. Frontmatter fields
are changed in-cell; body sentences are never edited — a dated marker goes under them.

## Phase 1: ADR-211

- [x] 1.1 Frontmatter `status: adopting` → `status: accepted`; add `8309` and `8272` to `related_issues:`.
- [x] 1.2 Append the `**[Accepted 2026-09-18 (#8309): …]**` bracket to the Status bullet (after `See "Delivery proof" under Decision.]**`).
- [x] 1.3 Append the one-line `> **Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS):** …` pointer blockquote under the existing `> **Superseded 2026-09-18 (#7960)**` note (second replace, run 35353167115, boot `3b70b6ae…`; 09-17 boot stays corroboration).
- [x] 1.4 Append `## Amendment 2026-09-18 — first PASS observed (status ACCEPTED)` at the end, quoting the sweeper run in a fenced `text` block; "delivered per this ADR's own proof key … tier-4 gate graded clean — 3 rows in 24h, 0 leaking"; never "PROVEN"; evidence pointer (#7960 comment `5731215695`) and the list of retracted sites.
- [x] 1.5 Append the `**[Fired: 2026-09-17 … and 2026-09-18 …]**` bracket to the Consequences bullet `Primary re-evaluation trigger: the next registry-host-replace` (not the `Superseded … (#8309 trigger` literal).

## Phase 2: Article 30 register (five in-cell entries)

- [x] 2.1 PA-8 §(c): append the canonical `**[Superseded 2026-09-18 (#8309 trigger — Phase B follow-through PASS): …]**` entry with the §(c) clause.
- [x] 2.2 PA-8 §(d): append with the §(d) clause (sink denylist is the backstop, no longer the only control).
- [x] 2.3 PA-8 §(g): ONE entry at the cell's end with the §(g) clause (Layer 2 backstop; discharges the "until a dated delivery entry is appended" condition).
- [x] 2.4 Vendor Mapping — Better Stack s.r.o. row: append with the retention clause (cite #7772).
- [x] 2.5 Vendor Mapping — GitHub Inc row: append with the §(c)-style clause.
- [x] 2.6 Confirm no table row was added (`grep -c '^|'` unchanged vs `origin/main`) and no standalone `TBD`/`TODO`/`XXX`/`FIXME` token.

## Phase 3: CLO attestation

- [x] 3.1 Frontmatter in-cell: `open_limbs:` → the CLO-ruled "ONE, NARROWED 2026-09-18 (#8309) …" value; `art_33_deadline:` → "on the still-open half of the limb below (narrowed 2026-09-18, #8309)"; `disposition:` → wrap in double quotes and append the NARROWED clause (colon-free). No `amended:` key. Frontmatter must still parse (`yaml.safe_load`).
- [x] 3.2 Append the `> **Narrowed 2026-09-18 (#8309 trigger — Phase B follow-through PASS): the limb is closed IN PART, not in full.**` blockquote under §"The open evidentiary limb" (verbatim from the plan: script name, 14:10:58Z, boot, run, counts; the pre-delivery corpus bounded by boot `3b70b6ae…` with the 09-17 boot as corroboration; 1,792/2,598; 90-day `logs_retention` of source `2457081`, age-out 2026-09-18 + 90d ≈ 2026-12-17).
- [x] 3.3 Append the `> **Superseded 2026-09-18 (#8309 trigger …)**` blockquote under §"What I am explicitly NOT attesting to" item 4.
- [x] 3.4 Append the `> **Superseded 2026-09-18 (#8309 trigger …)**` blockquote under Finding 1's sentence `one of which is inert. See Finding 3.`
- [x] 3.5 Append the `> **Superseded 2026-09-18 (#8309 trigger …)**` blockquote under §"Re-evaluation triggers" bullet 3 (`and Layer 1 is inert.`).
- [x] 3.6 Append the `> **Superseded 2026-09-18 (#8309 trigger …)**` blockquote under §"Re-evaluation triggers" bullet 2 (`A registry-host-replace firing`).
- [x] 3.7 Rendering: indent each blockquote to its list item (3 spaces under numbered items, 2 under bullets), blank line before; keep the bold heading literal on one line; the `Superseded 2026-09-18 (#8309 trigger` literal appears exactly 4 times in the body.

## Phase 4: C4 model

- [x] 4.1 `model.c4` `github -> publicReader` edge: replace `(ADR-211 Layer 1 — INERT until the next registry-host-replace, so this edge is currently guarded by the denylist alone)` with `(ADR-211 Layer 1 — DELIVERED 2026-09-18, see its Amendment 2026-09-18; the denylist here is the backstop, not the only guard)`.
- [x] 4.2 `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json`.

## Phase 5: Verification

- [x] 5.1 Run Acceptance Criteria 1–11 from the plan; all hold.
- [x] 5.2 `bash scripts/lint-legal-registers.sh`, `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, `bash plugins/soleur/test/c4-model-freshness.test.sh` all exit 0.
- [x] 5.3 Diff scope: only the eight paths in §Files to Edit plus the plan, this `tasks.md`, and `session-state.md`; nothing under `apps/`, `scripts/`, `plugins/`, `.github/`.
