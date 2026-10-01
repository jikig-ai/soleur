---
name: operator-bootstrap
description: "This skill should be used when a merge leaves two or more operator steps blocked on one credential: generate a runnable staged bootstrap.sh an agent runs, not a prose checklist."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

<!-- Inspired by mattpocock/skills/skills/engineering/wizard/ (MIT, Copyright (c) 2026 Matt Pocock). -->

# Operator Bootstrap — generate the script, not the checklist

Two hard rules already mandate the artifact this skill produces.
`hr-multi-step-post-merge-bootstrap-script` says a post-merge deferral with two or more steps ships
as a runnable script; `hr-ship-message-no-operator-checklist` says the ship message does not hand the
founder a checklist.

This skill authors that script. It does **not** author the machinery: every script it produces
`source`s `plugins/soleur/scripts/lib/operator-script.sh`, which is where the stage table, the plan
and receipt gate, the secret handling, the `.env` upsert, the prompt classes and the run ledger live.

**The script is run by an agent, one stage at a time, with no terminal** (ADR-264). The person never
opens a terminal and is never handed a command list. Their acknowledgement of each production write
is the harness approval prompt on the exact command the agent is about to run. §Running a generated
script is the protocol.

## The library header is the contract

**The library is one file. The skill authors only stages. Never hand-edit the library.**

Everything a generated script may rely on is documented **once**, in the header of
`plugins/soleur/scripts/lib/operator-script.sh`, and is not restated here:

- **Sourcing preconditions** (`set -euo pipefail` first; the xtrace/TLS prologue duplicated
  *above* the `source` line; required binaries) — header §"SOURCING PRECONDITIONS".
- **The library invariant** (it never expands a secret-shaped name; secrets arrive as positional
  parameters; credential *entry* stays in the generated script) — header §"LIBRARY INVARIANT".
- **The staged contract and the approval receipt** (stage table, plan, digest, one-time receipt,
  the order inside `soleur_op_stage_gate`) — header §"Staged contract" and §"Approval receipts".
- **The prompt classes** and their non-interactive behaviour — header §"Prompts".
- **Exit codes and stdout markers**, including exit 75, `SOLEUR_BOOTSTRAP_LIB_MISSING` and
  `SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE` — header §"EXIT CODES" and §"STDOUT MARKERS".
- **The API contract** (`SOLEUR_OP_LIB_API`) — header §"API CONTRACT".

When the header and this file disagree, the header is right and this file has drifted.

## The staged contract in one screen

A generated script carries the header line `# SOLEUR-GENERATED-OPERATOR-SCRIPT v2` on line 2. The
approval hook recognises a script by that line (a v1 script never gets a receipt), never by file name.

```text
bash SCRIPT --list                                      the stages (static, needs no login)
bash SCRIPT --stage NAME                                a READ stage runs; a WRITE stage prints its plan
bash SCRIPT --stage NAME --apply --plan-digest D [--rotate-token]   the approved write
```

- There is **no run-all mode and no `--yes`**. A missing `--stage` exits 64.
- A **read** stage only reads and reports. A **write** stage first prints a **plan** and changes
  nothing: `SOLEUR_BOOTSTRAP_PLAN stage= operations= digest=`, one `SOLEUR_BOOTSTRAP_PLAN_OP` per
  change, the stage's `SOLEUR_BOOTSTRAP_IMPACT` and `SOLEUR_BOOTSTRAP_ROLLBACK` sentences, and an
  `SOLEUR_BOOTSTRAP_APPLY_COMMAND` line followed by the exact command to run.
- `--apply --plan-digest D` performs the write. The script **recomputes** the plan and compares the
  digest, so what runs is what was shown; a mismatch exits 75 `SOLEUR_BOOTSTRAP_PLAN_DRIFT` with
  nothing written.
- The **receipt**: a plugin PreToolUse hook (`plugins/soleur/hooks/operator-stage-approval.sh`) mints
  a one-time record when the harness shows the person the exact command, and rewrites the command to
  carry `SOLEUR_APPROVAL_NONCE`. The script consumes the record before its first write. An
  environment variable or a flag set by the agent is never an approval. No valid receipt: exit 75,
  nothing written.
- **Stages are idempotent.** A re-run of a satisfied stage changes nothing and needs no approval: its
  plan has `operations=0`, so skip `--apply`.
