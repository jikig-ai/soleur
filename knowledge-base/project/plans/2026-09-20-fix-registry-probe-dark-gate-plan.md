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

## Research Insights

### Premise Validation (Phase 0.6)

- **#8079 is OPEN** (`gh issue view 8079 --json state` → `OPEN`; labels `type/bug`,
  `priority/p2-medium`, `domain/engineering`; `closedByPullRequestsReferences: []`).
- **#8054 is CLOSED**, and its artefact exists: `inngest_execute_registry_gate()` at
  `tests/scripts/lib/inngest-host-dark-gate.sh:1149`, E-table header from `:988`. Read, not assumed.
- **The arm exists with the shape the issue describes**: `registry-probe)` opens at
  `scripts/cutover-inngest.sh:821`, the next arm (`doublefire-probe)`) at `:864`.
- **The 2.0 reference region exists**, delimited by `# ---- 2.0 empty-registry pre-flight (P1-6)`
  and `# ---- 2.1 capture` (~`:1392`-`:1560`).
- **STALE — the pre-arm framing.** See `## Premise Correction`.

Capability claims verified rather than asserted (`hr-verify-repo-capability-claim-before-assert`):

- **No new credential or workflow change is needed.** `.github/workflows/cutover-inngest.yml`
  injects `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}` UNCONDITIONALLY for every op; only
  `DOPPLER_TOKEN_INNGEST_ARM` and `environment:` are op-gated. `Checkout` and `Install Doppler CLI`
  are likewise ungated. So the gate's Better Stack reads already have what they need.
- **`_bs_query_rows` (`:110`) and `_bs_read_remedy` (`:130`) are defined at script top level**,
  before `case "$OP" in` at `:790`, so both are in scope from the `registry-probe)` arm.
- **`restart-inngest-server.yml` is the WRONG remedy for a dead dedicated host.**
  `scripts/inngest-host-state.sh`'s header records, measured 2026-09-17 over 12 consecutive
  attempts, that the `/hooks` channel terminates on web-1 and the dedicated host runs no listener —
  and that `restart-inngest-server.yml` reads that same endpoint, "which is why its verify step
  failed against a host it never reached". The no-SSH instruments that DO reach the dedicated host
  are `scripts/inngest-host-state.sh` (read), `scheduled-inngest-health.yml` (the probe-stream
  consumer) and `apply-web-platform-infra.yml -f apply_target=inngest-host-replace` (repair).

### Property List (Phase 0.6b)

- **P1** — A non-200 from `op=registry-probe` produces a graded verdict naming what is and is not
  established about `10.0.1.40`, instead of one opaque HTTP line.
- **P2** — A verdict derived from host rows can never be read as the live measurement
  `registry_empty=true`.
- **P3** — Every refusal carries a remedy the operator can perform without SSH, phrased for a
  standalone read-only probe dispatched OUTSIDE any maintenance window.
- **P4** — Post-cutover, a dedicated host that has stopped answering is diagnosed as such, not as
  "the cutover already completed".
- **P5** — Adding a second consumer of the gate does not weaken the existing assertion that no
  unaccounted third consumer exists.
- **P6** — `op=execute` 2.0's behaviour is unchanged in what it prints.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | What already covers it → cut |
|---|---|---|
| A second gate entry point for the probe | P1/P3 | `inngest_execute_registry_gate` grades the same host, the same rows, the same 11 tokens. **CUT** — reuse. |
| A post-cutover flag partition in the LIB (making `done` a pass class) | P4 | The emit file already carries `flag` and `hb_flag`, so the CALLER can discriminate `done` from `armed`/`flipping`/`flushed` inside its own `flag_armed)` arm. Changing `_erg_flag_class` would change 2.0's and the recut gate's semantics. **CUT** — branch in the caller (**D8**). |
| New `--since` / freshness operands tuned for a standalone probe | P1 | The gate owns freshness (`--max-row-age` 5400 s, `--hb-max-age` 900 s); the caller's windows only have to be WIDER. 24h/30m already are. **CUT** — reuse verbatim. |
| A workflow change to inject Better Stack credentials | P1 | Already unconditional (verified above). **CUT.** |
| Hoisting the shared mechanism out of both arms into one helper | none in the list | **CUT** — see **D3**. |
| A shared, op-parameterised remedy printer | P3 | The remedies' value is that they are op-specific; a shared printer emits "re-dispatch op=execute" from a probe run — the #6617 dead-remediation defect. **CUT.** |

### Value-Proposition Measurement (Phase 0.6c)

Not applicable — the justification is correctness and operability, not a cost or latency saving.
No saving is claimed anywhere in this plan.

### Relevant code anchors

