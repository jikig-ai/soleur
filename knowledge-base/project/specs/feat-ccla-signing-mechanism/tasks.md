---
title: "Tasks — Corporate CLA signing mechanism"
date: 2026-09-04
type: tasks
lane: cross-domain
branch: feat-ccla-signing-mechanism
issue: 3210
plan: knowledge-base/project/plans/2026-09-04-feat-ccla-signing-mechanism-plan.md
---

# Tasks — Corporate CLA signing mechanism

Derived from the finalized (post-review) plan. Two scope decisions were taken by the operator at
plan review and are reflected throughout: the `cla-evidence.yml` roster-verification step is
**deferred** to the R2 PR, and the operator affordance is a **script, not a skill**.

## Phase 0 — Preconditions

- [x] 0.1. Record the Art. 6(1)(f) balancing test for the employer↔account association in
      `docs/legal/gdpr-policy.md` §3.4 (third balancing test) and in PA-7's Lawful basis row.
      **This is what gates the first roster row** (CLO ruling) — a documentation edit, in this PR.
- [x] 0.2. Write the CLO ruling to
      `knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`,
      with its external-counsel re-review triggers in frontmatter.
- [ ] 0.3. Re-derive the ADR ordinal across **all** `origin/*` refs (not `origin/main` — `main` max
      is ADR-198, all-refs max is ADR-200). Record the chosen ordinal as provisional.
- [x] 0.4. Establish and record the mail provider for `legal@jikigai.com` before any §0 sentence
      describes where the executed instrument is received. Do **not** assume by analogy with
      `ops@soleur.ai` — that is the reasoning class #7624 exists to correct.

## Phase 1 — Tier 0 (serve Convergence this week)

- [ ] 1.1. FR7 copy in `.github/workflows/cla.yml` `custom-notsigned-prcomment`: lead with the ICLA
      sign line; state the CCLA is the maintainer's to chase; name a turnaround.
- [ ] 1.2. Same three changes in `CONTRIBUTING.md`.
- [ ] 1.3. Add the in-flight state ("CCLA in progress — maintainer action, not yours") — the
      brainstorm's third minimum-fix item, dropped by the spec.
- [ ] 1.4. Reply to Convergence: request a named signatory with title and an individually-
      attributable mailbox, plus the §5 notice-delivery confirmation the ruling now requires.
- [ ] 1.5. Their contributor signs the ICLA through the ordinary path; the PR merges on its merits.
- [ ] 1.6. Countersign; compute and record the executed-instrument SHA-256 on receipt.
- [x] 1.7. Create `knowledge-base/legal/ccla-register.md` with the CLO's ruled field table and an
      empty Register table.
- [ ] 1.8. Add the first roster row — **only after 0.1 and only for an ICLA signer**.

## Phase 2 — Contracts, before any consumer

- [x] 2.1. Create `apps/web-platform/scripts/cla-evidence/cla-doc-path.ts` (the discriminant module).
- [x] 2.2. Extract pure `parseAllowlistLine(yml: string): string[] | null` into `allowlist.ts`;
      move the regex there. Keep `readFileSync` + `process.exit` in `build-bypass.ts`'s caller.
- [x] 2.3. Add `RosterSchema` (`.strict()`) + `validateRosterRecord()` to the existing `schema.ts`,
      reusing `Sha256Hex` and `SchemaVersionMismatchError`. `schema_version` is the **string**
      `"1.0"`.
- [x] 2.4. Write all three guard mutation matrices as failing tests **before** the guards exist.

## Phase 3 — Discriminant migration (six producer sites)

- [x] 3.1. `apps/web-platform/scripts/cla-backfill-evidence.ts:58` — **the sixth producer**.
- [x] 3.2. `apps/web-platform/scripts/cla-evidence/build-record.ts:98`.
- [x] 3.3. `apps/web-platform/scripts/cla-evidence/backfill.ts:55`.
- [x] 3.4. `.github/workflows/cla-evidence.yml` `:55`, `:128`, `:217`.
- [x] 3.5. Test fixtures: `schema.test.ts:20`, `hash.test.ts:3,8,11,17-18`.
- [x] 3.6. Leave `.github/workflows/cla.yml:45`/`:60` unchanged — correctly the ICLA.
- [x] 3.7. All of 3.1–3.5 in one commit.

