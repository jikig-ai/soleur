---
title: "likec4 export/validate exit 0 on broken sources — gate on the diagnostic stream, not just element-count"
date: 2026-06-18
category: best-practices
tags: [likec4, c4, cli, validation, exit-code, drift-guard, lefthook, ci]
module: knowledge-base/engineering/architecture/diagrams
related:
  - knowledge-base/project/learnings/best-practices/2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md
---

# likec4 exits 0 on a broken `.c4` source — element-count alone is not a sufficient clobber guard

## Problem

Building the C4 auto-regen sync gate (`scripts/regenerate-c4-model.sh` + a lefthook
pre-commit hook + a CI freshness test), the plan's clobber-protection AC assumed a
broken `.c4` source would produce an **empty** model that an
`(.elements | length) > 0` check catches — the failure mode documented in
[[2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact]] (#4966:
unresolved reference / missing `spec.c4` → zero elements, exit 0).

That assumption is INCOMPLETE. likec4@1.50.0 has (at least) **two** distinct
source-fault modes, and both exit 0:

1. **Unresolved reference / missing spec** → an EMPTY-elements model. Caught by the
   element-count check. (The #4966 case.)
2. **Trailing syntax error** (e.g. appending `broken = boguskind "x" {}`) → likec4
   *recovers* by dropping the bad fragment, prints `Invalid <file>` + `    Line N:
   Expecting token …` to its output, **exits 0**, and STILL emits the full set of
   valid elements (45/45 in our case). The element-count check passes — so a
   `(.elements | length) > 0`-only guard silently publishes a model that is missing
   whatever the broken fragment was meant to add.

Worse: `likec4 validate .` **also exits 0** on the same broken source. So the exit
code is useless for fault detection on BOTH `export json` and `validate` — the only
reliable signal is the textual diagnostic.

## Solution

Gate the publish on BOTH signals, not just element-count:

```bash
# Capture the render's combined output, then refuse to publish if EITHER:
#   (a) the diagnostic stream carries a validation error, OR
#   (b) the model is empty.
DIAG_RE='^Invalid |Could not resolve|^[[:space:]]+Line [0-9]+:'
if grep -qE "$DIAG_RE" "$RENDER_LOG"; then
  echo "ERROR: likec4 reported a source validation error — refusing to publish" >&2
  exit 1
fi
if ! jq -e '(.elements | length) > 0' "$rendered.json" >/dev/null 2>&1; then
  echo "ERROR: likec4 produced an empty/degenerate model" >&2
  exit 1
fi
```

The element-count check is the **version-robust backstop** (catches mode 1 even if
likec4's diagnostic wording drifts across releases). The diagnostic grep catches mode
2, which element-count structurally cannot. They are complementary, not redundant.

**Anchor the diagnostic markers** so they cannot false-FAIL on benign output: likec4
echoes the absolute workspace path (`workspace: /abs/path …`), so `^Invalid ` (line
start) and the indented `^[[:space:]]+Line [0-9]+:` (the diagnostic is indented
`    Line 274:`) keep the markers off the path line. A bare unanchored `Line [0-9]+:`
would false-FAIL on a checkout dir whose path literally contains "Line 5:".

## Key Insight

`exit-0-is-not-proof` (the #4966 learning) generalizes further than "validate the
artifact is non-empty": a CLI that **recovers from partial errors** can emit a
non-empty-but-wrong artifact with exit 0 AND a non-empty diagnostic stream. When the
tool offers no honest exit code (likec4 validate/export both exit 0 on faults), the
robust guard reads the *diagnostic text* in addition to validating artifact shape.
Note the runtime path `apps/web-platform/server/c4-render.ts` deliberately gates on
element-count ONLY and warns against stderr-substring matching — that is correct for
the empty-model case it handles (#4966), but it does not cover the syntax-recovery
case; a regen primitive that fronts a commit/CI gate needs both.

## Session Errors

- **AC2 design assumption incomplete (recurring).** Plan assumed broken `.c4` → empty
  model. Reality: likec4 recovers from a trailing syntax error and emits a non-empty
  model with exit 0. Recovery: added the diagnostic-grep gate beside element-count.
  Prevention: when a plan's clobber-protection AC relies on a tool's failure shape,
  empirically probe EVERY fault mode (syntax error, unresolved ref, empty source)
  before trusting one signal — exit code + one artifact predicate is rarely complete
  for a recovery-capable CLI.
- **`likec4 validate` also exits 0 on broken source (recurring).** Prevention: never
  gate likec4 correctness on its exit code; read the diagnostic stream.
- **lefthook `--commands` flag wrong (one-off).** lefthook 2.1.6 uses `--command`
  (singular) to scope `lefthook run <hook>`. Prevention: `lefthook run --help`.
- **`git push` rejected post-rebase (one-off).** After rebasing the feature branch
  onto origin/main, the remote branch (draft-PR init commit) diverged; resolved with
  `--force-with-lease`. Expected for an own post-rebase feature branch.
- **AC4 verification grepped the wrong stream (one-off).** lefthook routes a hook
  command's stdout/stderr into its own formatted stdout block; the advisory NOTE was
  present there, not in the captured stderr. Prevention: capture both streams when
  asserting on lefthook command output.
- **INDEX.md pre-existing drift (recurring, different subsystem — NOT fixed here).**
  Running `generate-kb-index.sh` showed `Total files: 3773 → 5619` (+1846) against
  the committed INDEX.md, with no untracked `.md` files — main's committed INDEX.md
  genuinely undercounts. Out of scope for this feature (kb-index subsystem, pre-existing,
  not caused by this PR); reverted the regeneration. Noted, not filed: uncertain
  actionability and filing would net-grow the backlog for a condition this PR did not
  introduce. Self-heals on the next KB-md commit that triggers the generate-kb-index hook.
- **Review false-positive (one-off).** code-quality flagged a "dead learning citation"
  that exists at `learnings/best-practices/`; refuted by git-history-analyzer +
  test-design-reviewer (cross-reconcile rule). Prevention: a single-agent HIGH/P2
  contradicted by orthogonal agents is the modal false-positive — verify before applying.
