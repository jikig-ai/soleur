---
title: "security(operator-scripts): human-presence guard (TTY ack + defer-gate backstop) for production-mutating operator scripts — step 1 of #8486"
date: 2026-09-23
slug: feat-human-presence-guard-operator-scripts
branch: feat-8486-human-presence-guard
issue: 8486
closes: 8486
type: security
lane: cross-domain
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: human-presence guard for production-mutating operator scripts (step 1 of #8486)

## Enhancement Summary

**Deepened on:** 2026-09-23 (headless, lean fan-out under the session's API rate budget)
**Agents used:** `soleur:engineering:review:security-sentinel`,
`soleur:engineering:review:user-impact-reviewer`, one verify-the-negative Explore pass; plan-review
already ran `architecture-strategist` and `code-simplicity-reviewer`. Gates run mechanically: 4.6
(User-Brand Impact), 4.7 (Observability; `probe-verb-gate.sh` accepts the discoverability command),
4.8 (no PAT shapes), 4.10 (Encryption Posture fields), 4.11 (`lint-guard-contract.py`: 4 entries);
4.4 precedent diff against migration 137; 4.55 downtime gate evaluated and not triggered. The
exhaustive "run every agent" fan-out of Phase 5 was not run.

### Key improvements

1. Handoff hardening (user-impact): the printed command is absolute and worktree-pinned, the
   handoff is a blocking operator step, and flag-set-role gains an incident-rollback block with a
   dashboard break-glass (Phase 7.1, AC14–AC15).
2. Rollback order for migration 140 (helper revert reaches the installed plugin before the down
   migration) and a read-only pre-merge probe that dev has the 8-arg RPC (AC16).
3. Guard 2 tree isolation: `create.sh`/`delete.sh` overwrite `server.ts`, `.env.example` and
   `flip.sh` in place, so pty-`yes` runs use a scratch copy and assert the worktree is untouched.
4. Resolved at deepen time instead of deferred to work: the `umask` question (in-place writes, no
   new files), audit-sentry's control flow (inventory completes before the first PUT), the LIA edit
   (one bullet; Article 30 register unchanged), audit-sentry's missing `SCRIPT_DIR`, and `go.md`'s
   stale "Skill-tool-invokable directly" text.

### New considerations discovered

- Every write arm is a production write, including `role=dev` arms (`flip.sh` writes both
  Flagsmith environments; `set-role.sh` edits prd users).
- A pipeline that prescribes an agent flag write now gets exit 64; without the blocking-step rule it
  could ship code whose safety depends on a flag nobody set.

## Overview

Step 1 of #8486. The operator scripts that write to Soleur's production gate their writes on a
prompt that piped stdin or a flag can satisfy, so an agent's tool subprocess can complete the write
unattended. This plan moves every such gate onto the existing no-skip TTY acknowledgement, removes
the flag bypass, keeps read-only modes agent-runnable, adds a hook backstop for Claude Code, and
records the layered decision in an ADR. The credential-custody broker (step 2) is #8652.

Concretely:

1. `delete.sh`, `create.sh`, `set-role.sh`, `flip.sh` and `audit-sentry-extra-text-references.sh
   --apply` source `plugins/soleur/scripts/lib/operator-script.sh` and gate every production write
   on `soleur_op_ack_or_die` (no skip variable, no flag). A write-mode run with no TTY on stdin
   exits 64 with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` **before any credential fetch or network call**
   (an early precheck right after argv parsing), and the ack itself sits after the preview, before
   the WORM append.
2. `flip.sh --confirmed` is removed and rejected with an error that names the terminal path.
3. `--dry-run` (and `audit-sentry`'s default inventory mode) stays runnable without a TTY.
4. The four skills tell the agent to run `--dry-run`, then print the exact write command for the
   operator's own terminal and never run it (the `provision-hetzner` precedent).
5. `.claude/hooks/prod-write-defer-gate.sh` gains one rule that defers write-mode invocations of
   every ack-calling operator script (Claude-side backstop), scoped per command segment so a
   `--dry-run` elsewhere in a chain cannot escape it.
6. The WORM row records `approval_method = 'tty-ack'` (migration 140 adds a nullable, enum-checked
   column; the RPC gains `p_approval_method DEFAULT NULL`).
7. ADR-245 (provisional ordinal) records the layered decision D1–D7, the per-harness coverage table
   (measured vs. unmeasured), the step-2 broker design, and the residual risks. ADR-236 is amended
   (its K1 rationale cites `--confirmed`, which this plan deletes). C4 gains the unmodeled Flagsmith
   system and the founder's terminal-gated write edge.
8. The guard set is **derived**, never hand-listed: a census test finds every raw typed-yes prompt
   and confirm-skip flag in tracked scripts, and a behavioral test's population is every script that
   calls `soleur_op_ack_or_die`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (measured 2026-09-23) | Plan response |
|---|---|---|
| FR1: gate the four scripts on `soleur_op_ack_or_die` | The four scripts do not source `operator-script.sh` today. Sourcing it adds them to the library's DISCOVERED consumer population in `plugins/soleur/test/operator-script.test.sh` (`g3_sourcing_scripts`, rooted at `plugins/soleur`), so Guards 3, 4, 5′ and 9 (`gack_check`) start scanning them. Guard 9's `DESTRUCTIVE_RE` matches the Doppler secret-write verb at `create.sh` (two writes ~100 lines after the prompt) and inside `flip.sh`'s `doppler_mirror()` — both fail its "ack within 15 comment-stripped lines above" window. | Phase 3 amends Guard 9: a consumer whose write sites are not window-covered must be registered in the behavioral arm table (Guard 2 below), which proves the same property by execution. Unregistered → RED. `DESTRUCTIVE_RE` widens to the Doppler delete verb, curl mutating methods and `audit_flag_flip_rpc` so the census sees these consumers' writes at all. |
| FR1: "requires a real TTY" | `soleur_op_input_required` prints to **stdout**, calls `soleur_op_run_halt` (a ledger line in `bootstrap-runs.jsonl` beside the main script — gitignored, `.gitignore:61`) and exits 64; `soleur_op_aborted` exits **1** and prints "Nothing was created." The four scripts exit **0** on an operator "no" today. The library also sets `umask 077` at source time. | Exit-code contract change (abort 0 → 1) lands in each script header and SKILL.md exit table. `umask 077` is checked against every file each script writes (Phase 2 task). |
| TR1: refused "before any network call" | Every script fetches `FLAGSMITH_MANAGEMENT_API_KEY` / the prd `SUPABASE_SERVICE_ROLE_KEY` from Doppler and GETs live state **before** today's prompt (the preview needs it). | An early precheck `[[ -t 0 ]] \|\| soleur_op_input_required "destructive-write-ack(no-skip-variable-by-design)" ack` runs right after argv parsing when not in a read-only mode — before `command -v` checks, Doppler reads and curl. A no-TTY write run never pulls the prod write key into the process. The ack after the preview stays (it is what a person answers). |
| FR6: "the WORM audit row records `approval_method=tty-ack`" | `public.flag_flip_audit` (migration `071_flag_flip_audit.sql`) has no such column; `audit_flag_flip(text,text,text,text,bool,bool,text)` has no such parameter. The table is WORM (UPDATE trigger raises). The audit DB target is Doppler `soleur/dev`. | Migration 140 (provisional) adds `approval_method text NULL CHECK (approval_method IS NULL OR approval_method IN ('tty-ack'))` and replaces the RPC with an 8-arg version whose last parameter defaults to NULL. The shared helper sends `p_approval_method: "tty-ack"` in every body. |
| FR7: derive the guard set as "scripts that mutate production" | A write-verb census (curl `-X POST/PUT/PATCH/DELETE`, Doppler `secrets set/delete/upload`, `gh secret/variable set`, `hcloud server create`, `terraform apply`, `audit_flag_flip_rpc`) over tracked non-test `*.sh` returns **49** files; ~14 run locally with no workflow invoking them, and **none of those 14 has any prompt** (e.g. `gdpr-override.sh`, `rotate-supabase-db-credential.sh`, `trigger.sh`). Several are agent-runnable by design (`trigger-cron`, `community`). | The #8486 class is a gate that claims human presence but does not prove it. The derived guard set is therefore (a) every script with a raw typed-yes prompt or confirm-skip flag (Guard 1 census) plus (b) every script that calls the ack (Guard 2 population). `audit-sentry-extra-text-references.sh --apply` joins (b) by decision (below). The ungated-writer census is recorded in the ADR as a residual and tracked in #8661, not guarded in step 1. |
| D7 / brainstorm: "Claude Code, Grok, Codex and local Devin all refuse, because a tool subprocess has no TTY" | Measured here for Claude Code only: the Bash tool reports `stdin=notty stdout=notty`. Codex's unified exec and Devin's shell sessions can be PTY-backed; if an agent can allocate a PTY and write `yes\n` to it, the ack is satisfiable in that harness exactly like `script -qc`. Not measured. | Phase 5 measures `[[ -t 0 ]]` under each locally installed harness (`codex`, `grok`, `devin` are on PATH) and records measured/unmeasured per row in the ADR. A harness that can allocate a PTY is recorded as "speed bump only", not "refuses". |
| ADR-236 K1 row: flag-set-role "stays model-invocable … `flip.sh --confirmed` exists for agent-driven use" | True today; false after this plan. The same rationale is pinned as a string in `plugins/soleur/test/components.test.ts` (`MUST_STAY_INVOCABLE`). | ADR-236 amended in this PR; `components.test.ts` reason strings updated. Both skills stay model-invocable: the agent still loads them, runs `--dry-run`, and prints the command. |
| C4 | `model.c4` has no Flagsmith element; the scripts' production writes go to Flagsmith, Supabase (WORM audit), Doppler and Sentry. | Phase 6 adds `flagsmith` (#external) with its edges and view include. |

## Research Insights

**Premise Validation (Phase 0.6).** #8486 open ("typed-yes prompts and flip.sh --confirmed are
agent-drivable"); #8652 open (step 2); draft PR #8650 open. Cited paths all exist on this branch:
`soleur_op_ack_or_die` at `plugins/soleur/scripts/lib/operator-script.sh` (`# soleur_op_ack_or_die
<prompt> [class 2]`, "NO skip variable, by design and by rule"); the class-2 precedent at
`plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh` (`soleur_op_ack_or_die
"Create the billable probe server …"`); `.claude/hooks/prod-write-defer-gate.sh` (three inline
`DEFAULT_TARGETS`, registered only in `.claude/settings.json`). ADR corpus grep for the mechanism:
ADR-228 (generated operator scripts are non-interactive by default, with the class-2 ack as the
one exception) and ADR-236 (human-only skills are user-invoked; §Decision 4 says the invocation axis
is not a security control and names this gap as #8486). Neither rejects a TTY ack; ADR-236 points
at this issue. Premise holds.

**Property List (Phase 0.6b).**

- **P1.** In any harness whose tool subprocess has no TTY on stdin, a write-mode invocation of a
  guard-set script exits 64 with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` before any credential fetch or
  network call.
- **P2.** No flag, argument or environment variable lets a guard-set script skip the ack.
- **P3.** Read-only modes run without a TTY and make zero mutating calls.
- **P4.** A person at a terminal completes each write with one typed `yes`.
- **P5.** The guard set is derived: no tracked script outside the library carries an unclassified
  raw typed-yes prompt or confirm-skip flag, and every script that calls the ack is covered by
  behavioral proof and by the Claude-side defer rule.
- **P6.** In Claude Code (this repo's settings), a write-mode Bash invocation of any ack-calling
  operator script is deferred before execution; a read-only invocation is not.
- **P7.** WORM rows written by the guarded scripts record `approval_method = 'tty-ack'`; rows from
  any caller that omits it record NULL.
- **P8.** An ADR states per-harness coverage (measured vs. unmeasured), the step-2 design, and the
  residual risks.
- **P9.** Each affected skill directs the agent to print the exact command for the operator's own
  terminal, never to run the write.

**Cut List (Phase 0.6b).**

- UserPromptSubmit marker hook (the issue's proposal) → P6 → covered by `prod-write-defer-gate.sh`;
  rejected in D4 (Claude-only, cross-event state, breaks `/soleur:go` routing).
- Nonce → P1/P2 → covered by the TTY ack; rejected in D4.
- New library helper for the early precheck → P1 → covered by the library's own inline idiom
  `[[ -t 0 ]] || soleur_op_input_required … ack` (the shape Guard 4's `TTY_GATE_LINE_RE` already
  recognises).
- A guard over the 49-file ungated prod-writer census with a classification ledger → "no new ungated
  local prod writer lands silently" → not a property of this ask (#8486's class is agent-drivable
  *gates*); recorded as a census snapshot in the ADR plus tracking issue #8661.
- A runtime content-sniffing defer rule (read the invoked script, grep for the ack) → P6 → a static
  path rule whose population is pinned by a set-identity test is simpler and has no file IO inside a
  security hook.
- Keeping the 7-arg RPC beside a new 8-arg overload → P7 → one 8-arg function with
  `p_approval_method DEFAULT NULL` serves old-shape callers.

**Value-proposition measurement (0.6c).** No cost/performance claim; skipped.

**Relevant files.**

- `plugins/soleur/scripts/lib/operator-script.sh` — `soleur_op_input_required` (stdout marker,
  ledger `run_halt`, exit 64, `ack` sentence), `soleur_op_aborted` (exit 1), `soleur_op_ack_or_die`,
  source-time `umask 077`, double-source guard, `SOLEUR_OP_RUN_ID="$$"` set at source time.
- `plugins/soleur/test/operator-script.test.sh` — Guard 3 (`g3_sourcing_scripts`: `grep -rl
  'lib/operator-script\.sh'` under the plugin root, minus tests and the library), Guard 4 (every
  `read` site in a consumer needs a `[[ -t 0 ]] || soleur_op_input_required` LINE within 12 lines
  above), Guard 9 `gack_check` (`DESTRUCTIVE_RE`, 15-line ack window), Guard 5′ (xtrace refusal above
  the `source` line for credential-acquiring consumers). Uses `script -qec` to drive prompts through
  a pty.
- The four scripts: `plugins/soleur/skills/flag-delete/scripts/delete.sh` (typed-yes at
  `read -r -p "Proceed? Type 'yes': " ACK`), `flag-create/scripts/create.sh`,
  `user-set-role/scripts/set-role.sh` (dry-run is positional `$3`), `flag-set-role/scripts/flip.sh`
  (`gate_or_confirm()` plus two inline copies in the detach and org arms; `--confirmed` in the argv
  `case`). All four already carry the #7797 xtrace refusal at the top and all four source
  `plugins/soleur/scripts/audit-flag-flip.sh`.
- `apps/web-platform/scripts/audit-sentry-extra-text-references.sh` — default GET-only inventory;
  `--apply` issues `curl -X PUT` against production Sentry alert rules, saved searches, Discover
  queries and dashboards; **no prompt**; token from env (`SENTRY_AUTH_TOKEN`); five `while IFS= read
  -r id` data loops; xtrace refusal present. Referenced by
  `knowledge-base/engineering/operations/runbooks/oauth-probe-failure.md` and ADR-031. Outside the
  plugin root, so outside `g3_sourcing_scripts`.
- `plugins/soleur/scripts/audit-flag-flip.sh` — `audit_flag_flip_rpc`, `jq -nc` body with seven
  `p_*` keys, returns 4 on any failure.
- `apps/web-platform/supabase/migrations/071_flag_flip_audit.sql` and
  `apps/web-platform/test/migration-071-flag-flip-audit.test.ts` (pins the 7-arg REVOKE/GRANT text of
  071 only).
- `.claude/hooks/prod-write-defer-gate.sh` + `.test.sh` — `TARGETS` entries `rule_id|prose|ERE`,
  `READONLY_FLAG_PATTERNS` evaluated against the **whole** command (so a `--dry-run` anywhere in a
  chain escapes), header "Expansion gate: NEW entries only after 2-week dry-run telemetry".
- Tests that drive `flip.sh` writes with `--confirmed`: `plugins/soleur/test/flag-detach-shared.test.sh`
  (`run_detach … --confirmed`, stubbed curl/doppler on PATH) and
  `plugins/soleur/test/flag-org-scoping-pr2.test.sh`.
- `scripts/test-all.sh` `SUITE_GLOBS` auto-registers `plugins/soleur/test/*.test.sh` and
  `.claude/hooks/*.test.sh`.
- `.claude/hooks/devin-dispositions.tsv` row for `prod-write-defer-gate.sh`: "emits
  permissionDecision:defer — UNMEASURED under Devin". `.grok/config.toml` and `.codex/config.toml`
  do not register the hook (grep count 0).

**Institutional learnings applied.**

- `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` — a menu/AskUserQuestion ack is
  not prod-write authorization; show the exact command. This is why `flip.sh --confirmed` (agent
  obtains AskUserQuestion ack, then passes the flag) is removed rather than hardened.
- `2026-02-24-guardrails-chained-commit-bypass.md` — anchor hook regexes on command boundaries
  `(^|&&|\|\||;)`, not `^`; mirrored on the trailing side.
- `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md` — hook behavior is tested
  in CI via its `.test.sh`, not assumed.
- `2026-03-13-skill-md-must-mirror-agent-command-lists.md` — SKILL.md and script usage change in
  the same PR.
- `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` — WORM functions
  under SECURITY DEFINER inherit the definer; keep `search_path = public, pg_temp` pinned.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — every
  guard below carries must-PASS rows and harness rows, not only RED rows.

**External research.** Skipped: strong local precedent (the class-2 ack, its guard suite and the
defer gate all exist and are tested); the change is internal to Soleur's own operator tooling.
Community discovery (1.5) and functional-overlap (1.5b) agents were not spawned under the session's
API rate budget; no registry skill can overlap a control over Soleur-private scripts.

**CLAUDE.md / AGENTS conventions in play.** `hr-menu-option-ack-not-prod-write-auth`,
`hr-the-bash-tool-runs-in-a-non-interactive`, `hr-verify-repo-capability-claim-before-assert`,
`cq-silent-fallback-must-mirror-to-sentry` (no silent RPC fallback), `cq-pg-security-definer-search-path-pin-pg-temp`,
`cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`, `hr-autonomous-loop-skill-api-budget-disclosure`
(Phase 5 harness probes spend a few model calls; disclosed there).

## Decision: does `audit-sentry-extra-text-references.sh --apply` belong in the guard set?

**Yes.** It writes to production (PUTs against Sentry alert rules, saved searches, Discover queries
and dashboard widgets), it runs locally with an operator credential, it is named in an operator
runbook an agent reads (`oauth-probe-failure.md` prints the `doppler run … bash …` line), and it has
no prompt at all. A silent rewrite of production alert rules can blind alerting for every tenant —
a single-user-incident-class harm. Cost is small: an early precheck when `APPLY=1`, one ack after
the inventory and before the first PUT (skipped when there are zero matches), and a behavioral arm.
Its default mode (GET-only inventory) stays agent-runnable. It sources the library by repo-relative
path (`$SCRIPT_DIR/../../../plugins/soleur/scripts/lib/operator-script.sh`), placed below its
existing xtrace refusal. Its five `while IFS= read` data loops are outside Guard 4's population
(rooted at the plugin), so no Guard 4 change is needed for it; this is recorded in the ADR so a
future move of the population root does not surprise anyone.

The other ungated local prod writers (`gdpr-override.sh`, `rotate-supabase-db-credential.sh`,
`rotate-x-api-secret-bootstrap.sh`, `rotate-sentry-actions-ro-token.sh`,
`provision-operator-digest-repo.sh`, `provision-plausible-goals.sh`, `create-cla-required-ruleset.sh`,
`configure-auth.sh`) are **not** in step 1: they have no gate to fix, and each needs its own
read-only/write split before an ack can land. They are listed in the ADR with the census command and
tracked by #8661 (filed at plan time).

## Implementation Phases

### Phase 0 — Tracking and measurement (before code)

- 0.1 Filed at plan time: **#8661** ("ungated local production writers need a per-script
  human-presence decision") with the census command below, the classified list from the Decision
  section and the re-evaluation criterion. Record it in the ADR and the PR body.
- 0.2 Filed at plan time: **#8662** — the three existing defer-gate rules evaluate their read-only
  escape against the whole command (`wg-when-an-audit-identifies-pre-existing`). Not fixed here.

  ```bash
  git ls-files -- 'plugins/soleur/skills/*/scripts/*.sh' 'apps/*/scripts/*.sh' 'scripts/*.sh' 'plugins/soleur/scripts/*.sh' \
    | grep -vE '\.test\.sh$|/test/' \
    | xargs grep -lE 'curl[^|;]*-X[[:space:]]*(POST|PUT|PATCH|DELETE)|doppler secrets (set|delete|upload)|audit_flag_flip_rpc|hcloud server create|terraform apply|gh (secret|variable) set'
  ```

### Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

Write Guards 1–4 (see Guard Contract) and the migration test before touching the scripts. Each must
be observed RED against the current tree for the right reason (Guard 1: six unclassified raw
confirmation sites — `create.sh` 1, `delete.sh` 1, `set-role.sh` 1, `flip.sh` 3 — plus the
`--confirmed` arm, measured 2026-09-23; the four `provision-{cloudflare,doppler,github}.sh` sites and
the three `worktree-manager.sh` `read -r response` sites are the exempt remainder; Guard 2: piped `yes` reaches mutating stub calls; Guard 3: no defer for
`bash …/flip.sh f prd on`; Guard 4: `create.sh`'s Doppler write outside the window once the source
line is added in a scratch copy).

- 1.1 `plugins/soleur/test/fixtures/operator-ack-arms.tsv` — the arm table (columns: `script`,
  `mode` ∈ {write, readonly}, `argv`, `stub_profile`). One `write` row per write arm (flip.sh: role,
  `--org`, `--detach-shared`; create.sh; delete.sh; set-role.sh; audit-sentry `--apply`;
  provision-hetzner is already driven by `operator-script.test.sh` and is listed with
  `stub_profile=external:operator-script.test.sh`). One `readonly` row per script.
- 1.2 `plugins/soleur/test/operator-ack-guard.test.sh` — Guards 1 and 2.
- 1.3 Extend `.claude/hooks/prod-write-defer-gate.test.sh` — Guard 3 (reads the same arm table).
- 1.4 Extend `plugins/soleur/test/operator-script.test.sh` — Guard 4 (Guard 9 amendment).
- 1.5 `apps/web-platform/test/migration-140-flag-flip-audit-approval-method.test.ts` — mirrors the 071
  test: column + CHECK, 8-arg signature with `DEFAULT NULL`, `SECURITY DEFINER SET search_path =
  public, pg_temp`, REVOKE from `PUBLIC, anon, authenticated`, GRANT to `service_role`, old 7-arg
  function dropped.

### Phase 2 — Contracts first, then the five scripts

Contract-changing edits land before their consumers (sharp edge: phase order is load-bearing when a
contract changes):

- 2.0a Migration 140 (Phase 8.1 content) — the RPC accepts `p_approval_method`.
- 2.0b `plugins/soleur/scripts/audit-flag-flip.sh` helper change (2.11 below) and its
  `audit-flag-flip.test.sh` contract rows.
- 2.0c Guard 9 amendment (Phase 3) — so `operator-script.test.sh` stays green the moment the first
  script sources the library.

Then, for each of `delete.sh`, `create.sh`, `set-role.sh`, `flip.sh`:

- 2.1 `source "$SCRIPT_DIR/../../../scripts/lib/operator-script.sh"` **below** the xtrace refusal
  (Guard 5′ requires the refusal above the `source` line) and next to the existing
  `audit-flag-flip.sh` source.
- 2.2 Early precheck immediately after argv parsing, before `command -v` checks and any Doppler or
  curl call: `if [[ $DRY_RUN -eq 0 ]]; then [[ -t 0 ]] || soleur_op_input_required
  "destructive-write-ack(no-skip-variable-by-design)" ack; fi`. Every non-dry-run arm is gated,
  including `role=dev` arms: `flip.sh <flag> dev on` names the **role** segment, and the script writes
  both Flagsmith environments (dev and prd) regardless; `set-role.sh <user> dev` changes a **prd**
  user's role. There is no dev-only write arm in these scripts, so "production write" and "write"
  coincide here. One arm-table row pins `flip.sh f dev on` as a gated `write` row (user-impact
  finding 6).
- 2.3 Replace the typed-yes block with `soleur_op_ack_or_die "<script-specific prompt naming the
  flag/user, the envs, and 'Type yes'>: "` at the same place (after the preview, before the WORM
  append). Prompts are distinct per site so Guard 2's coverage anchor can observe each one.
- 2.4 `flip.sh`: collapse the two inline copies (detach and org arms) into `gate_or_confirm`, which
  now calls `soleur_op_ack_or_die`; remove `CONFIRMED` and the `--confirmed)` case arm; add a
  `--confirmed)` arm that prints to stderr "`--confirmed` was removed (#8486). Run this command in
  your own terminal without it and type yes at the prompt: bash <path> <argv minus --confirmed>" and
  exits 2 before any other work. Usage lines drop `[--confirmed]`.
- 2.5 Header comments: exit-code tables change "operator aborted" from 0 to 1, add 64
  (`SOLEUR_BOOTSTRAP_INPUT_REQUIRED`) and, for flip.sh, 2 for `--confirmed`.
- 2.6 `umask 077` audit — resolved at deepen time: `create.sh` writes `server.ts` and
  `.env.example` (Python `open(p,'w')`, `create.sh` near its `.env.example` heredoc), and `delete.sh`
  writes `server.ts`, `.env.example` **and `flip.sh`'s own `FLAG_ENV_VARS` map** — all in-place
  overwrites of existing files, none via tmp+`mv`, none creating a new file. `umask` applies only to
  file creation, so modes are unchanged. Keep one test assertion (mode of each written file is
  unchanged after a pty `yes` run) so a future tmp+`mv` refactor cannot silently land 0600.
- 2.7 WORM: no call-site change — the helper supplies `tty-ack` (2.11).

For `audit-sentry-extra-text-references.sh`:

- 2.8 Source the library (repo-relative path) below the xtrace refusal (its `exit 78` block). The
  script defines no `SCRIPT_DIR` today; add `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &&
  pwd)"` and source `"$SCRIPT_DIR/../../../plugins/soleur/scripts/lib/operator-script.sh"`. Its
  `-h|--help)` arm already exits 0 during argv parsing, before the precheck.
- 2.9 After argv parsing: `if (( APPLY )); then [[ -t 0 ]] || soleur_op_input_required
  "destructive-write-ack(no-skip-variable-by-design)" ack; fi`.
- 2.10 After the inventory is printed and before the first PUT: `if (( APPLY && total_matches > 0 ));
  then soleur_op_ack_or_die "Rewrite ${total_matches} Sentry references in production now? Type
  'yes': "; fi`. Read the script's control flow at implementation time to confirm the inventory
  completes before any section's PUT loop; if the PUTs interleave with per-section inventory,
  restructure to inventory-all-then-apply.

`plugins/soleur/scripts/audit-flag-flip.sh`:

- 2.11 The helper always sends `p_approval_method: "tty-ack"` (a literal in the `jq -nc` body; no
  new positional argument). Only the four guarded scripts call it, each after the ack; the migration's
  CHECK constrains the column; a caller that bypasses the helper records NULL. (Plan review,
  simplicity finding 1, mechanical — applied.)

### Phase 3 — Guard 9 amendment (`operator-script.test.sh`)

- 3.1 Widen `DESTRUCTIVE_RE` with the Doppler `secrets delete` verb, `audit_flag_flip_rpc`, and a
  curl/wrapper mutating method token `-X[[:space:]]*(POST|PUT|PATCH|DELETE)` /
  `--request[[:space:]]+(POST|PUT|PATCH|DELETE)`. The widening is load-bearing for one case Guard 2
  cannot see: a library consumer that writes with curl and never calls the ack (Guard 2's population
  is ack callers). Guard 4 row M2 proves it with a fixture consumer, not with a hand-kept count.
- 3.2 A consumer with any site outside the 15-line window is accepted **only** if its path appears
  in `operator-ack-arms.tsv` with at least one `write` row; otherwise RED with
  "gack: <consumer>: writes outside the ack window and no behavioral arm registered".
- 3.3 Guard 4 needs no change for the four flag scripts (their only `read` sites are the prompts
  being deleted); assert that by re-running it.

### Phase 4 — Defer-gate rule

- 4.1 New `DEFAULT_TARGETS` entry `prod-write-defer-operator-ack-script|hr-menu-option-ack-not-prod-write-auth|<ERE>`.
  The ERE matches one of the ack-script path suffixes (`flag-create/scripts/create\.sh`,
  `flag-delete/scripts/delete\.sh`, `user-set-role/scripts/set-role\.sh`,
  `flag-set-role/scripts/flip\.sh`, `provision-hetzner/scripts/provision-hetzner\.sh`,
  `scripts/audit-sentry-extra-text-references\.sh`) wherever it appears as a token — at a command
  boundary (`^`, `&&`, `||`, `;`, `(`), after whitespace, or after a quote — so direct execution (the
  scripts are mode 0755), interpreter words (`bash|sh|exec|source|.`) and PTY wrappers (`script -qec
  "…"`, `yes | script -qc …`, `unbuffer`, `expect`, `python3 -c 'import pty…'`) are all caught. In
  Claude Code a plain invocation already stops at exit 64, so the PTY wrapper is the case this
  backstop exists for (plan review, architecture finding 1, mechanical — applied). A second
  alternation catches `cd <…>/<skill>/scripts && (bash |./)<basename>`. The ERE captures the
  argument tail after the suffix up to the next `;`, `&`, `|` or `)`.
- 4.2 Two escapes, both segment-scoped:
  - Reader escape: the matched segment's first word is a reader verb (`cat`, `less`, `head`, `tail`,
    `grep`, `rg`, `git`, `wc`, `ls`, `stat`, `file`, `diff`, `sed -n`, `shellcheck`, `bash -n`) →
    allow. The list lives beside the rule; a new reader is an ALLOW-side false positive
    (fail-closed direction).
  - Read-only-mode escape against the captured tail (`BASH_REMATCH`), not the whole command. Flag
    scripts: `--dry-run` or `--help`/`-h` in the tail escapes. audit-sentry: the rule matches only
    when `--apply` is in the tail. provision-hetzner: no escape.
  The existing three rules keep whole-command matching; that pre-existing escape is #8662.
- 4.3 Header: document the new rule and why it skips the two-week dry-run expansion gate: after this
  PR no legitimate agent invocation of these scripts exists in write mode (the script refuses it at
  exit 64), so a false-positive defer costs nothing a correct run would have produced.
- 4.4 `.claude/hooks/README.md` §"Starter manifest (3 entries, telemetry-driven expansion)": the
  heading and table become 4 entries (add the new rule's row) plus the same expansion-gate note.
  Grep the README and `DEFER-DECISION-PAYLOAD-SHAPE.md` for any other "3 entries"/"three rules" count
  and update it in the same edit.

### Phase 5 — Per-harness measurement

- 5.1 Record `[[ -t 0 ]]` under each harness installed on the workstation (Claude Code measured
  2026-09-23: `stdin=notty`). For `codex`, `grok` and `devin`, run one headless prompt that executes
  `bash -c '[[ -t 0 ]] && echo stdin=tty || echo stdin=notty'` and, where the harness's exec tool
  exposes a PTY option, a second run requesting it. Also record whether Claude Code's `!`
  bash-mode prefix gives a command a TTY on stdin (`! bash -c '[[ -t 0 ]] && echo stdin=tty || echo
  stdin=notty'`). Only a person can type the `!` prefix, so in a headless run this row is recorded
  UNMEASURED and the SKILL.md keeps "use your own terminal". Budget disclosure: ≤ 6 model calls
  total.
- 5.2 Any harness that can obtain a PTY is recorded in the ADR as "TTY ack is a speed bump in this
  harness (agent can answer the prompt)", not "refuses". Unrunnable harnesses are recorded as
  UNMEASURED, never as covered.

### Phase 6 — ADR, ADR-236 amendment, C4

See `## Architecture Decision (ADR/C4)`.

### Phase 7 — Skills, docs, and other model-read surfaces

- 7.1 `flag-create`, `flag-delete`, `user-set-role`, `flag-set-role` SKILL.md bodies (no
  `description:` edits): the agent runs `--dry-run`, shows the preview, then prints the exact write
  command in a fenced block for the operator's own terminal (Warp) and does not run it. Explain the
  exit-64 marker. Remove every `--confirmed` mention and the AskUserQuestion-then-apply flow in
  flag-set-role. Update exit-code tables. Three handoff requirements (deepen-plan, user-impact
  findings 1, 4, 5):
  - **Absolute, worktree-pinned command.** The printed command is `cd <absolute worktree path> &&
    bash <absolute script path> <argv>`, never a `${CLAUDE_PLUGIN_ROOT}`-relative or repo-relative
    form: `create.sh`/`delete.sh` also edit repo files, and an operator running from the main
    checkout or another worktree would land the code wiring in the wrong tree while Flagsmith and
    Doppler change.
  - **Blocking operator step.** The handoff is an undone operator step under
    `wg-block-pr-ready-on-undeferred-operator-steps`: the agent does not treat the printed command as
    done, records it where the pipeline tracks operator steps, and PR-ready waits on it. Exit 64 is
    never a success.
  - **Incident rollback block (flag-set-role).** A short section that gives the rollback write
    command at once (no dry-run first), says to run it in the operator's own terminal (Warp) — not
    via Claude Code's `!` prefix (whether it gives the command a TTY is unmeasured; Phase 5
    records it) — and names the Flagsmith dashboard as the break-glass when the audit append exits 4 (the dashboard is already a named residual in the ADR;
    a dashboard write leaves no WORM row, so the section says to record it afterwards).
- 7.2 `oauth-probe-failure.md` runbook: the `--apply` invocations are for the operator's terminal;
  the default inventory stays agent-runnable.
- 7.2a `plugins/soleur/commands/go.md` §Operator-typed tooling (ADR-236) currently says
  `soleur:flag-create`/`soleur:flag-set-role` "stay model-invocable" and are Skill-tool-invokable
  directly. Add that the agent runs only their `--dry-run` and hands off the write command, the same
  "reply with the exact command, never run it" rule it already states for `flag-delete` and
  `user-set-role`.
- 7.3 Sweep: `git grep -nF -- '--confirmed'` and `git grep -nE 'flag-(create|delete|set-role)|user-set-role'`
  across model-read surfaces (skills, commands incl. `commands/go.md` §Operator-typed tooling,
  agents, `AGENTS.rules.md`, runbooks). Every instruction that has the agent perform a write must
  become a printed-command handoff. Exclusions: `knowledge-base/project/{plans,specs,brainstorms,learnings}/`
  (point-in-time records) and `knowledge-base/product/competitive-intelligence.md` (issue title quote).
- 7.4 `plugins/soleur/test/components.test.ts` `MUST_STAY_INVOCABLE` reason strings for
  `flag-create` and `flag-set-role`: drop the `--confirmed` rationale; the skills stay invocable
  because the agent runs `--dry-run` and hands off the printed command.
- 7.5 Run `plugins/soleur/test/invocation-axis.test.ts` (ADR-236 Guard 1): `flag-delete` and
  `user-set-role` are user-invoked, so any new mention of them in a model-read file needs an ack-table
  row.
- 7.6 Plans are data a later session executes (learning
  `2026-09-21-the-flip-was-checked-against-every-surface-except-the-plans-that-prescribe-it.md`):
  `git grep -lE 'flip\.sh[^`]*--confirmed|soleur:flag-(create|set-role)|flag-create/scripts/create\.sh' -- 'knowledge-base/project/plans/*.md' 'knowledge-base/project/specs/*/tasks.md'`
  returned 24 non-archived files at plan time (4 carry `flip.sh … --confirmed`). For each whose
  linked issue or PR is still open, list it in the PR body as "agent flag-write step becomes a
  printed-command handoff". Point-in-time plans are not edited; the skills' new handoff text governs
  what an executing agent does.

### Phase 8 — Migration and legal record

- 8.1 `apps/web-platform/supabase/migrations/140_flag_flip_audit_approval_method.sql` (+ `.down.sql`).
  The ordinal is provisional (free across every `origin/*` ref on 2026-09-23); re-probe across all
  refs before merge. Down, in this order: `DROP FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text,text)`
  first, then recreate the 7-arg function with its REVOKE/GRANT, then drop the column (destroys
  `approval_method` values — state it in a header comment). Recreating the 7-arg function while the
  8-arg `DEFAULT NULL` one exists makes every 7-key call ambiguous ("function … is not unique") and
  every flag write exit 4 (plan review, architecture finding 2, mechanical — applied). The migration
  test asserts this order in the `.down.sql` and that only the last parameter has a default.
  **Rollback order (user-impact finding 2):** the helper change (always sending
  `p_approval_method`) must be reverted, and that revert must reach the operator's installed plugin
  copy, BEFORE `.down.sql` runs — otherwise every new-helper call hits a function that no longer
  accepts the key and exits 4 before any write. The `.down.sql` header and the ADR state this order.
- 8.1a Precedent (deepen-plan 4.4): `137_byok_cap_breach_audit_row.sql` is the same shape — inside
  `BEGIN; … COMMIT;`, `ALTER TABLE <audit table> ADD COLUMN …`, `DROP FUNCTION IF EXISTS <old
  signature>`, `CREATE FUNCTION … SECURITY DEFINER SET search_path = public, pg_temp`, then
  `REVOKE ALL … FROM PUBLIC, anon, authenticated` and `GRANT EXECUTE … TO service_role` on the new
  signature. Mirror it; `run-migrations.sh` already calls `postgrest-reload-schema.sh` after applying,
  so the new RPC signature is visible without a manual reload. Downtime gate (deepen-plan 4.55) does
  not fire: the column is nullable with no default (no table rewrite), `flag_flip_audit` is a small,
  cold, append-only table, and the inline CHECK validates only NULLs.
- 8.2 Deploy ordering (answered at plan time — architecture finding 3): the scripts write the audit
  row to Doppler `soleur/dev`'s Supabase, and `.github/workflows/tenant-integration.yml` applies
  unmerged migrations to the shared dev project during PR CI, so `dev` has the 8-arg function before
  merge; prd gets it from `web-platform-release.yml`'s migrate job. Callers that still send seven
  keys (main and other worktrees) keep working through PostgREST named arguments plus `DEFAULT NULL`.
  The only deploy risk was the down-migration order above.
- 8.3 `knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md` and
  `knowledge-base/legal/article-30-register.md`: resolved at deepen time — the LIA's
  data-minimisation list carries a per-field bullet ("**Actor field:** operator email only …"), so add
  one sibling bullet "**Approval-method field:** `tty-ack` or NULL; non-personal; records how the write
  was approved (ADR-245)". The Article 30 register has no `flag_flip_audit` entry; no change there.

## Files to Create

- `plugins/soleur/test/operator-ack-guard.test.sh`
- `plugins/soleur/test/fixtures/operator-ack-arms.tsv`
- `apps/web-platform/supabase/migrations/140_flag_flip_audit_approval_method.sql`
- `apps/web-platform/supabase/migrations/140_flag_flip_audit_approval_method.down.sql`
- `apps/web-platform/test/migration-140-flag-flip-audit-approval-method.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-245-operator-prod-writes-need-a-tty-ack-layered-with-credential-custody.md`

## Files to Edit

- `plugins/soleur/skills/flag-delete/scripts/delete.sh`
- `plugins/soleur/skills/flag-create/scripts/create.sh`
- `plugins/soleur/skills/user-set-role/scripts/set-role.sh`
- `plugins/soleur/skills/flag-set-role/scripts/flip.sh`
- `apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
- `plugins/soleur/scripts/audit-flag-flip.sh`
- `plugins/soleur/skills/{flag-delete,flag-create,user-set-role,flag-set-role}/SKILL.md` (bodies only)
- `plugins/soleur/test/operator-script.test.sh` (Guard 9)
- `plugins/soleur/test/flag-detach-shared.test.sh`, `plugins/soleur/test/flag-org-scoping-pr2.test.sh`
  (drive writes through `script -qec` with `yes` on the pty instead of `--confirmed`; add one
  `--confirmed` → exit 2 case)
- `plugins/soleur/test/audit-flag-flip.test.sh` (body carries `p_approval_method: "tty-ack"`)
- `plugins/soleur/test/components.test.ts`
- `.claude/hooks/prod-write-defer-gate.sh`, `.claude/hooks/prod-write-defer-gate.test.sh`,
  `.claude/hooks/README.md`
- `knowledge-base/engineering/architecture/decisions/ADR-236-human-only-skills-are-user-invoked.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`
- `knowledge-base/engineering/operations/runbooks/oauth-probe-failure.md`
- `plugins/soleur/commands/go.md` (§Operator-typed tooling, Phase 7.2a)
- `knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md` (one data-minimisation bullet, 8.3)
- Conditional (7.3): any model-read surface the sweep finds

## Open Code-Review Overlap

1 open scope-out touches these files: #8593 (probe gate window narrower than the silent-truncation
property — `components.test.ts`). **Acknowledge:** different concern (a probe window in another
test block); this plan edits only the `MUST_STAY_INVOCABLE` reason strings. The scope-out stays open.

## Guard Contract

All guards are written before the code they guard (Phase 1) and each is observed RED on the current
tree for its named reason before the fix lands.

### Guard 1 — typed-yes census (no unclassified raw confirmation gate)

**Property.** No tracked shell script outside `plugins/soleur/scripts/lib/operator-script.sh` asks
for a human confirmation through a raw prompt or offers a flag that skips one, unless it is a
classified exemption.

**Assembly.** Population is DISCOVERED from `git ls-files '*.sh'` minus `*.test.sh`, `*/test/*`,
`*/fixtures/*`, the library itself, and — the same exclusions as Guard 2 — the
`operator-bootstrap/template.sh` and `knowledge-base/**` generated bootstraps (plan review,
architecture finding 4, mechanical — applied). Phase 1 runs both detectors on the live tree and lists
every hit with its handling before the exemption registry is frozen; a rough "compares something to
yes" grep returns 18 files, most comparing a variable that `read` never filled, which is why detector
(a) tracks the read variable. Two detectors run over each member's comment-stripped text:
(a) a `read` site (the library's `READ_SITE_RE` shape, including `IFS= read` and `read reply`) whose
prompt text mentions `yes`/`y/N`, or whose read variable is later compared to `y` or `yes` in any
case (`== "yes"`, `!= "y"`, `Type 'yes'`); (b) a `case` arm label among `--confirmed`, `--yes`, `-y`,
`--assume-yes`, `--no-confirm`, `--no-prompt`. Exemption registry: an inline array in the test naming
`provision-cloudflare.sh`, `provision-doppler.sh`, `provision-github.sh` (class-3 attest barriers
followed by independent verification; brainstorm Non-Goals) and `git-worktree/scripts/worktree-manager.sh`
(local worktree cleanup; no production write), each with a reason. Plan-time census (2026-09-23): 13 detector-(a)
sites in 8 files (6 non-exempt, 7 exempt) plus 1 detector-(b) arm; after the change the non-exempt
count is 0. The work phase re-derives both numbers with the test's own detector before relying on
them. Also asserted: zero
`--confirmed` tokens in `plugins/soleur/skills/*/SKILL.md` and `plugins/soleur/skills/*/scripts/*.sh`.

**Mutation matrix.**

| # | Edit (to the system under test) | Expected |
|---|---|---|
| M1 | Re-add `read -p "Proceed? Type 'yes': " ACK` + `[[ "$ACK" == "yes" ]]` to a copy of `delete.sh` | RED (unclassified typed-yes site) |
| M2 | Re-add `--confirmed) CONFIRMED=1; shift ;;` to a copy of `flip.sh` | RED (confirm-skip flag) |
| M3 | Own dispatch: point the population walk at an empty tree | RED ("census scanned 0 files") |
| M4 | Second member after a compliant first: add a raw typed-yes to a NEW script under `apps/web-platform/scripts/` in a fixture tree that also contains a clean script | RED naming the new file |
| M5 | Precondition holds, property fails: prompt shaped `IFS= read -r ans` preceded by `printf 'Type yes: '` (no `-p`) | RED (detector (a) keys on the comparison, not only on `-p`) |
| M6 | Exemption registry names a file that no longer exists (rename `provision-github.sh` in the fixture) | RED (stale exemption; set identity both ways) |
| M7 | Add `--confirmed` back into `flag-set-role/SKILL.md` | RED |

**Harness rows.** H1: replace the test's comment-stripping helper with `cat` so a commented-out
`# read -p "Type 'yes'"` is scanned → must go RED on the pristine tree (proves the stripper is
load-bearing). H2 (must-PASS, not the canonical): a script that compares `[[ "$x" == "yes" ]]` on a
variable assigned from a function return, not from `read` (e.g. `generate-apex-rollback-pr.sh`-shaped
`with=yes`) → PASS. H3 (must-PASS): a script whose `-y` appears only inside a `curl` or `apt-get`
argv, not as a `case` label → PASS.

**Anchor.** The exemption registry lives in the test file next to the census; a PR that edits both
the registry and a script is visible as one diff. Set identity (every exemption names a live census
member, every census member is exempt or absent) replaces a count floor.

### Guard 2 — behavioral: no mutating call without a person at a TTY

**Property.** For every write arm of every script that calls `soleur_op_ack_or_die`, a run without
a TTY on stdin makes zero network or credential calls and exits 64; a run on a pty answered anything
but `yes` makes zero mutating calls and exits 1; a read-only run without a TTY makes zero mutating
calls and exits 0.

**Assembly.** Population is DISCOVERED: `git grep -l 'soleur_op_ack_or_die'` over tracked `*.sh`,
minus the library, `*.test.sh`, the `operator-bootstrap/template.sh` (copied, never run) and
`knowledge-base/**` (generated per-feature bootstraps). Set identity with the arm table's `script`
column, both ways. Every run uses a sandbox PATH containing ONLY the stub dir plus symlinks to the
coreutils the scripts need (measured at deepen time: `dirname`, `grep`, `printf`, `python3`,
`sed`, `sleep`, `tail`, `tr` across the four flag scripts; `jq` for the audit helper; audit-sentry's
set is derived the same way — the suite derives the list with a grep over each script rather than
hard-coding it, and a missing tool shows up as `command not found`, never as a silent pass); `curl` and `doppler` are stubs that append their full argv to a log. Any other
network binary is absent, so an unstubbed writer fails loudly instead of escaping the log. A call is
MUTATING when the curl argv carries `-X`/`--request` POST, PUT, PATCH or DELETE (or `-d`/`--data*`
without `-X GET`), or the doppler argv is `secrets set|delete|upload`. Pty runs use `script -qec` with
the answer on its stdin (the library suite's existing idiom). Coverage anchor: the prompt string of
every `soleur_op_ack_or_die` call site (grep-derived from the source) must appear in at least one pty
run's output. **Tree isolation (deepen-plan):** `create.sh` and `delete.sh` overwrite `server.ts` and
`.env.example` in place, and `delete.sh` also rewrites `flip.sh`'s `FLAG_ENV_VARS` map, so every
pty-`yes` run executes against a scratch copy of the repo-relative files the script reads and writes
(same relative layout under a `mktemp -d` root), and the suite asserts `git status --porcelain` on
the real worktree is unchanged after the run.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Delete the early precheck from `create.sh` | RED (no-TTY run shows Doppler `secrets get` / GET calls before exit 64) |
| M2 | Delete `soleur_op_ack_or_die` from `gate_or_confirm` in `flip.sh` (precheck kept) | RED (pty+`no` run shows mutating calls) |
| M3 | Move the ack in `delete.sh` from before the WORM append to after the first Flagsmith DELETE (REORDER row: the ack still runs, but after a write) | RED (pty+`no` run logs one mutating call before exit 1) |
| M4 | Second member after a compliant first: add an ack-calling script under `apps/web-platform/scripts/` with no arm-table row | RED (set identity) |
| M5 | Precondition holds, property fails: `set-role.sh` keeps both checks but adds `ACK=${SOLEUR_ACK:-}` / `[[ -n $ACK ]] && skip` before them | RED (no-TTY run with `SOLEUR_ACK=yes` in env reaches mutating calls; the arm table sets every `SOLEUR_*`/`*_ACK*` env var the script mentions) |
| M6 | Own dispatch: arm table empty | RED ("0 arms run") |
| M7 | Change one ack prompt string so no arm reaches it (e.g. put it on an arm the table lacks) | RED (coverage anchor: prompt never observed) |

**Harness rows.** H1 (suite edit): make the curl stub stop logging → pty+`yes` positive control must
go RED ("positive control observed 0 mutating calls"), proving the log is read. H2 (suite edit): run
the no-TTY arms on a pty instead → the exit-64 assertion must go RED. H3 (must-PASS, not canonical):
`--dry-run` passed in a different argv position the parser accepts (`flip.sh --dry-run f prd on`) →
exit 0, zero mutating calls. H4 (must-PASS): pty answered `yes` reaches ≥ 1 mutating call per write
arm and the WORM body carries `"p_approval_method":"tty-ack"`.

**Anchor.** The population is grep-derived from the scripts; the arm table cannot shrink without
set identity failing, and the prompt-coverage anchor is derived from the scripts' own call sites, so
a diff that weakens a script and its arm row together still fails M7-class coverage unless it also
deletes the ack call (which M2/M3 catch behaviorally).

### Guard 3 — defer-gate rule (Claude Code backstop)

**Property.** In Claude Code, a Bash command that executes any ack-calling operator script in write
mode is deferred; a read-only invocation of the same script, and any command that merely names the
path, is allowed.

**Assembly.** The rule is one `DEFAULT_TARGETS` entry plus a segment-scoped read-only escape. Its
population is pinned to Guard 2's derived population: the test reads `operator-ack-arms.tsv`,
asserts set identity with the grep-derived ack callers (same exclusions), and for every row builds
invocations in each shape — `bash <abs path> <argv>`, `bash "${CLAUDE_PLUGIN_ROOT}/<rel>" <argv>`,
bare `<rel path> <argv>`, `cd <…>/scripts && ./<basename> <argv>`, `doppler run -p soleur -c prd --
bash <path> <argv>`, `bash -c '… bash <path> <argv>'`, `script -qec "bash <path> <argv>" /dev/null`,
`yes | script -qc "<path> <argv>"` — asserting DEFER for `write` rows and ALLOW for `readonly` rows.

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Drop `flag-set-role/scripts/flip\.sh` from the ERE alternation | RED (set identity + flip write row allowed) |
| M2 | Evaluate the read-only escape against the whole command again (revert 4.2) | RED on `bash …/delete.sh f; echo --dry-run` (must DEFER) |
| M3 | Second member after a compliant first: new ack-calling script added to the tree with no ERE suffix | RED |
| M4 | Precondition holds, property fails: `--dry-run` inside a quoted `--description "--dry-run"` value for create.sh | expected verdict DEFER; the test records the chosen tokenisation and goes RED if the escape fires |
| M5 | audit-sentry rule loses its `--apply` requirement (defers default inventory) | RED (readonly row must ALLOW) |
| M6 | Own dispatch: arm table unreadable | RED (the test fails closed, it does not report 0 cases) |
| M7 | Restrict the ERE to interpreter-prefixed forms only (the first draft's shape) | RED on `script -qec "…/flip.sh f prd on"` and on bare `…/flip.sh f prd on` (must DEFER) |

**Harness rows.** H1 (suite edit): assert on `{}` instead of the defer envelope → pristine tree goes
RED. H2 (must-PASS): `cat plugins/soleur/skills/flag-set-role/scripts/flip.sh`, `git log --
…/flip.sh` and `grep -n ack …/delete.sh` → ALLOW (reader escape).

**Anchor.** The ERE and the arm table live in different files (`.claude/hooks/` vs
`plugins/soleur/test/fixtures/`); the grep-derived population is the third leg, owned by neither.

### Guard 4 — `operator-script.test.sh` Guard 9 (gack) amendment

**Property.** In every consumer of the operator-script library, each destructive write is either
within the 15-line ack window or belongs to a consumer whose write arms are proven behaviorally by
Guard 2.

**Assembly.** `g3_sourcing_scripts` (discovered, plugin root) → comment-stripped `DESTRUCTIVE_RE`
sites (widened in 3.1) → window check → fallback lookup in `operator-ack-arms.tsv` (`write` rows).

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| M1 | Remove `create.sh`'s rows from the arm table | RED (Doppler write outside window, unregistered) |
| M2 | Revert `DESTRUCTIVE_RE` widening; add a consumer whose only write is `fs_api -X DELETE` with no ack | RED once widened; GREEN-before proves the widening is load-bearing |
| M3 | Existing rows gack-r1/gack-r2 (hetzner ack deleted / commented) | RED (unchanged — hetzner is window-covered, no arm-table escape) |
| M4 | Own dispatch: zero consumers | RED (existing row) |
| M5 | A consumer registered in the arm table with only a `readonly` row | RED (fallback requires a `write` row) |

**Harness rows.** H1 (suite edit): make the fallback lookup read an empty arm table → the live tree
must go RED on `create.sh` and `flip.sh` (proves the fallback, not the window, is what accepts them).
H2 (must-PASS): `provision-hetzner.sh` passes via the window path, not the arm-table fallback (assert
which path accepted it).

**Anchor.** The fallback is only as strong as Guard 2; Guard 4 reads the same arm table Guard 2 must
satisfy by set identity against the grep-derived population.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-245 (provisional ordinal; `origin/main` max is ADR-244 as of 2026-09-23 — re-verify at
ship)** via `soleur:architecture`: "Production-writing operator scripts require a TTY acknowledgement;
hijacked-agent resistance needs credential custody." Status `accepted` for step 1, with a
`### Step 2 (adopting, #8652)` section. Contents:

- Decision D1–D7 from the brainstorm, with the guard set's derivation (Guards 1–2) and the
  `audit-sentry` inclusion.
- **Per-harness coverage table** (rows: Claude Code, Grok Build, Codex, Devin local, Devin cloud;
  columns: TTY ack — measured/unmeasured and result; defer gate — registered?; evidence). Seeds:
  Claude Code `stdin=notty` measured 2026-09-23; `.grok/config.toml` and `.codex/config.toml`
  register no defer hook; `devin-dispositions.tsv` marks defer UNMEASURED under Devin; Devin cloud
  runs no hooks. Phase 5 fills the rest.
- **What `approval_method = 'tty-ack'` means:** the script's TTY gate returned — self-reported, not
  proof that a person typed (D6).
- **Residual risks, named:** `script -qc`/any PTY an agent can allocate (including a harness exec
  tool with a PTY option); direct `curl` with the Doppler owner token (skips scripts and the WORM
  row); the Flagsmith and Supabase dashboards via shared browser cookies; a blind FIDO2 touch
  (step 2); the ungated local prod-writer census (#8661); a defer-rule path miss for a basename-only
  invocation whose `cd` happened in an earlier Bash call; the existing rules' whole-command read-only
  escape (#8662). Full closure: agents on a separate OS user.
- **Coverage notes (plan review, architecture findings 7–8):** every refused agent attempt appends a
  `run_halt` line to `bootstrap-runs.jsonl` beside the script (the plugin install directory for the
  skills, `apps/web-platform/scripts/` for audit-sentry) — a ledger designed for ADR-228 generated
  bootstraps, covered by the global `.gitignore` pattern. `audit-sentry-extra-text-references.sh`
  sourcing `plugins/soleur/scripts/lib/operator-script.sh` is the first `apps/` → plugin-internals
  dependency; it inherits `umask 077` and the library's exports, and because it sits outside the
  plugin root it is covered by Guard 2 only (not by Guards 3, 5′ or 9).
- **Step 2 design (#8652):** main-only workflow broker holding rotated keys, FIDO2 `sk` touch over a
  broker nonce plus an operation digest, evidence written into the audit row (widening the
  `approval_method` CHECK).
- **Alternatives considered:** UserPromptSubmit marker hook, nonce, `hookify` (D4 reasons);
  per-script typed-yes hardening (rejected: stdin is the agent's).
- Consequences: plan-prescribed `flag-create`/`flag-set-role` steps become printed-command handoffs;
  abort exit code 0 → 1.

**Amend ADR-236:** the `flag-set-role` K1 row and the `flag-create` rationale drop `--confirmed`;
§Decision 4's "tracked in #8486" becomes "closed for the accidental agent by ADR-245; hijacked agent
→ #8652". Add ADR-245 to its related links.

### C4 views

Read in full at plan time: `model.c4` (840 lines), `views.c4` (106), `spec.c4` (54). Enumeration:

- (a) External human actor: `founder` ("Founder / Operator") — modeled; description unchanged (it
  already covers the operator role).
- (b) External systems: **Flagsmith — NOT modeled** (no element, no edge; `grep -i flag` finds none).
  Doppler (`doppler`), Sentry (`sentry`) and Supabase (`supabase` database) — modeled.
- (c) Containers: `hooks` ("Hook Engine") — modeled; the defer gate is one of its hooks, no new edge.
  The WORM table lives in `supabase` — modeled.
- (d) Access relationships that change: production flag and role writes are now reachable only from
  the founder's own terminal.

Tasks: add `flagsmith = system "Flagsmith" { #external … }` to `model.c4`; edges `founder -> flagsmith
"Production flag and segment writes via the flag-* operator scripts, gated on a TTY ack in the
founder's own terminal (ADR-245)"` and `webapp -> flagsmith "Evaluates runtime flags"` (the existing
read path, unmodeled today); include `flagsmith` in the `context` view in `views.c4`. Run
`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
`plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

Step 1 is true at merge. The step-2 section is authored now with status `adopting`; it is not a
separate ADR.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_BOOTSTRAP_INPUT_REQUIRED marker on stdout from a no-TTY write-mode run; defer_requested rows from prod-write-defer-gate in .claude/logs/incidents.jsonl
  cadence: per invocation (event-driven; these scripts run a few times a month)
  alert_target: the invoking agent/operator terminal (marker) and the weekly rule-metrics aggregate (defer rows)
  configured_in: plugins/soleur/scripts/lib/operator-script.sh (soleur_op_input_required); .claude/hooks/prod-write-defer-gate.sh (emit_incident)
error_reporting:
  destination: stdout marker + bootstrap-runs.jsonl run_halt line beside the script; WORM RPC failures exit 4 with a FATAL line on stderr before any mutation
  fail_loud: true
failure_modes:
  - mode: agent pipes yes or runs a write arm with no TTY
    detection: exit 64 plus SOLEUR_BOOTSTRAP_INPUT_REQUIRED on stdout, emitted before any Doppler or curl call (Guard 2 M1)
    alert_route: agent transcript; the SKILL.md tells the agent to hand the printed command to the operator
  - mode: flip.sh --confirmed reintroduced by a caller
    detection: exit 2 with the removal message; Guard 1 census RED in CI
    alert_route: CI failure on the PR
  - mode: approval_method RPC parameter missing on the audit DB (migration not yet applied)
    detection: audit RPC non-2xx -> exit 4 FATAL before any mutation
    alert_route: operator terminal; PR body states the window (Phase 8.2)
  - mode: down migration applied while the installed helper still sends p_approval_method
    detection: audit RPC non-2xx -> exit 4 FATAL before any mutation, on every flag write
    alert_route: operator terminal; rollback order in the .down.sql header and ADR (helper revert first); Flagsmith dashboard break-glass per the flag-set-role incident block
  - mode: pipeline treats a printed handoff command as done
    detection: exit 64 marker in the transcript; the handoff is recorded as an undone operator step (wg-block-pr-ready-on-undeferred-operator-steps)
    alert_route: PR-ready blocked until the operator step is closed
  - mode: defer rule misses a path shape
    detection: Guard 3 shape matrix in CI; at runtime the TTY ack still refuses (exit 64)
    alert_route: CI failure; runtime marker
logs:
  where: stdout/stderr of the invocation; bootstrap-runs.jsonl beside each script (gitignored); .claude/logs/incidents.jsonl and approvals.jsonl for the hook
  retention: ledger files are local and unrotated; hook logs 1-year TTL via rotate_if_needed
discoverability_test:
  command: bash plugins/soleur/skills/flag-delete/scripts/delete.sh probe-flag
  expected_output: "SOLEUR_BOOTSTRAP_INPUT_REQUIRED"
```

The probe works because the precheck (2.2) runs right after argv parsing, before `command -v doppler`
and before any file lookup of the flag name; in preflight's sandbox stdin is not a TTY, so the
marker prints and the script exits 64 with no credentials and no network. A ledger write failure in
the read-only sandbox prints `SOLEUR_BOOTSTRAP_LEDGER_WRITE_FAILED` and is non-fatal.

## Encryption Posture

No new persistent store and no new cross-component connection. The migration path trigger fires
because migration 140 adds one column to an existing table; the inherited posture is declared.

```yaml
at_rest:
  - store: public.flag_flip_audit on the Supabase project behind Doppler soleur/dev SUPABASE_URL (and the same migration on prd)
    mechanism: vendor-managed-storage-encryption
    evidence: >-
      knowledge-base/legal/article-30-register.md TOMs row records "(2) Encryption at rest at storage
      layer (Supabase managed)". No Supabase DPA file exists under
      knowledge-base/legal/data-processing-agreements/ (present: anthropic, flagsmith, openai), so the
      in-repo evidence is the register line, not a named attestation document.
    defends_against: loss or re-use of the vendor's physical storage media
    does_not_defend: >-
      anyone holding the service-role key (the operator's Doppler owner token reads it — D2), a vendor
      operator, or lawful access to the vendor. The new column adds no personal data.
    disclosed_as: Article 30 register entry for the flag-flip audit (updated only if it enumerates columns, Phase 8.3)
    live_verification: none added by this change
in_transit:
  - connection: operator workstation -> Supabase PostgREST (audit RPC), existing
    tls: HTTPS
    cert_verification: on
    does_not_defend: a compromised workstation or agent process holding the service-role key
    disclosed_as: unchanged
```

## User-Brand Impact

**If this lands broken, the user experiences:** a feature silently turned off for their workspace,
unreleased features exposed to them or to a user wrongly promoted to `dev`, or a production Sentry
alert rule rewritten so their incident is never paged — each caused by an agent that piped `yes`
(or passed `--confirmed`) into `flip.sh`, `create.sh`, `delete.sh`, `set-role.sh` or
`audit-sentry … --apply`, with the WORM audit row attributing the change to the operator. The
inverse failure is the operator unable to run a needed rollback flip because the ack refuses a real
terminal (Guard 2 H4, AC14 and the flag-set-role incident block cover it). A new failure this change
introduces: a pipeline that prescribes an agent flag write gets exit 64 and ships code whose safety
depends on a flag state nobody set (a feature meant to stay dev-only, an unflipped kill-switch) —
covered by making the handoff a blocking operator step (Phase 7.1, AC15).

**If this leaks, the user's workflow and data are exposed via:** a role promotion to `dev` that
exposes unreleased, possibly unfinished features, or a per-org segment detach that changes which
tenants see a feature — both reachable with the operator's Doppler-held Flagsmith key and prd
service-role key, which the agent can read (D2).

**Brand-survival threshold:** single-user incident.

CPO sign-off: required at plan time (`requires_cpo_signoff: true`). The Product assessment in the
brainstorm (§Domain Assessments → Product) framed the blast radius and accepted the TTY friction
(about 11 uses in 3 months); headless run — the sign-off is carried forward from that assessment and
must be confirmed before `soleur:work`. `soleur:engineering:review:user-impact-reviewer` runs at
review (TR5).

## Acceptance Criteria

- [ ] AC1 — Guard 1 census passes on the final tree, and each of its mutation rows M1–M7 and harness
      rows H1–H3 is exercised in `operator-ack-guard.test.sh` with the expected verdict.
- [ ] AC2 — For each `write` row in `operator-ack-arms.tsv`: `printf 'yes\n' | bash <script> <argv>`
      (sandbox PATH) exits 64, prints `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`, and the stub log is empty.
- [ ] AC3 — `flip.sh … --confirmed` exits 2 with a message containing "own terminal", stub log empty.
- [ ] AC4 — Each `readonly` row exits 0 without a TTY with zero mutating stub calls.
- [ ] AC5 — Pty `no` → exit 1, zero mutating calls; pty `yes` → ≥ 1 mutating call and the audit body
      carries `"p_approval_method":"tty-ack"` (flag scripts). Every ack prompt string is observed.
- [ ] AC6 — Guard 3: every arm-table row × eight invocation shapes (including `script -qec "…"`,
      `yes | script -qc …`, bare path and `cd … && ./<basename>`) gives DEFER (write) / ALLOW
      (readonly); `bash …/delete.sh f; echo --dry-run` DEFERs; `cat …/flip.sh` ALLOWs.
- [ ] AC7 — Guard 9 amended; `bash plugins/soleur/test/operator-script.test.sh` green, including
      Guard 4 rows M1–M5 and H1–H2.
- [ ] AC8 — `git grep -nF -- '--confirmed' -- 'plugins/soleur/skills/*' '.claude/*' 'plugins/soleur/commands/*'`
      returns nothing.
- [ ] AC9 — Migration 140 test green; `071` test unchanged and green.
- [ ] AC10 — `ADR-245-*.md` exists (or its renumbered successor, with every plan/tasks/AC mention
      swept), contains the per-harness table with a measured/UNMEASURED cell per row, the named
      residual risks, and #8661 and #8662; ADR-236 amended.
- [ ] AC11 — `model.c4` has `flagsmith` with both edges and it renders in `context`; C4 syntax,
      render and count-parity tests green.
- [ ] AC12 — `bash scripts/test-all.sh` green for the groups containing the touched suites;
      `invocation-axis.test.ts` and `components.test.ts` green.
- [ ] AC13 — #8661 and #8662 are linked from the ADR and the PR body.
- [ ] AC14 — For each of the four SKILL.md files, the fenced write command it tells the agent to
      print (extracted by the test, not retyped) starts with `cd <absolute path> &&`, and, run under
      `script -qec` with stub PATH and `no` on the pty, reaches its ack prompt and exits 1 with zero
      mutating calls (proves the printed form works in a real terminal).
- [ ] AC15 — `flag-set-role/SKILL.md` has the incident-rollback block (write command without
      dry-run, own terminal not `!`, dashboard break-glass on exit 4); each of the four SKILL.md files
      names `wg-block-pr-ready-on-undeferred-operator-steps` for the handoff.
- [ ] AC16 (pre-merge, after tenant-integration CI applies migration 140 to the shared dev project) —
      a read-only probe of dev PostgREST's OpenAPI document
      (`GET <dev SUPABASE_URL>/rest/v1/` with the service-role key) lists `rpc/audit_flag_flip` with a
      `p_approval_method` parameter; output recorded in the PR body. Do not call the RPC to test it:
      every call writes a permanent WORM row.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm's
`## Domain Assessments`; Marketing, Sales, Finance, Operations, Support assessed there as not
relevant).

### Engineering

**Status:** reviewed (brainstorm carry-forward, CTO)
**Assessment:** Premise measured — the Doppler owner token reads every prod-write key, so in-script
checks are speed bumps against the accidental agent. Step 1 reuses the class-2 ack and the defer-gate
pattern; step 2 needs a broker that holds the credentials. Plan-time additions: Guard 9 interaction,
the harness PTY question, and the Flagsmith C4 gap.

### Legal

**Status:** reviewed (brainstorm carry-forward, CLO)
**Assessment:** Role changes are access control (GDPR Art. 5(2), 32(1)(b)); record the approval
method, not just the key owner. Step 1 records `tty-ack` honestly as self-reported; step 2 brings
unforgeable evidence. Plan adds the LIA / Article 30 check (8.3). `soleur:gdpr-gate` was not invoked
as a skill in this headless, rate-limited run; its triggers here (single-user-incident threshold; a
column on a table holding operator emails) are carried to review (TR5), where security-sentinel and
the review panel run.

### Product/UX Gate

**Tier:** none — no UI surface in Files to Create/Edit (mechanical override did not fire).
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

Brainstorm Product assessment: only Soleur's operator uses these scripts, rarely; the TTY step's
friction is acceptable. Real harms are a feature vanishing for a tenant and unreleased features being
exposed.

## Plan Review

Reduced panel under the session's API rate budget (the single-user-incident panel is five seats;
two ran): `soleur:engineering:review:architecture-strategist` (also serving as the Step 4.5
strong-model consult on the riskiest phase, Guard 4) and
`soleur:engineering:review:code-simplicity-reviewer`. DHH, Kieran and spec-flow-analyzer did not run;
`soleur:deepen-plan` and the TR5 review panel follow.

Applied (mechanical): defer ERE catches bare-path, PTY-wrapper and `cd && ./` shapes, with a reader
escape (Phase 4.1–4.2, Guard 3 M7, AC6); down-migration order (8.1); deploy ordering answered (8.2);
Guard 1 exclusions aligned with Guard 2 and measured before the registry freezes; helper sends a
`tty-ack` literal instead of a new positional argument (2.11); Guard 4's hand-kept site count
replaced by a fixture row. Pre-existing whole-command escape filed as #8662.

Surfaced, not applied (taste): T-1 … T-9 in
`knowledge-base/project/specs/feat-8486-human-presence-guard/decision-challenges.md`.

## Test Scenarios

Covered by Guards 1–4 and AC1–AC12. Additional: `set-role.sh` with `--dry-run` in position 3 runs
without a TTY (its positional parser); `audit-sentry` with `--apply` and zero matches exits 0 on a
pty without prompting; `create.sh`/`delete.sh` file writes keep their pre-change mode under the
library's `umask 077` (2.6).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Sourcing the library runs `umask 077` and sets `SOLEUR_OP_LIB_API=1` in the caller; the double-source
  guard means `audit-flag-flip.sh` must not source it too.
- `soleur_op_input_required` prints to stdout; tests that capture stderr only will miss the marker.
- `script -qec` in the tests is the same PTY route the ADR names as a residual — deliberate: the
  tests drive the write path the way a person does.
- ADR-245 and migration 140 are provisional ordinals; a renumber must sweep this plan, `tasks.md`
  and the ACs.
- The defer rule's read-only escape and each script's own `--dry-run` parser can disagree
  (`set-role.sh` only honours position 3). The disagreement is fail-safe: the hook allows, the script
  is not in dry-run mode, the precheck refuses at exit 64.
