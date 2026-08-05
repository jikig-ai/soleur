# RESUME — #7277 D10 gate PASS condition

Written 2026-08-05. Every path and command below was run and confirmed to resolve before this
file was written; none are recalled from memory.

---

## Paste this to resume

> Resume #7277 from PR #7290. The plan and Phase 0 probe evidence are committed on branch
> `feat-one-shot-7277-d10-gate-pass-condition`; implementation has not started. Read
> `knowledge-base/project/specs/feat-one-shot-7277-d10-gate-pass-condition/RESUME.md` first —
> it carries two measured findings that change the implementation and the safety framing this
> work turns on. Then continue from Phase 1 of
> `knowledge-base/project/specs/feat-one-shot-7277-d10-gate-pass-condition/tasks.md`
> via `/soleur:work <plan-path>`, and carry it through review → QA → compound → ship.

---

## State

| | |
|---|---|
| Branch | `feat-one-shot-7277-d10-gate-pass-condition` |
| Worktree | `.worktrees/feat-one-shot-7277-d10-gate-pass-condition` |
| PR | **#7290** (OPEN, draft) |
| Unpushed commits | 0 — everything is on the remote |
| Done | plan + deepen, Phase 0 partial (0.1, 0.5, 0.6, 0.8) |
| Not started | Phases 1–5 (~29 tasks) + five Phase 0 probes needing a runner |

Artifacts (all confirmed present):

- Plan — `knowledge-base/project/plans/2026-08-05-fix-registry-luks-recut-d10-pass-condition-plan.md`
- Tasks — `knowledge-base/project/specs/feat-one-shot-7277-d10-gate-pass-condition/tasks.md`
- Probe evidence — `knowledge-base/project/specs/feat-one-shot-7277-d10-gate-pass-condition/phase-0-probe-evidence.md`

Targets (all confirmed present):

- The gate — `scripts/registry-pull-path-health.sh`
- Its suite — `tests/scripts/test-registry-pull-path-health.sh`, registered at `scripts/test-all.sh:556`
- The runbook — `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`
- The dispatch — `.github/workflows/apply-web-platform-infra.yml`
- `scripts/registry-restore-from-ghcr.sh` — **absent**, Phase 1 creates it

---

## Read this before writing code

### 1. This is a destroy gate. A fail-open deletes the fleet's only image store.

Ask of every predicate: *what input makes this green while the thing it protects is broken?*
Prefer a positive proof of restorability over an absence-of-error signal. A "could not measure"
outcome is its own **aborting** class, evaluated *before* the comparison — never allowed to read
as safe.

The plan already caught one draft that failed this: a review subagent's first A5 verdict table put
`connection reset mid-upload` in ABORT. That is the literal signature of the live incident, so it
would have re-created the deadlock this work exists to remove.

### 2. The abort/degrade boundary — the single most dangerous line

**Only authorisation and correctness failures abort. Availability failures — reset, timeout, 5xx —
degrade with a named, logged degradation.**

Availability failures *are* the motivating incident. A gate that aborts on them cannot authorise
the recovery it exists to authorise.

### 3. Two Phase 0 measurements that change the implementation

Measured against the pinned crane `v0.20.2`:

- **`NAME_UNKNOWN` does not exist on GHCR.** A missing *repository* returns
  `MANIFEST_UNKNOWN: manifest unknown`, identical to a missing *tag*. Task 0.1 asked for it as a
  distinct string; a classifier branching on it carries a dead arm, and no test may assert a
  string GHCR never emits.
- **Neither `rc` nor the first stderr line discriminates.** Tag-absent, repo-absent and DNS
  failure all exit `1` and all emit the same first line
  (`HEAD request failed, falling back on GET: …`). Classify on the **last** line. Anything
  matching neither known shape is `UNKNOWN` → abort.

The full table is in `phase-0-probe-evidence.md`.

### 4. Why this PASS condition, on evidence

Chosen: **rehearsed restore from GHCR-via-CI** (issue candidate 2). Not on the issue's say-so —
the release pipeline's failing half is measurably the **push into prod zot**, while the
**GHCR-read half works**: `crane digest ghcr.io/jikig-ai/soleur-web-platform:latest` returns
`sha256:b04096d3…`, byte-identical to the digest in the failing run's own error text. The other
three candidates all depend on the failing component, or on a mirror that does not exist, or on a
credential that is structurally unmintable.

