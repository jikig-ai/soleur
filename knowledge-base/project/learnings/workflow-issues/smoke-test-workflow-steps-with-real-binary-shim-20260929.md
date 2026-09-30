---
title: Extracted `run:` blocks need a live smoke test — and the gh shim must exec the REAL binary by absolute path
date: 2026-09-29
category: engineering
tags: [workflow-guard, smoke-test, gh-cli, yaml-run-block, inngest]
symptoms: [a `gh`-shim smoke test of an extracted workflow step hung with zero output and forked endlessly; two `gh` CLI incompatibilities (`--slurp`+`--jq`, `gh issue list --order`) passed YAML/bash lint and all 56 structural guard asserts, and failed only when the step actually ran]
module: CI workflow detector steps
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: static verification (YAML parse, bash -n, shellcheck, mutation arms) cannot see CLI contract errors — only executing the embedded script against the real `gh` does
severity: medium
---

# Smoke-test extracted `run:` blocks against the real binary

## Problem

Shipping a new `Detect inngest CLI pin drift` step (#7463 PR-B), I verified it
three ways — YAML parse, `bash -n`, and a 56-assertion YAML-structural guard —
and all three were green while the step contained **two** runtime-fatal `gh`
misuses:

1. `gh api --paginate --slurp … --jq '…'` — `--slurp` is *unsupported with
   `--jq`* (flag-combination rejection, rc=1, no output).
2. `gh issue list … --order asc` — `--order` is not a flag on `issue list`
   (ordering goes through `--search 'sort:created-asc'`).

Both were invented-from-memory API shapes that static checks cannot falsify.
They surfaced only because I ran the extracted step end-to-end.

Separately, the smoke harness itself hung for ~110 s: the `gh` shim in
`/tmp/gh-shim/gh` passed reads through with `command gh "$@"`, but `command`
re-resolves via `PATH` — and the shim directory was first in `PATH`, so the
shim exec'd *itself* in an infinite fork loop. Fix: capture
`REAL_GH=$(command -v gh)` **before** prepending the shim dir, and have the
shim `exec "$REAL_GH" "$@"`.

## The working pattern

```bash
REAL_GH=$(command -v gh)          # BEFORE modifying PATH
mkdir -p /tmp/gh-shim
cat > /tmp/gh-shim/gh <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "issue create"|"issue comment"|"issue edit"|"label create")
    echo "SHIM: gh \$*" >&2; exit 0 ;;        # intercept WRITES
  *) exec "$REAL_GH" "\$@" ;;                 # real binary, absolute path
esac
EOF
chmod +x /tmp/gh-shim/gh
# extract the step's run: body via pyyaml, then:
PATH=/tmp/gh-shim:$PATH RUNNER_TEMP=$(mktemp -d) bash /tmp/step.sh
```

Intercept only the *write* verbs; pass API reads to the real binary so the
exercise is end-to-end. The run also verifies the step's failure-path output
(inspect the generated issue body file in `$RUNNER_TEMP`).

## Why this matters beyond this PR

Every workflow-guard suite in this repo proves the step's *text* is intact.
None of them prove the step *runs*. A quoted-heredoc `run:` block is dead code
to every linter — the only falsifier for CLI-contract errors is execution.
Whenever a PR adds or materially rewrites an embedded `run:` block, run the
extracted body once against a shim before relying on the guard suite as the
evidence.
