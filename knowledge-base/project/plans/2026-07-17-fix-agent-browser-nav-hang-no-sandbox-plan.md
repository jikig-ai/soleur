---
title: "fix: agent-browser navigation hang is a missing --no-sandbox flag, not a dead tool"
type: fix
date: 2026-07-17
branch: feat-one-shot-6605-agent-browser-nav-fix
closes: 6605
lane: procedural
brand_survival_threshold: none
status: ready
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: no infrastructure is provisioned. This change edits SKILL.md
docs, one preflight shell script, and a learning file. The `npm install --prefix ~/.local
-g agent-browser@...` lines are PRE-EXISTING local-CLI install documentation (a developer
tool, not a server/service/cron/secret/vendor/DNS/cert). "operator-driven" appears only in
a quoted issue caveat and a mitigation rationale. No .tf resource, cloud-init, or bootstrap
script is applicable. -->

# fix: agent-browser navigation hang (#6605) is a missing `--no-sandbox`, not a dead tool

## Overview

Issue #6605 reported "both browser-automation paths dead" and classified the failure
as `attempted-blocked-on-tool`, blocking an authorized Sentry billing write. Live
re-verification (2026-07-17) found the headline **half-wrong**:

- **Playwright MCP is not dead** — it navigated live pages on demand; the "tools
  de-register / cannot reload" symptom is a *transient* session-lifecycle event, not a
  permanent outage. The blocked billing write was completed through this path during
  verification (`onDemandMaxSpend` 5000→7500, confirmed by independent API read). That
  work is **already done** and is out of scope here.
- **`agent-browser` navigation is genuinely broken**, but not for the reason assumed.
  The 150s+ silent hang is a **missing `--no-sandbox` Chrome launch flag** on a host
  whose AppArmor policy restricts unprivileged user namespaces (Ubuntu 23.10+,
  containers, VMs). This is an environmental launch-gate, not a version regression.

The fix that restores navigation is the **`--no-sandbox` flag** — measured working on
the pinned 0.22.3 and on latest 0.32.1. A version bump is an *orthogonal* observability
improvement (0.32.1 fails loud in ~1s where 0.22.3 hangs silently for 150s), carrying
its own risk (see Risks) and therefore gated, not assumed.

## Research Reconciliation — Issue premise vs. measured reality

| Issue #6605 claim | Measured reality (2026-07-17, this host) | Plan response |
|---|---|---|
| "both browser-automation paths dead" | Playwright MCP works; only `agent-browser` fails | Scope to `agent-browser`; correct framing in PR body |
| "`agent-browser open` hangs / exits 1 with empty stdout+stderr" | Confirmed on **pinned 0.22.3**: 150s+ hang, 0 bytes both streams, even with `--debug` | Root-cause + fix |
| Implied: version drift (0.22.3 vs 0.32.1) | Installed 0.22.3 **is** the pinned version (`agent-browser/SKILL.md:20`); not drift | Version bump is optional/gated, not the fix |
| Implied: tool may need replacement / detection+fallback | Root cause is a **launch flag**; navigation works once `--no-sandbox` is passed | Config fix, not replacement |
| MCP "tools de-register" | More precise signature: browser **backend** closes between calls while the MCP **server** stays registered; recoverable by re-navigating; `ref=` handles do not survive, selector/name targeting does | Documented detection/recovery (D3) |

## Measured evidence (the decision matrix — MEASURED, not derived)

Per this skill's own Sharp Edge ("a claim about a VENDORED service's behavior is a claim
to MEASURE against the pinned image, never to derive") and the #6536 learning
("never mark a hypothesis CONFIRMED/REFUTED while its discriminator is invisible"), every
cell below was executed on this host, clean-slate (stale daemons killed, sockets cleared):

| Version | Launch flag | Result |
|---|---|---|
| 0.22.3 (pinned) | default | **HANG > 45s (timeout), 0 bytes stdout AND stderr** — even with `--debug` |
| 0.22.3 (pinned) | `--args "--no-sandbox"` | **EXIT=0, `✓ Example Domain`** |
| 0.22.3 (pinned) | `AGENT_BROWSER_ARGS="--no-sandbox"` (env) | **EXIT=0, `✓ Example Domain`** |
| 0.32.1 (latest) | default | **EXIT=1 in ~1s**, precise diagnostic (below) |
| 0.32.1 (latest) | `--args "--no-sandbox"` | **EXIT=0, navigation + ref-based snapshot (`ref=e1`, `ref=e2`) both work** |

