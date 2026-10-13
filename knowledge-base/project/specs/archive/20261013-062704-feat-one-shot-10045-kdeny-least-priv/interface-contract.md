# Interface Contract — feat-one-shot-10045-kdeny-least-priv

Plan: `knowledge-base/project/plans/2026-10-11-chore-kdeny-kernel-stream-read-grant-plan.md`

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`, `apps/web-platform/infra/cloud-init.yml`, `apps/web-platform/infra/server.tf`, `apps/web-platform/infra/ci-deploy.sh` |
| Agent 2 (Tests) | `apps/web-platform/infra/ci-deploy.test.sh`, `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` |
| Coordinator (neither) | `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`, plan/tasks/spec artifacts |

## Public Interfaces

**The granted argv (byte-exact everywhere — alias body, call site, provisioner probes, tests):**

```text
/usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat
```

Written UNESCAPED in sudoers (in-file `--unit=`/`--on-active=` precedent; escaped `--since\=-5min` is the documented fallback only).

**Sudoers file (`deploy-inngest-bootstrap.sudoers` + `cloud-init.yml` `/etc/sudoers.d/deploy-inngest-bootstrap` write_files block):**

```text
Cmnd_Alias KDENY_KERNEL_STREAM = /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat
deploy ALL=(root) NOPASSWD: KDENY_KERNEL_STREAM
```

Plus a `#10045` rationale comment (source file: issue-tagged block style; cloud-init copy: compressed comment per byte budget). Comment-stripped (`grep -vE '^\s*#|^\s*$'`) content must stay byte-identical between the two files (existing AC5 parity).

**Reader (`_canary_kdeny_read` in `ci-deploy.sh`):**

- Journal rung attempts first: `timeout -k 1 3 sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` (`timeout` outside sudo; `2>&1` capture, `tac`/`head -c 65536` newest-first bounds preserved).
- **Denial discriminator:** sudo-denial signature = non-zero rc AND at least one recognized denial phrase (`Sorry,`, `command not allowed`, `password is required`, `not allowed to execute`, `may not run`, `is not in the sudoers file`) AND every non-blank captured line `sudo:`- or `Sorry,`-prefixed AND zero kernel lines → fall back to the existing unprivileged `journalctl` read (today's `noaccess`/`empty` semantics). A run sudo *accepted* classifies through the existing state machine (no re-fallback).
- `src=`/`j=`/`d=` vocabulary and the `dmesg` rung unchanged (`d=skip` whenever the journal rung reads `ok`).

**Provisioner asserts (`server.tf`, both `terraform_data.infra_config_handler_bootstrap` and `terraform_data.deploy_pipeline_fix_web2` remote-exec):**

```text
grep -q KDENY_KERNEL_STREAM /etc/sudoers.d/deploy-inngest-bootstrap
runuser -u deploy -- sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat >/dev/null || { echo 'FATAL: …' >&2; exit 1; }
```

`deploy_pipeline_fix_web2` sentinel: `dpf-web2-remote-exec-v2` → `dpf-web2-remote-exec-v3`.

**Test knobs (Agent 2 fixtures in `ci-deploy.test.sh`):**

- `sudo` PATH-mock validating argv exactly `-n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat`, then exec'ing the journalctl mock.
- `MOCK_SUDO_DENY=rs|gnu` → denial emitted on **stderr**, rc 1 (rs: `sudo: deploy : command not allowed`, the recorded sudo-rs fleet emission; gnu: `Sorry, user deploy is not allowed to execute …`, the infra-config-apply.test.sh model), journalctl never exec'd. `MOCK_SUDO_WARN=1` → an accepted run also emits a `sudo:`-prefixed warning on stderr.
- Fixture arms: grant+journal answers (`src=journal j=ok`); grant+silent-empty (`j=empty` → dmesg rung); denied → fallback `noaccess`; sudo-accepted + journalctl-under-root rc 1 no lines → `j=error` (NO unprivileged re-run); `dmesg` rung unchanged.
