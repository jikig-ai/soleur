# Merge queue canary log

Evidence for ADR-270 (merge queue with advisory CodeQL), tracked on #9454. One entry per canary; each canary PR is
docs-only and exists to exercise the queue or its admin bypass on `main`.

| Canary | Path | Recorded |
|---|---|---|
| 1 | Admin bypass: this file's PR merged with `gh pr merge --admin` past the queue rule | result on #9454 after the merge |
