---
issue: 6793
type: chore
lane: single-domain
brand_survival_threshold: none
status: draft
created: 2026-07-22
---

# chore: extend the gh `--search` `--state` explicitness lint repo-wide + add `-L`/`--limit` truncation coverage

Closes #6793.

The `--state` explicitness lint added in #6786 (`plugins/soleur/test/components.test.ts`,
`describe("collision-gate probes carry an explicit --state")`) is scoped to
`skills/**/*.md` under `plugins/soleur/`. It catches `gh pr|issue list --search` probes that
omit an explicit `--state` (the silent fail-open where the appended default `--state open`
filter drops MERGED/CLOSED records and an empty result is indistinguishable from "no matches").
Repo-wide there are further real `gh (pr|issue) list --search` executable call sites the lint
never sees, and a *second* failure of the identical shape — a probe whose result set is
silently capped at gh's 30-row default (`-L`/`--limit` omitted) — is uncovered entirely.

This plan (a) widens the scan surface from `plugins/soleur/skills/**/*.md` to a repo-wide
allowlist of **executable-instruction surfaces**, and (b) adds a `-L`/`--limit` truncation
detector for the same silent-open class. It brings the handful of genuine violations the
widened lint surfaces into compliance, and preserves one anchored regression fixture
byte-identical (see Deliberate Scope Constraint).

## Enhancement Summary

**Deepened on:** 2026-07-22 (headless one-shot pipeline)
**Review agents:** code-simplicity-reviewer, verify-the-negative pass (Explore), scan-surface gap check. (architecture-strategist was spawned; its result did not return before synthesis — findings below are from the two that reported plus the direct gap checks.)

