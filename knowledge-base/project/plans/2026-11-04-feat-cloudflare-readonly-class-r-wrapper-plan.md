---
title: "feat: Cloudflare read-only wrapper for Class R live-read checks (#10479 A/B/C/E)"
date: 2026-11-04
slug: cloudflare-readonly-class-r-wrapper
branch: feat-one-shot-10479-cf-readonly-wrapper
issue: 10479
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
---

## Enhancement Summary

**Deepened on:** 2026-11-04
**Sections enhanced:** Phase 0, Phase 1, Phase 2, Phase 3, Guard Contract, Observability, Test Scenarios, Acceptance Criteria, Class R Checks
**Research and review agents used:** security-sentinel, test-design-reviewer, spec-flow-analyzer, framework-docs-researcher (Cloudflare docs check), plus the earlier plan-review panel (code-simplicity, DHH, Kieran, CTO devex seat).

### Key improvements

1. **Invocation fixed.** `doppler run ... -- bash <wrapper>` is forbidden by the Credentials paragraph; the wrapper is invoked as a directly executable file, like `sentry-issue.sh`.
2. **Hostile-PATH closure.** curl is called by absolute path (`/usr/bin/env -i /usr/bin/curl --disable ...`), `--disable` first; the credential channel is `< <(printf ...)` only (no pipe, no here-string).
3. **Vendor strings are enum- or regex-checked before printing** (ref, id, value, ssl, timestamps, group keys), and curl / jq diagnostics are captured and reduced to a class plus exit status.
4. **`ok empty-phase` removed.** Cloudflare's docs do not state the "no entrypoint" error code, and Terraform says the entrypoint exists, so any 404 is `unverified - not-found`.
5. **Audit log facts corrected from the docs:** v2 `/accounts/{id}/logs/audit`, field `action.time` (not `when`), send both `since` and `before` (docs conflict on whether they are required).
6. **Records mapping added** (a verdict table per projection, four stable-key `Unverified:` lines, reasons for exits 64 / 78 / drift / truncation) so a wrapper `ok` is never confused with a Records `ok`.
7. **Test design hardened:** instrumented `mutate` helper (pristine control, `bash -n`, exactly-one match, named failing row), fixture-file stub (the curl child has an empty environment), `grep -F` leak scans with controls, mutation rows for token-shape guard, binding swap, `CF_API_TOKEN` fallback, `DOPPLER_*` pin and 403 mapping.

### New considerations discovered

- Page Rules read needs "Page Rules Read" (or Zone Read / Write) per the docs; `CF_API_TOKEN_RULESETS` probably lacks it, so check C is expected to be `unverified - token-lacks-scope`. That is a valid, recorded outcome.
- The item 4 clause is a permission-widening edit written by the PR whose push it governs; the security seat would cut it, the CTO ruled to keep it (D9). It stays the second item the owner reviews.

## Overview

Give the CTO agent a repo wrapper that performs four read-only Cloudflare checks for the origin-TLS question on #10479 (zone SSL mode, the config-settings ruleset entrypoint, legacy page rules limited to SSL actions, and a bounded change-history read), so they run as Class R acts instead of being handed back as holds. The wrapper is the only Cloudflare reader that section 9 of the standing-delegation reference will allow; adding Cloudflare as a vendor also needs a CTO ruling (done, see Decisions) and a pin-test row.

This run ends at the draft pull request #12061, unarmed. No live Cloudflare call, no Doppler read, no credential mint, no workflow dispatch and no tracker edit is part of it. The spec had no `lane:` key (no brainstorm ran), so the lane defaulted to `cross-domain` (fail-closed).

Hard limits carried into every phase: draft only; do not mark ready, merge or arm; the PR body uses `Ref #10479` and `Ref #10205` only, and `closingIssuesReferences` is verified to be `[]` before any body is saved.

## Research Insights

### Premise validation (Phase 0.6)

