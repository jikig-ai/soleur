---
title: "chore(plugin): migrate the skills ${CLAUDE_PLUGIN_ROOT:-…} and git-root anchors to the bare plugin-root anchor (ADR-179)"
date: 2026-09-24
slug: chore-migrate-skills-plugin-root-default-sites-to-bare-anchor
branch: feat-one-shot-7453-bare-plugin-root-anchor
issue: 7453
closes: 7453
type: chore
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-24
**Research agents used:**

- security-sentinel
- test-design-reviewer
- observability-coverage-reviewer
- git-history-analyzer (attribution)
- a standard-tier verify-the-negative pass, with 10 claims checked against code

The halt gates all passed: 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT sweep and 4.11 Guard
Contract (the lint is green on 4 entries, and the adequacy read found the assemblies structural).
4.9 and 4.10 were not applicable: there is no UI surface and no store or connection.

### Key improvements

1. **The Read-surface placeholder is now a sentinel.** `export CLAUDE_PLUGIN_ROOT=<PLUGIN_ROOT>`
   was a bash syntax error when left unreplaced, and it fired before the fail-closed check (from
   test design). It is now the absolute, cannot-exist `"/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"`,
   which fails closed with a legible message.
2. **All seven pointers to the admin-merge and review docs are loader-anchored,** including the
   relative markdown links. The old assumption that those links resolve against the skill base
   directory could not be tested. AC12 now relocates the plugin away from the working directory and
   plants canaries there (from the security review).
3. **Guard 1 now also catches writes to the root**, through the new `plantsRootUnsafely`: a
   `CLAUDE_PLUGIN_ROOT=` assignment, a default arm of any variable pointing at `plugins/soleur`,
   and `env` reads. Guard 2's regexes were widened to 2a, 2b and 2c. All seven bypass forms the
   security review measured are now caught, with 0 new false positives, measured with node against
   575 files.
4. **Every decoy row has a twin positive control.** Every guard has a live-scan dispatch control.
   Population floors no longer depend on the enumerator. The schedule template row asserts the
   extracted block is non-empty (from test design).
5. **The Tier-1 gates `run-scan.sh` and `emit-review-trailer.sh` had no caller rule for a crashed
   or 127 exit.** The verification pass found this. Each gets a one-line fail-safe rule.
6. **The Observability block now cites layers.** It uses `cli-stdout-artifact` (layer 7), the
   workflow-run log (layer 6) and pino (layer 2). It adds the unresolved-root and Grok failure
   modes, and states that carve-out drift is detected only by CI.

### New considerations discovered

- `schedule/SKILL.md`'s mention of `admin-merge-ready.sh` must stay prose, never the token. An
  authoring agent could copy it into a generated workflow and leak the operator's install path.
- `TRAILING_SAFE_REDIRECT` must be exported, with its value unchanged, so the coupling test can
  normalise a `list 2>/dev/null` emission.
- All ten attribution claims (PRs, commits, issues and knowledge-base paths) were confirmed live.

## Overview

This plan moves every executable plugin-root reference in the Soleur payload's markdown that
still resolves through a caller-controlled path onto the canonical anchor that ADR-179 ratified.
"Caller-controlled" here means a `${CLAUDE_PLUGIN_ROOT:-…}` default arm or an unconditional
`$(git rev-parse --show-toplevel)`. The canonical anchor is a quoted, payload-relative, bare
`"${CLAUDE_PLUGIN_ROOT}/<path>"`. The plan also re-points the guards and the hosted
prompt-suppression carve-out that keyed on the old form, so that the old form cannot grow back.

The governing decision is **ADR-179**. The issue's title and body cite ADR-177; that ordinal is a
rename artifact, corrected in the issue's 2026-08-12 comment. This change **amends ADR-179**. It
reverses nothing in it: decision 1 already governs "every customer-facing executable path in
plugin markdown", and this retires the deferral recorded in its Consequences.

Scope, measured on `origin/main` (`ed37571a45`):

- **98 `${CLAUDE_PLUGIN_ROOT:-…}` occurrences in 31 markdown files, in two groups.**
  - **97 are agent-executable.** 89 are in loader-delivered `SKILL.md` files and 8 are in
    read-from-disk `references/*.md`.
  - **1 is a workflow template** (`schedule`), which gets its own treatment.
- **4 prose mentions of the rejected form**, reworded so that the literal leaves the payload.
- **The Read surface.** Five non-`SKILL.md` docs carry executable bare tokens that the loader
  never substitutes. Each gets a loader-anchored pointer, per-block root delivery and a notice.
  The five CWD-relative prose mentions of the admin-merge gate script are anchored too.
- **The 2 Pattern-C git-root code roots** in `preflight/SKILL.md`. These are severity-first: one
  of them executes a gate.
- **The `safe-bash.ts` exact-literal carve-out** for `worktree-manager.sh list|ls`. It keeps
  exact equality. There is no `^bash` regex and no denylist change.
- **Guard updates** that turn the migration into a zero-tolerance invariant over the whole
  payload's markdown.

This branch has no `spec.md`, so the lane has no valid value. It defaults to `lane: cross-domain`
(TR2 fail-closed).

The substitution-mechanism prerequisite (ADR §R3 "UNRESOLVED") is **already resolved**, by A10 and
#8391 Arm 5; see Premise Validation. This plan cites those measurements and does not run the
measurement again.

## Research Insights

### Premise Validation (Phase 0.6)

