---
title: "fix: safe-bash must not let git log/diff/show/status execute repo-config helpers"
date: 2026-11-09
slug: safe-bash-git-config-exec-carriers
branch: feat-one-shot-9600-safe-bash-ext-diff
issue: 9600
closes: none
epic: 9601
type: fix
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: safe-bash must not let git log/diff/show/status execute repo-config helpers

Ref #9600 (work target), #9601 (epic; not closed by this PR).

## Overview

`apps/web-platform/server/safe-bash.ts` auto-approves `git log|diff|show` followed by any number of `PATH_TOKEN` words, and bare `git status`. The issue names `--ext-diff`. A real-git falsifier (run during planning, results below) shows the problem is wider than a flag: with a planted repo-local config, even the plainest approved reads (`git status`, `git diff`, `git diff HEAD~1`, `git show HEAD`) execute a helper. A flag denylist therefore cannot close the hole, and the issue's own mitigation shape is insufficient.

CTO ruling (see `knowledge-base/project/specs/feat-one-shot-9600-safe-bash-ext-diff/decision-challenges.md`): close the **carriers** (the places a config key can come from) and make the **flag grammar** closed, instead of stripping the common reads of auto-approval. Three controls ship together:

1. **Closed flag grammar** in `safe-bash.ts` for `git log|diff|show`: only flags verified inert in the real-git table are admitted; `--ext-diff`, `--textconv`, `-p`, `-S`, `-G`, `-O*`, `--output*`, `--show-signature`, every abbreviation and every unknown flag fall to the review card (not a hard deny).
2. **Carrier guard**: `Write`/`Edit`/`NotebookEdit` are refused on any path with a `.git` component (case-insensitive, any depth, after symlink resolution), enforced in both the PreToolUse sandbox hook and `canUseTool`.
3. **Env pin (primary control)**: `safe.bareRepository=explicit` (plus unconditional `GIT_CONFIG_NOSYSTEM=1` / `GIT_CONFIG_GLOBAL=/dev/null`) in `buildAgentEnv`. Measured late in planning: a bare repository **committed into an untrusted repo** (`evil/HEAD`, `evil/config`, `evil/objects/info/alternates`, `evil/refs/heads/main` as plain tracked files) is a working config carrier after a plain clone; the agent only has to run the already-approved `cd evil && git diff HEAD~1 HEAD`. No file-tool write and no `.git` component is involved, so the path guard cannot see it; the pin does (git then ignores the bare dir and uses the outer repo). The pin is therefore the primary control and the `.git` guard the secondary one (CTO ruling in decision-challenges.md).

Honest outcome (stated verbatim in the PR body): bare `git diff` and `git status` **still execute** any config that is present; the hole is closed at the carriers, not at the verb. The PR says `Ref #9600`, not `Closes`, until the runtime image's git is measured at 2.38 or later (the first git with `safe.bareRepository`) and the real-git tests pass there; that measurement is the flip condition (AC11).

## Enhancement Summary

**Deepened on:** 2026-11-09 | **Gates run:** 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT sweep, 4.9 UI wireframe (not triggered), 4.10 Encryption Posture (not triggered: no `.tf`/migration/compose/cloud-init file), 4.11 Guard Contract (lint green), 4.12 Scope Check, 4.13 Task Design (not triggered: no new autonomous task).

