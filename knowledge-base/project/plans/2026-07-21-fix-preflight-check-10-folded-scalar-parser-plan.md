---
title: "fix: preflight Check 10 Form A parser mis-reads folded YAML scalars (`command: >-`)"
date: 2026-07-21
type: fix
issue: 6772
branch: feat-one-shot-6772-preflight-folded-scalar-parser
lane: cross-domain
brand_survival_threshold: none
---

# fix: preflight Check 10 Form A parser mis-reads folded YAML scalars

🐛 Closes #6772

## Overview

Preflight Check 10 Step 10.4 parses `discoverability_test.command` with a 4-rule awk
that handles exactly two YAML scalar shapes: inline (`command: <value>`) and block
(`command: |`). There is no folded-scalar branch. On `command: >-` the **inline rule
matches**, strips the key, and yields the literal `>-` — which then trips Check 10's
*own* shell-active-token reject (the `>` branch in Step 10.5):

```
FAIL: discoverability_test.command contains shell-active token; refusing to run.
```

The check fails closed (safe direction), but the diagnostic points at a nonexistent
shell-injection rather than at the parse. The natural operator response is to reword
the command until the reject stops firing — never noticing the parser never read it.
**A check that cannot parse its input is indistinguishable from a check that ran and
found nothing.**

This plan fixes the parser on **both** surfaces (production awk + TypeScript mirror),
adds the missing behavioural parity guard between them, and fixes a **second,
independent, pre-existing defect** this investigation surfaced in the block-scalar
branch (below).

### Blast radius is larger than the issue reports

Census over non-archive plans (`knowledge-base/project/plans/`, 2026-07-21). Counts are
**regex-derived, not literals** — re-derive at implementation time rather than trusting
these numbers (two independent reviewers counted 4/17/19 against my 5/18/20; the exact
count is not load-bearing, the *shape distribution* is):

| Header form | Approx. plans | Current parse result |
| --- | --- | --- |
| `command: >` (clip) | ~13 | literal `>` → shell-active reject |
| `command: >-` (strip) | ~4–5 | literal `>-` → shell-active reject |
| `command: >+` (keep) | 0 | — |
| `command: \|` (block) | ~19–20 | **swallows the sibling `expected_output:` key** (defect 2) |
| `command: \|-` / `\|+` | 0 | bash → block mode; TS → literal `\|-` (**existing drift**) |
| `discoverability_test: { command: "…" }` (flow mapping) | ~7–13 | **out of scope** — see §Variant Scope |

~17 plans in the corpus already use the folded form. `>` (clip) is roughly **3× more
common than `>-`** — a fix scoped only to `>-` would leave the majority of the corpus
broken.

## Research Reconciliation — Issue Claims vs. Codebase

| Issue claim | Reality (verified) | Plan response |
| --- | --- | --- |
| Inline rule shadows fold; ordering is load-bearing | **CONFIRMED.** awk evaluates rules top-down; rule 2 (`/^[[:space:]]*command:/`) matches `command: >-`, prints `>-`, `exit`s. Empirical: `awk "$RULES" fold.txt` → `>-` | Fold rule placed **first**, ahead of both block and inline rules. F1–F3 pin ordering behaviourally. |
| Suggested guard `^[[:space:]]*[a-z_]+:` stops the fold at the next key | **CONFIRMED for `expected_output:`, but the guard is over-broad in TWO ways.** (a) a continuation line starting `https://app.soleur.ai/...` matches it (`https` ∈ `[a-z_]+`) and silently truncates. (b) **even with the colon-must-be-followed-by-space fix, a deeper-indented `key: value` inside the command truncates it** — verified against a real corpus plan (below). | Terminator is **indent-aware**: a sibling key can never be more indented than its own `command:` key. See §Phase 2. N2 and N5 pin both failure modes. |
| Only `>-` needs handling | **REFUTED by census.** `>` is ~3× more common than `>-`. | Handle `>`, `>-`, `>+` via `>[-+]?`. |
| Trailing-space join concern | Real but avoidable. Appending `"%s "` leaves a trailing space; harmless to the shell-active reject (space is not a rejected token) and irrelevant to `expected_output` matching (which compares *stdout*, not the command) — but it defeats byte-exact parity. | **Prepended** separator (`(n++ ? " " : "")`) → no trailing space, deterministic on both surfaces. F4 pins it. |
| The TS mirror needs a parity assertion "if one does not already exist" | **None exists.** `preflight-discoverability-test.test.ts` asserts only *prose invariants* on SKILL.md. Nothing executes the awk. | Real behavioural parity harness (§Phase 3), made tractable by extracting the awk to a real file. |
| Revert the single-line workaround if still present | **Not locatable.** `git log -S'command: >-' --since=21.days` and a diff scan for removed `-  command: >` lines return nothing. | Recorded as "nothing to revert". §Workaround Revert. |

