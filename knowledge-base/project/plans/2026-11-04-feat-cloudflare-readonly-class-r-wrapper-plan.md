---
title: "feat: Cloudflare read-only wrapper for Class R live-read checks (#10479 A/B/C/E)"
date: 2026-11-04
slug: cloudflare-readonly-class-r-wrapper
branch: feat-one-shot-10479-cf-readonly-wrapper
issue: 10479
type: feat
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Overview

Give the CTO agent a repo wrapper that performs four read-only Cloudflare checks for the origin-TLS question on #10479 (zone SSL mode, the config-settings ruleset entrypoint, legacy page rules limited to SSL actions, and a bounded change-history read), so they run as Class R acts instead of being handed back as holds. The wrapper is the only Cloudflare reader that section 9 of the standing-delegation reference will allow; adding Cloudflare as a vendor also needs a CTO ruling (done, see Decisions) and a pin-test row.

This run ends at the draft pull request #12061, unarmed. No live Cloudflare call, no Doppler read, no credential mint, no workflow dispatch and no tracker edit is part of it. The spec had no `lane:` key (no brainstorm ran), so the lane defaulted to `cross-domain` (fail-closed).

Hard limits carried into every phase: draft only; do not mark ready, merge or arm; the PR body uses `Ref #10479` and `Ref #10205` only, and `closingIssuesReferences` is verified to be `[]` before any body is saved.

## Research Insights

### Premise validation (Phase 0.6)

- #10479 is OPEN. PR #12061 is an open draft with `closingIssuesReferences: []`. Merge commit f2e2ebd0e2 (the Class R change) resolves on this checkout. Comment 6610203058 was read in full: reads A, B, C, E are as described in the task; D is out of scope.
- Collision pre-check: the only open change naming #10479 is our own draft #12061; two foreign `test-all.sh` processes belong to unrelated worktrees (launch-check, suite-times). No duplicate work.
- The mechanism (a read wrapper under a Class R vendor ruling) is not in any ADR's rejected-alternatives table: ADR-289's 2026-11-03 addendum names Cloudflare as a Class R vendor but says no wrapper exists, and item 2 says the same. This plan fills that stated gap.

### Property list (Phase 0.6b)

1. The CTO agent can obtain, without the owner, the four live Cloudflare facts #10479 needs.
2. The credential never reaches the transcript, a command line, stdout, stderr or a child environment; it travels only on curl's stdin config.
3. The wrapper can send only a GET to four fixed URL templates on `api.cloudflare.com`; nothing in argv, env or a response selects method, host, path or query.
4. Output is a status, a count or a field subset; vendor text (rule expressions, descriptions, page-rule patterns) and personal data (audit actor, IP) never enter the transcript.
5. A token that lacks scope (403) is reported as `unverified` and never worked around.
6. Section 9, the CTO agent and the pin test agree on exactly this closed set, so Class R cannot widen silently.

### Cut list

| Mechanism considered | Property it would buy | Verdict |
|---|---|---|
| New runbook `cloudflare-read.md` | operator re-mint steps | Cut: section 9 plus the wrapper header carry the invocation; minting is owner-only and out of this run |
| Source `scripts/lib/bearer-curl.sh` (ADR-280) | one tested stdin-config implementation | Cut. Strong reason (CTO devex seat): the item 2 drift guard diffs only the wrapper against `origin/main`; a sourced root-level library would be a second file outside that guard and could change the wrapper's behavior. Cost accepted: a third copy of the credential-channel code, using the same form as `sentry-issue.sh` (`--config -` fed by a here-string / process substitution) and the same token alphabet `[A-Za-z0-9._~+/=-]` |
| Pagination loop on the audit log | complete window | Cut: one bounded page (50) and a single `truncated` flag |
| `--since-days N` option | adjustable window | Cut (plan review): fixed 7-day window, so no flag, no octal / unbound-`$2` parsing surface |
| `expression_sha256` | change detection | Cut (plan review): nothing consumes it; the two host booleans make the #10479 pass criterion decidable |
| mktemp body file, trap, `compgen -e` unset loop | body capture, env scrub | Cut (plan review): body is held in a shell variable via `-w`; the curl child is started as `env -i PATH="$PATH" LC_ALL=C curl ...`, which puts no secret on a command line because the token travels on stdin |
| Cloudflare error codes 9109 / 10000 in the status map | finer 403 split | Cut (plan review): unverified facts; map by HTTP status only |
| New Class R act (item 7) for Cloudflare | clarity | Cut: item 2 already covers "operator's own vendor accounts through repo wrappers"; the closed six-act count stays 6 |
| Reuse `cf-token-scope.sh` | a Cloudflare reader exists | Cut: it calls `doppler secrets get` (forbidden for agents), probes scope, and cannot project state |
| Cloudflare MCP server | a Cloudflare reader exists | Cut: open tool surface, OAuth writes; stays outside Class R |

### Institutional learnings applied

