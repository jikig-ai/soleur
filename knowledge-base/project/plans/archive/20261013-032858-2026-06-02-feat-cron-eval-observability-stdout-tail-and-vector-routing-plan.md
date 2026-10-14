---
title: "cron-eval observability: stdout-tail capture + thread diagnostics into 5 call sites + pino→Vector routing"
issue: 4773
type: chore
date: 2026-06-02
branch: feat-one-shot-4773-cron-eval-observability
milestone: "Post-MVP / Later"
lane: cross-domain
brand_survival_threshold: none
---

# 📈 cron-eval observability: stdout-tail capture + diagnostic threading + pino→Vector routing (#4773)

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** 4 (AC PR-C, Phase 3, Sharp Edges, Domain Review)
**Gates run:** Phase 4.4 (scheduled-work precedent — no new job), 4.45 (verify-the-negative +
self-audit), 4.6 (User-Brand Impact — PASS, threshold `none` with sensitive-path reason), 4.7
(Observability — PASS, 5 fields non-placeholder, no SSH), 4.8 (PAT-shaped variable — PASS, no hits).

### Key Improvements
1. **PR-C container-start sites: two → THREE (verified).** `docker run -d` for the app container
   exists at `cloud-init.yml:505` (first-boot), `ci-deploy.sh:613-627` (production, canonical
   deploy path), AND `ci-deploy.sh:448-449` (canary smoke-test). The plan v1 underspecified this
   as "grep cloud-init + deploy path"; the deepen pass pinned all three exact sites and added the
   canary to the AC so the AppArmor/bwrap canary check exercises the same log path as production.
2. **ADR attribution corrected.** v1 cited ADR-046 (oneshot scheduler self-arm — unrelated) for
   "crons run on Inngest"; the load-bearing ADR is
   `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn` (the exact
   `spawnClaudeEval` substrate this plan touches).
3. **pii_scrub pipeline reuse verified.** Confirmed `pii_scrub_drop_userdata` takes
   `inputs = ["inngest_journald", "system_journald"]` (`vector.toml:63`); the new app-container
   source must be added to this `inputs` list so it traverses the full 3-stage redaction before
   the Better Stack sink — the only brand-relevant axis (threshold stays `none` because parity holds).

### New Considerations Discovered
- The canary container (`ci-deploy.sh:448`) is a third log-driver site that v1 missed entirely.
- Switching `json-file` → `journald` drops the container's `max-size 10m/max-file 3` rotation;
  retention moves to journald's `SystemMaxUse`. Documented as a runbook trade-off (Distinctness
  safeguards + Sharp Edges).

## Overview

Three deferred observability follow-ups from #4770 (cron-workspace ENOSPC fix, closes the
#4684/#4689 silent-cron-failure incident). All three close the **same root gap**: a substrate
cron's `spawnClaudeEval` failure reason lives in the Next.js app container's pino **stdout**,
which is **not shipped to the log warehouse** — so a non-zero / turn-exhaustion exit is
red-on-the-Sentry-monitor but not self-diagnosing without SSH.

#4770 (merged as #4714) added the cheap half: Sentry `extra.exitCode` + `extra.stderrTail`
on the `scheduled-output-missing` event, plus a pre-clone `cron-workspace-low-disk` WARN.
It deliberately mirrored only the **existing 3-site** `stderrTail` subset rather than widening
scope on a disk fix. The three structural follow-ups below were scoped out and tracked in #4773.

This plan delivers all three as one PR (they share the same observability theme, the same files,
and the same test surface). Two are pure code against an already-provisioned surface (no new
infra); the third is a Vector/Docker config change routed through IaC.

**The three follow-ups:**

1. **PR-A — Capture a bounded redacted stdout tail.** `claude --print` writes its max-turns
   notice to **stdout**, which `spawnClaudeEval` currently sends only to `logger.info`. Add a
   `stdoutTail` field on `SpawnResult`, accumulate it in the readline `on("line")` handler using
   the same `redactToken` + bounded-tail symmetry as `stderrTail`, and fold it into the
   `scheduled-output-missing` Sentry extra so a turn-exhaustion exit is self-diagnosing.

