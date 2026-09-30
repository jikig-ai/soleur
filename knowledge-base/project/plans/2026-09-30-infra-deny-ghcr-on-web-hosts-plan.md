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
  `knowledge-base/project/specs/feat-one-shot-9169-web-host-ghcr-deny/decision-challenges.md`.

## Problem Statement

ADR-096 step 5.3b-iii asked to "re-scope, then remove, the GHCR egress allow". That allow was
measured as having no object (all five hcloud firewall rules are `direction=in`; host OUTPUT is
never filtered; the container egress allowlist names no GHCR host), so the step is realised as an
**enforced, observed per-host deny**. The registry host got it in PR #9147 (live:
`ghcr_blocked=1`). The two web hosts still resolve `ghcr.io`: nothing on them pulls from it any
more, but that is a claim, not an enforced and observed fact. A ghcr.io outage or compromise can
still reach anything on a web host that resolves the name — most importantly a future regression
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
verifier pull is a `dockerd` pull. The cosign verifier itself runs `docker run --rm --network host`
(`ci-deploy.sh`, the `"$COSIGN_IMAGE" verify --offline` call), and host-network containers carry the
host's hosts entries, so the deny covers the verifier's own resolution too. Bridge-network containers
(the app, agent sandboxes) get a docker-generated `/etc/hosts` without host entries; their egress is
governed by the cron-egress nftables allowlist, which names no GHCR host. That split is stated in the
ADR amendment, not left implicit.

### Implementation Phases

**Phase 0 — RED tests first (`cq-write-failing-tests-before`).**

- 0.1 New `apps/web-platform/infra/web-ghcr-deny.test.sh` (auto-registered by
  `infra-validation.yml`'s `apps/web-platform/infra/**.test.sh` glob):
  - extracts copy A (the `cloud-init.yml` runcmd block), copy B (`local.ghcr_deny_sh` heredoc body
    from `server.tf`) and copy R (the registry block) by anchor, dedents each, asserts A == B == R;
  - asserts copy B's heredoc body contains no `${` and no `%{` (HCL renders it literally — heredocs
    do not process backslash escapes);
  - executes copy B ONCE under `bash` (Terraform's `inline` has no shebang, so on the hosts it runs
    under root's login shell, bash — copy R's execution under `sh` by `zot-image-fetch.test.sh` R10
    does not cover that interpreter) against synthesized temp files, asserting one `0.0.0.0` and one
    `::` line per name;
  - classifier agreement: runs ONE table of `getent` shim states (sinkhole only; routable only;
    sinkhole + routable; unresolvable) against all three "resolves only to the sinkhole"
    implementations — the registry classifier snippet (`cloud-init-registry.yml`, the
    `GHCR_BLOCKED` block), `_ghcr_blocked_state` in `ci-deploy.sh`, and `local.ghcr_deny_assert_sh`
    — and asserts they agree (`1`/pass, `0`/fail, `0`/fail, `unknown`/fail);
  - asserts copy A is the `runcmd:` entry IMMEDIATELY after the entry containing `trap on_err EXIT`,
    and precedes every entry containing `apt-get`, `docker pull`, `docker run` or `wget` (the
    trap-arm entry stays first — its own comment requires it);
  - asserts both `zot_consumer_probe_install` and `deploy_pipeline_fix_web2` reference
    `local.ghcr_deny_sh` AND `local.ghcr_deny_assert_sh` in BOTH `triggers_replace` and a
    `remote-exec` `inline`;
  - non-vacuity floor: fails if any extraction is empty or fewer than 3 copies were compared;
  - every failure message for copy B / the two consumers says: "the deny must move to the successor
    route or be retired with it (active-active Phase 5, ADR-143); cloud-init copy A is the end
    state" — so retiring the web-1 SSH route reds with an explanation, not a mystery.
