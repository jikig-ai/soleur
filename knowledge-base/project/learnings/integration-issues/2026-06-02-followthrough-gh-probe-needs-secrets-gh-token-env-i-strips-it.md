# Learning: follow-through gh-probes silently never close — `env -i` strips GH_TOKEN, and local `gh` masks the CI failure

## Problem

Wiring deferred-scope-out issue #3950 into the follow-through sweeper, the
verification script `scripts/followthroughs/cla-evidence-hardening-3950.sh` uses
`gh run list` to probe for a post-merge green CI run. The script PASSED when run
locally (exit 0), and the header claimed "No secrets required (uses the sweeper's
default GH_TOKEN env block)." Both were **wrong for the CI sweeper context** — the
probe would have returned exit 2 (transient) on every sweep forever, so #3950
would **never auto-close**. No prior follow-through issue had ever been
auto-closed via a `gh`-using probe (the path was untested).

## Root Cause

`scripts/sweep-followthroughs.sh` runs every verification script under an
`env -i` sandbox with a **narrow allowlist**: `PATH`, `HOME`, and ONLY the env
vars named in the directive's `secrets=` clause (sweeper line ~194). The workflow
sets `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` in its own `env:` block, but `env -i`
**strips it** before the verification script runs.

Two compounding traps:
1. **On a CI runner, `gh` authenticates from `GH_TOKEN`** (no `~/.config/gh`). With
   `GH_TOKEN` stripped, `gh` is unauthenticated → every `gh` call fails → the probe
   exits 2 (transient) → the issue never closes. It fails **safe** (never a false
   close) but **silent** (no loud error — just transient-forever).
2. **Locally, `gh` authenticates from `~/.config/gh/hosts.yml`**, which lives under
   `HOME` — and `env -i` PRESERVES `HOME`. So running the script locally PASSES,
   masking the CI failure entirely. `env -i PATH=... HOME=$HOME gh ...` succeeds on
   a dev box and fails on a runner.

## Solution

Declare `secrets=GH_TOKEN` in the directive of any gh-using follow-through probe:

```html
<!-- soleur:followthrough script=scripts/followthroughs/<x>.sh earliest=<iso> secrets=GH_TOKEN -->
```

The sweeper's `secrets=` handler forwards each named var from its own env through
the `env -i` allowlist (`env_args+=("$name=${!name}")`), and `GH_TOKEN` is set in
the workflow `env:`. This is the same opt-in mechanism `sentry-checkins-3859.sh`
uses for `secrets=SENTRY_AUTH_TOKEN`. No sweeper change needed — the substrate
already supports it; the gap was that no gh-probe had ever declared it.

Only the **date** trigger shape needs no `secrets=` (its body is a trivial
`exit 0` gated by `earliest=`; it never calls `gh`). The dependency / event-grep /
counter shapes all use `gh` → all need `secrets=GH_TOKEN`.

## Key Insight

**A verification/probe script that passes locally can fail in its sandboxed CI
runtime when the two environments authenticate differently.** `env -i` whitelists
deliberately; `gh` (and any CLI) sourcing auth from `HOME` vs an env-var token is
the seam. When a script runs under `env -i`, enumerate which env vars its tools
need at runtime and forward them explicitly — do not assume a token "is in the
environment." And add a test that runs the script through the ACTUAL sandbox
(`env -i` + the secrets-forwarding path), not just a bare local invocation: the
local PASS is a false signal.

## Session Errors

1. **`components.test.ts` failed: backtick file-path reference in a skill's SKILL.md.**
   The "No backtick file references in skills" test (`/\`(references|assets|scripts)\/[^`]+\`/`)
   rejected `` `scripts/followthroughs/<slug>.sh` `` in review/SKILL.md.
   Recovery: rewrote as plain text + a markdown link (`[stub template](...)`).
   **Prevention:** in any `plugins/soleur/skills/*/SKILL.md`, never backtick-wrap a
   path beginning `references/`|`assets/`|`scripts/` — use a markdown link or plain
   prose. Backtick a basename only (`` `<slug>.sh` ``) if code-formatting is wanted.

2. **Self-introduced P1: gh-probe + "no secrets required" claim — silent-never-close.**
   Recovery: declare `secrets=GH_TOKEN`, corrected script header + 4 docs, added the
   T8 regression test (`sweep-followthroughs.test.sh`) proving `env -i` strips
   GH_TOKEN and `secrets=GH_TOKEN` forwards it.
   **Prevention:** the trigger→verification mapping in
   `followthrough-convention.md` now marks `secrets=GH_TOKEN` MANDATORY for every
   gh-using shape; review/SKILL.md §5 and review-todo-structure.md repeat it; T8 is
   the mechanical guard. When authoring ANY script that runs under `env -i`, list
   its runtime env deps and forward them — never trust a local PASS.

3. **Flawed Monitor command** (`jobs`/`%%` job-control in a fresh Monitor shell
   could not observe a separately-launched `run_in_background` bash). Redundant;
   stopped it. **Prevention:** to wait on a `run_in_background` task, react to its
   own completion `<task-notification>` — do not job-control it from a different
   shell (Monitor or otherwise).

## Tags
category: integration-issues
module: scripts/followthroughs, scripts/sweep-followthroughs.sh
