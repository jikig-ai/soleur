# Learning: vendor CLI grammar for a security boundary is verified at SOURCE level, not README level

## Problem

Planning the `rtk` unwrap arm (#10230), two different vendor-fact classes
failed two different verification levels in one session:

1. `RTK_DISABLED=1` — an env var asserted by a domain leader — did not exist
   in RTK's README at all. Caught by the plan's CLI-verification grep.
2. The deeper grammar facts were only true at SOURCE level: RTK's README
   claims `run|err|test|summary` "preserve positional argument boundaries,"
   but `src/main.rs` + `runner.rs`/`summary.rs` at HEAD join trailing args to
   `sh -c` — meaning `rtk err 'rm -rf ~'` is a shell string, not argv. The
   README also understates the flag surface (`--command` long form,
   `global = true` flags legal post-subcommand). A plan written from the
   README alone would have shipped an allow-bypass inside the security fix.

## Solution

When a plan consumes a vendor's command-line semantics into a security
boundary (wrapper table, allowlist, gate regex), the verification citation
must name the **parser source** (clap/argparse defs, `main.rs`/`cli.rs`),
not docs. README-level verification is sufficient for "does the token
exist" claims in user docs — it is insufficient for "how does the binary
parse argv" claims feeding a guard.

## Key Insight

Each verification level catches a different lie. Doc-grep catches invented
tokens. Source-grep catches *drift between claimed and actual semantics* —
the class that matters when the consumer is a security boundary whose
failure mode is silent-allow. README vs source is itself a divergence
surface: `rtk-ai/rtk#640` documents the argv-vs-`sh -c` gap as a known
upstream defect, so "the docs say argv" can stay true of the docs and false
of the binary for months.

## Prevention

- Plans that add a vendor command to any guard/unwrap/allowlist table cite
  the parser definition file, not the README. If the binary isn't
  inspectable, the plan states the unknown and chooses the ask-not-miss
  posture (unrecognized payload shapes → `unparsed-wrapper` ask).
- The divergence harness's `GRAMMAR-DRIFT` canary (scrape `rtk --help`
  against the canonical set) covers post-merge drift; plan-time source
  verification covers pre-merge correctness.

## Session Errors

- `RTK_DISABLED=1` propagated from a domain leader into early plan text —
  caught by CLI-verification gate (recurring class: leader-asserted claim,
  same as the LICENSE false claim this week — gated, documented).
- First-draft plan modeled `err|test|summary` as argv exec per README —
  caught by Kieran/CTO/architecture review via `src/main.rs` (this learning).
- `tool=none` emission contradicted between AC3 and Test Scenarios — caught
  by Kieran plan-review.
- `plugins/soleur/test/proc.test.sh` missing from Files to Edit while AC2
  required proc rows — caught by DHH + SpecFlow.
- Edit-tool `old_string` mismatch on Proposed Solution (one-off, trivial).
- markdownlint MD004 — two `+` list markers (one-off, fixed).

## Tags

vendor-verification, README-vs-source, security-boundary, plan-gates,
external-tool, wrapper-grammar
