---
name: cf-token-scope
description: This skill should be used to widen an existing Cloudflare API token's scope via Playwright dashboard automation, then run the ADR-130 retained-scope probe set verifying the target scope was added and none was dropped.
---

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

```bash
# Baseline / re-check — probe the four ADR-130 retained scopes:
bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh

# After a widen — also assert the newly-added scope is live:
bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh \
  --target-entrypoint http_config_settings

# Print the probe commands without running them (token stays unexpanded):
bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh --dry-run
```

The token / zone / account (`CF_API_TOKEN_RULESETS`, `CF_ZONE_ID`,
`CF_ACCOUNT_ID`) and Doppler config (`soleur` / `prd_terraform`) are hardcoded:
the ADR-130 retained-scope URL set is meaningful only for the rulesets token, so
a `--token-var` knob pointed elsewhere would run the wrong URLs against the wrong
token.

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
   use snapshot-only navigation, and never call `browser_evaluate` with a
   `filename` — see the playbook's leak constraints.

3. **Post-widen verification.** Re-run the probe with
   `--target-entrypoint <phase>`. Success = the target is currently authorized AND
   every retained control stayed authorized AND the account-scheme control is an
   authorized `200` — exit 0, `PASS: target scope present` + `PASS: no scope
   dropped`. A single run cannot observe the `403 → authorized` *transition*, so
   the tool prints "present", not "added" — confirm the transition against your
   step-1 baseline.

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

## Exit codes

- `0` — every retained scope authorized (and the target, if given).
- `2` — usage error, missing prerequisite (`curl` / `doppler` / `jq`), or an absent Doppler secret.
- `3` — probe failed: a scope was dropped, degraded, or denied.

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
  scope ledger), in the feature PR that consumes the widen.
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
