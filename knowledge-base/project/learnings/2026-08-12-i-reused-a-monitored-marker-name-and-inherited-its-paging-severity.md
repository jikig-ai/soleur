---
module: soleur-plugin-commands
date: 2026-08-12
problem_type: integration_issue
component: cli_command_surface
symptoms:
  - "a healthy workspace would log a platform-integrity error at every session start"
  - "WEDGE_RE matched a bare marker name while its siblings carried lookaheads"
  - "the invariant the new emitter broke was asserted in two files, neither in the diff"
root_cause: reused_identifier_inherits_consumer_semantics
severity: high
tags: [observability, telemetry, marker-vocabulary, review, anti-vacuity, mutation-testing]
issue: 7474
pr: 7475
synced_to: [review]
---

# I reused a monitored marker name, and inherited its paging severity

## Problem

#7474: `/soleur:sync`'s Phase 0 gate verifies the plugin root's **identity** (manifest exists,
`"name": "soleur"`, `scripts/` is a directory) and answers that correctly. It does not answer
**freshness** — a root that is genuinely Soleur but does not carry a producer satisfies every
predicate, so the invocation runs and dies as an unattributed interpreter error. The operator
reads "the c4 area is broken"; the actual cause is the payload.

The fix presence-guards each anchored invocation in `plugins/soleur/commands/{sync,go}.md`.
For `go.md` I deliberately reused its **existing** marker families rather than inventing new
ones — `SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=absent-from-verified-root` and
`SOLEUR_SESSION_START_SKIPPED reason=absent-from-verified-root`. The reasoning was
discoverability: `SOLEUR_GIT_REPO_DIAG` is already mirrored by
`apps/web-platform/server/git-lock-marker-telemetry.ts`, so a new name would have been invisible.

That instinct was right for **visibility** and exactly wrong for **severity**.

## Root cause

`WEDGE_RE` matched the bare name with no discrimination:

```ts
…|SOLEUR_GIT_WORKTREE_VERIFY_FAILED\b|SOLEUR_GIT_REPO_DIAG\b|SOLEUR_FEATURE_PUSH_FAILED\b|…
```

while its immediate siblings in the same alternation **do** discriminate:

```ts
SOLEUR_GIT_BARE_SELFHEAL\b(?=[^\n]*\sbranch=failed\s*$)
SOLEUR_SESSION_STATE_UNAVAILABLE\b(?=[^\n]*\sreason=worktree-UNLEASED-and-reapable\s*$)
```

A `WEDGE_RE` hit sets `wedged: true`, which emits
`log.error({sec: true}, "in-sandbox git wedge/rejection detected …")` to Better Stack plus a
Sentry breadcrumb. My new emission fires when the root **verified** and only the script is
missing — the repo may be perfectly healthy, and `go.md`'s own fallback `git rev-parse` probes
then decide readiness on their own. `go.md` runs at **every session start**.

So: every customer on a stale-but-valid install would have logged a recurring
platform-integrity error, on the first Bash call of every session. By this PR's own premise
(stale installs are common and invisible) that population is exactly the one the fix targets.

The invariant I broke was asserted in two places, **neither in my diff**:

- `git-lock-marker-telemetry.ts:132` — *"SOLEUR_GIT_REPO_DIAG is only emitted on the not-ready path"*
- `git-lock-marker-telemetry.test.ts:169` — *"emitted ONLY on the not-ready path → always a blocked session"*

Nothing local could have told me. `tsc` was clean, both suites green, 68/68 CI checks passed.
Five independent review agents converged on it.

## Solution

Discriminate in the consumer, matching the idiom the file already used twice:

```ts
SOLEUR_GIT_REPO_DIAG\b(?![^\n]*\ssource=probe-unreachable\b)
```

Both `probe-unreachable` arms (the pre-existing `reason=plugin-root-unverified` and the new
`reason=absent-from-verified-root`) stay in `MARKER_RE`, so they remain **mirrored** — they are
simply no longer classified as blocked sessions. The stale comment and the test invariant were
corrected in the same commit, and a paired test now pins both classes:

```ts
test("SOLEUR_GIT_REPO_DIAG source=probe-unreachable is mirrored but NOT wedged", () => {
  for (const reason of ["plugin-root-unverified", "absent-from-verified-root"]) {
    const line = `SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=${reason}`;
    const [m] = extractGitLockMarkers(line);
    expect(m?.line).toBe(line);   // still mirrored
    expect(m?.wedged).toBe(false); // but not paged
  }
});
```

## Key insight

**Reusing an existing marker/identifier name is a decision about its CONSUMERS, not just about
discoverability — and the consumer usually lives in another component, with no local signal.**

The trap has a specific shape. Inventing a new name is *obviously* a decision (you must wire it
up, and the wiring is visible). Reusing one *feels* like the conservative choice, because the
plumbing already exists — which is precisely why nobody re-reads what that plumbing decides.
Every property the existing name carries downstream is silently inherited: severity, routing,
alert thresholds, dedup keys, retention.

