---
title: "Phantom-ingest window prd auth.users audit (Branch C PR-α evidence)"
date: 2026-05-17
incident_pir: knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md
parent_issue: "#3861"
pr: "#3904"
plan: knowledge-base/project/plans/2026-05-16-feat-sentry-residency-a2-branch-c-plan.md
classification: art-30-5-accountability-evidence
ropa_entry: PA8 §(d) Recipients cell in knowledge-base/legal/article-30-register.md
---

# Phantom-ingest window — prd `auth.users` audit (Branch C PR-α evidence)

## Purpose

Establishes the Article 30(5) accountability evidence for the recipient-drift
disclosure in PA8 §(d) of `knowledge-base/legal/article-30-register.md`. The PIR
classification override (`brand_survival_threshold: none`, `art_34_triggered: false`)
rests on the premise "zero arms-length external signups during the phantom-ingest
window 2026-03-28 → 2026-05-16." This audit is the SQL-evidence-backed verification
of that premise — generated during PR-α review per `hr-no-dashboard-eyeball-pull-data-yourself`
when user-impact-reviewer (F3) flagged the un-evidenced claim as a potential P1
false-statement-in-Article-30 risk.

## Method

```bash
# Run against prd Supabase project via Doppler pooler (read-only SELECT).
doppler run -p soleur -c prd -- node -e '
  const { Client } = require("pg");
  const c = new Client({
    connectionString: process.env.DATABASE_URL_POOLER,
    ssl: { rejectUnauthorized: false }
  });
  await c.connect();
  const r = await c.query(
    "select count(*)::int as n " +
    "from auth.users " +
    "where created_at between '\''2026-03-28T00:00:00Z'\'' and '\''2026-05-16T23:59:59Z'\''"
  );
  console.log(r.rows[0]);
  await c.end();
'
```

Run at PR-α merge time 2026-05-17 (operator: Jean) via the Doppler pooler
(`aws-1-eu-west-1.pooler.supabase.com:6543`, transaction mode — single SELECT,
no DDL). Per-row email + `created_at` + `last_sign_in_at` + `provider` +
`raw_user_meta_data->>'full_name'` columns pulled in a follow-up query; operator
categorized each row by domain + signup pattern. Emails redacted to
domain + role classification in this committed audit file (raw email list
intentionally not committed — operator-internal categorization record only).

## Result

| Window count | Total prd `auth.users` count | Window date range observed |
|---|---|---|
| 10 | 14 | min `created_at` = 2026-04-02T15:46Z, max = 2026-05-07T09:56Z |

## Per-row categorization (operator-verified 2026-05-17)

| Email domain class | Count | Role / instruction basis | Arms-length? |
|---|---|---|---|
| `jikig.com` (founder) | 1 | Founder account (operator: Jean) | No |
| `soleur.ai` (founder) | 1 | Founder account (operator: Jean) | No |
| `jikigai.com` (team) | 1 | Team account (Harry — Jikigai employment relationship) | No |
| `soleur.ai` (team) | 1 | Team account (Harry — Jikigai employment relationship) | No |
| `jikigai.com` (bot) | 1 | `ux-audit-bot@jikigai.com` — automated audit bot under operator instruction | No |
| `soleur.dev` (test) | 1 | Internal QA test account (`qa-test@soleur.dev`) | No |
| `example.com` (test) | 2 | Internal test accounts (`qa-test@example.com`, `demo@example.com`) | No |
| `gmail.com` (friends-of-team test) | 2 | Both confirmed by operator on 2026-05-17 as friends-of-team / pre-team-account test of the external signup flow (single signup→signin in same second, no sustained usage; one preceded a team-account signup by 74 seconds, consistent with test-then-real pattern) | No |
| **Total** | **10** | All operator-adjacent | **Zero arms-length external** |

## Conclusion

**Zero arms-length external signups** occurred during the phantom-ingest window
2026-03-28 → 2026-05-16. All 10 in-window `auth.users` rows are operator-adjacent
(founder + team + bot + internal QA / test + 2 friends-of-team test signups under
operator instruction). The PIR `classification_override` (`chosen: none`) and
`art_34_triggered: false` decisions are supported by this evidence: the operator-as-
data-subject Art 34 obligation is satisfied by the PIR itself (committed, dated,
git-authored), the team / friends-of-team subjects are directly reachable by team
comms, and no arms-length external data subject was affected.

## Cross-references

- Article 30 register PA8 §(d) recipient-drift disclosure: `knowledge-base/legal/article-30-register.md:160`.
- PIR "Who was affected": `knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md:80,86`.
- compliance-posture.md Active Compliance Items row for #3861: `knowledge-base/legal/compliance-posture.md:86`.
- Plan Phase 2 GDPR Gate: `knowledge-base/project/plans/2026-05-16-feat-sentry-residency-a2-branch-c-plan.md:105`.
- Brainstorm threshold-framing: `knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md:33`.
- Learning on premise-vs-evidence asymmetry: `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md:94-100`.

## Re-evaluation triggers

- Any arms-length external signup in the prd `auth.users` table whose `created_at`
  falls within `2026-03-28T00:00:00Z` → `2026-05-16T23:59:59Z` (e.g., a delayed
  insertion from an offline migration or backfill). Re-run the SQL query above
  before PR-β merge and again at PIR Phase 8 close (PR-γ).
- Any operator-side reclassification of the 2 `gmail.com` rows from "friends-of-
  team test signups" to "arms-length external" — would escalate PIR Phase 8 +
  CNIL Art 33 filing posture per brainstorm Decision #10.
