#!/usr/bin/env python3
"""S6 guard edit (the LAST edit of Phase 2): usage: guard_edit.py ROOT. Each replacement asserts it matches exactly once."""
import os, sys
p = os.path.join(sys.argv[1], ".claude/hooks/grep-q-pipe-guard.test.sh")
s = open(p, encoding="utf-8").read()


def rep(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:70])
    s = s.replace(old, new)


rep("  'apps/web-platform/*.test.sh | <= | 59 | #9217'\n", "") if s.count("<= | 59 | #9217'") else rep("  'apps/web-platform/*.test.sh | <= | 180 | #9217'\n", "")
rep("'plugins/soleur/scripts/' 'plugins/soleur/skills/')\nSWEEP_FLOOR", "'plugins/soleur/scripts/' 'plugins/soleur/skills/' 'apps/web-platform/infra/' 'apps/web-platform/test/')\nSWEEP_FLOOR")
rep("SWEEP_CANARY_COUNT=7 ", "SWEEP_CANARY_COUNT=9 ")
rep('mkdir -p "$sr/scripts" "$sr/plugins/soleur/scripts" "$sr/plugins/soleur/skills" "$sr/apps/web-platform/scripts" "$sr/apps/cla-evidence" "$sr/tests" "$sr/ignored"',
    'mkdir -p "$sr/scripts" "$sr/plugins/soleur/scripts" "$sr/plugins/soleur/skills" "$sr/apps/web-platform/scripts" "$sr/apps/web-platform/infra" "$sr/apps/web-platform/test" "$sr/apps/cla-evidence" "$sr/tests" "$sr/ignored"')
rep("""{ _noise; echo 'echo "$x" | egrep -q p'; }              > "$sr/plugins/soleur/skills/x.sh"\n""",
    """{ _noise; echo 'echo "$x" | egrep -q p'; }              > "$sr/plugins/soleur/skills/x.sh"
{ _noise; echo 'echo "$x" | grep -iq p'; }              > "$sr/apps/web-platform/infra/x.sh"
{ _noise; echo 'echo "$x" | fgrep -q p'; }              > "$sr/apps/web-platform/test/x.sh"\n""")
rep("tests|plugins/soleur/scripts|plugins/soleur/skills)/x\\.sh:", "tests|plugins/soleur/scripts|plugins/soleur/skills|apps/web-platform/infra|apps/web-platform/test)/x\\.sh:")
rep('mkdir -p "$okroot/scripts" "$okroot/plugins/soleur/scripts" "$okroot/plugins/soleur/skills" "$okroot/apps/web-platform/scripts" "$okroot/apps/cla-evidence" "$okroot/tests"',
    'mkdir -p "$okroot/scripts" "$okroot/plugins/soleur/scripts" "$okroot/plugins/soleur/skills" "$okroot/apps/web-platform/scripts" "$okroot/apps/web-platform/infra" "$okroot/apps/web-platform/test" "$okroot/apps/cla-evidence" "$okroot/tests"')
rep("tests plugins/soleur/scripts plugins/soleur/skills; do echo 'grep -q p <<<\"$x\"' > \"$okroot/$_r/x.sh\"; done",
    "tests plugins/soleur/scripts plugins/soleur/skills apps/web-platform/infra apps/web-platform/test; do echo 'grep -q p <<<\"$x\"' > \"$okroot/$_r/x.sh\"; done")
rep("REAL_PLANTED=24 ", "REAL_PLANTED=31 ")
rep("  plugins/soleur/skills/zz/scripts/zz.test.sh\n)",
    "  plugins/soleur/skills/zz/scripts/zz.test.sh\n  apps/web-platform/zz.test.sh\n  apps/web-platform/infra/zz.test.sh\n  apps/web-platform/infra/lib/zz.test.sh\n  apps/web-platform/infra/supabase-advisor/zz.test.sh\n  apps/web-platform/scripts/zz.test.sh\n  apps/web-platform/test/zz.test.sh\n  apps/web-platform/test/infra/zz.test.sh\n)")
rep("GATED_TEST_ROWS=$'.claude/*.test.sh\\nplugins/soleur/test/*\\napps/web-platform/*.test.sh\\n'", "GATED_TEST_ROWS=$'.claude/*.test.sh\\nplugins/soleur/test/*\\n'")
rep("# S3 (scripts/) and S4 (tests/) took their subtrees to zero and deleted their rows; S5 did the same",
    "# S6 took apps/web-platform/ (all but the six file-exact carrier rows below) to zero; its marked lines are demonstrations, mutation recipes and needles for carrier bytes, and the\n# apps/web-platform/infra/ root canary is witnessed today by those six rows going stale (not ablation-proved), so it matters once they convert.\n# S3 (scripts/) and S4 (tests/) took their subtrees to zero and deleted their rows; S5 did the same")
open(p, "w", encoding="utf-8").write(s)
print("guard edited")
