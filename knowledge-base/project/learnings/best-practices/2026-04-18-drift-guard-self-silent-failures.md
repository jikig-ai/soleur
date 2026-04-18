---
module: plugins/soleur/skills/ux-audit
date: 2026-04-18
problem_type: test_quality_issue
component: drift_guard_tests
symptoms:
  - "toContain(short_token) false-positives on substring matches in prose"
  - "JSON Schema path pattern ^/ permits traversal with no current consumer"
  - "YAML parser regex covers only one style, silently underreads the rest"
root_cause: drift_guard_assertions_weaker_than_the_drift_they_claim_to_catch
severity: medium
tags: [drift-guard, test-design, regex, schema, parser-underread, review-catch]
synced_to: []
---

# Drift Guard Tests Must Survive Their Own Silent-Failure Modes

## Problem

During review of PR #2580 (`soleur:ux-audit` drain of #2356/#2357/#2362), three
parallel review agents independently surfaced three distinct silent-failure
modes in the new drift-guard tests — all in code the test author believed was
GREEN and load-bearing. Each could have shipped masking the drift it was
written to catch.

### Finding 1 — short-token `toContain` in drift test

`plugins/soleur/test/ux-audit/category-drift.test.ts` iterated
`FINDING_CATEGORIES` and asserted each string appeared in `SKILL.md` and
`ux-design-lead.md` via `expect(md).toContain(category)`. The canonical list
includes `"ia"` — a 2-char token that is a substring of `"media"`,
`"social"`, `"trivial"`, etc. The test would have continued passing even if
someone deleted every literal `"ia"` token from the markdown, as long as any
unrelated word containing the `ia` bigram remained.

### Finding 2 — `finding.schema.json` path pattern

`route` and `screenshot_ref` patterns were declared as `"^/"`. This permits
`/../../etc/passwd`, `/../../.ssh/id_rsa`, and embedded `\x00` control
characters. No consumer currently `fs.readFile`s those strings — but the
schema ships explicitly as a contract for future consumers. Security review
flagged this as forward-compat risk: when any consumer is added, the risk
becomes active with zero changes to the schema.

### Finding 3 — `route-list-prereqs.test.ts` YAML underread

The parser regex matched only flow-style lists
(`fixture_prereqs: [a, b, c]`). Every route in `route-list.yaml` currently
uses flow style, so the test passed with full coverage. If one route
switches to block style, the regex silently returns zero matches for that
key and the test's `fixtureLists.length > 0` guard still passes because
other routes carried the count. Net effect: a new block-style entry bypasses
the allowlist check without failing any test.

## Solution

Each finding was fixed inline on the PR branch (commit `9fa3631e`):

### Fix 1 — replace raw `toContain` with context-anchored form

```typescript
test.each([...FINDING_CATEGORIES])(
  "category %s appears quoted in SKILL.md",
  (category) => {
    // Require the quoted form `"${category}"` so short tokens like
    // "ia" don't false-positive on words like "media".
    expect(SKILL_MD).toContain(`"${category}"`);
  },
);

test.each([...FINDING_CATEGORIES])(
  "category %s appears in ux-design-lead.md with a word boundary",
  (category) => {
    const re = new RegExp(
      `\\b${category.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}\\b`,
    );
    expect(AGENT_MD).toMatch(re);
  },
);
```

Pattern: when testing short tokens against a large text blob, the assertion
must anchor on context (quoted form, inline-code backticks, word boundaries)
— never bare substring.

### Fix 2 — tighten schema path patterns to exclude traversal

```json
"route": {
  "type": "string",
  "pattern": "^/[A-Za-z0-9_\\-/]*$"
},
"screenshot_ref": {
  "type": "string",
  "pattern": "^/[A-Za-z0-9_\\-/.]+\\.(png|jpg|jpeg|webp)$"
}
```

Pattern: ship schema patterns that assume a worst-case consumer (untrusted
filesystem read) even when no consumer exists yet. Forward-compat hardening
is free at write time and expensive to retrofit after the first consumer
lands.

### Fix 3 — style-agnostic parser + exact count pin

Replaced the single-style regex with a per-key iterator that inspects both
inline and following-block content, then pinned the expected number of
`fixture_prereqs:` keys in the file:

