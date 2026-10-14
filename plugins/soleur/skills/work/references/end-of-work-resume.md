# End-of-work resume prompt: why the no-marker branch still emits the block

Relocated verbatim from `work/SKILL.md` step 3.5 (the skill body is byte-capped against the merge-base; the
rule itself, the marker literal, `recommend=true` and the "no marker means no `/clear` recommendation" clause
stay in the skill body because `compaction-state-hook.test.sh` scenarios 25c and 25d assert them there).

The no-marker branch is reached by a session that never compacted, by a kill-switched hook (`SOLEUR_DISABLE_COMPACTION_HOOKS=1`), and by every non-Claude harness — the hook is Claude-only and degrades to silence rather than to a false claim. In all three the resume prompt still fires, which is what keeps the retirement of the old unconditional "Tip: After shipping, run `/clear`…" from leaving a dead end.
