---
title: A custom gitleaks rule with a default-pack ID silently replaces the default rule; synthesized secret fixtures must be assembled at runtime
category: security-issues
tags: [gitleaks, secret-scanning, push-protection, test-fixtures]
pr: 5078
issue: 5079
date: 2026-06-09
---

# A custom gitleaks rule with a default-pack ID silently replaces the default rule

## Problem

PR #5078 added a custom `.gitleaks.toml` rule `id = "slack-webhook-url"` for Slack
incoming-webhook URLs, with a comment claiming the shape was "not in the default pack"
(copied from the adjacent Discord rule, where the claim is true). The gitleaks default
pack (v8.24.2) ALREADY ships a rule with that exact ID covering both
`hooks.slack.com/services/...` AND `hooks.slack.com/workflows/...`.

Under `[extend] useDefault = true`, a child rule whose ID matches a default-pack rule
**replaces** it entirely. Two silent detection regressions followed:

1. `/workflows/` webhook URLs were no longer detected anywhere in the tree (the custom
   regex matched `/services/` only).
2. The custom rule's per-rule allowlists (fixtures, KB plans/specs) now applied where
   the default rule previously fired unconditionally — contradicting the file header's
   own principle ("default rules do NOT inherit our per-rule allowlists — intentional").

Two review agents (pattern-recognition, code-quality) independently confirmed the
shadowing empirically with the pinned CI binary. Plan-time verification had only
grepped the repo config, not the inherited default pack.

## Fix

Rename the custom rule with a `soleur-` prefix (`soleur-slack-webhook-url`, matching
the existing `soleur-byok-key` precedent) so it is additive, and pin the no-shadow
property with a fixture test (`plugins/soleur/test/gitleaks-rules.test.sh`) asserting
BOTH rules fire on a canonical URL and `/workflows/` stays covered by the default rule.

## Rules

- **Before adding a custom gitleaks rule, check the DEFAULT pack for the same ID**, not
  just the repo config: `gitleaks dir <fixture-with-shape> --no-banner` (no `--config`)
  shows which default rule fires and its ID. If a default rule exists, use a
  `soleur-`-prefixed ID unless shadowing is explicitly intended and documented.
- **"Not in the default pack" comments must be verified per-shape**, not inherited from
  a sibling rule the block was copied from.

## Corollary: synthesized secret-shaped fixtures must be assembled at runtime

The first version of the fixture test embedded synthesized webhook URLs as contiguous
literals. GitHub push protection rejected the push (3 "Slack Incoming Webhook URL"
hits), and the repo's own pre-commit gitleaks gate then flagged the Discord fixture
literal (`discord-client-secret`, 32 contiguous chars near the `discord` keyword).
Fake-but-shape-perfect secrets are indistinguishable from real ones to every scanner in
the chain — by design.

Fix: build fixture strings from concatenated parts / `printf` repetition at runtime so
no secret-shaped contiguous literal exists in source (e.g. `SLACK_BASE` split across
two assignments + a `FAKE_TOKEN` assembled in halves). Never use the push-protection
"unblock" URL for fixtures — that whitelists the blob hash and trains the wrong habit.
This extends `cq-test-fixtures-synthesized-only`: synthesized AND non-contiguous.
