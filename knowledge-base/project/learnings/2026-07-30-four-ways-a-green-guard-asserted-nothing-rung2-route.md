---
title: "Four ways a green guard asserted nothing (the rung-2 route, #7066)"
date: 2026-07-30
category: test-failures
tags: [guards, mutation-testing, drift-guard, terraform, bare-token, anti-vacuity]
symptoms:
  - "A suite is fully green while the tripwire reads the wrong resource"
  - "Widening a prefix match is undetectable because every fixture shares the prefix"
  - "An empty value satisfies a cardinality check that only counted keys"
  - "An internal-consistency assertion passes no matter what the caller binds"
module: CI
component: infra_drift_guards
problem_type: logic_error
resolution_type: code_fix
root_cause: wrong_assumption
severity: high
issue: 7025
---

# Four ways a green guard asserted nothing (the rung-2 route, #7066)

Captured retroactively: PR #7066 fixed these four classes and recorded them only in its
commit messages, so they were unsearchable. Every one was measured against a **fully green**
suite (101/0, 39/0, or 54/0 depending on the arm).

## 1. Prose-satisfaction via `error_message` — prose the comment-stripper cannot see

`git-data-luks.test.sh` A19 extracted a Terraform `precondition` with `grep -A 3 | head -4`.
The 4th line of that window is `error_message`, which **interpolates the same
`data.hcloud_server_type.git_data.architecture` the clause greps for**.

So re-pointing the *condition* at a different data source in the same root
(`…hcloud_server_type.registry.architecture` — real, so the HCL stays valid and
`terraform fmt`-clean) left the tripwire silently reading **another host's architecture**
with the suite fully green.

The file had already closed prose-satisfaction for **comments** throughout — it strips them
before every assertion. `error_message` is prose the comment-stripper cannot see. Fix: narrow
the window to 3 lines, the scoping the sibling arm already used.

**Generalisable:** comment-stripping is not the whole of prose-satisfaction. Any field that
*interpolates the expression being asserted* — `error_message`, `description`, a log string,
a `printf` — is a second copy of the token inside the assertion window.

## 2. Cardinality is not discrimination — four members of one shape are one member

A16's comment claimed four `cax*` fixtures stopped a truncated `"ca"` prefix from passing.
False: `cax11/21/31/41` **all** start with `ca`, and `cpx/cx/ccx` start with none of it. So
widening the match to `"ca"` was undetectable by every fixture in the set.

Fix: one synthesized `ca99:amd64` — the only input shape that separates the two prefixes.

**Generalisable:** before trusting a fixture count, ask *what distinctions does this set
actually make?* N fixtures that vary along an axis the assertion does not read are one
fixture. This is the same root as "fixture-space cardinality" — count the SHAPES the set
instantiates, never the rows.

## 3. Closing ABSENT leaves EMPTY open

The gate's cardinality loop counted lines matching the **key** and never required a
**value**, so `RUNG2_VAR_DIVERGENCE=` counted as exactly 1. Divergence came back empty,
`read -ra` yielded zero tokens, the closed allowlist iterated zero times, and **the gate
RELEASED** — then printed `${divergence:-none}`, asserting a declaration of "none" that
nobody made.

The block directly above it already stated the correct property — *"declaring 'nothing
diverged' must be explicit, never inferred from silence"* — and its own fix had closed
**absent** while leaving **empty** open. Whitespace-only is the same silence with extra
bytes, and the upstream `--divergence` validated with `-z` only, so `$'\n'` reached the gate.

**Generalisable:** for any "must be declared" check, enumerate absent / empty /
whitespace-only / present-but-unparseable as four distinct states. A key-presence count
answers none of the last three. And drop `:-default` on the *release* message: a default
there lets the guard assert a value that was never declared.

## 4. An internal-consistency assertion passes whatever the caller binds

Once the Doppler config name became a template variable, the template is internally
consistent **no matter what the caller passes** — so A20's "every `doppler run` names the
same interpolation" could no longer catch the failure it existed for. That failure (#6982 W0)
is a token scoped to a *different* config than the one named: `doppler run` exits 1 before
the LUKS heredoc, `set -euo pipefail` runs zero times, and the host boots dark with sshd up.

Fix: split it. A20 keeps the internal-consistency claim; **A20b asserts the production caller
binds the variable to the config the boot service token is actually scoped to**, extracted by
shape from both files rather than pinned to a literal.

**Generalisable:** parameterising a value moves the risk from *the template* to *the
binding*. An assertion that survives the parameterisation unchanged has usually stopped
testing the thing it was written for — check whether it still discriminates, and add the
caller-side arm if not.

## Key insight

All four are the same failure with different masks: **the assertion and the thing it claims
to constrain had drifted apart, and nothing measured the gap.** In each case the guard's own
comment stated the stronger property (four members "stop" a prefix widening; divergence "must
be explicit"; every invocation "names the same" config) and the code delivered a weaker one.

The mechanical gate that catches all four is the same: **name a mutation that satisfies the
assertion while violating the property.** If you cannot, the assertion is at least as strong
as its claim. If you can — and in all four cases it was a one-token edit — the comment is
documentation of an intent the code does not implement.

## Tags
category: test-failures
module: CI
