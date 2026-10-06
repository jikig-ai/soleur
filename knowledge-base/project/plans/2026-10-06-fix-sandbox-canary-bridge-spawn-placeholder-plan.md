---
title: "fix: sandbox-canary capture projection — placeholder the SDK's HOME-derived bridge-spawn dir and refresh the stale fixture (#9614, #9618)"
type: fix
date: 2026-10-06
slug: sandbox-canary-bridge-spawn-placeholder
branch: feat-one-shot-9614-9618-canary-capture-fixture
issue: 9614
closes: [9614, 9618]
refs: [9570, 9559, 5913, 8623, 5875, 4932, 9601, 9599]
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: sandbox-canary capture projection — placeholder the SDK's HOME-derived bridge-spawn dir and refresh the stale fixture (#9614, #9618)

## Overview

The faithful sandbox canary cannot project the pinned SDK's bwrap argv: the
captured argv carries `--tmpfs <HOME>/.claude/bridge-spawn`, a host-HOME path
`normalizeCapturedArgv` deliberately refuses to bake into the committed fixture,
and no `${CANARY_*}` placeholder exists for it. Every `--capture`/`--verify`
run exits 4 with `verdict=canary_infra_error` `reason=projection_error:host_path`,
the committed fixture `apps/web-platform/infra/sandbox-canary-argv.json` sits
stale at `sdkVersion 0.3.197` while the pin is `0.3.284`, and the capture gate's
only fallback — a maintainer `sdk-bump-verified:` ack trailer — is unattestable,
so every PR touching a capture input is unmergeable on merit.

The fix mirrors the `${CANARY_C4_STAGING}` precedent (#8623 / ADR-079 2026-09-24
amendment): a fourth named placeholder `${CANARY_BRIDGE_SPAWN}` for the
SDK-internal HOME-derived dir, substituted in `runReplay` and listed in
`prepDirs`; the fixture re-captured in-image at 0.3.284; an ADR-079 amendment
recording the extension of the placeholder rule to SDK-internal paths; and the
premise-correction comment reverted on #9570 re-landed at
`server/agent-runner-sandbox-config.ts` (the `with Bash (kb-search greps)` site).

## Problem Statement / Motivation

- **#9614** — measured on 2026-10-06 (landing W1 of #9601, PR #9599): the repo's
  own in-image capture procedure (`node:22-slim` pinned digest, `npm ci`,
  `bun scripts/sandbox-canary.mjs --capture`) exits 4 on both the parent commit
  and the current tree with `projection_error:host_path`. The raw argv carries
  `--tmpfs /root/.claude/bridge-spawn`; the projection has no placeholder for it
  and the host_path guard (correctly) refuses to bake it. Fixture is stale at
  0.3.197 → deploy-time replay runs a stale argv and `--verify` cannot pass.
