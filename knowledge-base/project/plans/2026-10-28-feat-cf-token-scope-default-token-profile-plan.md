---
title: "feat: cf-token-scope — default-token profile in the ADR-130 retained-scope probe set"
type: feat
date: 2026-10-28
slug: cf-token-scope-default-token-profile
branch: feat-one-shot-11181-cf-token-scope-default-profile
issue: 11181
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat: cf-token-scope — default-token profile in the ADR-130 retained-scope probe set

## Enhancement Summary

**Deepened on:** 2026-10-28
**Sections enhanced:** 6 (`Research Insights`, `Proposed Solution`/`Technical Approach` + verdict vocabulary + classifier contract, `Scope Check`, `Observability`, `Guard Contract`, `Test Scenarios`)
**Research/agents used:** repo-research (script, SKILL.md, test baseline, infra consumers), learnings-researcher (3 cited learnings), premise validation via read-only `gh api`/`gh issue view`, Cloudflare API-reference verification (2 searches), precedent-diff sweep, verify-the-negative grep pass — **executed inline at depth 1 on OpenCode; `Reviewed-Coverage: sequential-fallback`** (no fan-out ran; no advisor consult ran — plan Step 4.5 deferred to the parent session, items recorded in `specs/feat-one-shot-11181-cf-token-scope-default-profile/decision-challenges.md`).