The 0.32.1 default-mode diagnostic (the observability difference the version bump buys):

```
✗ Auto-launch failed: Chrome exited early (exit code: unknown) without writing DevToolsActivePort
Chrome stderr:
  [FATAL:zygote_host_impl_linux.cc:128] No usable sandbox! If you are running on
  Ubuntu 23.10+ or another Linux distro that has disabled unprivileged user namespaces
  with AppArmor, see .../apparmor-userns-restrictions.md ...
  Hint: try --args "--no-sandbox" (required in containers, VMs, and some Linux setups)
```

**Why Playwright MCP works but agent-browser does not on the same host:** Playwright
launches Chromium with the sandbox already handled; agent-browser's Rust daemon
auto-launches Chrome for Testing without `--no-sandbox`, so the zygote sandbox init
fails the launch.

**Architecture note (for the silent-hang half):** `agent-browser` is a prebuilt Rust
CLI + Rust daemon over Unix sockets (`/run/user/<uid>/agent-browser/<session>.sock`, PID
files in `/tmp/agent-browser/`). The daemon auto-starts on first command. The CLI has a
30s IPC read timeout for *operations* (README) — but the launch failure occurs during
**daemon/browser bootstrap**, before that timeout applies, and 0.22.3 does not surface
the early Chrome exit, so the CLI waits indefinitely with the daemon's stdout routed to
`/dev/null`.

## User-Brand Impact

- **If this lands broken, the user experiences:** agent-driven browser flows
  (`feature-video` recordings, `test-browser` E2E, `ops-provisioner`/`ops-research`
  fallback navigation) hang for 150s with no output, then fail with nothing to act on —
  and a robot-automatable task silently gets reclassified as a founder chore.
- **If this leaks, the user's data is exposed via:** N/A — no data surface; this is
  tooling guidance (SKILL.md docs + a preflight script) with no PII, secrets, or
  persistence.
- **Brand-survival threshold:** none — internal developer/agent tooling. No user-facing
  product surface; no sensitive path touched (threshold: none, reason: change is limited
  to `plugins/soleur/skills/*/SKILL.md` docs, one preflight `.sh`, and a learning file).

## Deliverables

### D1 — Restore navigation: document `--no-sandbox` (the measured fix)

Prescribe `AGENT_BROWSER_ARGS="--no-sandbox"` (env form, set once per session — cleanest;
the daemon reads it at launch) as the canonical setup, with `--args "--no-sandbox"` on the
first `open` as the inline alternative. Both are measured working on the **pinned 0.22.3**,
so this fix does **not** require a version bump and does **not** re-open the recurring
Playwright-version-mismatch risk.

Edit sites (all verified present via `git grep`):
- `plugins/soleur/skills/agent-browser/SKILL.md` — canonical usage doc + version-pin
  (`:14` check, `:20` install). Add a "Sandbox / no usable sandbox" **Troubleshooting**
  entry mirroring the existing "Version mismatch" block (`:28-33`), and add the
  `AGENT_BROWSER_ARGS` setup line ahead of the first `open` example (`:46`).
- `plugins/soleur/skills/test-browser/SKILL.md` — invokes `open` (`:142`), pins 0.22.3
  (`:52`). Add the setup line + a one-line cross-reference to the agent-browser
  Troubleshooting entry.
- `plugins/soleur/skills/feature-video/SKILL.md` — invokes `open` (`:176`). Add the
  setup line ahead of the recording flow + cross-reference.

### D2 — Make the failure diagnosable (silent-failure defect, `cq-silent-fallback-must-mirror-to-sentry`)

Two independent layers:

1. **Repo-side timeout + smoke test (primary, version-independent).** Extend
   `plugins/soleur/skills/feature-video/scripts/check_deps.sh` (today a `command -v`
   check only — it cannot catch the hang) with a **bounded** launch smoke test:
   `timeout 45 agent-browser open <about:blank-or-example> --headless` under
   `AGENT_BROWSER_ARGS="--no-sandbox"`, and on non-zero/timeout print an actionable
   message naming the AppArmor/userns cause and the `--no-sandbox` remedy. This converts
   a 150s silent hang into a bounded, diagnosable preflight failure regardless of
   agent-browser version — the boundary `cq-silent-fallback-must-mirror-to-sentry` wants
   to be loud. Keep the daemon-cleanup discipline (kill stray `agent-browser-linux-x64`,
   clear `/tmp/agent-browser`, `/run/user/<uid>/agent-browser`) documented so a wedged
   daemon is not misread as a launch failure.

2. **Optional version bump 0.22.3 → 0.32.1 (GATED — see Risks).** Upstream 0.32.1 already
   fails loud in ~1s with the exact diagnostic. Adopt **only if** /work verifies 0.32.1's
   bundled CDP/Chromium is compatible with the co-resident Playwright MCP Chromium in this
   env (the recurring-mismatch history). If incompatible, keep 0.22.3 + layer (1); the
   pinned version + `--no-sandbox` + the timeout smoke test already restore navigation and
   remove the silent-hang failure mode at our boundary. If adopted, sweep the pin across
   all sites: `agent-browser/SKILL.md:20`, `agent-browser/SKILL.md:14`,
   `test-browser/SKILL.md:52`, `knowledge-base/engineering/operations/skill-freshness.json`,
   `knowledge-base/project/learnings/2026-03-20-npm-global-install-without-sudo.md`.

### D3 — Document the MCP backend-close (observability, `hr-no-dashboard-eyeball-pull-data-yourself`)

Confirmed real **three times in the verification session** (backend closed twice with
`browserBackend.callTool: Target page, context or browser has been closed`; tools
de-registered once more). The emission site is the **Claude Code harness / Playwright MCP
server lifecycle — out of this repo** (verify in /work: `git grep` for any in-repo
Playwright-MCP lifecycle manager; expected: none). Honest deliverable is therefore a
**documented detection + recovery recipe**, not a fake in-repo code hook:

- Signature: `browserBackend.callTool: Target page, context or browser has been closed`
  (backend dropped) vs. "these deferred tools are no longer available" (server
  disconnected) — distinct causes.
- Recovery: **re-navigate** to recover; the backend restarts. Stale `ref=` handles do
  **not** survive the restart — use **name/selector targeting** (`button:has-text(...)`,
  `input[aria-label=...]`) across it.

Place in `plugins/soleur/skills/agent-browser/SKILL.md` Troubleshooting (it is the
canonical browser-tooling doc). If /work finds an in-repo emission site we control, add a
`SOLEUR_*` stdout marker there instead; otherwise record the out-of-repo boundary
explicitly so the next session does not chase a non-existent hook.

### D4 — Correct the misframing + capture the lesson

- A correcting comment is already posted on #6605. The `/ship` PR body will carry the
  corrected framing (Playwright works; agent-browser needs `--no-sandbox`; the billing
  write is done).
- Capture a compound learning: **a tool that failed once in one session is not a dead
  tool.** Probe before declaring an outage or reclassifying a robot-automatable task
  (`attempted-blocked-on-tool`) as a founder chore — the classification required *both*
  paths down; only one was. Reinforces
  `hr-verify-repo-capability-claim-before-assert` and the Playwright-first audit rule.

## Files to Edit

- `plugins/soleur/skills/agent-browser/SKILL.md` — `--no-sandbox` setup + Troubleshooting
  (sandbox launch + MCP backend-close); optional pin bump (gated).
- `plugins/soleur/skills/test-browser/SKILL.md` — setup line + cross-ref; optional pin bump.
- `plugins/soleur/skills/feature-video/SKILL.md` — setup line + cross-ref.
- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` — bounded launch smoke test
  + actionable failure message.
- `knowledge-base/engineering/operations/skill-freshness.json` — pin (only if bumping).
- `knowledge-base/project/learnings/2026-03-20-npm-global-install-without-sudo.md` — pin
  (only if bumping).

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/2026-07-17-agent-browser-hang-is-missing-no-sandbox-not-dead-tool.md`
  — compound learning (D4).

