---
title: "fix(legal): retract the three unachievable multi-host clauses, re-scope the LUKS clause to the live single-host topology, and reaffirm the retained-plaintext HOLD while escalating its blocker #6808 (#6588 legal half)"
date: 2026-07-24
type: fix
issue: 6588
refs: [6897, 6893, 6808, 6570, 6604, 3723]
lane: cross-domain
brand_survival_threshold: single-user incident
plan_time_signoff: CLO   # Product = NONE (zero UI surface); the risk axis is legal-claim-vs-reality.
requires_cpo_signoff: false
live_infra_mutation: none
runtime_deploy_risk: none
adr_refs: [ADR-119, ADR-140, ADR-141, ADR-084]
deepened: 2026-07-24
amended: 2026-07-24   # D3 replaced: operator reaffirmed the UC-3 hold; escalate #6808 instead
---

# fix(legal): #6588 legal half — retract, re-scope, escalate

> **AMENDED 2026-07-24 (operator decision).** Deliverable 3 originally recommended adding an
> affirmative disclosure sentence about the retained pre-cutover plaintext volume to all five
> published LUKS sites, reversing the operator's same-day HOLD (UC-3, PR #6918). The question was
> re-raised with the full revisit-trigger analysis and **the operator reaffirmed the hold.**
> **No published legal text in this PR gains a sentence about the retained plaintext copy.**
> Deliverable 3 is now *reaffirm the hold and escalate the blocker* (#6808). Deliverables 1, 2 and
> 4 are unchanged. Every section below reflects the amendment.

## Enhancement Summary

**Deepened:** 2026-07-24
**Amended:** 2026-07-24 (D3 replaced — see the note above)
**Review panel:** `architecture-strategist`, `spec-flow-analyzer`, `code-simplicity-reviewer`
(escalated per `single-user incident`), plus the `clo` legal domain review invoked at plan time,
a verify-the-negative sweep, and a banner-precedent history check.

### Key improvements folded from review

1. **A `## Site Matrix` now supersedes every prose site list (P0, all three reviewers).** The
   three panels returned **conflicting** inventories, so every site was re-measured directly. The
   matrix corrected the plan in *both* directions: `dpd:276` **does** carry the LUKS claim
   (spec-flow said it does not) and `gdpr:318` **does not** (this plan's first draft said it did —
   following it would have *added* a LUKS claim to a document that publishes none, inside a
   retraction PR). It also surfaced `pp:298`, which carries the entire claim family and had **no
   disposition in any deliverable**, and added `dpd:318`.
2. **AC1 and AC7 were mutually unsatisfiable.** AC7 requires the July-2 banner segment to survive
   byte-identical; that segment *contains* the phrases AC1 demanded reach zero. AC1 is now scoped
   to body prose with the banner line excluded.
3. **Three ACs were measuring nothing.** `grep -c 'Previous:'` returns **1** on a single-line
   banner (18/17/17 real occurrences) — the count check was inert. `grep -c '<date>'` returns
   **2**, not 1, in `pp` and `gdpr` (banner + in-prose annotation), so AC5's premise was already
   false. AC7 now uses substring-preservation (empirically validated to pass an end-append and
   **fail** a mid-segment insertion), and AC5 uses the gate's own extraction regexes.
4. **The Art. 30 fold-in was under-scoped in exactly the way it warned against.** It covered only
   the `(g)` TOM cells while `(d) Recipients`, `(e) Transfers` (×2) and the vendor mapping still
   assert a destroyed host and an unborn CAX11 — **Art. 30(1)(d)/(f)** limbs, a *stronger*
   obligation than the TOM prose it did cover.
5. **A conditional branch that would have silently reclassified the PR was removed.** An earlier
   §4f fallback authorized editing `scripts/lint-encryption-posture.py` plus tests inside a PR
   declaring `runtime_deploy_risk: none`. Removed; the linter blind spot is filed against #6893
   instead. *(Post-amendment the branch is doubly moot — the `hcloud_volume.workspaces` row is not
   edited at all — but the #6893 filing stands on its own; see §4f.)*
6. **Phase 0's RED path was a dead end** ("stop", then "retraction becomes correct") with no
   downstream AC re-scoped. Now a defined DEGRADED-SCOPE branch.
7. **The audit trail is written first (Phase 1.5), not last.** Post-amendment it records a
   challenge **raised and resolved in favour of the operator's original position**, so there is no
   reversal for it to guard. It stays in Phase 1.5 because Phase 5's escalation comment and the
   CLO attestation both cite it, and because the record of a *retained* live over-claim is the
   more important artifact, not the less.
8. **Scope cuts:** the #3723 Art. 17 note (an *addition*, not a correction → posted to #3723
   instead), an `nfr-register:521` no-op row, AC2's un-artifacted ritual, and three-quarters of
   AC13. `## Observability` and `## Encryption Posture` were converted from non-compliant skip
   notes to real schemas — the gate applies here (`legal-doc-shas.ts` + the ledger are not docs).

### New considerations discovered

- **The mirror banners carry truncated history** (12/13/11 `Previous:` occurrences vs 18/17/17
  canonical). Pre-existing, passes CI, and **"fixing" it would append multi-KB of historical text
  to published legal documents.** Acknowledged, not folded in.
- **A `Falkenstein` sweep must carve out `eu-fsn-3`** — Better Stack's region is *genuinely*
  Falkenstein. Scrubbing it would delete a true sub-processor disclosure and later redden
  `validate-vector-config.yml`.
- **The ledger's `privacy-policy.md:519` anchor is dead, not merely decorative** — the file
  contains zero occurrences of the literal `519`, and the resolver's unresolvable branch is marked
  `# Fail CLOSED`, so it becomes a hard CI failure the moment that row's mechanism changes.
- **The retained-plaintext residual may concern one backstop or two.** `hcloud_volume.git_data` is
  ledgered as a backstop for a cutover that never happened (the host was never born, #6570 OPEN) —
  its contents are genuinely unestablished. **Moot for this PR** post-amendment (no sentence is
  written), but it is a live precondition for the *deferred* Path-2 wording: whoever writes it
  must first establish whether that volume holds any user data. Carried into the #6808 escalation
  comment (§Deliverable 3) so the question is not lost with the hold.
- **10 of 10 negative claims verified**, zero contradictions (see §Research Insights).

## Overview

Issue **#6588** (OPEN, `priority/p0-critical`, `type/security`) has two halves. The
**encryption half is DONE**: web-1 `/mnt/data` runs on the LUKS `workspaces_luks` mapper,
certified by `workspaces-luks-verify` run **30040444418** (2026-07-23 20:02:33Z, `success`,
`headBranch: main`). This plan is the **legal half**, which is entirely unstarted on `main`.

Four deliverables, one PR:

1. **RETRACT** three clauses #6588 marks as never-achievable (cross-host TLS; membership
   re-verification across hosts; the dedicated per-workspace git-data host).
2. **RE-SCOPE** the LUKS clause so it is true as written on the actual single-host topology
   (its current "Where the Web Platform spans more than one Hetzner host" premise is dead).
3. **REAFFIRM + ESCALATE** — record that the retained-plaintext disclosure question was re-raised
   with its revisit-trigger analysis and that the operator **reaffirmed the HOLD**; then escalate
   **#6808**, the blocker that gates the cure, recording that it now gates a *live published
   over-claim*. **No published legal text gains a plaintext-disclosure sentence in this PR.**
4. **MECHANICS** — re-pin `legal-doc-shas.ts`, close DC-1, append+annotate the provenance
   banner, correct the internal registers, reconcile with #6897.

> **The residual is not hidden — it is unpublished.** It stays recorded internally in
> `scripts/encryption-posture-ledger.json` (`hcloud_volume.workspaces`, `mechanism:
> plaintext-exception`, `tracking_issue: #6897`) and, per §4d, in `article-30-register.md`. What
> the operator held is the *public* sentence, not the internal record.

The governing principle, from the learning this issue produced
(`2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`):

> A claim family is removed **whole or not at all** — never just its head.

The 2026-07-16 attempt removed the git-data host and left the LUKS clause dangling, which made
a false Art. 32 claim *stronger*. This PR removes the family whole.

---

## Premise Validation (Phase 0.6)

Every premise the task statement carries by reference was verified live this session, by
reading, not by assuming. Two of them moved.

| # | Premise as given | Verified state (2026-07-24) | Disposition |
|---|---|---|---|
| P1 | #6588 OPEN, P0-critical | **HOLDS.** `state: OPEN`, labels `priority/p0-critical`, `domain/engineering`, `type/security` | Plan against it |
| P2 | Encryption half certified 2026-07-23, run 30040444418 | **HOLDS.** `conclusion: success`, `createdAt: 2026-07-23T20:02:33Z`. Note the 4 prior runs all `failure` — this is the first green | Re-verify live at /work (Phase 0) |
| P3 | #6808 OPEN, blocks soak + Phase-5 wipe | **HOLDS.** Body confirms `WORKSPACES_LUKS_HEARTBEAT_URL absent — heartbeat not pushed`. `workspaces-luks-soak-6604.sh` gates on the heartbeat being **present** and rows spanning **≥7d**, so the soak clock has not started | Material — this is both the revisit-trigger analysis put to the operator and the **escalation target**; see §Deliverable 3 |
| P4 | git-data host "never born" | **HOLDS.** #6570 still OPEN: *"git-data is pinned to cax11 — orderable in 0 of 3 EU DCs, so it can never be born"* | Retract clause (c) |
| P5 | No load balancer; `app.soleur.ai` singleton to web-1 | **HOLDS.** `tunnel.tf:54` pins ingress to `var.web_hosts["web-1"].private_ip`; `model.c4:413` records single connector post-#6538 | Retract clause (b) |
| P6 | Clauses live in privacy-policy + DPD + 2 mirrors (**4 files**) | **STALE — UNDERCOUNT.** The claim family also lives in **`gdpr-policy.md`** and its mirror. **6 files**, not 4. Corroborated independently by #6897's own scope (`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`) and by DC-1's own "all 6 files" | Scope = 6 files |
| P7 | Clauses at "roughly lines 298 and 519" | **STALE — UNDERCOUNT.** **8 canonical body sites + 3 banner headers, ×2 = 22 sites** (see §Site Matrix). Three sites (`privacy-policy.md:489`, `gdpr-policy.md:318`, `data-protection-disclosure.md:318`) carry a claim with **no `LUKS` token at all** | Union-anchor sweep; **never** `grep LUKS` |
| P8 | #6897 owns a "legal-doc reconciliation" bullet | **HOLDS, and it already RAN.** PR **#6918** merged 2026-07-24 17:55 CEST; the operator **HELD** the copy fix (UC-3), and **REAFFIRMED that hold on 2026-07-24** when this plan re-raised it | See §Deliverable 3 + §Issue Reconciliation |
| P9 | *(implicit)* users are exposed today | **ZERO arms-length data subjects.** #3723 OPEN; the volume holds the operator's own dogfooding workspaces | Makes the correction **cheap now**; see §User-Brand Impact |

**P7 is the load-bearing correction.** A literal-phrase sweep is the documented failure mode
here (Session Error #2 of the #6588 learning: *"sweep the semantic quantity, not its
formatting"*). My own first-pass grep for `"across hosts"` + `"spans more than one"` **missed**
`privacy-policy.md:489` and `gdpr-policy.md:318`, which phrase it `"across more than one host"`.
The prior #6588 plan had already recorded this trap; this plan inherits its union anchor.

---

## Research Reconciliation — task statement vs. repo reality

| Task statement | Repo reality | Plan response |
|---|---|---|
| "docs/legal/privacy-policy.md ... plus data-protection-disclosure.md plus BOTH Eleventy mirrors" | `gdpr-policy.md` + its mirror carry the same family. **6 files** | Scope widened to 6; AC1 asserts residual-zero across all 6 |
| "roughly lines 298 and 519" | **8** canonical body sites (§Site Matrix); **3** carry a claim with no `LUKS` token | Union-anchor grep (§Phase 1), content anchors not line numbers (`cq-cite-content-anchor-not-line-number`) |
| "re-pin legal-doc-shas.ts ... very likely a CI gate" | **Confirmed.** `tc-document-sha-guard` (required check, ADR-032-pinned name) via `check-tc-document-sha.sh`. Raw-byte `sha256sum`, **no bypass** for non-T&C docs | Phase 4; 3 SHAs |
| "possibly a cross-document consistency gate" | **Confirmed, and it is stricter than expected.** `legal-doc-consistency.test.ts` asserts (a) `##`/`###` heading-sequence parity canonical↔mirror, (b) **Last-Updated date byte-identical in 3 places per mirror** (canonical body, mirror body, mirror hero `<p>`) | Phase 3 + AC5; **9 date strings** total |
| "Follow the repo's ... 'Last Updated' provenance banner" convention | It is a **single line of 27,358 characters / 27,492 bytes** (UTF-8 multibyte — quote the unit), prepend-style: `**Last Updated:** <new> (...). Previous: <old> (...)` | Phase 3; §Banner Handling |
| "Close DC-1 ... Status is 'OPEN — remediation tracked, exposure accepted'" | **Confirmed verbatim** at `specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` | Phase 5 |
| "Check whether #6897 ... would be partly or fully satisfied" | #6897 **stays OPEN by operator decision**; its legal bullet already ran and **held** the fix | §Issue Reconciliation — `Ref`, never `Closes` |
| *(not in task)* Art. 30 register carries the same 4 claims | `article-30-register.md` restates them as Art. 32 TOM items **13–16 and 17–20** across two PAs | **Folded in** (CLO B2) |
| *(not in task)* `compliance-posture.md:80` | Hetzner DPA "Covers ... the git-data host CAX11" — never ordered | **Folded in** (CLO B2) |
| *(not in task)* `nfr-register.md:522` | "Hetzner web/workspaces server volumes not encrypted at disk level" — now **false** (an under-claim, but stale) | **Folded in** (2 rows) |
| *(not in task)* posture ledger `disclosed_as` | `workspaces_luks` row cites `docs/legal/privacy-policy.md:519` — the exact clause being rewritten | **Folded in** (§Ledger Coupling) |

---

## Site Matrix (authoritative — measured 2026-07-24, supersedes all prose site lists)

Three plan-review agents produced **conflicting** site inventories. This matrix is the tie-break:
it was produced by reading every matching line and probing each claim independently, and it is the
single source of truth for every deliverable and AC below. **Where any prose in this plan disagrees
with this table, the table wins.**

| Canonical | Mirror | LUKS | (a) TLS | (b) re-verify | (c) git-data host | web-2 | multi-host premise |
|---|---|---|---|---|---|---|---|
| `privacy-policy.md:298` | `:297` | **Y** | Y | Y | Y | Y | – |
| `privacy-policy.md:489` | `:475` | – | – | – | – | Y | Y |
| `privacy-policy.md:519` | `:500` | **Y** | Y | Y | Y | – | Y |
| `data-protection-disclosure.md:189` | `:186` | **Y** | Y | Y | Y | Y | – |
| `data-protection-disclosure.md:276` | `:261` | **Y** | Y | – | Y | Y | Y |
| `data-protection-disclosure.md:318` | `:301` | – | – | – | – | – | – |
| `gdpr-policy.md:44` | `:53` | **Y** | Y | Y | Y | Y | Y |
| `gdpr-policy.md:318` | `:306` | – | – | – | – | Y | Y |

**LUKS claim = 5 canonical sites** (`pp:298`, `pp:519`, `dpd:189`, `dpd:276`, `gdpr:44`) + 5 mirrors
= **10**. Corrections this matrix forces on the review panel and on this plan's own earlier drafts:

- **`dpd:276` DOES carry the LUKS claim** (spec-flow asserted it does not — measured `LUKS=Y`).
- **`gdpr:318` does NOT** (this plan's first draft asserted it does — measured `LUKS=.`). Following
  that draft would have *introduced* a LUKS claim into a document that publishes none, inside a
  retraction PR.
- **`pp:298` carries the entire family** and had no disposition in any deliverable body — it was
  listed only in Files to Edit. It is the most-read instance.
- **`dpd:318`** is a Hetzner two-DC transfer claim (*"Helsinki, Finland **and Falkenstein,
  Germany**"*) — stale post-retirement, and it carries **none** of the union-anchor tokens. Added.

> **CARVE-OUT — do NOT sweep `Falkenstein` blindly.** `pp:379` / mirror `:378` and `dpd:103` /
> mirror `:112` say *"Better Stack … EU region — Hetzner **Falkenstein** cluster `eu-fsn-3`"*.
> That is a **different processor**, its region is genuinely Falkenstein, and the claim is **true**.
> Scrubbing it would delete an accurate sub-processor disclosure **and** later turn
> `validate-vector-config.yml` red (it greps that source-ID/cluster string). Any `Falkenstein`
> sweep must exclude `eu-fsn-3` / `Better Stack`.

> **Phrase-variance warning (this plan's own R2 defect, caught in its own AC).** The web-2 claim is
> phrased **three** ways: *"**is** in Falkenstein"* (`pp:489`, `gdpr:318`), *"**has been** in
> Falkenstein"* (`pp:298`, `gdpr:44`), and a table-cell form (`dpd:189`, `dpd:276`). An AC anchored
> on the literal `web-2 … is in Falkenstein` returns **green while the most-read instance
> survives**. **Match the bare token `web-2`**, never the sentence.

## Deliverable 1 — Retract the three unachievable clauses

The three clauses, with the live evidence that each can never be true:

| Clause | Evidence it is unachievable | Verified |
|---|---|---|
| (a) *"traffic between the hosts is encrypted in transit with TLS"* / *"host↔host traffic TLS-encrypted (in transit)"* | No cross-host git traffic exists. web-2 retired 2026-07-17; `var.web_hosts` is single-host | `model.c4:413`, #6538 |
| (b) *"membership is re-verified when a session is served across hosts"* / *"re-verified on proxied sessions"* | No load balancer. `app.soleur.ai` ingress is pinned to web-1's private IP | `tunnel.tf:54` |
| (c) *"a dedicated per-workspace git-data host"* / *"a dedicated host for per-workspace git data"* | `cax11` orderable in **0 of 3** EU DCs (live Hetzner API 2026-07-16) | **#6570 OPEN today** |

**Retract, do not past-tense.** (a) and (b) were never true of the live platform at any moment
— there was never a served cross-host session to re-verify, and never cross-host git traffic to
encrypt. A past-tense rendering (*"traffic between the hosts was encrypted…"*) would assert a
historical fact that is also false. (c) likewise describes a host that never existed. **Delete
the claims; do not convert them.** The new banner entry carries the historical record instead —
that is the correct home for "we used to say this."

### Word-order trap (load-bearing)

`gdpr-policy.md:44` phrases clause (c) as **"a dedicated host for per-workspace git data"** —
different word order from the DPD's "a dedicated per-workspace git-data host". A literal
find-and-replace on either string misses the other. Both must be enumerated explicitly.

### The fourth, adjacent stale claim — FOLD IN

`privacy-policy.md:489` and `gdpr-policy.md:318` (+ mirrors) state, in present tense:

> a second web host (web-2, never user-serving) **is** in Falkenstein, Germany (`fsn1`)

web-2 was **retired 2026-07-17** (#6538/#6463). This is now false. It sits in the *same
sentence* as the "across more than one host" premise being corrected. Leaving it creates
exactly the dangling-claim defect the #6588 learning was written about. **Folded in.**

---

## Deliverable 2 — Re-scope the LUKS clause

Currently true: stored workspace data on web-1 sits on a LUKS-encrypted volume. Currently
false: the **premise** some instances hang it on.

Per the **Site Matrix**, the LUKS claim and the multi-host premise are *not* co-located — treat
them as two overlapping sets, not one:

| Site | LUKS | Multi-host premise | Action |
|---|---|---|---|
| `pp:519` | Y | Y — *"**Where the Web Platform spans more than one Hetzner host in the EU region**, …"* | Re-scope: drop the conditional, keep the claim |
| `dpd:276` | Y | Y — *"across more than one host"* | Re-scope: drop the conditional, keep the claim |
| `gdpr:44` | Y | Y | Re-scope: drop the conditional, keep the claim |
| `pp:298` | Y | – | Keep the claim; retract (a)(b)(c) + web-2 around it |
| `dpd:189` | Y | – | Keep the claim (table cell); retract (a)(b)(c) + web-2 around it |
| `pp:489`, `gdpr:318` | – | Y | Retract the multi-host premise + web-2. **Add no LUKS claim** |

Rewrite so the surviving claim stands on the **actual single-host topology**, unconditioned.

> **Two directional traps here, both verified.** (1) `pp:298` and `dpd:189` carry LUKS with **no**
> multi-host conditional — deleting their surrounding multi-host prose without re-anchoring the
> LUKS sentence leaves it dangling, which is *precisely* the #6588 defect. (2) `pp:489` and
> `gdpr:318` carry the premise with **no** LUKS — "re-scoping the LUKS clause" there would mean
> **adding** a claim to documents that publish none. Neither trap is visible without the matrix.

### Two bounding constraints on the rewrite

1. **Do not widen to "all data at rest is encrypted."** #6893 is the standing **claim-unlock
   gate**: until every user-data-bearing store reaches `luks` or `provider-managed:<attestation>`,
   external copy is constrained to the **verifiability** claim, not "encrypted by default."
   The ledger still carries **plaintext exceptions** for `hcloud_volume.git_data`,
   `hcloud_volume.inngest_redis` (#6894, highest sensitivity), and `redis.session_store`.
   The rewrite must remain scoped to **workspace git data on the serving host**.
2. **Do not import "EU region" as the new conditional.** `variables.tf:113` validation-pins
   `var.web_hosts` to `["nbg1","fsn1","hel1"]` — an **EU set**. Per the #6588 learning's design
   rule (*disclosure specificity should equal enforcement specificity*), EU-level is exactly the
   enforced invariant and is safe to keep; a host-count premise is not.

---

## Deliverable 3 — Reaffirm the hold and escalate the blocker

**Ruling: NO affirmative plaintext-disclosure sentence ships in this PR. The operator's UC-3 hold
STANDS, reaffirmed 2026-07-24. In its place, this PR escalates #6808.**

This deliverable produces **two artifacts and no published prose**: (1) a User-Challenge record of
the re-raise and its outcome, and (2) an escalation on #6808. Both are verifiable after the fact
(AC11, AC15).

### 3a. What was put to the operator, and what the operator decided

**The facts.** `hcloud_volume.workspaces` (plain ext4, `server.tf:1569`) holds a full copy of
every workspace as of the 2026-07-23 cutover. It is ATTACHED-UNMOUNTED and UN-WIPED, retained
as the ADR-119 rollback backstop. The ledger's own words:
`does_not_defend: "a seized/snapshot disk exposes any workspace data still resident on this volume."`

**The prior decision.** PR #6918 (merged 2026-07-24 17:55 CEST) ran `/soleur:legal-audit`, which
found exactly this as a **material over-claim of the #6588 class**. The operator **HELD** the copy
fix (UC-3), on the reasoning that *Path 1 (infra teardown) will cure it and is already tracked*.
The auditor's Path-2 wording was preserved verbatim for later. That decision is recorded in
`2026-07-24-holding-a-live-overclaim-pending-infra-teardown-and-drain-can-mean-keep-open.md`.

**The revisit-trigger analysis put to the operator (2026-07-24).** UC-3 states its own trigger:
*"If the teardown slips materially, revisit Path 2."* Measured this session:

- The teardown is blocked on **#6808** (OPEN — `WORKSPACES_LUKS_HEARTBEAT_URL` unwired).
- The soak probe `workspaces-luks-soak-6604.sh` requires the luks-monitor heartbeat to be
  **present** and its rows to **span ≥7 days**. With the URL unwired, the probe runs, succeeds,
  and pushes nothing — **the soak clock has not started.**
- Earliest cure is therefore **"#6808 fix + 7 days"**, with **no committed date** for either leg.
- Secondary point put alongside it: this PR is already rewriting those exact sentences, so the
  marginal cost of the wording is one clause rather than a fresh legal-doc edit.

**The operator's decision: KEEP THE HOLD.** Presented with the above, the operator reaffirmed the
UC-3 hold and directed that the blocker be escalated instead. Consequences, recorded plainly:

- **A live published over-claim is knowingly retained.** The re-scoped clause (d) will read, to
  any ordinary user, as a statement about *their* data rather than about *one volume*, while a
  full un-wiped copy sits on a seizable disk. That gap is now an **accepted, undisclosed
  residual** (§Risks R4), not an unnoticed one.
- **This makes the audit trail more important, not less.** A reversal would have needed a record
  so the change could be traced. A *retention* needs a record so the accepted exposure can be
  traced — to a decision, a date, and a tracking issue. Phase 1.5 writes it before anything else.
- **The escalation is the substitute remedy.** The operator did not decline the finding; they
  chose Path 1 (cure the reality) over Path 2 (qualify the words). Path 1 is only credible if its
  blocker is actually prioritised — hence §3c.

### 3b. Preserve the Path-2 wording verbatim (do not lose it)

The wording remains preserved for whoever writes it after #6808 clears. It is **not** used in this
PR. Recorded here so a second hold does not have to re-derive it:

> *"stored **live** workspace git data sits on a LUKS-encrypted volume (encryption at rest) (a
> superseded pre-cutover plaintext volume is retained only as a rollback backstop pending secure
> teardown)"*
> — `specs/feat-one-shot-6897-superseded-volumes-zot-legal/decision-challenges.md` UC-3, Path 2

Two constraints that survive with it, for that future edit:

1. **No published wipe date while #6808 is open** (CLO B4). A missed public deadline is a new
   over-claim of the same family. Use a condition, never a date. The ledger's
   `expires_on: 2026-10-22` is an **internal** commitment, not an achieved schedule.
2. **One backstop or two — establish it before writing.** The auditor named two attached plaintext
   volumes: `hcloud_volume.workspaces` (`server.tf:1569`) and `hcloud_volume.git_data`
   (`git-data.tf:196`). The second is ledgered as the backstop for a git-data LUKS cutover that
   **never happened** (the host was never born, #6570 OPEN), so it may hold nothing. Naming one of
   two would be a partial correction; asserting it holds data without evidence would be an
   over-claim in the other direction.

### 3c. The escalation — #6808 (this is a deliverable, not a note)

**What changed about #6808.** It was filed and triaged as a *monitoring gap* — a dead probe that
cannot page (`priority/p2-medium`, `type/bug`). As of this decision it is also the **gate on a
live published over-claim** in `docs/legal/*`: it blocks the soak, the soak blocks the Phase-5
plaintext wipe, and the wipe is the operator-chosen cure (Path 1) for the residual this PR
knowingly leaves undisclosed. That is a different severity class from "the probe is dark", and
#6808's labels must say so.

**Before mutating: re-verify state** (`hr-before-asserting-github-issue-status`) — do not assume
the labels below are still current:

```bash
gh issue view 6808 --json number,state,labels,title
```

**Step 1 — post the escalation comment.** It must name #6588, this PR, and the reaffirmed hold, so
that AC15 is checkable by anyone reading the issue:

```bash
gh issue comment 6808 --body "$(cat <<'EOF'
## Escalation — this now gates a live published over-claim (not only a monitoring gap)

Raised from #6588 (legal half) — PR <PR_URL>.

**What changed.** On 2026-07-24 the retained-plaintext disclosure question (UC-3, PR #6918) was
re-raised with the revisit-trigger analysis below. **The operator reaffirmed the HOLD**: no
affirmative disclosure sentence about the retained pre-cutover plaintext volume ships in
#6588's legal-half PR. The cure is Path 1 — tear down and wipe the plaintext volume — not
Path 2 (qualify the published wording).

**Why that lands on this issue.** Path 1 runs through this issue:

- `WORKSPACES_LUKS_HEARTBEAT_URL` is unwired, so `luks-monitor.sh` succeeds and pushes nothing.
- `workspaces-luks-soak-6604.sh` gates on the heartbeat being **present** with rows spanning
  **>= 7 days** — so the ADR-119 soak clock **has not started**.
- No soak means no Phase-5 plaintext wipe, which means the residual stays live.
- Earliest possible cure is therefore **"#6808 fix + 7 days"**, with no committed date for
  either leg.

**Consequence.** Until this is wired, `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
publish a LUKS-at-rest claim whose plain reading is broader than the infrastructure earns, with a
full un-wiped plaintext copy of every workspace on an attached Hetzner volume
(`hcloud_volume.workspaces`, ledgered `plaintext-exception`, `tracking_issue: #6897`). That
residual is **accepted and tracked here** — it is not unknown, and it is not disclosed.

**Open precondition carried over** (needed by whoever eventually writes the Path-2 wording, if the
teardown slips again): establish whether `hcloud_volume.git_data` holds any user data. It is
ledgered as the backstop for a git-data cutover that never happened (#6570 OPEN, host never born),
so it may hold nothing — but that must be measured, not assumed.

Refs: #6588, #6897, #6604, #6570. Prior decision: #6918 (UC-3).
EOF
)"
```

**Step 2 — re-prioritize.** Label taxonomy checked with `gh label list` this session; the
priority scale is `priority/p0-critical` | `p1-high` | `p2-medium` | `p3-low`, and `type/security`
exists (*"Security vulnerability, hardening, or audit finding"*).

```bash
gh issue edit 6808 \
  --add-label "priority/p1-high" \
  --add-label "type/security" \
  --remove-label "priority/p2-medium"
```

**Why `p1-high` and not `p0-critical`.** #6588 itself carries `priority/p0-critical`, and the
temptation is to mirror it. Rejected, deliberately: `p0-critical` reads *"drop everything"*, which
is the opposite of what the operator just decided — they chose to hold and proceed. It is also not
earned on the facts: there are **zero arms-length data subjects** today (#3723 OPEN; the volume
holds the operator's own dogfooding workspaces), so no data subject is presently misled.
`p1-high` — *"degraded functionality, no workaround"* — is exact: there is no workaround for a
soak clock that cannot start. **If #3723 onboards a first arms-length user while #6808 is still
open, this becomes p0** — record that trigger in the comment thread at that time.

### 3d. Recording the challenge

/work MUST create
`knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md`
in **Phase 1.5** (before any edit), recording: the UC-3 hold, the revisit-trigger analysis as put
to the operator, the operator's **reaffirmation**, the CLO's contrary recommendation and its
override, and the accepted residual with **#6808** as its tracking issue.

This is a challenge **raised and resolved in favour of the operator's original position** — not a
reversal. `ship` renders it into the PR body. **Do not silently apply and do not silently skip:**
the failure mode this guards is not an unrecorded change, it is an unrecorded *acceptance*.

---

## Deliverable 4 — Mechanics

### 4a. SHA re-pin (`apps/web-platform/lib/legal/legal-doc-shas.ts`)

Verified mechanics:

- `check-tc-document-sha.sh` enumerates all 9 `docs/legal/*.md` (sentinel `EXPECTED_COUNT=9`)
  and compares `sha256sum` of **raw bytes** (frontmatter, whitespace, trailing newline — no
  normalization) against the `LEGAL_DOC_SHAS` literal.
- **No bypass exists** for non-T&C docs. The `TC_VERSION`-bump bypass is `terms-and-conditions`-only.
- CI job **`tc-document-sha-guard`** is a **required check**, name-pinned by
  `infra/github/ruleset-ci-required.tf` per ADR-032.
- Body-equivalence canonical↔mirror is `BODY_EQUIVALENCE_DOCS=("terms-and-conditions")` only —
  it does **not** run for our three docs.

Baseline confirmed in sync (so all three go stale on edit): `privacy-policy` `0ac16eff…`,
`data-protection-disclosure` `eb346542…`, `gdpr-policy` `abcd6c4f…`.

```bash
sha256sum docs/legal/privacy-policy.md \
          docs/legal/data-protection-disclosure.md \
          docs/legal/gdpr-policy.md
```

Paste each **full 64-char** value (per `2026-05-16-sha-pin-prefix-match-false-positive-in-plan-verification.md`
— never truncate, verify with full-string `git grep -F`).

**No `TC_VERSION` bump.** `tc-version.ts` governs `terms-and-conditions.md` exclusively; these
three are notice/disclosure documents with no version constant and no re-acceptance gate. Per
`tc-version-bump-policy.md` the edit must still be **classified Tier 1/2/3 in the PR body**
(process requirement, not machine-enforced). **Classification: Tier 1 (material)** — retraction
of published Art. 32 TOM claims and re-scoping of a surviving one. (The tier does **not** rest on
a new affirmative disclosure; none ships — see §Deliverable 3.) Tier 1 also triggers the register
update, which this PR carries.

### 4b. DC-1 closure

`knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/decision-challenges.md`, DC-1,
`Status: OPEN — remediation tracked, exposure accepted` → **RESOLVED**, recording:
encryption certified 2026-07-23 (run 30040444418); the over-claim retracted by this PR; and
that the *reopen trigger* (2026-07-23, 7 days) had in fact **lapsed by one day** before this
correction landed — record that honestly rather than eliding it.

### 4c. Banner handling

Structure: one single line (`privacy-policy.md:11`, DPD `:12`, gdpr `:13`) of the form
`**Last Updated:** <date> (<summary>). Previous: <date> (<summary>). Previous: …` — prepend-style,
history preserved.

**Where the false claims actually sit — corrected at plan-review.** The (a)/(b)/(c)/LUKS family
sits under the historical **`Previous: July 2, 2026`** entry. But offset-mapping shows matches in
**three** segments, not one, and an earlier draft asserted only the first:

| Segment | Carries | Disposition |
|---|---|---|
| `**Last Updated:** July 16, 2026` (**head**) | `web-2 … **has been** in Falkenstein … and its retirement **is decided**` — both now stale (retired 2026-07-17) | **Demoted to `Previous:` and superseded by the new head**, which states the retirement completed. No in-place rewrite. |
| `Previous: July 2, 2026` | (a) + (b) + (c) + LUKS + web-2 | **Annotate** (below). Text preserved byte-identical. |
| `Previous: June 30, 2026` | a `git-data` mention | Covered by the same annotation approach; verify at /work. |

**Exact banner transformation (three operations, in this order, on all 6 files):**

1. **Annotate** — append the retraction marker at the **END** of the July-2 segment, immediately
   before `Previous: June 30, 2026`. **Not mid-segment.** This is forced by AC7: an end-append
   preserves the segment as a contiguous substring (verified PASS); a mid-segment insertion breaks
   contiguity (verified FAIL) and is exactly the destructive edit CLO B3 blocks.
2. **Demote** — rewrite the literal `**Last Updated:** July 16, 2026 (` → `Previous: July 16, 2026 (`.
   *(This step was implied only by AC7's "+1" and was stated in no phase — added here.)*
3. **Prepend** — insert `**Last Updated:** July 24, 2026 (<summary>). ` at position 0.

Operations 2 and 3 are what make the `Previous:` occurrence count go +1 (AC7).

**Precedent-diff (deepen Phase 4.4) — measured, not assumed.** Every commit in the last 12 that
touched `docs/legal/privacy-policy.md`'s banner was replayed and classified by comparing the
pre-commit banner (with its head relabelled to `Previous:`) against the post-commit banner:

| Commit | Verdict |
|---|---|
| `cb93c2948` (locative fix, #6568) | PREPEND-ONLY — history verbatim |
| `d4c18790f` (severity-ranked inbox) | PREPEND-ONLY — history verbatim |
| `2d0cc9c26` (multi-host 3.D — the commit that *introduced* these claims) | PREPEND-ONLY — history verbatim |
| `0e3a46d4f` (worktree-lease) | PREPEND-ONLY — history verbatim |
| `c0276e8e4` (routines UI) | PREPEND-ONLY — history verbatim |
| `a04d95c17`, `31cb69935`, `ee58951b9` | banner untouched (N/A) |

**Findings:**

- **Operations 2 + 3 (demote + prepend) have unanimous precedent — 5 of 5.** The exact
  transformation is `**Last Updated:** ` → `Previous: ` on the old head, with every prior byte
  preserved. Follow it literally.
- **Operation 1 (annotating a historical segment) has NO PRECEDENT — the pattern is NOVEL.**
  In the entire history of this banner, no commit has ever modified text inside an existing
  `Previous:` entry. Recorded here per the precedent-diff gate so reviewers scrutinise it rather
  than pattern-matching it to the routine prepend.

  This is *why* AC7 exists in its substring-preservation form: with no precedent to imitate, the
  guard has to be mechanical. It is also why CLO's B3 (annotate, never amend) is the binding
  constraint — the novelty is confined to **adding** bytes at a segment boundary, which keeps the
  append-only property the 5 precedent commits establish. An implementer who "improves" on this by
  editing the historical wording would be both breaking B3 and departing from 5-of-5 precedent.

> **Terminology fix.** An earlier draft said "insert a marker **inside** the July 2 entry" (§4c)
> while AC7 said "**appended**". Those imply different insertion offsets and therefore different
> AC7 outcomes. **"Appended at the end of the segment" is correct**; "inside" is retired.

**Disposition (CLO Q2): ANNOTATE — option (C).**

- **(B) amend in place is BLOCKED** (CLO B3). Rewriting a dated record of what was published
  destroys the Art. 5(2) audit trail that the append-with-history banner exists to provide.
- **(A) leave untouched is insufficient.** The banner is one unbroken line of prose; a
  present-tense sentence (*"now sits on a LUKS-encrypted volume"*) reads as a live claim to a
  user whose eye lands on it, regardless of its position in a changelog.
- **(C) annotate** preserves the record verbatim *and* kills the live-claim reading. Append a
  bracketed retraction marker **at the END of** the July 2 entry (immediately before
  `Previous: June 30, 2026`) without altering one word of its original text, plus a new head
  entry. Annotation is additive, so append-only holds. *(Wording aligned with the Terminology fix
  above — "inside" is retired; only the end-append satisfies AC7.)*

> **SHARP EDGE — the mirror banners are NOT byte-identical to the canonicals. Do not "sync" them.**
> Measured 2026-07-24:
>
> | Doc | Canonical banner | Mirror banner | Mirror is missing |
> |---|---|---|---|
> | `privacy-policy` | 27,358 chars (27,492 B) / **12** entries | 18,409 chars / **9** entries | `May 25`, `May 22`, one `June 15` |
> | `data-protection-disclosure` | 28,271 chars / **12** entries | 21,693 chars / **9** entries | same three |
> | `gdpr-policy` | 23,883 chars / **11** entries | 16,523 chars / **8** entries | same three |
>
> The mirrors carry a **truncated changelog history**. This is **pre-existing drift on `main`**,
> not something this PR creates, and it passes CI because `legal-doc-consistency.test.ts` asserts
> only the `**Last Updated:**` **date**, never the full banner body.
>
> An implementer who "helpfully" makes the mirror match the canonical would append three
> historical entries to **published legal text** — a large, unintended, unreviewed change to what
> users read at soleur.ai, and a diff that swamps the actual retraction. **Edit each banner in
> place; never copy one over the other.**
>
> The annotation itself is safe to apply identically to both: the `Previous: July 2, 2026`
> segment **is** byte-identical across each canonical/mirror pair (818 / 823 / 827 chars
> respectively), which is why AC7's substring check works uniformly on all six.
>
> **Pre-existing-finding disposition** (`wg-when-an-audit-identifies-pre-existing`):
> **acknowledged, not folded in, no issue filed.** It asserts nothing false — it is an omission of
> old changelog entries, not a claim — so it is not in this PR's defect class, and folding it in
> would mix an unrelated multi-KB text change into a legal-accuracy correction. Recorded here so
> the next editor does not "fix" it by accident. If the operator wants it tracked, it is a
> one-line issue; net-flow discipline argues against filing it unprompted.

**Style decision — RESOLVED by history, not left open.** Use **`Ref #6588`**.

The question was whether `2026-05-12-public-legal-doc-annotations-no-pr-numbers.md` (which
prescribes section refs `§N.M`, not issue numbers) still governs. History settles it:

| Date | Convention in banner summaries |
|---|---|
| pre-2026-06-10 | `PR #5124 (#4046)`, `PR #5014 (#5005)` — the form the learning objected to |
| **2026-06-10 onward** | **`Ref #NNNN (<branch-slug>)`** — e.g. `Ref #6538 (chore-retire-web-2-fsn1-orphan)`, `Ref #6007 (feat-severity-ranked-inbox)`, `Ref #5325 (feat-agent-native-outbound-email)` |

The `Ref #NNNN` convention was **adopted on 2026-06-10 — a month AFTER the 2026-05-12 learning**,
and has held unbroken since. It is not drift *from* the learning; it post-dates and supersedes it.
The learning's concern (a bare `PR #N` means nothing to an external reader) is answered by the
`(<branch-slug>)` suffix the current form carries. Match the adjacent entry.

**Apply uniformly** to the new banner head and to any body-prose `Ref` this PR adds. Record in the
PR body that the May-12 learning is superseded-in-practice from 2026-06-10, so the next editor does
not re-open this.

### 4d. Internal registers — SAME PR (CLO B2)

**Not sequenceable.** Art. 30(1)(g) makes "a general description of the technical and
organisational security measures" **mandatory register content** — the four false items are not
commentary, they are wrong register content. Art. 5(2) makes the register the primary artifact
handed to a supervisory authority.

Sequencing produces a state **strictly worse than today**: a timestamped public retraction
alongside an internal register still asserting the retracted TOMs — a documented
self-contradiction in which the *internal* record over-claims relative to the *public* one, with
a merge date proving it was known. Cost of inclusion: a handful of table-cell edits, no code, no
tests, no deploy risk.

- `knowledge-base/legal/article-30-register.md` — **exactly two `(g) TOMs (Art. 32)` cells**,
  verified by grep this session (`grep -nE "LUKS|One-way TLS host|re-verify on proxied"` returns
  lines 50 and 68 only):

  | Line | Processing Activity | False items |
  |---|---|---|
  | 50 | **PA 1 — Account & Authentication** | (13) LUKS-at-rest on the git-data volume · (14) One-way TLS host↔host proxy · (15) Per-workspace membership-gated git-data fetch authorization · (16) Membership re-verify on proxied sessions |
  | 68 | **PA 2 — Conversation Data (Messages, Turns, Usage Telemetry)** | (17)–(20), the same four restated |

  The `## Cross-Cutting Technical & Organisational Measures (Art. 32)` section (line 440) was
  checked and is **clean** — no third TOM site.

  > **CORRECTION (plan-review, code-simplicity-reviewer — verified).** Scoping the register edit
  > to the two TOM cells **reproduces this plan's own P7 failure mode inside the fold-in whose
  > entire justification is the "removed whole or not at all" principle.** The retracted claim
  > family also lives in **four non-TOM cells**, confirmed by
  > `grep -nE "web-2|CAX11|soleur-git-data|git-data" knowledge-base/legal/article-30-register.md`:
  >
  > | Line | Cell | Stale content |
  > |---|---|---|
  > | 47 | PA 1 **(d) Recipients** | Hetzner *"incl. web-2 CX33 in `fsn1`"* — retired 2026-07-17 |
  > | 48 | PA 1 **(e) Transfers** | names the `fsn1` host / `soleur-git-data` plane |
  > | 163 | PA 8 **(e) Transfers** | *"web-2 `fsn1` Germany since PR #6393"*, **present tense** |
  > | 426 | Vendor/Sub-Processor Mapping, Hetzner row | *"web-2 `fsn1` since PR #6393"* |
  >
  > Without this, the PR would ship a public retraction while the register still asserts in four
  > places that a destroyed host is live in Falkenstein — and `(d) Recipients` / `(e) Transfers`
  > are **Art. 30(1)(d)/(f)** limbs, a stronger obligation than the volunteered TOM prose.
  >
  > **Apply the Phase-1 union-anchor discipline to `article-30-register.md` too, not only to the
  > six published files.** AC9 asserts residual-zero on the register.

  Re-verify PA identity and item numbering by grep at /work before editing, per
  `2026-06-04-art-30-pa-citation-must-be-grep-validated-against-register.md`; do **not** inherit
  the item numbers from this plan (they shift if a sibling PR edits the cell first).

  **Note the substitution, not just the deletion.** Items (13)–(16) / (17)–(20) are the *only*
  volume-layer at-rest measures these two PAs claim. Deleting them outright would leave both PAs
  with **no** workspace-storage TOM at all — an under-claim that misdescribes the register. Replace
  them with the measure that *is* now true (LUKS on the live workspaces volume, cutover certified
  2026-07-23) plus the retained-backstop residual. This is the claim-family litmus (AC2) applied
  to the register.
- `knowledge-base/legal/compliance-posture.md:80` — drop the `git-data host CAX11` clause from
  the Hetzner DPA scope, and apply the same union-anchor sweep for `web-2`/`fsn1` present-tense
  claims. The AVV covers the *account*; naming an unordered host is a demonstrability defect,
  not a coverage gap.

  > **CUT from this PR (plan-review):** an earlier draft also *added* an Art. 17 gating condition
  > on **#3723** here. That is the only proposed edit in the whole PR that **adds a new
  > forward-looking commitment** rather than correcting a false statement, and this plan's own R1
  > concedes it does not block this PR. Nothing here makes its absence more false than yesterday.
  > **Post it as a comment on #3723 instead** — that issue is its correct home. R1 keeps the
  > finding; the diff does not.

### 4e. NFR register

- `nfr-register.md:522` — *"Hetzner web/workspaces server volumes not encrypted at disk level"*
  is now **false**. Correct it. (An under-claim — the *unexposed* direction — so it is not this
  PR's defect class, but it directly contradicts the PR's central fact and sits two rows from the
  one that is correct. Cheap to fix while open; **not** gated by an AC.)

  > **CUT (plan-review):** an earlier draft listed `nfr-register.md:521` as *"confirm still
  > accurate and leave if so"* — a Files-to-Edit row whose instruction is to produce no diff.
  > Removed.

### 4f. Ledger coupling — two dead anchors to fix, one row that stays put

`scripts/encryption-posture-ledger.json`. **Two `disclosed_as` edits, not three** (the third,
`hcloud_volume.workspaces`, was only in scope because of the retracted Deliverable 3 — see item 2).
Baseline **PASSES**
(`14 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS`).

1. **`workspaces_luks` row → `disclosed_as: "docs/legal/privacy-policy.md:519"`.** This cites
   the exact clause being rewritten, by **line number** — violating
   `cq-cite-content-anchor-not-line-number`. Convert to a **content anchor**.
   *Mechanism note (corrected at plan-review — the accurate version is the stronger argument):*
   `resolve_disclosed_as()` splits on the first `:` and does `text.find(anchor)` — a **substring
   search**, not a line lookup. `docs/legal/privacy-policy.md` contains **zero** occurrences of the
   literal string `519` (`grep -c "519"` → **0**), so the call returns `(None, None)`: the citation
   is **dead**, not merely decorative. It is harmless *today* only because `check_at_rest()` returns
   early on `mechanism == "luks"` and never reaches the resolver. But the unresolvable branch is
   explicitly marked `# Fail CLOSED` — so **the instant that row's mechanism ever changes, the dead
   anchor becomes a hard CI failure.** Fixing it now is cheap insurance, not just rule compliance.

2. **`hcloud_volume.workspaces` row → `disclosed_as: "not-publicly-claimed"` — NO CHANGE.**
   Post-amendment this is **trivially correct and stays exactly as committed**: with the hold
   reaffirmed, no published document makes any claim about this store, so the field is accurate on
   its face. `exception.justification`, `tracking_issue: "#6897"`, `reevaluate_when` and
   `expires_on` are likewise untouched.

   Earlier drafts of this plan carried an R5 sharp-edge analysis here — that flipping this field to
   a real anchor would turn CI red, because `mechanism: plaintext-exception` makes
   `check_disclosed_as_not_encrypted()` run and it FAILs when the resolved ±300-char window matches
   `/LUKS|encrypt/i`. **That analysis is retired: the flip is not happening, so the CI failure it
   warned about cannot occur in this PR.** Do not reinstate it, and do not "pre-empt" it by editing
   the row.

   > **One genuinely independent observation survives, and it is now MORE relevant, not less.**
   > `check_disclosed_as_not_encrypted()` cannot distinguish an honest **under**-claim from an
   > **over**-claim: it is built to catch a plaintext store being described in encryption language,
   > and it fires identically when a plaintext store is *honestly disclosed as a residual* inside a
   > security section. This does not depend on anything in this PR — it is a standing property of
   > the linter, and it is a **latent blocker on the deferred Path-2 wording**: the moment #6808
   > clears and someone writes that sentence, this check is in their way. **File it as a one-line
   > issue against #6893** (which already tracks a sibling class gap: Layer A validates
   > `tracking_issue` *shape* but never open/closed *state*). **Do not edit
   > `scripts/lint-encryption-posture.py` in this PR** — it declares `runtime_deploy_risk: none`
   > and its only non-prose file is `legal-doc-shas.ts`; touching a Python linter plus its tests
   > would silently change the PR's change-class.

3. **`connections[0]` (`web-platform server -> Supabase Postgres/PostgREST`) →
   `disclosed_as: "docs/legal/data-protection-disclosure.md:316"`.** The same
   `cq-cite-content-anchor-not-line-number` defect, in a file this PR edits. Convert to a content
   anchor. It is not evaluated today (`cert_verification: "on"` short-circuits the whole
   `disclosed_as` block in `check_connection`) and it *does* currently resolve
   (`grep -c "316"` → 4) — but leaving one line-number citation while fixing the others is the
   weaker option. Independent of Deliverable 3; unaffected by the amendment. Gated by AC8.

   Re-run `python3 scripts/lint-encryption-posture.py --repo-sweep` after items 1 and 3; expect
   PASS unchanged.

---

## Files to Edit

| File | Change |
|---|---|
| `docs/legal/privacy-policy.md` | Body `:298`, `:489`, `:519`; banner `:11` (annotate + demote + prepend) |
| `docs/legal/data-protection-disclosure.md` | Body `:189` (processor table), `:276`, **`:318`**; banner `:12` |
| `docs/legal/gdpr-policy.md` | Body `:44`, `:318`; banner `:13` |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | Body `:297`, `:475`, `:500`; banner `:20`; hero date `:11` |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Body `:186`, `:261`, **`:301`**; banner `:21`; hero date `:11` |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | Body `:53`, `:306`; banner `:22`; hero date `:11` |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | Re-pin 3 SHAs (full 64-char) |
| `knowledge-base/legal/article-30-register.md` | **6 cells** (§4d): `(g)` TOMs `:50` + `:68`, `(d)` Recipients `:47`, `(e)` Transfers `:48` + `:163`, Vendor mapping `:426` |
| `knowledge-base/legal/compliance-posture.md` | `:80` DPA scope (drop `git-data host CAX11`) + `web-2`/`fsn1` present-tense sweep. **No #3723 Art. 17 gate** — cut at plan-review; posted as a comment on #3723 instead (Phase 5.6) |
| `knowledge-base/engineering/architecture/nfr-register.md` | `:522` only (the `:521` "confirm and leave" row was cut at plan-review — it produced no diff) |
| `scripts/encryption-posture-ledger.json` | `disclosed_as` **×2** — `stores[0]` and `connections[0]` (see §4f). **`stores[2]` (`hcloud_volume.workspaces`) is NOT edited** — it was only in scope for the retracted Deliverable 3 |
| `knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` | DC-1 → RESOLVED |
| `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` | **Create** — the UC record for Deliverable 3 (hold **reaffirmed**, residual accepted, tracked #6808) |
| `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` | **Create** — CLO Phase 5.5 attestation |

**The five LUKS sites are still edited** — by Deliverables 1 and 2 (retract (a)(b)(c) + web-2;
drop the multi-host conditional). What they do **not** receive is any plaintext-disclosure
sentence or scope-to-live qualifier. There is no file in this table that exists solely to host the
retracted Deliverable 3.

**Line numbers above are navigational only.** All edits and all ACs bind to **content
anchors** (`cq-cite-content-anchor-not-line-number`); mirror offsets differ per file and drift
as soon as the first edit lands.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md`
  — the Deliverable-3 User-Challenge record: challenge raised, operator **reaffirmed the hold**,
  residual accepted and tracked via #6808. **Written in Phase 1.5, first**, because Phase 5's
  escalation comment and the CLO attestation both cite it, and because an abort mid-run must not
  leave a knowingly-retained live over-claim with no record of who accepted it or why.
- `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/site-dispositions.md`
  — the 16-row per-site disposition table AC2 gates on.
- `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` — CLO attestation. Follows the
  established convention in `knowledge-base/legal/audits/` (5+ prior `*-counsel-review-*.md`).

---

## Implementation Phases

### Phase 0 — Live re-verification (blocking, before any edit)

Every surviving claim must be verifiable against live infrastructure **as it exists today**, not
against a day-old certification.

1. Dispatch the verify workflow (it is `workflow_dispatch`-only, non-destructive, and is the
   designated no-SSH discoverability test per `hr-no-ssh-fallback-in-runbooks`):
   ```bash
   gh workflow run workspaces-luks-verify.yml
   ```
   Confirm `device_type=crypto_LUKS`, `mount_source=/dev/mapper/workspaces`, `escrow=ok`,
   `header=readable`, `workspace_count=8 expected=8`. **Do not seed the baseline** (leave
   `seed_workspace_count` unset — the only write path in that workflow).
   Capture the run id (`gh run list --workflow=workspaces-luks-verify.yml --limit 1 --json
   databaseId,conclusion`) — AC14 requires pasting it, so wait for completion rather than
   fire-and-forget.

   > **If it goes RED — the DEGRADED-SCOPE branch (pick this, do not improvise).** An earlier draft
   > said only "stop", then contradicted itself by saying "retraction becomes correct" — a dead end
   > that left every downstream AC assuming a true LUKS claim. The defined branch is:
   >
   > 1. **Do not abort the PR.** Deliverables 1 and 4 remain valid and urgent — the three
   >    unachievable clauses are false regardless of the LUKS state.
   > 2. **Retract clause (d) instead of re-scoping it.** Drop the LUKS claim from all 5 sites
   >    rather than asserting it.
   > 3. **AC3 is struck**; AC1 widens to include `LUKS` in the retraction anchor. **AC4 and AC15
   >    stand** — Deliverable 3 is unaffected in kind: no plaintext-disclosure sentence ships
   >    (there would be no LUKS claim left to qualify), and the #6808 escalation becomes *more*
   >    urgent, not less, because the certified cure has itself regressed. Say so in the escalation
   >    comment.
   > 4. **DC-1 stays OPEN** (§4b is predicated on certification holding) and the PR body uses
   >    `Ref #6588`, **not** `Closes` — the encryption half would no longer be done.
   > 5. **File a P0 incident** against #6588 / #6812 and flip the ledger's `workspaces_luks` row,
   >    whose `mechanism: luks` would then be a live misstatement the linter cannot catch (early
   >    return).
   >
   > This is not hypothetical: run 29782780158 landed crypto_LUKS for ~27 minutes before its own
   > dead-man timer silently reverted it (#6812). A stale green is the documented failure mode on
   > this exact surface, which is why Phase 0 re-measures rather than citing 2026-07-23.
2. Re-assert #6570 / #6808 / #6897 / #3723 are still OPEN (`gh issue view`).
3. Record `python3 scripts/lint-encryption-posture.py --repo-sweep` baseline (expect PASS).

### Phase 1 — Union-anchor site inventory (RED-equivalent gate)

Derive the site list mechanically; **never** `grep LUKS`.

```bash
grep -nE "LUKS|encrypted in transit with TLS|TLS-encrypted \(in transit\)|across hosts|proxied session|across more than one host|spans more than one|git-data host|dedicated host for per-workspace|web-2" \
  docs/legal/{privacy-policy,data-protection-disclosure,gdpr-policy}.md \
  plugins/soleur/docs/pages/legal/{privacy-policy,data-protection-disclosure,gdpr-policy}.md
```

Assert the inventory matches the **§Site Matrix** (8 canonical body sites + 3 banner headers, ×2 = **22**). A different
count means the union anchor is wrong or `main` moved — reconcile before editing.

Then apply the **claim-family litmus** per site: after removing X from *"…A, B, and X. X does P,
Q, R."*, ask *what does "does P" now attach to?* If the answer changed, a claim was rewritten
unintentionally.

### Phase 1.5 — Write the audit trail first

Create `specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` with the
Deliverable-3 User-Challenge record **now**, not in Phase 5. Content per §3d: the UC-3 hold, the
revisit-trigger analysis as put to the operator, the operator's **reaffirmation**, the CLO's
contrary recommendation and its override, and the accepted residual tracked by **#6808**.

> **Ordering rationale (simplified post-amendment).** There is no reversal here to guard against —
> the challenge resolved in favour of the operator's existing position, and nothing in the
> published documents changes as a result of it. It is written first for two plainer reasons:
> Phase 5's escalation comment quotes it, and the CLO attestation (ship Phase 5.5) cites it. An abort
> mid-run should not leave a knowingly-accepted live over-claim with no record of who accepted it.

Also create `site-dispositions.md` (16 rows, from the Site Matrix) — it is Phase 2's worklist and
AC2's artifact.

### Phase 2 — Canonical body edits

Deliverables **1 + 2** across the three canonicals, one claim family at a time (not one file at
a time) so no site is half-edited. Highest-grade item first: the **DPD processor table**
(`:189`) — Art. 13(1)(e) / Art. 30(1)(d) recipients territory, a stronger obligation than the
volunteered TOM paragraph (CLO Risk 1).

> **Deliverable 3 contributes NOTHING to this phase.** No site receives a plaintext-disclosure
> sentence, and no site receives a scope-to-live (*"stored **live** workspace git data …"*)
> qualifier. If a stale draft or a reviewer suggests adding one, that is the retracted D3 — AC4
> asserts its absence.

### Phase 3 — Mirrors + banner + dates

1. Mirror each canonical edit (hand-maintained; **no generator exists**).
2. Annotate the `Previous: July 2, 2026` entry; prepend the new head entry (all 6 files).
3. Set the new date in **9 places**: 3 canonical body lines, 3 mirror body lines, 3 mirror hero
   `<p>` lines — byte-identical
   (`2026-03-20-eleventy-mirror-dual-date-locations.md`).
4. **Heading-sequence parity:** if any `##`/`###` heading changes in a canonical, mirror it
   exactly. (This PR should not need heading changes — verify it did not introduce any.)

### Phase 4 — Mechanical pins

Ledger `disclosed_as` ×2 (§4f — `stores[0]`, `connections[0]`; **`stores[2]` untouched**) →
re-run the posture linter → **THEN** SHA re-pin ×3 → re-run `check-tc-document-sha.sh`.

> **Invariant: the SHA pin must be the LAST mutation touching `docs/legal/**`.** The pin is a
> raw-byte `sha256sum`, so *any* later byte change in those three files silently stales all three
> values, and `tc-document-sha-guard` is a required check with no bypass for non-T&C docs.
> Late-arriving wording tweaks (a reviewer's phrasing note on a retracted clause, a banner summary
> reword) are the realistic trigger. Ordering the ledger work first removes one hazard; if any
> `docs/legal/**` byte changes after the pin **for any reason**, re-run the pin and re-verify.

### Phase 5 — Registers, DC-1, escalation, attestation

Art. 30 register (6 cells, §4d) → compliance-posture `:80` → nfr-register `:522` → DC-1 RESOLVED →
**#6808 escalation (§3c: `gh issue comment` + `gh issue edit` re-prioritize)** → Art. 17 note
posted as a comment on #3723 → CLO writes the audit to `knowledge-base/legal/audits/`.

> The `decision-challenges.md` UC entry is **not** written here — it was written in Phase 1.5. The
> escalation comment quotes it, which is why the ordering matters.

### Phase 6 — Verification

Full suite; grep the log for `FAIL`/`× ` rather than trusting exit codes
(`2026-06-15-two-legal-mirror-gates-and-always-build-mcp-registered-list-desync.md`).

```bash
bash apps/web-platform/scripts/check-tc-document-sha.sh
cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts \
                                                     test/legal-doc-shas-guard.test.ts
python3 scripts/lint-encryption-posture.py --repo-sweep
bun test plugins/soleur/test/marketing-content-drift.test.ts   # fires on plugins/soleur/**/*.md
./node_modules/.bin/eleventy --dry-run      # repo-root pinned binary, NOT npx
```

**`marketing-content-drift.test.ts` Test 1** walks `plugins/soleur/docs/pages/legal/**/*.md`
(mirrors only) for stale exact counts matching `/\b(59|61|62|63|65|66|67) (agents?|skills?)\b/`.
It also fires via the **lefthook pre-commit hook** on any staged `plugins/soleur/**/*.md`, so it
will run whether or not it is invoked explicitly. This PR introduces no such counts — but do not
introduce one, and use the "60+" soft-floor phrasing if a count is ever needed.

Then run the **full** suite before ship (`bash scripts/test-all.sh`) — the two legal gates are
independent, and passing one does not imply the other.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — residual zero, BODY PROSE ONLY.** The retraction anchor below returns **0** matches
      across all **6** published files **with the banner line excluded**:

      ```bash
      for f in docs/legal/{privacy-policy,data-protection-disclosure,gdpr-policy}.md \
               plugins/soleur/docs/pages/legal/{privacy-policy,data-protection-disclosure,gdpr-policy}.md; do
        grep -vE '^\*\*Last Updated:\*\*' "$f" \
        | grep -nEi "encrypted in transit with TLS|TLS-encrypted \(in transit\)|host↔host|re-verified|proxied session|dedicated per-workspace git-data host|dedicated host for per-workspace|git-data host|web-2|spans more than one|across more than one host" \
        && echo "RESIDUAL IN $f"
      done
      ```

      > **The banner exclusion is load-bearing, not a loophole.** AC7 *requires* the
      > `Previous: July 2, 2026` segment to survive byte-identical, and that segment **contains**
      > `encrypted in transit with TLS`, `re-verified on proxied sessions`, and `git-data host` in
      > all 6 files. Without `grep -v` on the banner line, **AC1 and AC7 are mutually
      > unsatisfiable** — AC1 could never reach 0 while AC7 holds. Caught at plan-review.

      > **Anchor on the bare token `web-2`**, never on `web-2 … is in Falkenstein` — the claim is
      > phrased three ways (see Site Matrix) and the sentence-anchored form false-passes on
      > `pp:298`, the most-read instance. Exclude `eu-fsn-3` / Better Stack from any `Falkenstein`
      > sweep (Site Matrix carve-out).

      Scope excludes `**/archive/**` and this feature's own planning artifacts
      (`plans/2026-07-24-fix-6588-*`, `specs/feat-one-shot-6588-legal-clause-retraction/**`),
      which must retain the old text as migration records.
- [ ] **AC2 — no dangling claim.** Every site in the **Site Matrix** has an explicit per-claim
      disposition, recorded as a 16-row table (8 canonical + 8 mirror) in
      `specs/feat-one-shot-6588-legal-clause-retraction/site-dispositions.md`. Reviewers check the
      diff against that table.

      > An earlier draft asked for a "claim-family litmus applied and **recorded** per site" with
      > no named artifact — unverifiable at review. Naming the file makes it a post-condition.
- [ ] **AC3 — LUKS clause re-scoped: not widened, and not deleted.** Two mechanical limbs, each
      able to fail:

      **(a) No widening** (#6893 claim-unlock bound). Across the 6 published files:

      ```bash
      grep -nEi "all (user |customer |workspace )?data at rest|encrypted by default|all .{0,25}data is encrypted" <6 files>
      ```

      returns **0**. Baseline on `origin/main` is also 0 — measure it; a non-zero baseline means
      `main` moved and this AC must be re-derived before use.

      **(b) No deletion.** The LUKS claim still stands at all **5 canonical + 5 mirror** sites the
      Site Matrix names (`pp:298`, `pp:519`, `dpd:189`, `dpd:276`, `gdpr:44` + mirrors), verified
      **per site against `site-dispositions.md`** — not by a repo-wide count, which cannot tell
      which site lost it.

      > The multi-host-premise removal is **not** restated here — **AC1 measures it**, because its
      > anchor already carries `spans more than one` and `across more than one host` and both are
      > non-zero pre-change. Limb (b) is a deliberate preservation check: the failure it catches is
      > an implementer deleting an *earned, true* safeguard claim while retracting the false ones
      > around it — "removed whole or not at all" applied in the other direction.
- [ ] **AC4 — the HOLD held: NO plaintext disclosure was added (Deliverable 3).** The operator
      reaffirmed the UC-3 hold, so **no published legal text may gain a sentence, clause, or
      qualifier about the retained pre-cutover plaintext volume.** Three limbs:

      **(a) Absence, absolute.** Across the 6 published files:

      ```bash
      grep -nEi "rollback backstop|pre-cutover|plaintext volume|unencrypted volume|superseded .{0,30}volume|stored \*\*live\*\* workspace|older, unencrypted" <6 files>
      ```

      returns **0**. Measure the same anchor on `origin/main` first: it is **also 0** today. If it
      is not, `main` moved — stop and reconcile.

      **(b) Nothing added by this diff.** `git diff origin/main -- <6 files>` contains **no added
      line** matching the limb-(a) anchor. This is the limb that catches the specific regression
      risk: an implementer or reviewer working from a stale draft of Deliverable 3, or from PR
      #6918's preserved Path-2 wording, adding it back.

      > **The banner counts.** Per AC7's note, *any* banner edit renders as a full-line delete +
      > add, so the whole 27k-character banner is an "added line" for limb (b). The new head
      > summary and the July-2 retraction marker must therefore avoid these tokens too — describe
      > what was **retracted**, never the retained plaintext volume.

      **(c) CLO B4 — no published wipe date.** Trivially satisfied (there is no disclosure
      sentence to attach one to), guarded anyway: no added line in that diff matches
      `/(erased|wiped|destroyed|securely deleted).{0,40}\b(by|before|on)\b/i`.

      > **This is a preservation AC, like AC7 — deliberately, not by oversight.** Limb (a) reads
      > the same value before and after; that is the point, and it is stated with its measured
      > baseline so no future reader mistakes it for the inert-AC failure mode the deepen pass
      > removed. Limb (b) is direction-sensitive and is what actually detects a violation.
- [ ] **AC5 — date parity, by site extraction (NOT by count).** Extract the three date captures per
      document pair using the **exact regexes the gate itself uses**
      (`apps/web-platform/test/legal-doc-consistency.test.ts`) and assert all **9** captures equal
      the new date:
      `/\*\*Last Updated:\*\*\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/` on canonical body + mirror body,
      and `/Last Updated\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/` on the mirror hero `<p>`.
      `legal-doc-consistency.test.ts` passes.

      > **Do NOT use `grep -c` for this.** Measured: `grep -c 'July 16, 2026'` returns **2** in
      > `privacy-policy.md` and **2** in `gdpr-policy.md` — the banner *and* the in-prose
      > annotation *"corrected July 16, 2026"* at `pp:298` / `gdpr:44`. A count-based AC therefore
      > (a) has a false premise today, and (b) would spuriously fail the moment an implementer
      > follows the repo's own precedent of writing *"corrected July 24, 2026"* into a rewritten
      > sentence. The gate uses `.match()` — **first occurrence only** — so site extraction is
      > both the correct and the faithful check.
- [ ] **AC6 — SHA pins.** `check-tc-document-sha.sh` exits 0; each of the 3 new values is a full
      64-char string verified by `git grep -F '<full-sha>'`.
- [ ] **AC7 — banner integrity (preserved-substring form).** For each of the 6 files, the
      `Previous: July 2, 2026 … ` segment **as it exists on `origin/main`** must appear as a
      **contiguous substring** of the edited banner line, AND the `Previous:` **occurrence** count
      increases by exactly 1 — measured with `grep -o 'Previous:' "$f" | wc -l`, **never**
      `grep -c`.

      > **`grep -c 'Previous:'` returns `1` for every one of the 6 files** — it counts *lines*, and
      > the banner is a single line. "Count unchanged +1" would be 1→1 and detect nothing,
      > including R7's own cited failure (a sync script silently dropping a `Previous:` label).
      > Measured occurrence baselines, 2026-07-24 — assert **+1** on each:
      >
      > | File | `grep -c` (wrong) | `grep -o \| wc -l` (correct) | Assert after |
      > |---|---|---|---|
      > | `privacy-policy.md` | 1 | **18** | 19 |
      > | `data-protection-disclosure.md` | 1 | **17** | 18 |
      > | `gdpr-policy.md` | 1 | **17** | 18 |
      > | mirror `privacy-policy.md` | 1 | **12** | 13 |
      > | mirror `data-protection-disclosure.md` | 1 | **13** | 14 |
      > | mirror `gdpr-policy.md` | 1 | **11** | 12 |

      > **Do NOT express this as a `git diff` assertion.** The banner is a single
      > 27,358-character (27,492-byte) line, so *any* edit renders in `git diff` as a full-line delete + add
      > (empirically confirmed: 1 `<` + 1 `>`). "Insertion only, no deletion" is therefore
      > **unverifiable** by diff and would false-fail a correct edit. Use the substring form:
      >
      > ```bash
      > python3 - <<'PY'
      > import re, subprocess, sys
      > FILES = {  # file -> 0-based banner line index (all six verified 2026-07-24)
      >   "docs/legal/privacy-policy.md": 10,                                   # seg 818 chars
      >   "docs/legal/data-protection-disclosure.md": 11,                       # seg 823 chars
      >   "docs/legal/gdpr-policy.md": 12,                                      # seg 827 chars
      >   "plugins/soleur/docs/pages/legal/privacy-policy.md": 19,              # seg 818 chars
      >   "plugins/soleur/docs/pages/legal/data-protection-disclosure.md": 20,  # seg 823 chars
      >   "plugins/soleur/docs/pages/legal/gdpr-policy.md": 21,                 # seg 827 chars
      > }
      > for f, i in FILES.items():
      >     old = subprocess.run(["git","show",f"origin/main:{f}"],
      >                          capture_output=True, text=True).stdout.split("\n")[i]
      >     new = open(f).read().split("\n")[i]
      >     seg = re.search(r"Previous: July 2, 2026.*?(?=Previous: June 30, 2026)", old, re.S)
      >     assert seg, f"{f}: July-2 segment not found on origin/main"
      >     assert seg.group(0) in new, f"{f}: FAIL — July-2 segment was modified, not annotated"
      >     print(f"{f}: OK ({len(seg.group(0))} chars preserved verbatim)")
      > PY
      > ```
      >
      > **This pins a design constraint, not just a check:** the annotation must be **appended at
      > the END of the July-2 segment** (immediately before `Previous: June 30, 2026`). Verified
      > empirically — an end-append passes the substring check; a mid-segment insertion **fails**
      > it, which is exactly the destructive edit CLO's B3 blocks.
- [ ] **AC8 — posture linter.** `lint-encryption-posture.py --repo-sweep` PASSES, and **both**
      bare line-number `disclosed_as` citations are now content anchors:
      `stores[0]` (was `privacy-policy.md:519` — a **dead** anchor: `grep -c "519"` → 0) and
      **`connections[0]` (`web-platform server -> Supabase Postgres/PostgREST`, was
      `data-protection-disclosure.md:316`)**. Assert `git diff` on
      `scripts/encryption-posture-ledger.json` touches **exactly those two strings**.

      > `connections[0]` was missed by the plan's first draft and independently flagged by two
      > reviewers. It points into a file this PR edits. It is not evaluated today
      > (`cert_verification: "on"` short-circuits the whole `disclosed_as` block in
      > `check_connection`), and it *does* resolve (`grep -c "316"` → 4) — but asserting "there are
      > none" while leaving one is the weaker option.

      > **`stores[2]` (`hcloud_volume.workspaces`) must be BYTE-UNCHANGED.** It carried
      > `disclosed_as: "not-publicly-claimed"` only as a Deliverable-3 dependency; with the hold
      > reaffirmed that value is trivially correct and the row is out of scope. Any diff hunk
      > touching it — including its `exception.justification` — fails this AC.
- [ ] **AC9 — registers (CLO-blocking).** (a) `article-30-register.md` **residual-zero under the
      Phase-1 union anchor** — not merely items 13–16 / 17–20, but every cell: `(g)` TOMs at `:50`
      and `:68`, **`(d)` Recipients at `:47`, `(e)` Transfers at `:48` and `:163`, and the
      Vendor/Sub-Processor Mapping row at `:426`**. (b) `compliance-posture.md` no longer scopes the
      DPA to `git-data host CAX11` and carries no present-tense `web-2` claim.

      > Limb (a) is the correction that keeps this fold-in from defeating its own rationale.
      > Scoping the register edit to the TOM cells would ship a public retraction while
      > `(d) Recipients` and `(e) Transfers` — **Art. 30(1)(d)/(f)** limbs, a *stronger* obligation
      > than the volunteered TOM prose — still assert a destroyed host and an unborn CAX11.
- [ ] **AC9b — accuracy hygiene (non-blocking).** `nfr-register.md:522` corrected.

      > Split from AC9 deliberately. CLO B2's authority is Art. 30(1)(g) + Art. 5(2); an internal
      > engineering NFR table is outside it, and this row is an **under**-claim (the unexposed
      > direction). A snag here must not read as a CLO block.
- [ ] **AC10 — DC-1.** Status is no longer `OPEN — remediation tracked, exposure accepted`;
      records the 2026-07-23 certification, this PR's retraction, and the lapsed reopen trigger.
- [ ] **AC11 — challenge recorded, with its outcome.**
      `specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` exists and its
      Deliverable-3 entry names all five of: (i) the #6918 UC-3 hold, (ii) the revisit-trigger
      analysis as put to the operator (*"if the teardown slips materially, revisit Path 2"*; #6808
      OPEN ⇒ soak clock not started ⇒ earliest cure "#6808 fix + 7 days", no committed date),
      (iii) the operator's **REAFFIRMATION** of the hold on 2026-07-24, (iv) the CLO's contrary
      recommendation recorded as **overridden**, not deleted, and (v) the accepted residual with
      **#6808** named as its tracking issue.

      > Checkable by reading the file for those five elements. It is not a reversal record — it is
      > an *acceptance* record, which is the harder one to reconstruct later if it is missing.
- [ ] **AC12 — CLO attestation.** `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`
      exists, written by the CLO agent (not routed to the operator), **and it records the
      disclosure recommendation as made, overridden, and residually accepted** — with #6808 as the
      tracker. An attestation that silently omits its own overridden block fails this AC.
- [ ] **AC13 — `Ref #6897`, never `Closes #6897`.** Closing it would orphan the ledger's
      `tracking_issue: "#6897"` rows and the `model.c4:216,220` refs, leaving live exceptions
      pointing at a closed issue.

      > Trimmed at plan-review from a four-part bundle. `Closes #6588`, the other `Ref`s, the Tier
      > classification and the banner-style note are `ship` hygiene, already covered by `ship`'s
      > own PR-body construction — they do not need an AC each. The `Ref`-not-`Closes` clause is
      > the only load-bearing one, because getting it wrong is silent and destructive.
- [ ] **AC14 — live verification.** The Phase-0 verify run id and its discriminating fields are
      pasted into the PR body, dated the day of the PR.
- [ ] **AC15 — #6808 ESCALATED (Deliverable 3's shipped half).** Verifiable from the issue itself,
      by anyone, after the fact:

      ```bash
      gh issue view 6808 --json labels --jq '[.labels[].name]'
      gh issue view 6808 --comments --json comments \
        --jq '.comments[-3:] | .[] | .createdAt + " :: " + .body'
      ```

      (a) Labels contain **`priority/p1-high`** and **`type/security`**, and **no longer** contain
      `priority/p2-medium` (pre-state measured this session: `priority/p2-medium`, `type/bug`,
      `domain/engineering` — a real delta, not a no-op).
      (b) A comment exists, dated the day of the PR, that names **`#6588`**, **this PR** (number or
      URL), and states in terms that #6808 now gates a **live published over-claim** rather than
      only a monitoring gap.
      (c) That comment records the reaffirmed hold and names #6808 as the residual's tracking
      issue, so the issue thread is self-contained for a reader who never sees this plan.

      > This is the deliverable, not a courtesy note. The operator chose Path 1 (cure the reality)
      > over Path 2 (qualify the words); Path 1 is only credible if its blocker is actually
      > prioritised. If AC15 does not hold, Deliverable 3 shipped **nothing at all** — the hold
      > would then be a silent acceptance, which is the one outcome §3d exists to prevent.

### Post-merge (operator)

*None.* Every step is automatable in-session — `gh workflow run` for verification, `gh issue
view` for state, `gh issue comment` + `gh issue edit` for the #6808 escalation, local test
binaries for the gates. There is no vendor dashboard, no `terraform apply`, no migration, and no
credential mint in this PR.

**In particular, the #6808 escalation is NOT an operator step** (`wg-block-pr-ready-on-undeferred-operator-steps`).
It is two `gh` commands run in-session and asserted by AC15.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a published privacy policy at soleur.ai that
still asserts an Art. 32 safeguard that does not exist — cross-host TLS, membership
re-verification on proxied sessions, a dedicated git-data host — or that loses the one safeguard
claim that *is* now earned (see AC3(b)). Either is the same defect: the published document and
the infrastructure disagree. For a product whose entire proposition is that a non-technical
founder can trust an autonomous agent with their codebase, a demonstrably false security claim
in the published policy is not a docs bug — it is the trust proposition failing in the one
artifact a prospective user reads *before* deciding to trust it.

**What this PR knowingly does NOT fix — stated plainly.** The re-scoped LUKS clause reads, to an
ordinary user, as a statement about *their* data. A full un-wiped plaintext copy of every
workspace remains on `hcloud_volume.workspaces`. That reading gap is **not closed by this PR** and
is **not disclosed to users**: the operator reaffirmed the UC-3 hold on 2026-07-24, choosing to
cure the reality (wipe the volume) rather than qualify the words. It is an **accepted,
undisclosed residual**, recorded in `decision-challenges.md` (AC11), carried as **R4** in §Risks,
and tracked on **#6808** (AC15). It is narrower than the pre-PR state — (a), (b) and (c) are
false claims being deleted outright — but it is not zero, and this plan does not pretend it is.

**If this leaks, the user's source code is exposed via:** the retained plaintext
`hcloud_volume.workspaces` — a Hetzner block volume seizure, RMA, snapshot image, or
mis-scoped detach yields every workspace's repository in the clear. The LUKS mapper protects the
*live* volume; it does nothing for the retained copy. Erasure is a second vector: workspace git
data on that volume is **outside the account-deletion path**, so an Art. 17 request today would
not reach it.

**Brand-survival threshold:** `single-user incident`.

**Why this threshold on a docs-only PR.** Per the #6588 learning: *"Threshold follows the
surface, not the file type. A 'docs-only' PR that edits the public privacy policy has a user
surface."* Keeping `single-user incident` on the 2026-07-16 PR is precisely what fired
`user-impact-reviewer` and surfaced the P1 that became this issue. It fires again here.

**Sign-off.** `plan_time_signoff: CLO`, not CPO — Product = NONE (zero UI surface); the risk
axis is legal-claim-vs-reality. This mirrors the correction already made on the #6897 plan,
whose `requires_cpo_signoff: true` was found to contradict Product = NONE.
`user-impact-reviewer` runs at review time per the threshold.

**Mitigating fact, recorded not relied upon:** there are **zero arms-length data subjects**
today (#3723 OPEN; the volume holds the operator's own dogfooding workspaces). No data subject
has yet been misled. This makes the retraction **cheap now**, and it is what bounds the accepted
residual to a survivable size — it is the reason `p1-high` rather than `p0-critical` is the right
escalation on #6808 (§3c). It is **time-limited**: the cost of the remaining correction only rises
from here, which is why the p0 trigger is written into §3c and R4 — first arms-length onboarding
(#3723) while #6808 is open flips this assessment.

---

## Availability / Runtime Risk

**This change has no runtime or deploy risk. Explicitly:**

- **No production infrastructure is mutated.** `live_infra_mutation: none`. Zero `.tf` files,
  so the merge-triggered `apply-web-platform-infra.yml` does not fire on any resource.
- **No application code path changes.** `legal-doc-shas.ts` exports a constant map consumed
  only by a CI guard and its unit test — no route, no server module, no client bundle imports it.
- **No migration, no schema change, no secret, no new vendor, no cron.**
- **The only deploy triggered** is the Eleventy docs site (`deploy-docs.yml` fires on
  `plugins/soleur/docs/**`). The edits are prose **inside the existing
  `<section class="content">` wrapper** — no template change, no new selector — so
  `cq-eleventy-critical-css-screenshot-gate` has nothing new above the fold. Verify the build
  with the **repo-root pinned** `./node_modules/.bin/eleventy`, never `npx` (a cached wrong
  version and a CWD trap have both bitten here before).
- **Rollback is `git revert`.** No state to unwind.

---

## Observability

**The gate applies** (Files to Edit carries `apps/web-platform/lib/legal/legal-doc-shas.ts` and
`scripts/encryption-posture-ledger.json` — not pure-docs), so this is the full 5-field schema, not
a skip note. An earlier draft filed a skip justification here; that was non-compliant.

The observable surface of a published-claim PR is **claim-vs-reality divergence**: the ways this
PR's assertions can silently become false after merge.

```yaml
liveness_signal:
  what: "luks-monitor.sh daily probe on web-1 — mount→mapper resolution, `cryptsetup status`,
         `blkid` device_type=crypto_LUKS, Doppler escrow re-test, LUKS header UUID readback.
         This is the signal that keeps the re-scoped clause (d) TRUE after merge."
  cadence: "daily (host timer), plus on-demand via `workspaces-luks-verify.yml` workflow_dispatch"
  alert_target: "betteruptime_heartbeat.workspaces_luks (Better Stack) — a missed daily push
                 should page. KNOWN-BROKEN: WORKSPACES_LUKS_HEARTBEAT_URL is unwired, so the
                 probe runs, succeeds, and pushes nothing. Tracked #6808 (OPEN). This PR does
                 NOT close it and does not depend on it for merge — but it is precisely why
                 Deliverable 3 ESCALATES it: #6808 blocks the soak, the soak blocks the
                 plaintext wipe, and the wipe is the operator-chosen cure for the residual
                 this PR leaves undisclosed."
  configured_in: "apps/web-platform/infra/luks-monitor.sh; .github/workflows/workspaces-luks-verify.yml"

error_reporting:
  destination: "GitHub Actions check failure on the PR (tc-document-sha-guard — a required check,
                name-pinned by infra/github/ruleset-ci-required.tf per ADR-032); vitest failure
                for legal-doc-consistency; non-zero exit for lint-encryption-posture.py.
                Post-merge divergence: discriminating Sentry event from luks-monitor drift."
  fail_loud: true   # every gate is blocking; none is advisory, none is continue-on-error

failure_modes:
  - mode: "SHA pin goes stale (a docs/legal byte changes after Phase 4 pins)"
    detection: "check-tc-document-sha.sh raw-byte sha256 mismatch"
    alert_route: "tc-document-sha-guard required check → PR blocked (cannot merge)"
  - mode: "Canonical and Eleventy mirror drift (heading sequence or Last-Updated date)"
    detection: "legal-doc-consistency.test.ts — heading-sequence parity + 9-site date equality"
    alert_route: "vitest failure in CI → PR blocked"
  - mode: "Ledger disclosed_as content anchor rots (the cited prose is later reworded away)"
    detection: "lint-encryption-posture.py --repo-sweep (hermetic; fails CLOSED on an
                unresolvable anchor)"
    alert_route: "Encryption posture Layer A CI job → PR blocked"
  - mode: "The accepted undisclosed residual outlives its cure path — #6808 stays open, the
           ADR-119 soak never starts, and the plaintext volume is never wiped"
    detection: "#6808 open-state; ledger exception expires_on 2026-10-22 on
                hcloud_volume.workspaces (internal commitment, never published)"
    alert_route: "#6808 (escalated to priority/p1-high by this PR, AC15) + the #6897 umbrella;
                  Layer A flags an expired exception on sweep"
  - mode: "THE SUBSTANTIVE ONE — the LUKS claim silently becomes false again post-merge
           (precedent: #6812, crypto_LUKS held ~27 min then a dead-man timer reverted it)"
    detection: "luks-monitor.sh daily probe emits discriminating Sentry on mapper/escrow/header
                drift; workspaces-luks-verify.yml re-asserts on demand"
    alert_route: "Sentry (live today) + Better Stack heartbeat (DARK until #6808 — a real
                  detection gap on the very claim this PR re-scopes, which is a second reason
                  Deliverable 3 escalates #6808 rather than merely noting it)"

logs:
  where: "GitHub Actions run logs (CI gates); Better Stack Logs source 2457081 for host-side
          luks-monitor self-reports; Sentry for drift events"
  retention: "Actions logs 90d (GitHub default); Better Stack per plan retention; Sentry per
              project retention"

discoverability_test:
  command: "gh workflow run workspaces-luks-verify.yml && gh run list --workflow=workspaces-luks-verify.yml --limit 1 --json databaseId,conclusion"
  expected_output: "conclusion=success with SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8 against /dev/mapper/workspaces"
```

**No SSH anywhere in the discoverability path** (`hr-no-ssh-fallback-in-runbooks`). The verify
workflow reaches web-1 over the CF Tunnel SSH *bridge* as a transport, but the operator/agent
never SSHes a host to check whether it worked — the verdict is read from the workflow run.

---

## Encryption Posture

This PR **introduces no store and no connection** — the path detector (`\.tf$`,
`supabase/migrations/*.sql`, `cloud-init*`, `docker-compose*`) does not fire. But it **edits
`scripts/encryption-posture-ledger.json`** and its whole subject matter is what is publicly
claimed about at-rest posture, so the schema is filled for the three rows in scope — **two edited
(`workspaces_luks`, the Supabase connection) and one deliberately left untouched
(`hcloud_volume.workspaces`)** — rather than skipped. **No measured posture changes here — only
what is claimed about it, and for the plaintext row not even that.**

Values are transcribed from the committed ledger (verified this session; linter baseline
`14 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS`).

```yaml
at_rest:
  - store: hcloud_volume.workspaces_luks          # the LIVE serving volume — clause (d)'s subject
    mechanism: luks
    evidence: "workspaces-cutover.sh:2030,2041 (cryptsetup luksFormat/luksOpen,
               MAPPER_NAME=${WORKSPACES_MAPPER_NAME:-workspaces}); key: random_password.workspaces_luks
               + doppler_secret.workspaces_luks_key (workspaces-luks.tf); mount gate:
               soleur-host-bootstrap.sh:564-565"
    defends_against: "a seized/RMA'd or snapshot-imaged Hetzner block volume: contents are
                      unreadable without the Doppler-held LUKS passphrase"
    does_not_defend: "a leaked service-role credential, an RLS bypass, an SSRF reaching the store,
                      or any read on the live host where the mapper is already unlocked"
    disclosed_as: "docs/legal/privacy-policy.md — §11 Security bullet (CONTENT ANCHOR; this PR
                   replaces the dead line-number citation `:519`, which resolves to nothing:
                   grep -c '519' returns 0)"
    live_verification: available   # luks-monitor.sh + workspaces-luks-verify.yml

  - store: hcloud_volume.workspaces               # the RETAINED PLAINTEXT ORIGINAL — row UNCHANGED by this PR
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/server.tf:1569 (format = \"ext4\", no LUKS apparatus)"
    defends_against: "nothing at the volume layer; superseded on web-1 by
                      hcloud_volume.workspaces_luks (cutover certified 2026-07-23, run 30040444418)"
    does_not_defend: "a seized/snapshot disk exposes any workspace data still resident on this
                      volume"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:host attachment state not pulled in the code-sourced audit;
                        tracked #6897"
    exception:
      justification: "superseded plaintext resource retained as the pre-cutover rollback backstop;
                      web-1 /mnt/data now runs on the LUKS workspaces_luks mapper"
      tracking_issue: "#6897"
      reevaluate_when: "the workspaces_luks cutover is confirmed irreversible and the plaintext
                        volume can be detached and destroyed"
      expires_on: "2026-10-22"

in_transit:
  - connection: "web-platform server -> Supabase Postgres/PostgREST"
    tls: "https (Supabase REST) / TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked anon/service key; TLS protects the channel, not the credential"
    disclosed_as: "docs/legal/data-protection-disclosure.md — CONTENT ANCHOR (this PR replaces the
                   bare line-number citation `:316`; not evaluated today because
                   cert_verification: on short-circuits check_connection's disclosed_as block)"
```

**No `exception` block is required for the `in_transit` row** (`cert_verification: on`). The
`at_rest` plaintext row carries one, with both `tracking_issue` and `expires_on` present.

> **The `hcloud_volume.workspaces` row above is transcribed VERBATIM from the committed ledger and
> this PR does not modify one byte of it.** It was in scope only for the retracted Deliverable 3
> (see §4f item 2, AC8). Its `disclosed_as: "not-publicly-claimed"` is accurate precisely *because*
> the hold was reaffirmed — no published document claims anything about this store. This row is
> where the accepted residual lives on the record; do not "tidy" it.

> **The `expires_on: 2026-10-22` is an INTERNAL commitment, not an achieved schedule** — the cure
> path (#6808 fix + a 7-day soak that has not started) has no committed start date. It must never
> be published as a deadline (CLO B4). Post-amendment nothing about it is published at all.

---

## Architecture Decision (ADR / C4)

**No ADR. No C4 edit.** Detection does not fire: this PR makes no architectural decision. It
changes no ownership/tenancy boundary, introduces no substrate or integration pattern, changes
no resolver/dispatch/trust boundary, and reverses no ADR. It corrects published prose to match
an architecture already decided (ADR-119) and already shipped.

**C4 completeness check — enumerated, not assumed.** Per the mandate, all three model files were
read rather than keyword-grepped, and each category enumerated:

- **External human actors:** none added, removed, or changed. No new correspondent, reviewer,
  or recipient is introduced by a prose correction.
- **External systems / vendors:** none added or changed. Hetzner, Cloudflare, Better Stack,
  Doppler, Supabase are all already modeled.
- **Containers / data stores touched:** `workspacesVolume` and `gitDataStore`. **Both are
  already modeled and already accurate.** `model.c4:186` states *"ENCRYPTED AT REST as of the
  2026-07-23 cutover — the gap #6588/ADR-119 opened … is closed"* and cites run 30040444418;
  `model.c4:216` states git-data is *"currently PLAINTEXT ext4 … Ledgered exception … tracking
  #6897, pending cutover."* The C4 already says what this PR is making the legal docs say.
- **Actor↔surface access relationships:** none change. No sharing model, no ownership model,
  no membership semantic is altered.

**One observation, deliberately NOT folded in:** `model.c4:214` models `gitDataStore` as a live
element and `:449` describes a consumer probe to `10.0.1.20:22` feeding `git_data_prd`, while
#6570 (OPEN) holds that the host *cannot be born*. That is an internal engineering-diagram
tension, not a published-claim defect, and it belongs to #6570/#6897 — not to a legal-accuracy
PR. Folding it in would mix an infra-modeling question into a published-claim correction.
**Recorded here so it is not silently ignored.**

---

## Domain Review

**Domains relevant:** Legal (blocking), Engineering (advisory). Product: **NONE** — zero UI
surface; the mechanical UI-surface override did not fire (no path in Files to Edit matches
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or the UI-surface term list).

### Legal (CLO) — `soleur:legal:clo`

**Status:** reviewed (invoked this session, blocking). **B1 was overridden by operator decision on
2026-07-24**; B2–B4 stand. The override is a recorded exception, not a re-ruling — the CLO's
position below is unamended.

**Assessment.** Ruled on all three referred questions. Q1: affirmative disclosure **recommended**,
and the CLO would have blocked without it. Q2: **annotate** the historical banner entry — reject
in-place amendment. Q3: Art. 30 register corrections ship **in the same PR** — not sequenceable.

**Q1 — RECOMMENDED, OVERRIDDEN, RESIDUAL ACCEPTED. Recorded, not erased.**

The CLO's reasoning is preserved in full because an accepted residual must remain visible:

- **Arts. 13/14** are *not* the source of the duty — TOMs are not an enumerated limb, and a
  transient storage-media state is operational detail outside them. Correctly disposed of.
- **Art. 32(1)** is substantive, not publicational; it creates no disclosure duty.
- **Art. 5(2)** is already discharged internally by the ledger row and the Art. 30 register.
- **What decided it for the CLO was the #6588 over-claim standard itself.** *"Stored workspace git
  data sits on a LUKS-encrypted volume"* is read by any user as a statement about **their data**,
  not about **one volume**. A full un-wiped copy on a seizable disk defeats precisely the threat
  the sentence advertises, and Soleur has that admission in writing in its own ledger.

**Disposition:** the CLO **recommended disclosure; the operator reaffirmed the hold on 2026-07-24
after being shown the revisit-trigger analysis; the residual is accepted and tracked via #6808.**
The CLO position is recorded rather than deleted — the correct anchors, per that review, are
**Art. 12(1) + 5(1)(a)** (not Art. 13(3), which the #6588 premise table already found wrong for
this class); noted here so the deferred Path-2 edit does not propagate a loose citation.

**Blocks carried into the ACs:**

| Block | Status | Where enforced |
|---|---|---|
| B1 — no re-scoped clause (d) without the retained-plaintext sentence | **OVERRIDDEN by the operator** (hold reaffirmed 2026-07-24). Residual accepted, tracked #6808 | AC11 (record) + AC12 (attestation) + AC15 (escalation); AC4 asserts no sentence shipped |
| B2 — no public retraction without the register + `compliance-posture.md:80` corrections | **STANDS** | AC9 |
| B3 — no in-place edit of the `Previous: July 2, 2026` wording; annotate only | **STANDS** | AC7 |
| B4 — no published wipe date while #6808 is open | **STANDS** (trivially satisfied — nothing about the volume is published) | AC4(c) |

**Additional findings folded in:** DPD processor table outranks the TOM prose (Phase 2 ordering);
ledger content anchors (§4f); line-number citations violate
`cq-cite-content-anchor-not-line-number` (§4f, AC8); Art. 17 erasure reachability gates #3723
(§Risks R1); the "7-day soak" is not actually running (Deliverable 3 — now the escalation's
central fact); six files not three (P6).

**Phase 5.5 attestation:** the CLO agent performs the per-artifact review and writes
`knowledge-base/legal/audits/2026-07-counsel-review-6588.md` **at PR time**, and that audit must
itself record B1 as recommended-and-overridden with its accepted residual (AC12). It is explicitly
**not** an operator task. All output is draft material requiring professional legal review.

### Engineering (advisory)

Gate mechanics verified directly (§4a, §4f) rather than by assessment. No architectural
concern; no runtime surface.

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan — direct
one-shot entry).
**Skipped specialists:** none.
**Pencil available:** N/A (no UI surface).

---

## GDPR / Compliance Gate (Phase 2.7)

**Fires** — this is a regulated-data-surface change by subject matter, even though the canonical
path regex (schemas/migrations/auth/API routes/`.sql`) does not match. Trigger (b) applies:
brand-survival threshold is `single-user incident`.

The gate's function here is **discharged by the CLO domain review above**, which is the
higher-authority instrument for published legal copy (it is the artifact under review, not a
diff to be scanned). Findings are folded inline as blocks B1–B4 rather than filed.

**Not all of them are cured by this PR — say which.** B2, B3 and B4 are cured in the diff. **B1 is
not:** it was recommended, overridden by the operator, and its residual accepted. No new
`compliance/critical` issue is filed for it, because filing a fresh issue for a residual that
already has a blocker would split the tracking; instead the existing **#6808** is escalated to
carry it (§3c, AC15), with **#6897** as the umbrella and **#3723** holding the Art. 17
reachability gate. Net issue flow **for this gate**: 0 new, 1 re-prioritised. (The separate
one-line #6893 filing in §4f is an engineering linter gap, not a GDPR finding.)

---

## Issue Reconciliation — #6897 overlap

**Explicitly noted, neither duplicated nor ignored** (as the task required).

#6897's third checkbox is *"Legal-doc reconciliation — run `/soleur:legal-audit` … so
`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` encryption claims are
substantiated, not asserted."*

**It already ran.** PR **#6918** merged 2026-07-24 17:55 CEST. The `legal-compliance-auditor`
found the material over-claim; the operator **HELD** the copy fix (UC-3) and preserved the
auditor's Path-2 wording verbatim. #6897 **stays OPEN** by explicit operator decision (net-issue-flow 0;
its residuals are ongoing bounded exceptions that need an umbrella to home them).

**And the hold was re-raised and REAFFIRMED on 2026-07-24** (§Deliverable 3). That is the fact
that governs this reconciliation.

**Therefore:**

- This PR **does NOT execute the held Path-2.** It **partially** satisfies that bullet: the
  encryption claims that were *unachievable* are retracted and the surviving LUKS claim is
  re-scoped to the real topology, so those are substantiated rather than asserted. The
  **retained-plaintext limb remains open** — held by the operator, undisclosed, with the cure
  path escalated onto **#6808**. An implementer must not read this section as "the bullet is
  done."
- **Use `Ref #6897`, never `Closes #6897`.** Closing it would orphan the 8 ledger
  `tracking_issue: #6897` references and the C4 refs at `model.c4:216,220`, leaving live
  exceptions pointing at a closed issue — the exact failure PR #6918 was written to avoid.
- The ledger rows' `reevaluate_when` triggers remain the binding between the legal recon and the
  infra teardown. This PR does **not** discharge them: when the plaintext volumes are actually
  detached and wiped, the recon re-fires to confirm the wording became unconditionally true.
- **#6893** (claim-unlock gate) is untouched and still bounds external copy to the
  *verifiability* claim. AC3 enforces that this PR does not breach it.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| **R1** | **Art. 17 erasure reachability (the sleeper).** Workspace git data on the retained plaintext volume is outside the account-deletion path; an erasure request today would not reach it. | No live exposure at tenant-zero (#3723 OPEN, zero arms-length subjects) so it does **not** block this PR. It **hard-blocks #3723**: the volume must be wiped, or erasure extended to it, before first arms-length onboarding. **Posted as a comment on #3723** (Phase 5.6) — the diff-side addition was cut at plan-review (§4d), so this is *not* enforced by AC9. |
| **R2** | Literal-phrase sweep misses variant phrasings and silently false-passes. | Union-anchor grep (Phase 1) with an asserted count of **22** (8 canonical body sites + 3 banner headers, ×2 — see §Site Matrix); **never** `grep LUKS`. This already bit once (P7). |
| **R3** | Removing a clause leaves a dependent clause dangling and *stronger* — the exact #6588 defect. | Claim-family litmus per site (Phase 1, AC2); family removed whole. |
| **R4** | **ACCEPTED, UNDISCLOSED RESIDUAL (the one this PR knowingly leaves).** The re-scoped LUKS clause ships while a full un-wiped plaintext copy of every workspace remains on `hcloud_volume.workspaces`. Its plain reading is broader than the infrastructure earns, and users are not told. Operator-accepted (UC-3 hold reaffirmed 2026-07-24) — accepted, not unnoticed. | **Tracking issue: #6808** — escalated to `priority/p1-high` + `type/security` with a comment recording that it now gates a live published over-claim (§3c, **AC15**). Recorded in `decision-challenges.md` (**AC11**) and in the CLO attestation (**AC12**). Bounded by the facts that make it survivable *today*: zero arms-length data subjects (#3723 OPEN), the residual is ledgered (`plaintext-exception`, `#6897`, `expires_on: 2026-10-22`) and named in the Art. 30 register (§4d). **Escalation trigger: if #3723 onboards a first arms-length user while #6808 is open, this becomes p0 and the hold must be re-raised.** |
| **R4b** | The linter cannot distinguish an honest under-claim from an over-claim (`check_disclosed_as_not_encrypted` FAILs on `/LUKS\|encrypt/i` in the ±300-char window), so it will obstruct the *deferred* Path-2 wording when #6808 finally clears. | Not exercised by this PR (no `disclosed_as` flip). Filed as a one-line issue against **#6893** (Phase 4.6). **Do not edit `lint-encryption-posture.py` here** — it would change the PR's declared change-class. |
| **R5** | Mirror drift — 6 files hand-maintained, no generator. | Edit canonical-then-mirror per claim family, not per file; `legal-doc-consistency.test.ts` (heading + 9-date parity) is the mechanical gate. |
| **R6** | Trusting the 2026-07-23 certification when the live state has since reverted (#6812 precedent: crypto_LUKS held ~27 min then silently reverted). | Phase 0 dispatches a **fresh** verify run; AC14 pastes its id + fields, dated the day of the PR. |
| **R7** | Banner annotation accidentally alters the preserved historical text (Session Error #4: a sync script silently dropped a `Previous:` label). | AC7 asserts insertion-only on that segment and an unchanged-plus-one `Previous:` count. |
| **R8** | **Re-raising an operator decision and leaving no record of the outcome.** The challenge resolved *for* the operator, and the failure mode of a resolved-in-favour challenge is that nobody writes it down — leaving a knowingly-retained live over-claim indistinguishable from one nobody noticed. | Deliverable 3 is recorded as a User-Challenge in `decision-challenges.md` (AC11) with all five required elements including the overridden CLO position; the escalation on #6808 (AC15) makes the acceptance legible from outside this repo's planning artifacts; `ship` renders the DC record into the PR body. |
| **R9** | An implementer, reviewer, or later agent works from a stale draft of Deliverable 3 (or from #6918's preserved Path-2 wording) and adds the disclosure sentence back. | **AC4(b)** — the 6-file diff must contain no added line matching the disclosure anchor. The Phase-2 note and the amendment banner at the top of this plan state it in prose; AC4 makes it mechanical. |

---

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Past-tense the three clauses** instead of retracting | (a) and (b) were never true *at any moment* — there was never a cross-host session or cross-host git traffic. Past tense would assert a false historical fact. (c) describes a host that never existed. The banner carries the history instead. |
| **Retract the LUKS clause too**, publishing no encryption claim | Worse for users and worse for posture: the claim is now **true** of the live store. Deleting an earned safeguard claim under-informs data subjects. CLO concurred. |
| **Add the affirmative plaintext disclosure in this PR** (the original Deliverable 3; CLO's B1) | **CHOSEN AGAINST — by the operator, 2026-07-24.** The question was re-raised with the full revisit-trigger analysis (#6808 OPEN ⇒ soak clock not started ⇒ earliest cure "#6808 fix + 7 days", no committed date) and with the cost argument (this PR already rewrites those exact sentences). The operator **reaffirmed the UC-3 hold**, choosing Path 1 — cure the reality by wiping the volume — over Path 2 — qualify the published wording. Residual accepted and tracked via **#6808** (§Risks R4). Recorded, not erased: §Domain Review keeps the CLO's reasoning in full. |
| **Escalate #6808 to `priority/p0-critical`** to mirror #6588 | `p0-critical` means *"drop everything"*, which contradicts the decision the operator just made (hold and proceed), and it is not earned: zero arms-length data subjects today (#3723 OPEN). `p1-high` — *"degraded functionality, no workaround"* — is exact for a soak clock that cannot start. The p0 trigger is written into §3c instead. |
| **File a new `compliance/critical` issue for the accepted residual** | Splits tracking across two issues for one condition. #6808 already *is* the blocker; escalating it keeps the residual and its cure on the same thread (§GDPR Gate). |
| **Sequence the Art. 30 register into a follow-up** | Produces a state strictly worse than today — a timestamped public retraction beside an internal register still asserting the retracted TOMs. Art. 30(1)(g) + Art. 5(2). CLO blocks (B2). |
| **Amend the historical banner entry in place** | Destroys the Art. 5(2) audit trail the append-with-history banner exists to provide. CLO blocks (B3). Annotate instead. |
| **Fix the `model.c4` gitDataStore/#6570 tension here** | Mixes an infra-modeling question into a published-claim correction. Belongs to #6570/#6897. Recorded, not folded (§Architecture Decision). |
| **Fix #6808 / run the soak / wipe the plaintext volume in this PR** | Explicitly out of scope per the task; it is infra work in a docs-class PR declaring `runtime_deploy_risk: none`. This PR neither changes the state nor publishes it — it **escalates the blocker** so the operator-chosen cure actually moves (§3c, AC15). |

---

## Research Insights — verify-the-negative sweep (deepen Phase 4.45)

Every load-bearing **negative** claim in this plan was independently grepped against the named
artifact. **10 of 10 CONFIRM; zero contradictions.** Citations are the authority — if a claim in
the prose above drifts from this table, this table wins.

| # | Claim | Verdict | Citation |
|---|---|---|---|
| 1 | No mirror body-equivalence check runs for our 3 docs | **CONFIRMS** | `check-tc-document-sha.sh:177` — `BODY_EQUIVALENCE_DOCS=("terms-and-conditions")`; comment at `:14-17` explicitly defers the other 8 |
| 2 | No SHA bypass exists for non-T&C docs | **CONFIRMS** | `check-tc-document-sha.sh:240` gates the bypass on `[ "$doc" = "terms-and-conditions" ]`; the `else` at `:271` has no bypass path |
| 3 | `tc-document-sha-guard` is a pinned required check | **CONFIRMS** | `infra/github/ruleset-ci-required.tf:152` |
| 4 | Mirrors are hand-maintained; no generator | **CONFIRMS** | Repo-wide grep for `pages/legal` hits only the guard script + 2 vitest tests. **No writer.** |
| 5 | Consistency test asserts heading parity + 3 date sites | **CONFIRMS** | `legal-doc-consistency.test.ts:106-113` (headings), `:161/:162/:163` (the 3 date extractions), asserted equal at `:177,:179` |
| 6 | Our 3 docs are not T&C-coupled — no `TC_VERSION` bump | **CONFIRMS** | `tc-version.ts:14,34-35` reference only `terms-and-conditions.md` |
| 7 | `deploy-docs.yml` fires on `plugins/soleur/docs/**` | **CONFIRMS** | `deploy-docs.yml:11` |
| 8 | `workspaces-luks-verify.yml` is `workflow_dispatch`-ONLY | **CONFIRMS** | `:41-59` — no `schedule:`, no `push:`. **Phase 0 must dispatch it explicitly; nothing fires it for us.** |
| 9 | `lint-encryption-posture.py` is hermetic | **CONFIRMS** | Only `os/json/re/pathlib/argparse/datetime` imported; zero network call sites |
| 10 | Editing `knowledge-base/legal/**` or the ledger cannot stale the 3 SHAs | **CONFIRMS** | `check-tc-document-sha.sh:37,55-57` — `CANONICAL_DIR=docs/legal`, glob-scoped |

**Consequence for Phase 4 ordering:** claim 10 is what makes the ledger-before-SHA sequencing safe,
and claim 2 is what makes the pin non-negotiable. Both are now cited, not assumed.

## Open Code-Review Overlap

**None.** All 60 open `code-review`-labelled issues were queried and none references any file in
`## Files to Edit` (checked: the three canonical legal docs, the mirror path prefix,
`legal-doc-shas.ts`, `article-30-register.md`, `compliance-posture.md`,
`encryption-posture-ledger.json`).

---

## Sharp Edges

- **Never `grep LUKS` to find this claim family.** Three of the **eight** canonical body sites
  (`pp:489`, `gdpr:318`, `dpd:318`) carry a claim with no `LUKS` token at all. Use the union
  anchor.
- **`gdpr-policy.md` phrases the git-data-host clause with different word order** (*"a dedicated
  host for per-workspace git data"*). A find-and-replace tuned to the DPD's phrasing misses it.
- **The `disclosed_as` "anchor" is a substring search, not a line lookup.** `resolve_disclosed_as`
  does `text.find(anchor)`, so `"519"` matches the first literal `519` anywhere in the file — and
  `privacy-policy.md` contains **zero** occurrences of it, so that citation is **dead**, not merely
  decorative. It is additionally **never evaluated** for a `mechanism: luks` row (early return),
  which is the only reason a dead anchor has not already failed CI. Do not assume the existing
  citation is meaningful.
- **Do NOT touch the `hcloud_volume.workspaces` ledger row.** It looks adjacent to this PR's
  subject matter and it is not: its `disclosed_as: "not-publicly-claimed"` is correct *because*
  the disclosure was held. Flipping it to a real anchor would run
  `check_disclosed_as_not_encrypted()`, which FAILs when the ±300-char window matches
  `/LUKS|encrypt/i` — an honest under-claim caught by a check built for over-claims. That trap is
  latent, filed against #6893 (§Risks R4b), and reached only by an edit this PR must not make.
- **No published legal text gains a plaintext-disclosure sentence.** The operator reaffirmed the
  UC-3 hold on 2026-07-24. PR #6918's preserved Path-2 wording is quoted in §3b **for the future
  edit only**; pasting it into a legal document in this PR violates AC4.
- **Nine date strings, not three.** Mirrors carry the date twice (hero `<p>` + body).
- **Use the repo-root pinned `./node_modules/.bin/eleventy`**, never `npx` — a cached wrong
  version and a CWD trap have both bitten on this exact surface.
- **Do not trust a background runner's exit code** on the test suite; grep the log for `FAIL`/`× `.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This one is filled.
