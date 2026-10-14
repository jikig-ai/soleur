# ext-filter divergence report — 2026-10-13T22:17:48Z

- host: Linux 7.2.5-3-omarchy x86_64
- rtk: absent
- corpus: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-fcc-token-optimizations/plugins/soleur/scripts/ext-filter-divergence-corpus.txt (11 commands)

## Verdict

**UNMEASURED: rtk absent; control arm alive (lost=26) — posture stays unmeasured. rtk arm: SKIPPED reason=rtk-absent**

## Arms

| arm | commands | gate-literal lines lost | classes touched |
|---|---|---|---|
| control (head -3, must diverge) | 11 | 26 | eval-gate-marker file-line-citation gh-json-field porcelain-row rule-id-anchor sha-or-pr-ref soleur-env-echo soleur-marker tally-field |
| rtk | 0 | 0 | -- |

## Per-command detail

### control
    CONTROL 01 lost=5 :: git grep -n "wrap_skip\|fold_name\|decide_walk" -- plugins/soleur/hooks/destructive-command-guard.sh | head -8
    CONTROL 02 lost=3 :: git log --oneline -6
    CONTROL 03 lost=2 :: printf ' M plugins/soleur/hooks/hooks.json\n?? plugins/soleur/hooks/ext-filter-detect.sh\n M .claude/hooks/pkill-self-match-guard.sh\n?? plugins/soleur/scripts/ext-filter-divergence.sh\n M plugins/soleur/scripts/lib/proc.sh\n'
    CONTROL 04 lost=2 :: printf 'src/hooks/destructive-command-guard.sh:1180 asks\nsrc/hooks/pkill-self-match-guard.sh:224 matches\nplugins/soleur/hooks/ext-filter-detect.sh:1 emits\nlib/proc.sh:75 wraps\nlib/guardrails.sh:143 anchors\n'
    CONTROL 05 lost=2 :: printf 'abc1234 merged fix\nPR #10248 tracks the deferral\ncommit 9f8e7d6c5b4a3\nsee #5175 for context\nreviewed in #10227\n'
    CONTROL 06 lost=4 :: printf 'SOLEUR_EXT_FILTER tool=rtk\nSOLEUR_GIT_REPO_READY=true\nSOLEUR_COMPACTION_SKIPPED reason=startup\nSOLEUR_DISABLE_EXT_FILTER_DETECT=1\nSOLEUR_HOOK_TRACE=file\n'
    CONTROL 07 lost=2 :: printf 'eval-gate:block on recursive-delete-home\neval-gate:pass on porcelain check\neval-gate:ask on unparsed-wrapper\neval-gate:block second sample\neval-gate:pass final\n'
    CONTROL 08 lost=2 :: printf 'rule anchors: [id: recursive-delete-home] denies\n[id: unparsed-wrapper] asks\n[id: guard-degraded-jq-missing] degraded\n[id: wrapper-depth] caps\n[id: default-branch-force-push] asks\n'
    CONTROL 09 lost=1 :: printf '{"title":"x","number":10230,"state":"OPEN","labels":["external-env"],"body":"b","url":"u"}\n{"title":"y","number":10231,"state":"OPEN","labels":[],"body":"c","url":"v"}\n{"title":"z","number":10227,"state":"DRAFT","labels":[],"body":"d","url":"w"}\n{"title":"q","number":1,"state":"CLOSED","labels":[],"body":"e","url":"x"}\n'
    CONTROL 10 lost=1 :: printf 'killed=0 would_signal=9 failed=0 refused=5\nlate_refused=0 skipped_same_pgroup=1 scanned=20\nmode=dry-run passes=64 fails=0\nselected=40 union=100\n'
    CONTROL 11 lost=2 :: printf 'plugins/soleur/hooks/hooks.json:82 matcher\nplugins/soleur/hooks/ext-filter-detect.sh:38 kill-switch\nplugins/soleur/hooks/version-banner.sh:19 xtrace\nplugins/soleur/hooks/compaction-state.sh:129 bounded\nplugins/soleur/hooks/destructive-command-guard.sh:5 kill-switch\n'

## Lost literals (control arm proves the detector sees each class)

