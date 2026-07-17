# Decision Challenges — feat-one-shot-inngest-cutover-descoped-6551-6556

Surfaced by `soleur:plan-review` (6-agent panel, single-user-incident threshold), 2026-07-17.
Per ADR-084, these are Taste / User-Challenge decisions where a reviewer argued the operator's
**stated direction** should change. The operator's direction is the DEFAULT — these are recorded
for operator visibility, NOT silently applied. `ship` Phase 6 renders this into the PR body and
files an `action-required` issue.

## UC1 — Split the bundle (DHH) — User-Challenge
- **Operator's stated direction:** "Bundle these five OPEN issues into ONE cleanup PR."
- **Challenge (DHH):** the "shared files + one dependency" rationale is thin; the only real overlap
  is #6555 + #6556-P2 both touching `inngest-bootstrap.sh`. #6555 (the highest-blast-radius item)
  gates four safe fixes. Ship #6553 (one-line guard widen + ADR) on its own today; split #6555 out.
- **Panel position:** DHH alone argued to split; code-simplicity, spec-flow, architecture, and CTO
  reviewed the bundle as-is without demanding a split.
- **Default (kept):** ONE bundled PR, as directed. The plan-review mechanical fixes make each fix
  independently correct and cleanly revertable within the bundle.
- **If the operator wants to split:** #6553 (guard + ADR) is the cleanest standalone; #6555 is the
  natural second PR (its blast radius + cloud-init immutable-redeploy is the isolation argument).

## UC2 — #6555 approach: delete-the-threading vs fail-closed-only — User-Challenge (panel SPLIT)
- **Operator's stated direction:** "Preferred CTO fix from the plan: write DOPPLER_PROJECT into
  /etc/default/inngest-server … the unit could drop --project — deleting the ci-deploy + sudoers
  threading rather than extending it."
- **Challenge (DHH + code-simplicity C2):** the migration touches ~20 sites (6 `--project` + 2 env
  paths + tests) yet does NOT fix the named `:47` render-time default trap — worst of both worlds on
  a dark host. Prefer the smaller fail-closed-`:47` alternative; or at least defer the `--project`
  migration and ship only the dead-guard removal.
- **Counter (CTO + architecture, ENDORSE the CTO fix):** delete-the-threading is the better
  long-term devex call — it eliminates the byte-parity sudoers mirror (a recurring high-fragility
  tax) and collapses 6 drift-prone `--project` sites; the scoped `DOPPLER_TOKEN` (cloud-init-inngest.yml:384)
  makes dropping `--project` safe. The `:47` residual is recorded as SOLEUR-DEBT with its detector.
- **Default (kept):** the CTO delete-the-threading fix, as directed, with the plan-review mechanical
  hardening (2 standalone unit files added, fail-closed non-empty check, dead-substitution cleanup,
  `:47` SOLEUR-DEBT marker). The `:47` trap is explicitly out of #6555's stated scope.

## T2 — #6551 `vector_config_*` instrument: ship (gated) vs drop from bundle — Taste (panel SPLIT)
- **Challenge (DHH):** scope-creep on an investigation-only issue; the plan pre-wrote its own escape
  hatch ("gated", "ship alone", "drop if reviewer prefers"). Drop it; leave the finding as a next-step.
- **Counter (architecture (e); CTO §1 conditional):** the read-only discriminator is "the right call"
  (near-zero blast radius) — BUT the naive whole-file `sha256sum` can NEVER match (`@@HOST_NAME@@` sed
  at inngest-bootstrap.sh:708) and must be re-specced to a Source-definition-section hash. It is also
  latent until the next dedicated-host bake (CTO §5).
- **Default (kept, gated + corrected):** keep it recommended-but-gated with the corrected
  Source-section-hash spec; #6551 stays OPEN regardless. Final ship/drop decision deferred to
  CPO / deepen-plan.

## T1 — #6556 P1 CI-guard minimal shape (code-simplicity A1) — Taste
- **Challenge (code-simplicity A1):** the ExecStart-basename derivation + exclusion-with-reason
  registry is a mini-framework; the real gap is only that the test scans `infra/*.sh` alone. Scan
  explicit `logger -t`/`SyslogIdentifier=` declarations across the three file types; drop the
  basename branch and its exclusion list; keep `webhook` as one documented hardcoded entry.
- **Tension:** #6556's own text says "keep SYSTEMD_UNIT_IDENTIFIERS only for identifiers no source
  line can yield" and the issue TITLE is about units with no `SyslogIdentifier=` tagging as their
  ExecStart basename — so some basename handling is arguably operator-directed.
- **Default:** /work + deepen-plan pick the minimal shape that satisfies #6556's "explicit-exclusion
  half" + coverage extension without a general ExecStart parser. Surfaced for confirmation.
