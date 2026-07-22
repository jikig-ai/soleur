---
title: "Tasks — statutory-notify delivery path, ADR ordinals, ship Incident-PIR gate"
plan: knowledge-base/project/plans/2026-07-22-fix-statutory-notify-path-adr-ordinals-and-ship-pir-gate-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
issues: [6798, 6799, 6800, 6801, 6802, 6813]
branch: feat-one-shot-6798-6813-statutory-notify-adr-ship-gate
pr: 6834
---

# Tasks

Derived from
[the plan](../../plans/2026-07-22-fix-statutory-notify-path-adr-ordinals-and-ship-pir-gate-plan.md).
Phase order is **load-bearing**: contract changes precede the consumers that
report them, and Phase 1's CLO gate blocks everything after it in that issue's
chain.

Test-runner forms (do not substitute):

- `apps/web-platform` → `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`
- `apps/web-platform` typecheck → `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `plugins/soleur/test` → `bun test plugins/soleur/test/<file>`

---

## Phase 0 — Preconditions (blocking; no code written)

- [ ] **0.1** Prove `acknowledged_at` is non-NULL for every `status='acknowledged'` row.
  - [ ] 0.1.1 Read `apps/web-platform/server/email-triage/email-triage-status-handler.ts` and trace to the status RPC.
  - [ ] 0.1.2 Read the RPC bodies in `apps/web-platform/supabase/migrations/102_email_triage_items.sql` and `111_email_triage_items_workspace_shared.sql`; confirm `acknowledged_at = CASE WHEN p_status = 'acknowledged' THEN now() … END`.
  - [ ] 0.1.3 `git grep -n "status.*acknowledged" apps/web-platform/server apps/web-platform/app` — confirm no non-RPC writer.
  - [ ] 0.1.4 Record the verdict. **If NULL is reachable**, switch to the `.or("received_at.gte.<floor>,acknowledged_at.gte.<floor>")` branch and first confirm the vitest Supabase fake in `apps/web-platform/test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts` implements `.or()`; extend the fake if not.
- [ ] **0.2** Read `.github/actions/dev-migration-drift-probe/action.yml`; determine whether a `content_sha` mismatch **fails the job** or only reports. Record. If report-only → drop the plan's D6.5 carve-out and edit migration citations in place (and update AC29 accordingly).
- [ ] **0.3** `git grep -rn "^adr:" scripts/ plugins/ apps/ .github/` plus a scan of any frontmatter parser — confirm zero consumers of the `adr:` key. If a consumer exists, switch D6.2 to normalize-to-filename and record.
- [ ] **0.4** Confirm the runner forms above: read `apps/web-platform/vitest.config.ts` `include:` globs (must cover `test/server/inngest/**` and `test/*.test.ts`) and check `apps/web-platform/bunfig.toml` for `[test] pathIgnorePatterns`.
- [ ] **0.5** Next free ADR ordinal: `ls knowledge-base/engineering/architecture/decisions/ | grep -oE '^ADR-[0-9]{3}' | sort -u | tail -1` against `origin/main`. If the adopted ordinal is not `133`, sweep **the plan file, this tasks.md, and AC18** in the same edit.
- [ ] **0.6** Build the ADR-citation adjudication table. Run
      `grep -rn --include='*.md' --include='*.ts' --include='*.tsx' --include='*.sql' --include='*.sh' --include='*.yml' -E '\bADR-03[45]\b' . | grep -v '^\./\.git/' | grep -v '/archive/'`
      and append a table to this file with columns `file:line | quoted context | means (dedup / template-registry / action-class) | action (repoint→ADR-037 / leave / frozen-migration)`. Exclude `knowledge-base/project/{plans,specs,brainstorms,learnings}/**`.
- [ ] **0.7** Capture the pre-fix #6813 baseline: extract the current `OUTAGE_RE`/`PROD_RE` from `plugins/soleur/skills/ship/SKILL.md` and run them against all five fixtures. Record which fire. The three no-signal fixtures MUST fire now (otherwise they do not reproduce the bug). Paste the result into the PR body for AC24.
- [ ] **0.8** *(added at deepen-plan)* Record the live scanned-population size as evidence for the no-index decision in plan §D3b reason 2: count rows where `status = 'acknowledged' AND statutory_class IS NOT NULL` (read-only, via the Supabase MCP against **dev**, never prd write). If the count exceeds ~5,000, file a follow-up for the partial index `(acknowledged_at) WHERE status = 'acknowledged' AND statutory_class IS NOT NULL` — do **not** add a migration to this PR.
- [ ] **0.9** *(added at deepen-plan)* Run `/soleur:plan-review` on the plan file. It could not run during planning (no `Task` tool in the planning subagent) and is **not optional** at `brand_survival_threshold: single-user incident` — the panel escalates to `+architecture-strategist +spec-flow-analyzer`, which are the lenses that cover D2a (detector split) and D4c (marker rollback). Apply mechanical findings; surface taste/user-challenge findings to `specs/<branch>/decision-challenges.md`.

---

## Phase 1 — #6798 statutory framing (RED → GREEN → CLO gate)

- [ ] **1.1 RED** Add tests (`apps/web-platform/test/notifications.test.ts` + a new registry test):
  - [ ] 1.1.1 T22a: statutory push body contains the not-legal-advice framing.
  - [ ] 1.1.2 T22b: statutory email body + footnote contain the full framing.
  - [ ] 1.1.3 T22c: the cron reminder title uses computed/estimated framing.
  - [ ] 1.1.4 T23: `clockOriginCaveat("awareness") !== clockOriginCaveat("receipt")`, and the awareness variant names the awareness clock.
  - [ ] 1.1.5 Confirm all four fail on `main`.
- [ ] **1.2 GREEN** `apps/web-platform/lib/email-triage/statutory-rules.ts`:
  - [ ] 1.2.1 Add `export type ClockOrigin = "receipt" | "awareness" | "instrument"`.
  - [ ] 1.2.2 Add required `clockOrigin: ClockOrigin` to `StatutoryRule` (required, so omitting it fails `tsc` — AC1).
  - [ ] 1.2.3 Populate every rule: `breach-art33` → `"awareness"`, `service-of-process` → `"instrument"`, `dsar-art15` → `"receipt"`, remaining rules → `"receipt"`.
  - [ ] 1.2.4 Add `NOT_LEGAL_ADVICE_NOTICE` and `clockOriginCaveat(origin)`.
- [ ] **1.3 GREEN** Render at all three surfaces:
  - [ ] 1.3.1 `apps/web-platform/server/notifications.ts` — the `payload.isStatutory` push body (short caveat, length-constrained surface).
  - [ ] 1.3.2 `apps/web-platform/server/notifications.ts` — `sendEmailTriageEmailNotification` `bodyHtml` + `footnoteHtml` (full framing).
  - [ ] 1.3.3 `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` — the reminder `title` verb.
- [ ] **1.4 BLOCKING GATE — CLO review** (#6798 AC bullet 3):
  - [ ] 1.4.1 `Task(soleur:legal:clo)` with the rendered copy for all three surfaces and both caveat variants. Frame as a **detrimental-reliance** question, not copy polish. Name the Art. 33 awareness-vs-receipt asymmetry explicitly.
  - [ ] 1.4.2 Run `/soleur:gdpr-gate` against the working diff.
  - [ ] 1.4.3 Write the verdict verbatim to `knowledge-base/project/specs/feat-one-shot-6798-6813-statutory-notify-adr-ship-gate/clo-copy-review.md`, naming the reviewing agent and stating explicitly that every required change was applied.
  - [ ] 1.4.4 Apply every CLO-required change; re-run 1.1's tests.
  - [ ] 1.4.5 **Do not start Phase 2 until the CLO has returned.**

---

## Phase 2 — #6799 heads-up band + counter split (RED → GREEN)

- [ ] **2.1 RED** T14 in `apps/web-platform/test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts`: two runs with jittered clocks straddling the T-7 boundary (`D−8 06:00:10` then `D−7 06:00:40`, the issue's own table) → **exactly one** heads-up email on the `resend` spy. Confirm RED on `main`.
- [ ] **2.2 RED** T15: a `breach-art33` item observed across its whole 72h life → **no** `headsup` marker is ever written; the first ping carries a `daily:` key.
- [ ] **2.3 RED** T14b: five consecutive in-band days → exactly one heads-up email, `suppressed === 0`, `headsUpAlreadySent === 4`.
- [ ] **2.4 GREEN** `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts`:
  - [ ] 2.4.1 Replace the equality with `if (daysUntilDue > DEADLINE_REPIN_HEADS_UP_DAY) continue;`.
  - [ ] 2.4.2 `const inHeadsUpBand = daysUntilDue > DEADLINE_REPIN_DANGER_THRESHOLD_DAYS;` → `tickKey = inHeadsUpBand ? "headsup" : \`daily:${runDateUtc}\``.
  - [ ] 2.4.3 Split the counters: `suppressed` (23505 on a `daily:` key only) vs `headsUpAlreadySent` (23505 on the `headsup` key).
  - [ ] 2.4.4 Keep `tags: { repin_suppressed: suppressed > 0 ? "yes" : "no" }` bound to `suppressed` **only**.
  - [ ] 2.4.5 Rewrite the `DEADLINE_REPIN_HEADS_UP_DAY` doc comment (currently says "exactly T-7 (floor)") and the loop comment that cites the retired equality — both would be false after this change.
  - [ ] 2.4.6 Add the `breach-art33` intentional-no-heads-up comment at the band predicate, citing the 72h `dueRule`.
  - [ ] 2.4.7 Add the stated trade-off comment: a second scheduler firing only inside the band is masked in the heads-up arm; the daily arm catches it within ≤5 days.

---

## Phase 3 — #6801 scan re-anchor + excluded counter (RED → GREEN)

- [ ] **3.1 RED** T16: a row with `received_at` 90 days ago, `acknowledged_at` yesterday, due tomorrow → **is scanned and pinged**. Confirm RED on `main`.
- [ ] **3.2 RED** T16b: a row with `acknowledged_at` 90 days ago → excluded from the scan, and the sweep-complete payload carries `excluded >= 1` **at warn level** (assert on `warnSilentFallbackSpy`, not `infoSilentFallbackSpy`).
- [ ] **3.3 RED** T16c: the excluded-count query returns an error → `excluded: null`, the run still completes, and probe steps 3-5 are unaffected.
- [ ] **3.4 RED** T16d: `infoSilentFallback(null, { …, tags: { x: "y" } })` → the tag reaches `Sentry.captureMessage`'s `tags` argument. Confirm RED on `main`.
- [ ] **3.5 GREEN** `apps/web-platform/server/observability.ts` — add the `extraTags` merge to `infoSilentFallback`, mirroring `reportSilentFallback`/`warnSilentFallback` exactly (`if (extraTags) Object.assign(tags, extraTags);`).
- [ ] **3.6 GREEN** `cron-email-ingress-probe.ts`:
  - [ ] 3.6.1 Swap `.gte("received_at", scanFloor)` → `.gte("acknowledged_at", scanFloor)` (or the `.or()` branch from 0.1.4).
  - [ ] 3.6.2 Add the bounded excluded-count query (`.select("id", { count: "exact", head: true })` + `.lt("acknowledged_at", scanFloor)`), wrapped so an error yields `excluded: null` and never fails the run. *(deepen-plan precedent note: the four repo precedents for `count: "exact", head: true` are all in `app/(dashboard)/**` route handlers — this is the first use inside an Inngest cron, so confirm the vitest Supabase fake returns a `{ count }` shape for the `head:true` form and extend the fake if not.)*
  - [ ] 3.6.3 Level-escalate the sweep-complete emit: `warnSilentFallback` when `excluded > 0 || suppressed > 0 || undelivered > 0 || markerRollbackFailed > 0`, else `infoSilentFallback`. **Same op slug** `deadline-repin-sweep-complete`, same tags contract.
  - [ ] 3.6.4 Rewrite the `DEADLINE_REPIN_SCAN_WINDOW_DAYS` doc comment — it currently justifies 60 days in `received_at` terms and would become false.

---

## Phase 4 — #6802 delivery contract (RED → GREEN)

- [ ] **4.1 RED** T17: a non-410 `webpush` rejection on a statutory payload → exactly **one** `resend` send (assert on the `resend` spy — the harness's real-send seam, never a stubbed `notifyOfflineUser`). Confirm RED on `main`.
- [ ] **4.2 RED** T18: `webpush` succeeds → **zero** `resend` sends for that tick.
- [ ] **4.3 RED** T19: `webpush` and `resend` both fail → the `(item_id, tick_key)` marker is deleted, `pinged` is not incremented, `undelivered === 1`.
- [ ] **4.4 RED** T20: a `cost_breaker_tripped` payload with zero delivery also falls back to email.
- [ ] **4.5 RED** T21 (negative control): a `review_gate` payload with zero delivery does **not** fall back.
- [ ] **4.6 GREEN** `apps/web-platform/server/notifications.ts`:
  - [ ] 4.6.1 Add `export type NotifyChannel = "push" | "email" | "none"` and `export interface NotifyOutcome { channel: NotifyChannel; delivered: boolean }`.
  - [ ] 4.6.2 Extract `mustNotFailSilently(payload)` from `mirrorNotifyFailure`'s existing 3-class predicate; have `mirrorNotifyFailure` consume it (single source of truth).
  - [ ] 4.6.3 `notifyOfflineUser`: on `tally.delivered === 0 && mustNotFailSilently(payload)`, fall through to the same email path the zero-subscription branch uses.
  - [ ] 4.6.4 `notifyOfflineUser` returns `NotifyOutcome`; the outer catch arm returns `{channel:"none", delivered:false}` so the documented "never throws" contract holds.
  - [ ] 4.6.5 `sendEmailNotification` and the four `send*EmailNotification` variants return `boolean` (true only when Resend returned no error).
  - [ ] 4.6.6 Update the `statutory-notify-zero-delivery` message to describe the fallback. **Do not change the op slug.** Extend its `extra` to `{userId, attempted, delivered, channel, fallbackDelivered, emailId}`.
- [ ] **4.7 GREEN** `cron-email-ingress-probe.ts`:
  - [ ] 4.7.1 Capture the `NotifyOutcome` from `notifyOfflineUser`.
  - [ ] 4.7.2 On `!outcome.delivered`: `DELETE FROM statutory_repin_send WHERE item_id = <row.id> AND tick_key = <tickKey>`; increment `undelivered`; do **not** increment `pinged`.
    - **Novel pattern — no repo precedent** (deepen-plan 4.4). `statutory_repin_send` has exactly one non-test write site today (the insert) plus the 90-day sweep RPC. The DELETE MUST match on the **composite key** `.eq("item_id", …).eq("tick_key", …)` and MUST NOT chain `.select()` — the table has **no `id` column** (mig 135), so a RETURNING clause naming one fails the whole statement with `42703`, the same trap documented at the insert site.
  - [ ] 4.7.3 On a failed rollback DELETE: increment `markerRollbackFailed` (non-fatal, folded into the same emit).
  - [ ] 4.7.4 Extend the sweep-complete `extra` with `undelivered` and `markerRollbackFailed`; extend `HandlerResult` correspondingly.
- [ ] **4.8** Cross-consumer sweep: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; then confirm the 5 external `notifyOfflineUser` call sites (`agent-runner.ts`, `cc-dispatcher.ts`, `agent-on-spawn-requested.ts`, `email-on-received.ts`, `cron-email-ingress-probe.ts`) compile unchanged and the two "never throws" comments remain true.

---

## Phase 5 — #6813 ship Incident-PIR gate (RED → GREEN)

- [ ] **5.1** Create `plugins/soleur/test/fixtures/ship-incident-pir-gate/`:
  - [ ] 5.1.1 `preventive-hardening-single-user-incident.md` — the real #6782 plan body (must contain all four lines #6813 lists). Expect **no signal**.
  - [ ] 5.1.2 `this-plan.md` — a frozen copy of this feature's plan file. Expect **no signal**.
  - [ ] 5.1.3 `incidental-word.md` — prose whose only outage-shaped token is `incidental`. Expect **no signal**.
  - [ ] 5.1.4 `chat-rls-outage.md` — derived from `knowledge-base/engineering/operations/post-mortems/chat-rls-workspace-id-outage-postmortem.md`. Expect **SIGNAL**.
  - [ ] 5.1.5 `second-known-incident.md` — a second real past production-incident body. Expect **SIGNAL**.
- [ ] **5.2 RED** `plugins/soleur/test/ship-incident-pir-gate.test.ts`:
  - [ ] 5.2.1 **Extract** the `OUTAGE_RE='…'` and `PROD_RE='…'` literals from `plugins/soleur/skills/ship/SKILL.md` (do not re-declare a JS port — AC19).
  - [ ] 5.2.2 Execute the real haystack pre-strip + `grep -qiE` pipeline against each fixture.
  - [ ] 5.2.3 **`set -e` trap (measured at deepen-plan).** The gate's `A && B && echo SIGNAL` chain **exits 1 in the no-signal case**. Wrap it in `if …; then signal=yes; else signal=no; fi` (or `set +e` + capture `rc`) — a harness that lets `set -euo pipefail` see the non-zero exit reports "infrastructure failure" for every *correct* no-signal fixture, inverting exactly the three assertions #6813 cares about.
  - [ ] 5.2.4 Assert 3 no-signal + 2 signal. Confirm RED on `main`.
- [ ] **5.3 GREEN** `plugins/soleur/skills/ship/SKILL.md` §"Incident-PIR Gate" trigger 3:
  - [ ] 5.3.1 Add the haystack pre-strip: drop lines matching `^brand_survival_threshold:` and `\*\*Brand-survival threshold:\*\*`.
  - [ ] 5.3.2 Add the hypothetical-framing strip: drop `**If this lands broken,`, `**If this leaks,`, and lines containing `if this lands` / `would break` / `could break`.
  - [ ] 5.3.3 Replace `OUTAGE_RE` with the word-boundaried, past-tense set (drop bare `incident`; add `incident report|post-incident|postmortem|post-mortem`).
  - [ ] 5.3.4 Leave `PROD_RE` unchanged (the discrimination now lives in `OUTAGE_RE`; weakening `PROD_RE` risks the false-negative direction).
  - [ ] 5.3.5 Add a `**Why:**` line citing #6813 and the #6782 false positive.
- [ ] **5.4** Iterate the verb set against all five fixtures until both directions pass. If a genuine-incident fixture cannot fire without also firing a hypothetical fixture, **prefer firing** (fail-toward-PIR) and record the residual as a comment in the test.

---

## Phase 6 — #6800 ADR ordinals (mechanical, per-citation)

- [ ] **6.1** Delete the `adr:` frontmatter key from every ADR carrying one:
      `grep -l '^adr:' knowledge-base/engineering/architecture/decisions/ADR-*.md` (~57 files). Verify no other frontmatter key is disturbed.
- [ ] **6.2** Apply the Phase 0.6 adjudication table:
  - [ ] 6.2.1 Re-point dedup-idiom `ADR-035` citations → `ADR-037` (known: the two `notifyInboxItem` idempotency comments in `apps/web-platform/server/notifications.ts`).
  - [ ] 6.2.2 Leave template-registry citations (`apps/web-platform/server/templates/template-registry.ts`) as `ADR-035`.
  - [ ] 6.2.3 Leave action-class citations as `ADR-034`.
  - [ ] 6.2.4 Do **not** touch `apps/web-platform/supabase/migrations/122_inbox_item.sql` or `135_statutory_repin_send.sql` unless Phase 0.2 proved the drift probe is report-only.
- [ ] **6.3** Remove the two-line #6781 see-also block from `knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md`; confirm no remaining prose there implies the ordinal ambiguity.
- [ ] **6.4** `scripts/check-adr-ordinals.sh` — add layer (4): fail if any `ADR-*.md` frontmatter carries an ordinal key. Keep `ALLOWED_COLLISIONS` unchanged (D6.6 scope-out).
- [ ] **6.5** `plugins/soleur/test/adr-frontmatter-ordinal-guard.test.sh` — positive fixture (clean corpus → exit 0) and negative fixture (an ADR with an `adr:` key → exit 1).
- [ ] **6.6** Residual verification: `grep -rhoE '\bADR-[0-9]{3}\b'` over every edited file; assert each ordinal resolves to an existing `knowledge-base/engineering/architecture/decisions/ADR-NNN-*.md` (AC28 — enumerated, not sampled).

---

## Phase 7 — ADR + C4 deliverables

- [ ] **7.1** Author `knowledge-base/engineering/architecture/decisions/ADR-133-statutory-send-markers-certify-delivery-not-dispatch.md` via `/soleur:architecture` (ordinal from Phase 0.5). Required headings: `## Status`, `## Context`, `## Decision`, `## Consequences`, `## Alternatives Considered`. Alternatives must name: prune-on-repeated-non-410; leave the marker and rely on the warn; make `notifyOfflineUser` throw.
- [ ] **7.2** Amend `ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`:
  - [ ] 7.2.1 `## Decision`: `headsup` now keys a band (T-7..T-3), not an exact day.
  - [ ] 7.2.2 A `23505` on `headsup` is expected steady state and is counted separately from the double-fire signal (with the ≤5-day detection-delay ceiling stated).
  - [ ] 7.2.3 The repin scan is anchored on `acknowledged_at`, why, and the residual excluded population (AC13).
  - [ ] 7.2.4 `breach-art33` never enters the heads-up band, by design.
  - [ ] 7.2.5 A "Historical citations" note naming the frozen artifacts (migrations 122, 135) that cite this decision by its retired frontmatter ordinal.
  - [ ] 7.2.6 Add the rejected alternatives (keep the equality + traversal counter; per-day heads-up keys).
- [ ] **7.3** `knowledge-base/engineering/architecture/diagrams/model.c4`:
  - [ ] 7.3.1 Add `pushService = system "Web Push Services"` with the `#external` tag and a description naming FCM/APNs/WNS and the `push_subscriptions.endpoint` linkage.
  - [ ] 7.3.2 Add the context-level edge `webapp -> pushService` and the container-level edge from `platform.webapp.api`, both naming the non-410 → email fallback and the #5046 PR-2 WNS DROP trigger.
  - [ ] 7.3.3 Update the `resend` element description and the two `-> resend` edge descriptions to name the push-failure fallback as a reason the edge carries traffic.
- [ ] **7.4** `knowledge-base/engineering/architecture/diagrams/views.c4` — add `pushService` to the `include` list of **both** the `context` view and the `containers` view.
- [ ] **7.5** `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.

---

## Phase 8 — Full-suite exit gate

- [ ] **8.1** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → exit 0.
- [ ] **8.2** `cd apps/web-platform && ./node_modules/.bin/vitest run` → full suite green.
- [ ] **8.3** `bun test plugins/soleur/test/` → full suite green (includes `components.test.ts`).
- [ ] **8.4** `bash scripts/check-adr-ordinals.sh` → exit 0.
- [ ] **8.5** Run the repo lints wired in `.github/workflows/ci.yml` (rule-id lint, AGENTS budget lint).
- [ ] **8.6** Walk every AC1-AC34 in the plan and record pass/fail evidence for the PR body.
- [ ] **8.7** PR body carries `Closes #6798`, `Closes #6799`, `Closes #6800`, `Closes #6801`, `Closes #6802`, `Closes #6813` — in the **body**, not the title.

---

## ADR-citation adjudication table (filled at Phase 0.6)

| file:line | quoted context | means | action |
| --- | --- | --- | --- |
| _(populate at Phase 0.6 — do not edit any citation before this table exists)_ | | | |