1. **Premise corrected.** The first draft said committed content cannot carry a config. Measured false: a committed embedded bare repository is a carrier in a plain clone (git's own manual documents the attack for `safe.bareRepository`). Severity stays `single-user incident` but the trigger is now "repo content plus one approved `cd`", i.e. prompt-injection-by-README, no agent write needed.
2. **Control order inverted.** Env pin (primary, protected-scope, covers committed and text-built bare dirs) > closed grammar > `.git` file-tool guard (covers a planted real `.git/config`).
3. **Grammar verified before it is written into code.** The Phase 2 alternation was executed against 17 positives and 37 negatives (every exec-requesting flag, `--flag=value`, combined, abbreviation, attached-value `-Sx`, `-Oorder`) with zero mismatches, and three ReDoS probes (60-token failing tails) ran in under 0.1 ms.
4. **New build-time gate.** The pin does nothing on git older than 2.38, so the Dockerfile asserts the image's git version at build time (Phase 4).
5. **Reconsider-on-evidence.** The earlier ruling (`.git`-component guard) was widened twice by new measurements; all three rulings are in decision-challenges.md.

## Research Insights

### Premise Validation (Phase 0.6)

- `#9600` OPEN (title: safe-bash git log/diff/show --ext-diff auto-approves and executes repo-config diff.external). `#9601` OPEN epic. No merged PR closes either. Collision pre-check: only this branch's draft PR #12485 names `9600`; foreign `test-all.sh` processes belong to unrelated worktrees.
- Cited surface verified on `origin/main` (worktree == origin/main for the file): `safe-bash.ts` carries `new RegExp(String.raw\`^git\s+(log|diff|show)(?:\s+${PATH_TOKEN})*\s*$\`)` as three separate patterns and `FILE_WRITE_FLAG_DENYLIST = /(?:^|\s)--output(?:=|\s|$)/`. `isBashCommandSafe("git diff --ext-diff")` is true on main (issue claim holds).
- ADR corpus check (mechanism = "close config carriers"): ADR-050 amendment 2026-09-24 (#8623) already states the invariant "tenant workspace content - the worktree and its `.git` - is untrusted input" and records that the SDK Bash sandbox deny list covers `.git/hooks` and `.git/config` but not `.git/info/attributes`, objects or refs. ADR-284 (hosted must-ask lane, `bash_autonomous`) places the safe-bash allow BEFORE the destroy-ask lane and before the autonomous bypass, so a safe-bash false-positive skips the pre-acknowledgement disclosure hold and non-autonomous review cards. No ADR rejects the chosen mechanisms.
- Severity measured, not assumed: `autoAllowBashIfSandboxed:false` (`agent-runner-sandbox-config.ts`), so an approve skips only the card; execution stays inside bwrap. Exposure is concentrated in workspaces with `bash_autonomous=false` or not yet acknowledged (autonomous workspaces already approve non-blocklisted Bash). A config carrier is required, and two are measured: (a) a bare repository committed into the connected repo (untrusted input; reached by the approved `cd <dir> && git ...`), and (b) a file-tool write: `canUseTool` has no `.git` handling and `isPathInWorkspace` allows `<workspace>/.git/config` (CLI-side block unmeasured). A real `.git/config` cannot arrive through clone or commit. Git manual, `safe.bareRepository`: "This will protect you from attacks that involve cloning a repository that contains a bare repository and running a Git command within that directory", and "This config setting is only respected in protected configuration ... This prevents untrusted repositories from tampering with this value."
- Mechanism minimality (ADR corpus): ADR-050's 2026-09-24 amendment records the untrusted-workspace invariant but only for server-side tools; no ADR addresses the agent's own git invocation, so this PR extends rather than reverses a decision.

### Falsifier results (real git 2.56.0, temp repo, helpers append a tag to a marker file)

Planted: `diff.external`, `diff.<drv>.textconv` (+ `.gitattributes` and, separately, `.git/info/attributes`), `core.fsmonitor`, `filter.<n>.clean`, `gpg.program` (a hand-built commit object with a `gpgsig` header).

| Form (all with planted config) | Executes? | Channel |
|---|---|---|
| `git status` | yes | fsmonitor |
| `git diff`, `git diff HEAD~1`, `git diff -- f`, `git diff -p`, `-U3`, `--word-diff`, `--exit-code` | yes | ext-diff (+ fsmonitor, filter) |
| `git diff --ext-diff` | yes | ext-diff |
| `git diff --no-ext-diff` | yes | textconv |
| `git diff --textconv` / `--no-textconv` / `--text` | yes | ext-diff |
| `git diff --no-ext-diff --no-textconv` (+ `--stat`) | yes (worktree) | fsmonitor, filter.clean |
| `git diff --stat`, `--name-only`, `--cached`, `--staged` (worktree/index) | yes | fsmonitor (+ filter on worktree) |
| `git diff A B --stat` (two commits) | no | inert |
| `git log` (no patch), `--oneline -5`, `--stat`, `--name-only`, `--graph`, `--raw` | no | inert |
| `git log -p`, `--patch`, `--cc`, `-c`, `-S x`, `-G x`, `--textconv` | yes | textconv |
| `git log -p --ext-diff`, `git show --ext-diff` | yes | ext-diff |
| `git show HEAD`, bare `git show` | yes | textconv |
| `git show --stat`, `--name-only`, `-s`, `HEAD:path`, `--no-ext-diff --no-textconv` | no | inert |
| `git log|show --show-signature` on a signed commit | yes | gpg.program |
| `git rev-parse ...`, `git branch ...`, `git config --get ...` | no | inert |
| `git -c core.fsmonitor=false status` / `diff --no-ext-diff --no-textconv HEAD~1` | status no; diff yes | filter.clean cannot be pinned by any flag |
| `GIT_ATTR_SOURCE=<empty tree>` | does not help | `.git/info/attributes` still applies |
| `cd evil && git diff HEAD~1 HEAD` where `evil/` is text files only (HEAD, config, objects/info/alternates, refs/heads/main, info/attributes) | yes | bare-repo discovery carrier, no `.git` component |
| same with `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=explicit` | no (git refuses) | pin closes it |
| `evil/` COMMITTED into the source repo (HEAD, config, objects/info/alternates = `../../.git/objects`, refs/heads/main), then `git clone`, then `cd clone/evil && git diff HEAD~1 HEAD` | yes | embedded bare repo, repo content only |
| same with the pinned env | no (git skips the bare dir, uses the outer repo: `Could not access 'HEAD~1'`) | pin closes it |
| unique-prefix abbreviations `--ext`, `--ext-d`, `--textc`, `--outp`, `--no-ext` | rejected by git (rc 128/129) | not an exec channel on 2.56 |
| `--output=F`, `--output F` | writes F | already denylisted; `--output-indicator-*` is not a write |
| `-O<orderfile>` | reads a file only (reorder oracle) | no exec, no write |

Consequences: a flag denylist is insufficient (bare reads execute); abbreviations are not live on 2.56, but the runtime image's git (Debian apt, version unmeasured) must not matter, which is what a closed grammar buys; `git status` is the same class as the issue (fsmonitor), so it is in scope with no verb change.

### Institutional learnings applied

- `2026-05-05-cc-permissions-bash-allowlist-hardening.md` and `2026-05-19-llm-bash-allowlist-network-verbs-dual-defense-and-cross-reconcile.md`: allowlists need a dual defense and reconciliation across consumers.
- #9555 comment in `safe-bash.ts` (`git branch`): measured positive/negative tables against real git, `-q`-style quiet repair flags excluded. Same method here.
- Single-branch token alternation to avoid ReDoS (#4868): the new grammar must stay one non-overlapping alternation per token; the existing ReDoS pin test must still pass.

### Property List and Cut List (Phase 0.6b)

Properties: (P1) an auto-approved git read cannot be made to run a repo-config helper by a flag the agent chooses; (P2) the agent cannot plant the config carrier through file tools or repo discovery; (P3) ordinary reads (`git status`, `git diff HEAD~1`, `git log --oneline -5`, `git show HEAD`, `--stat`, `--name-only`) stay approved; (P4) a denied form reaches the review card, not a hard deny; (P5) the PR reports the falsifier result and closure state honestly.

Cut list: command rewrite via `updatedInput` (buys P1 for bare reads; cannot pin `filter.*.clean`; no precedent; the carrier controls cover P2 instead). Host-side config key check at approval time (TOCTOU, async; same property covered by P2 controls). A flag *denylist* for `--ext-diff` (insufficient per the table). `git -c`/`--git-dir`/`--bare`/env-prefix forms need no new work: the regexes start at `git\s+(log|diff|show|status)` so they already fall to the card; a test pins that.

## Research Reconciliation - Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: "add `--ext-diff` to a per-verb denylist" | Bare `git diff`/`git show HEAD`/`git status` execute a planted config; denylist leaves them. | Closed grammar + carrier closure (CTO ruling). |
| Issue: "`GIT_EXTERNAL_DIFF` env not expressible" | True: regexes begin at `git`, `=` in PATH_TOKEN does not help an env prefix. | Add a regression test only. |
| Brief: "unique-prefix abbreviations such as `--ext`, `--textc`" | git 2.56 rejects them for diff/log/show. | Record as measured-not-live; grammar rejects regardless of git version. |
| Brief: `--output` "already denylisted" | Confirmed; stays as a second layer behind the closed grammar. | Keep `FILE_WRITE_FLAG_DENYLIST` unchanged. |
| Brief acceptance (2): `git diff HEAD~1`, `git show HEAD` stay approved AND every executing form is false | These two execute under a planted config. | Reconciled: approval is kept; execution requires a carrier, which this PR closes. The test asserts exact membership of the "approved but carrier-dependent" set so it cannot grow silently. |

## Open Code-Review Overlap

- #3820 (safe-bash: extend allowlist with grep/find/rg/sort/uniq) touches `safe-bash.ts`: **Acknowledge** - different concern (new verbs); any future widening must follow the table-per-flag rule recorded in the comment this PR adds.
- #3453 (verify `isPathInWorkspace` symlink coverage) touches `sandbox.ts`: **Acknowledge** - the carrier guard reuses the resolver without editing it and adds its own symlinked-`.git` test.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "safe-bash must not auto-approve git log\|diff\|show forms that execute repo-config helpers" | Phase 2 (closed grammar), Phase 3-4 (carriers) | mapped |
| 2 | "Falsifier test with real git first" | Phase 1 | mapped |
| 3 | "keep ordinary read forms approved" | Phase 2 positives, AC4 | mapped |
| 4 | "audit neighbouring knobs (--output, --textconv, -O<orderfile>)" | Falsifier rows + grammar exclusions, AC6 | mapped |
| 5 | "Closes #9600 only if the falsifier shows the hole fully closed" | PR body rule, AC10 | mapped |
| 6 | "if bare `git diff` executes under a planted config, a flag denylist is not enough: the plan states which fix it chooses" | Overview + decision-challenges.md | mapped |
| 7 | "a denied form falls to the review card, not a hard deny" | Phase 2 (regex miss = card) | mapped |
| 8 | "No flags or migrations" | no flag, no migration anywhere in the file lists | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Closed flag grammar | "if bare `git diff` executes under a planted config, a flag denylist is not enough" | asked |
| `git status` in the falsifier and fix | "audit neighbouring knobs" | asked |
| Carrier guard in `sandbox-hook.ts` and `permission-callback.ts` | "measure real severity, do not assume" | asked (CTO-ruled) |
| Env pin in `agent-env.ts` | "pinning git config at execution" | asked (CTO-ruled) |
| Near-miss style telemetry for git grammar fall-through | "its UX cost" | asked (UX cost must be measurable) |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform/server` (+ its tests)
- Planned files: 8 edit, 3 create | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent that either stalls on review cards for everyday reads (grammar too tight) or, if the carrier controls are mis-wired, a file-tool deny message when the agent edits a path containing `.git`.
- **If this leaks, the user's workflow is exposed via:** an untrusted connected repo that commits an embedded bare repository (config keys `core.fsmonitor`, `diff.external`, `filter.*.clean`) which a prompt-injected agent enters with the approved `cd`, or a prompt-injected agent planting `.git/config` through file tools, then an auto-approved `git status`/`git diff` executing attacker-chosen code inside that user's workspace sandbox with no review card.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** Ruled by CPO agent, 2026-11-09: one prompt-injected session in one workspace, silent card-skip, sandbox-contained and not cross-tenant, so not `aggregate pattern`; not `none` because the bypass is silent.

CPO sign-off recorded (decision-challenges.md). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two rulings (fix selection; bare-repo carrier follow-up) recorded in decision-challenges.md. Ship carrier closure + closed grammar; env pin and `.git`-component guard unconditional; `Ref #9600`; residual list mandatory in the PR body.

### Product (CPO)

**Status:** reviewed
**Assessment:** Threshold `single-user incident`; no UX concern with a plain, non-alarming hard deny on `.git` file-tool writes; deny must be mirrored to a log/Sentry event; bare reads unchanged. No UI surface (no new page/component): Product/UX gate not triggered.

GDPR gate: no schema, migration, auth-flow or API-route file is touched and no personal-data processing is added; skipped. Legal, marketing, finance, sales, support, operations: no implications.

## Architecture Decision (ADR/C4)

Not a new decision: it applies the existing ADR-050 (2026-09-24 amendment) invariant that the tenant workspace and its `.git` are untrusted. Work-phase task: add a short dated amendment line to that invariant paragraph in `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` stating that file tools now refuse `.git` paths and that `safe.bareRepository=explicit` is pinned in the agent env, so the recorded sentence "the built-in deny list covers `.git/hooks` and `.git/config`" is not read as the whole control. C4: no container, actor or relationship changes (no new substrate, vendor or access edge; the change is inside the existing agent-runner containment). Work phase confirms by running `plugins/soleur/test/c4-count-parity.test.sh` green and reading the three `.c4` files for a falsified description; a falsified one is fixed in-PR.

## Implementation Phases

### Phase 1 - Falsifier first (RED before any fix)

Create `apps/web-platform/test/safe-bash-git-config-exec.test.ts`:

- Hermetic temp repo under `os.tmpdir()` (no read outside `apps/web-platform`, so it stays out of `REPO_WIDE_SUITES`; `repo-wide-containment.test.ts` verifies). Construct the git env with the project's fixture-env pattern (see `test/ensure-workspace-repo-ancestry-real-git.test.ts`): no inherited `GIT_DIR`/`GIT_INDEX_FILE` (vitest globalSetup tripwire exits rc=97 otherwise), `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, pinned identity.
- Plant `diff.external`, `diff.evil.textconv` + `.gitattributes`, `core.fsmonitor`, `filter.zz.clean`, `gpg.program` with a hand-built signed commit (`git hash-object -t commit -w --literally`), a dirty worktree, a text-built bare dir (`evil/`), and a source repo that COMMITS an embedded bare repo which the test then `git clone`s (the committed carrier; commit on a non-default branch of the fixture repo, the fixture env already pins identity).
- A `ROWS` table `{cmd, executes: set of channels, approved: boolean}`. Test A runs every row for real and asserts the observed channel set equals the table (a git upgrade that changes behaviour turns it RED; the test title prints `git --version`). Test B asserts `isBashCommandSafe(cmd) === approved` for every row. Test C (the invariant): any approved row that executes must be in the exact `CARRIER_DEPENDENT_APPROVED` set (`git status`, `git diff`, `git diff HEAD~1`, `git diff HEAD~1 --stat`, `git show HEAD`, `git log --oneline -5` is NOT in it because it is inert), and no approved row may contain an exec-requesting flag.
- Rows include every form in the falsifier table above, the abbreviations (recorded, not asserted on git's answer, but asserted `approved: false`), `--flag=value` and combined forms (`git log -p --ext-diff`, `git diff --ext-diff=x`, `git show --ext-diff HEAD`, `git diff HEAD~1 --textconv --stat`, `-O/etc/hostname`, `-Oorder`).
- Expected at commit time: Test B RED on the pre-fix `safe-bash.ts` for `--ext-diff`, `--textconv`, `-p`, `-S`, `-G`, `-O*`, `--show-signature`, abbreviations.

### Phase 2 - Closed flag grammar in `safe-bash.ts`

Replace the three free-tail patterns with one builder shared by `log|diff|show`. Token alternation (non-overlapping; positional tokens start with a non-dash, flags with a dash, so no ambiguity and no ReDoS):

```
GIT_READ_FLAG = (?:--oneline|--stat|--name-only|--name-status|--numstat|--shortstat|--summary|--raw|--graph|--no-patch|-s
  |--cached|--staged|--no-ext-diff|--no-textconv|--no-color|--abbrev-commit|--decorate|--all|--first-parent|--no-merges|--merges
  |--reverse|-\d+|-n\s+\d+|--max-count=\d+|--(?:since|until|author|grep)=PATH_TOKEN|--diff-filter=[A-Za-z]+|--)
pattern = ^git\s+(?:log|diff|show)(?:\s+(?:GIT_READ_FLAG|(?!-)PATH_TOKEN))*\s*$
```

Admission rule recorded in a code comment: a flag is added only with a real-git table row showing it never requests an exec channel and a safe-bash test; a flag is never admitted by prefix. `--output` denylist stays as the second layer. `git status` stays bare-only. Existing positives (`git log --oneline -5`, `git log -n 5`, `git diff HEAD~1 --stat`, `git show HEAD --name-only`, `git status`, `git diff HEAD~1`, `git show HEAD`) stay green; ReDoS pin test stays green.

UX cost (stated in the PR body): forms that now reach the review card are `git log|show -p/--patch`, `-S/-G`, `git diff -U<n>`, `--word-diff`, `-w`, `--color-words`, `--textconv`, `--show-signature` and anything with a flag outside the list. Common reads (`status`, `diff`, `diff <rev>`, `show <rev>`, `log --oneline -N`, `--stat`, `--name-only`) are unchanged. Telemetry: extend the existing near-miss block in `permission-callback.ts` so a command matching `^git\s+(log|diff|show)\b` that misses `isBashCommandSafe` emits one budgeted `safe-bash-git-flag-fallthrough` event (same per-context budget and dedupe as `safe-bash-near-miss`, extra field = the verb plus the first rejected flag, sliced to 32 chars), so the cost is measured and the list can be widened by evidence.

### Phase 3 - Carrier guard (file tools)

Create `apps/web-platform/server/git-carrier-guard.ts` exporting `GIT_CARRIER_WRITE_TOOLS = ["Write","Edit","NotebookEdit"]` and `gitCarrierTouched(toolName, toolInput, workspacePath): boolean`. It reads `file_path` and `notebook_path`, anchors a relative path on the workspace, resolves the deepest existing ancestor with `realpath` and appends the remainder (so a not-yet-existing `.git/config` and a symlink pointing at `.git` are both seen), and returns true when any component of the lexical OR resolved path equals `.git` case-insensitively. A non-string location value is treated as touching (fail closed). Wire it in:

- `sandbox-hook.ts` (`createSandboxHook`, after the workspace-escape check) - deny with `systemMessage`/`permissionDecisionReason`, plain wording: "Git configuration and hooks are protected. Run `git config` through Bash and you will be asked to approve it."
- `permission-callback.ts` file-tool branch (after `pathFieldsEscape`) - same deny, defense in depth, `logPermissionDecision(..., "deny", "git-carrier-path")`.
- Both emit a budgeted `git-carrier-write-denied` event (op name, tool name, which component class matched; never the file contents) through the existing `warnSilentFallback` helper so each deny reaches Sentry and the log.

Reads (`Read`, `Grep`, `Glob`, `LS`) are untouched. Verify the call sites by grepping every `createSandboxHook` and `canUseTool` file-tool consumer (cc-dispatcher and agent-runner-query-options both build on them) so no path bypasses the guard.

### Phase 4 - Env pin (primary control; implement and test this phase first)

In `apps/web-platform/server/agent-env.ts` `buildAgentEnv`, outside the `gitAskpassScriptPath && gitInstallationToken` block: set `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, and `safe.bareRepository=explicit` via `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_<n>`/`GIT_CONFIG_VALUE_<n>`, appending after any count already present in the allowlisted ambient env (never overwrite). The ambient allowlist must not be able to supply `GIT_CONFIG_*` after the pin (set after the allowlist loop). Check the existing `GIT_CONFIG_NOSYSTEM`/`GLOBAL` handling in `git-auth.ts` and `git-hardened-env.ts` for conflicts (`EXTRA_ENV_KEYS` refuses `GIT_CONFIG_COUNT` for the isolated push env; the agent env is a different builder). Risk to check: sessions without git-auth previously inherited global gitconfig identity; workspace identity is seeded into `.git/config` (`git-config-atomic.ts`), so confirm with `agent-env*.test.ts` and a commit-identity test before relying on it.

Build-time version gate: in `apps/web-platform/Dockerfile` (runner stage, after the apt step that installs git) add a `RUN` assertion that `git --version` is 2.38 or later and fail the build otherwise; the pin is inert on older git and `GIT_CONFIG_COUNT` itself needs 2.31. Record the image's measured version in the PR (AC11). Protected-scope proof: a real-git test commits an embedded bare repo whose own `config` sets `[safe] bareRepository = all`, clones it, and shows that under the pinned env git still skips the bare dir (repo-local config cannot undo the pin). Submodule check: a committed submodule's gitdir is reached through a `.git` FILE the pin does not govern; Phase 1 adds one real-git submodule row (`git submodule add` of a local repo, then `cd sub && git diff`) and records whether config in `.git/modules/<n>/config` can arrive by clone alone (expected no: modules config is written locally).

### Phase 5 - Tests for the controls

- `apps/web-platform/test/git-carrier-guard.test.ts`
- `apps/web-platform/test/dockerfile-git-version-floor.test.ts` (text test pinning the 2.38 floor in the Dockerfile; follows the `dockerfile-runner-ssh-client.test.ts` pattern): pure helper (nested `sub/.git/config`, `.GIT/hooks/x`, `.git` as a gitdir-pointer file, symlink `g -> .git` then `g/config`, relative `../` escapes, not-yet-existing target, non-string input, `Read` unaffected, `.gitignore`/`.github/` not matched), hook deny shape, `canUseTool` deny, plus a measurement test recording the pre-fix behaviour (Write of `<ws>/.git/config` allowed) as the RED row.
- Extend `safe-bash.test.ts`: grammar positives and negatives from the table; env-prefix and global-option forms (`GIT_CONFIG_COUNT=0 git status`, `GIT_DIR=x git log`, `git -c core.fsmonitor=x status`, `git --git-dir=x log`, `git --bare log`) are rejected; `&&`-chain with one exec-flag segment is rejected as a whole.
- Extend `agent-env.test.ts`: pin present for every auth scheme with and without git-auth; ambient `GIT_CONFIG_COUNT` is appended to, not overwritten.
- Real-git proof for the env pin inside the Phase 1 file: with the pinned env, `cd evil && git diff HEAD~1 HEAD` is refused and writes no marker.

### Phase 6 - ADR amendment and PR body inputs

ADR-050 amendment line (see Architecture Decision). Prepare the PR body text from the template below; do not push (planning run).

## Guard Contract

### Guard 1 - git read grammar closed over exec-requesting flags

**Property.** No command that `isBashCommandSafe` approves contains a flag that requests a repo-config helper (`--ext-diff`, `--textconv`, `-p`/`--patch`, `-S`, `-G`, `--show-signature`), a file write (`--output*`) or an order-file read (`-O*`), in any spelling, combination or `&&` segment.

**Assembly.** The chokepoint is `isSafeSingleSegment` stage 2 over `SAFE_BASH_PATTERNS`, reached from `isBashCommandSafe` for every `&&` segment; three verbs (`log`, `diff`, `show`) flow through one shared builder, and `git status` plus the remaining `git` verbs (`branch`, `rev-parse`, `config --get`) are separate patterns in the same array. Consumers: `permission-callback.ts` (`isBashCommandSafe` call) and the re-export; the dispatcher test `cc-dispatcher-bash-safe-allowlist.test.ts`. The test enumerates `SAFE_BASH_PATTERNS` itself so a new git pattern added later is checked by the same table.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `--ext-diff` (or `-p`) to `GIT_READ_FLAG` | RED (Test B: row approved true where table says false) |
| 2 | Make the pattern loop in the test iterate zero patterns or filter to zero `git` patterns (guard's own dispatch) | RED (floor: at least 5 git patterns exercised and at least 40 rows run, asserted) |
| 3 | Add a second git pattern after the compliant first, e.g. `^git\s+log(?:\s+PATH_TOKEN)*$` back in the array | RED (rows run against `isBashCommandSafe`, not the first matching pattern) |
| 4 | Admit a flag by prefix (`--ext` style alternation, `--ext[\w-]*`) | RED (abbreviation rows) |
| 5 | Admit `--stat` followed by `=PATH_TOKEN` generally (`--[\w-]+=PATH_TOKEN`) | RED (`--ext-diff=x`, `--output=x` rows) |
| 6 | Move the `&&` split after the flag check (segment 2 skips grammar) | RED (`git log --oneline && git diff --ext-diff` row) |
| 7 | Harness: delete the planted `diff.external` from the fixture | RED (Test A: observed set no longer equals the table; vacuous fixture detected) |

Must-PASS (harness) rows that are NOT the canonical: `git log --oneline -5 HEAD~2..HEAD`, `git diff main...HEAD --name-only`, `git show HEAD:apps/web-platform/package.json`.

**Anchor.** The `CARRIER_DEPENDENT_APPROVED` set and the table live in the test; weakening the grammar and the table in one diff passes the consistency check, so the real-git Test A (observed behaviour, not the table) is the independent anchor and the ADR/PR body lists the admitted flags.

### Guard 2 - no file-tool write reaches a `.git` component

**Property.** No `Write`/`Edit`/`NotebookEdit` call whose lexical or symlink-resolved path has a `.git` component (any case, any depth) is allowed by either enforcement point.

**Assembly.** Two enforcement points flow through one helper: `createSandboxHook` (PreToolUse) and the `canUseTool` file-tool branch in `permission-callback.ts`; both call `gitCarrierTouched`. Tool set = `GIT_CARRIER_WRITE_TOOLS`; path fields = `file_path`, `notebook_path` (the same `PATH_FIELDS` the existing `pathFieldsEscape` quantifies over). A test greps the repo for every `createSandboxHook(` and file-tool `canUseTool` registration and asserts each routes through the helper.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the helper match only `<workspace>/.git` (not nested) | RED (`sub/.git/config` row) |
| 2 | Remove the call from `canUseTool` only | RED (canUseTool deny test) |
| 3 | Remove the call from `sandbox-hook.ts` only | RED (hook deny test) |
| 4 | Drop case-insensitivity | RED (`.GIT/config` row) |
| 5 | Check only the lexical path, not the resolved one | RED (symlink row) |
| 6 | Add `MultiEdit`-like second tool to the matrix but not to the set | RED (set-vs-`FILE_TOOLS` write-class parity check) |
| 7 | Harness: guard test creates no symlink fixture | RED (fixture-presence assertion) |

Must-PASS rows: `Write` to `src/.github/workflows/x.yml`, `.gitignore`, `docs/git-notes.md`.

**Anchor.** The deny is the only barrier on this path (CLI-side block unmeasured); the PR body lists that as residual rather than claiming a second layer.

### Guard 3 - agent env pins bare-repo discovery

**Property.** Every agent environment built by `buildAgentEnv` carries `safe.bareRepository=explicit`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, regardless of auth scheme or git-auth presence, and ambient values cannot displace them.

**Assembly.** Single builder `buildAgentEnv`; consumers `agent-runner-query-options.ts` and `cc-dispatcher.ts` env construction (grep both, and any direct `process.env` pass-through to the SDK); the runtime image's git (Dockerfile) as the second member the property depends on, because the pin is a no-op below git 2.38.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the pin back inside the git-auth `if` | RED (no-git-auth session test) |
| 2 | Overwrite instead of append when ambient `GIT_CONFIG_COUNT` exists | RED (ambient count test) |
| 3 | Loop over zero auth schemes in the test | RED (floor on schemes covered) |
| 4 | Set the key to `all` | RED (real-git refusal test) |
| 5 | Add a second consumer path that skips the builder | RED (consumer grep test) |
| 6 | Drop the pin entirely (keep NOSYSTEM/GLOBAL) | RED (committed-then-cloned bare repo row executes the marker) |
| 7 | Weaken the Dockerfile assertion to any git version | RED (Dockerfile text test pins the `2.38` floor) |
| 8 | Harness: fixture clones nothing (embedded repo never committed) | RED (fixture asserts `git ls-files evil/config` in the source repo and `git rev-parse --is-bare-repository` true inside the clone before the pin is applied) |

Must-PASS (non-canonical) row: a repo containing a directory that merely LOOKS like a bare repo but is run with `git -C`-free commands from the outer repo root still works (`git status` at the root), so the pin does not break ordinary use.

## Observability

```yaml
liveness_signal:
  what: "pino sec:true decision log lines and the budgeted git-carrier-write-denied / safe-bash-git-flag-fallthrough warnSilentFallback events from the existing permission path"
  cadence: "per tool call"
  alert_target: "Sentry feature cc-permissions (existing), no new alert; frequency reviewed from the event counts"
  configured_in: "apps/web-platform/server/permission-callback.ts and apps/web-platform/server/sandbox-hook.ts"

error_reporting:
  destination: "Sentry via warnSilentFallback (existing helper used by safe-bash-near-miss)"
  fail_loud: "a denied .git write returns a deny with a plain message to the agent and emits git-carrier-write-denied; a guard throw fails closed (deny)"

failure_modes:
  - mode: "carrier guard blocks a legitimate flow (false positive on a path with a .git component)"
    detection: "git-carrier-write-denied event with the matched component class; sandbox-hook is a blind-surface-adjacent path so the event carries tool name, which enforcement point fired (hook or canUseTool) and whether the match was lexical or symlink-resolved"
    alert_route: "Sentry cc-permissions issue group"
  - mode: "grammar too tight - everyday git reads reach the card"
    detection: "safe-bash-git-flag-fallthrough events (verb + first rejected flag) per context, budgeted"
    alert_route: "Sentry cc-permissions; widen the list only with a real-git table row"
  - mode: "env pin missing in a session (builder bypassed)"
    detection: "agent-env test plus consumer-grep test fail in CI; no runtime signal is added for this"
    alert_route: "CI failure on the PR"

logs:
  where: "web-platform container pino logs (existing logPermissionDecision lines), Sentry events"
  retention: "existing log pipeline retention, unchanged"

discoverability_test:
  command: rg -c git-carrier-write-denied apps/web-platform/server
  expected_output: sandbox-hook.ts
```

## Files to Edit

- `apps/web-platform/server/safe-bash.ts` - closed grammar builder for `log|diff|show`, admission-rule comment, header comment update.
- `apps/web-platform/server/sandbox-hook.ts` - call `gitCarrierTouched`.
- `apps/web-platform/server/permission-callback.ts` - call `gitCarrierTouched` in the file-tool branch; git fall-through telemetry in the near-miss block.
- `apps/web-platform/server/agent-env.ts` - env pin outside the git-auth block.
- `apps/web-platform/Dockerfile` - build-time assertion that the runner image's git is 2.38 or later (the pin needs it).
- `apps/web-platform/test/safe-bash.test.ts` - grammar positives/negatives, env-prefix and global-option rejections.
- `apps/web-platform/test/permission-callback-safe-bash.test.ts` - keep the existing positive list; add exec-flag negatives at the callback level (card, not deny).
- `apps/web-platform/test/agent-env.test.ts` - pin assertions.
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` - dated amendment line (work phase).

Never edited: `apps/web-platform/server/dsar-export-allowlist.ts`; no file for issue 10613.

## Files to Create

- `apps/web-platform/server/git-carrier-guard.ts`
- `apps/web-platform/test/safe-bash-git-config-exec.test.ts` (the real-git falsifier)
- `apps/web-platform/test/git-carrier-guard.test.ts`
- `apps/web-platform/test/dockerfile-git-version-floor.test.ts` (text test pinning the 2.38 floor in the Dockerfile; follows the `dockerfile-runner-ssh-client.test.ts` pattern)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 Falsifier committed first (RED on pre-fix `safe-bash.ts`), table pins the observed channel set per row with `git --version` in the title.
- [ ] AC2 `isBashCommandSafe` is false for every row that carries an exec-requesting flag, in `--flag=value`, combined, abbreviated and `&&`-segment spellings.
- [ ] AC3 The approved-and-executing set equals `CARRIER_DEPENDENT_APPROVED` exactly (Test C); no approved row contains an exec-requesting flag.
- [ ] AC4 Existing `permission-callback-safe-bash.test.ts` cases stay green; `git status`, `git diff HEAD~1`, `git log --oneline -5`, `git show HEAD`, `--stat`, `--name-only` stay approved; the ReDoS pin test stays green.
- [ ] AC5 A denied git form reaches the review card (callback returns the ask path), not a hard deny.
- [ ] AC6 Neighbouring knobs audited with rows: `--output` (write, denylisted), `-O<orderfile>` (read-only, rejected by grammar), `--textconv`, `--show-signature`, `git status` fsmonitor.
- [ ] AC7 Carrier guard refuses Write/Edit/NotebookEdit on any `.git` component at both enforcement points (nested, case, symlink, gitdir-pointer file); reads unaffected; deny mirrored to an event.
- [ ] AC8 Env pin present for every auth scheme; real-git tests show (a) a text-built bare dir, (b) a committed-then-cloned embedded bare repo, and (c) a bare repo whose own config sets `safe.bareRepository=all` are all refused/skipped under the pinned env; Dockerfile build asserts git >= 2.38.
- [ ] AC9 `bunx tsc --noEmit` and `vitest run` for the touched test files pass; `lint-guard-contract.py` passes on this plan.
- [ ] AC10 PR body: `Ref #9600` (not `Closes`); falsifier result stated honestly, including that bare `git diff`/`git status` still execute a planted config; residual list (CLI-side `.git` write block unmeasured; HOME/system gitconfig in sessions before the pin lands; Bash-created dirs that reach the card and rely on human review; runtime-image git version until measured; submodule gitdirs; non-bare embedded repos only via the guarded file-tool path; env and discovery overrides `GIT_DIR`, `-c`, `--git-dir` rely on safe-bash rejecting them; bare `git diff` and `git status` still run any config that is present); UX cost; `Changelog` section; `- **Brand-survival threshold:** single-user incident`; a `Follow-ups not filed` line with: "9b residual (a) object-store swap after the walk; re-evaluate before the approval-queue flag leaves the Jikigai canary or when the sandbox-write probe result is recorded."
- [ ] AC11 `Closes #9600` is allowed only if, before ship, these are measured and recorded in the PR: the built runtime image's `git --version` is 2.38 or later and the Phase 1 table plus Phase 4 pin tests pass on it; the home and system gitconfig are pinned (or shown not tenant-writable); and the CLI-side `.git` write behaviour is measured or the guard is recorded as the sole barrier. Otherwise stays `Ref`.

## Test Scenarios

- Given a planted `diff.external`, `git diff --ext-diff` is not approved: `isBashCommandSafe` is false and the callback takes the ask path.
- Given a planted config, when the agent Writes `<ws>/.git/config`, then both enforcement points deny with the plain message and an event.
- Given a text-built `evil/` bare dir, when `cd evil && git diff HEAD~1 HEAD` runs under the pinned env, then git refuses and no marker is written.
- Given `git log --oneline -5 && git diff --textconv`, the whole command is not approved.
- Given `GIT_CONFIG_COUNT=0 git status`, not approved (regexes start at `git`).

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails deepen-plan; this one carries all three required lines.
- Real-git tests run under vitest: spawn git with a constructed env (no `GIT_DIR`/`GIT_INDEX_FILE`) or the tripwire exits rc=97. The fixture helper from the plugin tests is under `plugins/soleur/test/lib`; the web-platform test must not import across the app boundary (repo-wide containment) - copy the small env construction pattern from `ensure-workspace-repo-ancestry-real-git.test.ts`.
- Do not widen the grammar with a prefix match or a generic `--[\w-]+=PATH_TOKEN`; every admitted flag needs a table row.
- Do not claim "closed" in any public text before AC11 evidence exists (no security claim ahead of a measured control).
- The discoverability probe above is a static presence check; the behavioural proof is the committed tests.

## References

- Issue #9600, epic #9601; ADR-050 (2026-09-24 amendment), ADR-284, ADR-093; `apps/web-platform/server/safe-bash.ts`, `permission-callback.ts`, `sandbox-hook.ts`, `agent-env.ts`.