- #10479 is OPEN. PR #12061 is an open draft with `closingIssuesReferences: []`. Merge commit f2e2ebd0e2 (the Class R change) resolves on this checkout. Comment 6610203058 was read in full: reads A, B, C, E are as described in the task; D is out of scope.
- Collision pre-check: the only open change naming #10479 is our own draft #12061; two foreign `test-all.sh` processes belong to unrelated worktrees (launch-check, suite-times). No duplicate work.
- The mechanism (a read wrapper under a Class R vendor ruling) is not in any ADR's rejected-alternatives table: ADR-289's 2026-11-03 addendum names Cloudflare as a Class R vendor but says no wrapper exists, and item 2 says the same. This plan fills that stated gap.
- Deepen-plan verification: PR/issue citations resolved live (#11312 OPEN, #12061 OPEN draft, #10479 OPEN, #1810 MERGED as the cited fabricated-CLI-token precedent); every cited lint, test and ADR path exists on this checkout (`lint-orphan-test-suites.sh`, `lint-trap-tempfile-ownership.py`, `lint-shell-capture-exit.py`, `lint-shell-trace-credential-refusal.py`, `c4-count-parity.test.sh`, `opencode-adapter-install.test.ts`, `fixture-relative-assert.test.sh`, ADR-130, ADR-280); the plan cites no AGENTS rule id that is missing; `betterstack-query.sh` feeds curl `--config - < <(printf ...)` and says why a pipe is wrong (SIGPIPE 141 under pipefail); `sentry-issue.sh` uses `-w $'\n%{http_code}'`.

### Property list (Phase 0.6b)

1. The CTO agent can obtain, without the owner, the four live Cloudflare facts #10479 needs.
2. The credential never reaches the transcript, a command line, stdout, stderr or a child environment; it travels only on curl's stdin config.
3. The wrapper can send only a GET to four fixed URL templates on `api.cloudflare.com`; nothing in argv, env or a response selects method, host, path, query or the curl binary.
4. Output is a status, a count or a field subset; vendor text (rule expressions, descriptions, page-rule patterns) and personal data (audit actor, IP) never enter the transcript, and every vendor string that is printed is enum- or regex-checked first.
5. A token that lacks scope (403) is reported as `unverified` and never worked around.
6. Section 9, the CTO agent and the pin test agree on exactly this closed set, so Class R cannot widen silently.

### Cut list

| Mechanism considered | Property it would buy | Verdict |
|---|---|---|
| New runbook `cloudflare-read.md` | operator re-mint steps | Cut: section 9 plus the wrapper header carry the invocation and the Records mapping; minting is owner-only and out of this run |
| Source `scripts/lib/bearer-curl.sh` (ADR-280) | one tested stdin-config implementation | Cut. Strong reason (CTO devex seat): the item 2 drift guard diffs only the wrapper against `origin/main`; a sourced root-level library would be a second file outside that guard. Cost accepted: a third copy of the credential-channel code, using the same form as `betterstack-query.sh` (`--config - < <(printf ...)`) and the same token alphabet `[A-Za-z0-9._~+/=-]` |
| Pagination loop on the audit log | complete window | Cut: one bounded page (50) and a single `truncated` flag |
| `--since-days N` option | adjustable window | Cut: fixed 7-day window, so no flag and no parsing surface |
| `expression_sha256`, `ok empty-phase` | change detection, empty ruleset | Cut: nothing consumes the hash; the docs do not state the "no entrypoint" error code and Terraform says the entrypoint exists, so a 404 is a finding (`unverified - not-found`) |
| mktemp body file, trap, `compgen -e` unset loop | body capture, env scrub | Cut: the body is held in a shell variable via `-w`; the curl child is started as `/usr/bin/env -i /usr/bin/curl ...` |
| Cloudflare error codes 9109 / 10000 in the status map | finer 403 split | Cut: 9109 has no official definition and 10000 is documented as "Domain not found" elsewhere; map by HTTP status only |
| `bash <wrapper>` under `doppler run` | convenience | Cut: forbidden by the Credentials paragraph (`doppler run -- ... bash`); direct exec only |
| New Class R act (item 7) for Cloudflare | clarity | Cut: item 2 already covers "operator's own vendor accounts through repo wrappers"; the closed six-act count stays 6 |
| Reuse `cf-token-scope.sh` | a Cloudflare reader exists | Cut: it calls `doppler secrets get` (forbidden for agents), probes scope, and cannot project state |
| Cloudflare MCP server | a Cloudflare reader exists | Cut: open tool surface, OAuth writes; stays outside Class R |

### Institutional learnings applied

- Token on stdin config, never argv (`2026-02-18-token-env-var-not-cli-arg.md`, ADR-280, #7797 xtrace refusal).
- `doppler run` exports the whole config, so the curl child environment is empty by construction (`2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`).
- Guard every `jq` call and validate every 2xx body parses (`2026-03-09-shell-api-wrapper-hardening-patterns.md`); a 200 with `success:false` is an error, and `.result | length` reads `null` as 0.
- A 401/403 cannot distinguish "token lacks scope" from "resource missing"; report 403 as `unverified`, never "absent" (`2026-05-19-sentry-401-is-not-unowned-...`).
- Anchor the allow-list fully, with suffix / extra-segment refusal probes (`2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential.md`).
- Fixtures must include reordered, extra-field and wrong-type bodies; assert the wire (recorded URL, method, stdin), not only the output (`2026-07-19-a-mutation-battery-...`, `2026-07-27-my-battery-was-green-...`).
- A presence pin is not a boundary: pin each limit inside the item that owns it, closed sets by equality, polarity-bearing anchors (`2026-11-03-a-read-only-class-is-only-as-closed-as-its-per-item-pins-...`).

### Cloudflare API facts (framework-docs check at deepen time, documentation only, no authenticated call)

| Item | Seen in the docs | Not verifiable from docs (Phase 0 handles or the wrapper degrades) |
|---|---|---|
| SSL setting | `GET /zones/{zone_id}/settings/ssl` -> `{id:"ssl", value, editable, modified_on}`, `value` in `off`/`flexible`/`full`/`strict` | whether the single GET wraps in `result` (the #10479 command uses `.result.value`, so the wrapper expects it and treats a missing `.result` as `bad-response`) |
| Entrypoint | path `/zones/{id}/rulesets/phases/{phase}/entrypoint`; result `id, description, kind, last_updated, name, phase, rules`; `rules[]`: `id, ref, version, enabled, action, action_parameters, expression, description, last_updated` | result-level `version` is not in the docs excerpt (the #10479 command uses it; treated as optional, printed as `null` when absent); `action_parameters.ssl` not shown (config rules `set_config`); the missing-entrypoint status / code is not stated (hence no `empty-phase`) |
| Page rules | `GET /zones/{zone_id}/pagerules?status=active`; `targets[].constraint.operator/value`, `actions[].id/value`, `status`, `priority`; permission: any one of Zone Read, Zone Write, Page Rules Read, Page Rules Write | not covered by Zone Rulesets; so `CF_API_TOKEN_RULESETS` may 403 here |
| Audit log | v2 `GET /accounts/{account_id}/logs/audit`; `limit` 1-1000, `direction`, `cursor`, `action_type`, `actor_*`, `resource_*`; fields `result[].action.type`, `action.time`, `actor.*`, `resource.type`; retention 18 months | docs conflict on whether `since` and `before` are required (send both); permission name; no end-of-results signal (so `truncated` = rows equals the limit) |
| Errors / 429 | envelope `{"errors":[{"code","message"}],"success":false,...}`; 1,200 requests per 5 minutes per token; `Retry-After` on 429 | codes 9109 / 10000 are not auth codes per the docs (dropped from the map) |

### Repo findings

- Models: `scripts/sentry-issue.sh` (pinned host, xtrace refusal, stdin config), `scripts/betterstack-query.sh` (TLS-env `unset` block, credential shape guard). Tests: `scripts/sentry-issue.test.sh` (stub `curl` logging argv and stdin), `plugins/soleur/test/cf-token-scope.test.sh` (stub bin dir, curl marker, `src_has` / `src_lacks`), and the `mutate` shape at `scripts/assert-dependabot-drain.test.sh` (pristine control, `bash -n`, exactly-one match, named failing row).
- Lints that scan every tracked `.sh`: `scripts/lint-shell-trace-credential-refusal.py` (Rule A refusal in the prologue, Rule B no later `set -x`, Rule E no credential header or `-u` in curl argv), `scripts/lint-shell-capture-exit.py`, `scripts/lint-trap-tempfile-ownership.py`, and the fixture-relative-assert baseline.
- Test discovery: `scripts/test-all.sh` globs `plugins/soleur/test/*.test.sh`, so the new suite needs no edit under `scripts/`; `scripts/lint-orphan-test-suites.sh` checks registration. A suite weight row would need `scripts/suite-durations.tsv` (a root `scripts/` file), so the suite stays at the default weight and is kept fast.
- Distribution: everything under `plugins/soleur/` ships to plugin users. The wrapper is inert there by construction (it refuses unless `DOPPLER_PROJECT=soleur`, `DOPPLER_CONFIG=prd_terraform` and a bound token variable is present). Precedent: `cf-token-scope` ships with the same pins.
- Token names (names only, from repo text): `CF_API_TOKEN_ZONE_SETTINGS` (gh-pages-cert-renewal runbook), `CF_API_TOKEN_RULESETS` (ADR-130; Doppler `soleur` / `prd_terraform`), `CF_ZONE_ID`, `CF_ACCOUNT_ID`, `CF_API_TOKEN_AUDIT` ("dedicated read-only audit token", documented under Doppler `dev`, not `prd_terraform`).
- Class R text to change: item 2's last sentence ("No Cloudflare read wrapper exists ..."), item 4, the Credentials paragraph, the Boundary paragraph's "adding a vendor" clause. No edit needed in `go.md`, `operator-holds.md`, `delegation-verify.sh`, `AGENTS.rules.md`.

### CTO rulings and review disposition

Technical rulings D1-D6 and D9 are rows of `knowledge-base/project/specs/feat-one-shot-10479-cf-readonly-wrapper/decision-challenges.md` (each `Ruled by CTO agent, 2026-11-04`). Plan review (code-simplicity per mechanism, DHH, Kieran, CTO devex seat) and the deepen pass (security, test design, flow, docs) returned about 40 findings; the mechanical ones are applied in this revision, taste ones are rows D7, D8, D10, D11 and D12, and the item 4 clause cut proposed by two seats was ruled against by the CTO (D9) with the dissent recorded.

## Research Reconciliation - Spec vs. Codebase

| Task / comment claim | Reality | Plan response |
|---|---|---|
| B is "projected to ref/enabled/description/expression/ssl" | Section 9 Boundary treats vendor text as data never quoted into a transcript; CTO ruled expression and description are not printed | Print `ref`, `enabled`, `ssl` (enum-checked), and two derived booleans `mentions_app_host` / `mentions_lb_staging_host` computed inside the wrapper; the pass criterion in comment 6610203058 ("expression names app and lb-staging") stays decidable. Owner-visible deviation, recorded in D4 |
| "Credential used only inside the wrapper; fails closed on unexpected token source" | The bound tokens for A/B/C are Terraform-scoped and write-capable (ADR-130); the Credentials paragraph says a write-capable token makes a read `unverified` | CTO ruling D3/D6: accept for the three named tokens only because no read-only equivalent exists and the wrapper hardcodes GET; state the exception plainly; the stricter option is recorded dissent |
| E uses "an audit-log-read token"; field `when` | `CF_API_TOKEN_AUDIT` is documented under Doppler `dev`, not the pinned `prd_terraform`; the audit row time field is `action.time` | E reports `unverified - no-credential` when the variable is absent; no second Doppler config is added to Class R; the token's location is an owner-side fact |
| C reads `/pagerules` with `CF_API_TOKEN_RULESETS` | The comment says whether that token can read `/pagerules` is unverified; the docs require Page Rules Read or Zone Read / Write | Expected outcome may be `unverified - token-lacks-scope` (exit 11); a valid result, never worked around |
| Item 4: "scripts/** is never pushed" | Literal glob is root-anchored; `plugins/soleur/scripts/` is a different tree | CTO D2/D9: add one clause, pinned by a test row (final form per D9: `scripts/**` is any directory named scripts at any depth, and the bar does not cover exactly two named paths); the push basis is the ruling, not the unmerged clause |
| "Run the wrapper from a checkout matching origin/main" (item 2) | A new wrapper has no `origin/main` copy until merge | Not a defect: the live reads run after the owner arms and merges; a later stale checkout records `other: wrapper-drift` |

## Open Code-Review Overlap

One open scope-out names `plugins/soleur/scripts/` in its body: #11312 (monitor-pr-checks.sh hook-layer residue). Acknowledge: unrelated file and concern; it stays open. No other match for the files this plan edits or creates.

## User-Brand Impact

- **If this lands broken, the user experiences:** the CTO agent keeps handing the owner four technical Cloudflare reads as tasks (wrapper refuses wrongly), or reports a false origin-TLS fact in either direction: a false "strict" leaves the Cloudflare-to-origin hop unencrypted while that hop carries customers' API keys and session tokens; a false "flexible" could lead the owner to flip to strict against an origin that cannot serve it, taking the whole site down (certificate error 525). Customers feel the second as an outage and the first as a silent exposure.
- **If this leaks, the user's workflow is exposed via:** a Terraform-scoped Cloudflare API token (zone WAF, redirects, config rules edit) printed into an agent transcript, a command line or a child process environment, which would let a transcript reader change the production edge for every Soleur customer.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (ruled by CTO agent, 2026-11-04 (review), row D7):** `single-user incident`. The wrapper reads only the operator's own account and prints no customer data, but it holds write-capable Terraform-scoped tokens, so a leak could let a transcript reader change the production edge for every Soleur customer. The leak controls (stdin-only channel, empty environment for curl, jq and date, the xtrace refusal) lower the likelihood and do not change the threshold. CPO sign-off (2026-11-04, a CPO-agent step, not an owner step): approve-with-conditions. Conditions: (1) the failure modes here name both false-fact directions and the concrete leak outcomes (downgrade TLS, redirect traffic or switch off the WAF on `/api/keys` and `/api/auth`, i.e. customers' API keys exposed and an outage for all users); (2) the PR body leads with a plain worst-case paragraph and says the CTO agent's own recommendation is to wait for read-only tokens, which makes this PR a no-op today; (3) the write-token exception expires when the read-only token mint (#11857) lands (ADR-289 addendum); (4) CTO to confirm a revoke-and-rotate path for `CF_API_TOKEN_RULESETS` and `CF_API_TOKEN_ZONE_SETTINGS` tied to #11857 and who triggers it if a transcript is suspected to hold a token (open technical item owned by the CTO agent; no runbook exists yet); (5) CLO check of read E: done, legal-ok (2026-11-04, no personal data printed or registered, gdpr-gate not triggered; return to the CLO if the wrapper's scope widens).

Artifact / vector pairs for the review seat: (1) token printed on an error path, (2) token in argv or `ps`, (3) token inherited by the curl child from the `doppler run` export, (4) token traced under `bash -x`, (5) raw vendor body, jq / curl diagnostic or audit actor / IP echoed on a failure path, (6) a hostile `curl` earlier on PATH receiving the config channel.

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
| Records mapping table in the wrapper header | "output projected to status/counts/field-subset before it enters the transcript" | inferred - justification: a wrapper `ok` is not a Records `ok|bad` verdict; without the table the CTO would guess the pass criterion of comment 6610203058 (row D12) |
| `Unverified:` Class R Checks lines | — | inferred - justification: section 9 Records requires them while the live reads cannot yet run |

### Split Assessment

- Subsystems touched: 4 - `plugins/soleur/scripts`, `plugins/soleur/test`, `plugins/soleur/skills` + `agents` (text), `knowledge-base/engineering/architecture` (ADR addendum)
- Planned files: 8 | Estimated changed lines: ~650
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

### Phase 0 - Verify before building (documentation only; no Cloudflare call, no secrets)

1. Re-confirm, against current Cloudflare documentation (context7 / developers.cloudflare.com), the items the deepen pass could not verify, and cite the URLs with `verified: <date>` in the wrapper header: whether the single `GET .../settings/ssl` wraps its object in `result`; whether the entrypoint result carries a top-level `version`; `action_parameters.ssl` on `set_config` rules; the audit-log `since` / `before` requirement and the permission name for Audit Logs Read. Anything still unverifiable degrades as designed: a missing `.result` or field is `bad-response`, a missing optional field prints `null`, and `change-history` sends both `since` and `before`. If the audit endpoint cannot be confirmed at all, `change-history` ships as an `unverified - not-found` stub that sends no request, and the AC for E is limited accordingly.
2. Read all three C4 files in full and confirm the "No C4 change" conclusion.
3. Read the full `on:` / `paths:` / `types:` blocks of every workflow in `.github/workflows` for the Phase 5 push gate (the plan-time survey truncated long path lists).

### Phase 1 - RED: tests first (`cq-write-failing-tests-before`)

1. Create `plugins/soleur/test/cloudflare-readonly.test.sh` (see Test Scenarios and Guards 1-3). Design points the review demanded:
   - **Stub and scenario channel.** The wrapper calls `/usr/bin/curl` by absolute path, so the suite runs a COPY of the wrapper in which exactly one line (`CURL=/usr/bin/curl`) is rewritten to the stub's path by `sed`, with an exactly-one-match assertion; a census row asserts the production file contains the literal `CURL=/usr/bin/curl`, and there is no env override for the curl path. The curl child has an empty environment, so the stub reads its scenario (status, body, stderr canary) from fixture files next to itself (found via `dirname "$0"`), logs argv, stdin and `env` to files next to itself, and the suite writes new fixtures before each run. Tokens are exported as a direct command prefix (`CF_API_TOKEN_RULESETS=x "$BASH" "$SUT" ...`), not through a helper function (bash 5.2 prefix-assignment transience, see `cf-token-scope.test.sh`).
   - **`mutate` helper**, modeled on `scripts/assert-dependabot-drain.test.sh`: `mutate <label> <expected-failing-row-substring> <from> <to>` copies the wrapper, applies the edit, asserts `cmp` differs, `bash -n` passes and the match count is exactly 1 (anchored on a pinned unique literal, e.g. the refusing arm `*) die 64 "refused: unknown subcommand" ;;`), runs only the relevant row group, and counts the row as caught only when the suite fails with the NAMED row. Controls: the pristine copy exits 0; a benign edit (a comment) also exits 0. A recursion-guard env var stops the suite from re-running itself.
   - **Scans** use `grep -F` (the must-pass token contains `+` and `.`), and are fed a known-leaky and a known-clean file as controls. The curl census counts the invocation only (not `command -v curl` or a message string), with a 2-site fixture and a `command -v` fixture as controls. Each `src_lacks` has a `src_has` positive anchor.
   - **Clock.** `since` / `before` are asserted by regex and a range (now minus 7 days, plus or minus 2 minutes), never equality.
   - **Scratch.** `TMPDIR` points at an in-worktree scratch directory removed on exit.
   - Run once with the wrapper absent: it must fail (RED), not error out.
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
   - `[SD, "sd9", "this bar does not cover exactly two paths"]` (final form; the plan-phase row pinned a root-anchored phrase that no longer exists)
   - `[CTO, "ctoOwn", "plugins/soleur/scripts/cloudflare-readonly.sh"]`

   Structural tests (not PAIRS rows): (a) subcommand parity: slice item 2's text from "its four subcommands" to the next colon, take the backticked names, and assert BOTH sets are non-empty with length 4 and equal to the wrapper's `SUBCOMMANDS=(...)` array, the dispatcher's `case` labels and the `--list` output (comments stripped); (b) the Credentials clause lists exactly the three bound variable names (set equality); (c) item 4: the whole paragraph's `.github` mentions are pinned (the clause sentence names `plugins/**/scripts/**` and a `.github` token appears only in the pre-existing bar); (d) polarity: the Cloudflare clause (from "Cloudflare through" to "are not Class R") contains none of `permits`, `except`, `unless`, `but`; (e) add `plugins/soleur/scripts/cloudflare-readonly.sh` and `the wrapper sends GET only` to the item 2 `REQUIRED` strings and the item 4 clause anchor to `REQUIRED[4]`. Claim discipline: superset semantics mean a PAIRS row stays green when a second copy of its text survives, so the guarantee is "at least the item-scoped REQUIRED test goes red". The Guard 3 mutation rows are driven by a script that runs vitest against a sandbox copy of `plugins/soleur` (`PLUGIN_ROOT` is `import.meta.dir/..`), run manually at work time and recorded in the PR, not a standing test.

### Phase 2 - the wrapper (`plugins/soleur/scripts/cloudflare-readonly.sh`)

Header states: Jikigai-internal, inert outside this repo; the dated documentation citations; the invocation; the exit-code table; the Records mapping (below). Interface (CTO D4, simplified by D8, hardened at deepen):

- **Invocation** (direct exec; `doppler run -- bash` is forbidden by the Credentials paragraph): `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh <subcommand>`. The file is executable with `#!/usr/bin/env bash`. `SUBCOMMANDS=(ssl-mode config-entrypoint pagerules-ssl change-history)`; `--list` prints the four names and exits 0 (no credential, no network, no Doppler names). Anything else, or any extra argument or flag (`-X`, `--method`, `--data`, `--url`, `--path`, `--token-var`, `--since-days`, ...), exits 64 before any request; parsing uses `${1:-}` / `$#` so `set -u` never fires.
- **Prologue** (lint Rule A): `set -uo pipefail`; the xtrace refusal `case "$-" in *x*)` exiting 78 when any bound token variable is set; `export LC_ALL=C`; `PATH=/usr/bin:/bin` (for jq and date); the TLS-env `unset` block from `betterstack-query.sh`; `CURL=/usr/bin/curl`. No `set -x`, no `2>/dev/null`, no `eval`, no `mktemp`, no here-string or heredoc (`<<<`, `<<`).
- **Token source** (fail closed): `DOPPLER_PROJECT` must equal `soleur` and `DOPPLER_CONFIG` must equal `prd_terraform`, else exit 64 `refused: unexpected token source` (a mistake-guard; env can be forged). Binding by subcommand: `ssl-mode` -> `CF_API_TOKEN_ZONE_SETTINGS`; `config-entrypoint`, `pagerules-ssl` -> `CF_API_TOKEN_RULESETS`; `change-history` -> `CF_API_TOKEN_AUDIT` plus `CF_ACCOUNT_ID`. `CF_ZONE_ID` and `CF_ACCOUNT_ID` must match `^[0-9a-f]{32}$` (refusal names the variable, never the value). No fallback to `CF_API_TOKEN` or any other variable on any status. A missing or empty bound variable prints `unverified - no-credential (<VARIABLE NAME>)` and exits 10. The token is read into a non-exported variable, trailing whitespace is trimmed (a secret stored with a trailing newline is the commonest accident; same as `bc_ok`), then it must match `^[A-Za-z0-9._~+/=-]+$` (interior whitespace, quote or newline is refused, exit 64, naming only the variable).
- **Request chokepoint.** One function `cf_get <subcommand>` is the only curl call site: `out=$(/usr/bin/env -i "$CURL" --disable --noproxy '*' -X GET -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config - "$URL" < <(printf 'header = "Authorization: Bearer %s"\n' "$TOK") 2>&1)`; `--disable` is the first curl argument; the credential channel is the stdin redirect from a process substitution only (never a pipe: SIGPIPE 141 under pipefail; never a here-string: older bash writes it to a temp file). URL = `https://api.cloudflare.com/client/v4` plus a fixed template with only the validated ids substituted. No `-L`, `-d`, `--data*`, `--json`, `-T`, `-F`. Exactly one request per invocation: no retry and no second token. curl's own stderr is merged into `out` only so it can be reduced: it is never printed; a curl failure prints `curl exit <n>`. The status (last line of `out`) must match `^[0-9]{3}$`, else `bad-response`.
- **jq.** Every projection is preceded by a type guard (`jq -e '.success == true and (.result|type)=="<array|object>"'`) and uses `(.rules // [])`; a jq failure never prints jq's diagnostic (it quotes body fragments): its stderr is captured and reduced to the fixed message `bad-response (jq exit <n>)`. Never key on `.result | length`. This capture-and-reduce of curl and jq stderr is the one stated exception to "stderr is never discarded" (the wrapper's own diagnostics always reach stderr), pinned by Guard 2 row 7.
- **Vendor strings are checked before printing.** `value` and `ssl` must be in `off|flexible|full|strict` (else `other`); `id` and `ref` must match `^[A-Za-z0-9_-]{1,64}$` (else `invalid`); timestamps must match RFC 3339 (else `invalid`); change-history group keys must match `^[a-z_.]{1,64}$` (else `invalid`).
- **Projections.**
  - `ssl-mode`: `{subcommand, id, value, modified_on}`.
  - `config-entrypoint`: `{id, version, last_updated, rule_count, rules: [{ref, enabled, ssl, mentions_app_host, mentions_lb_staging_host}]}` in entrypoint order (`version` is `null` when absent); the host booleans test for the quoted whole token (`"app.soleur.ai"`, `"lb-staging.soleur.ai"`), so `app.soleur.ai.evil` does not match.
  - `pagerules-ssl`: `{active_rule_count, ssl_rule_count, ssl_rules: [{id, status, target_count, ssl, matches_app_host}]}`; URL patterns are never printed.
  - `change-history`: `GET /accounts/{acct}/logs/audit?since=<now-7d>&before=<now>&limit=50&direction=desc` with both times from a literal `date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ` / `date -u +...` (regex-checked before use; fail closed if date is not GNU); counts only, grouped by `action.type` and `resource.type`, plus `rows`, `oldest_time`, `newest_time` (`action.time`), and `truncated` (true when `rows` equals 50, since no end-of-results signal is documented; counts are then a lower bound). Never actor, IP or a raw row.
- **Output contract.** First stdout line `cloudflare-readonly: <subcommand> ok` or `cloudflare-readonly: <subcommand> unverified - <reason>`, then (ok only) the JSON projection. Messages are fixed, single-line and value-free; a response body is never printed.
- **Status map** (by HTTP status first; codes are collapsed, the reason token on the first line is the discriminator): 200 passing the type guard -> 0; 200 with `success:false` -> 14 `api-error`; 401 -> 11 `token-invalid`; 403 -> 11 `token-lacks-scope` (terminal, recorded, never retried, never another token); 404 anywhere -> 14 `not-found`; 429, 5xx, curl failure, timeout, any other non-2xx (400, 422, 3xx) -> 14 `upstream-error`; malformed JSON, wrong shape or jq failure -> 14 `bad-response`; missing token variable -> 10 `no-credential`; usage or refused source or token shape -> 64; xtrace -> 78.
- **Records mapping** (in the wrapper header, pointed to by the one `cto.md` sentence; it translates the wrapper verdict into a section 9 Records line and is where the pass criterion of comment 6610203058 lives):

| Check | Figure to record | Records verdict `ok` when | `bad` (forces a `Problem found` line) when |
|---|---|---|---|
| A `ssl-mode` | `value=<value>` | value is `strict` (the runbook's claim) | any other value |
| B `config-entrypoint` | `rule_count`, adopted rule `ssl`, count of other enabled rules with an `ssl` for the app hosts | `enabled_ssl_rules` is 1, that rule is `dcb85b75bc3c4f4aa2a8c13a080bf854` with `ssl=flexible`, and `rule_count` is 3 (dated snapshots; the host booleans are figures only, the wrapper cannot verify the expression is host-scoped, so the owner compares the live expression with `seo-config-rules.tf` before a flip go) | anything else, including `rule_count` 0 |
| C `pagerules-ssl` | `ssl_rule_count`, count with `matches_app_host` | no SSL rule matches the app host | one or more do |
| E `change-history` | `rows` and the top action types | `truncated` is false (evidence only, never a gate) | not used; a truncated window with no positive finding is `Unverified: ..., other: truncated-window` |

  Reasons to Records vocabulary: exit 10 -> `no-credential`; exits 11 and 14 -> `other: <reason token>`; exit 64 for a usage error records nothing (re-run correctly); exit 64 for a refused source or token shape -> `other: refused-source`; exit 78 -> `other: xtrace`; a checkout where `git diff origin/main -- <wrapper>` is non-empty -> `other: wrapper-drift` (fetch, rebase, re-diff, re-run); 429 / 5xx -> one re-run after a pause is allowed, the newest line governs. Each check is its own `Checked:` / `Unverified:` line with a stable key (`Cloudflare ssl-mode (A) #10479`, `... config-entrypoint (B) ...`, `... pagerules-ssl (C) ...`, `... change-history (E) ...`), so a later `Checked:` supersedes exactly its own `Unverified:`. None of A, B, C or E is a merge or deploy condition of this PR, so none becomes an `Operator-reserved:` hold here; a later TLS-change plan that names one writes the hold for that act.
- **Cloud (Devin) sessions:** the session-level `cloud-ack-before-secrets` obligation in the Credentials paragraph applies and is not implemented in the wrapper.

### Phase 3 - the text

1. `standing-delegation.md` section 9, via Edit: item 2 (replace the "No Cloudflare read wrapper exists" sentence), item 4 (one clause), the Credentials paragraph, the Boundary paragraph (Cloudflare added by ruling of 2026-11-04; any further vendor still needs a CTO ruling and a test row). Keep every existing REQUIRED string byte-identical (`never --latest-event`, the `--table` and `--grep` flag forms, `the exact parsed hostnames of items 2 and 3`, `Sentry reads use the read-only issue token only`, `if only a write-capable token is present the read is unverified` wording, `is never pushed under Class R`).
   - Item 2 clause: "Cloudflare through `plugins/soleur/scripts/cloudflare-readonly.sh` only, with one of its four subcommands `ssl-mode`, `config-entrypoint`, `pagerules-ssl` or `change-history`, as a status, a count or a field subset: the wrapper sends GET only, never prints a rule `expression`, a description, an actor or an IP, and a 403 is recorded as `unverified` and never answered by widening a token; its one host is the exact parsed `api.cloudflare.com`. The audit-log read is `unverified - no-credential` when `CF_API_TOKEN_AUDIT` is absent. The Cloudflare MCP server and the `cf-token-scope` skill are not Class R."
   - Item 4 clause: "Here `scripts/**` means the repository-root `scripts/` directory; `plugins/**/scripts/**` is not covered by this bar and is governed by the trigger-block read above."
   - Final form (decision-challenges.md D9): ONE reading, `scripts/**` is any directory named `scripts` at any depth, and this bar does not cover exactly two paths (`plugins/soleur/scripts/cloudflare-readonly.sh` and `plugins/soleur/test/cloudflare-readonly.test.sh`); the pin test compares the whole sentence up to "Never push main." by equality. It is an owner-visible widening by exactly two named files, not a clarification, and the root-anchored phrase above is deleted.
   - Credentials clause: "Cloudflare reads use only the token variable bound to the subcommand (`CF_API_TOKEN_ZONE_SETTINGS`, `CF_API_TOKEN_RULESETS` or `CF_API_TOKEN_AUDIT`); `CF_API_TOKEN` is never used and no other `CF_*` token is read; the wrapper starts curl, jq and date, each with an empty environment. The `ssl-mode`, `config-entrypoint` and `pagerules-ssl` subcommands use Terraform-scoped tokens that are write-capable because no read-only equivalent exists, so they are the one stated exception to the read-only-token rule for Cloudflare (`CF_API_TOKEN_AUDIT` is read-only); the wrapper sends GET only. An absent bound token makes the read `unverified`."
2. `plugins/soleur/agents/engineering/cto.md`: one sentence in "Class R first" naming the wrapper path and its four subcommands, pointing to the Records mapping in the wrapper header, and saying a 403 is recorded and never widened.
3. ADR-289 addendum (above).

### Phase 4 - verify (local, hermetic, one suite at a time)

`bash plugins/soleur/test/cloudflare-readonly.test.sh`; the Class R describe in `plugins/soleur/test/components.test.ts` (copy the run command from `scripts/test-all.sh`); the Guard 3 sandbox-copy drive; `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-capture-exit.py` and `scripts/lint-trap-tempfile-ownership.py` against the new file; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-guard-contract.py`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`; the fixture-relative-assert test; `plugins/soleur/test/opencode-adapter-install.test.ts`. The C4 tests (`c4-code-syntax`, `c4-render`) run only if a `.c4` file is edited. Confirm `test -x plugins/soleur/scripts/cloudflare-readonly.sh`.

### Phase 5 - ship phase: stop at the draft PR

1. Skip ready, merge, auto-merge, arming, postmerge, any workflow dispatch (including `mode=plan`), and any live wrapper run.
2. Push gate, before the first push and again before editing the PR: `git diff --name-only origin/main...HEAD` shows no path under `.github/` or root `scripts/`; read the `on:` / `paths:` / `types:` block of each workflow and match by hand. Plan-time survey: deploy / apply workflows trigger on `push` with `branches: [main]`, so a feature-branch push fires none of them; the `pull_request`-family set is `ci.yml`, `claude-code-review.yml` (accepted standing run), `pr-quality-guards.yml`, `secret-scan.yml`, `cla.yml` and `cla-evidence.yml` (`pull_request_target`), `cancel-superseded-pr-runs.yml`, `board-status-sync.yml`, `vendor-pin-verify.yml`, `tenant-integration.yml`, and `apply-sentry-infra.yml` (name says apply; read its PR job to confirm it only plans), plus path-gated ones (`gdpr-gate-self-test`, `skill-security-scan-corpus`, `infra-validation`, `sentry-audit-gate`, `check-inngest-bootstrap-build`, ...) that match only if the full `paths:` list names a changed path. Push only if none that matches deploys, applies infrastructure or spends money. The post-merge `push: main` workflows on `plugins/soleur/**` (`version-bump-and-release`, `web-platform-release`) are an arming-time matter for the owner, unchanged by placement because the required `standing-delegation.md` edit already triggers them. The plan-phase commit (plan, tasks, decision-challenges only, all under `knowledge-base/`) is committed locally and is not pushed by the planning run.
3. If the push gate fails, or the owner-facing doubt about `scripts/**` is unresolved: commit locally only, do not push, and report one plain sentence to the owner.
4. Before saving any PR body: `gh pr view 12061 --json closingIssuesReferences --jq '.closingIssuesReferences | length'` prints `0`; the body uses `Ref #10479` and `Ref #10205`, never `Closes`, `Fixes` or `Resolves`; re-check after saving. Body order, first items first: (1) the credential exception D6 (write-capable Terraform tokens used for reads, with the stricter alternative); (2) the item 4 clause, with the line "push eligibility does not depend on this clause" and the dissent; (3) the post-merge workflow note; (4) every standing `Unverified:` line.

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

Verified negatives: no edit under `.github/**` or root `scripts/**` (including `scripts/suite-durations.tsv` and `scripts/test-all.sh`); no SKILL.md `description:` edit (word budget untouched); no new skill or agent (component counts unchanged); `AGENTS.rules.md` untouched (no rule-body hash regeneration). Glob check: `plugins/soleur/scripts/*.sh` and `plugins/soleur/test/*.test.sh` both match existing files.

## Guard Contract

### Guard 1 - Request closure (GET only, closed allow-list, fixed host, fixed binary)

**Property.** The wrapper can send only an HTTP GET, through `/usr/bin/curl`, to one of four fixed URL templates on `api.cloudflare.com`, with the token bound to the subcommand, and nothing in argv, environment or a response selects the method, host, path, query, binary or token.

**Assembly.** Every path that can influence a request: the argument parser (flags, extra positionals), the dispatcher `case` and its refusing fallthrough arm, the `SUBCOMMANDS` array and URL templates, the single `cf_get` chokepoint (the only `curl` call site; a census with comments stripped asserts exactly one), the `--list` branch, the token-source checks (`DOPPLER_*`, binding table, shape and id regexes), environment variables read by the wrapper (any host or curl override), the curl flag set and its order, the config-channel line, the status map, and the jq projections (read-only). The chokepoint is `cf_get`; the parser, the dispatcher and the token binding are the other places a request could be steered, and each is covered below.

**Mutation matrix** (each edit to a copy of the wrapper, applied by `mutate` with an exactly-one-match check, must make the suite fail with the NAMED row):

| # | Edit | Must go RED via |
|---|---|---|
| 1 | change `-X GET` to `-X POST` in `cf_get` | per-subcommand wire assertion: recorded argv has exactly `-X GET` and none of `-d`, `--data*`, `--json`, `-T`, `-F`, for all four subcommands |
| 2 | add a fifth dispatcher arm after the four compliant ones (e.g. `raw) cf_get ssl-mode ;;`) | unknown-endpoint rows (`raw`, `ssl-mode/extra`, `../x`, `https://evil.example`, empty) refused with the curl marker absent; parity test (non-empty, length 4, equal across text, array, case labels and `--list`) |
| 3 | replace the dispatcher's refusing `*)` arm with a call into `cf_get` (the guard's own dispatch) | the same unknown-endpoint rows; and a floor: fewer than 4 subcommands x 3 outcomes exercised makes the suite fail ("0 checked" is RED) |
| 4 | add a second curl call site (retry on 403 with another token variable) | census == 1 (with controls); the 403 row asserts curl was called exactly once with the bound token only |
| 5 | make the host overridable (`${CF_API_BASE:-https://api.cloudflare.com}`) | a planted `CF_API_BASE=https://evil.example`: the recorded URL host must still be `api.cloudflare.com` |
| 6 | add `-L`, drop `--max-redirs 0`, or move `--disable` off argv position 1 | argv assertions (argv[1] is `--disable`; no `-L`; `--max-redirs 0` present) |
| 7 | accept an extra argument (`--method DELETE`, `-X DELETE`, `--data x`, `--since-days 3`) | non-GET and extra-argument rows: exit 64, curl marker absent, no request logged |
| 8 | delete the token-shape check (or the trailing-whitespace trim) | rows with a token containing a quote, a newline-plus-`url =` injection and interior whitespace: exit 64, curl marker absent; a token with a trailing newline is sent trimmed |
| 9 | swap the token binding, or add a `CF_API_TOKEN` fallback | distinct token per variable: the stdin log shows the bound one only per subcommand; with only `CF_API_TOKEN` exported the result is exit 10 and the marker is absent |
| 10 | delete the `DOPPLER_PROJECT` / `DOPPLER_CONFIG` pin | `DOPPLER_CONFIG=dev` and unset rows: exit 64, marker absent |
| 11 | call `curl` by name instead of `/usr/bin/curl`, or add an env override for the curl path | census: the production file contains the literal `CURL=/usr/bin/curl` and no override variable; the sandbox rewrite `sed` matches exactly once |
| 12 | map 403 to `ok` (or to a retry) | the 403 row on all four subcommands: first line `unverified - token-lacks-scope`, exit 11, curl called once |

**Harness rows.** Suite edit that must go RED: make the stub `curl` write its log to `/dev/null`; the floor "recorded argv is non-empty and carries the expected URL" fails instead of passing vacuously. Must-PASS inputs that are not the canonical: a valid 200 whose `rules` are reordered and carry unknown extra fields, a `pagerules` body with one SSL action and one non-SSL action, a body with `rules` omitted, a zone id that differs from the canonical fixture, a token with a trailing newline, and a benign comment edit of the wrapper (the suite must not red on every edit).

**Anchor.** The allow-list lives in the wrapper and its set is pinned in `components.test.ts` and section 9, which one diff could edit together (consistency, not integrity). The controls outside the commit are item 2's run-time rule (`git fetch origin main`, then `git diff origin/main -- <wrapper>` empty before any run) and the owner arming the PR; the review seat compares the wrapper's curl flag set to this table.

### Guard 2 - Credential non-disclosure

**Property.** No byte of any Cloudflare token reaches stdout, stderr, a command line, a file, or the environment of any child process; it travels only on curl's stdin config.

**Assembly.** Every output and propagation path: each `printf` / `echo` site, the `die` handler, `--list`, usage text, every error branch (401, 403, 404, 429, 5xx, bad JSON, wrong type, `success:false`, no-credential, shape refusal, source refusal), the jq invocations and jq's own stderr (it quotes body fragments), curl's own stderr, the curl child's environment and binary, the config-channel construction (process substitution only), and `set -x` / `bash -x`. Chokepoints: one `emit` for stdout, one `die` for stderr with fixed strings, the single `/usr/bin/env -i` curl invocation, and the config-channel line.

**Mutation matrix:**

| # | Edit | Must go RED via |
|---|---|---|
| 1 | add `echo "$TOK"` to the 403 branch (and, separately, to the success branch) | combined stdout+stderr `grep -F` scan over every subcommand x every status: fake token absent (the scan itself is controlled with a leaky and a clean file) |
| 2 | pass the credential as `-H "Authorization: Bearer $TOK"` in argv | argv log contains no token, `Bearer` or `Authorization`; stdin log contains the token exactly once, only there |
| 3 | drop `env -i` (plain `curl`) | stub curl's `env` dump: no token, no other `CF_*` token, no non-TLS planted canary variable (the TLS-variable unset block is an equivalent mutant for proxy / CA canaries and is not used as evidence) |
| 4 | remove the jq type guard / print the raw body on `bad-response` (stub body is a wrong-type JSON string containing a token-shaped canary) | stdout+stderr scan: the canary is absent and the message is the fixed `bad-response (jq exit <n>)` |
| 5 | remove the xtrace refusal (and, separately, add `set -x`) | the suite runs the wrapper under `bash -x` with a token set: exit 78 and no token in output; source guard: `set -x` absent |
| 6 | add `2>/dev/null`, `mktemp`, a here-string or a heredoc to the wrapper | source guards (each with a positive anchor): none present |
| 7 | print curl's merged stderr (stub curl writes the token-shaped canary to its stderr) | stdout+stderr scan: the canary is absent and the message is `curl exit <n>` |

**Harness rows.** Suite edit: replace the fake token with one the scan helper would not find if printed in a different case, then assert the helper still flags a deliberately injected leak (the detector is live). Must-PASS: a token containing every permitted punctuation character (`._~+/=-`) is sent on the config channel intact (scan with `grep -F`).

**Anchor.** `lint-shell-trace-credential-refusal.py` (Rules A, B, E) and its baselines run in CI independently of this suite and cannot be edited by the suite's author without showing in the baseline files.

### Guard 3 - Class R closed set (text, agent, pin test)

**Property.** Section 9 cannot gain a Cloudflare read, host, token or subcommand beyond the four named, and cannot lose the GET-only, no-expression, no-widening, not-Class-R-MCP or root-anchored `scripts/**` limits, without a named test going red.

**Assembly.** Item 2, item 4's clause, the Credentials paragraph, the Boundary paragraph, `cto.md` "Class R first", the wrapper's `SUBCOMMANDS` array and dispatcher labels, and the `PAIRS` table with `PAIRS_FLOOR`. The structural parts are the per-item `REQUIRED` strings and the set-equality and sentence-slice tests (subcommand parity; Credentials variable set; item 4 `.github` pin; polarity). The member list (the anchors) drifts; those tests do not.

**Mutation matrix** (driven manually or by script against a sandbox copy of `plugins/soleur`, at work time):

| # | Edit | Must go RED via |
|---|---|---|
| 1 | add a fifth name to item 2's subcommand list | subcommand parity against the wrapper array |
| 2 | change the host to a wildcard or add a second host | the `api.cloudflare.com` anchor and item 2 `REQUIRED` |
| 3 | delete "the wrapper sends GET only" from item 2 | item 2 `REQUIRED` (the PAIRS row alone may stay green: another copy exists in the Credentials clause) |
| 4 | widen the item 4 clause to include `.github`, in the clause or the next sentence | the item 4 whole-paragraph `.github` pin |
| 5 | add a fourth variable to the Credentials clause, or drop one | Credentials variable-set equality |
| 6 | insert "but" / "unless" so a Cloudflare limit becomes negated | polarity check on the Cloudflare clause |
| 7 | empty the Cloudflare rows from `PAIRS` | `PAIRS_FLOOR` (59) |

**Harness rows.** Suite edit: make the item 2 slicer return the whole file; the parity test must go RED (backticked tokens elsewhere in item 2 would otherwise pass silently), and an empty slice must go RED because of the non-empty assertion. Must-PASS: the Cloudflare clause re-flowed across lines with different whitespace still passes.

**Anchor.** The pin anchors live in the same file family as the text, so one diff can edit both; the independent controls are the user-impact-reviewer seat and the owner arming the PR (stated residual, same as the 2026-11-03 Class R pin).

## Observability

```yaml
liveness_signal:
  what: the wrapper's first stdout line "cloudflare-readonly: <subcommand> ok|unverified - <reason>" plus an exit code (0 ok, 10 no-credential, 11 token, 14 other, 64 refused, 78 xtrace)
  cadence: on demand, once per Class R read the CTO agent runs
  alert_target: the calling agent's transcript; the verdict becomes a "Checked:" or "Unverified:" line in the plan's "## Class R Checks" section and the PR body
  configured_in: plugins/soleur/scripts/cloudflare-readonly.sh (emit function and Records mapping header) and standing-delegation.md section 9 Records
error_reporting:
  destination: stderr of the wrapper with fixed value-free messages, plus the exit code; curl and jq diagnostics are captured and reduced to "curl exit <n>" / "jq exit <n>"; no Sentry client (operator-side tool, no server runtime, no silent fallback exists to mirror)
  fail_loud: true
failure_modes:
  - mode: bound token variable absent or empty
    detection: stdout "unverified - no-credential (<VARIABLE NAME>)", exit 10
    alert_route: "Unverified:" line in Class R Checks (reason no-credential); epic stays open
  - mode: token lacks scope or is invalid (403 / 401)
    detection: stdout "unverified - token-lacks-scope" or "token-invalid", exit 11, curl called exactly once
    alert_route: "Unverified:" line (other: <reason>); the token is never widened
  - mode: Cloudflare unreachable, 429 / 5xx, malformed or wrong-type body, success:false 200, any 404
    detection: exit 14 with a fixed reason token
    alert_route: "Unverified:" line; retriable reasons are re-run (one re-run after a pause, the newest line governs)
  - mode: wrapper edited after the owner reviewed it
    detection: "git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh" is non-empty before a run (item 2 rule)
    alert_route: "Unverified:" line with "other: wrapper-drift"; fetch, rebase, re-diff, re-run
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
    evidence: plugins/soleur/scripts/cloudflare-readonly.sh (no mktemp, no redirect to a file, no here-string or heredoc; source guards in the suite)
    defends_against: nothing is stored, so there is no stored copy to protect
    does_not_defend: process memory of the calling shell during the call, readable by a same-user process
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no store exists
in_transit:
  - connection: operator checkout (agent shell) -> api.cloudflare.com
    enforced_at: plugins/soleur/scripts/cloudflare-readonly.sh (cf_get; https scheme fixed in the URL template, absolute /usr/bin/curl, --max-redirs 0, TLS-env unset block)
    tls: https, curl default minimum (TLS 1.2+), certificate verification left at the curl default
    cert_verification: on
    does_not_defend: a compromised local trust store or a hostile same-host process (the TLS-subversion env vars are unset, the trust store itself is not pinned); Cloudflare itself
    disclosed_as: not-publicly-claimed
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-04 (rows D1-D6, D9): add Cloudflare for four reads through one GET-only wrapper at `plugins/soleur/scripts/cloudflare-readonly.sh`; per-subcommand token binding with an empty curl environment; expression, description, actor and IP are never printed; 403 is `unverified` and recorded; the Terraform-scoped (write-capable) tokens are accepted for A/B/C only, stated plainly, with the stricter alternative recorded as dissent. Legal: CLO checked read E on 2026-11-04 and ruled legal-ok; audit rows are reduced to counts inside the wrapper and no actor or IP is printed or stored, so no personal-data processing is added and no canonical regulated-data surface is touched. Product / UX: no user-facing surface, so no wireframe gate and CPO sign-off given with conditions (threshold `single-user incident`; see the threshold decision). Operations / Finance: no spend, no new vendor account.

## Acceptance Criteria

### Pre-merge (PR, draft)

- [ ] `plugins/soleur/scripts/cloudflare-readonly.sh` exists, is executable (`test -x`), has the `#!/usr/bin/env bash` shebang, passes `lint-shell-trace-credential-refusal.py`, `lint-shell-capture-exit.py`, `lint-trap-tempfile-ownership.py`; has exactly one curl call site, the literal `CURL=/usr/bin/curl`, no `set -x`, no `2>/dev/null`, no `mktemp`, no `<<`; its header documents the direct-exec `doppler run` invocation (never `-- bash`), the exit-code table and the Records mapping; `--list` prints exactly the four subcommand names with no credential and no network.
- [ ] `bash plugins/soleur/test/cloudflare-readonly.test.sh` is green, the pristine and benign-edit controls are green, and each mutation row of Guards 1 and 2 turns it RED with the named row (including the four asked rows: non-GET refused, unknown endpoint refused, token never printed, 403 gives `unverified`); the suite uses no network, no `prd` configuration (the `DOPPLER_*` values are inert strings) and writes only under an in-worktree scratch directory it removes on exit; `git status --short` shows no scratch files afterwards.
- [ ] Section 9 item 2 no longer says "No Cloudflare read wrapper exists"; item 2 carries the Cloudflare clause with the exact anchors in Phase 3; item 4 carries the root-anchored clause; the Credentials and Boundary paragraphs are updated; every pre-existing REQUIRED string is unchanged; section 9 still names exactly six Class R acts.
- [ ] `components.test.ts` has the 11 listed PAIRS rows (10 `sd9`, 1 `ctoOwn`), the structural tests (a) to (e), and `PAIRS_FLOOR` equal to 59; the file is green; the Guard 3 sandbox-copy drive turns the named test red for each of its 7 rows and the results are recorded in the PR.
- [ ] `cto.md` carries the Cloudflare sentence; ADR-289 carries the 2026-11-04 addendum with status `adopting` unchanged; `c4-count-parity` is green and `.c4` files are untouched (or, if work finds a falsified element, edited and the C4 tests green).
- [ ] `technical-ruling-gate.sh --branch` prints `[PASS]`; `lint-guard-contract.py` and `lint-orphan-test-suites.sh` pass.
- [ ] The diff touches no path under `.github/` or root `scripts/` (`git diff --name-only origin/main...HEAD`).
- [ ] No workflow was dispatched, no live Cloudflare call was made, no Doppler read happened, PR #12061 is still a draft and unarmed, and `closingIssuesReferences` is `[]` before and after the last body save.

### Post-merge (owner, separate, not part of this run)

- Owner arms and merges; then the CTO agent runs A, B, C, E through the wrapper from a checkout whose `git diff origin/main -- <wrapper>` is empty, records one `Checked:` or `Unverified:` line per check with the stable keys, and posts token-free figures on #10479. If a reason needs a person (a missing scope for C, or the audit token's location for E), at most one headless `action-required` issue with first line `Unverified read epic: #10479` is filed per section 9 Records.
- Later and separately: a `_dev` key-rotate `mode=plan` dispatch (needs the owner's typed go naming the command) and the credential mint (needs the owner's named go). The audit token's location (`dev` versus `prd_terraform`) is an owner-side fact to confirm before E can be anything but `unverified - no-credential`.

## Test Scenarios

Command-to-terminal rows (a stub `curl` whose path is rewritten into the sandbox copy, reading status / body / stderr canary from fixture files, logging argv, stdin and `env`; real `jq`; fake distinctive tokens):

1. `ssl-mode`, 200 with `value:"strict"` -> `ok`, URL `.../zones/<zone>/settings/ssl`, argv[1] is `--disable`, argv has `-X GET`, bound token on stdin only; `value:"weird"` -> printed as `other`.
2. `config-entrypoint`, 200 with three rules (reordered, extra fields) -> rules in order with `ref`, `enabled`, `ssl` and the two host booleans (`app.soleur.ai.evil` does not set `mentions_app_host`); no expression text in output; a body with `rules` omitted -> `rule_count: 0`; a `ref` with shell metacharacters -> `invalid`.
3. Any 404 (entrypoint, pagerules, audit, ssl) -> `unverified - not-found`, exit 14.
4. `pagerules-ssl`, 200 with two rules (one SSL action, one not) -> counts and `ssl_rules` of length 1; patterns not printed.
5. `change-history`, 200 with rows -> counts by action / resource type, `rows`, `oldest_time`, `newest_time`, `truncated` true at 50 rows; no actor / IP / raw row; the URL carries both `since` and `before` within the clock range; bound token or `CF_ACCOUNT_ID` absent -> exit 10 naming the variable.
6. 403 on each of the four subcommands -> `unverified - token-lacks-scope`, exit 11, curl called once, no second token tried.
7. 401 -> exit 11 `token-invalid`; 429, 5xx, 400, 3xx, curl failure -> exit 14; malformed JSON, wrong-type body (string containing a token-shaped canary), `{"success":true,"result":null}` and a non-numeric status line -> exit 14 `bad-response`, canary absent; 200 `success:false` -> exit 14 `api-error`; stub curl writing a canary to stderr -> exit 14 `curl exit <n>`, canary absent.
8. Refusals before any request: unknown subcommand, empty, `ssl-mode extra`, `-X POST`, `--method DELETE`, `--data x`, `--url https://evil.example`, `--since-days 3`, `../x`; `DOPPLER_CONFIG=dev`; `CF_ZONE_ID` non-hex; a token with a quote, a newline-plus-`url =` injection or interior whitespace; a token with a trailing newline is accepted trimmed.
9. Environment: with `CF_API_TOKEN`, a second Cloudflare token and a non-TLS planted canary exported, the stub curl's `env` dump is empty of all of them; a planted `CF_API_BASE` does not change the host; with only `CF_API_TOKEN` exported the result is exit 10.
10. Token hygiene: for every subcommand x every status above, stdout+stderr contain neither token nor canary (`grep -F`); the argv log contains neither token nor `Authorization`; under `bash -x` with a token set the wrapper exits 78.
11. Source guards (each with a positive anchor): no `set -x`, no `2>/dev/null`, no `mktemp`, no `eval`, no `<<`, exactly one curl call site (comments stripped, with controls), `CURL=/usr/bin/curl` present, `test -x` on the production file.
12. Mutation harness: `mutate <label> <expected-failing-row> <from> <to>` over a copy of the wrapper, one row per matrix line above, each asserting the suite fails with the named row; pristine and benign-edit controls pass; anti-vacuity floors on exercised subcommand x outcome count and on non-empty recorded argv.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- **Item 4 is read by the very change that clarifies it.** The clause ships only on merge, so push eligibility rests on the glob's plain any-depth reading plus the exemption of exactly two named paths by CTO ruling D2/D9, and not on text this PR adds. The PR body says "push eligibility does not depend on this clause" and lists the dissent. If the owner does not accept the two-path exemption, the fallback is: commit locally, do not push, one plain sentence to the owner.
- **Credential exception (D6).** `CF_API_TOKEN_RULESETS` and `CF_API_TOKEN_ZONE_SETTINGS` are write-capable; the wrapper's safety is structural (hardcoded `-X GET`, absolute curl path, fixed templates, empty curl environment, drift guard), not a scope property. Revisit if the wrapper can be driven to send a non-GET or a read-only token is minted. Dissent recorded in D6; it is the first item in the PR body.
- **`pagerules` may be a permanent 403** if `CF_API_TOKEN_RULESETS` lacks Page Rules read (docs: Page Rules Read or Zone Read / Write). That is a valid `unverified - token-lacks-scope` result recorded as its own `Unverified:` line; the token is not widened. Whether C is required to close #10479 is the owner's and CTO's call; the CTO's own comment names a 403 as a recordable outcome.
- **Distribution.** The wrapper ships to plugin users; it is inert there. Its header says "Jikigai-internal"; `--list` prints no Doppler project or config names. The zone and account ids come from the environment, never hardcoded.
- **Class R item 6 says "no write outside the worktree"**, stricter than the repo's usual `mktemp -d` in `/tmp`: the suite points `TMPDIR` at an in-worktree scratch directory removed on exit. Existing suites are unchanged.
- `doppler run` exports every secret in `prd_terraform`; never rely on a variable being unset by the caller. The curl child gets an empty environment via `/usr/bin/env -i`; jq, date and bash still inherit, and Property 2 is scoped to the curl child plus output channels. A re-exec of the whole wrapper under `env -i` was considered and left as an optional hardening (taste).
- `date -d` is GNU-only: the wrapper regex-checks the result and fails closed if date is not GNU.
- The single stated exception to "stderr is never discarded" is curl and jq diagnostics, which are captured and reduced because they can quote body fragments; the wrapper's own messages always reach stderr.
- Cloudflare documentation facts are re-confirmed in Phase 0 with dated citations; unverified facts degrade to `unverified`, never to a guess (the #1810 failure class).
- Cloud (Devin) sessions: the session-level acknowledgement before any secrets read still applies and is not implemented in the wrapper; an unanswered or headless session records the read as `unverified` with reason `no-session`.
- Section 9 Records: each standing `Unverified:` line is copied into the final report and the PR body before the plan is archived.
- Deferral tracking: nothing is deferred by this plan that is not already tracked. Check D and the other open items are tracked on #10479; the audit-token location question is an `Unverified:` line and a PR-body item, and no new issue is filed in this run (owner limit on trackers).

## Class R Checks

Unverified: Cloudflare ssl-mode (A) #10479, other: the read wrapper exists only in this unmerged draft PR and the owner has not armed it, 2026-11-04T08:12Z
Unverified: Cloudflare config-entrypoint (B) #10479, other: the read wrapper exists only in this unmerged draft PR and the owner has not armed it, 2026-11-04T08:12Z
Unverified: Cloudflare pagerules-ssl (C) #10479, other: the read wrapper exists only in this unmerged draft PR and the owner has not armed it, 2026-11-04T08:12Z
Unverified: Cloudflare change-history (E) #10479, other: the read wrapper exists only in this unmerged draft PR and the owner has not armed it, 2026-11-04T08:12Z
