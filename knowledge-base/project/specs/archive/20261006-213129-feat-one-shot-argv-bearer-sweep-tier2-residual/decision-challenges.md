# Decision challenges (plan-review, 2026-10-06)

Taste / scope calls the plan-review panel raised and the plan did NOT adopt. Default kept = the operator's stated scope.

1. **Split Phase 2 (residual non-Bearer scripts) into its own PR** (DHH). Raised: Phase 2 is outside baseline E and widens the PR. Kept: one PR, because the operator's brief lists these files as part of this pass and phases are separate commit groups. Reversible: Phase 2 commits can be dropped or moved without touching Phases 1 and 3.
2. **OAuth1 via a 0600 header file or defer `x-*` instead of `_cfg_q` + shim decoder** (DHH). Kept: the canonical stdin form ("do not improvise"); escaping is cross-checked against the real curl config parser.
3. **File a separate Tier 3 issue instead of restating #9597** (CTO). Kept: #9597 stays the single Tier 3 tracker (#7898 consolidated trackers on purpose); the PR body states which sites remain on argv.
4. **`web-zot-consumer-probe.sh` / `zot-entry-gate.sh` are outside baseline E** (DHH). Kept: the operator named both explicitly.
5. **Here-string / heredoc body for configure-auth and the bootstrap** (simplicity). Rejected: `--config -` already owns stdin, and a dash heredoc may spill the token to a tempfile; the 0600 file and the pipe form stay.
