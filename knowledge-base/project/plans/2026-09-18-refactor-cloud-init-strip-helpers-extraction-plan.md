---
title: "refactor(test): extract the three duplicated cloud-init strip helpers into two parameterised functions"
date: 2026-09-18
slug: refactor-cloud-init-strip-helpers-extraction
branch: feat-one-shot-7968-cloud-init-strip-helpers
issue: 7968
closes: 7968
type: refactor
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# refactor(test): extract the three duplicated cloud-init strip helpers into two parameterised functions

## Overview

`plugins/soleur/test/cloud-init-user-data-size.test.ts` carries three near-verbatim copies of two
helpers: an extractor that reads a host's `*_rationale_strip` terraform regex literal out of a `.tf`
file (`registryStripRegex` / `inngestStripRegex` / `gitDataStripRegex`), and a predicate that
decides whether that strip is actually wired into the host's `user_data` render
(`registryStripIsApplied` / `inngestStripIsApplied` / `gitDataStripIsApplied`). Each copy must
remember two things: strip line-leading HCL comments before matching, and require the match to be
unique. The third copy forgot the first one, and a fully green suite certified a 42,360 B tree
against Hetzner's 32,768 B cap. This plan collapses the six functions into two parameterised ones
so those two requirements are structural, keeps every existing arm green, and adds a committed
mutation battery proving the shared helpers go red when comment-stripping is removed.

Scope is #7968 only. Nothing under `apps/web-platform/infra/` changes.

## Problem Statement

The guard class these helpers implement is "does the model measure the payload production ships?"
Both halves read `.tf` source with a regex. Reading raw source lets the *prose above* a guard
satisfy the guard: a `#` comment line that names `replace(templatefile(...), local.X, "")` matches
the same regex as the live expression. `#7965` measured exactly that: with the `replace()` wrapper
unwired and one explanatory comment left inside the map, the raw-source predicate returned `true`,
the model applied the strip, and the suite certified a 42,360 B tree — the one that could not
create the host. The fix in #7965 was applied *in the copy* (the inngest predicate now strips
comments and requires a unique anchor); the other two copies still differ from it, and a fourth
host would be a fourth copy.

Measured on this branch (`bun run` probe over the three `.tf` files, 2026-09-18):

| file | anchor matches (stripped / raw) | local definitions (stripped / raw) | `\\` in body | comment lines naming the local |
|---|---|---|---|---|
| `zot-registry.tf` | 1 / 1 | 1 / 1 | no | 0 |
| `modules/git-data-userdata/main.tf` | 1 / 1 | 1 / 1 | no | 1 (prose, not a definition) |
| `inngest-host.tf` | 1 / 1 | 1 / 1 | no | 0 |

And the decisive measurement: **with `stripHclLineComments` removed from all six helpers (sed on a
scratch copy), the suite stays 47/47 green against the real tree.** No existing arm can red on the
mutation this issue is about. The extraction alone would not change that; the fixture arms written
RED in Phase 1 are what make the mutation battery in Phase 3 able to red.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (file:anchor) | Plan response |
|---|---|---|
| The three copies "differ only in a local name and their error strings" | The inngest extractor additionally refuses an HCL `\\` escape (`inngestStripRegex`, the `body.includes("\\\\")` guard); the inngest predicate additionally requires a unique anchor (`anchors.length !== 1`) and two chain links (`_b64gz = base64gzip(local._plain)`, `user_data = local._b64gz`); the registry predicate balances parens from `base64gzip(` where the other two balance from `replace(` | Make the `\\` refusal and anchor uniqueness universal (measured compatible: no body contains `\\`, every anchor is unique). Parameterise the chain as `chain: RegExp[]` (inngest passes two, the others none). Balance from the first `(` after the anchor start — identical to today's behaviour for all three (measured offsets: `base64gzip(` at +22, `replace(` at +18 and +33, each the first paren of its own anchor) |
| Extractor parameterised on `(localName, fileLabel)`; predicate on `(anchorRe, localName)` | Both also need the source text; the predicate needs the optional chain | Signatures below carry `tfSrc` first and `chain` last with a default |
| (implicit) the extraction is semantics-preserving for inngest | Today `inngestStripIsApplied` returns `false` for `anchors.length !== 1`; the shared predicate returns `false` for zero anchors and **throws** for more than one | Deliberate: an ambiguous input is a test defect and must not surface as a misleading cap failure. Recorded here so the diff reviewer is not surprised |
| "The arms are now well covered (47 in that suite)" | `bun test` on this branch: 47 pass, 0 fail, 130 expect() calls, 267 ms | Confirmed; the 47 titles are pinned unchanged by AC2 |
| "add a mutation row (in whatever committed mutation harness the suite already has …)" | The suite has NO committed mutation harness; its mutation history lives in comments (`M3`, `M4b`, `M14`, "measured divergence 24 bytes"). The established repo pattern is a sibling `*.test.sh` battery under `plugins/soleur/test/` (`kb-index-check-guard-mutation.test.sh`, `merge-kb-index-driver-mutation.test.sh`), auto-discovered by `scripts/test-all.sh` via the `plugins/soleur/test/*.test.sh` glob and round-robin sharded at the `run_suite` chokepoint | Create `plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh` in that pattern |

## Research Insights

