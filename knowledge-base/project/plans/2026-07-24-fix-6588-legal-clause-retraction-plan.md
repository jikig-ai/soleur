---
title: "fix(legal): retract the three unachievable multi-host clauses, re-scope the LUKS clause to the live single-host topology, and disclose the retained plaintext backstop (#6588 legal half)"
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
---

# fix(legal): #6588 legal half — retract, re-scope, disclose

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
3. **DISCLOSE** the retained pre-cutover plaintext volume honestly.
4. **MECHANICS** — re-pin `legal-doc-shas.ts`, close DC-1, append+annotate the provenance
   banner, correct the internal registers, reconcile with #6897.

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
| P3 | #6808 OPEN, blocks soak + Phase-5 wipe | **HOLDS.** Body confirms `WORKSPACES_LUKS_HEARTBEAT_URL absent — heartbeat not pushed`. `workspaces-luks-soak-6604.sh` gates on the heartbeat being **present** and rows spanning **≥7d**, so the soak clock has not started | Material — see §Deliverable 3 |
| P4 | git-data host "never born" | **HOLDS.** #6570 still OPEN: *"git-data is pinned to cax11 — orderable in 0 of 3 EU DCs, so it can never be born"* | Retract clause (c) |
| P5 | No load balancer; `app.soleur.ai` singleton to web-1 | **HOLDS.** `tunnel.tf:54` pins ingress to `var.web_hosts["web-1"].private_ip`; `model.c4:413` records single connector post-#6538 | Retract clause (b) |
| P6 | Clauses live in privacy-policy + DPD + 2 mirrors (**4 files**) | **STALE — UNDERCOUNT.** The claim family also lives in **`gdpr-policy.md`** and its mirror. **6 files**, not 4. Corroborated independently by #6897's own scope (`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`) and by DC-1's own "all 6 files" | Scope = 6 files |
| P7 | Clauses at "roughly lines 298 and 519" | **STALE — UNDERCOUNT.** **7 canonical body sites + 3 banner headers, ×2 = 20 sites.** Two sites (`privacy-policy.md:488`, `gdpr-policy.md:318`) carry the claim with **no `LUKS` token at all** | Union-anchor sweep; **never** `grep LUKS` |
| P8 | #6897 owns a "legal-doc reconciliation" bullet | **HOLDS, and it already RAN.** PR **#6918** merged 2026-07-24 17:55 CEST; the operator **HELD** the copy fix (UC-3) | See §Deliverable 3 + §Issue Reconciliation |
| P9 | *(implicit)* users are exposed today | **ZERO arms-length data subjects.** #3723 OPEN; the volume holds the operator's own dogfooding workspaces | Makes the correction **cheap now**; see §User-Brand Impact |

