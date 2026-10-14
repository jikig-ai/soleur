---
title: "feat: agent-runnable operator bootstrap scripts with a harness-approved human acknowledgement"
date: 2026-10-01
slug: feat-agent-runnable-operator-bootstrap
branch: feat-one-shot-agent-runnable-operator-bootstrap
issue: 9321
type: feat
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Generated operator scripts (the `soleur:operator-bootstrap` skill, the shared library
`plugins/soleur/scripts/lib/operator-script.sh`, the template, and the open #9321 script) refuse to run
without a TTY: every production write needs a typed `yes` at a terminal, and without one the script exits
64 with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED tty=0`. Soleur serves non-technical founders and a web app where
nobody has a terminal, so that contract is wrong by our own product direction. The agent has to be able to
run every stage, one at a time, and the human acknowledgement of each production write has to move out of
the terminal into the harness approval channel (the permission prompt on the exact command, and the web
app's own approval card).

This plan (1) redesigns the contract (ADR-264, the CTO ruling below), (2) re-cuts the #9321 bootstrap on it
without losing a single safety property, (3) fixes the skills, the two rules and ship Phase 5.5 option 4 so
the terminal-only handoff cannot recur, and (4) adds a mechanical guard that fails a generated operator
script that cannot run without a TTY, with mutation-proven rows. #9321 stays open: this PR carries
`Ref #9321`, never `Closes`, because the switch change that closes it is a separate later PR.

Standing constraints for the whole pipeline (operator hard stops): no production write by the pipeline
(never run the real bootstrap, never apply, never mint or store a token, never read a real secret value);
every test uses stubbed `doppler`/`gh`/`curl`/`openssl` binaries on a scratch PATH; the PR is not merged and
auto-merge is not queued; CI is the test gate; no closed issue number in `#N` form anywhere (earlier merged
work for #9321 is described in prose); GHCR retirement and the legal cluster are untouched.

## CTO Ruling (security-model fork) — recorded in substance

Routed to `soleur:engineering:cto` per `hr-technical-fork-is-not-an-operator-question`; a second round
challenged the first answer against the operator's literal constraint. Binding ruling, verbatim in
substance:

1. **May any production write drop the human ack? NO.** Not a Doppler secret write into a container, not a
   service-token mint, not a GitHub environment secret write, not a revoke or rotation, not terraform apply.
   Reads (plan, read stages, verification) need no ack; a stage whose plan has zero write operations is
   read-class and an already-satisfied stage returns `changed=0` with no approval. **The STOP condition
   (hard stop 5) is therefore not triggered; implement.**
2. **Mechanism: C2 + C3 + C5, the hook is the enforcement point.**
   - C1 alone (ack lives wholly in the harness, script ungated) is rejected: no-hook harnesses (Codex,
     Devin cloud, Grok) would regress from today's TTY refusal.
   - **C2, hook-minted command-bound one-time receipt, no HMAC.** A new plugin-shipped PreToolUse hook matches
     a write-class `--apply` by **content fingerprint** (the `SOLEUR-GENERATED-OPERATOR-SCRIPT` header on the
     resolved file), not by basename. It mints a 128-bit nonce, writes a record named `sha256(nonce)` in
     `${XDG_STATE_HOME:-~/.local/state}/soleur/approvals/` (dir 0700, files 0600, outside the worktree)
     holding the digest, a 10-minute expiry and the session id, and returns `ask` (interactive) or `defer`
     (headless) with `updatedInput` prefixing `SOLEUR_APPROVAL_NONCE=<nonce> ` to the command. The script
     recomputes its own digest (script realpath, stage, argv, plan digest), requires a 32-hex nonce with a
     matching unexpired record, renames the record to `.consumed` BEFORE any write (fail closed if the
     rename loses a race), unsets the nonce before spawning any child, rejects a record that is a symlink,
     not owned by its euid or not mode 0600, and never echoes the nonce.
   - **C3 plan/apply as integrity.** Every write stage takes `--plan-digest <d>`; the script recomputes the
     plan (operation names, container names, token slugs, never values) and exits 75 `PLAN_DRIFT` if it
     differs, so the human approves exactly what runs. The digest is not a secret; the receipt is the ack.
   - **C5 kept.** A real TTY typed `yes` is a second valid ack source (`approval=tty-ack`).
   - **C4 (server-side approval) is the web adapter, not a script mechanism**, and is a tracked follow-up
     behind the same script contract. Web requirement it must test: write-stage commands are excluded from
     `isBashCommandSafe`, from the 60-minute "Approve all prefix" cache and from `bash_autonomous`, and are
     approved per exact command through the review-gate card.
3. **Per surface.** (a) Claude Code local: `ask` + `updatedInput`, mint at that point. (b) Headless / `-p` /
   `--bg` / one-shot: `defer`, mint NOTHING on the deferring invocation; on `claude --resume` the hook
   re-runs and mints only if the human-owned resume process's environment carries
   `SOLEUR_RESUME_APPROVED_DIGEST=<digest>` matching this command (the agent cannot alter the harness
   environment). (c) No-hook harnesses: the script exits 75 and writes nothing, for an instruction-following
   agent. (d) Web: canUseTool is the chokepoint (follow-up). `bypassPermissions` / dangerously-skip: the hook
   **denies** and never mints; if interactive-vs-headless cannot be determined, emit `defer`, never `allow`.
4. **Threat model and residual (binding; the ADR must say it plainly).** No same-OS-user design satisfies the
   operator's literal "the agent cannot write a file itself": any file the script reads is writable by the
   same OS user through Bash, and hash naming only stops a directory listing from leaking a live nonce.
   What this design does satisfy: an env var or a flag is **never** an ack (the nonce is a lookup key into a
   hook-written record; any value with no matching record gets exit 75; the nonce is bearer-only and the
   hook denies any original tool input that already contains it), and an instruction-following agent that
   follows skill text and exit markers, sets env, passes flags, pipes `yes`, or uses its ordinary
   Write/Edit/Bash tools without reverse-engineering the gate cannot satisfy it. **Out of scope, named as
   residual:** a hijacked or deliberate agent forging a receipt through an obfuscated path, a PTY wrapper for
   the C5 TTY source, direct `curl` with Doppler-held keys, `BASH_ENV`, editing hook files or settings.
   Closing that residual needs a principal the agent cannot write as (a separate OS user, or a broker
   holding a FIDO2 touch): credential custody, tracked as the open ADR-249 step 2 custody issue, not moved into this
   change. **The word "unforgeable" must not appear in the ADR, the skills or the rule text.**
5. **Script contract.** `--list`; `--stage <name>` runs a read stage or prints the plan for a write stage;
   `--stage <name> --apply --plan-digest <d> [--rotate]` runs the write (the existing flag name `--rotate-token` is kept, R12); there is no run-all mode. Exit
   **75** (EX_TEMPFAIL) is approval-required / approval-invalid / plan-drift; 64 stays "missing input", 78
   stays "xtrace refused". New library function `soleur_op_stage_gate`; `soleur_op_ack_or_die` is unchanged.
6. **Scope boundary.** Migrate the generated-script path only: library (additive), template, the #9321
   re-cut, the new hook rule, the new guard. flag-create, flag-delete, user-set-role, flag-set-role,
   provision-hetzner and audit-sentry `--apply` stay on the TTY ack (the flag scripts feed
   `flag_flip_audit.approval_method`, whose CHECK allows only `'tty-ack'` or NULL; widening it is a
   migration with the rollback-ordering hazard ADR-249 recorded). The three finished generated scripts
   (8450, linkedin, 8609) keep the legacy ack, recorded as a tracked follow-up.
7. **ADR form.** A new ADR-264 that supersedes in part ADR-228 points 2-4 and ADR-249 step 1 points 2 and 4,
   for generated scripts only, plus a "Superseded in part by ADR-264" blockquote on each; ADR-228 points 1, 5,
   6, 7 and the class-1/class-3 skip variables and ADR-249 points 1, 3, 5, 6, step 2 and the residual list are
   unchanged. Amending in place would hide a decision reversal.
8. **W0 probes are a work-phase STOP gate** before any implementation task: (1) `ask` + `updatedInput` shows
   the rewritten command in the permission prompt and the env prefix executes; (2) `ask` holds under
   `bypassPermissions` and allow-rules; (3) `defer` + `--resume` re-runs the hook and exposes the
   human-set marker; (4) an interactive-vs-headless discriminator exists (a payload field or
   `CLAUDE_CODE_ENTRYPOINT`); (5) the tool_use text the model sees after approval does not leak the nonce.
   **If probe 1 fails, STOP and report; do not ship a weaker file-only receipt. If probe 2 or 4 fails the
   write path is blocked: STOP.** Until the probes pass the existing TTY handoff for writes stays in force;
   reads and plans are agent-runnable regardless (no probe dependency).

Planner additions to the ruling (consistent with it, not overriding it; the final set after plan review is
R1-R26 in "Plan Review Revisions"): the hook only mints for a command that is exactly one simple command
(`[cd <dir> &&] bash <script> --stage <s> --apply --plan-digest <d> [--rotate-token]`, no pipe, no `;`, no `&&`
tail, no substitution), because the human approves one exact string and ADR-162's single-rewriter invariant
(updatedInput replaces tool_input; permission rules match the ORIGINAL command; a sibling deny wins) forbids
composing with another rewriter on the same call, which needs an explicit ADR-162 amendment; the hook ships in
`plugins/soleur/hooks/hooks.json` (the surface that reaches a founder's install), not only in this
repository's `.claude/hooks`; the web runtime opts the hook out with
`SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=1` through `buildAgentEnv` (the precedent `unkept-promise-hook.sh`
set), because the web Concierge loads this plugin's hooks.json and the web script runs fail closed at exit 75
until the web adapter lands; and the new-library-capability check is `declare -F soleur_op_stage_gate` after
`source` plus a pre-source grep in the resolver, with `SOLEUR_OP_LIB_API` left at 1.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality (measured) | Plan response |
|---|---|---|
| "the ADR that today says agents get exit 64 on production writes" is found by `git grep -l 'exit 64'` | Hits are ADR-228 (points 2-4), ADR-249 (step 1 point 2) and an unrelated ADR-149 line | Two ADRs carry the decision; a NEW ADR-264 supersedes both in part (CTO item 7), not an in-place amend |
| Skills that name "own terminal" / "typed yes" as the only path must offer the agent path first | The flag-create, flag-delete, user-set-role, flag-set-role SKILL.md files and `commands/go.md` say so for scripts that feed the WORM `approval_method` CHECK; operator-bootstrap SKILL.md and the library messages say so for generated scripts | Generated-script path becomes agent-first (this PR). The four flag skills cannot offer an agent-run write yet; their text is rewritten to state the reason and name the tracked follow-up, and this is reported to the operator rather than papered over |
| `--rotate-token` is the 9321 rotation path | The current script has `--rotate-token` and the runbook documents it | The flag keeps its name (no rename, no alias); the CTO contract's point is that rotation is an explicit flag inside the approved argv, so the digest binds it |
| A guard over generated scripts needs a hand list | `git grep -l SOLEUR-GENERATED-OPERATOR-SCRIPT` returns the SKILL mention plus four scripts (8450, linkedin, 8609, 9321) | Population is discovered; the template emits a v2 header that must satisfy the guard, and a v1 file must be one of three hard-coded legacy paths that may only shrink (merge-base subset check) |
| The new guard needs manual wiring in `scripts/test-all.sh` | `plugins/soleur/test/*.test.sh` is in `SUITE_GLOBS` (line 97) so a new file is picked up; `scripts/lib/test-affected-paths.sh` lines 147-152 list operator tests for relevance | New test is auto-discovered; add its relevance-map entry so a library change runs it; run the shard-parity reproduction harness because a new `*.test.sh` can shift leg parity (the recent s1/s2 regression) |
| Operator-script guards cover the knowledge-base bootstrap scripts | `g3_sourcing_scripts "$PLUGIN_ROOT"` walks `plugins/soleur` only; the specs scripts are outside operator-script.test.sh Guards 4/9 and `template.sh` is inside | Guards 4/9 are generalized to accept `soleur_op_stage_gate` as a gate on the template; the new behavioural guard is the one that covers the specs scripts |

## Research Insights

**Premise validation (Phase 0.6).** #9321 is OPEN with no closing PR, and the draft PR for this branch is
open. The mechanism in the brief (move the ack into the harness approval channel) was checked against the
ADR corpus: ADR-249 rejected only "harden each typed-yes prompt", "UserPromptSubmit marker hook", "nonce the
operator echoes back" (a nonce readable from the same stream) and "hookify-style per-command confirmation"
(Claude-only, and a menu ack is not prod-write authorization). Its chosen option F (credential custody) is
the only design that stops a hijacked agent; this plan deliberately does not move that in. The
hook-minted receipt differs from rejected Option C because the nonce travels only inside a human-approved
command, not through a stream the agent reads.

**Property list (Phase 0.6b).**
P1. Every stage of a generated script can be run by an agent with no TTY, one stage at a time.
P2. A re-run of any stage is safe, and a satisfied stage changes nothing and needs no approval.
P3. Every production write is preceded by a human approval of the exact command that performs it.
P4. An env var, a flag or a piped `yes` is never an approval (accidental-agent threat model).
P5. A stage's success and failure are machine-readable on stdout, and no credential is ever printed.
P6. The human can tell what will change and how to undo it in plain language before approving.
P7. A generated script that cannot run without a TTY fails CI.

**Cut list (Phase 0.6b).** (a) Run-all mode with a `--yes` style flag: buys nothing P3 allows, and is the
rejected agent-satisfiable gate. (b) HMAC over the receipt: a same-user key is readable, so it buys no
property. (c) A resume-index variable: re-run is resume because each stage opens with an already-satisfied
read (`library header`, already on main). (d) Migrating the six TTY-ack scripts: P1/P3 are not required for
them by the brief, and the WORM CHECK makes it a migration. (e) A GitHub Environment required-reviewer
workflow (C4 variant): the writes use the operator's own logins, so it is a different system.

**Repo findings.** Library `soleur_op_ack_or_die` (`plugins/soleur/scripts/lib/operator-script.sh:419-427`)
and the 64 refusal text (`:361-377`); template ack example (`template.sh:299`); defer gate
`.claude/hooks/prod-write-defer-gate.sh` rule 4 keys on basenames only; `approvals.jsonl` records
`approval_method: tty_resume` and is audit-only (no signature); plugin hooks live in
`plugins/soleur/hooks/hooks.json` and the web Concierge loads them too; ADR-162 single-rewriter invariant;
`DEFER-DECISION-PAYLOAD-SHAPE.md`: `defer` pauses silently, `ask` under `-p` is reported as blocked, the
envelope needs `hookEventName`. Census G7d (`tests/scripts/test-infra-privileged-tier-census.sh:1352-1395`)
finds the 9321 script by the literal `soleur-infra-app` and requires every `gh secret set` to carry
`--env infra-privileged` or `${GH_ENVIRONMENT}`, `GH_ENVIRONMENT="infra-privileged"` on its own line, and
forbids `soleur_op_gh_secret_set`, `gh variable set` and REST PUT stores: the re-cut keeps all of that.

**Institutional learnings applied.** A bootstrap stage must prove state from the vendor, never from its own
marker (environment secrets are write-only); a guard of spelled patterns has escapes, so add a must-PASS
non-canonical fixture; a stdout marker emitted inside a `$(f)` capture becomes the captured value (so no
marker inside a function whose stdout is captured); menu acks are not prod-write authorization; derive a
guard's population with the authority's own parser, not a looser grep. Stdout markers stay on stdout (ADR-228
point 4: agent runtimes swallow stderr) and carry names and booleans only.

**Functional overlap (Phase 1.5b).** Zero qualifying community results across three registries; build
in-repo.

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder's agent either cannot finish a credential
  bootstrap (stuck at exit 75 with no actionable prompt) or, worse, writes a production credential without the
  founder having seen what it was; the founder's release pipeline then runs on a wrong or over-broad token.
- **If this leaks, the user's workflow and credentials are exposed via:** a printed token or nonce in a
  transcript or ledger, a receipt record an agent forges to satisfy the gate, or an approval prompt that shows
  a command the founder cannot read and approves blind.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off is required at plan time before `soleur:work` begins (`requires_cpo_signoff: true`); it is
obtained in the Domain Review below. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

An architectural decision is made (a new trust boundary: a hook-minted approval receipt consumed by a
script; a reversal of two ADR decisions). The ADR and C4 updates are deliverables of THIS plan.

### ADR

Create **ADR-264** via `soleur:architecture`. Measured across every `origin/*` ref on 2026-10-01: `origin/main`
tops out at ADR-261, and sibling branches already claim ADR-262 and ADR-263, so the next free ordinal is 264
(provisional: a further sibling can still claim it, so `soleur:ship`'s ADR-ordinal collision gate re-derives it across every
`origin/*` ref before merge and after each sync, and a renumber sweeps this plan, tasks.md and every AC that
names the ordinal in the same edit). Title: "Generated operator scripts are agent-run in stages; the human
acknowledgement is a harness-approved receipt". Decision: the CTO ruling above. Alternatives considered:
C1 hook-only, C2 with HMAC, C3 digest as the ack, C4 GitHub Environment reviewer, keep-TTY-only, drop the ack
for low-risk writes (rejected, hard stop 5), amend in place. Add "Superseded in part by ADR-264"
blockquotes to ADR-228 and ADR-249, and amend ADR-162 (a second named PreToolUse rewriter for approval hooks, with
precedence against `grep-rewrite.sh` and a carve-out of its idempotent and fail-open clauses). Threat model and residual list exactly as ruled; the status line says
the ack "resists an instruction-following agent" and never "unforgeable".

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Enumeration against the feature:
(a) external human actor: the `founder` actor (the approver at the harness prompt); modeled. (b) external
systems: `doppler` (container copy and service-token mint) and `github` (environment secret write,
`GET /app`) are modeled as systems but have NO founder-originated edge for staged operator-script writes
(only `founder -> flagsmith` carries a script edge, and its text names a terminal TTY ack that stays true for
the flag scripts). (c) container/data store: the plugin-shipped Hook Engine description
(`platform.engine.hooks`) names guards and rewriters but not an approval-minting hook, and the 10-minute
receipt directory is local state on the founder's machine (documented in the Hook Engine description; there
is no persistent store, so no new element). (d) access relationship that changes: founder-gated writes move
from "TTY typed in the founder's terminal" to "harness-approved exact command". Planned edits: add
`founder -> doppler` and `founder -> github` edges (technology: harness approval prompt + agent-run staged
script), extend the `platform.engine.hooks` and `plugin` descriptions with the approval hook, keep the
`founder -> flagsmith` text accurate by naming it as the legacy TTY path (ADR-249, unchanged). `views.c4`
already includes `founder`, `doppler` and `github` in the context and container views, so the new edges
render without a view edit (both endpoints present, which is what makes an edge render). Then run
`plugins/soleur/test/c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `render-c4-model.test.sh` and the
web-platform C4 tests (`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`); regenerate
`model.likec4.json` through the repo's render script if freshness reds.

### Sequencing

The ADR is authored now, status `adopting`, describing the target state: the write path flips to "accepted"
only after the W0 probes pass and the first real harness-approved write is recorded in a ledger. Until the
probes pass the existing TTY handoff for writes stays in force.

## Infrastructure (IaC)

No new infrastructure is introduced. The re-cut script performs the secret copy and token mint that
ADR-241 D11 deliberately keeps outside Terraform (a secret value must never enter Terraform state), against
containers Terraform already created (`soleur-infra-app`, its `prd` environment, both `prevent_destroy`).

### Terraform changes
None.

### Apply path
None. This change has no Terraform apply and no workflow dispatch; the approved agent-run stages happen
after merge, each behind a harness approval.

### Distinctness / drift safeguards
Unchanged from the 9321 script: `soleur-infra-privileged` is the source, `soleur-infra-app` the
destination; both stay literal in the file so census G7d keeps finding it.

### Vendor-tier reality check
Doppler service tokens scoped to one config and GitHub environment secrets are both available on the current
tiers (the 9321 PR already depends on them).

## Observability

```yaml
liveness_signal:
  what: every stage settles a begin and a settle line in the run ledger and prints SOLEUR_BOOTSTRAP_STAGE_OK or a refusal marker on stdout
  cadence: per stage run
  alert_target: the invoking agent's tool output (stdout markers) and the ledger beside the script, committed in the founder's own repository
  configured_in: plugins/soleur/scripts/lib/operator-script.sh (soleur_op_stage_gate, plan_emit, soleur_op_ledger_write)
error_reporting:
  destination: stdout markers (SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED, _APPROVAL_INVALID, _PLAN_DRIFT, _STAGE_FAILED) plus the ledger run_halt line; stderr is never relied on
  fail_loud: exit 75 for any approval problem, exit 1 for a failed stage, exit 64 for missing input, exit 78 under xtrace
failure_modes:
  - mode: the hook is absent or its decision is not honored by the harness
    detection: the script exits 75 APPROVAL_REQUIRED and the ledger records approval=none surface=<harness>; the write never runs
    alert_route: the agent reads the marker and tells the founder in plain language; follow-up tracked for per-harness adapters
  - mode: the hook mints but the human denies (record left on disk)
    detection: the record expires after 10 minutes and the nonce never reaches a process; the ledger shows no nonce_sha12 for the stage
    alert_route: none needed; a forged-record attempt shows as a hook deny of the receipt directory path
  - mode: plan drift between plan and apply
    detection: SOLEUR_BOOTSTRAP_PLAN_DRIFT exit 75, no write
    alert_route: the agent re-plans and asks for a new approval
logs:
  where: bootstrap-runs.jsonl beside the script (names, booleans, plan digest, nonce_sha12, never values); the hook's own deny and mint events append to the existing incidents emitter
  retention: lives in the founder's repository until the follow-through issue closes and the script is deleted
discoverability_test:
  command: bash knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh --list
  expected_output: stage=mint-and-store-token class=write
```

(`--list` greps the script's own `# SOLEUR-STAGE` lines BEFORE the library is resolved, so the probe needs no
credentials, no library and no network and finishes inside the 15-second preflight cap; asserting the LAST stage
means a truncated list fails.)

## Encryption Posture

Not applicable: no persistent store and no new network connection. The receipt records are 10-minute,
mode-0600 files in a 0700 directory on the invoking machine; they hold a digest, an expiry and a session id,
never a credential, and the nonce itself is never stored (only its hash).

## Plan Review Revisions (applied 2026-10-01)

The five-agent eng panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) plus the CPO
sign-off and a CTO fidelity review returned findings; the classification and disposition of each is below.
Mechanical findings are applied in this plan; Taste and User-Challenge findings are NOT applied and are
persisted to `knowledge-base/project/specs/feat-one-shot-agent-runnable-operator-bootstrap/decision-challenges.md`.