**Premise Validation (Phase 0.6).** `gh issue view 7968`: OPEN, labels `priority/p2-medium`,
`type/chore`, `domain/engineering`, no closing PR. `gh pr view 7965`: MERGED 2026-09-09T08:37Z,
"fix(inngest): recreate the destroyed host — user_data has been 8 KB over Hetzner's cap since
#7778" (the PR that filed this issue as P2-4). `gh issue view 7695`: CLOSED (the inngest budget
gate). All six helper symbols exist at the cited file (`git grep` on this branch); no ADR rejects
the mechanism — ADR-152 (`knowledge-base/engineering/architecture/decisions/ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md`)
is the decision the helpers guard and its amendments describe the three-instance history; a test
refactor neither reverses nor extends it. No stale premise.

**Property List (Phase 0.6b).**

- P1. Every host's strip extractor reads the comment-stripped `.tf` source and refuses anything but exactly one live definition of the named local.
- P2. Every host's "strip is applied" predicate reads the comment-stripped `.tf` source, refuses anything but exactly one anchor, and only accepts the local when it sits inside the anchor's balanced call.
- P3. A fourth host cannot get a helper that lacks P1/P2 without deliberately bypassing the shared function.
- P4. Removing the comment-strip (or the uniqueness requirement) from the shared function reds a committed test, so the #7965 fail-open is unexpressible rather than review-caught.
- P5. All 47 existing arms keep their titles and stay green; the modelled sizes do not move.

**Cut List (Phase 0.6b, extended after plan-review).**

- `allowHclEscape` parameter on the extractor (suggested by repo research) → buys nothing: no live body contains `\\`, and the refusal exists because Go RE2 and JS RegExp disagree on it for *any* host. Universal refusal is the stricter, parameter-free form.
- A shared `test-helpers.ts` module → buys nothing for P1–P4; the helpers have exactly one consumer file, and `registry-userdata-budget.test.sh` reads `REGISTRY_GZIP_*` constants from this file by path, so moving code out risks breaking a cross-read for zero property gain. Keep both functions in the suite.
- Rewriting the 11 call sites to pass host constants inline → cut in favour of six one-line wrappers keeping the original names; P5 is then free and the diff at the call sites is zero.
- Changing any `cloud-init*.yml` or `.tf` → out of scope by the issue's own instruction.
- Real-tree `test.each` arms that carry each host's anchor *line* and definition *line* as literal strings (plan-review: DHH, code-simplicity, CTO all fired) → a second copy of the per-host knowledge the extraction exists to collapse, and a whitespace reformat of a `.tf` would red it while every real guard stayed correct. The three existing `applies the strip through the shared local` arms already prove the wrappers reach the real files.
- `// MUT:Rn` marker lines inside the shared helpers plus a `let src = tfSrc; src = strip(src)` split written so a deleted line still compiles (DHH P0) → the SUT should read like the six copies do today. The battery mutates by **function-scoped substitution** instead (the `merge-kb-index-driver-mutation.test.sh` shape: slice the function body, assert the anchor occurs exactly once in the slice, substitute).
- Battery rows for the chain check, the `\\` refusal, and "a wrapper carries the wrong constant" (R5/R7/R8/R9 of the first draft) → no property in P1–P5 names them, and the pristine suite already reds on a wrong wrapper constant every run (the inngest size arm throws `not found in inngest-host.tf`). The arms A4/A10 stay as plain arms.
- `localName` identifier validation → defends against a caller that does not exist; replaced by left-anchoring the extractor pattern, which closes a real gap (see hidden assumptions).
- Fixture arms pinning error-message wording or slash/`(?m)` validation (first-draft A3/A5/A8) → no property, no row.
- A second Guard Contract entry for the battery itself → the battery's vacuity is covered by Guard 1's harness rows; a contract for a contract is ceremony.

**Relevant files.**

- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — the six helpers (`registryStripRegex` … `gitDataStripIsApplied`), `stripHclLineComments`, `toNewlineOnlyMultiline`, `renderedGzipB64LenStripped`; call sites in the `rendered user_data size` describe block (size arms, "applies the strip through the shared local" arms, "preserves #cloud-config" / "removes ONLY comments" / "preserves every shebang" arms).
- `scripts/test-all.sh` — `plugins/soleur/test/*.test.sh` is the first entry in the runner's suite globs; new suites are sharded round-robin at the `run_suite`/`skip_suite` chokepoint, so no registration edit is needed. No formatter (prettier/biome) runs over `plugins/soleur/test/*.ts` (verified: no config, none in the runner).
- `scripts/lint-orphan-test-suites.sh` — proves a tracked `*.test.sh` is reached by some runner; runs in `test-all.sh`.
- `plugins/soleur/test/kb-index-check-guard-mutation.test.sh` — the battery shape to mirror: header (PROPERTY / WHY / MUTATION MATRIX / AXIS DISCLOSURE), `#!/usr/bin/env bash`, `set -uo pipefail`, `TMPDIR` pin, degenerate-path refusals, mutate-a-copy-never-the-tracked-file, per-row apply/verify/restore, a landing check that reports a row FAILURE (not a process exit) when the edit changed nothing, the unmutated control as an exit-2 precondition (not a row), row-count floor.
- `plugins/soleur/test/merge-kb-index-driver-mutation.test.sh` — python-anchored mutators with `assert s.count(old) == 1` (the substitution shape adopted here).
- `apps/web-platform/infra/registry-userdata-budget.test.sh` — reads `REGISTRY_GZIP_FLOOR`/`REGISTRY_GZIP_BUDGET` from the TS suite by `grep -oE '^const REGISTRY_GZIP_…'`; those lines must stay byte-identical (AC7).
- Root `bunfig.toml` — `pathIgnorePatterns` excludes `apps/web-platform/**` and `preload`s the git tripwire; irrelevant when the battery runs `bun test` from its scratch tree (verified: a pristine copy passes 47/47 from a scratch dir whose `apps/web-platform/{infra,Dockerfile,.dockerignore}` are symlinks to the real ones).

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` — assert the *reason* of failure, never the return code alone: every RED row names the arm that must appear under `(fail)`, and every row requires `Ran N tests` to equal the pristine total so a compile-broken mutant is INVALID, not RED (measured on bun 1.3.14: a syntax error prints `0 pass / 1 fail / 1 error / Ran 1 test across 1 file.` — the `Ran` line IS present; the discriminator is `N ≠ pristine total`, plus an `error` line).
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the cheapest edit that breaks the named property while staying green is the row; here that edit is measured (strip removed, 47/47 green), which is why fixture arms precede the battery.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — harness rows: one that proves the battery cannot pass a green run (H1), one must-PASS non-canonical input (H2), one that proves a no-op edit is reported (H3), and a floor on rows run.
- `knowledge-base/project/learnings/2026-03-18-shared-test-helpers-extraction.md` — duplicated test helpers diverge; the extraction cost is one call.
- `knowledge-base/engineering/architecture/decisions/ADR-180-guard-contract-as-plan-time-deliverable.md` — the `## Guard Contract` below names the chokepoint, not today's three members.