**P7 is the load-bearing correction.** A literal-phrase sweep is the documented failure mode
here (Session Error #2 of the #6588 learning: *"sweep the semantic quantity, not its
formatting"*). My own first-pass grep for `"across hosts"` + `"spans more than one"` **missed**
`privacy-policy.md:488` and `gdpr-policy.md:318`, which phrase it `"across more than one host"`.
The prior #6588 plan had already recorded this trap; this plan inherits its union anchor.

---

## Research Reconciliation — task statement vs. repo reality

| Task statement | Repo reality | Plan response |
|---|---|---|
| "docs/legal/privacy-policy.md ... plus data-protection-disclosure.md plus BOTH Eleventy mirrors" | `gdpr-policy.md` + its mirror carry the same family. **6 files** | Scope widened to 6; AC1 asserts residual-zero across all 6 |
| "roughly lines 298 and 519" | 7 canonical body sites; 2 have no `LUKS` token | Union-anchor grep (§Phase 1), content anchors not line numbers (`cq-cite-content-anchor-not-line-number`) |
| "re-pin legal-doc-shas.ts ... very likely a CI gate" | **Confirmed.** `tc-document-sha-guard` (required check, ADR-032-pinned name) via `check-tc-document-sha.sh`. Raw-byte `sha256sum`, **no bypass** for non-T&C docs | Phase 4; 3 SHAs |
| "possibly a cross-document consistency gate" | **Confirmed, and it is stricter than expected.** `legal-doc-consistency.test.ts` asserts (a) `##`/`###` heading-sequence parity canonical↔mirror, (b) **Last-Updated date byte-identical in 3 places per mirror** (canonical body, mirror body, mirror hero `<p>`) | Phase 3 + AC5; **9 date strings** total |
| "Follow the repo's ... 'Last Updated' provenance banner" convention | It is a **single 27,358-char line**, prepend-style: `**Last Updated:** <new> (...). Previous: <old> (...)` | Phase 3; §Banner Handling |
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

`privacy-policy.md:488` and `gdpr-policy.md:318` (+ mirrors) state, in present tense:

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

## Deliverable 3 — Disclose the retained plaintext original

### The decision, and its justification

**Ruling: an affirmative disclosure sentence is REQUIRED.** Not immaterial.

This is a User-Challenge under ADR-084 and must be handled as one, because the operator took a
contrary decision **on this same day**. The full reasoning:

**The facts.** `hcloud_volume.workspaces` (plain ext4, `server.tf:1569`) holds a full copy of
every workspace as of the 2026-07-23 cutover. It is ATTACHED-UNMOUNTED and UN-WIPED, retained
as the ADR-119 rollback backstop. The ledger's own words:
`does_not_defend: "a seized/snapshot disk exposes any workspace data still resident on this volume."`

**The prior decision.** PR #6918 (merged today) ran `/soleur:legal-audit`, which found exactly
this as a **material over-claim of the #6588 class**. The operator **HELD** the copy fix (UC-3),
on the reasoning that *Path 1 (infra teardown) will cure it and is already tracked*. The
auditor's Path-2 wording was preserved verbatim for later. That decision was legitimate and is
recorded in `2026-07-24-holding-a-live-overclaim-pending-infra-teardown-and-drain-can-mean-keep-open.md`.

**Why it should now be folded in — two independent reasons.**

1. **The HOLD's own revisit trigger has fired.** UC-3 states: *"If the teardown slips
   materially, revisit Path 2."* The teardown is blocked on **#6808** (OPEN). The soak probe
   `workspaces-luks-soak-6604.sh` requires the luks-monitor heartbeat to be **present** and its
   rows to **span ≥7 days**; with `WORKSPACES_LUKS_HEARTBEAT_URL` unwired, the clock has **not
   started**. Earliest cure is therefore *#6808 fix + 7 days*, with no committed date. That is a
   material slip, and it is knowable **today** — this is not overriding the operator, it is the
   condition the operator themselves named.
2. **The HOLD's cost rationale collapses.** The hold traded off "a doc edit we are not otherwise
   making." **This PR is already rewriting those exact sentences.** The marginal cost of accuracy
   is one clause. Shipping a re-scoped clause (d) that is literally true but leaves its plain
   reading false — inside the PR whose entire purpose is retracting over-claims — reproduces
   #6588's error class within #6588's own fix.

**Against the legal standard.** The CLO domain review (invoked this session) reached the same
conclusion independently and **BLOCKS** on shipping without it (B1). Its reasoning:

- **Arts. 13/14** are *not* the source of the duty — TOMs are not an enumerated limb, and a
  transient storage-media state is operational detail outside them. Correctly disposed of.
- **Art. 32(1)** is substantive, not publicational; it creates no disclosure duty.
- **Art. 5(2)** is already discharged internally by the ledger row. On its own this lands at
  *immaterial*.
- **What decides it is the #6588 over-claim standard itself.** *"Stored workspace git data sits
  on a LUKS-encrypted volume"* is read by any user as a statement about **their data**, not about
  **one volume**. A full un-wiped copy on a seizable disk defeats precisely the threat the
  sentence advertises — and Soleur has that admission in writing in its own ledger. Publishing
  the unqualified sentence while holding that admission is the same failure mode as (a)(b)(c):
  **a safeguard asserted more broadly than it is earned. That is the exposed direction.**

**Instrument.** Adopt the *shape* of the PR #4455 temporal-qualifier precedent (bounded
condition + `Ref #N`), but **do not cite Art. 13(3)** as authority. The #6588 plan's own premise
table (P7) already recorded that the Art. 13(3) anchor is wrong for this class — CLO ruled the
correct anchors are **Art. 12(1) + 5(1)(a)**, and #4455 disclosed something *forthcoming*
whereas this is a *residual* being retired. Do not propagate the loose citation.

### Where the disclosure goes — all five LUKS sites, two registers

