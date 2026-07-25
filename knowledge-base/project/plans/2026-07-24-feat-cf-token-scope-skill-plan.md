---
title: "feat: Build the first-party soleur:cf-token-scope skill (Cloudflare token widen + retained-scope probe)"
type: feat
date: 2026-07-24
issue: 6755
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this skill introduces NO infrastructure. It reads Doppler
     secrets read-only and runs no terraform. The widen target is an operator-minted
     CF token deliberately NOT modeled as a cloudflare_api_token resource
     (variables.tf:285). See "## Other gates considered" -> IaC routing gate: N/A. -->

# feat: `soleur:cf-token-scope` — Cloudflare token widen + retained-scope probe

## Enhancement Summary

**Deepened on:** 2026-07-24
**Review panel:** security-sentinel (completed), code-simplicity-reviewer (completed),
architecture-strategist + spec-flow-analyzer (API-failed mid-response — their questions
addressed inline from first-party analysis; see Research Insights).

### Key improvements folded in

1. **Classifier hardened against the two fail-open seams in the cited learning
   (security HIGH).** The original `-o /dev/null` + uniform `200|404 = PASS` reproduced
   both seams of `2026-07-23-live-api-fail-closed-guard...`: it discarded the body (can't
   catch a degraded `200 {"success":false,"result":null}`) and trusted an account-scheme
   `404` with no per-scheme control. Now: capture the body and assert `success == true`
   (+ `.result` is an array) on 200; add a **per-scheme control probe** — the account
   list (`accounts/<acct>/rulesets`) must return `200`-with-array before any `404` in that
   scheme may PASS; **account-scheme `404` = FAIL**; a zone-scheme `404` passes only when a
   known-granted zone control is `200`.
2. **Negative claims are now grep-guard ACs**, not prose: no Doppler write, no
   `terraform`, no `set -x`; the no-leak test greps combined `2>&1` (stderr too).
3. **Honesty correction on the widen mechanism.** The adopted Playwright path still
   transits a *full-power* CF dashboard session (broader than the rejected ephemeral
   `User API Tokens:Edit` token). Kept the decision (no omnipotent token ever exists) but
   corrected the framing + added browser-capture leak mitigations (no network/console
   dumps to files, edit-control-scoped screenshots, snapshot-only navigation).
4. **Simplified surface (YAGNI).** Removed the no-op `--probe-only`; hardcoded the
   rulesets token/zone/account/config (the ADR-130 probe set is meaningful only for
   `cf_api_token_rulesets`); folded the probe-semantics reference into SKILL.md (one
   reference doc); demoted entrypoint-enumeration + ledger-update from flow steps to notes.

### New considerations discovered

- **The ADR-130 4-probe set is a canary for the whole-list REPLACE failure mode, not
  exhaustive per-permission coverage.** A dashboard "save" that replaces rather than
  appends drops *all* scopes at once → all four probes catch it. It does NOT probe every
  phase in the rulesets token's ledger (Zone WAF / `firewall_custom`, Transform Rules /
  `response_headers_transform`, account Filter Lists are unprobed). This is acceptable for
  the actual threat (append-vs-replace) but must be documented as a Sharp Edge so a
  surgical single-permission drop is not silently green.
- ADR-130 empirically pinned `403`-on-missing-scope for only ONE entrypoint
  (`http_config_settings`). The 403/404 semantics of the other three (esp. the account
  list) are assumed; `/work` must pin them or treat account `404` as FAIL.

## Overview

