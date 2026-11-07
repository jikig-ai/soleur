# Decision Challenges — CodeQL alert #216

No operator-class decisions arose and no contested technical fork required
arbitration: the operator scope named the remediation family (constrain the
untrusted checkout per repo precedent), and the *choice within* that family was
settled by evidence, not taste — `github/codeql`'s
`UntrustedCheckoutMedium.ql` + `UntrustedCheckoutQuery.qll` were read directly
and show the query has no `if:` sanitizer and no `persist-credentials`
sanitizer, so the only clearing fixes are structural (ref expression no longer
names a head-SHA source, or no checkout). Between the two structural shapes —
(a) gate step + validated `deploy_sha` ref, (b) remove the checkout and read
tree files via the contents/compare APIs — (a) was chosen because it preserves
the `deploy-arm.sh` `--depth=1 origin <sha>` log contract and the file-parse
logic, at less blast radius. Recorded here as context for reviewers; the full
alternatives analysis is in the plan's Research Insights.
