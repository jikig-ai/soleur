---
date: 2026-10-27
issue: 10849
---

# Legal correction notes quote the superseded phrase they remove — absence greps must strip note spans first

House-style `*(corrected <date>, ref #N: an earlier version stated '<old phrase>')*` notes — and `**Last Updated:**` amendment notes — quote the falsified text verbatim. A bare `grep -c '<old phrase>'` on a corrected legal doc counts its own audit trail. Verification must locate each surviving occurrence and prove it sits inside a `*( ... )*` italic-note span (paren-depth tracking — the notes contain nested parens like "eu-west-1 (Ireland)"), not just sed-strip `*(corrected*)` (the `**Last Updated:**` note also quotes). Second trap found the same run: an issue/audit section cite can be one level off — #10849 cites privacy-policy §5.9 while the sentence lives in §4.13's bullet that cross-references §5.9; grep for the quoted string, not the cited section.

## Session Errors

- **`gh api .../actions/jobs/<id>/logs` exits 1 on terminal escape sequences** — Recovery: re-run with `gh api --allow-escape-sequences`. **Prevention:** pass the flag by default when fetching raw job logs.
- **`gh run list --workflow e2e` → "could not find any workflows named e2e"** — `e2e` is a *job* inside the `CI` workflow, not a workflow name. Recovery: list the `CI` workflow's runs and filter `.jobs[]` by name. **Prevention:** name the workflow, filter jobs by `.name`, never guess a job is a workflow.
- **`gh issue create` denied by the filing gate (missing `--milestone`)** — Recovery: re-ran with `--milestone "Post-MVP / Later"`. **Prevention:** already hook-enforced (the deny named the remedy verbatim); no new rule.
- **`prepush-secret-scan.sh` path guessed as `$PLUGIN_ROOT/scripts/` — actual `$PLUGIN_ROOT/skills/ship/scripts/`** — Recovery: `find $CLAUDE_PLUGIN_ROOT -name 'prepush*'`. **Prevention:** resolve script paths with `find` under the plugin root, never guess the segment.
- **No agent-spawn surface on this harness → review panel ran inline sequential** — disclosed via `Reviewed-Coverage: sequential-fallback` in the review trailer (Gate 2a sanctioned path). **Prevention:** covered by review SKILL.md Gate 2a + `emit-review-trailer.sh --mode sequential-fallback`; no new rule.
