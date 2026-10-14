---
title: "fix: Correct stale legal rationale for operator-cc-oauth (CLO re-review after Anthropic paused the June 15 credit change)"
date: 2026-06-16
type: fix
status: draft
lane: cross-domain
branch: feat-one-shot-correct-cc-oauth-legal-rationale
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related:
  - PR #4824 (feat-operator-cc-oauth — the feature being re-documented)
  - knowledge-base/project/brainstorms/2026-06-02-operator-cc-subscription-auth-brainstorm.md
  - apps/web-platform/server/byok-lease.ts
  - https://support.claude.com/en/articles/15036540
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- This plan provisions NO infrastructure. It edits two server comment blocks, one
     .env.example comment, and two knowledge-base markdown docs. The only "infra"-adjacent
     mention is a Sharp Edge instructing the implementer NOT to author a manual
     container-restart step, because the existing path-filtered web-platform-release.yml
     pipeline already redeploys on merge to main. No terraform-architect routing is needed. -->

# fix: Correct stale legal rationale for operator-cc-oauth

🐛 / 📚 Documentation + comment correction. **No runtime behavior change.**

## Enhancement Summary

**Deepened on:** 2026-06-16
**Sections enhanced:** Files to Edit §1 (byok-lease comment sites), Acceptance Criteria, Research Insights
**Agents used:** comment-analyzer (comment-correctness), Explore (verify-the-negative on the no-runtime-change claim)

### Key Improvements
1. **Named the exact stale phrases.** `policy gate` appears at byok-lease.ts **line 87
   AND line 494** (verified). Both fold the same "permitted-on-date" framing and both
   must be re-framed — the plan's AC greps `policy gate`, so missing either fails CI.
   The edit bullets now name them explicitly instead of "any inline comment."
2. **Pinned the message-string trap.** The `OauthNotYetPermittedError` message at line 95
   contains the word `permitted`; it is runtime-coupled (derived from the constant) and
   MUST NOT be reworded. The edit bullet now restricts to lines 84-89 (doc-comment) and
   warns off the 90-103 class body.
3. **Added a comment-rot guard.** In-file comments must reference symbols, not hard line
   numbers — the comment expansion shifts every downstream `throw`-site line.

### Verified-live (deepen-pass grounding)
- PR #4824 is **MERGED** (2026-06-02), titled "feat(byok): operator Claude Code
  subscription oauth_token credential"; commit `b31884f6f`. ✓
- byok-lease.ts symbol lines exact: `CC_OAUTH_EFFECTIVE_DATE`=70, `isCcOauthEnabled`=79,
  `OauthNotYetPermittedError`=90, `OauthDelegationForbiddenError`=110; firing sites
  `Date.now() < CC_OAUTH_EFFECTIVE_DATE`=495, `throw OauthNotYetPermittedError`=496,
  `throw OauthDelegationForbiddenError`=504. ✓
- **No-runtime-change / suite-safe claim HOLDS:** the only readers of
  `CC_OAUTH_EFFECTIVE_DATE` are byok-lease.ts (`:70`,`:96`,`:495`) and the test (`:65`,
  `:76`,`:77`,`:159`). All oauth-error tests assert `toBeInstanceOf` on the CLASS
  (`byok-lease-credential-type.test.ts:154,179,196`), never the message string or comment
  prose. No test pins `"not permitted before"` / `"policy gate"` / `"legal floor"`. A
  comment-only edit cannot break the suite. ✓
- `web-platform-release.yml` is path-filtered `push: paths: ['apps/web-platform/**']` —
  the post-merge auto-deploy of the already-set `CC_OAUTH_ENABLED=1` Doppler value is
  real, not assumed. ✓
- Cited AGENTS rule ids (`hr-all-infrastructure-provisioning-servers`,
  `hr-weigh-every-decision-against-target-user-impact`) are active (not fabricated/retired). ✓
- Deepen halt gates 4.6 (User-Brand Impact + valid threshold), 4.7 (Observability,
  pure-docs skip), 4.8 (no PAT-shaped var), 4.9 (no UI surface) all PASS.

## Overview

