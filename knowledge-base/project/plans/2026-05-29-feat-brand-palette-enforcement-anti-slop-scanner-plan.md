---
title: "feat: deterministic brand-palette enforcement + two scanner-defect fixes in frontend-anti-slop"
date: 2026-05-29
type: feature
branch: feat-one-shot-brand-hex-scanner-gate
lane: cross-domain
closes: 4635
brand_survival_threshold: aggregate pattern
status: planned
---

# feat: Brand-palette enforcement in the frontend-anti-slop scanner (+ two defect fixes)

## Overview

Add three deterministic **brand-*** Tier-1 rules to the `soleur:frontend-anti-slop`
scanner, fix the two scanner defects that let off-brand colour ship undetected,
and extend scanner scope to server-side email/HTML templates — all within
`plugins/soleur/`, no app code, no `AGENTS.md` edits.

**Motivating incident (verified live in this tree).** The workspace-invite UI and
transactional emails shipped with off-brand blue `#2563eb`. The only brand-adjacent
gate — `frontend-anti-slop` — is advisory-only, excludes `server/` email templates,
and (the proximate cause) **silently matched zero files** because its collector uses
`grep -z`, which on this host (ugrep 7.5.0) means `--decompress`, not GNU
`--null-data`. The raw-hex literals are still present on `main`:

- `apps/web-platform/components/settings/pending-invites-list.tsx:99` — `bg-[#2563eb]/10 text-[#2563eb]`
- `apps/web-platform/components/dashboard/pending-invite-banner.tsx:62,64,76` — `border-[#2563eb]/20 bg-[#2563eb]/5`, `bg-[#2563eb] … text-white`
- `apps/web-platform/server/notifications.ts:212,310,351,388,428` — inline `color: #1a1a1a / #4a4a4a / #9a9a9a` greys

These component files are *already in scanner scope* — they went undetected purely
because of the `grep -z` no-op (work item 1). The `server/notifications.ts` greys
are out of scope until work item 4 extends scope.

**Scope discipline (hard constraints):**

- ALL edits within `plugins/soleur/`. **NO app-code edits** (`apps/web-platform/**` is read-only here).
- **Do NOT modify `AGENTS.md`** (byte-CRITICAL) or its `AGENTS.{core,docs,rest}.md` sidecars.
- **Do NOT edit any skill `description:` frontmatter** — cumulative skill-description budget is at **1950/1950 words, zero headroom** (verified via `components.test.ts` `SKILL_DESCRIPTION_WORD_BUDGET = 1950`). All SKILL.md edits in this plan are to the *body*, which does not count toward budget.

## User-Brand Impact

