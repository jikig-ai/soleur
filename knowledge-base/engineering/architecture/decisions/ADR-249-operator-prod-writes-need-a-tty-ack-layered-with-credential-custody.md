---
title: Production-writing operator scripts require a TTY acknowledgement; hijacked-agent resistance needs credential custody
status: active
date: 2026-09-24
---

# ADR-249: Production-writing operator scripts require a TTY acknowledgement; hijacked-agent resistance needs credential custody

Issue: #8486 (step 1, this ADR's accepted part). Step 2: #8652 (adopting). Related: ADR-228
(generated operator scripts are non-interactive by default; the class-2 ack is the one exception),
ADR-236 (human-only skills are user-invoked; the invocation axis is not a security control).

## Context

Soleur's operator scripts write to production: Flagsmith flags and segments, prd user roles in
Supabase, Doppler secrets, Sentry alert rules. Before this ADR, the scripts gated those writes on
a prompt that an agent's tool subprocess could satisfy. `read -p "Type 'yes'"` accepts piped stdin,
and `flip.sh --confirmed` skipped the prompt "for agent-driven use". So an agent could complete a
production write with no person present, and the WORM audit row then attributed the write to the
operator. ADR-236 §Decision 4 records that `disable-model-invocation` stops the Skill tool, not a
Bash call to the script path. It names this gap as #8486.

The premise that sizes the answer (brainstorm D2, measured): the operator's Doppler owner token
reads every production write key. An agent running under the operator's user can therefore call
the Flagsmith or Supabase APIs directly with `curl`. Any check that lives in a script is a speed
bump against a *hijacked* agent. It stops only an *accidental* agent, one that follows the skill's
instructions and the script's exit codes.

## Considered Options

- **Option A: harden each typed-yes prompt.** Pros: small diff. Cons: stdin belongs to the agent,
  so every hardening of a `read` is satisfiable by the process that owns stdin. Rejected.
- **Option B: a UserPromptSubmit marker hook** (the issue's proposal: allow a script only when the
  turn began with `/soleur:<skill>`). Cons: Claude Code only; new cross-event state; breaks
  `/soleur:go` routing to the model-invocable `flag-create`/`flag-set-role`; the marker lasts the
  whole turn. Rejected (brainstorm D4).
- **Option C: a nonce the operator echoes back.** Cons: the agent reads the nonce from the same
  stream it would answer from. Rejected (brainstorm D4).
- **Option D: `hookify`-style per-command confirmation.** Cons: Claude Code only, and an ack in a
  menu is not production-write authorization (`hr-menu-option-ack-not-prod-write-auth`). Rejected.
- **Option E (chosen for step 1): the library's class-2 TTY ack in every write path, plus a
  Claude-side defer-gate backstop.** `soleur_op_ack_or_die` has no skip variable and no flag: a
  write needs a person typing `yes` at a terminal. Pros: works in every harness whose tool
  subprocess has no TTY; already built and guarded (`operator-script.test.sh` Guards 4 and 8).
  Cons: a harness that can allocate a PTY can satisfy it (see the coverage table).
- **Option F (chosen for step 2, #8652): credential custody.** Move the write keys out of the
  operator's Doppler reach into a broker that demands unforgeable approval. This is the only option
  that resists a hijacked agent. It is larger, so it lands as its own step.

## Decision

Layered (brainstorm D1): step 1 now stops the accidental agent; step 2 stops the hijacked agent.

**Step 1 (accepted, lands with #8486):**

1. **The guard set** (D3). It covers every script that gates a production write on a confirmation,
   whether or not its skill is user-invoked: `flag-delete/scripts/delete.sh`,
   `flag-create/scripts/create.sh`, `user-set-role/scripts/set-role.sh`,
   `flag-set-role/scripts/flip.sh`, and `apps/web-platform/scripts/audit-sentry-extra-text-references.sh --apply`
   (Sentry alert rules, saved searches, Discover queries and dashboards; no prompt at all before).
   `provision-hetzner.sh` already used the ack. The set is **derived**, never hand-listed.
   `plugins/soleur/test/operator-ack-guard.test.sh` Guard 1 censuses every tracked raw typed-yes
   prompt and confirm-skip flag against a classified exemption registry. Its Guard 2 takes its
   population from `git grep soleur_op_ack_or_die`, set-identical to
   `plugins/soleur/test/fixtures/operator-ack-arms.tsv`.
2. **Every write gates on the TTY ack** (D4). After argv parsing and before any credential fetch or
   network call, a write-mode run checks `[[ -t 0 ]]`; with no TTY it exits `64` with
   `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`. The ack itself sits after the preview and before the WORM
   append. `flip.sh`'s confirm-skip flag is removed; passing it now fails as an unknown flag (exit
   `2`) with a message naming the operator's own terminal. `--dry-run` (and audit-sentry's default
   inventory) stays agent-runnable. An operator "no" now exits `1`, not `0`.
