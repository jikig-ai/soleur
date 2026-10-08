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

# ADR-277: The customer plugin ships a narrow, lexer-based destructive-command guard that asks (or denies) and degrades to a raw scan

## Status

**Accepted at merge (W2 of the agent-security epic #9601, PR #9653).** The behaviour is measured in the suites named under
Verification, so there is no `adopting` window as ADR-272 had. **Extends [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md)
and [ADR-165](./ADR-165-what-ask-means-on-a-harness-with-no-ask-state.md)** (both are bullet-style records with no YAML extends key, so
the relation is stated here and carried in `related_adrs`). It narrows one row of ADR-157's `.claude` failure table on purpose (D6) and
is the first ADR to apply that table to a hook that ships to customers rather than to this repository's own sessions.

The product owner (CPO) signed the **plan's** Decision Set (`## Final W2 Decision Set` in
`knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md`) before any implementation commit, on
revision `3a60924ebd6ff3b3482b9e8972c0d9b890c4f92e` and section SHA-256
`39593c04ced72bc4a7e6a768408cef4baaa6b22d52069b4836566bb00385d81a`, both recorded in the body of PR #9653; the four conditions the
sign-off attached are listed with their satisfaction under "CPO conditions". **This record is not that signed text.** D1 (the `cd` rule
narrowed to force and delete pushes), D2 (the longer non-coverage sentence), D4 (measured detail dropped, a caveat added) and D6-D10 differ
from it, the Considered Options were rewritten, and the shipped hook goes beyond D1-D10 in the places listed under "Post-review hardening"
(the list a re-sign-off would decide on, with what the CPO has not seen). The plan's Decision Set itself was not edited.

**The plan's own re-run rule was not followed, and nobody has waived it.** The plan says any change to D1-D9 after sign-off, from any later
phase, re-runs Phase 0.3. The CPO's cap of two rounds was spent (round 2 of 2) before the review found what changed D1, D7 and D8, so the
re-run did not happen and the hash gate stays green only because the signed section was left as it was. This is a recorded deviation, not a
decision: the operator may take the list under "Post-review hardening" back to the CPO (`decision-challenges.md` T13).

