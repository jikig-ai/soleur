---
title: "fix(cf-token-scope): retained Notifications probe queries nonexistent /notification_policies route (404/10404), fails closed"
type: fix
date: 2026-10-29
slug: fix-cf-token-scope-notification-route
branch: feat-one-shot-11480-cf-token-alerting-route
issue: 11480
closes: 11480
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-29
**Sections enhanced:** Research Insights (deepen-pass findings), Context
**Research agents used:** None — this harness has no Agent/Task spawn capability; research and
review were completed sequentially inline by the orchestrator.
**Reviewed-Coverage:** sequential-fallback

### Key Improvements

1. Verified the corrected endpoint against Cloudflare's current API reference (`GET
   /accounts/{account_id}/alerting/v3/policies`, "List Notification policies") and corroborated it
   in-repo (`infra-security.md:81`) and by the learning's measured-live authorized 200.
2. Surfaced the live duplicate (PR #11456, same three files) from the collision precheck into the
   plan's premise validation, and added the implementation step-0 duplicate-merge gate.
3. Pinned the corrected route against silent reversion with a Guard Contract entry (mock-dispatch
   chokepoint, 5-row mutation matrix including a must-PASS harness row).

### New Considerations Discovered

- The API reference documents no query parameters for this operation; the sibling PR ships the
  bare path while this plan keeps `?per_page=1` per the issue's explicit prescription — recorded
  as a `technical` row in `decision-challenges.md`.
- The mock's `*)` fallback arm returns a zone-shaped object, so a Notifications URL the dispatch
  does not recognize degrades to exit 3 rather than false-passing — the fail direction of a missed
  dispatch is safe.

# fix(cf-token-scope): retained Notifications probe queries nonexistent /notification_policies route

The `cf-token-scope` `default-token` profile's retained Notifications control queries
`GET /accounts/{account_id}/notification_policies`, a route Cloudflare does not serve — it returns
HTTP 404 / error 10404 (`No route for that URI`), so the baseline exits 3 (fail-closed) on every run
and the skill's widen precondition can never be met. Correct the probe to the documented
`GET /accounts/{account_id}/alerting/v3/policies` and move the skill's controls table and
URL-dispatch tests with it (#11480).

## User-Brand Impact

- **If this lands broken, the user experiences:** the `cf-token-scope` retained-scope ledger keeps
  reporting a wrong verdict on the Cloudflare API token that guards `soleur.ai` (a false
  "scope dropped" halt, or — only if the fix itself is botched — a false PASS that lets a widen
  proceed after a real scope loss). The failure direction of the shipped classifier stays
  fail-closed (exit 3), so the worst shipped-broken outcome is a continued blocking halt, not a
  silent pass.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the probe
  is a read-only authenticated GET whose only output is HTTP status plus a digit-sanitized error
  code; the token value rides a private-fd header (pinned by the `D-conf` argv-confinement asserts)
  and never reaches argv, logs, or stdout. The fix changes a URL string only.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change corrects a read-only URL and its test fixture;
  the worst outcome is a probe that keeps failing closed and a workflow that stays held, not a
  user-data, production-write, or permission exposure — same classification the sibling plan
  (`2026-10-28-fix-cloudflare-notifications-route-plan.md`) reached for the identical fix.

*Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by
preflight):* `threshold: none, reason: no diff path matches the canonical sensitive-path regex —
plugins/soleur/{skills,test}/ paths are outside apps/*, are not doppler-named, and no
.github/workflows file is touched; a regression fails the probe closed.`

## Research Insights

### Premise Validation (Phase 0.6)

- **Issue #11480** — verified `OPEN` via `gh issue view` (author: deruelle, labels:
  `domain/engineering`, `priority/p2-medium`, `type/chore`). Not resolved by any merged PR.
- **Cited edit sites confirmed on this branch:** `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh:102`
  carries `retained|accounts/<acct>/notification_policies|$API/accounts/\$ACCT/notification_policies?per_page=1|array|account`;
  `plugins/soleur/skills/cf-token-scope/SKILL.md:155` carries the same route in the controls table;
  `plugins/soleur/test/cf-token-scope.test.sh:89` (mock dispatch arm `*notification_policies*`) and
  `:281` (D1 dry-run fragment loop) pin the phantom route.
- **Cited learning** `knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md`
  is absent on this branch — it lands via PR #11479 (OPEN, docs-only, +30 lines). Read from the
  sibling worktree for context: a 404 is only meaningful to a permission classifier after the
  route itself is established; pin endpoint URLs to the provider's current API reference; keep the
  gate fail-closed until the retained control is corrected.
- **Endpoint verified against the provider's current API reference:**
  `GET /accounts/{account_id}/alerting/v3/policies` ("List Notification policies") — the reference
  documents `account_id` as the only parameter and lists no query parameters
  (developers.cloudflare.com/api/resources/alerting/subresources/policies/methods/list/).
  Corroborated in-repo: `plugins/soleur/agents/engineering/infra/infra-security.md:81` already calls
  `accounts/$ACCT_ID/alerting/v3/policies`, and the learning records a measured-live authorized 200
  on this route with the same profile credential (2026-10-28).
- **ADR corpus (Phase 0.6 step 4):** `ADR-130-cloudflare-token-widen-vs-narrow-alias.md` names the
  four-probe retained-scope set conceptually (Tunnel, Access, DNS, Notifications) but does not pin
  the endpoint string — a route correction does not reverse or extend the ADR (Phase 2.10 skips).
- **Mechanism-minimality (Phase 0.6b) — Property List:**
  P1 the retained Notifications probe queries a route that exists, so a healthy token reads
  `authorized (200)` and the fail-closed gate can pass; P2 the mock URL-dispatch models the
  corrected route so the suite exercises real dispatch; P3 the post-widen assert
  (`--expect-lb-scopes`) exercises the corrected endpoint; P4 the corrected route is pinned against
  silent reversion. **Cut List:** none — each proposed mechanism maps to a property and nothing on
  `origin/main` covers it (the route string IS the defect).
- **Collision report (Phase 0.6 step 6 — collision-precheck.sh exit 10):**
  - PR #11485 is this branch's own auto-created draft — not a foreign hit.
  - **Live duplicate:** PR #11456 (`WIP`, draft) on worktree
    `feat-one-shot-11181-cf-notification-route` implements this same fix on the same three files
    (verified by reading its diff: identical script/SKILL.md route change, plus a wider test
    expansion and a dedicated regex dispatch arm) and is mid-pipeline (`test-all.sh` processes
    running, latest commit `review-fix-round … final suite 183/183`). Its spec
    (`lane: single-domain`, threshold `none`) is the precedent this plan follows. Divergence: the
    sibling drops `?per_page=1` (its deepen pass found the API reference lists no query params);
    this plan keeps `?per_page=1` per the issue's explicit prescription — recorded as a `technical`
    row in `decision-challenges.md`. **Whichever PR lands first wins; the other rebases to a
    no-op diff.** Step 0 of implementation is a `git grep notification_policies origin/main` gate
    that closes #11480 as duplicate if the corrected route already landed.
  - Foreign `test-all.sh` processes in other worktrees are unrelated runs.

### Repo findings

- `cf-token-scope.sh` `DT_ROWS` (:98-105) is the single print/run-parity table: the label field is
  what the ledger prints, the URL template is what curl requests — both name
  `notification_policies` on the retained row and both move to `alerting/v3/policies` so the ledger
  keeps naming the route actually probed.
- Test mock dispatches on substring `case "$url" in` arms (:77-94); `*alerting/v3/policies*`
  collides with no sibling arm (`*/rulesets)` requires the URL to end in `/rulesets`; the
  `*load_balancers*` arms don't match). Arm ordering stays put (the pools-superstring ordering
  comment at :84-85 is unaffected).
- `MOCK_NOTIF` is only a mock lever (D3 loop :349 exports it per-row); the variable name does not
  name the route and needs no rename.
- The post-widen assert path (`--profile default-token --expect-lb-scopes`, D6/D7/D8) runs the full
  `DT_ROWS` table including the retained Notifications row — adding a `MOCK_CURL_URLLOG` capture to
  D7 and asserting the resolved `accounts/acct9876543210fedcba/alerting/v3/policies` URL pins P3 on
  the run path (same mechanism as the D2 run-path URL pin at :312-320).
- `references/widen-playbook.md` carries no `notification_policies` reference — no edit needed.
- CLAUDE.md conventions: none additional for this surface.

### Research decision (Phase 1.6)

External-API topic → the endpoint was verified against the live Cloudflare API reference (above)
plus in-repo corroboration (`infra-security.md:81`) plus the sibling's measured-live 200; no
best-practices/framework-docs fan-out needed for a one-line route correction. Research, review,
and advisor fan-outs ran **inline by the orchestrator** — this harness has no Agent/Task spawn
capability (`Reviewed-Coverage: sequential-fallback`); recorded as a `technical` row in
`decision-challenges.md`.

### Deepen-pass findings (2026-10-29)

- **`want_type` stays `array`:** the documented response shape is `result: array of Policy` —
  `?per_page=1` paginates but preserves the array contract the classifier checks.
- **Permission coverage:** the reference's Accepted Permissions (`Notifications Read` among them)
  are satisfied by the token's retained Notifications scope — corroborated by the learning's
  measured-live authorized 200 on this exact route.
- **Halt-gate results (deepen-plan Phases 4.6–4.13, run inline):** User-Brand Impact compliant
  (`none` + scope-out); Observability schema complete (allowlisted `grep` probe, literal
  `expected_output`, no ssh, inside the 15s cap); PAT sweep zero hits; no UI surface; no
  encryption trigger; Guard Contract `lint-guard-contract.py` rc=0 with a structural assembly
  (the mock `case` dispatch chokepoint) and a 5-row matrix; exactly one unfenced `## Scope Check`
  carrying `Recommendation: single PR`; no autonomous-task surface; no network-outage or downtime
  trigger. Test baseline verified green at 148/148 before the change.