Gate, when emitting an **existing** name from a **new** condition:

```bash
git grep -n '<MARKER_NAME>' -- '*.ts' '*.sh' ':!*test*'
```

For each consumer, ask: *does it discriminate, or does it match the bare name?* If it matches
bare, your new condition inherits the old one's classification. Check whether any nearby
sibling in the same construct carries a qualifier — if some do and yours does not, that
asymmetry is the tell.

Generalizes beyond markers: HTTP status codes reused for a new failure mode, an enum member
reused for an adjacent state, a log level reused for a different severity, an exception type
reused for a non-equivalent error.

## Secondary lessons

**A guard's value can live in the TEST's discriminating power, not in a live production gap.**
I cut a `to_command_position()` extractor widening after measuring, correctly, that no
command-position invocation exists in `sync.md` today. The measurement was right; the
conclusion was wrong. A mutation then showed that without it, rewriting a guard to the rejected
`&&`/`||` form fails as *"target not in inventory"* rather than naming the actual defect — i.e.
`T0l` could not fail for the right reason. "No live gap" answers whether the guard protects
production; it does not answer whether it protects the **test's ability to discriminate**.

**An assertion anchor must be unique within its own search scope.** My first `P8` pinned the
bare `SOLEUR_SESSION_START_SKIPPED`. That fence *also* contains the pre-existing
identity-failure arm emitting the same name, so deleting the branch under test passed. Pinning
the full marker including `reason=` fixed it. Reading the assertion did not catch this; running
the mutation did. (Same family as `cq-assert-anchor-not-bare-token`, one level up: the anchor
was specific enough to exclude comments and still ambiguous within its own fence.)

**A transform that rewrites code can rewrite itself.** Converting assertions to a counting
wrapper with `re.sub(r'\bexpect\(', 'check(', src)` also rewrote `return expect(actual)` inside
the helper being inserted → infinite recursion, 12 tests failing. Order matters: transform
first, insert the helper after. Any self-referential codemod needs its own insertion excluded
from its own pattern.

**The structural-twin miss recurred, four lines apart, in the file I was fixing.** I annotated
a stale scope claim `CORRECTED AT REVIEW` and left the `### Decisions` block immediately above
it asserting the reversed claims — including *"satisfies ADR-179 decision 5"*, which the ADR
amendment I had written minutes earlier contradicts in as many words. Correcting one block and
not its peer is worse than correcting neither: a reader infers unmarked = still live. Sweep by
CLAIM, and after correcting one instance, grep for its peers before moving on. See
[2026-07-21-i-marked-one-block-and-not-its-twin…](2026-07-21-i-marked-one-block-and-not-its-twin-in-the-file-whose-purpose-was-removing-that-defect.md).

**Both anti-vacuity floors counted DISPATCHES, not VERDICTS.** Neutering bash `fail()` to bump
only the case counter exited 0 with a live defect planted; gutting a vitest assertion body left
the per-block counter satisfied. Fixed by asserting `PASS` as well as `CASES`, and by counting
inside a `check()` wrapper — the only placement a deletion cannot survive. This class is
already well documented; see
[2026-08-05-i-built-a-cadence-on-a-bot-that-never-ran…](2026-08-05-i-built-a-cadence-on-a-bot-that-never-ran-and-my-battery-certified-the-gate.md).
What is worth adding: I hit it in **both** suites of the same PR, having read that catalogue
entry while writing them.

## Prevention

- When emitting an existing marker/identifier from a new condition, grep every consumer and
  check discrimination. Sibling qualifiers in the same construct are the tell.
- Before cutting a guard on "no live gap", run the mutation that guard exists to catch and
  confirm it still fails **for the right reason**.
- Mutation-verify every new assertion; do not read it and conclude. Two of this PR's assertions
  looked correct and were satisfiable by a sibling in the same scope.
- Anti-vacuity floors must count decided assertions, never blocks or dispatches.

## Session Errors

1. **Six P1s were PR-introduced by me and caught only by the review panel** — the WEDGE_RE
   paging regression, the wrong remedy verb, P6 testing co-occurrence rather than adjacency,
   go.md's attribution half pinned by nothing, `affects=` checked for membership rather than
   correspondence, and both floors counting dispatch.
   **Prevention:** the design-validity pass and the full panel each found classes the other
   could not. Run `test-design-reviewer` with an explicit "find the vacuity my battery MISSED —
   do not re-run its mutations" mandate; it found six holes on four axes my 13-mutation battery
   never touched.

2. **Told the operator the remedy was `claude plugin install soleur`** on four surfaces.
   `claude plugin update <plugin>` is the correct verb, and ADR-178 had already measured that
   the frozen `0.0.0-dev` sentinel means even that may not converge a stale install.
   **Prevention:** any command a user is told to RUN is a capability claim — verify with
   `<tool> <subcommand> --help` and grep the repo for a prior measurement before shipping it.

