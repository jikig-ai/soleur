---
name: go
description: Unified entry point that classifies intent and routes to the right workflow skill
argument-hint: "[what you want to do]"
---

# Soleur Go

Unified entry point for all Soleur workflows. Classify the user's intent and route to the correct skill.

## User Input

<user_input> #$ARGUMENTS </user_input>

**If the user input above is empty**, ask: "What would you like to do? Describe what you need and I'll route you to the right workflow."

Do not proceed until there is input from the user.

## Step 0.0: Workspace Readiness Gate

Before the session-start preamble and before any routing, confirm a usable git repository exists. Run the readiness probe (it decides readiness AND, on failure, emits a `SOLEUR_GIT_REPO_DIAG` forensic line that the server-side telemetry hook mirrors to Better Stack — so a not-ready workspace is self-diagnosable without a manual probe):

```bash
GATE=readiness
# --- soleur plugin-root resolver (ADR-179 decision 1 + decision 11 as amended by A16;
# #8308, #8401). The three copies in this file are byte-identical between these anchors;
# go-session-gates.test.sh pins that. Arm 1 is the loader-substituted token — on a
# substituting harness a literal fixed before bash runs, so no environment value can direct
# it (A10); on a read-from-disk harness (the Codex/Devin go mirrors) an ordinary variable
# those harnesses' INSTRUCTIONS tell the agent to set. Never a CWD default (#7442). POSIX
# only: no `xargs -r`, no `readlink -f`, no `sed -i`. Never enable `set -e`, `set -u` or
# `set -o pipefail` in these fences — line 1 is deliberately unguarded so it stays the exact
# token, and `-u` would abort before any marker is printed, which is the silent-skip class
# being fixed. ---
ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token
if [ -z "$ROOT" ] && [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  ROOT="$GROK_PLUGIN_ROOT"; SRC=grok-env
fi
# Arm 3 — the two managed Devin plugin caches, in ALL THREE gates since #8401. They were
# confined to Step 0.5 because Step 0 dispatches `cleanup-merged`; ADR-179 A16 records why
# that confinement is lifted (the capability gate below replaces it) and why the confinement
# was never about RESOLUTION in the first place. Identity-selected, never by basename;
# `[ -d ]`-gated so a non-Devin box searches nothing. `-exec … +`, not `xargs -r`: BSD/macOS
# xargs has no -r. `SOLEUR_DEVIN_CACHE_OPT` exists so a test can contain the ABSOLUTE arm —
# `run_gate` already contains the `$HOME` arm by overriding HOME, and a MUST-PASS suite whose
# verdict is a property of the host is not a suite. It is env-directed like `GROK_PLUGIN_ROOT`
# and subject to the same identity preflight, so it adds no trust class.
# Verify what arms 1-2 produced BEFORE deciding whether arm 3 is needed. A root that arrives
# but carries no Soleur manifest is not a usable root, and it must fall through exactly as an
# absent one does.
VERIFIED=false
if [ -n "$ROOT" ] \
   && [ -f "${ROOT}/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${ROOT}/.claude-plugin/plugin.json"; then
  VERIFIED=true
fi
# Arm 3 fires on `VERIFIED != true`, NOT on `-z "$ROOT"`. An earlier revision of this change
# used the empty test and thereby NARROWED Step 0.5: on `main` a set-but-unverified root still
# fell through to the cache, and under the empty test it stopped doing so — so a Devin host
# with a torn `CLAUDE_PLUGIN_ROOT` silently stopped engaging Cloud Mode, which is the fail-open
# class this work exists to close. Measured on both fences before and after.
PRIOR_SRC="$SRC"
PRIOR_ROOT="$ROOT"
if [ "$VERIFIED" != true ]; then
  ROOT=""; SRC=none
  for d in "$HOME/.local/share/devin/cli/plugins/cache" "${SOLEUR_DEVIN_CACHE_OPT:-/opt/.devin/plugins}"; do
    [ -d "$d" ] || continue
    # A cache directory EXISTED and was searched. That is a different state from "no cache at
    # all" and carries a different remedy, so it gets its own value instead of collapsing into
    # `none` (AP-021: do not name a cause this gate did not measure).
    [ "$SRC" = none ] && SRC=devin-cache-nomatch
    MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' \
      -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"
    if [ -n "$MANIFEST" ]; then
      ROOT="${MANIFEST%/.claude-plugin/plugin.json}"; SRC=devin-cache; VERIFIED=true
      break
    fi
  done
  # Nothing resolved anywhere. If arms 1-2 DID name a root, report that arm rather than the
  # cache's miss: "your token points at something that is not Soleur" is the actionable fact,
  # and reporting `none` there would name a cause this gate did not measure.
  if [ "$VERIFIED" != true ] && [ -n "$PRIOR_ROOT" ]; then
    SRC="$PRIOR_SRC"
  fi
fi
# EXACTLY ONE RESOLVE line per gate, emitted after verification. The cache arm used to print
# its own, so a cache hit emitted two and nothing pinned the count — `grep -F` is a presence
# check and cannot see a duplicate.
echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=${GATE} source=${SRC} verified=${VERIFIED}"
# --- end resolver ---
if [ "$VERIFIED" = true ]; then
  # Identity is not freshness (#7474): a root that IS ours can still not carry
  # this probe, and the bare invocation would then die with an unattributed
  # interpreter error. The fallback below is already the right behaviour for
  # that case — only the reason differs, so it is reported separately.
  if [ -f "${ROOT}/skills/git-worktree/scripts/git-repo-readiness-diag.sh" ]; then
    bash "${ROOT}/skills/git-worktree/scripts/git-repo-readiness-diag.sh" 2>&1
  else
    echo "SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=absent-from-verified-root"
    git rev-parse --is-bare-repository 2>/dev/null || true
    git rev-parse --is-inside-work-tree 2>/dev/null || true
  fi
else
  # Distinct from a not-ready workspace: the PROBE could not run. Emitting the
  # same marker family keeps this visible to the telemetry hook instead of
  # silently degrading into two git calls that print `true` (#7442). The
  # RESOLVE line above says WHICH arm produced nothing, so this branch is now
  # attributable rather than merely honest.
  echo "SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=plugin-root-unverified"
  git rev-parse --is-bare-repository 2>/dev/null || true
  git rev-parse --is-inside-work-tree 2>/dev/null || true
fi
```

**Read the `SOLEUR_PLUGIN_ROOT_RESOLVE` line before anything else — it says which arm produced the root, and each state below needs a different action. One blanket "file a defect" would misattribute a customer's own configuration to Soleur.** (The list is deliberately not headed by a count: it grew from four states to eight across #7442, #8308 and #8401, and a hard-coded number is the part that goes stale without anything noticing.)

