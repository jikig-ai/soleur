# ADR-236: Human-only skills are user-invoked; the description budget counts what the model sees

- **Date:** 2026-09-21
- **Issue:** #8290

## Status

Accepted. The flip, its guard (`plugins/soleur/test/invocation-axis.test.ts`) and the ratcheted
description budget land in the PR that carries this ADR.

## Context

Claude Code loads every model-invocable skill's description into an always-loaded skill listing.
That listing has its own cap, separate from the `AGENTS.md` + `AGENTS.rules.md` corpus that ADR-151
governs as `B_ALWAYS`: the harness keeps every skill's name but drops descriptions once the listing
exceeds a fraction of the context window. Soleur proxies it in-repo with
`SKILL_DESCRIPTION_WORD_BUDGET` (`plugins/soleur/test/components.test.ts`), which sat at zero headroom
(2561/2561).

A skill whose frontmatter sets `disable-model-invocation: true` is **user-invoked**. The
mattpocock/skills peer audit (Tier 1, bundle 4) surfaced this axis. Soleur used it nowhere.

### Measured behaviour (W0, 2026-09-21)

Transcripts are in `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/w0/`.

| Harness (version) | Probe | Result |
|---|---|---|
| Claude Code 2.1.278 | throwaway plugin, headless `/probe8290:flagged` | runs (`SENTINEL-FLAGGED-RAN`) |
| Claude Code 2.1.278 | Skill tool on the flagged skill | refused: `Skill probe8290:flagged cannot be used with Skill tool due to disable-model-invocation. Ask the user to run /probe8290:flagged themselves — it cannot be invoked via the Skill tool. Do not replicate this skill's workflow by other means — it is reserved for explicit user invocation.` |
| Claude Code 2.1.278 | model's listing | the flagged description is absent; the control is listed verbatim |
| Claude Code 2.1.278 | interactive TUI in tmux, `/probe8290:fla` | autocompletes, runs |
| Claude Code 2.1.278 | real plugin: headless `/soleur:cron-list`; Skill tool on `soleur:cron-list`; Skill tool on `soleur:trigger-cron` and `soleur:flag-list`; TUI `/soleur:flag-cr` | runs; refused (same text); both launch; `/soleur:flag-create` autocompletes |
| Devin CLI 3000.10.31 | `devin skills list` with the probe skills | flagged skill listed `[user]` (still typeable), control `[user,model]`. The key is honoured |
| Codex CLI 0.155.1 | `codex exec` listing with the probe skills | both descriptions load. The key is ignored: inert, nothing regresses, nothing is saved |
| Grok Build | not probed | inert by construction: its adapter Reads `SKILL.md` directly |