### Key improvements applied
1. **Simplified D3 (YAGNI).** Replaced the general `GH_SEARCH_LINT_WAIVERS` framework (array + class-union type wired into all three detectors, servicing exactly one exception) with a **single inline `linked:issue`-shape exemption** in `findUnlimitedProbes`. It encodes the real invariant (a `linked:issue #N` result set is domain-bounded to one issue's formally-linked PRs, so *any* such probe is truncation-safe), still keeps `one-shot/SKILL.md:55` byte-identical, and drops mutation M5. Introduce the array only when a genuinely different exception class appears.
2. **Added two missed executable surfaces** (verify-the-negative + gap check): `plugins/soleur/agents/**/*.md` (carries a real stateless probe — `deployment-verification-agent.md:103`) and `.github/workflows/**/*.yml` + `.github/actions/**/*.yml` (17 already-compliant `gh --search` sites — highest-value prod-CI surface). Repo-wide stateless-violation count is now **5**, not 4.
3. **Precise fixture exclusion.** `.test.sh` files are excluded by *scan-scope* (only `scripts/*.sh` is admitted, not `test/**/*.test.sh`), NOT by the `.ts` filter; the lint's OWN test file `plugins/soleur/test/components.test.ts` (full of intentional broken forms) is excluded because it is `.ts`. Both are documented so a future maintainer does not accidentally admit them.
4. **AC discipline.** Stripped the D3-mechanism encoding from AC3 (checkable post-condition is `git diff` no-change + suite GREEN, not "via a waiver"); relabeled the mutation battery (AC7) as a verification protocol and codified M1/M2/M4 as permanent synthesized negative controls.

### New consideration discovered
- `--jq length` consumers (`rule-prune.sh:239`, `ux-audit/SKILL.md:105`, `deployment-verification-agent.md:103`) are NOT existence-drills under D2 (the detector cannot tell `count >= 1` from `count == N`), so they are correctly flagged by the truncation detector — the fix is to add an explicit generous `-L`, which makes the count correct regardless of intent.

## Deliberate Scope Constraint (load-bearing — do NOT "fix")

`plugins/soleur/skills/one-shot/SKILL.md:55` (the `gh pr list --search "linked:issue #<N>"
--state all …` probe) is the **anchored regression fixture** #6793 cites as evidence of the
defect class. It already carries `--state all` and is correct as-is. It enumerates `.[]` and
carries **no** `-L`/`--limit` (deliberate — a single issue's formally-linked PR set is bounded
well under 30). The new `--limit` detector would otherwise newly flag it.

**Requirement:** this line stays **byte-identical**. The lint must not force a rewrite of it.
It is exempted via a **principled in-detector exemption** (D2(b) — its `--search` is the bounded
`linked:issue #<N>` shape), which lives in the detector's own logic in the test file, so neither
the probe line nor any adjacent line in `one-shot/SKILL.md` is edited. The line then serves as a
live, in-corpus regression fixture that proves the widened lint keeps seeing the real probe surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The artifact is a CI
  test (`plugins/soleur/test/components.test.ts`). A false-positive red-lines a PR (developer
  friction); a false-negative lets a silent-open `gh --search` probe ship in internal tooling
  (workflow-reliability regression of the collision-gate class — the 2026-05-29 / 2026-07-18 /
  2026-07-20 incidents), never a customer surface.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — no user data, secrets,
  or runtime path is touched. The diff is a test file + a few internal scripts/runbooks.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches only CI test code, an internal maintenance script, a
  command doc, and an ops runbook — no auth/migration/secret/payment/user-data path (preflight
  Check 6 sensitive regex does not match).`

## Research Reconciliation — Spec vs. Codebase

Premise validation (plan Phase 0.6) run 2026-07-22 against worktree state:

| Claim (issue #6793 / task) | Reality (verified 2026-07-22) | Plan response |
|---|---|---|
| Lint is scoped to `skills/*/SKILL.md` | Actually `skills/**/*.md` under `PLUGIN_ROOT` (already wider than SKILL.md per #6786 review; the `references/` probe drove that widening). Still plugin-local, not repo-wide. | Widen from plugin-local to a repo-wide executable-surface allowlist. |
| "~19 further call sites" repo-wide | A raw grep returns ~275 lines, but the overwhelming majority are **prose about** the command (learnings/plans/specs) or **negative-test fixtures** (`.ts` test files that deliberately encode the broken form). Real **executable stateless** probes on executable surfaces (excl. already-covered skills): exactly **4** — `scripts/rule-prune.sh:239`, `plugins/soleur/commands/sync.md:165`, `knowledge-base/engineering/operations/runbooks/inngest-server.md:990`, `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md:284`. | Scan surface = allowlist that admits executable surfaces and excludes prose/record surfaces. Fix the 4 (re-derive at /work — line numbers drift). |
| `.github/workflows/**` executable surface | 17 `gh issue list --search` sites (scheduled-inngest-health, scheduled-zot-restart-loop, apply-inngest-rls[-dev]) — **all already compliant** (`--state open` + `.[0]` existence drill). Highest-value executable surface; was omitted from the first-draft allowlist. | Add to D1 scan surface. Zero new violations; adds prod-CI coverage. |
| `plugins/soleur/agents/**` executable surface | Deepen verify-the-negative + architecture passes found `agents/engineering/review/deployment-verification-agent.md:103` — a **live stateless+limitless** probe (`--label incident --search "created:>…" --jq length`). Agent bodies are executable-instruction surfaces the first draft omitted. | Add to D1; fix the probe (`--state all` + `-L`). Repo-wide stateless count → **5**. |
| First-draft `-L` exemption soundness | Deepen architecture pass proved `.[0]`/`// empty` is NOT truncation-safe when a jq `select(…)` narrows *after* the 30-row cap (`content-publisher.sh:785`, `rule-prune.sh:239`). | D2 exemption requires existence-drill **AND no post-search narrowing**; adds `content-publisher.sh:785` as a limit fix. |
| Waiver framework (first draft) | Deepen simplicity pass: a general waiver array for N=1 is YAGNI. | Replaced by a principled in-detector `linked:issue #N` bounded-shape exemption (D2b/D3); line 55 still byte-identical. |
| `linked:issue` line is the byte-identical fixture | Confirmed at `one-shot/SKILL.md:55`; `--state all`, no `-L`, enumerates `.[]`. | D2(b) bounded-shape exemption (detector logic); do not edit. |
| Enumerated starting points (`sync.md:165`, `rule-prune.sh:239`, `inngest-server.md:990`) | All three present and stateless as described. | Fixed by this PR. |
| `#5095`/`#5097` rename-guard collision | Deterministic on every one-shot run; tracked in those compound issues; today's recurrence appended there. | **Context only — do NOT close.** Not a work target. Net issue flow for this PR = −1 (closes #6793 only). |

## Overview

The lint is a single `describe` block in `plugins/soleur/test/components.test.ts` (lines
~370–580). Its detectors and anti-vacuity machinery are already battle-tested (they were
themselves the subject of the 2026-07-20 "the lint I wrote to catch a fail-open shipped the
same fail-open" learning). This change **extends**, not rewrites: it keeps every existing
detector and corpus assertion and adds two orthogonal capabilities.

Two design forces are in tension and must both be honored:

1. **Repo-wide reach** — the class recurs outside the plugin (scripts, hooks, runbooks).
2. **No prose/fixture noise** — most repo-wide grep hits are documentation *about* the command
   or deliberate broken-form fixtures. Flagging those is the false-positive failure mode that
   makes a repo-wide lint un-shippable.

The resolution is a **file-surface allowlist** (coarse prose-vs-command boundary) plus
**principled in-detector exemptions** (existence-drill-without-narrowing; bounded-query-shape) —
no general waiver framework. The one intentional exception (the byte-identical `linked:issue #N`
fixture) falls out of the bounded-query-shape exemption, not a per-site waiver.

## Key Design Decisions

**D1 — Scan surface = explicit INCLUDE glob allowlist of executable-instruction surfaces.**
Scan (relative to a new `REPO_ROOT = resolve(PLUGIN_ROOT, "../..")`):
- `plugins/soleur/skills/**/*.md`, `plugins/soleur/commands/**/*.md`,
  **`plugins/soleur/agents/**/*.md`** (executable instructions — agent bodies instruct agents to
  run `gh` exactly as skills/commands do; **occupied**: `agents/engineering/review/deployment-verification-agent.md:103`
  carries a live stateless+limitless probe, found by the deepen verify-the-negative + architecture passes)
- `scripts/**/*.sh` **and `plugins/soleur/skills/**/scripts/*.sh`** (repo-root `scripts/` does NOT
  match skill-shipped scripts like `ship/scripts/*.sh`, `drain-prs/scripts/*.sh`,
  `model-launch-review/scripts/audit-models.sh` — ~70 runnable `gh`-calling shell files that the
  first draft left blind; currently clean but in-class per defect-class indexing)
- `.claude/hooks/**/*.sh`, `.openhands/hooks/**/*.sh`
- `.github/workflows/**/*.{yml,yaml}`, `.github/actions/**/*.{yml,yaml}` (the most-executable
  surface — CI `run:` blocks that actually invoke `gh` in production; **17 `gh issue list --search`
  sites found 2026-07-22, all already compliant** — `--state open` + `.[0]` existence drill — so
  they add coverage at zero fix cost. `.yaml` included defensively though only `.yml` exists today)
- `knowledge-base/engineering/operations/runbooks/**/*.md` (executable ops steps; the issue's
  own `inngest-server.md` target lives here)

Explicitly **excluded** (prose/record/fixture surfaces — the "context restriction" the issue
called for), each by a **specific mechanism** (the deepen architecture pass flagged that the
first draft conflated two different exclusion reasons):
- `knowledge-base/project/**` (learnings, plans, specs — historical prose), everything under
  `knowledge-base/` outside `.../runbooks/`, and `**/archive/**` — excluded by **not being in the
  INCLUDE globs**.
- `**/*.test.sh` (e.g. `apps/.../scan-workflow.test.sh`, `plugins/soleur/test/schedule-skill-once.test.sh`)
  — excluded by **scan-scope**: only `scripts/*.sh` + `skills/**/scripts/*.sh` are admitted, and
  test fixtures live elsewhere; add an explicit `!**/*.test.sh` guard so a future `scripts/foo.test.sh`
  cannot accidentally enter scope.
- All `.ts`/`.py` non-shell files — excluded by the **`.ts`/`.py` filter**. This drops the
  deliberate negative-test fixtures in `cron-claude-eval-substrate.test.ts` **and the lint's OWN
  test file `plugins/soleur/test/components.test.ts`** (which is full of intentional broken forms
  at lines 440/456/479/491/505/514/522 — these would ALL false-positive if scanned). **Residual
  (documented, not silently ignored):** the `.ts` filter is coarse — it also drops real
  agent-prompt-string probes like `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts:159`
  (`gh pr list --state open --search 'roadmap.md in:files'`, state-compliant but `-L`-flaggable).
  Scanning `.ts` would drag in the fixtures, so v1 excludes `.ts` wholesale; a tighter future form
  (`*.ts` minus `*.test.ts`/`*.spec.ts`/`__fixtures__`) is the re-open path (see Non-Goals).

This is **defect-class indexing, not result-set indexing** (2026-07-20 learning): the surface is
chosen by "which files carry executable instructions," not by where a grep found offenders.

**Extractor surface-type handling.** The fenced-vs-inline distinction is **markdown-specific**
(fence tracking only runs for `.md`). For `.sh` and `.yml`/`.yaml` surfaces there are no markdown
fences — every non-comment line is a candidate command line, and the fence flag is always `false`.
The existing per-line `GH_LIST_CMD` regex is surface-agnostic and needs no change; the corpus
builder tags each file with its surface type so the "both classes represented" assertion (D6)
scopes correctly (inline+fenced applies to the markdown subset; `.sh`/`.yml` contribute to a
separate non-empty assertion).

**D2 — New `-L`/`--limit` truncation detector (`findUnlimitedProbes`).** A search probe that
omits both `-L` and `--limit` is flagged **unless** it qualifies for one of two *principled*
exemptions:

- **(a) Existence-drill with NO post-search narrowing.** The jq consumer drills to one element
  (`.[0]`, `// empty`, `first(`) OR `--limit 1` is present, **AND** the jq contains no
  result-set-narrowing filter (`select(`, `map(select`, `| length` used as a count, etc.) between
  the search and the drill. Rationale: truncation only fails **open** when completeness carries
  the decision; a pure existence check ("does ≥1 row exist?") is safe at 30 (if >30 match, ≥1
  certainly does). **The "no post-search narrowing" clause is load-bearing — the deepen
  architecture pass proved the first-draft `.[0]`-only exemption is UNSOUND:** a probe like
  `content-publisher.sh:785` (`--search "in:title \"$title\"" … --jq "[.[] | select(.title == \"$title\")] | .[0].number // empty"`)
  fuzzy-searches, then the exact-match `select` runs *after* the 30-row truncation — if the exact
  match sits at row 31+ it is evicted before `select` sees it → empty → duplicate filed = the exact
  fail-open this lint exists to catch. `.[0]` + `// empty` are present, so the naive exemption would
  wave it through. The 17 workflow probes (`.[0].number // empty`, **no** `select`) are genuinely
  safe and correctly exempt.
- **(b) Bounded-cardinality query shape:** the `--search` string matches `linked:issue #<N>` — a
  single issue's *formally-linked* PR set, bounded by domain semantics well under 30. This exemption
  (not a waiver) is what keeps `one-shot/SKILL.md:55` unflagged while byte-identical (see D3).

Everything else lacking `-L`/`--limit` is flagged. Cost note (2026-07-20 perf-oracle): `-L 100`
costs the same GraphQL budget as the 30-default, so the fix for a flagged site is always
"add `-L <generous>`", never "narrow the query".

**D3 — The byte-identical fixture is handled by a principled in-detector exemption, NOT a waiver
framework.** The first draft proposed a general `GH_SEARCH_LINT_WAIVERS` array (keyed by content
substring, wired into all three detectors) to service exactly one exception. The deepen
simplicity pass flagged this as YAGNI, and the cleaner design — adopted here — is D2 exemption (b):
`findUnlimitedProbes` skips any probe whose `--search` is the `linked:issue #<N>` bounded shape.
This encodes the *actual invariant* (linked:issue sets are domain-bounded) rather than pinning one
opaque string, needs no array / class-union type / three-detector wiring, and — critically — still
keeps `one-shot/SKILL.md:55` **byte-identical** (the exemption is detector logic; line 55 is never
edited; `git diff --exit-code -- plugins/soleur/skills/one-shot/SKILL.md` enforces it). The shape
match is anchored on `linked:issue\s+#` so it cannot exempt a hypothetical unrelated `linked:issue`
enumeration. **Reviewer dissent recorded:** the architecture pass preferred *keeping* an out-of-line
waiver but hardened (keyed by `{file, substr}` + a longer key) over an inline exemption; this plan
chose the bounded-shape exemption because it is both simpler (no framework) and more correct (the
invariant is real for every `linked:issue #N` probe, not just this line). If a *genuinely different*
exception class ever appears — one not reducible to a query-shape or existence invariant — introduce
the `{file, substr, reason}` waiver array *then* (the second case justifies the abstraction, not the
first).

**D4 — Bring the genuine violations into compliance (re-derive at /work).** The widened detectors
surface a small, concrete set. **Do not trust these line numbers — re-derive with the extractor at
/work time (the issue explicitly warns line numbers drift).** Verified 2026-07-22 across all three
deepen passes:

*Stateless (add explicit `--state`) — 5 sites:*
- `scripts/rule-prune.sh:239` — dedup; add `--state all` (a *closed* duplicate issue currently gets
  re-filed — genuine latent bug). **Also `-L`-flagged** (see below): the `[.[] | select(.title==$t)] | length`
  runs after truncation → add a generous `-L` too.
- `plugins/soleur/commands/sync.md:165` — described dedup says "whether an **open** issue already
  exists"; pin `--state open` explicitly (same invariant, made explicit).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md:990` (`head:bot-fix/` PR filter)
  — add `--state all` **and** a generous explicit `-L` (enumerates all bot-fix PRs; truncation-prone).
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md:284` (`$CANONICAL_TITLE
  in:title` dedup) — add explicit `--state`.
- `plugins/soleur/agents/engineering/review/deployment-verification-agent.md:103`
  (`--label incident --search "created:>…" --jq length`) — add `--state all` **and** a generous `-L`
  (the `length` count consumes the truncated set).

*Unlimited-only (already `--state`-compliant, add explicit `-L`) — the select-after-truncation /
count-consuming class the deepen architecture pass surfaced:*
- `scripts/content-publisher.sh:785` — `--state open` present, but `select(.title==…)` runs after the
  30-row truncation → **fail-open latent bug**; add a generous `-L`. (This site was NOT in the first
  draft's fix list — the naive `.[0]` exemption hid it.)
- `plugins/soleur/skills/ux-audit/SKILL.md:105` — `--state all` present, `--jq length` on a unique
  hash (bounded to ≤1) → add an explicit `-L` (the invariant made explicit; harmless).
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md:113` — the
  `created:<window>` enumeration (already `--state all`): add a generous explicit `-L`.

Every flagged executable site is fixed (add the explicit flag) — no site is left silently red, and
no site needs a waiver (the only exemption is D2(b), the `linked:issue #N` bounded shape). Re-run the
extractor at /work to catch any site these passes missed or that drifted.

**D5 — Comment-line handling in the extractor.** For `.sh` **and `.yml`/`.yaml`** surfaces, the
extractor skips lines whose first non-space character is `#` (shell/YAML comments are the prose
surface — e.g. `rule-prune.sh:5`/`:226` and `audit-models.sh:162`'s `echo` describe the command; a
commented-out `gh` line in a workflow must not false-positive). The `echo "… gh issue list --search
…"` line in `audit-models.sh:162` is a print statement, not a probe — D5's `#`-skip does not catch it,
so it is a genuine candidate the extractor WILL see; it is a doc/echo string, so if flagged it is
fixed to the explicit form or the echo is reworded (re-derive at /work). Markdown fence tracking is
unchanged. Targeted extractor addition, not a rewrite.

**D6 — Preserve and extend the anti-vacuity / anti-launder machinery.** Keep verbatim: the
line-bounded capture `\bgh (?:pr|issue) list\b[^`\n]*` (NEVER revert to newline-spanning
`[^`]*` — that was the launder-by-neighbor bug, 2026-07-20), the per-line fence-independent
evaluation, the synthesized negative-control fixtures, and the "both probe classes represented"
corpus assertion. **Add:** (a) synthesized negative controls that the `--limit` detector flags
a truncatable enumeration probe, flags a `select`-after-search probe *even with* a trailing `.[0]`
(the D2 unsoundness fix), accepts a pure existence drill (no narrowing) and an explicit `-L`, and
accepts the `linked:issue #<N>` bounded shape — these controls carry the detector's discriminating
power independent of the live corpus; (b) a corpus assertion that the widened scan is **wider than
the plugin-local surface** (analogous to the existing "wider than `skills/*/SKILL.md`" assertion —
pins the widening so a later narrowing red-lines here). **Do NOT** add a live-corpus "≥1 real
unlimited representative" assertion: once the D4 sites are fixed and the sole remaining unlimited
probe (line 55) is exemption-(b)'d, that assertion would be empty while `findUnlimitedProbes(corpus)`
must ALSO be `[]` — a self-contradiction (the deepen architecture pass flagged this). The synthesized
controls in (a) are the correct non-vacuity guard; if a live-corpus liveness check is wanted, measure
it on the **pre-exemption `extractSearchProbes(files)`** population (as the existing "both classes
represented" test does), never on the post-exemption offender set.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
1. Re-run the extractor's own regex repo-wide to **re-derive** the current executable-surface
   violation set (line numbers WILL differ from this plan). `git grep -nE 'gh (pr|issue) list\b[^`\n]*--search'` across the D1 allowlist, minus `--state`/`--limit`-carrying lines.
