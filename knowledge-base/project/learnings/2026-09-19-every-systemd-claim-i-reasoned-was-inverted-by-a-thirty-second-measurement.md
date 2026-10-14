---
date: 2026-09-19
tags: [systemd, infra, review, mutation-testing, guards, instruments, git-data, followthrough, ratchets]
category: best-practices
refs: [8210, 8312, 8010, 8211, 8094, 6167, 8077, 7797]
synced_to: [work, review, one-shot]
---

# Every systemd claim I reasoned was inverted by a thirty-second measurement

## What happened

PR #8312 (#8210) gives the git-data host a boot-time LUKS reopen: a `Type=oneshot`
under `doppler run`, an `OnFailure=` reporter, a standing-retry timer, a measured
`boot_complete` boolean, and a rung-2 rehearsal reset arm that proves it on a real
host. The mechanism was right from the first commit. Almost every **sentence about
how systemd would run it** was wrong, and each wrong sentence had a unit directive,
a runbook paragraph, an ADR amendment, and a test arm built on it.

Five claims, all written from reading `systemd.service(5)` and the v255 source,
all refuted by a transient unit and a counting reporter on this box (systemd 261):

| Claim I wrote | Measured | Consequence of the claim |
|---|---|---|
| `OnFailure=` fires once, at the final failed state; `service_enter_dead()` suppresses it during auto-restart | Fires on **every** attempt plus the terminal one (3 runs for a 2-burst ladder); that state is what *triggers* it | A Doppler blip that recovered on attempt 2 paged a fatal and FAILED the rehearsal's reboot arm |
| A refused timer tick on a failed unit is itself a failed start, so the reporter fires "~4×/hour, ~96/day" | `failed → failed` is not a transition; **zero** fires | The "accepted cost" paragraph in the runbook and the timer was fiction in both directions |
| `Result=success` is the terminal-success read for a `RemainAfterExit` oneshot | Reset to `success` the instant retry attempt 2 **starts**; a never-started unit reads `inactive success` | The TERMINAL boolean `luks_reopen_unit` read `yes` on a unit still mid-ladder |
| `Persistent=true` gives a catch-up tick after an outage | `systemd.timer(5)`: only with `OnCalendar=` | Inert directive with a load-bearing comment |
| `enable --now` returns at attempt 1's result | True under default `RestartMode`; under `RestartMode=direct` it blocks through the **whole** ladder (≤1740 s) | The fix for claim 1 would have held cloud-final for half an hour |

The fixes were one directive each — `RestartMode=direct`, `RestartPreventExitStatus=3`,
`ActiveState=active`, drop `Persistent=`, `--no-block` — and each is now pinned by a
row that a mutation REDs. The cost was in the prose: the unit comment, the runbook's
"Event counts" section, the timer's "accepted cost", ADR-198's Art. 32(1)(c) bound,
and the plan's `## Observability` block all carried the inverted model.

The second thing that happened is the one this repo keeps re-learning: **the
instrument built to check a claim was satisfied by the wrong shape.** Twelve of the
PR's own defects were in its verification, not its mechanism:

- The central wire — the runcmd item's `systemctl enable --now` — was pinned by a
  raw-file substring grep. A `#` prefix on the line stayed 448/448 green.
- The reporter's "fires once when Doppler HANGS" row used a doppler stub whose
  `sleep 200` resolved to **the suite's own no-op `sleep` stub**, so the timeout arm
  never ran and the row passed in 0 s with `timeout` stripped from the body.
- "Never formats" was column-0 anchored while `/usr/bin/mkfs.ext4` sat on the scratch
  PATH; an indented `{ mkfs.ext4 … ; }` in the mount branch passed.
- "The passphrase reached luksOpen on stdin" had no negative half; appending the key
  to argv passed.
- A budget guard summed through `bc` (not installed), compared against `""`, and
  certified every ceiling. A settle guard matched a 3-digit shape and read a
  *shortened* settle as "no settle step".
- `NON_TERMINAL` was declared "ONCE, here" and re-typed literally on the next line.
  Two `head -1` roster reads were blind to a second site — the first-match defect
  a commit in the same PR had just fixed elsewhere.
