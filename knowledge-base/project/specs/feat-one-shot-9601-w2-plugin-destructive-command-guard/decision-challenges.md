# Decision challenges — W2 plugin destructive-command guard

Plan: `knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md`. Persisted by `plan-review` (headless). Each item is a Taste call the plan-review panel disagreed on or the plan overrode; the plan's default is stated, and the CPO sign-off (Phase 0.3) is the place to overturn any of them. None changes operator-requested scope.

## T1 — Keep a copy of the lexer, or move it (Taste)

- Panel: the DHH and devex seats recommended moving `.claude/hooks/lib/filing-shape.pl` into the plugin and pointing `guardrails.sh` at it; the architecture seat recommended a BEGIN/END-marked byte-identical region.
- Plan default: copy plus a byte-identical marked region, enforced by a test. Reason: ADR-256 binds the original to `cron-bash-allowlist-hook.mjs`; moving it edits the filing gate inside a customer-hook PR.
- Re-open when: the filing gate is next touched (tracked follow-up on the W2 deferral issue).

## T2 — Perl as a runtime dependency versus a bash-only splitter (Taste)

- Panel: the DHH seat called Perl a P0 for a customer plugin; the devex seat asked for the alternative to be priced; the simplicity seat said keep.
- Plan default: Perl, with a priced-and-rejected entry in the Cut List (the grammar rows that decide P1 and P2 are what a bash `xargs`-style splitter already gets wrong, measured on `guardrails.sh`; the lexer is measured to read all of them). Degrades to a raw scan when `perl` is missing (D6).
- Re-open when: a customer reports a perl-less environment, or the CPO prefers a smaller dependency set over fidelity.

## T3 — No decision log, transcript only (Taste)

- Panel: DHH, devex and simplicity seats said cut the local log; the observability layer-7 rule asks for a durable artifact and says stdout alone is a P1.
- Plan default: cut. The harness transcript is the durable artifact. The observability reviewer may re-open at review; the fallback (one append-only line per decision, no command text) is written down in the plan.

## T4 — Devin `exec` coverage deferred (Taste)

- Panel: DHH and simplicity seats said cut the ask-as-deny branch; the spec-flow seat noted it was a dead end for Devin users.
- Plan default: matcher `^Bash$` only, ledger row `skip`, Devin `ask` measurement and `exec` coverage on the follow-up issue. Devin users have no W2 protection until then.

## T5 — Narrower rule set than a general destructive guard (Taste)

- Panel: DHH asked to hold the three charter families; simplicity asked to drop the SQL rule; spec-flow and Kieran asked for more spellings (`cd`, wrappers, `--` suffixes) inside the families.
- Plan default: SQL rule cut (follow-up); spellings of the three families kept (they break P1 with no obfuscation involved); `doppler secrets set` and plain `terraform apply` dropped from spec FR2 and recorded as follow-up candidates. The CPO is asked about each.

## T6 — Kept despite a cut recommendation (Taste)

- `scripts/verify-agent-security-slice1.sh` extension (simplicity seat: cut). Kept because the observability gate needs a command that exists in this PR's tree and reads W2's signal.
- Separate mutation suite (DHH, devex and simplicity seats: fold it in). Kept separate but cut to eight CI rows M1-M8; the rest run once and are recorded.
- ADR-274 (DHH: fold into one amendment). Kept: the vendored-lexer, degrade-posture and decision-set decisions have no existing home; the ADR-157 and ADR-223 amendment lines were dropped.