```typescript
const EXPECTED_FIXTURE_LISTS = 11;

function parseFixturePrereqs(src: string): string[][] {
  const out: string[][] = [];
  const keyRegex =
    /fixture_prereqs:[ \t]*(.*)(?:\n((?:[ \t]*-[^\n]*\n?)*))?/g;
  for (const m of src.matchAll(keyRegex)) {
    // handle flow style, block style, and empty — every key emits one entry
  }
  return out;
}

test("parser reads every fixture_prereqs key (flow + block styles)", () => {
  expect(parseFixturePrereqs(YAML).length).toBe(EXPECTED_FIXTURE_LISTS);
});
```

Pattern: parser tests must pin an expected read count to catch regex
underread. This extends `cq-mutation-assertions-pin-exact-post-state` to
parser output shape.

## Key Insight

Drift-guard tests themselves need drift-guard reviews. The failure mode is
particularly insidious because:

1. The test author writes a drift-guard *because* they know silent-drift is
   the enemy.
2. The drift-guard implementation has its own silent-drift vulnerabilities
   (substring false-positives, style-specific regex, permissive pattern).
3. Unit-level thinking can't reach these — the test is green on the
   immediately-visible input.

Multi-agent parallel review reliably catches this class because each agent
asks a different "what if" question against the same artifact. In this PR,
three different agents (pattern-recognition, test-design, security-sentinel)
each surfaced one distinct silent-failure mode. No single agent found all
three; no unit test could.

**Applicable rule extension:** the existing rules
`cq-mutation-assertions-pin-exact-post-state` and
`cq-test-mocked-module-constant-import` cover similar classes for mutation
tests and mocked-import tests. The three findings above form a matching
class for *drift-guard tests* specifically — short-token containment,
schema-pattern permissiveness, and parser-style specificity.

## Prevention

When writing a drift-guard test, apply a self-check:

1. **Containment assertions:** if the token is under ~4 chars, anchor on
   context (quoted, backticked, word-boundary). A drift-guard that passes
   with unrelated prose shares no coverage with the drift it claims to
   catch.
2. **Schema patterns:** write patterns assuming the worst-case future
   consumer, not the current no-op. Especially for path-shaped strings
   (`route`, `screenshot_ref`, `file_path`, `url`) — restrict to the
   character class that current and foreseeable consumers need.
3. **Parser regexes:** pair the regex with an exact count pin derived from
   the source file's current key count. Underread surfaces as a count
   mismatch; a length-greater-than-zero guard is indistinguishable from
   partial coverage.

When reviewing a drift-guard test, ask three questions that map to the
findings above:

- "What's the shortest token in the iteration — would this assertion pass
  if the token appeared only in an unrelated word?"
- "If a future consumer reads this field from the filesystem, does the
  schema pattern prevent traversal and control-char injection?"
- "Does the parser regex cover every syntactic form the target language
  accepts, or does it implicitly pin the source file to one style?"

## Session Errors

1. **Initial `toContain(category)` in drift test without context anchoring** —
   Recovery: replaced with quoted-form + word-boundary regex after
   pattern-recognition review. **Prevention:** drift-guard tests iterating
   short tokens must anchor on context — this learning extends the existing
   rule class.

2. **Initial `finding.schema.json` patterns `"^/"` too permissive** —
   Recovery: tightened to character-class restricted forms after
   security-sentinel review. **Prevention:** schema-pattern writing checklist
   should include "assume future fs.readFile consumer" — codified in this
   learning's Prevention section.

3. **Initial `route-list-prereqs.test.ts` regex covered only flow-style
   YAML** — Recovery: added unified flow+block parser + exact count pin
   after test-design and code-quality reviews. **Prevention:** parser tests
   require count pins (extension of
   `cq-mutation-assertions-pin-exact-post-state`).

4. **Bash CWD drift during test runs** — Recovery: switched to absolute
   paths for `cd` commands. **Prevention:** already covered by
   `cq-for-local-verification-of-apps-doppler`; session lapse, not a new
   rule candidate.

5. **Planning subagent compaction boundary** — By design (plan+deepen
   offloaded to subagent to free context headroom); session-state.md
   captured forwarded decisions correctly. **Prevention:** existing flow.

## Related

- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
  — the meta-pattern that enabled all three catches
- `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`
  — sibling pattern for drift-guard strengthening in jsdom layout-gated tests
- `knowledge-base/project/learnings/best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`
  — consumer-boundary assertion pattern applied in `skill-summary.test.ts`
- AGENTS.md rules `cq-mutation-assertions-pin-exact-post-state`,
  `cq-test-mocked-module-constant-import` — same class, different targets

## PR

- PR #2580 — review-fix commit `9fa3631e`