1. **Verdict-vocabulary normative table + classifier pseudocode** added (exact strings the D-series asserts; neutrality minted at one site — Guard 2's Assembly claim is now checkable).
2. **Precedent-diff gate (deepen 4.4) run**: the profile-table mechanism has one near-precedent (`agent-browser/scripts/playwright-mcp-profile-slot.sh` — a *browser* profile slot table, different concept) and the per-profile Doppler config has precedent (`operator-digest/scripts/provision-operator-digest-repo.sh:24` config-from-env pattern). Verdict recorded under Dependencies & Risks; **vocabulary hedge**: "profile" in this plan means *named token-probe configuration* — NOT the Playwright persistent browser profile the widen-playbook also calls a "profile".
3. **Verify-the-negative pass (deepen 4.45.1)**, greps measured against the SUT at HEAD: "no `-X` curl verb anywhere" → 0 hits (6 curl sites, all GET-default); "no Doppler write verb" → 0 hits; "secret reaches only `$TOK`" → single `printf '%s' "$val"` acquisition site (line 154) + `cleanup()` unset trap; "dry-run precedes the prerequisite loop" → lines 122 < 140, confirmed — all negative claims **confirm**, none contradicted.
4. **PAT-shaped-variable halt (deepen 4.8) reconciled**: the halt regex fires on ANY `var.<name>_token` citation; every hit in this plan was the pre-existing **Cloudflare** TF variable (the gate's target is GitHub PATs per #4144; `hr-github-app-auth-not-pat` is not-applicable here). Citations reworded to the declaration form `cf_api_token` / `variables.tf:79`; no new variable is introduced by this plan. Recorded here rather than silently edited.
5. **Deepen 4.10 Encryption Posture: skip justified** — no `.tf` edit (detection regexes unmet); the "connection" is the pre-existing `api.cloudflare.com` HTTPS surface already probed by the script (TLS 1.2+ enforced by curl default against the public CA bundle; env-var trust-store subversion already closed by the script's `unset` block, #7873). **4.13 Task Design: skip** — no new autonomous-task surface (operator-triggered script only).

## Overview

Add a named profile to the `cf-token-scope` probe script so the ADR-130
retained-scope re-check can cover the production default Cloudflare token
(`CF_API_TOKEN`, the default `cloudflare` provider alias), not only
`CF_API_TOKEN_RULESETS`. The existing rulesets probing stays the default — no
operator-visible change for current usage. The new profile probes the default
token's ledgered abilities (Tunnel, Access, DNS on zone `soleur.ai`,
Notifications) with non-mutating GETs, plus two Load Balancer readiness probes
(account pools list, zone load-balancer list) whose exit semantics are defined
explicitly: a 403 in a pre-widen baseline run reports `not-yet-widened`
(exit-neutral), while a post-widen target run must see them green or fail.

This is the safety-check work the CTO ruling on epic #11181 made the binding
precondition of the token widen; the widen itself remains an operator-typed act
and is out of scope here.

## Research Insights

**Premise Validation (plan Phase 0.6, 2026-10-28, all checks read-only):**

- `#11181` — `gh issue view` state `OPEN`, title "Epic: ADR-068 Phase-3 GA blockers (multi-host /workspaces) — non-cutover track", labels `priority/p2-medium`, `type/chore`, `domain/engineering`. Premise holds; this plan is one queued slice, so **the epic is not closed by this PR** (no `closes:` key).
- The CTO ruling comment cited as "comment 6464031261" — the comment itself **exists** (`<!-- non-cutover-track status: cto-hold-classification -->`, created 2026-10-28T08:13:21Z, permalink `https://github.com/jikig-ai/soleur/issues/11181#issuecomment-6464031261`); the bare `database_id` renders `null` through this environment's `gh api --jq` (display quirk, measured across all 9 comments — cite the permalink anchor, not the id). The ruling text matches the brief verbatim: widen `CF_API_TOKEN` once to Zone `soleur.ai` → `Load Balancers: Edit` AND Account → `Load Balancing: Monitors and Pools: Edit`; binding precondition = the retained-scope re-check must cover **this** token; dissent = probe hardcoded to `CF_API_TOKEN_RULESETS` until this extension lands.
- The follow-up comment (2026-10-28T08:17:06Z, operator answers) confirms: "queue the safety-check work first… the operator then runs `cf-token-scope` against `CF_API_TOKEN`… The [default-token] scope-ledger description edit follows *after* the widen lands". Consistent with this plan's out-of-scope list.
- Collision pre-check: `gh pr list --state open --search "11181"` → only **#11383** (`WIP: feat-one-shot-11181-cf-token-scope-default-profile`), this pipeline's own WIP stub PR (two empty `chore: initialize` commits, no files). No foreign in-flight work on these files.
- ADR corpus grep (`knowledge-base/engineering/architecture/decisions/` for `retained-scope|token probe`): only **ADR-130** hits. ADR-130's rejected alternatives concern widen-vs-narrow-alias for the *rulesets* token, not the probe script's token binding. The named-profile mechanism is nowhere rejected; it is the CTO ruling's own named remedy ("a small `cf-token-scope` probe-profile extension").
- Mechanism check (Phase 0.6b, step 2 — grepped the authority `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`): the script has **no** profile/secret-selection mechanism today (`TOKEN_SECRET="CF_API_TOKEN_RULESETS"` hardcoded at line 64, verified at this worktree's HEAD). The brief's capability claim holds; nothing existing covers P1 below.

**Property List (Phase 0.6b):**

- **P1** — The retained-scope re-check can run against the production default token (`CF_API_TOKEN` in Doppler `soleur/prd_terraform`) without opening an arbitrary-token-probing surface.
- **P2** — A no-flag invocation behaves exactly as today: same token, same ADR-130 probe set, same verdict lines, same exit codes (backward compatible; operator muscle memory and `widen-playbook.md` step text keep working).
- **P3** — LB readiness against the default token is reported **explicitly** before the widen without failing the baseline run, and is a hard gate after the widen when the operator declares the target run.
- **P4** — The script stays strictly read-only and never prints the token (fd-private Bearer header, `--dry-run` unexpanded, xtrace refusal at exit 78).
- **P5** — The probe set is table-driven so a future ledger ability is added by appending a row, not by editing the classifier.

**Cut List (Phase 0.6b, step 3):**

- Raw `--token-var` / `--secret-name` knob → buys P1 → **cut**: the ruled profile mechanism (SKILL.md §Usage already refuses it by design — "a `--token-var` knob pointed elsewhere would run the wrong URLs against the wrong token"; profiles-only posture is preserved and re-worded).
- A `/user/tokens/verify` probe row → partial P3 → **cut**: the playbook's "After the widen" step 2 already prescribes verify interactively; the script's contract is scope probing, not token-status probing (no duplication).
- Separate exit code (e.g. `4`) for `not-yet-widened` → P3 → **cut, recorded as a pending row**: a distinct *reported state* plus exit-neutral baseline satisfies the ask without growing SKILL.md's published exit-code contract. See decision-challenges D4.
- Write-attesting probes (a no-op POST/PUT to prove `:Edit`) → P3 → **cut**: mutates; violates P4. The existing Sharp-Edge "GET attests read, not `:Edit`" carries over to the LB probes, and the widen flow keeps the visual Edit-vs-Read confirmation.

**Local research (Phase 1, executed inline at depth 1 — `Reviewed-Coverage: sequential-fallback`):**

- **Repo patterns:** `scripts/cf-token-scope.sh` (253 lines): xtrace guard (`$-` case, exit 78), curl-env sanitization (`unset SSLKEYLOGFILE …`), three-layer classifier in `check()` (line 179) + `authorized_body()` (line 169, `jq -e` `success==true AND .result|type==$t`), `trust404_for()` (verified-phase-only 404 trust), zone-control-first ordering (lines 210-214), private-fd header `-H @<(printf 'Authorization: Bearer %s' "$TOK")`, `--dry-run` block (lines 122-137) that **exits before the prerequisite check** (so dry-run needs no `curl`/`doppler`), stdout-as-data-channel verdict lines, `cleanup()` trap unsetting `TOK ZONE ACCT`.
- **Default-token ledger abilities** (`apps/web-platform/infra/variables.tf:79-82`, `cf_api_token` description): "Cloudflare API token (Tunnel, Access, DNS, Notifications permissions)". Consuming resources on the default provider alias (no `provider =` line): `tunnel.tf` (`cloudflare_zero_trust_tunnel_cloudflared*`, `cloudflare_zero_trust_access_*`, `cloudflare_notification_policy`), `dns.tf` (all `cloudflare_record.*` on zone soleur.ai), `cloudflare-lb.tf` (monitor + pool = `account_id`, LB = `zone_id`). A workflow already reads the same secret pair read-only from the same config: `.github/workflows/scheduled-inngest-health.yml:1298` (`doppler secrets get CF_API_TOKEN --project soleur --config prd_terraform --plain` + `CF_ACCOUNT_ID`) — confirming `CF_API_TOKEN` exists in `prd_terraform`.
- **LB endpoints verified against the official Cloudflare API reference (2026-10-28, CLI-verification gate):** `GET /accounts/{account_id}/load_balancers/pools` — accepted permissions `Load Balancing: Monitors and Pools Write|Read` (developers.cloudflare.com/api/resources/load_balancers/subresources/pools/methods/list); `GET /zones/{zone_id}/load_balancers` — `Load Balancers … Write|Read`, account/zone variants mutually exclusive (developers.cloudflare.com/api/resources/load_balancers/methods/list). Each returns `{"success":true,"result":[…]}` (array) — matches the ruling's two permissions one probe each. The other four retained endpoints: `GET /accounts/{id}/cfd_tunnel`, `GET /accounts/{id}/access/apps`, `GET /accounts/{id}/notification_policies` (account scheme), `GET /zones/{id}/dns_records` (zone scheme) — all list GETs returning `result` arrays; `?per_page=1` bounds the body.
- **Test baseline:** `plugins/soleur/test/cf-token-scope.test.sh` — 41 assertions (C1–C14), accumulate-then-exit, mock `curl`+`doppler` on a scratch PATH with real `jq`, URL-substring spec dispatch, measured green at this worktree HEAD (`41 passed, 0 failed`, rc 0). Auto-registered in CI via `scripts/test-all.sh` `SUITE_GLOBS` entry `plugins/soleur/test/*.test.sh` — **no runner change needed**. Follows `test/test-helpers.sh` conventions where applicable (tripwire prelude matters only for suites that spawn `git`; this suite spawns none — the existing file does not source the helpers and stays that way).
- **Callers of the script:** `SKILL.md`, `references/widen-playbook.md`, the test, and archived KB records only. Interface additions (not changes) keep all of them valid.
- **Learnings to honor** (`knowledge-base/project/learnings/`): `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md` (the three-layer classifier — reuse `check()`, do not weaken it); `2026-03-21-cloudflare-api-token-permission-editing.md` (permission edits don't rotate the value → no Doppler write); `2026-04-15-plan-skill-reconcile-spec-vs-codebase.md` (reconciliation section below); AGENTS.md `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only` (mocks only — no real Doppler/CF calls in tests), `hr-verify-repo-capability-claim-before-assert`.

**Skill description budget (Phase 1.8):** the only candidate `description:` edit (SKILL.md frontmatter) was **dropped** — the current description remains accurate. Even as a candidate it is budget-neutral: `cf-token-scope/SKILL.md:4` carries `disable-model-invocation: true`, and `plugins/soleur/test/components.test.ts` (authority, `SKILL_DESCRIPTION_WORD_BUDGET = 2436`) counts model-visible descriptions only (ADR-236, #8290 batch that moved this skill out of the count).

**Conventions (CLAUDE.md / plugin AGENTS.md):** flat skills; references/scripts linked as markdown (no bare backtick paths); imperative voice; no version keys; commit-on-branch, PR body needs `## Changelog` (ship handles labels); `wg-kb-artifacts-archived-in-pr`.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified 2026-10-28) | Plan response |
|---|---|---|
| "SKILL.md's Sharp Edges deliberately refuse a raw --token-var knob" | The knob refusal sits in **§Usage** (SKILL.md:64-68), not §Sharp Edges; Sharp Edges carries the ledger + never-print + canary edges | Reconcile **§Usage** (profiles-only wording) and add one matching Sharp-Edges bullet; the posture itself is unchanged |
| "probe script hardcodes TOKEN_SECRET at line 64" | Holds — `TOKEN_SECRET="CF_API_TOKEN_RULESETS"` at line 64 | Profile table replaces the single constant |
| "the script already has a probe helper around line 182" | Holds — `check()` at 179-202, `authorized_body()` at 169-171 | Reuse both; generalize the expected-`.result`-type parameter (see below) |
| "default-token (`cf_api_token`) description ~line 79-82 lists Tunnel, Access, DNS, Notifications" | Holds — `variables.tf:79-82` exactly that string | Probe set mirrors those four abilities + the two LB readiness rows |
| "cloudflare-lb.tf resources use zone_id" | Half holds — `cloudflare_load_balancer.app` uses `zone_id` (`cloudflare-lb.tf:59`); monitor + pool are **account**-scoped (`account_id`, lines 19, 36) | LB readiness = account pools probe + zone load_balancers probe (one per granted permission surface) |
| "tests: cf-token-scope.test.sh exists and is the baseline" | Holds — 41/41 green, measured | Extend (D-series), never replace; C1–C14 are the back-compat pin |
| ruling "recorded on epic comment 6464031261" | Comment present at that permalink; the numeric id itself is not renderable via this env's `gh api` jq (null `database_id`) | Cite the permalink anchor; substance matches the brief verbatim |

## Proposed Solution

Keep the script's single shape — read a secret from Doppler, run `check()` over a probe list, print verdict lines, exit — and make the **probe list and token binding table-driven per named profile**:

1. **Two profiles.** `rulesets` (default, unchanged behavior) and `default-token` (new). A profile row = Doppler secret name + probe rows. `DOPPLER_PROJECT=soleur`, `DOPPLER_CONFIG=prd_terraform`, and `CF_ZONE_ID`/`CF_ACCOUNT_ID` are shared across profiles today (the table still models per-profile secret names so a future profile on a different config is a row edit — P5).
2. **`--profile <rulesets|default-token>`** flag, defaulting to `rulesets` (P2). **`--target-entrypoint`** stays rulesets-only; **`--expect-lb-scopes`** is the default-token assert-mode analog (P3). Mismatches are usage errors (exit 2).
3. **Probe classes.** Rows are `retained` (regression ⇒ hard fail) or `target` (LB readiness; exit semantics mode-dependent). The classifier (`check()`) is reused unchanged in behavior; its second parameter becomes an explicit expected `.result` type (`object|array`) instead of a `zone|account` scheme label — today's scheme→type map is preserved exactly at the rulesets call sites.
4. **Read-only posture untouched** (P4): same private-fd header recipe, same xtrace refusal, `--dry-run` prints the per-profile plan with `$TOK` unexpanded, no Doppler write verbs, no terraform (C10 source-guards keep passing; tests add their dry-run pins per profile).

## Technical Approach

### Profile table (script shape)

```bash
# cf-token-scope.sh — profile table (illustrative final shape)
PROFILES=(rulesets default-token)
PROFILE="rulesets"                       # default: today's behavior, unchanged

profile_token_secret() {                 # the ONLY token binding
  case "$1" in
    rulesets)       printf '%s' "CF_API_TOKEN_RULESETS" ;;
    default-token)  printf '%s' "CF_API_TOKEN" ;;
  esac
}
```

Probe rows are pipe-joined strings `class|label|url|want_type|trust404` built at
runtime from `$API`, `$ZONE`, `$ACCT` (secrets `CF_ZONE_ID`/`CF_ACCOUNT_ID` shared,
same config). `class ∈ {retained,target}`; `want_type ∈ {object,array}`;
`trust404` stays 1 **only** for `http_config_settings` (ADR-130's empirically
verified phase) — every default-token row is `trust404=0`, fail-closed.

### Probe sets (exact endpoints + curl shapes)

**Profile `rulesets` (default) — unchanged, retained-only:**

| # | label | GET URL | want_type | trust404 |
|---|---|---|---|---|
| R0 | `http_request_dynamic_redirect` (zone control, probed first) | `$API/zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint` | object | 0 |
| R1 | `http_config_settings` | `$API/zones/$ZONE/rulesets/phases/http_config_settings/entrypoint` | object | 1 |
| R2 | `http_request_cache_settings` | `$API/zones/$ZONE/rulesets/phases/http_request_cache_settings/entrypoint` | object | 0 |
| R3 | `http_request_firewall_custom` | `$API/zones/$ZONE/rulesets/phases/http_request_firewall_custom/entrypoint` | object | 0 |
| R4 | `accounts/<acct>/rulesets` (account-scheme control) | `$API/accounts/$ACCT/rulesets` | array | 0 |
| T | `target: <phase>` (only with `--target-entrypoint`) | `$API/zones/$ZONE/rulesets/phases/<phase>/entrypoint` | object | `trust404_for(phase)` |

**Profile `default-token` — new.** Retained rows = the `cf_api_token` ledger
abilities; target rows = the two LB readiness probes (one per granted permission
surface of the ruling):

| # | class | label | GET URL | want_type | attests |
|---|---|---|---|---|---|
| D0 | retained | `accounts/<acct>/cfd_tunnel` | `$API/accounts/$ACCT/cfd_tunnel?per_page=1` | array | Tunnel (ledger) |
| D1 | retained | `accounts/<acct>/access/apps` | `$API/accounts/$ACCT/access/apps?per_page=1` | array | Access (ledger) |
| D2 | retained | `zones/<zone>/dns_records` | `$API/zones/$ZONE/dns_records?per_page=1` | array | DNS, zone soleur.ai (ledger) |
| D3 | retained | `accounts/<acct>/notification_policies` | `$API/accounts/$ACCT/notification_policies?per_page=1` | array | Notifications (ledger) |
| L0 | target | `accounts/<acct>/lb/pools` | `$API/accounts/$ACCT/load_balancers/pools?per_page=1` | array | Account "Monitors and Pools: Edit" (read half) |
| L1 | target | `zones/<zone>/load_balancers` | `$API/zones/$ZONE/load_balancers?per_page=1` | array | Zone soleur.ai "Load Balancers: Edit" (read half) |

Every probe keeps the established recipe, byte-shaped from the existing helper:
`curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -H @<(printf 'Authorization: Bearer %s' "$TOK") "$URL"`
with the three-layer classifier (status → body-shape `jq -e '.success == true and (.result | type == $t)'` → per-scheme control). No probe writes; no POST/PUT anywhere.

`default-token` has no zone-rulesets control, so the `trust404` machinery is moot there (all rows fail-closed on 404, per-scheme rule unchanged).

### Exit-code contract (normative)

| rc | rulesets profile | default-token profile |
|---|---|---|
| 0 | every retained row authorized (or trusted-404 under authorized control) — **and** `--target-entrypoint` present, if given (today's semantics, unchanged) | every retained row (D0–D3) authorized; target rows (L0/L1) authorized **or** reported `not-yet-widened` (baseline), **or** authorized with `--expect-lb-scopes` (assert mode) |
| 2 | unchanged: usage error, missing binary, absent/empty Doppler secret | plus: unknown profile name; `--profile default-token --target-entrypoint …`; `--profile rulesets --expect-lb-scopes` |
| 3 | unchanged: retained drop/degrade/deny; denied target | any retained (D0–D3) drop/degrade/deny; **baseline:** an L0/L1 anomaly that is NOT a clean 403 (404, degraded 200, 5xx, 000, empty) — fail-closed, not excused as missing-scope; **assert mode:** any L0/L1 still 403 or anomalous ⇒ `FAIL: LB scope still absent` |
| 78 | unchanged xtrace refusal | unchanged |

Expected-missing state (baseline, target class only): HTTP **403** ⇒ verdict
`not-yet-widened (403)` on the row (body-parsed `errors[0].code` appended when it
parses — e.g. `(403, err 10000)`) ⇒ **exit-neutral**. When at least one target
row is not-yet-widened and everything else passed, the run prints after the
retained PASS line:

```text
NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it
```

Assert mode (`--expect-lb-scopes`) on green prints
`PASS: LB scopes present — confirm the 403->present transition against your pre-widen baseline`
(mirroring the existing target-scope-present line's present-not-added caveat —
one run cannot observe a transition). A baseline run where the LB rows are
already authorized prints `authorized (200)` normally (post-widen baseline reads
green — widening was idempotent-safe).

Existing stdout vocabulary (`PASS: no scope dropped`, `FAIL: retained-scope probe
failed …`, `denied (…)`, `degraded (…)`, `empty (…)`) is **not** renamed: the
stdout channel is a documented data channel (script STREAM CONTRACT comment;
#7797). New strings are additive only.

### Verdict vocabulary (normative strings the D-series asserts)

| State | Stream | Exact line shape |
|---|---|---|
| retained authorized | stdout row | `  <label>  authorized (200)` |
| retained degraded | stdout row | `  <label>  degraded (200 body not success/<want_type>)` |
| retained denied | stdout row | `  <label>  denied (<code>)` / `denied (404, unverified — fail-closed)` |
| trusted empty phase (rulesets only) | stdout row | `  <label>  empty (404, verified phase exists)` |
| **target, baseline, 403** | stdout row | `  <lb-label>  not-yet-widened (403)` — plus `, err <code>` suffix when `.errors[0].code` parses (e.g. `err 10000`) |
| **target, baseline, summary** | stdout after retained ledger | `NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it` |
| target, baseline, authorized | stdout row | `  <lb-label>  authorized (200)` (post-widen re-baseline reads green, no NOTE) |
| **target, assert, both green** | stdout | `PASS: LB scopes present — confirm the 403->present transition against your pre-widen baseline` |
| **target, assert, still missing** | stderr (mirrors the retained-FAIL channel choice) | `FAIL: LB scope still absent — the widen was not applied to CF_API_TOKEN`; stdout rows show `denied (403)` normally |

Row labels are the table labels above (`accounts/<acct>/cfd_tunnel`,
`accounts/<acct>/lb/pools`, `zones/<zone>/load_balancers`, …), formatted through
the existing `report()` helper (`%-42s`).

### Target-class classifier (pseudocode — one neutrality site)

```bash
# classify_target <label> — runs AFTER check() populated VERDICT + CODE.
# Neutrality is minted HERE and nowhere else (Guard 2 Assembly).
classify_target() {
  local label="$1"
  if [[ "$CHECK_RC" == "0" ]]; then report "$label" "$VERDICT"; LB_OK=$((LB_OK+1)); return; fi
  if [[ "$CODE" == "403" && "$LB_EXPECT" == "0" ]]; then
    local err; err="$(printf '%s' "$BODY" | jq -r '.errors[0].code // empty' 2>/dev/null || true)"
    report "$label" "not-yet-widened (403${err:+, err $err})"
    LB_NOTED=1; return                       # exit-neutral — ONLY baseline, ONLY 403
  fi
  FAILED=1; report "$label" "$VERDICT"       # 404/degraded/5xx/000/empty: both modes
  [[ "$LB_EXPECT" == "1" ]] && LB_MISSING=$((LB_MISSING+1))
}
```

Final lines: `FAILED=0 && LB_EXPECT=0 && LB_NOTED=1` ⇒ PASS line + NOTE line,
exit 0. `FAILED=0 && LB_EXPECT=1 && LB_OK==2` ⇒ present line, exit 0.
`FAILED=1` ⇒ existing `FAIL: retained-scope probe failed …` to stderr, exit 3;
in assert mode with `LB_MISSING>0` prepend `FAIL: LB scope still absent …`
(stderr). Retained-class rows never consult `classify_target` — a retained 403
stays `denied (403)` + FAILED, whatever the profile.

### argv parsing (back-compat preserving)

Extend the existing `while [[ $# -gt 0 ]]` loop, keeping arm shapes identical:

```bash
--profile <name>)            validate name ∈ PROFILES, else usage to stderr + exit 2
--expect-lb-scopes)          LB_EXPECT=1; shift        # default-token only
```

Post-parse cross-validation (before any Doppler read, so usage errors cost no
secret access):

```bash
[[ "$PROFILE" == rulesets && "$LB_EXPECT" == 1 ]] && exit 2 "…--expect-lb-scopes is a default-token profile flag"
[[ "$PROFILE" == default-token && -n "$TARGET" ]] && exit 2 "…--target-entrypoint is a rulesets profile flag"
```

No-flag argv = exactly today's behavior. Flag order irrelevant; each takes one
value; unknown args unchanged (`*)` arm).

### dry-run (the no-secrets test lever)

`--dry-run` stays before the prerequisite loop and prints, token unexpanded, per
the selected profile: the `doppler secrets get <profile token secret>` /
`CF_ZONE_ID` / `CF_ACCOUNT_ID` lines plus every probe URL of that profile
(retained + target rows). Implementors reuse the existing recipe-print loop.

### SKILL.md + playbook changes

- §Usage: add the two default-token example lines (baseline; post-widen), state the
  profile table (name → secret → probe set), re-word the hardcoding paragraph to
  "**profiles only, no raw token-var knob**" (same posture, now a mechanism):
  the script probes named profiles only; a `--token-var` knob pointed at an
  arbitrary secret would still run the wrong URLs against the wrong token and
  remains refused by design.
- §Probe-set contract: add the `default-token` table (D0–D3 retained + L0/L1
  target) and the expected-missing/assert-mode semantics; keep the three-layer
  classifier description (it is profile-independent).
- §Exit codes: extend the 0/2/3 rows with the target-class states.
- §Execution: the 3-step widen flow gets its default-token variant (baseline →
  operator-typed widen via the playbook → `--profile default-token --expect-lb-scopes`
  must go green).
- §Sharp Edges: adjust the ledger edge to name the follow-on (the
  `cf_api_token` description edit lands in the PR that *consummates* the
  widen, per the ruling); add: LB probes attest read reachability, not `:Edit`
  (same one-click Read-vs-Edit trap), and `not-yet-widened` is neutral **only**
  in baseline mode — the widen is not verified until an assert run exits 0.
- [widen-playbook.md](./references/widen-playbook.md) §After the widen: one pointer
  line — for the `CF_API_TOKEN` widen, step 1 becomes
  `cf-token-scope.sh --profile default-token --expect-lb-scopes`, and the two
  permission names to select are `Zone soleur.ai → Load Balancers: Edit` and
  `Account → Load Balancing: Monitors and Pools: Edit` (append, never rebuild).
- SKILL.md `description:` frontmatter: **unchanged** (budget note above). The
  generated `plugins/soleur/cursor/skills/soleur-cf-token-scope/SKILL.md` mirror
  is CI-managed and must NOT be hand-edited.

## Files to Edit / Create

**Edits (product):**

- `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` — profile table, argv arms + cross-validation, `want_type` generalization of `check()`, `default-token` probe loop (retained + target classes, classifier reused), expected-missing classifier arm, dry-run per-profile print, usage/help text.
- `plugins/soleur/skills/cf-token-scope/SKILL.md` — §Usage, §Probe-set contract, §Exit codes, §Execution, §Sharp Edges (profiles-only re-word), Related unchanged.
- `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md` — §After the widen pointer (two lines).
- `plugins/soleur/test/cf-token-scope.test.sh` — mock `doppler` gets a `CF_API_TOKEN` arm; mock `curl` gets URL-substring arms for the six new endpoints (**pools arm ordered before the zone-LB catch-all**, `*load_balancers/pools*` first); D-series cases; C1–C14 untouched.

**Creates:** this plan, `knowledge-base/project/specs/feat-one-shot-11181-cf-token-scope-default-profile/tasks.md`, `…/decision-challenges.md`.

**Deliberately NOT touched (hard out-of-scope, restated):** `apps/web-platform/infra/**` (incl. the `cf_api_token` ledger edit — a follow-on **after** the widen lands), the Playwright dashboard widen (operator-reserved hold), the cursor skills mirror, `.github/workflows/**`, `scripts/test-all.sh` (auto-glob already covers the suite).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Named-profile support in cf-token-scope.sh: a profile table mapping profile -> Doppler secret name (+ config if it differs) + probe set" | Technical Approach §Profile table + §Probe sets; script edit | mapped |
| 2 | "Existing rulesets probing stays the DEFAULT (backward compatible, no operator-visible change for current usage)" | `PROFILE="rulesets"` default; argv back-compat; C1–C14 pins; AC1 | mapped |
| 3 | "probe set covering its ledgered abilities — Tunnel, Access, DNS on zone soleur.ai, Notifications … using non-mutating GET endpoints" | rows D0–D3; P4 | mapped |
| 4 | "two LB readiness probes (account pools endpoint GET /accounts/$ACCT/load_balancers/pools and the zone load_balancers listing)" | rows L0/L1 | mapped |
| 5 | "must report an explicit expected-missing state (403/10000 => \"not-yet-widened\", exit-neutral in a pre-widen baseline run) rather than fail the whole run ambiguously — define the exit-code semantics in the plan precisely" | §Exit-code contract (normative table); Guard 2 | mapped |
| 6 | "Keep the script strictly read-only." | P4; C10 guards + D12 | mapped |
| 7 | "Update plugins/soleur/skills/cf-token-scope/SKILL.md: usage section, probe-set docs, the profile flag, and reconcile with the existing Sharp-Edges text (the knob refusal becomes \"profiles only, no raw token-var\")" + "The widen-playbook.md reference may need a pointer" | §SKILL.md + playbook changes | mapped |
| 8 | "Tests: extend plugins/soleur/test/cf-token-scope.test.sh … follow test/test-helpers.sh conventions and AGENTS.md test-fixture rules … NO real Doppler/CF calls … Write failing tests first (cq-write-failing-tests-before)" | Phase 1 (RED-first), Test Scenarios | mapped |
| 9 | "HARD OUT-OF-SCOPE (do not plan edits here): the dashboard widen itself; the scope-ledger description edit in … variables.tf; the generated … cursor … mirror; anything under apps/web-platform/infra/*.tf" | Files-deliberately-not-touched + Out-of-scope follow-ons | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `--profile` flag + `rulesets` default | "a profile table mapping profile -> Doppler secret name (+ config if it differs) + probe set. Existing rulesets probing stays the DEFAULT" | asked |
| `--expect-lb-scopes` assert mode | "--target-entrypoint style post-widen run = LB probes must turn green or fail" | asked (flag name invented — sub-decision D2/D4) |
| `want_type` parameter generalization | "mirror the existing probe recipe … the script already has a probe helper around line 182" | inferred — required to type `array` on zone-scheme list endpoints without touching the classifier's semantics; purely mechanical consequence of ask 1/3 |
| Cross-flag usage errors (exit 2) | "define the exit-code semantics in the plan precisely" | inferred — fail-closed on ambiguous argv; mechanical, priced into D9/D10 |
| `NOTE:` summary line + present-line wording | "report an explicit expected-missing state … rather than fail the whole run ambiguously" | asked (exact strings invented; additive to the stdout channel per the STREAM CONTRACT) |
| Playbook pointer edit | "The widen-playbook.md reference may need a pointer" | asked |
| Follow-on record (ledger edit) | "record the follow-up as a note/follow-on task, not as a file edit in this plan's diff" | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/skills/cf-token-scope/`, `plugins/soleur/test/` (+ planning artifacts under `knowledge-base/project/`)
- Planned files: 4 edits + 3 creates | Estimated changed lines: ~430 (script +~150/−30, test +~160, docs +~70, KB artifacts rest)
- Thresholds: >= 4 roots OR > 25 files OR > 800 lines — none crossed
- Recommendation: **single PR**

## User-Brand Impact

- **If this lands broken, the user experiences:** a false-green or stuck widen
  verification on the #11181 LB track — either the operator's post-widen re-check
  approves a token whose ruleset-adjacent behavior silently regressed (the
  original failure class: cache rules, WAF, redirects break for **all** site
  traffic at once), or the baseline run fails ambiguously and the widen stalls,
  delaying the ADR-068 GA LB overlay (app.soleur.ai stays on single-origin web-1
  longer than planned).
- **If this leaks, the user's workflow is exposed via:** the production default
  Terraform token value surfacing into a transcript/`ps`/log — vectors: inline
  `-H` header (token on argv), `--dry-run` expanding `$TOK`, shell xtrace — each
  already countered (private-fd header, unexpanded dry-run, exit-78 refusal) and
  re-pinned by D6/D12 plus the retained C8/C9 assertions.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the guard's job is detecting a
  whole-list REPLACE drop that degrades every Cloudflare-dependent concern for
  all traffic simultaneously — platform-wide degradation, not one user's
  incident; recorded as decision-challenge D6 for the parent to confirm.

> **Addendum — 2026-10-28 (user-impact review seat, PR #11383):** the first
> bullet's named symptom set (cache rules, WAF, redirects) is the
> `CF_API_TOKEN_RULESETS` drop-set; a `CF_API_TOKEN` REPLACE cannot touch it —
> separate tokens, and nothing in the default-token flow re-runs the rulesets
> profile. The artifact's REAL aggregate blast radius is **Tunnel, Access, DNS,
> Notifications dropped on `CF_API_TOKEN`**: app.soleur.ai DNS management and the
> origin tunnels behind it break at once. Two vectors this seat found carried
> only by skill-surface prose, now named here: (a) the Read-vs-Edit green gate —
> a REPLACE re-adding LB as Read-only reads assert-green (mitigation: SKILL.md
> §Sharp Edges visual-confirmation; write-attesting probes cut per plan scope);
> (b) the subscription-404 baseline stall — an un-subscribed LB add-on answers
> 404 and hard-fails the pre-widen baseline while the token is fine (ruled
> deliberate in D4; D5 pins it; flip-evidence named there). Threshold itself
> stands (D6 ruling): both symptom sets are platform-wide, aggregate-pattern.

## Observability

```yaml
liveness_signal:
  what:            "per-run verdict ledger of cf-token-scope.sh (PASS/FAIL/NOTE lines) — the deterministic retained-scope re-check for the #11181 widen flow"
  cadence:         "per-run: operator-invoked before/after the widen (SKILL.md §Execution), and every CI run via scripts/test-all.sh auto-glob"
  alert_target:    "operator terminal during the widen session; blocking CI suite failure for regressions"
  configured_in:   "plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh; registered by SUITE_GLOBS 'plugins/soleur/test/*.test.sh' in scripts/test-all.sh (no runner edit)"

error_reporting:
  destination:     "stdout data channel (documented PASS/FAIL/NOTE vocabulary) + stderr zone-control explanation; CI job log for the suite"
  fail_loud:       "exit 3 with 'FAIL: retained-scope probe failed — inspect the denied/degraded entrypoints above.'; exit 2 with usage on any ambiguous/mispaired argv"

failure_modes:
  - mode:          "default-token profile binds the wrong Doppler secret (profile table drift)"
    detection:     "D1 dry-run pins the literal 'secrets get CF_API_TOKEN' line and forbids the rulesets name in that run; Guard 1 row M1 reddens CI"
    alert_route:   "CI suite failure (blocking)"
  - mode:          "expected-missing classifier broadens until a denied/anomalous LB probe reads neutral (widen falsely green)"
    detection:     "Guard 2 rows M1/M2/M4 (D5, D7-equivalent mutations); suite red"
    alert_route:   "CI suite failure (blocking)"
  - mode:          "the real widen lands without the LB permissions"
    detection:     "assert-mode run exits 3 with 'FAIL: LB scope still absent' before any infra apply consumes the widened token"
    alert_route:   "operator terminal (fail-closed skill flow — SKILL.md §Execution step 3)"

logs:
  where:           "CI run log for the suite; local operator runs print to terminal — the script stores no state or logs"
  retention:       "CI artifact retention; nothing server-side (script is stateless and read-only)"

discoverability_test:
  command:         "bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh --profile default-token --dry-run"
  expected_output: "\"CF_API_TOKEN\" or \"load_balancers\""
```

Probe-verb gate: first token `bash` (allowlisted); dry-run exits before the
prerequisite loop, so it runs in the Check-10 sandbox (no HOME, no credentials)
well inside 15s; both expected tokens are literal substrings of the printed
recipes.

## Guard Contract

The deliverable extends an existing fail-closed guard (the retained-scope probe).
Two guards.

### Guard 1 — profile dispatch and token binding

**Property.** Every probe issued in a `--profile X` run authenticates with exactly the Doppler secret named by profile X, and the default (no `--profile`) run issues exactly the ADR-130 rulesets probe set with today's semantics.

**Assembly.** The single profile table — `PROFILES` + `profile_token_secret()` + the per-profile probe-row arrays — is the only chokepoint: `get_secret` receives the profile-resolved name (one acquisition site), the probe loops iterate the selected profile's rows (one dispatch site per class), and `--dry-run` prints **from the same table** the run consumes (print/run parity is part of the assembly — a second hand-maintained recipe list would be a second chokepoint; the current script's dry-run loop already reuses `ZONE_PHASES`, keep that pattern). Usage validation (unknown profile, flag/profile mismatch) sits at one post-parse gate before any secret read.

**Mutation matrix:**

| # | Mutation (edit to the SUT) | Expected |
|---|---|---|
| M1 | Bind `default-token` to `CF_API_TOKEN_RULESETS` in `profile_token_secret()` | RED — D1 asserts `secrets get CF_API_TOKEN ` literal and D1b forbids `CF_API_TOKEN_RULESETS` in that profile's dry-run |
| M2 | Make `--profile <unknown>` fall through to `rulesets` instead of exit 2 (the guard's own dispatch) | RED — D9 |
| M3 | Add a third profile row with an empty probe set (second-member drift) | RED — D11 asserts the dry-run retained-row count equals the profile's declared table size (parameterized, never a hard-coded 6) |
| M4 | Drop the account-scheme control row `R4` from the rulesets table | RED — the untouched C-series (C9 baseline) — proves back-compat of the pinned default profile |
| H1 | Harness: mock `curl` arm defaulting every LB URL to authorized | RED — D2 (not-yet-widened lines vanish; vacuous-harness detector) |
| H2 | Harness (must-PASS, non-canonical): `--profile default-token --dry-run` under the no-curl/no-doppler PATH bin (`NOCURLBIN`) | PASS — dry-run precedes the prerequisite loop; a suite that only passes with mocks present is over-fitted |

### Guard 2 — expected-missing classifier (LB readiness neutrality)

**Property.** A `target`-class probe reading HTTP 403 is exit-neutral **only** in baseline mode of the `default-token` profile; in assert mode a 403 is a hard failure, and every non-403 anomaly (404, degraded 200, wrong-shape 200, 5xx, 000, empty) is a hard failure in both modes.

**Assembly.** One classification function receives `(probe-class, mode-flag, check-verdict)` and is the sole place neutrality can be minted; both target rows (L0, L1) route through it — no per-row special-casing; the retained-class path never consults it (a retained 403 stays `denied (403)` → FAILED). The mode is set at exactly one argv gate (`--expect-lb-scopes`, validated against profile before use).

**Mutation matrix:**

| # | Mutation (edit to the SUT) | Expected |
|---|---|---|
| M1 | Widen the expected-missing arm to include 404 | RED — D5 (baseline LB 404 must exit 3) |
| M2 | Read the neutrality arm before the mode flag (assert mode behaves like baseline) — the guard's own dispatch | RED — D7 (assert-mode 403 must exit 3) |
| M3 | Special-case only the FIRST target row (L0 neutral on 403, L1 left failing) | RED — D2 asserts BOTH LB rows print `not-yet-widened` in the same baseline run (per-row assertions, not a count) |
| M4 | Treat a degraded 200 (`success:true,result:null`) on a target row as not-yet-widened | RED — new row: `MOCK_LB_POOLS='200:{"success":true,"result":null}'` baseline ⇒ exit 3 |
| H1 | Harness: assert helper accepts "at least one not-yet-widened line" instead of both labels | RED against M3 (the aggregate-vs-per-member trap the matrix's M3 exists to catch) |
| H2 | Harness (must-PASS, non-canonical): baseline where both LB rows are already `200` array (post-widen re-baseline) | PASS with exit 0 and no NOTE line — neutrality is for absence, not presence |

Both matrices are written from this design, before the implementation exists
(plan Phase 2.12 ordering rule); `python3 scripts/lint-guard-contract.py` over
this plan is a verification task in Phase 4.

**Guard Contract amendments — 2026-10-28 advisor consult (BINDING supersessions; not a third guard).**
Append per the dated-record doctrine; the matrix rows quoted below are superseded AS LITERATURE,
this block is what AC10 audits against:
- Guard 1 M4 detector: C3d/C4 (the account-scheme pins), NOT "C9 baseline" (C9 is the token-leak
  pin, insensitive to row deletion).
- Guard 1 H1 replaced: harness mutation = mock `doppler` answering ANY secret name with the same
  token; RED detector = the D2 binding pin (requested-name log must contain CF_API_TOKEN and never
  CF_API_TOKEN_RULESETS). The always-authorized-LB-mock row MOVED to Guard 2 as its H1 (it tests
  the neutrality property; RED detector D2's explicit per-row 403 mocks).
- Guard 1 M5 added: `profile_token_secret()` drops the `default-token` arm (empty binding) ⇒ RED —
  D1 rc + the empty-secret guard exit 2 naming the profile.
- Vocabulary table: the assert-mode row "still missing" emits `FAIL: LB scope still absent` on
  STDOUT (disposition 1, pinned by D6 via the stdout-only capture), NOT stderr.
- Vocabulary table gains the unlisted state: target row, baseline, NON-403 anomaly ⇒ retained-style
  verdict (`denied (<code>)` / `degraded (…)`) + exit 3 (D5, D4b; classifier third arm).
- Default-token probe table carries `trust404=0` per row (already true in prose and in SKILL.md's
  delivered table).
- Phase 1 step 2 RED-count: green-by-construction at HEAD were D9a-d (unknown-arg rc 2 pre-
  implementation), D12/D12b and the D2b/D7 default-mock rc shapes; genuine RED targets: D1, D1b,
  D1H, D2, D2c-assembly, D3, D4a/b, D5, D6, D7-assert-line, D8, D-mint, D10, D11, D-e, D-doc
  (recorded in the Phase-1 commit message).
- D0 is pre-Phase-2 evidence (rc 2 at HEAD), not a permanent suite assertion; the tasks.md
  maintenance step ran at each phase's end.
- Guard 2 M2 detector citation: the case that reddens when neutrality is read before the mode
  flag is **D6** (assert-mode 403 -> rc 3); D7 is assert-GREEN and cannot redden under M2.
  The Observability matrix's "D7-equivalent" phrasing reads as D6 likewise. (AC10 auditability.)
- Pseudocode block (`classify_target` sketch, summary-lines sketch): bare `return`, hardcoded
  `LB_OK==2`, and stderr placement there are superseded by addenda 4/3/1 — the CODE and the
  D-series follow the addenda; the sketch stays as written literature.

## Implementation Phases

Sequenced for `soleur:work` with `cq-write-failing-tests-before` (tests first).

### Phase 1 — Tests, RED-first

1. Extend `plugins/soleur/test/cf-token-scope.test.sh`:
   - mock `doppler`: add `CF_API_TOKEN) printf '%s' "${MOCK_API_TOKEN-default-token-xyz789}" ;;` arm (synthesized value only).
   - mock `curl`: add arms, in this order before the catch-all — `*cfd_tunnel*` (`MOCK_TUNNEL`), `*access/apps*` (`MOCK_ACCESS`), `*dns_records*` (`MOCK_DNS`), `*notification_policies*` (`MOCK_NOTIF`), `*load_balancers/pools*` (`MOCK_LB_POOLS`), `*load_balancers*` (`MOCK_LB_ZONE`) — default specs for the six: an `array` authorized shape `200:{"success":true,"result":[]}` (zone LB list returns an array too). The existing `*/rulesets)` exact-suffix arm and `*http_*` arms stay verbatim.
   - Add D-series cases D0–D13 (below), keeping the accumulate-then-exit style and file-based greps (no pipe+`grep -q` SIGPIPE flake).
2. Run the suite against the **unmodified** script; record the D-series RED count (D0 RED-by-construction pin; D1–D12 all fail; D13 = C-series must stay GREEN now and after).

### Phase 2 — Script

3. Profile table + `PROFILE` default + `profile_token_secret()`; resolve `TOKEN_SECRET="$(profile_token_secret "$PROFILE")"` where the constant was (line 64).
4. argv arms `--profile`, `--expect-lb-scopes`; post-parse cross-validation (exit 2 arms) **before** the dry-run block, so usage errors never print recipes for a mispaired run.
5. `check()` parameter generalization: second arg `want_type` (`object|array`) replaces `scheme` (internal 404-trust gate keeps reading `trust404` + zone-control state). Rulesets call sites pass exactly their old scheme-derived types; the trusted-404 condition for zone rows (`scheme == zone` part) is preserved by passing a `zone_flow` marker or keeping the `trust404`+`ZONE_CONTROL_OK` conjunction unchanged — the observable behavior for the C-series is what pins it.
6. Default-token probe loop: retained rows D0–D3 through `check()` (all `trust404=0`); target rows L0/L1 through the classifier arm of Guard 2 with mode from `LB_EXPECT`. Header line names the profile's secret (`probing CF_API_TOKEN …`). PASS/FAIL vocabulary additive-only.
7. Dry-run branch prints per-profile rows from the table; usage/help text updated (documents the profile flag, `--expect-lb-scopes`, and the exit-code contract rows).
8. `bash -n` + `shellcheck` (repo config) clean; run suite → D-series GREEN, C-series still GREEN.

### Phase 3 — Docs

9. SKILL.md edits per §SKILL.md + playbook changes above (keep reference-link format rules; imperative voice; no second person).
10. widen-playbook.md pointer lines.

### Phase 4 — Verification & artifacts

11. `timeout 120 bash plugins/soleur/test/cf-token-scope.test.sh` → `fail == 0`, rc 0.
12. `python3 scripts/lint-guard-contract.py <this plan>` → pass.
13. Manual read-only checks: `--profile default-token --dry-run` under `env PATH=/usr/bin:/bin` (no curl/doppler) → rc 0, six URLs + `"$TOK"` unexpanded, no token-like literal; confirm no diff touches `apps/web-platform/infra/**` or `plugins/soleur/cursor/**` (`git status` + diff-path census — AC11).
14. `bun test plugins/soleur/test/components.test.ts` → description budget untouched (no SKILL.md `description:` edit; skill is `disable-model-invocation`, ADR-236-exempt — verify suite still green, not just reason it).

## Acceptance Criteria

### Functional Requirements

- [ ] AC1 — Back-compat: with no `--profile` flag the script reads `CF_API_TOKEN_RULESETS`, probes the ADR-130 set (R0–R4 + optional `--target-entrypoint`), and the C1–C14 assertions pass unmodified (D13).
- [ ] AC2 — `--profile default-token` reads `CF_API_TOKEN` from `soleur/prd_terraform` and probes exactly rows D0–D3 (retained) + L0–L1 (target) via the shared three-layer classifier; `--dry-run` prints them from the same table (Guard 1 H2).
- [ ] AC3 — Baseline: L0/L1 `403` ⇒ per-row verdict `not-yet-widened (403…)` + summary `NOTE:` line, exit-neutral; all retained rows still hard-gate (D2, D3, D4, D5).
- [ ] AC4 — Assert mode `--expect-lb-scopes`: both LB rows must be authorized `200` (array shape) or exit 3 with `FAIL: LB scope still absent` and no `PASS: LB scopes present` line (D6, D7, D8).
- [ ] AC5 — Usage errors (exit 2, before any secret read): unknown profile; `default-token` + `--target-entrypoint`; `rulesets` + `--expect-lb-scopes` (D9).
- [ ] AC6 — Strict read-only + credential hygiene preserved on the new path: no Doppler write verb, no terraform, no `set -x`, private-fd header, dry-run unexpanded, real run never echoes the token (C10 extended with D12; D13 includes a C8/C9-equivalent default-token leak pin).
- [ ] AC7 — SKILL.md documents: profile flag + table, default-token probe set, `--expect-lb-scopes`, the exit-code contract with the `not-yet-widened` state, and the re-worded posture "profiles only, no raw token-var"; `widen-playbook.md` carries the post-widen pointer (D-SKILL grep pins, below).

### Non-Functional Requirements

- [ ] AC8 — Fail-closed: any non-403 anomaly (404, degraded 200, wrong-shape 200, 5xx, 000, empty) on a target row exits 3 in **both** modes; 404-trust remains exclusive to `http_config_settings` under its zone control (unchanged ADR-130 rule).
- [ ] AC9 — stdout vocabulary additive-only: existing `PASS:`/`FAIL:` strings and the xtrace refusal (exit 78) byte-identical.
- [ ] AC10 — Guard Contract above passes `python3 scripts/lint-guard-contract.py`, and every matrix row has a named assertion in the suite.

### Quality Gates

- [ ] AC11 — Diff census: changed paths ⊆ {`plugins/soleur/skills/cf-token-scope/**`, `plugins/soleur/test/cf-token-scope.test.sh`, `knowledge-base/project/{plans,specs}/**`}; **zero** hunks under `apps/web-platform/infra/` or `plugins/soleur/cursor/`.
- [ ] AC12 — Suite green via the CI auto-glob (`scripts/test-all.sh` discovers it without registration edits); RED-first evidence recorded in the PR's work log (Phase 1 D-series failure count).
- [ ] AC13 — No real Doppler/Cloudflare call in tests (mock bins only) — `cq-test-fixtures-synthesized-only`.

## Test Scenarios

Layer labels per plan-template convention; all `unit` (script-level, mocked externals).

**Acceptance tests (RED phase targets):**

- [D0 — RED-by-construction pin] Given the script at current HEAD, when run with `--profile default-token --dry-run`, then exit 2 (`unknown argument`) — recorded **before** Phase 2 so the pipeline's red→green transition is evidenced; after implementation the same argv exits 0 (superseded by D1, kept as a labeled meta-assertion).
- [D1] Given mock doppler serving `CF_API_TOKEN`, when `--profile default-token --dry-run`, then rc 0; stdout contains `doppler secrets get CF_API_TOKEN` and all six probe URLs (`cfd_tunnel`, `access/apps`, `dns_records`, `notification_policies`, `load_balancers/pools`, `zones/$ZONE/load_balancers`); contains unexpanded `"$TOK"` and the `printf 'Authorization: Bearer %s'` private-fd form; curl marker file absent.
- [D1b] Same run: stdout must **not** contain `CF_API_TOKEN_RULESETS` (binding pin, Guard 1 M1).
- [D2] Given all six endpoints mocked permissive (retained authorized arrays; LB rows `403:{"success":false,"errors":[{"code":10000}]}`), when `--profile default-token` (baseline), then rc 0; both LB labels print `not-yet-widened (403` (per-row, not "at least one"); stdout contains `PASS: no scope dropped` and the `NOTE:` line.
- [D3] Given `MOCK_TUNNEL='403:…'`, when baseline default-token run, then rc 3 and **no** `PASS: no scope dropped` — a retained capability drop is never excused by the neutrality arm.
- [D4] Given `MOCK_DNS='200:{"success":true,"result":null}'`, when baseline run, then rc 3 (degraded-200 layer holds on new endpoints); Given `MOCK_LB_POOLS='200:{"success":true,"result":{"id":"x"}}'` (wrong shape), then rc 3 (body-shape half, both classes).
- [D5] Given `MOCK_LB_ZONE='404:{"success":false}'`, when baseline run, then rc 3 (403 is the only expected-missing status; fail-closed on 404).
- [D6] Given LB mocks still 403, when `--profile default-token --expect-lb-scopes`, then rc 3; stdout contains `FAIL: LB scope still absent`; **lacks** `PASS: LB scopes present`.
- [D7] Given LB mocks authorized arrays, when `--expect-lb-scopes`, then rc 0 and `PASS: LB scopes present`.
- [D8] Given `MOCK_LB_POOLS` authorized but `MOCK_LB_ZONE` 403, when `--expect-lb-scopes`, then rc 3 (per-row gating; guards against first-member-only pass).
- [D9] Usage errors rc 2 before any Doppler read: `--profile bogus --dry-run`… (dry-run prints are allowed only for **valid** combos — implementation places cross-validation before the dry-run block, so assert rc 2); `--profile default-token --target-entrypoint http_config_settings`; `--profile rulesets --expect-lb-scopes`; `--profile` with no value.
- [D10] Given `--profile rulesets --dry-run`, then output identical (verdict-shape-wise) to today's no-flag dry-run (back-compat pin beyond C-series).
- [D11] Parameterized table-size pin: dry-run retained+target row count equals the declared rows for the selected profile (rulesets: 5 (+1 per `--target-entrypoint`); default-token: 6) — Guard 1 M3 / aggregate-floor defense.
- [D12] Source-guards extended: existing C10 anchors stay; add `src_lacks` for any `doppler` verb other than `get`/`secrets get` and for `-X POST|PUT|PATCH|DELETE` in curl args (read-only proof on the new code path).
- [D13] The whole C1–C14 block unmodified ⇒ rc 0 and `14+` ok-count — pins AC1/AC9 (run before and after Phase 2).
- [D-doc] grep pins on SKILL.md/playbook post-edit: `--profile default-token`, `--expect-lb-scopes`, `not-yet-widened`, and the literal phrase `profiles only` present; `--token-var` refusal sentence re-worded (no raw-knob affordance text added anywhere).

**Edge cases:**

- Given an empty `CF_API_TOKEN` in Doppler (mock returns `""`), when default-token run, then rc 2 with the absent-secret message naming `CF_API_TOKEN` (D-mint pin via `MOCK_API_TOKEN=''`).
- Given the xtrace case, behavior unchanged (exit 78; covered by existing structure — do not weaken the guard when re-sourcing).
- Given `--expect-lb-scopes --profile default-token --dry-run`, then rc 0 and rows printed once (flags are orthogonal; dry-run prints target rows regardless of mode).

**Integration verification (operator, post-merge — not part of this PR's tests, no secrets in CI):** pre-widen baseline `… --profile default-token` must exit 0 with two `not-yet-widened` rows (proves D0–D3 retained soundness on the live token before the dashboard act); post-widen `… --profile default-token --expect-lb-scopes` must exit 0 green. `credentials_required` declared in Observability is **absent** deliberately — the dry-run probe needs no credentials; the live-pair checks belong to the widen session's own flow per SKILL.md §Execution.

## Dependencies & Risks

**Precedent diff (deepen 4.4 — pattern-bound behaviors):**

| Behavior the plan prescribes | Repo precedent (grepped) | Diff |
|---|---|---|
| curl probe recipe (`--disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}'`, private-fd `-H @<(printf 'Authorization: Bearer %s' "$TOK")`) | `cf-token-scope.sh:182-186` (`check()`), echoed in `--dry-run` recipes (132-135) | **none** — new rows reuse `check()` verbatim; only the `want_type` arg generalizes |
| Body-shape assertion (`jq -e` success+typed `.result`) | `authorized_body()` at 169-171, pinned by C3/C3a/C3c/C3d | **none** — reused; array-typed on new endpoints (their documented CF shape) |
| Doppler read-only secret acquisition (`doppler secrets get … --plain`, empty⇒exit 2) | `get_secret()` 147-155 | **none** — parameterized by the profile name |
| URL-substring mock dispatch in a `.test.sh` | this suite's own mock `curl` (case arms, spec strings `CODE:BODY`) | additive arms; **ordering constraint**: `*load_balancers/pools*` before `*load_balancers*` (pools URL is a superstring) |
| Named-profile table in a plugin script | `agent-browser/scripts/playwright-mcp-profile-slot.sh` (browser-profile slot table — same *shape*, different concept) | novel for token binding; **no token-profile precedent exists** → reviewers should scrutinize the binding chokepoint (Guard 1) |
| Per-profile Doppler config override | `operator-digest/scripts/provision-operator-digest-repo.sh:24` (`DOPPLER_CONFIG="${…:-prd}"`) | not adopted now: both profiles read `prd_terraform`; the table row shape leaves room (P5) without a live second config |
| LB apply-side permission surface (why these two probes) | `cloudflare-lb.tf:15` comment ("Applied via apply-web-platform-infra.yml"), runbook `cf-lb-a-record-gaplessness-verify.md` | consistent: readiness = read halves of exactly the two granted Edit permissions |

- **Depends on:** `CF_API_TOKEN` present in Doppler `soleur/prd_terraform` (confirmed via the workflow precedent at `scheduled-inngest-health.yml:1298`); zone `soleur.ai` LB add-on subscription for L1's post-widen green path (approved and billed per `cloudflare-lb.tf:14`; a subscription-missing 404 fails closed, loudly — acceptable and diagnostic).
- **Risk — endpoint shape drift:** all six default-token endpoints return `result` arrays at list level; the mock mirrors CF shapes; AC8 keeps a wrong-shape 200 red even if shapes surprise.
- **Risk — GET attests Read, not Edit:** unchanged known limit; SKILL.md keeps the visual Edit confirmation edge; assert-mode green + dashboard read-back together gate the widen (playbook).
- **Risk — stdout-channel consumers:** additive-only strings (AC9); no renames of `PASS:`/`FAIL:` tokens.
- **Risk — CI budget:** suite adds ~25 mocked subprocess cases, <10s (measured pattern: existing 41 assertions run well under the timeout).
- **No blockers:** epic stays open; PR #11383 (the pipeline's WIP stub) carries nothing; no other open work touches these files (overlap check: None).

## Out of Scope & Follow-ons (ruled by the brief — record, do not implement)

1. **The widen act** — operator-typed `cf-token-scope` flow against `CF_API_TOKEN` (standing operator-reserved hold on #11181). This plan builds its precondition only.
2. **Scope-ledger edit** — appending the two LB permissions to the `cf_api_token` variable's description in `apps/web-platform/infra/variables.tf` **after** the widen lands, in the PR that consumes the widen (ADR-130 ledger rule + the operator-answer comment: "records only what is true"). Follow-on: note on the #11181 thread; not a file edit in this PR (AC11 enforces).
3. **Cursor mirror** — `plugins/soleur/cursor/skills/soleur-cf-token-scope/SKILL.md` is CI-generated from SKILL.md; never hand-edited.
4. **Part-2 staging-convert dispatch authorization** — the CTO comment flags that when the widen lands, the `apply-web-platform-infra.yml` dispatch "needs a fresh named authorization"; belongs to the cutover/LB-Part-2 slice, not here.
5. **ADR-130 amendment** — no new/changed architectural decision in this plan (Phase 2.10 detection: the widen decision is already ADR-130-conformant and recorded on the epic; this is a tooling extension of the probe that ADR-130's own capability-gap remediation (this skill) anticipated). A future engineer reading ADR-130 + SKILL.md is not misled about the system. A reviewer who disagrees may escalate to an ADR note — recorded as decision-challenge D5 (pending).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a read-only verification script for a credential-scope workflow). Product/UX: no user-facing surface (mechanical UI-surface scan over the file lists matches nothing); Marketing/Sales/Support: none; Finance: none; Legal/GDPR (Phase 2.7): no regulated-data surface, no new processing activity, no LLM-bound data, no distribution surface beyond the plugin's existing delivery (the probes return only the operator's own zone/account configuration presence — never customer data), and the credential handling is unchanged posture; Operations: the act itself remains operator-reserved and is not baked into any phase of this plan (Phase 2.8 routing gate: no new infrastructure, secret, host, or vendor surface is provisioned here — the plan edits a script, its tests, and skill docs).

## Open Code-Review Overlap

None — checked 2026-10-28 against `gh issue list --label code-review --state open --limit 200` (jq `contains()` on bodies) for all four planned edit paths (`scripts/cf-token-scope.sh`, `SKILL.md`, `cf-token-scope.test.sh`, `widen-playbook.md`): zero matches. (The check queried 0 open code-review issues at run time.)

## References & Research

- CTO ruling: #11181 comment — `https://github.com/jikig-ai/soleur/issues/11181#issuecomment-6464031261` (ruling + operator holds + dissent); operator answers comment 2026-10-28T08:17:06Z.
- [ADR-130](../../engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md) — widen-vs-narrow rule, retained-scope probe set, scope-ledger rule.
- [ADR-136](../../engineering/architecture/decisions/ADR-136-preapply-entrypoint-enumeration-gate.md) — pre-apply enumeration gate (unchanged; no new phase is enabled by this plan).
- Skill baseline: `plugins/soleur/skills/cf-token-scope/{SKILL.md,scripts/cf-token-scope.sh,references/widen-playbook.md}`; test baseline `plugins/soleur/test/cf-token-scope.test.sh` (41 assertions green at HEAD).
- Ledger source: `apps/web-platform/infra/variables.tf:79-82` (`cf_api_token`); consumers `main.tf:150-160` (default provider), `tunnel.tf`, `dns.tf`, `cloudflare-lb.tf:15-73`.
- Cloudflare API reference (verified 2026-10-28): [List Pools](https://developers.cloudflare.com/api/resources/load_balancers/subresources/pools/methods/list) · [List account or zone Load Balancers](https://developers.cloudflare.com/api/resources/load_balancers/methods/list) · tunnel/access/notification/DNS list endpoints (`/accounts/{id}/cfd_tunnel`, `/accounts/{id}/access/apps`, `/accounts/{id}/notification_policies`, `/zones/{id}/dns_records`).
- Learnings: `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md`; `2026-03-21-cloudflare-api-token-permission-editing.md`; `2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`.
- Plan-review advisor consult: **not run in this headless subagent run** (harness constraint) — recorded for the parent session; items pending at `knowledge-base/project/specs/feat-one-shot-11181-cf-token-scope-default-profile/decision-challenges.md` (D1–D7).

**Note (lane default):** spec.md absent for this branch at plan time — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Advisor Consult Dispositions (plan finalization, 2026-10-28 — BINDING amendments)

Scoped advisor consult (D7-routed; OpenCode harness: architecture-strategist on the session-inherited model, disclosed tier substitution; sequential-fallback coverage). **No TECHNICAL findings** — no follow-up CTO ruling batch was needed. TASTE/PROCESS findings adopted by the parent session; where an item below contradicts a section above, THIS section wins.

Verdict-channel and classifier semantics (override the Guard Contract table/pseudocode):
1. The assert-mode blocking verdict `FAIL: LB scope still absent` is emitted on **stdout**, not stderr (aligns the vocabulary table with Test Scenario D6 and the #7797 rationale: agent runtimes surface stdout and swallow stderr; the divergence from the retained-FAIL-on-stderr precedent is deliberate). Update the rc-3 table row and D6 to match.
2. Neutrality/`LB_MISSING` counting gates on `CODE == 403` exactly (per D4); degraded-200, wrong-shape, 5xx, 404, 000 produce hard FAIL rows naming the observed status, never the still-absent wording — the final classifier arm must not assert a cause it did not establish.
3. The assert-mode green condition compares `LB_OK` against the profile-declared target-row count (parameterized, never a hardcoded 2), per the D11 aggregate-floor discipline.
4. `classify_target` ends with an unconditional `return 0` (a trailing false `[[ ]]` test would abort the run mid-ledger under `set -euo pipefail`).
5. `check()` publishes `CODE`, `BODY`, `CHECK_RC` as globals in the same edit that generalizes `want_type` (verdict semantics stay byte-identical; confirm no C-pin depends on their locality). Failing `check()` calls at the probe loop use `if …; then/else` form under `set -e`.
6. `--profile` argv arms mirror the script's existing shapes: usage-error = `echo msg >&2; usage >&2; exit 2` (no `exit 2 "message"`), and `--profile` with a missing value exits 2 exactly like `--target-entrypoint` (D9 pins).
7. `profile_token_secret()` carries a fail-closed `*)` arm (unknown/undeclared profile ⇒ exit 2 naming the profile, not an empty variable); Guard 1 matrix gains a drift row: every `PROFILES` member resolves a non-empty secret.
8. The rulesets path keeps its own `--target-entrypoint`/TARGET_PRESENT handling and never calls `classify_target`; the `target` class vocabulary is default-token-local (add the one-line hedge next to the existing "profile" vocabulary hedge).
9. The trailing zone-control stderr block (script 249-251) is gated on `PROFILE == rulesets`; a default-token failure must not print a line naming a probe that never ran (pin: default-token failure case `lacks "zone control"`).
10. Implementation Phases step 5 names ONE mechanism: keep the existing `trust404`+`ZONE_CONTROL_OK` conjunction and pass `want_type` as an added `check()` parameter (no `scheme` replacement) — the C5a/C5b 404-trust exclusivity gate is untouched.

Test-scenario and matrix corrections (override Test Scenarios / Guard Contract as listed):
11. Guard 1 M4 re-cites detecting pins C3d/C4 (the account-scheme controls), not C9 (token-leak pin, insensitive to row deletion).
12. The always-authorized-LB-mock harness mutation moves to Guard 2 (it tests the neutrality property); Guard 1's harness row becomes a binding-shaped mutation (mock doppler answering any secret name ⇒ the misbound-profile pin still reddens).
13. Add one assert-mode degraded-200 case (verdict channel pinned) — Guard 2's "non-403 anomalies fail in BOTH modes" property currently has no assert-mode witness.
14. Vocabulary table gains the target-row baseline non-403 anomaly row (retained-style verdict strings; closes the AC9 additive-only gap for unlisted states); the default-token probe table gains the `trust404` column (0 in every row).
15. Phase 1 step 2's RED claim corrected: name which D-cases are green-by-construction (D12's source/doc greps; D13 already listed) versus the genuine RED targets — AC12 evidence must match the prediction.
16. Stream column of the vocabulary table is documentation-only UNLESS a stdout-only capture helper is added to the suite for the two channel-sensitive rows (finding 1 makes D6 channel-asserting; the suite's merged `2>&1` capture cannot otherwise distinguish). Either is acceptable; do not claim a pin that cannot run.
17. D0 is declared pre-Phase-2 evidence-log (same argv asserts rc 0 in D1; D0's rc-2 is the pre-extension observation, not a permanent assertion); Implementation Phases gains the missing tasks.md maintenance step; step 13's PATH claim reworded to the true reason rc stays 0 (dry-run exits before the prerequisite loop).
