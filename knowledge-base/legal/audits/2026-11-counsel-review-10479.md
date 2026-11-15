---
title: "Counsel review audit — #10479 / #10538 (PR #12737): verified TLS from Cloudflare to the web servers for app.soleur.ai, published in Privacy Policy Section 11 and DPD 8.1(c), the DPA template, the Article 30 register, and the A7 leg-2 record addendum"
type: counsel-review
date: 2026-11-15
issue: 10479
pr: 12737
related: [10538, 12742, 12743, 12744, 12745, 12789, 9139, 7465]
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-11-15
signed_off_by: "CLO agent function run via subagent at the ship Phase 5.5 Counsel-Review CLO-Attestation Gate (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED for the merge of PR #12737, conditioned on pre-merge conditions P-1 to P-3 and the four in-PR text corrections R1 to R4 below. These are conditions. None of them is satisfied by this review. Every published claim matches the implementation: the adopted rule in seo-config-rules.tf (ref dcb85b75, ssl = strict, http.host eq app.soleur.ai), ledger connections 6 and 7 (0-indexed), and the declared sdk_url in inngest-host.tf. The live host keeps the private plain-HTTP poll until the owner's gated replace (#12742). Not external counsel."
non_blocking:
  - "N1 — The register markers cite 'a public-hostname probe 3/3 HTTP 200' at 06:50Z. This review found no run record for a 3-run probe. decision-challenges.md records 20/20 at 07:50Z and the PR body records 20/20. The figure understates rather than overstates, so it is left as drafted. A later correction should cite the 20/20 reading."
  - "N2 — #12742 item 8 says the owner-record draft is 'in the PR #12737 description'. Under ruling C3 the draft lives only in the A7 audit file, in the section 'Unsigned owner-record draft'. Correct the pointer in the issue body. It is not in-PR prose."
  - "N3 — The DPA template's draft note says api.soleur.ai is left out of the TLS claim because its SSL mode has not been read. In dns.tf, api.soleur.ai is an unproxied CNAME to Supabase, so it never crosses Cloudflare. The reason given is inexact, but leaving the host out is correct. Fix it when the template is promoted."
  - "N4 — The tunnel hostnames deploy, ssh and registry (proxied CNAMEs to the cfargotunnel) are not Cloudflare-to-origin pulls. The published sentence ('Cloudflare, the proxy in front of the Web Platform ... forwards requests to our web servers over TLS') is read in its Web Platform context, and these hosts do not falsify it. No change."
  - "N5 — The comment above the adopted rule in seo-config-rules.tf reads 'STRICT SINCE THE ORIGIN-TLS CLEANUP (2026-11-13). This change made it ...'. That comment is past tense inside the PR whose merge applies the change. It is a code comment, so it falls to the CTO and is not legal prose."
  - "N6 — The mirror-drift ratchet warns that the #7465 freeze passed its 2026-09-30 target with 80 drift lines. The warning predates this PR, and this PR does not grow the drift."
