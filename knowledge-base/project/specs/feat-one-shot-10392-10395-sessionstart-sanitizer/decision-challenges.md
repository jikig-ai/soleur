# Decision Challenges — feat-one-shot-10392-10395-sessionstart-sanitizer

Headless pipeline channel (one-shot → plan → deepen-plan). The plan-phase
subagent has no Task/run_subagent spawn surface, so technical rows are staged
as `pending - assumed:` for a batched `soleur:engineering:cto` ruling — the
same posture the #10383 pipeline used (specs/archive/20261015-174125-feat-bare-root-anchor-gate/decision-challenges.md).

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Sanitizer lib home + copy strategy: single physical file under `plugins/soleur/` sourced repo-wide vs two byte-equal copies (`.claude/hooks/lib/` + `plugins/soleur/scripts/lib/`) | technical | Ruled by CTO agent, 2026-10-20: two byte-equal copies cmp-pinned - plugin ships only plugins/soleur/** so neither single-home direction reaches the other topology; dual-home byte-equal convention established (memory-backstop.sh + hooks/lib/log-rotation.sh); scripts/lib/ is the correct plugin-side home |
| Sanitizer variants: three functions (strip-all / keep-\t\n / keep-\n-only) + NEL (`\xc2\x85`) in the sed set | technical | Ruled by CTO agent, 2026-10-20: three variants + NEL - all three strip shapes exist in the census; c2 85 already stripped at domain-model-drift.sh:321 and folding it in is strictly stronger with zero contract weakening |
| Lib-unreadable fallback at adopt sites | technical | Ruled by CTO agent, 2026-10-20: declare -F fallback carrying each site's pre-change strip set - matches the loader's fail-open posture; never weaker than today; a hard-fail would cost the whole emit, not just the strip |
| Plugin hook dedup predicate (skip when target repo already carries its own `SOLEUR_BARE_ROOT_CWD` arm AND a registry reference to `session-rules-loader.sh`) | technical | Ruled by CTO agent, 2026-10-20: suppress only when BOTH a SOLEUR_BARE_ROOT_CWD grep hits .claude/hooks/*.sh AND a registry references session-rules-loader.sh - a vendored-but-unwired tree hits term 1 only, so the arm still fires; over-suppression is the worse failure direction |
| Plugin hook redirect text: generic `git worktree add` always; soleur `worktree-manager.sh` hint line only when the plugin-side script exists | technical | Ruled by CTO agent, 2026-10-20: generic git worktree add always, worktree-manager.sh hint gated on the plugin-side file existing - the graceful-degradation contract; the manager ships in the plugin payload |
| `ensure-kb-index.sh` bare-root guard shape: `git -C "$KB_DIR" rev-parse --is-inside-work-tree` != true → skip regen | technical | Ruled by CTO agent, 2026-10-20: git -C "$KB_DIR" rev-parse --is-inside-work-tree != true -> skip regen - covers bare root + non-checkout --kb-dir; masked-config worktree degrades to skip (safe direction) |
| `memory-backstop.sh` ledger writes at bare root (`.claude/.memory-backstop.{jsonl,lock,stamp}`) | technical | Ruled by CTO agent, 2026-10-20: KEEP .claude/.memory-backstop.{jsonl,lock,stamp} writes at bare root - forensic reasoning per the session-manifests keep ruling (SOC 2 CC6.1); bounded + log-rotated; protection must run at misanchored sessions |
| `memory-backstop-resolve.sh`/`memory-backstop.sh` `//[[:cntrl:]]` substitutions and jq `gsub([[:cntrl:]])` sites | technical | Ruled by CTO agent, 2026-10-20: adopt the jq site (gsub \\u2028\|\\u2029), do not adopt the bash //[[:cntrl:]] sites - neither is an agent-context boundary; dual-home edit + BACKSTOP_REVISION bump cost exceeds the cosmetic residual |
| New plugin hook basename: `bare-root-cwd-guard.sh` (mirrors repo hook) vs a distinct name | technical | Ruled by CTO agent, 2026-10-20: same basename bare-root-cwd-guard.sh - the dual-home convention spans same-name-byte-equal and same-name-different-bytes; the tree disambiguates |
| Single PR closing both issues vs split at the lib boundary | technical | Ruled by CTO agent, 2026-10-20: single PR closing #10392 + #10395 - the hook's own .cwd emit is a sanitize site; a lib-first split adds a landing order; ~80% mechanical strip swaps |
| Sequential review fallback (no Task/run_subagent on this harness) | technical | Ruled by CTO agent, 2026-10-20: sequential-fallback applied with Reviewed-Coverage: sequential-fallback disclosed - identical posture ruled in the #10383 pipeline 2026-10-15 |
