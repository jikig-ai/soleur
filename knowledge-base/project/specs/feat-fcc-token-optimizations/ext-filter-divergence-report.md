# ext-filter divergence report — 2026-10-13T20:41:47Z

- host: Linux 7.2.5-3-omarchy x86_64
- rtk: absent
- corpus: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-fcc-token-optimizations/plugins/soleur/scripts/ext-filter-divergence-corpus.txt (11 commands)

## Verdict

**UNMEASURED: rtk absent; control arm alive (lost=24) — posture stays unmeasured**

## Arms

| arm | commands | gate-literal lines lost | classes touched |
|---|---|---|---|
| control (head -3, must diverge) | 11 | 24 | eval-gate-marker file-line-citation gh-json-field porcelain-row rule-id-anchor sha-or-pr-ref soleur-env-echo soleur-marker tally-field |
| rtk | 0 | 0 | -- |

## Per-command detail

    CONTROL 01 lost=5 :: git grep -n "wrap_skip\|fold_name\|decide_walk" -- plugins/soleur/hooks/destructive-command-guard.sh | head -8
    CONTROL 02 lost=3 :: git log --oneline -6
    CONTROL 03 lost=2 :: printf ' M plugins/soleur/hooks/hooks.json\n?? plugins/soleur/hooks/ext-filter-detect.sh\n M .claude/hooks/pkill-self-match-guard.sh\n?? plugins/soleur/scripts/ext-filter-divergence.sh\n M plugins/soleur/scripts/lib/proc.sh\n' 
    CONTROL 04 lost=2 :: printf 'src/hooks/destructive-command-guard.sh:1180 asks\nsrc/hooks/pkill-self-match-guard.sh:224 matches\nplugins/soleur/hooks/ext-filter-detect.sh:1 emits\nlib/proc.sh:75 wraps\nlib/guardrails.sh:143 anchors\n'
    CONTROL 05 lost=2 :: printf 'abc1234 merged fix\nPR #10230 tracks the deferral\ncommit 9f8e7d6c5b4a3\nsee #5175 for context\nreviewed in #10227\n'
    CONTROL 06 lost=4 :: printf 'SOLEUR_EXT_FILTER tool=rtk\nSOLEUR_GIT_REPO_READY=true\nSOLEUR_COMPACTION_SKIPPED reason=startup\nSOLEUR_DISABLE_EXT_FILTER_DETECT=1\nSOLEUR_HOOK_TRACE=file\n'
    CONTROL 07 lost=2 :: printf 'eval-gate:block on recursive-delete-home\neval-gate:pass on porcelain check\neval-gate:ask on unparsed-wrapper\neval-gate:block second sample\neval-gate:pass final\n'
    CONTROL 08 lost=2 :: printf 'rule anchors: [id: recursive-delete-home] denies\n[id: unparsed-wrapper] asks\n[id: guard-degraded-jq-missing] degraded\n[id: wrapper-depth] caps\n[id: default-branch-force-push] asks\n'
    CONTROL 09 lost=1 :: printf '{"title":"x","number":10230,"state":"OPEN","labels":["external-env"],"body":"b","url":"u"}\n{"title":"y","number":10231,"state":"OPEN","labels":[],"body":"c","url":"v"}\n{"title":"z","number":10227,"state":"DRAFT","labels":[],"body":"d","url":"w"}\n{"title":"q","number":1,"state":"CLOSED","labels":[],"body":"e","url":"x"}\n'
    CONTROL 10 lost=1 :: printf 'killed=0 would_signal=9 failed=0 refused=5\nlate_refused=0 skipped_same_pgroup=1 scanned=20\nmode=dry-run passes=64 fails=0\nselected=40 union=100\n'
    CONTROL 11 lost=0 :: git ls-files plugins/soleur/hooks/ | head -6

## Lost literals (control arm proves the detector sees each class)

    LOST 053745f679 skill: route SKILL.md decompose-vendor-bundles-by-insertion-layer learning
    LOST 6320e7d227 docs: create plan and tasks for feat-fcc-token-optimizations
    LOST ae858f6f6c docs: capture brainstorm and spec for feat-fcc-token-optimizations
    LOST eval-gate:block second sample
    LOST eval-gate:pass final
    LOST [id: default-branch-force-push] asks
    LOST [id: wrapper-depth] caps
    LOST lib/guardrails.sh:143 anchors
    LOST lib/proc.sh:75 wraps
    LOST  M plugins/soleur/scripts/lib/proc.sh
    LOST plugins/soleur/hooks/destructive-command-guard.sh:1211:# fold_name <name> -> FN: the command name in lower case when it is one the table knows, else the name as it is. No process is
    LOST plugins/soleur/hooks/destructive-command-guard.sh:1215:fold_name() {
    LOST plugins/soleur/hooks/destructive-command-guard.sh:1228:# walk_in_dir <dir> <flags> <depth>: decide_walk with the simulated working directory moved to a wrapper's chdir directory, for the
    LOST plugins/soleur/hooks/destructive-command-guard.sh:1241:  decide_walk "$3"
    LOST plugins/soleur/hooks/destructive-command-guard.sh:1245:# decide_walk <depth>: the rule table over DA_T/DA_F (the words of one simple command), retried on the
    LOST ?? plugins/soleur/scripts/ext-filter-divergence.sh
    LOST reviewed in #10227
    LOST see #5175 for context
    LOST selected=40 union=100
    LOST SOLEUR_DISABLE_EXT_FILTER_DETECT=1
    LOST SOLEUR_HOOK_TRACE=file
    LOST {"title":"q","number":1,"state":"CLOSED","labels":[],"body":"e","url":"x"}
