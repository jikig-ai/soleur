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

- [x] **0.1** Prove `acknowledged_at` is non-NULL for every `status='acknowledged'` row.
  - [x] 0.1.1 Read `apps/web-platform/server/email-triage/email-triage-status-handler.ts` and trace to the status RPC.
  - [x] 0.1.2 Read the RPC bodies in `apps/web-platform/supabase/migrations/102_email_triage_items.sql` and `111_email_triage_items_workspace_shared.sql`; confirm `acknowledged_at = CASE WHEN p_status = 'acknowledged' THEN now() … END`.
  - [x] 0.1.3 `git grep -n "status.*acknowledged" apps/web-platform/server apps/web-platform/app` — confirm no non-RPC writer.
  - [x] 0.1.4 Record the verdict. **If NULL is reachable**, switch to the `.or("received_at.gte.<floor>,acknowledged_at.gte.<floor>")` branch and first confirm the vitest Supabase fake in `apps/web-platform/test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts` implements `.or()`; extend the fake if not.
- [x] **0.2** Read `.github/actions/dev-migration-drift-probe/action.yml`; determine whether a `content_sha` mismatch **fails the job** or only reports. Record. If report-only → drop the plan's D6.5 carve-out and edit migration citations in place (and update AC29 accordingly).
- [x] **0.3** `git grep -rn "^adr:" scripts/ plugins/ apps/ .github/` plus a scan of any frontmatter parser — confirm zero consumers of the `adr:` key. If a consumer exists, switch D6.2 to normalize-to-filename and record.
- [x] **0.4** Confirm the runner forms above: read `apps/web-platform/vitest.config.ts` `include:` globs (must cover `test/server/inngest/**` and `test/*.test.ts`) and check `apps/web-platform/bunfig.toml` for `[test] pathIgnorePatterns`.
- [x] **0.5** Next free ADR ordinal: `ls knowledge-base/engineering/architecture/decisions/ | grep -oE '^ADR-[0-9]{3}' | sort -u | tail -1` against `origin/main`. If the adopted ordinal is not `133`, sweep **the plan file, this tasks.md, and AC18** in the same edit.
- [x] **0.6** Build the ADR-citation adjudication table. Run
      `grep -rn --include='*.md' --include='*.ts' --include='*.tsx' --include='*.sql' --include='*.sh' --include='*.yml' -E '\bADR-03[45]\b' . | grep -v '^\./\.git/' | grep -v '/archive/'`
      and append a table to this file with columns `file:line | quoted context | means (dedup / template-registry / action-class) | action (repoint→ADR-037 / leave / frozen-migration)`. Exclude `knowledge-base/project/{plans,specs,brainstorms,learnings}/**`.
- [ ] **0.7** Capture the pre-fix #6813 baseline: extract the current `OUTAGE_RE`/`PROD_RE` from `plugins/soleur/skills/ship/SKILL.md` and run them against all five fixtures. Record which fire. The three no-signal fixtures MUST fire now (otherwise they do not reproduce the bug). Paste the result into the PR body for AC24.
- [ ] **0.8** *(added at deepen-plan)* Record the live scanned-population size as evidence for the no-index decision in plan §D3b reason 2: count rows where `status = 'acknowledged' AND statutory_class IS NOT NULL` (read-only, via the Supabase MCP against **dev**, never prd write). If the count exceeds ~5,000, file a follow-up for the partial index `(acknowledged_at) WHERE status = 'acknowledged' AND statutory_class IS NOT NULL` — do **not** add a migration to this PR.
- [x] **0.9** *(added at deepen-plan)* Run `/soleur:plan-review` on the plan file. It could not run during planning (no `Task` tool in the planning subagent) and is **not optional** at `brand_survival_threshold: single-user incident` — the panel escalates to `+architecture-strategist +spec-flow-analyzer`, which are the lenses that cover D2a (detector split) and D4c (marker rollback). Apply mechanical findings; surface taste/user-challenge findings to `specs/<branch>/decision-challenges.md`.

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

