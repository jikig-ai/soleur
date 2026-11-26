---
title: "fix(cf-token-scope): zone-rest settings PATCH row sends a fixed JSON probe body"
type: fix
date: 2026-11-26
slug: fix-cf-token-scope-zone-rest-settings-probe-body
branch: feat-one-shot-12931-zone-rest-settings-probe
issue: 12931
closes: none
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(cf-token-scope): zone-rest settings PATCH row sends a fixed JSON probe body

Ref #12931 (epic stays open; the PR body uses `Ref #12931`, never `Closes`).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-26
**Sections enhanced:** Proposed Solution (steps 3, 5, 6, 7), Implementation Phases (Phase 1 step 1, 3; Phase 3
step 4), Guard Contract (Guards 2, 3), Acceptance Criteria (AC5, AC10, AC12), Test Scenarios, Research Insights.
**Agents used:** `soleur:engineering:review:security-sentinel`, `soleur:engineering:review:test-design-reviewer`,
`soleur:engineering:review:architecture-strategist`, and a verify-the-negative sweep (standard tier). It confirmed
all 10 current-code claims and found no stale references to items cut at plan review. Gates 4.6, 4.7, 4.8, 4.11
and 4.12 pass; 4.5, 4.55, 4.9, 4.10 and 4.13 do not trigger. All cited rule ids, PRs and the issue were verified
live. This is a proportionate fan-out rather than every agent: the plan-review panel (DHH, Kieran,
code-simplicity, CTO) had already run on the same text.

### Key Improvements

1. **The collision guard no longer passes on an empty list** (security). An authorized settings control with an
   empty `result` is degraded and makes the run inconclusive. The list reaches jq on stdin, not argv. The mock's
   GET default becomes a realistic non-empty list.
2. **The mutant helper cannot pass on a broken mutant** (test-design). `run_mut` checks the copy with `bash -n`,
   applies each replacement exactly once, accepts several anchor/replacement pairs, and asserts the guard's own
   refusal message. M11a asserts the collision message, so the fail-closed exit 2 cannot stand in for it.
3. **The dry-run output stays copy-pasteable** (architecture). Each write row prints its
   `w_body="$INVALID_BODY"` or `w_body="$SETTINGS_PROBE_BODY"` line before its recipes.
4. **Tighter static guard.** The settings-json row must use `PATCH`. The body may carry no keys besides
   `items` and `id`/`value`. The guard is unconditional on profile, which the plan now states.
5. **Counted, not vacuous, checks.** Per-URL body counts are exact (2 and 2). AC2 gets its own test row. The
   `w_body` backstop is a closed set over write forms. All rows are labelled `unit`. The `MIN_ASSERTIONS` rule
   is stated.

### New Considerations Discovered

- `mig_fatal`'s read-back prints `probe_id_listed` for an array result, the one fact a CTO re-ruling needs after a
  settings 2xx.
- `MIG_SETTINGS_CTRL_OK` is a separate flag, so one variable does not carry both "list" and "control passed".

## Overview

The `zone-rest` migration profile of the cf-token-scope probe returns `verdict=inconclusive`, because the
`PATCH /zones/<zone>/settings` endpoint parses JSON before it checks authorization: the non-JSON invalid body
gets `400` (code 6007) for every token, so the deny-control `403` can never be observed on that row. This plan
gives that single row a second fixed literal body (valid JSON that names a nonexistent, probe-prefixed setting
id), per the binding CTO ruling of 2026-11-26, with guards that keep every other row on the non-JSON body.

The fix unblocks the `zone-rest` staged probe that `swap-0b` runs before it swaps (runbook Phase 2 Step 3). The
swap and the `zone-rest` dispatch stay outside this PR: each needs its own typed authorization naming the command.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (checked 2026-11-26) | Plan response |
|---|---|---|
| The settings PATCH row's deny control got 400, not 403 | Confirmed by the code path: `cf-token-scope.sh` write loop (`# 3. Write probes`) reports `inconclusive (deny control … got 400, not 403 …)` and `continue`s; the grant is never probed | Fix at the body, not the verdict logic: the 403 control rule (header rule 3) stays unchanged |
| The body is `{"items":[{"id":…,"value":…}]}` | The current Cloudflare API reference for `bulk_edit` lists the body as a bare array of `{id, value}`; the `items` wrapper is the historic v4 / `cloudflare-go` wire form. Not verified on the wire | Keep the CTO literal. The deny control sends the IDENTICAL body and must get 403, which proves authorization runs before schema validation for that body, so the grant's 400 means "authorized" whichever schema the endpoint enforces (see Technical Considerations) |
| The endpoint is current | `bulk_edit` is deprecated (2025-04-23), end of life 2027-03-31 (extended from 2026-09-15); replacement is the per-setting `PATCH /zones/<z>/settings/<id>` | In scope only as a Sharp Edge: after EOL the row answers non-403 on the control and reads `inconclusive` (fail-closed). The CTO rejected the single-setting endpoint because it names a real setting |
| Only the settings row needs a JSON body | `zones/<zone>/bot_management\|PUT` already passes with INVALID_BODY (measured) | bot_management keeps `invalid`; every redirects-dns row keeps `invalid` |
| Test counts "M1" and "single-site D12c" | `cf-token-scope.test.sh`: M1 asserts every write carried `INV_BODY` (awk over the write log); D12c asserts exactly one `--data-binary "$INVALID_BODY"` site and its (F) lint requires that exact word; `INV_BODY` is parsed from source in the M-series preamble, AFTER D12c | One preamble block above the D12c single-site assertion holds `INV_BODY`, `SET_BODY` (both parsed from source), the hardcoded `WANT_SET_BODY` and `D12C_WRITE_ANCHOR`. M1/M2 read the two bodies; D12c's single-site count reads the anchor (confirmed by the CTO devex review, 2026-11-26) |

## Research Insights

**Premise Validation.** #12931 is OPEN (`infra(cloudflare): migrate Terraform to the new Soleur account and zone
after the 2026-11-18 registration move`). Collision pre-check (`collision-precheck.sh 12931`, exit 10) found two open
PRs naming it: #13076 is this branch's own draft PR; #12958 (`feat-one-shot-12937-zot-bridge-handshake`, tunnel
re-home) touches no `cf-token-scope` file. No live duplicate. The cited script, rows and tests all exist on this
branch (forked from `origin/main` at `27e84d0b4f`). The baseline suite is green: `bash
plugins/soleur/test/cf-token-scope.test.sh` → `320 passed, 0 failed` (floor `MIN_ASSERTIONS=320`, so the floor
must rise with the new assertions).

**Property List (Phase 0.6b).**

- P1. The `zone-rest` settings PATCH row reaches a 403 on its deny control, so its grant probe runs and its 400
  can count as authorized.
- P2. No write probe can mutate a real zone setting: the JSON body names only setting ids that cannot exist.
- P3. Every row other than the settings PATCH row keeps sending exactly INVALID_BODY.
- P4. A table or body edit that breaks P2 or P3 refuses the run (exit 2) before any write is sent.
- P5. Any 2xx on either body stays a fatal abort with a read-back (exit 4).
- P6. Docs and the dry-run say what the tool sends.

**Cut List.** Nothing cut. Every mechanism in the ruling maps to a property, and no existing mechanism covers it:
the INVALID_BODY JSON tripwire (`INVALID_BODY parses as JSON`) is the inverse check and cannot validate a JSON body;
the D12c allowlist pins the curl site shape, not body values; M0/M1 pin the one literal only. Considered and kept:
the per-row `body-kind` field versus a URL-keyed body switch. The ruling fixes the field; the URL check is the guard
on it, not a replacement.

**Relevant files.**

- `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`: header invariant 1 (`MIGRATION PROFILES` block),
  `readonly INVALID_BODY`, `MIG_WRITE_REDIRECTS_DNS` / `MIG_WRITE_ZONE_REST` (5-field rows), `MIG_CTRL_ZONE_REST`
  (the authorized settings GET control), the INVALID_BODY runtime tripwire, the migration dry-run block, `mig_req`
  (the ONE write curl site), `mig_fatal`, the control loop (`# 1. Known-present controls`), the write loop
  (`# 3. Write probes`), `usage()`.