2. Confirm `one-shot/SKILL.md` still contains the `linked:issue #<N>` probe verbatim (the D2(b)
   exemption target).
3. Confirm `REPO_ROOT = resolve(PLUGIN_ROOT, "../..")` resolves to the repo root from the test's
   location (`plugins/soleur/test/`).

### Phase 1 — Extend the lint (RED first)
1. Add `REPO_ROOT` and the D1 INCLUDE-glob corpus builder (multi-glob scan, dedup by path;
   `!**/*.test.sh` guard; per-file surface-type tag).
2. Add D5 comment-line skipping (`.sh` + `.yml`/`.yaml`) to the extractor.
3. Add `findUnlimitedProbes` (D2) with the two principled exemptions: existence-drill **without
   post-search `select(`/narrowing** (D2a) and the `linked:issue\s+#` bounded shape (D2b). No
   waiver framework.
4. Add the D6 synthesized negative-control tests for the new detector — including the
   D2-soundness control (a `select`-after-search probe with a trailing `.[0]` MUST be flagged).
   Write these as failing assertions first where practical (`cq-write-failing-tests-before`).
5. Update the corpus assertions: widen the "both classes represented" + "wider than plugin-local"
   assertions to the repo-wide surface. Do NOT add a post-exemption "≥1 unlimited representative"
   assertion (D6 — self-contradiction once line 55 is exempt and D4 sites are fixed).

