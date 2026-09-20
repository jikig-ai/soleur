---
title: "fix(go): resolve the plugin root through the loader token so the three /soleur:go session gates run with no *_PLUGIN_ROOT in the Bash env"
type: fix
date: 2026-09-19
slug: fix-go-session-gates-plugin-root-resolution
branch: feat-one-shot-8308-go-gates-plugin-root
issue: 8308
closes: 8308
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(go): resolve the plugin root through the loader token so the three `/soleur:go` session gates run with no `*_PLUGIN_ROOT` in the Bash env

## Overview

The three shell gates at the top of `plugins/soleur/commands/go.md` (Step 0.0 workspace readiness, Step 0.5 cloud-mode detection, Step 0 session-start preamble) take their degraded branch on every local Claude Code session: the readiness probe, `cloud-detect.sh`, `worktree-manager.sh cleanup-merged` and the `.mcp.json` refresh never run, and the only signal is a `SOLEUR_*_SKIPPED`/`probe-unreachable` marker that no consumer treats as a defect. This plan restores a verified plugin-root resolution that works with no `*_PLUGIN_ROOT` variable in the Bash environment, keeps the `name=soleur` identity preflight, makes every gate report which arm produced its root, and adds an executable suite that drives the three fence bodies with the environment unset and asserts the real probe ran.

**Root cause, established by measurement rather than inference.** The Claude Code plugin loader substitutes the *exact* braced literal `${CLAUDE_PLUGIN_ROOT}` in command and skill text at delivery — measured on the command surface (ADR-179 §R3 Arm 1), on the skill surface with an ambient-decoy control (ADR-179 A10; `specs/feat-one-shot-7450-git-root-anchor-untrusted/phase-1-measurement.md` §Arm 4), and again in this planning session: `plugins/soleur/skills/plan/SKILL.md`'s `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"` was delivered as an absolute path under `/data/git-repositories/jikig-ai/soleur/plugins/soleur` while `echo "${CLAUDE_PLUGIN_ROOT-UNSET}"` in the same session's Bash tool printed `UNSET`. PR #8061 (commit `949872534`, 2026-09-12) replaced go.md's bare token with `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"`. The unbraced `$CLAUDE_PLUGIN_ROOT` inside the `:-` default is **not the loader's token**, so the line reaches bash unsubstituted and expands empty — the class ADR-179 names for `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` ("not its token, passes through literally, reaches bash"). `commands/sync.md`, which kept the canonical braced token `${CLAUDE_PLUGIN_ROOT}` (ADR-179's "bare" form — bare of a `:-`/`:?` modifier, not bare of braces), is unaffected. Two guards then canonised the defect: `apps/web-platform/test/plugin-root-anchoring.test.ts` (`ROOT_ASSIGN_LITERAL`) and `plugins/soleur/test/workflow-fidelity.test.ts` both pin the broken literal, so CI is green over a command whose gates cannot run. The issue's "Cause" attributes the symptom to ADR-179's headline finding; ADR-179 §R3 itself reframes that finding as the *predicted benign observation* under loader substitution. Regression window: 2026-09-12 → now.

## Problem Statement / Motivation

