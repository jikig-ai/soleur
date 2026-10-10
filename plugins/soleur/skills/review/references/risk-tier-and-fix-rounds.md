# Risk-tier panel scaling + fix-commit targeted rounds

Normative contract for (a) scaling the review panel to the declared risk tier and (b) reviewing post-panel fix commits with targeted seats. `review/SKILL.md` carries pointer lines only — this file is the single source for the rules below, pinned three ways by `plugins/soleur/test/review-tier-parity.test.ts`: this table ↔ `workflows/review.workflow.js` gating ↔ `scripts/fix-round-seats.sh` map arms. See ADR-267.

`<plugin-root>` in the commands below resolves to the root of the plugin directory you read this file from — the absolute path prefix up to and including the plugin root (e.g. `/path/to/plugins/soleur`). Resolve it to an absolute path; if you cannot name one, stop — never substitute a CWD-relative guess.

## Risk tier

The tier reuses the plan's `brand_survival_threshold` enum — no second vocabulary for one concept:

- `none` — plugin-internal / docs / tooling diffs with no user-facing blast radius
- `single-user incident` — a defect or breach visible to one user is brand-survival-relevant
- `aggregate pattern` — the failure mode is a class, not an instance

`undeclared` is a classifier parse state, never a tier: it resolves per the order below and is rejected by `emit-review-trailer.sh --risk-tier` like any other invalid token.

### Resolution order (first match wins)

1. **PR body** — a `**Brand-survival threshold:** <value>` line, or a `## User-Brand Impact` section carrying one.
2. **Linked plan** — frontmatter `brand_survival_threshold:`, or the plan's `## User-Brand Impact` line. "Linked" = the plan path the PR body references — OR, when the body names none, the frontmatter of any `knowledge-base/project/plans/*.md` this diff adds/modifies (one-shot always commits its plan in the diff).
3. Neither source declares → `undeclared`.

Then the **fail-closed clamp** (mirrors preflight Check 6 Step 6.1 semantics): when the diff touches `SENSITIVE_PATH_RE` and the tier is `undeclared` — or is `none` without an explicit `threshold: none, reason: <non-empty>` scope-out — resolve `single-user incident` with `source: sensitive-path clamp`. The PR body is author-editable text, so a declared `none` is not trusted unconditionally on a sensitive diff. A `SENSITIVE_PATH_RE`-matching diff always carries `soleur:engineering:review:security-sentinel` regardless of tier.

`undeclared` with no sensitive-path hit resolves to `none` for panel purposes, reported as `source: undeclared`.

### Never scale below the declared tier

Review never spawns fewer seats than the resolved tier's row prescribes. When the declared tier exceeds what the diff's shape suggests (`single-user incident` on a docs-only diff), spawn the elevated set AND append a `mismatch` note to the summary — over-declaration is **reported**, never silently down-tiered. Repairing a wrong declaration is the plan-time threshold challenge's job (the `**Threshold decision (challengeable):**` line in `plan-issue-templates.md`), not review's.

## Seat scaling

| Tier | Base panel | Conditional/escalation seats | Fix-commit round |
|---|---|---|---|
| `none` (or undeclared, non-sensitive diff) | Class baseline, with {data-integrity, agent-native, performance} trigger-gated: each runs when the diff touches a path its `fix-round-seats.sh` map arm covers (checked mechanically) OR the classifier reports the surface — the path match is the floor; a model report can add a surface, never shed a mechanically-matched one. Floor: {git-history, pattern, architecture, security, code-quality} never shed. | Trigger-gated as today (test-design, semgrep/shellcheck, anti-slop, gdpr, rails, migration). | Targeted seats + one verification pass |
| `single-user incident` | Class baseline unconditional | + soleur:engineering:review:user-impact-reviewer; coverage consult unconditional at synthesis | Targeted seats; the user-impact lens returns via the reporting-seat union (it has no path arm — lead judgment may add it on a user-facing fix) |
| `aggregate pattern` | Class baseline unconditional + mandatory design-validity pass | + soleur:engineering:review:user-impact-reviewer; + structural-enumeration whenever guard-shaped; workflow `SKEPTICS=3` | Targeted seats + one verification pass; cap-2 escalation unchanged |

The `deep review` / `full review` override is unchanged and beats every row above.

## Reporting

Three surfaces:

1. The classification announce line gains `Tier: <value> (source: <pr-body|plan|sensitive-path clamp|undeclared>)`.
2. `### Review Agents Used` gains `**Risk tier:** <value> — seats spawned: <N> (class <class> baseline <B> + escalation <E>)`.
3. `emit-review-trailer.sh --risk-tier <none|single-user incident|aggregate pattern>` emits a `Reviewed-Risk-Tier:` line in the trailers paragraph (resolved values only — `undeclared` is rejected). **No consumer reads it** — the ADR-127 argument: recording a field whose key is already in main's history is cheap; adding it later is the expensive part. A `--fix-round` run emits **different keys** — `Reviewed-Fix-Round:` carrying the round's seat coverage and `Reviewed-Fix-Range: <since>..<head>` scoping it to the fix commits — and NEVER `Reviewed-Coverage:`: a targeted round covering `full` over the fix range would misread as branch-level coverage on ship's merge gate, and the main trailer's idempotence guard would swallow it anyway.

## Fix-commit targeted round

Fix commits are the least-audited surface in the pipeline (learnings 2026-09-23, 2026-08-16, 2026-08-10 all measure defects landing *in* fixes), and re-running the full class panel per fix round is the cost this mechanism removes.

1. **Snapshot at panel spawn:** record `PANEL_SHA=$(git rev-parse HEAD)` when the full panel is dispatched.
2. **Seat set per fix round:** `{seats that reported the findings these commits close} ∪ {path-mapped seats} ∪ {conditional seats}`, resolved mechanically:

   ```bash
   bash <plugin-root>/skills/review/scripts/fix-round-seats.sh \
     --files "$(git diff --name-only "$PANEL_SHA"..HEAD)" \
     --finding-seats <seats from the dedup ledger>
   ```

   The script's path→seat map is the single source for both consumers: it also defines the `none`-tier trigger-gating predicates (the seat fires iff the diff touches a path its map arm covers). Add `soleur:engineering:review:security-sentinel` whenever the fix diff touches `SENSITIVE_PATH_RE` — that arm is mechanical — OR adds guard/deny-shaped lines, which is lead judgment (the script maps paths only). A source-touching fix never resolves to zero seats — the script emits the `soleur:engineering:review:code-quality-analyst` floor on unmatched source paths, and lists them on stderr as `unmapped-paths:`; an empty fix diff emits nothing (`note: empty fix diff` on stderr) and legitimately spawns zero seats.
