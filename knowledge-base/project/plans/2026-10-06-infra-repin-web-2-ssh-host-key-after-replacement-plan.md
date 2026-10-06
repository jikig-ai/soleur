---
title: "infra: re-pin web-2's SSH host key after the 2026-10-06 replacement (Ref #9372)"
type: infra
date: 2026-10-06
slug: repin-web-2-ssh-host-key-after-replacement
branch: feat-one-shot-9372-web2-host-key-repin
issue: 9372
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# infra: re-pin web-2's SSH host key after the 2026-10-06 replacement (Ref #9372)

## Enhancement Summary

**Deepened on:** 2026-10-06. Scoped to the plan's size: the halt gates were run mechanically
rather than fanning out the full agent roster (one data file, no code, no new mechanism).

- Gates run: User-Brand Impact (pass, `aggregate pattern`), Observability (section added, see
  below), PAT-shaped variable sweep (none), Guard Contract (no guard in the deliverable; lint
  reports 0 entries), Scope Check (one unfenced section, all 8 asks mapped), Encryption Posture
  (no store or connection introduced; the file is a public host key), UI-wireframe (no UI).
- Citations re-verified live: #9151 CLOSED and its commit `bef6dd5a07` introduced the pin; #9305
  MERGED and re-pinned this same file on 2026-09-30; #9372 OPEN; ADR-237 and the runbook section
  "What the replace does NOT restore" exist at the cited paths. No AGENTS.md rule IDs are cited.
- Added: the `## Observability` section (the pin sits under `apps/web-platform/infra/`, which the
  mechanical trigger treats as production infra), and a diff-scope AC that lists the files the
  pipeline writes.
- Deliberately not done: re-running the capture, a second `ssh-keyscan`, or any live-host check.
  The brief forbids re-capture; the live-host verification belongs to the owner-gated re-enable.

## Overview

web-2 was replaced (Hetzner server id 169095540, IPv4 204.168.189.200, created 2026-10-06T19:32:09Z).
A replaced host mints a new sshd host key, so the committed pin
`apps/web-platform/infra/web-2-ssh-host-key.pub` (fingerprint `SHA256:P0J9dUv6...`, captured
2026-09-30 against the previous host) no longer matches. Until it is re-pinned,
`local.web_2_ssh_host_key` and the `deploy_pipeline_fix_web2` sibling would trust a key the live
host does not present, so every web-2 delivery fails closed.

This PR does one thing: replace the pin file on main with the already-captured file, copied
byte-for-byte. It references #9372 (`Ref #9372`) and never closes it. The capture was produced by
`scripts/capture-web-2-host-key.sh` on 2026-10-06T19:37:27Z; it is not re-run here.

Source file (read-only input, outside the repo):
`/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/2bc60a9e-7ca0-414d-bbcd-15a8e4f8b7c9/scratchpad/web-2-ssh-host-key.captured.pub` (a session-local file outside the repo that readers cannot reproduce; the committed pin is the artifact of record)

## Research Insights

**Premise Validation.** Checked: #9372 is OPEN (so `Ref`, never `Closes`, is correct and the
premise holds); #9151 (the delivery-via-bastion work that introduced the pin) is CLOSED; the pin
file exists on `origin/main` at the cited path; precedent PR #9305 re-pinned the same file after
the 2026-09-30 replace and is the shape to follow. The captured file's key line, run through
`ssh-keygen -lf`, prints `SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ`, which equals the
`# fingerprint:` header in that file and the fingerprint given in the task, so the header and
key agree. Nothing else in the repo hardcodes the old fingerprint or key body (grep of
`P0J9dUv60r9` / the old key fragment outside plans/specs: only the pin file itself).

**Property List.**

1. `web-2-ssh-host-key.pub` on main holds exactly the key captured from the replacement host.
2. The file still parses as a valid pin at both consumer sites (HCL `local.web_2_ssh_host_key`
   and the bash twin `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh`), and its `# fingerprint:` header equals
   `ssh-keygen -lf` of its key line.
