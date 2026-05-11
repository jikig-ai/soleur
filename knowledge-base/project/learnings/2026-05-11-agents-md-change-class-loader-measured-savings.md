# Learning: AGENTS.md change-class loader — measured savings vs Phase 1 estimate

**PR:** #3496 · **Issue:** #3493 · **Date:** 2026-05-11

## Problem

The single-file `AGENTS.md` (24,618 bytes) loaded into every turn via `CLAUDE.md`'s `@AGENTS.md` reference. ETH Zurich's per-turn overhead measurement (10–22%) put this at the high end of the price/latency curve. Class-aware loading was proposed to send only the rules a given session's change-set actually depends on, with a permanent always-loaded `core` for compliance-critical rules.

## Solution

Three-sidecar split + SessionStart hook + slug-only pointer index:

- `AGENTS.md` (4,303 B) → pointer index, loaded every turn.
- `AGENTS.core.md` (17,545 B) → injected via SessionStart additionalContext on every session.
- `AGENTS.docs.md` (1,994 B) + `AGENTS.rest.md` (4,925 B) → injected per change-class.
- `LOADER_FAIL_CLOSED=1` + missing-sidecar fail-safe + 3-field manifest.

## Measured savings vs plan estimate

| Metric | Pre-migration | Post-migration | Δ |
|---|---|---|---|
| Per-turn AGENTS load | 24,618 B | 4,303 B | **−82.5 %** |
| Always-loaded total (index + core) | 24,618 B | 21,848 B | −11.3 % |
| First-turn cost, docs-only session | 24,618 B | 23,842 B | −3.2 % |
| First-turn cost, code/infra session | 24,618 B | 26,773 B | +8.8 % |
| First-turn cost, mixed (fail-closed) | 24,618 B | 28,767 B | +16.9 % |

The headline 82.5 % per-turn reduction is real (one fewer `@AGENTS.md` re-render per turn after the SessionStart prefix lands in the cached prefix). The first-turn cost is slightly worse for any session that loads a sidecar — the migration trades a one-time session-start cost for a permanent per-turn savings, which becomes positive after ~3 turns on a stable prompt cache.

## Classifier accuracy (5-PR spot-check)

`tools/migration/classify-rules.sh` walked the 5 most recent merged PRs at migration time. The spot-check used the same regex set that ships in the live hook:

| PR | Predicted class | Files (first 3) |
|---|---|---|
| #3543 | mixed | .github/actions/, .github/workflows/, knowledge-base/ |
| #3538 | docs-only | knowledge-base/, knowledge-base/project/ |
| #3537 | docs-only | plugins/soleur/skills/review/SKILL.md |
| #3534 | docs-only | knowledge-base/, plugins/soleur/skills/ |
| #3524 | mixed | .claude/hooks/, .github/workflows/, code+docs |

3/5 docs-only, 2/5 mixed. Mixed-frequency = 40 %; for those sessions the loader provides no savings (fail-closed loads everything), but operates as a safety floor. The plan's worst-case ("if >50 % of sessions are mixed, savings are minimal but safety floor holds") was not hit by this small sample.

## Edge cases hit during implementation

1. **Initial pointer format was too verbose.** Each pointer with prose + `→ AGENTS.<class>.md` produced an 11,183 B index — 2× the 5 k target. Slug-only format (`- [id: <slug>] → core`) plus dropping enforcement tags from the index brought it to 4,303 B. Trade-off: index is no longer human-readable as a quick rules summary; the slug names are dense enough to function as the summary, and the full body is one hop away in the sidecar.

2. **`is_pointer_line` regex was too loose.** First-pass heuristic (any ` → ` substring) produced 7 false positives on the live registry — rule bodies that quote `→` in prose (e.g. `Browser tasks → Playwright MCP`). Tightened to `^- \[id: \w+\](?:\s+\[[^\]]+\])*\s+→\s+(core|docs|rest)\s*$` with end-of-line anchor. Line-shape match is the right invariant; substring match is not.

