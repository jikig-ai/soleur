---
title: "feat: continuous between-deploy inngest durability detector (#5553)"
type: feat
issue: 5553
branch: feat-one-shot-5553-continuous-inngest-durability-detector
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-18
---

# feat: Continuous between-deploy inngest durability detector

Closes #5553

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Overview (precedent-diff), User-Brand Impact (verify-the-negative), Risks, new Precedent-Diff section
**Gates passed:** 4.6 User-Brand Impact (present, threshold `single-user incident`), 4.7 Observability (all 5 fields, no SSH in discoverability command), 4.8 PAT-shaped (none), 4.9 UI-wireframe (no UI surface — skip)

### Key Improvements
1. **Precedent-diff (Phase 4.4, scheduled-work):** The workflow we extend already carries a `gate-override: new-scheduled-cron-prefer-inngest` justification — an Inngest cron cannot detect Inngest being down, so this watchdog MUST stay external GH-Actions (ADR-033 "prefer Inngest" is correctly overridden). Our extension inherits that override by adding to the existing workflow, not creating a new cron. No new Inngest function.
2. **Verify-the-negative (Phase 4.45) — the AC3 no-leak claim is structurally sound:** confirmed at source that `systemctl show -p ExecStart inngest-server.service` returns the **literal `$VAR`/sentinel form** (`inngest-bootstrap.sh:~318` writes `@@BACKEND_FLAGS@@` + `"$${POSTGRES_*}"` inside a single-quoted heredoc resolved only at runtime by `doppler run`), never the resolved DSN — exactly as `ci-deploy.sh:273` documents ("$VAR form — no secret value"). The substring match and emitted enum cannot touch a real secret.
3. **Three-parser drift gate (Phase 3) justified:** verified two existing ExecStart-`--postgres-uri` parsers (`ci-deploy.sh:277-287`, `inngest-wiped-volume-verify.sh:97-98`); this is the 3rd. Infra has no `source`-lib precedent, so a cross-file drift-guard test is the correct (cheaper, convention-consistent) pin vs. a novel shared lib.

### New Considerations Discovered
- `inngest-inventory` IS in Vector's tag allowlist (`vector.toml:132`, added by #5526), so the journald `durability=<enum>` summary reaches Better Stack — the `error_reporting` observability claim holds (contrast #5495 where untagged journald did NOT reach Better Stack). **The `inngest-inventory.sh:35` header is now STALE** ("it does NOT reach Better Stack — see #5495") and Phase 1.4 MUST correct it.
- The seam pattern is already established: `inngest-wiped-volume-verify.sh:97` uses `INNGEST_VERIFY_EXECSTART:-$(systemctl show …)`; adopt the identical env-override shape (`INVENTORY_EXECSTART`, `INVENTORY_REDIS_ACTIVE`) for CI (no `systemctl` in CI).