Checked against `origin/main` at `ed37571a45`. `f05728690b` (#8718, CI reaper) landed later and
touches none of the files below.

- **#7453 is OPEN.** Its title and body cite ADR-177. The 2026-08-12 comment corrects this to
  **ADR-179**. ADR-177 covers the test-runner result taxonomy. The ADR was renumbered 177→179
  inside `98ad03aa8`. The comment also records that the secret-gate subset shipped in #7482, and it
  names Pattern C (the two unconditional `git rev-parse` anchors in `preflight/SKILL.md`) as
  severity-above-baseline, routed to this issue.
- **The option-(d) sites (`${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}`)
  are already gone from shipped markdown.** #7482 migrated `incident`, `legal-generate`,
  `linear-fetch`, `compound`, `trigger-cron` and `community`. The only remaining occurrences are
  `FORBIDDEN` needles in `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`, and they
  must stay. The severity-first item that is **still live** is Pattern C:
  `plugins/soleur/skills/preflight/SKILL.md` (`FORM_A_AWK=` and `PROBE_GATE=`).
- **The substitution prerequisite (ADR §R3 "UNRESOLVED") is stale. It was resolved twice.**
  - ADR-179 **A10** (#7450 review remediation) ran the missing arm directly. It used a headless
    `claude -p --plugin-dir` and a synthetic skill with a **bare token inside a fenced `bash`
    block in `SKILL.md`**. The token was substituted at delivery with the real install root. In
    the same run the `:-` form arrived literal and expanded to a planted decoy. A control proved
    the decoy was present in the executing shell (`ENV_GREP=[1]`). §R3 already carries a
    "SUPERSEDED 2026-08-12 by amendment item A10" pointer.
  - **#8391** (Arm 5) extended the measurement to the command surface on both Claude Code and
    Grok Build 1.0.34: `${CLAUDE_PLUGIN_ROOT}` and `'${CLAUDE_PLUGIN_ROOT}'` were SUBSTITUTED,
    while `$CLAUDE_PLUGIN_ROOT` and `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` stayed literal.
  - **A third observation came from this planning session.** The `soleur:plan` SKILL.md loaded
    here carries `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"` in an inline span, and it
    arrived as `bash "/data/git-repositories/jikig-ai/soleur/plugins/soleur/scripts/cloud-detect.sh"`.
    Its three `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` sites arrived unchanged. The skill **args**
    were rewritten too: the operator's "299 bare `${CLAUDE_PLUGIN_ROOT}` sites" reached the skill
    body as an absolute path. So the transform runs after `$ARGUMENTS` interpolation, over the
    whole delivered text.
  - Two facts follow for this migration. The root is the **main checkout's** `plugins/soleur`, not
    this worktree's. And the string the agent emits carries an absolute path, never the token.
  - **Conclusion:** no new A/B arm is owed. The plan cites A10 and Arm 5 and does not re-measure.
- **The `safe-bash.ts` coupling blocks only the `list`/`ls` sites.** This matches the issue's 3rd
  comment. `EXACT_LITERAL_SAFE_COMMANDS` is a closed set of two literals, both
  `worktree-manager.sh list|ls`. `SAFE_BASH_PATTERNS` has no `^bash <path>` regex.
- **The prior PRs that cite #7453, and what each migrated:**
  - #7443 (`98ad03aa8`): the command surface and ADR-179 itself.
  - #7482 (`449b8c31a`): the secret-gate subset (5 §R5 sites + `trigger-cron` + `community`),
    Decision 8 (the `settings.json` ban) and Test 21/24.
  - #8070 (`9832d1d39`): one `ship` PIR-gate site moved to bare. The A13
    `${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/…` form was replaced by a git-root **data/repo-root**
    resolution. That is the §R4 class, now prose in a fence comment.
  - #8300 (`dd5c52fa5`): cites the issue only. It migrated nothing.
  - #8391 (`91c8bdccf`): the three `go.md` gates, the Arm 5 measurement and Decision 11.
  - #8570 (`a44cf8f9a`): widened the **skills ratchet** axis in `plugin-root-anchoring.test.ts`,
    baseline 101 → 137 rows. The axis already exists; this PR shrinks it and hardens it rather than
    creating it.
- **Measured population, recounted:**
  - `plugins/soleur/skills/**`: 108 `${CLAUDE_PLUGIN_ROOT:-` lines (109 occurrences) in 34 files.
  - Of those, `.md` holds 101 lines and **102 occurrences in 31 files**. `.sh` holds 7 occurrences:
    `lease-protects-active.test.sh` ×3, `redact-sentinel.test.sh` ×3 and
    `operator-bootstrap/template.sh` ×1.
  - Fence-aware classification of the 102 `.md` occurrences:
    - **98 are executable instructions**: 79 in fence code and 19 in inline spans that tell the
      agent to run them.
    - **4 are prose that names the rejected form**: `community/SKILL.md` (the "not `${…:-…}`"
      sentence), `preflight/SKILL.md` (the rationale comment in the Check 10 fence), `ship/SKILL.md`
      (the A13 history comment in the PIR fence) and `work/SKILL.md` (the #7442 "why" bullet).
  - Elsewhere under `plugins/soleur` there are 6 sites in 4 files: `hooks/devin-session-start.sh`
    (`${CLAUDE_PLUGIN_ROOT:-}`, an emptiness test that is correct as written) and test needles and
    comments in `test/admin-merge-ready-wiring.test.sh`, `test/concurrent-ship.test.sh` and
    `test/go-session-gates.test.sh`.
  - There are 302 bare `${CLAUDE_PLUGIN_ROOT}` lines under `plugins/soleur`. The operator measured
    299, and the gap is explained by counting lines rather than occurrences.
- **Every `:-` target is already payload-relative and exists on disk.** The anchor swap never has
  to rewrite the tail: all 25 distinct targets resolve under `plugins/soleur/`. The one exception
  is the A13 `../../scripts/` prose. The same holds for the 40 distinct bare-anchored operands
  already in skills: 0 missing, and 0 start with `plugins/soleur/`.
- The first comment on #7453 also names a **second population**: bare CWD-relative
  `bash plugins/soleur/…`, `python3 scripts/…` and `./scripts/…` runner operands. These are ratchet
  forms (b)/(d)/(e), about 93 baseline rows. #6222 already tracks them (Vector A covers the
  repo-root `scripts/` class; Vector B covers the `taste-profile-update.sh` siblings). They are out
  of scope here (see Cut List).

### Property List (Phase 0.6b)

- **P1.** An executable plugin-root reference in `plugins/soleur/skills/**/*.md` never resolves
  into a caller-controlled tree when `CLAUDE_PLUGIN_ROOT` is unset. It either names the installed
  payload or fails closed.
- **P2.** No skill executes a payload file located through `git rev-parse --show-toplevel`
  (Pattern C).
- **P3.** Every migrated operand still reaches the same payload file. It is payload-relative, and
  the path exists.
- **P4.** The read-only `worktree-manager.sh list|ls` prompt-suppression on the Concierge server is
  admitted by **exact string equality only**, keeps working after the skill text changes, and
  admits nothing outside the trusted deployed plugin copy.
- **P5.** The migrated population cannot grow back. A new `:-` or git-root code-root site in skills
  code context reddens CI.
- **P6.** The ADR, the guard docstrings and the server comments stop describing the `:-` sites as
  live or load-bearing.
- **P7** *(added at plan review)*. Two requirements for a read-from-disk skill doc: one that
  carries an executable bare token, and one that is Read rather than loader-delivered.
  - **It is itself loaded from the installed payload.** The pointer to it is loader-anchored,
    never a CWD-relative `Read plugins/soleur/…`.
  - **It still resolves**, because the root is re-derivable from the absolute path the agent just
    read, and it never tells the agent to fall back to the CWD.

### Cut List (Phase 0.6b)

- **Re-running the substitution A/B arm → P1/P3.** Already covered by ADR-179 A10 and #8391 Arm 5,
  plus this session's observation. Cut.
- **The per-site decision-2 identity preflight (`plugin.json` names `soleur`, `exit 2`) at every
  one of about 97 non-gate sites → P1.** P1 is already bought by the bare form. When the variable
  is unset it expands to a root-anchored `/skills/...` path that fails closed (decision 5), and
  ADR-179 A11 classifies the identity check as defence-in-depth and a shape check. The gate subset
  keeps its preflights. Cut, and recorded in the ADR amendment.
- **Widening the command-axis P-rules (P4 preflight-per-file, P6 presence guard, P1c quoted) to
  skills wholesale → P5.** The skills ratchet axis is already the enumerator. P5 is bought by
  making form (a) zero-tolerance there and adding a Pattern-C form and a payload-relative rule.
  Cut.
- **Migrating ratchet forms (b)/(d)/(e) → no property in this list.** They are CWD-relative runner
  operands with no `:-` arm, and #6222 tracks them. Several are monorepo-only (`scripts/test-all.sh`
  and `scripts/lint-*`) and need a decision-4/decision-9 disposition, not an anchor swap. Out of
  scope. Routed to #6222.
- **A new `^bash` regex or a denylist relaxation in `safe-bash.ts` → P4.** Forbidden by the issue
  and the operator. Exact literals suffice. Cut.
- **A permanent "operand exists" guard → P3** *(cut at plan review; DHH and code-simplicity
  agreed)*. P3 is a property of this one migration. The fixed-string replace never rewrites the
  tail, and all 25 targets were measured to exist. So a one-time AC check (AC3b) buys P3, with no
  floor, no `PAYLOAD_ROOT` harness and no matrix. The one piece of it that is a standing hazard,
  `${CLAUDE_PLUGIN_ROOT}/..` escaping the payload (Kieran P1-6), moves into Guard 2 as a literal
  alternative.
- **Script wrappers for the reference-file blocks → P7** *(the advisor's alternative)*. Not taken.
  See Phase 6 for the reasoning.
- **The ~20-row hand-applied mutation walk and `mutation-log.md` → the Guard Contract's
  mutation-matrix requirement** *(trimmed at plan review)*. Each guard's RED rows are encoded as
  in-code fixture controls (`P1B_FIXTURES`, `DYNPREFIX_FIXTURES`, the safe-bash negatives). The
  AC walk records one observed-RED per guard, not a row-by-row log.

### Relevant files (content anchors)

- `apps/web-platform/server/safe-bash.ts`: `WORKTREE_MANAGER_DEPLOYED_FORM`,
  `EXACT_LITERAL_SAFE_COMMANDS`, stage 0 of `isSafeSingleSegment`, `SHELL_METACHAR_DENYLIST`.
- `apps/web-platform/server/plugin-path.ts`: `SOLEUR_PLUGIN_PATH_DEFAULT = "/app/shared/plugins/soleur"`.
  This is the path the SDK `plugins:[{path}]` binding loads, so it is the root substituted into
  hosted skill text.
- `apps/web-platform/server/agent-env.ts`: the `pluginPath` docstring and the `CLAUDE_PLUGIN_ROOT`
  injection comment. Both call the `:-` sites load-bearing. The injection stays fail-closed.
- `apps/web-platform/server/agent-runner-query-options.ts`: the `pluginPath: trustedPluginPath`
  comment.
- `apps/web-platform/test/plugin-root-anchoring.test.ts`:
  - The file docstring's "DELIBERATELY OUT OF SCOPE" block.
  - The THIRD AXIS: `RATCHET_FORMS`, `RATCHET_MIN_FILES`/`RATCHET_MIN_ROWS`, and rows R0–R6.
  - Decision 8's `settings.json` assertion (`$(git rev-parse` / `${CLAUDE_PLUGIN_ROOT:-`).
- `apps/web-platform/test/fixtures/plugin-root-skills-ratchet.tsv`: 131 rows and 230 occurrences.
  38 rows (99 occurrences) are form (a).
- `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts`: `LIST_EMISSION` and the
  docstring's "Scope (deliberate, YAGNI)" paragraph, which warns that a form without `:-` "yields
  zero matches".
- `apps/web-platform/test/safe-bash.test.ts`: the `CPR` constant and the rejection rows (traversal,
  other script).
- Test consumers that pin or simulate a migrated site:
  - `plugins/soleur/test/concurrent-ship.test.sh`: T1c *requires* the `:-` form for
    `session-state.sh`, so it goes red on migration. It is a regex (`\$\{CLAUDE_PLUGIN_ROOT:-`),
    so a literal grep does not find it.
  - `plugins/soleur/test/admin-merge-ready-wiring.test.sh`: the `REF_GATE` literal.
  - `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`: scenario 10 simulates
    the SKILL.md hop and already `export`s the variable.
  - `plugins/soleur/test/preflight-discoverability-test.test.ts`: `toMatch(/FORM_A_AWK="\$\(git rev-parse …`
    pins Pattern C, and two rows read `^PROBE_GATE=`.
  - `scripts/battery-tag-authorship.test.sh`: its path extractor has an optional
    `${CLAUDE_PLUGIN_ROOT:-…}/` prefix group. It already under-approximates and needs no change.
  - `.claude/hooks/browser-snapshot-credential-guard.test.sh`: the `RED=` fixture. It is a
    rejection needle, so it stays.
- Test files that mention `CLAUDE_PLUGIN_ROOT` form the **regression sweep**. There are 26 in
  total; the full list is in the Test Scenarios section.
- `.claude/settings.json` `permissions.allow`: no entry matches `worktree-manager.sh` or the
  anchor. Unaffected. Decision 8 already removed the dead entry.

### Institutional learnings applied

- `2026-07-08-adr093-anchored-literal-migration-needs-parity-test-and-grep-F.md`: acceptance greps
  on `${…}` literals use `grep -F`. A BRE `grep -c '${CLAUDE_PLUGIN_ROOT:-…}'` silently returns 0.
- `2026-06-02-test-class-assertion-sweep-must-use-bare-token-not-bracketed.md`: the consumer sweep
  keys on the bare substring `CLAUDE_PLUGIN_ROOT`, which is how `concurrent-ship.test.sh` T1c's
  escaped regex was found. Afterwards, run the **whole** sweep list, not hand-picked files.
- `2026-07-08-plugin-root-migration-ac-grep-scope-and-anchor-preservation.md`: superseded by
  ADR-179. The canonical form has no fallback arm.
- `2026-02-22-bundle-external-plugin-into-soleur.md`: the loader expands the token "in all
  command/skill text". This is the prior finding that A10 later proved.
- `2026-05-05-cc-permissions-bash-allowlist-hardening.md`: exact-match carve-outs, with
  `PATH_TRAVERSAL_DENYLIST` staying ahead of the pattern loop.
- `2026-03-27-skill-description-budget-headroom.md`: not triggered, because no `description:` is
  edited. The body-byte change is net negative, since `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}`
  (38 chars) becomes `"${CLAUDE_PLUGIN_ROOT}"` (22 chars).

### Carry-in for the compound step (notes only, not acted on here)

After the review of PR #8686, CodeQL raised **three high-severity alerts** that its 12-agent review
panel had missed. One was a regex **built from data** that escaped only `-` and `:`. Another was a
**single-pass `<!--` strip** that left residue. Both were fixed in `1b240b96df`. This plan builds
regexes from data in two places: the coupling test's substituted-literal rendering and the
ratchet's form list. It therefore prescribes full metacharacter escaping (`escapeRe` already exists
in `plugin-root-anchoring.test.ts`) or literal `String.prototype.includes`/`Set.has`, never a
hand-rolled partial escape. It also prescribes no single-pass comment stripping. Feed this to
`soleur:compound` as a "review panels miss what CodeQL catches: data-built regex escaping" learning
candidate.

### Skill description budget (Phase 1.8)

No `description:` edit is a candidate, either in Phase 1 or in the final file list. Skipped.

### Loader reach — the Read surface (found at domain review, corrected at plan review)

The loader substitutes the token in text it **delivers**: a `SKILL.md` body, a command body, and
skill args. A `references/*.md` file, or any other non-`SKILL.md` doc such as
`flag-bootstrap/SETUP.md`, is opened with the **Read tool**, which returns the raw bytes. A bare
token in such a file therefore reaches bash **unsubstituted**. In a plain Claude Code session the
variable is unset, so the token expands to `/skills/...` or `/scripts/...`, and the command fails
closed with `No such file or directory`.

There are five such docs, measured:

| Doc | Executable bare-token sites | How it is reached today |
| --- | --- | --- |
| `brainstorm/references/brainstorm-brand-workshop.md` | 3 (`:-` today) | `brainstorm/SKILL.md` "**Read `plugins/soleur/skills/brainstorm/references/…` now**", which is **CWD-relative** |
| `brainstorm/references/brainstorm-validation-workshop.md` | 2 (`:-` today) | Same shape as the brand workshop: CWD-relative |
| `ship/references/settle-then-admin-merge.md` | 3 (`:-` today), plus the **only gate before `--admin`** | Relative markdown links (`./references/…`, `../ship/references/…`) from `ship`, `merge-pr`, `drain-prs` and `one-shot`, plus the `[ship.phase7.hatch_check]` echo, which prints a substituted `${CLAUDE_PLUGIN_ROOT}/skills/ship/references/…` |
| `review/references/review-e2e-testing.md` | 1 bare (#7482), a secret gate whose blocks are also handed to subagents | `review/SKILL.md` "**Read `plugins/soleur/skills/review/references/…` now**": CWD-relative |
| `flag-bootstrap/SETUP.md` | 3 bare (operator runbook) | Named in prose by `flag-delete` and `flag-list` |

Two findings from plan review reshaped the design.

1. **The CWD-relative pointers defeat the point.** This came from DHH P0, arch P1-2 and spec-flow.
   `/review` runs after `gh pr checkout`, so `Read plugins/soleur/skills/review/references/…`
   loads the **contributor's** copy of the doc. That means a notice inside the doc only hardens
   text chosen by the attacker. The three CWD-relative pointers therefore become
   `${CLAUDE_PLUGIN_ROOT}/skills/<s>/references/<f>.md`. The loader substitutes that, so the doc
   is read from the installed payload. The same change also **delivers the root**: the agent
   knows the absolute path it just read, and the root is that path minus
   `/skills/<s>/references/<f>.md`. This is the markdown twin of ADR-179 A17's `BASH_SOURCE` rule.
   It replaces the draft's parent-SKILL.md `export` clause, which relied on a value the agent
   copied by hand. Compaction could lose that value, and it did not reach a Monitor task or a
   subagent (spec-flow P1-2/-6/-10).

   The **relative markdown links** (`](./references/…)`, `](../ship/references/…)`) were first
   left as they were, on the assumption that they resolve against the skill's
   `Base directory for this skill:`. The deepen security review showed that the assumption was
   untestable as drafted (AC12 made the installed copy and the CWD copy the same file). `drain-prs`
   runs on contributor PRs, so the links to `settle-then-admin-merge.md` are **anchored too**
   (Phase 6), and AC12 now relocates the plugin away from the CWD.
   The ~124 other CWD-relative `Read plugins/soleur/…` pointers are **#8729**.
2. **Each doc's blocks must not depend on shell state.** Every Bash call, every Monitor command and
   every subagent gets a fresh shell. So each executable block in these docs **starts** with
   the sentinel line `export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"`, and a
   notice tells the agent how to fill it in. The deepen pass replaced an earlier `<…>` placeholder,
   which is a bash syntax error when left unreplaced. The sentinel is absolute and cannot exist,
   so an unreplaced line fails closed with a legible message (Phase 6).

   The admin-merge blocks also start with a presence check:
   `[[ -r "${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh" ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved"; exit 5; }`.
   `5` is unused by `admin-merge-ready.sh`, whose header maps exits 0–4. So a missing root gets
   its own named error state instead of the generic "anything else" arm (spec-flow P1-3).

### Hosted-surface substitution — settled by code inspection, hedged in the carve-out

`apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs` (0.3.197) turns
`plugins:[{type:"local", path}]` into `--plugin-dir <path>`. That is the mechanism A10 measured.
Kieran re-verified it. The hosted agent therefore most likely receives skill text already
substituted with `getPluginPath()`, which is `/app/shared/plugins/soleur` in production, the value
`.env.example` also carries. This is **not measured on the server**. So the carve-out admits both
renderings, and each member is reachable under one branch.

This is consistent with Decision 8, which removed an allow entry that was **dead by
construction**. Neither member here is dead by construction; one of them is dead by an unmeasured
fact. The cost is honest. There is one cross-module import (`SOLEUR_PLUGIN_PATH_DEFAULT`),
positive test rows for both members, and a second coupling assertion. "Costs nothing" was wrong
and has been struck.

### Other consumers (from plan review)

- **`schedule/SKILL.md`'s one-time-mode `SS_LIB=…` is a TEMPLATE**, not an agent instruction
  (Kieran P0-2). It sits inside the `prompt: |` block that the skill writes into the customer's
  committed `.github/workflows/*.yml`.
  - A bare token there would be substituted at authoring time with the **operator's local
    install path**. That path would leak into the customer repo, and it does not exist on the
    runner.
  - Keeping `:-` is not an option: Guard 1 has no allowlist, and the `:-` form is the vector.
  - **Disposition:** the generated prompt drops the `merge-main` lock and calls
    `gh pr merge --auto` directly. That is the template's existing degrade-open `else` arm.
  - Why this is safe: `session-state.sh`'s `with_lock` is a **machine-local** `flock`, and a
    scheduled fire runs alone on an ephemeral GitHub runner. The lock serialises nothing there.
  - `concurrent-ship.test.sh` T1 ("4 skill files wrap `gh pr merge --auto` with
    `acquire_lock merge-main`") and T1c both list `schedule/SKILL.md`. Both drop it, with that
    rationale in a comment. T1 also gains a row asserting that the schedule **template** carries
    no `CLAUDE_PLUGIN_ROOT` token at all.
- **The cron-bug-fixer surface** is neutral and recorded (arch P2-1, Kieran P2-10).
  - `cron-bug-fixer.ts` runs `claude --plugin-dir plugins/soleur` (relative).
  - The hook allowlist entry is `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
    (`_cron-claude-eval-substrate.ts`), matched by prefix in `cron-bash-allowlist-hook.mjs`.
  - `fix-issue/SKILL.md`'s site is denied today (the hook rejects `${…}`). It stays denied after
    this change: the substituted path is absolute and quoted, and it does not match the relative
    prefix.
  - The behaviour does not change, and the reason for the denial does. There is no edit here;
    the entry is named in A18 so that the next change to that allowlist sees it.
- **The five prose mentions of `plugins/soleur/scripts/admin-merge-ready.sh`** (spec-flow P0) name
  the gate by a CWD-relative path, right beside the blocks that now fail closed. They are in
  `ship`, `merge-pr`, `drain-prs`, `one-shot` and `schedule` (`SKILL.md`, loader-delivered). An
  agent "repairing" a `No such file` reaches for exactly that string, and in a contributor
  worktree it runs the contributor's gate. Four of them become
  `"${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh"`. The `schedule` one takes plain prose
  ("the installed Soleur plugin's `scripts/admin-merge-ready.sh`"), because an authoring agent may
  copy that sentence into a generated workflow (security review P2).
- **Harness residuals, stated rather than claimed equal** (spec-flow P2-12, arch (e)):
  - **Grok Build.** `one-shot` Reads nested `SKILL.md` files from disk, so on Grok those bare
    tokens are unsubstituted. The monorepo worktree, lease and `cleanup-merged` steps move from
    working (through the `:-./plugins/soleur` arm) to fail-closed. On a **customer** repo the old
    arm executed the customer's file. Fail-closed is the correct trade, and it is a real
    availability regression **in the monorepo on Grok**, so it is recorded in A20.
    **#8730** carries the root-setting guidance for the generated `grok-harness-invoke` block.
    That is a many-file change, which is why it gets its own issue.
  - **Devin cloud:** exec shells do not export the variable, so every exec shell needs the
    export. `devin/INSTRUCTIONS.md` already says this. The cost is stated in A20.

## Research Reconciliation — Spec vs. Codebase

| Issue / spec claim | Reality on `origin/main` | Plan response |
| --- | --- | --- |
| The governing ADR is ADR-177 | ADR-177 is the test-runner taxonomy. The right one is **ADR-179**, renumbered in `98ad03aa8`. | Cite and amend ADR-179. The PR body flags that the issue title's ordinal is stale. |
| "~100 `:-` sites vs 6 bare" | 102 `:-` occurrences in 31 `.md` files, plus 7 in `.sh`, and 302 bare lines. #7443, #7482, #8070 and #8391 moved sites. | Migrate the 97 agent-executable `.md` occurrences, handle the 1 template specially, and reword the 4 prose ones. Leave the `.sh` files. |
| Prerequisite: the bare-token-in-a-`bash`-fence arm is UNRESOLVED | **Resolved.** A10 covers the skill surface (decoy-controlled) and #8391 Arm 5 covers commands on both harnesses. | No new measurement. The ADR amendment records the closure. |
| Process the option-(d) `$(git rev-parse)` sites first | #7482 migrated the §R5 option-(d) sites. What is still live and severity-first is **Pattern C** (`preflight/SKILL.md` `FORM_A_AWK`/`PROBE_GATE`). | Phase 2 is Pattern C. The option-(d) `FORBIDDEN` needles stay. |
| `safe-bash.ts`: change the constant to the bare literal | A bare-only literal is probably dead on the server, because the SDK uses `--plugin-dir`. | Keep exact equality. The set becomes 4 exact literals: {bare, substituted-deployed} × {`list`, `ls`}. The residual is avoided. |
| Update `LIST_EMISSION` to `\$\{CLAUDE_PLUGIN_ROOT\}` | Right. Kieran also found it misses `"${…}"/…` and double-space shapes. | Make the regex modifier-agnostic and quote-tolerant, and pin the exact count at 4. |
| Widen the #7442 guard to `skills/` | #8570 added a skills ratchet. `readsRootUnsafely` flags exactly the 31 `:-` files and nothing else (Kieran confirmed). | Guard 1 widens the P1b scan to all tracked payload markdown. Form (a) leaves the ratchet. |
| All 108 skills sites are one class | 97 agent-executable, 1 **template** (`schedule`), 4 prose, 7 `.sh`. The Read-surface docs are not loader-delivered. | Each class is handled on its own (Phases 3–5). |
| Decision 2: every migrated site carries the identity preflight | A11 made it defence-in-depth, and decision 5 already makes the unset case fail closed. | Not added at non-gate sites. See A18 for the Tier-1 gates' exit-127 handling. |

## Implementation Phases

Guards go RED first (`cq-write-failing-tests-before`). Then come the migration phases, ordered by
**severity** and with **prose before the scripted replace** (Kieran P2-9). Everything ships in one
PR.

### Phase 0 — Preconditions (re-derive before touching anything)

```bash
git fetch origin main
git grep -o -F '${CLAUDE_PLUGIN_ROOT:-' origin/main -- 'plugins/soleur/skills/**/*.md' | wc -l       # expect 102
git grep -l -F '${CLAUDE_PLUGIN_ROOT:-' origin/main -- 'plugins/soleur/skills/**/*.md' | wc -l       # expect 31
git grep -n -E 'rev-parse --show-toplevel\)"?/plugins/soleur/' origin/main -- 'plugins/soleur/**/*.md'  # expect 2 (preflight)
grep -v '^#' apps/web-platform/test/fixtures/plugin-root-skills-ratchet.tsv | wc -l                   # expect 131
bash scripts/battery-tag-authorship.test.sh 2>&1 | grep -E 'closure reached a FIXPOINT'                 # record the member count
```

If a count differs, re-derive the site list. Never edit toward the plan's number. Use `grep -F` or
fixed-string `git grep` for every `${…}` literal: a BRE `${…}` silently matches nothing.

### Phase 1 — Guards, RED first (matrices in `## Guard Contract`)

All the guards below live in `apps/web-platform/test/plugin-root-anchoring.test.ts` unless noted.
Every floor or identity failure message prints the measured value plus a one-line fix hint (CTO
devex).

1. **Guard 1.** Scan every **tracked** `plugins/soleur/**/*.md` with `git ls-files --full-name`
   from the repo root, never a disk walk. The expected result is zero, with no exemptions. Two
   predicates run over the one population:
   - **(i) the existing `readsRootUnsafely`**, through the existing `scanForUnsafeRootReads`.
     Reuse both, and `P1B_FIXTURES`, by reference; do not copy them. It stays shared with the
     command-axis P1b.
   - **(ii) a new `plantsRootUnsafely`** (deepen-plan, from the security review). These are
     literal regexes, and each is measured at **0** hits on the post-migration tree:
     - `/\bCLAUDE_PLUGIN_ROOT=(?!<|"\/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__")/` catches
       `export CLAUDE_PLUGIN_ROOT=./plugins/soleur`, `$PWD/…`, `$(git rev-parse …)/…` and the
       conditional-fallback assignment. Only two assignment forms are allowed. One is a `=<…>`
       placeholder echo, the shape of today's `export CLAUDE_PLUGIN_ROOT=<the installed soleur
       plugin root>` messages. The other is the Read-surface sentinel from Phase 6.
     - `/\$\{[A-Za-z_]\w*:?[-=?+][^}]*plugins\/soleur/` catches a default arm of **any**
       variable pointing at `plugins/soleur` (`${R:-./plugins/soleur}`,
       `${SOLEUR_ROOT:-…}`, typo'd names). Measured: 100 hits today, all of them current `:-`
       sites.
     - `/\benv\b[^\n]*\|[^\n]*CLAUDE_PLUGIN_ROOT/` catches reading the root out of `env`
       without the token.
     - Its own `PLANT_FIXTURES` control covers all security-review bypass forms (must-flag), plus
       the two allowed assignment forms and `ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token`
       (must-pass).
   - **Live-scan dispatch control** (test-design P0-1). The scan wrapper takes its population as a
     parameter. One row runs the **live** wrapper over the real population plus one synthetic
     planted source, and asserts the result equals exactly `[<synthetic name>]`. A wrapper that
     returns `[]` goes RED, and so does one that ignores the population.
   - **Population floor, independent of the enumerator** (test-design P1-6): 575 files measured
     today, so `>= 550`. Do not compare the population with a second `git ls-files` call; that is
     circular.
   - One aggregated `check(violations)` per predicate, not one per file. That keeps the
     assertion-count floor independent of the population size.
   - The population includes about 202 `plugins/soleur/test/**/*.md` fixtures and 39 files under
     `docs/`. That is accepted, and the failure message says so: *"write 'the `:-` default arm' in
     prose; never spell the `${…:-` form, or assign `CLAUDE_PLUGIN_ROOT=`, in payload markdown"*.
   - Expected RED today: (i) **31 files**, and (ii) the 31 files with a `:-` default arm, all
     through the any-variable-default regex.
2. **Guard 2.** Over the same population, forbid a dynamic prefix into the payload **or** out of
   it. There are three module-level literal regexes, never built from data. Each was measured with
   node against today's tree and against the security review's bypass forms:
   - **2a** `/(\)|\}|\$[A-Za-z_]\w*)["']*\/+(?:\.\/+)*plugins\/soleur\b/`: Pattern C, the
     double prefix, and variable or `$(pwd)`/`${PWD}` indirection, including `//`, `/./` and
     mixed quotes. **3 hits today** (`sync.md:180`, `preflight:809`, `preflight:1011`).
   - **2b** ``/show-toplevel[)`"']*\/+(?:\.\/+)*plugins\/soleur\b/``: the backtick
     `` `git rev-parse --show-toplevel`/plugins/soleur/ `` form. A generic backtick prefix in 2a
     false-flagged `/plugins/soleur/NOTICE` code spans in `frontend-anti-slop` and `gdpr-gate`.
     2 hits today.
   - **2c** ``/\$\{CLAUDE_PLUGIN_ROOT\}["']*\/[^\s"'`]*\.\.(\/|"|'|\s|$)/``: a payload
     escape anywhere in the path (`/..`, `/./../`, `/skills/../../`, end of line). 0 hits today.
   - `DYNPREFIX_FIXTURES` drives the same function the live scan calls, with a
     `>= 10`-fixture floor that mirrors P1B's. It holds all 7 measured bypass forms (all caught),
     plus must-pass forms. The live-scan dispatch control is the same shape as Guard 1's.
3. **Guard 4. Read-surface docs.** A doc qualifies if it is tracked, sits under
   `plugins/soleur/skills/**/*.md`, has a basename `!== "SKILL.md"` and contains
   `${CLAUDE_PLUGIN_ROOT}/`. The checks use `String.prototype.includes` and one literal
   fence-opener regex.
   - **(a)** Each doc contains `**Plugin root in this file:**` **and** the closed-rule sentence
     `The root is ONLY the prefix of the path you read this file from`.
   - **(b)** No tracked payload markdown names a qualifying doc by its CWD-relative repo path
     (`plugins/soleur/skills/<rel>`) **or** by a relative markdown link (`](./…/<basename>)` or
     `](../…/<basename>)`). Pointers must be loader-anchored (security review P1).
   - **(c)** Every ```` ```bash ```` / ```` ```sh ```` fence in a qualifying doc starts with the
     sentinel `export` line from Phase 6 (test-design P1-7).
   - **(d)** The qualifying set equals, **by name**, the five docs in Research Insights. Adding or
     losing one goes RED with the measured set printed.
   - Expected RED today:
     - (a) on 2 docs: `review-e2e-testing.md` and `flag-bootstrap/SETUP.md`. The three `:-` docs
       join once migrated.
     - (b) on 9 lines: the brainstorm and review CWD-relative pointers ×3, `ship` relative links
       ×3, and `merge-pr`, `drain-prs` and `one-shot` ×1 each.
     - (c) on 2 docs.
     - (d) on the set.
   - A P2 from the security review: text docs outside `*.md` under `skills/` exist today only as
     `eval-harness/prompts/*.txt`, which are eval fixtures and never agent-Read runbooks. Record that
     in the guard docstring as the population boundary.
4. **Ratchet re-scope, in the order that works** (Kieran P1-3; the writer refuses below
   `RATCHET_MIN_ROWS`):
   - (i) remove form `(a)` from `RATCHET_FORMS` and `"a"` from R5, and update R5's
     measured-forms comment;
   - (ii) **lower `RATCHET_MIN_ROWS` 120 → 85 first**;
   - (iii) change `RATCHET_HEADER`, the THIRD AXIS comment, R2's failure message (it says
     "tracked in #7453") and the describe title. They now point forms (b)/(d)/(e) to **#6222** and
     the Read class to **#8729**;
   - (iv) regenerate the TSV with the guarded writer **as the last markdown-touching step** (after
     Phases 2–5).
5. Raise each describe's anti-vacuity assertion floor **in the same edit** that adds assertions.
6. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`.
   Expect Guards 1, 2 and 4 RED with exactly the enumerated counts. Save the output as
   `specs/feat-one-shot-7453-bare-plugin-root-anchor/phase1-red-run.txt`.

### Phase 2 — Severity-first: Pattern C in `preflight/SKILL.md`

- `FORM_A_AWK="${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/parse-form-a.awk"` and
  `PROBE_GATE="${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/probe-verb-gate.sh"`.
- The `test -r … || { echo "FAIL: …"; exit 1; }` lines are unchanged. They are already
  fail-closed.
- Replace the "RATIONALE CORRECTED (#7450)" fence comment with 2–4 lines saying the operands use
  the loader token (ADR-179, #7453). It must not spell `${…:-`.
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: **invert, do not delete**, the test
  "Step 10.4 calls the extracted awk via git rev-parse, not CLAUDE_PLUGIN_ROOT". It must assert the
  bare-token `FORM_A_AWK=` and `PROBE_GATE=` lines are present, and that Check 10 contains no
  `git rev-parse --show-toplevel` code root. The F1c/F1d rows (`^PROBE_GATE=`) are unaffected.
- Add a row to the same suite, as a committed replacement for the old behavioural scenario 3. It
  extracts the `FORM_A_AWK` block and runs it with `CLAUDE_PLUGIN_ROOT` **unset**, from a scratch
  repo whose `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` is a decoy that writes a
  ledger file. The row runs under `env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT`, with a
  pre-created, empty `mktemp` ledger. It asserts two things:
  - the block prints `FAIL: Check 10 parser missing at /skills/`;
  - the ledger file is still empty. Read the file itself.

  Pair it with a **twin positive control** (test-design P0-2): the same fixture running the
  pre-migration `$(git rev-parse --show-toplevel)` form of the block must write the decoy ledger.
  That proves the decoy can execute.

### Phase 3 — Prose that names the rejected or wrong form (moved ahead of the scripted replace)

- `community/SKILL.md`: change "not `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}`" to "not a `:-` default
  arm".
- `work/SKILL.md`: the #7442 "Why" bullet. Keep the fact and drop the literal.
- `ship/SKILL.md`: the A13 history comment inside the PIR fence.
- `preflight/SKILL.md`: the rationale comment (already covered in Phase 2).
- `commands/sync.md`: the double-prefix example `"${CLAUDE_PLUGIN_ROOT}/plugins/soleur/scripts/foo.ts"`.
  Reword it so neither guard matches, for example "the root plus a second `plugins/soleur/`
  segment". Then re-run the command-surface describe and `tests/commands/test-sync-*.sh`.
- Four of the five `plugins/soleur/scripts/admin-merge-ready.sh` prose mentions become
  `"${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh"`: in `ship`, `merge-pr`, `drain-prs` and
  `one-shot`, all loader-delivered `SKILL.md` files.
- The **`schedule/SKILL.md` mention (≈:216) takes prose instead**: "the installed Soleur plugin's
  `scripts/admin-merge-ready.sh`". No token and no repo path, because an authoring agent may copy
  that sentence into a generated workflow, and a token there would bake the operator's local
  install path into the customer's YAML (security review P2). That is the same leak Phase 5
  avoids for `SS_LIB`.
- Run `admin-merge-ready-wiring.test.sh` after this change: its W-rows read `ship/SKILL.md` and
  `schedule/SKILL.md` prose.

### Phase 4 — Executable `:-` sites in loader-delivered `SKILL.md` (27 files)

- Replace `${CLAUDE_PLUGIN_ROOT:-<default>}` with `${CLAUDE_PLUGIN_ROOT}`.
- **Quote** the operand. The resulting forms are:
  - `bash "${CLAUDE_PLUGIN_ROOT}/skills/x/scripts/y.sh" args`;
  - for direct exec, `"${CLAUDE_PLUGIN_ROOT}/…/worktree-manager.sh" feature <name>`;
  - for an assignment, `SS_LIB="${CLAUDE_PLUGIN_ROOT}/scripts/lib/session-state.sh"`.
- **Never rewrite the tail.** Every target exists, measured at 25/25.
- The replacement script is fixed-string only. It covers the four defaults (`./plugins/soleur`,
  `plugins/soleur`, `../../plugins/soleur`, and the A13 `.`, which is prose and already handled
  in Phase 3).
- It **excludes** `schedule/SKILL.md`'s template line. Phase 5 handles that one.
- Read each file's diff before committing it.
- Order the commits by tier:
  - **Tier 1 (gates and destructive sites):**
    - `ship`: `battery-owed.sh`, `auto-close-scan.sh` ×3, the lease, `cleanup-merged`;
    - `skill-security-scan` ×2 and `skill-creator`'s `run-scan.sh`. **Add one caller rule
      line.** The deepen verification found that no caller handles a crashed or 127 `run-scan.sh`;
      callers branch only on the printed verdict string. The rule to add: *"no
      `LOW-RISK`/`REVIEW`/`HIGH-RISK` verdict line (including `No such file`) means treat the
      skill as **REVIEW**, never LOW-RISK"*.
    - `review`: `emit-review-trailer.sh`. **Add one caller rule line**, for the same reason: *"a
      non-zero exit from the trailer script means the review is **not** attested; do not report
      success"*.
    - `merge-pr`;
    - `work`, `one-shot`, `git-worktree` (22 `worktree-manager.sh` + 1 lease), `drain-prs`,
      `fix-issue`, `product-roadmap`.
  - **Tier 2:**
    - `archive-kb`, `brainstorm`, `compound`, `compound-capture`;
    - `constraint-scaffold`, `deploy`, `drain-labeled-backlog`, `feature-video`;
    - `harvest-debt`, `kb-search`, `model-launch-review`;
    - `pencil-setup`, `plan`, `seo-aeo`.
- `git-worktree/SKILL.md`'s four `list` sites take **exactly** the form
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" list`.

### Phase 5 — The `schedule` template

- In the one-time-mode `prompt: |` block, remove the `SS_LIB=… with_lock merge-main …` branch.
  The generated prompt calls `gh pr merge --auto` directly, keeping the existing `MERGE_ERR`
  capture and the "degrades OPEN" explanation. Rewrite that explanation to give the real reason:
  on an ephemeral runner the machine-local lock serialises nothing.
- `plugins/soleur/test/concurrent-ship.test.sh`:
  - T1 and T1c drop `schedule/SKILL.md`, with the rationale in a comment.
  - T1c changes its presence regex to `\$\{CLAUDE_PLUGIN_ROOT\}/scripts/lib/session-state\.sh` and
    gains an **absence** row for `\$\{CLAUDE_PLUGIN_ROOT:-[^}]*\}/scripts/lib/session-state\.sh`
    (presence first, then absence).
  - Add a row asserting that `schedule/SKILL.md`'s `prompt: |` block contains no
    `CLAUDE_PLUGIN_ROOT` token. Extract the block with the file's existing section helper, or a
    flag-based awk, never an `awk '/a/,/b/'` range (sharp edge, #3809).
  - **Before** that absence check, assert the extracted block is non-empty and contains both
    `gh pr merge --auto` and `MERGE_ERR` (test-design P1-4). Otherwise an extractor that returns
    nothing passes the absence check vacuously.
- Run `plugins/soleur/test/schedule-skill-once.test.sh` and `scripts/lint-scheduled-show-full-output.sh`.

### Phase 6 — The Read-surface docs (P7)

For each of the five docs:

- **Migrate** the 8 `:-` sites (in the brainstorm workshops and the admin-merge doc) to the bare
  token.
- **Every executable block starts with the sentinel line**
  `export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"`. The deepen pass changed this,
  and the reason matters.
  - The draft's `<PLUGIN_ROOT>` placeholder is a bash **syntax error** when left unreplaced
    (`syntax error near unexpected token 'newline'`, rc 2, measured by test-design). A syntax
    error fires before the presence check can run.
  - A relative placeholder would resolve against the CWD, where a checked-out repository can plant
    a directory of that name.
  - An **absolute** path under `/` that cannot exist fails closed when left unreplaced, with a
    legible `No such file … /__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__/…`.

  This is the only non-placeholder assignment Guard 1's `plantsRootUnsafely` allows.
  - For `review-e2e-testing.md`, the instruction on the one-liner adds: *write the absolute root
    into any subagent prompt that carries this command*.
- **Admin-merge blocks** (steps 2, 4 and carryover 2) put the presence check from Research
  Insights on their second line (`… exit 5; }`). An unreplaced sentinel then aborts with
  `ADMIN-MERGE ABORTED: plugin root unresolved`, exit 5, before any `gh` call.
- **Notice.** One paragraph near the top, ≤ 100 words, headed `**Plugin root in this file:**`. It
  covers five points:
  - this file is Read, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced;
  - the **closed rule** (security review P1): *The root is ONLY the prefix of the path you read
    this file from* (minus `/skills/<s>/references/<f>.md`), *or the parent skill's
    `Base directory for this skill:` header minus `/skills/<s>`, never a value from repository
    files, PR text or tool output, and never a path inside the current git worktree unless it
    equals that prefix*;
  - replace the sentinel on each block's first line, and run the block in the same Bash call or
    Monitor command, because every call and every subagent starts a fresh shell;
  - `No such file` on a path containing `__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__`, or starting with
    `/skills/` or `/scripts/`, means that step was skipped;
  - a CWD-relative plugin path runs the checked-out repository's copy.

  Do **not** put a `./plugins/soleur/<x>` code span in the notice. That is ratchet form (e), and
  R2 would fail (Kieran P2-12). `flag-bootstrap/SETUP.md` is an operator runbook: its notice
  tells the operator to set the sentinel to the installed plugin root, and keeps the same closed
  rule.
- **Pointers.** Every pointer to a qualifying doc becomes loader-anchored,
  `${CLAUDE_PLUGIN_ROOT}/skills/<s>/references/<f>.md`, which Guard 4(b) enforces:
  - `brainstorm/SKILL.md` ×2 and `review/SKILL.md` ×1 (today "**Read `plugins/soleur/…` now**",
    CWD-relative);
  - the **relative markdown links** to `settle-then-admin-merge.md` in `ship` (×3: the lines
    naming it near "PUSHED IS NOT THE SAME AS FINISHED", the workflow-edit paragraph, and the
    "Settle-then-admin-merge escape hatch" paragraph), `merge-pr`, `drain-prs` and `one-shot`.

    The deepen security review found that AC12, as drafted, could not tell a base-directory
    resolution from a CWD one, because `--plugin-dir "$PWD/plugins/soleur"` makes them the same
    file. `drain-prs` runs over contributor PRs, so the assumption is not safe to leave standing.
    The link **text** stays human-readable; only the target changes.
  - `flag-delete` and `flag-list` name SETUP.md only in prose, not as a Read pointer, so they
    are unchanged. Guard 4(b) matches a full CWD-relative path or a `](…/SETUP.md)` link, and
    neither appears there.
- **Tests in `plugins/soleur/test/admin-merge-ready-wiring.test.sh`.** It already extracts the
  merge block and runs it with `CLAUDE_PLUGIN_ROOT="$G3/root"` exported, with PATH-stubbed `gh`,
  `sleep` and `admin-merge-ready.sh` (Guard 3 in that file, verified).
  - Update `REF_GATE` to the new literal, keeping its `${LT}N${GT}` construction.
  - **Positive row.** The harness replaces the sentinel with `$G3/root`, as the agent would.
    Assert two things: the stubbed `admin-merge-ready.sh` ran (its ledger is non-empty), and the
    `gh` merge ledger is non-empty. The second assertion is what proves the fake `gh` is actually
    on PATH (test-design P0-2).
  - **Unreplaced-sentinel row** (test-design P0-3). Run the block **as shipped**, sentinel
    included, under `env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT`. Assert all three:
    - the exit code is `5`;
    - the output contains `ADMIN-MERGE ABORTED: plugin root unresolved`;
    - the pre-created, **empty** `mktemp` merge-ledger **file** is still empty. Read the file
      directly, never through `$(…)`: that is the #8391 R6/R7 lesson.
  - **Twin positive control for the decoy.** The same fixture, with a planted
    `./plugins/soleur/scripts/admin-merge-ready.sh` decoy that writes its own ledger, runs a
    pre-migration copy of the block. The decoy ledger must be **present**. This proves the decoy
    can run at all, so the shipped block leaving it empty means something.
- **Alternative not taken: moving the blocks into `BASH_SOURCE`-anchored wrapper scripts** (the
  advisor's option, A17). It would create a new, reusable, shipped `gh pr merge --admin` entry
  point, which is a larger trust change than this migration. The blocks already fail closed, and
  the rows above prove it. Record in A20 that a future Read-surface site whose failure is **not**
  fail-closed must take the script route.

### Phase 7 — `safe-bash.ts` carve-out (exact equality retained)

**`apps/web-platform/server/safe-bash.ts`:**

- Import `SOLEUR_PLUGIN_PATH_DEFAULT` from `./plugin-path`.
- `WORKTREE_MANAGER_DEPLOYED_FORM = 'bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh"'`
  (a TS **string**, not a template literal).
- Add `WORKTREE_MANAGER_SUBSTITUTED_FORM`, a template literal whose only interpolation is the
  constant.
- `EXACT_LITERAL_SAFE_COMMANDS` has exactly 4 members, `{bare, substituted} × {list, ls}`.
- The `:-` members are **removed**. The deploy transition window costs at most a prompt (CTO).
- Stage 0 stays `EXACT_LITERAL_SAFE_COMMANDS.has(candidate.trim())`. **No `RegExp` entry changes**
  anywhere in the file. Only comments change, including the NOTE comment that sits **inside** the
  `SAFE_BASH_PATTERNS` array (Kieran P1-7).
- Docstrings give one line per member for its branch, one line for the `SOLEUR_PLUGIN_PATH`
  repoint fail-safe, and one line on why it is a constant rather than `getPluginPath()`: the value
  must not depend on the environment at import time.

**`apps/web-platform/test/safe-bash.test.ts`:**

- Drive **both** members through `list`, `ls` and `list 2>/dev/null`.
- Negatives:
  - the **unquoted** bare form (the old "no default-value form" row, inverted with its new reason);
  - the removed `:-` members, quoted and unquoted;
  - `…/worktree-manager.sh-pwn" list` (CPO condition 5);
  - the `/tmp/x/skills/…` root;
  - `"${CLAUDE_PLUGIN_ROOT}/../evil.sh" list`;
  - `other.sh`;
  - each member followed by `cleanup-merged`, `list --json` and `list && rm -rf /`;
  - `export CLAUDE_PLUGIN_ROOT=/tmp && <bare member> list`. This one could be denied by the
    `export` segment alone, so pair it with a positive control, `pwd && <bare member> list`, which
    **is** approved (test-design P1-8).
  - `"<member> list\nid"`, an embedded newline (security review P2).
- Add an identity pin: the sorted set equals a literal 4-element array.
- Add `.source` pins for `SAFE_BASH_PATTERNS` entries touched by nothing, by exporting a test-only
  frozen snapshot, **or** drop that ambition. AC5 then checks with a `git diff` that no `RegExp`
  line changed. Pick the `git diff` form; it needs no new export.

**`apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts`:**

- ``LIST_EMISSION = /(?:bash\s+)?"?\$\{CLAUDE_PLUGIN_ROOT[^}]*\}"?\/skills\/git-worktree\/scripts\/worktree-manager\.sh"?\s+(?:list|ls)\b[^\n`|;&)>]*/g``.
  It is modifier-agnostic (`[^}]*`), accepts a closing quote before or after `/skills` and is
  whitespace-tolerant (Kieran P2-8).
- Before the membership check, normalise each emission by stripping a trailing safe redirect with
  safe-bash's `TRAILING_SAFE_REDIRECT` (`safe-bash.ts`, currently module-private: export it in
  this PR, with no change to its value). Without that step, `list 2>/dev/null` leaves a trailing
  `2` fragment, because `>` is excluded from the trailing class (test-design P2-11). Add a must-pass
  fixture for it.
- For each emission `e`, assert `SET.has(e)` **and**
  `SET.has(e.replaceAll("${CLAUDE_PLUGIN_ROOT}", SOLEUR_PLUGIN_PATH_DEFAULT))`, using a string
  replace.
- Replace the `>= 1` floor with **`toBe(4)`**, with a comment naming the four `git-worktree` list
  sites. Rewrite the "Scope (deliberate, YAGNI)" paragraph.

### Phase 8 — Remaining consumers and docstrings

- `lease-protects-active.test.sh` scenario 10: the hop becomes the bare quoted form. The separate
  `export` line stays, and so do the two comments. Add a **decoy row**: the same `list` hop runs
  from `$NONSOLEUR` with a planted `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  that writes a ledger, run under `env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT` with a
  pre-created, empty `mktemp` ledger. Assert three things: the exit is non-zero, the log contains a
  `/skills/…` `No such file`, and the ledger file is still empty. This commits behavioural scenario
  2 (spec-flow P1-8).

  Add a **twin positive control**: the pre-migration `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` hop
  from the same directory **must** write the decoy ledger (test-design P0-2). Build that string in
  the test from pieces (for example `DEF=':-'`), so the test file's `.sh` text is not mistaken for
  a payload site. Guards scan only `*.md`, but the construction also keeps a future widening
  honest.
- **Do not touch** these (reasons go in the PR body):
  - `redact-sentinel.test.sh` `FORBIDDEN=`;
  - `.claude/hooks/browser-snapshot-credential-guard.test.sh` `RED=`;
  - `go-session-gates.test.sh` H1;
  - `tests/commands/test-sync-producer-reachability.sh` T0b;
  - `operator-bootstrap/template.sh`;
  - `hooks/devin-session-start.sh`;
  - `.github/workflows/ci.yml` (a comment only; a workflow edit removes the agent admin-merge
    path).
- `scripts/battery-tag-authorship.test.sh`: no edit. Its closure member count must equal the
  Phase 0 value.
- Docstrings in `plugin-root-anchoring.test.ts`:
  - drop the two "deferred to #7453" / "Pattern C routed to #7453" bullets;
  - state the whole-payload Guard 1;
  - add a **one-screen index** at the top: guard → property → ADR-179 section → how to fix (CTO
    devex).
- Server comments only, with no logic change:
  - `agent-env.ts`: the `pluginPath` docstring and the injection comment. The injection stays
    fail-closed, as defence-in-depth for the non-substituting branch and for payload **scripts**
    that read the variable at runtime.
  - `agent-runner-query-options.ts`;
  - `scripts/plugin-root-sandbox-propagation-probe.mjs`.

  Editing `agent-env.ts` triggers the paid in-image `plugin-root-propagation` CI job. That is
  intended: it re-proves the injection.
- **`CONTRIBUTING.md`: add one line** (CTO devex P1). To run edited payload scripts end-to-end from
  a worktree, start the session with `claude --plugin-dir "$PWD/plugins/soleur"`. The absolute root
  in any emitted command shows which copy ran. Put the same sentence in the PR body.

### Phase 9 — ADR-179 amendment and ADR-093

See `## Architecture Decision (ADR/C4)`.

### Phase 10 — Ratchet regeneration and verification sweep

1. Regenerate the ratchet TSV (Phase 1 step 4(iv)).
2. Run `bash scripts/plugin-root-anchor-debt.sh`. Expect `anchor-debt-files=0`.
3. Run every suite in `## Test Scenarios`, then `python3 scripts/lint-guard-contract.py`, then
   `lint-skill-body-budget` in its CI form, `markdownlint-cli2` on every edited `.md`, and
   `lint-shell-capture-exit` on the new script.
4. Walk each AC and record the output in the spec directory.

## Files to Edit

- **Pattern C:** `plugins/soleur/skills/preflight/SKILL.md`.
- **`SKILL.md` executable sites** (Phase 4), all under `plugins/soleur/skills/<name>/SKILL.md`:
  - `archive-kb`, `brainstorm`, `compound`, `compound-capture`, `constraint-scaffold`, `deploy`;
  - `drain-labeled-backlog`, `drain-prs`, `feature-video`, `fix-issue`, `git-worktree`;
  - `harvest-debt`, `kb-search`, `merge-pr`, `model-launch-review`, `one-shot`, `pencil-setup`;
  - `plan`, `product-roadmap`, `review`, `seo-aeo`, `ship`, `skill-creator`,
    `skill-security-scan`, `work`.
- **Template:** `plugins/soleur/skills/schedule/SKILL.md`.
- **Prose:**
  - `plugins/soleur/skills/community/SKILL.md`;
  - `plugins/soleur/commands/sync.md`;
  - the `admin-merge-ready.sh` mentions in the `ship`, `merge-pr`, `drain-prs`, `one-shot` and
    `schedule` SKILL.md files.
- **Read-surface docs:**
  - `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`
  - `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md`
  - `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`
  - `plugins/soleur/skills/review/references/review-e2e-testing.md`
  - `plugins/soleur/skills/flag-bootstrap/SETUP.md`
- **Server:**
  - `apps/web-platform/server/safe-bash.ts`
  - `apps/web-platform/server/agent-env.ts` (comments)
  - `apps/web-platform/server/agent-runner-query-options.ts` (comment)
  - `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` (comment)
- **Tests:**
  - `apps/web-platform/test/plugin-root-anchoring.test.ts`
  - `apps/web-platform/test/fixtures/plugin-root-skills-ratchet.tsv`
  - `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts`
  - `apps/web-platform/test/safe-bash.test.ts`
  - `plugins/soleur/test/preflight-discoverability-test.test.ts`
  - `plugins/soleur/test/concurrent-ship.test.sh`
  - `plugins/soleur/test/admin-merge-ready-wiring.test.sh`
  - `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`
- **Docs:**
  - `CONTRIBUTING.md` (one line)
  - `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
  - `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`
    (the "Amended by" line)

## Files to Create

- `scripts/plugin-root-anchor-debt.sh`: the discoverability probe, mode 100755. It is repo-root
  monorepo tooling, not payload. DHH and code-simplicity proposed an inline command instead. That
  **cannot** work here: Check 10 rejects `|`, `;`, `&`, `<`, `>`, `$` and backticks, and it needs
  a non-empty literal `expected_output`, while an inline `git grep` prints nothing on success.
  To answer the drift concern, the script's comment names Guard 1/2 as the gate and itself as a
  signal only. Its three needles are the literal substrings Guards 1 and 2 are anchored on.
- `knowledge-base/project/specs/feat-one-shot-7453-bare-plugin-root-anchor/tasks.md`, written by
  this skill.
- During work: `phase1-red-run.txt` and the AC walk record, in the same spec directory.

## Non-Goals

- **Ratchet forms (b)/(d)/(e)** go to **#6222**. The CWD-relative `Read plugins/soleur/…` class,
  128 occurrences in 102 files, goes to **#8729**. The three pointers to Read-surface docs that
  this PR edits are the exception.
- **`.sh` files and shipped scripts** (`plugins/soleur/**/*.{sh,ts,py}`). The variable is a real
  runtime variable in a script, and the right predicate is A17's `BASH_SOURCE` rule, not
  `readsRootUnsafely`. Measured: no live instance. The only `:-` arms are `template.sh`
  (`:-/nonexistent`) and `devin-session-start.sh` (an emptiness test), and the only
  `rev-parse …)/plugins/soleur/` is `ship-battery-owed.test.sh`'s intended test root. This is the
  stated boundary in A18.
- **Grok nested-Read root delivery:** **#8730**.
- **Measuring hosted substitution:** hedged by the dual-literal carve-out (see Research Insights).
- **`.github/workflows/ci.yml`'s stale comment.**

## Open Code-Review Overlap

3 open code-review issues touch these files:

- **#3820** (safe-bash: extend the allowlist with grep/find/rg/sort/uniq). **Acknowledge.** It is a
  different concern, and this PR must not widen `SAFE_BASH_PATTERNS`.
- **#8496** (`cleanup-merged` never gh-queries `[gone]` branches that have no worktree).
  **Acknowledge.** That is script behaviour; only the invocation changes here.
- **#4133** (a schema parity test for the `## Observability` block; it names `plan/SKILL.md`).
  **Acknowledge.** Only the three anchor sites in `plan/SKILL.md` are touched.

## User-Brand Impact

**If this lands broken, the user experiences:**

- A skill step fails with `No such file or directory` on a `/skills/…` or `/scripts/…` path. This
  covers worktree creation (`soleur:brainstorm`, `soleur:work`, `soleur:one-shot`), `archive-kb`,
  `pencil-setup`, the ship/merge helpers, session leases, preflight Check 10 and the admin-merge
  hatch (`ADMIN-MERGE ABORTED: plugin root unresolved`).
- On the hosted Concierge, a new approval prompt appears in Command Center for
  `worktree-manager.sh list`.
- The **silent** variant is worse: a missed site, or a doc the loader does not rewrite, keeps its
  fail-open path with no error, so the user never learns that a checked-out tree's script ran.
  Guards 1, 2 and 4 make that variant unmergeable.

**If this leaks, the user's workflow and credentials are exposed via:** the agent executing code
from the checked-out repository instead of the installed plugin. That code runs with the user's
shell, `gh` token, Doppler access and cloud credentials. Two ways this can happen:

- a residual `:-` or git-root anchor, or a CWD-relative Read of a reference doc, after
  `gh pr checkout`;
- an agent "fixing" a fail-closed `No such file` by typing `./plugins/soleur/…`.

On the server, a mis-scoped carve-out literal could auto-approve a command outside the trusted
`/app` plugin copy.

**Brand-survival threshold:** single-user incident

This inherits ADR-179's threshold, and CPO confirmed it (approved with conditions; see
`## Domain Review`). `requires_cpo_signoff: true`. `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-179.** Add a `## Amendment — 2026-09-24 (#7453)` section, an `amended_by:` entry and
**three** items continuing the `A`-series. They were consolidated from four at plan review, and
the retelling of A10 was dropped.

- **A18: the deferral is retired and the payload markdown is zero-tolerance.**
  - Strike through the Consequences deferral bullet and add a superseded note.
  - Record the before/after: 102 → 0 `:-` and 2 → 0 Pattern C in payload markdown.
  - Close §R5 C6, item 8 (Pattern C) and A13.
  - **A12 is discharged**, because the flat zero it declined is now Guard 1.
  - **§R3 closure line:** the "missing A/B arm" #7453 named is A10 (skill surface) plus Arm 5
    (commands, both harnesses). The hosted SDK passes the plugin as `--plugin-dir` (0.3.197), and
    that is a code-inspection fact, not a measurement.
  - Record scope decisions and boundaries:
    - The identity preflight is not added at non-gate sites.
    - Each Tier-1 gate and its caller's exit-127 handling, as arch P2-4 asked:
      - `battery-owed.sh`: any exit except 42 means "owed", so it fails safe.
      - `run-scan.sh`: before this PR, no caller handled a crashed or 127 exit. Callers branched
        only on the printed verdict string (deepen verification). This PR adds the rule that a
        missing verdict line means **REVIEW**.
      - `emit-review-trailer.sh`: before this PR, no caller rule covered a non-zero exit (deepen
        verification). This PR adds the rule that a non-zero exit means **not attested**.
      - `admin-merge-ready.sh`: `exit 5` presence check, pinned by a test row.
    - Shipped scripts are out of scope, with the reason.
    - The cron-bug-fixer allowlist entry is named.
    - Trackers: #6222, #8729, #8730.
- **A19: the carve-out.**
  - `EXACT_LITERAL_SAFE_COMMANDS` = `{bare, substituted-deployed} × {list, ls}`.
  - Exact equality; no `^bash` regex; the denylist is unchanged.
  - Each member is reachable under one branch. This is consistent with Decision 8, which removed
    an entry that was dead **by construction**.
  - A `SOLEUR_PLUGIN_PATH` repoint falls back to a prompt, which is fail-safe.
  - Decision 8's pointer to #7453 is discharged. The issue's "known residual" is avoided rather
    than accepted.
- **A20: the Read surface.**
  - A non-`SKILL.md` doc is Read, not delivered, so its token is never substituted.
  - The rule has three parts: the pointer is loader-anchored; the root is derived from the
    absolute path read (the markdown twin of A17); every block starts with its own `export`
    (fresh shell per Bash call, Monitor task or subagent), under a notice with an anti-fallback
    sentence.
  - A site whose failure is not fail-closed takes the A17 script route instead.
  - The Grok nested-Read regression (monorepo only) is recorded against #8730, and the Devin
    cloud per-shell export cost is recorded too.

**ADR-093:** extend the "Amended by" line. As of 2026-09-24 (#7453) the **entire** skills surface
uses the bare anchor. Point to ADR-179 A18.

### C4 views

**No C4 impact.** All three model files were read (`model.c4`, 854 lines; `views.c4`, 106;
`spec.c4`, 54), and the architecture reviewer concurred.

- **External actors:** unchanged. The untrusted `contributor` and the connected-repo plugin copy
  (`model.c4`, "External UNTRUSTED plugin SOURCE") are already modelled. This change reduces
  reliance on them.
- **External systems:** `soleurMarketplace`, `codex`, `devin` and the Grok harness, each with an
  unchanged `-> platform.plugin` edge.
- **Containers:** `platform.plugin` is unchanged, and `safe-bash.ts` stays inside the existing
  Concierge permission component.
- **Access relationships:** unchanged. The trust anchor was already the installed payload
  (`model.c4` ~427/~530).
- No edge prose counts skill sites. The work phase still runs
  `bash plugins/soleur/test/c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and
  `c4-render.test.ts`, and records the green result.

### Sequencing

None. Everything in this PR is true on merge.

## Observability

```yaml
liveness_signal:
  what: "anchor-debt-files=<n> — tracked payload markdown files that still resolve a plugin path through a :- (or any modifier) default arm or a git-root code root; expected 0 after merge"
  cadence: "every CI run (Guards 1/2/4 in the required web-platform vitest context) and on demand via discoverability_test"
  alert_target: "red required check on the PR / on main (GitHub CI); no paging — a markdown regression cannot reach a user before it reaches a PR"
  configured_in: "apps/web-platform/test/plugin-root-anchoring.test.ts (Guards 1, 2, 4), apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts, apps/web-platform/test/safe-bash.test.ts"
error_reporting:
  destination: "CI (vitest + bash suites, required contexts); hosted surface keeps the existing pino `decision: auto-approved-safe-bash` log line and the `safe-bash-near-miss` Sentry warnSilentFallback (feature cc-permissions), both unchanged"
  fail_loud: "yes — every guard names the file and text; at runtime an unset bare root fails closed with `No such file or directory`, `FAIL: Check 10 parser missing at …`, or `ADMIN-MERGE ABORTED: plugin root unresolved` (exit 5), never a silent CWD resolution"
failure_modes:
  - mode: "a :- / modifier / git-root / root-assignment anchor re-introduced in payload markdown"
    detection: "workflow-run log (layer 6) — Guard 1 / Guard 2 red with file + matched text"
    alert_route: "required check on the PR (GitHub CI)"
  - mode: "plugin root unresolved at runtime on the customer's CLI (unset / unsubstituted token / unreplaced sentinel) — bare path fails closed"
    detection: "cli-stdout-artifact (layer 7) — `No such file or directory` on a path under /skills/, /scripts/ or /__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__/; fail-closed means no mutation happened, so there is nothing further to record"
    alert_route: "operator session stdout (layer 7); aggregate halts stay un-countable across installs — the durable-artifact gap ADR-179 already tracks at #7452"
  - mode: "Grok Build nested SKILL.md Read leaves the token unsubstituted (monorepo availability regression)"
    detection: "cli-stdout-artifact (layer 7) — `No such file` on /skills/… in a Grok one-shot nested step"
    alert_route: "#8730 (root-setting guidance for the grok-harness-invoke block)"
  - mode: "migration error — double prefix or a ${CLAUDE_PLUGIN_ROOT}/.. payload escape"
    detection: "workflow-run log (layer 6) — Guard 2 red"
    alert_route: "required check on the PR"
  - mode: "a Read-surface doc lacks the notice, or is pointed to by a CWD-relative path (loaded from the checked-out tree)"
    detection: "workflow-run log (layer 6) — Guard 4 (a)/(b)/(c)/(d) red"
    alert_route: "required check on the PR"
  - mode: "admin-merge block runs with the root unresolved"
    detection: "cli-stdout-artifact (layer 7) — in-block presence check prints ADMIN-MERGE ABORTED: plugin root unresolved, exit 5; the durable evidence is the ABSENCE of a merge (PR state stays OPEN at the head SHA, queryable via gh); pinned by the admin-merge-ready-wiring unreplaced-sentinel row (empty merge ledger)"
    alert_route: "operator session stdout (layer 7; fail-closed, no merge) + required check on the PR if the check is removed"
  - mode: "worktree-manager.sh list emission drifts from the carve-out (prompt returns in Command Center)"
    detection: "workflow-run log (layer 6) — coupling test (raw + substituted membership, exact count 4) red; at runtime pino (layer 2) → Better Stack shows the ABSENCE of a `decision: auto-approved-safe-bash` info line for the list command — absence-based, and not mirrored to Sentry (info level; SAFE_BASH_NEAR_MISS_PREFIX cannot fire on `bash …`), so CI is the load-bearing signal"
    alert_route: "required check on the PR; Better Stack log query (pino, layer 2) for the hosted runtime"
  - mode: "CLAUDE_PLUGIN_ROOT injection stops reaching sandbox bash (non-substituting branch only)"
    detection: "workflow-run log (layer 6) — existing in-image plugin-root-propagation probe (triggered by this PR's agent-env.ts edit)"
    alert_route: "CI job on the PR"
logs:
  where: "CI job logs (GitHub Actions); hosted permission decisions in Better Stack via pino"
  retention: "GitHub Actions default (90 days); Better Stack per existing plan"
discoverability_test:
  command: "bash scripts/plugin-root-anchor-debt.sh"
  expected_output: "anchor-debt-files=0"
```

`scripts/plugin-root-anchor-debt.sh`:

- It lists the tracked `plugins/soleur/**/*.md` files that match
  `-e 'CLAUDE_PLUGIN_ROOT:' -e 'CLAUDE_PLUGIN_ROOT-' -e 'show-toplevel)/plugins/soleur/'` via
  `git grep -l -F`, using repeated `-e` and no alternation.
- It **branches on the rc**. 0 or 1 is a result. Anything else prints
  `anchor-debt-files=ERROR rc=<n>` and exits 2.
- It prints `anchor-debt-files=<n>` and exits 0 only when `n` is 0.
- It resolves the repo root from its own `BASH_SOURCE`.

The inline equivalent was measured before the script existed: `anchor-debt-files=31` in 0.02 s,
with no credentials, network or SSH.

## Guard Contract

Each guard's RED rows are encoded as **in-code fixture controls**. The AC walk records one
observed-RED run per guard; there is no hand-applied row-by-row log.

### Guard 1 — Payload markdown reads and sets the plugin root only through the exact loader token

**Property.** No tracked `plugins/soleur/**/*.md` file reads the plugin root through anything
other than the exact `${CLAUDE_PLUGIN_ROOT}` token, and none sets it to anything other than a
`<…>` placeholder or the Read-surface sentinel.

- Ruled-out reads: any modifier (`:-` `:?` `:=` `-` `?` `=` `+`), the unbraced
  `$CLAUDE_PLUGIN_ROOT`, `printenv`/`env` reads, and `${!…}`.
- Ruled-out writes: a default arm of **any** variable pointing at `plugins/soleur`, and any other
  `CLAUDE_PLUGIN_ROOT=` assignment.

**Assembly.**

- **Population:** `git ls-files --full-name -- ':(glob)plugins/soleur/**/*.md'`, run from the
  repo root. This is the index, not the disk, so an untracked file cannot get in and a tracked
  file cannot slip out. A literal floor of `>= 550` sits beside it (575 measured). The floor does
  not depend on the enumerator.
- **Predicates:**
  - the existing `readsRootUnsafely()`, proven by `P1B_FIXTURES` and shared with command-axis
    P1b;
  - the new `plantsRootUnsafely()`, proven by `PLANT_FIXTURES`.
- **Scan:** one population-parameterised wrapper around both predicates. The live row calls it on
  the real population, and the dispatch-control row calls the same wrapper on the population plus
  one synthetic source.
- **Whole-file**, so no fence parser can be narrower than the property.
- Shipped `.sh/.ts/.py` files are outside the property by design (Non-Goals).

**Mutation matrix.**

| # | Edit | Expected |
| --- | --- | --- |
| M1 | Re-add `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh` to `archive-kb/SKILL.md` | RED, naming the file |
| M2 | Add `${CLAUDE_PLUGIN_ROOT-plugins/soleur}` (colon-less) inside a `~~~bash` fence in a `references/*.md` | RED |
| M3 | After a compliant first file, add `$CLAUDE_PLUGIN_ROOT/x.sh` to a **second** file outside `skills/` (`plugins/soleur/agents/…`) | RED; the population is the whole payload |
| M4 | Add `export CLAUDE_PLUGIN_ROOT="$PWD/plugins/soleur"` to a reference doc | RED (`plantsRootUnsafely`, assignment) |
| M5 | Add `bash "${SOLEUR_ROOT:-./plugins/soleur}/scripts/x.sh"` | RED (`plantsRootUnsafely`, any-variable default arm) |
| M6 | Dispatch: the wrapper returns `[]` | RED: the dispatch-control row expects exactly `[<synthetic>]` |
| M7 | Swap the enumerator to a disk walk of `skills/` | RED: the `>= 550` literal floor (skills alone is about 240) |

**Harness rows.**

- A suite edit that must go RED: change the floor's expected count without adding an assertion.
  The assertion-count floor catches it.
- Must-PASS non-canonical inputs, all `mustFlag: false` fixtures:
  - `ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token`;
  - `export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"`, the Read-surface block's
    first line;
  - `export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>`, today's echo text.

**Anchor.** A flat zero with no allowlist. Admitting a violation means editing a predicate or the
enumerator in reviewed code, never a regenerable baseline row. That is why form (a) leaves the
ratchet.

### Guard 2 — No dynamic prefix into the payload, and no escape out of it

**Property.** Two things are forbidden in tracked payload markdown:

- composing `<dynamic>/plugins/soleur/…`, where `<dynamic>` is a `$(…)`, a `${…}`, a `$VAR`, or
  a backtick `git rev-parse --show-toplevel`, with any run of quotes, `//` or `/./` in between;
- any `..` segment after `${CLAUDE_PLUGIN_ROOT}/`.

**Assembly.**

- The same population and parameterised wrapper as Guard 1.
- Three module-level **literal** regexes (2a/2b/2c in Phase 1), never built from data. Each was
  measured against the tree: 3 / 2 / 0 hits today, and 0 / 0 / 0 after migration.
- Whole-file.
- `DYNPREFIX_FIXTURES` (`>= 10`) drives the same function the scan calls.

**Mutation matrix.**

| # | Edit | Expected |
| --- | --- | --- |
| M1 | Restore `FORM_A_AWK="$(git rev-parse --show-toplevel)/plugins/soleur/skills/preflight/scripts/parse-form-a.awk"` | RED (2a and 2b) |
| M2 | `bash "${CLAUDE_PLUGIN_ROOT}/plugins/soleur/scripts/x.sh"` (double prefix) | RED (2a) |
| M3 | Indirection in a **second** file after a compliant first: `bash "$PWD"'/plugins/soleur/skills/x.sh'` | RED (2a, mixed quotes) |
| M4 | `bash "${CLAUDE_PLUGIN_ROOT}/skills/../../scripts/x.sh"` (mid-path escape) | RED (2c) |
| M5 | `` `git rev-parse --show-toplevel`/plugins/soleur/x.sh `` | RED (2b) |
| M6 | Dispatch: the wrapper returns `[]` | RED, via the dispatch-control row and the `DYNPREFIX_FIXTURES` `mustFlag: true` rows |

**Harness rows.**

- A suite edit that must go RED: flip one `mustFlag: true` fixture to `false`.
- Must-PASS non-canonical inputs:
  - `Read plugins/soleur/skills/x/SKILL.md` (not dynamic; the #8729 class);
  - `` `/plugins/soleur/skills/gdpr-gate/NOTICE` `` (a CODEOWNERS-style absolute path in a code
    span, the measured false positive that shaped 2a);
  - `"${CLAUDE_PLUGIN_ROOT}/skills/x/scripts/y.sh"`.

**Anchor.** A flat zero, with no stored value.

### Guard 4 — A Read-surface doc is loaded from the payload and carries the root-delivery notice

**Property.** A qualifying doc is a tracked non-`SKILL.md` markdown file under
`plugins/soleur/skills/` that contains `${CLAUDE_PLUGIN_ROOT}/`. Every qualifying doc:

- **(a)** contains `**Plugin root in this file:**` and
  `The root is ONLY the prefix of the path you read this file from`;
- **(b)** is never pointed at, anywhere in tracked payload markdown, by a CWD-relative path
  (`plugins/soleur/skills/<rel>`) or a relative markdown link (`](./…/<basename>)`,
  `](../…/<basename>)`);
- **(c)** has a first line in every `bash`/`sh` fence that is
  `export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"`;
- **(d)** belongs to a qualifying set that equals the five named docs.

**Assembly.**

- The population is `git ls-files` for `skills/**/*.md`, filtered on an exact, case-sensitive
  `basename !== "SKILL.md"`.
- (b)'s haystack is Guard 1's population.
- (a), (b) and (c) use `String.prototype.includes` plus one literal fence-opener regex.
- (d) compares the qualifying set with a literal 5-element array.
- Guard 4 was kept despite the DHH and code-simplicity cut, because the spec-flow and Kieran
  reviews both found `flag-bootstrap/SETUP.md` through exactly this predicate. It maps to **P7**.

**Mutation matrix.**

| # | Edit | Expected |
| --- | --- | --- |
| M1 | Delete the notice from `settle-then-admin-merge.md` | RED (a) |
| M2 | Delete only the closed-rule sentence from a **second** doc after a compliant first | RED (a), naming that doc |
| M3 | Revert `review/SKILL.md`'s pointer to `Read plugins/soleur/skills/review/references/review-e2e-testing.md` | RED (b) |
| M4 | Revert one `drain-prs` link to `](../ship/references/settle-then-admin-merge.md)` | RED (b), the relative-link arm |
| M5 | Remove the sentinel `export` from one block of `brainstorm-brand-workshop.md` | RED (c) |
| M6 | Dispatch: the filter becomes `() => false` | RED (d): the set identity is printed |

**Harness rows.**

- A suite edit that must go RED: replace the (d) identity array with the measured set minus one
  doc.
- Must-PASS inputs:
  - `likec4-reference.md`, whose token has no trailing `/`;
  - a SKILL.md that names `settle-then-admin-merge.md` only in link **text**, with an anchored
    target.

**Anchor.** Only the (d) identity array is stored. It lives in the same file as the guard, which
proves consistency, not integrity. Adding a sixth doc is a deliberate, reviewed edit.

### Guard 5 — The carve-out is exact, closed, and tracks what skills emit

**Property.**

- `EXACT_LITERAL_SAFE_COMMANDS` is exactly the 4 literals.
- Every `worktree-manager.sh list|ls` emission in skills markdown, raw and rendered through the
  loader substitution, is a member.
- Exactly 4 emissions exist.

**Assembly.**

- The set is defined once, in `safe-bash.ts`, and consumed once, at stage 0 (`.has(candidate.trim())`).
- The emissions come from the coupling test's walk, with the modifier-agnostic, quote-tolerant
  `LIST_EMISSION`.
- The rendering is `replaceAll(<literal token>, SOLEUR_PLUGIN_PATH_DEFAULT)`.
- The denylist and pattern regexes are **not** asserted byte-for-byte by any suite. AC5's
  `git diff` check is what covers them, and it runs once, at PR time (Kieran P1-7, arch P2-3).

**Mutation matrix.**

| # | Edit | Expected |
| --- | --- | --- |
| M1 | Add a fifth member (`… cleanup-merged`) | RED on the identity pin |
| M2 | Revert one list site to `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…/worktree-manager.sh list` | RED in the coupling test (extracted, non-member) **and** Guard 1 |
| M3 | Unquote the operand at a **second** list site after a compliant first | RED in the coupling test, naming it |
| M4 | Replace stage 0 with a `^bash\s+"?[^"]*worktree-manager\.sh"? (list\|ls)$` regex | RED: the `/tmp/x/…` root and `-pwn` negatives pass wrongly |
| M5 | Write `bash "${CLAUDE_PLUGIN_ROOT}"/skills/…/worktree-manager.sh list` at a list site | RED: it is extracted (quote-tolerant) and is a non-member, and the exact count stays 4 |

