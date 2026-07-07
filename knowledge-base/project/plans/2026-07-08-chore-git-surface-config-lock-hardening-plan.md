---
title: "chore: git-surface / config.lock hardening — close ADR-099 §latent surfaces (#6191) + promote #5934 mask-scope finding"
date: 2026-07-08
type: chore
issues: [6191, 5934]
closes: [6191]
refs: [5934]
lane: cross-domain # no spec.md for this branch — defaulted to cross-domain (fail-closed per plan Save-Tasks)
brand_survival_threshold: none
adr: [ADR-099 (amend), ADR-081 (coherence consolidation)]
---

# chore: git-surface / config.lock hardening

## Overview

Bundle two pre-audited, low-severity git-surface items into one hardening PR. Both are already
named, graded, and prescribed in the accepted **ADR-099 §Known latent surfaces (audited #6184)** —
this PR *executes* those prescriptions and closes the two latent items out.

- **#6191 (code, `Closes`)** — two host-side / hook git-surface sites that carry the "wrong-layout
  polarity" smell but provably **cannot strand a user** (ADR-099 grades both low-severity,
  defense-in-depth):
  1. `apps/web-platform/server/workspace.ts:236/246` — the host-side raw `git config user.name /
     user.email` writes that seed the workspace **owner** as the local identity. Route through a
     new **lock-free TS `atomicGitConfig` writer** that writes via `cp -p` current config → temp →
     `git config --file <tmp>` → atomic `rename(tmp, config)` (mirrors the repo's blessed
     `workspace-permission-lock.ts` atomic-rename idiom AND the bash `atomic_git_config` cp-first
     seed). Atomic and lock-independent **by construction** — no stale-lock sweep, no TOCTOU.
  2. `.claude/hooks/prod-write-defer-gate.sh:112` — `resolve_operator_email`'s
     `git config --global --get user.email` fallback. `--global` is the **bot** identity on the
     non-bare Concierge surface (authority inversion). Resolve via the corpus-standard **bot-shape
     discriminator** so a `[bot]`-shaped value is never logged as the operator; fall through to
     `unknown@local`.
- **#5934 (docs, `Ref` — stays OPEN)** — the durable root-cause fix (stop the Concierge sandbox
  masking `.git/config.lock`) lives in **Concierge sandbox mount/masking policy, NOT this repo**, so
  no code fix can land here. Its re-evaluation criterion — *single-path vs `*.lock` glob mask* — was
  **already answered (single-path)** by live `findmnt`/`touch` forensics (2026-07-05). This PR
  **promotes/consolidates** that confirmed finding into the ADR corpus (currently split between a
  ruled-out ADR-081 candidate and a correction note) and updates #5934's re-eval status. #5934's
  non-recurrence follow-through (`scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh`) is
  **already enrolled** and **not due until 2026-07-14** — this PR adds no new soak gate.

**Lineage (contextual only — NOT work targets):** #5912 → PR #5932 (CLOSED, in-session lockless
self-heal), #6184 → PR #6183 (CLOSED, non-bare identity-inversion fix). Verified CLOSED at plan
time.

## Research Reconciliation — premise vs. codebase reality

