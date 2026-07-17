<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The only `systemctl reload docker` / `systemctl restart docker` references in this plan
     describe the EXISTING terraform_data.registry_insecure_config remote-exec + cloud-init
     invariants being PRESERVED (already routed through Terraform/cloud-init, not new manual
     operator steps). This plan adds NO new infrastructure, server, or manual provisioning; it
     refactors an existing IaC-managed resource. See ## Infrastructure (IaC) below. -->

---
title: "fix(infra): derive docker insecure-registries from local.registry_endpoint + make the drift guard non-self-referential (#6448)"
issue: 6448
type: fix
lane: single-domain
brand_survival_threshold: none
date: 2026-07-17
branch: feat-one-shot-6448-registry-endpoint-derive-drift-guard
---

# fix(infra): derive docker `insecure-registries` from `local.registry_endpoint`, and make the drift guard actually detect drift (#6448)

## Overview

`local.registry_endpoint` (`apps/web-platform/infra/zot-registry.tf:44` = `"${local.registry_private_ip}:5000"`, derived from the single-source IP at `:40`) is the canonical `host:port` for the self-hosted zot registry. It already feeds `tunnel.tf:107` and the `ZOT_REGISTRY_URL` Doppler secret (`zot-registry.tf:253`).

But the same `10.0.1.30:5000` endpoint is **independently hardcoded** as a literal in three *live* (non-comment) places, with **no drift guard that can detect divergence from the local**:

| Live literal site (current) | Content |
| --- | --- |
| `apps/web-platform/infra/docker-daemon.json:7` | `"insecure-registries": ["10.0.1.30:5000"]` |
| `apps/web-platform/infra/cloud-init.yml:446` | `"insecure-registries": ["10.0.1.30:5000"]` (fresh-host inline daemon.json) |
| `apps/web-platform/infra/server.tf:669` | `docker info … \| grep -q '10.0.1.30:5000'` (post-reload probe) |

The probe that *looks* like a guard is **self-referential by construction**. `server.tf:632` is `triggers_replace = sha256(file("${path.module}/docker-daemon.json"))` and `:650` is `provisioner "file" { source = "${path.module}/docker-daemon.json" }` — a **static file copy**, not a `templatefile()`. So the `:669` remote-exec greps the literal `10.0.1.30:5000` against the `docker-daemon.json` it just delivered, which hardcodes that same literal. It validates the file against a copy of its own content and **cannot detect drift from `local.registry_endpoint`**. `registry-insecure-config.test.sh` (CI) has the same defect: it `python3 json.load`s the raw file and asserts the literal `10.0.1.30:5000` is present — an assertion the file can never fail while it holds its own copy.

The result is the exact silent-failure shape of the #6400 postmortem: set `local.registry_private_ip = "10.0.1.31"` (a subnet renumber / region move like #6288) and network attaches at `.31`, cloud-init's `EXPECTED_IP` guard is healthy at `.31`, `local.registry_endpoint` → `.31:5000` so web hosts + CI pull from `.31:5000` — **but** `docker-daemon.json` still allowlists `.30:5000`, so dockerd treats `.31:5000` as *secure*, tries HTTPS against zot's plain-HTTP, and every pull fails. `server.tf:669` greps `.30:5000`, finds it, apply is GREEN; `registry-insecure-config.test.sh` passes, CI is GREEN; deploys fall back to GHCR (ADR-096, atomic) so it is invisible from the deploy pipeline.

**The fix** makes the `insecure-registries` allowlist DERIVE from `local.registry_endpoint` at all three live sites, and rebuilds the drift guard so it compares the *delivered/allowlisted endpoint against `local.registry_endpoint`* rather than grepping the file against a copy of its own content.