3. **Consumers clear what could stand in for the ack** before sourcing the library:
   `_SOLEUR_OPERATOR_SCRIPT_LOADED`, `SOLEUR_OP_ACKED`, and the ack/refusal functions. An exported
   `BASH_FUNC_soleur_op_ack_or_die%%` would otherwise survive the double-source guard as a no-op.
   Value-taking options refuse values that begin with `--`, so the hook's read-only escape and the
   script's parser cannot disagree about `--dry-run`.
4. **The skills hand off the write** (P9). The agent runs `--dry-run` and prints the exact write
   command, `cd <absolute worktree> && bash <absolute script> …`, for the operator's own terminal.
   That handoff is an undone operator step under `wg-block-pr-ready-on-undeferred-operator-steps`.
   `flag-set-role/SKILL.md` carries an incident-rollback block. Its break-glass is the Flagsmith
   dashboard, used when the WORM append exits `4`.
5. **The Claude-side backstop.** `.claude/hooks/prod-write-defer-gate.sh` rule
   `prod-write-defer-operator-ack-script` defers any write-mode invocation of those scripts. It
   evaluates every call in a command, scopes the `--dry-run` escape to that call's own argument
   tail, allows no read-only escape under a PTY wrapper or `yes |`, and fails closed on its own
   error. It is registered for the `Bash` and `Monitor` tools. It skips the two-week dry-run
   expansion gate: after step 1 no correct agent run of these scripts writes, so a false-positive
   defer costs nothing. The existing three rules' whole-command read-only escape is #8662.
6. **Approval evidence** (D6). Migration 140 adds `flag_flip_audit.approval_method` (`'tty-ack'`
   or NULL). `soleur_op_ack_or_die` sets the plain, non-exported `SOLEUR_OP_ACKED=tty-ack` after a
   typed `yes`, and the library clears it at load. `plugins/soleur/scripts/audit-flag-flip.sh`
   refuses to append (exit `4`) unless it sees that value, and sends it as `p_approval_method`.
   So `tty-ack` means "the script's TTY gate returned in this process". It is **self-reported**:
   the shell vouches for itself, which is not proof that a person typed.

**Per-harness coverage (D7, measured 2026-09-24 unless marked).** D7 in the brainstorm said the
TTY ack covers every harness. The Codex row below falsifies that, and this table replaces it.

| Harness | TTY ack (tool subprocess) | `/dev/tty` reachable | Defer gate | Evidence |
|---|---|---|---|---|
| Claude Code (Bash tool) | **Refuses**: `stdin=notty`, measured | unreachable, measured | Registered (`Bash`, `Monitor`) | `bash -c '[[ -t 0 ]] …'` in this session |
| Claude Code `!` prefix | UNMEASURED (only a person can type it) | UNMEASURED | n/a (not a tool call) | SKILL.md says: use your own terminal |
| Codex CLI 0.156.1, default exec | **Refuses**: `stdin=notty`, measured | unreachable, measured (read-only sandbox) | Not registered (`.codex/config.toml` registers no defer hook) | `codex exec -s read-only` probe |
| Codex CLI 0.156.1, exec with a PTY | **Speed bump only**: `stdin=tty`, measured | not probed | Not registered | second probe, the model enabled its tty option |
| Devin CLI 3000.11.3 (local) | **Refuses**: `stdin=notty`, measured | unreachable, measured | Registered; `defer` behaviour UNMEASURED (`.claude/hooks/devin-dispositions.tsv`) | `devin -p` probe from the worktree |
| Devin cloud | UNMEASURED | UNMEASURED | Runs no hooks | `plugins/soleur/AGENTS.md` §Cloud Sessions |
| Grok Build 1.0.41 | UNMEASURED (probe returned HTTP 402, usage balance exhausted) | UNMEASURED | Not registered (`.grok/config.toml`) | probe attempted 2026-09-24 |

A harness that can allocate a PTY, or reach `/dev/tty`, turns the ack into a speed bump there,
exactly like `script -qc` does anywhere.

