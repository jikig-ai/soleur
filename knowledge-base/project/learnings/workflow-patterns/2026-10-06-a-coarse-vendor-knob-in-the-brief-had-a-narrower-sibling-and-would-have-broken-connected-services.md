# Learning: a coarse vendor knob named in the brief had a narrower sibling in the SDK types

## Problem

The slice-1 brief said "SDK subprocess env scrub". `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips every credential-shaped variable (by name or value shape) from Bash, hook and MCP subprocesses. Hosted sessions deliberately hand connected-service tokens (Stripe, Cloudflare, Hetzner, Doppler) to Bash, and `agent-runner.ts` tells the agent they are available, so the scrub would have broken Connected Services.

## Solution

Read the pinned SDK's type file (`sdk.d.ts`) for options near the one the brief named. `sandbox.credentials.envVars[{name, mode: 'deny' | 'mask'}]` removes named variables from sandboxed Bash only, so the Anthropic key and OAuth token can be withheld while service tokens stay. The same option's `mask` mode (sentinel inside the sandbox, real value injected at the proxy) is the in-SDK candidate for the slice-2 broker.

## Key Insight

A knob named in an issue or brief is the author's first candidate, not the option space. Two cheap checks before adopting it: grep the vendor's type file for sibling options with a narrower scope, and ask what the product currently promises the agent that the knob would revoke (here, the Connected Services prompt block).

## Session Errors

1. **Taste-class review findings were written into the plan before the approval gate** — Recovery: disclosed them at the gate and offered to revert — Prevention: apply only findings explicitly tagged mechanical before the gate; hold taste and user-challenge edits until the operator answers.
2. **Haiku-pinned repo-research reported two false claims** (the guard detects customers by `CLAUDE_PLUGIN_ROOT`; bwrap already blocks `ps`/`pgrep`) — Recovery: re-derived from `browser-snapshot-credential-guard.sh` and the sandbox config — Prevention: re-derive any subagent claim that bounds the design, as the brainstorm skill already says.
3. **The canary fixture was stale** (captured at SDK 0.3.197, pinned 0.3.284) and the plan assumed it tracked the pin — Recovery: `jq -r .sdkVersion` caught it before the plan froze — Prevention: when a plan relies on a committed capture, read its recorded version against the pin.
4. **`lint-infra-no-human-steps.py` flagged two hook-behaviour bullets and `markdownlint` flagged five list spacings** — Recovery: wrapped the bullets in a `lint-infra-ignore` region and spaced the lists — Prevention: run both on the plan before committing, in the CI invocation form where the lint supports it.

## Tags

category: workflow-patterns
module: plan