The mechanism is the one the codebase already **anticipated**: convert `docker-daemon.json` → `docker-daemon.json.tmpl` (a `templatefile()` whose `insecure-registries` value is `${registry_endpoint}`). `.github/scripts/validate-infra-templates.sh:27-30` states verbatim that this "is what lets #6448's `docker-daemon.json` be covered the day it becomes a `templatefile()`, with no edit here", and its fixture suite already models the exact shape (F9/F9b in `.github/scripts/test/fixtures-validate-infra-templates.sh:311-357`). `cloud-init.yml` is *already* a `templatefile()` source (`server.tf:160`), so the endpoint is threaded in as a new template var. The endpoint VALUE is unchanged (`10.0.1.30:5000` today), and the `.tmpl` renders **byte-identical** to the current file, so `triggers_replace` (a `sha256`) keeps its current value → **zero apply churn** on the running fleet.

This is a self-contained infra refactor. It does **not** touch web-2 teardown, the zot cutover, or GHCR credential paths (parallel sessions).

## Research Reconciliation — Spec vs. Codebase

The issue body cites line numbers from before merged PR #6458 (2026-07-15). Verified fresh against `origin/main`/worktree; line numbers shifted:

| Issue claim | Reality (verified) | Plan response |
| --- | --- | --- |
| `server.tf:571` `sha256(file(docker-daemon.json))` | Now `server.tf:632` | Locate by content, not line; guard tests already cite by content-anchor. |
| `server.tf:589` `provisioner "file" { source = … }` | Now `server.tf:650` | Same. |
| `server.tf:608` `docker info … grep -q '10.0.1.30:5000'` | Now `server.tf:669` | Same. |
| `cloud-init.yml:445` | Now `cloud-init.yml:446` (heredoc at `:438-448`) | Same. |
| `registry-insecure-config.test.sh:63,70` assert `.30` | Confirmed at `:62-63` (remote-exec grep) and `:69-70` (raw-file `in insecure-registries`); also `:35-36` (sha256(file)), `:38-40` (source=), `:80-83` (cloud-init⇄file agreement) | All of these break when the file becomes a template; each is reworked (see Phase 5). |
| `docker-daemon.json` is the only Terraform consumer, via `file()` | Confirmed: `server.tf` (`:632`, `:650`, `:669`) + `registry-insecure-config.test.sh` are the *only* live consumers; no runtime/server code reads it. | Rename to `.tmpl`; rework both consumers. |
| private-nic-guard.test.sh explicitly defers `:5000` surface to #6448 | Confirmed at `private-nic-guard.test.sh:487-489` ("Do NOT widen this assert to cover them without fixing that first: it would go red") | Update that stale forward-reference note (Phase 6); do NOT widen private-nic-guard — the `:5000` guard lives in `registry-insecure-config.test.sh`. |

**Premise Validation.** #6448 is OPEN (title `review: docker-daemon.json insecure-registries hardcodes 10.0.1.30:5000 …`). ADR-096 (self-hosted zot, `10.0.1.30:5000`, plain-HTTP on private net, atomic GHCR fallback) is the governing decision and is intact. The two anticipatory scaffolds (`validate-infra-templates.sh` header + fixtures F9/F9b) confirm the templatefile mechanism is the intended fix, not a novel approach. No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the registry pull path has an atomic GHCR fallback (ADR-096), so even a broken derivation degrades to GHCR pulls, never a user-facing outage. The realistic failure of *this PR* is a RED `terraform apply` (infra pipeline blocked) or a RED CI guard — both caught before merge, neither user-visible.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — the change moves a private-net registry `host:port` (`10.0.1.30:5000`) from a hardcoded literal to a derived one. No secret, PII, credential, or user data is involved; the endpoint is already public in comments, ADRs, and the C4 model.

**Brand-survival threshold:** none.

`threshold: none, reason: the registry pull path has an atomic GHCR fallback (ADR-096), so even a fully-broken derivation degrades to GHCR pulls rather than a user-facing outage; this fix REMOVES a latent silent-drift risk (the #6400 shape) rather than adding any user-facing surface.` (Required scope-out because the diff touches the sensitive path `apps/web-platform/infra/*.tf`.)

## Hypotheses (network-outage gate — opt-out)