- Token on stdin config, never argv (`2026-02-18-token-env-var-not-cli-arg.md`, ADR-280, #7797 xtrace refusal).
- `doppler run` exports the whole config, so the curl child environment is empty by construction (`2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`).
- Guard every `jq` call and validate every 2xx body parses (`2026-03-09-shell-api-wrapper-hardening-patterns.md`); a 200 with `success:false` is an error, and `.result | length` reads `null` as 0.
- A 401/403 cannot distinguish "token lacks scope" from "resource missing"; report 403 as `unverified`, never "absent" (`2026-05-19-sentry-401-is-not-unowned-...`).
- Read the entrypoint via `/rulesets/phases/<phase>/entrypoint`; a 404 there means "phase exists, empty" only for the verified error code (ADR-130 #6746).
- Anchor the allow-list fully, with suffix / extra-segment refusal probes (`2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential.md`).
- Fixtures must include reordered, extra-field and wrong-type bodies; assert the wire (recorded URL, method, stdin), not only the output (`2026-07-19-a-mutation-battery-...`, `2026-07-27-my-battery-was-green-...`).
- A presence pin is not a boundary: pin each limit inside the item that owns it, closed sets by equality, polarity-bearing anchors (`2026-11-03-a-read-only-class-is-only-as-closed-as-its-per-item-pins-...`).
- Gap: no learning covers Cloudflare audit-log endpoints or `pagerules`; Phase 0 verifies them.

### Repo findings

- Models: `scripts/sentry-issue.sh` (pinned host, xtrace refusal, stdin config), `scripts/betterstack-query.sh` (TLS-env `unset` block, credential shape guard). Tests: `scripts/sentry-issue.test.sh` (PATH-prepended stub `curl` logging argv and stdin), `plugins/soleur/test/cf-token-scope.test.sh` (stub bin dir, curl marker, `src_has` / `src_lacks`).
- Lints that scan every tracked `.sh`: `scripts/lint-shell-trace-credential-refusal.py` (Rule A refusal in the prologue, Rule B no later `set -x`, Rule E no credential header or `-u` in curl argv), `scripts/lint-shell-capture-exit.py`, `scripts/lint-trap-tempfile-ownership.py`, and the fixture-relative-assert baseline.
- Test discovery: `scripts/test-all.sh` globs `plugins/soleur/test/*.test.sh`, so the new suite needs no edit under `scripts/`; `scripts/lint-orphan-test-suites.sh` checks registration.
- Distribution: everything under `plugins/soleur/` ships to plugin users. The wrapper is inert there by construction (it refuses unless `DOPPLER_PROJECT=soleur`, `DOPPLER_CONFIG=prd_terraform` and a bound token variable is present). Precedent: `cf-token-scope` ships with the same pins.
- Token names (names only, from repo text): `CF_API_TOKEN_ZONE_SETTINGS` (gh-pages-cert-renewal runbook), `CF_API_TOKEN_RULESETS` (ADR-130; Doppler `soleur` / `prd_terraform`), `CF_ZONE_ID`, `CF_ACCOUNT_ID`, `CF_API_TOKEN_AUDIT` ("dedicated read-only audit token", documented under Doppler `dev`, not `prd_terraform`).
- Class R text to change: item 2's last sentence ("No Cloudflare read wrapper exists ..."), item 4, the Credentials paragraph, the Boundary paragraph's "adding a vendor" clause. No edit needed in `go.md`, `operator-holds.md`, `delegation-verify.sh`, `AGENTS.rules.md`.

### CTO rulings and plan-review disposition

Technical rulings D1-D6 and the review-seat ruling D9 are rows of `knowledge-base/project/specs/feat-one-shot-10479-cf-readonly-wrapper/decision-challenges.md` (each `Ruled by CTO agent, 2026-11-04`). Plan review (code-simplicity per mechanism, DHH, Kieran, CTO devex seat) returned 4 high and about 12 medium or lower findings. Mechanical ones were applied in this revision (env -i, body in a variable, status-first exit map, empty-phase only on a verified code, jq type guards, anchored host booleans, stub/mutant ordering fixes, row arithmetic, reason vocabulary mapping); taste ones are rows D7, D8 and D10; the item 4 clause cut proposed by the simplicity seat was ruled against by the CTO (D9), with the dissent recorded.

## Research Reconciliation - Spec vs. Codebase

| Task / comment claim | Reality | Plan response |
|---|---|---|
| B is "projected to ref/enabled/description/expression/ssl" | Section 9 Boundary treats vendor text as data never quoted into a transcript; CTO ruled expression and description are not printed | Print `ref`, `enabled`, `ssl`, and two derived booleans `mentions_app_host` / `mentions_lb_staging_host` computed inside the wrapper; the pass criterion in comment 6610203058 ("expression names app and lb-staging") stays decidable. Owner-visible deviation, recorded in D4 |
| "Credential used only inside the wrapper; fails closed on unexpected token source" | The bound tokens for A/B/C are Terraform-scoped and write-capable (ADR-130); the Credentials paragraph says a write-capable token makes a read `unverified` | CTO ruling D3/D6: accept for the three named tokens only because no read-only equivalent exists and the wrapper hardcodes GET; state the exception plainly; the stricter option is recorded dissent |
| E uses "an audit-log-read token" | The only audit-named token (`CF_API_TOKEN_AUDIT`) is documented under Doppler `dev`, not the pinned `prd_terraform` | E reports `unverified - no-credential` when the variable is absent; no second Doppler config is added to Class R; the token's location is an owner-side fact, not in this run |
| C reads `/pagerules` with `CF_API_TOKEN_RULESETS` | The comment itself says whether that token can read `/pagerules` is unverified | Expected possible outcome is `unverified - token-lacks-scope` (exit 11); that is a valid result, never worked around |
| Item 4: "scripts/** is never pushed" | Literal glob is root-anchored; `plugins/soleur/scripts/` is a different tree | CTO D2/D9: add one clarifying clause, pinned by a test row; the push basis is the literal reading plus the ruling, not the unmerged clause |
| "Run the wrapper from a checkout matching origin/main" (item 2) | A new wrapper has no `origin/main` copy until merge | Not a defect: the live reads run after the owner arms and merges |

## Open Code-Review Overlap

One open scope-out names `plugins/soleur/scripts/` in its body: #11312 (monitor-pr-checks.sh hook-layer residue). Acknowledge: unrelated file and concern; it stays open. No other match for the files this plan edits or creates.

## User-Brand Impact

- **If this lands broken, the user experiences:** the CTO agent keeps handing the owner four technical Cloudflare reads as tasks (wrapper refuses wrongly), or reports a false "flexible" / "strict" / "no config rules" fact about the origin TLS mode that the owner then acts on; no Soleur end user sees anything directly.
- **If this leaks, the user's workflow is exposed via:** a Terraform-scoped Cloudflare API token (zone WAF, redirects, config rules edit) printed into an agent transcript, a command line or a child process environment, which would let a transcript reader change the production edge for every Soleur customer.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the wrapper is operator-side tooling that reads only the operator's own account, prints no customer data, and has the same exposure class as the existing Sentry and Better Stack wrappers; a leak is contained by the stdin-only channel, the empty curl environment and the xtrace refusal, so it does not rise to single-user (row D7).

Artifact / vector pairs for the review seat: (1) token printed on an error path, (2) token in argv or `ps`, (3) token inherited by the curl child from the `doppler run` export, (4) token traced under `bash -x`, (5) raw vendor body, jq diagnostic or audit actor / IP echoed on a failure path.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Build a Cloudflare READ-ONLY wrapper so the CTO agent can run the #10479 live-read checks A ..., B ..., C ... and E ... as Class R" | Phase 2 | mapped |
| 2 | "Model it on scripts/betterstack-query.sh and scripts/sentry-issue.sh: credential used only inside the wrapper ... GET only; a closed allow-list of endpoints and jq projections; ... stderr never discarded; a 403 ... reported as `unverified` ...; fails closed on any non-GET, unknown endpoint, or unexpected token source" | Phase 2, Guards 1-2 | mapped |
| 3 | "Update section 9 of ... standing-delegation.md ..., the 48-anchor pin test and the CTO agent definition as needed, with a test row for adding Cloudflare as a Class R vendor" | Phases 1 and 3 | mapped |
| 4 | "The adding-a-vendor ruling is technical: spawn soleur:engineering:cto and record 'Ruled by CTO agent'" | decision-challenges.md D1-D6 | mapped (done at plan time) |
| 5 | "Hermetic test suite for the wrapper ... with mutation rows for: non-GET refused, unknown endpoint refused, token never printed, 403 gives unverified" | Phase 1, Guards 1-2 | mapped |
| 6 | "Wrapper placement ... Prefer a path outside both" | D2, Phase 5 | mapped |
| 7 | "HARD LIMITS ... ends at a DRAFT pull request ... UNARMED" and the push gate | Phase 5 | mapped |
| 8 | "Check D (web-host listener reads) is out of scope" | Sharp Edges (nothing planned) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Wrapper script and four subcommands | "checks A ... B ... C ... and E" | asked |
| Item 4 clarifying clause | "Prefer a path outside both" | inferred - justification: CTO D2/D9 consequence of the placement; push eligibility does not depend on it; flagged to the owner |
| ADR-289 addendum | — | inferred - justification: plan Phase 2.10 makes an extension of an existing ADR a deliverable of the plan; scope trimmed to the Cloudflare vendor line and the credentials exception |
| `--list` zero-exit subcommand | — | inferred - justification: gives `discoverability_test` a no-network, no-credential, exit-0 probe and gives the pin test the code-side set (row D10) |
| Closed-set parity test (section 9 text vs wrapper array) | "the 48-anchor pin test ... as needed" | asked |
| `Unverified:` Class R Checks line | — | inferred - justification: section 9 Records requires it while the live reads cannot yet run |

### Split Assessment

- Subsystems touched: 4 - `plugins/soleur/scripts`, `plugins/soleur/test`, `plugins/soleur/skills` + `agents` (text), `knowledge-base/engineering/architecture` (ADR addendum)
- Planned files: 8 | Estimated changed lines: ~600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the roots are tightly coupled (the text, the wrapper and the pin test must agree in one diff, or the parity test is red)

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-289-standing-delegation-and-production-envelope.md` with `## Addendum 2026-11-04 (Ref #10205, #10479)` via `soleur:architecture`, in two short paragraphs: Cloudflare is a Class R vendor for four named reads through `plugins/soleur/scripts/cloudflare-readonly.sh`; and the Credentials exception for the three Terraform-scoped tokens (GET-only by construction, empty curl environment). Placement and the item 4 clause live in section 9 and are not restated. Status stays `adopting`. This is a Phase 3 task, not a follow-up issue.

### C4 views

No C4 change, with the enumeration the gate requires. Checked against `model.c4` (grep pass at plan time found the `cloudflare`, `doppler`, `sentry`, `betterstack` systems and `founder` approval edges; Phase 0 reads all three `.c4` files in full): (a) external human actor: the operator / founder is already modeled and no new human role is added; (b) external system: Cloudflare and Doppler are already modeled, no new vendor; (c) container / data store: none touched, the wrapper writes nothing durable; (d) actor-to-surface access: ADR-289 deliberately draws no agent-read edges to Sentry, Better Stack or Cloudflare, and this plan adds none. Backed by a green `plugins/soleur/test/c4-count-parity.test.sh` run (Phase 4).

### Sequencing

The addendum describes the target state now; the wrapper's first live use follows the owner's arming and merge.

## Implementation Phases

### Phase 0 - Verify before building (no Cloudflare call, no secrets)

1. Verify the vendor facts the wrapper encodes against current Cloudflare API documentation (context7 / developers.cloudflare.com) and cite the URL with `verified: <date>` in the wrapper header:
   - `GET /zones/{zone_id}/settings/ssl` (`result.id`, `value`, `modified_on`);
   - `GET /zones/{zone_id}/rulesets/phases/http_config_settings/entrypoint` (`result.id`, `version`, `last_updated`, `rules[].ref`, `enabled`, `action_parameters.ssl`; `rules` is omitted on an empty ruleset) and the exact `errors[].code` returned when no entrypoint ruleset exists, versus the code for an unroutable zone id;
   - `GET /zones/{zone_id}/pagerules?status=active` (`result[].targets[].constraint.value`, `actions[].id`, `actions[].value`) and which token permission it needs;
   - the account audit-log endpoint (`/accounts/{id}/logs/audit` or `/audit_logs`), whether `since` and `before` are both required, `limit`, `direction`, and the row fields (`action.type`, `resource.type`, `when`).
   Anything that cannot be verified is shipped as an `unverified - not-found` stub that sends no request, and the AC for that read is limited accordingly (an unverified `empty-phase` code means the entrypoint 404 is reported as `unverified - not-found`, not `ok`).
2. Read all three C4 files in full and confirm the "No C4 change" conclusion.
3. Read the full `on:` / `paths:` / `types:` blocks of every workflow in `.github/workflows` for the Phase 5 push gate (the plan-time survey truncated long path lists).

### Phase 1 - RED: tests first (`cq-write-failing-tests-before`)

1. Create `plugins/soleur/test/cloudflare-readonly.test.sh` (see Test Scenarios and Guards 1-2). Run it with the wrapper absent: it must fail (RED), not error out. The stub `curl` locates its log and fixtures from `dirname "$0"`, not from exported variables, because the real curl child has an empty environment.
2. Edit `plugins/soleur/test/components.test.ts`, describe "Class R read-only ownership wiring". Add exactly these 11 PAIRS rows (48 + 11 = 59; raise `PAIRS_FLOOR` to 59 in the same edit):
   - `[SD, "sd9", "plugins/soleur/scripts/cloudflare-readonly.sh"]`
   - `[SD, "sd9", "the exact parsed `api.cloudflare.com`"]`
   - `[SD, "sd9", "`ssl-mode`, `config-entrypoint`, `pagerules-ssl` or `change-history`"]`
   - `[SD, "sd9", "the wrapper sends GET only"]`
   - `[SD, "sd9", "never prints a rule `expression`"]`
   - `[SD, "sd9", "never answered by widening a token"]`
   - `[SD, "sd9", "The Cloudflare MCP server and the `cf-token-scope` skill are not Class R"]`
   - `[SD, "sd9", "`unverified - no-credential` when `CF_API_TOKEN_AUDIT` is absent"]`
   - `[SD, "sd9", "`CF_API_TOKEN` is never used"]`
   - `[SD, "sd9", "Here `scripts/**` means the repository-root `scripts/` directory"]`
   - `[CTO, "ctoOwn", "plugins/soleur/scripts/cloudflare-readonly.sh"]`
   Structural tests (not PAIRS rows): (a) subcommand parity: slice item 2's text from "its four subcommands" to the next colon, take the backticked names, and assert equality with the wrapper's `SUBCOMMANDS=(...)` array (comments stripped); (b) item 4 slice: the sentence starting "Here `scripts/**` means" names `plugins/**/scripts/**` and does not contain `.github`; (c) add `plugins/soleur/scripts/cloudflare-readonly.sh` and `the wrapper sends GET only` to the item 2 `REQUIRED` strings and the item 4 clause anchor to `REQUIRED[4]`. All new anchors must be unique in section 9 for the "exactly its named test red" claim. They fail against the unedited section 9.

### Phase 2 - the wrapper (`plugins/soleur/scripts/cloudflare-readonly.sh`)

Header states: Jikigai-internal, inert outside this repo; the verified vendor-doc citations; the invocation; the exit-code table. Interface (CTO D4, simplified by plan review D8):

- Invocation: `doppler run -p soleur -c prd_terraform -- bash plugins/soleur/scripts/cloudflare-readonly.sh <subcommand>`. `SUBCOMMANDS=(ssl-mode config-entrypoint pagerules-ssl change-history)`; `--list` prints the four names and exits 0 (no credential, no network, no Doppler names). Anything else, or any extra argument or flag (`-X`, `--method`, `--data`, `--url`, `--path`, `--token-var`, `--since-days`, ...), exits 64 before any request; parsing uses `${1:-}` / `$#` so `set -u` never fires.
- Prologue (lint Rule A): `set -uo pipefail`; the xtrace refusal `case "$-" in *x*)` exiting 78 when any bound token variable is set; `export LC_ALL=C`; the TLS-env `unset` block from `betterstack-query.sh`. No `set -x`, no `2>/dev/null`, no `eval`.
- Token source (fail closed): `DOPPLER_PROJECT` must equal `soleur` and `DOPPLER_CONFIG` must equal `prd_terraform`, else exit 64 `refused: unexpected token source` (a mistake-guard; env can be forged). Binding by subcommand: `ssl-mode` -> `CF_API_TOKEN_ZONE_SETTINGS`; `config-entrypoint`, `pagerules-ssl` -> `CF_API_TOKEN_RULESETS`; `change-history` -> `CF_API_TOKEN_AUDIT` plus `CF_ACCOUNT_ID`. `CF_ZONE_ID` (32 hex) for the first three, `CF_ACCOUNT_ID` (32 hex) for E. No fallback to `CF_API_TOKEN` or any other variable on any status. A missing bound variable prints `unverified - no-credential (<VARIABLE NAME>)` (the name only) and exits 10. Token shape must match `[A-Za-z0-9._~+/=-]`.
- Request chokepoint: one function `cf_get <subcommand>` is the only curl call site. It runs `env -i PATH="$PATH" LC_ALL=C curl -X GET --disable --noproxy '*' -sS --max-time 20 --max-redirs 0 -w '\n%{http_code}' --config - <URL>` with the credential supplied as `header = "Authorization: Bearer ..."` on the config channel (same form as `sentry-issue.sh`; verified by reading it in Phase 0), URL = `https://api.cloudflare.com/client/v4` + a fixed template with only the validated ids substituted, the method literal `-X GET`, and no `-L`, `-d`, `--data*`, `--json`, `-T`, `-F`. The body is held in a shell variable. Exactly one request per invocation: no retry and no second token.
- jq: every projection is preceded by a type guard (`jq -e '.success == true and (.result|type)=="<array|object>"'`) and uses `(.rules // [])`; a jq failure never prints jq's own diagnostic (it quotes body fragments); stderr is captured, not discarded, and reduced to the fixed message `bad-response (jq exit <n>)`. Never key on `.result | length`.
- Projections:
  - `ssl-mode`: `{subcommand, id, value, modified_on}`.
  - `config-entrypoint`: `{id, version, last_updated, rule_count, rules: [{ref, enabled, ssl, mentions_app_host, mentions_lb_staging_host}]}` in entrypoint order; the host booleans test for the quoted whole token (`"app.soleur.ai"`, `"lb-staging.soleur.ai"`), so `app.soleur.ai.evil` does not match. A 404 prints `ok empty-phase` (exit 0) only when `.errors[].code` equals the code verified in Phase 0; any other 404 is `unverified - not-found`.
  - `pagerules-ssl`: `{active_rule_count, ssl_rule_count, ssl_rules: [{id, status, target_count, ssl, matches_app_host}]}`; URL patterns are never printed.
  - `change-history`: fixed 7-day window (`since` = now minus 7 days, GNU `date -u -d`), `limit=50`, `direction=desc`, one page; counts only, grouped by `action.type` and `resource.type`, plus `rows`, `oldest_when`, `newest_when`, and one flag `truncated` (true when `rows` equals the limit; counts are then a lower bound). Never actor, IP or a raw row.
- Output contract: first stdout line `cloudflare-readonly: <subcommand> ok [empty-phase]` or `cloudflare-readonly: <subcommand> unverified - <reason>`, then (ok only) the JSON projection. Messages are fixed, single-line and value-free; a response body is never printed.
- Status map (by HTTP status first; codes are collapsed, the reason token on the first line is the discriminator): 200 with the type guard -> 0; 200 with `success:false` -> 14 `api-error`; 401 -> 11 `token-invalid`; 403 -> 11 `token-lacks-scope` (terminal, recorded, never retried, never another token); 404 -> 14 `not-found` (except the verified entrypoint code above); 429, 5xx, curl failure, timeout, any other non-2xx (400, 422, 3xx) -> 14 `upstream-error`; malformed JSON or wrong shape -> 14 `bad-response`; missing token variable -> 10 `no-credential`; usage or refusal -> 64; xtrace -> 78. Mapping to the Class R Records vocabulary: exit 10 is `no-credential`; exits 11 and 14 are `other: <reason>`.
- Cloud (Devin) sessions: the session-level `cloud-ack-before-secrets` obligation in the Credentials paragraph applies and is not implemented in the wrapper.

### Phase 3 - the text

1. `standing-delegation.md` section 9, via Edit: item 2 (replace the "No Cloudflare read wrapper exists" sentence), item 4 (one clause), the Credentials paragraph, the Boundary paragraph (Cloudflare added by ruling of 2026-11-04; any further vendor still needs a CTO ruling and a test row). Keep every existing REQUIRED string byte-identical (`never --latest-event`, the `--table` and `--grep` flag forms, `the exact parsed hostnames of items 2 and 3`, `Sentry reads use the read-only issue token only`, `is never pushed under Class R`).
   - Item 2 clause: "Cloudflare through `plugins/soleur/scripts/cloudflare-readonly.sh` only, with one of its four subcommands `ssl-mode`, `config-entrypoint`, `pagerules-ssl` or `change-history`, as a status, a count or a field subset: the wrapper sends GET only, never prints a rule `expression`, a description, an actor or an IP, and a 403 is recorded as `unverified` and never answered by widening a token; its one host is the exact parsed `api.cloudflare.com`. The audit-log read is `unverified - no-credential` when `CF_API_TOKEN_AUDIT` is absent. The Cloudflare MCP server and the `cf-token-scope` skill are not Class R."
   - Item 4 clause: "Here `scripts/**` means the repository-root `scripts/` directory; `plugins/**/scripts/**` is not covered by this bar and is governed by the trigger-block read above."
   - Credentials clause: "Cloudflare reads use only the token variable bound to the subcommand; `CF_API_TOKEN` is never used and no other `CF_*` token is read; the wrapper starts curl with an empty environment. The three Terraform-scoped Cloudflare tokens are write-capable because no read-only equivalent exists, so this is the one stated exception to the read-only-token rule; the wrapper sends GET only. An absent bound token makes the read `unverified`."
2. `plugins/soleur/agents/engineering/cto.md`: one sentence in "Class R first" naming the wrapper path and its four subcommands, and that a 403 is recorded and never widened.
3. ADR-289 addendum (above).

### Phase 4 - verify (local, hermetic, one suite at a time)

`bash plugins/soleur/test/cloudflare-readonly.test.sh`; the Class R describe in `plugins/soleur/test/components.test.ts` (copy the run command from `scripts/test-all.sh`); `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-capture-exit.py` and `scripts/lint-trap-tempfile-ownership.py` against the new file; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-guard-contract.py`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`; the fixture-relative-assert test; `plugins/soleur/test/opencode-adapter-install.test.ts`. The C4 tests (`c4-code-syntax`, `c4-render`) run only if a `.c4` file is edited.

### Phase 5 - ship phase: stop at the draft PR

1. Skip ready, merge, auto-merge, arming, postmerge, any workflow dispatch (including `mode=plan`), and any live wrapper run.
2. Push gate, before the first push and again before editing the PR: `git diff --name-only origin/main...HEAD` shows no path under `.github/` or root `scripts/`; read the `on:` / `paths:` / `types:` block of each workflow and match by hand. Plan-time survey: deploy / apply workflows trigger on `push` with `branches: [main]`, so a feature-branch push fires none of them; the `pull_request`-family set is `ci.yml`, `claude-code-review.yml` (accepted standing run), `pr-quality-guards.yml`, `secret-scan.yml`, `cla.yml` and `cla-evidence.yml` (`pull_request_target`), `cancel-superseded-pr-runs.yml`, `board-status-sync.yml`, `vendor-pin-verify.yml`, `tenant-integration.yml`, and `apply-sentry-infra.yml` (name says apply; read its PR job to confirm it only plans), plus path-gated ones (`gdpr-gate-self-test`, `skill-security-scan-corpus`, `infra-validation`, `sentry-audit-gate`, `check-inngest-bootstrap-build`, ...) that match only if the full `paths:` list names a changed path. Push only if none that matches deploys, applies infrastructure or spends money. The post-merge `push: main` workflows on `plugins/soleur/**` (`version-bump-and-release`, `web-platform-release`) are an arming-time matter for the owner, unchanged by placement because the required `standing-delegation.md` edit already triggers them.
3. If the push gate fails, or the owner-facing doubt about `scripts/**` is unresolved: commit locally only, do not push, and report one plain sentence to the owner.
4. Before saving any PR body: `gh pr view 12061 --json closingIssuesReferences --jq '.closingIssuesReferences | length'` prints `0`; the body uses `Ref #10479` and `Ref #10205`, never `Closes`, `Fixes` or `Resolves`; re-check after saving. Body order, first items first: (1) the credential exception D6 (write-capable Terraform tokens used for reads, with the stricter alternative); (2) the item 4 clause, with the line "push eligibility does not depend on this clause"; (3) the post-merge workflow note; (4) every standing `Unverified:` line.

## Files to Create

- `plugins/soleur/scripts/cloudflare-readonly.sh` (wrapper, executable, bash shebang)
- `plugins/soleur/test/cloudflare-readonly.test.sh` (hermetic suite with mutation rows)
- `knowledge-base/project/specs/feat-one-shot-10479-cf-readonly-wrapper/tasks.md` (derived at plan finalization)
- `knowledge-base/project/specs/feat-one-shot-10479-cf-readonly-wrapper/decision-challenges.md` (created at plan time)

## Files to Edit

- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` (section 9 items 2 and 4, Credentials, Boundary)
- `plugins/soleur/agents/engineering/cto.md` (one sentence, "Class R first")
- `plugins/soleur/test/components.test.ts` (11 pin rows, structural tests, `PAIRS_FLOOR` 48 -> 59)
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md` (addendum)

Verified negatives: no edit under `.github/**` or root `scripts/**`; no SKILL.md `description:` edit (word budget untouched); no new skill or agent (component counts unchanged); `AGENTS.rules.md` untouched (no rule-body hash regeneration). Glob check: `plugins/soleur/scripts/*.sh` and `plugins/soleur/test/*.test.sh` both match existing files.

## Guard Contract

### Guard 1 - Request closure (GET only, closed allow-list, fixed host)

**Property.** The wrapper can send only an HTTP GET to one of four fixed URL templates on `api.cloudflare.com`, and nothing in argv, environment or a response selects the method, host, path, query or token.

**Assembly.** Every path that can influence a request: the argument parser (flags, extra positionals), the dispatcher `case` and its refusing fallthrough arm, the `SUBCOMMANDS` array and URL templates, the single `cf_get` chokepoint (the only `curl` call site; a census with comments stripped asserts exactly one), the `--list` branch, environment variables read by the wrapper (any host override, `DOPPLER_*`), the curl flag set, the config-channel lines, and the jq projections (read-only). The chokepoint is `cf_get`; the parser and the dispatcher are the two other places a request could be steered, and both are covered below.

**Mutation matrix** (each edit to a copy of the wrapper must drive the suite RED):

| # | Edit | Must go RED via |
|---|---|---|
| 1 | change `-X GET` to `-X POST` in `cf_get` | per-subcommand wire assertion: recorded argv has exactly `-X GET` and none of `-d`, `--data*`, `--json`, `-T`, `-F`, for all four subcommands |
| 2 | add a fifth dispatcher arm after the four compliant ones (e.g. `raw) cf_get ssl-mode`) | unknown-endpoint rows (`raw`, `ssl-mode/extra`, `../x`, `https://evil.example`, empty) refused with the curl marker absent; closed-set parity (wrapper array == section 9 set) |
| 3 | replace the dispatcher's refusing `*)` arm with a call into `cf_get` (the guard's own dispatch) | the same unknown-endpoint rows; and a floor: fewer than 4 subcommands x 3 outcomes exercised makes the suite fail ("0 checked" is RED) |
| 4 | add a second curl call site (retry on 403 with another token variable) | census == 1; the 403 row asserts curl was called exactly once with the bound token only |
| 5 | make the host overridable (read `${CF_API_BASE:-https://api.cloudflare.com}` in `cf_get`) | a planted `CF_API_BASE=https://evil.example` in the test env: the recorded URL host must still be `api.cloudflare.com` |
| 6 | add `-L` or drop `--max-redirs 0` | argv assertion on those two flags |
| 7 | accept an extra argument (`--method DELETE`, `-X DELETE`, `--data x`, `--since-days 3`) | non-GET and extra-argument rows: exit 64, curl marker absent, no request logged |

**Harness rows.** Suite edit that must go RED: make the stub `curl` write its log to `/dev/null`; the floor "recorded argv is non-empty and carries the expected URL" fails instead of passing vacuously. Must-PASS inputs that are not the canonical: a valid 200 whose `rules` are reordered and carry unknown extra fields, a `pagerules` body with one SSL action and one non-SSL action, a body with `rules` omitted (empty ruleset), and a zone id that differs from the canonical fixture; each must produce the documented projection.

**Anchor.** The allow-list lives in the wrapper and its set is pinned in `components.test.ts` and section 9, which one diff could edit together (consistency, not integrity). The controls outside the commit are item 2's run-time rule (`git fetch origin main`, then `git diff origin/main -- <wrapper>` empty before any run) and the owner arming the PR; the review seat compares the wrapper's curl flag set to this table.

### Guard 2 - Credential non-disclosure

**Property.** No byte of any Cloudflare token reaches stdout, stderr, a command line, a file, or the environment of any child process; it travels only on curl's stdin config.

**Assembly.** Every output and propagation path: each `printf` / `echo` site, the `die` handler, `--list`, usage text, every error branch (401, 403, 404, 429, 5xx, bad JSON, wrong type, `success:false`, no-credential, shape refusal, source refusal), the jq invocations and jq's own stderr (it quotes body fragments), the curl child's environment, and `set -x` / `bash -x`. Chokepoints: one `emit` for stdout, one `die` for stderr with fixed strings, the single `env -i` curl invocation, and the config-channel line.

**Mutation matrix:**

| # | Edit | Must go RED via |
|---|---|---|
| 1 | add `echo "$TOKEN"` to the 403 branch (and, separately, to the success branch) | combined stdout+stderr scan over every subcommand x every status: fake token absent |
| 2 | pass the credential as `-H "Authorization: Bearer $TOKEN"` in argv | argv log contains no token, `Bearer` or `Authorization`; stdin log contains the token exactly once, only there |
| 3 | drop `env -i` (plain `curl`) | stub curl dumps its `env`: no token, no other `CF_*` token, no planted canary variable |
| 4 | remove the jq type guard / print the raw body on `bad-response` (stub body is a wrong-type JSON string containing a token-shaped canary) | stdout+stderr scan: the canary is absent and the message is the fixed `bad-response (jq exit <n>)` |
| 5 | remove the xtrace refusal (and, separately, add `set -x`) | the suite runs the wrapper under `bash -x` with a token set: exit 78 and no token in output; source guard: `set -x` absent |
| 6 | add `2>/dev/null` to a curl or jq call | source guard: no `2>/dev/null` in the wrapper |

**Harness rows.** Suite edit: replace the fake token with a value the scan would not match (shorter, inside another word) and assert the detector still catches an injected leak, proving the detector is live. Must-PASS: a token containing every permitted punctuation character (`._~+/=-`) is sent on the config channel intact.

**Anchor.** `lint-shell-trace-credential-refusal.py` (Rules A, B, E) and its baselines run in CI independently of this suite and cannot be edited by the suite's author without showing in the baseline files.

### Guard 3 - Class R closed set (text, agent, pin test)

**Property.** Section 9 cannot gain a Cloudflare read, host, token or subcommand beyond the four named, and cannot lose the GET-only, no-expression, no-widening, not-Class-R-MCP or root-anchored `scripts/**` limits, without a named test going red.

**Assembly.** Item 2, item 4's clause, the Credentials paragraph, the Boundary paragraph, `cto.md` "Class R first", the wrapper's `SUBCOMMANDS` array, and the `PAIRS` table with `PAIRS_FLOOR`. The structural parts are the per-item `REQUIRED` strings and the set-equality and sentence-slice tests (subcommand parity; item 4 sentence). The member list (the anchors) drifts; those two tests do not.

**Mutation matrix:**

| # | Edit | Must go RED via |
|---|---|---|
| 1 | add a fifth name to item 2's subcommand list | subcommand parity against the wrapper array |
| 2 | change the host to a wildcard or add a second host | the `api.cloudflare.com` anchor and item 2 `REQUIRED` |
| 3 | delete "sends GET only" or "never prints a rule `expression`" | their PAIRS rows and item 2 `REQUIRED` |
| 4 | widen the item 4 clause to include `.github` | the item 4 sentence-slice test (names `plugins/**/scripts/**`, not `.github`) |
| 5 | empty the Cloudflare rows from `PAIRS` | `PAIRS_FLOOR` (59) |

**Harness rows.** Suite edit: make the item 2 slicer return the whole file; the parity test must go RED (backticked tokens elsewhere in item 2 would otherwise pass silently). Must-PASS: the Cloudflare clause re-flowed across lines with different whitespace still passes.

**Anchor.** The pin anchors live in the same file family as the text, so one diff can edit both; the independent controls are the user-impact-reviewer seat and the owner arming the PR (stated residual, same as the 2026-11-03 Class R pin).

## Observability

```yaml
liveness_signal:
  what: the wrapper's first stdout line "cloudflare-readonly: <subcommand> ok|unverified - <reason>" plus an exit code (0 ok, 10 no-credential, 11 token, 14 other, 64 refused, 78 xtrace)
  cadence: on demand, once per Class R read the CTO agent runs
  alert_target: the calling agent's transcript; the verdict becomes a "Checked:" or "Unverified:" line in the plan's "## Class R Checks" section and the PR body
  configured_in: plugins/soleur/scripts/cloudflare-readonly.sh (emit function) and standing-delegation.md section 9 Records
error_reporting:
  destination: stderr of the wrapper (never discarded) with fixed value-free messages, plus the exit code; no Sentry client (operator-side tool, no server runtime, no silent fallback exists to mirror)
  fail_loud: true
failure_modes:
  - mode: bound token variable absent or empty
    detection: stdout "unverified - no-credential (<VARIABLE NAME>)", exit 10
    alert_route: "Unverified:" line in Class R Checks (reason no-credential); epic stays open
  - mode: token lacks scope or is invalid (403 / 401)
    detection: stdout "unverified - token-lacks-scope" or "token-invalid", exit 11, curl called exactly once
    alert_route: "Unverified:" line (other: <reason>); the token is never widened
  - mode: Cloudflare unreachable, 429 / 5xx, malformed or wrong-type body, success:false 200, unexpected 404
    detection: exit 14 with a fixed reason token
    alert_route: "Unverified:" line; retriable reasons are re-run next session
  - mode: wrapper edited after the owner reviewed it
    detection: "git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh" is non-empty before a run (item 2 rule)
    alert_route: the read is "unverified" until the diff is empty
logs:
  where: transcript of the calling session only; the wrapper writes no log file and keeps no body
  retention: none by the wrapper; the Class R Checks line carries the figure
discoverability_test:
  command: bash plugins/soleur/scripts/cloudflare-readonly.sh --list
  expected_output: ssl-mode
```

Layer citation (`hr-observability-layer-citation`): the wrapper executes on the operator's or CI agent's checkout, a non-server surface with no Sentry path; its observability layer is the stdout verdict plus exit code consumed by the calling agent. In a plugin user's install it is inert (Doppler pins refuse), so there is no customer self-hosted execution to cover.

## Encryption Posture

```yaml
at_rest:
  - store: none introduced (the response body lives only in a shell variable for one call; no temp file, no log, no persisted token)
    mechanism: not-applicable-no-persistent-store
    evidence: plugins/soleur/scripts/cloudflare-readonly.sh (no mktemp, no redirect to a file; source guard in the suite)
    defends_against: nothing is stored, so there is no stored copy to protect
    does_not_defend: process memory of the calling shell during the call, readable by a same-user process
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no store exists
in_transit:
  - connection: operator checkout (agent shell) -> api.cloudflare.com
    enforced_at: plugins/soleur/scripts/cloudflare-readonly.sh (cf_get; https scheme fixed in the URL template, --max-redirs 0, TLS-env unset block)
    tls: https, curl default minimum (TLS 1.2+), certificate verification left at the curl default
    cert_verification: on
    does_not_defend: a compromised local trust store or a hostile same-host process (the TLS-subversion env vars are unset, the trust store itself is not pinned); Cloudflare itself
    disclosed_as: not-publicly-claimed
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-04 (rows D1-D6, D9): add Cloudflare for four reads through one GET-only wrapper at `plugins/soleur/scripts/cloudflare-readonly.sh`; per-subcommand token binding with an empty curl environment; expression, description, actor and IP are never printed; 403 is `unverified` and recorded; the Terraform-scoped (write-capable) tokens are accepted for A/B/C only, stated plainly, with the stricter alternative recorded as dissent. Legal: no CLO spawn; audit rows are reduced to counts inside the wrapper and no actor or IP is printed or stored, so no personal-data processing is added and no canonical regulated-data surface is touched. Product / UX: no user-facing surface, so no wireframe gate and no CPO sign-off (threshold `aggregate pattern`). Operations / Finance: no spend, no new vendor account.

## Acceptance Criteria

### Pre-merge (PR, draft)

- [ ] `plugins/soleur/scripts/cloudflare-readonly.sh` exists, is executable, passes `lint-shell-trace-credential-refusal.py`, `lint-shell-capture-exit.py`, `lint-trap-tempfile-ownership.py`; has exactly one curl call site, no `set -x`, no `2>/dev/null`, no `mktemp`; `--list` prints exactly the four subcommand names with no credential and no network.
- [ ] `bash plugins/soleur/test/cloudflare-readonly.test.sh` is green, and each mutation row of Guards 1 and 2 turns it RED on a mutated copy (including the four asked rows: non-GET refused, unknown endpoint refused, token never printed, 403 gives `unverified`); the suite uses no network, no `prd` configuration (the `DOPPLER_*` values are inert strings) and writes only under a scratch directory inside the worktree that it removes on exit; `git status --short` shows no scratch files afterwards.
- [ ] Section 9 item 2 no longer says "No Cloudflare read wrapper exists"; item 2 carries the Cloudflare clause with the exact anchors in Phase 3; item 4 carries the root-anchored clause; the Credentials and Boundary paragraphs are updated; every pre-existing REQUIRED string is unchanged; section 9 still names exactly six Class R acts.
- [ ] `components.test.ts` has the 11 listed PAIRS rows (10 `sd9`, 1 `ctoOwn`), the subcommand-parity and item 4 sentence tests, the extended REQUIRED strings, and `PAIRS_FLOOR` equal to 59; the file is green; mutating any single anchor turns exactly its named test red.
- [ ] `cto.md` carries the Cloudflare sentence; ADR-289 carries the 2026-11-04 addendum with status `adopting` unchanged; `c4-count-parity` is green and `.c4` files are untouched (or, if work finds a falsified element, edited and the C4 tests green).
- [ ] `technical-ruling-gate.sh --branch` prints `[PASS]`; `lint-guard-contract.py` and `lint-orphan-test-suites.sh` pass.
- [ ] The diff touches no path under `.github/` or root `scripts/` (`git diff --name-only origin/main...HEAD`).
- [ ] No workflow was dispatched, no live Cloudflare call was made, no Doppler read happened, PR #12061 is still a draft and unarmed, and `closingIssuesReferences` is `[]` before and after the last body save.

### Post-merge (owner, separate, not part of this run)

- Owner arms and merges; then the CTO agent runs A, B, C, E through the wrapper, records `Checked:` lines, and posts token-free figures on #10479.
- Later and separately: a `_dev` key-rotate `mode=plan` dispatch (needs the owner's typed go naming the command) and the credential mint (needs the owner's named go). The audit token's location (`dev` versus `prd_terraform`) is an owner-side fact to confirm before E can be anything but `unverified - no-credential`.

## Test Scenarios

Command-to-terminal rows (stub `curl` first on PATH, logging argv, stdin and its own `env`; real `jq`; fake distinctive tokens):

1. `ssl-mode`, 200 with `value:"strict"` -> `ok`, URL `.../zones/<zone>/settings/ssl`, argv has `-X GET`, bound token on stdin only.
2. `config-entrypoint`, 200 with three rules (reordered, extra fields) -> rules in order with `ref`, `enabled`, `ssl` and the two host booleans (`app.soleur.ai.evil` does not set `mentions_app_host`); no expression text in output; a body with `rules` omitted -> `rule_count: 0`.
3. `config-entrypoint`, 404 with the verified empty-phase code -> `ok empty-phase`, exit 0; 404 with any other code (wrong zone) -> `unverified - not-found`, exit 14. `pagerules-ssl` 404 -> exit 14.
4. `pagerules-ssl`, 200 with two rules (one SSL action, one not) -> counts and `ssl_rules` of length 1; patterns not printed.
5. `change-history`, 200 with rows -> counts by action / resource type, `rows`, `oldest_when`, `newest_when`, `truncated` true at 50 rows; no actor / IP / raw row; bound token absent -> exit 10 naming the variable.
6. 403 on each of the four subcommands -> `unverified - token-lacks-scope`, exit 11, curl called once, no second token tried.
7. 401 -> exit 11 `token-invalid`; 429, 5xx, 400, 3xx, curl failure -> exit 14; malformed JSON, wrong-type body (string containing a token-shaped canary) and `{"success":true,"result":null}` -> exit 14 `bad-response`, canary absent; 200 `success:false` -> exit 14 `api-error`.
8. Refusals before any request: unknown subcommand, empty, `ssl-mode extra`, `-X POST`, `--method DELETE`, `--data x`, `--url https://evil.example`, `--since-days 3`, `../x`; `DOPPLER_CONFIG=dev`; `CF_ZONE_ID` non-hex; a token with a quote or newline.
9. Environment: with `CF_API_TOKEN`, a second Cloudflare token, `HTTPS_PROXY`, `CURL_CA_BUNDLE` and a planted canary exported, the stub curl's `env` dump is empty of all of them; a planted `CF_API_BASE` does not change the host.
10. Token hygiene: for every subcommand x every status above, stdout+stderr contain neither token nor canary; the argv log contains neither token nor `Authorization`; under `bash -x` with a token set the wrapper exits 78.
11. Source guards: no `set -x`, no `2>/dev/null`, no `mktemp`, no `eval`, exactly one curl call site (comments stripped).
12. Mutation harness: `mutate <label> '<from>' '<to>'` over a copy of the wrapper, one row per matrix line above, each asserting the battery reports at least one failure; anti-vacuity floors on exercised subcommand x outcome count and on non-empty recorded argv.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- **Item 4 is read by the very change that clarifies it.** The clause ships only on merge, so push eligibility rests on the literal, root-anchored glob and the CTO ruling D2/D9, not on text this PR adds. The PR body says "push eligibility does not depend on this clause". If the owner reads `scripts/**` as any-depth, the fallback is: commit locally, do not push, one plain sentence to the owner.
- **Credential exception (D6).** `CF_API_TOKEN_RULESETS` and `CF_API_TOKEN_ZONE_SETTINGS` are write-capable; the wrapper's safety is structural (hardcoded `-X GET`, fixed templates, empty curl environment, drift guard), not a scope property. Revisit if the wrapper can be driven to send a non-GET or a read-only token is minted. Dissent recorded in D6; it is the first item in the PR body.
- **`pagerules` may be a permanent 403** if `CF_API_TOKEN_RULESETS` lacks Page Rules read (the #10479 comment says this is unverified). That is a valid `unverified - token-lacks-scope` result; the token is not widened to fix it.
- **Distribution.** The wrapper ships to plugin users; it is inert there. Its header says "Jikigai-internal"; `--list` prints no Doppler project or config names. The zone and account ids come from the environment, never hardcoded.
- **Class R item 6 says "no write outside the worktree"**, stricter than the repo's usual `mktemp -d` in `/tmp`: the suite points `TMPDIR` at an in-worktree scratch directory removed on exit. Existing suites are unchanged.
- `doppler run` exports every secret in `prd_terraform`; never rely on a variable being unset by the caller. The curl child gets an empty environment via `env -i`; jq and other children still inherit, and Property 2 is scoped to the curl child plus output channels.
- Vendor facts the wrapper encodes (audit-log endpoint and fields, the entrypoint empty-phase error code, pagerules shape and permission) come from vendor documentation verified in Phase 0 with a dated citation; unverified facts degrade to `unverified`, never to a guess (the #1810 failure class).
- Cloud (Devin) sessions: the session-level acknowledgement before any secrets read still applies and is not implemented in the wrapper; an unanswered or headless session records the read as `unverified` with reason `no-session`.
- Section 9 Records: each standing `Unverified:` line is copied into the final report and the PR body before the plan is archived.
- Deferral tracking: nothing is deferred by this plan that is not already tracked. Check D and the other open items are tracked on #10479; the audit-token location question is an `Unverified:` line and a PR-body item, and no new issue is filed in this run (owner limit on trackers).

## Class R Checks

Unverified: Cloudflare live reads A, B, C and E for #10479, other: the read wrapper exists only in this unmerged draft PR and the owner has not armed it, 2026-11-04T08:12Z