**Harness rows.**

- A suite edit that must go RED: compare against a copy of the set with the substituted members
  removed. A `D`-style row drives a drifted emission through the same comparator and requires a
  failure.
- A must-PASS non-canonical input: `<substituted member> list 2>/dev/null`. The redirect is
  stripped before the exact match.

**Anchor.** The identity pin and the members live in two files that one diff can edit together.
That is **consistency, not integrity**, and it is stated honestly. The integrity argument is that
every member resolves only to the deployed `/app` copy or fails closed, and a reviewer checks that
by reading four literals under `safe-bash.ts`'s CODEOWNERS.

## Risks & Sharp Edges

- **Tests that execute fence text do not get loader substitution.**
  - A suite that runs a migrated block must `export` the root on its own line. A command-prefix
    assignment expands after the line's own expansions (the scenario-10 lesson).
  - It also needs a precondition row that fails when the script did not resolve.
  - Known executors: `admin-merge-ready-wiring.test.sh`, `lease-protects-active.test.sh`,
    `ship-phase-7-poll-fixtures.test.sh` (already exports), `go-session-gates.test.sh` (simulates
    substitution) and the preflight Pattern-C row. The sweep list in `## Test Scenarios` is
    **derived**, not hand-picked (arch P2-6).
- **Dogfooding semantics.**
  - In a worktree, migrated sites run the **session-loaded** root: the main checkout or the
    marketplace cache.
  - That root can also be **stale**. This session's loaded root was the main checkout at
    `ed37571a45`, behind `origin/main`.
  - Contributors use `claude --plugin-dir "$PWD/plugins/soleur"` (Phase 8 `CONTRIBUTING.md` line).
  - A PR that changes both Form A and `parse-form-a.awk` may see a false Check 10 FAIL when it
    dogfoods preflight on itself. Verify through the suite, and never bypass.