3. **`hook_resolves` rejected any `/` in tag value.** Pre-existing bug in `scripts/lint-agents-enforcement-tags.py` masked because lefthook hadn't re-run on the rule that introduced it (`cq-test-fixtures-synthesized-only` from PR #3121 has `[hook-enforced: .github/workflows/secret-scan.yml]`). Fixed inline: path-form tokens now resolve from repo root; `..` still rejected.

4. **Fail-safe stamp interpolation lost spaces.** `${CLASSES// /+}` substituted spaces in the annotated string `core docs-only rest (fail-safe: sidecar missing)` → `core+docs-only+rest+(fail-safe:+sidecar+missing)`. Operator stamp lost readability and the test grep missed the annotation. Split into `CLASSES_DISPLAY` (just the class names) plus a separate `FAIL_SAFE_NOTE` suffix.

5. **The split-sidecars migration script was non-idempotent on first try.** Reading from working-tree `AGENTS.md` meant a second run read the pointer-index version and produced empty sidecars. Switched to `git show HEAD:AGENTS.md` as the source-of-truth. Lesson: any migration that rewrites its own input must read from a stable source (HEAD, a backup, or a pre-flight checkpoint).

## Telemetry blind-spot acknowledgment

The 3-field manifest (`timestamp`, `change_class`, `rule_ids_loaded`) is post-hoc evidence only. It tells us which rules were *available* in the prompt, not which rules the agent actually *consulted* or which rules *fired* for the work the session produced. Cross-referencing rule_ids_loaded against the rule-incident telemetry stream (`./scripts/rule-metrics-aggregate.sh`) is the only way to estimate whether a class-gated rule's absence ever actually mattered. Until the loader logs pivot events (deferred to v2), mid-session class drift is invisible.

## Pivot-detector-cut rationale + observed frequency

The v1 plan included a PreToolUse pivot detector (~250 LOC + 50–200 ms × 100 tool-calls/session latency tax). Plan-review (DHH + code-simplicity) converged on cutting it. CPO sign-off on PR #3496 affirmed that v2's substitute — fail-closed `mixed` default + SessionStart stamp + operator `LOADER_FAIL_CLOSED=1` escape hatch — meets the `single-user incident` threshold, conditional on (a) mandatory `user-impact-reviewer` at PR-time review, (b) this learning recording observed pivot frequency, (c) any future `core > 18 k` redistribution demoting only `wg-*`, never `hr-*`.

**Observed pivot frequency during this PR's own sessions:** 0 unannounced pivots. The work that landed this migration was itself a docs+code mixed session (the loader/script/test/skill edits spanned `.claude/`, `scripts/`, `plugins/soleur/skills/compound/`, and knowledge-base). The loader's `mixed` default fired correctly on the first SessionStart; no operator override was needed. n=1 is not a statistical justification — the post-merge plan is to revisit after 4 weeks of real-session data on `main`.

## Session Errors

The 11-agent `/soleur:review` pass on PR #3496 surfaced 7 P1 + 8 P2 findings on this PR's own implementation. Capturing them here so the failure modes are documented even though every finding was fixed inline.

