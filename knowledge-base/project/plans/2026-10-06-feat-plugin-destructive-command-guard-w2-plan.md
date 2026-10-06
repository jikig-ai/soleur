---
title: "feat: plugin destructive-command guard (agent security hardening W2)"
date: 2026-10-06
slug: plugin-destructive-command-guard-w2
branch: feat-one-shot-9601-w2-plugin-destructive-command-guard
issue: 9601
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plugin destructive-command guard (W2)

Ref #9601 (the epic stays open for W3). Draft PR #9653. Builds on `knowledge-base/project/plans/2026-10-06-feat-agent-security-hardening-slice-1-plan.md` (Phase 2 and Guard 2), `knowledge-base/project/specs/feat-agent-security-three-layers/{spec,tasks,phase-0-measurements}.md` and the brainstorm of the same date. W1 (ADR-272, the sandbox credential deny) is merged and live. This plan is W2 only.

## Enhancement Summary

**Deepened on:** 2026-10-06 (after a six-seat plan-review panel: DHH, Kieran, simplicity, architecture, spec-flow, CTO devex; and the `soleur:gdpr-gate` plan-time pass, no findings).
**Gates run:** User-Brand Impact (4.6), Observability (4.7; the probe `bash scripts/verify-agent-security-slice1.sh` exists on this tree and prints `slice1-security: ok` in 44 ms), PAT-shaped variables (4.8, no hits), Guard Contract (4.11, `lint-guard-contract.py` green, 2 guards), Scope Check (4.12, one unfenced section, all rows justified); 4.9 UI and 4.10 encryption posture do not apply (no UI surface, no store).

### Key improvements

1. The mechanism changed from "lift the plugin tokenizer / port the `guardrails.sh` segmenter" (both measured not to work) to a Perl lexer whose shared spans are byte-identical to the repo's filing lexer.
2. A deepen-pass read of `.claude/hooks/lib/filing-shape.pl` found that the lexer is NOT one contiguous region: filing logic is interleaved, the lexer rolls records back through `@RECORDS`, and `process_command` enforces a 32-record cap. Phase 2 now marks three spans per file, pushes argv records onto `@RECORDS`, and drops the cap (a script with more than 32 commands would otherwise have asked on every call).
3. The oracle can never run a destructive command (stub-only `PATH`, canary, literal expectations for absolute-path and `sudo` rows), and the mutation battery is cut to eight CI rows with the rest recorded once.
4. The hosted override is now pinned by a census over every PreToolUse hook in `hooks.json` plus a real-`buildAgentEnv` behavioural run, not a hand-keyed value assertion.
5. Phase 0 has a bounded CPO loop, a revision SHA and section hash for the sign-off, and a re-sign-off rule for any later change to D1-D9.

### New considerations discovered

- `.github/workflows/test-pretooluse-hooks.yml` loads the plugin headless via `claude-code-action`; its prompt removes a directory under the worktrees path recursively (a descendant of the working directory) and runs a plain `terraform apply -no-color` (not `-destroy`), and the guard matches neither, so inheriting the hook does not break it today. The repo-local `prod-write-defer-gate` already covers a plain `terraform apply` for repo sessions, which is part of why dropping it from spec FR2 costs this repo nothing.
- `scripts/guard-vacuity-floor.test.sh` lists `plugins/soleur/test/` in `COVERED_DIRS`; the new suites are mutation-tested by that gate and must be mutant-constructible, and no `PROMOTED_FILES` edit is needed.
- Devin envelopes carry no `.cwd` (ledger header, lines 35-36), which is one reason Devin `exec` coverage is a measured follow-up rather than part of W2.
- Hook `ask` is measured to hold under `bypassPermissions` (CC 2.1.287) and to block under `claude -p` (CC 2.1.142); the remaining matrix rows are Phase 0.2.
- Writing this plan tripped the repo's own `guardrails.sh` worktree-path guard on a command whose text merely quoted such a delete: a live instance of the quoted-text false-positive class the must-PASS rows pin.

## Overview

Ship one narrow PreToolUse hook in the customer-facing plugin (`plugins/soleur/hooks/`) that asks, or denies, before an agent runs an unambiguous infrastructure destroy, a rewrite or deletion of the default branch on a remote, or a recursive delete of `/` or the home directory. It protects people running the Soleur plugin on their own machine. Hosted founders are not covered by W2: the hook is disabled in hosted sessions by default and they rely on the sandbox and the review gate.

The slice-1 plan sketched W2 before anyone read the code it proposed to reuse. Reading it shows the two reuse claims do not hold (see Research Reconciliation), so this plan changes the mechanism and keeps the property. Because W2 carries a `single-user incident` threshold, **nothing is implemented until the product owner has signed off on the final decision set recorded below**. Phase 0 makes that the first task.

## Research Reconciliation — Spec vs. Codebase

| Spec / slice-1 plan claim | Reality (command or file) | Plan response |
|---|---|---|
| Phase 2.2: lift `tokenize()` from `operator-stage-approval.sh` to `hooks/lib/` and use it to evaluate each simple command of a list | `plugins/soleur/hooks/operator-stage-approval.sh` `tokenize()` returns 1 on `;`, `\|`, `<`, `>`, `(`, `)`, `$`, backtick, `\`, newline, glob characters, `~`, `#`, and on any `&&` except a standalone one. It parses ONE simple command and cannot segment a list. Nothing else depends on it | **Cut the lift.** Do not touch `operator-stage-approval.sh`. |
| Phase 2.2: port the `block-recursive-delete` proof from `guardrails.sh` "instead of writing a new one" | `.claude/hooks/guardrails.sh` (~lines 195-315) tokenizes with `mapfile -t … < <(… \| xargs -n1)` (bash 4) and resolves with `realpath -m` (GNU coreutils); chain operators survive as their own tokens only when space-separated, so `rm -rf ~;` yields the token `~;` | **Not portable and not a segmenter.** The proof's logic (target is `/`, `$HOME`, an ancestor of a protected root) is reused as a spec; the code is not. |
| Phase 2.0 hedge: "adopt the plugin tokenizer or port the segmenter" | `.claude/hooks/lib/filing-shape.pl` (820 lines, ADR-256) is a bounded Perl shell lexer. Measured on this tree (`perl .claude/hooks/lib/filing-shape.pl --trace`, ~12 ms): it splits `ls && terraform destroy`, unwraps `bash -c '…'`, keeps `terraform plan 2>&1 \| tee log` as two commands, reads `echo $(terraform plan; true)` as two substitution commands plus `echo`, treats `ls #x; terraform destroy` as `ls` plus a comment, strips `\rm` to `rm`, keeps a quoted `"terraform destroy"` as one argument, and continues past a heredoc body to the real command after it | **Decision D7:** vendor the lexer core into the plugin (the repo-local `.claude/hooks/lib/` never ships to customers), with a parity test against the original. |
| Phase 2.4: a missing `jq` exits 0 with a one-time notice, "the one deliberate narrowing of ADR-157" | ADR-165 §"`jq_missing` must not fail open UNCONDITIONALLY" measured exactly that: `rm -f /usr/bin/jq` is not matched by the guard, so the chain `rm -f /usr/bin/jq` then `rm -rf $HOME` ran clean. The accepted resolution scans the RAW document for the guard's own patterns when the parser is gone | **Cut the blanket fail-open.** Decision D6: missing `jq` or `perl` scans the raw envelope; a hit asks, a miss exits 0. |
| Phase 2.5: add the hook to `hook-input-classification-mutation.test.sh` and run `hook-input-contract.test.sh` | Both exercise `.claude/hooks/lib/hook-input.sh` and name no `plugins/soleur/hooks/` file (a grep for `plugins/soleur/hooks` in both finds nothing relevant). `.claude/hooks/lib/` is not shipped, so a plugin hook cannot source it | **Not applicable.** The plugin hook implements the ADR-156/157 envelope checks itself and carries its own sandboxed mutation battery. |
| Phase 2.5: `.claude/settings.json` and a `claude-settings` ledger row | The sibling is wired in `.claude/settings.json` (line ~213) and therefore has two ledger rows (`.claude/hooks/devin-dispositions.tsv` lines 57 and 116). `devin-matcher-parity.test.sh` requires one ledger row per registry registration (lines 143-151) | Decision D9: register ONLY in `plugins/soleur/hooks/hooks.json`, add ONE `soleur-plugin` row, and let the parity test decide whether a settings row is demanded. This repo's own sessions are covered by `guardrails.sh` for the recursive-delete deny set only (Phase 0.1e); a second registration would double-prompt every contributor. |
| Spec FR2: "rm -rf of ancestors, terraform destroy/apply, doppler secret writes, force-push to main" | The slice-1 plan narrowed this to a smaller set without recording the difference against FR2 | Decision D1 states the final set and what FR2 items are dropped and why; Phase 6 amends spec FR2 so the spec says what ships. |
| Slice-1 Phase 0.2: measure the `ask` matrix for `claude -p`, interactive, `bypassPermissions`, subagent and the hosted SDK | `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` already measured: `ask` blocks a Bash call under `claude -p` (CC 2.1.142); `ask` still prompts under `bypassPermissions` and against an allow rule, and the payload carries `permission_mode` (CC 2.1.287, ADR-264); decision precedence is deny > defer > ask > allow. Unmeasured: a subagent turn, the current CC version, the hosted SDK | Phase 0.2 re-probes only the unmeasured rows, with the scripted Anthropic stand-in (no credential, no paid turn). The hosted SDK row is dropped: the hook is disabled there (D8) and its enablement is a tracked follow-up. |
| Slice-1 plan: ADR "amendments only" for W2 | `ADR-273` is taken on `origin/main` (schema-constrained publication). W2 introduces decisions no existing ADR holds: the vendored lexer, the dependency-degrade posture, the decision set | New **ADR-274** (ordinal provisional; `soleur:ship` re-verifies it against fresh `origin/main`), plus amendment lines on ADR-093, ADR-157 and ADR-223. |
| Slice-1 plan: borrow `cc-safety-net`'s false-positive corpus | Not verified to be fetchable or licence-compatible from this environment; the repo's own test oracle needs rows derived from real shell behaviour anyway | Phase 1 synthesizes the corpus from the shell grammar; `cc-safety-net` is a reading reference only. |