## Files to Edit

- `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` — `DT_ROWS` retained row
  (:102 at file time): label `accounts/<acct>/notification_policies` →
  `accounts/<acct>/alerting/v3/policies`; URL `accounts/\$ACCT/notification_policies?per_page=1` →
  `accounts/\$ACCT/alerting/v3/policies?per_page=1`.
- `plugins/soleur/skills/cf-token-scope/SKILL.md` — controls-table retained row (:155):
  `accounts/<acct>/notification_policies` / `.../notification_policies?per_page=1` →
  `accounts/<acct>/alerting/v3/policies` / `.../alerting/v3/policies?per_page=1`. The
  `Notifications` permission label stays (it names the scope, not the route).
- `plugins/soleur/test/cf-token-scope.test.sh` — four edits in the D-series block:
  (a) mock dispatch arm (:89) `*notification_policies*)` → `*alerting/v3/policies*)`, same position
  and `MOCK_NOTIF` lever; (b) D1 dry-run fragment loop (:281) `notification_policies` →
  `alerting/v3/policies`; (c) post-widen assert (D7 block, :389-392): run under
  `MOCK_CURL_URLLOG` and assert the resolved
  `accounts/acct9876543210fedcba/alerting/v3/policies` URL appears (the corrected endpoint
  exercised on the assert path, per the issue); (d) regression pin near the D-doc/D12 block:
  `src_lacks 'notification_policies'` (prevents silent reversion of this exact defect) and
  `d_has 'alerting/v3/policies' "$SKILLDOC"` (keeps the documented route from drifting back).

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` on 2026-10-29; zero issue bodies
match any of the three planned paths or `cf-token-scope`.

## Observability

```yaml
liveness_signal:
  what: "PASS verdict ledger line 'PASS: no scope dropped' + exit 0 on each --profile default-token run"
  cadence: "per-run (operator-invoked: pre-widen baseline and post-widen --expect-lb-scopes assert)"
  alert_target: "operator terminal — stdout verdict ledger, exit code is the machine-readable signal"
  configured_in: "plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh (verdict emit) + plugins/soleur/test/cf-token-scope.test.sh (verdict pinning)"