3. The PR body records the fingerprint, the capture vantage, and the weakness of the cross-check,
   so a reviewer can judge the pin without re-deriving it.
4. The PR makes no claim about web-2's disk encryption or boot state, and does not enable,
   dispatch, or apply anything.

**Cut List.** None. No mechanism beyond the file swap is proposed (no script, no test, no
workflow change). Every property is bought by the file copy plus the existing hermetic suites;
nothing new is added.

**Merge side-effect check (read-only).** `apply-deploy-pipeline-fix.yml` lists the pin file in its
`on.push.paths`, and `terraform_data.deploy_pipeline_fix_web2.triggers_replace` hashes it
(`server.tf`). Verified with `gh api repos/jikig-ai/soleur/actions/workflows/274867255`: the
workflow state is `disabled_manually`, so merging this PR does not fire an apply. This differs
from #9305, where merge did change production. The pin file is not in the ship skill's
Deploy-Pipeline-Fix drift-gate trigger list (that list covers `deploy_pipeline_fix`, the web-1
resource), so that gate does not fire.

**Institutional context.** `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`
(the pin policy); `knowledge-base/engineering/operations/runbooks/web-host-replace.md` ("What the
replace does NOT restore" lists the re-pin); PR #9305 (same operation, 2026-09-30).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. A wrong or malformed pin
  makes the next web-2 deploy-pipeline apply fail closed (the HCL local errors, or the SSH
  handshake rejects the host). The blocked artifact is the deploy-pipeline delivery, not web-2's
  service: `apply-deploy-pipeline-fix.yml` opens the web-2 forward and runs its end-to-end probe
  BEFORE `terraform plan` and fails the whole job closed (its own header, and `[skip-deploy-fix-apply]`
  skips web-1 remediation too), so a wrong pin or a dark web-2 also holds back delivery of the
  deploy script, seccomp/apparmor profiles and webhook unit to web-1, the host that serves users.
  web-2 itself serves nothing (weight 0).
- **If this leaks, the user's workflow is exposed via:** no secret is in the file (it is a
  public host key). The residual risk is a pin captured from the wrong party: this capture was a
  first-sight, trust-on-first-use read of a brand-new host with no prior `known_hosts` entry, so
  it proves "this is what 204.168.189.200 presented at 19:37:27Z", not independent identity. If
  that read had been intercepted, a later apply would run its remote-exec against the interceptor
  as root, and that same pinned connection (`terraform_data.deploy_pipeline_fix_web2`,
  `server.tf`) delivers `/etc/webhook/hooks.json` rendered from `var.webhook_deploy_secret`, the
  Doppler token drop-ins, the deploy scripts and sudoers. So the exposure is the deploy webhook
  secret and root-level provisioning, not only "holds no user data". Whether web-1 shares that
  secret is not established here and is not assumed away. The CI private key is not exposed (pubkey
  auth signs over the session id, so a man-in-the-middle cannot replay it).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because the capture was a
  direct connection from an ADMIN_IPS egress to the public port of a server created five minutes
  earlier (no Cloudflare hop, minimal interception window), the pin fails closed on mismatch, and
  Terraform's `host_key` is strict, so a mismatch is a red apply and never a trust-on-first-use
  bypass. That control holds because the capture path (admin egress, direct) and the CI path
  (web-1 bastion forward) differ: an interceptor on the capture path alone yields a mismatched pin
  and a red apply. An interceptor persistent on the CI route would NOT be caught. No web-2 analogue
  of `terraform_data.web_1_host_key_probe` exists, so the live-host check is only the paused
  workflow's probe. Before re-enabling, the owner should take one more independent read of the
  key (a second `ssh-keyscan` from a different egress, or the Hetzner console), which this PR does
  not do.

## Observability

The pin is committed data, not a running service, so it has no liveness signal of its own; the
signals below are the ones that exist today. Nothing here claims an alert fires on a path that is
currently disabled.