### The terminator trap that nearly shipped

The first draft of this plan used `^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:([[:space:]]|$)`
and claimed it was empirically verified. That verification covered only `https://` and
capitalisation. Review found a **real corpus plan** it breaks —
`knowledge-base/project/plans/2026-07-03-fix-seccomp-loaded-sha-deploy-status-discriminators-plan.md`,
whose folded command ends in a jq object filter:

```
    https://deploy.soleur.ai/hooks/deploy-status | jq
    '{matches: .seccomp_profile_loaded_matches_host,
      host_present: .seccomp_profile_host_present, host_sha: .seccomp_profile_host_sha256}'
```

`host_present:` is followed by a space → the terminator fires and cuts the command
mid-jq-expression. This is exactly the outcome §User-Brand Impact names as *worse* than
the reported bug: silent truncation, then a verdict on a partial command. (It is P1 not
P0 only because this particular command also contains `|` and `$(`, so the shell-active
reject masks it. That masking is incidental, not a mitigation.)

**The fix is indent-awareness**: a sibling key is never more indented than the
`command:` key that opened the scalar. Verified: all fixtures still pass, corpus
`expected_output` leaks stay at 0, and it differs from the naive terminator on exactly
that one falsely-truncated plan.

### Defect 2 (pre-existing, discovered here): block scalar over-consumes

The block branch has **no key terminator at all** — it relies on indentation:

```awk
mode=="block" && /^[[:space:]]+[^[:space:]]/ { print; next }   # matches ANY indented line
mode=="block" && /^[[:space:]]*[^[:space:]]/ { exit }          # only reached at column 0
```

`  expected_output: "200"` is indented, so rule 3 matches it first. Empirically:

```
$ awk "$CURRENT_RULES" block.txt
    curl -fsS --max-time 10 https://app.soleur.ai/api/inngest
  expected_output: "200"
```

**Corrected severity** (the first draft overstated this): `bash -c` runs the swallowed
line as a second command, `expected_output:` is not found, rc=127 goes to **stderr**,
and stdout is unchanged — so `matchExpected` usually reaches the same verdict. It is a
real bug (the command handed to the shell is not the command the plan declared, and
`$?` reflects the bogus second command, corrupting the rc-based states 4/5/7 of the
decision matrix) but it is **not** stdout pollution. Roughly 8 of the ~19 block plans
have `expected_output` on the immediately-following line.

The same shared terminator that fixes the fold fixes this at zero incremental cost —
it is literally the same rule line. Both branches get it.

## User-Brand Impact

**If this lands broken, the user experiences:** preflight FAILs a well-formed plan with
a shell-injection diagnostic that names a defect the plan does not have, or (worse, if
the terminator is over-broad) silently truncates the probe command so Check 10 executes
a partial command and reports a verdict on an unverified surface.

**If this leaks, the user's data/workflow/money is exposed via:** no new exposure
surface. The parser reads a repo-local plan file already trusted-on-PR-review; the
`env -i` scrub + shell-active reject + 15s timeout in Step 10.5 are unchanged.

**Brand-survival threshold:** none — internal preflight tooling, no user-facing surface,
no regulated data. `threshold: none, reason: the change is confined to a repo-local
plan-file parser in the preflight skill and its test mirror; no runtime user surface,
no persisted data, no credential path is touched.`

