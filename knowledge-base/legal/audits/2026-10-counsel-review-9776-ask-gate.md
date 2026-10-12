---
title: "Counsel review audit — #9776 ask-gate (hosted must-ask lane; banner and enable-confirm copy revised; legal text deliberately untouched)"
type: counsel-review
date: 2026-10-10
issue: 9776
pr: 9977
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-10-10
signed_off_by: "CLO agent"
disposition: "NOT DISCHARGED as of 2026-10-12 (#10054): C1-C8 were verified 2026-10-11 against a mocked SDK and the live path was inert until the 2026-10-12 08:38Z deploy; C9 is a PROPOSED equivalence pending operator ratification, limb (b) production arrival NOT OBSERVED; banner assurance stays ship-blocked in prod verification until both limbs are recorded"
conditions:
  - "C1 — one unit: banner copy, toggle copy, lane and tests ship in one build and one commit/revert unit; no feature flag; copy applied byte-for-byte from the ruling."
  - "C2 — the statement is true on the live canUseTool path: the real-factory wiring test, an un-acked owner is gated, and a prior git push or terraform grant does not launder the destroy forms."
  - "C3 — vocabulary guard: banner, toggle and card never say blocks, prevents, protects, safe to approve, guaranteed or always in reference to the lane; a test asserts it."
  - "C4 — card text states the matched family and 'paused for your approval', does not claim other commands are safe, options exactly Approve and Reject."
  - "C5 — telemetry hygiene: shared pino logger (userId hashed), no command text, preview, branch or refspec in pino, Sentry tags, extra or breadcrumbs; asserted by a test."
  - "C6 — tracking issue filed before merge for the AUP 5.7 / T&C 3a.7 parenthetical revision (deadline 2027-01-08 or earlier trigger); linked in the PR body and here."
  - "C7 — legal artifacts untouched and asserted: docs/legal/**, plugins/soleur/docs/pages/legal/**, TC_VERSION, TC_DOCUMENT_SHA, LEGAL_DOC_SHAS have an empty diff; the PR body states no TC_VERSION bump and no re-acceptance."
  - "C8 — ADR-284, the ADR-277 addendum and the C4 text do not say the hosted gate is complete; they carry the residual list."
  - "C9 — post-merge, one recorded observation on dev hosted (throwaway repo): the card appears for git push --force origin <default> and terraform destroy and the telemetry arrives. Until then the banner assurance is ship-blocked in prod verification."
supersedes_in_part: knowledge-base/legal/audits/2026-10-counsel-review-9776.md
re_evaluation_triggers: "First arms-length Workspace Owner; first EEA-out operator; first regulated-industry tenant; any change widening or narrowing the lane's recognised set (including adding GraphQL deleteRef/deleteRepository/updateRef, terragrunt or pulumi); a measured miss in the near-miss telemetry on a destructive spelling; any new unblocked destructive command family; any change to BLOCKED_BASH_PATTERNS or the read-only allowlist; any enablement of the plugin hook in hosted sessions (ADR-277 D8 change); the next TC_VERSION bump; publication of #9603's hosted-coverage claim; 2027-01-08; any conversion of autonomous execution into a third-party-effecting send (Art. 22(3))."
---

# Counsel review audit — #9776 ask-gate

Load-bearing evidence for the ship-time Counsel-Review CLO-Attestation Gate on the PR that ships the hosted must-ask lane. It supersedes in
part `2026-10-counsel-review-9776.md`, for the single row "Until a stricter check ships" in that audit's drift table, and only on the merge
of this PR. The binding ruling is `knowledge-base/project/specs/archive/20261011-050138-feat-9776-hosted-autonomous-ask/clo-ruling.md`; the design is ADR-284.

Under the Soleur-as-tenant-zero v1 posture the CLO agent performs this review; the operator retains an optional veto. Draft material, not
legal advice; external counsel is reserved for the re-evaluation triggers above and routes through `knowledge-base/legal/recommended-tools.md`.
Per-artifact verdicts are written in the conditional: each fires on the merge of the PR that carries this change.

## Code cross-checked (by name)

- `apps/web-platform/server/permission-callback.ts` — `createCanUseTool`, the Bash branch: the blocklist deny, the safe-bash allow, the
  support-persona deny, then the must-ask lane (`detectDestroyAsk`), then the autonomous bypass, the disclosure holds and the batch cache.
- `apps/web-platform/server/destroy-ask-classifier.ts`, `destroy-ask-lane.ts`, `resolve-protected-branches.ts` — the classifier, the card
  text and telemetry helpers, and the protected-branch resolver.
- `apps/web-platform/components/chat/autonomous-disclosure-banner.tsx` (`AUTONOMOUS_DISCLOSURE_COPY`) and
  `apps/web-platform/components/settings/bash-autonomous-toggle.tsx` (the enable-confirm paragraph).
- `apps/web-platform/test/destroy-ask-hook-parity.test.ts` and `test/fixtures/destroy-ask-corpus.json` — the classifier is bound to the
  plugin hook's D1 set.

## Drift table (prose against code)