`cron-list` and `trigger-cron` were the real-plugin probe subjects; `cron-list` was later kept
model-invocable (review reversal, below). The re-probe for the final set uses TUI autocomplete of
`/soleur:provision-h`, which shows a flipped skill without running it (#8499).

The upstream reports anthropics/claude-code#22345 (flag ignored for plugin skills) and #92769
(flagged plugin skills also hidden from the user) do not reproduce on 2.1.278 on Linux.

**Listing effect on a 200k-window model (model self-report, directional only).** Haiku 4.5 with the
real plugin (`--setting-sources project`) reported `TOTAL_WITH_DESC=11` before the flip
(`TOTAL_NAME_ONLY=99`) and `TOTAL_WITH_DESC=11` after it (`TOTAL_NAME_ONLY=91`). The same 11 built-in
skills kept a description both times. **No observed listing benefit on 200k-window models**: the
listing there is so far over its cap that removing the then-12 descriptions freed no slot a Soleur
skill can use; the final set is 8. The in-repo budget still banks the relief (Decision 2).

## Decision

1. **A skill takes `disable-model-invocation: true` only if** all three hold. These are necessary
   conditions, not sufficient ones. Membership is the reviewed list below, fixed by the exact-set pin
   in `invocation-axis.test.ts`.
   - **K1.** No model-read surface directs the agent to invoke it.
   - **K2.** It is not a founder-facing capability the web Command Center must reach. Web **user turns**
     reach skills only through the model: each ends with
     `POSTAMBLE = "Invoke /soleur:go on the user's intent."` (`apps/web-platform/server/prompt-injection-wrap.ts`).
     (`server/auto-sync-trigger.ts` sends `/soleur:sync` directly; that is not a flipped skill.) So a
     user-invoked skill is treated as unreachable there, and `commands/go.md` replies that those
     commands are CLI-only and names them. The web runner pins Claude Code 2.1.219 / Agent SDK 0.3.197,
     which W0 did not probe; the go.md hand-off holds whether or not that version refuses.
   - **K3.** Its capability is not stranded: the model can still reach it another way, or it is
     deliberately operator-only (a credential- or prod-bound action behind a human gate).
2. **`SKILL_DESCRIPTION_WORD_BUDGET` counts only model-invocable skills**, and the freed words are
   banked by ratcheting the cap down to the measured total (2561 → 2389), not left as spendable slack.
3. **Guard 1 (`plugins/soleur/test/invocation-axis.test.ts`) is the enforcement.** Its population is
   what the model reads or is dispatched with: `AGENTS.md`, `AGENTS.rules.md`, the `CLAUDE.md` files,
   `plugins/soleur/AGENTS.md`, the plugin's skills, agents, commands, Devin and Codex mirrors, hooks
   and harness lib, the Inngest cron prompts, two named web-platform prompt files, workflows,
   `.claude/hooks/`, and the operations runbooks. A user-invoked skill may be named there only at a
   (file, skill) pair in its ack table, as a `doc-mention` or an `operator-handoff`, on the reviewed
   number of lines. It also refuses any non-boolean value of the key (Claude Code honours `yes`,
   `on`, `1` and `"true"`, the guards read `=== true`) and asserts go.md names every flipped skill.
4. **The invocation axis is a context-budget and discoverability measure, not a security control.**
   It stops the Skill tool; it does not stop an agent running a skill's scripts with Bash. That
   pre-existing gap is tracked in #8486.

### The reviewed list

| Skill | Verdict | Criterion |
|---|---|---|
| flag-delete | user-invoked | K1: an irreversible delete across Flagsmith and Doppler prd; never a feature-build acceptance step (two cleanup plans name it, and `wg-plan-prescribed-skills-must-run-inline` marks those `pending-operator`) |
| provision-cloudflare, -doppler, -github, -hetzner | user-invoked | K1: the tenant-provisioning runbook hands each to the operator to type |
| admin-ip-refresh | user-invoked | K1: human-facing text only. It mutates Doppler behind an explicit ack. The agent's no-flip path for `hr-ssh-diagnosis-verify-firewall` is the read-only egress check in `admin-ip-drift.md` (`curl ifconfig.me`, `doppler secrets get ADMIN_IPS`) |
| user-set-role | user-invoked | K1: sibling prose; migration 054's error text names it for a human |
| cf-token-scope | user-invoked | K1: named in prose only |
| **trigger-cron** | **stays model-invocable** | fails K1: `hr-no-dashboard-eyeball-pull-data-yourself` and the incident, gdpr-gate and reproduce-bug skills direct the agent to fire crons itself |
| **invoice** | **stays model-invocable** | fails K2: founder-facing (ADR-107) and reached on the web only through the model |
| **flag-list** | **stays model-invocable** | a read-only drift audit the agent must pull itself, and the blast-radius step flag-delete calls |
| **flag-create** | **stays model-invocable** (review reversal) | fails K1: plans prescribe it as an agent acceptance step (`wg-plan-prescribed-skills-must-run-inline`); a refusal leaves a `RUNTIME_FLAGS` entry with no Flagsmith/Doppler flag, and `create.sh` then blocks the operator's own run |
| **flag-set-role** | **stays model-invocable** (review reversal) | fails K1: plans prescribe it as an agent step; `flip.sh --confirmed` exists for agent-driven use behind a typed-yes gate (#5333) |
| **cron-list, cron-delete** | **stay model-invocable** (review reversal) | K3 points the other way: `soleur:schedule` runs the same steps in place, so a flip saves nothing and its refusal text contradicts `schedule/SKILL.md` |
| flag-bootstrap | not applicable | not a skill: its directory holds only a runbook |

The seven keep-pins are asserted in `components.test.ts` (`MUST_STAY_INVOCABLE`), each with its reason.
This keeps #5333's intent: agents can create flags, flip them and run the cron CRUD. Only destructive
and credential-bound operator work is user-invoked.

### Measured saving

| Budget | Before | After | Delta | Command |
|---|---|---|---|---|
| Skill description listing (in-repo proxy) | 2561 words | 2389 words | −172 words / −1,152 B | `discoverSkills()` + `parseComponent()` over every skill, summing model-visible descriptions |
| `B_ALWAYS` (ADR-151) | 42,920 B | 42,920 B | **0 B** | `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` → `[OK] B_ALWAYS=42920` |

`B_ALWAYS` is untouched by construction; see ADR-151's 2026-09-21 addendum. On harnesses that ignore
the key (Codex, Grok), the 8 descriptions still load; each stays bounded by the per-skill
1024-character test, which counts every skill. Only the key is inert there: the prose policy in
go.md and help.md applies on every harness.

### Headless-refusal policy

The policy: an unattended run that hits a Skill-tool refusal for a user-invoked skill must stop and
file an `action-required` issue naming the command the operator must type, and must never re-run the
skill's steps by hand. The harness refusal itself says the same ("Do not replicate this skill's
workflow by other means"). It reaches the model through go.md's operator-typed paragraph; no
unattended pipeline prescribes a user-invoked skill today (Guard 1 scans them).

### Adding a user-invoked skill

Five sites move together in one reviewed diff: the exact-set pin and the ack table in
`invocation-axis.test.ts`, this ADR's list, go.md's operator-typed paragraph (asserted by the guard),
and `SKILL_DESCRIPTION_WORD_BUDGET` (lowered by the skill's description word count). Before flipping,
grep `knowledge-base/project/plans/` for the skill: a skill plans prescribe as an agent step fails K1.

## Considered Options

| Option | Outcome |
|---|---|
| Flip all 16 skills the issue listed | Rejected: `flag-bootstrap` is not a skill; flipping `trigger-cron` breaks an always-loaded rule; flipping `invoice` strands the web founder; flipping `flag-list` hides a read-only audit the agent must pull |
| `user-invocable: false` | Rejected: the inverse axis (hides from the `/` menu, keeps the model) |
| Rewrite the flipped descriptions as short human-facing one-liners | Cut: the flag removes the description whatever its wording |
| A router skill for operator tooling | Not needed: `soleur:help` already lists every skill for the human and marks user-invoked ones |
| A separate operator plugin | Out of scope |
| Keep the cap at 2561 and leave 172 words of headroom | Not chosen: it lets the listing regrow to today's size without a reviewed bump |
| **Positive-phrasing rewrite of the always-loaded rule corpus** (peer's writing-for-agents) | Not adopted: **INCONCLUSIVE; instrument validity limited** (B5, 2026-09-21). Pre-registered Δ = +8.0 pts, 2·SE [+0.2, +15.8] against a 10-pt MWE (648 calls, $48.85; verdict module sha256 `18c2481c…bf28` at 1a5b79261). A post-verdict audit found scorer false positives: the unbounded-output rule re-scores to Δ_r ≈ +0.037 and the aggregate to ≈ +5.6 pts, and empty answers scored as compliant. The run is evidence neither for nor against the rewrite. Rule bodies unchanged; no rejected-concepts entry. Machinery archived (restore from `pull/8484/head`). Record: `specs/feat-one-shot-8290-invocation-axis-budget-relief/b5-eval-results.md`; revisit: #8497 |
| Keep all 12 flips and teach plan/work to hand the flag and cron steps to the operator | Rejected in review: it knowingly ships a conflict with `wg-plan-prescribed-skills-must-run-inline` and leaves flags silently off, while the rule fix is out of this PR's scope |
| Un-flip only the flag pair | Rejected: the cron refusal text would still contradict `soleur:schedule`'s in-place steps, to save 56 words |
| Also un-flip flag-delete | Rejected: an irreversible prd delete no feature-build plan needs; the rule's `pending-operator` clause covers cleanup plans |
| Keep and fix the B5 machinery in place | Rejected: it cannot produce a new official verdict, every #8497 condition rewrites it, and its hash-lock tied CI to live rule bodies |
| Relabel the B5 verdict INVALID | Rejected: a retroactive change of a pre-registered output; a disclosed qualifier is the honest form |
| Make the budget assertion an equality | Rejected: every PR that shortens a description would edit one shared long line, with no ratchet benefit over `<=` at merge |

## Principle Alignment

| Principle | Status | Note |
|---|---|---|
| AP-004 Agent-native parity | Deviation | Eight destructive or credential-bound operator actions are human-invoked. Justified: each writes prod state behind a typed-yes gate or a human-only credential, and review kept every skill an agent pipeline needs (flag create/flip, cron CRUD) model-invocable |
| AP-007 Exhaust automation before manual steps | Deviation, bounded | The agent still runs every read-only diagnosis around these skills (flag-list, the admin-ip drift check) and hands over one typed command, not a manual procedure |

## Rollback triggers

Revert the 8 keys (the exact-set pin makes it an explicit edit) if any of these is observed:

- A Claude Code release hides a flagged plugin skill from the user (the upstream #92769 shape).
  Re-probe (TUI autocomplete of `/soleur:provision-h` against the installed plugin; nothing runs) after
  this release and at Claude Code releases. Tracked in #8499.
- Devin stops listing a flagged skill as user-typeable.
- Codex starts honouring the key in a way that hides it from the user.

## Consequences

- Operator tooling is typed by the operator; the model hands the command over instead of running it.
- The web Command Center cannot reach the 8 skills; it says so and names the CLI command.
- The in-repo description budget tracks what the model sees, and a new skill description again needs a
  reviewed bump against a zero-headroom baseline.
