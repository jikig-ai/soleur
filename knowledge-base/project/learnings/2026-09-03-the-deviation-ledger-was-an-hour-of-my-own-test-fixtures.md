---
title: The deviation ledger was an hour of my own test fixtures
date: 2026-09-03
category: workflow-issues
module: telemetry, hooks, compound
issues: [7570, 7534, 7544, 7481]
pr: 7755
tags: [rule-incidents, rule-metrics, adr-091, hook-test-isolation, vacuity, mutation-testing, guard-equals-claim]
---

# Learning: the deviation ledger was an hour of my own test fixtures

## Problem

Two things, one root shape — **a signal that measures the instrument rather than the world**.

### 1. The telemetry compound reads for deviation evidence is synthetic

`compound` Phase 1.5 step 3.5 reads `.claude/.rule-incidents.jsonl` and treats each recent
`deny` / `bypass` as deviation evidence. Measured on this machine, 2026-09-03:

| Fact | Value |
|---|---|
| Live ledger span | `2026-09-02T22:43:34Z` → `23:50:48Z` — **67 minutes** |
| Lines | 1275 |
| Rotation archives alongside it | **none** |
| `deny` events in that span | 951 |
| ...carrying `hr-all-infrastructure-provisioning-servers` | **759** |
| ...carrying `pre-merge-auto-close-scan` | 60 |
| `bypass` / `degraded` / `warn` / `applied` / `unavailable` | 198 / 39 / 75 / 6 / 3 |
| Tool calls of mine actually denied this session | **0** |

That 67-minute span is exactly the window in which I ran the `scripts` shard. The 759 denies are
`.claude/hooks/iac-plan-write-guard.test.sh` driving its hook with synthetic payloads. **The whole
ledger is one hour of the repo's own hook test suites.** A compound run that reads deny-count as
deviation evidence would have read a green full-gate run as ~951 workflow violations.

The suite says otherwise. `.claude/hooks/iac-plan-write-guard.test.sh:1-8`, under a heading
literally called `Isolation:`, states:

> `INCIDENTS_REPO_ROOT redirects emit_incident's writes into a per-test tmpdir.`

`INCIDENTS_REPO_ROOT` appears in that file **exactly once — in that sentence**. It is never
assigned. The isolation is documented and absent. Across `.claude/hooks/`, 20 of 44 `*.test.sh`
reference the variable at all; 24 do not.

### 2. The pollution then burns the aggregate that ADR-091 designates authoritative

Running the local producer (`scripts/rule-metrics-aggregate.sh`, compound Phase 1.5 step 8) exits
**rc=5**:

```
ERROR: orphan rule_id(s) in incidents jsonl not tagged in AGENTS.md:
  adr-033-inngest-cron-canonical, cq-docs-cli-verification, durable-reminder-prefer-inngest,
  git-commit-secret-scan, hr-in-github-actions-run-blocks-never-use, kb-domain-allowlist-guard,
  post-dispatch-watch-gate, pre-ask-technical-fork-gate, pre-merge-auto-close-scan
WARNING: 15 PreToolUse hook input-contract fault(s) [unparseable=15]
```

Every one of those 9 ids is a **hook-internal name** (not a corpus rule id), and every one first
appears in the ledger at `22:47`–`22:48` — injected by the suites. So the orphan gate refuses the
aggregate, the skill's own recovery path reverts the partial write, and nothing is committed.

Consequence, measured: `knowledge-base/project/rule-metrics.json` was last written by `f2f3cc4bc`
(**2026-08-25**, in CI) and reports `rules_unused_over_8w: 105` of `total_rules_tagged: 105` —
*every rule unused*. That all-unused reading is the fresh-checkout-in-CI signature that
[2026-07-06-aggregator-must-run-where-its-gitignored-input-lives.md](best-practices/2026-07-06-aggregator-must-run-where-its-gitignored-input-lives.md)
already named as the exact failure ADR-091 exists to prevent. A local run produces
`rules_unused_over_8w: 98`, `rules_bypassed_over_baseline: 2` — but cannot land.

**The rule-pruning input is currently a metric of how often the hook suites ran, gated by a check
that those same suites trip.**

## Solution

Not fixed here — different subsystem from this PR (git-data rehearsal harness), and the full fix
spans 24 suites. Filed as a consolidated tracker. The shape of the fix:

1. Assign the `INCIDENTS_REPO_ROOT` that suite headers already promise (`incidents.sh:37` honours
   it; the plumbing exists and is used by 20 suites).
2. Either tag the 9 hook-internal ids or teach the orphan gate that hook-owned ids are not corpus
   rules — today it fails closed on names it can never find in `AGENTS.md`.

## Key Insight

**A guard, a metric, and a test fixture are the same object seen from three angles: each claims to
measure something outside itself, and each fails by measuring itself instead.** This PR's entire
subject was "a guard must equal the property it names" — and the review found that same defect
*four more times in the guards this PR itself shipped*, each one after I had just fixed an instance
of it elsewhere in the same session:

