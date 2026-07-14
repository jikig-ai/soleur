---
title: web-host Vector log-shipping + terminal-block boot-emit trap + pull_failure_event host_id + C4 edge
type: feat
date: 2026-07-14
issue: 6396
relates_to: [6395, "ADR-082", "ADR-100", "ADR-068"]
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# web-host Vector log-shipping + boot observability (follow-up to #6395)

Consolidated observability follow-up deferred from PR #6395 (§1A GHCR credential re-fetch). Four
deliverables on the **web-2 / web-1 fresh-boot blind surface** (no SSH; ADR-082 contract):

1. **Vector on web hosts, ungated by `web_colocate_inngest`** — ship journald + host_metrics to Better Stack from every web host (today only the co-located/inngest path installs Vector; default-`false` flag ⇒ fresh web hosts ship nothing).
2. **Terminal serving-block boot-emit trap (DC-2)** — the cloud-init terminal `docker run` block has no named `soleur-boot-emit` fatal trap; a `doppler secrets download` `exit 1` or a `docker run` `set -e` abort is SSH-only.
3. **`host_id` on `ci-deploy.sh`'s `pull_failure_event`** — a deploy-path `image pull failed` cannot be host-attributed from Sentry alone.
4. **C4 edge `hetzner → Better Stack`** — the web-host log-ship path is unmodeled.

## Overview

All four deliverables extend the **ADR-082 fresh-web-2 boot-observability contract** (Status:
Adopting). Deliverable 1 is the materially larger piece: it **decouples the Vector log-shipper
from inngest co-location** (ADR-100 moved scheduling to a dedicated host; `web_colocate_inngest`
now defaults `false`), so a fresh `soleur-web-platform` / `soleur-web-2` host currently installs
**no** Vector at all and ships **no** logs. The design keeps the log surface strictly **fail-open**
and **sequenced after the `:9000` webhook-bind readiness gate** so that *observing* the boot can
never *break* it — the load-bearing safety contract the issue names.

The change rides the **immutable-redeploy channel**: `hcloud_server.web` carries
`ignore_changes = [user_data]` (`server.tf:204`), so a merged cloud-init/bootstrap change is
**inert on running hosts** and applies only on a fresh create. web-2 (the warm standby) picks it
up via the guarded no-SSH `web-2-recreate` dispatch; **web-1 is NEVER force-`-replace`d** (that
would power-off the sole live origin) — it takes the config on its next normal recreate.

**Sequencing dependency (from the issue):** land AFTER PR #6395's §1A fresh-boot verification
(`web-2-recreate` Phase-3) reports green. PR #6395 is **merged** (2026-07-13); this plan does not
re-verify §1A but its own web-2 fresh-boot verification must not confound §1A attribution.