**If this lands broken, the user experiences:** a Soleur user (or Soleur itself)
ships a UI page or transactional email with off-brand colour — the exact
`#2563eb`-blue invite-page/email incident — because the brand gate either still
no-ops (defect not fixed) or the new rules false-pass. The brand promise ("Solar
Forge" gold identity) is silently violated in a customer-facing surface.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this is a
build-time review gate over source/templates; it touches no runtime data path, no
auth, no PII, no money. The only artifact it reads is the diff of source files.

**Brand-survival threshold:** `aggregate pattern`. A single missed off-brand colour
is a polish regression, not a single-user data/security incident; the cost
accrues as a *pattern* of off-brand surfaces eroding brand trust. (No `single-user
incident` threshold → no `requires_cpo_signoff`, no `user-impact-reviewer` at review.)
This change touches no sensitive path (per preflight Check 6 canonical regex:
schemas/migrations/auth/API/`.sql`) → no `threshold: none` scope-out bullet required.

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description) | Reality (verified) | Plan response |
|---|---|---|
| #4635 is the open ugrep `grep -z` no-op | Confirmed OPEN; exact block at `review/SKILL.md:283-285`; host grep is ugrep 7.5.0 (`-z`=decompress) | Fix per work item 1; `Closes #4635` in PR body |
| `defaultPaths()` glob `~line 245` already matches route-group + dynamic paths; the real miss was `grep -z` | Confirmed. Learning `2026-05-29-ugrep-as-grep-breaks-grep-z-null-delimited-pipelines.md` explicitly records the route-group-regex hypothesis was **wrong**; plain-substring `grep -z` also no-op'd. Regex at `tier1-scan.ts:245` is `/^(apps\/web-platform\/(app\|components)\/.*\.(tsx\|jsx\|css)\|plugins\/soleur\/docs\/.*\.(njk\|css))$/` | Add regression test asserting the glob matches `(public)/[token]` (work item 2); do NOT "fix" the regex |
| incident hex `[#2563eb]` + `background: #2563eb` are plain hits | Verified live in `components/` (in-scope) | Prototyped BRAND-RAW-HEX regex flags all 4 incident strings + the 3 notification greys; passes all token-definition strings (see §"Regex prototypes (verified)") |
| `server/notifications.ts` ships inline-HTML emails | Confirmed exists. **CTA already remediated** (`ctaBackground:"#C9A962"`, `ctaText:"#1A1612"`, `border-radius:0`). Remaining off-brand: `color: #1a1a1a/#4a4a4a/#9a9a9a` body/footer greys at lines 212/310/351/388/428 | Scope-extend (work item 4) WILL flag these greys once blocking. See §"Sharp Edges" — app-side remediation deferred (out of scope), tracking issue filed |
| finding `category: "brand"` | **`finding.schema.json` enum = `[real-estate, ia, consistency, responsive, comprehension, anti-slop]` — does NOT include `brand`**; `additionalProperties:false`; `Finding.category` hardcoded `"anti-slop"` at `tier1-scan.ts:83,364`; enum mirrored in `ux-audit/scripts/dedup-hash.ts` + drift-guarded by `ux-audit/finding-schema.test.ts` | Keep emitted `Finding.category:"anti-slop"` (schema-safe); carry the brand discriminator on the **Rule** (`slop-rules.md` `category` column → `Rule.category` already parsed). Exit-code gate keys on `rule.category==="brand"`, NOT the emitted finding. Zero cross-component blast radius. See §"Design Decision: brand vs. schema enum" |
| current Tier-1 rule count | Exactly 15; asserted in `tier1-scan.test.ts:290` and stated in 4 prose sites | Adding 3 → 18; update the test assertion + all 4 prose sites (work item: count sync) |

## Design Decision: brand discriminator vs. `finding.schema.json` enum

The emitted JSON Finding MUST stay schema-conformant (`category: "anti-slop"`),
because `finding.schema.json` has `additionalProperties:false` and an enum that
excludes `"brand"`, and that enum is shared with `ux-audit` (dedup hash +
drift-guard test). Adding `"brand"` to the enum is a cross-component change with no
upside here.

Instead, the **brand-ness lives on the `Rule`**, not the emitted Finding. The
`slop-rules.md` Active-rules table already has a `category` column parsed into
`Rule.category` (`tier1-scan.ts:71,204`). The new rules set `category = brand` in
the table. The blocking exit-code logic (work item 6) keys on
`rule.category === "brand" && rule.severity === "high"`. The serialized Finding
keeps `category: "anti-slop"` so `--json` output still validates against
`finding.schema.json` and the ux-audit dedup hash is unaffected.

Net: one new branch in `main()` that inspects the matched rule's category; no
`Finding` interface change, no schema edit, no ux-audit touch.

## Regex prototypes (verified against real strings via `bun -e`)

