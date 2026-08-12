// Unit tests for the git-lock marker telemetry hook (#6184 observability follow-up):
// the pure extractor, tool_response coercion, and the PostToolUse hook's fail-open
// classification (wedge → error, diag-only → warn, non-Bash → no-op).
import { describe, test, expect } from "vitest";
import { readFileSync, readdirSync, existsSync } from "fs";
import { join } from "path";
import {
  extractGitLockMarkers,
  toolResponseToText,
  createGitLockMarkerHook,
} from "../server/git-lock-marker-telemetry";

const DIAG =
  "SOLEUR_GIT_LOCK_DIAG file=.git/config.lock type=chardevice owner=nobody perms=666 mtime=1 age=1140 mount=tmpfs rdev=1:3 whiteout=no";
const UNREMOVABLE =
  'SOLEUR_GIT_LOCK_UNREMOVABLE file=.git/config.lock type=chardevice rdev=1:3 errno=none reason=non-regular-lock hint="observed non-regular config lock"';
const WEDGE =
  "worktree wedge: could not apply shared-config prerequisites in .git (see errors above).";
const TEMP_WEDGED =
  'SOLEUR_GIT_LOCK_TEMP_WEDGED file=config.soleur-tmp type=temp-write-failed reason=lockless-temp-unwritable hint="glob mask"';
// #5934 config-target-masked wedge (this PR): the LIVE root cause + the two adjacent
// telemetry-blind markers (NO_GIT_REPOSITORY gate, SOLEUR_FEATURE_PUSH_FAILED) + the
// [error]-prefixed "worktree wedge:" line emitted through headless_or_stderr.
const CONFIG_TARGET_MASKED =
  "SOLEUR_GIT_CONFIG_TARGET_MASKED file=config reason=target-bind-mount";
const CONFIG_TARGET_MASKED_REMEDY =
  "SOLEUR_GIT_CONFIG_TARGET_MASKED file=config reason=bare-under-mask remedy=host-pre-seed-.git/config-before-bwrap-mask see=#6191,#5934";
const FEATURE_PUSH_FAILED = "SOLEUR_FEATURE_PUSH_FAILED branch=feat-x";
const NO_GIT_REPO =
  "NO_GIT_REPOSITORY: cannot run a worktree operation — the workspace has no git checkout.";
const WEDGE_PREFIXED =
  "[error] worktree wedge: could not apply shared-config prerequisites in .git";
// A benign non-bare-skip-under-mask diagnostic (D3): a masked config on a non-bare clone
// where the bare surgery is correctly skipped — mirrored, but NOT a wedge (creation proceeds).
const MASK_SKIP =
  'SOLEUR_GIT_CONFIG_MASK_SKIP file=config reason=non-bare-skip hint="masked config on a non-bare clone; bare surgery skipped"';
// #5934 round-3: verify_worktree_created's path-mismatch exit — the LIVE round-2 failure
// (a relative GIT_ROOT made the expected path relative while git reported it absolute). Was
// silent to every sink; now a mirrored WEDGE.
const WORKTREE_VERIFY_FAILED =
  "SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=path-mismatch branch=feat-x expected=.git/.worktrees/feat-x actual=/workspaces/abc/.git/.worktrees/feat-x";

