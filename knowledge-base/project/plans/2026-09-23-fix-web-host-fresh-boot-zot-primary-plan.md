---
title: "fix: a fresh web-host boot is dark — the zot-primary image path never activates"
date: 2026-09-23
slug: fix-web-host-fresh-boot-zot-primary
branch: feat-one-shot-8651-web-host-zot-primary-boot
issue: 8651
closes: []
refs: [8651, 6985, 6500, 6122, 6438, 8539]
type: bug
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix: a fresh web-host boot is dark — the zot-primary image path never activates

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).


A web-host replace boots a host that never comes up: the first-boot seed pull of the app image
goes to GHCR, whose read credential is revoked, and the pull is refused. This plan makes the web
host's first-boot image resolution take the self-hosted zot registry the way the dedicated inngest
host already does, and makes a failure of that leg loud rather than a silent fall-through to a
registry that can no longer authenticate.

## Research Insights

### Premise Validation (Phase 0.6)

- **Cited issues (all verified OPEN on 2026-09-23 via `gh issue view`):** #8651 (P1, this
  issue), #6500, #6122, #6438, #8539, #6441 (all OPEN). Also discovered and verified OPEN:
  **#6985** — "cloud-init sources the Doppler env file without `set -a`, so ~10 runcmd call
  sites never receive a token"; #6897 (the ledgered zot plain-HTTP exception); #8036 (GHCR
  read-path retirement, items 1c done / 1d open).
- **Cited files hold on `origin/main`:** `apps/web-platform/infra/cloud-init.yml` (seed-pull
  block anchored at `# BEGIN host-script extraction (#5921)`), `cloud-init-inngest.yml`
  (`/usr/local/bin/soleur-inngest-nic-wait`), `soleur-host-bootstrap.sh`
  (`cat > /usr/local/bin/soleur-wait-nic <<'NICEOF'`), `scripts/fresh-host-boot-trail.sh`,
  `scripts/followthroughs/zot-soak-6122.sh` (`WEB_BLOCKER=8651`).
