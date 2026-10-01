---
title: "infra: deny ghcr.io on the web hosts (/etc/hosts sinkhole + ghcr_blocked heartbeat)"
date: 2026-09-30
slug: infra-deny-ghcr-on-web-hosts
branch: feat-one-shot-9169-web-host-ghcr-deny
issue: 9169
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# infra: deny ghcr.io on the web hosts

## Enhancement Summary

**Deepened on:** 2026-09-30
**Sections enhanced:** Research Insights, Proposed Solution, Architecture, Implementation Phases,
Infrastructure (IaC), Downtime & Cutover (new), Network-Outage Deep-Dive (new), Architecture Decision,
Observability, Guard Contract, Acceptance Criteria, Test Scenarios, Non-Goals, Sharp Edges.
**Agents used:** `soleur:engineering:review:security-sentinel`,
`soleur:engineering:review:observability-coverage-reviewer`,
`soleur:engineering:review:test-design-reviewer`, `soleur:engineering:review:architecture-strategist`,
`soleur:engineering:research:framework-docs-researcher`, a verify-the-negative sweep (standard tier),
plus local measurements (Docker host-network `/etc/hosts`, `curl` to `0.0.0.0`/`::`, Better Stack,
`gh run` step conclusions). Halt gates 4.5 (resource-shape trigger), 4.55, 4.6, 4.7, 4.8, 4.10, 4.11
run; 4.9 not triggered (no UI surface).

### Key Improvements

1. **The deny runs in its own secret-free `remote-exec` block** on both resources. Both existing
   blocks reference sensitive values, so Terraform would have suppressed the FATAL text and a failure
   would have left a token/webhook-secret script in `/root` (security + observability + architecture).
2. **The container claim was false.** Bridge containers can reach GHCR through the GitHub CIDRs in
   the container egress allowlist, and `docker.pkg.github.com` is an undenied alias — both scoped out
   to #9275 with the reason (the alias needs a registry-template edit, i.e. a registry replace).
3. **Guards now parse instead of scanning lines:** render the template, `yaml.safe_load` runcmd,
   whole-entry parity (catches an extra command in the entry), `terraform console` for copy B,
   per-name `getent` shims with the IPv6 fixture, an in-suite mutation battery, and a block-anchored
   census exemption that also closes a pre-existing hole in the registry exemption.
4. **Blast radius corrected:** the web-2 re-fire restarts web-2's deploy listener (weight-0 host),
   and the `ci-deploy.sh` push restarts web-1's listener as every `ci-deploy.sh` change already does;
   `## Downtime & Cutover` records both and the zero-downtime default.

### New Considerations Discovered

- `cloud-init-registry.yml` must stay byte-identical: the registry host's `user_data` is ForceNew
  (AC16 + Sharp Edge).
- Measured: dockerd honours the deny (`zot-image-rehearse.sh` in CI), host-network containers carry
  the host's hosts file, and a connect to `0.0.0.0`/`::` fails in 0 ms.
- PM1 must check the SSH stage concluded `success` (a token-gate skip leaves the run green), and PM2
  treats `cancelled` (shared concurrency group) like red.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Mirror the registry-host ghcr.io name-resolution deny (PR #9147) onto the two web hosts (web-1
`soleur-web-platform`, web-2 `soleur-web-2`): sinkhole `ghcr.io` and
`pkg-containers.githubusercontent.com` in the hosts file and in cloud-init's hosts template, and
add a `ghcr_blocked` field to a web-host heartbeat so the deny is observable from Better Stack.
The change must reach both running hosts through the Terraform-owned apply route.

## Research Insights

### Premise Validation (Phase 0.6, measured 2026-09-30)

- **#9151 (the blocker) is CLOSED** (2026-09-30T01:02Z), delivered by PR #9212 (`bef6dd5a07`,
  `terraform_data.deploy_pipeline_fix_web2`) + hotfix PR #9247; the closing comment cites apply run
  36652454766 (`Creation complete after 44s`, parity arm green). Premise holds: unblocked.
- **Precondition 2 ("web-2's `IMAGE_VERIFY: ok` lines show the new ref") — HOLDS, measured three
  ways** via `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh`:
  1. `--since 3d --grep IMAGE_VERIFY`: every web release since 2026-09-29 15:58Z shows an
     `IMAGE_VERIFY: ok` row on `soleur-web-platform` AND `soleur-web-2` (latest pair
     2026-09-30 03:37:09Z / 03:38:24Z). `--grep IMAGE_VERIFY_FAIL` and `--grep cosign_absent` over 3d
     returned **zero** rows.
  2. Caveat, stated plainly: the `IMAGE_VERIFY: ok ref=` field is the **app image** ref
     (`10.0.1.30:5000/...@sha256:`), not the cosign verifier ref — the line cannot show the
     cosign ref by construction (`ci-deploy.sh` `logger ... "IMAGE_VERIFY: ok ref=$repo_digest"`).
     So the precondition was verified on the rows that DO carry it: `--grep projectsigstore`
     returns the post-verify prune row `untagged: gcr.io/projectsigstore/cosign@sha256:57c0e93a…`
     from `soleur-web-2` on every deploy from 02:12Z onward, and `--grep ghcr.io/sigstore` shows the
     LAST `ghcr.io/sigstore/cosign/cosign` row from `soleur-web-2` at **2026-09-30 01:29:42Z** —
     none after it (5 subsequent web-2 deploys, all gcr.io).
  3. `--since 12h --grep DEPLOY_SCRIPT_SHA`: web-2's newest rows carry
     `sha256=321c1e5662edce2fa5d7bfc3243dd6f65b2c07ecfc2ce7ce108d785459ef9c68`, which equals
     `sha256sum apps/web-platform/infra/ci-deploy.sh` at this branch's base — the script whose
     `COSIGN_IMAGE` is `gcr.io/projectsigstore/cosign@sha256:57c0e93a…` (ci-deploy.sh:148).
- **Nothing on the web hosts resolves ghcr.io for a fetch any more.** Better Stack census
  (`--since 2d --grep ghcr.io`, web hosts): the only remaining rows are (a) the deploy command's
  image NAME (`SSH_ORIGINAL_COMMAND: deploy web-platform ghcr.io/jikig-ai/...`, rewritten to zot by
  `ci-deploy.sh` before any pull), (b) deploy-status JSON echoing that name, (c) the pre-01:29Z
  web-2 cosign prune rows above. Repo census: `cloud-init-ghcr-seed-login.test.sh` Guard G1
  already asserts no GHCR credential/pull in any rendered template or baked host script;
  `git grep ghcr.io` over `apps/web-platform/{server,lib,app,Dockerfile}` returns nothing.
- **ADR corpus check (mechanism).** The mechanism (hosts-file sinkhole + `ghcr_blocked` field) is
  ADR-096's own "Amendment 2026-09-28 (#8714 step 5.3b-iii, part 2)", which names the web-host deny
  as "a tracked follow-up" — this issue. Not a rejected alternative.

**Deepen correction (2026-09-30).** The #9151 plan states `apply-deploy-pipeline-fix.yml` excludes
`server.tf` from `paths:`; the workflow on `main` lists it (and `ship-deploy-pipeline-fix-gate.test.ts`
pins that by set equality). The issue text's "the container egress allowlist names no GHCR host" is
true by name only — the CIDR allowlist admits GHCR's addresses (#9275).

### Property List (Phase 0.6b)

- **P1** — On both running web hosts (web-1 `soleur-web-platform`, web-2 `soleur-web-2`), `ghcr.io`
  and `pkg-containers.githubusercontent.com` resolve only to the sinkhole (`0.0.0.0` / `::`).
- **P2** — A freshly born or replaced web host comes up with the same deny, with zero operator
  action (`hr-fresh-host-provisioning-reachable-from-terraform-apply`).
- **P3** — Better Stack shows, per web host, whether the deny is in force (`ghcr_blocked=1`),
  without anyone logging in.
- **P4** — Web deploys still verify (`IMAGE_VERIFY: ok`, no `IMAGE_VERIFY_FAIL`, no
  `cosign_absent`) on both hosts after the deny lands.
- **P5** — The deny text cannot silently drift between its copies (fresh-boot template vs the
  running-host route) or re-open a ghcr.io pull path (the G1 census keeps its teeth).

### Cut List (Phase 0.6b)

