---
title: "infra: retire the host-side GHCR read path (#8036 item 1c)"
date: 2026-09-23
slug: fix-retire-host-ghcr-read-path
branch: feat-one-shot-8036-retire-host-ghcr-read-path
issue: 8036
closes: 7295
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Enhancement Summary (deepen-plan, 2026-09-23)

**Halt gates — all pass.** 4.6 User-Brand Impact (threshold `none` + sensitive-path scope-out reason),
4.7 Observability (all 5 fields, no placeholders, `command` is `bash`-verb / no shell-active tokens /
sub-second, `expected_output` is three matchable literals), 4.8 PAT-shaped variables (none), 4.10
Encryption Posture (`at_rest` ×2, `in_transit` ×2, `exception` with `tracking_issue` + `expires_on`),
4.11 Guard Contract (lint green, 3 entries, assembly stated as chokepoints rather than member lists).
4.5 network-outage and 4.9 UI-wireframe do not trigger — the only `components/**/*.tsx` matches in this
file are the Product/UX gate's own prose explaining the override did **not** fire.

**Verification sweeps run in this pass:**

- **Rule-ID resolution** — all 13 cited `hr-`/`wg-`/`cq-` ids resolve ACTIVE or MIGRATED-ACTIVE against
  `AGENTS.md` / `scripts/migrated-rule-ids.txt`. One fabricated id
  (`wg-architecture-decision-is-a-plan-deliverable`) was caught at review and replaced with the
  `plan` Phase 2.10 citation.
- **Citation resolution** — every `knowledge-base/**.md` path resolves; all 17 cited issue/PR numbers
  resolve live via `gh`; all 30 named repo paths exist.
- **Label existence** — `follow-through`, `action-required`, `domain/engineering`, `type/bug`,
  `priority/p2-medium` all confirmed present.
- **Post-edit self-audit** — the sweep that earns this phase. After ~40 revision edits it found the
  plan still naming `$DEPLOY_DOCKER_CONFIG_FILE` in the sweep sketch and in AC-F2 (the rename had been
  **cut**), still prescribing a single `deploy_prelude()` in six places (superseded by the three-way
  split), and still writing `swept=1\|0` (superseded by `yes\|no\|na`). All reconciled; the two
  surviving `deploy_prelude` mentions are the deliberate "do NOT ship this" narrative.
- **Code-fence and section-count integrity** — a scripted splice had silently eaten a closing fence,
  which swallowed the `## Guard Contract` section from the lint's parser and made it report zero
  entries over a file with three. Caught by re-counting; the lint is the oracle, and it was proven by
  driving it RED first.

**Why this pass is short.** The plan had already absorbed a four-seat review panel and a scoped
strong-model consult before deepen-plan ran, and those produced the substantive corrections — the
`ProtectHome=read-only` blocker, the `docker logout` simplification, the guard-row cut, the property
gap (P7). Re-running research fan-out over the same ground would have re-derived findings already
recorded in `## Review & Consult Provenance`. What deepen-plan adds here is the mechanical layer those
seats structurally cannot provide: halt-gate conformance and the self-audit that catches the drift the
revision itself introduced.

## Overview

The host-side deploy script presents a GHCR read credential that has been revoked since
2026-07-29. Every deploy retries it twice and logs `stage=relogin_failed`; the zot mirror
serves the image regardless. Item 1c of #8036 retires that dead read path from the host:
the prelude `docker login ghcr.io`, the Doppler re-fetch/re-login helper, and the GHCR leg
of the pull-recovery helper. CI's GHCR write and read are untouched, so the dual-push and
the ADR-169 restore path survive. The stale `ghcr.io` entry the 1b marker found in the
home docker config is swept by the script itself rather than by a host-side action.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Checked by | Holds? |
|---|---|---|
| #8036 is open and awaiting 1c | `gh issue view 8036` | Yes — `OPEN`, milestone `Phase 4: Validate + Scale` |
| Operator approved 1c on 2026-09-22 | issue comment `2026-09-22T13:03:45Z` | Yes — verbatim: "retire the host-side GHCR read path … Close criterion: `stage=relogin_failed` absent on the first post-apply deploy" |
| 1a + 1b shipped in PR #8456 (merge `69b08a4ee`) | `git log -- apps/web-platform/infra/ci-deploy.sh` | Yes — and a LATER commit `ec68b3ec42` (#8543) also touched the verifier's config handling; the plan is written against `ec68b3ec42`, not `69b08a4ee` |
| #8037 (cosign sibling) | `gh issue view 8037` | **Stale premise corrected** — now `CLOSED/COMPLETED`; its `cosign-verify-live-8037.sh` probe remains the template for 1c's own probe |
| #6565, #6630, #7295 still open | `gh issue view` | Yes — all three `OPEN`; dispositions in `## Adjacent Issues` |
| `GHCR_READ_TOKEN` revoked, minter disabled | operator measurement 2026-09-20 on #8036 | Accepted as given; not re-measured (no live credential read at plan time) |
| ADR-169 governs destroying the sole pull path | read in full | Holds, and **does not gate this change** — see `## Architecture Decision (ADR/C4)` |

No stale premise blocks the plan. The one correction is #8037's state: it is closed, so 1c does not
inherit an open sibling.

### Property List (Phase 0.6b)

