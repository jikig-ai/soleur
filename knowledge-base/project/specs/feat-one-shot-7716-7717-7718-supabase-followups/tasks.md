---
title: "Tasks — W6, the Art. 33(5) breach register (#7717)"
branch: feat-one-shot-7716-7717-7718-supabase-followups
plan: knowledge-base/project/plans/2026-09-03-chore-supabase-followups-art30-register-orphan-linter-plan.md
lane: cross-domain
date: 2026-09-03
scope: w6-statutory-only
---

# Tasks

Derived from the plan after a seven-agent review panel. Every phase number here matches the
plan's; where the plan records that an earlier draft was cut or corrected, that history is in the
plan and not repeated.

**Scope (DC-1 resolved: split).** This branch ships **W6 only** — the statutory workstream for
#7717. Phases 2–6 (W7/W1/W3/W4/W5, for #7716 + #7718 + #6489) are carried to a follow-on PR
against the same plan; their task list is preserved verbatim in
**§Deferred to the follow-on PR** at the end of this file — not behind a branch SHA, because
`ship` squash-merges and no per-commit SHA survives in `main`. See the plan's §Scope table for phase ownership. Do **not** implement Phases 2–6 here.

## Phase 0 — Preconditions (verify, never assume)

Only the legal-side preconditions run on this branch. 0.1–0.4, 0.7 and 0.9 are engineering
preconditions for W1/W7/W3 and move to the follow-on with their phases.