## Research Reconciliation — Spec (issue) vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| `ci-deploy.sh` (path unqualified) | Lives at `apps/web-platform/infra/ci-deploy.sh`, not `scripts/` | Edit the infra-dir file; `HOST_ID` is already a `readonly` global at `:137-157` |
| "add the Container-view edge **+ `view include` in `views.c4`**" | Both endpoints (`platform.infra.hetzner`, `betterstack`) are **already** in the `containers` view include (`views.c4:32,36`); LikeC4 auto-draws the edge — **no `views.c4` change needed** | Add only the `model.c4` relationship + regenerate `model.likec4.json` |
| "a generic 'web host' element may already carry it" | Web hosts are one generic `hetzner` container (`model.c4:180-183`); no per-host `web-2` element; **no** existing web-host→Better Stack edge (only `inngest → betterstack` at `model.c4:376`) | New edge is `hetzner → betterstack`, mirroring line 376; not a duplicate |
| terminal serving block "~L720-767", ":9000 bind" for serving | Actual block is `cloud-init.yml:730-778`; the app container binds `:80`/`:3000` (`:765-766`); `:9000` is the **webhook** bind, gated at `:609` (`soleur-wait-ready port 9000 webhook_bound`) | The `:9000` gate at `:609` is the correct sequencing anchor for the Vector install; the trap wraps the `:730-778` doppler-download + docker-run region |
| "vector.tf + vector.toml parameterization + new fail-open cloud-init runcmd" | `vector.tf` declares **no resources** (version/sha `locals` only); Vector install logic lives in `inngest-bootstrap.sh:530-667` **inside** `%{ if web_colocate_inngest ~}` (`cloud-init.yml:664-728`); `vector.toml` reaches a web host only via `docker cp` at `:704` (inside the gate) | Add the install to the **ungated** `soleur-host-bootstrap.sh` path; bake `vector.toml` + a web-host `vector.service` into `local.host_script_files` (`server.tf:16-59`, hash-covered) |
| `host_name` "derived per-host, not pinned `soleur-inngest-prd`" | `vector.toml:344,358` hardcode `soleur-inngest-prd`; server names are per-host `soleur-web-platform`/`soleur-web-2` (`server.tf:102`); `vector.toml` is a **shared** file the inngest host also consumes | Replace the literal with a `@@HOST_NAME@@` sentinel. **Preferred:** substitute uniformly at boot on BOTH paths as `$(hostname)` — one file, one rule, drift-proof (advisor) — *iff Phase 0 confirms the inngest host's OS hostname is `soleur-inngest-prd`*. **Fallback** (only if it differs): path-specific substitution value (inngest→`soleur-inngest-prd`, web→`$(hostname)`), still ONE repo file (mirrors `@@DOPPLER_PROJECT@@`, `inngest-bootstrap.sh:648-650`). Do NOT pre-render into two baked OCI copies. |
| (implicit) Better Stack token provisioning | `BETTERSTACK_LOGS_TOKEN` **already exists in `soleur/prd`** — `inngest-betterstack-token.tf:4-6` states "the co-located web host reads it there" | **No new secret provisioning.** Web-host `vector.service` reads it via `doppler run --project soleur --config prd` |
| (not mentioned) architecture record | This decision (web hosts as independent Better Stack log sources) is architectural and ADR-082 already governs fresh-web-2 boot observability | **Amend ADR-082** as a plan deliverable (`wg-architecture-decision-is-a-plan-deliverable`) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a fresh/recreated serving web host that fails
  to bind `:80`/`:3000` and powers off — `app.soleur.ai` returns 5xx / connection-refused on the
  affected origin. The two realistic break vectors: (a) a Vector install that is **not** truly
  fail-open aborts the boot before serving; (b) a mis-scoped terminal-block trap turns a
  transient `doppler`/`docker` blip into a `fatal`/poweroff on a host that would have recovered.
- **If this leaks, the user's data is exposed via:** Vector ships journald — including
  `app_container_journald` (`CONTAINER_NAME=soleur-web-platform`) — to the Better Stack HTTPS
  sink; an over-broad source or a mis-templated `BETTERSTACK_LOGS_TOKEN` could ship more than
  intended to log source 2457081. *(Mitigated: identical data class already ships from the
  inngest host / existing sources; Better Stack is an existing sub-processor.)*
