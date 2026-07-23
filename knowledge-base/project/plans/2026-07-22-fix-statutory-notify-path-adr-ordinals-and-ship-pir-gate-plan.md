---
title: "fix: statutory-notify delivery path, ADR ordinal disambiguation, and the ship Incident-PIR gate regex"
date: 2026-07-22
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: [6798, 6799, 6800, 6801, 6802, 6813]
branch: feat-one-shot-6798-6813-statutory-notify-adr-ship-gate
pr: 6834
---

# fix: statutory-notify delivery path, ADR ordinal disambiguation, and the ship Incident-PIR gate

> Spec lacks valid `lane:` (no `spec.md` on this branch at plan time) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-07-22 · **Gates run:** 4.4, 4.5, 4.55, 4.6, 4.7, 4.8, 4.9 (all pass or N/A) · Full log in [§Research Insights](#research-insights-deepen-plan-2026-07-22).

**Corrections applied to the plan body:**

1. **§D3b reason 2 was wrong.** The draft claimed `acknowledged_at` is "indexed-eligible". `email_triage_items` has four indexes and **none names `acknowledged_at`** — nor can a bare `received_at` predicate use the existing ones (it is always the second column). Rewritten: the real bound is the **365-day statutory retention**, not an index. Re-evaluation trigger + a Phase 0.8 row-count task added rather than a speculative migration.
2. **The dropped-`tags` blast radius is now measured, not open-ended.** Census run: **exactly one** affected site. The only other non-test `infoSilentFallback` caller (`cron-workspace-gc.ts`) passes no `tags`.
3. **A latent trap in the #6813 test harness, measured in a shell.** The gate's `A && B && echo SIGNAL` chain **exits 1 when there is no signal**. A harness that lets `set -euo pipefail` see it inverts the three no-signal assertions into infrastructure failures. Recorded as a Sharp Edge and as tasks.md step 5.2.3.

**New considerations discovered:**

- The `.delete()` marker rollback (§D4c) has **no repo precedent** — flagged for reviewer scrutiny, with the composite-key / no-`.select()` `42703` trap named in tasks.md 4.7.2.
- The `head:true` count query has four precedents, **all in dashboard route handlers** — this is its first use inside an Inngest cron, so the test fake may need extending.
- The conditional warn-vs-info escalation **diverges** from the `cron-workspace-gc.ts` precedent (which splits into two ops). The divergence is required by #6801's "not a separate emit" constraint and is now recorded rather than left to be discovered at review.
- **`/soleur:plan-review` did not run** (no `Task` tool in the planning subagent) and is mandatory at this threshold — added as blocking task **0.9**.

## Overview

Six OPEN issues, all deliberately deferred from #6781 (merged as PR #6782) per
`wg-when-deferring-a-capability-create-a`. They cluster into three code areas:

| # | Title (short) | Area | Class |
| --- | --- | --- | --- |
| #6798 | statutory reminder presents a computed date as THE deadline | statutory copy | legal / reliance |
| #6799 | T-7 heads-up exact equality → jitter skips it entirely | repin predicate | correctness |
| #6801 | 60-day repin scan cliff, uncountered | repin scan bound | correctness + observability |
| #6802 | non-410 push failure → permanent total silence | delivery path | correctness (single-user incident) |
| #6813 | Incident-PIR gate regex matches the threshold label | `ship/SKILL.md` | tooling / alert-fatigue |
| #6800 | ADR frontmatter ordinals disagree with filenames | ADR corpus | docs hygiene |

The four notification issues share one narrative: **#6781 made the statutory
backstop reliable, and reliability without delivery is worse than
unreliability.** Before the send-marker, a failed push was retried by the next
tick (an accidental self-heal); after it, the marker certifies a non-send as
sent. This plan makes the marker mean *delivered*, makes the heads-up
un-skippable, re-anchors the scan window to the state that actually confers
eligibility, and puts non-legal-advice framing on the copy the operator now
depends on.

`#6813` and `#6800` are independent and cheap; they are batched here because
they are the remaining #6781 deferrals and both are docs/tooling-only.

**Closes #6798, Closes #6799, Closes #6800, Closes #6801, Closes #6802, Closes #6813.**

---

## Premise Validation (Phase 0.6)

| Cited premise | Probe | Result |
| --- | --- | --- |
| #6798/#6799/#6800/#6801/#6802/#6813 are OPEN | `gh issue view N --json state` (all six) | **HOLDS** — all `OPEN` |
| #6782 merged (predecessor, NOT a collision) | `gh pr view 6782` | Predecessor. Cited-predecessor false positive already cleared by the one-shot collision gate. Do NOT abort. |
| `cron-email-ingress-probe.ts` exists | `test -f` | HOLDS (578 lines) |
| `notifications.ts` exists, exports `PushDeliveryTally {delivered, attempted}` | `notifications.ts` §`export interface PushDeliveryTally` | HOLDS (`delivered`/`attempted`) |
| `ship/SKILL.md` Phase 5.5 carries `OUTAGE_RE`/`PROD_RE` | `grep -n OUTAGE_RE` | HOLDS (`ship/SKILL.md` §"Incident-PIR Gate", the `OUTAGE_RE='(outage\|incident\|…` line) |
| `sendPushNotifications` prunes only on 410 | `notifications.ts` §`if (err.statusCode === 410)` | HOLDS |
| `notifyOfflineUser` branches on `subscriptions.length > 0` | `notifications.ts` §`if (subscriptions && subscriptions.length > 0)` | HOLDS |
| `deadline-repin` scan bounded on `received_at` | `cron-…-probe.ts` §`.gte("received_at", scanFloor)` | HOLDS |
| T-7 arm is an exact equality | `cron-…-probe.ts` §`daysUntilDue !== DEADLINE_REPIN_HEADS_UP_DAY` | HOLDS |
| `breach-art33` due rule is 72h | `lib/email-triage/statutory-rules.ts` §`ruleId: "breach-art33"` → `{kind:"hours", hours:72}` | HOLDS — `daysUntilDue` maxes at `2`, so `=== 7` is unreachable |
| `ADR-037-*.md` frontmatter says `adr: 035` | frontmatter scan of all 132 ADRs | HOLDS |
| `ADR-035-*.md` carries the #6781 see-also pointer | `ADR-035-template-registry-code-static.md` §"See also" block (2 lines) | HOLDS |
| ADR ordinal checker exists | `scripts/check-adr-ordinals.sh`, wired in `.github/workflows/ci.yml` + `grok-pre-push-gate.sh` + `ship/SKILL.md` | HOLDS — the enforcement point already exists |
| No open code-review issue names the primary files | `gh issue list --label code-review` + `jq` per path | 2 tangential hits — see §Open Code-Review Overlap |

Nothing stale. Two premises in the issue bodies are **wrong or incomplete** and
are corrected in §Research Reconciliation.

---

## Research Reconciliation — Issue Claims vs. Codebase

| Claim (source) | Reality | Plan response |
| --- | --- | --- |
| #6801: "Fold an excluded-row count into the existing `infoSilentFallback` payload … so a non-zero value is **visible in Better Stack**." | **FALSE as written.** `infoSilentFallback` logs at pino `info`; `apps/web-platform/infra/vector.toml` §`[transforms.app_container_warn_filter]` keeps only `level_int >= 40`. The file's own comment says so ("this counter reaches SENTRY only. Better Stack does not carry it."). An `info` emit can never satisfy the AC. | Keep **one** emit and one op slug (`deadline-repin-sweep-complete`), but **level-escalate**: `warnSilentFallback` when `excluded > 0 \|\| suppressed > 0`, `infoSilentFallback` otherwise. Warn clears the Vector filter → reaches Better Stack **and** Sentry, satisfying the AC without a second emit (which the issue explicitly rejects). |
| #6781 comment: "`tags: { repin_suppressed: … }` … has to be queryable." | **The tag is silently dropped.** `observability.ts` §`export function infoSilentFallback` destructures `{ feature, op, extra, message }` — it never reads `options.tags` (unlike its `report`/`warn` siblings, which do `Object.assign(tags, extraTags)`). The `repin_suppressed` tag has never reached Sentry. | Fold in: add the same `extraTags` merge to `infoSilentFallback` for sibling parity. Only **2** non-test callers exist, so the widening is contained. Pin with a test asserting the tag survives. |
| #6801: "keying the scan on an acknowledgement timestamp" is a hypothetical option. | `email_triage_items.acknowledged_at timestamptz` **already exists** (mig `102_email_triage_items.sql`), is set by the status RPC on the `→ acknowledged` transition, and is **one-time-set / immutable** (mig 102 §`acknowledged_at is immutable once set`). No migration needed. | Adopt it (see §Decision D3). Phase 0 precondition: prove no `status='acknowledged'` row can carry `acknowledged_at IS NULL`. |
| #6800: "any renumbering must sweep every citation." | A rename sweep is disproportionate: `ADR-NNN` appears **11,784** times repo-wide. But **zero renames are needed** — only 2 files disagree (`ADR-036` fm=`034`, `ADR-037` fm=`035`). | Filename becomes authoritative; the disagreeing frontmatter ordinal is **removed**, not rewritten (the acceptance criterion's second branch). Sweep is then bounded to citations of `ADR-034`/`ADR-035` that meant the *frontmatter* value. |
| #6800 implicit: fixing frontmatter fixes all citations. | **6 durable code/SQL sites cite `ADR-035` meaning the dedup idiom** (= the `ADR-037-*` file): `notifications.ts` (2, at the `notifyInboxItem` idempotency comments), `supabase/migrations/122_inbox_item.sql` (2), `supabase/migrations/135_statutory_repin_send.sql` (2). Two more (`server/templates/template-registry.ts`) legitimately mean the `ADR-035-*` file. | Per-citation content adjudication, not a blind sed. **Applied migrations are frozen** — see §Decision D6. |
| #6798: framing is a copy change. | The registry has no field distinguishing *when the clock starts*. `dueRule` carries a `label` only; `breach-art33`'s label already says "…within 72 hours (GDPR Art. 33)" but nothing encodes that the 72h runs from **awareness**, not from `received_at`. | Add a code-static `clockOrigin: "receipt" \| "awareness" \| "instrument"` field to `StatutoryRule` and derive the per-rule caveat from it (see §Decision D1). |
| #6813: "the regex matches the threshold label." | Confirmed, and there are **three** independent defects, exactly as the issue enumerates. Also confirmed: `PROD_RE` matches on the bare word `prod`, which this very plan file contains many times. | Fix all three + require a past-tense production-failure signal (see §Decision D5). |

---

## User-Brand Impact

**If this lands broken, the user experiences:** a statutory-deadline reminder
that never arrives — no push, no email — for an item with a running GDPR
Art. 12(3) / Art. 33 clock, while `/api/inbox` and the cron both report the ping
as sent. The first the operator learns of it is a regulator's follow-up.

**If this leaks, the user's data/workflow is exposed via:** no new exposure
surface. The change moves an **existing** notification from a failed push
channel onto the **existing** Resend email channel for the **same** recipient
(`auth.users.email`, already the fallback for zero-subscription users). No new
recipient, no new data category, no new processor. The one new *content* element
is a static, server-authored disclaimer — no third-party or personal data.

**If this over-notifies, the user experiences (added at review):** alarm fatigue.
Because `status` is a one-way `new → acknowledged` terminal matrix (no `resolved`
state) and D3b anchors the 60-day window on `acknowledged_at`, a statutory item the
founder already handled keeps generating daily "(computed) OVERDUE" pings for up to
~60 days after acknowledgement — desensitizing the founder to the exact notification
class this feature protects. This is the fatigue direction of the same harm #6798
addresses via reliance. It is **out of scope** for the six issues (it needs a
`resolved` state + a founder-facing digest) and is tracked in
`decision-challenges.md` C3 (consolidated flow-gaps follow-up); named here so the
gate section reflects both the under-notify (silence) and over-notify (fatigue)
directions, not only silence.

**Brand-survival threshold:** `single-user incident`

Justification: a single operator receiving zero statutory notices for the life
of a broken push subscription is, on its own, a brand-ending event — it is the
exact failure the whole email-triage feature exists to prevent, and #6802
documents the concrete trigger (the egress firewall's deliberate WNS DROP,
#5046 PR-2, which is not a 410 and therefore never prunes).

Per §2.6 Step 3: `requires_cpo_signoff: true` is set in frontmatter; CPO
sign-off is required at plan time (see §Domain Review), and
`user-impact-reviewer` runs at review time.

---

## Decisions (the plan is the decision record)

### D1 — #6798: registry-derived clock-origin framing + a standing not-legal-advice disclaimer

**Decision.** Encode clock origin in the registry, not in prose.

1. Widen `StatutoryRule` with `clockOrigin: ClockOrigin` where
   `type ClockOrigin = "receipt" | "awareness" | "instrument"`. Assign:
   - `dsar-art15` → `"receipt"` (Art. 12(3): one month from receipt of the request)
   - `regulator-*` → `"receipt"` unless the instrument states otherwise
   - `breach-art33` → `"awareness"` (72h from **becoming aware**, GDPR Art. 33(1))
   - `service-of-process` → `"instrument"` (its `dueRule` label already says
     "verify the instrument's own deadline")
2. Add two code-static copy constants to `lib/email-triage/statutory-rules.ts`
   (it is the pure, client-safe, code-static registry — the right home; no I/O,
   no env, imported by cron + routes + agent tools alike):
   - `NOT_LEGAL_ADVICE_NOTICE` — the standing disclaimer.
   - `clockOriginCaveat(origin: ClockOrigin): string` — the per-origin sentence.
3. Render both in **all three** statutory surfaces:
   - push body — `notifications.ts` §`payload.isStatutory ? "Statutory item — a response clock is running."` (append a short form; push bodies are length-constrained, so the push carries the short caveat + "not legal advice" and the email carries the full text)
   - email — `sendEmailTriageEmailNotification`'s `bodyHtml` + `footnoteHtml`
   - the reminder title built in the cron — `cron-…-probe.ts` §``title: `Statutory deadline approaching — ${formatDueDate(...)}` `` → the *computed* framing moves into the title verb ("estimated"/"computed"), with the full caveat in the body.

**Why encode rather than write prose:** a hard-coded paragraph goes stale the
moment a rule is added. A registry field makes "which clock does this start
from?" a compile-time obligation of adding a rule — the same discipline
`dueRule` already imposes.

**Non-negotiable gate.** The wording ships only after a `soleur:legal:clo`
agent review (#6798 AC bullet 3: "CLO reviews the wording before it ships —
this is a reliance question, not a copy-polish question"). This is an in-scope
implementation task (Phase 1, step 1.4), not a follow-up. The CLO's verdict is
recorded verbatim in `knowledge-base/project/specs/<branch>/clo-copy-review.md`
and referenced from the PR body.

**Scope-out (recorded):** we do NOT attempt to compute the true Art. 33
awareness-clock date. There is no awareness timestamp in the schema and
inferring one from `received_at` is precisely the over-claim this issue is
about. The caveat states the limitation instead.

### D2 — #6799: the heads-up becomes a BAND with a constant tick_key

**Decision.** Replace the exact equality with a range and let the existing
`headsup` marker do once-only enforcement.

```
// before
if (daysUntilDue !== DEADLINE_REPIN_HEADS_UP_DAY &&
    daysUntilDue >  DEADLINE_REPIN_DANGER_THRESHOLD_DAYS) continue;
const tickKey = daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY ? "headsup" : `daily:${runDateUtc}`;

// after
if (daysUntilDue > DEADLINE_REPIN_HEADS_UP_DAY) continue;          // 8+ → not yet
const inHeadsUpBand = daysUntilDue > DEADLINE_REPIN_DANGER_THRESHOLD_DAYS; // 3..7
const tickKey = inHeadsUpBand ? "headsup" : `daily:${runDateUtc}`;
```

This is the issue's first suggested direction. It composes with #6781 rather
than fighting it: the `headsup` key is *already* a constant precisely so it
collapses a window, and the migration-135 CHECK already pins exactly the two
tick_key shapes — **no migration change is required.**

**The consequence #6799 does not name, and which this plan must handle.**
Under the band, an item pinged at T-7 hits the `headsup` marker again at T-6,
T-5, T-4, T-3 and each raises a clean `23505`. Today that increments
`suppressed`, and `suppressed > 0` is the **sole signal that a second scheduler
is live** (`tags: { repin_suppressed: … }`, the #6781 detector). Widening the
band without splitting the counter **destroys that detector on day one** — every
run in steady state would report `suppressed > 0`.

**Sub-decision D2a — split the counter.** Two counters, keyed by which cadence
raised the 23505:

- `suppressed` — a `23505` on a **`daily:<date>`** key. Unchanged meaning: a
  genuine same-day double-fire. Remains the `repin_suppressed` tag input.
- `headsUpAlreadySent` — a `23505` on the **`headsup`** key. Expected steady
  state under the band; reported in `extra`, never in the tag.

**Stated trade-off (honest, not a win):** a second scheduler firing *only*
while an item sits in the T-7..T-3 band is now masked in the heads-up arm. It
is still caught in the daily arm, which **every** item enters within ≤5 days.
Detection is delayed, never lost. Recording this explicitly is the point —
`hr-observability-as-plan-quality-gate` and the "defense-relaxation must name
the new ceiling" sharp edge both apply: the ceiling here is "≤5 days to
detection via the daily arm", and it is named.

**Sub-decision D2b — `breach-art33` is documented as intentional, not fixed.**
Its 72h `dueRule` caps `daysUntilDue` at `2`, which is not `> DANGER_THRESHOLD
(2)`, so it still never enters the heads-up band and goes straight to the daily
danger cadence. **This is correct**: a "7-day heads-up" on a 72-hour clock is
incoherent — the item is in the danger band from the instant it is acknowledged.
Record it (a) as a code comment at the band predicate, (b) in the ADR-037
amendment, and (c) as a named test (T15).

### D3 — #6801: re-anchor the scan window to `acknowledged_at`, and count the residue

Two separable pieces, both in scope.

**D3a — Observability (the counter).** After the loop, one additional bounded
count query:

```ts
const { count: excludedCount } = await sb
  .from("email_triage_items")
  .select("id", { count: "exact", head: true })
  .eq("status", "acknowledged")
  .not("statutory_class", "is", null)
  .lt("acknowledged_at", scanFloor);
```

`head: true` transfers **no rows** — one index-backed count per daily run. That
is the deliberate DB round-trip decision the issue asks for: the cost is one
count/day against a table whose eligible population is single-digit, and the
alternative (a bound crossed silently) is the defect. Folded into the existing
`deadline-repin-sweep-complete` payload as `excluded`; **no second emit.** The
level escalates to `warn` when `excluded > 0 || suppressed > 0` (see
§Research Reconciliation row 1) so Better Stack carries it, satisfying the AC.
On query error, emit `excluded: null` (distinguishable from a real zero,
mirroring `statutory_repin_markers_purged`'s existing null-vs-zero discipline)
and never fail the run.

**D3b — Behavior: CLOSE the cliff by re-anchoring, do not merely accept it.**

> **The bound is kept; only its anchor moves.** `.gte("received_at", scanFloor)`
> → `.gte("acknowledged_at", scanFloor)`, same `DEADLINE_REPIN_SCAN_WINDOW_DAYS
> = 60`.

Reasoning:

1. **Eligibility is acknowledgement-derived, so the window should be too.** The
   issue states the defect precisely: "The bound is on `received_at`, but the
   thing that makes a row eligible is `status = 'acknowledged'`. Those are
   independent." Re-anchoring makes them dependent by construction — an item
   is pingable for 60 days *after it becomes pingable*.
2. **The scan stays bounded — but by row retention, not by an index.**
   *(Corrected at deepen-plan; the first draft claimed `acknowledged_at` was
   "indexed-eligible". It is not.)* `email_triage_items` carries four indexes
   (mig 102 §`email_triage_items_user_received_idx`, `…_llm_ceiling_idx`,
   `…_archived_idx`; mig 111 §`…_workspace_received_idx`) and **none of them
   names `acknowledged_at`** — nor can a bare `received_at >= X` predicate use
   the existing ones, since `received_at` is only ever the *second* column
   behind `user_id`/`workspace_id`. So today's scan is already a filtered scan,
   and re-anchoring does not make it worse. The real bound is the **365-day
   statutory retention** in mig 102 §`purge_email_triage_items`
   (`received_at < now() - interval '365 days'` for statutory rows, 7 days for
   the rest), which caps the `status='acknowledged' AND statutory_class IS NOT
   NULL` population regardless of which timestamp the window anchors on. For a
   single-operator product that population is small; the 60-day window is a
   *ping-lifetime* bound, not a *scan-cost* bound, and the plan says so rather
   than claiming an index that does not exist.
   **Re-evaluation trigger:** Phase 0.8 records the live row count. If the
   acknowledged+statutory population ever exceeds ~5,000 rows, add a partial
   index `(acknowledged_at) WHERE status = 'acknowledged' AND statutory_class
   IS NOT NULL` in a follow-up — deliberately not in this PR, which ships no
   migration.
3. **The overdue-ping ceiling is preserved, and becomes intentional.** Today the
   `received_at` bound *incidentally* terminates daily overdue pings ~30 days
   past due. Under the new anchor the terminator is "60 days after
   acknowledgement" — the same class of ceiling, now stated rather than
   accidental. Per the defense-relaxation sharp edge: **the new ceiling is
   named** and no defense is dissolved.
4. **`acknowledged_at` is WORM.** Mig 102's trigger makes it immutable once set,
   so the window cannot be gamed or drift under a live row.

**What the counter now counts** under D3b: rows acknowledged more than 60 days
ago and still unresolved — genuinely long-tail, certainly past due (every
registry rule's period is ≤ one calendar month from receipt, and receipt ≤
acknowledgement). Those are deliberately dropped, and now **visibly** dropped.
That is the residual accepted in writing.

**Phase 0 precondition (blocking).** Prove no `status='acknowledged'` row can
carry `acknowledged_at IS NULL`. Read every write path to `status`
(`server/email-triage/email-triage-status-handler.ts` → the mig 102/111 RPC,
which sets `acknowledged_at = CASE WHEN p_status = 'acknowledged' THEN now()
…`) and confirm no non-RPC writer exists (mig 102 §"status /
status_changed_at / acknowledged_at: writable ONLY under GUC"). **If any NULL
path exists**, fall back to a disjunctive bound
(`.or("received_at.gte.<floor>,acknowledged_at.gte.<floor>")`) and first verify
the vitest Supabase fake in
`test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts`
implements `.or()` — extend the fake if not. Record whichever branch is taken
in the ADR-037 amendment.

### D4 — #6802: the send-marker certifies DELIVERY, not dispatch

**Decision.** Three coordinated changes.

**D4a — zero-delivery falls through to email.** In `notifyOfflineUser`, the
channel choice stops being `subscriptions.length > 0` and becomes *did anything
land*:

```
subscriptions.length > 0
  → tally = sendPushNotifications(...)
  → tally.delivered === 0  →  fall through to the SAME email path the
                              zero-subscription branch already uses
  → tally.delivered  >  0  →  done (no email — no double-notify)
```

The existing `statutory-notify-zero-delivery` warn stays: it is now the
*fallback-fired* signal rather than the *nothing-happened* signal, and its
`message` is updated accordingly (per the "helper migration must preserve
operator dashboard message strings" sharp edge, the **op slug is unchanged** —
`statutory-notify-zero-delivery` — so any Sentry/Better Stack rule keyed on it
keeps firing; only the human-readable message moves).

**Class scope.** Apply the fallback to the three payload classes that
`notifications.ts` §`function mirrorNotifyFailure` **already** designates as
must-not-fail-silently: statutory `email_triage`, `cost_breaker_tripped`, and
`action_required` `inbox_item`. Rationale: that predicate already exists, is
already the file's definition of "a missed send is a real harm", and the email
fallback path *already runs* for all of these when a user has no subscriptions —
so this widens *when* an existing path fires, not *what* it does. Extract the
predicate as `mustNotFailSilently(payload)` and have `mirrorNotifyFailure`
consume it (single source of truth, no duplicate class list). Non-statutory
`email_triage` and `review_gate` keep today's behavior.

**D4b — `notifyOfflineUser` returns a delivery outcome.** Widen
`Promise<void>` → `Promise<NotifyOutcome>` where

```ts
export type NotifyChannel = "push" | "email" | "none";
export interface NotifyOutcome { channel: NotifyChannel; delivered: boolean; }
```

`sendEmailNotification` (and its four `send*EmailNotification` variants)
correspondingly return `boolean` instead of `void` — today they swallow the
Resend `error` into a `log.error`, which is why the caller cannot tell.
**Cross-consumer grep (`hr-type-widening-cross-consumer-grep`) run at plan
time:** `notifyOfflineUser` has 5 non-test call sites (`agent-runner.ts`,
`cc-dispatcher.ts`, `agent-on-spawn-requested.ts`, `email-on-received.ts`,
`cron-email-ingress-probe.ts`) plus 2 internal (`notifyInboxItem`);
`sendEmailNotification` has **zero** external callers (internal + tests only).
Return-type widening from `void` is additive — no call site breaks. The
`"never throws"` contract asserted at `agent-on-spawn-requested.ts` and
`email-on-received.ts` is preserved: the outer try/catch stays, and its catch
arm returns `{channel:"none", delivered:false}`.

**D4c — the marker is rolled back when nothing was delivered.** In the cron's
`deadline-repin` loop:

```
outcome = await notifyOfflineUser(row.user_id, {...})
if (!outcome.delivered) {
  DELETE FROM statutory_repin_send WHERE item_id = row.id AND tick_key = tickKey
  → do NOT increment `pinged`; increment `undelivered`
} else {
  pinged += 1
}
```

This is what makes AC "the marker must not certify a dispatch that delivered
nothing" true. It **deliberately restores** the pre-#6781 two-run self-heal —
but as a designed rollback rather than an accident of the un-pruned row. It
does not reintroduce the #6781 defect: a *delivered* send still writes a
durable marker, so a double-fire is still suppressed. Only a *provably
undelivered* send is retried.

Rollback failure is non-fatal and counted: on a failed DELETE, increment
`markerRollbackFailed` and fold it into the same sweep-complete emit (level
already escalated to `warn` when non-zero). Over-suppression is the strictly
worse outcome, so this arm is loud.

**Pruning on repeated non-410 failures: explicitly NOT done.** The issue asks
for a deliberate decision. Recorded rationale: pruning is a *destructive* action
on a subscription we cannot distinguish from a transient network failure, and
the fallback already guarantees the notice lands. Deleting a subscription on a
firewall-DROP would permanently remove a device that will work again the moment
the allowlist changes. `sendPushNotifications` keeps 410-only pruning; the
non-410 case is handled by fallback plus the existing `webpush-send-failed`
Sentry mirror. Re-evaluate only if `webpush-send-failed` volume shows a
persistent dead-endpoint population.

### D5 — #6813: rebuild the Incident-PIR signal scan around a PAST-TENSE production failure

**Decision.** Four changes to `plugins/soleur/skills/ship/SKILL.md` §"Incident-PIR
Gate" trigger 3, plus a real fixture test.

1. **Strip the threshold label from the haystack before scanning.** Remove lines
   matching `^brand_survival_threshold:` and `\*\*Brand-survival threshold:\*\*`
   (both forms — the frontmatter key and the `## User-Brand Impact` bold label).
   The gate's *trigger 2* already consumes the threshold declaration for its own
   purpose; trigger 3 must not double-count it as an outage verb.
2. **Strip the hypothetical framing lines.** Remove the `## User-Brand Impact`
   section's conditional lines — `**If this lands broken, …**`, `**If this
   leaks, …**` — and any line containing `if this lands`, `would break`,
   `could break`. That section's *job* is to describe a hypothetical failure;
   reading it as an incident report is a category error.
3. **Word-boundary and past-tense the outage verbs.** Drop bare `incident` (it
   matches `incidental`, and it matches the threshold literal). Replace with an
   explicit past-tense/report vocabulary:
   `\b(incident report|post-incident|postmortem|post-mortem|outage|went down|was down|took down|stopped working|silently (broke|broken|failing)|regression in prod|users? (could not|were unable to)|shipped broken|ran (broken|for [0-9]+ (days|weeks)) )`
   — final token set to be settled during implementation against the fixture
   corpus, subject to the two-direction AC below.
4. **`PROD_RE` is not weakened.** #6813 correctly notes it provides little
   discrimination on its own, but the discrimination now lives in `OUTAGE_RE`.
   Weakening `PROD_RE` would risk the false *negative* direction, which is the
   direction that matters (fail-toward-PIR). Leave it.

**The test is the deliverable, not the regex.** Add
`plugins/soleur/test/ship-incident-pir-gate.test.ts` +
`plugins/soleur/test/fixtures/ship-incident-pir-gate/`. Following the
`ship-undeferred-operator-step-gate.test.ts` precedent, but **stronger**: rather
than re-declaring a JS port of the ERE (which drifts), the test **extracts the
`OUTAGE_RE='…'` and `PROD_RE='…'` literals from `ship/SKILL.md`** and executes
the real `grep -qiE` pipeline against each fixture. A drift between the shipped
gate and the tested gate then becomes structurally impossible.

Fixtures pin **both** directions:

| Fixture | Expect | Source |
| --- | --- | --- |
| `preventive-hardening-single-user-incident.md` | **no signal** | the real #6782 plan body — the exact false positive #6813 reports, including its four tripping lines |
| `this-plan.md` | **no signal** | *this plan file* — it is a preventive-hardening `single-user incident` plan that says `prod` and `incident` throughout. If the fixed gate fires on it, the fix is not done. |
| `incidental-word.md` | **no signal** | a line containing `incidental` and nothing else outage-shaped |
| `chat-rls-outage.md` | **SIGNAL** | the known past production incident named in #6813 AC2 — cross-checked against `knowledge-base/engineering/operations/post-mortems/chat-rls-workspace-id-outage-postmortem.md` |
| `second-known-incident.md` | **SIGNAL** | a second real past incident PR body, so a single tuned phrase cannot satisfy AC2 |

### D6 — #6800: the FILENAME is authoritative; the disagreeing frontmatter ordinal is REMOVED

**Decision.** Zero file renames.

1. **Authority.** The filename ordinal is canonical. This takes the acceptance
   criterion's explicit second branch ("or one is authoritative and the other is
   removed"). Renaming is rejected: `ADR-NNN` occurs **11,784** times repo-wide,
   `check-adr-ordinals.sh` already treats the filename as the collision key, and
   every tool (`ship` Phase 5.5, `grok-pre-push-gate.sh`, CI) scans filenames.
2. **Single frontmatter format = no ordinal in frontmatter at all.** Delete the
   `adr:` key from every ADR that has one (~57 files across the two coexisting
   formats `adr: ADR-NNN` and `adr: NNN`; ~75 ADRs already carry no ordinal key,
   so *absence is already the plurality format*). Removing is strictly better
   than normalizing: it makes a future disagreement **impossible** rather than
   merely currently-absent. Phase 0 precondition: `git grep` for any consumer
   parsing the `adr:` key (none found at plan time — the only frontmatter
   parsers in `scripts/` are `frontmatter-strip` and `lint-agents-rule-budget.py`,
   neither of which reads `adr:`); if a consumer is found, switch to
   normalize-to-filename instead and record the change.
3. **Durable enforcement.** Extend `scripts/check-adr-ordinals.sh` with layer
   (4): fail if any `ADR-*.md` frontmatter contains an ordinal key. Already
   wired into `.github/workflows/ci.yml`, `grok-pre-push-gate.sh`, and `ship`
   Phase 5.5 — no new CI plumbing. Add `plugins/soleur/test/` coverage for
   layer 4 (positive + negative fixture) so the guard cannot silently loosen.
4. **Grep-enumerated citation sweep, adjudicated per citation.** Only two files
   ever disagreed (`ADR-036` fm=`034`, `ADR-037` fm=`035`), so the sweep is
   bounded to `ADR-034` and `ADR-035` citations. Enumerate with
   `grep -rn --include='*.md' --include='*.ts' --include='*.tsx' --include='*.sql' --include='*.sh' --include='*.yml' -E '\bADR-03[45]\b' . | grep -v '^\./\.git/'`
   and classify **each hit by content**, never by sed:
   - *means the dedup / plain-insert-catch-23505 / send-boundary idiom* → re-point to `ADR-037`
   - *means the template registry / code-static literals* → leave as `ADR-035`
   - *means the action-class registry* → leave as `ADR-034`
   Known re-point targets (`ADR-035` → `ADR-037`) in durable surfaces:
   `apps/web-platform/server/notifications.ts` (the two `notifyInboxItem`
   idempotency comments).
5. **Applied migrations are FROZEN — do not edit them.**
   `apps/web-platform/scripts/run-migrations.sh` records `git hash-object` of
   each file into `_schema_migrations.content_sha`, and
   `.github/actions/dev-migration-drift-probe/action.yml` surfaces any file whose
   content drifts from that recorded hash. A comment-only edit to `122_inbox_item.sql`
   or `135_statutory_repin_send.sql` would trip it. Instead, add a short
   **"Historical citations"** note to the `ADR-037-*.md` body naming the frozen
   artifacts (migrations 122, 135) that cite this decision by its retired
   frontmatter ordinal. Phase 0: read `dev-migration-drift-probe/action.yml`
   and confirm whether it **fails** or merely **reports**; if it only reports and
   the repo tolerates the row, prefer editing the citations in place and delete
   this carve-out.
6. **Scope-out (recorded, with reasoning):** the five pre-existing duplicate
   *filename* ordinals (`ADR-027`, `ADR-030`, `ADR-031`, `ADR-033`, `ADR-038`)
   are **not** renumbered here. They are already tracked as tech debt in
   `check-adr-ordinals.sh`'s `ALLOWED_COLLISIONS` allowlist with an explicit
   "renumber deferred to a single cleanup PR" comment. Renumbering them requires
   the full 11,784-citation rename sweep this plan deliberately avoids, and it
   is a different failure mode (two files, one ordinal) from the one #6800
   describes (one ordinal, two meanings). The allowlist **is** the tracker;
   no new issue is filed. Every in-repo `ADR-NNN` citation still resolves after
   this change, which is what #6800's AC3 requires.
7. **Remove the #6781 see-also pointer** — the two-line "See also / That
   filename/frontmatter ordinal collision with ADR-037 is tracked in #6800"
   block in `ADR-035-template-registry-code-static.md` (#6800 AC4). It becomes
   redundant once `ADR-037` carries no `adr: 035` frontmatter. Verify no
   remaining prose in that file implies the ordinal ambiguity.

---

## Architecture Decision (ADR/C4)

Detection fires: D4 introduces a **cross-cutting invariant every consumer must
honor** (a send marker means *delivered*, not *dispatched*), and D2/D3 change the
semantics of an existing decision's tick_key and scan bound.

### ADR

**Create `ADR-134-statutory-send-markers-certify-delivery-not-dispatch.md`**
(provisional ordinal — highest on `origin/main` at plan time is `ADR-132`;
`ship` Phase 5.5's ADR-Ordinal Collision Gate re-verifies against `origin/main`
before merge, and **any renumber must sweep this plan, `tasks.md`, and every AC
naming the ordinal in the same edit**).

Decision, one line: *a statutory send-marker row certifies that a notification
reached a recipient, not that a dispatch was attempted; a dispatch that
delivers to zero channels rolls its marker back so the next tick retries.*
Covers the `NotifyOutcome` contract, the zero-delivery email fallthrough, the
`mustNotFailSilently` class scope, the marker rollback, and the explicit
non-decision on non-410 pruning. `## Alternatives Considered` must carry:
prune-on-repeated-failure; leave the marker and rely on the warn; make
`notifyOfflineUser` throw.

**Amend `ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`**
(the governing decision for the plain-insert-catch-23505 idiom and its #6781
send-boundary extension). Its `## Decision` currently implies `headsup` is a
one-shot at an exact day. Amend to record: (a) `headsup` now keys a **band**
(T-7..T-3), (b) a `23505` on `headsup` is **expected steady state** and is
counted separately from the double-fire signal, (c) the repin scan is anchored
on `acknowledged_at`, not `received_at`, (d) `breach-art33` never enters the
heads-up band **by design**, (e) the "Historical citations" note from D6.5.
Add the alternatives (keep the equality + add a traversal counter; per-day
heads-up keys) to `## Alternatives Considered`.

Sequencing: both land in this PR. Neither is soak-gated; no `status: adopting`.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) were **read**, not
grepped, per the C4 completeness mandate. Enumeration for this change:

| Category | Item | Modeled? | Action |
| --- | --- | --- | --- |
| External human actor | `founder` (workspace Owner, the notice recipient) | yes (`model.c4` §`founder`) | none |
| External human actor | `emailSender` (Inbound Correspondent) | yes (`model.c4` §`emailSender`) | none — no new correspondent |
| External system | `resend` (outbound statutory notifications) | yes (`model.c4` §`resend = system "Resend"`, edges `webapp -> resend` and `api -> resend`) | **update descriptions** — the outbound edge is now also the *push-failure fallback*, which is a materially different reason for the edge to carry traffic |
| External system | **Web Push services** (FCM / APNs / WNS) — the endpoint host each `push_subscriptions.endpoint` resolves to | **NO — absent from the model** | **ADD** `pushService = system "Web Push Services" { #external; description … }` + edge `webapp -> pushService "Web Push delivery (VAPID); non-410 failures fall back to Resend email — the WNS egress DROP (#5046 PR-2) is the known trigger" { technology "HTTPS (Web Push / VAPID)" }` and the container-level edge from `platform.webapp.api`. This is the external system whose *failure* this whole change is about; leaving it unmodeled would make the C4 misleading about exactly the edge under repair. |
| Container / data store | `platform.infra.supabase` (`email_triage_items`, `statutory_repin_send`) | yes | none — no new store |
| Access relationship | who may read/receive a statutory item | unchanged (Owner-shared reads per ADR-066; send path stays single-recipient — the mig-135 note 4 / T12 tripwire is untouched) | none |

`views.c4`: add `pushService` to the `include` list of **both** the `context`
view and the `containers` view (an element not included in a view does not
render). Run `apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts` after editing — a `view … include` naming an undefined
element fails there, not at `tsc`.

`spec.c4`: read; the `#external` tag and the `system`/`actor` kinds it defines
already cover the new element. No change.

---

## Infrastructure (IaC)

**Skipped — no new infrastructure.** No server, systemd unit, cron job, vendor
account, DNS record, TLS cert, secret, firewall rule, or monitoring webhook is
introduced. The Phase 2.8 detection scan over this plan finds no host-shell
step, no secrets-manager write step, no service-unit step, no vendor-dashboard
step, and no new vendor. All edits land under
`apps/web-platform/{server,lib,test}/`, `plugins/soleur/{skills,test}/`,
`scripts/`, and `knowledge-base/`. The Sentry alert surface is unchanged: every
op slug this plan touches (`deadline-repin-sweep-complete`,
`statutory-notify-zero-delivery`, `webpush-send-failed`,
`deadline-repin-marker-insert-failed`) already exists and keeps its name.

---

## Observability

```yaml
liveness_signal:
  what: >
    The existing per-run `deadline-repin-sweep-complete` emit from
    apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts,
    extended with `excluded`, `headsUpAlreadySent`, `undelivered`, and
    `markerRollbackFailed`. Plus the existing Sentry cron monitor
    `cron-email-ingress-probe`.
  cadence: once per daily cron run (06:00 UTC).
  alert_target: >
    Sentry (always, via captureMessage) AND Better Stack (only when the emit
    escalates to warn — level_int >= 40 clears
    apps/web-platform/infra/vector.toml [transforms.app_container_warn_filter]).
    Escalation fires when excluded > 0 || suppressed > 0 || undelivered > 0 ||
    markerRollbackFailed > 0.
  configured_in: >
    apps/web-platform/infra/sentry/cron-monitors.tf (existing monitor,
    unchanged); apps/web-platform/infra/vector.toml (existing filter,
    unchanged — the plan changes the EMIT LEVEL, not the filter).

error_reporting:
  destination: >
    Sentry via warnSilentFallback/reportSilentFallback (server/observability.ts),
    tags {feature, op, repin_suppressed}. NOTE: the `tags` passthrough is being
    ADDED to infoSilentFallback in this PR — it is currently dropped, so
    repin_suppressed has never reached Sentry (see Research Reconciliation).
  fail_loud: >
    Yes for the delivery path. A statutory notification that reaches zero
    channels emits op=statutory-notify-zero-delivery at WARN, and the cron rolls
    the marker back so the next tick retries — the condition self-heals AND is
    visible. The excluded-count query fails soft (excluded: null, run continues)
    because an observability query must never take down the retention purge or
    the ingress probe that share the run.

failure_modes:
  - mode: Push delivers to zero devices on a statutory item (the #6802 trigger).
    detection: >
      warnSilentFallback op=statutory-notify-zero-delivery from
      server/notifications.ts (in-surface: emitted from notifyOfflineUser
      itself, after the tally is known — not inferred from a host-side proxy).
      Structured fields discriminate the competing hypotheses in ONE event:
      {attempted, delivered, channel, fallbackDelivered, emailId} separates
      "no subscriptions" from "subscriptions all failed" from "fallback also
      failed".
    alert_route: Sentry issue alert + Better Stack (warn clears the Vector filter).
  - mode: Email fallback ALSO fails (total silence survives the fix).
    detection: >
      NotifyOutcome.channel === "none" → the cron rolls the marker back and
      increments `undelivered` in the sweep-complete emit, which escalates the
      emit to warn. Distinct counter from `pinged` — a run can no longer report
      a ping it did not deliver.
    alert_route: Sentry + Better Stack.
  - mode: Marker rollback DELETE fails (an undelivered send stays certified).
    detection: markerRollbackFailed counter in the sweep-complete emit (escalates to warn).
    alert_route: Sentry + Better Stack.
  - mode: Eligible acknowledged rows fall outside the scan window (the #6801 cliff residue).
    detection: >
      `excluded` count in the sweep-complete emit, from a second bounded
      head:true count query. Non-zero escalates the emit to warn.
    alert_route: Better Stack + Sentry.
  - mode: A second scheduler double-fires the daily band.
    detection: >
      `suppressed` (daily-key 23505s only, after the D2a split) and the
      repin_suppressed Sentry tag — which actually reaches Sentry only after
      this PR adds tags passthrough to infoSilentFallback.
    alert_route: Sentry tag query `op:deadline-repin-sweep-complete repin_suppressed:yes`.
  - mode: An item traverses the heads-up band unpinged (the #6799 defect itself).
    detection: >
      Structurally prevented by the band predicate (D2), and pinned by test T14
      (two jittered runs straddling the boundary → exactly one ping).
    alert_route: n/a — prevented, not detected.

logs:
  where: >
    pino → stdout → Vector (apps/web-platform/infra/vector.toml) → Better Stack
    for level_int >= 40; Sentry for all levels via the observability helpers.
  retention: Better Stack + Sentry vendor defaults (unchanged by this PR).

discoverability_test:
  command: >
    cd apps/web-platform && ./node_modules/.bin/vitest run
    test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts
    test/notifications.test.ts
  expected_output: >
    All suites pass, including the new T14 (jitter straddle → exactly one
    heads-up), T15 (breach-art33 never enters the heads-up band), T16
    (excluded count non-zero for an acknowledged-but-out-of-window row), T17
    (non-410 push rejection → an email IS sent), T18 (push success → NO email),
    T19 (total failure → marker rolled back, `pinged` not incremented).
  # No host-shell access anywhere. Every signal above is reachable from a test
  # run, a Sentry query, or a Better Stack search.
```

### Soak Follow-Through Enrollment

**Not applicable.** No acceptance criterion is time-gated: there is no
"stays at ~0 for N days post-deploy" condition, no ADR status flip from
`adopting → accepted`, and no post-deploy soak. Every AC is verifiable
pre-merge from tests, greps, or a CLO review artifact. No
`scripts/followthroughs/` probe, no `soleur:followthrough` directive, and no
`follow-through` label are required.

### Affected-surface observability (§2.9.2)

The delivery path is a **blind execution surface** in the relevant sense — the
operator cannot inspect whether a push landed on their own device from the
server side. The `failure_modes` entries above satisfy the extension: each
`detection` names an **in-surface** probe (emitted from `notifyOfflineUser` /
the cron loop itself, downstream of the tally), and the zero-delivery event's
structured fields (`attempted`, `delivered`, `channel`, `fallbackDelivered`)
discriminate *no-subscriptions* vs *all-pushes-failed* vs *fallback-also-failed*
in a single event rather than via a boolean that fires for one shape only.

---

## Domain Review

**Domains relevant:** Legal, Engineering, Product

> **Method note.** This plan was authored inside a one-shot Task subagent, which
> has no `Task` tool and therefore cannot spawn domain-leader subagents. The
> assessments below are inline. The **CLO review is not delegated to this
> assessment** — #6798's acceptance requires a real `soleur:legal:clo` agent
> review of the shipped wording, and that is an explicit, blocking `/work`
> Phase 1 task (§Implementation Phases 1.4) where the `Task` tool is available.

### Legal

**Status:** reviewed (inline) — blocking `soleur:legal:clo` agent review scheduled as Phase 1.4

**Assessment.** The core question is **detrimental reliance**: #6781 made the
backstop more dependable, and dependability invites the recipient to stop
tracking their own clock. Three findings carried into the plan:

1. The Art. 33 gap is real and asymmetric — the 72h clock runs from **awareness
   of the breach** (Art. 33(1)), so a date computed from `received_at` can be
   **later than the true deadline**. Presenting it with the same confidence as a
   `dsar-art15` date is the specific over-claim. D1's `clockOrigin` field encodes
   this rather than papering it with a generic disclaimer.
2. A disclaimer alone is insufficient if the copy still reads as authoritative.
   The reminder's *verb* must change ("computed reminder", "estimated") — the
   caveat cannot be the only signal.
3. `service-of-process` is a third case: the instrument states its own deadline.
   Its `dueRule.label` already says so; `clockOrigin: "instrument"` makes that
   machine-readable and consistent with the other two.

**GDPR assessment (Phase 2.7).** The `hr-gdpr-gate-on-regulated-data-surfaces`
canonical regex does not fire (no schema, no migration, no auth flow, no `.sql`,
no new API route). Expansion trigger **(b)** *does* fire (`brand_survival_threshold:
single-user incident`). Inline assessment:

- **No new processing activity.** The change routes an existing notification to
  an existing channel for the same recipient. Article 30 register needs no new
  Processing Activity row (verified: the statutory-triage PAs already cover
  push + email notification to the operator).
- **No new personal data category** and no new recipient/processor. Resend is
  already the outbound processor; Web Push services already receive the
  encrypted payload today (their absence from C4 is a *modelling* gap, corrected
  here, not a disclosure gap).
- **Data minimisation preserved.** The disclaimer is static, server-authored
  text. TR3 hygiene holds: the reminder title still carries only the
  registry-derived due string, never the third-party subject.
- **Transparency (Art. 12(1)) improves.** The not-legal-advice framing makes the
  computed nature of the date explicit — this is a net compliance gain, not a
  risk.
- **No Critical finding**, so no `compliance-posture.md` Active Items write and
  no `compliance/critical` issue. `/soleur:gdpr-gate` runs at `/work` Phase 1.4
  alongside the CLO review, and any Critical it surfaces is folded in there.

### Engineering

**Status:** reviewed (inline)

**Assessment.** Four risks, all addressed above:

1. **The heads-up band silently kills the #6781 double-fire detector.** Highest-
   value finding in this plan; handled by D2a's counter split with a stated
   ≤5-day detection-delay ceiling.
2. **`infoSilentFallback` drops `tags`.** The #6781 `repin_suppressed` tag has
   never reached Sentry. Folded in (2 non-test callers — contained widening).
3. **`.gte("acknowledged_at", …)` presumes non-null.** Blocking Phase 0
   precondition with a named `.or()` fallback and a fake-extension note.
4. **Applied migrations are content-hashed.** `run-migrations.sh` writes
   `git hash-object` into `_schema_migrations.content_sha` and
   `dev-migration-drift-probe` compares it — so the #6800 sweep must not touch
   migrations 122/135. Carve-out recorded in D6.5 with a Phase 0 re-check.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no `Task` tool in this subagent; see method note)
**Skipped specialists:** `ux-design-lead` — **N/A, not skipped**: the mechanical
UI-surface override does not fire. Checked `## Files to Edit` and `## Files to
Create` against
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`'s glob
superset (`components/**/*.{tsx,jsx,vue,svelte}`, `app/**/page.tsx`,
`app/**/layout.tsx`, `app/**/template.tsx`, `pages/**`, `routes/**`,
`**/*.{njk,html,vue,svelte,astro}`) — **zero matches**. No new page, route,
component, modal, or flow. The email/push copy change is a
"pure copy tweak with no structural/layout change", which that same reference
lists under **Excluded (no wireframe required)**.
**Pencil available:** N/A (no UI surface)

#### Findings

The one product-shaped judgment is #6798's tone: a disclaimer that is too heavy
undermines the notice's urgency (the operator stops reading it), and one that is
too light does not discharge the reliance concern. Resolution: **short caveat in
the push** (length-constrained surface, must stay actionable), **full framing in
the email** (where the operator has room to read it). The CLO agent review in
Phase 1.4 adjudicates the exact wording; the copy is not frozen in this plan
beyond the placement decision.

---

## Open Code-Review Overlap

Two open `code-review` issues mention paths this plan touches:

- **#3739** — *review: extract `reportSilentFallbackWithUser` helper (collapse 11-site `withIsolationScope`+`setUser` duplication)*, names `server/observability.ts`.
  **Disposition: acknowledge.** This plan's `observability.ts` edit is a
  three-line `extraTags` merge inside `infoSilentFallback` for sibling parity —
  a different concern from the `withIsolationScope` duplication #3739 tracks,
  and folding an 11-site refactor into a six-issue PR would blur the diff.
  #3739 stays open.
- **#3593** — *review: extract post-synthetic-checks child composite (deferred per ADR-027)*, matches only on the string `architecture/decisions`.
  **Disposition: acknowledge.** A false-positive path match: #3593 is about a
  GitHub Actions composite, unrelated to the ADR corpus. No overlap.

No other open code-review issue names
`cron-email-ingress-probe.ts`, `notifications.ts`, `statutory-rules.ts`,
`ship/SKILL.md`, or `diagrams/model.c4`.

---

## Files to Edit

### Statutory copy (#6798)

- `apps/web-platform/lib/email-triage/statutory-rules.ts` — add `ClockOrigin` type, `clockOrigin` field on `StatutoryRule`, populate all four rules, add `NOT_LEGAL_ADVICE_NOTICE` + `clockOriginCaveat()`.
- `apps/web-platform/server/notifications.ts` — push body (`payload.isStatutory ? …` branch in `sendPushNotifications`) and `sendEmailTriageEmailNotification` (`heading` / `bodyHtml` / `footnoteHtml`).
- `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` — reminder title verb ("computed"/"estimated" framing).

### Repin predicate + scan window (#6799, #6801)

- `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` —
  band predicate + `inHeadsUpBand` tick_key; `suppressed` / `headsUpAlreadySent`
  counter split; scan `.gte("acknowledged_at", scanFloor)`; excluded-count query;
  level-escalating sweep-complete emit; `breach-art33` comment; the
  `DEADLINE_REPIN_HEADS_UP_DAY` and `DEADLINE_REPIN_SCAN_WINDOW_DAYS` doc
  comments (both currently justify the *old* semantics and would become false).
- `apps/web-platform/server/observability.ts` — `infoSilentFallback` `extraTags` merge (mirror the `report`/`warn` implementations exactly).

### Delivery path (#6802)

- `apps/web-platform/server/notifications.ts` — `NotifyChannel`/`NotifyOutcome` types; `mustNotFailSilently(payload)` extracted and consumed by `mirrorNotifyFailure`; `notifyOfflineUser` zero-delivery fallthrough + return value; `sendEmailNotification` and the four `send*EmailNotification` variants return `boolean`; `statutory-notify-zero-delivery` message updated (**op slug unchanged**).
- `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` — consume `NotifyOutcome`; marker rollback DELETE; `undelivered` + `markerRollbackFailed` counters; `pinged` increments only on delivery.

### Ship gate (#6813)

- `plugins/soleur/skills/ship/SKILL.md` — §"Incident-PIR Gate" trigger 3: haystack pre-strip, rewritten `OUTAGE_RE`, unchanged `PROD_RE`, plus a `**Why:**` line citing #6813 and the #6782 false positive.

### ADR corpus (#6800)

- `knowledge-base/engineering/architecture/decisions/ADR-*.md` — delete the `adr:` frontmatter key from every file that has one (~57 files; enumerate with `grep -l '^adr:' knowledge-base/engineering/architecture/decisions/ADR-*.md`).
- `knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md` — remove the two-line #6781 see-also block.
- `knowledge-base/engineering/architecture/decisions/ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md` — the D2/D3 amendment + the "Historical citations" note.
- `apps/web-platform/server/notifications.ts` — re-point the two `ADR-035` dedup-idiom comments to `ADR-037`.
- `scripts/check-adr-ordinals.sh` — layer (4): reject any frontmatter ordinal key.
- Any further hit from the D6.4 enumeration, adjudicated per citation.

### ADR / C4 deliverables

- `knowledge-base/engineering/architecture/diagrams/model.c4` — add `pushService` external system + its two edges; update the `resend` element/edge descriptions to name the fallback.
- `knowledge-base/engineering/architecture/diagrams/views.c4` — add `pushService` to the `context` and `containers` `include` lists.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-134-statutory-send-markers-certify-delivery-not-dispatch.md` *(ordinal provisional)*
- `plugins/soleur/test/ship-incident-pir-gate.test.ts`
- `plugins/soleur/test/fixtures/ship-incident-pir-gate/preventive-hardening-single-user-incident.md`
- `plugins/soleur/test/fixtures/ship-incident-pir-gate/this-plan.md`
- `plugins/soleur/test/fixtures/ship-incident-pir-gate/incidental-word.md`
- `plugins/soleur/test/fixtures/ship-incident-pir-gate/chat-rls-outage.md`
- `plugins/soleur/test/fixtures/ship-incident-pir-gate/second-known-incident.md`
- `plugins/soleur/test/adr-frontmatter-ordinal-guard.test.sh` *(layer-4 positive + negative fixtures for `check-adr-ordinals.sh`)*
- `knowledge-base/project/specs/feat-one-shot-6798-6813-statutory-notify-adr-ship-gate/clo-copy-review.md` *(the CLO agent's verdict, verbatim)*
- `knowledge-base/project/specs/feat-one-shot-6798-6813-statutory-notify-adr-ship-gate/tasks.md`

## Files NOT to Edit (recorded)

- `apps/web-platform/supabase/migrations/122_inbox_item.sql`, `135_statutory_repin_send.sql` — applied + content-hashed (D6.5). Their stale `ADR-035` citations are addressed by the ADR-037 "Historical citations" note.
- `apps/web-platform/supabase/migrations/` — **no new migration.** `acknowledged_at` already exists; the mig-135 `tick_key` CHECK already permits exactly `headsup` and `daily:YYYY-MM-DD`.
- `knowledge-base/project/{plans,specs,brainstorms,learnings}/**` and `**/archive/**` — point-in-time records; excluded from the D6.4 ADR-citation sweep (they legitimately cite the ordinal as it stood).

---

## Implementation Phases

### Phase 0 — Preconditions (blocking; no code)

0.1 `acknowledged_at` non-nullability. Read `server/email-triage/email-triage-status-handler.ts` and mig 102/111's status RPC; confirm every `status='acknowledged'` write goes through the RPC and sets `acknowledged_at`. **If not provable → take the `.or()` branch** and verify the test fake implements `.or()`.
0.2 Migration drift probe severity. Read `.github/actions/dev-migration-drift-probe/action.yml`; determine whether a content_sha mismatch **fails** or **reports**. Record; if report-only, drop the D6.5 carve-out and edit the migration citations in place.
0.3 `adr:` frontmatter consumers. `git grep -rn "^adr:\|\badr\b.*frontmatter" scripts/ plugins/ apps/ .github/` — confirm zero parsers. If a consumer exists, switch D6.2 to normalize-to-filename.
0.4 Test-runner form. Confirm `apps/web-platform` runs **vitest** (`./node_modules/.bin/vitest run <path>`, **never** `bun test`, **never** `npm run -w`) and that `vitest.config.ts`'s `include:` globs cover `test/server/inngest/**` and `test/*.test.ts`. Confirm `plugins/soleur/test/*.test.ts` runs under `bun test`.
0.5 Next free ADR ordinal — `ls knowledge-base/engineering/architecture/decisions/ | grep -oE '^ADR-[0-9]{3}' | sort -u | tail -1` against `origin/main`. Adopt the next free; if it is not 133, **sweep this plan + tasks.md + every AC naming the ordinal in the same edit**.
0.6 Enumerate the D6.4 citation corpus and write the per-citation adjudication table into `tasks.md` before editing anything.
0.7 Capture the "before" state of the #6813 gate: run the **current** `OUTAGE_RE`/`PROD_RE` against all five fixtures and record which fire. The false-positive fixtures must fire *before* the fix (otherwise the fixture does not reproduce the bug) and not fire *after*.

### Phase 1 — #6798 statutory framing (RED → GREEN → CLO)

1.1 RED: tests asserting the push body, the email body, and the reminder title each carry the not-legal-advice framing, and that a `clockOrigin: "awareness"` rule (`breach-art33`) renders a **different** caveat from a `"receipt"` rule (`dsar-art15`).
1.2 GREEN: `statutory-rules.ts` registry widening + copy constants.
1.3 GREEN: render at all three surfaces.
1.4 **BLOCKING GATE — `Task(soleur:legal:clo)`** with the rendered copy for all three surfaces + both caveat variants. Also run `/soleur:gdpr-gate` against the diff. Record the CLO verdict verbatim in `specs/<branch>/clo-copy-review.md`; apply every change the CLO requires; re-run 1.1's tests. **Do not proceed to Phase 2 until the CLO has returned.**

### Phase 2 — #6799 heads-up band + counter split (RED → GREEN)

*(Contract change before consumer change: the tick_key/counter semantics move first, then the emit that reports them.)*
2.1 RED T14: two runs with jittered clocks straddling the T-7 boundary (`D−8 06:00:10` → `D−7 06:00:40`, per the issue's table) → **exactly one** heads-up email. Must fail on `main`.
2.2 RED T15: a `breach-art33` item never produces a `headsup` marker; its first ping carries a `daily:` key.
2.3 RED T14b: an item observed on five consecutive days across the band → exactly one heads-up, `suppressed === 0`, `headsUpAlreadySent === 4`.
2.4 GREEN: band predicate + `inHeadsUpBand` tick_key + counter split; update the `DEADLINE_REPIN_HEADS_UP_DAY` doc comment and the mig-135-referencing loop comment so neither asserts the retired equality.

### Phase 3 — #6801 scan re-anchor + excluded counter (RED → GREEN)

3.1 RED T16: a row `received_at` 90 days ago, `acknowledged_at` yesterday, due tomorrow → **is scanned and pinged** (fails on `main`).
3.2 RED T16b: a row `acknowledged_at` 90 days ago → excluded, and `excluded >= 1` appears in the sweep-complete payload at **warn** level.
3.3 RED: `infoSilentFallback` passes `tags` through (mirror an existing `warnSilentFallback` tag test).
3.4 GREEN: `observability.ts` `extraTags` merge; the `.gte("acknowledged_at", …)` swap; the `head:true` count query with null-on-error; the level-escalating emit. Rewrite the `DEADLINE_REPIN_SCAN_WINDOW_DAYS` doc comment (it currently justifies 60 in `received_at` terms).

### Phase 4 — #6802 delivery contract (RED → GREEN)

4.1 RED T17: a non-410 `webpush` rejection on a statutory payload → **an email IS sent** (assert on the `resend` spy, per the existing harness's "count real send calls" discipline).
4.2 RED T18: push succeeds → **no** email (no double-notify).
4.3 RED T19: push fails **and** email fails → marker for `(item, tickKey)` is deleted, `pinged` is **not** incremented, `undelivered === 1`.
4.4 RED T20: a `cost_breaker_tripped` payload with zero delivery also falls back (class-scope pin).
4.5 GREEN: `mustNotFailSilently` extraction; `NotifyOutcome`; `sendEmailNotification` boolean returns; the fallthrough; the cron rollback + counters.
4.6 Cross-consumer sweep: `tsc --noEmit` in `apps/web-platform`, then confirm each of the 5 external `notifyOfflineUser` call sites still compiles and that the two "never throws" comments remain true.

### Phase 5 — #6813 ship gate (RED → GREEN)

5.1 Build the five fixtures (Phase 0.7 already proved the false-positive ones fire today).
5.2 RED: `ship-incident-pir-gate.test.ts` extracting `OUTAGE_RE`/`PROD_RE` from `ship/SKILL.md` and executing the real `grep -qiE` pipeline — 3 no-signal + 2 signal. Must fail on `main`.
5.3 GREEN: haystack pre-strip + rewritten `OUTAGE_RE` in `ship/SKILL.md`, with the `**Why:**` line.
5.4 Iterate the verb set against the fixtures until all five pass **in both directions**. If a genuine-incident fixture cannot be made to fire without also firing a hypothetical fixture, prefer firing (fail-toward-PIR) and record the residual in the test.

### Phase 6 — #6800 ADR ordinals (mechanical, per-citation)

6.1 Delete the `adr:` key from every ADR carrying one.
6.2 Apply the Phase 0.6 adjudication table: re-point dedup-idiom `ADR-035` citations to `ADR-037`; leave template-registry and action-class citations alone.
6.3 Remove the `ADR-035` see-also block.
6.4 `check-adr-ordinals.sh` layer 4 + its guard test.
6.5 Residual verification: `grep -rnE '\bADR-[0-9]{3}\b'` over the edited files and confirm every ordinal resolves to an existing `ADR-NNN-*.md`.

### Phase 7 — ADR + C4 deliverables

7.1 Author `ADR-134` (provisional ordinal) via `/soleur:architecture`.
7.2 Amend `ADR-037` (D2/D3 semantics + Historical citations note).
7.3 Edit `model.c4` (`pushService` + edges + `resend` description) and `views.c4` (`include` in both views).
7.4 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 8 — Full-suite exit gate

8.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
8.2 `cd apps/web-platform && ./node_modules/.bin/vitest run`
8.3 `bun test plugins/soleur/test/` (includes `components.test.ts`)
8.4 `bash scripts/check-adr-ordinals.sh` → exit 0
8.5 The repo lints wired in `.github/workflows/ci.yml` (rule-id lint, AGENTS budget lint)

---

## Acceptance Criteria

### Pre-merge (PR)

**#6798**

- **AC1** `apps/web-platform/lib/email-triage/statutory-rules.ts` exports `NOT_LEGAL_ADVICE_NOTICE` and `clockOriginCaveat`, and every entry in `STATUTORY_RULES` carries a `clockOrigin` — verified by a type-level test (adding a rule without `clockOrigin` fails `tsc`).
- **AC2** `breach-art33`'s rendered caveat differs from `dsar-art15`'s and names the awareness clock; asserted by a test, not by eyeball.
- **AC3** A statutory push body, a statutory email body, and the cron reminder title each contain the not-legal-advice framing; three assertions, one per surface.
- **AC4** `knowledge-base/project/specs/feat-one-shot-6798-6813-statutory-notify-adr-ship-gate/clo-copy-review.md` exists, is non-empty, names the reviewing agent, and records a verdict. Every CLO-required change is applied (the file states so explicitly).
- **AC5** `grep -rn "legal advice" apps/web-platform/` returns **> 0** hits (the issue's own reproduction command, inverted).

**#6799**

- **AC6** Test T14 drives two jittered runs straddling the T-7 boundary and asserts **exactly one** heads-up email — not zero, not two. Verified RED on `main` before the fix.
- **AC7** Test T14b: five consecutive in-band days → one heads-up, `suppressed === 0`, `headsUpAlreadySent === 4`. This is the AC that proves the #6781 double-fire detector survived the band.
- **AC8** Test T15 pins `breach-art33`: no `headsup` marker is ever written for it, and the behavior is documented in **both** a code comment at the band predicate and the ADR-037 amendment.

**#6801**

- **AC9** A run whose scan excludes eligible acknowledged rows emits `deadline-repin-sweep-complete` at **warn** level (`level_int >= 40`, so `apps/web-platform/infra/vector.toml`'s `app_container_warn_filter` passes it to Better Stack) carrying a non-zero `excluded`. Asserted on the `warnSilentFallbackSpy`, not on `infoSilentFallbackSpy`.
- **AC10** Test T16: a row received 90 days ago but acknowledged yesterday **is** scanned and pinged. RED on `main`.
- **AC11** Test T16b: a row acknowledged 90 days ago is excluded **and** counted.
- **AC12** `infoSilentFallback` passes `tags` through to `Sentry.captureMessage` — asserted by a test that reads the spy's `tags` argument. (Closes the silently-dropped `repin_suppressed` tag.)
- **AC13** The behavioral decision is recorded in writing: the ADR-037 amendment states that the scan is anchored on `acknowledged_at`, why, and what the residual excluded population is.

**#6802**

- **AC14** Test T17: a non-410 `webpush` rejection on a statutory payload results in an email send observed on the **`resend` spy** (the harness's existing "count real send calls" seam, not a stubbed `notifyOfflineUser`).
- **AC15** Test T18: a successful push results in **zero** `resend` sends for the same tick.
- **AC16** Test T19: push **and** email both fail → the `(item_id, tick_key)` marker is deleted, `pinged` is not incremented, `undelivered === 1`.
- **AC17** `git grep -n "statutory-notify-zero-delivery" apps/web-platform/` still returns the op slug (unchanged), and its `extra` payload carries `{attempted, delivered, channel, fallbackDelivered}`.
- **AC18** `ADR-134` (or the Phase 0.5 ordinal actually adopted) exists, is non-empty, carries `## Status`/`## Context`/`## Decision`/`## Consequences`, and its `## Alternatives Considered` names the prune-on-repeated-failure option and why it was rejected.

**#6813**

- **AC19** `plugins/soleur/test/ship-incident-pir-gate.test.ts` **extracts** `OUTAGE_RE` and `PROD_RE` from `plugins/soleur/skills/ship/SKILL.md` (rather than re-declaring them) and executes the real `grep -qiE` pipeline. A test that hard-codes a copy of the regex does not satisfy this AC.
- **AC20** The `preventive-hardening-single-user-incident.md` fixture (the real #6782 plan body, containing all four lines #6813 lists) produces **no** incident signal.
- **AC21** The `this-plan.md` fixture — a copy of this plan file — produces **no** incident signal.
- **AC22** The `chat-rls-outage.md` and `second-known-incident.md` fixtures **do** produce a signal.
- **AC23** A line whose only outage-shaped token is `incidental` produces **no** signal.
- **AC24** All five fixture expectations were verified RED against the pre-fix regex in Phase 0.7 (recorded in the PR body), so the fixtures demonstrably reproduce the bug.

**#6800**

- **AC25** `grep -l '^adr:' knowledge-base/engineering/architecture/decisions/ADR-*.md` returns **zero** files.
- **AC26** `bash scripts/check-adr-ordinals.sh` exits 0, and its new layer 4 fails on a fixture ADR carrying an `adr:` key (negative test).
- **AC27** The two-line #6781 see-also block is gone from `ADR-035-template-registry-code-static.md`, and no remaining prose in that file references the ordinal ambiguity.
- **AC28** Every `ADR-NNN` citation in every **edited** file resolves to an existing `knowledge-base/engineering/architecture/decisions/ADR-NNN-*.md`; verified by enumerating with `grep -rhoE '\bADR-[0-9]{3}\b'` over the edited set and testing each ordinal for a matching file. Grep-enumerated, not sampled.
- **AC29** Migrations `122_inbox_item.sql` and `135_statutory_repin_send.sql` are **unchanged** (`git diff --name-only origin/main...HEAD | grep supabase/migrations` returns nothing) unless Phase 0.2 proved the drift probe is report-only, in which case their citations are corrected and the PR body records the Phase 0.2 finding.

**Cross-cutting**

- **AC30** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- **AC31** `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite green.
- **AC32** `bun test plugins/soleur/test/` — full suite green, including `components.test.ts`.
- **AC33** `model.c4` defines `pushService` with `#external`, both its edges exist, and `views.c4` includes it in **both** the `context` and `containers` views; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC34** PR body carries `Closes #6798`, `Closes #6799`, `Closes #6800`, `Closes #6801`, `Closes #6802`, `Closes #6813` (in the **body**, not the title, per `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

**None.** Every step is automatable in-session or in CI:

- Migration apply — **not applicable** (no migration).
- Container restart / Inngest function sync — the `web-platform-release.yml` pipeline already restarts the container on any merge touching `apps/web-platform/**`; the merge **is** the remediation.
- `gh pr ready` / `gh pr merge --squash --auto` / `gh issue close` — handled by `/soleur:ship` via the `gh` CLI.
- Post-deploy verification — the Sentry cron monitor `cron-email-ingress-probe` already checks in daily; `deadline-repin-sweep-complete` is queryable from Sentry and (on escalation) Better Stack. No dashboard eyeballing, no host access.

---

## Test Scenarios

| ID | Scenario | Issue | Asserts |
| --- | --- | --- | --- |
| T14 | Two jittered runs straddle T-7 (`D−8 06:00:10` → `D−7 06:00:40`) | #6799 | exactly 1 heads-up email |
| T14b | Five consecutive in-band days | #6799 | 1 heads-up; `suppressed === 0`; `headsUpAlreadySent === 4` |
| T15 | `breach-art33` item through its whole life | #6799 | never a `headsup` marker; first ping is `daily:` |
| T16 | received 90d ago, acknowledged yesterday, due tomorrow | #6801 | scanned **and** pinged |
| T16b | acknowledged 90d ago | #6801 | excluded; `excluded >= 1`; emit at **warn** |
| T16c | excluded-count query errors | #6801 | `excluded: null`; run still completes; probe steps 3-5 unaffected |
| T16d | `infoSilentFallback` with `tags` | #6801 | tag reaches `Sentry.captureMessage`'s `tags` |
| T17 | non-410 webpush rejection, statutory payload | #6802 | 1 `resend` send |
| T18 | webpush succeeds, statutory payload | #6802 | 0 `resend` sends |
| T19 | webpush **and** resend both fail | #6802 | marker deleted; `pinged` not incremented; `undelivered === 1` |
| T20 | `cost_breaker_tripped`, zero delivery | #6802 | falls back to email (class scope) |
| T21 | `review_gate` payload, zero delivery | #6802 | does **not** fall back (negative control for the class scope) |
| T22 | statutory push body / email body / cron title | #6798 | each carries the framing |
| T23 | `clockOriginCaveat("awareness")` vs `("receipt")` | #6798 | distinct strings; awareness names the awareness clock |
| T24-T28 | five ship-gate fixtures | #6813 | 3 no-signal, 2 signal, via the extracted regex |
| T29 | ADR with an `adr:` frontmatter key | #6800 | `check-adr-ordinals.sh` exits 1 |
| T30 | corpus as shipped | #6800 | `check-adr-ordinals.sh` exits 0 |

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **The band destroys the #6781 double-fire detector.** | D2a counter split; AC7 pins `suppressed === 0` / `headsUpAlreadySent === 4` in steady state. Residual (≤5-day detection delay in the heads-up arm) named in the ADR-037 amendment. |
| **`acknowledged_at` is NULL on some acknowledged row → those rows silently disappear from the scan.** This would *create* the exact cliff the issue is about, in a new place. | Blocking Phase 0.1 precondition + named `.or()` fallback. T16 fails loudly if the anchor drops eligible rows. |
| **Email fallback doubles notification volume** on partial delivery. | **Corrected at review (M18 supersedes this row):** the fallback fires on `delivered < attempted`, NOT only `delivered === 0` — a stale device that still 201s must not mask a dead one and leave the founder on the road with nothing. So a founder with one live + one dead device gets BOTH a push and an email on a statutory tick. This is an **accepted, intentional** belt-and-suspenders trade-off for the legal-clock class (recorded in ADR-134), not a defect. T18 pins the FULL-delivery no-double-notify direction; T18b pins that partial delivery still emails; `delivered` is computed from `Promise.allSettled` fulfilment, not inferred. |
| **Marker rollback reintroduces the #6781 duplicate-send defect.** | It cannot: rollback fires **only** when the outcome is provably undelivered. A delivered send keeps its marker. T19 + the pre-existing T1/T2/T3 suite pin both directions. |
| **`sendEmailNotification` return-type widening breaks a caller.** | Cross-consumer grep run at plan time: zero external callers (`notifications.ts` internal + tests only); `void` → `boolean` is additive. AC30 (`tsc --noEmit`) is the mechanical backstop. |
| **The #6813 regex over-tightens and misses a real incident.** | Two independent genuine-incident fixtures (AC22), and the gate keeps its fail-toward-PIR posture (Phase 5.4: when in doubt, fire). |
| **The ADR sweep breaks a citation.** | AC28 enumerates rather than samples. Zero renames means no citation can dangle by construction; only the two known frontmatter-derived citations move. |
| **Editing an applied migration trips the content-drift probe.** | D6.5 + AC29: migrations are not edited unless Phase 0.2 proves the probe is report-only. |
| **Six issues in one PR makes the diff hard to review.** | Phase-per-issue commits with issue numbers in the subject; the ship-gate (#6813) and ADR (#6800) work touches no `apps/` code and is trivially separable in review. |
| **The `this-plan.md` ship-gate fixture goes stale** if this plan is later edited. | The fixture is a **frozen copy** committed under `plugins/soleur/test/fixtures/`, not a symlink — it pins the *shape* (a preventive-hardening `single-user incident` plan mentioning prod), which is the invariant, not this file's exact text. |

---

## Alternative Approaches Considered

| Approach | Rejected because |
| --- | --- |
| **#6799:** keep the equality, add a "traversed unpinged" counter | Makes the silence visible without ending it. #6799's AC1 is "An item cannot pass through the heads-up window unpinged" — a counter does not satisfy it. |
| **#6799:** per-day heads-up keys (`headsup:<date>`) | Would send a heads-up every day of the band — 5 emails where 1 is wanted, and it violates mig 135's `tick_key` CHECK (which pins exactly `headsup` and `daily:YYYY-MM-DD`), forcing a migration. |
| **#6801:** widen the window to 120/180 days | Moves the cliff without removing it, and grows the scan for no principled reason. The anchor, not the width, is the defect. |
| **#6801:** accept the cliff, ship only the counter | The issue permits it ("or it is accepted in writing"), but a statutory item acknowledged and then never pinged is the same harm class as #6802, at `single-user incident` threshold. The re-anchor costs one changed predicate and no migration. |
| **#6801:** a second `warnSilentFallback` emit for the excluded count | Explicitly rejected by the issue ("Deliberately *not* a separate emit"). Level-escalating the single emit achieves Better Stack reachability without a second op slug. |
| **#6802:** prune subscriptions after N consecutive non-410 failures | Destructive on a signal we cannot distinguish from transient. The firewall DROP case would permanently delete a device that works again the moment the allowlist changes. Recorded as an explicit non-decision in ADR-134. |
| **#6802:** make `notifyOfflineUser` throw on total failure | Breaks the documented "never throws" contract two call sites rely on (`agent-on-spawn-requested.ts`, `email-on-received.ts`), and under `retries: 0` a throw inside the cron loop would kill the ingress liveness probe. |
| **#6800:** rename `ADR-036`/`ADR-037` files to match their frontmatter | Inverts authority against every existing tool (`check-adr-ordinals.sh`, `ship` Phase 5.5, `grok-pre-push-gate.sh` all key on filenames) and would break every existing filename citation. |
| **#6800:** normalize frontmatter to `adr: ADR-NNN` everywhere | Larger diff (~75 files gain a line vs ~57 losing one) and leaves the disagreement *possible* forever. Removal makes it structurally impossible. |
| **#6800:** renumber the five duplicate filename ordinals in this PR | Requires the 11,784-citation sweep this plan exists to avoid, and is a different defect class. Already tracked by `ALLOWED_COLLISIONS`. Recorded as a scope-out with reasoning (§D6.6) — no new issue needed, the allowlist is the tracker. |
| **#6813:** delete the gate | It caught a real class once (the 2026-06-02 chat-RLS outage). The defect is the regex, not the gate. |
| **#6813:** re-declare the regex as a JS port in the test (the sibling-test precedent) | Ports drift. Extracting the literal from `SKILL.md` and running real `grep` makes drift structurally impossible — a strict improvement on the precedent. |

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with a concrete artifact, a concrete vector, and a threshold.
- **This plan is itself a #6813 fixture.** Phase 5.4's iteration must re-check `this-plan.md` after every regex tweak. If the fixed gate fires on this plan, the fix is not done — this document is the densest possible false-positive input (it says `prod`, `incident`, `outage`, `broken`, and `single-user incident` many times, while describing zero production incidents).
- **`infoSilentFallback` silently drops `tags`.** Any code passing `tags:` to it has a dead observability claim. **Census run at deepen-plan: exactly one affected site** — the repin `deadline-repin-sweep-complete` emit. The only other non-test caller, `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts` §`op: "workspace-gc-sweep-complete"`, passes `feature`/`op`/`message`/`extra` and **no** `tags`, so it is unaffected. Re-run the census after AC12 lands in case a new caller appeared mid-pipeline.
- **Do not use `bun test` for `apps/web-platform`.** It is a vitest package; `apps/web-platform/bunfig.toml` may carry `[test] pathIgnorePatterns` and `npm run -w` fails (the repo root declares no `workspaces` field). Use `./node_modules/.bin/vitest run <path>` there and `bun test` only under `plugins/soleur/test/`.
- **The ADR ordinal chosen here (133) is provisional.** A sibling PR can claim it mid-pipeline; `/ship` Phase 5.5's collision gate re-verifies against `origin/main` and re-runs after every Phase 7 sync. A renumber must sweep this plan, `tasks.md`, and AC18 in the same edit — the recurring failure is an AC left asserting a filename that no longer exists.
- **Migration files are content-hashed after apply.** `run-migrations.sh` writes `git hash-object` into `_schema_migrations.content_sha`; a comment-only edit to an applied migration is a drift-probe trip, not a free change.
- **The recipient-grain constraint is untouched and must stay untouched.** Mig 135 note 4 + the cron's loop comment + test T12 pin that the send path is single-recipient. The email fallback in D4a sends to `auth.users.email` for the **same** `row.user_id` — it does not fan out to workspace Owners. Any future fan-out still requires re-keying the marker table first.
- **The `ship` gate's `A && B && echo` chain returns 1 when there is no signal.** The `#6813` fixture test must not run it as a bare statement under `set -euo pipefail` — wrap it in `if …; then` or capture `rc=$?` explicitly. Measured, not assumed (see §Research Insights).

---

## Research Insights (deepen-plan, 2026-07-22)

> **Method note.** `deepen-plan` normally fans out research/review subagents via
> the `Task` tool. This pass ran inside a one-shot subagent with no `Task` tool,
> so every check below was executed directly and its output is quoted. Nothing
> here is asserted from memory. `/soleur:plan-review`'s agent panel could not be
> spawned for the same reason — it should run at `/work` entry, where `Task` is
> available.

### Gate results

| Gate | Result |
| --- | --- |
| **4.4 Precedent-diff** | PASS — see below. |
| **4.4 Scheduled-work** | N/A — no new scheduled job; the change lives inside the existing `cron-email-ingress-probe` Inngest function (ADR-033 path already). |
| **4.5 Network-outage deep-dive** | Triggered, adjudicated non-applicable — see below. |
| **4.55 Downtime & cutover** | N/A — no infra reboot/replace, no lock-taking DDL (no migration at all), no router/tunnel restructure. The one deploy effect is the routine container swap `web-platform-release.yml` already performs on every `apps/web-platform/**` merge. |
| **4.6 User-Brand Impact halt** | PASS — heading present, body concrete, threshold `single-user incident` (valid enum). |
| **4.7 Observability halt** | PASS — all five fields present with child content; no placeholder values; `discoverability_test.command` contains no `ssh` (measured: 0 matches for `(^\|\s\|/)ssh(\s\|$)`). |
| **4.8 PAT-shaped variable halt** | PASS — the four-pattern sweep returns zero matches. |
| **4.9 UI-wireframe halt** | N/A — no `Files to Edit`/`Files to Create` path matches the UI-surface glob superset. |

### 4.5 Network-Outage Deep-Dive — triggered, non-applicable (adjudicated)

`plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` was
read in full. The keyword scan matched on three tokens, none of which is a live
connectivity symptom:

| Match | Context | Verdict |
| --- | --- | --- |
| `unreachable` | "`=== 7` is unreachable" — describing an unsatisfiable integer equality | false positive |
| `504` | matched *inside* the issue reference `#5046` | false positive |
| `firewall` | "the egress firewall's deliberate WNS DROP (#5046 PR-2)" — a **cited historical cause**, already diagnosed and closed | not a live symptom |

`#5046` verified live: `ISSUE CLOSED — Tier-2: cron egress firewall +
least-priv token → restore paused crons`. The firewall DROP is *by design*
(WNS is a deliberate allowlist exclusion) and is confirmed in code at
`apps/web-platform/server/notifications.ts` §`// Bounded: the egress firewall
(#5046 PR-2) DROPs (not rejects)`. This plan proposes **no** connectivity fix
and **no** service-layer hypothesis — it makes the application resilient to a
DROP that will remain in place. The checklist's L3→L7 ordering exists to stop
sshd/fail2ban fixes that skip the firewall check; there is no such inversion
here. **No `## Hypotheses` section is required.**

### 4.4 Precedent-diff (pattern-bound behaviors)

| Pattern this plan prescribes | Precedent found | Verdict |
| --- | --- | --- |
| Bounded count query `.select("id", { count: "exact", head: true })` | `app/(dashboard)/dashboard/page.tsx`, `…/settings/billing/page.tsx` (×2), `…/settings/scope-grants/page.tsx` | **Matches precedent.** Caveat: all four precedents are in dashboard route handlers, none in `server/inngest/functions/` — same supabase-js API, first use in a cron. Verify the vitest Supabase fake supports the `head:true` shape (Phase 3 RED will catch it). |
| Conditional `warn` vs `info` on the same logical event | `server/inngest/functions/cron-workspace-gc.ts` emits `info` for the every-run throughput record and a *separate* `warn` for the actionable low-disk condition, with an explicit comment on why the levels differ | **Partial divergence, deliberate.** The precedent splits into **two ops**; this plan level-escalates **one op**. Justified by #6801's explicit "deliberately *not* a separate emit" constraint. The plan diverges knowingly, and the divergence is recorded here rather than discovered at review. |
| `.delete().eq()` rollback on the marker table | No precedent — `statutory_repin_send` has exactly one non-test write site today (the insert at `cron-email-ingress-probe.ts` §`.from("statutory_repin_send")`), plus the 90-day sweep RPC | **Pattern is novel.** Flagged for reviewer scrutiny per the gate. The rollback must use the composite key `(item_id, tick_key)` — the table has no `id` column (mig 135), the same fact that motivated the plain-insert-no-`.select()` idiom. A `.delete()` with a `.select()` would fail 42703 identically. |
| Registry field widening (`clockOrigin`) on a code-static registry | `lib/email-triage/statutory-rules.ts` is already the pure/code-static registry with a required `dueRule` per rule | **Matches precedent.** Making `clockOrigin` required mirrors `dueRule` and gives AC1 its `tsc`-level enforcement for free. |

### Verified-live claims (nothing cited from memory)

```
gh issue view 6798..6802,6813  →  all OPEN
gh pr view 6782                →  MERGED  "fix(notifications): guard the statutory-deadline
                                            cron send-path against double-fire"
gh issue view 6781             →  CLOSED  (predecessor; the one-shot collision gate already
                                            cleared this as a cited-predecessor false positive)
gh issue view 5046             →  CLOSED  "Tier-2: cron egress firewall + least-priv token"
gh issue view 3739             →  OPEN    (code-review overlap, acknowledged)
gh issue view 3593             →  OPEN    (code-review overlap, false-positive path match)
```

**Attribution probes against `origin/main`** (state ≠ attribution — both checked):

```
git log --oneline --grep=6781 -- apps/web-platform/server/notifications.ts
  → a04d95c17 fix(notifications): guard the statutory-deadline cron send-path
              against double-fire (#6782)
git show origin/main:apps/web-platform/server/notifications.ts \
  | grep -c 'PushDeliveryTally\|statutory-notify-zero-delivery'   → 3
```

So both #6802's premises ("`sendPushNotifications` already returns a
`PushDeliveryTally` as of #6781"; "`notifyOfflineUser` now emits
`statutory-notify-zero-delivery`") are on `main`, authored by the commit the
issue credits. **Attribution confirmed, not merely existence.**

**ADR ordinal, derived from a freshly-fetched `origin/main`** (not the branch base):

```
git fetch origin main
git ls-tree -r --name-only origin/main knowledge-base/engineering/architecture/decisions/ \
  | grep -oE 'ADR-[0-9]{3}' | sort -u | tail -1     → ADR-132
```

`ADR-134` is free on live `origin/main`. Still provisional — `/ship` Phase 5.5
re-verifies at merge.

**AGENTS rule IDs cited in the plan + tasks.md** — all five resolve to an
active `[id: …]` in `AGENTS.md`; none appears in `scripts/retired-rule-ids.txt`:
`hr-gdpr-gate-on-regulated-data-surfaces`, `hr-observability-as-plan-quality-gate`,
`hr-type-widening-cross-consumer-grep`, `wg-use-closes-n-in-pr-body-not-title-to`,
`wg-when-deferring-a-capability-create-a`.

**Labels prescribed in ACs:** none — this plan creates no GitHub issues, so the
label-existence check is vacuous. (The D6.6 scope-out is tracked by the existing
`ALLOWED_COLLISIONS` allowlist, not by a new issue.)

**Path citations:** every `knowledge-base/`, `apps/`, `plugins/`, `scripts/`,
and `.github/` path in the plan body was resolved with a filesystem check. The
only non-existent paths are exactly the `## Files to Create` set — verified by
diffing the two lists.

### Measured shell semantics — the `#6813` test harness (do not assume)

The gate's snippet is an AND-list whose final element is the `echo`:

```bash
$ bash -c 'set -euo pipefail; H="nothing here"
           echo "$H" | grep -qiE "outage" && echo "$H" | grep -qiE "prod" && echo SIGNAL
           echo "survived rc=$?"'
survived rc=1          # did NOT abort mid-script, but the list evaluates to 1

$ bash -c 'set -euo pipefail; H="nothing here"; echo "$H" | grep -qiE "outage" && echo SIGNAL'
$ echo $?
1                      # as the LAST command, the no-signal case exits the script 1
```

Two consequences, both actionable:

1. **The fixture test must not treat a non-zero exit as an error.** Wrap the
   pipeline in `if …; then signal=yes; else signal=no; fi`, or run it with
   `set +e` around the call and capture `rc`. A harness that lets `set -e`
   propagate will report "test infrastructure failure" for every correct
   no-signal fixture — i.e. it inverts exactly the three assertions #6813 cares
   most about.
2. **Same trap for an agent pasting the snippet into a `set -e` step.** Worth a
   one-line note beside the snippet in `ship/SKILL.md` when Phase 5.3 edits it:
   *"no-signal exits 1 — branch on it, do not let `set -e` see it."*

### Constraint confirmations (claims the plan depends on)

- **No migration is required for D2.** Mig 135 line 92:
  `CHECK (tick_key = 'headsup' OR tick_key ~ '^daily:\d{4}-\d{2}-\d{2}$')` — the
  widened band still emits only these two shapes. Verified by reading the CHECK,
  not by inference from the header comment.
- **No index on `acknowledged_at`.** Corrected inline in §D3b reason 2. The four
  existing indexes are `(user_id, received_at DESC) WHERE status <> 'archived'`,
  `(created_at) WHERE summary IS NOT NULL`, `(user_id, received_at DESC) WHERE
  status = 'archived'`, and `(workspace_id, received_at DESC) WHERE status <>
  'archived'`.
- **Retention horizon.** Mig 102 §`purge_email_triage_items`: statutory rows are
  kept **365 days**, non-statutory **7 days**. This is the real bound on the
  scanned population.
- **Only one `infoSilentFallback` site is affected by the dropped-`tags` bug.**
  Census quoted in §Sharp Edges.
- **Op-slug literals are internally consistent.** Every slug the plan names
  (`deadline-repin-sweep-complete`, `statutory-notify-zero-delivery`,
  `webpush-send-failed`, `deadline-repin-marker-insert-failed`) exists verbatim
  on `main` under `apps/web-platform/server/` and appears with one canonical
  spelling throughout the plan — no drift between the Decisions, Observability,
  AC, and Test-Scenario sections.

### Deferred to `/work` (needs a tool this subagent lacks)

| Item | Why deferred | Where it runs |
| --- | --- | --- |
| `soleur:legal:clo` copy review | needs `Task` | **Phase 1.4 — blocking gate** (already an in-scope task, per #6798 AC) |
| `/soleur:gdpr-gate` on the diff | needs `Task`/skill nesting | Phase 1.4, alongside the CLO review. An inline GDPR assessment is recorded in §Domain Review → Legal; the gate confirms it against the real diff. |
| `/soleur:plan-review` agent panel (DHH / Kieran / code-simplicity, escalated to +architecture-strategist +spec-flow-analyzer at `single-user incident`) | needs `Task` | **Run at `/work` entry, before Phase 1.** At this threshold the panel is not optional: `2026-05-22-plan-review-and-deepen-plan-catch-different-issue-classes` records that style/scope review and architectural review catch disjoint issue classes, and this plan's highest-risk decisions (D2a's detector split, D4c's marker rollback) are architectural. |