**Closed on 2026-10-08 by a third CPO pass, which the operator asked for after the merge.** Verdict: APPROVED WITH REQUIRED CHANGES, no
change to the merged hook; see "CPO third pass" below. The deviation above stays on the record as it happened.

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
  agent that can edit a settings file can disarm the guard: this is a seatbelt, not a boundary. The user-facing sentence sits in the
  plugin README and the hook header, **word for word the same in both** (the hook suite pins the README copy and a row compares the
  header's). It is **longer than the sentence the CPO signed**, which named only a plain `terraform apply`, secret writes, SQL or
  non-Bash tools and scoped credentials: the README commit widened it to `terragrunt` or `pulumi` destroy and indirect command
  forms (scripts or heredocs fed to a shell, wrappers the guard does not unwrap, obfuscated command names), because the short
  sentence let a reader assume those were covered. **Dropped from the spec's FR2:** Doppler secret writes and a plain `terraform apply`. Both are
  routine and ambiguous, so asking on them would spend the false-positive budget that makes the unambiguous asks credible; this
  repository's own sessions already defer a plain `terraform apply` through `prod-write-defer-gate.sh`, so the drop costs nothing here.
- **D3 — Ask versus deny.** `deny` only where no legitimate use exists (delete of `/`, home or an ancestor); everything else `ask`.
  `ask` is never an implicit allow in any measured mode (Measurements).
- **D4 — What the person and the agent see.** The reason names the rule id, quotes the matched simple command (truncated at 200
  characters) and tells the agent to stop and tell the person, to end and report blocked when no person is available rather than
  retry or rephrase, and names the two human routes (run it in their own terminal, or start the session with the kill switch) plus an
  issues URL for a false-positive report. A lexer failure uses a distinct reason ("could not parse this command; it was not
  recognised as destructive") so the person is never shown a command that was not matched. Every `deny` also carries a top-level
  `systemMessage` with the same reason (Measurements). This is the wording for a matched destructive command as signed; how an ask
  opens for the person and which tail each other cause gets are under Post-review hardening, "Reasons".
- **D5 — Kill switch.** `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` (exactly `1`; empty, `0` and anything else leave the guard on) exits 0
  silently as the hook's first executable statement, before any dependency probe. It is read from the harness process environment,
  so it needs a session restart.
- **D6 — Failure posture (a stated narrowing of ADR-157's `.claude` row).** An envelope `jq` rejects, empty stdin, a non-string
  `.tool_input.command`, a lexer parse failure and a lexer bound trip all `ask` with the D4 parse reason (the further inability asks,
  `bound`, `lexer-empty`, `unparsed-wrapper` and `wrapper-depth`, and the reasons by cause, are under Post-review hardening). A missing or unusable `jq`
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
  lexer only when every one of these holds, and each is a rule that fails toward the lexer path, never toward an allow: the tool call
  is at most 256 KiB (a larger one asks `bound` before the prefilter or any parser reads it); the envelope holds exactly one `"command"` text (a decoy
  or duplicate key goes to `jq`, which reads `.tool_input.command`); the envelope holds no backslash followed by `u` anywhere (a key
  spelled `"\u0063ommand"` is the key `command` to `jq` but not the text `"command"` to the count, so any `\u` goes to `jq`); and the
  command's raw JSON text has none of `rm` (also `Rm`, `RM`, `rM`), `destroy`, `push`, `eval` and none of backslash, single quote,
  `$`, a backtick, `<(`, `>(` or `<<`. Double quote needs no character of its own: inside the JSON string it is always escaped with a
  backslash, so the backslash test sees it. `<<` is in the set because a heredoc whose delimiter word is missing is the one
  unparseable command spelled with none of the other characters, and the lexer path asks on it; `<(` and `>(` because an
  unterminated process substitution is skipped by a keyword-only test yet asks on the lexer path. No skipped command can be a D1
  command (every D1 command spells `rm`, `destroy` or `push` as a plain substring and every other spelling carries a boundary
  character). Had the lexer path run on a skipped command it could add a parse, `unparsed-wrapper` or `wrapper-depth` ask (never a
  destructive-command decision), so "every skipped class is allowed by the lexer path" is NOT claimed, and those three asks are
  conditional on the prefilter: `env -S ls` and nine nested `env` plus `ls` are skipped and not asked. Every boundary character has a must-ask row. The hook header (MECHANISM AND ORDER) is the
  reference for the prefilter.
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

<!-- lint-infra-ignore start: this paragraph RECORDS the result of grepping the server-side agents' skill and prompt texts for destructive commands; it prescribes no human-run step -->
Twelve functions in `apps/web-platform/server/inngest/functions/` pass `--plugin-dir plugins/soleur` to a headless `claude` spawn:
`cron-agent-native-audit`, `cron-architecture-diagram-sync`, `cron-bug-fixer`, `cron-campaign-calendar`,
`cron-competitive-analysis`, `cron-content-generator`, `cron-growth-audit`, `cron-growth-execution`, `cron-legal-audit`,
`cron-seo-aeo-audit`, `cron-ux-audit` and the event function `event-ship-merge` (`cron-community-monitor` and `cron-roadmap-review`
mention the flag in a comment and do not pass it). Every one spawns through `_cron-claude-eval-substrate.ts` with a per-function
`buildSpawnEnv` allowlist (`PATH`, `HOME`, `NODE_ENV`, `ANTHROPIC_API_KEY`, `GH_TOKEN`) and never calls `buildAgentEnv`, so D8's
override does not reach them (ADR-093's 2026-09-30 amendment already records that headless cron spawns receive no
`AGENT_ENV_OVERRIDES`; #9289 tracks classifying non-Stop plugin hooks for the web runtime). The guard is therefore ACTIVE in those
runs, an `ask` under `claude -p` blocks the call (Measurements), and each spawn also carries the deny-by-default
`cron-bash-allowlist-hook.mjs`. No D1 command is issued by any of them today. The twelve TypeScript sources hold only "Do NOT run
git push" prompt prohibitions and Node-side `rm` of the temporary workspace (not an agent Bash call). Because the crons run
skills, not only prompts, the skill texts were grepped as well, for `terraform|tofu` with `destroy`, `apply -destroy`, a recursive
`rm` of `/`, `~`, `$HOME`, `..` or the working directory, and a forced or deleting `git push`: the skills the sources invoke
(`ship`, `fix-issue`, `ux-audit`, `agent-native-audit`, `campaign-calendar`, `competitive-analysis`, `content-writer`, `growth`,
`social-distribute`, `seo-aeo`, `legal-audit`; `cron-architecture-diagram-sync` names none), `merge-pr`, `work`, `architecture`
and the skills `ship` names (`deploy`, `postmerge`, `one-shot`, `plan`, `review`, `preflight`, `compound`, `test-fix-loop`,
`reproduce-bug`, `release-announce`, `operator-bootstrap`, `incident`, `gdpr-gate`, `schedule`, `go`). The only command match is
`merge-pr`, which force-pushes a feature branch (`git push --force-with-lease origin <branch-name>`, twice) and is not a D1
command; the other matches are prose or false matches of the pattern (`review` mentions `terraform destroy` while describing a guard; `one-shot` forbids asking the operator to `git push origin --delete` a stale branch by hand). The grep reads text,
so a command a skill assembles at run time is not covered. **"No D1 command" does not bound what can block a cron:** the asks that
fire on non-D1 input (`bound`, `lexer-empty`, `wrapper-depth`, `unparsed-wrapper`, and the parse and envelope asks) block a
headless run the same way, on any command that trips them. The classification is pinned by a census in
`apps/web-platform/test/plugin-pretooluse-hooks-web-parity.test.ts`: exactly twelve functions pass `--plugin-dir` (comments do not
count), none of them nor the shared substrate names the kill switch, and none reaches `buildAgentEnv` or `AGENT_ENV_OVERRIDES`.
This is a classification gap, not a demonstrated false positive; the cost today is a `jq` and `perl` spawn on lexed Bash calls.
Follow-up: decide per function whether to set the kill switch in its `buildSpawnEnv`, or to leave the guard on and accept
ask-as-block.
<!-- lint-infra-ignore end -->

## Consequences

- A customer running the plugin gets a human confirmation (or, for the home-directory delete, a block) before the agent runs an
  unambiguous destroy in every spelling bash reads as that command, within D2.
- The cost is a Perl dependency for full fidelity (present on macOS, nearly every Linux and Git for Windows; absent on minimal
  Alpine-style images, where D6 keeps the guard on narrowly) and a second copy of the lexer, bound to the original by the parity test
  rather than by being one file.
- Added latency per Bash call is avoided by the zero-spawn prefilter only for commands that spell none of its keywords or boundary
  characters (`rm` is a substring of `terraform`, `format`, `confirm` and `platform`, so `npm run format` is lexed) and measured
  once for the lexed path (the figures are in the PR body, not here, so they are not stale in a record).
- A headless run that legitimately needs `terraform destroy` has no per-rule allow; the kill switch is all-or-nothing (follow-up).
- The decision set is code in the same diff as its suite, so a weakening that edits both passes the suite. The independent anchors are
  the oracle (it runs real bash against recording stubs and can never execute a destructive command), the registry parity tests and
  the vacuity-floor gate that read committed state, the CPO sign-off against a named SHA, and the functional probe in
  `scripts/verify-agent-security-slice1.sh`.

## Residuals (as shipped; none is hidden)

- **A raw-scan miss with `jq` missing is an allow.** An implicit allow in the hook's own failure paths (a miss in the decoded scan with
  `perl` missing is the same), stated and tested. It has the shape of the raw-scan-miss residual ADR-165 accepted for its retired
  `.openhands` row.
- **A hook killed at the harness's 10 s timeout is an implicit allow too.** The caps (256 KiB envelope, 4096 bytes a word, 128 path
  components, 2000 records, 20000 words, 16 KiB a degraded segment and 64 KiB of them in all) and the 6 s deadline exist to keep every
  path inside it, and they hold on every shape the reviews measured. They do not hold by construction: a loaded machine can push a
  path of several seconds past the deadline into a `bound` ask (never an allow), and a stall inside one bash expansion is not
  interruptible. Round 2 found three shapes that ran past 10 s and closed them (a long word, a comment-only command of tens of
  thousands of lines, two near-cap degraded segments).
- **A chdir wrapper around a shell or `eval` makes the directory unresolved after it** (`env -C /tmp bash -c 'rm -rf ./x'` asks): the
  lexer makes the inner string a record of its own, and the guard cannot place that record in the wrapper's directory. An over-ask,
  never an under-ask.
- **The shared lexer lexes identical `bash -c` / `eval` strings once**, so the working-directory simulation cannot tell two identical
  inner strings under different `cd`s apart.
- **A `cd` inside a subshell or `$(…)` is sticky** for the later commands: it over-asks, never under-asks.
- **Partial globs such as `rm -rf ~/.*` are not decided.**
- **A directory literally named `~` is also denied when written `~/`** (and `~/*`); a quoted bare `'~'` is read as the literal directory
  and is not.
- **An unresolvable `cd` before a plain `git push` is not asked**; only the force and delete forms are (a plain push is routine).
- **Not decided:** the hook header's NOT DECIDED list is the single list of what the guard does not judge (wrappers and interpreters
  outside the table, strings run later, stdin-fed shells, expansions it cannot read, other tools); D2 above adds the product-level
  items. Each was considered and left out; none is hidden.
- **Seatbelt, not boundary:** the settings-env route to the kill switch and everything in D2.

## Post-review hardening (2026-10-07)

The panel review of PR #9653 and two fix rounds changed the shipped hook beyond, or differently from, the text of D1-D10 above. The
plan's Decision Set text (the CPO-signed section, whose hash is recorded in the PR body) was NOT edited. The CPO's two-round cap was
spent before the review, so none of this has been put back to the CPO. These are refinements of the signed set; the operator may
choose to take them back to the CPO. The hook header is the reference for each rule. **This section is the one list** of what
differs from the signed text: the plan addendum and `decision-challenges.md` (T13) point here instead of repeating it.

- **Targets.** A target whose every component after the glob-free root is only glob syntax (`/**`, `/*/*`, `~/**`) counts as the
  contents of `/` or home; `~+` is the working directory; with `HOME` unset or empty `~` is the passwd entry's home and `$HOME/` is `/`.
  A component that mixes literal text with a glob (`~/*/node_modules`, `/*.log`) is still not decided.
- **Working directory.** The check runs against BOTH the envelope's `cwd` and the one a literal `cd`/`pushd` earlier in the command
  moved to. A decision made while handling one simple command no longer leaks into the next (`cd -- ~ && rm -rf *` is a deny). A
  wrapper's own chdir option (`env -C DIR`, `env --chdir=DIR`, `sudo -D DIR`, `sudo --chdir=DIR`) moves the simulated directory for
  the command it runs, for that command only; a directory the guard cannot resolve is an unresolved `cd`.
- **A narrowing of signed D1.** The signed text asks on "an unresolvable `cd` followed by a recursive `rm` or a `git push`". The
  shipped hook asks only when that `git push` is a force or delete push (a plain push after an unresolvable `cd` is routine and is
  not asked; `cd $X && git push origin feat` gets no decision, `cd $X && git push -f origin feat` asks).
- **Names and wrappers.** Command names are compared in lower case (`RM`, `Git`, `Terraform`); a runner name is not (`BASH -c` is NOT
  DECIDED), and neither is the case of a `git` or `terraform` SUBCOMMAND (`git PUSH -f`, `terraform DESTROY` get no decision; see the
  follow-ups). `time` is a wrapper as a command word and `time -p` is recovered; short-option clusters whose last letter takes a
  value are parsed (`sudo -nu root`, `env -iu X`, `timeout -vk 5 10`). `-destroy=<value>` is a destroy unless the value is a Go
  false; `git` option abbreviations (`--al`, `--m`), a `heads/` destination, a glob destination and `--config-env` are read.
- **New ask classes, each with its own rule id.** `unparsed-wrapper` (`env -S`, `--split-string` and its abbreviations: the string it
  splits is not analysed); `wrapper-depth` (more than 8 nested wrappers or `--` separators: the two share one counter, so nine `--`
  words ask even with no wrapper once the command reaches the lexer path); `bound` (a command too large to check: a tool call over
  256 KiB, checked before the prefilter or any parser reads it; more than 2000 simple commands; more than 20000 words; a single word
  over 4096 bytes where the rule table would expand it (`MAX_WORD_BYTES`; a command name, a path, a wrapper's option or a dash word of
  `git`, `terraform` or `tofu`: bash's expansions on one word are quadratic in its length, and no clock check can interrupt one). A long
  argument that is only text (a PR body, a commit message, an echo argument, an assignment value) is never expanded, so it is not
  judged and is not asked about; a long word behind a wrapper (`timeout 5 gh pr create --body "<5 KB>"`) is read as an option and does
  ask. A review-time measurement over the reviewer's own agent transcripts found no lexed word over 2007 bytes (not reproducible from
  the repository); a target path of more than 128 components; a segment over 16 KiB, or more than 64 KiB of
  segments in all, in a degraded scan; or the 6 second `DEADLINE_S` wall clock reached; what was read before the
  limit is still judged, so a deny already found wins, and an ask-class match keeps its own rule id and reason with a sentence
  saying the rest was not checked); `lexer-empty` (the lexer returned no command for text that names something the guard decides on:
  a whole-word `rm`, `destroy`, `push`, `terraform`, `tofu`, `git` or `eval` in any case, also after quote, backslash and backtick
  removal so that `r""m` is read; both passes read the last path component of a token, so `/bin/rm` counts and `git/err` does not;
  full-line comments are skipped; a blank or comment-only command, and a bare redirect to a file that merely contains one, quoted or
  not, such as `> terraform.log` or `> "docs/confirm.md"`, is allowed; a command that is only a heredoc or here-string asks). `unparsed-wrapper` and `wrapper-depth` fire only on a command the
  prefilter lets reach the lexer path (D7), so `env -S ls` is not asked.
- **Degraded scans.** The raw (`jq` missing) and decoded (`perl` missing) scans read a run of blanks between the words of
  `terraform`, `tofu` and `git` commands as one gap, and ask `bound` at a segment over 16 KiB, at 64 KiB of segments in all, or at the
  deadline. The narrower scan cannot see the branch or the quoting, so it asks on every force push (a routine feature-branch
  `git push --force-with-lease` too) and on text that only names a destroy (a commit message): the plugin README says so.
- **Reasons.** An ask opens with a sentence for the person at the prompt ("The guard paused this command and is asking you. It has
  not run yet and runs only if you approve."), then the rule id, a one-sentence lead and the quoted command, then the agent's
  instructions under "If you are the agent: This command was NOT run."; a deny opens "This command was NOT run." and also goes in
  `systemMessage`. The agent's tail follows the cause: a matched destructive command (`infra-destroy`, `default-branch-force-push`,
  `recursive-delete-home`, `recursive-delete-workdir`) says stop, do not retry, do not rephrase; a lexer parse failure (`command-not-parsed`, exit 2) and `lexer-empty` say fix the quoting or heredoc and send it again;
  a lexer that gave out (depth, budget, alarm, crash) and `bound` say split it; a lexer that produced no result or malformed output
  (an environment fault: every piece of a split command fails the same way) and `envelope-unreadable` say stop and tell the person;
  `unparsed-wrapper` and `wrapper-depth` say write the command out so the guard can check it; `unresolved-cd-before-destructive` says
  to put a literal directory in the `cd`, not "do not rephrase".
  Every ask and deny carries the kill-switch route and the issues URL. The quoted command has credentials masked BEFORE the
  200-character cut: `NAME=value`, `--name=value` and `-var name=value` where the name holds key, tok, secret, pass, pw, cred, auth
  or bearer; the word after `--token`, `--password`, `--passwd`, `--secret`, `--api-key`, `--auth` or `--bearer`; the text after
  `Authorization:` or after the word `Bearer`; URL userinfo (not the `git@` of an ssh remote); never a command word or a destructive
  operand (`rm -rf --password /` keeps the `/`). That is a coverage choice, not a boundary: a name that merely contains a cue
  (`AUTHOR=`, `-var key_name=`) is masked too, and the person reads the original command at the Bash prompt. When `jq` cannot build the output the
  decision and the rule id are kept (a deny stays a deny).
- **Prefilter.** The rules are in D7: exactly one `"command"` text, any `\u` goes to `jq`, the 256 KiB cap, and `<(`, `>(`, `<<` and
  the case variants `Rm`, `RM`, `rM` as boundaries. The raw `tool_name` must still be exactly `Bash`.
- **Registration.** `hooks.json` registers `bash "${CLAUDE_PLUGIN_ROOT}/hooks/destructive-command-guard.sh"`, quoted, so a plugin root
  containing a space does not break it; the census derives the file name through the `bash "..."` wrapper. Four of the ten command
  strings in `hooks.json` were already written that way (`codex-session-start`, `devin-session-start`, `compaction-state` twice);
  the unquoted ones that remain are a plugin-wide follow-up.
- **Fix round 2, final batch (A-I).** A: a 4096-byte word cap at the frame reader. B: `lexer-empty` reads the text once, by word and by
  basename. C: the degraded scans capped at 16 KiB a segment and 64 KiB in all, and the perl-less quote gather stopped at the 200
  shown characters. D: the two wide `git push` rows shrunk to 5000 refs. E: the agent's tail for a lexer fault and an unresolved `cd`.
  F: the judge extension counted from the trip, sudo long options read by unique prefix, an absolute wrapper chdir clearing an earlier
  unresolved `cd`, a chdir wrapper around a shell, the masking and the marker byte. G: the bash-4 gate widened, the limits named
  (`MAX_WRAP`, `QUOTE_MAX`, `MAX_PATH_COMPONENTS`). H: the test-design seat's survivors as rows, the verdict-owning wrappers driven with a
  bad input, a narrowed run refused in CI, and one hook change the rows found (`cd_index` skips any run of `-p`/`--` after `command` or
  `builtin`: `command -p -- cd /tmp && rm -rf ./*` in home was read as no cd and denied). I: this section. The verification pass after
  it found two under-asks and seven smaller defects in the fix commits themselves, fixed inline: a shell behind any wrapper under a
  chdir wrapper, `timeout`/`nice`/`time` long options by prefix, the word cap asking about prose it never expands, a judge-extension
  ceiling, the reason text for a chdir wrapper around a shell, masking by position, and the reporter probe.
- **Fix rounds.** The commits whose subject ends `(fix round 1, R<n>)` and `(fix round 2, T<n>)` carry the rest. Hook: R1 path
  resolution bounded (one subshell per directory, a cache, a 128-component cap); R2 command-name case fold without a process; R3 a
  read-time bound trip still judges what was read; R4 the bound note appended to a matched rule's reason; R5 the degraded scans and the
  oversize envelope bounded; R6 any `\u` to `jq`; R7 `lexer-empty` as a word test; R8 the redaction shapes above; R9 reasons by
  cause and the output fallback; R10 wrapper chdir options; R11 the envelope fields read without a `jq` regex function; R12 the
  clock checked in the `git push` loops; R13 the quoted registration; R14 the header rewritten to what the hook does. Tests (T1-T10; T8 is a hook change, the run of blanks in
  the degraded scans): the hook suite's instrument self-test drives the verdict layer, every rule id is asserted by exact id and the roster is an exact
  set, the README rows compare whole lines and hide an unclosed comment, length controls on the stress rows, the executed-row lint
  refuses more escape shapes, the lexer parity suite rows the first line of spans 1 and 2, the mutation suite drives its wiring, and
  a census pins that the twelve server-side agents leave the guard active.
- **Not changed:** D1's families, D3's deny set, D5, D6's posture, and the scope of D8 and D9. D8's premise was corrected (below),
  not its decision. A wrapper outside the table is still NOT DECIDED (the hook header's list), by decision, not by omission.

**User-visible differences from the signed text, for a re-sign-off decision:**

1. **The D8 premise.** The signed D8 and its README line said hosted Bash is "already sandboxed and gated by `permission-callback.ts`".
   In the autonomous default (`workspaces.bash_autonomous` defaults to `true`, migration 099) it is not gated for these commands:
   `BLOCKED_BASH_PATTERNS` does not match `terraform destroy`, `rm -rf` or `git push -f`. The decision (guard disabled in hosted
   sessions) is kept; the stated reason changed. Whether hosted founders should be protected against these commands in autonomous
   mode is a product question for the operator (`decision-challenges.md` T12).
2. **Two README sentences the CPO's conditions C1 and C2 are about were rewritten:** the non-coverage sentence is longer (D2) and the
   hosted line now says what hosted Bash runs under (D8). A third sentence is new: the guard also asks, rather than allows, when it
   cannot read a command it was given.
3. **The narrowing of D1's `cd` rule** to force and delete pushes (above).
4. **Broader behaviour:** a wrapper's chdir option is applied; case-insensitive command names; glob-only targets; the four new ask
   classes with their triggers (some commands that used to run silently now ask, and a headless run blocks on them); the new size
   bounds; credential masking in the quoted command, in the shapes above; the degraded scans reading a run of blanks.
5. **Wording:** an ask opens with a sentence for the person, the agent's tail follows the cause, and "do not retry or rephrase" is
   the tail of a matched destructive command only; a deny already found wins after a bound trip.
6. **Registration:** the quoted `bash "${CLAUDE_PLUGIN_ROOT}/..."` form.

## CPO conditions and how each is satisfied

- **C1 — an honest scope statement where users read it.** The plugin README and the hook header carry the same non-coverage
  sentence, word for word; it is longer than the sentence signed in D2 (see D2 for what it adds and why), which is listed for
  re-sign-off above.
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

## CPO third pass (2026-10-08, after merge of 425ea0fc1f)

The operator asked for the re-sign-off the plan's rule called for, after the merge. The CPO read the code before answering and approved
every user-visible item in "Post-review hardening", two of them conditionally (items 1 and 4b below), and recommended one product change.

| Item in "Post-review hardening" | Verdict |
|---|---|
| 1. D8 premise corrected (hosted autonomous default) | Approved on the conditions R1 and R2; the decision stands, the risk accepted was larger than the signed text said |
| 2. Longer README C1/C2 sentences | In spirit |
| 3. `cd` rule narrowed to force and delete pushes | In spirit; fewer false positives, matches D3 |
| 4a. Wrapper chdir, case folding, glob-only targets, bound blank runs, credential masking | In spirit |
| 4b. New ask classes (`unparsed-wrapper`, `wrapper-depth`, `bound`, `lexer-empty`) and size bounds | Approved on condition R3: commands outside D1 now interrupt, headless runs block, and the false-positive rate is unmeasured |
| 4c. Degraded scans ask on every force push | In spirit (D6 signed "force flag or +") |
| 5. Reason wording by cause; "do not rephrase" only on matched destructive commands | Approved; a deliberate, bounded relaxation of D4's universal "no rephrase" |
| 6. Quoted `hooks.json` registration | Approved |
| D7 prefilter boundary growth (T8) | In spirit; keep the prefilter |

**Hosted default (T12).** Keep-as-is was rejected: a hosted founder in autonomous mode can have a force-push over the default branch or
an infrastructure teardown approved without a prompt, the consent copy promises "backed up in git" and never names it, and that is a
single-user incident. Changing the `bash_autonomous` default was also rejected (autonomous-on is a deliberate activation, and the narrow
risk is fixable narrowly). The recommendation is that hosted autonomous mode asks for the D1 destroy families only.

**Required changes.**

- **R1 (P1, before any broadening of the hosted rollout):** the hosted ask path for default-branch force-push/delete and
  `terraform|tofu` destroy under `bash_autonomous`. Tracked as #9776 (the one follow-up the CPO did not accept as ADR-only).
- **R2 (small):** the autonomous disclosure copy (`autonomous-disclosure-banner.tsx`, counsel-reviewed text) names a default-branch
  force-push and infrastructure teardown as things Soleur may run without asking, until R1 ships. Needs CLO review; whether existing
  acknowledgements stay valid is a CLO question.
- **R3 (small):** measure the rate of the 4b ask classes outside D1 on real agent transcripts, per rule id, tune if it is more than rare,
  and record the number here. Not started; it needs transcripts.
- **R4 (small, done by this record):** two claims in the plan's Observability block outrun the shipped behaviour, and the plan's own
  addendum already says so. Stated here so the durable record carries it: (1) `alert_route: the person at the harness prompt (layer 7,
  in-session)` for a missing `jq` or `perl` is not guaranteed, because the notice is on stderr, which the person may never see; a hit
  asks, and a command the narrow raw scan misses runs without a prompt. (2) `cadence: ... after merge on main` for the slice-1 probe is
  not true: no workflow calls `scripts/verify-agent-security-slice1.sh`; only `scripts/test-all.sh` runs its suite
  (`scripts/verify-agent-security-slice1.test.sh`), so no scheduled post-merge probe runs. The probe has no scheduled caller; a caller
  is a follow-up, not a claim.

Process note from the CPO: a post-review change to a signed decision should reopen the sign-off by default, whether or not the round cap
is spent.

## Open follow-ups (recorded here; no tracking issue by operator decision, see C3)

Enabling the guard in hosted sessions (needs a measured hosted `ask` path; the narrower autonomous-mode ask for the D1 destroy families is #9776); Devin `exec` coverage and Devin `ask` measurement; a
per-rule allow for headless CI teardown; a settings-env tripwire; a session-start message stating full or degraded dependency
posture (the stderr notice for a missing `jq` or `perl` is likely invisible to the person); the D2 candidates (the SQL rule, a plain
`terraform apply`, secret writes, `kubectl delete`, `pulumi`/`terragrunt destroy`, `git push --mirror`, `find -delete`); a canonical
plugin-side lexer for the filing gate when it is next touched; and moving the `%FIND_ACT` and `$MAX_RECORDS` declarations above the
`BEGIN SHARED-LEXER` marker in `filing-shape.pl` so the lexer spans stop depending on two filing-only names (an incidental coupling
the parity test currently tolerates); and a README note, now added, that where `/dev/fd` or `/proc` is unavailable (a minimal sandbox without
`/proc`) the hook reads the lexer output through process substitution and so asks with the parse reason instead of denying (fail-safe,
but noisy for every lexed command).

Added by the 2026-10-07 post-review pass:

- A per-cron decision on the kill switch for the server-side agents (see Server-side scheduled agents).
- The unquoted `${CLAUDE_PLUGIN_ROOT}` command paths that remain in `hooks.json` (five of the ten command strings: a plugin root
  containing a space breaks each such hook). This hook's own entry is now quoted (Post-review hardening, "Registration").
- A hosted-visible statement of the gap (a hosted founder or agent cannot see the plugin README, so nothing in the hosted prompt says
  the guard is off).
- A heredoc, pipe or here-string fed to a shell is a plausible agent pattern left undecided (follow-up: treat the body as code when
  the command is a shell without `-c`).
- The record of an answered Yes/No prompt and the expanded view of a deny (unmeasured; the transcript claim is scoped to
  `hook_success` rows).
- Shard-manifest rows for the two heavy suites (without them the hash fallback can stack both on one CI leg).
- Deleting the prefilter (the simplicity review estimated about 2 ms of average saving against two defects; deferred because the
  prefilter is D7 and its deletion reopens the signed set).
- A real run of the SUITES under bash 3.2 (the hook header states what was run on 3.2.57: the hook over a 30-command corpus with
  decisions identical to bash 5.3; the clock-trip, partial-record, degraded-scan and output-fallback paths were not run there, and
  the suites ran under the host bash only).
- Case-folding of git and terraform SUBCOMMANDS (`git PUSH -f origin main`, `terraform DESTROY` get no decision): undecided, and
  whether the tools accept an upper-case subcommand is unverified.
- The `--` hops share the wrapper-depth counter, so nine `--` words ask even with no wrapper (once the command reaches the lexer
  path); the two counters could be separate.
- The wrapper option loops (`wrap_skip`) could be one table.
- Some bound checks (the read loop, the main loop, the record cap) are redundant with the rest: simplification candidates.
- The harness-of-harness tests (the meta-copy rows) overlap the vacuity-floor gate.
- `lexer-empty` adds little over `command-not-parsed` (a candidate to merge into it).
- The ADR ordinal collision (see the note below).

**Ordinal note (re-verified 2026-10-07 after `git fetch origin`).** This record keeps the number 274 and is NOT renumbered here.
`origin/main` already holds `ADR-277-add-a-cursor-cli-plugin-adapter.md` (and `ADR-275-founder-stated-acceptance-check-...`), so the
two files collide on the ordinal, and `scripts/check-adr-ordinals.sh` reds the merge ref until one is renumbered. Of the remote
refs (the `gh-readonly-queue` refs hold nothing above main's ADR-275), two other branches claim ADR-276 with different slugs
(`feat-one-shot-ci-hosted-runner-demand` and `feat-open-web-egress`), so that pair collides with each other and 276 is not free.
**The next free ordinal is 277** as of this fetch. It must be re-derived over `refs/remotes/origin/*` at ship time, because the
answer moves while branches land. `soleur:ship` renumbers by `git mv` of this file (the slug links in ADR-093, the plan and
`feat-agent-security-three-layers/spec.md` follow the file name) and by editing every `ADR-277` mention in the files that
`git grep -l 'ADR-277' HEAD -- . ':!*.likec4.json'` lists on this branch (counts rot, so none are recorded here): `.claude/hooks/README.md`,
`.claude/hooks/devin-dispositions.tsv`, `apps/web-platform/server/agent-env.ts`, `apps/web-platform/test/agent-env.test.ts`,
`apps/web-platform/test/plugin-pretooluse-hooks-web-parity.test.ts`,
`ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`, this ADR's heading, `diagrams/model.c4` and
`diagrams/views.c4` (only the plugin guard's lines), the W2 plan, `feat-agent-security-three-layers/phase-0-measurements.md` and
`spec.md`, this feature's `decision-challenges.md` and `tasks.md`, `plugins/soleur/README.md`, the hook header and
`destructive-command-guard-hook.test.sh`. `model.likec4.json` is regenerated with `plugins/soleur/scripts/render-c4-model.sh`, never edited by hand. Two traps: on
`origin/main` `model.c4` and `views.c4` cite ADR-277 for the Cursor element (the lines naming `cursorCli`), so a blanket replace
after merging main renumbers the wrong ADR's citations, and a search for `#274` also hits archived issue numbers, which are not ADR
citations.

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
