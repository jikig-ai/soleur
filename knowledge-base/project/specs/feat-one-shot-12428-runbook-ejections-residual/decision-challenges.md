# Decision Challenges — feat-one-shot-12428-runbook-ejections-residual

Sequential-fallback: no Task/subagent spawn exists in this harness, so
`soleur:engineering:cto` rulings were made inline by the pipeline runner applying
the cto agent definition's lens (evidence over convenience, stricter default when
evidence is thin); `Reviewed-Coverage: sequential-fallback` is disclosed in the PR
body.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Ledger entry scope in runbook §2: record the criterion-a result alone, with criteria b/c/d named `unmeasured` and the re-ruling operator-reserved, vs. a fuller summary | technical | Ruled by CTO agent, 2026-11-08: criterion-a alone with siblings named unmeasured - the re-run measured criterion a only (receipts/rerun/README.md: criteria b, c and d stayed unmeasured and the go/no-go re-ruling is operator-reserved), so any wording implying a full re-ruling asserts a fact the instrument never produced |
| §4 residual placement: sibling bullet at the end of the limits list vs. extending the existing residual sentence inside the `no-run` bullet | technical | Ruled by CTO agent, 2026-11-08: sibling bullet - the existing residual sits inside a bullet about the per-sha `?head_sha=` collect read (existence-on-empty); the ejections residual is a different listing (window-class) with a different consequence (population under-count biasing the bound toward a false GO), and folding it into that sentence attaches a window-listing claim to a per-sha-read frame |
| Issue disposition: `Closes #12428` in the PR body vs. `Ref #12428` and leaving it open | technical | Ruled by CTO agent, 2026-11-08: Closes #12428 - the issue's deliverable is the recorded residual itself (its body asks for the record and names reopen-before-next-re-run as the re-evaluation criterion, which a closed issue still permits); leaving it open would track nothing further |
| Bound-driving attribution in the ledger: not-evaluable bucket over dropped runs | technical | Ruled by CTO agent, 2026-11-08: attribute to the not-evaluable bucket and state runs_via=head-sha 300/300 - replay-summary.txt shows zero index drops this window, so the corroboration path went unexercised by a live drop and the residual worst-case load is classifier coverage (histograms.txt route counts), not reads |
