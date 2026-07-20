# Runbook — Headless Grok Build dogfood host (Hetzner)

**Issue:** #6545 · **Phase 2 open model:** #6546 · **Product ACP epic:** #6547  
**Brand:** operator-only dogfood — do **not** market as “Grok 4.5 runs on our Hetzner.”

## Architecture (substrate)

| Layer | Where |
|-------|--------|
| Grok Build CLI (harness) | Hetzner host `soleur-grok-dogfood` |
| Grok 4.5 inference (Phase 1) | xAI API (`XAI_API_KEY`) |
| Open model (Phase 2) | Local OpenAI-compatible endpoint via `~/.grok/config.toml` |
| Soleur Web product agent | Still Claude Agent SDK (`agent-runner.ts`) until #6547 |

Model selection is **config-driven** so Phase 1 is not throwaway when the brain changes.

## Phase 0 — Capacity gate

```bash
export HCLOUD_TOKEN="$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)"
hcloud server list
# Confirm free slot vs account server limit before enabling create.
```

Current fleet (example): web-1, web-2, inngest, registry. Cap historically 5 — verify live.

## Provision (enable + apply)

TF resources live in `apps/web-platform/infra/grok-dogfood.tf`, gated by:

```hcl
enable_grok_dogfood = true   # default false
```