| Premise (from ARGUMENTS / issue bodies) | Reality on `origin/main` (verified) | Plan response |
|---|---|---|
| #5934 re-eval task = "probe/document mask scope (single-path vs glob)" | **Already answered: single-path.** Live `findmnt -T .git/config.lock` → `tmpfs[/null]` per-path bind-mount; `touch .git/config.soleur-probe.lock` succeeded (2026-07-05 learning; ADR-081 CORRECTION note L8–27). | Deliverable narrows from *probe* → *promote/consolidate* the confirmed finding + update #5934 status. No new forensic probe needed. |
| "route workspace.ts writes through `atomic_git_config`" | `atomic_git_config` is **bash-only** (`worktree-manager.sh`); workspace.ts is host-side **TS**. No TS git-config writer exists. | Build a **lock-free TS `atomicGitConfig`** (cp-p → temp → `git config --file <tmp>` → `rename`), modeled on the blessed TS atomic-rename precedent `workspace-permission-lock.ts:11–26`. Rename-based (not sweep-based) so it is correct under >1 caller — scoped-advisor (fable) flagged that sweep+native reintroduces a TOCTOU and that adding `seedWorktreeConfig` as a 2nd caller would falsify a "single-writer" premise. NOT a shell-out to the plugin bash script. |
| "route the identity write through `atomic_git_config`" (naive reading) | **ADR-081 Alternative (v) EXPLICITLY REJECTED** routing the *in-sandbox identity OVERRIDE* (`ensure_worktree_identity`, bash) through `atomic_git_config` — a "successful" write there overwrites the host-seeded owner with the bot. | This PR touches only the **host-side owner SEED** (workspace.ts), which *establishes* the correct identity — a different, safe surface (ADR-099 §latent). Do **NOT** touch `ensure_worktree_identity`. See Sharp Edges. |
| gate fix = "prefer `--local` on Concierge" (naive reading) | Blanket "respect local" **re-opens #2815** (bare-dev repos carry an inherited `[bot]` local; two review agents caught this on #6184). | Use the **bot-shape discriminator** (mirror shipped `ensure_worktree_identity` `_identity_is_bot`), not a scope flip. |
| ADR-099 / ADR-081 already assert "C4 impact: none" | Confirmed by reading all three `.c4` files (see §Architecture Decision). | Assert no-C4-impact citing the enumeration; no `.c4` edit. |

## User-Brand Impact

**If this lands broken, the user experiences:** No new user-facing failure. Both #6191 sites are
defense-in-depth that **fall through to today's behavior** — the workspace.ts write already
try/catch→`log.warn` (never a strand); the gate path already feeds an audit log, not a git op.

**If this leaks, the user's data is exposed via:** No new exposure vector. The operator email
already flows to `.claude/logs/approvals.jsonl`; this change makes that audit value *more* accurate
(never records the bot as the operator). No new processing activity.

**Brand-survival threshold:** none.
- `threshold: none, reason:` both #6191 sites are ADR-099-graded low-severity defense-in-depth that
  cannot strand a user or leak data (host-side unmasked single-writer seed; audit-log-only email
  resolver reached only when BOTH `SOLEUR_OPERATOR_EMAIL` and `GITHUB_ACTOR` are unset); #5934's
  deliverable here is documentation only. (Scope-out bullet present because the diff touches
  identity/git-config — a sensitive-ish path — per preflight Check 6.)

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- Re-grep the exact anchors (line numbers drift): `grep -n 'git","config","user.name\|user.email\|execFileSync' apps/web-platform/server/workspace.ts` and `grep -n 'git config --global --get user.email' .claude/hooks/prod-write-defer-gate.sh`.
- Confirm ADR-099 §Known latent surfaces still names both sites; confirm ADR-081 still has the 2026-07-05 single-path CORRECTION + the `coordinated with the open #6191` note (L233).
- Read the TS atomic-rename precedent `apps/web-platform/server/workspace-permission-lock.ts:11–26`.