- `wg-at-session-start-run-bash-plugins-soleur` and `wg-at-session-start-after-cleanup-merged` are corpus rules the harness's own entry point has not honoured for a week: merged worktrees accumulate (a hand re-run reaped 188 temp dirs, #8308), `.mcp.json` goes stale at the bare root so MCP servers silently drop out of new sessions, and cloud-mode classification is decided by the absence of a signal.
- The degraded arms are honest (the #7442 markers fire) but **nothing consumes them** (#8283 §2): three sessions (learnings 2026-09-13, 2026-09-14, 2026-09-18) read the marker, ran the manager by hand, and moved on. A marker whose consumer is "whoever happens to be reading" is not a monitor.
- The #8061 form is also a trust regression. Under the bare token the operand is a literal fixed by the loader before bash runs (A10: "not a shell variable at execution time"); under the #8061 form the root is read from environment variables at execution time, so an ambient export directs it — and A11 records the identity preflight as defence-in-depth, not the load-bearing control.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief / own-draft claim | Codebase reality | Plan response |
|---|---|---|
| "Neither variable is exported into the Bash tool environment" is the cause; "not a new discovery — ADR-179's headline finding" | Both are indeed unset (re-measured: `CLAUDE_PLUGIN_ROOT`, `GROK_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR` all `UNSET`; `env \| grep -c PLUGIN_ROOT` → 0). But §R3/A10 establish the unset variable is *benign* because the bare token is substituted at delivery. The cause is the #8061 rewrite to a non-token form. | Restore the token as arm 1; record the #8061 form as rejected in the ADR. |
| Remedy 1: "resolve from `BASH_SOURCE`/`CLAUDE_PROJECT_DIR`" | That note governs payload **scripts**. In a Bash-tool fence `BASH_SOURCE[0]` is empty (measured) and `CLAUDE_PROJECT_DIR` is unset in a plain Bash call; when set (hook processes) it names the **workspace** — CWD-derived, i.e. options (d)/(e) and A11's rejected class. | Cut. |
| "derive from the installed-plugin cache" (#8283 §2) | On Claude Code the loader-substituted literal *is* the install path (A10). The **Devin** caches are different and there are two: `devin/INSTRUCTIONS.md` §Paths names `~/.local/share/devin/cli/plugins/cache/<slug>/0.0.0-unversioned` (CLI) and §Cloud Mode names `/opt/.devin/plugins` (cloud); only the second exists in go.md today, in Step 0.5. | No Claude cache read. Both Devin paths covered — **and confined to Step 0.5**, see below. |
| "a marker file the SessionStart hook writes" | `.claude/settings.json` hooks are monorepo configuration, not payload; a customer install has none, and a workspace file is CWD-resident (contributor-writable on the review path — §R1). | Cut. |
| "consider a single shared shell snippet/script" | A script cannot locate itself — the resolver is what finds the script. | Inline snippet, identical across three fences, test-pinned. |
| Own draft: "`commands/go.md` is the only artifact carrying these gates" | **False in two ways.** (a) Three *delivery mechanisms*: `plugins/soleur/{codex,devin}/skills/go/SKILL.md` delegate to it ("read and execute the canonical go command"), so on those harnesses the fence is read from disk and **not substituted**. (b) A **74-file fleet** carries the replicated `<!-- soleur-cloud-mode:start -->` block whose own recipe is `find /opt/.devin/plugins -name cloud-detect.sh \| head -1` — basename-selected, with **no `name=soleur` check** — pinned by `plugins/soleur/test/devin-cloud-mode.test.ts`. `plugins/soleur/skills/go/SKILL.md` is a third delegating surface the draft never named. | Arm 1 documented as serving both substituted and read-from-disk delivery. The fleet block is **out of scope and filed** (AC13c): deleting Step 0.5's private `find` while leaving 74 basename-selected copies would leave go.md and the fleet disagreeing on the same lookup. Guard 1's Assembly no longer claims "no other resolver exists" — it claims the *dispatch* chokepoint, which is true. |
| `find /opt/.devin/plugins` lives only in Step 0.5 | Confirmed for go.md. | Kept there deliberately — promoting it was this plan's own P0. |
| Own draft: "`sync.md` kept the bare form" | True but ambiguously worded — a deepen-pass reader parsed "bare" as *unbraced* and reported a contradiction. `sync.md` uses `${CLAUDE_PLUGIN_ROOT}` throughout, which is ADR-179's "bare" (unmodified) form and the correct one. | Reworded to "canonical braced token" everywhere; `plugins/soleur/commands/sync.md` needs no change. |
| Own draft: "`cleanup-merged` is read-mostly on a plain clone" | **False, and the draft's most dangerous error.** `worktree-manager.sh:2773` builds `all_stale_branches` from `git branch --merged main` plus `[gone]` upstreams — branches with **no worktree**. Their safety guards are all gated on a non-empty worktree path (`:2851`, `:2868` lease, `:2890`, `:2905`, `:2942`), so they are skipped, and the loop still reaches `git push origin --delete` (`:2954`), `git branch -D` (`:2960`) and `git -C "$GIT_ROOT" reset --hard HEAD` (`:2999`). It also opens with `acquire_lock cleanup-merged 5` and calls `ensure_bare_config`, which **writes git config**. ADR-178 §Context calls the operation "unrecoverable". | Step 0 is **not** made newly reachable on a cloud session; it gains a session-class gate in its own fence (R3c). The stale fail-closed banner at `:82` is filed (AC13a). |
| Own draft: "behaviour on Grok is unchanged whether or not the token is substituted" | False in one branch — today `GROK_PLUGIN_ROOT` wins unconditionally; under token-first it is never consulted if Grok substitutes. | Corrected in Technical Considerations, measured in Phase 0, recorded in decision 11. |
| Own draft: "0.0 additionally prints the two bare `true` probes" | **False, measured.** In a fresh fixture repo `git rev-parse --is-bare-repository` → `false` and `--is-inside-work-tree` → `true`. Exactly one `true`. | R4 asserts the ordered pair `false` then `true`. |
| Own draft: the P1b positive control lives in `ANCHOR_FIXTURES` | **False.** `ANCHOR_FIXTURES` is declared after the command-surface describe and consumed only by G6/G6b in the skills describe, through `gateRefsIn()` — a *gate-script* reference scanner that would classify an #8061-form fixture as `[]`. Its tag union is `"anchor" \| "quoting" \| "bare-command" \| null` and G6b asserts set equality over it. | P1b gets **its own** fixture array and its own positive-control `it` inside the command-surface describe; `ANCHOR_FIXTURES`/G6/G6b untouched. |
| Own draft: AC "vitest run … green" after adding an assertion | **Unsatisfiable as drafted.** `plugin-root-anchoring.test.ts:682` is `expect(assertions).toBe(14)` — an exact-equality anti-vacuity floor; `:1263` is the skills-block twin `toBe(18)`; and `redact-sentinel.test.sh:880` `T20_FLOOR=18` reads the *declared* `#7450` floor cross-file and fails if it moves. | AC4 names the new P5 value explicitly; AC11 states whether `T20_FLOOR` moves (it does not — the skills block is untouched). |
| Own draft: a new `.test.sh` is free | **False.** `plugins/soleur/test/lib/fixture-scan.py` builds its corpus from `git ls-files '*.sh'` repo-wide, and `fixture-relative-assert.test.sh` pins the live row set **by row-by-row equality** against a 421-line baseline ("a fall reddens exactly like a rise"); `fixture-dir-operand-assert.test.sh` is its twin; `fixture-env-adoption.test.sh` requires every suite spawning mutating `git` to source the shared fixture-env helper **and check its return**. | Both `.baseline.txt` files join Files to Edit (regenerated in the same commit); all three suites join AC10; the new suite checks `git_fixture_env`'s exit status. |
| #8283 §2 "nothing consumes the marker" | `git-lock-marker-telemetry.ts` `MARKER_RE` mirrors `SOLEUR_GIT_REPO_DIAG` but neither `SOLEUR_SESSION_START_SKIPPED` nor `SOLEUR_CLOUD_DETECT_SKIPPED`. The local CLI has no Soleur-side sink by design (layer 7). | Consumers are the **in-session prose** (layer 7) and **CI**. A hosted `MARKER_RE` mirror was drafted and **cut** — Alternatives row 5. |

## Proposed Solution

### 1. One resolver snippet, three fences, byte-identical

Each gate fence opens with `GATE=<name>` (`readiness`, `cloud-detect`, `session-start`) **above the opening anchor**, then the snippet, then the gate's `if [ "$VERIFIED" = true ]` body. The byte-identity assertion covers **only the text between the anchors**:

```bash
GATE=session-start
# --- soleur plugin-root resolver (ADR-179 decision 1 + decision 11; #8308). The three
# copies in this file are byte-identical between these anchors; go-session-gates.test.sh
# pins that. Arm 1 is the loader-substituted token — on a substituting harness a literal
# fixed before bash runs, so no environment value can direct it (A10); on a read-from-disk
# harness (the Codex/Devin go mirrors) an ordinary variable those harnesses' INSTRUCTIONS
# tell the agent to set. Never a CWD default (#7442). POSIX only: no `xargs -r`, no
# `readlink -f`, no `sed -i`. Never enable `set -e`, `set -u` or `set -o pipefail` in these
# fences — line 1 is deliberately unguarded so it stays the exact token, and `-u` would
# abort before any marker is printed, which is the silent-skip class being fixed. ---
ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token
if [ -z "$ROOT" ] && [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  ROOT="$GROK_PLUGIN_ROOT"; SRC=grok-env
fi
[ -n "$ROOT" ] || SRC=none
if [ -n "$ROOT" ] \
   && [ -f "${ROOT}/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${ROOT}/.claude-plugin/plugin.json"; then
  VERIFIED=true
else
  VERIFIED=false
fi
echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=${GATE} source=${SRC} verified=${VERIFIED}"
# --- end resolver ---
```

**`VERIFIED` is the gate, not a label.** Every dispatch below it sits inside `if [ "$VERIFIED" = true ]`; on `false` the gate runs its existing degraded arm and executes nothing under `$ROOT`. The pre-#8061 behaviour, restored.

**Arm order is a decision.** Arm 1 is the only value the loader fixes *before* bash sees the text (A10), so on a substituting harness there is no environment-supplied operand to direct — the property A11 ground 1 relies on. It also serves the read-from-disk surfaces (Codex, Devin CLI), whose `INSTRUCTIONS.md` §"Paths and entry points" tell the agent to set `CLAUDE_PLUGIN_ROOT` to the verified installed root. Arm 2 is Grok's runtime variable.

**The Devin cache arms stay in Step 0.5 only; the shared resolver carries neither.** Step 0.5 keeps a cache fallback *below* its resolver, widened to both documented Devin caches and gated on directory existence so a non-Devin box searches nothing:

```bash
if [ "$VERIFIED" != true ]; then
  for d in "$HOME/.local/share/devin/cli/plugins/cache" /opt/.devin/plugins; do
    [ -d "$d" ] || continue
    MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' \
      -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"
    if [ -n "$MANIFEST" ]; then
      ROOT="${MANIFEST%/.claude-plugin/plugin.json}"; SRC=devin-cache; VERIFIED=true
      echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=${GATE} source=${SRC} verified=${VERIFIED}"
      break
    fi
  done
fi
```

Why the cache arms are **not** in the shared resolver, as a decision rather than an omission: they would make the *mutating* gate (Step 0) newly reachable on a harness where it has always skipped, and `cleanup-merged` on a plain clone deletes remote branches, closes their PRs, hard-resets the tree and writes git config. Step 0.5 only classifies; Step 0.0 only probes readiness and already answers correctly via its inline `git rev-parse` fallback. The cache arms therefore buy cloud-mode classification — the thing Devin sessions actually need — at no blast radius. Extending them to Step 0 is filed (AC13b), gated on the script-side fix (AC13a).

`codex/INSTRUCTIONS.md` says "never search another harness's cache"; the `[ -d ]` gate means a Codex-only box searches nothing, and on a box carrying both installs the arm is reached only when arms 1–2 produced nothing (i.e. the Codex agent did not follow its own INSTRUCTIONS) and returns an **identity-verified Soleur plugin** — the same plugin, not another harness's. Recorded as a deliberate divergence in decision 11. Note the contrast this creates with the 74-file cloud-mode fleet block, which selects the same cache **by basename with no identity check**; that inconsistency is filed (AC13c) rather than papered over.

**Step 0 additionally gates on the session class, in its own fence.** Bash carries no state between fences, so Step 0.5's verdict is unavailable to Step 0 (ADR-179 amendment 2026-08-11 §"Why the axes stay separate" item 3). Step 0 therefore runs `cloud-detect.sh` from its own verified root and dispatches `cleanup-merged` only on `local` or `not-local:no-devin-env`; any other verdict emits `SOLEUR_SESSION_START_SKIPPED reason=cloud-session` — a new *reason value* on an existing marker name, which changes no classification because `WEDGE_RE` does not match that name at all. This is a **session-class** gate, not a resolution-arm gate: a `SRC != devin-cache` test would not fire, because a Devin agent following its own INSTRUCTIONS resolves as `plugin-root-token`.

**Portability.** Every binary is POSIX and present on stock macOS: `find` (`-path`, `-exec … +`), `grep -l/-q`, `head -1`, `[`. `xargs -r`, `readlink -f`, `stat -c`, `sed -i` and `timeout` are deliberately absent.

Existing branch bodies keep their marker strings verbatim — `SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=…`, `SOLEUR_CLOUD_DETECT_SKIPPED reason=script-unreachable`, `SOLEUR_SESSION_START_SKIPPED reason=…` — because `plugin-root-anchoring.test.ts` P8 and `workflow-fidelity.test.ts` pin them and the hosted `WEDGE_RE` lookahead discriminates on them (learning 2026-08-12).

**What the identity preflight does and does not buy.** It refuses a root whose manifest is not Soleur's. It does **not** authenticate the root: a planted directory containing `{"name":"soleur"}` passes byte-for-byte, and a `gh pr checkout` tree satisfies it the same way (A11, which rejected the stronger root-outside-worktree assertion and recorded the preflight as defence-in-depth). On arm 1 the security claim is carried by the loader. **On arms 2 and 3 there is no such carrier, so the preflight becomes the sole control** — a promotion A11 explicitly declined to rely on, which is why arm 3 is confined to the non-mutating gate. Stated in decision 11; pinned by R6b so a future author cannot mistake the shape check for authentication.

### 2. Consumers for the new marker

- **go.md prose (layer 7, `cli-stdout-artifact`).** After the Step 0.0 fence, **four** state-keyed sentences, because one blanket "file a defect" misattributes a customer's configuration to Soleur (CPO note B, widened by spec-flow):
  - `source=none` **on Claude Code or Concierge** — no arm produced a root where the loader was expected to substitute one: a **Soleur plugin defect**. Per `wg-every-session-error-must-produce-either`, file an issue on `jikig-ai/soleur` quoting the three `RESOLVE` lines, then continue on the fallback.
  - `source=none` **on a read-from-disk harness (Codex, Devin CLI)** — nothing substituted and nothing set the variable: **set `CLAUDE_PLUGIN_ROOT` per your harness's `INSTRUCTIONS.md`** and re-run. Not a Soleur defect.
  - `source=grok-env verified=false` — `GROK_PLUGIN_ROOT` is set but does not point at the Soleur plugin: a **local configuration fact**. Check what it targets (`grok inspect`). Not a Soleur defect.
  - `verified=false` with any other `source` — a root arrived but carries no Soleur manifest: a **torn or stale install**. Reinstall/update; file an issue only if a fresh install reproduces it.

  This split is the state-discriminating shape `incident/SKILL.md` §halt markers uses.
- **CI (both surfaces).** `plugins/soleur/test/go-session-gates.test.sh` executes the delivered fence bytes, so a rewrite that breaks resolution reddens the PR instead of degrading silently — the consumer #8308's "future regression self-reports" clause needs, and with Guard 2 the mechanical answer to #8283 §2 on the surface where the marker lives.
- **Hosted mirror: drafted, then cut.** An earlier draft added the marker to `git-lock-marker-telemetry.ts` `MARKER_RE` with a value-discriminating lookahead. Cut for three converging reasons: the hosted path exports the root fail-closed per dispatch (`agent-runner-query-options.ts`), so the degraded shape cannot occur there by the plan's own argument; every existing `MARKER_RE` entry is `NAME\b.*`, with value discrimination reserved for `WEDGE_RE`, so a field-order change in go.md would silently stop mirroring; and the drift guard walks `skills/*/scripts/*.sh` + `skills/*/SKILL.md`, never `commands/`, so coverage would rest on a hand-typed fixture. Consequence stated: on Concierge a degraded resolution stays transcript-only — the same position as today.

### 3. Tests

**New: `plugins/soleur/test/go-session-gates.test.sh`** (auto-registered — `SUITE_GLOBS` in `scripts/test-all.sh:78` carries `plugins/soleur/test/*.test.sh`, and `scripts/lint-orphan-test-suites.sh` walks it). Sources `test-helpers.sh` and **checks `git_fixture_env`'s exit status** (`fixture-env-adoption.test.sh` Guard 5 requires the check, not just the call). Helpers:

- `extract_fence <heading-anchor>` — awk, **flag-based, never an `/A/,/B/` range**: `awk '$0 ~ h {flag=1; next} flag && /^```bash$/ {inf=1; next} inf && /^```$/ {exit} inf {print}'`. A range address opens *and* closes on the start line whenever the end pattern matches it, silently yielding an empty body every downstream assertion then passes over. Anchors are heading texts, never line numbers. Fence tracking reuses the shape of `exec_lines` in `redact-sentinel.test.sh`.
- `deliver <root>` — the loader simulator: replace only the exact literal `${CLAUDE_PLUGIN_ROOT}`. Pinned to `arm4-probe/arm5-delivered.txt`, the machine-readable artifact Phase 0 writes (prose in `phase-1-measurement.md` cannot be `cmp`'d, and a simulator pinned to the author's model is the failure H1 exists to prevent).
- `mk_root <dir> <manifest-name>` — fixture plugin root, with **every fixture file written from a quoted heredoc** (heredoc bodies are invisible to `plugins/soleur/test/lib/fixture-scan.py`, so this is what keeps the two row-by-row-equality baselines from churning — see §3b): `.claude-plugin/plugin.json` with the given name; `scripts/cloud-detect.sh` and `skills/git-worktree/scripts/git-repo-readiness-diag.sh` copied from the payload; `skills/git-worktree/scripts/worktree-manager.sh` a **stub** printing `STUB_WORKTREE_MANAGER argv=$*` (the real one deletes remote branches). A decoy root makes every script print `DECOY_EXECUTED`.
- `mk_workspace` — temp git repo via `git_fixture_env`, branch `main`, `.mcp.json` committed as `{"fixture":"main"}` then overwritten in the working copy so the restore is observable.
- `run_gate <gate> <delivered|literal> <env-spec>` — runs the fence body with `env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT -u CLAUDE_PROJECT_DIR`, every `DEVIN*` variable scrubbed, **`HOME` on scratch** (so the Devin CLI-cache arm can never reach a developer's real cache), `cd` into the workspace; captures stdout+stderr.

Rows (`⊂` contains, `⊄` does not):

| # | Arrangement | Assert |
|---|---|---|
| R1 | 0.0 delivered→fixture, env unset | ⊂ `SOLEUR_PLUGIN_ROOT_RESOLVE gate=readiness source=plugin-root-token verified=true`; ⊂ `SOLEUR_GIT_REPO_READY=true`; ⊄ `probe-unreachable` |
| R2 | 0.5 delivered→fixture, env unset | ⊂ `gate=cloud-detect source=plugin-root-token verified=true`; ⊂ `not-local:no-devin-env`; ⊄ `SOLEUR_CLOUD_DETECT_SKIPPED` |
| R3 | 0 delivered→fixture, env unset | ⊂ `gate=session-start source=plugin-root-token verified=true`; ⊂ `STUB_WORKTREE_MANAGER argv=cleanup-merged`; `.mcp.json` now equals `git show main:.mcp.json`; ⊄ `SOLEUR_SESSION_START_SKIPPED` |
| R3b | static: every `bash "${ROOT}/…"` operand literal in the three fences | the payload-relative remainder resolves to an existing file under `plugins/soleur/`. R3's stub proves the fence *computed* a path, not that the real script is still there — the `2026-02-22-cleanup-merged-path-mismatch` class |
| R3c | 0 delivered→fixture, env unset, fixture `cloud-detect.sh` stubbed to print `not-local:sentinel-absent` | ⊂ `SOLEUR_SESSION_START_SKIPPED reason=cloud-session`; ⊄ `STUB_WORKTREE_MANAGER` — the session-class gate asserted rather than described |
| R4 | each, **literal** (undelivered), env unset | ⊂ `source=none verified=false`; ⊂ the gate's existing `plugin-root-unverified` / `script-unreachable` skip marker; 0.0 additionally prints the ordered pair `false` then `true` (measured: `--is-bare-repository`→`false`, `--is-inside-work-tree`→`true`; exactly one `true`) |
| R5 | each, literal, `GROK_PLUGIN_ROOT=<fixture>` | ⊂ `source=grok-env verified=true`; the real probe / stub ran |
| R5b | each, literal, `CLAUDE_PLUGIN_ROOT=<fixture>` | ⊂ `source=plugin-root-token verified=true`; the real probe / stub ran — the Codex and Devin-CLI happy path, covered by no other row |
| R5c | 0.5 literal, env unset, scratch `HOME` containing a planted `…/devin/cli/plugins/cache/x/.claude-plugin/plugin.json` naming soleur | ⊂ `gate=cloud-detect source=devin-cache verified=true`; the real `cloud-detect.sh` ran. **Behavioural** coverage for the arm R9 otherwise pins only as a string |
| R6 | each, delivered→decoy (manifest `name: evil`) | ⊂ `source=plugin-root-token verified=false`; ⊂ the skip marker; ⊄ `DECOY_EXECUTED` |
| R6b | each, delivered→decoy whose manifest **claims** `name: soleur` | ⊂ `verified=true`; `DECOY_EXECUTED` **present**. Must-PASS, documenting the limitation: the preflight is a shape check, not authentication (A11). The precondition holds and the security property fails — the row Phase 2.12 requires. If it ever fails, someone added a trust assertion the ADR rejected, and the ADR must be superseded first |
| R6c | each, delivered→root that is ours but whose **payload script is absent** | ⊂ `verified=true` **and** ⊂ the gate's `absent-from-verified-root` skip marker; nothing executed. Covers the reachable `verified=true`-and-skipped state |
| R7 | each, delivered→fixture, env `CLAUDE_PLUGIN_ROOT=/tmp/DECOY-A GROK_PLUGIN_ROOT=/tmp/DECOY-B` | ⊂ `source=plugin-root-token verified=true`; ⊄ `DECOY` anywhere — the A10 control |
| R8 | static: resolver snippets between the anchors, all three fences | byte-identical (`cmp`); exactly three extracted; each holds `${CLAUDE_PLUGIN_ROOT}` exactly once. `GATE=` sits above the opening anchor and is excluded |
| R9 | static: the **code lines** of every bash fence in go.md — comment lines stripped, because prose and comments explaining the ban legitimately contain the banned tokens and an unscoped absence grep false-fails a correct file (`redact-sentinel.test.sh` Test 21 is the fence-scoping *technique's* precedent — it scans the secret gates, not go.md, so it is a pattern to copy rather than existing coverage; go.md on `main` already carries "never default to ./plugins/soleur" inside a fence comment) | ⊄ `/\$CLAUDE_PLUGIN_ROOT(?!\})/`; ⊄ `${CLAUDE_PLUGIN_ROOT:`; ⊄ `:-./plugins/soleur`, ⊄ `:-plugins/soleur`; ⊄ `xargs -r`, `readlink -f`, `stat -c`, `sed -i`, `timeout` + space; ⊄ `set -e`, `set -u`, `set -o pipefail`, `set -euo pipefail` in any of the three fences; the `RESOLVE` echo lines ⊄ `$ROOT` and ⊄ `${ROOT}`; the two Devin cache paths appear in **Step 0.5's fence only** |
| R10 | anti-vacuity floor | the `fixture-relative-assert.test.sh` **triple-check**: `pass`/`fail` counters, a per-verdict `VERDICT_LOG` ledger, and an exit-time floor derived from the row table's length with the ledger as the authority (`grep -c '^FAIL$'`). The ledger is what a pre-seeded counter cannot fake. An extractor yielding ≠ 3 fences, any empty extracted body, or any `~~~`/CRLF fence in go.md is a FAIL and never a skip (ADR-177: a suite that could not run is UNRESOLVED, not passed) |
| H1 | harness: `deliver` self-test | `${CLAUDE_PLUGIN_ROOT:-x}/y` and `$CLAUDE_PLUGIN_ROOT/y` survive delivery unchanged; the substituted form `cmp`s equal to `arm4-probe/arm5-delivered.txt` |
| H2 | must-PASS non-canonical | a synthesized go.md variant with a different `GATE=` value, extra prose lines and reordered comment text *outside* the anchors passes R8/R9 |
| H3 | **real-harness contact** — `claude -p --plugin-dir "$(git rev-parse --show-toplevel)/plugins/soleur" --allowedTools "Bash" "Run each of the /soleur:go Step 0.0, Step 0.5 and Step 0 bash blocks exactly as delivered, then stop."` | all three `… source=plugin-root-token verified=true` lines appear. The one row not mediated by the simulator: the bug was a mis-modeled loader CI certified for a week, so a simulator-only suite cannot see that class recur. Prints `SKIP-DECLARED reason=claude-binary-absent` **derived from `command -v claude`**, never unconditional. This inverts ADR-188's "FAIL in CI, SKIP locally" default **deliberately**: CI does not and should not install the Claude CLI, so a CI skip is the expected state rather than a broken environment — and the arm cannot silently disarm because AC12 makes a real run mandatory pre-merge and commits its output. Cite ADR-188 at the skip site so the divergence reads as a decision |

### 3b. Harness precedent (deepen-plan Phase 4.4 precedent-diff)

The suite adopts existing repo forms rather than inventing them. Each row below is a precedent that was read, not recalled.

| Concern | Precedent to adopt | Why it changes the design |
|---|---|---|
| Fence extraction | `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` → `extract_gate_anchor()` (the `/^[[:space:]]*```bash[[:space:]]*$/ { infence = 1; next }` awk) — the canonical fence tracker; `exec_lines` in the same file is the *line-classifier* built on top of it | Copy `extract_gate_anchor`'s fence bookkeeping verbatim and change only the inner match. It handles the info string and leading whitespace; it does **not** handle `~~~` or CRLF, and go.md uses neither — assert that rather than assume it (a `~~~` fence or a CR would silently yield an empty body, which R10 must catch) |
| Hermetic fixtures | `plugins/soleur/test/lib/git-fixture-env.sh` → `git_fixture_env <dir>`: scrubs every `GIT_*` by prefix plus `SSH_ASKPASS`, pins `GIT_CEILING_DIRECTORIES`, `GIT_CONFIG_NOSYSTEM=1`, a synthesized identity and `commit.gpgsign=false`, and **returns non-zero without exporting anything** when the ceiling would be unenforceable | Use the checked form `if ! git_fixture_env "$dir"; then fail …; fi`, which is both the documented contract and what `fixture-env-adoption.test.sh` Guard 5 enforces |
| Assertions and the anti-vacuity floor | `plugins/soleur/test/fixture-relative-assert.test.sh` → the **triple-check**: `pass`/`fail` counters, a `VERDICT_LOG` ledger appended per verdict, and a `MIN_ASSERTIONS` floor checked at exit with the ledger (`grep -c '^FAIL$'`) as the authority | Stronger than R10 as first drafted. R10 adopts all three: counters, the ledger, and a floor derived from the row table's length — the ledger is what makes mutation row 16 (a counter pre-seeded to the expected total) reddable, because the ledger's line count cannot be pre-seeded by an initialiser |
| Skip semantics | `plugins/soleur/test/lib/gitleaks-probe.sh` + **ADR-188**: "a guard that can silently disarm must FAIL in CI and SKIP only locally" — per-arm, never per-suite, and under `CI=true` the suite exits 1 naming every skipped arm | H3 **inverts this default, deliberately and with the reason stated**: gitleaks is a pinned binary CI installs, so a skip there is a broken environment; the Claude CLI is not installed in CI and must not be, so H3's skip is the *expected* CI state. The invariant is preserved elsewhere — AC12 makes a real H3 run mandatory pre-merge and commits its output, so the arm cannot silently disarm; it is merely verified by a different runner. Cite ADR-188 at the skip site so the divergence reads as a decision |
| Temp dirs and baseline churn | `fixture-relative-assert.test.sh` → `TMP_ROOT=$(mktemp -d -t …)`, then `: "${TMP_ROOT:?…}"` before any `rm -rf`, then `trap 'rm -rf "$TMP_ROOT"' EXIT`. And, load-bearing for AC6: `plugins/soleur/test/lib/fixture-scan.py` **skips heredoc bodies** | Write every fixture file (manifests, stub scripts, the decoy roots) as a **quoted heredoc**, not as a sequence of `echo`/`cd` statements. Heredoc bodies are invisible to the scanner, so the two row-by-row-equality baselines move by the minimum possible — which makes AC6's line-by-line diff review tractable instead of a wall of new rows |
| Scrubbed / overridden env | `redact-sentinel.test.sh` uses the `VAR=value "$BASH_BIN" "$SCRIPT"` prefix form with absolute tool paths | That form *overrides*; `run_gate` must also *unset*, so it composes both: `env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT -u CLAUDE_PROJECT_DIR HOME="$SCRATCH_HOME" "$BASH_BIN" "$fence"`. Resolve `bash` with `command -v` rather than relying on `PATH` |
| Marker plus downstream effect | `redact-sentinel.test.sh` Test 13f pairs a `grep -qE` marker assertion with a `! grep -E` anti-marker; `gitleaks-merge-commit.test.sh` reads a blob with `git show HEAD:<path>` and compares counts | R3's `.mcp.json` assertion uses `git show main:.mcp.json` and compares against the working copy — the same shape, not a bespoke one. R6/R7's `⊄ DECOY_EXECUTED` is the anti-marker half |

**Corrected static guards — with their floors.**

- `apps/web-platform/test/plugin-root-anchoring.test.ts`: `ROOT_ASSIGN_LITERAL` → `ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token`; `isSafelyAnchored` keeps its shape, and **every consumer** (`P4`, `P6`, `P8`) is re-verified rather than only the constant. P1b stays **whole-file** over `commandFiles()` — going fence-scoped would silently *narrow* an existing guard — and gains a regex predicate `/\$CLAUDE_PLUGIN_ROOT(?!\})/` (a bare `includes` would self-trip on every `${CLAUDE_PLUGIN_ROOT}`) plus `${CLAUDE_PLUGIN_ROOT:`. Its positive control gets **its own fixture array and its own `it`** inside the command-surface describe, driven through the same `src` predicate — not `ANCHOR_FIXTURES`, whose consumers and tag union belong to the skills block. **`:682` `expect(assertions).toBe(14)` is an exact-equality floor: it must be raised to the new decided-assertion count in the same edit**, or the suite is red on arrival. The skills block (`:1263` `toBe(18)`) is untouched, so `redact-sentinel.test.sh:880` `T20_FLOOR=18` — which reads that declared floor cross-file — does not move. The header comment's "dual-harness alias" paragraph is rewritten; it currently documents the defect as the sanctioned form.
- `plugins/soleur/test/workflow-fidelity.test.ts`: renamed "go.md plugin-root resolves from the loader token, then GROK_PLUGIN_ROOT, with no CWD default"; expects `ROOT="${CLAUDE_PLUGIN_ROOT}"`, `GROK_PLUGIN_ROOT`, `SOLEUR_PLUGIN_ROOT_RESOLVE`, `plugin-root-unverified`, `grok inspect`; `not.toContain(':-$CLAUDE_PLUGIN_ROOT')` and `not.toContain(':-./plugins/soleur')`; `name=soleur` grep count ≥ 3.
- **Baselines that move because a new `.sh` file exists at all:** `plugins/soleur/test/fixture-relative-assert.baseline.txt` and `fixture-dir-operand-assert.baseline.txt` are row-by-row-equality corpora built from `git ls-files '*.sh'` repo-wide ("a fall reddens exactly like a rise"). Both are regenerated via their suites' `--write-baseline` in the same commit, and the regenerated diff is reviewed rather than accepted blind.

### 4. Measurement (Phase 0)

Extend the committed probe at `specs/feat-one-shot-7450-git-root-anchor-untrusted/arm4-probe/` with a **command-surface** twin (`commands/zzzprobe.md`) whose fence writes, through a quoted heredoc, the delivered bytes of four forms: bare `${CLAUDE_PLUGIN_ROOT}`; the #8061 form; unbraced `$CLAUDE_PLUGIN_ROOT`; single-quoted `'${CLAUDE_PLUGIN_ROOT}'`. Run once per the probe README recipe with a decoy `CLAUDE_PLUGIN_ROOT` live as the control, and once under the Grok CLI if `command -v grok` succeeds. Write the delivered bytes to **`arm4-probe/arm5-delivered.txt`** (machine-readable, consumed by H1) and the narrative to `phase-1-measurement.md` §Arm 5.

**Stop-condition decision table** — one row per outcome, so the halt is an instruction:

| Observation | Action |
|---|---|
| Bare token substituted; #8061 form literal (predicted) | Proceed to Phase 1. |
| Bare token **not** substituted | STOP. Arm 1 and the fix are falsified. Write `specs/feat-one-shot-8308-go-gates-plugin-root/phase-0-stop.md` with the captured bytes, comment it on #8308, re-plan. No PR. |
| #8061 form **also** substituted | STOP, same artifact and comment. `main` was never broken by the form; re-scope. |
| Unbraced `$CLAUDE_PLUGIN_ROOT` substituted | STOP, same artifact. The loader's contract is not exact-literal, invalidating R9, P1b and §R3's reasoning; re-plan with ADR-179's record reopened. |
| Single-quoted form substituted | Proceed. Record Alternatives row 4 as viable-but-not-adopted; do not switch in this PR. |
| Grok cell: token substituted | Proceed, and record in decision 11 that `GROK_PLUGIN_ROOT` is demoted on Grok — a deliberate precedence change. |
| Grok cell: token not substituted, or `grok` absent | Proceed. Arm 2 fires on Grok exactly as today; the A11 residual stays open and is restated. |
| Probe unrunnable (no `claude` binary, headless auth) | Proceed **only** via the H3/AC12 route: capture the same cells from the live `claude -p --plugin-dir` run at Phase 3, and let Phase 1 proceed on §R3/A10's two prior measurements. Record `deferred-to-AC12` in `phase-0-stop.md`. H1 then pins against the AC12 capture instead. |

## Technical Considerations

- **ADR-179 compliance.** Decision 1 is restored on the command surface. Options (d)/(e) and A11 remain rejected — no `git rev-parse`, no `CLAUDE_PROJECT_DIR`, no CWD default; `redact-sentinel.test.sh` Test 21 stays green. What is genuinely new — a fallback *order*, and a cache arm whose only control is the identity preflight — is recorded as a **new decision**, not an amendment item.
- **`set -e` / `set -u` / `set -o pipefail`.** Line 1 is deliberately unguarded so it stays the exact token; line 2 is `${GROK_PLUGIN_ROOT:-}`. That asymmetry is safe only while no fence enables `-u`, which would abort *before* any `RESOLVE` line — a silent skip with no marker, i.e. the bug class at one remove. `-e` matters independently: `find` on an absent directory returns non-zero. R9 pins all four spellings absent; this is mandatory, not reviewer-contingent.
- **Grok Build — a measured-not-assumed change in one branch.** An earlier draft said "behaviour on Grok is unchanged whether or not the token is substituted." **False.** Today `GROK_PLUGIN_ROOT` wins unconditionally (it is the `:-` expansion's left operand). Under token-first, *if* Grok's loader also substitutes `${CLAUDE_PLUGIN_ROOT}`, arm 1 resolves and `GROK_PLUGIN_ROOT` is **never consulted** — a silent change for any Grok user whose two values differ. Whether Grok substitutes is exactly the A11 residual, i.e. unmeasured, so this is *unmeasured*, not *safe*. Phase 0 measures it; either outcome is recorded in decision 11. In the supported configuration the two coincide (`.grok/config.toml` sets `paths = ["./plugins/soleur"]`), and for an operator who pointed the variable elsewhere the substituted root is the more trustworthy of the two under decision 1.
- **Devin cloud — this plan's own P0, corrected.** The first draft promoted the cache arm into all three gates and called `cleanup-merged` "read-mostly on a plain clone". It is not: `worktree-manager.sh:2773` includes merged and `[gone]` branches with **no worktree**, whose safety guards are all gated on a non-empty worktree path (`:2851`, `:2868`, `:2890`, `:2905`, `:2942`), so the loop still reaches `git push origin --delete` (`:2954`), `git branch -D` (`:2960`) and `git -C "$GIT_ROOT" reset --hard HEAD` (`:2999`); it also takes a cross-session lock and calls `ensure_bare_config`, which writes git config. ADR-178 §Context calls it "unrecoverable". The corrected design keeps the cache arms out of Step 0 **and** adds a session-class gate inside Step 0's own fence, because a resolution-arm gate would not fire. Asserted by R3c and protected by mutation rows 8–9, not merely described.
- **Pre-existing defects, filed not fixed** (`wg-when-an-audit-identifies-pre-existing`, AC13): (a) `worktree-manager.sh:82` prints "cleanup-merged will REFUSE to reap any worktree (fail-closed)" when the lease library is missing, but the lease check at `:2868` is gated on a non-empty worktree path, so merged branches with no worktree bypass it and still reach `git push origin --delete` — the banner overstates the guarantee on exactly the layout this class of change dispatches into. (c) the 74-file `soleur-cloud-mode` fleet block resolves the Devin cloud cache **by basename with no `name=soleur` check**, which is the shadowing hazard go.md's identity-gated arm avoids; the two now disagree about the same lookup.
- **Marker-name reuse.** `SOLEUR_PLUGIN_ROOT_RESOLVE` is a **new** name, so it inherits no consumer's classification (learning 2026-08-12); `reason=cloud-session` is a new *value* on an existing name and changes no classification because `WEDGE_RE` does not match that name. Existing marker bytes are untouched.
- **Privacy / GDPR (Phase 2.7).** No regulated-data surface, and none of the (a)–(d) expansion triggers fire. One constraint keeps that true: **the `RESOLVE` line prints `source=` and `verified=` only — never `$ROOT`** — so no filesystem path, workspace id or operator-identifying string leaves the session. R9 pins the absence mechanically; a future edit interpolating the path needs the gate re-run.
- **Infrastructure (Phase 2.8).** None. The one candidate (a Better Stack alert) is cut, so no Terraform root changes.
- **Encryption posture (Phase 2.11 / deepen-plan 4.10): gate does not fire, recorded because a keyword invites the opposite conclusion.** Nothing in Files to Edit or Files to Create is a Terraform root, a Supabase migration, a cloud-init file or a compose file, and the plan introduces no persistent store and no new cross-component or network connection. The word *cache* appears throughout, but it names the harness's **pre-existing, read-only** plugin install directories (`~/.local/share/devin/cli/plugins/cache`, `/opt/.devin/plugins`) that the resolver reads one manifest from — it creates nothing, mutates nothing, and stores no data. The only bytes this change puts on disk at runtime are `.mcp.json` inside the session's own checkout, restored from that checkout's own `main`.
- **Downtime & cutover (deepen-plan 4.55): gate does not fire.** No infra reboot or replace class (no `hcloud_*`, no placement group, no server-type change), no database lock class (no migration), no deploy/router class (no container swap, no tunnel change). The change is markdown and test files; nothing serving goes offline. The one behaviour that *could* have taken something down — `cleanup-merged` reaching a cloud session's single clone — is the P0 the plan exists to prevent, and it is prevented by confinement plus the session-class gate rather than by a maintenance window.
- **Security, attack surface enumerated.** (i) loader token — fixed by the trusted loader, not environment-directable; (ii) `GROK_PLUGIN_ROOT` — environment, exactly as directable as the #8061 form was, so no regression; (iii) the two Devin cache paths — read only when the directory exists, only after arms 1–2 fail, only in the non-mutating gate, only for an identity-matching manifest. An earlier draft also called `/opt/.devin/plugins` "root-owned"; a deepen-pass check found **no repo file documents its ownership** and the directory does not exist locally, so that property is withdrawn: the arm's bound is the identity grep plus its confinement to Step 0.5, not an unverified filesystem permission; (iv) the identity grep — a `gh pr checkout` tree satisfies it (A11), which is why (i) carries the claim on arm 1 and why (iii) is confined away from the destructive dispatch.
- **Performance.** Three `echo`s and, on Claude Code, zero extra processes. The Devin `find` runs only when its directory exists and arms 1–2 produced nothing.
- **NFR register.** Read `knowledge-base/engineering/architecture/nfr-register.md` at work time; affected NFRs are supportability and security; no capacity or latency NFR moves.

## Alternative Approaches Considered

| # | Alternative | Why not |
|---|---|---|
| 1 | Keep `GROK_PLUGIN_ROOT` first, fix only the token | Fixes the bug and preserves #8061's precedence, but leaves the root environment-directable on Claude Code via an ambient `GROK_PLUGIN_ROOT`, contradicting A11 ground 1. Token-first is strictly safer; the Grok precedence change is measured and recorded rather than hidden. |
| 2 | `CLAUDE_PROJECT_DIR` / `BASH_SOURCE` (#8308 remedy 1) | Both empty in a Bash-tool fence (measured); when set, `CLAUDE_PROJECT_DIR` is the workspace — options (d)/(e)/A11's rejected class. |
| 3 | Merge the three gates into one fence | Changes the step structure `plugin-root-anchoring.test.ts` P4/P6/P8 and the Step 0.0 STOP semantics are written against. Three identical, test-pinned copies cost ~15 lines. Rejected, not deferred. |
| 4 | Single-quoted token + `case "$ROOT" in /*)` | Would make arm 1 provably non-environment on non-substituting harnesses too, but whether the loader substitutes inside single quotes is unmeasured. Phase 0 measures it; adopted only in a follow-up if positive. |
| 5 | Mirror the marker hosted (`MARKER_RE`) and/or a Better Stack alert (#8308 remedy 2) | Both cut — §2's three reasons for the mirror; for the alert, it observes only the hosted path where the root is exported fail-closed, and the 5-step alert pattern plus runbook is disproportionate. Consequence stated: hosted degradation stays transcript-only, as today. |
| 6 | Re-tier or retire `wg-at-session-start-run-bash-plugins-soleur` (#8308 remedy 3) | Moot once the gate runs. |
| 7 | Fold #7453 (skill-site `:-` migration) in | Inverse failure, different remedy (#8308 §"Why this is not just #7453"). Not folded. |
| 8 | Promote the Devin cache arms into all three gates (this plan's first draft) | Makes `cleanup-merged` newly reachable on Devin cloud, where it deletes remote branches, closes PRs, hard-resets and writes git config. Confined to Step 0.5; extension filed (AC13b) behind the script fix (AC13a). |
| 9 | Gate Step 0 on `SRC != devin-cache` | Does not fire: a Devin agent following its own INSTRUCTIONS resolves as `plugin-root-token`. The hazard is the session class, so the gate must be the session classifier. |
| 10 | Fold the 74-file `soleur-cloud-mode` fleet block's basename-selected cache recipe into this PR | A 74-file edit pinned by its own drift test, on a different marker family, in a PR whose threshold is `single-user incident`. Filed as AC13c with the inconsistency named, rather than either ignored or swept in. |

## User-Brand Impact

- **If this lands broken, the user experiences** (per persona, so `user-impact-reviewer` can cross-check each against the diff):
  - *Solo founder, local CLI, resolution stays empty (today's bug):* no error at all. `/soleur:go` proceeds; merged worktrees and temp dirs accumulate (188 reaped by hand in one session); `.mcp.json` is never refreshed at the bare root, so MCP servers are silently absent and a skill fails later with "tool not found", far from the cause.
  - *Solo founder, an implementer reintroduces a CWD default:* the first Bash call of every session executes a `worktree-manager.sh` / `cloud-detect.sh` / `git-repo-readiness-diag.sh` from the checked-out tree — their own repo, or a PR branch they checked out — with their `gh`/Doppler/SSH credentials. The #7442 reporter's incident.
  - *Solo founder, a future change promotes the cache arm into Step 0 without the session gate:* a cloud session reaps merged branches that have no worktree, deleting remote branches and closing their PRs, and hard-resets over uncommitted work. This is why the arm is confined, why R3c asserts the gate, and why mutation rows 8–9 exist.
  - *Concierge web user:* the root is exported fail-closed per dispatch, so behaviour is unchanged. A degraded resolution would show one `RESOLVE … source=none verified=false` line in the first tool result and the session would continue on the readiness fallback — no page, no blocked route, and (with the mirror cut) no hosted row: the same position as today.
  - *Devin cloud user:* Step 0.5 now classifies correctly instead of skipping, so the cloud contract (sequential-fallback disclosure, ack before secrets) is decided by `cloud-detect.sh` rather than by the absence of a signal. Step 0 continues to skip, now with an honest `reason=cloud-session`.
  - *Codex / Devin-CLI user:* if the agent follows its harness INSTRUCTIONS and sets `CLAUDE_PLUGIN_ROOT`, all three gates run (R5b). If not, they see `source=none` and a sentence telling them to set it — not an instruction to file a Soleur issue.
  - *Grok Build user with `GROK_PLUGIN_ROOT` pointing at a non-Soleur plugin:* `verified=false` and the gate skips, with prose naming it as their configuration.
- **If this leaks, the user's workflow/credentials are exposed via:** an environment- or CWD-directed plugin root executing an attacker-chosen `worktree-manager.sh` / `git-repo-readiness-diag.sh` / `cloud-detect.sh` at session start under the operator's credentials — ADR-179's vector. Arm 1 closes it on substituting harnesses; arm 2 is unchanged from today; the cache arms are bounded by directory existence, the identity grep, and confinement to the non-mutating gate.
- **Brand-survival threshold:** `single-user incident` — matches ADR-179's declaration for this trust anchor; one customer's machine executing a hostile script is the incident that opened #7442.

Artifact/vector pairs for `user-impact-reviewer`: (a) stale `.mcp.json` + accumulating worktrees ↔ a gate that skipped; (b) an executed hostile script ↔ a CWD/env-directed root; (c) deleted remote branches and a hard reset ↔ the mutating gate reached on a cloud session; (d) a cloud session claiming review coverage it lacks ↔ Step 0.5 skipped; (e) a misattributed defect report ↔ an undiscriminated degraded marker.

**CPO sign-off (2026-09-19): approve-with-notes.** Notes A (per-persona enumeration), B (state-keyed prose) and C (assert the marker line, not only the mechanism) are applied. Note D (do not fold #7453) was already the plan's position. Threshold and sign-off judged proportionate: ADR-179 already binds this anchor to `single-user incident`, and the plan neither escalates nor dilutes it.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_PLUGIN_ROOT_RESOLVE gate=<readiness|cloud-detect|session-start> source=<arm> verified=<bool> — one line per gate, first Bash call of every /soleur:go session (layer 7, cli-stdout-artifact)"
  cadence: "per session start (3 lines)"
  alert_target: "the in-session agent, via go.md's four state-keyed sentences; on Soleur's own repo the committed AC12 capture under specs/feat-one-shot-8308-go-gates-plugin-root/"
  configured_in: "plugins/soleur/commands/go.md (resolver snippet + the four sentences after Step 0.0); plugins/soleur/test/go-session-gates.test.sh"

error_reporting:
  destination: "layer 7 only, by design — the session's own stdout plus, on this repo, the committed AC12 capture. Routing a self-hosted run's output to Soleur infrastructure is a data-controller event, not an observability improvement."
  fail_loud: "any SOLEUR_PLUGIN_ROOT_RESOLVE line carrying source!=plugin-root-token or verified=false; the existing SOLEUR_*_SKIPPED / probe-unreachable line that follows it"

failure_modes:
  - mode: "go.md rewritten to a non-token form again (the #8308 class)"
    detection: "CI: go-session-gates.test.sh R1-R3 red; workflow-fidelity + plugin-root-anchoring static guards red"
    alert_route: "PR check failure (required checks) — pre-merge, both surfaces"
  - mode: "harness stops substituting the token, or a new harness neither substitutes nor exports"
    detection: "RESOLVE source=none on the first Bash call (layer 7 stdout); go.md's first two sentences discriminate a Soleur defect from a harness-configuration fact"
    alert_route: "issue filed by the session agent (Soleur-defect arm only)"
  - mode: "root resolves but is not the Soleur plugin, or is ours but carries no payload"
    detection: "RESOLVE verified=false (R6), or verified=true followed by the absent-from-verified-root skip marker (R6c)"
    alert_route: "in-session prose (reinstall); CI rows R6/R6c"
  - mode: "a future change reaches the mutating gate on a cloud session"
    detection: "R3c plus Guard 1 mutation rows 8 and 9 — a cloud verdict must produce SOLEUR_SESSION_START_SKIPPED reason=cloud-session and no dispatch, and the cache arm must not appear outside Step 0.5"
    alert_route: "CI red"
  - mode: "the Devin cache arm itself breaks (wrong path, identity grep dropped)"
    detection: "R5c drives source=devin-cache through a planted CLI cache under a scratch HOME. RESIDUAL, stated: the CLOUD path /opt/.devin/plugins is a hardcoded absolute location that cannot be driven in CI without introducing an env-directable search root, which would defeat the arm; R9 pins it as a string only and that is presence, not behaviour."
    alert_route: "CI red for the CLI arm; the cloud arm is covered only by AC11-class live runs"
  - mode: "identity preflight mistaken for authentication"
    detection: "R6b — a decoy manifest claiming name=soleur is accepted and executes; must-PASS, documenting the limitation"
    alert_route: "CI red if someone strengthens the check without superseding A11"

logs:
  where: "the Bash tool result in the session transcript; on this repo, specs/feat-one-shot-8308-go-gates-plugin-root/ac12-capture.txt"
  retention: "session transcript lifetime; the committed capture is permanent"

discoverability_test:
  command: "bash plugins/soleur/test/go-session-gates.test.sh"
  expected_output: "a per-row PASS list ending in a summary line with 0 failures and exit 0 — R1-R3 prove the three delivered gates reach their real probe with the environment unset, R3c proves the cloud gate holds"
```

**Layer citation (`hr-observability-layer-citation`), stated with its gap rather than around it.** The go.md fences run on the customer's own machine (**layer 7, `cli-stdout-artifact`**) and also hosted — the plugin tree is vendored into the production image and loaded by `agent-runner-query-options.ts`, which registers the Bash marker extractor in the same options object — so the same file is layer 7 for a customer and layers 1–2 for the platform. For the hosted path, resolution is carried by the fail-closed per-dispatch export and this change alters nothing there; the drafted `MARKER_RE` mirror was cut (§2). **For the customer path the layer-7 durable-artifact half is NOT closed by this plan.** `observability-coverage-reviewer` §7 requires a committed artifact carrying the same fields, and a discretionary issue filed on Soleur's repo is not one; ADR-179 §Consequences records this exact gap and routes it to **#7452**. This plan therefore claims layer 7's synchronous half only, commits the AC12 capture as the artifact *on this repo*, and leaves the customer-side durable artifact open at #7452 rather than presenting a filed issue as closure.

## Architecture Decision (ADR/C4)

Detection fires: the plan reverses a decision #8061 made on a trust boundary and introduces a *fallback order* plus a cache arm ADR-179 never enumerated.

### ADR

Edit `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md` via `soleur:architecture` — no new ordinal, so no ordinal-collision exposure — with **two** entries, because they are different classes and the ADR's own `## Amendment numbering` note says `### Decision N` headings are decisions while bolded `**N.**` items are amendment items (last item is **A14**, so **A15** is the correct next ordinal):

- **`### Decision 11` — the dual-harness resolution order for command-surface gates.** Normative and prospective, and it materially qualifies Decision 1, whose justification is option (a)'s "the decisive property is the failure mode with the variable unset": under the new resolver the unset case no longer expands to `/scripts/…` and refuse, it falls through to an environment variable and (in Step 0.5) a filesystem scan. The option-(a) failure-mode table is therefore **re-stated, not appended to**. Decision 11 records: loader token first, `GROK_PLUGIN_ROOT` second, Devin cache third **and only in a non-mutating gate**, never CWD; that arms 2–3 **promote the identity preflight to load-bearing**, which A11 explicitly declined to rely on, and that this is why arm 3 is confined; the `SOLEUR_PLUGIN_ROOT_RESOLVE` vocabulary (`source=plugin-root-token|grok-env|devin-cache|none`, `verified=true|false`); the Grok precedence outcome Phase 0 measures; the Codex "never search another harness's cache" divergence with its `[ -d ]` scoping; and the recorded inconsistency with the 74-file fleet block's basename-selected recipe, routed to AC13c.
- **Amendment item `A15`** — the narrow record that `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` (#8061) is a **rejected form**, same class as `:-`: not the loader's token, reaches bash, expands from the environment (empty on Claude Code). Added to the options table's failure-mode column, with A10 re-cited and the A11 Grok residual restated as still open.
- Frontmatter: `related:` gains 8308, 8283, 8061; `related_plans:` gains this plan.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Enumeration — external human actors: `founder` (modelled; runs `/go` on Claude Code, Grok Build, Devin, Codex); external systems: `devin`, `codex`, `platform.grokBuild`, `platform.engine`/`claude` — all modelled; containers/stores: `platform.plugin` (modelled; no new store); actor↔surface access relationships: none change. One relationship description is **falsified** by the arm-order change: `model.c4:423` `grokBuild -> plugin "Loads via .grok/config.toml (GROK_PLUGIN_ROOT then CLAUDE_PLUGIN_ROOT)"`. Task: edit that description to name the loader-substituted token first, citing decision 11. No element or `view … include` change. Verification: `c4-code-syntax.test.ts`, `c4-render.test.ts`, and `bash plugins/soleur/test/c4-count-parity.test.sh` — the edge carries no cardinalities, but the gate is the authority, not this sentence.

### Sequencing

The ADR edit lands **before** the go.md edit (Phase 1.5), so the resolver comment's citation of decision 11 is not a forward reference to a record that does not yet exist. Nothing is soak-gated.

## Guard Contract

### Guard 1 — go-session-gates executable suite

**Property.** With no `CLAUDE_PLUGIN_ROOT`, `GROK_PLUGIN_ROOT` or `CLAUDE_PROJECT_DIR` in the environment, each of the three go.md gate fences, as the loader delivers it, dispatches to the Soleur payload script at the verified root and emits a `SOLEUR_PLUGIN_ROOT_RESOLVE` line naming the arm that produced it; an undelivered fence, an unverified root, a missing payload, an ambient decoy environment, or a cloud session never reaches a dispatch.

**Assembly.** The three ```` ```bash ```` fences under `## Step 0.0: Workspace Readiness Gate`, `## Step 0.5: Cloud Mode detection` and `## Step 0: Session-Start Preamble` in `plugins/soleur/commands/go.md` — the single **dispatch** chokepoint every session-start gate flows through on every harness. That is structural for the three mirrors that delegate — Codex, Devin and `skills/go` — so for those, widening the harness set adds a *delivery mechanism* (loader-substituted, or read-from-disk with the agent setting the variable) rather than a second copy of these gates. It is **not** a universal over every `go` entry point: `.gemini/commands/workflow/go.toml` is a fourth one, it does not delegate, and it carries no gates at all (`grep -c` for the gate anchors returns 0). It is an unshipped research artifact from #1738/#1741, outside `plugins/soleur/`, so it reaches no customer — but the Assembly claim is about entry points, and that one is outside it. It is deliberately **not** the claim that no other plugin-root resolution exists in the payload — the 74-file `soleur-cloud-mode` fleet block carries its own basename-selected `/opt/.devin/plugins` recipe, guarded by `devin-cloud-mode.test.ts` and filed at AC13c; stating the boundary is what keeps this Assembly from being a false universal. `sync.md` has its own preflight and is out of scope. The population is established by `git grep -l` over the resolver's distinguishing literal, not by a file list. Members are extracted by heading anchor and the count is asserted: ≠ 3 fences, or any empty extracted body, is a FAIL (R10). The loader's substitution is modelled by `deliver`, pinned to `arm5-delivered.txt` (H1) and bypassed entirely by the real-harness row (H3).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the resolver's first line to `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"` in all three fences | RED — R1–R3 (`source=none`), R8 (token count 0), R9 |
| 2 | Delete the `echo "SOLEUR_PLUGIN_ROOT_RESOLVE …"` line | RED — R1–R7 (no RESOLVE line) |
| 3 | Remove the `grep -q '"name"…"soleur"'` conjunct (accept any manifest) | RED — R6 (`DECOY_EXECUTED`, `verified=true` on the evil decoy) |
| 4 | Insert `ROOT="${ROOT:-./plugins/soleur}"` **above** the identity check | RED — R9 (`:-./plugins/soleur`, anchored on the expansion so the explanatory comment is not a false positive) **and** R4 (`source` label no longer `none`). Placed above deliberately: below the `echo` it would change no printed label and R9 alone would carry the row |
| 5 | Fix Steps 0.0 and 0.5 but leave Step 0 on the #8061 form (a second member after a compliant first) | RED — R8 (snippets differ), R3 |
| 6 | Change the delivered token to unbraced `$CLAUDE_PLUGIN_ROOT` | RED — R1–R3, R9 |
| 7 | Move Step 0's dispatch above the identity check | RED — R6 (`DECOY_EXECUTED`) |
| 8 | Copy the Devin cache arm into Step 0's fence | RED — R9 (cache paths outside Step 0.5) — the plan's own P0, mechanically prevented |
| 9 | Delete Step 0's `cloud-detect` session-class gate | RED — R3c (dispatch on a `not-local:` verdict) |
| 10 | Rename `worktree-manager.sh` without updating the fence operand | RED — R3b (operand resolves to no file); R3's stub alone would stay green |
| 11 | Add `set -u` to the top of any of the three fences | RED — R9's shell-option clause; without the pin, resolution aborts before any marker on a read-from-disk harness |
| 12 | Replace `-exec grep -l … {} +` with `\| xargs -r grep -l …` (GNU-only; BSD/macOS `xargs` rejects `-r`) | RED — R9's portability clause |
| 13 | Interpolate the resolved path into the marker (`… source=${SRC} root=${ROOT}`) | RED — R9's echo-line clause; keeps paths out of telemetry and the GDPR assessment true |
| 14 | Harness: rename `## Step 0.5: Cloud Mode detection` so the extractor finds 2 fences | RED — R10 (count ≠ 3), never a silent skip |
| 15 | Harness: make `deliver` also replace `${CLAUDE_PLUGIN_ROOT:-` | RED — H1 |
| 16 | Harness: start the assertion counter at the expected total (vacuous floor) | RED — R10's authority is the `VERDICT_LOG` ledger's line count, which an initialiser cannot pre-seed, not the in-memory counter |
| 17 | Harness: make H3 print `SKIP-DECLARED` unconditionally | RED — H3's skip must derive from `command -v claude`, and AC11 requires a real PASS in the worktree |
| 18 | Must-PASS, non-canonical: a go.md variant with `GATE=` two lines above the anchor, an extra blank line and different comment text *outside* the anchors | PASS — H2 |
| 19 | Must-PASS, limitation: a decoy manifest claiming `name: soleur` is accepted and executes | PASS — R6b. The precondition holds and the security property fails; strengthening the check without superseding A11 turns this row red, which is the intended signal |

**Anchor.** The suite compares extracted bytes against each other (R8) and against behaviour (R1–R7, R3b/R3c, H3); it stores no hash or count the same diff could edit. The only stored expectations are marker strings — the contract under test — and `arm5-delivered.txt`, produced by a different process (a headless `claude -p` run) into a separate spec artifact, so it cannot be edited into agreement by the same diff.

### Guard 2 — command-surface anchor-form lint (plugin-root-anchoring P1b + workflow-fidelity)

**Property.** No file in `plugins/soleur/commands/` reads the plugin root through any `CLAUDE_PLUGIN_ROOT` expansion other than the exact loader token `${CLAUDE_PLUGIN_ROOT}`.

**Assembly.** Every file returned by `commandFiles()` over `COMMANDS_DIR` (`go.md`, `sync.md`, `help.md`), whole-file — the scope P1b already has, deliberately **not** narrowed to fences — plus the `workflow-fidelity.test.ts` go.md read. Discovery is a directory listing, never a file list, so a fourth command file joins the guarded set by existing. The predicates are regexes (`/\$CLAUDE_PLUGIN_ROOT(?!\})/`, `${CLAUDE_PLUGIN_ROOT:`), because a bare `includes("$CLAUDE_PLUGIN_ROOT")` self-trips on every compliant `${CLAUDE_PLUGIN_ROOT}`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` in go.md | RED — P1b (unbraced form), workflow-fidelity |
| 2 | Introduce `$CLAUDE_PLUGIN_ROOT/scripts/x.sh` in sync.md (a second member) | RED — P1b |
| 3 | Introduce `${CLAUDE_PLUGIN_ROOT:?msg}` in help.md | RED — P1b; confirms the extended predicate did not narrow the existing one |
| 4 | Add a fourth command file carrying the #8061 form | RED — the assembly is a directory listing, so the new member is guarded without an edit |
| 5 | Harness: empty `COMMANDS_DIR` | RED — P0/P3 floors (existing) |
| 6 | Harness: remove the #8061-form entry from P1b's **own** fixture array | RED — that array's length floor. (Note: the control does **not** live in `ANCHOR_FIXTURES`, whose consumers `G6`/`G6b` are gate-script scanners in the skills describe and whose tag union `G6b` asserts by set equality.) |
| 7 | Harness: leave `expect(assertions).toBe(14)` unchanged after adding P1b's control | RED — the P5 anti-vacuity floor is exact equality; raising it is part of the edit, not an afterthought |
| 8 | Must-PASS, non-canonical: a fence containing the token inside a comment line plus a `${ROOT}` operand | PASS |

## Acceptance Criteria

Every criterion is **pre-merge**. The one item that reads like an operator step (a live harness check) is automatable pre-merge via `claude -p --plugin-dir` against the worktree, which builds its own plugin registry (the A10 method, recorded at `arm4-probe/README.md`). `Automation: not feasible` is claimed nowhere.

### Pre-merge (PR)

- [x] AC1 — `plugins/soleur/commands/go.md` Steps 0.0, 0.5 and 0 each carry `GATE=<name>` above the opening anchor plus the resolver snippet whose bytes between `# --- soleur plugin-root resolver` and `# --- end resolver ---` are identical across the three fences (`cmp` exit 0 for both pairs); arm 1 is the exact literal `${CLAUDE_PLUGIN_ROOT}`, once per snippet; every dispatch sits inside `if [ "$VERIFIED" = true ]`; no fence enables `set -e`/`set -u`/`set -o pipefail`; the two Devin cache paths appear in Step 0.5's fence and nowhere else; Step 0's fence contains a `cloud-detect.sh` call and a `reason=cloud-session` arm.
- [x] AC2 — `bash plugins/soleur/test/go-session-gates.test.sh` exits 0 with rows R1, R2, R3, R3b, R3c, R4, R5, R5b, R5c, R6, R6b, R6c, R7, R8, R9, R10, H1 and H2 all PASS, and H3 either PASS or `SKIP-DECLARED reason=claude-binary-absent` derived from `command -v claude`. R1–R3 run with `CLAUDE_PLUGIN_ROOT`, `GROK_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR` and every `DEVIN*` variable unset, `HOME` on scratch, and assert both the `verified=true` marker line **and** the downstream effect.
- [x] AC3 — Guard 1 mutation rows **1–17** each applied in a scratch copy and each reddened the named rows; rows 18–19 stayed PASS. Guard 2 rows 1–7 reddened, row 8 passed. The run log (row → red assertion ids), the Phase 1 pre-fix red run, and the pre/post `lint-guard-contract.py` counts are recorded in `knowledge-base/project/specs/feat-one-shot-8308-go-gates-plugin-root/mutation-log.md`.
- [x] AC4 — `apps/web-platform/test/plugin-root-anchoring.test.ts`: `ROOT_ASSIGN_LITERAL` updated; `isSafelyAnchored`, P4, P6 and P8 each re-verified against the new literal, not just the constant; P1b stays whole-file over `commandFiles()` and gains the two regex predicates plus **its own** fixture array and positive-control `it` inside the command-surface describe (`ANCHOR_FIXTURES`, `G6`, `G6b` untouched); **`:682` `expect(assertions).toBe(14)` raised to the new decided-assertion count in the same edit**. Verified with the package's own runner — `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts` — **not** `bun test` (`apps/web-platform/bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]`) and **not** `npm run -w` (the root `package.json` declares no `workspaces`).
- [x] AC5 — `plugins/soleur/test/workflow-fidelity.test.ts` no longer contains `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` as an expectation; the renamed test expects `ROOT="${CLAUDE_PLUGIN_ROOT}"`, `SOLEUR_PLUGIN_ROOT_RESOLVE`, `grok inspect`, `not.toContain(':-$CLAUDE_PLUGIN_ROOT')` and `not.toContain(':-./plugins/soleur')`, and pins the `name=soleur` grep count at ≥ 3. `bun test plugins/soleur/test/workflow-fidelity.test.ts` green.
- [x] AC6 — `plugins/soleur/test/fixture-relative-assert.baseline.txt` and `fixture-dir-operand-assert.baseline.txt` regenerated in the same commit via their suites' `--write-baseline`, and the regenerated diff reviewed line-by-line rather than accepted blind (both are row-by-row-equality corpora over `git ls-files '*.sh'`, so a new suite necessarily moves them).
- [x] AC7 — go.md prose after the Step 0.0 fence carries **four** state-keyed sentences (`source=none` on a substituting harness; `source=none` on a read-from-disk harness; `source=grok-env verified=false`; `verified=false` otherwise), each naming a different action, and only the first instructs filing a Soleur issue. The Step 0 comment "Preferring GROK_PLUGIN_ROOT does not weaken…" is replaced by one naming the arm order and decision 11.
- [x] AC8 — ADR-179 carries `### Decision 11` (dual-harness order; arms 2–3 promote the preflight to load-bearing; the confinement of arm 3; the marker vocabulary; the Grok precedence outcome; the Codex cache divergence; the fleet-block inconsistency) **with the option-(a) failure-mode table re-stated**, plus amendment item `A15` recording the #8061 form as rejected; frontmatter `related:` gains 8308/8283/8061.
- [x] AC9 — `model.c4`'s `grokBuild -> plugin` description names the loader-substituted token first and cites decision 11; `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh` green.
- [x] AC10 — Phase 0 recorded: `arm4-probe/arm5-delivered.txt` holds the four delivered strings machine-readably, `phase-1-measurement.md` §Arm 5 holds the narrative plus the decoy control and the Grok cell (or its `grok`-absent note), and the probe is committed under `arm4-probe/commands/`. If the probe was unrunnable, `specs/feat-one-shot-8308-go-gates-plugin-root/phase-0-stop.md` exists and reads `deferred-to-AC12`.
- [x] AC11 — These suites green, each with its own runner: `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — included for Test 20's cross-file `T20_FLOOR=18`, which reads `plugin-root-anchoring.test.ts`'s declared `#7450` floor and is the reason this plan leaves the skills describe untouched. Test 21 scans the three SECRET gates, not go.md, so it is a regression check here rather than coverage of this change; `bash plugins/soleur/test/fixture-relative-assert.test.sh`; `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`; `bash plugins/soleur/test/fixture-env-adoption.test.sh`; `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts plugins/soleur/test/components.test.ts plugins/soleur/test/go-routing-golden-path.test.ts plugins/soleur/test/devin-cloud-mode.test.ts`; `bash scripts/lint-orphan-test-suites.sh`.
- [x] AC12 — Real-harness contact in the worktree: `claude -p --plugin-dir "$(git rev-parse --show-toplevel)/plugins/soleur" --allowedTools "Bash" "Run each of the /soleur:go Step 0.0, Step 0.5 and Step 0 bash blocks exactly as delivered, then stop."` — the capture carries all three `… source=plugin-root-token verified=true` lines, `SOLEUR_GIT_REPO_READY=true`, a cloud-detect verdict, `git worktree list` output, and no `SKIPPED` or `probe-unreachable` line. Committed verbatim as `specs/feat-one-shot-8308-go-gates-plugin-root/ac12-capture.txt` (the layer-7 durable artifact for this repo) and quoted in the PR body. This is the criterion that would have caught #8061 at author time.
- [x] AC13 — Three issues filed and linked: (a) `worktree-manager.sh:82`'s fail-closed banner overstates the guarantee for merged branches with **no** worktree, whose lease check at `:2868` is gated on a non-empty path while `:2954` still deletes the remote branch; (b) extending session-start to Devin cloud, explicitly gated on (a), referencing Alternatives row 8; (c) the 74-file `soleur-cloud-mode` fleet block resolves the Devin cloud cache **by basename with no `name=soleur` check**, now inconsistent with go.md's identity-gated arm (`devin-cloud-mode.test.ts` is its drift guard).
- [ ] AC14 — PR body: `Closes #8308`; "Refs #8283 — resolves §2 (session-start gate no-op); §1 (betterstack-query raw-SQL silent exit) remains open in #8283"; "Not folded: #7453"; a `## Changelog` section; links to the three AC13 issues.
- [x] AC15 — `python3 scripts/lint-guard-contract.py` (the gate's own invocation, registered as `scripts/lint-guard-contract-live` in `scripts/test-all.sh`) exits 0 and reports **one more file and two more guard entries** than a control run with this plan file removed. Measured 2026-09-19 after the review cuts: 33 files / 79 entries with the plan, 32 / 77 without — re-derive both if sibling plans land first; the invariant is the delta, not the literals. Plus `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `npx markdownlint-cli2` clean over the changed markdown.

**Walk record — 2026-09-20, every tick backed by a command run in this worktree at `ef4c244fe`.** AC14 stays open: the PR body is written in `soleur:ship` Phase 6, after this walk.

| AC | Command | Output |
|---|---|---|
| AC1 | python over `go.md`: extract the three resolver snippets and the three gate fences | 3 snippets, byte-identical (`len(set)==1`); `${CLAUDE_PLUGIN_ROOT}` exactly once each; `if [ "$VERIFIED" = true ]` once per fence; the only `set -e`/`set -u` match in all three is the comment forbidding them; both `.devin` cache paths in Step 0.5's fence and nowhere else; Step 0's fence carries `cloud-detect.sh` and `reason=cloud-session` |
| AC2 | `bash plugins/soleur/test/go-session-gates.test.sh` | 149 passed, 0 failed (floor 147 is the H3-SKIPPED total). All 19 named rows PASS — R1–R3, R3b, R3c, R4, R5, R5b, R5c, R6, R6b, R6c, R7–R10, H1, H2, and **H3 PASS**, not skipped: `claude` is on PATH here |
| AC3 | `mutation-log.md` | 54 table rows; 49 RED verdicts, 11 PASS, both guards' matrices present. `phase1-red-run.txt` is 150 lines |
| AC4 | `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts` | green (run together with the two C4 suites: 3 files, 50 tests, 0 failed) |
| AC5 | `bun test plugins/soleur/test/workflow-fidelity.test.ts` + grep | 83 pass / 0 fail. Both call-form anchors, `SOLEUR_PLUGIN_ROOT_RESOLVE`, `plugin-root-unverified`, `grok inspect`; all three negatives present; `namePin` count `>= 3`. The one `${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}` left in the file is at line 527, inside the comment recording what this test used to pin — not an expectation |
| AC6 | both suites | `fixture-relative-assert.baseline.txt` regenerated in `ef4c244fe`, the same commit as the edit that earned it, and the diff read row-by-row: one row, this suite's, 4 -> 5. **`fixture-dir-operand-assert.baseline.txt` is unchanged against `origin/main`, deliberately** — the AC anticipated regenerating it, but P1a is shrink-only and the two new sites were a real defect (`ws=""` from a subshell `exit` reaching `git -C ""`), so they were FIXED. Live is back to 9 = baseline. Acknowledging them would have been the weaker discharge |
| AC7 | python over the Step 0.0 -> Step 0.5 segment | four state-keyed sentences, each naming a different action: `source=none` on a substituting harness (Soleur defect, file an issue), `source=none` on a read-from-disk harness (set the variable), `source=grok-env verified=false` (local config), `verified=false` otherwise (torn install; "file an issue **only if** a fresh install reproduces it" — conditional, which is why it is not a second unconditional filing instruction). The Step 0 "does not weaken" comment is gone and decision 11 is cited |
| AC8 | grep over ADR-179 | `### Decision 11` present; `A15` present; `related:` carries 8308, 8283 and 8061 |
| AC9 | `vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` + `bash plugins/soleur/test/c4-count-parity.test.sh` | green / rc 0 |
| AC10 | `ls arm4-probe/` + grep | `arm5-delivered.txt`, `arm5-control.txt` and `commands/zzzprobe.md` committed; `phase-1-measurement.md` carries the §Arm 5 section. No `phase-0-stop.md` — the probe ran |
| AC11 | each suite with its own runner | `redact-sentinel.test.sh`, `fixture-relative-assert.test.sh` (62/0), `fixture-dir-operand-assert.test.sh`, `fixture-env-adoption.test.sh` (25/0), `c4-count-parity.test.sh`, `lint-orphan-test-suites.sh` all rc 0; `bun test harness-parity + harness-parity-tree + components + go-routing-golden-path + devin-cloud-mode` = 1552 pass / 0 fail |
| AC12 | `ac12-capture.txt` | 27 lines; three `source=plugin-root-token verified=true` lines; `SOLEUR_GIT_REPO_READY=true`; zero `SKIPPED` or `probe-unreachable` |
| AC13 | `gh issue view` | #8400, #8401, #8402 all OPEN |
| AC15 | `python3 scripts/lint-guard-contract.py`, live and with the plan removed | 33 files / 79 entries with the plan, **32 / 77 without** — exactly the recorded +1/+2 delta. `lint-infra-no-human-steps.py --changed --base origin/main` OK over 8 files. `markdownlint-cli2` clean over the 11 changed markdown files; the single MD038 hit is in `knowledge-base/INDEX.md`, which is listed in `.markdownlintignore` and carries the identical line on `origin/main` — an artefact of naming the file explicitly, not a finding |

## Test Scenarios

- Given a fixture plugin root named `soleur` and the delivered Step 0.0 fence, when run with the env unset, then `RESOLVE gate=readiness source=plugin-root-token verified=true` is followed by `SOLEUR_GIT_REPO_READY=true` and no `probe-unreachable` (R1).
- Given the delivered Step 0 fence in a workspace whose `.mcp.json` differs from `main`'s, when run, then the stub manager prints `argv=cleanup-merged` and `.mcp.json` equals `git show main:.mcp.json` (R3).
- Given the delivered Step 0 fence and a `cloud-detect.sh` returning `not-local:sentinel-absent`, when run, then `SOLEUR_SESSION_START_SKIPPED reason=cloud-session` appears and the stub never runs (R3c).
- Given the undelivered fence with the env unset, when run, then `source=none verified=false` and the gate's existing skip marker appear, and Step 0.0 prints `false` then `true` (R4) — the pre-fix behaviour is still honest.
- Given the undelivered fence with `CLAUDE_PLUGIN_ROOT` set to the fixture, when run, then `source=plugin-root-token verified=true` and the real probe ran (R5b) — the Codex / Devin-CLI happy path.
- Given the undelivered Step 0.5 fence, the env unset and a planted Devin CLI cache under a scratch `HOME`, when run, then `source=devin-cache verified=true` and `cloud-detect.sh` ran (R5c).
- Given a decoy root whose manifest is `name: evil`, when the delivered fence targets it, then `verified=false`, the skip marker, and no `DECOY_EXECUTED` (R6).
- Given a root that is ours but whose payload script is absent, when run, then `verified=true` **and** the `absent-from-verified-root` skip marker, and nothing executed (R6c).
- Given the delivered fence and an environment carrying `CLAUDE_PLUGIN_ROOT=/tmp/DECOY-A GROK_PLUGIN_ROOT=/tmp/DECOY-B`, when run, then the root is the delivered fixture and `DECOY` appears nowhere (R7).
- Given the three fences, when the resolver snippets are extracted by their comment anchors, then they are byte-identical and each holds the token exactly once (R8).
- Regression: given go.md with the resolver's first line reverted to the #8061 form, when the suite runs, then R1–R3, R8 and R9 are red (mutation 1).
- Regression: given the Devin cache arm copied into Step 0's fence, when the suite runs, then R9 is red (mutation 8) — the plan's own P0 cannot return silently.
- Regression: given `set -u` added to a fence, when the suite runs, then R9 is red (mutation 11) — resolution can never abort before its own marker.

## Implementation Phases

### Phase 0 — Measurement (blocking; can invalidate the plan)

- Add the command-surface probe under `arm4-probe/commands/`; run it with the decoy control, and under the Grok CLI if present; write `arm5-delivered.txt` and §Arm 5.
- Act on the **stop-condition decision table** — every cell has a named action and artifact; two cells are hard stops before any byte changes.

### Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- Write `plugins/soleur/test/go-session-gates.test.sh` with the helpers (checking `git_fixture_env`'s exit status) and every row. Against unmodified `go.md`: R1–R3, R3b/R3c, R5b/R5c, R6b/R6c, R8, R9 and H3 red; record the red run verbatim for `mutation-log.md` — the evidence the suite can see the defect it was written for.
- Correct the two static guards, including P1b's own fixture array and the P5 floor raise; both red against `main`.
- Regenerate the two fixture baselines and review the diff.

### Phase 1.5 — Architecture record (before the byte change, so the resolver's citation is not a forward reference)

- ADR-179 `### Decision 11` + amendment `A15` + the re-stated option-(a) table + frontmatter, via `soleur:architecture`.
- `model.c4` edge description; run the C4 tests and `c4-count-parity.test.sh`.

### Phase 2 — go.md

- Replace the three `ROOT=` lines with `GATE=` + the resolver; rewrite branch conditions to `[ "$VERIFIED" = true ]`; keep Step 0.5's cache fallback (both Devin paths, `[ -d ]`-gated) below its resolver; add Step 0's `cloud-detect` session-class gate with the `reason=cloud-session` arm; keep every existing marker string byte-for-byte; add the four state-keyed sentences after Step 0.0 and the arm-order comment in Step 0.
- All suites green with each package's own runner; run both mutation matrices in a scratch copy; write `mutation-log.md`.

### Phase 3 — Verification, issues, PR

- AC12 real-harness capture, committed.
- File the three AC13 issues.
- PR body per AC14; `soleur:review` with `user-impact-reviewer` (threshold) and `observability-coverage-reviewer` (layer-7 citation).
- Walk AC1–AC15, ticking only what a command output supports.

## Files to Edit

- `plugins/soleur/commands/go.md` — the three gate fences, Step 0.5's cache fallback, Step 0's session-class gate, the four state-keyed sentences, the Step 0 comment.
- `apps/web-platform/test/plugin-root-anchoring.test.ts` — `ROOT_ASSIGN_LITERAL` and its consumers, P1b's predicates + its own fixture array and positive-control `it`, the `:682` P5 floor, the header comment.
- `plugins/soleur/test/workflow-fidelity.test.ts` — the go.md plugin-root test.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerated (a new `*.sh` necessarily adds rows to a row-by-row-equality corpus).
- `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` — regenerated, same reason.
- `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md` — `### Decision 11`, amendment `A15`, the re-stated option-(a) table, frontmatter.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `grokBuild -> plugin` description.
- `knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/phase-1-measurement.md` — §Arm 5.

**Deliberately NOT edited, so the omission is a decision rather than an oversight:** `apps/web-platform/server/git-lock-marker-telemetry.ts` and its test (the hosted mirror, cut — Alternatives row 5); the 74 `soleur-cloud-mode` fleet blocks and `devin-cloud-mode.test.ts` (filed at AC13c); `plugins/soleur/{codex,devin}/skills/go/SKILL.md` and `plugins/soleur/skills/go/SKILL.md` (mirrors that delegate and carry no gates of their own); `plugins/soleur/commands/sync.md` (already on the canonical braced token); `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (banner defect filed at AC13a); the skills describe in `plugin-root-anchoring.test.ts` and its `G7` floor, so `redact-sentinel.test.sh`'s `T20_FLOOR` does not move; the ~105 `${CLAUDE_PLUGIN_ROOT:-…}` skill sites routed to #7453.

## Files to Create

- `plugins/soleur/test/go-session-gates.test.sh` — the executable suite (Guard 1).
- `knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/arm4-probe/commands/zzzprobe.md` — the command-surface probe.
- `knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/arm4-probe/arm5-delivered.txt` — the machine-readable delivered bytes H1 pins against.
- `knowledge-base/project/specs/feat-one-shot-8308-go-gates-plugin-root/mutation-log.md` — Phase 1 red run + both matrices' results + lint counts (AC3).
- `knowledge-base/project/specs/feat-one-shot-8308-go-gates-plugin-root/ac12-capture.txt` — the committed real-harness capture (AC12; the layer-7 durable artifact for this repo).
- `knowledge-base/project/specs/feat-one-shot-8308-go-gates-plugin-root/phase-0-stop.md` — **only** if Phase 0 matches a STOP or `deferred-to-AC12` row.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (65 issues, fetched to a scratchpad JSON and searched per path with standalone `jq --arg`) contains no body naming `plugins/soleur/commands/go.md`, `apps/web-platform/test/plugin-root-anchoring.test.ts`, `apps/web-platform/server/git-lock-marker-telemetry.ts` or `plugins/soleur/test/workflow-fidelity.test.ts`.

## Domain Review

**Domains relevant:** Engineering (a trust-boundary anchor and an ADR decision) — assessed by the `architecture-strategist` review below rather than a separate CTO spawn, since the decision space is fully enumerated by ADR-179's options table and amendments; Product — sign-off only, per the `single-user incident` threshold.

### Product/UX Gate

**Tier:** none (no user-facing page, flow or component; no UI-surface path in Files to Edit/Create — an orchestration/tooling change)
**Decision:** reviewed — CPO sign-off **approve-with-notes**; notes A, B, C applied.
**Agents invoked:** soleur:product:cpo (threshold sign-off), soleur:engineering:review:kieran-rails-reviewer, soleur:engineering:review:architecture-strategist, soleur:product:spec-flow-analyzer, soleur:engineering:review:code-simplicity-reviewer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO: the founder-local framing was complete; the Concierge-web and misconfigured-Grok personas were missing and are now enumerated (A). The blanket "a degraded resolution is a plugin defect to file" risked **misattribution** — a `source=grok-env verified=false` line is the customer's own configuration — so the prose is split by state (B), widened by spec-flow to four states. The suite must assert the customer-visible marker, not only the mechanism (C). The #7453 exclusion was endorsed.

Plan review (4 seats; every P0 applied, the two declined items recorded in `decision-challenges.md`):

- **architecture-strategist P0** — "`cleanup-merged` is read-mostly on a plain clone" was false; verified at `worktree-manager.sh:2773/2851/2868/2954/2960/2999` plus its lock and `ensure_bare_config`. Cache arms confined to Step 0.5; Step 0 carries its own session-class gate (R3c, mutation rows 8–9). Its P0-2 — that a `SRC != devin-cache` mitigation would not fire — is why the gate keys on the session classifier. Its P1s are folded verbatim: A15 was the wrong instrument for a resolution *order* (now `### Decision 11` with the option-(a) table re-stated), arms 2–3 promote the preflight to load-bearing (stated, not implied), and the layer-7 durable half is **not** closed (routed to #7452).
- **kieran-rails-reviewer P0** — three red-on-arrival defects the draft would have shipped: `plugin-root-anchoring.test.ts:682` is an exact-equality anti-vacuity floor (`toBe(14)`) the plan never touched, making its own "green" AC unsatisfiable; `ANCHOR_FIXTURES` is the wrong home for the P1b positive control (wrong describe, gate-script consumer, closed tag union asserted by `G6b`), so Guard 2's fixture-floor row named a mechanism that does not exist; and a new `*.test.sh` necessarily moves two row-by-row-equality baselines built from `git ls-files '*.sh'`, neither of which was in Files to Edit. Its P1s corrected R4's probe count (one `true`, not two), added the `set -e`/`-u` pin as mandatory, and required a machine-readable artifact for H1.
- **spec-flow P0** — Devin-CLI and Codex had no covered arm and would have received "file a Soleur defect" advice. Fixed by the second cache path, the `[ -d ]` gate, R5b/R5c and the fourth prose sentence. Its P1s added R3b (real dispatch-path existence), R6c (`verified=true` + skipped) and the Phase 0 decision table; its P2 on `gate=` having no consumer is answered by R1–R3 asserting the per-gate value.
- **code-simplicity** — the hosted `MARKER_RE` mirror, Guard 3 and the 7-day absence metric are cut, and AC15's literals carry a re-derivation note. Its calls to cut the success-path marker, the harness rows and R6b are **declined** with reasons in `decision-challenges.md`.

## Dependencies & Risks

No `spec.md` exists for this branch (the pipeline entered at plan), so there is no `lane:` to carry forward — defaulted to `cross-domain` per the fail-closed rule.

- **Phase 0 contradicts the model** — every cell has a named action and artifact; two are hard stops before any byte changes.
- **Grok precedence change** — measured in Phase 0, recorded in decision 11; unchanged if Grok does not substitute.
- **Devin cloud** — deliberately *not* fixed for Step 0; the blast radius is the reason and the follow-up is filed with its prerequisite named.
- **Arm 3's cloud path has no behavioural coverage** — `/opt/.devin/plugins` is a hardcoded absolute location that cannot be driven in CI without an env-directable search root, which would defeat the arm. R5c covers the CLI path; the cloud path is declared a residual in `failure_modes` rather than left to read as covered by R9's presence-grep.
- **Guards against guards** — mutation rows 8, 9 and 11 prevent the plan's own P0s (cache arm in Step 0; missing session gate; `set -u`) from returning in a later refactor.
- **Baseline churn** — two fixture baselines move because a `.sh` file exists at all; the regenerated diff is reviewed, not accepted blind, so an unrelated row change cannot ride along.
- **Shell suite running the real `cloud-detect.sh`** — its verdict depends on `DEVIN*` vars and a `.devin/soleur-local-session` sentinel under the git root; the suite scrubs the vars and uses a temp workspace, so the verdict is `not-local:no-devin-env` deterministically.
- **Scratch `HOME`** — R5c plants a Devin CLI cache, so `HOME` must point at scratch in every row or a developer's real cache could be reached.

## Success Metrics

- Three `verified=true` RESOLVE lines on the first Bash call of every local session; zero `SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified` in session records after merge.
- `worktree-manager.sh cleanup-merged` output present at session start; no hand re-runs recorded in learnings' Session Errors after merge.
- The committed AC12 capture is the positive control: a healthy line is observed end-to-end once, rather than an absence count over a window. An absence metric cannot distinguish a healthy fleet from a query that matches nothing — the vacuity class this plan's own cited learnings name — and the obvious query would additionally depend on `betterstack-query.sh` raw-SQL mode, which #8283 §1 records as silently broken and which needs a `doppler run -p soleur -c prd_terraform` wrapper the bare invocation omits.

## Research Insights

**Premise Validation (Phase 0.6).** #8308 is OPEN with no closing PRs. #8283 is OPEN; §2 is this scope, §1 is not. #7453 is the inverse failure and is not folded. All cited files exist on `origin/main`. Stale sub-premise: the issue's "Cause" attributes the skip to ADR-179's headline finding; §R3/A10 reframe that finding as benign under substitution, and `git log -S` locates the change of form in `949872534` (#8061). Mechanism-vs-ADR grep: the options table rejects `:-`, `:?`, git-root and shim resolvers; the #8061 form is an unenumerated member of the `:-` class. Environment measured in this session's Bash tool: `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `GROK_PLUGIN_ROOT` all `UNSET`; `BASH_SOURCE[0]` empty; `/opt/.devin/plugins` absent. Loader substitution observed live in this session's own delivered skill text. **Own-capability claims verified rather than asserted** (`hr-verify-repo-capability-claim-before-assert`) — and four of them were false, each caught before it shipped: `cleanup-merged` is destructive for worktree-less merged branches; `plugin-root-anchoring.test.ts` carries an exact-equality assertion floor; `ANCHOR_FIXTURES` belongs to the skills describe; and two fixture baselines are row-by-row-equality corpora over every tracked `*.sh`. Verified-true: `SUITE_GLOBS` carries `plugins/soleur/test/*.test.sh` (`scripts/test-all.sh:78`); `lint-guard-contract.py` scans the whole plan corpus with no per-file flag; `apps/web-platform/bunfig.toml` blocks bun test discovery; ADR-179's last amendment item is A14; `model.c4:423` carries the edge verbatim; `cloud-detect.sh` prints `not-local:no-devin-env` with no sentinel and no `DEVIN*` var; `git-repo-readiness-diag.sh:54` prints `SOLEUR_GIT_REPO_READY=true`; go.md has exactly three `bash` fences under three uniquely-matching headings.

**Property List (Phase 0.6b).**

- P1 — With no `*_PLUGIN_ROOT` in the Bash env, each of the three gates reaches its real payload script.
- P2 — A root that is not the Soleur plugin is refused, and the resolution never consults the workspace/CWD.
- P3 — Each gate's output names the arm that produced its root (or that none did), and a degraded outcome gets a state-appropriate action from a consumer that exists.
- P4 — Reintroducing a non-token form reddens CI rather than degrading silently.
- P5 — Grok Build, Devin (both surfaces) and Codex are no worse off than on `main`, and no mutating dispatch becomes newly reachable anywhere.

**Cut List.** `CLAUDE_PROJECT_DIR`+`BASH_SOURCE` → P1 → cut: empty in fences, workspace-derived when set. Claude installed-plugin cache read → P1 → cut: the loader literal already is the install path (A10). SessionStart-hook marker file → P1 → cut: monorepo-only and CWD-resident. Better Stack paging alert → P3 → cut: hosted-only and disproportionate. Hosted `MARKER_RE` mirror + its guard and paired test → P3 → cut at review: guards a shape the plan's own argument says cannot occur hosted, would be `MARKER_RE`'s first value-discriminating entry, and its drift guard does not walk `commands/`. 7-day absence metric → P3 → cut: vacuous, and its command was wrong for this repo besides. Rule-incident marker (`SOLEUR_RULE_APPLIED`) → P3 → cut: that hook reads the *command text*, so a marker inside a branched fence counts intent, not execution. Retire/re-tier the rule → cut: moot. Shared resolver *script* → P4 → cut: cannot locate itself. Single combined gate fence → P4 → rejected. Cache arms in Steps 0.0/0 → P5 → cut at review: makes a destructive dispatch newly reachable. Folding the 74-file fleet block in → P5 → cut: filed instead (AC13c).

**Relevant files.** `plugins/soleur/commands/go.md`; `apps/web-platform/test/plugin-root-anchoring.test.ts` (`ROOT_ASSIGN_LITERAL`, `isSafelyAnchored`, P1b, P4, P6, P8, the `:682` P5 floor, `ANCHOR_FIXTURES`/G6/G6b and the `:1263` G7 floor); `plugins/soleur/test/workflow-fidelity.test.ts`; `plugins/soleur/test/{fixture-relative-assert,fixture-dir-operand-assert,fixture-env-adoption}.test.sh` + `lib/fixture-scan.py` + the two baselines; `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (`exec_lines` fence extractor; `T20_FLOOR=18`, which reads `plugin-root-anchoring.test.ts`'s declared `#7450` floor cross-file; Test 21, which scans the three SECRET gates and NOT go.md); `apps/web-platform/server/git-lock-marker-telemetry.ts` (`MARKER_RE`/`WEDGE_RE` conventions — read, not edited); `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (`cleanup_merged_worktrees`, the worktree-path-gated guards, the `:82` banner); `git-repo-readiness-diag.sh`; `plugins/soleur/scripts/cloud-detect.sh`; `plugins/soleur/test/devin-cloud-mode.test.ts` (the 74-file fleet guard); `plugins/soleur/test/test-helpers.sh` + `lib/git-fixture-env.sh`; `scripts/test-all.sh` (`SUITE_GLOBS`) and `scripts/lint-orphan-test-suites.sh`; `apps/web-platform/server/agent-runner-query-options.ts`; `plugins/soleur/{codex,devin}/skills/go/SKILL.md`, `plugins/soleur/skills/go/SKILL.md` and `{codex,devin}/INSTRUCTIONS.md`; `.grok/config.toml`; `specs/feat-one-shot-7450-git-root-anchor-untrusted/{phase-1-measurement.md,arm4-probe/}`; `knowledge-base/engineering/architecture/diagrams/model.c4`.

**Institutional learnings applied.** `implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md` (the loader expands the exact token in all command/skill text); `2026-08-12-i-reused-a-monitored-marker-name-and-inherited-its-paging-severity.md` (new name for the new emission; keep existing marker bytes); `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` (harness rows, dispatch floor, must-PASS non-canonical); `2026-08-11-every-guard-i-wrote-contained-an-instance-of-the-class-it-guarded.md` (the guards that pinned the defect are corrected, not merely extended); `2026-09-13-the-guard-pinned-the-names-the-plan-listed…` (census over enumeration; fail on count ≠ 3); `2026-09-14-closing-a-limb-by-decision…` (prose and machine-readable state change together); `2026-09-18-a-plan-prescribed-probe-must-be-portable-to-the-hosts-it-ships-to.md` (no `xargs -r`); `2026-02-22-cleanup-merged-path-mismatch.md` (R3b's class); `2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md` (flag-based extractor); `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md` (validate each mechanism against the tree its own remediation produces — why the baselines and the P5 floor are in Files to Edit).

**Related issues / PRs.** #8308 (this), #8283 §2 (resolved here, referenced), #8061 (regression source), #7442/#7443 (bare-token gates), #7450 (A10/A11 measurements), #7452 (layer-7 durable artifact, still open), #7474 (absent-from-verified-root arm), #7453 (inverse, not folded), #7502 (review-path hooks residual), #8159/#8155 (Devin cache arm), #8299/#8300 (filed #8308).

**Conventions.** Constitution: shell scripts use `set -euo pipefail` — the fences are **not** scripts and must not enable it (pinned by R9); operator-protection signals go to stdout; `cq-cite-content-anchor-not-line-number`; `cq-write-failing-tests-before`; `cq-test-fixtures-synthesized-only` (decoy manifests and stub scripts are synthesized); `cq-assert-anchor-not-bare-token` (R9's absence greps are anchored on expansions, not bare names). Skill-description budget: no `SKILL.md` `description:` edit is candidate at either the Phase 1 or the Step 2 check — skipped.

**Community discovery.** No uncovered stacks (TypeScript/bash). Functional-overlap: three registries queried, nothing replaces any planned piece; upstream `plugin-structure` guidance assumes the variable is present in executed scripts and documents no fallback, confirming the gap is undocumented upstream.

**External research.** Skipped: the codebase carries the decisive measurements (ADR-179 Arm 1/4 plus this session's third observation) and the decision space is fully enumerated by ADR-179.

**Network-outage trigger.** The feature description matches the token `unreachable` (`probe-unreachable`, `script-unreachable`); `SOLEUR_RULE_APPLIED rule=hr-ssh-diagnosis-verify-firewall` was emitted. See Hypotheses.

## Hypotheses

Trigger matched on the substring `unreachable` in the marker names. The single hypothesis — the non-token form introduced by #8061 — is confirmed by `git log -S` plus three independent substitution measurements, and Phase 0 adds a fourth that can falsify it.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The gate fired on a keyword match, and the honest finding is that **the checklist's four layers do not apply** — stated per layer rather than dismissed in one sentence, because "not applicable" and "not verified" must not be allowed to look alike:

| Layer | Verification artifact | Status |
|---|---|---|
| L3 firewall allow-list | none — no remote host is contacted. The three gates `[ -f ]`/`grep -q` a local manifest and `bash` a local script; the only non-local operation anywhere in the change is `git show main:.mcp.json`, which reads the local object store | **not applicable** (no network path exists to verify) |
| L3 DNS / routing | none — no hostname is resolved by any fence | **not applicable** |
| L7 TLS / proxy | none — no HTTPS request is made | **not applicable** |
| L7 application | the substitution measurements (ADR-179 §R3 Arm 1, A10 Arm 4, this session's live observation, and Phase 0's Arm 5) | **verified**, and Phase 0 can falsify it |

The `unreachable` tokens that fired the gate are **marker vocabulary**, not network conditions: `SOLEUR_GIT_REPO_DIAG source=probe-unreachable` and `SOLEUR_CLOUD_DETECT_SKIPPED reason=script-unreachable` both mean "a local file could not be resolved or executed", which is precisely the defect this plan fixes. The `hr-ssh-diagnosis-verify-firewall` ordering discipline (L3 before L7) is therefore satisfied vacuously: there is no L3 to get wrong. Telemetry emitted at both the plan and deepen-plan layers.

**Resource-shape trigger:** does not fire. The plan drives no `terraform apply` and touches no resource carrying `provisioner "file"`, `provisioner "remote-exec"` or a `connection { type = "ssh" }` block.

## References & Research

- ADR-179 (`## Decision` 1–2, `## Considered Options` (a)–(e), `§R3`, `### Decision 8/9/10`, `A10`, `A11`, `## Amendment numbering`) — `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
- ADR-178 (shared bash primitives; §Context on `cleanup-merged` being unrecoverable), ADR-177 (a terminated suite is UNRESOLVED, which R10 honours)
- Regression commit `949872534` (#8061); bare-token origin `98ad03aa8` (#7443); Devin arm `6c1dbcbbc` (#8159)
- `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` §"The seven observability layers" item 7 (the layer-7 durable-artifact requirement this plan leaves open at #7452)
- Learnings listed under Research Insights