- 0.2 `ci-deploy.test.sh`: (classifier values are covered by 0.1's agreement table) one row with
  `getent` absent / exiting 2 asserting `ghcr_blocked=unknown`, the deploy's exit status unchanged
  under `set -euo pipefail`; and one row asserting `^GHCR_DENY ghcr_blocked=(1|0|unknown)$` is
  logged exactly once per invocation, after `DEPLOY_SCRIPT_SHA`.
- 0.3 `cloud-init-ghcr-seed-login.test.sh`: new mutation rows (see Guard 1) — RED until Phase 1.
- 0.4 Measure the budget BEFORE editing anything else: render `cloud-init.yml` with the deny block
  inserted (scratch copy) through `plugins/soleur/test/cloud-init-user-data-size.test.ts`'s own
  render path and record the delta against `WEB_GZIP_BUDGET` (~184 B headroom per its comment). If
  the delta exceeds the headroom, the budget raise is a planned edit of this PR (Phase 3.1), not a
  surprise — and the YAML comment above the deny stays one line.

**Phase 1 — the deny on every route.**

- 1.1 `cloud-init.yml`: insert the deny as the second `runcmd:` entry (right after the trap-arm
  entry that ends with `_emit "soleur-cloud-init boot stage" runcmd_start info`) with a SHORT comment (the
  rendered comment bytes count against `WEB_GZIP_BUDGET`; put the long rationale in the ADR, not
  the template).
- 1.2 `server.tf` `locals`: add `ghcr_deny_sh` (heredoc, byte-identical loop) and
  `ghcr_deny_assert_sh` (heredoc: for each of the two names, `a=$(getent ahosts "$h" | awk '{print
  $1}' | sort -u)`; `if [ -z "$a" ] || printf '%s\n' "$a" | grep -qvxE '0\.0\.0\.0|::'; then echo
  "FATAL: $h does not resolve ONLY to the sinkhole after the deny (#9169). Route back: the resource
  is now tainted, so push a fix commit or gh workflow run the owning apply workflow; never gh run
  rerun --failed." >&2; exit 1; fi` — this is the ONE FATAL literal; every AC greps
  `FATAL: .* (#9169)`),
  with a comment naming both consumers and Guard 2.
- 1.3 `zot_consumer_probe_install`: add both locals to `triggers_replace`; append both as the LAST
  elements of its `remote-exec` `inline` (after the env-file write and `systemctl` lines), so a deny
  or assertion failure can never block re-delivery of the probe's Doppler token file. Before relying on the re-fire, confirm its existing body
  is idempotent on a live host (it is: two `file` provisioners overwrite the same bytes, the env file
  is rewritten from the same inputs under `umask 0137`, `daemon-reload`, and `enable --now` on an
  already-enabled timer) — re-read the block at work time and say so in the PR body. Add a one-line
  header comment on the resource: `# also carries the ghcr.io hosts-file deny (#9169; Guard 2)`.
- 1.4 `deploy_pipeline_fix_web2`: add both locals to `triggers_replace` ABOVE the
  `file(".../web-2-ssh-host-key.pub"),` line (the pin line and the `"dpf-web2-remote-exec-v1",`
  sentinel after it must stay adjacent and byte-identical: `web-host-provisioner-parity-mutation.test.sh`
  M4b/c/d anchor on exactly those two lines); leave the sentinel at `-v1`; append both locals to the post-file `remote-exec` `inline` after the
  sha256 assertions; update the resource's header comment, whose charter today is "the FILE_MAP
  file set", to name the hosts-file deny as its one non-file duty (and re-run
  `web-host-provisioner-parity.test.sh` §1, which treats this resource as the only web-2 dialer).
  A failed assertion taints the resource, so every later run re-attempts it until fixed — the FATAL
  text names the route back.
- 1.5 `cloud-init-ghcr-seed-login.test.sh`: widen the whole-line exemption (today
  `f == "cloud-init-registry.yml" and s in REGISTRY_DENY_LINES`) to a `{file: {lines}}` table that
  admits the deny line in `cloud-init.yml` only; add the Guard 1 rows; re-measure and re-pin the
  row-count floor.