- Markers (stdout): `SOLEUR_BOOTSTRAP_STAGE_DECL stage= class=` (read or write); `_PLAN`; `_PLAN_OP`;
  `_IMPACT`; `_ROLLBACK`; `_APPLY_COMMAND stage= approval_digest=`; `_APPROVAL_REQUIRED stage=
  approval_digest= surface=`; `_APPROVAL_INVALID stage= reason=` (one of `no-record`, `expired`,
  `digest-mismatch`, `consumed`, `algo`, `perms`, `format`); `_PLAN_DRIFT stage=`;
  `_PRECONDITION_FAILED stage= need=`; `_STAGE_OK stage= changed=` (0 or 1, with `approval=` set to
  `harness-receipt` or `tty-ack` after a write); `_STAGE_FAILED stage= rc=`; `_LIB_INCOMPATIBLE need=stage-1`.
- Exit codes: 75 approval required, invalid or plan drift (nothing written); 64 missing input; 78
  refused under xtrace; 1 the stage failed.

**What the approval does and does not guard** (say it this way, in plain words): the approval guards
against an agent acting on a mistaken instruction, not against a compromised one. Never write that a
human approves every production write without that qualifier.

## Process

### 1. Scope the procedure

Read the deferral that triggered this. Name, in order, every step the founder must take before the
merged change is live. Stop when the list is complete, not when it is convenient.

Then apply the ladder **before** deciding anything is a step at all:
**environment variable → Doppler → MCP/CLI/REST → prompt.** `hr-exhaust-all-automated-options-before`
ends with *"prompt for creds not in Doppler"* — the prompt is the last rung of the ladder, not an
exception to it. A value that is missing and is not a credential is a hard failure with a named
remedy, never a prompt.

If fewer than two steps survive the ladder, do not generate a script. Say so.

### 2. Map each stage's journey

One stage per step. For each, write down five things before writing any code:

- **its class** — `read` (it only reads) or `write` (it changes production);
- **what the person is told** — for a write stage, one plain sentence of impact and one of rollback,
  written for a founder, which become the stage's `# SOLEUR-STAGE` line;
- **what it needs** — the value, and where on the ladder it comes from;
- **how it knows it is already done** — the precondition. Every stage opens with an
  "already satisfied?" check. This is what makes re-run idempotent over a non-idempotent create,
  and it is why there is **no resume index**: re-running a stage *is* resume, because a satisfied
  stage declares no operation and skips itself;
- **how it proves it worked** — the verification. A stage that attests without verifying attests
  nothing. The last stage of every script is a `verify` **read** stage that prints names only and
  derives its result from vendor state; its stdout markers are the closure evidence.

### 3. Author the stages

Copy [`template.sh`](./template.sh) to the location in §Where, keep everything above the `STAGES`
banner, and replace the example stages. Rules:

- **Stage lines.** Declare each stage once, in the table near the top of the script, as a comment
  line of the form `# SOLEUR-STAGE name|class|impact|rollback` (class is `read` or `write`). One plain
  sentence each for impact and rollback, no `|` inside them. `--list`, the dispatcher and the approval
  hook all read these same lines, and the person sees the impact and rollback in the approval prompt,
  so they are the only place those words are written.
- **Functions.** A read stage is `read_<name>()`. A write stage is a pair: `plan_<name>()` (read-only)
  and `apply_<name>()` (the writes; it runs only after the gate returned). `-` in a stage name
  becomes `_` in the function name.
- **A plan names operations and targets, never a value.** `soleur_op_plan_op <op-name> <target-name>`
  once per change the stage would make; the targets are container, slug and secret NAMES. The digest
  covers exactly this list, and the agent relays it, so a value in it would leak.
- **A satisfied stage declares no operation.** Then the plan prints `operations=0`, no approval is
  asked and `--apply` changes nothing.