## Phase 4 — Operator affordance (script)

- [ ] 4.1. `apps/cla-evidence/scripts/ccla-add.sh` — resolve logins → numeric ids; **refuse any id
      absent from `origin/cla-signatures:signatures/cla.json`**; validate against the schema; open a
      single-file PR. Support `CCLA_ADD_DRY_RUN=1`.
- [ ] 4.2. Collect the countersigning fields the schema requires — `signed_at`, CCLA `git_sha` +
      `content_sha256`, `executed_instrument_sha256`. Spec FR6's prompt set could not produce a
      schema-valid record.
- [ ] 4.3. Build the **remove** path too (withdrawal of designation). CCLA §5 makes removal an
      email; leaving it unbuilt makes withdrawing an ex-employee's authorization a hand-edit.
- [ ] 4.4. `apps/cla-evidence/scripts/ccla-add.test.sh` (collected by the existing
      `apps/cla-evidence/scripts/*.test.sh` glob).
- [ ] 4.5. Add a CCLA section to `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`.
- [x] 4.6. Declare the new repo-reading suites in `apps/web-platform/test/repo-wide-suites.ts`.

## Phase 5 — Corpus corrections

- [ ] 5.1. `docs/legal/corporate-cla.md` §0 (two-copies **and** erasure-procedure assertions), §5,
      §Signing — CLO's drafted replacements. Pair with mirror + `legal-doc-shas.ts` re-pin **in the
      same commit**.
- [ ] 5.2. `docs/legal/individual-cla.md` §1 (`:40`), §4(a) (`:60`), Art. 13 notice sentence —
      triple lockstep.
- [ ] 5.3. `privacy-policy.md` §4.5 (coverage map as a **distinct** disclosure) + §10 — triple lockstep.
- [ ] 5.4. `gdpr-policy.md` §3.4 (third balancing test — already landed at 0.1) + §6 — triple lockstep.
- [ ] 5.5. `data-protection-disclosure.md` §2.3(d) + §6.4 — triple lockstep.
- [ ] 5.6. `article-30-register.md` PA-7 §(c), §(d), §(e) **and the Lawful basis row**.
- [ ] 5.7. Rename `removed_at` from "tombstone" to *withdrawal-of-designation marker* everywhere.
- [ ] 5.8. Route the cross-document sweep through `legal-compliance-auditor`.
- [ ] 5.9. Do **not** enrol either CLA in `BODY_EQUIVALENCE_DOCS` — measured drift is non-zero.
- [ ] 5.10. Keep every `#NNNN` reference mid-line (markdownlint phantom-H1 trap).

## Phase 6 — ADR, C4, principle

- [ ] 6.1. Write ADR-201 scoped to: the CCLA record is a repo-tracked git artifact; not an allowlist
      entry and not a third required check; **fail-open** for additive evidence. Record the custody
      ruling (B1-c) and the two operator scope reversals.
- [ ] 6.2. `## Alternatives Considered` must include **"record the CCLA in the existing R2
      write-once store"** — the central alternative, absent from the first draft.
- [ ] 6.3. Re-derive the ordinal immediately before merge; if it moves, sweep plan + spec + tasks
      + ACs in the same edit.
- [ ] 6.4. C4: no change required under B1-c beyond an optional `contributor` description
      amendment. If any `.c4` edit lands, run `scripts/regenerate-c4-model.sh` and commit
      `model.likec4.json` in the same commit.
- [ ] 6.5. Propose a principles-register row for "additive evidence must not gate", citing #7597.

## Phase 7 — Verification

- [ ] 7.1. Run every AC in the plan's `## Acceptance Criteria`.
- [ ] 7.2. `bash scripts/test-all.sh` — the **full** battery, not touched-file shards.
- [ ] 7.3. Verify prose against code item by item (#7349 class): no `ccla/` write path;
      `ccla-add.sh` refuses un-signed ids; the custody location named in §0 is the one actually used.
- [ ] 7.4. File the `side-letter-register.md` legal-name-column issue, citing the B1 ruling as the
      fix pattern.
- [ ] 7.5. Extend #7668 with the CCLA-association retention sub-question.
