# Resume prompt — #6982 git-data pre-birth hardening

Paste everything below the line into a fresh session.

---

Continue #6982 (git-data pre-birth hardening). Do **not** start over — 14 commits are
already merged into the branch and pushed. Work in the existing worktree:

```
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6982-git-data-pre-birth-hardening
export TMPDIR=/var/tmp          # /tmp is a 4 GB tmpfs and a sibling session fills it; the
                                # budget/render scripts silently fail with ENOSPC without this
```

- Branch `feat-one-shot-6982-git-data-pre-birth-hardening`, PR **#7015** (still draft), clean tree, all commits pushed. This file is the tip commit.
- **Rebase first.** The branch is 2 behind `main` and the diff touches `knowledge-base/legal/**`, which is the FAIL-HARD rebase class in `/soleur:work` Phase 0.5: `git fetch origin main && git rebase origin/main`.
- Plan: `knowledge-base/project/plans/2026-07-27-chore-git-data-pre-birth-hardening-plan.md`
- Tasks + Phase-0 evidence: `knowledge-base/project/specs/feat-one-shot-6982-git-data-pre-birth-hardening/`
- Trackers already filed: **#7025** (banner-clear, gated on rung-2 rehearsal evidence — carries the follow-through directive in its BODY), **#7026** (deferred capabilities), **#7027** (ADR-143 phantom `cx22`).

## State

All 11 workstreams shipped and a 6-agent review panel ran. Its P0/P1s and most P2s are
fixed and committed. **The PR is not merge-ready** — the queue below is what remains.

Everything green as of HEAD: `git-data-luks` 58/58, `git-data-emit` 21/21,
`git-data-runcmd-rehearsal` 9/9, `git-data-replication` 14/14, parity 98/98, birth-gate
80/80, `tsc --noEmit`, `terraform validate` on both roots, `systemd-analyze verify`.
`user_data` = **31,904 / 32,768 (864 B headroom)**.

## Remaining queue (from the review panel — all ≤100 lines / ≤4 files ⇒ fix inline)

