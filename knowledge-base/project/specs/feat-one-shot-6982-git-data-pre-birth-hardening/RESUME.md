# Resume prompt — #6982 git-data pre-birth hardening

Paste everything below the line into a fresh session.

---

Continue #6982 (git-data pre-birth hardening). Do **not** start over — 24 commits are on the
branch and pushed. Work in the existing worktree:

```
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6982-git-data-pre-birth-hardening
export TMPDIR=/var/tmp          # /tmp is a 4 GB tmpfs a sibling session fills; the
                                # budget/render scripts fail with ENOSPC without this
```

- Branch `feat-one-shot-6982-git-data-pre-birth-hardening`, PR **#7015** (still draft), clean
  tree, all commits pushed. Rebased onto `origin/main` 2026-07-28.
- Plan: `knowledge-base/project/plans/2026-07-27-chore-git-data-pre-birth-hardening-plan.md`
- Trackers: **#7025** (banner-clear, gated on rung-2 evidence), **#7026** (deferred
  capabilities), **#7027** (ADR-143 phantom `cx22`), **#7048** (NEW — Art. 30 register GFM
  truncation, pre-existing, filed not fixed).

## State — the 18-item review queue is CLEARED

All 18 items plus one found during the work are done and committed. Everything below was
mutation-proven against the real artifact, not just re-run green.

| Suite | Before | After |
|---|---|---|
| `git-data-emit.test.sh` | 21 | **42** |
| `git-data-luks.test.sh` | 58 | **62** |
| `git-data-runcmd-rehearsal.test.sh` | 9 | **12** |
| `test-git-data-host-birth-gate.sh` | 80 | **93** |
| `credential-persist-home-guard.test.sh` | 34 | **35** |

`user_data` unchanged at **31,904 / 32,768 (864 B headroom)** — no queue item cost a byte.
`tsc --noEmit` clean. `lint-infra-no-human-steps` and `lint-encryption-posture` PASS.

## What the rebase forced (do not lose this context)

Rebasing pulled in **#7003**, which landed two operator decisions after this branch's code was
written. Both needed an answer and neither existed:

1. **ADR-149 item 5 / DC-3** mandates single-sourcing `GIT_DATA_SSH_HOST` from
   `hcloud_server_network.git_data.ip`. That is **not satisfiable**: the NIC depends on
   `hcloud_server.git_data`, so a secret reading its `ip` cannot be planned or applied while the
   host is absent — which is the entire window Residual 2 requires the secret to exist in.
   Shipped as `local.git_data_private_ip` (one literal, one source, both consumers read it, no
   edge to an unborn server) and recorded as **DC-5** in `decision-challenges.md`.
   **→ This is the one thing awaiting an operator answer.** See the PR body.
2. **ADR-149 item 7 / DC-2** conditions the interlock rewrite on #6982 defining the emitter as a
   Terraform resource. It does not — the emitter is a file inside `user_data`; git-data has no
   bake path. The item's own closing clause required that outcome be recorded before item 8
   clears; it now is. Checklist renumbered (banner-clear 7→8, sizing 8→9) and cross-references
   swept.

## Also found and fixed while in there

- **A fail-open in `credential-persist-home-guard.test.sh`** (main's, not this branch's): every
  directive regex is line-anchored, so a multi-line `ExecStart` is truncated at the backslash and
  a `docker login` on a continuation line was invisible to the whole scan. `mk_unit` now joins
  systemd continuations; M16 pins it.
- **#7048** — the Art. 30 register silently discards **12,531 chars** of Art. 32 TOM evidence
  across **5** rows (the handoff said 2; re-derived header-relative). Pre-existing → filed.
- **`lint-bot-statuses` was RED on this PR** with 6 findings, 5 of them predating this session.
  All were decision-record/plan prose (two literally say an operator step is *impossible* here);
  wrapped in `lint-infra-ignore` regions at whole-table granularity so the GFM tables survive.

## The one open verification — READ THIS BEFORE RE-RUNNING THE GATE