- `plugins/soleur/test/cf-token-scope.test.sh`: curl mock (write branch answers 400 to a granted token and 403
  otherwise, keyed on URL and token only; it ignores the body, which is how the live 6007 behavior stayed
  unmodeled), `MOCK_ZSET` (GET `*/settings`, default `{"success":true,"result":[]}`), `tbl_n` row counter (counts
  quoted lines, unaffected by a 6th field), D-pc dry-run row counts, D12c (P/I/S/F/U layers, `D12C_CANON`,
  `D12C_FLAGS`, `D12C_WRITE_ANCHOR`, mutants), M0-M10, U1, `MIN_ASSERTIONS`.
- `plugins/soleur/skills/cf-token-scope/SKILL.md`: `## Usage` intro ("only with a fixed body that cannot
  validate"), `## Migration profiles (#12931)` bullet "One fixed invalid body", the row table, exit code `4`.
- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: `### Write-probe each token
  before its phase (CTO L49)` bullet "one fixed invalid body literal that can never validate … never a valid body".
- Not affected (checked): `widen-playbook.md`, ADR-130/213/236 (name the skill only), `knowledge-base/legal/*`,
  `plugins/soleur/README.md` row, the cursor SKILL pointer, `tests/scripts/test-cf-account-migration-runbook.sh`
  (pins `echo "probe=$PROFILE verdict=pass"` exactly and `--staged`/profile names, which survive),
  `tests/scripts/test-cf-account-migration-bootstrap.sh` (stubs the tool), `tests/scripts/test-argv-bearer-sweep.sh`.
- Consumer: the bootstrap's `run_scope_probe` (swap-0b) runs `bash "$tool" --profile zone-rest --staged` and
  requires exit 0 AND `grep -qx "probe=zone-rest verdict=pass"`. Only the archived copy is tracked here
  (`knowledge-base/project/specs/archive/20261120-013510-feat-one-shot-12931-cf-account-migration/bootstrap.sh`,
  `run_scope_probe`); the live copy is untracked. Neither the exit codes nor that line change.
- CI: `scripts/suite-shard-legs.tsv` puts the suite in shard 3 of `test-scripts`; `scripts/test-all.sh` discovers
  `plugins/soleur/test/*.test.sh`. Local: `bash plugins/soleur/test/cf-token-scope.test.sh` (needs bash >= 5.2
  and jq).

**Measured shape for the D12c canon (bash 5.3.20 `--pretty-print`).** The planned `mig_req` prints as three
separate lines: `w_body="$INVALID_BODY"`, `w_body="$SETTINGS_PROBE_BODY"` and one curl line ending
`--data-binary "$w_body" -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2> /dev/null || true)"`;
the dry-run recipe line prints `--data-binary \"\$w_body\"`. So the body assignments are parse-visible lines a pin
can quantify over, separate from the curl lines D12c already pins.

**Institutional learnings applied.**

- `2026-07-24-stubbed-uniform-fixture-hides-per-endpoint-response-shape.md`: the curl mock ignores the body, which
  is why the live 6007 was invisible. The mock must model the settings endpoint's JSON-first parse (non-JSON body →
  400 6007 for every token), so the pre-fix code reds the suite.
- `2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md`: pin the endpoint to the official
  reference and confirm live. The reference was read (above); the live confirmation is the post-merge staged run.
