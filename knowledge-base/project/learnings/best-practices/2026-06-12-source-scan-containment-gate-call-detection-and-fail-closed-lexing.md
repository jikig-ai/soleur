# Learning: a source-text containment/classification gate must detect by CALL site, lex comment/string-aware, and cover the whole egress surface

## Problem

#5072 asked for a CI gate that classifies every new Inngest `cron-*.ts` into a
containment class (hook-contained vs. direct-spawn vs. pure-TS) so a new cron
cannot ship with an unbounded shell/network egress surface. The plan prescribed a
straightforward **source-text scan**: detect "hook-contained" by an import-regex
(`/_cron-claude-eval-substrate|runClaudeEval/`), detect "direct-spawn" by
`/spawn\(/`, and grandfather a plan-enumerated set of 6 direct-spawn crons.

Three independent ways the prescribed approach was wrong — none caught by a GREEN
unit suite, all caught by tracing the live tree + multi-agent review:

1. **Import-presence ≠ containment.** 16 cron files matched the substrate
   import-regex, but only 12 are actually hook-contained. The other 4 import
   substrate *helpers* (`resolveClaudeBin`, `KILL_ESCALATION_MS`) or merely
   mention the module in a comment, yet `cron-daily-triage` /
   `cron-follow-through-monitor` spawn claude **directly** (own `CLAUDE_CODE_FLAGS`,
   not via the contained `spawnClaudeEval()` wrapper). The plan's XOR-membership
   assertion would have made the gate RED on the clean tree, AND the plan's
   "6 direct-spawn crons" enumeration (built by *excluding* any substrate
   importer) silently dropped those two — the real set is 8.

2. **A regex is not a lexer (fail-OPEN).** A naive `/\/\*[\s\S]*?\*\//` block-comment
   stripper treats a `/*` inside a `//` comment as a real block-open and lazily
   consumes through to the `*/` inside a cron-schedule string like `"0 */4 * * *"`,
   swallowing every line between them (observed collapsing ~96% of
   `cron-inngest-cron-watchdog.ts`). A future cron with that shape + a `spawn(`
   in the swallowed span classifies pure-TS → ships uncontained. The gate exists
   to fail CLOSED; the stripper made it fail OPEN.

3. **`spawn(`-only detection misses the rest of the egress surface (fail-OPEN).**
   A cron egressing via `execFile`/`execSync` or a dynamic
   `await import("node:child_process")` classifies pure-TS. Live precedent: the
   substrate's own `_cron-safe-commit.ts` reaches git via dynamic-import +
   `execFile`. The inverse assertion (pure-TS ⇒ no map entry) does NOT backstop
   this — it only catches *stray* entries, never *missing* egress.

## Solution

- **Classify by CALL site, not import.** `substrate-contained` ⇔ the file *calls*
  `spawnClaudeEval(`, detected on comment/string-stripped code — not "imports the
  module." This precisely partitions the 12 mapped crons and leaves helper-importers
  in their true class.
- **Lex, don't regex, when neutralizing comments/strings.** Replaced the regex
  stripper with a single-pass char scanner tracking `code/line/block/single/double/
  template` state. A `*/` inside a string can no longer terminate a comment; a
  `/*` inside a `//` comment can no longer open one.
- **Two scan surfaces, because the two signals live in different lexical places.**
  CALL tokens (`spawn(`, `execSync(`) are CODE → scan with strings **blanked** so a
  `spawn(` inside a string literal does not false-trigger. The `child_process`
  module specifier is intrinsically a STRING → scan comments-stripped-but-strings-
  **kept**, so a dynamic/aliased import is still seen while a comment-only mention
  (`cron-skill-freshness`) is not. Bare `exec(`/`fork(` are excluded
  (`RegExp.prototype.exec`, stray `.fork(` would false-positive a pure-TS cron).
- **Add the gate's own tripwires:** an adversarial-strip RED row (asserts
  `"/*"; spawn("git"); "*/"` → direct-spawn), a non-degenerate class-distribution
  guard (catches a vacuous all-pure-TS pass), and a grandfather-integrity assertion
  (every grandfather entry still classifies direct-spawn). These mirror the
  vacuous-pass guards in the sibling `function-registry-count.test.ts`.
- **Document the single-file-scope limitation honestly:** egress reached through a
  NEW shared helper that wraps spawn/exec is invisible to a per-file scanner. Today
  every such helper is shared, fixed-argv, already-contained infra; if that changes,
  add the helper symbol to the detection regex or maintain a helper deny-list.

## Key Insight

For a **source-text scan that is a security control**, three failure modes
compound and none show up in a GREEN suite — only in tracing the live corpus and
in adversarial multi-agent review:

1. **Detect the behavior, not its proxy.** "Imports module X" is a proxy for
   "uses X's contained entrypoint." Match the *call*, not the *import* — a file can
   import a helper and still take the dangerous path itself.
2. **String/comment neutralization for a security scan must be a stateful lexer,
   not a regex** — a regex stripper bridges across string literals and fails OPEN.
   And it needs **two surfaces**: strings-blanked for call tokens, strings-kept for
   module specifiers (which are themselves strings).
3. **Enumerate the whole egress family** (`spawn`, `spawnSync`, `execFile*`,
   `execSync`, dynamic `child_process` import) — not just the one verb the issue
   names. A `spawn(`-only gate is a `spawn(`-only gate, not a containment gate.

Plan-quoted counts/enumerations are preconditions to re-derive at work time
([[2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited]]) — here the plan's
"6 direct-spawn crons" was a stale import-exclusion artifact; the live grep said 8.

## Session Errors

- **Plan's direct-spawn enumeration (6) was wrong (actual 8).** The plan's Phase-0
  command excluded substrate importers, dropping `cron-daily-triage` /
  `cron-follow-through-monitor`. Recovery: re-derived the set by call-detection on
  the live tree. Prevention: classify by call site; treat plan enumerations as
  preconditions (existing work-rule).
- **Plan's "gate cannot mis-classify the current tree" claim was false** (16 import
  matches vs 12 mapped). Recovery: switched detection import→call. Prevention: this
  learning + route-to-definition bullet on plan/work.
- **Two P1 fail-open gaps surfaced only at multi-agent review, not the GREEN suite**
  (block-comment collapse; spawn-only detection). Recovery: char-scanner lexer +
  exec/child_process surface + adversarial RED rows. Prevention: for a source-scan
  security gate, require an adversarial-strip test and a multi-agent review pass.
- **JSDoc comment containing literal `*/` broke tsc (TS1109).** Recovery: reworded
  the comment to describe the token sequence in words. Prevention: never embed a
  literal `*/` inside a block comment that documents comment parsing. One-off.
- **First exec-family widening anchored `child_process` on strings-blanked code**
  (module specifiers are strings → missed). Recovery: split into two scan surfaces;
  the new adversarial test caught it before commit. Prevention: remember that import
  specifiers are string literals — string-blanking hides them.
- **ugrep `\b(group)\s*\(` returned 0 in a bash verification loop.** Recovery:
  switched to a literal pattern via `sed`-strip + `grep -E`. Prevention: known
  bash/ugrep quirk — avoid `\b(` alternation groups in host-shell greps. One-off.

## Tags
category: best-practices
module: apps/web-platform/server/inngest