## Research Insights

**Premise Validation (Phase 0.6).** Verified live: #9601, #9602, #9603, #9604, #9543, #9534, #9614 are OPEN; PR #9653 (this branch) and #9529 (open-web egress) are OPEN drafts; `origin/main` is at ed6083309f. W1 is merged and ADR-272 is on `main`. Cited files confirmed on this tree: `plugins/soleur/hooks/{hooks.json,browser-snapshot-credential-guard.sh,operator-stage-approval.sh}`, `plugins/soleur/hooks/lib/{hook-tool-kind.sh,log-rotation.sh}`, `.claude/hooks/{guardrails.sh,devin-dispositions.tsv,devin-matcher-parity.test.sh,hook-input-contract.test.sh,README.md}`, `.claude/hooks/lib/filing-shape.pl`, `scripts/guard-vacuity-floor.test.sh`, `apps/web-platform/server/agent-env.ts` (`AGENT_ENV_OVERRIDES`, lines 59-77), `apps/web-platform/test/server/agent-env-allowlist.test.ts`. ADR corpus grepped for the mechanism (destructive-command guard, hook tokenizer, ask/deny semantics): ADR-156, ADR-157, ADR-165, ADR-162, ADR-223, ADR-256, ADR-264 govern it; none rejects a narrow ask/deny guard. Two research subagents returned claims the tree contradicts (that `guardrails.sh` is bash-3.2 portable, that the sibling's suite does not exist, that a `.devin/config.json` registration is required); every fact in this plan was re-read from the file named.

**Property List (Phase 0.6b).**

- P1: A customer running the plugin gets a human confirmation (or a block) before their agent runs an unambiguous destructive command, in every spelling a shell reads as that command.
- P2: A legitimate command in the same family (`rm -rf node_modules`, `terraform plan`, `git push --force-with-lease origin feature`, quoted text containing a destructive string) is never interrupted.
- P3: The guard cannot be switched off silently: a missing or broken dependency, an unreadable envelope, or an unregistered hook is visible, never an implicit allow.
- P4: The hook never adds a hosted-session prompt or latency the platform did not choose.

**Cut List.**

- Lift `tokenize()` from `operator-stage-approval.sh` → buys P1, but cannot read a command list; the vendored lexer buys P1 alone.
- Port the `guardrails.sh` segmenter → buys P1, but needs bash 4 and GNU `realpath`; the lexer plus POSIX path resolution covers it.
- Blanket fail-open on missing `jq` → buys "never brick a session", which `ask` already buys without leaving a one-call disarm (ADR-165).
- A Soleur-side telemetry sink for guard decisions → would buy visibility, but layer 7 forbids routing a customer-machine run to Soleur infrastructure without consent.
- A local decision log with a rotation and a one-time-notice marker file (in the first draft) → cut at plan review (DHH, simplicity and devex seats agreed): it buys nothing P1-P4 names, writes into the customer's home directory, and records no command text so a false positive cannot be diagnosed from it. The harness transcript already holds every decision reason, and is the layer-7 durable artifact (see Observability).
- A bash-only quote-aware splitter instead of the Perl lexer (priced at plan review, rejected) → buys no new runtime dependency, but the grammar rows that decide P1 and P2 (a heredoc followed by a real command, `$(…;…)`, `bash -c`, a mid-word `#`) are exactly what `guardrails.sh`'s `xargs -n1` tokenization already gets wrong (`rm -rf ~;` yields the token `~;`), and ADR-256 records the same blindness for text-matching guards. The lexer is already measured to read every one of those rows correctly.
- Moving `filing-shape.pl` into the plugin and pointing `guardrails.sh` at it (one canonical lexer; DHH and devex seats recommended it) → would remove the copy, but ADR-256 binds the original to `cron-bash-allowlist-hook.mjs` through a shared corpus and the move edits the repo's filing gate and its suites inside a customer-hook PR. Replaced by a structural control: the shared lexer spans is delimited by BEGIN/END markers and a test requires the two copies' regions to be byte-identical. Recorded as a follow-up trigger (make the plugin copy canonical when the filing gate is next touched).
- `exec` (Devin) coverage with ask-as-deny (first draft D9) → cut at plan review: it ships a behaviour nobody measured and a dead-end for a legitimate `terraform destroy` where the person has no shell to set the kill switch. The matcher is `^Bash$`; Devin `ask` measurement and `exec` coverage are a tracked follow-up.
- `drop database` / `dropdb` rule (first draft) → cut at plan review: a fourth class neither FR2 nor the Overview names, with its own stubs, rows and raw-scan patterns. Follow-up candidate.
- Enabling the guard in hosted sessions → buys nothing P1 names (hosted Bash is sandboxed and gated by `permission-callback.ts`); needs a measured hosted `ask` path. Tracked follow-up.
- Doppler secret writes, a plain `terraform apply`, `kubectl delete`, `pulumi destroy`, `terragrunt destroy`, `git push --mirror`, `find -delete`, `dd`, `mkfs` → not unambiguous (routine, or a long tail); each widens the false-positive surface P2 protects. Follow-up candidates, not W2.
- A keyword-only or quote-normalized substring prefilter (first draft) → would buy latency but opens a gap for spellings it cannot see. Replaced by a gap-free zero-spawn prefilter (D7) that skips the lexer only when the raw envelope has none of the keywords AND none of the quoting/escaping/expansion characters, so it never skips what the lexer path would flag; every boundary character has a must-ASK row.
- Reading `permission_mode` to special-case `bypassPermissions` → buys nothing: measured `ask` holds under it (CC 2.1.287).