- **#9618** — found on PR #9570's CI (job `sandbox-canary-capture-gate`): the
  in-image `--verify` printed the same projection error, so the designed
  fallback demanded an `sdk-bump-verified:` ack for a 4-line comment-only edit
  with no SDK bump and no argv drift. Since the projection error is
  deterministic for the current capture environment, every PR touching
  `server/agent-runner-sandbox-config.ts`, `server/c4-staging-root.ts`,
  `scripts/sandbox-canary.mjs`, or `infra/sandbox-canary-argv.json` blocks on an
  ack nobody can honestly give — and the gate currently *incentivizes reverting
  doc fixes* in capture inputs (that is what happened on #9570).

One root cause, one PR.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

**Research agents used:** none spawned — `Reviewed-Coverage: sequential-fallback`
(this harness exposes no Task/subagent tool; premise validation, repo research,
learnings sweep, the domain sweep, and the ADR-corpus mechanism check were
executed inline by the orchestrator and are disclosed as such, never as
independent review).

**Premise Validation (Phase 0.6 — all held):**

- `gh issue view 9614` / `gh issue view 9618` — both `state: OPEN`,
  `meta/machinery` label; not closed by any merged PR.
- All six cited paths exist on this branch:
  `apps/web-platform/{infra/sandbox-canary-argv.json, scripts/sdk-bump-sandbox-gate.sh, scripts/sandbox-canary.mjs, server/agent-runner-sandbox-config.ts, server/c4-staging-root.ts, test/sandbox-canary.test.ts}`.
- Fixture staleness confirmed: `jq -r .sdkVersion
  apps/web-platform/infra/sandbox-canary-argv.json` → `0.3.197`; pinned is
  `0.3.284` (`apps/web-platform/package.json` +
  `node_modules/@anthropic-ai/claude-agent-sdk/package.json`).
- Capture-input trigger regex confirmed at
  `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh:186` (issue said "~line
  184" — close enough; the regex itself is at :186 inside the section-3 comment
  block).
- Premise-correction site is NOT in the gate script — it is
  `apps/web-platform/server/agent-runner-sandbox-config.ts:313`
  (`with Bash (kb-search greps)`). The exact replacement text is recoverable
  verbatim from the reverted commit `cdab1153` on PR #9570's branch:
  `with Bash retained as the\n  // deny+escalate tripwire (kb-search itself is
  Read/Grep/Glob-only, #9559), so the`.
- ADR-corpus check on the proposed mechanism (Phase 0.6 item 4): the named-
  placeholder mechanism is the *affirmed* pattern, not a rejected alternative —
  ADR-079's 2026-09-24 (#8623) amendment states the rule verbatim ("replaced by
  a named placeholder that is listed in `prepDirs` and substituted at replay").
  The rejected alternative adjacent to it — a projection rule that drops
  non-universal tokens — must NOT be revived: dropping `--tmpfs
  <bridge-spawn>` would silently shed a hardening mount, the over-drop class
  §2d exists to prevent.
- **New finding beyond the issues:** the bridge-spawn dir is SDK-internal —
  `claude` binary computes it as `join(homedir(), ".claude", "bridge-spawn")`
  (verified in the bundled `@anthropic-ai/claude-code-linux-x64` strings:
  `Xzn="bridge-spawn", e5=J6(homedir→z6(), ".claude", Xzn)`; the
  `ensureBridgeSpawnRootDir` mkdir wraps it). There is **no env override** —
  `CLAUDE_CONFIG_DIR` exists in the binary but the path is built from
  `homedir()` with a literal `".claude"` segment, not from the config dir.
  So the #8623 amendment's sub-rules (a) env-overridable and (b)
  mkdtemp-redirected *cannot* apply; the adaptation is to derive the path the
  same way the SDK does and pass it into the projection as a named root —
  the same shape `c4StagingRoot` already uses.

**Relevant file anchors (verified by read):**

- `apps/web-platform/scripts/sandbox-canary.mjs`:
  - `:583-589` — the three existing `CANARY_*_PLACEHOLDER` consts.
  - `:682-777` — `normalizeCapturedArgv` (`norm()` at :683-693; host_path throw
    at :759-765; `prepDirs` assembly at :767-774).
  - `:787-794` — `substituteCanonicalArgv`.
  - `:846-929` — `runReplay` (mkdtemp block :873-875; substitution :878-884;
    `hasUnsubstitutedPlaceholder` guard :887-897; prepDirs mkdir :901-907).
  - `:1020-1165` — `doCapture` (env save/restore for `C4_RENDER_STAGING_ROOT`
    at :1044-1051; result return at :1126-1134).
  - `:1231-1243` — `normalizeCapturedArgv` call + `projection_error:` mapping.
  - `:1246-1247` — emitted fixture `_comment` (lists the placeholders — must
    gain `${CANARY_BRIDGE_SPAWN}`).
- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh:58-67,87-92` —
  `SANDBOX_CANARY_MODE=capture` already exists and copies the fixture out via a
  writable `/out` mount; no helper change needed for the creds path.
- `.github/workflows/ci.yml:639-676` — the `sandbox-canary-capture-gate` job;
  dark-launch, creds-gated, runs `SDK_GATE_VERIFY_CMD: bash
  apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`. This PR touches
  two capture inputs, so the job WILL run on it — the closing proof for #9618.
- `apps/web-platform/Dockerfile:2,48` — base digest `node:22-slim@sha256:4f77…`
  matches the helper pin `sandbox-canary-verify-in-image.sh:41`. In sync.
- `apps/web-platform/test/sandbox-canary.test.ts`:
  - `:372-493` `normalizeCapturedArgv` describe; `:495-503`
    `substituteCanonicalArgv`; `:530-579` C4-staging placeholder block + the
    committed-fixture census (`known` placeholder list at :573);
    `:696-716` `countFdValuedOptions` — asserts the committed fixture carries
    **zero** fd-valued options; a 0.3.284 capture that keeps one breaks this
    (watch item below).

**Institutional learnings applied:**

- `cq-test-fixtures-synthesized-only` — the fixture must be re-captured by the
  real in-image procedure, never hand-edited (#4932 trap; the fixture
  `_comment` itself bans hand-authoring).
- `knowledge-base/project/learnings/workflow-patterns/2026-09-29-detached-precommit-watchdog-and-sdk-bump-attestation.md`
  — the `sdk-bump-verified:` attestation recipe context; this fix removes the
  *need* for the unattestable ack on capture-input PRs (the bump-ack arm of the
  gate — section 2 — is untouched and still governs real SDK bumps).
- Security learning
  `knowledge-base/project/learnings/security-issues/tenant-cli-render-executes-config-under-cwd-and-home-c4-render-20260924.md`
  (#8623) — the C4 staging root placeholder is the direct precedent.

**Related PRs/issues:** #5913 (capture machinery), #8623 (c4 placeholder +
host_path guard), #9570 (reverted premise correction — commit `cdab1153`),
#9599 (W1 credential-deny, OPEN — may land `--unsetenv` tokens in the argv;
merge-order watch item), #9601, #9559, ADR-079 (Deferral A still open —
status stays `adopting`).

**External research:** skipped — the defect, the fix pattern, and all evidence
are repo-internal; ADR-079 is the governing authority.

**Property List (Phase 0.6b):**

- P1 — `--capture`/`--verify` must be able to project the SDK-emitted
  `~/.claude/bridge-spawn` tmpfs token instead of dying on `host_path`.
- P2 — deploy-time replay must substitute the new placeholder to a real dir and
  pre-create it (`prepDirs`), or bwrap fails the replay under a read-only root.
- P3 — the committed fixture must be regenerated in-image at the pinned SDK
  (0.3.284) so the `--verify` byte-diff (`bwrapSetupArgv` + `prepDirs`) passes.
- P4 — the capture gate must stop demanding an unattestable ack on
  capture-input-touching PRs — a consequence of P1–P3, not a new mechanism.
- P5 — re-land the #9570-reverted premise correction in
  `agent-runner-sandbox-config.ts`.
- P6 — record the projection-contract extension in ADR-079.

**Cut List:** nothing in the ask is cut. Rejected-but-adjacent mechanisms that
must NOT appear in the plan: dropping the `--tmpfs` token (ADR-079 rejected
alternative B — the over-drop class); a generic `${CANARY_HOME}` prefix
placeholder (silently placeholders ANY future HOME path — defeats the #8623
fail-loud guard's deliberate-review property); narrowing the capture-input
trigger regex (not asked; the trigger is deliberately broad — a comment edit is
indistinguishable from an argv-shaping edit by grep).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "capture-input regex ~line 184" of the gate script | Regex is at `sdk-bump-sandbox-gate.sh:186` (the comment block :183-185 describes it) | Cite :186 |
| premise correction reverted "in the gate script context" | Site is `agent-runner-sandbox-config.ts:313`; the gate script itself carries no such text | Edit the ts file; exact replacement recovered from `cdab1153` |
| "has no placeholder for it" | True — `norm()` maps only `wsRoot`/`c4StagingRoot` (:683-693) | Add `bridgeSpawnRoot` opt + `${CANARY_BRIDGE_SPAWN}` |
| fixture stale at 0.3.197 | Confirmed; pinned 0.3.284 | Re-capture in-image (Phase 4) |
| "no placeholder for a HOME-based directory" — implies C4-style env override possible | No env override exists for the SDK-internal dir (`join(homedir(), ".claude", "bridge-spawn")`) | Adapt the rule: derive the SDK-known path via `homedir()` in `doCapture` and pass it to the projection; record the adaptation in the ADR amendment |

## Proposed Solution

Extend the canonical projection with a fourth named placeholder,
`${CANARY_BRIDGE_SPAWN}`, for the SDK-internal
`<homedir>/.claude/bridge-spawn` dir — mirroring `c4StagingRoot` end-to-end:

1. **`sandbox-canary.mjs`** — add `CANARY_BRIDGE_SPAWN_PLACEHOLDER`; extend
   `normalizeCapturedArgv` opts with `bridgeSpawnRoot` and map it in `norm()`
   (exact dir + subpaths); append the placeholder to `prepDirs` when it appears
   in `out` (same conditional as C4 — bwrap cannot `--tmpfs` a path it cannot
   create under a read-only root); extend `substituteCanonicalArgv` with
   `bridgeSpawn`; `runReplay` mkdtemps `canary-replay-bridge-spawn-*` and passes
   it to both substitution calls; `doCapture` computes
   `bridgeSpawnRoot = join(homedir(), ".claude", "bridge-spawn")` — the same
   expression the bundled CLI evaluates — returns it on the ok branch, and
   `runCapture` passes it through. Update the emitted `_comment` placeholder
   list. `homedir` joins the existing `node:os` import.
2. **`test/sandbox-canary.test.ts`** — new describe covering: mapping of the
   dir + subpaths; `prepDirs` inclusion; round-trip substitution (and
   `hasUnsubstitutedPlaceholder` true when `bridgeSpawn` is omitted); the
   fail-loud pin — the token STILL throws `host_path` when `bridgeSpawnRoot`
   is not supplied; committed-fixture census gains the placeholder in `known`
   and an exact-once `--tmpfs ${CANARY_BRIDGE_SPAWN}` assertion.
3. **`agent-runner-sandbox-config.ts:313`** — re-land the reverted correction
   verbatim.
4. **Fixture re-capture** in-image at 0.3.284 (`SANDBOX_CANARY_MODE=capture`),
   then in-image `--verify` → `verify_ok`.
5. **ADR-079 amendment** — dated 2026-10-06, recording that SDK-internal
   HOME-derived dirs get named placeholders via a capture-computed root (the
   env-override/mkdtemp sub-rules apply only to our own modules' paths).

## Implementation Phases

### Phase 1 — failing tests (cq-write-failing-tests-before)

1.1. `test/sandbox-canary.test.ts`: import `CANARY_BRIDGE_SPAWN_PLACEHOLDER`;
add a `describe("bridge-spawn placeholder (#9614/#9618)")` block:

- maps `"/root/.claude/bridge-spawn"` (and a `/sub` subpath) to
  `${CANARY_BRIDGE_SPAWN}` when `bridgeSpawnRoot` is passed, and pushes it to
  `prepDirs`;
- `substituteCanonicalArgv` with `bridgeSpawn` replaces it; with it omitted,
  `hasUnsubstitutedPlaceholder` is true;
- **without** `bridgeSpawnRoot`, `"--tmpfs", "/root/.claude/bridge-spawn"`
  still throws `/host_path/` (fail-loud preserved — the placeholder is a named
  contract, not a blanket HOME pass-through);
- extend the committed-fixture census (`known` array) with the new
  placeholder and assert `--tmpfs ${CANARY_BRIDGE_SPAWN}` appears exactly once
  and `prepDirs` contains it — this row stays RED until Phase 4's re-capture
  lands the refreshed fixture (deliberate: it pins the deliverable).

1.2. Run `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts` —
expect the new assertions RED (`CANARY_BRIDGE_SPAWN_PLACEHOLDER` not exported /
no mapping). The package's test runner is vitest (`package.json` `test`/`test:ci`
scripts; verified against `apps/web-platform/vitest.config.ts` collect globs
`test/**/*.test.ts` at plan time).

### Phase 2 — projection + replay implementation

2.1. `sandbox-canary.mjs` edits (anchors above):

- `export const CANARY_BRIDGE_SPAWN_PLACEHOLDER = "${CANARY_BRIDGE_SPAWN}";`
  beside the C4 const, with a `#9614`/`#9618` comment noting the dir is
  SDK-internal (`join(homedir(), ".claude", "bridge-spawn")`, no env override).
- `norm()`: `if (bridgeSpawnRoot && (p === bridgeSpawnRoot ||
  p.startsWith(`${bridgeSpawnRoot}/`))) return CANARY_BRIDGE_SPAWN_PLACEHOLDER
  + p.slice(bridgeSpawnRoot.length);`
- `prepDirs`: `if (out.some((t) => typeof t === "string" &&
  t.startsWith(CANARY_BRIDGE_SPAWN_PLACEHOLDER)))
  prepDirs.push(CANARY_BRIDGE_SPAWN_PLACEHOLDER);`
- `substituteCanonicalArgv(argv, { ws, empty, c4Staging, bridgeSpawn })`:
  `if (bridgeSpawn !== undefined) out =
  out.split(CANARY_BRIDGE_SPAWN_PLACEHOLDER).join(bridgeSpawn);`
- `runReplay`: `const bridgeSpawn = mkdtempSync(join(tmpdir(),
  "canary-replay-bridge-spawn-"));` and pass `bridgeSpawn` into both
  `substituteCanonicalArgv` calls (argv + prepDirs).
- `doCapture`: `const bridgeSpawnRoot = join(homedir(), ".claude",
  "bridge-spawn");` (no realpath — match the SDK's own raw `homedir()`-join
  byte-for-byte), include it on the `ok: true` return, and have `runCapture`
  forward `bridgeSpawnRoot` into `normalizeCapturedArgv`.
- Emitted fixture `_comment`: add `${CANARY_BRIDGE_SPAWN}` to the placeholder
  list.

2.2. `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts` —
unit assertions green; the committed-fixture census row still RED (expected
until Phase 4).

### Phase 3 — premise correction re-land

3.1. `agent-runner-sandbox-config.ts:313` — replace the single comment line

```
// `--ro-bind / /` (whole FS readable) with Bash (kb-search greps), so the
```

with the two-line form recovered verbatim from reverted commit `cdab1153`:

```
// `--ro-bind / /` (whole FS readable) with Bash retained as the
// deny+escalate tripwire (kb-search itself is Read/Grep/Glob-only, #9559), so the
```

### Phase 4 — in-image re-capture + verify (the creds-gated step)

4.1. From the **worktree root** (`SANDBOX_CANARY_MODE=capture` mounts
`$PWD/apps/web-platform/infra` as `/out` and copies the refreshed fixture back
into the worktree):

```bash
cd <worktree-root>
ANTHROPIC_API_KEY="$(doppler secrets get ANTHROPIC_API_KEY --project soleur --config ci --plain)" \
  SANDBOX_CANARY_MODE=capture \
  bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh
```

- `ANTHROPIC_API_KEY` is a repo secret (`ci.yml:671`) and is present in Doppler
  `soleur/ci` (verified readable at plan time). One bounded paid Haiku turn —
  the cost already disclosed by the capture design (`CAPTURE_MODEL =
  claude-haiku-4-5`, `maxTurns: 2`, ≤3 attempts × 120s).
- Fallback if creds are unavailable in the work env: the #9614 measurement ran
  against a scripted API stand-in — the bundled CLI honors `ANTHROPIC_BASE_URL`;
  the stand-in serves one canned `tool_use` (Bash) then an `end_turn`. Only
  build this if the creds path is genuinely blocked — it needs an env
  passthrough in `sandbox-canary-verify-in-image.sh` and is NOT prescribed by
  default.
- If the fresh 0.3.284 capture throws `host_path` on a *different* token, or
  `unrecognized_option` on a new bwrap flag, iterate deliberately per the
  ADR-079 rule: each new HOME-derived dir gets its own named placeholder (or a
  justified drop) — never weaken the guard to get green.

4.2. Re-run with `SANDBOX_CANARY_MODE=verify` → expect
`{"verdict":"verify_ok","reason":"ok","sdkVersion":"0.3.284"}`.

4.3. Inspect the refreshed fixture diff: `sdkVersion` → `0.3.284`; argv gains
`--tmpfs ${CANARY_BRIDGE_SPAWN}`; `prepDirs` gains the placeholder; every other
delta is whatever 0.3.284 actually emits (review it — do not hand-edit; a
suspicious token is a finding, not an edit).

### Phase 5 — ADR-079 amendment + fixture-census green

5.1. Append to ADR-079 (after the 2026-09-24 amendment):

> ## Amendment — 2026-10-06 (#9614/#9618): SDK-internal HOME-derived dirs are
> placeholdered via a capture-computed root
>
> SDK 0.3.284 emits `--tmpfs <homedir>/.claude/bridge-spawn` — an SDK-internal
> dir (`join(homedir(), ".claude", "bridge-spawn")` in the bundled CLI; no env
> override exists, so the 2026-09-24 rule's sub-clauses (a)/(b) cannot apply).
> The projection gains `${CANARY_BRIDGE_SPAWN}`, mapped from a
> `bridgeSpawnRoot` `doCapture` derives with the same `homedir()` expression
> the SDK evaluates. The host_path fail-loud guard is unchanged: any OTHER
> `/root`|`/home` token still throws. Status stays `adopting` (Deferral A).

5.2. `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts` —
fully green, including the committed-fixture census.

## Files to Edit

- `apps/web-platform/scripts/sandbox-canary.mjs` — placeholder const, `norm()`
  arm, `prepDirs`, `substituteCanonicalArgv`, `runReplay` mkdtemp+args,
  `doCapture` compute+return, `runCapture` pass-through, `_comment`.
- `apps/web-platform/test/sandbox-canary.test.ts` — import + new describe +
  committed-fixture census update.
- `apps/web-platform/server/agent-runner-sandbox-config.ts:313` — premise
  correction (comment only; exact text above).
- `apps/web-platform/infra/sandbox-canary-argv.json` — **regenerated by Phase
  4's in-image capture; never hand-edited** (#4932 trap).
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
  — dated amendment block.

## Files to Create

- None.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Drop the `--tmpfs <bridge-spawn>` token in the projection | Rejected | ADR-079 rejected alternative B — silently shedding a *hardening* mount is the over-drop class the §2d guard exists to prevent; also hides the token from drift detection |
| Generic `${CANARY_HOME}` prefix placeholder over all of `$HOME` | Rejected | Any future HOME-derived path would auto-placeholder instead of tripping the fail-loud host_path guard — destroys the deliberate-review property the #8623 amendment added |
| Redirect `HOME`/`CLAUDE_CONFIG_DIR` to a mkdtemp during capture | Rejected | `CLAUDE_CONFIG_DIR` does not govern this path (verified: literal `join(homedir(), ".claude", "bridge-spawn")`); mutating `HOME` redirects the CLI's settings/session writes too — a less faithful capture environment and a bigger blast radius than the fix needs |
| Narrow the capture-input trigger regex so comment-only edits skip the gate | Rejected | Not asked; grep cannot distinguish a comment edit from an argv-shaping edit in the same file — the trigger is deliberately over-broad, and with the projection fixed the gate simply passes |
| Scripted API stand-in instead of real creds for the re-capture | Conditional fallback only | The committed machinery already does creds capture; building stub-API plumbing to save one Haiku turn is not worth it — revisit only if `ANTHROPIC_API_KEY` is unavailable |

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user-facing surface
  — the failure shapes are CI-visible (a red `sandbox-canary-capture-gate` on
  capture-input PRs) or a non-blocking `canary_infra_error` verdict in the
  dark-launch deploy replay. The canary's soak does not silently green: a
  wrong fixture fails `--verify` byte-diff at merge and `unsubstituted_
  placeholder`/`projection_error` at replay.
- **If this leaks, the user's data is exposed via:** no new exposure vector —
  the placeholder substitutes a tmpfs mount *target* (a path, not content);
  the secret-scrub stages and the image-baked fixture trust path are
  unchanged.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** meta/machinery only — the blast
  radius of a defect here is a CI block or a dark-launch canary infra error,
  not tenant data or a broken user session; the tenant-isolation surface the
  canary *measures* is untouched by this diff.
- *Scope-out override:* `threshold: none, reason: diff touches
  apps/web-platform/server/agent-runner-sandbox-config.ts (comment-only) and
  apps/*/infra/ (the regenerated fixture) — sensitive by path but the change is
  verification machinery with no user-facing or tenant-data surface.`

**GDPR gate (Phase 2.7):** skipped — no schema/migration/auth/API/`.sql`
surface, and none of triggers (a)–(d): no new processing of operator-session
data, threshold is not `single-user incident`, no new cron reading
learnings/specs, no new artifact-distribution surface.

## Observability

The touched surface is the agent-bwrap-sandbox capture/replay pipeline — a
listed blind surface (Phase 2.9.2). No NEW observability surface is added; the
block documents how the existing in-surface verdict probes discriminate the
failure modes this change touches. Each `detection` is emitted FROM the
capture/replay itself (`emitVerdict` single-line JSON on stdout), not a
host-side proxy.

```yaml
liveness_signal:
  what: "sandbox-canary verdict JSON (capture/verify in CI; replay per deploy)"
  cadence: "per PR touching a capture input (ci.yml sandbox-canary-capture-gate) + per deploy (ci-deploy.sh run_faithful_sandbox_canary)"
  alert_target: "CI job output (::error/::warning annotations) + deploy-state on /hooks/deploy-status + Sentry on faithful FAIL"
  configured_in: "apps/web-platform/scripts/sandbox-canary.mjs emitVerdict + apps/web-platform/infra/ci-deploy.sh write_sandbox_canary_state + .github/workflows/ci.yml sandbox-canary-capture-gate"

error_reporting:
  destination: "CI annotations (gate) / deploy-state file + Sentry web-platform (deploy replay FAIL)"
  fail_loud: "verdict=canary_infra_error with discriminating reason; argv_drift hard-blocks the gate; sandbox_broken pages via Sentry"

failure_modes:
  - mode: "fixture stale vs pinned SDK (post-merge drift)"
    detection: "in-surface verdict reason=argv_drift from in-image --verify (byte-diff of bwrapSetupArgv+prepDirs)"
    alert_route: "CI gate ::error — blocks the PR"
  - mode: "projection cannot express a captured token (new HOME-derived dir, new bwrap option)"
    detection: "in-surface verdict reason=projection_error:host_path | unrecognized_option — names the token on stderr"
    alert_route: "CI gate ::warning → ack-fallback (never silent-green)"
  - mode: "a placeholder survives to replay (substitution gap)"
    detection: "in-surface verdict reason=unsubstituted_placeholder in runReplay (post-substitution census before spawn)"
    alert_route: "deploy-state sandbox_canary_json + CI --verify"
  - mode: "capture creds absent / model turn fails"
    detection: "reason=creds_absent | capture_no_bwrap:* | capture_error:* — distinct from argv_drift so the ack-fallback is never mistaken for drift"
    alert_route: "CI gate ::warning → sdk-bump-verified ack fallback"

logs:
  where: "CI job log (gate); deploy-state json + pino 'agent-sandbox' container logs; Sentry events tagged feature=agent-sandbox op=sandbox-canary"
  retention: "CI retention per repo; Sentry project retention"

discoverability_test:
  command: jq -r '"status=" + .status + " sdk=" + .sdkVersion' apps/web-platform/infra/sandbox-canary-argv.json
  expected_output: "status=captured"
```

**Soak Follow-Through Enrollment:** not triggered — no AC declares a
post-deploy time-gated close criterion.

## Guard Contract

The deliverable amends two existing controls and adds placeholder-contract
assertions — one guard entry covers the projection contract the diff changes.

### Guard 1 — canonical-projection placeholder contract

**Property.** No literal capture-host path (`/root`, `/home`, ws-root,
staging-root, bridge-spawn root) is baked into the committed fixture — every
one is either dropped (host binds, env forwarding) or mapped to a named
`${CANARY_*}` placeholder that `prepDirs` carries and `runReplay` substitutes;
any `${CANARY_*}` token reaching replay unsubstituted fails visibly.

**Assembly.** The projection is the single chokepoint: every kept token of the
captured argv flows through `normalizeCapturedArgv`'s `norm()` + the post-loop
host_path census (`sandbox-canary.mjs:759-765`), and every replayed token flows
through `substituteCanonicalArgv` + `hasUnsubstitutedPlaceholder`
(`:787-799,887-897`). The committed-fixture census test
(`test/sandbox-canary.test.ts` — `known` placeholder allowlist + no-`/root|/home`
assertion + exact-once token counts) is the drift-check pinning the artifact.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `bridgeSpawnRoot` arm from `norm()` while capture still emits `--tmpfs <home>/.claude/bridge-spawn` | RED — projection throws `host_path` and the new describe's mapping test fails |
| 2 | Map the token to the placeholder but drop the `prepDirs` push (guard's own bookkeeping: argv placeholdered, prep dir missing) | RED — prepDirs-inclusion test fails; a real replay would hit `bwrap: Can't mkdir` under a read-only root |
| 3 | `substituteCanonicalArgv` never substitutes the new placeholder (second member added after compliant ones — `${CANARY_WS}`/`${CANARY_EMPTY}`/`${CANARY_C4_STAGING}` still substitute) | RED — `hasUnsubstitutedPlaceholder` census test fails, mirroring the replay-time guard |
| 4 | (harness) Stub the committed-fixture census `known` list to accept ANY `${CANARY_*}` token | RED — a fixture carrying a bogus `${CANARY_BOGUS}` token must fail the allowlist check, proving the census is not vacuous |
| 5 | (must-pass) A captured argv with NO bridge-spawn token (older SDK) projects cleanly with `bridgeSpawnRoot` set | PASS — the opt is conditional; absence adds nothing to `prepDirs` |

**Anchor.** The fixture the guard protects is regenerated by the in-image
capture from the pinned SDK — a weakened projection cannot pass `--verify`
without ALSO changing what the SDK emits (outside the commit), and the gate's
own in-image `--verify` on this PR is the merge-time enforcement.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — this harness exposes no Task/subagent spawn; the
assessment below is the orchestrator's, carrying the same content the CTO-lens
pass would: mechanism minimality, chokepoint correctness, rejected-alternative
discipline)

**Assessment:** the fix is the ADR-079 #8623 pattern applied to a new token
class — the cheapest correct mechanism because the projection already owns the
normalize/substitute chokepoints and the placeholder vocabulary. No new
machinery: no env override exists for the SDK-internal dir, so `doCapture`
derives it with the identical `join(homedir(), ".claude", "bridge-spawn")`
expression — captured-env == replay-env invariant preserved by running capture
in-image. The alternatives table records the three rejected shapes (drop, generic
HOME placeholder, env redirect) so they cannot be re-proposed. Residuals named,
not closed: a future SDK version emitting a *different* `$HOME` dir still
trips `host_path` deliberately (fail-loud is the design, per-token review is
the cost), and #9618's underlying incentive — "gate blocks comment edits" —
is resolved by making `--verify` reachable, not by narrowing the trigger.

### Product/UX Gate

**Tier:** none — Files-to-Edit/Create contain no UI-surface paths (no `*.tsx`,
no `app/**/page|layout`, no `components/**`); the mechanical override does not
fire and the semantic sweep finds no user-facing surface.

All 8 domains swept semantically (Marketing, Engineering, Operations, Product,
Legal, Sales, Finance, Support): only Engineering is relevant. Operations note —
no new infrastructure is provisioned (Phase 2.8 silent: the capture consumes
docker + an existing repo secret; no Terraform, host, or dashboard change).
Legal note — the GDPR advisory above records no regulated-data surface.

## Architecture Decision (ADR/C4)

Phase 2.10 fires: the change extends an existing ADR's recorded contract (the
canonical-projection placeholder rule) to a new path class — an extension of
ADR-079, recorded as an amendment in THIS plan (never deferred).

### ADR

- **Amend `ADR-079`** (`knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`)
  — dated amendment block per Phase 5.1: SDK-internal HOME-derived dirs are
  placeholdered via a capture-computed root (`${CANARY_BRIDGE_SPAWN}`); the
  env-override sub-clauses of the #8623 rule apply only to our own modules'
  paths; host_path fail-loud retained for all other host paths. No NEW ADR —
  this is an extension of the projection contract, not a new decision.
  Status stays `adopting` (Deferral A / #5889 promotion remains open).

### C4 views

**No C4 impact.** Enumeration per the completeness mandate (all three model
files read — `model.c4`, `views.c4`, `spec.c4`): (a) external human actors —
none added (CI machinery; no actor surface changes); (b) external
systems/vendors — none new (the capture already calls the Anthropic API — a
pre-existing, already-modeled edge; this diff adds no integration); (c)
containers/data-stores — the change lives inside the already-modeled
web-platform image/CI path; no new container or store; (d) actor↔surface
relationships — unchanged. A placeholder token in a committed fixture is below
the C4 abstraction line, matching how the existing canary machinery is
(un)modeled.

### Sequencing

The amendment lands in THIS PR describing the shipped state — binary change, no
soak-gated target state.

## Encryption Posture

Skipped — no persistent data store and no new cross-component/network
connection (a placeholder in a committed argv fixture and a comment line are
neither; the capture's Anthropic API call is a pre-existing connection).

## Infrastructure (IaC)

Skipped — no new provisioned resource (no server, service, cron, vendor
account, DNS record, secret, firewall rule, or monitoring webhook). The
re-capture reuses the existing `sandbox-canary-verify-in-image.sh` docker path
and the existing `ANTHROPIC_API_KEY` repo secret/Doppler entry.

## Open Code-Review Overlap

87+ open `code-review` issues checked against the planned file set
(`sandbox-canary.mjs`, `sandbox-canary-argv.json`, `sandbox-canary.test.ts`,
`agent-runner-sandbox-config.ts`, `sdk-bump-sandbox-gate.sh`, and the bare term
`sandbox-canary`). Matches: **None**.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a placeholder for the HOME-based directory (like the existing ${CANARY_C4_STAGING} placeholder)" [issue #9614] | Phase 2 / `sandbox-canary.mjs` `CANARY_BRIDGE_SPAWN_PLACEHOLDER` + `norm()` arm | mapped |
| 2 | "substitute it in runReplay" [issue #9614] | Phase 2 / `substituteCanonicalArgv` + `runReplay` mkdtemp | mapped |
| 3 | "add it to prepDirs" [issue #9614] | Phase 2 / `prepDirs` conditional push | mapped |
| 4 | "extend test/sandbox-canary.test.ts" [issue #9614] | Phase 1 / new describe + census update | mapped |
| 5 | "re-capture the fixture in the image (node:22-slim pinned digest, npm ci, bun scripts/sandbox-canary.mjs --capture against a scripted API stand-in)" [issue #9614] | Phase 4 / `SANDBOX_CANARY_MODE=capture` in-image re-capture (creds path primary; stand-in is the documented fallback for a creds-blocked env, exactly the shape the issue measured) | mapped |
| 6 | "add an ADR-079 amendment line" [issue #9614] | Phase 5 / ADR-079 dated amendment | mapped |
| 7 | "re-land a premise correction an earlier PR reverted: … 'with Bash (kb-search greps)' should become the Read/Grep/Glob phrasing (locate the exact site in sdk-bump-sandbox-gate.sh)" [brief] + "The premise correction reverted on #9570 … should land alongside this fix" [issue #9618] | Phase 3 / `agent-runner-sandbox-config.ts:313` comment (site located — it is the ts file, not the gate script; see Reconciliation) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `CANARY_BRIDGE_SPAWN_PLACEHOLDER` + `norm()` arm + `bridgeSpawnRoot` opt | "add a placeholder for the HOME-based directory (like the existing ${CANARY_C4_STAGING} placeholder)" | asked |
| `substituteCanonicalArgv` + `runReplay` edits | "substitute it in runReplay" | asked |
| `prepDirs` push | "add it to prepDirs" | asked |
| Test additions + census update | "extend test/sandbox-canary.test.ts" | asked |
| Fixture re-capture + in-image verify | "re-capture the fixture in the image" | asked |
| ADR-079 amendment | "add an ADR-079 amendment line" | asked |
| `agent-runner-sandbox-config.ts` comment fix | "the Read/Grep/Glob phrasing … should land alongside this fix" | asked |
| `hasUnsubstitutedPlaceholder` / fail-loud-preservation tests | — | inferred — the new opt must not silently weaken the #8623 host_path guard; pinning that is the property the issues' whole design rests on |
| `_comment` fixture-text update | — | inferred — the emitted `_comment` enumerates the placeholder vocabulary; a new placeholder without it makes the artifact self-misdescribing |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (plus `knowledge-base/` docs)
- Planned files: 5 | Estimated changed lines: ~320 (≈60 in the .mjs, ≈90 new
  test lines, ≈40 regenerated-fixture delta, 2 comment lines, ≈30 ADR)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `normalizeCapturedArgv` maps `<homedir>/.claude/bridge-spawn` (and
  subpaths) to `${CANARY_BRIDGE_SPAWN}` when `bridgeSpawnRoot` is supplied, and
  the placeholder appears in `prepDirs` iff present in the projected argv.
- [ ] The host_path guard is unchanged in strength: any `/root`/`/home` token
  that is NOT the supplied `bridgeSpawnRoot` (or ws/c4 roots) still throws —
  including `bridge-spawn` itself when the opt is absent.
- [ ] `substituteCanonicalArgv` replaces `${CANARY_BRIDGE_SPAWN}` when given
  `bridgeSpawn`, and `hasUnsubstitutedPlaceholder` returns true on the argv
  when it is not.
- [ ] `runReplay` creates a real dir for the bridge-spawn mount point and
  substitutes it in both `bwrapSetupArgv` and `prepDirs`.
- [ ] `apps/web-platform/infra/sandbox-canary-argv.json` is regenerated by the
  in-image `--capture` (never hand-edited): `sdkVersion` equals the pinned
  `0.3.284`, argv carries `--tmpfs ${CANARY_BRIDGE_SPAWN}`, and prepDirs
  carries the placeholder.
- [ ] In-image `--verify` against the refreshed fixture emits
  `verify_ok` (proving this PR's own capture gate passes — the #9618 fix
  demonstrated on the very diff that trips the gate).
- [ ] `agent-runner-sandbox-config.ts` reads `with Bash retained as the
  deny+escalate tripwire (kb-search itself is Read/Grep/Glob-only, #9559)` —
  the #9559 premise correction re-landed verbatim.
- [ ] ADR-079 carries the dated 2026-10-06 amendment; status stays `adopting`.
- [ ] `cd apps/web-platform && npx vitest run test/sandbox-canary.test.ts`
  fully green, including the committed-fixture census.
- [ ] No `version` key added to any manifest; no lockfile change (SDK pin
  already at 0.3.284 — this PR changes no dependency).

## Test Scenarios

- Given a raw argv containing `--tmpfs /root/.claude/bridge-spawn` and
  `bridgeSpawnRoot=/root/.claude/bridge-spawn`, when `normalizeCapturedArgv`
  runs, then the argv contains `--tmpfs ${CANARY_BRIDGE_SPAWN}` and prepDirs
  contains the placeholder — and given a `/sub` suffix, the suffix survives the
  mapping.
- Given the same raw argv WITHOUT the opt, when projection runs, then it throws
  `/host_path/` (fail-loud regression pin).
- Given `--tmpfs /root/.ssh`, when projection runs with `bridgeSpawnRoot` set,
  then it STILL throws `/host_path/` — the new mapping does not loosen the
  guard for sibling HOME paths.
- Given a projected argv carrying `${CANARY_BRIDGE_SPAWN}`, when
  `substituteCanonicalArgv` runs with `bridgeSpawn="/replay/bsp"`, then the
  token becomes `/replay/bsp` and `hasUnsubstitutedPlaceholder` is false; when
  run without `bridgeSpawn`, `hasUnsubstitutedPlaceholder` is true (the
  replay-time refuse-to-spawn guard).
- Given the refreshed committed fixture, when the census test reads it, then
  `--tmpfs ${CANARY_BRIDGE_SPAWN}` appears exactly once, every `${CANARY_*}`
  token is in `known`, and no `/root|/home` literal is present.
- **Integration (creds-gated):** `ANTHROPIC_API_KEY="$(doppler secrets get
  ANTHROPIC_API_KEY --project soleur --config ci --plain)"
  SANDBOX_CANARY_MODE=capture bash
  apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` from the
  worktree root → emits `{"verdict":"captured",...,"sdkVersion":"0.3.284"}`
  and updates `infra/sandbox-canary-argv.json` via the `/out` mount.
- **Integration verify:** same env with `SANDBOX_CANARY_MODE=verify` → last
  stdout line parses `"verify_ok"`.
- **Gate-level:** on the PR, `sandbox-canary-capture-gate` logs
  `canary --verify OK` and does NOT demand an `sdk-bump-verified:` trailer for
  this diff (the merge-blocking ack path only fires if capture itself fails).

## Success Metrics

- `sandbox-canary-capture-gate` on this PR reaches `verify_ok` with zero
  maintainer ack — the first capture-input-touching PR able to merge on merit
  since the 0.3.284 pin landed.
- Fixture `sdkVersion` == lockfile pin, demonstrable by `jq -r .sdkVersion`.

## Dependencies & Risks

- **Creds dependency:** Phase 4 needs `ANTHROPIC_API_KEY` (repo secret /
  Doppler `soleur` `ci`+`prd` configs — verified readable at plan time). If the
  work env lacks it, the scripted API stand-in (`ANTHROPIC_BASE_URL` → a
  container-reachable canned-response stub) is the documented fallback — a
  follow-on scaffold, not a reason to ship a stale fixture: shipping the
  projection fix WITHOUT the refreshed fixture leaves the gate exactly as
  broken (`argv_drift` or the same `host_path` on this branch's own verify run).
  Fixture freshness is a merge-blocker for this PR, not an optional step.
- **Merge-order drift:** if #9599 (W1 credential-deny, OPEN) or an SDK bump
  lands first, re-capture after the next `origin/main` sync — the gate's own
  `--verify` will flag `argv_drift` otherwise (fail-loud working as designed).
- **Unknown 0.3.284 argv shape:** #9614 measured the failure as the
  `bridge-spawn` `host_path` throw — the FIRST offending token. Other
  host-path or unrecognized-option tokens may sit behind it; Phase 4 iterates
  deliberately (each gets a named placeholder or a justified drop — never a
  weakened guard).
- **Fixture-census brittleness:** `countFdValuedOptions(fx.bwrapSetupArgv)
  === 0` and the exact-once C4 assertions encode the 0.3.197 shape; a 0.3.284
  argv carrying a kept fd-valued option or extra C4 token fails them —
  update with justification, never weaken.
- **Sharp edge — the placeholder is contract, not mechanism:** the mapping is
  keyed on the SDK's own `homedir()` expression; if the SDK moves the dir
  (e.g. under `CLAUDE_CONFIG_DIR` or XDG), capture throws `host_path` again —
  that IS the fail-loud doing its job; the fix is another deliberate
  placeholder, not a broader prefix match.
- **Sharp edge — User-Brand Impact:** an empty/`TBD` `## User-Brand Impact`
  fails `deepen-plan` Phase 4.6 — filled above.

## References & Research

- Issues: #9614, #9618 (both `meta/machinery`, OPEN)
- Reverted correction commit: `cdab1153` (PR #9570 branch)
- Governing ADR: `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
  (incl. the 2026-09-24 #8623 amendment — the placeholder rule)
- Capture machinery: `apps/web-platform/scripts/sandbox-canary.mjs`,
  `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`,
  `.github/workflows/ci.yml` (`sandbox-canary-capture-gate`)
- Gate: `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh:186`
- Precedent tests: `apps/web-platform/test/sandbox-canary.test.ts` (C4
  staging describe at :532-579 is the mirror image of the new block)
- SDK evidence: bundled
  `node_modules/@anthropic-ai/claude-code-linux-x64/claude` —
  `join(homedir(), ".claude", "bridge-spawn")` (`ensureBridgeSpawnRootDir`)
