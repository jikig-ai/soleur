# Review synthesis: PR #12414 (A-0), panel at bb10ba32d8

Panel: 13 seats (design pass: code-simplicity, architecture; full panel: security-sentinel, test-design-reviewer, pattern-recognition, git-history-analyzer, code-quality-analyst, performance-oracle, data-integrity-guardian, agent-native-reviewer, user-impact-reviewer, semgrep-sast + shellcheck/actionlint, structural-enumeration). Tier: aggregate pattern. No P1 from any seat. Semgrep/shellcheck/actionlint: no net-new findings.

Structural-cause roll-up: the verification added by the fix is narrower than the property it names, in three places: (1) text guards that count lines (F6/F8, V2) instead of occurrences or the plan command; (2) the wrapper's predicate terms (exact address, deposed, importing, read verb, two pool entries) have no fixture that reds them; (3) the chokepoint census scans a subset of the tree.

## Fix inline (pr-introduced)

1. P2 trap-tempfile high-water ratchet goes 36 to 37 because the wrapper uses mktemp (code-quality, pattern). Baselines ratchet down only, so fix the code: write the normalised copy next to the plan file (`${plan_json}.serve-norm.$$`), refuse an existing path or symlink, umask in a subshell, remove on every path, drop the lint annotation; re-run `--check-highwater` and `scripts/lint-trap-tempfile-ownership.test.sh`. Rework pn8/pn9 to observe the sibling file (rm shim + directory listing).
2. P2 wrapper predicate terms unpinned (test-design): add fixtures for module-addressed no-op pool, two pool entries, `read` verb, deposed, importing. G1.7 is NOT equivalent: a `["read"]` pool plus POLICY_CREATE passes through the remnant branch if the default arm falls through, so the default arm is load-bearing.
3. P2 wrapper: one jq verdict token instead of three passes, `(.address // "")` null-safe, `::error::` on every refusal (simplicity P2-2, code-quality).
4. P2 F8/F6/V2 text guards defeated by dead-line / echo / duplicate-`-var` / heredoc `default = 1` variants (test-design): anchor F8 to the `terraform plan` continuation chain, count occurrences, take the single top-level `default`.
5. P2 parity T4 only mutates 2 clauses (test-design): table of per-clause mutants and per-pair-member; repo-wide check that the random_bytes address is referenced only inside proxy-hello-hmac.tf.
6. P3 chokepoint census scans a subset of the tree (code-quality, test-design, structural, pattern): scan the whole repo minus .git, node_modules, knowledge-base, .worktrees, and the lib.
7. P2 (architecture, history) the "only feeder is the serve arm / 0-to-1 only through the gate chain" guarantee ends at the first drain: say so in the variables.tf comment and the ADR addendum; add a runbook pre-step for operator full applies ("the plan must show no pool change, or you are re-serving web-2 outside the gate chain").
8. P2 (architecture) web-host-replace.md has no LB step; a replace may change web-2's public IPv4 (verify `primary_ip` in server.tf) so the pool origin address goes stale: add a post-replace note to re-run `ga-pool-update mode=serve`.
9. P3 wording: ADR-068 "never names the variable" (names it five times: reword to "did not name it before this addendum"); wrapper comment "holds no state values" (reword to: same content as the plan JSON's resource_changes, 0600, removed on every path); variables.tf/cloudflare-lb.tf/cf-lb-overlay.yml say drain is explicit via `mode=drain` and ga-overlay (ga-overlay cannot drain a live pool: reword); rename warning in proxy-hello-hmac.tf (a doppler_secret rename without `moved {}` can delete the secret from prd); host_proxy_tls_enabled description date (31c8a232fe / #12203); C.3 header and C.3-sweep messages in lb-weight-gate.test.sh still say "drained member pre-flip"; parity row titles ("T4", "T1/T3") and the wrapper comment's unverifiable "17 selectors".
10. P3 plan edits (user-impact, agent-native): User-Brand Impact gets one line on the release arm restarting each live host's container in turn (live users 0) and one on the runner-local `terraform show -json` dump; Phase 4.3 presence check uses a tokenising names read (not `^...$` grep); drift check names the log line `No drift detected in web-platform` on the `apps/web-platform/infra` leg.
11. P3 ADR-118 one-paragraph amendment pointing at proxy-hello-hmac.tf (the six-resource family).
12. P3 cloudflare-lb.tf L160 description: add an adjacent comment that it is deliberately stale until an intended LB apply.
13. PR body must say: the release and a rolling deploy to both hosts fire on merge (web-2 restarts while serving), the revert rule (revert the flip hunk only), the local branch `w2prep-agent` encodes the opposite default and must not be merged, e2964b801d is outside the 100-run window so only two release precedents are verified.

## Scope-out / follow-ups (no new issue beyond the two planned, bundled)

- Stale web-2 weight-0 wording outside this diff: `web-platform-release.yml` ~L1401, `workspaces-luks-verify.yml` ~L1270, `server.tf` ~L620-630, `origin-tls-strict-flip.md`, `origin-tls-canary.md`, `web-host-reboot.md`, `web2-luks-rebirth-9372.md`, model.c4 L351/L355/L926 (folded into the planned stale-wording issue).
- For PR A (comment on #12289): fail-closed absent-key startup report (Sentry mirror), preflight names-only presence read, scrub-list entry in sensitive-keys.ts, rotation counter for random_bytes.proxy_hello_hmac in the destroy guard, rolling-deploy mixed-version window (architecture seat suggests an accept-unsigned-and-log phase; the CTO ruled fail-closed with N=0 live users: record as input for A's consult, not adopted here), key not in `keepers`/`lifecycle` pins.

## Rejected / not adopted

- Remove the default (history): the owner asked for default 1 and the CTO ruled it; documentation plus runbook pre-step instead.
- Delete work-log.md (simplicity P3-3): it is the plan's recorded evidence; kept.
- Collapse F8 into F6 (simplicity P2-3): F8 alone catches `${WEB2_LB_WEIGHT}` in ga_overlay (battery row G2.3); kept, hardened per item 4.
- Redactor rows redundant (simplicity P3-2, test-design): keep the clear-hex row; add a show-shape counted fixture.

## Environment blocker at synthesis time

Bash is failing with EDQUOT on the volume holding /tmp/claude-1000 (Claude Code's tmp dir). Nothing was deleted. Fixes resume once space is freed or CLAUDE_CODE_TMPDIR points elsewhere.
