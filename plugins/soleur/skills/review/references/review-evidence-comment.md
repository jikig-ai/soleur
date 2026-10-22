# Review-Evidence comment and the agent-review merge gate

Loaded by `soleur:review` step 3 (after `emit-review-trailer.sh` succeeds) and linked from the arm steps of
`soleur:ship` and `soleur:merge-pr`. This is the one copy of the gate text; the skills link here.

## The gate

Soleur's operators are non-technical and cannot review code, so the merge gate is **agent review plus green CI,
never a human approval** (CTO ruling 2026-10-22; `rf-never-skip-qa-review-before-merging` already defines
review-gated as "`soleur:review` ran and its findings are fixed"). This does not extend to production-mutating,
destructive or irreversible commands: those still need the explicit per-command go-ahead that
`hr-menu-option-ack-not-prod-write-auth` requires, whatever the review said.

Domain surfaces additionally need a binding ruling from the owning agent before the merge, obtained through the
ruling route in [technical-ruling-delegation.md](../../brainstorm-techniques/references/technical-ruling-delegation.md),
and recorded in the comment's `domain-ruling` field:

- legal text, the Art. 30 register, privacy, terms or DPA: `soleur:legal:clo`;
- `infra/`, terraform, migrations, production writes, destructive operations or `.github/workflows`:
  `soleur:engineering:cto`, plus the review panel's infra and data seats;
- auth, secrets and URL or input-validation code: `soleur:engineering:review:security-sentinel` is in the panel;
- the `single-user incident` and `aggregate pattern` tiers add `soleur:engineering:review:user-impact-reviewer`.

## The comment

A commit trailer is invisible to a reader of `gh pr merge`, so post one PR comment after the trailer. A comment is
not a push, so it is also safe on a PR already in the merge queue. State what actually ran, never more, and fill
every placeholder from the review you ran (do not post the template as written):

```bash
gh pr comment <number> --body "Review-Evidence: head=<short sha reviewed>; soleur:review ran; coverage=<full|degraded|partial-by-ruling>; tier=<resolved tier>; seats=<agents that returned>; missing=<names or none>; domain-ruling=<none|CLO|CTO>; unresolved-P1-P2=<n>; merge gate = agent review + green CI; no human approval required for non-production-mutating changes"
```

This is a self-attestation by the reviewing agent, not tamper-proof: anyone with comment access can post the same
text and it survives later pushes. Read it against the head it names; a head that differs from the PR head, a
`coverage` other than `full`, or a nonzero `unresolved-P1-P2` is not a pass.
