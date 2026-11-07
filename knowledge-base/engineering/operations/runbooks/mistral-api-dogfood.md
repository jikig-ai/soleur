---
title: Mistral API dogfood — measure ML4/Devstral through existing vehicles (no new harness)
category: dogfood
issue: 9648
last_verified: 2026-10-07
---

# Mistral API dogfood

Phase A0 of #9648: measure Mistral models through vehicles that need no new harness, so the
eval table on #9648 gates stages A (Vibe adapter) and B (BYOK provider). Nothing here is
customer-facing; it is operator dogfood producing a quality signal.

## Records

| Field | Value |
|---|---|
| Measured 2026-10-07 | `api.mistral.ai/v1/responses` **exists** — 401 on known routes vs 404 on fabricated paths, so auth-not-routing produces the 401 |
| Measured 2026-10-07 | `codex exec --json` 0.160.1 with inline `model_providers.mistral` **reaches `/v1/responses`** — rejected 401 at auth after a well-formed request; only credential validity remains unmeasured |
| Measured 2026-10-07 | `codex exec` 401s are retried ×5 as transient — a bad/absent key costs ~30 s of reconnects, not an instant error |
| Console | `https://console.mistral.ai` → `v2.auth.mistral.ai/login` (login+signup same form; email+password or Google/Apple/Microsoft OAuth) |
| Key landing | Doppler `soleur/dev` `MISTRAL_API_KEY` — operator-terminal write only |

## Prerequisite: the Mistral Studio key

The mint is an **operator gate** — credential entry, per the work-skill Playwright audit:

```text
playwright-attempt: navigated https://console.mistral.ai → redirected to
  https://v2.auth.mistral.ai/login (2026-10-07); reached credential-entry gate
  (email+password or OAuth consent via Google/Apple/Microsoft); no stored session
  exists and signup verification lands in the operator's inbox — a human-only
  interaction either way
```

Operator steps (the only manual link in the chain):

1. Sign in or create an account at `https://console.mistral.ai`.
2. *API keys → Create new key* — name it `soleur-a0-dogfood`.
3. In **your own terminal** (the agent must never see the value):

   ```bash
   doppler secrets set MISTRAL_API_KEY -p soleur -c dev
   ```

   Verify by length, never by printing: `doppler secrets get MISTRAL_API_KEY -p soleur -c dev --plain | wc -c` — expect ~33.

Once the key is in Doppler, everything below is agent-executable with
`doppler run -p soleur -c dev -- ...`.

## Vehicle A — Codex `model_providers` (primary)

Measured caveat: **Codex ignores `model_provider`/`model_providers`/`profile` in
project-local `.codex/config.toml`** — provider config must live in the user layer
(`~/.codex/config.toml` or a `-p` profile file) or be passed inline via `-c`.

### Durable recipe — `~/.codex/config.toml`

```toml
# Select per-run with `-c model_provider="mistral"` (do NOT set it globally
# unless every codex session should bill Mistral).
[model_providers.mistral]
name = "Mistral"
base_url = "https://api.mistral.ai/v1"
env_key = "MISTRAL_API_KEY"
wire_api = "responses"
```

### Self-contained recipe — no config file needed

`scripts/dogfood/mistral-measure.sh` passes the provider table inline (`-c
model_providers.mistral={...}`) plus `--ignore-user-config`, so ambient config
(MCP registrations, an inherited `model_provider`) cannot leak into the run:

```bash
doppler run -p soleur -c dev -- \
  scripts/dogfood/mistral-measure.sh \
    --model mistral-large-latest \
    --prompt "List the top-level directories in this repo (read-only)." \
    --cwd /path/to/repo --sandbox read-only \
    --log /var/tmp/mistral-dogfood/runs.jsonl
```

Useful args: `--model devstral-latest` for the Devstral arm; `--profile <name>` to
use a `$CODEX_HOME/<name>.config.toml` profile instead of the inline override;
`--add-dir <dir>` alongside `--sandbox workspace-write` for the scoped-edit class
(write confinement stays explicit); `--in-usd-per-mtok`/`--out-usd-per-mtok` fill
the cost column from the current rate card (codex emits no cost field — the cell
is labelled `cost_basis:"rate-card"`, never confused with a vendor number).

## Vehicle B — #1215 Ollama + `claude-code-proxy` (fallback)

Works regardless of the Responses-API answer: `claude-code-proxy` fronts an
Anthropic-shaped endpoint and forwards to Mistral's OpenAI-compatible
`/v1/chat/completions` (route existence also confirmed in the probe). Point the
proxy's upstream at `https://api.mistral.ai/v1` with `MISTRAL_API_KEY` as the
upstream key, then run Claude Code against the proxy (`ANTHROPIC_BASE_URL`).
Measure with `mistral-measure.sh --parse-only` over the proxy/Claude stream, or
reuse the canonical fixture shape — the summarizer is vehicle-agnostic.

## Measurement suite

Script: `scripts/dogfood/mistral-measure.sh` (adapter over the same
`normalize_stream`/`parse_events` pipeline as `grok-measure.sh`).

### Prompt classes (same three as the GEX/grok campaign)

1. **Read-only** — summarize one small file (`--sandbox read-only`)
2. **Scoped edit** — write under a scratch dir only (`--sandbox workspace-write --add-dir <scratch>`)
3. **Multi-tool** — `git status` + list dir (no push)

Pass criterion is **exit code AND artifact presence** — a fast, cheap, wrong run
is still a failure (per the plan's row schema). Vehicles/models to cover:
`mistral-large-latest` via Codex (and Devstral if the Studio key scopes it);
the #1215 proxy arm only if the Codex arm materially fails.

### Eval table — paste filled rows on #9648

| ts | prompt-class | vehicle | model | CLI version+pin | pass criterion | result | verifier | ttft_ms | tok/s | cost USD | exit |
|----|--------------|---------|-------|-----------------|----------------|--------|----------|---------|-------|----------|------|
|  |  |  |  |  |  |  |  |  |  |  |  |

## Guards / kill criteria

- `--sandbox read-only` is the default — a writable run is a deliberate per-class choice.
- No git push credentials in the dogfood environment.
- Soft API ceiling: flag to the operator before cumulative dogfood spend exceeds
  ~$25/mo on the preview key (preview pricing may be free-tier; verify on the
  Studio billing page at mint time).
- **14-day no-table kill criterion** (GEX precedent): if no eval rows land on
  #9648 within 14 days of key mint, record the stall on #9648 and stop spend.
- Decision rule on the signal: a vehicle failing ≥ half the prompt classes defers
  stages A and B (recorded on #9648) — C1 self-host is unaffected and may even be
  *strengthened* by a weak hosted-API result.
