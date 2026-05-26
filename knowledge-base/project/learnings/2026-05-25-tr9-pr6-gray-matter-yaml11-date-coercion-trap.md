---
title: "gray-matter coerces YAML 1.1 unquoted dates to JS Date objects (script-port silent data loss trap)"
date: 2026-05-25
category: integration-issues
problem_type: contract-drift
component: cron-strategy-review
module: inngest/functions
related_prs: [4412]
related_issues: [4416, 3948]
related_learnings:
  - 2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss
tags: [yaml, frontmatter, gray-matter, port-parity, multi-agent-review, silent-data-loss]
---

# gray-matter coerces YAML 1.1 unquoted dates to JS Date objects

## Problem

A TypeScript port of `scripts/strategy-review-check.sh` (TR9 PR-6, #4412) would have silently created **zero** GitHub issues on every cron fire, reporting `errors > 0` and `ok: false` against a contract that should have produced N issues for N overdue strategy documents.

Root cause: every strategy doc in `knowledge-base/{product,marketing,sales}/*.md` uses unquoted YAML dates in frontmatter:

```yaml
---
review_cadence: monthly
last_reviewed: 2026-05-25      # unquoted ISO date
owner: cpo
---
```

The TS port read `parsed.data.last_reviewed` (where `parsed = matter(raw)`) and coerced with `String(rawDate)`. That produced not the literal `"2026-05-25"` but the JS Date `.toString()` representation:

```text
"Mon May 25 2026 02:00:00 GMT+0200 (Central European Summer Time)"
```

Which failed the strict regex inside `parseISODate`:

```ts
function parseISODate(s: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;  // ← always returned null
  ...
}
```

Every doc routed into the "Skipping: invalid last_reviewed" warn → `errors++` → `continue` branch. The handler returned `{ ok: false, errors: N }` and Sentry showed a heartbeat with `error` status — but the bash predecessor (which used `sed` to extract the literal `2026-05-25` from the raw frontmatter text and fed it to `date -d`) produced N issues. Total contract drift; silent on every fire after deploy.

## Root cause

`gray-matter` delegates YAML parsing to `js-yaml`, which obeys YAML 1.1. YAML 1.1's `!!timestamp` schema auto-applies to unquoted strings matching `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS...`. js-yaml constructs a JavaScript `Date` object for these and returns it as the property value — not a string. YAML 1.2 dropped the auto-timestamp behavior, but js-yaml stays on 1.1 for backward compat.

The trap: at the consumer site, `parsed.data.last_reviewed` looks like it should be a string (the source file's bytes ARE the string `2026-05-25`), and `String(...)` looks like a safe defensive cast. Neither hint to the reader that the value is already a Date and that `.toString()` will produce timezone-localized prose.

## Solution

```ts
// gray-matter parses YAML 1.1, which coerces unquoted ISO dates
// (`last_reviewed: 2026-05-25`) into JavaScript `Date` objects, NOT strings.
// Every strategy doc in knowledge-base/ uses the unquoted form, so the raw
// frontmatter value is virtually always a `Date`. Coerce both shapes to a
// strict `YYYY-MM-DD` string so parseISODate accepts them. Returns undefined
// for missing/null and the literal raw string for unrecognized shapes (which
// will then fail parseISODate and route into the "invalid last_reviewed"
// errors++ branch — matching bash's `date -d` failure path).
function coerceFrontmatterDate(raw: unknown): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) return undefined;
    return raw.toISOString().slice(0, 10);
  }
  return String(raw);
}

// At the consumption site:
const lastReviewed = coerceFrontmatterDate(parsed.data.last_reviewed);
```

`toISOString()` always returns UTC. The downstream `parseISODate` regex `^\d{4}-\d{2}-\d{2}$` matches the `.slice(0, 10)` output exactly.

## Why TS unit tests did not catch it

The implementation subagent did not write a vitest case using a real `matter('---\nlast_reviewed: 2026-05-25\n...\n---\n...')` fixture. The only path-tests against `parsed.data.last_reviewed` would have hand-mocked `{ data: { last_reviewed: "2026-05-25" } }` — which IS a string, so the `String(rawDate)` cast is a no-op and `parseISODate` succeeds. The bug only surfaces when gray-matter actually parses YAML.

`tsc --noEmit` is silent: `parsed.data` is typed `{ [key: string]: any }` by gray-matter, so `String(Date)` typechecks fine.

The integration boundary (gray-matter ⇄ js-yaml ⇄ YAML 1.1 ⇄ unquoted-date schema) is invisible to per-module testing.

## Prevention

**Rule for any TS port of a shell script that reads frontmatter dates:** the port MUST include at least one vitest case using a REAL `matter(...)` call against a literal frontmatter string, not a hand-crafted `{ data: ... }` object. Pattern:

```ts
import matter from "gray-matter";

it("handles unquoted YAML date as gray-matter would in production", () => {
  const raw = "---\nlast_reviewed: 2026-05-25\nreview_cadence: monthly\n---\nbody";
  const parsed = matter(raw);
  expect(parsed.data.last_reviewed).toBeInstanceOf(Date); // proves the trap
  expect(coerceFrontmatterDate(parsed.data.last_reviewed)).toBe("2026-05-25");
});
```

Aligns with project convention `cq-test-fixtures-synthesized-only` — the fixture is synthesized in-test, not loaded from disk.

**Sweep target for codebase audit:** any other consumer of `parsed.data.<field>` where `<field>` is named `*_date`, `*_at`, `last_*`, `created`, `updated`, `published`, `expires`, etc., and the consumer assumes string semantics. `git grep -nE 'parsed\.data\.[a-z_]*(date|_at|last_|created|updated|published|expires)' apps/` would enumerate every site.

## How it was caught

Multi-agent review's `data-integrity-guardian` ran a function-by-function parity audit between `scripts/strategy-review-check.sh` and the TS port. The agent independently empirically tested gray-matter against `node_modules/gray-matter` with a representative frontmatter fixture, observed `typeof parsed.data.last_reviewed === "object"` + `instanceof Date === true`, traced the value through `String(rawDate)` → `parseISODate` → null → errors++, and applied the inline fix.

This matches the defect class "Contract drift between two surfaces no single test exercises" documented in `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`. The bash script and the TS port are both internally consistent — the drift lives at the YAML-parse boundary that only an agent reading BOTH source-of-truths could surface.

## Tags

category: integration-issues
module: inngest/functions
component: cron-strategy-review
related_prs: 4412