describe("extractGitLockMarkers", () => {
  test("pulls each marker sentinel out of surrounding bash noise", () => {
    const text = ["Preparing worktree", DIAG, "  updating files", UNREMOVABLE, "done"].join("\n");
    const markers = extractGitLockMarkers(text);
    expect(markers.map((m) => m.line)).toEqual([DIAG, UNREMOVABLE]);
  });

  test("classifies UNREMOVABLE / TEMP_WEDGED / 'worktree wedge' as wedged; DIAG as not", () => {
    expect(extractGitLockMarkers(DIAG)[0]?.wedged).toBe(false);
    expect(extractGitLockMarkers(UNREMOVABLE)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(WEDGE)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(TEMP_WEDGED)[0]?.wedged).toBe(true);
  });

  test("classifies IDENTITY_WEDGED as wedged; IDENTITY_DIAG as a benign (mirrored) marker", () => {
    const identityWedged =
      "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=native-eexist file=config";
    const identityCommonDir =
      "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=common-dir-unresolved file=config";
    const identityDiag =
      "SOLEUR_GIT_LOCK_IDENTITY_DIAG source=ensure_worktree_identity reason=identity-drift-set-from-global";
    expect(extractGitLockMarkers(identityWedged)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(identityCommonDir)[0]?.wedged).toBe(true);
    // Benign precondition marker: mirrored (MARKER_RE) but NOT a wedge (excluded from WEDGE_RE),
    // so a successful drift-set never pages as wedged=true / log.error.
    expect(extractGitLockMarkers(identityDiag).length).toBe(1);
    expect(extractGitLockMarkers(identityDiag)[0]?.wedged).toBe(false);
  });

  test("matches both #7102 orphan-reaper sentinels, neither classified as a wedge", () => {
    // Scope note: this asserts REGEX MEMBERSHIP — that a marker reaching this
    // extractor is matched and correctly classified. It does not assert that
    // any particular surface delivers one. `cleanup-merged` reaches this hook
    // on the platform surface (go.md Step 0 runs it, and that plugin loads via
    // the same options object that registers this hook); from the local CLI it
    // does not, because settings.json registers no PostToolUse "Bash" hook.
    // See the SURFACE SCOPE note in git-lock-marker-telemetry.ts.
    const orphan =
      'SOLEUR_ORPHAN_UNREMOVABLE count=2 cleaned=1 errno=EACCES names=feat-a,feat-b reason=rm-partial hint="partially-deleted orphans survive; see git-worktree SKILL.md §Sharp Edges"';
    expect(extractGitLockMarkers(orphan).length).toBe(1);
    // NOT paged: the reaper returns 0 and the rest of cleanup proceeds, so
    // nothing is wedged — and the condition recurs on every run until the
    // root-owned residue is cleared, so paging it would be pure noise.
    expect(extractGitLockMarkers(orphan)[0]?.wedged).toBe(false);

    const registry =
      'SOLEUR_ORPHAN_REGISTRY_UNAVAILABLE reason=git-worktree-list-failed errno=OTHER hint="refusing to reap; every dir would read as unregistered — see git-worktree SKILL.md §Sharp Edges"';
    expect(extractGitLockMarkers(registry).length).toBe(1);
    expect(extractGitLockMarkers(registry)[0]?.wedged).toBe(false);
  });

  test("matches the #5934 config-target-masked family and classifies it as wedged", () => {
    expect(extractGitLockMarkers(CONFIG_TARGET_MASKED)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(CONFIG_TARGET_MASKED_REMEDY)[0]?.wedged).toBe(true);
    // The remedy marker must survive verbatim (it names the host-seed fix for the operator).
    expect(extractGitLockMarkers(CONFIG_TARGET_MASKED_REMEDY)[0]?.line).toBe(
      CONFIG_TARGET_MASKED_REMEDY,
    );
  });

  test("mirrors the benign SOLEUR_GIT_CONFIG_MASK_SKIP non-bare-skip diagnostic but does NOT page it (D3)", () => {
    expect(extractGitLockMarkers(MASK_SKIP).length).toBe(1);
    expect(extractGitLockMarkers(MASK_SKIP)[0]?.wedged).toBe(false);
  });

  // #7394 — the bare-config polarity markers. Classification is by `branch=`, not by
  // marker name, because one name covers both a recoverable and an unrecoverable outcome.
  test("mirrors both SOLEUR_GIT_BARE_POISON branches without paging (the run proceeded)", () => {
    for (const branch of ["healed", "clean"]) {
      const line = `SOLEUR_GIT_BARE_POISON git_dir=/w/.git extension=present shared_bare=true wt_override=absent git_version=2.53.0 branch=${branch}`;
      expect(extractGitLockMarkers(line).length, `branch=${branch} must be mirrored`).toBe(1);
      expect(
        extractGitLockMarkers(line)[0]?.wedged,
        `branch=${branch} is informational — normalization ran and the run continued`,
      ).toBe(false);
    }
  });

  test("pages SOLEUR_GIT_BARE_SELFHEAL only at branch=failed", () => {
    const ok =
      "SOLEUR_GIT_BARE_SELFHEAL worktree=feat-a git_dir=/w/.git/worktrees/feat-a git_version=2.53.0 branch=ok";
    const failed =
      "SOLEUR_GIT_BARE_SELFHEAL worktree=feat-a git_dir=/w/.git/worktrees/feat-a git_version=2.53.0 branch=failed";
    // Recovered: the worktree is usable again, so this is a mirrored diagnostic.
    expect(extractGitLockMarkers(ok).length).toBe(1);
    expect(extractGitLockMarkers(ok)[0]?.wedged).toBe(false);
    // Not recovered: git keeps reporting a valid worktree as bare, so every
    // require_working_tree-gated subcommand refuses until a human fixes permissions.
    expect(extractGitLockMarkers(failed).length).toBe(1);
    expect(extractGitLockMarkers(failed)[0]?.wedged).toBe(true);
  });

  test("does NOT page the create-time seed failure (branch=seed-failed)", () => {
    // The seed is defense-in-depth and inert while extensions.worktreeConfig is absent,
    // so it is deliberately reported under a DISTINCT branch value. Were it to reuse
    // `failed`, a non-fatal pin would page — the "safe degradation becomes noise" class.
    const seed =
      "SOLEUR_GIT_BARE_SELFHEAL worktree=feat-a reason=seed-write-failed git_version=2.53.0 branch=seed-failed";
    expect(extractGitLockMarkers(seed).length).toBe(1);
    expect(extractGitLockMarkers(seed)[0]?.wedged).toBe(false);
  });

  test("adds SOLEUR_FEATURE_PUSH_FAILED + NO_GIT_REPOSITORY to the ingest allowlist (D1b) as wedges", () => {
    expect(extractGitLockMarkers(FEATURE_PUSH_FAILED)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(NO_GIT_REPO)[0]?.wedged).toBe(true);
  });

  test("matches SOLEUR_GIT_WORKTREE_VERIFY_FAILED (#5934 round-3) and classifies it as a wedge", () => {
    const [m] = extractGitLockMarkers(WORKTREE_VERIFY_FAILED);
    // The full marker (incl. the relative expected= and absolute actual= paths that name the
    // round-2 root cause) survives verbatim for diagnosis.
    expect(m?.line).toBe(WORKTREE_VERIFY_FAILED);
    expect(m?.wedged).toBe(true);
  });

  test("tolerates a leading [error] prefix on the worktree wedge line (D1c, headless_or_stderr sink)", () => {
    const [m] = extractGitLockMarkers(WEDGE_PREFIXED);
    expect(m?.line).toBe(WEDGE_PREFIXED);
    expect(m?.wedged).toBe(true);
  });

  test("matches the readiness-gate SOLEUR_GIT_REPO_DIAG forensic and treats it as wedged", () => {
    const repoDiag =
      'SOLEUR_GIT_REPO_DIAG ready=false git_dir=dir config_worktree=chardevice config_lock=chardevice rev_parse_rc=128 config_parse_rc=128 err="fatal: bad config line 1 in file .git/config"';
    const [m] = extractGitLockMarkers(repoDiag);
    expect(m?.line).toBe(repoDiag);
    // The probe RAN and reported not-ready → a genuinely blocked session.
    expect(m?.wedged).toBe(true);
  });

  test("SOLEUR_GIT_REPO_DIAG source=probe-unreachable is mirrored but NOT wedged", () => {
    // #7474. go.md emits this when the probe could not RUN — either the plugin root
    // did not verify, or it verified and does not carry the probe (a stale install).
    // Neither says anything about the repo: go.md falls back to inline `git rev-parse`
    // probes that decide readiness themselves. Classifying these as wedges turns a torn
    // install on a HEALTHY repo into a platform-integrity error at every session start.
    for (const reason of ["plugin-root-unverified", "absent-from-verified-root"]) {
      const line = `SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=${reason}`;
      const [m] = extractGitLockMarkers(line);
      // Still mirrored — the operator can see it.
      expect(m?.line).toBe(line);
      // But not paged.
      expect(m?.wedged).toBe(false);
    }
  });

  test("returns [] for output with no markers, and for empty input", () => {
    expect(extractGitLockMarkers("just some normal git output\nProsuming worktree")).toEqual([]);
    expect(extractGitLockMarkers("")).toEqual([]);
  });

  test("does not match a marker token embedded mid-line (anchored to line start)", () => {
    expect(extractGitLockMarkers("echo SOLEUR_GIT_LOCK_DIAG is the sentinel name")).toEqual([]);
  });

  test("bounds output: caps the number of markers even on a flood", () => {
    const flood = Array.from({ length: 500 }, () => UNREMOVABLE).join("\n");
    expect(extractGitLockMarkers(flood).length).toBeLessThanOrEqual(12);
  });

  test("truncates an over-long marker line", () => {
    const long = `${UNREMOVABLE} ${"x".repeat(2000)}`;
    const [m] = extractGitLockMarkers(long);
    expect(m.line.length).toBeLessThanOrEqual(601);
    expect(m.line.endsWith("…")).toBe(true);
  });
});