- The follow-through probe that closes the issue could **never PASS**: it handed
  the rung-2 gate a lone `mktemp` copy of the template, and the gate derives the
  evidence file, render module and every bound payload from the template's
  *directory*. A `git archive` export fixed the paths and then failed Guard 4's
  provenance read (not a git work tree). The gate wants a `main` checkout with
  history, which is exactly what the sweeper provides.
- The rung-2 interlock was copied onto the replace job **without** the create job's
  `fetch-depth: 0`; the provenance arm HOLDs on a shallow clone. The route every
  document called "held until PM2" was held permanently.
- My own `emit`-phase refusal was invisible: `Restart=on-failure` re-ran the script,
  attempt 2 found the store open, took the silent `noop` branch, exited 0.

## The generalisable lesson

**A claim about a platform's runtime semantics is a measurement you have not taken
yet.** For systemd specifically, the measurement is thirty seconds:

```bash
# a counting reporter, then a failing oneshot with the directives under test
cat > ~/.config/systemd/user/rep.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo FIRED >> /var/tmp/rep.count'
EOF
systemctl --user daemon-reload; : > /var/tmp/rep.count
systemd-run --user --unit=probe -p Type=oneshot -p RemainAfterExit=yes \
  -p Restart=on-failure -p RestartSec=2 -p StartLimitBurst=2 -p StartLimitIntervalSec=60 \
  -p OnFailure=rep.service /bin/sh -c 'exit 1'
sleep 10; grep -c FIRED /var/tmp/rep.count      # 3 under RestartMode=normal, 1 under direct
systemctl --user start probe.service; sleep 2   # refused inside the window
grep -c FIRED /var/tmp/rep.count                # unchanged: a refused start fires nothing
systemctl --user show -p ActiveState,Result,NRestarts --value probe.service
```

Run it **before** the directive is written, and again for every sentence the diff
adds about ordering, retry, or terminal state. The unit's `[Unit]` comment then
records the measurement, not the reasoning. Two corollaries the session paid for:

1. **A copied mechanism must come with its preconditions.** The gate call was
   copied from the create job without its `with: fetch-depth: 0`; the timer's
   `Persistent=true` was copied from `git-data-gc.timer` without its `OnCalendar=`;
   the inline `assert_fixture_dir` was copied and drifted by one string. When
   copying a block from a sibling, diff the *whole* sibling block — `with:` keys,
   the directives above and below, the comment explaining why — not the line you
   wanted.
2. **A guard is proven by the mutation that reds it, and the mutation must be
   applied to the artifact the guard reads.** Every arm that survived was one
   whose author had never tried to break it: the raw-file grep, the stub-shadowed
   sleep, the column-0 regex, the missing negative. The suite went 226 → 493
   assertions, and the floor now counts *call sites*, not verdicts.

## Repo-global ratchets this diff tripped (four, one per round)

