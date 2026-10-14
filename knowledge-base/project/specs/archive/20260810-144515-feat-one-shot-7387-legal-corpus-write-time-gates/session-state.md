# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-10-feat-legal-corpus-write-time-gates-plan.md
- Status: complete

### Errors
None blocking. Five substantive findings were folded into the plan rather than deferred to `/work`:

- CLO returned **NOT SAFE TO IMPLEMENT AS WRITTEN** with 13 binding amendments (1–5 and 11–12
  non-waivable). Gate 1 was respecified on *referent*; `tasks.md` carries the blocked status.
- Three cited context files do not exist on `main` or on the 7347 remote — they exist only on
  local ref `2dd397542`. No acceptance criterion may depend on them (task 0.6).
- The issue's own claims were measurably wrong: counterfactual value is **4 of 10** P1s, not 6–7;
  `app.soleur.ai` occurs 140 times, not 202; the "both list-splitting defects" are three.
- Gate 2 was unbuildable as first specified, twice. Strict equality would have red-ed the mirror
  remediation issue's own PR; a full-diff SHA false-fires on any lockstep edit. Both proven with
  fixtures. Resolved as a subset ratchet over an `^[<>]`-stripped ordered sequence.
- Two of the plan's own AC commands were broken and were fixed: `gh run view --job` takes a numeric
  ID, not a name; and `grep -rn … --include='*.sh' .` mis-reported because `grep` is a shell-function
  shim in this environment.

### Decisions
- **Gate 1 classifies on referent, not marker proximity.** `This section` inside a marker-bearing
  section fires; `The paragraph above` is excluded. Verified 2 hits / 0 false positives against the
  ruled-final tree. Flush-left became "attachment must match referent" — limb-referent riders are
  legitimately indented.
- **Gate 2 is a subset ratchet** computed against the merge-base SHA, fail-closed. Reduction must
  pass so the mirror-remediation work is not blocked.
- **All suites live in repo-root `scripts/`**, because `lint-orphan-test-suites.sh` auto-enforces
  registration there — making the issue's headline failure mode (an unregistered gate that is
  indistinguishable from a passing one) structurally impossible. Its `REQUIRED_RUNNERS` is extended
  to cover the live lines too, which nothing previously enforced.
- **The `ci.yml` edit was cut.** The gates already ride the required `test` context via
  `test-scripts` (`fetch-depth: 0`); the draft also rested on a false claim about job-level `env:`.
- **Gate 3's input is a sourced shell DSL, and its waiver is an out-of-band CODEOWNERS-owned ack
  ledger.** No `yq` exists anywhere in the repo, and an in-document pragma would change the raw file
  SHA pinned into the WORM consent ledger and the CLA R2 Object-Lock evidence.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Review panel: `kieran-rails-reviewer`, `architecture-strategist`, `code-simplicity-reviewer`,
  `spec-flow-analyzer`, `soleur:legal:clo`
- Research: `repo-research-analyst`, `learnings-researcher`, 4× `Explore`
- Gates run: plan 0.6 premise validation, 1.7.5 code-review overlap, 2.5 domain review, 2.7 GDPR,
  2.10 ADR/C4; deepen 4.4 / 4.6 / 4.7 / 4.8 / 4.9 / 4.10

### Open decision challenges
See `decision-challenges.md` — UC-1 (gate 3 scope) and UC-2 (mirror-remediation priority + date).
