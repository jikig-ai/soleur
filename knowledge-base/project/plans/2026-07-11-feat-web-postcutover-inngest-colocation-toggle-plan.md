---
title: "feat: Gate co-located Inngest bootstrap on fresh web hosts behind web_colocate_inngest (default false)"
date: 2026-07-11
branch: feat-one-shot-6178-web-postcutover-inngest-config
epic: "#6178 (contextual — part of, NOT Closes)"
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: infra
---

# feat: Post-cutover web-host cloud-init — stop bootstrapping co-located Inngest

⚙️ **Part of epic #6178** (`arch: extract inngest to its own HA host`). This is a **contextual** citation.
The PR body MUST say "part of epic #6178" and MUST NOT say `Closes #6178` / `Fixes #6178` — the epic
stays open; this is one implementation slice, not the whole cutover.

## Overview

A freshly-recreated web host currently bootstraps, enables, and starts a **co-located** Inngest server
unconditionally. Scheduling is moving to the dedicated host `soleur-inngest` (`10.0.1.40`, ADR-100). This
PR introduces a reviewable Terraform toggle `web_colocate_inngest` (**default `false`**) and uses a
Terraform `templatefile` `%{ if … }` / `%{ endif }` directive to **gate the entire "Bootstrap Inngest
server on first boot" runcmd block** in `apps/web-platform/infra/cloud-init.yml`. When the toggle is
`false` (post-cutover default), a recreated web host does NOT extract/run `inngest-bootstrap.sh`, and
therefore never `enable`s/`start`s `inngest-server.service` nor `inngest-heartbeat.timer`. Making
host-recreate the quiesce mechanism (no SSH) satisfies `hr-prod-host-config-change-immutable-redeploy`.

**Code + tests only.** No `terraform apply`, no host recreate, no power on/off, no cutover op.
`INNGEST_BASE_URL` is explicitly out of scope (a separate PR handles the repoint).

### Why this is SAFE TO MERGE (verified)
- `hcloud_server.web` (`server.tf:93`, `for_each = var.web_hosts`) carries
  `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }` (`server.tf:195-196`)
  — applies to **every** existing web instance, so a `cloud-init.yml` edit does NOT re-render `user_data`
  on any running host. New config lands only on a fresh **create** (a recreate).
- The auto-apply workflow `apply-web-platform-infra.yml` is `-target=`-scoped to specific
  `betteruptime_*` / `cloudflare_ruleset` / `doppler_secret` resources — `hcloud_server.web` is **not** a
  target → the merge-triggered apply cannot replace a web host.