- **"a web-host heartbeat" (the issue's proposed carrier) → P3 →** re-scoped, not cut. There is no
  periodic key=value web heartbeat that reaches BOTH running hosts: `disk-monitor.sh`,
  `resource-monitor.sh` and the `web-zot-consumer-probe` canary are delivered to running hosts only
  by web-1-pinned SSH resources (`disk_monitor_install`, `zot_consumer_probe_install`, server.tf),
  and web-2 receives them only at birth. `disk-monitor.sh` also emits only on failure. The one host
  script BOTH running-host routes already deliver is `ci-deploy.sh` (web-1: `deploy_pipeline_fix`
  webhook push; web-2: `deploy_pipeline_fix_web2`), and it already emits one per-invocation
  closed-vocabulary marker (`DEPLOY_SCRIPT_SHA`). P3 is bought by a sibling marker there.
- **A new dedicated `terraform_data` resource per host for the deny → P1 →** cut. Existing root
  SSH routes already reach each host (`zot_consumer_probe_install` for web-1 in
  `apply-web-platform-infra.yml`; `deploy_pipeline_fix_web2` for web-2 in
  `apply-deploy-pipeline-fix.yml`); a new resource would add `-target` lines, a Guard-1
  bridge-stage classification and a provisioner-parity floor bump for no additional property.
- **A new Better Stack alert on `ghcr_blocked=0` → P3 →** cut, parity with the registry precedent
  (#9147 shipped the field with no alert). The field is a queryable proof, and a regression
  surfaces at the point of use as `IMAGE_VERIFY_FAIL result=cosign_absent` only if cosign moves
  back to ghcr.io — which the G1 census blocks.

### Key file map (verified against this branch, base `aa4dc41ec5`)

- `apps/web-platform/infra/cloud-init-registry.yml:2328-2341` — the registry deny loop (precedent,
  byte source); `:984-991` — the `GHCR_BLOCKED` classifier (1 = only sinkhole, 0 = any routable
  address, `unknown` = unresolvable).
- `apps/web-platform/infra/cloud-init.yml:326` — web `runcmd:` start; first entry is the
  fatal-emit trap block. `hcloud_server.web` carries `ignore_changes = [user_data, ...]`
  (server.tf:502), so a cloud-init edit reaches only fresh/replaced hosts.
- `apps/web-platform/infra/server.tf:852-900` — `terraform_data.zot_consumer_probe_install`
  (Terraform provisioner, `connection.host` = web-1; `-target`ed by `apply-web-platform-infra.yml:1171`, post-bridge stage).
- `apps/web-platform/infra/server.tf:1968-2140` — `terraform_data.deploy_pipeline_fix_web2`
  (Terraform provisioner, `connection.host` = web-2 via the bastion forward; sentinel `"dpf-web2-remote-exec-v1"` in its
  `triggers_replace`; `-target`ed only by `apply-deploy-pipeline-fix.yml:422`).
- `apps/web-platform/infra/ci-deploy.sh:2999-3009` — `DEPLOY_SCRIPT_SHA` emit site (script runs
  `set -euo pipefail`, line 2); `scripts/check-deploy-script-parity.sh:105-106` parses
  `DEPLOY_SCRIPT_SHA sha256=[0-9a-f]{64}` — a separate marker line leaves that parser untouched.
- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh:289-332` — G1 census: a code line
  naming `ghcr.io` is a VIOL unless it is the `IREF=` pin carrier, a `GHCR_OK_TOKENS` token, or
  (only in `cloud-init-registry.yml`) one of `REGISTRY_DENY_LINES`; mutation rows 16/16b/16c and
  a measured row-count floor of 47 (`:597`).
- `apps/web-platform/infra/zot-image-fetch.test.sh:284-355,456-467` — the registry deny's
  executed-behaviour rows (R10: idempotent, exactly two lines per name) and classifier rows (H6).
- `plugins/soleur/test/cloud-init-user-data-size.test.ts:167` — `WEB_GZIP_BUDGET = 23_580`
  (~184 B headroom by its own comment); the deny block will likely need a CI-derived raise.
- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts:330-378` — the web-2 sibling's
  `triggers_replace` `file()` set must stay ⊆ TRIGGER_FILES ∪ {pin}; non-`file()` entries (a
  `local.*`, a sentinel) are not constrained by it.
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — destination-keyed guard: every
  absolute destination a web-1 SSH provisioner writes needs a fresh-boot counterpart.
- `.github/workflows/infra-validation.yml:540` — `apps/web-platform/infra/**.test.sh` is
  auto-registered by filesystem presence.

### Institutional learnings applied

- `knowledge-base/project/learnings/best-practices/2026-06-14-inline-remote-exec-body-outside-config-hash-is-a-silent-no-op.md`
  — an inline provisioner body is invisible to `triggers_replace`; the deny text therefore enters
  both resources' hashes through a `local`. Because the new inline text is itself hash-covered, the
  web-2 sentinel (`dpf-web2-remote-exec-v1`, whose convention exists for inline text the hash CANNOT
  see) is left unchanged — bumping it would also break the exact-text anchors of
  `web-host-provisioner-parity-mutation.test.sh` M4b/c/d (plan review).
- `knowledge-base/project/learnings/2026-06-10-terraform-remote-exec-gating-and-container-scoped-egress-allowlist.md`
  — remote-exec fails only on the last command unless `set -e` leads; containers do not see the
  host's `/etc/hosts` (their egress is governed by the cron-egress allowlist, which names no GHCR
  host). Scope of this change is host-level name resolution (dockerd pulls, host processes).
- `knowledge-base/project/learnings/best-practices/2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render.md`
  — budget is on `base64(gzip(render))`; re-derive a raise from the CI failure line.
- `knowledge-base/project/learnings/2026-09-28-a-replace-gate-on-one-route-and-an-isolation-that-shared-one-shell.md`
  — runcmd is ONE `/bin/sh` script; the deny loop uses only `f`/`h` and no credential, so it is
  safe as the first entry (same position as the registry precedent).
- Stale learnings NOT applied: "web-2 receives changes only on its next replace" and "remote-exec
  resources cannot be applied in CI" — both superseded by #9212 (web-2 SSH sibling applied by CI).

### Operational note carried from the lead

- `gh run rerun --failed` re-runs a workflow against its ORIGINAL merge ref; a newer pushed head is
  not picked up. A failed post-merge apply is re-driven with a fresh commit or a new
  `workflow_dispatch`, never a rerun.

### Functional overlap / community discovery

- `soleur:engineering:discovery:functional-discovery`: no community artifact covers a hosts-file
  deny + heartbeat field; nothing installed. Stack (Terraform/cloud-init/bash) is covered by
  `soleur:engineering:infra:terraform-architect`; no community-discovery gap.

### Plan Review Revisions (2026-09-30)

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer` (eng, threshold `none` → 3-seat baseline) plus the
named devex seat `soleur:engineering:cto`. Mechanical findings applied:

- **Cut:** the C4 description edit + `model.likec4.json` regen (no model change; DHH + simplicity);
  the apply-time `source=apply` logger and the `source=` field (green apply is the proof; DHH +
  simplicity); the executed-idempotence harness and redundant parity rows in Guard 2 (parity with
  copy R, whose execution R10 already proves; DHH + simplicity); Guard 1 rows keyed on table
  dispatch (DHH + simplicity); the parity-guard header note (simplicity); `terraform console` (Kieran).
- **Corrected:** the `ci-deploy.sh` probe line needs no census exemption — check (5) scans templates +
  `soleur-host-bootstrap.sh` only; host scripts go through the host-literal rule (Kieran). The web-2
  sentinel is NOT bumped: the new inline is hash-covered via the locals, and a bump would break
  `web-host-provisioner-parity-mutation.test.sh` M4b/c/d anchors; new trigger entries go above the pin
  line (Kieran + simplicity). AC8 reads the PR's sticky plan comment (no PR-time plan JSON exists);
  PM1 checks the SSH step concluded `success`, not `skipped`; one FATAL literal; untainted drift is not
  repaired by a dispatch (Kieran).
- **Added:** one `bash` execution of copy B (Terraform `inline` has no shebang); a default `getent` shim
  in `ci-deploy.test.sh`; a classifier-agreement table across the three "only the sinkhole"
  implementations (CTO devex); a Phase-5 retirement message in Guard 2's failures (CTO devex).
- **Taste / User-Challenge** items are persisted to
  `knowledge-base/project/specs/archive/20260930-144202-feat-one-shot-9169-web-host-ghcr-deny/decision-challenges.md`.

## Problem Statement

ADR-096 step 5.3b-iii asked to "re-scope, then remove, the GHCR egress allow". That allow was
measured as having no object (all five hcloud firewall rules are `direction=in`; host OUTPUT is
never filtered; the container egress allowlist names no GHCR host *by name* — deepen correction: its
CIDR half, `cron-egress-allowlist-cidr.txt`, admits `140.82.112.0/20` and `185.199.108.0/22`, which
contain ghcr.io and pkg-containers.githubusercontent.com, so bridge containers CAN reach GHCR; tracked
as #9275), so the step is realised as an **enforced, observed per-host deny**. The registry host got it in PR #9147 (live:
`ghcr_blocked=1`). The two web hosts still resolve `ghcr.io`: nothing on them pulls from it any
more, but that is a claim, not an enforced and observed fact. If ghcr.io is unavailable or
compromised, that can still reach anything on a web host that resolves the name — most importantly a future regression
that re-points the cosign verifier (the gate on every app release) back at ghcr.io.

## Proposed Solution

Mirror the registry precedent on the web hosts, and route it through the apply paths that
actually reach the RUNNING hosts:

1. **Deny text, one source per route, parity-tested.** The registry's 6-line POSIX loop
   (`cloud-init-registry.yml:2336-2341`), byte-identical, lands in:
   - `cloud-init.yml` as the **second `runcmd:` entry**, immediately after the #6090 fatal-emit
     trap-arm entry (which must stay at the top of runcmd) and before any package or image fetch —
     fresh births and replacements (P2);
   - a new `local.ghcr_deny_sh` heredoc in `server.tf`, executed by the two root SSH routes that
     already reach each running host (P1):
     - web-1: `terraform_data.zot_consumer_probe_install` (the web-1 root route whose subject is
       registry access; `-target`ed by `apply-web-platform-infra.yml` on every infra merge);
     - web-2: `terraform_data.deploy_pipeline_fix_web2` (the #9212 route; `-target`ed by
       `apply-deploy-pipeline-fix.yml`); its sentinel is left at `-v1` (see Research Insights).
   Both resources add `local.ghcr_deny_sh` (and the assertion local below) to `triggers_replace`,
   so the inline body is hash-covered — the
   `2026-06-14-inline-remote-exec-body-outside-config-hash-is-a-silent-no-op` class cannot bite.
2. **Apply-time in-band proof.** Each route runs `local.ghcr_deny_assert_sh` right after the deny.
   It asserts the POSITIVE form for both names (non-empty AND only `0.0.0.0` / `::`, following
   `zot-image-rehearse.sh:100-104` — an unresolvable name must not pass vacuously), fails the apply
   (`exit 1`) with a FATAL that names the route back (fresh commit or `gh workflow run`, never
   `gh run rerun --failed`). A green apply is itself the evidence of P1 on that host; no extra log
   line is emitted (plan review: the release marker below already reports the state per host).
3. **Heartbeat field (P3).** `ci-deploy.sh` emits a sibling closed-vocabulary marker right after
   `DEPLOY_SCRIPT_SHA`: `GHCR_DENY ghcr_blocked=<1|0|unknown>`, computed by a small fail-open
   function with the registry classifier's exact semantics (1 = resolves only to the sinkhole;
   0 = any routable address; `unknown` = does not resolve). It is emitted on every `ci-deploy.sh`
   invocation — i.e. on every release, on both hosts, next to the cosign verify it protects.
   `ci-deploy.sh` is the one host script BOTH running-host routes deliver, so the field reaches
   both hosts with no new delivery plumbing. (`apply-deploy-pipeline-fix.yml`'s `paths:` lists both
   `ci-deploy.sh` and `server.tf` — `.github/workflows/apply-deploy-pipeline-fix.yml` line ~72, pinned
   by `ship-deploy-pipeline-fix-gate.test.ts`'s paths set-equality row — so the web-2 deny re-fires
   on any future edit of the shared local too; it does not depend on `ci-deploy.sh` being touched.)
4. **Guards keep their teeth (P5).** Extend the G1 census's whole-line exemption from "registry
   template only" to the exact deny line (`for h in ghcr.io pkg-containers.githubusercontent.com; do`)
   in `cloud-init.yml` — nothing else. The `ci-deploy.sh` probe line needs no exemption: the census's
   whole-line rule (check 5) scans only the rendered templates + `soleur-host-bootstrap.sh`
   (`for f in derived + extras`), while host scripts such as `ci-deploy.sh` go through the narrower
   host-literal rule (a GHCR login or a `ghcr.io/jikig-ai/` pull), which a `getent ahosts ghcr.io`
   line does not trip — as today's `ci-deploy.sh` code lines naming `ghcr.io` already show. Mutation
   rows prove a pull appended to the admitted line is still a VIOL; add a small suite asserting the deny copies are byte-identical, wired into both
   routes, correctly ordered in runcmd, and that the three "resolves only to the sinkhole"
   implementations agree on the same fixtures. (Executing the loop itself is already covered for the
   byte source, copy R, by `zot-image-fetch.test.sh` R10 — parity makes a second execution redundant.)
5. **Record it.** ADR-096 amendment (5.3b-iii complete at template level on the web hosts, live
   proof = post-merge `ghcr_blocked=1` per web host). No C4 change (see Architecture Decision).

## Technical Approach

### Architecture

```text
fresh birth / replace ──► cloud-init.yml runcmd[1]  ── deny loop (copy A)
running web-1  ◄── apply-web-platform-infra.yml ── zot_consumer_probe_install ── local.ghcr_deny_sh (copy B) + assert
running web-2  ◄── apply-deploy-pipeline-fix.yml ── deploy_pipeline_fix_web2  ── local.ghcr_deny_sh (copy B) + assert
both hosts, every release ── ci-deploy.sh ── logger "GHCR_DENY ghcr_blocked=<v>" ──► Vector ──► Better Stack
registry host (unchanged) ── cloud-init-registry.yml runcmd ── deny loop (copy R, the byte source)
```

Copies A, B and R are asserted byte-identical after dedent (Guard 2).

Why host `/etc/hosts` is the right layer: `dockerd` performs every image pull on the host with the
Go resolver, which honours `/etc/hosts` under the default `hosts: files dns` order; the cosign
verifier pull is a `dockerd` pull. (Measured, not assumed: `zot-image-rehearse.sh` step 2 — "dockerd
could still pull from ghcr.io after the deny" → die — ran green in `zot-image-mirror.yml`'s `rehearse`
job on 2026-09-28 against the rendered registry deny.) The cosign verifier itself runs
`docker run --rm --network host` (`ci-deploy.sh`, the `"$COSIGN_IMAGE" verify --offline` call), and a
host-network container carries the host's hosts file (measured locally 2026-09-30, Docker 29.7.2:
`docker run --network host node:22-slim cat /etc/hosts` printed the host's file byte-for-byte, while a
bridge-network run printed Docker's generated one), so the deny covers the verifier's own resolution
too. **Bridge-network containers (the app, agent sandboxes) are NOT covered:** they resolve through
DNS, and the container egress CIDR allowlist admits GitHub's frontend ranges, which include GHCR —
out of scope here and tracked as #9275 (with the undenied `docker.pkg.github.com` alias). That split
is stated in the ADR amendment, not left implicit.

### Implementation Phases

**Phase 0 — RED tests first (`cq-write-failing-tests-before`).**

- 0.1 New `apps/web-platform/infra/web-ghcr-deny.test.sh` (auto-registered by
  `infra-validation.yml`'s `apps/web-platform/infra/**.test.sh` glob). Parse, don't scan lines
  (deepen: a guard over a structured language must lex it):
  - **Render, then parse.** Render `cloud-init.yml` through `terraform console` exactly as
    `cloud-init-web-zot-seed.test.sh` (its "Render (terraform templatefile)" block) does — the raw file
    is not valid YAML (`%{ if web_tunnel_connector ~}` at column 0) — and load `runcmd` with
    `yaml.safe_load`. Terraform absent: skip locally, FAIL under `CI` (the same fail-closed gate as
    that suite and `zot-image-fetch.test.sh`'s `R_RAN`). Do the same for `cloud-init-registry.yml`
    to get copy R as a parsed runcmd element.
  - **Copy B** is read from the dedicated deny `provisioner "remote-exec"` block (Phase 1.3/1.4) by
    evaluating `local.ghcr_deny_sh` with `terraform console` in a scratch root (heredoc `<<-`
    strips indentation itself; no hand-written dedent).
  - **Whole-entry parity:** runcmd element A == copy B == copy R, byte for byte — the WHOLE entry,
    so an extra command added to the entry (`: > /etc/hosts` names no ghcr.io and is invisible to
    the census) reds too.
  - **Ordering on the parsed list:** runcmd[0] contains `trap on_err EXIT`; runcmd[1] is copy A.
  - **One execution of copy B under `bash`** (Terraform's `inline` has no shebang; root's shell runs
    it), prefixed with `set -e` as the real block is, against synthesized temp files — after first
    asserting the path substitution removed every literal `/etc/hosts` from the script (so a root run
    can never touch the real file) — expecting one `0.0.0.0 <name>` and one `:: <name>` line per name.
  - **Classifier agreement,** with a `getent` shim that answers PER NAME: fixtures = sinkhole only;
    routable IPv4 only; sinkhole + routable; routable IPv6 containing `::` (`2606:50c0:8000::154`, the
    registry H6 fixture); unresolvable; and "ghcr.io sinkholed but pkg-containers routable". Run the
    registry classifier block (extracted from rendered copy R's heartbeat), `_ghcr_blocked_state`
    (sourced from `ci-deploy.sh` via a function-extraction seam) and `local.ghcr_deny_assert_sh`.
    Expected: `1`/pass, `0`/fail, `0`/fail, `0`/fail, `unknown`/fail, and for the last row the two
    classifiers say `1` (they probe ghcr.io only — by design, registry parity) while the assertion
    FAILS (it checks both names) — asserted as an expected difference, not agreement.
  - **Wiring, by parsed span:** strip HCL comments, then within each resource's own block (bounded
    by the top-level-block regex `ship-deploy-pipeline-fix-gate.test.ts` uses) assert both locals
    appear in the `triggers_replace` expression AND in a dedicated trailing `provisioner "remote-exec"`
    whose body references nothing but `"set -e"`, `local.ghcr_deny_sh` and `local.ghcr_deny_assert_sh`
    (no `var.`, no `doppler_`, no `hooks_json`, no `${` — Terraform suppresses a provisioner's whole
    output when its config holds a sensitive value, and a failed secret-bearing inline leaves its
    script in `/root`; deepen: security + observability + architecture).
  - **Consumer census:** across ALL `apps/web-platform/infra/*.tf`, every occurrence of
    `for h in ghcr.io` or of a write to `/etc/hosts` sits inside the two locals' definitions.
  - **In-suite mutation battery** (every Guard 2 row, applied to scratch copies, each required to red
    with the named check — not a one-off demonstration) plus a floor on assertions run.
  - Every copy-B/consumer failure message says: "the deny must move to the successor route or be
    retired with it (active-active Phase 5, ADR-143); cloud-init copy A is the end state".
- 0.2 `ci-deploy.test.sh`: put the default `getent` shim on EVERY PATH the harness constructs
  (`git grep -n 'PATH=' apps/web-platform/infra/ci-deploy.test.sh` — `$MOCK_DIR`, `$qd`,
  `$_CET_FCDIR`, `$effective_path`, `$TEST_PATH_BASE` at plan time — so no invocation does a real
  lookup). Rows: (a) a HANGING `getent` shim → `ghcr_blocked=unknown` inside the `timeout 5` bound and
  the script's exit status equals a paired baseline run's; (b) an NXDOMAIN shim (exit 2) under
  `set -euo pipefail` → `unknown`, run continues to a later marker; (c) `DEPLOY_SCRIPT_SHA` then
  `^GHCR_DENY ghcr_blocked=(1|0|unknown)$`, each exactly once per invocation.
- 0.3 `cloud-init-ghcr-seed-login.test.sh`: Guard 1 rows (RED until Phase 1).
- 0.4 Measure the budget BEFORE editing anything else: render `cloud-init.yml` with the deny block
  inserted (scratch copy) through `plugins/soleur/test/cloud-init-user-data-size.test.ts`'s own
  render path and record the delta against `WEB_GZIP_BUDGET` (~184 B headroom per its comment). If
  the delta exceeds the headroom, the budget raise is a planned edit of this PR (Phase 3.1), not a
  surprise — and the YAML comment above the deny stays one line.

**Phase 1 — the deny on every route.**

- 1.1 `cloud-init.yml`: insert the deny as the second `runcmd:` entry (right after the trap-arm
  entry that ends with `_emit "soleur-cloud-init boot stage" runcmd_start info`) with a SHORT comment
  (the rendered comment bytes count against `WEB_GZIP_BUDGET`; put the long rationale in the ADR).
  The comment names why the sinkhole is `0.0.0.0`/`::` and never `127.0.0.1` (a loopback-resolving
  registry name is one Docker may treat as an insecure/local registry — unverified here, stated as
  the reason not to "fix" it; Guard 2 row 1 reds on it).
- 1.2 `server.tf` `locals`: add `ghcr_deny_sh` (heredoc, byte-identical to copy R's whole runcmd
  entry) and `ghcr_deny_assert_sh` (heredoc: `for h in ghcr.io pkg-containers.githubusercontent.com;
  do a=$(getent ahosts "$h" | awk '{print $1}' | sort -u); if [ -z "$a" ] || printf '%s\n' "$a" |
  grep -qvxE '0\.0\.0\.0|::'; then echo "FATAL: $h does not resolve ONLY to the sinkhole after the
  deny (#9169). Route back: the resource is now tainted, so push a fix commit or gh workflow run the
  owning apply workflow; never gh run rerun --failed." >&2; exit 1; fi; done` — the ONE FATAL
  literal; every AC greps `FATAL: .* (#9169)`), with a comment naming both consumers and Guard 2.
- 1.3 `zot_consumer_probe_install`: add both locals to `triggers_replace`; add a NEW, LAST
  `provisioner "remote-exec" { inline = ["set -e", local.ghcr_deny_sh, local.ghcr_deny_assert_sh] }`
  — separate from the existing token-bearing block, so (a) the FATAL text is not swallowed by
  Terraform's sensitive-output suppression, (b) a failure never leaves the Doppler-token script in
  `/root`, (c) the token re-delivery has already completed. Confirm the existing body is idempotent
  (two `file` provisioners overwrite the same bytes, the env file is rewritten from the same inputs
  under `umask 0137`, `daemon-reload`, `enable --now` on an already-enabled timer) and say so in the
  PR body. Header comment: `# also carries the ghcr.io hosts-file deny (#9169; Guard 2)`.
- 1.4 `deploy_pipeline_fix_web2`: add both locals to `triggers_replace` ABOVE the
  `file(".../web-2-ssh-host-key.pub"),` line (the pin line and the `"dpf-web2-remote-exec-v1",`
  sentinel after it stay adjacent and byte-identical: `web-host-provisioner-parity-mutation.test.sh`
  M4b/c/d anchor on exactly those two lines, and M4f on the first `remote-exec` block); leave the
  sentinel at `-v1` and amend the resource's sentinel comment to "bump on any inline edit the
  `triggers_replace` locals do not already cover"; add the same NEW, LAST, secret-free
  `provisioner "remote-exec"` block AFTER the existing post-file block (so it runs after
  `systemctl try-restart webhook` / `is-active`, and a deny failure cannot leave the new
  `hooks.json`/`webhook.service` unloaded); update the header comment, whose charter today is "the
  FILE_MAP file set", to name the hosts-file deny as its one non-file duty; re-run
  `web-host-provisioner-parity.test.sh` §1, which treats this resource as the only web-2 dialer.
- 1.5 `cloud-init-ghcr-seed-login.test.sh`: widen the whole-line exemption (today
  `f == "cloud-init-registry.yml" and s in REGISTRY_DENY_LINES`) to a `{file: {lines}}` table that
  admits the deny header in `cloud-init.yml`, and make the exemption BLOCK-anchored for both files:
  the header line is admitted only when its whole runcmd entry equals copy R (closes the hole where
  an exempt header is followed by `docker pull "$h/jikig-ai/…"`, which names no ghcr.io literal on the
  pull line — the registry exemption has the same hole today). Add the Guard 1 rows; re-pin the
  row-count floor.
- 1.6 `web-host-provisioner-parity.test.sh`: it reads LITERAL destinations in server.tf, so the
  deny's `/etc/hosts` write — reached through `local.ghcr_deny_sh` — is invisible to it (it would
  fail open, not red). Guard 2 owns this destination's fresh-boot parity explicitly (copy A ≡ copy
  B). Run both parity suites unchanged; re-pin floors only if a measured count moves.

**Phase 2 — the heartbeat field.**

- 2.1 `ci-deploy.sh`: add `_ghcr_blocked_state` (prints exactly one of `1|0|unknown`; every
  command `|| true`/`if`-guarded because the script runs `set -euo pipefail`; `getent` bounded with
  `timeout 5` when `timeout` exists; probes `ghcr.io` only — registry-classifier parity; defined as
  a column-0 `_ghcr_blocked_state() {` … `}` function so tests extract it with the existing
  `sed -n '/^_name()/,/^}/p' "$DEPLOY_SCRIPT"` seam, as `ci-deploy.test.sh` does for
  `_cred_redact_env_values`) and emit
  `logger -t "$LOG_TAG" "GHCR_DENY ghcr_blocked=$v" 2>/dev/null || true` immediately after the
  `DEPLOY_SCRIPT_SHA` line. In `ci-deploy.test.sh`, put a default `getent` shim on the harness PATH
  so the many existing invocations never do a real lookup (which could stall up to 5 s each on a
  no-network runner).
- 2.2 Verify `scripts/check-deploy-script-parity.sh` and every other `DEPLOY_SCRIPT_SHA` /
  `IMAGE_VERIFY` consumer is untouched (`git grep -n 'DEPLOY_SCRIPT_SHA\|IMAGE_VERIFY' -- scripts
  apps .github`), because the new line is a separate marker. Before writing the marker, `git grep`
  for any closed list of allowed `ci-deploy` logger markers (in `ci-deploy.test.sh`, the `scripts/followthroughs/` probes,
  Better Stack alert predicates) and extend it if one exists.
- 2.3 Fix the stale comment at the cosign verify site (`ci-deploy.sh`, the block beginning "Verify via
  the pinned cosign container (ADR-087 Design B′). The app image is a PRIVATE GHCR package") so it no
  longer describes a GHCR-served `.sig` fetch that #8036 1c removed — the `.sig` comes from zot. A
  one-line drive-by in its own commit, in a file this PR already edits.

**Phase 3 — budgets and records.**

- 3.1 Run `plugins/soleur/test/cloud-init-user-data-size.test.ts`. If `WEB_GZIP_BUDGET` reds,
  raise it from the CI failure line (never the local one) with the comment convention of the
  file's previous raises; confirm it stays far below `HETZNER_CAP`.
- 3.2 ADR-096: add "Amendment 2026-09-30 (#9169) — the web hosts deny ghcr.io"; update the
  status bullets that say the web-host deny is a follow-up.

**Phase 4 — post-merge (automated routes only).**

- 4.1 The merge fires `apply-web-platform-infra.yml` (infra/** path; carries web-1) and
  `apply-deploy-pipeline-fix.yml` (`ci-deploy.sh` path; carries web-2). Watch both with
  `gh run watch`; both must be green, including the in-band `ghcr_deny_assert_sh`.
- 4.2 If either fails: re-drive with a fresh commit or `gh workflow run`, never
  `gh run rerun --failed` (it re-runs the ORIGINAL merge ref).
- 4.3 After the next web release (or a dispatched `web-platform-release.yml`), read Better Stack
  (Observability `discoverability_test`) and assert the post-merge ACs.
  (`apply-deploy-pipeline-fix.yml` fires on this PR through both `server.tf` and `ci-deploy.sh`.)

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Replace both web hosts (`web-host-replace` dispatch, ADR-148) so cloud-init alone carries the deny | Not available for web-1: `apply-deploy-pipeline-fix.yml`'s own recovery text (the `NO TERMINAL VERDICT` route-back, ~line 1373) says "Do NOT run terraform apply -replace=hcloud_server.web -- that host cannot be re-provisioned (cx33, 0/6 stock)", and `-replace` destroys before it creates. The exception to `hr-prod-host-config-change-immutable-redeploy` is therefore stated, not assumed: the change is Terraform-owned, hash-triggered and idempotent (no human SSH), copy A keeps the birth path authoritative, and the web-1 SSH route retires with active-active Phase 5. |
| Carry `ghcr_blocked` on the `web-zot-consumer-probe` canary (a true ~30-min heartbeat) | The probe reaches web-2 only at birth; delivering it through `deploy_pipeline_fix_web2` means widening TRIGGER_FILES and its SKILL.md/workflow lockstep for one field. Per-release cadence on `ci-deploy.sh` is at the point of use. Revisit if a periodic web heartbeat that reaches both hosts appears. |
| New dedicated `terraform_data.ghcr_deny` per host | Adds `-target` lines in two workflows, a Guard-1 bridge-stage classification and parity-floor bumps, and buys no property the two existing root routes do not. |
| Put the deny inside `infra-config-install.sh` (the webhook root helper) | Widens a deliberately narrow sudo boundary (the deploy user can invoke it with any args) to `/etc/hosts`; rejected on security grounds. |
| Put the web-1 deny in `infra_config_handler_bootstrap` (web-2 sibling's natural twin) | It is the break-glass lever the workflow's recovery text names; a failing assertion there would break the documented way back, and a re-fire restarts `webhook.service`. |
| Append `ghcr_blocked=` to the `DEPLOY_SCRIPT_SHA` or `IMAGE_VERIFY: ok` line | Those lines are parsed by `check-deploy-script-parity.sh`, `cosign-verify-live-8037.sh` and `ghcr-read-retired-8036.sh`; a separate marker leaves every existing parser byte-stable. |
| Better Stack alert on `ghcr_blocked=0` | Registry precedent shipped no alert; cut (see Cut List). |

## Non-Goals

- Bridge-network container resolution and egress (docker-generated `/etc/hosts`; the container CIDR
  allowlist admits GitHub's frontend ranges, which include GHCR) and the `docker.pkg.github.com`
  alias — both deferred to #9275 (adding the alias means editing `cloud-init-registry.yml`, whose
  `user_data` is ForceNew, i.e. a registry-host replace; see Sharp Edges).
- The inngest and git-data hosts. ADR-096 5.3b-iii's measured object was the registry host and the
  web hosts; the inngest template's `ghcr.io/...soleur-inngest-bootstrap` literal is the bump bot's
  pin carrier and is never pulled (G1 census).
- Stopping CI's GHCR push (ADR-169 restore source, `DECISION: B3`) — unchanged.

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — deny loop as the second `runcmd:` entry (right after the trap arm).
- `apps/web-platform/infra/server.tf` — `local.ghcr_deny_sh`, `local.ghcr_deny_assert_sh`;
  `zot_consumer_probe_install` and `deploy_pipeline_fix_web2` triggers + remote-exec (web-2
  sentinel unchanged; new trigger entries inserted above the pin line).
- `apps/web-platform/infra/ci-deploy.sh` — `_ghcr_blocked_state` + `GHCR_DENY` marker.
- `apps/web-platform/infra/ci-deploy.test.sh` — fail-open + once-per-invocation marker rows.
- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` — block-anchored exemption table (registry + web), mutation rows,
  floor re-pin.
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (conditional, Phase 3.1) —
  `WEB_GZIP_BUDGET`.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` 36 → 37
  with the PLACEMENT/TRUTH/NO SUBSTITUTE comment (do this FIRST in work: committing this plan already
  moved the count).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
  — amendment + status bullets.

## Files to Create

- `apps/web-platform/infra/web-ghcr-deny.test.sh` — Guard 2 (copy parity + classifier agreement +
  route wiring).

## Open Code-Review Overlap

1 open scope-out names a planned file: #2197 (billing `SubscriptionStatus` refactor; mentions
`apps/web-platform/infra/server.tf` only as an optional future CI check against `count`/`for_each`
while in-memory throttles exist). **Acknowledge:** different concern (billing rate-limiter
singletons); this plan adds no `count`/`for_each`. The scope-out stays open.

## Infrastructure (IaC)

### Terraform changes

- Root: `apps/web-platform/infra/` (existing; R2 backend unchanged). No new root, no new provider,
  no provider pin change, no new variable, no new secret, no new `TF_VAR_*`.
- `server.tf`: two new `locals` (`ghcr_deny_sh`, `ghcr_deny_assert_sh`, plain strings, no
  interpolation); `terraform_data.zot_consumer_probe_install` and
  `terraform_data.deploy_pipeline_fix_web2` gain both locals in `triggers_replace` and a NEW, last,
  secret-free `provisioner "remote-exec"` block running them; the web-2 sentinel is unchanged (the
  new inline text is hash-covered).
- `cloud-init.yml`: second `runcmd:` entry, after the trap arm (rendered by the existing
  `templatefile("${path.module}/cloud-init.yml", …)` for `hcloud_server.web`).
- No resource is created or destroyed; both `terraform_data` resources are REPLACED (re-provisioned)
  once because their hashes move — that is the delivery.

### Apply path

(b) cloud-init + idempotent re-provision of existing `terraform_data` siblings — the default for
existing infra. Fresh/replaced hosts get the deny from cloud-init; the running hosts get it when the
merge-triggered workflows re-fire the two resources:

- web-1: `apply-web-platform-infra.yml` job `apply`, step "Terraform apply (SSH-provisioned
  resources, over the bridge)" (`-target=terraform_data.zot_consumer_probe_install`), push-triggered.
- web-2: `apply-deploy-pipeline-fix.yml` (`-target=terraform_data.deploy_pipeline_fix_web2`),
  push-triggered because the PR edits `server.tf` and `ci-deploy.sh` (both in its `paths:`).

Downtime/blast radius: see `## Downtime & Cutover`. The deny itself restarts nothing (dockerd reads
`/etc/hosts` per lookup via the Go resolver). The web-1 resource re-runs
`systemctl enable --now web-zot-consumer-probe.timer` (no-op when enabled) and rewrites its env file
with identical content. The web-2 resource re-delivers the deploy-pipeline file set and ends with
`systemctl try-restart webhook` + an `is-active` assertion (server.tf, the post-file `inline` of
`deploy_pipeline_fix_web2`) — a restart of web-2's deploy listener that ANY `ci-deploy.sh` change
already triggers today; this PR's `ci-deploy.sh` edit alone would cause it.

Coupling check (measured, correcting a premise): the #9151 plan's deepen note says
`apply-deploy-pipeline-fix.yml` "deliberately excludes `server.tf` from `paths:` (R13)". The
workflow as merged LISTS `apps/web-platform/infra/server.tf` in `paths:` (its own comment: "server.tf
IS in this list (added long ago, kept)"), and `ship-deploy-pipeline-fix-gate.test.ts` pins that by
set equality. So a future edit of `local.ghcr_deny_sh` alone fires BOTH workflows and re-fires both
resources — no drift window between the hosts. Work re-verifies this with
`grep -n 'infra/server.tf' .github/workflows/apply-deploy-pipeline-fix.yml` before relying on it.

### Distinctness / drift safeguards

- No dev/prd split exists for these hosts (single prd root); no Supabase/Doppler config touched.
- `hcloud_server.web` `ignore_changes = [user_data, …]` is unchanged, so the cloud-init edit does not
  plan a server replacement (the destroy-guard filter must see no `hcloud_server.web` change —
  asserted in the Pre-merge ACs via `terraform plan`'s resource list, not eyeballed).
- No state-borne secret is added (both locals are non-secret literals).

### Vendor-tier reality check

No vendor resource is created. Better Stack ingestion of one extra short log line per `ci-deploy.sh`
invocation (a few dozen per day across two hosts) is negligible against the existing Source 4 volume.

## Downtime & Cutover

(deepen-plan Phase 4.55 — fired on the deploy/router class.)

- **Offline-inducing operation:** `deploy_pipeline_fix_web2`'s re-fire ends with
  `systemctl try-restart webhook` on web-2. For the second or two of that restart, a deploy POST to
  web-2's listener is refused. Nothing else in this change restarts a serving process: the deny is a
  file append, `zot_consumer_probe_install` only re-enables an already-enabled timer, and no
  `hcloud_server` attribute changes (`ignore_changes = [user_data, …]`).
- **web-1 side (pre-existing, unchanged):** the `ci-deploy.sh` edit also fires `deploy_pipeline_fix`
  (web-1's webhook push), whose handler schedules `systemd-run --on-active=3s … systemctl restart
  webhook` after every accepted push (`infra-config-apply.sh`, the "scheduling self-restart in 3s"
  branch). That is the standard delivery of every `ci-deploy.sh` change and is not new here;
  `infra_config_handler_bootstrap` is NOT re-fired (its hash inputs are untouched).
- **Surface affected:** the deploy listeners (`webhook.service`) only — a few seconds each. web-2 is serving-weight 0 (out of the load
  balancer pool, `variables.tf` comment near the `web_hosts` map: "web-2 is OUT-OF-BAND (serving-weight
  0, ADR-143 D2)"), so no user request is served by it; web-1's `webhook.service` is untouched.
- **Zero-downtime path evaluated — and it is the default:** the restart is already the documented
  behaviour of every `ci-deploy.sh` delivery to web-2 since #9212, and it is `try-restart` (a stopped
  unit stays stopped). The one casualty class is a release's web-2 deploy POST landing inside the
  restart window; it self-reports (the release's web-2 `DEPLOY_SCRIPT_SHA` / `IMAGE_VERIFY` rows are
  missing and `check-deploy-script-parity.sh` flags the host), and PM3/PM4 read the first release
  AFTER both applies precisely so that race cannot produce a false result. No maintenance window is
  needed; no residual user-facing downtime is accepted.
- **Placement:** the deny + assertion run in a separate, last `provisioner "remote-exec"` block AFTER
  the block that ends with `try-restart` / `is-active`, so a deny failure can never leave web-2's
  deploy listener un-restarted on the new files (the same "never block the resource's primary duty"
  rule applied to web-1 in Phase 1.3).

## Network-Outage Deep-Dive

(deepen-plan Phase 4.5 — fired on the resource shape: both touched resources use `remote-exec` over a
`connection { type = "ssh" }`.)

1. **L3 firewall allow-list:** not an operator-egress question — both resources are applied only by CI
   through tunnels (web-1: the `cf-tunnel-ssh-bridge` in `apply-web-platform-infra.yml`; web-2: the
   ADR-220 bastion forward through web-1 in `apply-deploy-pipeline-fix.yml`), never from an operator
   IP. **Verified** 2026-09-30: the latest `apply-web-platform-infra.yml` push run's step "Terraform
   apply (SSH-provisioned resources, over the bridge)" concluded `success`, and the latest
   `apply-deploy-pipeline-fix.yml` push run (2026-09-30T02:38Z) concluded `success`
   (`gh run list` / `gh run view --json jobs`).
2. **L3 DNS/routing:** the connections use literal IPv4 addresses (`hcloud_server.web[…].ipv4_address`)
   redirected through the tunnel; no DNS dependency. **Verified** by the same green runs.
3. **L7 TLS/proxy:** the tunnel legs are Cloudflare Access (service-token) — covered by the same green
   runs; host keys are pinned (ADR-237: `local.web_1_ssh_host_key`, `local.web_2_ssh_host_key`).
4. **L7 application (sshd):** no sshd change in this plan. **Opt-out justified** by the green runs
   above (same connection blocks, unchanged).

Gap to close at work time: none, beyond re-reading the two most recent runs' conclusions before
merge (a red SSH stage on `main` would make PM1/PM2 unattributable).

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-096** (`knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`)
with "Amendment 2026-09-30 (#9169) — the web hosts deny ghcr.io": the three copies of the deny
(cloud-init runcmd[1] after the trap arm, `local.ghcr_deny_sh` on both running-host routes); the
`GHCR_DENY ghcr_blocked=<v>` marker and why it is per-release rather than periodic, with the
worst-case evidence age (time since the last release); a short
**delivery route** paragraph (in-place Terraform re-provision because web-1 cannot be replaced —
cx33, 0/6 stock — with the ADR-148 gated web-host replace as the alternative, and the web-1 route
retiring with active-active Phase 5; web-2 COULD be replaced under ADR-148, and is changed in place
anyway because the same apply already re-fires its deploy-pipeline delivery for the `ci-deploy.sh`
edit, so a replace would add a destroy-first host cycle for no extra property); the scope split (host
processes and host-network containers such as the cosign verifier are covered; bridge-network
containers are NOT — GitHub CIDRs in the container allowlist, #9275 — nor is the
`docker.pkg.github.com` alias, #9275); that the release marker probes `ghcr.io` only (registry parity)
while `pkg-containers.githubusercontent.com` is proven at apply time by the assertion; the loopback
behaviour of `0.0.0.0`/`::` (a connect fails in 0 ms — measured with `curl` 2026-09-30); the two
workflows that carry the two hosts;
and the live proof (green post-merge applies, then the first release's `GHCR_DENY ghcr_blocked=1`
row per web host alongside `IMAGE_VERIFY: ok`). Update
the status bullets (top of file and the part-2 amendment's "a web-host deny is a tracked follow-up"
sentence) so the ADR no longer says the web hosts resolve ghcr.io. The ADR stays **Adopting**
(task 5.6 flips it). No new ADR ordinal is needed.

### C4 views

All three model files were checked for this assessment: `spec.c4` (54 lines — element kinds and the
`external`/`selfhosted` tags only, nothing host-specific), `views.c4` (the `ghcr`, `sigstore` and
`platform.infra.hetzner` elements appear only in view `include` lists, lines 28/54/58), and
`model.c4`:

- External systems checked: `ghcr` (model.c4:371, "PRIVATE GHCR registry … WRITE-ONLY"),
  `projectZot` (:381), `sigstore` (:429), `zotRegistry` (:385), `github`. Container checked:
  `hetzner` (the web host cluster, :258). Relationships checked: `hetzner -> sigstore` (:685, the
  gcr.io cosign pull), `hetzner -> zotRegistry` (:673); the last `hetzner -> ghcr` edge was already
  deleted by #8714 (:680). No actor is involved (host-level change). The `inngest -> ghcr` edge
  (~:745, the inngest host's config-bundle path) is out of scope.
- **Result: no C4 change.** No element, relationship, view `include` or embedded cardinality moves —
  the web hosts had no modeled edge to `ghcr` left to delete, and no existing description is made
  false by the deny (the `ghcr` node already states that no host pulls from it). A description-only
  sentence was considered and cut at plan review (it would force a `model.likec4.json` regen and four
  suites for no model change). `plugins/soleur/test/c4-count-parity.test.sh` ran green at plan time
  (2026-09-30, `ALL TESTS PASSED`) and is re-run as AC10.

### Sequencing

The ADR text describes the target state and ships in this PR; "live" is proven post-merge by the
Better Stack read in the Post-merge ACs.

## User-Brand Impact

- **If this lands broken, the user experiences:** a stalled or unverified web-platform release — the
  deploy of new app versions to web-1/web-2 either refuses (a future `ENFORCE` cosign mode) or
  proceeds with `IMAGE_VERIFY_FAIL result=cosign_absent` in today's `warn` mode, so users keep
  running the previous version while fixes queue behind it. A mis-rendered deny that also sinkholed
  a name the app needs (it names only `ghcr.io` and `pkg-containers.githubusercontent.com`) would
  fail app features that call that name.
- **If this leaks, the user's workflow is exposed via:** no new exposure vector — the change removes
  a name-resolution path and adds a closed-vocabulary log field (`1|0|unknown`) with no user data.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches infra provisioning and a deploy script but carries no user data, credential or tenant boundary; its failure mode is a delayed release, detectable in Better Stack within one deploy.`

## Observability

```yaml
liveness_signal:
  what: "Better Stack row `GHCR_DENY ghcr_blocked=<1|0|unknown>` (SYSLOG_IDENTIFIER ci-deploy) per web host (host_name soleur-web-platform / soleur-web-2), once per ci-deploy.sh invocation next to DEPLOY_SCRIPT_SHA"
  cadence: "per release per host (measured 2026-09-30: 5 web-2 deploys in ~2 h); worst-case evidence age = time since the last release, stated in the ADR amendment"
  alert_target: "none by design (registry precedent #9147 ships the field without an alert); the point-of-use failure IMAGE_VERIFY_FAIL result=cosign_absent already routes through ci-deploy.sh's cosign_verify_event page"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (_ghcr_blocked_state + the GHCR_DENY logger line after DEPLOY_SCRIPT_SHA); shipped by the existing journald -> Vector Source 4 path"

error_reporting:
  destination: "Better Stack Logs source 2457081 (ci-deploy rows) and the GitHub Actions apply logs of apply-web-platform-infra.yml / apply-deploy-pipeline-fix.yml"
  fail_loud: "apply time: the remote-exec prints 'FATAL: <name> does not resolve ONLY to the sinkhole after the deny (#9169). Route back: …' and exits 1, failing the workflow run; run time: a GHCR_DENY ghcr_blocked=0 row"

failure_modes:
  - mode: "deny not applied on a running host (resource did not re-fire, or workflow B did not run)"
    detection: "layer 3 vector (journald Source 4 -> Better Stack): GHCR_DENY ghcr_blocked=0 on that host_name in the next release's rows; layer 6 workflow run log: gh run list / gh run view --json jobs for the two apply workflows (SSH step success vs skipped)"
    alert_route: "post-merge verification in the pipeline (Post-merge ACs); no page"
  - mode: "deny text mis-rendered by HCL (escape or interpolation drift)"
    detection: "layer 6 workflow run log: web-ghcr-deny.test.sh parity/execution/agreement rows red the PR check; the in-band ghcr_deny_assert_sh prints its FATAL in the terraform apply transcript (visible because the deny runs in its own secret-free provisioner block)"
    alert_route: "red CI check pre-merge; post-merge, a red apply emails ops (apply-web-platform-infra.yml 'Email ops on a non-green apply run') and trips apply-deploy-pipeline-fix.yml's red-gate alert (main-health-monitor does not watch apply runs)"
  - mode: "a future change re-points the cosign verifier (or any host pull) at ghcr.io"
    detection: "layer 6 workflow run log: cloud-init-ghcr-seed-login.test.sh G1 census VIOL pre-merge; post-merge layer 3 vector (IMAGE_VERIFY_FAIL result=cosign_absent via logger) plus the Sentry event cosign_verify_event POSTs"
    alert_route: "red CI check pre-merge; cosign_verify_event page post-merge"
  - mode: "probe itself breaks (getent absent / hangs)"
    detection: "layer 3 vector (journald Source 4 -> Better Stack): GHCR_DENY ghcr_blocked=unknown rows; the probe is timeout-bounded and fail-open, so the deploy's own markers (DEPLOY_SCRIPT_SHA, IMAGE_VERIFY) still land"
    alert_route: "post-merge verification; no page"

logs:
  where: "journald (SYSLOG_IDENTIFIER ci-deploy) -> Vector Source 4 -> Better Stack source 2457081; apply transcripts in GitHub Actions"
  retention: "Better Stack plan retention for source 2457081; GitHub Actions log retention (90 days)"

discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 24h --grep GHCR_DENY"
  expected_output: "ghcr_blocked=1"
  credentials_required: "Doppler soleur/prd_terraform BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} — the rows live only in Better Stack's ClickHouse warehouse, which has no unauthenticated read path, and the host-side /etc/hosts state has no unauthenticated remote probe either"
```

## Encryption Posture

This plan introduces no persistent store and no new cross-component connection; it edits `.tf` and
`cloud-init.yml`, which trips the Phase 2.11 detector, so the posture of what it touches is declared
explicitly rather than omitted.

```yaml
at_rest:
  - store: web host /etc/hosts and /etc/cloud/templates/hosts.debian.tmpl (root disk, both web hosts)
    mechanism: plaintext-exception
    evidence: the appended lines are the public names ghcr.io and pkg-containers.githubusercontent.com mapped to 0.0.0.0 and ::; no secret, credential or personal data
    defends_against: nothing confidential is stored; integrity of the deny is re-asserted at every apply by ghcr_deny_assert_sh and observed per release by GHCR_DENY ghcr_blocked
    does_not_defend: root on the host can remove the lines (it is a name deny, not a firewall); a process that dials a GHCR IP literal bypasses it
    disclosed_as: ADR-096 amendment 2026-09-30 (#9169)
    live_verification: available — GHCR_DENY ghcr_blocked=1 per host_name in Better Stack
in_transit:
  - connection: web host dockerd -> gcr.io (cosign verifier image; existing, unchanged by this plan)
    enforced_at: apps/web-platform/infra/ci-deploy.sh COSIGN_IMAGE (digest-pinned ref)
    tls: HTTPS (registry v2 API, TLS 1.2+)
    cert_verification: on
    does_not_defend: availability of gcr.io; registry-side substitution is refused by the @sha256 digest pin, not by TLS
    disclosed_as: ADR-096 amendment 2026-09-28 (part 1)
exception:
  justification: the only at-rest row holds two public hostnames and sinkhole addresses; there is nothing confidential to encrypt, and the protected property (the deny is in force) is observed, not encrypted
  tracking_issue: "#8714"
  reevaluate_when: the hosts file ever carries a non-public name or address
  expires_on: 2026-12-29
```

## Guard Contract

### Guard 1 — G1 host-GHCR census keeps its teeth after the web exemption (`apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh`)

**Property.** No comment-stripped code line in any rendered cloud-init template (or
`soleur-host-bootstrap.sh`) names `ghcr.io` except the `IREF=` pin carrier, the `GHCR_OK_TOKENS`, the
registry probe line, and a deny header that is admitted only as part of a whole runcmd entry equal to
copy R, in `cloud-init-registry.yml` or `cloud-init.yml`; and no baked host script
(`local.host_script_files`, which includes `ci-deploy.sh`) presents a GHCR login or pulls a
`ghcr.io/jikig-ai/` image.

**Assembly.** Two chokepoints, stated as two, both in `cloud-init-ghcr-seed-login.test.sh`: (i) the
whole-line rule, check (5) in the `for f in derived + extras` loop (the `elif f ==
"cloud-init-registry.yml" and s in REGISTRY_DENY_LINES` branch, which this PR generalises to a
`{file: {admitted block}}` table) — its file set is DERIVED from every `templatefile()` call plus
`soleur-host-bootstrap.sh`; (ii) the host-literal rule (the `host_script_files` + `hextras` sweep),
where `ci-deploy.sh` is scanned and which this PR does not change (its existing rows 15/15b already
cover a GHCR pull appended in `ci-deploy.sh`).

**Mutation matrix** (added to the suite's `mrow` battery; each row asserts the SPECIFIC VIOL kind,
not "any new VIOL"):

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `; docker pull ghcr.io/project-zot/zot-linux-amd64:v2.1.20` to the web deny header in `cloud-init.yml` | RED — `VIOL cloud-init.yml ghcr.io` |
| 2 | Keep the header byte-identical and add `docker pull "$h/jikig-ai/soleur-web-platform:latest"` inside the web deny entry's loop body | RED — the entry no longer equals copy R, so the header loses its admission (`VIOL cloud-init.yml ghcr.io`) |
| 3 | Keep the compliant entry and ADD a second line `curl -fsS https://ghcr.io/v2/` after it in `cloud-init.yml` | RED — `VIOL cloud-init.yml ghcr.io` (second member after a compliant first) |
| 4 | Row 2's mutation applied to the REGISTRY entry in `cloud-init-registry.yml` | RED — `VIOL cloud-init-registry.yml ghcr.io` (the pre-existing registry hole, closed in the same change) |

The guard's own dispatch (an empty derived file set) is already caught by the suite's existing
SCANNED / measured row-count floor, re-pinned once for the new rows.

**Harness rows.** (a) must-PASS, non-canonical but permitted: the web deny entry re-indented under
its `- |` (YAML indentation differs, parsed entry identical) → PASS. (b) Suite edit that must red:
make `py_sub` write nothing → `landed()` exits 2 (an instrument fault, reported as such, not as a
detection) — the suite must fail, and must not report the rows as "detected".

**Anchor.** No stored value is compared; the exemption table and the entries it admits live in the
same commit, so a weakening needs a reviewed diff to this test file. Copy R is the external
reference for the admitted block (a registry-template diff fires the registry suites). Stated so it
is not mistaken for an integrity check.

### Guard 2 — every deny copy is the registry's entry and every running-host route hashes AND runs it, secret-free (`apps/web-platform/infra/web-ghcr-deny.test.sh`)

**Property.** Each copy of the deny that can reach a web host (rendered cloud-init runcmd[1];
`local.ghcr_deny_sh` as consumed by `zot_consumer_probe_install` and `deploy_pipeline_fix_web2`) is
byte-identical to copy R's whole runcmd entry (whose executed effect `zot-image-fetch.test.sh` R10
proves) and runs correctly under `bash`; each running-host consumer carries the deny and its
assertion in BOTH its `triggers_replace` and a dedicated, secret-free, last `remote-exec` block; and
the three "only the sinkhole" implementations agree on every fixture except the named, expected
difference.

**Assembly.** Two chokepoints, stated as two: (i) fresh hosts — rendered runcmd[1] of `cloud-init.yml`;
(ii) running hosts — `local.ghcr_deny_sh`/`local.ghcr_deny_assert_sh`, consumed by the two named
resources. The consumer set is DERIVED: every occurrence of `for h in ghcr.io` or of an `/etc/hosts`
write across `apps/web-platform/infra/*.tf` must sit inside the two locals' definitions, so a
hand-copied literal in a new resource is caught rather than silently unguarded. Resource spans are
bounded by the top-level-block regex, comment-stripped, so a mutation cannot land in the wrong
resource (`zot_consumer_probe_install` precedes `deploy_pipeline_fix_web2` in `server.tf`).

**Mutation matrix** (in-suite battery on scratch copies; each row names the check that must red):

| # | Mutation | Expected |
|---|---|---|
| 1 | `0.0.0.0` → `127.0.0.1` in copy B (`local.ghcr_deny_sh`) only | RED (whole-entry parity) |
| 2 | Append `: > /etc/hosts` as a new last line of copy A's runcmd entry | RED (whole-entry parity) |
| 3 | Remove `local.ghcr_deny_sh` from `deploy_pipeline_fix_web2`'s `triggers_replace`, keep the deny block | RED (hash coverage, scoped to the web-2 span) |
| 4 | Keep it in `triggers_replace`, delete `zot_consumer_probe_install`'s dedicated deny block | RED (wiring, scoped to the web-1 span) |
| 5 | Move the deny locals INTO web-1's existing token-bearing `remote-exec` block | RED (the deny block must be secret-free and separate) |
| 6 | Add a NEW `terraform_data` in a second `.tf` file whose `inline` carries a hand-copied deny literal, after the two compliant consumers | RED (consumer census: occurrence outside the locals) |
| 7 | Move copy A to runcmd[2] (after `networkctl reload`) | RED (ordering on the parsed list) |
| 8 | Move copy A above the trap-arm entry (runcmd[0]) | RED (the trap arm must stay first) |
| 9 | Weaken `ghcr_deny_assert_sh` to `[ -n "$a" ] && printf '%s\n' "$a" \| grep …` (unresolvable now passes) | RED (agreement: the unresolvable fixture must FAIL the assertion) |
| 10 | Drop `-x` from `_ghcr_blocked_state`'s `grep -qvxE` | RED (agreement: the `2606:50c0:8000::154` fixture must read `0`) |
| 11 | Dispatch: rename the heredoc so the `terraform console` read of copy B returns empty | RED (non-vacuity floor: 3 non-empty copies and ≥ N assertions) |

**Harness rows.** (a) must-PASS, non-canonical: copy A re-indented to a different YAML block indent
→ parsed entry unchanged → PASS; and a synthesized hosts file already holding `0.0.0.0<TAB>ghcr.io`
plus unrelated lines → the `bash` execution of copy B adds nothing for `ghcr.io` and leaves the
unrelated lines byte-identical → PASS. (b) Suite edit that must red: make the parity comparator return
success unconditionally → the in-suite battery's row 1 reports "not detected" and the suite fails.

**Anchor.** Copy R (the registry template) is the external reference for copies A and B: a weakening
of the web copies alone reds on parity; weakening all three needs a diff to `cloud-init-registry.yml`,
which fires its own suites (`zot-image-fetch.test.sh` R10/H6) and, since the registry host's
`user_data` is not ignored the same way, a planned registry replace — which is exactly why this plan
does NOT touch copy R.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `CI=1 bash apps/web-platform/infra/web-ghcr-deny.test.sh` exits 0 with terraform present
  (the render/console half RAN, not skipped), and its in-suite mutation battery reports every Guard 2
  row detected by the named check.
- [ ] AC2 `bash apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` exits 0 with the new
  Guard 1 rows 1-4 detected (each with its named VIOL kind) and the re-pinned row-count floor printed.
- [ ] AC3 `bash apps/web-platform/infra/ci-deploy.test.sh` exits 0 including the fail-open row
  (`getent` absent/NXDOMAIN → `unknown`, exit status unchanged) and the once-per-invocation row
  (`DEPLOY_SCRIPT_SHA` then `GHCR_DENY ghcr_blocked=…`, each exactly once).
- [ ] AC4 `bash apps/web-platform/infra/zot-image-fetch.test.sh` still exits 0 (registry copy R
  untouched).
- [ ] AC5 `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts
  plugins/soleur/test/cloud-init-user-data-size.test.ts plugins/soleur/test/terraform-target-parity.test.ts`
  all pass; if `WEB_GZIP_BUDGET` was raised, the new value and its comment cite the measured render.
- [ ] AC6 `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` and
  `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` exit 0.
- [ ] AC7 `cd apps/web-platform/infra && terraform init -backend=false -input=false && terraform validate`
  passes (render parity of `local.ghcr_deny_sh` is Guard 2's job — heredocs with no `${`/`%{` render
  literally).
- [ ] AC8 The PR's `infra-validation.yml` `plan` job sticky comment ("Post plan comment") contains
  `terraform_data.zot_consumer_probe_install must be replaced` and
  `terraform_data.deploy_pipeline_fix_web2 must be replaced`, and contains no line for any
  `hcloud_server.web[` change (read with `gh pr view <PR> --comments`; no plan JSON exists at PR time).
- [ ] AC9 `git diff --exit-code origin/main...HEAD -- scripts/check-deploy-script-parity.sh` is clean and
  `bash scripts/check-deploy-script-parity.test.sh` passes.
- [ ] AC10 `bash plugins/soleur/test/c4-count-parity.test.sh` passes (backs the "no C4 change"
  conclusion — measured green at plan time, 2026-09-30).
- [ ] AC11 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and
  `python3 scripts/lint-guard-contract.py` over this plan exit 0.
- [ ] AC12 The PR body carries `Ref #9169` and `Ref #8714` — NOT `Closes #9169`: the deny reaches the
  running hosts only through the post-merge applies, and #9169's own acceptance is a live Better Stack
  read, so an auto-close at merge would record it resolved before the remediation runs. #9169 is
  closed by PM6.
- [ ] AC13 The PR body's FIRST line answers "does merging this alone mutate production?": yes —
  the push-triggered `apply-web-platform-infra.yml` re-provisions `zot_consumer_probe_install` on
  web-1 and `apply-deploy-pipeline-fix.yml` re-provisions `deploy_pipeline_fix_web2` on web-2, each
  appending the deny to `/etc/hosts`; the merge click is the authorization. Those are the only two
  workflows that `-target` either resource (`git grep -n 'target=terraform_data.zot_consumer_probe_install\|target=terraform_data.deploy_pipeline_fix_web2' .github/workflows`
  → `apply-web-platform-infra.yml:1171`, `apply-deploy-pipeline-fix.yml:422`); re-run that grep at
  work time and name any new hit. The one other path is the pre-existing break-glass untargeted
  `terraform apply -var image_name=…` chain printed in `apply-web-platform-infra.yml`'s web-host
  recovery text, which would also apply both resources; it is unchanged by this PR.
- [ ] AC14 `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with
  `BASELINE_DECLARED_PROBES` bumped 36 → 37 and a PLACEMENT/TRUTH/NO SUBSTITUTE comment for this
  plan (this plan's `discoverability_test` declares `credentials_required`, which moves that corpus
  count the moment the plan is committed).
- [ ] AC15 `npx markdownlint-cli2` over this plan and its `tasks.md` exits 0.
- [ ] AC16 `git diff --exit-code origin/main...HEAD -- apps/web-platform/infra/cloud-init-registry.yml
  apps/web-platform/infra/zot-registry.tf` is clean (copy R and the registry host are untouched — a
  byte change there forces a registry-host replace).

### Post-merge (automated verification by the pipeline, no host access)

- [ ] PM1 `apply-web-platform-infra.yml` (push run for the merge commit) is green AND its step
  "Terraform apply (SSH-provisioned resources, over the bridge)" concluded `success`, not `skipped`
  (the `ssh_token_gate` skip leaves the run green with nothing delivered —
  `gh run view <id> --json jobs --jq '.jobs[].steps[] | select(.name|startswith("Terraform apply (SSH")) | .conclusion'`);
  its log shows `terraform_data.zot_consumer_probe_install` re-created and no line matching
  `FATAL: .* (#9169)`.
- [ ] PM2 `apply-deploy-pipeline-fix.yml` (push run for the merge commit) is green, with
  `terraform_data.deploy_pipeline_fix_web2` re-created and the same assertion passing on web-2.
  A red run is re-driven with a fresh commit or `gh workflow run apply-deploy-pipeline-fix.yml`,
  never `gh run rerun --failed`. A `cancelled` run (both workflows share the
  `terraform-apply-web-platform-host` concurrency group, so a waiting run can be cancelled by a newer
  one) is re-driven the same way.
- [ ] PM3 After the first web release that starts AFTER both PM1 and PM2 are green (the merge's own
  `web-platform-release.yml` run if it qualifies, else a dispatch),
  `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 6h --grep GHCR_DENY`
  returns `GHCR_DENY ghcr_blocked=1` for BOTH `host_name=soleur-web-platform` and
  `host_name=soleur-web-2` (decode the double-encoded `raw` with `jq -r '.raw | fromjson'` and select
  on `host_name` + `SYSLOG_IDENTIFIER == "ci-deploy"`).
- [ ] PM4 For that same release, `--grep IMAGE_VERIFY` returns `IMAGE_VERIFY: ok` from both hosts, and
  `--grep IMAGE_VERIFY_FAIL` / `--grep cosign_absent` return no rows since the merge.
- [ ] PM5 `bash scripts/check-deploy-script-parity.sh` (under `doppler run -p soleur -c prd_terraform`)
  exits 0 — both hosts run the new `ci-deploy.sh`.
- [ ] PM6 With PM1-PM5 green, `gh issue close 9169` with a comment quoting the two
  `GHCR_DENY ghcr_blocked=1` rows and the `IMAGE_VERIFY: ok` pair (host, timestamp); then comment on
  #8714 that 5.3b-iii's web-host half is live.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** `soleur:engineering:cto` (2026-09-30). Keep the Terraform-provisioner route; the
stronger justification is that web-1 cannot be `-replace`d (cx33, 0/6 stock, per the workflow's own
recovery text). Corrected a premise in the brief: `apply-deploy-pipeline-fix.yml` DOES list
`server.tf` in `paths:`. `zot_consumer_probe_install` is acceptable as the web-1 carrier with the deny
LAST in its `inline`; `infra_config_handler_bootstrap` must not be used (break-glass lever). Keep the
`ci-deploy.sh` marker (its suggested apply-time emit was later cut by plan review as redundant with
the green apply). Fix the container-scope statement
(the cosign verifier runs `--network host`), the stale GHCR `.sig` comment, keep the trap arm first
in runcmd, assert the positive form (no vacuous pass on an unresolvable name), document that the
destination-keyed parity guard cannot see a `local`-carried write, name the route back in the FATAL,
update the web-2 sibling's charter comment, and check for closed marker-name lists. All folded into
the phases, alternatives, Guard 2 rows 6/6b/6c and the ADR task above.

Other domains (Legal, Marketing, Operations, Product, Sales, Finance, Support): no implications — an
internal host-configuration change with no user data, no UI, no vendor or cost change.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given copies A, B and R extracted and dedented, then they are byte-identical; and given copy B run
  once under `bash` against synthesized temp files, then each file carries one `0.0.0.0 <name>` and one
  `:: <name>` line per name.
- Given `getent` shimmed to print only `0.0.0.0` and `::`, when `ci-deploy.sh` runs its startup block,
  then it logs `GHCR_DENY ghcr_blocked=1` once, after `DEPLOY_SCRIPT_SHA`.
- Given `getent` shimmed so a name does not resolve at all, when `local.ghcr_deny_assert_sh` runs, then
  it exits 1 with the FATAL naming the route back (no vacuous pass).
- Given `getent` shimmed to exit 2 (NXDOMAIN) under `set -euo pipefail`, when `ci-deploy.sh` runs, then
  it logs `ghcr_blocked=unknown` and the deploy proceeds (exit status unchanged).
- Given `getent` shimmed to print `0.0.0.0` AND `140.82.121.34`, then `ghcr_blocked=0`.

### Regression Tests

- The registry deny (`zot-image-fetch.test.sh` R10/H6) is unchanged and green.
- `check-deploy-script-parity.sh`'s `DEPLOY_SCRIPT_SHA` parse is unchanged.
- The G1 census still VIOLs any ghcr.io pull added anywhere else (existing rows 14-16c stay green).

### Edge Cases

- runcmd is ONE `/bin/sh` script, so the loop's `f` and `h` persist into later entries: grep the web
  runcmd for any later bare `$f`/`$h` read that relies on being unset (none expected; same shape as
  the registry precedent), and do not wrap the loop in a subshell — that would break byte parity with
  copy R for no measured benefit.
- `/etc/cloud/templates/hosts.debian.tmpl` present or absent — a property of the base image the repo
  cannot show (`user_data` sets no `manage_etc_hosts`): either way the loop
  `continue`s; only `/etc/hosts` is written.
- `getent` absent or hanging: bounded by `timeout 5` when present; result `unknown`; deploy continues.
- A host where the deny was removed out of band: the next release logs `ghcr_blocked=0`. A
  `gh workflow run` dispatch does NOT repair it — with `triggers_replace` unchanged the resource plans a
  no-op (a dispatch re-fires only a TAINTED resource, i.e. after a failed assertion). Untainted drift
  needs a hash-moving commit (e.g. a comment change inside `local.ghcr_deny_sh`), or a host replace.

### Integration Verification (for `soleur:qa`)

- **API verify:** `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 6h --grep GHCR_DENY | jq -r '.raw | fromjson | "\(.host_name) \(.message)"'`
  expects `soleur-web-platform GHCR_DENY ghcr_blocked=1` and `soleur-web-2 GHCR_DENY ghcr_blocked=1`
  after the first release that follows both applies (post-merge only).

## Success Metrics

- Both web hosts report `ghcr_blocked=1` on the first release after merge, and every release after it.
- Zero `IMAGE_VERIFY_FAIL` / `cosign_absent` rows attributable to the change.

## Dependencies & Risks

- **Dependency (satisfied):** #9151 closed; web-2 runs the gcr.io cosign ref (Premise Validation).
- **Risk — `0.0.0.0` / `::` route to loopback on Linux.** A ghcr.io client fails fast (refused, or a
  TLS name mismatch against a local :443 listener) rather than hanging; same accepted residual as the
  registry host, stated in the ADR.
- **Risk — cloud-init gzip budget.** ~184 B headroom; measured in Phase 0.4 and raised from the CI
  failure line if needed (far below the Hetzner cap).
- **Risk — HCL heredoc rendering.** Mitigated by Guard 2 (byte parity + no `${`/`%{` + one `bash`
  execution of copy B) and AC7 (`terraform validate`).
- **Risk — web-1 re-fire side effects.** `zot_consumer_probe_install`'s body is idempotent (Phase 1.3);
  it restarts nothing. (The web-2 re-fire's `try-restart webhook` is covered in `## Downtime & Cutover`.)
- **Risk — ordering between the two workflows.** The first release after merge can race the applies,
  so its marker may read `0` on one host; PM3 reads the first release AFTER both applies are green.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The `IMAGE_VERIFY: ok ref=` field is the APP image ref, never the cosign ref — do not write an AC that
  expects the cosign ref on that line; read the `untagged: gcr.io/projectsigstore/cosign@…` prune rows
  instead (as Premise Validation did).
- `gh run rerun --failed` re-runs the ORIGINAL merge ref; after pushing a fix, dispatch or push, do not
  rerun.
- Better Stack rows are double-encoded JSON; grep the decoded `.message`, never the raw line.
- **Never edit `cloud-init-registry.yml` in this PR** (not even to add `docker.pkg.github.com`, not
  even whitespace): `hcloud_server.registry`'s `user_data` is ForceNew with no `ignore_changes`
  (`zot-registry.tf`, the "Deliberately NO lifecycle.ignore_changes=[user_data]" note), so any byte
  change plans a destroy-first replace of the only image pull path. Copy R is read-only here; Guard 1
  row 4 mutates a scratch copy only. Assert it with
  `git diff --exit-code origin/main...HEAD -- apps/web-platform/infra/cloud-init-registry.yml`.
- **Terraform suppresses a provisioner's entire output when its config references a sensitive
  value** — which is why the deny lives in its own secret-free `remote-exec` block; putting it inside
  the existing token-bearing block would hide the FATAL and leave a secret-bearing script in `/root`
  on failure (the `#8706` `script_path` comment on each resource in server.tf).
- **The #9151 plan's claim that `apply-deploy-pipeline-fix.yml` excludes `server.tf` from `paths:`
  is false on `main`** (the workflow lists it; the gate test pins it). Re-verify workflow triggers
  from the YAML, never from a sibling plan's prose.
