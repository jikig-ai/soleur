---
category: security
tags: [breach, gdpr, art-33, access-logs, key-exposure, rls, supabase]
date: 2026-08-26
triggers:
  - anon key exposed
  - service_role key leaked
  - publishable key shipped in a client bundle
  - credential found in git history
  - RLS disabled on a public table
  - suspected unauthorized access
  - was the leaked key actually used
  - reachability confirmed but access unknown
  - access log investigation
---

# Runbook — breach access-log investigation (was the exposure actually used?)

**Status:** active
**Owner:** engineering / security, escalating to CLO
**Promoted from:** the `GATE G-ESCALATE` blockquote in
`knowledge-base/project/plans/2026-06-29-security-inngest-prd-enable-rls-lockdown-plan.md`
(§Escalation status at plan time). That plan ran the procedure once and the post-mortem called
it reusable; it lived nowhere durable until now.

## When to run this

Run it whenever *reachability* of personal data is confirmed but *actual access* is not — an
exposed key, an RLS gap on a public table, an over-broad grant. The distinction is the whole
point: **reachability alone does not start the GDPR Art. 33 72-hour clock.** Evidence that
personal data was actually accessed by an unauthorized party does. This procedure is what
turns "we don't know" into one of three defensible answers.

It is blocking: run it **before** remediation, because remediation can destroy the evidence
that would have answered the question.

## Step 1 — Key-exposure check (anon AND `service_role`)

Determine whether the project's **anon / publishable** key was ever published or embedded —
client bundles, git history, public docs, Doppler audit log. For a dedicated backing project
the anon key is expected to live only in the dashboard and Doppler and never to have shipped
in a client; confirm that rather than assuming it.

**Also check the `service_role` key.** `service_role` bypasses RLS entirely, so if it leaked
the breach surface is total and the RLS posture is irrelevant to the question. Same three
places: git history, CI logs, Doppler audit.

## Step 2 — Establish the actual log-retention horizon FIRST

Do this **before** looking for hits. A "zero hits" result over a window shorter than the
exposure window is *absence of evidence, not evidence of absence* — and once that zero has
been written into a record, it is very hard to un-write.

Run the helper over the candidate window and read the **verdict**, not the count
(runbook: [`supabase-log-query.md`](./supabase-log-query.md)):

```bash
doppler run -p soleur -c prd -- \
  scripts/supabase-logs-query.sh --ref <project-ref> --source postgres_logs \
    --since <candidate-window> --json
```

- Exit `0` / `COVERED` — the window is genuinely covered. This is your horizon so far; widen
  and repeat.
- Exit `3` / `INCONCLUSIVE` — the window is **not** covered. The boundary between the last
  `COVERED` window and the first `INCONCLUSIVE` one is the horizon you can actually assert.

Two rules that follow from measurement, not from the vendor's documentation:

1. **Never take the horizon from a tier page or a retention setting.** The published guard on
   this endpoint's window is not enforced, and the empirical cap is undocumented and moves.
2. **Never establish the horizon by comparing row counts across windows.** A *wider* window
   returning *fewer* rows is a measured behaviour of this endpoint, so a count comparison can
   be read backwards. The coverage verdict is the instrument; the count is not.

Measurements behind both rules:
[`phase-0-endpoint-evidence.md`](../../../project/specs/feat-one-shot-supabase-analytics-logs-endpoint-migration/phase-0-endpoint-evidence.md)
§Confirmed from the plan.

## Step 3 — Access-log analysis over the exposure window

Pull request logs over the exposure window, filtered to anon-authenticated requests against
`/rest/v1/*` and `/graphql/v1`.

**Justify the window's start** from the true exposure start — the project-creation or
first-public-table-served date from the provisioning config — not from a table's
`relfilenode` ctime. The end is the remediation date.

```bash
doppler run -p soleur -c prd -- \
  scripts/supabase-logs-query.sh --ref <project-ref> \
    --source postgrest_logs --source auth_logs \
    --since <exposure-start> --until <remediation-date> --json
```

**A source that has never emitted cannot exonerate anyone.** If the helper reports a source
`UNINSTRUMENTED`, its zero carries no information at all and must not be recorded as a clean
result — take the instrumented alternatives the helper names in the same block and re-run
against those. This is not hypothetical: `edge_logs` produced zero rows across an entire
30-day live period on prd (evidence file, §Confirmed from the plan, finding E), and a
2026-06-29 investigation reached for exactly that source.

## Step 4 — Branch on coverage (three ways, and only three)

| Finding | Verdict | Action |
|---|---|---|
| Evidence of actual unauthorized anon / `service_role` access | **BREACH** | **STOP.** Route to the CLO / legal-threshold path — Art. 33 72h clock, Art. 30 record. Capture timestamps and IPs. |
| Logs cover the FULL window and are clean | **CLEAN** | Proceed with remediation. Record the negative finding — window, queries, zero hits — plus an Art. 30 note reading "no breach — reachability only, remediated". |
| Logs do NOT cover the full window | **INCONCLUSIVE** | Not clean. Record the window *actually* covered, route the residual-window decision to the CLO, and state the coverage limitation explicitly in the Art. 30 note. |

**Never silently conclude "no breach" from a partial pull.** INCONCLUSIVE is a real verdict
with its own escalation path, not a softer way of saying clean. The helper's exit `3` exists
so that this branch cannot be taken by accident.

## Step 5 — On confirmed key exposure, rotate

If Step 1 confirmed exposure of either key, escalate **and rotate it**. Revoking grants
protects the locked tables, but rotation is the clean remediation and de-risks any window
before the lockdown applies.

## Recording the outcome

Whichever branch fires, the record must carry the window requested, the window actually
covered, the per-source instrumentation status, and the verdict — as one block. A count
separated from its verdict is how a partial pull becomes a clean bill of health three
documents downstream.
