# Devin Cloud Probe — feat-devin-cloud-session-parity

**Status:** PARTIAL — run 2026-09-15 in an operator-launched Devin Cloud
session on this repo (web-app arm, `jikig-ai/soleur`, checkout at `main`
`cdee39de1`; session
`https://app.devin.ai/sessions/4c574cf0fa594527bb3f9650c05b74a7`). Items 1, 2,
4, 7–11, 13, 15 measured; item 3 measured-indirect; items 5, 6, 12, 14 not
measurable from this arm — see §Results. A feature-branch arm is still needed
to close 5 and 14, and a CLI arm to close 6.

Part of #8159. Tracked by #8172. Plan:
`knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md`
§Phase 0.

## Pre-probe credential determination (GDPR gate — REQUIRED FIRST)

Record before the session runs. If ANY limb is Jikigai's, escalate to CLO
*before* probing — D10 is pre-emptive, not post-hoc.

| Limb | Owner | Notes |
|---|---|---|
| Devin account (whose login runs the session) | Operator's Devin org `jean-deruelle-ca24688f494a`; operator login is on the `jikigai.com` domain | Operator to state whether that org is the Jikigai corporate tenant or the founder's personal tenant |
| Billing entity (whose seat/subscription) | _unrecorded — operator-only determination_ | Jikigai seat → CLO escalation |
| API keys reachable in-session (`ANTHROPIC_API_KEY`, Doppler creds, `GH_TOKEN`) | **None reachable.** An `env` name-scan matched only `DEVIN_DIR` and `DEVIN_DISABLE_HISTEXPAND`; `gh auth status` reports not logged in; git access is brokered by Cognition's proxy remote (`git-manager.devin.ai/proxy/github.com/...`) rather than a token held in the VM | Measured by variable **name**, never value. No Jikigai-issued key existed in the VM, so this limb does not trigger D10 on its own |

**Implementer-side partial observation (local session, 2026-09-14):** this
Devin CLI session's process env carries zero `DOPPLER`/`ANTHROPIC_API_KEY`/
`GH_TOKEN`/`GITHUB_TOKEN` variables. This says nothing about the cloud VM's
reachable creds or the account's billing entity — the operator must complete
the table.

**Cloud-side observation (2026-09-15):** the cloud VM likewise carries none of
those variables (row 3 above). The billing limb remains open.

## Art. 30 determination

The probe satisfies the register's purpose limb (Jikigai engineering purpose,
PA-35 precedent). Record ONE of:

- [ ] New PA-37 register entry (appended, per register convention)
- [ ] Written out-of-scope determination (record reasoning here)

Still operator/CLO-owned. The 2026-09-15 run narrows the input: the processing
reduced to reading the VM's own environment-variable **names**, the installed
plugin's lock metadata, and this repository's already-committed content. No
credential value was read (none existed), and no third-party personal data was
processed beyond the git authorship already in the repo.

## DPIA-screening note

One paragraph required: systematic description of the processing, necessity,
risk to third-party data subjects in repo content (git authorship, committed
digests), compensating measures. The probe must capture **non-identifying
environment signals only** — no personal data, no credential values, no
operator-identifying output beyond what git history already carries.

**Screening note (2026-09-15 run).** The processing was: enumerate
environment-variable *names* in the cloud VM's `exec` shell; read the Devin
plugin lock file (`/opt/.devin/plugins/lock.json` — repo URL, subpath, resolved
SHA); execute repo-local hook scripts against synthesised payloads; and write
then delete one marker path under `/tmp` plus one gitignored
`.devin/config.local.json`. It was necessary because the capability matrix, FR4
and FR5 are all keyed to whether Devin Cloud dispatches hooks at all, and no
documentation states that for repo-level `.devin/config.json`. Risk to
third-party data subjects is negligible: the only personal data in scope is git
authorship already committed to a repository the operator controls, and the one
operator-identifying value recorded above (Devin org slug and login domain) is
already carried by every commit. Compensating measures: no variable *values*
were printed, no secret store was queried, no production system was contacted,
no mutation left the VM, and both marker artefacts were removed in the same
session.

## Probe session scope

- One `/handoff` or web-app Devin Cloud session on this repo.
- Operator-credentialed test scope only.
- No personal data. No production mutations. Read-only probes + marker files.

## Checklist (record each item with evidence)

1. **Repo-level `SessionStart` hook** — does a `.devin/config.json`
   SessionStart hook fire in cloud? (Plugin SessionStart is
   documented-absent; repo-level is the unknown.) Evidence: marker file
   written by a test repo hook.
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

## Results — 2026-09-15 cloud run (web-app arm, checkout `main` `cdee39de1`)

Evidence convention: *measured* = observed in this cloud session; *indirect* =
derived from an observable session property rather than a purpose-built probe;
*not measurable here* = requires an arm this session was not.

