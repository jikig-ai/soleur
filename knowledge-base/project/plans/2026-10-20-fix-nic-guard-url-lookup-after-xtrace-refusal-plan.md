---
title: "fix: resolve the nic-guard heartbeat URL after the xtrace refusal, not in the unit wrapper (#9639 F6)"
date: 2026-10-20
slug: nic-guard-url-lookup-after-xtrace-refusal
branch: feat-one-shot-9639-f6-nic-guard-url-after-refusal
issue: 9639
lane: single-domain
type: fix
---

# fix: resolve the nic-guard heartbeat URL after the xtrace refusal, not in the unit wrapper (#9639 F6)

PR body: `Ref #9639` and `Part of tracker #9217`. No closing keyword (F7 and F8 stay open; two sibling units are recorded not fixed). Draft PR: #10637.

## Enhancement Summary

**Deepened on:** 2026-10-20
**Gates run:** 4.6 User-Brand Impact (pass; `none` with the sensitive-path scope-out bullet), 4.7 Observability (pass; 5 fields present, probe verb `grep`, no shell-active characters, literal `expected_output`, fits the 15 s cap, run pre-fix to prove it discriminates), 4.8 PAT-shaped variable (none), 4.9 UI wireframe (no UI surface, skipped), 4.10 Encryption Posture (no `.tf`/cloud-init/migration in the file lists and no new store or connection, skipped), 4.11 Guard Contract (`scripts/lint-guard-contract.py` green, 2 entries; adequacy read done: Guard 1 assembly is the scanner's enumerated surfaces and the `analyse_exec` chokepoint, not a member list), 4.12 Scope Check (1 unfenced section, 3 subsections, a `Recommendation:` line, no unmapped ask).
**Verification instead of agent fan-out:** the change is two shell scripts, two unit files and one test scanner; every claim was verified directly (greps, a scratch xtrace experiment, `gh`), which is the proportionate depth, as for F5. The plan-review panel (DHH, Kieran, code-simplicity) and two CTO rulings supplied the independent reads.

### Key improvements over the first draft

1. Kieran's scratch scanner experiment falsified "script-side indirect = population reason, census unchanged": the unrestricted form pulled `inngest-luks-cutover.service` in (population 10 -> 11, rc 6). CTO amended F2: only `*_KEY`-named indirect expansion counts script-side (row G1.9).
2. The behavioral test mechanics were corrected from measurement: the stub `doppler` must not expand the secret (its own xtrace would leak it and void the G2.1 control); `SHELLOPTS=xtrace` cannot prefix `eval`; the env-capture row must exclude the key-named line.
3. The zot lookup moves to just after the `--canary-only` early exit (verified: `$URL` is used only inside functions defined earlier and called later, plus `_ping "$URL"` at the end, so nothing between the old and new site reads it).
4. Rollback order corrected (revert applies OLD script + NEW wrapper for one tick) and accepted.
5. Post-merge check 1 anchored on `Creation complete` after measuring that the bare resource name appears in a no-op apply log.

### New considerations discovered

- A one-line verification of the premise "no unit-side `${!`" is not enough for the scanner: keep the unit-side wrapper finding on the broader any-name form while the script-side reason is `_KEY`-bound.
- Cited issue/PR states checked live 2026-10-20: #9639 OPEN, #9217 OPEN, #10576 MERGED, #10501/#10546/#7390 OPEN, #7797 OPEN, #9638 OPEN; no open PR touches any file in "Files to Edit" (re-run on 2026-10-20 over every open PR).

## Overview

`apps/web-platform/infra/web-private-nic-guard.service` runs `doppler run ... -- bash -c 'export WEB_NIC_GUARD_URL="$${!WEB_NIC_GUARD_URL_KEY}"; exec /usr/local/bin/web-private-nic-guard.sh'` (`$$` is systemd's escape, so bash receives `${!WEB_NIC_GUARD_URL_KEY}`). The heartbeat URL is itself the credential (its path is the secret). The guard script refuses to run under xtrace (`web-private-nic-guard.sh` lines 11-13, exit 78), but the inner `bash -c` expands and exports the secret BEFORE the script starts, so a `SHELLOPTS=xtrace` or `BASH_ENV` `set -x` launch prints `+ export WEB_NIC_GUARD_URL=https://...` to the journal that Vector ships to Better Stack. The refusal never gets to run on that expansion.

Fix (CTO-ruled 2026-10-19 for the nic-guard, extended to the zot sibling by the 2026-10-20 ruling below): the unit stops expanding anything; the script resolves its own heartbeat URL through the key name AFTER the xtrace refusal.

Scope, by CTO ruling 2026-10-20 (F1, option c):

| Unit | Has an xtrace refusal to order against? | This PR |
|------|------------------------------------------|---------|
| `web-private-nic-guard` | yes, unconditional | fixed |
| `web-zot-consumer-probe` | yes: when the pull credential (`ZOT_PULL_TOKEN`/`ZTOK`) is set, or the key name is set and the launch is not `--canary-only` (both always set under `doppler run`) | fixed |
| `web-git-data-probe` | none | recorded NOT fixed on #9639 |
| `inngest-consumer-probe` | none (and it sources `inngest-registry-probe.sh`, which open PR #10501 edits) | recorded NOT fixed on #9639 |

No open PR touches any of the four units' `.service`/`.sh`/`.test.sh` files nor `doppler-injection-bound.test.sh` (checked with `gh pr diff --name-only` over every open PR, 2026-10-20; the only hits are the shared ratchet files `grep-q-pipe-guard.test.sh` and `guard-vacuity-floor.test.sh`, which this PR does not edit). The two unfixed siblings are excluded because there is no refusal for a moved lookup to follow; adding one is a separate #7797-class change, not an F6 fix.

## Research Reconciliation - Spec vs. Codebase

| Brief / issue claim | Reality (verified in this worktree) | Plan response |
|---------------------|--------------------------------------|---------------|
| "The same shape exists in sibling probe units" | Three siblings have the exact `export X="$${!X_KEY}"; exec script` shape: zot-consumer, git-data, inngest-consumer. Only zot has a refusal. | Fix nic-guard + zot; record git-data and inngest-consumer on #9639 as not fixed with the reason (CTO F1). |
| "Move the indirect lookup into the guard, after the refusal" | The URL is already read below the refusal (`URL="${WEB_NIC_GUARD_URL:-}"`, step 7), so the script change is "read the key, resolve through it", not a reorder. The reorder risk is a future edit hoisting it; that is what the order row guards. | Key-only resolution in the script; order row with a hoisted-lookup mutant. |
| (implicit) removing `${!` from the unit is self-contained | `doppler-injection-bound.test.sh` (Guard 2, #7761) uses the UNIT-side `${!` as the population reason for four units, each with an ACK entry (`ACK_CARDINALITY = 8`, pinned; R7b derives from it). Removing it makes the four ACKs stale (rc 5) and silently drops the units from the guard's coverage. | Extend the scanner (CTO F2, option A): script-side `${!NAME}` is a population reason; unit-side `${!` becomes a finding with an authored 2-entry wrapper-ack dict. Floors and `ACK_CARDINALITY` do not move. |
| (implicit) a bare `WEB_NIC_GUARD_URL` could stay as a fallback | The unit always overwrote it by `export`; production never relied on it. A fallback would keep a second path to the credential. | Key-only (CTO F3). Existing tests' `WEB_NIC_GUARD_URL=` fixtures are rewritten to key + value. |
| (implicit) the guard comment says "tracked as #9639" and an existing row asserts `grep -qF '#9639' $SUT` | After this PR the limitation no longer exists for the two fixed units. | Rewrite the comment and replace that row with one asserting the lookup follows the refusal. |

## Research Insights

**Premise validation.** #9639 is OPEN; F6's body text matches the brief. `web-private-nic-guard.service:29` carries the `$${!WEB_NIC_GUARD_URL_KEY}` expansion on `origin/main` (read in the worktree at `ff5d5142a5`, which is `main` plus the draft-PR init commit). F5 landed as #10576. The set of units with the shape was derived by grepping `\$\$?\{![A-Z_]+\}` across `*.service`/`*.sh`/`*.tf`/`*.yml` (four hits, all in `apps/web-platform/infra/`; the fifth `${!` hit, `scripts/derive-app-domain-base.sh`, is not a unit target). The brief's constraint list (cloud-init.yml, betterstack-logs-alerts.tf, apply-web-platform-infra.yml, server.tf) is respected: no edit to any of them. ADR corpus: ADR-202 (carried self-refusal, #7797) is the governing decision; nothing in it rejects "the unit must not expand secrets"; ADR-202 already states that xtrace does not cross `exec`, i.e. a traced parent is the residual shape F6 closes. ADR-280 (stdin-config) is unaffected.

**Property List.**

1. Under any xtrace launch form, the secret heartbeat URL never reaches stdout/stderr/the journal from the unit's `ExecStart` path (nic-guard always; zot whenever its credential is present, or its key name is set outside `--canary-only`).
2. The production path is unchanged for a well-formed install: the same URL reaches `curl` on its stdin config and the beat is sent.
3. A malformed key name cannot execute code through bash's `${!name}` subscript evaluation.
4. The resolved URL is not exported, so no child process inherits it.
5. A regression (unit re-expands, or the lookup is hoisted above the refusal) turns a test red, for every `doppler run` unit the repo enumerates, not only the two fixed ones.

**Cut List.**

- Fixing `web-git-data-probe` and `inngest-consumer-probe` -> would buy property 1 only after adding a brand-new unconditional xtrace refusal to each (a #7797-class change) -> cut; recorded on #9639 as not fixed (CTO F1).
- Keeping a bare `WEB_NIC_GUARD_URL` fallback -> buys backwards tolerance nobody uses -> cut (CTO F3).
- Lowering `ACK_CARDINALITY` / deleting the four ACKs (scanner option B) -> would shrink the guard's coverage and move a ratchet -> cut (CTO F2).
- Widening the zot refusal condition -> cut as first planned, then REVERSED at implementation: the credential-refusal lint (Rule C) counts `WEB_ZOT_CONSUMER_URL_KEY` as a credential name, so the new lookup needs the key in the refusal. Ruled by CTO agent 2026-10-20 (review): keep the key disjunct but exempt `--canary-only` (token disjuncts still apply there), so the `ExecStartPre` canary behaves exactly as on `main`; rows pin both disjuncts and both canary-only cases.
- A new boot-trail event (F7), a standing alert (F8), Sentry-DSN transport hardening (#9638) -> outside this PR by the brief.
- A production env seam for the unit-launch tests -> cut; the tests rewrite the extracted `ExecStart` text in a fixture copy.

**Writers of the identities the new lookup reads** (a guard must cite the artifact that writes what it reads). `WEB_NIC_GUARD_URL_KEY` is written into `/etc/default/web-private-nic-guard` by the `printf` in `server.tf` (the `private_nic_guard_install` remote-exec, web-1) and by `web-probe-envwrite.sh` line 48 (fresh hosts, via cloud-init); its value is built by `upper(replace(<host>,"-","_"))` after the `WEB_NIC_GUARD_URL_` prefix, i.e. `WEB_NIC_GUARD_URL_WEB_1` / `_WEB_2`, which satisfies `^[A-Z][A-Z0-9_]*$`. The Doppler secret of that name is written by `doppler_secret.web_nic_guard_url` (`web-probe.tf:115-123`). The zot key follows the same shape (`WEB_ZOT_CONSUMER_URL_WEB_1`). Tests use these production-shaped names, not only synthetic ones.

**No new `SOLEUR_*` marker.** The new invalid-key line is a plain `[nic] WARN:` stderr line, so the `git-lock-marker-telemetry` closed vocabulary (`apps/web-platform/server/git-lock-marker-telemetry.ts`) is not touched; the existing `SOLEUR_CREDENTIAL_REFUSED ... reason=empty` marker is reused.

**Institutional learnings applied.**

- `2026-10-19-a-hostile-fixture-must-put-the-payload-in-the-value-the-fix-reads.md` (F5): the hostile fixture for the new consumption point is the KEY value (`a[$(touch PLANT)]`), not the neighbouring lines.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: Guard Contract below.
- F5 ratchet lessons: run `grep-q-pipe-guard.test.sh` (PJ_TRIPLES), `lint-trap-tempfile-ownership`, `guard-vacuity-floor` before pushing; never lower a shared baseline.

## Technical rulings (CTO agent, persisted in `specs/feat-one-shot-9639-f6-nic-guard-url-after-refusal/decision-challenges.md`)

- F1 scope: option (c), nic-guard + zot; git-data and inngest-consumer recorded not fixed.
- F2 scanner: option A (script-side indirect = population reason; unit-side indirect = finding; separate 2-entry wrapper-ack dict with its own pinned cardinality; `ACK_CARDINALITY`, `MIN_POPULATION`, `MIN_DOPPLER_UNITS` unchanged).
- F3 script contract: key-only, charset-validated before any `${!KEY}`, expanded as `${!KEY:-}`, unset/invalid -> empty -> existing `reason=empty` path plus a value-free invalid-key line, plain unexported variable, no bare-var fallback.
- F4 test shape: static + behavioral (real `ExecStart`, `$$` unescaped, stub `doppler`, `SHELLOPTS=xtrace` and `BASH_ENV`) + mutation (old `ExecStart` restored in a fixture copy leaks) + required positive row; capture outputs into variables rather than `producer | grep -q`.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-202 (carried self-refusal) with an addendum via `soleur:architecture`: "the refusal's reach includes the unit wrapper: a systemd unit that runs a credential-handling script must not expand, export or otherwise name the secret in its `ExecStart`; the script resolves its own secret after its refusal. Enforced for `doppler run` units by `doppler-injection-bound.test.sh` (wrapper-expansion finding + authored wrapper-ack dict)." This is an in-plan task (Phase 4), not a follow-up issue.

### C4 views

No C4 impact. Read in full for this check: `model.c4` (998 lines), `views.c4` (131), `spec.c4` (54). Checked against: (a) external human actors - none added or changed; (b) external systems - Doppler (`doppler`) and Better Stack (`betterstack`) are already modeled and their edges are unchanged; (c) containers / data stores - none touched; per-unit systemd probe units are not modeled at all (a grep for `nic.guard|probe|heartbeat|doppler|systemd|betterstack` in `model.c4` returns only the Doppler/Better Stack systems and unrelated descriptions); (d) actor-to-surface access relationships - unchanged. Count parity: `bash plugins/soleur/test/c4-count-parity.test.sh` run on 2026-10-20 -> `ALL TESTS PASSED`. The work phase re-runs it (no `.c4` file is edited, so it must stay green).

### Sequencing

The ADR addendum describes the state after this PR merges and applies; no soak gate.

## Guard Contract

### Guard 1 - Unit wrappers never expand a doppler-injected secret (scanner stage in `doppler-injection-bound.test.sh`)

**Property.** No `Exec{Start,StartPre,StartPost}` of any `doppler run` unit the scanner enumerates contains an indirect expansion (`${!NAME}` or `${!NAME:-}` and the other operator spellings) unless the unit is in the authored, cardinality-pinned wrapper-ack dict, and every ack names a unit that still has one.

**Assembly.** The scanner's four unit surfaces plus the injected-directive surface (service files, sh-heredoc, tf-heredoc, cloud-init, sh-injected), every directive of every unit (`infos` list, not the first match), both indirect spellings (the plain `\w+` form and the operator-suffixed form the new script uses). Chokepoint: `analyse_exec()`'s `indirect` list, the single function every doppler directive flows through. Population reason side: the target script's own indirect expansion over a `*_KEY`-named variable (comment-stripped; regex `\$\{!(\w*_KEY)(?::?[-+=?][^}]*)?\}`, CTO amendment 2026-10-20 after a reviewer measured the unrestricted form pulling `inngest-luks-cutover.service` in via `${!_seam+x}` and failing it with READ_SET_FAIL) keeps a fixed unit inside the Guard-2 population so its existing ACK stays valid. A script whose key variable is not named `*_KEY` is outside script-side coverage by convention (stated in the PR). The unit-side wrapper finding keeps the broader any-name `${!` form. Measured baseline: `CENSUS: doppler_run_units=20`, `bound_required_population=10` (floors 12 / 5); both must read unchanged after the change (no unit may enter or leave the population by this PR, and the widened regex must not pull a new script into it).

**Mutation matrix.**

| # | Edit (fixture copy of the tree, never the real files) | Must go RED because |
|---|---------------------------------------------------------|----------------------|
| G1.1 | restore `export WEB_NIC_GUARD_URL="$${!WEB_NIC_GUARD_URL_KEY}"` in the fixture nic-guard unit | unit-side indirect, no wrapper ack -> `FINDING ... wrapper expands a secret` (rc 2) |
| G1.2 | add a second `ExecStartPre=` line with an indirect expansion to an otherwise compliant unit (second member after a compliant first) | the check quantifies over every directive, not the first |
| G1.3 | spell the expansion `$${!KEY:-}` (operator suffix) | the regex covers the spelling the script itself uses |
| G1.4 | make the wrapper stage a no-op (early return) in the scanner source | own-dispatch floor: new `CENSUS: wrapper_units_checked=N min=M` -> `CENSUS_FAIL` (rc 3); a stage that checks 0 units and exits 0 is vacuous |
| G1.5 | strip the script-side `${!...}` from the fixture `web-private-nic-guard.sh` while its ACK stays | unit leaves the population -> `ACK_FAIL stale=` (rc 5): proves the script-side reason is what holds the unit in |
| G1.6 | delete the wrapper-ack entry of an unfixed sibling (`web-git-data-probe.service`) | unfixed unit with no ack -> FINDING |
| G1.7 | add a wrapper-ack entry for a FIXED unit | stale wrapper ack -> `ACK_FAIL` (rc 5) |
| G1.8 | edit the wrapper-ack pin (2) without the dict | `ACK_FAIL wrapper_ack_cardinality` |
| G1.9 | fixture script bodies: `${!FOO_KEY:-}` in a doppler target script (must ENTER the population), `${!_seam+x}` (must NOT), and the real `inngest-luks-cutover.sh` (stays out, population stays exactly 10) | the script-side regex is bound to the `_KEY` convention, not to any indirect form |

Harness rows (edit to the SUITE, plus must-PASS): GH1 - flip the verdict arm of the new `expect_red_scanner` rows (assert GREEN where RED is expected) and require the suite to fail, via the existing `R*` self-check pattern in that file. GH2 - must-PASS non-canonical input: a fixed unit written as `ExecStart=/usr/bin/doppler run --project soleur --config prd -- /usr/local/bin/web-private-nic-guard.sh` (no outer `bash -c`) is GREEN and counted in `wrapper_units_checked`. GH3 - control: the unmutated fixture tree is GREEN (a scanner that rejects everything cannot pass GH2/GH3). GH6 - the file's existing loop that asserts every CENSUS floor is nonzero (about line 766) gains `wrapper_units_checked`, so zeroing that floor turns the suite red.

**Anchor.** The wrapper-ack dict and its pin live in the same file as the check, so one diff could weaken both; this guard proves consistency, not integrity. The outside anchor: the two unfixed units are listed on issue #9639 as not fixed (no string assertion on the reason text); the dict can only ratchet DOWN (a fix removes an entry and lowers the pin), and a new entry is a visible diff to a named, tracked set reviewers read.

### Guard 2 - The unit's real `ExecStart` never leaks the secret under xtrace, and the script resolves it only after the refusal (per-unit behavioral suites)

**Property.** Launching the unit's real `ExecStart` (systemd `$$` unescaped, `doppler` stubbed) under `SHELLOPTS=xtrace` or a `BASH_ENV` `set -x` exits 78 with the refusal message and the synthetic secret value appears in neither stream; and without xtrace the same launch delivers that value to `curl`'s stdin config.

**Assembly.** Launch forms: `SHELLOPTS=xtrace`, `BASH_ENV` `set -x` (the unit has no `bash -x` token to inject; the existing X1 rows keep covering `bash -x` against the script). Code paths that touch the secret: the unit's `ExecStart*` lines (static row over EVERY `Exec*` directive in the file), the script's key read and `${!KEY:-}` expansion (order row), the script's later uses (`URL`, `_hb_curl`, refusal markers; the existing transport rows), and the child environment (env-capture row, with the key-named line excluded). The nic-guard suite carries the full row set. The zot suite carries the lean subset (static, xtrace launch in both forms, positive delivery, dispatch, hoisted-lookup, one hostile key) with `ZOT_PULL_TOKEN` set because its refusal is conditional on it; it does not duplicate the invalid-key table.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|------|----------------------|
| G2.1 | fixture `.service` with the pre-fix `ExecStart` restored (literal in the test) | negative control: the xtrace launch MUST show the synthetic secret (leak visible), proving the harness can see the defect |
| G2.2 | script copy with the lookup hoisted above the refusal `case` block | reorder row: under `SHELLOPTS=xtrace` the secret appears in `ERR` (an order property needs a reorder row; deleting the lookup would only red the positive row) |
| G2.3 | script copy without the key charset check | hostile key `a[$(touch PLANT)]` executes -> `PLANT` exists |
| G2.4 | script copy that `export`s the resolved URL | env-capture row: the stub curl's `env` dump, with the line that starts with the key name removed (Doppler injects the secret under that name, so a correct run always shows it there), must not contain the value anywhere else |
| G2.5 | add a second `ExecStartPre=` line expanding the secret to the fixture `.service` | static row quantifies over every `Exec*` directive |
| G2.6 | stub `doppler` that exits 0 without exec'ing the script | own-dispatch row: refusal text must be present and rc 78, so "no secret in output" cannot pass for a launch that never ran |

Harness rows: GH4 - must-PASS non-canonical (the bare-variable-ignored case is a plain test row, not a mutation: a pre-set bare `WEB_NIC_GUARD_URL` with no key sends NO beat and logs `reason=empty`): the production-shaped keys `WEB_NIC_GUARD_URL_WEB_1` and `WEB_NIC_GUARD_URL_WEB_2` (different, contract-permitted valid names) resolve and are delivered; a key with a lowercase letter is refused under `LANG=en_US.UTF-8` too (a locale-collated `[A-Z]` range would admit it); invalid keys run in ONE table-driven loop (`lowercase`, `1LEAD`, `A B`, `A-B`, `a[$(touch PLANT)]`, newline, empty) plus a short list of valid-but-special names (`BASH_ENV`, `RANDOM`, `PATH`) that must resolve as plain reads with no execution and no beat (the contract states they read harmlessly); the old-wrapper + new-script transitional pair (stray bare var exported with a different value, key present) uses the KEY's value.

**Launch mechanics (measured by the plan reviewer on this machine).** (a) The stub `doppler` only skips to `--` and `exec "$@"`; it never expands or exports the secret itself, because a stub that does `export FOO=secret` leaks the value through its own xtrace and would make both the positive row and the G2.1 control vacuous - the synthetic secret is pre-exported in the test environment instead (verified: 0 leaks with the new `ExecStart`, 2 with the old one). (b) `SHELLOPTS=xtrace` cannot be a command prefix to `eval` (readonly variable): launch with `env SHELLOPTS=xtrace bash -c 'eval "$1"' _ "$LINE"`; the `BASH_ENV` form works as is. (c) The extraction unescapes `$$` and strips `%` specifiers, asserts the extracted line contains `/usr/local/bin/<script>.sh` BEFORE rewriting it to the script under test (so the rewrite cannot be a silent no-op), and carries one comment saying systemd's `'\''` quoting evaluates like the shell's, which is why running the line through `eval` is faithful.

**Anchor.** The pre-fix `ExecStart` literal is the only stored value; it is compared to nothing in the tree (it is the mutant, not a reference), so a weakening cannot hide by editing both. The scanner Guard 1 is the independent structural backstop for the same property.

## Implementation Phases

### Phase 1 - RED tests first (`cq-write-failing-tests-before`)

1.1 `web-private-nic-guard.test.sh`: add the harness mapping (default env becomes `WEB_NIC_GUARD_URL_KEY=WEB_NIC_GUARD_URL_SYNTH` + `WEB_NIC_GUARD_URL_SYNTH=<url>`, add `-u WEB_NIC_GUARD_URL` to the scrub list, rewrite the ~14 `EXTRA_ENV` `WEB_NIC_GUARD_URL=` fixtures to `WEB_NIC_GUARD_URL_SYNTH=`), then the new rows: key unset; invalid keys (`lowercase`, `1LEAD`, `A B`, `A-B`, `a[$(touch PLANT)]`, newline, empty) -> no execution, `reason=empty`, a value-free invalid-key line, no beat; bare var ignored; env capture; hoisted-lookup mutant; unit rows (static over every `Exec*` directive, behavioral xtrace x2 forms, G2.1 leak control, positive row, dispatch row). Invalid keys go through one table-driven loop. Rewrite the `#9639` comment-assertion. Raise `MIN_CASES` in lockstep (measure from the green run).
1.2 `web-zot-consumer-probe.test.sh`: the lean subset (see Guard 2 Assembly) against `WEB_ZOT_CONSUMER_URL`, token set for the xtrace launches.
1.3 `doppler-injection-bound.test.sh`: scanner changes are written test-first as the new RED rows G1.1-G1.9, GH1-GH3, GH6 (all rows are CTO-ruled or required by the Guard Contract gate: wrapper finding, second member, spelling, own-dispatch floor, stale ack) (run them against the unchanged scanner: they must fail), then the scanner edit in Phase 2.
1.4 Run the three suites: the new rows must be RED against the current tree (record the failing row names in the PR body).

### Phase 2 - GREEN

2.1 `web-private-nic-guard.sh`: after the existing refusal (the lookup site is the existing `URL=` line, below the refusal), replace `URL="${WEB_NIC_GUARD_URL:-}"` with: read `WEB_NIC_GUARD_URL_KEY`; validate with a `case` glob under `LC_ALL=C` (`''|[!A-Z]*|*[!A-Z0-9_]*` -> invalid, same style as `_hb_url_ok`); on valid `URL="${!_key:-}"` (a plain, unexported variable); invalid/unset -> `URL=""` with a flag; in the existing `-z "$URL"` branch, inside the same `_refusal_due` block, add a value-free line when the flag is set. Rewrite the header LIMIT comment and the step-7 comment that name #9639 as pending.
2.2 `web-private-nic-guard.service`: `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/web-private-nic-guard.sh'` (no `$`, no inner shell, no export); rewrite the comment block that describes the wrapper expansion. Keep `Environment=HOME=/root`, `SyslogIdentifier`, `EnvironmentFile`.
2.3 Same pair for zot: `web-zot-consumer-probe.sh` (lookup placed after the refusal `case` AND after the `--canary-only` early exit, next to the first real use, replacing `URL="${WEB_ZOT_CONSUMER_URL:-}"` at line 103; the `--canary-only` ExecStartPre path runs outside `doppler run` and never reaches the lookup) and `web-zot-consumer-probe.service`. Header comment of the script: state that the refusal fires on the pull credential, or on the key name outside `--canary-only` (reworked in review per the CTO ruling).
2.4 `doppler-injection-bound.test.sh` scanner: widen the unit-side `INDIRECT_RE` to accept an optional operator suffix; script-side population reason restricted to `*_KEY`-named indirect expansion (G1.9); unit-side wrapper finding over every directive; `WRAPPER_ACK_REASONS` (2 entries: `web-git-data-probe.service`, `inngest-consumer-probe.service`, each reason naming #9639 in prose) with `WRAPPER_ACK_CARDINALITY = 2`; `CENSUS: wrapper_units_checked` with a floor derived from a green run; stale-wrapper-ack check. Update the two fixed units' `ACK_REASONS` text (still true, now script-side). `ACK_CARDINALITY`, `MIN_POPULATION`, `MIN_DOPPLER_UNITS` stay as they are.
2.5 `web-probe-envwrite.sh`: comment-only correction of the "unit's ${!KEY} indirect expansion" sentence for the two fixed units.

### Phase 3 - Repo-global ratchets and verification (before push)

3.1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` (PJ_TRIPLES must be unchanged; recompute with the documented derivation before and after - new test rows capture output into variables or here-strings, no new `producer | grep -q`), `python3 scripts/lint-trap-tempfile-ownership.py` + `scripts/lint-trap-tempfile-ownership.test.sh` (no new highwater entry; reuse the suites' existing `$TMP`), `bash scripts/guard-vacuity-floor.test.sh`, `shellcheck` on every touched `.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation, not a hand-listed path set), `npx markdownlint-cli2` on the plan and `tasks.md`, and the discoverability probe command verbatim on the final tree.
3.2 Run the registered infra suites whose inputs are edited: the three edited suites, `fresh-boot-parity.test.sh` and `web-host-provisioner-parity.test.sh` (CI runs the rest). A shared ratchet baseline that a sibling PR can move is never lowered here.
3.3 Simulate the rollback before ship (a recipe nobody has run is first executed during an incident): in a scratch detached worktree under `/var/tmp`, `git revert --no-commit` this PR's commits, then run the three edited suites and `fresh-boot-parity.test.sh` against it; write the recipe from what that run needs into the PR body.
3.4 Measure and record in the PR body: `doppler-injection-bound` CENSUS lines before and after (population 10 -> 10, doppler units 20 -> 20).

### Phase 4 - ADR addendum and tracking

4.1 ADR-202 addendum (a 3-line edit via `soleur:architecture`, not a separate phase of work; see above).
4.2 Post a comment on #9639 (no new issue): F6 fixed for nic-guard + zot; git-data-probe and inngest-consumer-probe recorded NOT fixed, reason "no xtrace refusal exists in the script, so a moved lookup has nothing to follow; adding an unconditional refusal is a separate #7797-class change; inngest-consumer-probe also sources `inngest-registry-probe.sh` (open PR #10501)"; F7/F8 remain open. Record the merge on #9217 (no DONE) and close out the series status there after the post-merge checks.

## Files to Edit

- `apps/web-platform/infra/web-private-nic-guard.sh`
- `apps/web-platform/infra/web-private-nic-guard.service`
- `apps/web-platform/infra/web-private-nic-guard.test.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.sh`
- `apps/web-platform/infra/web-zot-consumer-probe.service`
- `apps/web-platform/infra/web-zot-consumer-probe.test.sh`
- `apps/web-platform/infra/doppler-injection-bound.test.sh`
- `apps/web-platform/infra/web-probe-envwrite.sh` (comment only)
- `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md` (addendum)

Glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was confirmed with `git ls-files` in the worktree; no glob is prescribed.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9639-f6-nic-guard-url-after-refusal/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9639-f6-nic-guard-url-after-refusal/decision-challenges.md`

## Files NOT touched (constraint record)

`apps/web-platform/infra/cloud-init.yml` (PR #10501), `betterstack-logs-alerts.tf`, `.github/workflows/apply-web-platform-infra.yml`, `server.tf` (PRs #10501/#10546/#7390), `.claude/hooks/grep-q-pipe-guard.test.sh` and `scripts/guard-vacuity-floor.test.sh` (touched by open sibling PRs), `web-git-data-probe.*`, `inngest-consumer-probe.*`, `inngest-registry-probe.sh`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` was matched against every path in the two file lists above with `jq --arg path ... contains($path)`; the work phase re-runs the same query before the first commit and applies the fold-in / acknowledge / defer disposition if a match appears.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file changes. The existing resources `terraform_data.private_nic_guard_install` and `terraform_data.zot_consumer_probe_install` re-fire because their `triggers_replace` hash `file()` of the `.sh`/`.service`/`.timer`; both are in the per-merge apply target list (`apply-web-platform-infra.yml` lines 1247-1248, verified). No new variable, secret or provider; the Doppler vars `WEB_NIC_GUARD_URL_WEB_1` / `WEB_ZOT_CONSUMER_URL_WEB_1` and the `*_KEY` entries in `/etc/default/<unit>` are unchanged.

### Apply path

In-place via the per-merge apply, no host replace, no downtime. The provisioner copies `.sh`, then `.service`, then `.timer`, reloads the systemd manager, and re-enables the timer. Transitional-pair safety (verified by reading the unit/script contract, and pinned by test row GH5): `.sh` lands first, so the only transient pair is NEW script + OLD wrapper, which works (the key is in the `EnvironmentFile`, the script resolves it itself and ignores the wrapper's exported bare variable). The reverse pair (old script + new wrapper) cannot occur in this order. Blast radius: one 5-minute nic-guard tick and one zot tick on web-1; a bug would lapse a heartbeat and send a "host down" email, hence the required positive row.

### Host fan-out

No SSH `terraform_data` provisioner is added or edited. web-2: `birth-covered: predates web-2 birth` (existing classification in `web-host-provisioner-parity.test.sh`, lines 402/407, unchanged). Residual to state in the PR: web-2 keeps the self-consistent OLD pair (old `.service` + old `.sh`, both baked in the image) until its next `-replace`, when it picks up both new files together via the `host_script_files` bake; that exposure equals today's and is not worsened. The baked-file content hash changes, user_data changes, and `ignore_changes = [user_data]` on `hcloud_server.web` means no host replace (same mechanism the F5 ruling relied on).

### Distinctness / drift safeguards

No dev/prd distinctness change. The `.service` and `.sh` stay byte-identical across the SSH and image-bake delivery routes (they are the same repo files). `fresh-boot-parity.test.sh` and `web-host-provisioner-parity.test.sh` must stay green.

### Vendor-tier reality check

No vendor resource is created. The Better Stack heartbeat `soleur-web-nic-guard-web-1` (`period = 360`, `grace = 120`, `web-probe.tf`) is the live signal; a regression pages by email within about 8 minutes.

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeats soleur-web-nic-guard-web-1 and the zot consumer beat, pinged on every healthy run by the two scripts
  cadence: nic-guard every 5 min (OnUnitActiveSec=5min); zot per its timer
  alert_target: operator email via Better Stack heartbeat (grace 120s on a 360s period)
  configured_in: apps/web-platform/infra/web-probe.tf (betteruptime_heartbeat.web_nic_guard, doppler_secret.web_nic_guard_url)
error_reporting:
  destination: journald SyslogIdentifier web-nic-guard and web-zot-consumer-probe, shipped by Vector Source 4 (vector.toml host_scripts_journald) to the Better Stack Logs source
  fail_loud: stderr line SOLEUR_CREDENTIAL_REFUSED script=web-private-nic-guard reason=empty var=WEB_NIC_GUARD_URL (hourly-limited) plus the new value-free invalid-key line; the beat lapses so absence alarms
failure_modes:
  - mode: lookup broken or key unreadable on web-1 after the apply (URL resolves empty)
    detection: (layer 3: vector Source 4 host_scripts_journald, exact SyslogIdentifier web-nic-guard) the reason=empty marker in Better Stack Logs after the apply timestamp (post-merge query), and the heartbeat going down
    alert_route: Better Stack heartbeat absence -> operator email
  - mode: zot key valid but its secret missing (the beat URL resolves empty)
    detection: (layer 3: vector Source 4 host_scripts_journald, exact SyslogIdentifier web-zot-consumer-probe) the `WEB_ZOT_CONSUMER_URL unset` stderr line each 60s tick, and the zot beat going down
    alert_route: Better Stack heartbeat absence -> operator email
  - mode: invalid key name in /etc/default/web-private-nic-guard
    detection: (layer 3: vector Source 4 host_scripts_journald, exact SyslogIdentifier web-nic-guard / web-zot-consumer-probe) the value-free invalid-key stderr line in the same Logs source
    alert_route: heartbeat absence -> operator email (a standing log alert is F8, out of scope)
  - mode: web-2 still on the old pair (not a failure: the old unit and script are mutually consistent)
    detection: none by design (layer 3 would show the old, unchanged emitters); recorded in the PR body
    alert_route: none (not applicable until web-2 is replaced)
logs:
  where: the unit journal (identifier web-nic-guard), shipped off-box to Better Stack Logs
  retention: Better Stack Logs source retention (plan-tier); journald persistent per journald-config
discoverability_test:
  command: grep -c -e 'config prd -- /usr/local/bin/web-' apps/web-platform/infra/web-private-nic-guard.service apps/web-platform/infra/web-zot-consumer-probe.service
  expected_output: web-private-nic-guard.service:1
```

The probe above is the credential-free static half: the unit's `ExecStart` runs the script directly under `doppler run`, with no inner shell. Measured on the pre-fix tree it prints `web-private-nic-guard.service:0` (exit 1), so it discriminates; after the change it prints `:1` for both files with exit 0, one token of which is the `expected_output` literal. It contains none of the shell-active characters preflight Check 10 rejects (`|`, `;`, `&`, `<`, `>`, `$`, backtick). The live half needs Better Stack and Doppler read access and is run by the postmerge skill (below), not by the discoverability probe. The work phase re-runs this exact command on the final tree before ship.

## Post-merge verification (no SSH; run by `soleur:postmerge`)

1. Resolve the merge SHA (`gh pr view 10637 --json mergeCommit,mergedAt`; the SHA is empty until the merge lands, so an empty value means "not yet", never "no run"), find the `apply-web-platform-infra.yml` run whose `headSha` equals it (`gh run list --workflow apply-web-platform-infra.yml --limit 10 --json databaseId,conclusion,headSha,createdAt`; verified read-only on 2026-10-20, it returns those four fields), require `conclusion == success`, and in `gh run view <id> --log` count the ANCHORED lines `terraform_data.private_nic_guard_install: Creation complete` and `terraform_data.zot_consumer_probe_install: Creation complete` (both >= 1). Measured on run 39351965961 (an unrelated, no-change apply): the bare resource name appears twice there, once in the `-target=` list and once as `Refreshing state`, and `Creation complete` appears zero times, so an unanchored grep for the name would pass on a run that applied nothing.
2. Better Stack heartbeat `soleur-web-nic-guard-web-1` is `up` with a ping later than the apply completion time (API read with the read-only token from Doppler; value never printed). Same for the zot consumer beat.
3. Better Stack Logs, read no earlier than about ten minutes after the apply completes (nic-guard ticks every 300s, zot every 60s): (a) a row whose message STARTS with `SOLEUR_PRIVATE_NIC nic_ok=true`, with NO tag filter (it is a direct POST to the ingest, not a journald line, so it has no SyslogIdentifier; the nic failure paths echo the same text after `not shipped:` or `FAILED:` in journald, so anchor on the start of the message) proves the ingest is alive; (b) the two beats from step 2 are the authority for "the new pair works" (a ping later than the apply completion); (c) under SyslogIdentifier `web-nic-guard` and `web-zot-consumer-probe` since the apply, none of `reason=empty`, `WEB_NIC_GUARD_URL_KEY is unset`, `WEB_ZOT_CONSUMER_URL unset`, `WEB_ZOT_CONSUMER_URL_KEY is unset`. A missing marker alone is weak evidence (the nic hourly limiter can hide one); the beat timestamps decide.
4. Failure handling: any of the three fails -> revert the PR (the per-merge apply restores the old pair) and record on #9639.
5. Record the merge on #9217 (no DONE), then close out the series status there.

## Rollback

Revert this PR; the per-merge apply re-fires `private_nic_guard_install` and `zot_consumer_probe_install` and restores the old script + unit pair on web-1 (web-2 never left the old pair). The old pair works with the new Doppler/EnvironmentFile data, because the data is unchanged. On the revert apply the provisioner copies `.sh` first and `.service` second, so for one tick the pair is OLD script + NEW wrapper: the old script reads the bare variable, which the new wrapper no longer exports, sees it empty and takes the `reason=empty` path (no beat for that tick, then the `.service` copy lands). That one-tick gap is accepted; the forward direction (NEW script + OLD wrapper) is the safe order. The scanner revert restores the four unit-side population reasons and ACKs together. The simulated-revert run (Phase 3.3) replaces this paragraph with the measured recipe in the PR body.

A revert can email once: between the old script and the new unit landing there is a window of seconds where the old script reads a bare variable that is no longer exported, and one skipped 300s tick can exceed the beat tolerance. Decode it as `reason=empty var=WEB_NIC_GUARD_URL` with no key line; it clears on the next tick.

## Test Scenarios

1. Valid key + value, no xtrace, via the real `ExecStart` + stub `doppler` + stub `curl`: the URL arrives on curl's stdin config; beat sent; rc 0.
2. Same launch with `SHELLOPTS=xtrace`: rc 78, refusal message, secret in neither stream. Same with `BASH_ENV` `set -x`.
3. Old `ExecStart` restored in a fixture copy, same xtrace launch: the secret IS visible (control).
4. Script copy with the lookup hoisted above the refusal: secret visible under `SHELLOPTS=xtrace`.
5. Key unset: no beat, one `reason=empty` marker, rate-limited to one per hour.
6. Hostile keys (`a[$(touch PLANT)]`, `lowercase`, `1LEAD`, `A B`, `A-B`, newline): no execution (`PLANT` absent), no beat, value-free invalid-key line.
7. Pre-set bare `WEB_NIC_GUARD_URL` with no key: ignored, no beat. Pre-set bare var with a key: the key's value wins.
8. Stub curl `env` dump never contains the URL (not exported).
9. Scanner: G1.1-G1.9 and GH1-GH3, GH6 (see Guard Contract); census lines unchanged.
10. Zot: scenarios 1-4 and 6 with `ZOT_PULL_TOKEN` set; `--canary-only` mode unchanged (key name alone does not refuse a traced canary; a pull credential still does). Both refusal disjuncts are pinned by their own launch.

## Acceptance Criteria

- [ ] Phase 1 rows fail against the unchanged tree and pass after Phase 2 (names recorded in the PR body).
- [ ] `grep -cE '^Exec[A-Za-z]*=.*[$]{1,2}[{][!]' apps/web-platform/infra/web-private-nic-guard.service apps/web-platform/infra/web-zot-consumer-probe.service` prints `:0` for both files (measured on the pre-fix tree: `:1` for both, so it discriminates). Scoped to `Exec*` directives on purpose: a comment may legitimately name the construct it forbids.
- [ ] `web-private-nic-guard.test.sh`, `web-zot-consumer-probe.test.sh`, `doppler-injection-bound.test.sh` green; `doppler-injection-bound` CENSUS shows `doppler_run_units=20` and `bound_required_population=10` before and after, `ACK_CARDINALITY = 8` unchanged, `WRAPPER_ACK_CARDINALITY = 2`.
- [ ] Repo-global ratchets green with no baseline lowered: `grep-q-pipe-guard.test.sh` (PJ_TRIPLES unchanged), `lint-trap-tempfile-ownership`, `guard-vacuity-floor`, `lint-guard-contract.py`.
- [ ] `git diff --name-only origin/main...HEAD` (merge-base form, so a sibling merge cannot redden it) lists no file from "Files NOT touched" and only the files in the two lists above plus the pipeline-written `knowledge-base/INDEX.md` / `specs/<branch>/session-state.md` if regenerated.
- [ ] ADR-202 addendum present; `c4-count-parity` green; no `.c4` file edited.
- [ ] PR body: `Ref #9639`, `Part of tracker #9217`, no closing keyword; lists the two unfixed siblings with the reason and the zot refusal-predicate note (pull credential, or key name outside `--canary-only`); web-2 residual stated.
- [ ] #9639 comment posted (fixed / not fixed / F7 F8 open); #9217 merge recorded without DONE.
- [ ] Post-merge checks 1-3 pass (pre-merge ACs above are verified by the commands shown; these three are verified after the apply).

## User-Brand Impact

- **If this lands broken, the user experiences:** the web-1 private-NIC or zot heartbeat stops arriving, Better Stack sends a false "host down" alert email for a healthy host (no end-user-visible product change; web traffic is unaffected).
- **If this leaks, the user's workflow is exposed via:** the secret heartbeat URL printed by an xtrace launch into the journal shipped to Better Stack; whoever reads it could ping the beat and mask a dead private NIC. No user data, token or tenant content is involved.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the URL gates only an operator-facing liveness signal, with no user data and no path to a tenant, so it is below `aggregate pattern`.

threshold: none, reason: the touched infra scripts handle one operator-side liveness URL and a Better Stack ingest token, no end-user data or credential.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled all four forks (scope, scanner coupling, script contract, test shape) on 2026-10-20; rulings are in `decision-challenges.md`. No product, marketing, legal, finance, sales, support or operations implication: this is a host-script and test change with no user-facing surface, no new vendor and no spend.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix #9639 finding F6 only" [brief] | Overview, Phases 1-2 | mapped |
| 2 | "move the ${!WEB_NIC_GUARD_URL_KEY} indirect lookup into web-private-nic-guard.sh AFTER the xtrace refusal, so the service wrapper no longer expands the secret" [brief] | Phase 2.1, 2.2 | mapped |
| 3 | "add a failing test first that proves the wrapper no longer expands the secret before the refusal, with a mutation that restores the old expansion" [brief] | Phase 1.1, Guard 2 (G2.1) | mapped |
| 4 | "check web-zot-consumer-probe and web-git-data-probe (and any other unit with the same inner bash -c indirect expansion) and include ONLY those whose files are not touched by any other open PR" [brief] | Overview scope table, Phase 2.3, Phase 4.2 | mapped |
| 5 | "record the others on #9639 as not fixed with the reason instead of filing a new issue" [brief] | Phase 4.2 | mapped |
| 6 | "do NOT touch cloud-init.yml ... betterstack-logs-alerts.tf, apply-web-platform-infra.yml, server.tf" [brief] | Files NOT touched | mapped |
| 7 | "do NOT harden the Sentry-DSN curl transport (#9638 recorded not fixed); no F7 boot-trail event or F8 alert" [brief] | Cut List | mapped |
| 8 | "run the repo-global ratchets that a file-selected suite set cannot see before pushing" [brief] | Phase 3.1 | mapped |
| 9 | "post-merge check that private_nic_guard_install applied and the guard timer fires on web-1 via Sentry/Better Stack (no SSH)" [brief] | Post-merge verification | mapped |
| 10 | "Record the merge on #9217 (no DONE), then close out the series status on #9217." [brief] | Phase 4.2, Post-merge 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| nic-guard `.sh` / `.service` edits | "move the ${!WEB_NIC_GUARD_URL_KEY} indirect lookup into web-private-nic-guard.sh AFTER the xtrace refusal" | asked |
| zot `.sh` / `.service` / test edits | asks 4 | asked |
| `web-private-nic-guard.test.sh` / `web-zot-consumer-probe.test.sh` rows | asks 3 | asked |
| `doppler-injection-bound.test.sh` scanner change | — | inferred - justification: without it the four ACKs go stale and the Guard-2 coverage of these units silently ends (measured: rc 5 `ACK_FAIL stale`), i.e. the change would break a green gate and blind it |
| `web-probe-envwrite.sh` comment | — | inferred - justification: the comment names the unit's `${!KEY}` expansion, which becomes false; a stale comment on a secret-handling path misleads the next editor |
| ADR-202 addendum | — | inferred - justification: plan skill Phase 2.10 makes the ADR update a deliverable when an existing ADR is extended (here: the refusal's reach now includes the unit wrapper) |
| key charset validation | — | inferred - justification: moving `${!name}` into the script puts a root-run indirect expansion on an env-file value; bash evaluates subscripts in `name`, so the validation is part of moving it safely (CTO F3) |
| `decision-challenges.md`, `tasks.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | asked |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform/infra` (plus one ADR file under knowledge-base)
- Planned files: 9 edited + 2 created | Estimated changed lines: about 450 (mostly tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- `$$` in a `.service` file is systemd's escape for a literal `$`; the behavioral test MUST apply that unescape before running the extracted line or the old-`ExecStart` control would not expand and the control would be vacuous.
- The script-side population reason must be bound to `*_KEY`-named indirect expansion, never to any `${!...}`: the unrestricted form measurably moved the population 10 -> 11 and turned `inngest-luks-cutover.service` red (rc 6). Re-measure `doppler_run_units` and `bound_required_population` (20 / 10) and the ACK set after the edit; `${!R_NAME[@]}` array forms in the zot script must stay unmatched.
- Do not edit the shared ratchet files. If a sibling merges first and moves `PJ_TRIPLES` or a vacuity floor, rebase and recompute; never lower.
- The zot refusal is conditional on the credential; under `doppler run` it always is set, but the PR must say so rather than imply the same unconditional guarantee as the nic-guard.