`run-registered-suites.sh` has reported **77/78 with exactly one RED on every run, and a
DIFFERENT suite each time**: `soleur-host-bootstrap-observability`, then
`infra-config-handler-bootstrap`, then `cloud-init-inngest-bootstrap` (that last one under
`JOBS=1`). **Every one of them passes in isolation** (100/100, 33/33, 80/80 twice).

Cause, confirmed not assumed: a **sibling session** is running the same runner concurrently from
worktree `feat-one-shot-6997-7002-7024-gate-preamble-actionlint-sigpipe` (`readlink
/proc/<pid>/cwd`). Two runs were already active before mine started.

Before treating any RED as a regression: `pgrep -fa run-registered-suites.sh`, resolve each PID's
worktree, and wait for a genuinely quiet machine. **Do not `pkill -f run-registered-suites.sh`** —
the pattern matches the invoking shell (exit 144) *and* kills the sibling's run. I did this once
by accident; do not repeat it.

Independent corroboration that the branch is fine: `gh pr checks 7015` shows
`infra-validate-required`, `validate (apps/web-platform/infra)` and `plan
(apps/web-platform/infra)` all **pass**, and every suite this PR touches is green (table above).

## Remaining before ready

- [ ] One clean `run-registered-suites.sh` on a quiet machine (the only open item).
- [ ] AC walk: 1, 4, 5, 6, 8, 9, 10, 12, 13, 14, 16, 20 verified this session. **AC7** (`terraform
      plan` per-merge shows zero git-data creates) needs credentials — not run locally.
- [ ] `/soleur:review` → `/soleur:ship`. Ship must verify `Closes #6982` is the only close-keyword
      ref and that #7025 is linked.

## Rung 2 is deliberately NOT done

W12 reached rung 1 (container harness) only. Rung 2 — booting the rendered template on a
throwaway host outside the `hcloud_server.git_data` address — is a real Hetzner write outside this
PR's scope fence. Carried as **#7025's own precondition**, not inherited as a pass. The
DO-NOT-DISPATCH banner stays up.

**Note the interlock itself now RELEASES** (`git_data_birth_readiness_gate … → rc=0, 2 non-comment
`${sentry_dsn}` interpolations`). Dispatch is held by the runbook banner, not by the gate — every
"INTERLOCKED" claim in the workflow/runbook/gate was corrected to say so.

## Gotchas that cost time — do not rediscover

- **`user_data` is a hard 32,768-byte gate and comments count.** Run
  `bash apps/web-platform/infra/git-data-userdata-budget.sh` after every edit to
  `cloud-init-git-data.yml`, `git-data-bootstrap.sh`, `git-data-gc.sh` or the units. Measure with
  Terraform's own `base64gzip`, never `gzip -9`.
- **Terraform's template scanner does not skip YAML comments.** A `%{` or live `${…}` inside a `#`
  comment breaks the render.
- **A body-grep sees comments too.** Two guards written THIS session were vacuous on first draft
  for exactly this: `grep -F 'set -e'` matched the prose two lines above the code, and a `[^\n]`-
  style anchor missed `set -exuo`. Anchor on whole lines, strip comments, and mutation-prove.
- **Existence checks cannot see one of N deleted.** The rc guard appears at three trap sites;
  deleting one left an existence-based guard green. Use counts with the design's N.
- **`betterstack-query.sh` Mode 1** takes raw SQL as the first positional and rejects `--since`
  (exit 64). `remote($BS_TABLE)` takes no `primary` argument.
- **Never capture stderr into a match buffer** when the tool echoes the failing query back.
- **A mutation that does not land is a null result wearing a pass's clothes.** Assert it landed
  (`diff -q` against a pristine backup) and restore-verify after.
- Synthesized **secret-shaped** fixtures trip GitHub Push Protection; split across concatenation.
- `git-data-luks.test.sh` runs under `set -o pipefail`: `grep -c … | grep -q '^0$'` reports the
  opposite of the truth on a clean file.
- **CWD drifts between Bash calls.** A `cd apps/web-platform` persisted and made the next three
  commands read nonexistent paths. Chain `cd <abs> && …` in one call.

## Definition of done

One clean registered-suite run, then `/soleur:review` → `/soleur:ship`.