## Variant Scope

| Variant | In scope | Why |
| --- | --- | --- |
| `>-` (strip), `>` (clip), `>+` (keep) | ✅ | `>` and `>-` cover ~17 corpus plans. `>+` has zero usage but is one character (`>[-+]?`); excluding it leaves a third silent variant. Covered by one table-driven fixture, not three. |
| `\|-` / `\|+` | ✅ (alignment only) | Zero corpus usage, but **bash and TS already disagree**: bash's `\|` prefix match enters block mode; TS's anchored regex falls through to inline and returns the literal `\|-`. Aligning both to `\|[-+]?` closes a real drift for ten characters. B3 is its only pin. |
| Explicit indent indicators (`>2`, `\|4`) | ❌ | Zero usage. Falls through to the inline rule → literal `>2` → shell-active reject. Fails closed, same as today. |
| Chomping semantics (`-`/`+` trailing-newline behaviour) | ❌ | The value goes to `bash -c` and `$(…)` strips trailing newlines regardless. All three indicators treated identically; documented in the `.awk` header comment. |
| **Flow-mapping shape** `discoverability_test: { command: "…", expected_output: "…" }` | ❌ (tracked) | ~7–13 plans. The line-anchored `^[[:space:]]*command:` never matches, so Form A yields empty and Form B also fails → Check 10 FAILs state 3 today. It fails **honestly** (the diagnostic correctly says "no command could be parsed"), unlike #6772. Out of scope; **file a tracking issue** so it does not stay invisible behind this plan's census. |
| **Inline quote stripping** (`command: "curl …"`) | ❌ (tracked) | TS `parseCommand` calls `stripQuotes`; the awk does not. On quoted inline commands bash hands `"curl …"` to `bash -c` as a single word. Pre-existing on both surfaces, orthogonal to folded scalars. **File a tracking issue**; the parity harness records it as a documented divergence rather than silently omitting it (see §Phase 3). |

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md` — Check 10 Step 10.4: call the extracted awk file; update the Form A prose to name all three scalar shapes.
- `plugins/soleur/test/lib/discoverability-test-parser.ts` — `parseCommand()` TS mirror.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — fixtures + parity harness.

## Files to Create

- `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` — the Form A parser, extracted
  from the SKILL.md fence into a real file (see §Phase 2, rationale).

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200`, body-matched against each
path above via standalone `jq --arg`: **None.**

## Architecture Decision (ADR/C4)

Not applicable. A bug fix to an existing parser on an existing surface — no
ownership/tenancy boundary move, no new substrate, no resolver/trust-boundary change, no
divergence from an existing ADR. Extracting the awk to a sibling `scripts/` file is a
file-layout change already sanctioned by `plugins/soleur/AGENTS.md`, not an architectural
decision.

**C4 completeness check:** all three of `model.c4`, `views.c4`, `spec.c4` reviewed against
this change's actors and systems. It introduces no external human actor (the parser reads
a repo-local file authored by the existing operator role), no external system or vendor
(no network, no third-party API — pure text), no container or data store (the parse runs
in-process inside the preflight shell), and no actor↔surface access relationship (the
operator↔preflight relationship is unchanged in direction and permission). No C4 edit
required.

## Infrastructure (IaC)

Not applicable. No server, service, secret, DNS record, cron, vendor account, or
persistent runtime process. Pure text-parser change in a skill + its tests.

## Domain Review

**Domains relevant:** none

No cross-domain implications — internal tooling change to a preflight parser. No
UI-surface path appears in `## Files to Edit` or `## Files to Create` (the mechanical
UI-surface override does not fire), so the Product/UX Gate is skipped.

## Implementation Phases

Phase ordering is load-bearing: the **contract** (the awk, the runtime of record) changes
before the **mirror** (TS), before the **guard** (parity harness) that binds them.
Reversing this would make the parity harness green against a half-applied fix.

### Phase 1 — RED: fixtures first