- `source=none` **on Claude Code or Concierge** — no arm produced a root on a harness where the loader was expected to substitute one. That is a **Soleur plugin defect**. Per `wg-every-session-error-must-produce-either`, file an issue on `jikig-ai/soleur` quoting the three `RESOLVE` lines, then continue on the fallback.
- `source=none` **on a read-from-disk harness (Codex, Devin CLI, Grok Build)** — nothing substituted, nothing set the variable, **and no Devin plugin cache directory existed to search**. Since #8401 all three gates also try the two managed Devin caches, so on a Devin CLI host this value now means the caches are genuinely absent rather than merely unsearched. **Set `CLAUDE_PLUGIN_ROOT` — or, on Grok Build, `GROK_PLUGIN_ROOT`, the one variable arm 2 consults — per your harness's `INSTRUCTIONS.md` §"Paths and entry points"**, and re-run. Not a Soleur defect.
- `source=devin-cache verified=true` — **nothing to do; this is the healthy Devin path.** Arms 1–2 produced nothing and a managed Devin plugin cache supplied the root, so the bytes about to run are the ones in that cache, not in any checkout on screen. Worth knowing for exactly one reason: when a later line refuses with `reason=reaper-capability-unverified source=devin-cache`, the stale artifact is that cached copy and `git pull` in your repository will not move it.
- `source=devin-cache-nomatch` — a Devin plugin cache directory EXISTS and was searched, but holds no `.claude-plugin/plugin.json` naming `soleur`. Distinct from `none`, and with a different remedy: the cache is present but does not carry Soleur. **Reinstall or update the plugin in that cache** (`devin plugins install ./plugins/soleur`, or `devin plugins update soleur`), then re-run. A **local configuration fact**, not a Soleur defect.
- `SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified source=<arm>` — the plugin root resolved and verified, but its `worktree-manager.sh` predates the branch-keyed reap guards (#8400), so the session-start gate refused to dispatch `cleanup-merged` from it rather than run a reaper whose per-branch safety guards may not cover a worktree-less merged branch. **A stale install, not a defect.** On Claude Code it takes TWO commands and the second one alone is a no-op: `claude plugin marketplace update soleur-marketplace` advances the marketplace checkout, then `claude plugin update soleur@soleur-marketplace` updates the plugin you actually run — skipping the first leaves you on the old bytes while the update reports success (this repo's own getting-started page says the same). On Devin, `devin plugins update soleur`. Restart the session either way. The `source=` field is carried for symmetry with the other `SKIPPED` reasons, but this refusal only ever reads `source=devin-cache`: the capability gate is scoped to that arm on purpose (ADR-179 A16 — the arm-agnostic form was measured to stop reaping on every long-lived worktree and every marketplace install between releases). A stale `plugin-root-token` or `grok-env` install is therefore NOT refused here; it dispatches its own reaper. The Claude Code remedy above is for that case, which you will recognise by an old reaper's output rather than by this marker. For `source=devin-cache` the stale artifact is in the Devin plugin cache rather than in any checkout you can see. Session-start maintenance is skipped until then, deliberately; everything else in the gate (the worktree listing and the `.mcp.json` restore) still runs.
- `source=grok-env verified=false` — `GROK_PLUGIN_ROOT` is set but does not point at the Soleur plugin. A **local configuration fact**: check what it targets (`grok plugin list`). Not a Soleur defect.
- `SOLEUR_SESSION_START_SKIPPED reason=cloud-session verdict=<v>` **on a machine you know is local** — `cloud-detect.sh` classified the session as a Devin one. The usual cause is a stray `DEVIN_DIR` or `DEVIN_DISABLE_HISTEXPAND` exported by your shell profile, which makes the box Devin-marked; unset it and re-run. Session-start maintenance is skipped until then, deliberately — the classifier fails closed by contract.
- `verified=false` with any other `source` — a root arrived but carries no Soleur manifest: a **torn or stale install**. Reinstall or update the plugin; file an issue only if a fresh install reproduces it.

**One caveat that applies to every `devin-cache*` value above.** The `/opt` arm is read through `${SOLEUR_DEVIN_CACHE_OPT:-/opt/.devin/plugins}`, so if that variable is exported the three bullets above are reporting on whatever it points at, not on `/opt/.devin/plugins`. It exists because `/opt/.devin/plugins` is absolute, and a MUST-PASS suite whose verdict depends on whether the host happens to carry a populated one is not a suite — `go-session-gates.test.sh` pins it to a scratch path (ADR-179 A16). It is env-directed exactly as `GROK_PLUGIN_ROOT` is and runs through the same identity preflight, so it adds no trust class; but if a `devin-cache` verdict surprises you, `echo "${SOLEUR_DEVIN_CACHE_OPT:-unset}"` before reading further.

The `else` branch runs the bare inline probes when the plugin payload cannot be verified (e.g. a repo-less workspace whose plugin symlink was not scaffolded). Readiness = the output contains `SOLEUR_GIT_REPO_READY=true` (script path) OR a bare `true` (fallback path).

**The fallback is not silent.** Before #7442 this was a bare `||` after an unquoted, unverified path: if the probe could not resolve, the fallback printed `true` and the gate read PASS while `SOLEUR_GIT_REPO_DIAG` — the forensic line the server-side hook mirrors to Better Stack — was never emitted. "Probe said not-ready" and "probe never ran" produced identical output. The `source=probe-unreachable` marker keeps them distinguishable, which matters because `soleur:go` is the first command of every session.

If the output shows `SOLEUR_GIT_REPO_READY=false` (or, on the fallback, **neither** probe printed `true`), the workspace has no usable git checkout. In the Soleur web (Concierge) environment this happens when a connected repository is still cloning in the background, or its setup failed (the CWD is then a repo-less `/workspaces/<id>`), OR the `.git` is present but git rejects it (a corrupt/masked config — the emitted `SOLEUR_GIT_REPO_DIAG config_parse_rc`/`err=` fields distinguish these). **Every** route (`go`/`brainstorm`/`plan`/`one-shot`/`fix`/`drain`) will fail: worktree creation, knowledge-base artifact writes, and the session-start preamble all need a real repo. Do NOT run the preamble, do NOT route, do NOT improvise filesystem exploration. STOP and reply with this honest, no-wait message:

> Your workspace isn't ready yet — its repository is still being set up, or its setup didn't finish. Please try again in a moment.

**Claude / Concierge:** if this keeps happening and your project lives in a **team workspace**, switch to that workspace and try again; if this is your own workspace, check that a repository is connected in **Settings → Repository**.

**Grok Build:** that Concierge settings path does not apply. Confirm `GROK_PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT` points at the Soleur plugin (plugin.json name `soleur`) and that `grok inspect` lists it. Do not invent a Settings → Repository screen.

This gate is deterministic and fires on the first action, so a not-ready workspace produces a clear message instead of a long flail. (The runtime's `worktree_enter_failed` detector only catches a narrow repeated-`cd … && pwd` loop — #5313 — not the general "no repo, agent tries many different commands" case the Concierge no-repo session hit.)

## Step 0.5: Cloud Mode detection

Before the mutating preamble below (worktree cleanup, `.mcp.json` restore), classify the session — a routed skill's marker block cannot protect work that runs before it loads:

```bash
GATE=cloud-detect
# --- soleur plugin-root resolver (ADR-179 decision 1 + decision 11 as amended by A16;
# #8308, #8401). The three copies in this file are byte-identical between these anchors;
# go-session-gates.test.sh pins that. Arm 1 is the loader-substituted token — on a
# substituting harness a literal fixed before bash runs, so no environment value can direct
# it (A10); on a read-from-disk harness (the Codex/Devin go mirrors) an ordinary variable
# those harnesses' INSTRUCTIONS tell the agent to set. Never a CWD default (#7442). POSIX
# only: no `xargs -r`, no `readlink -f`, no `sed -i`. Never enable `set -e`, `set -u` or
# `set -o pipefail` in these fences — line 1 is deliberately unguarded so it stays the exact
# token, and `-u` would abort before any marker is printed, which is the silent-skip class
# being fixed. ---
ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token
if [ -z "$ROOT" ] && [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  ROOT="$GROK_PLUGIN_ROOT"; SRC=grok-env
fi
# Arm 3 — the two managed Devin plugin caches, in ALL THREE gates since #8401. They were
# confined to Step 0.5 because Step 0 dispatches `cleanup-merged`; ADR-179 A16 records why
# that confinement is lifted (the capability gate below replaces it) and why the confinement
# was never about RESOLUTION in the first place. Identity-selected, never by basename;
# `[ -d ]`-gated so a non-Devin box searches nothing. `-exec … +`, not `xargs -r`: BSD/macOS
# xargs has no -r. `SOLEUR_DEVIN_CACHE_OPT` exists so a test can contain the ABSOLUTE arm —
# `run_gate` already contains the `$HOME` arm by overriding HOME, and a MUST-PASS suite whose
# verdict is a property of the host is not a suite. It is env-directed like `GROK_PLUGIN_ROOT`
# and subject to the same identity preflight, so it adds no trust class.
# Verify what arms 1-2 produced BEFORE deciding whether arm 3 is needed. A root that arrives
# but carries no Soleur manifest is not a usable root, and it must fall through exactly as an
# absent one does.
VERIFIED=false
if [ -n "$ROOT" ] \
   && [ -f "${ROOT}/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${ROOT}/.claude-plugin/plugin.json"; then
  VERIFIED=true
fi
# Arm 3 fires on `VERIFIED != true`, NOT on `-z "$ROOT"`. An earlier revision of this change
# used the empty test and thereby NARROWED Step 0.5: on `main` a set-but-unverified root still
# fell through to the cache, and under the empty test it stopped doing so — so a Devin host
# with a torn `CLAUDE_PLUGIN_ROOT` silently stopped engaging Cloud Mode, which is the fail-open
# class this work exists to close. Measured on both fences before and after.
PRIOR_SRC="$SRC"
PRIOR_ROOT="$ROOT"
if [ "$VERIFIED" != true ]; then
  ROOT=""; SRC=none
  for d in "$HOME/.local/share/devin/cli/plugins/cache" "${SOLEUR_DEVIN_CACHE_OPT:-/opt/.devin/plugins}"; do
    [ -d "$d" ] || continue
    # A cache directory EXISTED and was searched. That is a different state from "no cache at
    # all" and carries a different remedy, so it gets its own value instead of collapsing into
    # `none` (AP-021: do not name a cause this gate did not measure).
    [ "$SRC" = none ] && SRC=devin-cache-nomatch
    MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' \
      -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"
    if [ -n "$MANIFEST" ]; then
      ROOT="${MANIFEST%/.claude-plugin/plugin.json}"; SRC=devin-cache; VERIFIED=true
      break
    fi
  done
  # Nothing resolved anywhere. If arms 1-2 DID name a root, report that arm rather than the
  # cache's miss: "your token points at something that is not Soleur" is the actionable fact,
  # and reporting `none` there would name a cause this gate did not measure.
  if [ "$VERIFIED" != true ] && [ -n "$PRIOR_ROOT" ]; then
    SRC="$PRIOR_SRC"
  fi
fi
# EXACTLY ONE RESOLVE line per gate, emitted after verification. The cache arm used to print
# its own, so a cache hit emitted two and nothing pinned the count — `grep -F` is a presence
# check and cannot see a duplicate.
echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=${GATE} source=${SRC} verified=${VERIFIED}"
# --- end resolver ---
if [ "$VERIFIED" = true ]; then
  # NESTED, not `[ "$VERIFIED" = true ] && [ -f … ]`: #7474 requires the presence check and
  # the invocation to share a subprocess, and plugin-root-anchoring.test.ts P6 anchors on a
  # `[ -f` at statement start. The conjunction form reads as guarded and is not recognised.
  if [ -f "${ROOT}/scripts/cloud-detect.sh" ]; then
    bash "${ROOT}/scripts/cloud-detect.sh" --banner
  else
    echo "SOLEUR_CLOUD_DETECT_SKIPPED reason=script-unreachable"
  fi
else
  # NOT `script-unreachable` — nothing looked for the script, so that would name a cause this
  # gate did not measure (AP-021), and it is the #7442 class this change exists to remove. Steps
  # 0.0 and 0 already discriminate these two states; this one used to collapse them.
  echo "SOLEUR_CLOUD_DETECT_SKIPPED reason=plugin-root-unverified"
fi
```

`local` or `not-local:no-devin-env` → proceed. Any other `not-local:<reason>` → apply the cloud contract in `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode (sequential fan-out with `Reviewed-Coverage: sequential-fallback` disclosure, `message_user` ack before secrets/prod, `precommit-guard.sh` before any `git commit`).

## Step 0: Session-Start Preamble

Before any other work, run the session-start gates from AGENTS.md (`wg-at-session-start-run-bash-plugins-soleur` + `wg-at-session-start-after-cleanup-merged`):

```bash
GATE=session-start
# --- soleur plugin-root resolver (ADR-179 decision 1 + decision 11 as amended by A16;
# #8308, #8401). The three copies in this file are byte-identical between these anchors;
# go-session-gates.test.sh pins that. Arm 1 is the loader-substituted token — on a
# substituting harness a literal fixed before bash runs, so no environment value can direct
# it (A10); on a read-from-disk harness (the Codex/Devin go mirrors) an ordinary variable
# those harnesses' INSTRUCTIONS tell the agent to set. Never a CWD default (#7442). POSIX
# only: no `xargs -r`, no `readlink -f`, no `sed -i`. Never enable `set -e`, `set -u` or
# `set -o pipefail` in these fences — line 1 is deliberately unguarded so it stays the exact
# token, and `-u` would abort before any marker is printed, which is the silent-skip class
# being fixed. ---
ROOT="${CLAUDE_PLUGIN_ROOT}"; SRC=plugin-root-token
if [ -z "$ROOT" ] && [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  ROOT="$GROK_PLUGIN_ROOT"; SRC=grok-env
fi
# Arm 3 — the two managed Devin plugin caches, in ALL THREE gates since #8401. They were
# confined to Step 0.5 because Step 0 dispatches `cleanup-merged`; ADR-179 A16 records why
# that confinement is lifted (the capability gate below replaces it) and why the confinement
# was never about RESOLUTION in the first place. Identity-selected, never by basename;
# `[ -d ]`-gated so a non-Devin box searches nothing. `-exec … +`, not `xargs -r`: BSD/macOS
# xargs has no -r. `SOLEUR_DEVIN_CACHE_OPT` exists so a test can contain the ABSOLUTE arm —
# `run_gate` already contains the `$HOME` arm by overriding HOME, and a MUST-PASS suite whose
# verdict is a property of the host is not a suite. It is env-directed like `GROK_PLUGIN_ROOT`
# and subject to the same identity preflight, so it adds no trust class.
# Verify what arms 1-2 produced BEFORE deciding whether arm 3 is needed. A root that arrives
# but carries no Soleur manifest is not a usable root, and it must fall through exactly as an
# absent one does.
VERIFIED=false
if [ -n "$ROOT" ] \
   && [ -f "${ROOT}/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${ROOT}/.claude-plugin/plugin.json"; then
  VERIFIED=true
fi
# Arm 3 fires on `VERIFIED != true`, NOT on `-z "$ROOT"`. An earlier revision of this change
# used the empty test and thereby NARROWED Step 0.5: on `main` a set-but-unverified root still
# fell through to the cache, and under the empty test it stopped doing so — so a Devin host
# with a torn `CLAUDE_PLUGIN_ROOT` silently stopped engaging Cloud Mode, which is the fail-open
# class this work exists to close. Measured on both fences before and after.
PRIOR_SRC="$SRC"
PRIOR_ROOT="$ROOT"
if [ "$VERIFIED" != true ]; then
  ROOT=""; SRC=none
  for d in "$HOME/.local/share/devin/cli/plugins/cache" "${SOLEUR_DEVIN_CACHE_OPT:-/opt/.devin/plugins}"; do
    [ -d "$d" ] || continue
    # A cache directory EXISTED and was searched. That is a different state from "no cache at
    # all" and carries a different remedy, so it gets its own value instead of collapsing into
    # `none` (AP-021: do not name a cause this gate did not measure).
    [ "$SRC" = none ] && SRC=devin-cache-nomatch
    MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' \
      -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"
    if [ -n "$MANIFEST" ]; then
      ROOT="${MANIFEST%/.claude-plugin/plugin.json}"; SRC=devin-cache; VERIFIED=true
      break
    fi
  done
  # Nothing resolved anywhere. If arms 1-2 DID name a root, report that arm rather than the
  # cache's miss: "your token points at something that is not Soleur" is the actionable fact,
  # and reporting `none` there would name a cause this gate did not measure.
  if [ "$VERIFIED" != true ] && [ -n "$PRIOR_ROOT" ]; then
    SRC="$PRIOR_SRC"
  fi
fi
# EXACTLY ONE RESOLVE line per gate, emitted after verification. The cache arm used to print
# its own, so a cache hit emitted two and nothing pinned the count — `grep -F` is a presence
# check and cannot see a duplicate.
echo "SOLEUR_PLUGIN_ROOT_RESOLVE gate=${GATE} source=${SRC} verified=${VERIFIED}"
# --- end resolver ---
# Session-class gate, in THIS fence rather than inherited from Step 0.5: bash carries no
# state between fences (ADR-179 §"Why the axes stay separate" item 3), so 0.5's verdict is
# unavailable here. Keyed on the CLASSIFIER, not on SRC — a Devin agent following its own
# INSTRUCTIONS resolves as plugin-root-token, so an `SRC != devin-cache` test would never
# fire. This is the only gate below that mutates anything.
SESSION_OK=false
SESSION_PROBE=absent
SESSION_VERDICT=none
# Reap-capability gate (#8401; ADR-179 A16 amends decision 11 to permit this).
#
# NARROWED TO THE devin-cache ARM ON PURPOSE. An arm-agnostic form has a measured fleet-wide
# blast radius: every root whose `worktree-manager.sh` predates the branch-keyed guards —
# every long-lived worktree on a pre-merge branch, and every marketplace install between
# releases — would emit `reaper-capability-unverified` and stop reaping. The ground ADR-179
# actually states is about the CACHE arm: `head -1` may select a cached copy of unbounded
# age, and fixing the repository's script does not fix that artifact on disk.
#
# It ATTESTS a contract; it does not authenticate one. A planted root can carry this literal
# as trivially as it can carry `{"name":"soleur"}` — ADR-179 A11 one level down.
#
# Evaluated BEFORE the classifier, not just before the reaper: the gate covers every artifact
# in the dispatch DECISION CHAIN, not only the artifact dispatched. A cache root whose reaper
# lacks the capability is not trusted to classify the session either, which is what makes the
# blast-radius argument non-circular — one token, both consumers.
#
# PATH-PINNED: the `grep -q` and the `bash` below operate on the same `${ROOT}`-derived path,
# resolved once above, with NO second `find` between them. A check that re-resolves is
# check-A/execute-B across two independent `head -1` calls — the defect one level down from
# the one this gate closes, and no behavioural row can see it.
REAP_CAP=not-applicable
# Whether the non-destructive half of this gate runs. Set by the two arms that reach it, and
# read AFTER the dispatch `fi` — so a refusal on the reaper cannot silently take the
# `.mcp.json` restore with it (FR8d). Before #8401 the restore was nested inside the
# success arm, where any new refusal arm would have skipped it by construction.
DO_RESTORE=false
if [ "$VERIFIED" = true ] && [ "$SRC" = devin-cache ]; then
  REAP_CAP=unverified
  if [ -f "${ROOT}/skills/git-worktree/scripts/worktree-manager.sh" ]; then
    # ANCHORED at statement start, so a COMMENT mentioning the token cannot satisfy the gate,
    # and read as a SET so `no-branch-keyed-guards` / `branch-keyed-guards-v2` are not accepted
    # as the capability by substring. The value is space-separated; membership is additive.
    CAP_VAL="$(sed -n 's/^[[:space:]]*SOLEUR_WORKTREE_REAP_CAPABILITY="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' \
      "${ROOT}/skills/git-worktree/scripts/worktree-manager.sh" | head -1)"
    case " ${CAP_VAL} " in
      *" branch-keyed-guards "*) REAP_CAP=ok ;;
    esac
  fi
fi
if [ "$VERIFIED" = true ] && [ "$REAP_CAP" != unverified ]; then
  # The classifier itself is presence-guarded (#7474). Without this, a verified-but-TORN
  # install runs a missing script, the `case` sees empty output, and the gate reports
  # `reason=cloud-session` — telling the operator their local session is a cloud one. A
  # guard that misattributes is worse than one that skips.
  if [ -f "${ROOT}/scripts/cloud-detect.sh" ]; then
    SESSION_PROBE=present
    # The proceed set is EXACTLY the classifier's own documented exception — its header says
    # "consumers MUST fail closed on [not-local:<reason>]" and names one carve-out: "Callers
    # treat no-devin-env like `local`". Do not widen it. A review pass proposed adding
    # `not-local:sentinel-absent` because a local box with a stray `DEVIN_DIR` exported reports
    # it (measured, and it is this repo's own operator profile); but that reason means "a
    # Devin-MARKED box with no sentinel", which is precisely the fail-closed case — admitting it
    # would let a real Devin cloud session reach `cleanup-merged`. The symptom is real and the
    # fix belongs in the REASON, not the predicate: SESSION_VERDICT is reported below so the
    # operator sees which verdict skipped them and can clear it.
    SESSION_VERDICT="$(bash "${ROOT}/scripts/cloud-detect.sh" 2>/dev/null | head -1)"
    [ -n "$SESSION_VERDICT" ] || SESSION_VERDICT=classifier-silent
    case "$SESSION_VERDICT" in
      local|not-local:no-devin-env) SESSION_OK=true ;;
    esac
  fi
fi
if [ "$VERIFIED" != true ]; then
  # Do not let the session-start gate no-op invisibly: the form before #7442 ended in
  # `|| true`, so an unresolved root skipped cleanup-merged AND the .mcp.json restore with
  # no output at all. The RESOLVE line above now also says WHICH arm produced nothing.
  echo "SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified"
elif [ "$REAP_CAP" = unverified ]; then
  # A cache root whose reaper predates the branch-keyed guards. Refused BY NAME rather than
  # run — and `source=` is emitted because the three arms have three different remedies.
  #
  # This arm deliberately does NOT take the non-destructive work with it. `git worktree list`
  # and the `.mcp.json` restore need neither the classifier nor the reaper, and a refusal
  # that silently killed all three gates would be the very defect #8401 exists to fix. A row
  # asserting only `want_not_in … STUB_WORKTREE_MANAGER` passes for that implementation too,
  # which is why R11 carries positive `want_in`s as well.
  echo "SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified source=${SRC}"
  git worktree list
  DO_RESTORE=true
elif [ "$SESSION_PROBE" != present ]; then
  # A DISTINCT reason from the worktree-manager arm below. Both said
  # `reason=absent-from-verified-root`, which (a) told the operator a script was missing without
  # saying which, and (b) made plugin-root-anchoring.test.ts P8 satisfiable by this sibling — the
  # exact vacuity P8's own comment records having closed for this producer.
  echo "SOLEUR_SESSION_START_SKIPPED reason=classifier-absent"
  # Same argument as the capability arm above, applied to the arm it was missing from: the
  # `.mcp.json` restore needs neither the classifier nor the reaper, so a torn install missing
  # `cloud-detect.sh` has no reason to lose it. The `cloud-session` arm below deliberately does
  # NOT set this — there the classifier ANSWERED and said this is a cloud session, and skipping
  # session-start maintenance is the contract, not a casualty.
  DO_RESTORE=true
elif [ "$SESSION_OK" != true ]; then
  # Name the VERDICT. A blanket `reason=cloud-session` told an operator with a stray DEVIN*
  # variable on an ordinary laptop that their local session was a cloud one, and gave them
  # nothing to act on.
  echo "SOLEUR_SESSION_START_SKIPPED reason=cloud-session verdict=${SESSION_VERDICT}"
else
  # Identity is not freshness (#7474) — see the Step 0.0 probe above. Arm order is the
  # loader-substituted token, then GROK_PLUGIN_ROOT (ADR-179 decision 11); the name=soleur
  # preflight in the resolver runs on whichever arm produced the root.
  DO_RESTORE=true
  if [ -f "${ROOT}/skills/git-worktree/scripts/worktree-manager.sh" ]; then
    bash "${ROOT}/skills/git-worktree/scripts/worktree-manager.sh" cleanup-merged
    git worktree list
  else
    echo "SOLEUR_SESSION_START_SKIPPED reason=absent-from-verified-root"
  fi
fi

if [ "$DO_RESTORE" = true ]; then
  # The .mcp.json restore is a SIBLING of the reaper, not nested inside it. It was nested, and
  # that re-created in miniature the coupling #8308 is about: the restore needs no part of
  # worktree-manager.sh, so on a verified-but-torn install missing that one script it silently
  # did not run and the only marker named the reaper. The PR's own account lists the never-
  # running restore as a SEPARATE consequence of the bug; keeping it behind the reaper's
  # presence check would have contradicted that.
  #
  # Write-then-rename, NEVER `git show … > .mcp.json`. The shell TRUNCATES the redirect target
  # before forking `git show`, so every failure mode leaves a 0-byte .mcp.json. Measured:
  # 67 bytes -> 0, silently, with `2>/dev/null || true` swallowing the status and reporting
  # rc 0. On a customer machine that file is their MCP server registry, commonly holding
  # per-server tokens, and it is untracked — so the loss is unrecoverable.
  if git show main:.mcp.json > .mcp.json.soleur-tmp 2>/dev/null; then
    if mv .mcp.json.soleur-tmp .mcp.json; then
      :
    else
      # A failed rename leaves the temp file in the customer's worktree. Report it and
      # remove it; silence here is how a stray .soleur-tmp becomes someone's mystery file.
      rm -f .mcp.json.soleur-tmp
      echo "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-rename-failed"
    fi
  else
    # MEASURE the cause; do not name one (AP-021 — the rule this file's other markers enforce).
    # `git show main:.mcp.json` fails for at least three distinct reasons and the previous
    # single `reason=mcp-json-absent-on-main` asserted the first of them for all three, which
    # is the same defect as `reason=cloud-session` before it learned to print its verdict.
    # $? here is the `if` condition's status, so it is captured before `rm` overwrites it.
    SHOW_RC=$?
    rm -f .mcp.json.soleur-tmp
    if ! git rev-parse --verify -q main >/dev/null 2>&1; then
      echo "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-no-local-main"
    elif ! git cat-file -e main:.mcp.json 2>/dev/null; then
      echo "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-absent-on-main"
    else
      echo "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-read-failed rc=${SHOW_RC}"
    fi
  fi
fi
```

The script works from either the bare root or any worktree. The `.mcp.json` refresh is harmless inside a worktree (file gets overwritten on next session-start from the new CWD). Skip silently on first error — do not block routing on session-start hygiene.

See `knowledge-base/project/learnings/2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record.md` Session Errors #1-#2 for the gap this closes.

## Step 1: Worktree Context

Run `pwd`. If the path contains `.worktrees/`, extract the feature name and mention it:

"You're in worktree **feat-[name]**. Want to continue working on this, or start something new?"

If the user wants to continue the current feature, delegate to `soleur:work`. **Claude:** Skill tool (`soleur:work`) with the user input as arguments. **Grok:** Read `plugins/soleur/skills/work/SKILL.md` in this process and run it to completion. Then stop.

**Bare-repo CWD guard.** If `pwd` is NOT inside `.worktrees/` AND `git rev-parse --is-bare-repository` returns `true`, the CWD is a bare-repo root with no working tree. Any Edit/Write to files visible at this path lands on stray untracked content not on any branch, and `node_modules` is not hydrated so typecheck/dev-server commands fail. For file-touching intents (the `fix`/`implement`/`drain`/`review` rows in Step 2), do NOT edit in place — route through `soleur:one-shot` so a proper worktree is created via `worktree-manager.sh`. For read-only intents (questions, exploration, `clo-attestation`, `legal-threshold`), proceed without worktree creation. See `knowledge-base/project/learnings/2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`.

## Step 2: Classify and Route

### Step 2.0: Harness adapter (never improvise)

<!-- harness-forms:start -->
Before applying the routing table, detect the active harness and use the correct invocation surface. Canonical implementation: `plugins/soleur/lib/harness.ts`.

| Harness | Skills | Agents | Entry command |
|---------|--------|--------|---------------|
| Claude Code | **Skill tool** — `soleur:<skill>` | **Task tool** — `subagent_type` | `/soleur:go` |
| Grok Build | **Slash command** — `/<skill>` (e.g. `/one-shot`) | **spawn_subagent** | `/go` (not `/soleur:go`) |
| Codex | Load `$soleur:<skill>` through `skills.read` or the installed SKILL.md | **spawn_agent** with canonical instructions | `$soleur:go` |
| Devin CLI | **Slash command** — `/soleur:<skill>` | **run_subagent** with agent id | `/soleur:go` |

**Codex harness:** read [Codex compatibility instructions](../codex/INSTRUCTIONS.md).
Use the installed plugin root for plugin-owned paths. Reading the full named
skill is the Codex entry point when no skill-loading tool is available; execute
all of its phases. Do not invoke a nonexistent Skill tool or a Grok slash command.

**Devin CLI harness:** read [Devin compatibility instructions](../devin/INSTRUCTIONS.md).
Devin exposes Soleur skills as slash commands: `/soleur:<skill>` (e.g. `/soleur:one-shot`, `/soleur:brainstorm`). Agents are spawned via `run_subagent`.

**Routing contract (never improvise):** when a table row names `soleur:<skill>` or an agent, invoke it via the harness adapter (`invokeSkill` / `spawnAgent` semantics in `harness.ts` — or `routingInstructions()`). Pass the original user input as args/prompt. **Do NOT** improvise workflow steps, explore the filesystem as a substitute, or hand-roll plan/work/review phases when a registered route exists.

**Grok Build harness:** entry is `/go` (slash command); agents via `spawn_subagent`. Invoke a skill by Reading `plugins/soleur/skills/<name>/SKILL.md` in this process (`/<skill>` names the skill; it is not a nested tool_use). **Agent spawn keys:** Grok matches `subagent_type` to the `.grok/agents/` **filename stem** (colons → hyphens), e.g. `soleur:product:cpo` → `soleur-product-cpo`. Colon form is listed in some error catalogs but is **rejected** at spawn — always use `spawnAgent()` / `agentIdToGrokSubagentType()`. See `lib/harness.ts:detectHarness`, `formatSkillInvocation`, `spawnAgent`.

**Devin CLI harness:** entry is `/soleur:go` (slash command); agents via `run_subagent`. Invoke routed skills with the `/soleur:<skill>` slash command. See `lib/harness.ts:detectHarness`, `formatSkillInvocation`, `spawnAgent`.

**Self-reference (Phase C #6323 / epic #6320):** This document + the eval-harness Grok arm were produced and shipped by invoking `/go 6320 implement and ship the next open feature` (next open = Phase C #6323) inside worktree `feat-one-shot-6323-grok-phase-c` (draft PR #6329). The routing contract above is the enforceable spec exercised by this very run. Edits to the go-routing block are gated by eval-harness (see `gated-skills.json` + `eval-gate:block:go-routing`).

If harness is unknown and Skill/slash tools are unavailable, STOP and suggest `grok inspect` (Grok), `claude --plugin-dir ./plugins/soleur` (Claude), or `devin plugins install ./plugins/soleur` (Devin). Live CLI 1.0.29 has no `grok --trust` — do not invent one.
<!-- harness-forms:end -->

Analyze the user input and classify intent using semantic assessment:

<!-- eval-gate:block:go-routing:start -->
| Intent | Trigger Signals | Routes To |
|--------|----------------|-----------|
| fix | The user describes broken behavior, errors, regressions, or something that needs fixing | `soleur:one-shot` |
| drain | "fix all issues labeled X", "drain the Y backlog", "close all label:Z", "clean up the X backlog" | `soleur:drain-labeled-backlog` |
| drain-prs | "drain the open PRs", "review and merge all open PRs", "merge all the green PRs", "clear the PR queue/backlog", "triage open pull requests" — draining open PULL REQUESTS (not labeled issues, which is the `drain` row above; not a single named PR, which is the `review` row below) | `soleur:drain-prs` |
| clo-attestation | The user input is `#N` (or a bare number) AND `gh issue view N` returns a body containing `clo_routable: true` OR matches ALL of: `type:\s*manual`, `manual_because:\s*subjective-design-call`, AND at least one external legal-source signal (`eur-lex\.europa\.eu`, `leginfo\.legislature\.ca\.gov`, `congress\.gov`, `federalregister\.gov`, `legislation\.gov\.uk`, `laws-lois\.justice\.gc\.ca`, OR a `Art\.\s*[0-9]+` / `§\s*[0-9]+` statute citation in the body). Must fire BEFORE the `review` row. | `soleur:legal:clo` agent (Task spawn; the agent's prompt receives the full issue body + the verification question(s) extracted from the body) |
| review | "review PR", "check this code", PR number reference (when `#N` resolves via `gh pr view N` — confirm PR-vs-issue type before routing) | `soleur:review` |
| legal-threshold | The user input mentions an inbound vendor MSA, DSAR (data subject access request) / right-to-be-forgotten / data deletion request / account deletion request / data export request / "what data do you have on me", AI vendor terms / vendor AI review, OSS license question (GPL/AGPL/SSPL/copyleft), OR a personal-data exposure / unauthorized access / PII leak that crosses a statutory clock (GDPR Art. 33 72h) — events that exceed founder-grade compliance helping and warrant a downstream specialist | `soleur:legal:clo` agent (Task spawn; the Assess phase emits the threshold catalog from `knowledge-base/legal/recommended-tools.md`) |
| incident | The user describes a live or recent production incident (outage, customer-impact, Sentry alert) needing classification + PIR. NOTE: pure data breaches without an operational outage route to `legal-threshold` above (statutory clock takes precedence); use `incident` for ops-postmortem scope (uptime, latency, error-rate). | `soleur:incident` |
| implement | User asks to **implement**, **build**, or **ship** a scoped feature, issue, or phase (e.g. "implement Phase F", "#6325 implement", "ship this feature") — concrete deliverables, not open-ended exploration | `soleur:one-shot` |
| questionnaire | The user needs an ANSWER THEY DO NOT HOLD from a NAMED THIRD PARTY outside the company — an accountant, bookkeeper, lawyer, notary, auditor, insurer, bank, regulator, landlord, or a vendor — and the deliverable is a document to send them ("ask my accountant", "draft questions for the lawyer", "what do I need from the insurer", "I need to email our bookkeeper about"). The tell is a recipient plus a decision the founder is blocked on; a question the founder can answer, or one about this codebase, is NOT this row — those are `default` and `fix` respectively. Also reached without routing when `.claude/hooks/pre-ask-technical-fork-gate.sh` denies an external-expert `AskUserQuestion` | `soleur:questionnaire-generate` |
| glossary | The user asks what a term MEANS inside this repository, reports that two agents or documents use one word for different things, or asks to record or sharpen the definition of a project term ("what do we mean by lane", "shard and shard mean two different things here", "write down what a rung is"). Scoped to the repository's own vocabulary — a question about a third-party product's terminology is `default` | `soleur:kb-glossary` |
| default | Everything else — features, exploration, questions, generation, vague scope without implement/build/ship intent | `soleur:brainstorm` |
<!-- eval-gate:block:go-routing:end -->

**Operator-typed tooling (ADR-236).** Every flag, cron and operator skill named in this paragraph acts on Soleur's own flags, tenants and production access; a founder asking for a feature flag in their own product is ordinary implementation work (the `implement` row). Of these, the following are user-invoked: on Claude Code and Devin the model cannot run them and the Skill tool refuses them (the key is inert on Codex and Grok, but the same hand-off policy applies there). When a request targets one of them, do not route and do not re-run the skill's steps by hand. Reply with the exact command for the operator to type, rendered in the active harness's operator-typed form (`formatSkillInvocation`): deleting a flag (`soleur:flag-delete`); tenant provisioning (the four skills `soleur:provision-hetzner`, `soleur:provision-cloudflare`, `soleur:provision-doppler`, `soleur:provision-github`, in the order `knowledge-base/engineering/operations/runbooks/tenant-provisioning.md` gives); the prod SSH allowlist (`soleur:admin-ip-refresh`; for a failing SSH connection, first run the read-only Diagnosis steps in `knowledge-base/engineering/operations/runbooks/admin-ip-drift.md`, per `hr-ssh-diagnosis-verify-firewall`, then hand over the command); a user's role (`soleur:user-set-role`); a Cloudflare token's scope (`soleur:cf-token-scope`). When your system prompt says you are the web Command Center, these commands are CLI-only, so say that and name the command. The rest stay model-invocable and have no routing row: invoke them directly through the Skill tool (or the harness's slash form): listing flags (`soleur:flag-list`), creating a flag or flipping its roles (`soleur:flag-create`, `soleur:flag-set-role`), and cron list/delete (`soleur:cron-list`, `soleur:cron-delete`, or `soleur:schedule`). For the flag and role skills (`soleur:flag-create`, `soleur:flag-set-role`, and `soleur:flag-delete` / `soleur:user-set-role` once the operator has typed them), the agent runs only the script's `--dry-run` and then replies with the exact write command for the operator's own terminal, never running it: every production write behind those scripts needs a person to type `yes` at a TTY, and an agent shell gets exit 64 (ADR-249, #8486).

### Step 2.1: Post-route invocation fidelity (Grok Build — never bypass)

<!-- workflow-fidelity:block:go-post-route:start -->
When Step 2 routes to a **pipeline skill** (`soleur:one-shot`, `soleur:brainstorm`, `soleur:drain-labeled-backlog`, `soleur:drain-prs`):

0. **You are still in `soleur:go`, not in the pipeline skill.** Routing is classification + dispatch only. The `soleur:go` handler does **not** run pipeline phases, create worktrees for implementation, or write product code — even if you "know what the skill would do next."
1. **Your very next action** MUST invoke that skill via the harness adapter (`plugins/soleur/lib/harness.ts` `invokeSkill()`). **Grok:** Read `plugins/soleur/skills/<name>/SKILL.md` in this process and run it to completion — slash `/<name>` names the skill; it is not a nested tool_use. **Claude:** Skill tool (`soleur:brainstorm`, `soleur:one-shot`, …). **Devin:** the slash command for `soleur:brainstorm`, `soleur:one-shot`, … as the Step 2.0 table gives it, with `<args>`. Do **not** execute a subset of the skill's steps with Write/Edit/Shell yourself. (Claude must not substitute Read for the Skill tool.)
2. **Do NOT end your turn** after routing, worktree creation, brainstorm artifacts, or a pushed draft PR. Those are mid-pipeline checkpoints, not deliverables.
3. **`brainstorm` deliverable:** brainstorm doc + spec + handoff to `soleur:plan` (or `soleur:one-shot` shortcut when requirements are clear). **FORBIDDEN:** product code during brainstorm.
4. **`one-shot` deliverable:** merged PR + `<promise>DONE</promise>` (Step 8). Pushed code on a draft PR without review/ship is a **protocol violation**, not completion.
5. **Lifecycle handoff skills (standalone or under orchestrators):** `plan` → `soleur:work`; `work` → `soleur:review` → `soleur:qa` (when structural UI gate fires) → `soleur:compound` → `soleur:ship`. Never substitute ad-hoc tool loops. Each skill's exit summary is a **continuation gate**, not a stopping point.
6. **Canonical contract:** `plugins/soleur/lib/workflow-fidelity.ts` (`PIPELINE_SKILLS`, `IMPLEMENTATION_TAIL`, `HANDOFF_SKILLS`) + `routingInstructions()` in `harness.ts`.
<!-- workflow-fidelity:block:go-post-route:end -->

If intent is clear, route without confirmation:

<!-- harness-forms:start -->
- **Claude Code:** invoke via the **Skill tool** (`soleur:<skill>`, args = original user input). Agents: **Task tool** with `subagent_type` and prompt = original user input.
- **Grok Build:** Read `plugins/soleur/skills/<skill>/SKILL.md` in this process and run it to completion (`/<skill>` names the skill; it is not a nested tool_use). Agents: **spawn_subagent** with the agent id and prompt = original user input.
- **Devin CLI:** invoke via the **`/soleur:<skill>` slash command** with args = original user input. Agents: **run_subagent** with the agent id and prompt = original user input.
<!-- harness-forms:end -->

Map `soleur:<skill>` cells in the table to the Grok skill name `/<skill>` (strip the `soleur:` prefix) and Read that SKILL.md — do not nested-invoke slash. **Exception:** rows whose `Routes To` cell names an agent (e.g., `soleur:legal:clo`) instead of a `soleur:<skill>` skill spawn that agent — never substitute a manual workflow. When extending this table, prefer routing to a skill when one exists; route to an agent only when no skill wraps the desired behavior.

**PR-vs-issue type resolution (when `#N` or a bare number is the input):** Before evaluating the `clo-attestation` and `review` rows, run `gh issue view N --json body,title,state 2>/dev/null` to determine whether `N` is an issue. If `gh issue view` succeeds AND the body satisfies the `clo-attestation` predicate, route to soleur:legal:clo. If `gh issue view` succeeds but no `clo-attestation` match, route to `soleur:review` only after confirming `gh pr view N` ALSO succeeds (otherwise the input is a non-attestation issue — route to default/brainstorm with the issue body as context). This ordering closes the gap that caused `soleur:go #3998` to mis-route an issue to PR review. See `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`.

When routing to `soleur:drain-labeled-backlog`, extract the label value from the user's message. If the user used a bare name (e.g., "security"), resolve it to the namespaced form by running `gh label list --limit 100 | grep -i <name>` before invoking — `gh` rejects an invalid `--label` with a clear error, so verify against the live label set. Pass the resolved label via `--label <resolved>` in the skill arguments.

If intent is truly ambiguous, use the **AskUserQuestion tool** with 4 options: Brainstorm (Recommended), Fix (one-shot), Drain (labeled backlog), Review.

## Sharp Edges

- **NAME-relative worktree detection (Linear-ID-keyed entry).** Step 1 only checks whether `pwd` is currently inside a worktree (CWD-relative). If the user input contains a Linear ID (`SOL-\d+`) and `git worktree list` shows a sibling worktree named after that ID (e.g., `.worktrees/feat-one-shot-sol-39-*` or `.worktrees/feat-fix-sol-39-*`), surface that state BEFORE routing to one-shot — routing fresh would collide with the existing branch and orphan any open draft PR. Present a 4-option `AskUserQuestion` (continue / review existing PR / restart fresh / brief). If "restart fresh" is chosen, follow up with a SECOND `AskUserQuestion` enumerating cleanup scope (full nuke / soft nuke / cancel) so destructive actions get explicit per-step approval. See `knowledge-base/project/learnings/2026-05-12-soleur-go-restart-fresh-from-existing-wip.md`.
- **Worktree-recovery PR-merge probe.** When the user asks to resume/recover a stale worktree (e.g., after a laptop crash, branch switched away, phantom staged files), run `gh pr list --head <branch> --state all --json number,state` BEFORE proposing "reset to remote branch". A remote feature branch existing is NOT proof the work is open — squash merges leave the source branch intact. If `state == MERGED`, the recovery path is clean-and-remove (`git reset --hard HEAD` → `git worktree remove` → `git push origin --delete <branch>`), not reset-to-remote (which would silently re-introduce pre-merge state). See `knowledge-base/project/learnings/workflow-patterns/2026-05-19-worktree-recovery-check-pr-merge-status-first.md`.
- **An EMPTY worktree is not an ABANDONED one — free-prose entry has no guard at all.** The two sharp edges above are *input-keyed*: NAME-relative detection fires on a `SOL-\d+` Linear ID, worktree-plan-vs-issue fires on a `#N`. A brainstorm entered as plain English carries neither, so **no guard evaluates a name-matching sibling worktree** — the most common entry shape is the uncovered one. Worse, the signals that read as "abandoned scaffold" are identical to the signals of a worktree created *thirty seconds ago*: one `chore: initialize` commit on current `main`, a clean `git status`, and an open `WIP:` draft PR. Before reusing ANY worktree you did not create in this session, run both probes: `gh pr view <n> --json updatedAt,author` (a PR updated minutes ago is a LIVE session, not a leftover) and grep that worktree's `specs/feat-*/spec.md` frontmatter + `plans/*` for an issue number — if it names a DIFFERENT issue, it is a different feature. Reuse loses commits: two sessions on one branch means one hard-resets the other's work away, and both write the same `specs/feat-<name>/spec.md` path. Default to a sibling branch; an extra worktree costs nothing. **Why:** 2026-08-06 — `feat-alpha-onboarding-motion` presented as an abandoned scaffold, was a live session on #7329; it hard-reset the branch and discarded commit `4943757d7`, and a spawned design agent had to recover its `.pen` files from a dangling commit. See `knowledge-base/project/learnings/2026-08-06-an-empty-worktree-is-not-an-abandoned-one.md`.
- **Worktree-plan-vs-issue alignment (`#N` entry → "Continue in that worktree").** When the input is an issue `#N` and a topically-named worktree already exists, NAME-relevance is NOT issue-relevance. Before offering "Continue in that worktree", grep the worktree's planning artifact (`knowledge-base/project/plans/*`, `specs/feat-*/spec.md` frontmatter `closes:`) for the input issue number. If the worktree's plan targets a DIFFERENT (sibling) issue, surface that mismatch in the `AskUserQuestion` options (offer a fresh worktree for `#N` vs. continuing the existing one for `#M`). Issues that a body explicitly splits into a "separate PR" / "follow-up PR" must not be silently co-located. See `knowledge-base/project/learnings/2026-05-29-brand-hex-commit-gate-and-go-worktree-plan-mismatch.md`.
<!-- harness-forms:start -->
- **Grok entry is `/go`, not `/soleur:go`.** If the operator typed `/soleur:go`, continue — that is Claude's slash; Grok's is `/go`. Do not refuse or re-prompt.
<!-- harness-forms:end -->
- **Grok Build bypass guard (#6325 class).** If you routed to `soleur:one-shot` and find yourself writing product code or running `git commit` before `soleur:review` and `soleur:ship` ran, STOP — you inlined the pipeline. Invoke `soleur:one-shot <args>` (or continue the active one-shot Steps 3–8), never "implement then report done."
- **Brainstorm / plan / work bypass guard (#6320 lifecycle).** If you routed to `soleur:brainstorm` and wrote product code, or finished brainstorm/plan artifacts without invoking `soleur:plan` or `soleur:work`, or pushed from `soleur:work` without `soleur:review` → `soleur:ship`, STOP — invoke the mandated successor from `workflow-fidelity.ts` (`BRAINSTORM_CHILD_SKILLS`, `IMPLEMENTATION_TAIL`).
- **Scrub closed `#N` contextual citations before invoking one-shot.** When routing to `soleur:one-shot`, the args you construct must use `#N` form ONLY for OPEN work-target issues. A *contextual* citation of a prior merged PR/issue ("structural causes already fixed in #4577", "supersedes #1234") trips one-shot's Step 0a.5 closed-issue collision abort — the gate cannot distinguish a work target from a citation. Rephrase such citations to date-anchored prose ("the apex-canonical reconciliation merged 2026-05-29") before invoking. **Scrub the QUOTED TITLES too, not just your prose** — a decision-challenge/follow-up issue routinely carries the predecessor `#N` inside its own title (`decision-challenge: … while fixing #6572`), so an args block that quotes that title verbatim to say which issue to close re-imports the closed ref and the gate aborts on args that read as fully scrubbed. Grep your constructed args for `#[0-9]+` and confirm every survivor is an OPEN work target before invoking. **Why:** #6578 — two aborts, prose scrubbed on the first, the title quote missed on both. See `knowledge-base/project/learnings/2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md` and `knowledge-base/project/learnings/workflow-patterns/2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`.
- **An issue that claims the bug is external ("not in this repo", "vendor/bot backend", "no code here") is a claim to VERIFY, not a fact to route on** (`hr-verify-repo-capability-claim-before-assert` applied to routing). Before deflecting such an issue as out-of-scope or dispatching it to a non-existent external service, `git grep -l "<verbatim symptom string the issue quotes>" main` — a named "bot"/"GitHub App" is frequently the *identity* an in-repo automation authenticates as, not a separate codebase, and its user-visible comment strings are string literals in the code that emits them. If the grep resolves, route to `one-shot` and have the plan/PR body correct the misframing. See `knowledge-base/project/learnings/workflow-patterns/2026-07-06-issue-claims-bug-is-external-verify-with-literal-grep-before-routing.md` (#6132 — "external soleur-ai bot" was the in-repo `cron-follow-through-monitor.ts`).
- **An operational "do the real cutover / run the workflow / flip it live" request routes to a gated `workflow_dispatch`, NOT to `soleur:one-shot`.** When the work's *mechanism* already merged and the ask is to EXECUTE it in production (a cutover, a migration apply, a plaintext wipe), the deliverable is dispatching the gated `workflow_dispatch` — verify readiness first (target state exists, dry-run rehearsal green, escrow/preconditions proven), confirm the GitHub `environment:` required-reviewer set is **non-empty** (a zero-reviewer environment auto-approves — DP-11 F8), then `gh workflow run <wf>.yml -f dry_run=false`. Dispatching QUEUES the irreversible step for the operator's environment approval; it does not bypass the human gate, so proceed without a redundant confirmation once the operator has asked. The **code FIX that FOLLOWS a safe-abort** (a fail-closed gate that discarded its evidence, a missing precondition) is the one-shot task — not the cutover itself. See `knowledge-base/project/learnings/workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`.
- **Diagnostic / incident / verification loops: self-pull from the observability layer — never ask the operator to fetch.** When any route surfaces a failure to diagnose, pull the errors/telemetry yourself: Better Stack `SOLEUR_*` markers via `scripts/betterstack-query.sh` (creds in Doppler `prd_terraform`) and Sentry. Never ask the operator to paste error output, run probes (`grep`/`stat`/`git config`), or eyeball logs — the operator decides, they do not retrieve. If a needed diagnostic signal is missing from telemetry, ADD a monitored stdout `SOLEUR_*` marker in the emitting code so the next occurrence self-reports — do not escalate to the operator for it. **And when a component reports SUCCESS but its downstream effect is absent (a webhook 2xx with no handler run, a deploy exit-0 with no state change, a run "succeeded" on a stale artifact), ship THAT component's OWN error channel FIRST (its unit/binary journald → the vector allowlist) BEFORE black-box reproduction — a success-code that fires regardless of command success is a silent-failure anti-pattern, and verify gates must assert against the EXPECTED source-of-truth count, not the artifact's self-reported total.** Cite `hr-no-dashboard-eyeball-pull-data-yourself`. See `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md` (#5934 worktree-wedge) and `knowledge-base/project/learnings/2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md` (#6178 — webhook 202 while fork/exec died E2BIG; hours of manual repro before the unshipped webhook journald named it).
- **An empty telemetry query is not evidence of absence until you have verified the signal is instrumented AND that retention covers the window.** Before reading silence as an all-clear in any incident/verification loop, check both: does a source actually ship this channel (grep the vector allowlist; `journalctl -u <unit> -o json -n 200 | jq -r .SYSLOG_IDENTIFIER | sort -u`), and does retention reach back far enough (`journalctl --list-boots`)? A query returning nothing because the channel was never allowlisted is indistinguishable from one returning nothing because the event never happened — and the first reads as safety. **Why:** 2026-07-28 — the "did anyone SSH into prod during the compromise window?" query would have come back empty for lack of an `sshd` entry in the Vector Source 4 allowlist, not for lack of an intrusion. See `knowledge-base/project/learnings/security-issues/2026-07-28-vscode-folderopen-task-rce-and-fleet-wide-key-rotation.md`.
