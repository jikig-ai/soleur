# Interface Contract — feat-one-shot-9555-9559-safe-bash-kb-search

Plan: `knowledge-base/project/plans/2026-10-06-fix-safe-bash-git-branch-support-kb-search-plan.md` (read it in full — it is the authority).

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `apps/web-platform/server/safe-bash.ts`, `plugins/soleur/skills/kb-search/SKILL.md`, `apps/web-platform/server/support-directive.ts`, `apps/web-platform/server/cc-dispatcher.ts` |
| Agent 2 (Tests) | `apps/web-platform/test/safe-bash.test.ts`, `apps/web-platform/test/permission-callback-safe-bash.test.ts`, `apps/web-platform/test/support-directive.test.ts`, `plugins/soleur/test/kb-search-support-path.test.sh` (new file) |

Lead (neither agent — written after integration): `knowledge-base/engineering/architecture/decisions/ADR-113-*.md`, `knowledge-base/engineering/architecture/diagrams/model.c4`, `knowledge-base/engineering/architecture/diagrams/views.c4`, `knowledge-base/project/plans/2026-10-06-fix-safe-bash-git-branch-support-kb-search-plan.md` (checkbox flips).

## Public Interfaces

### 1. `isBashCommandSafe` — `git branch` contract (module `apps/web-platform/server/safe-bash.ts`)

The single existing entry `^git\s+branch(?:\s+PATH_TOKEN)*$` at `safe-bash.ts:131` is REPLACED by a closed flag set plus two arms (verbatim from the plan's Fix A):

```ts
// (Review correction, PR #9570 panel: the plan's single "read-only flag"
// set conflated list-FORCING flags with display modifiers — `-v`,
// `--sort=`, `--format=`, `--color`, `--column`, `--ignore-case`,
// `--abbrev` do NOT put git branch into list mode, so `git branch -v
// <name>` would still have auto-approved a CREATE. Verified against git
// 2.55; the shipped Arm 2 requires a forcing flag in the leading flag
// run.)
const GIT_BRANCH_LIST_FORCE = String.raw`(?:--list|--show-current|--all|--remotes|--contains|--no-contains|--merged|--no-merged|--points-at|-[arv]*[ar][arv]*)`;
const GIT_BRANCH_READ_FLAG = String.raw`(?:${GIT_BRANCH_LIST_FORCE}|-[v]+|--verbose|--sort=${PATH_TOKEN}|--format=${PATH_TOKEN}|--abbrev(?:=\d+)?|--column|--no-column|--color(?:=${PATH_TOKEN})?|--no-color|--ignore-case)`;
// Arm 1: bare `git branch` or flag-only forms (incl. --show-current, -v).
new RegExp(String.raw`^git\s+branch(?:\s+${GIT_BRANCH_READ_FLAG})*\s*$`),
// Arm 2: leading flag run must contain ≥1 list-FORCING flag before any
// positional arg, then flags and non-dash args mix freely.
new RegExp(String.raw`^git\s+branch(?=\s+(?:${GIT_BRANCH_READ_FLAG}\s+)*?${GIT_BRANCH_LIST_FORCE}(?=\s|$))\s+${GIT_BRANCH_READ_FLAG}(?:\s+(?:${GIT_BRANCH_READ_FLAG}|(?!-)${PATH_TOKEN}))*\s*$`),
```

(Agent 1 keeps the plan's full comment block above the declaration; `-q` is deliberately absent from the flag set — quiet-create is a write modifier.)

`isBashCommandSafe(...)` must return:

- **true (allow):** `git branch`, `git branch -a`, `git branch -r`, `git branch -v`, `git branch -vv`, `git branch -av`, `git branch --list`, `git branch --list feat`, `git branch --show-current`, `git branch --merged main`, `git branch --contains HEAD~2`, `git branch --no-merged main`, `git branch --points-at HEAD`, `git branch --sort=-committerdate`, `git branch --ignore-case --list x`
- **false (deny → review-gate):** `git branch foo`, `git branch foo main`, `git branch -d foo`, `git branch -D foo`, `git branch --delete foo`, `git branch -m a b`, `git branch -M a b`, `git branch --move a b`, `git branch -c a b`, `git branch -C a b`, `git branch --copy a b`, `git branch -f foo`, `git branch -q foo`, `git branch -u origin/main foo`, `git branch --set-upstream-to=origin/main foo`, `git branch --unset-upstream foo`, `git branch --edit-description foo`, `git branch --list -d`, `git branch --list foo -D`, `git branch --list ../x`, `git status && git branch -d x` (whole command denied), and — review-added — every display-modifier + positional create (`git branch -v foo`, `-vv`, `--verbose`, `--sort=…`, `--format=…`, `--abbrev[=n]`, `--column`, `--no-column`, `--color[=w]`, `--no-color`, `--ignore-case`, `-v foo HEAD~0`, `-i`, `-t`, `foo --list`, `-l foo`)

`permission-callback-safe-bash.test.ts`: `git branch -d x` and `git branch feat-x` join the not-auto-approved list; `"git branch"` stays in SAFE_COMMANDS.

### 2. kb-search support-persona section (`plugins/soleur/skills/kb-search/SKILL.md`)

Agent 1 inserts a new section at the TOP of `## Execution` (before Phase 0), exactly per the plan's quoted block ("> **Support-persona path (no Bash).**" …) including the Phase→tool-path table. The literal string `Support-persona path (no Bash)` is the REQUIRED marker Agent 2's drift test greps for. Inside that section there must be NO fenced ```` ```bash ```` block and no line instructing a shell call. The `<!-- stage-2-paraphrase-union-v1 -->` marker and the `SENSITIVE_QUERY_REGEX` literal elsewhere in the file stay byte-identical (pinned by `kb-search-lockstep.test.sh`).

### 3. `SUPPORT_SYSTEM_DIRECTIVE` (`apps/web-platform/server/support-directive.ts`)

Agent 1 adds ONE directive sentence whose exact text is:

`kb-search answers through Read/Grep/Glob only — there is no shell in this chat.`

Agent 1 also corrects the stale comments at `support-directive.ts:16-17` and `:51-52` (the "Bash is KEPT because kb-search shells out" premise is falsified — the support path is tool-only now) and the stale "kb-search shells out" comment in `cc-dispatcher.ts` ~:2879. `SUPPORT_EXTRA_DISALLOWED_TOOLS` must still NOT contain `"Bash"` (pinned by the existing `.not.toContain("Bash")` assertion at `support-directive.test.ts:32`).

Agent 2 updates `support-directive.test.ts`: rename the stale title at :28 (`"…KEEPS Bash (kb-search shells out)"`) to the tool-only framing, and add an assertion that the directive matches `/Read.*Grep.*Glob|no shell/i`. All existing assertions stay.

### 4. New drift test (`plugins/soleur/test/kb-search-support-path.test.sh`)

Asserts: (i) `grep -F "Support-persona path (no Bash)"` hits in SKILL.md; (ii) no ```` ```bash ```` fenced block inside the support section (from the marker line to the next `##`/`###` heading — prose may legitimately name Bash); (iii) `plugins/soleur/knowledge-base/{INDEX.md,kb-tags.txt,kb-categories.txt}` exist non-empty. Conventions: owning EXIT trap BEFORE `source`ing `test-helpers.sh`; canonical `assert_fixture_dir` byte-copied from `plugins/soleur/test/test-helpers.sh` for any `mktemp -d` window; pass-count floor ≥3 written to the same counter the verdict reads; every negative row carries a positive control on the same input. Model it on an existing sibling (`plugins/soleur/test/kb-search-lockstep.test.sh`).
