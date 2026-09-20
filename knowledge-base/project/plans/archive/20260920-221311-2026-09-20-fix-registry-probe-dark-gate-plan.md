---
title: "fix: route op=registry-probe's non-200 branch through the dark-host gate"
date: 2026-09-20
slug: fix-registry-probe-dark-gate
branch: feat-one-shot-8079-registry-probe-dark-gate
issue: 8079
closes: 8079
type: bug
lane: single-domain
domain: engineering
priority: p2
brand_survival_threshold: aggregate pattern
---

## Overview

`scripts/cutover-inngest.sh op=registry-probe` is a standalone read-only diagnostic. It GETs the
web host's `inngest-registry-probe` hook, which forwards a `{ functions { id } }` GQL query to the
dedicated inngest host at `10.0.1.40:8288`, and on any non-200 it prints one opaque `::error::`
line carrying the raw cause and exits 1 — no verdict, no remedy.

#8079 asks for that branch to be routed through `inngest_execute_registry_gate`
(`tests/scripts/lib/inngest-host-dark-gate.sh:1149`), the standalone diagnostic twin of what #8054
built for `op=execute` step 2.0, plus the corresponding wiring assertion in
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`.

**The code defect is live and the fix is unchanged. The issue's stated MOTIVATION is not** — see
`## Premise Correction` immediately below, which re-aims the design effort from the branch #8079
was written about onto the branch that can now actually fire.

## Premise Correction — the cutover completed on 2026-09-15

#8079 was filed `2026-09-11T11:33:53Z` and argues from a pre-arm world: "the P1-5 flip guard keeps
the dedicated host dark on every pre-arm flag, so `op=registry-probe` is unrunnable pre-arm."
That world ended four days later. Verified this session from the repo and from GitHub — not from
the issue body:

- `knowledge-base/engineering/architecture/decisions/ADR-100…` **§ Addendum — 2026-09-15 (#6178,
  #8191) — the cutover completed**: `op=arm` (run 34948112813) confirmed the host FSM `done`
  (`INNGEST_CUTOVER_FLIP=done`), and `op=registry-probe` (run 34948634783) read **70 registered
  functions** from `10.0.1.40:8288`. `gh run view 34948634783` → `conclusion: success`,
  `createdAt 2026-09-15T08:44:38Z`. `gh issue view 8191` → `MERGED 2026-09-15T10:20:23Z`; 2.4
  repointed `INNGEST_BASE_URL` at the dedicated host in all four places.
- § **Addendum — 2026-09-18 (#7695)** records the live row: `cutover_flag=done`,
  `server_active=active`, `http_code=200`, `redis_keys=1261`, `flush_latched=true`, host
  `166317708`.

Four consequences, each of which changes what this plan must build:

1. **`op=registry-probe` returns HTTP 200 today.** The non-200 branch is no longer the pre-arm
   default; it fires when something is BROKEN. And since 2.4, `10.0.1.40` is the ONLY scheduler —
   so "the registry probe got a non-200" now means *production scheduling may be down*, not *the
   host has not been armed yet*. The branch went from low-stakes to the highest-stakes branch in
   the arm, which strengthens the case for fixing it rather than weakening it.
2. **`dark` is nearly unreachable.** `_erg_flag_class` maps only `aborted|rolled-back` to
   `preflip`; `armed|flipping|flushed|done` map to `armed`. With the flag pinned at `done`, E11
   refuses before darkness is ever graded. A dark verdict is now reachable only after an
   `op=rollback`. The exit-code question #8079's brief poses is therefore real but no longer the
   main event, and this plan treats it as such (**D1** still stands; its rationale is re-grounded).
3. **`flag_armed` is the token that will actually fire, and copying 2.0's remedy would be actively
   harmful.** A dead dedicated host post-cutover emits `http_code=000 server_active=failed
   cutover_flag=done`: E9 passes, E10 passes, E11 returns `flag_armed`. 2.0's remedy for that token
   says *"done => the cutover already completed: dispatch op=verify."* Pasted into this arm, the
   diagnostic would answer a production outage with "already completed, run verify" — reproducing
   #8079's own defect class in a new place. See **D8**.
4. **The gate's positive allowlist turns out to partition correctly post-cutover, once the remedies
   are rewritten.** A dark host under `done` ⇒ `flag_armed` ⇒ exit 1 (production scheduling is
   down — correct to be red). A dark host under `rolled-back`/`aborted` ⇒ `dark` ⇒ exit 0 (a
   deliberate rollback; nothing has registered against `10.0.1.40` since boot — correct to be
   green). No library change is needed to get that partition; only the caller's messages.

**Scope verdict: re-scope in place, do not close as overtaken.** The deliverable #8079 names — route
the branch through the gate, add the wiring assertions — is unchanged and is now worth more than
when it was filed. What changes is where the design effort goes: from `dark` to `flag_armed` and
`host_serving`, and from "make a pre-arm diagnostic runnable" to "make a production-outage
diagnostic say something true".

## Review Corrections — what the panel changed in this plan

A five-reviewer panel ran against the first draft. Every claim below was RE-VERIFIED in this session
by running the command, not by reading the reviewer's report; the measured output is quoted. These
corrections are folded into the decisions, and they are recorded here because the class they share —
*a plan long enough that nobody re-ran its own claims* — is the one the corrections are about.

| # | Correction | Measurement |
|---|---|---|
| **C1** | **BLOCKER.** The `registry-probe)` arm has **no `else`**. `if [[ "$CODE" != "200" ]]; then … exit 1; fi` falls through to the `jq` shape check. A `dark)` branch that does not exit therefore runs that check against a 500 body, fails it, `echo "$BODY"`s the raw body and exits 1 — breaking D1, AC1, AC2 and the purity contract in one step. | `sed -n '845,851p' scripts/cutover-inngest.sh` — `fi` at `:847`, no `else`. 2.0 escapes this because its region IS an `if … else … fi` (`:1541`). |
| **C2** | A **sixth** real assertion collision the draft missed: `mktemp -d` trips `#6617 probe arms send NO request body`, because `-d` is an alternative matched between whitespace. | `echo 'RPG_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/rpg.XXXXXXXX")' \| grep -cE '(^\|[[:space:]])(-d\|--data\|…)([[:space:]]\|=)'` → **1** |
| **C3** | **Two draft collisions were phantoms.** The no-mutating-hook row and the no-doppler row do not break, and both proposed re-aims were strictly WEAKER than the assertions they replaced. | `echo 'inngest-cutover-flip' \| grep -cE 'inngest-(arm\|flip\|quiesce\|rearm\|wiped)'` → **0**; `grep -cE '(^\|[^a-z-])doppler([[:space:]]\|$)'` over the 2.0 region → **0** |
| **C4** | `_bs_read_remedy` hardcodes `2.0` in **nine** messages, not eight. The ninth is the trailing "NOTHING about the dedicated host was measured" summary — the one most likely to be read during an incident. | `awk '/^_bs_read_remedy\(\) \{$/,/^\}$/' scripts/cutover-inngest.sh \| grep -c '::error::2\.0 '` → **9** |
| **C5** | D4's behaviour-preservation proof was overstated: there is **no `heartbeat read:` render**. Two of the nine messages are render-pinned; seven are not. | `grep -c 'heartbeat read:' apps/web-platform/infra/cutover-inngest-workflow.test.sh` → **0** |
| **C6** | A broken knowledge-base citation — the `awk \b` learning has no `best-practices/` path segment, so the path resolved to nothing. (The reviewer who found it attributed the class to "#4173"; probed here, **#4173 is a GitHub Actions secrets 403 and has nothing to do with citation paths**, so that attribution is dropped rather than propagated — which is the same class as the finding itself.) | `ls knowledge-base/project/learnings/best-practices/2026-09-17-awk-…md` → No such file; `gh issue view 4173` → "apply step fails 403 on github" |
| **C7** | D8's `flag_armed` branch was **wrong**, not merely under-specified: it keyed on "`flag`/`hb_flag` == `done`" without the `__UNREAD__` sample discriminator that 2.0 documents as mandatory. | `sed -n '1517,1523p' scripts/cutover-inngest.sh`; lib emits at `:1253`/`:1304` then refuses |
| **C8** | The draft's `M1.1` was anchored on `enumerate)` — the **first** arm in the file (`:791`), before both compliant members — so it could not test the "second member" property it claimed. | arm offsets: `enumerate) :791`, `registry-probe) :821`, `execute) :1290` |
| **C9** | The draft's `M2.7` (move the `trap`) was **unkillable and inexpressible**: nothing between the two positions can exit, and `mutate_file` requires a one-line diff while a move changes two. | `mutate_file` hard-fails on `changed != 1` |

## Deepen-Plan Verification

Run 2026-09-20. This pass added no new mechanism — the substantive depth came from the review panel
above. What it did was **resolve every citation in the plan against the live tree and GitHub**, which
is the one thing a long document reliably gets wrong.

| Check | Result |
|---|---|
| Halt gate 4.6 — `## User-Brand Impact` | PASS: present, threshold `aggregate pattern`, non-placeholder body |
| Halt gate 4.7 — `## Observability` | PASS: all 5 fields present; `command` verb `bash` is allowlisted; no `ssh`; not suite-shaped (finishes well inside the 15 s cap); `expected_output: "1"` is a matchable literal, not prose |
| Halt gate 4.8 — PAT-shaped variables | PASS: no matches |
| Halt gate 4.9 — UI wireframe | SKIP: no UI-surface path in Files to Edit/Create |
| Halt gate 4.10 — `## Encryption Posture` | SKIP, reasoned: no `.tf` / migration / cloud-init / compose path, and the Better Stack read is **not a new cross-component connection** — `_bs_query_rows` already has 6 call sites in this same script. This change adds callers, not a connection. |
| Halt gate 4.11 — Guard Contract | PASS: `python3 scripts/lint-guard-contract.py` → 2 guard entries, 0 failures |
| Every cited `#N` resolved live | 9/9 resolve (`#4173 #6178 #6488 #6617 #7695 #8054 #8079 #8191 #8389`) |
| Every cited AGENTS rule ID active | 7/7 present in `AGENTS.rules.md` |
| Every cited learning path resolves | 10/10 exist on disk (one was broken in the draft — **C6**) |
| **Attribution probe** | **1 FAILURE, corrected.** The draft's **C6** row attributed the broken-path class to "#4173". `gh issue view 4173` → *"apply-web-platform-infra apply step fails 403 on github"* — a GitHub Actions secrets 403, unrelated to citation paths. The attribution came from a reviewer and was propagated without checking. Dropped. That a correction table meant to catch unverified claims itself carried one is the sharpest evidence in this plan for why this check exists. |
| Internal count consistency | D7 prose "six" = 6 table rows; Guard 1 = M1.1-M1.5; Guard 2 = M2.1-M2.12; ACs AC1-AC17 with no plan-internal count asserted in any AC |
| Literal consistency | `nine` used for `_bs_read_remedy` at all 5 sites; `__FETCH_FAILED__` one spelling; the reserved triple cited identically in D2, AC2 and the Test Scenarios; `render_arm_region` appears ONLY as a rejected alternative |
| Network-outage gate 4.5 | Keyword `ssh` matches, but only as the prohibition `Do NOT SSH the host` and the AC that forbids it. The plan diagnoses no network symptom and proposes no sshd/firewall fix, so the L3→L7 checklist has no subject. Recorded rather than silently skipped. |

Baseline suite runs are in the table below (measured, not asserted).

## Research Insights

### Premise Validation (Phase 0.6)

- **#8079 is OPEN**; labels `type/bug`, `priority/p2-medium`, `domain/engineering`;
  `closedByPullRequestsReferences: []`.
- **#8054 is CLOSED** and its artefact exists: `inngest_execute_registry_gate()` at
  `tests/scripts/lib/inngest-host-dark-gate.sh:1149`, E-table header from `:988`. Read, not assumed.
- **The arm exists** — `registry-probe)` at `scripts/cutover-inngest.sh:821`, next arm at `:864`.
- **The 2.0 reference region exists**, delimited by `# ---- 2.0 empty-registry pre-flight (P1-6)`
  and `# ---- 2.1 capture`.
- **STALE — the pre-arm framing.** See `## Premise Correction`. Independently corroborated a third
  way while this plan was being written: open PR #8389 (`Closes #6617`, `Closes #6488`) states
  `INNGEST_CUTOVER_FLIP` reads `done` and adds its own ADR-100 addendum. It touches neither
  `scripts/cutover-inngest.sh` nor `cutover-inngest-workflow.test.sh`, so there is no file
  collision — but it DOES touch ADR-100 and `plugins/soleur/test/fixture-relative-assert.baseline.txt`
  (one of this plan's hand-run ratchets), so **re-sync `main` before running the ratchets**.

Capability claims verified rather than asserted (`hr-verify-repo-capability-claim-before-assert`):

- **No new credential or workflow change is needed.** `.github/workflows/cutover-inngest.yml:123`
  injects `DOPPLER_TOKEN` UNCONDITIONALLY for every op; only `DOPPLER_TOKEN_INNGEST_ARM` and
  `environment:` are op-gated. `Checkout` and `Install Doppler CLI` are ungated too.
- **`_bs_query_rows` (`:110`) and `_bs_read_remedy` (`:130`) are top-level**, before
  `case "$OP" in` at `:790`, so both are in scope from the `registry-probe)` arm.
- **`restart-inngest-server.yml` is the WRONG remedy for a dead dedicated host.**
  `scripts/inngest-host-state.sh`'s header records, measured 2026-09-17 over 12 consecutive
  attempts, that the `/hooks` channel terminates on web-1 and the dedicated host runs no listener —
  and `scheduled-inngest-health.yml:926` already says the same in its own arm.
- **`scripts/inngest-host-state.sh` is NOT dispatchable.** `grep -rln inngest-host-state
  .github/workflows/` → no match. Running it needs a local checkout plus the `doppler` CLI plus
  `prd_terraform` access. This is why **D8** orders the remedy dispatchable-read-first.
- **The watchdog works against the operator during the incident this arm diagnoses.**
  `scheduled-inngest-health.yml:419` auto-dispatches `restart-inngest-server.yml` on failure, and
  both it and `cutover-inngest.yml` sit in `concurrency: deploy-inngest-restart,
  cancel-in-progress: false` — so those auto-restarts, which cannot reach the dedicated host,
  serialise AHEAD of the operator's diagnostic dispatch.

### Measured baselines (Phase 0, taken during planning)

| Probe | Result |
|---|---|
| `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` | **665 passed, 0 failed**; floor exactly 665 |
| `bash apps/web-platform/infra/inngest-registry-probe.test.sh` | **75 passed, 0 failed** |
| `bash tests/scripts/test-inngest-host-dark-gate.sh` | **282 passed, 0 failed** |
| `bash plugins/soleur/test/fixture-relative-assert.test.sh` | 62 passed, 0 failed (floor 62) |
| `bash scripts/guard-vacuity-floor.test.sh` | 23 passed, 0 failed |
| `bash scripts/lint-diagnosis-claims.test.sh` | 24 passed, 0 failed |
| `python3 scripts/lint-shell-capture-exit.py --baseline …` | 1175 scanned, **0 new findings**, 201 baselined |
| `bash scripts/test-all.sh --capacity` | **`CAPACITY_CONTENDED`**, `measured_runs=3` — a full gate is NOT claimable; run the diff's suites plus the ratchets and say so |

### Property List (Phase 0.6b)

- **P1** — A non-200 from `op=registry-probe` produces a graded verdict naming what is and is not
  established about 10.0.1.40, instead of one opaque HTTP line.
- **P2** — A verdict derived from host rows can never be read as the live measurement
  `registry_empty=true`.
- **P3** — Every refusal carries a remedy the operator can PERFORM, without SSH, phrased for a
  standalone read-only probe dispatched OUTSIDE any maintenance window.
- **P4** — Post-cutover, a dedicated host that has stopped answering is diagnosed as such, not as
  "the cutover already completed".
- **P5** — Adding a second consumer of the gate does not weaken the existing assertion that no
  unaccounted third consumer exists.
- **P6** — **2.0's verdicts, exit codes and every pinned render expectation are unchanged.**
  (The draft said "2.0's behaviour is unchanged in what it prints", which D9 and D8's `silent` clause
  violate BY DESIGN — a mechanism with no property and a property no mechanism could satisfy. This is
  the restatement.)
- **P7** — Remedy text inside `op=execute` that consumes this op's result stays true after this op's
  result becomes three-valued. (Added so D9 anchors to a property instead of floating.)

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it → cut |
|---|---|---|
| A second gate entry point for the probe | P1/P3 | The gate grades the same host, the same rows, the same 11 tokens. **CUT** — reuse. |
| A post-cutover flag partition in the LIB | P4 | The emit file already carries `flag`/`hb_flag` BEFORE the refusal (lib `:1253`, `:1304`), so the caller discriminates. Changing `_erg_flag_class` would alter a destroy gate's semantics. **CUT** — branch in the caller (**D8**). |
| New `--since` / freshness operands | P1 | The gate owns freshness; the caller's windows only have to be WIDER. 24h/30m already are. **CUT.** |
| A workflow change for credentials | P1 | `DOPPLER_TOKEN` already unconditional. **CUT.** |
| Hoisting the shared mechanism into one helper | none | **CUT** — see **D3**. |
| A shared op-parameterised remedy printer | P3 | The remedies' value is being op-specific. **CUT.** |
| `render_2_0` → `render_arm_region` rename | none | `:2033` already reads `local region="$1"` — the function is ALREADY generic. Churn across a file whose floor has conflicted at merge before. **CUT** (`soleur:engineering:review:code-simplicity-reviewer`). |
| D10's three-way token-set EQUALITY | P1 | The suite already derives the lib's token set and loops a presence check; running that loop a second time buys the whole property in ~4 lines. Equality additionally forbids a dead `case` arm, which no property needs. **CUT** down to coverage. |

### Value-Proposition Measurement (Phase 0.6c)

Not applicable — the justification is correctness and operability, not a cost or latency saving.

### Relevant code anchors

| Path | Anchor | Why |
|---|---|---|
| `scripts/cutover-inngest.sh` | `registry-probe)` `:821`-`:863` — note `if … fi` with **no `else`** (`:845`-`:847`) | the change site, and **C1** |
| `scripts/cutover-inngest.sh` | `# ---- 2.0 empty-registry pre-flight (P1-6)` … `# ---- 2.1 capture`; the `else` at `:1541` | the reference to mirror, structurally |
| `scripts/cutover-inngest.sh` | `:1434` (2.0 `webhook_path`), `:1515` (2.0 `host_serving`), `:1521` (the `__UNREAD__` discriminator) | **D9**, and the shape **D8** must copy |
| `scripts/cutover-inngest.sh` | `_bs_query_rows()` `:110`; `_bs_read_remedy()` `:130` — **9** hardcoded `2.0` | **D4** |
| `tests/scripts/lib/inngest-host-dark-gate.sh` | `inngest_execute_registry_gate()` `:1149`; `_erg_flag_class()` `:1067`; emit-then-refuse at `:1253`/`:1304` | the gate, its 11 tokens, and the invariant **D8** rests on |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | `#6617` `:1230`-`:1291`; `FLQ_SITES` `:1050`; `#8054` from `:1860`; `render_2_0` `:2032`; `ANNOT_LEAKS` sub-block extractor `:1928`; `mutate_file` `:2170`; `_EXACT_FLOOR` `:2882` | every assertion this change touches |
| `apps/web-platform/infra/inngest-registry-probe.sh` | `run_probe()`, the `__FETCH_FAILED__` literal | producer of the admission signature |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-11-the-gate-i-built-for-a-dark-host-was-blind-to-the-byte-shape-of-nothing.md`
  — the #8054 learning: extract the REAL `_bs_query_rows`/`_bs_read_remedy` and stub the PROCESS
  (`doppler`), never the function under the seam; never echo an HTTP error body.
- `knowledge-base/project/learnings/2026-09-13-the-mock-that-answered-in-one-line-certified-a-constant-and-my-beacons-stdout-was-the-secret.md`
  — a uniform stub certifies a constant; every fixture must discriminate a failure CLASS.
- `knowledge-base/project/learnings/2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`
  — names this suite's `_EXACT_FLOOR`: re-derive and MEASURE, never increment by guess; a mutant that
  exits non-zero with no `FAIL` line is UNRESOLVED, not KILLED.
- `knowledge-base/project/learnings/2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`
  — parity-pin the half you copy (**D10**).
- `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md`
  and `knowledge-base/project/learnings/2026-04-19-enoent-on-optional-mount-should-not-alarm.md`
  — alarming on a structurally expected state drowns signal. Supports **D1**.
- `knowledge-base/project/learnings/best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md`
  — an exit 0 must still carry the discriminating verdict on stdout. Supports **D2**.
- `knowledge-base/project/learnings/2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md`
  — a gate whose reassuring branch was unreachable from the real producer. **D1**'s `dark` branch is
  now rollback-only-reachable and the plan says so rather than pretending otherwise.
- `knowledge-base/project/learnings/2026-09-17-awk-word-boundary-backslash-b-is-backspace.md`
  and `knowledge-base/project/learnings/2026-05-13-plan-verify-reducer-case-arms-with-grep-not-read-first-n.md`
  — the arm extractor must be PROVED to select exactly the intended arm. (This citation's path was
  wrong in the draft — see **C6**.)

### CLAUDE.md / AGENTS.md conventions that bind

`hr-no-ssh-fallback-in-runbooks`; `hr-observability-layer-citation` (layer 6);
`cq-write-failing-tests-before`; `cq-assert-anchor-not-bare-token` and
`cq-cite-content-anchor-not-line-number` (the draft violated both — see C3 and AC16);
`hr-verify-repo-capability-claim-before-assert`; `wg-when-deferring-a-capability-create-a`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality, verified | Plan response |
|---|---|---|
| "P1-5 keeps the host dark on every pre-arm flag, so the op is unrunnable pre-arm" | Cutover completed 2026-09-15; flag `done`, host serving, 70 functions registered, probe returns 200 | Re-scoped in place; effort moved to `flag_armed`/`host_serving` |
| "so a dark host reports the gate's token and remediation" | `dark` needs a `preflip` flag, i.e. only after `op=rollback` | `dark` still implemented, still exits 0 (**D1**), documented as the rollback-only branch |
| "Add the corresponding wiring assertion" (singular) | **Six** real collisions across three blocks (and two the draft invented) | **D7** |
| Implied: the probe arm is a copy of 2.0 | 2.0's region is an `if … else … fi`; this arm's is not (**C1**) | Phase 2 restructures the arm FIRST |
| Implied: `_bs_read_remedy` is reusable as-is | **9** hardcoded `2.0` messages | **D4** |

## Decisions

### D1 — a `dark` verdict EXITS 0, with a notice plus a warning

`dark` exits 0; every other token exits 1. For 2.0 the property is "no registry can double-fire", and
a host that CANNOT START satisfies it more strongly than one that answered empty. Here the operator
asked "has an SDK registered against 10.0.1.40?", and darkness answers a weaker proposition —
*nothing can have registered since this boot* — measuring no registry contents at all (E12 REQUIRES
`registry_fns=__UNREADABLE__` on a dark row).

Exit 0 because: the arm's own convention already prints its WORST finding (`registry_empty=false`)
as a warning at exit 0, reserving non-zero for "the probe could not run"; and post-cutover `dark`
means the operator ran `op=rollback` minutes earlier, so red would fire on a state they created
deliberately. The confusion cost — a green run looking like a live measurement — is paid by **D2**,
in the message, where it can be stated in words rather than encoded in a two-valued status.

One caveat is real and **D9** fixes it: the exit code IS consumed today by human remedy text inside
2.0. (An earlier draft also claimed "nothing downstream consumes this exit code as a gate" as a bare
universal negative; the enumeration is `git grep -n 'op=registry-probe' -- .github/workflows/
scripts/ knowledge-base/engineering/operations/runbooks/`, and it finds the two 2.0 strings D9 fixes
plus the runbook, which `## Files to Edit` item 3 covers.)

### D2 — the dark path never emits the live-measurement triple

`registry_empty=`, `function_count=` and `ids=[` are RESERVED for the live HTTP-200 measurement. The
dark path emits instead: one `::notice::registry-probe HOST-STATE VERDICT: dark — …` carrying the
gate's evidence (`boot_id`, row age, `flag`, heartbeat age, `hb_flag`), every field from
`--emit-file`, never from a raw row; and one `::warning::` in two clauses:

> `What this establishes:` nothing can have registered against 10.0.1.40 since boot `<id>` — its
> inngest-server has not been bound on this boot. `What it does not establish:` what the registry
> holds; `registry_empty` was not measured. Dispatch `op=doublefire-probe` for the stronger reading.

Two clause openers that are ordinary English AND greppable. (An earlier draft mandated shouty
`ANSWERED:` / `NOT ANSWERED:` tokens purely so an assertion could find them — the test wagging the
prose.) **The warning names the field as `registry_empty` with NO trailing `=`**, which is what keeps
it clear of its own reserved-string assertion; a mutation row appending `=false` to it must redden.

### D3 — duplicate the plumbing; do NOT hoist it out of 2.0

An earlier draft argued "six assertions grep that plumbing inside the extracted exec arm, so hoisting
reddens them". That does not survive contact with the suite: extracting a function body with
`awk '/^name\(\) \{$/,/^\}$/'` and pointing assertions at it is this file's most-used idiom (8
existing sites). Re-scoping six assertions is less work than the D7 extensions already signed up for.

The honest reason is the INTERFACE. Strip out what D5/D6/D8 require to differ — eleven bespoke remedy
strings — and ~20 lines remain whose extraction would hand **seven** values back through globals or
`eval`. A function taking a prefix and writing seven globals is worse than the duplicate.

Recorded as debt with a trigger, not as settled: the duplicated block carries a `SOLEUR-DEBT:` marker
whose upgrade trigger is **a third consumer of the gate**, at which point the assertions re-scope to a
region LIST and the mechanism hoists once. Two is not a pattern. **D10** makes two safe meanwhile.

### D4 — `_bs_read_remedy` gains a TRAILING `step` operand with a default

It hardcodes `2.0` in **nine** messages (**C4**) — the ninth being the trailing "NOTHING about the
dedicated host was measured" summary, the line most likely to be read during an incident.

**Shape: `local label="$1" rc="$2" errfile="$3" rowsfile="$4" step="${5:-2.0}"`.** A trailing optional
with a default leaves BOTH `execute)` call sites byte-untouched, which is a strictly stronger
behaviour-preservation argument than editing them; the probe arm passes `"registry-probe"` as a fifth
argument. (An earlier draft used a LEADING positional, which put two bare label strings adjacent at
the call site with no cue which was which, and forced two edits into the P0 arm for no gain.)

**The proof is bounded, and the draft overstated it (C5).** Only two of the nine messages are
render-pinned (`:2112` maintenance, `:2120` credentials-rejected), and there is **no `heartbeat read:`
render at all**. So: those two renders are a NECESSARY, not sufficient, proof, and the other seven are
covered by a static census — inside `_bs_read_remedy`'s body, `grep -c '::error::2\.0 '` is **0** and
`grep -c '::error::\$step '` equals the total `::error::` line count. That census is the AC, not the
number nine, so a tenth message added later cannot slip through.

**Collateral, same edit:** the doc-comment signature line changes and `mutate_file`'s known-negative
`sed` is anchored on it (**D7** row 6).

### D5 — the probe arm's remedies never name a mutating op

2.0's remedies legitimately end in `op=execute` / `op=resume` / `op=rollback` because 2.0 runs INSIDE
a window. This op is dispatched outside one, frequently during an incident. **Flat ban:** no remedy
here names `op=execute`, `op=resume`, `op=rollback` or `op=arm`; every remedy ends at a READ, and
where recovery needs a mutating op the remedy points at the cutover runbook.

An earlier draft allowed them behind a literal qualifier string and then needed a lookbehind assertion
to police it. The flat ban is shorter, strictly stricter, and collapses the assertion to
`! grep -qE 'op=(execute|resume|rollback|arm)'`.

### D6 — the `webhook_path` remedy names `op=inventory`, and carries its discrimination rule

2.0's version names `op=registry-probe`, which is self-referential here. This arm names `op=inventory`
— a sibling GET through the SAME webhook path (`$BASE/inngest-inventory`, `:1266`, same
HMAC-over-empty-body + CF-Access headers). **The discrimination rule goes IN the emitted string:** a
200 isolates the fault to the `inngest-registry-probe` hook; a non-200 confirms the path itself
(CF Access / WAF / `webhook.service`). Otherwise the operator dispatches a sibling op at 3am and then
has to work out what its answer meant.

### D7 — six real assertion collisions; two draft entries were phantoms

**The phantoms first, because the lesson is the point (C3).** The draft claimed the no-mutating-hook
row broke on the heartbeat's log tag, and the no-doppler row on D8's remedy text. Measured: the hook
regex needs `inngest-` immediately followed by one of five words, and `inngest-cutover-flip` never
produces that (`grep -c` → 0); the doppler regex scores 0 over the 2.0 region. **Both proposed
re-aims were strictly WEAKER than the assertions they replaced** — the hook re-aim ("anchor at the
hook-path shape") would have matched the arm's own legitimate `"$BASE/inngest-registry-probe"` curl
and failed on a pristine tree. Both rows are deleted; both assertions ship byte-unchanged. This is
the `cq-assert-anchor-not-bare-token` class, committed inside a plan that cites the rule.

| # | Assertion | Why it breaks | Extension |
|---|---|---|---|
| 1 | `#8054 no other arm sources or calls the gate` (`grep -c` over `$BODY_SH` `-eq 1`) | a second call site makes it 2 | A per-arm census derived from the arm enumeration (`^  [a-z-]+\)$`): 1 in `execute)`, 1 in `registry-probe)`, 0 in every other arm, dispatch floor ≥ 12 arms — **PLUS the whole-file total held at exactly 2.** The census alone LOSES coverage: a gate call in a top-level function or in the `*)` catch-all (`:2927`) sits in no arm and escapes it. Both, not either. |
| 2 | `#6617 probe arms make exactly 2 network/tool calls` — the 2.0 region scores **7** | remedies contain `gh workflow run …` inside `echo "::error::…"` strings | The regex conflates *a tool named in prose* with *a tool invoked*. Derive ONE `PROBE_ARMS_CODE` = the region with comment lines removed and **the quoted ARGUMENT of every `echo "::(error\|notice\|warning)::…"` stripped** — not the whole line, because the guarded `source … \|\| { echo "::error::…"; exit 1; }` is one physical line and line-stripping would hide a real invocation. Rows 2, 4 and 5 of the `#6617` block all consume it. The existing assertions then ship **unedited**. |
| 3 | `#6617 probe arms add NO retry loop` — the 2.0 region scores **1** | the emit read is a line-start `while IFS= read -r …` | Keep the TOTAL ban and allowlist the one known loop by its exact header (`grep -vF 'while IFS= read -r _rpg_line; do'` before the loop grep). The draft's re-aim ("no loop containing `curl` or `_bs_query_rows`") was strictly WEAKER — it admits a retry loop around the gate call, around `openssl`, around `gh`. |
| 4 | `#6617 probe arms send NO request body` | **`mktemp -d` matches** — `-d` between whitespace (**C2**) | Require the `-d`/`-T` short forms to be adjacent to a `curl` invocation. Mutation row: `curl … -d '{}'` must still redden. |
| 5 | `FLQ_SITES` — `exactly 6 call sites` | two new `_bs_query_rows` sites → 8 | Raise to 8 **and extend the enumerating message** to name them, or the single-chokepoint row stops being readable. |
| 6 | `mutate_file "known-negative"` sed anchored on `_bs_read_remedy`'s doc-comment | **D4** changes that line | Update it in the same commit. Un-updated, the harness's only self-test silently becomes a no-op. |

Rows 2-6 serve no Property-List entry: they are **forced collateral**, not design. Only row 1 serves
P5, and that is labelled so no reviewer hunts for the property behind each one.

**One latent seventh to avoid rather than extend:** `! grep -qE 'hooks/deploy'` does not strip
comments, and D8's rationale mentions `/hooks/deploy-status`. Write that reason into the PLAN, not
into a code comment inside the arm.

### D8 — `flag_armed`, `host_serving`, `silent`: new semantics, a 2×2 branch, and a new OUTPUT SHAPE

The gate emits `flag` and `hb_flag` **before** it refuses (lib `:1253`, `:1304`), so the caller can
discriminate with no lib change. That invariant is cited, not assumed, because the whole re-scope
rests on it.

**The 2×2 is mandatory and the draft got it wrong (C7).** E11 grades the probe row's flag BEFORE E13
reads the heartbeat, so on an E11 refusal `hb_flag` is `__UNREAD__` — and on an E13 refusal the emit
file holds `flag=rolled-back` AND `hb_flag=done` simultaneously. A branch keyed on "either equals
`done`" mis-grades the second; one keyed on `$RPG_HB_FLAG` alone drops the first into `*)`. Mirror
2.0 (`:1521`): **outer branch on `__UNREAD__` picks WHICH SAMPLE, inner branch on that sample's value
picks `done` vs `armed|flipping|flushed`. Four messages, not two**, and each names the sample it is
quoting. On the E11 path `RPG_HB_AGE` is `__UNREAD__` and must not be interpolated.

- **`done`** — the cutover is COMPLETE and the host is not answering; since 2.4, **production cron
  scheduling may be down**. Must NOT say "the cutover already completed: dispatch op=verify", and
  must NOT name `restart-inngest-server.yml`.
  **On the probe-row (E11) branch the sample is the HOURLY row, up to 60 min stale** — so it carries
  the staleness qualifier the way 2.0's `:1526` does for its own direction. Without it the arm can
  send an operator to REPLACE a host they deliberately rolled back ten minutes earlier: the flag goes
  `rolled-back`, the hourly row still reads `done`, and E11 refuses before E13 ever reads the fresh
  heartbeat that would say otherwise. That is the same "answer the wrong question confidently" defect
  the Premise Correction exists to avoid, reproduced inside its own fix.
- **`armed`/`flipping`/`flushed`** — a sequence is in flight; read that run, dispatch nothing.
- **`host_serving`** — row and webhook disagree; post-cutover that usually means the webhook path.
  `op=inventory` with D6's rule, then the host's own state.
- **`silent`** — 2.0 escalates after two readings to `inngest-host-replace`. Known false positive: on
  2026-08-14 the Better Stack Logs quota exhausted and **ingest returned 402 for ~49 h while the read
  path answered 200** — rows absent, read healthy, i.e. exactly `silent`. Both this arm's remedy and
  2.0's gain one clause: confirm ingest health/quota before treating silence as a dead host.
- **The other five** (`wrong_host`, `stale_row`, `stale_schema`, `flag_unreadable`, `fsm_silent`) are
  NOT designed here and must not become five bespoke near-copies. Each is the op-independent host
  fact (reuse 2.0's wording) plus one op-appropriate next line obeying D5.

**OUTPUT SHAPE.** The highest-stakes sentence must not arrive last inside one long annotation after
two lines that read as progress — GitHub truncates long annotations in the summary panel. For
`flag_armed`+`done`: (1) the headline as its own SHORT `::error::`; (2) the ordered steps as **plain
log lines**, which wrap (2.0 already prints the webhook body as a plain line); (3) **the dispatchable
read FIRST** — `scheduled-inngest-health.yml`'s latest run via `gh run list`, then
`scripts/inngest-host-state.sh` **with its prerequisites stated in the string** (it is not
dispatchable — verified), then `apply_target=inngest-host-replace`.

### D9 — the two self-referential strings inside 2.0 are corrected here (P7)

- `:1434` (2.0 `webhook_path`): *"when it returns the `__FETCH_FAILED__` refusal or HTTP 200,
  re-dispatch op=execute."* After this change the arm no longer REFUSES on `__FETCH_FAILED__` — it
  grades and may go green, so the operator waits for a refusal that never comes.
- `:1515` (2.0 `host_serving`): *"If that returns 200 the host IS serving pre-arm."* Both the
  colour-inference and the word `pre-arm` are stale.

Both amended to key on the LIVE marker: *"if that run prints a `registry_empty=` line, the host IS
serving."* The existing assertion's `REFUSED \(webhook_path\).*op=registry-probe` match survives.

### D10 — three drift guards for the accepted duplication

1. **Token coverage by reusing the existing loop.** The suite already derives `ERG_TOKENS` from the
   gate's function body and presence-checks each against `$EXEC_ARM_FILE`. Run the SAME loop against
   `$PROBE_ARM_FILE`. Both arms then quantify over the lib's set, so a 12th lib token reddens both.
   Non-vacuity rides on the existing `ERG_TOKEN_N -eq 11` row surviving — three empty sets are equal.
   The probe arm's emit `case` arms MUST stay single-line (as `:1484`-`:1488` are), because that is
   what keeps the `$`-anchored token pattern from swallowing `flag)`, `boot_id)` etc.
2. **Plumbing parity by prefix normalisation.** One assertion: the probe plumbing region normalised
   with `sed 's/^RPG_/ERG_/; s/\$RPG_/$ERG_/g'` equals the exec plumbing region. That single row pins
   the `trap` POSITION, the `: > "$EMIT"` pre-touch, the `|| RC=$?` shape, both read windows, the emit
   shape regex and the absence of a `umask`. It is also the real justification for the `RPG_*` prefix
   — a uniform prefix is what makes the normalisation mechanical. (The prefix's earlier rationale,
   "it keeps existing `ERG_*` assertions exec-arm-scoped", was false: all of them already are.)
3. **Cross-arm remedy guard.** Guards 1 and 2 pin the token set and the plumbing; nothing pins the
   ELEVEN remedy strings, where all the divergence and all the value live. The plan proves the class
   is live by hitting it itself — D8's ingest/quota clause must land in BOTH `silent` remedies, caught
   only because someone looked. One row per arm: every non-`dark` token's remedy names at least one
   no-SSH instrument (`gh workflow run`, `gh run list`, `scripts/inngest-host-state.sh`,
   `op=inventory`). Plus a `# twin: <the other arm's marker>` comment at each `case` head.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the op is operator-dispatched,
read-only, and gates nothing. The path to user harm is indirect: post-cutover `10.0.1.40` is the only
cron scheduler, so a non-200 here can mean every scheduled job is down, and a remedy that misdirects
the operator (2.0's "the cutover already completed: dispatch op=verify", which **D8** forbids, or a
host REPLACE triggered off a 60-minute-stale flag, which **D8**'s staleness qualifier forbids)
lengthens an outage in which no reminder email, no SLA sweep and no billing cron fires. The outage is
always caused elsewhere; this arm only shortens or lengthens the diagnosis.

**If this leaks, the user's data is exposed via:** a PUBLIC repository's run log. Two vectors, both
already live on the 2.0 path: (1) the Better Stack read's credentials enter via `doppler run` INSIDE
the reader, so GitHub's masking never sees them, and a ClickHouse 403 body is `Code: 516.
DB::Exception: <BETTERSTACK_QUERY_USERNAME>: Authentication failed…`; (2) raw journald rows carry
host internals. Scoped precisely: **the Better Stack HTTP error body is never printed** (only its
length and a two-way classification); **the WEBHOOK body is printed once, CR/LF-stripped**, on the
two branches that have no other cause to report. Row files live under a `mktemp -d` (0700) removed on
`EXIT`; the gate's stdout is one token; every printed field comes from `--emit-file` behind a shape
regex.

**Brand-survival threshold:** aggregate pattern

Counter stated so a reviewer can overrule: post-cutover this arm sits on a production-outage
diagnosis path, which argues for `single-user incident`. Not adopted because the harm is *diagnosis
latency during an incident caused elsewhere*, which compounds across occurrences rather than
materialising in one, and because the mutating path has its own independent gate (2.0).

## Open Code-Review Overlap

Checked 2026-09-20 against 65 open `code-review` issues by substring match of each planned file path
against every issue body (two-stage `gh issue list --json` → standalone `jq --arg`). All four planned
paths: **None.** Nothing to fold in, acknowledge or defer.

## Files to Edit

1. **`scripts/cutover-inngest.sh`**
   - `_bs_read_remedy()`: trailing `step="${5:-2.0}"`; all **nine** `2.0 ` prefixes → `$step `;
     doc-comment signature line (**D4**). **Both `execute)` call sites stay untouched.**
   - `:1434`, `:1515`: the two self-referential strings (**D9**).
   - 2.0's `silent)` remedy: the ingest/quota clause (**D8**).
   - The `registry-probe)` arm: **restructure to `if … else … fi` first** (**C1**), then the non-200
     branch, then region markers at the arm's head and tail.
2. **`apps/web-platform/infra/cutover-inngest-workflow.test.sh`** — the six **D7** extensions, the
   three **D10** guards, the probe-arm static rows, the probe-region renders, the mutation rows, the
   `_bs_read_remedy` census (**D4**), and `_EXACT_FLOOR`. **No `render_2_0` rename** (already generic).
3. **`knowledge-base/engineering/operations/runbooks/inngest-server.md`** — anchored on SECTION
   HEADINGS, not line numbers, because edit (b) shifts (a) and (c):
   - § "Dedicated-host cutover" → "Window procedure", item 1(a): add `op=registry-probe` as the
     cheaper pre-window reading; and **lead with** the operator-facing direction of the shared
     `deploy-inngest-restart` concurrency group — during the incident this arm diagnoses, the
     watchdog's auto-restarts serialise AHEAD of the diagnostic dispatch.
   - § "Cutover pre-flight-hang triage", item 3: a standalone `op=registry-probe` that exits 0
     **without** a `registry_empty=` line is the host-state verdict, not a live measurement. Plus:
     **a red `restart-inngest-server` run is not a statement about this host.**
   - § "2.0 registry-non-empty remediation (P1-6)": widen the opening clause to the standalone op.
   - § "Cutover procedure" is the SAME-HOST durable-backend cutover and is **not** edited.
   - Optional, free: `.github/workflows/cutover-inngest.yml` header points readers at that wrong
     section for all ops.

## Files to Create

None.

## Implementation Phases

### Phase 0 — verify live state; baselines already measured

Baselines are in `## Research Insights` (measured during planning, not asserted). Remaining:

1. **Re-confirm live host state before writing code:**
   `doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh`. Expect
   `cutover_flag=done`, `server_active=active`, `http_code=200`. **The concrete fork if it
   disagrees:** a `rolled-back`/`aborted` reading makes `dark` the live branch and **D8**'s `done`
   remedy unreachable by anything but a synthetic fixture — Test Scenario 4 becomes synthetic-only
   and must be labelled as such, and the D8 priority ordering is revisited.
2. **Re-sync `main`** before running the ratchets (PR #8389 touches
   `plugins/soleur/test/fixture-relative-assert.baseline.txt` and ADR-100).

### Phase 1 — `_bs_read_remedy` (D4), landed alone

Re-read the function and its doc comment first. Add the trailing `step` operand with its `2.0`
default; replace all **nine** prefixes; update the doc comment; update `mutate_file`'s known-negative
`sed`; add the `_bs_read_remedy` census assertion. Both `execute)` call sites are untouched by
construction. The suite must be green at 665 with no count change except the census row.

### Phase 2 — restructure the `registry-probe)` arm (C1), before any new logic

Convert `if [[ "$CODE" != "200" ]]; then … exit 1; fi` + fall-through into
`if [[ "$CODE" != "200" ]]; then <non-200 branch> else <the 200 path, unchanged> fi`. Place the
region-open marker immediately BEFORE `SIG=$(printf '' | openssl …)` and the close marker immediately
before the arm's `;;`, mirroring 2.0.

This ordering is not cosmetic. It is what makes the region **self-contained and sourceable** (the
draft's markers sat inside the `if` body, so the extracted region excluded the enclosing `if`/`fi`
and the 200 path — the render would have reported `__RC=0` and `__REGION_FELL_THROUGH__` while
production exited 1 printing the raw body, a green suite over a broken arm). It is also what makes
Test Scenarios 13/14 (the live-200 renders) possible at all, and it gives the dark sub-block a
terminator (`^    else$`) so the purity greps can be scoped the way the existing `ANNOT_LEAKS`
extractor at `:1928` scopes 2.0's.

**Extend the render driver's preamble in the same step:** it exports `BASE`, `WEBHOOK_SECRET`,
`CF_ACCESS_*`, `INNGEST_HOST*`, `FLIP_LIVENESS_SINCE` and computes `CODE`/`BODY` from the stubbed
`curl`. A region starting after `BODY=$(cat …)` would die on `CODE: unbound variable` under `set -u`.
Starting the region at `SIG=` avoids that — confirm it, do not assume it.

Run the suite: green at 665, structure-only change.

### Phase 3 — the 2.0 text corrections (D9, D8's `silent` clause)

Amend `:1434`, `:1515` and 2.0's `silent)` remedy. Re-run: the `webhook_path` render pins only the
prefix and `.*op=registry-probe`, the `silent` render only the prefix, so both should stay green. If
either reddens, look at the assertion before the string.

### Phase 4 — the non-200 branch

Preamble unchanged. Then, in order: the `webhook_path` pre-refusal naming `op=inventory` **with D6's
discrimination rule in the string**, before any Better Stack read; the signature notice and the
CR/LF-stripped body once as a plain line; the guarded `source`; `mktemp -d` then IMMEDIATELY
`trap 'rm -rf "$RPG_DIR"' EXIT`; the two reads (24h probe / 30m heartbeat), stderr to files, rc into
`RPG_PROBE_RC`/`RPG_HB_RC`; `: > "$RPG_EMIT"`; the gate call with `|| RPG_RC=$?`; the
sentinel-initialised emit read loop behind the shape regex, its inner `case` arms **single-line**;
then `case "$RPG_VERDICT"` — `dark)` with the rc/token agreement check, the **D2** notice + warning
and NO exit; `flag_armed)` as **D8**'s 2×2; `host_serving)`/`silent)` per **D8**; `unreadable)` /
`fsm_unreadable)` delegating to `_bs_read_remedy … "registry-probe"`; the other five per **D8**;
`*)` sanitised, naming the GATE as the defect. Every non-`dark` arm exits 1; every remedy ends
`Do NOT SSH the host.` and obeys **D5**.

### Phase 5 — suite extension

The six **D7** extensions; the three **D10** guards; the probe-arm static rows; the region extraction
with its selection control; the renders; the mutation rows. Then run the suite, read `_DISPATCHED`
from its own failure message, and set `_EXACT_FLOOR` to exactly that.

**Do not grow the itemised delta comment** and **re-measure after the FINAL rebase onto `main`, not
at authoring time** — the documented failure was a stale CORRECT measurement, not a guess. (Replacing
the exact-integer convention outright is UC3 in `decision-challenges.md`; not adopted here.)

### Phase 6 — runbook and gates

The runbook edits, then run and record verbatim: the two suites, the dark-gate lib suite, the four
repo-global ratchets BY HAND (they reference no changed file and are invisible to file-based
selection), `bash -n scripts/cutover-inngest.sh`, and `shellcheck` if available. `--capacity` already
measured CONTENDED, so the PR body states which suites ran rather than claiming a full gate.

## Acceptance Criteria

Every criterion below is a property of the ARTIFACT, verified by a named assertion or render.

- [ ] **AC1** — a non-200 with `__FETCH_FAILED__` plus fixture rows establishing darkness completes
      **rc 0**, prints the HOST-STATE VERDICT notice and the caveat warning, and the region reaches
      its end rather than falling into the 200 path. Proven by a render over the FULL arm region.
- [ ] **AC2** — the dark sub-block's output contains none of `registry_empty=`, `function_count=`,
      `ids=[`. Scoped to the sub-block via the `^    else$` terminator, as `ANNOT_LEAKS` does for 2.0.
- [ ] **AC3** — the caveat warning contains both clause openers and names the follow-up op.
- [ ] **AC4** — `flag_armed` renders **four** distinct messages across the 2×2 (`__UNREAD__` ×
      `done` | `armed|flipping|flushed`); each names which sample it quotes; the probe-row `done`
      branch carries the 60-minute staleness qualifier and does not interpolate `RPG_HB_AGE`; and no
      `done` message contains "the cutover already completed", `op=verify` or `restart-inngest-server`.
- [ ] **AC5** — every token the gate can emit has a `case` arm in the probe arm, checked by the SAME
      lib-derived loop the exec arm uses, with the `ERG_TOKEN_N -eq 11` non-vacuity row intact.
- [ ] **AC6** — the gate call is `|| RPG_RC=$?`-guarded and a refusing fixture still prints its
      `::error::` (dynamic render).
- [ ] **AC7** — a webhook 403, and a 500 without `__FETCH_FAILED__`, both refuse as `webhook_path`
      with rc 1 and perform NO Better Stack read, against a positive control proving the markers DO
      appear on the graded path.
- [ ] **AC8** — the probe region contains no `ssh ` and no `op=(execute|resume|rollback|arm)`.
- [ ] **AC9** — the HTTP-200 path is **content-pinned modulo leading indentation and comment lines**,
      as the existing AC7 pin does for 2.0 (the `if/else` restructure changes indentation, so
      "byte-unchanged" would be unsatisfiable), and performs NO Better Stack read.
- [ ] **AC10** — no probe-arm annotation interpolates `RPG_PROBE_ROWS`, `RPG_HB_ROWS`, `BODY` or
      `CAUSE`; every printed field comes from the emit-file read; **and every site printing `$BODY`
      or `$CAUSE` uses the CR/LF-stripped form**, proven by a render whose body contains a literal
      newline followed by `::notice::PASS` (annotation log-injection).
- [ ] **AC11** — the plumbing parity row holds: the probe plumbing region, prefix-normalised, equals
      the exec plumbing region.
- [ ] **AC12** — inside `_bs_read_remedy`'s body, `grep -c '::error::2\.0 '` is 0 and
      `grep -c '::error::\$step '` equals the total `::error::` line count; both `execute)` call sites
      are unmodified (`git diff` over those two lines is empty).
- [ ] **AC13** — the consumer census holds AND the whole-file total is exactly 2: 1 in `execute)`,
      1 in `registry-probe)`, 0 in every other arm, ≥ 12 arms enumerated, `grep -c` over the file = 2.
- [ ] **AC14** — every `#6617` and `FLQ_SITES` assertion this change touches still rejects the
      violation it was built to catch, each proven by its own mutation row; the two phantom rows are
      absent and their assertions unmodified.
- [ ] **AC15** — 2.0's two self-referential strings key on the `registry_empty=` marker, and 2.0's
      `silent` remedy carries the ingest/quota clause.
- [ ] **AC16** — the runbook edits are present, each located by its SECTION HEADING; § "Cutover
      procedure" is unmodified.
- [ ] **AC17** — `_EXACT_FLOOR` equals the suite's dispatched count, measured after the final rebase.

## Guard Contract

### Guard 1 — the gate's consumer set

**Property.** `inngest_execute_registry_gate` is called from exactly two arms — `execute` and
`registry-probe` — and from nowhere else in the script, now or after any future arm is added.

**Assembly.** The chokepoint is the single top-level `case "$OP" in`, enumerated structurally by
`^  [a-z-]+\)$` (14 arms today) with each extracted by the `awk` range the suite already uses. **Plus
the whole-file total**, because the per-arm census alone cannot see a call in a top-level function or
in the `*)` catch-all, which match no arm pattern. The dispatch floor (≥ 12 arms) is part of the
assembly: a collapsed enumeration would satisfy "0 other arms" vacuously.

**Mutation matrix.**

| # | Mutation | Must redden |
|---|---|---|
| M1.1 | Add a gate call to a THIRD arm — **anchored on `rollback)` (`:2495`), which follows BOTH compliant members.** The draft used `enumerate)` (`:791`), the FIRST arm, so a census that stopped after two members would still have caught it and the row proved nothing (**C8**) | "0 gate calls in every other arm" — the **second-member** row |
| M1.2 | Rename the `registry-probe)` arm's call | "exactly 1 in `registry-probe)`" |
| M1.3 | Rename the `execute)` arm's call | "exactly 1 in `execute)`" — the census is not scoped to the new arm |
| M1.4 | Break the arm-enumeration anchor in the SUITE (`^  [a-z-]+\)$` → `^  ZZZ[a-z-]+\)$`) | the **dispatch floor** — the guard's own dispatch row, required because a guard reporting "0 arms checked" and exiting 0 is vacuous |
| M1.5 | Add a 12th token to the lib (`_ihdg_verdict "fsm_stale"; return $?`) | BOTH arms' coverage rows and the `ERG_TOKEN_N -eq 11` row — the "instance it has never seen" row |

**Harness rows.** M1.4 is the suite-side row. The must-PASS non-canonical input is Guard 2's H2.

**Anchor.** `_EXACT_FLOOR` is a stored count and survives add-one-delete-one, so it is NOT the
integrity anchor — SET IDENTITY is. The census derives the arm set from the script and the token set
from the lib's function body, so weakening either requires editing the thing being measured. The
floor's narrower role: it catches DELETION, not substitution.

### Guard 2 — the probe arm's non-200 behaviour

**Property.** When and only when the non-200 carries the host's own fetch-failure signature, the arm
grades the host from its own rows; `dark` exits 0 carrying the evidence and an explicit statement that
the registry was NOT read live; every other verdict exits 1 having printed a no-SSH remedy phrased for
a standalone probe — and for `flag_armed` under `done`, one describing a production outage with its
sample named and its staleness qualified; and no path prints a raw row, a credential-bearing body, or
the live-measurement triple.

**Assembly.** The chokepoint is the FULL extracted arm region (head marker before `SIG=`, tail before
`;;`), executed in a fresh `bash` process by `render_2_0` with `curl` and the `doppler` PROCESS
stubbed and the REAL gate lib, `_bs_query_rows` and `_bs_read_remedy` sourced from the script. The
process boundary is load-bearing: bash disables `errexit` inside an `if` condition or the left of
`||`, so a subshell would render an un-guarded mutant identically to the guarded original. The token
population is derived from the gate's function body.

**Mutation matrix.**

| # | Mutation | Must redden |
|---|---|---|
| M2.1 | Drop `\|\| RPG_RC=$?` | a refusing fixture must still print its `::error::` and exit 1, not die mute |
| M2.2 | Add `exit 1` to `dark)` | the rc-0 render — **pins D1** |
| M2.3 | Neuter the `webhook_path` test (`if false`) | a 403 must refuse with no Better Stack read |
| M2.4 | Append `=false` to the warning's `registry_empty` mention | the reserved-triple row — **pins D2**, and proves the assertion is one character from self-falsifying |
| M2.5 | Replace the `flag_armed`/`done` body with 2.0's "the cutover already completed: dispatch op=verify" | **AC4** — **pins D8** |
| M2.6 | Collapse D8's 2×2 to a single branch on `$RPG_FLAG` | the four-message row — pins the `__UNREAD__` sample discriminator (**C7**) |
| M2.7 | **Delete the `trap` line** (a genuine one-line mutation), with the trap's correct home being **after `esac`** so every refusal leaks `$RUNNER_TEMP/rpg.*` | Test Scenario 15. The draft specified a MOVE between two positions with no exit between them — unkillable — and `mutate_file` requires a one-line diff while a move changes two (**C9**) |
| M2.8 | Make the `*)` arm fall through | "`*)` exits 1 and names the gate as the defect" |
| M2.9 | Append a real `gh workflow run` invocation to the END of an existing `echo "::error::…"` line | the tool-count row — proves the annotation-ARGUMENT strip has no line-level evasion |
| M2.10 | Add `curl … -d '{}'` to the region | the re-aimed no-request-body row (**C2**) |
| M2.11 | Wrap the `curl` in a `for attempt in 1 2` loop | the total-ban-plus-allowlist loop row |
| M2.12 | Point the region's `curl` at `$BASE/inngest-rearm-reminders` | the **existing, unmodified** no-mutating-hook assertion — a regression check proving the phantom row was right to delete |

**Harness rows.**

- **H1 (must-FAIL):** render with `cutover_flag=armed` → exit 1, `flag_armed`. A harness stubbed to
  always emit the dark notice, or a check ignoring rc, goes red here.
- **H2 (must-PASS, NOT canonical):** render with `cutover_flag=aborted` on the probe row and
  `{"flag":"aborted","reason":"noop-aborted"}` on the heartbeat — the OTHER `preflip` member, which
  the contract explicitly permits. Must render rc 0 dark exactly as `rolled-back` does.
- **H3 (extraction control):** the probe-arm extractor's output is non-vacuous AND contains no
  `CRON_PERIOD` (the neighbouring `doublefire-probe` arm's unique token).
- **H4 (existing):** `mutate_file`'s known-negative — a comment-only mutation reported as NOT
  reddening; its `sed` updated for **D4** in the same edit.

**Anchor.** The `__FETCH_FAILED__` admission literal is DERIVED from the producer
(`apps/web-platform/infra/inngest-registry-probe.sh`) and required to equal the literal the arm tests
for, so a rename on either side reddens instead of silently refusing every dispatch. D10's token
coverage is the second anchor: it ties both arms to the lib rather than to each other.

## Observability

Surface: `scripts/cutover-inngest.sh` executed by `.github/workflows/cutover-inngest.yml` on a
`workflow_dispatch`. No server-side runtime, no async sink; the operator's only synchronous signal is
the workflow run log — **observability layer 6** (synchronous webhook-response body / workflow-run
log), cited for every failure mode.

```yaml
liveness_signal:
  what: "the ::notice::registry-probe HOST-STATE VERDICT / ::warning:: pair, or an ::error::registry-probe REFUSED (<token>) line, on the cutover-inngest workflow run"
  cadence: "per operator dispatch — workflow_dispatch only, by design (#6617: a diagnostic, not a scheduled probe)"
  alert_target: "the dispatching operator, via the run's annotations and the job's exit status (layer 6)"
  configured_in: ".github/workflows/cutover-inngest.yml (job `cutover`, step `Run cutover host op via webhook`)"
error_reporting:
  destination: "GitHub Actions run log + annotations (layer 6); the job turns red on every non-dark verdict"
  fail_loud: "yes — every non-dark token exits 1 after printing its remedy; the || RPG_RC=$? call shape exists so no refusal can be fail-closed-but-mute under set -e"
failure_modes:
  - mode: "the dedicated host has stopped answering while the flag reads done — production cron scheduling may be down"
    detection: "a short ::error:: headline plus ordered plain log lines, from the flag_armed 2x2 (layer 6, workflow run log)"
    alert_route: "run turns red; step 1 is the dispatchable scheduled-inngest-health.yml read, then inngest-host-state.sh with its prerequisites stated, then apply_target=inngest-host-replace — never op=verify, never restart-inngest-server.yml"
  - mode: "a cutover sequence is in flight (flag armed/flipping/flushed)"
    detection: "::error::registry-probe REFUSED (flag_armed) naming the sample and its age (layer 6)"
    alert_route: "run turns red; the remedy says read that run and dispatch nothing"
  - mode: "the row and the webhook disagree (host serving, webhook non-200)"
    detection: "::error::registry-probe REFUSED (host_serving) (layer 6)"
    alert_route: "run turns red; op=inventory with its discrimination rule, then the host's own state"
  - mode: "the host emitted no probe row in the window"
    detection: "::error::registry-probe REFUSED (silent) (layer 6)"
    alert_route: "run turns red; confirm Better Stack ingest health/quota BEFORE treating silence as a dead host (the 2026-08-14 402-for-49h precedent)"
  - mode: "the gate library is absent on the dispatched ref"
    detection: "::error::registry-probe: gate library … not found on this ref (layer 6)"
    alert_route: "run turns red; the message names --ref main"
  - mode: "the Better Stack read fails (credentials absent/rejected, transport, maintenance)"
    detection: "_bs_read_remedy prints an rc-classified ::error::registry-probe … read: line (layer 6); the HTTP error body is never printed, only its length and a two-way classification"
    alert_route: "run turns red; the remedy names the value-silent Doppler check, no SSH"
  - mode: "the webhook path itself is broken (CF Access 403, WAF 5xx, webhook.service down, 000)"
    detection: "::error::registry-probe REFUSED (webhook_path) (layer 6), emitted BEFORE any Better Stack read"
    alert_route: "run turns red; op=inventory, with 200-vs-non-200 meaning stated in the string"
  - mode: "the gate returns a token this arm does not recognise (a gate defect)"
    detection: "::error::registry-probe REFUSED: … unrecognised verdict '<sanitised>' (layer 6), with both rcs, never the raw stdout"
    alert_route: "run turns red; the message names the gate as the defect"
  - mode: "the host is dark under a preflip flag (a deliberate rollback)"
    detection: "::notice::registry-probe HOST-STATE VERDICT: dark + the two-clause ::warning:: (layer 6)"
    alert_route: "run stays GREEN by design (D1); the warning is what makes the unanswered question visible in the run summary"
logs:
  where: "GitHub Actions run log for .github/workflows/cutover-inngest.yml"
  retention: "repository default for Actions logs (90 days)"
discoverability_test:
  command: |
    grep -c 'RPG_VERDICT=.*inngest_execute_registry_gate' scripts/cutover-inngest.sh
  expected_output: "1"
```

The `discoverability_test` is the smallest command that prints the signal, never the suite: one `awk`
plus one `grep` over a tracked file, no network, no credentials, milliseconds (well inside preflight
Check 10's 15 s cap), literal expected output `1`. `credentials_required` is omitted because an
unauthenticated local probe verifies the property.

### Soak / follow-through enrollment

Not applicable. No acceptance criterion and no `liveness_signal` here is time-gated; every criterion
is decided by a suite run at merge time. No `soleur:followthrough` directive is emitted — an
enrollment for a non-existent soak would be a directive nothing could satisfy.

## Follow-Through Directives

At ship time, post the `## Premise Correction` section to issue #8079 as a comment before the PR merges, so the issue's own thread records that its pre-arm framing was superseded by the 2026-09-15 cutover completion and that the fix was re-scoped in place rather than closed as overtaken.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed — `soleur:engineering:cto` (twice: structural at Phase 2.5, devex at plan-review),
`soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer`.

**Assessment.** The CTO's structural pass produced the stale-premise finding that re-shaped this plan.
Kieran's pass produced the **C1 blocker** (the arm has no `else`) and the C2 missed collision, and
rejected three of the draft's re-aims as net loosenings. DHH and code-simplicity independently found
the C3 phantoms by running the regexes. The devex pass produced the output-shape and
dispatchable-remedy corrections and the cross-arm remedy guard. Every correction is in
`## Review Corrections` with its measurement.

Two reviewers argued for a materially smaller mechanism; that is scope the operator asked for by name,
so it is routed to `decision-challenges.md` (UC1) rather than auto-applied.

### Operations

**Status:** reviewed — `soleur:operations:coo`.
**Assessment.** No new credential, no new spend. Produced the two self-referential 2.0 strings (D9),
the remedy-escalation ban (D5), the reserved-triple widening (D2) and the Better Stack ingest-quota
false positive behind the `silent` escalation (D8). Located the runbook edits by reading, and
established that § "Cutover procedure" is the SAME-HOST cutover and must NOT be edited.

**Out of scope, recorded not deferred:** `knowledge-base/operations/expenses.md` carries the Better
Stack row with `verify_by=2026-09-16`, overdue. Pre-existing, not caused by this change — and open
PR #8389 already touches that file, so it is being handled elsewhere.

### Product/UX Gate

Tier **NONE**. The mechanical UI-surface scan finds no path under `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx` or any UI-surface glob in `## Files to Edit` / `## Files to Create`. The change's
entire user surface is a GitHub Actions run log read by one operator.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Close #8079 as overtaken** | The code defect is live and now sits on a production-outage diagnosis path. Only the motivation is historical. |
| **Drop the gate import; just discriminate `webhook_path` and name the dispatchable reads** | Meets P3/P4, weakens P1, and drops most of the assertion collisions. Two reviewers argued for it — but it drops scope the operator named, so it is **UC1** in `decision-challenges.md`, not a silent re-scope. |
| **`dark` exits non-zero with a distinct token** | Inverts the arm's own convention and reds a state the operator created deliberately. Prevented in the message instead (**D2**). |
| **Teach the LIB a post-cutover flag partition** | Would alter a destroy gate's semantics to fix a diagnostic's message. The emit file already carries what the caller needs. |
| **A new gate entry point** | Same host, same rows, same 11 tokens; a fork would drift (the E11/E13 allowlist drifted once already). |
| **Hoist the shared mechanism** | **D3** — the interface, not the suite: seven values handed back through globals. |
| **Bump the consumer assertion to `-eq 2`** | Keeps the number, loses the property. Census **plus** whole-file total instead. |
| **Loosen the `#6617` assertions to let the new code through** | Two of the four were never broken (**C3**), and every proposed loosening was strictly weaker than what it replaced. Annotation-argument stripping keeps them unedited. |
| **Rename `render_2_0` → `render_arm_region`** | Already generic (`local region="$1"`). Pure churn in a file whose floor conflicts at merge. |
| **Replace the `_EXACT_FLOOR` convention** | A shared-convention change far beyond this arm — **UC3**. The two narrow parts (re-measure after rebase; stop growing the delta comment) ARE adopted. |
| **Make `scripts/inngest-host-state.sh` dispatchable** | Orthogonal and valuable (**UC2**); mitigated inline by D8's remedy ordering rather than grown into this PR. |

## Test Scenarios

EXECUTED unless marked *(static)*. Dynamic scenarios run the FULL extracted arm region in a fresh
`bash` process with `curl` and the `doppler` process stubbed and the real gate lib sourced.

1. **Dark, canonical.** 500 + `__FETCH_FAILED__`; probe row `http_code=000 server_active=failed
   cutover_flag=rolled-back registry_fns=__UNREADABLE__ probe_schema=8 host_role=dedicated`; same-boot
   heartbeat 1 min old, `rolled-back` → rc 0; notice carries a 36-char `boot_id`, a row age,
   `flag=rolled-back`, a heartbeat age, `hb_flag=rolled-back`; warning carries both clause openers;
   no reserved triple; no raw row field (`zz_trailing` absent); region does not enter the 200 path.
2. **Dark, non-canonical must-PASS (H2).** `aborted` on both rows → rc 0, same shape.
3. **Armed must-FAIL (H1).** `cutover_flag=armed` → rc 1, `flag_armed`, remedy dispatches nothing.
4. **`done` on the PROBE row (E11 path).** → rc 1; short headline; ordered plain lines; the
   dispatchable read first; names the HOURLY sample with its ≤60-min staleness qualifier; does not
   interpolate `RPG_HB_AGE`; contains none of "the cutover already completed", `op=verify`,
   `restart-inngest-server`.
5. **`done` on the HEARTBEAT (E13 path), probe row `rolled-back`.** → rc 1; names the heartbeat as
   the sample; distinct message from (4). This is the case a single-branch implementation mis-grades.
6. **Silent.** Zero probe rows → rc 1, `silent` including the ingest/quota clause.
7. **fsm_silent.** Dark row, no same-boot heartbeat → rc 1.
8. **host_serving.** Probe row `http_code=200` → rc 1, names `op=inventory`; no mutating op.
9. **Read failure.** probe rc 22 maintenance body → rc 1, the maintenance classification, body NOT
   printed, the "NOTHING about the dedicated host was measured" line present **prefixed
   `registry-probe`, not `2.0`** (this is the ninth message from **C4**).
10. **Credentials rejected.** rc 22 with a `Code: 516` body → rc 1, classified, username substring
    absent from the entire output.
11. **webhook_path 403.** → rc 1, names `op=inventory` with its discrimination rule, NEITHER read
    marker present.
12. **webhook_path 500 without the signature.** → rc 1, no read.
13. **Marker control.** The graded path DOES leave both read markers, so (11)/(12) are measurements.
14. **Live 200, empty.** → rc 0, prints `registry_empty=true function_count=0 ids=[]`, NO read.
15. **Live 200, non-empty.** → rc 0 with the existing warning naming `op=doublefire-probe`.
16. **Trap window.** After (6)'s refusal, no `rpg.*` directory remains under the render's
    `RUNNER_TEMP`.
17. **Annotation injection.** A webhook body containing a literal newline then `::notice::PASS`
    renders with that text CR/LF-stripped onto one line and no synthetic `::notice::` in the output.
18. *(static)* **Consumer census + whole-file total** (AC13).
19. *(static)* **Token coverage** both arms, `ERG_TOKEN_N -eq 11` intact; ≥ 10 `exit 1` inside the
    probe `case` (mirrors the exec arm's floor; a deleted arm falling to `*)` is caught by the
    coverage row, not by this floor).
20. *(static)* **Plumbing parity** (AC11) and **extraction control** (H3).
21. *(static)* **Purity, no-SSH, no mutating op** (AC8, AC10).
22. *(static)* **HTTP-200 content pin** modulo indentation and comments (AC9).
23. *(static)* **`_bs_read_remedy` census** and both `execute)` call sites unmodified (AC12).
24. **Exec-arm regression.** Every existing `#8054` render and the AC7 content pin green with no edit
    to their expectations.
25. **Mutation matrix.** M1.1-M1.5 and M2.1-M2.12 redden; H4's known-negative does not.

## Review round — 2026-09-20 (PR #8426, 10 seats + coverage consult)

Corrections applied on the branch; the sections above are the design record as planned, this
block is what the review changed and why. Nothing here reverses a D-number.

- **D2 wording was false post-rollback.** "nothing can have registered since boot `<id>` — its
  inngest-server has not been bound on this boot" is a universal the gate never measures: `op=rollback`
  is `systemctl stop`, same `boot_id`, and the server served ~70 registered functions on that boot
  before the stop (ADR-100 addendum 2026-09-15). E9–E14 establish "not serving as of the newest row,
  flag pre-arm on the heartbeat, no FSM transition since". The notice and the warning now say
  exactly that, plus the same-boot rollback caveat; a render row pins the interval wording and bans
  the since-boot phrasing. (data-integrity + architecture seats, converged.)
- **`host_serving` blamed the webhook path inside the branch that had already proved the path
  answered**, and sent the operator to `op=inventory`, which reads the WEB host's loopback. Rewritten:
  row age with the 90-minute bound first, `inngest-host-state.sh` first, the `op=inventory` caveat
  stated. `wrong_host` no longer says "the host is not the problem" (a dedicated host absent > 24 h
  while web hosts emit lands there); `fsm_silent` names its three inputs and the 15-minute
  re-dispatch; `stale_row` names E14; the E13 `flag_unreadable` message no longer quotes the lib's
  `__UNREADABLE__` sentinel as if it were the flag; `*)` prints both read rcs as 2.0 does. The
  staleness bound is 90 minutes everywhere (lib `max_row_age=5400`), not 60.
- **`webhook_path` for a 500 whose body is the hook's own `FATAL … errors=[…]`** (the host ANSWERED
  `/v0/gql` with a GraphQL error) was attributed to the hook; the message now discriminates on the
  body's `inngest-registry-probe: FATAL` prefix before naming the path. (observability seat.)
- **The 200-path REGISTERED warning said "Pre-cutover this is UNEXPECTED" on every healthy
  post-cutover run.** AC9's pin is now a verbatim heredoc (the `origin/main` comparison is
  `main == main` after merge and measured RED with HEAD standing in for main), and the one intended
  change it carries is the cutover-state qualifier.
- **Guard Contract realised in full.** The branch shipped M2.1–M2.5 and M2.10 only. Added: M1.1,
  M1.2, a same-line second call (the census now counts OCCURRENCES, not lines), M2.6 (with row ages
  normalised — the 2x2 headlines interpolate the age and a mutant survived 1 run in 3 on a second
  boundary), M2.7, M2.8, M2.9 and its nested-`$(gh …)` sibling (the echo-arg emptier now refuses to
  empty a string carrying `$(` or a backtick), H2 (`aborted`/`aborted` must-PASS), H3. Every token
  the case handles now has a render (host_serving, wrong_host, stale_row, stale_schema, both
  `flag_unreadable` cells, `unreadable`/`fsm_unreadable` at rc 0, the heartbeat read-failure leg);
  the `>= 10 exit 1` and `no-SSH >= exits` aggregates are replaced by a per-arm row over tokens + `*)`
  (the aggregates had one line of slack — `host_serving` could lose its `exit 1` green). Test
  Scenario 19's "≥ 10 `exit 1`" is superseded by that row; Scenario 16's `RUNNER_TEMP` is now
  `TMPDIR` (`mktemp -d -t`). Both region markers are asserted exactly-once and the end marker must
  be the arm's last line before `;;`. Negated rows over the region views use herestrings (the
  `producer | grep -q` form under pipefail measured a 1-in-8 false verdict).
- **The suite could not run on the PR shape every remedy edit takes.** `infra-validation.yml`'s
  path filter listed `.github/workflows/cutover-inngest.yml` but not `scripts/cutover-inngest.sh`,
  the gate lib or the read classifier (the three files the suite reads since ADR-150), so an
  arm-only PR skipped its own guard. Added. (coverage consult.)
- **Runbook.** The read recipe grepped `::notice::`, which the runner renders as `##[notice]` —
  zero matches on a real run (run 34948634783); now `grep -F 'registry-probe'`, and the two sibling
  2.0 recipes accept both spellings. The "group's in-flight run" pointed at the watchdog, which runs
  in its own group; it now lists the group's workflows and names all four members. The P1-6
  widening was gated **pre-arm only** — post-cutover `registry_empty=false` is the healthy state and
  the section's remedy replaces the production scheduler host. A displaced run shows `cancelled`,
  not red.
- **D3's `SOLEUR-DEBT:` marker** was claimed and absent; it is now at the arm's head with the
  third-consumer trigger, and the `(:1402-1530)` line citation is a content anchor.
- **Observability `discoverability_test`** failed Check 10 both as parsed (YAML escapes reached
  `bash -c` unresolved) and as intended (the arm's own comment sat inside the awk range and printed
  2); replaced by a block scalar anchored on the assignment form (`RPG_VERDICT=.*inngest_execute_registry_gate` — the `$(` form is a shell-active token Check 10's Step 10.5 rejects before running).
