---
title: "ADR-264: Generated operator scripts are agent-run in stages; the human acknowledgement is a harness-approved receipt"
status: adopting
date: 2026-10-01
supersedes: "ADR-228 points 2-4 and ADR-249 step 1 points 2 and 4, for generated operator scripts only"
amends: [ADR-162]
issue: 9321
related: [9321, 9387, 9388, 9389]
related_adrs: [ADR-228, ADR-249, ADR-162, ADR-178, ADR-236, ADR-241]
tags: [operator-bootstrap, hooks, approval, trust-boundary, agent-run, pretooluse]
brand_survival_threshold: single-user incident
---

# ADR-264: Generated operator scripts are agent-run in stages; the human acknowledgement is a harness-approved receipt

## Status

Adopting, 2026-10-01. The acknowledgement this ADR describes resists an
instruction-following agent. It does not resist a hijacked or deliberate one (see
[Threat model and residual](#threat-model-and-residual)). The status flips to `accepted` when
the first real harness-approved production write is recorded in a run ledger. Until then the
existing TTY handoff for writes stays in force for the founder; reads and plans are
agent-runnable regardless, because they need no approval.

> **Supersedes in part**, for **generated operator scripts only**: [ADR-228](./ADR-228-generated-operator-scripts-are-non-interactive-by-default.md)
> points 2, 3 and 4, and [ADR-249](./ADR-249-operator-prod-writes-need-a-tty-ack-layered-with-credential-custody.md)
> step 1 points 2 and 4. Each of those carries a "Superseded in part by ADR-264" blockquote
> that names what stays in force. **Amends** [ADR-162](./ADR-162-pretooluse-hooks-may-rewrite-tool-input.md)
> (a second named PreToolUse rewriter). The schema carries ADR ids only, so the point
> numbers are named here and in the blockquotes, not in the `supersedes` key.

## Context

Soleur's product direction is to serve non-technical users and a web app that has no terminal.
Two earlier decisions assume the opposite for the one moment that matters, a production write:

- ADR-228 made a generated script non-interactive by default, with the destructive-write
  acknowledgement taking no skip variable and a missing TTY meaning exit `64` with
  `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` (points 2 to 4).
- ADR-249 made every production-writing script gate its write on a typed `yes` at a terminal,
  exit `64` with no TTY, and a skill that hands the write command to the operator's own terminal
  (step 1 points 2 and 4).

So today's contract is: exit `64`, typed `yes` at a terminal. A founder cannot be asked to open a
terminal, and the web app has none. An agent cannot run the steps either, so a merge that leaves
several operator steps blocked on one credential ends in a printed command and an undone
operator step. That is the opposite of what a product for non-technical users needs. The
motivating case is the release-job App source work (#9321): copy values into the release
container, prove the App is live, mint and store a scoped token, verify. Every one of those steps
is mechanical except the decision to write, and that decision is the only thing the human adds.

The constraint that shapes the answer is the one ADR-249 measured: the operator's Doppler owner
token reads every production write key, so any check that lives in a script is a speed bump
against a hijacked agent. What a script can do is stop an agent acting on a mistaken
instruction. The decision here therefore moves the human acknowledgement to the place a person
already is (the harness approval prompt on the exact command), without pretending to a stronger
guarantee than a same-user file gives.

## Decision

A generated operator script (header line `SOLEUR-GENERATED-OPERATOR-SCRIPT v2`) is run by an
agent one stage at a time with no TTY. The human acknowledgement of each production write moves
from a typed `yes` at a terminal to the harness approval prompt on the exact command, and the
approval is carried to the script as a one-time, command-bound receipt that the harness hook
minted.

**The stage grammar.** There is no run-all mode.

```text
bash <script> --list
bash <script> --stage <name>
bash <script> --stage <name> --apply --plan-digest <d> [--rotate-token]
```

- `--list` prints one `SOLEUR_BOOTSTRAP_STAGE_DECL stage=<s> class=<read|write>` line per
  stage.
- `--stage <name>` runs a read stage. For a write stage it prints the PLAN (operation names and
  the container, slug and secret names they touch, never a value), its digest, the stage's
  plain-language impact and rollback, and the exact apply command
  (`SOLEUR_BOOTSTRAP_APPLY_COMMAND`).
- `--stage <name> --apply --plan-digest <d> [--rotate-token]` performs the write. The existing
  flag name `--rotate-token` is kept.
- A stage whose plan has zero write operations is read-class. An already-satisfied stage returns
  `changed=0` with no approval.

**The hook.** `plugins/soleur/hooks/operator-stage-approval.sh`, a PreToolUse hook:

1. Recognises the script by its **content** (the v2 header line), never by basename, and reads
   the stage declarations statically with `grep`. It never executes the script it fingerprints.
2. Mints a one-time receipt only for a command that is exactly one simple command,
   `[cd <dir> &&] bash <script> --stage <s> --apply --plan-digest <d> [--rotate-token]`, with no
   pipe, `;`, trailing `&&`, redirect, substitution or glob. The human approves one exact string.
3. The receipt is a record named `sha256(nonce)` in `${XDG_STATE_HOME:-~/.local/state}/soleur/approvals`
   (directory `0700`, files `0600`, outside the worktree). It holds the digest of the script
   realpath, the stage and the exact argv, a 10-minute expiry and the session id.
4. Rewrites the command to carry `SOLEUR_APPROVAL_NONCE=<nonce>` immediately before `bash`
   (`updatedInput`) and answers `ask` on an interactive session
   (`CLAUDE_CODE_ENTRYPOINT=cli`), so the human sees the rewritten command plus the stage's
   plain-language impact and rollback.
5. Headless (`claude -p`, `--bg`, one-shot; entrypoint `sdk-cli` or anything else) it emits
   `defer` and mints **nothing** on the deferring invocation. On `claude --resume` the hook
   re-runs and mints only when the environment of the human-owned resumed process carries
   `SOLEUR_RESUME_APPROVED_DIGEST` equal to this command's digest, then answers `allow`.
6. Under `bypassPermissions`, `dontAsk`, `auto`, or an unknown permission mode it **denies** and
   never mints. If interactive versus headless cannot be determined it emits `defer`, never
   `allow`.
7. Denies any original tool input that already contains the nonce variable name, and any
   Bash, Monitor, Write, Edit or Read access to the receipt directory. The path-tool denial is
   reliable; string matching on a shell command is a speed bump, not a wall.
8. A call that is not a candidate returns at once, before any `jq` is needed. Only a candidate
   fails closed, so a machine without `jq` is not denied every Bash call.

**The script.** `soleur_op_stage_gate` in `plugins/soleur/scripts/lib/operator-script.sh`
enforces this order, and the order is the contract:

1. Recompute the plan and its digest. A mismatch with `--plan-digest` is `PLAN_DRIFT`, exit
   `75`, and the receipt is burned.
2. Require a 32-hex nonce with a matching, unexpired record that is not a symlink, is owned by
   the script's euid and has mode `0600`, and whose bound digest equals the recomputed command
   digest.
3. Consume the record (rename to `.consumed`) **before** the first write. A lost rename race
   fails closed.
4. Unset the nonce so no child process inherits it. The nonce is never echoed.
5. Only then may the caller write. The ledger records `approval=harness-receipt`.

Otherwise a real TTY with a typed `yes` is a second valid source (`approval=tty-ack`), and
otherwise the script exits `75`.

**Exit `75`** (`EX_TEMPFAIL`) is new: approval required, approval invalid, or plan drift. `64`
stays "missing input" and `78` stays "xtrace refused". The stdout markers, one line each and
never a value or a hash of one: `SOLEUR_BOOTSTRAP_PLAN`, `_PLAN_OP`, `_IMPACT`, `_ROLLBACK`,
`_APPLY_COMMAND`, `_APPROVAL_REQUIRED stage=<s> approval_digest=<hex> surface=<s>`,
`_APPROVAL_INVALID stage=<s> reason=<no-record|expired|digest-mismatch|consumed|algo|perms|format>`,
`_PLAN_DRIFT`, `_PRECONDITION_FAILED`, `_STAGE_OK stage=<s> changed=<0|1> [approval=<harness-receipt|tty-ack>]`
and `_STAGE_FAILED`.

**An environment variable or a flag is never an approval.** The nonce is a lookup key into a
record the hook wrote. A value with no matching record gets exit `75`. The nonce is bearer-only,
single-use and bound to one command digest. The plan digest is not a secret and is not the
acknowledgement; the receipt is.

**Where it ships.** The hook ships in `plugins/soleur/hooks/hooks.json`, the surface that reaches
a founder's install, not only in this repository's `.claude/hooks`. Web Concierge loads that file
too (see the per-surface table).

## Threat model and residual

The record is a file the same OS user can write. Hash naming only stops a directory listing from
leaking a live nonce. No same-OS-user design can satisfy "the agent cannot write the file
itself", because any file the script reads is writable by that user through Bash.

What this design resists: an instruction-following agent that follows skill text and exit
markers, sets environment variables, passes flags, pipes `yes`, or uses its ordinary
Write/Edit/Bash tools without reverse-engineering the gate. Such an agent cannot satisfy it.

What it does **not** resist: a hijacked or deliberate agent that forges a record through an
obfuscated path, allocates a PTY wrapper for the `tty-ack` source, calls `curl` directly with
Doppler-held keys, sets `BASH_ENV`, or edits the hook files or settings. Closing that needs a
principal the agent cannot write as: a separate OS user, or a broker holding a FIDO2 touch. That
is credential custody, the open step 2 of ADR-249, and it is not moved into this change.

In plain words, for the skill and the PR: **the approval guards against an agent acting on a
mistaken instruction, not against a compromised one; do not claim that a human approves every
production write without that qualifier.**

The credibility of the approval prompt itself has one more measured limit: the first line above
the command in the prompt is the model-authored `description` field, not the real command. The
real command is the line below it. The hook's own reason text carries the impact and rollback so
the founder does not rely on the model's description.

## Alternatives considered

- **C1, the hook alone with the script ungated.** Rejected. Harnesses with no hook (Codex, Devin
  cloud, Grok) would regress from today's TTY refusal to an open write.
- **C2 (chosen) with an HMAC over the receipt.** The HMAC variant is rejected: a same-user key is
  readable by the same user, so it buys nothing. The receipt without an HMAC is chosen.
- **C3, the plan digest as the acknowledgement.** Rejected. The digest is printed by the plan
  stage; it is not a secret, so presenting it proves nothing. It is kept as an integrity binding
  (so the human approves exactly what runs), not as the acknowledgement.
- **C4, a GitHub Environment required reviewer or a server-side approval.** Not a script
  mechanism. It is the web adapter, tracked as a follow-up behind the same script contract.
- **Keep the TTY ack as the only source.** Rejected. It contradicts the product direction: a
  founder with no terminal could never complete a write.
- **Drop the human acknowledgement for low-risk writes.** Rejected outright by the CTO ruling
  and by hard rule `hr-menu-option-ack-not-prod-write-auth`. No production write class (a
  Doppler secret write into a container, a service-token mint, a GitHub environment secret
  write, a revoke or rotation, a terraform apply) loses its acknowledgement.
- **Amend ADR-228 and ADR-249 in place.** Rejected. It hides a decision reversal. Dated records
  are append-only: the originals keep their text and gain a pointer here.

## Per-surface coverage

| Surface | Mechanism | Result |
|---|---|---|
| Claude Code interactive (`CLAUDE_CODE_ENTRYPOINT=cli`) | `ask` plus `updatedInput`; the hook mints at that point | Human sees the rewritten command, impact and rollback; approval runs it |
| Headless, `claude -p`, `--bg`, one-shot (`sdk-cli`) | `defer`, then a resume marker | Mints nothing on the deferring call; mints on `--resume` only when `SOLEUR_RESUME_APPROVED_DIGEST` matches, then `allow` |
| Codex, Devin cloud, Grok | No hook runs | The script exits `75` and writes nothing; a tracked capability gap (#9389) |
| Web app (Concierge) | The hook opts out through `SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=1`, set by `buildAgentEnv` | Scripts fail closed at exit `75` until the web adapter lands (#9388) |

Web Concierge loads `plugins/soleur/hooks/hooks.json`, so without the opt-out the hook would run
inside the web runtime where no human sees a harness prompt. The opt-out follows the precedent the
`unkept-promise-hook.sh` set. The web adapter (#9388) is a `canUseTool` chokepoint and must
exclude write-stage commands from `isBashCommandSafe`, from the 60-minute "Approve all prefix"
cache and from `bash_autonomous`, and approve them per exact command through the review-gate
card. That requirement is tested there, not assumed here.

## Measurements (W0)

Measured 2026-10-01 on Claude Code 2.1.287, in a nested `claude -p` and an interactive tmux
session with a stub PreToolUse hook in a throwaway `--settings` file. Nothing touched production.
Method and re-probe trigger: `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md`, section "Operator
stage approval (ADR-264), measured 2026-10-01".

| # | Question | Result |
|---|---|---|
| 1 | Does `ask` together with `updatedInput` show the rewritten command and run it after approval? | Yes. The prompt shows the rewritten command and the hook's reason ("Hook PreToolUse:Bash requires confirmation for this command"); PostToolUse receives the rewritten command; it executes after approval |
| 2 | Does the hook's `ask` hold against an allow rule and under `bypassPermissions`? | Yes. With `Bash(echo:*)` matching the original command, and under `--permission-mode bypassPermissions`, `ask` still prompts. The payload carries `permission_mode` (`default` versus `bypassPermissions`) |
| 3 | Does headless `defer` plus `--resume` re-run the hook and expose a human-set marker? | Yes. `defer` ends the turn with terminal_reason `tool_deferred` and the deferred input shows the ORIGINAL command. `claude -p --resume <session>` re-runs the hook; an environment variable on the resumed process (`SOLEUR_RESUME_APPROVED_DIGEST=abc123`) is visible to it; `allow` plus `updatedInput` on resume executes the rewritten command |
| 4 | Is there an interactive versus headless discriminator? | Yes. `CLAUDE_CODE_ENTRYPOINT` is `cli` interactive and `sdk-cli` under `claude -p`. The payload also has `permission_mode`, `session_id`, `cwd`, `tool_use_id`, `prompt_id` |
| 5 | Does the tool_use text the model sees afterwards leak the nonce? | No. The model sees the ORIGINAL command. The nonce appears only in the transcript's hook_success attachment (the hook's stdout), in the human-visible prompt, and in a headless permission_denials result record. It is single-use and bound to the exact command digest |
| 6 | What is the first line of the prompt? | The model-authored `description` field, not the real command; the real command is the line below it |

For replace-versus-merge (`updatedInput` REPLACES `tool_input`), see
`.claude/hooks/UPDATED-INPUT-PAYLOAD-SHAPE.md`, which is not re-measured here.

## Scope

This ADR migrates **generated scripts only**: the library (additive), the template, the
release-job App source re-cut (#9321), the new hook, and the new guard.

- `flag-create`, `flag-delete`, `user-set-role`, `flag-set-role`, `provision-hetzner` and
  `audit-sentry --apply` keep the TTY ack. The flag scripts feed `flag_flip_audit.approval_method`,
  whose CHECK allows only `'tty-ack'` or NULL. Widening it is a migration with the
  rollback-ordering hazard ADR-249 recorded.
- The three finished generated scripts (for the earlier CI-concurrency work, the LinkedIn-token
  work and the runtime-App-key-eviction work) keep the legacy ack.
- `soleur_op_ack_or_die` is unchanged. ADR-228 points 1, 5, 6 and 7 and its class-1 and class-3
  skip variables stand, as do ADR-249 step 1 points 1, 3, 5 and 6, step 2 and the residual list.

## Consequences

- An agent can run every read stage and print every plan with no human present, and the founder
  approves each write at the harness prompt on the exact command. The founder is never asked to
  open a terminal for a generated script.
- A second PreToolUse rewriter now exists. ADR-162 carries an appended amendment: the precedence
  rule against `grep-rewrite.sh`, and the carve-out of its idempotent, fail-open and
  never-emit-a-decision clauses for an approval hook.
- Exit `75` is a distinct code. A caller that treats every non-zero as "done" must read the
  marker: `APPROVAL_REQUIRED` is a stop, not a failure to retry blindly.
- On a surface with no hook (Codex, Devin cloud, Grok) and on the web app until its adapter lands,
  a write stage cannot complete. This is deliberate: it fails closed for an instruction-following
  agent, and it is a visible, tracked gap rather than a silent regression.
- The receipt directory is local state on the founder's machine with a 10-minute record
  lifetime. It is not a persistent store and adds no C4 element; the C4 model gains the
  founder-to-Doppler and founder-to-GitHub write edges and the approval hook in the Hook Engine
  description.
- The approval depends on the harness honouring a hook's `ask` plus `updatedInput`. That was
  measured on one version; a harness version change triggers a re-probe.

## Follow-ups

- **#9387**: migrate the TTY-ack scripts and the three finished legacy generated scripts onto the
  staged contract, including the `approval_method` CHECK widening.
- **#9388**: the web approval adapter (`canUseTool`), with write-stage commands excluded from
  `isBashCommandSafe`, the 60-minute "Approve all prefix" cache and `bash_autonomous`.
- **#9389**: per-harness approval adapters for Codex, Devin and Grok.
- Credential custody (the open step 2 of ADR-249) remains the only route to resisting a hijacked
  agent.

## Cost Impacts

None. No new vendor, service or tier.

## NFR Impacts

- NFR-041 (Link-Level Access Control): the founder-to-Doppler and founder-to-GitHub write links
  are gated on a person approving the exact command, for the instruction-following agent. The
  status does not move to Implemented until credential custody takes the keys out of the agent's
  reach.

## Principle Alignment

- AP-007 (Exhaust automation before manual steps): Aligned. Every read, plan and verify stage is
  automated; the human adds only the write decision, at a surface they already use.
- AP-008 (Doppler for all secrets management): Aligned. The staged scripts copy and mint through
  Doppler; no value enters the plan, the ledger or the receipt.
- AP-020 (Untrusted input at the agent boundary): Aligned. The hook treats the command string as
  adversarial: one simple command, no composition, deny when mode is unknown, and fail closed for a
  candidate.
- AP-011 (ADRs for architecture decisions): Aligned.

## Diagram

The C4 model gains the founder's write edges to Doppler and GitHub (a harness approval prompt on
an agent-run staged script), and the Hook Engine and plugin descriptions name the approval hook.
The founder-to-Flagsmith edge is the legacy TTY path and is unchanged:

```likec4-view
context
```