3. **Report-only spawn** against `git diff $PANEL_SHA..HEAD` — the FIX diff, not the branch diff. **Tally (#9403):** fix-round seats are review seats — `gate seats <N>` (N = the resolved seat count) before dispatch and `incr seats <N>` after, on the branch ledger; a `STOP` verdict is the classified-stop path (write `status: budget-capped` + `budget-capped: seats=<n>/<cap>` to the feature's `session-state.md` and halt — do not silently shrink the round).
4. **Cap two targeted rounds.** A third needed round escalates to the full class panel over the cumulative fix diff — an unbounded targeted loop is the treadmill this mechanism exists to prevent.
5. **One verification pass** after the last round: a single fresh-eyes verifier seat answers "does each fix commit close its finding, and did any fix introduce a defect in its own area?", plus the lead's affected-shard run (`scripts/test-all.sh`, `TEST_GROUP=affected`).
6. **Invocation:** `soleur:review <PR> --fix-round --since <sha>` runs only the targeted round + verification pass — `soleur:one-shot` Step 5 calls this after its resolver-agent commits land. `--since` is the panel snapshot; when it is absent (a bare invocation, or a rebase invalidated it) recover the base as **the parent of the oldest `review:`/`fix`-subject commit since the merge-base, else the merge-base itself** — and report which base was used. The fix round attests via `emit-review-trailer.sh --fix-round --since <base>` (`Reviewed-Fix-Round:`/`Reviewed-Fix-Range:` keys — never `Reviewed-Coverage:`). The range's effective head is derived by attestation-TRAILER presence, never by `review:`-prefixed subjects — `review: <summary> (P<N>)` is this repo's prescribed fix-commit subject, so a subject filter silently excludes real fixes. A standalone/fresh-session invocation has no access to the prior session's dedup ledger — without it the round degrades to path-mapped seats only (no `--finding-seats` union); that is the known, fail-safe direction and should be reported. A fix round attests ONLY via `--fix-round` keys: the branch-level `Reviewed-By-Soleur`/`Reviewed-Coverage` trailer must already exist from the main panel — absent, that is the anomaly (a fix round without a panel), report it, never emit a main trailer for a targeted round. Its commit subject is `review-fix-round:`, deliberately NOT matching the merge gate's legacy `review:` evidence regex — a targeted round is not branch-level review evidence.

## Briefing fix agents and seats

Two lessons from #9448 belong in every fix-agent and review-seat brief (full account: `knowledge-base/project/learnings/2026-10-04-an-allow-list-of-line-shapes-is-not-a-closed-sequence-and-a-text-matching-hook-stops-delegated-agents-silently.md`):

- **A Bash call whose TEXT contains `terraform apply` — even inside a heredoc fixture — is deferred by `prod-write-defer-gate.sh`, and a spawned agent cannot approve it, so it stops silently with no report.** Tell agents to write such files with the Write tool, run them with a short Bash command, and report a deferral instead of stopping. Four silent stops on #9448.
- **A per-line allow-list is not a closed sequence.** A guard whose property is "nothing can skip or alter X" must be pinned by index, count and balance (each required statement once, in order, balanced `if`/`fi`, nothing after the last `fi`), with executed mutants each shown to defeat the guarded thing when run unchecked. The first allow-list on #9448 was bypassed by four one-line edits that were each a permitted shape.
- **Brief an adversarial seat defensively, or its safety classifier may stop it with no report.** "Construct an edit that passes the suite and still leaks the token" ended a fix-round seat on #9474 with nothing delivered. Ask instead for: re-run the exact repro from your own prior report against the fixed tree, read each new predicate and name its gap (line number, no working payload), and verify behaviour with the suite's own stub harness. The lead mutation-tests the named gaps. See `knowledge-base/project/learnings/2026-10-04-a-spelling-list-guard-was-bypassed-two-rounds-running-and-the-loop-i-added-to-close-it-did-nothing.md`.
- **Two review-environment traps (#9505).** (1) The guardrail hook refuses writes into the shared git dir (`$(git rev-parse --git-dir)` resolves under the bare checkout) whenever other worktrees exist, so a fix brief cannot be persisted there: write it to the session scratchpad under a lead-unique name and re-derive from the PR if the session is lost. (2) a `TEST_GROUP=affected` run of `scripts/test-all.sh` queues behind every other worktree's full-gate run (`LOCK_WAIT_HEARTBEAT ... position=N of 7200s`) and the runner flags a commit made during its run as a suite writing to the repo: read the runner's `--capacity` verdict first and, if it is queued, stop it and rely on the targeted suites rather than let it race a fix commit. See `knowledge-base/project/learnings/2026-10-05-the-advice-i-added-to-the-abort-message-satisfied-the-assertions-written-against-it.md`.

- **Re-attach before the first commit after a panel returns, and test the branch name for EMPTY.** Report-only seats still run `git checkout --detach`, and `git branch --show-current && git commit …` does not stop on a detached HEAD because the empty output exits 0 (#9584: a fix commit landed detached). Guard with `[ -n "$(git branch --show-current)" ] || { echo DETACHED; exit 1; }`; recover with `git branch -f <branch> HEAD && git switch <branch>`. See `knowledge-base/project/learnings/2026-10-06-a-truncated-sweep-blamed-the-nav-drawer-and-a-redundant-alternative-hid-a-regression.md`.
- **A brief that asks a seat (or the lead's own battery) to flip a line inside a helper that sends signals or removes files carries the PID-namespace rule.** Run every mutant through the `run-isolated` verb (a mutant that exits 125 with `RUN_IN_PID_NAMESPACE_REFUSED` is `UNVERIFIED-NO-NAMESPACE`); a report-only seat reasons about the line and reports, and the lead mutation-tests the named gap through the verb. The command, the refusal rule and the limits: [work-scratch-sandboxes.md](../../work/references/work-scratch-sandboxes.md).

## Dedup-before-fixing ledger

§5 Step 1's "Remove duplicate or overlapping findings" becomes a required emitted artifact, produced **before any fix dispatch**:

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|

The canonical defect key is `defect-class + rolled-up root cause`, **not** file-scoped: a structural finding spanning N files ("same predicate copy at every call site") merges across files into one defect and one fix; the key is file-qualified only when the defect is genuinely file-local. The ledger is also the durable findings→seat carrier the targeted round's `--finding-seats` input reads — a fix commit closing a finding re-spawns the seat that reported it. `reporting seat(s)` values may be the leaf form, the canonical id (`soleur:engineering:review:security-sentinel`), or a workflow dimension key (`security`) — the script normalizes all three to the leaf; anything else is dropped with an `unknown-seat:` stderr warning. The summary carries `dedup: <N raw> → <M unique>`; the workflow's mechanical `file::title` dedup stays as the cheap first pass and its report gains a `mergedGroups` count.
