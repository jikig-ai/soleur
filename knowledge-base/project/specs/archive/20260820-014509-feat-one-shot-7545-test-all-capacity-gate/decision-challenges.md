# Decision Challenges — feat-one-shot-7545-test-all-capacity-gate

Persisted by `plan` / `plan-review` on the headless arm (ADR-084). `ship` Phase 6 renders these into
the PR body and files an `action-required` issue.

---

## DC-2 — The plan does not ship the decline the issue asked for (User-Challenge)

**Your stated direction.** #7545 asks for a pre-launch *decision* that declines a full gate the box
cannot absorb, plus a decision about the `LOCK_CONTENDED_PROCEEDING` path.

**What the plan ships instead.** A pre-launch *verdict* and a `test-all.sh --capacity` query that
answer the same question in under a second without blocking anything, plus a raised lock budget and
a wait heartbeat so the contended path stops firing routinely. No exit code changes.

**Why.** A six-agent review converged, and the decisive evidence sits in the ADR the issue itself
rests on:

1. **ADR-133 records a wait that was redeemed after 616 s** behind two sibling worktrees
   (`LOCK_ACQUIRED … after 616310ms`). A `>= 1` sibling decline refuses that run at t=0, converting
   a gate that *completed* into no coverage at all. The draft's "Pareto — never worse than the status
   quo" claim reasoned only about the missed-decline direction and was false in the other.
2. **A decline blocks `git commit`.** `lefthook.yml` runs `bash scripts/test-all.sh` at `pre-commit`
   on any staged `*.{ts,tsx,js,jsx}`; a non-zero exit blocks the commit. No `.ts` change could be
   committed while any sibling worktree ran the runner.
3. **It would be misread at ship.** `ship/SKILL.md` documents `rc=4` as "`SOLEUR_SUBAGENT=1` was
   set", and notes ship reached from a drain fan-out *inherits that variable* — so a ship session
   hitting a capacity decline would set `SOLEUR_ALLOW_FULL_GATE=1`, which is the exact override that
   re-creates the incident.
4. **The decline had no completion path.** Its only escape was that same override, which also
   disarms the subagent refusal. The draft used it as the mitigation for three of six risks.
5. **The real root cause was elsewhere.** `TC_LOCK_TIMEOUT` is 900 s against a measured ~45-minute
   full gate, so the budget expires by construction — that is *why* N runs land together. ADR-133's
   own addendum names raising it as "a candidate the original Alternatives never considered".

**What you get anyway.** The pre-launch check you asked for, before launching, in under a second —
and hand-queueing removed rather than renamed, because a budget above the hold time plus a heartbeat
lets the wait complete unattended instead of expiring into a pile-up.

**How to reverse.** The decline is deferred, not abandoned. #7454 item 3 holds its evidence bar
(in-suite sampler at ≤2 s, ≥3 single-runner runs, ≥2 runs at N=2, ≥1 at N=3, one adversarial run),
and the verdict line shipped here is the instrument that produces most of it. Say the word and it
ships as its own PR, on measurement rather than on argument.

**Note.** Issue constraint 4 explicitly licenses this shape: *"a gate may therefore let a run proceed
and qualify its output — it does not have to block to be useful."*

---

## DC-1 — Diff justification ships as a report, not a decline (User-Challenge)

**Your stated direction.** A diff-justification check reusing `scripts/lib/test-relevance-paths.sh`,
so a session can tell whether its own diff warrants a full run.

**What the plan ships.** An advisory line naming which `TEST_GROUP` shards the diff touches. No fifth
`*_PATHS` relevance array, and no decline on that basis.

**Why.** Adding a relevance gate is a documented **six-site** change, and the `GATED` table's own
comment records a live defect where a fifth gate left the linter, the harness floor and every
behavioural arm green. The measured ceiling is **4** gated suites out of **167** top-level
`run_suite` registrations (~2.4%) — and your own steer records only 3 declines of 325. The lever is
real but too small to justify that machinery in this PR.

**How to reverse.** If you want the decline form, it is a six-site change and belongs alongside
#7498, which is already queued.
