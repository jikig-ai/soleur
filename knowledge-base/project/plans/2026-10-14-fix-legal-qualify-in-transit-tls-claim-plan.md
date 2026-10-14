---
title: "fix(legal): qualify the in-transit TLS claim (Privacy Policy s11, DPD 8.1(c), Article 30 register)"
date: 2026-10-14
slug: legal-qualify-in-transit-tls-claim
branch: feat-one-shot-legal-tls-wording-10136
issue: 10136
lane: cross-domain
type: fix
---

# fix(legal): qualify the in-transit TLS claim

## Enhancement Summary

**Deepened on:** 2026-10-14. **Method:** the full agent fan-out was not run - the plan edits roughly 40 lines of CLO-ruled legal prose, a register and one JSON value, and the plan already carries a CLO (Q1-Q8, R1-R4) and CTO (Q1-Q3) ruling set, a three-reviewer plan-review pass (DHH, Kieran, code-simplicity) and a learnings sweep. Deepening is therefore gate verification plus live re-verification of every cited artifact.

**Gates (deepen-plan Phase 4.6-4.12):** 4.6 User-Brand Impact present, threshold `aggregate pattern`, pass. 4.7 Observability: skipped - no file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts` is edited (the plan Phase 2.9 trigger set); the two non-doc files are a hash literal in `apps/web-platform/lib/legal/` and a repo-root JSON ledger value. 4.8 PAT grep: no hit. 4.9 UI wireframe: no UI surface. 4.10 Encryption posture: no `.tf`, migration, cloud-init or compose file; the plan documents an existing ledgered exception and introduces no store or connection - skipped. 4.11 Guard contract: the deliverable ships no guard (ACs are one-off diff checks; a permanent lint is on the Cut List) - skipped. 4.12 Scope Check: 1 live section, Ask Mapping / Provenance / Split Assessment present, a `Recommendation:` line, no `unmapped` status, no `status: BLOCKED` - pass.

**Re-verified live in this pass:** every cited call site exists on this branch (stripe, github, today/[id]/send, resend-inbound, run-routine, routines/run, write-action-send, inngest client, list-runs, ci-deploy.sh, cloud-init.yml, inngest route, `agent-on-spawn-requested.ts`); `INNGEST_BASE_URL=http://10.0.1.40:8288` occurs in `ci-deploy.sh` (2 sites) and `cloud-init.yml` (the address is for the PR-body trace only, never register or published text); the event key in the URL path is the pinned SDK's own behavior (`inngest@3.54.2`, `components/Inngest.js`), now cited in AC11; every `knowledge-base/` path in the plan resolves; every cited rule id exists in `AGENTS.md`; #7465, #9948, #9949, #7992 are open, #6588 closed (cited only as history); the live soleur.ai probe in AC14 returns HTTP 200 with the old sentence count 1 today.

**Key improvements carried in from review:** FULFILLED split instead of a literal replace; word-level diff method for ACs (whole-line diffs hit pre-existing tokens on 1-38 KB lines); claim-to-source trace; DPA-template line; credentials clause trimmed; pointers without field lists; `last_reviewed` not bumped; #10136 comment before ready; final pin before CLO attestation.

**New considerations:** the ledger's own wording of the hop ("event payloads and step outputs, `sdk_url` call-back") is broader than the CTO's code read, and the plan deliberately does not repeat it (CLO Q7); three plaintext-exception ledger strings still call the published sentence "referred to the 2026-10-24 ruling" after this merge and are left as history.

Ref #10138 (item 3). Ref #10136. Draft PR #10326. Must merge by 2026-10-24 (CLO deadline). PR body uses `Ref`, never `Closes`.

## Overview

Two published sentences say transport encryption is complete: Privacy Policy section 11 ("All communication with the Web Platform is protected by TLS") and DPD section 8.1(c) ("TLS for data in transit ... **FULFILLED.**"). Configuration read on 2026-10-12 shows some server-to-server traffic on Jikigai's Hetzner private network (event payloads to the dedicated Inngest host, port 8288) is plain HTTP. The CLO agent ruled (2026-10-13, re-ruled 2026-10-14) that both sentences be corrected in one mirror-paired PR, and that the Article 30 register be qualified in step. This plan ships that correction and nothing wider. It adds no TLS, changes no infrastructure and renews no encryption-posture exception.

Three artifacts change, each paired with its sibling:

1. Privacy Policy section 11 bullet, canonical + Eleventy mirror.
2. DPD section 8.1(c), canonical + Eleventy mirror.
3. `knowledge-base/legal/article-30-register.md` (dated in-cell markers + one plaintext-private-network note).

Plus the lockstep files those force: `LEGAL_DOC_SHAS` re-pin, the two `Last Updated` changelog entries (CLO-ruled), one ledger `disclosed_as` value (Research Reconciliation row 7), and one list item in the draft DPA template that states the same hop wrongly (row 11).

## Research Reconciliation - Spec vs. Codebase

