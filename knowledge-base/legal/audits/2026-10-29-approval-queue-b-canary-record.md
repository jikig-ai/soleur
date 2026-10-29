---
title: "CLO (b-canary) record: approval queue, Jikigai-owned canary workspace only (#4672, PR #11289)"
status: conditional
date: 2026-10-29
pinned_head: e271d9f1019c426c0e4c7101527c4d3e2e7ab6f7
related: [4672, 11289, 11303]
related_adrs: [ADR-307, ADR-029]
brand_survival_threshold: single-user incident
scope: "verification step of posture item (b) plus the canary-workspace condition; NOT the full (b) attestation"
---

# CLO (b-canary) record: approval queue, canary only

Draft internal v1 position (CLO as the v1 attestation authority); not a counsel review. It is limited to what the posture row "Approval queue: public wording and enabling gate" in `knowledge-base/legal/compliance-posture.md` assigns to (b-canary), per CLO round-2 ruling 2. It claims nothing is enabled and nothing is measured beyond what each section below says it verified.

Pinned to HEAD `e271d9f1019c426c0e4c7101527c4d3e2e7ab6f7` (branch `feat-hitl-approval-queue`, PR #11289). The only working-tree change made at the time of writing, outside this file, is one CLO edit in `knowledge-base/legal/article-30-register.md` PA-38 (g)(7) (the key derivation is HKDF-SHA256, not "HMAC of the secret with the label"; see section 6). No published document or mirror was changed.

**This record is conditional on** the `Tenant integration (dev-Supabase)` workflow (`.github/workflows/tenant-integration.yml`) running `approval-request.tenant-isolation.test.ts` green for this PR (section 7). I did not observe that run: at the time of writing `gh pr checks 11289` listed other checks as `pending` and no tenant-integration row. If that suite is red, skipped or not run, this record is void.

## (i) Verification step

### (i-1) The three "no plaintext" statements each carry their approval-queue qualifier

Commands (run from the worktree root; every phrase occurrence must have "approval queue" or "approval request" within 1400 characters after it):

```
for f in docs/legal/*.md plugins/soleur/docs/pages/legal/*.md; do
  perl -0777 -ne 'my($n,$q)=(0,0); while(/(persist no plaintext|never store the plaintext|remain only in the drafting)(.{0,1400})/gs){$n++; $q++ if $2=~/approval queue|approval request/i} print "$ARGV phrases=$n qualified=$q\n" if $n' "$f"
done
```

| File | phrase occurrences | with qualifier |
|---|---|---|
| `docs/legal/data-protection-disclosure.md` | 1 (`persist no plaintext`) | 1 |
| `docs/legal/gdpr-policy.md` | 1 (`remain only in the drafting`) | 1 |
| `docs/legal/privacy-policy.md` | 2 (`persist no plaintext`, `never store the plaintext`) | 2 |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 1 | 1 |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 1 | 1 |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 2 | 2 |

Total 8 occurrences, 8 qualified, canonical and mirrors identical. (A first run with a 700-character window reported 7 of 8 because the Privacy Policy 4.14 "never store the plaintext" qualifier sits 796 characters later, in the trailing italic note of the same bullet; I read that note and it is the qualifier, so the window, not the text, was the defect.) The 4.14 note says the recipient address, subject and body are also held in the workspace's approval request, readable by the workspace Owner only, until 30 days after the request ends, and that the outbound-email records still hold hashes only.

Broader census, because the posture row names three phrases and a categorical sentence need not use them: `grep -n -i plaintext` over `docs/legal/*.md` returned 19 hits that concern outbound-email records. The ones with no qualifier in reach are all of two kinds: (1) the dated amendment/history notes in the `Last Updated` header of each document (the DPD and GDPR Policy and Privacy Policy headers quote the superseded #5325 sentence and are followed by the "previously stated" corrections of #8532/#8617); (2) sentences scoped to named tables ("these tables never persist the plaintext recipient address or bodies", DPD 2.3(ab)), which stay true because the approval request is a different table. I accept both as history or scoped; I do not find a present-tense categorical statement about outbound email data in the three documents that lacks its qualifier.

Register: the register does not use the three phrases (0 hits). Its equivalents are PA-28 (c) "plaintext recipient address is NEVER persisted and bodies are NEVER persisted" and PA-28 (g) item 9 "plaintext recipient never persisted". The qualifier is the PA-28 `Amended 2026-10-29 (#4672 ...)` block, which states it applies "as to the statements in (c)". Residual noted, not blocking a canary: that block names (c) only, and (g) item 9 is scoped by its own text to the outbound tables; a reader who wants it explicit should widen the block to "(c) and (g)". The register is an internal record, not a published statement.

### (i-2) No emitter carries `canonical_action`

Commands and counts:

```
grep -rIl 'canonical_action' apps/web-platform --include='*.ts' --include='*.tsx' --exclude-dir=node_modules --exclude-dir=.next | grep -v -E '/test/|\.test\.'        -> 10 files (counted next)
grep -rIn 'canonical_action\|canonicalAction' apps/web-platform/server apps/web-platform/lib apps/web-platform/app --include='*.ts' --include='*.tsx' | grep -v -E '/test/|\.test\.' | grep -E -i '(logger|log|pino)\.(info|warn|error|debug)|reportSilentFallback|warnSilentFallback|mirrorP0Deduped|Sentry\.|captureException|captureMessage|console\.|extra:|logApprovalMarker|reportApprovalOp'   -> 0 lines
grep -rIl 'canonical_action\|canonicalAction' apps/web-platform/infra .github   -> 0 files
grep -rn 'canonicalAction\|canonical_action' apps/web-platform/server/approval apps/web-platform/server/inngest/functions/cron-approval-expiry.ts apps/web-platform/lib | grep -v '\.test\.' | grep -i 'log\.\|logger\|reportSilentFallback\|warnSilentFallback\|mirrorP0\|Sentry\.\|captureException\|captureMessage\|extra\|console\.'   -> 0 lines
```

The 10 non-test files that name the column are the migration (`180_approval_request.sql`), the Owner page and inbox enrichment (both a `select` column list), `reattach.ts`, `view-model.ts`, `service.ts` (the row type, the RPC argument, and a destructuring that strips the column before a status object is returned), `canonical.ts` (a comment), `cron-approval-expiry.ts` (a comment), `account-delete.ts` (comments) and `dsar-export-allowlist.ts` (a comment). None is a log, Sentry or marker call.

Emitters: the approval code reaches Sentry and Better Stack through two functions in `apps/web-platform/server/approval/ops.ts`, `reportApprovalOp` (a static message, a tag `approval_id`, and `extra` limited to tool name, ids, `code`/`fn`/`errName` from a caught error and small caller-supplied scalars) and `logApprovalMarker` (`SOLEUR_APPROVAL_*` markers, ids, enums and counts). Of the 50 call sites of these two functions outside tests that I counted, the `extra:` objects I read (grants.ts, reattach.ts, gate-flow.ts, listed by `grep -rn 'extra: *{' apps/web-platform/server/approval`) carry reason/code/stage/channel/count scalars, never action content. The Vector/Better Stack config under `apps/web-platform/infra` has 0 references to the field. This is a static grep of code at the pinned head; it is not a measurement of what Sentry or Better Stack actually received, and a caller-supplied `extra` could be changed later, which is why the canary gate re-uses this step at every flip.

## (ii) Canary workspace condition

Confirmed recorded as a gate condition: the posture row's "Does not close" clause now reads that a canary ON requires (b-canary), "plus confirmation that the canary workspace is owned by Jikigai and that every member of it is a Jikigai principal", and the same row names the engineering counterpart in ADR-307 (cohort rule: the flag is limited to single-member workspaces, `workspace_members` count checked before any per-workspace override, and re-checked on every member invite). The legal condition is stated independently of the engineering rule, so it still holds if the cohort rule is relaxed.

This is an operator check at flip time. It cannot be verified from the repo: whether a given workspace is Jikigai-owned and who its members are is runtime data. I have verified only that the condition is written into the gate. Nothing here states that any workspace qualifies.

## (iii) Re-pin check

Method: `sha256sum docs/legal/<doc>.md` against `apps/web-platform/lib/legal/legal-doc-shas.ts`.

| Document | sha256 (canonical file at the pinned head) | equals pin |
|---|---|---|
| `privacy-policy` | `a5a0f4e2d0095131b5d90edfbdf5c4218b6fb4e824355c3cc3b2f3f663099aa0` | yes |
| `gdpr-policy` | `bed31edf0020fa00a3020b78ed71aa5798c0e54c84ce18c0ea1056134c08adc7` | yes |
| `data-protection-disclosure` | `7d5ec49275f849a8aaa510d7e54ec921b71171d03e6c89d5976bea70d71e6bb4` | yes |

All eight entries in the pin file match their files (checked by script), and `apps/web-platform/scripts/check-tc-document-sha.sh` exits 0. `scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` exits 0. `git diff --stat origin/main...HEAD` over the legal paths lists only the Privacy Policy, GDPR Policy, DPD, their three mirrors and `legal-doc-shas.ts`; the Terms and Conditions are not in the diff, so no `TC_VERSION` bump applies.

If any of the three canonical documents changes after this record, this record is void for that document and the re-pin and this step must be repeated.

## (iv) Round-2 application choices I accept

I was given no itemised list of the clerk's calls; I diffed the committed text against my round-2 rulings (`CLO-RULINGS-R2.md`) and accept the following. Anything not named here is not accepted by this record.

1. Verbatim application of the exact replacements of rulings 1.1 to 1.9, 4.1, 4.2, 5.1, 5.2 (twelve before/after pairs re-checked by string match: all twelve "after" strings present, the superseded "before" strings absent), applied in-cell with no `Superseded` marker, because the PR is unmerged.
2. The ruling 1.10 straggler sweep (`both links`, `two user columns`, `decided, used`, `used or expired`, `forward-only`) returns only the corrected Privacy 4.15 status sentence ("decided, withdrawn, used or expired", which is the ruling's own wording) and the corrected PA-38 (g)(3) and ADR-307 "forward-only except an Owner revoke". The ruling 9 final sweep (`nothing was run`, `Only who decided`, `retention stated in those Sections (90 days)`, `removed 90 days later`) returns nothing across `docs/legal`, the mirrors, `knowledge-base/legal`, `apps/web-platform/lib` and `apps/web-platform/server`.
3. Ruling 8 strings: the copy-deck strings now read "ran nothing" (`resolvedNothing`, `expiredLine`, the expired-after-approval line, the push body and the email line), not "Nothing was run".
4. Ruling 6: `detailsRemovedLine` carries the scheduled-removal wording and `detailsRemovedNeutralLine` exists as the neutral variant.
5. Rulings 2 and 3 posture-row text (b-canary clause, "(b) the full CLO attestation" prefix, card-string note) present as worded.
6. Ruling 4.2: the dangling "(ruling 1)" citation is gone from the PA-38 (f) cell (0 hits).
7. The key derivation: the code is HKDF-SHA256 (`hkdfSync`, key material `SENTRY_USERID_PEPPER`, empty salt, `info` `soleur:approval-request:action-sha256:v1`, 32 bytes) followed by HMAC-SHA-256 over the canonical action, which is a stronger and more conventional construction than the "HMAC of the secret with the label" I accepted in ruling 7. I accept the change; the register is conformed to the code (section 6). Rotation consequence, residual and "does not defend" list are unchanged by it.
8. ADR-307's cohort rule (single-member workspaces only) as the engineering counterpart of the canary condition.

## (v) What remains owed

Before ANY ON, canary included:

- **(a) Real-SDK probe recorded.** Exists: `knowledge-base/project/specs/feat-hitl-approval-queue/phase-0-measurements.md`, "Addendum 2026-10-29 (#4672): probe re-run on the finished branch (task 5.4)", result `RESULT: PASS (sdk=0.3.284 cli=2.1.284, cases-run=10)` with all eight gated tools `denyHonoured=true` and the raw-composition canary `CANARY-OK`. Limits that this record carries rather than hides: (1) that addendum was committed in `971c7a5916`; since then `dev-probe-approval-gate.ts` and `agent-runner.ts` changed (the probe script now passes a disabled `ExecutionGrants` to the tool builders, and the runner wires one shared grants object into the gate and three builders), and `gate-flow.ts` and `gate.ts` changed substantially. A re-run at the final head `e271d9f101` is recorded in the same file ("Addendum 2026-10-29 (#4672): probe re-run at the final head e271d9f101", PASS, cases-run=10); a later code change to the gate, the grants or the runner re-opens it. (2) The addendum itself says it does not measure the approval flow with the flag on, nor the hosted ask lane (#9776, #10111). It supports ruling 3's standing condition only for "a deny is honoured on the legacy runner path"; the single-use grant behaviour that justifies "this exact commit" and "this exact setting" remains design intent, not measured.
- **(i) Erasure and fingerprint conformance, as a real-database run.** Owed as a recorded run: after a real-database test erasure of a personal workspace, `select count(*) from approval_request where workspace_id = :erased_user_id` is 0 and the fingerprint is keyed. The test file is `apps/web-platform/test/server/approval-request.tenant-isolation.test.ts`, gated by `describe.skipIf(!ENABLED)` (`TENANT_INTEGRATION_TEST=1`); it runs only in `tenant-integration.yml`. This record is conditional on that suite being green there for this PR (see top); the result must be recorded in `knowledge-base/legal/audits/` before a canary ON. I have not seen it.
- **(b-canary)** is this record, subject to its conditions: the tenant-integration suite green, a probe re-run at the final head recorded, no later change to the three canonical documents, and the operator's flip-time confirmation (section ii).
- **Cohort and pepper (posture row (j), (k); ADR-307 flip checklist items 1 and 2).** Single-member workspaces only until the cohort rule is met; `SENTRY_USERID_PEPPER` non-empty in the container and not rotated while approvals are live. Not verifiable from the repo; operator checks at flip time.

Before NON-canary ON, in addition:

- the **full (b)** CLO attestation (design-intent review of the queue; it is not done by this record), then **(c)** the docs PR removing the two qualifier sentences from the three documents and mirrors with re-pin and a re-read of each "nothing here states that a request ... has been stored" sentence; **(d)** `gdpr-gate` recorded; **(e)** the DSAR export path (Art. 15 is manual by email to `legal@jikigai.com` today); **(f)** DPIA screening, the standalone LIA for the user-column record, and the outbound-email LIA re-read for the new storage location; **(g)** the counsel questions in Register Maintenance item 15; **(h)** the autonomous-run card wording flipped to non-provisional with the CPO and CLO reviewer fields filled.
- Ruling 3's standing condition must hold in the probe, and the ruling 6 and ruling 8 in-product strings must be in the build.

## (vi) Register conformance edit made with this record

`knowledge-base/legal/article-30-register.md`, Processing Activity 38, (g) item 7: the sentence "a key derived (HMAC-SHA-256 of the secret with the domain-separation label ...)" was replaced in-cell (the PR is unmerged; no `Superseded` marker) by a description of the code in `deriveApprovalHashKey`: HKDF-SHA256 via `node:crypto` `hkdfSync`, input keying material `SENTRY_USERID_PEPPER`, empty salt, `info` label `soleur:approval-request:action-sha256:v1`, 32 bytes; the fingerprint is HMAC-SHA-256 over the canonical action under that derived key. A grep for `domain-separation label` and `HMAC-SHA-256 of the secret` over `knowledge-base/legal` now returns 0. The published documents and mirrors describe the fingerprint only as "a keyed fingerprint (an HMAC-SHA-256 computed with a secret held outside the database ...)" and do not describe the derivation; that statement stays true under HKDF-then-HMAC, so no published change and no re-pin follow from this edit. ADR-307 already says HKDF.

## Re-evaluation triggers

Void and repeat on: any change to a canonical legal document or mirror; any new emitter or `extra` field in `server/approval`; a change to the cohort rule; the first arms-length (non-Jikigai) workspace; or the first non-canary ON, which needs the full (b).