PR #4824 (merged 2026-06-02, commit `b31884f6f`) shipped the operator-only Claude
Code subscription OAuth credential (`oauth_token`, `provider='anthropic_oauth'`).
The legal rationale for that feature was built on a **predicted Anthropic policy
transition**: that on **2026-06-15**, support article 15036540 would grant Pro/Max/
Team/Enterprise plans a per-user monthly "Agent SDK credit" that *"explicitly permits"*
third-party apps to authenticate with a Claude subscription — lifting Consumer Terms
§3's automated-access bar. The CLO verdict was therefore framed as
**"permitted-with-guardrails on/after June 15, 2026"**, and the date `2026-06-15` was
documented across the code + env + brainstorm as a **legal floor** — "the date the
conduct becomes permitted."

On **2026-06-16** Anthropic emailed that this change is **PAUSED**. The live article
now reads:

> **Update June 15:** We're pausing the changes... For now, nothing has changed:
> Claude Agent SDK, `claude -p`, and third-party app usage still draw from your
> subscription's usage limits.

The predicted permission never landed. The date gate is now **spent** — the date has
passed and corresponds to **no policy transition**. The CLO re-review verdict
(2026-06-16) is:

- **AMBIGUOUS, leaning tolerated** (NOT explicitly-permitted) for the owner-only
  operator-self-use construction.
- The **real risk axis** — the per-user / no-pooling / no-share constraint — **survived
  intact** in the paused article and is **enforced in code** by the owner-only routing
  guardrail (`OauthDelegationForbiddenError`).
- Legal basis **downgraded** from "permitted" to **"tolerated / metered subscription
  use, owner-only no-share enforced in code, operator-borne risk-acceptance."**
- **Disabling is NOT mandatory.** The operator has elected to **keep it enabled** as
  documented risk-acceptance.

This change corrects the now-false framing across four surfaces so the documented
rationale matches reality, and records the re-review verdict as a durable legal audit.
**It is a comments/rationale + docs change only — the date constant, the fail-closed
logic, and all runtime behavior stay exactly as-is.**

This is **not** a re-litigation of whether the feature should exist. It is a
correctness fix on the *recorded justification* for a feature that already shipped and
stays on.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|-------|--------------------|---------------|
| `CC_OAUTH_EFFECTIVE_DATE` is at `byok-lease.ts:70`; `OauthNotYetPermittedError` at `:90`; `OauthDelegationForbiddenError` at `:110`; kill-switch `isCcOauthEnabled` at `:79` | Confirmed at those lines | Comment-only edits at each site; no symbol rename |
| `.env.example` `CC_OAUTH_ENABLED` block at lines 45-54, default `0` | Confirmed (`=0` at :54, comment block :45-53) | Rewrite comment block; keep `=0` default verbatim |
| Brainstorm contains original CLO verdict "permitted-with-guardrails on/after June 15" | Confirmed (`:48`, `:109`-`:119`, Decision 4 `:60`, Open Q4 `:80-81`) | Append dated Re-review section; mark original superseded; do NOT delete |
| `knowledge-base/legal/audits/` exists with `type: counsel-review`-style frontmatter + `draft_notice` + `re_evaluation_triggers` convention | Confirmed (e.g. `2026-06-15-clo-presend-review-listicle-outreach-5314.md`, `2026-06-counsel-review-5037.md`) | New audit file matches this frontmatter contract |
| Date constant MUST NOT change — `byok-lease-credential-type.test.ts:76-77` derives `BEFORE_DATE`/`AFTER_DATE` from `CC_OAUTH_EFFECTIVE_DATE`; AC3 (`:143`) asserts `OauthNotYetPermittedError` `instanceof` | Confirmed: test imports the constant + error class; pins behavior, NOT comment prose | Keep constant value, keep error class + `instanceof`, keep date-gate logic byte-for-bit. Only the *constant's doc-comment* and *error-class doc-comment* prose change. No test reads comment text → comment edits are suite-safe |
| Premise "Anthropic granted the June 15 credit" | **STALE** — paused per 2026-06-16 email + live article | This entire change exists to correct the stale premise |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing functional — this is a
docs/comment change. The failure mode is *informational*: the codebase and KB would
continue to assert a **false legal basis** ("permitted as of June 15") that a future
operator/auditor/counsel relies on, leading them to believe the conduct is
explicitly-permitted when it is only tolerated-with-risk. A stale "permitted" claim
is a worse liability than an honest "tolerated / risk-accepted" one.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no data path,
secret, schema, or auth surface is touched. The operator's `oauth_token` exposure
surface is unchanged from PR #4824 (same HKDF encryption, same owner-only routing).
The *risk-acceptance* this change documents was already live; this change only records
it accurately.