**P2 — tests that certify the wrong thing**
1. `apps/web-platform/infra/git-data-emit.test.sh` — whole redactor rules have **zero fixtures**. Deleting any of these individually leaves the suite 21/21 green: the Bearer rule, the `://user:pass@` rule, the `tail -c 180` cap, and `tr -d '"\\'` (that last one is payload-integrity: an unescaped `"` in a git error yields malformed JSON → Sentry 400 → `curl -f` non-zero → the delivery assertion fails the boot). Add one fixture per rule, each mutation-proven.
2. Same file — **k=v tag VALUES are never asserted.** AC30's loop is `grep -q "\"$k\""`, key only; blanking every value stays 21/21 green. Also uncovered: the `[ -n "$k" ]` empty-key guard, and a value containing `=` (`${kv#*=}` vs `${kv%%=*}`).
3. `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — the `CHMOD_RAN` arm is a tautology (`grep -rn CHMOD_RAN` returns only the assertion itself; nothing ever prints it). Append `; echo CHMOD_RAN` to the chmod line in the mutated fixture.
4. `tests/scripts/test-git-data-host-birth-gate.sh` — presence loop is a population-of-three: only the SSH key secrets get an omission fixture. Deleting the two **new** members from the gate's `for present_addr in` loop leaves the suite 80/80 green (the `n_all -eq 15` self-check pins the *fixture*, not the gate).
5. `git-data-emit.test.sh` channel-split arm — `[ "$n_with" -gt "$n_without" ]` has no floor on `n_without` (a broken Sentry arm gives `1 > 0` → pass), and it never inspects the Better Stack **body**, so no redaction assertion runs against that payload's separate format string.

**P2 — stale claims that go FALSE at merge** (grep `git grep -n '#6982'` and classify each)
6. `.github/workflows/apply-web-platform-infra.yml:~187` — the `workflow_dispatch` **input help text** still says the route "is INTERLOCKED until #6982 ships an off-host emitter". First thing a dispatcher reads.
7. Same file, birth-job header (~`:3841`) — "INTERLOCKED — this job REFUSES TO PLAN today… measured 0 for sentry_dsn". Both clauses false (the count is 2).
8. `knowledge-base/engineering/operations/runbooks/git-data-birth.md:~196` — "The git-data host itself emits nothing… until #6982", eleven lines above the new section that queries those channels.
9. `tests/scripts/lib/git-data-birth-readiness-gate.sh:5-6` — the gate's own justification comment states "0 occurrences of sentry_dsn".
10. Counts: ADR-149 `:~154` says "the other **thirteen**" (now fifteen); `git-data-birth.md:~94` says "**eighteen** `-target`s" (now twenty).
11. `ADR-068:~1285` and `git-data.tf:~350` still say **"NOTHING ABORTS"** — this PR falsifies it (the trap + `set -e` now precede the checksum block).

**P2 — verification gaps**
12. `git-data-luks.test.sh` A27 is named "BYTE-IDENTITY" but only greps for `indent(6, <var>)` and asserts zero `encoding: b64`. It never renders and never compares bytes. The real check is ~4 lines in the rehearsal's existing `yaml.safe_load` block: hash each `write_files` payload against its source file. (The mechanism itself is verified sound — all nine payloads render byte-identical.)
13. `cloud-init-git-data.yml` — `_devalue` is armed in only **1 of 3** trap contexts. `GIT_DATA_LUKS_KEY` is in env for `luks_err` and the bootstrap, but **not** for `on_err` / `bootstrap_err`, which pass the *same* `/var/log/cloud-init-output.log` as detail. The passphrase is 40 chars alphanumeric and matches no pattern rule, so `_devalue` is its only defence. Fix: have the LUKS/doppler stages tee a pre-scrubbed stage-local detail file the parent traps read.
14. Plan `discoverability_test` (plan:~895) and `git-data-birth.md` step 2 both call `scripts/sentry-issue.sh --search` — **no such flag** (usage is `[--latest-event] [--redact] <issue-id>`). Replace with a Sentry issues-API `curl` or an issue id.
15. Plan `failure_modes` (plan:~838-854) describe three routes that were never built (a 15-min `SOLEUR_GIT_DATA_DISK` poller, a `doppler-cli-install-FAILED` Better Stack marker, a gc-OOM poller). Rewrite to what shipped.

**P3**
16. `git-data-replication.ts` — the new `log.warn({ workspaceId, … })` ships a bare workspace UUID (= `auth.users.id`) to the app log sink, in the same PR that adds a UUID redactor to the host emitter *because* a bare UUID is not scrubbed. Pre-existing sibling at `log.info` line ~385.
17. `article-30-register.md` — two **pre-existing** rows silently lose content to GFM: `:~230` (`terraform show -json | jq` splits a cell, ~730 chars discarded) and `:~324` (~3,270 chars). Not this PR's; file separately per `wg-when-an-audit-identifies-pre-existing`.
18. `ADR-147` addendum should record the divergence that `git-data-emit` ships **inside** `user_data` while that ADR's decision is "baked host scripts, not `user_data`" (git-data has no bake path).

## Rung 2 is deliberately NOT done

The W12 rehearsal reached **rung 1** (container harness) only. Rung 2 — booting the rendered
template once on a throwaway `cpx22` outside the `hcloud_server.git_data` address — is a real
Hetzner write outside this PR's scope fence and needs operator authorisation. It is carried as
**#7025's own precondition**, not inherited as a pass. The DO-NOT-DISPATCH banner is
deliberately retained; do not clear it in this PR.

## Gotchas that cost time this session — do not rediscover

- **`user_data` is a hard 32,768-byte gate** and comments count. `bash apps/web-platform/infra/git-data-userdata-budget.sh` after **every** edit to `cloud-init-git-data.yml`, `git-data-bootstrap.sh`, `git-data-gc.sh` or the units — all four ship inside it. Measure with Terraform's own `base64gzip`, never `gzip -9` (`-9` overstates headroom; the plan's "~10.8 KB" was really 9,052 B). Adding review-fix comments blew the cap **three** times.
- **Terraform's template scanner does not skip YAML comments.** A `%{` or a live `${…}` inside a `#` comment breaks the render. Broke it twice — once in a comment *describing* the trap.
- **`betterstack-query.sh` Mode 1** takes raw SQL as the **first positional** and rejects convenience flags (`--since` → exit 64). Put the window inside the SQL. And `remote($BS_TABLE)` takes **no** `primary` argument — only `s3Cluster` does; `remote(primary, …)` needs a NAMED COLLECTION grant this credential lacks (HTTP 500 ACCESS_DENIED).
- **Never capture stderr into a match buffer** when the tool echoes the failing query back — that is how the birth poll matched `boot_complete` in its own error message and reported success.
- **A mutation that does not land is a null result wearing a pass's clothes.** Assert it landed (`diff -q` against a pristine backup) and watch for `sed: unknown option to 's'` — a `;` delimiter with `; then` in the pattern silently no-ops.
- Synthesized **secret-shaped** fixtures trip GitHub Push Protection (a stub `dp.st.…` blocked a push). Split across `join()`/concatenation. Push scans the whole commit range, so amend — a working-tree fix is not enough.
- `git-data-luks.test.sh` runs under `set -o pipefail`: `grep -c … | grep -q '^0$'` reports the **opposite** of the truth on a clean file (`grep -c` prints 0 and exits 1).

## Definition of done

Queue above cleared (or explicitly deferred with a CONCUR'd scope-out), budget under cap,
`bash apps/web-platform/infra/run-registered-suites.sh` green, then `/soleur:ship`. Ship must
verify `Closes #6982` is the only close-keyword ref in the PR body and that #7025 is linked.