- **Later stages re-prove earlier stages' work.** Stages are separately addressable, so a stage whose
  precondition is another stage's output calls `soleur_op_precondition_failed <stage> <need-stage>
  "<sentence>"` (marker `SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage= need=`) instead of trusting that
  the earlier one ran.
- **A stage never calls `soleur_op_ack_or_die`.** That helper needs a typed `yes` at a terminal and
  makes the stage unrunnable by an agent. The gate is `soleur_op_stage_gate`, called by the
  template's dispatcher, not by the stage; a stage that gates itself is a defect the guard fails.
- **Bake the library path.** The template carries a placeholder line
  `SOLEUR_OP_LIB_BAKED="__SOLEUR_OP_LIB_BAKED__"`. The generator MUST replace it with the absolute
  path of the library resolved at generation time, because the generated script lives in the
  founder's repository where `CLAUDE_PLUGIN_ROOT` may be unset and no relative path to the plugin
  exists:

  ```bash
  LIB="$(realpath "${CLAUDE_PLUGIN_ROOT}/scripts/lib/operator-script.sh")"
  sed -i "s|^SOLEUR_OP_LIB_BAKED=.*|SOLEUR_OP_LIB_BAKED=\"${LIB}\"|" knowledge-base/project/specs/feat-<name>/bootstrap.sh
  ```

  Anchor on the assignment line, as above — a global replace of the placeholder would be harmless
  today (the resolution loop deliberately does not spell it) but is not the documented form.
- **Never echo a secret variable** for progress. That is the documented
  `hr-never-paste-secrets-via-bang-prefix` leak path, whose Why cites a live prd-JWT leak.
- **Credential entry stays a class-1 ladder rung** in the generated script (`read -rs` behind the
  library's TTY gate — copy the shape from `provision-hetzner.sh`; the ladder tries the environment
  and Doppler first). With no terminal the script exits 64 naming what to set up, and the agent never
  asks for the secret in chat. `soleur_op_value` is for non-secret ladder values (a region, an
  account id); it echoes its input.
- **Write secrets through `soleur_op_gh_secret_set`** (stdin) and non-secrets through
  `soleur_op_gh_variable_set` (argv, and it refuses secret-shaped names). Do not merge them.
- **Write `.env` values through `soleur_op_env_upsert`.** It is exact-key: the trailing `=` is what
  stops an upsert of `X_API_KEY` from removing `X_API_KEY_SECRET`.
- **Keep the dispatcher.** The template's `dispatch_stage` is the one place that applies the staged
  contract and records the stage the template's one `EXIT` trap reports on: a stop inside a stage
  prints `SOLEUR_BOOTSTRAP_STAGE_FAILED stage= rc=` and one plain sentence, and settles the stage in
  the ledger as `failed` with the exit code (exit 75 settles as `refused` and adds nothing).
- **A destructive stage's precondition asks the vendor, never only a local marker written after the
  create.** Between "create succeeded" and "marker written" an interruption leaves a resource the
  next run cannot see, and it creates a second one. Keep the template's two controls: the vendor-side
  read and the `*_ATTEMPTED` marker written *before* the create, which stops a re-run and sends the
  person to the vendor console (`--reset <KEY>_ATTEMPTED` clears it once they have looked).
- **A marker the script writes is not proof of vendor state, and "already satisfied" must be read from the vendor.**
  Write the marker that skips a stage only AFTER the write and its verification succeed; treat an unreadable list as
  INCONCLUSIVE (stop), never as "absent"; confirm a revoke by re-listing, not by its exit code; and when exactly one
  vendor object exists that the script cannot show is the stored one, replace it new-before-old instead of dead-ending.
  Environment secrets are write-only, so a name listing proves nothing about the value (#9321).
- **Name skip variables by convention, and let `usage()` derive the list.** A class-1 value is
  `SOLEUR_BOOTSTRAP_<WHAT>` (`SOLEUR_BOOTSTRAP_ACCOUNT_ID`); a class-3 barrier is
  `SOLEUR_BOOTSTRAP_SKIP_<WHAT>_BARRIER`. The template's `--help` greps its own `soleur_op_value` /
  `soleur_op_barrier` call sites for the list, so a prompt added on a line of its own is
  documented without editing `usage()`. Keep each call on one line for that reason.
- **Open a URL with `soleur_op_open_url`.** It prints the URL first and never branches on the
  opener's exit code, so a headless box degrades to "here is the URL" instead of to a failed stage.
  `SOLEUR_OP_NO_OPEN=1` prints the URL and launches nothing (CI, test harnesses).

### 4. Verify and hand off

Drive the generated script the way an agent will, with stdin closed:

1. `--list` prints every stage with its class.
2. Every **read** stage runs with the class-1 skip variables set and exits 0, or with none set and
   exits 64 printing `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` naming the **first** skip variable — before
   any read, never after.
3. Every **write** stage prints its plan with no mutating call, and `--apply` with no receipt exits 75
   and writes nothing.

`plugins/soleur/test/operator-agent-runnable.test.sh` does this for every v2 script in the tree
(§Guards). Then read the ledger beside the script (`bootstrap-runs.jsonl`): every stage that ran has a
`begin` and a `settle` line. Hand off by **running the stages yourself** per §Running a generated
script, not by giving the person a script path to run.

## Running a generated script

This is the AGENT PROTOCOL. A person with no terminal can complete a bootstrap with it, because the
agent does every step and the person only answers the approval prompt.

1. **List.** Run `bash <script> --list` and read the `SOLEUR_BOOTSTRAP_STAGE_DECL` lines. This needs
   no library and no login.
2. **Run the read stages** (class `read`) in order, one `bash <script> --stage <name>` each.
3. **For each write stage**, run `bash <script> --stage <name>` first. This prints the plan and
   changes nothing. If it prints `operations=0`, the stage is already satisfied: **skip the apply**.
4. **Relay the impact and rollback.** Tell the person, in plain words and **verbatim from the
   script's own `SOLEUR_BOOTSTRAP_IMPACT` and `SOLEUR_BOOTSTRAP_ROLLBACK` lines**, what the write will
   change and how it is undone, **before** issuing the apply. Compose no impact or rollback sentence
   of your own: the words the person reads are the words that were approved.
5. **Announce it.** Print `SOLEUR_BOOTSTRAP_APPROVAL_PENDING stage=<s>`. In a headless session the
   approval hook defers silently; this line is what makes the wait visible.
6. **Issue exactly** `bash <script> --stage <name> --apply --plan-digest <d>` (plus `--rotate-token`
   only if the plan was produced with it) as **ONE simple command**: no pipe, `;`, `&&`, redirect,
   substitution or glob. The one accepted prefix is a leading `cd <dir> &&`. Use the line the plan
   printed after `SOLEUR_BOOTSTRAP_APPLY_COMMAND`.
7. **Let the harness prompt carry the approval.** The person sees the exact command (the hook has
   rewritten it to carry the receipt) and decides. **Never** set an environment variable, a flag or a
   file to approve; **never** pipe `yes`; **never** ask for a secret in chat.
8. After the last write stage, run the `verify` stage and keep its stdout markers: they are the
   closure evidence for the follow-through issue.

**Surfaces.** Claude Code interactive: the permission prompt on the exact command. Headless, `-p` or
one-shot: the hook defers; print `SOLEUR_BOOTSTRAP_APPROVAL_PENDING` before issuing the apply, and a
person resumes with `SOLEUR_RESUME_APPROVED_DIGEST=<approval_digest>` set in the resumed process.
`bypassPermissions`, `dontAsk` and auto modes: the hook denies. Harnesses without the hook (Codex,
Devin cloud, Grok) and the web app: the script exits 75 and writes nothing; say "this surface cannot
make production changes yet" and **never** tell the person to open a terminal (the web approval
adapter is #9388; per-harness adapters are #9389).

**The scheduled follow-through sweeper never runs `--apply`.** A receipt expires after ten minutes,
which an unattended runner cannot satisfy. The follow-through issue's `auto_command:` for a staged
script is attended-only: it names `--list` plus this protocol, and the issue closes on the `verify`
stage's stdout markers pasted into a comment.

### Outcome table

| Outcome | Agent does | Founder is told |
|---|---|---|
| founder denied the prompt | stop; do not re-prompt in a loop; ask once whether to retry | "You declined, so nothing changed." |
| 75 `APPROVAL_INVALID` reason `expired`, `consumed` or `digest-mismatch` | re-plan, re-issue once | "That approval timed out (or was already used), so I am asking again." |
| 75 `APPROVAL_INVALID` reason `perms`, `algo` or `format` | stop and report | "A safety check failed and nothing changed; this needs a person to look at it." |
| 75 `PLAN_DRIFT` | re-plan, relay the new impact, re-issue | "Something changed since I showed you the plan; here is what is different." |
| 75 `APPROVAL_REQUIRED` on a no-hook or web surface | stop | "This surface cannot make production changes yet; run the stage from Claude Code." |
| headless pending | print `SOLEUR_BOOTSTRAP_APPROVAL_PENDING stage=<s>` | "A change is waiting for your approval." |
| bypass-mode deny | stop | "Approvals are switched off in this session; switch to the normal mode and I will ask again." |
| 64 missing input | stop; name the input; never ask for a secret in chat | "I need (the login or input) set up first." |
| 78 refused under xtrace | unset xtrace, re-run once | none |
| 1 `STAGE_FAILED` | run the `verify` or a read stage; never re-apply blindly | a plain account of what changed and what did not |

## The interactive surface

Generated scripts are **non-interactive by default** (ADR-228) and, from v2, **agent-run** (ADR-264).
The one interactive rung left in a script is credential **entry**
(`hr-never-label-any-step-as-manual-without`): a class-1 ladder rung that tries the environment and
Doppler first and prompts only as the last step, behind the library's TTY gate. With no terminal it
exits 64 naming the missing input.

The destructive-write acknowledgement is **not** a prompt in the script any more. It is the harness
approval on the exact command and the receipt it mints (§The staged contract). The rulings an author
must not undo:

- **No environment variable, flag or file approves a write.** A skip variable for the write ack would
  be exactly the "prior approval extending to a new command" that
  `hr-menu-option-ack-not-prod-write-auth` forbids. The receipt is bound to one command and one use.
- **A class-3 barrier must be followed by an independent verification.** A barrier only attests that
  a human *says* they did something outside the script. Skipping it is safe **only** because a
  `gh api /installation`, a `doppler projects get` or a `terraform output` runs immediately after
  and fails if the attestation was false. A skippable barrier with no downstream verification is a
  no-op wearing a prompt.

## Recovering from a bad run

- **A wrong credential was permanent.** The value is persisted before it can be validated, and the
  environment-first ladder means a re-run never re-prompts — it fails identically forever. Every
  generated script exposes `--reset <KEY>`, which calls `soleur_op_env_reset`.
- **Re-run was not idempotent.** The precondition check is what makes it so, and it is also what makes
  re-running a stage the resume mechanism. This is a rule for the author, not a feature of the library.
- **A stage failed (`STAGE_FAILED`, exit 1).** Run the `verify` or a read stage to see what changed.
  Never re-apply blindly: the failure sentence says whether production may already have changed.

An interruption leaves a state byte-identical to a crash, and the ledger's completed-set-versus-declared
comparison detects both. What every non-zero exit *inside a stage* gets is the template's single `EXIT`
trap: `SOLEUR_BOOTSTRAP_STAGE_FAILED`, one sentence naming the stage, whether anything was changed and the
command that shows where it stands, plus a `failed` settle line in the ledger. Every library refusal
prints its marker **and** one plain sentence, and writes a `run_halt` ledger line before exiting.

## Where the artifact lives

**One location:** `knowledge-base/project/specs/feat-<name>/bootstrap.sh`, with the run ledger
beside it as `knowledge-base/project/specs/feat-<name>/bootstrap-runs.jsonl`.

That is the rule's own `<feature>/` prefix (`hr-multi-step-post-merge-bootstrap-script` names
`<feature>/bootstrap.sh`, and the feature's tracked artifact home is its spec directory); it is
tracked, so the script survives `ship` reaping the worktree and is visible to the credential linter
and to review; and a gitignored path (`provisioning/`, `.soleur/` — both are) would leave the
follow-through issue's `auto_command:` pointing at a file that stops existing at ship Phase 7.

A tracked home has one consequence the founder must not discover from a pushed token: the `.env`
beside the script — and the `.env.tmp.XXXXXX` sibling the upsert creates — must be covered by the
repository's `.gitignore` (a bare `.env` pattern does not cover the sibling; `.env*` covers both).
The template checks this **before its first write**, `--reset` included: inside a git work tree, an
uncovered path stops the run with `SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED path=<path>`, exit 64, and one
sentence naming the fix. This repository's `.gitignore` carries both patterns.

The ledger is written on the founder's machine and is committable in the founder's repository,
which is where observability layer 7's "committed to the customer's own repository" condition is
satisfied. Nothing is transmitted to Soleur infrastructure: the surface is the founder's own
machine, and routing it anywhere else is a data-controller event, not an observability improvement.

## Lifecycle

- **Create:** this skill, from ship's operator-step gate (option 4).
- **Read / run:** the agent runs it per §Running a generated script; `--list` shows the stages,
  `--help` lists the skip variables, and the ledger beside it is the run history.
- **Regenerate** (the procedure changed, the library's API number moved): re-run this skill. It
  rewrites the script from the template; the `.env` and the ledger are left in place, and every
  stage's precondition makes the next run skip what is already done.
- **Delete:** when the follow-through issue that points at the script closes, remove the script,
  the ledger (`bootstrap-runs.jsonl`) and the `.env` together — the `.env` holds live credentials
  and has no reason to outlive the procedure that needed them. The
  `SOLEUR-GENERATED-OPERATOR-SCRIPT v2` header line is what the approval hook and the guard use to
  find every generated script by one grep.

## Legacy scripts

Three finished generated scripts still carry the v1 header and the typed-yes TTY acknowledgement: the
8450 CI-concurrency script, the LinkedIn token renewal script and the runtime App key eviction script.
So do `flag-create`, `flag-delete`, `user-set-role`, `flag-set-role`, `provision-hetzner` and
`audit-sentry`. The approval hook never mints for a v1 script. Migrating them to the staged contract is
tracked in #9387; until then their writes keep the typed-yes handoff, and credential entry in
`provision-hetzner` stays a class-1 interactive carve-out.

## Guards

- [`plugins/soleur/test/operator-agent-runnable.test.sh`](../../test/operator-agent-runnable.test.sh)
  (Guard 1) discovers every v2 generated script in the tree and drives every `--list` entry with stdin
  closed and no terminal against PATH-stubbed vendor tools: every stage reaches a defined outcome, no
  stage reaches a mutating call without a receipt or a real terminal ack, and no stage demands a
  terminal or calls `soleur_op_ack_or_die`. A v1 script must be one of the three legacy paths, and that
  list may only shrink. It is wired through the `plugins/soleur/test/*.test.sh` glob in
  [test-all.sh](../../../../scripts/test-all.sh), so it runs in the repository's test suite and CI with no per-script entry.
- [`plugins/soleur/test/operator-script.test.sh`](../../test/operator-script.test.sh) pins the library
  controls below and the receipt algorithm's known-answer vectors.
- Decision record: ADR-264 (generated operator scripts are agent-run in stages; the human
  acknowledgement is a harness-approved receipt).

## What protects the founder's credentials

Seven vectors, six controls — five inside the library or the hook so no generated script re-decides
them, one in the template because only the generated script knows where it lives:

| Vector | Control |
|---|---|
| `.env` written at a default umask into a cloud-synced directory | `umask 077` in the library, `chmod 600` asserted **after** the `mv` that completes each upsert — `mv` replaces the inode and its mode |
| a secret on argv, readable in `/proc/<pid>/cmdline` | the secret helper is stdin-only; the `--body` form is banned |
| a secret echoed for progress, or a run under `set -x` | the xtrace refusal (exit 78) plus the repo-root `lint-shell-trace-credential-refusal.py` linter in CI |
| a third-party CLI dumping unrelated secrets as a side effect of a write | the write's own output is redirected and the result confirmed by a separate read |
| a half-populated `.env` and partly-set secrets after an interrupted run | **not** a library control — it is the precondition/`--reset` work above, and it is the author's job |
| the `.env` (or its `.tmp.XXXXXX` sibling) sitting in a tracked directory that `.gitignore` does not cover | the template's `git check-ignore` probe on both paths before the first write — `SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED`, exit 64 (a template control, not a library one: the library does not know where it is sourced from) |
| a production write the person never saw | the one-time receipt bound to the exact command, the plan recomputed and its digest compared, the receipt consumed before the first write (the hook and the library). It guards against an agent acting on a mistaken instruction, not against a compromised one |

The guards behind the library controls and the template's ignore probe live in
`operator-script.test.sh`, whose mutation matrix drives each one red (the ignore probe is observed on
a real git fixture, with the probe deleted from the generated script as the mutation). The same suite
proves the bake in §3 is load-bearing: the unbaked template, placed at the documented location with no
`CLAUDE_PLUGIN_ROOT`, exits 64.

## Related

- [`template.sh`](./template.sh) — the starting point. Copy it; do not copy the library.
- `plugins/soleur/scripts/lib/operator-script.sh` — the library; its header is the contract.
- `plugins/soleur/hooks/operator-stage-approval.sh` — the approval hook that mints the receipt.
- `soleur:provision-hetzner` — the proving consumer; read its script for a real refactor onto the library.
- `soleur:ship` — invokes this skill when a post-merge deferral carries two or more operator steps.
