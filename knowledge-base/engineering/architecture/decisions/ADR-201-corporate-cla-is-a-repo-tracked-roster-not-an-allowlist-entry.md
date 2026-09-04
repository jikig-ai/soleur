---
title: "ADR-201 — The Corporate CLA is recorded as a repo-tracked roster read at the base ref, not as an allowlist entry and not as a third required check"
status: adopting
date: 2026-09-04
tags: [cla, legal, ci, gdpr, evidence, contributor-licensing]
related_adrs: [ADR-200]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md
---

# ADR-201 — The Corporate CLA is a repo-tracked roster, not an allowlist entry

## Status

**Adopting**, 2026-09-04 (#3210). The roster, its schema, its guards and the operator
affordance ship now. The `cla-evidence.yml` roster-verification step and the R2 write are
deferred (see *Two scope reversals* and *Consequences*), so this ADR describes a target state
that is partly built. It supersedes no ADR: an ADR-corpus sweep for
`contributor-license|cla-assistant|corporate-cla|cla-signatures|contributor-assistant` returned
zero hits, so this is the first architectural record of contributor licensing.

The legal siting decision this rests on is not made here. It is the CLO ruling at
`knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`,
which governs.

## The problem

`docs/legal/corporate-cla.md` was published and binding, and no code path recorded a Corporate
CLA anywhere. Recognising a corporate contributor meant editing the `allowlist:` string inside
`.github/workflows/cla.yml`.

That has two costs, and the second one is the reason this ADR exists.

**It records a falsehood in a permanent archive.** The allowlist is the upstream action's
maintainer-class *bypass* — "this account may merge without a CLA". A contributor whose employer
has executed a real IP grant is the opposite of a bypass. Writing them into that list files a
misstatement about the basis on which their code entered the project, into a ten-year write-once
evidence archive.

**It is a single point of failure for the whole repository.** `build-bypass.ts` reads that file
with `readFileSync` and a single regex and calls `process.exit(1)` on no-match, inside the
**required** `cla-evidence` check. One malformed hand-edit took every open pull request in the
repository offline and needed an admin bypass to escape (#7597, and the CLO ruling at
`knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`). Making
that string the routine mechanism for onboarding corporate contributors puts a repository-wide
outage on the critical path of every new employer.

## The decision

**1. The record is a git-tracked artifact.** `apps/cla-evidence/roster/ccla-roster.json` is a
public coverage map; `knowledge-base/legal/ccla-register.md` is the operator-facing index. The
executed instrument is held off-repo. The mechanism is not invented here — Corporate CLA §4(c)
and §5 specify a maintainer-held roster of GitHub usernames, so the instrument decides the shape
and this ADR records that we implemented what we signed.

**2. It is not an allowlist entry.** `cla.yml`'s `allowlist:` value and format are untouched, and
a guard now pins the regex against the real file so the #7597 class cannot recur silently.

**3. It is not a third required check.** Folded into the existing `cla-evidence` job. Adding a
content-scoped required check costs a **six**-artifact lockstep — `infra/github/ruleset-cla-required.tf`,
`scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`,
`scripts/create-cla-required-ruleset.sh`, `scripts/required-checks.txt`,
`plugins/soleur/test/required-checks-canonical-parity.test.sh` (Test 7) and
`.github/actions/bot-pr-with-synthetic-checks/action.yml` — and additionally trips the #6049
auto-fabrication guard, which fabricates a green for every bot PR unless reproduced in that
action's Phase-4 ceiling.

**4. Additive evidence must not gate.** This is the reusable half, and it is stated explicitly
because an earlier draft of the plan wrote the **inverse** into the one artifact that outlives the
PR. The roster path records and annotates; it must never fail a pull request for the *absence* of
coverage. The fail-closed ICLA gate it sits beside is untouched. A contributor's merge is decided
by whether they signed the Individual CLA, never by whether the maintainer has finished the
corporate paperwork. The generalisation is registered as **AP-025**.

**5. Reads are at the base ref.** `cla-evidence.yml` checks out `github.event.pull_request.base.sha`
and never the PR head. This is what stops a contributor authorizing themselves by editing the
roster in the same pull request the roster authorizes. It is **not new machinery** — the checkout
and its comment already existed and were already reviewed; this ADR records it as a load-bearing
invariant so a future edit to that `ref:` is legible as the security change it would be.

**6. Entry is contribution-triggered.** An account enters the roster only at or after that person
has signed the Individual CLA on a pull request here. This is a *legal* requirement adopted as an
*architectural* one, because it is the only form in which it survives: enforced at the write path
(`ccla-add.sh` refuses) and again in CI (a test cross-checks the tracked roster against
`origin/cla-signatures:signatures/cla.json`). Both sites, deliberately — CI alone catches the
violation only after the association is committed, and the surface is a public repository from
which nothing can be erased.

## What the roster may not carry

No name, title, email address or postal address — **permanently, not pending a decision**. The
schema is `.strict()`, so the prohibition is enforced by construction rather than by a denylist
that a fifth key name walks through. Identity rests in the executed instrument, off-repo.

This follows the CLO ruling's option **B1-c**, with two amendments: custody is the **encrypted
operator drive** rather than a mailbox (a mailbox is transport, has no retention discipline and no
access record, and an Art. 15 or 17 request against it is unanswerable), and an organisation's
**legal name is not unconditionally non-personal** — for a sole trader it *is* a natural person's
name, and such a counterparty is published under an opaque record reference alone.

The employer↔account association that *is* published is personal data under Art. 4(1), processed
under the Art. 6(1)(f) balancing test recorded at `docs/legal/gdpr-policy.md` §3.4. The earlier
framing — that a coverage map of public logins contains no personal data — was a category error,
and the corpus already contradicted it: Corporate CLA §4(e) classes GitHub usernames as personal
information.

## Two scope reversals, recorded because they reverse earlier decisions

**The `cla-evidence.yml` roster-verification step is deferred**, reversing CTO Key Decision 5 and
spec FR4. Measured rather than argued: the step is fail-open, writes no evidence record, and its
receipt-comment output is gated on an `issue_comment` sign comment that a *returning* contributor
never posts — so its only durable output today is a `::notice::` in a 90-day log, while the
temporal-record property it was meant to buy is bought permanently and for free by the roster
file's own git history.

**The operator affordance is a script, not a skill**, reversing spec FR6. The two operator-facing
CLA affordances that already exist — `gdpr-override.sh` and `inspect-evidence.sh` — are both
scripts in `apps/cla-evidence/scripts/` with runbook sections, and a `git grep` for either across
`plugins/soleur/skills/` returns zero. A skill would also have cost a bump against a measured
2400/2400 zero-headroom skill-description budget shared by 96 skills.

## Alternatives considered

| Alternative | Why not |
|---|---|
| **Record the CCLA in the existing `soleur-cla-evidence` R2 write-once store** | **The central alternative** — the repository already operates a purpose-built CLA evidence bucket with a 10-year Object Lock, `inspect-evidence.sh` retrieval and `gdpr-override.sh` controlled erasure, so "why a git JSON file rather than the store built for exactly this?" is the first question a future reader asks. Rejected **for now and not on the merits**: a CCLA arrives as an inbound email body, which is a third and worse Art. 9 ingress surface behind a one-way lock rule, and §4(c) capture is structurally non-signer. Blocked on #7813 + #7814 + #7816. The roster's `schema_version` and its two hashes are the seam it plugs into when those close. |
| Widen `cla.yml`'s `allowlist:` | Files a permanent, non-erasable "maintainer-class bypass" misstatement about a contributor who holds a real grant, and puts the #7597 repository-wide outage on the onboarding path of every new employer |
| A third required status check | Six-artifact lockstep plus the #6049 auto-fabrication ceiling, for a content-scoped gate |
| A PR-time corporate sign phrase | Requires amending a signed legal instrument before it is legally coherent |
| A hosted `soleur.ai` corporate signing flow | Same amendment problem, plus a new authenticated surface and a new PII store, to serve n=1 |
| Fork or replace `contributor-assistant/github-action` | No org concept at the pinned SHA — confirmed from two sides, the action's inputs and the ledger's own flat `signedContributors` schema. Four surfaces encode its semantics (`build-bypass.ts`, `sentinel-pr.sh`, `fix-issue/SKILL.md`'s author-email pin, `.claude/hooks/cla-signed-author-gate.sh`) |
| Adopt **EasyCLA** | A Linux Foundation platform migration — LF SSO, DocuSign, Python + Go services — to serve one organisation |
| Adopt **cla-assistant** (SAP) | Closed the corporate-CLA request **wontfix** (#414) and dormant since October 2023 |
| Adopt **microsoft/ContributorLicenseAgreement** | Its per-company `approvedUsers.csv` is **independent convergence on this same design** — evidence the shape is right, and simultaneously the argument against adopting it, since the tool wrapping it was frozen in June 2024 |
| A separate **private** repository for the register (B1-b) | Refused by the CLO at n=1: it buys a repository, an access policy and a second drift surface to protect a field set that under B1-c need not be in version control at all. Re-evaluate above ten organisations, or at the first jointly-auditable instrument |
| A **gitignored** private register (B1-a) | Privacy by `.gitignore` discipline is not privacy by construction — it has failed twice here already — and it destroys the content-addressed integrity the tracked record exists to provide |

## Consequences

- The roster is world-readable and **cannot be erased**. Every downstream document says so, and
  `removed_at` is named a *withdrawal-of-designation marker* rather than a tombstone — that word
  already denotes something erasure-shaped here (`tombstones/<sha>.deleted.json` on the R2 path),
  and reusing it is how a false disclosure about erasure reaches a data subject.
- A first corporate pull request may be annotated as not-yet-covered while the roster catches up.
  That is a latency on an annotation, not a gate on a merge; Corporate CLA §1 covers future
  contributions with no cut-off.
- The R2 write, its `cla-evidence.yml` step, that step's guard and AC4 are deferred together. A
  guard for a mechanism that does not ship is vacuity, so it is not written yet.
- `docs/legal/corporate-cla.md` and `docs/legal/individual-cla.md` are **not** enrolled in
  `BODY_EQUIVALENCE_DOCS`. Measured drift against the canonical normaliser is non-zero on both,
  and the code's own enrolment rule is to enrol only after a reported zero.

## Related

- CLO ruling — `knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`
- #7597 outage ruling — `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`
- Art. 30 register PA-7 — `knowledge-base/legal/article-30-register.md`
- Runbook §10 — `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`
- Principle **AP-025** — `knowledge-base/engineering/architecture/principles-register.md`
