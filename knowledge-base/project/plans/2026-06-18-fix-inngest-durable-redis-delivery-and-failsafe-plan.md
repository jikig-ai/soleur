---
title: "fix(inngest): durable image deploy delivers Redis assets + SQLite fail-safe when Redis unprovisioned"
type: fix
date: 2026-06-18
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(inngest): durable image deploy leaves host without inngest-redis → crash-loop (no fail-safe to SQLite)

🐛 **Bug** · closes nothing automatically (see PR-body note) · Ref #5547 · Ref #5542 · Ref #5450

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO new infrastructure. All
     systemd-unit / /etc/systemd/system / /usr/local/bin references in prose are
     DESCRIPTIVE of resources that already exist on the host (shipped by #5459
     via the existing inngest-bootstrap.sh + inngest-redis-bootstrap.sh delivery
     path). The fix edits those existing bootstrap scripts + ci-deploy.sh + a CI
     workflow only — no new .tf resource, secret, vendor, unit, or manual SSH
     provisioning. The bootstrap reaches the host via the existing `deploy
     inngest …` webhook path (cloud-init for fresh hosts, ci-deploy.sh for
     existing hosts), both already Terraform-provisioned. See ## Infrastructure (IaC). -->

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Phase 0/2/3/4, Acceptance Criteria, Observability, Risks, Sharp Edges
**Review agents used:** architecture-strategist, observability-coverage-reviewer, code-simplicity-reviewer (3 parallel, single-user-incident threshold)

### Key Improvements (from review findings)

1. **Env-file ordering dependency (architecture P0).** The durable-Redis block
   depends on `/etc/default/inngest-server` (DOPPLER_TOKEN) existing — moving it
   before the server heredoc MUST also hoist the env-file materialization, else
   `REDIS_READY=0` permanently on fresh hosts (SQLite becomes the only path,
   masking durability). Phase 0 + Phase 2 now prescribe `env-file → Redis →
   server-unit` order explicitly.