Add the fixtures from §Test Matrix and confirm the fold/terminator cases are **red**
against the unmodified parser. Capture the actual failure strings; they are the primary
non-vacuity evidence (see §Mutation Verification).

Note: N1, N5 and B1 assert the *absence* of over-consumed content. Confirm they fail for
the right reason (over-consumption), not because the fixture is malformed.

### Phase 2 — Extract the awk to a real file, then fix it

**Why extract.** Today the production awk lives inside a markdown fence: nothing lints
it, nothing executes it, and any test that wants to run it must regex-scrape it back out
of the prose — then needs a second guard against the scrape silently returning empty. A
guard against your own harness's fragility is the tell that the harness is wrong.
`plugins/soleur/AGENTS.md` already sanctions `skills/<name>/scripts/`. Extracting kills
the scrape, the scrape-guard, and the "awk is unlintable" sharp edge in one move, and
makes rule order reviewable in a real file instead of asserted by byte offset.

Create `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`:

```awk
# Form A parser for preflight Check 10 Step 10.4 — the production runtime of record.
# Mirrored (non-authoritatively) by plugins/soleur/test/lib/discoverability-test-parser.ts.
# If the two drift, THIS FILE WINS and the mirror is the bug.
#
# Handles three YAML scalar shapes for `command:`:
#   inline   `command: curl …`
#   block    `command: |`  `|-`  `|+`   → continuation lines joined with NEWLINE
#   folded   `command: >`  `>-`  `>+`   → continuation lines joined with SPACE
# Chomping indicators (-/+) are accepted but not modelled: the value is passed to
# `bash -c` and $(…) strips trailing newlines regardless.

function indent(s,   t) { t = s; sub(/[^[:space:]].*$/, "", t); return length(t) }

# Folded scalar. MUST precede the inline rule: `/^[[:space:]]*command:/` also matches
# `command: >-` and would print the literal indicator, which then self-rejects against
# Step 10.5's shell-active `>` branch (#6772). Header anchored to EOL — a folded or
# block header carries no value.
/^[[:space:]]*command:[[:space:]]*>[-+]?[[:space:]]*$/ { mode = "fold";  key = indent($0); next }
/^[[:space:]]*command:[[:space:]]*\|[-+]?[[:space:]]*$/ { mode = "block"; key = indent($0); next }

# Inline.
/^[[:space:]]*command:/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; exit }

# Sibling-key terminator, shared by BOTH multi-line modes. Two guards, both load-bearing:
#   - colon must be followed by whitespace or EOL, else a continuation line beginning
#     `https://…` is read as the key `https:` and the command truncates.
#   - the key must be no MORE indented than the `command:` key that opened the scalar,
#     else a deeper-indented `key: value` inside the command (e.g. a jq object filter
#     `'{matches: .x, host_present: .y}'`) truncates it mid-expression.
mode && indent($0) <= key && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:([[:space:]]|$)/ { exit }

# Continuation lines. Folded joins with a PREPENDED separator so there is no trailing
# space. Block prints the line verbatim, indentation included — matching the current
# production behaviour exactly (see §Phase 3 on how the parity harness handles this).
mode == "fold"  && /^[[:space:]]+[^[:space:]]/ { sub(/^[[:space:]]+/, ""); printf "%s%s", (n++ ? " " : ""), $0; next }
mode == "block" && /^[[:space:]]+[^[:space:]]/ { print; next }

# Dedent to column 0 ends either mode. Reached by the closing ``` of the YAML fence and
# by column-0 prose following the block.
mode && /^[[:space:]]*[^[:space:]]/ { exit }

END { if (mode == "fold" && n) printf "\n" }
```

In `SKILL.md` Step 10.4, replace the inline awk program with:

```bash
CMD=$(awk -f "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/preflight/scripts/parse-form-a.awk" \
  "$PREFLIGHT_TMP/preflight-observability.txt")
