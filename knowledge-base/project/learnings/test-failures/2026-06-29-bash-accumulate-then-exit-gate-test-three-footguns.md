# Learning: three foot-guns when authoring a bash `set -euo pipefail` accumulate-then-exit gate test

## Problem

Implementing the #5703 registry-completeness gate (`plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh`, a pure-bash parity gate mirroring `eval-gate.test.sh`'s `pass()`/`fail()`/`fails` accumulate-then-`exit 1` convention) plus the registry-driven refactor of `extract-block.test.sh`, three independent foot-guns surfaced — one caught by my own mutation test, two by multi-agent review. All three pass a naïve GREEN run and only manifest on drift/failure or edge inputs, which is exactly when a gate must behave.

## Solution

### 1. `set -e` + `pipefail` aborts BEFORE `fail()` when a deliberately-nonzero pipeline is in a command substitution

The first draft built the PARITY failure message with:

```bash
else
  drift="$(diff <(echo "$src_set") <(echo "$reg_set") | tr '\n' ' ')"   # <-- aborts here
  fail "PARITY — drift" "$drift ..."
fi
```

`diff` exits 1 when the sets differ (the failure case). Under `set -euo pipefail` the
pipeline-in-`$(...)` propagates that non-zero, and `set -e` kills the whole script *before*
`fail()` runs. Symptom: the test exits 1 (correct code) but the run is **truncated** — the
clear remediation message never prints, and on a multi-assertion test every later assertion
is skipped, so you lose the accumulate-then-surface-all-drift behavior the convention exists
for. The mutation-test log stopped right after the last passing assertion, which is the tell.

Fix — capture the deliberately-nonzero command with `|| true` *inside* the substitution and
gate on emptiness, so the substitution itself exits 0:

```bash
parity_diff="$(diff <(echo "$src_set") <(echo "$reg_set") || true)"
if [[ -z "$parity_diff" ]]; then pass ...; else fail ... "$(echo "$parity_diff" | tr '\n' ' ')"; fi
```

Same applies to the scan helper: `git grep … | sed … || true` (a legitimately-empty scan
returns 1 and would abort; the downstream parity/characterization assertions report it
cleanly instead). `eval-gate.test.sh` never hit this because its substitutions are all `node`
calls that exit 0; a `diff`/`grep`/`comm`-based gate is the new hazard.

### 2. A registry/array-driven loop fail-opens to `exit 0` with ZERO coverage

The `extract-block.test.sh` refactor replaced `for target in go-routing ticket-triage` with a
loop reading rows from `gated-skills.json` via process substitution (`done < <(node -e …)`). A
process-substitution failure is **not** caught by `set -e`, and an empty/unreadable registry
emits zero rows → the `while` body never runs → the only assertions left are the always-green
`extractBlock` unit checks → the suite exits 0 having tested nothing. Two review agents
(test-design P2, security-sentinel LOW) flagged it. The plan's AC3 "grep for both round-trip
ok lines" only catches this *externally*; the guarantee belongs *in* the test:

```bash
roundtrips=0
while IFS=$'\t' read -r target projected; do [[ -z "$target" ]] && continue; …; roundtrips=$((roundtrips+1)); done < <(node …)
if [[ "$roundtrips" -lt 1 ]]; then fail "registry round-trip coverage" "0 targets executed — empty/unreadable registry would otherwise pass with no coverage"; fi
```

Any time a hardcoded enumeration is refactored to be data-derived, add a minimum-cardinality
assertion in the same edit — the data source becomes a new silent-zero surface.

### 3. A "verify-the-verifier" negative that injects a constant tests the coreutil, not the gate

The negative-sanity check injected a fixed `zz-injected-unregistered` into a copy of the set
and asserted `diff` was non-empty. `diff(A+x, A)` is **always** non-empty, so the check passes
identically against a healthy, empty, or broken live scan — it proves `diff` works, not that
the gate fires. Fix: route the injection through the *same idiom the production check uses*
(captured `diff … || true` string) and assert the injected id lands on the specific
(`< source-only`) side the real fail-message keys off:

```bash
inj_diff="$(diff <(echo "$inj_src") <(echo "$reg_set") || true)"
[[ -n "$inj_diff" && "$inj_diff" == *"< zz-injected-unregistered"* ]] && pass … || fail …
```

The companion DEDUP negative was already correct because it injects into the *raw scan output*,
so the dup only appears if the live scan also emits the id — that data-dependency is the
property a meaningful negative needs.

## Key Insight

For a bash `set -euo pipefail` accumulate-then-`exit` gate test: (1) wrap every
deliberately-nonzero command (`diff`/`grep`/`comm`) in a command substitution with `|| true`
or `set -e` aborts before your `fail()` message and silently truncates the run; (2) a loop
derived from a data source (registry/array/file) needs a minimum-cardinality guard or it
fail-opens to `exit 0`; (3) a verify-the-verifier negative must drive *real* data through the
*production idiom*, not inject a constant that trivially trips the builtin. A naïve GREEN run
exercises none of these — only mutation testing (live drift) and multi-agent review surface
them. Mutation-test every drift class and confirm a *clean message* prints, not just `exit 1`.

Complements [[2026-06-29-new-guard-test-check-what-existing-round-trip-already-covers]] (the
plan-time design simplification for the same gate).

## Session Errors

1. **`Read` of the plan issued at the bare-repo root path before entering the worktree** — "File does not exist." Recovery: read the worktree-absolute path. Prevention: in a bare/worktree repo, resolve and `cd` into the worktree first; never issue a `Read` on a plan path in parallel with the orienting `cd`. (one-off)
2. **errexit-abort masked the PARITY `fail()` message** — see §1. Recovery: `|| true` inside the substitution + `[[ -z "$parity_diff" ]]`. Prevention: §1 — captured this learning.
3. **extract-block registry-driven loop fail-opened to exit 0 on empty registry** — see §2. Recovery: `roundtrips` minimum-cardinality guard. Prevention: §2.
4. **NEGATIVE-(a) injected a constant → tautological** — see §3. Recovery: production-idiom + source-only-side assertion. Prevention: §3.

## Tags
category: test-failures
module: eval-harness