describe("toolResponseToText", () => {
  test("passes a string through", () => {
    expect(toolResponseToText(DIAG)).toBe(DIAG);
  });
  test("joins stdout + stderr on an object response", () => {
    expect(toolResponseToText({ stdout: "out", stderr: "err" })).toBe("out\nerr");
  });
  test("flattens an array of text content blocks", () => {
    expect(toolResponseToText([{ type: "text", text: DIAG }, { type: "text", text: "x" }])).toBe(
      `${DIAG}\nx`,
    );
  });
  test("unknown shapes yield empty string (no markers)", () => {
    expect(toolResponseToText(42)).toBe("");
    expect(toolResponseToText(null)).toBe("");
    expect(toolResponseToText({ foo: 1 })).toBe("");
  });
});

describe("drift guard: every sentinel the shell script emits is mirrored", () => {
  // The extractor's MARKER_RE is a hand-maintained copy of the sentinel names in
  // worktree-manager.sh. If the script gains/renames a SOLEUR_GIT_LOCK_* sentinel and
  // this copy is not updated, the new wedge signal would go silently unmirrored — the
  // exact blindness this feature closes. Pin the two in sync: every `echo "SOLEUR_GIT_LOCK_*`
  // literal in the script must be matched by extractGitLockMarkers.
  test("extractor matches every SOLEUR_GIT_* sentinel echoed by the two shell scripts", () => {
    const scripts = [
      "../../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh",
      "../../../plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh",
    ].map((p) => readFileSync(join(__dirname, p), "utf8"));
    // SKILL.md files are scanned too (#7409). The two .sh paths above were the
    // entire scan set, so a `SOLEUR_*` sentinel authored in agent-executed
    // SKILL.md prose was invisible to this guard FOREVER — which is exactly what
    // happened: #7409's degrade-open arms minted a new failure marker across five
    // skills and it reached no telemetry layer, while the guard stayed green.
    // Derived from the directory rather than listed, so a new skill cannot add an
    // unmirrored sentinel by being absent from a hand-maintained array.
    const skillsDir = join(__dirname, "../../../plugins/soleur/skills");
    const skillDocs = readdirSync(skillsDir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => join(skillsDir, e.name, "SKILL.md"))
      .filter((p) => existsSync(p))
      .map((p) => readFileSync(p, "utf8"));
    // Both scripts emit `echo "SOLEUR_..."` sentinels; also collect the non-SOLEUR_-prefixed
    // fatal markers now in the allowlist (D1b): `NO_GIT_REPOSITORY` (the repo-readiness gate),
    // the `SOLEUR_FEATURE_*` push-failure, and the `worktree wedge:` give-up phrase (this PR
    // adds five new bare-echo copies of it — pin the literal so a future rename fails CI here
    // rather than silently un-mirroring). A renamed/added sentinel unmatched by MARKER_RE
    // must fail CI here rather than go silently unmirrored — the exact blindness this closes.
    const SENTINEL_RE = /echo "(SOLEUR_[A-Z_]+|NO_GIT_REPOSITORY|worktree wedge:)/g;
    const collect = (s: string) => [...s.matchAll(SENTINEL_RE)].map((m) => m[1]);

    // The two .sh files are a bounded surface: every sentinel they echo belongs to
    // this telemetry's domain, so collect them wholesale.
    const scriptSentinels = scripts.flatMap(collect);

    // SKILL.md is NOT bounded that way — a skill file is agent-executed prose for
    // whatever that skill does, so it carries sentinels from unrelated domains.
    // Requiring MARKER_RE to mirror all of them makes this guard fail on other
    // people's work and pressures the fix in the wrong direction: registering a
    // foreign marker for telemetry nobody asked for. Measured: the unscoped form
    // demanded `SOLEUR_PREFLIGHT_CHECK10_NOSANDBOX` (preflight's sandbox
    // diagnostic, landed on main by a sibling PR) be mirrored as a git-lock marker.
    // Scope the SKILL.md half to the domains extractGitLockMarkers actually covers.
    const DOMAIN_RE = /^(SOLEUR_GIT_|SOLEUR_WORKTREE_|SOLEUR_SESSION_STATE_)/;
    const skillSentinels = skillDocs.flatMap(collect).filter((n) => DOMAIN_RE.test(n));

    const unique = [...new Set([...scriptSentinels, ...skillSentinels])];
    expect(unique.length).toBeGreaterThan(0); // non-vacuous: the scripts DO emit sentinels
    // The SKILL.md scan is the whole point of the #7409 widening, and a prefix
    // filter is exactly the thing that can silently reduce it to a no-op — which
    // would reopen the blindness (a sentinel authored in prose, mirrored nowhere)
    // while leaving this test green. Assert the scan still contributes.
    expect(
      new Set(skillSentinels).size,
      "the SKILL.md scan matched no in-domain sentinel — DOMAIN_RE has drifted from the names skills actually echo, and the #7409 gap is open again",
    ).toBeGreaterThan(0);
    // Every emitted sentinel must be mirrored — except SUCCESS-PATH control signals,
    // which are read locally and are not forensics to log:
    //   - SOLEUR_GIT_REPO_READY — go.md's readiness gate reads it on the ready path.
    //   - SOLEUR_WORKTREE_LEASE_LIB_OK (#7409) — the positive counterpart of
    //     SOLEUR_WORKTREE_LEASE_LIB_MISSING, emitted once per worktree-manager.sh
    //     load whenever the lease library resolves, i.e. on EVERY invocation in a
    //     healthy tree (`list` included). It exists so that silence is not ambiguous
    //     at the operator's terminal — the only observability layer a marketplace
    //     install has. Mirroring the healthy path of the highest-frequency script in
    //     the system would be pure volume, and paging on it is meaningless: it
    //     reports that nothing is wrong. The FAILURE direction stays mirrored via
    //     ..._LIB_MISSING, so the signal this telemetry exists for is unaffected.
    const SUCCESS_PATH_CONTROL_SIGNALS = new Set([
      "SOLEUR_GIT_REPO_READY",
      "SOLEUR_WORKTREE_LEASE_LIB_OK",
    ]);
    for (const name of unique) {
      if (SUCCESS_PATH_CONTROL_SIGNALS.has(name)) continue;
      const sample = `${name} file=.git/config.lock type=chardevice rdev=1:3`;
      expect(
        extractGitLockMarkers(sample).length,
        `sentinel ${name} echoed by a git-worktree script or a skill's SKILL.md is not matched by the telemetry extractor — update MARKER_RE`,
      ).toBe(1);
    }
  });
});

describe("createGitLockMarkerHook", () => {
  const call = (input: unknown) =>
    createGitLockMarkerHook("/ws/abc")(input as never, undefined, {} as never);

  test("is a no-op for non-Bash tools", async () => {
    const out = await call({ tool_name: "Read", tool_response: UNREMOVABLE });
    expect(out).toEqual({});
  });

  test("is a no-op for Bash output with no markers", async () => {
    const out = await call({ tool_name: "Bash", tool_response: "Preparing worktree\ndone" });
    expect(out).toEqual({});
  });

  test("returns {} (observe-only) when markers ARE present", async () => {
    const out = await call({ tool_name: "Bash", tool_response: `${DIAG}\n${UNREMOVABLE}` });
    expect(out).toEqual({});
  });

  test("never throws — fail-open on a malformed input", async () => {
    const weird = { get tool_name() { throw new Error("boom"); } };
    await expect(call(weird)).resolves.toEqual({});
  });
});
