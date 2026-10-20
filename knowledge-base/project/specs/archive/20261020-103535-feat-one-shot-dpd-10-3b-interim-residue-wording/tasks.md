# Tasks - feat-one-shot-dpd-10-3b-interim-residue-wording

Plan: `knowledge-base/project/plans/2026-10-19-fix-dpd-10-3b-interim-residue-wording-plan.md`. DRAFT legal wording; owner review required before merge; Ref #10138, Ref #6897 only. Stops at a draft (Operator Holds).

## Phase 0 - Start
- 0.1 `git fetch origin main && git merge origin/main`; re-run the four baseline gates (drift ratchet, check-tc-document-sha, lint-legal-registers, probe-legal-corpus-truth)
- 0.2 Confirm PR #10528 is a draft and `mergeQueueEntry` is null (GraphQL); STOP if queued

## Phase 1 - Pre-merge reads (plain reads, no dispatch)
- 1.1 Hetzner volume read (read-only token) plus volume action history
- 1.2 `gh run list --workflow git-data-cutover.yml --limit 1000`; no wipe-family run, none in flight, no successful wipe_check
- 1.3 Doppler prd reads of GIT_DATA_STORE_ENABLED and GIT_DATA_LUKS_CUTOVER_AT (non-zero exit is a HOLD)
- 1.4 Record in session-state.md and the PR body; set `<ASOF>`; on any HOLD write `HOLD: <condition>`, stop, no DONE promise

## Phase 2 - DPD 10.3(b)
- 2.1 Bullet (b) canonical then mirror, byte-identical (CLO text with ruling-B replacement)
- 2.2 DPD Last Updated entry (canonical, mirror body, mirror hero date)

## Phase 3 - T&C pointer, bump, pins
- 3.1 T&C 14.1b pointer paragraph (canonical, mirror link form)
- 3.2 T&C Last Updated entry (canonical, mirror body, mirror hero)
- 3.3 tc-version.ts: TC_VERSION 2.6.1, TC_DOCUMENT_SHA (provisional), TC_BUMP_METADATA label and date
- 3.4 seed-dev-users.sh and seed-qa-user.sh TC_VERSION 2.6.1
- 3.5 legal-doc-shas.ts data-protection-disclosure hash (provisional)
- 3.6 compliance-posture.md T&C row: version 2.6.1 and date

## Phase 4 - Register and sibling records
- 4.1 PA-36 (f) end-of-cell marker (governs both 2026-10-22 mentions)
- 4.2 PA-36 Status marker
- 4.3 M2 after the ledger citation in PA-36 (f)
- 4.4 M1 x4 (PA-2 (g) one, PA-36 (g) three), anchors asserted unique
- 4.5 ADR-239 blockquote pointer; attestation 9066 frontmatter and body pointers (YAML still parses)
- 4.6 compliance-posture.md follow-up row

## Phase 5 - Attestation and final pin
- 5.1 All wording final; set edit-day values; final `git merge origin/main`; recompute both pins
- 5.2 Phase 6 gates; spawn CLO for the final-diff attestation; write the attestation file
- 5.3 Day rollover: re-date, re-hash, re-attest

## Phase 6 - Verification
- 6.1 Gates: sha256sum vs literals, check-tc-document-sha, drift ratchet, lint-legal-registers, lint-legal-scope-block-placement, probe-legal-corpus-truth, technical-ruling-gate, four vitest files, markdownlint
- 6.2 AC1-AC12 greps (ADDED word-diff; published surfaces vs internal records)

## Phase 7 - PR marking, then stop
- 7.1 Update PR #10528 title (DRAFT prefix) and body; no ready, no merge, no enqueue
- 7.2 Verify no workflow dispatch and no issue post occurred