Build a first-party Claude Code skill, `soleur:cf-token-scope`, that closes the
capability gap ADR-130 explicitly leaves open in its *"Capability gap (not closed by
this ADR)"* section: **there is no first-party path for Cloudflare API-token scope
changes**, so every one becomes an ad-hoc dashboard trip (third on record — #6657 DNS,
#6649 R2, #6755 Config Rules).

The skill performs a Cloudflare API-token **scope widen** (add a permission in the same
API family per ADR-130's widen-vs-mint rule) via **Playwright MCP** dashboard automation,
then runs the **ADR-130 retained-scope probe set** (four `curl` GETs against
`http_config_settings` + `http_request_dynamic_redirect` + `http_request_cache_settings`
entrypoints + `accounts/<acct>/rulesets`) to confirm the target scope was **added** AND
that **no existing scope was dropped** (403 = failure; **404 on an entrypoint is a pass**
— the phase exists with no ruleset yet; only 403 is a failure).

**The incident that triggered #6755 is already resolved** — `Config Rules:Edit` was
appended to `cf_api_token_rulesets` 2026-07-20 and is live (`variables.tf:224` scope
ledger records it; the four-probe retained set all return 200). No widen action remains.
The deliverable here is the **durable tooling**, not a widen.

**Scope of this plan:** a new skill (SKILL.md + a deterministic bash probe script + two
reference docs + a bash test), an amendment to ADR-130 marking the capability gap closed
and recording the browser-vs-API mechanism decision, the skill-description budget bump,
and README/docs count updates. **No production infrastructure changes** (the skill reads
Doppler secrets read-only and drives the dashboard; it runs no `terraform`).

## Problem Statement / Motivation

ADR-130 (`knowledge-base/engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md`)
established *how* to decide widen-vs-mint and *what* to verify after any re-scope of a
shared token (the four-probe retained-scope set). But it leaves the **execution** manual:

- `soleur:provision-cloudflare` mints *tenant* tokens via the `cloudflare_api_token`
  Terraform resource, which itself requires `User API Tokens:Edit` — a permission **no
  Soleur token holds**, and the account deliberately has **no Global API Key**
  (`variables.tf:285`, ADR-130). So the operator-minted first-party tokens (e.g.
  `cf_api_token_rulesets`, `cf_api_token_dns_edit`) are **not** Terraform-managed
  resources and cannot be re-scoped via API.
- Therefore every scope change is a hand-driven dashboard trip, and the safety-critical
  half — proving a dashboard edit **appended** rather than **replaced** scopes (a replace
  silently breaks cache rules, WAF, single redirects, transform rules, and account bulk
  redirects at once) — is done by eye or skipped.

The durable fix is a skill that automates the dashboard widen up to the interactive-auth
gate and makes the retained-scope probe a deterministic, fail-closed command.

## Proposed Solution

A `soleur:cf-token-scope` skill whose **deterministic core** is the retained-scope probe
(pure API, read-only, **fail-closed with body-shape assertion + per-scheme control**) and
whose **operator-facing action** is a Playwright-MCP-assisted widen. Three flow steps:

1. **Pre-widen baseline.** Run the probe (default mode — the script only ever probes). It
   prints each entrypoint's status; before a widen, the target entrypoint reads **403**
   (scope absent — the control-probe negative) while the known-granted controls read the
   authorized signal (200-with-array, or an ADR-130-endorsed zone 404 gated by a zone
   control). This 403-on-new + authorized-on-known isolation is the house control-probe
   pattern (learnings `2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md`,
   `2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`).
2. **Widen (Playwright MCP).** Navigate to `https://dash.cloudflare.com/profile/api-tokens`,
   operator clears login/MFA (interactive-auth gate — the sanctioned manual carve-out),
   agent edits the target token: three-dot menu → Edit → "Add more" → select the
   permission (same API family per ADR-130) → "Continue to summary" → "Update token".
   Editing permissions does **not** rotate the token value (learning
   `2026-03-21-cloudflare-api-token-permission-editing.md`), so no Doppler write and no
   dependent-infra re-run is needed. **The widen transits a full-power dashboard session**
   — do NOT dump `browser_network_requests`/`browser_console_messages` to files, scope
   screenshots to the edit control, use snapshot-only navigation (the session cookie is an
   account-wide bearer, strictly broader than the token being edited).
3. **Post-widen verification.** Re-run the probe with `--target-entrypoint <phase>`.
   Success = the target entrypoint flipped **403 → authorized** (scope added, observed by
   comparing this run's output to step 1) AND all controls stay authorized (nothing
   dropped) AND `/user/tokens/verify` reports `active`.

**Notes folded out of the flow (were over-weighted as steps):**
- *New-phase entrypoint enumeration* (widen-playbook note, not a flow step): if the widen
  enables a *new* ruleset phase, enumerate that phase's entrypoint and confirm it is
  404/empty before any subsequent `terraform apply` (ADR-130: a `kind="zone"` ruleset OWNS
  its phase entrypoint as whole-list replacement). ADR-136 already gates this at apply
  time; this manual check is the `/work`-time pre-*write* backstop, only for a new phase.
- *Scope-ledger update* (SKILL.md Sharp Edge, not a flow step): the `variables.tf`
  description for the widened token (the ADR-130 "scope ledger") must be updated with the
  new permission in the relevant feature PR — a code edit, not this skill's runtime.

The **widen mechanism decision (Playwright MCP, not a standing API meta-token)** is the
plan's key architectural call and is recorded as a User-Challenge (see Research
Reconciliation + `decision-challenges.md`), because it diverges from the pipeline
framing's implicit lean toward an API approach. **Honest framing (security review):** the
Playwright path still transits a full-power dashboard session — it is not *strictly*
least-privilege — but it avoids ever minting an omnipotent `User API Tokens:Edit` token
(even ephemerally), which is the invariant we keep.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue / pipeline framing) | Reality (verified) | Plan response |
|---|---|---|
| "The immediate #6755 incident is already resolved" | `variables.tf:224` scope ledger: `Config Rules:Edit` appended 2026-07-20, live; four-probe retained set all 200 | Confirmed. Plan builds tooling only; no widen action. |
| "Weigh a robust API approach using a dedicated `User API Tokens:Edit` token" | `variables.tf:285` + ADR-130: no Soleur token holds `User API Tokens:Edit`; no Global API Key (deliberate). Editing token perms via API requires that omnipotent scope. | **Rejected** as standing credential (Global-API-Key-equivalent). See Alternatives + UC-1. |
| "agent-browser daemon was wedged" ⇒ avoid the browser | `agent-browser` (Vercel CLI daemon) wedges on a stale socket; **Playwright MCP is a distinct surface** and is the documented tool for CF token edits (learning 2026-03-21, #992) | Use **Playwright MCP** for the widen; do NOT use the agent-browser CLI. |
| ADR-130 recommends a "Playwright-driven" skill (ADR-130:173) | Confirmed at that line | Adopt as primary mechanism. |
| Cloudflare must be added to the C4 model | `model.c4:234` `cloudflare = system "Cloudflare"` already modeled; edges `github -> cloudflare` (rulesets GET, ADR-136) and `api -> cloudflare` (DNS-edit) exist | **No C4 impact** — see Architecture Decision section (enumeration cited). |
| Skill descriptions have "1800-word cap" (plan-skill prose) | Actual gate: moving constant `SKILL_DESCRIPTION_WORD_BUDGET = 2366` in `components.test.ts:16`, currently at **zero headroom** | Bump the constant by the new description's word count with a justification comment (established pattern). |

## Technical Considerations

### Architecture

- **Deterministic core = the probe script** (`scripts/cf-token-scope.sh`): `curl` GETs
  that **capture the body** (NOT `-o /dev/null`) and read Cloudflare token/zone/account
  from Doppler read-only. **Fail-closed, in three layers** (all from learning
  `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md`, which this design must satisfy in full — not merely cite):
  1. **Status layer:** `403`/`000`/`5xx`/empty/non-numeric = FAIL.
  2. **Body-shape layer (guards degraded-200):** a `200` PASSes only if the JSON body has
     `success == true` AND `.result` is an array. A `200 {"success":false,"result":null}`
     is a FAIL. Do **not** key on `.result | length` (reads `null` as `0`) — key on the
     shape.
  3. **Per-scheme control layer (guards 404-trust):** the four probes span two schemes —
     three **zone** (`http_config_settings`, `http_request_dynamic_redirect`,
     `http_request_cache_settings`) and one **account** (`accounts/<acct>/rulesets`). A
     `404` is trusted as "phase exists, empty" ONLY within a scheme whose known-granted
     control returned an authorized 200. The **account list is itself the account-scheme
     control**: it must return `200`-with-array — an account-scheme `404` is a FAIL (a
     mis-built account URL or dropped `Account Rulesets:Edit` is indistinguishable from an
     empty phase otherwise). A zone `404` (ADR-130-endorsed pass) is trusted only when a
     zone control (a known-granted zone entrypoint, e.g. `dynamic_redirect`) returned an
     authorized 200; a blanket zone 403/degraded = bad token, not a scope drop.
  ADR-130 empirically pinned `403`-on-missing for only `http_config_settings`; `/work`
  must pin the other entrypoints' 403/404 semantics live, or keep account `404` = FAIL.
  (This is a deliberate *strengthening* of ADR-130's illustrative `-o /dev/null` snippet —
  recorded in the ADR-130 amendment.)
- **Widen = Playwright MCP**, orchestrated by SKILL.md prose (bash cannot drive MCP
  tools). The script never touches the browser.
- **No new infrastructure.** No new Doppler secret, no new TF resource, no new provider
  alias. The widen target is an operator-minted CF token that is deliberately *not* a
  `cloudflare_api_token` resource (`variables.tf:285`), so `hr-all-infrastructure-provisioning-servers`
  is satisfied by driving the only available path (dashboard, interactive-auth-gated)
  with maximal automation — analogous to `soleur:admin-ip-refresh`, which likewise does
  not call `terraform`. **IaC gate (plan Phase 2.8): N/A** — no server/secret/DNS/cert/
  firewall/vendor-account introduced.

### Security considerations

- **Token value never echoed.** Read into an env var; pass via `curl -H "Authorization:
  Bearer $TOK"`; `--dry-run` prints the command with `$TOK` **unexpanded** (trigger-cron
  pattern). If Playwright `browser_evaluate` is ever used to read a value, do it
  **without** `filename` to avoid transcript leakage (learning
  `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`).
- `cf_api_token_rulesets` carries Single Redirect:Edit (a full soleur.ai traffic-hijack
  primitive per ADR-130 axis-1) + Zone WAF:Edit — leaking it is high-severity. This is
  why value-echo protection is load-bearing, not cosmetic.
- **The omnipotent-meta-token approach is rejected** — see Alternatives + UC-1.

### Attack Surface Enumeration

- **How the token is read:** `doppler secrets get CF_API_TOKEN_RULESETS -p soleur -c prd_terraform --plain`
  (read-only; the skill never writes Doppler). Checked path: the script; no other read path.
- **How the token is transmitted:** the Authorization header is passed to `curl` from a
  **private fd**, e.g. `curl -H @<(printf 'Authorization: Bearer %s' "$TOK")`, NOT
  `-H "Authorization: Bearer $TOK"` — the inline form places the expanded token in the
  process argv, readable via `ps` / `/proc/<pid>/cmdline` for the curl lifetime (security
  LOW; on a single-user box but a real surface). `--dry-run` never expands it.
- **Bypass/leak vectors (each covered by an AC or the widen-playbook):**
  transcript echo (mitigated: no echo, unexpanded dry-run); process argv (mitigated:
  header-from-private-fd); shell trace (mitigated: no `set -x` — grep-guard AC); Playwright
  `browser_evaluate` filename JSON dump (mitigated: no filename); **the full-power CF
  dashboard session cookie** captured by `browser_network_requests` /
  `browser_console_messages` / `browser_snapshot` / `browser_take_screenshot` (mitigated
  in widen-playbook: no network/console dumps to files, edit-control-scoped screenshots,
  snapshot-only navigation).
- The no-leak test greps **combined `2>&1`** output (stderr too — a `set -x` trace or a
  curl error prints the expanded header to stderr, escaping a stdout-only assertion).

## User-Brand Impact

- **If this lands broken, the user experiences:** a **false-green retained-scope probe**
  lets a silent scope-*drop* pass unnoticed → the next `terraform apply` on
  `apps/web-platform/infra/` 403s or a whole-list ruleset create clobbers dashboard
  rules → soleur.ai edge behavior (WAF, SEO redirects, cache rules, Flexible-SSL config)
  breaks for **every** visitor to the operator's brand site. A false verdict here is
  worse than no tool, because it manufactures confidence.
- **If this leaks, the operator's infrastructure is exposed via:** the
  `cf_api_token_rulesets` Bearer token echoed into the session transcript or logs —
  granting a reader Single Redirect:Edit (redirect any soleur.ai path to attacker
  infrastructure) + Zone WAF:Edit on the production zone.
- **Brand-survival threshold:** `single-user incident` — a single botched run breaks the
  solo operator's entire brand surface, and the tool handles a production credential with
  a traffic-hijack primitive. `requires_cpo_signoff: true`; `user-impact-reviewer` runs
  at review time.

## Observability

```yaml
liveness_signal:
  what:            "The retained-scope probe set itself — four HTTP status codes printed per run (the tool IS the observability surface for CF token scope)."
  cadence:         "per-run (on demand); the script only probes, so any run is a read-only re-check"
  alert_target:    "operator terminal (non-zero exit on any 403); the standing pre-apply gate (ADR-136, apply-web-platform-infra.yml) is the CI-time backstop"
  configured_in:   "plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh"

error_reporting:
  destination:     "operator terminal + non-zero exit code (interactive operator skill; no Sentry surface — not a server runtime)"
  fail_loud:       "exit 3 on any probe returning non-200/404; exit 2 on missing prereq (doppler/curl/secret); the per-entrypoint status line is printed for every probe"

failure_modes:
  - mode:          "false-green: a dropped scope reads as pass"
    detection:     "fail-closed classifier — only 200/404 pass; 403/000/5xx/empty/non-numeric fail; control probe on a known-granted entrypoint must be non-403 or the run aborts (a blanket 403 = bad token, not a scope drop)"
    alert_route:   "operator terminal (exit 3)"
  - mode:          "token leaked to transcript"
    detection:     "test asserts no un-redacted Bearer value is printed; --dry-run leaves $TOK unexpanded"
    alert_route:   "code review + cf-token-scope.test.sh"
  - mode:          "widen replaced instead of appended (dropped a retained scope)"
    detection:     "post-widen probe: all four controls must stay non-403 AND target must flip 403->non-403"
    alert_route:   "operator terminal (exit 3)"

logs:
  where:           "operator terminal stdout/stderr (ephemeral, interactive run)"
  retention:       "session-scoped; re-run the script to re-read live state"

discoverability_test:
  command:         "bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh"
  expected_output: "four '<entrypoint> -> <code> (authorized)' lines and 'PASS: no scope dropped'; exit 0 (NO ssh)"
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-130** (`knowledge-base/engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md`),
same issue (#6755) — do **not** file a new ADR; ADR-130 already frames this gap:

- Update the **"Capability gap (not closed by this ADR)"** section → mark it **closed by
  `soleur:cf-token-scope`** (Playwright MCP widen + the four-probe retained-scope set).
- Add an `## Amendment (#6755)` section (house convention — 18 accepted ADRs carry
  amendment/addendum sections) recording: (1) the widen is driven via **Playwright MCP
  dashboard automation**; a standing `User API Tokens:Edit` token is **rejected** as
  Global-API-Key-equivalent power the account deliberately lacks (axis-1); **honest note**
  — the Playwright path still transits a full-power dashboard session, so it is not
  *strictly* least-privilege, but it never mints an omnipotent token. Cite learning
  `2026-03-21-cloudflare-api-token-permission-editing.md`. (2) The skill **strengthens**
  ADR-130's illustrative `-o /dev/null` + `%{http_code}` probe to a three-layer fail-closed
  classifier (status → body-shape `success==true` → per-scheme control) per learning
  `2026-07-23-live-api-fail-closed-guard...`, and records that the canonical four-probe set
  is a **canary for whole-list REPLACE**, not exhaustive per-permission coverage.
