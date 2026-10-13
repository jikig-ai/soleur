# Resume prompt — #6982 git-data pre-birth hardening

Paste everything below the line into a fresh session.

---

Continue #6982 (git-data pre-birth hardening). Do **not** start over — 28 commits are on the
branch and pushed. Work in the existing worktree:

```
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6982-git-data-pre-birth-hardening
export TMPDIR=/var/tmp          # /tmp is a 4 GB tmpfs a sibling session fills
```

- Branch `feat-one-shot-6982-git-data-pre-birth-hardening`, PR **#7015** (draft), clean tree.
- Rebased onto `origin/main` 2026-07-28. A **13-agent review ran 2026-07-29**; its P1s are fixed
  and pushed. The queue below is what that review left open.
- Trackers: **#7025** (banner-clear, gated on rung-2 evidence), **#7026** (deferred capabilities),
  **#7027** (ADR-143 phantom `cx22`), **#7048** (Art. 30 GFM truncation — **has a wrong count, see
  A4**).

## COMMIT EACH VERIFIED UNIT IMMEDIATELY — this bit me

A worktree sync restored tracked files to HEAD mid-session and silently reverted every
verified-but-uncommitted review fix. It was caught only because `git log -S 'FORMAT JSONEachRow'`
came back empty against a *clean* tree. Where an edit must be followed by a commit, do **both in
one Bash call**. Do not batch a round of fixes and commit at the end.

## Current state (all verified this session)

| Gate | Result |
|---|---|
| `run-registered-suites.sh` | **78/78, rc=0** (on a quiet machine — see contention note) |
| `git-data-emit` / `luks` / `rehearsal` / birth-gate / cred-guard | 42 / 62 / 12 / 93 / 35, all 0 failed |
| `tsc --noEmit`, `lint-infra-no-human-steps`, `lint-encryption-posture` | clean |
| `user_data` | **20,456 / 32,768 — 12,312 B headroom** (ADR-152 render-strip; was 32,128/640 before it) |

**Suite contention:** three earlier gate runs each reddened a *different* suite that passed in
isolation, because a sibling session was running the same runner from another worktree. Before
treating any RED as a regression: `pgrep -fa run-registered-suites.sh`, resolve each PID via
`readlink /proc/<pid>/cwd`, wait for quiet. **Never `pkill -f run-registered-suites.sh`** — the
pattern matches the invoking shell AND kills the sibling's run. I did that by accident once.

## The queue — A-items first, they are the ones that bite users

Each item names its source. **Treat every agent-reported measurement as a claim to re-derive**,
not a fact — the four marked ✅ are ones I verified personally.

### A1 — `receive.unpackLimit` unset ⇒ the volume ENOSPCs on INODES at ~58 % byte usage
`performance-oracle`, measured on a real bare clone: 79,411 objects = 700 MB / 79,411 inodes loose
vs 123 MiB / 2 inodes packed (**39,705× inode amplification**). `transfer.unpackLimit` defaults to
100 and a typical session push is ~97 objects, so **the modal push lands entirely loose** — and
`gc.auto=0` means nothing packs it until Sunday. `mkfs` gives the 10 GB volume 655,360 inodes;
~312 workspaces × 3 sessions/day exhausts them at df-bytes ≈ 58 %, while `disk_pct` (the only
metric emitted) reads 58 and looks healthy.
**Fix:** `git config --system receive.unpackLimit 1` in `git-data-bootstrap.sh` §6c **and** its
re-assert list; add `--output=ipcent` to the two `df` calls (`git-data-gc.sh`,
`git-data-bootstrap.sh`). Costs `user_data` bytes — check the budget.

