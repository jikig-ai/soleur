# Risk-tier panel scaling + fix-commit targeted rounds

Normative contract for (a) scaling the review panel to the declared risk tier and (b) reviewing post-panel fix commits with targeted seats. `review/SKILL.md` carries pointer lines only — this file is the single source for the rules below, pinned three ways by `plugins/soleur/test/review-tier-parity.test.ts`: this table ↔ `workflows/review.workflow.js` gating ↔ `scripts/fix-round-seats.sh` map arms. See ADR-267.

## Risk tier

The tier reuses the plan's `brand_survival_threshold` enum — no second vocabulary for one concept:

- `none` — plugin-internal / docs / tooling diffs with no user-facing blast radius
- `single-user incident` — a defect or breach visible to one user is brand-survival-relevant
- `aggregate pattern` — the failure mode is a class, not an instance

`undeclared` is a classifier parse state, never a tier: it resolves per the order below and is rejected by `emit-review-trailer.sh --risk-tier` like any other invalid token.

### Resolution order (first match wins)

1. **PR body** — a `**Brand-survival threshold:** <value>` line, or a `## User-Brand Impact` section carrying one.
2. **Linked plan** — frontmatter `brand_survival_threshold:`, or the plan's `## User-Brand Impact` line. ("Linked" = the plan path the PR body references.)
3. Neither source declares → `undeclared`.

Then the **fail-closed clamp** (mirrors preflight Check 6 Step 6.1 semantics): when the diff touches `SENSITIVE_PATH_RE` and the tier is `undeclared` — or is `none` without an explicit `threshold: none, reason: <non-empty>` scope-out — resolve `single-user incident` with `source: sensitive-path clamp`. The PR body is author-editable text, so a declared `none` is not trusted unconditionally on a sensitive diff. A `SENSITIVE_PATH_RE`-matching diff always carries `soleur:engineering:review:security-sentinel` regardless of tier.

`undeclared` with no sensitive-path hit resolves to `none` for panel purposes, reported as `source: undeclared`.

### Never scale below the declared tier

Review never spawns fewer seats than the resolved tier's row prescribes. When the declared tier exceeds what the diff's shape suggests (`single-user incident` on a docs-only diff), spawn the elevated set AND append a `mismatch` note to the summary — over-declaration is **reported**, never silently down-tiered. Repairing a wrong declaration is the plan-time threshold challenge's job (the `**Threshold decision (challengeable):**` line in `plan-issue-templates.md`), not review's.

## Seat scaling

| Tier | Base panel | Conditional/escalation seats | Fix-commit round |
|---|---|---|---|
| `none` (or undeclared, non-sensitive diff) | Class baseline, with {data-integrity, agent-native, performance} trigger-gated: each runs only when the diff touches a path its `fix-round-seats.sh` map arm covers — the map arm IS the predicate; there is no second table to drift. Floor: {git-history, pattern, architecture, security, code-quality} never shed. | Trigger-gated as today (test-design, semgrep/shellcheck, anti-slop, gdpr, rails, migration). | Targeted seats + one verification pass |
| `single-user incident` | Class baseline unconditional | + soleur:engineering:review:user-impact-reviewer; coverage consult unconditional at synthesis | Targeted seats; user-impact lens added when a fix touches user-facing paths |
| `aggregate pattern` | Class baseline unconditional + mandatory design-validity pass | + soleur:engineering:review:user-impact-reviewer; + structural-enumeration whenever guard-shaped; workflow `SKEPTICS=3` | Targeted seats + one verification pass; cap-2 escalation unchanged |

The `deep review` / `full review` override is unchanged and beats every row above.

## Reporting

Three surfaces:

1. The classification announce line gains `Tier: <value> (source: <pr-body|plan:<path>|sensitive-path clamp|undeclared>)`.
2. `### Review Agents Used` gains `**Risk tier:** <value> — seats spawned: <N> (class <class> baseline <B> + escalation <E>)`.
3. `emit-review-trailer.sh --risk-tier <none|single-user incident|aggregate pattern>` emits a `Reviewed-Risk-Tier:` line in the trailers paragraph (resolved values only — `undeclared` is rejected). **No consumer reads it** — the ADR-127 argument: recording a field whose key is already in main's history is cheap; adding it later is the expensive part. A `--fix-round` run attests `Reviewed-Coverage: full` **over the fix-commit range only**, plus `--agents-ran/--agents-expected` for the targeted seats — a targeted round never attests the whole branch.

## Fix-commit targeted round

Fix commits are the least-audited surface in the pipeline (learnings 2026-09-23, 2026-08-16, 2026-08-10 all measure defects landing *in* fixes), and re-running the full class panel per fix round is the cost this mechanism removes.

1. **Snapshot at panel spawn:** record `PANEL_SHA=$(git rev-parse HEAD)` when the full panel is dispatched.
2. **Seat set per fix round:** `{seats that reported the findings these commits close} ∪ {path-mapped seats} ∪ {conditional seats}`, resolved mechanically:

   ```bash
   bash <plugin-root>/skills/review/scripts/fix-round-seats.sh \
     --files "$(git diff --name-only "$PANEL_SHA"..HEAD)" \
     --finding-seats <seats from the dedup ledger>
   ```

   The script's path→seat map is the single source for both consumers: it also defines the `none`-tier trigger-gating predicates (the seat fires iff the diff touches a path its map arm covers). Add `soleur:engineering:review:security-sentinel` whenever the fix diff touches `SENSITIVE_PATH_RE` or adds guard/deny-shaped lines. A source-touching fix never resolves to zero seats — the script emits the `soleur:engineering:review:code-quality-analyst` floor on unmatched source paths; an empty fix diff emits nothing (`note: empty fix diff` on stderr) and legitimately spawns zero seats.
3. **Report-only spawn** against `git diff $PANEL_SHA..HEAD` — the FIX diff, not the branch diff.
4. **Cap two targeted rounds.** A third needed round escalates to the full class panel over the cumulative fix diff — an unbounded targeted loop is the treadmill this mechanism exists to prevent.
5. **One verification pass** after the last round: a single fresh-eyes verifier seat answers "does each fix commit close its finding, and did any fix introduce a defect in its own area?", plus the lead's affected-shard run (`scripts/test-all.sh`, `TEST_GROUP=affected`).
6. **Invocation:** `soleur:review <PR> --fix-round` (optionally `--since <sha>`) runs only the targeted round + verification pass — `soleur:one-shot` Step 5 calls this after its resolver-agent commits land. Round scope = commits since the caller-attested snapshot, else `git merge-base origin/main HEAD`. A rebase after the panel invalidates `PANEL_SHA`; the merge-base fallback exists for exactly that.

## Dedup-before-fixing ledger

§5 Step 1's "Remove duplicate or overlapping findings" becomes a required emitted artifact, produced **before any fix dispatch**:

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|

The canonical defect key is `defect-class + rolled-up root cause`, **not** file-scoped: a structural finding spanning N files ("same predicate copy at every call site") merges across files into one defect and one fix; the key is file-qualified only when the defect is genuinely file-local. The ledger is also the durable findings→seat carrier the targeted round's `--finding-seats` input reads — a fix commit closing a finding re-spawns the seat that reported it. The summary carries `dedup: <N raw> → <M unique>`; the workflow's mechanical `file::title` dedup stays as the cheap first pass and its report gains a `mergedGroups` count.
