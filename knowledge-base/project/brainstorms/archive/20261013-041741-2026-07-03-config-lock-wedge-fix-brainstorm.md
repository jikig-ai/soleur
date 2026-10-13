---
date: 2026-07-03
topic: config.lock worktree-creation wedge — targeted fix
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 5912
branch: feat-config-lock-wedge-fix
pr: 5932
---

# Brainstorm: config.lock worktree-creation wedge — targeted fix (#5912)

## What We're Building

The deferred root-cause fix for the Concierge agent-sandbox wedge tracked by #5912.
A real wedged session finally emitted the instrumented sentinel PR #5907 was built
to capture (recorded on #5912), unblocking this work:

```
SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=other errno=none reason=non-regular-lock
Cannot create worktree — wedged on an unremovable git lock
```

**Root cause (confirmed):** `.git/config.lock` in the sandbox is a **non-regular
file — a character device** (sweep classifies `type=other`), an artifact of the
sandbox filesystem/masking layer, write/remove-protected. It is NOT a stale git
lock (a genuine one is always a regular file, created via `open(O_CREAT|O_EXCL)`).
`ensure_bare_config()` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
writes shared `.git/config` on every worktree-create path; each `git config` write
tries to create `.git/config.lock` via `O_CREAT|O_EXCL`, hits `EEXIST` against the
pre-existing device node → permanent worktree-creation wedge, no in-sandbox self-heal.

**Fix shape:** a generalized `atomic_git_config <file> <args…>` helper that composes
read-first idempotence with a gated lockless writer, applied to *every* config
mutation across both wedge surfaces.

## Why This Approach

The three originally-scoped candidates are not competing options — they **compose**:

- **(2) Read-first idempotence** — necessary but INSUFFICIENT alone. A fresh
  `git clone --bare` ships `extensions.worktreeConfig` unset and `core.bare=true`
  in shared config, so the first worktree-create genuinely needs the write; read-first
  skips nothing on a fresh clone. Value: a zero-write fast path for the common re-run.
- **(1) Lockless writer** — the load-bearing fix. Redirect **git's own** config
  writer to a same-directory temp file (`.git/config.soleur-tmp.$$`, whose `.lock`
  sibling is a clean, distinct path from the masked `config.lock`), then
  atomic-`rename` over the target. Keeps git's INI correctness; never touches the
  char-device lock.
- **(3) Platform mount fix** — the only truly durable fix, but lives in Concierge
  sandbox infra (not this repo) and has no in-session self-heal → cannot be primary.
  Filed as an upstream companion ask.

Chosen scope: **(2)+(1-gated) repo-side helper + companion platform issue for (3).**

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Fix mechanism | `atomic_git_config` helper: read-first, then gated lockless | (2) fast-paths common case; (1) survives the wedge; git-native INI correctness |
| Lockless technique | `cp -p` copy → `git config --file <temp>` → atomic `mv -f` (same dir) | `cp -p` preserves perms/owner (plain `cp` perm-drifts config); same-dir rename is atomic (cross-fs `/tmp` would be copy+unlink, non-atomic) |
| Gating | Branch on sweep's non-regular-lock signal: clean → native `git config`; wedged → temp-rename | Preserves flock serialization for healthy concurrent writers; avoids degrading every user's concurrency to win a bit-rot argument |
| Coverage | ALL mutations on BOTH `config` (290-291, 296, 303) AND `config.worktree` (311) | 311 is a SECOND wedge surface (`config.worktree.lock`); a 290-291-only fix leaves it wedged |
| Bit-rot guard | CI fixture forcing a char-device (or bind-mount) at `config.lock` to exercise the fallback branch | Rare-branch code rots without a test that reaches it |
| Symlink guard | Guard symlinked `.git/config` before `mv -f` clobbers the symlink with a regular file | Rare on bare repos, cheap to guard |
| Platform fix (3) | File as separate upstream Concierge-sandbox issue | Only durable fix, but out-of-repo + no self-heal; keep repo-side fix primary |

## Open Questions

1. **[Sharpest — plan-phase assumption]** Is the sandbox masking a **single-path**
   artifact (literal `.git/config.lock` only) or a **glob** over any `*.lock`? The
   entire repo-side fix hinges on single-path: if globbed, `config.soleur-tmp.$$.lock`
   is also a char-device and the fix fails identically. **Evidence it is single-path:**
   the wedged session's sweep scans both `config.lock` and `config.worktree.lock`, but
   the forensic emitted `UNREMOVABLE` for `config.lock` ONLY — a glob would have tripped
   `config.worktree.lock` too. Not conclusive (stream was summarized). Confirm against
   the next fuller forensic or by probing the sandbox mount config if reachable.
2. Parallel-session safety: last-rename-wins can lose an edit, but all writers converge
   to the same fixed target state (idempotent) → a lost update is redundant, not
   corrupting. The copy→edit→rename window is wider than git's in-place lock, so an
   *unrelated* concurrent config writer is marginally more clobberable — acceptable under
   the existing age-guard-not-flock posture; note in plan.
3. `core.fsync` durability: no dir-fsync on the rename — acceptable for idempotent
   metadata (not user data).

## User-Brand Impact

- **Artifact:** `worktree-manager.sh` worktree-creation path (the surface every
  autonomous Concierge `/soleur:go` and `/soleur:one-shot` session depends on).
- **Vector:** a wedged session presents as the product being silently broken — the
  agent cannot create a worktree, cannot start any work, with no in-session self-heal;
  a single operator hitting this loses the entire session with no recourse.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO). Product/Legal not materially engaged — pure
developer-tooling git-plumbing fix with no user-data or content surface.

### Engineering

**Summary:** The temp-copy + same-dir atomic-rename mechanism faithfully mimics git's
own write-then-rename and is correct. Corrections folded into Key Decisions: use `cp -p`
(perms/owner preservation), generalize into one helper covering all mutations on both
lock surfaces, guard symlinked config, gate the lockless path on the sweep's existing
non-regular-lock signal (not unconditional), and add a CI char-device fixture to
exercise the fallback. Read-first is necessary but insufficient — fresh clones need the
write. Sharpest risk: confirm single-path vs glob masking. Keep (3) as upstream ask.
