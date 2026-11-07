---
title: Exposure answers are unknown-by-default and session-only in a public repo
status: accepted
date: 2026-11-07
issue: 12006
related_adrs: [ADR-281, ADR-197, ADR-192, ADR-286, ADR-287, ADR-236, ADR-214, ADR-280, ADR-179]
---

# ADR-322: Exposure answers are unknown-by-default and session-only in a public repo

Refs: #12006, #12007. Related: ADR-281 (image scan, public-repo constraint), ADR-197 and ADR-192 (absence of evidence on a log
surface), ADR-286 (Vector admission), ADR-287 (untrusted content), ADR-236 (human-only skills), ADR-214, ADR-280 (credentials on
stdin), ADR-179 (bare plugin-root anchor). Plan: `knowledge-base/project/plans/2026-11-07-feat-cve-exposure-skill-plan.md`.

## Context

`plugins/soleur/skills/cve-exposure/` answers "are we subject to CVE-X" for Soleur's own infrastructure, read-only, from Terraform
and Better Stack telemetry, never SSH. The question has two failure modes that a plain checklist does not prevent:

1. **A silent surface reads as a clean surface.** A host that stopped shipping logs, a stale marker, a query error or a component
   with no mapping all return "nothing found". Reading that as "not affected" is the error ADR-197 and ADR-192 already name for
   log surfaces; here the cost is a false all-clear on a security question.
2. **This repository is public.** An exposure table that lists exact component versions, host names or addresses next to a CVE is
   a targeting list (the constraint ADR-281 records for the image scan). Issues, commit messages, PR titles, review comments and CI
   logs are all publicly readable. The skill also reads advisory text from the network, which is attacker-influenced input.

ADR-281 left one item open: there is no private durable place for per-finding dispositions. That is still true, and this ADR does
not close it.

## Considered Options

- **A. Unknown-by-default, session-only table, one-status chokepoint for durable artifacts (chosen).** Pros: no exact exposure data
  leaves the operator session; the only public write is fixed and enumerable. Cons: the answer is not durable, so a later session
  repeats the read.
- **B. A durable private exposure register (rejected).** No private durable store exists for this repo; ADR-281 records the same gap.
  Building one is a separate decision and would hold the most sensitive data the company has.
- **C. Exact versions in gap issues after redaction (rejected).** Redaction of a free-text body is a second uncontrolled path, and
  a public issue naming a component version and a CVE is a targeting list whatever else is removed.
- **D. Mark the skill `disable-model-invocation` to save description budget (rejected).** The Skill tool refuses such skills, so
  `/go` could not route to it (ADR-236). The skill pays the description-budget cost like the other customer-session skills
  (precedent: `invoice`, `operator-digest`); the cap is raised by the measured words in the same change.
- **E. No gap issues at all (dissent, recorded).** See Consequences.

## Decision

1. **Affected and Reachable are three-valued: yes, no, unknown.** An unobservable, stale, silent or unmapped surface is `unknown`,
   never "not affected". `Affected=no` on a mutable host needs fresh observation; a declared-only source supports `no` only for an
   immutable, digest-pinned artifact. `Reachable=no` needs positive evidence from both the network layer and the code path. The
   overall verdict is worst-case: unknown reachability counts as reachable. This extends ADR-197 and ADR-192; "tri-state" is
   avoided in the title because ADR-192 already uses "three states" for a different classifier.
2. **The detailed exposure table is session output only.** Durable public artifacts carry only the single status
   `exposure-review-needed`, the CVE id and a generalized class (`infra`, `runtime` or `dependency`), and they are written through
   one chokepoint script, `file-gap-issue.sh`, which takes enumerated arguments only (no free text), uses a fixed title and body,
   defaults to a draft, requires an explicit yes and no exploitation evidence to create, and de-duplicates against open and closed
   issues. Never versions, hosts, addresses, kernel strings, advisory text, or the words "not affected" or "patched" beside a CVE
   id. A confirmed "no exposure" files nothing; any permitted wording is source-bounded and dated and states that it is not a
   security representation. This generalizes ADR-281 constraint 2 beyond the image scan; it does not close ADR-281's open item
   on a private place for dispositions.
3. **Fetched advisory text is untrusted.** It is annotated and never executed or copied into a durable artifact. This is ADR-287's
   rule, cited here and not re-decided.
4. **Hand-off to `fix` carries only the CVE id and component class.** The disclosure rule for fix-flow artifacts lives in the
   skill's hand-off text, not in AGENTS.md: exposure data exists only in this skill's context, and an always-loaded rule is paid on
   every turn for a single-skill concern.

## Consequences

- **Enforcement covers this skill's own writes only.** `fix`, `compound` and `ship` hold no exposure table and are not constrained
  by it; the hand-off payload is the only thing that reaches them. A lint over `knowledge-base/**` that rejects a CVE id paired
  with "not affected" is the cross-skill backstop; it is a tracked follow-up filed with this change, not delivered here.
- **Public residual.** Even the single status discloses that Soleur may be exposed to a named CVE. That is bounded by dedupe (one
  issue per CVE), draft-by-default, the explicit-yes gate, and the exploitation gate: with any evidence of exploitation the skill
  files nothing public and hands off to the breach-triage path. The skill never decides that a breach occurred.
- **Dissent.** The DHH plan-review reviewer argued for dropping gap-issue filing entirely, since any public mention is a
  disclosure. The plan keeps filing, narrowed to one status and a fixed body, and records the dissent as a user-challenge row in
  `knowledge-base/project/specs/feat-one-shot-12006-cve-exposure-skill/decision-challenges.md` for `ship` to surface. Reversing it
  later is a deletion of the script and its call site; no data depends on it.
- **Not durable.** Re-asking the question re-runs the telemetry read. That is cheap and keeps the answer fresh, which is the point
  for a mutable host.
- **Scope.** The skill is operator tooling for Soleur's own stack (file-existence scope guard); a customer's question about their
  own product goes elsewhere. It is read-only, makes no coverage or assurance claim, and its output is marked advisory.

## Cost Impacts

None. Reads use the existing Better Stack credential; the only recurring cost is the skill description's share of the per-session
description budget, paid by raising the cap by the measured word count.

## NFR Impacts

None. No new container, store or link is introduced; two operator-session edges are added to the C4 model (`founder` to
`betterstack`, `founder` to `github`).

## Principle Alignment

None. No AP-NNN deviation; the skill follows the no-SSH diagnosis rule and the Terraform-first rule by construction.

## Diagram

The two edges are in `knowledge-base/engineering/architecture/diagrams/model.c4`: `founder -> betterstack` (fixed read-only
ClickHouse SQL, session-only output) and `founder -> github` (gap issues in the Soleur repository only, through the chokepoint,
visible to `publicReader`). There is deliberately no `plugin -> betterstack` edge: it would contradict the customer-facing edges
that state Jikigai receives nothing from the customer's repository.