- [ ] **7.1** Author `knowledge-base/engineering/architecture/decisions/ADR-134-statutory-send-markers-certify-delivery-not-dispatch.md` via `/soleur:architecture` (ordinal from Phase 0.5). Required headings: `## Status`, `## Context`, `## Decision`, `## Consequences`, `## Alternatives Considered`. Alternatives must name: prune-on-repeated-non-410; leave the marker and rely on the warn; make `notifyOfflineUser` throw.
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

## Phase 0 results (recorded 2026-07-22)

### 0.1 — `acknowledged_at` non-nullability: **PROVEN. Take the `.gte()` branch; no `.or()` fallback.**

Chain of evidence:

1. `102_email_triage_items.sql` — `status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','acknowledged','archived'))`. A row cannot be born `acknowledged`.
2. Same file — `REVOKE INSERT ON TABLE public.email_triage_items FROM PUBLIC, anon, authenticated`. Writes are service-role pipeline + SECURITY DEFINER RPCs only.
3. The **single** non-test INSERT site is `server/inngest/functions/email-on-received.ts` §`.insert({ user_id, workspace_id, claim_key, message_id, resend_email_id, sender, subject, received_at, received_at_source, summary: null, mail_class: null, statutory_class: null, rule_id: null })` — it does **not** set `status`, so it takes the `'new'` default.
4. `102` §`email_triage_items_no_mutate()` — any UPDATE changing `status` / `status_changed_at` / `acknowledged_at` raises `P0001` unless `current_setting('app.email_triage_status_in_progress')` is `'on'`, a GUC only `set_email_triage_status` sets → **RPC-only transitions**.
5. `102` §`set_email_triage_status` (and the `111` re-definition) sets `acknowledged_at = CASE WHEN p_status = 'acknowledged' THEN now() ELSE acknowledged_at END` in the same UPDATE as the status flip.

∴ every `status='acknowledged'` row has `acknowledged_at` set in the same statement that set the status. `.gte("acknowledged_at", scanFloor)` drops no eligible row.

### 0.2 — dev-migration-drift-probe severity: **REPORT-ONLY — but the D6.5 carve-out is KEPT.**

`.github/actions/dev-migration-drift-probe/action.yml` header: *"Emits `::warning::` annotations (NOT `::error::`)… Severity is `::warning::` by design."* The content-drift branch emits four `::warning::` lines and no `exit 1`; the action's only `exit 1` belongs to the **byok RPC body-marker** probe, gated behind `fail-on-rpc-body-drift` (default `false` on PR CI).

**Decision: still do NOT edit migrations 122/135.** The AC29 conditional ("in which case their citations are corrected") was written before the answer was known. Report-only removes the *blocking* risk, not the *cost*: the probe compares dev-Supabase's recorded `content_sha` against `origin/main`'s blob, and an applied migration is never re-applied — so a comment-only edit emits a `::warning::` on **every future CI run, permanently**. Trading four stale comment citations for a permanent un-clearable warning is precisely the cry-wolf alert erosion #6813 exists to stop; introducing it in this PR would be self-contradictory. The `ADR-037` "Historical citations" note (D6.5) carries the correction instead. **AC29 is updated to record this finding and this disposition.**

### 0.3 — `adr:` frontmatter consumers: **zero consumers, but ONE PRODUCER (not in the plan).**

`git grep -rn "^adr:" -- scripts/ plugins/ apps/ .github/` returns exactly one hit, and it is not a parser:

- `plugins/soleur/skills/architecture/references/adr-template.md:9` — `adr: ADR-NNN`

That is the **template every new ADR is scaffolded from**. Removing the key from the corpus without removing it from the template means the very next `/soleur:architecture` invocation re-introduces it and **fails the new layer-4 gate**. Added as task **6.1b**. No frontmatter parser reads `adr:` (`scripts/`'s only frontmatter tooling is `frontmatter-strip` and `lint-agents-rule-budget.py`, neither of which references the key), so D6.2 (remove, don't normalize) stands.

### 0.4 — runner forms confirmed