| # | Brief / ruling claim | Reality (verified 2026-10-14 on this branch) | Plan response |
|---|---|---|---|
| 1 | PP bullet at `docs/legal/privacy-policy.md` ~651, mirror ~652 | Exactly `:651` and `:652`, text `- **Encryption in transit:** All communication with the Web Platform is protected by TLS.` | Edit by content anchor, not line number |
| 2 | DPD 8.1(c) at ~439, mirror ~448 | Exactly `:439` / `:448`; item ends `**FULFILLED.**` for the whole of (c) | CLO restructure (row 3 of decisions): FULFILLED cannot follow the TLS clause |
| 3 | Register lines ~64 PA-1, ~84 PA-2 (g)(1), ~465 "TLS 1.2+ enforced everywhere" | `:64` is PA-1 (g) opening `(1) TLS 1.2+ in transit.`; `:84` PA-2 (g) opening `(1) TLS in transit.`; only `:465` (Cross-Cutting bullet) literally says "enforced everywhere" | Marker quotes the actual text of each line, not the brief's paraphrase |
| 4 | "check PA-3/4/6 for Inngest routing" | PA-3 (`:103`, "TLS 1.2+ in transit") is routed: `app/api/webhooks/stripe/route.ts` sends `finance.payment_failed` to Inngest. PA-4 (`:119`) and PA-6 (`:152`) have no Inngest call site. | PA-3 gets a pointer; PA-4/PA-6 untouched (CLO Q4) |
| 5 | "add a plaintext-private-network entry to the Inngest-carrying activities (PA-13 ~265, PA-21/22)" | CTO code read: event payloads also cross for PA-16, PA-17, PA-27 and (manual runs) PA-29; PA-14, PA-18, PA-31 carry no personal data in the ingest direction. PA-21 is `:421`, PA-22 `:439`. | Full note once at PA-13, short pointers elsewhere (CTO Q3 rule A; CLO Q6). PA-14/18/31: nothing added. |
| 6 | Ledger and #10136 body: the hop carries "event payloads and step outputs" and an `sdk_url` call-back | CTO: step execution and step outputs go to the app's public serve URL (`serveHost` in `app/api/inngest/route.ts`; header of `server/inngest/execution-placement.ts`), not this hop. Only event ingest, the `/v1` read-back and the `--sdk-url` registration poll are plain HTTP. | Register says "event payloads" only and "step execution is a different path ... transport of that path not asserted here". Discrepancy goes to a #10136 comment, not into legal prose (CLO Q7). |
| 7 | Brief scope: three items only | `scripts/encryption-posture-ledger.json` connection "web-platform server -> Supabase Postgres/PostgREST" has `disclosed_as: docs/legal/data-protection-disclosure.md:TLS for data in transit`. That anchor string disappears with the DPD edit. `lint-encryption-posture.py` resolves anchors only for `cert_verification: off` rows, so CI would stay green with a dangling pointer. | One-value ledger edit: `disclosed_as` -> `not-publicly-claimed` (CLO Q3). Operator-scope flag in decision-challenges.md; no exception renewed, no expiry moved. |
| 8 | CLO 2026-10-13 proposed PP "We are adding TLS ..." and DPD "browser-to-platform and Supabase connections" | The brief carries the 2026-10-14 re-ruling: "We plan to add TLS to these links" and no Supabase mention | Use the brief's exact PP and DPD clause text; the 10-13 text is superseded |
| 9 | "LEAVE UNEDITED" retracted July 2 entries and Cloudflare hits | `privacy-policy.md:20`, `gdpr-policy.md:22`, `data-protection-disclosure.md:21` carry the retracted sentence inside the history chain; `gdpr-policy.md:157` and DPD `:294` are the Cloudflare TLS-termination hits | Out of the diff; AC11 asserts zero diff on those passages |
| 11 | Scope: PP, DPD and register only | A sweep of `knowledge-base/legal/` for transport claims (plan-review finding) found `data-processing-agreement-template.md` line ~373 "Hetzner-terminated TLS at internal HTTP hops" (customer-facing draft, unexecuted, no CI gate); `article-30-2-register.md` P-1 (3), the alpha-tester annex and `compliance-posture.md` concern other legs and are unaffected | One list item edited (CLO R1); inherited "TLS 1.3 minimum" line ~180 listed on the #10136 comment, not edited |
| 10 | Local gates named in the brief | All five gates pass on `origin/main` today (baseline run): drift ratchet rc=0 (with the existing `#7465` overdue warning), `check-tc-document-sha.sh` rc=0, `lint-encryption-posture.py --repo-sweep` PASS, `lint-legal-registers.sh` PASS, `probe-legal-corpus-truth.sh` CORPUS-OK | Any red after the edit is caused by the edit |

## Research Insights

**Premise Validation (Phase 0.6).** Cited issues/PRs: #10136 open ("encryption-posture: private-network in-transit exceptions"), #10138 open (decision-challenge), #10326 open draft (this branch), #10291, #9051, #8626 open drafts. All cited files exist on `origin/main`. Stale or changed premises found: (a) the ledger anchor coupling (Reconciliation 7), (b) the step-outputs over-claim (6), (c) the 10-13 vs 10-14 CLO wording (8). Mechanism vs ADR corpus: ADR-100 (dedicated Inngest host, singleton control plane, private-network plaintext "by design") and ADR-140 (encryption posture as a design-time default) frame the exception; neither rejects "qualify the published sentence"; no ADR conflict.

**Property List (Phase 0.6b).**

- P1. A reader of the published Privacy Policy cannot conclude all Web Platform traffic is TLS-protected.
- P2. A reader of the published DPD cannot conclude transport encryption is FULFILLED.
- P3. Canonical and mirror carry byte-identical new sentences, the SHA pins match, and the `Last Updated` date is identical on both surfaces of each document.
- P4. The Article 30 register no longer asserts "TLS enforced everywhere" and records which activities' event payloads cross the plaintext hop, each sentence labelled measured / code-read / policy / inherited and dated.
- P5. No pointer in a compliance artifact is left dangling by the DPD edit.
- P6. No new claim of the forbidden kinds is introduced (end-to-end/all/everywhere/FULFILLED transport encryption; private-network or nftables access restriction; peers only our own hosts; Cloudflare-to-origin TLS; any TLS date; wire-capture language; Supabase in the DPD clause).
- P7. #10291, #9051, #8626 passages are untouched and the second-to-merge re-pin path is stated.

**Cut List.**

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| Edit `gdpr-policy.md` | none | Its TLS hits are the retracted history entry and the Cloudflare termination line; both ruled "leave unedited" |
| New lint forbidding unqualified "TLS" sentences | P6 | The AC9 word-level diff grep at work time plus existing `lint-encryption-posture.py` anchors; a permanent lint is a separate deliverable and would be a Guard Contract plan of its own |
| Renew or reword the three plaintext-exception ledger rows | none | Rules in force: do not renew an exception to turn a lint green; the rows keep their strings (CLO Q3) |
| A "Corrected <date>" paragraph beside the Last Updated entry | P1/P2 | The CLO-ruled Last Updated entry already says "corrects an earlier statement that overstated" |
| PA-4, PA-6, PA-14, PA-18, PA-31, PA-36 register edits | P4 | No Inngest routing (PA-4/6), no personal data in the ingest direction (PA-14/18/31, "not asserted either way" stated once at PA-13), PA-36 needs no entry (brief) |
| ADR / C4 change | none | No architectural decision is made or changed |
| The `--sdk-url` registration-poll sentence in PA-13 (14) | none | Carries no personal data; dropped (CLO R2). The credentials-in-clear clause stays as one clause |
| Field lists in the six per-activity pointers | P4 | PA-13 (g)(14) is the single source of truth (CLO R3) |
| Full four-part marker on PA-2 and PA-3 | P4 | One-clause marker pointing at the Cross-Cutting block and PA-13 (g)(14) (CLO R4); PA-1 and Cross-Cutting keep the full text |

**Institutional learnings applied** (from `knowledge-base/project/learnings/`):

- `2026-10-12-a-ledger-renewal-restated-the-plans-unmeasured-claims-as-facts.md` - label every added sentence measured / policy / inherited; never repoint `disclosed_as` at the TLS sentence to turn a lint green.
- `2026-05-12-public-legal-doc-annotations-no-pr-numbers.md` - public Last Updated entries carry no PR or issue numbers and cross-reference by section; register markers (internal) do carry `#10136`.
- `2026-03-20-eleventy-mirror-dual-date-locations.md` - mirror has the hero `<p>` date AND the body `**Last Updated:**` date; both change.
- `2026-06-15-two-legal-mirror-gates-and-always-build-mcp-registered-list-desync.md` - `check-tc-document-sha.sh` green does not imply `legal-doc-consistency.test.ts` green; run both.
- `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` - on high-collision legal docs prefer one merge with one careful resolution; recompute `legal-doc-shas.ts` from the merged canonical files, never take either side.
- `2026-08-20-my-correction-pr-published-three-new-false-statements.md` - the unit of truth is the claim: do not drop a scope qualifier ("between the hosts", "in transit"); a zero-residual grep measures a string, not a claim.
- `2026-08-02-the-retraction-pr-was-itself-over-claiming-and-its-counsel-signoff-certified-a-diff-that-no-longer-existed.md` - after any rebase, re-diff the PR's claims against the register and re-attest the FINAL diff with the CLO agent.
- `2026-09-18-my-supersession-pointer-named-the-wrong-bracket.md` - register cells are append-only and date-ordered: say "recorded above in this cell", never "immediately above".
- `2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md` - sweep registers, not only published docs, when a mechanism's status changes.

