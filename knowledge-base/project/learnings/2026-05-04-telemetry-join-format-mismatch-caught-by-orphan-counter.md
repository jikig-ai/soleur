# Learning: orphan counter on a telemetry join surfaced its own producer's format bug

## Problem

PR #3124 added a per-Skill-call `PreToolUse` hook
(`.claude/hooks/skill-invocation-logger.sh`) that appends JSONL records to
`.claude/.skill-invocations.jsonl`, plus a monthly aggregator
(`scripts/skill-freshness-aggregate.sh`) that joins those records against
the skill inventory walked from `plugins/soleur/skills/*/SKILL.md` and
emits per-skill freshness records.

All 6 aggregator tests passed. All 6 hook tests passed. Reviewer agents
(10 of them) raised performance, schema, idempotency, and subshell issues.
None caught the actual semantic bug:

The hook logs `tool_input.skill`, which CC delivers as the
fully-namespaced form (`"soleur:plan"`). The inventory walk emits the
bare directory name (`"plan"`). The jq join keyed inventory by name and
looked up `$by_skill["plan"]`, which never matched `"soleur:plan"` —
**every real invocation was silently classified as `never_invoked`**, no
matter how recently it fired. The aggregator was effectively a no-op even
once a CI persistence bridge ships.

Tests passed because every test fixture used the bare-name form. The
hook emits the namespaced form. No test exercised the cross-stream
contract.

## Solution

Two-part fix:

1. **Normalize at the join.** Add a `bare` jq function that takes the
   last colon-split segment of a skill name. Key the lookup table by
   `bare`, and compute orphans against `bare`-mapped invocation names.
   This means `"soleur:plan"`, `"foo:plan"`, and `"plan"` all collapse
   to the same inventory key.

2. **Add a regression test that uses the production format of both
   streams.** Test 6 in `scripts/skill-freshness-aggregate.test.sh`
   feeds a JSONL with `"soleur:alpha"` (matched), `"beta"` (bare,
   matched), `"foo:gamma"` (matched), and `"unknown:zzz"` (correctly
   surfaces as orphan). Locks the contract.

The bug was discovered because PR review surfaced a
`pattern-recognition-specialist` finding that
`scripts/rule-metrics-aggregate.sh` warns when JSONL contains skills
absent from the inventory ("orphan"), and the new aggregator silently
dropped them. Mirroring that warning in `skill-freshness-aggregate.sh`
took 3 lines. Running it against the real `.claude/.skill-invocations.jsonl`
immediately reported `1 orphan: soleur:plan` — at which point the bug
was self-evident.

## Key Insight

**When a feature joins two telemetry streams, write at least one test
that uses each stream's production format.** Bare-name fixtures on both
sides of the join is a circular validation — the test confirms the
function does what the function does, not what the producers actually
emit.

**A polish-tier counter (orphan detection in summary) caught a P1
semantic bug that 10 review agents and 11 unit tests missed.** The
counter exists for a different reason (operational visibility into
renamed/deleted skills), but its surface area happens to overlap with
the missing contract test. This is "telemetry on telemetry": when
adding a derived metric, ask "what would surprising values of this
metric tell me about the feature itself?" — those questions tend to
expose contract bugs that test fixtures sanitize away.

**The same subshell-scoping bug pattern appeared in three places in
this session.** The production workflow's `filed=$((filed + 1))` inside
a `jq | while read` ran in a subshell (caught by review). My test
fixture's `ROOTS+=("$dir")` inside `make_root() { ... }` called via
`$(make_root)` ran in a subshell (caught immediately on inspection).
The fix shape is identical in both: hoist the mutation out of the
subshell — process substitution `< <(jq ...)` for the production
case, `ROOT=$(make_root); ROOTS+=("$ROOT")` for the test case. Bash
subshell scoping is a single class of bug with multiple aliases.

## Session Errors

1. **Telemetry stream format mismatch between hook and aggregator** —
   Recovery: namespace-normalize at the join + regression test.
   Prevention: when joining two streams, at least one test fixture per
   stream must use the production format observed in the wild, not a
   simplified bare-name placeholder.

2. **Test-fixture subshell-array gotcha (`ROOTS+=` inside `$(make_root)`)** —
   Recovery: hoist the array push to the parent shell.
   Prevention: when adding trap-based cleanup that depends on an array,
   ensure the array is mutated only in the parent shell — never inside
   `$()`, pipe stages, or `while` loops fed by pipes.

3. **Reviewer `code-quality` mis-classified `filed` subshell as
   "cap silently disabled"; `pattern-recognition` correctly identified
   it as "trailing log line wrong but cap intact via subshell-local
   `break`"** — Recovery: trust the more specific reviewer; verify
   semantics by re-reading the bash man page.
   Prevention: when two reviewers disagree on impact, run the failing
   path once before deciding which to trust.

## Related

- `scripts/rule-metrics-aggregate.sh` — the precedent that emits the
  orphan-rule warning that this learning mirrors.
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
  — pre-existing learning on multi-agent review's defect classes; this
  session adds a class the catalogue did not yet name (cross-stream
  format-contract drift, caught by polish-tier metric, not by review
  agents).

## Tags
category: integration-issues
module: skill-freshness, telemetry