- 1.6 `web-host-provisioner-parity.test.sh`: it reads LITERAL destinations in server.tf, so the
  deny's `/etc/hosts` write — reached through `${local.ghcr_deny_sh}` — is invisible to it (it would
  fail open, not red). Guard 2 owns this destination's fresh-boot parity explicitly (copy A ≡ copy
  B). Run both parity suites unchanged; re-pin floors only if a measured count moves.

**Phase 2 — the heartbeat field.**

- 2.1 `ci-deploy.sh`: add `_ghcr_blocked_state` (prints exactly one of `1|0|unknown`; every
  command `|| true`/`if`-guarded because the script runs `set -euo pipefail`; `getent` bounded with
  `timeout 5` when `timeout` exists; probes `ghcr.io` only — registry-classifier parity) and emit
  `logger -t "$LOG_TAG" "GHCR_DENY ghcr_blocked=$v" 2>/dev/null || true` immediately after the
  `DEPLOY_SCRIPT_SHA` line. In `ci-deploy.test.sh`, put a default `getent` shim on the harness PATH
  so the many existing invocations never do a real lookup (which could stall up to 5 s each on a
  no-network runner).
- 2.2 Verify `scripts/check-deploy-script-parity.sh` and every other `DEPLOY_SCRIPT_SHA` /
  `IMAGE_VERIFY` consumer is untouched (`git grep -n 'DEPLOY_SCRIPT_SHA\|IMAGE_VERIFY' -- scripts
  apps .github`), because the new line is a separate marker. Before writing the marker, `git grep`
  for any closed list of allowed `ci-deploy` logger markers (in `ci-deploy.test.sh`, soak scripts,
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
| Append `ghcr_blocked=` to the `DEPLOY_SCRIPT_SHA` or `IMAGE_VERIFY: ok` line | Those lines are parsed by `check-deploy-script-parity.sh` and the soak scripts; a separate marker leaves every existing parser byte-stable. |
| Better Stack alert on `ghcr_blocked=0` | Registry precedent shipped no alert; cut (see Cut List). |

## Non-Goals

- Container-internal name resolution (docker-generated `/etc/hosts` in each container). Covered by
  the cron-egress nftables allowlist, which names no GHCR host.
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
- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` — cloud-init.yml whole-line exemption, mutation rows,
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
  `terraform_data.deploy_pipeline_fix_web2` gain both locals in `triggers_replace` and in a
  `remote-exec` `inline`; the web-2 sentinel is unchanged (the new inline text is hash-covered).
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

Downtime/blast radius: none expected. The deny appends at most four lines per file; no daemon is
restarted (dockerd re-reads `/etc/hosts` per lookup via the Go resolver). The web-1 resource re-runs
`systemctl enable --now web-zot-consumer-probe.timer` (no-op when enabled) and rewrites its env file
with identical content; the web-2 resource re-delivers the same deploy-pipeline file set (identical
bytes except `ci-deploy.sh`) and re-runs `visudo`/sha assertions — the same work #9212's first apply
did. Neither resource restarts `webhook.service`.

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

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-096** (`knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`)
with "Amendment 2026-09-30 (#9169) — the web hosts deny ghcr.io": the three copies of the deny
(cloud-init runcmd[1] after the trap arm, `local.ghcr_deny_sh` on both running-host routes); the
`GHCR_DENY ghcr_blocked=<v>` marker and why it is per-release rather than periodic, with the
worst-case evidence age (time since the last release); a short
**delivery route** paragraph (in-place Terraform re-provision because web-1 cannot be replaced —
cx33, 0/6 stock — with the ADR-148 gated web-host replace as the alternative, and the web-1 route
retiring with active-active Phase 5); the scope split (host processes and host-network containers
such as the cosign verifier are covered; bridge-network containers are governed by the cron-egress
allowlist); the loopback behaviour of `0.0.0.0`/`::`; the two workflows that carry the two hosts;
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
    detection: "GHCR_DENY ghcr_blocked=0 on that host_name in the next release's rows; gh run list for the two apply workflows"
    alert_route: "post-merge verification in the pipeline (Post-merge ACs); no page"
  - mode: "deny text mis-rendered by HCL (escape or interpolation drift)"
    detection: "web-ghcr-deny.test.sh copy-parity + bash-execution + classifier-agreement rows in CI; the in-band ghcr_deny_assert_sh fails the apply"
    alert_route: "red CI check / red apply run on main (main-health-monitor)"
  - mode: "a future change re-points the cosign verifier (or any host pull) at ghcr.io"
    detection: "cloud-init-ghcr-seed-login.test.sh G1 census VIOL pre-merge; post-merge IMAGE_VERIFY_FAIL result=cosign_absent via cosign_verify_event"
    alert_route: "red CI check pre-merge; cosign_verify_event page post-merge"
  - mode: "probe itself breaks (getent absent / hangs)"
    detection: "GHCR_DENY ghcr_blocked=unknown rows; the probe is timeout-bounded and fail-open, so the deploy's own markers (DEPLOY_SCRIPT_SHA, IMAGE_VERIFY) still land"
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
`soleur-host-bootstrap.sh`) names `ghcr.io` except the `IREF=` pin carrier, the `GHCR_OK_TOKENS`, and
three exact whole lines each admitted ONLY in its named file: the registry deny and probe lines in
`cloud-init-registry.yml`, and the web deny line in `cloud-init.yml`; and no baked host script
(`local.host_script_files`, which includes `ci-deploy.sh`) presents a GHCR login or pulls a
`ghcr.io/jikig-ai/` image.

**Assembly.** Two chokepoints, stated as two, both in `cloud-init-ghcr-seed-login.test.sh`: (i) the
whole-line rule, check (5) in the `for f in derived + extras` loop (~line 304-331; the `elif f ==
"cloud-init-registry.yml" and s in REGISTRY_DENY_LINES` branch this PR generalises to a
`{file: {exact stripped line, …}}` table) — its file set is DERIVED from every `templatefile()` call
plus `soleur-host-bootstrap.sh`; (ii) the host-literal rule (~line 387), over `local.host_script_files`
plus `hextras`, which is where `ci-deploy.sh` is scanned and which this PR does not change.

**Mutation matrix** (added to the suite's `mrow` battery; written before the exemption change):

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `; docker pull ghcr.io/project-zot/zot-linux-amd64:v2.1.20` to the web deny line in `cloud-init.yml` | RED (VIOL ghcr.io cloud-init.yml) |
| 2 | Append `; docker pull ghcr.io/jikig-ai/soleur-web-platform:latest` to the new probe line in `ci-deploy.sh` | RED (host-literal rule: host-pull-ghcr in ci-deploy.sh — the probe line is NOT a shelter) |
| 3 | Keep the compliant deny line and ADD a second line `curl -fsS https://ghcr.io/v2/` after it in `cloud-init.yml` | RED (second member after a compliant first) |

The guard's own dispatch (an empty derived file set) is already caught by the suite's existing
SCANNED / measured row-count floor, re-pinned once for the three new rows.

**Harness rows.** (a) must-PASS, non-canonical but permitted: the web deny line re-indented by two
extra spaces (the census strips the line before comparing) → PASS. (b) Suite edit that must RED:
turn the `mrow` helper's mutation into a no-op (`py_sub` writes nothing) → the new rows 1-3 report
"not detected" and the measured row-count floor (re-pinned from 47 to the new measured count) fails.

**Anchor.** No stored value is compared; the exemption table and the lines it admits live in the same
commit, so a weakening needs a reviewed diff to this test file — the file is under `apps/web-platform/infra/`,
covered by the repo's review gates. Stated so it is not mistaken for an integrity check.

### Guard 2 — every deny copy is the registry's bytes and every running-host route hashes AND runs it (`apps/web-platform/infra/web-ghcr-deny.test.sh`)

**Property.** Each copy of the deny that can reach a web host (cloud-init runcmd[1]; `local.ghcr_deny_sh`
as consumed by `zot_consumer_probe_install` and `deploy_pipeline_fix_web2`) is byte-identical (after
dedent) to the registry precedent, whose executed effect `zot-image-fetch.test.sh` R10 already proves;
each running-host consumer includes the deny and its assertion in BOTH its `triggers_replace` and its
`remote-exec` body; and the three "resolves only to the sinkhole" implementations agree.

**Assembly.** Two chokepoints, stated as two: (i) fresh hosts — the `runcmd:` entry right after the trap arm in
`cloud-init.yml`; (ii) running hosts — `local.ghcr_deny_sh`/`local.ghcr_deny_assert_sh`, consumed by
the two named resources. The suite also DERIVES the consumer set: every `server.tf` occurrence of
`for h in ghcr.io` must sit inside the two locals' heredoc definitions (occurrences outside them = 0),
so a hand-copied literal in a new resource is caught rather than silently unguarded.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `0.0.0.0` → `127.0.0.1` in copy B (`local.ghcr_deny_sh`) only | RED (copy parity) |
| 3 | Remove `local.ghcr_deny_sh` from `deploy_pipeline_fix_web2`'s `triggers_replace`, keep it in `inline` | RED (hash coverage) |
| 4 | Keep it in `triggers_replace`, remove it from `zot_consumer_probe_install`'s `inline` | RED (wiring: not run) |
| 5 | Add a NEW `terraform_data` whose `inline` carries a hand-copied deny literal (not the local), after the two compliant consumers | RED (occurrences of `for h in ghcr.io` outside the two locals ≠ 0) |
| 6 | Move the deny below the `STAGE=cf_apt_key`/`apt-get` entry (after the first package fetch) | RED (ordering) |
| 6b | Move the deny ABOVE the trap-arm entry (runcmd[0]) | RED (the trap arm must stay first) |
| 6c | Weaken `ghcr_deny_assert_sh` to the negative form (drop the `[ -z "$a" ]` arm) | RED (agreement table: the unresolvable shim must FAIL the assertion) |
| 7 | Make `_ghcr_blocked_state` report `1` when `getent` prints nothing | RED (agreement table: unresolvable must be `unknown`) |
| 8 | Dispatch: rename the heredoc anchor so extraction of copy B returns empty | RED (non-vacuity floor: 3 non-empty copies required) |

**Harness rows.** (a) must-PASS, non-canonical: copy A re-indented to a different YAML block indent
(4 → 6 spaces under its `- |`) → still equal after dedent → PASS. (b) Suite edit that must RED: make
the comparator return success unconditionally → row 1 goes undetected, which the suite's own
self-check (it runs row 1's mutation on a scratch copy and requires a RED) reports.

**Anchor.** Copy R (the registry template) is the external reference for copies A and B: a weakening
of the web copies alone reds on parity; weakening all three at once needs a diff to
`cloud-init-registry.yml`, which fires its own registry suites (`zot-image-fetch.test.sh` R10/H6).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `bash apps/web-platform/infra/web-ghcr-deny.test.sh` exits 0, and every Guard 2 mutation
  row was demonstrated RED during work (record the command + outcome per row in the PR body).
- [ ] AC2 `bash apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` exits 0 with the new
  Guard 1 rows 1-3 detected and the re-pinned row-count floor printed.
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
  work time and name any new hit.
- [ ] AC14 `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with
  `BASELINE_DECLARED_PROBES` bumped 36 → 37 and a PLACEMENT/TRUTH/NO SUBSTITUTE comment for this
  plan (this plan's `discoverability_test` declares `credentials_required`, which moves that corpus
  count the moment the plan is committed).
- [ ] AC15 `npx markdownlint-cli2` over this plan and its `tasks.md` exits 0.

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
  never `gh run rerun --failed`.
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
- `/etc/cloud/templates/hosts.debian.tmpl` absent (`grep -n manage_etc_hosts cloud-init.yml` is empty): the loop
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
  it restarts nothing.
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