```yaml
liveness_signal:
  what: the pin file's committed fingerprint header matches the captured key (CI row H1 of web-2-host-key-local.test.sh); the live-host check is the apply workflow's end-to-end probe, which only runs once that workflow is re-enabled by the owner
  cadence: per PR run for H1; per apply run for the probe
  alert_target: the failed CI check on a PR; a red apply-deploy-pipeline-fix.yml run once re-enabled
  configured_in: apps/web-platform/infra/web-2-host-key-local.test.sh and .github/workflows/apply-deploy-pipeline-fix.yml
error_reporting:
  destination: GitHub Actions check and run status (no Sentry surface: this is infrastructure data, not application code)
  fail_loud: the HCL local errors on a malformed pin (every plan fails closed); an SSH handshake rejects a host whose key differs from the pin
failure_modes:
  - mode: pin does not match the live host's key
    detection: the apply workflow's SSH handshake and end-to-end probe fail closed once the workflow is re-enabled
    alert_route: red workflow run, owner-visible; web-1 pipeline and security-profile delivery is held back until it is fixed (web-2 itself serves nothing)
  - mode: pin file malformed or header disagrees with the key line
    detection: web-2-host-key-local.test.sh (shape rows and H1) fails on the PR
    alert_route: blocking CI check on the PR
logs:
  where: GitHub Actions run logs
  retention: GitHub's default Actions log retention
discoverability_test:
  command: grep -c "fingerprint: SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ" apps/web-platform/infra/web-2-ssh-host-key.pub
  expected_output: "1"
```

The `discoverability_test` reads only the committed header (it prints `0` on the pre-change tree
and `1` once the new pin is in place); it does not verify the key against the live host, which is
exactly the gap the weak cross-check statement in the PR body discloses.

## Files to Edit

- `apps/web-platform/infra/web-2-ssh-host-key.pub` — overwrite with the captured file
  (6 comment lines + 1 key line). The key line must not be edited.

## Files to Create

