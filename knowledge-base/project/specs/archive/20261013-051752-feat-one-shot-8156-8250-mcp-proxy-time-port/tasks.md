# Tasks — feat-proxy-wrapped-playwright-mcp-default (#8156)

Plan: `knowledge-base/project/plans/2026-09-18-feat-proxy-wrapped-playwright-mcp-default-plan.md`
Issue: #8156 · Type: security · Priority: p1-high · Lane: cross-domain (eng + CLO)
CPO sign-off required before `/work` begins (`single-user incident` threshold).

## Phase 0 — Floor probe (gating)

- [x] T0.1 Scratch-plugin probe on the `engines.claude-code >=2.1.139` floor and the
      installed CLI: (a) plugin-root `.mcp.json` stdio entry registers
      `mcp__plugin_soleur_playwright__*` tools; (b) `${CLAUDE_PLUGIN_ROOT}`
      expands inside plugin `.mcp.json` `command`/`args`; (c) user-scoped
      `playwright` + plugin `playwright` coexist with both namespaces live;
      (d) macOS launch sanity; (e) record the `mcp-logs-*/` directory name used
      for the connect-failure playbook.
- [x] T0.2 Write `plan-time-probe-record.md` in this spec dir. If the floor
      fails, record the minimum working version — the `engines` bump becomes a
      conditional manifest edit (AC10, CPO-flagged).

## Phase 1 — The wrapped registration

- [x] T1.1 `playwright-mcp-redact-proxy.py`: add `--user-data-dir-name
      <basename>` — resolve under `$XDG_CACHE_HOME` (default `~/.cache`) via
      `os.path.expanduser`; inject `--user-data-dir=<abs>` into child argv only
      when child argv lacks `--user-data-dir`; refuse-to-start on
      `..`/separator basename, on flag+explicit-dir ambiguity, on a RELATIVE
      `XDG_CACHE_HOME` value, and when `~` cannot resolve (HOME unset) —
      mirroring `scripts/lib/scratch-root.sh`'s XDG semantics; update the
      module header. No behavior change when the flag is absent.
- [x] T1.2 Create `plugins/soleur/.mcp.json`: `playwright` → `command:
      "python3"`, args `[${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py,
      --user-data-dir-name soleur-playwright-mcp-profile, --, npx,
      @playwright/mcp@0.0.78]` — no `bash`, no `--config`, no literal
      `--user-data-dir`.
- [x] T1.3 Proxy suite rows: flag injection + `$XDG_CACHE_HOME` + `~/.cache`
      fallback; `..`/separator refusal; flag+explicit refusal; RELATIVE
      `XDG_CACHE_HOME` refusal; HOME-unset (`~` unresolvable) refusal;
      flag-absent argv-identical regression row; plugin-registration Guard-3
      row (parse `plugins/soleur/.mcp.json`, derive pin from repo `.mcp.json`);
      one mutant per clause.
- [x] T1.4 `agent-browser/SKILL.md` §"Wrapping the server" rewrite:
      plugin-registered default (prefix, preconditions, `/mcp` toggle,
      separate-profile note); manual `.mcp.json` shape demoted to "advanced";
      connect-failure playbook extended with the plugin server log dir.

## Phase 2 — Skills resolve to the wrapped server

- [x] T2.1 Sweep 13 `mcp__playwright__*` literals (agent-browser 3,
      reproduce-bug 6, cf-token-scope/widen-playbook 1, plan 1, work 1) to
      `mcp__plugin_soleur_playwright__*`; retain only literals scoped to a
      customer's OWN `playwright` registration (AC4 survivor set).
- [x] T2.2 Add preference clause (plugin server already wrapped; other
      `mcp__<server>__` prefixes are separate unwrapped registrations) beside
      — not inside — the verbatim S2 paragraph in `qa`, `ux-audit`,
      `reproduce-bug`, `cf-token-scope/widen-playbook`. `S2_CANONICAL`
      unchanged.
- [x] T2.3 `EXPECTED_GATE_REFS` update iff a SKILL.md gains a new
      `${CLAUDE_PLUGIN_ROOT}`-anchored proxy reference (likely zero).

## Phase 3 — Records, register, deferral

