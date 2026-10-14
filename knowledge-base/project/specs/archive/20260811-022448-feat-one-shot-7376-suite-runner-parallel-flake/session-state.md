# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-10-fix-infra-suite-runner-parallel-flake-plan.md
- Status: complete

### Errors

None. All deepen-plan gates passed (4.6 User-Brand Impact with required scope-out; 4.7
Observability 5/5 fields, ssh-free; 4.8 no PAT-shaped vars; 4.9/4.10/4.55 skip — no UI surface,
no store, no serving surface).

Two self-corrections were made mid-session and recorded in the plan rather than silently fixed:

- A false "zero delta to the published surface" claim — the monitor's `tail -30` is
  **unconditional** (outside its `if`), so line-prefixing alone does not protect the public
  issue body. Risk 2's mitigation and the GDPR clearance were both false until corrected, and
  the GDPR gate was then cleared against the wrong surface twice (the genuinely new surface is
  the world-readable run log, since output currently goes to `/dev/null` and reaches nothing).
- An intuited excerpt-anchoring marker set that measurement showed was ~85% wrong: only 10 of
  93 suites print `[FAIL]` while 78 print bare `FAIL:` at column 0, and `^no ` matches nothing
  (it was derived from a helper function's *name*, not its output). Corrected to a
  corpus-derived ERE covering 85/93 plus a conformance test.

### Decisions

- **Probe-first, but bucketed by what is actually known.** Certain defects (observability gap,
  live-tree collision, false-green exit logic) ship without a measurement gate; H2/H3/H4 stay
  `UNKNOWN` with explicit confirmation criteria; H1 is refuted and written up so it is not
  rediscovered.
- **H1 (`pipefail` + `producer | grep -q` → SIGPIPE) is refuted by measurement.** The mechanism
  reproduces, but the threshold is the 64 KiB pipe capacity and every real call site is ≤5 KB —
  ~12× below the bar, with zero above-threshold streaming sites in the repo.
- **Two defects are provable by reading, so they ship without waiting for evidence.**
  `run-registered-suites.test.sh` is itself registered and mutates the live infra dir while
  `credential-persist-home-guard` diffs a copy against that same still-live directory; and an
  OOM-killed wrapper emits neither `PASS` nor `RED`, so `RED=0` and the runner **exits 0** while
  printing `91 passed, 0 failed (of 93)` — a pre-existing false green that likely masked H2
  evidence all along.
- **One PR by default, with a single explicit Split Trigger.** The evidence source is a local
  loop needing the instrument in the working tree, not on `main`; ADR-133's "instrument ships
  alone" was formed where the author did not control the measuring environment.
- **Rejected auto-derived parallelism width.** A harness whose width varies with its environment
  makes its own flake irreproducible; if H2 is confirmed, serialise the docker/terraform class
  instead.
- **Local change plus a one-clause ADR-133 amendment; no shared width primitive** —
  `test-all.sh` is sequential, so such a primitive would have exactly one consumer.
- **Deferred the `| grep -q` linter to a follow-up issue** — it would guard a mechanism that
  provably cannot fire today and would need a mass rewrite or a baseline file.

### Caveat carried into implementation

The local `taskset` loop bounds **CPU only**, not RAM or disk, so it cannot validate a capacity
fix, and a local non-reproduction establishes nothing — hence the explicit Split Trigger rather
than a silent assumption.

### Components Invoked

- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `Explore` (93-suite shared-state audit), `learnings-researcher`,
  `soleur:engineering:cto`, `code-simplicity-reviewer`, `spec-flow-analyzer`,
  `security-sentinel`, `test-design-reviewer`, `observability-coverage-reviewer`, plus a scoped
  advisor consult
- CLI: `gh` (issue/PR/run premise validation), `git grep` / `git ls-files`, `taskset`, direct
  suite execution for measurement
