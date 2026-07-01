---
title: "feat(harness): constraint-scaffold v2 — transitive client→helper→server-secret boundary gate"
type: feat
issue: 5777
branch: feat-one-shot-5777-transitive-secret-leak-gate
pr: null
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_plan: knowledge-base/project/plans/2026-06-30-feat-constraint-scaffold-l1-gate-generator-plan.md
adr: ADR-071 (amend)
created: 2026-07-01
---

# Plan: constraint-scaffold v2 — transitive import-boundary gate (#5777)

## Overview

The v1 Layer-1 gate (`constraint-scaffold`, ADR-071, shipped in #5770) rejects a `"use client"`
module taking a **value** (non-`type-only`) import **directly** on the server-only tree
(`server/**`) — a server secret leaking into the browser bundle. It matches **DIRECT edges only**.

The gap (NG5, deferred from #5765): a `"use client"` module that imports a **non-client helper**
(e.g. in `lib/`) which in turn imports a `server/**` secret — the secret still ends up in the
browser bundle, but the direct-edge rule never sees the transitive chain. This plan adds a
dependency-cruiser **`reachable` rule** to catch `client → helper → … → server-secret`.

**This is the second, independent deliverable of the constraint-gates v2 "buildable" spec.** The
sibling recovery-dispatcher (ADR-074, two-stage `fix-constraints`) already shipped (merged
2026-06-30). The parent L1 generator (ADR-071) shipped earlier. A prior WIP branch was abandoned
as stale; this restarts fresh from `main`. Priority p3-low, domain/engineering, type/feature.

**Brand-survival threshold is inherited: `single-user incident`** — a mis-calibrated transitive
gate that reads green while a real server secret ships transitively into the browser is the exact
`single-user incident` vector v1 was built to close, now extended one hop deeper.

### The two load-bearing constraints discovered during planning (both verified against the installed dependency-cruiser@16.10.x source, twice, independently)

The feature is **not buildable as literally worded in the issue** ("add a `to.reachable` rule that
excludes type-only via the rule"). Two hard facts about dependency-cruiser v16.10.x reshape the
design. Both were confirmed (a) by a docs/schema/published-package research pass AND (b) by a
spec-flow trace of the installed library source (`node_modules/dependency-cruiser/src/**`).

1. **`reachable` rules are schema-locked.** Their `to` object allows ONLY `{path, pathNot,
   reachable}` with `additionalProperties: false`. `dependencyTypesNot`, `viaOnly`, `via`, `viaNot`
   are **rejected at config-validation time** on a reachable rule (those keys are for `circular`
   rules). `reachable.mjs` never reads dependency-types; `getPath` traverses **every** edge,
   type-only included. So `to: {path:"^server/", reachable:true, dependencyTypesNot:["type-only"]}`
   is a **silent no-op that fails validation** — and even if it parsed, it would traverse type-only
   edges, false-positiving on `client → helper(type-only) → server(value)` (which MUST pass — a
   type-only hop erases at build, no runtime value flows). **The ONLY lever to exclude type-only
   edges from reachability is the global `options.tsPreCompilationDeps: false`** (elides type-only
   imports from the graph entirely so reachability cannot follow them). v1 sets it `true` (its
   direct rule needs type-only edges present so `dependencyTypesNot` can filter them). → **D1** below.

2. **Reachability baseline suppression is coarse (per-origin fail-OPEN).**
   `soften-known-violations.mjs` softens `reachability` violations via `softenModuleViolation`,
   which matches on `from` + `rule.name` **only** — it ignores `to` and `via` (unlike
   `dependency`/`cycle`, matched fine-grained by `isSameViolation`). So baselining ONE value-safe
   transitive path from client `X` silently suppresses **ALL** future reachability violations from
   `X` under that rule — including a genuinely new `X → G → server/REAL-SECRET` leak. The baseline
   file *looks* precise (the WRITE side dumps `from`+`to`+`via`) but suppresses coarsely. At
   `single-user incident` threshold this is unacceptable. → **D2** below.

## Research Reconciliation — Spec/Issue vs. Codebase

| Issue / requirement claim | Codebase / library reality (verified 2026-07-01) | Plan response |
|---|---|---|
| "Add a `to.reachable` rule … exclude type-only imports (`import type`) from the rule." | dependency-cruiser@16.10.x `reachable` `to` is schema-locked to `{path,pathNot,reachable}` (`additionalProperties:false`); per-rule `dependencyTypesNot`/`viaOnly` are impossible. Type-only exclusion is only via **global** `tsPreCompilationDeps:false`. | **D1:** flip the shared `options.tsPreCompilationDeps` `true→false`, drop the direct rule's now-redundant `dependencyTypesNot:["type-only"]`, add the reachable rule. Direct-rule outcome is unchanged (Phase 0 proves byte-identical); type-only chains are globally elided so reachability ignores them. |
| "Run a single `--refresh-baseline` … review the diff for pre-existing transitive paths before committing the baseline." | Reachability baseline suppression is **per-origin** (`from`+`rule.name` only). A baselined reachability entry turns that client into a permanent transitive blind spot. | **D2:** the reachable baseline MUST stay **EMPTY**. Exclude the 3 verified-value-safe server modules via `to.pathNot`; FIX any real pre-existing transitive leak (never grandfather). A CI guard fails if the committed baseline holds any `type:"reachability"` entry. |
| "Reuse the shared runner and pin the dependency-cruiser version IDENTICALLY to v1." | Runner `constraint-gates.sh` runs one cruise (`--config … --ignore-known … --output-type err app components server`). package.json pins `dependency-cruiser@^16.10.0`. | Single config + single cruise → runner **reused unchanged** for the cruise itself (one small additive guard for D2; see Phase 3). Version pin **untouched** (`^16.10.0`) — no bump, no drift. |
| "A transitive client→helper→secret chain MUST fail; a type-only transitive chain MUST pass." | The hermetic self-test `boundary.test.sh` copies the REAL `.cjs` into a mktemp Next.js-shaped fixture and asserts positive/negative. It SKIPs (exit 0) when the toolchain parses 0 modules. | Add negative + both-directional positive fixtures (incl. a `lib/`-helper chain) with an **anti-vacuity guard** (toolchain-present ⇒ assertions MUST run, MUST fail not skip). |
| "`.dependency-cruiser.cjs`" is the edit target | The `.cjs` is **byte-identical** to `references/depcruise-config.template` (enforced by `parity.test.sh`); the generator emits it via `cp`. | Edit BOTH the template AND the emitted `.cjs` identically (Files to Edit). |
| Prior WIP branch exists | Abandoned as stale; restarted from current `main`. `main` HEAD = d86256032 (recovery-dispatcher merged). | No dependency on the WIP branch; ignore it. |

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) a false-positive wall — the transitive
rule flags legitimate `client → lib(types)` chains as leaks and hard-blocks the founder's PR on a
`.cjs` they cannot read or unblock; or (b) a false sense of safety — a mis-built reachable rule
(type-only edges traversed, or an origin silently baselined per D2) reads **green while a real
server secret ships transitively into the browser bundle**.

**If this leaks, the user's data / secrets are exposed via:** a `"use client"` component pulling in
a non-client helper (`lib/*`) that value-imports a server-secret module — the bundler inlines the
secret into client JS served to every browser. This is the same exposure vector as v1, one
dependency hop deeper (the hop v1 is blind to).

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO reviewed the gate's threshold framing at the parent brainstorm
(Phase 0.5 triad, `USER_BRAND_CRITICAL=true`); this v2 extends the **same gate** under the **same
threshold** and carries the sign-off forward. `user-impact-reviewer` runs at PR-review time. The
agent-owns-gates + two-stage auto-recovery model (ADR-071 / ADR-074) is the primary founder-safety
mitigation and is unchanged.

> **Sharp Edge:** a plan whose `## User-Brand Impact` section is empty / `TBD` / threshold-less
> fails `deepen-plan` Phase 4.6. This section is filled.

## Design Decisions (load-bearing)

### D1 — Single config; flip `tsPreCompilationDeps` to `false`; drop the direct rule's redundant `dependencyTypesNot`

The type-only-exclusion for the reachable rule is expressible ONLY as the global
`options.tsPreCompilationDeps: false` (type-only imports are elided from the graph → reachability
cannot follow them). With type-only edges globally absent:

- The **direct** rule becomes `to: { path: SECRET_PATH }` (drop `dependencyTypesNot:["type-only"]`
  — now redundant, because type-only edges no longer exist to filter). Its **output is unchanged**:
  it flags exactly the value edges it flagged under v1 (`true` + `dependencyTypesNot` ≡ `false`
  with the filter dropped — both leave "value edges into `server/` only").
- The **reachable** rule correctly ignores any chain containing a type-only edge (the edge is not
  in the graph, so no path exists through it).

`computeClientFromSet()` is called **once** (`const clientFrom = computeClientFromSet();`) and
referenced by both rules — preserving the fail-closed empty-from-set + regex-escape + symlink
guards for BOTH rules automatically (confirmed: shared `computeClientFromSet` in `.cjs:104-136`).

**Phase 0 GATE (mandatory, brand-survival):** empirically prove the **direct rule's violation set
is byte-identical** before and after the `tsPreCompilationDeps` flip (diff `depcruise --output-type
baseline` for the direct rule only, on the real tree). If it diverges, fall back to **D1-alt**:
keep v1's `.cjs` untouched (`tsPreCompilationDeps:true`), add a **separate** config
`.dependency-cruiser-reachable.cjs` (`tsPreCompilationDeps:false`, reachable rule only) with its
own `references/depcruise-reachable-config.template` + parity assertion, and extend the runner to
run the second cruise + second (empty) baseline. D1 is strongly preferred (one config, one cruise,
runner reused, matches the issue's "add a rule to `.dependency-cruiser.cjs`"); D1-alt is the
zero-v1-regression escape hatch.

### D2 — Reachable baseline MUST be empty (avoid per-origin fail-open); use `to.pathNot` + fix, never grandfather

Because reachability suppression is per-origin, the reachable rule must produce **zero** baselined
entries. Two mechanisms, both schema-legal:

- **`to.pathNot`** excludes the 3 modules v1 already verified value-safe by security review —
  `server/domain-leaders.ts` (static array, no secrets), `server/providers.ts` (env-var **names**
  as metadata, not values), `server/team-names-validation.ts` (no secret values). Excluding them
  from the reachable **target** (not the `from` set — excluding a client from `from` would blind it
  to ALL secrets) zeroes out the reachability violations that correspond to the already-value-safe
  direct edges, and any transitive path that only reaches those 3. A client is still watched for
  reachability to every OTHER `server/` module.
- **Fix, don't baseline:** any remaining reachable violation on HEAD is either a **real transitive
  leak** (FIX it in this PR — move the value import behind a server boundary, or make the client
  import a client-safe façade) or a **newly-discovered value-safe module** (security-review it; if
  genuinely value-safe, add to `pathNot` with a one-line justification). Iterate `pathNot` + fixes
  until the reachable rule is GREEN on HEAD with **zero** `type:"reachability"` baseline entries.

**Reachable rule shape:**
```js
{
  name: "no-client-to-server-secret-transitive",
  severity: "error",
  comment:
    'A "use client" module must not TRANSITIVELY reach the server-only tree (server/**) ' +
    "through a chain of value imports (a non-client helper that value-imports a server secret " +
    "ships that secret into the browser bundle). Break the chain, or use `import type`.",
  from: { path: clientFrom },
  to: { path: SECRET_PATH, pathNot: VALUE_SAFE_PATH, reachable: true },
}
```
where `const VALUE_SAFE_PATH = "^server/(domain-leaders|providers|team-names-validation)\\.";`
(finalized against Phase 0's enumerated reached-set; add only Phase-0-verified value-safe modules).

Because `pathNot` already excludes the value-safe targets, the reachable rule does **not**
re-flag v1's 10 direct value-safe edges (they reach only excluded modules) — the baseline does NOT
double. The single baseline file keeps its existing direct entries (fine-grained matched) and adds
**zero** reachability entries.

### D3 — CI guard: zero reachability entries in the committed baseline

Add a guard that FAILS if `.dependency-cruiser-known-violations.json` contains any `type:
"reachability"` entry. Placement: the hermetic self-test `boundary.test.sh` (asserts the committed
baseline is reachability-free; runs in the `test-webplat` shard where the toolchain is present),
AND — preferred for defense-in-depth — a small additive check in the shared runner
`constraint-gates.sh` so the dogfood CI job fails if a future `--refresh-baseline` ever captures a
reachability entry. The runner check is generic ("no reachability entry may be suppressed") and is
mirrored into `shared-runner.template` to keep `parity.test.sh` green.

## Architecture Decision (ADR/C4)

### ADR — amend ADR-071 (this is an EXTENSION of an existing decision, not a new ADR)

Amend `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md`:
- **Decision:** add a paragraph — the gate now also enforces **transitive** client→server-secret
  reachability via a dependency-cruiser `reachable` rule; because reachable rules cannot filter
  dependency-types per-rule in v16.10.x, the shared `options.tsPreCompilationDeps` is set `false`
  (type-only edges elided globally) so both the direct and reachable rules ignore type-only imports;
  the reachable baseline is kept **empty** (value-safe targets excluded via `to.pathNot`; real
  leaks fixed) to sidestep dependency-cruiser's per-origin reachability suppression.
- **Alternatives Considered:** add (i) per-rule `dependencyTypesNot` on reachable — **impossible**
  (schema-forbidden in v16.10.x); (ii) baselining pre-existing transitive paths — **rejected**
  (per-origin suppression = permanent blind spot); (iii) D1-alt two-config split — retained as the
  fallback if the `tsPreCompilationDeps` flip changes the direct-rule set.
- **Consequences:** update the line that lists "transitive-edge coverage … deferred (#5774–#5778)"
  to record NG5/#5777 as **closed** by this rule.

### C4 views — no C4 impact (enumeration required by the completeness mandate)

The `constraint-scaffold` component (`platform.plugin.constraintscaffold`) was added to
`model.c4` + `views.c4` in v1 (parent plan §C4). This v2 is a **rule-logic addition to an existing
modeled component**. Completeness enumeration for THIS change — **external human actors:** none
added (no new data sender/receiver); **external systems/vendors:** none (dependency-cruiser remains
a build-time devDep, unmodeled by design per parent plan §C4); **containers/data-stores:** none;
**actor↔surface access relationships:** none changed. → **No `.c4` edit.** `/work` confirms by
reading all three model files (`model.c4`, `views.c4`, `spec.c4`) and re-running
`c4-code-syntax.test.ts` + `c4-render.test.ts` only if any `.c4` is touched (it will not be).

## Infrastructure (IaC)

**Skipped — no provisioned infrastructure.** Pure config/skill/test change against the
already-provisioned CI surface. `dependency-cruiser` is an existing npm devDep; no Terraform root,
no secret, no new runtime process. (Phase 2.8 considered, cleared.)

## Observability

```yaml
liveness_signal:
  what: "constraint-gates CI job conclusion on every apps/web-platform PR (shared with v1 direct rule; the reachable rule adds no new job)"
  cadence: "per PR event"
  alert_target: "GitHub PR checks (red = blocked/annotated merge); gh pr checks"
  configured_in: "apps/web-platform/.github/workflows/constraint-gates.yml (unchanged; calls the shared runner)"
error_reporting:
  destination: "GitHub Actions job log + PR check annotation (prints the auto-recovery path on failure)"
  fail_loud: "runner exits non-zero on any new (non-baselined) reachability OR direct violation, OR dep-cruiser config/binary error; verified: report/error.mjs increments exitCode for reachability errors and prints the 'N dependency violations' summary line the runner greps for"
failure_modes:
  - mode: "new transitive client→helper→server-secret leak (value chain)"
    detection: "reachable rule fires (type:reachability), --ignore-known does NOT suppress it (baseline has zero reachability entries by design D2)"
    alert_route: "constraint-gates job fails → red/annotated PR check → two-stage auto-recovery (ADR-074) attempts fix, else surfaces for maintainer"
  - mode: "reachability entry silently baselined (per-origin fail-open, D2)"
    detection: "D3 guard: boundary.test.sh + runner FAIL if the committed baseline contains any type:'reachability' entry"
    alert_route: "scripts/test-webplat shard fails on PRs touching the gate; runner fails in the dogfood job"
  - mode: "reachable rule goes vacuous (type-only wrongly traversed / assertions skipped)"
    detection: "boundary.test.sh both-directional type-only fixtures + anti-vacuity guard (toolchain-present ⇒ assertions run, fail not skip)"
    alert_route: "scripts test shard fails"
logs:
  where: "GitHub Actions run logs (constraint-gates job + scripts test shard)"
  retention: "GitHub Actions default (90d)"
discoverability_test:
  command: "cd apps/web-platform && bun install --frozen-lockfile && ./node_modules/.bin/depcruise --config .dependency-cruiser.cjs --ignore-known .dependency-cruiser-known-violations.json --output-type err app components server; echo rc=$?"
  expected_output: "rc=0 with 'no dependency violations found' (baseline-clean, zero reachability entries) — NO ssh"
```

## Implementation Phases

### Phase 0 — Empirical spike & preconditions (no committed writes; brand-survival gate)

Per learning `2026-06-30-constraint-scaffold-verify-every-assumed-capability-at-brand-survival-threshold.md`:
at this threshold, EXERCISE every capability before writing it load-bearing.

- **0.1 Install toolchain:** `cd apps/web-platform && bun install --frozen-lockfile` (this worktree
  has no `node_modules`; depcruise binary is required for every subsequent step).
- **0.2 Reachable-rule capability proof (D1):** on a scratch copy of `.cjs`, set
  `tsPreCompilationDeps:false`, drop the direct rule's `dependencyTypesNot`, add the reachable rule
  (no `pathNot` yet). Run against the real tree. Confirm: (a) the config **validates** (no
  `additionalProperties` error); (b) `import type` chains are NOT reported (type-only elided);
  (c) a hand-made value chain IS reported.
- **0.3 Direct-rule equivalence proof (D1 GATE):** diff the **direct-rule** violation set from
  `--output-type baseline` before (`tsPreCompilationDeps:true`+`dependencyTypesNot`) vs after
  (`false`, filter dropped). MUST be byte-identical. If not → adopt **D1-alt** (two-config split);
  record the divergence in a Research-Reconciliation addendum.
- **0.4 Enumerate the reachable target set (D2):** with the reachable rule (no `pathNot`), list
  EVERY distinct `server/**` module transitively reached from any client origin (parse
  `--output-type json` `via`/`to`). For EACH: classify **value-safe** (→ candidate for `pathNot`)
  vs **real leak** (→ Phase 2 fix). Do NOT trust the v1 count or the issue's framing — re-scan
  (learning `2026-04-06-rule-audit-budget-baseline-drift.md`). Record the reached-set + the
  disposition of each module.
- **0.5 Perf probe (P2-1):** wall-clock `depcruise … app components server` with the reachable
  rule on the real tree (~170 client modules). Record the delta; if it materially slows CI, tighten
  `to.path`/`pathNot` and note a runner timeout budget.
- **0.6 Confirm no description-budget impact:** the change edits `SKILL.md` **body prose** only
  (line 15 "direct-edge only … transitive coverage deferred"), NOT the `description:` frontmatter →
  no `components.test.ts` budget re-check needed. Verify no `description:` edit is introduced.

### Phase 1 — Config: template + emitted `.cjs` (D1)

- **1.1** Edit `plugins/soleur/skills/constraint-scaffold/references/depcruise-config.template`:
  set `options.tsPreCompilationDeps: false`; compute `const clientFrom = computeClientFromSet();`
  once; direct rule → `to: { path: SECRET_PATH }` (drop `dependencyTypesNot`); add
  `const VALUE_SAFE_PATH = "^server/(domain-leaders|providers|team-names-validation)\\.";` and the
  reachable rule (D2 shape); update the header comment + rule `comment` strings to describe the new
  mechanism (global type-only elision; transitive coverage; `pathNot` value-safe rationale;
  per-origin-baseline caveat).
- **1.2** Apply the **byte-identical** change to `apps/web-platform/.dependency-cruiser.cjs`
  (parity.test.sh test #1 enforces byte-equality).
- **1.3** Do NOT touch `apps/web-platform/package.json` (version pin stays `^16.10.0` — identical to
  v1; requirement's "no version drift").

### Phase 2 — Zero-out the reachable baseline (D2): fix real leaks + finalize `pathNot`

- **2.1** For every **real leak** enumerated in 0.4: fix it (break the transitive value chain).
  Each fix is a `Files to Edit` entry once 0.4 names the file (cannot be enumerated at plan time —
  depends on the live scan; `lib/*.ts` importing `@/server/*` as a value AND reachable from a
  client is the candidate shape). At `single-user incident` threshold a real leak MUST be fixed,
  never baselined. If the fix set is large/risky, STOP and surface for scoping (do not grandfather).
- **2.2** Finalize `VALUE_SAFE_PATH` = the Phase-0-verified value-safe reached modules (start with
  the 3 v1-verified; add only security-reviewed additions with a one-line justification comment).
- **2.3** Single authoritative `constraint-scaffold.sh --refresh-baseline` (clean tree +
  origin/main merge-base). **Review the full baseline diff:** it MUST show **zero** new
  `type:"reachability"` entries (ideally the baseline is byte-unchanged from v1 — only the direct
  entries). Any reachability entry ⇒ go back to 2.1/2.2 (fix or exclude), do NOT commit it.

### Phase 3 — CI guard (D3)

- **3.1** Add to `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` an assertion:
  the committed `apps/web-platform/.dependency-cruiser-known-violations.json` contains **zero**
  `type:"reachability"` entries (jq/node parse). Fail loud otherwise.
- **3.2** Add a generic additive guard to `references/shared-runner.template` AND
  `apps/web-platform/scripts/constraint-gates.sh` (byte-identical): after loading the baseline,
  fail-closed if it contains any `type:"reachability"` entry (a reachability suppression is never
  legitimate under D2). Keep `parity.test.sh` tests #1/#2 green (edit template + emitted copy
  together). If this guard is judged out-of-scope for the shared/tenant runner at review, fall back
  to the boundary.test.sh assertion alone (3.1) — that is the minimum.

### Phase 4 — Fixtures (negative + both-directional positive) + anti-vacuity guard

Add to `boundary.test.sh` `make_fixture` + assertions (all synthesized under mktemp; nothing
written to the real tree):

- **4.1 NEGATIVE (transitive, helper in `lib/` — locks P2-2):** `components/leakdir/transitive.tsx`
  (`"use client"`) → `import { fmt } from "@/lib/leak-helper"`; `lib/leak-helper.ts` (non-client)
  → `import { SECRET_TOKEN } from "@/server/secret"` (value). The transitive rule MUST flag
  `transitive.tsx`. (Fixture `secret.ts` must be a module NOT in `VALUE_SAFE_PATH`.)
- **4.2 NEGATIVE (depth-3):** `client → lib/a → lib/b → server/secret` (value). MUST flag.
- **4.3 POSITIVE (terminal type-only):** `client → lib/helper(value) → server` via `import type`.
  MUST NOT flag (terminal edge elided).
- **4.4 POSITIVE (first-hop type-only — the load-bearing case, P0-2):**
  `client → import type helper`, helper value-imports server. MUST NOT flag (client→helper edge
  elided → no path). This is the case a naive per-edge filter would false-positive.
- **4.5 POSITIVE (pathNot target):** `client → lib/helper(value) → server/domain-leaders` (value).
  MUST NOT be flagged by the transitive rule (`pathNot` excludes it) — proves `pathNot` + no
  double-count against the direct rule.
- **4.6 Anti-vacuity guard (P1-2):** if `PARSED_COMPONENTS >= 1` (toolchain present), the transitive
  assertions MUST execute and MUST `bad`/exit-nonzero if the negative fixtures are not flagged —
  never silently skipped. Keep the existing toolchain-absent SKIP (exit 0) for shards with no
  depcruise, but ensure the new assertions live AFTER the existing skip guard and are covered by the
  `test-webplat` shard (committed toolchain present).

### Phase 5 — Docs / ADR / prose

- **5.1** Amend ADR-071 (§Decision, §Alternatives Considered, §Consequences) per the ADR gate above.
- **5.2** Update `SKILL.md` body line 15–16: remove "direct-edge only" and the "transitive coverage
  … deferred" claim; state transitive coverage is now included (cite #5777 / ADR-071 amendment).
  **Do NOT edit the `description:` frontmatter** (no budget impact).
- **5.3** No `plugin.json`/`README` count change (no new component — same skill). release-docs not
  needed.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — The reachable rule is added to BOTH `references/depcruise-config.template` and
  `apps/web-platform/.dependency-cruiser.cjs`, **byte-identically** (`parity.test.sh` test #1 green).
- [ ] **AC2 (D1)** — The shared `options.tsPreCompilationDeps` is `false`; the direct rule no longer
  carries `dependencyTypesNot`; `computeClientFromSet()` is computed once and shared by both rules.
  Phase 0.3 evidence recorded: the **direct-rule** violation set is byte-identical before/after the
  flip (or D1-alt adopted, with the divergence documented).
- [ ] **AC3 (type-only, both directions)** — `boundary.test.sh` asserts: a transitive value chain
  (`client → lib/helper → server(value)`) is FLAGGED; a terminal-`import type` chain PASSES; a
  **first-hop** `import type` chain (`client → import type helper → server(value)`) PASSES. All
  three via the real `.cjs`.
- [ ] **AC4 (D2, zero reachability baseline)** — the committed
  `.dependency-cruiser-known-violations.json` contains **zero** `type:"reachability"` entries;
  a guard (boundary.test.sh, and the runner if adopted) FAILS if one is present. The reachable rule
  is GREEN on HEAD without any reachability suppression.
- [ ] **AC5 (real leaks fixed, not grandfathered)** — every real transitive leak enumerated in
  Phase 0.4 is fixed in this PR (import moved behind a server boundary); `VALUE_SAFE_PATH` contains
  ONLY security-reviewed value-safe modules, each with a justification comment. No real leak is
  added to `pathNot` or the baseline.
- [ ] **AC6 (helper outside scan roots)** — a fixture with the helper in `lib/` (outside
  `app|components|server`) proves transitive-through-non-scanned-root reachability is caught
  (dep-cruiser follows it; `doNotFollow` is node_modules-only).
- [ ] **AC7 (anti-vacuity)** — when the toolchain is present (`PARSED_COMPONENTS >= 1`) the new
  transitive assertions execute and FAIL (not SKIP) if a negative fixture is unflagged; the
  `test-webplat` shard exercises them.
- [ ] **AC8 (fail-closed preserved)** — the reachable rule shares `computeClientFromSet()`, so the
  empty-from-set hard error, the `(?!)` never-match sentinel, the "neither app/ nor components/"
  hard error, and the symlinked-source hard error apply to it identically (existing AC5/AC6b
  self-tests still green).
- [ ] **AC9 (runner reused, version pinned)** — `constraint-gates.sh` runs the single existing
  cruise (plus at most the additive D3 guard); `apps/web-platform/package.json` still pins
  `dependency-cruiser@^16.10.0` (no bump); `parity.test.sh` tests #1 & #2 green.
- [ ] **AC10 (green on HEAD)** — `cd apps/web-platform && ./node_modules/.bin/depcruise --config
  .dependency-cruiser.cjs --ignore-known .dependency-cruiser-known-violations.json --output-type err
  app components server` exits 0; the same invocation is used in the runner, the CI workflow, and
  the observability `discoverability_test`.
- [ ] **AC11 (ADR/C4)** — ADR-071 amended (Decision + Alternatives + Consequences record #5777/NG5
  closed); no `.c4` edit needed (enumeration in §C4 confirms zero new actors/systems/relationships);
  `/work` confirms against the 3 `.c4` files.
- [ ] **AC12 (docs/typecheck/tests)** — `SKILL.md` body no longer claims "direct-edge only"; the
  `description:` frontmatter is unchanged (no budget check); `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` and the existing test suites pass.

### Post-merge (operator)

- [ ] **AC13** — None. No provisioned infra, no operator mint, no migration. The dogfood gate runs
  in CI automatically on the next `apps/web-platform/**` PR. Auto-recovery (ADR-074) handles a
  tripped gate agent-free from the founder's perspective.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (minimal). Product = NONE. Carry-forward from the
parent brainstorm's `USER_BRAND_CRITICAL=true` triad (CTO/CPO/CLO); this v2 extends the same gate.

### Engineering (CTO) — reviewed (carry-forward + v2 deltas)
dep-cruiser remains the correct engine. The v2-specific architectural decisions (D1 single-config
`tsPreCompilationDeps` flip; D2 zero-reachability-baseline via `pathNot`+fix to defeat per-origin
suppression; D3 guard) were derived from two independent verifications of the installed library
source and are documented above for CTO/architecture-strategist scrutiny at deepen-plan/review. The
lethal failure mode (a green gate over a real transitive leak) is closed by D2 + D3 + the
both-directional type-only fixtures. deepen-plan (single-user threshold) will re-run
architecture-strategist + a precedent check.

### Legal (CLO) — reviewed (carry-forward)
No new legal surface. dependency-cruiser MIT, already vendored. No PII / GDPR data-processing
surface (CI tooling). Matches parent's assessment.

### GDPR / Compliance Gate (Phase 2.7)
Trigger (b) (`single-user incident`) fires, but the change touches no regulated-data surface — no
schema/migration/auth/API-route, no LLM on operator data. Documented no-op (carry-forward).

### Product/UX Gate
**Tier:** none. No UI surface — the change is a CI/config/test extension. Files to Create/Edit
contain no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, modal, banner, or flow.
(The `.tsx` files in fixtures are synthesized under mktemp by `boundary.test.sh` — not committed UI
surfaces.) spec-flow-analyzer ran (Phase 3); its P0/P1/P2 findings are folded into D1/D2/D3 + the
fixtures + AC3–AC7.

## Open Code-Review Overlap

**None.** 61 open `code-review` issues checked (2026-07-01) against every path in Files to
Create/Edit (`.dependency-cruiser.cjs`, `depcruise-config.template`, `constraint-gates.sh` /
`shared-runner.template`, `boundary.test.sh`, `.dependency-cruiser-known-violations.json`, ADR-071,
`constraint-scaffold/SKILL.md`) — zero overlap.

## Files to Create

- None expected under D1. (Under the D1-alt fallback only:
  `apps/web-platform/.dependency-cruiser-reachable.cjs`,
  `plugins/soleur/skills/constraint-scaffold/references/depcruise-reachable-config.template`, and
  its baseline — plus a parity assertion. Named here so the fallback is scoped, not a surprise.)

## Files to Edit

- `plugins/soleur/skills/constraint-scaffold/references/depcruise-config.template` — D1 flip +
  reachable rule + `pathNot` + comments (Phase 1.1).
- `apps/web-platform/.dependency-cruiser.cjs` — byte-identical to the template (Phase 1.2).
- `apps/web-platform/.dependency-cruiser-known-violations.json` — re-captured via a single
  `--refresh-baseline`; MUST show zero reachability entries (Phase 2.3).
- `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` — negative + both-directional
  positive + `lib/`-helper + `pathNot`-target fixtures, anti-vacuity guard, zero-reachability-entry
  baseline assertion (Phases 3.1, 4).
- `plugins/soleur/skills/constraint-scaffold/references/shared-runner.template` +
  `apps/web-platform/scripts/constraint-gates.sh` — optional additive D3 runner guard, byte-identical
  (Phase 3.2).
- `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` — amend
  (Phase 5.1).
- `plugins/soleur/skills/constraint-scaffold/SKILL.md` — body prose only, remove "direct-edge only"
  (Phase 5.2).
- `apps/web-platform/lib/*.ts` (and/or the real client/helper files) — ONLY the specific files
  Phase 0.4 identifies as real transitive leaks (cannot be enumerated at plan time; scan-derived).

## Risks & Mitigations

- **R1 — the `tsPreCompilationDeps` flip changes the direct-rule set (silent v1 regression).**
  Mitigation: Phase 0.3 byte-identity GATE; D1-alt two-config fallback preserves v1 untouched.
- **R2 — per-origin reachability baseline grandfathers a future real leak (the P0 fail-open).**
  Mitigation: D2 (zero reachability baseline via `pathNot`+fix) + D3 guard (fail if any reachability
  entry is committed). This is the load-bearing brand-survival mitigation.
- **R3 — type-only chain false-positives (naive per-edge filter, impossible anyway).**
  Mitigation: global elision (`tsPreCompilationDeps:false`) + both-directional type-only fixtures
  (AC3), incl. the load-bearing first-hop case.
- **R4 — new transitive assertions silently skipped in a toolchain-absent shard.** Mitigation:
  anti-vacuity guard (AC7); coverage guaranteed in `test-webplat`.
- **R5 — real pre-existing transitive leaks larger than expected.** Mitigation: Phase 0.4 enumerates
  before any commit; if the fix set is large/risky, STOP and surface for scoping — never grandfather
  (a scoped follow-up for a subset is acceptable; a baselined reachability entry is not).
- **R6 — reachable traversal too slow on ~170 client modules (CI timeout).** Mitigation: Phase 0.5
  perf probe; tighten `to.path`/`pathNot`; set a runner timeout budget if needed.
- **R7 — auto-recovery (ADR-074) can't auto-fix a transitive chain.** Acceptable: it is fix-only and
  never grows the baseline; an un-auto-fixable transitive leak surfaces for a maintainer (unchanged
  contract). No fix-constraints template edits in this PR.

## Sharp Edges

- The reachable `to` object is **schema-locked** (`{path,pathNot,reachable}`, `additionalProperties:
  false`) in dep-cruiser v16.10.x. Adding `dependencyTypesNot`/`viaOnly`/`via` there fails config
  validation — verify the `.cjs` parses (`node -e 'require("./.dependency-cruiser.cjs")'`) as part
  of Phase 1.
- Reachability baseline suppression is **per-origin** (`from`+`rule.name`, ignores `to`/`via`). A
  reachability entry in the baseline is NEVER benign — it blinds that client to all transitive
  secrets. D3 guard enforces zero.
- `tsPreCompilationDeps:false` is a **shared `options`** flip — it changes BOTH rules and must be
  mirrored into the template (byte-diff). Re-prove ALL existing `boundary.test.sh` assertions after
  the flip (AC3 typeonly PASSES, value FLAGGED, `couldNotResolve==0`).
- The reachable rule is a **superset** of the direct rule (a direct edge is a length-1 path), but
  `pathNot`-excluding the value-safe targets means it does NOT re-flag v1's baselined direct edges —
  the baseline does not double. Confirm this empirically in Phase 2.3 (baseline ≈ unchanged).
- Do NOT edit `package.json` — the version pin is part of the "no drift" requirement. The reachable
  rule needs no newer dep-cruiser (reachable + `pathNot` are stable since long before 16.10).
- `constraint-scaffold.sh --refresh-baseline` is **agent-only** (never shown to the founder); it
  needs `node_modules` installed and a clean tree, and captures against the origin/main merge-base.
