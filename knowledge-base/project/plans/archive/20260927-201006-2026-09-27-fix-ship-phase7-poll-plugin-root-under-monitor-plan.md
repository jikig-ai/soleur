---
title: "fix(ship): Phase 7 poll loses the plugin root when its fence is run from disk under Monitor"
date: 2026-09-27
slug: fix-ship-phase7-poll-plugin-root-under-monitor
branch: feat-one-shot-ship-poll-plugin-root-monitor
issue: none
type: bug
lane: cross-domain
brand_survival_threshold: none
---

# fix(ship): Phase 7 poll loses the plugin root when its fence is run from disk under Monitor

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No spec dir exists for this branch.)

## Enhancement Summary

**Deepened on:** 2026-09-27
**Sections enhanced:** 6 (Overview, Phase 1, Guard Contract, Observability (new), Acceptance Criteria, Sharp Edges)
**Agents and checks used:**

- `soleur:engineering:review:test-design-reviewer`.
- Deepen gates 4.6 (User-Brand Impact), 4.7 (Observability), 4.8 (PAT sweep) and 4.11 (`scripts/lint-guard-contract.py`, rc 0).
- Empirical probes: W1, W1b and W2 predicates on the exact prose; a literal-substitution prototype over both extracted fences; `probe-verb-gate.sh`.

### Key Improvements

1. **Added row 17c** (delivered text, variable **unset**). Row 17b's decoy satisfies any mutant that
   only requires the variable to be present, such as a `${CLAUDE_PLUGIN_ROOT:?}` guard. The real
   Monitor shape is "unset".
2. **The substitution root now contains a space**, so a mutant that unquotes the binding goes RED.
   The landing assertion counts **occurrences** and requires equality, and it pins the rewritten
   `SYNC_ROOT=` line.
3. **Row placement is load-bearing.** 17b must sit after scenario 13c, because `EVIL_ROOT` is defined
   there. Without that, 17b silently passes with no decoy. There is now a `[[ -d "$EVIL_ROOT" ]]`
   guard and a fresh mocks file, since scenario 9 deletes its own.
4. **M1 was re-chosen.** The old M1 (`SYNC_ROOT="$HOME"`) also turned scenario 9 RED, so it proved
   nothing. The new M1 is an env-reading binding, and every mutation row now names the control that
   stays GREEN.
5. **The prose pins cover the remedy clause** (`export … using that path`), not only the root
   display. They use single-quoted patterns and sit after the parity loop.
6. **Added an `## Observability` section.** Deepen gate 4.7 applies because the edited SKILL.md files
   sit under `plugins/*/skills/`. The probe is `grep -cF 'the root for this session is' …`, which
   prints `0` before the fix and `1` after, and it passes `probe-verb-gate.sh`.

### Verified facts (commands run this pass)

- The notice measures **760 bytes** and the pointer **264 bytes**. Both pass W1, W1b and W2; the
  predicates were ported verbatim from `plugin-root-anchoring.test.ts` and run against the exact text.
- A literal bash substitution over each extracted fence rewrites the token on **5 lines per block**
  and leaves 0. The binding becomes `SYNC_ROOT="$(set +u; printf '%s' "<root>")"`.
- `grep -c CLAUDE_PLUGIN_ROOT plugins/soleur/scripts/sync-pr-behind.sh` prints `0`, so a decoy in
  the environment cannot leak through the child script.

## Overview

The ship skill's Phase 7 merge poll runs as a Monitor command. In the prior session it started with an
empty plugin root. That switched off BEHIND auto-sync until the agent re-armed the poll with
`export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>` in front of the command.

**Root cause (verified; it is not the one the brief guessed).** The fence already binds the root once,
from the exact token the loader replaces:
`SYNC_ROOT="$(set +u; printf '%s' "${CLAUDE_PLUGIN_ROOT}")"`. That line sits in `ship/SKILL.md` inside
the `phase-7-poll-block` fence, and the identical line is in the `merge-pr/SKILL.md` §5.2 mirror.
ADR-179 measured this exact form as **SUBSTITUTED** in delivered text on both Claude Code and Grok (its
§"Measured before deciding" table). So the fence works when it is pasted from the skill body the Skill
tool delivered.