```

and update the Form A prose ("Detection: … OR the next non-blank line if the value is a
YAML `|` block-scalar") to name inline, block **and folded** shapes.

**Two deliberate changes beyond the reported fold gap, each justified:**

1. **Block header widened** `\|` → `\|[-+]?[[:space:]]*$`. Behaviour-preserving for every
   corpus form (`|`, `|-`, `|+` all still enter block mode) and it aligns bash with the
   TS mirror's already-anchored regex, closing a real drift. B3 is its pin.
2. **Key terminator applied to `mode=="block"`** — fixes defect 2. Same shared rule line
   as the fold fix; splitting it into its own PR would mean a second PR editing the
   identical awk block with a guaranteed conflict, for zero incremental lines here.

**Explicitly NOT changed** (rejected from the first draft): stripping indentation in
block mode. That would modify the *authoritative* runtime to match the
acknowledged-buggy mirror, in service of a harness introduced in the same PR — the tail
wagging the dog, and against the mirror's own stated "bash wins" contract. The harness
normalizes instead (§Phase 3).

### Phase 3 — Mirror in TypeScript + parity harness

`parseCommand()` in `discoverability-test-parser.ts`: add the fold branch ahead of the
inline match, widen the block header to `/^\s*command:\s*\|[-+]?\s*$/`, and apply the
same indent-aware terminator to both multi-line modes. Fold joins with `" "` — no
trailing separator. Align the blank-line-inside-block behaviour to the awk (the awk
matches no rule on a blank line and drops it; TS currently pushes `""`) — **bash wins**
per the file header, and blank-line-in-block has zero corpus usage.

**Parity harness** — the guard that does not exist today:

- For every Form-A fixture, run `awk -f plugins/soleur/skills/preflight/scripts/parse-form-a.awk`
  via `Bun.spawn` and compare stdout (trailing newline trimmed) to `parseCommand(block)`.
- **Restrict the harness to Form-A-only inputs and assert that restriction.**
  `parseCommand()` runs Form A *and then falls back to Form B* (the prose/fenced-block
  path), which in bash is a separate awk program further down SKILL.md guarded by
  `if [[ -z "$CMD" ]]`. A fixture where Form A yields empty and a fenced block exists
  would diverge spuriously. Every harness fixture must contain a `command:` key and no
  competing fenced block; assert this in the harness itself.
- **Normalize block-mode leading indentation** before comparison (the awk preserves it,
  TS strips it). One line in the harness, zero production risk.
- **Record known divergences explicitly** rather than omitting them, so AC8 is not a
  tautology: inline quote stripping (TS strips, awk does not — §Variant Scope, tracked).
  Assert the divergence *as a known-difference expectation*, so if either side changes,
  the harness reddens and forces a decision.

Where the two differ, **the bash is authoritative** and the TS is the bug — state this
in the assertion message, matching the file's header comment.

### Phase 4 — GREEN + verification

Run `bash scripts/test-all.sh`. Then execute §Mutation Verification and §AC11's corpus
re-parse.

## Test Matrix

Every case names the concrete mutation that reddens it. A case with no such mutation
pins nothing and does not belong in the suite.

### Permissive direction — the fold parses

| # | Fixture | Assertion | Reddening mutation |
| --- | --- | --- | --- |
| F1–F3 | **Table-driven** over `[">", ">-", ">+"]`, each + 2 continuation lines | parsed == the space-joined single line; **and explicitly `!== the indicator`** | Delete the fold rule → returns the literal indicator. Narrowing `>[-+]?` → `>-` reddens the `>` and `>+` rows specifically. |
| F4 | `command: >-`, single continuation line | parsed == that line, **no leading or trailing space** | Change the join to append (`"%s "`) → trailing space |

### Restrictive direction — the fold does NOT over-consume

This half is what a parser-widening suite structurally forgets. Each case proves the
fold *stops*. Two of these were found by review, not by the original draft.

| # | Fixture | Assertion | Reddening mutation |
| --- | --- | --- | --- |
| N1 | fold + sibling `  expected_output: "200"` | command does **not** contain `expected_output`; `parseExpected` still returns `200` | Delete the terminator rule → the key is swallowed |
| N2 | fold whose continuation line **starts with** `https://app.soleur.ai/api/inngest` | command **contains** the full URL | Replace the terminator with `^[[:space:]]*[a-z_]+:` → `https:` matches, command truncates |
| N5 | fold whose continuation lines contain a **deeper-indented** jq object filter (`'{matches: .x,` / `  host_present: .y}'`) — modelled on the real corpus plan cited in §Research Reconciliation | command contains `host_present` (not truncated) | Drop the `indent($0) <= key` guard → truncates mid-jq-expression |
| N3 | fold followed by the **closing ` ``` ` of the YAML fence**, and a second fixture with column-0 prose | command stops at the fence/dedent | Delete the column-0 exit rule → runs past the block boundary. *(Corrected from the first draft, which used a `## ` heading — unreachable, since Step 10.3's extraction already strips at `^## `.)* |

