---
title: 'A drift guard scoped by resource NAME is addition-blind, and a mutation that deletes the block never tests the branch it advertises'
date: 2026-07-17
category: engineering
tags: [drift-guard, mutation-testing, terraform, false-pass, vacuous-assertion, doppler, cwe-522]
symptoms:
  - A mutation-tested guard reports 20/20 green against a file carrying the exact drift it was written to catch
  - A predicate's regex can be replaced with one that never matches and its own mutation test still passes
  - A whole-file grep asserting a per-resource property is satisfied by an unrelated sibling resource
module: WebPlatform
component: infra
problem_type: test_failure
resolution_type: test_fix
root_cause: vacuous_assertion
severity: high
issues: ['#6588', '#6593', '#6167']
---

## What happened

PR #6593 shipped `workspaces-luks.test.sh` to satisfy #6588's AC: *"a drift guard so a future volume
can't be born plaintext (mutation-tested: a plaintext volume must go RED)."* It had 20 assertions, all
mutation-tested, all green. Two review agents each proved it could not catch the drift it was named for.

## Three false-PASS classes, all verified

**1. Name-scoped extraction is ADDITION-blind.** Every predicate did
`awk '/^resource "doppler_secret" "workspaces_luks_key"/,/^}/'` — it checked *the block it knew by
name*. Adding a **second** resource beside it was invisible:

- A second `doppler_secret` writing the LUKS key to `config = "prd"`, `visibility = "unmasked"` — the
  exact CWE-522 drift the guard existed to name (that key then rides `doppler secrets download --config
  prd` into `docker run --env-file`, readable by the agent container whose data it encrypts). **20/20 green.**
- `length = 8` on the real passphrase + a decoy `random_password { length = 40 }`. The whole-file grep
  was satisfied by the decoy. **20/20 green.**

The mutations only ever *relocated* an existing value (`sed`-swap). Nothing tested **addition**.

**2. A mutation that deletes the resource header never reaches the check.** The `for_each` predicate was:

```bash
block="$(awk '/^resource "hcloud_volume" "workspaces_luks"/,/^}/' "$1")"
if [ -z "$block" ]; then echo 0; return; fi          # ← block-absent guard
if printf '%s' "$block" | grep -Eq '^[[:space:]]*for_each'; then echo 0; else echo 1; fi
```

Its mutation renamed the resource → the predicate exited at the **block-absent guard** and never reached
the `for_each` grep. Replacing that grep with `'^ZZZ_NEVER_MATCHES'` left the suite **20/20 green and the
mutation still passing**. Half the AC had completely unprotected logic.

**3. `awk '/^resource …/,/^}/'` truncates at the first column-0 `}`.** A nested block closed at column 0
hides everything after it. `terraform fmt` would reject that layout — but fmt runs in the `validate` job
while the guard runs in `deploy-script-tests`, so the guard's soundness silently depended on a gate in
**another job it never named**.

## The rules

- **A guard keyed on a resource's NAME can only ever police that resource.** If the threat is "the key
  must not reach shared `prd`", assert it over the FILE (`config = "prd"` appears nowhere) and pin
  **cardinality** (exactly one `doppler_secret`), not over the one block you happened to write. Ask: *what
  could someone ADD, beside this, that the predicate would never look at?*
- **A mutation must exercise the branch the predicate advertises.** Deleting the subject tests the
  fail-safe guard, not the logic. Litmus: **replace the predicate's core regex with one that can never
  match — if the suite stays green, the mutation is testing the wrong thing.** This is cheap and it is the
  only way to catch a predicate whose logic is dead.
- **Extract by brace depth, not by an `awk` range**, whenever the block can nest.
- **Strip all three HCL comment forms** (`#`, `//`, `/* */`). A file that FORBIDS a construct must also
  DISCUSS it, so every forbidden-token grep collides with the file's own prose
  (`cq-assert-anchor-not-bare-token`). This bit twice in one PR: first a bare `grep 'ignore_changes'`
  matched the `.tf`'s own "NO ignore_changes" comment; then the *fix* used
  `sed -E 's|^[[:space:]]*(#|//).*$||'` — `|` as **both** delimiter and alternation — so sed died
  `unknown option to 's'`, which `set -uo pipefail` does **not** abort on, silently degrading the
  predicate to grepping the unstripped file. **A sed that dies inside a pipeline is a silent false-PASS.**

## The security half: a false claim the repo had already disproven

The `.tf` described the boot token as *"read-only least-privilege… NOT the full-prd token"*. **False.**
Doppler branch configs **inherit the root**, so a token scoped to `prd_workspaces_luks` resolves ~116
`prd` secrets including `SUPABASE_SERVICE_ROLE_KEY`. This was already documented at
[[2026-07-07-doppler-branch-config-does-not-isolate-secrets]] (severity high, #6122/#6167) — and #6167 is
tracking the identical bug in `prd_git_data`, **the precedent this PR mirrored**. The PR cited none of it.

The decision survived; the *reason* was wrong. Inheritance is **root → branch**, so a branch secret never
appears in a `--config prd` download. That **directionality** is the entire mechanism — not scope
reduction. Free on web-1 (already full-prd), so the CWE-522 container boundary genuinely holds.

**Rule: when you mirror a precedent, grep the learnings for the precedent's name before you copy its
security rationale.** A precedent's rationale is a claim about the precedent, not about you — and here the
precedent's own rationale was already known to be false. `git grep -l prd_git_data knowledge-base/project/learnings/`
would have surfaced it in one command.

## Cheapest prevention

For any `.test.sh` drift guard, before declaring it done:

1. **Add** a laundering resource beside each subject. Does it redden?
2. **Neuter** each predicate's core regex to `^ZZZ_NEVER_MATCHES`. Does the suite redden?
3. Run it under `env -i PATH=/usr/bin:/bin` to prove it needs nothing the CI job lacks.

Steps 1–2 take a minute and are what separates a mutation-tested guard from a guard-shaped file.
