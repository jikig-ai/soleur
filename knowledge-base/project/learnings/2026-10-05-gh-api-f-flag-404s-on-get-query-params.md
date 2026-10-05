---
title: "gh api -f flags 404 on GET endpoints where params must be query strings"
date: 2026-10-05
type: learning
tags: [gh-cli, verification-commands, plan-probes]
related: 2026-04-15-gh-jq-does-not-forward-arg-to-jq.md
---

# `gh api -f` is not interchangeable with a literal query string

While writing a `discoverability_test` probe, I wrote:

```bash
gh api repos/OWNER/REPO/actions/workflows/ci.yml/runs -f branch=main -f per_page=1 --jq '.workflow_runs[0].conclusion'
```

It returned **404 Not Found** — twice, on two different endpoints — while the
literal-URL form succeeded:

```bash
gh api 'repos/OWNER/REPO/actions/workflows/ci.yml/runs?branch=main&per_page=1' --jq '.workflow_runs[0].conclusion'
```

The `-f/--field` flags are documented to go to the query string for GET
requests, but on this gh version they did not produce the same request — the
endpoint itself 404'd (a param-shaping failure reads as "route not found", not
"params ignored"). Two takeaways:

1. **Run every literal command a plan prescribes before committing the plan** —
   the probe-verb gate checks well-formedness, never that the command returns
   what the plan claims (this caught itself only because the sharp-edges rule
   forced a live run).
2. For `discoverability_test.command` specifically, `&` in a literal query
   string is *also* banned (Check 10's shell-active byte reject), so a
   multi-param `gh api` probe is awkward either way — prefer a `grep`-shape
   probe over a repo file, or a committed wrapper script, rather than fighting
   both constraints at once.

Sibling traps in the corpus: `gh --jq` does not forward `--arg` to its
embedded jq; `gh run list --json` returned stale rows where `gh api` agreed
with REST.
