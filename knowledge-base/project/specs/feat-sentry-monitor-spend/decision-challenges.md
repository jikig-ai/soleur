---
feature: feat-sentry-monitor-spend
issue: 6589
plan: knowledge-base/project/plans/2026-07-17-fix-sentry-iac-delete-path-plan.md
---

# Decision challenges — feat-sentry-monitor-spend

Decisions taken during `/work` that went **against the plan's stated direction**, with
the evidence that changed the call. Recorded so the divergence is reviewable rather
than buried in a diff.

---

## DC-1 — Phase 5c is refused: uptime monitor `1422253` is not dead, it is the app's only Sentry uptime coverage

**Plan said (Phase 5c, and OQ3):** delete uptime id `1422253` ($1.00/mo) via
`curl -X DELETE`. Rationale given: *"State has 4 uptime, `.tf` has 4, **live has 5**:
never Terraform-managed, so Terraform cannot destroy it."* OQ3 concedes *"Creation
mechanism of uptime id `1422253` — untraced; Sentry-only. **Does not block 5c.**"*

**What the live read shows (2026-07-17):**

| id | name | url | interval | status |
|---|---|---|---:|---|
| 1221115 | `soleur-ai-apex` | `https://soleur.ai/` | 300s | active |
| 1221117 | `soleur-ai-www` | `https://www.soleur.ai/` | 300s | active |
| 1221114 | `soleur-ai-changelog-deep` | `https://soleur.ai/changelog/` | 600s | active |
| 1221116 | `soleur-ai-acme-carveout-probe` | `https://soleur.ai/.well-known/acme-challenge/probe` | 300s | active |
| **1422253** | **Uptime Monitoring for https://app.soleur.ai** | **`https://app.soleur.ai`** | **60s** | **active** |

All four Terraform-declared monitors watch the **marketing site**. `1422253` is the only
one watching the **production application** — at the tightest cadence of the five.

**Why the plan's reasoning fails.** It infers *dead* from *not-Terraform-managed*. Those
are different properties: an unmanaged resource can be load-bearing, and this one is. The
plan's own OQ3 records that the creation mechanism is untraced and then rules that this
does not block the delete — but the untraced provenance is precisely the evidence that
would have shown it is load-bearing. "Untraced" is a reason to look, not a reason to
proceed.

This is the Class D confusion in reverse. Class D asks *"is this live thing declared?"* and
correctly treats an undeclared live monitor as suspicious. It does **not** license the
inference *undeclared ⇒ deletable* — which is what 5c does.

**Blast radius, against this plan's own `brand_survival_threshold: single-user incident`.**
Deleting `1422253` removes Sentry's only uptime coverage of `app.soleur.ai`. Better Stack
does second-source `app.soleur.ai/health` (3-min interval), so coverage would not reach
zero — but `model.c4:271` is explicit about what the second source is *for*:

> `betterstack` is a SECOND-SOURCE vendor that pages independently precisely so a Sentry
> outage is survivable (see its own edge to founder). **Do not 'consolidate' the two — the
> redundancy is the design.**

So the delete would collapse deliberate two-vendor redundancy on the one surface where a
user-facing outage actually lives, to save **$1.00/mo**. The plan's Overview states the
case for the whole change as *"The win is not the $42/mo"* — 5c trades a brand-survival
control for 2.4% of a figure the plan itself disclaims.

**Decision:** Phase 5c is **not executed**. `1422253` is left live.

**Operator ruling (2026-07-17):** do not delete; **import it into Terraform**. Keeps
`app.soleur.ai` on two independent vendors, and brings the resource under IaC so it stops
being an untracked orphan that Class D will flag on every audit run.

**Not done in this PR, deliberately.** The import needs an `import` block + a matching
`sentry_uptime_monitor` resource whose attributes reconcile against the live monitor
(url/interval/method/assertion + `owner`), and #6589's own `## Infrastructure` section
records **"None to `infra/sentry/*.tf`" — no import blocks needed; state is complete**.
Adding one here would contradict that section's premise and put a fresh, unreviewed
`create`-or-`import` into the very plan whose delete-set (AC5) this PR asserts by identity.
Tracked as **#6606**.

**Does Class D flag it in the meantime? No — and I checked rather than assumed.** Class D
reads the **cron-monitor** endpoint (`/organizations/<org>/monitors/`) and compares against
`resource "sentry_cron_monitor"` declarations. Uptime monitors are a **different API
surface** (`/organizations/<org>/uptime/`) and a different resource type, so `1422253` is
outside Class D's scope entirely. It will not be flagged, and the apply will not halt on it.

That is a **coverage gap, not a reprieve**: the uptime direction has no Class D equivalent,
which is precisely why this monitor could exist un-noticed and un-costed for long enough
that a plan called it dead. Worth folding into the import follow-up.

_Evidence: live `GET /api/0/organizations/jikigai-eu/uptime/` 2026-07-17; `model.c4:271`;
`uptime-monitors.tf:60,79,119,180`; `expenses.md` Better Stack row._