- **An agent "repairing" a fail-closed path.** Mitigated by the notice, the anti-fallback sentence,
  the anchored `admin-merge-ready.sh` prose and the named exit-5 message.
- **Guard 1 is whole-file, so payload prose must not spell the rejected form.** The failure
  message gives the rewrite.
- **Ratchet regeneration can hide a non-(a) change.** Diff the data rows only
  (`grep -v '^#'`). Exactly the 38 form-(a) rows may disappear.
- **The markdown-link resolution assumption.** `](./references/…)` resolves against the skill base
  directory, not the working directory. AC12 exercises it on the ship hatch pointer.
- **The CodeQL carry-in.** No regex in this plan is built from data. The only bridge from data to
  a pattern is `replaceAll(<literal string>, <constant>)` plus `Set.has`/`includes`. If `new
  RegExp(site)` is ever needed, use `escapeRe` (the full metacharacter set).
- The `## User-Brand Impact` section is filled in. An empty or placeholder section would fail
  `deepen-plan` Phase 4.6.

## Acceptance Criteria

- [x] **AC1** Payload markdown carries no default-armed anchor and no Pattern C.
  - `git grep -l -F -e 'CLAUDE_PLUGIN_ROOT:' -e 'CLAUDE_PLUGIN_ROOT-' -- 'plugins/soleur/**/*.md' | wc -l`
    prints 0.
  - `git grep -l -F 'show-toplevel)/plugins/soleur/' -- 'plugins/soleur/**/*.md' | wc -l` prints
    0.
  - `bash scripts/plugin-root-anchor-debt.sh` prints `anchor-debt-files=0`.
