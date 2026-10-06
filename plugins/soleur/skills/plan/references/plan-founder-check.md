# Founder-stated check (plan capture)

Linked from `plan/SKILL.md` step 2.13. Lets a founder state, in their own words and before work
starts, what shows a piece of work is done. The plan stores it as a `founder_check:` block under
`## Acceptance Criteria`; `soleur:preflight` Check 13 runs it later, in a step separate from the
work. Decision record: ADR-274. This file is the only place the block's YAML shape lives.

**Wording is a contract.** Print the pinned constants with `founder-check.py text <key>` (the
script, not this prose, is the source) and never paraphrase them. Every call below is
`python3 "${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/founder-check.py"`; start each Bash block
with the guard shown, which stops the call when the plugin root is unresolved. Never describe a
check more strongly than the pinned sentences do.

## When it runs

- **Interactive only.** Headless and one-shot runs ask nothing and write no block; a run with no
  block prints `founder-check.py text no-block` at ship and continues. Treat a run as headless
  unless the founder is present in this session. When unsure, headless.
- **After the plan's `## Acceptance Criteria` section is written, before Plan Review and
  `deepen-plan`.** The block is the last element of that section.
- **Never twice.** Before asking, run:

  ```bash
  : "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is unset; export it as the installed soleur plugin root, never a path inside this repository}"
  PREFLIGHT_TMP="$(git rev-parse --git-dir)"
  python3 "${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/founder-check.py" verify --base origin/main --no-pr --out "$PREFLIGHT_TMP/founder-check-verify.json"
  ```

  Then branch on `outcome`:
  - `OK`, `UNTRUSTED` or `CHANGED-SINCE-APPROVAL`: a block is frozen on this branch. **Import it
    verbatim** from `git show <freeze_sha>:<plan path>` (copy the `founder_check` fence unchanged)
    and do not re-ask. A re-run of this skill must never rewrite, reformat or drop an approved
    block.
  - `NO-BLOCK`: capture, below.
  - `FAIL` with `reason: no-freeze`: the block is written but was never frozen. Run the baseline
    and make the freeze commit (below). Do not re-ask.
  - any other `FAIL`: stop and print `detail`. Never overwrite a frozen block to clear it.

## The question and the first-use notice

Show `founder-check.py text first-use` on one screen **at every capture**, then ask
`founder-check.py text capture-question`. Offer a plain "I do not have a check for this" answer; it
records nothing. Store the founder's answer **verbatim** as `text`. Do not clean it up.

## Proposing the literal check

Propose a `command` (what runs) and an `expected` string (one literal substring of stdout; empty
means "exit 0 only"), and one plain sentence beside them saying what the command will do. The
founder approves the **exact text**, not a paraphrase: print `founder-check.py text approval-ask`
and record the founder's answer exactly as given in `approved_by`, with today's UTC date in
`approved_at`. Tell the founder up front what the check can and cannot do, so nothing surprises
them at ship:

- the check runs on this computer in a limited environment that can still use the network and read every file and the history in this project, so a command could send what it reads to any address; read the command before approving; a limited environment does not make a command harmless;
- the first word must be one of `curl bash grep rg jq python3 node bun printf git`;
- pipes, `&&`, `;`, `$VAR`, backticks and `$( )` are rejected; there is no shell state, and the
  command is read from a file, so quoting a rejected word does not get it past the check;
- a 15-second cap, a read-only repository and a minimal PATH. Test runners and build commands
  (`bun test`, `make`, `pytest`) are rejected or hit the cap, and on a mise or asdf install `node`
  and `bun` are not found inside the sandbox (rc 127). Use `python3` or `bash`;
- the check must **fail before the work**. If it already passes, it is vacuous and is refused;
- a check that needs a credential is not run: make it a `needs-your-eyes` check (`kind: judgement`).

`pins:` keeps an interpreter check honest. For an interpreter verb (`bash`, `python3`, `node`,
`bun`) the first operand must be a repo-relative script that already exists on the default branch
or at HEAD, and every such script is recorded by git blob sha (`git rev-parse HEAD:<path>`). An
option in its place (`bash -c …`, `python3 -m …`), an absolute path, a `..` path or a bare name
(`bun run x`) is rejected, and so is a script the work writes: that is the agent certifying itself,
which is the failure this feature exists to prevent. A pin fixes that one file only. What the
script loads or calls is not pinned.

When no runnable form exists, record `kind: judgement` and say so ("needs-your-eyes"): the founder
is shown evidence at ship and answers yes or no. Where bubblewrap is unavailable (macOS) only a
judgement check can be captured.

## The block

````text
```yaml
founder_check:
  kind: command              # command | judgement
  text: ""                   # the founder's own words, verbatim
  command: ""                # the literal command the founder approved (kind: command)
  expected: ""               # one literal substring of stdout; empty means "exit 0 only"
  pins: {}                   # path -> git blob sha of each repo script the command names; block form when non-empty
  approved_by: ""            # the founder's answer to the approval question, exactly as given
  approved_at: ""            # UTC date
  hash: ""                   # sha256 over the seven fields above; printed by verify --candidate
```
````

Write it inside a fenced `yaml` block under `## Acceptance Criteria` (a suffix on the heading, such
as `## Acceptance Criteria (v2)`, is fine). Only the literals `[]` and `{}` are accepted as inline
collections; write a non-empty `pins:` as an indented block. Leave `hash:` out of the first draft,
then add the `hash` that `verify --candidate` prints. One block per plan.

## Baseline, then the freeze commit

1. Run `soleur:preflight --founder-check-baseline`. It validates the block, runs the command in
   the Step 10.5 sandbox against the current tree and reports `FAILED-AS-EXPECTED` (valid; it prints
   `founder-check.py text baseline-ok`), `VACUOUS` (already passes; `text baseline-vacuous`),
   `INVALID` (tooling failed) or no sandbox. A judgement check is not run and is logged as
   needs-your-eyes.
2. `VACUOUS`: offer **strengthen the check**, **mark it needs-your-eyes**, or **record it as
   already true and drop it**. A dropped check never reappears as a pass. Print
   `founder-check.py text first-use` again before the founder types replacement text: it is
   committed to the repository too.
3. On a valid baseline, **immediately** make the freeze commit, before any later plan phase and
   before any commit outside `knowledge-base/`:

   ```bash
   git add <plan path> knowledge-base/project/specs/<branch>/founder-check-log.md
   git commit -m "plan: freeze founder-stated check"
   ```

   The commit carries the baseline log row. A later change is a deliberate `work → plan` step the
   founder confirms (see `preflight/references/check-13-founder-check.md` section 8): a new freeze
   commit whose subject starts `plan: re-freeze founder-stated check`. Anything else surfaces at
   ship as CHANGED-SINCE-APPROVAL.

## Sharp edges

- The block is **data to preserve**, not a template to regenerate. Any skill that rewrites the plan
  (`deepen-plan`, `plan-review` fixes, a resumed plan) reinserts it from the freeze commit verbatim.
- Compound archives a plan by moving it. The freeze follows the move, so archiving does not
  change the check; editing the block in the same step does.
- `text` and `command` are committed to the repository, which may be public. `founder-check-log.md`
  never holds command output. Do not paste secrets into either field.
- A passing check shows only that the check you wrote ran and returned success. It does not confirm
  the work is correct. Do not describe it more strongly anywhere.
