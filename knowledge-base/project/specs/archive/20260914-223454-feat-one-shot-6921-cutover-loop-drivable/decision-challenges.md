# Decision Challenges — feat-one-shot-6921-cutover-loop-drivable

Recorded during plan + plan-review (headless). Surfaced by /ship into the PR body + an
`action-required` issue for operator visibility.

## 1. The brief's third blocker (stale `CUTOVER_HOSTS` / destroyed web-2) was measured false — no host-set change ships

- **Class:** user-challenge → resolved to re-scope (premise validation, plan Phase 0.6).
- **Source:** plan Phase 0.6 premise validation; two read-only measurements.
- **Brief said:** `cutover-inngest.yml:135` pins `10.0.1.10,10.0.1.11` but web-2 was destroyed 2026-07-17; an unreachable peer makes `op=quiesce-web` / `op=rollback` report failure after mutating web-1 — "one-line pin fix".
- **Measured:** hcloud API (`doppler run -p soleur -c prd_terraform`, `GET /v1/servers`) lists `soleur-web-2` id 155786558 `running` at private 10.0.1.11, created 2026-07-27 (the cattle rebirth, #6969/ADR-143); Better Stack `--grep FANOUT` over 72 h shows 21× `peer 10.0.1.11 accepted deploy (HTTP 202)`, zero refusals; `cutover-inngest-workflow.test.sh` H1 already pins `CUTOVER_HOSTS` to `variables.tf`, so the proposed pin edit would redden CI.
- **Decision:** no pin change; the stale prose (web-2 "retired", web-2 "self-arms reminders", "freeze/recreate MANDATORY") is corrected to the measured state (web-2 born with `web_colocate_inngest=false`, no scheduler). The local-then-fan-out ordering is kept as risk R4 (re-dispatch converges).
- **If the operator disagrees:** the only alternative is removing web-2 from `var.web_hosts` + `WEB_HOST_PRIVATE_IPS` + `CUTOVER_HOSTS` together — a host-retirement decision (ADR-143), not part of this fix.

## 2. Capture-at-quiesce (D1b) added beyond the brief's stated item (1)

- **Class:** user-challenge (scope ADD) → resolved to fold in.
- **Source:** scoped advisor consult (ADR-083, plan Step 4.5) Change 1 + CPO advisory C1; feasibility verified read-only (`cloud-init.yml:250` `User=deploy`, `:267` `ReadWritePaths … -/var/lib/inngest`, `inngest-bootstrap.sh:142-143` deploy-owned dir; the enumerate needs no secret).
- **Brief said:** "(1) #6921: a second `op=execute` after `op=quiesce-web` must resume from the persisted on-host capture … instead of re-running 2.1 against the stopped web scheduler."
- **Plan does:** exactly that (D1) AND makes `op=quiesce-web`'s handler capture the still-armed reminders immediately before it stops the scheduler (fail-closed: no capture → no stop), so the persisted capture the second execute resumes from is taken at the quiesce boundary. Without D1b every persisted resume replays a capture minutes older than the stop and silently drops any reminder armed in between — a single-founder silent loss, the plan's brand-survival class.
- **Cost:** ~15 lines in the `quiesce` handler, the capture branch hoisted above the secret read in the rearm script, one new deploy-status reason, 5 test rows, one Guard Contract.
- **If the operator prefers the narrow scope:** drop D1b (Phase 1 step 4, Guard 5, FR12), restore the 2.1 `::warning::` naming the [capture, quiesce] window, and file the deferral issue the plan originally proposed.

## 3. Plan-review taste findings applied under the both-panels-fire rule (headless)

- **Class:** taste (auto-applied because the simplification and correctness panels fired on the same scopes; recorded here for operator visibility).
- **Source:** plan-review 5-agent panel + CTO devex, 2026-09-14.
- **Applied:** (a) the `web_scheduler` step output and every auto-close gate DELETED — a deliberate stop+disable resolves a "web scheduler down" issue, and every gating variant left some issue class unable to auto-close forever post-cutover; (b) `render_2_1` harness → two grep rows; (c) source-shape drift rows that only re-assert the diff removed; (d) FR13's DROPPED arm files an issue rather than shipping a re-arm clamp; (e) QG evidence lightened to "red before, green after"; (f) the `quiesce_capture_failed)` CI case arm dropped (the `*)` fast-fail carries the reason); (g) disable-before-stop + a documented single false tick (R8) instead of a second `deactivating`-tolerant predicate.
- **Not applied:** a pure-function extraction of the 2.2 verdict tree (the curl-stub region driver is the more faithful test); a shared predicate lib across the three delivered host scripts (a new FILE_MAP row; three literal copies + a cross-file parity grep instead).
- **If the operator disagrees with (a):** the narrowed in-body gate (only the three liveness-derived closes) is the documented alternative; it costs one step output re-emitted from `poolprobe` and `effmode` and leaves those three issue classes un-closeable after the cutover.
