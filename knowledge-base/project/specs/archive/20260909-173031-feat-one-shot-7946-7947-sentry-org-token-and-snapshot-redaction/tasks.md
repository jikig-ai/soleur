# Tasks — Sentry org-token retirement and browser-snapshot redaction

Plan: `knowledge-base/project/plans/2026-09-09-feat-sentry-org-token-and-snapshot-redaction-plan.md`
Branch: `feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction`
Closes: #7946, #7947

**Ordering is load-bearing.** Phase 1 is not written until Phase 0.1's verdict table is filled in —
two of its five verdicts delete the artifacts Phase 1 would author. Phase 2 (#7947) lands entirely
ahead of Phase 3 (#7946): the Phase 3.1 mint is a browser login, and it is performed under the guard
Phase 2 ships. That ordering is also what makes the DC-1 split a clean cut if the operator takes it.

## Phase 0 — Measure, then decide

- [ ] 0.1.1 Serve a synthesized page over `python3 -m http.server --bind 127.0.0.1 <port>
      --directory <dedicated mktemp -d>` — never `file://`, never inside the repo, never the bare
      form (it binds 0.0.0.0 and lists the whole directory). Nodes: a `type=password` with a static
      `value=` holding `ZZQP-SENTINEL-7947`; a second `type=password` set by inline JS; a
      `type=text` named "Enter your password" left empty; **a read-only `type=text` named "Token"
      holding the sentinel** (the class that already fired in this repo and the one Phase 3.1's own
      mint page renders); a benign email field as the must-PASS control. Tear the server down
      before Phase 3.
- [ ] 0.1.2 Capture and grep per surface: `agent-browser snapshot -i`, `--json`,
      `mcp__playwright__browser_snapshot`, `browser_take_screenshot`; every flag the six
      token-bearing surfaces use (`-i`, `-c`, `-d N`, `--json`); headed and headless.
- [ ] 0.1.3 Record the exact serialized node line per surface per provenance path — how the node is
      MARKED, not only whether the sentinel appears. A label-only distinction changes the filter's
      design from structural to heuristic.
- [ ] 0.1.4 As its own row with its own disposition: does `browser_type` / `agent-browser fill` echo
      the typed value into the tool result? If yes, file its own issue; do not widen this plan.
- [ ] 0.1.5 Note the prior evidence before measuring, so the probe confirms or refutes a stated
      expectation rather than fishing: the installed `playwright-core` aria-snapshot generator
      excludes checkbox/radio/file from value rendering and does NOT exclude `password`, and it
      reads `element.value` from the DOM rather than the platform accessibility tree. "Neither
      leaks" is therefore the least likely verdict — but `@playwright/mcp` bundles its own
      Playwright and `agent-browser` may not wrap `ariaSnapshot` at all, so both surfaces are
      still measured.
- [ ] 0.1.6 Fill the verdict table in the plan. **Stop here and re-scope if the verdict is
      "only the MCP surface leaks" or "neither leaks".**
- [ ] 0.2.1 Probe all four Sentry endpoints with `SENTRY_ISSUE_RO_TOKEN`, per endpoint AND per
      distinct org slug (`jikigai-eu`, `jikigai`). Record HTTP status for every pair.
- [ ] 0.2.2 Re-probe each relevant token's own scopes via `GET https://<org>.sentry.io/api/0/`
      → `.auth.scopes`. Record the reading.
- [ ] 0.2.3 Apply the Phase 0.2 branch table: all 200 → minimum is `[event:read, org:read]`;
      checkins 403 → throwaway at `+project:read`, re-probe, widen only on a second 403, and delete
      the throwaway in the same trap scope; any 404 on `jikigai` → the org-slug fix is in scope.
- [ ] 0.3.1 Confirm populations: 16 files under `scripts/followthroughs/`; the six token-bearing
      browser surfaces; `grep -c snapshot` = 0 for `ux-audit/SKILL.md` and `ops-research.md`.
- [ ] 0.4.1 Confirm `excluded_for_rule_d`-shaped per-rule exclusion can un-exclude `*.test.sh` for
      Rule E alone; fall back to `lint-followthrough-varq-ban.sh` if not.
- [ ] 0.4.2 Confirm `lint-credential-path-literals.py` can host the snapshot rule family, and record
      that this makes it blocking from its first run via the required `credential-path-guard` job.
- [ ] 0.4.3 Confirm `plugins/soleur/hooks/hooks.json` accepts a `PreToolUse` arm and that the hook
      path resolves from the installed plugin root. If not, file the deferral and amend
      `## User-Brand Impact` to state that P7 is not delivered to the operator.
- [ ] 0.4.4 Evaluate the ADR-162 rewrite disposition against the single-rewriter invariant in
      `.claude/hooks/hookeventname-coverage.test.sh`. Record the outcome in the Cut List either way.

## Phase 1 — RED tests first

- [ ] 1.1 `plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh` + synthesized
      fixtures. Assertions: sentinel redacted; non-password textbox unchanged (must-PASS); a
      `type=password` with a non-password accessible name still redacted; `--json` shape handled;
      malformed input exits 2 with stdout empty and stderr non-empty and sentinel-free.
      **Auto-globbed — do NOT add a `run_suite` line.**
- [ ] 1.2 Walker 1 rule cases added to `scripts/lint-credential-path-literals.test.sh`, fixtures in
      that lint's existing corpus. Cover M1-M7 and H1-H5.
- [ ] 1.3 Rule E cases added to `scripts/lint-shell-trace-credential-refusal.test.sh`. Cover M1-M6
      and H1-H3, including M6 (consumption renamed, refusal not).
- [ ] 1.4 `.claude/hooks/browser-snapshot-credential-guard.test.sh` — envelope cases plus a
      registration case parsing BOTH `.claude/settings.json` and `plugins/soleur/hooks/hooks.json`.
      **Auto-globbed — do NOT add a `run_suite` line.**
- [ ] 1.5 Confirm every suite carries an anti-vacuity floor reporting directly per ADR-193, and a
      case-count check equal to its matrix row count.

## Phase 2 — #7947 GREEN

- [ ] 2.1.1 `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py`. Structural
      predicate first, then the named credential-name list as data in one place (`password`,
      `passphrase`, `secret`, `token`, `api key`, `client secret`, `recovery code`, `one-time
      code`, `otp`, `2fa`, `pin`) — English-only, and documented as such.
- [ ] 2.1.4 NOT a streaming filter: read stdin to EOF and classify before writing a byte. The cap
      is a refusal, never a truncation. Normalisation is per-node and decision-only so the
      passthrough path stays byte-exact.
- [ ] 2.1.2 Import or vendor the cap and NFKC/strip front-half from
      `plugins/soleur/skills/incident/scripts/redact-engine.py` with a pointer comment. Do not retype.
- [ ] 2.1.3 Exit 2 writes a plain-language stderr diagnostic naming the screenshot alternative,
      never echoing input; stdout stays empty.
- [ ] 2.2.1 Rewrite `### Login Flow` in `agent-browser/SKILL.md` to the single rule; drop the
      `password123` literal.
- [ ] 2.2.2 Apply the rule to `test-browser`, `reproduce-bug`, `qa`, `feature-video` SKILL.md.
- [ ] 2.2.3 `cf-token-scope/references/widen-playbook.md` — carve-out: route the snapshot through the
      redactor, keep the screenshot-scoping constraint verbatim.
- [ ] 2.2.4 Correct the inverted `browser_evaluate` rule in BOTH `cf-token-scope` files: `filename`
      keeps the value out of the transcript; without it the return value is written there.
- [ ] 2.2.5 Tier B, for consistency only: `review/references/review-e2e-testing.md`,
      `agents/operations/ops-provisioner.md`.
- [ ] 2.3.1 Walker 1 as a second rule family in `scripts/lint-credential-path-literals.py`, with a
      `--population-root` seam so M4 is executable.
- [ ] 2.3.2 Predicate reds on an un-piped retry documented as the exit-2 recovery.
- [ ] 2.4.1 `.claude/hooks/browser-snapshot-credential-guard.sh` — Bash arm only, **allowlist not
      denylist**, kill-switch env var, `.claude/.rule-incidents.jsonl` reason row. Approved form
      requires `2>&1` before the pipe (a pipe redirects stdout only; the Bash tool captures both).
      Deny absolute-path, `env`/`timeout`-prefixed, redirected, `tee`-d and command-substituted
      shapes.
- [ ] 2.4.2 Register in `plugins/soleur/hooks/hooks.json` (the shipped surface) AND
      `.claude/settings.json` (this checkout).
- [ ] 2.5 Add the hook's row to the `.claude/hooks/README.md` PreToolUse table.

## Phase 3 — #7946 GREEN

- [ ] 3.1.1 Apply the Phase 3.1 convergence rule; mint `followthroughs-read-prd` via Playwright at
      the measured scope set, under the #7947 discipline (no snapshot of a credential page,
      shell-expanded credentials, scoped screenshots).
- [ ] 3.1.2 Capture with `browser_evaluate(filename:)` — WITH the filename, to an absolute path
      inside a `mktemp -d` created mode 0700, outside the repo and outside any MCP output dir.
- [ ] 3.1.3 No credential value is ever an MCP tool-call argument (MCP args are not shell-expanded).
      The auth handoff is operator-in-browser, or the `agent-browser` Bash path where `$VAR`
      expands. Otherwise stop and file a tooling gap.
- [ ] 3.2.0 Dry-run the whole capture chain against `ZZQP-SENTINEL-7947` on the Phase 0.1 page
      first. Only then point it at Sentry.
- [ ] 3.2.1 In ONE trap scope (`trap cleanup EXIT INT TERM HUP`): read, JSON-decode,
      `gh secret set <NAME> --body-file -` from the decode's stdout (never `--body "$TOKEN"`),
      read-back verify, then remove. On write failure, delete the just-minted integration in-page
      before the trap fires. `shred -u` is best-effort on journaled and CoW filesystems — the 0700
      dir and the short lifetime are the primary control.
- [ ] 3.2.2 Assert `.auth.scopes` contains the derived minimum and nothing outside the smallest
      dashboard-expressible superset; record any implied extra in the ADR with its granting level.
- [ ] 3.2.3 Re-run all four endpoint probes against the NEW token before migrating any file.
- [ ] 3.3.1 Migrate all sixteen files' consumption to `SENTRY_FOLLOWTHROUGH_RO_TOKEN`, including the
      two `.test.sh` and the comment in `git-data-birth-emitter-6982.sh`.
- [ ] 3.3.2 Rewrite the ADR-202 xtrace refusal predicate and message in all 13 files carrying it,
      preserving `${VAR:+x}` (never `${VAR:-}`).
- [ ] 3.3.3 Rule D drawdown: remediate every touched baselined script to Rule D form
      (`curl --disable --noproxy '*'`, pinned destination) and delete its baseline line.
- [ ] 3.3.4 `sentry-checkins-3859.sh`: move `ORG` to `jikigai-eu` in the same commit.
- [ ] 3.3.5 Watch the multi-credential predicates: `anthropic-admin-key-6297.sh` concatenates three
      `${VAR:+x}` terms — rename the Sentry term, never delete it.
- [ ] 3.3.6 `git-data-birth-emitter-6982.sh` has NO xtrace refusal while binding
      `BETTERSTACK_QUERY_PASSWORD` via `${!v:-}` (which expands the VALUE under `set -x`). This PR
      opens the file, so it gains an unconditional refusal covering every credential it binds.
- [ ] 3.4.1 Rewrite the affected tracker directives FIRST (issue-body edits, revertible).
      Enumerate with `--limit 200` and commit the timestamped census fixture.
- [ ] 3.4.2 Add `SENTRY_FOLLOWTHROUGH_RO_TOKEN` and drop `SENTRY_AUTH_TOKEN` from the sweeper env in
      the same commit as the migration. **No compatibility shim.**
- [ ] 3.4.3 Add `SENTRY_ISSUE_RO_TOKEN` to the sweeper env, closing the `second channel: SKIPPED`
      degradation.
- [ ] 3.5.1 Migrate `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`.
- [ ] 3.5.2 Retarget (never delete) the AC13 assertion in
      `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`.
- [ ] 3.6 Rule E in `scripts/lint-shell-trace-credential-refusal.py`: per-rule exclusion override for
      `*.test.sh`, min-cardinality floor 14 with a test-only override env var.
- [ ] 3.7 Write `knowledge-base/engineering/operations/runbooks/sentry-org-token-rotation.md`,
      including a `## Failure modes` table with a next ACTION per row.
- [ ] 3.8 Update all THREE occurrences in `followthrough-convention.md`, plus the header comment in
      `scripts/sweep-followthroughs.sh` and `plugins/soleur/skills/schedule/SKILL.md`.
- [ ] 3.9 Extend `.claude/hooks/follow-through-directive-gate.sh` to reject a `secrets=` name absent
      from the sweeper's `env:` block, with a mutation row for the retired name.

## Phase 4 — Documentation, ADR, C4, register

- [ ] 4.1 Amend `ADR-031-sentry-as-iac.md`: fourth credential class, measured scopes, store
      discriminator, Org-Auth-Tokens-vs-Internal-Integrations surface distinction, narrow-by-adding
      rule, duplicated-ordinal header note.
- [ ] 4.2 New ADR (conditional on 0.1): per-path statement of what ships, ADR-202 applied honestly,
      P7 unachieved on the MCP path, plus the CLO's two Article 33 bounding conditions.
- [ ] 4.3 Widen the `github -> sentry` edge label in `model.c4` to name all three credentials
      (do NOT remove the existing name — it is the Terraform provider's env-var name); regenerate
      `model.likec4.json`; run the C4 syntax, render and count-parity suites.
- [ ] 4.4 Update the post-mortem's `### Still open` ONLY. Leave `art_33_*` / `art_34_*` frontmatter,
      the Art. 4(12) section and the asymmetry table's read-limb column untouched.
- [ ] 4.5 Article 30 register: additive dated brackets on PA-8 §(g) and PA-31 §(g), slots filled from
      the actual mint and diff; PA-36 stays free. One `## Completed Compliance Work` row.
- [ ] 4.6 File deferrals: `.mcp.json` proxy (`priority/p1-high`), personal-token revocation, ADR-031
      ordinal collision, `browser_type` echo if reproduced, shipped-hook work if applicable.

## Phase 5 — Follow-through enrolment

- [ ] 5.1 `scripts/followthroughs/sentry-followthrough-token-cutover-7946.sh`, referencing any
      retired name through env indirection so Rule E stays green.
- [ ] 5.2 Enrol it: `<!-- soleur:followthrough script=... earliest=<deploy+Nd> secrets=... -->`,
      the `follow-through` label, and its `secrets=` names wired into the sweeper env.

## Phase 6 — Verification

Mirrors the plan's `### Phase 6 — Verification`.

- [ ] 6.1 Walk every pre-merge acceptance criterion in the plan and record the command output.
- [ ] 6.2 Re-derive the ADR ordinal across all `origin/*` refs; sweep plan, spec, tasks and probe on
      any renumber.
- [ ] 6.3 Confirm the published legal corpus is untouched
      (`git diff --name-only origin/main -- plugins/soleur/docs/pages/legal/ docs/legal/` empty).
