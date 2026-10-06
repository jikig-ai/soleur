# Founder-stated check (plan capture)

Linked from `plan/SKILL.md` step 2.13. Lets a founder state, in their own words and before work
starts, what proves a piece of work is done. The plan stores it as a `founder_check:` block under
`## Acceptance Criteria`; `soleur:preflight` Check 13 runs it later, in a step separate from the
work. Decision record: ADR-274. This file is the only place the block's YAML shape lives.

**Wording is a contract.** Print the pinned constants from `founder-check.py text <name>` (the
script, not this prose, is the source) and never paraphrase them. Never say "verified", "proven"
or "safe" about a check.

## When it runs

- **Interactive only.** Headless and one-shot runs ask nothing and write no block; a run with no
  block prints the no-block banner at ship and continues.
- **After the plan's `## Acceptance Criteria` section is written, before Plan Review and
  `deepen-plan`.** The block is the last element of that section.
- **Never twice.** Before asking, run
  `python3 plugins/soleur/skills/preflight/scripts/founder-check.py verify --base origin/main`
  (add `--plan <path>` when the plan already merged to main). Any `outcome` other than `NO-BLOCK`
  means a block is frozen on this branch: **import it verbatim** from
  `git show <freeze_sha>:<plan path>` (copy the `founder_check` fence unchanged) and do not
  re-ask. A re-run of this skill must never rewrite, reformat or drop an approved block.

## The question and the first-use notice

Show `founder-check.py text first-use` on one screen **at every capture**, with the question:

> What would you check to know this is done?

Offer a plain "I do not have a check for this" answer; it records nothing. Store the founder's
answer **verbatim** as `text`. Do not clean it up.

## Proposing the literal check

Propose a `command` (what runs) and an `expected` string (one literal substring of stdout; empty
means "exit 0 only"), and one plain sentence beside them saying what the command will do. The founder
approves the **exact text**, not a paraphrase. Tell the founder up front what the sandbox allows, so
they are not surprised at ship:

- the check runs on this computer in a limited environment that can still use your network connection, so read the command before approving; "sandbox" is not a promise of safety;
- the first word must be one of `curl bash grep rg jq python3 node bun printf git`;
- pipes, `&&`, `;`, `$VAR` and `$( )` are rejected; there is no shell state;
- a 15-second cap, a read-only repository and a minimal PATH. Test runners and build commands
  (`bun test`, `make`, `pytest`) are rejected or hit the cap, and on a mise or asdf install `node`
  and `bun` are not found inside the sandbox (rc 127). Use `python3` or `bash`;
- the check must **fail before the work**. If it already passes, it is vacuous and is refused;
- a check that needs a credential is not run: make it a `needs-your-eyes` check (`kind: judgement`).

Two fields keep the check honest:

- **`creates:`** repo-relative DATA paths the work will create (for example the page the check
  greps). Only with a non-interpreter verb (`curl grep rg jq printf git`). The path must be absent
  now, so a stub cannot make the check pass.
- **`pins:`** for an interpreter verb (`bash`, `python3`, `node`, `bun`) every repo script it names
  must already exist and is recorded by git blob sha (`git rev-parse HEAD:<path>`). A script the
  work writes is the agent certifying itself, which is the failure this feature exists to prevent,
  so it is rejected.

When no runnable form exists, record `kind: judgement` and say so ("needs-your-eyes"): the founder
will be shown evidence at ship and answers yes or no. Where bubblewrap is unavailable (macOS) only
a judgement check can be captured.

## The block

````text
```yaml
founder_check:
  kind: command              # command | judgement
  text: ""                   # the founder's own words, verbatim
  command: ""                # the literal command the founder approved (kind: command)
  expected: ""               # one literal substring of stdout; empty means "exit 0 only"
  creates: []                # optional repo-relative DATA paths the work will create
  pins: {}                   # path -> git blob sha of each existing repo script the command names
  approved_by: ""            # recorded from the interactive answer
  approved_at: ""            # UTC date
  hash: ""                   # sha256 over the canonical fields: an identity shown in the log
```
````

Write it inside a fenced `yaml` block under `## Acceptance Criteria`. Fill `hash:` from the `hash`
field printed by `founder-check.py verify --candidate`. One block per plan in v1.

## Baseline, then the freeze commit

1. Run `soleur:preflight --founder-check-baseline`. It validates the block, runs the command in the
   Step 10.5 sandbox against the current tree and reports: `FAILED-AS-EXPECTED` (valid),
   `VACUOUS` (already passes), `INVALID` (tooling failed) or no sandbox.
2. `VACUOUS`: offer **strengthen the check**, **mark it needs-your-eyes**, or **record it as
   already true and drop it**. A dropped check never reappears as a pass.
3. On a valid baseline, **immediately** make the freeze commit, before any later plan phase and
   before any commit outside `knowledge-base/`:

   ```bash
   git add <plan path> knowledge-base/project/specs/<branch>/founder-check-log.md
   git commit -m "plan: freeze founder-stated check"
   ```

   The commit carries the baseline log row. After it, the block may only be changed by a deliberate
   `work → plan` step the founder confirms (see `preflight/references/check-13-founder-check.md`
   section 8); anything else surfaces at ship as CHANGED-SINCE-APPROVAL.

## Sharp edges

- The block is **data to preserve**, not a template to regenerate. Any skill that rewrites the plan
  (`deepen-plan`, `plan-review` fixes, a resumed plan) reinserts it from the freeze commit verbatim.
- `text` and `command` are committed to the repository, which may be public. `founder-check-log.md`
  never holds command output, only an output hash. Do not paste secrets into either field.
- A passing check shows only that the check you wrote ran and returned success. It does not confirm
  the work is correct. Do not describe it more strongly anywhere.
