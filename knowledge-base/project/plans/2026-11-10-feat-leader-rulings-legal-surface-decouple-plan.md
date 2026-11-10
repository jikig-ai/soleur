---
title: "feat: implement the 2026-11-10 leader rulings for the founder acceptance record (legal surface decoupled from the approval-queue flag, push and gh disclosures, records)"
date: 2026-11-10
slug: feat-leader-rulings-legal-surface-decouple
branch: feat-one-shot-12197-leader-rulings-surface-decouple
issue: 12197
closes: none
type: feature
priority: p2
domain: engineering, legal, product
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
pr: 12567
lane: cross-domain
---

# feat: implement the 2026-11-10 leader rulings for the founder acceptance record

## Enhancement Summary

**Deepened on:** 2026-11-10 (after a seven-reviewer plan review plus a sharp-edges pass).
**Sections enhanced:** Implementation Phases 1, 2, 4, 7 and 8; Observability; Acceptance Criteria; Test Scenarios; Not in this PR; Files to Edit and Create; Research Reconciliation.
**Agents used:** plan review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CPO, UX design lead), a sharp-edges verifier, CTO rulings K1 to K3, CLO ruling L2, and a verify-the-negative and self-audit pass.

### Key Improvements

1. The internal legal records that change 1 makes false on merge now get dated, append-only markers in this PR (CLO ruling L2, Phase 4.3). The text is in the spec directory's `clo-register-markers.md`. The published trio is still unchanged.
2. The kill switch is spelled out (CTO K1 and K2). Unsetting the founder id closes the card and the check endpoint together (503, so web-acceptance holds stay unevaluated), only after a redeploy, with no Sentry event. It is detected by the post-deploy unauthenticated probe (401 when set, 503 when unset). Post-merge AC21 checks this.
3. The e2e contract is now hardened:
   - The founder is identified by the JWT `sub`, not by token string.
   - The refresh token is read from the request body, and an unknown one returns 400.
   - The founder and non-founder cases run in separate `describe` blocks.
   - The negative control waits for the inbox to load before asserting.
   - The hash check is scoped to the row and the payload.
   - Two screenshots are taken.
   - After the click, the spec asserts the card's own marker, not a status code.
   - The run uses `CI=1`.
