---
title: "The gate I built for a dark host was blind to the byte shape of nothing — and my define-once refactor broke the consumer I did not grep"
category: test-failures
tags: [inngest, cutover, bash, mutation-testing, test-fixtures, better-stack, observability, cross-consumer-grep, review]
module: scripts/cutover-inngest.sh, tests/scripts/lib/inngest-host-dark-gate.sh
issue: 8054
pr: 8056
date: 2026-09-11
symptom: "A 550-assertion wiring suite and a 270-assertion gate suite were green while the production reader's EMPTY result graded `unreadable` instead of `silent`, the recut workflow's remedy derived an empty schema, and an HTTP error body that names a credential was echoed to a public run log."
root_cause: "The render harness stubbed the FUNCTION under the seam (`_bs_query_rows`) instead of the PROCESS it execs (`doppler`), so the stub's byte shape became the fixture's shape; a constant refactor was grepped in one consumer and not the other; a remedy printed a body without asking what a body can contain."
---

# The gate I built for a dark host was blind to the byte shape of nothing

## Problem

#8054: `op=execute` step 2.0 required the dedicated Inngest host to answer over GQL, but P1-5
keeps it dark until `op=arm`, which runs after execute — the cutover's own orchestrator could not
run its first step. The fix (PR #8056) added a second entry point to the recut gate lib,
`inngest_execute_registry_gate`, that grades darkness positively from the host's hourly probe row
plus the flip FSM's ~1/min heartbeat, joined on the journald `_BOOT_ID`. The implementation shipped
with TDD, a 22-row mutation matrix, two exact assertion floors, a token-coverage floor, and a
render harness that executes the real 2.0 block in a fresh bash process. A ten-agent review then
found **41 findings — 1 P1, 8 P2** — every one of them in verification code or prose, none in the
predicate logic, and four agents converged on the same defect the whole battery could not see.

## Solution

Three shapes, each fixed inline and pinned:

1. **Stub the process boundary, not the function under it.** The render driver had
   `_bs_query_rows() { … empty) return 0 ;; }` — zero bytes for "no rows". The real reader ends in
   `printf '%s\n' "$rows"`, so a zero-row result lands on disk as ONE blank line; `grep -c ''`
   counted it, E2 saw "bytes present, nothing decoded" and graded `unreadable` ("file an issue
   against the emitter") where the state was `silent` ("read the health run, replace the host").
   Fixed by making the driver extract the REAL `_bs_query_rows` and `_bs_read_remedy` from the
   script and stub `doppler`, recording its argv (which also pinned `--since 24h/--limit 500` and
   `--since 30m/--limit 200`), and by a shared `_ihdg_undecodable` that counts NON-EMPTY lines
   (`grep -c .`, the idiom G10 already used two screens down). One-blank-line fixtures were added
   to the gate suite for both streams.
2. **A "define it once" refactor is a cross-consumer grep.** Replacing `expected_schema="8"` with
   `$_IHDG_EXPECTED_SCHEMA` in the lib silently broke `.github/workflows/apply-web-platform-infra.yml`,
   whose `stale_schema` remedy told the operator to run `grep -oE 'expected_schema="[0-9]+"'` on the
   lib — resolving to `''`, so `grep -c "probe_schema="` would have read "the pin carries it" for
   every pin. Nothing pinned that derivation. Fixed the workflow and added Row 6d to the gate suite:
   extract the operator's command from the workflow text, run it against the live lib, require a
   digit equal to the constant (proven red on the old text).
3. **Never echo an HTTP error body until you have asked what it can contain.** The rc-22 read
   remedy printed the first 200 bytes of the ClickHouse error body. A 403 body is
   `Code: 516. DB::Exception: <BETTERSTACK_QUERY_USERNAME>: Authentication failed…` — half of the
   Basic-auth pair, injected by `doppler run` inside the reader so GitHub's masking never sees it,
   on a public repo. Verified live with a wrong password. Now the body is classified
   (credentials-rejected / under-maintenance / other) and only its length is printed; stderr is
   scrubbed of quoted values and `*.betterstackdata.com` hosts.

Also from the panel: `__FETCH_FAILED__` is emitted by the web-host probe on ANY curl failure
(timeout, reset), not only connection-refused — the ADR, C4 edge and script comment all said
"refused"; E14 was added (the probe row must postdate the newest same-boot FSM transition) to close
the window a stale dark row could outlive an arm-then-abort. The heartbeat's object `.message` is
Better Stack's ingest-side parse, not Vector's (`vector.toml` ends every transform in
`encode_json`) — three artifacts said Vector. The execute→quiesce→execute loop the 2.2 remedy
prescribes fails at 2.1 capture on the stopped scheduler (#6921, pre-existing, newly reachable);
the output now says so before the operator opens the window.

## Key Insight

**A stub placed ABOVE the seam it replaces cannot be wrong about the seam — it can only be wrong
about everything below it, and nothing in the suite can tell.** The render "executed the real 2.0
block" and it did; the reader it executed was a five-line stand-in whose author was thinking about
rows, not about the one byte a `printf '%s\n'` emits for none. Four independent agents found it
because each ran the REAL reader once. Every mutation of the gate, every render of the arm, every
floor was measured through the stand-in. The cheapest gate is: **stub the process the code execs,
never a function the code defines** — then the fixture's byte shape is whatever the real function
makes of the stub's output.

The second insight is the same shape one level up: **"define it once" is a rename, and a rename is
a cross-consumer grep** (`hr-type-widening-cross-consumer-grep`). The dark-gate suite asserted the
literal appeared nowhere else in the lib — and that assertion was satisfied by breaking the one
consumer that lived in a different file.

## Prevention

- **Render harnesses stub `doppler`/`curl`/the binary, never `_bs_query_rows`-class wrappers.**
  Extract the wrapper from the script under test with `awk '/^fn\(\) \{$/,/^\}$/'` and eval it in
  the driver; record the stubbed process's argv so operands (`--since`, `--limit`) are pinned.
- **Before replacing a literal with a constant, `git grep` the literal repo-wide and read every
  hit as a consumer** — including operator remedy text inside workflow YAML, which is source code
  the operator executes by copy-paste. Add a suite row that RUNS the derived command.
- **A "not printed" rule for any HTTP error body on a public runner**: print length + a
  classification; never bytes. Ask "what does this endpoint put in a 4xx body?" and test the
  answer live with a deliberately wrong credential before shipping the echo.
- **When the review panel converges on one defect from four lenses, treat it as ONE structural
  cause and fix the class**: here, the seam placement, not the E2 comparison.

## Session Errors

1. **Planning subagent + two children hit HTTP 429** (forwarded). Recovery: recovered the on-disk
   plan checkpoint and completed in place. **Prevention:** the plan skill's skeleton-checkpoint
   phase already makes this recoverable; nothing further.
2. **OR-combined `--grep` starved the probe stream** (forwarded). Recovery: two reads, one term
   each; now asserted in the wiring suite. **Prevention:** `_bs_query_rows` takes exactly one term.
3. **First E13 remedy named the WEB scheduler's restart workflow** (forwarded). Recovery: corrected;
   the `BLOCK:`-stream design was cut by the panel. **Prevention:** every remedy verb is now checked
   against the workflow's `op` inputs by the observability reviewer.
4. **`op=arm` dispatched after a partial predicate sweep**, cancelled while `waiting`. Recovery:
   #8018 filed. **Prevention:** read every predicate of a gate before dispatching the op it guards.
5. **`.test-logs/` written into the worktree and "ignored" via the worktree's `.git/info/exclude`**,
   which git does not honour (the common dir's exclude is the one read). Recovery: removed; logs go
   to the session scratchpad. **Prevention:** use the scratchpad for long-lived logs.
6. **Two `test-all.sh` shards refused rc 4** — six sibling full-gate runs in flight. Recovery: every
   suite and lint reading a touched file run in isolation. **Prevention:** rc 4 is a no-verdict, not a
   failure; the one-shot protocol already says so.
7. **A full-command-line process grep was blocked by the guardrail hook** (self-matching).
   Recovery: `list_runs`. **Prevention:** the hook.
8. **Wiring Row 19 reported "did NOT redden"** because the render ran in a subshell inside an `if`
   condition, where bash IGNORES a re-enabled `set -e` — the un-guarded mutant rendered identically to
   the guarded original. Recovery: the render runs in a fresh `bash` process. **Prevention:** any
   harness whose property is "X under `set -e`" must cross a process boundary.
9. **`RENDER_TMPD` set inside `$(…)` was unbound in the caller.** Recovery: parsed from the render's
   output; scratch dirs swept via a list file. **Prevention:** nothing set inside `$(…)` survives.
10. **shellcheck SC1010/SC2034/SC1087** in the suites. Recovery: quoted `"done"`, directives, braces.
    **Prevention:** run `shellcheck -S warning` after each suite edit, not at the end.
11. **Pre-existing SC2283 in the script** blocked AC10. Recovery: quoted the `=set`/`=empty` echoes.
12. **CI's `lint-shell-trace-credential-refusal.py --changed` unbaselines any touched file** — 25
    pre-existing violations in `cutover-inngest.sh` (no xtrace refusal; 24 curls without
    `--disable --noproxy '*'`) had to be paid down in this PR. Recovery: paid down, file removed from
    both baselines, pinned in the wiring suite. **Prevention:** `/work` Phase 0.5 should run the
    changed-file lints the moment a baselined file enters the diff, so the debt is scoped up front.
13. **Mutation rows 21/22 were an equivalent mutant and a design-shape change**; `mutate()` correctly
    reports an equivalent mutant as a FAIL. Recovery: landed as input cases; plan amended.
    **Prevention:** before writing a mutation row, ask whether an earlier predicate makes it
    unreachable.
14. **Plan claimed three `_flip_query_rows` call sites (two) and a "connection-refused" reading of
    `__FETCH_FAILED__` (any curl failure).** Recovery: both corrected; the second became E14.
    **Prevention:** for each causal sentence the plan asserts about a producer, read the producer's
    emit site (`|| echo '…__FETCH_FAILED__…'` fires on every non-zero curl rc).
15. **The `_IHDG_EXPECTED_SCHEMA` refactor broke the recut workflow's remedy derivation** (P1).
    Recovery: workflow fixed; Row 6d runs the workflow's own command against the live lib.
    **Prevention:** `git grep` the literal repo-wide before replacing it — YAML remedy text is a
    consumer.
16. **The render stubbed the reader with a 0-byte empty result; the real reader writes `\n`.**
    Recovery: real reader in the driver, `doppler` stubbed, `_ihdg_undecodable` counts non-empty
    lines, one-blank-line fixtures. **Prevention:** stub the process boundary.
17. **rc-22 remedy echoed a body that can name the ClickHouse username on a public run log.**
    Recovery: length + classification only; stderr scrubbed. **Prevention:** never print an HTTP
    error body; test the 4xx shape live with a wrong credential first.
18. **Three artifacts said Vector parses the heartbeat to an object; Better Stack does.** Recovery:
    ADR §4, C4 edge, `hb_line` comment corrected; the `__UNPARSED__` sentinel names the read path.
    **Prevention:** name the component by reading its config (`vector.toml` → `encode_json`), not by
    inferring from the warehouse row.
19. **A Monitor on the test-design agent's transcript matched an intermediate stop marker.**
    Recovery: waited for the completion notification. **Prevention:** rely on the agent notification;
    do not poll transcripts.
20. **A batch edit aborted on a wrong anchor with earlier replacements unwritten.** Recovery:
    re-applied. **Prevention:** assert every anchor before writing any (the script did; it just
    wrote nothing — which is the correct failure).
