# Devin Cloud Probe — feat-devin-cloud-session-parity

**Status:** TWO-ARM MEASURED 2026-09-15 — the probe ran in two cloud
sessions on this repo:

- **Web-app arm** (user-facing): session `4c574cf0fa594527bb3f9650c05b74a7`
  (<https://app.devin.ai/sessions/4c574cf0fa594527bb3f9650c05b74a7>),
  checkout `main` `cdee39de1`. Evidence class: **user-facing**.
- **DRS sandbox arm**: session `b9cf2c02cc8f49debdbc49ed72cdf2b5`
  (<https://app.devin.ai/sessions/b9cf2c02cc8f49debdbc49ed72cdf2b5>), repo
  cloned fresh at `main`. Evidence class: **sandbox**.

The two arms agree on the load-bearing findings (no hook dispatch on any
surface; no `ask_user_question`; only `DEVIN_DIR`/`DEVIN_DISABLE_HISTEXPAND`
in the exec env). They diverge on `run_subagent` — see §Reconciliation.
Residual arms: a feature-branch session (items 5-marginal, 14) and a CLI
`/handoff` session (items 6, 12) — tracked by #8172.

Part of #8159. Tracked by #8172. Plan:
`knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md`
§Phase 0.

## Pre-probe credential determination (GDPR gate — REQUIRED FIRST)

Recorded before both sessions ran. If ANY limb is Jikigai's, escalate to CLO
*before* probing — D10 is pre-emptive, not post-hoc.

| Limb | Owner | Notes |
|---|---|---|
| Devin account (whose login runs the session) | **Jean Deruelle — personal** | Operator-confirmed 2026-09-14; org `org-ca24688f494a49eea7e43e9eb57f2710` (web-app arm observed the same org slug `jean-deruelle-ca24688f494a`). Operator confirmed this is the founder's personal tenant, not a Jikigai corporate tenant |
| Billing entity (whose seat/subscription) | **Personal** | Operator-confirmed 2026-09-14 — not a Jikigai seat |
| API keys reachable in-session (`ANTHROPIC_API_KEY`, Doppler creds, `GH_TOKEN`) | **None reachable** — measured in both arms | Env name-scan matched only `DEVIN_DIR` and `DEVIN_DISABLE_HISTEXPAND`; `gh auth status` not logged in; git access brokered by Cognition's proxy remote (`git-manager.devin.ai/proxy/github.com/...`) — no token held in the VM. Measured by variable **name**, never value |

No limb is Jikigai's → D10 not engaged; CLO escalation not required.
Provider-operated sessions under the operator's own credentials for the
operator's own purposes.

## Art. 30 determination

- [x] **Written out-of-scope determination (2026-09-15, covering both
  arms):** the probes processed no personal data — inputs were a read-only
  capability checklist and environment-inspection commands on a clone of a
  repo the operator controls; outputs were capability signals (tool-catalog
  presence, env-var names, hook dispatch absence, plugin lock metadata). No
  credential value existed to read (name-scan only), and no third-party
  personal data was processed beyond the git authorship already committed.
  The sole account limb is the operator's own personal Devin account
  (user-confirmed); no Jikigai machine, credential, or purpose limb attached
  to third-party personal data. Provider-operated configuration, user
  credentials, user purposes → outside the register's limb-keyed scope test
  on both limbs.

## DPIA-screening note

Processing (web-app arm): enumerate environment-variable *names* in the
cloud VM's `exec` shell; read the Devin plugin lock file
(`/opt/.devin/plugins/lock.json` — repo URL, subpath, resolved SHA); execute
repo-local hook scripts against synthesised payloads; write then delete one
marker path under `/tmp` plus one gitignored `.devin/config.local.json`.
Processing (sandbox arm): a `devin cloud drs` session cloned the repo at
`main`, ran the read-only checklist, and wrote a findings file read back over
the DRS run channel. Necessity: the capability matrix, FR4 and FR5 are all
keyed to whether Devin Cloud dispatches hooks at all, and no documentation
states that for repo-level `.devin/config.json`. Risk to third-party data
subjects is negligible: the only personal data in scope is git authorship
already committed to a repository the operator controls, and the one
operator-identifying value recorded above (Devin org slug) is carried by
every commit. Compensating measures: no variable *values* printed, no secret
store queried, no production system contacted, no mutation left the VMs, and
the marker artefacts were removed in-session.

## Probe session scope

- One `/handoff` or web-app Devin Cloud session on this repo.
- Operator-credentialed test scope only.
- No personal data. No production mutations. Read-only probes + marker files.

## Checklist (record each item with evidence)

1. **Repo-level `SessionStart` hook** — does a `.devin/config.json`
   SessionStart hook fire in cloud? (Plugin SessionStart is
   documented-absent; repo-level is the unknown.)
2. **Repo-level `PostToolUse`/`Stop` hooks** — same test with marker files.
3. **`ask_user_question` in an unattended cloud session** — auto-approve
   (fail-open), stall, or distinguishable unanswered/timeout? **Freezes the
   FR4 ack mechanism.**
4. **Per-hook, per-matcher binding** — `hooks.json` registers
   `matcher: "Bash"`; Devin's shell tool is `exec`. Verify each registered
   plugin hook individually — a matcher that never matches is a silent no-op.
5. **`requiredPlugins`** — does `.devin/config.json` `requiredPlugins`
   install the plugin in a fresh-repo cloud session? Does an unknown key
   break local hook registration? **Freezes FR6 placement.**
6. **`/handoff` worktree sync** — does handoff carry gitignored `.devin/`
   files to the cloud VM? (Determines whether a local sentinel can arrive
   foreign.)
7. **`run_subagent` built-in profiles** — do `subagent_explore`/
   `subagent_general` exist and produce artifacts? Artifact output, not
   invocation success (Cloud Routines lesson).
8. **`DEVIN*` env signals** — which markers exist in cloud and propagate to
   `exec` tool shells? Session-id env var available in exec context (banner
   session-boundary oracle)?
9. **Exec-shell propagation** — do env markers reach `exec` subshells?
10. **Session ID availability** — env var or otherwise reachable.
11. **`.claude/settings.json` hooks** — do repo-level Claude-format hooks
    fire?
12. **`PostCompaction` hooks** — documented cloud-capable; confirm. A
    PostCompaction hook re-emitting cloud-mode context would structurally
    solve banner loss + ack re-priming (requires spec NG5 revision —
    escalate, don't inherit).
13. **Plugin command hooks** — confirm actual execution (docs say yes —
    verify, don't assume).
14. **`hook_source`** — record `hook_source` from any sentinel written;
    distinguishes repo-config vs plugin registration.
15. **Unknown-key tolerance** — `.devin/config.json` parse behavior with
    `requiredPlugins` present, locally (can verify pre-merge without cloud).

## Results — web-app arm (user-facing, 2026-09-15, checkout `main` `cdee39de1`)

Evidence convention: *measured* = observed in this cloud session; *indirect* =
derived from an observable session property rather than a purpose-built probe;
*not measurable here* = requires an arm this session was not.

**Headline: no hook of any kind fired in the cloud session.** That single
finding collapses items 1, 2, 4, 11, 13 and 14, and it is the load-bearing
input to FR4 and FR5. Cloud is a *no-hook* environment, not a degraded-hook
one.

1. **Repo-level `SessionStart` — DOES NOT FIRE (measured).** `main`'s
   `.devin/config.json` registers `session-rules-loader.sh` on
   `startup|resume|clear|compact`. Its `additionalContext` — the 98-rule
   `AGENTS.rules.md` corpus — was absent from the session context; only the
   `AGENTS.md` pointer index was injected, and that arrives through Devin's own
   always-on rules mechanism, not the hook. Control: running the same script by
   hand in the same shell with a synthesised SessionStart envelope succeeded,
   emitting `[rules-loader] loaded: 98 of 98 rules` in `additionalContext`. The
   script is cloud-capable; the *dispatcher* is what is absent.
2. **Repo-level `PostToolUse`/`Stop` — no dispatcher (measured, by
   inheritance).** Neither is registered on `main`, and the item-4 marker test
   shows no tool-event dispatch at all, so a registration would have nothing to
   attach to.
3. **`ask_user_question` in an unattended cloud session — STALLS, does not fail
   open (indirect).** The cloud equivalent is a blocking `message_user`: the
   session suspends awaiting the operator, with no timeout and no auto-approval
   path; nothing in the cloud arm answers a blocking question on the operator's
   behalf. **FR4 consequence:** an interactive ack is *safe* — it can never be
   silently auto-approved — but it is not *live*: in an unattended run it
   converts the workflow into an indefinite halt. Hard-defer stays the correct
   FR4 default; interactive ack is admissible only where a halt is an
   acceptable outcome.
4. **Per-matcher binding — untestable in cloud because nothing dispatches
   (measured).** Direct test: a gitignored `.devin/config.local.json`
   registering a `PreToolUse` hook with `matcher: ""` (matches every tool name)
   writing a timestamp to `/tmp/probe-hook-marker`, followed by an `exec` call.
   The marker was never created. Two facts follow: cloud does not hot-reload
   hook config mid-session, and — with item 1 — no tool-event hook dispatch is
   reachable in cloud at all.
   The `"Bash"`-vs-`exec` question is therefore moot **in cloud** and was a
   live defect **locally**: the matcher is a regex over `tool_name`, and
   Devin's shell tool is `exec`, which `"Bash"` never matches.
   `plugins/soleur/hooks/hooks.json` registered `matcher: "Bash"` for
   `browser-snapshot-credential-guard.sh` — a silent no-op on every Devin
   surface, local included. **Fixed** to `^(Bash|exec)$`, pinned by a
   regex-evaluating test in `plugins/soleur/test/devin-plugin.test.ts` and a
   jq-level binding assertion in
   `.claude/hooks/browser-snapshot-credential-guard.test.sh`.
   Corroboration that the scripts themselves are sound: invoking
   `.claude/hooks/guardrails.sh` directly with a synthesised `exec` payload for
   a direct commit to `main` returns `permissionDecision: "deny"` with the
   expected reason. The scripts work; the cloud surface never calls them.
   **Sibling finding (not fixed here):** `.claude/settings.json` carries ~25
   `"Bash"` matchers with the same latent dead-under-Devin shape, but those
   hooks were built for Claude Code (`$CLAUDE_PROJECT_DIR` interpolations,
   Claude tool names) and activating them under Devin needs per-hook review —
   not a mechanical sweep. Tracked by #8205.
5. **`requiredPlugins` — marginal effect NOT MEASURED; placement is VALID
   (reconciled).** The plugin installed via the org **managed manifest** —
   `/opt/.devin/plugins/lock.json` attributes it to a `managed` origin scope
   (`git-subdir`, `github.com/jikig-ai/soleur`, path `plugins/soleur`,
   resolved `cdee39de1a7ad53ff86e42a500b79d037af66aa6`) — so the repo-level
   key's marginal effect cannot be observed on this account. The arm's
   initial doc-finding ("`.devin/config.json` accepts only `permissions`,
   `read_config_from`, `hooks`") is **corrected**: the plugins reference
   (`/cli/extensibility/plugins/overview`, §Inheritance and levels, level 3
   "Repo") documents `requiredPlugins`/`optionalPlugins`/`forbiddenPlugins`
   in a checkout's `.devin/config.json`, discovered by walking up from the
   working directory, "**in cloud sessions, from each cloned repository**".
   FR6 placement on `.devin/config.json` stands; what remains unmeasured is
   its marginal effect on an account where the managed manifest does not
   already install Soleur — feature-branch arm or a clean account (#8172).
6. **`/handoff` worktree sync — not measurable here.** This was a web-app
   session, not a handoff; the question needs the CLI arm.
7. **`run_subagent` built-in profiles — subagent fan-out EXISTS in cloud
   (measured, partial).** Cloud exposes background subagents (`read_subagent`
   documents `run_subagent` and a separate testing agent) and the
   `run_workflow` orchestrator that fans out to child sessions. Not verified:
   the specific `subagent_explore`/`subagent_general` profile names and
   artifact production — neither was spawned, so the Cloud Routines lesson
   (artifacts, not invocation success) is not yet discharged.
   **Plugin-defined** subagents remain documented-absent in cloud
   (`/product-guides/plugins#current-limitations`), so Soleur's `agents/**`
   roster is unavailable — but the fan-out substrate itself is not missing.
   See §Reconciliation for the sandbox-arm divergence.
8. **`DEVIN*` env signals — only `DEVIN_DIR` and `DEVIN_DISABLE_HISTEXPAND`
   (measured).** `DEVIN`, `DEVIN_HOME`, `DEVIN_PROJECT_DIR` and
   `DEVIN_PLUGIN_ROOT` are all unset in the cloud `exec` shell.
   `cloud-detect.sh` therefore recognised `DEVIN_DIR` as a Devin marker — see
   §Reconciliation for why that direction was kept over this arm's contrary
   recommendation.
9. **Exec-shell propagation — yes, for what exists (measured).** `DEVIN_DIR`
   reaches `exec` subshells; there are no other Devin markers to propagate.
10. **Session ID — available to the agent, NOT in the exec environment
    (measured).** The session URL and a `devin-<uuid>` identifier are present in
    the agent's context, but no session-id variable exists in the `exec` shell
    (sandbox arm: reachable at `/opt/.devin/devin_id`).
    **Banner consequence:** a shell-side env-var session-boundary oracle is not
    implementable in cloud; the stateless per-invocation form stands.
11. **`.claude/settings.json` hooks — no (measured, by inheritance from item
    4).** No hook dispatcher of any format is active in cloud.
12. **`PostCompaction` — not measurable here.** No compaction occurred, and
    with no observed dispatcher the documented cloud capability could not be
    confirmed. The "PostCompaction re-emits cloud-mode context" design must not
    be inherited on documentation alone: it now has contrary evidence from every
    other hook event and needs a dedicated arm.
13. **Plugin command hooks — do not fire (measured).** Same marker test as item
    4; nothing executed. What *did* survive into cloud is the useful half: all
    plugin **skills** loaded and are invocable as `/soleur:*`, and the plugin's
    `AGENTS.md` was injected as an always-on rule. Skills and rules are the
    cloud-durable surface; hooks and agents are not.
14. **`hook_source` — no sentinel was written (measured).** The installed plugin
    resolves to `cdee39de1` (`main`), which predates the sentinel writer, and no
    SessionStart hook ran regardless. On the current measurement the field is
    *unreachable* in cloud (no dispatcher), not merely unwritten — the design
    purpose stands as forward-defense: IF a future cloud build dispatches
    repo-level SessionStart, its sentinel must not classify local.
15. **Unknown-key tolerance — PASS (both limbs now covered).** Cloud: the
    extra gitignored `.devin/config.local.json` parsed without error. Local:
    `.devin/config.json` with `requiredPlugins` present parses clean
    (`devin doctor --json`), and local SessionStart hook registration is
    unaffected (the sentinel writer demonstrably fires locally).

## Results — DRS sandbox arm (2026-09-15, `devin-b9cf2c02cc8f49debdbc49ed72cdf2b5`)

Run earlier the same day via `devin cloud drs sandbox-create --repo
jikig-ai/soleur`; agent-side findings at `/tmp/probe-findings.md` in-session,
corroborated by `drs run` shell evidence. Corroborates the web-app arm on
every shared item; diverges only on item 7:

1. Repo `SessionStart` — does not fire (sandbox): no hook context, no
   `additionalContext`; blueprint states "lifecycle hooks do NOT dispatch in
   cloud sessions — only Git-native hooks run there."
2. Repo `PostToolUse`/`Stop` — do not fire; `PreToolUse:Skill` logger produced
   no output after a `skill` call.
3. `ask_user_question` — **absent from the 99-tool catalog**; `message_user`
   (`user_question`) is the only interactive primitive — blocking, no
   auto-approve.
4. Matcher binding — moot, nothing dispatches.
5. `requiredPlugins` — plugin loaded from account-level cache
   `/opt/.devin/plugins/cache/github.com_jikig-ai_soleur_plugins_soleur-*/`;
   ~95 `soleur:*` skills + plugin `AGENTS.md` rules + MCP servers (cloudflare,
   context7, stripe, vercel). Marginal effect unmeasurable — already installed.
6. Handoff sync — not measured (fresh clone, not a handoff).
7. **`run_subagent` — ABSENT in the sandbox tool catalog** (divergence — see
   §Reconciliation). Nearest surfaces: `testing_agent`, `run_workflow`,
   `devin_session_create`.
8. Env signals — identical to web-app arm: `DEVIN_DIR=/opt/.devin` +
   `DEVIN_DISABLE_HISTEXPAND` only. No `DEVIN_SESSION_ID`, `CLAUDE*`,
   `SOLEUR*`.
9. Exec propagation — `drs run` shells see the same env the agent reported.
10. Session ID — `/opt/.devin/devin_id` (`devin-b9cf…b5`); not an env var.
11. `.claude/settings.json` hooks — do not fire (file exists and declares
    SessionStart/PreToolUse/PostToolUse; none ran).
12. `PostCompaction` — absent per the same no-dispatch statement; not
    separately triggerable in the probe window.
13. Plugin command hooks — do not dispatch (corrects the plan-time
    framework-docs claim that `command` hooks run in cloud).
14. `hook_source` — no hook ran → no sentinel → unreachable in cloud.
15. Unknown-key tolerance — verified locally pre-merge (see item 15 above).

**Sandbox bonus measurement:** `cloud-detect.sh` was exercised on the live VM
from the feature branch — `not-local:sentinel-absent` and `--banner` emitted
the full Cloud Mode banner to stderr, rc=0. The fail-closed degrade path is
verified end-to-end on a real cloud box.

## Reconciliation across arms

- **`run_subagent` divergence.** Web-app arm: the tool exists (`read_subagent`
  documents it; `run_workflow` orchestrates child sessions). Sandbox arm:
  absent from the catalog. Likely cause: the DRS sandbox runs a reduced tool
  surface, or `subagents_enabled` differs per surface (the config key exists
  in `config.json`, default on). Either way, Soleur's `agents/**` roster is
  plugin-defined and documented-absent in cloud, so the sequential-fallback
  contract is unchanged; the matrix records the nuance.
- **`requiredPlugins` placement.** The web-app arm's initial doc-finding
  (`.devin/config.json` does not support the key) is corrected by
  `/cli/extensibility/plugins/overview` §Inheritance level 3, which documents
  repo-level `requiredPlugins` honored "in cloud sessions, from each cloned
  repository". The managed-manifest install it observed masks the marginal
  effect — unmeasured, not refuted.
- **`DEVIN_DIR` in `cloud-detect.sh`.** The web-app arm recommended *not*
  adding `DEVIN_DIR`, arguing it "stops distinguishing 'no Devin env' from
  'Devin env without a local sentinel'". That reasoning inverts: before the
  change, a cloud VM and a non-Devin host both classified
  `no-devin-env` — the indistinguishable case is the *old* behavior. Adding
  `DEVIN_DIR` is what separates them (`sentinel-absent` on a Devin box,
  `no-devin-env` on a non-Devin host). The verdict is `not-local` and
  fail-closed either way; the change only makes the *reason* accurate on a
  box where `/opt/.devin` demonstrably exists. Kept.
- **`"Bash"` matcher defect.** Surfaced by the web-app arm; the fix
  (`^(Bash|exec)$` + regex-evaluating tests) is ported onto this branch. The
  wider `.claude/settings.json` `"Bash"` class is tracked by #8205 —
  those hooks were built for Claude Code and need per-hook review before
  binding to `exec`.

## What the probe freezes — outcomes

- **FR4** acknowledgement mechanism — **frozen on "operator reply, never
  auto-answer"**: `ask_user_question` doesn't exist on the cloud surface;
  `message_user` is blocking. An interactive ack is *safe* (never silently
  auto-approved) but not *live* — in an unattended session it becomes an
  indefinite halt. Hard-defer is the default; interactive ack admissible only
  where halting is acceptable.
- **FR5** extraction scope — **confirmed maximal**: NO hooks dispatch on any
  surface (repo `.devin/config.json`, `.claude/settings.json`, plugin
  `hooks.json` — all inert, measured on both arms). Skill-internal backstops
  are the only enforcement that exists in cloud; `precommit-guard.sh`
  coverage is the right floor.
- **Capability-matrix rows** — cite the two-arm measured results (see
  `devin/INSTRUCTIONS.md` §Cloud Mode).
- **Art. 30 amendment wording** — hook TOMs keyed as "local sessions; absent
  on provider-operated machines" is now measured-accurate on the user-facing
  surface, not just documented-absent.
- **Banner session-boundary mechanism** — no `DEVIN_SESSION_ID` env;
  `/opt/.devin/devin_id` is reachable if a per-session boundary is ever
  needed. Stateless per-invocation stands.
- **FR6 placement** — `.devin/config.json` `requiredPlugins` stands
  (documented repo level); marginal effect deferred to the feature-branch /
  clean-account arm.

## Deferral record

Not deferred; discharged on two arms. Residual items tracked by #8172:

- `/handoff` gitignored-`.devin/` sync (item 6 — needs the CLI arm);
- `PostCompaction` dispatch (item 12 — needs an arm where compaction occurs);
- `requiredPlugins` marginal effect on an account without the managed
  manifest install (item 5 — feature-branch arm or clean account);
- `hook_source` remains unreachable in cloud by construction (no dispatcher)
  — its design purpose is forward-defense, not a measurement gap;
- post-merge SC1/SC3/SC4 verification session — discharged 2026-09-17 (see
  `## Post-merge verification` below); the SC4 marginal-effect arm remains on
  #8172 item 5 via follow-up #8257.

Residual operator-owned limbs the runs did not close: CLO ceiling /
TC_VERSION / SC5 sign-offs.

Merge-readiness consequence: probe-measured items are recorded above; the
remaining limbs are operator decisions or post-merge verifications, not
pre-merge measurements — per `wg-block-pr-ready-on-undeferred-operator-steps`
the deferred items are explicitly enumerated here and on #8172.

## Post-merge verification

**Session:** `devin-92db1c1f9e07498099bfafef02e1704a` (<https://app.devin.ai/sessions/92db1c1f9e07498099bfafef02e1704a>) — DRS sandbox created 2026-09-17T14:19Z, repo cloned at `main` `4dbd1affe8ebf6b72639c54fc167dc3dc25099bb`, plugin lock resolved `72fdff382361ae8c7ed2e3385e18fa8f6076d578` (both verified descendants of merge `6c1dbcbbcc36365b6db10a500827bedec0f2585e` via `git merge-base --is-ancestor`).
**Credential determination:** carried forward from §Pre-probe credential determination — personal account (`org-ca24688f494a49eea7e43e9eb57f2710`), no Jikigai limbs, D10 not engaged (`devin cloud drs whoami` re-affirmed 2026-09-17 — it re-verifies the org_id limb only; the billing-entity and reachable-credentials limbs carry forward from the 2026-09-14 determination).
**cloud-detect.sh on the real surface (operator-side `drs run`, not agent-reported):** `not-local:sentinel-absent` rc=0; `--banner` emitted the full 9-line capability block on stderr: yes. Env markers (names only): the operator-side probe greps `^DEVIN[A-Z_]*` only and returned `DEVIN_DIR` in the exec shell — it cannot observe the absence of other classes; the agent-side scan additionally observed `DEVIN_DISABLE_HISTEXPAND` and no `CLAUDE*`/`SOLEUR*`/credential vars. Delta vs the pre-merge arm (§Env-marker comparison above, which measured both names in the exec env) noted for completeness — different session/build, not a contradiction.
**Session disposition:** left suspended for audit (SC3 ack unanswered by design); operator may remove via `devin rm`. **#8228 remains open** — the sweeper's exit-5 assigns the close decision to the operator, and the issue explicitly forbids closing on partial coverage (SC4 PARTIAL).

| SC | AC | Verdict | Evidence |
|---|---|---|---|
| SC1 | #8228 AC13 | PASS | Banner quoted verbatim at go.md Step 0.5 (`CLAUDE_PLUGIN_ROOT` unset → `find /opt/.devin/plugins` recipe); `/soleur:go` routed to `soleur:brainstorm` and the stage completed (brainstorm doc written); `Reviewed-Coverage: sequential-fallback` present in the deliverable body + `reviewed_coverage` frontmatter |
| SC3 | #8228 AC14 | PASS | Step-3 marker appended 2026-09-17T14:23:27Z immediately before the secrets-class action; the findings log records the gate attribution verbatim — "`doppler` binary NOT installed in this sandbox (`command not found`); no `DOPPLER_*` env vars present" (pre-check) then "Cloud Mode rule 3 (acknowledgement gate) fired: blocking `message_user` ack requested before running `doppler secrets get SOLEUR_PROBE_NONEXISTENT --project soleur --config dev`. Awaiting operator response" — so the halt is gate-attributed, not timing-inferred (the missing binary was a recorded pre-check, not the cause); no Step-4 output for 10m57s observed (14:23:39→14:34:36Z) with `drs run` liveness confirming suspended-not-ended; second defer also recorded (`gh pr create` held on the same gate) |
| SC4 | #8228 AC15 | PARTIAL | 98 `soleur:*` skills exposed (99 on disk minus unsurfaced `flag-bootstrap`); `lock.json` records the repo-level `requiredPlugins` as a distinct `origin.scope:"repo"` requirement rooted at `/home/ubuntu/repos/soleur` (`source:"url"` = the `.devin/config.json` entry), resolving sha `72fdff38`; but a `managed`-scope requirement feeds the same resolution, so the marginal effect of the repo key alone remains unisolated — clean-account arm filed as follow-up, cross-ref #8172 item 5 |

Banner verbatim (from the session's findings log, matching the operator-side `--banner` capture):

```text
=== Soleur Cloud Mode — reduced-capability session ===
This Devin session is NOT running the local Soleur surface (reason: sentinel-absent — no local-session sentinel at .devin/soleur-local-session (plugin SessionStart never ran here)).
Absent surfaces:   plugin subagents (run_subagent / Task agent fan-out), ALL hooks
                   (SessionStart / SessionEnd / PreToolUse / PostToolUse / Stop — incl.
                   the credential guard, guardrails, and DONE-marker stop-gate)
Still available:   /soleur:* skills, AGENTS.md rules, MCP servers
Degrade path:      spawn-site skills run agent roles sequentially inline and disclose with
                   "Reviewed-Coverage: sequential-fallback" in the deliverable
Secrets/prod:      reads and mutations require an explicit cloud acknowledgement first
```

Deviations observed (recorded for completeness; none affect the verdicts):

- `worktree-manager.sh feature scratch-notes-line` created the worktree but refused to author commits: `SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=bot-global-refused` — the sandbox's only git identity is the `Devin AI` bot identity and the script declines to author as bot (CLA gate would bounce the commits anyway). Fail-safe, not a defect.
- `gh pr create` was deferred by the agent under Cloud Mode rule 3 (mutating GitHub call requires ack) — a second independent manifestation of the ack gate.
- `ask_user_question` confirmed absent on the cloud surface (consistent with the pre-merge probe).