### Non-shadowing — existing forms stay green

| # | Fixture | Assertion | Reddening mutation |
| --- | --- | --- | --- |
| I1 | inline `command: curl -fsS https://x/health` | unchanged | Delete the inline rule → returns empty |
| B1 | `command: \|` + sibling `expected_output:` | command does **not** contain `expected_output` (**defect 2 regression pin**) | Remove the terminator from `mode=="block"` → swallows it |
| B2 | `command: \|` + 2 continuation lines | joined with `\n`, **not** with a space | Swap the fold and block join operators → block collapses to one line |
| B3 | `command: \|-` | enters block mode on **both** surfaces | Revert the TS block regex to `/^\s*command:\s*\|\s*$/` → TS returns the literal `\|-`; parity harness reddens |
| E1 | `command: >-` with **no** continuation lines | returns empty (falls through to Form B / FAIL state 3); does **not** return `">-"` | Make the fold branch emit the header → returns `>-` |

**Ordering note (honest scope of each pin):** the mutation "move the inline rule ahead of
the fold rule" reddens F1–F4 but **not** I1. I1 pins only that the inline path survives;
F1–F4 are the cases that pin rule ordering. Stated so a future reader does not mistake I1
for ordering coverage.

### Parity

| # | Assertion | Reddening mutation |
| --- | --- | --- |
| P1 | For every Form-A fixture, `parse-form-a.awk` output == `parseCommand()` output (block indentation normalized; known divergences asserted as known) | Apply the fold fix to only one of the two surfaces |
| P3 | Every harness fixture contains a `command:` key and no competing fenced block | Add a Form-B-only fixture → the constraint assertion reddens, instead of a spurious parity failure |

## Mutation Verification

**Phase 1's RED-first run is the primary non-vacuity evidence** and covers every case
that is failing before the fix (F1–F4, N1, N2, N5, B1, and P1). Recording its output is
mandatory; re-deriving the same signal with a sandbox protocol for those cases is
redundant work.

The sandbox protocol below applies to the cases RED-first **cannot** cover — those
already green before the fix, where only a deliberate mutation can prove they pin
anything: **I1, N3, B2, B3, E1, P3.**

1. `cp` the `.awk` and `discoverability-test-parser.ts` into a scratch sandbox, plus a
   second pristine backup of each.
2. Apply exactly one mutation from the matrix to the sandbox copy.
3. **Prove the mutation landed**: `diff <pristine> <mutated>` must be non-empty and its
   hunk must contain the intended change. A mutation that silently no-ops produces a
   green suite that looks like a passing verification — this diff is the guard.
4. Point the suite at the sandbox copies; confirm the **named** case reddens (assert on
   the specific test name, not merely a non-zero exit — an unrelated failure is not
   evidence).
5. Restore from the pristine backup; confirm green.