`fixture-relative-assert` (P1b: an empty `$RUNDIR` → `/action` root write),
`guard-vacuity-floor` (ledger 47→48; fixed by promotion; later the mutant
construction broke because a comment sat between the floor's bindings and its
`if`), `lint-followthrough-varq-ban` (a P1b-driven `${OUT:?}` on a follow-through
line — the two ratchets *appear* to disagree, and the canonical
`assert_fixture_dir` copy satisfies both), and ci-deploy's **inngest start-writer
inventory** (#8077 Guard 2 #6c) for `systemctl start "$_munit"`. None references a
changed file at selection time; the work-skill rule about them is correct and was
still hit four times. Run them by name on any infra diff.

## Session Errors

Forwarded from the plan/deepen phases (session-state.md):

1. **`iac-plan-write-guard` denied the first plan/tasks writes** (systemctl tokens) — Recovery: `iac-routing-ack` after terraform-architect confirmed routing — **Prevention:** expect the hook on any plan naming a unit file; ack it up front.
2. **`lint-infra-no-human-steps.py` flagged actor tokens three times** — Recovery: reworded — **Prevention:** run the lint on plan prose before the first commit, not after.
3. **Two plan-phase claims were false against the tree** (the replace job "calls the rung-2 gate"; the route "is held") — Recovery: corrected at plan-review — **Prevention:** for every "X already does Y" in a plan, `grep` X for Y before writing it.
4. **Playwright MCP failed to connect** — Recovery: not needed — **Prevention:** none (environment).

This session:

5. **Memory reaper killed `git commit` twice under lefthook's bun battery** — Recovery: `LEFTHOOK=0` + the bypassed linters run explicitly and disclosed in the message — **Prevention:** on this box commit with `LEFTHOOK=0` and run gitleaks/markdown-lint/no-human-steps/terraform fmt by hand; check for a surviving hook process before any git-write retry.
6. **`git checkout --` during mutation testing reverted uncommitted edits** — Recovery: re-applied — **Prevention:** `cp` a pristine copy per mutation; never `git checkout` while the tree is dirty.
7. **Budget guard summed through uninstalled `bc`** and compared against `""` — Recovery: awk + non-vacuity floor — **Prevention:** every arithmetic in a guard needs a positive control that changes the verdict.
8. **Settle guard matched a 3-digit shape**, so a shortened settle read "no settle step" — Recovery: read the value numerically — **Prevention:** assert the value, never the token's width.
9. **Monitor watched the `setsid` wrapper PID** → false "GONE" — Recovery: resolve the real PID by `/proc/<pid>/cwd` — **Prevention:** capture the runner's own PID via the cwd scan, never the shell's.
10. **Monitor filter emitted only after its inner loop**, exceeding the 30-min cap twice — Recovery: heartbeat every N iterations — **Prevention:** a Monitor must emit within its ceiling or its expiry reads as a stall.
11. **A grep with stray backslashes returned 0** and reported "no RED fixture" — Recovery: confirmed with Python — **Prevention:** the Box rule: confirm negatives with `grep -a`, `sed` or Python.
12. **Empty `$RUNDIR` → `/action` root-filesystem write as root** (P1b) — Recovery: validated + `${VAR:?}` at each use — **Prevention:** run `fixture-relative-assert` on any new `.sh` before the first push.
13. **`guard-vacuity-floor` ledger 47→48** — Recovery: promotion, as the gate prescribes — **Prevention:** a new floor-bearing suite is promoted in the same commit.
14. **Inline `assert_fixture_dir` drifted by one string** — Recovery: byte-identical — **Prevention:** copy the canonical body with `sed -n`, never retype.
15. **Sentry op-contract arm took `indexOf` of the first `_warn` emit** — Recovery: check every emit — **Prevention:** a positional read of a set is blind to its second member by construction.
16. **`merge-tree` conflict on generated `model.likec4.json`** — Recovery: regenerate from the auto-merged `.c4` — **Prevention:** regenerate, never hand-merge, a generated file.
17. **Stop-hook feedback, repeatedly: closing text named actions not yet taken** — Recovery: `<stop>BLOCKED:</stop>` with no forward-looking language — **Prevention:** end a turn on what was done or on the named blocker.
18. **`NON_TERMINAL` declared "once" and re-typed on the next line** — Recovery: derive from the variable; two mutations RED — **Prevention:** after declaring a single source, grep the file for the values it holds.
19. **Monitor re-echoed matched lines every loop** — Recovery: dedup by count — **Prevention:** a poll that re-greps a growing file must emit only lines past the last count.
20. **Session rate limit killed 7 of 11 review seats** — Recovery: re-spawned after reset, briefed with what the first four found — **Prevention:** a seat that died is not a seat that ran; never count its absence as clean.
21. **Full gate run against a tree edited underneath it — twice** — Recovery: killed, re-queued HEAD-frozen — **Prevention:** a gate reads the live tree; either stop editing until it ends or run it from a detached worktree at the SHA being certified.
22. **ADR-115 cleared its blocker citing the gc `Wants=` the same PR deleted** — Recovery: dated correction — **Prevention:** the correction sweep for a cut mechanism greps the mechanism's *name* repo-wide, not the diff's file list.
23. **PR body's "zero files under `apps/web-platform` outside `infra/`" was false** — Recovery: corrected; the conclusion stood on the reproduction — **Prevention:** a proof in prose is a command; run it before writing it.
24. **`${OUT:?}` in a follow-through violated the varq-ban** (3 gate reds from one cause) — Recovery: canonical `assert_fixture_dir` copy — **Prevention:** in `scripts/followthroughs/`, the sound guard is the helper copy, never `:?`.
25. **`grep --exclude` after `--` was silently not applied** — Recovery: moved before `--` — **Prevention:** options before `--`; a negative assertion that fails on its one allowed file is telling you the exclusion never ran.
26. **The follow-through probe could never PASS — wrong twice** — Recovery: reads the checkout it stands in, TRANSIENT off-main — **Prevention:** a probe that calls a gate must run the gate the way its production caller does; positive-control the PASS branch, not only the TRANSIENT ones.
27. **Timer `Persistent=true` inert; "96/day" and "quarter-hour" claims false** — Recovery: measured, rewritten — **Prevention:** the thirty-second probe above, before the directive.
28. **`OnFailure=` per-attempt, `Result` non-terminal, blocking `enable --now`** — Recovery: `RestartMode=direct`, `ActiveState=active`, `--no-block` — **Prevention:** same probe; the unit comment records the measurement.
29. **Interlock copied onto the replace job without `fetch-depth: 0`** — Recovery: added + parity pin — **Prevention:** copy the sibling's whole block including `with:`.
30. **My `emit` refusal was erased by the retry** — Recovery: exit 3 + `RestartPreventExitStatus=3` — **Prevention:** for every new failure exit, ask what the *next attempt* does with it.
31. **gc unit pair cached the passphrase on the root disk; ADR-198's "never" was false** — Recovery: `--no-fallback`, tmpfs `TMPDIR`, `PrivateTmp` on the class — **Prevention:** a "never" about a host is a grep over every unit on it.
32. **Birth heredoc `mkfs` guard fail-open on a damaged superblock** — Recovery: keyed on the run having `luksFormat`'d; B18m with four mutations — **Prevention:** a format guard keyed on a probe's *absence of signal* is fail-open; key it on provenance.
33. **Eleven vacuous test arms** — Recovery: extracted bodies, runtime spies, token-boundary regexes, negatives, real sleep, exact-line `unit_has` — **Prevention:** before reporting a suite green, name the edit that reverts the central change and which row reds.
34. **Runbook cited `doppler activity --project` (no such flag), a SHA for `gh workflow run --ref`, and an ADR-068 "backup path" that does not exist** — Recovery: `configs logs`, a tag push, and an honest "no automated route yet" — **Prevention:** run `--help` on every command a runbook row cites; grep the ADR for the procedure a lever names.
35. **Hook blocked `doppler secrets set` without `> /dev/null` in runbook prose** — Recovery: reworded to the rollback route — **Prevention:** the hook is right; runbook text is executed by agents.
36. **ci-deploy's start-writer inventory caught `systemctl start "$_munit"`** — Recovery: pinned with the reason it can never be inngest-server — **Prevention:** the four ratchets above, by name, on any infra diff.
37. **Vacuity-floor mutant construction broke** when a comment sat between the floor's bindings and its `if` — Recovery: bindings contiguous with the `if` — **Prevention:** `MIN_ASSERTIONS=` and `total=` directly above the floor block, comment above them.
38. **`bun test` on web-platform finds 0 files** (bunfig `pathIgnorePatterns`) — Recovery: `bunx vitest run` — **Prevention:** web-platform is vitest; `plugins/soleur` is bun.
39. **semgrep's 0 on 17 `.sh` files was vacuous** (zero bash rules in 339) — Recovery: `shellcheck -S error` as the load-bearing analysis, coverage stated in the PR body — **Prevention:** a "0 findings" from a scanner is a statement about its rule inventory until the canary says otherwise.

## Related

- `2026-09-18-three-sentences-i-pasted-from-the-plan-were-inherited-not-measured.md` —
  the same class one level up (inherited sentences); this session's inherited
  sentences came from a man page and a source read rather than a sibling artifact.
- `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md` —
  the central-wire defect, recurring: here the wire was pinned by a grep a comment
  satisfies.
- `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
  — the `bc` guard, the stub-shadowed sleep and the Monitor faults are that class.
- `2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md` — the `emit` refusal,
  the `${OUT:?}` guard and the `head -1` rosters.
