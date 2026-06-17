---
title: "A 'no C4 impact' conclusion requires reading all three .c4 files and enumerating external actors/systems — never a single keyword grep"
date: 2026-06-18
category: workflow-patterns
tags: [c4, architecture, adr, plan-gate, external-actors, likec4]
issue: PR #5494 (feat-shared-workspace-email-triage-inbox)
---

## What happened

While shipping the shared-workspace email-triage inbox (ADR-066), the plan's
Architecture Decision (ADR/C4) gate concluded **"no C4 impact"** from a single
narrow grep:

```
grep -niE "email.?triage|inbox" model.c4 views.c4   # → no output
```

and wrote "the inbox is not modeled at the C4 abstraction level — no `.c4` edit
warranted." The operator pushed back: *"are you sure there is no C4 updates? Did
we map the external actors for emails by example? Did we look at updating all C4
diagrams?"*

Reading the model properly revealed the grep was the wrong probe entirely:

- The email-triage **inbound ingress** (Resend webhook) and **outbound
  notifications** were **completely absent** from the C4 model — a pre-existing
  gap from the email-triage introduction (#5125).
- The relevant elements are named by **vendor/role**, not by feature: an
  **external actor** "Inbound Correspondent" (the senders) and an **external
  system** "Resend" — neither matches a `grep email-triage`.
- The `founder` actor description ("**Solo** founder") was factually stale post
  ADR-038 (team workspaces) and directly contradicted by this very feature
  (multi-Owner shared inbox).

The correct fix added the `emailSender` actor + `resend` system + inbound/
outbound/`inngest→supabase` edges to `model.c4`, the two new elements to the L1
+ L2 `view … include` lists in `views.c4` (else they don't render), and
corrected the actor description. `spec.c4` needed no change. Validated via
`c4-code-syntax` + `c4-render` tests (29 green).

## The rule

A "no C4 impact" conclusion is only valid after you have **READ all three model
files** (`diagrams/{model.c4,views.c4,spec.c4}`) and **enumerated, for the
feature**: (a) external human actors (who sends/receives the data), (b) external
systems/vendors (inbound webhooks, outbound APIs, third-party stores), (c)
containers/data-stores touched, (d) actor↔surface access relationships that
change (single-owner → workspace-shared). For each, confirm it is already
modeled; if not, adding it (element + `#external` tag + relationship edges + the
`views.c4` `include` line so it renders) is an in-scope task. **A keyword grep
for the feature's own noun is not evidence of absence** — the gap is usually an
external actor/vendor named by something else. Reviewing "all diagrams for
correctness" also means fixing element descriptions the change falsifies.

Codified in `plugins/soleur/skills/plan/SKILL.md` Phase 2.10 "C4 completeness
mandate" + reject condition. See [[2026-06-16-adr-c4-update-is-a-plan-deliverable-not-a-deferred-issue]].

## How to apply

When a plan touches an integration boundary (email, SMS, payments, webhooks,
any third-party data flow) or an access-grain change (who can see/do X), the C4
review is NOT optional and NOT grep-shaped: read the model, list the external
actors + systems + access edges, and edit `model.c4` + `views.c4` (+ run the C4
tests) in the same PR. After editing `views.c4` `include` lists, run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` — an
include referencing an undefined element fails there, never at `tsc`.
