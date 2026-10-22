# Review-Evidence comment

Loaded by `soleur:review` step 3, after `emit-review-trailer.sh` succeeds.

**Then post the evidence where a merge can see it.** The trailer is a commit trailer, so a reader of
`gh pr merge` cannot see it. After the trailer, post one PR comment (a comment is not a push, so it is also
safe on a PR already in the merge queue). State what actually ran, never more:

```bash
gh pr comment <number> --body "Review-Evidence: soleur:review ran; coverage=<full|degraded|partial-by-ruling>; tier=<resolved tier>; seats=<agents that returned>; missing=<names or none>; domain-seat=<none|CLO|CTO>; unresolved P1/P2=0; merge gate = agent review + green CI; no human approval required"
```

The merge gate is agent review plus green CI, never a human approval: Soleur's operators are non-technical and cannot review code (CTO ruling 2026-10-22; `rf-never-skip-qa-review-before-merging` already defines review-gated as "`soleur:review` ran and its findings are fixed"). Domain text and risky surfaces keep a named agent seat: legal text, the Art. 30 register, privacy, terms or DPA → `soleur:legal:clo`; `infra/`, terraform, migrations, production writes, destructive operations or `.github/workflows` → `soleur:engineering:cto` plus the panel's infra and data seats; auth, secrets and URL/input-validation code → `soleur:engineering:review:security-sentinel`; the `single-user incident` and `aggregate pattern` tiers add `soleur:engineering:review:user-impact-reviewer`.
