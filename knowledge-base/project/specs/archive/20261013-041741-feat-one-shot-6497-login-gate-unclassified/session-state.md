# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-16-fix-login-gate-unclassified-dead-end-plan.md
- Status: complete
- Companions: specs/feat-one-shot-6497-login-gate-unclassified/{tasks.md,decision-challenges.md}

### Errors
None blocking. Two self-corrections during planning: an `Edit` failed on a typo in the match string
(recovered); and an unaccounted file state was resolved by diffing against HEAD rather than proceeding
on assumption.

### Decisions
- **Measured rather than derived.** Ran `docker login` failure modes against a live `registry:2` and fed
  the output through the REAL classifier. This falsified 3 of the brief's 5 proposed keywords
  (`not a TTY` is actually `non-TTY device`; `credential helper` never appears; the daemon string was
  unreproducible), and ruled out the brief's leading hypothesis variant: a config-dir EACCES already
  classifies as `transport` (the arm matches `permission denied`), so observing `unclassified` EXCLUDES it.
- **#6497's cause is FALSIFIED, not fixed.** The 2026-07-16 08:15Z re-bake was the experiment the htpasswd
  hypothesis implied. htpasswd now matches on both users AND `login_failed` continues — so the htpasswd
  causation is refuted, and #6497's own AC11 is red exactly as its body predicted. Two shipped
  `zot-registry.tf` comments now assert a refuted causation, in the very file whose false comment started
  this thread.
- **Hatch fires on EVERY failed login, not `unclassified`-only.** This contradicts a capitalized instruction
  in the brief, but serves its stated goal ("so this can never dead-end again"), which the narrow gate
  defeats: both surviving hypotheses share the measured prefix `error saving credentials`, so both would
  classify as `cred_store`, the hatch would never fire, and `cred_store` would silently become
  `unclassified` under a new name — in the PR that exists to drain it. Recorded as UC-3 for `/ship`.
- **Declined the successor issue as a duplicate** (#6497 and #6122 already own "zero pulls"); met the intent
  via a correcting comment on the closed zot-mirror connector issue, whose gate only ever measured the push
  side. Recorded as UC-1.
- **Verified the apply path by the right question** — not the `-target` grep that famously passes while its
  conclusion is false. `apply-deploy-pipeline-fix.yml` is `on: push` with `ci-deploy.sh` in `paths:`, so the
  fix ships on merge.

### Components Invoked
`soleur:plan`; `soleur:deepen-plan`; agents: security-sentinel, spec-flow-analyzer,
observability-coverage-reviewer, user-impact-reviewer, verify-the-negative sweep, test-harness research,
zot-issue research; `gh`, `docker`, `jq`, `git`; deepen-plan halt gates 4.5/4.55/4.6/4.7/4.8/4.9 (all pass).