error_reporting:
  destination: "stderr 'FAIL: retained-scope probe failed' + exit 3 (stream contract pinned by D6)"
  fail_loud: "exit 3 with per-row 'denied (404, unverified — fail-closed)' / 'degraded (200 body not success/array)' / 'denied (403)' verdict on stdout"
failure_modes:
  - mode: "Notifications probe hits a removed/renamed Cloudflare route (the defect this fixes, or a future move)"
    detection: "per-row 'denied (404, unverified — fail-closed)' verdict line + exit 3"
    alert_route: "operator terminal — blocking verdict, never a silent pass"
  - mode: "endpoint returns a non-array or non-success 200 (degraded response)"
    detection: "per-row 'degraded (200 body not success/array)' verdict + exit 3 (D4a/D4b/D4c pinned)"
    alert_route: "operator terminal — blocking verdict"
  - mode: "phantom route reintroduced into script, SKILL.md, or mock dispatch"
    detection: "src_lacks 'notification_policies' pin + D1 fragment loop + D7 URL-log assert redden"
    alert_route: "CI — plugins/soleur/test/cf-token-scope.test.sh exits non-zero"
logs:
  where: "stdout/stderr of the invoking session (per-row verdict ledger); the script is synchronous — no daemon log"
  retention: "session transcript lifetime; CI retains the suite output for the run"
