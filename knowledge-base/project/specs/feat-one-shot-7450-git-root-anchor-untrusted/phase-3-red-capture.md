# Phase 3 — RED capture for Guard 1 (cq-write-failing-tests-before)

`cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
run before any migration.

```
× G2: every gate-script reference in code context is reached through the bare anchor
  expected [ …(4) ] to deeply equal []
  + "plugins/soleur/skills/compound/SKILL.md:326: bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/compound/scripts/token-efficiency-report.sh""
  + "plugins/soleur/skills/incident/SKILL.md:222: SENTINEL="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh""
  + "plugins/soleur/skills/legal-generate/SKILL.md:63: SENTINEL="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh""
  + "plugins/soleur/skills/linear-fetch/SKILL.md:79: bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/linear-fetch/scripts/redact-linear-urls.sh""

× G5: every SECRET-gate skill carries the identity preflight with a fail-closed exit 2

Tests  2 failed | 14 passed (16)
```

G2 enumerates exactly the four executable gate sites and nothing else, which is the
work-list for Phase 4. G3 (the anti-vacuity floor) PASSES here, correctly: the floor asserts
the scan FOUND its references, not that they comply — a floor that only passed after the fix
could not distinguish "compliant" from "scanned nothing".

## Two design corrections Phase 3 forced, neither in the plan

**1. The anchored path is in an ASSIGNMENT, not a runner operand.** The command surface invokes
producers directly, so its runner-position rule sees the anchor. The skills gate surface is
assignment-then-invoke:

```
SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"
bash "$SENTINEL"
```

A runner-operand rule certifies `bash "$SENTINEL"` while the assignment above it points
anywhere. The skills axis therefore matches gate-script references in code context.

**2. Seven of eleven path-form references are markdown links.**
`[redact-sentinel.sh](../incident/scripts/redact-sentinel.sh)` is documentation, not an
execution path. Scoping the scan to fence bodies and inline spans excludes them by
construction; a bare-path rule would have reported documentation as a vulnerability.

## Incidental fix: `deepen-plan/SKILL.md` unterminated fence

G1 surfaced a pre-existing defect unrelated to this PR's subject. `deepen-plan/SKILL.md`'s
"Example Enhancement" section shows an "After" **markdown** example that CONTAINS a nested
```` ```typescript ```` block. Equal-length fences cannot nest in CommonMark, so the bare
closer at line 889 ended the outer block early and left the fence at line 902 dangling — 34
balanced pairs plus one orphan, which an even 72-line fence count hides.

Fixed by promoting the outer fence to four backticks, which is the construct the guard's own
parser docstring already anticipates. Intent-preserving and two lines.

It is fixed inline rather than deferred because an unbalanced fence makes the parser drop every
reference after the break — the exact vacuity G1 exists to prevent — so leaving it would mean
either a permanently-red guard or a weakened one. Cost-of-filing threshold (<=100 lines,
<=4 files) puts it well inside the inline band.