**Conventions.** `cq-write-failing-tests-before` (fixture arms are written RED first — Phase 1 lands before the wrappers switch over); `cq-cite-content-anchor-not-line-number` (this plan cites symbols, not line numbers); `cq-assert-anchor-not-bare-token` (battery greps `(fail) <describe> > <title>`, not a bare word); `cq-ac-must-not-depend-on-concurrent-sessions` (no wall-clock AC; diffs are against the merge-base, not a moving `origin/main`); `hr-never-run-commands-with-unbounded-output` (every `bun test` capture in the battery goes to a file, summarised by `tail`/`grep`).

**Functional overlap (Phase 1.5b).** functional-discovery queried 3/3 registries: no community artifact offers a TS/bun HCL-literal test helper or a targeted single-mutant battery; nothing installed.

**External research (Phase 1.6).** Skipped — strong local precedent (three sibling batteries, the ADR-152 history) and no external API.

**Plan review (5 reviewers: DHH, Kieran, code-simplicity, CTO devex, Step 4.5 advisor).** All findings were engineering-panel Mechanical and are applied in this revision; the one named-panel Taste finding (CTO: an env-var seam `CLOUD_INIT_SUITE_REPO_ROOT` in the SUT instead of the scratch tree's symlinks) is declined here and persisted to `knowledge-base/project/specs/feat-one-shot-7968-cloud-init-strip-helpers/decision-challenges.md`.

**Hidden assumptions made explicit (from review).**

- The extractor pattern is left-anchored with `(?<![a-z0-9_])` so `x_registry_rationale_strip = …` cannot satisfy `registry_rationale_strip`; `main.tf` already carries the sibling `git_data_rationale_strip` beside `git_data_template_rationale_strip` (harmless today only because the prefix differs).
- `stripIsApplied` balances from the first `(` after the anchor start, so every anchor must put the OUTERMOST call's paren first (`base64gzip(` / `replace(`). True for the three anchors; the wrapper docblock states the contract so a fourth host's author sees it at the call site.
- `anchorRe` must be `/g`; `matchAll` throws a TypeError otherwise — loud, so left as the contract.
- The scratch copy must sit exactly three directories deep (`REPO_ROOT = join(import.meta.dir, "..", "..", "..")`), and the walker arm's `readdirSync(INFRA)` must resolve through the `infra` symlink — both verified on this branch; the control run additionally asserts the walker arm's title is in the pass list.

## Proposed Solution

### The two shared functions

```ts
// plugins/soleur/test/cloud-init-user-data-size.test.ts

// The HCL string body of a strip local, backslash-pair aware. Kept as a LITERAL (not a template
// string) so the pattern reads as it did in the three copies and AC4's fixed-string grep = 1 holds.
const STRIP_LITERAL_RE = /\s*=\s*"((?:[^"\\]|\\.)*)"/;

// Reads `local.<localName> = "/(?m).../"` from COMMENT-STRIPPED `.tf` source. Structural, not
// remembered: every host goes through this one function, so "strip first" and "exactly one live
// definition" cannot be forgotten by a fourth copy. (The M3 / "the comment I wrote to explain it
// satisfied it" history from the three copies' docblocks moves here, once.)
function extractStripRegex(tfSrc: string, localName: string, fileLabel: string): RegExp {
  const src = stripHclLineComments(tfSrc);
  // Left-anchored: `x_<localName>` must not satisfy `<localName>`.
  const all = [...src.matchAll(new RegExp(`(?<![a-z0-9_])${localName}${STRIP_LITERAL_RE.source}`, "g"))];
  if (all.length === 0) throw new Error(`local.${localName} not found in ${fileLabel}`);
  if (all.length > 1) throw new Error(`local.${localName} must be declared exactly once in ${fileLabel}, found ${all.length}`);
  let body = all[0][1];
  if (!body.startsWith("/") || !body.endsWith("/")) throw new Error(`${localName} must be a slash-delimited terraform regex literal, got: ${body}`);
  body = body.slice(1, -1);
  if (!body.startsWith("(?m)")) throw new Error(`${localName} must be multiline-anchored ((?m)), got: ${body}`);
  // Universal now (was inngest-only): Go RE2 and JS RegExp disagree on `\\`, so the model would
  // measure a payload production never ships.
  if (body.includes("\\\\")) throw new Error(`${localName} contains an HCL backslash escape (${body}); Go RE2 and JS RegExp do not agree on it`);
  return new RegExp(toNewlineOnlyMultiline(body.slice("(?m)".length)), "g"); // `g` only — never `m`
}

// Is the strip WIRED INTO the render? Decided from COMMENT-STRIPPED source. Zero anchors → `false`
// (unwired — the size arm then models the unstripped payload and reds at the cap, for the reason
// the host would fail). More than one anchor → THROW with the count: an ambiguous input is a test
// defect, not an unwired strip, and must not surface as a misleading cap failure. `anchorRe` is
// /g so matchAll can count it. The anchor's FIRST `(` must belong to the outermost call whose
// balanced span should contain the local (`base64gzip(` / `replace(`) — see the wrappers.
function stripIsApplied(tfSrc: string, anchorRe: RegExp, localName: string, chain: readonly RegExp[] = []): boolean {
  const src = stripHclLineComments(tfSrc);
  const anchors = [...src.matchAll(anchorRe)];
  if (anchors.length === 0) return false;
  if (anchors.length > 1) throw new Error(`${anchorRe.source} must match exactly once, found ${anchors.length}`);
  const open = src.indexOf("(", anchors[0].index!);
  let depth = 0, end = -1;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "(") depth++;
    else if (src[i] === ")" && --depth === 0) { end = i; break; }
  }
  if (end === -1) return false;
  if (!new RegExp(`local\\.${localName}\\b`).test(src.slice(open, end + 1))) return false;
  return chain.every((re) => re.test(src));
}
```

### The six wrappers (names and call sites unchanged; one space around `=`, one per line)

```ts
// Anchor contract: the first `(` in each anchor is the OUTERMOST call whose span must contain the
// local — the registry anchor starts its span at `base64gzip(`, the other two at `replace(`.
const registryStripRegex = (tf: string) => extractStripRegex(tf, "registry_rationale_strip", "zot-registry.tf");
const inngestStripRegex = (tf: string) => extractStripRegex(tf, "inngest_rationale_strip", "inngest-host.tf");
const gitDataStripRegex = (tf: string) => extractStripRegex(tf, "git_data_template_rationale_strip", "the git-data render module");

const registryStripIsApplied = (tf: string) =>
  stripIsApplied(tf, /user_data\s*=\s*base64gzip\(\s*replace\(\s*templatefile\(/g, "registry_rationale_strip");
const gitDataStripIsApplied = (tf: string) =>
  stripIsApplied(tf, /rendered\s*=\s*replace\(\s*templatefile\(/g, "git_data_template_rationale_strip");
const inngestStripIsApplied = (tf: string) =>
  stripIsApplied(tf, /inngest_user_data_plain\s*=\s*replace\(\s*templatefile\(/g, "inngest_rationale_strip", [
    /inngest_user_data_b64gz\s*=\s*base64gzip\(\s*local\.inngest_user_data_plain\s*\)/,
    /user_data\s*=\s*local\.inngest_user_data_b64gz/,
  ]);
```

A fourth base64gzip'd host adds two wrapper lines here and (as the walker arm already requires) a
`<HOST>_GZIP_BUDGET` constant — nothing else.

### The fixture arms (Phase 1, written RED first) — what lets the battery red

A new `describe("shared strip helpers are structural (#7968)")` block over small synthetic HCL
strings using a host name that exists nowhere in `infra/` (`x_`), so no arm can accidentally pass
by reading a real file. Nine arms, each mapping to a property or a mutation row:

| arm | fixture | expected | buys |
|---|---|---|---|
| A1 extractor ignores a commented decoy definition | `# historical: x_rationale_strip = "/(?m)^.*\n?/"` above the live definition | returns the LIVE body | P1, row R1 |
| A2 extractor refuses a duplicate live definition | two uncommented definitions | throws `/exactly once/` | P1, row R4 |
| A3 extractor is left-anchored | only `y_x_rationale_strip = "/(?m)…/"` present | throws `/not found/` | P1 (hidden assumption) |
| A4 extractor refuses an HCL backslash escape | body containing `\\` | throws `/backslash/` | universal-refusal decision |
| A5 predicate accepts the canonical inngest-shaped chain | hoisted locals + two chain links | `true` | the must-PASS control that keeps A6/A8/A9 from being satisfiable by `return false` |
| A6 predicate is not satisfied by a comment naming the chain (the #7965 fail-open) | `replace()` unwired, one `#` line carrying the full expression | `false` | P2, row R2 |
| A7 predicate refuses a second anchor | the block duplicated under a decoy resource | throws `/exactly once/` | P2, row R3 |
| A8 predicate requires every chain link | the `user_data = local.x_b64gz` link removed | `false` | `chain` parameter |
| A9 predicate bounds the local to the balanced call | registry-shaped anchor with the local mentioned only in a later resource → `false`; with it inside the call → `true` | as stated | P2, row R6 |

Design-probed on this branch before the plan was written: with the strip present, A1 returns the
live body and A6 returns `false`; with the strip removed, A1 throws `found 2` and A6 returns
`true` — the exact `control: true / MUT-A: true` pair #7965 reported.

### The mutation battery (Phase 3)

`plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh`, in the shape of
`kb-index-check-guard-mutation.test.sh`:

1. Prelude: `#!/usr/bin/env bash`, `export TMPDIR="${TMPDIR:-/var/tmp}"`, `set -uo pipefail`, degenerate-path refusals, `WORK=$(mktemp -d)`. Build `$WORK/plugins/soleur/test/` and `$WORK/apps/web-platform/`; symlink `infra`, `Dockerfile`, `.dockerignore` from the real tree (read-only inputs). One comment names the depth invariant: the suite derives `REPO_ROOT` from `import.meta.dir/../../..`, so the copy must sit exactly three directories deep. Never touch the tracked file.
2. `run_suite <copy>`: `(cd "$WORK" && bun test plugins/soleur/test/cloud-init-user-data-size.test.ts > "$OUT" 2>&1)`; captures rc, the `N pass` / `N fail` lines, whether an `N error` line is present, and `Ran N tests?` (singular accepted, as `preflight-check10-suite-integrity.test.sh` does).
3. Control (exit-2 precondition, not a row): pristine copy → rc 0, `0 fail`, no `error` line, `Ran N` captured as `PRISTINE_TOTAL` and asserted `== 56`, and the walker arm's title present in the pass list (pins symlink resolution).
4. `mutate <row> <fn-name> <old> <new>`: python slices the copy between `function <fn-name>(` and the next `\n}\n`, asserts `slice.count(old) == 1`, substitutes, writes the copy. **Returns** 2 (never exits) when the anchor is absent or the file is byte-identical afterwards (`diff -q` against the pristine copy); the calling row records `LANDING-FAILED` and counts as a failed row — the `mb_case` / `LANDING-FAILED` precedent.
5. `expect_red <row> <arm-title>`: rc ≠ 0 AND `grep -Fq "(fail) shared strip helpers are structural (#7968) > <arm-title>" "$OUT"` AND no `error` line AND `Ran N` == `PRISTINE_TOTAL`. Returns non-zero (the row is not ok) otherwise — INVALID is reported distinctly from "still green".
6. `expect_green <row>`: rc 0 AND `Ran N` == `PRISTINE_TOTAL`.
7. Floor: a `CASES` counter incremented before each row's assertion; final `rows=$CASES ok=$OK`; exit 1 unless `CASES == EXPECTED_ROWS (8)` and `OK == CASES`.

## Files to Edit

- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — add `STRIP_LITERAL_RE`, `extractStripRegex` and `stripIsApplied`; replace the six function bodies with one-line wrappers (same names); move the docblocks; add the `shared strip helpers are structural (#7968)` describe block. Every `^const <NAME>_(FLOOR|BUDGET) =` line stays byte-identical (cross-read by `registry-userdata-budget.test.sh` and by this file's own walker arm).

## Files to Create

- `plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh` — the battery above (auto-discovered by `scripts/test-all.sh`'s `plugins/soleur/test/*.test.sh` glob; no runner edit).

Pipeline-written artifacts that will also appear in the diff (so a diff-scope AC lists them):
`knowledge-base/project/plans/2026-09-18-refactor-cloud-init-strip-helpers-extraction-plan.md`,
`knowledge-base/project/specs/feat-one-shot-7968-cloud-init-strip-helpers/{tasks.md,session-state.md,decision-challenges.md}`,
`knowledge-base/INDEX.md` (regenerated), and a learning under `knowledge-base/project/learnings/`.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (65 issues) contains no body naming
`cloud-init-user-data-size`, `registryStripRegex`, `inngestStripIsApplied` or `stripHclLineComments`.

## Implementation Phases

### Phase 0 — Preconditions (measure, do not assume)

- `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → `47 pass / 0 fail` (baseline, measured 267 ms).
- Record the 47 test titles: `grep -oE '^\s*test\("[^"]+"' plugins/soleur/test/cloud-init-user-data-size.test.ts | sort > /tmp/titles.before` (pinned by AC2).
- Re-run the uniqueness probe from §Problem Statement if `origin/main` has moved the three `.tf` files since the branch point (`git diff --stat "$(git merge-base origin/main HEAD)" origin/main -- apps/web-platform/infra/{zot-registry.tf,inngest-host.tf,modules/git-data-userdata/main.tf}`); the universal-uniqueness and universal-`\\`-refusal decisions are valid only while its table reads 1/1 everywhere and "no" in the `\\` column.

### Phase 1 — RED: the fixture arms against the not-yet-existing shared functions

Write the `describe("shared strip helpers are structural (#7968)")` block (A1–A9) calling
`extractStripRegex` / `stripIsApplied`. `bun test` must fail with the two symbols undefined —
that is the RED. Fixtures are inline template strings; the `x_` host shape mirrors
`inngest-host.tf`'s hoisted-locals chain for A5–A8 and `zot-registry.tf`'s
`user_data = base64gzip(replace(templatefile(` shape for A9.

### Phase 2 — GREEN: the shared functions and the six wrappers

Add `STRIP_LITERAL_RE` and the two functions (§Proposed Solution), replace the six bodies with the
wrappers, move the docblocks. `bun test` → `56 pass / 0 fail`. `git diff` must show no changed
line inside the `rendered user_data size` describe block (call sites untouched).

### Phase 3 — the mutation battery

Write `cloud-init-strip-helpers-mutation.test.sh` with the rows in the Guard Contract. Run it
directly (`bash plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh`) — expect
`rows=8 ok=8` and exit 0. Then `bash scripts/lint-orphan-test-suites.sh` (the new suite must be
`git add`ed first — it reads `git ls-files`) and `bash scripts/test-all.sh --print-suite-globs`
to confirm the glob still expands over it. Do NOT run the full `scripts/test-all.sh` in this
phase; the `/ship` full-battery checkpoint does.

### Phase 4 — verification of the sharp edges

- `git diff --stat "$(git merge-base origin/main HEAD)" -- apps/web-platform/infra` is empty.
- `grep -cF '((?:[^"\\]|\\.)*)' plugins/soleur/test/cloud-init-user-data-size.test.ts` = 1 (was 3).
- `git diff "$(git merge-base origin/main HEAD)" -- plugins/soleur/test/cloud-init-user-data-size.test.ts | grep -cE '^[-+]const [A-Z_]+_(FLOOR|BUDGET) ='` = 0.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on the day it lands — the payload
  budgets are unchanged and the hosts are up. The exposure is the next over-cap edit to any
  `cloud-init-*.yml`: if the shared predicate is vacuous (returns `true` for an unwired strip) the
  suite stays green, the next `*-host-replace` dispatch destroys a host Hetzner then refuses to
  recreate, and every workspace loses that host's function (Inngest crons and scheduled agents,
  the registry pull path, or git-data) until an operator trims the payload — the #7965 outage
  shape, repeated.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector —
  the diff touches a test file and a test battery; it reads committed `.tf` text and writes only
  under `mktemp -d`. No secrets, no customer data, no production write.
- **Brand-survival threshold:** `aggregate pattern` — a vacuous guard fails every workspace at
  once on the next incident, not one user at a time.

## Observability

The surface is CI (the required `test` check running `scripts/test-all.sh`), not production code;
the layer covering every failure mode below is layer 6 (workflow run log) per
`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.

```yaml
liveness_signal:
  what: the `test` required check on every PR runs the `bun` shard (which executes cloud-init-user-data-size.test.ts) and the scripts shards (which execute cloud-init-strip-helpers-mutation.test.sh via the plugins/soleur/test/*.test.sh glob)
  cadence: every push to a PR and every merge to main
  alert_target: red required check blocks the merge (branch ruleset); workflow run log names the failing suite
  configured_in: scripts/test-all.sh (suite globs + run_suite chokepoint), .github/workflows/ci.yml
error_reporting:
  destination: GitHub Actions workflow run log (observability layer 6 — workflow run log); the runner prints the failing suite name and the `(fail) … > <arm>` line from bun
  fail_loud: true — any non-zero suite reds the required check; the battery exits 1 on any row mismatch and 2 on a failed precondition
failure_modes:
  - mode: the shared helper regresses (comment-strip or uniqueness removed) and the real-tree arms stay green
    detection: fixture arms A1/A2/A6/A7 red in the bun shard; the battery rows R1–R4 red in the scripts shard — both in the workflow run log (layer 6)
    alert_route: red `test` required check on the PR
  - mode: the battery goes vacuous (a substitution anchor no longer matches after a rename; a mutant fails to compile and "reds" for the wrong reason)
    detection: `mutate` returns LANDING-FAILED on a zero-byte edit and the row fails; `expect_red` requires `Ran N` == pristine total, no `error` line, and the named arm under `(fail)` — reported in the workflow run log (layer 6)
    alert_route: red `test` required check
  - mode: the battery is never executed (glob drift, orphaned suite)
    detection: scripts/lint-orphan-test-suites.sh reds in the scripts shard (workflow run log, layer 6); scripts-shard-totality.test.sh reds if the partition drops a registration
    alert_route: red `test` required check
logs:
  where: GitHub Actions run log for the `test` workflow (per-suite stdout via run_suite; TEST_TIMING_LOG artifact)
  retention: GitHub Actions default log retention for the repo
discoverability_test:
  command: bash plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh
  expected_output: a per-row `ok` line for every row and a final `rows=8 ok=8` summary, exit 0
```

## Guard Contract

### Guard 1 — shared strip helpers (`extractStripRegex` / `stripIsApplied`) with their fixture arms and battery

**Property.** For every base64gzip'd host, the suite models the strip production applies only when the host's `.tf` declares exactly one live strip local and wires it, uniquely, inside the render call — decided from comment-stripped source, never from prose.

**Assembly.** The chokepoint is the pair of shared functions in `plugins/soleur/test/cloud-init-user-data-size.test.ts`: every per-host wrapper (`registryStripRegex`, `inngestStripRegex`, `gitDataStripRegex`, `registryStripIsApplied`, `inngestStripIsApplied`, `gitDataStripIsApplied`) is a one-line delegation carrying only constants, and every size/applies/preserves arm reaches the `.tf` text through a wrapper. A fourth host adds wrapper lines, not a fourth body. The members that flow through it today are the three hosts named in the walker arm ("every base64gzip'd host has a committed byte measurement"), which is derived from `readdirSync(INFRA)` — the walker, not this list, is what enumerates hosts.

**Mutation matrix** (each row is a function-scoped substitution in the battery; `old` must occur exactly once inside the named function):

| # | Mutation | Expected |
|---|---|---|
| R1 | in `extractStripRegex`: `stripHclLineComments(tfSrc)` → `tfSrc` (reads raw source) | RED — A1 (a commented decoy becomes a second definition → throws) |
| R2 | in `stripIsApplied`: `stripHclLineComments(tfSrc)` → `tfSrc` | RED — A6 (the #7965 fail-open: a comment naming the chain returns `true`) |
| R3 | in `stripIsApplied`: `if (anchors.length > 1)` → `if (false && anchors.length > 1)` (first-match semantics, the pre-#7965 registry/git-data shape) | RED — A7 (second anchor accepted instead of throwing) |
| R4 | in `extractStripRegex`: `if (all.length > 1)` → `if (false && all.length > 1)` | RED — A2 (duplicate live definition accepted) |
| R6 | in `stripIsApplied`: `.test(src.slice(open, end + 1))` → `.test(src)` (the balanced-call bound is gone) | RED — A9 (an out-of-span mention is accepted) |

R3 and R4 are the "second member after a compliant first" rows; R1/R2 are the operator-mandated row and its predicate sibling; R6 pins the balanced-call clause of P2.

**Harness rows** (edits to the harness, and the non-canonical must-PASS):

| # | Edit | Expected |
|---|---|---|
| H1 | run `expect_red R1 "<A1 title>"` against the CONTROL run's output (a green run) | must return non-zero — proves the battery cannot mark a green run as RED and that the named-arm grep is live; zero extra bun runs |
| H2 | in `extractStripRegex`: substitute `\bsrc\b` → `hcl` throughout the function slice (a benign rename) | GREEN — proves the battery is not rejecting every edit |
| H3 | apply R1 to a copy on which R1 was already applied | `mutate` returns 2 (anchor absent / zero-byte edit) and the row asserts exactly that — proves a renamed helper cannot make a row a silent no-op |

**Anchor.** The rows compare nothing stored; the guard's value is a live evaluation over the `.tf` text each run, so no merge-base or registry anchor applies. The battery's own substitution anchors are pinned by H3 (a drifted anchor is a reported row failure, not a pass).

## Acceptance Criteria

- [ ] AC1 — `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` prints `56 pass`, `0 fail` (47 pre-existing + 9 fixture arms A1–A9).
- [ ] AC2 — the 47 pre-existing test titles are unchanged: `grep -oE '^\s*test\("[^"]+"' <file> | sort` before vs after differs only by the 9 added titles inside the new describe block (`diff <(before) <(after) | grep -c '^<'` = 0; `grep -c '^>'` = 9).
- [ ] AC3 — the file defines exactly one `function extractStripRegex(` and one `function stripIsApplied(` (`grep -c` = 1 each), and the six original names remain one-line wrappers (`grep -cE '^const (registry|inngest|gitData)Strip(Regex|IsApplied) = \(tf: string\) =>' <file>` = 6; no formatter runs over this directory, so the spelling is stable).
- [ ] AC4 — `grep -cF '((?:[^"\\]|\\.)*)' <file>` = 1 (the HCL-string-body pattern exists once, as the `STRIP_LITERAL_RE` literal).
- [ ] AC5 — `bash plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh` exits 0 and its last line is `rows=8 ok=8`.
- [ ] AC6 — the battery's H1 row prints `ok` and its log line shows `expect_red R1` returning non-zero on the control output (the battery cannot pass a green run); the battery as a whole still exits 0.
- [ ] AC7 — `git diff --stat "$(git merge-base origin/main HEAD)" -- apps/web-platform/infra` is empty, and `git diff "$(git merge-base origin/main HEAD)" -- plugins/soleur/test/cloud-init-user-data-size.test.ts | grep -cE '^[-+]const [A-Z_]+_(FLOOR|BUDGET) ='` = 0.
- [ ] AC8 — `bash scripts/lint-orphan-test-suites.sh` exits 0 with the new suite tracked (`git ls-files plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh` prints the path).
- [ ] AC9 — the battery never writes inside the repo: `git status --porcelain -- plugins/soleur/test apps/web-platform/infra` is identical before and after `bash plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh`.
- [ ] AC10 — `git diff --name-only "$(git merge-base origin/main HEAD)"` is a subset of: `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `plugins/soleur/test/cloud-init-strip-helpers-mutation.test.sh`, `knowledge-base/project/plans/2026-09-18-refactor-cloud-init-strip-helpers-extraction-plan.md`, `knowledge-base/project/specs/feat-one-shot-7968-cloud-init-strip-helpers/**`, `knowledge-base/INDEX.md`, `knowledge-base/project/learnings/**`.
- [ ] AC11 — PR body carries `Closes #7968` (body, not title).

## Test Scenarios

- Given the pristine suite, when `bun test` runs, then 56 pass and the modelled registry/inngest/git-data sizes equal the pre-refactor values (the `_FLOOR`/`_BUDGET` assertions are unchanged and green).
- Given a `.tf` string with a `#`-commented `x_rationale_strip` definition above the live one, when `extractStripRegex(src, "x_rationale_strip", "x.tf")` runs, then it returns the live body; and when the comment-strip is substituted away inside the function (R1), then it throws `must be declared exactly once`.
- Given a `.tf` string where `replace()` is unwired and one `#` line names `x_plain = replace(templatefile(..., local.x_rationale_strip, ""))`, when `stripIsApplied` runs with the inngest-shaped anchor and chain, then it returns `false`; with the comment-strip substituted away (R2) it returns `true` — the exact #7965 verdict pair.
- Given a `.tf` string carrying the anchor twice, when `stripIsApplied` runs, then it throws `must match exactly once, found 2` (not `false`, not `true`); with R3 applied it returns `true` (A7 reds).
- Given the registry-shaped anchor and a `.tf` string mentioning `local.x_rationale_strip` only in a later resource, when `stripIsApplied` runs, then `false`; with R6 applied, `true` (A9 reds).
- Given a `.tf` string whose only definition is `y_x_rationale_strip = …`, when the extractor is asked for `x_rationale_strip`, then it throws `not found`.
- Given the battery, when H1 runs `expect_red R1` against the control output, then `expect_red` returns non-zero and the H1 row prints `ok`.
- Given a compile-broken mutant, when `run_suite` runs it, then bun prints an `error` line and `Ran 1 test`, and `expect_red` reports INVALID (not ok) because `1 ≠ 56`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a test-file refactor and a
test battery; no product surface, no legal/finance/marketing/sales/support/operations touch).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Parameterise the `\\` refusal (`allowHclEscape`) | No live body has `\\`; the refusal reasons about engine divergence, not about a host. Universal is stricter and simpler. |
| Keep first-match (`.exec`) semantics for registry/git-data predicates | That is the M4b class #7965 closed for inngest; the point of the extraction is to make uniqueness structural. Measured safe: every anchor is unique today. |
| Move the helpers to a `test/lib/*.ts` module | One consumer; `registry-userdata-budget.test.sh` cross-reads constants from this file by path; a module adds a seam with no property gain. |
| Put the mutation rows inside the TS suite (in-memory sed on a string copy of the helper) | Cannot mutate the *function under test* from inside the same module without `eval`; the repo's established pattern is a sibling `.test.sh` that mutates a copy of the SUT. |
| Rely on the fixture arms alone, no battery (Step 4.5 advisor, Change 1) | The arms are the guard; the battery is the proof the guard reds (H1–H3). The operator's direction asks for a committed mutation row explicitly. Not a User-Challenge: the session model does not agree the direction should change. The advisor's real-tree in-process arms were adopted in the first draft and then cut at plan-review (three reviewers: a second copy of the per-host knowledge, drift-prone on `.tf` whitespace). |
| Predicate throws on ANY anchor-count ambiguity, including zero (advisor Change 2) | Adopted for `> 1`. Kept `false` for zero anchors: that IS the unwired case, and the size arm's "reds at the cap for the reason the host would" semantics depend on it. |
| `// MUT:Rn` marker lines in the SUT + `grep -v` mutator (first draft; the `lint-guard-contract.test.sh` convention) | Rejected at plan-review (DHH P0): the SUT would carry a map of every way the harness intends to break it, and the `let/assign` split existed only so a deleted line compiles. Function-scoped substitution keeps the helpers reading like the six copies do today. |
| An env-var seam (`CLOUD_INIT_SUITE_REPO_ROOT`) in the SUT instead of the scratch tree's symlinks (CTO devex, Taste) | Declined: it adds a production-side seam to the suite for the harness's benefit — the same shape as the marker objection — and the symlinked scratch tree is verified and needs one comment. Persisted to `decision-challenges.md` for the operator. |

No deferrals arise from this table — every alternative is rejected outright, so no tracking issue is
filed.

## Dependencies & Risks

- **Semantic widening (registry/git-data predicates now require a unique anchor; inngest's `false` on ambiguity becomes a throw; all extractors refuse `\\`).** Mitigated by the Phase 0 measurement (1/1 everywhere, no `\\`) and by AC1/AC7; if a future `.tf` legitimately needs a second anchor, the predicate throws with the count — loud, and the right direction for ADR-152.
- **Battery anchors drift with the helper's text.** A drifted `old` string is a reported `LANDING-FAILED` row (H3 pins the mechanism), never a silent pass; the fix is a one-line anchor update in the battery, and the battery header says so.
- **`bun test` from a scratch tree skips the root `bunfig.toml`.** Intended: the tripwire preload guards git-writing fixtures, and this suite writes nothing; `pathIgnorePatterns` is moot because only `infra`, `Dockerfile` and `.dockerignore` are linked (no `apps/web-platform/test/` reaches the scratch tree).
- **Concurrent runs.** Everything lives under `mktemp -d`; no in-tree mutant is ever written, so a sibling `bun test plugins/soleur/` shard cannot pick up a mutant.
- **Runtime cost (information, not a gate).** 1 control + 7 bun runs (H1 reuses the control output) at ~0.1–0.3 s each; no `_suite_budget_ms` entry needed.

## References & Research

- Issue #7968 (this plan); PR #7965 (filed it — merged 2026-09-09); #7695 (inngest gate), #7278 (registry gate), #7264 (git-data template strip).
- `knowledge-base/engineering/architecture/decisions/ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md` and its 2026-09-09 amendment (three instances of one class).
- `knowledge-base/engineering/architecture/decisions/ADR-180-guard-contract-as-plan-time-deliverable.md`.
- `knowledge-base/engineering/operations/post-mortems/2026-07-03-hetzner-fresh-host-userdata-32kb-cap-postmortem.md`.
- `plugins/soleur/test/kb-index-check-guard-mutation.test.sh` (battery shape), `plugins/soleur/test/merge-kb-index-driver-mutation.test.sh` (python-anchored mutators with `count == 1` assertions).
