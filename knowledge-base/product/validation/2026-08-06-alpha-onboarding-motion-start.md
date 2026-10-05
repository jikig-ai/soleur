---
title: Alpha Onboarding Motion — Start of Active User Onboarding
date: 2026-08-06
status: active
type: validation-milestone
scope: Soleur Phase 4 (Validate + Scale), roadmap rows 4.1–4.5
tester: Skouer (https://github.com/2my8r9ry2t-wq/Skouer)
origin: 2026-08-06-alpha-onboarding-motion-brainstorm.md
issue: "#7329"
---

# Alpha Onboarding Motion — Start

**Soleur moved from pre-launch to active user onboarding on 2026-08-06.** This record marks that
transition and registers the first alpha tester against the existing Phase 4 validation protocol.

`Beta users` on the roadmap moves **0 → 1**. It is the first non-zero value in the product's
history.

## What this is not

This is not a new programme. Roadmap rows 4.1–4.5 already define the validation motion as a
sequenced five-stage protocol with open P1 issues; this record *advances* that protocol rather
than creating a parallel structure beside it.

| Roadmap row | Issue | Stage | State on 2026-08-06 |
|---|---|---|---|
| 4.1 | [#1439](https://github.com/jikig-ai/soleur/issues/1439) | Recruit 10 solo founders | **Underway — 1 of 10 recorded** |
| 4.2 | [#1440](https://github.com/jikig-ai/soleur/issues/1440) | Problem interviews (*no demo*) | Not run for this tester — see Protocol deviation |
| 4.3 | [#1441](https://github.com/jikig-ai/soleur/issues/1441) | Guided onboarding, top 5 | **This session** |
| 4.4 | [#1442](https://github.com/jikig-ai/soleur/issues/1442) | 2-week unassisted usage tracking | Pending — see Measurability |
| 4.5 | [#1443](https://github.com/jikig-ai/soleur/issues/1443) | Exit interviews + willingness-to-pay | Pending |

## Alpha tester #1 — Skouer

| | |
|---|---|
| **Repository** | `https://github.com/2my8r9ry2t-wq/Skouer` (private) |
| **Product** | A domain-specific reference database; the sector descriptor is held in the Article 30(2) register rather than restated here |
| **Stack** | Postgres + PostgREST on Clever Cloud; static front-end; Python/JS tooling |
| **Test surface** | **Self-hosted Soleur CLI plugin.** The hosted web platform is deferred until it is serving reliably again |
| **Prior Claude Code use** | **Yes** — the repository carries `CLAUDE.md`, `.agents/`, and a `skills/` tree (geocoder, press-reader, press-review-mentions) |

No personal data about the founder appears in this record or anywhere else in git. See
[Data-handling boundary](#data-handling-boundary).

## Recruitment mix — tracked from tester #1

#1439 carries a CMO-review constraint: **at least 3 of 10 founders must NOT be current Claude Code
users.** Skouer's repository shows established Claude Code usage, so this tester consumes one of
the seven Claude-Code-user slots.

| | Claude Code users | Non-Claude-Code users |
|---|---|---|
| **Recorded** | 1 | 0 |
| **Ceiling / floor** | ≤ 7 | ≥ 3 |

Tracking this from tester #1 is deliberate: the constraint is only checkable once recruitment
completes, and by then a violation is unfixable. The runbook places the enforcement check before
recruiting tester #8 — the last point at which ≥3 non-Claude-Code users is still satisfiable.

## Protocol deviation — #1440 did not precede #1441

The protocol sequences #1440 (problem interviews, explicitly *no demo*) before #1441 (guided
onboarding). For this tester the order was not followed: today's session is guided onboarding
without a preceding problem interview.

**Why:** the hosted web platform is currently degraded (Concierge non-functional, deploy issues in
flight), so the operator ran onboarding personally through the CLI — with a second purpose of
dogfooding the onboarding experience itself in order to improve it for testers 2–10.

**Consequence to carry forward:** no uncontaminated problem-discovery signal exists for Skouer.
Any #1440 finding attributed to this tester would be post-exposure and must not be pooled with
clean discovery data from testers who receive the protocol in order.

## Measurability — #1442 is only partially observable on this surface

#1442 tracks returns, knowledge-base growth, and non-engineering agent usage. On a **self-hosted
CLI plugin there is no server-side telemetry**, so most of that is not measurable.

| #1442 metric | Measurable on CLI? | How |
|---|---|---|
| Knowledge-base growth | **Yes** | Git history on the tester's own `knowledge-base/` tree — the operator holds collaborator access |
| Returns / session frequency | No | No server-side session record |
| Non-engineering agent usage | No | No server-side agent-invocation record |

**This caveat must travel with any #1442 finding from the CLI era.** CLI-era data and future
platform-era data are not equivalent and must not be compared as though they were.

## Data-handling boundary

**No third-party personal data is committed to git — here or anywhere in this repository.** The
tester is identified only by company name and repository URL.

The beta-CRM LIA establishes why: git history is permanent, so committed third-party personal data
would be an **Art. 17 erasure impossibility**. The database boundary is load-bearing, not
incidental. Article 30 PA-32 reaches the same conclusion independently for a different activity,
citing this same LIA.

Named contact details belong in the **beta-CRM database only** (`beta_contacts`,
`interview_notes`), which is owner-private under RLS, swept at 24 months, and erasable per contact
via the `crm_erase_contact` RPC.

**Transparency posture.** Art. 14 governs the CRM record: the LIA scopes it to data "not obtained
from the data subject via a form they submitted", which covers operator-authored conversation
notes even for a tester who holds a platform account. The notice is a short line in the alpha
welcome message — not a signature, not an in-person step. Art. 13 governs the separate
platform-account dataset and is satisfied by the existing `accept-terms` privacy-policy flow if
and when this tester signs up.

## Open gate — the beta-CRM contact record

The contact record for this tester **has not been created yet**, and this is an architectural gate
rather than an oversight.

Migration `126_beta_crm.sql` REVOKEs `INSERT`/`UPDATE`/`DELETE` on the CRM tables from `PUBLIC`,
`anon`, `authenticated` **and `service_role`**; per ADR-102 no service-role write pipeline exists
by design. Writes go only through `auth.uid()`-pinned `SECURITY DEFINER` RPCs as the authenticated
owner in the web platform — the surface that is currently degraded. Automating this from the CLI
would mean adding precisely the bypass the architecture exists to prevent.

**Unblock condition:** the operator performs the contact upsert as authenticated owner once the
web platform is serving again.

**Entry stage when it lands:** `evaluating` (probability 0.5) — past `qualified` (recruited and
actively onboarding), short of `committed` (no agreement, no willingness-to-pay signal).
`beta_contact_stage_transitions` is append-only, so the entry stage cannot be silently corrected
afterwards and must be set deliberately.

## Agreement gap — RESOLVED 2026-08-06, and the answer was not the one expected

Was tracked as an open gap in **[#7331](https://github.com/jikig-ai/soleur/issues/7331)**. Both
exposures are now determined:
`knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md`.

1. **No alpha-tester terms — CLOSED.** The defect was never that terms did not exist: the T&Cs bind
   on **installing**, and §10.2 already disclaims availability and warranty. The defect was
   **notice** — the plugin README surfaced only the BSL licence, so a CLI installer was bound by
   terms never shown. Fixed by a Terms section in `plugins/soleur/README.md` and a terms paragraph
   in the onboarding runbook's welcome message.

2. **Processor relationship — CONFIRMED, but for a different reason than this record predicted, and
   it had already happened.** The prediction was that exposure begins when agents operate on the
   tester's *venture database*. That is not what triggered it. The **2026-08-06 guided-onboarding
   session itself** ran on the operator's machine **under a Jikigai Anthropic key** — which makes
   Jikigai an Art. 28 processor for the instructed limb of that run, retroactively, with no
   instrument in place. Recorded at P-1 in `knowledge-base/legal/article-30-2-register.md`.

   The record previously read: *"Exposure (2) begins at first substantive agent run against their
   data, not at onboarding."* That was **wrong, and wrong in the direction that mattered** —
   onboarding *was* the run. It is quoted here, and struck, rather than silently deleted, because
   the mistake is the finding. (An earlier draft of this paragraph claimed the sentence was "left
   standing below" while the same edit removed it; that claim is withdrawn.)

3. **A third exposure this record did not anticipate.** Operator collaborator access to the
   tester's private repository, read for Jikigai's own #1442 metrics, makes Jikigai a **controller**
   under Art. 4(7) — a posture a DPA cannot cure. Recorded at PA-35 with an LIA. The operator has
   elected to retain and paper it; the LIA recommends re-deriving the metric to non-personal
   aggregates instead, which is free.

**What the session actually touched** (reconstructed, not assumed): no venture-database records were
processed. Working material was schema, configuration, tests and documentation. A fixtures file
containing company-officer records was present in the tree; no evidence it was read, and a read
cannot be excluded — see
`knowledge-base/project/specs/feat-one-shot-7331-alpha-tester-terms-dpa/session-scope-reconstruction.md`.

**Forward control:** no further Jikigai-keyed runs against tester content until an Art. 28(3)
instrument exists — the operator uses the tester's machine and key, or does not run.

## Repeatability

The per-tester process is written down at
`knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`. Skouer is tester #1
of a target 10; the process repeats nine more times, and writing it while the first run was live
was the cheapest and most accurate moment to capture it.