- [x] 0.3 Re-derive the next free ADR ordinal across every `origin/*` ref, not `origin/main`. This branch takes **one** ordinal (ADR-200, the register's maintaining surface); the ADR-139 amendment belongs to the follow-on and takes none.
- [x] 0.5 Confirm no `docs/legal/**` path is in the working set, so the three-way legal-doc lockstep does not fire.
- [x] 0.6 `bash scripts/check-pa-22.sh` passes before it is wired. Wiring a red sentinel and a green one are different changes.
- [x] 0.8 Re-derive the PA ordinal by enumerating `^## Processing Activity` headings — the headings are out of numeric order, so reading the last one is wrong.
- [x] 0.10 **Split-specific.** Re-read `knowledge-base/legal/article-30-register.md` against #7670's current head before editing: #7670 is concurrently editing PA-7/PA-1 under the same additive-only contract. Record which PA blocks it touches; if it has merged since planning, rebase and re-derive 0.8.

## Phase 1 — W6, the statutory workstream

- [x] 1.1 Create `knowledge-base/legal/breach-register.md` with `article-30-2-register.md`-shaped frontmatter; scope paragraph disclaims the #3686 collision.
- [x] 1.2 Write the inclusion predicate in prose, excluding PIR `art_33_triggered` screening outputs.
- [x] 1.3 Write the dated provenance preamble — Art. 5(2) framing only, not escalated.
- [x] 1.4 Index the seven determinations (six under `audits/`, one post-mortem). Pin the machine-readable form of the canonical-source column. Grep-validate every cell against its source.
- [x] 1.5 Write the 2026-06-29 row with the coverage correction inline; transcribe no fence.
- [x] 1.6 Append the second annotation-only addendum to the canonical record (naming `auth_logs` and the never-queried `postgrest_logs`); add a one-line pointer from each of the two siblings.
- [x] 1.7 Close all three pointer legs — the audit, `article-30-register.md` §Register Maintenance, and `statutory-response-catalog.md` (accountability-pack step + `related:` frontmatter).
- [x] 1.8 Resolve five `__TBD_*` occurrences: two `NOT RECORDED`, two `NOT EXECUTED` (dropping "signed" in both places), one cross-reference. Also fix `recover-userid-from-pino-stdout.md`.
- [x] 1.9 Narrow the stale AC15 directive in `compliance-posture.md` (#7529 **is** filed); add the register to its pointer list and an Active Compliance Items row.
- [x] 1.10 Add the two PA-8 entries the CLO ruled in place of a retention measure — the Art. 33 evidentiary-chain limitation in §(g), and the durable-sink item citing #5697.
- [x] 1.11 State the non-scope in the register itself, with both evidence citations.
- [x] 1.12 Bump `last_reviewed:`; add counsel-review item 12.
- [ ] 1.13 Write the CLO attestation at `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md`.

## Phase 7 — Register gate and ADR (W6 slice only)

- [x] 7.1 Build `scripts/lint-legal-registers.sh` + `.test.sh`: token class scoped to the register files with a citing waiver and an inline-code exemption; the accepted-resolution shape in the **failure message**; reuse `tenant-dpa-register-guard.sh` for row counting; canonical-source paths resolve; declared-set integrity with the pinned `4\(12\)|33\(5\)|Art\. 33` producer over `audits/**`, `post-mortems/**` excluded with its reason inline. Land advisory for one cycle.
- [x] 7.1a Correct PA-31 §(g) measure 10 and the 2026-07-31 DPIA memo, whose "wired into no workflow" evidence command would stay true while its claim became false.
- [x] 7.1b Name the register's maintaining surface in ADR-200; update `register-update-pr-pattern.md`.
- [x] 7.2 Register three `run_suite` lines (`check-pa-22.sh`, `lint-legal-registers.sh`, `lint-legal-registers.test.sh`); mutation-test all three — for `check-pa-22.sh` the mutation moves the TOMs row outside the PA-22 block. **Split coupling:** Phase 2.6's `REQUIRED_RUNNERS` floor bump does not run on this branch, so verify these three registrations do not depend on it; if they do, carry the minimal floor change here and say so in the commit.
- [x] 7.3 Write ADR-200. The **ADR-139 amendment is out of scope on this branch** — it documents W1's promotion route and ships with the follow-on.
- [x] 7.4 W6 slice only: add `action-required` to #7529. File any legal-subject issues from the plan's Phase 7 list; engineering-subject filings, the plan-SKILL §2.6 inversion fix, and the #7125 re-milestone move to the follow-on.

## Phase 8 — Verification

- [x] 8.1 Work through §Acceptance Criteria **§Pre-merge — W6 (statutory)** in order. The engineering AC block is not asserted on this branch.
- [ ] 8.2 Re-run `/soleur:gdpr-gate` at the work Phase 2 exit.
- [ ] 8.3 Full battery `bash scripts/test-all.sh` at the `/ship` Phase 4 checkpoint.
- [x] 8.4 Re-derive the ADR ordinal against a fresh fetch immediately before merge; sweep plan, tasks and ACs if it moved.
- [x] 8.5 **Split-specific.** Confirm the merged diff touches no W1/W7/W3/W4/W5 file — `git diff origin/main...HEAD --name-only` must not list `scripts/lint-orphan-test-suites.sh`, `scripts/lint-supabase-deprecated-endpoints.sh`, `scripts/test-all.sh` W7/W1 rows, `.github/workflows/ci.yml`, the C4 model, or `plugins/soleur/skills/incident/**`.

---

## Deferred to the follow-on PR (#7716 + #7718 + #6489)

**Not in scope for this PR.** Preserved here verbatim from the pre-split task list so the
follow-on is self-serve: the plan document these derive from merges with this PR and remains the
single source for their design (see its §Scope table for phase ownership). Do not implement
these on this branch — Phase 8.5 asserts the diff touches none of their files.

The engineering preconditions from Phase 0 travel with them: 0.1 (re-derive the ADR-139
intersection), 0.2 (`lint-supabase-deprecated-endpoints.sh` + `--check-highwater` both exit 0),
0.4 (re-run the four orphan probes), 0.7 (`SUPABASE_ACCESS_TOKEN` present and scoped in **both**
Doppler configs), 0.9 (probe the guard's ALLOWLIST for entries matching no file).

Two items this PR discovered that the follow-on must carry:

- **`gate-g-escalate-evidence.md` asserts the deprecated-endpoint guard "is advisory only — not
  merge-blocking".** True while W6 ships alone; FALSE the moment W1 lands. Grep
  `git grep -n 'advisory only' -- knowledge-base/` before closing W1.
- **ADR-139's amendment is W1's, not W6's.** ADR-200 shipped here and deliberately does not
  carry the aggregator-union invariant; that belongs with the promotion route.

## Phase 2 — W7, orphan-suite linter (RED first; already merge-blocking)

- [ ] 2.1 Write the failing rows in `scripts/lint-orphan-test-suites.test.sh` from Guard 3's matrix, before touching the linter.
- [ ] 2.2 Clone the `tests/commands/` loop twice — `tests/scripts/test-*.sh` and `tests/hooks/test_*.sh` — non-recursive globs, `git ls-files`-sourced.
- [ ] 2.3 Give each loop the existing cardinality floor.
- [ ] 2.4 Fix the three self-contradictions: the trailing `MIN_SUITES` claim, the stale `45` (actual 53), the "fails on any SIXTH" comment.
- [ ] 2.5 Register the four orphans — read each first; a red one is fixed or excluded with a citing issue, never left unregistered.
- [ ] 2.6 Add the three new live gates to `REQUIRED_RUNNERS` and bump its floor.
- [ ] 2.7 Remove the duplicate advisory `lint-orphan-test-suites` step from `ci.yml`, and re-scope the comment above it to the tempfile steps only.

## Phase 3 — W1, the promotion

- [ ] 3.1 Add one `-live` `run_suite` line; rewrite the comment block that explains why there was none.
- [ ] 3.2 Remove the two Supabase steps from `lint-bot-statuses`; correct the job's comments.
- [ ] 3.3 Rewrite the guard's `ENFORCEMENT LEVEL: ADVISORY` header to state the blocking level, name the context it rides, and carry the ADR-139 derivation.
- [ ] 3.4 Add Test 9 to `plugins/soleur/test/required-checks-canonical-parity.test.sh` — the union intersection, read through a new `--print-pathspec` accessor, never parsed.
- [ ] 3.6 Amend ADR-197's promotion paragraph: it names four requirements, of which this plan performs the fourth; supersede three and retain that one explicitly.

## Phase 4 — W3, credential unification

- [ ] 4.1 Migrate `postgrest-reload-schema.sh` and its `.test.sh` to `SUPABASE_ACCESS_TOKEN`; update `run-migrations.sh` and `migration-rollback.md`.
- [ ] 4.2 Keep `SUPABASE_PAT` in the guard's arm-2 regex.
- [ ] 4.3 Preserve `run-migrations.sh`'s assembly membership via the renamed comment; update its ALLOWLIST reason string.
- [ ] 4.4 Re-run `--census` (expect 26) and the 30-file union. A move takes the highwater with it, in the same commit, with the reason.
- [ ] 4.5 No-op — the Doppler deletion is post-merge, at AC36.

## Phase 5 — W4, the C4 element

- [ ] 5.1 Add `supabaseMgmtApi` as a top-level `#external` `system`, distinct from the in-boundary `platform.infra.supabase` data plane.
- [ ] 5.2 Add the edges for the CI and Inngest callers.
- [ ] 5.3 Add it to the include lists of the two views it renders in; confirm both endpoints of every edge are in the same list.
- [ ] 5.4 Keep numbers out of the edge descriptions.
- [ ] 5.5 `bash scripts/regenerate-c4-model.sh`; commit `model.likec4.json`; refresh `c4-model.md` if it changes.

## Phase 6 — W5, the `triggers:` shape and three defect fixes

- [ ] 6.1 Pin all four emitted shapes, or fix `templates/pir.md` + `scripts/dry-run.sh` to always emit `triggers: []` and pin two. Either way both emitter files are edited.
- [ ] 6.2 Correct the PIR claim against the measured 102 of 113.
- [ ] 6.3 Widen Phase 3's scan to `knowledge-base/legal/runbooks/`, add a curated `triggers:` block to the one runbook there, and widen `dry-run.sh`'s hard-coded directory.
- [ ] 6.4 Define the no-scoring-match branch, the index-`0` offer, and top-3 with fewer than three matches.
- [ ] 6.5 Reconcile the three `triggers` vocabularies so the secret-leak preamble is reachable from Phase-3 routing.
- [ ] 6.6 Point `/soleur:incident` at `breach-register.md` for the `art_33_triggered: true` case.
- [ ] 6.7 Update the census figures.