| Claim | Code evidence | Verdict |
|---|---|---|
| "It also pauses to ask before common forms of a force-push over, or deletion of, your repository's default branch ... and before terraform destroy" | The lane in `createCanUseTool` sends a match to the review gate with Approve and Reject; corpus rows for each spelling; `permission-callback-destroy-ask.test.ts` | MATCH, scoped by "common forms" |
| "It does not recognise every way of writing those commands, or every other way to delete a repository or tear down infrastructure, so such a command can still run without asking" | ADR-284 residuals: variable-built names, aliases, script indirection, terragrunt and pulumi, `git update-ref`, GraphQL mutations, other `gh` deletes, recursive `rm` | MATCH |
| "no blocklist is perfect" | `BLOCKED_BASH_PATTERNS` is unchanged | MATCH, kept as locked |
| "Other commands that look safe could still change or delete files in this workspace" | The lane covers one short list; every other non-blocked command is unchanged | MATCH, kept as locked |
| "Until a stricter check ships ... without asking" (2026-10-08 copy) | The check shipped in this PR | Removed |
| Approval applies to this command only | The lane returns on approval with no acknowledgement write and no cache grant; asserted by test | MATCH |

## Representation ruling (the added assurance)

The assurance is acceptable as a hedged, present-tense, best-effort description of a shipped behaviour on three conditions: (i) it is true on
the live `canUseTool` path in the same build (C2); (ii) it is never stronger than the verbs it uses, "pauses to ask" and never "blocks",
"prevents" or "protects" (C3); (iii) it ships and reverts as one unit with the lane (C1). It is not a warranty: T&C 10.4 still disclaims, in
capitals, any warranty that the layer will stop or ask first.

## Existing acknowledgements

Still valid. An acknowledgement evidences consent to a risk; the risk under the new copy is a strict subset of the risk the acknowledged copy
disclosed. The added assurance is a representation made after the acknowledgement and induced none of them. Triggers that WOULD require a
versioned acknowledgement: any copy widening (a newly unasked command class, or a withdrawal of this assurance that is not a pure revert to the
2026-10-08 text). Not covered here: the C2 follow-through from PR #9792 (the supersede UPDATE for acknowledgements written on the old build
during the migrate-before-swap window) remains an open operator item.

## Legal text: deliberately untouched

AUP 5.7, T&C 3a.7 and T&C 10.4, and both Eleventy mirrors, are not edited in this PR. The sentence "does not guarantee that it will stop, or ask
you first about ..." stays true. The parenthetical "(and at the date of this version it does not)" is anchored to the 2026-10-08 version date
and goes stale in the user-favourable direction (risk LOW). Deleting it is a Tier 2 T&C change under `tc-version-bump-policy.md` and forces
every user to re-accept Terms one build after the previous forced re-acceptance; an AUP-only edit is rejected (it would put "pauses to ask" next
to Terms saying the opposite). Dated deadline: the earliest of the next `TC_VERSION` bump (bundle it there), publication of #9603's hosted-coverage
claim, the first arms-length workspace owner, or **2027-01-08**. The verbatim replacement text is in the CLO ruling (section 3.4). Tracking issue
(C6): filed as [#9955](https://github.com/jikig-ai/soleur/issues/9955) (also in the PR body).

## Art. 30 / privacy documents

No change. The telemetry (`ruleId`, `family`, `autonomous`, `isOwner`, `acked`, `authoritative`, `repo`) is security and operational logging inside
the existing Sentry and Better Stack streams (Privacy Policy 5.14, 90-day retention); no new purpose, data category, recipient, sub-processor,
retention period or transfer; lawful basis unchanged (Art. 6(1)(f) with Art. 32). No command text or redacted preview is emitted (C5).

## Per-artifact verdicts

| Artifact | Verdict |
|---|---|
| Banner `autonomous-disclosure-banner.tsx` + test | Would PASS on the merge of the PR that carries this change: copy verbatim from the ruling (section 1); vocabulary guard green. |
| Enable-confirm paragraph `bash-autonomous-toggle.tsx` + test | Would PASS on the merge of the PR that carries this change: copy verbatim (section 2); `/no blocklist is perfect/i` still matches. |
| Review-gate card (server-built question) | Would PASS on the merge of the PR that carries this change: states the cause and "paused for your approval", options Approve and Reject. |
| AUP 5.7, T&C 3a.7 / 10.4, mirrors, `TC_VERSION`, SHAs | UNTOUCHED (C7). |
| Migrations, RPCs, acknowledgement columns | UNTOUCHED: no migration, no write to production. |

## Overall disposition

**DISCHARGED** if C1-C9 hold at ship. C9 is a post-merge observation: until it is recorded the banner assurance stays ship-blocked in prod
verification and the operator is told so. If C1 or C2 fails the disposition is BLOCKED.

## Addendum — 2026-10-12 (#10054)

> **Superseded 2026-10-12 (#10054):** "C1-C8 verified 2026-10-11 ... C9 post-merge observation pending" and the C2 verification above. C2 was verified against a mocked SDK. The live path was inert until the 2026-10-12 08:38Z deploy, so for that interval the banner assurance was not true in production. The overall disposition stays not DISCHARGED until C9 limb (b) is recorded and limb (a) is ratified.

**C9 — PROPOSED equivalence, pending operator ratification (not discharged).** The dev-hosted observation is proposed to be replaced by two limbs. **(a) Card behaviour:** the real-SDK probe `apps/web-platform/scripts/dev-probe-destroy-ask.ts` passing on the deployed stack (SDK 0.3.284, bundled CLI 2.1.284) for the owner, a non-owner member, a stale batch grant with a live-grant control, and the `gh` repo-delete family, with in-process emission of the pino line and Sentry event asserted. See ADR-284, "Runtime proof / C9 result". **(b) Production telemetry arrival:** NOT OBSERVED. There were no natural asks in the first hour after deploy, and the `ci` Doppler config carries no DSN or Better Stack token, so a local run cannot arrive at the sinks. Limb (a) may be closed by ratified decision, which closes it but does not make it a dev-hosted observation. Limb (b) stays open until one production arrival is recorded, pulled by API. The wording "the ask gate is verified in production" may not appear anywhere.