- [x] **AC2** Every remaining non-markdown `${CLAUDE_PLUGIN_ROOT:-` under `plugins/soleur/` is a
  documented Non-Goal. `git grep -n -F '${CLAUDE_PLUGIN_ROOT:-' -- plugins/soleur ':!*.md'` lists
  lines only in:
  - `hooks/devin-session-start.sh`
  - `skills/operator-bootstrap/template.sh`
  - `skills/incident/test/redact-sentinel.test.sh`
  - `test/go-session-gates.test.sh`
  - comment or message lines in `test/concurrent-ship.test.sh` and
    `skills/git-worktree/test/lease-protects-active.test.sh`

  The AC walk classifies every listed line.
- [x] **AC3** Check 10 resolves both files via `"${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/…"`.
  `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with 0 failures,
  including the inverted test and the unset-root decoy row, which leaves the ledger file absent.
- [x] **AC3b** (one-time P3 check, replacing Guard 3) Every `${CLAUDE_PLUGIN_ROOT}/<path>` in
  `plugins/soleur/skills/**/*.md` names an existing `plugins/soleur/<path>`, and none starts with
  `plugins/`. Run it once with a Node one-liner or a shell loop over
  `git grep -ohE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]*'` that strips a trailing `.` and skips
  an empty tail and the `<name>`-placeholder tails. Record the operand count and 0 missing.