The plan-network-outage gate fires *structurally* because the feature narrative names `terraform apply` and the affected resource `terraform_data.registry_insecure_config` carries `provisioner "file"`, `provisioner "remote-exec"`, and `connection { type = "ssh" }`. This plan is **not** diagnosing a network/SSH outage — it is a config-derivation refactor. Per-layer opt-out with artifact:

- **L3 firewall / DNS / routing — opt out.** The SSH `connection {}` block (`server.tf:634-640`), its host (`hcloud_server.web["web-1"].ipv4_address`), and the apply-time `-target` list are **unchanged by this PR** (verified: the diff touches only `triggers_replace`, the `provisioner "file"` source→content, the `:669` grep literal, and the delivered content). No firewall/DNS/route surface is modified, so no L3 diagnosis applies.
- **L7 TLS / application — opt out.** The one behavioral assertion (`docker info | grep -qF '<endpoint>'`) is preserved in shape and only has its literal *derived*; the reload-not-restart and malformed-JSON-guard invariants are preserved (Phase 3, guarded by `server-tf-set-e.test.sh` + `registry-insecure-config.test.sh`). Endpoint VALUE is unchanged (`10.0.1.30:5000`), so dockerd behavior on the live fleet is identical.

Telemetry for `hr-ssh-diagnosis-verify-firewall` emitted at plan time.

## Implementation Phases

### Phase 1 — Create the templatefile source (byte-identical)

`git mv apps/web-platform/infra/docker-daemon.json apps/web-platform/infra/docker-daemon.json.tmpl`, then change the single value line so the endpoint is the template var:

- `"insecure-registries": ["10.0.1.30:5000"]` → `"insecure-registries": ["${registry_endpoint}"]`

Every other byte (2-space indent, key order, the trailing `]\n}\n`) MUST be preserved so that `templatefile(".../docker-daemon.json.tmpl", { registry_endpoint = "10.0.1.30:5000" })` renders **byte-for-byte identical** to the pre-change `docker-daemon.json` (verified layout: `…"insecure-registries": ["10.0.1.30:5000"]\n}\n`). This keeps the `sha256` trigger value stable ⇒ zero replace/churn.

Naming: `.json.tmpl` is load-bearing — `validate-infra-templates.sh:224` dispatches `jq empty` JSON validation on `*.json|*.json.tmpl`, and `has_template_syntax` treats `${…}` as render-required.

### Phase 2 — Derive the local + rewire the resource (`server.tf`)

Add a local (locality: `server.tf`, near `terraform_data.registry_insecure_config`; discovery greps all `*.tf`):

```hcl
locals {
  # #6448 — the delivered docker daemon.json derives its insecure-registries
  # allowlist from local.registry_endpoint (the single source, zot-registry.tf:44),
  # so a subnet renumber propagates here automatically instead of drifting silently.
  docker_daemon_json = templatefile("${path.module}/docker-daemon.json.tmpl", {
    registry_endpoint = local.registry_endpoint
  })
}
```

Rewire `terraform_data.registry_insecure_config`:

