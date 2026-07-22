# Decision challenges — feat-one-shot-6297-anthropic-key-missing-false-page

Headless pipeline run (`/soleur:one-shot` → plan). Per ADR-084 / `decision-principles.md`, Taste and
User-Challenge decisions are persisted here rather than surfaced at an interactive gate. `/ship`
renders this into the PR body and files it as an `action-required` issue.

---

## DC-1 — Cut the code-level day-31 severity escalation (User-Challenge)

**Class:** User-Challenge — this narrows the shape of something the operator asked for.

**What the operator asked for (the default, and it stands):**
> "Make the blocked state self-escalating so a stalled external dependency cannot decay into silence
> again — e.g. raise #6297 off p3-low, apply the `follow-through` label …, and have the cron's
> key-missing path carry the age of the dark window."

**What the plan originally proposed:** in addition to the above, a `DARK_WINDOW_BUDGET_DAYS = 30`
constant in the cron. Inside the budget the key-missing branch emits at `warning` (non-paging);
past it, it reverts to `reportSilentFallback` at `level=error` with a distinct
`op: "anthropic-admin-key-missing-overdue"`.

**What changed and why:** three independent review findings converged on cutting it. The third is
decisive on correctness grounds, not taste.

1. **It re-creates the defect it sits next to.** The bug is *"a non-incident emits at `level=error`
   and hits the operator's high-priority notification rule, daily, forever."* A 30-day fuse on the
   same emission is a snooze, not a fix. The cron runs daily, so day 31 onward is a daily page
   carrying no new information and no action the operator could not already take.

2. **Its stated alert route was factually inert.** The plan cited
   `sentry_cron_monitor.scheduled_anthropic_cost_report`, but the design keeps the heartbeat
   `ok: true` in both arms, and `cron-monitors.tf` explicitly scopes that monitor to a missed
   check-in or a classified 401/403. The monitor therefore *cannot* fire for the `-overdue` mode. The
   only thing that would actually page is the operator's **personal, un-versioned** Sentry
   notification setting — the same non-IaC setting the plan's own Overview blames for the false page.
   No `.tf` asserts it and no AC verifies it.

3. **It would have become a booby trap (decisive).** `FIRST_DARK_FIRE` is a frozen literal. If the
   key is minted and later unset — which ADR-108 `## Consequences` explicitly anticipates, naming key exposure
   a *rotation trigger* — the counter would read ~120 on day one of a fresh, entirely benign gap and
   page immediately at `level=error`. That is the exact failure this PR exists to remove, re-armed in
   the same branch.

Supporting: Better Stack retention on this source is **3 days**, so a 30-day budget is 10× the window
in which its own evidence survives.

**What still satisfies the operator's requirement:** self-escalation is delivered by Phase 4 —
`priority/p2-medium` + `follow-through` + the daily sweeper comment trail + auto-close on the first
healthy report. That is the house-standard mechanism (40 prior probes) and routes the nag to the
backlog channel rather than the fleet-down paging channel. The age the operator asked for is carried
by `days_since_first_dark` on the marker (Phase 2), which is retained.

**Recorded dissent (Kieran, plan-review):** argued to *keep* the escalation but fire it **once** (gate
on `days === BUDGET + 1`, or a weekly modulus) rather than daily, which would preserve a forcing
function without the alarm-fatigue loop. This was not adopted because it addresses only finding (1);
findings (2) and (3) apply unchanged to a fire-once variant, and (3) is a correctness defect
regardless of frequency. Noted here so the operator can overrule.

**If the operator disagrees:** the cheapest re-introduction that avoids all three findings is an
age-based label bump in the **sweeper** (`priority/p2-medium` → `priority/p1-high` after N days),
not a severity branch in application code. That keeps escalation in the channel that owns it and has
no frozen-date dependency.

---

## DC-2 — `deferred-automation` retained on #6297 (Mechanical, applied)

Not a challenge — recorded because it looks like one. The label and the literal body string are both
kept even though this PR removes the false page, because
`.claude/hooks/ship-operator-step-gate.sh:139` greps the linked issue **body** for the string
`deferred-automation` when gating PR-ready on operator-action references. Dropping it would trip that
gate. The issue remains genuinely blocked on an external dependency until the key is minted.

---

## DC-3 — Admin-key mint is NOT yet classified operator-only (Mechanical, applied)

Verified: the Anthropic Admin API has no key-creation endpoint (docs FAQ: *"new API keys can only be
created through the Claude Console for security reasons"*). That establishes there is no **API** path.

It does **not** establish that the Console UI is un-automatable, and the plan deliberately does not
claim so. Per `2026-06-10-playwright-attempt-evidence-before-operator-only.md` and the #5480
post-mortem — where the assertion *"no creation API — vendor limit"* was itself the defect, and a
later Playwright run found a working "Create API key" form behind no human gate — the step is marked
`automation-status: UNVERIFIED`. /work must attempt Playwright against `console.anthropic.com` and
record `playwright-attempt:` evidence before any operator handoff text ships.

---

## DC-4 — AC12/4.2/5.2 text amended to follow the shipped code (Mechanical, applied)

The plan specified field isolation as a **byte-form substring** match: `"component":"claude-cost"`
matched in both its unescaped form (for `--grep` / `raw LIKE`) and its backslash-escaped form (for
`grep -F` over JSONEachRow stdout). The shipped probe does not do that. It decodes `raw` once and
requires both discriminators as **top-level JSON keys** in a single-pass `jq` filter that fails
closed on trailing garbage.

The change was forced by review, not by convenience. Two-stage byte matching was **defeatable by an
embedded newline**: stage 1 materializes a `\n` inside `raw` as a real newline, stage 2 re-tokenizes
on physical lines, so a forged line from *inside* a multi-line `raw` is evaluated as though it were a
top-level log line — a false PASS that would auto-close #6297 with the key unminted. Reproduced
end-to-end; see commit `b12cd46b8` and the committed learning file.

**Decision: the AC text follows the code, rather than the code being held to the AC.** The shipped
form is strictly stronger — it accepts a superset of nothing and rejects a superset of what the
byte-form rejected — and it is mutation-proven (fixture 5c + arm 7 splits the filter back into two
stages and requires the fixture to flip). Holding AC12 to its literal original wording would have
had the AC certify the *weaker* property, which is the precise failure mode this PR spent its review
budget removing.

**Recorded rather than silently applied** because "spec follows code" is otherwise indistinguishable
from rewriting the target after missing it. The distinguishing evidence here is the mutation arm: a
code change made to dodge an AC cannot also make the guard demonstrably load-bearing.

Amended: plan AC12; `tasks.md` 4.2 and 5.2. The `betterstack-log-query.md` runbook already shipped
the structural wording and needed no change.
