---
title: "feat: enroll #9387 in the follow-through sweeper with a notify-only date probe"
date: 2026-10-05
slug: enroll-9387-notify-only-date-probe
branch: feat-one-shot-9387-followthrough-date-probe
issue: 9387
lane: cross-domain
type: feat
---

# feat: enroll #9387 in the follow-through sweeper with a notify-only date probe

Note: the spec for this branch carries no `lane:` (there is no spec file), so `lane` defaulted to `cross-domain` (fail-closed). The change is a single-domain engineering/CI-tooling change.

## Overview

Issue #9387 ("operator-scripts: migrate the TTY-ack scripts to the staged approval gate (ADR-264)") is a `deferred-scope-out` tracker. Its re-evaluation trigger has two parts: a real harness-approved write recorded in the staged-gate run ledger, and the plugin hook being live for two weeks. The ledger (`bootstrap-runs.jsonl`) lives on the founder's machine and the sweeper cannot read it, and ADR-264 states that a ledger line is not evidence of approval (an agent that reads the hook can mint its own receipt). So the only part of the trigger a CI probe can honestly evaluate is the date.

This plan adds a **notify-only date probe** and enrolls the tracker:

1. `scripts/followthroughs/tty-ack-migration-9387.sh` — exit 2 (NOT YET) before `2026-10-16T00:00:00Z`, exit 5 (ACTION REQUIRED) on or after it. It never exits 0 (it must not close the tracker) and never exits 1 (the sweeper reads 1 as FAIL and "still exits 1" reads as a regression). No secrets, no `gh` call.
2. `scripts/followthroughs/tty-ack-migration-9387.test.sh` — drives every exit arm through a fixed-clock seam and asserts the never-0/never-1 contract, the header obligations, and the registration.
3. Registration in `scripts/test-all.sh` (explicit `run_suite`, light `scripts` group) plus the incremental shard-manifest regeneration.
4. Post-merge (agent-executed, pre-approved GitHub write): put the probe under the main checkout, then edit #9387 — add labels `follow-through` and `do-not-autoclose`, append an unfenced column-0 directive with `earliest=2026-10-16T00:00:00Z`.

Out of scope, explicitly: the #9387 migration itself, any `.github/workflows` or `.github/actions` edit (none is needed — see Research Insights), any edit to the ADR corpus.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9387`: OPEN, title and body match the brief; labels today are `priority/p2-medium`, `domain/engineering`, `deferred-scope-out`. It carries no directive and no `follow-through` label, so nothing enrolls it yet.
- The body says "related open work #9321". `gh issue view 9321` reports CLOSED. Stale reference in prose only; it does not affect scope and the probe message does not cite #9321.
- Cited artifacts exist on the branch (= `origin/main` at `27f5bc84a5`): `scripts/followthroughs/ccla-representative-icla-7922.sh` and `.test.sh`, `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/regenerate-shard-manifest.py`, ADR-264 and ADR-249.
- Both labels exist in the repo (`follow-through`, `do-not-autoclose`), so `gh issue edit --add-label` will not create anything.
- ADR corpus grep for the mechanism (date probe / notify-only): the convention is the runbook `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` ("a registered sub-vocabulary inside the TRANSIENT bucket, for NOTIFY-ONLY probes": 2 = NOT YET, 3 = CANNOT ESTABLISH, 5 = ACTION REQUIRED). No ADR rejects it.

### Mirror target — the better template (Phase 1 repo research)

The brief names `ccla-representative-icla-7922.sh` (438 lines) and its test (1210 lines) as the model. Those establish the notify-only vocabulary and the header obligations, but they carry a git-derived epoch, a roster and an acknowledged-floor file: none of that applies to a pure date probe, and its test needs `tsx` (it is registered in the `want_webplat` shard for that reason). The closer structural template for a **clock-seam probe** is `scripts/followthroughs/workspaces-plaintext-hold-9348.sh` + `.test.sh` (116 + 174 lines): `NOW_EPOCH` test seam inert under the sweeper's `env -i`, fixed-clock arms, instrument self-test, a control that proves the case helper can fail, and a source pin that the probe never exits 1. This plan takes the 7922 header obligations (notify-only statement, credential posture, RETIREMENT) and the 9348 mechanics.

### Sweeper behaviour this relies on (scripts/sweep-followthroughs.sh)