- [x] T3.1 ADR-213: append `## Addendum — 2026-09-XX (#8156)` (reach (b)
      closed; dedicated-`.mcp.json`-over-inline rationale; profile isolation;
      Option-C deferral + criteria; toggle-off/precondition caveats).
- [x] T3.2 `model.c4`: update `snapshotGuard` (SHIPS vs WIRES) and
      `playwrightMcp` ("until #8156" clause) descriptions; run
      `scripts/regenerate-c4-model.sh`; four C4 gates green.
- [x] T3.3 `article-30-register.md`: PA-8 §(g) re-append reach (b)
      (append-only); PA-31 §(g) assessment line.
- [x] T3.4 Dated addendum on
      `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md`
      superseding row-18 evidence ("no `plugins/soleur/.mcp.json` exists").
- [x] T3.5 File the Option-C deferral issue (`deferred-scope-out`,
      `domain/engineering`, `type/security`) with the re-evaluation criteria
      and upstream refs (#47859 transcript persistence, #54161 hook output
      semantics); reference it from the ADR addendum.

## Verification gates

- [x] `python3 plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` green — 316/316 cases, 63/63 mutants; re-run post-review-fixes **323/323, 65/65 mutants**
- [x] `bun test plugins/soleur/test/codex-plugin.test.ts plugins/soleur/test/devin-plugin.test.ts` green unmodified — 14 pass
- [x] `bun test apps/web-platform/test/plugin-root-anchoring.test.ts` green — 26/26 (EXPECTED_GATE_REFS unchanged)
- [x] `bash scripts/lint-credential-path-literals.test.sh` green — 41/41; lint-legal-registers 11/11; c4 gates 4/4; cron-ux-audit 30/30; components+skill-security-scan 1353 pass
- [x] AC1–AC11 verified (AC12 lands with the PR body); AC11 diff-scope clean (Files-to-Edit updated for the review-driven additions)
- [x] PR body: `Closes #8156`, `## Changelog` (MINOR — new plugin MCP
      surface), Option-C issue referenced
- [x] Review dispositions (2026-09-18): architecture P1 resolved by
      vendored-tree exclusion (`rm -f "$DEST/.mcp.json"` in both vendor steps,
      Guard-3-pinned; reach (c) by exclusion recorded in ADR/audit/register/C4);
      P1-2 stored-profile prose scoped (cf-token-scope, work, plan); compound
      stale literal fixed; simplicity P2s fixed (dup/dash refusals, dead
      assert, README table, alternatives row) — `dd085a96a`
- [x] Review round-2 dispositions (2026-09-18, fix-inline each): headed
      premise corrected (0.0.78 defaults headed, `channel: chrome` — plan/
      SKILL/model.c4/audit); Devin `.mcp.json` reach corrected (docs-honored,
      benign-wrapped; Codex unverified); `--strict-mcp-config` suppression
      measured (TOOL-ABSENT/TOOL-PRESENT, 2.1.273); sink surface widened
      (SINK_FLAGS +5 incl. `--save-trace`/`--save-video`/`--no-sandbox`/
      `--ignore-https-errors`/`--daemon`; config contextOptions +
      chromiumSandbox arms; VALUE_FLAGS +2); log control-char scrub; vet_error
      rebuild; vet_other_result; realpath profile root; mutation suite
      retargeted (31/48) + 2 new mutants — **419/419 cases, 77/77 mutants**
- [x] Prose follow-through (2026-09-18): session-rules-loader roster reads
      all three committed sources; help.md playwright row (Claude+Devin);
      guard.sh residual re-pointed at #8286; review-e2e prefer bullet;
      reproduce-bug absent-server fallback; SKILL.md arm-1 full refusal
      enumeration + launch-degradation playbook (display-less/Chrome-absent/
      Wayland)

- [x] Ship + post-merge verification (2026-09-18): PR #8275 merged as
      `0bb97c229` (squash, auto-merge); 12/12 post-merge workflows settled
      (11 success, 1 conditional skip); vendored `.mcp.json` exclusion
      observed executing in Web Platform Release run 35369612030; plugin
      release `v3.278.17` tagged at the merge commit and ships the
      registration; web release `web-v0.276.19`.

## Out of scope

- #8250 (test-portability chore) — explicitly not planned.
- Option C (PostToolUse/PreToolUse hook net) — deferred, tracked by its own issue.
