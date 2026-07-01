---
title: A dependency-cruiser reachability-baseline guard must key on rule NAME, not entry type
date: 2026-07-01
category: security-issues
module: constraint-scaffold
pr: 5845
issue: 5777
tags: [dependency-cruiser, fail-open, reachable-rule, baseline, import-boundary, multi-agent-review]
---

## Problem

The transitive client→server-secret gate (#5777, ADR-071 amendment) keeps its
dependency-cruiser `reachable`-rule baseline provably EMPTY, because dep-cruiser
softens reachability violations **per-origin** (one baselined entry blinds a client
to every future transitive secret). The always-on runner guard + the `boundary.test.sh`
assertion both enforced "empty" by counting `entries.filter(e => e.type === "reachability").length === 0`.

Multi-agent review (`security-sentinel`) found — and I reproduced end-to-end against
dependency-cruiser 16.10.4 — that this count is **bypassable**, a green-while-leaking
fail-open at a `single-user incident` threshold:

```json
[{ "type": "module", "from": "components/c/leak.tsx", "to": "server/secret.ts",
   "rule": { "severity": "error", "name": "no-client-to-server-secret-transitive" } }]
```

- The guard's `filter(e.type === "reachability")` counts this as **0** → runner passes.
- But `depcruise --ignore-known` on a real `client → lib/helper → server/secret` value
  chain returns **rc=0, "no dependency violations found, 1 known violation ignored"** —
  the real transitive leak is SUPPRESSED.

## Root cause

`node_modules/dependency-cruiser/src/enrich/soften-known-violations.mjs` softens
module-level violations (which is where reachable-rule violations live) via
`softenModuleViolation`, matching a baseline entry to a live violation on
**`from` + `rule.name` only** — it ignores `to`, `via`, AND the entry's `type`
(beyond a membership test `["module","reachability"].includes(type)`). So a
`type:"module"` entry that merely names the transitive rule suppresses it identically
to a `type:"reachability"` entry. A `--output-type baseline` capture emits
`type:"reachability"`, so an organically-generated baseline is caught — the gap is any
hand-authored / merged / auto-recovery-touched entry.

## Solution

Key the guard on the transitive **rule name**, not the entry `type`. Reject any baseline
entry where `type === "reachability"` OR `rule.name === "<the transitive rule>"`,
regardless of `type`; also fail closed on a non-array baseline (`{}`/`null` parse fine
but are not an entry array). Applied identically to all three synced copies (shared
runner template, emitted `constraint-gates.sh`, and the `boundary.test.sh` AC4 assertion),
with a `type:"module"` regression fixture proving the runner now fails closed.

## Key insight

**For any dependency-cruiser `reachable`-rule baseline "stays empty" guard, count by
`rule.name`, never by `type:"reachability"`.** dep-cruiser's per-origin softening is
name-keyed and type-agnostic, so a type-only count is a fail-open a one-line baseline
edit defeats. A `--output-type baseline`-generated baseline hides this (it always emits
`type:"reachability"`); only a hand-authored entry exposes it — so the regression test
MUST inject a `type:"module"` entry, not rely on a generated baseline.

## Session Errors

1. **First D4 drift-guard rewrite false-positived on real value-safe modules**
   (`domain-leaders.ts`, `scope-grants/action-class-map.ts`). — Recovery: the broadened
   value-import regex matched prose ` from "` and `export const …` declarations as edges;
   split detection into IMPORT statements (`^import ` not `import type`), RE-EXPORT edges
   (`^export … from` not `export type`), and dynamic `import()/require()` — never a bare
   ` from ` match. — Prevention: when a content-grep guard must catch module-graph EDGES,
   anchor on the statement keyword (`^import`/`^export … from`), never a bare token that
   also appears in prose or in `export const` declarations. Mirror of
   `cq-nextjs-route-files-http-only-exports`-style keyword anchoring for bash grep guards.
2. **VALUE_SAFE_PATH anchoring test read the regex from `.cjs` SOURCE** and got the
   literal `\\.` (double-backslash), which `new RegExp` interpreted as "match a literal
   backslash". — Recovery: `require()` the config and read the RUNTIME
   `forbidden[].to.pathNot` value (properly unescaped) instead of grepping source. —
   Prevention: to test a regex embedded in an executable config, evaluate the config and
   read the compiled value; never re-parse the escaped source literal.
3. **AC10 (runner-green-on-baselined-fixture) broke** when the transitive fixtures were
   added — the reachable rule is a SUPERSET of the direct rule, so baselining a fixture
   with a non-value-safe direct leak now produces `type:"reachability"` entries the new
   guard rejects. — Recovery: scope AC10 to a client that directly value-imports a
   VALUE_SAFE module (a baselineable `type:"dependency"` entry with zero reachability),
   mirroring the real app exactly. — Prevention: one-off; specific to this test.
4. **Monitor fired prematurely** — the `until`-loop matched an intermediate suite summary
   line (`… N passed`) so it reported "done" while `test-all.sh` was still running. —
   Recovery: re-armed watching for the true `EXIT=` marker in the backgrounded task's
   output. — Prevention: covered by
   `[[2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness]]`; a
   completion monitor must match ONLY the terminal marker, not any line containing
   `passed`/`failed`.
5. *(forwarded from session-state)* Plan subagent Write blocked (main-checkout path) and
   mid-pass plan edits by review agents — one-offs; the hook worked as intended.

## Related

- [[2026-04-15-multi-agent-review-catches-bugs-tests-miss]] — review caught a P1 fail-open
  in my own freshly-written guard that the green self-test suite could not (the generated
  baseline never exercises the `type:"module"` shape).
- ADR-071 §Amendment 2026-07-01 (the shipped decision record).