- `2026-10-11-a-fake-that-ignores-its-selectors-lets-every-selector-mutation-pass.md` and
  `test-failures/2026-10-29-curl-mock-confused-proxy-targets.md`: the mock already refuses unmodelled flags (U1);
  its body log must record the exact body per request, and the per-row body assertion must fail on an empty log.
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` and
  `2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md`: each new
  guard gets its own mutant, run against a temp copy, asserting its own reason.
- `2026-10-28-a-read-only-census-allowlist-widened-for-one-script-was-widened-for-all.md` and
  `2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential.md`: the JSON allowance is scoped
  to one URL and checked at runtime against the live settings list, not admitted by the literal's text.
- `2026-05-29-blocking-gate-fail-closed-key-parse-and-redos-line-cap.md`: an unparsable body or a missing control
  list fails closed (exit 2, or the row skipped as inconclusive), never falls through to a write.

**External docs.** Cloudflare `bulk_edit` reference
(<https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/bulk_edit>): permission "Zone
Settings Write" (or Workers Routes Write); no documented error for an unknown setting id, no documented partial
application, no documented parse/authorize order (6007 and 9109 are observed, not documented). Deprecations page
(<https://developers.cloudflare.com/fundamentals/api/reference/deprecations/>): EOL 2027-03-31. Nothing in the docs
rules out a 200 no-op for the grant token, which is why 2xx stays fatal and the CTO dissent stands.

**Functional overlap.** `soleur:engineering:discovery:functional-discovery`: 3 of 3 registries answered, no
community skill probes Cloudflare token write scope; nothing installed.

**Community discovery.** Skipped: the change is bash only; no uncovered stack.

**CLAUDE.md / AGENTS conventions.** `cq-write-failing-tests-before` (mock fidelity first, RED on the old code),
`cq-test-fixtures-synthesized-only` (mock tokens and ids are synthetic), `hr-never-run-commands-with-unbounded-output`,
`hr-ssh-diagnosis-verify-firewall` not triggered (no network-outage keywords), no SSH anywhere.

## Problem Statement

Header rule 3 makes a grant token's 400 count as authorized only after a known-denied sibling token got 403 on the
same request. On `PATCH /zones/<z>/settings`, Cloudflare rejects a non-JSON body with 400 code 6007 before it looks
at the token, so the deny control (`CF_API_TOKEN_BOT_MANAGEMENT_NEXT`) can never answer 403 to INVALID_BODY. The row
is permanently `inconclusive`, the profile exits 3, and `swap-0b` refuses to swap. Measured on the new zone on
2026-11-26: INVALID_BODY gets 400 6007 for `PURGE_NEXT`, `DNS_EDIT_NEXT` and `BOT_MANAGEMENT_NEXT`; valid JSON
`{"cf_token_scope_probe":"never-valid"}` gets 403 9109 for `PURGE_NEXT` and `BOT_MANAGEMENT_NEXT` (comment
7193905571 on #12931).

## Proposed Solution

Implement the CTO ruling of 2026-11-26 exactly. Revised after plan review on 2026-11-26 (see `## Plan Review
Revisions`).

1. **Second literal.** Next to `readonly INVALID_BODY`, add
   `readonly SETTINGS_PROBE_BODY='{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}'`.
   The probe-id prefix `cf_token_scope_probe_` is written inline in the one jq expression that checks it (no
   separate prefix constant).
2. **Sixth row field `body-kind`.** Write rows become `label|method|url-template|grant-token-key|deny-token-key|body-kind`.
   Every `MIG_WRITE_REDIRECTS_DNS` row and the `bot_management` row end `|invalid`; only
   `zones/<zone>/settings|PATCH|$API/zones/\$ZONE/settings|…|settings-json`. Every `read -r` over write rows gains
   the 6th variable: the dry-run loop (`w_kind`), the token-acquisition loop (`_k`, and add `_k` to the
   `unset _l _u _w _m` line), the write loop (`w_kind`), the static guard and the collision pre-check (5 read sites).
3. **Static table guard, before any secret read and before the dry-run prints.** Place it AFTER the `mig_url()`
   definition and BEFORE the migration dry-run block. It cannot sit directly under the INVALID_BODY tripwire: that
   is above `mig_write_rows()`, and a `< <(mig_write_rows …)` there fails inside the process substitution without
   tripping `set -e`, so the loop would see zero rows and pass silently. Loop over the two arrays directly
   (`for row in "${MIG_WRITE_REDIRECTS_DNS[@]}" "${MIG_WRITE_ZONE_REST[@]}"`), unconditional on profile because the
   tables are global: a corrupt migration table also refuses the `rulesets` and `default-token` profiles, as the
   INVALID_BODY tripwire does; do not narrow it to migration profiles. Exit 2, stderr, naming the corruption, when:
   - any write row has a body-kind outside `{invalid, settings-json}` (always checked, jq not needed);
   - any `settings-json` row's url-template is not exactly the literal string `$API/zones/\$ZONE/settings` (rows
     store a literal `$ZONE`), or its method is not `PATCH` (always checked);
   - `SETTINGS_PROBE_BODY` fails (`jq -e … >/dev/null`, any non-zero rc is a refusal; only this check is gated on
     `command -v jq`, as the INVALID_BODY tripwire is)
     `type == "object" and keys == ["items"] and (.items | type == "array" and length > 0) and all(.items[]; type == "object" and keys == ["id","value"] and (.id | type == "string" and startswith("cf_token_scope_probe_")))`.
     One expression covers "parses as JSON", "object, not array/scalar", "no keys besides `items` and
     `id`/`value`" (the endpoint parses arbitrary object keys, so an extra `"ssl":"off"` must never ride along),
     "items non-empty" (the rejected no-op body) and "every id is probe-prefixed". Verified 2026-11-26: an extra
     top-level `"ssl"` key → rc 1; an extra item key → rc 1. `startswith` must apply to `.id`, not to the item object. Verified
     2026-11-26 with jq: canonical body → `true`; `{"items":[]}`, `[]` and a second item `{"id":"ssl"}` → `false`.
   Without jq the JSON check is skipped and the run path exits 2 at the prerequisite loop before any request, so
   only `--dry-run` runs without it, and it sends nothing.
4. **`mig_req` body chokepoint.** `mig_req <method> <url> <token-key> [body-kind]`, with `local kind="${4:-}"`
   (the script runs under `set -u`; GET callers, the controls and `mig_fatal`'s read-back, pass no 4th argument).
   In the `PUT|POST|PATCH` arm a closed `case "$kind"` sets `w_body="$INVALID_BODY"` or
   `w_body="$SETTINGS_PROBE_BODY"`; `*)` prints the table-corruption message and `exit 2`. The `settings-json` arm
   also refuses (exit 2) unless `"$url" == "$API/zones/$MIG_ZONE/settings"` (one line at the real write boundary).
   `w_body` is declared `local` with no initializer. The ONE write curl keeps its shape with
   `--data-binary "$w_body"`. `mig_req` stays called directly (never inside `$(…)`), so `exit 2` ends the script.
5. **Collision guard, after the controls, before the first write.** *(Superseded at review: the shipped guard runs
   inside the settings control arm as `mig_settings_check`; see the note under Guard Contract.)* Initialize
   `MIG_SETTINGS_LIST=""` and
   `MIG_SETTINGS_CTRL_OK=0` next to `MIG_CTRL_OK=1` (`set -u`, and an exported value must never be inherited). In
   the control loop's authorized arm, the `zones/*/settings)` case sets `MIG_SETTINGS_LIST="$BODY"` and
   `MIG_SETTINGS_CTRL_OK=1` only when `.result` is a NON-EMPTY array. A real zone always lists settings, so an
   authorized empty list is degraded: report the control `degraded (200 settings list empty)` and set
   `MIG_CTRL_OK=0; MIG_INCONCLUSIVE=1` (deepen security review: otherwise an empty list passes the collision check
   vacuously). Before the write loop, when any write row of the profile is `settings-json` and
   `MIG_SETTINGS_CTRL_OK=1`, pipe the list on stdin, never `--argjson list` (that would put the Cloudflare response
   on jq's argv, visible to `ps`, and fail with E2BIG past 128 KiB):
   `rc=0; printf '%s' "$MIG_SETTINGS_LIST" | jq -e --argjson body "$SETTINGS_PROBE_BODY" '. as $list | any($body.items[].id; . as $i | any($list.result[]?; .id? == $i))' >/dev/null 2>&1 || rc=$?`
   (stdout is the data channel, so jq's `true`/`false` must not reach it). rc 0 (a hit) → exit 2 with zero writes
   and the message `a setting named like the probe id exists on this zone; refusing to send a body that names it`;
   rc 1 → proceed; any other rc → exit 2 (`could not evaluate the settings list`), fail-closed. Verified
   2026-11-26: probe id listed (second element) → rc 0; `[{"id":"ssl"}]` → rc 1; unparsable input → rc 5. In the
   write loop a `settings-json` row with `MIG_SETTINGS_CTRL_OK=0` reports `inconclusive (settings control not
   authorized — the JSON probe body is only sent under a parsed settings list)`, sets `MIG_INCONCLUSIVE=1` and
   `continue`s with no request. Other rows are unchanged.
6. **Write loop.** Passes `w_kind` to both `mig_req` calls (deny, grant). Verdict logic unchanged: 2xx → `mig_fatal`
   (exit 4 after the read-back), deny non-403 → inconclusive, grant 400 → authorized, 401/403 → denied, other →
   inconclusive. `mig_fatal`'s array read-back summary also prints `probe_id_listed: true|false` (whether any
   listed id starts with `cf_token_scope_probe_`), so a settings 2xx (the CTO dissent) carries the one fact the
   re-ruling needs; every string still passes `safe()`.
7. **Dry-run.** Print both literals (`INVALID_BODY='…'`, `SETTINGS_PROBE_BODY='…'`), and per write row the existing
   comment extended with its kind (`# write <label> (body-kind <kind>): deny control …`), then a printed assignment
   line `w_body="$INVALID_BODY"` or `w_body="$SETTINGS_PROBE_BODY"`, then the two recipes with
   `--data-binary \"\$w_body\"`. The printed assignment keeps the output copy-pasteable; without it a pasted recipe
   sends an empty body (deepen architecture review). The dry-run picks the name with its own two-arm closed case (an
   unknown kind cannot reach it: the static guard ran first); M10's per-row line and M2's per-row body pin it to the
   run-path map. Those parse lines start with `printf`, so the Phase 3 step 4 set is unaffected. The second banner
   line changes from "write probes send ONLY the invalid body" to "write probes send ONLY the two fixed never-valid
   bodies; any 2xx aborts (exit 4) after a read-back". None of the new printed or stderr text may contain the
   substring `curl` (D12c (I) flags any parse line naming it) or `curl --disable` (D-pc counts it).
8. **Prose.** Rewrite header invariant 1 to name both literals and their guards; update the top summary ("one fixed
   invalid body that can never validate"), the `INVALID_BODY` comment ("The ONE write-probe body"), `mig_req`'s
   comment, `usage()` (lines with "fixed-invalid-body" / "invalid-body WRITE probes" and the exit-4 line),
   `mig_fatal`'s two messages and the pass line ("invalid-body probes"). `mig_fatal` keeps the substring "a mutation
   may have landed" (M5 pins it). No comment may contain the text `--data-binary "$w_body"`: the single-site count
   is a raw `grep -cF` that counts comments, and the mutant helper replaces the first match.

## Technical Considerations

- **Why the grant's 400 still proves scope.** The deny token sends the identical `SETTINGS_PROBE_BODY` to the
  identical URL and must answer 403. A 403 on a body that is JSON-valid but schema-invalid (whatever schema the
  endpoint enforces, `items` wrapper or bare array) shows authorization precedes schema validation for that request
  shape, so a grant 400 on the same request passed authorization. The measured 403 9109 on
  `{"cf_token_scope_probe":"never-valid"}` for `BOT_MANAGEMENT_NEXT` is the evidence this ordering holds.
- **Why no real setting can change.** The only item names `cf_token_scope_probe_nonexistent_setting`; the static
  guard forbids any non-prefixed id; the collision guard forbids an id the zone actually lists. A 200 would be a
  no-op that still reads fatal (exit 4), which is the CTO dissent's trigger.
- **Grant answers other than 400.** A 4xx other than 400 reads `inconclusive (PATCH <code>, err <n>)`, exit 3,
  fail-closed, and routes to a re-ruling (Phase 5).
- **Security.** No new flag reaches curl (D12c (F) keeps the -X / --data-binary pair and pins the body word to
  `"$w_body"`); no token value is printed; the old account/zone refusal still precedes every Doppler read. The only
  write path is `mig_req`'s `PUT|POST|PATCH` arm (D12c (I)); the mock's `UNMODELLED` refusal plus U1 catch any other
  flag.
- **Performance.** One extra `jq` call at startup and one per run for the collision check.
- **Architecture.** No ADR: ruling L49 lives in the #12931 plan and the script header, not in an ADR; this plan
  amends L49 rule 1 in the header and in SKILL.md. No C4 element changes (an internal script's request body).

## Implementation Phases

### Phase 1 — RED: mock fidelity and new assertions (test file only)

1. Mock write branch, in this order: `MOCK_WRITE_OVERRIDE` first (explicit answers, e.g. M5d's 200); then, for a
   URL matching `/zones/[^/]+/settings$` whose `$body_arg` fails `jq -e .`, answer
   `400:{"success":false,"errors":[{"code":6007,"message":"Malformed JSON in request body"}]}` for every token; then
   the token default (granted → 400, others → 403; for the settings URL use code 9109, as measured). The GET
   `*/settings` default (`MOCK_ZSET`) becomes a realistic non-empty list (`[{"id":"ssl","value":"full"},
   {"id":"always_use_https","value":"on"}]`), because an empty list is now a degraded control. A comment
   beside the settings branch states that the grant's 400 is ASSUMED until Phase 5 measures it.
2. One preamble block above the D12c single-site assertion (today near line 937) holds: `INV_BODY` (moved up from
   the M-series preamble), `SET_BODY="$(sed -n "s/^readonly SETTINGS_PROBE_BODY='\(.*\)'$/\1/p" "$SUT" | head -1)"`,
   the hardcoded `WANT_SET_BODY` (the CTO literal byte-for-byte; the one anchor that does not come from the
   script), and `D12C_WRITE_ANCHOR`. M1/M2 read `INV_BODY`/`SET_BODY`; D12c reads `D12C_WRITE_ANCHOR`.
3. A table-driven temp-copy helper next to `d12c_mut`:
   `run_mut <label> <want-exit> <want-writes> <want-doppler-reads> <want-message> <anchor> <replacement> [<anchor> <replacement>…]`.
   For each pair it refuses a vacuous mutant whose anchor is missing, anchors on a full line, and asserts the
   replacement occurs exactly once in the copy; it runs `bash -n` on the copy and fails if it does not parse (bash
   exits 2 on a syntax error, which would otherwise satisfy every exit-2 row with zero writes and zero Doppler
   reads); it RUNS the copy through the mock with fresh write/GET/Doppler logs via a `run_script <script> <PATH>
   <args…>` sibling of `run()` (which hardcodes `$SUT`); and it asserts exit code, write count, Doppler-read count
   and that `<want-message>` (the guard's own refusal text) appears in the output. It emits the same number of
   assertions on every path, so `MIN_ASSERTIONS` still catches a block that stops running.
4. Add the new assertions (Test Scenarios). Run the suite on the unmodified script: M2 must fail
   (`verdict=inconclusive`, exit 3), proving the mock reproduces the live defect.

### Phase 2 — GREEN: script change

Implement Proposed Solution steps 1-8 in `cf-token-scope.sh`.

### Phase 3 — D12c canon and allowlist (reviewed act)

1. Regenerate the changed canon lines from `env -i PATH=/var/empty "$BASHBIN" --pretty-print "$SUT"` (the `mig_req`
   write line and the dry-run write recipe) and review the diff line by line before pasting into `D12C_CANON`.
2. `D12C_FLAGS` (F): `--data-binary` must be followed by exactly `"$w_body"` (the run line and, after the awk's
   `\"`/`\$` unescape, the dry-run line). `"$INVALID_BODY"` is no longer admitted at a curl site.
