---
title: "feat: arm-heartbeats --status and --arm-one (arming tooling for the git-data host heartbeat)"
date: 2026-10-11
slug: arm-heartbeats-status-and-arm-one
branch: feat-one-shot-9980-arm-one-tooling
issue: 9980
closes: 9980
refs: [9438, 8211, 8093]
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat: `arm-heartbeats.sh --status <name>` and `--arm-one <name> [--id <id>]`

## Enhancement Summary

**Deepened on:** 2026-10-11
**Gates run (mechanical):** User-Brand Impact (4.6), Observability (4.7), PAT-shaped variable sweep (4.8, no hits), Guard Contract lint (4.11, 3 entries green), Scope Check (4.12, one live section); cited issue/PR states re-verified live (`gh issue view`: #9438, #9980, #8211, #8093, #9705 OPEN; #9936 MERGED); the only cited rule id (`cq-write-failing-tests-before`) exists in AGENTS.md. Not run: the open-ended per-skill/per-agent fan-out (the change is one bash script plus its suite; plan-review already ran three reviewers).
**Plan review applied (before deepen):** DHH, Kieran and code-simplicity findings folded in: positional 4th `arm_one` parameter instead of a global override, mutation rows trimmed to M22-M33 with consistent numbering, resolver hardened (`.data` array check, delimiter and null sentinels, direct calls), transcript-diff and extra parity assertions cut.

### Key improvements from deepening
1. The vendor list shape was checked against Better Stack's published docs (WebSearch of the "List heartbeats" page): each row carries `period`, `grace`, `status`, `name`, `url`; the doc example shows `paused_at` (a timestamp) rather than a boolean `paused`, while this repo's own live reader (`heartbeat-live-reconcile.ts`) validates a boolean `paused` from the same endpoint. The resolver therefore prints `paused` as reported or `unreported` and NEVER gates on it; the only gates are `status` (via `arm_one`'s existing op/state check) and `period`/`grace` (fail closed).
2. The resolver's jq filter and delimiter handling were exercised on a synthetic page in the scratchpad: exact match only, `null` fields survive as the literal `null`, `\x1f`-delimited `read` keeps empty/null fields aligned (tab would have collapsed them), and `jq -e '.data | type == "array"'` exits 1 for both `{}` and `{"errors":...}` bodies.
3. Measured: existing mutation row M7 (`s|--max-time "$ARM_CURL_MAX_TIME_S" ||g`) lands on exactly 2 lines today; the resolver's own `--max-time` literal makes it 3 (deliberate, listed under Files to Edit). The phrase `rollback PATCH paused=true FAILED` occurs exactly once, so reusing it in new code would break M4's sed range.

### New considerations discovered
- `period`/`grace` have not been read live by this repo before; the owner's first `--status` is the first live read. Absent or non-integer values refuse (fail closed), so a wrong vendor-shape guess cannot arm.
- The vendor docs do not document `per_page`; this repo already relies on `?per_page=250` (`scripts/cutover-inngest.sh`, `reconcile-live-heartbeats.ts` allows `page`/`per_page`), so it is kept, and a 20-page bound covers a vendor that ignores it.

Spec lacks a `lane:` (no spec directory exists for this branch), so `lane` defaulted to `cross-domain` (fail-closed).

## Overview

PR #9936 (merged 2026-10-11) added the host-originated liveness feeder and its Better Stack
heartbeat `soleur-git-data-host-prd` (id 506836, period 60, grace 300), born paused and carried in
`heartbeat-manifest.ts` as `arming_pending: { tracking_issue: 9438 }`. The soak read is satisfied
(four `ok` rows over 32 minutes). The cutover runbook (step 7) forbids a by-hand unpause because
a manual unpause has no rollback if no beat follows, and `arm-heartbeats.sh` today accepts only
`--arm | --sweep | --help`, whose `--arm` walks a hard-coded six-monitor tfstate list (the per-merge
apply path) and cannot name one monitor.

This plan adds two modes to the existing script and nothing else on the apply path:

- `--status <name>`: read-only. Resolves the heartbeat by EXACT name over the full paginated
  `GET /heartbeats` list and prints `name / id / paused / status / period / grace`. rc 0 only for exactly
  one match.
- `--arm-one <name> [--id <id>]`: resolves the id the same way (exactly one exact-name match, and
  equal to `--id` when given), refuses when the fixed 150 s deadline exceeds the monitor's own
  `period + grace - 40` read from the API, then runs the EXISTING `arm_one` machinery (op/state gate,
  unpause, poll `status` to `up`, rollback to paused with one retry, state-file books, sweep hand-off)
  via a one-line override of arm_one's id-resolution line.

It also updates the runbook step 7 (replacing "do not arm by hand" with the command, the secret
NAMES and the no-exposure invocation), amends ADR-117, and ratchets the suite's assertion floor.
Running `--arm-one` against production is NOT part of this PR (separate owner step after merge).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (verified on this worktree) | Plan response |
|---|---|---|
| Issue #9980 says the script is `plugins/soleur/scripts/arm-heartbeats.sh` | It lives at `apps/web-platform/infra/arm-heartbeats.sh` (593 lines); no copy exists under `plugins/soleur/scripts/` | Use the real path everywhere; do not create a second copy |
| "the six `arm_one` call lines at the bottom stay untouched" | Confirmed: six hand-written `arm_one '<addr>' '<label>' <deadline>` lines (lines 525-537 plus inngest at 571). The ladder guard in `terraform-target-parity.test.ts` scans them with `^arm_one\s+'..'\s+'..'\s+(deadline)` | New `arm_one` call is spelled with double-quoted variables and is indented inside a function, so the scan neither counts it nor can be fooled by it (asserted, see Guard 3) |
| "arm_one resolves the id from TFSTATE_JSON with jq" | Confirmed (`arm_one`, the `id=$(jq -r --arg a "$addr" ...)` line). `arm_one` is defined AFTER the `--arm` tfstate/required-env block, which `exit 1`s on failure, so the function is unreachable for a mode that has no tfstate | Wrap that block in `if [[ "$MODE" == arm ]]`; add an optional 4th positional `arm_one` parameter as the id override; dispatch `status` / `armone` after the function definition and before the six calls |
| "paginate, per_page=250" | `scripts/cutover-inngest.sh:3279` uses `?per_page=250` with NO pagination follow (single page); `plugins/soleur/scripts/reconcile-live-heartbeats.ts` follows `pagination.next` with an origin+path pin, `page`/`per_page` only, 50-page bound | Port the reconcile script's contract to bash: follow `pagination.next` only when it starts with `${BS_API_BASE}/heartbeats?` and carries only `page`/`per_page`; bound 20 pages; refuse otherwise |
| "parity guard: ARM ladder guard" | Beyond the ladder, the guard pins `stripped.match(/curl\b/g).length == 1` and `stripped.match(/\$\(bs_api /g).length == 2` (the GET in `hb_fetch` and the PATCH in `hb_patch_paused`) in non-comment text | The list read is a third credentialed call site: change the pin 2 -> 3 with a rationale comment (honest), keep `curl` at exactly 1; do NOT dodge the pin by hiding the call from the regex |
| "ARMED_UNCONFIRMED defaults to a private mktemp file" | The `--arm`/`--sweep` contract makes `ARMED_UNCONFIRMED` REQUIRED. The state file is the only thing `--sweep` reads | `--arm-one` creates `mktemp` (0600) when unset, prints its path up front with the exact `--sweep` recovery command, removes it only when empty on exit, keeps it when non-empty |
| "BS_TOKEN needs write scope" | Doppler `soleur/prd_terraform` holds `BETTERSTACK_API_TOKEN` (the write token the apply workflow's ARM step reads via `doppler secrets get BETTERSTACK_API_TOKEN`) and `BETTERSTACK_API_TOKEN_READONLY` (names only, `doppler secrets --only-names`, no value read) | `--status` documents the READONLY name; `--arm-one` documents the write name |
| Fake curl in the suite handles `GET <base>/heartbeats/<id>` only | `id="${url##*/}"` would turn `.../heartbeats?per_page=250` into the id `heartbeats?per_page=250` and `exit 64` ("no fixture") | Extend the stub with a list endpoint (paged fixtures, `per_page=250` required, off-origin refusal) and self-test it (harness rows) |
| `heartbeat-manifest.ts` carries `arming_pending` for the row | Confirmed (`tracking_issue: 9438`); removal belongs to the record PR (runbook step 8, `Closes #9438`) | Out of scope here; this PR carries `Refs #9438` only |

## Research Insights

### Premise Validation (Phase 0.6)

- #9980 is OPEN; PR #9936 is MERGED (2026-10-11T09:25:13Z); #9438 is OPEN (closed by the later record PR). The target is not stale.
- Cited paths verified on this tree: `apps/web-platform/infra/arm-heartbeats.sh`, `.test.sh`, the runbook step 7 text (lines ~1229-1232 carry the exact "Do not arm by hand" sentence), ADR-117, ADR-283 (line 75 already says the tooling "must land before the owner's arm; tracked on #9980").
- The issue's path `plugins/soleur/scripts/arm-heartbeats.sh` is wrong (see table). Corrected silently in this plan; the PR body should note it.
- ADR corpus check: ADR-117 (executable arming; amendments 2026-07-17/18, 2026-08-20) and ADR-283 (host liveness heartbeat) govern. Neither rejects a named-monitor arm entry; ADR-283 anticipates it. No rejected alternative is being re-proposed.
- Capability claims verified, not asserted: `arm_one`'s tfstate-only id lookup (read), `usage()` prints the `# CONTRACT` block via a `sed` range ending at `#   mint-unreadable` (read), the stub's `exit 64` on an unknown id (read).

### Property List and Cut List (Phase 0.6b)

Properties the work must deliver:

1. P1. A named monitor can be armed with a measured beat and an automatic rollback, without editing the per-merge list.
2. P2. A name collision, a near-name, or a stale id can never cause the wrong monitor to be unpaused.
3. P3. The state of one named monitor is readable without any write.
4. P4. A failed or interrupted arm leaves a recorded, one-command recovery (the sweep books).
5. P5. The apply-path behaviour of `--arm` / `--sweep` is unchanged.
6. P6. The invocation never exposes the token (argv, xtrace, history) and the destination/shape guards are unchanged.

Mechanisms proposed by the brief, and what already buys the property:

| Mechanism in the ask | Property | Existing mechanism checked | Verdict |
|---|---|---|---|
| Reuse `arm_one` via id override | P1, P4, P5 | `arm_one` (grepped: unpause, poll, `hb_rollback` retry, `state_add/remove`) | KEEP: cheapest implementation; no second copy of the rollback |
| `ARMED_UNCONFIRMED` private mktemp | P4 | `--sweep` consumes any file path | KEEP, plus printed recovery command |
| Deadline 150 s and ceiling refusal | P1, P2 (a window past the first absence alert false-pages) | Ladder formula `period + grace - 40` documented in the script header | KEEP: reuse the header's own formula, derived not restated |
| Exact-name resolution + `--id` pin | P2 | `cutover-inngest.sh` resolves by name but takes `head -1` on a possible multi-match; reconcile script paginates | KEEP resolver, STRICTER than both (count must be 1) |
| A new `--rollback` / `--pause-one` mode | P4 | `--sweep` with `ARMED_UNCONFIRMED=<file>` already re-pauses every id on a file | CUT: not asked, `--sweep` already covers it; the recovery command names it |
| New standalone script instead of editing `arm-heartbeats.sh` | P1 | The brief mandates reuse; a second script would duplicate `hb_patch_paused`/`bs_api` | CUT |
| Regenerate `suite-shard-legs.tsv` / `suite-durations.tsv` | P5 | Suite already registered (`arm-heartbeats.test.sh`, leg 3, 21000 ms measured); no suite added | CUT unless the post-change runtime moves >50% (then `regenerate-shard-manifest.py --group infra --incremental --write`, never hand-edited) |

### Relevant learnings and files

- `knowledge-base/project/learnings/2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: token rides curl stdin config via `<(printf ...)`; the suite's floor was re-measured to 234, never lowered; fixture-relative-assert baseline rows are equality-checked and regenerated in the same commit.
- `knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` section 2: an ORDER/LIFETIME property needs a reorder row plus a case observing inside the window (the books must hold the id during the poll). Applies to the new mode through the external-cut case.
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts` (pagination contract to port), `plugins/soleur/lib/heartbeat-live-reconcile.ts` (row shape `data[].id` + `data[].attributes`).
- Consumers of `arm-heartbeats.sh` (grepped, whole repo): the workflow step `apply-web-platform-infra.yml` (calls `--arm` and `--sweep`; NOT edited), `plugins/soleur/test/terraform-target-parity.test.ts` (ladder + structural pins), `scripts/guard-vacuity-floor.test.sh` (PROMOTED_FILES lists the suite; no count), `plugins/soleur/test/fixture-relative-assert.baseline.txt` (rows `3 .../arm-heartbeats.sh`, `1 .../arm-heartbeats.test.sh`), `plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt` (one row quoting the stub's `kill -9 "$PPID"` line: do not edit that line), `apps/web-platform/infra/suite-shard-legs.tsv` / `suite-durations.tsv` (registration), `scripts/registry-heartbeat-poll.sh` and `git-data-root-key.test.sh` (comment mentions only), ADR-117/283, the runbook, `git-data.tf` comments.

## Open Code-Review Overlap

One open code-review issue names a planned file: #9705 ("review: dead-probe heartbeat for inngest wrong-volume alert") mentions `terraform-target-parity.test.ts`. Disposition: ACKNOWLEDGE. Different concern (inngest alert evidence); this plan touches only the ARM-script structural pins in that file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add `--status <name>` and `--arm-one <name>` to apps/web-platform/infra/arm-heartbeats.sh" | Phase 1-3, Files to Edit 1 | mapped |
| 2 | "(+ tests in arm-heartbeats.test.sh" | Phase 0, Phase 4, Files to Edit 2 | mapped |
| 3 | "+ runbook update in knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md step 7 replacing the \"do not arm by hand\" note with the command)" | Phase 6, Files to Edit 4 | mapped |
| 4 | "--status is read-only: exact-name match against GET /heartbeats (paginate, per_page=250), print name/id/paused/status, rc 1 on zero or multiple matches (never a regex; a name collision must not arm the wrong monitor)" | Phase 1 (`hb_resolve_name`), Phase 2 (`status`), Guard 1 | mapped |
| 5 | "--arm-one <name> [--id <id> pin]: resolves id the same way, requires exactly one exact-name match (and equality with --id if given), then reuses the existing arm_one machinery ... via a minimal override of the id-resolution line" | Phase 1 (override), Phase 3, Guards 1 and 3 | mapped |
| 6 | "deadline for --arm-one = 150 s and must refuse if > period+grace-40 read from the API" | Phase 3, Guard 2 | mapped |
| 7 | "ARMED_UNCONFIRMED defaults to a private mktemp file for this mode; never touches the per-merge arm list (the six arm_one call lines at the bottom stay untouched); the tfstate/required-env checks apply to --arm only" | Phase 1 (gate the `--arm` block), Phase 3 | mapped |
| 8 | "BS_TOKEN needs write scope; no xtrace; destination pin and token-shape guard unchanged" | Phase 1 (order of checks), Phase 6 (runbook), Guard 3 | mapped |
| 9 | "Tests: behavioural with the fake curl/clock harness ... rollback arm, name-collision refusal, id-pin mismatch, already-armed no-op, and a mutation row" | Phase 0, Phase 4 | mapped |
| 10 | "also run plugins/soleur/test/terraform-target-parity.test.ts (ARM ladder guard) and any suite that parses arm-heartbeats.sh (grep for consumers ...). Targeted suites only." | Phase 5 | mapped |
| 11 | "avoid editing .github/workflows" / "Do NOT run --arm-one against production" / "Refs #9438 (never Closes)" | Constraints section, ACs | mapped |
| 12 | "document in the runbook which secret name and the exact invocation (including how to pass BS_TOKEN without exposing it on the command line or via xtrace)" | Phase 6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `arm-heartbeats.sh` edits (resolver, modes, override) | "add `--status <name>` and `--arm-one <name>`" | asked |
| `arm-heartbeats.test.sh` edits (stub list endpoint, cases, mutation rows, floor ratchet) | "tests in arm-heartbeats.test.sh" | asked |
| Floor ratchet in the same suite | "a mutation row" (ask 9) | inferred - justification: the suite's `ASSERT_FLOOR` is an exact-count tripwire; new assertions without the ratchet leave room to delete them silently |
| Runbook step 7 + secret names | "runbook update ... step 7" and "which secret name and the exact invocation" | asked |
| `terraform-target-parity.test.ts` pin 2 -> 3 | "also run plugins/soleur/test/terraform-target-parity.test.ts" | inferred - justification: the structural pin on `$(bs_api ` call sites turns red on the resolver's read; leaving it red or hiding the call from the regex would defeat the guard |
| ADR-117 amendment | "reuses the existing arm_one machinery" | inferred - justification: a second entry point into the arm gate (operator-invoked, single monitor, own deadline) is an extension the ADR's own amendment history records for every prior change to this gate (Phase 2.10) |
| `fixture-relative-assert.baseline.txt` regeneration (only if the lint moves) | "any suite that parses arm-heartbeats.sh" | inferred - justification: baseline rows are equality-checked, so an unregenerated row reds CI |

### Split Assessment

- Subsystems touched: 3 (infra script + suite, runbook/ADR docs, plugin test) - roots `apps/web-platform/infra`, `knowledge-base`, `plugins/soleur/test`
- Planned files: 6-7 | Estimated changed lines: ~550 (script ~200, suite ~280, runbook ~40, ADR ~25, parity test ~8)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** the owner's pager gets a false "git-data host silent" page (a monitor armed with nothing feeding it), or the git-data host stays unmonitored because the arm is refused/rolled back; no end-user-facing surface changes.
- **If this leaks, the user's workflow is exposed via:** the Better Stack API token (write scope) leaking through argv, an xtrace line or shell history, which would let a holder pause or edit every uptime monitor and thereby silence production alerting.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the tool arms an alerting monitor and handles a write-scope token, but it cannot expose or alter user data; the worst outcome is a mis-armed or silenced monitor, not a single-user data incident.

## Files to Edit

1. `apps/web-platform/infra/arm-heartbeats.sh`: contract header + `usage()`; argument parsing (`${2:-}`/`${3:-}` under `set -u`); `hb_resolve_name`; gate the `--arm` tfstate/required-env block on `MODE == arm`; an optional 4th positional parameter on `arm_one` (the id override, see Design); `status_main` and `armone_main`; dispatch before the six `arm_one` lines. The six call lines and the inngest block stay byte-identical.
2. `apps/web-platform/infra/arm-heartbeats.test.sh`: stub list endpoint + self-test; new cases ST*/AO*; mutation rows M22-M33 and one existing row adjusted (M7: its landing count goes 2 -> 3 because the resolver's read carries the same `--max-time` literal; a deliberate edit, not a loosening); ratchet `ASSERT_FLOOR` to the EXACT new total; header comment updates.
3. `plugins/soleur/test/terraform-target-parity.test.ts`: ONLY the `$(bs_api ` count pin 2 -> 3 with a rationale comment (the resolver's read is the third credentialed call site). No new structural assertions: the existing ladder scan plus the byte-identical call-line diff already cover the six calls.
4. `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`: step 7 rewritten (the ask names step 7 only; steps 4 and 9 keep their existing curl read).
5. `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md`: a dated amendment (Phase 2.10 below).
6. `knowledge-base/engineering/architecture/decisions/ADR-283-git-data-host-originated-liveness-heartbeat.md`: one-line pointer update at the existing "tracked on #9980" sentence once the tooling exists.
7. `plugins/soleur/test/fixture-relative-assert.baseline.txt`: expect to regenerate (a new `mktemp`/`rm -f` operand is likely to add a row to the 3 existing ones for `arm-heartbeats.sh`); run `bash plugins/soleur/test/fixture-relative-assert.test.sh`, and if it reds regenerate with its own `--write-baseline` in the same commit.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9980-arm-one-tooling/tasks.md` (derived from this plan).

Not touched (standing constraints): `.github/workflows/**`, `git-data-gc.sh`, `.gc-cursor`, the main checkout `.mcp.json`, PR #9466, `.worktrees/feat-one-shot-9361-marketplace-ruleset-bypass-swap`, `suite-*.tsv` (unless the runtime check in Phase 5 says otherwise).

## Design

### Argument grammar (parsed before the destination pin, as today)

```text
arm-heartbeats.sh --status <name>
arm-heartbeats.sh --arm-one <name> [--id <id>]
arm-heartbeats.sh [--arm | --sweep | --help]        # unchanged
```

- `<name>` must match `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$` (leading alphanumeric so a forgotten name cannot swallow `--id` as the name; real names are `soleur-...-prd`). Anything else refuses rc 1 with ZERO requests. The comparison is jq string equality (`.attributes.name == $n` via `--arg`), never `test()`/`match()`/`contains()`/`startswith()`; a `.` in the argument must not match `-` in a name. Under `set -u` read `${2:-}`/`${3:-}` so a missing name is a named `::error::` refusal, not an unbound-variable abort.
- `--id <id>` is valid only with `--arm-one`, must match `^[0-9]+$`, refuses otherwise. Extra or repeated arguments refuse rc 1.
- Order of checks: the xtrace refusal (rc 78) already runs before argument parsing and stays first; then argument shape -> destination pin (shared, existing) -> `BS_TOKEN` non-empty and `_bearer_ok` (rc 1) -> resolution. The tfstate/required-env/resource-count block runs for `MODE == arm` only; `--status` needs only `BS_TOKEN`; `--arm-one` needs `BS_TOKEN` and optionally `ARMED_UNCONFIRMED`.

### Resolver (`hb_resolve_name <name>`)

- Loop: URL = `${BS_API_BASE}/heartbeats?per_page=250`, then each `.pagination.next`. A `next` is followed ONLY when it starts with the QUOTED prefix `"${BS_API_BASE}/heartbeats?"` (an unquoted `?` is a glob); anything else is refused, and more than 20 pages is refused (exactly 20 requests are made, then rc 1). Every page must satisfy `jq -e '.data | type == "array"'`: a 200 whose body is `{}` or `{"errors":...}` is a FAILED read (rc 1), never an empty page, because a hidden duplicate on that page would otherwise read as a unique match. Each read goes through the single credentialed wrapper (`body=$(bs_api -fsS --max-time "$ARM_CURL_MAX_TIME_S" ...) || return 1`, never `local body=$(...)`, which masks the exit code); a failed/empty/non-JSON page is rc 1.
- Per page, jq (arg-bound, never interpolated) emits one row per exact-name match (`paused` as `(.attributes.paused // "unreported")`: informational only, never a gate) with a NON-whitespace delimiter (`\x1f`) and a non-null sentinel per field (`(.x // "null" | tostring)` with CR/LF removed per field in jq via `gsub`), because tab is IFS-whitespace and `read` collapses empty fields (a `null` period would shift `grace` into `period`). The id must match `^[0-9]+$` (a match with a malformed id refuses, never skipped). Matches are COUNTED, not de-duplicated: a row repeated by an overlapping page reads as a collision and refuses (fail closed; a false refusal costs one owner look, a false unique costs a wrong arm). The resolver is called DIRECTLY (`hb_resolve_name "$n"; rc=$?`), never inside `$( )` or a `| while read` pipeline, so `RES_*` survive in the parent shell; `arm_one` likewise runs in the parent shell (its globals, and the suite's `kill -9 "$PPID"` cut model, require it).
- Outputs: `RES_COUNT`, and for count 1 `RES_ID`, `RES_PAUSED`, `RES_STATUS`, `RES_PERIOD`, `RES_GRACE`. For count > 1 only the ids are printed (`::error::... N heartbeats are named '<name>': ids <a> <b>; refusing`).

### `--status`

Prints one line, e.g. `name=soleur-git-data-host-prd id=506836 paused=true status=paused period=60 grace=300`, exits 0 on exactly one match; rc 1 on zero, many, or any read failure. No PATCH is reachable from this function (asserted by a zero-PATCH count in every status case, and by a mutation row that makes it fall through).

### `--arm-one`

1. Resolve (above). `--id` given and `!= RES_ID` -> rc 1 `id pin mismatch`, zero PATCH. Pin given with zero name matches -> rc 1 (a pin never substitutes for the name).
2. Deadline guard: `ARM_ONE_DEADLINE=150` (bare assignment). `max = RES_PERIOD + RES_GRACE - (ARM_POLL_INTERVAL_S + 2 * ARM_CURL_MAX_TIME_S)` (equals `period + grace - 40` at shipped values: derived from the file's own constants, not a literal 40). Refuse rc 1 when `RES_PERIOD`/`RES_GRACE` are not positive integers, or when `150 > max`; ZERO PATCH. For monitor 506836: max = 60 + 300 - 40 = 320, so 150 passes; worst-case live window is 150 + 40 = 190 s against a 360 s first-alert horizon.
3. `ARMED_UNCONFIRMED` unset -> `mktemp "${TMPDIR:-/var/tmp}/arm-one-unconfirmed.XXXXXX"` (0600); print its path and the recovery command `ARMED_UNCONFIRMED=<path> bash <script> --sweep` BEFORE the first PATCH (the interrupt case: Ctrl-C leaves a live monitor and, by the file's own design, no trap exists).
4. `arm_one "(by name)" "$name" "$ARM_ONE_DEADLINE" "$RES_ID"`; rc passes through unchanged: 0 armed / already armed (`already armed (status=...)` no-op, zero PATCH), 1 gate could not do its job (incl. a FAILED rollback: file kept, recovery command repeated), 2 gate worked, no beat, rolled back to paused. Do not reuse the phrase `rollback PATCH paused=true FAILED` in `armone_main` (existing mutation row M4 is a sed RANGE keyed on it and would land on two regions). On rc 2 one extra line says `arm_one`'s generic hint names web-1 and that for this monitor the feeder to read is the `git-data-liveness` events (stage `liveness`) in Better Stack.
5. Cleanup without a trap: if the file was the private mktemp and is empty, remove it; otherwise leave it and say so.

### The override (the only edit inside `arm_one`)

An OPTIONAL 4th positional parameter, with no ambient state (a global/env override would need a reset line plus guards against a stray environment variable steering `--arm`; a positional argument cannot leak):

```bash
local addr="$1" label="$2" deadline="$3" given_id="${4:-}"
...
if [[ -n "$given_id" ]]; then id="$given_id"
else id=$(jq -r --arg a "$addr" '...unchanged...' "$TFSTATE_JSON"); fi
```

The six per-merge call lines pass three arguments, so their behaviour is unchanged; the new call is indented inside a function and double-quoted, so the ladder scan (`^arm_one\s+'...'`) cannot count it. Everything after the id line is untouched, so the existing T1-T12, S1-S7 and M1-M21 rows remain the evidence for the apply path (M7 is the one adjusted landing count). Note the edit is a few lines, not one; the claim is "minimal and byte-neutral for three-argument callers".

## Implementation Phases

### Phase 0 - Tests first (`cq-write-failing-tests-before`)

In `arm-heartbeats.test.sh`: extend the stub, add fixtures/helpers, write the ST*/AO* cases and mutation rows (below) and watch them fail against the unmodified script (record the failing count). Stub additions: a list endpoint (`GET .../heartbeats[?query]`) served from `$FAKE_LIST_DIR/page-<n>.json`, DETECTED BEFORE `id="${url##*/}"`, the clock advance and the call log (it logs its own `list` row); REQUIRES `per_page=250` on the first page only (`next` URLs may carry `page=` alone) else `exit 64`; `exit 67` for any non-`uptime.betterstack.com` host (logged first); `exit 64` for a missing page file; a `FAKE_LIST_FAIL` knob for a 500 and empty/garbage/`{}` bodies. Export `FAKE_LIST_DIR` and `FAKE_LIST_FAIL` in BOTH `case_setup` and the self-test block (the stub has no `set -u`, so an unset directory silently becomes `/page-1.json`). Keep every existing stub refusal intact; new helpers: `run_status`/`run_armone` set `TMPDIR="$CASE"` (so the private books file is findable) and use `env -u TFSTATE_JSON -u ARMED_UNCONFIRMED` for the unset cases; `get_urls` callers in new cases filter out the `list` rows. A list-endpoint self-test (call without `per_page` -> rc 64; page 2 reachable; off-origin refused) is a plain stub self-test, not a mutation row.

### Phase 1 - Script plumbing

Header contract + `usage()` (the `sed` range still ends at `#   mint-unreadable`; new modes, env, exit codes go inside it), arg parser, `hb_resolve_name`, gate the `--arm` block, the `arm_one` 4th-parameter override. Constraints from the parity guard (non-comment text): the word `curl` must not appear in new lines (count stays exactly 1), `$(bs_api ` appears exactly 3 times, no line starts with `((`, no `trap`, and `ARM_CURL_MAX_TIME_S=15`, `ARM_POLL_INTERVAL_S="${ARM_POLL_INTERVAL_S:-10}"`, `ARM_ROLLBACK_ATTEMPTS=2` and the `if [[ "$HB_STATUS" != "paused" ]]; then ... already armed` shape stay verbatim.

### Phase 2 - `--status`

### Phase 3 - `--arm-one`

### Phase 4 - Suite completion and floor ratchet

Run the suite, set `ASSERT_FLOOR` to the exact total (hand-ratcheted, the comment appended: `234 -> <new> for #9980 ...`).

### Phase 5 - Targeted verification (no full-suite run)

- `bash apps/web-platform/infra/arm-heartbeats.test.sh` (must be green; capture runtime vs the 21000 ms manifest value).
- `bun test plugins/soleur/test/terraform-target-parity.test.ts` (ARM ladder guard + the edited pin).
- `bash scripts/guard-vacuity-floor.test.sh` (the suite is in PROMOTED_FILES; floor is a literal adjacent to the test).
- `bash plugins/soleur/test/fixture-relative-assert.test.sh` (equality baseline; regenerate in the same commit if and only if it reds).
- `python3 scripts/lint-shell-trace-credential-refusal.py` over the two changed shell files (xtrace refusal sentinel and argv-bearer rules; check its CLI with `--help` first).
- `shellcheck` on both shell files if available; `bash -n` is already asserted by the suite.
- `bash plugins/soleur/test/c4-count-parity.test.sh` (cheap confirmation of the "no C4 impact" conclusion).
- Markdown lint on the runbook/ADR edits (`npx markdownlint-cli2` on the two files, per repo convention).

### Phase 6 - Runbook and ADR

Runbook step 7 text (replace the "must land BEFORE this step ... Do not arm by hand" sentence): states the tool has landed (this PR) and gives, in code blocks:

```bash
# 1. Read-only state (read-scope token is enough):
doppler run -p soleur -c prd_terraform -- bash -c \
  'BS_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" exec bash apps/web-platform/infra/arm-heartbeats.sh --status soleur-git-data-host-prd'
# 2. The arm (write scope; owner-authorized; id pin = the id step 4 read):
doppler run -p soleur -c prd_terraform -- bash -c \
  'BS_TOKEN="$BETTERSTACK_API_TOKEN" exec bash apps/web-platform/infra/arm-heartbeats.sh --arm-one soleur-git-data-host-prd --id 506836'
```

Why this shape: the token is read by `doppler run` into the child's environment only; the single-quoted `bash -c` string holds variable NAMES, never values; nothing is `export`ed into the interactive shell or history; the script puts the bearer on curl's stdin config, never argv; and the script itself refuses `bash -x` (rc 78). Also document: do not wrap in `set -x`/`bash -x`; do not use `doppler secrets get --plain` into a variable; the READONLY token reading `--status` but 403-ing an arm is the expected failure of the wrong-name mistake; exit-code table (0 / 1 / 2) with what the owner does next (rc 2 = soak not satisfied, flip stays blocked, monitor already rolled back; rc 1 with a kept books file = run the printed `--sweep` command); the id-pin is the independent anchor (the id came from a step-4 read, not from the same lookup the tool performs). The secret NAMES are the two above (names only were read; no value was printed in this plan).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `arm-heartbeats.sh --help` documents `--status`, `--arm-one`, `--id`, the exit codes and the private-books behaviour (asserted by the suite).
- [x] `--status` is read-only: every ST case issues zero PATCH; rc 0 only for exactly one exact-name match; zero / many / read failure / off-pin `next` all rc 1.
- [x] `--arm-one`: unique exact name -> unpause -> `up` within 150 s -> rc 0 and books empty; never `up` -> exactly two PATCHes (`paused:false` then `paused:true`), rc 2, books empty; failed rollback -> rc 1, books file kept with the id, recovery command printed and `--sweep` on that file re-pauses it (end-to-end).
- [x] Refusals make ZERO PATCH: name collision (including a duplicate on page 2 after a compliant page-1 match), id-pin mismatch, pin with no name match, ceiling breach (and the exact boundary: allowed at `max == 150`, refused at `max == 149`), malformed period/grace, malformed name/id arguments.
- [x] Already-armed (`up`/`down`/`pending`) -> rc 0, `already armed (status=...)`, zero PATCH, nothing written to the books.
- [x] `--arm-one` and `--status` run with `TFSTATE_JSON` and `ARMED_UNCONFIRMED` unset; `--arm` still refuses without them (existing T9 unchanged and green).
- [x] `arm_one` called with three arguments (the six per-merge lines) behaves exactly as before; the existing T/S/M rows pass unmodified except M7's landing count (2 -> 3), which is a deliberate, commented edit.
- [x] The six `arm_one '` call lines and the inngest block are byte-identical to `origin/main` (`git diff origin/main -- apps/web-platform/infra/arm-heartbeats.sh` shows no hunk touching them).
- [x] `ASSERT_FLOOR` equals the exact new assertion total.
- [x] `terraform-target-parity.test.ts` green with the `$(bs_api ` pin at 3 (rationale in the comment) and `curl\b` still exactly 1.
- [x] Runbook step 7 carries both invocations, the two secret NAMES, the exit-code table and the no-exposure explanation; ADR-117 amended; ADR-283 pointer updated.
- [ ] PR body: `Closes #9980`, `Refs #9438` (never `Closes #9438`), no workflow file in the diff, `## Changelog` section, note about the wrong path in the issue.
- [x] No production API call was made while building this (the suite uses the stub only).

### Post-merge (owner, separate authorization; not part of this PR)

- [ ] Owner runs the runbook's `--status` then `--arm-one` invocations; the result (rc, `ARMED` line, elapsed) is pasted on #9438 for the record PR.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** infra tooling change on an existing script; assessed inline by the planner (no new infrastructure, store or connection; no UI, legal, marketing or finance surface). Product/UX gate: no UI-surface file in Files to Edit/Create, tier NONE. GDPR gate: no regulated-data surface. IaC routing: the heartbeat resource is already Terraform-managed (`git-data.tf`, `ignore_changes = [paused]`); the unpause is by design the measured-beat step (ADR-117), which is exactly what this script is, so no IaC reshaping applies.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-117 (do not create a new ADR): a short dated amendment recording that the arm gate now has a second, operator-invoked entry (`--arm-one`) resolving by exact name through the API instead of tfstate (exactly one match required, id pin as the independent anchor), with its own 150 s deadline bounded by the monitor's own `period + grace - 40`, a private books file, and `--status` as the read-only twin. One sentence of rationale only; no alternatives table (nobody proposed one).

### C4 views

No change. Checked against all three `.c4` files (`model.c4` 956 lines, `views.c4`, `spec.c4`): the external human actor is `founder` (already modeled), the external systems are `betterstack` and `doppler` (already modeled), no new store or container, and the actor-to-surface access relationship (the founder reaching Better Stack's API with the Doppler-held token) is the same path the existing `github -> betterstack` edge description already covers for the apply-side arm. No derived cardinality moves (no new workflow, heartbeat slug or monitor); `c4-count-parity.test.sh` is run in Phase 5 to confirm.

### Sequencing

ADR text is authored now (target state; the tooling ships in this PR so there is no `adopting` status).

## Observability

```yaml
liveness_signal:
  what: the arm run's own terminal verdict lines (`ARMED`, `already armed`, `ROLLED BACK`) plus the monitor's Better Stack status read back by --status
  cadence: on demand (operator-invoked), one run per arm decision
  alert_target: the invoking terminal (exit code 0/1/2) and, for a failed rollback, the kept books file plus the printed --sweep recovery command
  configured_in: apps/web-platform/infra/arm-heartbeats.sh (armone_main, status_main)
error_reporting:
  destination: stdout/stderr annotations (`::error::` / `::warning::` / `::notice::` prefixes, the script's existing vocabulary) and the process exit code
  fail_loud: yes - every refusal and failed API call is a non-zero exit with a named cause; a partial or unreadable list is never read as zero or one match
failure_modes:
  - mode: name collision or near-name (wrong monitor would be armed)
    detection: resolver count != 1, or id pin mismatch
    alert_route: rc 1 with both ids printed, zero PATCH
  - mode: feeder not beating (no up within 150 s)
    detection: poll never reads status=up
    alert_route: rc 2, rolled back to paused, extra line naming the git-data-liveness events to read
  - mode: rollback PATCH fails or the run is interrupted mid-poll
    detection: id remains in the books file
    alert_route: rc 1 (or a killed shell), books path and the exact --sweep command printed before the first PATCH and again on failure
  - mode: token shape / scope wrong
    detection: _bearer_ok refusal (zero requests) or HTTP 401/403 on the PATCH
    alert_route: rc 1 naming the HTTP status
logs:
  where: operator terminal stdout/stderr; the owner pastes the verdict lines on #9438 for the record PR
  retention: the issue/PR comment (no host-side log is written)
discoverability_test:
  command: bash apps/web-platform/infra/arm-heartbeats.sh --help
  expected_output: --arm-one
```

## Guard Contract

### Guard 1 - Exact-name resolution refuses anything but exactly one match

**Property.** `--status` and `--arm-one` resolve a heartbeat id only when exactly one row, across every page of `GET /heartbeats`, has `.attributes.name` byte-equal to the requested name, and `--arm-one` issues no PATCH unless that id also equals any `--id` pin.

**Assembly.** One chokepoint: `hb_resolve_name` is the only producer of `RES_ID`, and `arm_one`'s 4th parameter receives nothing else; the two consumers are `status_main` and `armone_main`. The quantified set is every page the pagination chain yields (bounded at 20, off-origin `next` refused, a 200 with no `.data` array refused), every row on each page, and both comparison sites (name equality in jq, id-pin equality in `armone_main`). Dispatch of the two modes is itself in the set (a mode that is never dispatched checks nothing). The single-match test lives in the resolver ONLY, so one mutation lands on one line.

**Mutation matrix.** Each row is a single-line anchored `sed` on a copy of the script via the suite's `mutate` helper, which asserts the landing count (N = 1 unless stated) so a row cannot pass by testing the baseline.

| # | Mutation (edit to the script) | Fixture that must go RED | Expected verdict change |
|---|---|---|---|
| M22 | name comparison `==` -> `contains($n)` in the resolver's jq | only `soleur-git-data-host-prd-old` exists; request `soleur-git-data-host-prd` | exact: rc 1, zero PATCH; mutant unpauses the wrong monitor |
| M23 | single-match requirement `-eq 1` -> `-ge 1` (resolver) | two rows with the exact name | mutant arms the first |
| M24 | stop after page 1 (blank the `next=` assignment) | compliant match on page 1, DUPLICATE exact name on page 2 (a second member after a compliant first) | mutant arms despite the collision |
| M25 | drop the id-pin equality (`armone_main`) | `--id` differs from the resolved id | mutant arms |
| M30 | drop the quoted-prefix refusal of `pagination.next` | page 1 `next` -> `https://evil.example/...` | the stub logs an off-origin call (and exits 67) only in the mutant |
| M31 | drop the `.data | type == "array"` check | page 2 is a 200 with `{}` and holds the hidden duplicate | mutant reads one match and arms |

**Harness rows.** (H1) Stub self-test (plain, not a mutation row): a list call without `per_page=250` exits 64, page 2 is reachable, an off-origin URL exits 67. (H2) must-PASS non-canonical input: the target on page 2 of 3 among decoys (case-variant `Soleur-Git-Data-Host-Prd`, suffix `-staging`, prefix `x-`, and a regex-bait `soleur.git.data.host.prd`); the exact name resolves, the bait name requested resolves to zero. (H3) Every `--arm-one`/`--status` case asserts the stub's call log contains a `list` row, so a SUT that resolved nothing cannot pass vacuously. (H4) `ASSERT_FLOOR`: deleting any case drops the total below the exact floor.

**Anchor.** The `--id` pin is the independent anchor: the owner reads the id in step 4 (a separate read, by a different tool path) and passes it to the arm; one edit cannot move the name list and the owner's held id together. The assertion floor proves consistency, not integrity (hand-ratcheted in the same diff).

### Guard 2 - The deadline ceiling

**Property.** `--arm-one` never unpauses a monitor whose measured window (`ARM_ONE_DEADLINE` plus the rollback reserve) could outlive that monitor's own first absence alert, read from the API for THAT monitor, and fails closed when `period`/`grace` cannot be read as positive integers.

**Assembly.** `armone_main`'s single check, fed by `RES_PERIOD`/`RES_GRACE` from the resolver, using the file's own `ARM_POLL_INTERVAL_S`/`ARM_CURL_MAX_TIME_S` terms; the deadline constant; the arithmetic is the only place the ceiling exists, with one inline comment stating that the derived reserve equals the literal 40 of the ask at shipped values. Not on the per-merge ladder (which sums only the six call sites).

**Mutation matrix.**

| # | Mutation | Fixture | Expected verdict change |
|---|---|---|---|
| M26 | delete the ceiling comparison | grace 100 (max 120 < 150) | mutant unpauses a short-window monitor |
| M27 | `>` -> `>=` | grace 130 (max == 150) | mutant refuses a monitor the contract allows; the suite also asserts grace 129 refuses (both sides of the boundary) |
| M32 | treat a non-numeric/absent period or grace as proceed (drop the positive-integer check) | row with `"period": null` (case AO6) | must refuse fail-closed with zero PATCH; mutant proceeds |

**Harness rows.** The boundary pair (130 allowed, 129 refused) is also the must-PASS non-canonical input (a monitor that is NOT 60/300); every refusal asserts ZERO PATCH, so a refusal that happens AFTER the unpause cannot pass.

**Anchor.** None outside the commit: the ceiling is derived from constants in the same file; the ladder guard reads `ARM_POLL_INTERVAL_S` and `ARM_CURL_MAX_TIME_S` from this file (`scriptConst`), so redefining either term moves both.

### Guard 3 - Apply-path isolation

**Property.** The `--arm` and `--sweep` behaviour is unchanged by the new modes: the override is positional (no ambient variable can steer `arm_one`'s id), the six call lines and the inngest block are untouched, and the new modes never enumerate the six monitors.

**Assembly.** `arm_one`'s 4th parameter and its branch, the six `arm_one '` lines, the `--arm` required-env block (gated on `MODE == arm`), and the parity guard's regexes over non-comment text (`curl\b` == 1, `$(bs_api ` == 3).

**Mutation matrix.**

| # | Mutation | Fixture | Expected verdict change |
|---|---|---|---|
| M28 | override branch disabled (`[[ -n "$given_id" ]]` -> `false`) | `--arm-one` happy path (no tfstate) | mutant falls to the tfstate lookup, skips ("not present in tfstate"), issues no PATCH |
| M29 | hoist the `--arm` tfstate block out of the gate (mutate the `if [[ "$MODE" == arm ]]` condition line to always-true) | `--arm-one` with `TFSTATE_JSON` unset | mutant refuses ("TFSTATE_JSON is unset") |
| M33 | let the override fall back to the environment (`given_id="${4:-${ARM_ONE_ID:-}}"`) | `--arm` run with `ARM_ONE_ID=1` exported (case AO8, kept as one cheap case) | mutant GETs id 1 instead of the six tfstate ids |

**Harness rows.** The existing M15 unmutated control stays; a new control runs `--arm-one` unmutated end to end; the unmodified T1-T12, S1-S7, M1-M21 rows (M7's count adjusted to 3) are the evidence the apply path did not move.

**Anchor.** The `git diff origin/main` hunk check on the six call lines (AC) is independent of the suite; the suite's rows prove consistency only.

## Test Scenarios

Each is a case in `arm-heartbeats.test.sh` using `case_setup`, the fake clock and synthesized ids (`ID_HOST=900201` etc.; no real Better Stack id appears in the file).

- ST1 one match -> prints the fields, rc 0, zero PATCH, TFSTATE/ARMED_UNCONFIRMED unset. ST2 zero matches rc 1. ST3 two exact rows rc 1 with both ids. ST3b near-names/case-variants/regex-bait only: rc 1 (zero matches) and, next to the exact row, rc 0 with the exact id. ST4 match on page 2; ST4b off-origin `next` refused; ST4c endless `next` makes exactly 20 requests then rc 1. ST5 list 500 / empty / non-JSON / `{}` on a later page / a matching row with a malformed id / a null `period` -> rc 1 (status mode surfaces the null as `null`, never shifted fields).
- AX argument refusals (zero requests): no name (no unbound-variable abort), leading `-` name, bad charset, `--id` with `--status`, non-numeric `--id`, extra argument, empty/odd-shaped token, off-pin `BS_API_BASE`, `bash -x` (rc 78) for both new modes.
- AO1 happy arm (`upat` flips status to up): rc 0, one PATCH (unpause), books file created under `$CASE` (via `TMPDIR`), path printed, file removed when empty; only the list + the resolved id's GETs hit the stub (never the six ids). AO2 never up: rc 2, PATCH sequence `false`,`true`, reported elapsed within one iteration of 150, observed clock within `150 + 85 + list`; AO2b rollback 500: rc 1, books file kept holding the id, the printed recovery command's path is parsed from the output (never `eval`ed) and `--sweep` on it re-pauses (end to end). AO3 collision (incl. page-2 duplicate): rc 1, zero PATCH, zero GET by id. AO4 pin mismatch / pin without name / pin match proceeds. AO5 already armed (`up`, `down`, `pending`): rc 0, zero PATCH, books untouched. AO6 ceiling: 100 refused, 130 allowed, 129 refused, null period refused.
- AO8 an exported `ARM_ONE_ID` is inert on `--arm` (six no-ops against the six real ids).
- Mutation rows M22-M33 above, plus a new-mode unmutated control. Cut after plan review (covered elsewhere): rollback-retry and external-cut cases for the new mode (the retry and books-ordering code is unchanged `arm_one`, already covered by T2e and T11/M18).

## Risks and Sharp Edges

- **The parity guard pin changes (2 -> 3).** A reviewer may read it as loosening the guard. It is the honest count of credentialed call sites after a third legitimate read; the guard's intent (one curl, every credentialed call through `bs_api`) is preserved and asserted by `curl\b == 1`.
- **Interrupt window.** There is deliberately no `trap` in this file (header, Cut List C6). A Ctrl-C during the 150 s poll leaves the monitor live; the mitigation is the up-front books path and recovery command, and the live window is bounded at about 190 s against a 360 s first-alert horizon.
- **Hint text in `arm_one`'s rc 2 line is web-1-specific.** Left untouched to keep the apply path byte-identical; `armone_main` adds one disambiguating line instead.
- **Vendor field names.** `period`, `grace`, `paused`, `status` are read from `data[].attributes` as `hb_fetch` already reads `.status`; the row shape matches `plugins/soleur/lib/heartbeat-live-reconcile.ts`. No fresh production read is made in this PR; if `period`/`grace` were ever absent the resolver fails closed (refuses), so a wrong guess cannot arm. The owner's `--status` read is the first live read of those two fields: a refusal there is a clean stop, not a harm.
- **Name collision with a deleted-but-listed monitor** is treated as a collision (refuse); the owner resolves it in Better Stack.
- **A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6.** It is filled above (threshold `aggregate pattern`).
- **Lint tokens:** the runbook/plan prose pairs no human-actor token with an infrastructure imperative; the arm is a script-driven API call under the owner's authorization, not provisioning.

## Non-Goals and Deferrals

- Removing `arming_pending` from the manifest row, ticking the soak precondition and refreshing the ledger: the record PR (`Closes #9438`), runbook step 8.
- Running `--arm-one` against production: a separate owner step after merge.
- Re-deriving the sweep's arm set from tfstate for the "runner died" gap recorded in the script header (E9): pre-existing, tracked there; the private books file here makes the new mode's own residue explicit but does not close that class.
- Any `.github/workflows` change (an admin merge is forbidden on such PRs).