- [x] **AC4** Guards 1, 2 and 4 went RED in `phase1-red-run.txt` with the exact expected counts
  from Phase 1 step 6, and they are green after the migration. The counts are:
  - Guard 1: 31 files for (i) and 31 for (ii);
  - Guard 2: 3 + 2 + 0;
  - Guard 4: (a) 2, (b) 9, (c) 2, (d) set mismatch.

  The live-scan dispatch controls pass.
  `vitest run test/plugin-root-anchoring.test.ts` passes. One observed-RED run per guard is
  recorded.
- [x] **AC5** `safe-bash.ts`:
  - The identity pin passes.
  - `git diff origin/main -U0 -- apps/web-platform/server/safe-bash.ts | grep -E '^[-+]' | grep -E 'RegExp|DENYLIST *=|String\.raw'`
    is empty. The only permitted non-comment change besides the carve-out constants is `export`
    added to `TRAILING_SAFE_REDIRECT`'s declaration, with its value byte-identical.
  - `vitest run test/safe-bash.test.ts test/plugin-root-list-carveout-coupling.test.ts` passes,
    including every Phase 7 negative and the exact count of 4.
- [x] **AC6** The ratchet lost exactly the form-(a) data rows.
  `diff <(grep -v '^#' <old>) <(grep -v '^#' <new>)` shows only `<` lines, 38 of them, each
  containing `CLAUDE_PLUGIN_ROOT:`. `RATCHET_MIN_ROWS` is below the new count, and the docstring
  records the measurement.