3. `D12C_WRITE_ANCHOR='--data-binary "$w_body"'`; the single-site count is `grep -cF -- "$D12C_WRITE_ANCHOR"` = 1.
4. Body-variable WRITE-form closed set over the same parse: the trimmed parse lines that write `w_body`
   (matching `local[^;]*\bw_body\b`, `^w_body\+?=`, `read[^;]*\bw_body\b`, `printf -v w_body`, `declare[^;]*\bw_body\b`)
   are exactly three: the `local` declaration with no initializer, `w_body="$INVALID_BODY"` and
   `w_body="$SETTINGS_PROBE_BODY"`. Dry-run print lines start with `printf '%s\n'` and match none of these. The
   behavioral per-row body checks in M1/M2 are the primary guard; this set is the cheap structural backstop (a
   narrower form than the cut whole-multiset canon, kept after the deepen test-design review showed a plain
   `^w_body=` count misses `local w_body=…`, `read`, `printf -v` and `+=`).
5. Update the D12c header comment (CONTRACT and (F) text): the one body variable is `$w_body`, set only from the
   two readonly literals by `mig_req`'s closed case.

### Phase 4 — Prose (Proposed Solution step 8, SKILL.md, runbook)

- `SKILL.md`: `## Usage` intro → "only with one of two fixed bodies that cannot validate"; the "One fixed invalid
  body" bullet → "Two fixed never-valid bodies": INVALID_BODY (not JSON) for every row except the settings PATCH;
  SETTINGS_PROBE_BODY (JSON naming one nonexistent `cf_token_scope_probe_`-prefixed setting id) for that row,
  because the endpoint parses JSON before authorization; the static guard, the `mig_req` URL refusal and the
  collision guard by name. Add a `body` column to the row table; exit `4` → "a write probe answered `2xx`".