- The new variable has `default = false`, so the auto-applied infra root won't fail on a missing
  `TF_VAR_web_colocate_inngest` (HCL evaluates all root vars pre-`-target`-pruning; a no-default var
  would break the whole apply — this one won't).

Net: merging redeploys the app image (web-platform release) but recreates NO host. web-1's running Inngest
is unaffected until web-1 is retired; web-2 picks up the gated config on its next recreate.

## Research Reconciliation — Spec vs. Codebase

| Claim (task) | Reality (verified) | Plan response |
| --- | --- | --- |
| Inngest enabled unconditionally on fresh web host | Confirmed: `cloud-init.yml:636-694` runcmd item extracts + runs `inngest-bootstrap.sh`; enable/start/heartbeat live in `inngest-bootstrap.sh:504-506`, invoked at `cloud-init.yml:693`. | Gate the cloud-init item; do NOT touch `inngest-bootstrap.sh`. |
| Rendered by `templatefile(...)` at `server.tf:137` | Confirmed: `user_data = base64gzip(templatefile("${path.module}/cloud-init.yml", { … }))` (`server.tf:137`), map closes ~`:167`. | Add `web_colocate_inngest = var.web_colocate_inngest` to that map. |
| Dedicated host must NOT regress | Confirmed: `inngest-host.tf:201` renders a DIFFERENT file `cloud-init-inngest.yml`, which has its OWN bootstrap block (own IREF pin `v1.1.19`, `:330`). Shares `inngest-bootstrap.sh` but via its own extract path. | Gate ONLY `cloud-init.yml`. Leave `inngest-bootstrap.sh` + `cloud-init-inngest.yml` untouched. |
| Architectural decision recorded | Confirmed: `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` exists; C4 `model.c4:377` already annotates hosting edge `"removed from web cloud-init — ADR-100, #6178"`. | No new ADR; no C4 edit (see Architecture Decision gate). |
| `%{ if }` gate is implementable without breaking render | Verified via `terraform console`: col-0 `%{ if web_colocate_inngest ~}` / `%{ endif ~}` renders clean valid YAML for both `true` (block present) and `false` (block absent). Indented directive fails raw-parse AND corrupts render. | Use col-0 right-strip (`~}`) markers wrapping the whole runcmd item. |

## User-Brand Impact

**If this lands broken, the user experiences:**
- *Gate over-broad (accidentally strips host-script extraction / invalid YAML):* a recreated web host
  fails first boot → fail-closed `/run/soleur-hostscripts.ok` guard `poweroff -f`s the host → Better Stack
  per-host origin-absence check pages; web-1 keeps serving. No data exposed.
- *Gate under-broad (still co-locates post-cutover) OR dedicated host not yet ready when a web host
  recreates:* a Soleur user's scheduled reminder either **double-fires** (two schedulers) or **silently
  misses** (no reachable scheduler). Either is user-visible per user.

**If this leaks, the user's data is exposed via:** N/A — no data surface, no PII, no auth. This is a boot-
time systemd/service gate on infra config; it moves scheduling topology, it does not read or persist user data.

**Brand-survival threshold:** single-user incident (a single user's missed/duplicated scheduled reminder is
user-visible). → `requires_cpo_signoff: true`. `user-impact-reviewer` runs at review time. Mitigations: the
gate wraps exactly the bootstrap item (tests assert span-containment on both sides); the existing
`inngest-doublefire-probe` / `inngest-enumerate-reminders` scan guards double-fire; sequencing (below) keeps
the recreate path behind dedicated-host readiness + the separate `INNGEST_BASE_URL` repoint PR.

## Files to Edit

- **`apps/web-platform/infra/variables.tf`** — add:
  ```hcl
  variable "web_colocate_inngest" {
    description = "When true, a freshly-created web host bootstraps + enables the co-located inngest-server.service (pre-cutover behavior). Default false: scheduling lives on the dedicated soleur-inngest host (10.0.1.40, ADR-100, #6178). Recreate is the quiesce mechanism (hr-prod-host-config-change-immutable-redeploy)."
    type        = bool
    default     = false
  }
  ```
  Non-sensitive, has a default → no Doppler `prd_terraform` provisioning needed, no auto-apply break.

- **`apps/web-platform/infra/server.tf`** — inside the web `cloud-init.yml` templatefile map (the
  `templatefile("${path.module}/cloud-init.yml", { … })` at `:137`, before the closing `}))` near `:167`),
  add one line: `web_colocate_inngest = var.web_colocate_inngest`.

- **`apps/web-platform/infra/cloud-init.yml`** — wrap the "Bootstrap Inngest server on first boot" runcmd
  item with a `templatefile` conditional, using **col-0 right-strip markers** (verified render form):
  - Insert `%{ if web_colocate_inngest ~}` on its own **column-0** line **immediately before** the
    `  # Bootstrap Inngest server on first boot (#4118, Tier 1).` comment (currently `:636`).
  - Insert `%{ endif ~}` on its own **column-0** line **immediately after** the block's terminal
    `    trap - EXIT  # …` line (currently `:694`) and **before** the next runcmd item `  - |` (`:696`,
    the fail-closed app-bring-up gate).
  - Result (verified via `terraform console`): `web_colocate_inngest = true` → comment + block render
    intact; `= false` → the whole item vanishes, leaving valid YAML (`… .seed-complete` block directly
    followed by the fail-closed gate item). Do NOT change indentation of the block body; do NOT alter any
    existing `$${…}` escaping.

- **`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`** — two edits (see Test Strategy):
  1. **Fix AC3** (`cloud-init.yml parses as valid YAML`): the raw file now contains col-0 `%{ … }`
     templatefile directives, which `python3 … yaml.safe_load` rejects (`%` at col 0 = YAML directive
     indicator → `ScannerError`, verified). Pre-strip `^%{` lines before `safe_load`; ADD a rendered-both-
     -states YAML-validity assertion so the intent (rendered cloud-init is valid YAML) is strengthened,
     not weakened.
  2. **Add the toggle=false coverage** (new AC block): assert the gate markers exist and wrap exactly the
     bootstrap item, and that the gated-false render omits the bootstrap while the gated-true render keeps it.

### Files explicitly NOT edited (guardrails)
- `apps/web-platform/infra/inngest-bootstrap.sh` — shared with the dedicated host; the enable/start/heartbeat
  lines (`:504-506`) stay. The web gate prevents this script from being *invoked* on a fresh web host; its
  behavior for the dedicated host is unchanged.
- `apps/web-platform/infra/cloud-init-inngest.yml` + `inngest-host.tf` — the dedicated host's own render path.
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — passes unmodified (models block-present /
  worst-case size; the new map entry is an unused `${…}`-free var → never evaluated; ~60 B of directive
  text is negligible against the 21,000 B gzip budget). Run it to confirm green; do NOT change it.

## Implementation Phases

### Phase 1 — Terraform variable + wiring (contract first)
1. Add `variable "web_colocate_inngest"` to `variables.tf` (bool, default false).
2. Add `web_colocate_inngest = var.web_colocate_inngest` to the `cloud-init.yml` templatefile map in
   `server.tf`.
Contract lands before the consumer (Phase 2) so the directive has a defined var when rendered.

### Phase 2 — Gate the cloud-init runcmd block
1. Insert the `%{ if web_colocate_inngest ~}` (before the bootstrap comment) and `%{ endif ~}` (after the
   block's terminal `trap - EXIT`) col-0 directive lines in `cloud-init.yml`.
2. Verify render both ways with `terraform console`:
   `echo 'templatefile("./apps/web-platform/infra/cloud-init.yml", { …all-vars…, web_colocate_inngest=false })' | terraform console`
   → block absent; `=true` → block present. Both outputs `yaml.safe_load`-clean.

### Phase 3 — Tests
1. Update AC3 (strip `^%{`; add rendered-state YAML validity).
2. Add the toggle=false / toggle=true coverage block.
3. Run: `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`,
   `bunx --bun vitest run` for `plugins/soleur/test/cloud-init-user-data-size.test.ts` (or the repo's test
   command per `package.json`), and the infra `*.test.ts` suite (target-parity, web-hosts-fanout-parity,
   server-tf-set-e) to confirm no regression.
4. `terraform fmt -check` + `terraform validate` on `apps/web-platform/infra/`.

## Test Strategy

Primary assertions are **static + terraform-render**, matching the existing file's grep/awk + skip-when-tool-
absent convention. There is exactly one `if`/`endif` pair and no nesting, so an awk model of the directive is
faithful (verified to match `terraform console` output).

**AC3 fix (raw YAML validity with directives present):**
```sh
# strip col-0 templatefile directive lines before parsing the (non-rendered) source
grep -v '^%{' "$CLOUD_INIT" | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"
```
Plus a rendered-state check (below) so YAML validity of the *rendered* artifact is asserted directly.

**New toggle coverage:**
- **Markers present + placed:** exactly one `^%{ if web_colocate_inngest ~}$` and one `^%{ endif ~}$`; the
  `if` line precedes `# Bootstrap Inngest server on first boot`; the `endif` line follows the block's
  `trap - EXIT` and precedes the next `  - |` item.
- **Span containment (gate wraps the RIGHT content):** the text between the markers CONTAINS the IREF pin
  (`soleur-inngest-bootstrap:v…`) AND the `bash "$EXTRACT_DIR/inngest-bootstrap.sh"` invocation.
- **Nothing outside the span co-locates Inngest:** deleting the span (`awk` from `%{ if web_colocate_inngest`
  through `%{ endif`) yields a file with **no** `soleur-inngest-bootstrap` ref and **no** `inngest-bootstrap.sh`
  invocation → transitively no `enable/start inngest-server.service` / `inngest-heartbeat.timer` on a fresh
  web host. That deleted-span file also `yaml.safe_load`s clean (models `web_colocate_inngest=false`, matches
  `terraform console`).
- **toggle=true model:** removing only the two marker lines keeps the IREF pin present and `yaml.safe_load`s
  clean (models `web_colocate_inngest=true`).
- **Optional CI-authoritative leg (SKIP if `! command -v terraform`, mirroring the dash/visudo/git skips):**
  render via `terraform console` with all templatefile vars set to placeholders and `web_colocate_inngest`
  false/true; assert the false render lacks `soleur-inngest-bootstrap` and the true render contains it, and
  both parse as YAML. Var list to supply: `image_name, fail2ban_sshd_local_b64, host_scripts_content_hash,
  tunnel_token, webhook_deploy_secret, doppler_token, sentry_dsn, resend_api_key, ghcr_read_user,
  ghcr_read_token, ci_ssh_public_key_openssh` (+ `web_colocate_inngest`).

Existing assertions that MUST stay green (the gate must not disturb them): AC1 IREF pin shape, Config.Env
sourcing, composite EXIT-trap-calls-cleanup, AC4 positional (bootstrap precedes `--name soleur-web-platform`),
AC4 `bash -n`/`dash -n` snippet extraction (the extraction awk exits on the col-0 `%{ endif` line → directives
are NOT pulled into the shell snippet, verified against the awk logic), AC5 sudoers parity, AC6 pin drift-guard.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `variables.tf` declares `web_colocate_inngest` (bool, `default = false`, non-sensitive).
- [ ] `server.tf`'s `cloud-init.yml` templatefile map passes `web_colocate_inngest = var.web_colocate_inngest`.
- [ ] `cloud-init.yml` wraps the "Bootstrap Inngest server on first boot" item in col-0
      `%{ if web_colocate_inngest ~}` / `%{ endif ~}`, escaping (`$${…}`) unchanged.
- [ ] `terraform console` render with `web_colocate_inngest=false` omits `soleur-inngest-bootstrap` +
      `inngest-bootstrap.sh` and is `yaml.safe_load`-clean; with `=true` it includes them and is clean.
- [ ] `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → all PASS, 0 FAIL (AC3 fixed;
      new toggle block green; all prior ACs green).
- [ ] `plugins/soleur/test/cloud-init-user-data-size.test.ts` green **unmodified** (web gzip render < 21,000 B).
- [ ] Infra `*.test.ts` (target-parity, web-hosts-fanout-parity, server-tf-set-e) green.
- [ ] `terraform fmt -check` + `terraform validate` clean on `apps/web-platform/infra/`.
- [ ] `inngest-bootstrap.sh` and `cloud-init-inngest.yml` are byte-unchanged in the diff.
- [ ] (Read-only, review-time) `terraform plan` shows **no create/replace** of any `hcloud_server.web[*]`
      (proves SAFE-TO-MERGE; no apply is run in this PR).
- [ ] PR body: "part of epic #6178" (NOT `Closes`); documents rollback.

### Post-merge (operator) — Automation: none required
- None. Merging redeploys the app image only (no host recreate). No operator step, no apply. The
  behavioral change materializes when a web host is next recreated under the epic's cutover sequencing.

## Rollback (for PR body)
To restore the co-located scheduler (the immutable-redeploy reverse of the cutover's `op=rollback`
re-enable): set `web_colocate_inngest = true` — flip the `variables.tf` default (or set
`TF_VAR_web_colocate_inngest=true`) — then **recreate** the web host. Recreate is the quiesce/restore
mechanism; no SSH, no live mutation (`hr-prod-host-config-change-immutable-redeploy`).

## Sequencing note (epic-level, not this PR's blocker)
Because this PR recreates no host, merge order is flexible. But the cutover choreography must ensure that
before any web host is recreated with `web_colocate_inngest=false`, the dedicated `soleur-inngest` host is
serving AND the separate `INNGEST_BASE_URL` repoint PR has landed — else a recreated web host has no
reachable scheduler. That sequencing is owned by epic #6178, not gated here.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/variables.tf` — new `web_colocate_inngest` (bool, default false, non-sensitive).
- `apps/web-platform/infra/server.tf` — one new key in the existing `cloud-init.yml` templatefile map.
- `apps/web-platform/infra/cloud-init.yml` — one `%{ if }`/`%{ endif }` directive pair (no new resource).
- No new provider, no version-pin change, no `TF_VAR` secret (default supplied → nothing to mint in Doppler).

### Apply path
**cloud-init-only.** No `terraform apply` in this PR. `ignore_changes=[user_data]` means the config never
re-renders onto a running host; the new gate takes effect only on a fresh **create** (recreate) — the
immutable-redeploy quiesce path. No taint, no `-replace`, zero downtime on merge.

### Distinctness / drift safeguards
- `ignore_changes=[user_data, ssh_keys, image, placement_group_id]` on the `for_each` web resource keeps
  the cloud-init edit off existing hosts (web-1 AND web-2).
- `apply-web-platform-infra.yml` `-target=` set excludes `hcloud_server.web` → merge-apply cannot replace a host.
- Default `false` value keeps the auto-applied root's pre-`-target` var resolution from failing.

### Vendor-tier reality check
N/A — no vendor resource created.

## Observability

```yaml
liveness_signal:
  what: "fresh-web-host first-boot success (host-script extraction sentinel + app container up)"
  cadence: "on host create/recreate"
  alert_target: "Better Stack per-host origin-absence check (web-N.app.soleur.ai/health) + apex uptime"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf (existing); cloud-init.yml fail-closed poweroff gate"
error_reporting:
  destination: "Sentry via soleur-boot-emit (existing cloud-init emits: inngest_bootstrap fatal, host-script stages)"
  fail_loud: "true — /run/soleur-hostscripts.ok guard poweroff -f's a host whose boot failed (visible absence)"
failure_modes:
  - mode: "directive makes raw/rendered cloud-init invalid YAML"
    detection: "cloud-init-inngest-bootstrap.test.sh AC3 (rendered-state yaml.safe_load) + terraform validate in CI"
    alert_route: "CI red (pre-merge); at runtime a boot failure → fail-closed poweroff → Better Stack origin-absence page"
  - mode: "gate over-broad — strips host-script extraction / wrong content"
    detection: "new span-containment + size test (block still modeled) + terraform render test in CI"
    alert_route: "CI red (pre-merge)"
  - mode: "gate under-broad — web host still co-locates post-cutover (double scheduler)"
    detection: "inngest-doublefire-probe.sh + inngest-enumerate-reminders.sh (existing epic probes)"
    alert_route: "Sentry / cutover-verify state (existing #6178 tooling)"
logs:
  where: "journald → Better Stack Logs (source 2457081) via Vector on the app host"
  retention: "Better Stack Logs default"
discoverability_test:
  command: "echo 'templatefile(\"apps/web-platform/infra/cloud-init.yml\", {web_colocate_inngest=false, …})' | terraform console | grep -c soleur-inngest-bootstrap  # expect 0 (NO ssh)"
  expected_output: "0 (rendered false-state web cloud-init contains no co-located inngest bootstrap)"
```

## Architecture Decision (ADR/C4)

**No new ADR; no C4 edit.** The decision (dedicated single-host Inngest as the sole scheduler; removal of
web co-location) is already recorded in `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`.
This PR is one implementation slice realizing that decision — a contextual citation, not a new/amended ADR.

**C4 completeness check (read all three `.c4` files):** `model.c4` models `inngest` as its own container
(`:184`, description already cites ADR-100 + #6178 + "Extracted to its own single-host … node"); the hosting
edge `hetzner -> inngest` (`:377`) is **already annotated** `"…removed from web cloud-init — ADR-100, #6178"`;
the `api -> inngest` HTTP event edge (`:370`, "Sends events; serves functions") correctly REMAINS (the web
app still sends events to the dedicated host). Enumerated: external actors — none new; external systems —
none new (Hetzner/Doppler/GHCR already modeled); containers/data-stores — none new; access relationships —
the web→co-located-inngest topology edge does not exist as a separate element to remove (co-location was a
cloud-init detail, not a modeled edge), and the model already documents its removal. → **No `.c4` change; no
`views.c4` include change.** The three files (`model.c4`, `views.c4`, `spec.c4`) were read and require no edit.

## Domain Review

**Domains relevant:** none (infrastructure/tooling change).

No cross-domain business implications. No user-facing UI surface (no files under `components/**`, `app/**`).
Product/UX Gate: NONE (no UI-surface file in Files-to-Edit; mechanical override does not fire).
Engineering/infra concerns are captured in Infrastructure (IaC), Observability, and Architecture Decision
sections above. `user-impact-reviewer` will run at review time (single-user-incident threshold).

## Open Code-Review Overlap

None — no open `code-review` issue targets `apps/web-platform/infra/cloud-init.yml`, `server.tf`,
`variables.tf`, or `cloud-init-inngest-bootstrap.test.sh` for this change class.

## Risks & Sharp Edges

- **[YAML-validity, highest]** Col-0 `%{ … }` directives make the **raw** source non-`yaml.safe_load`-able
  (`%` at col 0 = YAML directive indicator). This is expected and handled by the AC3 fix (strip `^%{` before
  parse) + the rendered-state validity check. Do NOT try to "fix" it by indenting the directive — verified:
  indenting BOTH fails raw-parse AND corrupts the render (mis-nested list items).
- **Strip-marker form is load-bearing:** use right-strip `~}` on both `%{ if … ~}` and `%{ endif ~}`.
  Verified this produces clean YAML with no stray blank line between runcmd items in the `true` render and a
  clean list in the `false` render.
- **Placement is load-bearing for the `bash -n` snippet test:** `%{ if }` goes BEFORE the bootstrap comment
  (so the AC4 extraction awk, which starts at that comment, never sees it) and `%{ endif }` goes at col 0
  AFTER the block (the extraction awk exits on the first `^[^[:space:]]` line → directive excluded from the
  shell snippet). Confirmed against the awk in the test.
- **Do not modify `inngest-bootstrap.sh`.** Gating at the web cloud-init layer is sufficient; the dedicated
  host relies on the script's enable/start behavior.
- **A plan/AC that greps for the *absence* of a token** (e.g., "no `inngest-bootstrap.sh`") must run on the
  span-deleted render, not the raw file (the raw file always contains the block text inside the `if`).
- **Sharp edge (plan-time budget):** the size test passes unmodified only because the new map var is
  `${…}`-free (referenced via `%{ if }`, not `${}`) → never evaluated by the TS model. Do not rename the
  directive to `${web_colocate_inngest ? … : …}` or the model will try to substitute it.