Record the resulting table (case → mutation → observed failing test name) in the PR body,
alongside the Phase 1 RED output.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` exists and its
      fold rule precedes its inline rule. Verify with **first-match** capture (a later
      comment mentioning the pattern must not flip the result):
      `awk '/command:\[\[:space:\]\]\*>/ && !f { f=NR } /^\/\^\[\[:space:\]\]\*command:\/ / && !i { i=NR } END { exit !(f && i && f < i) }' <file>`
- [ ] **AC2** — Fold header accepts `>`, `>-`, `>+` on **both** surfaces. Verify with
      consistent literal matching (`grep -F`, not mixed BRE/ERE escaping):
      `grep -cF '>[-+]?' plugins/soleur/skills/preflight/scripts/parse-form-a.awk` ≥ 1 and
      `grep -cF '>[-+]?' plugins/soleur/test/lib/discoverability-test-parser.ts` ≥ 1.
- [ ] **AC3** — F1–F4 green: `>` / `>-` / `>+` fixtures parse to the space-joined
      single-line form, not to the literal indicator, with no trailing space.
- [ ] **AC4** — N1 green: the fold stops at the next sibling key; the parsed command does
      not contain `expected_output`, and `parseExpected()` on the same block still
      returns `200`.
- [ ] **AC5** — N2 **and N5** green: a continuation line beginning `https://` is not
      treated as a key, **and** a deeper-indented `key: value` inside the command does not
      truncate it. (N5 pins the indent-awareness that review caught.)
- [ ] **AC6** — B1 green: `command: |` no longer swallows the sibling `expected_output:`
      key (defect 2 fixed).
- [ ] **AC7** — I1, B2, B3, N3, E1 green: inline and block behaviour otherwise unchanged;
      block joins with `\n`, fold with `" "`; both stop at the fence close.
- [ ] **AC8** — Parity harness passes: for every Form-A fixture, `parse-form-a.awk` and
      `parseCommand()` agree (block indentation normalized). Known divergences are
      asserted **as known** (P3), not omitted — a silent omission would make this AC a
      tautology.
- [ ] **AC9** — PR body records the Phase 1 RED output **and** the sandbox mutation table
      for the six already-green pins (I1, N3, B2, B3, E1, P3).
- [ ] **AC10** — Full suite green: `bash scripts/test-all.sh` (repo `package.json`
      `scripts.test`). Do **not** substitute a bare `bun test` — see §Sharp Edges.
- [ ] **AC11** — **Corpus re-parse (the strongest regression net in this plan).** Run the
      fixed `parse-form-a.awk` over the `## Observability` block of **every** non-archive
      plan matching `^[[:space:]]*command:[[:space:]]*[>|]` in
      `knowledge-base/project/plans/`. For each: parsed command is non-empty, does not
      equal a bare scalar indicator, and does not contain `expected_output`. Report the
      count parsed and the count changed vs. the pre-fix parser. Do not hardcode the
      plan counts — derive them from the regex at run time.
- [ ] **AC12** — Two tracking issues filed for the deliberately out-of-scope shapes:
      flow-mapping `discoverability_test: { command: … }`, and inline quote stripping.
      Both are recorded in §Variant Scope; without issues they stay invisible behind this
      plan's census.

### Post-merge (operator)

None. Every step above is automatable in-session via Bash + the repo test runner.

## Workaround Revert

The issue notes a workaround applied at discovery time — rewriting the command onto a
single long line — and asks whether it is still present.

**Searched and not found.** `git log --since=21.days -S'command: >-' -- knowledge-base/project/plans/`
returns four commits, none of which collapses a folded scalar; a diff scan for removed
`-  command: >` lines over the same window returns nothing. No plan in the current corpus
carries a single-line command attributable to this defect. **There is nothing to revert.**
Recorded explicitly so a future reader does not re-run the search.

Separately: the ~17 folded-form plans need **no** edit. They are correct YAML today; the
parser was wrong. AC11 verifies they parse correctly after the fix rather than changing
them.

## Observability