- Runbook `### Write-probe each token before its phase (CTO L49)`: replace the first bullet's "one fixed invalid
  body literal that can never validate … never a valid body" with the two-literal statement (still never
  `{"rules":[]}`, never a body naming a real setting, never `DELETE`). Keep `probe=<phase> verdict=pass` (R5 pin).
- Raise `MIN_ASSERTIONS` to the new measured total (never lower).

### Phase 5 — Post-merge (agent, local; not part of the diff)

Run `bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh --profile zone-rest --staged` from a
`main` checkout and post the verdict lines on #12931, always including the settings row's grant status and error
code. Route by outcome; in every branch `swap-0b` stays held until its own typed authorization:

Read the exit code first, then the `probe=zone-rest verdict=` line, then the per-row report lines. When several
exit-3 rows match, post all of them and take the first matching row below as the route. Each row is keyed on text the
script prints.

Match the relayed `probe=zone-rest row <label> -> <status>` lines; split on the first ` -> `.

| Outcome | Action |
|---|---|
| exit 0, `verdict=pass` | Report swap-0b unblocked. Post the settings row line `row zones/<zone>/settings -> authorized (PATCH 400, err <code> after a 403 control)`. If `<code>` differs from the mock's assumed 400 body, correct the mock in a follow-up PR |
| exit 4, `verdict=fatal-mutation` | No re-run. Post the `probe=zone-rest fatal`, `write-response` and `read-back` lines (all `probe=` lines, so the swap-0b wrapper keeps them); re-consult the CTO (recorded dissent: GET control plus a separate permission-group check) |
| exit 2, `verdict=refused reason=probe-id-collision` | Post it with its `probe=zone-rest refused-detail` line; changing the probe id needs a re-ruling |
| exit 2, `verdict=refused reason=settings-list-unevaluable` | Post it with its `refused-detail` line; the list shape changed. Re-consult the CTO before any re-run |
| exit 2, no `probe=zone-rest verdict=` line (row lines may precede it) | Not a probe verdict: a usage error, a missing `_NEXT` secret, or table corruption. Read stderr, fix that, re-run |
| exit 3, `row control: zones/<zone>/settings -> denied (…)` or `-> degraded (…)`, then `row zones/<zone>/settings -> inconclusive (settings control not established` | The settings read failed or returned an empty list. Check the `CF_API_TOKEN_ZONE_SETTINGS` read scope, then re-run. No re-ruling needed |
| exit 3, `row zones/<zone>/settings -> inconclusive (grant got 400` | The JSON body was not parsed (err 6007, or not one JSON document): post it and re-consult the CTO |
| exit 3, `row zones/<zone>/settings -> inconclusive (… got 400, not 403` | The deny control did not get 403 on the settings row (bulk endpoint EOL, or the wrapper format): post it and re-consult the CTO |
| exit 3, `row zones/<zone>/settings -> denied (…; re-mint <KEY>)` | The grant token lacks Zone Settings Edit: post it and re-consult the CTO |
| exit 3, any `row zones/<zone>/bot_management -> …` line not `authorized` | The bot_management row failed (its deny control or its grant): post it; re-mint `CF_API_TOKEN_BOT_MANAGEMENT_NEXT` only if its grant reads `denied` |

## Observability

```yaml
liveness_signal:
  what: the probe's last stdout line, probe=zone-rest verdict=pass|denied|inconclusive|refused|fatal-mutation (refused carries reason=probe-id-collision|settings-list-unevaluable), plus its exit code (0/3/4; 2 for refused, or with no probe= line for a refused table or body)
  cadence: per run (before swap-0b, and once post-merge by the agent; swap-0b runs it itself)
  alert_target: the #12931 thread (the agent posts the verdict lines); swap-0b refuses on anything but exit 0 plus the exact verdict=pass line
  configured_in: plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh (verdict echo lines) and the bootstrap run_scope_probe consumer

error_reporting:
  destination: stdout verdict rows (the documented data channel) plus stderr for exit-2 refusals; no Sentry, as this is an operator-local CLI with no server surface (observability layer 7, self-hosted CLI)
  fail_loud: exit 2 with "cf-token-scope:" stderr naming the corruption (body not probe-shaped, bad body-kind, settings-json off its URL, probe id present on the zone); exit 4 with verdict=fatal-mutation and a read-back

failure_modes:
  - mode: SETTINGS_PROBE_BODY edited to a non-JSON, non-object, empty-items or non-prefixed body
    detection: static guard exit 2 before any secret read; suite M0s and mutants red in CI shard 3
    alert_route: CI red on the PR; locally the exit-2 stderr line
  - mode: a row's body-kind set to settings-json on another URL, or an unknown kind
    detection: static guard exit 2 before any request; mig_req chokepoint exit 2; suite M11 mutants
    alert_route: CI red on the PR
  - mode: the new zone lists a setting whose id equals the probe id
    detection: collision guard exit 2 with zero writes
    alert_route: stderr of the run, posted on #12931
  - mode: grant token answers 2xx to SETTINGS_PROBE_BODY (CTO dissent)
    detection: mig_fatal read-back, verdict=fatal-mutation, exit 4
    alert_route: #12931 thread, then a CTO re-ruling
  - mode: bulk endpoint reaches end of life (2027-03-31)
    detection: deny control non-403, row inconclusive, exit 3
    alert_route: swap/dispatch refused; #12931 thread

logs:
  where: the run's stdout/stderr in the agent session; verdict lines copied to #12931
  retention: GitHub issue comments (indefinite)

discoverability_test:
  command: bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh --profile zone-rest --dry-run
  expected_output: cf_token_scope_probe_nonexistent_setting
```

The command sends nothing (dry-run exits before the prerequisite loop and every Doppler read) and finishes in well
under a second.

## Guard Contract