The LUKS claim is made at **five canonical body sites** (×2 with mirrors): `privacy-policy.md:298`
and `:519`; `data-protection-disclosure.md:189` (processor table) and `:276`; `gdpr-policy.md:44`.
Putting the disclosure in `privacy-policy.md` alone would leave **DPD and GDPR Policy each still
carrying an unqualified completeness claim** — CLO's B1 reasoning applies to every unqualified
instance, not just the most prominent one. Two-part treatment:

| Site | Treatment |
|---|---|
| `privacy-policy.md:519` (§11 Security) | **Full disclosure sentence.** Natural home — this is the Art. 32 TOM section. |
| `privacy-policy.md:298`, `data-protection-disclosure.md:189` + `:276`, `gdpr-policy.md:44` | **Scope-to-live qualifier.** Adopt the preserved Path-2 construction — *"stored **live** workspace git data sits on a LUKS-encrypted volume (encryption at rest)"* — so no instance reads as an unqualified all-copies claim, without repeating the full sentence five times. |
| All six mirrors | Lockstep with their canonical. |
| `article-30-register.md` TOM items | The register's TOM description must match: the volume-layer measure is scoped to the live store, with the retained backstop named as a residual. |

**Source of the wording.** PR #6918 preserved the auditor's Path-2 text verbatim, precisely so
that "if wording is chosen later" it is one edit away. Use it as the base rather than re-drafting:

> *"stored **live** workspace git data sits on a LUKS-encrypted volume (encryption at rest) (a
> superseded pre-cutover plaintext volume is retained only as a rollback backstop pending secure
> teardown)"*
> — `specs/feat-one-shot-6897-superseded-volumes-zot-legal/decision-challenges.md` UC-3, Path 2

**Pinned §11 sentence (privacy-policy, full form).** CLO supplied this plain-language rendering,
date-free per B4. Ship this text unless /work finds a factual defect in it:

> **Encrypted, access-controlled workspace storage:** Stored workspace git data sits on a
> **LUKS-encrypted volume (encryption at rest)** on the Hetzner host that serves the Web Platform,
> and each workspace's git data is **access-controlled per workspace** so that only that
> workspace's members can retrieve it. A copy of workspace git data as it stood on 23 July 2026
> also remains on the older, unencrypted volume it replaced; that copy is kept only as a rollback
> safeguard, is not mounted or served, and is erased once the change is confirmed final.

**Pinned short form** (for `pp:298`, `dpd:189` table cell, `dpd:276`, `gdpr:44`): the preserved
Path-2 construction above — *"stored **live** workspace git data … (a superseded pre-cutover
plaintext volume is retained only as a rollback backstop pending secure teardown)"*.

> **`Ref` anchor.** The preserved Path-2 wording carries none, and §Instrument requires one. Add
> `(Ref #6588)` — subject to the §4c style decision, which must be applied consistently to body
> prose and banner alike. Note the "23 July 2026" above is a **historical fact** (when the copy was
> taken), not a wipe deadline — it does not breach B4. Do not add a *future* date.

**One backstop or two? — verify, do not assume.** The auditor's finding named **two** attached
plaintext volumes: `hcloud_volume.workspaces` (`server.tf:1569`) and `hcloud_volume.git_data`
(`git-data.tf:196`). This plan's D3 reasoning, and AC4, speak of one (singular). Disclosing one of
two would reproduce the partial-correction defect inside the PR that exists to fix partial
corrections.

