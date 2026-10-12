---
title: "chore(infra): least-privilege kernel-stream read for the deploy user (canary kdeny src=none)"
type: chore
date: 2026-10-11
slug: chore-kdeny-kernel-stream-read-grant
branch: feat-one-shot-10045-kdeny-least-priv
issue: 10045
closes: 10045
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(infra): least-privilege kernel-stream read for the deploy user (canary kdeny src=none)

## Enhancement Summary

**Deepened on:** 2026-10-11 (soleur:deepen-plan; `Reviewed-Coverage: sequential-fallback` — no agent-spawn capability in the planning subagent; gates and lenses run inline)
**Sections enhanced:** Proposed Solution (sudoers `=` escape nuance), Technical Considerations, Risks (precedent-diff), Hypotheses (deep-dive status)

### Key Improvements

1. **sudoers `=` escape documented** — sudoers syntax requires `,` `:` `=` `\` backslash-escaped inside command arguments (sudoers(5)); `--since=-5min` carries one. The in-file precedent (`WEBHOOK_SELF_RESTART`'s `--unit=`/`--on-active=`, live and policy-probed under the fleet's sudo-rs) shows the unescaped form resolves on this fleet — the plan standardizes on it for lockstep-comparability, with the escaped spelling recorded as the fallback if a future sudo rejects it.
2. **Verify-the-negative pass ran** — every load-bearing negative claim grepped against the tree (FILE_MAP sudoers exclusion at `infra-config-apply.sh`, `ignore_changes=[user_data]`, deploy user's no-SSH-key + docker-group posture); all confirmed.
3. **Halt gates swept:** 4.6 user-brand (scope-out present), 4.7 observability (5 fields, allowlisted probe verb, literal `expected_output`, `credentials_required`), 4.8 PAT (no hits), 4.9 UI-wireframe (no UI surface), 4.10 encryption (all fields, no exception needed), 4.11 guard-contract lint (2 entries, green), 4.12 scope-check (single section, all rows mapped/justified), 4.55 downtime (no trigger — no serving-surface reboot/replace/migration).

### New Considerations Discovered

- `visudo -cf` parses both escaped and unescaped `=` in argv (verified locally, GNU sudo) — syntax is not the arbiter; runtime argv matching is, and the fleet's live `--unit=`/`--on-active=` aliases + provisioner probes prove unescaped resolution.
- `cloud-init-inngest.yml`'s `ci-deploy.sh` mentions are comment-only — the canary/kdeny path exists only on web hosts; git-data/inngest/registry stay role-only.

## Overview

The canary DIAG `kdeny` row (PR #9938, tracking #9860) reads `src=none j=noaccess d=noaccess` on
every emission because the unprivileged `deploy` user cannot read the host kernel stream under
`kernel.dmesg_restrict=1` (the Ubuntu 24.04 default on the web hosts — defense in depth, not a
defect). Issue #10045 was carved out of #10032 (the sandbox-shim procfs fix, squash-merged
2026-10-11) as "a separate host-IaC plan with its own apply+gate", and names two candidate shapes:

- **(a)** `systemd-journal` group membership for `deploy` — flagged as needing a blast-radius read
  because `deploy` is already docker-group / root-equivalent.
- **(b)** a fixed-argv sudoers grant, shape-matched to the exact invocation
  `journalctl -k -n 400 --since=-5min --no-pager -o cat` that `_canary_kdeny_read` already runs.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

This plan selects **(b)** and delivers it through the repo's existing host-IaC channels only —
`deploy-inngest-bootstrap.sudoers` (the canonical deploy-user grant file), its byte-parity inline
copy in `cloud-init.yml`, and the two running-host terraform_data bridges
(`infra_config_handler_bootstrap` for web-1, `deploy_pipeline_fix_web2` for web-2) that
`apply-deploy-pipeline-fix.yml` applies automatically on merge. Delivery rides the channels that
already own this file; no new provisioner, no ad-hoc SSH, no operator step.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10045` — verified OPEN via `gh issue view 10045 --json state` (title: "host-IaC:
  least-privilege kernel-stream read for the deploy user (canary kdeny src=none)"). Not closed by
  any PR.
- `#10032` — verified CLOSED (the procfs fix shipped; ADR-075 addendum dated 2026-10-11 records the
  deferral of this item by name: "The least-privilege kernel-stream read for `kdeny` (`src=none`)
  is **#10045**, explicitly not folded into this change").
- `#9860` — verified OPEN (soak-tracking issue; explicitly out of scope, "do not touch").
- PR #9938 — verified MERGED 2026-10-11 (the kdeny row's introducing PR).
- Cited artifacts verified on this branch: `canary-probe-set.md` §`kdeny` row docs exist
  (`knowledge-base/engineering/operations/runbooks/canary-probe-set.md` §"Reading `kdeny`");
  `_canary_kdeny_read` exists at `apps/web-platform/infra/ci-deploy.sh` (function, `src=`/`j=`/`d=`
  state machine, `timeout -k 1 3` per rung); the `SOLEUR-DEBT` note above it names #10045 as the
  open follow-up.
- ADR-corpus check for the proposed mechanism (`sudoers`/`journalctl`/`dmesg`/`systemd-journal`
  greps over `knowledge-base/engineering/architecture/decisions/`): no ADR rejects a fixed-argv
  sudoers grant; the idiom is established by eleven existing `Cmnd_Alias` grants in
  `deploy-inngest-bootstrap.sudoers` (`INNGEST_BOOTSTRAP`, `WEBHOOK_SELF_RESTART`,
  `INNGEST_RESTART`/`STOP`/`START`/`QUIESCE`/`ENABLE`, `INFRA_CONFIG_INSTALL`,
  `GIT_LOCK_CHARDEVICE_SWEEP`, `DROPIN_TRY_RESTART`, `SYSTEMCTL_DAEMON_RELOAD`). The plan's chosen
  mechanism is an application of an in-force pattern, not a rejected alternative.

### Property List (Phase 0.6b)

Restated asks as properties:

1. A `deploy`-user process can read the host kernel stream, bounded to kernel messages and a
   short recent window, so `kdeny` can return `src=journal j=ok`.
2. The grant is least-privilege: it must not widen `deploy`'s ambient read surface beyond what the
   kdeny row needs (no whole-journal read, no follow mode, no write).
3. Delivery is exclusively through the committed host-IaC path (cloud-init for fresh hosts;
   terraform_data bridges for running hosts) — `hr-all-infrastructure-provisioning-servers`.
4. The apply has its own gate: post-delivery assertions prove the grant is *effective* (not just
   present as bytes), per the #7220 policy-probe precedent.
5. A host whose grant has not landed (rollout window, or a host rebuilt from a stale image) must
   degrade to today's `src=none`/`noaccess` reading, never to a new failure class.

### Cut List (Phase 0.6b)

- **`systemd-journal` group membership (candidate (a)) → property 1** — also satisfies it, but
  fails property 2 (ambient whole-journal read by every deploy-uid process, no per-read audit).
  Rejected; see "Alternatives considered".
- **Root helper script (`/usr/local/bin/kdeny-read`)** → property 1 via a new indirection — cut:
  `/usr/local/bin/*` dests carry no content gate (canonical sudoers comment, path 2), so a
  deploy-writable-then-root-executed helper adds an integrity surface the pinned-argv form does not
  need. The 2026-06-02 sudo-helper-hardening learning documents exactly this trap class.
- **`dmesg` sudoers grant** → redundant: the journal rung answers first when the grant is in place
  (`d=skip`); a bare `dmesg` grant would expose the unbounded ring buffer — wider than the `-k`
  bounded journal read.
- **New terraform_data resource** → cut: the artifact (sudoers file) already rides three existing
  resources; a new dialer would trip `web-host-provisioner-parity.test.sh` for zero benefit.
- **Webhook FILE_MAP delivery** → cut (and already excluded on main): the sudoers file is
  deliberately root-managed; the webhook path must never mutate the file that defines its own
  privileges (2026-06-02 learning, trap 2).

### Relevant file paths

| Path | Role |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | `_canary_kdeny_read` (~L1717), `emit_canary_sandbox_diag` (~L1785); the `SOLEUR-DEBT` comment (~L1714) |
| `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` | canonical grant file; carries the "WHAT THE `deploy` USER ALREADY IS" statement |
| `apps/web-platform/infra/cloud-init.yml` | `write_files` inline copy at `path: /etc/sudoers.d/deploy-inngest-bootstrap` (~L83); `users:` deploy entry `groups: docker` (~L48-55) |
| `apps/web-platform/infra/server.tf` | `terraform_data.infra_config_handler_bootstrap` (~L1719, web-1 root SSH bridge: stage → `visudo -cf` → `install -o root -g root -m 0440` → grep + `sudo -n -l -U` policy probes); `terraform_data.deploy_pipeline_fix_web2` (~L2162, web-2 via web-1 bastion; same install + sha256 + grep + policy-probe battery; sentinel `"dpf-web2-remote-exec-v2"` at end of `triggers_replace`) |
| `apps/web-platform/infra/ci-deploy.test.sh` | kdeny fixture battery D10a–D10x (~L4246+); `journalctl`/`dmesg` PATH mocks (~L103-151) with `MOCK_KLOG_*` knobs incl. `MOCK_KLOG_*_ERR` (stderr channel) and `_RC` |
| `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` | AC5 comment-stripped byte-parity between the `.sudoers` source and the cloud-init inline block (~L203-240); "ci-deploy.sh invokes the sudoers-pinned path" grep pattern to mirror |
| `apps/web-platform/infra/git-lock-chardevice-sweep.test.sh` | argv-lockstep precedent (~L196-209): asserts sudoers alias argv == the argv ci-deploy.sh invokes |
| `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` | asserts the web-1 bridge's verify greps (~L155-180) — extend for the new alias |
| `apps/web-platform/infra/web-host-provisioner-parity.test.sh` | `FLEET_SSH_HOSTS = {web-1, web-2}`; classifies every SSH `terraform_data` — no new dialer, but the fan-out classification must be recorded |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | auto-applies on merge for the `paths:` set (includes `deploy-inngest-bootstrap.sudoers`, `ci-deploy.sh`, `server.tf`; `cloud-init.yml` is birth-only by `ignore_changes=[user_data]` so it is deliberately absent); `-target` list covers both delivery bridges |
| `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` | §kdeny row semantics + "Reading `kdeny`" — needs updating for the privileged path |
| `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` | its "Deferred" paragraph names #10045 — amend to resolved |
| `scripts/betterstack-query.sh` | Better Stack Logs SQL query entrypoint (env `BETTERSTACK_API_TOKEN` via `doppler run -p soleur -c prd_terraform`) — the kdeny-row query path for post-apply observation |

### Institutional learnings applied

- `learnings/security-issues/2026-06-02-deploy-user-sudo-helper-hardening.md` — a path-pinned
  sudoers grant moves the boundary into whatever the argv resolves to; prefer a pinned *binary
  argv* (journalctl itself, fixed flags) over a helper whose content deploy can influence. Also:
  never let the deploy-writable channel write the sudoers file — preserved here (root-managed
  channels only).
- `learnings/2026-05-26-ssh-to-webhook-provisioner-migration-mount-namespace-traps.md` — sudo
  matches the resolved command plus args as literal strings; invoke with the full path and copy the
  exact argument list into the call site — never retype (hence the lockstep test below).
- `learnings/bug-fixes/2026-05-20-pat-to-app-auth-migration-and-sudo-rs-no-wildcards.md` — Ubuntu
  24.04 sudo-rs rejects argument wildcards; the grant must be wildcard-free. Ours is.
- `learnings/2026-10-11-every-fixture-of-the-kernel-denial-row-fed-the-hints-through-stdout...md` —
  the kdeny mocks must reproduce real channel behavior (hints on stderr, multi-denial selection);
  new `sudo` mock must emit its denial on stderr with rc 1, and fixtures must exercise both arms.
- `learnings/test-failures/2026-07-17-a-drift-guard-scoped-by-resource-name-is-addition-blind.md` —
  keep the verify battery as named greps/probes the tests can assert, not prose.
- `2026-06-02-deploy-pipeline-fix-false-success-202-trigger-and-forget` (bug-fixes) — delivery
  channels report 202 before files land; the gate belongs in the provisioner's remote-exec asserts
  (grep + policy probe + execute probe), not in post-hoc observation.

### Repo conventions

- sudoers grants: `Cmnd_Alias <NAME> = <full path> <exact args>` + `deploy ALL=(root) NOPASSWD: <NAME>`
  + rationale comment citing the issue; the cloud-init copy carries a compressed comment
  (byte-budgeted, `#6090` sub-cap) and must match comment-stripped (`grep -vE '^\s*#|^\s*$'`).
- Every running-host delivery ends with positive post-write assertions (grep presence, sha256
  content equality, `sudo -n -l -U` policy probes, idempotent execute probes) — fail loud, never
  silent drift (#4792/#7220 pattern).
- `triggers_replace` already hashes `deploy-inngest-bootstrap.sudoers` in all three consumers —
  the file edit re-fires them; the `deploy_pipeline_fix_web2` inline-edit sentinel
  (`dpf-web2-remote-exec-v2`) must still be bumped because its remote-exec content changes.

### Community discovery / functional overlap

- Phase 1.5 stack-gap check: no uncovered stacks — bash/HCL/cloud-init only, all repo-native.
- Phase 1.5b functional overlap: not applicable — the deliverable is repo-local host IaC
  (a sudoers grant for a canary row that exists only in this codebase); no community artifact can
  ship it. `Reviewed-Coverage: sequential-fallback` — no Task/agent spawn capability exists in this
  planning subagent context; all prescribed fan-outs were performed inline in this session.

## Problem Statement / Motivation

`kdeny` exists to decide between H6 (docker's masked `/proc` silently EPERMing a fresh procfs
mount — silent, no kernel record) and H7 (the `soleur-bwrap` AppArmor profile DENYing the mount —
kernel-audited, `type=1400` with `operation="mount" fstype="proc"`). It cannot decide either way
while `src=none`: every bundle reports "could not read", which the runbook explicitly ranks as
neutral. #10032 resolved the underlying procfs failure at the shim layer, but the NEXT
H6/H7-undecided incident (or a regression of this one) would again have no host-side witness.

The grant is deliberately deferred-scoped, per the issue's re-evaluation criteria: it exists to
restore a diagnostic the incident field already paid for, not to grow `deploy`'s ambient power.

## Proposed Solution

Add one `Cmnd_Alias` + one grant line to `deploy-inngest-bootstrap.sudoers`:

```sudoers
Cmnd_Alias KDENY_KERNEL_STREAM = /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat
deploy ALL=(root) NOPASSWD: KDENY_KERNEL_STREAM
```

`-k` restricts journalctl to kernel messages (dmesg-equivalent scope inside the journald store);
`-n 400 --since=-5min` bound volume and window; `--no-pager -o cat` produce raw lines with no pager
and no metadata envelope. Sudo (and sudo-rs) match the resolved command **plus its argument list**
literally, so the caller cannot widen scope — any argv that differs is denied, not broadened. Every
invocation emits a `sudo: deploy : … COMMAND=` record into the same journal — self-auditing.

`_canary_kdeny_read` changes minimally: the journal rung first attempts
`timeout -k 1 3 sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` (`timeout`
stays outside sudo — the escalated argv is journalctl alone); when sudo itself denies (its own
`sudo:`/`Sorry,`-prefixed stderr class — `sudo: deploy : command not allowed` (sudo-rs, recorded) / `Sorry, user … not allowed to execute` (GNU)), the rung
falls back to today's unprivileged `journalctl` read, preserving the current `noaccess`/`empty`
semantics during the delivery window or on a host that predates the grant. A journalctl-under-root
failure (rc≠0 after sudo accepted the argv) classifies through the existing state machine — under
root the permission-hint paths cannot be hit, so output is lines or a genuine error, both honest.

The `src=`/`j=`/`d=` vocabulary is unchanged — `src=journal` continues to name the *stream*, not
the privilege path that reached it. The `dmesg` rung stays unprivileged (it only runs when the
journal rung did not answer; under the grant it stays `d=skip`).

### Alternatives considered

| Option | Verdict |
|---|---|
| (a) `usermod -aG systemd-journal deploy` (cloud-init `groups:` + usermod remote-exec) | **Rejected.** Blast-radius read per the issue: `deploy` is already root-equivalent by documented decision (docker group; `deploy-inngest-bootstrap.sudoers` "WHAT THE `deploy` USER ALREADY IS" block; `2026-03-20-security-deploy-ssh-user-privilege-boundary-plan.md`), so the group adds no new *ceiling*. What it adds is *ambient* reach: every process running as `deploy` reads the ENTIRE journal — all units' stdout (webhook, vector, sshd auth, dockerd), not just kernel — persistently, silently, with zero per-read audit. Under the grant-free posture that ambient surface is deliberately absent. (b) is strictly narrower: kernel transport only, bounded window, transient, and every read logged by sudo. |
| Fixed-argv sudoers on `dmesg` | **Rejected.** The `dmesg` rung is the fallback; a grant there exposes the unbounded ring buffer with no time window — wider than the journal `-k` read it would supplement. The journal rung alone satisfies the diagnostic (runbook: `src=journal` is the strongest rung). |
| Root-owned helper script (`/usr/local/bin/kdeny-read.sh`) + bare-command grant | **Rejected.** Repo precedent (`INFRA_CONFIG_INSTALL`) shows the helper pattern is for *dest-allowlist* enforcement; here it buys nothing over a pinned argv and adds a deploy-influenceable file to the root exec path (2026-06-02 learning). |
| `setfacl -m u:deploy:r` on `/var/log/journal` | **Rejected.** File-level access = whole-journal read (journalctl filters client-side), same exposure as (a) minus group semantics, plus a second ACL-maintenance channel. |
| Leave `src=none` (do nothing) | Rejected by the issue's own scoping — but note the issue's re-evaluation clause: this grant exists because a diagnostic was promised; it is NOT a precedent for wider grants. |

## Technical Considerations

- **sudo-rs safety (Ubuntu 24.04):** no argument wildcards — the argv is fully literal. Confirmed
  idiom-wide in the same file.
- **Full-path + exact-argv contract:** `ci-deploy.sh` must invoke `sudo -n /usr/bin/journalctl …`
  verbatim (resolved path, fixed arg order). A lockstep test extracts the invoked argv from
  `ci-deploy.sh` and asserts it matches the `Cmnd_Alias` body — both directions (drift denies,
  never widens).
- **`sudo -n`:** non-interactive, fails fast — the reader runs unattended inside `webhook.service`
  (`User=deploy`; `NoNewPrivileges` deliberately omitted so sudo works — `webhook.service` comment
  citing #967).
- **Rollout ordering:** `ci-deploy.sh` reaches hosts via the webhook FILE_MAP channel and
  cloud-init, independently of the root-managed sudoers file. The fallback-to-unprivileged design
  means a host mid-window emits today's `noaccess`, not a new `error` class. Conversely the grant
  is *sufficient* before `ci-deploy.sh` updates: nothing new runs until the reader calls it.
- **Apply-time gate (#7220 pattern):** each delivery bridge gains a `grep -q KDENY_KERNEL_STREAM`
  content assert and an idempotent *execute* probe `runuser -u deploy -- sudo -n
  /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat >/dev/null` — the strongest
  assertion class (proves the grant effective, not merely present). The existing `sudo -n -l -U
  deploy` list-mode availability preflight already runs in both blocks, so no new canary is needed;
  the execute probe's failure text names the grant so a denial cannot masquerade as a probe-bug.
- **sudoers `=` escaping (deepen finding):** sudoers(5) requires `,` `:` `=` `\` backslash-escaped
  inside command arguments, and our argv carries one: `--since=-5min`. The in-file precedent —
  `WEBHOOK_SELF_RESTART`'s `--unit=webhook-self-restart` / `--on-active=3s` — is written
  UNESCAPED and resolves on the fleet's sudo (its `sudo -n -l -U` policy probe runs in every
  bridge apply). This plan standardizes on the unescaped spelling to match precedent AND keep the
  Guard-1 argv comparison byte-literal (alias body == invoked argv, no unescaping step). If a
  future sudo/sudo-rs build ever rejects it, the documented fallback is the escaped spelling
  `--since\=-5min` — and the provisioner execute probe is what arbitrates, failing the apply
  rather than shipping a non-resolving grant.
- **Environment:** `NOPASSWD` + default `env_reset` means the escalated journalctl runs with a
  scrubbed env (no `PAGER`, no `SYSTEMD_*` overrides) — `--no-pager` is belt-and-braces.
- **Audit routing caveat (unchanged):** `j=ok hits=0` can still be a false negative where auditd
  reroutes audit records — the row's documented neutrality is unaffected; what changes is that
  `src=none` now means "genuinely unreachable", not "denied by default".
- **NFRs:** security surface — one new root-mediated read, bounded argv, audited per invocation;
  reliability — fallback preserves the degraded-mode contract; no performance NFR impact
  (diagnostic path, ≤3 s per rung unchanged).

### Attack surface enumeration (security fix surface)

What the grant lets any `deploy`-uid process do that it could not do before:

- Run, as root, exactly `/usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` — read
  ≤400 kernel-log lines from the last 5 minutes, no `-f`, no unit/user selector beyond `-k`, no
  cursor manipulation, no output-file write.
- Everything else is denied at the sudo policy layer, and denial is the drift failure mode.

What it does **not** grant: `dmesg` (still blocked by `kernel.dmesg_restrict=1` for unprivileged
`deploy`), arbitrary journalctl argv (unit logs of webhook/vector/sshd stay unreadable to
`deploy`-as-deploy), file writes, shell escapes, `--vacuum-*`, `-D`/`--directory` journal
manipulation, or any systemd control verb.

Unchecked paths acknowledged: `deploy` is already root-equivalent via docker group (documented,
accepted) — this grant adds an *audited, bounded* capability, not a new escalation primitive.
`journalctl` itself carries no known command-injection or editor/pager path under `-o cat
--no-pager` with reset env.

## Hypotheses

Triggered per Phase 1.4 (the plan touches `terraform_data` resources with `provisioner "file"` /
`provisioner "remote-exec"` under `connection { type = "ssh" }`; the feature text also names SSH).
This is not an outage-diagnosis plan; the L3→L7 checks below verify the *apply path's* SSH
dependency the provisioners carry.

1. **L3 — firewall / tunnel reachability.** The bridges do not dial public :22 directly: CI opens
   a pinned cloudflared forward (`ssh.<domain>` → web-1 `10.0.1.10:22`; web-2 via web-1 bastion
   `127.0.0.1:2223`) and NAT-redirects the Go SSH client's target to loopback
   (`apply-deploy-pipeline-fix.yml` bridge setup; ADR-114 origin-relative ingress; ADR-220).
   `var.admin_ips` ingress is NOT on this path. [verified — wiring committed in
   `.github/workflows/apply-deploy-pipeline-fix.yml` and `server.tf` `connection` blocks]
2. **L3 — DNS/routing.** GitHub-runner → Cloudflare edge → tunnel connector on web-1; the route is
   the same channel `infra-config` pushes already use on every merge. Host-key verification is
   pinned (`local.web_1_ssh_host_key`, `web-2-ssh-host-key.pub` in `triggers_replace`).
   [verified — same channel green on every deploy_pipeline_fix apply]
3. **L7 — TLS/proxy.** The CF Access service-token auth on the `ssh.`/`deploy.` ingress is the
   existing mechanism (ci-ssh-key.tf / workflow env); no new HTTPS surface is added.
   [verified — unchanged surfaces]
4. **L7 — service layer.** sshd `AllowUsers root` is deliberate (bridge connects as root); the CI
   key lands via `terraform_data.root_authorized_keys`. No sshd/fail2ban change is proposed by
   this plan. [verified — out of scope, no service-layer hypothesis needed]

**Deep-dive status (deepen-plan Phase 4.5):** all four layers carry a cited artifact or an explicit
out-of-scope note above; no unverified service-layer hypothesis precedes them. No gaps to close
before implementation — the apply path introduces zero new connectivity (the same bridges already
deliver this file on every sudoers edit).

## Implementation Phases

### Phase 1 — Grant definition + delivery plumbing (sudoers, cloud-init, server.tf)

1. `deploy-inngest-bootstrap.sudoers`: append `Cmnd_Alias KDENY_KERNEL_STREAM` + grant line with a
   rationale comment citing #10045 (style: the file's existing issue-tagged blocks).
2. `cloud-init.yml`: add the same content lines (comments compressed per byte budget) to the
   `/etc/sudoers.d/deploy-inngest-bootstrap` `write_files` block so the comment-stripped parity
   holds (`cloud-init-inngest-bootstrap.test.sh` AC5).
3. `server.tf` `terraform_data.infra_config_handler_bootstrap` remote-exec: add
   `grep -q KDENY_KERNEL_STREAM /etc/sudoers.d/deploy-inngest-bootstrap` beside the existing alias
   asserts, plus the execute probe
   `runuser -u deploy -- sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat >/dev/null || { echo 'FATAL: …' >&2; exit 1; }`
   — the execute probe subsumes the `sudo -n -l -U` list-mode policy check (an effective read
   proves the policy resolved; the block's existing list-mode availability preflight stays as the
   sibling grants' canary). Adding a second `-l <argv>` probe would assert nothing the execute
   probe does not (plan-review simplification).
4. `server.tf` `terraform_data.deploy_pipeline_fix_web2` remote-exec: the same two assertions;
   bump the inline sentinel `dpf-web2-remote-exec-v2` → `dpf-web2-remote-exec-v3` (documented
   lockstep for remote-exec content edits).

### Phase 2 — Reader change (ci-deploy.sh)

5. `_canary_kdeny_read` journal rung: attempt the `sudo -n` form first; on a sudo-denial
   signature run the existing unprivileged `journalctl` read unchanged. The denial discriminator
   is **sudo's own error channel**: non-zero rc AND a recognized denial phrase AND captured output carrying only `sudo:`/`Sorry,`-prefixed
   lines (the class covering `command not allowed` / "not allowed to execute" / "a terminal is
   required") AND zero kernel lines — never journalctl's own output shape. Implementation note:
   verify the exact denial text sudo-rs emits on a web host (sudo-rs phrasing differs from GNU
   sudo; the recorded fleet emission `sudo: deploy : command not allowed` (sudo-rs) plus the GNU `Sorry,` shape were pinned in the
   fixture — match by the tool's own prefix, not a hardcoded sentence. Keep `2>&1` semantics, the
   `tac` / `head -c 65536` newest-first bounds, and all counters identical for either path. A
   journalctl run that sudo *accepted* (no `sudo:` denial line) classifies through the existing
   state machine — under root the hint paths are unreachable, so output is lines or real error.
6. Update the function's header comment (grant existence + fallback contract), and re-scope the
   `SOLEUR-DEBT` note: the grant lands with this change; the row stays while #9860 soaks (the
   note's own disposition sentence names that fork).

### Phase 3 — Tests

7. `ci-deploy.test.sh`: extend the kdeny mock harness — a `sudo` mock that validates argv is
   exactly `-n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` then execs the
   journalctl mock; a `MOCK_SUDO_DENY=rs|gnu` knob emitting the denial to **stderr** with rc 1 (the
   stderr-channel lesson). New fixtures: grant present+journal answers (`src=journal j=ok`),
   grant present+journal silent-empty (`j=empty`, then dmesg), grant denied (`sudo:` stderr)
   → fallback produces today's `noaccess`/`empty` shapes, denial-vs-journalctl-error
   discrimination (a root journalctl failure classifies, never re-falls-back), and
   `dmesg`-rung-unchanged coverage.
8. `cloud-init-inngest-bootstrap.test.sh`: extend the AC5 block with a kdeny argv-lockstep assert
   (mirror the `inngest-bootstrap` "invokes the sudoers-pinned path" assert): extract the journalctl
   argv ci-deploy.sh passes to sudo, assert the `Cmnd_Alias` body matches it exactly in BOTH the
   `.sudoers` source and the cloud-init inline block. Extraction note: split the alias line on its
   FIRST `=` only (the assignment operator) — the argv itself contains `=` inside `--since=-5min`,
   so a naive `cut -d= -f2` truncates mid-flag.
9. `infra-config-handler-bootstrap.test.sh`: extend the verify-block asserts to pin the new
   `grep -q KDENY_KERNEL_STREAM` + `runuser … journalctl` execute-probe lines in the remote-exec
   (the file's existing AC7-style asserts are the pattern).

### Phase 4 — Docs, ADR note, apply+gate

10. `canary-probe-set.md` §kdeny: document that `j=ok`/`src=journal` is now the expected reading on
    grant-bearing hosts; add the fallback contract (a `noaccess` post-rollout means the grant did
    not land — read the provisioner's FATAL / re-run the bridge's `runuser` execute probe); note
    each read is journal-audited via sudo's `COMMAND=` record.
11. ADR-075: amend the "Deferred" paragraph — #10045 resolved by this change (one-line status
    update; no Decision change).
12. Apply gate: merge triggers `apply-deploy-pipeline-fix.yml` (paths already cover the touched
    files) → both bridges re-run → remote-exec asserts prove the grant *effective* on web-1 and
    web-2. Post-apply observation: the next `sandbox_broken` bundle reports `src=journal`; a
    Better Stack query (`betterstack-query.sh`, runbook recipe) is the read path. No bundle emits
    on a healthy deploy — the provisioner probes are the landing gate, not a live kdeny row.

## Files to Create

None. (No new provisioner, helper, or test file — all changes extend existing artifacts.)

## Files to Edit

- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`
- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/server.tf`
- `apps/web-platform/infra/ci-deploy.sh`
- `apps/web-platform/infra/ci-deploy.test.sh`
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
- `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`

## User-Brand Impact

- **If this lands broken, the user experiences:** no new surface — worst realistic case is the
  status quo (`kdeny` unreadable) or a loud apply failure (`visudo -cf` gates a malformed file
  before install; the remote-exec asserts fail the provisioner). Deploys continue; tenants see
  nothing.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the grant's only new
  reach is ≤400 kernel-stream lines to a user that is already root-equivalent by documented
  decision; kernel text is scrubbed by the row's closed key set before it can reach Better Stack.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change is a bounded, audited diagnostic read on
  operator-owned infra with no tenant-data adjacency — a level below `single-user incident`.

*Scope-out override (diff touches a sensitive path — `*.sudoers`, host IaC):* `threshold: none, reason: the grant is a read-only, fixed-argv, per-invocation-audited diagnostic capability on a user already documented root-equivalent; no tenant-facing surface changes`.

## Observability

```yaml
liveness_signal:
  what: "the `kdeny` DIAG row itself — its `src=` field reports journal|dmesg|none per emitted bundle"
  cadence: "per `sandbox_broken` canary event (the bundle's only emission arm)"
  alert_target: "existing sandbox-canary Sentry page (sandbox-canary op) + Better Stack DIAG rows"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (`emit_canary_sandbox_diag` → `_canary_diag_emit`)"

error_reporting:
  destination: "ci-deploy logger rows → Vector → Better Stack (`SOLEUR_CANARY_SANDBOX_DIAG`); apply-time: terraform remote-exec FATAL lines + `apply-deploy-pipeline-fix.yml` failure"
  fail_loud: "provisioner FATAL on missing/denied grant; at runtime `j=noaccess|error` in a bundle"

failure_modes:
  - mode: "sudoers edit lands but grant is inert (argv drift between reader and alias)"
    detection: "apply-time `runuser … sudo -n journalctl <exact argv>` execute probe (effective-not-present); repo lockstep test prevents the drift upstream"
    alert_route: "`apply-deploy-pipeline-fix.yml` run fails the provisioner — loud, before merge of any dependent state"
  - mode: "host without the grant (rollout window, stale birth)"
    detection: "kdeny falls back to the unprivileged rung: `src=none`/`noaccess` — today's reading, not a new failure class; distinguishable post-rollout via the bridge's `runuser` execute probe"
    alert_route: "kdeny row itself (Better Stack); runbook §kdeny updated to read it"
  - mode: "sudo-rs or policy rejects `sudo -n -l -U` list mode (#7220 lesson)"
    detection: "the availability preflight line fails with a named FATAL, distinct from a denial"
    alert_route: "apply run failure"

logs:
  where: "host journal (sudo `COMMAND=` record per granted read — the audit trail); `ci-deploy` syslog rows → Better Stack"
  retention: "journald persistent + bounded (`journald-soleur.conf`, `terraform_data.journald_persistent`); Better Stack per plan retention"

discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 6h --limit 100 --grep 'section=kdeny'"
  expected_output: "section=kdeny"
  credentials_required: "Better Stack Telemetry API token via `doppler run -p soleur -c prd_terraform` — the grant's live effectiveness has no unauthenticated local substitute (host sudo policy is not repo-readable); Check 10 SKIP-DECLAREDs"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — `terraform_data.infra_config_handler_bootstrap`
  remote-exec: +2 assert lines (alias grep, execute probe).
  `terraform_data.deploy_pipeline_fix_web2` remote-exec: +2 same asserts; sentinel bump
  `dpf-web2-remote-exec-v2 → v3`. No new resource, provider, or variable.
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` — content change (the file both
  bridges already deliver).
- `apps/web-platform/infra/cloud-init.yml` — fresh-host `write_files` mirror.

### Apply path

**(a-variant, terraform_data channel):** no server `-replace` needed — the sudoers file already
rides running-host delivery via the two SSH bridges, and this plan changes its *content*, not the
host's image or cloud-init surface. Merge to `main` auto-fires `apply-deploy-pipeline-fix.yml`
(the `paths:` filter covers every delivery-bearing touched file), which `-target`s
`deploy_pipeline_fix`, `infra_config_handler_bootstrap`, `deploy_pipeline_fix_web2` (+
`docker_seccomp_config`, `apparmor_bwrap_profile`). Expected downtime: none — the change is a file
install plus read-only probes; the webhook restart on the bridge is sub-second and existing.
Blast radius: bounded by `visudo -cf` before install and by `set -e` asserts; a bad file can never
reach `/etc/sudoers.d/`.

### Host fan-out

| Host | Class | Coverage |
|---|---|---|
| web-1 | twin | `terraform_data.infra_config_handler_bootstrap` (root SSH bridge) installs + asserts |
| web-2 | twin | `terraform_data.deploy_pipeline_fix_web2` (web-1 bastion) installs + asserts |
| git-data / inngest / registry hosts | role-only | `ci-deploy.sh` and the canary exist only on web hosts; no `kdeny` row is emitted there — naming this classification so the parity guard's intent is on record (`FLEET_SSH_HOSTS` covers only web-1/web-2) |
| fresh web hosts | birth-covered | `cloud-init.yml` write_files entry (this plan's mirror edit) |

### Distinctness / drift safeguards

- `hr-prod-host-config-change-immutable-redeploy` is honored in form, not just letter: the change
  arrives exclusively through Terraform-managed provisioners in CI apply — the repo's sanctioned
  running-host channel for this exact file set — and cloud-init for births; no operator SSH.
- Content parity is mechanical: sha256 file asserts on web-2; comment-stripped parity test for
  cloud-init; `visudo` gates syntax; policy probes gate semantics.
- `lifecycle.ignore_changes=[user_data]` on `hcloud_server.web` means cloud-init edits are
  fresh-host only — the running-host bridges are the load-bearing delivery, which is why their
  asserts are the apply gate.

### Vendor-tier reality check

None — Hetzner-only hosts already provisioned; no new vendor resource or tier-gated API.

## Encryption Posture

Detection fired on the `server.tf` edit (`\.tf$`); the change introduces **no new persistent store
and no new cross-component/network connection**. Posture rows below document the inherited
channel the delivery bytes traverse, for completeness:

```yaml
at_rest:
  - store: "/etc/sudoers.d/deploy-inngest-bootstrap (host file)"
    mechanism: "root:root 0440 on the host root fs — a policy file, not a data store; no data at rest"
    evidence: "server.tf remote-exec `install -o root -g root -m 0440`"
    defends_against: "tamper by non-root host processes (mode 0440 root:root)"
    does_not_defend: "a root-equivalent principal (deploy via docker, by documented decision) or any committed-content defect — visudo checks syntax, not intent"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — remote-exec sha256 + grep + policy probes"
in_transit:
  - connection: "CI runner -> host sshd (via Cloudflare Tunnel forward + NAT redirect)"
    enforced_at: "server.tf `connection { type = \"ssh\" host_key = local.web_1_ssh_host_key … }` + apply-deploy-pipeline-fix.yml bridge"
    tls: "SSH (not TLS); server host key pinned in-repo (`web-1-ssh-host-key`/`web-2-ssh-host-key.pub`)"
    cert_verification: "on (pinned host key — verification is the pin itself)"
    does_not_defend: "a stolen CI SSH private key or cloudflared access token (both scoped, Doppler-held)"
    disclosed_as: "not-publicly-claimed"
```

No `exception` block — no plaintext-exception mechanism and no `cert_verification: off` row.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-075** (`knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`):
its "Deferred" paragraph names #10045 as the explicitly-not-folded follow-up; landing this change
closes that deferral. In-scope task (Phase 4): update the paragraph to "resolved by #10045" with
the grant's one-line shape. **No new ADR** — this plan applies the existing fixed-argv sudoers
idiom; it creates no ownership move, substrate, or boundary invariant a future reader could be
misled about. The provisional-ordinal risk does not apply (no new ordinal claimed).

### C4 views

**No C4 impact.** Enumeration per the completeness mandate (all three files read —
`model.c4` 956 lines, `views.c4` 129, `spec.c4` 54):

- (a) external human actors: none added — `deploy` is an internal service uid, not a modelled
  actor, and its sudo channel to the host is pre-existing.
- (b) external systems/vendors: none — no new API, webhook, or store.
- (c) containers/data-stores touched: the host journal is not a modelled store; the change writes
  one policy file inside already-modelled `webHost` territory (Hetzner cluster element).
- (d) access relationships changed: none at model granularity — `deploy`'s sudoers-mediated
  privilege surface is a host-internal detail already treated as root-equivalent by the corpus.

### Sequencing

The ADR-075 amendment ships in this PR (same commit set), not a follow-up.

## Guard Contract

### Guard 1 — sudoers↔reader argv lockstep

**Property.** The `Cmnd_Alias KDENY_KERNEL_STREAM` argv in `deploy-inngest-bootstrap.sudoers`,
the argv `ci-deploy.sh` passes after `sudo -n`, and the provisioner policy/execute probes all name
byte-identical command+args — any drift denies (fails closed), never widens.

**Assembly.** Three text surfaces, one chokepoint each: (1) the `Cmnd_Alias KDENY_KERNEL_STREAM =`
line in the `.sudoers` source AND its comment-stripped cloud-init mirror (parity is separately
guarded by AC5); (2) the `sudo -n /usr/bin/journalctl …` invocation inside `_canary_kdeny_read` in
`ci-deploy.sh` — the ONLY call site for the grant; (3) the `runuser … sudo -n <argv>` execute
probes inside BOTH `server.tf` remote-exec blocks. The test extracts (2) by grep from
`ci-deploy.sh` and asserts it equals (1)'s alias body in both file copies, and greps (3) in
`server.tf` for the same argv.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reorder two flags in the ci-deploy.sh invocation only (e.g. `--no-pager` before `-n 400`) | RED — call-site ≠ alias |
| 2 | Drop `--since=-5min` from the `Cmnd_Alias` body only | RED — alias ≠ call-site |
| 3 | Delete the `KDENY_KERNEL_STREAM` extraction grep from the test itself (guard dispatch) — the extracted argv is empty | RED — assert on non-empty extraction plus match |
| 4 | Add a SECOND `Cmnd_Alias` line granting `journalctl` a different argv (e.g. `-u nginx`) alongside the compliant first | RED — census counts all journalctl-granting lines for deploy, not the first |
| 5 | Change the cloud-init inline copy's alias argv while the `.sudoers` source stays correct | RED — parity + argv asserts read the inline block too |
| 6 | (harness) Replace the assertion body with `exit 0` / a comment | RED — suite asserts the kdeny lockstep block exists and runs (assert count floor) |
| 7 | (harness must-PASS, non-canonical) Alias order varied within the *file* (grant line before Cmnd_Alias) with identical argv | PASS — sudoers evaluation is order-insensitive across definitions |

**Anchor.** The argv is compared across committed files in the same diff — a weakening must edit
the call site AND alias AND probes consistently, which is precisely the drift the guard exists to
catch (a divergent partial edit reds).

### Guard 2 — apply-time grant-effectiveness battery

**Property.** After `apply-deploy-pipeline-fix.yml` applies the bridges, the grant is provably
*effective* for `deploy` on each web host — not merely present as file bytes.

**Assembly.** The remote-exec tails of `infra_config_handler_bootstrap` (web-1) and
`deploy_pipeline_fix_web2` (web-2): `visudo -cf` (syntax), `install -o root -g root -m 0440`
(atomic placement), sha256 equality (web-2; bytes), `grep -q KDENY_KERNEL_STREAM` (content), the
pre-existing `sudo -n -l -U deploy` list-mode availability preflight, and the `runuser` execute
probe (which subsumes a list-mode `-l <argv>` policy probe — an effective read proves the policy
resolved). `set -e` makes any assertion's failure abort the apply.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Ship the file without the grant line (alias defined, `deploy ALL=` absent) | RED — execute probe's sudo denies |
| 2 | Change the alias argv on-host only (e.g. add `-u sshd`) while repo stays correct | RED — sha256/grep content asserts |
| 3 | Remove the `runuser` execute probe from the battery (guard's own dispatch) | RED — `infra-config-handler-bootstrap.test.sh` asserts the probe line exists |
| 4 | Make `sudo -n -l -U` unavailable on the host (sudo-rs regression) | RED — the pre-existing preflight FATALs with the named message, distinct from denial |
| 5 | (harness must-PASS) A quiet host journal (zero kernel lines in the window) with the grant present | PASS — `journalctl -k` rc 0; probes assert exit code, not content |

**Anchor.** The battery compares live host policy against committed bytes; a weakening must change
the repo artifacts, which the sha256/grep asserts resolve against `path.module` — outside the
commit, only a full fresh host re-apply under different bytes could diverge, and that is the
declared (cloud-init) path.

## Domain Review

**Domains relevant:** Engineering | `Reviewed-Coverage: sequential-fallback` — no agent-spawn
capability exists in this planning subagent; the assessments below were performed inline by the
orchestrator, not by an independent leader.

### Engineering

**Status:** reviewed
**Assessment:** Infra/security-adjacent change on prod web hosts. The dominant risks are (i) a
widening the issue explicitly cautioned against — mitigated by choosing fixed-argv over group
membership, by the closed-flag journalctl argv, and by the ambient-surface argument (whole-journal
ambient read rejected); (ii) delivery-window drift — mitigated by the unprivileged fallback; (iii)
the "present but inert" class — mitigated by policy+execute probes per #7220. The design reuses the
canonical sudoers file and its three delivery channels, so no new mechanism is introduced. The
blast-radius read the issue required for candidate (a) is recorded under Alternatives considered,
citing the file's own canonical "deploy is already root-equivalent" statement.

**Domains not relevant:** Marketing, Operations (no vendor/procurement), Product, Legal, Sales,
Finance, Support. Product/UX Gate: **none** — mechanical UI-surface scan of Files to Edit
(`*.sh`, `*.tf`, `*.yml`, `*.sudoers`, runbook/ADR `.md`) matches no `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or ui-surface term; no user-facing surface.

## Open Code-Review Overlap

One open `code-review` issue touches a planned file:

- **#2197** (`refactor(billing): SubscriptionStatus type + …`) mentions
  `apps/web-platform/infra/server.tf` — but only as the site of a hypothetical future
  `count`/`for_each` edit scaling the web server (in-memory rate-limiter assumption). This plan
  adds remote-exec assert lines inside `terraform_data` resources — it changes no server
  count/scaling semantics. **Disposition: acknowledge** — orthogonal concern; #2197 stays open and
  untouched.

No other open code-review issue bodies name a planned file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "implement the deferred least-privilege kernel-stream read for the deploy user (canary kdeny diag reads src=none because the deploy user cannot read the kernel stream under kernel.dmesg_restrict=1)" [issue #10045 title + brief] | Phases 1-2 (grant + reader change); AC-1..AC-4 | mapped |
| 2 | "(a) systemd-journal group membership for the deploy user — needs a blast-radius read since the user is already docker-group/root-equivalent; (b) a fixed-argv sudoers grant (e.g. `journalctl -k -n 400 --since=-5min --no-pager -o cat` shape-matched)" [issue #10045] | "Alternatives considered" blast-radius analysis + chosen shape (b) in Proposed Solution | mapped |
| 3 | "Delivery MUST go through the host IaC path (cloud-init / terraform_data), never ad-hoc SSH" [brief] | Phase 1 + `## Infrastructure (IaC)` Apply path | mapped |
| 4 | "a separate host-IaC plan with its own apply+gate" [issue #10045, quoting #10032 scoping] | Phase 1 assert additions + Phase 4 apply-gate description + Guard 2 | mapped |
| 5 | "Runbook: knowledge-base/engineering/operations/runbooks/canary-probe-set.md §kdeny. A SOLEUR-DEBT note in apps/web-platform/infra/ci-deploy.sh covers the row's disposition." [brief] | Phase 2 item 6 + Phase 4 item 10 | mapped |
| 6 | "The soak-tracking issue for the procfs fix stays open for observation — do not touch it." [brief] | Non-Goals | mapped (as exclusion) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `Cmnd_Alias KDENY_KERNEL_STREAM` + grant line | "a fixed-argv sudoers grant (e.g. `journalctl -k -n 400 --since=-5min --no-pager -o cat` shape-matched)" | asked |
| cloud-init.yml inline mirror | "Delivery MUST go through the host IaC path (cloud-init / terraform_data), never ad-hoc SSH" | asked |
| Provisioner asserts (alias `grep -q` + `runuser` execute probe) in both bridges | "a separate host-IaC plan with its own apply+gate" | asked |
| `sudo -n` attempt + unprivileged fallback in `_canary_kdeny_read` | "implement the deferred least-privilege kernel-stream read for the deploy user" | asked |
| ci-deploy.test.sh sudo-mock fixtures | — | inferred — justification: repo contract (cq-write-failing-tests-before + the D10 fixture battery owns this row's behavior; a behavior change without a fixture is unverifiable) |
| cloud-init-inngest-bootstrap.test.sh argv-lockstep assert | — | inferred — justification: the sudoers↔call-site drift-denies contract is only as strong as the test pinning it (2026-05-26 learning: "copy the exact argument list into the handler script — never retype") |
| infra-config-handler-bootstrap.test.sh verify asserts | — | inferred — justification: the file's AC7-style asserts pin the provisioner verify battery; adding battery lines without test pins leaves them drift-able |
| Runbook §kdeny update | "Runbook: knowledge-base/engineering/operations/runbooks/canary-probe-set.md §kdeny" | asked |
| ADR-075 Deferred-paragraph amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the ADR names this deferral by number; landing it without updating the record leaves the architecture doc asserting an open deferral that is closed |
| `dpf-web2-remote-exec-v2→v3` sentinel bump | — | inferred — justification: server.tf documents the sentinel as the re-fire mechanism for remote-exec content edits ("Bump the sentinel suffix in lockstep with any inline edit") |
| systemd-journal group grant (candidate (a)) | named in issue | descoped — justification: rejected in Alternatives; ambient whole-journal read is wider than the property requires |
| `#9860` edits | "do not touch it" | descoped — explicit exclusion |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (infra/ subtree), `knowledge-base` (runbook + ADR + plan artifacts)
- Planned files: 9 | Estimated changed lines: ~180
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — none met
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] `deploy-inngest-bootstrap.sudoers` carries `Cmnd_Alias KDENY_KERNEL_STREAM = /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` and `deploy ALL=(root) NOPASSWD: KDENY_KERNEL_STREAM`, parses under `visudo -cf`, and cites #10045.
- [x] `cloud-init.yml`'s `/etc/sudoers.d/deploy-inngest-bootstrap` inline block, comment-stripped, equals the `.sudoers` source comment-stripped (AC5 stays green).
- [x] Both `terraform_data` bridges' remote-exec contain the alias `grep -q` and the `runuser -u deploy -- sudo -n` execute probe for the exact argv; `deploy_pipeline_fix_web2`'s sentinel is bumped.
- [x] `_canary_kdeny_read` attempts `sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` first; on a sudo-denial signature it falls back to the unprivileged read; `dmesg` rung and the `src=/j=/d=` vocabulary are unchanged; no new failure class is introduced for a grant-less host.
- [x] `ci-deploy.test.sh` covers: grant-present readable journal (`src=journal j=ok`), grant-present silent-empty, sudo-denied fallback to `noaccess`, and journalctl-under-root error classification — with the sudo mock emitting its denial on stderr (rc 1).
- [x] The argv-lockstep assert exists in `cloud-init-inngest-bootstrap.test.sh` (or the kdeny test section) and fails on any single-surface drift per Guard 1's matrix.
- [x] `canary-probe-set.md` §kdeny documents the privileged path, the fallback contract, and the sudo audit record; the `SOLEUR-DEBT` comment in `ci-deploy.sh` is re-scoped to reflect the landed grant.
- [x] ADR-075's Deferred paragraph records #10045 as resolved.
- [x] #9860 is untouched by the diff and remains open.

### Post-merge (operator/CI apply)

- [ ] Apply gate: `apply-deploy-pipeline-fix.yml` runs both bridges green, including the new execute probe (`runuser -u deploy -- sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat`), on web-1 and web-2.
- [ ] Post-apply observation (documented in PR body, not blocking merge): the next `sandbox_broken` bundle is expected to read `src=journal`; no healthy deploy emits a bundle.

## Test Scenarios

- **(unit)** Given a `sudo` mock granting the pinned argv and a journalctl mock printing an
  anchored AppArmor mount-denial, when `_canary_kdeny_read` runs, then `src=journal j=ok` with
  `hits`/`mproc` counted and `d=skip`.
- **(unit)** Given `MOCK_SUDO_DENY=rs|gnu` (stderr denial body, rc 1) and a
  permission-denied unprivileged journalctl, when the read runs, then `j=noaccess` — the
  pre-grant contract, not `error`.
- **(unit)** Given sudo accepts but journalctl-under-root exits rc 1 with no kernel lines and no
  hint, when the read runs, then `j=error` and no unprivileged re-run (denial-vs-tool-failure
  discrimination).
- **(unit)** Given grant present and journal silent-empty (systemd 261 shape, impossible under
  root — fixture asserts the classifier still maps rc-0-no-lines to `empty` honestly rather than
  `ok`), when the read runs, then `j=empty` and the dmesg rung proceeds.
- **(unit)** Given the `dmesg` rung unchanged, when the journal rung (both arms) does not read
  `ok`, then `d=` behaves exactly as today (`dmesg` stays unprivileged).
- **(integration)** `visudo -cf apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` exits 0.
- **(integration)** `bash apps/web-platform/infra/ci-deploy.test.sh` — kdeny section green.
- **(integration)** `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC5
  parity + new lockstep assert green.
- **(integration)** `bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` — new
  verify asserts green.
- **(integration)** `terraform -chdir=apps/web-platform/infra validate` clean (HCL syntax only —
  provisioner content is shell, validated by the test pins).
- **(e2e, apply-time)** The `runuser -u deploy -- sudo -n /usr/bin/journalctl -k -n 400
  --since=-5min --no-pager -o cat` probe exits 0 on web-1 and web-2 during
  `apply-deploy-pipeline-fix.yml`. `pyramid-justified: effectiveness of a host sudo policy is not
  repo-simulable — the provisioner IS the integration surface`.

## Risks

- **Precedent diff (Phase 4.4):** the grant's shape is NOT novel — `deploy-inngest-bootstrap.sudoers`
  carries nine sibling `Cmnd_Alias`+grant pairs with the same form (issue-tagged comment, alias
  pinned argv, `NOPASSWD` line), and the `visudo → install 0440 → grep → policy probe` battery is
  the established delivery-tail. The delta vs. precedent: (1) our alias's argv contains `=` inside
  `--since=-5min` (precedent: `WEBHOOK_SELF_RESTART`'s `--unit=`/`--on-active=`, also unescaped —
  see the Technical Considerations deepen note); (2) the grant drives a *read* inside a diagnostic
  row rather than an action — the new surface is the reader's fallback branch, which the sibling
  grants do not have (they hard-fail on denial; `kdeny` must not, per Property 5).
- **argv drift (denial, not widening):** the whole contract is literal-string matching; mitigated
  by Guard 1's lockstep across the three text surfaces and by fail-closed semantics.
- **sudo-rs behavioral deltas:** `sudo -n -l -U` availability is itself probed before use (#7220
  pattern); `-l` with command args behaves per sudo on this fleet today.
- **journald flapping / Storage=volatile hosts:** `journalctl -k` under root reads whatever the
  journald store holds; `journald-soleur.conf` persistence is already a managed resource —
  unchanged.
- **Rollout skew:** covered by the fallback design; no AC depends on a mid-window state.

## Non-Goals

- The `systemd-journal` group membership shape (rejected — see Alternatives).
- A `dmesg` grant, a helper script, or ACL-based journal access (rejected — see Alternatives).
- Demoting or removing the `kdeny` row (its disposition fork per the `SOLEUR-DEBT` note resolves
  to *keep*: with the grant landed the row is functional evidence, and #9860 remains open for
  soak — the note is re-scoped, not deleted).
- Any change to `kernel.dmesg_restrict=1` (deliberate defense-in-depth; untouched).
- Touching #9860 (explicitly excluded by the brief).
- New terraform resources, providers, variables, or webhook FILE_MAP entries.

## References

- Issue: #10045 (this plan); deferred-from #10032; tracks evidence for #9860 (untouched).
- Runbook: `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` §kdeny.
- ADR-075 (addendum names this issue as deferred); the fixed-argv sudoers idiom across
  `deploy-inngest-bootstrap.sudoers`; #4144/#4827/#5934/#7220 precedents for grant shape,
  delivery bridge, and policy-probe gating.
- Privilege-boundary decision record:
  `knowledge-base/project/plans/archive/20261012-213508-2026-03-20-security-deploy-ssh-user-privilege-boundary-plan.md`.
- Learnings: `2026-06-02-deploy-user-sudo-helper-hardening.md`,
  `2026-05-26-ssh-to-webhook-provisioner-migration-mount-namespace-traps.md`,
  `2026-05-20-…-sudo-rs-no-wildcards.md`,
  `2026-10-11-every-fixture-of-the-kernel-denial-row-fed-the-hints-through-stdout….md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold fails
  `deepen-plan` Phase 4.6 — filled above (`none` + scope-out bullet for the sudoers path).
- `sudo` compares the resolved command **and** argv literally: the call site, the alias, and the
  provisioner probes must stay byte-identical — Guard 1 pins all three; adding a second
  journalctl-granting line without updating the census assert reds the suite.
- The kdeny bundle emits **only** on `sandbox_broken` — do not plan a "next deploy shows
  `src=journal`" gate; the provisioner execute probe is the landing gate.
- `cloud-init.yml` is `ignore_changes=[user_data]` on running hosts — fresh hosts only; the two
  bridges are the running-host delivery and their asserts are the apply gate.
- The `SOLEUR-DEBT` note's disposition fork resolves to *keep* the row (grant landed → row works);
  rewrite the comment, don't delete the row.
