# Decision Challenges — feat-one-shot-8203-vendor-pin-required-check

Recorded by headless `/plan` (pipeline path — no AskUserQuestion). `ship`
Phase 6 renders these into the PR body / `action-required` issue.

## DC-1 — `requires_cpo_signoff: true` is set but no CPO agent ran (headless)

- **Context:** `## User-Brand Impact` declares `single-user incident` (the
  vendored corpus is compliance surface — gdpr-gate PII patterns +
  legal-generate attorney-drafted templates — so a wrong-but-green merge on it
  is a per-user legal artifact). The threshold sets
  `requires_cpo_signoff: true` in the plan frontmatter.
- **What the pipeline could not do:** no Task/agent surface exists in this
  headless planning subagent, so no CPO consult ran at plan time, and no
  brainstorm exists to carry a sign-off forward from.
- **Default if unchallenged:** proceed — the change is CI-gating machinery
  (no user-facing artifact changes), the single-user-incident declaration is
  conservative (it widens review surface via `user-impact-reviewer` at PR
  review rather than narrowing it), and the #5585 sibling shipped under the
  same threshold.
- **Challenge if:** the operator judges a required-check addition on the
  compliance vendoring path to need product-owner ack before `/work`.

## DC-2 — Naming choice: `vendor-pin-required` as the required context

- **Context:** the issue allows "`verify-upstream-blobs` (or an aggregator
  context wrapping it)". The plan registers `vendor-pin-required`, matching
  the `<thing>-required` convention (`tenant-integration-required`,
  `sentry-destroy-required`) — the context string is public ABI once required.
- **Default if unchallenged:** `vendor-pin-required`.
- **Challenge if:** a different name is preferred (e.g.
  `vendor-pin-verify-required`); renaming pre-merge is a four-file sweep
  (workflow job, .tf, canonical JSON, required-checks.txt) and cheap now,
  expensive after.