- `earliest=` is a wall-clock gate evaluated before the probe runs, so before 2026-10-16 the sweeper does not run the probe and posts nothing (no daily NOT YET noise). The probe's own date check is still required: it is the authority if `earliest=` is ever edited, and it is what the test drives.
- Exit 2 and exit 5 both take the `comment` action ("Leaving the issue open"), with the heading words NOT YET / ACTION REQUIRED. Exit 5 therefore comments on every sweep from 2026-10-16 until the operator closes the tracker by hand. That is the intended nag; the message tells the operator how to stop it (do (a) then (b), then close #9387 by hand).
- The sweeper lists only open issues (`--label follow-through --state open`), so a hand-closed tracker leaves the sweep with no further action.
- The sweeper runs probes under `env -i` with only PATH, HOME and directive-declared `secrets=`. The probe needs none, so the directive omits `secrets=`. No `.github/workflows/scheduled-followthrough-sweeper.yml` edit is needed (consistent with the operator's exclusion of workflow edits).

### Registration surface (Phase 1 repo research)

- `scripts/followthroughs/` matches no `SUITE_GLOBS` entry, so the suite must be registered explicitly with `run_suite "scripts/<label>" bash scripts/followthroughs/<name>.test.sh` in `scripts/test-all.sh`. 9348 is registered in the light `scripts` block; the block's own comments say new registrations append at the END of the block so no earlier registration's positional ordinal moves. The last entry today is `run_suite "scripts/audit-suite-reads" ...` immediately before the closing `fi` that precedes `# Named bun-test entries — bun shard.`.
- `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` are generated. The sanctioned path for adding a registered suite is `python3 scripts/regenerate-shard-manifest.py --incremental --write` (header of the TSV: "suite added/removed"); it fetches no timings and diffs only the added row (and its `floor` row in the durations table). Hand-editing is forbidden by the comment at `test-all.sh` ("generated suite-shard-legs.tsv / suite-durations.tsv are NOT hand-edited").
- Cheap local conformance checks that apply: `bash scripts/lint-orphan-test-suites.sh` (an unregistered suite is an orphan), `bash scripts/followthrough-exec-bit.test.sh` (probe must be mode 100755 in the index), `bash scripts/lint-followthrough-varq-ban.sh`. CI is the full test gate; the long local battery is skipped per the brief.

### Institutional learnings applied

- `followthrough-convention.md`: credential posture stated exactly ("none" means no `secrets=` in the environment, not "unauthenticated" — here the probe makes no network call at all, so the posture is genuinely none), `RETIREMENT:` line enumerating every reference, notify-only probes assert never-0/never-1 in their own suite, never gate the exit on `: "${VAR:?}"` (status 1 = FAIL).
- Bash trap specific to a never-1 contract: a non-interactive bash aborts on an unbound-variable expansion under `set -u` (status 127 on this bash 5.x, 1 on others — measured) and on any failed command under `set -e` (the failed command's status, commonly 1). Either is an uncontrolled status the sweeper would read as FAIL or TRANSIENT instead of a verdict. The probe therefore sets neither, and the suite bans both by source pin.
- Bash arithmetic trap (measured): `[[ 08 -ge 5 ]]` prints `value too great for base` and evaluates FALSE with rc 1, so a zero-padded clock silently takes the "not yet" arm — a wrong verdict, not a crash. 20-digit values wrap negative under `10#`. The probe validates the clock as digits-only and at most 12 digits, and compares with `(( 10#$NOW >= 10#$DEADLINE_EPOCH ))` inside an `if`.
- Directive placement: unfenced at column 0, full ISO `earliest=`; the PreToolUse directive gate resolves `script=` under the MAIN checkout (runbook "Where the gate resolves `script=`"). The gate fires at `gh issue create`; this plan uses `gh issue edit`, so the gate does not fire, but the sweeper still resolves the path on its own checkout of `main`, hence the probe must be on `main` first.

### Property List (Phase 0.6b)

1. A tracker the sweeper can never auto-close still produces a human-visible notice on the day its re-evaluation date arrives.
2. The notice cannot be mistaken for completion: the probe has no code path that closes the tracker or reports FAIL, under any input including a hostile clock or a missing `date`.
3. The notice tells the operator to verify approval on their own machine before starting, because the evidence is not reachable from CI and a ledger line is not proof of approval.
4. The probe uses no credential and no network, and nothing it prints can carry one.
5. When the tracker is finished, the probe and every reference to it are removable by one grep.

### Cut List (Phase 0.6b)

- Reading `bootstrap-runs.jsonl` or any ledger from the sweeper -> property 3 -> cut: unreachable from CI (founder-machine file) and ADR-264 says a ledger line is not approval evidence; the message asks the operator instead.
- Querying `gh` for the hook-live-for-two-weeks half of the trigger -> property 1 -> cut: the date already encodes that half, and `gh` would require `secrets=GH_TOKEN` and break property 4. Existing mechanism covering it: `earliest=` plus the probe's own date check.
- A `.acknowledged` floor file like 7922's -> property 2 -> cut: 7922 needs edge-triggering because its predicate is a monotone count; this probe's predicate is a date, and a daily nag until the operator acts is the requirement, not a defect.
- Reading the sweeper-forwarded `SOLEUR_FT_EARLIEST` instead of a constant (one date instead of three) -> property 2 -> cut: it would make the verdict depend on the issue body, which anyone with edit access can change, and the brief pins the date in the probe. The drift risk is covered by the Phase 3.5 equality assertion instead.
- A workflow edit to wire `secrets=` or a new label -> property 4 -> cut: no secret is declared and both labels already exist.
- A new ADR / C4 change -> cut: no architectural decision (see Architecture Decision section).

## Scope Check

| Ask | Maps to |
|---|---|
| 1. probe script, notify-only, exit 2 / 5, message (a) then (b), no secrets, no gh, header with credential posture + notify-only + `RETIREMENT:`, test suite asserting never-0/never-1, registration | Phases 1-2 |
| 2. no `.github/workflows` / `.github/actions` edit; stop and ask if needed | Constraint; verified no workflow edit is needed (Research Insights) |
| 3. after on main: copy probe to main checkout untracked, edit #9387 (labels + unfenced column-0 directive, full ISO `earliest=`) | Phase 3 |
| Constraints: no prod writes beyond the issue edit; CI is the gate; admin merge SHA-pinned via admin-merge-ready.sh, Reviewed-By-Soleur trailer; never print secrets; do not start the migration | Phase 3 + Sharp Edges |

No inferred items. The only addition beyond the literal ask is the manifest regeneration, which is what "register where the suite-shard manifest requires" means in practice.

## Open Code-Review Overlap

2 open scope-outs touch `scripts/test-all.sh`: #8659 (test suites replacing test-helpers' EXIT trap) and #7942 (two `*.mutation.sh` batteries in no gate). Acknowledge both: neither concerns follow-through probe suites, and the new suite is a standalone script that does not source `test-helpers.sh`, so it adds no instance of #8659. `scripts/followthroughs/` is touched by #8800, #8659, #8496, #8435 (all about other probes). Acknowledge, no fold-in. None for `suite-shard-legs.tsv` / `suite-durations.tsv`.

## Files to Create

- `scripts/followthroughs/tty-ack-migration-9387.sh` (mode 100755)
- `scripts/followthroughs/tty-ack-migration-9387.test.sh` (mode 100755; companion suites in this directory are executable)

## Files to Edit

- `scripts/test-all.sh` — one `run_suite "scripts/followthroughs/tty-ack-migration-9387" ...` registration with a comment, appended LAST in the light `scripts` block (before the `fi` that precedes the "Named bun-test entries" comment).
- `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` — by `python3 scripts/regenerate-shard-manifest.py --incremental --write` only, never by hand.

No `.github/**` file is edited. No SKILL.md `description:` is edited (skill-description budget check: not applicable).

## Implementation Phases

### Phase 1 — Probe and suite (write the failing test first, `cq-write-failing-tests-before`)

**1.1 Suite first.** Write `tty-ack-migration-9387.test.sh`, run it red against a probe that does not exist yet (the suite aborts with exit 2 "probe missing" — confirm the abort is loud), then write the probe.

Suite shape (mirror 9348 mechanics): `set -uo pipefail`; probe path overridable by a `PROBE` variable only for the in-suite mutation arms; instrument self-test (drive `ok`/`no` once each, abort if the counters did not both move, then reset); a control proving the case helper rejects a wrong expectation; a reporter floor (`pass >= N`, N set to the actual count minus nothing — a hard floor, not `> 0`); final exit `[ "$failc" -eq 0 ]`.

Assertions, by group:

- **Clock arms (seam `NOW_EPOCH`)**: epoch `0` -> 2; today-ish (2026-10-05T12:00:00Z) -> 2; deadline minus 1 s -> 2; exactly the deadline -> 5 (pins `>=` not `>`); deadline plus 1 s -> 5; year 2100 -> 5. Each asserts the exit code AND a verdict substring (`NOT YET` / `ACTION REQUIRED`), so a probe that prints one word and exits the other is caught.
- **Hostile clock arms -> exactly 3 (CANNOT ESTABLISH), never 0 or 1**: `NOW_EPOCH=abc`, `-5`, `1.5`, a 13-digit value, a trailing-newline value (measured: the regex rejects it), a fullwidth-digit value and an Arabic-Indic-digit value (review finding: in a UTF-8 locale `[0-9]` can match them, and `10#` then aborts with status 1; the probe sets `LC_ALL=C` and the arm pins it). Empty `NOW_EPOCH` falls through to the real clock (documented, asserted as rc in {2,5}).
- **Zero-padded clocks (octal trap)**: `0000000009` (before the deadline) -> 2, and a zero-padded epoch ABOVE the deadline (`00` + the deadline epoch plus 1 hour) -> 5. The second row is the discriminating one: without `10#` the old `[[ -ge ]]` form errors and silently takes the NOT YET arm, whereas a zero-padded value before the deadline returns 2 either way and proves nothing.
- **`date` unusable**: probe run with a PATH holding no `date` (absolute `bash`), and with a PATH `date` shim that prints garbage -> 3. Because the probe also resolves the deadline with `date -d`, the shim arm is run both with and without the seam set (with `NOW_EPOCH` set, only the deadline call is exercised); the probe validates `DEADLINE_EPOCH` with the same digits-only regex.
- **Production shape**: `env -i PATH=... HOME=... bash probe` with no seams (the sweeper's exact shape); rc must be in {2,5} (clock-independent set so the suite does not rot on the deadline); also run with `GH_TOKEN`/`SENTRY_ACTIONS_RO_TOKEN` canaries set in the outer env and assert the canary strings appear in no output (inert credential posture).
- **No `gh`, no network**: put a stub `gh` (and `curl`) earlier on PATH that logs every call and exits 99; run both verdict arms; assert the log is empty. Source pin: no executable (non-comment) line contains a `gh`/`curl`/`wget` word.
- **Message arm (exit 5)**: output contains, in this order, a step (a) that names `bootstrap-runs.jsonl`, the founder's machine, `ADR-264` and that a ledger line is not evidence of approval, and that the operator approved the first real write at the prompt; then a step (b) that says start the migration. Assert (a) precedes (b) by character index. Exit-2 output contains `NOT YET` and `2026-10-16`.
- **Never-0 / never-1 contract (the guard) — source pins and behaviour**: every `exit` operand in the probe's executable lines is a literal in {2,3,5}; no `exit` with a variable operand; no bare `exit`; no `set -e`, `set -u`, `set -o errexit|nounset`, no `trap ... EXIT` that could rewrite the status; the stub-driven arms plus the hostile-clock table never produce rc 0 or 1 (assert rc not in {0,1} over the whole input table, not just per-row expected values).
- **In-suite mutation arms (guard matrix, below; six mutants)**: copy the probe into the suite's sandbox, apply a single edit, and assert that the matching check (the source-pin checker, or the behavioural clock run against the mutant) goes red; the unmutated copy goes through the identical function and must come out clean (pristine-copy control; a mutant that fails to land, detected by asserting the edit changed the verdict block's line range rather than by `cmp`, is an instrument error, not a catch). One checker function serves the real probe and every mutant, so the arms test the checker, not a copy of it.
- **Header arm (one pin)**: the probe's leading comment block contains `NOTIFY-ONLY` and a `RETIREMENT:` line (the content of the RETIREMENT line is reviewed, not machine-checked; a probe-with-no-retirement is the failure, and a grep per named row would be a second copy of the list).
- **No registration arm** (cut after simplicity review): registration is covered by `bash scripts/lint-orphan-test-suites.sh` (an unregistered suite is an orphan) and by the shard runner, so a copy of that check here would be a second authority.

**1.2 Probe.** `tty-ack-migration-9387.sh`:

- Header (comment block): what it is (date probe for #9387, re-evaluation 2026-10-16T00:00:00Z); **NOTIFY-ONLY** statement (never exits 0 so the sweeper never closes #9387 — closing is the operator's act after the migration; never exits 1 because 1 reads as FAIL); **CREDENTIAL POSTURE** (declares no `secrets=`; makes no `gh`, network or git call; reads no file; the only inputs are the system clock and the `NOW_EPOCH` test seam, inert under the sweeper's `env -i`); the exit vocabulary (2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED); why the probe cannot read the evidence (founder-machine ledger, ADR-264 residual: a ledger line is not approval evidence); and the `RETIREMENT:` line (delete the probe, its `.test.sh`, the `run_suite "scripts/followthroughs/tty-ack-migration-9387"` line and its comment in `scripts/test-all.sh`, and regenerate the two TSV rows with `python3 scripts/regenerate-shard-manifest.py --incremental --write`; at retirement re-census `git grep tty-ack-migration`).
- Body: `export LC_ALL=C` first; no `set -e`, no `set -u` (uncontrolled aborts). `DEADLINE_ISO='2026-10-16T00:00:00Z'` resolved once with `date -u -d`; `NOW="${NOW_EPOCH:-$(date -u +%s 2>/dev/null)}"`; BOTH epochs must match `^[0-9]{1,12}$` else print `CANNOT ESTABLISH: ...` to stderr and `exit 3` (the only non-literal-verdict path); compare with `if (( 10#$NOW >= 10#$DEADLINE_EPOCH ))`. `NOW < DEADLINE` -> print `NOT YET: ...` naming the date, `exit 2`. Otherwise print the two-step ACTION REQUIRED message (above) and `exit 5`. The message ends by telling the operator how to stop the daily comment: finish (a) and (b), then close #9387 by hand. Messages print no environment value.
- `chmod 755`; commit mode 100755 (`git update-index --chmod=+x` if needed; `followthrough-exec-bit.test.sh` asserts the index mode).

**1.3 Run the suite once locally** (fast, single-file) and `bash scripts/followthrough-exec-bit.test.sh`, `bash scripts/lint-followthrough-varq-ban.sh`. Do not run the long local battery; CI is the gate.

### Phase 2 — Registration

2.1 Append the `run_suite` line with a short comment (explicit because `scripts/followthroughs/` matches no glob; the suite pins that the probe never returns 0 or 1) as the last entry of the light `scripts` block in `scripts/test-all.sh`.
2.2 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; the diff must be exactly one added `+` line in `suite-shard-legs.tsv` and one in `suite-durations.tsv` (a `floor` row at the default weight) — if the diff touches other rows, stop and investigate rather than committing a rebalance. Run the regenerator after the `run_suite` line exists (it keys on registered labels).
Label convention: both `scripts/<name>` (e.g. 9348) and `scripts/followthroughs/<name>` (39 registrations incl. the newest, 9323 and 7510) exist; this plan uses the `scripts/followthroughs/` prefix of the newer registrations. Use the same label in the `run_suite` line, the RETIREMENT line and the TSV rows.
2.3 `bash scripts/lint-orphan-test-suites.sh`.

### Phase 3 — Post-merge enrollment (agent-executed; GitHub write pre-approved for #9387 only)

Ordering is load-bearing: the directive gate and the sweeper resolve `script=` against `main`, so the probe must be on `main` first.

3.1 Ship through the normal pipeline: PR body `Ref #9387` (NOT `Closes`: merging this PR must not close the tracker; `wg-use-closes-n-in-pr-body-not-title-to` applies to issues the PR resolves, and this one is deliberately left open). Admin merge on green CI only, SHA-pinned via `admin-merge-ready.sh` from the primary checkout; the merge needs the `Reviewed-By-Soleur` trailer; the PR touches no `.github/workflows` or `.github/actions`.
3.2 After merge, in the PRIMARY checkout: `git pull --ff-only` so the tracked probe is present. If the primary checkout cannot fast-forward cleanly (dirty tree), copy the probe to `<main-checkout>/scripts/followthroughs/tty-ack-migration-9387.sh` untracked with mode 755 instead (the brief's fallback), and delete the untracked copy once main contains it. Confirm `test -x` there.
3.3 Run the probe once under `env -i PATH=/usr/bin:/bin HOME=/tmp bash <path>`: expect exit 2 and `NOT YET` today (2026-10-05).
3.4 Edit the issue, with the body read fresh and appended to (never replacing the existing text):

```bash
gh issue view 9387 --json body --jq .body > "$SCRATCH/9387-body.md"
# append, after a blank line, an UNFENCED directive whose "<!--" opener is at column 0:
#   <!-- soleur:followthrough
#   script=scripts/followthroughs/tty-ack-migration-9387.sh
#   earliest=2026-10-16T00:00:00Z
#   -->
gh issue edit 9387 --add-label follow-through,do-not-autoclose --body-file "$SCRATCH/9387-body.md"
```

No `secrets=` line. Build the appended text with a quoted heredoc so nothing expands, and make sure the opener is not inside a fence or indented.
3.5 Verify by pull, not by eye (`hr-no-dashboard-eyeball-pull-data-yourself`): re-read the body with `gh issue view 9387 --json body,labels`, assert both labels are present, the pre-existing text is byte-intact, and `grep -c '^<!-- soleur:followthrough$'` is 1 at column 0 outside any fence; confirm the issue still has `deferred-scope-out`, `priority/p2-medium`, `domain/engineering`. Optionally confirm the sweeper parser accepts it with a local read-only parse of the fetched body (the sweeper's directive parser, `scripts/sweep-followthroughs.sh`, is the authority).
3.6 Do not dispatch the sweeper workflow and do not start the migration.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `scripts/followthroughs/tty-ack-migration-9387.sh` exists, is mode 100755 in the index, and its header states NOTIFY-ONLY, CREDENTIAL POSTURE (no secrets, no gh, no network) and a `RETIREMENT:` line naming the probe, the suite, the `run_suite` line and both generated manifest rows.
- [ ] The probe returns 2 for every clock before `2026-10-16T00:00:00Z` and 5 for the deadline and every later clock; the deadline second itself is 5. Verified by the suite's clock arms.
- [ ] The probe returns 3 for non-numeric, negative, fractional, over-long and non-ASCII-digit clocks and for an unusable `date` (either `date` call); it returns decimal-correct verdicts for zero-padded values, including a zero-padded epoch above the deadline returning 5. No input in the suite's table produces rc 0 or rc 1.
- [ ] The exit-5 message names `bootstrap-runs.jsonl`, the founder's machine, ADR-264 and "a ledger line is not evidence of approval", asks the operator to confirm they approved the first real harness-approved write at the prompt, and only then to start the migration; step (a) precedes step (b).
- [ ] The probe calls no `gh`/`curl` (stub log empty on both verdict arms; source pin on executable lines), declares no secrets, and prints no value of `GH_TOKEN`/`SENTRY_ACTIONS_RO_TOKEN` canaries.
- [ ] Source pins: every `exit` operand is a literal in {2,3,5}; no `set -e` / `set -u` / `errexit` / `nounset`.
- [ ] Each of the six in-suite mutations of the probe copy (see Guard Contract) is caught by the suite, and the unmutated copy passes the same checks.
- [ ] `scripts/test-all.sh` registers the suite exactly once (appended last in the light `scripts` block); `suite-shard-legs.tsv` and `suite-durations.tsv` each gain exactly one row for it, produced by `regenerate-shard-manifest.py --incremental --write`, with no other row changed; `lint-orphan-test-suites.sh` is green.
- [ ] `git diff --name-only origin/main...HEAD` lists no path under `.github/workflows/` or `.github/actions/`.
- [ ] The PR body uses `Ref #9387`, not `Closes #9387`.
- [ ] CI is green (the `test-scripts` shard runs the new suite plus `followthrough-exec-bit`, `lint-followthrough-varq-ban` and the orphan-suite lint).

### Post-merge (agent-executed, not an operator checklist)

- [ ] The probe is on `main` and executable in the primary checkout; `env -i ... bash <probe>` exits 2 with `NOT YET` before 2026-10-16.
- [ ] #9387 carries labels `follow-through` and `do-not-autoclose` (and still its three prior labels); its body keeps the original text and ends with the unfenced column-0 directive (`script=scripts/followthroughs/tty-ack-migration-9387.sh`, `earliest=2026-10-16T00:00:00Z`, no `secrets=`), verified by re-reading the issue.
- [ ] #9387 is still OPEN after the merge and after the edit.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The failure mode is operator-facing: the 2026-10-16 reminder to start the TTY-ack-to-staged-gate migration does not arrive (the tracker rots silently), or arrives and is misread as complete.
**If this leaks, the user's data / workflow / money is exposed via:** no vector. The probe reads no data, declares no secret, makes no network call, and prints only fixed text; the issue edit appends a directive with no secret.
**Brand-survival threshold:** none
threshold: none, reason: the diff adds a clock-only CI probe, its suite and a test registration; it touches no schema, auth, API route, credential or user-data surface and no sensitive path.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to a follow-through probe, its test suite and the test runner registration. No UI surface (no `components/**`, `app/**` path), no regulated-data surface (GDPR gate not triggered: no schema, auth, API, LLM/external-API processing, learnings/specs reader or distribution surface), no new infrastructure.

## Architecture Decision (ADR/C4)

No architectural decision: a bug-class-free tooling addition on an existing substrate (the follow-through sweeper) using its documented notify-only vocabulary. Would an engineer reading the ADRs and C4 be misled after this ships? No. C4 not edited; the cardinality gate `plugins/soleur/test/c4-count-parity.test.sh` is unaffected because no workflow, monitor or heartbeat count moves (no workflow file is touched). ADR-264 and ADR-249 are cited as evidence, not amended.

## Observability

The sweeper's tracker comment is the notification channel and the probe is runnable locally without credentials, so there is no SSH-only surface.

```yaml
liveness_signal:
  what: the sweeper posts a "Sweeper run: ACTION REQUIRED (exit 5)" comment on #9387 from 2026-10-16
  cadence: daily sweep (scheduled-followthrough-sweeper), silent before the date by the earliest= gate
  alert_target: GitHub issue comment on #9387 (the founder is subscribed as the tracker's participant)
  configured_in: the unfenced directive on #9387 plus scripts/followthroughs/tty-ack-migration-9387.sh
error_reporting:
  destination: sweeper comment heading CANNOT ESTABLISH (exit 3) on an unresolvable clock; stderr tail in the comment
  fail_loud: true — no failure path exits 0 or 1; an exit-3 repeats daily and is visible
failure_modes:
  - mode: directive fenced or indented, tracker never enrolled
    detection: the sweeper's end-of-run FENCED_DIRECTIVE / no-directive summary names the issue; Phase 3.5 re-reads the body and asserts column 0
    alert_route: sweeper job summary and the post-merge verification step
  - mode: probe absent or not executable on main when the sweeper runs
    detection: followthrough-exec-bit.test.sh in CI; Phase 3.3 runs the probe from the primary checkout
    alert_route: CI red before merge; post-merge step fails loudly
  - mode: probe exits 0 or 1 by accident (would close the tracker or read as FAIL)
    detection: the never-0/never-1 source pins and the hostile-input table in the suite
    alert_route: CI red on the PR
logs:
  where: GitHub Actions log of scheduled-followthrough-sweeper.yml and the comment on #9387
  retention: GitHub default Actions log retention; comments permanent
discoverability_test:
  command: bash scripts/followthroughs/tty-ack-migration-9387.sh
  expected_output: NOT YET
```

(The `expected_output` literal is correct only before 2026-10-16; after that date the same command prints `ACTION REQUIRED`, which is the signal working.)

## Guard Contract

The deliverable includes one guard: the never-0/never-1 exit-code contract of a notify-only probe, asserted by its own suite.

### Guard 1 — notify-only exit-code contract

**Property.** No input and no source edit to the probe can make it return 0 (close #9387) or 1 (FAIL), and the deadline instant itself is ACTION REQUIRED.

**Assembly.** Every `exit` in the probe (the three literal sites 2, 3, 5), every implicit exit (the script's final command, a bash abort from `set -e` / `set -u`, an `EXIT` trap that rewrites status, an arithmetic error in `[[ -ge ]]`), every input that reaches the comparison (the real clock via `date`, the `NOW_EPOCH` seam, an absent or broken `date`), and every command the probe could run that touches `gh`/network. The chokepoint is the single comparison plus the three exit sites; the suite quantifies over the probe's whole executable text (not the first `exit`) and over a table of clocks (not one).

**Mutation matrix.**

| # | Edit to the probe copy | Must go RED because |
|---|---|---|
| M1 | change `exit 5` to `exit 0` (or append `exit 0` after the verdict block) | the source-pin checker finds an exit operand outside {2,3,5}; the clock table also returns rc 0 |
| M2 | add a second `exit 1` on a rarely-taken branch AFTER a compliant first `exit 5`; and a variant `exit $rc` with a variable operand | the checker scans every `exit` and bans variable operands, not just the first literal |
| M3 | change `>=` to `>` in the deadline comparison | the exact-deadline clock arm returns 2, not 5 |
| M4 | delete `10#` (restoring the octal-hazard form) | the zero-padded-epoch-above-deadline arm returns 2 instead of 5 |
| M5 | replace the verdict block with `true` so the script falls off the end (the probe's own dispatch) | rc 0 appears in the clock table and the exit-operand floor (>= 3 literal sites) fails, so the checker cannot report "0 checked" as clean |
| M6 | add a `gh issue view 9387` line | the no-`gh` source pin and the stub log both catch it |

Direct pins with no mutant (the plain assertion is the whole test): no `set -e` / `set -u`, `LC_ALL=C` present, message order (a) before (b) by character index, header has NOTIFY-ONLY and RETIREMENT.

**Harness rows.** (i) Break the suite's own case helper to always say yes: the control that feeds it a wrong expectation reddens. (ii) Remove the final `printf` of the pass floor: the floor check fails. Must-PASS inputs that are not the canonical: leading-zero `0000000009` (decimal 9 -> 2), the deadline expressed as a different but equal epoch computed in the suite with a different `date` invocation, and a production-shape run with unrelated environment variables set.

**Anchor.** The suite compares the probe against a literal set {2,3,5} and a literal date written in the suite. A commit that edits both the probe's deadline and the suite's date passes the suite, so the suite proves consistency, not that 2026-10-16 is the right date. The independent anchor is the tracker directive's `earliest=2026-10-16T00:00:00Z` in the issue body (outside the commit) and the issue's own text; Phase 3.5 asserts the directive date equals the probe's `DEADLINE_ISO`.

## Test Scenarios

- Run the suite on the unmutated probe: all rows green, pass count at or above the floor.
- Run the sweeper-shaped invocation today: `NOT YET`, rc 2.
- Set `NOW_EPOCH` to the deadline: `ACTION REQUIRED`, rc 5, message ordered (a) then (b).
- Apply each of M1-M6 by hand once during work (the suite's mutation arms automate this) and confirm the matching arm reddens.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6; this one carries concrete artifact/vector lines and `threshold: none` with a reason.
- Exit 5 comments every sweep after the date until the tracker is hand-closed. That is intended and the message says how to stop it. Do not "fix" the noise with an acknowledged-floor file (cut above).
- `Closes #9387` anywhere (PR title or body) would close the tracker on merge and defeat the purpose. Use `Ref #9387`.
- The directive must be unfenced at column 0: a fenced or indented one is present in the body and enrols nothing (#7490). Phase 3.5 asserts it by pull.
- The issue edit must append to a freshly read body; `--body-file` replaces the whole body, so a stale read would drop edits made since.
- The suite must not rot on the deadline: production-shape arms assert rc in {2,5}, never a fixed one, and every date-specific arm uses the `NOW_EPOCH` seam. The suite must also not hard-code "today".
- Do not run the sweeper workflow (even as a dry run): the brief allows no production writes beyond the issue edit, and a local `env -i` run of the probe gives the same evidence.
- The never-1 contract is also a property of the shell: `set -e`, `set -u`, `: "${VAR:?}"` and a failed arithmetic expansion each produce status 1. Keep all four out of the probe.
- Sibling date-based probes (e.g. 9348's `DEADLINE_ISO='2026-10-15T00:00:00Z'`) fire a day earlier on an unrelated tracker; no coupling, noted so nobody "aligns" the dates.
- Merge hygiene: admin merge only after green CI, SHA-pinned via `admin-merge-ready.sh` from the primary checkout, `Reviewed-By-Soleur` trailer present; if CI shows any need to touch `.github/**`, stop and ask instead of editing.