- None in the product tree. (`knowledge-base/project/specs/feat-one-shot-9372-web2-host-key-repin/tasks.md`
  is the plan's task breakdown only.)

## Open Code-Review Overlap

None. Queried open `code-review` issues for `web-2-ssh-host-key` and `capture-web-2-host-key`:
no matches.

## Implementation

1. **Copy verbatim.** `cp` the captured file over the pin file. Do not retype, reformat or trim.
   Afterwards confirm byte identity: `cmp <captured> apps/web-platform/infra/web-2-ssh-host-key.pub`
   exits 0, and `git diff --stat` shows only this one file.
2. **Fingerprint round-trip.** `ssh-keygen -lf apps/web-platform/infra/web-2-ssh-host-key.pub`
   prints `SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ`.
3. **Run the hermetic suites** (all offline; no network, no apply):
   - `bash scripts/capture-web-2-host-key.test.sh` (stubs `ssh-keyscan`; expects 17 passed)
   - `bash apps/web-platform/infra/web-2-host-key-local.test.sh` (pin-shape check: HCL local and
     bash twin agree, and row `H1` asserts the committed header equals `ssh-keygen -lf` of the
     key line; expects 23 passed). `H1` is the check that actually exercises the new file.
   - Also the three suites #9305 ran, since they reference the pin file:
     `bash apps/web-platform/infra/web-ghcr-deny.test.sh`,
     `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`, and
     `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`.
   Baseline on the unmodified tree (run during planning): capture suite 17/17, pin-shape suite
   23/23.
4. **PR.** Title `chore(infra): re-pin web-2's SSH host key after the 2026-10-06 replacement`.
   Body must contain, in this order: what changed and why; the capture vantage; the new
   fingerprint; the honest cross-check statement; the "apply workflow stays paused" paragraph;
   `Ref #9372`; the `## Changelog` section (patch). Draft below.

### PR body draft (the implementer fills in test counts from the real runs)

```markdown
Re-pins web-2's SSH host key after the replacement server was created. A replaced host mints a
new sshd host key, so the previous pin (`SHA256:P0J9dUv60r9UHDLAxaTZ9hZDLJ9TYuciQQnQTtdtYiQ`,
captured 2026-09-30) no longer matches. The new pin file is the captured file copied verbatim.

## Capture

- Script: `scripts/capture-web-2-host-key.sh` (`ssh-keyscan -T 10 -t ecdsa`), captured 2026-10-06T19:37:27Z.
- Target: the replacement web-2, Hetzner server id 169095540, IPv4 204.168.189.200, created 2026-10-06T19:32:09Z.
- Vantage: directly to web-2's public port 22 from an ADMIN_IPS egress, not via Cloudflare.
- New fingerprint: `SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ` (ECDSA-P256).
  `ssh-keygen -lf` on the committed key line prints the same value.

## Cross-check strength: weak

There was no prior `known_hosts` entry for this IP and no second independent read. This is a
first-sight capture of a brand-new host. A replaced web-2 legitimately changes its key (web-2 is
cattle), so a changed key is expected and is not by itself evidence of anything. The pin proves
what 204.168.189.200 presented at capture time, not the host's identity by an independent
channel. The end-to-end probe in the apply workflow is what re-checks the pin against the live
host once that workflow is re-enabled.

## apply-deploy-pipeline-fix.yml stays paused

`apply-deploy-pipeline-fix.yml` lists this file in its push paths, but the workflow was disabled
when this was written and stays disabled after this PR merges (re-check its state at merge time),
so that workflow does not run. `apply-web-platform-infra.yml` DOES fire on the merge, because it
triggers on any `apps/web-platform/infra/**` push. It is inert for web-2: its allow-list does not
include `deploy_pipeline_fix_web2`, the only resource that hashes this file. Re-enabling
`apply-deploy-pipeline-fix.yml` is a separate owner go-ahead and is not part of this PR; a wrong
pin or a dark web-2 would make that workflow abort before its plan and hold back web-1's
pipeline delivery. This PR does not dispatch, enable, or disable any workflow, write to Doppler,
mint a token, run Terraform, or reboot anything.

## Scope

Only `apps/web-platform/infra/web-2-ssh-host-key.pub` changes. This PR makes no claim about
web-2's disk or encryption state. That evidence is tracked on #9372 and is not established here.

## Tests

- `scripts/capture-web-2-host-key.test.sh`: <N> passed, 0 failed
- `apps/web-platform/infra/web-2-host-key-local.test.sh` (pin-shape check, incl. H1 header vs key): <N> passed, 0 failed
- `web-ghcr-deny.test.sh`, `web-host-provisioner-parity-mutation.test.sh`, `ship-deploy-pipeline-fix-gate.test.ts`: <results>

Ref #9372

## Changelog

- Re-pinned web-2's SSH host key after the 2026-10-06 server replacement.
```

## Acceptance Criteria

- [ ] `cmp` of the captured file and `apps/web-platform/infra/web-2-ssh-host-key.pub` exits 0, and
      `git diff origin/main...HEAD --name-only` lists the pin file plus only files the pipeline
      writes (this plan, `specs/feat-one-shot-9372-web2-host-key-repin/tasks.md`, and any
      `session-state.md` or regenerated `knowledge-base/INDEX.md`); no source, workflow or
      Terraform file.
- [ ] `ssh-keygen -lf apps/web-platform/infra/web-2-ssh-host-key.pub` prints
      `SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ`.
- [ ] `bash scripts/capture-web-2-host-key.test.sh` reports 17 passed, 0 failed.
- [ ] `bash apps/web-platform/infra/web-2-host-key-local.test.sh` reports 23 passed, 0 failed,
      including row `H1`.
- [ ] The three pin-referencing suites listed in Implementation step 3 pass.
- [ ] PR body contains the fingerprint, the capture vantage, the weak-cross-check statement, and
      the paragraph that `apply-deploy-pipeline-fix.yml` stays disabled after merge, that
      `apply-web-platform-infra.yml` fires but is inert for web-2, and that re-enabling is a
      separate owner go-ahead.
- [ ] PR body uses `Ref #9372` and contains no `Closes`/`Fixes`/`Resolves` keyword for it
      (`gh pr view --json body --jq .body | grep -iE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #9372'`
      returns nothing).
- [ ] Neither the PR body, the commit message, nor any changed file says web-2 is LUKS-backed,
      reborn, or encrypted (`grep -inE 'luks|reborn|encrypt'` over the pin file, the commit
      message and the PR body finds only the explicit "makes no claim" sentence; the plan and
      specs files legitimately name the gate and the negations).
- [ ] No workflow dispatch/enable/disable, Doppler write, token mint, Terraform apply or reboot
      was performed in this session.

## Test Scenarios

- Given the captured file copied into place, when `web-2-host-key-local.test.sh` runs, then
  `H1` passes because the `# fingerprint:` header equals `ssh-keygen -lf` of the key line, and the
  HCL local evaluates to exactly the new key line.
- Given the new pin, when the bash twin (`write-known-hosts.sh web-2 <pin>`) runs inside that
  suite, then it accepts the file with the same verdict as the HCL site.
- Given the capture-script suite, when it runs against its stubbed `ssh-keyscan`, then 17/17
  pass; it does not touch the committed pin and does not use the network.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Replace apps/web-platform/infra/web-2-ssh-host-key.pub on main with the file at ..." | Implementation 1 | mapped |
| 2 | "copy it verbatim; do not re-run the capture script and do not edit the key line" | Implementation 1 (`cmp` AC) | mapped |
| 3 | "Put the fingerprint and the capture vantage in the PR body" | PR body draft, Capture | mapped |
| 4 | "The cross-check was weak" | PR body draft, Cross-check strength | mapped |
| 5 | "Include the existing hermetic tests that cover the pin file" | Implementation 3 | mapped |
| 6 | "PR body uses \"Ref #9372\" only, never \"Closes\"" | PR body draft, AC grep | mapped |
| 7 | "Do not claim web-2 is LUKS-backed, reborn or encrypted anywhere" | Scope paragraph, AC grep | mapped |
| 8 | "apply-deploy-pipeline-fix.yml stays paused until this PR merges and that re-enabling it is a separate owner go-ahead" | PR body draft, paused paragraph | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Copy pin file | "Replace apps/web-platform/infra/web-2-ssh-host-key.pub on main" | asked |
| Run both suites | "run the suite for scripts/capture-web-2-host-key.sh and the pin-shape check" | asked |
| Three extra suites (ghcr-deny, parity-mutation, ship gate test) | none | inferred: PR #9305 ran them because they reference this file; a one-line run each, no code change |
| `cmp` / `ssh-keygen -lf` checks | "copy it verbatim ... do not edit the key line" | asked |

### Split Assessment

- Subsystems touched: 1 (`apps/web-platform/infra`)
- Planned files: 1 | Estimated changed lines: ~7
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is a one-file infrastructure pin refresh with no new
infrastructure, no schema, no UI, no copy, and no new architectural decision (ADR-237 already
defines the pin policy), so no ADR/C4 update is required. The Observability, Encryption Posture
and Guard Contract gates do not fire: no code-class file is edited, no store or connection is
introduced, and no guard is added (the existing suites are run, not changed).

## Sharp Edges

- The captured file's comment header omits the IP and egress IP that the previous pin carried
  (it says "web-2's public :22" without the address). That is expected: the file is copied
  verbatim, and the IP and vantage belong in the PR body instead. Do not "fix" the header.
- The pin file is a push-path of `apply-deploy-pipeline-fix.yml`. It is disabled now; if it is
  ever found enabled at merge time, do not dispatch or toggle it from this PR's session. Stop
  and report.
- A plan `## User-Brand Impact` section that is empty or placeholder text fails deepen-plan
  Phase 4.6; this one is filled.
- Do not state or imply web-2's LUKS/encryption/reboot status anywhere (graded reboot proof
  does not exist yet).