4. The sweep of stale flag wording is complete across code comments, the README, the runbook and `feature-map.md`, and AC18 widens the grep to prove it. A stale Sentry config comment is deliberately left alone, because editing it would trigger a production Sentry apply (CTO K3, #12581).

### New Considerations Discovered

- `apps/web-platform/infra/sentry/**` edits trigger a full-root production `terraform apply` on merge. A comment-only change there is a production write.
- `technical-ruling-gate.sh` accepts only `Ruled by CTO|CLO agent, <date>:` for technical rows and one-word operator classes. The decision record was reshaped to pass (34 rows, PASS).
- `lint-questionnaire-identity.sh` needs `--all` (CI's form). The bare call exits 3.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

One pull request (draft #12567) carries the repository changes that the CLO, CTO and CPO agents ruled on 2026-11-10 for epic #12197: the founder legal-acceptance surface stops reading the approval-queue flag, a shared push disclosure replaces three inaccurate settings sentences (and the shared gh disclosure is corrected for the same defect), and the rulings are recorded in the ADRs, the C4 model, the legal audit trail, the compliance posture register, a draft counsel questionnaire and the approvals wireframe. One hermetic browser e2e renders the Inbox legal row for the first time.

Nothing here writes to production, flips a flag, or edits `docs/legal/*`, their Eleventy mirrors or `founder-acceptance-record.md`. The PR body says `Ref #12197`, `Ref #12365`, `Ref #12366`, `Ref #12449` and closes none of them.

**Rulings are inputs, not open questions.** Every decision below was made by a spawned domain agent with "do NOT use AskUserQuestion". They are recorded in `knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/decision-challenges.md` (written at plan time). Planning surfaced three gaps the original rulings did not cover; the CTO ruled them (F1 to F3 below) and the CPO and CLO ruled the resulting wording.

## Research Reconciliation — Spec vs. Codebase

| Brief / ruling claim | Reality on this branch (base `b258336eb5`) | Plan response |
|---|---|---|
| Change 1 tests: `surface.test.ts`, `inbox-rows.test.ts`, `page.test.tsx`, `inbox-route.test.ts` | `test/legal-acceptance/routes.test.ts` also drives the real surface through a mocked flag (`h.flag.value = false` → 404 in "flag off and unknown or malformed key", "founder gate: with the flag ON…", and "a founder who already holds a live intent cannot record once the gate is off"). These go RED once the flag is not read. `inbox-rows.test.ts` and `inbox-route.test.ts` mock the surface module, so they keep passing and are not edited (1.4). | `routes.test.ts` added to Files to Edit; its flag-off arms become founder-id-unset arms plus a new "flag off, founder configured → still enabled" arm. |
| "Who sees the card" paragraph is the only stale prose | Stale "flag AND founder" prose also sits in `server/legal-acceptance/README.md` (line 12 and the paragraph), `surface.ts` header, `inbox-rows.ts` header, `app/api/inbox/route.ts` header, both legal page headers and inline comments, `page.test.tsx` header, ADR-319 (2026-11-07 bullet, 2026-11-09 addendum) and the C4 model (`model.c4` `legalAcceptanceStore` description and the `webapp -> legalAcceptanceStore` edge: "Screens ship behind the approval-queue flag (PR-C)"). | Code comments and README are edited in place (not records); ADR-319 gets an append-only amendment; `model.c4` descriptions are corrected and `model.likec4.json` re-rendered (C4 is a model, not a dated record). |
| Config report semantics after decoupling | Not covered by CTO follow-up 2. Today the once-per-process `storeFailed`/`config` report fires only when the flag is ON. | CTO ruling F1: unset founder id silent (the kill switch), set-but-malformed reported once per process. |
| PUSH_DISCLOSURE text (CTO follow-up 4) | ADR-309 checklist item 12 requires the copy to be accurate in both forwarder states. A toggle-on session whose web access fails to start keeps `GH_TOKEN`, `GIT_ASKPASS` and GitHub egress and can push (`cc-dispatcher.ts`, `agent-runner-query-options.ts` `allowWebEgress: args.webEgress !== undefined`). The existing `GH_DISCLOSURE` has the same absolute claim. | CTO ruling F3 corrects both constants; CPO and CLO rule the final wording (see Phase 2). |
| e2e: "set LEGAL_ACCEPTANCE_FOUNDER_ID to the mock user's id" | `MOCK_USER.id` is `"test-user-id"`, not a UUID; `legalFounderId()` requires a UUID, so that value disables the surface. The row is a `role="button"` div that navigates with `router.push`, not an `<a href>`. CI uploads `test-results/` only on failure. | CTO ruling F2: a second mock user (the founder, a fixed synthesized UUID) keyed on its own token and storage state; click the row and `waitForURL(..., { waitUntil: "commit" })`; the screenshot is committed as design evidence by the work phase. |
| Published legal text and the copy change | CLO W2: PP "Agent web access (opt-in; migration 158, #9534)" bullet and DPD 2.3(ag) (and both mirrors) claim no stored credentials "while enabled", false when a session's web access fails to start. Pre-existing, not caused by this PR. | BLOCKED in this PR (no `docs/legal` changes allowed); tracked in #12571 with the CLO ruling as its input. |
| Internal legal records (not published) describe the surface as flag-gated | Plan review found sentences that become false on merge in `article-30-register.md` (PA-40 Status and Addendum 2026-11-09), the founder row of `compliance-posture.md`, the founder-acceptance attestation (property 10), the founder-acceptance LIA and the counsel review record. | CLO ruling L2: dated append-only markers in this PR (Phase 4.3), text in the spec directory's `clo-register-markers.md`. |
| Published legal text might state the card is flag-gated | Checked: PP 4.17, GDPR 3.19 and DPD 2.3(aj) status paragraphs say the screens "answer only for one configured account"; no sentence in the trio ties the legal-acceptance screens to the approval-queue flag (the only joint sentences point to 4.15 / 3.17 / 2.3(ah) "for the approval queue itself"). | Change 1 makes no published sentence untrue; it keeps the "answer only for one configured account" statement true in every flag state. Nothing is blocked. CLO is asked to confirm in the same wording ruling. |

## Research Insights

**Premise validation (Phase 0.6).** #12197, #12365, #12366, #12449 are all OPEN (`gh issue view`); PR #12567 is OPEN and draft on this branch. `surface.ts`, `web-egress-disclosure.ts`, ADR-319, ADR-032 "Amendment — 2026-11-08 (#12396)", the `compliance-posture.md` approval-queue row (its last cell ends with the round-4 "Superseded 2026-11-09" marker) and frame `j89zs` at `"y": 11500` (exactly one occurrence of that literal in the file) all exist as the rulings describe. `founder-acceptance-record.md` sha256 is `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`. Collision pre-check: the only open PR naming the issues is #12567 itself; the foreign hits are `test-all.sh` processes of the unrelated `feat-one-shot-9137-placement-aware-execution` worktree (host load, not a duplicate). Production `/health` today: `{"status":"ok","version":"0.403.3","build_sha":"e5ad65a6…"}`.

**Property List (Phase 0.6b).**

- P1: the founder's legal screens, Inbox row and decide/reauth routes stay available to the configured founder whatever state the approval-queue flag is in.
- P2: nobody other than the configured founder can see or answer the card (unchanged); with no usable founder id, nobody can.
- P3: a set-but-malformed founder id is visible to the operator in Sentry; an unset one is silent.
- P4: no settings surface tells an owner something false about pushing or `gh` in either forwarder state.
- P5: the rulings are recorded where the repo's readers look (decision-challenges, ADR-319, ADR-032, C4, audit record, posture cell, questionnaire, wireframe).
- P6: the Inbox legal row is exercised in a real browser against the real server route.

**Cut List (Phase 0.6b).** None cut: every mechanism maps to a property. `isApprovalQueueEnabled` read in the surface → cut by the ruling itself (P1). A flag read kept only for the config report → rejected by CTO F1 (it re-couples). A new pen frame for the copy change → rejected by CPO (copy-only, `wg-ui-feature-requires-pen-wireframe` excludes it).

**Value-proposition measurement (0.6c).** No cost/performance justification; skipped.

**Relevant files** (all under `apps/web-platform/` unless noted): `server/legal-acceptance/surface.ts` (`isLegalSurfaceEnabled`, `legalFounderId`, `resetSurfaceConfigReport`); consumers `app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx`, `app/(dashboard)/dashboard/approvals/legal/page.tsx`, `app/api/legal-acceptance/[key]/decide/route.ts`, `app/api/legal-acceptance/[key]/reauth/route.ts`, `server/legal-acceptance/inbox-rows.ts` (via `app/api/inbox/route.ts`); check endpoint precedent `app/api/internal/legal-acceptance/[key]/route.ts` (`reportBadConfig`: unset silent, set-but-malformed once). Copy: `lib/web-egress-disclosure.ts` (`GH_DISCLOSURE`), `components/settings/web-egress-toggle.tsx`, `app/(dashboard)/dashboard/settings/scope-grants/page.tsx`; pins in `test/web-egress-toggle.test.tsx` (independent literal + anchored import regex `^import \{ GH_DISCLOSURE \} from "@\/lib\/web-egress-disclosure";$` that a combined import would break). e2e: `playwright.config.ts` (`authenticated` project matches `**/nav-states-*.e2e.ts`; `e2e-auth` webServer env), `e2e/mock-supabase.ts` (`MOCK_USER`, `MOCK_SESSION`, unknown REST paths 404), `e2e/global-setup.ts` (writes `e2e/.auth/user.json`, gitignored), `components/inbox/legal-inbox-row.tsx` (`data-testid="legal-inbox-row"`, `role="button"`), `lib/legal-inbox-copy.ts`, `lib/legal-acceptance-copy.ts` (`Acknowledge "${label}"?`, `textMeta`, badge `Needs your answer`). C4: `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json` (re-rendered by `bash plugins/soleur/scripts/render-c4-model.sh`; gated by `plugins/soleur/test/c4-model-freshness.test.sh`). Lints: `scripts/lint-questionnaire-identity.sh` (the draft questionnaire passes: "1 file(s) checked, clean"), `scripts/lint-legal-registers.sh` (the audit record must not match `DETERMINATION_PATTERN` without a citation or waiver; the CLO rulings text contains no Art. 33 / 4(12) string, measured).

**Institutional learnings applied.**

- `2026-07-17-test-only-override-seam-leaves-prod-default-untested.md`: after removing the flag read, test the unset/default founder-id path explicitly (Phase 1 tests do).
- `2026-09-25-a-proof-by-absence-close-on-a-flag-gated-surface-proves-nothing.md`: the e2e exercises the surface with the gate open, not only its absence.
- `2026-10-05-new-consts-in-mocked-modules-break-test-factories.md`: `lib/web-egress-disclosure.ts` is a leaf module that no test `vi.mock`s (grep: only real imports), so adding `PUSH_DISCLOSURE` there is safe.
- `2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md`: the only consumer pinning the old gh text is `test/web-egress-toggle.test.tsx` (grep of the repo for `gh tool is unavailable`).
- `2026-04-10-e2e-authenticated-dashboard-tests-mock-supabase.md`: the server and the browser both hit the same mock; the founder session must be honoured by both.
- `2026-02-27-pencil-editor-operational-requirements.md`: the `.pen` edit is a JSON edit; re-parse the file after editing.

**Conventions.** `cq-cite-content-anchor-not-line-number` (records cite anchors, not line numbers); `cq-test-fixtures-synthesized-only` (the founder UUID in the e2e is synthesized, e.g. `00000000-0000-4000-8000-0000000000f0`); `wg-kb-artifacts-archived-in-pr`; `hr-never-git-add-a-in-user-repo-agents` (stage exact paths).

**Functional overlap / community discovery.** Internal change to an existing surface with no new stack; no registry search is meaningful. Recorded rather than run.

## Hypotheses

Not applicable (no network-outage trigger in the brief).

## Implementation Phases

Commits are ordered per change so each can revert independently.

### Phase 0 — Decision record (written at plan time)

`bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0 on it (measured at plan time after the plan-review rows: 34 rows examined, PASS). Pipes inside quoted CLO text are escaped as `\|`.

`knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/decision-challenges.md` was written during planning (the session scratchpad is not durable) with the `| Item | Class | Ruling |` table; the work phase verifies it against the agent replies and appends any ruling taken during work or review. Every technical row starts exactly `Ruled by CTO agent, 2026-11-10:` or `Ruled by CLO agent, 2026-11-10:` (the gate accepts only those two; CPO rulings are classed `taste`). Rows (verbatim substance from the agent replies in the session scratchpad; this plan's §Rulings Digest is the fallback copy):

- R1 change 1 (CTO follow-up 2), R2 change 2 (CTO follow-up 4), R3 change 3 (CTO item b), R4 change 4 (CLO Rulings 3 and 4 + required changes 1 and 2), R5 change 5 (CLO questionnaire, status draft, deadline 2026-11-24 proposed), R6 change 6 (CPO frame overlap), R7 `PROVISIONAL` stays true (CPO ruling 3), R8 deferrals (CTO item a: base-SHA pin guard stays deferred; CTO item b: hook speed fix deferred, idle = 1-min load below nproc/4), R9 CTO item c (OTP 10 minutes confirmed), R10 CTO follow-up 1 (agents still ask when the flag is off, by runner), R11 CTO follow-up 3 / item d (counts not measurable by an allowed route; aggregate endpoint is operator scope), F1 config report, F2 e2e shape, F3 disclosure accuracy, W1 CPO wording, W2 CLO wording (approved unchanged; final GH text is the CTO's), L1 the two published web-access sentences (CLO W2; blocked here, tracked in #12571). Added at plan review: W3 frame-23 evidence (CPO), L2 internal legal records (CLO; markers M1 to M4c in `clo-register-markers.md`), K1 to K3 (CTO: shared kill switch, silent unset, Sentry comments tracked in #12581), PR1 to PR7 (plan-review resolutions).
- Operator rows (Class `operator (...)`): O1 whether to narrow or turn off the approval queue (`operator (production-mutating)`, an authorization; CTO's order "role-prd off first, then add workspaces"; NOT done in this PR); O2 whether to build the workspace/approval-request aggregate count (`operator (scope)`); O3 sending the counsel questionnaire and its deadline (`operator (legal-risk)`); O4 pen.dev plan upgrade (`operator (money)`); O5 one PR despite the split thresholds (`operator (scope)`, the brief requires one PR).

### Phase 1 — Change 1: the legal surface gates on the founder id only (TDD)

1.1 RED first. `test/legal-acceptance/surface.test.ts`: keep the `@/server/approval/flag` mock only to set the flag to `false` (no never-called spy: once the import is gone the spy cannot fire, and AC1's grep covers the import). Cases: founder → `true` with the flag mock returning `false` (P1, the case the old AND would break); another user → `false`; unset (`""` and `undefined`) → `false` for everyone and NO report; malformed → `false` and exactly ONE `CONFIG_REPORT` across repeated calls; the report carries neither user id nor value and re-arms after `resetSurfaceConfigReport()`; case-insensitive id compare; `legalFounderId` cases unchanged.

1.2 `test/legal-acceptance/page.test.tsx`: every case that sets `h.flag.mockResolvedValue(false)` to close the surface is re-driven by an unset founder id, and every `h.flag.mockResolvedValue` line is deleted (the flag mock stays only for the one P1 case below). Measured list (case titles at plan time): card page "flag off: an existing recorded row still renders (read-only, no actions)", "flag off and no recorded row: not-found …", "flag off with only an OLDER text's row …", and the undeclared-kind "flag off: the same not-found and no event (the gate runs first)"; index page "flag off and no recorded row: not-found, no key is listed", "flag off with a recorded row …", "flag off with a row only for an older text …", "flag off with a row only for key A …", "flag off with a row only for key B …". Each becomes "surface off: …" with the same assertions. The two "reads the flag first … workspaceId null" cases are deleted outright; "flag on: …" cases become "founder configured: …"; the founder-gate case ("founder gate: with the flag ON, …") keeps the non-founder refusal with the founder configured, drops "with the flag ON" from its title, and its "unset or malformed … exactly ONE report" comment becomes "malformed: exactly one report; unset: none". In `surface.test.ts` the flag-read assertions ("flag is read with the CALLER's own spelling", "WITHOUT reading the flag") are rewritten as founder-id-only cases. Add "flag off and the founder configured: the pending card is open" (P1, the only case that sets the flag mock to `false`). Update the file's header comment ("flag-gated" wording).

1.3 `test/legal-acceptance/routes.test.ts`: "flag off and unknown or malformed key are 404" becomes "founder id unset and unknown or malformed key are 404"; the founder-gate case drops `h.flag` and gains "flag off with the variable equal: STILL enabled"; the live-intent case's "operator turned the flag off" arm is inverted: with a live intent and the flag mock flipped to `false`, decide still records (the journey that used to end in a 404 now completes); the "founder variable went away" arm stays a 404. The founder-gate case runs for both reauth and decide (it is parameterised by `action`). Keep the control arms, including a non-founder refused with the flag on and the founder configured. Add `resetSurfaceConfigReport()` to the file's `beforeEach` (it never re-arms the once-per-process report today) and update the header comment (line 3, "flag-gated").

1.4 Not edited: `test/legal-acceptance/inbox-rows.test.ts` and `inbox-route.test.ts` mock the surface module, so they keep passing and their wording still describes a mocked gate (plan review: no property needs the edit).

1.5 GREEN. `server/legal-acceptance/surface.ts` per CTO F1:

```ts
export async function isLegalSurfaceEnabled(userId: string): Promise<boolean> {
  const founder = legalFounderId();
  if (founder === null) {
    if (process.env.LEGAL_ACCEPTANCE_FOUNDER_ID && !configReported) {
      configReported = true;
      reportLegalOp("storeFailed", null, {
        tags: { stage: "config" },
        extra: { step: "config", variables: ["LEGAL_ACCEPTANCE_FOUNDER_ID"] },
      });
    }
    return false;
  }
  return userId.toLowerCase() === founder;
}
```

Remove the `isApprovalQueueEnabled` import; keep the function `async` (no caller changes); rewrite the header and docblock (founder id only; kill switch = unset; unset silent, malformed once; CTO ruling 2026-11-10 supersedes ruling B's flag AND founder and T4's "flag ON" condition; the module never reads or flips the flag).

The `surface.ts` docblock's T4 passage ("the one state that would otherwise be invisible") is replaced, not kept, by the CTO's K2 text verbatim: "An unset id is the dark state (the kill switch, or a value removed by accident): it is silent here and in the check endpoint, it can take effect only at a process start, and it is found by the unauthenticated probe of the check endpoint answering 503 instead of 401. A set-but-malformed id is reported once per process as `store_failed` / stage `config`. CTO ruling 2026-11-10 supersedes T4's flag-ON condition."

1.6 Comments and local names: `app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx` and `.../legal/page.tsx` (headers and the "surface gate first (flag AND founder)" comments only; the local `flagOn` and the card's `flagEnabled` prop keep their names, because renaming one without the other leaves the name wrong one hop away and renaming the prop widens the diff into `components/approvals/legal-acceptance-card.tsx` and its tests), `server/legal-acceptance/inbox-rows.ts` header, `app/api/inbox/route.ts` header (comment only; the file keeps HTTP-only exports), the status lists in the headers of `app/api/legal-acceptance/[key]/decide/route.ts` and `.../reauth/route.ts` ("404 flag off, not the founder, …" → "404 surface off (founder id unset or malformed), not the founder, …") and the reauth route's `reason` comment ("the flag read" removed), the `guardLegalRequest` docblock in `server/legal-acceptance/reauth.ts` ("in this order: flag, key, …" → "in this order: surface (founder id), key, …"), the `flagEnabled` docstring and the `currentVisible` "(flag off, no answer yet)" comment in `components/approvals/legal-acceptance-card.tsx` (comments only; the prop keeps its name, its meaning is "the surface is open"), the inline "Flag off: …" comments in both legal pages (the `[key]` page header's "as if the flag were off" sentence and its inline gate comment, the index page header and its "Flag off:" comment), both sentences of the `guardLegalRequest` docblock ("in this order: flag, …" and "Flag off (or not the founder) …"), the `inbox-rows.ts` "flag-off user" header phrase, `server/legal-acceptance/README.md` beyond 1.7's paragraph (the "check founder, flag or kind" line and the "Before the `approval-queue` flag is on … pre-flip count check" passage, re-anchored to "before a text change is published"), the header comment of `test/legal-acceptance/surface.test.ts`, and the `/dashboard/approvals/legal` entry in `test/feature-map.md` ("with the `approval-queue` flag on …", "while the flag is on", "with the flag off …" → founder-id wording). A grep AC (AC18) proves the sweep.

1.7 `server/legal-acceptance/README.md`: line 12 parenthetical and the "Who sees the card, and what it says" first paragraph rewritten: the card pages, the Inbox row and the decide and reauth routes require only that the signed-in user id equals `LEGAL_ACCEPTANCE_FOUNDER_ID` (`isLegalSurfaceEnabled`); the approval-queue flag is not read, so narrowing or turning it off does not hide the founder's screen; the kill switch is unsetting the variable, which takes effect only after a Doppler edit plus a redeploy (the container's env file is frozen at creation, so a restart is not enough; `hr-prod-host-config-change-immutable-redeploy`; it closes the surface for everyone; the founder's already-recorded rows still render read-only on the card page and index); unsetting it also closes the check endpoint for the same founder ("Unsetting it also closes the check endpoint for the same founder (it answers 503), so ship's `web-acceptance` holds stay unevaluated and standing until the value is restored and the app redeployed; the counts route reads no founder id and keeps answering.", CTO ruling K1); unset is silent, set-but-malformed reports one `store_failed` / stage `config` per process, then the CTO's K2 sentence verbatim: "To tell an accidental removal from a working setup, request the check endpoint without a token: 401 means the token and founder id are set and valid, 503 `{"error":"Not available"}` means one of them is unset."; a founder mid-flow (code sent, not yet decided) gets a 404 on decide after the redeploy, and the intent expires unused. Ruled by CTO agent, 2026-11-10.

1.7b Runbook `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md` (three passages; edits, not appends, since a runbook describes the present): the intro's "because the flag is global and the key is …" → "because the endpoint and the screens answer for that one id and the key is …"; the `gate` stage row "the flag read or the `LEGAL_ACCEPTANCE_FOUNDER_ID` check" → "the `LEGAL_ACCEPTANCE_FOUNDER_ID` check", and its action drops "the flag provider"; rollout step (6) "only then is the `approval-queue` flag turned on" → a sentence saying the card opens for the founder at step (2), so step (5) is done by the founder through the card, and the flag is not a step.

1.8 ADR-319: append `## Amendment 2026-11-10 (#12197): the founder surface no longer reads the approval-queue flag` after the 2026-11-09 addendum (append-only; earlier text untouched). Sections: Decisions (gate = founder id only; why: the flag is read with `workspaceId: null` → identity `role:prd`, so no per-workspace segment can match it, and the CLO's recommendation to narrow or turn off the queue would otherwise hide the founder's screen; kill switch, and its latency: `process.env` is read per call but only changes when the container is recreated, so closing the surface takes a Doppler edit plus a redeploy where the flag flip used to take seconds (gdpr-gate suggestion A-*; accepted because the gate fails closed on unset or malformed values and a non-founder is refused in every state); the shared kill switch, verbatim from CTO ruling K1: "The kill switch is shared on purpose: the check endpoint (`app/api/internal/legal-acceptance/[key]/route.ts`) answers only for the same `LEGAL_ACCEPTANCE_FOUNDER_ID`, so unsetting it closes the card and also makes that endpoint answer 503, which `hold-gate-eval.sh` reads as UNEVAL; every `web-acceptance` hold then stands until the value is restored and the app redeployed. This is the fail-closed direction, and no separate surface-off variable is added (CTO ruling, 2026-11-10). The counts route reads no founder id and is unaffected."; config report rule, verbatim from K2: "An unset founder id raises no Sentry event, in the surface or in the check endpoint (`route.ts` treats unset as the dark state). It is detected after a deploy by the unauthenticated probe of the check endpoint answering 503 instead of 401, and between deploys by any `web-acceptance` hold coming back UNEVAL; no standing probe exists, and that residual is accepted because the state fails closed."; what does NOT change: RLS, the check and counts endpoints' code, the registry, `PROVISIONAL`, and, verbatim from CTO ruling K3: "The PROVISIONAL `legal-acceptance-failure-burst` threshold (3 in 1 hour) is unchanged; its recalibration trigger is now 14 days of data after `LEGAL_ACCEPTANCE_FOUNDER_ID` is set in production, not after the approval-queue flag is enabled. The comments that still name the flag (`infra/sentry/issue-alerts.tf` above `legal_acceptance_failure_burst`, `infra/sentry/README.md` 'Founder legal-acceptance paging') are corrected in the next PR that already changes `infra/sentry/`, because any edit there starts a full-root Sentry apply on merge (tracked in #12581)."), Superseded by this amendment, quoting ADR-319's own text (verify each quote with `grep -n` at work time): the PR-C intro "PR-C ships the web card and the in-place email-code check behind the `approval-queue` flag" and "ships behind the flag until counsel decides" / "The card ships PROVISIONAL behind the flag", as descriptions of the present; **Flag scope** "Enabling the card means enabling `approval-queue` for every workspace"; **Enabling conditions** "All of these hold before the flag goes on for any founder", re-anchored to "before a founder id is configured in production" (the reading the 2026-11-09 addendum already applies); the 2026-11-07 bullet "The card surface is founder-only while the flag is global … require the flag AND `LEGAL_ACCEPTANCE_FOUNDER_ID`"; the 2026-11-09 addendum's "checked before the flag is read" clause, as to the flag being read at all; and the 2026-11-08 (#12429) "Before the `approval-queue` flag is turned on" counts precondition, re-anchored the same way (`ok_to_flag` keeps its name and now reads as "ok to publish"), then one closing sentence for principle alignment (AP-021 aligned) and the diagram (two `model.c4` descriptions corrected; no element or edge added), instead of two boilerplate sections.

1.9 C4: in `model.c4` replace, in the `legalAcceptanceStore` description (line 339 at plan time), the span from `Screens ship behind the approval-queue flag (PR-C), but` through `no configured id means off)` (exclusive end: the following `; the check endpoint merges dark …` stays) with `The screens, the Inbox row and the decide and reauth routes answer only for the configured founder id (LEGAL_ACCEPTANCE_FOUNDER_ID; no configured id means off); the approval-queue flag is not read (ADR-319 amendment 2026-11-10)`; and in the `webapp -> legalAcceptanceStore` edge (line 661) the one sentence `Screens ship behind the approval-queue flag (PR-C).` with `Screens answer only for the configured founder id (ADR-319 amendment 2026-11-10).` Everything else in both strings stays byte-identical. Re-render locally with `bash plugins/soleur/scripts/render-c4-model.sh` (npx fetches the pinned `likec4`) before the Phase 1 commit; `plugins/soleur/test/c4-model-freshness.test.sh` passing locally gates that commit (a stale `model.likec4.json` is a merge blocker, never left to CI). Never hand-edit the JSON. Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-canonical-mirror.test.ts`, `plugins/soleur/test/c4-model-freshness.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 2 — Change 2: the push and gh disclosures (TDD)

Final strings (CTO F3 accuracy; CLO W2 approved both CTO strings unchanged; CPO W1 accepted PUSH_DISCLOSURE word for word and proposed a punctuation-only split of GH_DISCLOSURE, but stated it accepts the CTO's GH text if the CLO keeps it, which the CLO did, so the CTO text is final for both):

```ts
export const PUSH_DISCLOSURE =
  "While this is on and a session's web access is running, commands an agent runs in its sandbox have no stored credentials, so they can't push to git remotes or use stored API keys. If web access can't start for a session, that session runs as if this were off: it has no web access, and its commands keep their usual access to your connected repository, which can include pushing. An agent may still ask to push a branch to your connected repository through Soleur; nothing is pushed that way unless the workspace owner approves that push.";

export const GH_DISCLOSURE =
  "While this is on and a session's web access is running, the command-line gh tool is unavailable to agents in that session; for public repositories they still read your issues, pull requests, and CI status through Soleur, but can't create or edit them, and private repositories can't be read.";
```

2.1 RED. `test/web-egress-toggle.test.tsx`: update the independent `GH_DISCLOSURE` literal to the new text; add an independent `PUSH_DISCLOSURE` literal; assert each appears exactly once in the ON block and exactly once in the enable dialog; assert neither surface (rendered text) contains `can't push to git remotes or use stored API keys while this is on` nor `agents can't push to git remotes`; the existing content pins on GH (`gh tool is unavailable`, `public repositories`, `private repositories can't be read`) still hold and are not extended (the full-literal equality already pins every PUSH word); the "does not claim a write capability or a scope-grant gate" case still passes. Scope-grants page: the shared constants equal the ruled literals; the page imports both with the exact line `import { GH_DISCLOSURE, PUSH_DISCLOSURE } from "@/lib/web-egress-disclosure";` (the anchored regex is updated to that line); after stripping comments and strings the code holds `{PUSH_DISCLOSURE}` and `{GH_DISCLOSURE}`; the page carries no copy of either sentence and no "push to git remotes" text. `test/scope-grants-page-egress-wiring.test.ts` stubs the toggle and renders no copy (checked), so it is not edited. Also read the source of `components/settings/web-egress-toggle.tsx` and `scope-grants/page.tsx`, collapse whitespace, and assert neither contains `push to git remotes` (AC5).

2.2 GREEN. `lib/web-egress-disclosure.ts`: add `PUSH_DISCLOSURE` next to `GH_DISCLOSURE`, update `GH_DISCLOSURE`, extend the header comment (ADR-309 items 8(a) and 12; accurate in both forwarder states; approval claimed only for pushes made through Soleur; CTO/CPO/CLO 2026-11-10). Each piece goes in its own paragraph, breaking only where one ruled string ends and the next begins, never inside a constant (design-lens review: about 1,100 characters in one `text-xs` span is ~28 lines at 390 px). `components/settings/web-egress-toggle.tsx` ON block: the `<span>` becomes `<div className="flex flex-col gap-1.5 text-xs text-soleur-text-secondary">` holding `<p>On. Applies to sessions started after enabling; turning off revokes live access on the session's next dispatch.</p><p>{PUSH_DISCLOSURE}</p><p>{GH_DISCLOSURE}</p>` (the CPO-accepted placement had the timing sentence between the two constants; putting it with "On." keeps every ruled word and was flagged as taste, recorded as row PR3); enable dialog: the intro sentence, `{PUSH_DISCLOSURE}` and `{GH_DISCLOSURE}` each in its own `<p>` inside the existing container. `scope-grants/page.tsx`: the callout `<p>` becomes a `<div>` (same classes) with `<p><strong>Widens the security boundary.</strong> A compromised or prompt-injected agent could send workspace data to external hosts.</p><p className="mt-2">{PUSH_DISCLOSURE}</p><p className="mt-2">{GH_DISCLOSURE}</p>`. Check that the "exactly once in the ON block" test's selector still finds the container. The three hand-written "can't push to git remotes" phrases are removed, not kept alongside.

2.3 Sweep: `git grep -n "push to git remotes" -- apps/web-platform ':!**/*.test.*'` returns only `lib/web-egress-disclosure.ts`.

### Phase 3 — Change 3: ADR-032 sentence

Append, as the last bullet of "Amendment — 2026-11-08 (#12396)" (the file's last section), one dated sentence: `- **Accepted residual, 2026-11-10 (#12449).** Ruled by CTO agent, 2026-11-10: stated residual 2 (the ruleset's admin bypass lets an admin-credentialed \`gh pr merge --admin\` pass a parked PR) is accepted with no ruleset change, because every CODEOWNERS entry names one code owner, so a code-owner review rule would block every PR that identity authors (GitHub does not let an author approve their own PR) while the bypass stayed, and both agent merge paths are already gated by \`admin-merge-ready.sh\` and the local hook.` No other ADR-032 byte changes.

### Phase 4 — Change 4: CLO audit record and posture cell

4.1 Create `knowledge-base/legal/audits/2026-11-10-clo-ruling-approval-queue-gates-12365.md`. Frontmatter (same shape as `2026-11-07-clo-ruling-founder-acceptance-record-12197.md`): `title`, `type: legal-ruling`, `date: 2026-11-10`, `issue: 12365`, `related: [12197, 4672, 12366]`, `status: "CLO-AGENT V1 RULING, standing in for counsel on the operator's instruction. NOT a lawyer's opinion. Human-lawyer review owed."`, `ruled_by: "soleur:legal:clo agent (2026-11-10)"`, `measured_at_commit: "b258336eb5"`, `measured_against: "origin/main, not production"`, `source_sha256: "<sha256 of the extracted Rulings 3 and 4 block>"` (computed at work time from the extracted block; AC9). Body: the standing paragraph (stand-in, not a lawyer's opinion), then Rulings 3 and 4 WORD FOR WORD (source: the CLO reply, `## Ruling 3: enabling gates for a non-canary ON` through the end of `## Ruling 4`, extracted programmatically, not retyped; the session scratchpad holds an extracted copy `clo-rulings-3-4.md`; §Rulings Digest holds the headings and first lines to verify against), and nothing else (plan review cut an extra note: the PR body, decision-challenges R4/W2/L1 and #12571 already say it). No version bump, no SHA move. Run `bash scripts/lint-legal-registers.sh` (must exit 0).

4.2 `knowledge-base/legal/compliance-posture.md`, approval-queue row (the row whose first cell starts `Approval queue: public wording and enabling gate`): append the CLO's exact text from required change 2 to the LAST cell, after the round-4 `**[Superseded 2026-11-09 (review round 4), as to "as of the flag listing of 2026-11-09":]**` sentence and before the cell's closing pipe. Use the Edit tool anchored on the unique round-4 marker sentence plus the closing pipe (Edit refuses a non-unique anchor); the pipe count and exact-text checks live in AC10, not in a second validation path. Row status stays OPEN. No other line changes.

4.3 Internal legal records that change 1 makes false on merge (CLO ruling L2, 2026-11-10; this is the #7791 / PR #8153 defect class, so the PR whose merge falsifies them carries the correction): paste markers M1 to M4c from `knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/clo-register-markers.md` word for word, at the placement each names: `article-30-register.md` (M1 in the PA-40 Status cell, M2 as a blockquote in the PA-40 Addendum 2026-11-09), `compliance-posture.md` founder legal-acceptance row (M3, a different row from 4.2's), and end-of-file addenda plus frontmatter entries in `audits/2026-11-founder-legal-acceptance-attestation.md` (M4a), `legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md` (M4b) and `audits/2026-11-counsel-review-12011.md` (M4c). Use the Edit tool on unique anchors; nothing earlier in those files is edited. Then `bash scripts/lint-legal-registers.sh` and markdownlint on the five files. These are internal records, not `docs/legal`; the published trio stays unchanged.

### Phase 5 — Change 5: the counsel questionnaire

Copy the CLO's file byte-for-byte to `knowledge-base/project/questionnaires/2026-11-10-eu-data-protection-counsel-approval-queue-retention.md` (status `draft`, `needed_by: 2026-11-24`). Before copying, record the source file's sha256 in decision-challenges row R5 (AC11). Source: the session scratchpad copy; fallback the untracked file in `/data/git-repositories/jikig-ai/soleur/.worktrees/ref-12197-main/knowledge-base/project/questionnaires/` (read-only; compare sha256 of both before copying). Run `bash scripts/lint-questionnaire-identity.sh <path>` (must print `clean`) and confirm every quoted sentence still occurs in `docs/legal/` (the CLO checked byte-exactness at `b258336eb5`; the legal files are unchanged on this branch). The founder sends it; `status: sent` is the founder's edit, not this PR's.

### Phase 6 — Change 6: wireframe frame position

In `knowledge-base/product/design/approvals/approval-request.pen`, change the top-level frame with `"id": "j89zs"` from `"y": 11500` to `"y": 12300` with one Edit on the unique literal `"y": 11500` (measured: exactly one occurrence, inside `j89zs`); then `python3 -c 'import json,sys; json.load(open(sys.argv[1]))' <file>` and `--numstat` `1` added and `1` deleted (AC12). Pencil is not needed.

### Phase 7 — The Inbox legal-row e2e (orchestrator addition; CTO F2)

7.1 `e2e/mock-supabase.ts`: add `MOCK_FOUNDER = { ...MOCK_USER, id: "00000000-0000-4000-8000-0000000000f0", email: "founder@example.com" }` (synthesized; reserved example domain, `cq-test-fixtures-synthesized-only`); generalise `mintMockJwt(nowSeconds, user)`; export `MOCK_FOUNDER_SESSION` with its own access token (`sub` = founder id) and refresh token (`test-founder-refresh-token`). Give `mintMockJwt(nowSeconds, user = MOCK_USER)` a default so existing callers are untouched. `/auth/v1/user`: decode the unsigned bearer JWT's payload and return `MOCK_FOUNDER` when `sub === MOCK_FOUNDER.id`, else `MOCK_USER` (unchanged for every existing spec; keying on `sub`, not on token-string equality, because tokens embed `Date.now()` at module load and a second module instance, such as the config's import, mints different strings). `/auth/v1/token` refresh: buffer the POST JSON body and read `refresh_token` (today's handler is synchronous and never reads the body); return the founder session for `test-founder-refresh-token`, `MOCK_SESSION` for `test-refresh-token`, and 400 for anything else, so a silent identity swap fails loudly. REST defaults returning `[]`: `/rest/v1/inbox_item`, `/rest/v1/email_triage_items`, `/rest/v1/legal_acceptance` (CTO: safe; existing inbox visits render an empty inbox instead of a 500). Update the header comment.

7.2 `e2e/global-setup.ts`: also write `e2e/.auth/founder.json` (same cookie shape with `MOCK_FOUNDER_SESSION`); `e2e/.auth/` is already gitignored.

7.3 `playwright.config.ts`: add `LEGAL_ACCEPTANCE_FOUNDER_ID: "00000000-0000-4000-8000-0000000000f0"` (the literal, with a comment naming `MOCK_FOUNDER` in `e2e/mock-supabase.ts`; importing the mock into the config would load a second instance in every worker), `FLAG_APPROVAL_QUEUE: "0"` and `FLAGSMITH_ENVIRONMENT_KEY: ""` to the `e2e-auth` webServer env only, so the spec proves P1 (flag off, founder configured, row visible) instead of inheriting whatever the developer's shell exports.

7.4 New `e2e/nav-states-inbox-legal.e2e.ts` (matched by the `authenticated` project's `**/nav-states-*.e2e.ts`, ignored by `chromium`), test title naming the property: "flag off, founder configured: the Inbox legal row is visible". two `test.describe` blocks, each with its own `test.use` (a file-level `test.use` would apply to both): the founder block uses `{ storageState: "e2e/.auth/founder.json", viewport: { width: 1440, height: 900 } }`; reuse the shell route stubs the dashboard chrome needs (copy the minimal set from `nav-states-shell.e2e.ts` `beforeEach`, or extract a shared helper only if the copy exceeds ~30 lines); capture the `/api/inbox` response with `page.waitForResponse`; `page.goto("/dashboard/inbox")`; assert with independent literals: the row (`getByTestId("legal-inbox-row")`, `data-state="pending"`) is visible and has text `Acknowledge "How your decisions are recorded and kept"?`, the badge `Needs your answer`, the meta `How your decisions are recorded and kept, version 2026-11-07`; neither the full DOM (`document.documentElement.outerHTML`) nor the `/api/inbox` JSON body contains the exact hash `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`, and neither the row's `outerHTML` nor the `/api/inbox` body matches `/[0-9a-f]{64}/` (the generic scan is scoped to those two, because the dev page's RSC payload and chunk URLs carry unrelated 64-hex strings). Before the click: `await page.evaluate(() => document.fonts.ready)`, then an element screenshot of the row with `animations: "disabled"` to `test-results/inbox-legal-row-pending.png` and a viewport screenshot to `test-results/inbox-legal-row-pending-viewport.png`. Assert the row has `role="button"` first (the row sets it only when it has an href), then click it (`getByRole("button", { name: /Acknowledge "How your decisions are recorded and kept"\?/ })`), `await page.waitForURL(/\/dashboard\/approvals\/legal\/founder-acceptance-record$/, { waitUntil: "commit" })`, then assert the destination is not the not-found page: `getByTestId("legal-card")` is visible with `data-state="pending"` and `data-key="founder-acceptance-record"` (the row navigates with `router.push`, a client-side navigation with no document response to read a status from, so the card's own marker is the check). This proves the page gate also ignores the flag. All APIs used here (`waitUntil: "commit"`, `animations: "disabled"`, `scrollIntoViewIfNeeded`) exist in the installed `@playwright/test` 1.58.2 (`node_modules/playwright-core/types/types.d.ts`). The negative-control block (CTO F2) uses `{ storageState: "e2e/.auth/user.json" }` (`MOCK_USER`, not the founder): wait for the `/api/inbox` response (match `new URL(r.url()).pathname === "/api/inbox"`, which excludes `/api/inbox/emails`) with status 200, assert its JSON has no legal-kind row, wait for the rendered inbox (its empty-state or list marker), and only then assert `getByTestId("legal-inbox-row")` has count 0 (an absence assertion before the fetch lands would pass on a page that never loaded).

7.5 Run locally, after stopping any dev server already on port 3100 (`reuseExistingServer: !process.env.CI` would otherwise reuse a server without the new env; prefixing `CI=1` makes Playwright start its own and fail loudly if the port is taken): `cd apps/web-platform && CI=1 npx playwright test --project=authenticated e2e/nav-states-inbox-legal.e2e.ts`. The whole `authenticated` project runs in the PR's required `e2e` job (the default-`[]` REST stubs and the auth branch touch every spec, so that job, not a second local run on a loaded host, is the gate; AC13). Copy both screenshots to `knowledge-base/product/design/approvals/screenshots/23-inbox-legal-row-pending-e2e.png` and `23-inbox-legal-row-pending-e2e-viewport.png` and commit them as a dated snapshot; the spec is the living evidence for frame 23 (the CPO's 2026-11-10 ruling: "A Playwright screenshot of the real Inbox row … would also count"). No CPO re-attestation runs in this PR, so frame 23 stays open in the wireframe record; the decision-challenges row W3 says so.

### Phase 8 — Verification before ship

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- `cd apps/web-platform && npx vitest run test/legal-acceptance test/web-egress-toggle.test.tsx test/scope-grants-page-egress-wiring.test.ts test/inbox-tools.test.ts test/c4-code-syntax.test.ts test/c4-render.test.ts test/c4-canonical-mirror.test.ts`.
- `sha256sum apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` prints `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`.
- `git diff --quiet "$(git merge-base origin/main HEAD)" -- docs/legal plugins/soleur/docs/pages/legal apps/web-platform/server/legal-acceptance/texts` exits 0.
- `grep -n "PROVISIONAL: true" apps/web-platform/lib/legal-acceptance-copy.ts` prints one line; that file is not in the diff.
- `bash scripts/lint-legal-registers.sh`, `bash scripts/lint-questionnaire-identity.sh --all` (CI's invocation; the bare form exits 3 "not certified"), `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` (exit 0), the AC18 grep, markdownlint on the plan, tasks, decision-challenges and the new audit record.
- Archive the plan and spec in the PR (`soleur:archive-kb`) before marking ready; merge only through the merge queue after PR-attached CI is green; skip the feature tweet; after deploy, `curl -sS https://app.soleur.ai/health` must report the merge commit's `build_sha`.

## Files to Edit

- `apps/web-platform/server/legal-acceptance/surface.ts`
- `apps/web-platform/server/legal-acceptance/README.md`
- `apps/web-platform/server/legal-acceptance/inbox-rows.ts` (comment)
- `apps/web-platform/app/api/inbox/route.ts` (comment)
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx` (comments)
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/page.tsx` (comments)
- `apps/web-platform/app/api/legal-acceptance/[key]/decide/route.ts` (comment)
- `apps/web-platform/app/api/legal-acceptance/[key]/reauth/route.ts` (comments)
- `apps/web-platform/server/legal-acceptance/reauth.ts` (comment)
- `apps/web-platform/components/approvals/legal-acceptance-card.tsx` (comments)
- `apps/web-platform/test/feature-map.md`
- `apps/web-platform/test/legal-acceptance/surface.test.ts`
- `apps/web-platform/test/legal-acceptance/page.test.tsx`
- `apps/web-platform/test/legal-acceptance/routes.test.ts`
- `apps/web-platform/lib/web-egress-disclosure.ts`
- `apps/web-platform/components/settings/web-egress-toggle.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
- `apps/web-platform/test/web-egress-toggle.test.tsx`
- `apps/web-platform/e2e/mock-supabase.ts`
- `apps/web-platform/e2e/global-setup.ts`
- `apps/web-platform/playwright.config.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-319-legal-acceptance-record.md` (append)
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` (append)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (re-rendered, never hand-edited)
- `knowledge-base/legal/compliance-posture.md` (two cell appends: 4.2 approval-queue row, 4.3 founder row)
- `knowledge-base/legal/article-30-register.md` (two markers, 4.3)
- `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-attestation.md` (addendum, 4.3)
- `knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md` (addendum, 4.3)
- `knowledge-base/legal/audits/2026-11-counsel-review-12011.md` (addendum, 4.3)
- `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md` (three passages)
- `knowledge-base/product/design/approvals/approval-request.pen` (one value)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/clo-register-markers.md` (written at plan time; verbatim CLO marker text)
- `knowledge-base/legal/audits/2026-11-10-clo-ruling-approval-queue-gates-12365.md`
- `knowledge-base/project/questionnaires/2026-11-10-eu-data-protection-counsel-approval-queue-retention.md`
- `apps/web-platform/e2e/nav-states-inbox-legal.e2e.ts` (plus a shared e2e helper only if the copied shell stubs exceed ~30 lines)
- `knowledge-base/product/design/approvals/screenshots/23-inbox-legal-row-pending-e2e.png`
- `knowledge-base/product/design/approvals/screenshots/23-inbox-legal-row-pending-e2e-viewport.png`

## Not in this PR

- The docs/legal flag-status wording (CLO required change 4): only if and when the operator narrows or turns off the flag.
- `LEGAL_COPY.PROVISIONAL` stays `true`; `founder-acceptance-record.md` is untouched.
- The hook speed fix (#12449) and the base-SHA pin guard (#12366 item 3): deferred by CTO ruling; their triggers are recorded in decision-challenges rows R8.
- Migration 184's stale line comment ("life plus 5, capped at 10"): migration files are immutable.
- `dsar-export-allowlist.ts` reason string (CLO change 5, tidiness only).
- Any approval-queue flag change, Flagsmith or Doppler write.
- The flag wording in the `infra/sentry/issue-alerts.tf` and `infra/sentry/README.md` comments: any change under `apps/web-platform/infra/sentry/**` triggers `apply-sentry-infra.yml` on push to main (a full-root `terraform apply -auto-approve`), a production config write this PR must not add. Tracked in #12581; CTO ruling K3, 2026-11-10.
- **BLOCKED here, tracked in #12571:** the two published web-access sentences (PP "Agent web access" bullet and DPD 2.3(ag), plus their Eleventy mirrors) that carry the same failure-state defect as the old settings copy. Found by CLO ruling W2; the brief forbids `docs/legal` byte changes in this PR. Report it in the PR body and the session summary.

## Open Code-Review Overlap

None (94 open `code-review` issues checked against every path in Files to Edit and Files to Create).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-319 (append-only `## Amendment 2026-11-10 (#12197)`): the founder surface's trust boundary moves from "flag AND founder id" to "founder id only". Amend ADR-032 with one dated accepted-residual sentence. ADR-309 is not edited: its checklist item 8(a)/12 status is the CLO's to state (W2), and the posture cell carries the dated measurement.

### C4 views

No element, relationship or view changes. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): actors `founder` (operator) and workspace users; systems Supabase (`legalAcceptanceStore`), Flagsmith (the flag substrate, which the surface no longer reads; no `webapp -> flagsmith` edge text names the legal surface), Sentry (`storeFailed` events unchanged); relationships `webapp -> legalAcceptanceStore` and `founder -> legalAcceptanceStore`. Two description strings are falsified by the change ("Screens ship behind the approval-queue flag (PR-C)" in the `legalAcceptanceStore` description and on the `webapp -> legalAcceptanceStore` edge) and are corrected in Phase 1.9; `model.likec4.json` is re-rendered and `c4-count-parity.test.sh` must stay green (no counts change).

### Sequencing

Both ADR amendments describe the merged state; nothing is soak-gated.

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder (the operator, today the only configured founder) loses the legal screen, the Inbox "Needs your answer" row and the decide route, or, in the open direction, another signed-in user is offered the founder's acknowledgement card and can record a decision; workspace owners read settings copy that misstates whether agents can push.
- **If this leaks, the user's data is exposed via:** a non-founder decision row in `legal_acceptance` (a regulated record the published policies say exists only for the operator's account), or the founder's text hash in an Inbox payload.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one non-founder recording a legal decision would falsify the published PP 4.17 / GDPR 3.19 / DPD 2.3(aj) status sentence for one person, which is a disclosure incident on its own; the copy defect reaches every owner but misleads rather than exposes.

- **Kill switch and its latency:** unsetting `LEGAL_ACCEPTANCE_FOUNDER_ID` closes the surface for everyone; it takes effect after a Doppler change plus a redeploy (a restart is not enough), not in seconds. Before this PR the flag was a second, faster switch; after it, the founder id is the only one (CTO ruling R1).

CPO sign-off: GIVEN by the CPO agent at plan review, 2026-11-10 (copy W1, wireframe ruling 1, and this plan's User-Brand Impact). `soleur:engineering:review:user-impact-reviewer` runs at review.

**Operator follow-through (O1), for the ship summary and the resume prompt:** this PR makes narrowing or turning off the approval queue safe for the founder's legal screen; it does not do it. If the operator changes the flag, the CLO requires the published "on for every workspace" status notices to change in the same cycle (Ruling 4).

## Observability

```yaml
liveness_signal:
  what: "served build_sha on the public health endpoint after deploy; the legal surface emits no heartbeat (founder-only, pull-based)"
  cadence: "per deploy"
  alert_target: "ship/postmerge step compares build_sha to the merge commit"
  configured_in: "apps/web-platform/server/health route (existing); plugins/soleur/skills/postmerge"
error_reporting:
  destination: "Sentry (web-platform DSN, SENTRY_DSN) via reportLegalOp in server/approval/ops.ts"
  fail_loud: "one store_failed event, tags.stage=config, extra.variables=[LEGAL_ACCEPTANCE_FOUNDER_ID], once per process, when the variable is set but not a UUID"
failure_modes:
  - mode: "founder id malformed in Doppler prd"
    detection: "store_failed stage=config in Sentry on the first surface read of the process"
    alert_route: "Sentry issue (store_failed is in UNPAGED_OPS: recorded, not paged; accepted for a sole-operator surface, #12195)"
  - mode: "founder id unset (deliberate kill switch or accidental removal)"
    detection: "no Sentry event by design (surface.ts and app/api/internal/legal-acceptance/[key]/route.ts both treat unset as the dark state). The value changes only at a process start, so after a deploy an unauthenticated GET https://app.soleur.ai/api/internal/legal-acceptance/founder-acceptance-record answers 401 when configured and 503 {\"error\":\"Not available\"} when the founder id or token is unset. Between deploys: hold-gate-eval.sh reports a web-acceptance gate UNEVAL ('the check is not available right now (not switched on, or temporarily down)'), and the founder sees a 404 and no Inbox row. The counts route reads no founder id and keeps answering."
    alert_route: "postmerge step (pull, not paged); none between deploys (the dark state is not a fault, CTO ruling F1; no standing probe, residual accepted, CTO ruling K2)"
  - mode: "founder gate broken after deploy (P1 regresses in production)"
    detection: "post-deploy read-only Sentry query: no store_failed event with tags.stage=config since the deploy time, and the founder's Inbox row renders"
    alert_route: "postmerge step (pull, not paged)"
  - mode: "gate opens to a non-founder"
    detection: "unit suites surface.test.ts, routes.test.ts and page.test.tsx plus the e2e negative control fail in CI before merge"
    alert_route: "PR-attached CI (required checks)"
logs:
  where: "Sentry and Better Stack (existing web-platform sinks)"
  retention: "90 days (as published for Sentry and Better Stack)"
discoverability_test:
  # deploy liveness only: it passes on any deploy and proves nothing about this PR's failure modes;
  # the failure-mode probe is the post-deploy read-only Sentry issue search for op store_failed with
  # tag stage config, expected zero issues since the deploy time (founder id in prd is UUID-shaped).
  command: "curl -sS https://app.soleur.ai/health"
  expected_output: "build_sha"
```

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO agent rulings of 2026-11-10 (items a to d, follow-ups 1 to 4) plus planning forks F1 (config report), F2 (e2e second mock user), F3 (both disclosures false when a session's web access fails to start; corrected text). No architecture fork left open.

### Legal

**Status:** reviewed
**Assessment:** CLO agent Rulings 3 and 4 and required changes 1 to 3 of 2026-11-10; wording ruling W2 approved both disclosures unchanged. No `docs/legal` byte changes; no published sentence ties the legal screens to the flag (checked in the trio). W2 also found two PUBLISHED sentences with the same failure-state defect (PP "Agent web access (opt-in; migration 158, #9534)" bullet: "While enabled, sessions run without stored credentials in-sandbox."; DPD 2.3(ag): "While enabled, sandboxed agent commands carry no stored credentials …"; both mirrored). They are already inaccurate in production and are not made untrue by this PR; editing them is BLOCKED here by the no-`docs/legal`-change constraint and is tracked in #12571 (CLO to rule the wording; re-pin `legal-doc-shas.ts`).

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no new UI surface: copy-only edits to existing components, which `ui-surface-terms.md` excludes "Pure copy or style tweaks with no structural/layout change"; the CPO ruled no new .pen frame is needed; the frame 23 position edit is a JSON value change)

#### Findings

The mechanical glob override matches `components/settings/web-egress-toggle.tsx` and `scope-grants/page.tsx`, but both edits replace text inside existing blocks with no structural change. The CPO accepted the CTO's PUSH_DISCLOSURE word for word and GH_DISCLOSURE either with a punctuation-only split or as the CTO wrote it if the CLO kept it (the CLO did), required the same two strings on all three surfaces, and asked for a phone-width QA check that the longer ON block and callout wrap and the dialog still scrolls (added to Test Scenarios).

## Rulings Digest

Fallback copy of the inputs the work phase needs if the session scratchpad is gone (the scratchpad copies are authoritative for verbatim text).

- CLO Ruling 3 heading: `## Ruling 3: enabling gates for a non-canary ON`; first line `**Ruled by CLO agent, 2026-11-10:** No. The gates as a set cannot be discharged now, and a non-canary ON is still not permitted. Evidence is from the repository at \`b258336eb5\`, not from production.`; a table of gates (a) to (k) with Evidence and Status columns; closing paragraph "One more ADR-309 precondition is also not met: checklist item 8(a). …".
- CLO Ruling 4 heading: `## Ruling 4: the published "on for every workspace" statement`; first line `**Ruled by CLO agent, 2026-11-10:** It stays as published, unchanged, while the flag is on.` and three bullets.
- CLO required change 2 (posture cell append) begins `**[Ruled by CLO agent, 2026-11-10 (#12365; v1 position standing in for counsel, human review owed; recorded by the pull request that carries it and effective on its merge):` and ends `discharged as to its text by the 2026-11-10 ruling; no other gate changes.`
- PUSH_DISCLOSURE and GH_DISCLOSURE: the final strings in Phase 2 (CTO F3 text, approved unchanged by CLO W2; CPO W1 accepts it once the CLO keeps the CTO punctuation).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "legal-acceptance surface gates on LEGAL_ACCEPTANCE_FOUNDER_ID only, decoupled from the approval-queue flag, with tests, README and an ADR-319 amendment" [brief] | Phase 1 | mapped |
| 2 | "PUSH_DISCLOSURE constant replacing three false \"agents can't push to git remotes\" sentences in the web-egress toggle and scope-grants page, with tests" [brief] | Phase 2 | mapped |
| 3 | "one dated sentence in ADR-032's 2026-11-08 amendment accepting the parked-hold admin-bypass residual" [brief] | Phase 3 | mapped |
| 4 | "CLO audit record knowledge-base/legal/audits/2026-11-10-clo-ruling-approval-queue-gates-12365.md plus the compliance-posture.md approval-queue cell append" [brief] | Phase 4 | mapped |
| 5 | "the counsel questionnaire under knowledge-base/project/questionnaires/ (status draft)" [brief] | Phase 5 | mapped |
| 6 | "move frame j89zs in approval-request.pen from y 11500 to y 12300" [brief] | Phase 6 | mapped |
| 7 | "record them in knowledge-base/project/specs/feat-one-shot-12197-leader-rulings-surface-decouple/decision-challenges.md" [brief] | Phase 0 | mapped |
| 8 | "include ONE browser e2e that renders the Inbox legal row" [orchestrator addition] | Phase 7 | mapped |
| 9 | "if change 1 makes any published sentence untrue, flag that part in the plan as blocked and report it" [brief] | Research Reconciliation row 8 ("Published legal text might state the card is flag-gated"; row 6 records the separate #12571 block) | mapped (nothing blocked) |
| 10 | "archive the plan and spec inside the PR; after deploy check the served build_sha" [brief] | Phase 8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| routes.test.ts edits | — | inferred — justification: the brief's test list misses a suite that goes red when the flag read is removed |
| Comment/README/page-name sweep (1.6, 1.7) | "with tests, README" | asked (README); the comments are inferred — justification: they would state a gate the code no longer has |
| C4 `model.c4` + `model.likec4.json` | — | inferred — justification: two model descriptions become false; the plan skill's architecture gate (soleur:plan Phase 2.10) makes the C4 update a deliverable of the change (implemented in this plan's Phase 1.9) |
| GH_DISCLOSURE correction | — | inferred — justification: CTO ruling F3 (same defect, ADR-309 item 12 binds the toggle copy as a whole); CPO and CLO ruled the wording |
| Config report rule (F1) | — | inferred — justification: removing the flag read changes when the existing report fires; CTO ruled the shape |
| Frame 23 screenshot commit | "Take a screenshot artifact in the test (it doubles as the rendered evidence for frame 23's re-attestation)" | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform` (server, app, components, lib, e2e, test), `knowledge-base/engineering/architecture`, `knowledge-base/legal`, `knowledge-base/project`, `knowledge-base/product/design`
- Planned files: 40 | Estimated changed lines: about 850
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the brief requires ONE PR (draft #12567); commits are ordered per change so each reverts independently (recorded as `operator (scope)` row O5).

## Acceptance Criteria

AC numbers are stable ids, not order (rows were added at plan review).

### Pre-merge

1. `git grep -nE '^import .*approval/flag|isApprovalQueueEnabled\(' -- apps/web-platform/server/legal-acceptance` returns nothing (import and call lines only, so README or comment prose that names the function does not trip it).
2. `surface.test.ts` has a case where the flag mock returns `false` and `isLegalSurfaceEnabled(FOUNDER)` is `true`; it passes.
3. Unset founder id produces zero `storeFailed` calls; `"not-a-uuid"` produces exactly one across repeated calls (surface and page suites).
4. `routes.test.ts` asserts, for both reauth and decide, that the route proceeds past the guard with the flag off and the founder configured, that a live intent with the flag off still records on decide, and that it 404s with the founder id unset.
5. `git grep -n "push to git remotes" -- apps/web-platform ':!**/*.test.*'` lists only `apps/web-platform/lib/web-egress-disclosure.ts`, and a test in `web-egress-toggle.test.tsx` reads the source of `web-egress-toggle.tsx` and `scope-grants/page.tsx`, collapses whitespace, and asserts neither contains `push to git remotes` (the old copy wrapped across JSX lines, which a line grep cannot see).
6. `test/web-egress-toggle.test.tsx` pins both ruled literals independently, asserts each appears exactly once in the ON block and once in the dialog, and asserts the scope-grants page imports both constants and renders `{PUSH_DISCLOSURE}` and `{GH_DISCLOSURE}`.
7. The last level-2 heading line of ADR-319 starts `## Amendment 2026-11-10 (#12197)`, and `git diff --numstat <merge-base> -- <ADR-319>` shows 0 deletions. ADR-032: `--numstat` shows 0 deletions and the added line is one bullet.
8. `model.c4` contains neither `Screens ship behind the approval-queue flag` nor `checked before the flag is read`; `c4-model-freshness.test.sh`, `c4-count-parity.test.sh`, `c4-code-syntax.test.ts`, `c4-render.test.ts` pass.
9. The audit record exists with `measured_at_commit: "b258336eb5"`, carries `source_sha256:` in its frontmatter (the sha256 of the Rulings 3 and 4 block as extracted from the CLO reply at work time), the ruling section's sha256 equals that recorded value, and `bash scripts/lint-legal-registers.sh` exits 0.
10. `compliance-posture.md` diff vs merge-base is two changed lines (the approval-queue row and the founder row), each row's pipe count is unchanged, and the appended texts equal the CLO's required change 2 and marker M3 exactly.
22. Each of M1 to M4c appears exactly once (`grep -cF` on a distinctive substring of each) in its target file; `git diff --numstat <merge-base>` shows deletions only on the three in-cell rows (M1 in `article-30-register.md`; M3 and the 4.2 approval-queue row in `compliance-posture.md`) and 0 deletions in the three addendum files except the one-line frontmatter `addenda:` array in the LIA and the counsel-review record, where adding the CLO's new element rewrites that single line (1 deletion each, the array line only; amended at work time, 2026-11-10); `bash scripts/lint-legal-registers.sh` exits 0.
11. `sha256sum` of the questionnaire file equals the value recorded in decision-challenges row R5 at work time (the CLO draft's sha256), it has `status: draft`, and `bash scripts/lint-questionnaire-identity.sh --all` prints `clean`.
12. `approval-request.pen` parses as JSON; frame `j89zs` has `y == 12300`; `git diff --numstat <merge-base> -- <pen>` prints `1` added and `1` deleted.
13. `npx playwright test --project=authenticated e2e/nav-states-inbox-legal.e2e.ts` passes locally; the PR's required `e2e` job (whole `authenticated` project) is green; the negative control (non-founder storage state) shows no legal row; after the click `legal-card` renders in `data-state="pending"`.
14. Hard constraints hold: `founder-acceptance-record.md` sha256 = `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`; no diff vs merge-base under `docs/legal`, `plugins/soleur/docs/pages/legal`, `apps/web-platform/server/legal-acceptance/texts`; `apps/web-platform/lib/legal-acceptance-copy.ts` not in the diff (`PROVISIONAL: true` stays).
15. `decision-challenges.md` has one row per ruling listed in Phase 0, every technical row starting `Ruled by CTO agent, 2026-11-10:` or `Ruled by CLO agent, 2026-11-10:`.
16. PR body contains `Ref #12197`, `Ref #12365`, `Ref #12366`, `Ref #12449` and no closing keyword for them; no comment is posted on those issues.
18. `git grep -nE "flag AND|flag off, not the founder|while the flag is on|the flag read or|[Ff]lag off|flag-off|flag were off|in this order: flag|check founder, flag|because the flag is global" -- apps/web-platform/server/legal-acceptance ':!apps/web-platform/server/legal-acceptance/texts' apps/web-platform/app/api/legal-acceptance 'apps/web-platform/app/(dashboard)/dashboard/approvals/legal' apps/web-platform/app/api/inbox apps/web-platform/components/approvals/legal-acceptance-card.tsx apps/web-platform/test/feature-map.md knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md` returns nothing.
19. `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.

### Post-merge

17. `curl -sS https://app.soleur.ai/health` reports the merge commit's `build_sha` (deploy liveness).
21. An unauthenticated `curl -sS -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/internal/legal-acceptance/founder-acceptance-record` prints `401` (founder id and token configured after the deploy; 503 would mean the kill switch is set, CTO ruling K2).
20. A read-only Sentry issue search for `store_failed` with tag `stage:config` returns no issue first seen after the deploy time (the failure-mode probe for P1/F1).

## Test Scenarios

- Founder, flag mocked off → card page renders the pending card; Inbox loader returns the row; decide route proceeds.
- Non-founder, flag mocked on → 404 / no row / 404 (unchanged).
- Founder id unset → closed for everyone, no Sentry event; the founder's recorded rows still render read-only.
- Founder id malformed → closed for everyone, one Sentry `store_failed` (stage `config`) per process.
- Settings toggle ON block, enable dialog and scope-grants callout each show PUSH_DISCLOSURE and GH_DISCLOSURE once and no "can't push to git remotes … while this is on" phrase; at 390×844 the page has `document.documentElement.scrollWidth <= 390`, each disclosure is its own paragraph, and the dialog's confirm button is in the viewport after `scrollIntoViewIfNeeded()` (the dialog is an inline alertdialog with no inner scroll; CPO QA note, design-lens review). Phone-width screenshots of the ON block, dialog and callout are QA evidence at review, not committed.
- e2e (flag off, founder configured): founder session sees the pending legal row with the ruled title, badge and meta, the exact text hash appears in neither the row nor the `/api/inbox` payload, and the click lands on `/dashboard/approvals/legal/founder-acceptance-record` with `legal-card` in `data-state="pending"`; default session sees no legal row.
- Non-owner render of the scope-grants page: unchanged by this PR (the callout's audience is decided by the existing page); covered by the existing `scope-grants-page-egress-wiring` test, not extended.

## Dependencies & Risks

- **likec4 CLI for the C4 re-render** (pinned version + `--before` date in `render-c4-model.sh`): it must run locally before the Phase 1 commit (Phase 1.9 gate); if npx cannot fetch it, stop and report rather than commit a stale `model.likec4.json`; never hand-edit it.
- **Host load** (CTO measured load 57 to 102 on 16 cores; another worktree is running `test-all.sh`): run vitest by file list and the e2e by spec first; a runner crash goes through `wg-when-a-test-runner-crashes-segfault-oom`.
- **e2e flake on the cold dev-server compile** of `/dashboard/inbox`: the `authenticated` project already allows 60 s per test and 45 s navigation; the click wait uses `waitUntil: "commit"` so the destination page's render is not part of the assertion.
- **Founder id in Doppler prd** is UUID-shaped (CTO checked shape only); after deploy the surface keeps working for the founder with no flag dependency. No production write is needed to ship.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The anchored import regex in `test/web-egress-toggle.test.tsx` breaks on a combined import; update it in the same commit as the page import.
- `decision-challenges.md` technical rows are machine-gated by `technical-ruling-gate.sh`: each must start exactly `Ruled by CTO agent, 2026-11-10:` or `Ruled by CLO agent, 2026-11-10:` (no parenthetical before the colon), and an operator class must match `operator (<one-word-or-hyphenated>)`.
- The posture cell is a single ~9.5 kB table line; edit it with the Edit tool anchored on the unique round-4 marker sentence plus the closing pipe, never by a heading- or substring-keyed splice that could match the cell's own quoted text; AC10 checks the pipe count after.
- The ADR-032 append lands at the end of the file (the amendment is its last section); confirm no trailing section was added on `main` before appending (`git fetch` and re-read at work time).
- Run markdownlint on the plan, `tasks.md` and `decision-challenges.md` before committing.