**Resolution at /work — a factual question with a decisive answer, so answer it rather than
hedging.** `hcloud_volume.workspaces` demonstrably holds user source code (it is the pre-cutover
copy of `/mnt/data`). `hcloud_volume.git_data`'s status is genuinely uncertain: its ledger row calls
it *"the pre-cutover rollback backstop"* for a **git-data LUKS cutover that never happened**,
because the git-data host was never born (#6570 OPEN). A volume attached to a host that does not
exist may hold nothing. **Determine whether `hcloud_volume.git_data` holds any user data before
writing the sentence** — then either name both, or name one and record why the other is empty.
**Do not assert "a volume" (singular) without having checked**; and do not assert it holds data
without evidence, which would be an over-claim in the opposite direction.

### Hard constraint on the wording

**No published wipe date while #6808 is open** (CLO B4). A missed public deadline is a new
over-claim of the same family. Use a condition (*"once the change is confirmed final"*), never
a date. The ledger's `expires_on: 2026-10-22` is an **internal** commitment, not an achieved
schedule, and must not be published as one.

### Recording the challenge

Because this reverses a same-day operator decision, /work MUST append a `DC` entry to
`knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md`
stating: the UC-3 hold, the revisit trigger that fired, the collapsed cost rationale, and the
CLO block. `ship` renders it into the PR body and files it as `action-required`. **Do not
silently apply and do not silently skip.**

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
of published Art. 32 TOM claims plus a new affirmative disclosure. Tier 1 also triggers the
register update, which this PR carries.

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

> **Terminology fix.** An earlier draft said "insert a marker **inside** the July 2 entry" (§4c)
> while AC7 said "**appended**". Those imply different insertion offsets and therefore different
> AC7 outcomes. **"Appended at the end of the segment" is correct**; "inside" is retired.

**Disposition (CLO Q2): ANNOTATE — option (C).**

- **(B) amend in place is BLOCKED** (CLO B3). Rewriting a dated record of what was published
  destroys the Art. 5(2) audit trail that the append-with-history banner exists to provide.
- **(A) leave untouched is insufficient.** The banner is one unbroken line of prose; a
  present-tense sentence (*"now sits on a LUKS-encrypted volume"*) reads as a live claim to a
  user whose eye lands on it, regardless of its position in a changelog.
- **(C) annotate** preserves the record verbatim *and* kills the live-claim reading. Insert a
  bracketed retraction marker **inside** the July 2 entry without altering one word of its
  original text, plus a new head entry. Annotation is additive, so append-only holds.

> **SHARP EDGE — the mirror banners are NOT byte-identical to the canonicals. Do not "sync" them.**
> Measured 2026-07-24:
>
> | Doc | Canonical banner | Mirror banner | Mirror is missing |
> |---|---|---|---|
> | `privacy-policy` | 27,358 chars / **12** entries | 18,409 chars / **9** entries | `May 25`, `May 22`, one `June 15` |
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

**Open style decision for /work** (do not guess — reconcile and record):
`2026-05-12-public-legal-doc-annotations-no-pr-numbers.md` says use section refs (`§N.M`), not
issue numbers, in public legal-doc annotations. But the **immediately preceding** July 16 head
entry uses `Ref #6538`, and body prose at `gdpr-policy.md:44` uses `Ref #6538`. Neither is
CI-enforced. Recommend **matching the adjacent precedent** (`Ref #6588`) for within-banner
consistency, and noting the learning as superseded-in-practice — or follow the learning and
drop the numbers. Pick one, apply it uniformly across all 9 date sites, and say which in the
PR body.

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

### 4f. Ledger coupling — both directions

`scripts/encryption-posture-ledger.json`. Baseline **PASSES**
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

2. **`hcloud_volume.workspaces` row → `disclosed_as: "not-publicly-claimed"`.** This becomes
   **false** the instant Deliverable 3's sentence lands.

   > **SHARP EDGE — flipping it to a real anchor will turn CI RED.** That row's
   > `mechanism` is `plaintext-exception`, so `check_disclosed_as_not_encrypted()` **does** run,
   > and it FAILs when the resolved ±300-char region matches `/LUKS|encrypt/i`. Our disclosure
   > sentence sits *inside the encryption paragraph* — the window will contain "encrypted" with
   > near-certainty. R5 exists to catch **over**-claims; an honest **under**-claim trips it
   > spuriously.

   **Resolution — PRE-DECIDED, do not re-open at /work.** Retain
   `disclosed_as: "not-publicly-claimed"` and record the new published sentence in the row's
   **`exception.justification`** instead. Rationale: the field's semantics are "what public claim
   is made *about this store*"; the new sentence discloses the store's *existence as a residual*,
   it does not claim a safeguard for it — so `not-publicly-claimed` remains defensible, and the
   justification field carries the cross-reference.

   > **A previous draft of this plan offered a second option — "a minimal, tested extension to
   > `check_disclosed_as_not_encrypted`" — and that option is now REMOVED.** Plan-review caught
   > that it authorizes editing `scripts/lint-encryption-posture.py` (a Python linter, plus tests)
   > inside a PR that declares `runtime_deploy_risk: none` and states in writing that its only
   > non-prose file is `legal-doc-shas.ts`. That file is not in Files to Edit. Taking option (ii)
   > would silently change the PR's change-class and falsify three of this plan's own sections.
   > The linter's inability to distinguish an honest under-claim from an over-claim is a **real
   > blind spot** — file it as a one-line issue against **#6893** (which already tracks a sibling
   > class gap: Layer A validates `tracking_issue` *shape* but never open/closed *state*). Do not
   > fix it here.

   Re-run `python3 scripts/lint-encryption-posture.py --repo-sweep` after; expect PASS unchanged.

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
| `knowledge-base/legal/article-30-register.md` | TOM items 13–16 and 17–20 across two PAs |
| `knowledge-base/legal/compliance-posture.md` | `:80` DPA scope; add #3723 Art. 17 gate |
| `knowledge-base/engineering/architecture/nfr-register.md` | `:522` (+ confirm `:521`) |
| `scripts/encryption-posture-ledger.json` | `disclosed_as` **×3** — `stores[0]`, `stores[2]`, `connections[0]` (see §4f) |
| `knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` | DC-1 → RESOLVED |
| `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` | **Create** — the UC record for Deliverable 3 |
| `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` | **Create** — CLO Phase 5.5 attestation |

