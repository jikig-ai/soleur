---
title: A migration/plan comment asserting referential (cascade) safety must verify the actual FK ON DELETE type, not assume it
date: 2026-07-07
category: best-practices
tags: [migrations, postgres, foreign-keys, plan-verification, review]
issue: 5739
pr: 6181
---

# Migration cascade-safety prose must verify the actual FK `ON DELETE` type

## Problem

Migration 124 (#5739) prunes `auth.flow_state`. The one referential dependent is
`auth.saml_relay_states.flow_state_id`. Both the plan's `## Downtime & Cutover`
section (authored at deepen-plan time) and the migration header comment I copied
from it asserted the DELETE was safe because *"if the child were ever non-empty, a
`NO ACTION` FK would surface as a visible cron error, never corruption."*

The FK is actually `ON DELETE CASCADE` (GoTrue's schema). The assumed behavior
(block/error) and the real behavior (silently cascade-delete the child) are
**opposite**, so the "safety" prose described a failure mode that cannot happen and
omitted the one that can. tsc/tests are blind to prose; the deepen-plan triad had
already reviewed the plan and did not catch it — a fresh `data-integrity-guardian`
at PR-review time did.

## Root Cause

A referential-safety claim in a migration comment / plan is a **hypothesis about a
catalog fact**, not a fact. `ON DELETE` behavior is a one-query lookup
(`pg_constraint.confdeltype`: `a`=NO ACTION, `r`=RESTRICT, `c`=CASCADE, `n`=SET
NULL, `d`=SET DEFAULT), yet it is easy to guess from the table's role ("relay states
are ephemeral, probably NO ACTION") and let the guess propagate from plan → migration
comment → ADR unverified.

## Solution / Rule

Before writing ANY cascade / referential-safety prose into a migration comment, plan
`## Downtime` section, or ADR, verify the actual `ON DELETE` action from the live
catalog:

```sql
SELECT con.conname,
       CASE con.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
         WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END,
       pg_get_constraintdef(con.oid)
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
 WHERE con.contype='f' AND nsp.nspname='<schema>' AND rel.relname='<child_table>';
```

Same class as `hr-when-a-plan-specifies-relative-paths-e-g` and "plan-quoted numbers
are preconditions to verify" — the plan is authoritative for *intent* (is the DELETE
referentially safe?), never for the *catalog fact* (which `ON DELETE` action makes it
safe). A DELETE on a parent is safe under BOTH `CASCADE` (child auto-removed) and an
empty child, but the *reason* and the *forward-looking* behavior differ, so the prose
must state the real action.

## Key Insight

"Is this DELETE referentially safe?" and "what is the FK's `ON DELETE` action?" are
different questions. Answer the second from `pg_constraint`, not from the child
table's apparent role, before you write the safety narrative — a wrong guess inverts
the documented failure mode and misleads the next integrator (here: a future SAML
onboarding would find the daily prune reaches into `saml_relay_states` by cascade,
which the "NO ACTION → errors" prose actively denied).

## Session Errors

- **FK `ON DELETE` asserted (`NO ACTION`) not verified; actual is `CASCADE`.** —
  Recovery: live-queried `pg_constraint.confdeltype`, corrected migration comment +
  plan Downtime + ADR. Prevention: this learning (verify `confdeltype` before writing
  cascade-safety prose).
- **ADR-098 cited a non-existent `ADR-033-inngest-for-application-scheduled-work.md`.**
  ADR-033 has three ordinal-collided files, none matching. — Recovery: routed the
  citation to the real precedent `ADR-030-inngest-as-durable-trigger-layer.md`.
  Prevention: `ls` the exact ADR filename before citing it (ordinal collisions make
  bare `ADR-0NN` labels ambiguous).
- **Retention-cron prose drift** — "all prior crons target `public.*`" (115 prunes the
  `cron` schema) and "14 existing retention crons" vs ADR's "5 sibling crons". —
  Recovery: reconciled to the 5 named siblings + noted 115's `cron`-schema exception.
  Prevention: derive counts/claims from the enumerated file set, not a mental tally.