### Phase 2 — Bring genuine violations into compliance (GREEN)
1. Apply D4 fixes to the re-derived executable sites (add explicit `--state` / `-L`).
2. Confirm the D2(b) `linked:issue #<N>` exemption keeps line 55 unflagged — verify the fixture
   LINE is byte-identical (`diff` of `sed -n '55p'` from origin/main vs HEAD is empty). Do NOT
   assert a whole-file `git diff --exit-code`: the repo-wide `-L` sweep legitimately fixes a
   *different* enumerating probe at `one-shot/SKILL.md:180`, so the file as a whole changes.
3. Run the mutation battery (see Test Scenarios) to prove each new assertion has real
   discriminating power, then confirm the un-mutated suite is GREEN.

### Phase 3 — Corpus + docs
1. In-code comment block documenting each detector's assertion dimension (state presence /
   state non-contradiction / limit presence-or-existence-drill-without-narrowing / bounded-shape
   exemption), so the prose-in-code matches what the checks assert (2026-05-16 dimension-drift
   discipline).

## Files to Edit
- `plugins/soleur/test/components.test.ts` — the lint extension (repo-wide scan surface, `--limit`
  detector with the two principled exemptions, corpus assertions, synthesized negative controls).
  **Primary file.**
- `scripts/rule-prune.sh` — add `--state all` + generous `-L` to the dedup probe (re-derive line).
- `scripts/content-publisher.sh` — add generous `-L` (select-after-truncation fail-open fix).
- `plugins/soleur/commands/sync.md` — make the described dedup `--state` explicit (re-derive line).
- `plugins/soleur/skills/ux-audit/SKILL.md` — add explicit `-L` to the hash-dedup probe.
- `plugins/soleur/agents/engineering/review/deployment-verification-agent.md` — add `--state all`
  + `-L` to the incident-signal probe.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — add `--state all` + `-L`
  to the `head:bot-fix/` probe (re-derive line).
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — add explicit
  `--state` / `-L` to the two probes (re-derive lines).

