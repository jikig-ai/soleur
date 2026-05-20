---
title: components.test.ts no-backtick-scripts/ regex catches illustrative paths, not just real file refs
date: 2026-05-20
issue: 4190
category: best-practices
tags:
  - components-test
  - skill-prose-authoring
  - parser-parity
related_prs:
  - 4191
---

## Problem

`plugins/soleur/test/components.test.ts` enforces that SKILL.md/AGENT.md/COMMAND.md bodies use markdown links for `references/`, `assets/`, and `scripts/` paths — never backticks. The regex is:

```js
body.match(/`(?:references|assets|scripts)\/[^`]+`/g)
```

This catches THREE classes of usage, not one:

1. **Real file references** (e.g., `` `scripts/sweep-followthroughs.sh` ``) — the intended target. Fix: convert to `[scripts/...](../../../../scripts/...)` markdown link.
2. **Path prefixes used in assertions** (e.g., `` `scripts/followthroughs/` `` as a literal allowlist prefix). Fix: drop backticks and use plain prose, OR convert the prefix to a markdown link to the directory.
3. **Illustrative security/malicious example paths** (e.g., `` `scripts/followthroughs/../../bin/sh` `` as an attack-pattern example in prose). Fix: describe the pattern descriptively without backticking the literal exploit string ("a path that uses `..` traversal under the followthroughs root" rather than backticking the literal).

PR #4191 (issue #4190) iterated against the gate 3 times — once each for classes 1, 2, and 3 — before the SKILL.md rewrite passed. Each iteration was a single Edit + test re-run, so the cost was bounded; the gate worked as intended (catching unintended backtick usage). But the third class (illustrative paths) is non-obvious — the author isn't trying to link to a real file, just describing a pattern.

## Solution

When authoring SKILL.md prose that references `scripts/...`, `references/...`, or `assets/...` paths:

- **Real file refs** → markdown link to the path.
- **Literal prefixes** → drop the backticks; use plain prose or markdown link to the directory.
- **Security examples / hypothetical paths** → describe the pattern, do not backtick the literal string. The regex doesn't distinguish "real reference" from "illustration."

Cheapest pre-commit check (saves the test round-trip):

```bash
grep -nE '`(references|assets|scripts)/[^`]+`' plugins/soleur/skills/<skill>/SKILL.md
```

Zero hits = passes the components.test.ts gate.

## Key Insight

A regex enforcing "no backtick references" matches on the path-prefix shape alone, with no semantic context about whether the string IS a reference. Illustrative paths in prose (especially security/malicious examples) trip the same guard as forgotten markdown links. When intentionally including a path-shaped string for illustration, describe-without-backticking is the cleanest form.

This is a specific instance of a broader pattern: lexical regex gates have no semantics. They match the form, not the intent.

## Related Pattern: Verbatim Parser Parity Assertions

PR #4191 also introduced a behavioral-equivalence assertion for a parser triplicated across three files (sweeper script + skill prose + test). Rather than diff the awk-block bytes (fragile to indentation/comment differences), the assertion sources the sweeper's `parse_directive()` function from its file via `sed`, runs both parsers on the canonical fixture, and asserts identical output. This concretizes the existing "replicated literals must have a parity test" sharp edge in `plugins/soleur/skills/review/SKILL.md` with a low-cost behavioral assertion:

```bash
sweeper_fn=$(sed -n '/^parse_directive() {/,/^}/p' "$REPO_ROOT/scripts/sweep-followthroughs.sh")
sweeper_out=$(bash -c "$sweeper_fn
parse_directive < '$FIXTURE_DIR/expected-issue-body.md'")
test_out=$(awk "$PARSER" "$FIXTURE_DIR/expected-issue-body.md")
[[ "$sweeper_out" == "$test_out" ]] || fail "test PARSER differs from sweeper parse_directive"
```

Pattern: when N copies of a function/regex exist for defense-in-depth, the cheap drift defense is a test that EXECUTES each copy on identical input and diffs OUTPUTS — not the source bytes.

## Session Errors

- **components.test.ts trip #1 — 5 `` `scripts/...` `` backtick refs in new SKILL.md content** — Recovery: converted to markdown links (`[scripts/sweep-followthroughs.sh](../../../../scripts/sweep-followthroughs.sh)`). **Prevention:** run the grep above before invoking the components test.
- **components.test.ts trip #2 — `` `scripts/followthroughs/` `` literal prefix in assertion prose** — Recovery: rewrote as "points under the [scripts/followthroughs/](../../../../scripts/followthroughs/) root". **Prevention:** treat directory prefixes the same as file refs — markdown link or unwrap.
- **components.test.ts trip #3 — `` `scripts/followthroughs/../../bin/sh` `` illustrative malicious path** — Recovery: rewrote as descriptive prose ("a path that uses `..` traversal under the followthroughs root"). **Prevention:** when writing security examples, never backtick the literal exploit path.

## References

- Gate: `plugins/soleur/test/components.test.ts:228-234`
- Existing sharp edge: `plugins/soleur/skills/review/SKILL.md` — "Replicated literals across ≥2 source files without parity test"
- PR #4191 — example of all 3 trip classes + the parser-parity assertion
- Sweeper parser: `scripts/sweep-followthroughs.sh:37-47`
