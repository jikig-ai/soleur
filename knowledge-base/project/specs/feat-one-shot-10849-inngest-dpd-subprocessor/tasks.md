# Tasks — feat-one-shot-10849-inngest-dpd-subprocessor

Plan: `knowledge-base/project/plans/2026-10-27-legal-inngest-subprocessor-correction-plan.md` (issue #10849)

## Phase 0 — Re-verify

- [ ] 0.1 Re-fetch origin/main; re-run open-PR re-probe over the 8 planned file paths.
- [ ] 0.2 Re-read each target line on the current tree (amendment chains shift).

## Phase 1 — DPD §2.3(o) (canonical + mirror, byte-identical)

- [ ] 1.1 Replace `self-hosted Inngest OSS on Hetzner, eu-central, no external sub-processor` with the CLO-prescribed clause + `*(corrected October 27, 2026, ref #10849: an earlier version stated 'no external sub-processor')*` in `docs/legal/data-protection-disclosure.md`.
- [ ] 1.2 Same edit in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.

## Phase 2 — privacy-policy §4.13 (canonical + mirror)

- [ ] 2.1 Replace the "self-hosted, operator-managed event store on EU infrastructure" phrase + correction note in `docs/legal/privacy-policy.md`.
- [ ] 2.2 Same in `plugins/soleur/docs/pages/legal/privacy-policy.md`.

## Phase 3 — gdpr-policy recipients bullet (canonical + mirror)

- [ ] 3.1 Replace "persist in the self-hosted Inngest event store" phrasing + correction note in `docs/legal/gdpr-policy.md`.
- [ ] 3.2 Same in `plugins/soleur/docs/pages/legal/gdpr-policy.md`.

## Phase 4 — DPD §4.2 Supabase row (canonical + mirror)

- [ ] 4.1 Extend Supabase row's Processing-Activity + Data-Processed cells with the run-history/event category in both surfaces.

## Phase 5 — DPD §2.3(aa) (canonical + mirror)

- [ ] 5.1 Replace "self-hosted, operator-managed Inngest event store … not a third-party recipient" phrasing + correction note in both surfaces.

## Phase 6 — Last Updated chains

- [ ] 6.1 Prepend `October 27, 2026` + amendment note to each canonical `**Last Updated:**` line (3 docs); demote October 26 to `Previous:`.
- [ ] 6.2 Same on the three mirror body lines + bump each mirror hero `<p>…| Last Updated October 27, 2026</p>`.

## Phase 7 — SHA re-pin

- [ ] 7.1 `sha256sum` the three canonical docs; update `apps/web-platform/lib/legal/legal-doc-shas.ts`.

## Phase 8 — Gates

- [ ] 8.1 `lint-legal-scope-block-placement.sh --base origin/main` → 0.
- [ ] 8.2 `lint-legal-mirror-drift-baseline.sh --base origin/main` → 0, no drift at touched positions.
- [ ] 8.3 `apps/web-platform/scripts/check-tc-document-sha.sh` → 0.
- [ ] 8.4 `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` → green.
- [ ] 8.5 `probe-legal-corpus-truth.sh` → 0.
- [ ] 8.6 Correction-note-stripped absence greps (AC1/AC3) → 0.

## Phase 9 — Counsel-review attestation

- [ ] 9.1 Write `knowledge-base/legal/audits/2026-10-counsel-review-10849.md` (per-artifact verdicts, DISCHARGED/BLOCKED, re_evaluation_triggers).
- [ ] 9.2 Conditional: `lint-legal-registers.sh` waiver row iff the audit trips the Art. 33 producer pattern.
- [ ] 9.3 Emit the one-line COUNSEL-REVIEW veto notice; commit all.
