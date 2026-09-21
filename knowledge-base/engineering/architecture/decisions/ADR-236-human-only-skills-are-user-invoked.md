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

The upstream reports anthropics/claude-code#22345 (flag ignored for plugin skills) and #92769
(flagged plugin skills also hidden from the user) do not reproduce on 2.1.278 on Linux.

**Listing effect on a 200k-window model (model self-report, directional only).** Haiku 4.5 with the
real plugin (`--setting-sources project`) reported `TOTAL_WITH_DESC=11` before the flip
(`TOTAL_NAME_ONLY=99`) and `TOTAL_WITH_DESC=11` after it (`TOTAL_NAME_ONLY=91`). The same 11 built-in
skills kept a description both times. **No observed listing benefit on 200k-window models**: the
listing there is so far over its cap that removing 12 descriptions frees no slot a Soleur skill can
use. The in-repo budget still banks the relief (Decision 2).

## Decision

1. **A skill takes `disable-model-invocation: true` only if** all three hold. These are necessary
   conditions, not sufficient ones. Membership is the reviewed list below, fixed by the exact-set pin
   in `invocation-axis.test.ts`.
   - **K1.** No model-read surface directs the agent to invoke it.
   - **K2.** It is not a founder-facing capability the web Command Center must reach. The web product
     reaches skills **only through the model**: each user turn ends with
     `POSTAMBLE = "Invoke /soleur:go on the user's intent."` (`apps/web-platform/server/prompt-injection-wrap.ts`).
     A user-invoked skill is unreachable there, so `commands/go.md` replies that those commands are
     CLI-only and names them.
   - **K3.** Its capability is not otherwise stranded.
2. **`SKILL_DESCRIPTION_WORD_BUDGET` counts only model-invocable skills**, and the freed words are
   banked by ratcheting the cap down to the measured total (2561 → 2295), not left as spendable slack.
3. **Guard 1 (`plugins/soleur/test/invocation-axis.test.ts`) is the enforcement.** Its population is
   what the model reads or is dispatched with: `AGENTS.md`, `AGENTS.rules.md`, the plugin's skills,
   agents, commands, Devin and Codex mirrors, hooks and harness lib, the Inngest cron prompts,
   workflows, `.claude/hooks/`, and the operations runbooks. A user-invoked skill may be named there
   only at a (file, skill) pair in its ack table, as a `doc-mention` or an `operator-handoff`.
4. **The invocation axis is a context-budget and discoverability measure, not a security control.**
   It stops the Skill tool; it does not stop an agent running a skill's scripts with Bash. That
   pre-existing gap is tracked in #8486.

### The reviewed list

| Skill | Verdict | Criterion |
|---|---|---|
| flag-create, flag-delete, flag-set-role | user-invoked | K1: named only by siblings and operator documentation; they operate Soleur's own Flagsmith and Doppler |
| cron-list, cron-delete | user-invoked | K3: `soleur:schedule` carries the identical list and delete steps, and the model runs them in place |
| provision-cloudflare, -doppler, -github, -hetzner | user-invoked | K1: the tenant-provisioning runbook hands each to the operator to type |
| admin-ip-refresh | user-invoked | K1: human-facing text only. It mutates Doppler behind an explicit ack. The agent's no-flip path for `hr-ssh-diagnosis-verify-firewall` is the read-only egress check in `admin-ip-drift.md` (`curl ifconfig.me`, `doppler secrets get ADMIN_IPS`) |
| user-set-role | user-invoked | K1: sibling prose; migration 054's error text names it for a human |
| cf-token-scope | user-invoked | K1: named in prose only |
| **trigger-cron** | **stays model-invocable** | fails K1: `hr-no-dashboard-eyeball-pull-data-yourself` and the incident, gdpr-gate and reproduce-bug skills direct the agent to fire crons itself |
| **invoice** | **stays model-invocable** | fails K2: founder-facing (ADR-107) and reached on the web only through the model |
| **flag-list** | **stays model-invocable** | a read-only drift audit the agent must pull itself, and the blast-radius step flag-delete calls |
| flag-bootstrap | not applicable | not a skill: its directory holds only a runbook |

The three keep-pins are asserted in `components.test.ts` (`MUST_STAY_INVOCABLE`), each with its reason.

### Measured saving

| Budget | Before | After | Delta | Command |
|---|---|---|---|---|
| Skill description listing (in-repo proxy) | 2561 words | 2295 words | −266 words / −1,733 B | `discoverSkills()` + `parseComponent()` over every skill, summing model-visible descriptions |
| `B_ALWAYS` (ADR-151) | 42,920 B | 42,920 B | **0 B** | `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` → `[OK] B_ALWAYS=42920` |

`B_ALWAYS` is untouched by construction; see ADR-151's 2026-09-21 addendum. On harnesses that ignore
the key (Codex), the 12 descriptions still load; each stays bounded by the per-skill 1024-character
test, which counts every skill.

### Headless-refusal policy

When an unattended run hits a Skill-tool refusal for a user-invoked skill, it stops and files an
`action-required` issue naming the command the operator must type. It never re-runs the skill's steps
by hand. The harness refusal itself says the same ("Do not replicate this skill's workflow by other
means"). `skill-creator/references/authoring-levers.md` carries the policy for skill authors.

### Adding a 13th user-invoked skill

Four sites move together in one reviewed diff: the exact-set pin and the ack table in
`invocation-axis.test.ts`, this ADR's list, and `SKILL_DESCRIPTION_WORD_BUDGET` (lowered by the skill's
description word count).

## Considered Options

| Option | Outcome |
|---|---|
| Flip all 16 skills the issue listed | Rejected: `flag-bootstrap` is not a skill; flipping `trigger-cron` breaks an always-loaded rule; flipping `invoice` strands the web founder; flipping `flag-list` hides a read-only audit the agent must pull |
| `user-invocable: false` | Rejected: the inverse axis (hides from the `/` menu, keeps the model) |
| Rewrite the 12 descriptions as short human-facing one-liners | Cut: the flag removes the description whatever its wording |
| A router skill for operator tooling | Not needed: `soleur:help` already lists every skill for the human and marks user-invoked ones |
| A separate operator plugin | Out of scope |
| Keep the cap at 2561 and leave 266 words of headroom | Not chosen: it lets the listing regrow to today's size without a reviewed bump |
| **Positive-phrasing rewrite of the always-loaded rule corpus** (peer's writing-for-agents) | B5_ROW_PENDING |

## Rollback triggers

Revert the 12 keys (the exact-set pin makes it an explicit edit) if any of these is observed:

- A Claude Code release hides a flagged plugin skill from the user (the upstream #92769 shape). Re-probe
  at each release through `soleur:model-launch-review`, and after this release through `soleur:postmerge`
  with the tmux TUI capture against the installed plugin.
- Devin stops listing a flagged skill as user-typeable.
- Codex starts honouring the key in a way that hides it from the user.

## Consequences

- Operator tooling is typed by the operator; the model hands the command over instead of running it.
- The web Command Center cannot reach the 12 skills; it says so and names the CLI command.
- The in-repo description budget tracks what the model sees, and a new skill description again needs a
  reviewed bump against a zero-headroom baseline.