discoverability_test:
  command: "grep 'alerting/v3/policies' plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh"
  expected_output: "alerting/v3/policies"
```

## Guard Contract

### Guard 1 — URL-dispatch conformance for the corrected Notifications probe

**Property.** Every probe URL the `default-token` profile issues or dry-run prints is dispatched by
the mock to a verdict-bearing spec, and the retained Notifications row is pinned to Cloudflare's
documented `alerting/v3/policies` route such that a route regression fails the suite.

**Assembly.** The mock's `case "$url" in` dispatch (`plugins/soleur/test/cf-token-scope.test.sh`
heredoc) is the single chokepoint every curl URL the SUT issues flows through — the substring arms
are the assembly, not an inventory of current probes. The pin set: the `*alerting/v3/policies*`
dispatch arm, the D1 dry-run fragment loop, the D7 assert-mode URL-log assert, the
`src_lacks 'notification_policies'` source pin, and the `d_has` SKILL.md doc pin.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert the `DT_ROWS` retained URL to `notification_policies` (mock arm no longer matches → `*)` arm returns a zone-shaped body on an account row) — and `src_lacks 'notification_policies'` fires | RED |
| 2 | Delete the `*alerting/v3/policies*` dispatch arm (guard's own dispatch: probe falls to the `*)` default spec) | RED |
| 3 | Revert only the row's label field to `accounts/<acct>/notification_policies` leaving the URL correct | RED (source pin) |
| 4 | Append a SECOND retained row after the compliant first (new endpoint fragment) — it falls to `*)` and degrades, proving multi-member coverage is not first-member-only | RED |
| 5 | Harness row: weaken `src_lacks` to `src_has` with the URL still correct | PASS (must-PASS, non-canonical: the pin asserts absence, not the route's correctness — the behavioral arms carry that) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "retained-row URL `accounts/\$ACCT/notification_policies?per_page=1` → `accounts/\$ACCT/alerting/v3/policies?per_page=1` (line ~102 at file time)" [issue #11480] | `cf-token-scope.sh` `DT_ROWS` row edit | mapped |
| 2 | "the same route in the controls table (line ~155)" [issue #11480] | `SKILL.md` controls-table row edit | mapped |
| 3 | "The profile's URL-dispatch tests — update together per the learning, and exercise the corrected endpoint in the post-widen assert." [issue #11480] | `cf-token-scope.test.sh` edits (a)–(c) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cf-token-scope.sh` retained-row label + URL | "retained-row URL … → `accounts/\$ACCT/alerting/v3/policies?per_page=1`" | asked |
| `SKILL.md` controls-table row | "the same route in the controls table" | asked |
| test edits (a) mock dispatch arm, (b) D1 fragment loop | "The profile's URL-dispatch tests — update together per the learning" | asked |
| test edit (c) D7 assert-mode URL-log assert | "exercise the corrected endpoint in the post-widen assert" | asked |
| test edit (d) `src_lacks 'notification_policies'` + `d_has 'alerting/v3/policies'` pins | — | inferred — justification: encodes the cited learning's prevention ("pin the live route in tests"), one line each in a file already being edited, keeps the phantom route from silently returning through either the script or the doc |
| Implementation step 0 duplicate-merge gate (`git grep notification_policies origin/main`) | — | inferred — justification: collision-precheck found PR #11456 implementing the identical fix in flight; the gate prevents shipping a no-op duplicate |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 3 | Estimated changed lines: ~15
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `git grep -n 'alerting/v3/policies' -- plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh plugins/soleur/skills/cf-token-scope/SKILL.md` shows the corrected route on the retained row and the controls-table row.
- [ ] `git grep -n 'notification_policies' -- plugins/soleur/` returns zero matches (script, SKILL.md, test, and mock dispatch all moved).
- [ ] `bash plugins/soleur/test/cf-token-scope.test.sh` exits 0 with all assertions green (record the pass count in the PR body).
- [ ] The D7 assert-mode run (`--profile default-token --expect-lb-scopes`) logs a request to the resolved `accounts/<acct>/alerting/v3/policies` URL — the corrected endpoint is exercised on the post-widen assert path.
- [ ] A mocked 404 on the corrected route still exits 3 with `denied (404, unverified` per-row attribution (fail-closed posture unchanged — the fix moves the route, not the classifier).
- [ ] Duplicate gate: if `git grep notification_policies origin/main -- plugins/soleur` is already empty at implementation start (sibling landed first), halt work and close #11480 as duplicate rather than shipping a no-op diff.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Semantic assessment across
all 8 domains (marketing/engineering/operations/product/legal/sales/finance/support per
`brainstorm-domain-config.md`): a read-only URL correction inside an existing dev-tooling script and
its test fixture matches no Assessment Question; the Engineering question requires significant
architecture beyond normal implementation, which a one-line route fix is not. Product/UX
mechanical override: no `Files to Edit`/`Files to Create` path matches the UI-surface term list —
Product/UX gate does not fire.