All three regexes were prototyped against the live incident strings, the
`notifications.ts` greys, and the `BRAND_EMAIL_COLORS` token-definition lines.
Results recorded here as preconditions for /work (re-verify with the table
parser's pipe-escaping — see §"Markdown-table pipe-escape constraint").

**BRAND-RAW-HEX** (category `brand`, severity `high`): flagged all 4 incident
hex + 3 notification greys; passed all 4 token-definition/token-class cases
(`ctaBackground: "#C9A962"`, `const GOLD = "#D4B36A"`, `className="bg-soleur-gold"`,
`style={{ background: GOLD_GRADIENT }}`).

```text
\[#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\]|(?:background|color|border)[a-z-]*\s*:\s*#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b
```

Left alternation = Tailwind/class arbitrary value `[#hex]`. Right = inline
`style=…(background|color|border…): #hex`. A bare TS string assignment
(`x = "#C9A962"`) has no `[#…]` brackets and no `prop: #hex` shape → not flagged.
This rule is **project-agnostic** ("use a wired token, not a literal") — it is the
generalisable rule for Soleur users (work item 7).

**BRAND-WHITE-ON-GOLD** (category `brand`, severity `high`): flagged white-on-gold
gradient + `bg-soleur-gold text-white`; correctly did NOT flag the blue-incident
`bg-[#2563eb] … text-white` (caught by BRAND-RAW-HEX instead) nor the correct
forge-ink-on-gold. Keys on co-occurrence of a gold/gradient/accent reference AND
`#fff|#ffffff|white|text-white`.

```text
(?:gold|gradient|accent|#[CcDdBb][0-9A-Fa-f]{5})[^"\n]*(?:color\s*:\s*#(?:fff|ffffff)\b|text-white\b)|(?:color\s*:\s*#(?:fff|ffffff)\b|text-white\b)[^"\n]*(?:gold|gradient|accent)
```

**BRAND-NONZERO-CORNER** (category `brand`, severity `medium`): brand mandates 0px
corners (brand-guide.md:266 "Corners: Sharp (0px border-radius)"). Flags
`border-radius: <1-9…>` and `rounded`-without-`-none`/`-0` in CTA/button context.
Severity medium → advisory (not blocking; only high-severity brand is blocking).

```text
border-radius\s*:\s*[1-9]|\brounded(?:-(?:sm|md|lg|xl|2xl|3xl|full|t|b|l|r))?\b(?![\w-]*-none)
```

> Note on min-occurrence / context: keep BRAND-NONZERO-CORNER a line-regex like
> the others. If /work finds it noisy on the prod tree during the in-tree dry-run
> (Phase 6), narrow the right alternation to require a button/CTA token on the
> same line (`(button|btn|cta)[^"\n]*rounded`), mirroring how `UNIFORM-HOVER-SCALE`
> uses `min_occurrences`. Decision deferred to the dry-run signal, not guessed now.

## Markdown-table pipe-escape constraint (load-bearing)

`parseRules` (`tier1-scan.ts:172`) splits table rows on **unescaped** `|`
(`/(?<!\\)\|/`) then unescapes `\|`→`|`. Any `|` *inside* a rule's `pattern` or
`message` cell MUST be written as `\|` in `slop-rules.md`, or the row mis-splits
and the regex compiles wrong (or the row is dropped). All three new rules contain
alternation `|` and MUST escape every literal pipe as `\|`. See learning
`best-practices/2026-05-21-calibration-fixture-probe-and-markdown-table-pipe-escapes.md`
Pattern 2. AC: after adding rows, `bun test plugins/soleur/test/frontend-anti-slop/tier1-scan.test.ts`
"every parsed rule compiles a valid RegExp" must stay green AND a new test asserts
each brand rule's compiled source round-trips the intended alternation.

## Single-source path regex (work item 4)

The path regex appears in **two** places that must stay in lockstep:

1. `tier1-scan.ts` `defaultPaths()` line 245 (JS `RegExp`).
2. `review/SKILL.md:285` anti-slop hook (shell ERE, currently `grep -zE`).

The description offers two strategies; **chosen: parity test** (Option B), because
the two literals live in different languages (JS RegExp vs shell ERE) and a shared
export cannot be consumed by a markdown code block. Export the canonical pattern
string from `tier1-scan.ts` (e.g. `export const DEFAULT_PATH_RE_SOURCE`) and add a
test in `plugins/soleur/test/frontend-anti-slop/` that reads `review/SKILL.md`,
extracts the `grep -E '<pattern>'` literal from the hook block, and asserts it
equals `DEFAULT_PATH_RE_SOURCE` byte-for-byte (modulo the anchoring the JS form
adds — assert the shared alternation body matches). Both literals extend to add
`apps/web-platform/server/.*\.(ts|tsx)$`.

New combined alternation (both sites):

```text
(apps/web-platform/(app|components)/.*\.(tsx|jsx|css)|apps/web-platform/server/.*\.(ts|tsx)|plugins/soleur/docs/.*\.(njk|css))$
```

## Files to Edit

- `plugins/soleur/skills/review/SKILL.md`
  - L283-291 hook block: replace `mapfile -d '' … grep -zE` with the portable
    `git diff --name-only -z … | tr '\0' '\n' | grep -E '<pattern>'` form
    (`mapfile -t`, no `-d ''`); **never `grep -z`** (host is ugrep). Extend the
    pattern to add the `server/.*\.(ts|tsx)$` alternation.
  - Add the empty-result **guard**: if the raw diff contains files matching the
    scanner extensions but `CHANGED_FILES` is empty, emit a warning to the review
    output instead of silently treating it as clean.
  - "What this hook checks" (L295): 15 → 18; add the brand-rule note.
  - Document that **high-severity `brand` findings are a required-fix gate** (exit
    non-zero), NOT operator triage — distinct from the advisory anti-slop findings.
- `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts`
  - `defaultPaths()` L245: extend regex to add `server/.*\.(ts|tsx)$`. Export
    `DEFAULT_PATH_RE_SOURCE` for the parity test.
  - `main()` exit-code logic (currently always `process.exit(0)` at L423/438):
    after collecting findings, exit `1` iff any finding's *originating rule* has
    `category==="brand" && severity==="high"`; else exit `0` (anti-slop stays
    advisory). Requires threading the rule (or rule category) onto each finding,
    or recomputing from the matched rule set — keep `Finding` interface unchanged
    by tracking the blocking condition in `main()` from `rules`+`findings`
    correlation via `selector` `#<RULE-ID>` suffix.
  - Header docblock (L24-27 "Exit codes"): document the brand-blocking exit.
- `plugins/soleur/skills/frontend-anti-slop/references/slop-rules.md`
  - Add 3 rows to the Active-rules table (tier 1): BRAND-RAW-HEX (brand/high),
    BRAND-WHITE-ON-GOLD (brand/high), BRAND-NONZERO-CORNER (brand/medium). Escape
    every literal `|` in `pattern`/`message` as `\|`.
  - Add a prose paragraph documenting: (a) brand high-severity = blocking; (b)
    BRAND-RAW-HEX is project-agnostic ("token not literal"); for Soleur users,
    BRAND-WHITE-ON-GOLD / BRAND-NONZERO-CORNER reference *their* `brand-guide.md`
    palette + wired token file rather than hardcoding Soleur gold (work item 7).
- `plugins/soleur/skills/frontend-anti-slop/SKILL.md` (body only — NOT `description:`)
  - L9, L47, L54: 15 → 18.
  - Scope table (L46): add `apps/web-platform/server/**/*.{ts,tsx}` row.
  - Add a "Brand rules (blocking)" subsection noting exit-1 on high-severity brand.
- `plugins/soleur/test/frontend-anti-slop/tier1-scan.test.ts`
  - L290: `toHaveLength(15)` → `18`.
  - Add positive+negative fixtures for the 3 brand rules (synthesised inline via
    the existing `withFile` helper — see §"Test Strategy").
  - Add the route-group regression test (work item 2).
  - Add brand-rule pipe-escape / compile round-trip assertions.

## Files to Create

- `plugins/soleur/test/frontend-anti-slop/path-regex-parity.test.ts` — asserts the
  `review/SKILL.md` hook pattern literal equals `DEFAULT_PATH_RE_SOURCE`
  (single-source parity, work item 4). *(May instead be folded into
  `tier1-scan.test.ts` to keep the test surface small — /work picks based on
  import ergonomics; either satisfies the AC.)*
- Optional fixtures under `plugins/soleur/test/fixtures/frontend-anti-slop/` ONLY if
  a brand rule needs an end-to-end (default-path) fixture beyond the in-memory
  `withFile` synthesis. Prefer `withFile` (synthetic, per existing test idiom) —
  do NOT add a new production-pinned fixture (per the calibration-decoupling
  learning). All brand fixtures are synthesised, never copied from app code
  (`cq-test-fixtures-synthesized-only`).

## Implementation Phases

Ordered by dependency direction (contract-before-consumer):

1. **RED — brand rules.** Add the 3 brand-rule rows to `slop-rules.md` (escaped
   pipes). Add positive+negative fixtures + the `toHaveLength(18)` bump + compile
   round-trip tests to `tier1-scan.test.ts`. Run `bun test` → expect the new rule
   tests to drive parse/scan behaviour; the count test goes 15→18 green once rows
   land. (Rules are data; the scanner already iterates `parseRules` output.)
2. **GREEN — blocking exit code.** Implement the `main()` brand-blocking branch.
   Add a test asserting: a high-severity brand finding → exit 1; an anti-slop-only
   finding → exit 0; a medium brand finding (BRAND-NONZERO-CORNER) alone → exit 0.
   (Use the script's process exit via `Bun.spawnSync` on the CLI, or refactor the
   exit decision into a pure exported `computeExitCode(findings, rules)` and unit-test
   it directly — preferred, deterministic, no subprocess.)
3. **Scope extension + parity.** Extend `defaultPaths()` regex + export
   `DEFAULT_PATH_RE_SOURCE`. Update `review/SKILL.md` hook pattern. Add the
   route-group regression test (work item 2) and the parity test (work item 4).
4. **ugrep grep -z fix + guard.** Rewrite the `review/SKILL.md` collector to
   `tr '\0' '\n' | grep -E` (drop `-z`), add the empty-result warn guard. (Pure
   docs/shell edit; verified by the parity test + a shell-form review at QA.)
5. **Doc sync.** 15→18 across the 4 prose sites; brand-blocking documentation in
   `review/SKILL.md` + `frontend-anti-slop/SKILL.md`; project-agnostic note in
   `slop-rules.md`.
6. **In-tree dry-run (calibration sanity).** Run the scanner against the live
   incident files to confirm BRAND-RAW-HEX flags them and the blocking exit fires:
   `bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts --paths apps/web-platform/components/dashboard/pending-invite-banner.tsx apps/web-platform/server/notifications.ts --json; echo "exit=$?"`.
   Expect ≥1 brand/high finding and `exit=1`. This is a *manual verification run*,
   not a committed test (it reads app code). Use the BRAND-NONZERO-CORNER noise
   signal here to decide the context-narrowing deferred above.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `grep -zE` no longer appears in `plugins/soleur/skills/review/SKILL.md`:
      `grep -c 'grep -zE' plugins/soleur/skills/review/SKILL.md` returns `0`; the
      collector uses `tr '\0' '\n' | grep -E` and `mapfile -t` (no `-d ''`).
- [ ] AC2 Empty-result guard present: the hook warns when the diff contains
      extension-matching files but `CHANGED_FILES` is empty (assert the warn string
      exists in the hook block).
- [ ] AC3 Route-group regression test: a unit test asserts the
      `DEFAULT_PATH_RE_SOURCE` (and JS `defaultPaths` regex) matches
      `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx` and
      `…/page.tsx`. Test FAILS if a future regex edit excludes route-group/dynamic
      segments.
- [ ] AC4 BRAND-RAW-HEX: fixture `bg-[#2563eb]` flags (1 finding, severity high,
      rule category brand); fixture inline `background: #2563eb` flags; a
      token-using fixture (`className="bg-soleur-gold"` / `style={{background: GOLD_GRADIENT}}`
      / `const C = "#C9A962"`) yields 0 findings.
- [ ] AC5 BRAND-WHITE-ON-GOLD: white-on-gold fixture flags (high); forge-ink-on-gold
      passes; the blue-incident `bg-[#2563eb] text-white` does NOT flag this rule
      (asserted with `--rule BRAND-WHITE-ON-GOLD` so it's isolated from BRAND-RAW-HEX).
- [ ] AC6 BRAND-NONZERO-CORNER: `border-radius: 8` / `rounded-lg` (CTA) fixture flags
      (medium); `rounded-none` / `border-radius: 0` passes.
- [ ] AC7 Blocking exit: `computeExitCode` (or CLI) returns 1 when ≥1 finding is
      brand+high; returns 0 for anti-slop-only and for brand-medium-only.
- [ ] AC8 Scope extension: `DEFAULT_PATH_RE_SOURCE` matches
      `apps/web-platform/server/notifications.ts`; `defaultPaths()` includes server
      `.ts/.tsx`.
- [ ] AC9 Parity: a test asserts the `review/SKILL.md` hook pattern literal equals
      `DEFAULT_PATH_RE_SOURCE` (the shared alternation body) byte-for-byte.
- [ ] AC10 Count sync: `tier1-scan.test.ts` asserts `toHaveLength(18)`; `grep -rn
      '15 ' ` across the 4 named prose sites returns no stale "15 …Tier 1/gates"
      (each now reads 18).
- [ ] AC11 Pipe-escape integrity: `bun test plugins/soleur/test/frontend-anti-slop/tier1-scan.test.ts`
      "every parsed rule compiles a valid RegExp" green AND each brand rule's
      compiled `.source` round-trips the intended alternation (no `\|` mis-split).
- [ ] AC12 Full suite green: `cd plugins/soleur && bun test` (or the repo's bun-test
      invocation for `plugins/soleur/test/`) passes — including the unchanged
      `components.test.ts` budget test (proves no `description:` edit crept in).
- [ ] AC13 Plugin compliance: README component counts + `plugin.json` unchanged
      (no new skill/agent/command added — only rules/tests/docs within an existing
      skill). Confirm `bun test plugins/soleur/test/components.test.ts` green.
- [ ] AC14 PR body uses `Closes #4635`.

### Post-merge (operator) — automation-feasibility checked

- [ ] AC15 App-side remediation tracking issue exists for `notifications.ts` greys
      + the `pending-invite*` `#2563eb` hex (app code, out of scope here). File via
      `gh issue create` (automatable — bake into ship, not a manual step). The brand
      gate now blocks the *next* app PR that touches those files; the tracking issue
      drives proactive remediation. Label with an existing label (verify via
      `gh label list` at ship time).

## Test Strategy

- Runner: `bun test`, idiom per existing `plugins/soleur/test/frontend-anti-slop/tier1-scan.test.ts`
  (in-memory `withFile` + `scanFile(abs, [ruleById(id)])`). Brand fixtures are
  synthesised inline — never copied from app code.
- Exit-code logic: prefer a pure exported `computeExitCode(findings, rules)` unit-tested
  directly (deterministic, no subprocess) over `Bun.spawnSync` on the CLI.
- The route-group + parity tests are pure-string assertions over the exported
  `DEFAULT_PATH_RE_SOURCE` and the `review/SKILL.md` literal — no filesystem fixtures.
- Verify the bun-test discovery: `plugins/soleur/test/` has no `bunfig.toml`
  `pathIgnorePatterns` (verified — only `apps/web-platform` has the ignore-all
  pattern). Co-located `plugins/soleur/test/frontend-anti-slop/*.test.ts` files are
  already discovered (the existing tier1-scan test runs there).

## Domain Review

**Domains relevant:** Product (advisory), Marketing (advisory — brand-guide is the rule source)

This plan implements review-tooling/orchestration changes (a deterministic scanner
gate), not a new user-facing page or flow. Per the plan-skill NONE-tier rule, a plan
that *discusses* brand/UI concepts but *implements* a scanner is NONE for the
mechanical BLOCKING escalation (no new `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx` created). Marketing/Product implications are advisory: the rules
encode `brand-guide.md` palette facts (gold `#C9A962`, no-white-on-gold per
brand-guide.md:213/245, 0px corners per :266). No domain-leader sign-off gates this
infra/tooling change. (Subagent spawning unavailable in this environment; assessment
performed inline against `brand-guide.md` which was read and cited directly.)

## Observability

Not applicable as a runtime surface — this is a build-time/review-time CLI gate with
no server/infra deployment. Files-to-Edit are under `plugins/soleur/skills/**` and
`plugins/soleur/test/**`, not `apps/*/server|src|infra` or `plugins/*/scripts` runtime
paths; no new infrastructure (Phase 2.8 skip). The gate's own "did it run?" signal is
the review-hook output line (and the new empty-result warn guard, AC2), which surfaces
in `/soleur:review` output — that IS the discoverability test:

```yaml
discoverability_test:
  command: "bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts --paths <file> --json; echo exit=$?"  # NO ssh
  expected_output: "JSON findings array; exit=1 when a brand+high finding is present"
```

## Infrastructure (IaC)

None. Pure code/docs change against existing skill components; no server, secret,
vendor, cron, or persistent process introduced (Phase 2.8 skip).

## GDPR / Compliance

Skip — no regulated-data surface (no schema/migration/auth/API/`.sql`), no
LLM-on-session-data, no new distribution surface, threshold is `aggregate pattern`
(not `single-user incident`). None of the (a)-(d) expanders fire.

## Open Code-Review Overlap

None checked at draft time — to be confirmed at /work by querying open `code-review`
issues against the Files-to-Edit list (`tier1-scan.ts`, `slop-rules.md`,
`review/SKILL.md`, `frontend-anti-slop/SKILL.md`). If any open scope-out names these
files, fold-in/acknowledge/defer per Phase 1.7.5.

## Sharp Edges

- **`## User-Brand Impact` completeness:** this section is filled (threshold
  `aggregate pattern`); a plan whose section is empty/`TBD`/threshold-less fails
  `deepen-plan` Phase 4.6 and preflight Check 6.
- **Scope-extension vs. blocking tension (load-bearing).** Once work item 4 scopes
  `server/.*\.(ts|tsx)$` in AND BRAND-RAW-HEX is blocking, the scanner will exit 1 on
  any PR touching `notifications.ts` (its `color: #1a1a1a/#4a4a4a/#9a9a9a` greys are
  raw-hex inline-style hits). Remediating those greys is **app code → out of scope
  here**. Resolution: ship the rule + scope extension (so the gate is armed), and
  file an app-side remediation tracking issue (AC15). The brand gate is correctly a
  *forward gate* on the next app PR; this is the intended behaviour, not a defect.
  Per `guard-surface-audit-before-coding`: the protected surface already contains
  matches → the AC must cover retroactive remediation (the tracking issue), not
  "future-only enforcement".
- **finding.schema.json enum excludes `brand`.** Do NOT add `"brand"` to the emitted
  Finding category — keep `category:"anti-slop"` and carry the brand discriminator on
  the Rule (see §"Design Decision"). Editing the shared enum would touch ux-audit's
  `dedup-hash.ts` + `finding-schema.test.ts` for zero benefit.
- **Markdown-table pipe-escape:** every `|` inside a brand rule's `pattern`/`message`
  cell MUST be `\|`, or `parseRules` mis-splits the row. Verified by the compile
  round-trip AC11.
- **Skill-description budget at 1950/1950 (zero headroom).** Touch NO `description:`
  frontmatter. All SKILL.md edits are body-only. The unchanged `components.test.ts`
  budget test (AC12) is the canary.
- **Never `grep -z` in new shell** (host is ugrep). The fix itself must use
  `tr '\0' '\n' | grep -E` (or long-form `--null-data`), never short `-z`.
- **BRAND-NONZERO-CORNER noise risk:** `rounded` is ubiquitous in Tailwind. Keep it
  medium (advisory, non-blocking). Narrow to CTA/button context only if the Phase 6
  dry-run shows high false-positive volume — decision driven by the dry-run signal,
  not guessed at plan time.
