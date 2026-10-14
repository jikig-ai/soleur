# Tasks — Better Stack round-trip verdict, credential-destination confinement, lefthook hop-budget

Derived from
[`knowledge-base/project/plans/2026-09-07-fix-betterstack-roundtrip-credfwd-lefthook-plan.md`](../../plans/2026-09-07-fix-betterstack-roundtrip-credfwd-lefthook-plan.md)
after an eight-reviewer panel. `lane: cross-domain` (fail-closed default — no `spec.md` on this branch).

**Delivery: three PRs off this branch, plus one task that is not a PR.** The slicing discipline is a
property of *merges*, not commits — `apply-web-platform-infra.yml` fires on the union of a PR's diff.

**Order:** Track D first in wall-clock (it blocks nothing and is time-sensitive) → PR 0 → PR 1 → PR 2.

---

## Phase 0 — Preconditions (blocking)

- [x] 0.1 Re-run `gh issue view` for #7867, #7873, #7886 — all three OPEN at 2026-09-07T13:0xZ. Abort any unit whose issue closed.
- [x] 0.2 **Fix the classifier's token set, then run the census with it** — not from the plan's
      table. The classifier does not exist yet at Phase 0, so this step *defines* it (`-u`, `--user`,
      `--header @-`, `--netrc`/`--netrc-file`, `--oauth2-bearer`, `--proxy-user`, `-E`) and runs a
      one-off sweep with exactly that set; Rule D then implements the same set. Record the number —
      it becomes Rule D's baseline and AC B1's floor. Deriving the floor from a different token set
      than the rule ships with is how five reviewers got five different counts.
- [x] 0.3 Enumerate which PR 0 / PR 2 files sit in
      `scripts/lint-shell-trace-credential-refusal.baseline.txt` **without** a
      `case "$-" in *x*)` preamble. Known: `zot-inventory.sh`, `betterstack-query.sh`,
      `supabase-advisor-scan.sh`. CI runs that lint in `--changed` mode, which **bypasses the
      baseline**, so touching any of them fails CI until the preamble lands in the same commit.
- [x] 0.4 Measure this runner's base ancestry distance to `claude` via `/proc`, so the depth harness
      targets `MAX_WALK_HOPS` hops from the hook's frame rather than a hardcoded number.