**Brand-survival threshold:** single-user incident (the "user" is the operator's own
Claude Max account; the documented-risk axis is the operator's own ToS posture /
account-ban exposure if the owner-only guardrail were ever defeated — which this change
does not touch).

> **Note:** the threshold is inherited verbatim from the brainstorm
> (`brand_survival_threshold: single-user incident`, `user_brand_critical: true`). This
> doc-correction does not *change* the threshold; it carries it forward because the
> underlying feature's risk posture is what is being re-documented. **CPO sign-off at
> plan time:** confirm CPO has reviewed (or carry forward the brainstorm triad
> CPO+CLO+CTO framing — the brainstorm already ran the triad). `user-impact-reviewer`
> will be invoked at review-time per the review skill's conditional-agent block.

## Why this change is safe (the load-bearing invariant)

The runtime guardrail stack is **unchanged**:

1. **Kill-switch** `CC_OAUTH_ENABLED` (`byok-lease.ts:79`) — feature inert when off.
2. **Owner-only routing** `OauthDelegationForbiddenError` (`:110`, fired at `:500-505`)
   — the per-user/no-share constraint, which is the surviving real risk axis.
3. **Date gate** `OauthNotYetPermittedError` (`:90`, fired at `:495-497`) — kept
   byte-for-bit. **We do NOT remove it.** Removing the fail-closed branch would be a
   runtime change and would risk the test suite (AC3). We only re-frame *what the date
   means*: it is no longer a "legal floor" but a **spent gate** — a now-passed boundary
   that no longer corresponds to any policy transition. Because today (2026-06-16) is
   already past `2026-06-15`, the gate is permanently satisfied and is effectively a
   historical artifact; the live load-bearing gates are #1 and #2.

The corrected legal basis stated everywhere: **tolerated / metered subscription use;
owner-only, no-share enforced in code; operator-borne risk-acceptance.**

## Files to Edit

### 1. `apps/web-platform/server/byok-lease.ts` (comments/rationale ONLY)

Edit the doc-comments at three sites. **Do not touch any executable line, the constant
value, the error-class names, or the fail-closed branches.**

- **Lines 64-70** — `CC_OAUTH_EFFECTIVE_DATE` doc-comment. Currently frames it as "CLO
  Guardrail 1 ... fails closed before this instant ... date gate." Re-frame: this is a
  **spent date gate** — it was gated to a *predicted* 2026-06-15 Anthropic policy
  transition that Anthropic **paused** (see audit
  `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`). The date has
  passed and no longer corresponds to any policy change. The constant is retained as a
  historical fail-closed artifact (and because the lease test derives its before/after
  boundaries from it); the **live** load-bearing gates are the `CC_OAUTH_ENABLED`
  kill-switch + owner-only routing (`OauthDelegationForbiddenError`). Legal basis:
  tolerated/metered subscription use, owner-only no-share enforced in code,
  operator-borne risk-acceptance. Keep the `export const ... = Date.parse(...)` line
  unchanged.
