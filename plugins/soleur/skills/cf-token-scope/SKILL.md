---
name: cf-token-scope
description: This skill should be used to widen an existing Cloudflare API token's scope via Playwright dashboard automation, then run the ADR-130 retained-scope probe set verifying the target scope was added and none was dropped.
disable-model-invocation: true
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# cf-token-scope

Close the capability gap ADR-130 leaves open: there is no first-party path for
Cloudflare API-token scope changes, so each one is an ad-hoc dashboard trip
(third on record — #6657 DNS, #6649 R2, #6755 Config Rules). This skill widens a
token via **Playwright MCP** dashboard automation and makes the ADR-130
retained-scope check a deterministic, fail-closed command.

The widen mutates a live production credential that four concerns depend on. A
dashboard "save" that **replaces** rather than **appends** scopes silently breaks
cache rules, WAF, single redirects, transform rules, and account bulk redirects
at once — so the retained-scope probe is the load-bearing half, not the widen.

## Usage

The deterministic core is a read-only probe script,
[cf-token-scope.sh](./scripts/cf-token-scope.sh). It only ever probes — run it as
often as needed; it mutates nothing.

### Preflight: verify the plugin install before any snapshot

The redactor is reached through `${CLAUDE_PLUGIN_ROOT}`. An ambient value pointing at a
directory that is not a Soleur install would resolve to a path that does not exist — or, worse,
to one an attacker chose. Verify plugin IDENTITY and halt if it does not hold (ADR-179 decision 2);
a `test -f` on the script alone is a shape check and was measured bypassable.

```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "SOLEUR_SNAPSHOT_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]" >&2
       echo "  Cannot locate the snapshot redactor, so no accessibility snapshot may be taken here." >&2
       echo "  Root EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session." >&2
       echo "  Root set but wrong: a repo checkout is not an install. Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly), then RESTART Claude Code." >&2
       echo "  Nothing has been captured yet, so nothing has leaked." >&2
       exit 2; }
```

```bash
# Baseline / re-check — probe the four ADR-130 retained scopes:
bash "${CLAUDE_PLUGIN_ROOT}/skills/cf-token-scope/scripts/cf-token-scope.sh"

# After a widen — also assert the newly-added scope is live:
bash "${CLAUDE_PLUGIN_ROOT}/skills/cf-token-scope/scripts/cf-token-scope.sh" \
  --target-entrypoint http_config_settings

# default-token profile — the #11181 CF_API_TOKEN widen precondition + post-check:
bash "${CLAUDE_PLUGIN_ROOT}/skills/cf-token-scope/scripts/cf-token-scope.sh" --profile default-token
bash "${CLAUDE_PLUGIN_ROOT}/skills/cf-token-scope/scripts/cf-token-scope.sh" \
  --profile default-token --expect-lb-scopes

# Print the probe commands without running them (token stays unexpanded):
bash "${CLAUDE_PLUGIN_ROOT}/skills/cf-token-scope/scripts/cf-token-scope.sh" --dry-run
```

The token (`CF_API_TOKEN_RULESETS` or `CF_API_TOKEN`, resolved by `--profile`),
zone / account (`CF_ZONE_ID`, `CF_ACCOUNT_ID`) and Doppler config
(`soleur` / `prd_terraform`) are **profiles only, no raw token-var knob**: each
probe set is meaningful only for the token it binds to, so a `--token-var` knob
pointed at an arbitrary secret would run the wrong URLs against the wrong token.
The named-profile table is the one sanctioned widening of that posture —
`default-token` pairs the production default `CF_API_TOKEN` (the `cloudflare`
provider alias) with its own ledger probe set.

## Execution — the 3-step widen flow

1. **Pre-widen baseline.** Run the probe. Before the widen, the target
   entrypoint reads `403` (scope absent) while the known-granted controls read
   the authorized signal. Record this output — the added-scope check in step 3
   compares against it.

2. **Widen (Playwright MCP).** Follow
   [widen-playbook.md](./references/widen-playbook.md): decide widen-vs-mint per
   ADR-130, navigate to `https://dash.cloudflare.com/profile/api-tokens`, hand
   off only the login/MFA gate to the operator, then edit the token —
   three-dot menu → Edit → Add more → select the permission (same API family) →
   Continue to summary → Update token. Editing permissions does **not** rotate
   the token value, so no Doppler write follows.

   The widen transits a **full-power dashboard session** (the cookie is an
   account-wide bearer). Do **not** dump `browser_network_requests` /
   `browser_console_messages` to files, scope screenshots to the edit control,
   take any accessibility snapshot in the file form and filter the file through
   the redactor (`"${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"`)
   — an MCP tool result cannot be piped through a script; the playbook states
   when a bare call is safe — and
   always call `browser_evaluate` **with** a `filename` — without one the value
   is returned into the transcript. This corrects an inverted instruction that
   stood here previously; see the playbook's leak constraints.

3. **Post-widen verification.** Re-run the probe with
   `--target-entrypoint <phase>`. Success = the target is currently authorized AND
   every retained control stayed authorized AND the account-scheme control is an
   authorized `200` — exit 0, `PASS: target scope present` + `PASS: no scope
   dropped`. A single run cannot observe the `403 → authorized` *transition*, so
   the tool prints "present", not "added" — confirm the transition against your
   step-1 baseline.

### The same 3 steps for `CF_API_TOKEN` (the #11181 LB widen)

1. **Pre-widen baseline:** `--profile default-token`. The four retained ledger
   rows (Tunnel, Access, DNS, Notifications) must read `authorized (200)` — a
   retained failure here means the widen precondition is unmet, halt. The two LB
   target rows read `not-yet-widened (403)` and the run exits 0 with a `NOTE:`
   line — that is the expected absent-scope state BEFORE the widen.
2. **Widen** via the playbook to Zone `soleur.ai` → `Load Balancers: Edit` AND
   Account → `Load Balancing: Monitors and Pools: Edit` (append, never rebuild).
3. **Assert:** `--profile default-token --expect-lb-scopes` must exit 0 with
   `PASS: LB scopes present`. `not-yet-widened` is neutral ONLY in the step-1
   baseline — the widen is not verified until an assert run exits 0.

## Probe-set contract (three-layer fail-closed classifier)

The probe set is the ADR-130 four-probe retained set plus Zone WAF — four **zone**
phases (`http_config_settings`, `http_request_dynamic_redirect`,
`http_request_cache_settings`, `http_request_firewall_custom`) and one **account**
list (`accounts/<acct>/rulesets`). The classifier captures each response **body**
(not `-o /dev/null`) and decides in three layers:

1. **Status** — `403` / `000` / `5xx` / empty / no-newline / non-numeric = FAIL.
2. **Body-shape** — a `200` passes only when the body has `success == true` AND
   `.result` is an array. A degraded `200` (`{"success":false,...}` OR
   `{"success":true,"result":null}`) is a FAIL. Never key on `.result | length` —
   jq reads `null` as `0` and would pass.
3. **Per-scheme control** — the account list is the account-scheme control and
   must be an authorized `200` (an account `404` = FAIL). A zone `404` (ADR-130's
   "phase exists, empty") is trusted **only** for `http_config_settings` — the one
   phase whose 403-on-missing-scope semantics ADR-130 empirically verified — and
   only under an authorized zone control (`http_request_dynamic_redirect`). Every
   other phase's `404` fails closed: 403-on-missing is unverified there, so a
   dropped scope that returned `404` must not read as green.

Profile `default-token` — the `CF_API_TOKEN` set (the two LB rows are the
readiness probes of exactly the granted permission surfaces of the #11181
ruling; GETs attest the READ half):

| class | label | GET | attests | trust404 |
|---|---|---|---|---|
| retained | accounts/<acct>/cfd_tunnel | `.../cfd_tunnel?per_page=1` | Tunnel | 0 |
| retained | accounts/<acct>/access/apps | `.../access/apps?per_page=1` | Access | 0 |
| retained | zones/<zone>/dns_records | `.../dns_records?per_page=1` | DNS, zone soleur.ai | 0 |
| retained | accounts/<acct>/notification_policies | `.../notification_policies?per_page=1` | Notifications | 0 |
| target | accounts/<acct>/lb/pools | `.../load_balancers/pools?per_page=1` | Account Monitors-and-Pools (read half) | 0 |
| target | zones/<zone>/load_balancers | `.../load_balancers?per_page=1` | Zone Load Balancers (read half) | 0 |

Every default-token row is `trust404=0` — all rows fail closed on 404 (the
verified-404 exception stays exclusive to `http_config_settings`). `target`-class
neutrality is minted at exactly ONE classifier site and ONLY in baseline mode: a
clean `403` prints `not-yet-widened (403)` (with the parsed `errors[0].code`
appended when present) and the run stays exit-neutral with a `NOTE:` summary;
any other anomaly (404, degraded 200, wrong-shape 200, 5xx, 000, empty) is a
hard fail in BOTH modes. In assert mode (`--expect-lb-scopes`) every target row
must be authorized or the run exits 3 naming the still-absent 403s. The `target`
vocabulary is default-token-local: the rulesets `--target-entrypoint` path keeps
its own `TARGET_PRESENT` handling and never consults this classifier.

## Exit codes

- `0` — every retained scope authorized (and, per profile: the rulesets target,
  if given; in `default-token` baseline, LB rows authorized OR reported
  `not-yet-widened`; in `--expect-lb-scopes` assert mode, all LB rows authorized).
- `2` — usage error (including an unknown `--profile` and a flag used with the
  wrong profile — always raised before any secret read), missing prerequisite
  (`curl` / `doppler` / `jq`), or an absent Doppler secret.
- `3` — probe failed: a scope was dropped, degraded, or denied (assert mode: an
  LB row still `403` or anomalous).

## Sharp Edges

- **The probe set is a CANARY for the whole-list REPLACE failure mode, not
  exhaustive per-permission coverage.** A dashboard save that replaces (not
  appends) drops *all* scopes at once → every probe catches it. Zone WAF
  (`http_request_firewall_custom`) is now probed, but Transform Rules
  (`http_response_headers_transform`) and account Filter Lists are not — a
  *surgical* single-permission drop of one of those can still pass. Extend the
  entrypoint set if a future threat model needs per-permission coverage.
- **The probe attests read reachability, not `:Edit` retention.** It issues `GET`,
  so a dashboard REPLACE that re-adds a phase as **Read-only** (a one-click
  operator error — the CF dropdown lists Read/Edit side-by-side) returns an
  authorized `200` and reads as green while the write/hijack capability was
  dropped. Visually confirm the widened permission is `Edit`, not `Read`.
- **Probe, never trust the Cloudflare UI permission label** — it is named
  inconsistently across surfaces. The target entrypoint returning non-403 is the
  ground truth (ADR-130).
- **Update the scope ledger.** After a widen, add the new permission to the
  `apps/web-platform/infra/variables.tf` description of the widened token (ADR-130's
  scope ledger), in the feature PR that consumes the widen. For the `CF_API_TOKEN`
  LB widen that is the post-widen follow-on: the two permissions join the
  `cf_api_token` description — and ADR-130 gains its one-paragraph amendment note
  pinning that the `CF_API_TOKEN` retained-scope re-check is the `default-token`
  profile probe set — in the PR that consummates the widen, never before the
  dashboard act has actually run.
- **The LB readiness probes attest read reachability, not `:Edit`** — the same
  one-click Read-vs-Edit trap as the rulesets probe: a dashboard REPLACE that
  re-adds `Load Balancers` as Read-only returns an authorized `200` and reads as
  green while the write capability was dropped. Visually confirm `Edit` on both
  granted rows.
- **`not-yet-widened` is neutral ONLY in baseline mode.** The widen is not
  verified until an `--expect-lb-scopes` run exits 0. Reading a green baseline
  (post-widen) as proof of the transition is the same present-not-added trap the
  rulesets flow documents.
- **Never print the Bearer token.** The script passes it from a private fd (not
  argv), `--dry-run` leaves it unexpanded, and it runs no `set -x`. When driving
  the widen, keep the full-power-session leak constraints above.
- **New phase → enumerate before apply.** If the widen enables a *new* ruleset
  phase, confirm its entrypoint is `404`/empty before any infra apply, or a
  whole-list ruleset create clobbers dashboard rules (ADR-130, ADR-136).

## Related

- [ADR-130](../../../../knowledge-base/engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md) — widen-vs-narrow-alias rule, the four-probe retained-scope set, and the capability gap this skill closes.
- [ADR-136](../../../../knowledge-base/engineering/architecture/decisions/ADR-136-preapply-entrypoint-enumeration-gate.md) — the standing pre-apply entrypoint-enumeration gate.
- [provision-cloudflare](../provision-cloudflare/SKILL.md) — mints *tenant* tokens (a distinct function; requires `User API Tokens:Edit`, which no Soleur token holds).
- [widen-playbook.md](./references/widen-playbook.md) — the Playwright MCP click-path and leak constraints.
- Learnings: `2026-03-21-cloudflare-api-token-permission-editing.md` (the Playwright widen path), `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md` (the three-layer classifier).