- **Brand-survival threshold:** `single-user incident` — the change touches the boot path of the
  serving hosts. CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs at
  review (per `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

## Observability

```yaml
liveness_signal:
  what: "Better Stack per-host origin uptime probe (web-N.app.soleur.ai/health, CF-proxied; ADR-082 Item 1 / model.c4:380) is the PAGE signal; Vector internal-metrics → vector_console sink → journald is the shipper-liveness signal; soleur-boot-emit cloud_init_complete breadcrumb marks a healthy boot"
  cadence: "uptime probe per-interval; boot breadcrumbs per-boot; Vector internal metrics continuous"
  alert_target: "operator email / Sentry issue (Better Stack uptime absence → betteruptime_policy; boot fatals → shared Sentry boot-stage issue-group)"
  configured_in: "apps/web-platform/infra/cloud-init.yml (call sites); apps/web-platform/infra/soleur-host-bootstrap.sh (baked emitter + Vector installer); apps/web-platform/infra/dns.tf + betteruptime (uptime probe)"
error_reporting:
  destination: "Sentry (EU de.sentry.io) via the baked soleur-boot-emit DSN (SOLEUR_SENTRY_DSN, spliced at bootstrap); ci-deploy.sh pull_failure_event via SENTRY_INGEST_DOMAIN/PROJECT_ID/PUBLIC_KEY"
  fail_loud: "terminal-block failure emits soleur-boot-emit <stage> fatal (tags.stage names the region) instead of an SSH-only cloud-init-output.log line; a non-binding host is caught by the Better Stack uptime absence detector"
failure_modes:
  - mode: "Vector install fails on a web host (binary download/sha/extract, config install, or unit start)"
    detection: "fail-open by design (boot continues, host still serves); absence of the soleur-web-N source in Better Stack (ClickHouse per-source query) + absence of Vector internal-metrics; NOT a boot abort"
    alert_route: "no page (fail-open, non-serving-impacting); surfaced by Better Stack source-volume review"
  - mode: "terminal serving block: doppler secrets download exit 1 OR docker run set -e abort"
    detection: "NEW composite EXIT trap emits soleur-boot-emit <terminal-stage> fatal (in-surface, no SSH); host that never binds :80/:3000 → Better Stack uptime absence"
    alert_route: "Better Stack uptime absence → operator; Sentry boot-stage issue-group carries the fatal cause breadcrumb for no-SSH root-cause attribution"
  - mode: "deploy-path image pull failed (auth_denied / manifest_unknown / network)"
    detection: "ci-deploy.sh pull_failure_event Sentry event, NOW carrying tags.host_id so the failing host is identifiable without cross-referencing the release aggregate JSON"
    alert_route: "Sentry (feature=supply-chain, op=image-pull) → operator"
logs:
  where: "host journald → Vector → Better Stack Logs source 2457081 (HTTPS); cloud-init boot events → Sentry; cloud-init-output.log is the SSH-only surface being de-relied-upon"
  retention: "Better Stack per its plan retention; Sentry per project retention; journald local until rotation"
discoverability_test:
  command: "gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6396 vector+trap verify' — the job's 'Surface fresh-host Sentry breadcrumb trail' step queries Sentry by host_id (no ssh); OR query Better Stack ClickHouse for the soleur-web-2 source volume > 0"
  expected_output: "web-2-recreate reports reason==ok off-host; Sentry breadcrumb trail shows cloud_init_complete for the host_id; Better Stack shows a non-zero soleur-web-2 log source"
```

*Affected-surface note (Phase 2.9.2):* cloud-init/boot is a blind (no-SSH) execution surface. The
`soleur-boot-emit <stage> fatal` breadcrumb IS the in-surface probe; `tags.stage` discriminates
the failing region (terminal-serve vs. earlier stages) in one SSH-free event.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
*(Every host-side command below runs INSIDE Terraform-delivered artifacts — `soleur-host-bootstrap.sh` baked into the OCI image and `cloud-init.yml` rendered into `hcloud_server.web.user_data` — mirroring the existing `inngest-bootstrap.sh`. There are NO operator SSH / dashboard steps; the apply path is the guarded no-SSH `web-2-recreate` dispatch. Phase 2.8 reviewed.)*

### Terraform / cloud-init changes
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — author a baked `/usr/local/bin/soleur-vector-install` helper (heredoc, **0 user_data**) that: `curl --max-time`-downloads + sha-verifies the pinned Vector binary (`vector.tf` `locals`: `vector_version=0.43.1`, per-arch sha), installs `/etc/vector/vector.toml` (renders `@@HOST_NAME@@`→`$(hostname)` — see host_name note below), writes a **web-host** `vector.service` unit (no `After=inngest-server.service`, no `EnvironmentFile=/etc/default/inngest-server`; `ExecStart=doppler run --project soleur --config prd -- /usr/local/bin/vector --config /etc/vector/vector.toml`), then `enable`+`restart --no-block` (NOT `enable --now`). Entire helper body fail-open AND fail-fast (non-blocking).
- `apps/web-platform/infra/cloud-init.yml` — (a) NEW ungated runcmd item, placed **after** the `:609` `soleur-wait-ready port 9000` gate, invoking the installer wall-clock-bounded + fail-open: `- timeout 60 sh -c 'soleur-vector-install' || true`; (b) terminal-block (`:730-778`) composite EXIT trap (Deliverable 2).
- `apps/web-platform/infra/vector.toml` — `@@HOST_NAME@@` sentinel at `:344,:358` (both `tag_journald`/`tag_metrics` transforms); no sink/source change.
- `apps/web-platform/infra/inngest-bootstrap.sh` — render `@@HOST_NAME@@`→`soleur-inngest-prd` in its existing Vector-config install step (mirror the `@@DOPPLER_PROJECT@@` render at `:648-650`) so the shared `vector.toml` keeps the inngest host's host_name byte-for-byte.
- `apps/web-platform/infra/server.tf` — add `vector.toml` and the web-host `vector.service` (or a `vector.service.web` template) to `local.host_script_files` (`:16-59`) so they are baked into the web-host OCI image + covered by `host_scripts_content_hash` (`:77-79`).
- `apps/web-platform/infra/ci-deploy.sh` — `host_id` tag on `pull_failure_event` (Deliverable 3).

### Apply path
- **web-2 (warm standby):** `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate` — the existing **scoped, guarded, no-SSH `-replace` of `hcloud_server.web["web-2"]`** (workflow `web_2_recreate` job) re-runs first-boot cloud-init and verifies off-host via `deploy-status-fanout-verify.sh`. Menu-ack, not an operator prod-write (`hr-menu-option-ack-not-prod-write-auth`).
- **web-1 (live origin):** **config/immutable-redeploy channel only — NEVER `-replace`.** The merged cloud-init change is inert on running web-1 (`ignore_changes=[user_data]`); it takes effect on web-1's next normal recreate. Do NOT add a web-1 `-replace` step.
- **Auto-apply exclusion:** `hcloud_server.web` is **not** in `apply-web-platform-infra.yml`'s `-target` allow-list (managed by initial-apply + dispatch paths), so this PR's `.tf`/cloud-init edits do **not** trigger a host reboot on merge. Expected downtime: **zero** (web-2 recreate is on the warm standby; web-1 untouched).

### Distinctness / drift safeguards
- `dev != prd`: web hosts read `--config prd` exclusively (`hr-dev-prd-distinct`); no dev provisioning.
- No new TF variable and **no new `doppler_secret`** — `BETTERSTACK_LOGS_TOKEN` already resides in `soleur/prd` (`inngest-betterstack-token.tf:4-6`); avoids the `hr-tf-variable-no-operator-mint-default` / no-default-var-on-auto-apply footgun entirely.
- `host_scripts_content_hash` re-covers the two new baked files (byte-identity drift guard).
- **No force-replace of web-1 (advisor-flagged, must verify in Phase 0):** editing `host_script_files` changes the baked-image content + `host_scripts_content_hash`. `hcloud_server.web` carries `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` (`server.tf:204`) and the hash rides `user_data` (`server.tf:77-79`), so a content change does NOT diff a running host into replacement — it lands only on a fresh create. Confirm this holds (`terraform plan` shows 0 change to `hcloud_server.web["web-1"]`) before merge; a false assumption here would turn a log-shipping tweak into a live-origin outage.

### Vendor-tier reality check
- Better Stack ingest: host_metrics through the generic `http` sink bill against the **logs** quota (learning `2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink`). Two new web-host sources roughly double host-metrics volume vs. the single inngest source. Preflight MUST confirm the web-host `vector.toml` `host_metrics` `scrape_interval_secs` and loop-device excludes match the cost-tuned inngest values (do not ship a 30s default to two more hosts).

## Architecture Decision (ADR/C4)

### ADR
- **Amend `ADR-082-fresh-web2-boot-observability.md`** (Status: Adopting) — add a control for
  **Layer-3 web-host log shipping**: Vector installed on the ungated `soleur-host-bootstrap.sh`
  path (decoupled from `web_colocate_inngest` / inngest co-location per ADR-100), fail-open and
  sequenced after the `:9000` bind; the terminal serving-block no-SSH `fatal` cause breadcrumb;
  and `host_id` attribution on `pull_failure_event`. Record in ADR-082's Decision + note the
  rejected alternative (inline emitter bodies in cloud-init — blows the 32 KB user_data cap;
  learning `2026-07-06-cloud-init-user-data-cap-bake-bodies`). Cross-ref ADR-100 (inngest cutover)
  and ADR-068 (multi-host web cluster). This is an in-scope plan task, not a follow-up issue.

### C4 views
- **Container view:** add relationship `hetzner -> betterstack` in `model.c4` (immediately after the
  `inngest -> betterstack` edge at `:376`), technology `"Vector → Better Stack Logs (HTTPS)"`,
  description naming the per-host journald+host_metrics ship. **Completeness check (all three `.c4`
  files read):** external human actors — none new (log ship is host→vendor); external systems —
  `betterstack` already modeled `#external` (`model.c4:262-265`), no new system; container/data-store
  — `hetzner` already modeled (`:180-183`); access relationship — the NEW `hetzner → betterstack`
  edge is the only change. **No `views.c4` include line needed** (both endpoints already in the
  `containers` include, `:32,36`). Then run `bash scripts/regenerate-c4-model.sh`, commit the
  regenerated `model.likec4.json` (the `plugins/soleur/test/c4-model-freshness.test.sh` orphan
  suite gates it), and run `c4-code-syntax.test.ts` + `c4-render.test.ts` (mocked unit tests — the
  real reference check is the likec4 regen: a dangling reference collapses the export to empty).

### Sequencing
- The ADR-082 amendment describes the target state and ships with this PR (Status stays Adopting;
  the web-2 log-ship is fully true only after the `web-2-recreate` dispatch runs post-merge).

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (carried into plan body — infra boot-path change; deepen-plan will run the precedent-diff + observability + ADR/C4 passes)
**Assessment:** Pure infra/observability. Primary risks: fail-open discipline of the Vector install (must never abort boot), correct scoping of the terminal-block trap (must not poweroff on transient blips), `set -e` scope-leak across cloud-init runcmd items (learning `2026-07-06-...set-e-scope`), and byte-identity drift guards on the two new baked files. No product, legal-critical, or financial surface beyond the Better Stack ingest-cost note (Finance-adjacent, non-blocking; handled by the Vendor-tier reality check).

### Product/UX Gate
Not applicable — no UI surface. Files-to-Edit contains no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`; the mechanical UI-surface override does not fire. Tier: NONE.

## GDPR / Compliance

Vector ships `app_container_journald` (which may carry user-derived data) to Better Stack — a
cross-controller data-movement surface. **Assessed, covered:** identical journald data class
already ships from the inngest host and existing sources; Better Stack is an existing
sub-processor with a DPA in place; this plan adds no new data class and no new processor. No
`compliance/critical` finding. (Re-confirm at deepen-plan via `/soleur:gdpr-gate` given the
`single-user incident` threshold.)

## Open Code-Review Overlap

None substantive. Open code-review issues mentioning `server.tf` (#3216 dpf-regex/canary,
#2197 billing SubscriptionStatus) do not touch the `local.host_script_files` list, Vector, or the
boot-observability surface this plan edits. No fold-in / defer required.

## Hypotheses (network-outage gate 1.4)

The feature text contains the substring `SSH` ("SSH-only", "no-SSH"), but the plan proposes **no**
sshd/fail2ban/firewall/connectivity fix — `SSH` appears only as the log-visibility surface being
*reduced*. The L3→L7 firewall-first checklist is **non-applicable**: the apply path
(`web-2-recreate`) and all verification are no-SSH (deploy-status webhook + Sentry breadcrumb
trail). No sshd/firewall hypothesis is raised or needed.

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)
- Confirm `BETTERSTACK_LOGS_TOKEN` is readable in `soleur/prd` (source of truth per `inngest-betterstack-token.tf`): `doppler secrets get BETTERSTACK_LOGS_TOKEN --plain --project soleur --config prd` (read-only). If absent, STOP — the web-host `vector.service` would fail to authenticate.
- **Determine the `@@HOST_NAME@@` substitution rule:** confirm whether the inngest host's OS `hostname` is `soleur-inngest-prd`. If yes → uniform `$(hostname)` on both paths (preferred). If no → path-specific value on the inngest path so its Better Stack `host_name` does NOT change. Read `inngest-bootstrap.sh:595-650` + the server-name derivation (`server.tf:102`).
- `git grep -n 'soleur-inngest-prd' apps/web-platform/infra/` — enumerate every consumer of the pinned host_name before parameterizing (avoid a false zero; the `zot-registry.tf:66-72` keep-in-sync comment references the same Better Stack endpoint).
- **Prove no force-replace of web-1 (advisor-flagged, load-bearing):** run `terraform plan` (read-only, via the canonical `doppler run --name-transformer tf-var` invocation) and confirm the `host_script_files`/image change shows **0 change** to `hcloud_server.web["web-1"]` (expected — `ignore_changes=[user_data, image, …]`, `server.tf:204`). A non-zero diff on web-1 is a STOP.
- Dry-run `bash scripts/regenerate-c4-model.sh` on a scratch copy to confirm it runs in this environment.

### Phase 1 — Vector config parameterization (contract-declaring; before consumers)
- `vector.toml`: `@@HOST_NAME@@` sentinel at `:344,:358`; keep the `host_metrics` `scrape_interval_secs` + device excludes at the cost-tuned inngest values (do not ship a 30s default to two more hosts).
- Substitution per the Phase 0 decision: preferred uniform `$(hostname)` on both paths; fallback path-specific only if the inngest OS hostname ≠ `soleur-inngest-prd`. Whichever, `inngest-bootstrap.sh`'s render must keep the inngest host's Better Stack `host_name` byte-identical to today.
- Author the web-host `vector.service` unit (decoupled from inngest) — inline heredoc in the bootstrap installer, or a baked `vector.service.web` template.
- `server.tf`: add `vector.toml` (+ unit template if a file) to `local.host_script_files`.

### Phase 2 — Ungated Vector install (consumer of Phase 1)
- `soleur-host-bootstrap.sh`: baked `/usr/local/bin/soleur-vector-install` helper (0 user_data), fully fail-open **AND fail-fast** (internal `curl --max-time`, unit start non-blocking; `enable`+`restart --no-block`, NOT `enable --now` — the inngest installer's proven pattern at `inngest-bootstrap.sh:652-662`, since `--now` no-ops on a running unit and keeps a stale config).
- `cloud-init.yml`: new ungated runcmd item **after** the `:609` `:9000` gate, wall-clock-bounded and fail-open: `- timeout 60 sh -c 'soleur-vector-install' || true`. Advisor: `|| true` guards a non-zero *exit* but NOT a *hang*, and all runcmd items share ONE `/bin/sh` — a blocking fetch/start would stall the whole boot chain; `timeout` + non-blocking internals make fail-open also fail-fast (and contain any `set -e` leak).

### Phase 3 — Terminal serving-block boot-emit trap (DC-2)
- `cloud-init.yml:730-778`: after `set -e`/`TMPENV=` (`:740`), arm `trap 'rc=$?; rm -f "$TMPENV"; [ "$rc" = 0 ] || soleur-boot-emit "$stage" fatal' EXIT` covering the `doppler secrets download` (`:742`) + `docker run` (`:755`) region. **Use a mutable `stage=` var** advanced through the block (`stage=doppler_download` before `:742`, `stage=docker_run` before `:755`) so the single trap reports the actual failing region (advisor) — a static stage would mislabel every terminal failure.
- **Disarm `trap - EXIT` immediately after `rm -f "$TMPENV"` (`:768`) — BEFORE the egress-enforce-probe (`:772-774`)**: that probe already emits its own SSH-free Sentry event before `poweroff -f`, so spanning it would double-emit/mis-tag. Two caveats the scope respects: (i) the covered region fails via `exit 1` (doppler) / `set -e` abort (docker) — NOT `poweroff` — so the EXIT trap DOES fire there; (ii) `poweroff -f` tears the process down by signal and bash EXIT traps do NOT reliably run on signal death (advisor), which is exactly why the trap deliberately does not try to cover the `:738`/`:772` poweroff paths (both already self-emit). Mirror the inngest composite trap (`:701`) + plugin-seed (`:655`). Message stays the fixed `"soleur-cloud-init boot stage"` (AC8 query already covers it; only `tags.stage` is new).

### Phase 4 — `host_id` on `pull_failure_event`
- `ci-deploy.sh:536`: add `host_id: $h` to the `tags` object; pass `--arg h "${HOST_ID:-}"` (the `readonly HOST_ID` global at `:137-157` is in scope; empty-safe).

### Phase 5 — C4 edge + ADR-082 amendment
- `model.c4`: `hetzner -> betterstack` edge (after `:376`); regenerate `model.likec4.json`; commit both.
- Amend `ADR-082-fresh-web2-boot-observability.md` (Decision + Alternatives + cross-refs).

### Phase 6 — Tests (fold RED into each phase; consolidated list)
- `soleur-host-bootstrap-observability.test.sh`: NEW AC — terminal-block composite trap present + `trap - EXIT` disarm + the terminal stage name (AC6b's `trap 'rc=$?; cleanup;` regex will NOT match a `rm -f "$TMPENV"` trap, so add a dedicated assertion, don't just bump AC6b); NEW AC — ungated `soleur-vector-install` call site after the `:9000` gate + the baked installer authored once in `$BOOT`.
- `cloud-init-inngest-bootstrap.test.sh`: update AC7 gate expectations (Vector install is no longer gated behind `%{ if web_colocate_inngest ~}` — a fresh ungated host now installs Vector).
- `journald-config.test.sh`, `inngest.test.sh`: reconcile Vector-config expectations with the `@@HOST_NAME@@` sentinel.
- `.github/workflows/validate-vector-config.yml` + VRL fixture: validate the sentinel-rendered per-host config parses.
- `ci-deploy.test.sh`: NET-NEW assertion capturing the `pull_failure_event` Sentry `-d` payload and asserting `tags.host_id` (no existing Sentry-payload assertion to extend; use `SOLEUR_HOST_ID_OVERRIDE` per the `assert_soleur_host_id` pattern at `:1576`).
- `c4-code-syntax.test.ts` + `c4-render.test.ts` (mocked) + `c4-model-freshness.test.sh` (orphan — run via full-suite exit gate).

