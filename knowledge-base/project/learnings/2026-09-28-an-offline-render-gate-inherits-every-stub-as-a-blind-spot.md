---
title: An offline render used as a delivery gate inherits every stub as a blind spot
date: 2026-09-28
category: integration-issues
tags: [registry, dispatcher, terraform, templatefile, test-stubs]
issue: 7582
---

# Learning: an offline render gate inherits every stub as a blind spot

## Problem

`registry-host-replace-dispatch.yml` decided "did the bytes the registry host boots change?" by
comparing the comment-stripped template, so a zot digest bump (a `zot-registry.tf` local) changed
the host's `user_data` with `deliver=false`. The fix rendered the real `templatefile()` at both
SHAs with `registry-userdata-budget.sh` — and the structural-enumeration seat then showed the
render was itself a restatement: it stubbed or hand-copied the volume id, the Doppler token key,
the heartbeat URLs, the memory cap, the arch, and six `zot-registry.tf` literals, and it rebuilt
the templatefile MAP in its own fixed shape. Every stub was a path by which host bytes could change
while the render compared identical.

## Solution

- Read every `.tf` LITERAL the map consumes instead of copying it, each anchored at both ends of
  the line (a trailing `# was "x"` comment makes the read fail closed, not pick the comment's
  string); the doppler ternary matched as its exact shape.
- Compare what an offline render cannot know DIRECTLY: `registry_server_type`,
  `registry_location`, `registry_volume_size` by value; the map/wrapper, derivation locals and
  the registry resource blocks as comment-stripped, whitespace-normalized text (so `terraform fmt`
  and comments compare equal).
- Refuse, rather than deliver, when a watermark revision cannot be read (a contents-API blip must
  not destroy and recreate the sole pull path) or the head render is unmeasurable/over cap.

## Key Insight

When a gate answers "did X change?" through a model of X, enumerate what the model STUBS or
RESTATES — each is an input the gate cannot see. Compare those inputs by value or text alongside
the model, or the model's fidelity becomes the gate's blind spot.

Two harness lessons from the same PR:

- A stub whose refusals go only to stderr is swallowed by a gate that runs `gh … 2>/dev/null`; a
  wrong-ref request then falls into a fallback branch and rows pass for the wrong reason. Write
  refusals to a file the harness checks.
- A `gh` stub route matched on a SUBSTRING (`*" workflow run "*`) swallowed a verdict POST whose
  body quotes a `gh workflow run …` re-fire command. Anchor stub routes on argv POSITION.

## Session Errors

1. **G4c fixture wrong** (the arm64 arm only matters when a render input changed) — Recovery: paired it with a template edit. **Prevention:** before writing a row, name the branch condition it must satisfy and grep the gate for it.
2. **G4d asserted the wrong direction** (mutated BEFORE, expected `after -> before` text) — Recovery: fixed the expected string. **Prevention:** state which side a fixture mutates in the row comment and derive the expected text from it.
3. **`tf_literal` first version dropped the doppler ternary** via `grep -v 'local\.'` → render rc 2 — Recovery: exact-shape parse. **Prevention:** run the render and `cmp` against a pre-change render after every parser edit (done; caught it).
4. **Gate used `$RUNNER_TEMP`**, unset in the harness under `set -u` — Recovery: `mktemp`. **Prevention:** a workflow body executed by a harness should not depend on runner-only env; prefer `mktemp`.
5. **Substring stub route swallowed V13's POST** — Recovery: argv-position anchor. **Prevention:** see Key Insight.
6. **`git stash list` blocked by hook** — Recovery: `git show HEAD:<path>` copy. **Prevention:** already hook-enforced.
7. **G5c mutation assumed `re.escape` escapes spaces** — Recovery: plain `str.replace` on exact text. **Prevention:** prefer exact-text mutations with a landing assertion (the helper asserts the edit changed the file).
8. **Plan AC8 could not exercise the render** (the PR touched no render input) — Recovery: a comment-only `zot-registry.tf` edit makes the merge push render. **Prevention:** for a "live proof" AC, trace which gate arm the merge push takes.
9. **PR worktree created nested under another worktree** (worktree-manager run from inside a worktree) — Recovery: harmless. **Prevention:** run worktree-manager from the bare root.
10. **Render-stub blind spots in the first design** — Recovery: value/text compares (above). **Prevention:** the Key Insight; the structural-enumeration seat is what found it.

## Tags

category: integration-issues
module: registry-host-replace-dispatch