> **Superseded in part 2026-11-26 (review and fix round, PR #13076):** the collision check now runs inside the
> settings control arm (`mig_settings_check`), the write loop gates on `MIG_SETTINGS_CLEARED` (initialized 0, set
> only by a clear list), `MIG_SETTINGS_LIST` and the separate collision step are gone, the static guard reads every
> migration profile and requires exactly one settings control, and a hit or an unevaluable list prints
> `probe=zone-rest verdict=refused reason=…`. The rows below record the planned contract; the shipped one is the
> script plus its `M11*`/`Guard *` test rows.

Every mutant below is one `run_mut` (or `d12c_mut`) line on a temp copy of the script, run through the mock; the
live tree is never edited.

### Guard 1 — body selection is closed and URL-scoped

**Property.** Every write request the script sends carries exactly INVALID_BODY or exactly SETTINGS_PROBE_BODY,
and SETTINGS_PROBE_BODY is sent only to `$API/zones/$MIG_ZONE/settings`.

**Assembly.** The chokepoint is `mig_req`'s `PUT|POST|PATCH` arm: the only parse-level write curl line (D12c (I)),
whose body word is `"$w_body"` (D12c (F)), with `w_body` assigned only by that arm's closed `case` (Phase 3 step 4
count). Members that feed it: the 6th field of every row of `MIG_WRITE_REDIRECTS_DNS` and `MIG_WRITE_ZONE_REST`,
read at five sites (static guard, token acquisition, dry-run, collision pre-check, write loop). The static guard is
a second, earlier enforcement point that exists for ORDER: it refuses before the first write of ANY row, while the
chokepoint fires only when the offending row is reached.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | bot_management row's body-kind → `settings-json` | RED: exit 2, write log empty, Doppler log empty |
| 2 | dispatch: the static guard's loop iterates an empty list (anchored on a named marker comment) AND mutation 1 | RED: the zero-writes assertion fails, because only the chokepoint is left and it exits after the settings row's writes |
| 3 | second member: append a third zone-rest row `…/zones/\$ZONE/dns_records…\|settings-json` after the compliant settings row | RED: exit 2, write log empty |
| 4 | a redirects-dns row's body-kind → `bogus` | RED: exit 2, Doppler log empty |
| 5 | revert the fix: settings row body-kind → `invalid` (M2w) | RED: verdict inconclusive (mock answers 6007 to the deny control) |
| 6 | swap the closed-case arms | RED: M1/M2 per-row body assertions |
| 7 | a third `w_body=` assignment | RED: Phase 3 step 4 count |
| 8 | curl site back to `--data-binary "$INVALID_BODY"` | RED: D12c (I) and (F) |

**Harness rows.**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | the mock stops logging the body | RED: the per-row body check requires `2 * rows` lines and compares each body to the expected literal, so a body-less log fails |
| H2 | must-PASS, non-canonical: a temp copy whose zone-rest rows are reordered (settings second) | PASS: exit 0; settings row still carries SET_BODY, bot row INVALID_BODY |

### Guard 2 — SETTINGS_PROBE_BODY shape

**Property.** SETTINGS_PROBE_BODY is a JSON object whose `items` array is non-empty and every item's `id` is a
string starting with `cf_token_scope_probe_`; otherwise the script exits 2 before any secret read or print.

**Assembly.** One readonly literal, checked by one jq expression in the static guard (prefix inline); the suite
pins the literal byte-for-byte against its own hardcoded `WANT_SET_BODY` and re-checks its shape (M0s, the asked
tests), so the source pin does not depend on the runtime check running.

**Mutation matrix.**

| # | Mutation to the literal | Expected |
|---|---|---|
| 1 | not JSON (drop the closing `}`) | RED: exit 2, Doppler log empty |
| 2 | `{"items":[]}` (the rejected no-op) | RED: exit 2 |
| 3 | `[{"id":"cf_token_scope_probe_x","value":"y"}]` (JSON non-object, rejected by the ruling) | RED: exit 2 |
| 4 | second member: a compliant first item then `{"id":"ssl","value":"off"}` | RED: exit 2 |
| 4b | an extra top-level key beside `items` (`"ssl":"off"`) | RED: exit 2 |
| 5 | dispatch: the static guard's jq expression replaced by `true`, combined with mutant 1's literal | RED: the run no longer exits 2 before Doppler, so M11d's assertion fails (rows 1-4 test the runtime check, not only the source literal) |

**Harness rows.**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | the `SET_BODY` sed parse returns empty | RED: the "literal parsed from source" positive control |
| H2 | must-PASS, non-canonical: two compliant items (`cf_token_scope_probe_a`, `cf_token_scope_probe_b`) | PASS: dry-run exit 0 |

### Guard 3 — the probe id is absent from the zone's live settings list

**Property.** No request carrying SETTINGS_PROBE_BODY is sent unless the authorized settings GET control's parsed
`.result[].id` list was captured in this run and none of its ids equals any `.items[].id` of the body.

**Assembly.** `MIG_SETTINGS_LIST` is initialized empty and set only in the control loop's authorized arm for the
`zones/*/settings` label; the collision check runs once between the control loop and the write loop; the write
loop's `settings-json` branch skips (inconclusive) when the list is empty. Both sides are quantified over every
element.

**Mutation matrix.**

| # | Mutation / input | Expected |
|---|---|---|
| 1 | `MOCK_ZSET` list contains `cf_token_scope_probe_nonexistent_setting` | RED: exit 2, write log empty |
| 2 | second member: list `[{"id":"ssl"},{"id":"cf_token_scope_probe_nonexistent_setting"}]` | RED: exit 2, write log empty |
| 3 | dispatch: the `printf '%s' "$MIG_SETTINGS_LIST"` feeding the collision jq reads a different (never-set) variable, with input 1 | RED: jq gets empty input, so the run takes the fail-closed `could not evaluate` exit 2 and NOT the collision message; M11a asserts the collision message text, so it reds |
| 3b | an authorized control with an EMPTY `result` | the settings control reads `degraded (200 settings list empty)`, no `/settings` write, exit 3 (security review: an empty list must not pass the check vacuously) |
| 4 | reorder: collision check moved after the write loop | RED: write log non-empty on input 1 |
| 5 | settings control 404 (`MOCK_ZSET`) | row skipped: no `/settings` write, `inconclusive (settings control not authorized`, exit 3; bot row still probed |

**Harness rows.**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | must-PASS, non-canonical: list holds `cf_token_scope_probe_nonexistent_setting_other` and `ssl` | PASS: exit 0 (exact match, not substring) |

**Anchor.** `WANT_SET_BODY` is hardcoded in the suite, so a change to the body must edit two files; `D12C_CANON`
and the expected counts live in the same commit as the script, so those prove consistency, not integrity.
Changing either is a reviewed act (D12c header). The live settings list (Guard 3) is the one input from outside the
commit.

**Exit sites relative to the first write.**