- **Hook `set -e` + mid-script `mkdir`/`jq` could exit non-zero before emitting `additionalContext`** — Recovery: dropped `set -e`, added `trap ERR` + `emit_core_only_fallback`. Prevention: any SessionStart hook that emits the prompt-injection envelope MUST guarantee non-empty output on any error path; `set -e` between classifier and emit is a `single-user incident` vector.
- **Manifest path traversal via `session_id`** — Recovery: sanitize KEY to `[A-Za-z0-9._-]`, refuse `.`/`..`/empty. Prevention: any envelope field used as a filename component MUST be sanitized; substring match against the parent dir is insufficient (e.g., `../../foo` escapes anyway).
- **`cwd` accepted any writable dir** — Recovery: assert `git rev-parse --is-inside-work-tree`. Prevention: SessionStart hooks MUST verify the resolved `REPO_ROOT` is inside a git worktree before writing to `$REPO_ROOT/.claude/.session-manifests/`.
- **In-stamp hint `'{}'` would re-classify wrong tree** — Recovery: embed resolved `$REPO_ROOT` via printf. Prevention: any operator command embedded in agent-visible text MUST be self-contained; `$PWD` is unsafe across Bash tool calls because CWD resets.
- **`docs` vs `docs-only` slug drift across 6 surfaces** — Recovery: aligned everywhere; new `tests/scripts/test_classifier_regex_parity.sh` asserts DOCS_RE/CODE_RE/INFRA_RE byte-equality. Prevention: cross-stream format contracts (producer/consumer pair sharing a token vocabulary) MUST have a parity test from day 1, not retro-fitted after review. Same defect class as `knowledge-base/project/learnings/2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md`.
- **Rebase against origin/main aborted on 10 commits × 230-file divergence** — Recovery: hand-import the GDPR rule + minimum supporting infrastructure (lefthook entry + script). Prevention: for branches significantly behind main, do NOT attempt a full `git rebase origin/main` to pull in one rule — cherry-pick the specific files; rebase is for cosmetic fast-forwards, not feature integration.
- **Initial GDPR rule import added rule body without supporting infrastructure** — Recovery: `lint-agents-enforcement-tags.py` caught it; reverted and re-imported with the minimum supporting set. Prevention: when importing a rule that carries `[hook-enforced: lefthook X]` or `[skill-enforced: <skill>]`, verify the referenced enforcer exists in the same patch.
- **CPO sign-off condition #3 ("only wg-* may be demoted from core") was prose-only** — Recovery: added `collect_residency_metadata` to lint_union + 2 tests asserting `hr-*` and `[compliance-tier]` rules live in AGENTS.core.md. Prevention: any prose-only invariant in a CPO sign-off comment MUST be mechanically enforced (linter, hook, or test) within the PR that introduces it — verbal acknowledgment is not a fix.
- **CWD persisted across Bash calls in unexpected ways** — Recovery: re-`cd` into the worktree absolute path explicitly. Prevention: already documented in AGENTS.md (`cq-for-local-verification-of-apps-doppler` and related); rule applies broadly, not just to Doppler.
- **`split-sidecars.sh` non-idempotent on first revision** — Recovery: switched source to `git show <ref>:AGENTS.md` + added pointer-form guard. Prevention: any migration script that rewrites its own input MUST read from a stable source (HEAD blob, backup file, or remote ref) — never from the working tree it's about to mutate.
- **`is_pointer_line` substring match `→` produced 7 false positives** — Recovery: anchored line-shape regex with class-token alternation. Prevention: when detecting line "shape" (pointer vs body, header vs prose), use full-line anchored regex with literal end-of-line, not substring presence.
- **Live `lint-agents-enforcement-tags.py` pre-existing failure was masked** — `[hook-enforced: .github/workflows/secret-scan.yml]` on `cq-test-fixtures-synthesized-only` never resolved because `hook_resolves` rejected `/` in token; lefthook didn't fire the rule on the original PR landing. Recovery: extended `hook_resolves` to accept path-form tokens from repo root. Prevention: when a linter has a search-vs-resolve split (`hook_resolves`), audit existing tags against both code paths before assuming "lint passes today" means "lint is complete."

Cumulative failure-mode taxonomy: 5 are **security/blast-radius** (hook-crash, path-traversal, cwd-untrusted, hint-injection, prose-only-invariant), 4 are **format/contract drift** (slug-drift, regex-mirror, idempotency-of-self-rewrite, line-shape-heuristic), 3 are **integration friction** (rebase abort, partial-import, CWD-persistence). The security-class items are the load-bearing ones — `user-impact-reviewer` + `security-sentinel` were essential and would have been omitted by a `class=non-code` classification.

## Key Insight

**Per-turn savings ≠ per-session savings.** The architecture trades a one-time session-start cost (sidecars added to additionalContext) for a permanent per-turn savings (smaller `@AGENTS.md` re-render). Anthropic's prompt cache amortizes the first-turn additionalContext over the rest of the session; the per-turn cost is what the operator pays in latency × turns. Optimising for per-turn cost is the correct objective even when it makes the first-turn total worse.

## Tags

`agents-md`, `sidecar`, `session-start-hook`, `token-efficiency`, `prompt-cache`, `compliance-tier`, `migration`, `idempotency`, `linter`, `bash-test-pattern`
