# Devin Cloud Probe — feat-devin-cloud-session-parity

**Status:** SANDBOX-MEASURED 2026-09-15 — probe ran in a `devin cloud drs`
sandbox session (`devin-b9cf2c02cc8f49debdbc49ed72cdf2b5`,
<https://app.devin.ai/sessions/b9cf2c02cc8f49debdbc49ed72cdf2b5>), repo cloned
fresh at `main`, `/home/ubuntu/repos/soleur`. Evidence class: **sandbox** —
a DRS session may differ from a user-facing `/handoff`/web-app session; rows
marked *sandbox* below should be re-confirmed post-merge on a real session
(tracks #8172's residual scope).

Part of #8159. Tracked by #8172. Plan:
`knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md`
§Phase 0.

## Pre-probe credential determination (GDPR gate — REQUIRED FIRST)

Record before the session runs. If ANY limb is Jikigai's, escalate to CLO
*before* probing — D10 is pre-emptive, not post-hoc.

| Limb | Owner | Notes |
|---|---|---|
| Devin account (whose login runs the session) | **Jean Deruelle — personal** | Operator-confirmed 2026-09-14; `devin auth status` shows user Jean Deruelle, org `org-ca24688f494a49eea7e43e9eb57f2710` |
| Billing entity (whose seat/subscription) | **Personal** | Operator-confirmed 2026-09-14 — not a Jikigai seat |
| API keys reachable in-session (`ANTHROPIC_API_KEY`, Doppler creds, `GH_TOKEN`) | **Personal** — verified in-session during probe | No Jikigai-issued keys injected; see probe evidence |

No limb is Jikigai's → D10 not engaged; CLO escalation not required. Provider-operated session under the operator's own credentials for the operator's own purposes.

**Implementer-side partial observation (local session, 2026-09-14):** this
Devin CLI session's process env carries zero `DOPPLER`/`ANTHROPIC_API_KEY`/
`GH_TOKEN`/`GITHUB_TOKEN` variables. This says nothing about the cloud VM's
reachable creds or the account's billing entity — the operator must complete
the table.

## Art. 30 determination

The probe satisfies the register's purpose limb (Jikigai engineering purpose,
PA-35 precedent). Record ONE of:

- [ ] New PA-37 register entry (appended, per register convention)
- [x] **Written out-of-scope determination (2026-09-15):** the sandbox probe
  processed no personal data — inputs were a read-only checklist prompt and
  environment-inspection commands on a public-repo clone; outputs were
  capability signals (tool-catalog presence, env-var names, hook dispatch
  absence). No data subject's personal data was collected, stored, or
  transmitted beyond what the public repo already carries. The sole account
  limb is the operator's own personal Devin account (user-confirmed); no
  Jikigai machine, credential, or purpose limb attached to third-party
  personal data. Provider-operated configuration, user credentials, user
  purposes → outside the register's limb-keyed scope test on both limbs.

## DPIA-screening note

Systematic description: a single `devin cloud drs` sandbox session on a
Cognition-managed VM cloned `jikig-ai/soleur` at `main` (public repo), ran a
read-only capability checklist, and wrote a findings file read back over the
DRS run channel. Necessity: the findings gate merge-readiness for the Cloud
Mode contract — the legal floor and the disclosure claims rest on what the
cloud surface actually dispatches. Risk to third-party data subjects in repo
content (git authorship names, committed content): the clone is of a public
repository; the session captured environment metadata only, no file contents
beyond the two scripts fetched for the classifier test. Compensating
measures: no personal data requested or recorded, credential determination
completed and negative on all Jikigai limbs before launch, no production
mutations, no credential values captured (env names only). Residual risk:
minimal — the session type itself is the subject under test.

## Probe session scope

- One `/handoff` or web-app Devin Cloud session on this repo.
- Operator-credentialed test scope only.
- No personal data. No production mutations. Read-only probes + marker files.

## Checklist (record each item with evidence)

**Sandbox results, 2026-09-15** (session `devin-b9cf2c02cc8f49debdbc49ed72cdf2b5`;
agent-written record at `/tmp/probe-findings.md` in-session, corroborated by
`drs run` shell evidence):

1. **Repo-level `SessionStart` hook** — **does NOT fire** *(sandbox)*.
   No hook context reached the session; no sentinel written (the sentinel
   code isn't on `main`, but the hook's `additionalContext` output — plugin
   root + `devin/INSTRUCTIONS.md` — was absent from session-start context).
   Blueprint knowledge states verbatim: "Devin lifecycle hooks
   (.devin/config.json, plugin hooks) do NOT dispatch in cloud sessions —
   only Git-native hooks run there."
2. **Repo-level `PostToolUse`/`Stop`** — **do NOT fire** *(sandbox)*. Same
   blueprint statement; corroborated: after a `skill` tool call the
   `PreToolUse:Skill` logger produced no jsonl and `git status` stayed clean.
3. **`ask_user_question`** — **tool does not exist** *(sandbox)*. Absent from
   the 99-tool catalog. Equivalent is `message_user` with
   `content_type="user_question"` — always blocking, waits for a human reply,
   no auto-approve path. **FR4 frozen:** cloud acks cannot use
   `ask_user_question`; the contract's "explicit session-scoped
   acknowledgement" must be satisfied by an operator reply (blocking = fail
   closed in unattended sessions) or by proceeding only after an explicit
   go-ahead in the prompt — never an auto-answered question.
4. **Per-hook matcher binding** — moot *(sandbox)*: no hooks dispatch at all,
   so `Bash`-vs-`exec` matching never engages.