| Exit | Position | Proven by |
|---|---|---|
| static guard (Guards 1, 2) | before any Doppler read, before the dry-run print | `run_mut` want-doppler-reads 0 and no curl marker |
| collision guard (Guard 3) | after the GET controls, before the first write | write log empty |
| `mig_req` chokepoint (Guard 1) | at write time; earlier rows may have written | Guard 1 row 2 |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the settings PATCH row sends a second fixed literal SETTINGS_PROBE_BODY='{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}', and the grant token may receive it" [brief] | Proposed Solution 1, 4 | mapped |
| 2 | "add a 6th row field body-kind (`invalid` \| `settings-json`); only the `zones/<zone>/settings\|PATCH` row uses settings-json, bot_management keeps invalid" [brief] | Proposed Solution 2 | mapped |
| 3 | "mig_req maps kind -> one of two readonly constants via a closed `case` (unknown kind exits 2); keep ONE curl site with `--data-binary "$w_body"`" [brief] | Proposed Solution 4; Phase 3 | mapped |
| 4 | "SETTINGS_PROBE_BODY parses as JSON; every .items[].id starts with `cf_token_scope_probe_`" [brief] | Proposed Solution 3; Guard 2 | mapped |
| 5 | "that id is absent from the authorized GET control's `.result[].id` (if the control did not pass, the row is skipped as inconclusive)" [brief] | Proposed Solution 5; Guard 3 | mapped |
| 6 | "settings-json on any URL other than /zones/$ZONE/settings is refused" [brief] | Proposed Solution 3, 4; Guard 1 | mapped |
| 7 | "Rewrite header invariant 1 to name both literals; update the dry-run output" [brief] | Proposed Solution 7, 8 | mapped |
| 8 | "Any 2xx stays fatal (exit 4 after read-back, mig_fatal)" [brief] | Proposed Solution 6; M5d | mapped |
| 9 | "Tests to add in plugins/soleur/test/cf-token-scope.test.sh: SETTINGS_PROBE_BODY parses; its ids match the probe prefix; a mocked control list containing the probe id -> exit 2 and zero writes; a settings-json row on another URL -> exit 2; the settings row sends exactly SETTINGS_PROBE_BODY and every other row exactly INVALID_BODY (move the M1 and single-site D12c counts to two named constants at one site); a 200 on the settings row -> exit 4 after read-back" [brief] | Phase 1 (preamble block); Test Scenarios M0s, M11a-b, M1/M2 body rows, M5d; Phase 3 | mapped |
| 10 | "Ref #12931 (do NOT close the epic; use `Ref #12931`)" [brief] | frontmatter `closes: none`; AC14 | mapped |
| 11 | "After merge, the agent re-runs the staged zone-rest probe locally and posts the verdict on #12931" [brief] | Phase 5 | mapped |
| 12 | "swap-0b and the zone-rest dispatch remain operator-authorized (typed go naming the command), not part of this PR" [brief] | Overview; Non-Goals | descoped — justification: the brief places them outside this PR |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cf-token-scope.sh` edits | asks 1-8 | asked |
| `cf-token-scope.test.sh` edits | ask 9 | asked |
| Mock models the settings endpoint's JSON-first parse; M2w | — | inferred — justification: without it the suite cannot red on the defect the brief measured (`cq-write-failing-tests-before`; learning 2026-07-24 stubbed-uniform-fixture) |
| `WANT_SET_BODY` hardcoded | — | inferred — justification: the only anchor outside the script; without it the suite's checks agree with whatever the script contains |
| `run_mut` helper | — | inferred — justification: keeps each asked mutant to one line (CTO devex review); reuses `d12c_mut`'s vacuous-anchor refusal |
| D12c canon, (F) allowlist, anchor, `w_body=` count | ask 3 ("keep ONE curl site with `--data-binary "$w_body"`") | asked |
| SKILL.md and runbook prose | — | inferred — justification: both state "one fixed invalid body … never a valid body", which becomes false; the runbook is the procedure the brief cites (Phase 2 Step 3) |
| `MIN_ASSERTIONS` raise | — | inferred — justification: the anti-vacuity floor equals today's count (320) and must hold the new assertions |
| decision-challenges.md row | "write it as a `technical` row" [brief] | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 4 edited (+2 planning artifacts) | Estimated changed lines: ~230 (script ~80, test ~120, docs ~30)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Non-Goals

- Running `swap-0b`, the `zone-rest` rehearsal or apply (each needs its own typed authorization).
- Any live Cloudflare write probe from CI, or any probe of the old account/zone.
- Moving the settings row to the per-setting endpoint before the bulk endpoint's 2027-03-31 end of life (rejected
  by the CTO ruling: it names a real setting). The EOL reads as `inconclusive`, fail-closed.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] AC1. `cf-token-scope.sh` declares `readonly SETTINGS_PROBE_BODY='{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}'` byte-for-byte (`grep -cxF` = 1), and the suite's hardcoded `WANT_SET_BODY` equals it.
- [ ] AC2. Every write row in both tables has exactly 6 `|`-separated fields; exactly one row ends `|settings-json` and its url-template is `$API/zones/\$ZONE/settings`; all others end `|invalid`.
- [ ] AC3. `bash --pretty-print` of the script shows exactly one curl line containing `--data-binary`, with the body word `"$w_body"`, and exactly two lines starting with `w_body=`: `w_body="$INVALID_BODY"` and `w_body="$SETTINGS_PROBE_BODY"`.
- [ ] AC4. With the mock modeling JSON-first parsing, a temp copy with the settings row set to `invalid` reads `probe=zone-rest verdict=inconclusive` (M2w), and the fixed script reads `probe=zone-rest verdict=pass`, exit 0.
- [ ] AC5. In the zone-rest happy path the write log holds exactly 4 lines: exactly 2 `/settings` PATCH lines carrying SET_BODY and exactly 2 `/bot_management` PUT lines carrying INV_BODY (counted, so an empty or short log fails); in redirects-dns all `2 * MW_RD_N` lines carry INV_BODY.
- [ ] AC6. Each of: body not JSON / `{"items":[]}` / JSON array / a non-prefixed second item / unknown body-kind / `settings-json` on another URL (first or third row) → exit 2, empty write log, no Doppler read.
- [ ] AC7. A settings list containing the probe id (first or second element) → exit 2 with an empty write log; a list with only prefix-sharing ids → exit 0.
- [ ] AC8. Settings control 404 → no write to `/settings`, row reads `inconclusive (settings control not established`, exit 3, and the bot_management row is still probed.
- [ ] AC9. A 200 to the settings grant probe → exit 4 and `verdict=fatal-mutation`; the GET log carries `GET …/zones/<new>/settings tok-zonesettings-mock` exactly twice (the control, then the read-back), and the write log stops at 2 lines.
- [ ] AC10. `--profile zone-rest --dry-run` prints both literal lines, `(body-kind settings-json)` then a printed `w_body="$SETTINGS_PROBE_BODY"` line before the settings recipes and `(body-kind invalid)` then `w_body="$INVALID_BODY"` before the bot recipes, sends no curl, and leaks no token; D-pc recipe counts are unchanged.
- [ ] AC11. `grep -rniE 'one fixed invalid|fixed-invalid-body|invalid-body' plugins/soleur/skills/cf-token-scope knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md` returns nothing, and the header, SKILL.md and runbook state the two-literal rule.
- [ ] AC12. `bash plugins/soleur/test/cf-token-scope.test.sh` exits 0 and `MIN_ASSERTIONS` equals the measured GREEN total, which the PR body states as `320 + <number of new assertions>`; `bash tests/scripts/test-cf-account-migration-runbook.sh` and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exit 0; `shellcheck` on both bash files is clean.
- [ ] AC13. No token value appears in any suite output (existing `lacks` rows plus one for the zone-rest JSON path).
- [ ] AC14. The PR body says `Ref #12931` and carries no `Closes`/`Fixes` for it.

### Post-merge (agent)

- [ ] AC15. The staged zone-rest probe was run from `main` and its verdict lines, including the settings row's grant status and error code, are posted on #12931 with the Phase 5 branch taken.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (carry-forward)
**Assessment:** `soleur:engineering:cto` ruled on this exact change on 2026-11-26 (binding, recorded in
`decision-challenges.md`): a second fixed JSON literal for the settings PATCH row only, a closed body-kind map at one
curl site, the static table guard (startup: body shape, body-kind set, settings-json URL), the `mig_req` URL refusal
at the write boundary, and the collision guard against the live settings list; 2xx stays fatal; recorded dissent (a
grant 2xx flips the ruling to the GET control plus a separate permission-group check). The CTO also reviewed this
plan on 2026-11-26 (devex lens) and its changes are applied. No other domain is implicated: no user-facing surface
(Product NONE, no UI file in the Files lists), no regulated data, no new infrastructure, no new store or
connection, no new autonomous task.

## Test Scenarios

All `unit` layer (a `*.test.sh` suite with mocked curl and doppler; deepen test-design review), in `plugins/soleur/test/cf-token-scope.test.sh`, mocked curl and doppler, no
network. Temp-copy cases use `run_mut`.

- **M0s** (unit, asked): `SET_BODY` parsed from source is non-empty (positive control); it parses as JSON; every
  `.items[].id` starts with `cf_token_scope_probe_`; it carries no `"rules"` key.
- **M0h** (unit): `SET_BODY == WANT_SET_BODY`.
- **M1** (unit): redirects-dns happy path, every write line's body equals `INV_BODY`, line count `2 * MW_RD_N`.
- **M2** (unit): zone-rest happy path, exit 0, `verdict=pass`; exactly 2 `/settings` lines with `SET_BODY` and exactly
  2 `/bot_management` lines with `INV_BODY`; deny-first order on both rows; the settings deny control is logged with
  `tok-botmgmt-mock` and the SET body.
- **M2w** (unit, temp copy): settings row set back to `invalid` → `verdict=inconclusive`, `got 400` on the
  settings row, grant never probed.
- **M5d** (unit): `MOCK_WRITE_OVERRIDE` makes `/settings` + `tok-zonesettings-mock` answer `200` → exit 4,
  `verdict=fatal-mutation`, the settings GET line for the grant token appears exactly twice, write log stops at 2.
- **M11a** (unit, asked): `MOCK_ZSET` list contains the probe id (first, then second element) → exit 2, write log
  empty, and the output carries the collision message `a setting named like the probe id exists`; prefix-sharing
  ids → exit 0.
- **M11g** (unit): an authorized settings control with an empty `result` → `degraded (200 settings list empty)`,
  no `/settings` write, exit 3.
- **D-rows** (unit, AC2): every line of both write tables has exactly 6 `|`-separated fields; exactly one row's 6th
  field is `settings-json`, with method `PATCH` and url-template `$API/zones/\$ZONE/settings`; every other row's is
  `invalid`.
- **M11b** (unit, temp copy, asked): bot row → `settings-json` → exit 2, write log and Doppler log empty;
  same with a third `settings-json` row appended after the compliant one.
- **M11c** (unit, temp copy): unknown body-kind → exit 2 before Doppler.
- **M11d** (unit, temp copies): Guard 2 mutants 1-4 → exit 2 before Doppler; the two-compliant-items
  variant → dry-run exit 0.
- **M11e** (unit): settings control 404 → no `/settings` write, row inconclusive, bot row probed, exit 3.
- **M10** (unit): zone-rest dry-run prints both literals and, per row, the body-kind comment and the printed
  `w_body=` line for that kind; recipe count still `MC_ZR_N + 2 * MW_ZR_N` (D-pc); no curl; no token.
- **D12c** (unit): canon multiset equality (I, S), (F) lint admits only `"$w_body"`, single-site count via
  `D12C_WRITE_ANCHOR`, the `w_body=` count, Guard 1 mutants 7-8.
- **Regression**: every existing C/D/M/U row stays green.

## Dependencies & Risks

- **The grant side is unmeasured.** Only the deny side (403 9109 on valid JSON) was measured on 2026-11-26; the
  grant token's answer to SETTINGS_PROBE_BODY is not, and a live write probe is out of scope before merge. The
  mock's grant 400 is an assumption, labelled in a comment beside the mock's settings branch. Phase 5 records the
  real status and code; a mismatch is corrected in a follow-up PR (or the re-ruling it triggers).
- **Grant gets 2xx (dissent).** Exit 4 is the designed outcome; Phase 5 routes it to a CTO re-ruling.
- **Grant gets a non-400 4xx.** Reads inconclusive (fail-closed); Phase 5 routes it to a CTO re-ruling.
- **Body wrapper not the wire format.** Mitigated by the deny control on the identical body (Technical
  Considerations); the docs show a bare array, so a schema 400 is likely and still meaningful.
- **D12c canon churn.** The canon is bash's own printing; regenerate with bash >= 5.2 and review the diff.
- **Bulk endpoint EOL 2027-03-31.** Fail-closed `inconclusive` after that date; out of scope here.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Changing `D12C_CANON` is a reviewed act: paste bash's printing of the reviewed source, never a hand-edited line.
- `set -u`: every new variable read before it is guaranteed set needs an initializer or `${x:-}` (`MIG_SETTINGS_LIST`,
  `mig_req`'s `kind`).
- The static guard must not iterate `< <(mig_write_rows …)` above that function's definition: a failure inside a
  process substitution does not trip `set -e`, so the guard would check zero rows and pass.
- The collision check compares whole ids with jq equality, never a substring `grep` (H1).
- jq output from the guards goes to `/dev/null`: stdout is the documented data channel.
- No new printed or stderr text may contain `curl` (D12c (I)); no comment may contain `--data-binary "$w_body"`
  (single-site count, mutant anchor).
- Mock evaluation order: `MOCK_WRITE_OVERRIDE` first, then the settings 6007 branch, then the token default.

## Plan Review Revisions

Plan review on 2026-11-26 (headless): `soleur:engineering:review:dhh-rails-reviewer`,
`soleur:engineering:review:kieran-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`, and
`soleur:engineering:cto` (devex lens), after a scoped advisor consult (Step 4.5). All applied findings are
Mechanical (eng-panel correctness or simplification of plan-inferred items; none drops operator-requested scope).

- **Correctness (Kieran, applied):** initialize `MIG_SETTINGS_LIST=""`; `local kind="${4:-}"`; static guard placed
  after `mig_url()` and looping over the arrays directly; AC9 read-back counted (the control logs the same GET);
  AC11 grep widened and case-insensitive; jq output to `/dev/null`; row checks not gated on jq; literal
  `$API/zones/\$ZONE/settings` comparison; 5 read sites and `_k` in the unset line; Guard 3 dispatch row reworded.
- **Advisor (applied):** jq `startswith` parenthesisation bug; hardcoded expected literal in the suite; the grant
  side named as unmeasured.
- **Simplification (DHH and code-simplicity both fired, so delete over fix):** cut the `PROBE_ID_PREFIX` constant
  (prefix inline in jq) and `WANT_PROBE_PREFIX`; cut the `D12C_WBODY_CANON` multiset pin (replaced by a two-line
  `w_body=` count; M1/M2 behavioral checks are primary); cut the chokepoint-reachability mutants (old Guard 1 rows
  10-13, M11f); cut the dry-run's second kind→name map (print the 6th field and a legend; superseded at deepen: the printed `w_body=` assignment is reinstated so recipes stay copy-pasteable); trimmed the Guard
  Contract to one dispatch and one second-member row per guard plus minimal harness rows (the plan skill requires
  both).
- **Kept against a cut:** M0s shape checks (DHH proposed cutting them as redundant with `WANT_SET_BODY`; they are
  asked tests, ask 9, so cutting them would drop operator-requested scope).
- **CTO devex (applied):** one preamble block for the body constants and D12c anchors, with the reconciliation row
  reworded (M1/M2 read the bodies; D12c reads the anchor); the `run_mut` helper; the static-guard neuter mutant
  anchored on a named marker comment; Phase 5 routes every exit code; Domain Review names the guards.

## References

- #12931 (epic), comment 7193905571 (the 6007 / 9109 measurement); PR #13076 (this branch's draft).
- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md` Phase 2 Step 3.
- Cloudflare: `bulk_edit` reference and the API deprecations page (URLs in Research Insights).