| # | The guard | What it named | What it actually read |
|---|---|---|---|
| 1 | `scripts/sentry-issue-discover.test.sh` anti-vacuity floor | "assertions ran" | pushed onto the `FAILURES` ledger the verdict reads — one edit disarmed every assertion *and* the floor |
| 2 | `tests/scripts/lib/git-data-birth-readiness-gate.sh` | "the module's payload shape" | `main.tf` alone — `file("${path.root}/../../evil.sh")` in `outputs.tf` renders into `user_data` and does not move the digest (measured) |
| 3 | two suites' `fail()` | "failures" | `fails=$((fails+1))` → `passes=$((passes+1))` left them **48/0** and **77/0** with real defects injected, because both floors sum the two buckets |
| 4 | ARM 16's eyeball-verb sweep | "no eyeball instructions remain" | a case-sensitive, backtick-blind regex — passed clean while **two real sites survived** |

Three of those four classes were **already documented in this repo**, and #3's fix was sitting in a
sibling file in the same PR: `git-data-runcmd-rehearsal.test.sh` already carried the append-only
`FAILURES` ledger *with a comment describing this exact measurement*. The class had been found and
fixed in **one instance**; the other two suites in the same PR never got it.

So the honest learning is not "these are defect classes to watch for" — the corpus says that
already and said it while I was writing them. It is:

> **Documentation of a class does not transfer to a sibling instance. When you fix a guard-shaped
> defect, the next action is to grep for the shape across every file in the diff — not to write it
> down.** The fix for #3 was `grep -l 'fails=\$((fails+1))' $(git diff --name-only origin/main...HEAD)`,
> which takes two seconds and would have found both survivors.

### Corollary: instrument yields were disjoint, and none dominated

| Instrument | Findings | Notes |
|---|---|---|
| My own mutation battery | 3 | axes I already believed in |
| 10-agent review panel | ~22 | |
| `shellcheck` | 1 | pre-existing `SC2034`, verified present on `main` |
| Deterministic repo lints | 3 | `guard-vacuity-floor`, `lint-shell-capture-exit`, `lint-trap-tempfile-ownership` |

**All three lint hits were against code I had added hours earlier** — including the vacuity floor,
which neither I nor the 10-agent panel caught. The deterministic gates fire only on new code, so
running them once at session start measures nothing; on a guard-shaped PR they are the *cheapest*
instrument and belong **after each guard-shaped commit, before the panel** — the panel costs orders
of magnitude more and did not dominate them.

### Corollary: the suite that caught the composition bug is invisible to CI

`apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` is the only thing that caught a change
that was right in isolation and wrong in composition (job-log masking added *inside* the capture
step consumed one of the harness's queued `doppler` responses and shifted the poll's attempt
accounting: **71/0 → 70/1**; the fix was lifting it into its own step). **Both shards structurally
exclude that suite and no required check covers it** — it is verified only when someone runs it
deliberately. Record this as a coverage-boundary fact about this repo, not as a bug that got fixed.

## Session Errors

**Forwarded from `session-state.md` (plan phase, pre-compaction):**

1. **Three one-shot brief premises did not survive verification** — #7460's "merge-blocking Doppler
   write" was already satisfied; the `HOST_SQL` `detail` gap closed on main in `dfcf7bd26`; ADR-115
   does not state the `user_data` ForceNew property it was cited for (it is ADR-149/ADR-152).
   **Prevention:** re-derive every inherited premise against the tree before planning on it.
2. **Four self-caught planning errors** — ref-count from a tag-dominated `ls-remote`; 83 duplicated
   lines in a Phase 4 rewrite; an `= 6`/`>= 6` contradiction in AC 8; a shared-helper consumer count
   from too narrow a grep (1 claimed, 12 actual). **Prevention:** already the right behaviour —
   recorded rather than quietly patched.
3. **Three security claims drafted stronger than the tree supports**, walked back. **Prevention:**
   state the threat model's preconditions before asserting the mitigation.
4. **MCP `plugin:github:github` failed to connect** (recurred this session). `gh` CLI used
   throughout; nothing blocked. **Prevention:** none needed — the fallback is the primary path here.

**This session:**

5. **A Python heredoc with `'''` adjacent to a shell `'`** → `SyntaxError`, 3×, nothing written.
   **Prevention:** placeholder tokens (`Q = "'"`, `NL`, `BT`) instead of nested quote characters.
6. **`shift 2` with one argument left is an infinite loop** — introduced in `scripts/sentry-issue.sh`,
   measured by hanging to timeout; the same shape then found in the capture script's
   `--cloud-init`/`--out` (measured rc=124). **Prevention:** `shift 2 || shift` on every value flag.
7. **Mutation harness broken by its own setup** — copied the suite to `/var/tmp`, but it derives
   `DIR` from `BASH_SOURCE`, so every mutant reported "render failed" rather than a verdict.
   **Prevention:** mutate in place under a non-`.test.sh` name; assert the mutation LANDED (`cmp`)
   before reading the mutant's exit code.
8. **A filename pin ABORTed 31 arms** of the gate's own suite (the fixtures use
   `templatefile("${path.module}/../../ci.yml")`). **Prevention:** pin the FORM, not the filename.