## Test Scenarios

All scenarios run inside `plugins/soleur/test/cf-token-scope.test.sh` (`integration` layer —
shell-suite with mocked curl/doppler; no e2e scenario prescribed: the live Cloudflare call needs the
operator-held `CF_API_TOKEN`, which CI does not and must not carry).

- Given the corrected route, when the mock returns an authorized array 200 on `*alerting/v3/policies*`, then the `default-token` baseline exits 0 with `authorized (200)` on the `accounts/<acct>/alerting/v3/policies` row — `integration`.
- Given a 404 on the corrected route, when the baseline runs, then the row reports `denied (404, unverified` and the run exits 3 — `integration` (fail-closed posture unchanged).
- Given `notification_policies` anywhere in the SUT source, when the suite runs, then `src_lacks 'notification_policies'` fails — `integration` (regression pin).
- Given post-widen assert mode, when `--profile default-token --expect-lb-scopes` runs, then the mock's URL log contains `accounts/acct9876543210fedcba/alerting/v3/policies` — `integration`.
- Given the doc surface, when the suite runs, then `d_has 'alerting/v3/policies' "$SKILLDOC"` passes and no `notification_policies` remains in SKILL.md — `integration`.
- **API verify (operator-side, post-merge):** `doppler run -- curl -s -o /dev/null -w '%{http_code}' -H @<fd-with-Authorization> "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/alerting/v3/policies?per_page=1"` expects `200` — mirrors the learning's measured-live check; run on the same private-fd header form the script uses.

## Context

- **Live duplicate (collision-precheck hit, reported not silently continued):** PR #11456
  (`feat-one-shot-11181-cf-notification-route`, draft WIP) implements this same fix on the same
  three files with a wider test expansion; it is mid-pipeline. If it merges first, this PR rebases
  to a no-op and closes. If this one lands first, the sibling's residual value is its extra
  per-row assertion coverage — a follow-up candidate, not a blocker. Recorded as a `technical` row
  in `decision-challenges.md`.
- **`?per_page=1` divergence:** the issue prescribes `alerting/v3/policies?per_page=1`; the sibling
  plan's deepen pass found the API reference documents no query params for this operation and
  shipped the bare path. This plan keeps `?per_page=1` — the issue prescribes it explicitly, every
  sibling `DT_ROWS` URL carries it (uniform print/run parity), and an unsupported param is ignored
  while a supported one bounds the payload. `technical` row in `decision-challenges.md`.
- **Headless/pipeline disclosures:** no Agent/Task spawn capability in this harness — the Phase 1
  research fan-out, functional-overlap agent, SpecFlow analyzer (Phase 3), scoped advisor consult
  (Phase 4.5), domain leaders, and the plan-review panel all ran as orchestrator-inline checks or
  were skipped with reasons recorded here and in `decision-challenges.md`
  (`Reviewed-Coverage: sequential-fallback`).
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold fails `deepen-plan` Phase 4.6 — filled above.

## References

- Issue: #11480 — `fix(cf-token-scope): retained Notifications probe queries nonexistent /notification_policies route (404/10404), fails closed`
- Learning (lands via PR #11479): `knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md`
- ADR-130: `knowledge-base/engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md` — the four-probe retained-scope set this row belongs to
- Cloudflare API reference: `GET /accounts/{account_id}/alerting/v3/policies` — [List Notification policies](https://developers.cloudflare.com/api/resources/alerting/subresources/policies/methods/list/)
- In-repo corroboration: `plugins/soleur/agents/engineering/infra/infra-security.md:81`
- In-flight duplicate: PR #11456 (`feat-one-shot-11181-cf-notification-route`); sibling plan `knowledge-base/project/plans/2026-10-28-fix-cloudflare-notifications-route-plan.md` (lives in the sibling worktree, not this branch — context citation, not a dependency)
