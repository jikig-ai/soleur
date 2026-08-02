---
title: "Site dispositions — #6588 legal half (AC2 artifact)"
issue: 6588
date: 2026-07-24
---

# Site dispositions — 16 body sites (8 canonical + 8 mirror)

AC2's artifact. Every site in the plan's **Site Matrix** gets an explicit per-claim disposition,
so a reviewer can check the diff against this table rather than re-deriving the inventory.

**Claim key:** **(a)** cross-host traffic TLS-encrypted in transit · **(b)** membership
re-verified on proxied / cross-host sessions · **(c)** the dedicated per-workspace git-data host ·
**web-2** the second-web-host present-tense claim · **premise** the "spans / across more than one
host" conditional · **LUKS** the encryption-at-rest claim.

Line numbers are **navigational only** (they shift as edits land); the dispositions bind to
content.

## Canonical — `docs/legal/`

| # | Site | (a) | (b) | (c) | web-2 | premise | LUKS | Disposition |
|---|---|---|---|---|---|---|---|---|
| 1 | `privacy-policy.md:298` | Y | Y | Y | Y | – | **Y** | Retract (a)(b)(c) + web-2. **Keep LUKS**, re-anchored to "that Helsinki host" (antecedent at `:297`, which names `hel1`). Bullet relabelled *Multi-host* → *Workspace storage encryption (corrected July 24, 2026)*. Per-workspace access-control retained (true of the live platform). |
| 2 | `privacy-policy.md:489` | – | – | – | Y | Y | – | Retract premise + web-2. **Add no LUKS claim** — this site publishes none, and adding one inside a retraction PR would be the inverse defect. "data centres" → "a Hetzner data centre". |
| 3 | `privacy-policy.md:519` (§11 Security) | Y | Y | Y | – | Y | **Y** | Drop the *"Where the Web Platform spans more than one Hetzner host in the EU region"* conditional; **keep LUKS unconditioned** on the live single host, EU-region scoping retained (the enforced invariant per `variables.tf:113`). Retract (a)(b). Access-control clause retained. **This is the ledger `stores[0]` content-anchor target.** |
| 4 | `data-protection-disclosure.md:189` (processor table) | Y | Y | Y | Y | – | **Y** | Highest-grade site (Art. 13(1)(e) / Art. 30(1)(d) recipients). Retract (a)(b)(c) + web-2 from the Processing-Activity cell; **keep LUKS** in the Data-Processed cell, re-anchored to "the serving host". Also drops the never-built per-workspace git-data *fetch authorization* claim (register item 15). |
| 5 | `data-protection-disclosure.md:276` | Y | – | Y | Y | Y | **Y** | Retract (a)(c) + web-2, drop premise. **Keep LUKS**, re-anchored ("on that host"). Matrix-confirmed to carry LUKS (a plan-review agent had asserted it does not). |
| 6 | `data-protection-disclosure.md:318` limb (e) | – | – | – | – | – | – | **Carries none of the union-anchor tokens** — found by separate measurement, not by the Phase-1 grep. Corrects the Hetzner two-DC transfer claim *"Helsinki, Finland and Falkenstein, Germany"* → Helsinki only. Verified against infra: `var.location`, `var.registry_location`, `grok_dogfood_location` and `web_hosts` all resolve to `hel1`. |
| 7 | `gdpr-policy.md:44` | Y | Y | Y | Y | Y | **Y** | **Word-order trap:** phrases (c) as *"a dedicated host for per-workspace git data"* — a find-and-replace tuned to the DPD's wording misses it. Retract (a)(b)(c) + web-2, drop premise (including the italic *"ran across more than one host"* retrospective, which carries an anchor token). **Keep LUKS** re-anchored. `Ref #6538` → `Ref #6588`, date → July 24, 2026. |
| 8 | `gdpr-policy.md:318` | – | – | – | Y | Y | – | Retract premise + web-2. **Add no LUKS claim** — matrix-corrected; this plan's own first draft wrongly asserted this site carries LUKS. |

## Mirror — `plugins/soleur/docs/pages/legal/`

Each mirror line was verified **byte-identical** to its canonical before editing, and received
the identical replacement. Mirror **banners are NOT synced** to canonical (they carry a
legitimately truncated history — 12/13/11 vs 18/17/17 `Previous:` entries); they are edited in
place only.

| # | Site | Mirrors canonical | Disposition |
|---|---|---|---|
| 9 | `privacy-policy.md:297` | #1 | Identical replacement. Antecedent for "that Helsinki host" verified present at mirror `:296`. |
| 10 | `privacy-policy.md:475` | #2 | Identical replacement. |
| 11 | `privacy-policy.md:500` | #3 | Identical replacement. |
| 12 | `data-protection-disclosure.md:186` | #4 | Identical replacement. |
| 13 | `data-protection-disclosure.md:261` | #5 | Identical replacement. |
| 14 | `data-protection-disclosure.md:301` | #6 | Identical replacement. |
| 15 | `gdpr-policy.md:53` | #7 | Identical replacement. |
| 16 | `gdpr-policy.md:306` | #8 | Identical replacement. |

## Claim-family litmus, applied

The governing rule (from the learning #6588 produced): **a claim family is removed whole or not
at all — never just its head.** After removing X from *"…A, B, and X. X does P, Q, R."*, ask
*what does "does P" now attach to?*

- Sites 1, 4: the LUKS sentence sat **after** the multi-host/git-data-host enumeration with no
  conditional of its own. Deleting the enumeration alone would have re-pointed it at whatever
  remained — the exact 2026-07-16 defect that created #6588. Both were **re-anchored explicitly**
  to the live serving host, not merely left in place.
- Sites 3, 5, 7: the LUKS claim hung on an explicit *"where … more than one host"* premise.
  Dropping the premise without re-anchoring would have left it grammatically unmoored; each was
  rewritten to stand unconditioned on the live topology.
- Sites 2, 8: carry the premise but **no** LUKS. "Re-scoping the LUKS clause" here would have
  meant **adding** a claim to documents that publish none — the inverse defect. Neither gained
  one.

## Not swept — deliberate carve-out

`privacy-policy.md:379` / mirror `:378` and `data-protection-disclosure.md:103` / mirror `:112`
name **Better Stack's** *"Hetzner Falkenstein cluster `eu-fsn-3`"*. That is a **different
processor**, its region genuinely is Falkenstein, and the claim is **true**. Scrubbing it would
delete an accurate sub-processor disclosure and later turn `validate-vector-config.yml` red (it
greps that source-ID/cluster string). Excluded from every `Falkenstein` sweep.

## Site-count reconciliation (plan correction)

The plan's Phase 1 asserts the union anchor returns **22**. Measured: it returns **20**
(= (7 body + 3 banner) × 2). The 8th canonical body site — `data-protection-disclosure.md:318`
and its mirror `:301` — carries **zero** union-anchor tokens, exactly as the Site Matrix itself
states, so the grep structurally cannot find it. **20 + 2 = 22 sites.** The matrix is correct;
only the assertion's phrasing conflated "the grep returns 22" with "the matrix has 22 rows".
This is a plan arithmetic slip, **not** a "`main` moved" signal — verified before proceeding.
