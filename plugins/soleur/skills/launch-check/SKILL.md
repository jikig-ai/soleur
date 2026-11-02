---
name: launch-check
description: "This skill should be used when checking an existing repository for production-readiness gaps and missing Soleur engineering practices."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# launch-check

Read-only readiness and best-practice gap analysis for an existing repository. It answers two questions in one living file, `knowledge-base/engineering/readiness/launch-check.md`:

1. **What stands between this repo and real customers?** Findings in four domains: Security & secrets, Tests & CI/CD, Tech debt & architecture, Reliability / performance & ops.
2. **Which Soleur practices does this repo lack?** One baseline check per guard that `soleur:verification-scaffold` can install, derived from its manifest at run time, plus a few non-guard conventions.

The analysis writes **only** that report file. It never installs anything, never sends data anywhere, and has no telemetry. Issue-epic creation is **planned** (not yet built; see [Planned](#planned)).

This is a findings list, not a score and not an attestation. Nothing in the report certifies a standard; the banner in every report says so.

## Hard rules

- Only the scripts write the report. Never write or edit `launch-check.md` yourself, and never run `gh` for this skill.
- Read only the paths listed in the `--files-out` list from the scan. Never open a path that is not on it, and never read `.env*`, keys, credentials, state files, SQL or CSV data, fixtures, or anything the scan excluded.
- Never quote file content into any output. Cite `path:line` only, and never write a secret's value or its location anywhere. `scan --show-secrets` prints locations to the terminal for the customer; do not copy them into files, issues or the judged file.
- Headless runs (no TTY): `scan` and `render --dry-run` only. Never overwrite the report headless.
- `gitleaks` must be installed. If a script aborts, read its `SOLEUR_LAUNCH_CHECK_ABORT reason=` line, report it plainly, and stop. Do not work around a refusal.

## Flow

```bash
LC="${CLAUDE_PLUGIN_ROOT}/skills/launch-check/scripts/launch-check.sh"
W="$(mktemp -d)"
bash "$LC" scan --target . --facts "$W/facts.tsv" --files-out "$W/files.list"
```

1. **Scan.** Read `$W/facts.tsv` (`id<TAB>status<TAB>evidence`). Statuses: `ok`, `gap`, `na`, `unsupported-stack`.
2. **AI-assisted review (four items).** Using only paths from `$W/files.list`, form a view on `JDG-AUTH` (how users sign in and which routes check permission), `JDG-ARCH` (module boundaries, migrations, destructive data operations), `JDG-SCALE` (endpoints and queries that degrade first; rate limiting) and `JDG-OBS` (can a failure be seen without logging into a server). Write `$W/judged.tsv`, one line per item you reviewed, exactly four tab-separated fields:

   ```text
   JDG-AUTH<TAB>gap|ok|na<TAB>high|medium|low|-<TAB>FACT-ID,FACT-ID|-
   ```

   The third field is the severity (`-` unless the status is `gap`). The fourth cites the ids of the deterministic facts you relied on; a `gap` must cite at least one. **No other field is accepted**: titles and remedies come from [checks.tsv](./references/checks.tsv). A malformed line aborts the render with `reason=judged-schema`.
3. **Render.** Preview first, then write:

   ```bash
   bash "$LC" render --target . --facts "$W/facts.tsv" --judged "$W/judged.tsv" --dry-run
   bash "$LC" render --target . --facts "$W/facts.tsv" --judged "$W/judged.tsv"
   ```

   Re-running diffs against the previous report: fixed gaps appear under *Closed since last run*, new ones under *New since last run*.
4. **Accepting a finding.** The customer edits the report's state block, changing `finding ID open` to `finding ID accepted <date> <reason>`. Accepted findings leave the open table and are listed under *Accepted*.
5. **Verify.** `bash "$LC" verify-report --file knowledge-base/engineering/readiness/launch-check.md` prints `LAUNCH_CHECK_REPORT_OK` for a well-formed report.

Closing a baseline gap is the customer's decision: each finding names the `soleur:verification-scaffold` or `soleur:constraint-scaffold` command that installs the practice (advisory first). This skill installs nothing.

## Coverage and limits

- Deterministic checks target Node/TypeScript projects; other stacks report `unsupported-stack` where a check is stack-specific, and the banner says coverage is partial.
- The scan reads the last commit for secret-shaped content, not git history. A secret removed from the current tree may still be live in history; rotate it.
- Secret-class findings are counts only. Locations stay on the customer's terminal.
- Detectors are heuristics. A gap means "not identified in the files read"; a missing gap is not assurance.
- Libraries and CLIs are not deployed services: checks such as the health endpoint or backups will read as gaps and can be accepted.

## Planned

Issue-epic creation (preview, then confirm, severity and domain labels) is built in a follow-up change. Until it ships, this skill produces the report only.

## References

- [checks.tsv](./references/checks.tsv): the catalog (ids, titles, severities, remedies).
- [severity-rubric.md](./references/severity-rubric.md)
- [banner.txt](./references/banner.txt), [footer.txt](./references/footer.txt), [phrases.txt](./references/phrases.txt), [banned-words.txt](./references/banned-words.txt), [baseline-domains.tsv](./references/baseline-domains.tsv), [retired-checks.tsv](./references/retired-checks.tsv)
- [launch-check.sh](./scripts/launch-check.sh)
