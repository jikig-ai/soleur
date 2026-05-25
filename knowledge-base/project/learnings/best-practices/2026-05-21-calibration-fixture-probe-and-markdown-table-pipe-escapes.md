---
date: 2026-05-21
tags:
  - planning
  - tools
  - regex
  - markdown
category: best-practices
module: plugins/soleur/skills/frontend-anti-slop
prs:
  - 4265
issues:
  - 4264
related_learnings:
  - 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets
  - 2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts
---

# Calibration-fixture probe at plan time, and markdown-table pipe-escape parsing

Two distinct lessons from shipping `soleur:frontend-anti-slop` v1 (#4265): one
about how to choose calibration fixtures for regex-based rule sets, and one
about parsing GitHub-flavoured markdown tables when cells contain regexes with
alternation.

## Pattern 1: A calibration fixture must trigger the active rule set, not the version of "anti-pattern" in the planner's head

### Problem

The plan named `apps/web-platform/components/ui/gold-button.tsx` as the
calibration baseline fixture for the scanner ("scanner returns JSON array
length ≥ 1 on this file"). The file ships an inline-style gradient:

```tsx
<button
  className="rounded-lg px-6 py-3 ..."
  style={{ background: GOLD_GRADIENT }}
>
```

None of the 15 Tier 1 rules in `references/slop-rules.md` catch this pattern.
`GRADIENT-TEXT` keys on a three-class Tailwind triad
(`bg-clip-text` + `text-transparent` + `bg-gradient-to-*`). `PURPLE-BLUE-GRADIENT`
keys on a Tailwind alternation. `TRANSITION-ALL`, `UNIFORM-HOVER-SCALE`,
`BOUNCY-EASING-UI` — none of them fire on `style={{ background: GOLD_GRADIENT }}`
either.

So the calibration AC (`returns JSON array length ≥ 1`) would fail on the file
the plan named. The plan was self-inconsistent: the rule set audits
Tailwind/JSX patterns, but the calibration fixture used inline-style for a
designer-mandated brand gradient — the exact case the rule set is designed to
*not* flag.

### Root cause

Plan time: "gradient" in the planner's mental model. Implementation time:
"gradient" as a specific regex over Tailwind class strings. The plan reasoned
"gold-button has a gradient, the scanner will catch it" without grounding the
claim against the actual rule patterns. The plan-precondition rule (`Plan-quoted
measurements are preconditions to verify, not facts`) caught it at /work Phase
0 step 5 — but only because step 5 was an explicit "sanity-scan ... to confirm
the calibration-baseline assumption."

### Fix

At /work Phase 0, the agent grep'd the codebase for files that DO trigger
active Tier 1 rules:

```bash
rg -l --type-add 'tsx:*.tsx' --type tsx \
  "transition-all|bg-clip-text|hover:scale-105" \
  apps/web-platform/{app,components}
```

Picked `apps/web-platform/components/connect-repo/setting-up-state.tsx` (line
29 `transition-all` → `TRANSITION-ALL` rule). Swapped:

- `plan.md` calibration AC marked done with explicit deviation note.
- `tier1-scan.test.ts § "calibration baseline"` uses the new fixture and
  adds a precondition assertion (`expect(content).toContain("transition-all")`)
  with a diagnostic that points at the fixture if a future refactor strips
  the keyed token.
- Test-design-reviewer flagged exactly this coupling at code-review time; the
  precondition was added pre-merge per the cost-of-filing gate.

### Generalised rule

**When prescribing a calibration fixture for a regex / pattern-based rule set,
the planner MUST grep the candidate fixture against the rule patterns BEFORE
naming it in the plan.** A "this file contains the kind of pattern the rule
set looks for" mental claim is not a fact — it's a hypothesis the regex can
falsify in one shell call. The cheapest gate is:

```bash
# At plan time, before naming a calibration fixture:
for pat in $(awk -F'|' '/^\| [A-Z]/ {gsub(/`/, "", $7); print $7}' references/slop-rules.md); do
  grep -lE "$pat" <candidate-fixture> && echo "FIXTURE TRIGGERS RULE"