2. **PR-B — Thread `stderrTail` + `exitCode` into the 5 remaining call sites.** Five substrate
   crons call `spawnClaudeEval` (which populates both fields on its `SpawnResult`) but pass
   neither into `resolveOutputAwareOk`, so their `scheduled-output-missing` events lack the
   diagnostic payload. ~2 lines per site.

3. **PR-C — Route the app container's pino stdout into Vector → Better Stack.** The Vector
   source ships only host metrics + the inngest supervisor's journald; the Next.js app
   container's pino stdout (`fn: cron-<name>`) is not in the warehouse. Once shipped, the cron
   failure reason becomes queryable in Better Stack instead of only Sentry extras.

**Why one PR, not three:** PR-A and PR-B both edit `_cron-claude-eval-substrate.ts` /
`_cron-shared.ts` and the same Sentry-extra contract; splitting them would re-touch the same
3 files twice. PR-C edits Vector config + cloud-init + bootstrap and is independent, but ships
in the same PR because it closes the same `## Known coverage gap` the runbook documents under
this issue number — and the runbook edit must reference the now-closed gap atomically.

## Research Reconciliation — Issue Body vs. Codebase

Every artifact the issue body cites by reference was verified against the worktree on 2026-06-02.

| Issue-body claim | Reality (verified) | Plan response |
| --- | --- | --- |
| 5 sites pass neither `stderrTail` nor `exitCode`: `cron-campaign-calendar:215`, `cron-growth-audit:212`, `cron-seo-aeo-audit:241`, `cron-community-monitor:309`, `cron-growth-execution:249` | **Exact match.** All 5 call sites bind `spawnResult` from `spawnClaudeEval` and pass only `{spawnOk, label, runStartedAt, cronName}`. Cited line numbers all correct. | PR-B threads both fields into all 5 (Phase 2). |
| 3 sites already pass both (the #4770 subset) | Confirmed: `cron-roadmap-review:288`, `cron-competitive-analysis:262`, `cron-content-generator:211` already pass `stderrTail: spawnResult.stderrTail` + `exitCode: spawnResult.exitCode`. **Total callers = 8, not "5".** | PR-B touches only the 5 missing sites; the 3 done sites are the verbatim pattern to copy. AC asserts all 8 pass both fields post-change. |
| Insertion point `_cron-claude-eval-substrate.ts` `~:222-230` readline path | Confirmed: stdout readline at `:227-235` calls `logger.info` only; no tail accumulated. `stderrTail` accumulates at `:242` via `(stderrTail + redacted + "\n").slice(-STDERR_CAP_BYTES)`. | PR-A mirrors the `:242` pattern for stdout with a new `STDOUT_TAIL_CAP_BYTES`. |
| `resolveOutputAwareOk` should "fold it into scheduled-output-missing" | Confirmed: `_cron-shared.ts:265-349` already accepts optional `stderrTail`/`exitCode` and folds them into `extra` (`:339-344`, `stderrTail.slice(-4000)`). | PR-A adds an optional `stdoutTail` param to the SAME signature + a sibling `stdoutTail.slice(-N)` in `extra`. |
| Runbook documents the gap at `betterstack-log-query.md` `## Known coverage gap` | Confirmed: the section exists, names `spawnClaudeEval` cron stderr / `fn: cron-<name>`, and says "Tracked in #4773". | PR-C edits this section to record the gap as closed once routing ships. |
| #4684 / #4689 / #4714 | #4684 CLOSED, #4689 CLOSED, #4714 MERGED (the #4770 PR). Premises hold; nothing already resolves #4773. | Proceed. |

## Research Reconciliation — Infra Topology (for PR-C)

The Vector routing item required tracing the runtime topology, because the issue body says
"app container's pino stdout" without specifying how it is logged. Verified 2026-06-02:

| Question | Finding (file:line) | Consequence for PR-C |
| --- | --- | --- |
| What runs the cron pino stdout? | The **Next.js app** as a Docker container `soleur-web-platform` (`cloud-init.yml:505-516`, `docker run -d --name soleur-web-platform`). NOT the `inngest-server.service` systemd unit — that is the inngest CLI supervisor connecting to the app at `127.0.0.1:3000`. | Vector Source 1 (`inngest_journald`, `vector.toml:27-32`) ships ONLY `inngest-server.service` journald — it structurally cannot see the app container's stdout. |
| What log driver does the container use? | Docker daemon default `json-file` with rotation (`cloud-init.yml:362-369`, `max-size 10m / max-file 3`). The `docker run` has **no `--log-driver`** flag, so it inherits `json-file`. Logs land at `/var/lib/docker/containers/<id>/<id>-json.log` (root-owned). | A Vector `file` source would need root + `ProtectSystem=strict` widening; a `docker_logs` source would need Docker-socket access. |
| What user/hardening does Vector run under? | `vector.service` runs `User=deploy Group=deploy`, `SupplementaryGroups=systemd-journal` (NOT `docker`), `ProtectSystem=strict`, `ReadOnlyPaths=/etc/vector` (`inngest-bootstrap.sh:391-419`). | `docker_logs` (socket) and `file` (`/var/lib/docker/...`) both require a **privilege expansion** of the `deploy` user. The lowest-privilege path is to switch the container to `--log-driver journald` and add a journald source filtered on `CONTAINER_NAME=soleur-web-platform` — reusing the `systemd-journal` group Vector already holds. |
| How is `vector.toml` deployed (no SSH)? | `vector.toml` is embedded into `inngest-bootstrap.sh` at image-build time (`vector.tf:19-28`); the bootstrap rebuild + deploy runs on merge via `build-inngest-bootstrap-image.yml` + `web-platform-release.yml`. `vector.service` does `enable + restart` each deploy (`inngest-bootstrap.sh:432-435`). | PR-C config change ships through the existing merge-driven bootstrap path — **no operator SSH**. The container log-driver flag change ships through `cloud-init.yml` + the deploy path (`web-platform-release.yml` restarts the container on merge). |
| Is there a CI gate for Vector config? | Yes: `validate-vector-config.yml` runs `vector validate --no-environment --config-toml`, `vector-pii-scrub.test.sh`, and a Better Stack source/cluster parity grep. | PR-C's new journald source must pass `vector validate` and route through the existing 3-stage `pii_scrub_*` pipeline (`vector.toml:61-182`) so the app container's user-content keys are dropped/hashed at the boundary like every other source. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. This is operator-only
  diagnostic plumbing for background substrate crons (campaign-calendar, growth-audit,
  seo-aeo-audit, community-monitor, growth-execution). A bug would degrade operator
  observability (a Sentry extra missing or a Vector source mis-filtered), not a user surface.
- **If this leaks, the user's data is exposed via:** the captured stdout tail and the
  app-container journald stream both flow to Sentry / Better Stack. `claude --print` stdout can
  echo prompt fragments or repo content. **Mitigation is load-bearing:** PR-A routes the
  stdout tail through the **same `redactToken`** symmetry as stderr (token redaction), and PR-C
  routes the container journald stream through the **existing 3-stage `pii_scrub_*` Vector
  pipeline** (`pii_scrub_drop_userdata` drops Art-9 user-content keys → `pii_scrub_structured`
  HMAC-hashes userId → `pii_scrub_string` regex backstop) before the Better Stack sink. No new
  unredacted egress path is introduced; the new sources inherit the existing boundary contract.
- **Brand-survival threshold:** `none` — operator-only observability; no per-user data surface,
  no auth boundary, no tenancy boundary touched. The redaction/scrub reuse keeps the existing
  egress contract intact. (Sensitive-path note: `_cron-claude-eval-substrate.ts` is under
  `apps/*/server/` and `vector.toml` is infra, but neither change widens the redaction surface
  — both reuse existing redaction/scrub. Threshold remains `none`; reason recorded here per
  preflight Check 6.)

## Acceptance Criteria

### Pre-merge (PR)

**PR-A — stdout tail capture:**
- [x] `SpawnResult` has an optional `stdoutTail?: string` field with a comment mirroring the
      `stderrTail` doc block (`_cron-claude-eval-substrate.ts:16-30`).
- [x] A `STDOUT_TAIL_CAP_BYTES` constant is exported, mirroring `STDERR_CAP_BYTES` (8192).
      Justify the chosen value inline (the max-turns notice is a few hundred bytes; the cap is a
      pathological-OOM ceiling, same rationale as stderr).
- [x] The stdout readline `on("line")` handler accumulates a bounded redacted tail using the
      identical pattern as `:242`: `stdoutTail = (stdoutTail + redacted + "\n").slice(-STDOUT_TAIL_CAP_BYTES)`,
      and still calls `logger.info` for the live stream (do NOT drop the existing log line).
- [x] Every `finish({...})` / resolve path that already sets `stderrTail` also sets `stdoutTail`
      (the `child.on("exit")` path at `:275-284` and the `child.on("error")` path at `:295-302`).
      Grep: `grep -n "stderrTail" _cron-claude-eval-substrate.ts` and confirm a sibling
      `stdoutTail` at each — no resolve path sets one without the other.
- [x] `resolveOutputAwareOk` accepts an optional `stdoutTail?: string` param and folds it into
      the `scheduled-output-missing` `extra` as `stdoutTail: stdoutTail ? stdoutTail.slice(-N) : undefined`
      (choose N consistent with the existing `stderrTail.slice(-4000)`).

**PR-B — thread diagnostics into 5 sites:**
- [x] All 5 cited sites pass `stderrTail: spawnResult.stderrTail` + `exitCode: spawnResult.exitCode`
      (and `stdoutTail: spawnResult.stdoutTail` from PR-A) into `resolveOutputAwareOk`.
- [x] Verification grep returns **8** sites passing all three fields (the 5 fixed + 3 pre-existing):
      `grep -rl "stderrTail: spawnResult.stderrTail" apps/web-platform/server/inngest/functions/cron-*.ts | wc -l` → 8.
- [x] No site passes `stderrTail` without also passing `exitCode` (and vice versa) — the fields
      are a diagnostic triple.

**PR-C — Vector routing:**
- [x] `soleur-web-platform` container runs with `--log-driver journald`, added to **all THREE**
      `docker run` sites (verified 2026-06-02 — none currently set a log driver, all inherit the
      json-file daemon default): `cloud-init.yml:505` (first-boot), `ci-deploy.sh:613-627`
      (production deploy — the canonical path that re-creates the container on every release),
      and `ci-deploy.sh:448-449` (the `soleur-web-platform-canary` smoke-test container, so the
      canary's log routing matches production before promotion). Grep
      `grep -n "docker run -d" apps/web-platform/infra/ci-deploy.sh apps/web-platform/infra/cloud-init.yml`
      to confirm the count is 3 and each gets the flag.
- [x] `vector.toml` gains a journald source filtered to the app container
      (`include_matches.CONTAINER_NAME = ["soleur-web-platform"]` or the journald
      `CONTAINER_TAG`/`SYSLOG_IDENTIFIER` the json-file→journald driver actually emits —
      verify the field name against `journalctl CONTAINER_NAME=soleur-web-platform` output
      shape before freezing; see Sharp Edges).
- [x] The new source's output is wired into `inputs` of `pii_scrub_drop_userdata`
      (`vector.toml:63`) so it traverses the full 3-stage redaction pipeline before the sink —
      NOT a direct path to `tag_journald`/`betterstack`.
- [x] The new source carries a distinct `source_kind` tag (e.g. `app_container`) in
      `tag_journald` so Better Stack can filter cron pino lines from supervisor journald.
- [x] `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml`
      passes locally (the `validate-vector-config.yml` CI gate).
- [x] `vector-pii-scrub.test.sh` is extended to assert the new app-container source routes
      through the pii_scrub pipeline (a cron line with a `userId` is hashed, an Art-9
      user-content key is dropped).
- [x] `betterstack-log-query.md` `## Known coverage gap` is updated to record the gap as
      **closed** (cron pino stdout now queryable), with the new `source_kind` filter documented
      so an operator can query `fn: cron-<name>` in Better Stack.

### Post-merge (operator)
- [x] None required. PR-C config ships through the merge-driven bootstrap rebuild + container
      restart (`build-inngest-bootstrap-image.yml` → `web-platform-release.yml`); `vector.service`
      `enable + restart` on deploy. Automation: feasible — no SSH, no dashboard click.

## Implementation Phases

> **Phase ordering is load-bearing.** PR-A changes the `SpawnResult` contract + the
> `resolveOutputAwareOk` signature (the producer side). PR-B consumes the new fields at the call
> sites. Even though the PR merges atomically, `/work` reads phases sequentially — the contract
> phase MUST precede the consumer phase or the consumer edits reference a field that does not yet
> exist. PR-C is independent and ships last.

### Phase 0 — Preconditions (verify, do not code)
- Confirm the 5 sites + 3 done sites with the grep in AC PR-B.
- `grep -n "stderrTail" apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
  to enumerate every resolve path that sets `stderrTail` (PR-A must add `stdoutTail` to each).
- For PR-C: run `journalctl CONTAINER_NAME=soleur-web-platform -n 1` shape is NOT verifiable
  locally; instead verify the journald field the json-file→journald driver emits by reading
  Docker's journald-driver docs (the driver tags with `CONTAINER_NAME`, `CONTAINER_ID`,
  `CONTAINER_TAG`). Pin the chosen `include_matches` key with a `<!-- verified: ... -->` note.

### Phase 1 — PR-A: stdout tail capture (contract change, producer side)
1. `_cron-claude-eval-substrate.ts`: add `stdoutTail?: string` to `SpawnResult` (with doc block);
   add `export const STDOUT_TAIL_CAP_BYTES = 8192;` (or chosen value).
2. Add a `let stdoutTail = "";` accumulator next to `let stderrTail = "";` (`:216`).
3. In the stdout readline handler (`:229-234`): keep `logger.info`, and append the redacted line
   to `stdoutTail` with the bounded `.slice(-STDOUT_TAIL_CAP_BYTES)` pattern.
4. Add `stdoutTail` to the `child.on("exit")` resolve (`:275-284`) and the `child.on("error")`
   resolve (`:295-302`).
5. `_cron-shared.ts` `resolveOutputAwareOk`: add optional `stdoutTail?: string` param; fold into
   the `scheduled-output-missing` `extra` (`:334-345`) as a sliced sibling of `stderrTail`.

### Phase 2 — PR-B: thread diagnostics into the 5 consumer sites
For each of `cron-growth-audit:212`, `cron-campaign-calendar:215`, `cron-seo-aeo-audit:241`,
`cron-community-monitor:309`, `cron-growth-execution:249`: add the three lines
`stderrTail: spawnResult.stderrTail`, `exitCode: spawnResult.exitCode`,
`stdoutTail: spawnResult.stdoutTail` to the `resolveOutputAwareOk({...})` call. Copy verbatim
from a done site (e.g. `cron-roadmap-review:288-294`).

### Phase 3 — PR-C: Vector routing (infra)
1. Add `--log-driver journald` to all THREE `docker run` sites (verified 2026-06-02):
   `cloud-init.yml:505` (first-boot), `ci-deploy.sh:613-627` (production — the canonical path,
   re-creates the container on each release, so a cloud-init-only change is overwritten on first
   deploy), and `ci-deploy.sh:448-449` (canary smoke-test container — match production so the
   AppArmor/bwrap canary check at `ci-deploy.sh:575` exercises the same log path).
3. `vector.toml`: add `[sources.app_container_journald]` (type `journald`,
   `include_matches.CONTAINER_NAME = ["soleur-web-platform"]`,
   `include_matches.PRIORITY` filter consistent with the inngest source, `journal_directory`,
   `batch_size`). Add it to `inputs` of `pii_scrub_drop_userdata` (`:63`). Tag it with a distinct
   `source_kind` in `tag_journald`.
4. Extend `apps/web-platform/test/infra/vector-pii-scrub.test.sh` for the new source's redaction.
5. Update `betterstack-log-query.md` `## Known coverage gap` to closed.

### Phase 4 — Tests + verification
- Extend `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` (vitest,
  `test/**/*.test.ts`, node env) with a stdout-tail capture test mirroring the existing
  `spawnSimple — stderr capture` describe block: spawn a child that writes a known multi-line
  string + a token to stdout, assert `stdoutTail` contains the tail and the token is redacted,
  and that the tail is bounded to `STDOUT_TAIL_CAP_BYTES`.
- Run `vector validate` + `vector-pii-scrub.test.sh` for PR-C.
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts`
  (vitest, NOT bun test — `apps/web-platform` uses vitest per `package.json`).

## Infrastructure (IaC)

PR-C introduces an infra config change (Vector source + Docker log-driver). PR-A/PR-B touch only
`apps/*/server/` code against the already-provisioned runtime and introduce no infra.

### Terraform changes
- No new Terraform **resources**. `vector.toml` is the Vector agent config, version-pinned by
  `apps/web-platform/infra/vector.tf:13` (`vector_version`) and embedded into
  `inngest-bootstrap.sh` at image-build time. The change is to the embedded `.toml` + the
  `cloud-init.yml` container-start flag, both delivered by the existing bootstrap/deploy path.
- No new provider, no new sensitive variable. The Better Stack sink token
  (`BETTERSTACK_LOGS_TOKEN`) and `SENTRY_USERID_PEPPER` are already injected via Doppler `prd`
  at `vector.service` ExecStart — the new journald source reuses both.

### Apply path
- **cloud-init + idempotent bootstrap (option b).** `vector.toml` ships embedded in
  `inngest-bootstrap.sh`; `build-inngest-bootstrap-image.yml` rebuilds the image and
  `web-platform-release.yml` deploys it on merge, where `vector.service` does `enable + restart`
  (`inngest-bootstrap.sh:432-435` — restart, not `enable --now`, so the new config is picked up).
  The container `--log-driver journald` flag is applied when the deploy path re-creates
  `soleur-web-platform`. **No SSH, no taint, no manual apply.** Blast radius: one `vector.service`
  restart + one container restart on the next deploy (already happens every release).

### Distinctness / drift safeguards
- This is prod-only infra (single Hetzner cx33 VM, `soleur-inngest-prd`); no dev/prd Vector
  split exists. The `validate-vector-config.yml` CI gate + the Better Stack source/cluster
  parity grep guard against config drift and source-ID rotation.
- Switching the container to `--log-driver journald` changes where `docker logs` reads from
  (journald instead of json-file) — the json-file rotation (`max-size 10m/max-file 3`) no longer
  applies; journald's own `SystemMaxUse` governs retention. Note this trade-off in the runbook.

### Vendor-tier reality check
- Better Stack source `2457081` (EU `eu-fsn-3`) is already paid/active and ingesting the existing
  sources. Adding the app-container journald source increases log volume (cron pino INFO/ERROR
  lines) — the `include_matches.PRIORITY` filter should be set to keep volume focused (match the
  inngest source's `0-4` WARN+ filter, or tighter, to avoid shipping high-volume INFO stdout).
  Document the chosen priority filter and its quota rationale inline.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor per substrate cron (scheduled-output-missing heartbeat) + Better Stack queryable cron pino lines (new, via PR-C)"
  cadence: "per-run (each cron fire); Vector ships continuously"
  alert_target: "Sentry issue (operator email) for output-missing; Better Stack for queryable diagnosis"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (monitors); apps/web-platform/infra/vector.toml (warehouse routing); apps/web-platform/server/inngest/functions/_cron-shared.ts:265 (resolveOutputAwareOk)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN; scheduled-output-missing extra now carries exitCode + stderrTail + stdoutTail"
  fail_loud: "scheduled-output-missing Sentry event (red monitor) with extra.exitCode / extra.stderrTail / extra.stdoutTail; cron pino lines queryable in Better Stack by source_kind=app_container + fn:cron-<name>"

failure_modes:
  - mode: "Substrate cron exits non-zero / hits --max-turns and produces no issue"
    detection: "resolveOutputAwareOk -> scheduled-output-missing Sentry event with exitCode + stderrTail + stdoutTail (PR-A surfaces the max-turns notice that previously lived only in app stdout)"
    alert_route: "Sentry issue -> operator email"
  - mode: "One of the 5 previously-unthreaded crons fails undiagnosably"
    detection: "PR-B threads exitCode + stderrTail (+ stdoutTail) into all 8 call sites; the diagnostic payload is now present for every substrate cron"
    alert_route: "Sentry issue -> operator email"
  - mode: "Vector app-container source mis-filtered (wrong CONTAINER_NAME key) -> cron lines absent in Better Stack"
    detection: "vector-pii-scrub.test.sh asserts the new source routes through pii_scrub; validate-vector-config.yml runs vector validate on every vector.toml change; absence of cron lines in Better Stack is operator-queryable"
    alert_route: "CI gate fail (pre-merge); post-merge Better Stack query returns zero cron lines"

logs:
  where: "Sentry extras (exitCode/stderrTail/stdoutTail); Better Stack Logs source 2457081 (cron pino via new app_container journald source, PR-C); container journald (local, post log-driver switch)"
  retention: "Sentry per project plan; Better Stack per source plan; journald per SystemMaxUse (replaces json-file 10m/3-file rotation for the container)"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts && vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml"
  expected_output: "vitest: all pass incl. new stdout-tail capture test; vector validate: 'Validated' with zero errors"
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` checked against the planned files
(`_cron-claude-eval-substrate.ts`, `_cron-shared.ts`, the 5 cron files, `vector.toml`,
`cloud-init.yml`, `betterstack-log-query.md`) — no open scope-out names any of them.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is an operator-only observability/infra change (Sentry extras + Vector log routing + a
Docker log-driver flag). No user-facing surface, no auth/tenancy boundary, no Product/UX
implications, no pricing/retention/legal surface. Mechanical Product/UX escalation does not fire
(no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx` in Files to Create).

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Three-part observability chore. PR-A/PR-B are low-risk symmetry extensions of the
#4770 pattern (already reviewed + merged as #4714). PR-C is the structural fix — the load-bearing
design decision is "switch the container to `--log-driver journald` + filtered journald source"
over "docker_logs/file source", chosen because Vector runs as `User=deploy` without
docker-socket/root access (verified in Research Reconciliation). The new source MUST traverse the
existing `pii_scrub_*` pipeline (redaction parity is the only brand-relevant axis, and the
threshold is `none` precisely because that parity is preserved). Scheduled-job routing precedent:
this is NOT a new scheduled job — the substrate crons already run on Inngest and invoke
claude-code via child-process spawn per `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn`
(the exact `spawnClaudeEval` substrate this plan touches). PR-C only routes their existing log
output; no new-scheduled-job / Inngest-vs-GH-Actions trigger decision applies.

## Risks & Mitigations — Precedent Diff (Phase 4.4)

PR-C's new Vector source is a **pattern-bound behavior with two sibling precedents in the same
file** — `[sources.inngest_journald]` (`vector.toml:27-32`) and `[sources.system_journald]`
(`:37-42`). The new `[sources.app_container_journald]` MUST adopt the canonical shape, not a novel
one:

| Aspect | Precedent (`inngest_journald` / `system_journald`) | New `app_container_journald` |
| --- | --- | --- |
| `type` | `journald` | `journald` (same) |
| unit/container filter | `include_units` / `exclude_units` (systemd unit) | `include_matches.CONTAINER_NAME = ["soleur-web-platform"]` (Docker journald driver tags by container, not systemd unit) |
| priority filter | `include_matches.PRIORITY = ["0".."4"]` (WARN+) | match the inngest source's `0-4` WARN+ filter or tighter (quota control) |
| `journal_directory` | `/var/log/journal` | `/var/log/journal` (same) |
| `batch_size` | `16` | `16` (same) |
| redaction routing | wired into `pii_scrub_drop_userdata.inputs` (`:63`) | MUST be added to the same `inputs` list — do NOT route direct to the sink |
| Better Stack tag | `source_kind = "journald"` (`tag_journald`) | distinct `source_kind = "app_container"` so cron pino lines are filterable |

The only genuinely novel element is the `CONTAINER_NAME` match key (the existing sources filter
by systemd unit). Verify the field name against Docker's journald-driver tag shape before freezing
(see Sharp Edges) — everything else is a verbatim adoption of the precedent. No SQL/lock/atomic-write
pattern is touched; the only pattern axis is the Vector source shape, and it has a direct sibling.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled;
  threshold `none` with a recorded sensitive-path reason.)
- **PR-A resolve-path symmetry:** the `child.on("error")` resolve sets
  `stderrTail: stderrTail || redactedMsg` (`:301`) — a fallback to the error message when the tail
  is empty. Decide whether `stdoutTail` needs the same fallback (likely no: a spawn error has no
  stdout) and document the choice; do NOT blindly mirror the `||` fallback.
- **PR-C journald field name:** Docker's journald log driver tags records with `CONTAINER_NAME`,
  `CONTAINER_ID`, `CONTAINER_TAG`, `IMAGE_NAME` — but the exact field Vector's `include_matches`
  must key on depends on the driver version. `CONTAINER_NAME` is the stable choice but VERIFY the
  emitted field shape before freezing (the json-file→journald switch changes what `journalctl`
  shows). A wrong key silently ships ZERO cron lines while `vector validate` still passes (the
  config is syntactically valid). Pin with a `<!-- verified: -->` note.
- **PR-C three container-start sites (not two):** `docker run -d` appears at `cloud-init.yml:505`
  (first boot), `ci-deploy.sh:613-627` (production deploy — the canonical path, re-creates the
  container every release so a cloud-init-only change is overwritten on first deploy), AND
  `ci-deploy.sh:448-449` (the `soleur-web-platform-canary` smoke-test container). All three must
  get `--log-driver journald` or the production container silently keeps json-file logging. Same
  class as the "extend a hand-maintained allow-list, derive Files-to-Edit from git grep not the
  named filter" rule — `grep -n "docker run -d"` returned exactly 3 sites on 2026-06-02.
- **PR-C log-volume / quota:** the app container's pino stream is higher-volume than the
  supervisor journald (every cron stdout INFO line). Set `include_matches.PRIORITY` to match the
  inngest source's WARN+ filter (`0-4`) or tighter so cron INFO stdout does not blow the Better
  Stack quota. The whole point of the stdout-tail (PR-A) is that the FAILURE reason reaches
  Sentry; Better Stack routing (PR-C) is for queryable diagnosis, not full INFO firehose.
- **Test runner:** `apps/web-platform` uses **vitest**, not bun test. Use
  `./node_modules/.bin/vitest run <path>` with paths under `test/**/*.test.ts` (the node-project
  include glob); a co-located or bun-test invocation silently no-ops.

## References

- Tracker issue: #4773
- Predecessor PR: #4714 (the #4770 fix; closes #4684/#4689)
- Insertion point: `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
- Consumer: `apps/web-platform/server/inngest/functions/_cron-shared.ts:265` (`resolveOutputAwareOk`)
- 5 sites: `cron-growth-audit.ts:212`, `cron-campaign-calendar.ts:215`, `cron-seo-aeo-audit.ts:241`, `cron-community-monitor.ts:309`, `cron-growth-execution.ts:249`
- Vector config: `apps/web-platform/infra/vector.toml`, `apps/web-platform/infra/vector.tf`, `apps/web-platform/infra/inngest-bootstrap.sh`
- Container: `apps/web-platform/infra/cloud-init.yml:505-516` (`soleur-web-platform`)
- Runbook gap: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (`## Known coverage gap`)
- CI gate: `.github/workflows/validate-vector-config.yml`, `apps/web-platform/test/infra/vector-pii-scrub.test.sh`
- Test: `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`
