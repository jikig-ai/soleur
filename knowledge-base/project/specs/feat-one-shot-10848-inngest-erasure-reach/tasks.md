# Tasks — feat-one-shot-10848-inngest-erasure-reach

Derived from `knowledge-base/project/plans/2026-11-02-compliance-inngest-erasure-reach-plan.md`.
Issue #10848 — the compliance half (Art. 15/17 reach of the Inngest Postgres
run-history store + the five PA (f) / §2.3(o) amendments).

## Phase 0 — Re-verify premises

- [ ] 0.1 `git fetch origin main`; re-grep the clause census
  (`git grep -n 'is not account deletion and is not a response'` on the
  register, the three canonical docs, the three mirrors,
  `compliance-posture.md`) and re-read each target line on the current tree.
- [ ] 0.2 Re-run the collision re-probe over the planned paths.
- [ ] 0.3 Verify whether a post-2026-10-28 `apply_target=inngest-host-replace`
  dispatch has run (`gh run list --workflow apply-web-platform-infra.yml`);
  record the live-pruning premise for the ruling brief. If unobtainable, the
  conditional clause stays.

## Phase 1 — CLO ruling (the determination)

- [ ] 1.1 Spawn `soleur:legal:clo` (`run_subagent` / `subagent_explore`,
  definition `plugins/soleur/agents/legal/clo.md`) with the plan's evidence
  pack + disqualifying-facts brief; instruction: "do NOT use
  AskUserQuestion". Required answers: (a) Art. 17 disposition + branch
  B1–B4; (b) Art. 15 disposition; (c) exact clause text per surface.
- [ ] 1.2 Record `Ruled by CLO agent, <date>: <decision> - <rationale>` in
  `decision-challenges.md` and in the counsel-review audit file.

## Phase 2 — Register (f) cell amendments

- [ ] 2.1 Append the dated determination marker per ruling to the six
  clause-bearing cells (PA-13, PA-21, PA-22, PA-27 ×2, PA-31) and the
  PA-14 (f) sibling, in `knowledge-base/legal/article-30-register.md`.

## Phase 3 — Published-doc amendments (canonical + mirror)

- [ ] 3.1 Extend the clause per ruling at DPD §2.3(o) + §2.3(aa),
  privacy-policy recipients bullet, gdpr-policy bullet — byte-identical on
  canonical + mirror (8 positions).
- [ ] 3.2 Move `Last Updated` on all three docs (canonical `**Last
  Updated:**` + mirror hero `<p>…Last Updated…</p>`) with the house-form
  amendment note.
- [ ] 3.3 Falsified-negatives sweep: grep the legal corpus for paraphrases
  of the undetermined state and amend every hit the ruling falsifies.

## Phase 4 — Posture item + SHA re-pin

- [ ] 4.1 Update the `compliance-posture.md` #10848 open item to the
  determined state.
- [ ] 4.2 `sha256sum` the three edited canonical docs → update
  `apps/web-platform/lib/legal/legal-doc-shas.ts` in the same commit.

## Phase 5 — Conditional implementation (ruling-gated)

- [ ] 5.1 Only if the ruling selects branch ≠ B4: emit the branch's IaC /
  ADR + C4 / observability / encryption-posture / task-design deliverables
  BEFORE any code, then implement; the identifier census is derived from a
  full `git grep` of every `inngest.send` call site, tested per site.

## Phase 6 — Gate suite + counsel-review attestation

- [ ] 6.1 Run the five legal-corpus gates:
  `scripts/lint-legal-scope-block-placement.sh --base origin/main`,
  `scripts/lint-legal-mirror-drift-baseline.sh --base origin/main`,
  `apps/web-platform/scripts/check-tc-document-sha.sh`,
  `apps/web-platform/test/legal-doc-consistency.test.ts` +
  `legal-doc-shas-guard.test.ts`, `scripts/probe-legal-corpus-truth.sh`;
  plus the affected-suites runner.
- [ ] 6.2 Produce `knowledge-base/legal/audits/2026-11-counsel-review-10848.md`
  (house shape; `disposition: DISCHARGED` or halt on the named blocker);
  waiver row in `scripts/lint-legal-registers.sh` only if it trips the
  producer pattern.

## Acceptance

- [ ] AC1–AC11 in the plan file all verified.