- `triggers_replace = sha256(file("${path.module}/docker-daemon.json"))` → `triggers_replace = sha256(local.docker_daemon_json)`
- `provisioner "file" { source = "${path.module}/docker-daemon.json" … }` → `provisioner "file" { content = local.docker_daemon_json … }` (Terraform's `file` provisioner accepts `content` XOR `source`; `content` takes the rendered string — the file provisioner cannot `source` rendered content, so `content` is required here).
- Update the resource's leading comment (`server.tf:613-630`) so it no longer implies a static `file()` copy; cite `local.registry_endpoint` as the source. Keep the ADR-096 / `-target` / reload-not-restart rationale.

### Phase 3 — Derive the remote-exec probe + preserve HIGH-RISK invariants (`server.tf`)

- `"docker info 2>/dev/null | grep -q '10.0.1.30:5000'"` → `"docker info 2>/dev/null | grep -qF '${local.registry_endpoint}'"` (Terraform interpolates `local.registry_endpoint` into the inline string; `-qF` fixed-string so the `.`/`:` are literal). This is the meaningful runtime check: it confirms the *live* dockerd honors `local.registry_endpoint` after reload; when the IP changes to `.31`, the delivered daemon.json says `.31`, the probe greps `.31`, and if the delivered content ever failed to update, the probe fails RED.
- **Preserve** (do not touch): `"set -e"` as the first inline element (enforced by `server-tf-set-e.test.sh`), the `python3 -c 'import json; json.load(...)'` malformed-JSON guard *before* the reload, `chown/chmod`, and the SIGHUP reload directive (reload, NOT restart — so running containers are not bounced). The probe stays the terminal command of its inline array so its non-zero exit fails the apply.

### Phase 4 — Derive the fresh-host inline daemon.json (`cloud-init.yml` + `server.tf` map)

`cloud-init.yml` is already a `templatefile()` source (`server.tf:160`). Thread the endpoint in:

- `server.tf:160-226` templatefile map: add `registry_endpoint = local.registry_endpoint`.
- `cloud-init.yml:446`: `"insecure-registries": ["10.0.1.30:5000"]` → `"insecure-registries": ["${registry_endpoint}"]`. (The write is not inside a `%{ if }` directive, so `${registry_endpoint}` is always referenced ⇒ the map key is required and present.)
- Lightly update the explanatory comment at `cloud-init.yml:432` if needed so it does not restate a stale literal (it already says "= zot-registry.tf local.registry_endpoint" — keep the pointer).

### Phase 5 — Rebuild the drift guard (`registry-insecure-config.test.sh`) — the core of #6448

Rework the assertions that read the file as a static artifact so the guard proves **derivation-from-local**, not self-reference. New/changed assertions:

1. **Structural wiring (grep `server.tf`):**
   - `local.docker_daemon_json` is defined as `templatefile("${path.module}/docker-daemon.json.tmpl", { … })` and its map passes `registry_endpoint = local.registry_endpoint`.
   - `triggers_replace = sha256(local.docker_daemon_json)` (NOT `sha256(file(…))`).
   - the `provisioner "file"` uses `content = local.docker_daemon_json` (NOT `source =`), destination `/etc/docker/daemon.json`.
   - the remote-exec probe greps `${local.registry_endpoint}` (interpolated), NOT a literal. Anchor on the interpolation token so a re-hardcoded literal fails.
2. **Template shape (grep `docker-daemon.json.tmpl`):** the `insecure-registries` array value is `${registry_endpoint}`, and the raw `.tmpl` contains **no** `10.0.1.30:5000` literal. Preserve the existing valid-JSON check but run it against the *rendered* doc, not the raw template (raw would parse but hold the placeholder string).
3. **cloud-init derivation (grep):** `cloud-init.yml`'s `insecure-registries` value is `${registry_endpoint}`, and `server.tf`'s cloud-init templatefile map passes `registry_endpoint = local.registry_endpoint`.
4. **Single-source residual scan (adapt `private-nic-guard.test.sh:490-499`):** count **non-comment** occurrences of the endpoint literal `10.0.1.30:5000` across the derivation surface (`docker-daemon.json.tmpl`, `cloud-init.yml`, `server.tf`) and assert **zero** — the endpoint is never a live literal; it is only ever `${registry_endpoint}` / `${local.registry_endpoint}`. (The bare IP `10.0.1.30` legitimately remains once, at `local.registry_private_ip`, guarded by private-nic-guard; this scan is scoped to the `:5000`-suffixed endpoint.) Comment-strip like the sibling (`^[^#]*` for HCL/YAML; JSON has no comments).
5. **Mutation proof (credential-free `terraform console`, the load-bearing anti-self-reference test):** render `docker-daemon.json.tmpl` in an **empty scratch dir** (templatefile is a builtin — no `init`, no providers, preserving the credential-free contract, exactly as `validate-infra-templates.sh:82-84` does) with a **synthetic** endpoint `registry_endpoint = "10.99.99.99:5000"`; assert the rendered `insecure-registries[0] == "10.99.99.99:5000"` and the output contains **no** `10.0.1.30`. A hardcoded template emits `10.0.1.30` regardless of the var ⇒ this leg RED. Then render with the endpoint **extracted from `zot-registry.tf`** (`local.registry_endpoint` derivation) and assert the rendered value equals it (`registry_endpoint = local.registry_endpoint` wiring proven by Phase 5.1). Together with the residual scan, this is the mutation battery: a reintroduced hardcoded copy (in the template, the remote-exec grep, or cloud-init) fails at least one leg.
6. **Preserve** the still-valid HIGH-RISK assertions: resource-block extraction, reload-not-restart, JSON-guard-precedes-reload, every-remote-exec-opens-`set -e`, and the `-target` list membership (`-target=terraform_data.registry_insecure_config` in `apply-web-platform-infra.yml`). Update the `#6497` credential-convergence section only if an anchor it greps shifts (it should not).

Guard against the known false-pass classes (learnings): anchor on the JSON/HCL **construct**, not a bare substring (`2026-06-02`, `2026-06-03`); assert the *rendered* value, not the raw source, for anything interpolated (`2026-05-06`); define the mutation battery upfront and run every arm (`2026-07-16`); keep the guard's own logic out of `triggers_replace`'s blind spot (N/A here — the guard is a CI `.test.sh`, not an inline provisioner body).

### Phase 6 — Update the stale forward-reference in `private-nic-guard.test.sh`

`private-nic-guard.test.sh:487-489` says the `:5000` endpoint surface is "tracked in #6448. Do NOT widen this assert to cover them without fixing that first: it would go red." Update this note to record #6448 as resolved and point to `registry-insecure-config.test.sh`'s single-source scan as the owner of the `:5000` surface. **Do NOT widen** private-nic-guard's own `LIVE_LITERALS`/`ASSIGNS` asserts — keep its scope on the bare IP; the `:5000` guard lives in the sibling. (It stays green regardless: `docker-daemon.json.tmpl` uses `${registry_endpoint}`, so no bare `"10.0.1.30"` literal is added.) Cite content anchors, not line numbers (`cq-cite-content-anchor-not-line-number`).

### Phase 7 — Register nothing new; verify auto-coverage

No workflow edit is required:
- `registry-insecure-config.test.sh` already has a named step in `infra-validation.yml` (`deploy-script-tests` job) — it is reused, not added.
- `docker-daemon.json.tmpl` is **auto-discovered** by `validate-infra-templates.sh` the moment it becomes a `templatefile()` referent (discovery set A greps all `*.tf`), which renders it (`registry_endpoint` stubbed `"x"`) and `jq empty`-validates the JSON in the `validate` matrix job. Verify this by running the script locally against `apps/web-platform/infra`.

## Files to Edit

- `apps/web-platform/infra/docker-daemon.json` → **rename** to `apps/web-platform/infra/docker-daemon.json.tmpl` (`git mv`) + one value line (Phase 1).
- `apps/web-platform/infra/server.tf` — add `local.docker_daemon_json`; rewire `triggers_replace`, `provisioner "file"` (source→content), remote-exec grep; add `registry_endpoint` to the cloud-init templatefile map; update the resource comment (Phases 2, 3, 4).
- `apps/web-platform/infra/cloud-init.yml` — derive the inline daemon.json `insecure-registries` value (Phase 4).
- `apps/web-platform/infra/registry-insecure-config.test.sh` — rebuild the drift guard (Phase 5).
- `apps/web-platform/infra/private-nic-guard.test.sh` — update the stale forward-reference note only (Phase 6).

## Files to Create

- `apps/web-platform/infra/docker-daemon.json.tmpl` (via `git mv` of the existing file — preserves history).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` queried; no open scope-out names `docker-daemon.json`, `registry-insecure-config`, `server.tf`'s registry resource, or the cloud-init daemon.json write. The only cross-references to `docker-daemon.json` outside this plan's target files are the two anticipatory scaffolds in `.github/scripts/`, which require no edit.)

## Acceptance Criteria

### Pre-merge (PR / CI)

- [ ] `docker-daemon.json` no longer exists; `docker-daemon.json.tmpl` exists with `insecure-registries` value `["${registry_endpoint}"]` and **no** `10.0.1.30:5000` literal.
- [ ] `templatefile(".../docker-daemon.json.tmpl", { registry_endpoint = "10.0.1.30:5000" })` renders **byte-identical** to the pre-change `docker-daemon.json` (proves zero-churn; the `sha256` trigger value is unchanged).
- [ ] `server.tf`: `local.docker_daemon_json` is a `templatefile()` of the `.tmpl` passing `registry_endpoint = local.registry_endpoint`; `triggers_replace = sha256(local.docker_daemon_json)`; `provisioner "file"` uses `content = local.docker_daemon_json`; remote-exec greps `${local.registry_endpoint}` (no literal).
- [ ] `cloud-init.yml`'s `insecure-registries` value is `${registry_endpoint}`; `server.tf`'s cloud-init templatefile map passes `registry_endpoint = local.registry_endpoint`.
- [ ] Non-comment `10.0.1.30:5000` literal count across `docker-daemon.json.tmpl` + `cloud-init.yml` + `server.tf` is **0** (single-source residual scan).
- [ ] `registry-insecure-config.test.sh` mutation leg: rendering the `.tmpl` with a synthetic endpoint yields that endpoint (not `10.0.1.30`) — the guard is proven non-self-referential.
- [ ] `bash apps/web-platform/infra/registry-insecure-config.test.sh` → `0 failed`, exit 0.
- [ ] `bash apps/web-platform/infra/private-nic-guard.test.sh` → `0 failed`, exit 0 (unchanged behavior; stale note corrected).
- [ ] `bash apps/web-platform/infra/server-tf-set-e.test.sh` → passes (remote-exec `set -e` invariant preserved).
- [ ] `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra` → `rendered+validated N/N`, exit 0, and its output names `docker-daemon.json.tmpl` (auto-coverage).
- [ ] `bash .github/scripts/test/fixtures-validate-infra-templates.sh` → passes (F9/F9b unaffected).
- [ ] `cd apps/web-platform/infra && terraform fmt -check && terraform validate` pass (fmt-clean; `terraform_data` local + provisioner rewire is valid HCL).
- [ ] Manual mutation acceptance (the issue's phrasing): with a throwaway edit setting `local.registry_private_ip = "10.0.1.31"` and a copy left hardcoded at `.30` anywhere on the derivation surface, `registry-insecure-config.test.sh` goes **RED**; reverted, it is GREEN. (Documents that the self-referential green is gone.)

### Post-merge (operator)

- None. The change is applied automatically by `apply-web-platform-infra.yml` (the resource is in its SSH `-target` list). Because the `.tmpl` renders byte-identical to the prior file, `triggers_replace` is unchanged ⇒ Terraform performs **no replace** and the running fleet's `/etc/docker/daemon.json` is untouched. Fresh hosts render the same value from cloud-init. No SSH, no manual apply, no dashboard step.

## Infrastructure (IaC)

### Terraform changes

- Files: `apps/web-platform/infra/server.tf` (local + `terraform_data.registry_insecure_config` rewire + cloud-init map var), `apps/web-platform/infra/docker-daemon.json.tmpl` (new templatefile source), `apps/web-platform/infra/cloud-init.yml` (fresh-host derivation).
- No new provider, resource, variable, secret, or `TF_VAR_*`. No new Terraform root. `local.registry_endpoint` and `local.registry_private_ip` already exist.

### Apply path

- Path (c): none required beyond the existing automation. `terraform_data.registry_insecure_config` is already in `apply-web-platform-infra.yml`'s SSH `-target` list; the merge triggers the apply. Expected blast radius: **zero** — the `sha256(local.docker_daemon_json)` trigger value is identical to the prior `sha256(file(...))` value (byte-identical render), so no replace fires and no provisioner re-runs. Even in the counterfactual where a replace did fire, the delivery is a SIGHUP reload (running containers untouched) with a malformed-JSON pre-guard.

### Distinctness / drift safeguards

- `dev != prd`: N/A — single registry host, single endpoint local; no dev/prd fork in this surface.
- The whole point of the change is to eliminate the silent-drift class: after it lands, `local.registry_private_ip` → `local.registry_endpoint` propagates to every daemon.json copy and the runtime probe automatically; the CI single-source scan + mutation leg reject any reintroduced hardcoded copy.

### Vendor-tier reality check

- N/A — no vendor free-tier limit affects this refactor (Hetzner host + local docker config only).

## Observability

```yaml
liveness_signal:
  what: "terraform_data.registry_insecure_config remote-exec probe (docker info | grep -qF ${local.registry_endpoint}) confirms live dockerd honors the derived endpoint after reload"
  cadence: "every apply-web-platform-infra.yml run (on infra merge / manual apply)"
  alert_target: "apply-web-platform-infra.yml job failure (GitHub Actions run status)"
  configured_in: "apps/web-platform/infra/server.tf (remote-exec) + .github/workflows/apply-web-platform-infra.yml"
error_reporting:
  destination: "GitHub Actions run logs (apply-web-platform-infra.yml for apply; infra-validation.yml for the PR-time CI guard)"
  fail_loud: true   # apply probe is the terminal inline command; CI guard exits non-zero on any failed assert
failure_modes:
  - mode: "derivation wired wrong (template/map does not reference local.registry_endpoint)"
    detection: "registry-insecure-config.test.sh structural + mutation legs"
    alert_route: "infra-validation.yml deploy-script-tests RED (PR)"
  - mode: "hardcoded endpoint copy reintroduced on the derivation surface"
    detection: "registry-insecure-config.test.sh single-source residual scan"
    alert_route: "infra-validation.yml deploy-script-tests RED (PR)"
  - mode: "rendered daemon.json malformed JSON"
    detection: "validate-infra-templates.sh jq empty (CI) + remote-exec python3 json.load guard (apply)"
    alert_route: "infra-validation.yml validate RED (PR) / apply-web-platform-infra.yml RED (apply)"
  - mode: "dockerd does not honor the endpoint after reload"
    detection: "remote-exec 'docker info | grep -qF <endpoint>' probe"
    alert_route: "apply-web-platform-infra.yml RED (apply)"
logs:
  where: "GitHub Actions job logs (infra-validation + apply-web-platform-infra)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "bash apps/web-platform/infra/registry-insecure-config.test.sh && bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra"
  expected_output: "both exit 0; drift guard prints '0 failed'; validator prints 'rendered+validated N/N' including docker-daemon.json.tmpl"
```

No SSH is required to observe any failure mode; every signal is a GitHub Actions job result or a locally-runnable bash script.

## Architecture Decision (ADR/C4)

**No ADR.** This plan enforces an *existing* decision (ADR-096's single-source zot endpoint) by removing hardcoded copies; it makes no new or reversed architectural decision.

**No C4 impact — verified against all three model files.** Read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. The registry topology is already fully modeled: `zotRegistry` system (`model.c4:262`, description names `10.0.1.30:5000` and plain-HTTP-on-private-net), the `tunnel -> zotRegistry` edge (`model.c4:385`, `tcp://10.0.1.30:5000`), and `ghcr` as the fallback (`model.c4:258`). Enumerated for this change: (a) external human actors — none added; (b) external systems/vendors — none added (zot, ghcr already modeled); (c) containers/data-stores — none added; (d) actor↔surface access relationships — none changed (web hosts still pull from zot; the fix changes only *how the endpoint literal is sourced* inside the infra config, not who talks to whom). The endpoint value in the C4 descriptions is unchanged (`10.0.1.30:5000`), so no description is falsified. Therefore no `.c4` edit and no `views.c4` include change.

## Domain Review

**Domains relevant:** Engineering (infra/tooling).

### Engineering

**Status:** reviewed (CTO lens, carried into deepen-plan's multi-agent enhancement).
**Assessment:** Pure infra refactor enforcing ADR-096. No product/marketing/legal/finance/sales/support/ops implications. The mechanism (templatefile + credential-free `terraform console` mutation proof + single-source residual scan) matches established sibling patterns (`private-nic-guard.test.sh`, `validate-infra-templates.sh`) and the codebase's own anticipatory scaffolds. Risk is confined to CI/apply correctness, fully covered by the guard rework.

### Product/UX Gate

Not applicable — Product domain not relevant; the mechanical UI-surface override did not fire (no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit). NONE.

## Test Scenarios

1. **Happy path (today's value):** render `.tmpl` with the real endpoint → byte-identical to pre-change file; full guard suite GREEN; `terraform validate` clean.
2. **Subnet renumber (the fixed bug):** conceptually set `local.registry_private_ip = "10.0.1.31"` → `local.registry_endpoint` → `.31:5000` → every daemon.json copy + the probe derive `.31:5000`; the guard's mutation leg proves the template tracks the synthetic value. No drift possible.
3. **Reintroduced hardcode (regression the guard must catch):** hardcode `10.0.1.30:5000` back into `docker-daemon.json.tmpl`, `cloud-init.yml`, or the `server.tf` probe → single-source residual scan and/or mutation leg go RED.
4. **Malformed rendered JSON:** break the `.tmpl` JSON → `validate-infra-templates.sh jq empty` RED (CI) and the apply-time `python3 json.load` guard RED (apply).
5. **Auto-coverage:** `validate-infra-templates.sh apps/web-platform/infra` discovers `docker-daemon.json.tmpl` from the `.tf` call site alone and validates it — no harness edit.

## Risks & Mitigations

- **Non-byte-identical `.tmpl` → one-time apply churn.** If the implementer reformats the `.tmpl`, the `sha256` trigger changes and the resource replaces once (SIGHUP reload, running containers untouched — safe, but avoidable). *Mitigation:* AC asserts byte-identical render; preserve indentation and the trailing `]\n}\n`.
- **`terraform console` in the guard needs terraform on PATH.** `deploy-script-tests` installs terraform (`terraform_wrapper: false`), and a sibling render leg (`cloud-init-inngest-bootstrap.test.sh`) already relies on it. *Mitigation:* use the empty-scratch-dir builtin-`templatefile` technique (no `init`, no providers, no creds) exactly as `validate-infra-templates.sh` does; fail closed (not skip) if terraform is absent.
- **File-provisioner `content` vs `source`.** Terraform's `file` provisioner accepts `content` (a string) as an alternative to `source` (a path). *Mitigation:* AC includes `terraform validate`; this is the standard rendered-content delivery pattern.
- **Comment-prose false-pass in the guard.** *Mitigation:* the single-source scan is non-comment-scoped (`^[^#]*`), and construct-anchored assertions (not bare substrings), per learnings `2026-06-02` / `2026-06-03`.
- **`cloud-init.yml` col-0 `%{ }` directives break raw parsers.** The daemon.json write is not inside a directive; the new `${registry_endpoint}` is a plain interpolation. *Mitigation:* validation goes through the render-then-check path (`validate-infra-templates.sh` / the stripped schema check), never raw-parsing the interpolated value (learning `2026-07-11`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold fails `deepen-plan` Phase 4.6. This one is filled: threshold `none` with the required sensitive-path scope-out reason.
- The mutation proof MUST render the template with a value **different** from the real endpoint (`10.99.99.99:5000`) — a mutation battery only covers what it actually mutates (`2026-07-16`). Rendering only with the real value would pass on a hardcoded template.
- Do NOT widen `private-nic-guard.test.sh`'s bare-IP assert to cover `:5000`; the `:5000` surface is owned by `registry-insecure-config.test.sh`. Widening couples two guards and re-creates the scope-creep the sibling note warns against (`2026-05-11-drift-guard-scoping`).