2. **Degraded marker was swallowed on the 0-exit fail-safe path (observability
   P0).** The fail-safe exits 0, but `ci-deploy.sh` reads the bootstrap stderr
   only on a NON-zero exit, and Vector has no `inngest-bootstrap` tag — so the
   marker reached no operator surface and `/hooks/deploy-status` read plain
   `success`. Fixed: the authoritative carrier is the `verify_inngest_health`
   `logger -t ci-deploy` advisory (IS in Vector's allowlist) + a distinct
   `success_degraded_durability` deploy-status reason (AC5b).
3. **Simplified per convergent review:** `REDIS_READY` driven by the bootstrap
   exit code alone (its step 6 self-asserts `is-active`); a single prescribed
   placeholder-substitution technique for the ExecStart fragment (dropped the
   "whichever technique" fork that reintroduced the heredoc-token foot-gun).
4. **Reconciled the existing `inngest.test.sh` ordering guard** (the
   `inngest-redis-bootstrap.sh$` + `tail -1` grep) — added to the explicit
   reconcile list (architecture P0 #2).
5. **Tightened AC1** to per-asset line-start greps (a WHY-comment would have
   inflated the prior `grep -c >= 3`).

### New Considerations Discovered

- The precedent-diff confirmed Gap 1 is a verbatim mirror of the cloud-init
  Redis docker-cp form + the `/tmp/vector.toml` rm+cp sibling — not novel.
- No new cron/scheduled job (ADR-033 path clean); the `scheduled-inngest-health.yml`
  references are to the existing complementary reactive watchdog.

## Overview

The #5450 durable-backend migration (PR #5459, merged 2026-06-17) switched
`inngest-server` to a durable `ExecStart` carrying `--postgres-uri` **and**
`--redis-uri`. The next day a real outage (#5542 window, recovered 2026-06-18)
showed two distinct delivery/robustness gaps that left the host with **no Redis
at all**, so `inngest-server` crash-looped on
`dial tcp 127.0.0.1:6379: connect: connection refused` for ~3.5h.

This is **not** an architecture change — the durable topology (Postgres state
store + AOF Redis queue on the persistent volume) defined by ADR-030 / #5450 is
correct and stays. This plan fixes (1) that the **existing-host deploy path never
delivers the Redis assets to the host**, and (2) that the bootstrap applies the
durable `ExecStart` **even when Redis is unprovisioned**, with no fall-back to a
working SQLite-only server.

**Two gaps, root-caused in code:**

1. **Gap 1 — existing-host deploy never stages the Redis assets.**
   `inngest-bootstrap.sh` only installs Redis when the three staged assets exist
   (the `# Durable Redis (#5450)` block guarded by
   `[[ -f /tmp/inngest-redis.conf && -f /tmp/inngest-redis.service && -x /tmp/inngest-redis-bootstrap.sh ]]`).
   The OCI image **does** bake all three (`build-inngest-bootstrap-image.yml`
   `COPY inngest-redis.*` + the `ENTRYPOINT` `cp /inngest-redis.* /tmp/`), and the
   **cloud-init fresh-host path** docker-cp's all three to the staging dir
   (`cloud-init.yml` `docker cp …:/inngest-redis.conf …` block). But the
   **existing-host deploy path** in `ci-deploy.sh` `case "inngest")` runs the
   bootstrap **directly on the host** (it bypasses the container `ENTRYPOINT`,
   because the Alpine container has no `systemctl`) and only docker-cp's
   `/inngest-bootstrap.sh` + `/vector.toml`. **It never copies the three Redis
   assets.** So on every `deploy inngest …` to a live host the Redis-install
   guard is false → Redis never installed → the durable `ExecStart` crash-loops.
   This is the exact "assets absent even after deploying v1.1.15" symptom.

2. **Gap 2 — no fail-safe; the durable ExecStart is written unconditionally.**
   `inngest-bootstrap.sh` writes the durable `ExecStart` heredoc (the
   `--postgres-uri … --redis-uri …` line) **unconditionally**, then runs
   `inngest-redis-bootstrap.sh` only as a best-effort `if … else log "warn: …"`.
   When Redis bootstrap fails it logs a warning and **still restarts
   `inngest-server` with the durable ExecStart** → crash-loop. Worse,
   `verify_inngest_health` in `ci-deploy.sh` (the `INNGEST_DURABLE` HARD gate)
   returns 1 whenever `--postgres-uri` is present but Redis is not active — which
   (a) is correct as a *consistency* assert but (b) makes a SQLite-only
   **rollback deploy impossible**: the rollback "fails" verify and the gate rolls
   back to the *broken durable image*, with no path back to a serving server.

   The fix inverts the dependency: **Redis must be a hard precondition for
   writing the durable ExecStart.** If `inngest-redis-bootstrap.sh` succeeds AND
   the Redis unit is verifiably active, write the durable ExecStart; otherwise
   write the SQLite-only ExecStart so `inngest-server` stays **available** on the
   non-durable backend, and surface the Redis failure **loudly** (deploy-status
   reason + Better Stack) so the operator knows durability is degraded without SSH.

**Why minimal:** No new infrastructure, no new secret, no new vendor, no schema,
no UI. The Redis unit/conf/bootstrap/TF resources already exist (shipped by
#5459). This is a delivery-path correction in `ci-deploy.sh` + a precondition
inversion in `inngest-bootstrap.sh` + reconciling `verify_inngest_health` to
treat SQLite-only as a healthy (degraded-durability) state rather than a
roll-back trigger.

## Premise Validation

Checked all cited references against live state:

- **#5542** — CLOSED, closed by PR #5544. PR #5544 fixed the *FALLBACK re-arm
  self-enumeration* bug (a distinct cutover failure mode), **not** the
  image-delivery / fail-safe gaps this issue names. The #5542 outage *window* is
  cited as the incident that surfaced these two gaps; the premise (two unaddressed
  gaps remain) holds.
- **#5450** — OPEN (parent durability epic). The durable backend it tracks was
  shipped by **PR #5459** (MERGED 2026-06-17), which introduced the durable
  ExecStart + Redis assets + `verify_inngest_health` durable gate that this bug
  patches. Premise holds: #5547 is the deployment-robustness follow-up to #5459.
- **Brainstorm** `2026-06-17-inngest-scheduled-durability-brainstorm.md` is the
  framing for the #5450/#5459 migration (parent), NOT a brainstorm for #5547. It
  is used as architectural context only; idea-refinement skipped (issue is
  detailed and code-grounded). Threshold inherited: `single-user incident`.
- **Mechanism vs ADR corpus:** the durable topology is recorded in ADR-030
  (amended by #5450) and modelled in C4 (`model.c4` `inngestRedis`). This plan
  does NOT change that decision — it fixes that the deploy *delivers* it and
  *degrades gracefully*. No rejected-alternative collision.
- **Repo-capability claims verified by reading code** (not memory): `ci-deploy.sh`
  `case "inngest")` block (only `/inngest-bootstrap.sh` + `/vector.toml` cp'd);
  `cloud-init.yml` (all three Redis assets cp'd — the asymmetry);
  `build-inngest-bootstrap-image.yml` (image bakes + entrypoint-stages all
  three); `inngest-bootstrap.sh` durable-Redis block (best-effort, unconditional
  ExecStart); `verify_inngest_health` `INNGEST_DURABLE` gate.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Either the OCI image isn't baking/staging the assets, or the entrypoint isn't copying them to `/tmp`." | The image **does** bake (`build-inngest-bootstrap-image.yml` `COPY inngest-redis.*`) and the **entrypoint does** stage to `/tmp`. The real gap is that **`ci-deploy.sh` bypasses the entrypoint** (runs bootstrap on the host) and its `case "inngest")` block omits the Redis `docker cp` lines that the **cloud-init path already has**. | Gap 1 fix lands in `ci-deploy.sh` (mirror the cloud-init `docker cp` lines), NOT in the image build. The image is correct. |
| "Make `inngest-redis-bootstrap.sh` a hard precondition." | `inngest-bootstrap.sh` writes the durable ExecStart **before** running Redis bootstrap, unconditionally. | Gap 2 fix: compute Redis readiness **first**, branch the ExecStart heredoc on it. |
| "verify_inngest_health hard-requires the durable flags, which also makes a SQLite-only rollback deploy impossible." | The `INNGEST_DURABLE` gate returns 1 when `--postgres-uri` present + Redis not active. A SQLite-only ExecStart (no `--postgres-uri`) already **passes** (the gate skips). | The fail-safe writes a **SQLite-only** ExecStart when Redis is down → the gate skips → server stays healthy. The change is purely on the bootstrap (write SQLite ExecStart) side, plus a loud degraded-durability signal. |
| (Discovered) `inngest.test.sh` carries the Redis drift-guards but is **NOT invoked in `infra-validation.yml`** (22 infra `.test.sh` runs, `inngest.test.sh` absent) and is **NOT in `test-all.sh`'s `scripts` glob** (`plugins/**` + `.claude/hooks/**`, not `apps/web-platform/infra/*.test.sh`). | So the existing Redis-asset drift-guards do not run in CI. | New tests MUST land in a CI-wired file — `ci-deploy.test.sh` (wired) for Gap 1, and **wire `inngest.test.sh` into `infra-validation.yml`** for Gap 2 (also activates the existing Redis guards). |

## User-Brand Impact

**If this lands broken, the user experiences:** an armed reminder / scheduled
action that silently never fires — the durable backend the operator believes is
protecting their scheduled work is either absent (Gap 1: Redis never installed,
inngest crash-looping → *every* trigger dead) or the deploy rolls back to a
crash-looping image (Gap 2), reproducing the ~3.5h #5542 outage where the
operator's autonomous workflows were dark with no alert.

**If this leaks, the user's data / workflow is exposed via:** N/A — no
personal-data surface. The vector is **availability + silent durability loss**,
not confidentiality. The Redis password is already Doppler-injected; this plan
does not touch it.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. The brand-survival
> framing is inherited from the #5450 brainstorm (CPO+CLO+CTO reviewed the
> durable migration). This follow-up does not change the threshold or the data
> surface; CPO ack confirms the SQLite-degraded-availability fail-safe is the
> right product trade-off (server stays up on non-durable backend + loud alert >
> server crash-loops). `user-impact-reviewer` runs at review-time.

## Implementation Phases

> Phase order is load-bearing: Gap 2 (bootstrap precondition inversion) changes
> the ExecStart contract that Gap 1 (asset delivery) feeds. Implement Gap 1 first
> (delivery), then Gap 2 (precondition) — because the precondition's happy-path
> (write durable ExecStart) is only reachable once the assets are delivered, and
> TDD for Gap 2 needs the delivered-assets case to exist.

### Phase 0 — Preconditions (read-before-edit, verify shapes)

- Re-read the four edit targets at HEAD: `ci-deploy.sh` `case "inngest")` block,
  `cloud-init.yml` Redis `docker cp` lines (the canonical form to mirror),
  `inngest-bootstrap.sh` durable-Redis block + the server unit heredoc, and
  `verify_inngest_health`.
- Confirm the sudoers pin (`deploy-inngest-bootstrap.sudoers` / `cloud-init.yml`
  `Cmnd_Alias INNGEST_BOOTSTRAP`) pins the bootstrap script path. Gap 1's extra
  `docker cp` lines run as the `deploy` user in `ci-deploy.sh` (NOT under sudo),
  so they need no sudoers change. Verify the Redis `docker cp` target is the
  `/tmp/inngest-redis.*` staging path (world-writable `/tmp`, same as
  `/tmp/vector.toml`), and the bootstrap (run under sudo) reads them from `/tmp`.
- Confirm `inngest-bootstrap.sh` runs under the webhook deploy namespace where
  `/usr/local/bin`, the systemd unit dir, and the persistent volume are writable
  but `/etc` is read-only (the existing `inngest-redis-bootstrap.sh` header
  documents this). The fail-safe SQLite ExecStart writes only the server unit
  file — already in the writable set.
- **LOAD-BEARING ordering dependency (architecture P0).** The durable-Redis
  install block has a hidden dependency on the `/etc/default/inngest-server`
  env-file (DOPPLER_TOKEN), which `inngest-redis.service` reads via
  `EnvironmentFile=` + `doppler run` to inject `$INNGEST_REDIS_PASSWORD`. That
  env-file is materialized in `inngest-bootstrap.sh` (the `DOPPLER_TOKEN`
  preserve-or-write block, currently AFTER the server unit heredoc). The Redis
  bootstrap CANNOT start the unit (→ `REDIS_READY=0`) unless the env-file already
  exists. So Phase 2's "move Redis before the server heredoc" MUST also confirm
  the env-file materialization runs BEFORE the Redis block. **Read the current
  order** at HEAD and note the line ranges of: (a) the env-file materialization
  block, (b) the durable-Redis install block, (c) the server unit `cat >`. The
  Phase 2 target order is **env-file → Redis install + `REDIS_READY` → server unit
  heredoc**. Without hoisting the env-file too, `REDIS_READY` is permanently 0 on
  fresh hosts (Doppler can't auth → Redis never starts) — silently making SQLite
  the ONLY path and masking durability behind the new "graceful" branch.
- **Run `bash apps/web-platform/infra/inngest.test.sh` to confirm it passes at
  HEAD** before adding asserts (it will be newly CI-wired; surface latent drift
  now — R5).

### Phase 1 — Gap 1: deliver the Redis assets on the existing-host deploy path (`ci-deploy.sh`)

- In `ci-deploy.sh` `case "inngest")`, after the existing `/vector.toml`
  `docker cp` line and **before** the `docker rm "$INNGEST_EXTRACT_CONTAINER"`
  line (the container must still exist), add three Redis `docker cp` lines
  mirroring the cloud-init form, each preceded by an `rm -f` of the staging
  target and followed by `chmod +x` on the bootstrap script. Comment the WHY:
  the existing-host deploy bypasses the container ENTRYPOINT that stages these,
  so ci-deploy must stage them itself or the bootstrap's Redis-install guard is
  always false (#5547 Gap 1); `|| true` keeps a pre-#5450 rollback image
  functional (the bootstrap's Gap 2 fail-safe keeps inngest on SQLite when
  they're absent); `rm -f` first prevents a stale prior-deploy asset surviving a
  silent cp failure (same defense as the `/tmp/vector.toml` rm above).
- Verify no early-exit cleanup branch leaves a half-staged asset a later
  same-version no-op deploy would mis-read — the top-of-block `rm -f` neutralizes
  this (the assets live at `/tmp/inngest-redis.*`, not under the extract dir the
  cleanup branches `rm -rf`).

### Phase 2 — Gap 2: invert the precondition + SQLite fail-safe (`inngest-bootstrap.sh`)

- **Re-order to: env-file → Redis install + `REDIS_READY` → server unit heredoc.**
  Per the Phase 0 P0 dependency, the `/etc/default/inngest-server` materialization
  block MUST precede the durable-Redis install block (the Redis unit reads it for
  the Doppler-injected password). Move the durable-Redis install block to run
  AFTER the env-file block but BEFORE the server unit heredoc, capturing a
  `REDIS_READY` flag.
- **Readiness = the Redis bootstrap exit code alone** (code-simplicity finding):
  `if /usr/local/bin/inngest-redis-bootstrap.sh; then REDIS_READY=1; else REDIS_READY=0; …; fi`.
  `inngest-redis-bootstrap.sh` already self-asserts `systemctl is-active --quiet`
  and exits 1 on failure (its step 6), so exit-0 already means active — a second
  `is-active` here would be redundant. Add a one-line comment at the
  `REDIS_READY` site citing `inngest-redis-bootstrap.sh` step 6 as the contract
  (exit-0 ⟹ unit active) rather than duplicating the check. On not-ready, `log`
  the degraded marker and fall through to the SQLite-only ExecStart.
- **Branch the server ExecStart on `REDIS_READY` via a placeholder fragment
  (single technique — do NOT offer alternatives).** Keep the heredoc
  single-quoted (`<<'UNITEOF'`) so the literal `$${INNGEST_*}` Doppler tokens
  survive verbatim, with a literal placeholder sentinel (e.g. `@@BACKEND_FLAGS@@`)
  on the `ExecStart=` line. After writing `$UNIT_FILE`, substitute the sentinel
  with the backend-flags fragment using a substitution that does NOT re-interpret
  `$`/`/`/`&` metacharacters — bash parameter expansion on the file content, or
  `awk` with a literal-string replacement (NOT `sed`, whose replacement string
  would mangle the `redis://:$${…}@` URI's `/` and `$`). The two fragment values:
  - `REDIS_READY=1` → `--postgres-uri "$${INNGEST_POSTGRES_URI}" --redis-uri "redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379" --postgres-max-open-conns 25`
  - `REDIS_READY=0` → empty string (the SQLite-only form).
  Both forms keep `--sqlite-dir /var/lib/inngest`, signing-key strip, event-key,
  `--poll-interval 60 --sdk-url …` in the SHARED (non-placeholder) prefix —
  `--sqlite-dir` is load-bearing in the SQLite form and vestigial-but-harmless in
  the durable form. The `REDIS_READY=0` form is the #5450 pre-migration shape,
  known-good. AC4 locks the literal-token preservation; AC3 additionally asserts
  `--sqlite-dir` is in the shared prefix (present in both branches) and that no
  stray `@@BACKEND_FLAGS@@` sentinel survives substitution.
- **Surface the degraded state loudly (no-SSH).** When `REDIS_READY=0`, emit a
  distinct greppable token `INNGEST_DURABLE_DEGRADED` (one short clause, not a
  paragraph) via the bootstrap's `log()`. **Do NOT rely on the bootstrap-stderr →
  `final_write_state` reason path as the carrier** (observability P0): the
  fail-safe deliberately exits 0 (server stays up), but `ci-deploy.sh` only reads
  `$BOOTSTRAP_STDERR` inside the NON-zero-exit branch — on a 0-exit degraded
  deploy the marker is captured to the stderr file and dropped, and
  `/hooks/deploy-status` reports plain `reason=success` (indistinguishable from a
  healthy durable deploy). The authoritative no-SSH carriers are wired in Phase 3
  (the `verify_inngest_health` ADVISORY via `logger -t ci-deploy`, which IS in
  Vector's tag allowlist → Better Stack) + the distinct `success_degraded_durability`
  deploy-status reason token. The bootstrap `log()` marker remains useful for the
  failure-branch path and as a journald breadcrumb, but is NOT the load-bearing
  operator surface. (Vector does NOT ship the bootstrap's stderr — it has no
  `inngest-bootstrap` syslog tag in Source 4's allowlist; only `ci-deploy`-tagged
  lines reach Better Stack.)

### Phase 3 — Reconcile `verify_inngest_health` for the SQLite fail-safe (`ci-deploy.sh`)

- The `INNGEST_DURABLE` gate already skips when `--postgres-uri` is **absent**
  (the SQLite-only ExecStart) — so a fail-safe deploy already passes /health and
  the durable gate. **No change needed to make the fail-safe pass.**
- **Add a degraded-durability ADVISORY** (NOT a failure): after the
  `INNGEST_DURABLE` block, if `--postgres-uri` is **absent**, `logger -t "$LOG_TAG"`
  (LOG_TAG=`ci-deploy`, which IS in Vector Source 4's allowlist → Better Stack) an
  `INNGEST_DURABLE: advisory — server running SQLite-only (non-durable); durable
  Redis was not ready this deploy (#5547). Server is available; armed reminders
  will NOT persist a host rebuild until a deploy with Redis ready.` This makes the
  degraded state visible in the deploy log + Better Stack without failing the
  deploy or blocking a rollback. **This `logger -t ci-deploy` line is the
  AUTHORITATIVE no-SSH carrier for the degraded state** (the bootstrap-stderr
  marker is NOT — see Phase 2 observability P0).
- **Write a distinct deploy-status reason on the 0-exit degraded path
  (observability P0).** In the `case "inngest")` block, after a 0-exit bootstrap,
  `grep -q INNGEST_DURABLE_DEGRADED "$BOOTSTRAP_STDERR"` (the captured file) OR
  re-derive from the post-bootstrap ExecStart lacking `--postgres-uri`; if
  degraded, `final_write_state 0 "success_degraded_durability"` instead of the
  plain `success`. This makes `/hooks/deploy-status` `.reason` DISTINGUISH a
  degraded deploy from a healthy durable one (today both would read `success`).
  The deploy still succeeds (exit 0) — only the reason token differs.
- Confirm the rollback path: a `--sqlite-dir`-only rollback delivers no Redis
  assets → `REDIS_READY=0` → SQLite ExecStart → /health passes → `INNGEST_DURABLE`
  skip → deploy succeeds (`reason=success_degraded_durability`). The "rollback
  impossible" half dissolves because the fail-safe ExecStart never carries
  `--postgres-uri`.

### Phase 4 — Tests (RED → GREEN) wired into CI

> `inngest.test.sh` is NOT currently invoked in `infra-validation.yml`.
> `ci-deploy.test.sh` IS (the `Run ci-deploy.sh tests` step). See Research
> Reconciliation row 4.

- **Gap 1 (delivery) — `ci-deploy.test.sh`** (CI-wired): drift-guard asserting the
  `case "inngest")` block docker-cp's all three Redis assets (source-grep against
  `ci-deploy.sh`, mirroring the `/tmp/vector.toml` cp-assertion shape). RED first.
- **Gap 2 (precondition + fail-safe) — `inngest.test.sh`** for the bootstrap
  ExecStart-shape drift-guards (the existing Redis guards already live here),
  AND **wire `inngest.test.sh` into `infra-validation.yml`**:
  - bootstrap assigns `REDIS_READY` on a line preceding the server unit `cat >`.
  - bootstrap contains BOTH a durable ExecStart fragment (`--postgres-uri` +
    `--redis-uri`) and a SQLite-only fragment, branch-selected by `REDIS_READY`.
  - the SQLite-only fragment preserves `--sqlite-dir`, signing-key strip,
    event-key, `--poll-interval`, `--sdk-url` and **omits** `--postgres-uri` /
    `--redis-uri`.
  - `--sqlite-dir /var/lib/inngest` is in the SHARED prefix → present in BOTH
    branches; no stray `@@BACKEND_FLAGS@@` sentinel survives substitution (AC3).
  - **reconcile** the existing `inngest.test.sh` asserts "server ExecStart sets
    --postgres-uri" / "--redis-uri (loopback)" to scope to the **durable
    branch** (not the whole file) so they remain true under the new branching.
  - **reconcile the existing ordering guard** (architecture P0 #2): the current
    `inngest.test.sh` assert "bootstrap runs inngest-redis-bootstrap.sh BEFORE the
    inngest-server restart" greps `inngest-redis-bootstrap.sh$` with `tail -1`.
    After the Redis block moves, the `$`-anchored grep may match BOTH the
    `install -m 0755 /tmp/inngest-redis-bootstrap.sh /usr/local/bin/…` line AND
    the `if /usr/local/bin/inngest-redis-bootstrap.sh; then` invocation line.
    Re-verify the anchor selects the INVOCATION line (not the install line) under
    the new order, and tighten it if `tail -1` now captures the wrong one. Add
    this assert to the reconcile list explicitly.
- **Gap 3 verify-health — `ci-deploy.test.sh`**: assert `verify_inngest_health`
  emits the degraded ADVISORY (not `return 1`) when ExecStart lacks
  `--postgres-uri`, AND the `INNGEST_DURABLE` FAIL branch still fires when
  `--postgres-uri` present but `--redis-uri` absent / Redis not active. AND assert
  the `case "inngest")` block writes `final_write_state 0 "success_degraded_durability"`
  on a 0-exit degraded bootstrap (not plain `success`).
- **Run** (bash `.test.sh`, no bats per repo convention):
  `bash apps/web-platform/infra/ci-deploy.test.sh` and
  `bash apps/web-platform/infra/inngest.test.sh`. No TS edits → no `tsc` needed.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — Gap 1: add three Redis `docker cp`
  lines (+ `rm -f` + `chmod +x`) to `case "inngest")`. Gap 3: degraded-durability
  ADVISORY in `verify_inngest_health`.
- `apps/web-platform/infra/inngest-bootstrap.sh` — Gap 2: compute `REDIS_READY`
  before the server unit heredoc; branch the `ExecStart` (durable vs
  SQLite-only); emit the degraded marker.
- `apps/web-platform/infra/ci-deploy.test.sh` — Gap 1 delivery drift-guard +
  verify-health degraded-ADVISORY assert (CI-wired).
- `apps/web-platform/infra/inngest.test.sh` — Gap 2 bootstrap ExecStart-branch +
  ordering drift-guards; reconcile existing `--redis-uri` / `--postgres-uri`
  asserts to the durable branch.
- `.github/workflows/infra-validation.yml` — add a step to run `inngest.test.sh`.

## Files to Create

- None. (All units/conf/scripts/TF resources already exist from #5459.)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (63 open) returned zero
matches for `inngest-bootstrap.sh`, `ci-deploy.sh`, `inngest-redis-bootstrap.sh`,
`inngest.test.sh`, `ci-deploy.test.sh`.

## Acceptance Criteria

### Pre-merge (PR / CI)

- [ ] AC1 — `ci-deploy.sh` `case "inngest")` docker-cp's each of `inngest-redis.conf`,
  `inngest-redis.service`, `inngest-redis-bootstrap.sh` to the `/tmp/inngest-redis.*`
  staging path. Verify per-asset (NOT a `grep -c >= 3`, which a WHY-comment
  mentioning `inngest-redis` would inflate): assert a `docker cp`-line-start match
  for EACH of the three filenames independently —
  `grep -E '^[[:space:]]*docker cp .*inngest-redis\.conf'`,
  `…inngest-redis\.service`, `…inngest-redis-bootstrap\.sh` each return ≥1.
- [ ] AC2 — `inngest-bootstrap.sh` assigns `REDIS_READY` on a line that follows
  the `/etc/default/inngest-server` env-file materialization AND precedes the
  server unit `cat >` line. Verify in `inngest.test.sh` via line-number ordering
  (env-file block < `REDIS_READY=` < server-unit `cat >`).
- [ ] AC3 — `inngest-bootstrap.sh` selects the durable backend-flags fragment when
  `REDIS_READY=1` and an empty fragment (SQLite-only) when `REDIS_READY=0`;
  `--sqlite-dir /var/lib/inngest` is in the SHARED prefix (present in BOTH
  branches); no `@@BACKEND_FLAGS@@` sentinel survives in the written unit. Verify
  in `inngest.test.sh`.
- [ ] AC4 — the durable backend fragment preserves the literal `$${INNGEST_*}`
  Doppler tokens (NOT expanded). Verify by grepping the rendered/heredoc body for
  `\$\${INNGEST_POSTGRES_URI}` and `\$\${INNGEST_REDIS_PASSWORD}`, AND assert no
  expanded/leaked secret value appears.
- [ ] AC5 — `verify_inngest_health` emits a degraded-durability **ADVISORY** (not
  `return 1`) via `logger -t "$LOG_TAG"` when ExecStart lacks `--postgres-uri`;
  the `INNGEST_DURABLE` **FAIL** branch still fires when `--postgres-uri` present
  but `--redis-uri` absent OR Redis not active. Verify in `ci-deploy.test.sh`.
- [ ] AC5b — the `case "inngest")` block writes `final_write_state 0
  "success_degraded_durability"` (NOT plain `success`) when a 0-exit bootstrap
  left inngest on the SQLite-only ExecStart, so `/hooks/deploy-status` `.reason`
  distinguishes degraded from healthy-durable. Verify in `ci-deploy.test.sh`.
- [ ] AC6 — `infra-validation.yml` runs `bash apps/web-platform/infra/inngest.test.sh`.
  Verify: `grep -c 'inngest.test.sh' .github/workflows/infra-validation.yml` ≥ 1.
- [ ] AC7 — `bash apps/web-platform/infra/ci-deploy.test.sh` and
  `bash apps/web-platform/infra/inngest.test.sh` both pass.
- [ ] AC8 — the existing `inngest.test.sh` `--postgres-uri` / `--redis-uri`
  asserts are scoped to the durable branch and still pass under the new shape.

### Post-merge (operator)

- [ ] AC9 — `deploy inngest … vX.Y.Z` to the live host installs the Redis unit
  (active) and `inngest-server` runs the **durable** ExecStart. Automatable: read
  server-side state via the deploy-status webhook
  (`deploy.soleur.ai/hooks/deploy-status`, read-only GET, HMAC+CF Access auth via
  Doppler `prd_terraform`) AND the inngest-inventory hook used by
  `scheduled-inngest-health.yml`. Automation: bake into `/soleur:ship` post-merge
  verification — single authenticated GET, NOT operator-only. No SSH.
- [ ] AC10 — a rollback `deploy inngest … <pre-#5450 tag>` succeeds (server on
  SQLite-only, /health passes, NOT rolled back). Verify via the same
  deploy-status read — `.reason` reads `success_degraded_durability` (AC5b) — and
  confirm the `INNGEST_DURABLE: advisory` line in the deploy log stream (Better
  Stack query, no SSH per `hr-no-dashboard-eyeball-pull-data-yourself`).

> Issue closure: use **`Ref #5547`** in the PR body (NOT `Closes`). The full fix
> is only proven once the post-merge live deploy (AC9) confirms Redis installs on
> the existing host; `gh issue close 5547` runs after that verification (the
> ops-remediation `Closes`-vs-`Ref` Sharp Edge).

## Risks & Mitigations

- **R1 — Heredoc + Doppler-token preservation.** The server unit uses
  `<<'UNITEOF'` precisely so `$${INNGEST_*}` survives literally. Branching it
  risks expanding the tokens. Mitigation: AC4 asserts the literal tokens in the
  written unit; the implementer picks the technique and the test locks it.
  Precedent: `inngest-redis.service` ships as a FILE (not TF inline) for this
  exact reason ("the doppler-wrapped nested single-quotes do not survive
  templating") — mirror that caution.
- **R2 — Idempotency / SKIP_BINARY_INSTALL interaction.** The unit-write +
  service-restart already run OUTSIDE the `SKIP_BINARY_INSTALL` guard
  (reconcile-always). `REDIS_READY` must be computed every bootstrap (also outside
  the guard) so a same-version redeploy that newly delivers Redis flips
  SQLite→durable. The load-bearing reconcile is the existing bootstrap's
  server-unit restart step (outside the guard) — a rewritten-but-not-restarted
  unit leaves the OLD process running with the new unit on disk (the `enable
  --now` no-op class the file already documents). Verify the `REDIS_READY` block +
  branched ExecStart write + that restart step are all outside the short-circuit.
  AC2's ordering grep + a comment lock this.
- **R3 — Flip-flop on transient Redis failure.** A transient
  `inngest-redis-bootstrap.sh` failure writes SQLite ExecStart (server stays up);
  the next deploy with Redis ready flips back to durable. This is the intended
  graceful-degradation behavior; the ADVISORY (AC5) makes each transition visible.
  A flip to SQLite-only does NOT lose in-flight durable state (Postgres persists);
  newly-armed work during the SQLite window lives only on the root disk until the
  next durable deploy (the known #5450 host-rebuild gap, now alerted).
- **R4 — `/tmp` staging collision.** Redis assets stage to world-writable `/tmp`
  (same as `/tmp/vector.toml`). The `rm -f` before each `docker cp` prevents a
  stale prior-deploy asset surviving a silent cp failure (the #5450-era
  `/tmp/vector.toml` trap the comments document). `inngest-redis-bootstrap.sh`
  already has CWE-367 symlink guards on the `/tmp` read.
- **R5 — `inngest.test.sh` newly CI-wired may surface pre-existing failures.**
  Wiring it runs ~33 Redis asserts + others for the first time in CI. Mitigation:
  run it in Phase 0 to confirm it passes at HEAD before adding new asserts; if any
  pre-existing assert fails, triage inline (a latent drift the wiring correctly
  exposes) per `wg-when-an-audit-identifies-pre-existing`.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (inline — code-grounded infra robustness fix; CTO lens applied during research)
**Assessment:** Two delivery/robustness gaps in the #5459 durable-backend
rollout, both root-caused in code (ci-deploy asset-delivery asymmetry vs
cloud-init; unconditional durable ExecStart with no SQLite fall-back). The fix is
a minimal delivery-path correction + precondition inversion, no new infra. The
load-bearing correctness invariant: the durable ExecStart must be written ONLY
when the Redis unit is verifiably active, else SQLite-only keeps the server
available. Mirrors-a-sibling-layer check: the fail-safe does NOT duplicate the
`scheduled-inngest-health.yml` external watchdog — that is *reactive* (detects a
crash-loop within 15min, dispatches a restart); this fail-safe is *preventive*
(the server never enters the crash-loop). Both are load-bearing and complementary.

### Operations

**Status:** reviewed (inline)
**Assessment:** Both delivery paths (existing-host ci-deploy + fresh-host
cloud-init) must reach the host from a deploy without SSH
(`hr-fresh-host-provisioning-reachable-from-terraform-apply` already satisfied by
#5459 for cloud-init; this plan brings the existing-host path to parity). No new
secret/vendor/TF resource. The degraded-durability ADVISORY surfaces via the
deploy-status webhook + Better Stack (no-SSH); the external watchdog remains the
backstop. Post-merge verification is automatable via the deploy-status read — no
operator-only step.

### Product/UX Gate

Skipped — NONE. No UI surface (no `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx` in Files to Edit; all changes are infra shell + workflow YAML).
Mechanical UI-surface override did not fire.

## Architecture Decision (ADR/C4)

**No architectural decision.** This is a delivery-path + graceful-degradation fix
to a topology ALREADY decided (ADR-030, amended by #5450) and ALREADY modelled in
C4. Verified by reading all three model files:

- `model.c4` — `platform.infra.inngest`, `inngestPostgres`, `inngestRedis`
  containers all present (added by #5459). No new element.
- `views.c4` (the inngest include line) — `inngest, inngestPostgres, inngestRedis`
  already in the rendered include set. No new view edge.
- `c4-model.md` — already documents "Redis with AOF persistence that survives a
  host re-provision (ADR-030, #5450)."

**External actors / systems / relationships checked:** no new external human
actor (deploy is operator-via-CI, already modelled); no new external system
(Redis is self-hosted, already a container; no new vendor); no new data store; no
actor↔surface access-relationship change (the deploy delivery path is internal
infra, not a C4 relationship). The fix changes HOW the existing edge is delivered
and degraded, not the edge itself. No C4 edit, no ADR — confirmed against all
three `.c4` files, not a keyword grep.

## Infrastructure (IaC)

**No new infrastructure.** This plan edits bootstrap/deploy shell scripts and a CI
workflow only. No new server, systemd unit, cron, vendor account, DNS record, TLS
cert, secret, or firewall rule. The Redis systemd unit, conf, bootstrap script,
and TF resources (`random_password.inngest_redis_password_prd`, the Doppler
secret) already exist (shipped by #5459). The change is purely to the *delivery*
of those existing assets (ci-deploy docker-cp) and the *robustness* of their
application (bootstrap precondition). Phase 2.8 IaC routing does not apply — no
`terraform apply` is needed; the bootstrap reaches the host via the existing
`deploy inngest …` webhook path (cloud-init fresh-host + ci-deploy existing-host),
both already Terraform-provisioned. All systemd-unit / `/etc` path references in
this plan are descriptive of resources that already exist on the host.

## Observability

```yaml
liveness_signal:
  what: "Inngest Better Stack heartbeat (60s) + external scheduled-inngest-health.yml probe (15min) + /hooks/deploy-status reason"
  cadence: "60s heartbeat / 15min external probe / per-deploy status"
  alert_target: "operator email (Better Stack heartbeat-missing) + P1 GitHub issue (scheduled-inngest-health) + Sentry error heartbeat"
  configured_in: "apps/web-platform/infra/inngest.tf (betteruptime_heartbeat.inngest_prd) + .github/workflows/scheduled-inngest-health.yml + apps/web-platform/infra/ci-deploy.sh (final_write_state reason)"
error_reporting:
  destination: "degraded-durability -> ci-deploy `logger -t ci-deploy` advisory (Vector Source 4 tag allowlist) -> Better Stack Logs + /hooks/deploy-status reason=success_degraded_durability; crash-loop logs -> Vector -> Better Stack Logs; external probe -> Sentry error heartbeat"
  fail_loud: "INNGEST_DURABLE: advisory line (logger -t ci-deploy) -> Better Stack; /hooks/deploy-status .reason=success_degraded_durability; scheduled-inngest-health P1 issue if server actually down. NOTE: the bootstrap-stderr INNGEST_DURABLE_DEGRADED marker is NOT a carrier on the 0-exit fail-safe path (ci-deploy reads stderr only on non-zero exit) — the ci-deploy logger advisory is authoritative."
failure_modes:
  - mode: "Redis assets not delivered (Gap 1) -> bootstrap falls back to SQLite-only ExecStart"
    detection: "ci-deploy `INNGEST_DURABLE: advisory` line (logger -t ci-deploy -> Vector -> Better Stack) + deploy-status .reason=success_degraded_durability; server stays /health=200"
    alert_route: "Better Stack log query + deploy-status reason (no SSH); operator sees degraded durability without an outage"
  - mode: "inngest-redis-bootstrap.sh fails on a durable host (Gap 2) -> SQLite-only fall-back"
    detection: "same authoritative carriers: ci-deploy `INNGEST_DURABLE: advisory` (Better Stack) + deploy-status .reason=success_degraded_durability. (The bootstrap-stderr marker is a journald breadcrumb only — NOT relied upon, since the 0-exit path bypasses ci-deploy's stderr-read.)"
    alert_route: "Better Stack log query + deploy-status webhook read (no SSH)"
  - mode: "Both fail AND SQLite ExecStart also dead (server fully down)"
    detection: "Better Stack heartbeat-missing (60s) + scheduled-inngest-health external probe (15min) auto-dispatches restart + files P1"
    alert_route: "operator email + P1 GitHub issue (existing #5542 watchdog)"
logs:
  where: "journald on host -> Vector (ci-deploy-tagged) -> Better Stack Logs; deploy reason -> /hooks/deploy-status; CI test output -> infra-validation.yml run logs"
  retention: "Better Stack Logs default retention; deploy-status state file rolling"
discoverability_test:
  command: "curl -s https://deploy.soleur.ai/hooks/deploy-status (HMAC+CF Access auth via Doppler prd_terraform) | jq '.reason' ; AND Better Stack log query for 'INNGEST_DURABLE: advisory'"
  expected_output: "On a degraded deploy: .reason == 'success_degraded_durability' AND log stream contains 'INNGEST_DURABLE: advisory'. On a healthy durable deploy: .reason == 'success' and no advisory line."
```

## Hypotheses

(Network/SSH-outage checklist not triggered — the failure is a missing local
Redis service, not a network/firewall/SSH connectivity issue. The crash-loop
error `connect: connection refused` on `127.0.0.1:6379` is loopback-local: Redis
is absent, not unreachable-over-network. No L3→L7 firewall checklist applies.)

## Test Scenarios

1. **Existing-host deploy delivers Redis (Gap 1):** `ci-deploy.test.sh` asserts
   the three `docker cp …inngest-redis…` lines exist in `case "inngest")`.
2. **Bootstrap precondition order (Gap 2):** `inngest.test.sh` asserts
   `REDIS_READY=` precedes the server unit `cat >`.
3. **SQLite fall-back ExecStart shape:** a fragment without
   `--postgres-uri`/`--redis-uri` is reachable under `REDIS_READY=0`.
4. **Durable ExecStart preserved under `REDIS_READY=1`** with literal Doppler
   tokens (AC4).
5. **verify-health degraded ADVISORY (not fail) on SQLite-only ExecStart; FAIL
   still fires on postgres-without-redis** — `ci-deploy.test.sh`.
6. **`inngest.test.sh` runs in CI** — `infra-validation.yml` grep.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan's section is filled; threshold = single-user incident.)
- The server unit heredoc is single-quoted to preserve literal `$${INNGEST_*}`
  Doppler tokens. Any branching of the ExecStart MUST keep those literal — verify
  via AC4, not by eyeballing the heredoc.
- `inngest.test.sh` was not CI-wired before this plan; wiring it surfaces ~33
  pre-existing Redis asserts for the first time in CI. Run it at Phase 0 before
  adding new asserts (R5).
- `REDIS_READY` is driven by the `inngest-redis-bootstrap.sh` exit code alone
  (exit-0 ⟹ the unit is active — its step 6 self-asserts `systemctl is-active`
  and exits 1 otherwise). Do NOT add a redundant `is-active` re-check in the
  bootstrap; instead cite `inngest-redis-bootstrap.sh` step 6 as the contract in a
  one-line comment at the `REDIS_READY` site (code-simplicity finding).
- The degraded-durability fail-safe deliberately exits 0 (server up on SQLite).
  Its operator signal MUST be carried by the `verify_inngest_health` `logger -t
  ci-deploy` advisory + the `success_degraded_durability` deploy-status reason —
  NOT by the bootstrap-stderr marker, which `ci-deploy.sh` reads only on a
  NON-zero exit. A reviewer flagged this as the central dark-mode (observability
  P0); the carrier wiring is in Phase 3.
- Use a placeholder-substitution technique (single-quoted heredoc + sentinel +
  non-`sed` substitution) for the ExecStart backend fragment — do NOT switch to an
  unquoted heredoc with escaped `$$` interpolation (it removes the literal-token
  guarantee `<<'UNITEOF'` provides and is a foot-gun for the next editor).