| Path | Anchor | Why |
|---|---|---|
| `scripts/cutover-inngest.sh` | `registry-probe)` (`:821`-`:863`) | the change site |
| `scripts/cutover-inngest.sh` | `# ---- 2.0 empty-registry pre-flight (P1-6)` … `# ---- 2.1 capture` | the reference to mirror |
| `scripts/cutover-inngest.sh` | `:1434` (2.0 `webhook_path`), `:1515` (2.0 `host_serving`) | the two self-referential strings this change makes ambiguous (**D9**) |
| `scripts/cutover-inngest.sh` | `_bs_query_rows()` `:110`, `_bs_read_remedy()` `:130` | shared readers; the latter hardcodes `2.0` in 8 messages |
| `tests/scripts/lib/inngest-host-dark-gate.sh` | `inngest_execute_registry_gate()` `:1149`; `_erg_flag_class()`; E-table `:988` | the gate, its 11 tokens, and the `preflip`/`armed` partition |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | `#6617` block `:1230`-`:1290`; `FLQ_SITES` `:1050`; `#8054` block `:1866`+; `render_2_0()` `:2032`; `mutate_file()` `:2170`+; `_EXACT_FLOOR=665` | every assertion this change touches |
| `apps/web-platform/infra/inngest-registry-probe.sh` | `run_probe()`, the `__FETCH_FAILED__` literal | producer of the admission signature |
| `scripts/inngest-host-state.sh` | file header | why `restart-inngest-server.yml` is the wrong remedy |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-11-the-gate-i-built-for-a-dark-host-was-blind-to-the-byte-shape-of-nothing.md`
  — the #8054 learning. The render harness must extract the REAL `_bs_query_rows` /
  `_bs_read_remedy` from the script and stub the PROCESS (`doppler`), never the function under the
  seam; an HTTP error body must never be echoed (a 403 body carries `BETTERSTACK_QUERY_USERNAME`);
  `grep -c .` not `grep -c ''` (empty vs one blank line).
- `.../2026-09-13-the-mock-that-answered-in-one-line-certified-a-constant-and-my-beacons-stdout-was-the-secret.md`
  — a uniform stub certifies a constant. Every new render fixture must discriminate a failure
  CLASS, not merely produce output.
- `.../2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`
  — names this suite's `_EXACT_FLOOR` directly: it has already conflicted at merge. **Re-derive it
  from the suite's own failure message and measure; never increment by guess.** A mutant that
  exits non-zero with no `FAIL` line is UNRESOLVED, not KILLED.
- `.../2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`
  — a copy-adapted gate block dropped one line and shipped permanently red. **Parity-pin the
  copied half** (**D10**).
- `.../best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md`
  and `.../2026-04-19-enoent-on-optional-mount-should-not-alarm.md` — alarming on a structurally
  expected state drowns signal; an expected absence is not a degraded fallback. Supports **D1**.
- `.../best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md`
  — the converse: an exit 0 must still carry the discriminating verdict on stdout. Supports **D2**.
- `.../2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md` — a gate
  whose reassuring branch was unreachable from the real producer. Directly relevant: **D1**'s `dark`
  branch is now reachable only under a preflip flag, and the plan says so rather than pretending
  otherwise.
- `.../best-practices/2026-09-17-awk-word-boundary-backslash-b-is-backspace.md` and
  `.../2026-05-13-plan-verify-reducer-case-arms-with-grep-not-read-first-n.md` — the arm extractor
  must be proved to select exactly the intended arm; add a control that it does not also match a
  neighbouring arm or a `registry-probe-*` prefix.

### CLAUDE.md / AGENTS.md conventions that bind

`hr-no-ssh-fallback-in-runbooks` (every remedy, no exceptions), `hr-observability-layer-citation`
(see `## Observability` — layer 6), `cq-write-failing-tests-before`,
`cq-assert-anchor-not-bare-token` and `cq-cite-content-anchor-not-line-number` (every new assertion
anchors on a syntactic construct), `hr-verify-repo-capability-claim-before-assert`,
`wg-when-deferring-a-capability-create-a` (this issue exists because #8054 deferred it once).

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Reality, verified | Plan response |
|---|---|---|
| "P1-5 keeps the host dark on every pre-arm flag, so the op is unrunnable pre-arm" | The cutover completed 2026-09-15; flag `done`, host serving, 70 functions registered, probe returns 200 | Re-scoped in place — see `## Premise Correction`; design effort moves to `flag_armed`/`host_serving` |
| "so a dark host reports the gate's token and remediation" | `dark` requires a `preflip` flag (`aborted`/`rolled-back`), i.e. only after `op=rollback` | `dark` is still implemented and still exits 0 (**D1**), but is documented as the rollback-only branch |
| "`inngest_execute_registry_gate` lands with #8054" | Landed; #8054 CLOSED | Actionable now |
| "Add the corresponding wiring assertion" (singular) | A second call site collides with **seven** existing assertions across three blocks (`#6617` ×4, `FLQ_SITES`, the `#8054` consumer count, `mutate_file`'s known-negative) | All seven are extended deliberately — **D7**, **D4** |
| Implied: the probe arm is a copy of 2.0 | 2.0 is a pre-flight on a mutating sequence, inside a window this arm never runs in; its remedies terminate in mutating ops | Remedies are re-authored, not copied (**D8**, **D5**) |
| Implied: `_bs_read_remedy` is reusable as-is | It hardcodes `2.0` in all 8 messages | Parameterised (**D4**) |

## Decisions

### D1 — a `dark` verdict EXITS 0, with a notice plus a warning

**Decision.** In the `registry-probe)` arm the token `dark` exits 0; every other token exits 1.

**Why this is not simply copying 2.0.** For 2.0 the property is "the dedicated host carries no
registry that could double-fire", and a host that CANNOT START satisfies it *more strongly* than a
host that answered empty — so `dark` is a genuine pass. For the standalone probe the operator asked
"has an SDK registered functions against `10.0.1.40`?", and darkness answers a strictly weaker
proposition: *nothing can have completed a registration against this host since this boot, because
its server has not been bound on this boot.* It measures no registry contents — the gate's E12 in
fact REQUIRES `registry_fns=__UNREADABLE__` on a dark row, so there is no count to report.

**Why 0 and not a distinct non-zero token.** Three reasons, re-grounded for the post-cutover world:

1. **The arm's own convention.** Its FINDINGS — including the worst one it can deliver,
   `registry_empty=false` ("an SDK has registered against the dark host") — are annotations at
   exit 0; a non-zero exit means "the probe could not run". Making a *deliberate rollback state*
   the one exit-1 finding would invert that.
2. **`dark` is now reachable only under `aborted`/`rolled-back`** — i.e. the operator has just run
   `op=rollback` and put the host in that state on purpose. Red on a state the operator created
   deliberately, one minute earlier, is noise.
3. **Nothing downstream consumes this exit code as a gate.** `op=registry-probe` is
   `workflow_dispatch`-only and read-only; the flip is gated by 2.0, which runs the gate itself.
   *Caveat, and it is a real one:* the exit code IS consumed by human remedy text inside 2.0 —
   which **D9** fixes in this same PR.

**The cost, and how D2 pays it.** A green run has the same shape as a green run that measured
`registry_empty=true` live. That confusion is the real risk and is killed in the MESSAGE, not the
exit code: an exit code has two values and cannot carry the distinction; a message can.

### D2 — the dark path never emits the live-measurement triple

**Decision.** The strings `registry_empty=`, `function_count=` and `ids=[` are RESERVED for the
live HTTP-200 measurement. The dark path emits a structurally different pair:

- `::notice::registry-probe DARK-HOST VERDICT — …` carrying the gate's evidence (`boot_id`, probe
  row age, `flag`, heartbeat age, `hb_flag`), every field read from `--emit-file`, never from a raw
  row;
- `::warning::registry-probe: the dedicated host's registry was NOT read live …` written as a
  **greppable proposition pair**, not prose — the literal substrings `ANSWERED:` and
  `NOT ANSWERED:` each introduce one clause, so a reviewer (and an assertion) can find both halves:
  `ANSWERED: nothing can have registered against 10.0.1.40 since boot <id> — its inngest-server has
  not been bound on this boot.` / `NOT ANSWERED: what the registry holds; registry_empty was not
  measured.` Followed by the follow-up that WOULD answer it (`op=doublefire-probe`, which proves
  the harm itself rather than a proxy for it; or re-dispatch once the host is serving).

A warning rather than a second notice: it is the strongest instrument that makes the caveat visible
in the run summary without turning a correct run red, and it fires only on the dark path.

Enforced mechanically: an assertion pins that the dark region contains none of the three reserved
strings, and a mutation row proves that assertion reddens.

### D3 — duplicate the mechanism into the probe arm; do NOT hoist it out of 2.0

The `mktemp -d` + `trap`, the two `_bs_query_rows` reads, the `: > "$RPG_EMIT"` pre-touch, the
`|| RC=$?` call shape and the emit-file read loop are duplicated rather than factored into a shared
helper. Six existing assertions grep those literals INSIDE the awk-extracted `$EXEC_ARM_FILE`
(private-mktemp/trap; "exactly two Better Stack reads"; the two-terms row; both-reads-capture-stderr;
the emit-regex row; the ERG-assignment census). Hoisting reddens all six and forces re-authoring the
P0 cutover gate's suite as collateral of a P2 fix. The lib — where the judgement lives — is already
shared; what is duplicated is plumbing. **D10** adds the drift guard that makes this safe.

### D4 — `_bs_read_remedy` gains a leading `<step>` parameter

It hardcodes the literal `2.0` in all 8 `::error::` lines; called unchanged from the probe arm it
would report a step of an op the operator never ran. Signature becomes
`_bs_read_remedy <step> <label> <rc> <errfile> <rowsfile>`; 2.0's two call sites pass `"2.0"`, the
probe arm's pass `"registry-probe"`. The exec arm's output is therefore byte-identical, and the
existing renders pinning `^::error::2\.0 probe read: …` / `… heartbeat read: …` stay green
unchanged — which IS the proof that the refactor is behaviour-preserving.

**Collateral, same edit:** the doc-comment line `# _bs_read_remedy <label> <rc> <errfile>
<rowsfile> — …` changes, and `mutate_file`'s known-negative row is anchored on exactly that
literal. Un-updated, `mutate_file` reports "the mutation matched NOTHING … the line drifted", the
suite fails, and — worse if that were ever tolerated — the harness's only self-test silently becomes
a no-op. Its `sed` pattern is updated in the same commit.

### D5 — remedies never terminate in a mutating op without an explicit window qualifier

2.0's remedies legitimately end in `op=execute` (capture + quiesce), `op=resume` and `op=rollback`
(reviewer-gated prod writes) because 2.0 runs INSIDE a maintenance window. `op=registry-probe` is
dispatched outside one. Every remedy in this arm therefore ends at a READ, and may name a mutating
op only behind the literal qualifier `Only if you are opening the cutover window now:`. This is the
#6617 dead-remediation discipline applied to its inverse — a remedy the operator *can* perform but
*should not*.

### D6 — the `webhook_path` remedy names `op=inventory`

2.0's `webhook_path` remedy tells the operator to dispatch `op=registry-probe` to discriminate a
path fault from a host state; inside this arm that is self-referential. The probe arm names
`op=inventory` instead — a sibling GET through the SAME webhook path (`$BASE/inngest-inventory`,
same HMAC-over-empty-body + CF-Access headers), so a 200 from it isolates the fault to the
`inngest-registry-probe` hook while a non-200 confirms the path (CF Access / WAF /
`webhook.service` on the web host). No SSH on either branch.

### D7 — every colliding assertion is EXTENDED, never loosened

Seven assertions across three blocks interact with a second call site. Each is re-aimed at the
property it was protecting, and each re-aiming gets a mutation row proving the new form still
reddens on a real violation.

| # | Assertion (current form) | Why it breaks / interacts | Extension |
|---|---|---|---|
| 1 | `#8054 no other arm sources or calls the gate` — `grep -c 'inngest_execute_registry_gate' "$BODY_SH" -eq 1` | a second call site makes it 2 | Replaced by a **per-arm census DERIVED from the script's own arm enumeration** (`^  [a-z-]+\)$`): exactly 1 in `execute)`, exactly 1 in `registry-probe)`, **0 in every other arm**, plus a dispatch floor of ≥ 12 arms. Bumping to `-eq 2` would keep the number and lose the property. |
| 2 | `#6617 probe arms make exactly 2 network/tool calls` (`curl\|wget\|nc\|…\|gh\|doppler\|…` in the combined registry-probe + doublefire-probe region over `$WF`) | the per-token remedies contain `gh workflow run …` / `gh run list …` **inside `echo "::error::…"` strings** | The regex conflates *a tool named in an operator remedy* with *a tool invoked*. Re-aim at INVOCATIONS: strip comments AND strip `echo "::(error\|notice\|warning)::…"` lines before counting. Keep the count at 2, keep `-X GET` / `--max-time` at 2. |
| 3 | `#6617 probe arms add NO retry loop` (`! grep -qE '^[[:space:]]*(for\|while\|until)[[:space:]]'`) | the emit-file read is a line-start `while IFS= read -r …` | The property is "no TRANSPORT retry". Re-aim: no loop whose body contains `curl` or `_bs_query_rows`. Stated structurally it is strictly stronger than the keyword ban it replaces. |
| 4 | `#6617 probe arms touch NO flip/quiesce/rearm hook` (`! grep -qE 'inngest-(arm\|flip\|quiesce\|rearm\|wiped)'`) | the heartbeat read's `--grep` term is the LOG TAG `inngest-cutover-flip` | The property is "invokes no mutating HOOK". Re-aim the anchor at the hook-path shape (`$BASE/inngest-…` / `hooks/inngest-…`), which is what "hook" means; a log tag passed to a read is not one. |
| 5 | `#6617 probe arms invoke NO doppler at all` | survives only while no remedy TEXT names the tool; `_bs_query_rows` hides the token | Re-aim at the real property: **no Doppler secret-WRITE invocation** (the write verb, never `run`) and no bare Doppler invocation outside `_bs_query_rows`. Keep the wget/nc/socat and request-body denials untouched. |
| 6 | `FLQ_SITES` — `the shared reader has exactly 6 call sites (…)` | two new `_bs_query_rows` sites → 8 | Raise to 8 **and extend the enumerating message** to name the two new sites, or the single-chokepoint row stops being readable. |
| 7 | `mutate_file "known-negative"` sed, anchored on `_bs_read_remedy`'s doc-comment | **D4** changes that line | Update the pattern in the same commit (see **D4**). |

### D8 — `flag_armed` and `host_serving` get NEW semantics, not reworded ones

This is where the re-scope lands. The emit file already carries `flag` and `hb_flag`, so the caller
can discriminate inside its own `flag_armed)` arm without touching the lib:

- **`flag_armed` with `flag`/`hb_flag` == `done`** — the cutover is COMPLETE and the dedicated host
  is not answering. Since 2.4 repointed `INNGEST_BASE_URL`, that means **production cron scheduling
  may be down**. Remedy, no-SSH, in order: read the host directly
  (`doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh`); read the latest
  `scheduled-inngest-health.yml` run; if two consecutive readings agree the host is dead,
  `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason=<why>`.
  **It must NOT say "the cutover already completed: dispatch op=verify".** And it must NOT name
  `restart-inngest-server.yml` — that reads `/hooks/deploy-status`, which terminates on web-1 and
  structurally cannot reach this host (measured 2026-09-17, 12/12).
- **`flag_armed` with `armed`/`flipping`/`flushed`** — a cutover sequence is in flight. Remedy: read
  that run; dispatch nothing. (`flushed` may name `op=resume` only behind **D5**'s qualifier.)
- **`host_serving`** — the row says the host IS serving while the webhook returned non-200: the row
  and the webhook disagree, which post-cutover most often means the WEBHOOK path, not the host.
  Remedy: `op=inventory` to test the path (**D6**), then `scripts/inngest-host-state.sh` to settle
  the disagreement. No mutating op.
- **`silent`** — 2.0's remedy escalates, after two readings, to `inngest-host-replace`. That
  escalation has a known false positive: on 2026-08-14 the Better Stack Logs quota exhausted and
  **ingest returned HTTP 402 for ~49 h while the read path kept answering 200**, which presents as
  rows-absent-but-read-healthy — exactly `silent`. Both this arm's `silent` remedy **and 2.0's**
  gain one clause: confirm Better Stack ingest health/quota before treating silence as a dead host.
  (One sentence in an existing string; fixing it only in the new arm would leave the P0 path with
  the sharper edge, and `wg-defer-only-after-inline-triage` does not permit deferring a one-line
  fix already triaged.)

### D9 — the two self-referential strings inside 2.0 are corrected in this PR

`op=registry-probe`'s exit status is already consumed as a two-valued discriminator by remedy text
inside 2.0. This change makes it three-valued (live-200 / green-dark / refused), so both strings
become wrong on the same day the arm changes:

- `scripts/cutover-inngest.sh:1434` (2.0 `webhook_path`): *"Check the path first: gh workflow run
  cutover-inngest.yml -f op=registry-probe … when it returns the `__FETCH_FAILED__` refusal or
  HTTP 200, re-dispatch op=execute."*
- `scripts/cutover-inngest.sh:1515` (2.0 `host_serving`): *"If that returns 200 the host IS serving
  pre-arm."*

Both are amended to key on the LIVE marker rather than on the run's colour: *"if that run prints a
`registry_empty=` line, the host IS serving."* This keeps the existing assertion's
`REFUSED \(webhook_path\).*op=registry-probe` match intact (the op is still named) while removing
the inference that a green probe run means a serving host.

### D10 — a cross-arm token-set parity assertion makes the accepted duplication safe

Duplicating an 11-token `case` creates exactly the drift the shared-reader chokepoint row exists to
prevent: a 12th token added to the lib could be handled in one arm and silently fall to `*)` in the
other. One assertion closes it — extract the handled token set from EACH arm's `case`, `sort -u`,
and require both to equal the token set derived from `inngest_execute_registry_gate`'s own function
body. Three-way equality, one row, and it is the only thing that makes **D3** safe.

### D11 — the probe arm uses an `RPG_*` variable prefix

`RPG_DIR`, `RPG_EMIT`, `RPG_VERDICT`, `RPG_RC`, `RPG_PROBE_RC`, `RPG_HB_RC`, `RPG_FLAG`, `RPG_BOOT`,
`RPG_ROW_AGE`, `RPG_HB_AGE`, `RPG_HB_FLAG`. Only one arm runs per dispatch, so this is not about
collisions: it keeps every existing `ERG_*`-anchored assertion unambiguously exec-arm-scoped by
construction, and makes the new file-global probe-arm assertions anchorable without extraction
fragility.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `op=registry-probe` is
operator-dispatched, read-only, and gates nothing. The realistic path to user harm is indirect.
Post-cutover, `10.0.1.40` is the only cron scheduler, so a non-200 from this probe can mean every
scheduled job is down; a remedy that misdirects the operator there (2.0's "the cutover already
completed: dispatch op=verify" — the exact string **D8** forbids) lengthens an outage in which no
reminder email, no SLA sweep and no billing cron fires. The outage itself is always caused
elsewhere; this arm can only shorten or lengthen the diagnosis.

**If this leaks, the user's data is exposed via:** a PUBLIC repository's run log. Two concrete
vectors, both already live on the 2.0 path and carried forward verbatim: (1) the Better Stack read's
credentials enter via `doppler run` INSIDE the reader, so GitHub's secret masking never sees them,
and a ClickHouse 403 body is `Code: 516. DB::Exception: <BETTERSTACK_QUERY_USERNAME>:
Authentication failed…` — half of the Basic-auth pair; (2) raw journald probe rows carry host
internals. Mitigations asserted for the probe arm exactly as for 2.0: the gate's stdout is one
token, every printed field comes from `--emit-file` behind a shape regex, row files live under a
`mktemp -d` (0700) removed on `EXIT`, the HTTP error body is never printed (only its length and a
two-way classification), and no annotation may interpolate `RPG_PROBE_ROWS` / `RPG_HB_ROWS` /
`BODY` / `CAUSE`.

**Brand-survival threshold:** aggregate pattern

Rationale, with the counter stated so a reviewer can overrule it: no single dispatch of a read-only
diagnostic produces a user incident on its own, and the mutating path has its own independent gate
(2.0). The counter is that post-cutover this arm sits on a production-outage diagnosis path, which
argues for `single-user incident`; it is not adopted because the harm is *diagnosis latency during
an incident caused elsewhere*, which compounds across occurrences rather than materialising in one.
No per-PR CPO sign-off is therefore required.

## Open Code-Review Overlap

Checked 2026-09-20 against 65 open `code-review` issues by substring match of each planned file
path against every issue body (two-stage `gh issue list --json` → standalone `jq --arg`):
`scripts/cutover-inngest.sh` — none; `apps/web-platform/infra/cutover-inngest-workflow.test.sh` —
none; `tests/scripts/lib/inngest-host-dark-gate.sh` — none;
`apps/web-platform/infra/inngest-registry-probe.sh` — none.

**None.** Nothing to fold in, acknowledge or defer.

## Files to Edit

1. **`scripts/cutover-inngest.sh`**
   - `_bs_read_remedy()` (`:130`): leading `<step>` parameter; 8 `2.0 ` prefixes → `$step `;
     doc-comment signature line (**D4**).
   - The two `_bs_read_remedy` call sites in `execute)`: pass `"2.0"`.
   - `:1434` and `:1515`: amend the two self-referential strings (**D9**).
   - 2.0's `silent)` remedy: add the Better Stack ingest/quota clause (**D8**).
   - The `registry-probe)` arm (`:821`-`:863`): the dark branch, plus region-delimiter comments.
2. **`apps/web-platform/infra/cutover-inngest-workflow.test.sh`** — the seven extensions of **D7**,
   the **D10** parity row, the probe-arm static rows, the probe-region renders, the mutation rows,
   `render_2_0` → `render_arm_region`, and `_EXACT_FLOOR`.
3. **`knowledge-base/engineering/operations/runbooks/inngest-server.md`** — three edits, located by
   reading rather than guessing. **§ "Cutover procedure" (`:885`) is NOT one of them** — that
   section is the same-host durable-backend cutover and never mentions this op.
   - **(a) `~:1075-1083`**, § "Dedicated-host cutover" → "Window procedure", item 1(a): "The first
     `op=execute` must have passed 2.0 … Read it from that run" — add `op=registry-probe` as the
     cheaper route to the same reading without dispatching a capture+quiesce op, plus one sentence
     on the shared `deploy-inngest-restart` concurrency group (the dark path's extra ~2 minutes can
     queue a deploy behind a probe fired just before a window).
   - **(b) `~:453-457`**, § "Cutover pre-flight-hang triage" item 3, after "Do NOT read a
     `registry_empty` halt as a pre-flight hang": add the companion — a standalone
     `op=registry-probe` that exits 0 **without** a `registry_empty=` line is the dark-host verdict,
     not a live measurement.
   - **(c) `:1657`**, § "2.0 registry-non-empty remediation (P1-6)": widen the opening clause so an
     operator who hits the non-empty verdict from the STANDALONE op also finds the remediation.
   - Optional, free: `.github/workflows/cutover-inngest.yml:15-16` points readers at § "Cutover
     procedure" for ALL ops, which is already mildly wrong.

## Files to Create

None.

## Implementation Phases

### Phase 0 — verify live state, probe capacity, record the baseline

1. **Re-confirm the corrected premise against live state before writing code** — the ADR addenda
   are 1-5 days old and this plan's whole shape depends on them:
   `doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh`. Expect
   `cutover_flag=done`, `server_active=active`, `http_code=200`. If it disagrees, STOP and re-read
   `## Premise Correction` before proceeding — **D8**'s remedies are written for `done`.
2. `bash scripts/test-all.sh --capacity`. If it refuses (rc=4, a sibling full-gate run in flight),
   do NOT claim a full gate later; run the diff's suites plus the four repo-global ratchets and say
   so in the PR body.
3. Baseline: `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` (expect the dispatched
   count to equal `_EXACT_FLOOR`, currently 665) and
   `bash apps/web-platform/infra/inngest-registry-probe.test.sh`.
4. `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
   — record it clean BEFORE the change so any later finding is attributable.

### Phase 1 — the shared-helper parameterisation (D4), landed alone

Re-read the function and its doc comment first (`hr-always-read-a-file-before-editing-it`).

1. Add `<step>`; replace the 8 `2.0 ` literals with `$step `; update the doc-comment signature.
2. Update the two `execute)` call sites to pass `"2.0"`.
3. Update `mutate_file`'s known-negative `sed` pattern to the new comment text.
4. Run the workflow suite. It MUST be green at 665 with no count change: the `FAILREAD_OUT` /
   `AUTHFAIL_OUT` renders pin `^::error::2\.0 probe read: …` against the REAL extracted function,
   so that green IS the proof the refactor is behaviour-preserving.

### Phase 2 — the 2.0 text corrections (D9, and D8's `silent` clause)

1. Amend `:1434` and `:1515` to key on the `registry_empty=` marker rather than on the run's colour.
2. Add the Better Stack ingest/quota clause to 2.0's `silent)` remedy.
3. Re-run the suite: the `webhook_path` render pins only the prefix and `.*op=registry-probe`, and
   the `silent` render pins only `^::error::2\.0 REFUSED \(silent\)`, so both should stay green. If
   either reddens, the assertion — not the string — is the first thing to look at.

### Phase 3 — the registry-probe dark arm

Re-read `scripts/cutover-inngest.sh:821-863` and the 2.0 region before editing.

1. Leave the arm's preamble (`SIG`, `rm -f`, `curl`, `BODY`) unchanged.
2. Replace the non-200 branch with, in order:
   - `# ---- registry-probe DARK ARM (#8079)` region-open marker;
   - the `webhook_path` pre-refusal —
     `if [[ "$CODE" != "500" || "$BODY" != *"__FETCH_FAILED__"* ]]` → an `::error::registry-probe
     REFUSED (webhook_path)` naming `op=inventory` (**D6**), the CR/LF-stripped body once as a plain
     line, `exit 1`. **Before any Better Stack read.**
   - a `::notice::` recording that the 500 carries the host's fetch-failure signature, then the body
     once as a plain non-annotation line;
   - `source tests/scripts/lib/inngest-host-dark-gate.sh || { echo "::error::registry-probe: gate
     library … not found on this ref — dispatch with --ref main"; exit 1; }`;
   - `RPG_DIR=$(mktemp -d "${RUNNER_TEMP:-/tmp}/rpg.XXXXXXXX") || { … exit 1; }` **immediately**
     followed by `trap 'rm -rf "$RPG_DIR"' EXIT` — armed before any other statement that can write
     or exit;
   - the two reads, one `--grep` term each, windows verbatim from 2.0 (`24h`
     `SOLEUR_INNGEST_SERVER_PROBE` `500`; `30m` `inngest-cutover-flip` `200`), each capturing stderr
     to its own file and returning the query's rc into `RPG_PROBE_RC` / `RPG_HB_RC`;
   - `: > "$RPG_EMIT"` before the call (the gate truncates after argument parsing; a refusal inside
     the parser would otherwise abort under `set -e` before the `case` prints);
   - `RPG_RC=0` then `RPG_VERDICT="$(inngest_execute_registry_gate … --emit-file "$RPG_EMIT" --host
     "$INNGEST_HOST" --host-name "$INNGEST_HOST_NAME")" || RPG_RC=$?` — the `||` is load-bearing;
   - the sentinel-initialised emit read loop behind
     `^(flag|boot_id|row_age|hb_age|hb_flag)=([A-Za-z0-9_-]{1,64})$`. **Post-re-scope this loop is
     load-bearing rather than decorative:** `flag`/`hb_flag` are what let `flag_armed)` tell `done`
     from `armed` (**D8**);
   - `case "$RPG_VERDICT"` with all 11 tokens + `*)`:
     `dark)` → token-AND-rc agreement check, then the **D2** notice + warning, and NO exit;
     `flag_armed)` → the **D8** `done` / `armed|flipping|flushed` split;
     `host_serving)`, `silent)` → **D8**; `unreadable)` / `fsm_unreadable)` → branch on the read rc
     and call `_bs_read_remedy "registry-probe" probe|heartbeat …`; the remaining tokens → one
     remedy each; `*)` → sanitised (`${RPG_VERDICT:0:32}`, non-`[a-z_]` → `?`), naming the GATE as
     the defect. Every non-`dark` arm `exit 1`; every remedy ends `Do NOT SSH the host.` and obeys
     **D5**;
   - `# ---- registry-probe DARK ARM end` marker, placed so the extracted region is sourceable (it
     must not contain the arm's trailing `;;`).
3. Leave the HTTP-200 path — the `jq` shape check, `REG_EMPTY`/`REG_COUNT`/`REG_IDS`, the
   `registry_empty=/function_count=/ids=[]` notice and the `REG_EMPTY == false` warning — BYTE
   UNCHANGED.

### Phase 4 — suite extension

1. Rename `render_2_0` → `render_arm_region` (it already takes the region file as `$1`; 11 call
   sites + 3 comment mentions).
2. Apply the seven **D7** extensions, each with its mutation row.
3. Add the **D10** three-way token-set parity row.
4. Add the probe-arm static rows, the region extraction (with the control proving it selects exactly
   the intended arm and not a neighbour), the renders and the mutation rows.
5. Run the suite; read `_DISPATCHED` from its own failure message; set `_EXACT_FLOOR` to exactly
   that number with the itemised `665 -> NNN (+k)` comment the block's convention requires. **Never
   increment by guess** — that count has already conflicted at merge once.

### Phase 5 — runbook and gates

1. The three runbook edits (a)-(c), plus the optional workflow-header pointer.
2. Run and record verbatim:
   - `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`
   - `bash apps/web-platform/infra/inngest-registry-probe.test.sh`
   - `bash tests/scripts/test-inngest-host-dark-gate.sh` (the lib is untouched — a regression check)
   - `bash plugins/soleur/test/fixture-relative-assert.test.sh`
   - `bash scripts/guard-vacuity-floor.test.sh`
   - `bash scripts/lint-diagnosis-claims.test.sh`
   - `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
     (WITH `--baseline`; run bare it re-reports all 216 baseline entries as new. Fix new findings at
     the source by guarding the capture, in preference to appending to the baseline.)
   - `bash -n scripts/cutover-inngest.sh`, and `shellcheck scripts/cutover-inngest.sh` if available
     — this arm is only ever executed by a manual dispatch, so syntax has no other gate.
   The four ratchets reference no changed file and are invisible to file-based suite selection; they
   must be run BY HAND regardless of what `test-all.sh` selects.

## Acceptance Criteria

- [ ] **AC1** — a non-200 with the `__FETCH_FAILED__` signature and fixture rows establishing
      darkness completes rc 0 and prints both the DARK-HOST VERDICT notice and the caveat warning.
      Proven by a render, not by reading the diff.
- [ ] **AC2** — the dark path's output contains none of `registry_empty=`, `function_count=`,
      `ids=[`. Proven by a render assertion AND a mutation row that reddens it.
- [ ] **AC3** — the caveat warning contains the literal substrings `ANSWERED:` and `NOT ANSWERED:`,
      each introducing its clause, and names the follow-up op.
- [ ] **AC4** — `flag_armed` with flag `done` produces a PRODUCTION-OUTAGE remedy naming
      `scripts/inngest-host-state.sh`, `scheduled-inngest-health.yml` and
      `apply_target=inngest-host-replace`, and contains NEITHER "the cutover already completed" NOR
      `op=verify` NOR `restart-inngest-server`. Proven by a render with a `done` fixture.
- [ ] **AC5** — all 11 gate tokens have their own `case` arm in the probe arm; the handled token set
      is DERIVED from the gate's function body; and the exec arm's, the probe arm's and the lib's
      sets are three-way equal (**D10**).
- [ ] **AC6** — the gate call is `|| RPG_RC=$?`-guarded and a refusing fixture still prints its
      `::error::` (dynamic render; a bare `$(…)` under `set -e` is fail-closed but MUTE).
- [ ] **AC7** — a webhook 403, and a 500 WITHOUT `__FETCH_FAILED__`, both refuse as `webhook_path`
      with rc 1 and perform NO Better Stack read — against a positive control showing the read
      markers DO appear on the dark path.
- [ ] **AC8** — no remedy in the probe arm contains `ssh `; none names a mutating op (`op=execute`,
      `op=resume`, `op=rollback`, `op=arm`) except behind the literal qualifier `Only if you are
      opening the cutover window now:` (**D5**).
- [ ] **AC9** — the HTTP-200 path is byte-unchanged (pinned as CONTENT, as the existing AC7 pin does
      for 2.0) and performs NO Better Stack read.
- [ ] **AC10** — no probe-arm annotation interpolates `RPG_PROBE_ROWS`, `RPG_HB_ROWS`, `BODY` or
      `CAUSE`; every printed field comes from the emit-file read behind the shape regex.
- [ ] **AC11** — row files live under a `mktemp -d` (0700) under `RUNNER_TEMP`, the `EXIT` trap is
      armed immediately after the `mktemp -d` and before any other statement, no `umask` appears,
      and a refusing render leaves no directory behind.
- [ ] **AC12** — `op=execute`'s rendered output is unchanged: every existing `#8054` render and the
      AC7 content pin are green with **no edit to their expectations**.
- [ ] **AC13** — the consumer census holds: exactly 1 gate call in `execute)`, exactly 1 in
      `registry-probe)`, 0 in every other arm, ≥ 12 arms enumerated.
- [ ] **AC14** — all seven **D7** extensions are in place and each has a mutation row showing the
      re-aimed form still reddens on a real violation (a secret-write invocation, a `curl` inside a
      loop, a request to a mutating hook, a third consumer arm).
- [ ] **AC15** — 2.0's two self-referential strings key on the `registry_empty=` marker rather than
      on the run's colour (**D9**), and 2.0's `silent` remedy carries the ingest/quota clause.
- [ ] **AC16** — the three runbook edits are in place; § "Cutover procedure" (`:885`) is NOT edited.
- [ ] **AC17** — `_EXACT_FLOOR` equals the suite's actual dispatched count, raised in the same commit
      as the rows it guards, with the itemised `665 -> NNN (+k)` comment.
- [ ] **AC18** — every gate in Phase 5 is green and recorded verbatim; if `test-all.sh --capacity`
      refused, the PR body says so and does not claim a full gate.

## Guard Contract

### Guard 1 — the gate's consumer set

**Property.** In `scripts/cutover-inngest.sh`, `inngest_execute_registry_gate` is called from
exactly two of the script's `case "$OP"` arms — `execute` and `registry-probe` — and from no other
arm, now or after any future arm is added.

**Assembly.** The chokepoint is the script's single top-level `case "$OP" in`, whose arms are
enumerated STRUCTURALLY by `^  [a-z-]+\)$` and each extracted with the same `awk` range the suite
already uses for `execute`. The guard quantifies over that enumeration, not a list of two names, so
an arm added tomorrow enters the population automatically. The dispatch floor (≥ 12 arms) is part of
the assembly: an enumeration that collapsed to zero arms would otherwise satisfy "0 other arms call
the gate" vacuously.

**Mutation matrix.**

| # | Mutation (one line, pristine copy) | Must redden |
|---|---|---|
| M1.1 | Add a gate call to a THIRD arm (append it to the `enumerate)` arm's `BODY=$(cat /tmp/enum-body …)` line) | "0 gate calls in every other arm" — **the second-member row**: the census must not stop after the two compliant members |
| M1.2 | Rename the `registry-probe)` arm's call | "exactly 1 in `registry-probe)`" |
| M1.3 | Rename the `execute)` arm's call | "exactly 1 in `execute)`" — proves the census is not scoped to the new arm |
| M1.4 | Break the arm-enumeration anchor in the SUITE (`^  [a-z-]+\)$` → `^  ZZZ[a-z-]+\)$`) | the **dispatch floor** — a guard reporting "0 arms checked" and exiting 0 is vacuous |

**Harness rows.** M1.4 is the suite-side row (it edits the SUITE, not the SUT, and must drive it
RED). The must-PASS non-canonical input is Guard 2's H2, which shares this suite's dispatch.

**Anchor.** `_EXACT_FLOOR` is a stored count and survives any add-one-delete-one substitution, so it
is NOT the integrity anchor — the SET IDENTITY is. The census derives the arm set from the script
and the token set from the lib's function body, so weakening either requires editing the thing being
measured, which M1.1-M1.4 then redden. The floor's narrower role is stated as such: it catches
DELETION of rows, not substitution.

### Guard 2 — the probe arm's non-200 behaviour

**Property.** When and only when the webhook's non-200 carries the dedicated host's own
fetch-failure signature, `op=registry-probe` grades the host from its own rows; a `dark` verdict
exits 0 carrying the gate's evidence and an explicit statement that the registry was NOT read live;
every other verdict exits 1 having printed a remedy that is no-SSH, phrased for a standalone probe,
and — for `flag_armed` under `done` — describes a production outage rather than a completed cutover;
and no path prints a raw row, a credential-bearing body, or the live-measurement triple.

**Assembly.** The chokepoint is the extracted `registry-probe` dark region, delimited by its two
marker comments and EXECUTED in a fresh `bash` process by `render_arm_region`, with `curl` and the
`doppler` PROCESS stubbed and the REAL gate lib, the REAL `_bs_query_rows` and the REAL
`_bs_read_remedy` sourced from the script. The process boundary is load-bearing: bash disables
`errexit` inside an `if` condition or the left of `||`, so a subshell would render an un-guarded
mutant identically to the guarded original. The token population is the 11 tokens derived from
`inngest_execute_registry_gate`'s body, never a retyped list.

**Mutation matrix.**

| # | Mutation | Must redden |
|---|---|---|
| M2.1 | Drop `\|\| RPG_RC=$?` from the gate call | the DYNAMIC row: a refusing fixture must still print its `::error::` and exit 1, not die mute — **the render harness's own dispatch row** |
| M2.2 | Add `exit 1` to the `dark)` case | the dark render's rc-0 assertion — **pins D1** |
| M2.3 | Neuter the `webhook_path` test (`if [[ … ]]` → `if false`) | a 403 must refuse without any Better Stack read |
| M2.4 | Make the dark notice print `registry_empty=true` | the **D2** pin |
| M2.5 | Replace the `flag_armed` `done` branch's body with 2.0's "the cutover already completed: dispatch op=verify" | **AC4** — **pins D8**, the re-scope's central decision |
| M2.6 | Make the `*)` arm fall through (`echo …; exit 1 ;;` → `: ;;`) | "the `*)` arm exits 1 and names the gate as the defect" |
| M2.7 | **REORDER, not delete:** move `trap 'rm -rf "$RPG_DIR"' EXIT` from immediately after the `mktemp -d` to after the two reads | a render that refuses INSIDE the read window must leave no directory behind. A delete-only row reddens any suite that checks for the directory at all; only a MOVE tests the window the property is about, and the observation must be taken at a refusal occurring between the two positions |
| M2.8 | Add a Doppler secret-write invocation (the write verb, not `run`) to the probe arm | the re-aimed `#6617` no-secret-write row (**D7** #5) — proves the re-aiming did not simply delete a guard |
| M2.9 | Wrap the `curl` in a `for attempt in 1 2` loop | the re-aimed no-TRANSPORT-retry row (**D7** #3) |
| M2.10 | Point the region's `curl` at `$BASE/inngest-rearm-reminders` | the re-aimed no-mutating-HOOK row (**D7** #4) |

**Harness rows.**

- **H1 (must-FAIL fixture):** render with a probe row carrying `cutover_flag=armed` → must exit 1
  with `flag_armed`. A harness stubbed to always emit the dark notice, or a check that ignores rc,
  goes red here. This bounds a guard that would otherwise accept everything.
- **H2 (must-PASS, NOT the canonical):** render with `cutover_flag=aborted` on the probe row and
  `{"flag":"aborted","reason":"noop-aborted"}` on the heartbeat. `aborted` is the OTHER member of
  the gate's `preflip` allowlist, so the contract explicitly permits it; it must render rc 0 dark
  exactly as the canonical `rolled-back` fixture does. A guard that reddens here is over-fitted to
  its one fixture.
- **H3 (extraction control):** assert the probe-arm `awk` extractor selects exactly the intended arm
  — non-vacuous line count AND absence of a neighbouring arm's unique marker (the
  `doublefire-probe` arm's `CRON_PERIOD` token) in the extracted file.
- **H4 (existing, reused):** `mutate_file`'s known-negative — a comment-only mutation must be
  reported as NOT reddening. Its `sed` pattern is updated for **D4** in the same edit, and the suite
  fails loudly ("the line drifted") if that update is forgotten.

**Anchor.** The `__FETCH_FAILED__` admission literal is not retyped in the suite: it is DERIVED from
the producer (`apps/web-platform/infra/inngest-registry-probe.sh`) and required to equal the literal
the probe arm tests for, so a rename on either side reddens instead of silently refusing every
dispatch as `webhook_path`. The same derivation the exec arm already uses is extended to the probe
arm rather than duplicated as a constant. **D10**'s three-way token-set equality is the second
anchor: it ties both arms to the lib rather than to each other.

## Observability

Surface: `scripts/cutover-inngest.sh` executed by `.github/workflows/cutover-inngest.yml` on a
`workflow_dispatch`. There is no server-side runtime and no async sink; the operator's only
synchronous signal is the workflow run log. That is **observability layer 6** (synchronous
webhook-response body / workflow-run log), cited for every failure mode below.

```yaml
liveness_signal:
  what: "the ::notice::registry-probe DARK-HOST VERDICT / ::warning:: pair, or an ::error::registry-probe REFUSED (<token>) line, on the cutover-inngest workflow run"
  cadence: "per operator dispatch — workflow_dispatch only, by design (#6617: a diagnostic, not a scheduled probe)"
  alert_target: "the dispatching operator, via the run's annotations and the job's exit status (layer 6)"
  configured_in: ".github/workflows/cutover-inngest.yml (job `cutover`, step `Run cutover host op via webhook`)"
error_reporting:
  destination: "GitHub Actions run log + annotations (layer 6); the job turns red on every non-dark verdict"
  fail_loud: "yes — every non-dark token exits 1 after printing its remedy; the || RPG_RC=$? call shape exists so no refusal can be fail-closed-but-mute under set -e"
failure_modes:
  - mode: "the dedicated host has stopped answering while the flag reads done — production cron scheduling may be down"
    detection: "::error::registry-probe REFUSED (flag_armed) with flag=done (layer 6, workflow run log)"
    alert_route: "run turns red; the remedy names inngest-host-state.sh, scheduled-inngest-health.yml and apply_target=inngest-host-replace — never op=verify, never restart-inngest-server.yml"
  - mode: "a cutover sequence is in flight (flag armed/flipping/flushed)"
    detection: "::error::registry-probe REFUSED (flag_armed) with that flag value (layer 6)"
    alert_route: "run turns red; the remedy says read that run and dispatch nothing"
  - mode: "the row and the webhook disagree (host serving, webhook non-200)"
    detection: "::error::registry-probe REFUSED (host_serving) (layer 6)"
    alert_route: "run turns red; the remedy names op=inventory then inngest-host-state.sh"
  - mode: "the host emitted no probe row in the window"
    detection: "::error::registry-probe REFUSED (silent) (layer 6)"
    alert_route: "run turns red; the remedy checks Better Stack ingest health/quota BEFORE treating silence as a dead host (the 2026-08-14 402-for-49h precedent)"
  - mode: "the gate library is absent on the dispatched ref"
    detection: "::error::registry-probe: gate library … not found on this ref (layer 6)"
    alert_route: "run turns red; the message names --ref main"
  - mode: "the Better Stack read fails (credentials absent/rejected, transport, maintenance)"
    detection: "_bs_read_remedy prints an rc-classified ::error::registry-probe … read: line (layer 6); the HTTP error body is never printed, only its length and a two-way classification"
    alert_route: "run turns red; the remedy names the value-silent Doppler check, no SSH"
  - mode: "the webhook path itself is broken (CF Access 403, WAF 5xx, webhook.service down, 000)"
    detection: "::error::registry-probe REFUSED (webhook_path) (layer 6), emitted BEFORE any Better Stack read"
    alert_route: "run turns red; the remedy names op=inventory as the discriminating sibling dispatch"
  - mode: "the gate returns a token this arm does not recognise (a gate defect)"
    detection: "::error::registry-probe REFUSED: … unrecognised verdict '<sanitised>' (layer 6), printed with both rcs, never the raw stdout"
    alert_route: "run turns red; the message names the gate as the defect"
  - mode: "the host is dark under a preflip flag (a deliberate rollback)"
    detection: "::notice::registry-probe DARK-HOST VERDICT + ::warning:: … NOT ANSWERED: … (layer 6)"
    alert_route: "run stays GREEN by design (D1); the warning annotation is what makes the unanswered question visible in the run summary"
logs:
  where: "GitHub Actions run log for .github/workflows/cutover-inngest.yml"
  retention: "repository default for Actions logs (90 days)"
discoverability_test:
  command: "bash -c 'awk \"/^  registry-probe\\\\)\\$/{f=1;next} f&&/^  [a-z-]+\\\\)\\$/{exit} f\" scripts/cutover-inngest.sh | grep -c inngest_execute_registry_gate'"
  expected_output: "1"
```

The `discoverability_test` declares the smallest command that prints the signal, never the suite:
one `awk` plus one `grep` over a tracked file, no network, no credentials, milliseconds (well inside
preflight Check 10's 15 s cap), and a literal expected output of `1` rather than a sentence
describing it. `credentials_required` is omitted because an unauthenticated local probe verifies the
property.

### Soak / follow-through enrollment

Not applicable. No acceptance criterion and no `liveness_signal` here is time-gated — every
criterion is decided by a suite run at merge time, and nothing must hold for N days before an issue
closes. No `soleur:followthrough` directive is emitted; an enrollment for a non-existent soak would
be a directive nothing could satisfy.

## Follow-Through Directives

At ship time, post the `## Premise Correction` section to issue #8079 as a comment before the PR merges, so the issue's own thread records that its pre-arm framing was superseded by the 2026-09-15 cutover completion and that the fix was re-scoped in place rather than closed as overtaken.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (`soleur:engineering:cto`)
**Assessment:** Raised the stale-premise finding that re-shaped this plan (now `## Premise
Correction`), the `#6617` read-only-contract collisions and the `FLQ_SITES` collision (now **D7**
rows 2-6), the missing cross-arm token-set parity guard (now **D10**), and the known-negative `sed`
drift (now **D4** collateral). Endorsed **D1**'s exit-code convention without change, and asked for
the caveat warning to be a greppable proposition pair rather than prose (now **D2** and **AC3**).
Its one cut candidate — the five-field emit-file read loop — is explicitly NOT cut: the re-scope
turns it load-bearing, because `flag`/`hb_flag` are what let `flag_armed)` tell `done` from `armed`
(**D8**). Complexity estimate: medium, dominated by the test suite rather than the script.

### Operations

**Status:** reviewed (`soleur:operations:coo`)
**Assessment:** Confirmed no new credential or provisioning step and no new spend. Raised the two
self-referential 2.0 remedy strings (now **D9**), the remedy-escalation problem — a read-only probe
must not hand the operator a mutating op (now **D5**) — the reserved-triple widening (now **D2**),
and the Better Stack ingest-quota false positive behind the `silent` → host-replace escalation
(now **D8**). Located the runbook edits by reading: § "Cutover procedure" at `:885` is the SAME-HOST
cutover and must NOT be edited; the three real edits are at `~:1075`, `~:453` and `:1657` (now
`## Files to Edit` item 3). Noted that the job holds `concurrency: deploy-inngest-restart,
cancel-in-progress: false`, so the dark path's extra ~2 minutes can queue a deploy behind a probe
fired just before a window — one sentence in runbook edit (a).

**Out of scope, recorded not deferred:** `knowledge-base/operations/expenses.md:46` carries the
Better Stack row at `$68.00/mo` with `verify_by=2026-09-16`, four days overdue, renewal date `-` and
plan tier unverified. It is pre-existing and not caused by this change; it needs an
`soleur:operations:ops-advisor` pass, not a deferral issue from this plan.

### Product/UX Gate

Not applicable — tier **NONE**. The mechanical UI-surface override does not fire: `## Files to Edit`
and `## Files to Create` contain no path under `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx` or any other UI-surface glob. The change's entire user surface is a GitHub
Actions run log read by one operator.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Close #8079 as overtaken by the cutover** | Rejected — the code defect (bare `exit 1`, opaque cause) is live, and since 2.4 it sits on a production-outage diagnosis path. Only the issue's MOTIVATION is historical; the deliverable is unchanged and now worth more. |
| **`dark` exits non-zero with a distinct token** | Rejected — see **D1**. It inverts the arm's own convention (its worst finding is already a warning at exit 0) and reds a state the operator created deliberately via `op=rollback`. The confusion it would prevent is prevented in the message instead (**D2**), where it can be stated in words. |
| **Teach the LIB a post-cutover flag partition (make `done` a pass class)** | Rejected — `_erg_flag_class` is shared with 2.0 and the recut gate; changing it would alter a destroy gate's semantics to fix a diagnostic's message. The caller already has `flag`/`hb_flag` in the emit file (**D8**). |
| **Leave the arm as `exit 1` and document the limitation in the runbook** | Rejected — a documented unrunnable diagnostic is still unrunnable, and #8054 established that this class is fixed in the script, not in prose. |
| **A new gate entry point for the probe** | Rejected — the gate grades the same host on the same rows with the same 11 tokens; a fork would drift (the E11/E13 allowlist has already drifted once, which is why the suite derives it from the P1-5 source). |
| **Hoist the shared mechanism out of both arms** | Rejected — **D3**: six exec-arm-scoped assertions would redden, widening a P2 fix onto the P0 gate. **D10** supplies the drift guard instead. |
| **Bump the consumer assertion from `-eq 1` to `-eq 2`** | Rejected — **D7** row 1: it preserves the number and loses the property. |
| **Loosen the `#6617` read-only-contract assertions to let the new code through** | Rejected — each is re-aimed at the property it was protecting (invocations not mentions; transport retry not loop keywords; hooks not log tags; secret writes not the tool's name), and each re-aiming gets a mutation row proving it still reddens (**M2.8**-**M2.10**). |
| **Reuse `_bs_read_remedy` unchanged** | Rejected — it would report "2.0 probe read:" from an op the operator never ran (**D4**). |

## Test Scenarios

EXECUTED unless marked *(static)*. Dynamic scenarios run the extracted region in a fresh `bash`
process via `render_arm_region`, with `curl` and the `doppler` process stubbed and the real gate lib
sourced.

1. **Dark, canonical.** webhook 500 + `__FETCH_FAILED__`; probe row `http_code=000
   server_active=failed cutover_flag=rolled-back registry_fns=__UNREADABLE__ probe_schema=8
   host_role=dedicated`; same-boot heartbeat 1 min old, `rolled-back` → rc 0; the notice carries a
   36-char `boot_id`, a row age, `flag=rolled-back`, a heartbeat age and `hb_flag=rolled-back`; the
   warning carries `ANSWERED:` and `NOT ANSWERED:`; output contains none of the reserved triple and
   no raw row field (`zz_trailing` absent).
2. **Dark, non-canonical must-PASS (H2).** As (1) with `aborted` on both rows → rc 0, same shape.
3. **Armed flag must-FAIL (H1).** As (1) with `cutover_flag=armed` → rc 1, `REFUSED (flag_armed)`,
   remedy says read that run and dispatch nothing.
4. **`done` flag — the post-cutover outage case.** As (1) with `cutover_flag=done` on both rows →
   rc 1, `REFUSED (flag_armed)`; the remedy names `inngest-host-state.sh`,
   `scheduled-inngest-health.yml` and `apply_target=inngest-host-replace`, and contains none of
   "the cutover already completed", `op=verify`, `restart-inngest-server`.
5. **Silent.** Zero probe rows → rc 1, `REFUSED (silent)` including the ingest/quota clause; region
   does not fall through.
6. **fsm_silent.** Dark probe row, zero same-boot heartbeats → rc 1, `REFUSED (fsm_silent)`.
7. **host_serving.** Probe row `http_code=200` → rc 1, `REFUSED (host_serving)` naming
   `op=inventory`; no mutating op named.
8. **Read failure, maintenance body.** probe read rc 22 → rc 1, `::error::registry-probe probe read:
   the ClickHouse read path is under maintenance`; body NOT printed; the "NOTHING about the
   dedicated host was measured" line present.
9. **Read failure, credentials rejected.** rc 22 with a `Code: 516` body → rc 1, classified, and the
   username substring absent from the entire output.
10. **webhook_path 403.** → rc 1, `REFUSED (webhook_path)` naming `op=inventory`, NEITHER read marker
    present.
11. **webhook_path 500 without the signature.** → rc 1, `REFUSED (webhook_path)`, no read.
12. **Marker control.** The dark path with the same stubs DOES leave both read markers — so (10) and
    (11)'s absence assertions are measurements, not vacuities.
13. **Live 200, empty.** `{"registry_empty":true,"function_count":0,"function_ids":[]}` → rc 0,
    prints `registry_empty=true function_count=0 ids=[]`, and performs NO Better Stack read.
14. **Live 200, non-empty.** `{"registry_empty":false,"function_count":3,…}` → rc 0 with the existing
    warning naming `op=doublefire-probe` — unchanged behaviour.
15. **Trap window (M2.7).** After (5)'s refusal, no `rpg.*` directory remains under the render's
    `RUNNER_TEMP`.
16. *(static)* **Consumer census.** 1 in `execute)`, 1 in `registry-probe)`, 0 elsewhere, ≥ 12 arms.
17. *(static)* **Token parity (D10).** exec-arm set == probe-arm set == the lib's execute-gate set;
    ≥ 10 `exit 1` inside the probe `case`; `*)` exits 1 and names the gate.
18. *(static)* **Extraction control (H3).** the probe-arm extractor's output is non-vacuous and
    contains no `CRON_PERIOD` (the neighbouring `doublefire-probe` arm's unique token).
19. *(static)* **Purity.** no probe-arm annotation interpolates `RPG_PROBE_ROWS`, `RPG_HB_ROWS`,
    `BODY` or `CAUSE`; no `RPG_` field is assigned outside the emit-regex read except its
    `__UNREAD__` sentinel initialisation.
20. *(static)* **No SSH, no bare mutating op.** the probe region contains no `ssh `, and every
    `op=(execute|resume|rollback|arm)` mention is preceded by **D5**'s qualifier.
21. *(static)* **HTTP-200 content pin.** the live block is byte-identical to its pre-change form
    modulo indentation and comments.
22. **Exec-arm regression.** every existing `#8054` render and the AC7 content pin are green with no
    edit to their expectations.
23. **Mutation matrix.** M1.1-M1.4 and M2.1-M2.10 all redden; H4's known-negative does not.
