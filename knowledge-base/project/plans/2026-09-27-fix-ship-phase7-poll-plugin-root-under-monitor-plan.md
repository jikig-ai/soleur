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
2. **Fixture.** Add one delivered-text row, 17b, on both blocks. It substitutes the token the way the
   loader does and exports a hostile decoy root. It is the first row to exercise the delivered shape,
   and it proves the loader's literal beats the environment. Also add a prose-pin row per SKILL.md, a
   header comment, and a raise of the verdict floor.

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
- plan sharp edge "a presence check after `source` is satisfied by the environment". Row 17b must run with an explicit decoy root, never inheriting the developer's shell value.

**Conventions.** `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`,
`hr-verify-repo-capability-claim-before-assert`, `cq-write-failing-tests-before`,
`hr-never-git-stash-in-worktrees`.

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md`: one prose notice before the Phase 7 fence. The fence stays byte-identical. The notice measures **761 bytes**; cap the net growth at **800** against 2,966 bytes of headroom.
- `plugins/soleur/skills/merge-pr/SKILL.md`: one pointer sentence appended to the §5.2 `**Mirror invariant:**` paragraph. The fence stays byte-identical.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`: the delivered-decoy row 17b on both blocks, one prose-pin row per SKILL.md, the header comment, and `MIN_VERDICTS`.

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED: fixture rows first (`cq-write-failing-tests-before`)

In `ship-phase-7-poll-fixtures.test.sh`:

1. **Prose pin (RED today).** For each of the two SKILL.md files, `grep -qF` the whole file for the
   notice's sentence fragment `` the root for this session is `${CLAUDE_PLUGIN_ROOT}` ``. On disk the
   file carries the raw token, so this is the exact byte string. Anchor on the sentence, not a bare
   token (`cq-assert-anchor-not-bare-token`). Give each file its own `pass`/`fail` line.
2. **Delivered-text blocks.** Build `SUBST_BLOCK` and `SUBST_MIRROR` from `BLOCK_FILE` and
   `MIRROR_FILE`. Replace every literal `${CLAUDE_PLUGIN_ROOT}` with `$PLUGIN_COPY`, the way the
   loader does.
   - Use a **literal** replacement: bash `${line//"$tok"/"$PLUGIN_COPY"}` inside a
     `while IFS= read -r` loop, or awk `index`/`substr`. Never use a regex `sed`/`perl` whose
     replacement carries `$`.
   - Register both files in `_TMP_OWNED`.
   - Assert the replacement landed: the token count after is `0`, and `$PLUGIN_COPY` appears at least
     as many times as the token did before, which must be at least 1.
3. **Row 17b: delivered text, decoy environment (GREEN today; it proves the diagnosis).** Base it on
   scenario 9 (`9-success-path`): reuse its `${SYNC_MOCKS}` mocks file, and extend its
   `SUCCESS_FORBID` with `\[ship\.phase7\.precondition\]|does not name soleur`.
   - Run with `SCEN_ROOT="$EVIL_ROOT"`, scenario 13c's `{"name":"evil"}` root, exported as an ambient
     decoy.
   - `run_scenario` takes the block path as its fifth argument, so call it twice: once as
     `17b-delivered-decoy:ship` with `SUBST_BLOCK`, once as `17b-delivered-decoy:merge-pr` with
     `SUBST_MIRROR`.
   - Expect scenario 9's per-block success line. Ship prints `\[1/60\] auto-sync 1 pushed`; the
     mirror prints `\[1/60\] auto-sync 1/6 pushed`.
   - This is the ADR-179 A10 decoy control. The loader-fixed literal wins over the environment, and
     the poll resolves the root with no help from the environment, which is the Monitor shape.
     `sync-pr-behind.sh` never reads `CLAUDE_PLUGIN_ROOT`, so the decoy cannot leak in through the
     child script.
4. Run the suite against the unmodified skills. **Expected:** the two prose-pin rows are RED. Row 17b
   is GREEN because the existing binding is correct; record that in the PR body as the executable
   proof of the root-cause diagnosis.

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
   - Add 17b and the prose pin to the header's scenario list.
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

### Guard 1 — Delivered-decoy row 17b and the prose pin

**Property.** Pasted from delivered text (the token replaced by a literal), each Phase 7 block
resolves the installed root without help from the environment, and an ambient hostile
`CLAUDE_PLUGIN_ROOT` cannot redirect it. Each SKILL.md tells an agent that reads it from disk how to
supply the root.