It breaks when the fence is **taken from `ship/SKILL.md` on disk**, with `awk`/`sed`/Read, or by
re-reading the file after a compaction dropped the delivered body. ADR-179 A20 records that the Read
surface returns raw bytes, so the token reaches bash unsubstituted. Every Monitor shell is fresh and
does not export `CLAUDE_PLUGIN_ROOT`. Measured this session: `CPR=[]`, and nothing matching `plugin`
in `env`. So `SYNC_ROOT` comes out empty, the precondition prints `CLAUDE_PLUGIN_ROOT is unset`, and
auto-sync turns off. Today's session learning records exactly this as item 4 of
`knowledge-base/project/learnings/2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`:
"A Phase 7 poll block extracted raw from `ship/SKILL.md` ran with its plugin-root token
unsubstituted". Raw extraction is the natural shortcut here: the fence is about 180 lines, the ship
body is 271 KB, and the fixture suite itself extracts the fence with `awk`.

**Why the fix cannot live only in the fence.** Payload markdown may read the root only through the
exact token. In `apps/web-platform/test/plugin-root-anchoring.test.ts`, W1 (`readsRootUnsafely`)
rejects `$CLAUDE_PLUGIN_ROOT`, any `${CLAUDE_PLUGIN_ROOT<modifier>}`, `printenv` and `${!…}`. W1b
(`plantsRootUnsafely`) rejects any `CLAUDE_PLUGIN_ROOT=` other than a lowercase `<…>` placeholder.
ADR-179 also forbids CWD defaults and confines the cache-search arm to go Step 0.5. So a fence run
from disk has exactly one legitimate source for the root: the environment the launching agent sets.
The fix hands the agent that value before it launches, and proves the delivered path works in a
fresh shell. The fence itself stays byte-identical. Its first event already names the cause
(`CLAUDE_PLUGIN_ROOT is unset`) and the remedy
(`export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>`), and that remedy is the one the prior
session applied:

1. **Prose (the remedy).** Add a short notice just before ship's fence and a one-line pointer in
   merge-pr §5.2. The notice says the token is fixed only in delivered text, and it **prints this
   session's substituted root**: `${CLAUDE_PLUGIN_ROOT}` in prose, which the loader turns into the
   absolute path. The agent can then prefix `export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>`
   with a value in hand rather than a guess. On a raw read the same spot shows the literal token, which
   tells the agent it is reading the file on disk.
2. **Fixture.** Add two delivered-text rows on both blocks: 17b (a hostile decoy root is exported)
   and 17c (the variable is unset, the real Monitor shape). Both substitute the token the way the
   loader does, with a root path that contains a space. They are the first rows to exercise the
   delivered shape, and they prove the loader's literal beats the environment. Also add prose pins
   in both SKILL.md files, a header comment, and set the verdict floor to the exact new total.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| The poll uses a form the loader does not substitute (bare `$VAR`, a `:-` default, or a reference inside a script the fence writes out) | The fence's only functional read of the root is the exact braced token, which is substituted in delivered text. The other token sites are messages. The hatch_check and behind_exhausted echoes run only when `sync_ok=1`, which means the root was already valid. The behind_no_sync text is a single-quoted literal. The fence writes out no script; the per-poll snapshot copies an existing file. | Diagnose raw extraction from disk (the Read surface, ADR-179 A20), not a wrong token form. Do not rewrite the binding. |