- [x] **AC7** Read surface:
  - Guard 4 (a)–(d) is green. That covers the notice, the closed-rule sentence and the sentinel
    first line on every `bash`/`sh` fence, across exactly the five docs.
  - `git grep -n -F -e 'plugins/soleur/skills/brainstorm/references/' -e 'plugins/soleur/skills/review/references/review-e2e' -e '](../ship/references/settle-then-admin-merge.md)' -e '](./references/settle-then-admin-merge.md)' -- 'plugins/soleur/**/*.md'`
    is empty.
  - No added line introduces a CWD-relative plugin path:
    `git diff origin/main -U0 -- plugins/soleur | grep -E '^\+' | grep -F './plugins/soleur'`
    is empty. The notice avoids that spelling by design.
- [x] **AC7b** `admin-merge-ready-wiring.test.sh` passes, with three rows:
  - the positive row: the stub ran and the `gh` merge ledger is non-empty;
  - the unreplaced-sentinel row, under `env -u`: exit 5, `ADMIN-MERGE ABORTED: plugin root
    unresolved`, and the merge-ledger file still empty;
  - the decoy twin row: the pre-migration block writes the decoy ledger.
- [x] **AC7c** In `schedule/SKILL.md`, the `prompt: |` template carries no `CLAUDE_PLUGIN_ROOT`,
  and `concurrent-ship.test.sh` (T1, T1c and the new template row) passes.
