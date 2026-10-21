# Determinism checklist for test suites

A suite an agent can trust is *deterministic*: same code, same inputs, same
result — on any machine, under any load. A suite that is not teaches the
worst lesson a fix loop can learn: retry until green. A failure that
disappears on the next run of *unchanged* code was never fixed — it was
nondeterministic, and it will be back.

This reference is shared by three consumers: `test-fix-loop` applies its
signatures and quarantine protocol inside the loop,
`soleur:engineering:review:test-design-reviewer` cites its axes when
scoring a test's Repeatable property, and `qa` lands
its flake-vs-regression discrimination here for the follow-through fix.

## Flake signatures

Name the shape before fixing it — each signature routes to a different
axis below.

- **Pass-on-retry.** The test fails inside the suite and passes when the
  same test is re-run in isolation on *unchanged* code — no fix applied.
  This is the signature the loop's quarantine screen detects: one isolated
  re-run per newly-failed test, keyed by file + test name (the same `it()`
  title in two files is two entries, not one flake). A retry that itself
  errors or times out is NOT a pass — the failure stays on the fix path.
- **Order-dependence.** Passes alone, fails in the suite (or the inverse)
  — shared mutable state, leaked globals, an unfrozen clock or leaked env
  var left over from a sibling test.
- **Environment-dependence.** Green locally and on branch CI, red on
  merge-group or shared-runner runs — the issue #10649 shape: a
  timing-sensitive suite that only fails under load it never sees in
  isolation. Isolated re-runs under-detect this class; the honest fix is
  determinism work on the test, not another retry.

## The quarantine protocol

For each test the screen marks pass-on-retry:

1. **Isolate** — re-run the one test in isolation via the runner's filter
   flag (`vitest -t`, `pytest -k`, `go test -run`, `bun test -t` /
   `--test-name-pattern`). When the runner cannot filter, one suite-level
   re-run of unchanged code answers the same question by absence.
2. **File** — when the repo has a GitHub remote and `gh` is available,
   file `flake: <test> — <signature>`. Ensure the `flaky` label first
   (`gh label create` with `|| true` — self-heals on a repo that lacks
   it and never rewrites an existing one), then dedupe on a sentinel,
   not the title: `gh issue list --state open --label flaky --json
   number,body` and match `<!-- soleur:flake test="<file>::<name>" -->`
   in the bodies — comment on the existing tracker instead of filing a
   duplicate (the sentinel-dedup arm of `check-red-on-main.sh` in this
   repo; an `in:title "…"` phrase breaks on a test name carrying `"` or
   search-significant punctuation). The issue body carries the sentinel
   line, the pass-on-retry signature, the runner command, and a pointer
   to this checklist; apply `--label flaky` on create or via
   `gh issue edit`. With no `gh`/remote, the quarantine is report-only
   and says so.
3. **Track** — the quarantined set is run-scoped: excluded from the
   failure set driving fix/cluster bookkeeping and the delta counts,
   never counted as fixed, never re-entered on a later re-failure (the
   re-failure is noted in the report and the filed issue instead). It
   consumes no fix-round tally — no fix was attempted.
4. **Un-quarantine** — a flake tracker that stays open forever trains the
   label to be ignored. Convention: auto-close the issue on the next
   green run of the same suite, mirroring the auto-close-stale arm of
   `scheduled-integration-suites.yml` (one green run closes it — "a
   transient flake leaves a permanently open issue and trains the label
   to be ignored"). A repo with no scheduled re-runner keeps the tracker
   until a later loop or a human observes green.

Quarantine is bookkeeping + tracker + report — it never edits, skips, or
deletes a test file, and a quarantined failure never counts toward
"fixed" nor trips a circular-fix verdict.

## The determinism checklist

When a filed flake or a flaky-shaped new test needs a root cause, walk
the axes — most flakes resolve to exactly one.

### Seeds — make randomness reproducible

An unseeded RNG is a test that fails on inputs nobody can replay. Seed
every random source the test touches (`faker.seed(123)`, a stubbed or
injected `Math.random`, synthesized fixtures over live UUID factories).
Property-based runners already print their seed — log it in the failure
line so a red run is reproducible verbatim. (Unseeded-RNG substring
collisions are a measured class: rename the fixture rather than regexing
around it.)

### Clocks — freeze time

A test that reads wall-clock time is nondeterministic by construction.
Freeze the clock the harness provides (`vi.useFakeTimers` +
`vi.setSystemTime`, `timekeeper`, `freezegun`), and never assert exact
equality on a measured quantity — bound it (`-le`, `expect.poll`, a
range); a real clock can tick between the before and after reads.
Cross-service tests need the same skew discipline at both ends: a
timestamp written by one clock and compared by another drifts.

### Network — controlled, fail-loud

Real network inside a unit test is a flake farm: latency, DNS, rate
limits, vendor brownouts. Stub the seam — and make the stub fail LOUD on
an unexpected request (an allowlist router that 500s on anything
unregistered), not return a default that silently passes. DOM emulators
ship real network adapters (happy-dom's `fetch`/`WebSocket` reach the
wire): the blockade is what turns "no network" from an intention into a
property.

### State isolation — no residue between tests

Every test leaves the world as it found it: fresh fixture state per test
(`beforeEach`, not a `beforeAll` that mutates), no shared files, no
leaked env vars or globals, no singleton carried into the next case. A
describe-level row or a mutated module registry is an order-dependence
signature waiting for a scheduler to expose it.

### Output terseness — quiet on green, loud on red

Chatty suites bury the failure line in noise. Run the runner quiet
(`--reporter=dot`, `-q`, the runner's quiet flag) and keep failure output
terse (test name + error, not a stack dump). Terseness is a correctness
property for consumers, not a style one: the loop's parse-failures step
reads only the summary, and any `| tail` / pipefail chain reads the last
line — only a terse summary makes that line the verdict.

### Contention / ordering — load boundaries

The signature an isolated re-run structurally cannot see: a test that
fails only under suite load — parallel workers racing a fixed port, a
tmpfs watchdog, a file lock, a `sleep`-gated resource. The issue #10649
shape: green in isolation and on branch CI, red in merge-group runs
carrying unrelated diffs. Disciplines: allocate ports and tmpdirs per
worker, never fixed; wait on real signals (poll the port or lock, never
`sleep`); keep watchdog budgets per-test, not per-run. A contention
flake can carry two mechanisms at once (an intra-test wait budget AND a
cold-import cost): triage to mechanism, never bump a timeout. For this
class an isolated re-run answers pass-on-retry honestly — and the fix is
the determinism work itself, not the retry.

## Using this checklist

- `test-fix-loop`: the §1 quarantine screen applies the signatures and
  protocol above; a filed flake's issue body points here for the fix
  work.
- `soleur:engineering:review:test-design-reviewer`: a new test carrying
  flake-signal sources (unseeded RNG, wall-clock reads, real network,
  shared mutable state, nondeterministic output) with no determinism
  control is a Repeatable WARN — cite the axis.
- `qa` and humans: the flake-vs-regression discriminator lands here for
  the "what makes it deterministic" remediation.

Source: Addy Osmani, [Agentic Verification](https://addyo.substack.com/p/agentic-verification)
("fast and deterministic" — a suite an agent can trust must be both; a
pass on retry is a flake to isolate, not a fix to report).
