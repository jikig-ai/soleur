---
title: "Tasks — drain #7716, #7717, #7718"
branch: feat-one-shot-7716-7717-7718-supabase-followups
plan: knowledge-base/project/plans/2026-09-03-chore-supabase-followups-art30-register-orphan-linter-plan.md
lane: cross-domain
date: 2026-09-03
---

# Tasks

Derived from the plan after a seven-agent review panel. Every phase number here matches the
plan's; where the plan records that an earlier draft was cut or corrected, that history is in the
plan and not repeated.

## Phase 0 — Preconditions (verify, never assume)

- [ ] 0.1 Re-derive the ADR-139 intersection with the two commands in §Research Insights; paste the output into the PR body. If a `knowledge-base/` path has entered either assembly, W1's disposition changes from unreachability to earned-green.
- [ ] 0.2 `bash scripts/lint-supabase-deprecated-endpoints.sh` exits 0 on a clean tree. A red here adds a backlog-drain phase before the promotion.
- [ ] 0.3 Re-derive the next free ADR ordinal across every `origin/*` ref, not `origin/main`. One ordinal only — the promotion decision amends ADR-139 in place.
- [ ] 0.4 Re-run the four orphan probes; a sibling PR may have registered one.
- [ ] 0.5 Confirm no `docs/legal/**` path is in the working set, so the three-way legal-doc lockstep does not fire.
- [ ] 0.6 `bash scripts/check-pa-22.sh` passes before it is wired. Wiring a red sentinel and a green one are different changes.
- [ ] 0.7 Confirm `SUPABASE_ACCESS_TOKEN` is present, authenticating, and record its account scope in **both** Doppler configs `postgrest-reload-schema.sh` runs under. Per-project, not once.
- [ ] 0.8 Re-derive the PA ordinal by enumerating `^## Processing Activity` headings — the headings are out of numeric order, so reading the last one is wrong.
- [ ] 0.9 Probe the deprecated-endpoint guard's ALLOWLIST for entries matching no file, so Phase 4.3's claim that none exists is measured rather than asserted.

## Phase 1 — W6, the statutory workstream (first, its own commit)

- [ ] 1.1 Create `knowledge-base/legal/breach-register.md` with `article-30-2-register.md`-shaped frontmatter; scope paragraph disclaims the #3686 collision.
- [ ] 1.2 Write the inclusion predicate in prose, excluding PIR `art_33_triggered` screening outputs.
- [ ] 1.3 Write the dated provenance preamble — Art. 5(2) framing only, not escalated.
- [ ] 1.4 Index the seven determinations (six under `audits/`, one post-mortem). Pin the machine-readable form of the canonical-source column. Grep-validate every cell against its source.
- [ ] 1.5 Write the 2026-06-29 row with the coverage correction inline; transcribe no fence.
- [ ] 1.6 Append the second annotation-only addendum to the canonical record (naming `auth_logs` and the never-queried `postgrest_logs`); add a one-line pointer from each of the two siblings.
- [ ] 1.7 Close all three pointer legs — the audit, `article-30-register.md` §Register Maintenance, and `statutory-response-catalog.md` (accountability-pack step + `related:` frontmatter).
- [ ] 1.8 Resolve five `__TBD_*` occurrences: two `NOT RECORDED`, two `NOT EXECUTED` (dropping "signed" in both places), one cross-reference. Also fix `recover-userid-from-pino-stdout.md`.
- [ ] 1.9 Narrow the stale AC15 directive in `compliance-posture.md` (#7529 **is** filed); add the register to its pointer list and an Active Compliance Items row.
- [ ] 1.10 Add the two PA-8 entries the CLO ruled in place of a retention measure — the Art. 33 evidentiary-chain limitation in §(g), and the durable-sink item citing #5697.
- [ ] 1.11 State the non-scope in the register itself, with both evidence citations.
- [ ] 1.12 Bump `last_reviewed:`; add counsel-review item 12.
- [ ] 1.13 Write the CLO attestation at `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md`.

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

## Phase 7 — Register gate, ADR, issues

- [ ] 7.1 Build `scripts/lint-legal-registers.sh` + `.test.sh`: token class scoped to the register files with a citing waiver and an inline-code exemption; the accepted-resolution shape in the **failure message**; reuse `tenant-dpa-register-guard.sh` for row counting; canonical-source paths resolve; declared-set integrity with the pinned `4\(12\)|33\(5\)|Art\. 33` producer over `audits/**`, `post-mortems/**` excluded with its reason inline. Land advisory for one cycle.
- [ ] 7.1a Correct PA-31 §(g) measure 10 and the 2026-07-31 DPIA memo, whose "wired into no workflow" evidence command would stay true while its claim became false.
- [ ] 7.1b Name the register's maintaining surface in ADR-200; update `register-update-pr-pattern.md`.
- [ ] 7.2 Register three `run_suite` lines (the two scripts plus the `.test.sh`); mutation-test all three — for `check-pa-22.sh` the mutation moves the TOMs row outside the PA-22 block.
- [ ] 7.3 Write ADR-200; write the ADR-139 amendment carrying the aggregator-union invariant, the compensating control, and the un-un-requirable-`test` consequence.
- [ ] 7.4 File three issues (none `action-required`); fix the plan-SKILL §2.6 inversion inline; execute the #7125 re-milestone and add `action-required` to #7529.

## Phase 8 — Verification

- [ ] 8.1 Work through §Acceptance Criteria AC1–AC36 in order.
- [ ] 8.2 Re-run `/soleur:gdpr-gate` at the work Phase 2 exit.
- [ ] 8.3 Full battery `bash scripts/test-all.sh` at the `/ship` Phase 4 checkpoint.
- [ ] 8.4 Re-derive the ADR ordinal against a fresh fetch immediately before merge; sweep plan, tasks and ACs if it moved.