**Step 2 (adopting, #8652).** A main-only workflow broker holds rotated keys: the Flagsmith write
key and the prd service-role key, moved out of the operator's Doppler reach. The broker verifies a
FIDO2 `sk` touch over its own nonce plus an operation digest, and writes the approval evidence into
the audit row. That widens the `approval_method` CHECK beyond `'tty-ack'`. Named residuals for step
2: a blind touch (the key has no display), and the broker's own compromise.

## Consequences

- An agent can no longer complete a flag, role or Sentry-rule write by piping `yes` or passing a
  flag. It gets exit `64` before any credential is fetched. The only route left in Claude Code is a
  PTY wrapper, and the defer gate stops that **for the four scripts under their documented paths and
  basenames**. The defer gate's `opack_prefilter` keys on the literal basename
  (`flip.sh`/`create.sh`/`delete.sh`/`set-role.sh`/…), so a PTY wrapper invoking a byte-identical copy
  under a different filename evades the prefilter entirely — no defer, no `approvals.jsonl` row, no
  incident emission — while the primary `[[ -t 0 ]]` ack gate still requires a real pty to satisfy
  (review #8650, security-sentinel). This basename-bypass-under-PTY combination is a **named residual**
  alongside the PTY-generally residual above: closing it needs the prefilter to key on a content
  fingerprint (does the resolved script source `operator-script.sh` / call
  `soleur_op_ack_or_die`?) rather than on basename.
- Plans that prescribe an agent `flag-create`/`flag-set-role` apply step now become printed-command
  handoffs. A pipeline that treated exit `64` as done would ship code whose safety depends on a flag
  state nobody set; the blocking-operator-step rule is what prevents that.
- `audit-sentry-extra-text-references.sh` is the first `apps/` → plugin-internals dependency: it
  sources `plugins/soleur/scripts/lib/operator-script.sh`, inherits `umask 077` and the library's
  exports, and sits outside the plugin root. So Guard 2 and the defer rule cover it, but
  `operator-script.test.sh` Guards 3, 4, 5′ and 9 do not. Its five `while IFS= read` data loops are
  outside Guard 4's population for the same reason. A future move of that root must bring them in.
- `operator-script.test.sh` Guard 9 was blind to `printf … | <writer>`: it dropped every
  echo/printf line as quoted output. It now blanks only the quoted text. Its pattern also covers
  Doppler deletes, `audit_flag_flip_rpc` and curl mutating methods. A consumer whose writes sit
  outside the 15-line ack window is accepted only when it has a `write` row that Guard 2 proves
  behaviourally.
- Every refused agent attempt appends a `run_halt` line to `bootstrap-runs.jsonl` beside the
  script (gitignored): the plugin install directory for the skills, `apps/web-platform/scripts/`
  for audit-sentry.
- **Rollback order for migration 140.** Revert the helper (the `p_approval_method` body key) and let
  the revert reach the operator's installed plugin BEFORE running the down migration. Otherwise
  every flag write exits `4` before any mutation. The `.down.sql` header states this.

**Residual risks (named, not closed by step 1):**

- any PTY an agent can allocate: `script -qc`, `unbuffer`, `expect`, `python3 -c 'import pty'`, or
  a harness exec tool with a PTY option (Codex, measured above);
- direct `curl` with the Doppler-held keys, which skips the scripts and the WORM row;
- the Flagsmith and Supabase dashboards, through shared browser cookies;
- an exported `BASH_ENV`, which runs before the script and cannot be cleared from inside it
  (hijack-class);
- for audit-sentry, the agent already holds the Sentry token from the caller's environment
  (`doppler run … --`) when the precheck runs, so P1 holds there as "before any network call",
  not "before any credential fetch";
- a defer-rule miss for a basename-only invocation whose `cd` happened in an earlier Bash call;
- the ungated local production writers (`gdpr-override.sh`, `rotate-supabase-db-credential.sh`
  and others): they have no gate to fix and each needs its own read-only/write split. Census
  command and classification in #8661;
- the existing defer rules' whole-command read-only escape (#8662).

Full closure is agents on a separate OS user, beyond step 2.

## Cost Impacts

None for step 1: no new vendor, service or tier. Step 2 (#8652) will state its own.

## NFR Impacts

- NFR-041 (Link-Level Access Control): the operator → Flagsmith and operator → Supabase (prd role)
  write links are now gated on a person at a TTY for the accidental agent. The status does not move
  to Implemented until step 2 takes the credentials out of the agent's reach.
- NFR-030 (Data Accuracy): the WORM audit row now records how a write was approved
  (`approval_method`), and the helper refuses an append made before the ack.

## Principle Alignment

- AP-007 (Exhaust automation before manual steps): Deviation, justified. A production write
  becomes a person-at-a-terminal step on purpose. The preview stays automated, and the handoff is a
  tracked blocking step, never a silent manual one.
- AP-008 (Doppler for all secrets management): Aligned. No secret moves in step 1. Step 2 moves the
  write keys out of the operator's Doppler reach into the broker.
- AP-020 (Untrusted input at the agent boundary): Aligned. The defer rule treats the command string
  as adversarial: every call is evaluated, the escapes are segment-scoped, and it fails closed.
- AP-011 (ADRs for architecture decisions): Aligned.

## Diagram

The C4 model gains the Flagsmith external system (it was unmodeled), the web app's runtime-flag
read, and the founder's terminal-gated write edge:

```likec4-view
context
```