**Open Code-Review Overlap check (Phase 1.7.5):** ran against the 7 files below; the only hit is #10112 (ledger root disks / image-baked rollback arm) on `scripts/encryption-posture-ledger.json`.

## Open Code-Review Overlap

- #10112 (review: finish the #9786 residuals ...) mentions `scripts/encryption-posture-ledger.json`. **Acknowledge:** different concern (root-disk rows and rollback arm); this PR edits one unrelated `disclosed_as` value in the Supabase connection row. The issue stays open.

No other planned file appears in an open `code-review` issue body.

## Decisions Already Ruled (planning phase)

All rows are persisted in `knowledge-base/project/specs/feat-one-shot-legal-tls-wording-10136/decision-challenges.md` (Decision Classes table). Summary of what binds the implementation:

- Ruled by CLO agent, 2026-10-14: DPD 8.1(c) split-status text (literal below); new Last Updated entries, Tier 2; Supabase connection `disclosed_as` -> `not-publicly-claimed`; marker forms; provenance vocabulary; PA-3 qualified, PA-4/PA-6 left; register pointers on PA-3/16/17/21/22/27 and PA-29 manual runs only; nothing on PA-14/18/31.
- Ruled by CTO agent, 2026-10-14: which activities' event payloads cross the hop; step execution is not on the plain hop; no private IPs; rule A (one canonical note at PA-13, short pointers elsewhere).
- Two `operator (scope)` rows (ledger one-liner; pointers beyond the CLO's first list) proceed on the CLO/CTO rulings and are named in the PR body so the owner can veto after the fact. Both are reversible by deleting one value or sentence.

## Files to Edit

1. `docs/legal/privacy-policy.md` - section 11 bullet (`:651`); `Last Updated` paragraph (`:20`).
2. `plugins/soleur/docs/pages/legal/privacy-policy.md` - bullet (`:652`); hero `<p>` (`:11`) and body `Last Updated` (`:29`).
3. `docs/legal/data-protection-disclosure.md` - 8.1(c) (`:439`); `Last Updated` (`:21`).
4. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` - 8.1(c) (`:448`); hero (`:11`) and body (`:30`).
5. `apps/web-platform/lib/legal/legal-doc-shas.ts` - `privacy-policy` and `data-protection-disclosure` hashes only. `tc-version.ts` / `TC_VERSION` are not touched (Terms are not edited; CLO Q2).
6. `knowledge-base/legal/article-30-register.md` - PA-1 (g)(1) `:64`, PA-2 (g)(1) `:84`, PA-3 (g) `:103`, PA-13 (g) `:265` (new item 14), PA-16 (g) `:345`, PA-17 (g) `:325`, PA-21 (g) `:421`, PA-22 (g) `:439`, PA-27 (g) `:554`, PA-29 (g) `:590`, Cross-Cutting bullet `:465`. Line numbers are as of this plan; locate each by the content anchors in Phase 2. (Anchors, not numbers: `cq-cite-content-anchor-not-line-number`.)
7. `scripts/encryption-posture-ledger.json` - one value: `disclosed_as` of connection `web-platform server -> Supabase Postgres/PostgREST`.
8. `knowledge-base/legal/data-processing-agreement-template.md` - one list item (`Encryption in transit`, line ~373), CLO R1.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-legal-tls-wording-10136/tasks.md` (derived from this plan).
- (Already created at plan time) `.../decision-challenges.md`.

No other file is created or edited. No workflow dispatch, `terraform apply`, Doppler write, volume wipe or destroy is part of this plan.

## Implementation Phases

### Phase 1 - Published documents (canonical then mirror, same session)

Use an exact-string replace per file (Edit tool or a small `python3 -I` script reading and writing UTF-8; never `sed` on these very long lines). Assert each old string occurs exactly once before replacing.

**1a. Privacy Policy section 11 bullet** (canonical and mirror, identical):

Old: `- **Encryption in transit:** All communication with the Web Platform is protected by TLS.`

New (the CLO's ruled bullet text verbatim):

`- **Encryption in transit:** Connections between your browser and the Web Platform are protected by TLS. Some traffic between Jikigai's own servers, on a private network at our EU hosting provider, is not yet TLS-encrypted, including traffic to our job scheduler. We plan to add TLS to these links.`

Use the straight apostrophe the document already uses (`Jikigai's` occurs 8 times in the canonical).

**1b. DPD 8.1(c)** (canonical and mirror, identical). Old: the whole bullet `- **(c)** Technical and organizational measures implemented: encryption at rest (AES-256-GCM for API keys), TLS for data in transit, EU-only hosting (Hetzner EU data centres; workspace data in Helsinki, Finland) for infrastructure. **FULFILLED.**`

New (CLO split-status text; the TLS clause is the brief's ruled text verbatim, preceded only by `In transit:`):

`- **(c)** Technical and organizational measures implemented: encryption at rest (AES-256-GCM for API keys) and EU-only hosting (Hetzner EU data centres; workspace data in Helsinki, Finland) for infrastructure. **FULFILLED as to encryption at rest and EU-only hosting.** In transit: TLS for browser-to-platform connections; some server-to-server traffic on a private network is not yet TLS-encrypted (see Privacy Policy Section 11). **NOT YET FULFILLED as to server-to-server transport encryption.**`

No "Supabase" in the clause. The mirror's section 8.1 lacks the canonical's (f) bullet today; that pre-existing drift is untouched (the drift ratchet is a subset check).

**1c. Last Updated entries** (CLO Q2: yes, Tier 2). In each of the four files, change the opening of the changelog paragraph from `**Last Updated:** October 13, 2026 *(` to `**Last Updated:** <D> *(<NEW ENTRY>)* Previous: October 13, 2026 *(`, leaving the entire existing chain intact. `<D>` is the day the edit is written, formatted `Month D, YYYY` (the regex in `legal-doc-consistency.test.ts` requires this shape), identical on canonical, mirror body and mirror hero `<p>` (any date grep must tolerate both punctuation forms: hero is `Last Updated <D>` with no colon, body is `**Last Updated:** <D>`; use `Last Updated[: *]+<D>` or two separate counts); re-check it at ship (Phase 5) and re-pin if the day changed.

- Privacy Policy `<NEW ENTRY>`: `Section 11 now says accurately how data is protected in transit: connections between your browser and the Web Platform are protected by TLS, but some traffic between Jikigai's own servers, on a private network at our EU hosting provider, including traffic to our job scheduler, is not yet TLS-encrypted, and we plan to add TLS to these links. **This corrects an earlier statement that overstated our transport encryption; this change is to the description, not to what Jikigai processes, and there is no new processing, sub-processor, recipient, or transfer.**`
- DPD `<NEW ENTRY>`: `Section 8.1(c) now says accurately how data is protected in transit and now separates the status of encryption at rest and EU-only hosting (fulfilled) from server-to-server transport encryption (not yet fulfilled): connections between your browser and the Web Platform are protected by TLS, but some traffic between Jikigai's own servers, on a private network at our EU hosting provider, including traffic to our job scheduler, is not yet TLS-encrypted, and we plan to add TLS to these links. **This corrects an earlier statement that overstated our transport encryption; this change is to the description, not to what Jikigai processes, and there is no new processing, sub-processor, recipient, or transfer.**`

No PR or issue numbers, no TLS date, no mention of the retracted July 2 sentence, no Supabase.

**1d. Mirror hero** (`<p>Effective February 20, 2026 | Last Updated <D></p>`) in both mirrors: the date only.

### Phase 2 - Article 30 register (`knowledge-base/legal/article-30-register.md`)

Edit by content anchor. Each edit PRESERVES the original text unedited inside the marker; dates are the day the edit is written (`<d>` = `YYYY-MM-DD`). Provenance vocabulary is fixed by the CLO: **configuration read 2026-10-12, not a wire capture** (plaintext state); **code read 2026-10-14** (what crosses); **inherited, not re-measured** (browser TLS, vendor legs, peer identity, nftables); **policy (#10136), no date** (the plan to add TLS). The word "measured" is not used bare.

**Marker rule (one sentence, applied uniformly).** A marker goes on a TLS sentence whose scope is the whole platform (PA-1, PA-2, Cross-Cutting) or that covers a leg carrying an Inngest-routed event (PA-3). A TLS sentence scoped to a single browser or named-vendor leg that no Inngest event crosses (PA-4 share pages, PA-6 newsletter) is left alone (CLO Q4). The register front matter `last_reviewed: 2026-09-14` is NOT bumped: a bump would assert a whole-register review that did not happen (CLO R4); the scoped edit is recorded in the in-cell markers and the PR body only.

2a. **PA-1 (g)(1)** - anchor `| **(g) TOMs (Art. 32)** | (1) TLS 1.2+ in transit.` Insert immediately after `(1) TLS 1.2+ in transit.` (full four-part marker):

`**[Superseded <d> (#10136), as to "TLS 1.2+ in transit": TLS protects browser-to-platform connections (inherited, not re-measured by this PR); the vendor legs stand as originally recorded (inherited, not re-measured); some server-to-server traffic on the Hetzner private network, including events sent to the job scheduler, is not TLS-encrypted (configuration read 2026-10-12, not a wire capture; see PA-13 (g)(14) for which activities are affected); the plan to add TLS is policy (#10136), no date.]**`

2b. **PA-2 (g)(1)** - anchor `| **(g) TOMs (Art. 32)** | (1) TLS in transit. (2) Encryption at rest (Supabase managed).` One-clause marker after `(1) TLS in transit.` (CLO R4):

`**[Superseded <d> (#10136), as to "TLS in transit": see the Cross-Cutting block and PA-13 (g)(14); provenance as there.]**`

2c. **PA-3 (g)** - anchor `| **(g) TOMs** | TLS 1.2+ in transit; Stripe Checkout`. After `TLS 1.2+ in transit;` insert the one-clause marker with `as to "TLS 1.2+ in transit"`, then this inline pointer (this is PA-3's only pointer; it is not repeated in 2f):

`**[Added <d> (#10136): the Stripe webhook's `finance.payment_failed` event payload crosses the plain-HTTP hop to the dedicated Inngest host, port 8288 (INNGEST_BASE_URL) (code read 2026-10-14; plaintext state: configuration read 2026-10-12, not a wire capture); see PA-13 (g)(14).]**` Qualify only that leg; do not say PA-3 traffic as a whole is unencrypted.

2d. **Cross-Cutting bullet** - anchor `- **Encryption in transit:** TLS 1.2+ enforced everywhere; HSTS on `app.soleur.ai`.` Leave the bullet unedited; add, after a blank line, a two-space-indented blockquote so it stays inside the list item (run markdownlint before commit; there is no existing blockquote-in-list precedent in this file):

`  > **Superseded <d> (#10136)**, as to "TLS 1.2+ enforced everywhere": not asserted. TLS covers browser-to-platform connections (inherited, not re-measured by this PR); the vendor legs stand as originally recorded (inherited, not re-measured); some server-to-server traffic on the Hetzner private network, including event payloads sent to the dedicated Inngest host, port 8288 (INNGEST_BASE_URL), is not TLS-encrypted (configuration read 2026-10-12, not a wire capture; which payloads: code read 2026-10-14; see PA-13 (g)(14)); the plan to add TLS is policy (#10136), no date. Peer identity and nftables restrictions: inherited, not re-measured 2026-10-12, not asserted.`

HSTS is not touched and not asserted.

2e. **PA-13 (g)** - append a new final item after `(13) ...` (cell tail `... removing one copy does not render the data unrecoverable. |`). This is the single source of truth for the hop:

`(14) **Plaintext private-network transport of Inngest events (a limit of the TOMs above; added <d>, #10136).** Event payloads are sent from the web-platform app to the dedicated Inngest host, port 8288 (`INNGEST_BASE_URL`), over plain HTTP on the Hetzner private network, with no TLS (configuration read 2026-10-12, not a wire capture; recorded as a ledger exception in `scripts/encryption-posture-ledger.json`). The event key (in the `/e/<key>` path) and the signing key (bearer on `/v1` reads) also cross that hop in clear; they are credentials, not personal data (code read 2026-10-14). Activities whose event payloads cross it: PA-3 (Stripe `finance.payment_failed`), PA-13, PA-16 (row identifier), PA-17 (GitHub webhook event payloads), PA-21, PA-22, PA-27 (inbound-mail sender, subject, recipients) and, for manual runs only, PA-29 (`actor_id`) (code read 2026-10-14, not a wire capture); other Inngest-routed activities are not asserted either way. Step execution is a different path (configuration read 2026-10-14; transport of that path not asserted here). The ledger's description of this hop is broader; reconciliation tracked in #10136. Peer identity on the private network and the host-local nftables peer restrictions in (11) are inherited and were not re-measured on 2026-10-12; this item does not assert them. The plan to add TLS is policy (#10136), with no date.`

The `--sdk-url` registration-poll sentence of the earlier draft is dropped (CLO R2). Do not use "web-1", "web-2" or any private IP address in the text (CTO). Do not edit (11).

2f. **Pointers** (PA-16, PA-17, PA-21, PA-22, PA-27, PA-29) at the end of each (g) cell, no field lists (CLO R3: single source of truth at PA-13 (g)(14)), event name in place of "the event payload" where the event is named:

`**[Added <d> (#10136): Inngest-carried events for this activity: <EVENT> crosses the plain-HTTP hop to the dedicated Inngest host, port 8288 (INNGEST_BASE_URL) (code read 2026-10-14; plaintext state: configuration read 2026-10-12, not a wire capture); see PA-13 (g)(14).]**`

- PA-16 (`:345`): `<EVENT>` = "the `agent.spawn.requested` event's `action_sends` row identifier only".
- PA-17 (`:325`): `<EVENT>` = "the GitHub webhook event payloads"; append "it is not asserted that the redaction at the route works".
- PA-21 (`:421`): `<EVENT>` = "the `agent.spawn.requested` event".
- PA-22 (`:439`): `<EVENT>` = "the `agent.spawn.requested` event"; append "and, on failure only, a forwarded copy of the original event plus the error message (contents of the message not asserted)".
- PA-27 (`:554`): `<EVENT>` = "the `email/inbound.received` event".
- PA-29 (`:590`): `<EVENT>` = "for manual runs only, the run event carrying the actor identifier; cron runs carry no app-to-server payload".

2g. Nothing at PA-4, PA-6, PA-14, PA-18, PA-31, PA-36, nor at PA-12 `(4)` / PA-7 (those are GitHub/R2 API legs, unaffected).

### Phase 3 - Ledger one-liner and DPA template line

3a. In `scripts/encryption-posture-ledger.json`, connection `web-platform server -> Supabase Postgres/PostgREST`: change `"disclosed_as": "docs/legal/data-protection-disclosure.md:TLS for data in transit"` to `"disclosed_as": "not-publicly-claimed"`. Touch no other key, string or date. The three plaintext-exception rows keep their justification strings ("referred to the 2026-10-24 CLO ruling" remains true history; rewriting it is a separate record edit per the CLO).

3b. In `knowledge-base/legal/data-processing-agreement-template.md`, anchor `1. **Encryption in transit.** TLS 1.3 minimum at all Customer-facing endpoints. Cloudflare-terminated TLS at `app.soleur.ai` with Cloudflare-managed certs; Hetzner-terminated TLS at internal HTTP hops.` replace that one list item (CLO R1, ruled 2026-10-14) with:

`1. **Encryption in transit.** TLS 1.3 minimum at all Customer-facing endpoints. Some server-to-server traffic on a private network at Jikigai's EU hosting provider, including traffic to Jikigai's job scheduler, is not yet TLS-encrypted; Jikigai plans to add TLS to these links. *[Draft note <d> (#10136): reconcile with Privacy Policy Section 11 before execution.]*`

The Cloudflare and certificate sentence is dropped with no replacement about Cloudflare-to-origin. The separate line ~180 ("TLS 1.3 minimum on all Customer-facing endpoints") stays: it is scoped to Customer-facing endpoints, not the private hop; its TLS 1.3 claim is inherited and unverified and is listed in the #10136 comment (Phase 5 step 1). `tenant-dpa-register.md`, `article-30-2-register.md` P-1 (3) and `2026-08-06-alpha-tester-processing-annex.md` are unaffected (operator-to-Anthropic leg; no Jikigai server hop) and are not edited. The template is an unexecuted draft with no CI gate; the edit is still made so that no known-wrong sentence sits in a document headed for execution.

### Phase 4 - Verification, then final pin

Run the focused gates (no `test-all --affected`; CI's required `test` context covers the rest). The `Last Updated` date `<D>` and the two hashes are the LAST edit before this phase's final run (see Phase 5 step 2): fix every wording issue first, then set the date, then hash.

```bash
sha256sum docs/legal/privacy-policy.md docs/legal/data-protection-disclosure.md
# paste each hash into LEGAL_DOC_SHAS["privacy-policy"] / ["data-protection-disclosure"]
bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main   # expect rc=0 (the existing #7465 overdue warning is pre-existing)
bash apps/web-platform/scripts/check-tc-document-sha.sh                # expect rc=0
python3 scripts/lint-encryption-posture.py --repo-sweep                # expect PASS, 0 failing checks
bash scripts/lint-legal-registers.sh                                   # expect all assertions passed
bash scripts/probe-legal-corpus-truth.sh                               # expect CORPUS-OK
(cd apps/web-platform && npx vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts)
npx markdownlint-cli2 <the five markdown files edited above>           # or the repo's markdownlint-cli invocation; only if it ran green on origin/main for these files
```

If a gate goes red, fix the edit; never loosen a baseline, renew an exception or add a waiver to turn it green.

### Phase 5 - Ship (merge queue) and post-merge

1. Before marking ready, in this order: (i) post ONE comment on #10136 (not a close) so the register's "reconciliation tracked in #10136" is true on the day it merges - the PR link, the step-outputs discrepancy (the ledger/issue wording "event payloads and step outputs, `sdk_url` call-back" vs the CTO's 2026-10-14 code read: only event payloads, the `/v1` read-back and the `--sdk-url` registration poll are on the plain hop; step execution is a different path whose transport is not asserted), and the follow-up list: the inherited "TLS 1.3 minimum on all Customer-facing endpoints" in `data-processing-agreement-template.md` line ~180, and the three plaintext-exception ledger strings that still say the published sentence is "referred to the 2026-10-24 ruling"; (ii) finish all wording edits; (iii) go to step 2.
2. Final pin: set the `Last Updated` date `<D>` to the day of the final push on all six surfaces (2 canonical bodies, 2 mirror bodies, 2 mirror heroes), recompute and paste both hashes, run the Phase 4 gates. Only then spawn the CLO agent with the FINAL diff for attestation (Tier 2 sign-off per `tc-version-bump-policy.md`) and record `Ruled by CLO agent, <date>: ...` in the PR body. No owner question. If the day rolls over after the attestation, repeat step 2 (a date-only change; the CLO re-attests the date).
3. **Sibling-PR sequencing.** Open DRAFT PRs #10291 (Better Stack SCC wording), #9051 (codex web) and #8626 (ledger root disks) also touch `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`, `apps/web-platform/lib/legal/legal-doc-shas.ts` and/or `article-30-register.md` - different passages, but the `Last Updated` paragraph is one line that #10291 (and possibly #9051) also prepend to, and the two hash lines are shared. **Whichever PR merges second re-pins `legal-doc-shas.ts` after merging `origin/main`**: do one `git merge origin/main`, resolve the `Last Updated` conflict by keeping every entry in date order (accuracy decides), recompute both hashes with `sha256sum` from the merged canonical files (never take either side's literal), re-run Phase 4, and have the CLO agent re-attest the merged diff. This PR must not edit those PRs' passages (Better Stack SCC wording; codex web; ledger root disks and Article 30 anchoring). If another PR merges ahead while this one is in the queue, the `merge_group` run of `tc-document-sha-guard` goes red on the stale pin: re-pin and re-queue.
4. PR body: `Ref #10138`, `Ref #10136` (never `Closes`), Tier 2 classification, the two `operator (scope)` items from decision-challenges.md plus the DPA-template line (CLO R1), the DPD (c) deviation from the brief's literal text and why, and the explicit statement that no TLS is added and no exception is renewed.
5. Ship via the merge queue; then run `soleur:postmerge`. Post-merge checks: the live site pages `https://soleur.ai/legal/privacy-policy/` and `https://soleur.ai/legal/data-protection-disclosure/` contain the new sentences (the Eleventy docs deploy), and `check-tc-document-sha` is green on `main`. Emit DONE only after the literal line `postmerge verification complete!`.

## Acceptance Criteria

Diff checks below use word-level added text, because the touched register and `Last Updated` lines are single paragraphs of 1 to 38 KB and a whole-line diff returns every pre-existing token on them: `ADDED() { git diff -U0 --word-diff=porcelain origin/main...HEAD -- "$@" | grep -E '^\+[^+]'; }` (tested on a scratch repo: one `+` line per contiguous added run; `+++` file headers are excluded).

**Byte-level span check (ruled by CTO agent, 2026-10-14; word-diff alone is a reviewer aid, not the gate).** For every edited file, a throwaway script run with `python -I` and kept out of the repo loads the `origin/main` version and the working version, asserts each intended old span occurs exactly once in the old file, replaces it with the intended new text, and asserts the result is byte-identical to the working file. This is the acceptance check for AC8 and every "only these spans changed" claim; a failure blocks marking the PR ready.

### Pre-merge (PR)

- [ ] AC1. `grep -c 'All communication with the Web Platform is protected by TLS' docs/legal/privacy-policy.md plugins/soleur/docs/pages/legal/privacy-policy.md` prints 0 for both, and the exact new bullet text of Phase 1a appears exactly once in each.
- [ ] AC2. In both DPD files, `TLS for data in transit` no longer occurs, the Phase 1b (c) bullet occurs exactly once, and the string `NOT YET FULFILLED as to server-to-server transport encryption` is present; `FULFILLED` in (c) appears only inside the two scoped markers.
- [ ] AC3. All Phase 4 gates are green: `sha256sum` of the two canonical files equals the two `LEGAL_DOC_SHAS` literals; `check-tc-document-sha.sh`, the drift ratchet (no new drift lines; the pre-existing `#7465` warning is allowed), `lint-encryption-posture.py --repo-sweep`, `lint-legal-registers.sh`, `probe-legal-corpus-truth.sh`, `legal-doc-consistency.test.ts` and `legal-doc-shas-guard.test.ts` (Last Updated date identical on canonical body, mirror body and mirror hero for both docs; check with `Last Updated[: *]+<D>` or two separate counts - hero has no colon, body has `:**`).
- [ ] AC4. Register, per anchor (not a whole-file count): the original text of each of the four TLS lines (PA-1 `TLS 1.2+ in transit.`, PA-2 `TLS in transit.`, PA-3 `TLS 1.2+ in transit;`, Cross-Cutting `TLS 1.2+ enforced everywhere`) is still present unedited, and each is followed (in its own cell or list item) by a marker containing `Superseded <d> (#10136)`; PA-1 and Cross-Cutting carry the full four-part text, PA-2 and PA-3 the one-clause form naming `PA-13 (g)(14)`.
- [ ] AC5. Register: PA-13 (g) contains `(14) **Plaintext private-network transport of Inngest events`; PA-3 carries its inline `Added <d> (#10136)` pointer; PA-16, PA-17, PA-21, PA-22, PA-27, PA-29 each carry exactly one `Added <d> (#10136)` pointer naming `PA-13 (g)(14)` and no field list; PA-4, PA-6, PA-14, PA-18, PA-31, PA-36 have zero diff lines; `last_reviewed: 2026-09-14` is unchanged.
- [ ] AC6. Every added register sentence carries one provenance label from the CLO vocabulary and none uses the bare word "measured": `ADDED knowledge-base/legal/article-30-register.md | grep -E '[^-a-z]measured'` returns no hit (the mandated "re-measured" has a preceding `-` and is excluded).
- [ ] AC7. Ledger diff is exactly one changed line (the `disclosed_as` value); no `expires_on` / `exception` / `tls` / `cert_verification` line is in the diff. DPA template diff is exactly the one list item of Phase 3b.
- [ ] AC8. `git diff --stat origin/main...HEAD` lists only the Files-to-Edit above plus the files the pipeline itself writes (this plan, `specs/feat-one-shot-legal-tls-wording-10136/{tasks.md,decision-challenges.md,session-state.md}`, a regenerated `knowledge-base/INDEX.md` if the pipeline emits one). Untouched passages, by word-level diff: `ADDED docs/legal/gdpr-policy.md plugins/soleur/docs/pages/legal/gdpr-policy.md` returns nothing; the retracted July 2 entries and the Cloudflare `TLS termination` lines have no removed (`-`) word-diff chunk (`git diff -U0 --word-diff=porcelain origin/main...HEAD -- docs/legal | grep -E '^-[^-]'` returns nothing, as nothing in the published docs is deleted except the two replaced sentences, which are named in AC1/AC2 - inspect each hit against that list).
- [ ] AC9. Forbidden-claim check on word-level added text. Published docs (`ADDED docs/legal/privacy-policy.md docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/privacy-policy.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md`): zero matches for `end-to-end`, `everywhere`, `Supabase`, `Cloudflare`, `nftables`, `10\.0\.1\.`, `wire`, `packet`, and zero dates adjacent to `TLS` (the Last Updated date itself is allowed). Register (`ADDED knowledge-base/legal/article-30-register.md`): `everywhere` only inside the quoted `"TLS 1.2+ enforced everywhere"` anchor; `nftables` only inside "host-local nftables peer restrictions in (11) are inherited" and "nftables restrictions: inherited, not re-measured 2026-10-12, not asserted"; `Cloudflare`, `10.0.1.`, `FULFILLED`, `web-1`, `web-2` zero; `wire` only in "not a wire capture". DPA template: zero `Cloudflare`.
- [ ] AC10. PR body contains `Ref #10138` and `Ref #10136`, contains no `Closes`/`Fixes`/`Resolves`, states Tier 2, lists the `operator (scope)` items and the DPD (c) deviation, and carries the CLO agent's attestation of the final diff.
- [ ] AC11. Claim-to-source trace (absence greps test shape, not truth): the PR body carries a table that lists each register CLAIM first and its call site second. Claims: event payloads for PA-3 / PA-17 / PA-21 / PA-22 / PA-27 / PA-29 / PA-16 cross the plain-HTTP hop; PA-22's failure-path forward of the original event plus `error.message`; the event key rides in the `/e/<key>` path; the signing key is the bearer on `/v1` reads; the plain-HTTP base URL is configured. Call sites (re-opened at work time): `app/api/webhooks/stripe/route.ts` (`finance.payment_failed`); `app/api/webhooks/github/route.ts`; `app/api/dashboard/today/[id]/send/route.ts` (`agent.spawn.requested`); `agentOnSpawnRequestedOnFailure` (`step.sendEvent("forward-orphan")`) under `server/inngest/functions/`; `app/api/webhooks/resend-inbound/route.ts` (`email/inbound.received`); `server/routines/run-routine.ts` and `app/api/dashboard/routines/run/route.ts` (`actor_id`); no Inngest reference in `server/action-sends/write-action-send.ts` (PA-16 row identifier only); the event-key path in the pinned SDK (`apps/web-platform/node_modules/inngest/components/Inngest.js`, `inngest@3.54.2`: `this.sendEventUrl = new URL(`e/${this.eventKey}`, this.eventBaseUrl || ...)`) and the signing-key bearer in `apps/web-platform/lib/inngest/list-runs.ts` (`Authorization: Bearer ${signingKey}`), re-read at work time against the then-installed version; the `INNGEST_BASE_URL` variable (name only, no address) in `apps/web-platform/infra/ci-deploy.sh` and `cloud-init.yml`; step execution on `serveHost` in `app/api/inngest/route.ts`. A claim whose call site no longer exists at work time is dropped, not reworded.
- [ ] AC12. No workflow dispatch, `terraform apply`, Doppler write, volume wipe or destroy occurred; no ledger exception was renewed or re-dated.
- [ ] AC13. One comment on #10136 posted before the PR is marked ready (Phase 5 step 1); #10136 and #10138 remain open.

### Post-merge

- [ ] AC14. `soleur:postmerge` finishes with the literal line `postmerge verification complete!`; the two live soleur.ai legal pages contain the new Privacy Policy bullet and the new DPD (c) text (probe pre-run read-only on 2026-10-14: `curl -s https://soleur.ai/legal/privacy-policy/ | grep -c 'All communication with the Web Platform is protected by TLS'` prints 1 today and must print 0 after deploy; same for `TLS for data in transit` on `/legal/data-protection-disclosure/`; both pages return HTTP 200); the required `tc-document-sha-guard` context is green on `main`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ship the CLO-ruled legal wording correction as ONE separate mirror-paired PR, merged by 2026-10-24" [brief] | Phase 1-5, Files to Edit 1-6 | mapped |
| 2 | "Privacy Policy section 11 bullet \"Encryption in transit\" ... replace with exactly" [brief] | Phase 1a, AC1 | mapped |
| 3 | "DPD section 8.1(c) \"TLS for data in transit ... FULFILLED\" ... replace with exactly ... Do NOT mention Supabase" [brief] | Phase 1b, AC2, AC9 | mapped (CLO restructure, decisions row 1-2) |
| 4 | "Article 30 register ... add dated in-cell qualification plus a \"> **Superseded <date> (#10136)**\" marker on the TOM lines" [brief] | Phase 2a-2d, AC4 | mapped |
| 5 | "add a plaintext-private-network entry to the Inngest-carrying activities (PA-13 ~265, PA-21/22); verify each line yourself before editing and check PA-3/4/6 for Inngest routing; PA-36 needs no new entry" [brief] | Phase 2e-2g, AC5, AC11 | mapped |
| 6 | "LEAVE UNEDITED: the retracted July 2 2026 'Last Updated' history entries ... and the Cloudflare 'TLS termination data' hits" [brief] | AC8 | mapped |
| 7 | "MUST NOT CLAIM: end-to-end/all/everywhere/FULFILLED transport encryption; ..." [brief] | AC9 | mapped |
| 8 | "re-pin apps/web-platform/lib/legal/legal-doc-shas.ts; run bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main and apps/web-platform/scripts/check-tc-document-sha.sh" [brief] | Phase 4, AC3 | mapped |
| 9 | "Every ledger/register sentence must say whether it is measured, policy or inherited, and mark past measurements with their date" [brief] | Phase 2 vocabulary, AC6 | mapped |
| 10 | "the plan must say that whichever merges second re-pins legal-doc-shas.ts after rebasing, and must not edit their passages" [brief] | Phase 5 step 3 | mapped |
| 11 | "PR body uses 'Ref #10138' and 'Ref #10136', never Closes; ship via the merge queue and run soleur:postmerge, emitting DONE only after 'postmerge verification complete!'" [brief] | Phase 5 steps 4-5, AC10, AC14 | mapped |
| 12 | "no workflow dispatch, terraform apply, Doppler write, volume wipe or destroy ...; do not renew an encryption-posture exception to turn a lint green; do not claim reopen, passphrase-loss recovery (#9948), re-escrow (#9949), the state-restore substrate (#7992) or emptiness for web-2" [brief] | AC12; none of those claims appears in any inserted text | mapped |
| 13 | "Local gate: skip test-all --affected and rely on CI's required test context; run only focused suites." [brief] | Phase 4 | mapped |
| 14 | "technical rulings go to the CTO agent, legal ones to the CLO agent" [brief] | decisions table; Phase 5 step 1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files 1-4 (PP and DPD, canonical + mirror) | "and its mirror plugins/soleur/docs/pages/legal/privacy-policy.md (~652)" | asked (asks 2-3) |
| File 5 (`legal-doc-shas.ts`) | "re-pin apps/web-platform/lib/legal/legal-doc-shas.ts" | asked (ask 8) |
| File 6 (register) | "knowledge-base/legal/article-30-register.md: add dated in-cell qualification" | asked (asks 4-5) |
| Last Updated entries (Phase 1c) | - | inferred - justification: `tc-version-bump-policy.md` requires the Last Updated line to summarise the substantive delta for a Tier 1/2 edit and the CLO agent ruled yes on 2026-10-14; omitting it leaves the October 13 entry contradicting the page |
| Mirror hero date (Phase 1d) | - | inferred - justification: `legal-doc-consistency.test.ts` requires hero and body dates to be identical or CI fails |
| Pointers on PA-16, PA-17, PA-27, PA-29 (Phase 2f) | "add a plaintext-private-network entry to the Inngest-carrying activities" | inferred - justification: the cells themselves carry no TLS sentence, so the pointer is not correcting an overstatement there; it makes the register traceable per activity for an Art. 30(4) reader, the CTO code read of 2026-10-14 shows their event payloads cross the hop, and the CLO ruled yes (Q6, R3: no field lists). Surfaced as an `operator (scope)` row; PA-13 (g)(14) alone would satisfy P4, so deleting these four sentences is a valid reversal |
| Pointer on PA-3 (Phase 2c) | "check PA-3/4/6 for Inngest routing" | asked (the PA-3 TOM line also carries a TLS sentence, so it takes the marker as well) |
| File 7 (ledger `disclosed_as`) | - | inferred - justification: the DPD edit removes the anchor `TLS for data in transit`; the pointer would dangle in a compliance artifact (CLO Q3); no exception is renewed |
| File 8 (`data-processing-agreement-template.md` one list item) | - | inferred - justification: a plan reviewer found the sentence "Hetzner-terminated TLS at internal HTTP hops" in a customer-facing draft headed for execution; it states the very hop this PR corrects, and the CLO ruled (R1) to edit it. Surfaced as an `operator (scope)` row; reversal is dropping one list item |
| Comment on #10136 (Phase 5 step 1) | - | inferred - justification: the CLO ruled the ledger/issue-vs-code discrepancy detail belongs in a #10136 comment, not in legal prose |
| CLO attestation of the final diff (Phase 5 step 2) | "route any wording doubt to the CLO agent, not to the owner" | asked |

### Split Assessment

- Subsystems touched: 5 - `docs/legal`, `plugins/soleur/docs`, `apps/web-platform/lib/legal`, `knowledge-base/legal` (register + DPA template), `scripts` (one ledger value).
- Planned files: 8 edited + 2 spec artifacts | Estimated changed lines: roughly 40 (almost all in a few very long lines).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR** despite the root count. The brief mandates "ONE separate mirror-paired PR"; canonical, mirror and SHA pin must land together or the required `tc-document-sha-guard` context goes red; and splitting the register from the published text would leave the register contradicting (or lagging) the policy for however long the second PR waits. The root count is a mechanical consequence of mirror pairing, not scope breadth.

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal

**Status:** reviewed
**Assessment:** CLO agent rulings of 2026-10-14 (Q1-Q8 and the plan-review follow-ups R1-R4) are carried verbatim into Phase 1-3 and recorded in decision-challenges.md. Key calls: split FULFILLED status in DPD (c); Tier 2 with a Last Updated entry; ledger `disclosed_as` -> `not-publicly-claimed`; register scope and marker forms; provenance vocabulary. Final-diff attestation is a Phase 5 step.

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruling of 2026-10-14: seven activities' event payloads cross the plaintext hop (code read, no wire capture); step execution is not on it; do not name private IPs; one canonical register note with per-activity pointers. No infrastructure, code or workflow change; nothing in `apps/*/server`, `src` or `infra` is edited.

No Product/UX gate (no user-facing UI surface; published legal prose only). No CMO/CRO/COO/CFO/CCO implications. GDPR gate (`soleur:gdpr-gate`) not separately run: no schema, migration, auth-flow or API surface is touched and none of the Phase 2.7 (a)-(d) triggers fires; the CLO agent owns the substantive review of this transparency correction.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Privacy Policy or DPD page that still says all communication is TLS-protected (overstated), or a rewritten sentence that over-corrects or drops a true status (for example removes "encryption at rest ... FULFILLED"), or a docs build that fails and leaves the old text live.
- **If this leaks, the user's data is exposed via:** no new exposure vector - the PR publishes no data, only a corrected description. The disclosed fact (event payloads on a private-network plain-HTTP hop) is already true; the exposure it describes exists independently of this PR and is tracked on #10136.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a wrong transport-security sentence in a published policy misleads every reader at once, but no single reader's account, data or money is put at new risk by this edit, so `single-user incident` (CPO sign-off) is not warranted; `none` is rejected because the PR edits a published Art. 13 disclosure.

## Test Scenarios

No application code changes, so no new unit test (`cq-write-failing-tests-before` governs code). The verification is the existing gates plus a diff-level check of the exact new strings:

1. Phase 4 gate list: each exits 0 / PASS.
2. Mirror parity spot check: `diff <(grep -n 'Encryption in transit' docs/legal/privacy-policy.md | cut -d: -f2-) <(grep -n 'Encryption in transit' plugins/soleur/docs/pages/legal/privacy-policy.md | cut -d: -f2-)` prints nothing; same for the DPD (c) bullet.

## Risks and Sharp Edges

- **Line numbers drift** between plan time and work time (siblings are active). Every edit locates its target by the quoted content anchor; the line numbers above are orientation only.
- **One-line paragraphs of 1 to 38 KB.** An editor that rewraps, or a `sed` with a metacharacter in the anchor, can corrupt the register. Use exact-string replace with a count-equals-one assertion, then `git diff --word-diff` to confirm only the intended spans moved.
- **Straight vs curly apostrophe** in `Jikigai's`: match the document's character; AC1 greps the exact string.
- **Two real conflict surfaces** with open drafts: the `Last Updated` one-liner (#10291 and possibly #9051) and the hash lines. Phase 5 step 3 states the resolution; do not rebase repeatedly (one merge).
- **The ledger rows still say "published unqualified TLS sentence ... referred to the 2026-10-24 CLO ruling"** after this PR. By ruling that stays true history and is rewritten in a separate record edit; do not "tidy" it here.
- **Do not describe the step-execution path at all** (not even as HTTPS): that would implicitly speak to Cloudflare-to-origin TLS, which is out of scope and unmeasured.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- The register's own HSTS statement (`HSTS on app.soleur.ai`) is neither re-asserted nor qualified here; do not extend the marker to it.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Use the brief's DPD clause as a literal one-for-one replacement of `TLS for data in transit` | Leaves `**FULFILLED.**` attached to an item that now contains a not-yet-encrypted statement; the brief itself forbids FULFILLED transport encryption (CLO ruled the split instead) |
| Re-anchor the Supabase `disclosed_as` to `TLS for browser-to-platform connections` | Asserts a DPD disclosure of the server-to-Supabase leg that does not exist; the lint would still pass, hiding it (CLO ruled `not-publicly-claimed`) |
| Duplicate the full plaintext note in every Inngest-carrying activity | Eleven drifting copies of one transport statement; the register already documents the marked/unmarked confusion (CTO rule A) |
| Wait for Inngest TLS before correcting the wording | The CLO deadline is 2026-10-24 and the published sentence is an overstatement today; the correction stands regardless of the remediation date (2026-11-12 horizon on #10136) |
| Edit the ledger exception justifications to match the new wording | Out of scope and would touch rows that are due for their own re-evaluation; rule in force against renewing exceptions to turn a lint green |

## Deferral Tracking

Nothing is deferred without a tracker. The TLS remediation itself, the ledger exception expiry (2026-11-12 horizon) and the broader-vs-narrower description of the hop all live on #10136 (open); the overdue mirror-drift remediation is #7465 (pre-existing, untouched). No new issue is needed.

## Review-round amendments (2026-10-14/15)

An 11-seat review of the first implementation (SHA 02e2ebbfcc) returned findings that change this plan's text; the rulings are rows in `decision-challenges.md` (review round). Where this plan and those rows differ, the rows govern: Tier 1 (not Tier 2) with in-place `Corrected <date>` marks and a `tier_classification` attestation file; the status sentence scoped to API-key encryption at rest; `own servers` and `job scheduler` wording changed; `plan to add TLS` replaced by `evaluating`; section references to 4.13 and 2.3(o)/(aa); DPA template item and line ~180 reworded without a TLS 1.3 claim; register pointers shortened and the exclusivity words removed; the signing-key discrepancy recorded. Dates are the day of the correction (October 15, 2026). The edit scripts are not committed; the byte-level check was re-run against the regenerated files.
