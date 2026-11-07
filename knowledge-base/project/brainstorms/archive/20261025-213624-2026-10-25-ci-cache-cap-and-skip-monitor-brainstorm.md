---
date: 2026-10-25
topic: ci-cache-cap-and-skip-monitor
issues: [10917, 10918, 8856]
branch: feat-ci-cache-cap-and-skip-monitor
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Actions cache cap + rehearsal skip monitor

## What We're Building

Two PRs from three open chores, scoped with the operator (2026-10-25: "all three, #8856 re-framed").

- **PR A, #10917.** Stop the release workflow writing to the Actions cache so the repo stays under its 10 GB cap and stops evicting unrelated caches.
- **PR B, #8856 + #10918.** Make the rehearsal skip probe implement the bound ADR-188 actually states, stop the alert text pointing at work that was cut, and give the probe-broken escalation its own alert title and body.

## Premise checks (verified 2026-10-25)

- #7535 (pre-baked image) is CLOSED, "image cut on measurement": $0 saving on a public repo with standard runners, 0 operator-visible seconds. #7572 is CLOSED. The #8856 alert text and ADR-188 still say the image is owed. Stale remedy.
- ADR-188 bounds skips at "more than 1 in 20 post-merge runs". The probe (`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`) FAILs on any single hit (`hits -gt 0` at the rehearsal source, `g_hits -gt 0` at the guard source) and counts marker lines, not runs. No rate is computed.
- The escalation (`consecutive TRANSIENT`) exits 1 like a skip, so the workflow files it under the skip title. Only the summary text differs.
- #10916 is merged and verified: the streak round-trips via artifact (runs on 2026-10-24 and 2026-10-25).
- `cache-to: type=gha,mode=min` is the only `cache-to` in the repo (`reusable-release.yml:802-803`). No direct `actions/cache` use.

## Key Decisions

All technical rulings: **Ruled by CTO agent, 2026-10-25.**

| Decision | Ruling | Flips if |
|---|---|---|
| Cache backend for release builds | `cache-to: type=inline` + `cache-from: type=registry,ref=<image>:latest`. No `gha` fallback during transition (a dual cache keeps churning the quota). Keep the `mode=min` secret-safety comment: inline holds final-image layers only, so the secret-bearing builder stage stays out. | A real release shows a build-time regression or the registry cache misses on every build. |
| Prune workflow | Rejected. It mutates production state and treats the symptom. | n/a |
| Dockerfile reorder (#5055) | Not needed for this fix. Per-release layers are already last. | Inline cache turns out not to dedupe. |
| `chown -R` → `COPY --chown` | Proposed here; CUT at plan (spec FR2): FR1 alone meets the cap and this changes production image ownership. | n/a |
| Probe bound | Count runs with at least one skip, not marker lines. FAIL when `runs_with_skip * 20 > observed`. | n/a |
| Alert text | Drop "#7535 owed". Point at diagnosing the rc 100/125 declines. | n/a |
| Escalation (#10918) | Own title and body; keep the stable `soleur-skip-persistence-monitor-alert` marker so open-issue dedupe still works. Add a unit case and a wiring property. | n/a |
| Dead-man's switch for the monitor | Out of scope; separate issue. | n/a |

**[Updated 2026-10-25, plan phase] Measured skip history supersedes the earlier "stays red" note.** Of the 12 newest infra-validation main runs, exactly one (2026-10-23, S1, docker rc=100 apt decline) carries a probe marker; the ten newest are clean. With sampling extended to 20 observed runs, 1 skip passes the 1-in-20 bound. The remaining uncertainty is the live verdict, recorded at plan AC11.

## User-Brand Impact

- **Artifact:** the release build cache export (`reusable-release.yml`) and the rehearsal skip monitor (`scheduled-rehearsal-skip-monitor.yml`, its probe, ADR-188).
- **Vector:** a regression in the release build path silently breaks or slows production deploys; a monitor that mislabels or false-greens hides a degraded safety check.
- **Threshold:** single-user incident.

## Open Questions

- Which Dockerfile COPY is the ~776 MB layer? Layer sizes come from #10917 and were not verified; needs a build log. Also whether GHCR layer dedupe makes the inline export near zero (inferred).
- What causes the T5/S1/T17 skips? The rc 100/125 decline is inferred from ADR-188. The plan must start by pulling an actual skip line from an infra-validation run log.
- Why did 7 of 20 sampled runs have no suite output (13 observed)?
- "No build-time regression" can only be proven on a real release after merge.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO recommends two PRs (release cache; monitor), inline registry cache over a prune workflow, and making the probe implement ADR-188's stated rate. Verification against origin/main is listed above; sizes and the skip cause remain unverified.

CPO and CLO were not spawned: internal CI work, no user-facing or legal surface.

## Capability Gaps

None.