- [x] 0.5 **DONE 2026-09-07 — outcome: PR 1 CUT** (#7879 already carries the fix in unpushed 4115024f5). — **Re-check PR #7879.** It is OPEN, WIP, on `.claude/hooks/memory-backstop.test.sh`, taking
      the same verdict-gate mechanism this plan adopts, and it does **not** close #7886. Verified at
      plan time that its change is not yet pushed (the diff against `origin/main` for both hook files
      is empty). If it has since landed, PR 1 shrinks — verify #7886 is actually fixed on `origin` and
      close it against #7879 rather than re-fixing it. Settle PR 1's scope here.
- [x] 0.6 **MOOT — PR 1 cut, so no new `.claude/hooks/` suite is added and MAX_DEFERRED is not perturbed.** — Decide whether the `#7886` guard suite will be floor-bearing (see 1.f1) — it changes whether
      `scripts/guard-vacuity-floor.test.sh`'s `PROMOTED_FILES` must be edited in the same PR.

---

## Track D — #7867 (not a PR; run first in wall-clock terms)

> **Open items and why (recorded 2026-09-07).** D.1 is a third-party support
> conversation opened in the operator's name — surfaced for their go-ahead rather than
> sent autonomously. D.7/D.8 are gated on a literal `NOT_STORED`; the probe returned
> `UNKNOWN`, so they did not fire (the substance was established out-of-band instead —
> see the #7867 comment). The `Deferred` items below moved to tracker #7898.

- [ ] D.1 **Open the Better Stack vendor escalation — unconditional on the verdict.** #7867 records
      it as deliberately not gated; hypothesis (b) is already confirmed independently by
      `CLUSTER_DOESNT_EXIST` persisting after an acknowledged write. Include the marker prefix the
      probe writes (`SOLEUR_BS_ROUNDTRIP_7855_`) and the timestamps of both the 2026-09-06 run and
      this one, so the vendor has a specific reproducible round trip.
- [x] D.2 Re-read #7867's state and latest comment. If the sweeper (cron ~19:4x UTC) already posted a
      verdict for this window, read it and re-run only if it was `UNKNOWN`/`DARK`.
- [x] D.3 Run `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` under
      `doppler run -p soleur -c prd_terraform`. Capture full stdout **and** the exit code.
- [x] D.4 Pull corroborating rows first-hand with `scripts/betterstack-query.sh`: the control source's
      liveness in the same window, and the target table's existence. Never request a dashboard reading.
- [x] D.5 Comment on #7867 with the verdict, marker, wall-clock latency, the vendor's
      `ingest_time - dt`, **and the verdict→action table** so the decision procedure survives the
      plan's archival.
- [x] D.6 **DONE — verdict was `ROUNDTRIP_UNKNOWN` (exit 3); took the D.6d branch.** — Branch on the verdict actually returned:
  - [ ] D.6a `ROUNDTRIP_STORED` (0) — **do not close the issue**; leave closure to the sweeper
        (`closed_precheck` reopens agent-authored closes). Correct ADR-192:326 and `model.c4:630`'s
        `TARGET state — wired at merge, unobserved` clause. **Not** the `betterstack` element
        description — verified, it makes no storage claim.
  - [ ] D.6b `ROUNDTRIP_NOT_STORED` (1) — issue stays open. Run the throwaway-source discriminator
        (D.7). Record a review-by date: first sweeper run ≥7 days after the escalation opened.
  - [ ] D.6c `ROUNDTRIP_DARK` (2) — account-level claim. Comment, file/append to a #7811-shaped issue.
        Run **once** this session; do not loop.
  - [ ] D.6d `ROUNDTRIP_UNKNOWN` (3) — diagnose **schema first** (`dt`/`raw`/`_row_type`/`ingest_time`
        were verified against a `vector`-platform table; this source is `http`), credential second
        (pre-cleared at plan time). Record the **conclusion**, not that it was attempted.
  - [ ] D.6e **Any other exit, or no `SOLEUR_BETTERSTACK_ROUNDTRIP` line** — the probe did not run.
        Exit **78** is reachable (refuses to run under `set -x` with a live credential, #7797) and
        emits no verdict line. Record raw output; treat as not-a-verdict; do not close or escalate on it.
- [ ] D.7 On `NOT_STORED` only: mint a **throwaway** Logs source via `POST /api/v2/sources` (same
      `http` platform, same `eu-central-1a` region), POST one marker, read it back. `2734275` was
      itself API-minted 2026-09-03 and never stored, so recreation is a second draw from the same urn.
      Stores → object-scoped, recreation is the answer. Does not store → recreation is **refuted**.
- [ ] D.8 Route the mechanism choice to the `cto` agent with the discriminator's result attached.
      Record that Sentry is an **already-wired** evidence channel (git-data bakes a DSN; the rung-2
      capture has a Sentry read path), and that repointing at `2457081` stays unavailable (ADR-192 I-2).
- [x] D.9 Verify no write to source `2457081` occurred — no marker with this session's prefix in the
      control table.

---

## PR 0 — the credential-transport sweep (depends on nothing; merge first)

- [x] 0.a Add the `case "$-" in *x*)` xtrace preamble to each affected file, modelled on
      `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`.
- [x] 0.b Add `--disable` (**literal first argument**) and `--noproxy '*'` to the credentialed `curl`
      in: `scripts/supabase-advisor-scan.sh`, `scripts/betterstack-query.sh`,
      `scripts/betterstack-ingest-probe.sh`,
      `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`.
      **Flags only — no destination pin.** Three suites drive these through a
      `BETTERSTACK_QUERY_HOST=127.0.0.1` env seam; pinning here would send synthetic credentials at
      the real warehouse from CI.
- [x] 0.c Verify: `tests/scripts/test-git-data-rung2-evidence-capture.sh`,
      `tests/scripts/test-betterstack-ingest-probe.sh`, the `betterstack-query` suites.
- [x] 0.d Verify `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
      passes on the diff. *(AC S1-S3)*

---

## PR 1 — #7886 — CUT 2026-09-07 (transferred to PR #7879)

Task 0.5's re-check found PR #7879 already carries this fix in unpushed local commit `4115024f5`,
with the same verdict-gate mechanism and a fuller reason classification. Two live sessions on one
file is the failure this cut avoids. Every task below is struck; none is to be implemented on this
branch. The transfer is recorded as a comment on #7886, and #7879 must add `Closes #7886`.

- [x] CUT — 1.a **RED first.** Build the depth harness: **real forks** (`{ …; } & wait`), and it must
      **verify its achieved depth against `/proc`** before invoking the suite. Nested `bash -c` adds
      **no** hop (measured: ×1 → 3, ×2 → 3, because the outer `exec`s into the inner), so a harness
      built that way silently tests nothing. Target is derived from 0.4, not hardcoded.
- [x] CUT — 1.b Confirm the harness reproduces `FAILED 1 (passed 46)` at the boundary depth.
- [x] CUT — 1.c **Replace the gate's independent walk with a verdict read.** Run the hook, take its
      `outcome`/`reason`, and classify — this *deletes* the second walk rather than aligning it.
      Measured: the hook emits **12** decline reasons. FAIL on the five defects
      (`adoption_unverified`, `cap_out_of_range`, `fleet_caps_unverified`, `pid_reuse_disambiguated`,
      `scope_caps_unverified`); SKIP on the environment ones (`claude_pid_not_found`, `no_bus`,
      `no_busctl`, `no_jq`, `no_terminal_scope`) and the two deliberate ones (`disabled`,
      `concurrent_apply`). The classification is what keeps T8 meaningful — a bare
      `outcome != "applied" ⇒ skip` would lose all five defect reasons.
- [x] CUT — 1.d Derive the reason set **from the hook's source** (`reason="…"` assignments), never a list
      maintained in the test, so a reason added to the hook without a classification reddens the guard.
- [x] CUT — 1.e **Fallback only, if the verdict gate cannot be adopted:** seed the walk from **`$BASHPID`**
      (measured: `$$` survives subshells — inside `( )` it is still the parent's PID, so "spawn a
      child" written with `$$` is a no-op) and read the budget from the sourced `MAX_WALK_HOPS`.
- [x] CUT — 1.f Add the **static** guard (`.claude/hooks/*.test.sh` — already in `SUITE_GLOBS`, so no
      `run_suite` line needed) over the reason enumeration and its classification.
- [x] CUT — 1.f1 **If that guard is floor-bearing, add it to `PROMOTED_FILES` in
      `scripts/guard-vacuity-floor.test.sh` in the same PR.** `.claude/hooks/` is in that guard's
      `DEFERRED_DIRS`, its population is `git ls-files '*.test.sh'`, and `MAX_DEFERRED=47` is a
      **shrink-only** ratchet — an unpromoted floor-bearing suite reddens CI. Precedent:
      `monitor-supersede-guard.test.sh`, `incident-sandbox-coverage.test.sh`.
- [x] CUT — 1.g Comment on #7208: `MAX_WALK_HOPS` is **not raisable-for-benefit** — the hook is registered
      only as a `SessionStart` hook (`.claude/settings.json`, no lefthook entry), runs 1-2 hops from
      `claude` there, and deeper trees are covered by cgroup inheritance from the SessionStart adoption.
- [x] CUT — 1.h Verify across the depth range: none reports `FAILED`; the boundary depth reports a green,
      honestly-skipped **47**; one beyond still skips the arm. **47-under-lefthook vs 54-direct is the
      correct steady state** — do not "fix" the count. *(AC A1-A7)*

---

## PR 2 — #7873 site 1 + Rule D

- [x] 2.a **RED first.** Invert the `mutate_sub` seam in `tests/scripts/test-zot-inventory.sh`:
      normal cases run a **source-mutated copy** whose pinned literal is rewritten to the loopback URL
      (so the injected env value matches and all ~79 `INGEST_BODY` assertions keep working against the
      real listener); `inv-exfil` runs the **unmutated** script with the canary URL and asserts refusal.
      **Do not convert the harness to a stubbed `curl`** — the pin is a bash comparison evaluated
      *before* curl runs, so a stub cannot stop `run_inv`'s loopback injection being refused on every case.
- [x] 2.b `inv-exfil` asserts **zero canary requests AND the refusal message anchor** — not a bare
      non-zero exit (a `set -u` crash also exits non-zero), and not absence alone (vacuous once the
      destination can never be accepted).
- [x] 2.c Add the proxy-defeat case; **demonstrate** it failing against the pre-fix script. Add the
      `.curlrc` case only if it can also be demonstrated failing pre-fix — finding 3 is doc-derived;
      drop it with a stated reason otherwise.
- [x] 2.d Add the xtrace preamble to `scripts/zot-inventory.sh`.
- [x] 2.e Pin + confine the **ingest** `curl`: exact equality against the inline literal at `:91`,
      `--disable` first, `--noproxy '*'`, `--proto '=https'`. **Scope to the ingest call only** — the
      registry leg defaults to `http://127.0.0.1:5000` and `--proto '=https'` would break production
      and the harness. **Keep the comparand the inline literal** so `mutate_sub` still lands.
- [x] 2.f Pin the **second credential path the issue does not name**: `REGISTRY_HOST` is derived from
      the env-settable `ZOT_INVENTORY_REGISTRY_URL` and lands in the netrc `machine` line at `:179`,
      consumed at `:194` via `--netrc-file`. Validate that destination before the netrc is written.
- [x] 2.g Add **Rule D** to `scripts/lint-shell-trace-credential-refusal.py` as `check_rule_d`,
      mirroring the existing `check_rule_a`/`b`/`c` shape: caller-shape assembly (membership is the
      assertion — never key on the pinned literal), widened classifier, **three** chokepoints
      (argv, `--config`, netrc `machine`), transport over all members + pin over
      env-settable-destination members.
- [x] 2.g1 **Give Rule D its OWN baseline — do not share the lint's existing one.** Measured: the
      shared baseline is per-file and rule-agnostic (`if rel not in baseline` drops *all* rules'
      findings for that file), it holds **130** entries, and **all seven** Better Stack sites are
      already in it (`zot-inventory.sh`, `betterstack-query.sh`, `supabase-advisor-scan.sh`,
      `betterstack-ingest-probe.sh`, both host scripts, `arm-heartbeats.sh`). Sharing it makes Rule D
      green over exactly the population it was written for, on the repo-wide run that is the blocking
      arm. Create `scripts/lint-shell-trace-credential-refusal.rule-d.baseline.txt`, generated from
      0.2's census. (`--changed` mode is unaffected — it bypasses the baseline entirely.)
- [x] 2.g2 ~~Add a ratchet~~ **CUT at review — strictly subsumed by the repo-wide run; see the plan.** It carries `--census` and `--write-baseline` only.
      ~~Create a `.highwater` mirroring the four existing ones; add `--check-highwater`.~~ Built,
      then REMOVED at review: the repo-wide run already reports a new offender (it is not in the
      baseline), so the ratchet could not fire without that suite firing first.
- [x] 2.h Add the parity assertion. **The plan's six-file list was wrong and is not what shipped:**
      a repo-wide grep finds **twelve** declaring files across **two** deliberate sources
      (`s2457081` and the git-data `s2734275`), so the shipped suite DERIVES its population and
      partitions by source id. A hand-list would have modelled one source as the whole fleet.
- [x] 2.i **DONE — both stay baselined; the classifier was NOT narrowed to exclude them.** — Keep the baseline **honest**: `arm-heartbeats.sh` and `cutover-verify.sh` are real members
      under `apps/web-platform/infra/**` this cycle does not fix. Baseline them; do **not** narrow the
      classifier to exclude them.
- [x] 2.j Add mutation + harness rows to `scripts/lint-shell-trace-credential-refusal.test.sh`
      (12 RED, 2 RED harness, 3 must-PASS).
- [x] 2.k Amend the `github -> betterstack` edge description in
      `knowledge-base/engineering/architecture/diagrams/model.c4`; run
      `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [x] 2.l Verify `bash scripts/lint-orphan-test-suites.sh` — **the linter**, not
      `scripts/lint-orphan-test-suites.test.sh`, which runs against a sandbox copy and *synthesizes*
      registration lines for up to 25 inherited orphans (it would be green on the exact defect).
- [x] 2.m File the two tracking issues: (1) the deferral census — files, `curl` lines, compliant count,
      env-settable / customer-shipped / host-baked splits, the seven cloud-init YAML siblings, the four
      Resend host scripts (`disk-monitor.sh`, `resource-monitor.sh`, `container-restart-monitor.sh`,
      `cron-egress-alarm.sh`), and the `CURL_BIN` transport seam **with an explicit upgrade trigger**;
      (2) the web-2 unpinned-script gap. *(AC B1-B12)*

---

## Deferred — #7873 sites 2 and 3 (rides a window opened for another reason)

Not this cycle. Recorded so the facts are not rediscovered:

- [ ] The refusal is **skip-and-report, never fail-stop**. At `soleur-host-bootstrap.sh` the post is
      followed by `soleur-boot-emit … fatal` (the Vector-independent dark-host detector); at
      `web-private-nic-guard.sh` by the `web_nic_guard` heartbeat. An `exit` above either silences a
      healthy host's beat or a dark host's only signal.
- [ ] `soleur-host-bootstrap.sh:878-881` has **no `else` branch today** — delivering "never a silent
      skip" there means adding a report line that does not exist yet.
- [ ] Use POSIX `[ … ]`, not `[[ … ]]`: that ingest post lives in a quoted heredoc authoring
      `/usr/local/bin/soleur-fresh-boot-ready` (`#!/bin/sh`), and the bootstrap runs as `sh <file>`.
      Both run under **dash**.
- [ ] **web-2 will not receive the fix** — the SSH provisioner hardcodes web-1; web-2's copy comes
      only from the image bake and `ignore_changes = [user_data, image]` prevents re-creation. Tracked
      gap, not something a green guard should paper over.
- [ ] Confirm the image's `curl` accepts `--disable`/`--noproxy` via `docker run --rm ubuntu:24.04`
      in CI — not a host shell.
- [ ] Read `steps.ssh_token_gate`'s outcome, not just the run conclusion: a `::warning::` skip leaves
      the PR green while the change never lands. Remediation is `workflow_dispatch` with `reason`.