*(The exact edited set is re-derived at /work via the Phase 0 grep; a site that turns out
already-compliant is dropped from this list. There are no waivers — the only exemption is the
D2(b) `linked:issue #N` bounded shape, which is detector logic, not a per-site edit.)*

## Files to Create
None.

## Observability

```yaml
liveness_signal:
  what: "CI test — plugins/soleur/test/components.test.ts describe(collision-gate probes …) runs on every PR"
  cadence: per-PR (and per push via scripts/test-all.sh)
  alert_target: "GitHub PR status check (red = offender list printed in the failing assertion message)"
  configured_in: "plugins/soleur/test/components.test.ts (describe block); package.json test -> scripts/test-all.sh"
error_reporting:
  destination: "bun test assertion output in CI logs (no Sentry — this is a build-time lint, not a runtime path)"
  fail_loud: "the assertion message enumerates each offending file:cmd, so the failing check names the exact probe"
failure_modes:
  - mode: "a new stateless / truncatable gh --search probe lands on an executable surface"
    detection: "findStatelessProbes/findUnlimitedProbes returns it; assertion toEqual([]) fails and prints file:cmd"
    alert_route: "PR author via the red required check"
  - mode: "the scan is silently narrowed (glob regression) so the lint goes vacuously green"
    detection: "the 'wider than plugin-local surface' + 'both classes represented' + unlimited-non-vacuity corpus assertions red-line"
    alert_route: "PR author via the red check"
  - mode: "an exemption over-broadens (D2b bounded-shape match too loose, or D2a narrowing-clause dropped)"
    detection: "the D2-soundness + bounded-shape synthesized controls red-line; code review of the exemption predicate"
    alert_route: "PR author via the red check + code review"
logs:
  where: "CI job logs (bun test output)"
  retention: "GitHub Actions default log retention"
discoverability_test:
  command: "cd plugins/soleur && bun test test/components.test.ts"
  expected_output: "the describe('collision-gate probes carry an explicit --state') block passes; offender assertions are []"
```