- **STALE PREMISE — the mechanism in the issue body is not the one the code and telemetry
  show.** The issue (and the soak commit 3aaaede525's message) attribute the dark boot to "the
  3-second probe losing" to a cold NIC. What the code actually shows:
  1. `cloud-init.yml`, seed-pull block, line anchored `ZURL=$(timeout 15 doppler secrets get
     ZOT_REGISTRY_URL --plain --project soleur --config prd 2>/dev/null || true)` directly
     below `# /v2/-reachable, else the unchanged GHCR ref) → /run/soleur-image-ref`: this runs
     in the **main runcmd shell**, and the only place that shell exports the Doppler token is
     the terminal block's `set -a; . /etc/default/webhook-deploy; set +a` — which comes **after**
     the seed pull. The top-of-runcmd comment anchored `(#6981) runcmd runs as root with no
     `User=`` already records "sites above the exporting `set -a; . webhook-deploy` use a bare
     `.` and stay tokenless/inert — not fixed here (#6985)". The zot login inside the
     `STAGE=ghcr_login` subshell sources the file with a bare `.` too, so its three
     `doppler secrets get ZOT_*` calls are equally tokenless.
  2. **Reproduced locally** (no secret read): `env -i HOME=<empty> PATH=… sh -c '. <env file
     with DOPPLER_TOKEN=fake>; doppler secrets get ZOT_REGISTRY_URL --plain --project soleur
     --config prd'` → `rc=1 Doppler Error: you must provide a token`. The shell variable is set;
     `env | grep -c '^DOPPLER_TOKEN='` in the child prints `0`. On the host the error is
     swallowed by `2>/dev/null || true`, so `ZURL=""` and `REF="$IMAGE_REF"` (GHCR) **before
     the probe is ever evaluated** — `[ -n "$ZURL" ]` short-circuits it.
  3. **Measured on Sentry (org `jikigai-eu`, 90-day retention, counts only; token injected via
     `doppler run`, never printed):** `stage:"app_zot"` = **0**; `stage:"app_ghcr_fallback"` =
     **0**; `stage:"app_ghcr_served"` = **3** (2026-07-26T16:51Z, 2026-07-27T07:49Z,
     2026-07-27T11:05Z — all *after* the 2026-07-17 zot cutover recorded in
     `zot-soak-6122.sh` `START=`). Every web fresh boot in retention began with `REF` = GHCR
     and never attempted zot; a probe-loses mechanism would have needed to lose 4/4 boots,
     while the tokenless mechanism is deterministic. `stage:"pull" "soleur-hostscript-seed
     failed"` = 3, the newest being run 35912244388 (2026-09-23T20:10:21Z, detail
     `ghcr_login_fail: … denied | pull_err: … unauthorized`).
  4. Run 35912244388's own log (`gh run view --log`, job `web_host_replace`, step 16) shows only
     `bootcmd_start` (20:09:06Z) then the `stage=pull` fatal (20:10:21Z) with `host=?` — the
     cloud-init `_emit` carries no `host_name` tag, so the trail cannot attribute the event.
     The boot trail's QUERY does not include the `app image served …` messages, so the trail
     is structurally blind to which registry served a boot.
- **The NIC hypothesis is real but secondary (the second defect in the stack).** Web hosts
  join the private net through a separate `hcloud_server_network.web` (`network.tf`), the
  same hot-attach shape as the inngest host's #8539 race. And `soleur-wait-nic` is written by
  `soleur-host-bootstrap.sh`, which is extracted **from the image this block pulls**, so it
  structurally cannot run before the pull; its only call site (`- soleur-wait-nic
  ${private_ip}`) is later and gated `%{ if web_tunnel_connector ~}`. Once the token defect is
  fixed, the zot login/pull would be the web host's first private-net use with **no** NIC wait
  in front of it. Measured counterpoint: the inngest host's pre-login wait on 2026-09-23
  reported `private_nic_ok … waited_s=0`, so the race is intermittent, not deterministic —
  worth a cheap bounded wait, not the root cause of #8651.

### Mechanism Minimality (Phase 0.6b)

**Property List.**

- P1 — A fresh web-host boot pulls the app image from zot whenever zot is configured,
  without depending on Doppler answering, and without depending on a GHCR credential.
- P2 — A zot-leg failure is attributable off-host: the fatal names the zot leg's login and
  pull outcome, not a GHCR 401 that points away from the cause.
- P3 — The zot login/pull does not race private-NIC convergence on a web host; the wait's
  outcome is observable and an unconverged NIC pages.
- P4 — The delivery verification (the replace job's boot trail) can show, from Sentry alone,
  that the boot was zot-served and that GHCR failed non-fatally.
- P5 — The fix regresses loudly: a future edit that reintroduces a tokenless or Doppler-gated
  image resolution, or a silent downgrade to GHCR, reds a test.

**Cut List.**

- `/v2/` 3-second liveness probe → P1 → cut; the bounded, retried, timeout-wrapped zot pull
  is itself the probe (the inngest arm has none and states why in `cloud-init-inngest.yml`
  "BOUNDED. This is the optional leg").
- Exporting the full-prd Doppler token earlier (`set -a` at the seed block) as the P1
  mechanism → cut in favour of baking; baking is the ADR-096 2026-08-13 precedent and removes
  Doppler from the cold-boot critical path. (The one remaining pre-anchor Doppler site, `_emit`'s
  DSN fallback, is deleted rather than exported — Phase 2.4.)
- Doppler re-fetch of the GHCR credential (`ghcr_login_ok_refetch` arm + the empty-bake
  fallback loops) → buys no property: tokenless since birth (#6985), and the only value it
  could fetch is the revoked PAT (`GHCR_MINTER_DISABLED=true`, server.tf `#8036 1c` note).
  Deleted to pay user_data bytes.
- A new Sentry alert for zot-leg failure → P2 is covered by the fatal event
  (`soleur-hostscript-seed failed`, stage `pull`) being read by the job that created the host:
  every web fresh boot is born by a `web-host-create`/`web-host-replace` dispatch whose boot-trail
  step turns red on it. **Correction (plan review):** `web_terminal_boot_fatal` does NOT page a
  lone seed fatal — its `event_frequency_count value = 1` is a strict "more than 1" (the #6982
  note in `issue-alerts.tf`), which works only for the busy shared boot-stage group, and the seed
  fatal is its own message group with one event per dark boot. The dispatching job is the
  detector; no new alert is added here. P3's timeout is covered by `web_private_nic_boot_gate`
  (the NIC events land in the busy `soleur-cloud-init boot stage` group) as long as the wait
  emits exactly `private_nic_timeout` / `private_nic_probe_fault`.
- A web copy of the baked `soleur-wait-nic` helper → cannot be baked (chicken-and-egg with
  the image), so the wait is inline and minimal.

### Value-Proposition Measurement (Phase 0.6c)

Not a cost/performance plan — skipped. (Byte cost is measured in Phase 0.1 and 2.7 against
`WEB_GZIP_BUDGET`, not asserted.)

### Relevant files

- `apps/web-platform/infra/cloud-init.yml` — seed-pull block (`STAGE=ghcr_login` subshell,
  the `ZURL=` resolution, the `until docker pull "$REF"` loop, the `_emit` helper and
  `on_err` at the top of runcmd), the colocated-inngest block's `ZURL=` (rendered only when
  `web_colocate_inngest`), the daemon.json `insecure-registries: ["${registry_endpoint}"]`.
- `apps/web-platform/infra/server.tf` — `resource "hcloud_server" "web"`, `user_data =
  base64gzip(templatefile("${path.module}/cloud-init.yml", {…}))`, `lifecycle {
  ignore_changes = [user_data, ssh_keys, image, placement_group_id] }`; already passes
  `registry_endpoint = local.registry_endpoint`, `private_ip = each.value.private_ip`,
  `host_name`.
- `apps/web-platform/infra/inngest-host.tf` — the bake precedent: `zot_registry_endpoint =
  local.registry_endpoint`, `zot_pull_user = local.zot_pull_user`, `zot_pull_token =
  random_password.zot_pull.result`, with its "WHOLE-APPLY HAZARD" rationale for reading the
  in-root resource instead of a new root variable.
- `apps/web-platform/infra/zot-registry.tf` — `zot_pull_user = "zot-pull"`, `resource
  "random_password" "zot_pull"` (length 40, no specials).
- `apps/web-platform/infra/network.tf` — `resource "hcloud_server_network" "web"`.
- `apps/web-platform/infra/cloud-init-inngest.yml` — `soleur-inngest-nic-wait` (probe_ran /
  exit-capture shape, 75×2 s), `zot login` arm (`timeout 60 docker login`), bounded
  `timeout 180 docker pull "$ZIREF"`, per-leg `oci-pull-ALL-LEGS-FAILED "zot=[…] ghcr=[…]"`.
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` — `QUERY=` (4 message literals),
  `EXPECT_HOST="soleur-${WEB_HOST_KEY}"`, `hostok()` (untagged events pass), verdict green only
  on `fresh_boot_ready`.
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — AC8 two-way
  QUERY↔emit lockstep.
- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` — asserts the seed GHCR login
  and the §1A `ghcr_login_ok_refetch` arm (to be re-scoped).
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC7 `render_ci()` carries
  the full web templatefile var map ("a new map var breaks this render (the intended
  tripwire)").
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — `WEB_GZIP_BUDGET = 24_740`
  (measured 24,556 in CI → ~184 B headroom), "Re-derive from a CI failure line, never from a
  local run".
- `apps/web-platform/infra/nic-wait-gate.test.sh` — the extract-and-execute-with-stub-`ip`
  pattern to reuse for the inline wait.
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — pins the
  emit call forms `"app_ghcr_fallback" warning`, `"app_ghcr_served" warning`, `"app_zot" info`.
- `apps/web-platform/infra/sentry/issue-alerts.tf` — `sentry_alert.web_private_nic_boot_gate`
  (stages `private_nic_timeout`, `private_nic_probe_fault`; host-generic).
- `scripts/followthroughs/zot-soak-6122.sh` — `WEB_BLOCKER=8651` arm requires #8651 CLOSED as
  COMPLETED ("⚠ Do not delete this arm to make the gate pass, and do not close #8651 to bypass
  it").
- `apps/web-platform/infra/scripts/host-image-coherence-preflight.sh` — the replace job's
  load-bearing preflight: recomputes the pinned image's `/opt/soleur/host-scripts` hash and
  compares it to `local.host_scripts_content_hash`.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
  — "Amendment 2026-08-13 (#7462/#7516) — the inngest cold-boot pull site is migrated, by BAKE
  not Doppler", which justifies the bake with "the measured cold-boot fact the web host
  records — Doppler answers EMPTY at the boot instant". That "fact" is the #6985 tokenless
  defect observed from the outside; this plan's amendment corrects the record.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `hetzner -> zotRegistry
  "Pulls app image + … — dark-launch gated (attempts zot only when configured +
  /v2/-reachable + login ok) …"`.
- `scripts/encryption-posture-ledger.json` — row `"web hosts -> zot registry
  (10.0.1.30:5000)"`, exception `#6897`, `expires_on 2026-10-22`.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it.md` (#6981) — a grep
  cannot pin a property of the shell; bare `.` does not export. The regression guard for this
  plan therefore EXECUTES the extracted block with stubs.
- `knowledge-base/project/learnings/2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`
  — comments in `cloud-init.yml` cost user_data bytes; rationale belongs in `server.tf` / the
  ADR. The budget test renders with real-length values.
- `knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md` — `-target` walks dependencies not dependents; a fresh
  host may boot before its `hcloud_server_network` attach lands.
- `knowledge-base/project/learnings/2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md` (#6090) — the
  prior GHCR stale-cred diagnosis; with the PAT revoked the re-fetch has no value left to fetch.
- `knowledge-base/project/learnings/2026-07-04-cosign-verify-phase0-falsifies-plan-flags-and-userdata-cap-relocation.md` — the
  user_data cap forces bulk into the baked image; only irreducibly-inline call sites stay in
  `cloud-init.yml`.
- `knowledge-base/project/learnings/2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md` — root runcmd needs
  `HOME=/root` exported (already done, #6981).
- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` + the 2026-07-06 errexit-leak
  post-mortem — runcmd is ONE `/bin/sh`; any new `set -e` must stay scoped, and the block's
  closing `set +e` must survive.

### External research

None — strong local precedent (`cloud-init-inngest.yml` #7462/#6500/#8539). Functional
overlap check (community registries, 3/3 answered): no meaningful overlap; nothing installed.

### CLAUDE.md / AGENTS.md conventions in force

`hr-prod-host-config-change-immutable-redeploy`, `hr-fresh-host-provisioning-reachable-from-terraform-apply`,
`hr-all-infrastructure-provisioning-servers`, `hr-observability-as-plan-quality-gate`,
`hr-no-ssh-fallback-in-runbooks`, `hr-never-run-commands-with-unbounded-output`,
`cq-cite-content-anchor-not-line-number`, `wg-use-closes-n-in-pr-body-not-title-to`, and the
operator constraint that #6500, #6122 and #6438 are only ever written with `Ref`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (code + telemetry) | Plan response |
|---|---|---|
| "The 3-second `/v2/` probe lost" is why REF stayed GHCR. | The probe is never evaluated: `ZURL` comes from a tokenless `doppler` call (bare `.` source, no `set -a`) and is always empty (#6985). Reproduced locally; Sentry shows 0 `app_zot` / 0 `app_ghcr_fallback` / 3 `app_ghcr_served` since the cutover. | Root cause is the token scope, not the probe. The fix removes Doppler from the resolution entirely (bake), and drops the probe. The soak commit message and the issue body carry the wrong mechanism; the ADR-096 amendment records the correction. Neither the soak script's arm nor its message text is edited (the arm's gate is `#8651 CLOSED as COMPLETED`, which the correction does not change). |
| "Confirm whether the probe precedes `soleur-wait-nic`." | It does, and structurally must: `soleur-wait-nic` is written by `soleur-host-bootstrap.sh`, extracted **from the image the probe gates**; its only call site sits after the seed pull under `%{ if web_tunnel_connector ~}` (web-1 only). | Add an inline, bounded, fail-open NIC wait *before* the zot login — it cannot be the baked helper. |
| "`ZOT_REGISTRY_URL` is set (10.0.1.30:5000), so this is not a missing config." | True in Doppler; irrelevant on the host, which cannot read it. The same value is already compiled into `user_data` as `${registry_endpoint}` (the daemon.json `insecure-registries` entry). | Use `${registry_endpoint}`; add `zot_pull_user` / `zot_pull_token` to the template map from the in-root resources, as `inngest-host.tf` does. |
| ADR-096 2026-08-13: "Doppler answers EMPTY at the boot instant" (the web host's measured cold-boot fact). | That observation is the tokenless call seen from outside, not a Doppler availability property. | Amend ADR-096 to say so. The bake decision still stands on its own merit (no network dependency on Doppler at cold boot). |
| "Consider making the GHCR leg fail closed and loud at login." | Today a failed GHCR login is recorded to `/run/soleur-stage-detail` and the pull is still attempted, so the fatal reads as a GHCR 401 even when zot was never tried. | GHCR pull is attempted only when the baked GHCR login succeeded; otherwise the fatal names both legs. The GHCR leg itself is kept (ADR-096 5.3 / #8036 1d are not this PR's authority). |
| "Tackle #6122 and #6438." | #6122's web fresh-boot enrollment is exactly this change; #6438 §3 (web-host NIC convergence) is split between a running-host guard (bake-and-extract, not this PR) and the fresh-boot half (this PR). | Both advanced, both `Ref` only. |

## Hypotheses

The network-outage checklist fires (the description names `timeout` and `unreachable`). Layers
in L3 → L7 order; each answered with what was actually checked.

1. **L3 firewall.** Not the cause, and verifiable without SSH from code: Hetzner cloud
   firewalls filter only the public interface (`inngest-host.tf` comment anchored
   "Hetzner firewalls filter only the PUBLIC interface"); `hcloud_server_network.web` and
   `.registry` share `hcloud_network_subnet.private`. The zot host's deny-all-public firewall
   does not apply to 10.0.1.0/24. The failing boot never sent a packet to zot (no zot leg was
   attempted), so no firewall could have dropped it. Verified: code read + Sentry (0
   `app_ghcr_fallback`, which is the only emit that fires after a zot attempt).
2. **L3 DNS/routing.** Not applicable to the zot leg: the endpoint is an IP literal
   (`local.registry_endpoint = "${local.registry_private_ip}:5000"`). Routing on the private
   subnet depends on the NIC being attached — hypothesis 5.
3. **L7 TLS.** Not applicable: the zot link is plain HTTP by design (ADR-096; ledger row
   "web hosts -> zot registry", exception #6897). The GHCR leg's TLS succeeded — GHCR
   *answered* `denied`.
4. **L7 application.** **Confirmed cause.** `ZURL` empty because `doppler` received no token
   (reproduced; `Doppler Error: you must provide a token`), so `REF` stayed GHCR, and GHCR
   refused the revoked PAT (`ghcr_login_fail: … denied`, then `pull_err: … unauthorized`).
5. **Private-NIC convergence (#8539 class).** **Plausible, not causal for #8651, latent.**
   Separate `hcloud_server_network.web` attach; no NIC wait before the first private-net use;
   the inngest host measured `waited_s=0` on 2026-09-23. Once hypothesis 4 is fixed, this
   becomes the next thing that can turn a zot boot into a failure, so it is fixed in the same
   change.

## Problem Statement

Every web-host fresh boot since the 2026-07-17 zot cutover has resolved its app image to
GHCR, because the zot selection reads Doppler with a token the shell never exported. While the
GHCR read PAT worked, this was invisible (the boot succeeded, `app_ghcr_served` fired as a
warning into a group nobody read as a failure). Since the PAT was revoked (AP-016, 2026-07-29/30)
every fresh web boot is dark. `web-1` is the sole live web host; its replacement would strand
the web tier, and `runcmd` runs once per instance, so a dark host can only be replaced.

## Proposed Solution

Mirror the dedicated inngest host (`cloud-init-inngest.yml`, #7462/#6500/#8539), sized to the
web template's byte budget:

1. **Bake** the zot endpoint (already baked: `${registry_endpoint}`) and the zot pull
   credential (`zot_pull_user`, `zot_pull_token`, new template vars from `local.zot_pull_user`
   and `random_password.zot_pull.result`) — no Doppler read on the resolution path.
2. **Wait** (inline, bounded ≤150 s — the `soleur-inngest-nic-wait` bound, cited in `server.tf`
   not in the byte-budgeted template — fail-open) for this host's private address before the
   first private-net use. The two non-ready outcomes emit `private_nic_timeout` /
   `private_nic_probe_fault` through the existing baked-DSN `_emit`, so the existing host-generic
   `web_private_nic_boot_gate` alert pages on them. The ready outcome emits nothing of its own
   (no extra pre-pull emit, no throttle latency on the healthy path); its `nic_w=<s>` rides the
   `app_zot` detail and the fatal detail, so every outcome is still observable.
3. **Log in to zot** from the baked credential (bounded retries), recording the outcome.
   The GHCR login runs inside `( set +e … ) || true`, so variables set there never reach the pull
   loop: each login's outcome (and the NIC wait's `W`) is persisted to a `/run/soleur-*-login`
   (resp. `/run/soleur-nic-w`) file, or the zot login and NIC wait run outside the subshell,
   `||`-guarded against the item's `set -e`. The sketch below is written that way.
4. **Resolve `REF` to zot unconditionally** when the baked endpoint is non-empty. No probe.
5. **Pull** with bounded, timeout-wrapped zot attempts. Flip to the GHCR ref only when the
   baked GHCR login succeeded (that flip keeps its `app_ghcr_fallback` warning and the
   ADR-096 5.3 tripwire comment). Otherwise fail with a detail that names both legs in the
   inngest host's `oci-pull-ALL-LEGS-FAILED` shape, so one Sentry search reads both hosts.
   `_emit` truncates the detail at 200 chars (`head -c 200`), so **fixed-length fields come
   first and variable tails last**: `ghcr=[login=fail,not-attempted] nic_w=<s>
   zot=[login=<ok|fail>] pull_err: <zot pull tail, capped so the whole detail is ≤200>`, and on a
   failed zot login the login tail replaces the pull tail (a login tail is what separates a
   rotated token from zot-down from no-route). The GHCR login's error text is no longer written
   into the detail file (the GHCR outcome is the fixed `login=fail` field). The literal
   `pull_err:` is kept (pinned by `soleur-host-bootstrap-observability.test.sh` AC18).
6. **Report success loudly and attributably:** before the `app_zot` emit (unchanged
   stage/message/call form), write `zot_login=ok ghcr_login=<ok|fail> nic_w=<s>` to the
   existing `/run/soleur-stage-detail` file `_emit` already reads, then clear it (no `_emit`
   signature change). `_emit` gains a `host_name` tag. The replace job's boot trail gains the
   `app image served` message **and prints the newest image-origin event for the host outside
   its 8-event slice** (a healthy boot's `app_zot` is early and would otherwise fall off the
   printed list); a `--image-origin <host_name>` query-only mode of the same script prints that
   one line locally (the Observability discoverability command — one copy of the Sentry
   filtering logic, not two).
7. **Delete** the Doppler GHCR re-fetch arms (dead by construction, twice over) to pay for the
   additions; keep the baked GHCR login itself (#8036 1d owns its retirement).
8. **Colocated-inngest block** (rendered only when `web_colocate_inngest`): source `ZURL` from
   `${registry_endpoint}` instead of Doppler, so no tokenless zot read survives in the file.
9. **Delete `_emit`'s Doppler DSN fallback** (and the `. /etc/default/webhook-deploy` line
   that only serves it). It runs only when the baked DSN is empty, and every host-creating
   dispatch refuses an empty `SENTRY_DSN` (`apply-web-platform-infra.yml` step "Extract backend
   credentials + assert SENTRY_DSN non-empty (ADR-128 R1)", three sites). After this, **no
   `doppler` invocation remains in runcmd above the terminal block's exporting source** — the
   whole #6985 class is gone from this file rather than patched site by site.

Nothing under `/opt/soleur/host-scripts` (i.e. `soleur-host-bootstrap.sh` and siblings)
changes: the replace job's coherence preflight pins web-1's **running** image and compares its
baked host-scripts hash to `local.host_scripts_content_hash`, so a host-scripts edit would make
the very delivery dispatch this fix needs refuse to run until a new release is deployed to web-1.

### Seed-block shape (sketch — `soleur:work` owns the final bytes)

```sh
# apps/web-platform/infra/cloud-init.yml — inside the existing `set -e` host-script extraction
# item, replacing the STAGE=ghcr_login subshell's Doppler arms, its ZOT_* reads, and the
# ZURL=/probe resolution. Every shell `${…}` must be written `$${…}` (templatefile).
ZEP='${registry_endpoint}'
# NIC wait: probe exit captured separately from the match (a failing `ip` is a probe fault,
# never "absent"); empty-address guard (grep -qwF -- "" matches every line).
#   -> on timeout/probe fault only: _emit "soleur-cloud-init boot stage"
#      private_nic_{timeout,probe_fault} warning (detail via /run/soleur-stage-detail); W kept
#      for the later detail as nic_w=$W
# zot login (fail-open, bounded, OUTSIDE the GHCR subshell or persisted to /run):
#   printf '%s' '${zot_pull_token}' | timeout 60 docker login "$ZEP" -u '${zot_pull_user}' \
#     --password-stdin >/run/soleur-zot-login.log 2>&1 && ZL=ok || ZL=fail
# GHCR login: baked creds only, inside the existing ( set +e … ) subshell -> writes
#   /run/soleur-ghcr-login (ok|fail); no Doppler fallback, no re-fetch, no error text in the
#   stage-detail file
REF="$ZEP/$(printf '%s' "$IMAGE_REF" | sed 's#^ghcr.io/##')"   # ${registry_endpoint} is a compile-time constant
# pull loop — keep the `until docker pull "$REF"` anchor the seed-login test keys on; bound
#   each attempt inside the loop body or via a wrapper that preserves that anchor (update the
#   test's pull_ln anchor in the same edit if the form must change). zot attempts bounded; flip
#   to IMAGE_REF only if /run/soleur-ghcr-login says ok (emit app_ghcr_fallback); else write the
#   fixed-fields-first detail and exit 1 (on_err -> stage=pull fatal)
# success: printf 'zot_login=%s ghcr_login=%s nic_w=%s' … > /run/soleur-stage-detail, then the
#   UNCHANGED `if [ "$REF" = "$IMAGE_REF" ]; then _emit … app_ghcr_served …; else _emit …
#   app_zot info; fi` line, THEN `: > /run/soleur-stage-detail` (the clear moves after the emit)
```

The inngest arm's rationale comments stay in `cloud-init-inngest.yml`/ADR-096; the web copy
carries one-line pointers only (bytes).

## Implementation Phases

Ordered so the harness and the byte measurement exist **before** the block is rewritten
(advisor consult, ADR-083): a restructure forced by the budget or by templatefile escaping is
discovered against a test, not after.

### Phase 0 — Baseline and harness (RED first)

- 0.1 Measure the current web render with the size test locally
  (`bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` — 70 pass at plan time; it
  prints the web figure only on failure, so read it via an uncommitted local lower bound) and
  record the local figure next to the CI figure (24,556). Local and CI differ by ~32 B
  (`WEB_GZIP_BUDGET` comment), so the CI line is the authority. The PR body records the
  post-change CI figure and remaining headroom; if headroom ends below ~100 B, file a
  follow-up issue naming the next thing to move out of `cloud-init.yml`.
- 0.2 Create `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh`: render
  `cloud-init.yml` with `terraform console` + `templatefile()` (the `render_ci()` pattern from
  `cloud-init-inngest-bootstrap.test.sh` AC7, SKIP-with-reason when terraform is absent
  locally, required in CI), extract runcmd item 1 (`STAGE=runcmd_early`: `_emit`, `on_err`,
  `trap on_err EXIT`, `HOST_ID`, `export HOME`) **joined with** the host-script extraction item —
  the seed item cannot run alone — rewrite its hard-coded `/run/…` and `/etc/default/…` paths
  into a sandbox root with a sed whose application is asserted (count the rewritten occurrences),
  and stop execution at `STAGE=extract` (or stub `docker create`/`docker cp` to produce a seed
  whose hash matches the rendered `host_scripts_content_hash`, so the success path does not reach
  a real `soleur-host-bootstrap.sh`). EXECUTE it with stubs on `PATH`: `docker` (records argv; `login`/`pull` outcomes per registry driven by env),
  `ip` (argv-validating, converging-after-N variant — copy the `make_ip` /
  `make_ip_converging` shapes from `nic-wait-gate.test.sh`), recording no-op `sleep` (records
  argv; `docker info` stubbed to succeed at once so its `sleep 2` loop records nothing, and the
  NIC-wait count is taken over `sleep 2` records only — pull retries use `sleep 5`),
  `timeout` pass-through, `doppler` (records every invocation), `curl` (records the Sentry POST
  bodies `_emit` sends), and a fake `/run` root. Render with a non-empty `sentry_dsn` (the
  dispatch-enforced state). Write it so it fails against today's block (Guard 1 rows below).
- 0.3 In the SAME file, a mutation section executing the Guard Contract matrices (pristine
  sandbox copy per case; confirm each mutation landed; HARNESS failures exit 2 — the
  `cloud-init-inngest-zot-pull-mutation.test.sh` contract), plus one cross-template parity
  assertion: the web fatal detail and the inngest `oci-pull-ALL-LEGS-FAILED` marker both use the
  `zot=[` / `ghcr=[` shape. One new test file, not two.
- 0.4 Register it in `.github/workflows/infra-validation.yml` next to the
  `nic-wait-gate.test.sh` step.

### Phase 1 — Terraform wiring

- 1.1 `apps/web-platform/infra/server.tf`, `hcloud_server.web` templatefile map: add
  `zot_pull_user = local.zot_pull_user` and `zot_pull_token = random_password.zot_pull.result`.
  Rationale prose goes in `server.tf` (free), pointing at the inngest-host.tf precedent and the
  cleartext-Basic-on-private-net note.
- 1.2 Update every other render map of the web template in the same edit:
  `cloud-init-inngest-bootstrap.test.sh` `render_ci()` and the stub map in
  `plugins/soleur/test/cloud-init-user-data-size.test.ts` (enumerated by
  `git grep -l soleur_doppler_token_env_b64`; `.github/scripts/validate-infra-templates.sh`
  derives names from the `.tf` call and needs no edit — confirm by running it).

### Phase 2 — The seed block (`apps/web-platform/infra/cloud-init.yml`)

- 2.1 Delete the Doppler arms of the `STAGE=ghcr_login` subshell (the empty-bake fallback loops
  and the `ghcr_login_ok_refetch` re-fetch) and its three `doppler secrets get ZOT_*` reads.
  Keep the baked GHCR login and its outcome capture.
- 2.2 Add the inline NIC wait (Proposed Solution 2), then the baked zot login (3).
- 2.3 Replace the `ZURL=` + `/v2/` probe with the baked resolution (4) and rework the pull loop
  (5): bounded zot attempts, GHCR flip gated on the GHCR login outcome, per-leg fatal detail.
  Keep `: > /run/soleur-stage-detail`, `printf '%s' "$REF" > /run/soleur-image-ref`, the #6462
  `app_ghcr_served` / `app_zot` emit pair **byte-identical in call form** (the op-contract test
  pins `"app_zot" info` etc.), and the `# ADR-096 5.3 tripwire (#6285)` line.
- 2.4 `_emit` and the `bootcmd:` beacon (both printed `host=?` on run 35912244388): add the
  `host_name` tag (`'${host_name}'`); delete the Doppler DSN fallback and
  the `. /etc/default/webhook-deploy` line that only serves it (Proposed Solution 9). No
  signature change — success/failure details go through `/run/soleur-stage-detail`.
- 2.5 Colocated-inngest block: `ZURL='${registry_endpoint}'` in place of the Doppler read.
- 2.6 Preserve the block's closing `set +e` (H3, #6090) and `trap - EXIT` placement.
- 2.7 Re-run the size test. If the render exceeds `WEB_GZIP_BUDGET`, trim comments in this
  file first (prose → `server.tf`/ADR). Raise the budget only if still over, and only from the
  CI failure line, with a comment in the test's established shape (what was added, why it is
  irreducibly inline, measured CI render, headroom kept).

### Phase 3 — Boot-trail visibility

- 3.1 `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`: add `message:"app image
  served"` to `QUERY` (one literal — it is used as a regex by `MSG_RE`, and the fallback
  message's `(zot miss)` parentheses would be regex groups; the prefix matches all three).
- 3.2 `soleur-host-bootstrap-observability.test.sh` AC8: add the literal to the QUERY list, add
  the reverse pair as the FULL `"app image served by zot:$CI"` (a bare `app image served` pair
  would stay green after an `app_zot` rename because the GHCR messages share the prefix) plus an
  assertion that the QUERY literal is a prefix of it, and add one assertion that no
  literal extracted from QUERY contains a regex metacharacter (`MSG_RE` is built from them).
- 3.3 The trail already prints each listed event's `detail`, but only the newest 8 events
  (`| .[0:8][]`), so a healthy boot's early `app_zot` falls off. Add one line, outside the
  slice, printing the newest `app image served` event for `EXPECT_HOST` (stage, host, time,
  detail), reusing `JQ_HOSTDEF`/`MSG_RE`. Add a `--image-origin <host_name>` mode that runs only
  that query and prints that line (`TRANSIENT:` + exit 2 on a missing token or non-200, never an
  empty "nothing found"). The line does not change the verdict (`fresh_boot_ready` stays the
  sole green).

### Phase 4 — Tests that change meaning

- 4.1 `cloud-init-ghcr-seed-login.test.sh`: retire assertion 1 ("seed login fetches
  GHCR_READ_{USER,TOKEN} via doppler") and the §1A `ghcr_login_ok_refetch` assertion, and
  assert their absence with the reason (no Doppler read on the seed path; the baked value is the
  create-time value); keep "docker login ghcr.io precedes the seed pull" and the baked-DSN
  assertion (re-worded: the DSN is baked-only now).
- 4.2 `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` pins the
  `_emit` tag string `'"tags":{"stage":"%s","image_ref":"%s","host_id":"%s","detail":"%s"}'`
  including the closing brace. Append `host_name` **after** `detail` and loosen that pin to an
  open prefix (ADR-147: "add tags, never rename"); the emit call-form pins (`"app_zot" info`
  etc.) stay unchanged.
- 4.2b `plugins/soleur/test/cloud-init-user-data-size.test.ts` AC1c pins the whole
  `…else _emit "app image served by zot" "app_zot" info; fi` line — keep that line
  byte-identical (the success detail goes through the file, not an argument).
- 4.2c `soleur-host-bootstrap-observability.test.sh` AC19(2) requires the deleted
  `until GHCR_USER=$(timeout 45 doppler … GHCR_READ_USER` arm — retire it with an absence
  assertion and reason; AC18's `pull_err:` literal stays satisfied by the new detail format.
- 4.2d `cloud-init-ghcr-seed-login.test.sh`: check 1b (`doppler secrets get GHCR_READ_USER`)
  contradicts AC6 — retire it; its `pull_ln` anchor on `until docker pull "\$REF"` must match
  the final loop form.
- 4.3 `nic-wait-gate.test.sh` / `cloud-init-inngest-bootstrap.test.sh` emit/route lockstep
  sections: extend (or confirm they already cover) the rule that every `private_nic_*` stage
  `cloud-init.yml` emits is routed by `web_private_nic_boot_gate`.

### Phase 5 — Architecture record

- 5.1 ADR-096: new section "Amendment 2026-09-23 (#8651) — the web cold-boot pull site is
  migrated, by BAKE" (see `## Architecture Decision (ADR/C4)`).
- 5.2 `model.c4`: rewrite the fresh-boot clause of the `hetzner -> zotRegistry` edge
  description; run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, and
  `plugins/soleur/test/c4-count-parity.test.sh`.
- 5.3 `scripts/encryption-posture-ledger.json`, row `web hosts -> zot registry
  (10.0.1.30:5000)`: extend `does_not_defend` with the credential (Basic over plain HTTP) and run
  `python3 scripts/lint-encryption-posture.py`. Do not move `expires_on`.

### Phase 6 — Delivery and verification (post-merge; merging changes no host)

- 6.1 Confirm the merge-triggered apply's plan shows no `hcloud_server.web["web-1"]` diff
  (`ignore_changes = [user_data, …]`).
- 6.2 Dispatch `apply-web-platform-infra.yml` with `apply_target=web-host-replace`,
  `web_host_key=web-2`, `confirm=REPLACE-web-2`, no `image_tag` override (the default pin is
  web-1's running, zot-served digest), arm a watch on the run
  (`hr-dispatch-async-must-arm-watch`), and route the `web-platform-infra-apply` environment
  approval to the operator — the reviewer gate is the authorization, not a checklist item.
- 6.3 Read the job's boot trail (step "Surface fresh-host Sentry breadcrumb trail"): pass =
  the image-origin line shows `app_zot` with `ghcr_login=fail` and a `nic_w=` value in its
  detail, the verdict is `fresh_boot_ready`, and there is no `soleur-hostscript-seed failed`
  event for the host. A `private_nic_timeout` is not fatal but is recorded in the #8651 closing
  comment. Reproduce the origin line locally with the discoverability command.
- 6.4 Only then close #8651 as **completed** with the run URL and the event ids. `web-2` stays
  out of service per the operator constraint (this replace is a verification host, not a
  promotion). Close #6985 alongside it if its acceptance items are all met (see AC).

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/server.tf`
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`
- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
- `plugins/soleur/test/cloud-init-user-data-size.test.ts`
- `.github/workflows/infra-validation.yml`
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `scripts/encryption-posture-ledger.json`

## Files to Create

- `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh` — the render-and-execute harness
  plus its mutation section (Guards 1–3).

Explicitly **not** edited: `apps/web-platform/infra/soleur-host-bootstrap.sh` (coherence
preflight — see Proposed Solution), `scripts/followthroughs/zot-soak-6122.sh` (its #8651 arm is
kept verbatim), `apps/web-platform/infra/sentry/issue-alerts.tf` (existing rules already route
the stages this plan emits).

## Open Code-Review Overlap

1 open scope-out mentions a planned file:

- #2197 (billing `SubscriptionStatus` type + single-instance throttle doc) names
  `infra/server.tf` only as a place an operator might add `count`. **Acknowledge** — unrelated
  concern (rate-limiter singletons); this plan adds two template-map entries and no
  `count`/`for_each` change.

## Architecture Decision (ADR/C4)

Detection fires: this changes the web host's cold-boot registry trust path (zot becomes the
unconditional first leg, read from baked config instead of Doppler) and corrects a factual
premise recorded in ADR-096.

### ADR

Amend **ADR-096** (no new ordinal) with "Amendment 2026-09-23 (#8651) — the web cold-boot pull
site is migrated, by BAKE":

- The web host now bakes `zot_pull_user`/`zot_pull_token` and uses the compile-time
  `local.registry_endpoint`, like the dedicated host. Web fresh boots are zot-first
  unconditionally; there is no runtime kill switch (the dark-safe empty-endpoint arm is
  unreachable in this root, as the inngest amendment already says of its own).
- **Correction:** the 2026-08-13 amendment's "Doppler answers EMPTY at the boot instant" was the
  #6985 tokenless source observed from outside; measured evidence (0 `app_zot` in 90 days).
  The bake stands on removing a network dependency from cold boot, not on that premise.
- The GHCR leg on the web fresh-boot path is attempted only after a successful baked login;
  it cannot currently succeed (AP-016). This is not "break-glass": web fresh boot now depends
  entirely on zot reachability — the same consequence the inngest amendment states, now
  fleet-wide for fresh boots. Its retirement remains #8036 1d / ADR-096 5.3.
- (Operational notes — the pre-pull NIC wait, the 150 s bound's inngest provenance, and the
  `random_password.zot_pull` rotation consequence — live in `server.tf` beside the template-map
  entries, not in the ADR.)

### C4 views

All three model files were read for this assessment (`model.c4`, `views.c4`, `spec.c4`).
Elements involved, all already modeled: actor/system `hetzner` (web hosts, container
cluster), `zotRegistry` (self-hosted zot, 10.0.1.30:5000), `ghcr` (write-only for private
packages since #8036 1c), `doppler`, `sentry`. No new actor, system, container or data store;
no access-relationship change. **One edge description becomes false and is edited:**
`hetzner -> zotRegistry` "… at boot/deploy — dark-launch gated (attempts zot only when
configured + /v2/-reachable + login ok) …" → fresh boot: baked endpoint + baked pull
credential, zot-first unconditionally after a bounded private-NIC wait; deploy path unchanged.
No derived cardinality in edge prose changes; `c4-count-parity.test.sh` is run to prove it.

### Sequencing

The amendment describes the code state at merge ("armed in source"); the live-host claim
("observed zot-served on a replace") is appended when Phase 6 closes #8651 — the same
two-step the 2026-08-13 inngest amendment used.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/server.tf` only: two new template-map entries on `hcloud_server.web`
(`zot_pull_user = local.zot_pull_user`, `zot_pull_token = random_password.zot_pull.result`).
No new resources, providers, or root variables — reading the in-root resource avoids the
whole-apply hazard `inngest-host.tf` documents for a no-default root variable.

### Apply path

**Does merging this alone mutate production? No.** `hcloud_server.web` carries
`ignore_changes = [user_data, ssh_keys, image, placement_group_id]`, the only `.tf` edit is two
template-map entries feeding `user_data`, and `random_password.zot_pull` already exists in state.
The merge-triggered apply therefore plans no change for either web host. The PR body's first line
states this.

(c) replace, per host, on demand: `hcloud_server.web` carries `ignore_changes = [user_data, …]`,
so the merge-triggered apply is a no-op for web-1 and web-2; the new template is realized only by
a gated `web-host-replace` of **web-2** (refuses web-1). Downtime: none (web-2 serves no
traffic). Blast radius: web-2 only.

### Distinctness / drift safeguards

- The sensitive value lands in `terraform.tfstate` already (it is `random_password.zot_pull`,
  consumed by the inngest host and `doppler_secret.zot_pull_token`); no new state secret.
- `user_data` already carries `doppler_token` (full `soleur/prd` read, which can read
  `ZOT_PULL_TOKEN`) and `ghcr_read_token`; the zot pull token is strictly weaker than the
  former. No new trust boundary; exposure = Hetzner metadata API, same as today.
- `-target=hcloud_server.web["web-2"]` pulls `random_password.zot_pull` in as a dependency with
  no diff, so the replace job's inverted replace gate still sees only web-2's resources.

### Vendor-tier reality check

None — no new vendor resource.

## Observability

```yaml
liveness_signal:
  what: "Per fresh web-host boot: message 'app image served by zot' stage app_zot (detail zot_login=ok ghcr_login=<ok|fail> nic_w=N), then fresh_boot_ready; on a non-converged NIC additionally 'soleur-cloud-init boot stage' stage private_nic_timeout|private_nic_probe_fault. All carry host_name. The replace job's boot trail prints the newest image-origin event for the host."
  cadence: "per fresh web-host boot (runcmd is once-per-instance)"
  alert_target: "The dispatching job's boot-trail step (web-host-create / web-host-replace) turns red on a stage=pull fatal — web_terminal_boot_fatal does not page a lone seed fatal (#6982 strict >1); Sentry email via web_private_nic_boot_gate (private_nic_timeout, private_nic_probe_fault) and zot_mirror_fallback_rate (app_ghcr_fallback, app_ghcr_served)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (existing rules); emitters in apps/web-platform/infra/cloud-init.yml _emit"

error_reporting:
  destination: "Sentry project web-platform via the baked var.sentry_dsn (fires before Doppler/docker)"
  fail_loud: "'soleur-hostscript-seed failed' stage=pull with detail 'ghcr=[login=fail,not-attempted] nic_w=N zot=[login=…] pull_err: …' (≤200 chars); the web-host-create/replace job's boot-trail step turns red with that detail"

failure_modes:
  - mode: "zot login fails (bad/rotated baked token, zot auth down)"
    detection: "fatal detail zot=[login=fail] plus the login tail on stage=pull"
    alert_route: "dispatching job's boot-trail step red"
  - mode: "zot pull fails (unreachable, manifest/blob unknown after GC)"
    detection: "fatal detail zot=[login=ok] pull_err: <registry tail>"
    alert_route: "dispatching job's boot-trail step red"
  - mode: "private NIC never converges within 150 s"
    detection: "private_nic_timeout warning (boot continues; zot leg then fails and names itself)"
    alert_route: "web_private_nic_boot_gate"
  - mode: "ip probe cannot run"
    detection: "private_nic_probe_fault warning"
    alert_route: "web_private_nic_boot_gate"
  - mode: "GHCR served the boot (only possible if a valid GHCR credential is restored)"
    detection: "app_ghcr_fallback / app_ghcr_served warning"
    alert_route: "zot_mirror_fallback_rate"

logs:
  where: "Sentry events (tags stage, host_name, host_id, image_ref, detail); on-host /run/soleur-pull.log and /run/soleur-zot-login.log (tmpfs, diagnostic only — never required)"
  retention: "Sentry 90 days; /run until reboot"

discoverability_test:
  command: "bash apps/web-platform/infra/scripts/fresh-host-boot-trail.sh --image-origin soleur-web-2"
  expected_output: "app_zot"
  credentials_required: "Sentry read token as SENTRY_ACTIONS_RO_TOKEN (GitHub secret; locally Doppler soleur/prd SENTRY_AUTH_TOKEN) — a fresh boot's image origin is recorded only in Sentry events; no unauthenticated endpoint exposes it"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_server.web user_data (Hetzner metadata API) — now also carries the zot pull credential"
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/server.tf resource \"hcloud_server\" \"web\" user_data = base64gzip(templatefile(...)); same bake as ghcr_read_token and doppler_token"
    defends_against: "nothing beyond Hetzner's own access control on the metadata API and the project"
    does_not_defend: "anyone with root on the host, Hetzner project API access, or a process that can reach the metadata endpoint can read a read-only zot pull credential (strictly weaker than the doppler_token already present)"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:no metadata-API exposure probe; posture inherited from the existing ghcr_read_token/doppler_token bake"
in_transit:
  - connection: "web host (fresh boot) -> zot registry 10.0.1.30:5000"
    enforced_at: "apps/web-platform/infra/cloud-init.yml daemon.json insecure-registries [\"${registry_endpoint}\"] + the seed-block docker login/pull"
    tls: "none (plain HTTP on the Hetzner private network, by design)"
    cert_verification: off
    does_not_defend: "a passive on-net attacker on 10.0.1.0/24 can read image bytes AND the zot pull credential (HTTP Basic); integrity of the payload comes from the @sha256 digest pin, not TLS"
    disclosed_as: not-publicly-claimed
exception:
  justification: "the existing ledgered private-network-only zot link (row 'web hosts -> zot registry'), extended from the deploy path to fresh boot; payload integrity via digest pin"
  tracking_issue: "#6897"
  reevaluate_when: "the registry is exposed beyond the private network, TLS is added to the link, or the zot credential gains write scope"
  expires_on: 2026-10-22
```

## Guard Contract

### Guard 1 — web seed pull resolves zot-first without Doppler, and a zot failure names itself

**Property.** On a fresh web boot with a non-empty baked endpoint, the first `docker pull` of
the app image targets the zot ref, no `doppler` process is spawned between the start of the
host-script extraction item and that pull, and any exit of the item at `STAGE=pull` leaves a
detail naming the zot leg's login and pull outcome.

**Assembly.** The single chokepoint is the host-script extraction runcmd item of the RENDERED
`cloud-init.yml` (terraform `templatefile` render, not the raw template), executed under stubs.
Members that feed it: the template map in `server.tf` (`registry_endpoint`, `zot_pull_user`,
`zot_pull_token`), the `STAGE=ghcr_login` subshell, the resolution line, the pull loop, `on_err`
+ `_emit` (the fatal path), and `/run/soleur-image-ref` (the downstream consumer contract).
There is exactly one app-image pull site in this item; the colocated-inngest item (rendered only
when `web_colocate_inngest`) is covered by the census in Guard 3 and AC7, not by this matrix.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `ZURL=$(timeout 15 doppler secrets get ZOT_REGISTRY_URL …)` as the endpoint source | RED (doppler spawned; first pull is the GHCR ref under a tokenless stub) |
| 2 | Re-add the 3 s `curl … /v2/` gate with the curl stub failing | RED (first pull is GHCR) |
| 3 | Guard's own dispatch: the extractor matches no item (anchor renamed) | RED ("0 items executed" is a failure, not a pass) |
| 4 | Second member after a compliant first: a later line in the same item reassigns `REF="$IMAGE_REF"` before the loop | RED |
| 5 | Pull loop flips to GHCR regardless of the GHCR login outcome | RED (with GHCR login stub failing, a GHCR pull is attempted) |
| 7 | Fatal detail written without the zot leg (only `ghcr_login_fail …`) | RED |
| 8 | REORDER: move the zot login after the pull loop (login still present) | RED (first pull runs unauthenticated; stub zot rejects unauthenticated pulls) |

**Harness rows.**

- H1 (suite edit): make the `doppler` stub silently succeed and return `10.0.1.30:5000` → the
  "no doppler spawned" assertion must still RED on row 1 (the assertion reads the spawn log,
  not the pull outcome).
- H2 (must-PASS, non-canonical): endpoint rendered as `10.0.1.99:5000` with the zot stub
  serving that host → PASS (the guard keys on "the baked endpoint", not the literal).
- H3 (must-PASS): zot login fails, zot pull fails, GHCR login fails → item exits non-zero AND
  the test PASSES because the detail names both legs (a guard that rejects every failure path
  would red here).

**Anchor.** Not a stored-value comparison.

### Guard 2 — pre-pull private-NIC wait is bounded, fail-open, and every non-ready outcome pages

**Property.** Before the first private-net use in the seed item, the host waits at most 150 s
for its own private address, never aborts the item, emits exactly one routed warning
(`private_nic_timeout` or `private_nic_probe_fault`) on a non-ready outcome and none on the
ready outcome, and records `nic_w=<s>` in the detail of whichever terminal event the item emits.

**Assembly.** The inline wait in the rendered seed item (single site) plus the routing contract
in `sentry/issue-alerts.tf` `web_private_nic_boot_gate` (both warning stages must be in its
`tagged_event` set). The address is `${private_ip}` from the template map — the empty-render
case is a member.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pipe `ip … \| grep` so a failing `ip` reads as "absent" | RED (stub `ip` exiting 1 must yield probe_fault, not timeout) |
| 2 | Drop the empty-address guard; render `private_ip=""` | RED (must emit probe_fault, not proceed as ready) |
| 3 | Guard's own dispatch: the wait loop body never runs yet the item proceeds as if it waited | RED (recording `sleep` stub shows 0 sleeps on the never-present fixture) |
| 4 | Second event after a compliant first: emit `private_nic_timeout` AND `private_nic_probe_fault` | RED (exactly one) |
| 5 | Rename the timeout stage to `private_nic_wait_timeout` | RED (not in `web_private_nic_boot_gate`) |
| 6 | REORDER: move the wait after the zot login | RED (the login stub records being called before the address appeared) |

**Harness rows.**

- H1 (suite edit): make the `ip` stub ignore argv → the argv-validation row must RED
  (an argv-blind stub is the #6415 hole).
- H2 (must-PASS): address appears on the 10th poll → PASS, no `private_nic_*` emit, `app_zot`
  detail contains `nic_w=20`.

**Anchor.** Not a stored-value comparison.

### Guard 3 — no Doppler invocation above the terminal block's exporting source

**Property.** No `doppler` invocation exists in `cloud-init.yml` runcmd before the terminal
block's `set -a; . /etc/default/webhook-deploy; set +a`, so no call site can run tokenless.

**Assembly.** A census over the non-comment lines of `cloud-init.yml` between `runcmd:` and that
anchor line, matching the call form (`doppler` followed by a subcommand — `secrets`, `run`,
`configure`), not layout. Covers every item in that span, including the colocated-inngest item.
The anchor itself is a member: if it is missing, the census has no end and must fail.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `_emit`'s `doppler secrets get SENTRY_DSN` fallback | RED |
| 2 | Add a `doppler secrets get X` line in the seed item after a compliant file | RED |
| 3 | Guard's own dispatch: rename/remove the terminal `set -a; . /etc/default/webhook-deploy` anchor | RED (census span undefined is a failure, not 0) |
| 4 | Second member: a clean seed item plus a Doppler `ZURL=` read in the colocated-inngest item | RED |

**Harness rows.**

- H1 (suite edit): census regex changed to match nothing → the floor assertion (the same census
  run over the region *after* the anchor finds ≥1, proving the regex can match) must RED.
- H2 (must-PASS): a comment line mentioning `doppler secrets get` above the anchor → PASS.

**Anchor.** Not a stored-value comparison.

### Guard 4 — boot-trail QUERY ↔ emit lockstep includes the image-origin message

**Property.** The replace job's boot trail can surface the event that says which registry
served a fresh web boot.

**Assembly.** `fresh-host-boot-trail.sh` `QUERY=` and its derived `MSG_RE`, and the AC8
two-way lockstep in `soleur-host-bootstrap-observability.test.sh` (existing guard, extended).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `message:"app image served"` from QUERY | RED (AC8 forward direction) |
| 2 | Rename the `app_zot` emit message in `cloud-init.yml` | RED (the reverse pair is the full `app image served by zot`, not the QUERY prefix — the prefix alone stays satisfied by the GHCR messages) |
| 3 | Guard's own dispatch: QUERY line not found | RED (existing AC8 floor) |
| 4 | Add the fallback message with its literal `(zot miss)` to QUERY | RED (a regex-metachar literal in QUERY; AC8 asserts no `(` in extracted literals) |

**Harness rows.**

- H1 (suite edit): AC8 loop list emptied → the "AC8-16 floor" style assertion must RED.
- H2 (must-PASS): QUERY literal order permuted → PASS.

**Anchor.** Not a stored-value comparison.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Export the Doppler token (`set -a`) at the seed block and keep the Doppler reads | Keeps a network dependency on Doppler in the cold-boot critical path, and revives ~10 never-run call sites at once including the revoked-PAT re-fetch (#6985's own blast-radius warning; CTO review R2). Kept only inside `_emit`'s subshell. |
| Keep the `/v2/` probe, move it after a NIC wait | A probe that fails open to a dead leg is the #8651 shape; the bounded pull is a strictly better probe. |
| Delete the GHCR leg from the web fresh boot | That is #8036 1d / ADR-096 5.3 territory, soak-gated; the #6285 tripwire comment names it. Gating the GHCR attempt on a successful login gives the fail-closed-at-login property without retiring anything. |
| Template-time elision of the GHCR leg (`%{ if … }`) | `ghcr_read_token` is a required no-default variable carrying a revoked but non-empty value, so a template condition cannot tell "dead" from "live"; it would need a new variable — retirement scope again. |
| Bake a copy of `soleur-wait-nic` for pre-pull use | Impossible without the image; inline is the only placement. |
| Change the close criterion to "app_zot observed" only (advisor) | The operator's stated proof is a zot-served pull **with GHCR failing and non-fatal**; the `ghcr_login=fail` detail on `app_zot` satisfies both at no extra cost. Kept as stated. |

Deferrals: none new. The mutable-`:latest` hazard (`var.image_name` default) is scoped out
with its guard named (`host-image-coherence-preflight.sh` refuses a non-`@sha256` ref on every
automated route; a `:latest` ref could reach `user_data` only through an un-gated apply outside
every workflow, and zot mirrors the same tags CI dual-pushes). Bootstrap's own bare-dot Doppler sources
(`soleur-host-bootstrap.sh` `STAGE=ghcr_login`) stay on #6985 — changing host-scripts would
break the replace preflight (see Proposed Solution).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing immediately (merge touches no live
  host); the latent failure is that the next replacement of a web host — including web-1, the
  sole live origin — boots dark and the web app is unreachable until another replace succeeds.
- **If this leaks, the user's workflow is exposed via:** the baked zot **pull** credential in
  web-host `user_data` (metadata API) — read-only access to the app's container images, which
  contain application code but no user data; strictly weaker than the Doppler token already
  baked there.
- **Brand-survival threshold:** `aggregate pattern`

## Risks

- **Byte budget** (~184 B gz headroom). Mitigation: deletions land first, measured; comments
  stay in `server.tf`/ADR; budget raise only from a CI line with the test's standard rationale.
- **templatefile escaping.** Every new shell `${…}` must be `$${…}`; `%{` is a directive. The
  terraform-render leg of the new test is the only thing that catches this before a host does.
- **errexit scope.** The seed item runs under `set -e`; every new fail-open step must be
  `|| true`-guarded or subshelled, and the item's closing `set +e` must remain (H3, #6090).
- **Pinned digest absent from zot.** The replace pins web-1's running version, and web-1's
  deploy path has been zot-only since #8036 1c, so that digest was served by zot (`crane copy`
  preserves the index digest — `reusable-release.yml` "digest preserved → zot manifest
  byte-identical"). Residuals: blob GC, and an `image_tag` override naming a release published
  with `allow_unmirrored_reason`. Phase 6.2 therefore dispatches with the default pin (no
  `image_tag` override); if the pull still fails, the fatal names `pull_err: … manifest unknown`
  instead of a GHCR 401.
- **Emit latency.** Each `_emit` is `curl --connect-timeout 5 -m 8 --retry 1`; the NIC event
  adds one emit before the pull, so a throttling Sentry adds up to ~17-31 s to a boot (the #6500
  measurement for this flag set). Accepted: the alternative is an unobserved wait.
- **Rotation staleness.** A future `random_password.zot_pull` rotation strands only fresh
  boots of hosts created before it (recorded in the ADR amendment).
- **Sentry-only evidence is forgeable with the public DSN** (zot-soak header note). The #8651
  close is backed by the replace run's own job log and the run URL, not by the event alone.

## Plan Review Revisions (2026-09-23)

Panel: DHH, Kieran, code-simplicity (eng), CTO (named devex lens). Applied (mechanical):

- Cut: `_emit` 4th-argument detail override (details go through `/run/soleur-stage-detail`);
  the subshell `set -a` (replaced by deleting `_emit`'s dispatch-dead Doppler DSN fallback —
  census of pre-anchor Doppler calls goes 11 → 0); the separate mutation test file (folded into
  one suite); the new `web-boot-image-origin.sh` (replaced by an out-of-slice origin line and a
  `--image-origin` mode in `fresh-host-boot-trail.sh`, one copy of the Sentry filter); the
  empty-endpoint branch and its scenario; the ready-path NIC emit.
- Fixed (Kieran): four existing test pins the plan would have broken now listed in Phase 4;
  login outcomes persisted across the GHCR subshell; fatal detail reordered to fit the 200-char
  cap with both legs; harness joins runcmd item 1 with the seed item and stops at
  `STAGE=extract`; Guard 4 reverse pair uses the full `app image served by zot`; corrected the
  false claim that `web_terminal_boot_fatal` pages a lone seed fatal; recording-`sleep` count
  scoped; default pin (no `image_tag` override) for the delivery replace.
- Added (CTO): zot login tail in the fatal detail; cross-template `zot=[`/`ghcr=[` parity
  assertion; post-change headroom recorded in the PR body with a follow-up below ~100 B.
- Surfaced, not applied (headless → `specs/feat-one-shot-8651-web-host-zot-primary-boot/decision-challenges.md`):
  DC-1 cut the NIC wait (operator scope, kept); DC-2 close-criterion wording (operator's kept).

## Acceptance Criteria

### Pre-merge (CI-verifiable)

- [ ] AC1 — `cloud-init-web-zot-seed.test.sh` executes the **rendered** seed item under stubs
  and asserts: first `docker pull` argv is `<registry_endpoint>/jikig-ai/soleur-web-platform@sha256:…`
  (digest carried unchanged); the `doppler` stub's spawn log is empty for the whole item; the zot
  `docker login` precedes the first pull; `/run/soleur-image-ref` holds the zot ref on success.
  (Guard 1; `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh`.)
- [ ] AC2 — Same suite, failure arms: zot pull failing (stub error text 160 chars) + GHCR login
  failing → item exits non-zero, **no** GHCR `docker pull` is attempted, and the Sentry POST
  body recorded by the `curl` stub carries message `soleur-hostscript-seed failed`,
  `stage":"pull"`, a detail of **≤200 chars** containing both `ghcr=[login=fail,not-attempted]`
  and `zot=[`, and `host_name":"soleur-web-2"` (render with `host_name="soleur-web-2"`). GHCR login succeeding → GHCR flip attempted and
  `app_ghcr_fallback` emitted exactly once.
- [ ] AC3 — NIC wait: address present → no `private_nic_*` emit, 0 sleeps, `nic_w=0` in the
  `app_zot` detail; converging on poll 10 → `nic_w=20`; never present → one `private_nic_timeout`
  after exactly 75 recorded 2 s sleeps and the item **continues**; `ip` failing every call → one
  `private_nic_probe_fault`; empty `private_ip` render → `private_nic_probe_fault`. (Guard 2.)
- [ ] AC4 — The census of `doppler` invocations in `cloud-init.yml` runcmd above the terminal
  block's `set -a; . /etc/default/webhook-deploy; set +a` is **0**, and the same census below
  the anchor is ≥ 1 (the regex can match). Measured at plan time on `origin/main`: **11** such
  sites above the anchor (`_emit` DSN ×2, GHCR Doppler ×4, zot login ×3, seed `ZURL=`,
  colocated-inngest `ZURL=`) — exactly the set this plan deletes or bakes. (Guard 3.)
- [ ] AC5 — The mutation section of `cloud-init-web-zot-seed.test.sh` drives every Guard 1–3
  mutation row RED and every must-PASS harness row green; each case confirms its mutation
  landed; harness failures exit 2. The cross-template parity assertion (web fatal detail and
  inngest `oci-pull-ALL-LEGS-FAILED` both use `zot=[` / `ghcr=[`) passes.
- [ ] AC6 — `git grep -nE '^[^#]*doppler secrets get (ZOT_|GHCR_)' apps/web-platform/infra/cloud-init.yml`
  prints nothing, and `git grep -nE '^[^#]*ghcr_login_ok_refetch' apps/web-platform/infra/cloud-init.yml`
  prints nothing (the `^[^#]*` anchor keeps a comment that documents the removal from
  false-failing the check).
- [ ] AC7 — `git grep -nE '^[^#]*ZURL=.*doppler' apps/web-platform/infra/cloud-init.yml`
  prints nothing (both the seed site and the colocated-inngest site are baked).
- [ ] AC8 — `fresh-host-boot-trail.sh` `QUERY=` contains `message:"app image served"`;
  `soleur-host-bootstrap-observability.test.sh` AC8 passes both directions and rejects a
  metacharacter-bearing literal (Guard 4); with a fixture event list of 12 events whose oldest is
  `app_zot`, the trail's output still contains an `app_zot` line (the out-of-slice origin line),
  and `--image-origin` with no token prints `TRANSIENT:` and exits 2.
- [ ] AC9 — `plugins/soleur/test/cloud-init-user-data-size.test.ts` passes in CI; if
  `WEB_GZIP_BUDGET` moved, the diff shows the CI-measured render and the rationale comment in the
  file's established shape.
- [ ] AC10 — `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`,
  `cloud-init-ghcr-seed-login.test.sh` (with §1A re-scoped), `cloud-init-inngest-bootstrap.test.sh`
  (AC7 render with the two new map vars), `nic-wait-gate.test.sh`, the C4 tests
  (`c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`),
  `.github/scripts/validate-infra-templates.sh`, and `python3 scripts/lint-encryption-posture.py`
  all pass.
- [ ] AC11 — `git diff --name-only origin/main...HEAD` contains no path under
  `apps/web-platform/infra/` that is listed in `local.host_script_files` (so
  `host_scripts_content_hash` is unchanged and the replace job's coherence preflight still
  accepts web-1's running image).
- [ ] AC12 — Deterministic: `resource "hcloud_server" "web"`'s `lifecycle { ignore_changes = [...] }`
  in `server.tf` still lists `user_data` (asserted by the new seed test reading `server.tf`, so the
  property is about the diff, not about live state). Corroborating, not gating: the PR's
  infra-validation `terraform plan` shows no `user_data`-driven change to any `hcloud_server.web`
  instance (unrelated live drift can appear there and is out of this AC's scope).
- [ ] AC13 — ADR-096 carries "Amendment 2026-09-23 (#8651)" with the correction of the
  "Doppler answers EMPTY" premise; `grep -c 'dark-launch gated (attempts zot only when configured + /v2/-reachable + login ok)'
  knowledge-base/engineering/architecture/diagrams/model.c4` returns 0 (1 at plan time) and the
  edge describes the baked, zot-first fresh boot.
- [ ] AC14a — The PR body's first line answers "merging this alone mutates production: no" with
  the `ignore_changes = [user_data, …]` reason.
- [ ] AC14 — PR body uses `Ref #8651`, `Ref #6985`, `Ref #6500`, `Ref #6122`, `Ref #6438`,
  `Ref #8539` and no closing keyword for any issue; `git log origin/main..HEAD --format=%B`
  contains no `(close[sd]?|fix(e[sd])?|resolve[sd]?) #(6500|6122|6438|8651)` match
  (case-insensitive). `scripts/followthroughs/zot-soak-6122.sh` is unchanged
  (`git diff --quiet origin/main...HEAD -- scripts/followthroughs/zot-soak-6122.sh`).

### Post-merge (delivery — the only proof)

- [ ] AC15 — `web-host-replace` of `web-2` (`confirm=REPLACE-web-2`) completes with the
  "Surface fresh-host Sentry breadcrumb trail" step GREEN, and its trail shows, for
  `host_name=soleur-web-2` after the run anchor: an `app_zot` event whose detail contains
  `ghcr_login=fail` and `nic_w=`, and `fresh_boot_ready`. No `soleur-hostscript-seed failed`
  event.
- [ ] AC16 — The replace job's step summary contains the image-origin line for
  `soleur-web-2` showing `app_zot` with `ghcr_login=fail` in its detail, timestamped after the
  run anchor; the same line is reproducible locally with `fresh-host-boot-trail.sh
  --image-origin soleur-web-2` (token injected from Doppler, never printed).
- [ ] AC17 — #8651 is closed as **completed** only after AC15–AC16, with the run URL and event
  ids in the closing comment; `web-2` remains out of service. #6985 is closed as completed in the
  same step if its acceptance list is met (token scope, regression assertion, `:latest` scoped
  out with its guard, live verification); otherwise it gets a comment listing what remains.
  #6500, #6122, #6438 each get a `Ref` comment with the run URL; none is closed.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO concurs with the bake-over-export direction and zot-first with no probe.
Risks folded into this plan: byte budget is the dominant risk — delete before adding and
measure first (Phase 0.1/2.7); do not sweep bare-dot sources to `set -a` (revives ~10 unwatched
call sites) — limited to `_emit`'s own subshell; keep the GHCR leg but attempt it only after a
successful baked login, and emit `app_ghcr_fallback` only when GHCR was actually attempted; keep
`app_zot` / `app_ghcr_served` stage names byte-identical (#6462 denominator, zot soak);
`ignore_changes` covers every `hcloud_server.web[*]`, verify the PR plan shows no web diff; do
not touch host-scripts (coherence preflight); NIC-wait stage names must match
`web_private_nic_boot_gate` exactly or nothing pages; amend ADR-096 rather than a new ADR.
Residual noted: `random_password.zot_pull` rotation strands fresh boots of older hosts (ADR
amendment says so).

No Product/UX surface (no UI file in Files to Edit/Create); Product gate: NONE.

## Test Scenarios

1. Happy path: NIC ready at t=0, zot login ok, zot pull ok, GHCR login fails → `app_zot`
   (detail `zot_login=ok ghcr_login=fail nic_w=0`), image ref file = zot ref, item exits 0.
2. Late NIC: address appears at poll 10 → no NIC emit, then as (1) with `nic_w=20`.
3. NIC never converges → `private_nic_timeout`, zot login/pull fail (network unreachable stub)
   → fatal `stage=pull`, detail names `zot=[login=fail,…] ghcr=[login=fail,not-attempted]`.
4. zot manifest unknown (GC'd pin) → fatal detail carries the registry's `manifest unknown`
   tail within the 200-char cap.
5. GHCR credential restored (login stub ok) + zot down → flip after the bounded zot attempts,
   `app_ghcr_fallback` once, then `app_ghcr_served`.
6. Colocated-inngest render (`web_colocate_inngest=true`) → Guard 3's census is still 0.
7. Template render: the rendered YAML is valid (AC7 leg of `cloud-init-inngest-bootstrap.test.sh`)
   and contains no unescaped `${` shell expansion that terraform would have consumed.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- `cloud-init.yml` is a Terraform template: shell `${var}` must be `$${var}`; a missed escape is a
  render error at best and a silently-substituted empty string at worst. Test against the
  terraform render, never the raw file.
- runcmd is ONE `/bin/sh`: a new `set -e` or a missing `|| true` on a fail-open step aborts
  every later item for the life of the instance.
- Do not "fix" the soak blocker arm or its message to match the corrected mechanism — the arm's
  gate (`#8651` closed as COMPLETED) is correct regardless, and editing it is out of scope.
- Do not change anything under `local.host_script_files`: the replace job would refuse to run.
- The size test's local figure is ~32 B lower than CI's; re-derive any budget from the CI line.
- Never write a closing keyword next to #6500, #6122 or #6438 — not in the PR body, not in any
  commit message (the squash body appends branch commit messages; markdown is ignored).
