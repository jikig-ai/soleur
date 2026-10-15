# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-18-fix-inngest-bootstrap-v1-1-23-bake-pin-plan.md
- Status: complete

### Errors
None. All deepen-plan halt gates (4.5/4.55/4.6/4.7/4.8/4.9) passed with no telemetry emitted.

### Decisions
- Corrected drift provenance (verified vs git/gh/GHCR): inngest-bootstrap.sh drifted via #6178 bundle commit 119861998 (+101/-27); vector.toml drifted via a DIFFERENT commit 938863a9d (PR #6610 / issue #6604 LUKS luks-monitor Source-4 entry). The inngest-cutover-flip marker was ALREADY baked in v1.1.22 — it is NOT the justification. Both carrier files still differ from the baked image, so the rebake is genuinely needed.
- Tag target is current origin/main HEAD (68c2ff458), not the bundle commit 119861998 (4 commits landed since). Plan asserts git merge-base --is-ancestor 119861998 <tag>; forbids tagging the feature branch.
- Load-bearing coupling: drift-guard cloud-init-inngest-bootstrap.test.sh (AC6/AC6b, #4675/#6536) derives the expected tag dynamically → pushing vinngest-v1.1.23 red-lines CI until pins bump. Tag-push + 3-site pin-bump are a coupled unit; merge promptly.
- Latent/safe confirmed: pin bump edits .yml (not *.tf → apply-web-platform-infra.yml doesn't fire); web hosts carry lifecycle ignore_changes=[user_data]; dedicated host re-reads cloud-init only on the dispatch-only inngest-host-replace (a non-goal). Nothing pulls v1.1.23 until the separately-gated force-replace.
- Exactly 3 real pin sites, zero fixture edits: cloud-init-inngest.yml:341, cloud-init.yml:698 + 704. Other v1.x literals (ci-deploy.test.sh, zot-soak-6122.test.sh) are synthetic fixtures — do not bump. Threshold: single-user incident (singleton control-plane host); requires_cpo_signoff: true.

### Components Invoked
- Skill soleur:plan
- Skill soleur:deepen-plan
- Direct premise validation via Bash (git/gh/GHCR/grep) + Read; no sub-agents
