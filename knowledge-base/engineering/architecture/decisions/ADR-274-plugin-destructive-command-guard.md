---
title: The customer plugin ships a narrow, lexer-based destructive-command guard that asks (or denies) and degrades to a raw scan
status: accepted
date: 2026-10-07
supersedes: none
issue: 9601
related: [9653, 9543, 9602, 9603, 9604]
related_adrs: [ADR-157, ADR-165, ADR-156, ADR-093, ADR-223, ADR-245, ADR-256, ADR-264, ADR-272]
tags: [security, hooks, plugin, destructive-command, pretooluse, lexer, customer-surface]
brand_survival_threshold: single-user incident
---

# ADR-274: The customer plugin ships a narrow, lexer-based destructive-command guard that asks (or denies) and degrades to a raw scan

## Status

**Accepted at merge (W2 of the agent-security epic #9601, PR #9653).** The behaviour is measured in the suites named under
Verification, so there is no `adopting` window as ADR-272 had. **Extends [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md)
and [ADR-165](./ADR-165-what-ask-means-on-a-harness-with-no-ask-state.md)** (both are bullet-style records with no YAML extends key, so
the relation is stated here and carried in `related_adrs`). It narrows one row of ADR-157's `.claude` failure table on purpose (D6) and
is the first ADR to apply that table to a hook that ships to customers rather than to this repository's own sessions.

The product owner (CPO) signed off the decision set below before any implementation commit, on a named revision SHA and section hash
recorded in the PR body; the four conditions the sign-off attached are listed with their satisfaction under "CPO conditions".

## Context

A person who runs the Soleur plugin on their own machine gave their agent a shell. Before this change the plugin shipped one
credential guard for browser snapshots and one approval hook for a single staged command form, and nothing that stops an agent
(confused, or prompt-injected through the content it reads) from running `terraform destroy` against that person's production,
force-pushing over their default branch, or deleting their home directory. The repository's own sessions have such guards in
`.claude/hooks/` (`guardrails.sh`), but that directory never ships to customers.

Two reuse paths the slice-1 plan named were measured not to work (Research Reconciliation in the W2 plan): the plugin's
`operator-stage-approval.sh` `tokenize()` parses one simple command and returns failure on every list operator, and the
`guardrails.sh` recursive-delete proof needs bash 4 and GNU `realpath` and leaves `rm -rf ~;` as the token `~;`. A regex over the
command text is structurally blind to the quoted, substituted and heredoc spellings bash still executes, which is the finding of
[ADR-256](./ADR-256-filing-gate-lexer-and-corpus-bound-predicate-parity.md) for the filing gate. That ADR's lexer
(`.claude/hooks/lib/filing-shape.pl`) is measured to read every grammar row W2 needs (it splits `ls && terraform destroy`, unwraps
`bash -c`, keeps `terraform plan 2>&1 | tee log` as two commands, treats `ls #x; terraform destroy` as `ls` plus a comment, keeps a
quoted `"terraform destroy"` as one argument and continues past a heredoc body to the real command).

The threshold is a single-user incident: a false positive on every session, a hook that breaks every Bash call, or a guard that a
one-line respelling walks past each loses the user. So the design target is a narrow set decided exactly, with every residual stated.

## Considered Options

Each rejected option is rejected once, here. Other sites point at this list.

| Option | Why not |
|---|---|
| Lift `tokenize()` from `operator-stage-approval.sh` into `hooks/lib/` | It cannot read a command list, so it buys nothing the lexer does not. Nothing else depends on it and it is untouched |
| Port the `guardrails.sh` segmenter | Needs bash 4 (`mapfile`) and GNU `realpath`, and is not a segmenter (`~;` stays one token). Its logic is reused as a specification, not as code |
| A bash-only quote-aware splitter, no Perl | Priced at plan review. The rows that decide the property (a heredoc then a real command, `$(…;…)`, `bash -c`, a mid-word `#`) are exactly what the `xargs -n1` tokenization already gets wrong; the lexer is measured to read all of them. The cost is a Perl dependency, handled by D6 |
| Move `filing-shape.pl` into the plugin and point `guardrails.sh` at it (one canonical lexer) | Would remove the copy, but ADR-256 binds the original to `cron-bash-allowlist-hook.mjs` through a shared corpus, and the move edits the filing gate and its suites inside a customer-hook PR. Replaced by byte-identical BEGIN/END-marked spans enforced by a test; making the plugin copy canonical is a follow-up |
| Blanket fail-open when `jq` is missing | A one-call disarm: ADR-165 measured that `rm -f /usr/bin/jq` is not matched by the guard, so a chain that removes `jq` then runs `rm -rf $HOME` ran clean. D6 scans the raw envelope instead |
| A Soleur-side telemetry sink for decisions | Observability layer 7 forbids routing a customer-machine run to Soleur infrastructure without consent |
| A local decision log with rotation and a notice marker | Cut at plan review: it writes into the customer's home directory, records no command text (so a false positive cannot be diagnosed from it) and buys none of P1-P4. The harness transcript on the customer's machine records each PreToolUse hook's stdout, stderr and exit code as `hook_success` rows (Measurements); the record of an answered Yes/No prompt is unmeasured |
| `exec` (Devin) coverage with ask-as-deny | Ships a behaviour nobody measured and a dead end for a legitimate `terraform destroy` where the person has no shell to set the kill switch. Devin's `ask` is unmeasured and its envelopes carry no `.cwd` |
| A `drop database` / `dropdb` SQL rule | A fourth class neither the spec nor the charter names, with its own stubs, rows and raw-scan patterns. A follow-up candidate |
| Enabling the guard in hosted sessions | The hosted `ask` path is unmeasured, and hosted Bash is not gated for these commands in the default mode (D8 states what it is gated by). Disabled there by D8; enablement is a follow-up |
| A keyword-only (or quote-normalised) substring prefilter | Buys latency but opens a gap for spellings it cannot see. Replaced by the gap-free prefilter in D7 |
| Reading `permission_mode` to special-case `bypassPermissions` | Buys nothing: `ask` is measured to hold under it |

## Decision

The guard is one PreToolUse hook, `plugins/soleur/hooks/destructive-command-guard.sh`, registered in `plugins/soleur/hooks/hooks.json`
with matcher `^Bash$` and an explicit `timeout`, plus a Perl lexer, `plugins/soleur/hooks/lib/shell-argv.pl`. The hook header is the
reference for the rule table; this section records the decisions and why.

- **D1 — What it decides (Bash tool calls only).** After lexing and unwrapping, each simple command is judged (a command inside
  `bash|sh|zsh|dash|ksh -c`, `eval`, `$(…)`, backticks, `<(…)` and every list operator is its own simple command).
  **deny**: `rm` with a recursive flag in any spelling whose target is `/`, an ancestor of the home directory, the home directory
  or the contents of those (a bare symlink name is not followed, `link/` is). **ask**: `rm` with a recursive flag whose target is the
  working directory or an ancestor of it; `terraform|tofu destroy` and `apply -destroy`; `git push` that force-pushes or deletes a
  default branch (the union of the locally-read `refs/remotes/<named remote>/HEAD`, `main` and `master`); an unresolvable
  `cd`/`pushd` followed in the same list by a recursive `rm` or by a force/delete `git push`. A literal `cd`/`pushd` earlier in the
  list moves the simulated working directory. Wrappers (`sudo`, `doas`, `env`, `command` but not `command -v`, `nohup`, `time`,
  `timeout`, `nice`) are unwrapped from a small option table, `xargs` is not, and the rule table is retried after a `--`
  (`doppler run --`, `aws-vault exec <profile> --`, `op run --`).
- **D2 — Deliberately not decided.** Obfuscation (a variable-built command name, glob or brace expansion of a command name such as
  `r[m]` or `r{m,}`, `xargs rm`, `find -delete`, zsh-only expansions); a script written then run; a piped SQL string and
  `drop database`/`dropdb`; MCP delete tools; any non-Bash tool, Devin's `exec` included; Doppler secret writes and deletes; a plain
  `terraform apply`; `kubectl delete`; `pulumi destroy`; `terragrunt destroy`; `git push --mirror` without `--force`; and an
  unresolvable `$VAR` target. **The kill switch can also be set through a settings-level `env` block, which no Bash guard sees**, so an
  agent that can edit a settings file can disarm the guard: this is a seatbelt, not a boundary. The user-facing sentence (plugin README
  and hook header) says the guard does not cover a plain `terraform apply`, secret writes, SQL or non-Bash tools and is not a
  substitute for scoped credentials. **Dropped from the spec's FR2:** Doppler secret writes and a plain `terraform apply`. Both are
  routine and ambiguous, so asking on them would spend the false-positive budget that makes the unambiguous asks credible; this
  repository's own sessions already defer a plain `terraform apply` through `prod-write-defer-gate.sh`, so the drop costs nothing here.
- **D3 — Ask versus deny.** `deny` only where no legitimate use exists (delete of `/`, home or an ancestor); everything else `ask`.
  `ask` is never an implicit allow in any measured mode (Measurements).
- **D4 — What the person and the agent see.** The reason names the rule id, quotes the matched simple command (truncated at 200
  characters) and tells the agent to stop and tell the person, to end and report blocked when no person is available rather than
  retry or rephrase, and names the two human routes (run it in their own terminal, or start the session with the kill switch) plus an
  issues URL for a false-positive report. A lexer failure uses a distinct reason ("could not parse this command; it was not
  recognised as destructive") so the person is never shown a command that was not matched. Every `deny` also carries a top-level
  `systemMessage` with the same reason (Measurements).
- **D5 — Kill switch.** `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` (exactly `1`; empty, `0` and anything else leave the guard on) exits 0
  silently as the hook's first executable statement, before any dependency probe. It is read from the harness process environment,
  so it needs a session restart.
- **D6 — Failure posture (a stated narrowing of ADR-157's `.claude` row).** An envelope `jq` rejects, empty stdin, a non-string
  `.tool_input.command`, a lexer parse failure and a lexer bound trip all `ask` with the D4 parse reason. A missing or unusable `jq`
  does not ask on every call (that would make the plugin unusable without `jq`): the hook scans the RAW envelope for its own narrow
  patterns, asks on a hit with a hand-built fixed reason and exits 0 on a miss. A missing `perl` with a working `jq` scans the
  `jq`-decoded command the same way. It never denies on a dependency failure, because the repair is itself a Bash call. ADR-157's `.claude`
  row asks on every call when `jq` is missing; ADR-165's `.openhands` row failed open pattern-scoped (a raw-document scan, deny on a
  hit, exit 0 on a miss) because that harness has no `ask` (the `.openhands` mirror was retired by [ADR-245](./ADR-245-retire-openhands-gemini-ports-and-prove-codex-devin-discovery-in-ci.md); ADR-165's status note keeps its reasoning as precedent, so it is cited here as history). W2 takes the second shape with the first's verb: the harness has `ask`,
  a customer machine may lack `jq` for a reason other than an attacker, and `ask` puts a person in the loop without bricking a
  session whose repair is itself a Bash call.
- **D7 — Mechanism.** The Perl lexer's marked spans (three, `BEGIN SHARED-LEXER` to `END SHARED-LEXER`) are byte-identical to the same
  spans in `.claude/hooks/lib/filing-shape.pl`; `shell-argv-parity.test.sh` enforces identity, a span count and a minimum span size.
  `process_command` is replaced by a per-simple-command argv record that carries each word's quoted and expanded flags (so `'~'` is not
  read as home) pushed onto `@RECORDS` (the lexer's rollback depends on it), and the original's 32-record cap is dropped (a script
  with more than 32 commands would otherwise ask on every call). The depth, 8x-input budget and 2 s alarm bounds stay. External
  binaries are `bash` (3.2 or later), `jq`, `perl`, `git` (read-only and local) and POSIX utilities. A zero-spawn prefilter skips the
  lexer only when the command's raw JSON text has none of `rm`, `destroy`, `push`, `eval` and none of backslash, single quote, `$`,
  a backtick or `<<`. Double quote needs no character of its own: inside the JSON string it is always escaped with a backslash, so
  the backslash test sees it. `<<` is in the set because a heredoc whose delimiter word is missing is the one unparseable command
  spelled with none of the other characters, and the lexer path asks on it. No skipped command can be a D1 command (every D1
  command spells `rm`, `destroy` or `push` as a plain substring and every other spelling carries a boundary character); the lexer
  path can still add a parse or wrapper-depth ask to a skipped command, so "every skipped class is allowed by the lexer path" is NOT
  claimed. Every boundary character has a must-ask row. The prefilter's current boundary set is under Post-review hardening.
- **D8 — Hosted sessions.** The plugin's `hooks.json` loads into hosted sessions even with `settingSources: []` (ADR-093's
  2026-09-30 amendment establishes that; its 2026-10-07 amendment records this guard's override), so
  `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` joins `AGENT_ENV_OVERRIDES`. A web-platform census derives every
  PreToolUse hook from `hooks.json` and fails on one that is not classified web-disabled or web-active, and runs the hook with the
  real `buildAgentEnv` output to prove it exits 0 silently. **W2 protects customer-machine plugin users, not hosted founders, and
  hosted Bash is not gated for these commands in the default mode.** What hosted Bash runs under: the bwrap sandbox and the
  workspace's approval mode. `workspaces.bash_autonomous` defaults to `true` for new workspaces (migration 099; existing rows keep
  their stored value), and in that mode `permission-callback.ts` (`if (deps.bashAutonomous)`) auto-approves every Bash command that
  survived `BLOCKED_BASH_PATTERNS`, after a one-time owner acknowledgement. That blocklist covers `curl`, `wget`, `nc`, `eval`,
  `sudo` and the `sh -c` family; it does NOT match `terraform destroy`, `rm -rf` or `git push -f`. The earlier wording that hosted
  sessions "rely on the sandbox and the review gate" was therefore false for the default and was corrected on 2026-10-07 (PR
  review). The hosted `ask` path is unmeasured, which is why the guard is off there rather than on.
- **D9 — Harness scope.** Registered only in `plugins/soleur/hooks/hooks.json`; one `soleur-plugin` ledger row with disposition `skip`
  (Devin's `ask` is unmeasured and its envelopes carry no `.cwd`), no `.claude/settings.json` entry (the parity dry run showed none is
  demanded, and a second registration would double-prompt contributors). This repository's contributor sessions that load the plugin
  get no double prompt: `guardrails.sh` already denies the recursive-delete set, and `prod-write-defer-gate.sh` outranks the
  plugin's `ask` for what its `DEFAULT_TARGETS` match: `terraform|tofu apply` (so `apply -destroy`, and a plain `apply`), and
  `git push [-f|--force|--force-with-lease] origin main|master|HEAD:main|HEAD:master` (so a plain push too). It matches no bare
  `terraform|tofu destroy` and no `--delete`, `:main` or `+main` push form (each run against the gate and answered with no decision);
  for contributors this plugin hook is the only control on those, and the sole `ask` for the other spellings. The headless workflow that loads the plugin (`test-pretooluse-hooks.yml`) inherits the hook and its prompt issues no
  command in D1.
- **D10 — No new processing, no log.** Soleur receives nothing from this hook and the hook writes nothing outside the harness: the
  decision reason in the harness transcript on the customer's own machine is the record, as far as measured: a PreToolUse hook's stdout, stderr and exit code are persisted there as `hook_success` rows, while the record of an answered Yes/No prompt and the expanded view of a deny are unmeasured (follow-ups). No public security claim is made.

## Measurements (Claude Code 2.1.291, `phase-0-measurements.md` section 1.2)

A throwaway stub hook and a scripted Anthropic stand-in inside a loopback-only network namespace; no credential, no paid turn. A
`PostToolUse` sentinel observed execution, so "ran" is observed, not inferred.

- `ask` under `claude -p` blocks the call in every permission mode (`default`, `dontAsk`, `auto`, `acceptEdits`, `plan`,
  `bypassPermissions`), with the full reason delivered to the agent. A headless run degrades to a block, never an allow.
- Interactively `ask` prompts the person in every mode measured, `bypassPermissions`, `dontAsk` and `auto` included (the hook's `ask`
  is not resolved by the classifier). Nothing measured lets a hook `ask` become an allow without a person.
- A subagent turn fires the hook (the envelope carries `agent_id` and `agent_type`), and `ask` reaches the person interactively.
- **Finding that changed D4:** on a `deny` the person sees only a collapsed "Ran 1 shell command"; the `permissionDecisionReason` is
  shown to the agent, not the person. A top-level `systemMessage` renders as `PreToolUse:Bash says: …`, so every `deny` carries one.
  An `ask` needs none (the prompt shows the whole reason, measured to 815 characters unclipped).
- Earlier rows (`ask` holds under `bypassPermissions` and against an allow rule, decision precedence deny > defer >
  ask > allow) stand from `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` and ADR-264 and were not re-run.
- Observed in review, not in `phase-0-measurements.md`: a PreToolUse hook's stdout, stderr and exit code are persisted in the Claude
  Code session transcript as `hook_success` attachments (read from this machine's own transcripts: `hookEvent: PreToolUse`,
  `hookName: PreToolUse:Bash`, `exitCode`, `stdout`, `stderr`). That is the whole of the transcript claim.
- Not measured and not claimed: the hosted Agent SDK `ask` path, a real model's reaction to a block, the auto-mode classifier on a
  real model, answering the prompt (what the transcript holds after the person answers Yes or No), the expanded transcript view of a
  deny, Devin's `ask`.

The mutation evidence is in the same file, section 1.6: 43 mutants for matrix rows 9-20 run once at work time (35 killed on the
first run; of the survivors five were fixture-inadequate and were killed after six rows were added, one is an equivalent mutant, and
one hang counts as a kill by timeout), and rows M1-M8 run in CI by the mutation suite against a copy of the plugin tree.

## Server-side scheduled agents

Twelve functions in `apps/web-platform/server/inngest/functions/` pass `--plugin-dir plugins/soleur` to a headless `claude` spawn:
`cron-agent-native-audit`, `cron-architecture-diagram-sync`, `cron-bug-fixer`, `cron-campaign-calendar`,
`cron-competitive-analysis`, `cron-content-generator`, `cron-growth-audit`, `cron-growth-execution`, `cron-legal-audit`,
`cron-seo-aeo-audit`, `cron-ux-audit` and the event function `event-ship-merge` (`cron-community-monitor` and `cron-roadmap-review`
mention the flag in a comment and do not pass it). Every one spawns through `_cron-claude-eval-substrate.ts` with a per-function
`buildSpawnEnv` allowlist (`PATH`, `HOME`, `NODE_ENV`, `ANTHROPIC_API_KEY`, `GH_TOKEN`) and never calls `buildAgentEnv`, so D8's
override does not reach them (ADR-093's 2026-09-30 amendment already records that headless cron spawns receive no
`AGENT_ENV_OVERRIDES`; #9289 tracks classifying non-Stop plugin hooks for the web runtime). The guard is therefore ACTIVE in those
runs, an `ask` under `claude -p` blocks the call (Measurements), and each spawn also carries the deny-by-default
`cron-bash-allowlist-hook.mjs`. No D1 command is issued by any of them today: a grep of the twelve sources for `terraform`, `tofu`,
`destroy`, a recursive `rm` and a forced or deleting `git push` finds only "Do NOT run git push" prompt prohibitions and Node-side
`rm` of the temporary workspace (not an agent Bash call). This is a classification gap, not a demonstrated false positive; the cost
today is a `jq` and `perl` spawn on lexed Bash calls. Follow-up: decide per function whether to set the kill switch in its
`buildSpawnEnv`, or to leave the guard on and accept ask-as-block.

## Consequences

- A customer running the plugin gets a human confirmation (or, for the home-directory delete, a block) before the agent runs an
  unambiguous destroy in every spelling bash reads as that command, within D2.
- The cost is a Perl dependency for full fidelity (present on macOS, nearly every Linux and Git for Windows; absent on minimal
  Alpine-style images, where D6 keeps the guard on narrowly) and a second copy of the lexer, bound to the original by the parity test
  rather than by being one file.
- Added latency per Bash call is bounded by the zero-spawn prefilter for ordinary commands and measured once for the lexed path (the
  figures are in the PR body, not here, so they are not stale in a record).
- A headless run that legitimately needs `terraform destroy` has no per-rule allow; the kill switch is all-or-nothing (follow-up).
- The decision set is code in the same diff as its suite, so a weakening that edits both passes the suite. The independent anchors are
  the oracle (it runs real bash against recording stubs and can never execute a destructive command), the registry parity tests and
  the vacuity-floor gate that read committed state, the CPO sign-off against a named SHA, and the functional probe in
  `scripts/verify-agent-security-slice1.sh`.

## Residuals (as shipped; none is hidden)

- **A raw-scan miss with `jq` missing is an allow.** The one implicit allow in the hook's own failure paths, stated and tested. It is the
  raw-scan-miss residual ADR-165 accepts for its `.openhands` row.
- **The shared lexer lexes identical `bash -c` / `eval` strings once**, so the working-directory simulation cannot tell two identical
  inner strings under different `cd`s apart.
- **A `cd` inside a subshell or `$(…)` is sticky** for the later commands: it over-asks, never under-asks.
- **Partial globs such as `rm -rf ~/.*` are not decided.**
- **A directory literally named `~` is also denied when written `~/`** (and `~/*`); a quoted bare `'~'` is read as the literal directory
  and is not.
- **An unresolvable `cd` before a plain `git push` is not asked**; only the force and delete forms are (a plain push is routine).
- **The prefilter includes `<<`** because a heredoc with no delimiter word would otherwise be skipped and never reach the lexer
  path that asks on it (D7).
- **Not decided, as the shipped hook header lists it (NOT DECIDED):** `exec`, `builtin`, `setsid`, `ionice`, `stdbuf`, `flock`,
  `nsenter`, `chroot`, `su -c` and `sudo -s '...'`, `coproc`; trap strings, function bodies and aliases (including `git -c
  alias.x=push`); stdin-fed shells (a heredoc, here-string or pipe into `bash` or `sh`) and `source <(...)`; brace-expanded targets
  such as `/{bin,usr}` and brace or glob expansion of a command name; `xargs rm`, `find -delete` and `find -exec rm`, `rsync
  --delete`; other interpreters and tools (python `shutil.rmtree`); a runner name in another case (`BASH -c`); `terragrunt` and
  `pulumi destroy`; and the D2 list above. Each was considered and left out; none is hidden.
- **Seatbelt, not boundary:** the settings-env route to the kill switch and everything in D2.

## Post-review hardening (2026-10-07)

The panel review of PR #9653 changed the shipped hook beyond, or differently from, the text of D1-D10 above. The plan's Decision Set
text (the CPO-signed section, whose hash is recorded in the PR body) was NOT edited. The CPO's two-round cap was spent before the
review, so none of this has been put back to the CPO. These are refinements of the signed set; the operator may choose to take them
back to the CPO. The hook header is the reference for each rule; the list below says what differs, once.

- **Targets.** A target whose every component after the glob-free root is only glob syntax (`/**`, `/*/*`, `~/**`) counts as the
  contents of `/` or home; `~+` is the working directory; with `HOME` unset or empty `~` is the passwd entry's home and `$HOME/` is `/`.
  A component that mixes literal text with a glob (`~/*/node_modules`, `/*.log`) is still not decided.
- **Working directory.** The check runs against BOTH the envelope's `cwd` and the one a literal `cd`/`pushd` earlier in the command
  moved to. A decision made while handling one simple command no longer leaks into the next (`cd -- ~ && rm -rf *` is a deny).
- **Names and wrappers.** Command names are compared in lower case (`RM`, `Git`, `Terraform`); a runner name is not (`BASH -c` is NOT
  DECIDED). `time` is a wrapper as a command word and `time -p` is recovered; short-option clusters whose last letter takes a value are
  parsed (`sudo -nu root`, `env -iu X`, `timeout -vk 5 10`). `-destroy=<value>` is a destroy unless the value is a Go false;
  `git` option abbreviations (`--al`, `--m`), a `heads/` destination, a glob destination and `--config-env` are read.
- **New ask classes, each with its own rule id.** `unparsed-wrapper` (`env -S`, `--split-string` and its abbreviations: the string it
  splits is not analysed); `wrapper-depth` (more than 8 nested wrappers or `--` separators); `bound` (more than 2000 simple commands,
  more than 20000 words, or the 6 second `DEADLINE_S` wall clock reached, unless a deny was already found); `lexer-empty` (the lexer
  returned no command for text that, minus comments, mentions `rm`, `destroy`, `push`, `terraform`, `tofu`, `git` or `eval` in any
  case; a blank, comment-only or keyword-free command such as `> out.log` is allowed).
- **Reasons.** Every reason opens "This command was NOT run." Parse-class asks (`command-not-parsed`, `envelope-unreadable`,
  `lexer-empty`) end with a fix-and-resend tail instead of "do not retry"; `bound` ends with a split-it tail. The quoted command has
  credentials masked (`NAME=value` where the name holds key, token, secret, password, passwd, cred or auth; URL userinfo) BEFORE the
  200-character cut. D4's "do not retry or rephrase" therefore holds for the destructive-command asks only.
- **Prefilter.** It decides only when the envelope holds exactly one `"command"` text; `<(`, `>(`, `<<` and the case variants
  `Rm`, `RM`, `rM` are boundaries. A dead `hook_tool_kind` sourcing (a per-call stderr warning if its library was missing) was removed; the raw `tool_name` must still be exactly `Bash`.
- **Not changed:** D1's families, D3's deny set, D5, D6's posture and D8/D9's scope. A wrapper outside the table is still NOT DECIDED
  (Residuals), by decision, not by omission.

User-visible differences from the signed text, for a re-sign-off decision: the four new ask classes, case-insensitive command names,
glob-only targets, credential masking, and the reason wording.

## CPO conditions and how each is satisfied

- **C1 — an honest scope statement where users read it.** The plugin README and the hook header carry the one sentence from D2.
- **C2 — the hosted gap stated outside this ADR.** The plugin README carries one line that the guard is not active in Soleur-hosted
  sessions and says what hosted Bash runs under (D8 is the single statement of why; the README sentence is pinned verbatim by the hook
  suite). The ADR-093 amendment of 2026-10-07 records it for the hosted path and carries a dated correction of the first wording.
- **C3 — follow-ups durably recorded, not left as prose.** The CPO asked for one filed tracking issue. The repository's filing gate
  (`guardrails:require-filing-justification`) refuses a roll-up issue unless it carries a measured fix size, and a roll-up has none; the
  operator therefore decided on 2026-10-07 to record the list here, in the section below, and in the plan's Non-Goals, which is what
  `wg-when-deferring-a-capability-create-a` prescribes. This is a recorded deviation from the literal wording of C3, not a silent one;
  the PR body states it. Each item becomes its own issue when someone picks it up with a measured size.
- **C4 — a deny the person can read.** Every `deny` carries `systemMessage` with the full reason, the escape hatch and the issues URL;
  a suite row asserts it.

## Open follow-ups (recorded here; no tracking issue by operator decision, see C3)

Enabling the guard in hosted sessions (needs a measured hosted `ask` path); Devin `exec` coverage and Devin `ask` measurement; a
per-rule allow for headless CI teardown; a settings-env tripwire; a session-start message stating full or degraded dependency
posture (the stderr notice for a missing `jq` or `perl` is likely invisible to the person); the D2 candidates (the SQL rule, a plain
`terraform apply`, secret writes, `kubectl delete`, `pulumi`/`terragrunt destroy`, `git push --mirror`, `find -delete`); a canonical
plugin-side lexer for the filing gate when it is next touched; and moving the `%FIND_ACT` and `$MAX_RECORDS` declarations above the
`BEGIN SHARED-LEXER` marker in `filing-shape.pl` so the lexer spans stop depending on two filing-only names (an incidental coupling
the parity test currently tolerates); and a README note, now added, that where `/dev/fd` or `/proc` is unavailable (a minimal sandbox without
`/proc`) the hook reads the lexer output through process substitution and so asks with the parse reason instead of denying (fail-safe,
but noisy for every lexed command).

Added by the 2026-10-07 post-review pass: a per-cron decision on the kill switch for the server-side agents (see Server-side scheduled
agents); the plugin-wide unquoted `${CLAUDE_PLUGIN_ROOT}` command paths in `hooks.json` (a plugin root containing a space breaks every
such hook, not only this one; left as the plugin's convention); a hosted-visible statement of the gap (a hosted founder or agent cannot
see the plugin README, so nothing in the hosted prompt says the guard is off); a heredoc, pipe or here-string fed to a shell as a
plausible agent pattern left undecided (follow-up: treat the body as code when the command is a shell without `-c`); the record of an
answered Yes/No prompt and the expanded view of a deny (unmeasured; the transcript claim is scoped to `hook_success` rows); shard-manifest
rows for the two heavy suites (without them the hash fallback can stack both on one CI leg); deleting the prefilter (the simplicity
review estimated about 2 ms of average saving against two defects; deferred because the prefilter is D7 and its deletion reopens the
signed set); and a real run of the suites under bash 3.2 (the hook itself was run under 3.2.57 on a 43-command corpus with identical
decisions to bash 5.3; the suites ran under the host bash only).

## Cost Impacts

None. No new vendor, service or paid API; the hook runs locally and sends nothing.

## NFR Impacts

None. The NFR register's `Hook Engine` rows describe this repository's own guard scripts; this hook ships in the plugin to the
customer's machine and changes no register row.

## Principle Alignment

- AP-020 (untrusted input at the agent boundary): Aligned. The hook treats stdin as model-controlled, never evaluates it, checks that
  `.tool_input.command` is a string, and asks on anything it cannot read.
- AP-023 (an anti-vacuity floor reports directly): Aligned. The new suites carry a literal floor reported by `printf` and `exit 1`
  and a call-site counter, and score FIRES under the vacuity-floor gate.
- AP-011 (ADRs for architecture decisions): Aligned. This record, the ADR-093 amendment and the C4 component.

## Verification

- `plugins/soleur/test/destructive-command-guard-hook.test.sh`: every rule, spelling and must-pass row, with expectations derived from
  a real shell run against recording stubs and a stub-only `PATH` canary.
- `plugins/soleur/test/destructive-command-guard-mutation.test.sh`: M1-M8, each reddening the suite in a copy of the plugin tree.
- `plugins/soleur/test/shell-argv-parity.test.sh`: the three shared lexer spans are byte-identical to `filing-shape.pl`'s.
- The registry parity tests (`devin-matcher-parity.test.sh`) and `scripts/guard-vacuity-floor.test.sh`.
- `apps/web-platform/test/server/agent-env-allowlist.test.ts` and the PreToolUse classification census: the hosted override.
- `scripts/verify-agent-security-slice1.sh`: the registration and a functional probe of the three canonical decisions, run from a
  temp HOME and cwd; `scripts/verify-agent-security-slice1.test.sh` drives copies of the plugin hooks through the probe's seam and
  turns it red for a non-Bash matcher, an unregistered hook, a silent hook, a hook that asks for `ls` and a missing `jq` or `perl`.