**Line numbers above are navigational only.** All edits and all ACs bind to **content
anchors** (`cq-cite-content-anchor-not-line-number`); mirror offsets differ per file and drift
as soon as the first edit lands.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md`
  — the Deliverable-3 User-Challenge record. **Written in Phase 1.5, BEFORE the D3 edit is
  applied** (see Phase ordering note), so an abort mid-run cannot leave a same-day operator
  reversal applied with no audit trail.
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
   >    rather than asserting it. Deliverable 3's disclosure becomes moot (nothing to qualify).
   > 3. **AC3 and AC4 are struck**; AC1 widens to include `LUKS` in the retraction anchor.
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

Assert the inventory equals **7 canonical body sites + 3 banner headers, ×2 = 20**. A different
count means the union anchor is wrong or `main` moved — reconcile before editing.

Then apply the **claim-family litmus** per site: after removing X from *"…A, B, and X. X does P,
Q, R."*, ask *what does "does P" now attach to?* If the answer changed, a claim was rewritten
unintentionally.

### Phase 1.5 — Write the audit trail BEFORE applying the change it audits

Create `specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md` with the
Deliverable-3 User-Challenge record **now**, not in Phase 5.

> Deliverable 3's content lands in Phase 2 while an earlier draft filed its DC record in Phase 5.
> For a gate whose stated purpose is *"do not silently apply and do not silently skip"*, an abort
> between those phases leaves a same-day operator reversal applied with **no trail** — the exact
> failure the record exists to prevent. Write it first.

Also create `site-dispositions.md` (16 rows, from the Site Matrix) — it is Phase 2's worklist and
AC2's artifact.

### Phase 2 — Canonical body edits

Deliverables 1 + 2 + 3 across the three canonicals, one claim family at a time (not one file at
a time) so no site is half-edited. Highest-grade item first: the **DPD processor table**
(`:189`) — Art. 13(1)(e) / Art. 30(1)(d) recipients territory, a stronger obligation than the
volunteered TOM paragraph (CLO Risk 1).

### Phase 3 — Mirrors + banner + dates

1. Mirror each canonical edit (hand-maintained; **no generator exists**).
2. Annotate the `Previous: July 2, 2026` entry; prepend the new head entry (all 6 files).
3. Set the new date in **9 places**: 3 canonical body lines, 3 mirror body lines, 3 mirror hero
   `<p>` lines — byte-identical
   (`2026-03-20-eleventy-mirror-dual-date-locations.md`).
4. **Heading-sequence parity:** if any `##`/`###` heading changes in a canonical, mirror it
   exactly. (This PR should not need heading changes — verify it did not introduce any.)

### Phase 4 — Mechanical pins

Ledger `disclosed_as` ×3 (§4f) → re-run the posture linter → **THEN** SHA re-pin ×3 → re-run
`check-tc-document-sha.sh`.