## Open Code-Review Overlap

None. (No open `code-review` issue names these files; check to be re-run at Step 1.7.5
against the finalized list.)

## Observability

```yaml
liveness_signal:
  what: feature-video check_deps.sh bounded launch smoke test (agent-browser open under timeout)
  cadence: on-demand (before any feature-video / test-browser recording run)
  alert_target: script stderr (non-zero exit) — operator/agent sees it inline, no dashboard
  configured_in: plugins/soleur/skills/feature-video/scripts/check_deps.sh
error_reporting:
  destination: script stderr with actionable AppArmor/userns + --no-sandbox message
  fail_loud: true (bounded by `timeout`; non-zero exit; never a silent 150s hang)
failure_modes:
  - mode: Chrome cannot launch (no usable sandbox / AppArmor userns restriction)
    detection: bounded `agent-browser open` smoke test exits non-zero or times out; on 0.32.1 the CLI prints the zygote FATAL + `--no-sandbox` hint
    alert_route: check_deps.sh stderr (no ssh, no dashboard)
  - mode: Playwright MCP backend closed between calls (server stays registered)
    detection: "`browserBackend.callTool: Target page, context or browser has been closed` string on the tool result"
    alert_route: documented recovery (re-navigate; use selector/name targeting, not stale ref=) in agent-browser SKILL.md Troubleshooting
  - mode: wedged/stale agent-browser daemon
    detection: stray `agent-browser-linux-x64` process + stale `/tmp/agent-browser/*.sock`; smoke test still fails after cleanup means genuine launch failure
    alert_route: documented cleanup step in SKILL.md Troubleshooting
logs:
  where: check_deps.sh stdout/stderr (ephemeral, inline to the invoking session)
  retention: none (preflight; not persisted)
discoverability_test:
  command: "AGENT_BROWSER_ARGS=\"--no-sandbox\" timeout 45 agent-browser open https://example.com --headless; echo EXIT=$?"
  expected_output: "EXIT=0 with the check-mark Example Domain line (NO ssh required)"
```

## Domain Review

**Domains relevant:** none

Internal developer/agent tooling change (SKILL.md docs + one preflight shell script + a
learning file). No user-facing product surface, no business-domain implications, no
regulated data, no new infrastructure.

- Product/UX Gate: NONE — no UI surface file in Files to Edit/Create.
- GDPR/Compliance (2.7): skip — no regulated-data surface.
- IaC (2.8): skip — no new server/service/secret/vendor/DNS/cert/cron. Ack comment in
  frontmatter records the reviewed opt-out.
- Architecture Decision (2.10): skip — no architectural decision. The two-browser-stack
  coexistence (Playwright MCP + agent-browser CLI) is a pre-existing established fact
  (QA-skill brainstorm 2026-03-26; ADR-049 records the agent-browser-vs-Playwright
  trade-off). This change adds a launch flag + docs; it neither reverses nor extends an
  ADR, and no future engineer would be misled about the architecture. C4 impact: none —
  no new external actor, external system, container, or access relationship (agent-browser
  and Playwright MCP are both already-modeled internal tooling; `--no-sandbox` is a launch
  parameter, not a system edge).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (measured fix, primary):** After the SKILL.md edits, a clean-slate
  `AGENT_BROWSER_ARGS="--no-sandbox" timeout 45 agent-browser open https://example.com --headless`
  exits 0 and prints the success line on the pinned 0.22.3. (Command is copy-pasteable
  from `agent-browser/SKILL.md`.)
- [ ] **AC2 (no silent hang):** `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
  detects a launch failure within its bounded timeout and prints a message naming
  `--no-sandbox`; it never hangs unbounded. Verify by running the script on a
  deliberately-broken invocation (e.g., `--args` that forces sandbox) and confirming a
  bounded non-zero exit with the actionable message.
- [ ] **AC3 (docs present):** `git grep -n "no-sandbox" plugins/soleur/skills/` returns
  hits in `agent-browser/SKILL.md`, `test-browser/SKILL.md`, and `feature-video/SKILL.md`.
- [ ] **AC4 (backend-close recipe):** `agent-browser/SKILL.md` Troubleshooting contains the
  `browserBackend.callTool: Target page, context or browser has been closed` signature and
  the re-navigate + selector-not-stale-ref recovery.
- [ ] **AC5 (learning captured):**
  `knowledge-base/project/learnings/bug-fixes/2026-07-17-agent-browser-hang-is-missing-no-sandbox-not-dead-tool.md`
  exists with the probe-before-declaring-dead lesson.
- [ ] **AC6 (version-bump gate honored):** If the pin was bumped to 0.32.1, every pin site
  (`git grep -n "agent-browser@0.22.3"` → 0.32.1) is updated AND a note records the
  Playwright-MCP Chromium compatibility check result. If NOT bumped, all pins stay 0.22.3
  and the plan's Risks rationale is cited in the PR body. (Either branch is acceptable;
  silence is not.)
- [ ] **AC7 (no product code / no infra):** `git diff --stat origin/main...HEAD` touches
  only `plugins/soleur/skills/**` (SKILL.md + check_deps.sh) and
  `knowledge-base/**` (learning + optional skill-freshness.json). No `apps/**`, no
  `*.tf`, no workflow YAML.

## Test Scenarios

1. **Fix verification (0.22.3 + env flag):** clean daemons → `AGENT_BROWSER_ARGS="--no-sandbox" timeout 45 agent-browser open https://example.com --headless` → EXIT=0, success line. (Measured OK.)
2. **Ref-API intact:** after (1), `agent-browser snapshot -c` returns `ref=`-bearing nodes. (Measured OK on 0.32.1; re-confirm on the shipped version.)
3. **Bounded failure on sandbox block:** force the sandbox (no `--no-sandbox`) → `check_deps.sh` smoke test returns non-zero within the timeout with the `--no-sandbox` message; never a 150s hang.
4. **Deliberately-unreachable URL:** `AGENT_BROWSER_ARGS="--no-sandbox" timeout 20 agent-browser open http://127.0.0.1:1 --headless` → bounded non-zero exit (not an unbounded hang).
5. **Version-bump compatibility (only if adopting 0.32.1):** install 0.32.1 in an isolated prefix, run `open` + `snapshot`, and confirm Playwright MCP still navigates in the same session (no Chromium-cache mismatch regression).

## Risks & Mitigations

- **Version bump re-triggers the recurring Playwright-version-mismatch (real history:
  plans 2026-03-20 + 2026-03-26 "permanently resolve recurring").** agent-browser and
  Playwright MCP share the Chrome-for-Testing cache; the 0.22.3 pin may be deliberate.
  *Mitigation:* the fix does **not** require the bump (`--no-sandbox` works on 0.22.3);
  treat the bump as gated on an explicit compatibility check, default to keeping 0.22.3.
- **`--no-sandbox` reduces Chrome's process isolation.** *Mitigation:* it is confined to
  agent-browser's own automation Chrome (headless, ephemeral, operator-driven, navigating
  operator-chosen URLs) — the same posture Playwright MCP already runs here; it does not
  touch the user's real browser. The upstream hint explicitly sanctions it for "containers,
  VMs, and some Linux setups." No broader isolation is being removed.
- **Host-specificity:** measured on the operator's host. *Mitigation:* the AppArmor
  userns restriction is common on modern Ubuntu/containers, and the fix is a no-op where
  the sandbox already works (`--no-sandbox` on an unrestricted host still launches). The
  smoke test makes any environment's actual state observable rather than assumed.

## Plan-review deviation note

This plan compresses the full multi-agent plan-review panel to a self-review against this
skill's Sharp Edges, because: (a) the change is docs + one preflight script + a learning
file (no product code, no infra, threshold `none`); (b) every behavioral claim is
**empirically measured** on-host (the decision matrix above), which is the exact class of
verification plan-review agents cannot add for a vendored-tool behavior; and (c) the
planning subagent was terminated by a transient API 529, making agent fan-out fragile this
session. The one-shot pipeline's `soleur:review` (Step 4) remains the substantive review
gate and is not skipped.