### Phase 1 — lock-free TS `atomicGitConfig` writer (RED → GREEN)
- **Create** `apps/web-platform/server/git-config-atomic.ts` exporting
  `atomicGitConfig(cwd: string, args: string[], opts?: { log?: Logger }): void`.
  - **Design = copy-then-edit-then-rename (lock-free by construction), mirroring the bash writer's
    cp-first seed AND `workspace-permission-lock.ts`'s `rename(2)` atomicity — NOT a stale-lock sweep:**
    1. Resolve `<cwd>/.git/config` (via `git rev-parse --git-dir`, or `<cwd>/.git/config` for the
       normal non-bare clone).
    2. `cp -p` the current `.git/config` → a same-dir temp (`config.soleur-tmp.<pid/uuid>`). **Load-bearing:**
       `git config --file <tmp>` starts from an EMPTY file — seeding the temp with the current
       contents first is what prevents dropping every other config key (the advisor's rework caution).
       If `.git/config` is absent, start the temp empty.
    3. Edit the temp with git's own INI writer: `git config --file <tmp> <args…>`.
    4. **Defensive masked-TARGET pre-check** (`statSync(config).isCharacterDevice()` / non-regular →
       must never occur host-side; if it does, log a structured `error` and abort WITHOUT the rename —
       best-effort, never throws). Then `renameSync(tmp, config)` — POSIX-atomic, never touches
       `config.lock`.
  - Best-effort semantics: **never throws** (preserves workspace.ts's current non-stranding behavior);
    a failure cleans up the temp and logs.
  - Structured logging via `createChildLogger("git-config-atomic")` (→ Better Stack + Sentry
    breadcrumb) — a **host-side observable** surface, so it does **NOT** emit in-sandbox stdout
    `SOLEUR_*` sentinels (those are for the blind sandbox scanner; adding one would trip the
    `git-lock-marker-telemetry.ts` drift guard).
  - deepen-plan Phase 4.4 precedent-diff: formalize against `worktree-manager.sh` `atomic_git_config`
    (cp-p + `git config --file` + `mv -f`) and `workspace-permission-lock.ts` (open→write→fdatasync→
    rename) — the two blessed idioms this mirrors.
- **Create** RED test `apps/web-platform/test/git-config-atomic.test.ts` (vitest, `test/**/*.test.ts`
  node project); model the tmp-repo fixture on `test/worktree-config-seed.test.ts`. Assert:
  (a) clean write lands; (b) **other pre-existing config keys survive** the write (the cp-first
  correctness invariant — write `user.email`, assert an unrelated pre-seeded key is unchanged);
  (c) a **pre-existing `config.lock`** (regular file left by another writer) does NOT block the write
  (rename is lock-independent) and is not deleted by us; (d) a non-regular node AT the config target
  is refused with an error log and the helper does not throw.

### Phase 2 — Route workspace.ts through `atomicGitConfig`
- Replace the two raw `execFileSync("git", ["config", "user.name"/"user.email", …])` calls
  (L236/L246) with `atomicGitConfig(workspacePath, ["config", "user.name", userName])` /
  `["config", "user.email", userEmail]`, keeping the existing outer try/catch→`log.warn` (the helper
  is best-effort but the call site stays defensive).
- **Consistency (in-scope, small — clean now that the helper is rename-based):** route
  `seedWorktreeConfig`'s writes in `worktree-config-seed.ts` (`--unset-all extensions.worktreeConfig`
  + `core.repositoryformatversion 0`) through `atomicGitConfig` too — the paired host-side mutator on
  the same surface. Safe under the two call sites precisely because the writer is lock-free by
  construction (the advisor's caveat about a sweep-based helper + 2 callers does not apply). Its
  `--get` **read** stays a raw `execFileSync` (reads never take the lock).
- **No test-shape edits expected:** `test/workspace.test.ts` and `test/worktree-config-seed.test.ts`
  assert config **outcomes** via `git config --get` reads (verified at plan time), not the write
  `execFileSync` argv — routing writes through the helper leaves the resulting config values
  identical. Adjust only if a specific assertion breaks.

### Phase 3 — Gate resolver: fix the authority inversion
ADR-099 §latent offers *"resolve … or accept the caveat."* The ARGUMENTS likewise say
*"resolve/accept."* The scoped-advisor (fable) leaned to **accept-the-caveat** as the lower-risk close
(the path is audit-log-only, reached only when BOTH `SOLEUR_OPERATOR_EMAIL` and `GITHUB_ACTOR` are
unset; a substring bot-match can *mis*classify a legitimately-named human/service account and downgrade
it to `unknown@local` — trading a known-wrong value for a differently-wrong one).

- **Primary (recommended): accept the caveat (comment-only, cannot regress).** Fix the misleading
  L105–107 comment: it cites the *bare*-repo `2026-04-24-fake-git-author-bare-repo-bot-override`
  learning to justify preferring `--global`, but ADR-099 shows that reasoning **inverts** on the
  non-bare Concierge surface (`--global` = the sandbox bot). Document that on Concierge the `--global`
  fallback may record the bot in the audit log, that this feeds an audit log (not a git op) and is
  reached only under a double-unset, and cite ADR-099 §latent. No resolver logic change.
- **Alternative (active fix, if review prefers): bot-shape discriminator applied UNIFORMLY to both
  scopes.** Read `--local` then `--global` (first non-empty), run the value through
  `_email_is_bot` (`[[ "$e" == *"[bot]"* || "$e" == *"github-actions"* ]]`); if bot-shaped in EITHER
  scope, discard → `unknown@local`. Apply to both scopes (a bot can appear in local too — advisor
  note) rather than a `--global`-specific patch. Mirrors shipped `ensure_worktree_identity`
  bot-shape logic.
- **Decision routing:** this is a **Taste** call (both ADR-sanctioned, within the ARGUMENTS'
  "resolve/accept"). Headless pipeline → recorded in `decision-challenges.md` for plan-review /
  ship to surface; default = the recommended accept-the-caveat.
- **Extend** `.claude/hooks/prod-write-defer-gate.test.sh` only if the active fix is chosen
  (synthesized `TEST-FIXTURE-NOT-REAL` cases: bot-shaped `--global` → `unknown@local`; non-bot
  `--local` → resolved; env-precedence unchanged). For accept-the-caveat, no new test case (behavior
  unchanged; the fix is documentation).

### Phase 4 — Documentation (ADR + issue status)
- **ADR-099 amend** (`/soleur:architecture`): in §Known latent surfaces, mark **both** items
  **RESOLVED** by this PR (workspace.ts → routed through TS `atomicGitConfig`; gate →
  bot-shape-discriminated). Add a one-line "resolved 2026-07-08, #6191" note.
- **ADR-081 coherence consolidation:** the single-path mask-scope answer is currently stated under
  *ruled-out* candidate (a) AND re-derived under the 2026-07-05 candidate-(b) CORRECTION. Consolidate
  into one authoritative statement ("mask scope = **single-path**, confirmed by live `findmnt`/`touch`
  under candidate (b); criterion (1) closed"), so a future reader is not misled by the stale
  attribution. Do **not** change ADR-081 status (`adopting` → stays until the AC10 soak / 2026-07-14
  follow-through).
- **#5934 issue** (`gh issue comment`, **do NOT close** — `Ref #5934` only): record re-eval outcome —
  single-path CONFIRMED; #5912 fallback branch de-risked to insurance; durable sandbox-masking fix
  remains OPEN (not in this repo); non-recurrence tracked by the 2026-07-14 follow-through.

### Phase 5 — Verify (all no-SSH)
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-config-atomic.test.ts test/workspace.test.ts test/worktree-config-seed.test.ts`
- `bash .claude/hooks/prod-write-defer-gate.test.sh`
- `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` (unchanged — parity reference, must stay green)
- Telemetry drift guard: `./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts` (must stay green — no new sentinels added).
- ADR corpus tests if touched: `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts` is **N/A** (no `.c4` edit); run any ADR-lint the repo has.

## Files to Create
- `apps/web-platform/server/git-config-atomic.ts` — TS `atomicGitConfig` writer.
- `apps/web-platform/test/git-config-atomic.test.ts` — RED/GREEN unit tests.

## Files to Edit
- `apps/web-platform/server/workspace.ts` — route L236/L246 through `atomicGitConfig`.
- `apps/web-platform/server/worktree-config-seed.ts` — route seed writes through `atomicGitConfig` (consistency).
- `.claude/hooks/prod-write-defer-gate.sh` — fix L105–107 comment (accept-caveat default) OR add bot-shape discriminator (active-fix arm).
- `.claude/hooks/prod-write-defer-gate.test.sh` — new fixture cases **only if** the active-fix arm is chosen.
- `knowledge-base/project/specs/feat-one-shot-5934-6191-git-surface-hardening/decision-challenges.md` — the gate resolve-vs-caveat Taste decision (for ship to surface).
- `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md` — mark §latent items resolved.
- `knowledge-base/engineering/architecture/decisions/ADR-081-chardevice-config-lock-substrate-sweep.md` — consolidate single-path finding.
- (possibly) `apps/web-platform/test/workspace.test.ts`, `test/worktree-config-seed.test.ts` — argv-shape expectation updates.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `apps/web-platform/server/git-config-atomic.ts` exists and exports `atomicGitConfig`; `grep -c 'export function atomicGitConfig' apps/web-platform/server/git-config-atomic.ts` == 1.
- **AC2** No raw `git config` identity write remains at the seed site: `grep -nE 'execFileSync\("git", \["config", "user\.(name|email)"' apps/web-platform/server/workspace.ts` returns **0**; the two calls route through `atomicGitConfig` (grep ≥ 2 `atomicGitConfig(` in workspace.ts).
- **AC3** `apps/web-platform/test/git-config-atomic.test.ts` passes under vitest, covering: clean-write; **other pre-existing config keys survive** the write (cp-first invariant); pre-existing `config.lock` does not block the write; non-regular-target refused-no-throw.
- **AC4** Gate authority inversion addressed. **If accept-the-caveat (default):** the L105–107 comment documents the non-bare `--global`=bot inversion and cites ADR-099 §latent (`grep -c 'ADR-099' .claude/hooks/prod-write-defer-gate.sh` ≥ 1 near `resolve_operator_email`); `prod-write-defer-gate.test.sh` stays green (behavior unchanged). **If active fix:** the new fixture case (bot-shaped value, env unset) asserts resolved == `unknown@local`; suite exits 0.
- **AC5** `tsc --noEmit` clean; `vitest run` (the three named test files) green; `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` green; `test/git-lock-marker-telemetry.test.ts` green (drift guard — no new sentinels).
- **AC6** ADR-099 §Known latent surfaces marks **both** items resolved (grep for `resolved` + `#6191` in the section). ADR-081 has a single consolidated single-path statement (no contradiction between candidate (a) and the correction).
- **AC7** PR body uses `Closes #6191` and `Ref #5934` (NOT `Closes #5934` — durable fix not in this repo; soak not due until 2026-07-14).

### Post-merge (operator / automated)
- **AC8** `gh issue view 6191` state == CLOSED (auto via `Closes`). `gh issue view 5934` state == OPEN (still tracks the Concierge-infra durable fix + the 2026-07-14 non-recurrence follow-through). *Automation: `gh` CLI via ship post-merge verification — no operator step.*
- **AC9** `#5934` carries a comment recording the re-eval outcome (single-path confirmed; fallback de-risked). *Automation: `gh issue comment` inline in Phase 4.*

## Observability

```yaml
liveness_signal:
  what: workspace-provision git-identity seed + gate operator-email resolution
  cadence: per workspace provision / per PreToolUse prod-write gate hit
  alert_target: none (defense-in-depth; existing provision-path health already covered)
  configured_in: apps/web-platform/server/git-config-atomic.ts (createChildLogger "git-config-atomic")
error_reporting:
  destination: server logger → Better Stack + Sentry breadcrumb (host-side, observable — NOT a blind sandbox surface)
  fail_loud: true (non-regular/masked lock host-side → error log; best-effort, never throws)
failure_modes:
  - mode: NON-REGULAR (masked) config TARGET host-side (should never occur — real anomaly)
    detection: git-config-atomic error log (Better Stack + Sentry breadcrumb); rename aborted
    alert_route: Sentry breadcrumb; existing provision-error surface
  - mode: cp/temp-write/rename fails (disk, perms)
    detection: git-config-atomic warn/error log + existing workspace.ts try/catch → log.warn
    alert_route: none (non-stranding; temp cleaned up; falls through to today's behavior)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/git-config-atomic.test.ts   # asserts key-preservation + lock-independence + refuse-no-throw (no ssh)"
  expected_output: "4 passed — clean-write, other-keys-survive, pre-existing-lock-non-blocking, non-regular-target refused (no throw)"
```

*2.9.2 (blind-surface) note:* neither #6191 site is a blind sandbox surface — `workspace.ts` and the
pre-merge hook run **host-side**, directly observable via the server logger. The in-sandbox blind
surface (`worktree-manager.sh` `atomic_git_config`) is **unchanged** by this PR and already emits
the drift-guarded `SOLEUR_GIT_*` sentinels mirrored by `git-lock-marker-telemetry.ts`. No new
in-sandbox probe is required.

*2.9.1 (soak) note:* no NEW soak/time-gated close criterion. #5934's non-recurrence follow-through
(`scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh`, earliest 2026-07-14) is **already
enrolled** — this PR neither closes #5934 nor adds a soak gate.

## Architecture Decision (ADR/C4)

### ADR
- **ADR-099 (amend)** — mark §Known latent surfaces items (workspace.ts:236/246; gate
  `resolve_operator_email`) RESOLVED by #6191. Provisional; no new ordinal.
- **ADR-081 (amend — coherence)** — consolidate the single-path mask-scope conclusion (currently
  split between ruled-out candidate (a) and the 2026-07-05 candidate-(b) correction) into one
  authoritative statement. Status unchanged (`adopting`).
- No **new** ADR: this PR *implements decisions already recorded* in ADR-099/ADR-081; it does not make
  a novel architectural decision.

### C4 views
**No C4 impact** — verified by reading all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Enumeration:
- **External human actors** (`founder` model.c4:8, `emailSender` :14, `contributor` :23) — none added/changed.
- **External systems/vendors** — none added/changed (host-internal Node writes + a local bash hook; no new edge to `github`/`anthropic`/`doppler`).
- **Containers/data-stores touched** — all already-modeled: the host-side git writes run on the `/workspaces` agent compute (`hetzner` Compute, model.c4:168; ADR-075 isolation); the gate is part of the CLI `hooks` Hook Engine (model.c4:60). The bare `gitDataStore` (model.c4:198, ADR-068) is **not** touched (workspace.ts writes the non-bare clone).
- **Actor↔surface access relationships** — none added/removed/re-scoped (edge lists model.c4:277–405 unchanged). Identity-authority polarity is an internal write-path detail, not a modeled access edge.

Direct precedent: ADR-099 already carries `## C4 impact — None` with this exact enumeration for the
same surfaces; ADR-081's 2026-07-07 amendment likewise `C4 impact: none`.

### Sequencing
None — the decisions are already recorded; this PR resolves latent follow-ups and consolidates a
confirmed finding. No soak-gated ADR status flip in this PR.

## Domain Review

**Domains relevant:** none

No cross-domain (business) implications detected — infrastructure/tooling change (server
provisioning helper, pre-merge hook, ADR docs). No UI surface (no `## Files to Create`/`Edit` path
matches a UI-surface glob), so the Product/UX Gate does not fire. Engineering/CTO ownership only.

**GDPR / Compliance (Phase 2.7):** considered — no new regulated-data surface. The operator email
already flows to `.claude/logs/approvals.jsonl`; the gate change makes that audit value *more*
accurate (never records the bot), introducing no new processing activity, no schema/migration/auth/API
change. No gate invocation required.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` cross-referenced against all target paths
(`workspace.ts`, `prod-write-defer-gate.sh`, `worktree-config-seed.ts`, `ADR-099`, `ADR-081`,
`git-config-atomic`) returned zero matches at plan time.

## Risks & Sharp Edges

- **DO NOT touch `ensure_worktree_identity`.** ADR-081 Alternative (v) *explicitly rejected* routing
  the in-sandbox identity **override** through `atomic_git_config` (a "successful" write there
  overwrites the host-seeded owner with the bot). #6191 targets only the host-side owner **seed**
  (workspace.ts) — an entirely different, safe surface. Conflating them re-introduces the exact
  misattribution ADR-081 fixed via bot-shape discrimination (#6184).
- **Gate fix must be bot-shape, not scope-flip.** Blanket "prefer `--local`" re-opens #2815 (bare-dev
  repos carry an inherited `[bot]` local identity). The corpus-correct fix is the bot-shape
  discriminator, mirroring the shipped `ensure_worktree_identity`.
- **Proportionality + primitive choice.** The TS `atomicGitConfig` is defense-in-depth on an
  unmasked, non-stranding host surface — but use the **rename-based** primitive (cp-p → temp →
  `git config --file` → `renameSync`), NOT a stale-lock *sweep*. Scoped-advisor (fable) flagged that a
  sweep can delete a *live* lock and reintroduces a TOCTOU, and that "single-writer" is falsified the
  moment `seedWorktreeConfig` becomes a 2nd caller. Rename is lock-free by construction and is *less*
  code than a correct staleness heuristic. **Critical:** `git config --file <tmp>` starts from an
  EMPTY file — `cp -p` the current config into the temp first or every other key is dropped. Do
  **not** port the full masked-target detection machinery from the bash writer (that exists for the
  *blind, masked, in-sandbox* surface this PR does not touch) beyond the one defensive non-regular-
  target check. deepen-plan Phase 4.4 formalizes the precedent-diff.
- **No new stdout `SOLEUR_*` sentinels** — the host-side helper logs via the server logger. Emitting
  a new in-sandbox-style sentinel would trip the `git-lock-marker-telemetry.ts` drift guard.
- **`Ref #5934`, not `Closes`.** The durable fix is Concierge-infra, not in this repo; auto-closing at
  merge would produce a false-resolved state while the 2026-07-14 non-recurrence follow-through is
  still pending. Use `Ref #5934` in the PR body; keep `Closes #6191`.
- **Test-runner traps** (repo Sharp Edges): use `./node_modules/.bin/vitest run <path>` (bun test is
  blocked by `apps/web-platform/bunfig.toml` `pathIgnorePatterns=["**"]`) and `./node_modules/.bin/tsc
  --noEmit` (root has no `workspaces` field, so `npm run -w` fails). New TS test must live at
  `apps/web-platform/test/**/*.test.ts` to match the node vitest project include glob.
- **Line anchors drift** — 236/246 and 112 are current-tree anchors; re-grep in Phase 0 before editing.

## Test Scenarios

1. **Clean seed** — fresh `git init` tmp repo → `atomicGitConfig` writes `user.email`; `git config --get user.email` returns it.
2. **Other keys survive** — pre-seed an unrelated key (`core.someflag=x`), write `user.email` via helper → assert `core.someflag` still == `x` (cp-first invariant; catches the empty-temp-drops-keys bug).
3. **Pre-existing lock non-blocking** — plant a regular `.git/config.lock`, call helper → write lands (rename is lock-free), and the planted lock is NOT deleted by us.
4. **Non-regular target refused** — simulate a non-regular node at the config target → helper logs error, does **not** throw, does not corrupt config.
5. **Gate (active-fix arm only): bot-shaped value discarded** — env vars unset, `user.email` = `github-actions[bot]@…` in local OR global → `resolve_operator_email` returns `unknown@local`.
6. **Gate: env precedence unchanged** — `SOLEUR_OPERATOR_EMAIL` set → returned verbatim (fallback not reached). (Holds for both arms.)