3. **`affects=(\S+)` swallowed the closing quote** (`coverage"`), so every area read as unknown.
   **Prevention:** a regex reading a token out of a shell double-quoted string must exclude the
   quote character (`[^\s"]+`), not just whitespace.

4. **The `check()` codemod recursed infinitely** by rewriting its own helper body.
   **Prevention:** in a self-referential transform, apply the substitution before inserting the
   code that must be exempt from it.

5. **First `P8` marker pin collided with a sibling arm in the same fence**, so the mutation it
   was written for passed.
   **Prevention:** after writing an assertion, run the mutation it targets before trusting it.

6. **Reverted the extractor widening on a correct measurement, then re-added it** when a
   mutation proved it load-bearing for the test's discriminating power.
   **Prevention:** see Secondary lessons — "no live gap" is the wrong question for a test guard.

7. **Two review agents stalled on the 600 s stream watchdog** under 4-way machine contention.
   **Prevention:** resume rather than respawn (the transcript survives), and bound the resumed
   brief to a short explicit list.

8. **The full suite was harness-reaped twice** — no terminal marker, no rc file, log frozen at
   the contention preamble. That is the documented reap signature, not a diff failure.
   **Prevention:** read the rc FILE, never the completion notification; treat
   `{no marker, no rc}` as un-run. CI on the pushed HEAD is the authoritative gate.

9. **Ran `bun test plugins/soleur/test/changelog.test.ts`** — the file is `changelog-data.test.ts`.
   **Prevention:** one-off; `ls` the directory before asserting a path.

10. **A `pgrep`-in-subshell loop printed nothing** while `ps -ef | grep` found three processes.
    **Prevention:** one-off; prefer `ps -ef | grep '[t]oken'` when the pattern may match the
    probe's own command line.

11. **`awk '{print $2}'` on `gh pr checks`** produced garbage — the column is not stable.
    **Prevention:** use `gh pr view --json statusCheckRollup --jq`, never positional columns.

### Forwarded from `session-state.md` (planning phase)

12. **Two research-agent claims were falsified by direct measurement** — "no existing test
    verifies referenced scripts exist on disk" (P2 already runs `existsSync`) and "no
    `bunfig.toml` pathIgnorePatterns relevant to sync" (`pathIgnorePatterns = ["**"]`, so vitest
    is the only runner).
    **Prevention:** treat a research agent's absence-claim as a hypothesis; grep before adopting.

13. **A capability claim was withdrawn** — "markers are parsed by an agent that files GitHub
    issues"; no such consumer exists.
    **Prevention:** `hr-verify-repo-capability-claim-before-assert`, applied at plan time.

### Ship phase (post-review)

14. **A merge-poll filter counted `CANCELLED` as a failed required check**, so a push that
    superseded an in-flight run self-reported `TERMINAL: required check failed: scan` while
    `scan` was green on the actual head commit. In a headless pipeline that aborts the ship on
    a healthy PR. The guidance drilled into these filters is "silence is not success" — widen
    the alternation so a crash cannot pass unseen — and applying it without thinking produced
    the mirror defect: a filter so wide that routine churn reads as failure. Both directions
    cost a run; only one is ever discussed.
    **Prevention:** in a merge/CI poll, treat `FAILURE`/`TIMED_OUT`/`ERROR` as terminal and
    `CANCELLED` as churn — a superseding push cancels by design. Before acting on any terminal
    verdict, re-read the rollup for the *current* head: this one had a SUCCESS row for the same
    job name sitting alongside the cancelled one.

15. **Archiving the spec directory silently dangled two ADR frontmatter citations**, because
    `related_plans:`/`related_specs:` record the live authored path and `archive-kb.sh` moves
    the file out from under them. Nothing checks these — no linter, no CI job. Measuring all
    four citations in the file (rather than fixing the one that surfaced) showed three dangling,
    one of them pre-existing and belonging to another branch's work.
    **Prevention:** after any `archive-kb.sh` run, `grep -rn` the pre-archive path across
    `--include='*.md'` and repoint what this branch authored. Measure every citation in a
    frontmatter block you touch — the structural twin of the one that surfaced is usually
    already broken, and the corpus-wide version of the class is not this PR's to fix.

## Cross-references

- ADR-179 — bare `${CLAUDE_PLUGIN_ROOT}` anchoring; amended by this PR with Decision 7
- ADR-178 — shared bash primitives ship in the plugin; source of the frozen-sentinel measurement
- #7442 / #7443 — the anchoring fix this builds on
- #7452 — the deferred `installed_plugins.json` SHA-divergence probe
- [2026-08-06-an-observability-plan-can-name-a-sink-the-code-cannot-reach](workflow-patterns/2026-08-06-an-observability-plan-can-name-a-sink-the-code-cannot-reach.md)
  — the adjacent class: a sink that is unreachable, versus this one, reachable and misclassified