- Amend (not supersede); ADR-130 stays `accepted`. No ordinal collision risk.

### C4 views

**No C4 impact.** Enumeration (read against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` at
`/work` time; confirm before concluding):

- **External human actors:** none new. The operator running a local skill is not modeled
  as a C4 actor (precedent: `soleur:provision-cloudflare` has no C4 node — local
  operator tooling is outside the runtime C4 boundary).
- **External systems/vendors:** Cloudflare is **already** modeled (`model.c4:234`
  `cloudflare = system "Cloudflare"`) and already appears in the System-Context include
  lists (`views.c4:14`, `:36`). The skill's read-only rulesets GET is the same shape as
  the existing `github -> cloudflare` ADR-136 edge (`model.c4:424`) but from a local
  operator origin that the runtime model does not depict.
- **Containers / data stores:** none new.
- **Access relationships:** none changed in the runtime model.

A "no C4 impact" conclusion is only valid if `/work` confirms the above by reading the
three `.c4` files (C4 completeness mandate). If any check fails, add the element +
`#external` tag + edge + `views.c4` include line and run `c4-code-syntax.test.ts` +
`c4-render.test.ts`.

## Research Insights (deepen-plan)

The architecture-strategist and spec-flow-analyzer Tasks failed mid-response (API errors);
their questions are resolved here from first-party analysis:

- **Amend vs. new ADR (architecture).** Amend ADR-130 (same issue #6755, already frames the
  gap). Verified house convention: 18 accepted ADRs carry `## Amendment`/`## Addendum`
  sections, so amending an `accepted` ADR is standard — no supersede, no new ordinal.
- **C4 no-impact (architecture).** Confirmed sound: Cloudflare is already a modeled system
  (`model.c4:234`) in the System-Context include lists; the operator-run local skill is
  outside the runtime C4 boundary (precedent: `provision-cloudflare` has no C4 node).
- **Proxy-vs-invariant (spec-flow).** Keying on the CF ruleset entrypoint's authorization
  status is ADR-130's own ground truth ("Probe 1 returning non-403 is the ground truth"),
  not a proxy — BUT the four-probe set is a **canary for whole-list REPLACE**, not
  exhaustive per-permission coverage (WAF/`firewall_custom`, transform, account filter
  lists unprobed). Acceptable for the real threat (append-vs-replace, which drops all at
  once); documented as a Sharp Edge so a surgical single-permission drop is not silent.
- **Missing-writer-path (spec-flow).** The "target scope ADDED" half is preserved via
  `--target-entrypoint` (kept against the simplicity reviewer's defer-it advice, because
  the issue explicitly requires confirming the add). The probe is invoked by the operator
  at both baseline and post-widen; the SKILL.md flow wires both.
- **Control probe (spec-flow + security).** A blanket-denied set (bad token) vs a
  single-entrypoint denial (dropped scope) is distinguished by the per-scheme control
  layer — load-bearing for correctness (gates 404-trust), kept minimal (one control per
  scheme inside the one loop, not a separate subsystem).

## Implementation Phases

Dependency-ordered (contract/deterministic core first, then prose that depends on it).

### Phase 0 — Preconditions (`/work` Phase 0)

- Read all three `.c4` files and confirm the "no C4 impact" enumeration above.
- Re-read `ADR-130` `## Consequences` (the exact four-probe URLs + 403/404 semantics).
- Confirm Doppler read access: `doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain` returns a 32-hex value (do NOT print the token secrets themselves).
- Confirm `jq` is on PATH (body-shape layer depends on it) — `command -v jq`.
- Pin the live 403/404/degraded-200 semantics of the three not-yet-empirically-verified
  entrypoints (dynamic_redirect, cache_settings, account list) with a read-only probe, or
  keep account-scheme `404` = FAIL (ADR-130 verified only `http_config_settings`).
- Re-measure the skill-description budget with the Node one-liner and confirm the
  `SKILL_DESCRIPTION_WORD_BUDGET` constant is still `2366` at HEAD (rebase drift check).

### Phase 1 — Deterministic probe script (RED first)

Write `plugins/soleur/test/cf-token-scope.test.sh` **before** the script (cq-write-failing-tests-before):
stub `curl` on PATH to emit scripted status+body pairs, stub `doppler` to echo fixture
zone/account, and assert:
- all controls authorized (200 + `{"success":true,"result":[]}`) + target 403→authorized
  ⇒ exit 0, `PASS: no scope dropped` + `PASS: target scope added` printed;
- any zone control 403 ⇒ exit 3, `PASS: no scope dropped` NOT printed;
- **degraded 200** (`{"success":false,"result":null}`) on any probe ⇒ exit 3 (body-shape layer);
- **account-scheme 404** ⇒ exit 3 (account list is its own control — 404 is not a pass there);
- **zone 404 with the zone control at 200** ⇒ that zone entrypoint PASSes; zone 404 with a
  degraded/403 zone control ⇒ exit 3;
- `000`/empty/`500` ⇒ exit 3 (status layer);
- `--dry-run` prints the `curl` lines with the token **unexpanded** and never calls the stub curl;
- no Bearer token value appears in **combined `2>&1`** output;
- grep-guard: the script source contains no `set -x`, no Doppler write verb, no `terraform`.

Then write `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`:
- `set -euo pipefail`; manual arg parse (case-statement + positional fallback, house style).
- **Args (minimal): `--target-entrypoint <phase>` (optional; confirms the ADDED scope),
  `--dry-run`, `--help`.** The token/zone/account env-var names and Doppler config are
  **hardcoded** (`CF_API_TOKEN_RULESETS`, `CF_ZONE_ID`, `CF_ACCOUNT_ID`, `prd_terraform`) —
  the ADR-130 retained-scope URL set is meaningful only for the rulesets token, so a
  `--token-var` knob pointed elsewhere would run the wrong URLs against the wrong token.
  The script has exactly one mode (probe); there is no `--probe-only` (it would be a no-op).
- Prereq checks: `command -v curl`, `command -v doppler`, `command -v jq` (exit 2 if missing).
- Read secrets read-only into env vars via `doppler secrets get <NAME> -p soleur -c prd_terraform --plain` (exit 2 if a secret is absent).
- Probe loop over the four ADR-130 URLs (+ `--target-entrypoint` if given, de-duped),
  **capturing status AND body**: `curl -sS -w '\n%{http_code}' --max-time 15 -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url"` (header from a private fd — not argv).
- Three-layer fail-closed classifier (see Architecture above): status → body-shape
  (`jq -e '.success==true and (.result|type=="array")'`) → per-scheme control (account
  list must be authorized-200; zone 404 trusted only under an authorized zone control).
  Print `"<url> -> <code> (<authorized|denied|degraded|empty>)"` per probe.
- Verdict: exit 0 iff every retained control is authorized (and, if `--target-entrypoint`
  given, it is authorized); print `"PASS: no scope dropped"` and, when applicable,
  `"PASS: target scope added"`. On a blanket-denied set, print the bad-token diagnostic
  (a message refinement inside the one loop — not a separate control subsystem). Exit 3 on
  any FAIL. `trap` cleanup unsets token env vars.
- `--dry-run`: print the `curl` commands with the token unexpanded; exit 0 without executing.

### Phase 2 — Reference doc + SKILL.md

- **One reference doc** — `references/widen-playbook.md` (rare, lazy-loaded): the Playwright
  MCP click-path (from learning 2026-03-21), the combobox-offscreen gotcha (click parent
  container), the ADR-130 widen-vs-mint test, the new-phase entrypoint enumeration, and the
  **full-power-session leak constraints** (no `browser_network_requests`/`browser_console_messages`
  dumps to files, edit-control-scoped screenshots, snapshot-only navigation). The
  **probe-set semantics fold into SKILL.md** (needed on every invocation → belongs inline
  per skill-creator progressive-disclosure, not a lazily-loaded reference that would become
  a third copy of the classifier rule to drift).
- `SKILL.md`: frontmatter (`name: cf-token-scope`, third-person `description:` — see budget
  below), `## Usage`, `## Execution` (the 3-step flow: baseline → widen → verify), the
  inline probe-set contract (four entrypoints, three-layer fail-closed classifier), a
  Playwright pre-flight checklist AC (**no `browser_evaluate` filename**), `## Exit codes`,
  `## Sharp Edges` (incl. the scope-ledger-update reminder + the canary-not-exhaustive
  note), `## Related` (ADR-130, ADR-136, provision-cloudflare, the learnings). All
  `references/`/`scripts/` linked as markdown links. Prose must not include `<example>` blocks.

### Phase 3 — Budget + docs + ADR amendment

- `plugins/soleur/test/components.test.ts:16`: bump `SKILL_DESCRIPTION_WORD_BUDGET` by the
  description's exact word count (target ~34) with a justification comment appended in the
  established format: `bumped +<N> for #6755 (cf-token-scope skill description, <N> words,
  against a 2366/2366 zero-headroom baseline)`.
- `plugins/soleur/README.md`: add the skill to the skills table + bump the skill count.
  Run `soleur:release-docs` conventions (also updates `plugin.json` description count + the
  Eleventy docs data if applicable). Verify counts via the components test + build.
- Amend `ADR-130` per the Architecture Decision section.
- `knowledge-base/project/specs/feat-one-shot-cf-token-scope-6755/decision-challenges.md`
  already written by plan (UC-1); `/ship` renders it into the PR body + files an
  `action-required` issue.

### Phase 4 — Verify

- `bash plugins/soleur/test/cf-token-scope.test.sh` (stubbed) passes.
- `bun test plugins/soleur/test/components.test.ts` passes (budget + third-person voice +
  char-limit + reference-link lint).
- `shellcheck` clean on the new script (if available in the repo's test-all path).
- `--dry-run` and a default (probe) smoke-run against a stubbed curl.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| **Playwright MCP dashboard widen + API probe set** | **Adopted** | Documented house path for CF token edits (learning 2026-03-21); no new standing credential; matches ADR-130:173; token value does not rotate. |
| Standing `User API Tokens:Edit` API token (pure-API widen) | **Rejected** | Global-API-Key-equivalent; reverses the deliberate no-omnipotent-credential posture (`variables.tf:285`, ADR-130 axis-1); high leak blast-radius for a security delta the account chose not to hold. |
| Ephemeral operator-supplied `User API Tokens:Edit` token (mint→use→revoke) | **Rejected (documented future opt-in)** | Honest trade (security review): arguably security-*optimal* for the automation phase (deterministic API, no live omnipotent-session transit, no browser-capture surface) — but rejected because (a) it briefly creates an omnipotent token whose orphaning (skipped/failed revoke) leaves a standing Global-API-Key-equivalent, and (b) it is dominated on UX (dashboard mint + paste + delete > driving the widen in-session). The Playwright path's invariant — *no omnipotent token ever exists* — is the one we keep. |
| `agent-browser` CLI (Vercel daemon) for the widen | **Rejected** | The surface that wedges (stale socket); Playwright MCP is the more robust, documented alternative. |
| Import operator-minted tokens into Terraform as `cloudflare_api_token` | **Rejected (non-goal)** | Managing them via TF itself requires `User API Tokens:Edit` (circular/blocked); ADR-130 already settled their operator-minted nature. |

## Acceptance Criteria

### Pre-merge (PR) — Functional

- [ ] `plugins/soleur/skills/cf-token-scope/SKILL.md` exists with third-person
      `description:`, all `references/`/`scripts/` linked as markdown links, no `<example>`
      blocks; `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] `scripts/cf-token-scope.sh` runs the four ADR-130 probes **capturing status AND body**
      and is fail-closed in three layers: (1) status (`403`/`000`/`5xx`/empty/non-numeric
      FAIL); (2) body-shape (a 200 PASSes only when `success==true` and `.result` is an
      array — degraded 200 FAILs); (3) per-scheme control (account-scheme `404` FAILs;
      zone `404` passes only under an authorized zone control).
- [ ] `--target-entrypoint <phase>` verdict requires that entrypoint authorized (added)
      AND all retained controls authorized (nothing dropped); prints `PASS: target scope
      added` + `PASS: no scope dropped` on success. Token/zone/account/config are hardcoded
      (no `--token-var`/`--probe-only`).
- [ ] `--dry-run` prints the `curl` commands with the token **unexpanded** and executes nothing.
- [ ] Token never leaks: the Authorization header is passed from a **private fd** (not
      inline `-H "…$TOK"` → not in argv); the no-leak test greps **combined `2>&1`** and
      finds no Bearer value.
- [ ] Grep-guard ACs (negatives enforced, not just prose): the script source contains no
      `set -x`, no Doppler write path (the script must not call `doppler` with a mutating
      subcommand such as `set`/`upload`/`delete`), and no `terraform` invocation; SKILL.md's
      Playwright checklist forbids `browser_evaluate` with a `filename` and forbids
      network/console dumps to files.
- [ ] `plugins/soleur/test/cf-token-scope.test.sh` (stubbed `curl`/`doppler`/`jq`) passes and is
      discovered by `scripts/test-all.sh`.
- [ ] `SKILL_DESCRIPTION_WORD_BUDGET` bumped by the exact new description word count with a
      justification comment; `components.test.ts` green.
- [ ] `README.md` skills table + count updated; docs build/counts verified.
- [ ] ADR-130 amended: capability gap marked **closed by soleur:cf-token-scope**; mechanism
      decision (Playwright, meta-token rejected) recorded.
- [ ] `decision-challenges.md` present with UC-1 (widen-mechanism challenge).

### Pre-merge (PR) — Verification shape (not phase-audit)

- [ ] Running the script against a stubbed authorized curl prints four authorized lines
      and exits 0; flipping one control to `403` (or a degraded `200 {"success":false}`)
      exits 3 and omits `PASS: no scope dropped`.

### Post-merge (operator)

- [ ] None required for this PR (tooling only; no widen action, no infra apply). A future
      widen invocation is the tool's use, not an acceptance criterion of this PR.
- [ ] `/work` confirms the C4 "no impact" enumeration against the three `.c4` files;
      if any element is missing, the C4 edit + `views.c4` include + c4 tests land in this PR.

## Test Scenarios

- Given all three control entrypoints return 200 and the target returns 200 after widen,
  when `cf-token-scope.sh --target-entrypoint http_config_settings` runs, then it prints
  `PASS: target scope added` + `PASS: no scope dropped` and exits 0.
- Given a retained control (e.g. `http_request_cache_settings`) returns 403 (scope
  silently dropped by a replace-instead-of-append widen), when the probe runs, then it
  exits 3 and does NOT print `PASS: no scope dropped`.
- Given `curl` returns `000` (network failure) or an empty body for any probe, when the
  probe runs, then it treats it as FAIL (fail-closed) and exits 3.
- Given `--dry-run`, when the skill runs, then it prints the four `curl` commands with
  `$TOK` literally unexpanded and never invokes `curl`.
- Given a missing Doppler secret or absent `curl`/`doppler`, when the skill runs, then it
  exits 2 with an install/config hint.
- **API verify (integration, operator-run):** `doppler run -c prd_terraform -- bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` (default probe mode) → four authorized lines, exit 0.
- **Browser (Playwright MCP, operator-present):** navigate `dash.cloudflare.com/profile/api-tokens`, edit target token, add permission, Update token; verify `/user/tokens/verify` → `active`.

## Domain Review

**Domains relevant:** Engineering / Infrastructure-Security.

### Engineering / Infrastructure-Security

**Status:** reviewed (sweep + delegated)
**Assessment:** The skill handles a production Cloudflare credential (read-only) and
mutates its scope via the dashboard. Core risks are (a) a false-green probe and (b) token
leakage — both addressed by the fail-closed classifier + control probe and by
value-echo protection. The security-posture crux (rejecting a standing `User API
Tokens:Edit` token) is argued in Alternatives + UC-1. **No Product/UX surface** (CLI
skill; no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files-to-Create),
so the Product/UX Gate is NONE and is skipped. Detailed security review is delegated to
**deepen-plan** (security-sentinel + architecture-strategist + data-integrity-guardian at
the single-user-incident threshold) and to **plan-review** (single-user-incident
escalation adds architecture-strategist; the named `cto`/devex lens is relevant for a new
skill) — running a redundant infra-security leader Task now would duplicate those layers.

### Product/UX Gate

**Tier:** none — no user-facing surface.

## Other gates considered

- **Network-outage checklist (Phase 1.4):** N/A. The `403` in scope is an
  authorization-scope signal, not a connectivity symptom; no SSH/firewall/DNS diagnosis.
- **GDPR gate (Phase 2.7):** N/A. No regulated/personal-data surface — the skill processes
  API credentials (secrets), not personal data. The `single-user incident` threshold here
  is a security/brand blast-radius classification, not a personal-data processing activity.
- **IaC routing gate (Phase 2.8):** N/A. No server/secret/DNS/cert/firewall/vendor-account
  introduced; the skill reads Doppler read-only and runs no `terraform`.
- **Community/functional-overlap:** first-party skill, no uncovered stack;
  `soleur:provision-cloudflare` is adjacent but mints tenant tokens (distinct function).

## Skill-description budget

Proposed `description:` (third person, routing-only, ~34 words):

> This skill should be used to widen an existing Cloudflare API token's scope via
> Playwright dashboard automation, then run the ADR-130 retained-scope probe set verifying
> the target scope was added and none was dropped.

Confirm the exact word count with `desc.split(/\s+/).filter(Boolean).length` and bump
`SKILL_DESCRIPTION_WORD_BUDGET` (`components.test.ts:16`, currently `2366`, zero headroom)
by that count with the justification comment. Keep the description ≤ 1024 chars.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this plan fills it (threshold `single-user incident`, `requires_cpo_signoff`).
- **The probe must satisfy the cited fail-closed learning in FULL, not just cite it:**
  capture the body (never `-o /dev/null`) and assert `success==true` + `.result` is an
  array on 200; never key on `.result | length` (reads `null` as `0`); add the per-scheme
  control (account `404` = FAIL; zone `404` trusted only under an authorized zone control).
- **The canonical four-probe set is a canary for the whole-list REPLACE failure mode, not
  exhaustive coverage.** A dashboard save that replaces (not appends) drops *all* scopes at
  once → all four catch it. It does NOT probe Zone WAF (`firewall_custom`), Transform Rules
  (`response_headers_transform`), or account Filter Lists — a *surgical* single-permission
  drop can pass. Documented as a known boundary; extend the entrypoint set if a future
  threat model needs per-permission coverage.
- Editing token permissions does **not** rotate the token value; do NOT add a Doppler
  write or dependent-infra re-run to the widen flow.
- **The widen transits a full-power CF dashboard session** (session cookie = account-wide
  bearer). No `browser_network_requests`/`browser_console_messages` dumps to files;
  edit-control-scoped screenshots; snapshot-only navigation.
- Never print the Bearer token; pass it from a **private fd** (not `-H "…$TOK"` → keeps it
  out of argv); no `set -x`; `--dry-run` leaves the token unexpanded; no Playwright
  `browser_evaluate` value read with a `filename`. The no-leak test greps combined `2>&1`.
- The scope-ledger (`variables.tf` description of the widened token) MUST be updated with
  the new permission in the feature PR that consumes the widen — ADR-130 consequence.

## References & Research

### Internal
- ADR-130 (widen-vs-narrow-alias, the four-probe set, capability gap): `knowledge-base/engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md`
- ADR-136 (pre-apply entrypoint-enumeration gate): `knowledge-base/engineering/architecture/decisions/ADR-136-preapply-entrypoint-enumeration-gate.md`
- Scope ledger: `apps/web-platform/infra/variables.tf:224` (`cf_api_token_rulesets`), `:285`–`:288` (operator-minted, no `User API Tokens:Edit`)
- Provider aliases: `apps/web-platform/infra/main.tf:96`–`:158`
- Conventions: `plugins/soleur/skills/provision-cloudflare/SKILL.md`, `plugins/soleur/skills/admin-ip-refresh/SKILL.md`, `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` (Doppler read + dry-run), `plugins/soleur/skills/flag-set-role/` (ack + exit codes)
- Budget gate: `plugins/soleur/test/components.test.ts:16` + `:148`
- Learnings: `2026-03-21-cloudflare-api-token-permission-editing.md` (Playwright widen path), `2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md` (control probe), `2026-07-23-live-api-fail-closed-guard...md` (fail-closed classifier), `2026-05-18-vendor-token-mint...md` (no-filename value read), `2026-06-02-playwright-mcp-local-auth-dashboard-verification.md`
- C4: `knowledge-base/engineering/architecture/diagrams/model.c4:234`, `:424`; `views.c4:14`, `:36`

### Related work
- Issue: #6755 (this) — close on merge via `Closes #6755`
- Precedent PRs/issues: #6746 (Config Rules 403 incident), #5092 (rulesets widen), #6767/ADR-136 (pre-apply gate), #992 (CF token Playwright edit)