**Applied (mechanical):**
R1 ADR-162 is amended, not merely "complied with": a second named PreToolUse rewriter (approval hooks), a
precedence rule against `grep-rewrite.sh` (an apply command must be a single simple command, so the two
predicates are disjoint; if both would fire the approval hook denies with the accepted form), a carve-out of
ADR-162 clauses 4 (idempotent) and 5 (fail open) for approval hooks (which fail closed), the one-entry
allowlist in `.claude/hooks/hookeventname-coverage.test.sh` extended by one named entry, and a test row.
R2 Version skew: the record and the digest input carry `algo=1`; a mismatch is `APPROVAL_INVALID reason=algo`,
never a generic 75. The library resolver skips a candidate that lacks `soleur_op_stage_gate()` (a grep of the
candidate file, before sourcing) and the template asserts `declare -F soleur_op_stage_gate` after `source`
with `SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE need=stage-1`. The second exported capability number was dropped.
R3 The `cd <dir> && bash ...` form: the nonce assignment is injected immediately BEFORE `bash`, not before the
whole string, and the whole `tool_input` object is copied into `updatedInput` (it replaces, it does not merge).
R4 The hook is prefiltered by a fixed-string check (the v2 header marker is not yet known at that point, so
the prefilter is: the command contains `--apply`, or the nonce variable name, or the receipt directory
fragment, or the tool is Write/Edit/Read and the path fragment matches). A call that fails the prefilter
returns `{}` with no jq dependency. Fail closed (deny envelope) applies ONLY to a prefiltered candidate, so a
missing `jq` on a founder machine cannot deny every Bash call. The hook is registered LAST, after its suite is
green, so a fault cannot brick the session that builds it.
R5 `.claude/hooks/devin-dispositions.tsv` gets a row per new hooks.json registration and the matchers are
anchored (`^(Bash|Monitor|Write|Edit|Read)$`-style, matching the existing `^(Bash|exec)$` convention), so
`devin-matcher-parity.test.sh` stays green; the Devin binding decision (bind or `n/a` with reason) is made in
Phase 0 from the measured Devin behaviour. Codex, Devin cloud and Grok get no hook: the coverage table in
ADR-264 records "script exits 75" and a tracked capability gap.
R6 Burn the receipt on `PLAN_DRIFT`; check the receipt DIRECTORY is mode 0700 and euid-owned as well as each
record; a failed rename (lost race) writes nothing; the nonce is unset before any child; a plan digest the
caller supplied is never trusted, it is recomputed; a correct digest with no nonce is exit 75.
R7 The "consume before write" property is tested deterministically: the stub logger snapshots the receipt
directory at the FIRST mutating call and asserts the record is already `.consumed`. The previous
concurrent-apply race row is replaced (it was nondeterministic).
R8 Known-answer digest vectors gain argv-boundary injection (`"a b"` vs `"a" "b"`) and a symlinked script path,
and there is an end-to-end hook-to-script round trip with a quoted, spaced path (the hook parses a command
string; the script receives shell-parsed argv).
R9 The stub classifies `curl` with `-X`, `-d`, `--data*` or `-T` as mutating. The legacy-list guard FAILS (not
skips) when there is no merge base or the clone is shallow.
R10 9321 stage preconditions (ordering is no longer enforced by a single run): the plan phase of
`mint-and-store-token` re-proves the live App and the copied values in-process and refuses with a
`SOLEUR_BOOTSTRAP_PRECONDITION_FAILED stage=<s> need=<stage>` marker if either fails; an inconclusive plan read
prints NO digest; an interrupted-mint marker appears as a recovery operation in the next plan;
`SOLEUR_BOOTSTRAP_READY_FOR_PR2` is derived from vendor state inside `verify`, never from the sequence of
stages run; the skill tells the agent to skip `--apply` when the plan has zero operations.
R11 Census G7d traps kept in the re-cut: `GH_ENVIRONMENT="infra-privileged"` stays top-level on its own line
(never inside a function), the only store is `gh secret set --env infra-privileged`, and plan or operation
text never contains the literal `gh secret set` (operations are named `store-environment-secret`,
`mint-read-token`, `revoke-token`, `copy-secret`).
R12 The apply-time alias is dropped: the existing flag name `--rotate-token` is KEPT unchanged (no rename, no
alias); it is the only rotation spelling in the hook grammar, the script and the runbook.
R13 The hook's `ask` reason carries the stage's plain-language impact and rollback line (CPO required change 2).
The hook reads them statically from the script's own `# SOLEUR-STAGE` lines; it NEVER executes the script (the
header marker is agent-writable, so running `--list` from a hook would hand the agent code execution outside
its sandbox). Impact and rollback text are included in the plan digest input, so the human approves the text
shown. The agent relays the script's lines verbatim and never composes its own (CPO required change 1).
R14 No terminal handoff for a no-hook or web surface (CPO required change 3): the skill's fallback says
"this surface cannot do production writes yet; run the stage from Claude Code in the interactive CLI" and does
not instruct a founder to open a terminal; founder-facing wording is specified for deny, expiry, drift,
headless-pending, web exit 75, bypass mode and tamper-class `APPROVAL_INVALID` reasons (Phase 4.2 table).
R15 A single exit-code and marker table with the agent's action for each is published in the skill (spec-flow
gap 1); `APPROVAL_INVALID reason=` is enumerated: `no-record`, `expired`, `digest-mismatch`, `consumed`,
`algo`, `perms` (symlink, owner, mode, directory), `format`. Re-issue for `expired`/`consumed`/`digest-mismatch`;
stop and report for `perms`/`algo`/`format`.
R16 `--list` is a static read of the script's own `# SOLEUR-STAGE <name>|<class>|<impact>|<rollback>` lines
(one source of truth: the hook parses the same lines, the dispatcher validates `--stage` against them, and a
guard row fails a dispatched function that is not declared). It runs BELOW the xtrace refusal and
`unset SSLKEYLOGFILE` and ABOVE library resolution (`PROLOGUE_MAX_CMDS = 0` forbids any command above the
refusal; the `grep` is below it), so the preflight probe works with no library and no credentials.
R17 The discoverability probe asserts the LAST stage (`stage=mint-and-store-token class=write`), so a one-line
list passes only if the whole table printed.
R18 `operator-approval.sh` sets no shell option, expands no secret-shaped name, uses portable `stat`
(`-c` with an `-f` fallback for bash 3.2 / macOS) and the library header's binary list gains `od`, `shasum`
and `stat`; the missing-sibling case is a marker plus `return` from the library `source`, not an `exit`
inside the library (header rule: a library `exit` kills the caller; the consumer owns `LIB_MISSING`).
R19 The hook fingerprint requires the `v2` header line (`SOLEUR-GENERATED-OPERATOR-SCRIPT v2`), so a legacy v1
script never gets a receipt minted. The template emits v2. SKILL.md's v1 line is updated.
R20 Pre-merge tests force `SOLEUR_OP_LIB` to the worktree library (the baked path points at the primary
checkout's pre-merge library); a row proves a stale library yields `LIB_INCOMPATIBLE need=stage-1`.
R21 Shard parity: run the reproduction harness right after Phase 1 and again at the end; confirm
`scripts/suite-shard-legs.tsv` needs no row (hash fallback) or add one.
R22 Phase 0 cites `.claude/hooks/UPDATED-INPUT-PAYLOAD-SHAPE.md` (updatedInput replaces tool_input, measured on
Claude Code 2.1.220) and probes only the NEW `ask` + `updatedInput` combination and the other W0 items.
R23 The resume marker is pinned: `SOLEUR_RESUME_APPROVED_DIGEST=<digest>`, minted only when it equals this
command's digest; a missing or mismatched value mints nothing (tested).
R24 A command matching both this hook and `prod-write-defer-gate.sh` rule 4 resolves by the documented
precedence deny > ask > defer; a test row covers it.
R25 Plain-language residual disclosure (CPO 5): the ADR, the skill, and the PR body each carry one sentence in
plain words: the approval guards against an agent acting on a mistaken instruction, not against a compromised
one; public copy must not claim "a human approves every production write" without that qualifier (flagged to
CMO and CLO in the PR body).
R26 `auto_command:` for a staged script is attended-only: it names `--list` plus the agent protocol
(`soleur:operator-bootstrap` §Running a generated script); the scheduled follow-through sweeper must not run
`--apply` (a 10-minute receipt expires before an unattended runner has an approval). A headless run prints
`SOLEUR_BOOTSTRAP_APPROVAL_PENDING stage=<s>` (the agent prints it before issuing apply) so a silent `defer` is
visible. Closure evidence is the `verify` stage's stdout markers pasted into the issue comment.

**Not applied (surfaced in decision-challenges.md):** DHH/simplicity propose cutting the Read/Write/Edit
receipt-directory deny arms (Bash-only hook; the CTO ruling lists Read/Write/Edit/Bash) and cutting the
four flag SKILL.md rewordings plus `go.md` (operator-requested scope: the terminal-only sweep; CPO also
requires the wording); DHH proposes folding the sibling and the stage helpers into fewer functions and cutting
guard rows (the CTO review asks for MORE rows). Where a cut conflicts with the operator's stated scope or the
binding CTO ruling it is a User-Challenge and the operator's direction is the default.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`): the guards' mutation matrices and fixtures are written
from the design before the code they test, and the hook is registered last.

### Phase 0 — W0 probes (STOP gate, no production effect)

Run the five probes in the CTO ruling with the `DEFER-DECISION-PAYLOAD-SHAPE.md` method (a stub
`PreToolUse(Bash)` hook in a scratch `CLAUDE_CONFIG_DIR`, a sentinel PostToolUse hook, `claude --print`;
nothing touches production). Cite `UPDATED-INPUT-PAYLOAD-SHAPE.md` for replace-vs-merge and probe only the new
`ask` + `updatedInput` combination, the bypass/allow-rule behaviour, the resume marker, the interactive
discriminator and nonce non-leak. Record the measured payloads and the Claude Code version in a new section of
`DEFER-DECISION-PAYLOAD-SHAPE.md`. Probe 1 failing, or 2 or 4 failing, stops the pipeline with a report
(CTO STOP); probe 3 failing narrows the headless arm to `defer` with no resume-mint (the stage then runs only
in an attended interactive session). Also verify that the existing guards over hook files and settings cover
`.claude/hooks` and `plugins/soleur/hooks`, and decide the Devin binding from a measured Devin run.

### Phase 1 — Tests first (RED)

1.1 `plugins/soleur/test/operator-agent-runnable.test.sh` (Guard 1) with fixtures; RED against today's
template. 1.2 `plugins/soleur/test/operator-stage-approval-hook.test.sh` (Guard 3). 1.3 Guard 11 in
`plugins/soleur/test/operator-script.test.sh` (Guard 2, the gate unit rows and the known-answer vectors).
1.4 Run the shard-parity reproduction harness now (R21).

### Phase 2 — Library (additive; `SOLEUR_OP_LIB_API` stays 1)

2.1 New sibling `plugins/soleur/scripts/lib/operator-approval.sh` (R18): digest, receipt directory
resolution, record validation, 32-hex check, `algo=1`. Sourced by the library and by the hook so mint and
verify share one algorithm. 2.2 In `operator-script.sh`: `plan_emit` (prints `SOLEUR_BOOTSTRAP_PLAN`,
`_IMPACT`, `_ROLLBACK`; no digest on an inconclusive read), `soleur_op_stage_gate` (order: recompute plan,
compare digest, validate nonce and record, burn on drift, consume-before-write, unset nonce, else TTY typed
`yes`, else APPROVAL_REQUIRED) and the stdout `STAGE_OK` printf; ledger fields `approval=`, `nonce_sha12=`,
`plan=`, `surface=`; header exit table gains 75 and marker table gains the new markers, `need=stage-1` and the
`APPROVAL_INVALID` reasons; the two "run this script in your own terminal" sentences are rewritten
agent-first for class-1 values. The library invariant holds (nonce read with `printenv`; no secret-shaped name).
2.3 `soleur_op_ack_or_die` is unchanged and frozen; its comment points at the stage gate and ADR-264.

### Phase 3 — Hook (registered last)

3.1 `plugins/soleur/hooks/operator-stage-approval.sh`, behaviour per the ruling and R1-R5, R13, R19, R23-R24.
3.2 `buildAgentEnv` in `apps/web-platform/server/agent-env.ts` sets
`SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=1` and a test mirroring `agent-env-credential-type.test.ts`
(and the existing unkept-promise opt-out test) fails if it stops being set; exact `1` only.
3.3 ADR-162 amendment plus the allowlist edit (R1). 3.4 ONLY after 1.2 is green: register in
`plugins/soleur/hooks/hooks.json` with anchored matchers and add the `devin-dispositions.tsv` rows (R5).

### Phase 4 — Template and skill

4.1 `template.sh` (v2 header, `# SOLEUR-STAGE` lines, `--list` above library resolution, `--stage`,
`--apply`, `--plan-digest`, `--rotate-token`, no run-all, `plan_*`/`apply_*` pairs for write class,
`STAGE_OK`, no `soleur_op_ack_or_die`, no raw `read` outside a class-1 `soleur_op_value`; keeps the xtrace
prologue, the `declare -F` capability assert, the git-ignore probe, `--reset` and the EXIT trap).
4.2 `operator-bootstrap/SKILL.md`: the stage/plan/apply/receipt contract replaces "exit 64 at the ack"; a new
section "Running a generated script" with the agent protocol (list; run read stages; for each write stage run
`--stage` for the plan; if zero operations skip apply; relay the script's impact and rollback lines
verbatim BEFORE issuing the apply command; print `SOLEUR_BOOTSTRAP_APPROVAL_PENDING stage=<s>`; issue exactly
`--apply --plan-digest <d>`; let the harness prompt carry the approval) and the table of exit codes and
markers with the agent action and the founder-facing wording for each (R14, R15):

| Outcome | Agent does | Founder is told |
|---|---|---|
| founder denied the prompt | stop; do not re-prompt in a loop; ask once whether to retry | "You declined, so nothing changed." |
| 75 APPROVAL_INVALID expired / consumed / digest-mismatch | re-plan, re-issue once | "That approval timed out (or was already used), so I am asking again." |
| 75 APPROVAL_INVALID perms / algo / format | stop and report | "A safety check failed and nothing changed; this needs a person to look at it." |
| 75 PLAN_DRIFT | re-plan, relay the new impact, re-issue | "Something changed since I showed you the plan; here is what is different." |
| 75 APPROVAL_REQUIRED, no hook or web | stop | "This surface cannot make production changes yet; run it from Claude Code in the interactive CLI." |
| headless pending | print APPROVAL_PENDING | "A change is waiting for your approval." |
| bypass-mode deny | stop | "Approvals are switched off in this session; switch to the normal mode and I will ask again." |
| 64 | stop; name the input; never ask for a secret in chat | "I need <login/input> set up first." |
| 78 | unset xtrace, re-run once | none |
| 1 STAGE_FAILED | run `verify`; never re-apply blindly | plain account of what changed and what did not |

Also require a plain-language impact and rollback line per write stage; credential entry stays a class-1
ladder rung; reference the guards and ADR-264; the residual in plain words (R25).

### Phase 5 — Re-cut the #9321 script

5.1 Regenerate from the template. Stages: `preflight` (read), `copy-app-values` (write; one approval covers
both values; `changed=0` when both already match), `prove-live-app` (read; a real RS256 JWT against
`GET /app`, PEM in-process), `mint-and-store-token` (write; one atomic approved unit: mint the read-only
service token scoped to `soleur-infra-app/prd`, store it as the `infra-privileged` ENVIRONMENT secret
`DOPPLER_TOKEN_INFRA_APP` through `gh secret set --env`, read-back verify, new-before-old; its plan phase
re-proves the live App and the copies, R10), `verify` (read; names only; derives the READY marker from vendor
state). `--rotate-token` inside the approved argv binds the revoke of the old token; a failure after the mint
revokes the new token in the on-exit cleanup and, if that revoke fails, prints
`SOLEUR_BOOTSTRAP_ORPHAN_TOKEN slug=<slug>` so the next plan carries a revoke recovery operation.
5.2 Keep every existing safety property (AC list) and the G7d traps (R11). `val_hash` stays in-process and
no hash of a secret is printed. 5.3 Update the runbook `infra-credential-tiers-8209.md` (step 3 and Rotation)
to the stage commands, keeping the `soleur-infra-app` literal in the script. 5.4 Verify with stub binaries
only (Test Scenarios); never run the real script.

### Phase 6 — Workflow, skills, rules

6.1 `ship/SKILL.md` Phase 5.5 option 4 and the headless abort text: for a staged script the follow-through
issue's `auto_command:` is the `--list` line plus the agent protocol reference (R26, attended-only); the agent
runs the stages in-session, the human approves each write at the prompt; the issue closes on the `verify`
stage's pasted markers; a harness approval prompt is not an "undeferred operator step" under
`wg-block-pr-ready-on-undeferred-operator-steps`; the legacy handoffs stay for the scripts still on the TTY
ack. 6.2 `AGENTS.rules.md`: shorten `hr-multi-step-post-merge-bootstrap-script` and
`hr-ship-message-no-operator-checklist` (substance: agent-run stages, human approves each write via the harness
prompt on the exact command, `auto_command:` names the stage protocol; detail lives in the skill); ids and the
single-line `**Why:**` kept; run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`
(B_ALWAYS 42919 now; warn 44000; reject 46000; per-rule cap 600 bytes); no new rule.
6.3 Terminal-only sweep (`own terminal`, `TTY`, `typed yes`, `type yes` over `plugins/soleur/skills`,
`commands`, `agents`, `.claude/hooks/README.md`): generated-script surfaces become agent-first; the four flag
SKILL.md files and `commands/go.md` keep the terminal handoff for the WRITE but say why (the audit-row CHECK
accepts only a TTY ack), never present a terminal as the normal founder path, and name the tracked follow-up;
`provision-hetzner` credential entry stays a class-1 interactive carve-out, stated as such.
6.4 `.claude/hooks/prod-write-defer-gate.sh` rule 4 comment and `.claude/hooks/README.md` cross-reference the
new hook and ADR-264; rule 4 itself is unchanged.

### Phase 7 — Guard generalization, ADR, C4, learning

7.1 `operator-script.test.sh` Guards 4 and 9 accept `soleur_op_stage_gate` as a gate on the template (window
rule) with a mutation row that removes it; Guard 7's baked-template copy is re-derived (R20).
`operator-ack-guard.test.sh` Guard 1 census is re-run (no change expected). `scripts/lib/test-affected-paths.sh`
gets the new tests' relevance entries. 7.2 ADR-264 (frontmatter `supersedes` naming the specific points,
`status: adopting`, two-way links with the blockquotes on ADR-228 and ADR-249, coverage table, W0
measurements, the plain residual) and the C4 edits. 7.3 Learning file. 7.4 `scripts-shard-totality.test.sh`
and the parity harness again (R21).

### Phase 8 — Deferral issues and PR

The follow-ups are FILED at plan time (open issues, milestones set): #9387 (migrate the TTY-ack scripts and the
three finished generated scripts, including the `approval_method` CHECK widening), #9388 (web approval adapter),
#9389 (per-harness adapters for Codex, Devin and Grok). The four flag SKILL.md files and `go.md` name #9387; the
web exit-75 wording in the skill names #9388; the ADR coverage table names #9389. Ask the roadmap workshop
(`soleur:product-roadmap`) to list them so they are not lost: (1) migrate the TTY-ack scripts (flag-create,
flag-delete, user-set-role, flag-set-role, provision-hetzner, audit-sentry `--apply`) to the stage gate,
including the `approval_method` CHECK widening migration; (2) the three finished legacy generated scripts;
(3) the web adapter (canUseTool approval card; exclusions from `isBashCommandSafe`, the "Approve all prefix"
cache and `bash_autonomous` tested); (4) per-harness adapters for Codex, Devin and Grok. PR body: `Ref #9321`,
no other `#N`, the plain-words residual, the W0 measurements, the files NOT touched.

## Guard Contract

### Guard 1 — operator-agent-runnable (a generated v2 operator script runs without a TTY and gates every write)

**Property.** For every discovered v2 generated operator script, every declared stage reaches a defined
outcome with stdin closed and no TTY, no stage reaches a mutating call without a valid harness receipt or a
real TTY ack, and no stage blocks, demands a terminal, or calls the legacy ack.

**Assembly.** Population: every file `git grep -l SOLEUR-GENERATED-OPERATOR-SCRIPT` finds (specs, archived
specs included) plus `template.sh`. A file with the v2 header must satisfy this guard; a file with the v1
header must be one of exactly three hard-coded legacy paths (8450, linkedin, 8609), and that inline list may
only shrink relative to the merge base (the guard FAILS if there is no merge base or the clone is shallow).
Chokepoints a stage leaves through: (1) the `# SOLEUR-STAGE` table behind `--list`, (2) each stage's plan path,
(3) each stage's apply path through `soleur_op_stage_gate`, (4) the class-1 value helper. The guard iterates
every `--list` entry (never a hard-coded count, never only the first stage), with `</dev/null`, a `timeout`,
`SOLEUR_OP_LIB` forced to the worktree library, and PATH-stubbed `doppler`, `gh`, `curl`, `jq`, `openssl`
that log each call and classify it read or mutating by verb (`curl` with `-X`, `-d`, `--data*`, `-T` is
mutating). It also walks comment-stripped source for raw `read -p`, a TTY demand on a non-class-1 path, and
`soleur_op_ack_or_die`, and fails a stage function that is dispatched but absent from the table.

**Mutation matrix:**

| # | Mutation (each on a COPY proven to differ from its source) | Expected |
|---|---|---|
| 1 | Add an unconditional `[[ -t 0 ]] \|\| exit 64` to a read stage | RED, read stage not runnable |
| 2 | Add a SECOND stage after a compliant first that calls `soleur_op_ack_or_die` or a raw `read -p` | RED naming stage 2 |
| 3 | Remove `soleur_op_stage_gate` from a write stage | RED, mutating stub call with no receipt |
| 4 | Guard's own dispatch: strip the v2 header from a fixture copy, or make `--list` print nothing | RED, "population != expected" or "zero stages observed" |
| 5 | A stage declared `read` that makes a mutating stub call | RED |
| 6 | Add a new v1-header script outside the three legacy paths | RED |
| 7 | A function dispatched by `--stage` but absent from the `# SOLEUR-STAGE` table | RED |
| 8 | A write stage whose declared impact or rollback text is empty | RED (CPO required change) |

**Harness rows.** The runner floor reports directly (`printf` + `exit 1`, never through the `fail()` counter,
ADR-193) when zero stages were driven. P1 (must-PASS, non-canonical): a fixture with `stage_install_keys`
dispatched by a `case` table and a read-class stage using a class-1 `soleur_op_value` whose skip variable is
set must PASS (behaviour, not naming). P2 (must-PASS): a write stage whose plan has zero operations returns
`changed=0` with no approval and no prompt.

**Anchor.** The population is re-derived from the tree at test time (`git grep`), not stored; the only stored
list is the three-path legacy list, anchored by the merge-base subset check, so one diff cannot add a legacy
path and bless it in the same commit.

### Guard 2 — receipt gate (library `soleur_op_stage_gate`; Guard 11 of operator-script.test.sh)

**Property.** The only inputs that let a write stage proceed are a valid single-use record for this exact
script, stage, argv and plan, or a real TTY typed `yes`; every other input exits 75 and writes nothing.

**Assembly.** Every way a value reaches the gate: the environment (`SOLEUR_APPROVAL_NONCE` and every other
`SOLEUR_BOOTSTRAP_*` name the script mentions, derived from the script), argv (every parsed flag), a file in the
working tree, a file in the receipt directory, stdin. The chokepoint is the single function
`soleur_op_stage_gate`; the guard asserts it is the only function that precedes the first write.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Skip the digest comparison | RED (a receipt minted for another stage is accepted) |
| 2 | Skip the expiry check | RED (an 11-minute-old record is accepted) |
| 3 | Skip the owner, mode, symlink or directory-0700 check | RED |
| 4 | Accept any 32-hex nonce with no record; accept `yes`, `1`, `true` as the nonce | RED |
| 5 | Move the consume (rename to `.consumed`) to AFTER the first write (a reorder, not a delete) | RED: the stub snapshots the receipt directory at the first mutating call and the record is not yet `.consumed` |
| 6 | Ignore a failed rename | RED (a lost race still writes) |
| 7 | Do not unset the nonce before a child runs | RED (the stub records the child's environment) |
| 8 | Trust the supplied `--plan-digest` without recomputing | RED (drift not caught) |
| 9 | A correct plan digest with no nonce is accepted | RED |
| 10 | Do not burn the record on `PLAN_DRIFT` | RED (the record is still live) |
| 11 | Echo the nonce in the ledger line or on stdout | RED |
| 12 | Add a SECOND write stage after a compliant first whose apply path bypasses the gate | RED naming that stage |
| 13 | Accept a record with `algo` other than 1 | RED (reason=algo) |

**Harness rows.** Must-PASS: a receipt directory on a path with a space and an `XDG_STATE_HOME` override.
Must-RED: the gate pointed at a different directory than the hook writes (the positive control reads the same
directory the hook wrote). Own-dispatch floor: the stub log must contain at least one entry per positive run.

**Anchor.** Mint and verify share `operator-approval.sh`, so one diff moves both and the suite stays green.
The independent anchor is a known-answer vector set computed by a second implementation (`python3 hashlib`)
inside the suite: `(script realpath, stage, argv, plan, algo)` vectors including argv-boundary injection
(`"a b"` vs `"a" "b"`) and a symlinked script path, plus an end-to-end hook-to-script round trip with a
quoted, spaced path.

### Guard 3 — approval hook (operator-stage-approval.sh)

**Property.** The hook never lets a stage `--apply` command reach execution without a human decision, never
mints for anything but one simple command, never mints under bypass mode or on a deferring invocation, and
never breaks a call that is not a candidate.

**Assembly.** Tool inputs (Bash, Monitor, Write, Edit, Read), every spelling of the script path (absolute,
relative with `cd`, via `bash -c`, a renamed copy carrying the v2 header, a legacy v1 copy), the modes
(interactive, headless, bypass, undeterminable, disabled by the web variable, resume with and without the
marker), and the other hooks that may fire on the same call (`prod-write-defer-gate.sh` rule 4,
`grep-rewrite.sh`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Key the fingerprint on the basename, or accept a v1 header | RED (a renamed v2 copy is missed / a legacy script gets a receipt) |
| 2 | Emit `allow` instead of `defer` when the mode is undeterminable | RED |
| 3 | Mint on the deferring headless invocation | RED |
| 4 | Mint under bypass mode | RED |
| 5 | Strip instead of deny an input carrying the nonce | RED |
| 6 | Let a compound command (pipe, `;`, `&&` tail, substitution) mint | RED |
| 7 | Inject the nonce before `cd` instead of before `bash` in the `cd <dir> && bash` form | RED (the script never sees the nonce) |
| 8 | Resume marker present but with a different digest, or absent, still mints | RED |
| 9 | Fail closed on a non-candidate Bash call when `jq` is missing | RED (must return `{}`) |
| 10 | A command that matches this hook AND rule 4 or `grep-rewrite.sh` resolves to anything weaker than deny > ask > defer | RED |
| 11 | Execute the script (for example `--list`) from the hook | RED (the hook must read the stage lines statically) |

**Harness rows.** The hook's trace file must show the SUT ran for every row (the `unkept-promise-hook`
pattern); a must-PASS non-canonical input (`--list` with a path containing a space) returns `{}`; a row that
removes `jq` from PATH and sends a candidate command must produce a deny envelope (fail closed only for
candidates).

**Anchor.** Envelope keys are asserted against the measured payloads committed in
`DEFER-DECISION-PAYLOAD-SHAPE.md` and `UPDATED-INPUT-PAYLOAD-SHAPE.md`, so a harness version change that
invalidates a measurement fails the re-probe trigger rather than the code.

## Files to Edit

- `plugins/soleur/scripts/lib/operator-script.sh` (stage gate, plan emit, markers, exit 75, ledger fields, wording)
- `plugins/soleur/skills/operator-bootstrap/SKILL.md`, `plugins/soleur/skills/operator-bootstrap/template.sh`
- `knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh` (re-cut)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (step 3, Rotation)
- `plugins/soleur/skills/ship/SKILL.md` (Phase 5.5 option 4 and headless abort text)
- `AGENTS.rules.md` (two rules)
- `plugins/soleur/hooks/hooks.json` (registered last), `.claude/hooks/devin-dispositions.tsv`
- `apps/web-platform/server/agent-env.ts` and its test (web opt-out variable)
- `plugins/soleur/test/operator-script.test.sh`, `plugins/soleur/test/operator-ack-guard.test.sh` (only if the census needs it), `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv` (only if the shard harness requires a row)
- `plugins/soleur/skills/flag-create/SKILL.md`, `flag-delete/SKILL.md`, `user-set-role/SKILL.md`, `flag-set-role/SKILL.md`, `plugins/soleur/commands/go.md` (reason, follow-up, never a normal founder path)
- `.claude/hooks/prod-write-defer-gate.sh` (comment), `.claude/hooks/README.md`, `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` (W0 measurements), `.claude/hooks/hookeventname-coverage.test.sh` (allowlist, with the ADR-162 amendment)
- `knowledge-base/engineering/architecture/decisions/ADR-162-pretooluse-hooks-may-rewrite-tool-input.md` (amendment), `ADR-228-generated-operator-scripts-are-non-interactive-by-default.md`, `ADR-249-operator-prod-writes-need-a-tty-ack-layered-with-credential-custody.md` (blockquotes)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `model.likec4.json` if freshness requires regeneration)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-264-generated-operator-scripts-are-agent-run-in-stages.md`
- `plugins/soleur/scripts/lib/operator-approval.sh`
- `plugins/soleur/hooks/operator-stage-approval.sh`
- `plugins/soleur/test/operator-agent-runnable.test.sh`, `plugins/soleur/test/operator-stage-approval-hook.test.sh`
- `plugins/soleur/test/fixtures/operator-agent-runnable/` (fixture generated scripts, including the non-canonical `case`-table one and the v1 legacy-shape one)
- `knowledge-base/project/learnings/2026-10-01-an-operator-script-that-needs-a-terminal-cannot-serve-a-user-without-one.md` (final name decided at work time)
- `knowledge-base/project/specs/feat-one-shot-agent-runnable-operator-bootstrap/tasks.md` and `decision-challenges.md`

Paths were checked with `git ls-files`: `plugins/soleur/test/*.test.sh` matches existing files,
`plugins/soleur/hooks/hooks.json` exists, `.claude/hooks/devin-dispositions.tsv` and
`UPDATED-INPUT-PAYLOAD-SHAPE.md` exist, the four flag SKILL.md files exist.

## Open Code-Review Overlap

None. A query of open `code-review` issues for every file in the two lists above returned no match.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] W0 probes 1, 2 and 4 pass and are recorded with the Claude Code version; if any fails the pipeline reports (CTO STOP) and the write path is not shipped.
- [ ] ADR-264 exists (`status: adopting`, `supersedes` names the specific points), states the threat model and residual in the CTO's words and in plain words, never uses the word "unforgeable" (`git grep -n unforgeable -- plugins knowledge-base/engineering/architecture/decisions/ADR-264*` returns nothing), names ADR-249 step 2 (credential custody) as the closure, and the blockquotes on ADR-228 and ADR-249 link both ways; ADR-162 carries the approval-hook amendment and `hookeventname-coverage.test.sh` is green.
- [ ] `bash plugins/soleur/test/operator-agent-runnable.test.sh` is green on the template, the re-cut 9321 script and the must-PASS fixtures, every mutation row is RED for its named reason, and the three legacy scripts are accepted only through the inline list.
- [ ] `bash plugins/soleur/test/operator-stage-approval-hook.test.sh` and the extended `operator-script.test.sh` (Guard 11, generalized Guards 4/9) are green; `operator-ack-guard.test.sh` and `.claude/hooks/prod-write-defer-gate.test.sh` stay green unchanged; `devin-matcher-parity.test.sh` is green.
- [ ] The re-cut 9321 script, driven with stubbed `doppler`/`gh`/`curl`/`openssl`, `SOLEUR_OP_LIB` forced to the worktree library and `</dev/null`: `--list` prints five `STAGE_DECL` lines (the last is `mint-and-store-token`); each read stage exits 0 with `STAGE_OK`; each write stage without `--apply` prints `PLAN`, `IMPACT` and `ROLLBACK` and makes zero mutating stub calls; `--apply` with no receipt exits 75 with `APPROVAL_REQUIRED` and zero mutating calls; `--apply` with a valid fixture receipt makes the expected mutating calls; a re-run returns `changed=0` with no approval; `--rotate-token` revokes the old token only after the new one is stored; stdout of every run contains no secret value and no hash of one (grep for the stub's sentinel secret returns nothing).
- [ ] Every existing 9321 safety property still holds, each by a named test row: no xtrace (exit 78), no secret on stdout, token scoped to `soleur-infra-app/prd` read-only, stored only with `gh secret set --env infra-privileged` (census G7d green: `bash tests/scripts/test-infra-privileged-tier-census.sh`), vendor-derived already-satisfied, interrupted-mint marker, INCONCLUSIVE never PASS (and no digest printed on an inconclusive read), repository- and organisation-level secret absence checks, re-run is the rotation path, `READY` derived from vendor state.
- [ ] `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` exits 0 with B_ALWAYS not above its pre-change value; the two rules keep their ids and a single-line `**Why:**`.
- [ ] `python3 scripts/lint-guard-contract.py` is green on this plan; `plugins/soleur/test/c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `render-c4-model.test.sh` and the web-platform C4 tests are green; `plugins/soleur/test/scripts-shard-totality.test.sh` and the shard-parity reproduction harness are green with the new test files present.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py`, `python3 scripts/lint-infra-no-human-steps.py` (changed markdown) and `shellcheck` are clean over new and re-cut shell.
- [ ] The terminal-only sweep greps (`own terminal`, `TTY`, `typed yes`, `type yes`) show no generated-script surface that offers the terminal as the only path; each remaining mention (the four flag skills, `go.md`, `provision-hetzner` credential entry) states why and names a tracked follow-up issue that exists with a milestone.
- [ ] `git diff --stat origin/main...HEAD` shows none of: `.github/workflows/cla.yml`, any legal document, any GHCR file, any Terraform file, any workflow.
- [ ] PR body: `Ref #9321`, no other issue number in `#N` form, no `Closes`, no auto-merge queued, not merged.
- [ ] CI green (CI is the test gate); PR marked ready (not draft); report. Never merge, never admin-merge.

### Post-merge (after this PR merges; not performed by the pipeline)

- [ ] In an attended Claude Code session the agent runs `bash knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh --list`, each read stage, and for each write stage `--stage <name>` then `--stage <name> --apply --plan-digest <d>`; the founder approves each write at the harness prompt on the exact command. The `verify` stage's stdout markers (including `SOLEUR_BOOTSTRAP_READY_FOR_PR2`) are the closure evidence.

## Test Scenarios

- Given a harness with the hook and `ask`, when the agent issues the apply command for a write stage, then the permission prompt shows the rewritten command and the stage's plain-language impact and rollback line, and on approval the script consumes the receipt and writes (`approval=harness-receipt`).
- Given the same, when the human denies, then no process receives the nonce, the record expires after 10 minutes, and a second apply attempt gets a fresh prompt.
- Given a no-hook harness, when the agent issues `--apply`, then exit 75 `APPROVAL_REQUIRED` with the exact command in the marker and zero writes.
- Given a replayed nonce, a nonce for another stage, an expired record, a symlinked or wrong-mode record or directory, `yes` as the nonce, `--confirmed`, or an `algo` mismatch, then exit 75, zero writes and the right `APPROVAL_INVALID reason=`.
- Given a state change between plan and apply, then `PLAN_DRIFT`, exit 75, the record burned, zero writes.
- Given a stage whose vendor state already satisfies it, then `changed=0` and no approval needed.
- Given `mint-and-store-token` planned while the live-App proof fails, then `PRECONDITION_FAILED` and no digest.
- Given xtrace is on, then exit 78 before any read of a credential.
- Given `bypassPermissions`, then the hook denies and mints nothing.
- Given the web runtime (`SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=1`), then the hook is a no-op and the script exits 75 on apply (web adapter pending).
- API verify (names only, post-merge, by the agent): `gh api repos/jikig-ai/soleur/environments/infra-privileged/secrets --jq '.secrets[].name'` lists `DOPPLER_TOKEN_INFRA_APP`; `doppler configs tokens -p soleur-infra-app -c prd --json | jq -r '[.[].name] | sort | join(",")'` prints `release-app-mint`.

## Domain Review

**Domains relevant:** Engineering, Product, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The security-model ruling above (explicit consult plus a challenge round), then a fidelity review
of the finished plan: approved with nine required changes, all applied (R1-R26). The CTO also reviewed that no
production write may drop the human ack; hard stop 5 is not triggered.

### Product (CPO)

**Status:** reviewed (sign-off obtained)
**Assessment:** CPO SIGN-OFF: approved with required changes: (1) script-emitted, digest-bound impact and
rollback lines relayed verbatim, with a guard row; (2) plain-language impact in the hook's `ask` reason; (3) no
terminal-handoff fallback for no-hook or web surfaces; (4) founder-facing wording for deny, expiry, drift,
headless-pending and web exit 75; (5) plain-words residual disclosure and milestoned follow-up issues filed
before merge. All five applied (R13, R14, R15, R25, R26, Phase 8, Guard 1 row 8).

### Operations (COO)

**Status:** reviewed by carry-forward from the CTO ruling
**Assessment:** The post-merge run of the 9321 script is an attended agent-run, human-approved sequence rather
than a founder terminal session; the staged `auto_command:` is attended-only (R26).

### Product/UX Gate

**Tier:** none (no UI file in Files to Create/Edit; the web adapter that adds an approval card is a tracked
follow-up). The wording the founder sees in the harness prompt is a product surface covered by the CPO
assessment.
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

### GDPR / Compliance

`soleur:gdpr-gate` not invoked: no schema, migration, auth flow or API route is touched, and the receipt holds
no personal data. The one trigger-adjacent point (a plugin hook runs on a customer's self-hosted CLI,
observability layer 7) is addressed in the Observability section.

## Deliverables beyond code

- **Learning** (`knowledge-base/project/learnings/`): a gate that needs a terminal cannot serve a user who has
  none; the approval has to live in the channel the human already has (the harness prompt on the exact command),
  and the honest threat model for a same-user gate is "resists an instruction-following agent", with the
  hijacked-agent closure assigned to credential custody. Include the planning traps: a hook that executes the
  script it fingerprints is code execution outside the sandbox; a fail-closed hook needs a prefilter or it bricks
  every call; a plan that moves ordering from a single run to separately addressable stages must re-prove
  preconditions inside the later stage.
- **Follow-up issues** (Phase 8), filed before merge.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails deepen-plan; it is filled here.
- `updatedInput` REPLACES `tool_input`, and permission rules match the ORIGINAL command (ADR-162): the human
  approves the rewritten string but an allow rule matches the original. W0 probe 2 must show `ask` still
  prompts when an allow rule would have matched, or the write path is blocked.
- The receipt is a same-user file. Never describe it as unforgeable; the deny rule on the receipt directory is
  a speed bump for Bash and Monitor (string matching is evadable) and reliable only for the Write/Edit/Read
  tools (canonicalized path).
- The hook must never execute the script it fingerprints: the v2 header is agent-writable, so running
  `--list` from the hook is code execution outside the agent's sandbox. It reads `# SOLEUR-STAGE` lines
  statically.
- A stage marker emitted inside a `$(...)` capture becomes the captured value; keep `STAGE_OK`, `PLAN` and
  refusal markers outside any function whose stdout is captured, and never print a secret hash (a hash is an
  oracle).
- `soleur_op_stage_gate` consumes the record BEFORE the first vendor write; a reorder (not a delete) is the
  mutation a suite that only reads state after the function returns cannot see, so the stub snapshots the
  receipt directory at the first mutating call.
- `SOLEUR_OP_LIB_API` stays 1 (frozen legacy scripts assert equality); the new capability is detected by
  `declare -F soleur_op_stage_gate` after `source` and by a pre-source grep in the resolver, so a stale cached
  library cannot shadow a newer baked one.
- The baked library path in the re-cut script points at the primary checkout's library, which gains the new
  function only after this PR merges and the checkout updates; every pre-merge test forces `SOLEUR_OP_LIB`.
- Census G7d reads the 9321 script line by line: keep `GH_ENVIRONMENT="infra-privileged"` top-level and never
  write the literal `gh secret set` in plan text without `--env infra-privileged` or `${GH_ENVIRONMENT}`.
- `PROLOGUE_MAX_CMDS = 0`: no command may sit above the xtrace refusal; the `--list` grep sits below it.
- Adding a `*.test.sh` can shift shard-leg parity; run the reproduction harness after Phase 1 and at the end.
- `hooks.json` in `plugins/soleur/hooks/` is also loaded by the web Concierge: the hook must no-op there
  through the disable variable, with a test that fails if `buildAgentEnv` stops setting it.
- Do not cite closed issue numbers: #9321 is the only issue reference; the earlier merged work for #9321 is
  described in prose in every artifact.
