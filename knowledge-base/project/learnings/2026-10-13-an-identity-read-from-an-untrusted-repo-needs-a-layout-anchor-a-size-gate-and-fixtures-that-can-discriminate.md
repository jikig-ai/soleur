# Learning: an identity read from an untrusted repo needs a layout anchor, a size gate, and fixtures that can discriminate

## Problem
The version banner printed nothing for an in-place plugin install (local-Folder marketplace; the hook
root is `<folder>/plugins/soleur`, with no manifest `version` and no 12-hex cache dir). The obvious fix
(walk up to `.git`, ask git for HEAD) runs git against a repository the hook does not own: its
`.git/config` is untrusted project config (see
`2026-10-12-a-global-hook-that-shells-out-inherits-the-project-it-runs-in.md`).
A side defect surfaced while restoring the maintainer's setup: `worktree-manager.sh sync-bare-files`
ran GNU `comm` without `LC_ALL=C`; under `en_US.UTF-8` it reported unsorted input and its output
deleted tracked dotfiles (including `.claude-plugin/marketplace.json`) from the bare root, so the plugin
failed to load with `cache-miss`.

## Solution
- `source=checkout` reads HEAD, the loose ref and `packed-refs` as plain files. Anchor on the layout, not
  a free walk-up: absolute root whose physical path ends `/plugins/soleur`, `<top>/.git` a directory or a
  `gitdir:` file, `<root>/.claude-plugin/plugin.json` present. A free walk reports an ambient
  `/tmp/.git` or a dotfiles-`$HOME` repo as Soleur's identity.
- Gate every read: `[[ -f && -r ]]`, a `stat` size cap before `read` (512 B small files, 4 MiB packed-refs,
  64 KiB manifest), and require the bytes consumed to equal the stat size so a NUL-spliced file is
  `unknown` on every bash version. A sparse 2 GiB HEAD took 38.8 s against a 10 s hook budget.
- Validate the ref name with a deny-list (an allow-list would hide `fix/issue-#12`), never fall through
  to `packed-refs` when a loose ref exists but is invalid, print only a 40-hex first 12.
- `LC_ALL=C comm -23` in `sync_bare_files`, with a locale regression row.
- Legal wording states what is new: a checkout already sent the release-list request under the opt-in; it
  now also sends the compare request carrying its 12-hex commit hash, same opt-in.

## Key Insight
A resolver that reads another party's repository is a parser of hostile input: pin its inputs by layout,
bound them by size before reading, and prove "never ran git" with a witness that arms real git, because a
recording stub alone makes the claim vacuous. And a fixture can agree with the code under test by
construction: the `comm` regression passed against the buggy code until the fixture held `.0-old.md`
(order-sensitive) and a kept path that the bug deletes; the empty-`commondir` mutant survived until the
fixture had a fallback ref; a hook-suite control used the same sha as the stub's tag so `current` came
back without any curl. Each row must be run against the mutation it claims to kill.

## Session Errors
1. **Maintainer's bare-root mirror lost tracked dotfiles to the `comm` locale bug (plugin `failed to load: cache-miss`)** — Recovery: additive checkout-index restore (not the buggy prune), then the one-line fix — Prevention: `LC_ALL=C` on every `comm`; sibling sites (`scripts/plugin-delivery-canary.sh`, `apps/web-platform/infra/run-registered-suites.sh`) are tracked by draft PR #10163.
2. **Locale regression row passed against the buggy code (fixture too small to be order-sensitive)** — Recovery: added `.0-old.md`, then `.zz-gone.md` so kept paths are actually deleted without the fix — Prevention: run a new regression row against the pre-fix code before trusting it.
3. **Hostile-config witness failed: the `[include]` pointed at a script git tried to parse** — Recovery: include a nonexistent `never-read.cfg` — Prevention: one-off.
4. **`co_cmp` split JSON on `:`** — Recovery: helper function — Prevention: one-off.
5. **`fb-repo-run` fixture broke on `printf … 2>/dev/null ||` fallback** — Recovery: `mkdir -p` plus `printf` — Prevention: one-off.
6. **Hook-suite `CO_SHA` equalled `STUB_SHA` (tag commit), yielding `current` without curl** — Recovery: distinct sha — Prevention: a control must use a value distinct from every stub constant it could collide with.
7. **`15.l` control hardcoded 12 hex instead of `$CO12`** — Recovery: derive from the fixture — Prevention: derive expectations from the fixture variable.
8. **Oversize packed-refs fixture via `dd count=0` did not extend the file** — Recovery: write one byte at the end (`seek` + `conv=notrunc`) — Prevention: assert the fixture's size before the row that depends on it.
9. **Mutation battery sandbox lacked `README.md`, so the control was red** — Recovery: fixed the battery build — Prevention: run the battery's unmutated control first.
10. **Review: em-space ref expectation wrong (git allows U+2003); label parity needed `${HOOK_LABEL%)}`; empty-`commondir` mutant survived** — Recovery: rows corrected, fallback ref added — Prevention: derive expectations from the reference implementation (`git check-ref-format`), not memory.
11. **`version.md` edit script failed after the slice had already removed the "Any other source" bullet** — Recovery: redone without the delete — Prevention: one-off.
12. **First CLO-ruled legal sentence was factually wrong (a checkout already sent the release-list request)** — Recovery: the verifier measured origin/main; wording corrected — Prevention: for every causal or universal claim a doc diff adds, name the command that falsifies it and run it before the ruling is applied (existing Phase 0.5 inherited-framing gate).
13. **Stop hook "unkept promise" while background work ran** — Recovery: ended with an explicit "Paused: …" sentence — Prevention: one-off.

## Tags
category: security-issues
module: plugins/soleur/scripts/plugin-version.sh, plugins/soleur/hooks/version-banner.sh, worktree-manager.sh
