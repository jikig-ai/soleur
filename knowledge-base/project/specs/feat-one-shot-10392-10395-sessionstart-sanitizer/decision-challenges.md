# Decision Challenges — feat-one-shot-10392-10395-sessionstart-sanitizer

Headless pipeline channel (one-shot → plan → deepen-plan). The plan-phase
subagent has no Task/run_subagent spawn surface, so technical rows are staged
as `pending - assumed:` for a batched `soleur:engineering:cto` ruling — the
same posture the #10383 pipeline used (specs/archive/20261015-174125-feat-bare-root-anchor-gate/decision-challenges.md).

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Sanitizer lib home + copy strategy: single physical file under `plugins/soleur/` sourced repo-wide vs two byte-equal copies (`.claude/hooks/lib/` + `plugins/soleur/scripts/lib/`) | technical | pending - assumed: two byte-equal copies pinned by a `cmp` parity guard — the memory-backstop.sh dual-home convention; avoids a repo→plugin runtime dependency direction |
| Sanitizer variants: three functions (strip-all / keep-\t\n / keep-\n-only) + NEL (`\xc2\x85`) in the sed set | technical | pending - assumed: three variants cover every in-scope site with zero contract weakening; NEL is the same line-break class and two sites already strip it |
| Lib-unreadable fallback at adopt sites | technical | pending - assumed: `declare -F` fallback carrying the site's *pre-change* strip set — never weaker than today, matches the loader's under-strip-is-safe posture |
| Plugin hook dedup predicate (skip when target repo already carries its own `SOLEUR_BARE_ROOT_CWD` arm AND a registry reference to `session-rules-loader.sh`) | technical | pending - assumed: requires BOTH a marker file under `.claude/hooks/` AND a settings/devin registration reference, so vendored-but-unwired copies don't suppress detection |
| Plugin hook redirect text: generic `git worktree add` always; soleur `worktree-manager.sh` hint line only when the plugin-side script exists | technical | pending - assumed: satisfies "degrade gracefully off this repo's topology" while keeping the soleur path discoverable where it exists |
| `ensure-kb-index.sh` bare-root guard shape: `git -C "$KB_DIR" rev-parse --is-inside-work-tree` != true → skip regen | technical | pending - assumed: one line, covers bare root + non-checkout `--kb-dir`; masked-config worktree degrades to skip (safe direction; that shape is already broken per ADR-173) |
| `memory-backstop.sh` ledger writes at bare root (`.claude/.memory-backstop.{jsonl,lock,stamp}`) | technical | pending - assumed: KEEP — bounded + log-rotated, same forensic reasoning as the session-manifests keep ruling (CTO 2026-10-15); protection must still run at a misanchored session |
| `memory-backstop-resolve.sh`/`memory-backstop.sh` `//[[:cntrl:]]` substitutions and jq `gsub([[:cntrl:]])` sites | technical | pending - assumed: jq site adopted (one-token LS/PS addition); bash `//` sites not adopted — resolver-owned literals / byte-equal-copy + BACKSTOP_REVISION bump cost exceeds residual |
| New plugin hook basename: `bare-root-cwd-guard.sh` (mirrors repo hook) vs a distinct name | technical | pending - assumed: same basename, dual-home convention (memory-backstop.sh precedent); the tree disambiguates |
| Single PR closing both issues vs split at the lib boundary | technical | pending - assumed: single PR — the plugin hook's own emit is a sanitize site; landing lib first makes the hook correct by construction; operator bundled both issues into one branch |
| Sequential review fallback (no Task/run_subagent on this harness) | technical | pending - assumed: applied — domain sweep, GDPR check, specflow and plan-review lenses executed inline; `Reviewed-Coverage: sequential-fallback` disclosed in the plan |