### Deepen-plan multi-agent review corrections (3-reviewer consensus, applied)
Architecture-strategist + observability-coverage-reviewer + code-simplicity-reviewer **independently converged** on one P0/P1: the plan's original "`degraded` → neither file nor close" routing **re-opened the exact silent-loss hole the feature exists to close**. `degraded` (= `--postgres-uri` present but `--redis-uri` absent OR `inngest-redis` inactive) is the **#5542 incident state** ("durable ExecStart live but inngest-redis missing", `scheduled-inngest-health.yml:12`) and the canonical `ci-deploy.sh:278-286` treats it as a **hard FAIL** — strictly MORE severe than `sqlite_only` (which ci-deploy treats as advisory/pass). The between-deploy window has nothing else re-checking it, and `inngest_down` only trips on non-200/missing-functions — a redis-dead-but-still-serving host returns 200 and falls in the gap. **Corrections applied below:**
1. **`degraded` now ALERTS** — the advisory step fires on the **non-durable union** (`sqlite_only` OR `degraded`), with `priority/p1-high` for `degraded` (canonically fatal) and `priority/p2-medium` for `sqlite_only` (canonically advisory). [P0-1]
2. **Distinguish field-absent from value-`unknown`** — probe reads `// "absent"`; a literal `"unknown"` from a redeployed host (live parser/unit-read failure) emits a `::warning::` + journald `durability=unknown` so it is visible; `absent` (older host) stays benign-silent but emits a one-line `::notice::` so the blind window is itself visible. [P1-2, P1-3, obs-P1-2]
3. **Auto-close on "now durable"** — close/comment keys off `durability_state == 'durable'` AND comments a transition when an open issue's host moves `sqlite_only↔degraded` so the issue does not silently rot at a non-durable-non-sqlite state. [P2-1]
4. **Drift-guard token list adds `inngest-server.service`** (the unit being parsed is load-bearing too); the guard is explicitly documented as a **token-co-occurrence tripwire, NOT a verdict-equivalence proof** — the five Phase 2.2 verdict tests are the real pin for THIS parser. [P1-1, P2-3]
5. **`degraded` kept, not cut** (simplicity reviewer's alternative) — the architecture/observability P0 wins: `degraded` must exist AND alert; collapsing it into `unknown` would silence the most dangerous state.

## Overview

The deploy-time degraded-durability signal (`verify_inngest_health`'s `logger -t ci-deploy`
"INNGEST_DURABLE: advisory" line + the `success_degraded_durability` deploy-status reason,
shipped in **PR #5550** which closed issue **#5547**) fires **only at deploy time**. A host that
runs the SQLite-only fail-safe ExecStart **between** deploys re-alerts no one: the 15-min
`scheduled-inngest-health.yml` watchdog probes the `inngest-inventory` hook and asserts only
`.functions | type == "array"`, which is `true` for a SQLite-only-but-alive server. So an
extended SQLite-only window (Redis lost on a rebuild that somehow skipped re-install, or a
deploy that never re-staged Redis) is **invisible** until the next inngest deploy.

This plan adds a **continuous** between-deploy detector across three materially-unrelated files:

1. **`apps/web-platform/infra/inngest-inventory.sh`** — add a new no-SSH `durability_state`
   field to the pure-JSON hook body, derived ON-HOST from `systemctl show -p ExecStart
   inngest-server.service` + `systemctl is-active inngest-redis.service` (mirroring
   `ci-deploy.sh` `verify_inngest_health` lines 264-299). SSH is forbidden
   (`hr-no-ssh-fallback-in-runbooks`); the hook already executes on-host via the webhook.
2. **`apps/web-platform/infra/inngest-inventory.test.sh`** — add the env-override test seam
   (`INVENTORY_EXECSTART`, `INVENTORY_REDIS_ACTIVE`) and cases for each durability state, plus
   re-assert the #5503 combined-stream-purity invariant with the new field present.
3. **`.github/workflows/scheduled-inngest-health.yml`** — extend the probe to read
   `.durability_state`; when it is **non-durable** (`sqlite_only` OR `degraded`), file/comment an
   advisory `ci/inngest-degraded-durability` tracking issue (`priority/p1-high` for `degraded` —
   the #5542 incident state; `priority/p2-medium` for `sqlite_only`) and auto-close it when durable
   again. This is a SEPARATE signal from the existing `inngest_down` hard-outage path: the
   server is alive, so it does **not** dispatch a restart.

**Why this shape:** the inventory hook already exists (`hooks.json.tmpl:100-117`,
`include-command-output-in-response: true`), already runs on-host with `systemctl` access, and
is already in Vector's tag allowlist (`vector.toml:132`), so its journald summary reaches Better
Stack. We change only script *output* + workflow *logic* — no new infra, no new secret, no new
vendor, no `hooks.json.tmpl` change.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body / prompt) | Reality (verified) | Plan response |
| --- | --- | --- |
| Deploy-time signal shipped in "#5547 fix" | Issue body says #5547; prompt says #5550. **Both correct**: PR **#5550** (commit `2d0ea8110`) shipped `verify_inngest_health` + `success_degraded_durability` and **closed issue #5547**. | Cite PR #5550 / issue #5547 precisely in the plan + PR body; no scope change. |
| Inventory hook exposes only `{functions, event_names, armed_reminders}` | Confirmed: `inngest-inventory.sh:204-205` emits exactly those three keys. | Add a 4th key `durability_state`. |
| Need to change `hooks.json.tmpl` | **No.** Hook already registered with `include-command-output-in-response: true` (`hooks.json.tmpl:100-117`). | `hooks.json.tmpl` is NOT in Files to Edit. |
| No precedent for parsing ExecStart durability | **Two** precedents exist: `ci-deploy.sh:277-287` and `inngest-wiped-volume-verify.sh:97-98`. With this change there will be **three** ExecStart-`--postgres-uri` parsers. | Duplicate inline (infra has no `source`-lib pattern) BUT add a cross-file drift-guard test so the three stay in agreement. See Architecture Decision note. |
| #5450 (durability epic) is the re-eval dependency | Confirmed OPEN; this issue is the no-SSH continuous-durability-surface slice the #5553 scope-out named as its re-eval trigger. | Reference #5450 (`Ref #5450`); do not close it. |

## User-Brand Impact

**If this lands broken, the user experiences:** a SQLite-only inngest server runs silently for
days; an armed reminder (e.g. a scheduled GitHub-issue follow-up the founder is relying on) is
lost on the next host rebuild with **no alert** — the exact silent-loss this detector exists to
surface. A *false-positive* detector (mis-reads a healthy durable ExecStart as `sqlite_only`)
files spurious P-noise issues that train the founder to ignore the channel.

**If this leaks, the user's data is exposed via:** the inventory hook is HMAC + CF-Access gated
and returns only a state *enum* (`durable` / `sqlite_only` / `degraded` / `unknown`) — never the
`--postgres-uri` / `--redis-uri` connection-string **values** (#5503 purity: stdout = pure JSON,
no secret values; the substring match reads the `$VAR`-form ExecStart, not resolved secrets).
The new field carries no PII and no secret. Exposure vector: none beyond the existing gated hook.

**Brand-survival threshold:** single-user incident — inherited from the durability epic (#5450);
a single lost armed reminder is a single-user brand incident under that framing.

> CPO sign-off required at plan time before `/work` begins. The durability framing was set by the
> #5450 epic / #5547 PR review (`user-impact-reviewer` Finding 4); confirm CPO has reviewed that
> framing, or invoke the CPO domain leader. `user-impact-reviewer` will be invoked at review time.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing; no code)

0.1 Re-read the canonical durability logic at `ci-deploy.sh:264-299` (the verdict source of
    truth) and the seam precedent at `inngest-wiped-volume-verify.sh:97-98` (`INNGEST_VERIFY_EXECSTART:-$(systemctl show inngest-server.service -p ExecStart …)`).
0.2 Confirm the #5503 purity test still gates: `inngest-inventory.test.sh:88-101`
    (`test_combined_is_pure_json_object` — `combined=$(bash "$TARGET" 2>&1)` must parse as a
    JSON object). Our new field MUST keep stdout pure and emit nothing new to stderr on success.
0.3 Confirm `inngest-inventory.test.sh` runs in CI at `infra-validation.yml:199-200`.
0.4 Confirm `inngest-inventory` is in Vector's tag allowlist (`vector.toml:132`) so the journald
    durability summary reaches Better Stack (observability layer citation).

### Phase 1 — `inngest-inventory.sh`: derive + emit `durability_state` (RED first)

1.1 Add a `derive_durability_state()` function (snake_case, `local` vars, `[[ ]]` tests, per
    constitution) that mirrors `ci-deploy.sh:277-287` exactly:
    - Read ExecStart via the **seam-overridable** form (so CI has no `systemctl`):
      `exec_start="${INVENTORY_EXECSTART:-$(systemctl show -p ExecStart inngest-server.service 2>/dev/null || true)}"`
    - Read Redis activeness via a seam: `redis_active="${INVENTORY_REDIS_ACTIVE:-$(systemctl is-active inngest-redis.service 2>/dev/null || echo inactive)}"`
    - Verdict (returns ONE enum string on stdout):
      - `exec_start` contains `--postgres-uri` AND contains `--redis-uri` AND `redis_active == active` → `durable`
      - `exec_start` contains `--postgres-uri` but **lacks** `--redis-uri`, OR `--postgres-uri` present but `redis_active != active` → `degraded` (durable backend configured but the durability invariant is broken — the `verify_inngest_health` FAIL arms)
      - `exec_start` lacks `--postgres-uri` (SQLite-only fail-safe) → `sqlite_only`
      - `exec_start` empty (could not read the unit; service-down case is already caught by the functions guard) → `unknown`
    - **Never** echo `exec_start` itself (it carries `$VAR`-form connection refs); emit only the enum.
1.2 Call `derive_durability_state` inside `run_inventory()` and add the result to the final
    object: `jq -nc … --arg d "$durability_state" '{functions:$f, event_names:$e, armed_reminders:$r, durability_state:$d}'` (extend line 204-205).
1.3 Extend the journald summary (line 201) to append `durability=<enum>` (counts/enum only,
    no values — #5503 purity preserved): `logger -t "$LOG_TAG" "inventory: functions=… armed=… durability=$durability_state"`.
1.4 Update the file header doc-comment (lines 7-10) to document the new 4th field and the seam
    env vars (`INVENTORY_EXECSTART`, `INVENTORY_REDIS_ACTIVE`). **AND correct the now-stale line
    ~35** which reads "it does NOT reach Better Stack — see #5495" — `inngest-inventory` was added
    to Vector's tag allowlist (`vector.toml:132`, #5526), so its journald DOES now ship to Better
    Stack; rewrite that sentence to say so (the `durability=<enum>` summary is the load-bearing
    no-SSH carrier for the degraded state).

### Phase 2 — `inngest-inventory.test.sh`: seam + state cases (write tests, watch them drive Phase 1)

2.1 Add a `run_inv_durability()` helper that sets `INVENTORY_EXECSTART` + `INVENTORY_REDIS_ACTIVE`
    alongside the existing fixture seams (mirror `run_inv()` at lines 79-81), so the GraphQL
    fixtures still satisfy the functions/events path while we vary the durability inputs.
2.2 Cases (use `assert_eq`):
    - `durable`: ExecStart `… --postgres-uri postgres://x --redis-uri redis://y`, redis `active` → `.durability_state == "durable"`.
    - `degraded` (no redis flag): `… --postgres-uri postgres://x --sqlite-dir /d`, redis `active` → `"degraded"`.
    - `degraded` (redis inactive): `… --postgres-uri … --redis-uri …`, redis `inactive` → `"degraded"`.
    - `sqlite_only`: `… --sqlite-dir /var/lib/inngest` (no `--postgres-uri`), redis `inactive` → `"sqlite_only"`.
    - `unknown`: `INVENTORY_EXECSTART=""` → `"unknown"`.
2.3 **Secret-leak guard:** assert the combined output does **not** contain the connection-string
    token (e.g. seed `INVENTORY_EXECSTART="… --postgres-uri postgres://SECRET-DSN …"` and assert
    `SECRET-DSN` is absent from `$(bash "$TARGET" 2>&1)`) — mirrors the existing `SECRET-BODY`
    journald guard (lines 145-165).
2.4 **Purity regression:** re-run `test_combined_is_pure_json_object` shape with the new field —
    assert `jq 'has("durability_state")'` AND object still has the original three keys AND
    success-path stderr is empty (lines 88-101 pattern).

### Phase 3 — cross-file drift guard (the 3rd-occurrence gate)

3.1 Add a drift-guard test (in `inngest-inventory.test.sh`, or a tiny new assertion block) that
    greps `ci-deploy.sh`, `inngest-wiped-volume-verify.sh`, and `inngest-inventory.sh` and
    asserts all three reference the same load-bearing tokens (`--postgres-uri`, `--redis-uri`,
    `inngest-redis.service`, **`inngest-server.service`** — the unit being parsed is load-bearing
    too). This makes a future change to the durability rule in one file fail CI until the others
    are reconciled — cheaper than a sourced lib (infra has no source-lib precedent), and
    consistent with `ci-deploy-wrapper.test.sh:225` / `bwrap-userns-sysctl.test.sh` drift-guard
    style. **Scope note (per simplicity review):** this guard is a token-co-occurrence TRIPWIRE,
    NOT a verdict-equivalence proof — it cannot catch a logic inversion that keeps all tokens
    present. The five Phase 2.2 verdict tests are the real pin for THIS (the new) parser; the
    tripwire's job is only to force a human to re-look at all three when one changes. (Document the
    deferred shared-lib option in the Architecture note.)

### Phase 4 — `scheduled-inngest-health.yml`: continuous detector + advisory issue

4.1 In the probe step (after the `inngest_down` / `inngest_unhealthy` checks at lines 92-106),
    on a **healthy** body (200 + functions array), additionally read
    `dstate=$(printf '%s' "$BODY" | jq -r '.durability_state // "absent"')` and expose it as a
    `$GITHUB_OUTPUT` (`durability_state=$dstate`, run through `strip_log_injection`).
    **Distinguish field-absent from value-unknown** (review P1-2/P1-3): `absent` = older host
    script not yet redeployed (benign; emit a one-line `::notice::` so the blind window is itself
    visible, but file no issue); a literal `"unknown"` = a redeployed host whose live parser could
    not read the unit (a real parser/permission regression — emit `::warning::` + it flows to
    journald `durability=unknown`). Do **not** flap on `absent`.
4.2 Add a NEW step `File or comment durability advisory (non-durable)` gated on the **non-durable
    union**: `steps.probe.outputs.failure_mode == '' && (steps.probe.outputs.durability_state ==
    'sqlite_only' || steps.probe.outputs.durability_state == 'degraded')`. **This is the load-bearing
    review-P0 fix:** `degraded` (durable backend configured but `--redis-uri` absent or
    `inngest-redis` inactive) is the #5542 incident state and is canonically MORE severe than
    `sqlite_only` — it must NOT be silenced. The step `gh label create
    "ci/inngest-degraded-durability"` (idempotent, mirrors line 140), then files **or comments** an
    advisory issue titled `[ci/inngest-degraded-durability] Inngest non-durable between deploys`.
    **Label by severity:** `priority/p1-high` when `durability_state == 'degraded'` (canonically
    fatal — durable backend half-broken, live armed-reminder loss risk now, not just on rebuild);
    `priority/p2-medium` when `sqlite_only` (server alive on the fail-safe; armed reminders survive
    until a host rebuild). Body: the specific state, detected-at, run URL, and the remediation
    pointer (re-deploy inngest with Redis ready / restart `inngest-redis.service`; cite
    `knowledge-base/engineering/operations/runbooks/inngest-server.md` + #5450). Idempotent
    open-issue "persists across probes" mechanism: first non-durable probe files; subsequent
    non-durable probes comment "still <state> at <ts>" (**including a state TRANSITION comment when
    the host moves `sqlite_only↔degraded`** so the issue never silently rots — review P2-1); the
    auto-close step (4.3) closes it when durable. (No GH-Actions cross-run cache needed — ExecStart
    is a deterministic config read; the open-issue-state IS the cross-probe persistence carrier,
    same pattern as the existing `inngest_down` issue.)
4.3 Add an auto-close step gated on
    `steps.probe.outputs.failure_mode == '' && steps.probe.outputs.durability_state == 'durable'`
    that closes any open `ci/inngest-degraded-durability` issue (mirror the `inngest_down`
    auto-close at lines 160-174). Leave only `absent`/`unknown` neither-file-nor-close (`absent`
    is benign-self-healing; `unknown` is surfaced via the 4.1 `::warning::` + journald, not an
    issue, since it is a read failure not a confirmed degradation). **`degraded` is NOT in the
    neither-branch** — it files via 4.2.
4.4 Do NOT add a Sentry-heartbeat monitor for this advisory (the existing
    `scheduled-inngest-health` heartbeat already covers liveness; durability degradation is an
    advisory issue, not a missing-check-in). Keep the final heartbeat step (lines 176-185)
    unchanged.

### Phase 5 — Local verification (no SSH, no prod write)

5.1 `bash apps/web-platform/infra/inngest-inventory.test.sh` → all PASS, 0 FAIL.
5.2 `shellcheck apps/web-platform/infra/inngest-inventory.sh` (clean, or only pre-existing
    `# shellcheck disable` directives).
5.3 `actionlint .github/workflows/scheduled-inngest-health.yml` for the YAML + extract each new
    `run:` block and `bash -c '<snippet>'` it (NEVER `bash -n` the `.yml` — parses YAML as bash,
    per the composite-action Sharp Edge).
5.4 Manually run the inventory script with a fixture ExecStart to eyeball the JSON shape:
    `INVENTORY_EXECSTART='… --postgres-uri x --redis-uri y' INVENTORY_REDIS_ACTIVE=active INNGEST_GQL_FIXTURE_DIR=… INVENTORY_FUNCTIONS_FIXTURE=… bash inngest-inventory.sh | jq .durability_state`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `inngest-inventory.sh` emits a JSON object with **four** keys including
      `durability_state` whose value is one of `durable|degraded|sqlite_only|unknown`. Verify:
      `INVENTORY_EXECSTART='--postgres-uri x --redis-uri y' INVENTORY_REDIS_ACTIVE=active … bash inngest-inventory.sh | jq -e '.durability_state == "durable" and has("functions") and has("event_names") and has("armed_reminders")'`.
- [x] AC2: The four state verdicts are correct — `inngest-inventory.test.sh` contains and passes
      the five cases in Phase 2.2 (`durable`, two `degraded` arms, `sqlite_only`, `unknown`).
      Verify: `bash apps/web-platform/infra/inngest-inventory.test.sh` reports `FAIL: 0` and the
      five durability case descriptions appear in `PASS:` output.
- [x] AC3: **Secret purity** — the resolved/`$VAR`-form ExecStart connection ref never reaches
      stdout/stderr. Verify: `INVENTORY_EXECSTART='--postgres-uri postgres://SECRET-DSN --redis-uri r' INVENTORY_REDIS_ACTIVE=active … bash inngest-inventory.sh 2>&1 | grep -c SECRET-DSN` returns `0`.
- [x] AC4: **#5503 purity preserved** — `test_combined_is_pure_json_object` still passes with the
      new field; success-path stderr is empty. Verify: present in the test PASS output.
- [x] AC5: **Drift guard** — a test asserts all three ExecStart-durability parsers
      (`ci-deploy.sh`, `inngest-wiped-volume-verify.sh`, `inngest-inventory.sh`) reference
      `--postgres-uri`, `--redis-uri`, and `inngest-redis.service`. Verify: the drift-guard test
      case appears in `inngest-inventory.test.sh` PASS output.
- [x] AC6: The workflow validates + exposes durability. Verify: `actionlint
      .github/workflows/scheduled-inngest-health.yml` exits 0, and the probe step writes
      `durability_state=` to `$GITHUB_OUTPUT` (grep the workflow for `durability_state=`).
- [x] AC7: The advisory-issue step is gated on the **non-durable union** (healthy-AND-(`sqlite_only`
      OR `degraded`)) and uses label `ci/inngest-degraded-durability` with severity `priority/p1-high`
      for `degraded` and `priority/p2-medium` for `sqlite_only`; the auto-close step is gated on
      healthy-AND-`durable`. Verify by reading the new step `if:` conditions and the
      `gh issue create --label` / `gh issue close` calls. **`degraded` MUST file an issue** (review
      P0-1) — it is the #5542 incident state, canonically more severe than `sqlite_only`.
- [x] AC8: A **missing** `.durability_state` (older host) is coerced to `absent`, files NO issue,
      emits a `::notice::`, and does NOT restart. A present literal `"unknown"` (redeployed host,
      unreadable unit) emits a `::warning::` (visible read-failure), files no issue. Verify: probe
      jq uses `// "absent"`; advisory step matches the non-durable union only (`sqlite_only`/
      `degraded`), never `absent`/`unknown`.
- [x] AC9: `hooks.json.tmpl` is **unchanged** (the hook already returns command output). Verify:
      `git diff --name-only origin/main | grep -c hooks.json.tmpl` returns `0`.
- [x] AC10: No SSH anywhere in the diff. Verify: `git diff origin/main | grep -E '^\+' | grep -c 'ssh '` returns `0`.

### Post-merge (operator)

- [ ] AC11: After the next merge to `main` touching `apps/web-platform/**`, the
      `web-platform-release.yml` pipeline restarts the container and re-stages the on-host
      `inngest-inventory.sh` via the infra-config push (no separate operator step). The first
      scheduled `scheduled-inngest-health` run after deploy will read the new field.
      **Automation:** handled by the existing release pipeline + the 15-min cron — no operator
      action. Verify (no-SSH): trigger `gh workflow run scheduled-inngest-health.yml --ref main`
      and confirm the run logs `Inngest healthy … functions=N` with no advisory issue filed on a
      durable host (and that `durability_state` is read without error).

## Observability

```yaml
liveness_signal:
  what: "scheduled-inngest-health Sentry cron heartbeat (existing, unchanged) — proves the watchdog itself ran"
  cadence: "every 15 min (cron '*/15 * * * *')"
  alert_target: "Sentry cron monitor slug 'scheduled-inngest-health' (missing check-in alerts)"
  configured_in: ".github/workflows/scheduled-inngest-health.yml:176-185 (sentry-heartbeat action)"
error_reporting:
  destination: "GitHub advisory issue 'ci/inngest-degraded-durability' (priority/p2-medium) filed/commented by the workflow; plus on-host journald 'logger -t inngest-inventory … durability=<enum>' → Vector tag allowlist (vector.toml:132) → Better Stack Logs"
  fail_loud: "yes — a persistent SQLite-only state files a tracking issue every 15 min via comment until durable; the inventory hook itself still fails LOUD (exit 1, webhook non-200) on an unreachable /v0/gql, so 'unknown' from a down server surfaces via the existing inngest_down path, not silently"
failure_modes:
  - mode: "host runs SQLite-only fail-safe ExecStart between deploys"
    detection: "inventory durability_state == 'sqlite_only' read by the 15-min probe"
    alert_route: "GitHub issue ci/inngest-degraded-durability (priority/p2-medium) + journald→Better Stack durability=sqlite_only"
  - mode: "durable backend configured but invariant broken (--redis-uri absent or inngest-redis inactive) between deploys — the #5542 incident state"
    detection: "durability_state == 'degraded' read by the 15-min probe (NOT caught by inngest_down: a redis-dead-but-still-serving host returns 200 + functions array)"
    alert_route: "GitHub issue ci/inngest-degraded-durability (priority/p1-high — canonically MORE severe than sqlite_only) + journald→Better Stack durability=degraded. NOT silenced (review P0-1 fix)."
  - mode: "redeployed host whose live parser cannot read the unit (durability_state literal 'unknown')"
    detection: "durability_state == 'unknown' (distinct from 'absent')"
    alert_route: "::warning:: in the Actions run log + journald→Better Stack durability=unknown (visible read-failure; not an issue since it is a read failure, not a confirmed degradation)"
  - mode: "inventory hook reports durability_state false-positive (mis-read healthy host)"
    detection: "the 5 unit-test verdicts pin the parse against the canonical ci-deploy.sh rule; the cross-file drift tripwire forces a re-look when any of the 3 parsers' tokens change"
    alert_route: "CI test failure pre-merge"
  - mode: "older host script lacks the field"
    detection: "jq '// \"absent\"' tolerance; no spurious issue"
    alert_route: "::notice:: in the Actions run log (blind window made visible) — resolves on next deploy that re-stages the script"
logs:
  where: "GitHub Actions run logs (scheduled-inngest-health); on-host journald (journalctl -t inngest-inventory) → Better Stack Logs"
  retention: "Better Stack Logs default retention; GitHub Actions logs 90 days"
discoverability_test:
  command: "gh workflow run scheduled-inngest-health.yml --ref main && gh run list --workflow scheduled-inngest-health.yml --limit 1   # then: gh issue list --label ci/inngest-degraded-durability --state open"
  expected_output: "On a durable host: run succeeds, no open ci/inngest-degraded-durability issue. On a SQLite-only host: an open advisory issue exists. NO ssh used."
```

## Architecture Decision (ADR/C4)

This plan makes **no new architectural decision**. It implements the no-SSH continuous-durability
surface that the #5553 scope-out and the **#5450 durability epic** already framed, and operates
within **ADR-030 (Inngest as durable trigger layer)**. No ADR is created or amended.

**C4 completeness check (all three `.c4` files read):** the change adds an *output field* to an
already-modeled webhook hook and an *advisory branch* to an already-modeled scheduled watchdog.
No new external human actor (HMAC/CF-Access-gated machine-to-machine probe only), no new external
system/vendor, no new data store, no changed actor↔surface access relationship. **No C4 impact** —
the inngest-inventory hook and the scheduled-inngest-health watchdog are existing elements; the
durability field and advisory issue are internal refinements of edges already rendered.

**Shared-lib deferral note:** with this change, three scripts parse the ExecStart `--postgres-uri`
durability rule (`ci-deploy.sh`, `inngest-wiped-volume-verify.sh`, `inngest-inventory.sh`). The
repo has **no `source`-lib precedent in `apps/web-platform/infra/`**, so extracting a shared
`inngest-durability-lib.sh` now would itself be a novel pattern. We instead pin the three with a
cross-file drift-guard test (Phase 3) — consistent with existing infra drift guards. If a 4th
consumer appears, that is the gate to extract the lib (track via the existing #5450 epic).

## Domain Review

**Domains relevant:** none (infrastructure/observability tooling change).

This is a no-SSH infra/CI change adding an observability field + advisory monitor. No user-facing
UI surface (Product NONE — no path under `components/**`, `app/**/page.tsx`, or the UI-surface
glob). No legal/financial/marketing/sales/support implications. The brand-survival threshold
(`single-user incident`) is inherited from the #5450 durability framing and is handled by the
User-Brand Impact section + plan-time CPO sign-off + review-time `user-impact-reviewer`, not by a
fresh domain sweep.

## Hypotheses

Not an incident/connectivity diagnosis — no SSH/timeout/handshake hypothesis tree needed. The
single design hypothesis (validated in research): "the inventory hook runs on-host with
`systemctl` access, so durability can be read without SSH." Confirmed: the hook executes via
adnanh/webhook on the host (`hooks.json.tmpl:100-102`), and `inngest-wiped-volume-verify.sh:97`
already reads `systemctl show … ExecStart` the same way.

## Open Code-Review Overlap

Only #5553 itself (the issue this plan closes) references the three target files in open
`code-review` issues. No other open scope-out touches `inngest-inventory.sh`,
`scheduled-inngest-health.yml`, or `inngest-inventory.test.sh`. Disposition: **Fold in** —
`Closes #5553`. No additional fold-in/acknowledge/defer.

## Files to Edit

- `apps/web-platform/infra/inngest-inventory.sh` — add `derive_durability_state()`, the 4th JSON
  field, the journald `durability=` summary, header doc-comment update.
- `apps/web-platform/infra/inngest-inventory.test.sh` — `INVENTORY_EXECSTART` /
  `INVENTORY_REDIS_ACTIVE` seam, five state cases, secret-leak guard, purity regression,
  cross-file drift guard.
- `.github/workflows/scheduled-inngest-health.yml` — expose `durability_state`; add the advisory
  file/comment step (`ci/inngest-degraded-durability`, `priority/p2-medium`) + the auto-close step.

## Files to Create

None. (The advisory GitHub issue is created at runtime by the workflow, not committed.)

## Precedent-Diff (Phase 4.4)

**Scheduled-work pattern (ADR-033 "prefer Inngest" — correctly overridden):**

| Aspect | Canonical (ADR-033) | This plan |
| --- | --- | --- |
| New scheduled work → Inngest cron function | `apps/web-platform/server/inngest/functions/cron-*.ts` | **N/A** — we extend an EXISTING GH-Actions workflow, not create a new cron. |
| GH-Actions cron acceptable only if git/repo-scoped, no app context | The watchdog already carries `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->` (`scheduled-inngest-health.yml:1-4`): an Inngest cron cannot detect Inngest being down. | Inherited — the durability detector rides the same external-probe rationale (a SQLite-only-but-alive server is exactly the kind of degraded state an internal Inngest cron would mis-report). |

No new cron is created; the override is pre-existing and load-bearing. The `new-scheduled-cron-prefer-inngest` PreToolUse hook will not fire (no new `scheduled-*.yml`).

**ExecStart-durability-parse pattern (3 consumers — drift-guard, not shared lib):**

| Consumer | Form | Citation |
| --- | --- | --- |
| `ci-deploy.sh` (deploy-time verdict, source of truth) | `systemctl show -p ExecStart` → substring `--postgres-uri`/`--redis-uri` + `systemctl is-active inngest-redis.service` | `ci-deploy.sh:277-287` |
| `inngest-wiped-volume-verify.sh` (wipe sanity) | `INNGEST_VERIFY_EXECSTART:-$(systemctl show … ExecStart)` → `*"--postgres-uri"*` | `inngest-wiped-volume-verify.sh:97-98` |
| `inngest-inventory.sh` (THIS plan, no-SSH continuous) | identical substring rule, seam `INVENTORY_EXECSTART`/`INVENTORY_REDIS_ACTIVE` | new |

No `source`-lib precedent exists in `apps/web-platform/infra/`; a sourced lib would itself be a novel pattern. Pin the three with the Phase 3 cross-file drift-guard test (style precedent: `ci-deploy-wrapper.test.sh:225`, `bwrap-userns-sysctl.test.sh:36`).

## Risks & Mitigations

- **False-positive `sqlite_only`** from a parser drift vs. `ci-deploy.sh` → mitigated by Phase 3
  cross-file drift guard + the five unit verdicts pinned to the canonical rule.
- **Issue flapping** if a host oscillates durable↔non-durable → mitigated by the idempotent
  open-issue pattern (file once, comment on repeat **including `sqlite_only↔degraded` transition
  comments**, auto-close on `durable`) — identical in shape to the existing `inngest_down` path.
  Only `absent` (older host) and `unknown` (read failure) neither file nor close; `degraded` and
  `sqlite_only` both file (review P0-1).
- **`gh` log-injection** via the probe body → the body never reaches the advisory step's echoes
  unsanitized; `durability_state` is a constrained enum and still passes through
  `strip_log_injection` before `$GITHUB_OUTPUT` (existing pattern, lines 109-111).
- **Older on-host script** without the field after a partial rollout → `jq '// "absent"'`
  tolerance (workflow-side coercion of a missing field); no spurious issue; self-heals on the
  next infra-config push. (A redeployed host whose live parser fails to read the unit emits the
  distinct literal `unknown` → `::warning::`, also no issue.)

## Implementation Reconciliations (/work)

Three plan-prescribed verify commands were corrected against the actual codebase
(plan is authoritative for intent, not for verify-command exactness):

1. **Drift guard scoped per-file (AC5 / Phase 3.1).** The plan asked the guard to
   assert all three parsers reference all four tokens, but `inngest-wiped-volume-verify.sh`
   only references `--postgres-uri` + `inngest-server.service` — its gate deliberately
   checks postgres-presence only and never parses redis. Requiring `--redis-uri` /
   `inngest-redis.service` there would false-fail. The guard now asserts the FULL
   four-token rule on the two parsers that implement it (`ci-deploy.sh` source-of-truth
   + `inngest-inventory.sh` new mirror) and the genuinely-shared subset on
   `inngest-wiped-volume-verify.sh`. Tripwire intent preserved; no false-fail.

2. **AC10 (no SSH) — verify command has two false-positive classes.** `git diff
   origin/main | grep -c 'ssh '` returns 5, all non-code: (a) self-referential prose in
   this plan + tasks.md (the AC text literally contains "ssh"), and (b) a branch-divergence
   artifact — origin/main edited `knowledge-base/.../inngest-server.md` (the runbook this
   plan CITES but does not edit) after the branch base. Restricted to the three changed
   code/workflow files, `ssh ` count is **0**. AC10 substance (no SSH in the implementation)
   holds.

3. **AC6 (actionlint exits 0).** actionlint reports only 7× `SC2016:info` (single-quoted
   backticked-markdown in `printf`), identical to the pre-existing `inngest-down` issue step
   and present on origin/main; actionlint's harness ignores the top-of-script
   `# shellcheck disable=SC2016` directive, so this is unsuppressible without per-line noise.
   actionlint is **not** a CI gate (not referenced in any workflow). Zero errors/warnings;
   `durability_state=` is written to `$GITHUB_OUTPUT`. AC6 substance met.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this plan fills it (threshold `single-user incident`).
- The new workflow steps MUST be syntax-checked with `actionlint` + `bash -c '<extracted snippet>'`,
  **never** `bash -n .github/workflows/*.yml` (parses YAML header as bash).
- Keep the durability verdict **byte-identical in intent** to `ci-deploy.sh:277-287`; the
  drift-guard test is the enforcement, but author the function by reading that block, not memory.
- Emit **only the enum** — never the ExecStart string — to any stream (#5503 purity; AC3 is the gate).