9. **ARM 16's regex was case-sensitive and backtick-blind** → reported clean while two real sites
   survived; the widened `.{0,4}` still missed a 6-char gap. Bound measured in both directions → 8.
   **Prevention:** measure a text sweep's bound against known-positive AND known-negative sites
   before trusting a clean result.
10. **`tr -d ' |'` stripped the ASCII pipe, not Doppler's `│`** — a grep that could never match.
    Redone with `--json`. **Prevention:** never parse a CLI's box-drawing table; ask for JSON.
11. **Edited a file while its own suite was reading it** → bogus `rc=2` "syntax error". Bash reads
    by byte offset. Self-diagnosed as the documented trap; relaunched on a stable tree.
    **Prevention:** treat any rc=2 during a run as suspect-self-inflicted before reading it as a
    finding.
12. **Guessed a vacuity floor of 24 against a measured 23.** **Prevention:** floors are measured,
    never estimated.
13. **A mentions-count bound stood in for a binding assertion** on D1 — replaced with a structural
    one (the live call site's text, plus the helper definition not containing `CAPTURE`).
    **Prevention:** a count is evidence about a string, never about a binding.
14. **My own `SOLEUR_TEST_MODE` gate broke my own 4 Sentry arms** — fixed by wiring the marker into
    the helper, which incidentally proves the gate is load-bearing. **Prevention:** when adding a
    test-mode gate, run the suites that cross it in the same breath.
15. **A verdict message introduced backticks and an apostrophe into a quoted `jq` program** → shell
    syntax error. De-quoted. **Prevention:** message text is code inside a quoted program.
16. **Three shard lint failures, all against code I had added hours earlier** —
    `lint-shell-capture-exit-live` (`|| true`), `guard-vacuity-floor` (the floor routed through its
    own machinery), `lint-trap-tempfile-ownership` (missing owning trap). **Prevention:** run the
    deterministic lints after each guard-shaped commit, not once at the end.
17. **`lint-diagnosis-claims` 1 over baseline** (ADR-166 ratchets down only) → resolved with a
    MEASURED-BY annotation. **Prevention:** name the measurement in the message when the message
    names a cause.
18. **`test-all-killed-classification` read 76/77** — diagnosed as a stale-branch artifact (two
    commits had landed on `main` mid-session), not a defect; fixed by merging → 77/0.
    **Prevention:** before reading an off-by-one assertion count as a defect, check whether `main`
    moved.
19. **`rung2-rehearsal` went 71/0 → 70/1** — job-log masking placed inside the capture step consumed
    a queued `doppler` response and shifted the poll's attempt accounting. Lifted into its own step.
    **Prevention:** a step that shares a harness's mocked command queue must not gain a new call.
20. **Three claims I wrote that the panel falsified** — the emitter has **three** exit-2 paths, not
    two, and the third can EMIT (its own header names it); the filename pin ABORTed **31** arms, not
    25, and "including the must-PASS rows" was inverted; "no THIRD Sentry reader in this repo" is
    off by ~20 (the repo has ~23 Sentry call sites; the claim is true only of the endpoint family).
    **Prevention:** for every causal or universal sentence the diff ADDS, name the command that
    falsifies it and run it — each of these took one command.
21. **I bulk-toggled the task checkboxes.** Ticking Phases 0–4 in one replace marked task 0.3
    (migrate the floors to `gate-suite-harness.sh`) done when it was never attempted — and the stale
    "floor is 69" message the panel found is precisely the drift that migration prevents.
    **Prevention:** a checkbox is a claim; tick each one at the moment its work is verified.
22. **`rule-metrics-aggregate.sh` exits rc=5 and the local aggregate cannot be committed** — see the
    Problem section. **Prevention:** filed as a tracker; the local producer ADR-091 designates as
    authoritative is currently blocked by the repo's own hook suites.

## Measurements

- Rule budget: `[WARN] B_ALWAYS=46000 >= 44000` (`AGENTS.md=5489` + `AGENTS.rules.md=40511`),
  linter exit 0. Registry 46073 bytes / 105 rules, longest rule 600 chars. `constitution.md`:
  298 bullets. **The WARN tier is why this learning routes to a skill, not to `AGENTS.rules.md`.**
- Phase 1.6 token-efficiency: skipped (small diff).
- Redaction/allowlist scope, measured 2026-09-03: the capture step's Doppler config holds **160
  names, ~70 credential-shaped**, so the 11-name allowlist covers a small fraction — the tuple is a
  belt over the producer's `_clean` scrubbing, not the control. One tuple entry
  (`GIT_DATA_LUKS_KEY`) is inert at length 0 because it lives in a different config: **eleven names,
  ten controls.**

## Related

- [2026-07-06-aggregator-must-run-where-its-gitignored-input-lives.md](best-practices/2026-07-06-aggregator-must-run-where-its-gitignored-input-lives.md) — the failure ADR-091 exists to prevent, now observed with a different cause
- [2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md](2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md)
- [2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md](2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md)
- [2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md](2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md)
- [2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md](2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md) — orphan-suite class; `git-data-rung2-rehearsal.test.sh` is a new instance
