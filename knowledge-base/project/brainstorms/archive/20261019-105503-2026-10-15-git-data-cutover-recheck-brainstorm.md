# Brainstorm: git-data cutover resume (2026-10-15)

## What We're Building
Three read/design artifacts under `knowledge-base/project/specs/feat-git-data-cutover-recheck-8211/`: the live precondition re-read,
the rehearsal run sheet, the owner command chain. No code.

## User-Brand Impact
- **Artifact:** the git-data flip, rollback and rehearsal dispatches of `git-data-cutover.yml` and the credential chain feeding them.
- **Vector:** a wrong or mis-ordered production step silently strands or exposes a user's repository data, or erases it before the soak ends.
- **Threshold:** `single-user incident`.

## Key Decisions
- The brief's host facts were stale: the host was rotated again (run 38583657167, server 170370833), so the rotate leaves the owner chain.
- Two undisclosed flip blockers found: `GIT_DATA_EMITTER_FLOOR` / `GIT_DATA_DENY_FLOOR` unset; `DOPPLER_TOKEN_GIT_DATA_FLAG` absent.
- One flip and one rollback dispatch cover both hosts (Ruled by CTO agent, 2026-10-15).
- #9943 deferred to its own PR (Ruled by CTO agent, 2026-10-15).
- The rehearsal flip closes the rotate door (#10207 guard): the d6 stamp must still be in the 100-run window at the real flip.

## Open Questions
- Sentry rule 1310055 cannot be read headlessly (needs `SENTRY_ACTIONS_RO_TOKEN`, a GitHub secret).
- Per-host attribution of `git_data_ssh_client` is impossible from Better Stack; web-2 rows do not appear under any host name.
- No command is defined for steps 5, 6 and 7 of the owner chain.
- 2026-11-04 flip deadline is at risk (owner and CLO call).

## Domain Assessments
**Assessed:** Engineering, Legal
### Engineering
**Summary:** Ruled by CTO agent on the two technical forks above.
### Legal
**Summary:** No new legal question; the CLO Level 2 ruling of 2026-10-12 is carried into the run sheet unchanged. No legal document edited.