open_follow_ups: ["Q-1: re-measure after the cleanup apply. Record a read-only config-entrypoint read showing a new ruleset version, 3 rules, the adopted rule strict for app.soleur.ai and no flexible rule matching it, plus public origin-tls-probe --require-tls passes. Do this before #12742 dispatches anything", "Q-2: #12742, the owner's inngest-host-replace. Before the live act, hop 1 (Inngest host to the Cloudflare edge certificate check) must be measured against the deployed build, and a fresh read-back must show no flexible rule. The replace must run by 2026-11-20, or else an owner-typed record beginning 'SIGNED BY OWNER (human, not an agent)' is required. Outer limit 2026-12-10", "Q-3: the owner's own words for the 2026-11-13 new acceptance, on #12742 (owner-pending; an agent cannot supply them)", "Q-4: #12742 item 7. Once leg 2 is measured as TLS, revisit the Privacy Policy Section 11 and DPD 8.1(c) clause 'some traffic between our web servers and our job scheduler ... is not TLS-encrypted', and the DPA template and register equivalents", "Q-5: any change of the adopted rule away from strict, whether to full or flexible, by PR or break-glass, corrects the published wording the same day (runbook origin-tls-strict-flip.md, Rollback step 5; rollbackCouplingViolations in seo-config-rules.test.ts)", "Q-6: #12743 (port 80, Authenticated Origin Pulls), #12744 (handshake-reset bursts alert), #12745 (lb-pool-health reader)"]
re_evaluation_triggers: "Any change of the adopted rule's ssl mode away from strict (PR or dashboard) OR the owner's inngest-host-replace (#12742) running OR leg 2 measured as TLS OR the A7 leg-2 acceptance lapsing (2026-11-20) without an owner-typed record OR a new proxied hostname routed to the web servers OR first arms-length user OR EEA-out data subject OR regulated-industry user"
---

# Counsel review audit — #10479 / #10538 (PR #12737)

This is the v1 internal counsel-review attestation under the ship Phase 5.5 gate, for a PR whose plan declares `brand_survival_threshold: single-user incident`. Authority: the CLO agent function (Soleur-as-tenant-zero v1). The operator keeps a veto. External counsel is reserved for the frontmatter triggers. This output is draft material, not legal advice. This file is the only file the review wrote. Every correction it requires is listed under "Required in-PR corrections" for the PR author to apply.

**Method.** The legal diff (`git diff origin/main...HEAD` over `docs/legal/`, `plugins/soleur/docs/pages/legal/`, `knowledge-base/legal/`) was read at word level on both surfaces. Each claim was checked against the following sources:

- `apps/web-platform/infra/seo-config-rules.tf`: the adopted `set_config` rule with ref `dcb85b75bc3c4f4aa2a8c13a080bf854`, described "Strict SSL for app.soleur.ai (ADR-321, #10479)", expression `(http.host eq "app.soleur.ai")`, `ssl = "strict"`. The ORIGIN-TLS canary and strict-flip rules are gone. The `full` rule for the apex and www is the only other ssl rule.
- `scripts/encryption-posture-ledger.json` `connections` (0-indexed). Connection 6 is the leg-2 `sdk_url` poll: tls none, `cert_verification: off`, the exception relabelled a new acceptance after a lapse, accepted to 2026-11-20, tracking #12742. Connection 7 is Cloudflare edge to the web hosts' origin: strict, `cert_verification: on`, no exception, `disclosed_as` Privacy Policy.
- `apps/web-platform/infra/inngest-host.tf` `sdk_url = "https://app.soleur.ai/api/inngest"`. This is declared only. The live host changes only through the gated `inngest-host-replace` dispatch.
- `apps/web-platform/server/origin-tls.ts` (`ORIGIN_TLS_REQUIRED_ENV`).
- `apps/web-platform/infra/cloudflare-lb.tf` (`allow_insecure = false`).
- `apps/web-platform/infra/dns.tf`: `cloudflare_record.app` proxied; `api` unproxied to Supabase; deploy, ssh and registry are tunnel CNAMEs.
- The runbook `origin-tls-strict-flip.md` (Rollback and Break-glass).
- `rollbackCouplingViolations` in `apps/web-platform/test/seo-config-rules.test.ts`.
- The CLO rows and the pre-merge evidence readings in `knowledge-base/project/specs/feat-origin-tls-inngest-poll-10479-10538/decision-challenges.md`.

Live state was not re-read by this review. Measurements are cited from the records named.

**Gates run locally (read-only), 2026-11-15:**

- `lint-legal-mirror-drift-baseline.sh --base origin/main`: within baseline. It also printed the pre-existing #7465 warning (N6).
- `lint-legal-scope-block-placement.sh --base origin/main`: pass.
- `check-tc-document-sha.sh`: exit 0.
- vitest `legal-doc-consistency.test.ts` with `seo-config-rules.test.ts`: 83/83 pass.