### 5. A second blocker the issue never named

Deleting the unconditional refusal is **not sufficient**. The `zot_served == 0` arm aborts during
exactly the crash-loop the recut recovers from. The plan drops the whole Sentry arm, which also
resolves the dark `ghcr-fallback` operand by dropping the signal.

---

## Scope boundaries — do not cross

- **Do NOT dispatch the recut.** No `gh workflow run apply-web-platform-infra.yml`. Firing it is a
  separate operator-gated decision.
- **No `terraform apply`**, targeted or otherwise. The registry host carries a standing
  pending-REPLACE in any untargeted plan (`user_data` is ForceNew, no `ignore_changes`), and a live
  probe on 2026-08-05 found `cx23` orderable in nbg1-dc3 but **not hel1-dc2**, where the host runs —
  a recreate there fails on stock.
- **ADR-096 clause (g) stays open.** It records a broader debt than #7277, which covers only the gate.
- **`zot_last_err` widening stays with #7247**, not here.

---

## Done-signal

The runbook's own staleness check is the contract. It currently returns `1`:

```
grep -c "no valid PASS condition" scripts/registry-pull-path-health.sh
```

When this work lands it must return **0**, and the ⛔ blocked-state banner at the top of
`registry-luks-recut-6929.md` must be deleted — the banner says so itself
(`0 = THIS BANNER IS STALE, delete it`). It is deliberately a grep, not an issue state.

Also: the literal phrase must appear **nowhere** in the gate file, including historical commentary
(task 2.3).

---

## Gates (commands confirmed to resolve)

```
bash scripts/test-all.sh scripts        # TEST_GROUP arg is supported (test-all.sh:119)
bash tests/scripts/test-registry-pull-path-health.sh
```

**Measured baseline 2026-08-05** (re-run, not recalled): the D10 suite is
`EXIT=0`, **26 passed, 0 failed** on the current tree. Phase 2.1 rewrites it, so expect the count
to change — but a fresh session that sees anything other than 26/0 *before* editing has inherited
a regression from elsewhere, not from this work.

Before merge, re-derive the ADR ordinal against freshly-fetched `origin/main` (task 5.3) —
**ADR-169** was next-free at 2026-08-05 (168 highest, 167 absent), but ordinals have collided
three times recently, so a branch-picked one is provisional until re-measured.

PR body must say `Closes #7277`.

---

## Live context (all OPEN as of 2026-08-05)

- **#7247** — zot crash-looping. `pcent=89` and climbing, `zot_restarts=9281`, ~6.5 GB headroom.
  **9 consecutive blocked releases**; production is up but serving the 2026-08-04 11:09 build
  (`version 0.249.4`, `build_sha f838839e`). This is what #7277 unblocks.
- **#7278** — the restart lever. Its activation vehicle is this recut, so it is downstream of #7277.
- **#7286** — inngest down, opened 2026-08-05 07:17Z. **Not investigated at all.** Scheduled crons
  and armed reminders may not be firing. Independent of the registry work; flagged so it is not
  quietly lost.

Already merged this session: **#7280** (`d0295964f`) fixed the registry `user_data` cap breach
(34,628 B against a 32,768 B cap), which removed the *other* blocker on the recut — every
host-creation path was failing at the Hetzner API regardless of its own gate.

---

## Five Phase 0 probes still to run

They need a runner or a throwaway registry; a workstation probe cannot establish runner capability.

| # | What |
|---|---|
| 0.2 | `GITHUB_TOKEN` + `packages: read` can `crane ls`/`digest` the GHCR repos **from a runner** |
| 0.3 | Signature mechanism — copy `sha256-<digest>.sig` vs re-sign keyless; does `cosign verify` check `critical.identity.docker-reference`? |
| 0.4 | Throwaway-zot feasibility for the full pin set — per-pass wall-clock and peak runner disk |
| 0.7 | A4 wiring — `zot_mirror_verdict` makes **zero** network calls; the detector must run first or the predicate can never abort |
| 0.9 | `crane validate --remote` over plain-HTTP loopback; if it fails, A2 has no blob-completeness verifier and needs a recorded fallback **before Phase 2** |
