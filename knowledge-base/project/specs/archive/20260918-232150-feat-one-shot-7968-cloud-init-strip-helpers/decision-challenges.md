# Decision challenges — feat-one-shot-7968-cloud-init-strip-helpers

Persisted by `plan-review` (headless; ADR-084 routing). Mechanical findings were auto-applied to the
plan; the entries below are Taste / User-Challenge class and are surfaced, not applied.

## T1 — env-var seam vs scratch-tree symlinks (Taste, CTO devex panel)

- **Finding:** replace the mutation battery's three-deep scratch tree + three symlinks with a one-line
  seam in the suite, `const REPO_ROOT = process.env.CLOUD_INIT_SUITE_REPO_ROOT ?? join(import.meta.dir, "..", "..", "..")`,
  so the battery copies the suite flat and sets the env var.
- **Disposition (session):** declined. It adds a harness-serving seam to production test code — the
  same objection DHH raised (P0) against `// MUT:` markers in the SUT, which the plan removed. The
  symlinked scratch tree is verified on this branch (47/47) and needs one comment naming the depth
  invariant. Either choice is a taste call with no property difference; the operator may flip it.