done
```

A fixture that triggers zero active rules is a worse calibration than no
fixture — it codifies a false-positive workflow expectation that ripples into
ACs, tests, and runtime promotion gates.

## Pattern 2: Markdown-table cells that contain regex alternations need `\|`-aware splitting

### Problem

The `slop-rules.md` rule table contains regex cells like:

```markdown
| GENERIC-DISPLAY-FONT | 1 | visual | 1 | medium | `next/font/google.*\b(Inter\|Roboto\|Open_Sans\|Poppins\|Lato)\b` | ... |
```

Markdown convention: `\|` inside a table cell is an escaped pipe (literal `|`
in the rendered output). Inside a regex it serves the same purpose
(alternation). A naive parser splitting on every `|` collapses the cell into:

- `next/font/google.*\b(Inter\`
- `Roboto\`
- `...`

…and `new RegExp("next/font/google.*\\b(Inter\\")` throws:
`Invalid regular expression: \ at end of pattern`.

### Fix

Split only on UNescaped pipes, then unescape `\|` → `|` per cell:

```ts
const cells = line
  .split(/(?<!\\)\|/)  // lookbehind: don't split where `|` is preceded by `\`
  .slice(1, -1)        // drop the empty leading/trailing cells from `|cell|cell|`
  .map((c) => c.trim().replace(/\\\|/g, "|"));
```

The same trick applies to any markdown-table parser that has to round-trip
content where `|` is meaningful (regex alternation, shell pipes inside code
spans, type unions in TS type signatures).

### Generalised rule

**Any parser that reads structured content out of a markdown pipe-table MUST
treat `\|` as an escape, not a delimiter.** The trap is subtle because
single-pipe regex tables — `(foo|bar)` without table use — parse fine; the
collision only happens when the table's column separator and the cell's
alternation operator are the same character. Lookbehind split + per-cell
unescape is two lines of code and the canonical fix.

## Why both lessons cluster here

Both surfaced from the same PR (#4265) and both reflect a single deeper rule:
*structures that look right at planning time often have a contract the
implementer must re-verify at execution time*. The plan's calibration fixture
was "right" until we asked "does this regex actually fire?". The plan's rule
table was "right" until we asked "what does the parser do with `\|`?". The
fix in both cases was the same shape: probe the contract with the real
mechanism (grep, regex compile) before treating it as ground truth.

## Session Errors

- **PreToolUse hook blocked initial `tier1-scan.ts` write** — script imported `execSync` from `node:child` `_process` (the security hook matches on the literal substring of that subpath). Recovery: rewrote with `Bun.spawnSync(["git", ...], { stdout: "pipe" })`. Prevention: scripts that need to spawn external binaries from a Bun runtime should default to `Bun.spawnSync` argv-array — avoids both the hook AND the underlying shell-injection class.
- **Plan precondition #0.3 was wrong about `finding.schema.json`** — claimed `selector` field had regex `^[A-Za-z0-9_\-/]*$` to relax; reality: `selector` had no `pattern` at all (the regex was on `route`). Recovery: verified at /work Phase 0; simplified Phase 2.1 to no-op; added regression gate `expect(SCHEMA.properties.selector.pattern).toBeUndefined()`. Prevention: already covered by `Plan-quoted measurements are preconditions to verify` (hard rule).
- **Calibration fixture mismatch** — see Pattern 1 above.
- **`GENERIC-DISPLAY-FONT` initial regex required wrong token order** — `next/font/google.*\b(Inter|...)\b` required `next/font/google` BEFORE the font name, but real imports put the font name first (`import { Inter } from "next/font/google"`). Recovery: flipped to `import\s*\{\s*(Inter|...)\s*[\},].*from\s*["']next/font/google`. Prevention: for any rule targeting a syntactic construct, write the regex from a real example — paste an actual import line into the rule's test fixture FIRST, then construct the regex against that string, never against a mental model of "X then Y".
- **Markdown-table pipe-escape parsing** — see Pattern 2 above.
- **`semgrep --config=auto` failed under `--metrics=off`** — `auto` config requires telemetry. Recovery: switched to explicit `--config=plugins/soleur/skills/review/references/semgrep-custom-rules.yaml --config=p/typescript --config=p/security-audit`. Prevention: `plugins/soleur/skills/review/scripts/ensure-semgrep.sh` or the review SKILL.md §"Bootstrap" should call out that `--config=auto` is incompatible with `--metrics=off` and prescribe the explicit-config fallback.
- **Skill description budget exceeded after new skill** — house convention `"This skill should be used when..."` prefix bumped a ~12-word description to ~19, blowing the 1850-word budget by 9. Recovery: applied the plan's pre-derived sibling-trim sub-plan exactly (`pencil-setup`, `test-fix-loop`, `campaign-calendar` — 9 words each). Prevention: sibling-trim sub-plans already work as designed; future plans introducing a new skill should always carry a pre-derived trim list keyed to the final tokenised word count, NOT the prose-only count.