### Phase 7 — Verification (no-SSH)
- Post-merge: `web-2-recreate` dispatch → `deploy-status-fanout-verify.sh` reports `reason==ok` off-host; the job's Sentry breadcrumb-trail step shows `cloud_init_complete` for the host_id; Better Stack shows a non-zero `soleur-web-2` source. web-1 verification is deferred to its next natural recreate (documented, not forced).

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Inline the Vector-install + emitter bodies directly in `cloud-init.yml` runcmd | Comments + bodies count against the 32,768-byte user_data cap (already ~29.6 KB; ~0.4 KB headroom). Bake into `soleur-host-bootstrap.sh` (0 user_data) per learning `2026-07-06-cloud-init-user-data-cap-bake-bodies`. |
| Provision a new `doppler_secret` / `TF_VAR` for the web-host Better Stack token | Unnecessary — `BETTERSTACK_LOGS_TOKEN` already lives in `soleur/prd`; avoids the no-default-var-on-auto-apply footgun. |
| Add a per-host `web-2` element to the C4 model | The model uses one generic `hetzner` container; a per-host element is out of the model's granularity and would need a `views.c4` include. The `hetzner → betterstack` edge is correct and needs no include change. |
| Force a web-1 `-replace` to apply Vector immediately | Powers off the sole live origin — forbidden. web-1 rides the immutable-redeploy channel. |
| Create a new ADR for web-host log shipping | ADR-082 already governs fresh-web-2 boot observability; amend it (coherent record) rather than fragment. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled with `single-user incident`.
- `cc_runcmd` joins ALL cloud-init runcmd blocks into one `/bin/sh` process; `set -e`/vars/traps leak across items. The new Vector-install runcmd MUST be an explicit fail-open subshell `( … ) || true`, and the terminal-block trap MUST be disarmed (`trap - EXIT`) before the healthy `cloud_init_complete` emit or it mislabels the healthy exit (mirror the inngest `:727` disarm).
- The observability test's AC6b composite-trap counter anchors on the literal `trap 'rc=$?; cleanup;` substring; the terminal trap uses `rm -f "$TMPENV"` not `cleanup;`, so it is NOT auto-covered — add a dedicated AC, do not merely bump the count.
- Changing `vector.toml` is a SHARED-config edit: the inngest host consumes the same file. The `@@HOST_NAME@@` sentinel must resolve on BOTH paths without altering the inngest host's existing Better Stack `host_name` (`soleur-inngest-prd`) — hence the Phase 0 gate deciding uniform `$(hostname)` vs. path-specific. Do NOT fork it into two baked OCI copies (that loses the shared-artifact property and guarantees future drift).
- `|| true` is NOT sufficient for fail-open on a shared-`/bin/sh` runcmd chain: it masks a non-zero *exit* but not a *hang*. The Vector install MUST be `timeout`-bounded and internally non-blocking (`curl --max-time`, unit-start via `--no-block`), or a stalled fetch/unit-start hangs the whole boot on the serving path.
- After editing `.c4`, regenerate + commit `model.likec4.json` in the same change (treat like a lockfile); the freshness test is an orphan suite only hit by the full-suite exit gate.

## References

- Issue: #6396 · Predecessor: PR #6395 (merged 2026-07-13) · ADR-082, ADR-100, ADR-068
- `apps/web-platform/infra/{soleur-host-bootstrap.sh,cloud-init.yml,vector.toml,vector.tf,server.tf,inngest-bootstrap.sh,ci-deploy.sh,inngest-betterstack-token.tf}`
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4,model.likec4.json}`
- Learnings: `2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md`, `2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md`, `2026-06-16-adr-c4-update-is-a-plan-deliverable-not-a-deferred-issue.md`, `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md`, `2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md`, `2026-07-07-immutable-redeploy.md`, `2026-07-09-sentry-fallback-rate-alarm-pre-bootstrap-emitter-and-issue-group-grouping.md`