- [x] **AC8** The derived regression sweep in `## Test Scenarios` passes with 0 failures.
  `scripts/battery-tag-authorship.test.sh`'s closure member count equals the Phase 0 value.
- [x] **AC9** ADR-179 carries `## Amendment — 2026-09-24 (#7453)` with A18–A20, including the
  Tier-1 exit-127 table, plus an `amended_by:` entry. The deferral bullet is struck through.
  ADR-093's "Amended by" line names the whole skills surface.
- [x] **AC10** No docstring or comment in `apps/web-platform/{server,test,scripts}` says the skills
  `:-` sites are live or deferred to #7453. Run
  `git grep -n -e '#7453' -e '~105' -- apps/web-platform/server apps/web-platform/test apps/web-platform/scripts`
  and review every hit in the AC walk.
- [x] **AC11** `bash plugins/soleur/test/c4-count-parity.test.sh`, `c4-code-syntax.test.ts` and
  `c4-render.test.ts` pass.
- [x] **AC12** Real-harness contact, **with the plugin relocated away from the CWD**, so the
  installed copy and a CWD copy are different files (security review P1).
  - **Setup.** `cp -r plugins/soleur "$TMP/soleur-plugin"`, then run
    `claude -p --plugin-dir "$TMP/soleur-plugin"` from this worktree. Plant canary edits in the
    worktree's own `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` and
    `…/git-worktree/scripts/worktree-manager.sh`: a distinctive line, and a script that writes a
    canary ledger.
  - **Prompt 1:** run the git-worktree skill's `list` step. The emitted command carries the
    `$TMP/soleur-plugin` absolute root, it succeeds, and the canary ledger stays empty.
  - **Prompt 2:** follow ship's pointer to `settle-then-admin-merge.md` and print the path read
    plus its first notice line. The path is under `$TMP/soleur-plugin`, and the canary line is
    absent.

  Commit both captures verbatim. If the CLI is unavailable, record
  `[~] NOT MET — <reason>`; never paraphrase a pass.
- [ ] **AC13** The PR body:
  - uses `Closes #7453` and cites ADR-179 (not ADR-177);
  - lists #6222, #8729 and #8730;
  - names the do-not-touch `:-` needles, with one line each;
  - carries the `--plugin-dir` contributor sentence.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** reviewed, at plan time and in the plan-review devex seat.

**Assessment:**

- **Keep both carve-out literals, low risk.** Both are exact. The bare literal fails closed when
  unset, and `export … && <literal>` is still decomposed. The `SOLEUR_PLUGIN_PATH` override falls
  back to a prompt, and A19 records that.
- **Grok, Codex and Devin availability, low risk.** Spec-flow found it is not the same status as
  for Grok nested Read (A20, #8730).
- **Sequencing:** the same-image reseed means the worst case is a short prompt. Check
  `battery-tag-authorship` (AC8), and leave H1 and T0b alone.
- **Devex:**
  - add the `--plugin-dir` contributor loop (Phase 8);
  - floor messages print the measured value;
  - the test-file index;
  - keep Guard 3's value as a one-time AC (it was cut as a permanent guard).

### Product/UX Gate

**Tier:** none. No UI-surface file is created or edited; the only user-visible surface is an
approval prompt, and the plan keeps it suppressed.
**Decision:** reviewed (CPO sign-off for single-user-incident)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off: **approved with conditions**, dispositions below.

1. The silent failure mode is added to "lands broken" (User-Brand Impact).
2. The leak wording is credential-level.
3. Substitution is checked for every file type. The Read-surface docs are handled by Phase 6 and
   Guard 4. `.sh` files are out of scope. Hooks are unaffected: `hooks.json` has had bare tokens
   substituted since `6893c7941`.
4. A CI check stops `:-` from returning (Guard 1).
5. The carve-out stays exact, with a `-pwn` negative (Phase 7).

### Plan Review (5-agent eng panel + CTO devex, 2026-09-24)

All findings were eng-panel correctness or simplification findings, so they are **Mechanical**
and applied. The one taste-shaped call, keeping Guard 4 and the probe script against a cut, is
recorded with reasons in its section.

- **Applied:**
  - Loader-anchored pointers plus root derivation from the path read, replacing the parent
    `export` clause (DHH P0, arch P1-1/P1-2, spec-flow P1-2/-4/-6/-10).
  - Per-block `export` and the exit-5 presence check (spec-flow P1-3).
  - `flag-bootstrap/SETUP.md` added (Kieran P0-1, spec-flow P1-5).
  - The schedule template handled (Kieran P0-2).
  - The five `admin-merge-ready.sh` prose mentions (spec-flow P0).
  - Ratchet ordering and AC6 on data rows (Kieran P1-3/-4).
  - Guard 5 M5 replaced, and the byte-for-byte claim corrected (Kieran P1-5/-7, arch P2-3).
  - Guard 2 gains the `..` escape (Kieran P1-6).
  - `LIST_EMISSION` widened and the count pinned at 4 (Kieran P2-8).
  - Prose before the script (Kieran P2-9).
  - R2 message and the file count (Kieran P2-11); the AC7 filter (Kieran P2-12).
  - The cron-bug-fixer entry recorded (arch P2-1, Kieran P2-10).
  - The Tier-1 exit-127 table (arch P2-4); Guard 1's population accepted and messaged (arch P2-5).
  - The derived sweep (arch P2-6).
  - Behavioural scenarios committed as rows (spec-flow P1-8).
  - The stale loaded root (spec-flow P2-11).
  - Guard 3 cut to AC3b (DHH P1, simplicity).
  - The mutation-log ritual and the AC7b mutation step cut (DHH, simplicity).
  - The ADR consolidated to 3 items (DHH, simplicity).
  - The `--plugin-dir` contributor line and floor messages (CTO devex).
- **Declined, with reasons:**
  - The inline probe (DHH P1-4, simplicity): Check 10 grammar forbids it (see Files to Create).
  - Cutting Guard 4 (DHH, simplicity): it found a missed doc (see Guard 4).
  - A hosted Better Stack post-deploy AC (spec-flow P2-9): an AC on production log absence
    depends on traffic, not code (`cq-ac-must-not-depend-on-concurrent-sessions`); the coupling
    test plus the dual literal cover it.
  - Extending the paid in-image probe to measure substitution (arch P2-2): the cost is out of
    proportion to a UX-only carve-out.

## Test Scenarios

The regression sweep is **derived**, not hand-picked. Take the union of:

1. Every test file that mentions `CLAUDE_PLUGIN_ROOT`:
   `git grep -l 'CLAUDE_PLUGIN_ROOT' -- '*.test.sh' '*.test.ts' 'tests/**'`. That is 26 today.
2. Every test file that names a migrated doc path:
   `git grep -l -F -f <(git diff --name-only origin/main -- 'plugins/soleur/**/*.md') -- '*.test.sh' '*.test.ts' 'tests/**'`.
   This catches `ship-battery-owed.test.sh`, `schedule-skill-once.test.sh` and others.
3. `apps/web-platform/test/{safe-bash,plugin-root-*,agent-env,agent-runner-query-options,c4-code-syntax,c4-render}.test.ts`,
   plus `plugins/soleur/test/{c4-count-parity.test.sh,components.test.ts}`.

Run each with its runner:

- `cd apps/web-platform && ./node_modules/.bin/vitest run <files>` for `apps/web-platform/test`;
- `bun test <files>` for `plugins/soleur/test/*.test.ts`;
- `bash <file>` for `*.test.sh` and `tests/commands/*.sh`.

Record the file list and a result of 0 failures for each.

Also run these lints:

- `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-24-chore-migrate-skills-plugin-root-default-sites-to-bare-anchor-plan.md`
- `lint-skill-body-budget` in its CI form (`--base "$(git merge-base origin/main HEAD)"`)
- `markdownlint-cli2` on every edited `.md`
- `python3 scripts/lint-infra-no-human-steps.py`
- `lint-shell-capture-exit` on `scripts/plugin-root-anchor-debt.sh`

Behavioural rows are committed rather than run once. They are:

- the unset-root decoy row in `lease-protects-active.test.sh`;
- the Pattern-C decoy row in `preflight-discoverability-test.test.ts`;
- the admin-merge positive and unset-root rows;
- the schedule template row.

AC12 is the only real-harness step.