5. **`requiredPlugins`** — **not measurable pre-merge** *(partial)*. The
   plugin DID load — ~95 `soleur:*` skills + plugin `AGENTS.md` rules + MCP
   servers (cloudflare, context7, stripe, vercel) — from the account-level
   plugin cache `/opt/.devin/plugins/cache/github.com_jikig-ai_soleur_
   plugins_soleur-5a09ea60/0.0.0-unversioned/`. The account already has the
   plugin installed, so `requiredPlugins`' marginal effect on a fresh
   install can't be observed from this account. Post-merge verification on
   an account/session without the plugin installed remains #8172 scope.
6. **`/handoff` worktree sync** — **not measured** *(sandbox is a fresh
   clone, not a handoff)*. `.devin/config.json` arrived (it's tracked);
   whether gitignored files carry over via handoff stays open (#8172).
7. **`run_subagent` profiles** — **absent** *(sandbox)*. `run_subagent` is
   not in the tool catalog; nearest surfaces are `testing_agent`,
   `run_workflow`, `devin_session_create` (child sessions on separate VMs).
   Sequential-fallback contract is the correct degrade path.
8. **`DEVIN*` env signals** — exec-shell env carries only
   `DEVIN_DIR=/opt/.devin` and `DEVIN_DISABLE_HISTEXPAND` *(sandbox)*. No
   `DEVIN`, `DEVIN_HOME`, `DEVIN_PROJECT_DIR`, `DEVIN_PLUGIN_ROOT`, no
   `DEVIN_SESSION_ID`, no `CLAUDE*`, no `SOLEUR*`. `cloud-detect.sh` was
   widened to treat `DEVIN_DIR` as a Devin marker (post-probe fix —
   previously it would have mislabeled this VM `no-devin-env` instead of
   `sentinel-absent`).
9. **Exec-shell propagation** — `drs run` shells see the same env as the
   agent reported *(sandbox)*: `DEVIN_DIR` present, nothing else.
10. **Session ID** — reachable at `/opt/.devin/devin_id` (`devin-b9cf…b5`),
    **not** exposed as an env var *(sandbox)*. Banner session-boundary oracle
    can read that file if needed; stateless per-invocation remains the
    implemented choice.
11. **`.claude/settings.json` hooks** — **do NOT fire** *(sandbox)*. File
    exists and declares SessionStart/PreToolUse/PostToolUse; none ran (its
    `env.CLAUDE_CODE_EFFORT_LEVEL` is unset in the process env;
    `$CLAUDE_PROJECT_DIR` interpolations would have resolved to `/` — absent).
12. **`PostCompaction`** — **absent** *(sandbox)* per the same no-dispatch
    statement; not separately triggerable in the probe window. The
    PostCompaction-banner idea stays open (NG5 revision remains a spec note).
13. **Plugin command hooks** — **do NOT dispatch** *(sandbox)*. This
    *corrects* the plan-time framework-docs claim that `command` hooks run
    in cloud for non-SessionStart/End events: measured here, nothing ran.
    Caveat: sandbox class — re-verify on a real session (#8172).
14. **`hook_source`** — no hook ran → no sentinel → unmeasured. The field's
    design purpose stands: IF a future cloud build dispatches repo-level
    SessionStart, its sentinel must not classify local.
15. **Unknown-key tolerance** — verified locally pre-merge: `.devin/config.json`
    parses with `requiredPlugins` present; `devin doctor --json` clean.

**Bonus measurement:** `cloud-detect.sh` was exercised on the live VM via the
feature branch — `not-local:sentinel-absent` (post-widening) and `--banner`
emitted the full Cloud Mode banner to stderr, rc=0. The fail-closed degrade
path is verified end-to-end on a real cloud box.

## What the probe freezes — outcomes

- **FR4** acknowledgement mechanism — **frozen on "operator reply, never
  auto-answer"**: `ask_user_question` doesn't exist on the cloud surface;
  `message_user` is blocking. An ack gate in cloud halts until a human
  replies — fail-closed by construction.
- **FR5** extraction scope — **confirmed maximal**: NO hooks dispatch
  (repo `.devin/config.json`, `.claude/settings.json`, and plugin
  `hooks.json` all inert in the sandbox), so skill-internal backstops are
  the only enforcement that exists in cloud. `precommit-guard.sh` coverage
  is the right floor.
- **Capability-matrix rows** — now cite sandbox-measured results (see
  `devin/INSTRUCTIONS.md` §Cloud Mode).
- **Art. 30 amendment wording** — hook TOMs keyed as "local sessions;
  absent on provider-operated machines" is now measured-accurate, not
  just documented-absent.
- **Banner session-boundary mechanism** — no `DEVIN_SESSION_ID` env;
  `/opt/.devin/devin_id` is reachable if a per-session boundary is ever
  needed. Stateless per-invocation stands.

## Deferral record

Probe ran 2026-09-15 as a DRS sandbox — #8172 remains open for the residual
items that need a user-facing `/handoff`/web-app session or a clean account:

- re-confirm hook non-dispatch and `run_subagent`/`message_user` absence on
  a non-sandbox session;
- `requiredPlugins` marginal effect on an account without the plugin
  installed;
- `/handoff` gitignored-`.devin/` sync (sentinel-travel arm);
- post-merge SC1/SC3/SC4 verification session.

Merge-readiness consequence stands: PR-ready stays blocked until the
residual items are either measured or explicitly deferred on #8172 with the
disclosure wording unchanged.