## Architecture Decision (ADR/C4)

**No ADR / no C4 impact.** Checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): this change
introduces no external human actor, no external system/vendor, no container or data store, and
no actor↔surface access-relationship change. It is a build-time test-lint design local to one
file, reusing an existing test suite. No competent engineer reading the current ADR/C4 corpus
would be misled about the system after this ships. The one novel convention (file-surface
allowlist + principled in-detector exemptions for a repo-wide markdown/shell/yaml lint) is
contained to the test file and documented in-code + in this plan; if the team wants it reusable it
becomes a `knowledge-base/project/learnings/` entry (see Non-Goals), not an ADR.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an infrastructure/tooling (CI lint) change.
No UI surface (no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` in the file lists),
so the Product/UX gate does not fire. No regulated-data surface (GDPR gate skipped). No new
infrastructure (IaC gate skipped).

## Open Code-Review Overlap

None. Queried open `code-review`-labelled issues (61 open, fetched 2026-07-22) against every
planned file path (`components.test.ts`, `rule-prune.sh`, `inngest-server.md`, `sync.md`,
`cloud-scheduled-tasks.md`) — zero matches.

## Acceptance Criteria (Pre-merge)

- [ ] The lint scans a repo-wide executable-surface allowlist (D1); a corpus assertion proves
      the scanned file count exceeds the plugin-local (`skills/**/*.md`) count and red-lines if
      the surface is narrowed back.
- [ ] `findUnlimitedProbes` exists (D2). Synthesized controls assert it: flags a
      completeness-consuming probe lacking `-L`/`--limit`; **flags a `select`-after-search probe
      even when a trailing `.[0]`/`// empty` is present** (the D2-soundness fix); accepts a pure
      existence drill (no narrowing), `--limit 1`, an explicit `-L`, and the `linked:issue #<N>`
      bounded shape.
- [x] The `linked:issue #<N>` probe **line** at `one-shot/SKILL.md:55` is **byte-identical**
      (`diff <(git show origin/main:…one-shot/SKILL.md | sed -n '55p') <(sed -n '55p' …)` empty),
      and the un-mutated suite is GREEN. (Mechanism — bounded-shape exemption vs anything else — is
      an implementation choice, not part of this criterion.) **/work reconciliation:** the
      constraint is scoped to the fixture LINE, not the whole file — `one-shot/SKILL.md:180` carries
      a *different* probe (`--label code-review … --search "PR #<n>"`, a genuine enumeration, not a
      `linked:issue` shape) that the repo-wide `-L` sweep correctly flagged and fixed. A whole-file
      `git diff --exit-code` therefore intentionally shows that one-line change; line 55 is untouched.
- [ ] Every executable-surface `gh (pr|issue) list --search` probe re-derived at /work is
      compliant (explicit `--state`, and explicit `-L`/`--limit` unless it is a pure existence
      drill with no post-search narrowing OR the `linked:issue #N` bounded shape).
      `findStatelessProbes(corpus)` and `findUnlimitedProbes(corpus)` both return `[]`. No waivers
      exist (the sole exemption is D2(b), in detector logic).
- [ ] The existing anti-launder / anti-vacuity machinery is intact: line-bounded capture (not
      newline-spanning), per-line fence-independent evaluation, "both classes represented"
      corpus assertion, synthesized negative controls — all preserved and extended, not replaced.
- [ ] Prose/record surfaces are not scanned: no assertion fires on `knowledge-base/project/**`
      learnings/plans/specs, `**/archive/**`, `**/*.test.sh`, or `.ts`/`.py` files (including the
      lint's own `components.test.ts`).
- [ ] `bash scripts/test-all.sh` (or `cd plugins/soleur && bun test test/components.test.ts`)
      is GREEN.
- [ ] PR body uses `Closes #6793` (net issue flow −1). #5095 / #5097 are NOT referenced as
      closed — they remain open (context only).

## Test Scenarios

Detector unit behavior (synthesized fixtures — `cq-test-fixtures-synthesized-only`, no file I/O):
- Given a probe `gh pr list --search "topic" --json number` (no `--state`, no `-L`, enumerates),
  When `findStatelessProbes` runs, Then it is flagged; When `findUnlimitedProbes` runs, Then it
  is flagged.
- Given `gh issue list --search "t in:title" --state all --json number --jq '.[0].number // empty'`
  (existence drill, NO post-search narrowing), When both detectors run, Then neither flags it.
- **(D2-soundness control)** Given `gh issue list --state open --search "in:title \"$t\"" --json number,title --jq "[.[] | select(.title == \"$t\")] | .[0].number // empty"`
  (a `.[0]`/`// empty` drill BUT a `select(` narrows after the search), When `findUnlimitedProbes`
  runs, Then it **IS** flagged (the post-search narrowing defeats the existence exemption); adding
  an explicit `-L` clears it.
- Given `gh pr list --search "linked:issue #5" --state all --json number --jq '.[] | .number'`
  (enumerates, no `-L`), When `findUnlimitedProbes` runs, Then it is NOT flagged (D2(b) bounded
  shape); Given the same command with `linked:issue` replaced by an unbounded query, Then it IS
  flagged (the exemption is anchored on `linked:issue\s+#`).
- Given `gh pr list --search "a is:merged" --state open` (query/flag state contradiction),
  When `findContradictingStateProbes` runs, Then it is flagged (unchanged behavior).
- Given a fenced block with a stateless probe followed by a later `--state`-carrying different
  command, Then the stateless one is still flagged (launder-by-neighbor guard preserved).
- Given a `.sh` OR `.yml` comment line `# … gh issue list --search "x"`, Then it is NOT treated as
  a command (D5 comment skipping).

Mutation battery. M1/M2/M4 are **also encoded as permanent synthesized negative-control tests**
(checkable post-conditions in the suite); the full sweep below is a /work verification protocol
(each mutation must turn the suite RED; baseline un-mutated must be GREEN first):
- M1: revert capture to newline-spanning `[^`]*` → launder test RED.
- M2: remove the existence-drill / bounded-shape exemption logic → false-positive on safe probes;
      remove the "no post-search narrowing" clause → the D2-soundness control goes GREEN-when-it-should-be-RED.
- M3: narrow the scan back to `skills/**/*.md` under PLUGIN_ROOT → "wider than plugin-local" RED.
- M4: drop `findUnlimitedProbes` from the corpus offender assertion → unlimited-class RED.

## Risks & Sharp Edges

- **`--limit` existence-exemption soundness (highest-risk — nearly shipped a fail-open).** The
  exemption must require existence-drill **AND no post-search `select(`/narrowing** (D2a). A
  `.[0]`/`// empty`-only exemption is UNSOUND: `content-publisher.sh:785` fuzzy-searches, then the
  exact-match `select` runs after the 30-row cap, so the exact match at row 31+ is evicted →
  duplicate filed. The D2-soundness synthesized control (Test Scenarios) is the permanent guard;
  do NOT "simplify" the detector by dropping the narrowing clause. Equally, do NOT "simplify" to a
  bare `!/-L|--limit/` check (flags harmless pure-existence dedups → un-shippable).
- **Byte-identical fixture.** The exemption for line 55 is the D2(b) `linked:issue #<N>` bounded
  shape — detector logic, not an edit near line 55. Verify at end of Phase 2 with
  `git diff --exit-code -- plugins/soleur/skills/one-shot/SKILL.md`.
- **Bounded-shape exemption breadth.** Anchor the D2(b) match on `linked:issue\s+#` so it exempts
  only the genuinely-bounded single-issue link query, not any string containing `linked:issue`.
  (Architecture pass preferred a hardened out-of-line waiver; recorded in D3 — revisit if a
  non-shape-reducible exception ever appears.)
- **Line-number drift.** The issue warns its enumeration was measured 2026-07-20 and drifts.
  Re-derive every edited site at /work via the Phase 0 grep; never hard-code from this plan.
- **Intra-file prose in runbooks / agents.** A runbook or agent body can both *run* and *describe*
  a `gh --search` command inline. The allowlist admits these surfaces (the issue's own
  `inngest-server.md:990` and the agents-surface probe live there), so a genuinely-descriptive
  inline mention that trips a detector is fixed by making the described form explicit — narrowing
  the surface would miss the real targets. No waiver mechanism exists to lean on.
- **`.ts` surfaces out of scope (coarse but documented).** The `.ts` exclusion drops the
  deliberate broken-form fixtures (`cron-claude-eval-substrate.test.ts`) AND the lint's own
  `components.test.ts` — but also real agent-prompt-string probes like `cron-roadmap-review.ts:159`
  (state-compliant, `-L`-flaggable). v1 excludes `.ts` wholesale to avoid fixture noise; the tighter
  `*.ts` minus `*.test.ts`/`*.spec.ts` form is the re-open path (Non-Goals).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this section is filled (threshold `none` + reason).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this section is filled (threshold `none` + reason).

## Non-Goals

- Guarding against GitHub/`gh` **semantic** change — the lint proves well-formedness, not that a
  probe works. Named in #6786 and the 2026-07-18 learning; `/plan` Phase 0.6 remains the backstop.
- Scanning `.ts`/`.py` surfaces (cron prompt strings, code fixtures). Documented residual;
  re-open if a stateless/truncatable probe is traced to one of those surfaces (mirrors #6793's
  own re-evaluation criteria).
- Fixing / closing `#5095` / `#5097` (rename-guard collision) — context only; net issue flow −1.
- A dedicated reusable-lint-convention ADR. If the file-surface-allowlist + in-detector-exemption
  pattern proves reusable, capture it as a `knowledge-base/project/learnings/` entry at
  `/compound` time (the learnings-researcher confirmed no such convention doc exists yet).