- **Lines 84-89** (doc-comment ONLY — the class body is 90-103) — `OauthNotYetPermittedError`
  doc-comment. Currently "CLO Guardrail 1 — raised when ... selected before
  CC_OAUTH_EFFECTIVE_DATE ... the conduct becomes permitted." Re-frame: this guard fires
  only for runs whose clock is before the spent date; since the date has passed it is now
  historically inert, but is **retained fail-closed** (never silently falls back to the
  api_key). Drop the "the date the conduct becomes permitted" framing. **Must also
  re-frame the phrase `defeat the policy gate` on line 87** (the comment-analyzer found
  it folds the same stale framing — and the AC greps for `policy gate`). **Keep the
  class, the constructor, and the date-derived message string at lines 90-103 unchanged**
  — in particular **do NOT reword the runtime message string at line 95** (`...is not
  permitted before <date>`); it derives from the constant, the test relies on the class
  + `instanceof` not the message, and rewording it is a runtime change. The `84-103`
  range is the trap: edit only 84-89.
- **Lines 105-117** — `OauthDelegationForbiddenError` doc-comment. Strengthen: note this
  is the **surviving load-bearing guardrail** that enforces Anthropic's per-user /
  no-pooling / no-share constraint — the real risk axis that did NOT change when the
  June 15 credit was paused. This is the gate the corrected "tolerated, owner-only,
  no-share enforced in code" basis rests on. Keep the class + message unchanged.
- **Lines 318-329 + 492-505** (`getAgentCredential` JSDoc + the inline `---- Gates fire
  ONLY on the oauth read ----` comment block) — update the inline comments that frame the
  date as a permission gate. **Specifically re-frame the phrase `defeat the policy gate`
  on line 494** (the second of the two `policy gate` occurrences; the AC depends on both
  being gone). The line-498-499 `CLO G2 — owner-only routing` inline comment already
  describes the surviving guardrail accurately — leave it (or lightly strengthen). Do NOT
  alter the `@throws` contract lines at 323-326 (they document real fail-closed behavior,
  not a legal-floor claim) or any executable line.

**Comment-rot guard (apply to ALL three byok-lease edits above):** the rewritten
in-file comments will be *longer* than the originals, which shifts every downstream
line. Reference **symbols** (`OauthDelegationForbiddenError`, `isCcOauthEnabled`,
`fetchAgentCredentialIntoSlot`, `CC_OAUTH_ENABLED`) — **never hard line numbers** — inside
byok-lease.ts comments, so the expansion does not plant fresh stale `:NNN` cross-refs.
(The `.md` audit/brainstorm files MAY keep line numbers — they are dated artifacts that
rot independently.)

**Constraint reminder for /work:** after editing, run
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and the lease test
(`./node_modules/.bin/vitest run test/byok-lease-credential-type.test.ts`) to prove
comment-only edits did not perturb behavior. A `git diff -w` should show only
comment-line changes.

### 2. `apps/web-platform/.env.example` (comment block lines 45-54)

Rewrite the `CC_OAUTH_ENABLED` comment block (lines 45-53). Drop the line
`# Set to "1" ONLY on/after 2026-06-15 (the CLO-gated effective date; the` and its
continuation. Replace with the corrected basis: this kill-switch is the live on/off
control; the legal basis for enabling it is **tolerated/metered subscription use,
owner-only (no-share) enforced in code, operator-borne risk-acceptance** (not the
once-predicted June-15 permission, which Anthropic paused — see
`knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`). Keep the
`ADMIN_USER_IDS` combine-note and the "lease enforces the date independently" mechanical
note (still true). **Keep the default `CC_OAUTH_ENABLED=0` line at :54 verbatim** — the
live Doppler dev+prd values are already `1` out-of-band; the example default stays off.

### 3. `knowledge-base/project/brainstorms/2026-06-02-operator-cc-subscription-auth-brainstorm.md`

Append a new dated section (do NOT delete or rewrite the original verdict; mark it
superseded):

- Add `## Re-review 2026-06-16 — Anthropic paused the June 15 credit change` after the
  existing `## Domain Assessments` / `## User-Brand Impact` content (place near the end,
  before or after `## Lane`).