Per #7349, these gates measure agreement between the surfaces, not truth. The prose was read in full.

## Artifact 1 — Privacy Policy Section 11 "Encryption in transit" (canonical and Eleventy mirror)

| Claim | Checked against | Verdict |
|---|---|---|
| "Since November 8, 2026 (UTC), Cloudflare forwards requests to our web servers over TLS and verifies our servers' certificate." | Ledger connection 7: strict written 2026-11-07T23:43:43.865Z, first proven 23:44:39Z. The ruleset was still version 7 at the 2026-11-15 read-only re-read, so no rule changed. Zone default strict; last match strict for app.soleur.ai. Strict checks the Origin CA certificate and the hostname, fails closed, and has no plaintext fallback. The post-merge adopted rule is strict | TRUE. Day precision without a minute follows ruling C1, and the published date does not precede the measured start |
| Scope "our web servers" | `cloudflare_record.app` and the LB pool hold the two web hosts. The tunnel hosts are not origin pulls (N4). `api` is unproxied | TRUE in context |
| "We do not claim TLS for all server-to-server traffic ... some of that traffic is not TLS-encrypted, including some traffic between our web servers and our job scheduler" | Connection 5 (leg 1) has been TLS since 2026-10-26. Connection 6 (leg 2 poll) is plain HTTP and stays so live after merge until #12742 | TRUE. "Some" is right now that leg 1 is TLS |
| No claim about hop 1 of the step-call leg (Inngest host to the Cloudflare edge) | Ledger connection 7: hop 1 unmeasured (#12742) | Correctly not claimed |
| Last Updated "November 15, 2026" note: "no new purpose, sub-processor, recipient or international transfer" | Cloudflare is already disclosed (Section 5.8). This is a TOM change only | TRUE |
| In-section note "*(Added 2026-11-13, ref #10479 ...)*" | House precedent: the note date equals the Last Updated date of the same update (the 2026-10-29 DPD note; "qualified November 5, 2026") | **INCONSISTENT. Correct per R2.** The page says Last Updated November 15, and the text first publishes at merge |
| Mirror equals canonical on every changed line | Word diff of both surfaces | TRUE |

**Verdict: accurate, subject to R2 and P-2.**

## Artifact 2 — Data Protection Disclosure 8.1(c) (canonical and Eleventy mirror)

| Claim | Checked against | Verdict |
|---|---|---|
| "since November 8, 2026 (UTC), TLS from Cloudflare to our web servers, with Cloudflare verifying the servers' certificate" | As Artifact 1 | TRUE |
| "**FULFILLED as to the Cloudflare-to-origin connection. NOT FULFILLED as to server-to-server transport.**" | Connections 6 and 7 | TRUE. The split status is right. Leg 1 being TLS does not make server-to-server transport fulfilled, because leg 2 and other private links are not claimed |
| Job scheduler cross-reference to Sections 2.3(o) and 2.3(aa) | Unchanged text | TRUE |
| "*(Added 2026-11-13 ...)*" | As Artifact 1 | **INCONSISTENT. Correct per R2** |

**Verdict: accurate, subject to R2 and P-2.**

## Artifact 3 — DPA template (Annex TOM rows)

Both encryption-in-transit rows carry the same claims as Artifact 1, worded in the third person ("Jikigai's web servers"). The scope is bounded to the Customer-facing endpoint `app.soleur.ai`, the minimum protocol version is left open, and "whether other such links are TLS-encrypted is not stated". All TRUE against connections 5 to 7. The draft note on `api.soleur.ai` gives an inexact reason (N3) but reaches the right result.

**Verdict: accurate.**

## Artifact 4 — Article 30 register (six 2026-11-13 Superseded markers)

| Check | Result |
|---|---|
| Every live occurrence of "not claimed for the Cloudflare-to-origin connection", "crosses the public internet" or "Flexible SSL" has a 2026-11-13 (#10479) marker beneath it | TRUE in all six cells: the Cross-Cutting block, the PA TOM rows, PA-13 (g)(14) and the Art. 32 list. The 2026-10-29 Art. 32 note is superseded by the 2026-11-13 note beneath it |
| Each marker quotes the superseded phrase and is conditioned "fires on the merge of PR #12737" | TRUE. It is not past tense (#8207 rule) |
| "since 2026-11-07" internally and "since November 8" in the published text | Consistent by ruling C1. Internal records give the write and the first proof to the second, and both are correct |
| "The Flexible rule is overridden by later strict rules until the cleanup apply of PR #12737, after which the adopted rule ... is itself strict" | `seo-config-rules.tf` and the 2026-11-13 config-entrypoint read (5 rules, last match strict) | TRUE |
| "the web-app-to-scheduler leg has been TLS since 2026-10-26"; the `sdk_url` poll stays plain HTTP (#10538) | Connections 5 and 6 | TRUE |
| "a public-hostname probe 3/3 HTTP 200" | Not sourced by a run record this review found | Understatement, left as drafted (N1) |
| PA-13 (g)(14): "A return to `flexible` corrects this marker and Privacy Policy Section 11 the same day." | The runbook's Rollback makes `full` the first step. `full` does not verify the certificate, so the published "verifies our servers' certificate" would be false under it. `rollbackCouplingViolations` fires on any mode other than strict | **INCOMPLETE. Correct per R4.** The commitment must cover `full` as well as `flexible` |

**Verdict: accurate, subject to R4.**

## Artifact 5 — A7 record `2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md` (retitle, Superseded marker, addendum, owner-record draft)

| Claim | Checked against | Verdict |
|---|---|---|
| A new acceptance after a lapse, not an extension. Gap from 2026-11-13T00:00Z recorded and not backdated. Outer limit 2026-12-10 | Rulings at rows "2026-11-12 lapse" and C4. Ledger connection 6 `exception.justification` | TRUE and consistent with the ledger |
| Controls re-measured 2026-11-13 (5 Jikigai servers; `nft_rules=7`, `legacy_8288=0`) | Ledger connection 6 cites the same comment and values | TRUE (as recorded) |
| Fix-round ruling (c): the push apply rewrites `cloudflare_ruleset.seo_config_settings` at merge; the effective mode and the live `--sdk-url` stay the same | `seo-config-rules.tf`; the `inngest-host.tf` declared-only `sdk_url` | TRUE. The "nothing live changes" overstatement is cured |
| Fix-round ruling (a): the owner-record draft is a list of prompts, says "NOT a signature", and is fenced | Ruling C3 | TRUE. No owner sentence is pre-written |
| "**That is owner-pending**: the owner confirms in their own words on #10538." | This PR's body says `Closes #10538`. Ledger connection 6 and the PR body route the owner's words to #12742 | **WRONG ROUTE. Correct per R1.** The issue named closes when this PR merges |
| Frontmatter pointer to the addendum | Earlier addenda carry a frontmatter `addenda:` key (#8207 precedent) | **MISSING. Add per R3** |
| The H1 still reads "owner extension" | The body is left as filed, and the Superseded marker under the H1 corrects it | Acceptable |

**Verdict: accurate after R1 and R3.**

## Required in-PR corrections

The PR author applies these. Once each lands verbatim, nothing is re-reviewed; a grep confirms it.

- **R1.** File: `knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`, "Owner's words" bullet.
  - Old: `the owner confirms in their own words on #10538.`
  - New: `the owner confirms in their own words on #12742 (#10538 closes on the merge of PR #12737).`
- **R2.** Files: `docs/legal/privacy-policy.md`, `plugins/soleur/docs/pages/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`. Make the same edit on both surfaces.
  - Old: `*(Added 2026-11-13, ref #10479:`
  - New: `*(Added 2026-11-15, ref #10479:`, or the merge date if P-2 re-bumps.
  - Then re-pin `LEGAL_DOC_SHAS` in `apps/web-platform/lib/legal/legal-doc-shas.ts`.
- **R3.** File: the same A7 record, frontmatter. Add:
  `addenda: ["2026-11-13 CLO-cures addendum (PR #12737; its ledger-row and sdk_url limbs fire on that PR's merge), amended 2026-11-15 by CLO fix-round rulings (a) and (c): see 'Addendum — 2026-11-13 (CLO cures, PR #12737)' and 'Unsigned owner-record draft'"]`
- **R4.** File: `knowledge-base/legal/article-30-register.md`, PA-13 (g)(14) marker.
  - Old: ``A return to `flexible` corrects this marker and Privacy Policy Section 11 the same day.``
  - New: ``Any change of the adopted rule away from `strict` (to `full` or `flexible`) corrects this marker and Privacy Policy Section 11 the same day.``
  - Recommended alongside, for the CTO: make the matching wording change in `scripts/encryption-posture-ledger.json` connection 7 `does_not_defend` ("back to flexible" becomes "away from strict, to full or flexible").

## Pre-merge conditions (not satisfied by this review)

- **P-1. Per-host evidence (rulings C and C2).** Record in the PR one Better Stack `origin-tls: listening` row with `required: true` for soleur-web-platform (web-1). Record another for soleur-web-2. Each must be dated within 24 h before merge. Record a strict-mode measurement in the same window: zone `strict`, and the config ruleset's last match for app.soleur.ai `strict`. **Not yet re-taken.** The 2026-11-12 rows lapsed at 2026-11-13T22:18Z.
- **P-2. Last Updated dates.** The Last Updated strings on the four published surfaces read November 15, 2026. If the merge date differs, re-bump all four, together with the R2 note dates, and re-pin the SHAs.
- **P-3. R1 to R4 applied.**

The CTO's merge-alone check (D5) and the `[ack-destroy]` line also apply. They are technical rulings, recorded in decision-challenges.md and not repeated here.

## Open conditions carried (not merge-gating)

The merge does not change leg 2 live, so these do not gate it.

- Q-1 to Q-6, as listed in the frontmatter `open_follow_ups`.
- Q-3 in particular: the owner's own signed words for the 2026-11-13 acceptance are pending and go on #12742.
- The acceptance lapses again after 2026-11-20 unless the owner's replace has run or an owner-typed record exists.
- GitHub will close #10479 and #10538 at merge ("Closes"). For the legal record, #10479 counts as closed only once Q-1 is recorded (ruling "Remedy (c) legality"). #12742 must not dispatch before then.

## `[DRAFT — pending CLO/counsel review` markers

These markers are present in the Privacy Policy, the GDPR Policy and the Data Protection Disclosure, on both surfaces, six in each file. That is the same count as `origin/main`, and none sits in a section this PR touches, so they are not introduced or affected here. Several audit files also quote the phrase as text. This review does not discharge those markers.

## Decision record

**Decision:** discharge the counsel-review gate for PR #12737 on the text as drafted, conditioned on P-1 to P-3.

**Rationale:** the published claim was measured continuously from the strict write to the 2026-11-15 re-read, and strict fails closed. The merge keeps the effective mode strict and leaves the live poll unchanged. Every claim is bounded where it should be: leg 2, hop 1 and the other private links are left out. The four corrections fix record accuracy: an issue route, the dating of a self-history note, a pointer key, and the scope of a rollback commitment. None of them changes what users are told about the processing.

## External counsel re-review triggers

Any of the `re_evaluation_triggers` in the frontmatter re-opens this review. When the trigger is a first arms-length user, an EEA-out data subject or a regulated-industry user, the review goes to external counsel.