- `apps/web-platform/vitest.config.ts` — node project `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` (covers `test/server/inngest/**`), happy-dom project `include: ["test/**/*.test.tsx"]`.
- `apps/web-platform/bunfig.toml` — `[test] pathIgnorePatterns = ["**"]`, blocking all bun-test discovery by design (#1469). **Never `bun test` in web-platform.**

### 0.5 — ADR ordinal: **`ADR-134` is free.** Highest on freshly-fetched `origin/main` is `ADR-132`. Plan's provisional ordinal holds; **no sweep required**.

### 0.6 — ADR-citation adjudication (grep-enumerated, per-citation)

Corpus: `git grep -nE '\bADR-03[45]\b' -- '*.md' '*.ts' '*.tsx' '*.sql' '*.sh' '*.yml'`, minus `/archive/` and `knowledge-base/project/**`.

**Ground truth.** `ADR-037-…-multi-source-dedup.md` §Decision owns the `plain-insert` + catch-`23505` idiom (explicitly: *"Webhook + Inngest + KB-drift ingest all INSERT without `ON CONFLICT`; supabase-js `error.code === 23505` → 200 duplicate"*). `ADR-035-template-registry-code-static.md` §Decision owns `TEMPLATE_IDS` / `getTemplateHash`. `ADR-034` owns `ACTION_CLASSES`. Any citation meaning *dedup / 23505 / send-boundary* meant the **ADR-037 file** via its retired `adr: 035` frontmatter.

| file:line | quoted context | means | action |
| --- | --- | --- | --- |
| `server/notifications.ts:733` | "Idempotent (ADR-035): plain-insert + catch 23505 rather than `ON CONFLICT DO NOTHING`" | dedup | **re-point → ADR-037** |
| `server/notifications.ts:754` | "Idempotency key (ADR-035). … the dedup index is `(workspace_id, dedup_key)`" | dedup | **re-point → ADR-037** |
| `server/inngest/functions/cron-email-ingress-probe.ts:295` | "RECIPIENT-GRAIN CONSTRAINT (ADR-035; migration 135 header note 4)" | dedup / send-boundary | **re-point → ADR-037** *(not named in the plan — found by enumeration)* |
| `test/migration-122-inbox-item.test.ts:107` | "dedup: workspace-scoped partial-unique index (ADR-035)" | dedup | **re-point → ADR-037** *(not named in the plan)* |
| `test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts:839` | "see migration 135 header note 4 and the ADR-035" | dedup / send-boundary | **re-point → ADR-037** *(not named in the plan)* |
| `knowledge-base/engineering/architecture/domain-model.md:59` | BR-NOTIFY-1 sources: "migration 135_statutory_repin_send.sql; ADR-035; GDPR Art. 32(1)(b)" | dedup / send-boundary | **re-point → ADR-037** *(not named in the plan)* |
| `supabase/migrations/122_inbox_item.sql` (×2) | dedup index rationale | dedup | **FROZEN** — covered by the ADR-037 Historical-citations note (0.2) |
| `supabase/migrations/135_statutory_repin_send.sql` (×2) | send-marker rationale | dedup | **FROZEN** — same |
| `server/templates/template-registry.ts:4,35,36` | "ADR-035 §Decision (1)… mirroring ADR-034's ACTION_CLASSES pattern" | template registry | leave |
| `server/action-sends/write-action-send.ts:128` | "canonical template hash … code-static template registry … See ADR-035" | template registry | leave |
| `app/api/dashboard/today/[id]/send/route.ts:184` | "Plan §Phase 4 §4 + Sharp Edges + ADR-035" (at `tierRequiresTemplateAuth`) | template registry | leave |
| `app/api/dashboard/today/[id]/send/route.ts:329` | "action-class typed-literal lint (PR-H ADR-034 §1)" | action-class registry | leave |
| `docs/legal/data-protection-disclosure.md:119`, `docs/legal/gdpr-policy.md:295`, `plugins/soleur/docs/pages/legal/data-protection-disclosure.md:126` | "See also ADR-035 … for the code-static template registry decision" | template registry | leave |
| `knowledge-base/legal/article-30-register.md:315,317,323,325,335,343,345`, `knowledge-base/legal/compliance-posture.md:163`, `knowledge-base/INDEX.md:46` | PA-16/PA-18 registry prose | action-class / template registry | leave |
| `apps/web-platform/lib/auth/csrf-coverage.test.ts:19`, `server/inngest/model-tiers.ts:7`, `server/scope-grants/action-class-map.ts:4,6`, `test/lint/action-class-typed-literals.test.ts:16,121,183`, `test/server/scope-grants/action-class-exhaustive.test.ts:15,80,88`, `supabase/migrations/051_*.sql`, `053_*.sql`, `app/api/webhooks/github/route.ts:276` | `ACTION_CLASSES` / template-auth prose | action-class / template registry | leave |

**Net: 6 re-points, 4 frozen, everything else left.** The plan predicted 2 re-points (`notifications.ts` only); enumeration found **4 more**. This is exactly the "grep-enumerated, not intuited" requirement.

### 0.6b — **H1 headings disagree too (scope extension, not in the plan)**

Removing the `adr:` frontmatter key alone does **not** discharge #6800: the ADR-037 file's own H1 reads `# ADR-035: messages.source_ref composite-unique for multi-source dedup`, so `ADR-035` would still resolve to two documents — one by filename, one by H1. A corpus sweep found the mismatch set is **exactly the same two files**, and every one of the 138 ADRs carries an H1 ordinal (zero exceptions):

| file | H1 says | action |
| --- | --- | --- |
| `ADR-036-github-app-webhook-as-second-multi-source-ingress.md` | `# ADR-034:` | rewrite H1 → `ADR-036` |
| `ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md` | `# ADR-035:` | rewrite H1 → `ADR-037` |

Both files also carry a "Note on numbering" paragraph narrating the adoption of the now-retired ordinal; both are rewritten to state that the **filename is authoritative**. Added as task **6.1c** and **AC25b**.

### 0.7 — #6813 pre-fix baseline

Gate lives at `plugins/soleur/skills/ship/SKILL.md` §"Incident-PIR Gate" trigger 3 (the `OUTAGE_RE=` / `PROD_RE=` / `grep -qiE` lines). Baseline captured; the three no-signal fixtures MUST fire against this pre-fix pair — recorded in Phase 5.

### 0.8 — scanned-population size

Recorded in Phase 3 (evidence for the no-index decision in plan §D3b reason 2).

### 0.9 — `/soleur:plan-review`

Run at Phase 0 exit; findings recorded below.

---

## Added tasks (from Phase 0 findings)

- [ ] **6.1b** Remove the `adr: ADR-NNN` line from `plugins/soleur/skills/architecture/references/adr-template.md` — otherwise the next scaffolded ADR re-introduces the key and fails the new layer-4 gate (**Phase 0.3**).
- [ ] **6.1c** Rewrite the H1 ordinal in `ADR-036-*.md` (`ADR-034`→`ADR-036`) and `ADR-037-*.md` (`ADR-035`→`ADR-037`), and rewrite both "Note on numbering" paragraphs to state that the filename is authoritative (**Phase 0.6b**).
- [ ] **6.2e** Re-point the four additional dedup citations found by enumeration: `cron-email-ingress-probe.ts:295`, `test/migration-122-inbox-item.test.ts:107`, `test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts:839`, `knowledge-base/engineering/architecture/domain-model.md:59` (**Phase 0.6**).
- [ ] **AC25b** `for f in ADR-*.md; do` H1 ordinal `==` filename ordinal `; done` — zero mismatches.
- [ ] **AC29 (revised)** Migrations `122_inbox_item.sql` and `135_statutory_repin_send.sql` are unchanged. Phase 0.2 proved the drift probe is **report-only**, and the PR body records that finding **and** the reason the carve-out is kept anyway (a permanent un-clearable `::warning::` on every future CI run).

---

## Plan Review Resolution (Phase 0.9) — BINDING mechanical deltas

8-agent panel (DHH · Kieran · code-simplicity · architecture-strategist · spec-flow-analyzer ·
cpo[rate-limited] · cmo · cto). All factual claims below were re-verified against source before
adoption. Taste/User-Challenge/scope items are in `decision-challenges.md`. These deltas
**supersede** the cited plan decisions and are authoritative for `/work`.

**Both panels fired on D1 and D4b** (simplify + correctness) → per plan-review's prefer-delete rule,
both are cut, dissolving their attached bug findings.

- [ ] **M1 — supersedes D1: cut `clockOrigin` + `clockOriginCaveat()` entirely.** `StatutoryRule.catalogExcerpt` is ALREADY a required field (`statutory-rules.ts:39`) that states clock origin verbatim per rule ("within 72 hours of becoming aware of it"; "within one calendar month of receipt … the clock runs from the day the request arrived"; `VERIFY_INSTRUMENT_DUE`). A new `clockOrigin` enum is a second, drift-prone encoding and its draft `regulator-* → "receipt"` mapping already contradicts `regulator-contact`'s `VERIFY_INSTRUMENT_DUE`. Ship ONE exported `NOT_LEGAL_ADVICE_NOTICE` constant; render `catalogExcerpt` in the statutory **email** body next to the computed date. The "compile-time obligation when adding a rule" is already provided by `catalogExcerpt` being non-optional. **Collapses AC1/AC2/T23** into "the rendered email carries the rule's `catalogExcerpt` + the notice"; drops Phase 1.2.1–1.2.3 (the type + field + population) and the type-level test.
- [ ] **M2 — adds to D1: fix the overdue-title over-claim.** The cron reminder title is ```Statutory deadline approaching — …``` and fires unchanged when `daysUntilDue` is **negative** (`cron-email-ingress-probe.ts`). Presenting "approaching" on an item 12 days past due is the exact over-claim #6798 is about. Make the title state-accurate: an "approaching" verb only when `daysUntilDue >= 0`, an "OVERDUE — was due <date>" verb when negative. **New AC + test: the overdue title string ≠ the approaching title string.**
- [ ] **M3 — supersedes D4b: collapse `NotifyOutcome`/`NotifyChannel` → `notifyOfflineUser(): Promise<boolean>`** (returns `delivered`). The `{channel, fallbackDelivered}` fields the emit wants are LOCAL to `notifyOfflineUser` (the `statutory-notify-zero-delivery` emit fires inside it). Widen only the three fallback-relevant email fns to `Promise<boolean>`: `sendEmailNotification` (dispatcher) + `sendEmailTriageEmailNotification` + `sendCostBreakerEmailNotification` + `sendInboxItemEmailNotification`. **Correction:** the plan's "four `send*EmailNotification` variants" is wrong — there are **three** triage-family variants (the DSAR/invite senders at `notifications.ts:947+` are NOT in the fallback path; do not widen them). No exported struct/union types.
- [ ] **M4 — corrects D4b cross-consumer sweep: `permission-callback.ts:169` was MISSED.** It declares `notifyOfflineUser: (userId, payload) => Promise<void>` as an injected dependency and calls it at 3 sites (313/799/975). `void`→`boolean` return-widening stays assignable so `tsc` will NOT flag the omission (exactly why `hr-type-widening-cross-consumer-grep` exists). Run the sweep over **declared dependency/interface signatures**, not just call sites. Disposition: leave `permission-callback`'s dep type `Promise<void>` (its 3 sites dispatch tool/`review_gate` payloads — out of the D4a must-not-fail-silently fallback class); record the file + this rationale in the sweep note.
- [ ] **M5 — corrects D4c: gate the rollback on `markerClaimedHere`.** The marker insert has a fail-open arm (`cron-email-ingress-probe.ts:379–387`): a non-23505 error OR a thrown error increments `failOpenCount` and **falls through to dispatch without a marker**. A `DELETE WHERE item_id AND tick_key` in that arm deletes a marker a *concurrent* run wrote → reopens the #6781 double-fire window. Set `markerClaimedHere = true` ONLY in the clean-insert branch; gate the rollback on it. Test: marker insert returns a non-23505 code, delivery fails, a pre-existing marker row survives.
- [ ] **M6 — corrects D4c: scope the rollback DELETE to `tickKey === "headsup"`.** The `daily:${runDateUtc}` key rotates daily (`cron-email-ingress-probe.ts:336–339`), so the next tick re-arms the daily arm for free regardless of the marker — deleting a `daily:` marker buys **zero** retry while re-opening the same-day double-fire window. All real rollback value lives on the constant `headsup` key. This removes the no-precedent `.delete()` from 4/5 of the surface and shrinks T19.
- [ ] **M7 — corrects D4c: wrap the rollback DELETE in `try/catch`.** Under `retries: 0` (pinned) a THROWN rejection (connection reset — the likeliest trigger, correlated across the band during a deploy blip) escapes the loop → escapes `step.run` → kills steps 3–5 → `postSentryHeartbeat` never posts → false "ingress chain broken" page daily. Mirror the insert's shape (`markerRollbackFailedCode ??= "threw"`). Test: a *thrown* DELETE rejection still leaves the probe healthy (`probeFound` true).
- [ ] **M8 — refines D4c: emit a per-rollback audit op, drop the bare counter.** The raw `.delete()` bypasses mig-135's audited `purge_statutory_repin_send` SECURITY-DEFINER boundary with no audit line. On a rollback (success and failure) emit via the file's existing warn-op precedent — `op: "statutory-repin-marker-rolled-back"` (info) / a `warnSilentFallback` on failure — carrying `{itemId, tickKey}`, instead of the untested `markerRollbackFailed` payload counter. Keep a `undelivered` counter (it maps to a real founder-facing failure mode); `markerRollbackFailed` becomes a warn-op, not a 7th payload field.
- [ ] **M9 — supersedes D3a escalation: DROP `excluded > 0` from the warn predicate.** `excluded` is **monotonic** — `acknowledged` is terminal (`102`), statutory rows live 365 days (`purge_email_triage_items`), so the first abandoned item pins `excluded > 0` **forever** → `deadline-repin-sweep-complete` escalates to warn on every run, permanently = the exact alert-fatigue #6813 fixes, reintroduced in the same PR (5-agent convergence). Escalate on `undelivered > 0 || markerRollbackFailed > 0 || suppressed > 0` only. Keep `excluded` as a structured field **and** a low-cardinality Sentry tag (`repin_excluded:yes|no`) → queryable = "reachable", which is #6801's real requirement. **Revise AC9:** assert `excluded` is present + queryable (tag), NOT that a non-zero `excluded` pages. **Revise AC (new):** a steady-state run with `excluded > 0` and zero delivery failures does NOT escalate to warn.
- [ ] **M10 — refines D3a: one typed tally + one escalation helper.** Define a `SweepTally` interface (single home for `pinged`/`suppressed`/`headsUpAlreadySent`/`undelivered`/`excluded`) and derive the level from `anomalyCount(tally) > 0` (a single helper), not an inline OR chain that rots as counters are added. `headsUpAlreadySent` is explicitly EXCLUDED from `anomalyCount`. Add every counter to the step return **and** `HandlerResult`; rewrite the `repinSuppressed` JSDoc (currently "the signal a second scheduler is live" — false after the split) to "daily-key 23505s only; a heads-up-band double-fire is detected via the daily arm". Test: each anomaly counter, non-zero in isolation, flips `warnSilentFallbackSpy` vs `infoSilentFallbackSpy`.
- [ ] **M11 — supersedes D2a: disambiguate the `headsup` 23505 by `created_at`, don't split by heuristic.** The marker table has `created_at timestamptz NOT NULL DEFAULT now()` (`135:81`). On a 23505 against the `headsup` key, read the existing marker's `created_at`: **same UTC date as `runDateUtc`** → a genuine same-tick double-fire → `suppressed`; **earlier date** → the expected band re-hit → `headsUpAlreadySent`. This is **exact**, one cheap select per band-item per day (single-digit population), and — unlike an `id` RETURNING — `created_at` exists so no 42703 trap. It removes the plan's stated "≤5-day detection delay" residual, which spec-flow/architecture showed is *wrong* anyway (an item resolved during the heads-up band never reaches the daily arm, so a band-only second scheduler would be undetected). A `daily:`-key 23505 stays unambiguously `suppressed` (same-day by construction). Record the mechanism + the fact it preserves the #6781 detector fully in the ADR-037 amendment.
- [ ] **M12 — supersedes T15: make the `breach-art33` invariant GENERIC.** Do not pin today's registry. Iterate `STATUTORY_RULES`: for every `hours`-kind rule whose max `daysUntilDue` `<= DEADLINE_REPIN_DANGER_THRESHOLD_DAYS`, assert no `headsup` key is ever produced. A future `{kind:"hours", hours:96}` rule then fails a test instead of silently writing `headsup` markers (the same latent-breakage class this PR is fixing for `=== 7`).
- [ ] **M13 — supersedes D5: extract the gate to `scripts/ship-incident-pir-gate.sh`.** Do NOT scrape regex literals out of Markdown. The repo's dominant pattern is `scripts/<name>.sh` + colocated `<name>.test.sh` (`check-adr-ordinals.sh`, `content-publisher.sh`, `inngest-liveness-classify.sh`). Move `OUTAGE_RE`/`PROD_RE` + the strips + the `grep -qiE` pipeline into the script (stdin → exit 0/1, owning its own exit semantics so the `A && B && echo` `set -e` trap disappears). `ship/SKILL.md` **calls** the script; the test **invokes the script directly** against fixtures. Satisfies AC19's intent (no re-declared regex) more strongly, and is shellcheck-able. Keep the regex-content fix (past-tense verbs, word-boundaries, threshold-label + hypothetical strips). **Rejected alt (DHH):** firing on a post-mortem-link/incident-label instead of prose — it cannot fire BEFORE the PIR exists, which is exactly when the gate must fire to *force* the PIR.
- [ ] **M14 — supersedes D5 fixtures: drop `this-plan.md` + AC21.** A frozen 1,271-line self-copy is stale-prone bloat testing the same property as the synthesized `preventive-hardening-single-user-incident.md` (a preventive `single-user incident` plan saying `prod`/`incident`). Ship **4** fixtures, not 5. Keep the synthesized ones (frozen by design per `cq-test-fixtures-synthesized-only`).
- [ ] **M15 — delete AC5.** `grep -rn "legal advice" apps/web-platform/` is vacuous (matches any code comment; also unbounded through `node_modules` → `hr-never-run-commands-with-unbounded-output`). T22/AC3 assert the framing on the rendered surfaces, which is the real criterion. (4-agent convergence + `cq-assert-anchor-not-bare-token`.)
- [ ] **M16 — supersedes ADR-134 title/invariant: "dispatch claim, released on observed non-delivery" — NOT "certify delivery".** `delivered` = transport acceptance (`Promise.allSettled` fulfilled / Resend 200), not receipt. Rename to `ADR-134-statutory-send-markers-are-dispatch-claims-released-on-observed-non-delivery.md`. `## Decision`: the marker is a claim; an observed zero-(or, per M18, partial-)acceptance releases it; the crash window between dispatch and release, and bounce/spam (Resend webhooks, a deliberate follow-up), are **named residuals** in `## Consequences`. This is the honest form and un-repeats the exact over-claim #6798 is about.
- [ ] **M17 — relabel the `observability.ts` edit honestly (AC12).** Keep the `infoSilentFallback` `tags`-passthrough fix (3 lines, 1 affected caller — sibling parity with `report`/`warn`), but stop claiming it "closes the `repin_suppressed` gap": once `suppressed > 0` routes through `warnSilentFallback` (which already merges tags), the info path only ever carries `repin_suppressed:"no"`. Re-label it as an independent sibling-parity bugfix; **AC12 asserts parity** (a `tags` arg reaches `Sentry.captureMessage` from `infoSilentFallback`), not gap-closure.
- [ ] **M18 — refines D4a: fire the fallback on `delivered < attempted`, not `delivered === 0`, for `mustNotFailSilently` classes.** A founder with two devices — a dead phone (WNS DROP, never pruned per D4c) and a stale-but-201-ing laptop — yields `delivered === 1`, suppressing the email while the founder on the road sees nothing. For the legal-clock class, partial delivery must still email. Accepted trade-off: one extra email when one of N registered devices is stale — the fail-safe direction for a `single-user incident` statutory notice. Record the cost in ADR-134.

### 0.9 outcome
`/soleur:plan-review` ran the escalated 5-agent eng panel + named cpo/cmo/cto (cpo hit a vendor
rate-limit; its product lens — the 60-day cliff, disclaimer under-reaction, batching — is covered by
spec-flow P1-1/P1-4 and cmo). 18 mechanical deltas adopted (M1–M18); 4 challenges surfaced to
`decision-challenges.md` (push-copy direction, the flow-gap follow-up tracker, the PR-split
challenge, the comment-only migration 136). Two GDPR-relevant items (no new processing) unchanged;
`/soleur:gdpr-gate` still runs at Phase 1.4.
