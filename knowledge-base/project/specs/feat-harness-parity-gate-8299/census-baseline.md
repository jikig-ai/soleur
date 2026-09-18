# Phase 1 RED checkpoint — `harness-parity-census.ts --report` on the pre-remediation tree

Base: 8be3af2bf (rebased onto origin/main f5ad46390), 2026-09-18.

```text
harness-parity: 106 docs examined, 1029 non-canonical sites in 62 docs, 250 canonical, 20 unknown-ns, 0 exempt, 0 marker errors
attribution: grok 339 / claude-devin 187 / codex 2 / claude-agent 8 / claude-leaf 3 / grok-stem 1 / bare-leaf 488 / unrecognised 1
docs:
  218  plugins/soleur/skills/review/SKILL.md
  163  plugins/soleur/skills/plan/SKILL.md
  81  plugins/soleur/skills/work/SKILL.md
  72  plugins/soleur/skills/ship/SKILL.md
  47  plugins/soleur/commands/go.md
  40  plugins/soleur/skills/brainstorm/SKILL.md
  39  plugins/soleur/skills/one-shot/SKILL.md
  28  plugins/soleur/skills/gdpr-gate/SKILL.md
  25  plugins/soleur/skills/deepen-plan/SKILL.md
  25  plugins/soleur/skills/plan-review/SKILL.md
  24  plugins/soleur/skills/compound/SKILL.md
  15  plugins/soleur/skills/postmerge/SKILL.md
  15  plugins/soleur/skills/product-roadmap/SKILL.md
  15  plugins/soleur/commands/sync.md
  11  plugins/soleur/skills/content-writer/SKILL.md
  11  plugins/soleur/skills/growth/SKILL.md
  11  plugins/soleur/skills/kb-search/SKILL.md
  10  plugins/soleur/skills/community/SKILL.md
  10  plugins/soleur/skills/eval-harness/SKILL.md
  9  plugins/soleur/skills/linear-fetch/SKILL.md
  9  plugins/soleur/skills/qa/SKILL.md
  8  plugins/soleur/skills/drain-labeled-backlog/SKILL.md
  7  plugins/soleur/skills/preflight/SKILL.md
  7  plugins/soleur/skills/resolve-todo-parallel/SKILL.md
  7  plugins/soleur/skills/ux-audit/SKILL.md
  6  plugins/soleur/skills/feature-tweet/SKILL.md
  6  plugins/soleur/skills/go/SKILL.md
  6  plugins/soleur/skills/resolve-pr-parallel/SKILL.md
  6  plugins/soleur/skills/test-browser/SKILL.md
  5  plugins/soleur/skills/compound-capture/SKILL.md
  5  plugins/soleur/skills/merge-pr/SKILL.md
  5  plugins/soleur/skills/resolve-parallel/SKILL.md
  5  plugins/soleur/skills/schedule/SKILL.md
  5  plugins/soleur/skills/seo-aeo/SKILL.md
  5  plugins/soleur/skills/sync/SKILL.md
  5  plugins/soleur/skills/triage/SKILL.md
  5  plugins/soleur/skills/xcode-test/SKILL.md
  4  plugins/soleur/skills/feature-video/SKILL.md
  4  plugins/soleur/skills/harvest-debt/SKILL.md
  4  plugins/soleur/skills/help/SKILL.md
  4  plugins/soleur/skills/incident/SKILL.md
  4  plugins/soleur/skills/legal-generate/SKILL.md
  3  plugins/soleur/skills/architecture/SKILL.md
  3  plugins/soleur/skills/drain-prs/SKILL.md
  3  plugins/soleur/skills/legal-audit/SKILL.md
  3  plugins/soleur/skills/resolve-debt/SKILL.md
  3  plugins/soleur/skills/social-distribute/SKILL.md
  2  plugins/soleur/skills/agent-native-audit/SKILL.md
  2  plugins/soleur/skills/atdd-developer/SKILL.md
  2  plugins/soleur/skills/competitive-analysis/SKILL.md
  2  plugins/soleur/skills/file-todos/SKILL.md
  2  plugins/soleur/skills/heal-skill/SKILL.md
  2  plugins/soleur/skills/rclone/SKILL.md
  2  plugins/soleur/skills/skill-security-scan/SKILL.md
  2  plugins/soleur/skills/spec-templates/SKILL.md
  1  plugins/soleur/skills/agent-browser/SKILL.md
  1  plugins/soleur/skills/code-to-prd/SKILL.md
  1  plugins/soleur/skills/discord-content/SKILL.md
  1  plugins/soleur/skills/frontend-anti-slop/SKILL.md
  1  plugins/soleur/skills/pencil-setup/SKILL.md
  1  plugins/soleur/skills/provision-hetzner/SKILL.md
  1  plugins/soleur/skills/test-fix-loop/SKILL.md
unknown-ns:
  plugins/soleur/skills/compound-capture/SKILL.md:308: soleur:engineering:review:baz
  plugins/soleur/skills/compound-capture/SKILL.md:309: soleur:bar
  plugins/soleur/skills/harvest-debt/SKILL.md:28: soleur:
  plugins/soleur/skills/plan/SKILL.md:678: soleur:followthrough
  plugins/soleur/skills/review/SKILL.md:825: soleur:followthrough
  plugins/soleur/skills/schedule/SKILL.md:184: soleur:
  plugins/soleur/skills/ship/SKILL.md:1479: soleur:followthrough
  plugins/soleur/skills/ship/SKILL.md:1538: soleur:followthrough
  plugins/soleur/skills/ship/SKILL.md:1560: soleur:followthrough
  plugins/soleur/skills/ship/SKILL.md:1575: soleur:followthrough
  plugins/soleur/skills/ship/SKILL.md:2605: soleur:followthrough
  plugins/soleur/skills/ship/SKILL.md:2666: soleur:followthrough
  plugins/soleur/skills/ship/SKILL.md:2667: soleur:followthrough
  plugins/soleur/skills/work/SKILL.md:1277: soleur:
  plugins/soleur/commands/go.md:134: soleur:
  plugins/soleur/commands/go.md:147: soleur:
  plugins/soleur/commands/go.md:189: soleur:
  plugins/soleur/commands/go.md:193: soleur:
  plugins/soleur/commands/go.md:193: soleur:
  plugins/soleur/commands/go.md:193: soleur:
```