```yaml
liveness_signal:
  what: >-
    preflight Check 10 parses discoverability_test.command from all three YAML
    scalar shapes (inline, block, folded) and reaches an execution verdict rather
    than self-rejecting at the shell-active-token gate
  cadence: every /soleur:preflight run on a sensitive-path diff
  alert_target: the preflight run itself (fail-closed; FAIL aborts the pipeline)
  configured_in: plugins/soleur/skills/preflight/scripts/parse-form-a.awk (called from SKILL.md Step 10.4)
error_reporting:
  destination: preflight stdout diagnostic + non-zero exit (headless aborts the pipeline)
  fail_loud: true
failure_modes:
  - mode: fold rule shadowed by the inline rule (regression of #6772)
    detection: fixtures F1-F4 in preflight-discoverability-test.test.ts
    alert_route: CI test failure on the PR
  - mode: terminator over-consumes or under-consumes (swallows a sibling key, or
      truncates on an https:// or deeper-indented key inside the command)
    detection: fixtures N1, N2, N5, N3, B1
    alert_route: CI test failure on the PR
  - mode: awk and TS mirror drift apart
    detection: parity harness P1/P3 (executes the production .awk file directly)
    alert_route: CI test failure on the PR
logs:
  where: preflight run output (stdout); no persisted log — the check is synchronous
  retention: CI run retention (90 days)
discoverability_test:
  command: bun test plugins/soleur/test/preflight-discoverability-test.test.ts
  expected_output: "0 fail"
```

**Note on this block's own form:** `command:` above is deliberately **inline**, not
folded. `plugins/soleur/skills/**` and `plugins/soleur/test/**` are absent from
`SENSITIVE_PATH_RE` (verified at `SKILL.md:477`), so Check 10 SKIPs on this PR and a
folded form would not self-block — but an inline command removes the dependency entirely
and avoids a plan that can only be validated by the fix it proposes. The `what:` field
above uses `>-` freely; only `command:` is affected by the defect.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| The terminator truncates legitimate command content containing a colon | Two guards: colon must be followed by whitespace/EOL (N2), **and** the key must be no more indented than `command:` (N5, modelled on the real corpus plan that broke the naive version). Both verified against the corpus, not just synthetic fixtures. |
| Adding the terminator to `mode=="block"` changes a currently-green path | It is a fix, not a regression: today `bash -c` receives a second bogus command whose rc=127 corrupts decision-matrix states 4/5/7. B1 pins the new behaviour; AC11 re-parses the whole corpus. |
| Widening the block header regresses an existing plan | Zero corpus usage of `\|-`/`\|+`; all bare `command: \|` plans still enter block mode. AC11 verifies. |
| Extracting the awk to a file breaks path resolution in the skill | Use the established `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` pattern already used across the plugin. AC1 asserts the file exists; AC10's full suite exercises the call site. |
| Parity harness passes vacuously | P3 asserts every fixture is genuinely Form-A (has a `command:` key, no competing fenced block) — without it, a Form-B fixture would compare Form-A awk against Form-A+B TS and diverge spuriously or mask a real difference. Known divergences are asserted as known rather than omitted. |
| Fixing only one of the two surfaces | Phase ordering (awk → TS → parity) plus AC8. The harness makes a one-sided fix a hard CI failure. |

## Sharp Edges

- **`bunfig.toml` `pathIgnorePatterns`.** The repo root sets
  `pathIgnorePatterns = [".worktrees/**", "apps/web-platform/**"]`. Work happens inside
  `.worktrees/feat-one-shot-6772-…/`, but paths resolve relative to the worktree root, so
  `plugins/soleur/test/**` is collected normally. Run the suite **from the worktree root**;
  invoking `bun test` from the bare repo against a `.worktrees/…` path silently matches
  zero files and reports success.
- **`scripts.test` is `bash scripts/test-all.sh`, not a bare test runner.** AC10 must use
  it — orphan suites that only the full-suite exit gate exercises are exactly the class
  this change could break.
- **Rule order is the whole bug.** Any future edit that reorders `parse-form-a.awk` can
  silently reintroduce #6772 — the inline rule matches every `command:` line. AC1 and
  F1–F4 are the pins; do not remove them when refactoring.
- **`mode &&` is safe, but not for the obvious reason.** `mode` is uninitialized (`""` →
  falsy) and only ever assigned the string literals `"fold"`/`"block"` (truthy). awk's
  strnum rule would make a `"0"` *read from input* falsy — a string literal is exempt.
  Do not "simplify" this into a comparison against an input-derived value.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Fill it
  before requesting deepen-plan or `/work`.