**Learning constraints carried in.** ADR-156: hook stdin is model-controlled, so the hook never evaluates it and checks `.tool_input.command` is a string. ADR-157/165: an unreadable envelope asks; `jq_missing` scans the raw document. ADR-256: grepping a quote-blanked copy cannot answer "what would bash execute", so lex. `2026-02-24-guardrails-grep-false-positive-worktree-text.md`: one anchored pattern per case, never independent greps ANDed. `2026-03-28-pretooluse-hook-guard-ordering-matters.md`: hook order in `hooks.json` is load-bearing. `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` and `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: independent oracle, and every decision path leaves a record. `hook-input-classification-mutation.test.sh` header: a mutation battery must mutate a COPY, never the live tree. ADR-264: decision precedence deny > defer > ask > allow, so another hook's allow cannot turn this hook's ask into a silent run.

**Functional overlap (Phase 1.5b).** No community artifact is adopted. `cc-safety-net` (MIT) is a general destructive-command guard whose design (no ask/deny split, no fail-to-ask) does not fit; it is a reading reference for false-positive classes only.

**Value measurement (Phase 0.6c).** The justification is a safety property, not a cost or performance saving; skipped. The one performance claim (added latency per Bash call) is measured in Phase 3.7 against a stated budget.

## User-Brand Impact

**If this lands broken, the user experiences:** their own legitimate `rm`, `git push` or infrastructure command interrupted or blocked by a false positive on every session; or a hook that errors and breaks every Bash call the agent makes; or no protection at all because a missing dependency silently switched the guard off.

**If this leaks, the user's data / money is exposed via:** an agent (prompt-injected or confused) running `terraform destroy` against their production, force-pushing over their default branch, or recursively deleting their home directory, with a guard that a one-line spelling change (`r""m -rf ~`, `bash -c`, a heredoc, a `jq`-less PATH) walked past. The hook itself exposes nothing: it reads the command string already in the transcript, writes no file and sends nothing.

- **Brand-survival threshold:** single-user incident

CPO sign-off on the **final decision set** is a hard precondition (Phase 0.3). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Final W2 Decision Set (the artifact the CPO signs off on)

Revision R4 (after plan review, the Phase 0.2 measurements and CPO round 1 required changes C1-C4). Phase 0.3 sends this section verbatim, with the Phase 0.2 measurements, to `soleur:product:cpo`. Any change to D1-D9 after sign-off, from any later phase, re-runs Phase 0.3.

- **D1 — What the guard decides.** Bash tool calls only. After lexing and unwrapping, for each simple command (a command inside `bash|sh|zsh|dash|ksh -c`, `eval`, `$(…)`, backticks and every list operator counts as its own simple command):
  - **deny** `rm` with a recursive flag (`-r`, `-R`, `-rf`, `-fr`, `--recursive`, any cluster or spelling, flags before or after the targets; `-f` not required) whose target is `/`, an ancestor of the home directory, the home directory itself (`~`, `$HOME`, `${HOME}`, `$PWD` when it is home, a literal or relative path resolving there), or the contents of those (`/*`, `~/*`, `$HOME/*`, and a bare `*` or `./*` when the working directory resolves to `/` or home). A trailing-slash or glob suffix follows a symlink; a bare symlink name does not (`rm -rf link` only unlinks it);
  - **ask** `rm` with a recursive flag whose target is the working directory or an ancestor of it (`..`, `../..`, an absolute path above it; `.` alone is not asked because `rm` refuses it);
  - **ask** `terraform|tofu destroy` and `terraform|tofu apply -destroy` (global options such as `-chdir=` before the subcommand are skipped);
  - **ask** `git push` whose refspec destination is, or whose current-branch default is, a default branch AND that force-pushes (`-f`, `--force`, `--force-with-lease[=…]`, `--force-if-includes`, a `+` refspec, in any short-flag cluster, or `--force` with `--all`/`--mirror`) or deletes it (`--delete`, `:ref`). Default branches = the union of `git symbolic-ref --short refs/remotes/<named remote>/HEAD` (local only), `main` and `master`; value-taking flags (`-o`, `--push-option`, `--repo`, `--receive-pack`) and `git -C <dir>` are parsed so positions and the repository path are right;
  - the `cd`/`pushd` effect: a literal `cd <dir>` earlier in the same list moves the simulated working directory for the later commands; an unresolvable `cd` (variable, `-`) followed by a recursive `rm` or a `git push` in the same list asks.
  - wrappers are unwrapped with a small option table: `sudo`, `doas`, `env`, `command` (not `command -v`), `nohup`, `time`, `timeout`, `nice`, `xargs` is NOT unwrapped; and the rule table is retried on the suffix after a `--`, which covers `doppler run --`, `aws-vault exec <profile> --`, `op run --`.
- **D2 — Deliberately not decided** (stated in the hook header and ADR-274): obfuscation (a variable-built command name, glob or brace expansion of a command name such as `r[m]` or `r{m,}`, `xargs rm`, `find -delete`, zsh-only expansions such as `=rm`), a script written then run, a piped SQL string, `drop database`/`dropdb`, MCP delete tools, any non-Bash tool (including Devin's `exec`), Doppler secret writes and deletes, a plain `terraform apply`, `kubectl delete`, `pulumi destroy`, `terragrunt destroy`, `git push --mirror` without `--force`, and an unresolvable `$VAR` target. The kill switch can also be set through a settings-level `env` block, which no Bash guard sees. Dropped from spec FR2: Doppler secret writes and a plain `terraform apply` (routine, ambiguous). The user-facing scope statement (the plugin README line and the hook header) says in one sentence that the guard does not cover a plain `terraform apply`, secret writes, SQL or non-Bash tools, and is not a substitute for scoped credentials (CPO round 1, C1).
- **D3 — Ask vs deny.** `deny` only where no legitimate use exists (delete of `/`, home or an ancestor). Everything else `ask`. Measured: `ask` holds under `bypassPermissions` and against an allow rule (CC 2.1.287); under `claude -p` it blocks the call with the reason shown (CC 2.1.142), so a headless run degrades to a block, never an allow. Measured on Claude Code 2.1.291 (Phase 0.2, `phase-0-measurements.md` §1.2): interactive `dontAsk` and `auto` still prompt the person, while headless `dontAsk` and `auto` block the call; `ask` is never an implicit allow in any measured mode.
- **D4 — What the person and the agent see.** The reason names the rule id, quotes the matched simple command (truncated at 200 characters) and says: stop and tell the person; if no person is available, end the task and report blocked, do not retry or rephrase; the person can run it in their own terminal outside the agent, or start the session with `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` in their own shell; and an issues URL for a false-positive report. A lexer failure uses a distinct reason ("could not parse this command; it was not recognised as destructive") so the person is never shown a matched command that does not exist. Measured (Phase 0.2, CC 2.1.291): on a `deny` the person sees only a collapsed "Ran 1 shell command" unless a top-level `systemMessage` is set, which then renders as `PreToolUse:Bash says: …`; so every `deny` also carries `systemMessage` with the same full reason, which includes the kill-switch escape hatch and the issues URL (CPO round 1, C4). `ask` does not need it (the prompt shows the full reason).
- **D5 — Kill switch.** `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` exits 0 with no output; any other value, including empty and `0`, leaves the guard on. It is the hook's first executable statement, before any dependency probe. It is read from the harness process environment, so it needs a session restart. This is a seatbelt, not a boundary: an agent can edit a settings file that sets it (D2), and the header and ADR-274 say so.
- **D6 — Failure posture (a stated narrowing of ADR-157's `.claude` row, with reasons).** An envelope `jq` rejects, or a non-string `.tool_input.command`, asks. A lexer exit 2 (unbalanced quote) or exit 3 (budget, depth, alarm, crash) asks, with the D4 parse reason. A missing or unusable `jq` does not ask on every call (that would make the plugin unusable without `jq`): the hook scans the RAW envelope for the guard's own narrow patterns (recursive `rm` with a `/`, `~` or `$HOME` target, `destroy`, `push` with a force flag or `+`), tolerating JSON-escaped whitespace, and asks on a hit and exits 0 on a miss; the reason names the missing tool and the output is built by hand with a fixed string because `jq` is unavailable. A missing `perl` with a working `jq` scans the `jq`-decoded command instead of the raw envelope. It never denies on a dependency failure (the repair is itself a Bash call). A miss on the raw scan is a stated, tested fail-open (ADR-165's own `.claude` accepted residual, narrower than its row).
- **D7 — Mechanism.** A Perl lexer, `plugins/soleur/hooks/lib/shell-argv.pl`, whose lexer spans (BEGIN/END-marked) are byte-identical to the same spans in `.claude/hooks/lib/filing-shape.pl` (a test enforces it), with `process_command`'s filing logic replaced by a per-simple-command argv record that carries each word's quoted (`q`) and expanded (`x`) flags so `'~'` is not read as home. It keeps the depth, 8x-input budget and 2 s alarm bounds and drops the 32-record cap. External binaries: `bash`, `jq`, `perl`, `git`, POSIX utilities. No bash-4 feature, no GNU-only flag. A zero-spawn prefilter skips the lexer when the raw envelope contains none of `rm`, `destroy`, `push`, `eval` and none of the characters `\`, `'`, `$`, a backtick; every skipped class has a must-ASK row pinning the boundary.
- **D8 — Hosted sessions.** `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` joins `AGENT_ENV_OVERRIDES` (hosted Bash is already sandboxed and gated by `permission-callback.ts`). The web-platform test derives every PreToolUse hook from `plugins/soleur/hooks/hooks.json` and fails on a hook that is not classified web-disabled or web-active, and runs the hook with the real `buildAgentEnv` output to prove it exits 0 silently. W2 protects customer-machine users, not hosted founders; enabling it hosted is a tracked follow-up that needs a measured hosted `ask` path. The plugin README states it in one line, not only the hook header and ADR-274: "Not active in Soleur-hosted sessions; hosted sessions rely on the sandbox and review gate." (CPO round 1, C2). The follow-up issue (hosted enablement, Devin `exec`, a per-rule allow for headless CI, a settings-env tripwire, a session-start posture message, the D2 candidates) is filed BEFORE merge and linked from the PR body, never left as prose (C3).
- **D9 — Harness scope.** Registered in `plugins/soleur/hooks/hooks.json` with matcher `^Bash$` and an explicit `timeout`, as the sibling does. Devin's `exec` is out of scope; the ledger row records `skip` with the reason (Devin's `ask` is unmeasured, and Devin envelopes carry no `.cwd`), and measuring it is a tracked follow-up. The headless GitHub workflow that loads the plugin (`test-pretooluse-hooks.yml`) inherits the hook; Phase 0.1 records whether its jobs can issue a destructive command.
- **D10 — No new processing, no log.** Soleur receives nothing from this hook and the hook writes nothing outside the harness: the decision reason in the harness transcript on the customer's own machine is the record. No public security claim is made. `soleur:gdpr-gate` ran at plan time with no findings.

## Implementation Phases

### Phase 0 — Product gate and measurements (BEFORE any implementation task)

No product code, hook, lexer, test suite, registry row or ADR is written until 0.4 is recorded. Everything in 0.1-0.3 is read-only or a throwaway probe.

- 0.1 **Read-only checks that can still change the decision set** (any change re-opens the Decision Set):
  - the ADR ordinal: `git ls-tree -r origin/main --name-only | grep decisions/ADR-27` still ends at ADR-273;
  - registry parity: run `bash .claude/hooks/devin-matcher-parity.test.sh` against a scratch copy of the tree with a hypothetical `^Bash$` hook row to learn whether a `claude-settings` row is demanded (a second registration would double-prompt contributors), and read `scripts/guard-vacuity-floor.test.sh` lines 195-225 (the suite lands in `COVERED_DIRS`, so the gate mutation-tests it and it must be mutant-constructible: a literal floor adjacent to its check, reported by `printf` + `exit 1`);
  - headless and cron surfaces that load the plugin: `grep -l "soleur@soleur-marketplace" .github/workflows/*.yml` (today `test-pretooluse-hooks.yml`) and every `plugins:` spawn under `apps/web-platform/server` (today the single `agent-runner-query-options.ts` binding); record, per surface, whether it can issue a destructive command and whether it needs the disable env (deepen-pass result for `test-pretooluse-hooks.yml`: its prompt issues a recursive delete under the worktrees path and `terraform apply -no-color`, which the guard does not match, so no disable env is needed today);
  - whether this repo's own sessions load the plugin hooks (decides the contributor double-prompt note).
- 0.2 **Re-probe only the unmeasured rows** with a throwaway stub hook and the scripted Anthropic stand-in used for W1 (`apps/web-platform/test/helpers/anthropic-stub.ts`; no credential, no paid turn, no network): on the current Claude Code version, a subagent turn (does the hook fire, does `ask` reach the person or auto-deny; the envelope carries `agent_id`), `dontAsk` and `auto` permission modes, a re-confirm of `claude -p` and `bypassPermissions`, and whether a top-level `systemMessage` on a `deny` renders to the person. Append the results and the exact commands to `knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md` under `## 1.2 — customer hook-decision matrix for W2`. If a row contradicts D3, D4, D6 or D9, edit the Decision Set first.
- 0.3 **CPO sign-off (hard gate).**
  1. Commit and push the Decision Set section so the revision has a SHA; compute the section's `sha256sum`.
  2. Spawn `soleur:product:cpo` with the "Final W2 Decision Set" section verbatim plus the 0.1 and 0.2 results, asking for an explicit sign-off or the change they require. The prompt asks specifically about false-positive tolerance (the ask set), the deny-versus-ask line (D3), what was dropped from spec FR2 (D2), the hosted posture and the headless-workflow inheritance (D8, D9), and the Devin and SQL cuts. Structured advisory only, no `AskUserQuestion`.
  3. At most two rounds. A revision that needs a third is a stop: report blocked with the open question, do not proceed.
  4. Record the verdict verbatim, the date, the revision SHA and the section hash under a `## CPO sign-off` heading in **PR #9653's body** (edit with `gh pr edit 9653 --body-file`; read the current body first and append, never overwrite). The body must also: state on its first line whether merging alone mutates production (it ships a hook to every plugin user on the next plugin release and changes one hosted env override); carry the PR title `feat(plugin): destructive-command guard (W2)` instead of `WIP:`; and use `Ref #9601`, never `Closes`, `Fixes` or `Resolves` (the epic spans W2 and W3).
- 0.4 **Gate check (the line implementation may not cross).** `gh pr view 9653 --json body --jq .body` contains `CPO sign-off`, a 40-hex revision SHA and `Ref #9601`, and contains none of `Closes #`, `Fixes #`, `Resolves #`. Re-run this exact check before the PR is marked ready and after any later `gh pr edit`; any later edit to D1-D9 sends the work back to 0.3.

### Phase 1 — Tests first (RED), per `cq-write-failing-tests-before`

- 1.1 Create `plugins/soleur/test/destructive-command-guard-hook.test.sh`. Floor-bearing and mutant-constructible for the vacuity-floor gate: a per-row `checked` counter incremented at the call site, `pass + fail == checked` conservation, an instrument self-test that drives both helpers once, and a literal floor reported by `printf` + `exit 1`, never through the helpers it backstops.
- 1.2 **Oracle = a real shell run against recording stubs, never the hook's output, and it can never run a destructive command.**
  - The suite builds a `PATH` made of stub directories only (`rm`, `terraform`, `tofu`, `git`, `sudo`, `doas`, `env`, `timeout`, `nice`, `nohup`, `doppler`, `aws-vault`, `op` all record argv and exit 0), a temp `HOME`, a temp working tree, and `set -f` is NOT set so the oracle shell expands globs inside the temp tree only.
  - A canary runs first: `command -v rm`, `command -v terraform` and `command -v git` must resolve inside the stub directory, else the suite aborts before any row.
  - Only rows whose command words are bare names execute. Rows with an absolute binary path (`/bin/rm`), a `sudo` that would reset `PATH`, NUL bytes, oversized input, garbage stdin or a non-string `command` carry a literal expected value and are never executed.
  - The expected decision is derived from the recorded argv by a small rule table inside the test. Stated honestly: the shell supplies lexing and expansion; the rule table is a second implementation by the same author, so the mutation rows below are what check it.
  - Rows whose dead code a conservative static hook cannot see (`false && terraform destroy`) are labelled as expected-ask and excluded from the "executed stub fired" comparison.
  - A jq-less or perl-less `PATH` uses a symlink farm that links every `/usr/bin` utility except the removed one.
  - zsh-only expansions are listed in D2 and not tested.
- 1.3 Grammar fixture, built from the shell grammar rather than the decision set (every blank class, quoting context, option cluster, wrapper, nesting and `cd` construct). Beyond the Guard 1 matrix rows: `$'…'` decoding, `${…}` with a command substitution inside, `eval "…"`, every wrapper in D1 with its option form (`sudo -u x`, `env -i`, `timeout 5`, `nice -n 5`, `command -v rm` which must NOT ask), the `--` suffix wrappers, `-chdir=` before `destroy`, `git -C dir push`, `git push -o x origin main`, `feature:main`, `HEAD:main`, `refs/heads/main`, `+HEAD`, `--force --all`, `+main`, `:main`, `--delete main`, a push to a second remote, a substitution the lexer lexes twice (`echo $(terraform plan; true)`) and a `((` it re-reads as two subshells (each simple command must appear exactly once in the record stream), a relative target resolving to `$HOME`, `rm ~ -rf` (flags after the target), `rm -rf '~'` and `rm -rf "$HOME"` (quoted-tilde is a literal directory, quoted `$HOME` is home), `rm -rf link` where `link` points at `$HOME` (no decision) versus `rm -rf link/` (deny), a nonexistent target under `$HOME`, `HOME` that is itself a symlink, `/home` and `/home/*`, `cd ~ && rm -rf ./*`, `cd /tmp && rm -rf ./*` (no decision), a 100 KB heredoc that lexes within the bounds (no decision), a command that trips a bound (asks with the D4 parse reason), more than 32 simple commands (no cap), a NUL byte, a non-string `command`, garbage stdin, `SOLEUR_DISABLE_DESTRUCTIVE_GUARD` set to `1` (off), `0` and empty (on), and each prefilter-boundary character (`\`, `'`, `$`, a backtick) in an otherwise benign command (the guard must still reach the lexer).
- 1.4 Must-PASS rows (differ from the canonical in a way the contract permits): `rm -rf node_modules`, `rm -rf ./build`, `terraform plan`, `terraform plan -destroy`, `git push origin feature-branch`, `git push --force-with-lease origin feature-branch`, `git push --force` while the current branch is not a default branch, `echo "terraform destroy"`, `git commit -m "rm -rf /"`, `grep -r destroy .`, a heredoc body containing `terraform destroy`, plus a synthesized corpus of about 40 ordinary agent commands (`case`, `[[ ]]`, here-strings, `for` loops, pipelines, `find … -exec`, `docker`, `npm`) that must produce no decision; the ask rate on that corpus is reported in the PR body.
- 1.5 `plugins/soleur/test/shell-argv-parity.test.sh`: extracts the BEGIN/END-marked lexer spans from `plugins/soleur/hooks/lib/shell-argv.pl` and `.claude/hooks/lib/filing-shape.pl` and requires byte identity; it also runs a small grammar corpus through both lexers' `--trace` output and compares the argv lines. Row-count floor.
- 1.6 `plugins/soleur/test/destructive-command-guard-mutation.test.sh` (named into the `plugins/soleur/test/*.test.sh` glob so it runs, not `*.mutation.sh`): mutates a COPY of the plugin tree in a temp dir, never the working tree. It executes only the chokepoint rows M1-M8 of the Guard 1 matrix in CI; the remaining design-derived rows are run once at work time and their results recorded in `phase-0-measurements.md`. Wall-time budget 60 s, stated at the top of the file.

### Phase 2 — Lexer

- 2.1 In `.claude/hooks/lib/filing-shape.pl` add `# BEGIN SHARED-LEXER` / `# END SHARED-LEXER` marker pairs around EACH lexer-owned span. Read on this tree, the spans are not contiguous because the filing logic is interleaved: (a) the data and state the lexer reads (`%RUNNER`, `%RESERVED`, `$MAX_DEPTH`, `$ALARM_S`, the state `my` lines `$BUDGET $USED $DEPTH $INVIS $RELEX`, `@HD_LOG @PATH %SEEN_SUBST %SEEN_STR`, and `$TRACE`), (b) the helper subs from `fail2` through `new_word`, (c) `lex_string` through `runner_script` (lines ~326-727). The filing-only spans (`$GH_VERSION`, the `*_VAL` tables, `filing_shape`, `api_endpoint_arg`, `parse_opts`, `value_corpus`, `fields_of`, the `gh` loop inside `process_command`) stay outside every pair. Comments only, no behaviour change; `.claude/hooks/lib/filing-shape.test.sh` and the corpus-parity suite stay green.
- 2.2 Create `plugins/soleur/hooks/lib/shell-argv.pl`: the identical marked spans plus a new `process_command` that pushes one argv record per simple command onto `@RECORDS` (the lexer's rollback `splice @RECORDS, $n0` on a re-lexed substitution and on a `((` re-read as two subshells depends on records living there, so emitting straight to stdout would keep or duplicate records the original drops). Output is NUL-framed `C\0<ctx>\0<argc>\0(<flags>\0<arg>\0)…` with `q`/`x` flags per word, terminated by `OK\0`; `E\0<cause>\0` with exit 2 and 3 as in the original. The 32-record cap lives in `process_command`, outside the shared spans, and is dropped. Header states provenance and the parity test.
- 2.3 The hook's rule table, not the lexer, unwraps the D1 wrappers.
- 2.4 Lexer rows of the Phase 1 suites go green.

### Phase 3 — The hook

- 3.1 Create `plugins/soleur/hooks/destructive-command-guard.sh` (executable; `set -uo pipefail`, `export LC_ALL=C`; no `eval`, ever, ADR-156). Order: the D5 kill switch as the first executable statement; read stdin; the D7 zero-spawn prefilter; capture the raw `tool_name` BEFORE `hook_tool_kind` normalizes it (via `lib/hook-tool-kind.sh` with the sibling's degrade-on-missing-lib shim); dependency probes by RESULT (not `command -v`, as the sibling's header explains); `jq` extraction (the command through `jq -j` straight into the lexer so NULs and newlines survive, the small fields in a separate call); lexer; rule table; decision.
- 3.2 Bash 3.2 plumbing, written down because each is a real trap: `$(…)` strips NULs so frames are read with `read -d ''`; decide from the `OK\0` terminator, never from an exit status lost across process substitution; guard every empty-array expansion for `set -u`; no `mapfile`, `declare -A`, `${x,,}`, `readlink -f`, `realpath`, `sed -i`, `date -d`, `stat -c`.
- 3.3 Rule table per D1. Working directory = envelope `.cwd`, falling back to `CLAUDE_PROJECT_DIR` then `PWD` as `operator-stage-approval.sh` does. Path resolution without `realpath`: resolve the physical parent with `cd … && pwd -P` plus the literal basename; for a nonexistent target resolve the longest existing prefix and normalize the rest lexically; compare `HOME` in both its literal and physical forms; a trailing `/` or glob suffix follows a symlink. Default branches via `git -C <dir> symbolic-ref --short refs/remotes/<remote>/HEAD`, local only (no network call, so a hook cannot hang on one), unioned with `main`/`master`.
- 3.4 Emit the full envelope `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":…,"permissionDecisionReason":…}}` built with `jq -nc --arg` (a bare decision without `hookEventName` is silently ignored, measured in `DEFER-DECISION-PAYLOAD-SHAPE.md`); on the no-`jq` path, a hand-built string with a fixed reason. Every `deny` also carries a top-level `systemMessage` with the same reason (measured in 0.2 to render to the person); `ask` does not.
- 3.5 Degraded paths per D6.
- 3.6 Header documents: the property, the D2 non-coverage list, the dependency list, the portability rules, the kill switch (needs a restart; settable through a settings `env` block), and that the guard sees the original command, not another hook's `updatedInput`.
- 3.7 Latency measured once and reported: 200 calls with a prefilter-skipped command, a lexed benign command and a destructive command; record the three medians in the PR body. Budget: median added latency at most 60 ms on a lexed command on Linux. Over budget is a finding to fix, not a branch to add.
- 3.8 Register in `plugins/soleur/hooks/hooks.json` as a PreToolUse entry with matcher `^Bash$` and an explicit `timeout`, after the snapshot guard's entry. Order does not change outcomes: all hooks of one event run independently and decision precedence is deny > defer > ask > allow (ADR-264); the 2026-03-28 ordering learning concerns hooks that rewrite input and this hook never does.
- 3.9 Phase 1 suites go green.

### Phase 4 — Registries and parity (ADR-223)

- 4.1 `.claude/hooks/devin-dispositions.tsv`: one `soleur-plugin` row for the new path, event `PreToolUse`, matcher `^Bash$`, disposition `skip`, reason "Devin ask unmeasured and Devin envelopes carry no cwd; follow-up", evidence naming the suite. Run `bash .claude/hooks/devin-matcher-parity.test.sh`; add a `claude-settings` row and a `.claude/settings.json` entry only if the 0.1 dry run showed the parity test demands it, and state the double-prompt consequence if so.
- 4.2 `.claude/hooks/README.md`: a hook-table row beside the sibling's and a kill-switch row (needs a session restart).
- 4.3 `scripts/guard-vacuity-floor.test.sh`: run it. The new suites sit in `COVERED_DIRS`, so no `PROMOTED_FILES` edit is made (that list holds only suites from the deferred directories); the gate mutation-tests the suite and the suite must score FIRES. Never raise `MAX_DEFERRED`.
- 4.4 `plugins/soleur/test/devin-plugin.test.ts`: a parallel assertion where line ~107 hard-codes the sibling's name.
- 4.5 `scripts/suite-shard-legs.tsv` and the shard-totality tests (`plugins/soleur/test/scripts-shard-totality*.sh`): add the new suites if the census demands it. Run `bash scripts/lint-orphan-test-suites.sh`.
- 4.6 Run `plugins/soleur/test/components.test.ts` and `bun test plugins/soleur/test/devin-*.test.ts` to catch a hook-count or registry assertion.

### Phase 5 — Hosted posture

- 5.1 `apps/web-platform/server/agent-env.ts`: add `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` to `AGENT_ENV_OVERRIDES` next to the two sibling `SOLEUR_DISABLE_*` entries.
- 5.2 `apps/web-platform/test/server/agent-env-allowlist.test.ts` (or a sibling census beside `plugin-stop-hooks-web-parity.test.ts`): derive every PreToolUse hook from `plugins/soleur/hooks/hooks.json`; each must be listed `web-disabled` (this hook and `operator-stage-approval.sh`) or `web-active` with a reason (`browser-snapshot-credential-guard.sh`), and an unlisted hook fails; for each `web-disabled` hook, spawn it with the real `buildAgentEnv` output and a destructive envelope and assert exit 0 with empty output on every auth scheme. Mutation: moving the kill-switch read below the `jq` probe must go red.
- 5.3 State plainly in the ADR-093 amendment and in a comment on #9601 that W2 protects customer-machine plugin users, not hosted founders.

### Phase 6 — Architecture, docs, close-out

- 6.1 ADR-274 and one ADR-093 amendment line (see Architecture Decision); C4 per below.
- 6.2 Amend `knowledge-base/project/specs/feat-agent-security-three-layers/spec.md` FR2 to the shipped decision set; add one line to the PR 2 heading of `knowledge-base/project/specs/feat-agent-security-three-layers/tasks.md` pointing at this plan (the plan is the source of truth; the branch's own `tasks.md` carries the W2 task list).
- 6.3 Extend `scripts/verify-agent-security-slice1.sh` (created in PR 1) with the guard check, kept small because the observability gate runs it under a 15 s cap: the hook is registered in `hooks.json` with a Bash-matching matcher, and a functional probe feeds three canned envelopes (`terraform destroy`, `rm -rf ~`, `ls`) to the hook and checks `ask`, `deny` and empty. It keeps printing `slice1-security: ok`, compares with `grep -c`, never a negated grep, and has no shell-active character in the command line the gate sees.
- 6.4 Deferral tracking (filed before merge, linked from the PR body; also comment on #9603 and tell the CMO and CLO domain notes that W2 must not be cited as coverage of "destructive commands" in general, CPO round 1): one GitHub issue, milestone from `knowledge-base/product/roadmap.md`, covering (a) enabling the guard in hosted sessions (needs the hosted `ask` measurement), (b) Devin `exec` coverage and `ask` measurement, (c) the D2 candidates incl. the SQL rule and a settings-env tripwire, (d) making the plugin lexer canonical for the filing gate, (e) a posture message at session start (full vs degraded dependency state), (f) a per-rule allow for headless CI teardown; run `gh issue edit <N> --add-blocked-by` where a blocker is known. Comment the hosted-enablement pointer on #9601.
- 6.5 Run `markdownlint`, the plan's own lints (`scripts/lint-guard-contract.py`, `scripts/lint-infra-no-human-steps.py`) and `bun test` for the touched web-platform files.

## Files to Edit

- `plugins/soleur/hooks/hooks.json` — new PreToolUse entry (ask 1).
- `.claude/hooks/lib/filing-shape.pl` — BEGIN/END marker comments around the shared lexer spans only (inferred: the structural parity control for the vendored copy).
- `.claude/hooks/devin-dispositions.tsv` — one `soleur-plugin` row (inferred: ADR-223 parity fails on an unregistered hook).
- `.claude/hooks/README.md` — hook-table and kill-switch rows (inferred: the README documents every hook and kill switch).
- `plugins/soleur/README.md` — a short destructive-command-guard section: what it does, the one-sentence non-coverage statement (C1), the hosted-gap line (C2), the kill switch (CPO round 1, C1/C2).
- `plugins/soleur/test/devin-plugin.test.ts` — parallel assertion (inferred).
- `scripts/suite-shard-legs.tsv` — new suite rows if the shard census requires them (inferred).
- `apps/web-platform/server/agent-env.ts`, `apps/web-platform/test/server/agent-env-allowlist.test.ts` — hosted override and the PreToolUse-hook classification census (inferred: plugin hooks load into hosted sessions, ADR-093).
- `scripts/verify-agent-security-slice1.sh` — guard check (inferred: the observability gate needs a local discoverability probe; kept small, the simplicity seat's cut was not taken because the gate requires a command that exists in this PR's tree).
- `knowledge-base/engineering/architecture/decisions/ADR-093-*.md` — one amendment line (inferred).
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4` — `destructiveGuard` component and one edge (inferred).
- `knowledge-base/project/specs/feat-agent-security-three-layers/{spec.md,tasks.md,phase-0-measurements.md}` — FR2 amendment, a pointer line, the W2 matrix (inferred).
- `.claude/settings.json` — only if `devin-matcher-parity.test.sh` demands it (inferred; default is no change).
- `scripts/guard-vacuity-floor.test.sh` is NOT edited: the new suites sit in `COVERED_DIRS` and the gate mutation-tests them.

## Files to Create

- `plugins/soleur/hooks/destructive-command-guard.sh` (ask 1).
- `plugins/soleur/hooks/lib/shell-argv.pl` (ask 1; replaces the slice-1 plan's lifted `lib/tokenize.sh`, which cannot read a list).
- `plugins/soleur/test/destructive-command-guard-hook.test.sh`, `plugins/soleur/test/destructive-command-guard-mutation.test.sh`, `plugins/soleur/test/shell-argv-parity.test.sh` (ask 1: the guard's tests).
- `knowledge-base/engineering/architecture/decisions/ADR-274-plugin-destructive-command-guard.md` — ordinal provisional (inferred: the plan skill makes the ADR a deliverable).
- `knowledge-base/project/specs/feat-one-shot-9601-w2-plugin-destructive-command-guard/tasks.md` — this branch's task list (the plan skill's output).

## Open Code-Review Overlap

None. Checked the 87 open `code-review` issues against `plugins/soleur/hooks/hooks.json`, `operator-stage-approval.sh`, `browser-snapshot-credential-guard.sh`, `.claude/hooks/devin-dispositions.tsv`, `.claude/hooks/README.md`, `.claude/hooks/guardrails.sh`, `apps/web-platform/server/agent-env.ts`, `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/devin-plugin.test.ts`, the two `.c4` files, ADR-093, ADR-157, ADR-223 and `.claude/settings.json`: zero matches.

## Guard Contract

### Guard 1 — destructive-command hook decision

**Property.** A Bash tool call whose command, after lexing and wrapper unwrapping, runs a command in the D1 set receives `ask` or `deny`, never an implicit allow, in every spelling bash reads as that command (within the D2 scope); a command in the same family outside D1 receives no decision; an envelope the hook cannot read receives `ask`.

**Assembly.** Every route by which a command string reaches execution inside one Bash call, within the D2 scope: a simple command; `&&`, `||`, `;`, `&`, `|`, `|&`, newline lists; subshells and brace groups; `$(…)`, backticks, `<(…)`; `bash|sh|zsh|dash|ksh -c` and `eval` strings; the D1 wrappers and the `--` suffix forms; a `cd`/`pushd` earlier in the list. There are exactly three code paths from envelope to decision, and each has its own rows: the lexer path (the chokepoint, one lexer invocation), the zero-spawn prefilter skip (which may only skip what the lexer path would also have allowed), and the degraded raw-scan path (`jq` or `perl` missing). Registration side: `hooks.json` references the hook with a Bash-matching matcher, the ledger row exists, and the hosted override is in `AGENT_ENV_OVERRIDES`.

**Mutation matrix.** M1-M8 are executed in CI by `destructive-command-guard-mutation.test.sh` against a COPY of the plugin tree; the other rows are derived from the design and run once at work time with the results recorded in `phase-0-measurements.md`.

| # | Edit that MUST turn the guard RED | Detected by |
|---|---|---|
| M1 | Stop scanning the second command of a list: scan only the first record of the lexer's output (a second member after a compliant first) | `terraform plan; terraform destroy` asks; `terraform plan; rm -rf ~` denies |
| M2 | Guard's own dispatch: garbled, empty or truncated stdin, or a non-string `command`, exits 0 silently | garbage stdin and `{"tool_input":` ask (ADR-157) |
| M3 | Guard's own dispatch: the lexer returns zero records and the hook reports "nothing to check" as allow | an unbalanced quote asks; an assertion that a known command yields at least one record |
| M4 | The prefilter skips a command the lexer would have flagged | a benign-looking command carrying each boundary character (`\`, `'`, `$`, backtick) plus a destructive word still asks |
| M5 | A missing `jq` or `perl` exits 0 unconditionally (the ADR-165 defect) | jq-less `PATH`: `rm -f jq; rm -rf ~` and `terraform destroy` ask, `ls` exits 0; perl-less `PATH` likewise via the decoded command |
| M6 | Move the kill-switch read below the dependency probes, or honour a value other than `1` | `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` exits 0 silently with no `jq` and no `perl` on `PATH`; `=0` and empty keep the guard on |
| M7 | Remove the `hooks.json` registration or change its matcher so it no longer matches `Bash` | registration assertion in the hook suite |
| M8 | The decision envelope loses `hookEventName` | output-shape assertion |
| 9 | Stop unwrapping `bash -c` / `eval` | `bash -c 'terraform destroy'`, `eval "rm -rf ~"` |
| 10 | Match inside quoted text or a heredoc body | must-PASS `echo "terraform destroy"`, `git commit -m "rm -rf /"`, a heredoc body, then a real command after the terminator |
| 11 | Treat a mid-word `#` as a comment | `echo a#b; terraform destroy` asks; `ls #x; terraform destroy` no decision |
| 12 | Segment on a character the shell reads as part of one command | `terraform plan 2>&1 \| tee log`, `ls &> out; terraform destroy`, `echo $(terraform plan; true)`, `cmd >\| f` |
| 13 | An `rm` option spelling or position escapes the match | `rm -rf ~`, `-fr`, `-r -f`, `--recursive --force`, `-Rf $HOME`, `-rf -- ~`, `\rm -rf ~`, `"rm" -rf ~`, `rm -r ~`, `rm ~ -rf` |
| 14 | A target spelling escapes the resolver, or the resolver follows a bare symlink | `~/`, `$HOME/`, `${HOME}`, `"$HOME"`, `/`, `//`, `/*`, `~/*`, `/home`, a relative path resolving to `$HOME`, `link/` denies while `rm -rf link` does not, `'~'` does not |
| 15 | `cd` is not modelled | `cd ~ && rm -rf ./*` denies, `cd /tmp/x && rm -rf ./*` does not, an unresolvable `cd` followed by a recursive `rm` asks |
| 16 | Default-branch resolution hard-codes `main` or only `origin` | a repo whose `origin/HEAD` is `trunk`: `git push --force origin trunk` asks; a second remote with its own HEAD; `git -C dir push -f` |
| 17 | A push spelling escapes the match | `-f`, `-fu`, `--force`, `--force-with-lease=main:abc`, `--force-if-includes`, `+main`, `HEAD:+main`, `feature:main`, `refs/heads/main`, `--delete main`, `:main`, `--force --all`, `-o x` before the remote |
| 18 | A wrapper hides the command | `sudo -u x terraform destroy`, `env -i terraform destroy`, `timeout 5 terraform destroy`, `doppler run -- terraform destroy`, `aws-vault exec p -- terraform destroy`; and `command -v rm` does NOT ask |
| 19 | The record cap or a lexer bound turns benign input into an ask | more than 32 simple commands and a 100 KB heredoc that lexes within bounds give no decision; a bound trip asks with the D4 parse reason |
| 20 | The kill switch is read from a file or a value instead of the harness environment | covered by M6 plus a header assertion that the settings-env route is documented |

**Grammar fixture and oracle.** The expected value of every executable row comes from running the command with `bash -c` against recording stubs (Phase 1.2), never from what the hook returned, and the oracle never runs a destructive command (stub-only `PATH`, a canary that proves it, literal expectations for absolute-path and `sudo` rows). The rule table in the test is a second implementation by the same author; the mutation rows are the check on it. The suite carries a count floor on rows executed.

**Harness rows.** (a) Mutate the SUITE: delete one expected-ask row; the case-count floor fails. (b) Mutate the SUITE: make the `terraform` stub record nothing; the oracle-derived expectation changes and the suite goes red. (c) Must-PASS inputs that are not the canonical: the Phase 1.4 list and corpus.

**Anchor.** The decision set is code in the same diff as the suite, so a weakening that edits both passes the suite. The independent anchors are (i) the oracle, which executes real bash, (ii) the registry parity tests and the vacuity-floor gate that read committed state, (iii) the CPO sign-off recorded in PR #9653 against a named revision SHA and section hash, which a reviewer diffs against the shipped rules, and (iv) the `scripts/verify-agent-security-slice1.sh` functional probe that runs on `main` after merge.

### Guard 2 — shared lexer spans parity

**Property.** The plugin's lexer and the repo's `filing-shape.pl` share their lexer spans, so a lexing fix in one cannot silently leave the other behind.

**Assembly.** The two files' BEGIN/END-marked spans, and the marker pairs themselves (there are three spans per file). The test extracts every span from both files, so a removed or moved marker is part of the surface.

**Mutation matrix.**

| # | Edit that MUST turn the guard RED | Detected by |
|---|---|---|
| 1 | Change one character inside a span in the plugin copy only | byte-identity comparison |
| 2 | Change one character inside a span in the original only | byte-identity comparison |
| 3 | Guard's own dispatch: remove the markers from one file so the extracted spans are empty on both sides and compare equal | the test asserts the span count is exactly three and each span is at least a stated minimum size and exits 1 otherwise |
| 4 | Add a second divergence after a matching first (a second span, or a changed line below the first) | the test compares every span, not only the first |

**Harness rows.** (a) Mutate the SUITE: lower the minimum-size floor to zero; the self-test must catch it. (b) A must-PASS pair that differs from the canonical in a way the contract permits: a change outside the markers (`process_command`) compares equal.

**Anchor.** The markers are committed in the original, so a weakening that edits a lexer and the markers together is visible in one diff; `shell-argv-parity` runs in CI on every change under either lexer path (the orphan-suite census and the shard census confirm it runs).

## Observability

Layer 7 (`cli-stdout-artifact`), because the hook executes on a customer's own machine. The same file also loads inside hosted sessions in principle; it is disabled there by `AGENT_ENV_OVERRIDES` (D8), so the hosted path emits nothing by design and the hosted regression surface is the web-platform census and behavioural test (Phase 5.2), which fails CI if the override is removed or the hook ever answers on a hosted environment. No Soleur-side sink exists or is added (the layer-7 rule forbids one without consent).

The layer-7 durable artifact is the harness transcript on the customer's machine, which records every hook decision and its reason; a separate decision log was cut at plan review (see Cut List) and the observability reviewer may re-open that choice at review time, in which case the minimal fallback is a single append-only line per decision with no command text.

```yaml
liveness_signal:
  what: the hook's decision JSON (ask or deny with the rule id and reason) read in-session by the person and the agent and recorded in the harness transcript on the customer machine; for Soleur's own verification, the functional probe in scripts/verify-agent-security-slice1.sh printing slice1-security ok
  cadence: every ask or deny; the probe runs in CI on every change under plugins/soleur/hooks and after merge on main
  alert_target: the person at the harness prompt (ask) or the tool-result text (deny); a red CI check for a registration or behaviour regression
  configured_in: plugins/soleur/hooks/destructive-command-guard.sh; plugins/soleur/hooks/hooks.json
error_reporting:
  destination: harness transcript on the customer machine (decision reason), a one-line stderr notice when jq or perl is missing; CI for regressions
  fail_loud: yes — an unreadable envelope, a lexer bound trip or a lexer crash asks with a parse reason; a missing dependency scans the raw envelope and asks on a hit; the one implicit allow in the hook's own failure paths is a raw-scan miss, which is stated and tested
failure_modes:
  - mode: hook silently not registered or its matcher no longer matches Bash
    detection: registration assertion in the hook suite, the ADR-223 parity tests, and the probe script's registration check (layer 7 for the customer surface; CI is the Soleur-side detector)
    alert_route: CI red on plugins/soleur/test and .claude/hooks parity suites
  - mode: lexer diverges from the original or is vacuous (zero records)
    detection: shell-argv-parity byte-identity test with a minimum-size floor; hook suite assertion that a known command yields at least one record
    alert_route: CI red
  - mode: jq or perl missing on the customer machine, guard degraded
    detection: the stderr notice and the raw-scan ask on any destructive-looking command
    alert_route: the person at the harness prompt (layer 7, in-session)
  - mode: false positive interrupts a legitimate command
    detection: the ask reason names the rule id and carries an issues URL; must-PASS rows and the ordinary-command corpus pin the known classes and report the ask rate
    alert_route: the person, via the kill switch and the issue tracker; no Soleur-side telemetry by design
  - mode: hook breaks every Bash call (crash, hang)
    detection: lexer alarm 2 s and budget bounds ask rather than hang; latency measured in Phase 3.7; a crash-path test (perl dies) expects ask
    alert_route: CI red; in-session ask
  - mode: hook answers inside a hosted session
    detection: the Phase 5.2 census and behavioural test (real buildAgentEnv output, exit 0, empty output)
    alert_route: CI red on the web-platform test lane
logs:
  where: harness transcript on the customer's machine; CI logs for regressions
  retention: the harness's own transcript retention, owned by the customer
discoverability_test:
  command: bash scripts/verify-agent-security-slice1.sh
  expected_output: slice1-security: ok
```

## Architecture Decision (ADR/C4)

### ADR

- **ADR-274 (ordinal provisional; `soleur:ship` re-verifies against fresh `origin/main`)**, front matter `Extends: ADR-157, ADR-165` — *the customer plugin ships a narrow, lexer-based destructive-command guard: ask for ambiguous-intent destroys, deny only for deletion of `/`, home or an ancestor; the lexer shares a byte-identical marked spans with the repo's filing lexer; a missing dependency scans the raw envelope and asks on a hit instead of asking on every call (a stated narrowing of ADR-157's `.claude` row, with the reason); the harness transcript is the only record and nothing leaves the machine.* Records the Final Decision Set (D1-D10), the Phase 0 measurements, the rejected alternatives (the Cut List: lift `tokenize()`, port the `guardrails.sh` segmenter, bash-only splitter, move the lexer, blanket fail-open, Soleur-side telemetry, a local log, `exec` coverage, the SQL rule, hosted enablement), the stated non-coverage (D2, including the settings-env kill-switch route), and the residual that a raw-scan miss is an allow. Status: accepted at merge (the behaviour is measured in the suite); the open follow-ups are listed.
- One amendment line on ADR-093: this plugin hook loads into hosted sessions and is disabled there by `AGENT_ENV_OVERRIDES`; W2 protects customer-machine users, not hosted founders. No ADR-157 or ADR-223 amendment (ADR-274's front matter and the ledger row carry them).

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) are read in full at work time (a keyword grep is not evidence). Checked so far: the `snapshotGuard` component at `model.c4` line ~245 with edges at lines ~906-908 and view includes in `views.c4` at lines ~34, ~52, ~72-73, ~96-99. Required edits, minimal: one plugin component `destructiveGuard` next to `snapshotGuard` and the edge `engine.hooks -> plugin.destructiveGuard` ("PreToolUse ask/deny on destructive commands; no egress"), included in the same view as `snapshotGuard` so `c4-render` does not flag an orphan, plus the description of any element these edits falsify. `operator-stage-approval.sh` is not modelled as a component; the reason this one is is that it, like `snapshotGuard`, is a security guard whose hosted posture differs from its customer posture, which the diagram is the right place to show. External actors and systems checked as already modelled: the person running the plugin and the agent (`engine.claude`). The change adds a confirmation prompt, not a new access relationship; no Soleur-side sink or vendor is added. After editing, run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (no workflow, monitor or Resend count changes; a green run is the evidence).

### Sequencing

ADR-274, the ADR-093 line and the C4 edits ship in this PR; none is deferred to a follow-up issue.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm's `## Domain Assessments` and the slice-1 plan; no fresh sweep).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Carried forward: the near-empty customer-plugin guard is a real gap. This plan's research changes the mechanism (vendored lexer instead of a lifted tokenizer) and closes the ADR-165 fail-open the slice-1 sketch reintroduced. Plan review (devex lens) priced a bash-only splitter and a move of the lexer and recorded why neither was taken; the Perl dependency and lexer drift are carried as named risks.

### Product (CPO)

**Status:** reviewed (brainstorm and slice-1 plan); **explicit sign-off on the final decision set pending, recorded in PR #9653 at Phase 0.3**
**Assessment:** Carried forward: one founder-visible ask on destructive commands; friction handled by a narrow set, `ask` where intent is ambiguous, and honest scope statements (W2 does not cover hosted founders).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Carried forward: claims follow measured controls. W2 adds no Soleur processing and no sub-processor; the hook runs on the customer's machine, sends nothing, and writes no log. No public claim; no Art. 30 TOM entry is added because the control is not Soleur's processing. `soleur:gdpr-gate` ran at plan time (artifact-distribution trigger: a plugin update ships the hook): 0 Critical, 0 Important, 2 Suggestion, both honoured.

### Product/UX Gate

**Tier:** none
**Decision:** no user-facing page or component in the Files lists; the mechanical UI-surface override did not fire (no `components/**/*.tsx`, `app/**/page.tsx` or `layout.tsx`).
**Pencil available:** N/A (no UI surface)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement PR 2 of epic #9601 … the W2 plugin destructive-command guard" | Phases 1-6 | mapped |
| 2 | "BEFORE implementing, obtain CPO sign-off (spawn soleur:product:cpo) on the FINAL W2 decision set and record that sign-off in the PR body" | Phase 0.3 and the Final Decision Set section | mapped |
| 3 | "The PR body must close nothing but link the epic (use `Ref #9601`, not `Closes`" | Phase 0.3 PR-body rule and its verification command | mapped |
| 4 | "Scope is W2 ONLY … do not implement … mention only as follow-ups" (W3, broker, ADRs, control page, filing vocabulary, canary re-measure, pipefail sweep, #9529) | Non-Goals; Phase 6.4 names only the W2-adjacent follow-ups | mapped |
| 5 | "do not block on it, and if needed report it as unverified" (the Sentry token) | No task depends on it; reported in the session summary | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Hook, rule table, registration | "the W2 plugin destructive-command guard" | asked |
| Phase 0.3 CPO gate and PR-body rule | "obtain CPO sign-off (spawn soleur:product:cpo)" | asked |
| Vendored lexer and parity test | — | inferred — justification: the two reuse paths the slice-1 plan named were measured not to work; a regex guard is structurally blind to quoted, substituted and heredoc spellings (ADR-256) |
| Raw-envelope scan for missing `jq`/`perl` | — | inferred — justification: ADR-165 measured the unconditional fail-open as a one-call disarm |
| Zero-spawn prefilter | — | inferred — justification: the hook runs on every Bash call; the prefilter skips only what the lexer path would also allow, pinned by boundary rows |
| `cd` modelling, wrapper tables, `q`/`x` flags | — | inferred — justification: without them ordinary spellings (`cd ~ && rm -rf ./*`, `doppler run -- terraform destroy`, `rm -rf '~'`) break P1 or P2 with no obfuscation involved (plan review, spec-flow and Kieran seats) |
| PreToolUse hook classification census (hosted) | — | inferred — justification: a hand-keyed override test cannot catch the next hook author forgetting the override (architecture seat) |
| Hosted override in `agent-env.ts` | — | inferred — justification: plugin hooks load into hosted sessions (ADR-093) and every operator hook is neutralized there the same way |
| Registry rows, shard census | — | inferred — justification: ADR-223 parity tests and the shard census fail on an unregistered new suite |
| ADR-274, one ADR-093 line, C4 edits | — | inferred — justification: the plan skill makes the ADR and C4 update a deliverable of the plan that changes the architecture |
| `verify-agent-security-slice1.sh` extension | — | inferred — justification: the observability gate needs a local one-command discoverability probe under its 15 s cap |
| Spec FR2 amendment, a pointer line in the slice tasks file | — | inferred — justification: a spec that contradicts what ships misleads the next slice |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `.claude`, `apps/web-platform`, `knowledge-base` (plus `scripts`)
- Planned files: ~20 | Estimated changed lines: ~1,300 (the lexer copy and the grammar fixture dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: do not split further. The thresholds trip on lexer size and root count, but the pieces are not separable releases: the hook is useless without the lexer, the registries fail without the hook, and the hosted override must ship with the hook or a hosted session gains a hook the platform did not choose (P4). The slice-1 plan already split W2 from W1 and W3 on blast-radius seams, and this is that W2 PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **First:** Phase 0.4 holds: PR #9653's body carries the CPO sign-off for a named revision SHA and section hash, `Ref #9601`, none of `Closes #`, `Fixes #`, `Resolves #`, and the title is no longer `WIP:`; the check is re-run before the PR is marked ready, and no implementation commit precedes the sign-off commit in `git log`.
- [ ] Phase 0.1 and 0.2 results (parity dry run, headless and cron plugin loaders, subagent, `dontAsk`, `auto`, `claude -p`, `bypassPermissions`, `systemMessage`) are recorded with exact commands in `phase-0-measurements.md`, and D3, D4, D6 and D9 match them.
- [ ] `destructive-command-guard.sh`, `lib/shell-argv.pl` and the `hooks.json` entry are in; `destructive-command-guard-hook.test.sh` is green with every Guard 1 row and all harness rows, executable rows verified against recording stubs, the stub-only `PATH` canary green, and no row able to run a real destructive command.
- [ ] `destructive-command-guard-mutation.test.sh` is green: M1-M8 each redden the suite in a COPY of the tree and the working tree is unmodified afterwards (`git status --porcelain` empty for tracked files); rows 9-20 were run once and are recorded in `phase-0-measurements.md`.
- [ ] `shell-argv-parity.test.sh` is green with every Guard 2 row; `.claude/hooks/lib/filing-shape.test.sh` and the filing-shape corpus-parity suite stay green after the marker comments.
- [ ] No false positive on the Phase 1.4 must-PASS list; the ask rate on the ordinary-command corpus is 0 and is reported in the PR body; an unresolvable `$VAR` target produces no decision; a jq-less `PATH` with `rm -f jq; rm -rf ~` asks.
- [ ] The hook uses no bash-4 feature and no GNU-only binary or flag: `grep -cE '(declare -A|mapfile|readarray|readlink -f|realpath|sed -i|date -d|stat -c)'` over the hook prints 0 (a count, never a negated grep); the suite also runs once under `bash --posix` if bash 3.2 is not available.
- [ ] Median added latency for a prefilter-skipped, a lexed and a destructive command is recorded in the PR body and the lexed one is within the Phase 3.7 budget.
- [ ] One `soleur-plugin` row in `devin-dispositions.tsv`; `devin-matcher-parity.test.sh`, `guard-vacuity-floor.test.sh` (new suites score FIRES; `PROMOTED_FILES` and `MAX_DEFERRED` untouched), `lint-orphan-test-suites.sh`, `plugins/soleur/test/components.test.ts` and `plugins/soleur/test/devin-plugin.test.ts` are green; README rows are in.
- [ ] `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` is in `AGENT_ENV_OVERRIDES`; the PreToolUse hook classification census and the real-`buildAgentEnv` behavioural test are green, and the kill-switch-order mutation reddens them.
- [ ] ADR-274 is written (ordinal re-checked against fresh `origin/main`) and the ADR-093 line is added; C4 edited with `c4-code-syntax`, `c4-render`, `c4-count-parity` and `c4-model-freshness` green; spec FR2 amended.
- [ ] `bash scripts/verify-agent-security-slice1.sh` prints `slice1-security: ok` with the guard check included.
- [ ] The plugin README carries the scope sentence (C1) and the hosted-gap line (C2); the `deny` `systemMessage` carries the escape hatch and issues URL (C4) and a test asserts it; the PR body states that the ask rate of 0 is measured on a synthetic corpus.
- [ ] The deferral issue is created with a milestone and linked from the PR body; `soleur:gdpr-gate` and `soleur:engineering:review:user-impact-reviewer` have run.

### Post-merge (agent-verified, no operator steps)

- [ ] `bash scripts/verify-agent-security-slice1.sh` prints `slice1-security: ok` on `main` (verified by `soleur:postmerge`).
- [ ] The first plugin-release CI run after merge is green with the new suites executed (not skipped), read from the run summary.

PR body uses `Ref #9601`, never `Closes` (the epic stays open for W3).

## Test Scenarios

- `terraform destroy` → ask; `ls && terraform destroy` → ask; `bash -c 'rm -rf ~'` → deny; `terraform plan; rm -rf ~` → deny; `cd ~ && rm -rf ./*` → deny; `doppler run -- terraform destroy` → ask; `echo "terraform destroy"` → no decision; a heredoc body containing `terraform destroy` → no decision; `git push --force origin main` → ask; `git push --force-with-lease origin feature` → no decision; `rm -rf node_modules` → no decision; `rm -rf ../..` from a subdirectory → ask.
- Envelope: garbage stdin → ask; `.tool_input.command` an array → ask; `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` → no output; `=0` → still guarded; a bound trip → ask with the parse reason.
- Degraded: jq-less `PATH` with `rm -f jq; rm -rf ~` → ask and a stderr notice naming `jq`; jq-less `PATH` with `ls` → exit 0; perl-less `PATH` → the decoded command is scanned.
- Harness matrix (Phase 0.2, current CC version): `claude -p` ask → call blocked with reason; `bypassPermissions` ask → still prompts; subagent turn → hook fires and ask holds; `dontAsk` and `auto` recorded.
- Hosted: the census lists every PreToolUse hook; the real-`buildAgentEnv` run exits 0 with empty output for each auth scheme.

## Risks and Sharp Edges

- **Lexer drift.** The structural control (byte-identical marked spans) is stronger than a behavioural corpus but still means two files; a lexing fix lands in the original first and is copied. Making the plugin copy canonical is a tracked follow-up trigger, not W2 scope, because the original is bound by ADR-256 to a second implementation.
- **Perl on customer machines.** Present on macOS, nearly every Linux and Git for Windows; absent on minimal Alpine-style images. D6's raw scan keeps the guard on (narrowly) rather than off, at the price of a stated raw-scan-miss allow. The stderr notice is likely invisible to the person; a session-start posture message is a follow-up.
- **False positives are the user-visible failure.** The set is narrow, every rule has must-PASS neighbours plus an ordinary-command corpus, and the kill switch needs a restart by design. A false-positive report is handled by tightening the rule in the fixture first.
- **Headless runs.** `ask` becomes a block with no person present; D4's reason tells the agent to end and report blocked. A CI teardown that legitimately runs `terraform destroy` has no per-rule allow in W2 (follow-up); the kill switch is all-or-nothing.
- **Devin and `exec` are out of scope.** Devin users get no W2 protection until the measured follow-up lands; the ledger row says `skip` and why.
- **The hook is a seatbelt, not a boundary.** Obfuscation, a script written then run, glob or brace expansion of a command name, MCP delete tools, and a settings-level `env` block that sets the kill switch are out of scope and stated in the header and ADR-274. There is no decision log, so an incident review reads the harness transcript.
- **Another hook's `updatedInput` is invisible to this hook:** it judges the original command (header says so); `operator-stage-approval.sh` only rewrites a single staged `bash <script> --apply` form this hook does not match.
- **The oracle is stub-only.** A bare `PATH` of stubs plus a canary is what keeps the suite from ever running a real `rm`; any new row that needs a real binary must carry a literal expectation instead.
- **Two research subagents were wrong on checkable facts** (portability of `guardrails.sh`, the sibling suite's existence, a `.devin/config.json` registration). Work-time reads files, not summaries.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this one is filled. The Guard Contract headings use the exact `## Guard Contract` / `### Guard <n> —` spellings `lint-guard-contract.py` matches.

## Non-Goals / Deferrals

Out of scope for this PR and tracked on the epic or its children, not closed here: the image CVE scan (W3, the next PR), the egress credential broker (#9543), per-session containers and Landlock ADRs (#9602), the security/control page (#9603), the filing-gate vocabulary chore (#9604), the in-image canary re-measure and flipping ADR-272 to accepted (the canary fixture defect is tracked at #9614), the pipefail grep sweep, and the operator's decision on holding draft PR #9529. The Sentry token with `event:read` for the `feature:agent-sandbox` check is an operator-side item; nothing here depends on it and it is reported as unverified. W2-adjacent follow-ups (one issue, created at Phase 6.4): hosted enablement, Devin `exec` coverage and `ask` measurement, the D2 candidates (SQL rule, settings-env tripwire), a canonical plugin-side lexer, a session-start posture message, a per-rule allow for headless CI.