**Do not** merge with default true and expect per-PR apply to create the host — `host_creates` tripwire (#6416) blocks unattended host birth.

Operator-local apply (after free slot + stock check for `cx33` in `hel1`):

```bash
cd apps/web-platform/infra
export AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=…   # R2 backend
terraform init -input=false
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  env TF_VAR_enable_grok_dogfood=true \
  terraform plan \
    -target=hcloud_server.grok_dogfood \
    -target=hcloud_firewall.grok_dogfood \
    -target=hcloud_firewall_attachment.grok_dogfood
# Review: 0 destroy of product fleet, 1 create of soleur-grok-dogfood
# Phase 1: no private-net attach (agent host stays off 10.0.1.0/24 trust plane)
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  env TF_VAR_enable_grok_dogfood=true \
  terraform apply \
    -target=hcloud_server.grok_dogfood \
    -target=hcloud_firewall.grok_dogfood \
    -target=hcloud_firewall_attachment.grok_dogfood
```

Record host monthly cost in `knowledge-base/operations/expenses.md` when retained.

## Bootstrap secrets + repo

1. SSH as root (admin IP allowlist): `ssh root@<ip>`  
   - If banner times out, check egress ∈ Doppler `ADMIN_IPS` and live `hcloud firewall describe soleur-grok-dogfood`.
2. Confirm cloud-init: `test -f /var/log/grok-dogfood/boot-complete` and `grok --version`  
   - **Known footgun (fixed in cloud-init after first trial):** `write_files` must not use `owner: dogfood` — that module runs *before* `users`, so the install script was skipped and only `boot-complete` appeared. Repair: reinstall CLI + reseed `config.toml` as root, then `chown dogfood`.
3. Place API key (operator-only — **never** prd customer secrets):

```bash
install -m 600 /dev/null /home/dogfood/.grok/secrets.env
# Write XAI_API_KEY=... only (durable console key preferred; OIDC access tokens expire)
chown dogfood:dogfood /home/dogfood/.grok/secrets.env
```

   Do **not** create a Doppler config that inherits/copies `prd` secrets for this host.

4. Clone Soleur for dogfood (read-only preferred; no push credentials):

```bash
sudo -u dogfood git clone --depth 1 https://github.com/jikig-ai/soleur.git /home/dogfood/soleur
```

5. Config already seeds `default = "grok-4.5"` under `/home/dogfood/.grok/config.toml`.

## Measurement suite

Script: `scripts/dogfood/grok-measure.sh`

```bash
export XAI_API_KEY=…   # or source secrets.env
# Opt-in --yolo only for trusted unattended runs; prefer deny rules, e.g.:
#   grok -p "..." --yolo --deny 'Bash(rm*)' --deny 'Bash(sudo*)' --max-turns 15
./scripts/dogfood/grok-measure.sh \
  --prompt "List the top-level directories in this repo (read-only)." \
  --cwd /home/dogfood/soleur \
  --max-turns 15 \
  --log /var/log/grok-dogfood/runs.jsonl
# Add --yolo only after reviewing the prompt; script defaults YOLO off.
```

### Prompt classes (minimum 3)

1. **Read-only** — summarize one small file  
2. **Scoped edit** — write under `/tmp` only  
3. **Multi-tool** — `git status` + list dir (no push)

### Expected Phase 1 ballpark

| Metric | Ballpark |
|--------|----------|
| TTFT | ~1.0–1.5 s from EU |
| Tok/s | ~80–90 (API-bound) |
| Host | ~€6–12/mo CX33 |
| API @ 1–5 runs/day | ~$30–120/mo |

Fill sample table:

| ts | class | ttft_ms | tok_per_sec | total_cost_usd | exit |
|----|-------|---------|-------------|----------------|------|
|  |  |  |  |  |  |

## Guards / kill criteria

- `grok-measure.sh` defaults **YOLO off** — pass `--yolo` only deliberately; pair with `--deny` / permission rules  
- Default `--max-turns` 30 (or lower)  
- Soft API ceiling **$100/mo** unless operator raises  
- No git push credentials on host by default  
- No private-net attachment (Phase 1) — host is not on `10.0.1.0/24` trust plane  
- dogfood user has **no** passwordless sudo  
- Kill: spend ceiling, customer data on host, host compromise → destroy / disable flag  
- CLI version: record `grok --version` after install; pin release artifact in runbook if you need bit-for-bit reproducibility (install.sh tracks latest stable)

## Phase 2 — open-weight on Robot GEX44 (#6546)

**Architecture (Approach A — locked):** separate **Robot dedicated GEX44** host (not Cloud/`hcloud`); **Grok CLI + Ollama co-located** on that host; Ollama OpenAI-compatible API on **loopback only** (`http://127.0.0.1:11434/v1`). Phase 1 CX33 remains the xAI API baseline — do **not** point CX33 at GEX public IP (that recreates Approach B).

**Brand:** operator-only dogfood. **Never** claim “self-hosted Grok 4.5” or “Grok runs on our GPU.”

**Control plane:** Robot console order + `scripts/dogfood/grok-gpu-bootstrap.sh` + this runbook + expense ledger. See ADR-120. **Not** Cloud TF birth.

### Forbidden configs (Approach B / product)

| Forbidden | Why |
|-----------|-----|
| Ollama listening on `0.0.0.0:11434` / `*:11434` | Public OpenAI-compatible surface |
| Any host `base_url = http://<GEX-public-IP>:11434/v1` | Split-host Approach B |
| Product Concierge / `agent-runner` → GEX | #6547 parked |
| Private-net `10.0.1.0/24` attach | Trust plane isolation |
| Passwordless sudo for dogfood user | Agent escalation |

### Order checklist (STOP until all true)

**Do not order GPU without all of these recorded on #6546.**

0. **GEX is Robot dedicated** (not a Cloud type). Cloud fleet free-slot inventory is **N/A** for Robot birth (separate product class).
1. Operator **spend ack** on #6546 (1-week default soak envelope; setup fee accepted).
2. Live **stock/price/setup** from Robot configurator (GEX44 FSN1; re-verify ~€184/mo + setup).
3. **License memo** for exact model id (OK / OK-with-conditions / Reject) — Apache-2.0/MIT preferred; ≤20 GB VRAM; **before** `ollama pull`.

Also confirm billing pro-ration (hourly vs month minimum) or plan full-month worst case.

### Expense ledger

Path: **`knowledge-base/operations/expenses.md`** (not `engineering/operations/expenses.md`).

| When | Status |
|------|--------|
| Before order | `approved-not-billing` (GEX row must exist) |
| Host live | flip `active` **same day**; stamp on #6546: `order_id`, `ip`, **`billable_from: <ISO8601>`** |
| Robot cancel | flip `retired` **same day** |

Cost-model R&D line: update only when status is `active` (not pre-order).

### Bootstrap (after OS is up)

Fresh Robot host has **no** repo checkout. Copy the script from a machine that has this tree, then run as root:

```bash
# From a soleur checkout that contains scripts/dogfood/grok-gpu-bootstrap.sh
# <!-- verified: 2026-07-17 source: scripts/dogfood/grok-gpu-bootstrap.sh -->
# SSH: L3 firewall / admin IP first if connect fails (hr-ssh-diagnosis-verify-firewall)
GEX_IP='<from Robot console / #6546>'
scp scripts/dogfood/grok-gpu-bootstrap.sh scripts/dogfood/assert-ollama-loopback.sh root@${GEX_IP}:/tmp/
ssh root@${GEX_IP} 'bash /tmp/grok-gpu-bootstrap.sh'
# After license memo on #6546:
ssh root@${GEX_IP} 'bash /tmp/grok-gpu-bootstrap.sh --model <exact-ollama-tag> --license-ok'
# Later re-runs can use the cloned tree:
# ssh root@${GEX_IP} 'bash /home/dogfood/soleur/scripts/dogfood/grok-gpu-bootstrap.sh'
```

Idempotent: NVIDIA detect → install `ss`/iproute2 → Ollama with `OLLAMA_HOST=127.0.0.1:11434` → **fail closed** if `ss` missing or public bind → Grok CLI → config.toml → shallow clone `/home/dogfood/soleur` → optional pull.

### License memo (before pull)

1. Name exact model id + source (HF/Ollama tag).  
2. Read model card license (SPDX or custom URL/date).  
3. Classify: OK (Apache/MIT/BSD) / OK-with-conditions / Reject (NC / field-of-use).  
4. One-line + link on #6546 **before** `--license-ok` pull.  
5. Confirm Hetzner AVV covers **Robot dedicated** at order.

### Config (`/home/dogfood/.grok/config.toml`)

```toml
[models]
default = "local-open"

[model.local-open]
model = "<exact-open-weight-id>"
base_url = "http://127.0.0.1:11434/v1"
name = "Local open model"
context_window = 128000
```

`base_url` host **must** be `127.0.0.1` or `localhost` only.

### Smoke (before multi-day soak)

Grok Build OpenAI client → Ollama `/v1` must succeed once (AC11b). Concrete agent-runnable checks:

```bash
# On GEX as root or dogfood (Ollama already loopback-bound)
curl -fsS http://127.0.0.1:11434/v1/models | jq -e '.data | length >= 0'
# After --license-ok model pull, prefer a one-shot measure (exit 0 + non-null ttft_ms):
sudo -u dogfood bash -lc '
  cd /home/dogfood/soleur
  ./scripts/dogfood/grok-measure.sh     --model local-open     --prompt "Reply with OK only."     --cwd /home/dogfood/soleur     --max-turns 3     --log /var/log/grok-dogfood/smoke.jsonl
'
```

On fail: within **48h** either fix, Robot cancel, or re-approve burn with written reason on #6546 — do not leave host billing without disposition.

### Measure (same three classes as Phase 1)

**Preflight every campaign** (not only bootstrap):

```bash
# Loopback listen — fail if public (ss required; measure also re-asserts for --model local-open)
ss -lnt | grep 11434   # expect 127.0.0.1:11434 only, not 0.0.0.0:11434
curl -fsS http://127.0.0.1:11434/api/tags >/dev/null
# base_url host must be 127.0.0.1 or localhost — fail on any other host
grep -E '^\s*base_url\s*=' /home/dogfood/.grok/config.toml \
  | grep -vE '127\.0\.0\.1|localhost' && { echo 'FAIL non-loopback base_url'; exit 1; } || true
grep -qE 'base_url = "http://(127\.0\.0\.1|localhost)' /home/dogfood/.grok/config.toml \
  || { echo 'FAIL missing loopback base_url'; exit 1; }
```

```bash
sudo -u dogfood bash -lc '
  cd /home/dogfood/soleur
  # YOLO off by default
  ./scripts/dogfood/grok-measure.sh \
    --model local-open \
    --prompt "List top-level directories (read-only)." \
    --cwd /home/dogfood/soleur \
    --max-turns 15 \
    --log /var/log/grok-dogfood/runs.jsonl
'
```

Prompt classes: (1) read-only, (2) scoped `/tmp` edit, (3) multi-tool `git status` + list dir. No push credentials.

### Comparison table (paste filled rows on #6546)

**Phase 1 baseline (API Grok 4.5, 2026-07-16, YOLO off):**

| class | ttft_ms | tok/s | cost USD | exit |
|-------|---------|-------|----------|------|
| read | 2648 | 49.4 | 0.046 | 0 |
| scoped /tmp edit | 2344 | 12.6 | 0.045 | 0 |
| multi-tool | 5239 | 104 | 0.046 | 0 |

**Phase 2 (open-weight on GEX — fill after measure):**

| ts | class | model | ttft_ms | tok_per_sec | exit | notes |
|----|-------|-------|---------|-------------|------|-------|
|  | read |  |  |  |  |  |
|  | scoped /tmp edit |  |  |  |  |  |
|  | multi-tool |  |  |  |  |  |

Also record: host €/mo, setup fee, Ollama version, Grok version, GPU (`nvidia-smi`), `billable_from`.

**Narrative rules:** harness + cost/latency curve only. **No** quality-parity claim vs Grok 4.5. **No** “self-hosted Grok 4.5.”

### Kill criteria

- Spend ceiling / no re-approval after default **1-week** soak  
- No filled comparison table within **14 days** of `billable_from`  
- License fail / compromise / customer data on host  
- Public Ollama bind or Approach B config  
- Brand mislabel  
- SKU jump without re-approval  

### Destroy — Phase 2 (Robot cancel)

1. Robot console: cancel / return GEX server (not `terraform`).  
2. Same day: expense row → `retired` with cancel date.  
3. Comment on #6546: cancel confirmation + final cost note.  
4. Do **not** use Phase 1 TF destroy for GEX.

### SSH diagnosis (L3 → L7)

If SSH fails: (1) operator egress IP vs Robot firewall / admin allowlist, (2) correct public IP from Robot console, (3) only then sshd/fail2ban. See `hr-ssh-diagnosis-verify-firewall`.

## Product trajectory (#6547)

Soleur Web today: `@anthropic-ai/claude-agent-sdk` in `apps/web-platform/server/agent-runner.ts`.  
Future: Grok Build **ACP** (`grok agent stdio` / `serve`) or headless job dispatch as product agent backend. This dogfood host proves harness + cost + model-swap; it is **not** multi-tenant Concierge. Phase 2 does **not** unpark #6547.

## Destroy — Phase 1 only (Cloud CX33)

```bash
TF_VAR_enable_grok_dogfood=false terraform apply \
  -target=hcloud_server.grok_dogfood \
  -target=hcloud_firewall.grok_dogfood \
  -target=hcloud_firewall_attachment.grok_dogfood
```

Phase 2 GEX destroy is **Robot cancel** (section above) — never this TF path.