- **P1** A deploy no longer presents the revoked credential to `ghcr.io`. Observable: `stage=relogin_failed` and `PRELUDE: docker login ghcr.io FAILED` both absent from journald for the deploy.
- **P2** The deploy still prefetches `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY` into the script's own env *before* the first pull or verify emitter. Observable: pull/verify Sentry events still arrive.
- **P3** No docker config the deploy CLI or the cosign verifier can resolve carries an inline `ghcr.io` auth, and that stays true across repeated deploys.
- **P4** An off-box consumer can tell that a given host ran the post-1c code, rather than only that it emitted nothing.
- **P5** Every off-box consumer of a deleted signal still grades correctly — no silent green, no permanent TRANSIENT.
- **P6** The recorded architecture (C4 + ADR corpus) stops describing a host→GHCR pull edge the code no longer has.
- **P7** The surviving pull path retains the bounded `PULL_TRANSIENT_RETRY_SLEEPS` retry and its empty-value break-glass disable lever. *(Added at plan review. It was argued twice in prose — Alternatives and Risks — and never written down, so nothing authorized the retry re-point except a footnote. Measured: `origin/main`'s zot arm is a bare `docker pull "${zot_ref}:${TAG}"` with zero retries, so the capability is real and lost by a naive deletion.)*

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Already covered by |
|---|---|---|
| A new bespoke "GHCR read path retired" journald marker, so the close criterion has a positive control | P4 | **The 1b marker.** `ghcr_prelude_and_login` already emits `SOLEUR_DEPLOY_GHCR_CONFIG effective=deploy_cfg deploy_ghcr_auth=… home_ghcr_auth=…` once per deploy (`_ghcr_cfg_probe`, closed vocabulary). Once the sweep lands, `deploy_ghcr_auth=none` plus a `swept=` token the pre-1c script cannot emit is itself a positive, version-discriminating control — the pre-1c fleet reads `inline` on both. **Cut: reuse the 1b marker; do not mint a second one.** |
| A new Sentry alert for "zot is now the sole host read path" | P5 | `sentry_alert.zot_mirror_fallback_rate` (four surviving signals), `zot_gate_degraded_event`, and `pull_failure_event` → `image_pull_failed`. The in-code retirement tripwire says explicitly: *"do NOT retire that alarm here — NARROW its `filters_v2` to the signals that still emit."* **Cut: narrow the existing rule; add none.** |
| A standalone bootstrap/operator script to clear the stale config entries on each host | P3 | `terraform_data.deploy_pipeline_fix` (`server.tf`) already hashes `file("${path.module}/ci-deploy.sh")` into `triggers_replace` and is "the sole path for pushing ci-deploy.sh" to running hosts. An idempotent in-script sweep therefore reaches every host on the next apply with no second delivery mechanism. **Cut: no bootstrap script** (`hr-never-label-any-step-as-manual-without`, `hr-exhaust-all-automated-options-before`). |
| A bespoke `jq` + `mktemp` + `chmod --reference` + `mv -f` sweep body | P3 | **`docker logout ghcr.io` run with `DOCKER_CONFIG` pointed at the config dir.** Registry-native, key-scoped to exactly `.auths["ghcr.io"]`, preserves sibling entries by construction, writes with docker's own mode, and additionally clears a `credHelpers["ghcr.io"]` / `credsStore` indirection the `jq` form silently leaves behind — one `_ghcr_cfg_probe` already reports as `*_ghcr_helper=set`. Verified precedent on `origin/main`: five workflows use a `docker logout` teardown guarded with a non-fatal `or-true`, unconditionally (`reusable-release.yml`, `registry-zot-inventory.yml`, `build-inngest-config-bundle.yml`, `build-inngest-bootstrap-image.yml`, `apply-web-platform-infra.yml`). **Cut the body; keep only the `jq -e` presence guard**, which is what buys mtime-idempotence. |
| Renaming `GHCR_DOCKER_CONFIG` → `DEPLOY_DOCKER_CONFIG_FILE` | none | Nothing — it maps to **no property**. 9 sites in the script plus its test plus an ADR-087 clause, and that ADR clause exists *only because of the rename*. Self-inflicted work on a PR whose own risk table calls consumer reconciliation its largest hazard. **Cut.** |
| Three new `T-1c-*` rows for `_try_local_cache_reload` (same-version rescue, no-candidate hard fail, new-version fallthrough) | P7-adjacent | **The existing `#6512 local-cache reload tier` block in `ci-deploy.test.sh`** already covers all three; its new-version row's PASS string is verbatim *"new-version deploy (running image is an older version) → tier does NOT fire, hard image_pull_failed (no stale-bits rollback)"*. `_try_local_cache_reload` is **not edited by this PR** — "becomes more load-bearing" is not "changed". **Cut all three; cite the existing cases.** This also retracts domain-review finding 5, which asserted the coverage was missing without checking. |
| Nine guard mutation rows whose subject is the test harness | none | Nothing — `lint-guard-contract.py` sets `MIN_MUTATION_ROWS = 3` and the class it exists to catch is *"a guard whose WINDOW, CHOKEPOINT or IDENTIFIER SET is narrower than the property it names"*. None of the nine is that class; several restate a `T-1c-*` row verbatim. **Cut to one harness row per guard.** |
| A shared array deriving the sweep list and the probe list from one source | P3 | Nothing — it is a generic solution to a **two-element** problem (the deploy config and the home config; root is probed but deliberately not written). Two adjacent literal calls are self-evidently in sync. **Cut, with Guard 1's row that justified it.** |
| C4 amendment reconciling the cosign-verifier edge's "CODE-DECLARED until…" caveat with #8037's closure | none | Nothing — that edge's mechanism is untouched by this diff. It is #8037 bookkeeping noticed in passing; P6 covers the edge the code **no longer has**, not an edge whose caveat aged. **Cut.** |
| Retiring cloud-init's boot-time `ghcr_login` in the same PR | (would extend P1 to the fresh-boot path) | Not covered — but **out of scope by measurement**, not by omission: cloud-init's `runcmd` runs as root with no `DOCKER_CONFIG`, so its `docker login ghcr.io` writes `/root/.docker/config.json`, which the 1b marker measured as `root_cfg=unreadable` and which `effective=deploy_cfg` proves the deploy CLI does not resolve. It therefore **cannot** undo the deploy-user sweep. Retiring the boot path also removes the fresh-boot pull's only non-zot arm, which is a different blast radius. **Deferred to a follow-up issue (1d), not silently dropped** (`wg-when-deferring-a-capability-create-a`). |

### Value-proposition measurement (Phase 0.6c)

The justification is defect elimination, not cost saving, so the number is a defect rate rather than a
saving. Measured by the operator on 2026-09-20 over the trailing 168 h (Better Stack,
`SYSLOG_IDENTIFIER=ci-deploy`, `--grep relogin_failed`): **89 occurrences**, one per deploy, plus 89
matching `result=cosign_absent`. 1a removed the second 89 (confirmed by the 2026-09-22 post-apply
deploy). 1c targets the first. Command that produces the number post-merge:
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 168h --grep relogin_failed`.

### Scope correction the evidence forces: the sweep covers the DEPLOY config ONLY

The operator's ruling names "the stale `ghcr.io` entry from the home docker config". **That entry
cannot be swept by this script, and the plan must not pretend otherwise.**

`ci-deploy.sh` runs under `webhook.service`, which is `User=deploy` with `ProtectHome=read-only` and a
`ReadWritePaths=` list that does **not** include `/home`. This is not inference — `ci-deploy.sh`'s own
header says it in terms:

> "The old default `$HOME/.docker` (/home/deploy/.docker) sits under webhook.service's
> ProtectHome=read-only mount and is NOT in its ReadWritePaths, so the login AUTHENTICATES but cannot
> PERSIST the cred → EROFS"

and `apps/web-platform/infra/credential-persist-home-guard.test.sh` names it as **recurrence class #1**,
by file, with a dedicated CI gate wired into `.github/workflows/infra-validation.yml`. An earlier draft
of this plan proposed a `$HOME` write from that unit — the precise class that guard exists to stop
recurring. It would have failed safe (the `-w` test returns false on a read-only mount) and therefore
**silently never swept**, while:

- `AC-F2` ("leaves neither") would pass only against a harness with a writable fake `HOME` — the exact
  vacuous-green this plan cites `2026-07-03-pass-is-not-proof` against;
- the close criterion's `home_ghcr_auth=none` leg would read `inline` forever, so the probe would FAIL
  on every sweep and **#8036 would never close**.

**Resolution.** The sweep covers `$GHCR_DOCKER_CONFIG` only (`$DOCKER_CONFIG/config.json`; the rename to a truthful name was cut at plan review, so the misleading symbol stays and only its header comment is corrected) — `/mnt/data/deploy-docker/config.json`,
which is on `/mnt/data`, an existing `ReadWritePath`. That is also the config that matters: the 1b marker
measured `effective=deploy_cfg`, so it is the one the docker CLI presents and the one bind-mounted `:ro`
into the cosign verifier. It carries the revoked PAT inline, and that entry is what turned the *public*
verifier-image pull into a 401 (`cosign_absent`, 89/89).

The home entry is a **pre-#6565 fossil**: written by no live code path since `DOCKER_CONFIG` was
relocated, unresolvable by the deploy CLI, and unreachable by the unit that would clear it. It is
therefore **observed, not swept** — `emit_registry_config_marker` keeps reporting `home_ghcr_auth`, so if
it ever changes, something new is writing there and the marker says so. Clearing the fossil itself is
out of scope for a unit that structurally cannot do it, and rides the 1d follow-up alongside root's
config, which is in the same position for the same reason.

### The largest sharp edge: `ghcr_prelude_and_login` is not only a GHCR login

The function name is misleading and the retirement must not follow it. Besides the GHCR login, the
function is the **sole site that REFRESHES `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID` and
`SENTRY_PUBLIC_KEY` from Doppler**, and it runs *before* `zot_gate_and_login` and before every
pull/verify emitter. *(Precision matters and an earlier draft got it wrong: the three are also read
from the baked `/etc/default/soleur-doppler-token` at script top, before any function runs, so the
prelude is not their only source. #7095's "took the host Sentry-dark" was caused by an unconditional
`printf -v` **blanking** those baked values, not by their absence — which is why the loop's guard is
"assign only on a non-empty result". Deleting the loop loses the refresh, not necessarily every value.
The conclusion — keep the function — stands on the 1b-marker argument alone.)* Its own comment records what deleting that is worth:

> "that blanked all seven `[[ -n $SENTRY_INGEST_DOMAIN && … ]]` guards and took the host Sentry-dark
> — silently destroying, ~1400 lines later, the exact mitigation the baking exists to provide. It is
> why 341 unit failures over 5.7h paged nobody." (#7095)

It is also the emitter of the 1b `SOLEUR_DEPLOY_GHCR_CONFIG` marker. So the function **survives**;
what is deleted is its credential-read + login + refetch body. Splitting it into three named functions (below) is the
honest outcome, and is cheap because it has exactly one call site.

### Structural map of the code under change (`apps/web-platform/infra/ci-deploy.sh`)

Anchors are quoted defining lines, per `cq-cite-content-anchor-not-line-number`.

| Symbol | Anchor | Fate under 1c |
|---|---|---|
| `ghcr_prelude_and_login()` | `ghcr_prelude_and_login() {` | **Survives, gutted + renamed.** Keeps the SENTRY_* prefetch loop, the new sweep, `_ghcr_cfg_probe` ×3 and the marker emit. Loses the baked-cred read, the `_docker_login_capture ghcr.io` call, both `PRELUDE: docker login ghcr.io …` arms and the `PRELUDE: GHCR_READ_{USER,TOKEN} not both present` arm. |
| `refetch_ghcr_and_relogin()` | `refetch_ghcr_and_relogin() {` | **Deleted.** Its only two callers are the two arms deleted here. |
| `_ghcr_pull_or_recover()` | `_ghcr_pull_or_recover() {` | **Survives, auth arm deleted, renamed.** The `if _pull_result_is_auth_denied "$(tail -c 400 "$perr" …` block is the "GHCR leg". What remains is the generic `docker pull` + bounded transient-retry loop (`PULL_TRANSIENT_RETRY_SLEEPS`) + the manifest/unknown arm — all registry-neutral. |
| `pull_image_with_fallback()` | `pull_image_with_fallback() {` | **Both GHCR arms deleted.** The `ZOT_ACTIVE=1` arm loses its "ATOMIC fallback to GHCR" branch; the `ZOT_ACTIVE=0` (zot-dark) tail loses its `_ghcr_pull_or_recover` call. See the open design question below. |
| `_ghcr_cfg_probe()` | `_ghcr_cfg_probe() {` | **Survives**; gains the `swept=yes\|no\|na` token. Its in-code comment must additionally name `root_ghcr_auth=inline` as **expected and out of scope**, citing the 1d issue. After 1c that slot reads `inline` permanently (cloud-init's root login is 1d scope, and Guard 3 harness row 6 makes it a PASS), so a reader seeing `deploy_ghcr_auth=none swept=yes root_ghcr_auth=inline` would otherwise reasonably conclude the change half-landed. The probe's `--explain` output says the same thing. |
| `_try_local_cache_reload()` | `_try_local_cache_reload() {` | **Survives, and becomes materially more load-bearing**: after 1c it is the only tier between a zot miss and `image_pull_failed`. |
| `_docker_login_capture`, `_docker_login_failure_class`, `_docker_login_http_status`, `_login_hatch`, `_login_kw`, `_login_tok` | each `<name>() {` | **Survive — shared with `zot_gate_and_login`.** Do not delete as "orphaned"; only the GHCR *call sites* go. |
| `_pull_result_is_auth_denied`, `_pull_result_is_transient` | each `<name>() {` | **Survive** — also called by `pull_failure_event` for its `pull_result` classification. |
| `pull_auth_recovery_event()` | `pull_auth_recovery_event() {` | **Survives.** It is *not* GHCR-only: `_ghcr_pull_or_recover` also calls it with `transient_recovered` on the generic retry arm. Only the `recovered` call site (inside the deleted auth arm) goes. |
| `registry_pull_event()` | `registry_pull_event() {` | Survives; its `ghcr-fallback` argument site is deleted, so `registry=ghcr-fallback` can never be emitted again. |
| `GHCR_READ_USER` / `GHCR_READ_TOKEN` / `SOLEUR_GHCR_READ_FILE` / `/etc/default/soleur-ghcr-read` | `local ghcr_read_file="${SOLEUR_GHCR_READ_FILE:-/etc/default/soleur-ghcr-read}"` | **Dead in this script.** Still written by cloud-init and still declared in `variables.tf` / `ghcr-read-credential.tf` — see the 1d deferral. |
| `GHCR_DOCKER_CONFIG` | `readonly GHCR_DOCKER_CONFIG="${DOCKER_CONFIG}/config.json"` | **Survives and must not be removed.** `zot_gate_and_login` writes the zot auth into it and `verify_image_signature` mounts it `:ro` for the `.sig` fetch. Its name reads wrong after 1c, but the rename was **cut** at plan review (no property, 19 sites, self-inflicted ADR churn) — fix the header comment, keep the symbol. |
| The retirement tripwire comment | `# RETIREMENT TRIPWIRE (#6285): ADR-096 task 5.3 deletes this branch.` | **Deleted with the branch it guards — and its instructions executed.** Note it is itself stale: it says the soak's FAIL set is "FOUR entries, not two"; it is now **five**. |

### Off-box consumers of the signals this change deletes (P5 inventory)

| Consumer | What it reads | Effect of 1c if untouched |
|---|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` › `resource "sentry_alert" "zot_mirror_fallback_rate"` | five `action_filters` conditions, incl. `{ tagged_event = { key = "registry", match = "eq", value = "ghcr-fallback" } }` | One of five signals goes permanently silent. The rule keeps working on the other four. Its `lifecycle` is `ignore_changes = [environment]` only, so `action_filters` **are** Terraform-managed here and the edit is live (unlike the `sandbox_startup_failure` block above it, which is `ignore_changes = all`). |
| `scripts/followthroughs/zot-soak-6122.sh` › `declare -A FAIL_QUERIES=(` | `[rolling]='feature:supply-chain op:image-pull registry:"ghcr-fallback"'` plus a **hard cardinality floor**: `if (( ${#FAIL_QUERIES[@]} != 5 )); then … exit 2` | **Breaks loudly and permanently.** Dropping `[rolling]` without moving the floor to 4 makes every sweep `TRANSIENT: FAIL_QUERIES has 4 entries, expected 5`. Both must move in the same edit. |
| `scripts/followthroughs/zot-soak-6122.test.sh` | fixtures spelling all five signals, e.g. `HEALTHY="…;ghcr-fallback=0;zot-gate-degraded=0;…"` | Every fixture string must drop the `ghcr-fallback=` term; the floor row must assert **4**. |
| `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` | the alert's committed shape | Will red until it agrees with the narrowed rule. |
| `scripts/sentry-alert-live-fidelity.sh` | pins live workflow values against the committed capture | Needs the capture re-pinned after the narrowing applies. |
| `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` | asserts zero *unrecovered* `op:image-pull pull_result:auth_denied` — i.e. it soaks the very recovery mechanism 1c deletes | Becomes a soak of deleted code. Must be retired with #6400's tracker, not left sweeping. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `hetzner -> ghcr "DEAD EDGE as of 2026-07-30 (#7071) … This edge stays DEAD pending #8036 1c"` | **The model names this change by number.** The edge must be deleted here; leaving it makes the recorded architecture false in the opposite direction. |
| `apps/web-platform/infra/ci-deploy.test.sh` | the #6400 / §1A / #6497 / #6525 GHCR test arms | Enumerated in `## Files to Edit`. |

### Institutional learnings that apply

- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` — the independence criterion, and Named Residual 3 (*"The `ghcr-fallback` emitter and its Sentry rule remain dark … Tracked separately"*), which is #7295. Its Context §2 already records that `registry_pull_event ghcr-fallback` "can never fire".
- `knowledge-base/project/learnings/2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md` — alarm on fallback *usage*, not only on total failure. Directly inverted here: deleting the fallback removes the usage signal, so the surviving zot-health signals must be confirmed live *before* merge, not after.
- `knowledge-base/project/learnings/2026-08-20-making-op-arm-idempotent-opened-the-window-the-refusal-was-holding-shut.md` — a guard you remove may be load-bearing for a reason it never names. Ask what states become reachable that were not. Here: `ZOT_ACTIVE=0` with no pull arm at all.
- `knowledge-base/project/learnings/best-practices/2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md` — a green gate is a hypothesis. Every surviving pull test must be checked for whether it still reaches the zot arm or now passes vacuously.
- `knowledge-base/project/learnings/best-practices/2026-07-17-reuse-live-artifact-fallback-must-gate-on-version-not-presence.md` — `_try_local_cache_reload` becomes the last tier; its version gate (`[[ "$_rt" == *":$TAG" ]]`) is now the only thing between a zot outage and serving stale bits.
- `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` — this suite's mock-trace discipline: assert stdout trace markers, not temp files.
- `knowledge-base/engineering/operations/post-mortems/2026-07-14-web-platform-deploy-ghcr-pull-denial-outage-postmortem.md` — the incident class 1c makes structurally impossible on the host side.
- `knowledge-base/project/learnings/2026-07-05-ghcr-installation-token-minter-dependency-gate-and-adr-ordinal-drift.md` — where GHCR credentials flow into the estate; the reverse-dependency check behind the 1d deferral.
- `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — the 1c probe must field-isolate `SYSLOG_IDENTIFIER == "ci-deploy"`, never substring-match, because the Better Stack source also carries issue/PR bodies quoting this very tracker.

### Conventions in force

- `AGENTS.md` `cq-write-failing-tests-before` — the mutation matrix and the RED tests precede the deletion.
- `AGENTS.md` `cq-ref-removal-sweep-cleanup-closures` — the P5 inventory above is that sweep.
- `AGENTS.md` `cq-cite-content-anchor-not-line-number` — every citation here is a quoted defining line.
- `AGENTS.md` `hr-no-ssh-fallback-in-runbooks` / `hr-no-dashboard-eyeball-pull-data-yourself` — the close criterion is graded by `scripts/betterstack-query.sh`, never by SSH or a dashboard.
- `AGENTS.md` `hr-never-label-any-step-as-manual-without` — the config sweep is in-script and idempotent.
- `constitution.md` › Testing › Always — *"A lint cited as the oracle for a guard is proven by a RED, never a green."*
- `constitution.md` › Testing › Never — *"Never stub a wrapper the code under test DEFINES … stub the PROCESS it execs."* The suite already does this (`docker`/`doppler`/`logger` process mocks).
- `constitution.md` › Architecture › Always — *"New commands must be idempotent."*

### Apply path (how this reaches a live host)

`apps/web-platform/infra/server.tf` › `terraform_data.deploy_pipeline_fix` — *"This resource is the sole
path for pushing ci-deploy.sh"* — carries `file("${path.module}/ci-deploy.sh")` inside its
`triggers_replace` hash. Editing the script changes the hash, so the next
**`.github/workflows/apply-deploy-pipeline-fix.yml`** run re-fires the resource and pushes the new script
to every running web host. No SSH step, no operator action, no separate bootstrap script.

### Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 75 issues; none of their
bodies contain `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/ci-deploy.test.sh`, or
`apps/web-platform/infra/cloud-init`.

### Skill description budget (Phase 1.8)

Not applicable — no `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalized.

## Lane

No `spec.md` exists for this branch, so `lane:` could not be carried forward — defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement

`apps/web-platform/infra/ci-deploy.sh` authenticates the host docker daemon to `ghcr.io` on every
deploy with a credential that has been revoked since 2026-07-29 (#7071 measured it; the operator
re-measured it on 2026-09-20: `GET api.github.com/user` → 401, `ghcr.io/token` → `DENIED`, and
`GHCR_MINTER_DISABLED=true` in Doppler `soleur/prd`, so no replacement can be minted). The login
fails, a Doppler re-fetch runs, the second login fails, and the deploy logs:

```
PRELUDE: docker login ghcr.io STILL FAILED after Doppler re-fetch (stage=relogin_failed)
         — private pull may fail-closed
```

Measured volume: **89 occurrences per 168 h**, one per deploy. The image still arrives because the
self-hosted zot mirror serves it, so nothing goes red.

Three things make this worse than noise:

1. **The title's framing is backwards.** zot is not covering for GHCR; GHCR is the dead half. ADR-096's
   own 2026-07-30 amendment says so: *"GHCR still receives every image (dual-push is live) but nothing
   can read it back. Receiving is not serving. zot is therefore not redundant — it is the **sole pull
   path**."* The 89 lines a week are the backup announcing it is gone.
2. **The dead credential is not merely unused — it is presented, and that is itself a defect.** GHCR
   denies an *authenticated* request carrying a revoked token where it would have served the same
   bytes anonymously. That is exactly how the *public* cosign verifier image became unpullable
   (`result=cosign_absent`, 89/89, #8037). Item 1a worked around it with an isolated anonymous docker
   config; the revoked entry is still sitting in the effective config.
3. **The recorded architecture already says this change is owed.** `model.c4`'s
   `hetzner -> ghcr` edge reads: *"DEAD EDGE as of 2026-07-30 … kept because the CODE PATH still
   exists, not because it works … This edge stays DEAD pending #8036 1c."* The model names this plan
   by number.

The operator's 1c ruling (2026-09-22) closes the third state the diagnosis named as indefensible:
*"retrying a credential that has been revoked for seven weeks, twice per deploy, and logging it as
though it might recover."*

## Proposed Solution

Delete the host-side GHCR read path from `ci-deploy.sh`, sweep the revoked credential out of every
docker config the deploy user can write, and bring every off-box consumer of the deleted signals to
agreement in the same PR. CI's GHCR write and CI's GHCR read (the ADR-169 restore source) are
untouched.

The change is a **deletion plus a reconciliation**, and the reconciliation is the larger half. Eleven
artifacts outside `ci-deploy.sh` consume a string this change removes; three of them fail loudly, three
go silently vacuous, and five carry operator-facing text that becomes false.

## Technical Approach

### Architecture

The host pull path today, and after:

```
BEFORE                                            AFTER
------                                            -----
ghcr_prelude_and_login                            prefetch_deploy_secrets
  ├─ read /etc/default/soleur-ghcr-read             ├─ prefetch SENTRY_* from Doppler   (kept — #7095)
  ├─ prefetch SENTRY_* from Doppler                 ├─ sweep the ghcr.io auth from the DEPLOY cfg  (NEW)
  ├─ docker login ghcr.io          ──┐              └─ _ghcr_cfg_probe ×3 → SOLEUR_DEPLOY_GHCR_CONFIG
  │    └─ on failure:               │                                                    (kept — 1b)
  │       refetch_ghcr_and_relogin ─┤ DELETED
  └─ _ghcr_cfg_probe ×3 → marker    │
                                    │
zot_gate_and_login  (unchanged) ────┘            zot_gate_and_login  (unchanged)

pull_image_with_fallback                          pull_image_with_fallback
  ├─ ZOT_ACTIVE=1: docker pull zot  (no retry)      ├─ ZOT_ACTIVE=1: _pull_with_transient_retry <zot ref>
  │    └─ on miss: _ghcr_pull_or_recover ──┐        │    └─ on miss: _try_local_cache_reload
  │         ├─ auth-denied leg  ───────────┤ DEL    │         └─ else pull_failure_event → image_pull_failed
  │         └─ transient retry loop        │        └─ ZOT_ACTIVE=0: _try_local_cache_reload
  │    └─ else _try_local_cache_reload     │                  └─ else pull_failure_event → image_pull_failed
  └─ ZOT_ACTIVE=0: _ghcr_pull_or_recover ──┘
```

Three structural consequences the implementation must handle explicitly.

**1. `ghcr_prelude_and_login` is not only a GHCR login, and deleting it would take the host
Sentry-dark.** It is the sole site prefetching `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` /
`SENTRY_PUBLIC_KEY` into the script's own env before any pull or verify emitter, and its own comment
records the cost of losing that: *"that blanked all seven `[[ -n $SENTRY_INGEST_DOMAIN && … ]]` guards
and took the host Sentry-dark … It is why 341 unit failures over 5.7h paged nobody"* (#7095). It is
also the emitter of the 1b marker. The function survives, gutted and **split into three named functions** (see Phase 2); it has
exactly one call site.

**2. Removing the GHCR leg removes the pull path's only transient retry.** The bounded backoff loop
(`PULL_TRANSIENT_RETRY_SLEEPS`, default `2 4`, #6525) lives inside `_ghcr_pull_or_recover`. The zot arm
is a bare `docker pull` with no retry at all. Deleting the function wholesale would be a silent
availability regression on the path that is about to carry production alone, and would leave the seven
`T-6525-*` tests exercising nothing. The function is therefore **kept, its auth arm deleted, renamed
`_pull_with_transient_retry`, and given a ref argument** so the zot arm can call it. This is the
minimal edit that avoids a capability regression; the alternative (accept the regression) is recorded
under Alternatives.

**3. `ZOT_ACTIVE=0` becomes a terminal state.** Today a zot-dark deploy falls through to the GHCR path.
After 1c there is no second registry, so the order is `_try_local_cache_reload` → `pull_failure_event`
→ `image_pull_failed`, which keeps the old container live (downtime-safe) and pages. This is not new
risk being introduced — a zot-dark deploy already ends in `image_pull_failed`, because the GHCR arm it
falls through to cannot authenticate. 1c makes the outcome honest instead of arriving via a 401.

### The sweep, and why it is in-script and idempotent

The 1b marker's first post-apply reading measured a revoked `ghcr.io` inline auth in **both** the
effective deploy config and the legacy home config. The sweep removes the key from the **deploy**
config only — see the scope correction above for why the home one is structurally unreachable
from `webhook.service`, and why grading on it would keep #8036 open forever:

> **This plan carried a verbatim copy of `sweep_stale_registry_auth` here. It has been deleted
> rather than updated (2026-09-23, #8600 review).** Two reasons. First, the copy had already
> DRIFTED from the shipped function inside this one PR — it said `SWEPT_STATE=yes # a sweep was
> performed`, while the code says *attempted*, and it claimed `docker logout` "would rewrite the
> LINK and leave the target's credential in place", the opposite of the code's reasoning. Second
> and decisively, the design it documented was **wrong**: see the amendment below.
>
> The implementation is the single source. Read it at `apps/web-platform/infra/ci-deploy.sh` ›
> `sweep_stale_registry_auth`.

> **Amendment 2026-09-23 (#8600 review) — `docker logout` ALONE DOES NOT SWEEP.** The design
> above chose the registry's own removal verb over a `jq` rewrite, and argued it "additionally
> clears a `credHelpers` indirection that a `del(.auths…)` would leave behind". That is inverted,
> and it was falsified by running it (docker 29.7.2, throwaway `DOCKER_CONFIG`, no network):
>
> | deploy `config.json` | `docker logout ghcr.io` | file after |
> |---|---|---|
> | inline `auths` only | rc 0, "Removing login credentials" | entry removed |
> | `auths` + `credHelpers["ghcr.io"]` | rc 0, same message | **byte-identical** |
> | `auths` + `credsStore` | rc 0, same message | **byte-identical** |
> | `credHelpers` only, no `auths` | guard never fires | untouched |
>
> docker/cli decides `loggedIn` from `AuthConfigs[reg]` and then calls `store.Erase(reg)`, which
> asks the HELPER to drop its secret and never mutates the config map. So on any host carrying a
> helper the sweep emitted `swept=yes` every deploy while the revoked PAT stayed live, GHCR kept
> refusing the *public* cosign verifier image, and leg 1 of the close probe could never go green.
> The shipped function now does both halves — the verb for the helper-held secret, a `jq` rewrite
> for the file — and re-reads the post-state before reporting `swept=yes`.

**Why `docker logout` and not a hand-rolled `jq` rewrite** (plan review, both simplification seats):
it is the registry's own removal verb, it is already this repo's idempotent-teardown idiom in five
workflows, it preserves the co-resident zot entry by construction rather than by a carefully-scoped
`del()`, it writes the file with docker's own mode — which deletes the `chmod --reference` mode hazard
and the acceptance criterion that existed only to guard it — and it additionally clears a
`credHelpers["ghcr.io"]` / `credsStore` indirection that a `del(.auths…)` leaves behind. That
indirection is not hypothetical: `_ghcr_cfg_probe` already has a token for it.

`sweep_stale_registry_auth` runs **before** `emit_registry_config_marker`, so the marker reports the
post-sweep state and can render `swept=$SWEPT_STATE` (P4), and **before** `zot_gate_and_login`, so the
zot login's write is never racing it (P3). The `SWEPT_STATE` global is the out-parameter: an earlier
sketch returned 0 on every arm and had no way to report the token `AC-F4` demands. **Both orderings are load-bearing and only the first was named** — the call site carries one
comment stating both, and with the three-way function split the ordering is visible at the call site
rather than buried 100 lines into one function. It is a no-op on the second and every later deploy: the
`jq -e` guard returns non-zero on a clean file.

**`jq` is therefore a hard dependency of the close criterion, and `na` must FAIL.** On a host without
`jq` the sweep no-ops *and* `_ghcr_cfg_probe` emits `*_ghcr_auth=na`, not `none`. The probe's PASS
predicate requires `deploy_ghcr_auth=none`, so an `na` reading fails closed — but only by
accident of the predicate's spelling. The probe header states it explicitly.

Why in-script rather than an operator step or a bootstrap script: `terraform_data.deploy_pipeline_fix`
(`apps/web-platform/infra/server.tf`) hashes `file("${path.module}/ci-deploy.sh")` into its
`triggers_replace` and is *"the sole path for pushing ci-deploy.sh … to production"*. Editing the
script therefore already delivers the sweep to every running host, via
`.github/workflows/apply-deploy-pipeline-fix.yml`. A second delivery mechanism would buy nothing
(`hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`).

Why it is durable: nothing re-creates the home entry. Cloud-init's `runcmd` and
`soleur-host-bootstrap.sh` both run as **root** with `DOCKER_CONFIG` unset, so their
`docker login ghcr.io` writes `/root/.docker/config.json` — the marker's `root_cfg` slot, which
`effective=deploy_cfg` proves the deploy CLI does not resolve. `grep -rn '\.docker/config.json\|/home/deploy/\.docker\|sudo -u deploy' apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/soleur-host-bootstrap.sh`
returns zero hits. Since #6565 the deploy user's own logins go to `$DEPLOY_DOCKER_CONFIG_DIR`, so
`/home/deploy/.docker/config.json` is written by no live code path at all — it is a pre-relocation
fossil. The deploy config entry is likewise only ever re-written by a `docker login ghcr.io` this
change deletes.

### Implementation Phases

#### Phase 1: RED — the mutation matrix, written before the deletion

Per `cq-write-failing-tests-before` and the constitution's *"A lint cited as the oracle for a guard is
proven by a RED, never a green."* Every row below must be driven RED on the **current** tree before any
deletion, and green after.

**`## Test Scenarios` is the single source of truth for the `T-1c-*` set.** An earlier draft carried
three different contracts for the same identifiers — nine rows here, fifteen there, "add `T-1c-1` …
`T-1c-15`" in `## Files to Edit` — so whoever implemented it would have written whichever section they
read last. This phase names the classes; the identifiers and their assertions live in one place.

Classes delivered, all in `apps/web-platform/infra/ci-deploy.test.sh`:

- `T-1c-1` residual-zero: the committed `ci-deploy.sh` contains **zero** `docker login ghcr.io`
  invocations and no `refetch_ghcr_and_relogin` definition. RED today (three call sites exist).
- `T-1c-2` the sweep removes an inline `ghcr.io` auth from the DEPLOY config in one deploy, leaves
  the HOME config byte-identical, and leaves the co-resident zot auths entry **equal as a JSON
  value** (`jq -S '.auths'` compare).
- `T-1c-3` idempotence: a second deploy over an already-clean config performs **no write** (mtime
  unchanged) — folded into `T-1c-2`'s fixture rather than given its own row, since the defect it
  catches is one redundant config write.
- `T-1c-4` the marker reads `deploy_ghcr_auth=none` and carries `swept=yes` after a sweep, `swept=no` on a clean second deploy — the positive
  control the close criterion depends on.
- `T-1c-5` the SENTRY_* prefetch still runs and still precedes `zot_gate_and_login` (assert on the
  emitted order, not on the function body).
- `T-1c-6` `ZOT_ACTIVE=0` with no local-cache candidate ends in `pull_failure_event` /
  `image_pull_failed`, and issues **zero** `docker pull` against a `ghcr.io/` ref.
- `T-1c-7` the transient retry still fires on the **zot** arm with the `PULL_TRANSIENT_RETRY_SLEEPS`
  schedule, and its break-glass empty-value disable lever still works (**P7**).
- `T-1c-8` the swept config keeps mode 0600 and its owning uid, asserted explicitly rather than
  as "unchanged" (an unchanged-assertion passes against a sweep that never ran).
- `T-1c-9` harness row (must-RED): stubbing the sweep to a no-op must red `T-1c-2` and `T-1c-4`.

  > The two identifiers above disagreed with `## Test Scenarios` in an earlier draft of this plan
  > — this list gave `T-1c-8` as an untouched-config harness row, while Test Scenarios gave it as
  > the mode/ownership row. `## Test Scenarios` is this plan's declared single source of truth for
  > the `T-1c-*` set, so it wins and this list is corrected to match. The untouched-config cases
  > it named are covered, as `## Edge Cases` rows, by the `#8036 1b` marker matrix
  > (`credsstore` / `noghcr` / `absent`), which asserts `swept=no` or `swept=na` for each.

**Do NOT author rows for `_try_local_cache_reload`.** An earlier draft added three (same-version
rescue, no-candidate hard fail, new-version fallthrough) on a domain-review finding that its
new-version fallthrough was untested. **That finding is false** and plan review measured it: the
`--- #6512 local-cache reload tier (both registries fail → reuse the RUNNING image) ---` block in
`ci-deploy.test.sh` already covers all three, and its new-version row's PASS string reads verbatim
*"new-version deploy (running image is an older version) → tier does NOT fire, hard image_pull_failed
(no stale-bits rollback)"*. `_try_local_cache_reload` is **not edited by this PR** — "becomes more
load-bearing" is not "changed". Cite the existing `#6512` cases in the AC instead.

Success criteria: the rows above, each proven RED on `origin/main`'s `ci-deploy.sh` before any
deletion.

#### Phase 2: the script surgery

`apps/web-platform/infra/ci-deploy.sh`:

- Delete `refetch_ghcr_and_relogin()` entirely.
- **Split `ghcr_prelude_and_login()` into three named functions** (devex review; supersedes the earlier
  single-rename proposal). Drop the baked-cred read, the `SOLEUR_GHCR_READ_FILE` seam, the
  `_docker_login_capture ghcr.io` call, both `PRELUDE: docker login ghcr.io …` arms, the
  `PRELUDE: GHCR_READ_{USER,TOKEN} not both present` arm and the `export GHCR_READ_USER`.
  **Rewrite the `elif` too — it is a deploy-killer if missed.** The SENTRY_* loop sits inside
  `if command -v doppler … && [[ -n "${DOPPLER_TOKEN:-}" ]]`, whose sibling is
  `elif [[ -z "$ghcr_user" || -z "$ghcr_token" ]]; then logger … "doppler/DOPPLER_TOKEN unavailable and
  baked GHCR creds incomplete — skipping GHCR login + SENTRY prefetch"`. Delete those two locals and
  that `elif` expands two **unbound** variables under `set -euo pipefail`, aborting the deploy at the
  prelude — before `T-1c-5`'s emitted-order assertion can observe anything. The arm becomes a plain
  `else` whose log line drops its GHCR clause. What remains
  is three unrelated jobs, so give each its own name and hoist the ordering to the single call site:

  ```bash
  prefetch_deploy_secrets      # the SENTRY_* loop (the #7095 comment moves with it, intact)
  sweep_stale_registry_auth    # the deploy-config sweep (ONE config; see the scope correction)
  emit_registry_config_marker  # _ghcr_cfg_probe ×3 + SOLEUR_DEPLOY_GHCR_CONFIG
  ```

  **Do NOT ship a single `deploy_prelude()`.** "Prelude" names when the code runs, not what it does;
  renaming a misleading name to a vacuous one moves the confusion to the next reader instead of
  removing it. The split is also what makes Guard 1's ordering invariant cheap — see that guard's
  row 4. Risk is low: all three arms are already fail-open, no local crosses a boundary
  (`ghcr_user`/`ghcr_token` are being deleted; `_GHCR_CFG_MARKER` is a global). Cost is one extra
  rename in the two `cloud-init.yml` comments the plan already edits.
- Delete the auth-denied arm of `_ghcr_pull_or_recover()`; rename to `_pull_with_transient_retry()`;
  give it a ref parameter.
- `pull_image_with_fallback()`: delete the GHCR fallback branch (and the `RETIREMENT TRIPWIRE`
  comment it carries — note that comment is itself stale, claiming the soak's FAIL set is "FOUR
  entries" when it is five); route the zot arm through `_pull_with_transient_retry`; delete the
  `ZOT_ACTIVE=0` GHCR tail.
- **Do NOT rename `GHCR_DOCKER_CONFIG`.** An earlier draft renamed it to `DEPLOY_DOCKER_CONFIG_FILE`.
  Cut at plan review: it maps to **no property**, costs 9 sites in the script plus its test, and the
  ADR-087 amendment clause about the name rotting existed *only because of the rename*. Correct the
  misleading header comment instead (`# The config FILE is written by ghcr_prelude_and_login (host pull
  auth) …`) — the comment is what misleads, and a comment is free to fix.
- Do **not** delete `_docker_login_capture`, `_docker_login_failure_class`, `_docker_login_http_status`,
  `_login_hatch`, `_login_kw`, `_login_tok`, `_pull_result_is_auth_denied`, `_pull_result_is_transient`,
  `pull_auth_recovery_event`, `registry_pull_event` or `_try_local_cache_reload` — every one is still
  reached by the zot gate, `pull_failure_event`, or the surviving retry arm.

Success criteria: Phase 1's nine rows green; the existing suite's GHCR rows deleted or rewritten (see
Files to Edit); `bash apps/web-platform/infra/ci-deploy.test.sh` green.

#### Phase 3: the consumer reconciliation

Three consumers break loudly, three go silently vacuous, five carry false operator text.

**Breaks loudly — must be edited in the same PR:**

- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` —
  `expect(ciDeploy).toContain("registry_pull_event ghcr-fallback")` and
  `expect(tf).toContain('value = "ghcr-fallback"')` and the `soakQueryFor("ghcr-fallback")` pin — **plus the two hard cardinality
  assertions `expect(alarm.size).toBe(5)` and `expect(soakFailQueries().size).toBe(5)`, which are what
  actually gate the parity and which an earlier draft omitted.** All five move to 4 / the four surviving
  signals. `issue-alerts.tf` itself flags the pair.
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — AC20 clause (3) and the
  positional `_doppler_get_or_report GHCR_READ_{USER,TOKEN}` assertions inside
  `CD_PRELUDE_FN="$(awk '/^ghcr_prelude_and_login\(\) \{/{f=1} …)"`. The cloud-init half of AC20
  (clauses 1 and 2 — the bake and its 0600 mode) **stays**, because cloud-init is out of scope.
- `apps/web-platform/infra/ci-deploy.test.sh` — the S1A, `#6400` AC1/AC2/AC4/AC14, `#6497` T-5B-17 /
  T-5B-18, `#7095` T-7095-4, `#6525` and `#8036 1b` blocks.

**Goes silently vacuous — the higher-risk class:**

- `scripts/followthroughs/zot-soak-6122.sh` — drop `FAIL_QUERIES[rolling]` **and move the hard floor
  `if (( ${#FAIL_QUERIES[@]} != 5 ))` to `!= 4`** in the same edit. Leaving the floor at 5 would make
  every sweep a permanent `exit 2` TRANSIENT; dropping the operand without the floor edit is the defect
  the floor exists to catch. **Operational stake: low, and the plan should not overstate it** — ADR-096's
  2026-09-22 amendment records *"The soak is **not enrolled** in the sweeper: with this `START`, its
  verdict is fixed at FAIL, so a daily run adds no information."* The edit is source hygiene plus the
  parity test's correctness, not a live alarm repair. The *record* stake is the one that matters, and it
  lives in the ADR-096 amendment.
- `scripts/followthroughs/zot-soak-6122.test.sh` — every fixture spelling `ghcr-fallback=` (e.g.
  `HEALTHY="…;ghcr-fallback=0;zot-gate-degraded=0;…"`), plus a floor row asserting **4**.
- `apps/web-platform/infra/ci-deploy.test.sh`'s
  `HELPER_BODY=$(awk '/^refetch_ghcr_and_relogin\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")` — an extraction that
  yields an empty string once the function is gone, making every assertion over it vacuously true.
  Delete the block rather than letting it pass.
- `tests/scripts/test-sentry-alert-live-fidelity.sh` — its comment pins positions:
  *"five action-filter conditions; `[0]` is registry=ghcr-fallback and `[2]` is …"*. Removing `[0]`
  shifts every index.

**Narrow, do not retire** — the in-code tripwire's own instruction:

- `apps/web-platform/infra/sentry/issue-alerts.tf` › `resource "sentry_alert" "zot_mirror_fallback_rate"`
  — delete the one condition `{ tagged_event = { key = "registry", match = "eq", value = "ghcr-fallback" } }`,
  keep the other four. Its `lifecycle` is `ignore_changes = [environment]`, so `action_filters` **are**
  Terraform-managed here (unlike `sentry_alert.sandbox_startup_failure` ~30 resources earlier in the same file, which is `ignore_changes = all` and whose edits are inert — do not copy that block's posture).
- `apps/web-platform/infra/sentry/alert-reference.json` — regenerate the captured reference.
- `scripts/sentry-alert-live-fidelity.sh` — re-pin the committed capture after the apply.

**Operator-facing text that becomes false:**

- `.github/workflows/scheduled-zot-restart-loop.yml` — the remediation step-summary instructs
  `scripts/betterstack-query.sh --since 24h --grep ghcr-fallback --grep local-cache`. After 1c the
  first grep is permanently empty; `local-cache` remains the live signal. Rewrite the instruction and
  its surrounding rationale.
- `apps/web-platform/infra/variables.tf` — `ghcr_read_token`'s description says *"consumed by
  ci-deploy.sh (host pull + cosign .sig fetch auth) + cloud-init fresh-boot login"*. Drop the
  `ci-deploy.sh` clause; the cloud-init clause stays true.
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` — the five-signal list and
  the *"the only no-SSH page gating the irreversible 5.5 PAT revoke"* claim.
- `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` — its PASS requires a positive OK line
  per `_MACHINE_ID` matching `PRELUDE: docker login ghcr\.io ok|ZOT_GATE: active .* docker login .* ok`.
  The first disjunct dies. Drop it, leaving the `ZOT_GATE` leg, and state in the PR that the probe is
  now one-legged.
- `scripts/followthroughs/zot-login-gate-names-failure-6497.sh` — its documented 3-state taxonomy names a `ghcr` state that becomes unreachable. It does **not** stop
  producing rows; the `ZOT_GATE` half still satisfies its `ANY_LINES` non-vacuity check, so it does not
  force TRANSIENT. Update its documented 3-state taxonomy, which names an unreachable `ghcr` state.
- `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` — it soaks the recovery machinery this PR
  deletes. Retire it with its `#6400` tracker rather than leaving a sweeper asserting over deleted code.

**Advisory-only, verified safe, do not touch:** `scripts/registry-replace-preflight.sh` (P2 carries a
`MUST NEVER BECOME A GATE / ZERO HERE IS NOT EVIDENCE OF ANYTHING` banner),
`scripts/registry-pull-path-health.sh` (the D10 gate already dropped this operand — see
`tests/scripts/test-registry-pull-path-health.sh`'s *"the dark ghcr-fallback operand and its siblings
are gone from the gate body"*), `.github/workflows/apply-web-platform-infra.yml` (non-executing prose,
which 1c makes retrospectively accurate).

Success criteria: `rg -n 'refetch_ghcr_and_relogin|ghcr_prelude_and_login|registry_pull_event ghcr-fallback|stage=relogin_failed'` returns hits only in
`knowledge-base/` archives and this plan's own artifacts; the full registered suite green.

#### Phase 4: the architecture record

See `## Architecture Decision (ADR/C4)`. Three amendments and one C4 edit, all in this PR.

#### Phase 5: the close criterion, made non-vacuous

The operator's criterion — *"`stage=relogin_failed` absent on the first post-apply deploy"* — is a
pure-absence test, and `cosign-verify-live-8037.sh` records exactly why that is not enough:
*"Closure needs a POSITIVE `IMAGE_VERIFY: ok` per host, not the absence of `cosign_absent`: a host that
never deploys emits nothing."* A host that is down, or that never ran the new script, also emits no
`relogin_failed`.

The positive control is already built. The 1b marker emits once per deploy, and post-sweep it reads
a `swept=` token the pre-1c script does not emit. The
close grade is therefore a **conjunction**, per host, over the window since the apply:

1. ≥1 `SOLEUR_DEPLOY_GHCR_CONFIG` line whose latest reading carries **`swept=`** (any value) **and**
   `deploy_ghcr_auth=none`; **and**

   > **`swept=` is the version discriminator, not `deploy_ghcr_auth=none`.** An earlier draft graded on
   > the `none` token alone, reasoning that the whole pre-1c fleet reads `inline`. That is an observation
   > about today's two hosts, not a structural property: `docker login ghcr.io` currently **fails**, and a
   > failed login writes no auths entry, so today's `inline` readings are stale leftovers from when the
   > PAT worked. A **freshly provisioned** host running the *pre*-1c script would read
   > `deploy_ghcr_auth=none` on its first deploy and pass — which is `## Observability` failure-mode 3
   > ("the new code never reached this host") sailing through the probe written to catch it. The
   > `swept=` token does not exist in the pre-1c script at all, so its *presence* is the discriminator
   > and its value is the drift signal. `home_ghcr_auth` is **not graded** — see the scope correction
   > above.
2. zero `stage=relogin_failed` rows — the operator's stated criterion; **and**
3. a latest `IMAGE_VERIFY*` verdict that is not `result=verify_failed`.

Leg 3 exists because devex review measured that **no Sentry rule matches `result=verify_failed`** —
`grep -n 'cosign\|verify_failed' apps/web-platform/infra/sentry/issue-alerts.tf` returns **zero hits**.
`verify_image_signature` posts a Sentry event, but nothing pages on it. That matters here specifically:
this plan's own `## User-Brand Impact` names "the sweep clips the zot auths entry" as its worst arm, and
under the `IMAGE_VERIFY_MODE=warn` default the deploy *proceeds* — the release ships while signature
verification has silently stopped. Routing detection to `scripts/followthroughs/cosign-verify-live-8037.sh`
is not durable: **#8037 is CLOSED**, so the sweeper evaluates that probe only inside its closed-set
lookback. Carrying the leg here keeps the alarm on an open tracker and needs no Terraform apply.
(Deleting `cosign-verify-live-8037.sh` and executing its overdue `# RETIREMENT:` clause is the reviewer's
further proposal; that is scope beyond the 1c ruling and is surfaced in `decision-challenges.md` DC-2,
not applied here.)

Deliverables: `scripts/followthroughs/ghcr-read-retired-8036.sh` (+ `.test.sh`), **built by repurposing
`deploy-ghcr-pull-recovery-6400.sh`, which this PR retires anyway** — same journald source, same verdict
contract, and it keeps the family's file count flat while putting the deletion and the addition in one
reviewable hunk. Grading rules modelled on `cosign-verify-live-8037.sh` — per-`_MACHINE_ID` keying, field-isolated on
`SYSLOG_IDENTIFIER == "ci-deploy"` decoded with `fromjson` (never a substring match — the Better Stack
source also carries issue and PR bodies quoting this very tracker,
`2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`), `earliest=` pinned
strictly after the apply, `--explain` for a network-free self-description, and the
`<!-- soleur:followthrough script=… earliest=<apply+1d> secrets=… -->` directive plus the
`follow-through` label on #8036.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Mint a new GHCR read credential and keep the fallback** | Not available. `GHCR_MINTER_DISABLED=true`; ADR-096 clause (c) and ADR-088 arm-b establish that no GHCR *pull* credential can be minted without a browser, and the App installation token can `docker login` but is DENIED `docker pull`. The operator's 1c ruling took this off the table. |
| **Delete `ghcr_prelude_and_login` wholesale** | Deletes the 1b marker, which is the positive control this change's own close criterion depends on, and loses the Doppler **refresh** of `SENTRY_*` that keeps pull/verify telemetry current. *(An earlier draft said "takes the host Sentry-dark"; plan review measured that overstated — the three values are also read from the baked `/etc/default/soleur-doppler-token` at script top. The marker argument alone is decisive.)* |
| **Delete `_ghcr_pull_or_recover` wholesale** | Deletes the pull path's only transient retry on the day zot becomes the sole path, and leaves eight `T-6525-*` rows exercising nothing (a vacuous-green, `2026-07-03-pass-is-not-proof`). |
| **Keep an anonymous `docker pull` from ghcr.io as the zot-dark arm** | The app image is a private package; anonymous pull 401s. It reproduces the failure being removed, minus the log line that names it. |
| **A one-shot operator/bootstrap script for the config sweep** | `terraform_data.deploy_pipeline_fix` already delivers `ci-deploy.sh` to every running host on a content-hash trigger. A second mechanism adds an operator step the repo's rules forbid (`hr-never-label-any-step-as-manual-without`). |
| **Retire cloud-init's boot-time `ghcr_login` in the same PR** | Different blast radius (it is the fresh-boot pull's only non-zot arm), different signals (`app_ghcr_fallback` / `app_ghcr_served`, both still watched), and it writes root's config, which the deploy CLI provably does not resolve. **Deferred to a tracked follow-up (1d), not dropped.** |
| **Retire `sentry_alert.zot_mirror_fallback_rate` along with its emitter** | The in-code tripwire forbids it in terms: *"do NOT retire that alarm here — NARROW its `filters_v2` to the signals that still emit. Retiring it blinds the survivors, and zot-gate-degraded is currently its HIGHEST-volume signal."* |
| **Wait for the ADR-096 Phase-5 soak to PASS before removing the `ci-deploy.sh` branch** | Rejected, but **not** on the ground that the soak is stuck on a dark operand — that framing is wrong and was corrected in domain review. ADR-096's Amendment 2026-09-22 records **"Backfilled verdict: FAIL, six fallbacks"**, and all six sit on *live* operands (`zot-gate-degraded` ×2, `app_ghcr_served` ×3, `inngest_ghcr_fallback` ×1 / #8539) — dropping `[rolling]` does not move that verdict, and the amendment says in terms: *"This does not authorize 5.3–5.5, and no one may move `START` later to make it pass."* The real argument is narrower and is the one to record: **1c performs a PARTIAL 5.3 — the `ci-deploy.sh` branch only, not the two `cloud-init.yml` branches, not GHCR push, not egress — while the soak verdict stands at FAIL, on the ground that the branch being deleted is already non-functional, so its deletion cannot change the fleet's exposure, which is exactly the quantity the soak measures.** Anything the soak would have caught on that branch is already caught by the four signals that survive. See `## Architecture Decision (ADR/C4)` for the amendment wording. |

## Adjacent Issues

<!-- lint-infra-ignore start: this table QUOTES existing GitHub issue titles (#6630 is literally titled "operator: exercise EROFS-relocated login path on both web hosts") and records their disposition. It prescribes no step for anyone to run — every action in this plan is in-script or CI-delivered; see ## Infrastructure (IaC). -->

| Issue | State | Disposition |
|---|---|---|
| **#7295** — *the ghcr-fallback emitter is structurally dark, so `zot_mirror_fallback_rate` can never fire* | OPEN | **Resolved by this PR.** It is ADR-169's Named residual 3 (*"the emitter is not re-plumbed here, deliberately … Tracked separately"*). 1c converts "dark" into "deleted" and narrows the rule to its four live signals — the disposition #7295 asks for. `Closes #7295` in the PR body. |
| **#6565** — *repair the zot/GHCR login failure* | OPEN | **Partially mooted, not closed here.** Its GHCR half becomes unreachable (there is no GHCR login left to fail); its zot half — the EROFS `DOCKER_CONFIG` relocation — already shipped and stays live. Its follow-through `zot-login-gate-erofs-repaired-6565.sh` is edited (its `PRELUDE:` disjunct dies) but still reaches PASS on the `ZOT_GATE` leg. Comment on #6565 recording the narrowing; leave the operator to close it. |
| **#6630** — *operator: exercise EROFS-relocated login path on both web hosts (#6565 close)* | OPEN | **Narrowed to zot only.** Its "both login paths" scope halves. Comment; do not close. |
| **#8037** — cosign verification | CLOSED/COMPLETED | Its probe `cosign-verify-live-8037.sh` is the template for Phase 5, and its 2026-09-21 ADR-087 amendment is the reason the cosign `:ro` mount survives this change. |
| **#6400** — GHCR pull-site recovery | (tracker) | Its follow-through `deploy-ghcr-pull-recovery-6400.sh` soaks deleted code. Retire the probe and comment on the tracker. |
| **New: 1d** — retire cloud-init / `soleur-host-bootstrap.sh` boot-time `ghcr_login` | to file | Filed by this PR with the Cut List rationale, milestone `Phase 4: Validate + Scale` (`wg-when-deferring-a-capability-create-a`). |
| **New: debt** — extract the duplicated journald-envelope decode shared by the follow-through family | to file | `grep -l SYSLOG_IDENTIFIER scripts/followthroughs/*.sh` returns **16** files, each carrying its own copy of the `fromjson` decode + `_MACHINE_ID` keying + field-isolation block; this plan's probe is the 17th. That duplication, not the file count, is where this family's maintenance cost lives. **Explicitly NOT extracted here** — it would touch 16 probes carrying live tracker verdicts. Filed alongside 1d. |

<!-- lint-infra-ignore end -->

## Scoped Advisor Consult (Phase 4.5)

A strong-model consult ran against the Overview, the Implementation Phases and Phase 3 (judged the
riskiest). It returned one falsifiable challenge, one scope challenge and two free ordering notes.
All four are resolved here rather than deferred.

### Challenge 1 — "does the sweep accidentally restore a working anonymous GHCR fallback?" FALSIFIED, measured

The consult observed that item 1a proved a *public* image 401'd **only because the dead inline entry
poisoned the config**, and pulled fine under an isolated anonymous config. If the app packages were
public, the sweep would restore a working anonymous fallback in the same commit that phase 2(c)
deletes it — and the ADR amendments would encode the wrong answer as architecture.

Measured directly on 2026-09-23, with a must-PASS control:

| scope | anonymous `GET ghcr.io/token?service=ghcr.io&scope=repository:<pkg>:pull` |
|---|---|
| `sigstore/cosign/cosign` (control — known public, the 1a case) | `{"token":"djE6c2lnc3RvcmUvY29zaWduL2Nvc2lnbjox…"}` |
| `jikig-ai/soleur-web-platform` | `{"errors":[{"code":"UNAUTHORIZED","message":"authentication required"}]}` |
| `jikig-ai/soleur-inngest-bootstrap` | `{"errors":[{"code":"UNAUTHORIZED","message":"authentication required"}]}` |

The control returning a token is what makes the two failures evidence about **package visibility**
rather than about network reachability or blocked egress. Both app packages — the two the deploy
pulls, per `ci-deploy.sh`'s `[web-platform]="ghcr.io/jikig-ai/soleur-web-platform"` /
`[inngest]="ghcr.io/jikig-ai/soleur-inngest-bootstrap"` map — are **private**. An anonymous pull 401s
regardless of what is in the config, so the sweep restores nothing and phase 2(c) stands. This agrees
with #6005 ("the app image is now a PRIVATE GHCR package") and with ADR-096 clause (c), but those are
claims in the repo; the table above is a measurement.

### Challenge 2 — "2(b) adds new behavior to the only live pull path" ACCEPTED, matrix widened

The consult is right that re-pointing the zot arm through the transient-retry loop is a *behavior
addition* to the sole remaining pull path, and that `deploy_ghcr_auth=none` grades green whether or
not that path works. Two options were weighed:

- **Drop the re-point.** But with the GHCR arms gone nothing calls `_ghcr_pull_or_recover`, so
  dropping the re-point *is* deleting the transient retry — an availability regression on the sole
  path, taken on the day it becomes the sole path, plus eight `T-6525-*` rows exercising nothing.
- **Keep it and widen the matrix.** Adopted. Phase 1 gains three rows that exercise the *new terminal
  route* end-to-end rather than its string residue, so its first execution is in the suite and not in
  production: `T-1c-10` zot transient → retry → success; `T-1c-11` zot transient → retries exhausted →
  `_try_local_cache_reload` rescue → deploy proceeds; `T-1c-12` zot transient → retries exhausted → no
  local-cache candidate → `pull_failure_event` → `image_pull_failed` with the **old container still
  running**.

If `plan-review` prefers the split, the re-point is the clean seam to cut — it is independent of the
deletion and of the sweep.

### Note A — narrow the consumers BEFORE deleting the emitter ADOPTED

Within the branch, the soak floor (`!= 5` → `!= 4`), the `FAIL_QUERIES` edit and the Sentry
`action_filters` narrowing land in a commit **before** the `registry_pull_event ghcr-fallback` call
site is deleted. Otherwise a window exists in which the soak counts an operand nothing can emit —
vacuously green, and reported by nothing. The ordering costs nothing and is asserted by AC-Q4.

### Note B — record the ADR-096 deviation as a gate INVALIDATION, not a reschedule ADOPTED

See `## Architecture Decision (ADR/C4)`.

### Provenance note

This section was lost once during authoring when a scripted append was refused by a pre-tool guard
and the retry omitted it, while two later sections still cited its evidence. It was recovered by the
section-count discipline in `plan-sharp-edges.md` ("after ANY scripted multi-edit re-count the
document's sections"). Recorded because the near-miss is the point: the citation survived, the
evidence did not.

## User-Brand Impact

- **If this lands broken, the user experiences:** a release that never reaches production. A defective
  sweep or a mis-ordered prelude aborts `ci-deploy.sh` before the pull, `final_write_state 1
  "image_pull_failed"` fires, and the **previous container keeps serving** — so the user sees a stale
  `soleur.ai` app (the version banner and any shipped fix simply do not appear) rather than an outage.
  The worse arm is silent: if the sweep were to delete the zot auths entry alongside the `ghcr.io` one,
  the cosign `.sig` fetch would 401 and every deploy would report `IMAGE_VERIFY_FAIL:
  result=verify_failed`. Under the current `IMAGE_VERIFY_MODE=warn` default that does **not** block, so
  the user would get their release while signature verification had silently stopped working.
- **If this leaks, the user's data is exposed via:** nothing new. The change **removes** credential
  material from the host (a revoked `ghcr.io` PAT sitting inline in two docker configs, one of which is
  bind-mounted `:ro` into an ephemeral container on every deploy). The one new write path touches only
  `.auths["ghcr.io"]` in files the deploy user already owns, preserves mode via
  `chmod --reference`, and logs a fixed string — no config content, username or token value reaches
  `logger`, matching the closed-vocabulary discipline `_ghcr_cfg_probe` already enforces for the same
  files (journald ships **unscrubbed** to Better Stack).
- **Brand-survival threshold:** `none`

*Scope-out override (the diff touches `apps/web-platform/infra/**`, a preflight-sensitive path):*
`threshold: none, reason: the change is confined to the host-side deploy mechanism — it handles no
end-user data, alters no user-visible surface, and its worst failure keeps the previously-verified
container serving rather than degrading a user's session.`

## Observability

```yaml
liveness_signal:
  what:          "SOLEUR_DEPLOY_GHCR_CONFIG marker (journald, SYSLOG_IDENTIFIER=ci-deploy), one line per deploy per host, carrying deploy_ghcr_auth=/home_ghcr_auth=/root_ghcr_auth= closed-vocabulary tokens"
  cadence:       "per-deploy (6-12/day/host)"
  alert_target:  "scripts/followthroughs/ghcr-read-retired-8036.sh via the scheduled follow-through sweeper; a FAIL comments on #8036 and leaves it open"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (emitter, in emit_registry_config_marker); .github/workflows/scheduled-followthrough-sweeper.yml (grader)"

error_reporting:
  destination:   "journald -> Vector -> Better Stack Logs (queried by scripts/betterstack-query.sh under doppler -p soleur -c prd_terraform); pull failures additionally to Sentry project web-platform via pull_failure_event (SENTRY_INGEST_DOMAIN/SENTRY_PROJECT_ID/SENTRY_PUBLIC_KEY, prefetched by prefetch_deploy_secrets)"
  fail_loud:     "IMAGE_PULL_FAILED / final_write_state 1 image_pull_failed on a total pull failure; ZOT_GATE_DEGRADED when zot is configured but inactive; IMAGE_VERIFY_FAIL: result=verify_failed when the cosign .sig fetch loses its credential"

failure_modes:
  - mode:        "The sweep deletes or corrupts the zot auths entry that shares the deploy docker config"
    detection:   "IMAGE_VERIFY_FAIL: result=<class> in journald, graded per host as leg 3 of scripts/followthroughs/ghcr-read-retired-8036.sh (latest-verdict-per-_MACHINE_ID, closed allowlist ok|reused_local_reload)"
    alert_route: "the follow-through sweeper comments on #8036 (exit 5 = ACTION REQUIRED). NOT #8037: that tracker is CLOSED, so its sweeper only evaluates inside a closed-set lookback and cannot carry this leg. There is no Sentry rule for cosign verdicts (grep issue-alerts.tf: zero hits), which is why the leg is carried by the probe."
  - mode:        "zot is unreachable or unconfigured, and there is no longer a second registry"
    detection:   "registry=zot-gate-degraded Sentry event (zot_gate_degraded_event) and, on a total miss, op:image-pull pull_result:* via pull_failure_event"
    alert_route: "sentry_alert.zot_mirror_fallback_rate, narrowed to its four surviving conditions in this PR; zot-gate-degraded is its highest-volume signal"
  - mode:        "The new code never reaches a host (deploy_pipeline_fix did not re-fire), so relogin_failed silently stops only because that host stopped deploying"
    detection:   "the positive control: the host's latest SOLEUR_DEPLOY_GHCR_CONFIG line still reads deploy_ghcr_auth=inline. Absence of relogin_failed with deploy_ghcr_auth=inline is a FAIL, not a PASS"
    alert_route: "scripts/followthroughs/ghcr-read-retired-8036.sh -> #8036"
  - mode:        "The narrowed Sentry rule drifts from the committed capture after apply"
    detection:   "scripts/sentry-alert-live-fidelity.sh, run by the release preflight"
    alert_route: "preflight failure blocks the release"

logs:
  where:         "journald on each web host (SYSLOG_IDENTIFIER=ci-deploy), shipped by Vector to Better Stack Logs; Sentry issue stream for the pull/verify events"
  retention:     "Better Stack Logs retention on the shared prd source (queried with --since windows up to 168h in this repo's probes); journald is persistent on-host but is never the query surface (hr-no-ssh-fallback-in-runbooks)"

discoverability_test:
  command:       "bash scripts/followthroughs/ghcr-read-retired-8036.sh --explain"
  expected_output: "PROBE-READY, SOLEUR_DEPLOY_GHCR_CONFIG, deploy_ghcr_auth=none"
```

`--explain` makes **zero** network calls: it prints the exact Better Stack SQL the probe would run, the
two literals it grades on, and the marker `PROBE-READY`. The script is committed in this PR, is
repo-relative, and returns in well under a second. The credentialed grade (the probe's normal mode)
needs the Doppler `prd_terraform` Better Stack connection and runs under the scheduled sweeper, which
is why the discoverability test is the self-description rather than the live query.

## Encryption Posture

This plan introduces **no** persistent data store and **no** new cross-component connection; it removes
one (host → `ghcr.io`). The section is emitted because the diff touches `*.tf`
(`apps/web-platform/infra/sentry/issue-alerts.tf`) and because the change mutates a credential-bearing
file at rest.

```yaml
at_rest:
  - store:            "/mnt/data/deploy-docker/config.json on each web host (ci-deploy.sh `readonly DEPLOY_DOCKER_CONFIG_DIR`), mode 0700 dir / 0600 file, deploy:deploy"
    mechanism:        "luks"
    evidence:         "implied by device_binding — /mnt/data is the LUKS-backed data volume; the gating of zot on the LUKS store landed in PR #8456 (merge 69b08a4ee) and the volume binding is asserted by the SOLEUR_INNGEST_SERVER_PROBE / logtail_exploration_alert.inngest_luks_wrong_volume pair for the sibling host"
    defends_against:  "a seized or RMA'd disk; a raw Hetzner volume snapshot taken while the volume is detached"
    does_not_defend:  "anything on a running, unlocked host: a compromised deploy user, a root shell, a container escape, or the :ro bind-mount this file already has into the ephemeral cosign verifier. This change REDUCES that surface by removing a revoked ghcr.io credential from the file."
    disclosed_as:     "not-publicly-claimed"
    live_verification: "available — the post-sweep state is read off-box from the SOLEUR_DEPLOY_GHCR_CONFIG marker (deploy_ghcr_auth=none), never by SSH"
  - store:            "the deploy user's home docker config dir (~/.docker/) on each web host — the pre-#6565 fossil location"
    mechanism:        "luks"
    evidence:         "implied by device_binding — /home is on the encrypted root; written by no live code path since the #6565 DOCKER_CONFIG relocation"
    defends_against:  "the same disk-at-rest cases as above"
    does_not_defend:  "a running host. This change empties its only credential-bearing key."
    disclosed_as:     "not-publicly-claimed"
    live_verification: "available — home_ghcr_auth= token on the same marker"
in_transit:
  - connection:        "web host -> zot registry (10.0.1.30:5000), the SOLE host-side image read path after this change"
    enforced_at:       "apps/web-platform/infra/ci-deploy.sh `zot_gate_and_login() {` (the /v2/ probe + docker login) and `pull_image_with_fallback() {` (the pull); the daemon-side allowance is the insecure-registries entry written at boot"
    tls:               "none — plain HTTP on the private Hetzner network (10.0.1.0/24, deny-all)"
    cert_verification: "off"
    does_not_defend:   "an attacker already inside 10.0.1.0/24 can read the pull credential and the image bytes on the wire. It does NOT defend confidentiality of the pull; it is not relied on for INTEGRITY, which is carried by @sha256 digest pinning plus the offline cosign verify against the pinned trusted root."
    disclosed_as:      "not-publicly-claimed"
  - connection:        "web host -> ghcr.io (private-package read)"
    enforced_at:       "REMOVED BY THIS CHANGE — was `ghcr_prelude_and_login() {` / `refetch_ghcr_and_relogin() {`"
    tls:               "n/a (connection removed)"
    cert_verification: "n/a"
    does_not_defend:   "n/a — the posture improvement is the removal of a revoked bearer credential from two at-rest configs and from every deploy's outbound request"
    disclosed_as:      "not-publicly-claimed"
exception:
  justification:      "The host->zot leg is plain HTTP by an existing, recorded decision: ADR-096 states that cosign digest-pinning is the integrity guard, not TLS, and the leg never leaves the private deny-all subnet. This plan does not introduce that posture; it raises its criticality by removing the (already non-functional) second read path."
  tracking_issue:     "#6126"
  reevaluate_when:    "a second mirror is built (ADR-096 clause (g)), or zot is fronted by TLS on the private net, or the private subnet ceases to be deny-all"
  expires_on:         "2026-12-20"
```

## Guard Contract

> **Trimmed at plan review, 24 mutation rows → 13.** Both simplification seats fired on the same
> scope, so per the consolidation rule the answer is delete rather than fix. Nine of the original rows
> had the **test harness** as their subject, not the system; `lint-guard-contract.py` sets
> `MIN_MUTATION_ROWS = 3` and the class it exists to catch is *"a guard whose WINDOW, CHOKEPOINT or
> IDENTIFIER SET is narrower than the property it names"* — not one of the nine was that class, and
> several restated a `T-1c-*` row verbatim. One harness row per guard survives.

### Guard 1 — host-side GHCR read residual-zero

**Property.** After this change, no code path in `ci-deploy.sh` presents a `ghcr.io` credential, and no
docker config the deploy user can write retains a `ghcr.io` inline auth across deploys.

**Assembly.** Two structural chokepoints, not a list of current members. (1) **Credential
presentation:** every `_docker_login_capture <registry> …` call site — the function is the single
chokepoint through which every `docker login` in the script flows (verified: the script contains no
bare `docker login`), so the assertion is "no `_docker_login_capture` call site names `ghcr.io`",
which survives a new login site being added. (2) **Credential at rest:** the ONE writable config
`sweep_stale_registry_auth` covers — `$GHCR_DOCKER_CONFIG`, on `/mnt/data`. The home config is
probed and deliberately NOT written (it is unreachable under `ProtectHome=read-only`), exactly as
root's is; an earlier draft of this guard said "two", which contradicted the scope correction this
plan's own Technical Approach derives. *(The earlier draft derived the sweep
list and the probe list from one shared array to defend against a third config being probed but not
swept. Cut: a generic solution to a two-element problem no diff is proposing — root's config is
probed and deliberately not written.)*

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore a single `_docker_login_capture ghcr.io "$u" "$t"` call anywhere in `ci-deploy.sh` — or re-add `refetch_ghcr_and_relogin()` with a body that logs `stage=relogin_failed` | RED |
| 2 | Add a second writable config to `emit_registry_config_marker`'s probe list without adding it to `sweep_stale_registry_auth`, after a compliant first — the **assembly** row, and the only one here that catches the class the lint's own docstring names | RED |
| 3 | Reorder the call site so `emit_registry_config_marker` runs BEFORE `sweep_stale_registry_auth` — a REORDER, not a delete. The final on-disk state is identical, so every after-the-fact assertion still passes; only a case that observes the marker *during* the window reds. With the three-way function split this is a **static assertion on call order at the single call site**, not a mid-flight observation harness — which is the whole reason the split earns its diff | RED |
| 4 | **Harness row (must-RED):** delete the assertion helper the `T-1c-*` rows call and re-run — the suite must not report a green tally over zero executed rows | RED |

**Anchor.** The guard compares the committed script's text against a *derived* expectation, not against
a stored hash, so there is no self-certifying value. For the fleet half the anchor is outside the commit
entirely — Guard 3's probe grades live journald from hosts, which no PR can edit.

### Guard 2 — soak/alert signal parity after the narrowing

**Property.** The set of registry-fallback signals the Sentry rule matches is exactly the set the
Phase-5 soak counts, and both are exactly the set `ci-deploy.sh` + `cloud-init*.yml` can still emit.

**Assembly.** Three declarations that must agree: `action_filters[].conditions[]` on
`resource "sentry_alert" "zot_mirror_fallback_rate"` in `apps/web-platform/infra/sentry/issue-alerts.tf`;
the `declare -A FAIL_QUERIES=(` array plus its runtime cardinality floor in
`scripts/followthroughs/zot-soak-6122.sh`; and the emit call sites (`registry_pull_event <tag>` in
`ci-deploy.sh`, `stage:"…"` in the cloud-init boot paths). The chokepoint already exists —
`apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` pins all three — so this
guard **extends a running test** rather than adding a fourth declaration.

**What it actually protects.** Not the soak: ADR-096's 2026-09-22 amendment records that the soak *"is
**not enrolled** in the sweeper … a daily run adds no information."* It protects the op-contract test,
which does run on every PR, and the source hygiene that keeps the three declarations honest for whoever
re-arms the soak later.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `FAIL_QUERIES[rolling]` but leave the floor at `!= 5` | RED — the test must catch the permanent-`exit 2` TRANSIENT, not leave it for the sweeper to discover at runtime |
| 2 | Drop `FAIL_QUERIES[rolling]` and move the floor to `!= 4`, but leave the `.tf` condition for `ghcr-fallback` in place | RED — parity broken the other way |
| 3 | Remove a **second** signal (`zot-gate-degraded`) from the `.tf` only, after a compliant first removal | RED |
| 4 | Delete a `registry_pull_event zot` call site so the `.tf` and the soak agree with each other but not with the emitters | RED |
| 5 | **Harness row (must-PASS, non-canonical):** reorder the four surviving `.tf` conditions — parity is set equality, not sequence. `tests/scripts/test-sentry-alert-live-fidelity.sh`'s positional `[0]`/`[2]` comment must become a key lookup **in the code fix**, or this row fails for the wrong reason | PASS |

**Anchor.** `scripts/sentry-alert-live-fidelity.sh` compares the committed `.tf` against the **live**
Sentry workflow read from the API — a value one diff cannot move, because the live side only changes
after an apply the reviewer can see. The soak side's anchor is the runtime cardinality floor: a literal
compared against `${#FAIL_QUERIES[@]}`, so emptying the array at runtime still refuses a verdict rather
than passing with `FALLBACKS=0`.

### Guard 3 — the close criterion is a conjunction, never a pure absence

**Property.** #8036 closes only when **every host that emitted any `ci-deploy` record since
`earliest`** has positively demonstrated it is running the post-1c script (latest
`SOLEUR_DEPLOY_GHCR_CONFIG` carries `swept=` and reads `deploy_ghcr_auth=none`), emitted zero
`stage=relogin_failed`, and has a latest `IMAGE_VERIFY*` verdict that is not `verify_failed`.

> **Scoped to "every host that spoke", not "every deploying host".** A probe that groups by
> `_MACHINE_ID` over its own result set structurally cannot see a host that emitted nothing — such a
> host is not a group. `cosign-verify-live-8037.sh` hit this and resolved it by measurement rather than
> grading (*"every `IMAGE_VERIFY` line in 24 h came from ONE machine id (web-1), so PASS needs >=1
> host, never >=2"*). Stating the property as "every deploying host" would make row 1 a green that
> cannot be driven RED, and would have the close comment tell the operator "all hosts confirmed" when
> it means "every host that spoke".

**Assembly.** Every journald record from the fleet whose decoded `SYSLOG_IDENTIFIER` field is exactly
`ci-deploy` and whose `__REALTIME_TIMESTAMP` is at or after `earliest`, grouped by `_MACHINE_ID`. The
chokepoint is the single Better Stack query in `scripts/followthroughs/ghcr-read-retired-8036.sh`, so a
host cannot be graded by one rule and counted by another. This guard's prose lives in that script's
header block, following the template's own convention.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A host that emitted `stage=relogin_failed` but **no** post-sweep marker row | RED — the testable form of the defect the conjunction exists to catch; a pure-absence probe passes it |
| 2 | A host whose latest marker reads `deploy_ghcr_auth=inline`, or `deploy_ghcr_auth=na` (the jq-absent case), and which emitted no `relogin_failed` | RED — `na` must fail closed, not pass |
| 3 | A **second** host added, compliant-first / non-compliant-second | RED — the probe must not stop at the first host |
| 4 | **Harness row (must-RED):** replace the HTTP fixture with a 500, or stub the query helper to echo a bare word where an integer is expected, and assert the probe still reports a 0/1 verdict | RED — must be TRANSIENT, never a numeric verdict |

**Anchor.** The graded values are produced by hosts, off-box, after the merge. No commit can move them,
which is what makes this probe an anchor for Guard 1 rather than a restatement of it.

## Domain Review

**Domains relevant:** engineering

All eight domains were assessed against the plan body. Marketing, sales, finance, legal, support,
operations and product carry no implication: no user-facing surface, no pricing or billing path, no
personal data, no vendor relationship change (both registries are already provisioned; no account, plan
or cost moves), no support-visible behavior. The one operations-adjacent fact — `GHCR_READ_TOKEN`
becomes unconsumed by `ci-deploy.sh` — does **not** retire the secret, because cloud-init still reads
it; no Doppler or vendor change is in scope.

### Engineering

**Status:** reviewed
**Assessment:** *"APPROVE the substance, BLOCK on structure."* The three structural decisions (2a/2b/2c)
were each independently verified against source and confirmed correct; risk of zot-as-sole-read-path
rated **Low** on the ground that no reachable success arm exists on the GHCR path today. Eight findings
were returned and **all eight are folded into this plan** rather than deferred:

1. **The ADR-096 sequencing argument was aimed at the wrong operand.** Corrected in
   `## Alternative Approaches Considered` and in the amendment wording below. The soak verdict is a
   recorded **FAIL on live operands**, not a stall on a dark one.
2. **ADR-087 was not scoped for amendment.** Now scoped — its `.sig`-fetch content contract is made
   false by the sweep. Added below.
3. **Four wrong-ref emit sites fall out of "give it a ref parameter."** Added to Phase 2 and to the
   test matrix (`T-1c-13`).
4. **The FR-C1 zot-stderr breadcrumb is physically inside the deleted branch.** Added (`T-1c-14`).
5. **`_try_local_cache_reload`'s new-version fallthrough has no test row.** Added (`T-1c-15`).
6. **The sweep destroys its own diagnostic.** Resolved by adding a `swept=` token to the marker.
7. **Two cloud-init comments and one ADR-087 reference are name-anchored** on symbols being renamed.
   Added to `## Files to Edit`.
8. **The soak edit's operational stake was overstated.** Corrected in Phase 3.

Two positives the plan did not claim, now banked: deploy **wall-clock shrinks** (two `timeout 45`
Doppler reads × up to 3 tries × 5 s sleeps, on the critical path of every deploy, all of which always
fail), and the Sentry `recovery_stage` **tag vocabulary narrows** to `""` | `transient_exhausted` —
grep-verified to have no consumer other than the `#6400` probe this PR retires.

### Product/UX Gate

Not applicable — tier **NONE**. The mechanical UI-surface override was evaluated against
`## Files to Create` and `## Files to Edit` and did not fire: no path matches `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx` or any term in the shared UI-surface list. Every edited path is
under `apps/web-platform/infra/`, `apps/web-platform/test/`, `scripts/`, `tests/scripts/`,
`.github/workflows/` or `knowledge-base/`. `wg-ui-feature-requires-pen-wireframe` does not apply, so no
`.pen` is owed and `soleur:product:design:ux-design-lead` is not a skipped specialist — it was never in
scope.

**Skipped specialists:** none.

## GDPR / Compliance Gate (Phase 2.7)

**Skipped — no regulated-data surface, and none of the four expansion triggers fire.** The canonical
regex (schemas, migrations, auth flows, API routes, `.sql`) matches nothing in the file list. Checked
individually: (a) no LLM or external API processes operator-session-derived data; (b) the
brand-survival threshold is `none`, not `single-user incident`; (c) no new cron or workflow reads
`knowledge-base/project/learnings/` or `knowledge-base/project/specs/`; (d) no new artifact-distribution
surface. The one credential-adjacent fact cuts the safe way: the change **removes** a revoked bearer
token from the deploy docker config (one at-rest file, swept on every deploy) and from every
outbound deploy request. *(Corrected at implementation: an earlier draft said “two at-rest
files”. The home config cannot be written from `webhook.service` — see the scope correction —
so it is observed by the 1b marker and cleared under 1d, not here.)*

## Architecture Decision (ADR/C4)

Phase 2.10 fires: this plan changes a substrate/trust-boundary topology (which registries a production
host may read from) and deviates from sequencing an accepted ADR declares. The records below are
**deliverables of this plan**, not follow-ups.

### ADR — a three-part amendment, no new ordinal

Each item is a divergence from, or a completion of, an existing decision, so each is an amendment in
place rather than a new ADR (Phase 2.10: *"divergence from an existing one → amend that ADR's
`## Decision` + add to its `## Alternatives Considered`"*). A fourth ADR would fragment a record
ADR-096 and ADR-169 already jointly own. This also removes any ordinal-collision exposure during the
pipeline; the next free ordinal on `origin/main` is **238** should `plan-review` insist on a standalone
ADR.

**1. `ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` (status `Adopting`) — amend
`## Status`, `## Consequences` and `## Alternatives Considered`.**

- **Split task 5.3 into 5.3a and 5.3b.** 5.3a is the `ci-deploy.sh` pull-site branch, landing here on
  the #8036 1c track. 5.3b is everything else ADR-096 files under 5.3–5.5: the two `cloud-init.yml`
  fresh-boot branches (`app_ghcr_fallback`, `inngest_ghcr_fallback`), GHCR push, egress and the PAT
  revoke. 5.3b remains soak-gated and untouched.
- **State the authorization precisely, and do not paper over the FAIL.** The amendment must say: the
  soak's *"Backfilled verdict: FAIL, six fallbacks"* **stands**, 5.3a does **not** consume it, and 5.3a
  is soak-independent because the branch it deletes has no reachable success arm — a revoked PAT against
  a private package (measured anonymous-mint `UNAUTHORIZED` for both app packages, with a public-package
  control returning a token), so deleting it cannot change the fleet exposure the soak measures. Add the
  "wait for the soak" row to `## Alternatives Considered` with that reasoning, so a later reader can
  audit the judgement rather than infer impatience.
- **Cross-reference, do not restate.** ADR-096's own 2026-09-22 amendment already records what the FAIL
  is about (two `zot-gate-degraded`, three `app_ghcr_served`, one `inngest_ghcr_fallback` / #8539), that
  `stage:"app_zot"` has 0 events, and that clause (f)'s `web-zot-consumer-probe.sh` must not be retired
  — all of which bear on 5.3b and none on 5.3a. Point at it. Re-affirming an unchanged clause is a
  no-op edit a future reader must diff to discover changed nothing. *(Trimmed at plan review.)*

**2. `ADR-087-cosign-deploy-verify-host-net-ephemeral-verifier-over-private-ghcr.md` — amend
`## Decision`.** Scoped in response to domain review. Its credential clause still reads *"the mounted
config must carry an **inline** `auths."ghcr.io".auth` base64 entry, not a `credsStore`/`credHelpers`
indirection"*, and `ci-deploy.sh`'s own header restates it. The sweep makes that permanently false: the
mounted config will carry a **zot** inline entry and no `ghcr.io` entry at all. The ADR's header already
anticipates the flip (*"'GHCR' in this ADR becomes the zot endpoint and the mounted docker-config carries
the zot … instead of a GHCR PAT"*) — move it from a forward-looking note into the Decision body. Keep the
**inline-not-`credHelpers`** requirement verbatim: the distroless verifier still has no credential
helper, so the constraint is unchanged and now binds on the zot entry. One further note: its
2026-09-21 amendment covers the *verifier-image* pull (1a's anonymous config), **not** the `.sig`-fetch
content contract — do not read the first as having already handled the second. Its §"A per-deploy
dependency on public ghcr.io" is unaffected and is independently re-confirmed by this plan's
anonymous-mint control row.

**3. `ADR-169-what-authorizes-destroying-the-sole-pull-path.md` — one line under Named residual 3.**
That residual reads *"The `ghcr-fallback` emitter and its Sentry rule remain dark … Tracked
separately."* Record that the emitter is now **removed rather than dark**, that the rule was narrowed to
its four live signals, and that #7295 is the tracker this closes. **No ADR-169 gate is tripped:** its
independence criterion binds on **GHCR-read-from-CI**, which runs on a GitHub runner under
`packages: read` and is untouched, and the ADR already builds on the host edge being dead (*"#7071
retracted the host→GHCR fallback, so while the fresh host boots, nothing pulls"*). Re-state its declared
`IMAGE_VERIFY_MODE=warn` dependency as still-declared — this plan does not flip it.

### C4 views

All three model files were read — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
— not grepped for the feature's own noun. Enumerating what the change moves:

- **External human actors:** none added or removed; the change has no human counterparty.
- **External systems:** `ghcr` (`ghcr = system "GitHub Container Registry" {`) and `zotRegistry` are both
  already modeled and both stay. `views.c4` already includes both in the landscape and context views, so
  no `include` line changes and no new element needs an `#external` tag.
- **Containers / data stores:** none added or removed.
- **Relationships — one deletion, three description corrections:**
  - **DELETE** the `hetzner -> ghcr` edge whose description begins *"DEAD EDGE as of 2026-07-30 (#7071)
    — kept because the CODE PATH still exists, not because it works … **This edge stays DEAD pending
    #8036 1c**"*. The model names this plan by number; the code path it describes ceases to exist.
    Deleting the edge, rather than re-describing it, is what makes the model true.
  - **AMEND** `hetzner -> zotRegistry` (*"Pulls app image … zot-primary, dark-launch gated"*): no longer
    "primary" with an arm behind it — the **sole** host-side read path for `ci-deploy.sh`, with
    `ZOT_ACTIVE=0` terminal. "Dark-launch gated" stays accurate as a mechanism description but must stop
    implying a second arm.
  - **NOT amended** — the sibling `hetzner -> ghcr` edge (*"LIVE by design … anonymous public pull of
    the @sha256-pinned cosign VERIFIER IMAGE"*). Its mechanism is untouched by this diff; reconciling
    its "CODE-DECLARED until…" caveat with #8037's closure is that issue's bookkeeping, noticed in
    passing. **Cut at plan review** — P6 covers the edge the code no longer has, not an edge whose
    caveat aged.
  - **AMEND the `//` comment** that reads *"retiring the interim read:packages PAT; hosts read
    GHCR_READ_TOKEN unchanged."* — false for `ci-deploy.sh` after this change, still true for the
    cloud-init boot path. Qualify, do not delete. **It is a comment, not an edge**: an earlier draft
    attributed it to the `inngest -> doppler` relationship, whose actual description is
    *"Writes GHCR_READ_TOKEN (1h scoped, prd_ghcr) (ADR-088)"*. An implementer following that
    instruction literally would edit the wrong element or find nothing.
- **Unchanged and explicitly checked:** `github -> ghcr` (the ADR-169 READ path), `github -> zotRegistry`
  (RESTORE + INVENTORY), `github -> ghcr` (config-bundle publish), `inngest -> ghcr` (the config-refresh
  bundle pull — a **separate host-side GHCR read, on a different host, via a different mechanism**, which
  is why every claim in this plan is scoped to `ci-deploy.sh` and never to "the fleet"),
  `doppler -> zotRegistry`, `tunnel -> zotRegistry`.
- **Derived cardinalities:** `model.c4` embeds counts in some edge prose, which
  `plugins/soleur/test/c4-count-parity.test.sh` gates as required context. No count in the edges touched
  here is derived from a registry-edge population — but that conclusion is **backed by a green run of
  that test, not by reasoning about actors** (AC-Q6).

Gates to run after the edit: `plugins/soleur/test/c4-count-parity.test.sh` (assert the entry count
moved, not merely that it exits 0), `apps/web-platform/test/c4-code-syntax.test.ts`,
`apps/web-platform/test/c4-render.test.ts`.

### Sequencing

Nothing here is true only after a later slice; every amendment describes the state this PR lands, so no
`status: adopting` staging is needed. ADR-096's own status stays `Adopting` — this plan completes 5.3a,
not the ADR.

## Infrastructure (IaC) — Phase 2.8

The detection scan fires on the `.tf` edits, so the section is emitted. **No new infrastructure is
introduced** — no server, service, systemd unit, cron, vendor account, DNS record, TLS cert, secret or
firewall rule. The plan contains zero SSH steps, zero `systemctl` steps, zero Doppler secret-write
steps, zero `terraform import` and zero vendor-dashboard steps.

### Terraform changes

- `apps/web-platform/infra/sentry/issue-alerts.tf` — remove one `action_filters[].conditions[]` entry
  from `resource "sentry_alert" "zot_mirror_fallback_rate"`. No new resource, provider, version pin or
  variable.
- `apps/web-platform/infra/variables.tf` — a **description-only** edit to `variable "ghcr_read_token"`
  (drop the now-false `ci-deploy.sh` consumer clause). No default introduced
  (`hr-tf-variable-no-operator-mint-default`); no type or sensitivity change.
- `apps/web-platform/infra/ghcr-read-credential.tf`, `ghcr-minter-doppler-token.tf` and `server.tf` are
  **untouched** — the secret is still consumed by cloud-init, so retiring those resources belongs to 1d.
- Sensitive variables: none added. `var.ghcr_read_user` / `var.ghcr_read_token` keep their existing
  Doppler `soleur/prd` sourcing.

### Apply path

**(b) existing delivery mechanisms, no new one.** Two independent, already-provisioned paths:

- `ci-deploy.sh` reaches running hosts through `terraform_data.deploy_pipeline_fix`
  (`apps/web-platform/infra/server.tf`), whose `triggers_replace` hashes
  `file("${path.module}/ci-deploy.sh")` and which `server.tf` documents as *"the sole path for pushing
  ci-deploy.sh … to production"*. Delivery is the `.github/workflows/apply-deploy-pipeline-fix.yml`
  auto-apply, which already carries a plan-derived freshness gate that fails closed.
- The Sentry rule reaches prod through the existing `.github/workflows/apply-web-platform-infra.yml`
  push-apply.

Expected downtime: **none**. Blast radius: the deploy mechanism only; a failure keeps the previously
verified container serving. No server `-replace`, no volume touched.

### Distinctness / drift safeguards

- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`'s `TRIGGER_FILES` and the ship skill's
  `DEPLOY_PIPELINE_FIX_TRIGGERS` stay in lockstep with `triggers_replace`. `ci-deploy.sh` is **already**
  a registered trigger, so no 3-way update is needed — but the gate must be **run**, because it is what
  proves the edit will be delivered rather than sitting in git.
- `server.tf`'s standing warning applies and is honored deliberately: *"Both paths must stay in sync — a
  change here without updating cloud-init.yml means new servers provisioned from scratch will miss the
  change."* After 1c a fresh host's cloud-init still contains GHCR login logic `ci-deploy.sh` no longer
  has. That divergence is **intentional and recorded** — it is the substance of 1d, not an oversight —
  and the two dangling `ghcr_prelude_and_login` citations in `cloud-init.yml` are corrected here.
- **`lifecycle` posture:** do not copy `sentry_alert.sandbox_startup_failure`'s `ignore_changes = all`
  when editing `zot_mirror_fallback_rate`. The latter's `lifecycle` is `ignore_changes = [environment]`,
  which is what makes this `action_filters` edit live rather than inert.
- No secret value moves, so nothing new lands in `terraform.tfstate`.

### Vendor-tier reality check

None. No provider resource is created; the edited Sentry alert already exists on the current plan tier,
and the close-criterion probe queries the already-provisioned `prd_terraform` Better Stack ClickHouse
connection.

## Files to Edit

Every path below was verified to exist on this branch (`[[ -e ]]`). The tables name **23** distinct edit paths plus 2 creates; an earlier draft's "30/30" counted the verification sweep, not the edit list.

### The change itself

| File | Edit |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | Delete `refetch_ghcr_and_relogin()`. **Split** `ghcr_prelude_and_login()` into `prefetch_deploy_secrets` / `sweep_stale_registry_auth` / `emit_registry_config_marker`; add the deploy-config sweep **before** `_ghcr_cfg_probe`; add a closed-vocabulary `swept=yes\|no\|na` token to the `SOLEUR_DEPLOY_GHCR_CONFIG` marker — `na` for the jq-absent case, matching the `inline\|none\|na` shape every other token on that marker already uses. **Do not also keep a conditional `PRELUDE: swept stale ghcr.io auth` log line**: two emitters for one property means two query shapes for the probe, and an earlier draft had the Observability section grading off the line while the risk table graded off the token. Delete the auth arm of `_ghcr_pull_or_recover()`; rename → `_pull_with_transient_retry()`; add a ref parameter. In `pull_image_with_fallback()`: delete the GHCR fallback branch and the stale `RETIREMENT TRIPWIRE` comment, delete the `ZOT_ACTIVE=0` GHCR tail, route the zot arm through the retry helper. Do NOT rename `GHCR_DOCKER_CONFIG` (the rename was CUT at plan review — no property, 9 sites plus its test, and the ADR clause it needed existed only because of it); fix its header comment instead. **Four ref-correctness fixes surfaced in domain review:** (i) `pull_auth_recovery_event "${IMAGE}:${TAG}" transient_recovered` reads the *global* `IMAGE`, which on the zot arm is still the `ghcr.io/…` ref (reassignment happens only after success) — must take the ref parameter; (ii) both `docker pull "${IMAGE}:${TAG}"` loop positions, same; (iii) `pull_failure_event "${IMAGE}:${TAG}" …` on the `ZOT_ACTIVE=1` both-failed arm already names a GHCR ref for a zot failure — pre-1c ambiguous, post-1c actively false; (iv) **preserve the FR-C1 breadcrumb** `logger … "IMAGE_PULL: zot pull failed for ${zot_ref}:${TAG} reason=…"`, which sits *physically inside* the deleted branch — drop its `— falling back to GHCR` suffix and move it **below** the retry loop so it reports the final attempt's stderr. Its own in-code note records that its absence is what sent the 2026-07-29 (v0.244.1) diagnosis at the tunnel instead of the registry. |
| `apps/web-platform/infra/ci-deploy.test.sh` | Add `T-1c-1` … `T-1c-15`. Delete/rewrite: the `§1A` block, `#6400` AC1/AC2/AC4/AC14, `#6497` T-5B-17 and T-5B-18, `#7095` T-7095-4 and T-6, the `#6525` GHCR-scoped rows (re-point at zot), and the `#8036 1b` marker block (re-point at the post-sweep expectations). **Delete** `HELPER_BODY=$(awk '/^refetch_ghcr_and_relogin\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")` and everything asserting over it — once the function is gone the extraction yields an empty string and every assertion over it is vacuously true. |

### Consumers that fail loudly

| File | Edit |
|---|---|
| `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` | `expect(ciDeploy).toContain("registry_pull_event ghcr-fallback")`, `expect(tf).toContain('value = "ghcr-fallback"')` and the `soakQueryFor("ghcr-fallback")` pin all move to the four surviving signals. Extend to the Guard 2 parity rows. |
| `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` | AC20 clause (3) and the positional `_doppler_get_or_report GHCR_READ_{USER,TOKEN}` assertions inside `CD_PRELUDE_FN="$(awk '/^ghcr_prelude_and_login\(\) \{/{f=1} …)"`. **Keep AC20 clauses (1) and (2)** — the cloud-init bake and its 0600 mode are out of scope and still true. |

### Consumers that go silently vacuous

| File | Edit |
|---|---|
| `scripts/followthroughs/zot-soak-6122.sh` | Drop `FAIL_QUERIES[rolling]`; move the runtime floor `if (( ${#FAIL_QUERIES[@]} != 5 ))` to `!= 4` **in the same edit**; update the header's five-signal prose and its "COVERED" list. |
| `scripts/followthroughs/zot-soak-6122.test.sh` | The **4** fixture lines spelling `ghcr-fallback=` (e.g. `HEALTHY="…;ghcr-fallback=0;…"` and its sibling rows); the floor row asserts **4**. |
| `tests/scripts/test-sentry-alert-live-fidelity.sh` | Its comment pins conditions **by index** (*"five action-filter conditions; `[0]` is registry=ghcr-fallback and `[2]` is …"*). Removing `[0]` shifts everything — rewrite as a key lookup, not a position. |

### Narrow, do not retire

| File | Edit |
|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` | Delete the one `{ tagged_event = { key = "registry", match = "eq", value = "ghcr-fallback" } }` condition from `resource "sentry_alert" "zot_mirror_fallback_rate"`; keep the other four. Do **not** touch its `lifecycle { ignore_changes = [environment] }`. |
| `apps/web-platform/infra/sentry/alert-reference.json` | Regenerate the captured live-rule reference. |
| `scripts/sentry-alert-live-fidelity.sh` | Re-pin the committed capture against the live rule. **This cannot happen inside the PR that performs the apply** — merging is what fires `apply-sentry-infra.yml`, so the live side only moves after the merge. In the single-PR shape it is therefore a **post-merge step of this PR's own follow-through**, not a pre-merge edit; the two-PR split (`decision-challenges.md` DC-1) resolves it differently, by landing the re-pin at the head of PR-B. |

### Operator-facing text that becomes false

| File | Edit |
|---|---|
| `.github/workflows/scheduled-zot-restart-loop.yml` | The remediation step-summary instructs `scripts/betterstack-query.sh --since 24h --grep ghcr-fallback --grep local-cache` before firing a registry replace. The first grep becomes permanently empty; `local-cache` stays live. Rewrite the command and the surrounding "doubly-degraded pull path" rationale. |
| `apps/web-platform/infra/variables.tf` | `variable "ghcr_read_token"`'s description — drop the `ci-deploy.sh (host pull + cosign .sig fetch auth)` clause and **name the divergence**: *"cloud-init fresh-boot login only; the deploy-path consumer was retired in #8036 1c, the boot path is tracked in #&lt;1d&gt;."* The next engineer who greps `GHCR_READ_TOKEN` then lands on the answer instead of re-deriving why two host postures disagree. |
| `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` | **One comment only** — *"Mirrors ci-deploy.sh ghcr_prelude_and_login."* It was on the do-not-touch list while AC-Q7 demanded it be zero; plan review caught the contradiction. Its greps target `CI="$DIR/cloud-init.yml"`, not `ci-deploy.sh`, so its assertions are otherwise untouched. |
| `apps/web-platform/infra/cloud-init.yml` | **Comments only** (surfaced in domain review): two name-anchored citations of `ghcr_prelude_and_login` — *"so ci-deploy.sh's ghcr_prelude_and_login (the"* and *"(mirrors ci-deploy.sh ghcr_prelude_and_login)"*. Its behavior is out of scope; its citations are not. |
| `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` | The five-signal list and the *"the only no-SSH page gating the irreversible 5.5 PAT revoke"* claim. |
| `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` | Drop the dead `PRELUDE: docker login ghcr\.io ok` disjunct from its per-`_MACHINE_ID` positive-OK requirement, leaving the `ZOT_GATE: active .* docker login .* ok` leg. Note in-file that the probe is now one-legged. |
| `scripts/followthroughs/zot-login-gate-names-failure-6497.sh` | Update its documented 3-state taxonomy, which names a `ghcr → PRELUDE: … skipping …` state that becomes unreachable. Its `ANY_LINES` non-vacuity check still passes on `ZOT_GATE` rows, so it does not force TRANSIENT. |
| `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` | **Retire** — it soaks the recovery machinery this PR deletes; its body is the base for the new probe. Remove the directive from its tracker and comment there. |
| `knowledge-base/engineering/operations/post-mortems/2026-07-14-web-platform-deploy-ghcr-pull-denial-outage-postmortem.md` | Cites `deploy-ghcr-pull-recovery-6400.sh` **by path** as the soak of record; retiring the script leaves the citation dangling. One line noting the retirement — do not rewrite the narrative. |
| `scripts/registry-replace-preflight.sh` | **One comment only** — a name-anchored citation of `_ghcr_pull_or_recover` that goes stale on the rename. Its P2 logic is advisory-only and unchanged; the `MUST NEVER BECOME A GATE` banner stays. |

### Architecture record

| File | Edit |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | Split 5.3 into 5.3a / 5.3b; record the FAIL verdict as standing and un-consumed; add the "wait for the soak" alternative row. |
| `knowledge-base/engineering/architecture/decisions/ADR-087-cosign-deploy-verify-host-net-ephemeral-verifier-over-private-ghcr.md` | Move the header's forward-looking zot note into `## Decision`; keep the inline-not-`credHelpers` requirement verbatim; fix the `GHCR_DOCKER_CONFIG` name reference. |
| `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` | One line under Named residual 3: dark → deleted; rule narrowed; #7295 closed. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Delete the `hetzner -> ghcr` "DEAD EDGE … pending #8036 1c" relationship; amend three descriptions (`hetzner -> zotRegistry`, the cosign-verifier `hetzner -> ghcr`, `inngest -> doppler`). |

**Explicitly NOT edited** (verified safe, recorded so review does not re-litigate):
`scripts/registry-replace-preflight.sh` (P2 carries a *"MUST NEVER BECOME A GATE"* banner);
`scripts/registry-pull-path-health.sh` (the D10 gate already dropped this operand);
`.github/workflows/apply-web-platform-infra.yml` (non-executing prose that 1c makes retrospectively
accurate); its `GHCR_READ_USER` assertions (they target `cloud-init.yml`, not `ci-deploy.sh`);
`apps/web-platform/infra/ghcr-read-credential.tf`, `ghcr-minter-doppler-token.tf`,
`apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts`, `server.tf`,
`apps/web-platform/infra/cloud-init-inngest.yml`, `apps/web-platform/infra/soleur-host-bootstrap.sh`
(all 1d scope — cloud-init still consumes the secret).

## Files to Create

| File | Purpose |
|---|---|
| `scripts/followthroughs/ghcr-read-retired-8036.sh` | The close-criterion probe. Per-`_MACHINE_ID`, field-isolated on a decoded `SYSLOG_IDENTIFIER == "ci-deploy"` (`fromjson`, never substring), `earliest=` pinned strictly after the apply. Grades the **conjunction**: latest marker reads `deploy_ghcr_auth=none` **and** a `swept=` token, **and** zero `stage=relogin_failed`. Exit 0 PASS / 1 FAIL / other TRANSIENT, per the sweeper contract. Supports `--explain` (no network; prints the SQL, the graded literals and `PROBE-READY`). Modelled on `scripts/followthroughs/cosign-verify-live-8037.sh`. |
| `scripts/followthroughs/ghcr-read-retired-8036.test.sh` | Guard 3's eight mutation rows against stubbed `curl`/`gh`, mirroring `cosign-verify-live-8037.test.sh`'s harness shape. |

## Acceptance Criteria

### Functional Requirements

- [x] **AC-F1** `apps/web-platform/infra/ci-deploy.sh` contains **zero** `_docker_login_capture ghcr.io` call sites and no `refetch_ghcr_and_relogin` definition. Measured baseline on this branch: **2** and **1** respectively (plus **1** `registry_pull_event ghcr-fallback` site and **9** `GHCR_DOCKER_CONFIG` references), so the guard is proven by driving those to zero, not by a grep that was already zero. *(impl: `ci-deploy.sh` › `prefetch_deploy_secrets()` / `sweep_stale_registry_auth()` / `emit_registry_config_marker()`; test: `T-1c-1`)*
- [x] **AC-F2** A deploy over `$GHCR_DOCKER_CONFIG` carrying an inline `ghcr.io` auth leaves no `ghcr.io` key, and leaves the co-resident zot auths entry **equal as a JSON value** (`jq -S '.auths'` compare). *(Deploy config only — the home docker config under `~/.docker/` is unreachable under `ProtectHome=read-only`; see the scope correction in `## Technical Approach`.)* *(test: `T-1c-2`)*
- [x] **AC-F3** A second deploy over already-clean configs performs no write (mtime unchanged). *(test: `T-1c-2`, which absorbed the former `T-1c-3`)*
- [x] **AC-F4** The `SOLEUR_DEPLOY_GHCR_CONFIG` marker reads `deploy_ghcr_auth=none` after the sweep and carries a `swept=yes\|no\|na` token distinguishing "arrived clean" from "arrived dirty and was swept". *(impl: `ci-deploy.sh` › `_ghcr_cfg_probe()` + the marker emit; test: `T-1c-4`)*
- [x] **AC-F5** The `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY` prefetch still runs and still precedes `zot_gate_and_login`. *(impl: `ci-deploy.sh` › `prefetch_deploy_secrets()`; test: `T-1c-5`)*
- [x] **AC-F6** `ZOT_ACTIVE=0` with no local-cache candidate ends in `pull_failure_event` → `final_write_state 1 image_pull_failed`, issues **zero** `docker pull` against any `ghcr.io/` ref, and leaves the previous container running. *(test: `T-1c-6`; the local-cache tier's own three arms are covered by the pre-existing `#6512` block, cited not duplicated)*
- [x] **AC-F7** **(P7)** The bounded transient retry fires on the **zot** arm with the `PULL_TRANSIENT_RETRY_SLEEPS` schedule, and its empty-value break-glass disable lever still works. *(impl: `ci-deploy.sh` › `_pull_with_transient_retry()`; test: `T-1c-7`)*
- [x] **AC-F8** Every pull-path emitter names the ref actually pulled: `docker pull`, `pull_auth_recovery_event` and `pull_failure_event` all take the ref parameter, never the global `IMAGE`. *(test: `T-1c-13`)*
- [x] **AC-F9** The FR-C1 zot-stderr breadcrumb survives the branch deletion, drops its `— falling back to GHCR` suffix, and reports the **final** attempt's stderr. *(test: `T-1c-14`)*
- [ ] **AC-F10** *(cut at plan review.)* It asserted that a new-version deploy whose zot pull fails must not serve the running image. True and important — and already asserted by the pre-existing `#6512` row whose PASS string is *"new-version deploy (running image is an older version) → tier does NOT fire, hard image_pull_failed (no stale-bits rollback)"*. `_try_local_cache_reload` is not edited here; the existing case is cited in the PR body instead.
- [x] **AC-F11** `scripts/followthroughs/ghcr-read-retired-8036.sh --explain` prints `PROBE-READY` and makes zero network calls.
- [ ] **AC-F12** #8036 carries the `follow-through` label (verified to exist: `gh label list` → `follow-through — External dependency awaiting verification`) and a `<!-- soleur:followthrough script=scripts/followthroughs/ghcr-read-retired-8036.sh earliest=<apply+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` directive. **No new secret wiring is required** — all three are already wired in `.github/workflows/scheduled-followthrough-sweeper.yml` and already consumed by sibling probes (`bwrap-probe-selfreport-8016.sh`, `betterstack-roundtrip-latency-7855.sh`, `anthropic-admin-key-6297.sh`), so the workflow edit is the directive only.

### Non-Functional Requirements

- [x] **AC-N1** The always-failing Doppler GHCR reads leave the deploy's critical path. Asserted **deterministically over the code**, not over a stopwatch: with the suite's `doppler` process mock in trace mode, a deploy issues **zero** `secrets get GHCR_READ_USER` and **zero** `secrets get GHCR_READ_TOKEN` calls (baseline on this branch: up to 3 + 3 with 5 s sleeps between, on every deploy, all failing). *(test: `T-1c-16`)*
  > **Standing panel check (`cq-ac-must-not-depend-on-concurrent-sessions`) applied.** The original wording was *"deploy wall-clock does not regress"* — an ambient-timing assertion a busy host, a slow network or a concurrent build could flip with no line of the diff changing. It measured the machine, not the change. Rewritten as a call-count assertion over the existing process mock. Every other AC was scanned for the same shape and none carries it.
- [x] **AC-N2** No credential value, username, config content or helper name reaches `logger`, Sentry or any sink — journald ships unscrubbed to Better Stack. The sweep logs a fixed string only.
- [ ] **AC-N3** *(cut at plan review.)* It asserted the swept files keep mode 0600 / `deploy:deploy`,
  justified by a `chmod --reference` propagating a wrong mode from the fail-soft `mkdir -p` path. Two
  reviewers independently falsified it: `--reference` propagates the file's **own** mode, so the
  scenario is a no-op by construction — and once the sweep body became `docker logout`, which writes the
  file with docker's own mode, there is no `chmod` in the change at all. One mode assertion rides inside
  `T-1c-2`'s fixture.
- [x] **AC-N4** No `ssh`, no `systemctl`, no Doppler secret-write, no vendor-dashboard and no operator step appears anywhere in the shipped diff or the PR body (`hr-never-label-any-step-as-manual-without`, `hr-ship-message-no-operator-checklist`).
- [x] **AC-N5** NFR register assessment run against `knowledge-base/engineering/architecture/nfr-register.md`.
  **Verdict: no register row moves, and the register does not cover the property this change
  touches.** Searched for a redundancy / availability / failover / pull-path NFR; there is none.
  The closest rows are NFR-018 (Canary Upgrade, `Not Implemented`, evidence *"single-instance
  deployment; rollback via previous Docker tag"*) and NFR-032 (Automatic Rollback on KPI Alert),
  neither of which mentions the registry, and NFR-041's `Container Registry (zot) store volume`
  row, which is about encryption at rest and is untouched. The single-pull-path property this
  change consummates is governed by **ADR-169**, which is amended in this PR, not by the
  register. Recorded as an assessment with a verdict rather than as an edit: adding a row here
  would be inventing an NFR the register has never carried, inside a PR that is not about the
  register's coverage.

### Quality Gates

- [x] **AC-Q1** `bash apps/web-platform/infra/ci-deploy.test.sh` green, with `T-1c-1` … `T-1c-15` present and each proven RED on `origin/main`'s script before the deletion (constitution: *"proven by a RED, never a green"*).
- [x] **AC-Q2** `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` green, with AC20 clauses (1) and (2) still asserting the cloud-init bake.
- [x] **AC-Q3** `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`, `scripts/followthroughs/zot-soak-6122.test.sh` and `tests/scripts/test-sentry-alert-live-fidelity.sh` all green on the four-signal set.
- [ ] **AC-Q4** *(cut at plan review — no window exists to protect.)* An earlier form ordered the soak
  floor move ahead of the emitter deletion "so no window exists in which the soak counts an operand
  nothing can emit". But the operand has been structurally dark since #7071 — it emits nothing **today** —
  and ADR-096's 2026-09-22 amendment records the soak is not enrolled in the sweeper. The ordering
  protected against a state change that is not one. Same commit; the parity is enforced by Guard 2.
- [x] **AC-Q5** `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` is **run** *(TypeScript — use the repo's TS runner, not `bash`)* (not merely assumed) — it is what proves the `ci-deploy.sh` edit will be delivered rather than sit in git.
- [x] **AC-Q6** `plugins/soleur/test/c4-count-parity.test.sh` green **and its entry count observed to have moved** (not merely exit 0); `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` green.
- [x] **AC-Q7** Residual sweep over **executable paths only** — `apps/`, `scripts/`, `.github/`, `tests/`:
  `rg -n 'refetch_ghcr_and_relogin|ghcr_prelude_and_login|_ghcr_pull_or_recover|registry_pull_event ghcr-fallback' apps scripts .github tests`
  returns hits only in files this PR edits.
  > **Rescoped at plan review, from a measured failure.** The earlier form claimed residual-zero across
  > the whole repo outside `plans`/`specs`/`archive`. Run as written it hit **14 files**, including two
  > on this plan's own "Explicitly NOT edited" list (`apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh`,
  > `scripts/registry-replace-preflight.sh`) plus `ADR-088`, `ADR-087`, `ADR-096`, `ADR-169`, two
  > post-mortems and three learnings. Those record a moment in time and must not be rewritten — which is
  > this plan's own carve-out argument, applied to a class it had not enumerated. The old form was also
  > simultaneously too narrow: it omitted `_ghcr_pull_or_recover`, so it policed two renames and missed
  > one. **Off-code citations of a renamed symbol stay put**; the sweep governs code, not history.
- [x] **AC-Q8** The three ADR amendments and the `model.c4` edit are in **this** PR, not a follow-up (the rule migrated out of `AGENTS.rules.md` in PR #8034 and is now enforced at `plan` Phase 2.10 — cite the phase, not an `AGENTS.md` id, which no longer resolves).
- [ ] **AC-Q9** **The PR body's FIRST line answers "does merging this alone mutate production?" — and the answer is YES.** `.github/workflows/apply-deploy-pipeline-fix.yml` is `on: push: branches: [main]` with `paths:` listing `apps/web-platform/infra/ci-deploy.sh`, and `apply-web-platform-infra.yml` is `on: push: branches: [main]` with `paths: apps/web-platform/infra/**`. Both fire on merge, so the merge click **is** the per-command production authorization for the script push and the Sentry-rule apply — there is no separate operator dispatch (`hr-menu-option-ack-not-prod-write-auth`).
- [ ] **AC-Q10** `Closes #7295` in the PR body (not the title). **`Ref #8036`, never `Closes #8036`** — #8036's close criterion is graded post-apply by the follow-through probe, so `Closes` would auto-close it at merge, before the criterion can be measured, producing a false-resolved state. #6565 and #6630 receive narrowing comments and stay open. #6400's tracker receives the probe-retirement comment. The 1d follow-up issue is filed with milestone `Phase 4: Validate + Scale`.
- [x] **AC-Q11** `scripts/lint-guard-contract.py` passes over this plan's `## Guard Contract`; `scripts/lint-infra-no-human-steps.py` passes over the plan file.
- [x] **AC-Q12** The new follow-through script passes **its own family's gates**, which an earlier draft omitted: `scripts/followthrough-exec-bit.test.sh` (every `scripts/followthroughs/*.sh` committed `100755`), `scripts/followthrough-predicate-parity.test.sh`, `scripts/lint-followthrough-varq-ban.test.sh`, `plugins/soleur/test/ship-followthrough-directive.test.sh`, `plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts`.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- **T-1c-1** Given the committed `ci-deploy.sh`, when the residual scan runs, then zero `_docker_login_capture ghcr.io` call sites and no `refetch_ghcr_and_relogin` definition are found. *(RED today — measured baseline: `_docker_login_capture ghcr.io` = **2** call sites, `refetch_ghcr_and_relogin` definitions = **1**.)*
- **T-1c-2** Given a deploy config carrying an inline `ghcr.io` auth plus a zot auths entry, and a home config carrying one too, when one deploy runs, then the DEPLOY config's `ghcr.io` key is gone, the HOME config is byte-identical (the scope correction's testable form), the zot entry is **equal as a JSON value** (`jq -S` compare — `docker logout` re-serializes the document, so a byte compare is written to fail), each file is still mode 0600 owned by the deploy user, and a **second** deploy over the now-clean configs changes no mtime. *(Absorbs the former `T-1c-3` — the defect it caught alone was one redundant config write — and the former `AC-N3`'s single useful assertion.)*
- **T-1c-4** Given the sweep has run, when the marker is emitted, then it reads `deploy_ghcr_auth=none swept=yes` on the first deploy and `deploy_ghcr_auth=none swept=no` on the second. `home_ghcr_auth` is reported but **not graded** — it is unreachable under `ProtectHome=read-only`.
- **T-1c-5** Given a deploy, when the emitted order is inspected, then the SENTRY_* prefetch precedes the first `ZOT_GATE` line.
- **T-1c-6** Given `ZOT_ACTIVE=0` and no local-cache candidate, when the pull runs, then zero `docker pull` targets a `ghcr.io/` ref and the deploy ends `image_pull_failed` with the old container running.
- **T-1c-7** Given a zot pull that fails transiently twice then succeeds, when `PULL_TRANSIENT_RETRY_SLEEPS="0 0"`, then exactly three pulls occur and `pull_auth_recovery_event … transient_recovered` fires **naming the zot ref**.
- **T-1c-8** Given configs at mode 0600 owned by the deploy user, when the sweep rewrites them, then mode and ownership are **0600 / deploy:deploy** afterwards (asserted explicitly, not "unchanged").
- **T-1c-9** Given `_sweep_ghcr_auth` stubbed to a no-op, when the suite runs, then `T-1c-2` and `T-1c-4` are RED. *(harness row)*
- **T-1c-10** Given a zot transient miss, when the retry loop exhausts, then the FR-C1 breadcrumb reports the **final** attempt's stderr and contains no `falling back to GHCR`.
- **T-1c-11** Given a same-version `web` reload whose zot pull exhausts, when `_try_local_cache_reload` finds the running image tagged `:$TAG`, then the deploy proceeds and emits `registry=local-cache` plus the `reused_local_reload` cosign breadcrumb.
- **T-1c-12** Given zot exhausted and no local-cache candidate, when the pull returns, then `pull_failure_event` fires, `final_write_state 1 image_pull_failed` is written, and the previous container is still running.
- **T-1c-13** Given a zot pull on the `ZOT_ACTIVE=1` arm, when any of `docker pull`, `pull_auth_recovery_event` or `pull_failure_event` emits, then each names the **zot** ref and none names a `ghcr.io/` ref.
- **T-1c-14** Given a zot pull failure, when the breadcrumb is emitted, then it is present, single-line (`tr '\n' '|'`), ≤400 bytes, and carries the reason.
- **T-1c-16** Given a deploy with the `doppler` process mock in trace mode, when the prelude runs, then the trace contains zero `secrets get GHCR_READ_USER` and zero `secrets get GHCR_READ_TOKEN` invocations, and still contains the three `SENTRY_*` reads.
- **T-1c-15** Given a **new-version** deploy (`$TAG` not among the running image's RepoTags) whose zot pull fails, when `_try_local_cache_reload` runs, then it returns 1 and the deploy hard-fails rather than serving stale bits.

### Regression Tests

- Given `#7095`'s failure shape (an empty Doppler read), when `prefetch_deploy_secrets` runs, then the baked/preset SENTRY_* values are **not** overwritten with empty strings and the host stays Sentry-capable.
- Given `#6512`'s rescue shape, when both the zot pull and the retry fail on a same-version reload, then the local-cache tier still rescues (it is now the last tier).
- Given `#6565`'s EROFS shape, when a login persists, then it writes under `$DEPLOY_DOCKER_CONFIG_DIR` and never `${HOME}/.docker`.

### Edge Cases

- A config file with an `auths` object but no `ghcr.io` key → untouched, no log line.
- A config file with no `auths` key at all → untouched.
- A config file that is unparseable JSON → untouched, `deploy_cfg=unparseable` on the marker, no abort under `set -euo pipefail`.
- `jq` absent from `PATH` → sweep is a no-op, every marker token is `na`, deploy proceeds.
- `${HOME}` unset → the home PROBE no-ops rather than reading `/.docker/config.json`. There is no home sweep to no-op; see the scope correction.
- The config file is read-only → the sweep declines rather than aborting the deploy.
- The Better Stack query returns rows whose `raw` payload quotes this tracker's body containing
  `stage=relogin_failed`, with `SYSLOG_IDENTIFIER` ≠ `ci-deploy` → the probe ignores them.

### Integration Verification (for `soleur:qa`)

- **Probe self-description:** `bash scripts/followthroughs/ghcr-read-retired-8036.sh --explain` expects `PROBE-READY`.
- **Live grade (post-apply, credentialed):** `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/ghcr-read-retired-8036.sh` expects exit `0`.
- **Fleet marker read:** `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_DEPLOY_GHCR_CONFIG --limit 20` expects `deploy_ghcr_auth=none`.
- **The operator's stated criterion:** `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep relogin_failed --limit 20` expects zero rows.
- **Cleanup:** none — every command is read-only.

## Success Metrics

| Metric | Baseline (measured) | Target |
|---|---|---|
| `stage=relogin_failed` per 168 h, fleet-wide | 89 | **0** |
| Hosts whose latest marker reads `deploy_ghcr_auth=inline` | all | **0** |
| Deploy critical-path time spent on always-failing Doppler GHCR reads | up to 2 × (3 × 45 s timeout + 2 × 5 s sleep) per deploy | 0 |
| `registry=ghcr-fallback` Sentry events | 0 (structurally dark) | 0 (structurally absent) |
| Signals watched by `zot_mirror_fallback_rate` that can actually emit | 4 of 5 | **4 of 4** |

## Dependencies & Prerequisites

- **#8539 is OPEN** — *"inngest-host-replace can boot before the private NIC exists; zot pull times out and the scheduler never starts."* ADR-096's 2026-09-22 amendment cites it as a live reason the soak reads FAIL. It bears on **5.3b** (the cloud-init fresh-boot branches), not on 5.3a, because `ci-deploy.sh` runs on an already-booted host. Re-read it before merge and confirm that conclusion still holds; if it does not, the 1d deferral needs re-scoping, not this PR.
- `terraform_data.deploy_pipeline_fix` must re-fire for the change to reach a host. No action needed — the content hash moves automatically — but the close-criterion probe's `earliest=` must be pinned strictly after the `apply-deploy-pipeline-fix.yml` run completes, or the probe grades pre-apply deploys.
- The Better Stack `prd_terraform` ClickHouse connection and the follow-through sweeper's secret wiring must be in place for the probe. Both already exist.

## Risk Analysis & Mitigation

| Risk | Rating | Mitigation |
|---|---|---|
| zot becomes the sole `ci-deploy.sh` read path | **Low** | Verified: the GHCR path has no reachable success arm today (revoked PAT + private package, measured). The outcome is unchanged in substance; 1c removes the 401 detour. |
| Losing the #6525 transient retry | **High if 2(b) is not done as written**, Low as planned | Keep and re-point the helper; `T-1c-7`, `T-1c-10` prove it fires on the zot arm. |
| Re-point ref bugs — emitters naming a GHCR ref for a zot pull | **Medium** (silent wrong-ref telemetry) | Four named fixes in `## Files to Edit`; `T-1c-13`. |
| FR-C1 zot-stderr breadcrumb deleted with its branch | **Medium-high** (repeats a named prior misdiagnosis — 2026-07-29, v0.244.1) | Explicit preserve-and-move instruction; `T-1c-10`, `T-1c-14`. |
| `_try_local_cache_reload` is now the last tier | **Medium** | `T-1c-15` proves a new-version deploy falls through rather than serving stale bits. |
| The sweep damages the zot auths entry → silent `verify_failed` under `IMAGE_VERIFY_MODE=warn` | **Medium** | Registry-native `docker logout ghcr.io`, key-scoped by construction, never a rewrite; `T-1c-2` asserts the zot entry equal as a JSON value (not byte-identical — the writer re-serializes); `cosign-verify-live-8037.sh` grades the live outcome per host. |
| The sweep hides its own drift signal | Low | The marker gains `swept=yes\|no\|na`, so "arrived clean" and "arrived dirty and was swept" stay distinguishable off-box without relying on a conditional log line. |
| Proceeding while the ADR-096 soak verdict is FAIL | **Medium (record risk, not operational)** | Do not paper over it. The ADR-096 amendment states the FAIL stands, that 5.3a does not consume it, and why 5.3a is soak-independent. |
| A host stops deploying and the pure-absence criterion reads green | **Medium** | The close criterion is a conjunction with a positive control (Guard 3, `T` rows 1–2 of its matrix). |
| Commit-ordering window where the soak counts an unemittable operand | Low | AC-Q4. |

**Rollback.** Revert the PR. `terraform_data.deploy_pipeline_fix` re-fires on the restored content hash
and pushes the previous `ci-deploy.sh` to every host; the Sentry rule's fifth condition returns on the
next infra apply. No state migration is involved, but **the sweep is one-way and the revert does not undo it** — an
earlier draft of this paragraph said "nothing is destroyed" one sentence before naming the
irreversible act, which is the kind of self-contradiction a 3am reader resolves in the wrong
direction. Concretely: the swept `ghcr.io` entries do NOT come back. A restored pre-1c prelude
re-runs `docker login ghcr.io` with a PAT revoked since 2026-07-29, and a failed login writes no
`auths` entry; `cloud-init.yml`'s boot `ghcr_login` fails identically on the same credential, so a
revert-plus-boot does not re-create root's copy either. `GHCR_MINTER_DISABLED=true` means no
replacement can be minted. That is acceptable — the entry is a revoked credential and is not worth
restoring — but it must be stated as the one-way step it is, and it is now also stated in
`zot-registry-revert.md`, which is where someone would actually look.

## Documentation Plan

- Three ADR amendments + the `model.c4` edit (above) — in this PR.
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` — the five-signal list.
- A learning capture via `soleur:compound` on the reusable finding: *a function named for one job can be
  the sole carrier of another* (`ghcr_prelude_and_login` and the SENTRY_* prefetch), and *a
  pure-absence close criterion needs a positive control that discriminates code versions*.

## References & Research

### Internal

- `apps/web-platform/infra/ci-deploy.sh` › `ghcr_prelude_and_login() {`, `refetch_ghcr_and_relogin() {`, `_ghcr_pull_or_recover() {`, `pull_image_with_fallback() {`, `_ghcr_cfg_probe() {`, `_try_local_cache_reload() {`, `verify_image_signature() {`
- `apps/web-platform/infra/server.tf` › `terraform_data.deploy_pipeline_fix` (*"the sole path for pushing ci-deploy.sh"*)
- `apps/web-platform/infra/sentry/issue-alerts.tf` › `resource "sentry_alert" "zot_mirror_fallback_rate" {`
- `scripts/followthroughs/zot-soak-6122.sh` › `declare -A FAIL_QUERIES=(` and its `!= 5` floor
- `scripts/followthroughs/cosign-verify-live-8037.sh` (the probe template)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (`scripts/betterstack-query.sh`)
- ADRs: **169** (independence criterion, Named residual 3), **096** (pull topology, clause (f)/(g), task 5.3, Amendment 2026-09-22), **087** (cosign verifier, the mounted-config contract), **088** (why no GHCR pull credential can be minted)

### Related work

- PRs: **#8456** (1a + 1b, merge `69b08a4ee`), **#8543** (`ec68b3ec42`, the verifier's mounted credential), **#7071** (where the revocation was first measured)
- Issues: **#8036** (this), **#8037** (closed), **#7295** (closed by this), **#6565** / **#6630** (narrowed), **#6400** (probe retired), **#6122** (the zot soak), **#8539** (open, bears on 5.3b), **#6126** (second mirror, the encryption-posture tracking issue)

## Review & Consult Provenance

Four independent seats ran against this plan, plus a scoped strong-model consult at Phase 4.5. Every
finding below was verified against the tree before it was applied or declined.

| Seat | Verdict | What it changed |
|---|---|---|
| Scoped advisor consult (Phase 4.5) | 1 falsifiable challenge, 1 scope challenge, 2 ordering notes | Forced the anonymous-GHCR measurement (falsified); widened the matrix for the retry re-point |
| `soleur:engineering:cto` — structural seat (plan Phase 2.5) | approve substance | ADR-087 scoped in; 4 wrong-ref emit sites; the FR-C1 breadcrumb; corrected the ADR-096 sequencing argument |
| `soleur:engineering:cto` — devex seat (named panel) | approve direction, 4 landing conditions | Split `deploy_prelude` into three named functions; the `verify_failed` alarm gap; `earliest=apply+30m`; Guard 3 row 1 |
| `soleur:engineering:review:dhh-rails-reviewer` | overengineered | Guard rows 24→13; three pre-existing `#6512` rows cut; AC-Q7 rescoped; AC-Q4 and AC-N3 cut |
| `soleur:engineering:review:code-simplicity-reviewer` | proceed with simplifications | `docker logout` replaces the bespoke sweep; `GHCR_DOCKER_CONFIG` rename cut; C4 amend #3 cut; **P7 added** |
| `soleur:engineering:review:kieran-rails-reviewer` | **does not meet the bar — 2 blockers** | The `ProtectHome` blocker (below); the SENTRY_* claim; the `set -u` `elif`; the marker's version-discrimination; ~15 anchor corrections |

**The finding that changed the design.** Kieran measured that `ci-deploy.sh` runs under
`webhook.service` with `User=deploy`, `ProtectHome=read-only`, and `/home` absent from
`ReadWritePaths` — so the home-config sweep the operator's ruling names is **structurally
impossible** from that unit, and grading the close criterion on `home_ghcr_auth=none` would have kept
#8036 open forever. The plan now sweeps the deploy config only and grades on a `swept=` token. Three
seats had read the same plan without catching it; it took the seat whose brief was "verify, do not
take on trust".

**Two findings were declined and surfaced instead**, per the headless routing rule — they change scope
the operator set rather than correcting an error. Both are in
`knowledge-base/project/specs/<branch>/decision-challenges.md` for `ship` to render: **DC-1** ship as
two PRs; **DC-2** absorb and retire `cosign-verify-live-8037.sh`.

**One earlier finding was retracted by a later seat.** The structural seat reported that
`_try_local_cache_reload`'s new-version fallthrough had no test row; DHH measured that the
`#6512 local-cache reload tier` block already covers it verbatim. The plan cites the existing cases
rather than duplicating them — recorded because a plan that folds in review findings without checking
them inherits their errors.