**Assembly.** There are two blocks: ship's canonical fence and merge-pr's §5.2 mirror. Each block has
one chokepoint, its single binding line `SYNC_ROOT="$(set +u; printf '%s' "${CLAUDE_PLUGIN_ROOT}")"`.
That line is the only functional read of the root; every other token site is message text. There are
two prose sites, one per file. Row 17b reaches both blocks through two explicit `run_scenario` calls,
and the prose pin reaches both files.

**Mutation matrix.** Each mutation must turn the suite RED.

| # | Mutation | Expected RED |
|---|---|---|
| M1 | Replace ship's binding with a read that ignores the token (for example `SYNC_ROOT="$HOME"`, a local-only mutant that W1 would also reject) | 17b:ship |
| M2 | The same mutant in the mirror only, the second member after a compliant first | 17b:merge-pr and the existing parity token for the binding line |
| M3 | Delete the notice from ship's prose | the prose pin for ship |
| M4 | Delete the pointer sentence from merge-pr only | the prose pin for merge-pr |
| M5 | Own dispatch: drop the `:merge-pr` call for row 17b | the `MIN_VERDICTS` floor |

**Harness rows.**

- **H1**, a suite edit that must go RED: the substitution helper replaces nothing (a pattern typo).
  The landing assertion fails.
- **H2**, must PASS and is not the canonical case: row 17b itself. The environment carries a
  different, hostile root, and the poll still syncs from the substituted literal.

**Anchor.** Not applicable. The guard compares no stored hash, count or manifest row. The
`MIN_VERDICTS` floor is a ratchet, paired with per-row verdicts.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` exits 0 with more than the baseline 392 verdicts, and `MIN_VERDICTS` equals the new measured total.
- [ ] Row `17b-delivered-decoy` runs against **both** blocks (`:ship` and `:merge-pr` labels) with `SCEN_ROOT="$EVIL_ROOT"`, and asserts scenario 9's per-block success line (`auto-sync 1 pushed` for ship, `auto-sync 1/6 pushed` for the mirror) with no `[ship.phase7.precondition]` or `does not name soleur` line.
- [ ] The substitution-landing assertion exists: token count after = 0, and path count ≥ 1.
- [ ] Every Guard Contract mutation M1–M5 and harness row H1 was applied and observed RED. H2/H3 were observed GREEN. The table is in the PR body.
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

See Phase 1: row 17b on both blocks, the substitution-landing assertion, and the two prose-pin rows.
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
- **Row 17 and its fence edits cut.** Row 17b, now on both blocks, covers the same ground.
- **Prose pin changed to a whole-file grep.**
- **Byte cap tightened to 800,** from a measured 761.

The change of direction relative to the brief is recorded in
`knowledge-base/project/specs/feat-one-shot-ship-poll-plugin-root-monitor/decision-challenges.md` (DC-1).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- **The byte budget is tight.** ship has 2,966 bytes of headroom and the ceiling only ratchets down. Measure `wc -c` after the edit. If the prose runs long, trim it without dropping its conditions (unsubstituted on disk, fresh Monitor shell, where the root comes from); do not touch the budget file, since raising a ceiling is a separate reviewed PR.
- **Never spell a checkout path in payload prose.** `$PWD/plugins/soleur` trips W2 (the dynamic-prefix predicate).
- **The substitution helper for row 17b must be literal.** A `sed`/`perl` replacement containing `$` is interpolated by the tool, and the result is garbage even though "the file changed" still holds. Assert on the token count after the replacement and on the path count.
- **Row 17b must control the environment.** It exports a decoy and must never inherit a developer's shell value (the presence-after-`source` class).
- **Do not edit the fence at all.** In particular, do not add a refusal of in-checkout roots. The headless `event-ship-merge` consumer legitimately runs with a loader root inside the checkout; see Cut List.
- **Ship-time CI flake #9028** (rename-guard false alarm on main-sync merges). If it fires, rebuild the branch as one linear commit on `origin/main` with an identical tree. **Never** apply the override label.
- One PR for this item only. The guardrails.sh filing-gate matcher is a separate follow-up PR.
- Run `npx markdownlint-cli2` on the plan and `tasks.md` before committing them.