> **Invariant: the SHA pin must be the LAST mutation touching `docs/legal/**`.** §4f instructs
> measuring a ±300-char window and, if unclean, choosing a fallback — a plausible /work move is to
> *reword the disclosure sentence* to obtain a clean window. Doing that after pinning silently
> stales all three SHAs. Ordering the ledger work first removes the hazard; if any
> `docs/legal/**` byte changes after the pin for any reason, **re-run the pin and re-verify**.

### Phase 5 — Registers, DC-1, attestation

Art. 30 register → compliance-posture (`:80` + #3723 gate) → nfr-register → DC-1 RESOLVED →
new `decision-challenges.md` UC entry → CLO writes the audit to `knowledge-base/legal/audits/`.

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
- [ ] **AC3 — LUKS clause re-scoped.** No instance of the LUKS claim is conditioned on a
      multi-host premise; none widens to "all data at rest"; the #6893 verifiability bound holds.
- [ ] **AC4 — plaintext disclosed, at every unqualified site.** (a) The full disclosure sentence
      appears in `privacy-policy.md` §11 + its mirror. (b) **No LUKS claim site anywhere in the 6
      files reads as an unqualified all-copies claim** — each of the other four canonical sites
      (+ mirrors) carries the scope-to-live qualifier. (c) **No published wipe date** in any of
      them (CLO B4) — assert mechanically:
      `grep -nE 'LUKS|encryption at rest' <6 files> | grep -viE '\blive\b|rollback backstop'`
      returns only sites already covered by (a). (d) No date-shaped token appears within the
      disclosure sentence.
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
      > 27,358-character line, so *any* edit renders in `git diff` as a full-line delete + add
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
- [ ] **AC8 — posture linter.** `lint-encryption-posture.py --repo-sweep` PASSES, and **all three**
      bare line-number `disclosed_as` citations are content anchors:
      `stores[0]` → `privacy-policy.md:519`, `stores[2]` (`hcloud_volume.workspaces`) per §4f, and
      **`connections[0]` (`web-platform server -> Supabase Postgres/PostgREST`) →
      `data-protection-disclosure.md:316`**.

      > The third citation was missed by the plan's first draft and independently flagged by two
      > reviewers. It points into a file this PR edits. It is not evaluated today
      > (`cert_verification: "on"` short-circuits the whole `disclosed_as` block in
      > `check_connection`), and it *does* resolve (`grep -c "316"` → 4) — but asserting "there are
      > none" while leaving one is the weaker option. Fix all three; it is three JSON strings.
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
- [ ] **AC11 — challenge recorded.** `specs/feat-one-shot-6588-legal-clause-retraction/decision-challenges.md`
      contains the Deliverable-3 UC entry (UC-3 hold, revisit trigger fired, CLO B1).
- [ ] **AC12 — CLO attestation.** `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`
      exists, written by the CLO agent (not routed to the operator).
- [ ] **AC13 — `Ref #6897`, never `Closes #6897`.** Closing it would orphan the ledger's
      `tracking_issue: "#6897"` rows and the `model.c4:216,220` refs, leaving live exceptions
      pointing at a closed issue.

      > Trimmed at plan-review from a four-part bundle. `Closes #6588`, the other `Ref`s, the Tier
      > classification and the banner-style note are `ship` hygiene, already covered by `ship`'s
      > own PR-body construction — they do not need an AC each. The `Ref`-not-`Closes` clause is
      > the only load-bearing one, because getting it wrong is silent and destructive.
- [ ] **AC14 — live verification.** The Phase-0 verify run id and its discriminating fields are
      pasted into the PR body, dated the day of the PR.

### Post-merge (operator)

*None.* Every step is automatable in-session — `gh workflow run` for verification, `gh issue
view` for state, local test binaries for the gates. There is no vendor dashboard, no
`terraform apply`, no migration, and no credential mint in this PR.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a published privacy policy at soleur.ai that
either (i) still asserts an Art. 32 safeguard that does not exist — cross-host TLS, membership
re-verification on proxied sessions, a dedicated git-data host — or (ii) newly asserts that
their source code is encrypted at rest without disclosing that a full un-encrypted copy of it
sits on an attached, un-wiped disk. Both are the same defect: a security promise the
infrastructure does not keep. For a product whose entire proposition is that a non-technical
founder can trust an autonomous agent with their codebase, a demonstrably false security claim
in the published policy is not a docs bug — it is the trust proposition failing in the one
artifact a prospective user reads *before* deciding to trust it.

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
has yet been misled. This makes the correction **cheap now** and is the strongest argument for
doing it completely rather than partially — the cost of full correction only rises from here.

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

**Skipped — justified.** The Phase-2.9 trigger requires a Files-to-Edit entry under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, or a new
infrastructure surface. This PR's only non-prose file is `apps/web-platform/lib/legal/legal-doc-shas.ts`
— `lib/`, not a listed path — and it introduces no runtime code, no error path, and no failure
mode. There is no new execution surface to instrument.

The relevant *existing* observability is unchanged and remains the gate for the encryption claim
this PR describes: `luks-monitor.sh` (daily; mount→mapper, `cryptsetup status`, `blkid`
crypto_LUKS, Doppler escrow re-test, header UUID) + the `workspaces-luks-verify` dispatch used
in Phase 0. Its alerting path is **known-broken** and tracked at **#6808** — which is a load-bearing
input to Deliverable 3, not a gap this PR introduces or closes.

---

## Encryption Posture

**Skipped as a schema deliverable — justified.** The Phase-2.11 detector fires on
`\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`.
This PR touches none, introduces no persistent store, and creates no cross-component connection.

It nonetheless **edits the ledger** (`disclosed_as` ×2, §4f), which is why the linter is a
Phase-0 baseline and a Phase-4 re-run, and why AC8 is a gate. The measured postures themselves
are unchanged by this PR — it changes only what is *claimed about* them.

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
PR. Folding it in would mix an infra-modeling question into a disclosure correction. **Recorded
here so it is not silently ignored.**

---

## Domain Review

**Domains relevant:** Legal (blocking), Engineering (advisory). Product: **NONE** — zero UI
surface; the mechanical UI-surface override did not fire (no path in Files to Edit matches
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or the UI-surface term list).

### Legal (CLO) — `soleur:legal:clo`

**Status:** reviewed (invoked this session, blocking).

**Assessment.** Ruled on all three referred questions. Q1: affirmative disclosure **required**
(reasoning folded into Deliverable 3). Q2: **annotate** the historical banner entry — reject
in-place amendment. Q3: Art. 30 register corrections ship **in the same PR** — not sequenceable.

**Blocks carried into the ACs:**

| Block | Where enforced |
|---|---|
| B1 — no re-scoped clause (d) without the retained-plaintext sentence | AC4 |
| B2 — no public retraction without the register + `compliance-posture.md:80` corrections | AC9 |
| B3 — no in-place edit of the `Previous: July 2, 2026` wording; annotate only | AC7 |
| B4 — no published wipe date while #6808 is open | AC4 |

**Additional findings folded in:** DPD processor table outranks the TOM prose (Phase 2 ordering);
ledger coupling in both directions (§4f); line-number citations violate
`cq-cite-content-anchor-not-line-number` (§4f, AC8); Art. 17 erasure reachability gates #3723
(§Risks R1); the "7-day soak" is not actually running (Deliverable 3); six files not three (P6).

**Phase 5.5 attestation:** the CLO agent performs the per-artifact review and writes
`knowledge-base/legal/audits/2026-07-counsel-review-6588.md` **at PR time**. It is explicitly
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
diff to be scanned). Findings are folded inline as blocks B1–B4 rather than filed. No new
`compliance/critical` issue is filed — the findings are *cured by this PR*, and the residual
(the plaintext volume's Art. 17 reachability) is recorded against the existing **#3723** and
**#6897** rather than growing the backlog.

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

**Therefore:**

- This PR **executes the held Path-2** and so **substantially satisfies** that bullet.
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
| **R1** | **Art. 17 erasure reachability (the sleeper).** Workspace git data on the retained plaintext volume is outside the account-deletion path; an erasure request today would not reach it. | No live exposure at tenant-zero (#3723 OPEN, zero arms-length subjects) so it does **not** block this PR. It **hard-blocks #3723**: the volume must be wiped, or erasure extended to it, before first arms-length onboarding. Recorded as a gating condition in `compliance-posture.md` (AC9). |
| **R2** | Literal-phrase sweep misses variant phrasings and silently false-passes. | Union-anchor grep (Phase 1) with an asserted count of 20; **never** `grep LUKS`. This already bit once (P7). |
| **R3** | Removing a clause leaves a dependent clause dangling and *stronger* — the exact #6588 defect. | Claim-family litmus per site (Phase 1, AC2); family removed whole. |
| **R4** | Ledger `disclosed_as` flip turns CI RED via the R5 check (§4f). | Measure the ±300-char window **before** choosing; two named fallbacks; AC8 gates. |
| **R5** | Mirror drift — 6 files hand-maintained, no generator. | Edit canonical-then-mirror per claim family, not per file; `legal-doc-consistency.test.ts` (heading + 9-date parity) is the mechanical gate. |
| **R6** | Trusting the 2026-07-23 certification when the live state has since reverted (#6812 precedent: crypto_LUKS held ~27 min then silently reverted). | Phase 0 dispatches a **fresh** verify run; AC14 pastes its id + fields, dated the day of the PR. |
| **R7** | Banner annotation accidentally alters the preserved historical text (Session Error #4: a sync script silently dropped a `Previous:` label). | AC7 asserts insertion-only on that segment and an unchanged-plus-one `Previous:` count. |
| **R8** | Reversing a same-day operator decision without an audit trail. | Deliverable 3 is recorded as a User-Challenge in `decision-challenges.md` (AC11); `ship` renders it into the PR body and files `action-required`. Framed as the HOLD's **own** revisit trigger firing, not as an override. |

---

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Past-tense the three clauses** instead of retracting | (a) and (b) were never true *at any moment* — there was never a cross-host session or cross-host git traffic. Past tense would assert a false historical fact. (c) describes a host that never existed. The banner carries the history instead. |
| **Retract the LUKS clause too**, publishing no encryption claim | Worse for users and worse for posture: the claim is now **true** of the live store. Deleting an earned safeguard claim under-informs data subjects. CLO concurred. |
| **Hold the plaintext disclosure** (status quo per UC-3) | The hold's own revisit trigger has fired (#6808 blocks the soak indefinitely) and its cost rationale collapses because this PR already rewrites those sentences. CLO blocks (B1). |
| **Sequence the Art. 30 register into a follow-up** | Produces a state strictly worse than today — a timestamped public retraction beside an internal register still asserting the retracted TOMs. Art. 30(1)(g) + Art. 5(2). CLO blocks (B2). |
| **Amend the historical banner entry in place** | Destroys the Art. 5(2) audit trail the append-with-history banner exists to provide. CLO blocks (B3). Annotate instead. |
| **Fix the `model.c4` gitDataStore/#6570 tension here** | Mixes an infra-modeling question into a disclosure correction. Belongs to #6570/#6897. Recorded, not folded (§Architecture Decision). |
| **Fix #6808 / run the soak / wipe the plaintext volume** | Explicitly out of scope per the task; separately tracked. This PR discloses the state honestly rather than changing it. |

---

## Open Code-Review Overlap

**None.** All 60 open `code-review`-labelled issues were queried and none references any file in
`## Files to Edit` (checked: the three canonical legal docs, the mirror path prefix,
`legal-doc-shas.ts`, `article-30-register.md`, `compliance-posture.md`,
`encryption-posture-ledger.json`).

---

## Sharp Edges

- **Never `grep LUKS` to find this claim family.** Two of the seven canonical body sites carry it
  with no `LUKS` token. Use the union anchor.
- **`gdpr-policy.md` phrases the git-data-host clause with different word order** (*"a dedicated
  host for per-workspace git data"*). A find-and-replace tuned to the DPD's phrasing misses it.
- **The `disclosed_as` "anchor" is a substring search, not a line lookup.** `resolve_disclosed_as`
  does `text.find(anchor)`, so `"519"` matches the first literal `519` anywhere in the file. It is
  additionally **never evaluated** for a `mechanism: luks` row (early return). Do not assume the
  existing citation is meaningful, and do not assume changing it is safe — the plaintext row's
  citation **is** evaluated, and R5 will FAIL on an honest under-claim.
- **Nine date strings, not three.** Mirrors carry the date twice (hero `<p>` + body).
- **Use the repo-root pinned `./node_modules/.bin/eleventy`**, never `npx` — a cached wrong
  version and a CWD trap have both bitten on this exact surface.
- **Do not trust a background runner's exit code** on the test suite; grep the log for `FAIL`/`× `.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This one is filled.