| "Prefer binding a local variable once from the substituted token at the top of the fence" | Already done (`SYNC_ROOT`, since #8474). Moving the two message echoes onto `$SYNC_ROOT` changes no behaviour, because they are reachable only when the root is valid. | Cut (see Cut List). |
| The fix is fence-only | W1/W1b forbid every non-token root read and every assignment in payload markdown. A fence read from disk can get the root only from the launching shell's environment. | Prose notice carrying the substituted root. The fence is unchanged (its first event already names the remedy). |

## Research Insights

**Premise validation.** No issue is the target (`issue: none`). The cited context still holds.

- #9028 (rename-guard false alarm on main-sync merges) is OPEN, so the brief's ship-time advice applies.
- #8730 (Grok nested SKILL.md reads need the root set) is OPEN. It is the same Read-surface class on
  another harness: acknowledged, not folded in.
- #8308 (go gates with the root unset) is CLOSED by #8391. That fix is the source of the go
  resolver's `ROOT="${CLAUDE_PLUGIN_ROOT}"` arm-1 pattern the brief points to.

All paths cited in the brief exist in the worktree, which is at `origin/main` `b650205010`.

**Property List.**

- P1: A Phase 7 poll launched under Monitor from the **delivered** skill text resolves the installed
  root with the variable unset, and an ambient `CLAUDE_PLUGIN_ROOT` cannot redirect it.
- P2: An agent launching the fence **from the file on disk** has the correct root value, and an
  instruction for supplying it, before it launches.
- P3: When the root is missing, the poll's first event names the cause and the remedy. **Already met
  on `main`:** `[ship.phase7.precondition] … CLAUDE_PLUGIN_ROOT is unset — … export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>`.
- P4: `merge-pr/SKILL.md` §5.2 carries the same text and the same guidance (mirror invariant).

**Cut List.**

- Rewriting the `SYNC_ROOT` binding to another form. Property: P1. The existing exact-token line already delivers it, and W1 forbids every alternative that reads the environment.
- Routing the hatch_check/behind_exhausted echoes through `$SYNC_ROOT` ("bind once"). Property: none. Both are reachable only with `sync_ok=1`, so neither can print an empty root.
- A single-quoted `'${CLAUDE_PLUGIN_ROOT}'` sentinel to tell substituted from raw at runtime. Property: P3. The first event already reports the unset root and its remedy. An unset root means an unsubstituted token: on a substituting harness (Claude Code, Grok), that is a read from disk; on Devin or Codex, which do not substitute, it is the expected state (scenario 13b's header).
- Rewording the fence's unset arm and precondition tail (planned in v1). Property: P3, which is already met. The new wording was also **wrong on some paths**: "copied from SKILL.md on disk" misstates the cause on Devin and Codex, and "above its Phase 7 fence … minus /skills/ship", copied byte-for-byte into the merge-pr mirror, points merge-pr agents at the wrong place. Cut by plan review; the fence stays byte-identical.
- A plugin-cache or `installed_plugins.json` search arm. Property: P2. Forbidden outside go Step 0.5 (ADR-179 A11 confinement). Measured here, it would also **diverge**: the registry says `~/.claude/plugins/cache/soleur/soleur/4dbd1affe8eb`, while this session's loader substituted `/data/git-repositories/jikig-ai/soleur/plugins/soleur` (a directory marketplace).
- Failing the poll fast when the root is unset. Property: P3. It would reverse scenario 13b's deliberate degrade-open design for Devin/Codex, and the first event already reports the cause.
- **Refusing a root inside the checkout** (the ADR-179 A20.4 shape the admin-merge fences use). Property: stopping the natural wrong repair, `export` of the checkout's own `plugins/soleur`. **Cut after measurement: it would break a legitimate consumer.** `apps/web-platform/server/inngest/functions/event-ship-merge.ts` runs `/soleur:ship --headless` with `"--plugin-dir", "plugins/soleur"`, the PR clone's tracked tree by design (#5091). There the loader's own root is inside the checkout, so the refusal would switch off BEHIND auto-sync on every auto-ship run. The sync script is also not a trust gate like `admin-merge-ready.sh`, and ship already runs the checkout's own code (its test battery). The prose steers the agent to the loader's printed root instead.
- Moving the fence into a committed `BASH_SOURCE`-anchored script that both skills call (the ADR-179 A17 route). Properties: P1/P2/P4. It would remove the extraction temptation and the mirror. **Rejected for this PR:** it restructures the fixture's extract-and-source harness and the mirror-parity machinery, so it is a design change, not this fix. Recorded as an alternative, not a deferral.

**Relevant files.**

- `plugins/soleur/skills/ship/SKILL.md`, Phase 7:
  - The fence between the `phase-7-poll-block:start` and `:end` markers.
  - The binding and the `why` chain under the comment beginning `# Bare ${CLAUDE_PLUGIN_ROOT}, never a`.
  - The shared precondition `echo "[ship.phase7.precondition] sync-pr-behind.sh not usable at '$SYNC_SH': $why — …"`.
  - The prose line beginning `**Claude — Monitor tool loop**`, just before the fence.
- `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 `Poll for Merge`: the `**Mirror invariant:**` paragraph and the mirror fence (`# <!-- phase-7-poll-block:start --> mirror of ship/SKILL.md Phase 7`).
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`:
  - Relevant parts: `extract_block()`, the mirror parity `for token in …` list, `run_scenario` (block path is the fifth argument) and its `case "${SCEN_ROOT:-}"`, scenarios 13b/13c (`EVIL_ROOT`), and the tail `MIN_VERDICTS=380`.
  - **Baseline measured:** `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` gives `392 pass, 0 fail`, rc 0.
- `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`:
  - The substitution table row `| ${CLAUDE_PLUGIN_ROOT} | SUBSTITUTED | SUBSTITUTED |`.
  - A20: the Read surface delivers raw tokens, no block exports the variable, and the notice tells the agent to prefix `export CLAUDE_PLUGIN_ROOT=<root>` because every Monitor task starts a fresh shell.
- `apps/web-platform/server/inngest/functions/event-ship-merge.ts`: the headless ship consumer (`--plugin-dir plugins/soleur`). It is the reason the in-checkout refusal was cut.
- `apps/web-platform/test/plugin-root-anchoring.test.ts`: W1/W1b/W2/W3 constrain any new prose or fence text. It is a required CI context.
- `plugins/soleur/test/skill-body-budget.json`: `"ship": 274000`, against a measured `wc -c` of **271034**, which leaves **2966 bytes** of headroom. The ceiling is enforced against the merge base by `python3 scripts/lint-skill-body-budget.py --base origin/main` (currently `OK`) and only ratchets down. merge-pr has no row.

**Institutional learnings applied.**

- `2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`, item 4. This is the incident itself; its stated prevention is "export first; read the first event".
- `2026-09-24-every-refusal-i-added-had-a-one-keystroke-repair-that-reopened-it.md`. A message must name the fix. This drove the look at an in-checkout refusal, cut here only after the headless consumer was found.
- review SKILL.md's "a green check answers a question about the SET you gave it", shape (b). A `sed`/`perl` replacement that contains `$` is interpolated by the tool, so the delivered-text rows must do a literal replacement and assert that it landed.
- plan sharp edge "a presence check after `source` is satisfied by the environment". Rows 17b and 17c must run with an explicit decoy or an explicit unset, never inheriting the developer's shell value.

**Conventions.** `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`,
`hr-verify-repo-capability-claim-before-assert`, `cq-write-failing-tests-before`,
`hr-never-git-stash-in-worktrees`.

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md`: one prose notice before the Phase 7 fence. The fence stays byte-identical. The notice measures **761 bytes**; cap the net growth at **800** against 2,966 bytes of headroom.
- `plugins/soleur/skills/merge-pr/SKILL.md`: one pointer sentence appended to the §5.2 `**Mirror invariant:**` paragraph. The fence stays byte-identical.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`: the delivered-text rows 17b and 17c on both blocks, the prose pins in both SKILL.md files, the header comment, and `MIN_VERDICTS`.

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED: fixture rows first (`cq-write-failing-tests-before`)

In `ship-phase-7-poll-fixtures.test.sh`. Place **every** new row after scenario 13c, whose
`EVIL_ROOT="$(mktemp -d)"` is near the `# Scenario 13c` header, and after the mirror-parity loop.

1. **A spaced plugin root.** Make `SPACED_PARENT="$(mktemp -d)"` and
   `SPACED_ROOT="$SPACED_PARENT/plugin root"`, then `cp -R "$PLUGIN_COPY/." "$SPACED_ROOT/"`.
   - Register `SPACED_PARENT` in `_TMP_OWNED` and run `assert_fixture_dir` on it.
   - The space in the path catches a mutant that unquotes the binding.
   - Add `[[ -d "$EVIL_ROOT" ]] || { fail "EVIL_ROOT missing (17b placed before 13c?)"; exit 1; }`.
     An empty `EVIL_ROOT` drops `run_scenario` into its `""` arm, which exports `$PLUGIN_COPY`, and
     17b would then pass with no decoy at all.
2. **Delivered-text blocks.** Build `SUBST_BLOCK` and `SUBST_MIRROR` from `BLOCK_FILE` and
   `MIRROR_FILE`. Replace every literal `${CLAUDE_PLUGIN_ROOT}` with `$SPACED_ROOT`, the way the loader does.
   - Use a **literal** replacement: bash `${line//"$tok"/"$SPACED_ROOT"}` inside a
     `while IFS= read -r line || [[ -n $line ]]` loop. Never use a regex `sed`/`perl` whose
     replacement carries `$`.
   - Register both files in `_TMP_OWNED`.
   - Assert the landing by counting **occurrences**, not lines (`grep -oF -- "$x" f | wc -l`):
     - The token count after is `0`.
     - The `$SPACED_ROOT` count after **equals** the token count before, and that count is at least 1.
     - The rewritten binding line is present verbatim: `SYNC_ROOT="$(set +u; printf '%s' "<SPACED_ROOT>")"`.
   - Measured on today's blocks: the token sits on 5 lines per block, a literal bash substitution
     leaves 0, and the binding becomes a literal path.
3. **Mocks.** Build a fresh `mktemp` mocks file from `${SYNC_MOCKS}`, the same content as scenario
   9's. Scenario 9 deletes its `$SCEN9` file right after its run, so reusing it is unsafe. Register
   the new file in `_TMP_OWNED`.
   - Extend scenario 9's `SUCCESS_FORBID` with `\[ship\.phase7\.precondition\]|does not name soleur`.
   - `run_scenario` takes the block path as its fifth argument. Call it per block and expect
     scenario 9's per-block success line: ship prints `\[1/60\] auto-sync 1 pushed`, and the mirror
     prints `\[1/60\] auto-sync 1/6 pushed`.
4. **Row 17b, delivered text with a decoy environment.** Use `SCEN_ROOT="$EVIL_ROOT"`, scenario 13c's
   `{"name":"evil"}` root, exported as an ambient decoy. Labels: `17b-delivered-decoy:ship` and
   `17b-delivered-decoy:merge-pr`.
   - This is the ADR-179 A10 decoy control: the loader-fixed literal wins over the environment.
   - `sync-pr-behind.sh` never reads `CLAUDE_PLUGIN_ROOT` (it has 0 references), so the decoy cannot
     leak in through the child script.
   - **The negative control is scenario 13c**: the same decoy on the raw block, where it is refused.
5. **Row 17c, delivered text with the variable unset.** This is the real Monitor shape. Use
   `SCEN_ROOT=unset` with labels `17c-delivered-unset:ship` and `17c-delivered-unset:merge-pr`.
   - This row catches a mutant that requires the variable to be **present**, which 17b's decoy
     satisfies. Examples: a `${CLAUDE_PLUGIN_ROOT:?}` guard, or a bare env read on the success path.
6. **Prose pins.** Place them after the parity loop, because its skeleton `pass` checks the global
   `FAIL` count. For each of the two SKILL.md files, run `grep -qF` over the whole file for
   **two** single-quoted fragments. Single quotes keep the harness shell from expanding the token.
   - `` 'the root for this session is `${CLAUDE_PLUGIN_ROOT}`' ``
   - `` 'export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>` using that path' ``

   The second fragment pins the remedy clause, not only the root display. Anchor on these sentence
   fragments, not a bare token (`cq-assert-anchor-not-bare-token`). Give each file and fragment its
   own `pass` or `fail` line.
7. Run the suite against the unmodified skills.
   - **Expected RED:** the prose pins.
   - **Expected GREEN:** 17b and 17c, because the existing binding is already correct. Record that
     result in the PR body as the executable proof of the root-cause diagnosis.

### Phase 2 — GREEN: ship prose

Add a new paragraph to `ship/SKILL.md` right after the `**Claude — Monitor tool loop**` line and
before "Use the **Monitor tool** with this shell loop". Measured at 761 bytes:

> **The plugin root is fixed only in delivered text.** The loader replaced the token in the fence below when the Skill tool delivered this skill; the root for this session is `${CLAUDE_PLUGIN_ROOT}` (a literal token there means you are reading the file on disk). A fence copied from `SKILL.md` on disk — `awk`/`sed`/Read, or a re-read after compaction — keeps the raw token, and a Monitor shell does not export the variable, so the poll opens with `[ship.phase7.precondition] … CLAUDE_PLUGIN_ROOT is unset` and BEHIND auto-sync off. Paste the fence from the delivered text, or prefix the Monitor command with `export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>` using that path, not a path derived from the checkout. Read the poll's first event.

Before committing, re-check the exact final text:

- **W1:** no `$CLAUDE_PLUGIN_ROOT` without braces, and no modifier.
- **W1b:** the only assignment is the `<…>` placeholder.
- **W2:** no `$VAR/plugins/soleur` and no `show-toplevel)/plugins/soleur`. Do **not** spell a checkout path such as `$PWD/plugins/soleur`.
- **W3:** no unquoted token passed to a runner.
- **Size:** `wc -c` is at most 274000 and net growth is at most 800 bytes.

**Do not edit the fence.** A fence change would need the same bytes in the merge-pr mirror, and
text that points at "ship's Phase 7" reads wrong there.

### Phase 3 — GREEN: merge-pr pointer

Append this sentence to the `**Mirror invariant:**` paragraph in `merge-pr/SKILL.md` §5.2:

> ship Phase 7's plugin-root rule applies here: paste this fence from the delivered skill text (the root for this session is `${CLAUDE_PLUGIN_ROOT}`), or prefix the Monitor command with `export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>` using that path.

### Phase 4 — Verify

1. Run `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`; it must be all green.
   - Read the new total and raise `MIN_VERDICTS` to it. The floor goes up only, never down.
   - Add 17b, 17c and the prose pins to the header's scenario list.
2. Apply each Guard Contract mutation as a temporary edit, run the suite, then revert with
   `git checkout -- <file>`. Never use `git stash` (`hr-never-git-stash-in-worktrees`). Record
   RED or GREEN per row in the PR body.
3. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`.
   W1, W1b, W2, W3 and the W5 floor must stay green.
4. Run `python3 scripts/lint-skill-body-budget.py --base origin/main`.
   - Invocation verified: `--base` is required.
   - Today it prints `OK (10 lifecycle skill(s) within ceilings…)`.
5. Run `bash scripts/plugin-root-anchor-debt.sh`; it must print `anchor-debt-files=0` (verified today).
6. Run `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/components.test.ts`.
7. Run `npx markdownlint-cli2` on both edited SKILL.md files.

## Guard Contract

### Guard 1 — Delivered-text rows 17b/17c and the prose pins

**Property.** Pasted from delivered text (the token replaced by a literal), each Phase 7 block
resolves the installed root without help from the environment, and an ambient hostile
`CLAUDE_PLUGIN_ROOT` cannot redirect it. Each SKILL.md tells an agent that reads it from disk how to
supply the root.

**Assembly.** There are two blocks: ship's canonical fence and merge-pr's §5.2 mirror. Each block has
one chokepoint, its single binding line `SYNC_ROOT="$(set +u; printf '%s' "${CLAUDE_PLUGIN_ROOT}")"`.
That line is the only functional read of the root; every other token site is message text. There are
two prose sites, one per file. Rows 17b and 17c each reach both blocks through explicit `run_scenario` calls,
and the prose pins reach both files.

**Mutation matrix.** Each mutation must turn the suite RED.

| # | Mutation | Expected RED | Control that stays GREEN |
|---|---|---|---|
| M1 | Ship's binding reads the environment instead of the token: `SYNC_ROOT="$(set +u; printf '%s' "$CLAUDE_PLUGIN_ROOT")"`. This is a local-only mutant; CI's W1 would also reject it. | 17b:ship (resolves the decoy and fails identity) and 17c:ship (empty root) | scenario 9:ship, where the variable carries the right root |
| M2 | The same mutant in the mirror only, the second member after a compliant first | 17b:merge-pr, 17c:merge-pr, and the existing parity token for the binding line | ship rows |
| M3 | Ship's binding requires presence: prepend `: "${CLAUDE_PLUGIN_ROOT:?}";` (local-only; W1 rejects it) | 17c:ship | 17b:ship, since the decoy satisfies presence |
| M4 | Unquote the token in ship's binding (`printf '%s' ${CLAUDE_PLUGIN_ROOT}`) | 17b:ship and 17c:ship (the spaced root word-splits) | scenario 9 (no space in `$PLUGIN_COPY`) |
| M5 | Delete the notice from ship's prose, or only its `export … using that path` clause | the matching prose pin for ship | merge-pr pins |
| M6 | Delete the pointer sentence from merge-pr only | the prose pins for merge-pr | ship pins |
| M7 | Own dispatch: drop the `:merge-pr` call for 17c | the `MIN_VERDICTS` floor. This works only if the floor is set to the **exact** new total; one dropped call costs about 5 verdicts, and today's floor sits 12 below the total. | none |

**Harness rows.**

- **H1**, a suite edit that must go RED: make the substitution helper replace nothing, for example
  with a pattern typo. The landing assertion goes RED, and so do 17b and 17c.
- **H2**, a suite edit that must go RED: move 17b above scenario 13c, so `EVIL_ROOT` is empty. The
  `[[ -d "$EVIL_ROOT" ]]` guard fails.
- **Negative control**, an existing row that must stay as is: scenario 13c. It uses the same decoy
  on the raw block and is refused (`does not name soleur`). That shows the decoy is live, and that
  17b passes only because of the substitution.

**Anchor.** Not applicable. The guard compares no stored hash, count or manifest row. The
`MIN_VERDICTS` floor is a ratchet, paired with per-row verdicts.

## Observability

The surface is a plugin skill doc that runs on the operator's own CLI (observability layer 7). No
server code changes, and the poll's output lines are unchanged. The signal the operator reads is the
poll's own Monitor stream.

```yaml
liveness_signal:
  what: the Phase 7 poll's first Monitor event; either a PR state line, or `[ship.phase7.precondition] … CLAUDE_PLUGIN_ROOT is unset` when the fence ran unsubstituted
  cadence: first poll iteration, then each state change plus a heartbeat every 3rd minute
  alert_target: the operator's Claude Code session (Monitor notifications stream stdout)
  configured_in: plugins/soleur/skills/ship/SKILL.md Phase 7 fence (unchanged) and its new delivered-text notice
error_reporting:
  destination: Monitor stdout; the `[ship.phase7.*]` tags are asserted stdout-only by the fixture
  fail_loud: true (an unset root prints the precondition line on the first event, then `[ship.phase7.behind_no_sync]` stops the poll at the first BEHIND tick)
failure_modes:
  - mode: fence copied from SKILL.md on disk into a Monitor shell (token unsubstituted, variable unexported)
    detection: the first event is `[ship.phase7.precondition] … CLAUDE_PLUGIN_ROOT is unset`
    alert_route: Monitor notification to the operator's session; the new notice gives the root to export
  - mode: the notice is deleted or drifts out of either SKILL.md
    detection: the prose-pin rows in plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh go RED in CI
    alert_route: a failed CI check on the PR
  - mode: the fence's root binding stops reading the loader token
    detection: row 17b (decoy) or row 17c (unset) goes RED
    alert_route: a failed CI check on the PR
logs:
  where: the Monitor task's stdout in the operator's session; CI logs for the fixture suite
  retention: session-scoped (Monitor) and GitHub Actions log retention (CI)
discoverability_test:
  command: grep -cF 'the root for this session is' plugins/soleur/skills/ship/SKILL.md
  expected_output: "1"
```

The probe was checked with `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh`: rc 0, and it
uses no shell-active characters. Before the fix it prints `0`; after the fix it prints `1`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` exits 0 with more than the baseline 392 verdicts. `MIN_VERDICTS` is set to the **exact** new measured total, not a round number below it.
- [ ] Rows `17b-delivered-decoy` (`SCEN_ROOT="$EVIL_ROOT"`) and `17c-delivered-unset` (`SCEN_ROOT=unset`) run against **both** blocks, with a substitution root that contains a space. Each asserts scenario 9's per-block success line (`auto-sync 1 pushed` for ship, `auto-sync 1/6 pushed` for the mirror), with no `[ship.phase7.precondition]` or `does not name soleur` line.
- [ ] The substitution-landing assertion counts occurrences: the token count after is 0, the root count equals the token count before (at least 1), and the rewritten `SYNC_ROOT=` line is present.
- [ ] Every Guard Contract mutation M1–M7 and harness rows H1 and H2 were applied and observed RED, with each row's control observed GREEN. The table is in the PR body.
- [ ] Both phase-7-poll-block fences are byte-identical to `origin/main`: `diff` of the extracted fence at `origin/main` and at `HEAD` is empty for each file.
- [ ] Both SKILL.md files carry `` the root for this session is `${CLAUDE_PLUGIN_ROOT}` `` (the prose-pin rows are green).
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` passes, and ship grows by at most 800 bytes.
- [ ] `apps/web-platform/test/plugin-root-anchoring.test.ts` is green.
- [ ] `bash scripts/plugin-root-anchor-debt.sh` prints `anchor-debt-files=0`.
- [ ] `git diff --name-only origin/main...HEAD -- ':!knowledge-base'` lists exactly the three Files to Edit. Pipeline-written knowledge-base artifacts (plan, tasks, session-state, learnings, INDEX) are excluded.

### Post-merge

- [ ] None beyond the normal ship flow. There is no deploy surface; the plugin ships through the release workflow.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is a tooling change to two skill docs and one fixture
suite. There is no UI surface, and the mechanical UI-surface override does not fire: nothing matches
`components/**`, `app/**`, or the UI term list.

## User-Brand Impact

**If this lands broken, the user experiences:** a notice that points the agent at the wrong root. The
poll's bytes and behaviour do not change; only the surrounding guidance does. The worst case is the pre-fix state: auto-sync disabled until the
agent re-arms the poll.

**If this leaks, the user's workflow is exposed via:** nothing new. No credential, token or user data
is read or printed. The notice prints the plugin install path, which is already present in every
delivered skill body.

**Brand-survival threshold:** none

- threshold: none, reason: text-only change to a degrade-open merge poll plus fixture rows; no user data, credentials or production state is touched.

## Test Scenarios

See Phase 1: rows 17b and 17c on both blocks, the substitution-landing assertion, and the prose-pin rows.
The existing rows, 13b included, must stay green unchanged, because the fence does not change.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) was checked for the three file
paths and the `phase-7-poll-block` marker: zero matches.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Rewrite the binding to another root-reading form | Rejected. The existing exact token is the only form the loader fixes, and W1 bans the rest. |
| Search the plugin cache or `installed_plugins.json` | Rejected. ADR-179 A11 confines cache arms to go Step 0.5, and a search here was measured to diverge from the loader root (directory marketplace). |
| Fail the poll fast when the root is unset | Rejected. It reverses scenario 13b's deliberate degrade-open design (Devin/Codex). |
| Refuse a root inside the checkout (ADR-179 A20.4 shape) | Rejected after measurement. `event-ship-merge.ts` runs headless ship with `--plugin-dir plugins/soleur`, the PR clone's tree (#5091), so the loader's own root is inside the checkout and the refusal would disable auto-sync on every auto-ship run. |
| Move the fence into a `BASH_SOURCE`-anchored script both skills call (ADR-179 A17 route) | Rejected for this PR. It removes the extraction temptation but restructures the fixture harness and retires the mirror, which makes it a design change rather than this fix. |

## Plan Review

The code-simplicity reviewer ran against v2 of this plan. Its findings were applied:

- **Precondition rewording cut.** P3 was already met, and the new wording was wrong for Devin/Codex
  and for the merge-pr mirror.
- **Row 17 and its fence edits cut.** Row 17b, now on both blocks, covers the same ground. The later test-design review re-added the unset case as 17c, because it catches presence-requiring mutants.
- **Prose pin changed to a whole-file grep.**
- **Byte cap tightened to 800,** from a measured 761.

The change of direction relative to the brief is recorded in
`knowledge-base/project/specs/feat-one-shot-ship-poll-plugin-root-monitor/decision-challenges.md` (DC-1).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- **The byte budget is tight.** ship has 2,966 bytes of headroom and the ceiling only ratchets down. Measure `wc -c` after the edit. If the prose runs long, trim it without dropping its conditions (unsubstituted on disk, fresh Monitor shell, where the root comes from); do not touch the budget file, since raising a ceiling is a separate reviewed PR.
- **Never spell a checkout path in payload prose.** `$PWD/plugins/soleur` trips W2 (the dynamic-prefix predicate).
- **The substitution helper for rows 17b and 17c must be literal.** A `sed`/`perl` replacement containing `$` is interpolated by the tool, and the result is garbage even though "the file changed" still holds. Assert on the token count after the replacement and on the path count.
- **Rows 17b and 17c must control the environment.** 17b exports a decoy and 17c unsets the variable. Neither may inherit a developer's shell value (the presence-after-`source` class). 17b must sit after scenario 13c, which defines `EVIL_ROOT`.
- **Do not edit the fence at all.** In particular, do not add a refusal of in-checkout roots. The headless `event-ship-merge` consumer legitimately runs with a loader root inside the checkout; see Cut List.
- **Ship-time CI flake #9028** (rename-guard false alarm on main-sync merges). If it fires, rebuild the branch as one linear commit on `origin/main` with an identical tree. **Never** apply the override label.
- One PR for this item only. The guardrails.sh filing-gate matcher is a separate follow-up PR.
- Run `npx markdownlint-cli2` on the plan and `tasks.md` before committing them.