**Headline: no hook of any kind fired in the cloud session.** That single
finding collapses items 1, 2, 4, 11, 13 and 14, and it is the load-bearing
input to FR4 and FR5.

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
   The `"Bash"`-vs-`exec` question is therefore moot **in cloud** and remains a
   live defect **locally**: per
   `/cli/extensibility/hooks/lifecycle-hooks#using-the-matcher` the matcher is a
   regex over `tool_name`, and Devin's shell tool is `exec`, which `"Bash"`
   never matches. `plugins/soleur/hooks/hooks.json` registered
   `matcher: "Bash"` for `browser-snapshot-credential-guard.sh` — a silent
   no-op on every Devin surface, local included. **Fixed in this branch** to
   `^(Bash|exec)$` (both surfaces), pinned by a regex-evaluating test in
   `plugins/soleur/test/devin-plugin.test.ts`; a presence grep would not have
   caught it, since `"Bash"` is present and still wrong.
   Corroboration that the scripts themselves are sound: invoking
   `.claude/hooks/guardrails.sh` directly with a synthesised `exec` payload for
   a direct commit to `main` returns `permissionDecision: "deny"` with the
   expected reason. The scripts work; the cloud surface never calls them.
5. **`requiredPlugins` — NOT MEASURED, and the planned placement looks wrong
   (doc finding).** This session ran on `main`, which carries no
   `requiredPlugins`, so the fresh-repo install path was not exercised.
   Separately, the config reference states `.devin/config.json` supports only
   `permissions`, `read_config_from` and `hooks`; `requiredPlugins` is a key of
   the **plugin manifest** (`.devin-plugin/plugin.json`) and of the **managed
   manifest** edited in the web app. Consistent with that, the plugin *was*
   installed in this session and `/opt/.devin/plugins/lock.json` attributes it
   to a **managed** origin scope (`git-subdir`, `github.com/jikig-ai/soleur`,
   path `plugins/soleur`, resolved `cdee39de1a7ad53ff86e42a500b79d037af66aa6`)
   — org-level governance, not repo config. **FR6 consequence:** putting
   `requiredPlugins` in `.devin/config.json` most likely installs nothing; the
   managed manifest is the placement with demonstrated effect. Confirm on the
   feature-branch arm before freezing FR6.
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
8. **`DEVIN*` env signals — only `DEVIN_DIR` and `DEVIN_DISABLE_HISTEXPAND`
   (measured).** `DEVIN`, `DEVIN_HOME`, `DEVIN_PROJECT_DIR` and
   `DEVIN_PLUGIN_ROOT` are all unset in the cloud `exec` shell.
   **Consequence for `cloud-detect.sh`:** the classifier returns
   `not-local:no-devin-env` in cloud — the right *verdict* by the wrong
   *reason*, and the identical verdict it would return on any non-Devin host.
   Do **not** add `DEVIN_DIR` to the recognised set: it is present in cloud, so
   treating it as a Devin-session signal flips the cloud reason to
   `sentinel-absent` (still non-local, but it stops distinguishing "no Devin
   env" from "Devin env without a local sentinel"). The sentinel stays the only
   positive local signal.
9. **Exec-shell propagation — yes, for what exists (measured).** `DEVIN_DIR`
   reaches `exec` subshells; there are no other Devin markers to propagate.
10. **Session ID — available to the agent, NOT in the exec environment
    (measured).** The session URL and a `devin-<uuid>` identifier are present in
    the agent's context, but no session-id variable exists in the `exec` shell.
    **Banner consequence:** a shell-side env-var session-boundary oracle is not
    implementable in cloud; use the stateless per-invocation form.
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
    SessionStart hook ran regardless. Re-check after merge.
15. **Unknown-key tolerance — PASS in cloud (measured).** With the extra
    gitignored `.devin/config.local.json` present, the session continued
    normally and config parsing raised nothing. Weak evidence for the *local*
    limb (cloud registers no hooks either way), so "does an unknown key break
    local hook registration" still needs a CLI run.

### Net effect on the design

- Cloud is not a degraded-hook environment; it is a **no-hook** environment.
  Every guardrail currently enforced by `.claude/hooks/guardrails.sh` or
  `plugins/soleur/hooks/hooks.json` is absent there, which puts FR5's
  extraction scope at its maximum: any guardrail that must hold in cloud has to
  live in skill text, not in a hook.
- The `"Bash"` matcher no-op (item 4) was a real *local* defect surfaced by
  this probe, independent of the cloud work; fixed here.
- `requiredPlugins` placement (item 5) should move to the managed manifest
  before FR6 is frozen.
- The banner needs the stateless per-invocation form (item 10), and FR4 should
  stay hard-defer (item 3).

## What the probe freezes

- **FR4** acknowledgement mechanism (interactive ask vs. hard-defer).
- **FR5** extraction scope (which guardrails actually need skill-internal
  restoration).
- **Capability-matrix rows** (Phase 4 — every row cites a doc anchor or a
  probe result).
- **Art. 30 amendment wording** (probe-informed keying by where each measure
  executes).
- **Banner session-boundary mechanism** (env oracle vs. stateless
  per-invocation).

## Deferral record

_If deferred:_ record the deferral issue number and the merge-readiness
consequence here (Phase 3 extraction scope, Phase 4 matrix rows, Phase 5
Art. 30 wording, and PR-ready status are all frozen on this file's
completion — `wg-block-pr-ready-on-undeferred-operator-steps`).

Not deferred; partially discharged. Residual operator-owned limbs from the
2026-09-14 gate that this run did **not** close: the billing-entity
determination, the Art. 30 register decision, and the CLO ceiling /
TC_VERSION / SC5 sign-offs. Residual measurement arms: feature-branch cloud
session (items 5, 14) and a CLI `/handoff` session (items 6, 12, and the local
limb of 15).