- In the section: quote the paused-article text verbatim (the "Update June 15: We're
  pausing the changes... still draw from your subscription's usage limits." passage).
- State the superseding verdict: original "permitted-with-guardrails on/after June 15"
  (Domain Assessments → Legal, `:109`-`:119`) is **SUPERSEDED**; new verdict is
  **AMBIGUOUS, leaning tolerated** (owner-only operator-self-use); basis downgraded
  permitted → tolerated risk-acceptance; disabling NOT mandatory; kept enabled as
  documented risk-acceptance.
- Update the **re-review trigger**: replace the old Open-Q4 / Legal trigger ("any
  amendment to article 15036540 / the Consumer Terms") with: *"Anthropic un-pauses /
  ships its promised advance-notice update, OR amends the 'still draw from your
  subscription limits' sentence, OR any move off owner-only self-use."*
- Mark the original verdict superseded **in place** with a short pointer — e.g. add a
  one-line `> **[SUPERSEDED 2026-06-16 — see Re-review section below]**` annotation
  immediately under the Decision-4 row note (`:60`), the Legal Summary (`:109`), and
  Open Question 4 (`:80`). Do not strike the prose; leave it readable as the historical
  record.
- Link to the new audit file `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`.

## Files to Create

### 4. `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`

A draft internal legal assessment recording the full CLO re-review. Match the existing
audit frontmatter contract (see `2026-06-counsel-review-5037.md` /
`2026-06-15-clo-presend-review-listicle-outreach-5314.md`):

```yaml
---
title: "CLO re-review — operator Claude Code subscription OAuth (Anthropic paused the June 15 Agent SDK credit)"
type: counsel-review
date: 2026-06-16
related_pr: 4824
related_branch: feat-one-shot-correct-cc-oauth-legal-rationale
artifact: apps/web-platform/server/byok-lease.ts (operator-cc-oauth / oauth_token credential)
brand_survival_threshold: single-user incident
status: DRAFT (CLO-agent-attested, Soleur-as-tenant-zero v1 internal assessment)
disposition: AMBIGUOUS-LEANING-TOLERATED — keep enabled as documented risk-acceptance
reviewed_by: "CLO agent (v1 internal counsel-review attestation, Soleur-as-tenant-zero posture)"
operator: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "Anthropic un-pauses / ships its promised advance-notice update; OR amends the 'still draw from your subscription's usage limits' sentence; OR any move off owner-only operator-self-use (e.g. delegation, customer-facing, pooling)"
draft_notice: "Draft internal legal guidance for a non-lawyer founder. NOT a substitute for licensed external counsel."
---
```

Body sections:

1. **What changed (the trigger).** The 2026-06-02 verdict was conditioned on a predicted
   June-15 Agent SDK credit. Anthropic emailed 2026-06-16 that the change is paused;
   quote the live article text verbatim. The premise that "the conduct becomes
   explicitly-permitted on June 15" is now false.
2. **The 5 answered questions** (the core of the audit):
   - **Q1 — Permitted, prohibited, or ambiguous?** → **AMBIGUOUS, leaning tolerated**
     (NOT explicitly-permitted) for the owner-only operator-self-use construction. The
     paused article's "still draw from your subscription's usage limits" is metered
     tolerance, not an explicit permission lifting Consumer Terms §3's automated-access
     bar.
   - **Q2 — Does the pre-June-15 analysis still control?** → **No.** The original analysis
     turned on the *predicted permission*; that did not land. But the part that *did*
     survive intact is the **per-user / no-pooling / no-share constraint** — the real
     risk axis — which the paused article still imposes.
   - **Q3 — Must the feature be disabled?** → **No, disabling is NOT mandatory.** The
     conduct is tolerated/metered, owner-only is enforced in code, and the operator
     bears the (small, owner-self-use) residual risk. The operator has elected to keep
     it enabled as documented risk-acceptance.
   - **Q4 — Is the owner-only boundary unchanged?** → **Yes, unchanged and still
     load-bearing.** `OauthDelegationForbiddenError` (`byok-lease.ts:110`, fired at
     `:500-505`) enforces it fail-closed. This is the gate the entire tolerated basis
     rests on.
   - **Q5 — New re-review trigger?** → "Anthropic un-pauses / ships its promised
     advance-notice update, OR amends the 'still draw from your subscription limits'
     sentence, OR any move off owner-only self-use."
3. **Basis downgrade (recorded).** permitted → **tolerated risk-acceptance**; one
   paragraph on what "tolerated" means here (metered subscription use that Anthropic's
   own paused article describes as still drawing from subscription limits; no explicit
   blessing, no explicit prohibition for owner-self-use; the prohibited construct
   remains pooling/sharing/non-owner runs, which code blocks).
4. **Recommended-actions table** (Action | Status | Owner):

   | Action | Status | Owner |
   |--------|--------|-------|
   | Correct byok-lease.ts comments (spent-date-gate framing) | this PR | eng |
   | Correct .env.example CC_OAUTH_ENABLED basis | this PR | eng |
   | Supersede brainstorm verdict (do not delete) | this PR | eng |
   | Record this audit | this PR | clo |
   | Keep `CC_OAUTH_ENABLED=1` in Doppler dev+prd | already set out-of-band | operator |
   | Keep owner-only routing guardrail fail-closed | unchanged (no action) | eng |
   | Re-review on un-pause / article amendment / any non-owner extension | watch | clo |

5. **Draft notice / not-a-substitute-for-counsel disclaimer** (also in frontmatter
   `draft_notice`).

**Provenance verification (do at /work-write time):** `gh pr view 4824 --json title` to
confirm the cited PR is the operator-cc-oauth feature before pinning `related_pr: 4824`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `byok-lease.ts` doc-comments no longer describe `2026-06-15` as a "legal floor",
      "the date the conduct becomes permitted", or a "policy gate" that confers
      permission. Verify: `grep -nE "becomes permitted|legal floor|policy gate" apps/web-platform/server/byok-lease.ts` returns no match in the oauth comment blocks.
- [ ] `byok-lease.ts` comments state the corrected basis (tolerated / owner-only
      no-share enforced in code / operator risk-acceptance) and cite the audit file.
      Verify: `grep -nE "tolerated|risk-acceptance|2026-06-16-clo-re-review-cc-oauth" apps/web-platform/server/byok-lease.ts` returns matches.
- [ ] **No runtime change in byok-lease.ts:** `git diff -w apps/web-platform/server/byok-lease.ts`
      shows only comment lines (lines beginning with `*`, `//`, `/*`, or inside block
      comments); the `CC_OAUTH_EFFECTIVE_DATE = Date.parse("2026-06-15T00:00:00Z")` line
      is unchanged; the two error classes + their messages + the `Date.now() < CC_OAUTH_EFFECTIVE_DATE`
      / `OauthDelegationForbiddenError` branches are unchanged.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/byok-lease-credential-type.test.ts`
      passes unchanged (AC3 date gate + owner-only still green — proves no behavior
      change).
- [ ] `.env.example` no longer contains `Set to "1" ONLY on/after 2026-06-15`; default
      remains `CC_OAUTH_ENABLED=0`. Verify: `grep -n "ONLY on/after 2026-06-15" apps/web-platform/.env.example`
      returns nothing AND `grep -n "^CC_OAUTH_ENABLED=0$" apps/web-platform/.env.example` returns the constant line.
- [ ] Brainstorm file gains a `## Re-review 2026-06-16` section quoting the paused-article
      text; the original verdict is annotated SUPERSEDED but NOT deleted. Verify:
      `grep -n "Re-review 2026-06-16\|SUPERSEDED\|pausing the changes" knowledge-base/project/brainstorms/2026-06-02-operator-cc-subscription-auth-brainstorm.md` returns matches AND the original "permitted-with-guardrails" prose still present.
- [ ] `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md` exists, contains
      the 5 answered questions, the recommended-actions table, and the draft-notice
      disclaimer. Verify: `test -f` + `grep -c "Q1\|Q2\|Q3\|Q4\|Q5\|Recommended"`.
- [ ] All four files reference each other consistently (audit ↔ code ↔ env ↔ brainstorm);
      KB-path citations resolve: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <edited-files> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'`.

### Post-merge (automatic)

- [ ] Merging to `main` touches `apps/web-platform/**` and triggers the
      `web-platform-release` pipeline. **This is desired** — the prd container
      redeploys and picks up the already-set `CC_OAUTH_ENABLED=1` Doppler value. No
      separate operator action; the path-filtered `on.push` is the remediation.
      Automation: handled by `web-platform-release.yml` on merge (no operator step).

## Domain Review

**Domains relevant:** Legal (primary), Engineering (comment edits + no-behavior-change
verification).

This is the rare plan where the **Legal domain is the deliverable itself** (the CLO
re-review verdict). The brainstorm already ran the USER_BRAND_CRITICAL triad
(CPO+CLO+CTO) on 2026-06-02; this change records the CLO's *updated* verdict. Per the
sign-off lifecycle (plan phase = CPO ack only), confirm CPO sign-off / brainstorm
carry-forward at plan time; CLO + CTO concerns from the brainstorm are reflected in the
plan body (the no-behavior-change invariant is the CTO concern; the tolerated-basis
re-framing is the CLO concern).

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Edit/Create (server comment, env
example, two KB markdown docs). No `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`.

## Observability

Not applicable as a *new* surface — this is a comment/docs change with **no new code
path, no new error path, no new log call**. The existing observability for the
operator-cc-oauth feature (the `byok-lease:missing-key` errorClass breadcrumb at
`:219`, the `subscription_limit` cause→code mapping at `:261`) is **unchanged**. The
no-behavior-change ACs above (tsc + vitest + `git diff -w`) are the gate that proves no
observability surface moved.

> Skip rationale: pure comment/docs change; deletes no read/emit site, adds no new
> failure mode. Per Phase 2.9 skip condition ("pure-docs / no new code surface").

## Hypotheses

N/A — not a bug-investigation plan. The "bug" is a known stale-premise documentation
defect with a fully-specified correction; no diagnostic hypotheses needed.

## Test Scenarios

The only test surface is the **invariant that behavior did not change**:

1. `byok-lease-credential-type.test.ts` passes unchanged (AC3 date gate, owner-only
   routing). This is the proof that the comment re-framing did not perturb the
   fail-closed branches.
2. `tsc --noEmit` passes (comments don't affect types, but proves no accidental code
   edit).
3. `git diff -w` on byok-lease.ts shows comment-only lines.

No new tests are written — adding behavioral tests for a comment change would be
ceremony (the existing suite already pins the behavior we are NOT changing).

## Sharp Edges

- **Do NOT change the `CC_OAUTH_EFFECTIVE_DATE` constant value.** `byok-lease-credential-type.test.ts:76-77`
  derives `BEFORE_DATE`/`AFTER_DATE` from it; AC3 asserts `OauthNotYetPermittedError`.
  Changing the value (or removing the class/branch) is a runtime change and breaks the
  suite. The task is comment-only; the date stays `2026-06-15T00:00:00Z`.
- **Do NOT rename `OauthNotYetPermittedError` / `OauthDelegationForbiddenError`** — both
  are imported by tests and consumed by the lease. Only their doc-comments change.
- The `OauthNotYetPermittedError` **message string** derives from the constant
  (`byok-lease.ts:94-100`) so it cannot drift; leave it. Re-framing happens in the
  *doc-comment above the class*, not the runtime message.
- **Keep `CC_OAUTH_ENABLED=0` in `.env.example`.** The example default is OFF; the live
  Doppler dev+prd values are `1` out-of-band. Do not "helpfully" flip the example to 1.
- **Do NOT delete the original brainstorm verdict.** Mark SUPERSEDED in place; the
  brainstorm is a point-in-time record. Deleting it loses the audit trail of *why* the
  verdict changed.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder,
  or omits the threshold will fail `deepen-plan` Phase 4.6 — this section is filled.
- The merge IS the deploy (path-filtered `web-platform-release.yml` on `apps/web-platform/**`).
  The implementer must NOT add any separate operator container-restart step — the
  pipeline handles redeploy automatically on merge to main.

## Domain Review (closing note)

No cross-domain implications beyond Legal + Engineering. No GDPR/regulated-data surface
touched (no schema, migration, auth flow, API route, `.sql`). No new infrastructure (no
server/secret/cron/vendor — Phase 2.8 skip; see iac-routing-ack at top). The
`web-platform-release` redeploy is an intended side effect of touching
`apps/web-platform/**`, already provisioned.
