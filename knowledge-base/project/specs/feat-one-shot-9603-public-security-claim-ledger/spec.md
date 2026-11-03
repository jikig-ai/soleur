---
title: Internal public-security-claim ledger
feature: feat-one-shot-9603-public-security-claim-ledger
issue: 9603
epic: 9601
lane: single-domain
brand_survival_threshold: single-user incident
status: planned
---

# Spec: internal public-security-claim ledger (#9603)

Plan: `knowledge-base/project/plans/2026-11-03-feat-public-security-claim-ledger-plan.md`. Rulings: `decision-challenges.md` in this directory.

## Problem

Public documents, in-app copy and the Art. 30 register already say some things about agent isolation, egress and human approval, while several controls are off, partly measured or not built. There is no single place that states, per claim topic, which control would measure it, what its status is, and what evidence backs it. Issue #9603 assumed no isolation claim exists publicly; that premise is stale.

## Goals

- G1: One internal ledger, `knowledge-base/legal/public-security-claim-ledger.md`, with claim-topic rows across isolation, egress and human approval.
- G2: Every `measured` row has resolvable evidence; everything unverified is labelled.
- G3: Every isolation, egress or approval statement already on a public or world-readable surface is mapped to a row and classified; unsupported ones reach the CLO as findings.
- G4: A Publication Criterion with a pass criterion and runnable reviewer commands, a #2004 overlap decision, and a re-evaluation trigger.

## Non-goals

No published page or draft page sentence. No gate script or CI check. No edit to `docs/legal`, `plugins/soleur/docs`, in-app copy, the Art. 30 register, `compliance-posture.md`, the Privacy Policy or the DPD. No issue filed or closed. No flag created or flipped.

## Functional requirements

- FR1: The ledger opens with a banner stating it is an internal working ledger and not a statement by Jikigai about product security.
- FR2: Part 1 rows use columns ID, Topic, Control that would measure it, Status, Evidence, Not yet claimable; Part 1 status is one of measured, dark, not-shipped, advisory.
- FR3: Part 1A holds rows with a measured basis; Part 1B ("Not yet claimable") holds every dark, not-shipped and advisory row plus a pointer for each flagged measured row.
- FR4: Part 2 rows use columns ID, Surface and anchor, Topic descriptor, Kind, Maps to, Status, Finding; Part 2 status is published-measured or published-unverified (weakest mapped row wins); Kind is assurance, disclosure or register-entry; each finding has a closed Finding type and a Disposition (escalate, CLO-owned, accepted-by-CLO).
- FR2a: The not-yet-claimable column is exactly yes or no; every yes row carries `[residual: ...]` and or `[prod-unmeasured: ...]` tags; every measured evidence cell carries the owning ADR status quote, host class, measured-commit SHA and instrumented path list.
- FR5: The ledger corrects the stale premise, records the #2004 decision and the re-evaluation trigger, and documents the Publication Criterion (C1 to C7).
- FR6: The CLO agent prepares the rows and the Part 2 sweep; the CLO review is recorded before merge.

## Technical requirements

- TR1: Diff limited to the allowed paths (plan AC1, with a negative control).
- TR2: The digits of the egress-audit enablement issue appear nowhere in the diff, PR body or comments (plan AC2).
- TR3: `bash scripts/lint-legal-registers.sh`, markdown lint and `scripts/check-adr-ordinals.sh` pass.
- TR4: No candidate public sentence anywhere; topic descriptors only.
