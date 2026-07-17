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

Record host monthly cost in `knowledge-base/engineering/operations/expenses.md` when retained.

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

## Phase 2 — open model swap (#6546)

Edit `~/.grok/config.toml`:

```toml
[models]
default = "local-open"

[model.local-open]
model = "your-open-weight-id"
base_url = "http://127.0.0.1:11434/v1"
name = "Local open model"
context_window = 128000
```

Re-run the **same** measure script with `--model local-open` (or rely on default). No reinstall of harness required.

GPU host class (entry): Hetzner GEX44-class (~€184+/mo) — separate provision.

## Product trajectory (#6547)

Soleur Web today: `@anthropic-ai/claude-agent-sdk` in `apps/web-platform/server/agent-runner.ts`.  
Future: Grok Build **ACP** (`grok agent stdio` / `serve`) or headless job dispatch as product agent backend. This dogfood host proves harness + cost + model-swap; it is **not** multi-tenant Concierge.

## Destroy

```bash
TF_VAR_enable_grok_dogfood=false terraform apply \
  -target=hcloud_server.grok_dogfood \
  -target=hcloud_firewall.grok_dogfood \
  -target=hcloud_firewall_attachment.grok_dogfood
```