### A2 — the failure reporter's documented fallback is unreachable ✅
`pattern-recognition-specialist`; **I verified the mechanism empirically**:
`dash -c '. /nonexistent || echo FALLBACK; echo SURVIVED'` prints **nothing**, rc=2 — the shell
dies at the failed `.` (a POSIX *special builtin*), so neither the `||` arm nor anything after it
runs. bash prints both. `git-data-gc-failure.service` and `git-data-gc.service` both open with
`/bin/sh -c 'set -a; . /etc/default/git-data-doppler; set +a; …'`, and `/bin/sh` is dash. So if
that env file is missing or unreadable — mode 0600, written in `runcmd` *after* stages that can
abort — the reporter dies silently, defeating its own comment ("*if `doppler run` is itself the
broken thing, the Sentry half still fires from the BAKED DSN*").
**Fix:** `EnvironmentFile=-/etc/default/git-data-doppler` on both units (the file is already
`KEY=VALUE`; the `-` tolerates absence), dropping `set -a; . …; set +a`. Precedents:
`luks-monitor.service`, `cron-egress-resolve.service`, `web-git-data-probe.service`.

### A3 — the birth is now held ONLY by prose
`user-impact-reviewer` + `agent-native-reviewer`. `git_data_birth_readiness_gate` returns **0**;
`grep -rn 7025 .github/ tests/ apps/ plugins/` finds comments and zero executable checks. ADR-149's
own Alternatives table rejects this posture: *"a capability held only by prose is held until the
first person who reads the runbook and not the plan."*
**Fix:** add a rehearsal-evidence sentinel to the existing gate (~5 lines) — require a tracked
evidence file, or `confirm=BIRTH-GIT-DATA-REHEARSED`. Plan R26 already flagged multi-sentinel
hardening.

### A4 — correct #7048, which I filed with a wrong count ✅
I said 5 rows / 12,531 chars. It is **2 rows / 4,005 chars** (lines 230 and 324). Three of the five
rows already escape the pipe as `\|` and lose nothing; my scanner counted raw pipes without escape
awareness. Re-derive with a `(?<!\\)\|` split before editing the issue.

### B — P2s, roughly by value

| # | Finding | Source |
|---|---|---|
| B1 | **B1 byte-identity maps by basename and `continue`s on a miss**, with a *count* floor of exactly 9. A payload whose basename is not a file in `infra/` ships unchecked; a duplicate basename can mask a dropped member (measured fail-open). Fix: assert the delivered→source **set**, both directions, like the birth-gate drift guard. | data-integrity, test-design |
| B2 | **A28a/A28b scan only the template**, so `git-data-bootstrap.sh` — the *second* `GIT_DATA_LUKS_KEY` site, whose failures land in the trap where `_devalue` is inert — is outside the quantifier. Measured: `set -exuo` there leaves 62/62 green. Fix: scan the render, or the template + every `file()`-interpolated script. | test-design, security |
| B3 | **`CONT_RE` over-merge** — my join fires on *any* trailing backslash, so a non-continuation backslash swallows the next `Exec*=`. Reproduced: a `docker login` becomes invisible. Fix: refuse to join when the next line matches `^\s*[A-Z][A-Za-z]*=`, or union joined+unjoined. | security (F3) |
| B4 | `systemd-analyze verify` step passes when the binary is absent (`\|\| true` + a grep that misses `command not found`). | pattern-recognition |
| B5 | Rehearsal + emit **skip guards `exit 0` before the cardinality floor** — a runner without docker/terraform turns a runtime gate into a green no-op. Fix: hard-fail the skip under `CI=true`. | test-design, pattern-recognition |
| B6 | The **`boot_complete` contract is replicated across 5 sites** (producer, workflow reader, probe, fixture) with no parity test. Dropping `hooks_path=yes` stays green and surfaces during a real birth. | pattern-recognition |
| B7 | `systemctl enable --now git-data-gc.timer \|\| true` — silent fallback, no emit, no `boot_complete` field. The sole defence against unbounded growth can fail to arm while the host reports healthy. | pattern-recognition |
| B8 | gc: a `MemoryMax`/`TimeoutStartSec` kill destroys the loop **and** the summary emit; every repo after the offender in glob order is silently unmaintained. Fix: per-repo `timeout`, emit from a `trap … TERM EXIT`. | performance |
| B9 | gc: `--threads=1` is **not** re-passed to `repack`, though the bootstrap names it "the actual OOM path" and the script re-passes the *less* important `--window-memory`. | performance |
| B10 | gc: the lock-open and `flock -n` paths `exit 0` with no emit — the anti-pattern the same file argues against one stanza earlier. | performance, user-impact |
| B11 | `receive.maxInputSize` unset — one client can fill the shared 10 GB volume. | performance |
| B12 | Timer is **weekly**; with `gc.auto=0` it is the only thing that ever packs, and `--unpack-unreachable=2.weeks.ago` maximises loosened-object residency. Daily costs nothing. | performance |
| B13 | The shed returns bare `void`; both callers `await` inside `catch {}` and cannot distinguish a shed from a completed push. | data-integrity |
| B14 | `recover-userid-from-pino-stdout.md` filters on `grep -F 'userIdHash'`, which matches neither new hashed field. | data-integrity |
| B15 | `encryption-posture-ledger.json` evidence cites `cloud-init-git-data.yml:170,173,180` — now inside the emitter. Re-anchor on content (`cq-cite-content-anchor-not-line-number`). | data-integrity |
| B16 | `mkfs.ext4 -O quota,project` has **zero assertions**; dropping it later is migration-forcing. | data-integrity |
| B17 | Stale counts/ordinals: `ADR-068:1382` "checklist item (8)" → **9**; "seven-item checklist" (runbook :30, session-state :20, plan ×2) → **nine**; plan `:494`/`:1437` item 8 → 9; emit floor 40 → **44** (42 was itself stale: B6's parity arm and A1's inode_pct landed after); plan T10 (`SOLEUR_GIT_DATA_DISK`) and T14 (exit 1 → **2**) contradict what shipped. | code-quality, architecture |

### C — P3s
`_expand`/`is_sandboxed` still line-anchored (pre-existing); `$CAPTURE` dereferenced before
assignment at rehearsal D1; `$BODY` stale at the AC30 encryption-claim check; `preamble.sh`
extracted but unread (B2 reads `runcmd-all.sh`); `else pass; pass` manufactures floor credit;
`pack.packSizeLimit` bounds nothing it is grouped under; stale `.tmp-*.pack` never swept; shed
Sentry event carries no correlator; the plan's Phase 0.3/1.2 prescribe forms its own ACs now
disqualify.

## Ship gate

`Closes #6982` must be the only close-keyword ref in the PR body, and #7025 must be linked. The
PR body's evidence table still cites "21/21" and "7/7" — **now 42 and 12**; fix before `gh pr ready`.

## Rung 2 stays out of scope

W12 reached rung 1 (container harness) only. Rung 2 — booting the rendered template on a throwaway
host — is a real Hetzner write outside this PR's fence, carried as **#7025's own precondition**.
The DO-NOT-DISPATCH banner stays up.

## Gotchas — do not rediscover

- **`user_data` is a hard 32,768 B gate and comments count.** 12,312 B of headroom (ADR-152 strips comments at render time; it was 640 B before that). Run
  `bash apps/web-platform/infra/git-data-userdata-budget.sh` after every edit to
  `cloud-init-git-data.yml`, `git-data-bootstrap.sh`, `git-data-gc.sh` or the units. Measure with
  Terraform's own `base64gzip` — `gzip -9` overstates headroom by ~34 %. **A1 and B7 both add bytes; ADR-152's render-strip is
  what made them fit.**
- **Terraform's template scanner does not skip YAML comments** — a `%{` or live `${…}` in a `#`
  comment breaks the render.
- **A body-grep sees comments too.** Three guards this branch shipped were vacuous on first draft
  for exactly that. Anchor on whole lines, strip comments, mutation-prove.
- **Existence checks cannot see one of N deleted** — derive minimums from the artifact.
- **`betterstack-query.sh` Mode 1 passes SQL verbatim**: no `FORMAT JSONEachRow` appended, output
  is TSV. `remote()` takes no `primary` argument. `--since` makes `$1` a flag → exit 64.
- **`SENTRY_AUTH_TOKEN` 403s on `/issues/`** — use `SENTRY_ISSUE_RO_TOKEN`
  (`scripts/sentry-issue.sh:5-11`).
- **A mutation that does not land is a null result wearing a pass's clothes.** Assert it landed
  against a pristine backup; restore-verify after.
- **CWD drifts between Bash calls** — chain `cd <abs> && …` in one call.

## Definition of done

A-items fixed, B-items fixed or explicitly scoped out with a CONCUR'd criterion, budget under cap,
`run-registered-suites.sh` green on a quiet machine, then `/soleur:review` (delta only) → `/soleur:ship`.
