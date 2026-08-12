# Phase 0 baseline — measured, not restated (#7349)

Re-derived on the clean tree at merge-base `bab29e6`. The plan's numbers are claims; these are
the measurements. **They agree.**

## 0.1 Gate exit codes (clean tree)

| Gate | Command | Exit |
|---|---|---|
| 1 — scope-block placement | `scripts/lint-legal-scope-block-placement.sh --base origin/main` | 0 (no added lines; nothing to check) |
| 2 — mirror-drift ratchet | `scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` | 0 (9 pairs, within baseline) |
| 3 — T&C document SHA | `apps/web-platform/scripts/check-tc-document-sha.sh` | 0 |

## 0.2 Canonical SHAs — the before-picture for every SHA refresh

```
eb8f4dd62418b7d58d43200bb45171e3113c323fdd44614c1412851aed49028a  acceptable-use-policy.md
3c3d57a9227069bccf2c7f671b389d2f2ac79980481647fb029793a957020cc8  cookie-policy.md
d41147d94cf53c9340cdf39d751b91b4140991ddbab092451308a1398eb00826  corporate-cla.md
6864fac371a4083b9ef3ba4fd959692a74de78c56332e1302d2267a12262b844  data-protection-disclosure.md
f02375aadf0b0aeb6f60718bbca3f75135bb6a949b2cded1bbfabbf704b117c2  disclaimer.md
56f8021cc0fabf3806131d3ea4370f18189b964b0f8bbda54bd45dd3b43c5ed0  gdpr-policy.md
8d773e4331fd82e4b27a506eac2f968ad319adcef624d8f6115c0b71deb5e538  individual-cla.md
dc2df0ce37ad1bbec032b8a79ebba3a81152ef342121bacb2789976dab8c4495  privacy-policy.md
f3640a38ea9805667456336ea2be8cf9606ee61a097664ad2770e3888893a5cf  terms-and-conditions.md
```

## 0.3 DPD §2.3 item sets — matches the plan exactly

Canonical **29**, mirror **23**. Canonical-only: `(ad) (p) (w) (x) (y) (z)`. Mirror-only: none.

## 0.4 Dangling `2.3(x)` cross-references — matches the plan exactly

Canonical surface: **0**. Mirror surface: `(ad)`×1, `(p)`×2, `(w)`×3, `(x)`×3, `(y)`×1.

## 0.5 Per-pair drift — total 220, matching the plan

| Pair | Total | canonical-only `<` | mirror-only `>` |
|---|---|---|---|
| acceptable-use-policy | 18 | 11 | 7 |
| cookie-policy | 4 | 2 | 2 |
| corporate-cla | 12 | 7 | 5 |
| data-protection-disclosure | 56 | 44 | 12 |
| disclaimer | 2 | 1 | 1 |
| gdpr-policy | 63 | 44 | 19 |
| individual-cla | 7 | 5 | 2 |
| privacy-policy | 58 | 44 | 14 |
| terms-and-conditions | **0** | 0 | 0 |
| **total** | **220** | | |

### Instrument error worth recording

A first pass measured **309** and showed `terms-and-conditions` at **40**, which would have
falsified the plan's "T&C mirror is at zero drift" premise and its 220 total. The cause was
mine, not the plan's: the reconstruction sourced `scripts/lib/legal-normalise.sh` and then
**overrode** its `collapse()` with a passthrough, so cross-normalised link forms
(`(privacy-policy.md)` vs `(/legal/privacy-policy/)`) counted as drift.

This is why task 7.1 says to run every gate by its own invocation rather than a reconstruction
of its input set. Had the reconstruction been trusted, the plan would have been "corrected" to
match a broken instrument, and the T&C lockstep constraint — the thing keeping Phase 5 safe —
would have been discarded.

## 0.5 (CPO C3) Character of the deferred set

`privacy-policy`'s 44 canonical-only lines are **not** the "pure copy exercise orthogonal to the
contradictions" the plan's rejected-alternatives section assumed. **CPO C3's condition FIRED.**
The CLO re-derived every count independently and ruled; the binding disposition is Phase 3c.

### Corrected — two first-draft claims were OVERSTATED

This section's first draft claimed the Chapter V transfer disclosures and the Art. 17
community-digest carve-out were absent from the published mirror. **Both are present.** They
are recorded here rather than deleted, because acting on either would have been wasted or
harmful work:

- **Chapter V transfers are published.** `EU-US Data Privacy Framework` (canon 7 / mirror 6),
  `Microsoft Ireland Operations Ltd` (6/5), `EU Data Boundary` (5/3), `K-bis` (12/9). The
  mirror's §5.12 carries the DPF / SCC Module 2 storage-location disclosure verbatim. Only the
  *consolidated restatement* in §10 is missing — duplicative disclosure, not first-instance
  omission. **Art. 13(1)(f) is satisfied on the published surface.**
- **The Art. 17 community-digest carve-out is published**, inlined inside a 2,423-character
  merged paragraph at mirror line 491 (canonical breaks it out standalone at line 507). Same
  for the LinkedIn-published carve-out. Structural drift, not omission.

### The limbs that actually decide it

- **Limb A — Art. 13(1)(c).** The LinkedIn Company Page **dual-basis paragraph is wholly
  absent** (`dual basis`: canon 1 / mirror 0). A lawful-basis allocation recorded canonically
  and never published is the same defect, in the same article, as `gdpr-policy`'s Art. 6(1)
  bullets. C3 is met on this limb alone.
- **Limb B — Art. 13(1)(a)–(c), strictly worse than `gdpr-policy`.** Published §4.7 discloses
  **6 of 12** data-category bullets. Six processing activities are absent from the published
  notice entirely — `team_names`, Concierge turn summaries, `message_attachments` (and the
  `chat-attachments/` bucket), workspace logo, `audit_byok_use`, `beta_contacts` — each at zero
  occurrences in the mirror. A seventh, `statutory_repin_send`, is also absent, and the
  surviving Workspace-data bullet is truncated. `gdpr-policy` omits the *basis* for processing
  that is disclosed; this omits the *processing*. An unstated basis is arguably inferable from a
  disclosed purpose; an undisclosed activity cannot be — the data subject has no way to know it
  happens.
- **Limb C — Art. 12(2)/15/20.** `Right of access / portability` (1/0), `Download my data`
  (1/0), the Art. 15(4) rights-of-others paragraph (1/0). The published notice enumerates rights
  while withholding the route by which they are exercised.

Also: the mirror publishes the share-link Art. 6(1)(f) basis stripped of the legitimate
interests pursued, which Art. 13(1)(d) requires be stated; and the Resend disclosure omits three
recipient/purpose classes.

These are gate 2's own three named counts. **The gate has been printing that admission on every
CI run.**

### Why this could not be deferred

The T&C **incorporates the Privacy Policy by reference** into the agreement (`terms-and-conditions.md`
lines 149, 232, 392) and at line 232 routes the user to the exact defective section. This PR bumps
`TC_VERSION` 2.4.0 → 2.5.0, forcing every web-platform principal through `/accept-terms` — an
affirmative act acknowledging processing "as described in the Privacy Policy". Deferring to
2026-09-30 would re-solicit that acknowledgment against a notice this repository has by then
measured and committed as omitting six processing categories, converting a passively inherited
defect into an affirmative one and inverting the Art. 83(2)(c)/(k) mitigating-action posture the
drift freeze rests on. The ratchet would make the omission permanent in the interim.

## 0.6 Verdict

Every plan number re-derived here agrees with the plan. No plan correction was required.
