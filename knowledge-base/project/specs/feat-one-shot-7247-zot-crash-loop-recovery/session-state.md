# Session State

> ## ⚠️ SUPERSEDED 2026-08-06 — read this before anything below
>
> Everything below was written BEFORE two descopes and describes work that is **not in this PR's
> diff**. It is retained as the record of what was measured, not as a claim about what shipped.
>
> - The `registry-userdata-budget.sh` gate fix, its test suite and the `infra-validation.yml`
>   changes were **reverted out** — PR #7300 was already fixing the same defect.
> - The `scripts/lint-diagnosis-claims.sh` widening was **also reverted**, and split to **#7310**:
>   once working it correctly flags the message only #7300 removes, taking a BLOCKING lint's
>   census (2) above its ratchet baseline (1) until #7300 merges.
>
> What this PR actually ships: the recut runbook's `user_data` precondition, the #7287 body +
> comment corrections, and two filings (#7309, #7310). It closes no issue.
> Authoritative status lives in `tasks.md`, not here.

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-06-fix-registry-userdata-budget-measures-unstripped-render-plan.md
- Status: complete
- Draft PR: #7303
- Branch base: `546294c1f` (PR #7290, D10 gate PASS condition)

### Errors
- **The collision that forced the descope (added 2026-08-06).** `one-shot`'s Step 0a.5 gate cleared
  the INVOKED issues (#7247 / #7287 / #7278). Planning then correctly re-diagnosed the defect and
  re-targeted **#7299**, which no gate had checked — so the duplicate PR #7300 was not found until
  a `test-all.sh` contention banner named its worktree. **A work target discovered AFTER the
  collision gate runs is not covered by it.**
- First `Write` of the plan was blocked by the IaC-routing PreToolUse hook: an acceptance criterion
  listed `doppler secrets set` as a *prohibited* token and the detector matched it literally.
  Reworded to "manual secret write"; no scope change.
- An initial `awk` probe for the continuation-comment claim reported a false hit at line 1 (unset
  `prev` compared as `0`). Caught and re-run in Python: true result is **0 hits against 11 at-risk
  continuation lines**. The bad figure never reached the plan.
- `decision-challenges.md` cited `tests/scripts/lib/test-registry-gate-mutation-battery.sh`; the real
  path is `tests/scripts/test-registry-gate-mutation-battery.sh`. Caught by the citation sweep and
  corrected.
- No blocking errors *at plan time*. All plan/spec gates passed; every cited AGENTS rule ID resolves
  to an active rule; all cited paths resolved except the to-be-created test file and the
  deliberately-absent `spec.md`. This line predates the collision above, which WAS blocking and
  cost the branch its primary deliverable.

### Decisions
- **Deliverable is (a) a code/infra change, not (b) a gated `workflow_dispatch`.** The recut is not
  ready on three independently-verified counts: #7287 declares #7278 a *rollback dependency*;
  Hetzner `cx23` was probed unorderable in `hel1-dc2` (the registry's own datacenter); and five
  pre-first-fire re-verifications are declared REQUIRED. The ARGUMENTS' readiness check on "the
  GitHub environment's required-reviewer set" is **not applicable** — the `registry_luks_recut` job
  deliberately has no `environment:` (an unprovisioned one silently auto-approves, DP-11 F8).
- **The original premise was stale.** #7274 already shipped the `zot_last_err` widening (ranked
  tiers, `head -c` for `tail -c`, `zot_last_err_src`). Live telemetry shows the running host emits
  none of #7274's or #7283's fields, so both merged fixes are **inert** — the registry is
  cloud-init-only (ADR-096), so the only delivery vehicle is destroy-and-recreate.
- **The actual defect:** `registry-userdata-budget.sh` renders the cloud-init template *without* the
  `replace(..., local.registry_rationale_strip, "")` that `zot-registry.tf:451-494` applies. It
  measures 36,404 B ("OVER CAP", rc=1) for a payload terraform actually renders at 9,404 B against
  a 32,768 B cap. This falsifies #7299's P1 premise and its suggested remedy.
- **Scope honesty made explicit.** The fix clears 1 of 4 blockers, and that blocker is *documentary*
  — no workflow job invokes the gate as a precondition, and the CI job that does runs
  `continue-on-error: true`. Reviewers flagged the v1 Overview as overselling leverage; v2 states it
  plainly.
- **The `zot-registry.tf` comment edit was cut, not fixed.** Both review panels fired on it; the
  "ONE COPY" claim stays true post-fix and the v1 acceptance criterion was vacuous (phrase is
  line-wrapped). Cutting it dissolved four ACs, one test arm, and the plan's top risk row.
- **Two pre-existing fail-open paths folded in.** The gate exits 0 when terraform is absent, and its
  CI job swallows every exit code. #7302's body already claims the latter was fixed.

### Live state measured during planning (2026-08-05 23:00Z)
- `zot_restarts` 12,087 → 12,668 over 12 h (~4.0/min); `boot_id` unchanged — no reboot, no replace.
- `ping_rc=0`, `state_status=running`, `oom_killed=false`, `exit_code=0` — non-OOM signature holds.
- **`pcent` climbed 96 → 99 → 100 between 20:35Z and 22:00Z and stayed at 100.** The store
  filesystem is now full — a material worsening from the 89% in the #7247 thread at 14:20Z.

### Triage pointer — the lever that measures this incident (added 2026-08-06, #7278/ADR-172)

The line above stops at *"the store filesystem is now full"* and nothing in this branch could say
**what is filling it**. That is not an oversight of this spec: `SOLEUR_ZOT_DISK` reports `pcent`
with **no per-path breakdown**, so the telemetry this triage rests on structurally cannot answer
it, and every write-shaped remedy (tighten the keep-set, force a GC, resize) needs a host config
change, i.e. a cloud-init re-run, i.e. a host **replace** — which is fatal while the LUKS recut is unfired (#7287).

**#7278 ships the read-only half of that answer.** Before proposing any further remedy on this
issue, dispatch it and read the number:

```
gh workflow run registry-zot-inventory.yml
```

It runs from GitHub Actions only, `GET`/`HEAD` with pull-only credentials, no `docker login`, no
host change and no Terraform. It walks the OCI API over the existing CF-Access-gated `registry.`
ingress, emits `SOLEUR_ZOT_INVENTORY` to Better Stack, requires a readback before going green, and
**comments the line and its interpretation onto #7247** — this issue.

Three constraints on reading it, because the failure mode of this measurement is a confident wrong
number:

- Require `enumeration_complete=true`. A prototype sweep run from a workstation on 2026-08-06
  returned 14.78 GB manifest-referenced against ~56 GB used — but with **12 manifest errors**, so
  `enumeration_complete=false` and it licenses **no** conclusion. The errors are consistent with
  the ~4.8/min restart loop interrupting the sweep, which is why the shipped enumerator retries.
- `delta_gb` is an **upper bound on unreferenced bytes**, not a measurement of them. Named
  candidates with different remedies: zot's dedupe cache DB, and orphaned `.uploads/` staging.
  **Assert no cause from it.**
- A `delta_gb` under ~3 GB is **not distinguishable from zero** — `pcent` is `used/(used+avail)`
  and excludes ext4's root reserve (~2.95 GB on 59 GB).

**What #7278 did NOT deliver, so it is not proposed here as available:** `restart`, `push-config`
and `reclaim` are all **BLOCKED ON A PROVISIONING EVENT**. `reclaim` is additionally blocked
today on its own terms — zot's deny-by-default `accessControl` grants the pull user `["read"]` and
the push user `["read","create","update"]`, so **no user holds `delete`** (measured) and manifest
DELETE is refused whatever the pinned build supports. And restart-as-remedy is refuted by this
spec's own evidence: `--restart unless-stopped` has already restarted zot **15,640** times into
the same full volume.

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `Explore` x2, scoped advisor consult, 6-agent review panel (`dhh-rails-reviewer`,
  `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`,
  `spec-flow-analyzer`, `cto`)
- Live data: `scripts/betterstack-query.sh` via Doppler `prd_terraform` (12h + 3h windows),
  `gh issue/pr view` x10, `terraform console` measurements of both renders, `cloud-init schema`,
  `bun test cloud-init-user-data-size.test.ts`, `git-data-render-strip-parity.test.sh`
- Commits: `7d1a5abe8` (plan + tasks + decision-challenges), `c7432f53e` (deepened plan). The
  branch has since grown to ten commits, including the add-then-revert pairs for the descoped
  gate fix and lint widening.
