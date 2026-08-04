# feat(release): add a promotion dashboard to the deploy pipeline

Synthesized fixture (see `cq-test-fixtures-synthesized-only`). Greenfield tooling,
dense with `production` / `deployed` / `live` / `release` / `deploy` / `blocked`,
describing no event. Do not add explanatory prose here: this file must contain no
vocabulary from either half of the gate, or it stops pinning anything.

brand_survival_threshold: aggregate pattern

## Summary

Operators cannot currently see which release is live in production without
opening the deploy logs. This plan adds a dashboard that reads the promotion
history and renders the currently deployed version per environment.

## Non-goals

Changing how releases are promoted, or when the pipeline holds one back. The
promotion gate itself is out of scope; this is a read-only view over what the
pipeline already records.
