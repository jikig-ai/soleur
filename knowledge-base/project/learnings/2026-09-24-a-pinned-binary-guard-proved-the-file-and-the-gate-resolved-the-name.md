---
title: "A pinned-binary guard proved the file; the gate resolved the name"
date: 2026-09-24
category: integration-issues
tags: [ci, supply-chain, vendor-cli, guard-contract, grok, review]
issue: 8615
pr: 8756
---

# Learning: a pinned-binary guard proved the file; the gate resolved the name

## Problem

#8615 pinned the Grok CLI in the REQUIRED `grok-fidelity` job: download
`grok-${GROK_PIN}-linux-x86_64`, `sha256sum -c` before install, assert
`grok --version` == pin, exit 3 on drift. A 9-row local mutation harness (the
install step's real `run:` body, extracted from `ci.yml` by PyYAML and run under
`bash -e`) was green, with both neutered-harness controls red.

The structural-enumeration review seat then showed the guard's ASSEMBLY did not
equal its PROPERTY. The install step proves the bytes at `$HOME/.grok/bin/grok`;
the gate step and its bun tests resolve `grok` BY NAME (bash `command -v`,
`Bun.spawnSync(["which","grok"])` on the startup env, Bun shell `$` on the live
`process.env.PATH`, and `bun run` prepending `node_modules/.bin`). Nothing
asserted those resolutions reached the pinned file, and the post-gate digest
re-check hashed one path AFTER the gate had already executed whatever it found.
The harness could not see this: it only ever ran the install step body, whose
own `export PATH=` guarantees the right answer.

## Solution

- The gate step refuses with `resolved-elsewhere:<path>` unless
  `command -v grok` is the pinned file; the post-gate step re-checks resolution,
  digest AND `grok --version`.
- Download loops over x.ai and the vendor installer's own GCS base with the
  sha256 check inside the loop (same etag measured on both), so a pruned or
  unreachable primary no longer reds every PR on a required check.
- CR/LF stripped from `--version` text before it reaches `::error::`.
- ADR-245 amendment narrowed from "conforms" to "conforms to the pin bullet";
  accepted risk recorded (a pruned pinned artifact reds every PR and holds the
  deploy via `ci_not_green`).
- Harness grew to 17 rows including a decoy `grok` earlier on the gate step's
  PATH, primary-source 404 served by the fallback, and a multi-line annotation
  row proven to red without the strip.

## Key Insight

A guard over a binary must pin the NAME the consumer resolves, not only the
bytes at the path the installer wrote, and a harness that runs only the
installer body is structurally blind to every resolution that happens in a later
step. Ask per guard: which steps execute this, how do they find it, and does
any assertion sit in THOSE steps?

## Session Errors

1. **(planning, forwarded) Misread `grok-fidelity-gate.sh` as fail-open; mutation row 6 first written as "delete the comparison"; curl budget first sized past the job timeout.** Recovery: plan review + deepen corrected all three. **Prevention:** existing plan-review/deepen gates caught them; no new rule.
2. **Live `grok-inspect-contract` test fails locally (`.grok/commands/*` not user-invocable) with BOTH binary-only and installer installs, scratch HOME, XDG unset, while CI with the same 1.0.41 passes.** Recovery: A/B against the installer isolated it as local-environment, not the pin; relied on CI's live arm. Root cause not identified (symlinks intact; `projectTrusted` read false despite a trust entry). **Prevention:** before attributing a live-vendor failure to a change, A/B the old install path in the same environment; done here, and it prevented a false regression.
3. **`rm -rf` over a glob was denied by the protected-location hook.** Recovery: enumerated matches and removed them by explicit path. **Prevention:** hook worked as designed.
4. **A self-matching process probe was denied by the self-match hook (twice: once as a command, once because the learning's own heredoc quoted the probe).** Recovery: `proc.sh list_runs`/`kill_mine`; wrote this file with the Write tool. **Prevention:** use `proc.sh` first; write prose that quotes guarded command shapes via the Write tool, not a Bash heredoc.
5. **`test-all.sh --affected` queued behind a sibling worktree holding the lock for about 2 h.** Recovery: killed own queued run and its flock waiter by cwd, ran consumer-derived targeted suites (19 shell suites, 6 bun files, 3 vitest files, workflow ratchets); CI owns the full battery per the operator's instruction. **Prevention:** run `--capacity` before launching; when a sibling holds the lock for hours, go straight to targeted suites.
6. **`lint-infra-no-human-steps.py` invoked bare reported 518 corpus findings.** Recovery: re-ran in lefthook's per-file form (0). **Prevention:** already covered by work/SKILL.md ("a guard run without the argument that bounds it"); read the runner's own invocation first.
7. **README batch edit's anchor spanned a line break; the assertion aborted the batch before any write.** Recovery: re-anchored and re-applied; `git diff --stat` confirmed the file moved. **Prevention:** `assert s.count(a)==1` did its job; always re-check `git diff --stat` after a failed batch.
8. **Guard assembly narrower than its property (the finding above) shipped past a green 9-row harness.** Recovery: review fix plus harness rows 9-14. **Prevention:** routed to plan-sharp-edges.
9. **git-history agent asserted two false facts (#8574 "does not exist"; the installer "runs grok update").** Recovery: discarded as unverified; #8574 is an open issue. **Prevention:** treat unsourced agent claims as leads; neither changed a decision.
10. **Stop hook fired on a closing "Waiting on..." line while agents ran.** Recovery: emitted an explicit stop marker. **Prevention:** when idling on background agents, close with the explicit stop marker.

## Tags
category: integration-issues
module: .github/workflows/ci.yml (grok-fidelity)
