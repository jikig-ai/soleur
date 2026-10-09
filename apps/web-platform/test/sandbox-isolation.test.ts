/**
 * Cross-workspace isolation suite — Path C (hybrid) per
 * knowledge-base/project/specs/feat-verify-workspace-isolation/{spec,sdk-probe-notes}.md.
 *
 * Direct-bwrap cases (this file): FR2/3/4/5/6/7 — tier-4 process isolation, deterministic.
 * SDK-query cases (this file): FR2-smoke/8/9 — full-stack LLM sandbox, live API key.
 * Out of scope here: FR10/FR11 (LS, NotebookRead — covered by sandbox-hook/sandbox tests),
 * FR12 Task subagent (deferred follow-up). Coverage matrix pinned at EOF.
 *
 * FR9 local-dev gate: FR9 reads `~/.claude/projects/*.jsonl` from inside a
 * sandbox and sends excerpts to the Anthropic API. On a developer workstation
 * this could transmit historical transcripts if isolation regressed. Require
 * `CI=true` or `ANTHROPIC_ISOLATION_TEST_OK=1` to opt in.
 */

import { randomBytes } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { query } from "@anthropic-ai/claude-agent-sdk";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  createNamedWorkspacePair,
  createWorkspacePair,
  FS_DENY_RE,
  linkEscape,
  probeSkip,
  rescueStaleFixtures,
  seedMarker,
  shellQuote,
  spawnBwrap,
  spawnSandboxB,
  spawnSandboxed,
  waitForFile,
  type ProbeTier,
  type SandboxBHandle,
  type SandboxProcessHandle,
  type WorkspacePair,
} from "./helpers/sandbox-isolation-fixtures";

/**
 * Deploy-probe tier scoping (#2640). `SOLEUR_ISOLATION_TIERS` is a
 * comma-separated allowlist of probe tiers (`direct`, `query`). When set, a
 * suite whose tier is not listed is skipped BEFORE its `probeSkip` capability
 * evaluation — so `SOLEUR_ISOLATION_TIERS=direct` in the canary exec keeps the
 * query tier's live-ANTHROPIC_API_KEY runs (FR2-smoke/FR8/FR9) out of the
 * deploy path entirely, and FR9's `ANTHROPIC_ISOLATION_TEST_OK` gate is
 * unchanged (it lives inside the query describe, which never registers).
 * Unset or empty runs the full matrix — the default CI/local behavior.
 * An unrecognized tier name throws at load: a typo'd canary env would
 * otherwise skip every suite and report a vacuous green — the same
 * fail-loud opt-in class as `SOLEUR_ISOLATION_TEST_HOST` below.
 */
const KNOWN_TIERS: readonly ProbeTier[] = ["direct", "query"];

/**
 * In-image arm (#2640). `SOLEUR_ISOLATION_IN_IMAGE=1` marks a run inside the
 * baked runner image (the ci-deploy.sh canary probe sets it on the docker
 * exec). There PATH-resolved `bwrap` IS the deployed PATH shim
 * (/usr/local/bin/bwrap precedes /usr/bin) and the shim's repo path
 * (`infra/bwrap-shim/bwrap`) is never COPY'd in — so FR7b, which needs a
 * real-binary CONTROL arm plus a symlink to the repo shim, is structurally
 * un-runnable in-image and skips. FR7b's shim-splice property is still pinned
 * by test/bwrap-shim.test.ts and the faithful-canary replay, so the exclusion
 * loses no deploy signal.
 */
const ISOLATION_IN_IMAGE = process.env.SOLEUR_ISOLATION_IN_IMAGE === "1";

function parseIsolationTiers(raw: string | undefined): Set<ProbeTier> | null {
  if (raw === undefined || raw.trim() === "") return null;
  const tiers = new Set<ProbeTier>();
  const unknown: string[] = [];
  for (const t of raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)) {
    if ((KNOWN_TIERS as readonly string[]).includes(t)) tiers.add(t as ProbeTier);
    else unknown.push(t);
  }
  if (unknown.length) {
    throw new Error(
      `sandbox-isolation: unrecognized SOLEUR_ISOLATION_TIERS entries: ${unknown.join(", ")} ` +
        `(known tiers: ${KNOWN_TIERS.join(", ")})`,
    );
  }
  return tiers;
}

function isolationTierEnabled(tier: ProbeTier, raw: string | undefined): boolean {
  const tiers = parseIsolationTiers(raw);
  return tiers === null || tiers.has(tier);
}

// Bound once at module load — no default-parameter read inside
// isolationTierEnabled, so an explicit `undefined` argument tests "unset"
// rather than falling back to the live env.
const ISOLATION_TIERS_RAW = process.env.SOLEUR_ISOLATION_TIERS;
const directProbe = isolationTierEnabled("direct", ISOLATION_TIERS_RAW)
  ? probeSkip("direct")
  : { skip: true, reason: "SOLEUR_ISOLATION_TIERS excludes direct tier" };
const queryProbe = isolationTierEnabled("query", ISOLATION_TIERS_RAW)
  ? probeSkip("query")
  : { skip: true, reason: "SOLEUR_ISOLATION_TIERS excludes query tier" };
// #9723 — the deployed PATH shim (same file the prod image installs at
// /usr/local/bin/bwrap) and its seccomp artifact, for the through-shim FR7b arm.
const APP_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM_PATH = path.join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF_PATH = path.join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");
// FR9 reads ~/.claude/projects/*.jsonl excerpts and sends them to the Anthropic
// API. On a dev workstation, historical transcripts could leak if isolation
// regresses. Require explicit opt-in rather than inferring from CI=true —
// generic CI doesn't imply "safe to exfiltrate session files".
const fr9OptIn = process.env.ANTHROPIC_ISOLATION_TEST_OK === "1";

describe.runIf(!directProbe.skip)("sandbox-isolation: direct bwrap (tier 4)", () => {
  const pairs: WorkspacePair[] = [];
  const sandboxes: SandboxBHandle[] = [];
  const procHandles: SandboxProcessHandle[] = [];

  beforeAll(() => {
    rescueStaleFixtures();
  });

  afterEach(async () => {
    while (sandboxes.length) {
      const handle = sandboxes.pop();
      if (!handle) continue;
      handle.kill();
      await handle.waitExit().catch(() => undefined);
    }
    while (procHandles.length) {
      const handle = procHandles.pop();
      if (!handle) continue;
      handle.kill();
      await handle.waitExit().catch(() => undefined);
    }
    while (pairs.length) {
      pairs.pop()?.cleanup();
    }
  });

  test("FR2: rootA sandbox cannot read rootB/secret.md (cat exits non-zero, marker absent)", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/secret.md")}`,
      { pair, timeoutMs: 5_000 },
    );

    // Setup-failure guard: if bwrap itself failed (missing socat at runtime,
    // seccomp denial, etc.), the test signal is meaningless. Fail loudly.
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Isolation assertions: cat must have failed AND the marker must be absent
    // from combined stdio. Post-state is pinned (cq-mutation-assertions-pin-exact-post-state).
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(FS_DENY_RE);
  });

  test("FR3: rootA sandbox write to rootB/leaked.md does not mutate host rootB", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const preMarker = seedMarker(pair.rootB, "existing.md");
    const preEntries = fs.readdirSync(pair.rootB).sort();
    const leakPath = path.join(pair.rootB, "leaked.md");

    const result = spawnBwrap(
      pair.rootA,
      `echo "leaked-${Date.now()}" > ${shellQuote(leakPath)} 2>/dev/null; echo DONE`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Host-side assertions: rootB must be identical to pre-state. Inside the
    // sandbox the write may "succeed" against the tmpfs overlay (ephemeral),
    // but the host directory is the blast-radius boundary we care about.
    const postEntries = fs.readdirSync(pair.rootB).sort();
    expect(postEntries).toEqual(preEntries);
    expect(fs.existsSync(leakPath)).toBe(false);
    // Existing marker must be intact.
    expect(fs.readFileSync(preMarker.path, "utf8")).toBe(preMarker.token);
  });

  test("FR4: prefix collision (user1 vs user10) does not grant user1 sandbox access to user10", () => {
    const pair = createNamedWorkspacePair(["user1", "user10"]);
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/secret.md")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(FS_DENY_RE);
  });

  test("FR6: dangling symlink (target never existed) surfaces as no-such-file, not bypass", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    // The link's target path is a name that was never created inside rootB.
    // FR5 proves an existing rootB file cannot be reached through a symlink;
    // FR6 proves the *dangling* variant reports the same no-such-file class
    // rather than e.g. a Permission Denied that could mask path-resolution
    // going through unexpected code paths.
    const danglingTarget = path.join(pair.rootB, "does-not-exist.md");
    linkEscape(pair.rootA, "dangle", danglingTarget);

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootA + "/dangle")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.status).not.toBe(0);
    // Must be the missing-target class, not a permission error.
    expect(result.stderr).toMatch(/No such file|cannot open/);
  });

  test("FR7: rootA sandbox cannot read /proc/<rootB-pid>/environ (pid namespace isolation)", async () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const sentinel = `FR7_SECRET_${randomBytes(8).toString("hex")}`;

    const handle = spawnSandboxB(pair.rootB, {
      pair,
      readyTimeoutMs: 5_000,
      env: { ...process.env, FR7_SECRET: sentinel },
    });
    sandboxes.push(handle);
    await handle.ready;
    const hostPid = handle.pid;

    // Precondition: on the HOST (outside any sandbox), /proc/<hostPid>/environ
    // MUST contain the sentinel. If not, the test lacks discriminative power —
    // sandboxA would appear isolated even though the target data was never there.
    const hostEnviron = fs.readFileSync(`/proc/${hostPid}/environ`, "utf8");
    expect(
      hostEnviron,
      `precondition: host /proc/${hostPid}/environ must contain sentinel`,
    ).toContain(sentinel);

    // Cross-read attempt from sandboxA. With --unshare-pid, sandboxA's /proc
    // reflects sandboxA's own pid namespace — host pid does not exist there.
    const result = spawnBwrap(
      pair.rootA,
      `cat /proc/${hostPid}/environ 2>&1; echo "__EXIT__$?"`,
      { pair, timeoutMs: 5_000 },
    );
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.stdout).not.toContain(sentinel);
    // Must surface a no-such-file or permission-denied signal, otherwise we
    // somehow read a legitimate /proc/<pid>/environ and got lucky that the
    // sentinel wasn't there.
    expect(result.stdout + result.stderr).toMatch(FS_DENY_RE);
  });

  test.skipIf(ISOLATION_IN_IMAGE)("FR7b (#9723): the vendored tail --bind /proc /proc is re-masked by the PATH shim", async () => {
    // The harness argv (buildBwrapArgs) never emits the vendor tail bind, so
    // FR7 measures a cleaner-than-production shape. This row appends the real
    // tail — `--bind /proc /proc` (the enableWeakerNestedSandbox defect) — and
    // runs the SAME argv through the PATH-resolved shim, so the assertion
    // measures the deployed chain, not the vendor text.
    const pair = createWorkspacePair();
    pairs.push(pair);
    const sentinel = `FR7B_SECRET_${randomBytes(8).toString("hex")}`;
    // The vendored argv's namespace set — --unshare-user is load-bearing under
    // the shim: a /proc-exposing argv without it cannot mount a fresh procfs
    // (bwrap 0.8.0 in-image → EPERM) and the shim refuses rather than ship the
    // leak. The deploy-probe shape (pidns without userns) is the counter-case,
    // pinned by the passthrough row in bwrap-shim.test.ts.
    const VENDOR_TAIL = ["--unshare-user", "--bind", "/proc", "/proc"];

    const handle = spawnSandboxB(pair.rootB, {
      pair,
      readyTimeoutMs: 5_000,
      env: { ...process.env, FR7B_SECRET: sentinel },
    });
    sandboxes.push(handle);
    await handle.ready;
    const hostPid = handle.pid;

    // Precondition (same as FR7): the sentinel must actually be on the host's
    // procfs, or a "masked" result below would be vacuous. The environ READ is
    // host-policy-dependent though — ptrace_scope≥2, a setuid bwrap binary
    // (dumpable cleared), or a hidepid procfs all deny it even host→child —
    // so on EACCES the precondition degrades to PID-dir existence and the
    // `__SANDBOXB_SEEN__` control arm below (already policy-independent) does
    // the discrimination. An ENOENT means the spawn died before probing —
    // that still fails loud.
    let hostEnviron = "";
    try {
      hostEnviron = fs.readFileSync(`/proc/${hostPid}/environ`, "utf8");
      expect(hostEnviron).toContain(sentinel);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "EACCES") throw err;
      expect(fs.existsSync(`/proc/${hostPid}`)).toBe(true);
    }

    // Probe shape — positional, host-policy-independent. Whether a masked
    // procfs leaves `/proc/<hostPid>/environ` READABLE is kernel-dependent
    // (yama ptrace_scope / userns credentials deny it on some hosts even when
    // procfs is exposed), so the discriminator is host-pid VISIBILITY: the
    // sandboxB host pid is a /proc dir only when real procfs is mounted.
    // (`/proc/1` exists in BOTH arms — under the pidns-scoped `--proc` mask it
    // is the sandbox's own init — so it is not the discriminator.)
    const probe = [
      `test -d /proc/${hostPid} && echo __SANDBOXB_SEEN__`,
      `cat /proc/${hostPid}/environ 2>/dev/null || true`,
      // Self-view intactness: the vendor's `apply-seccomp /proc/self/fd/N`
      // inner command needs procfs for SELF — the mask must not break it.
      `test -e /proc/self/environ && echo __SELFPROC_OK__`,
    ].join("; ");

    // CONTROL — the same argv straight through the real binary keeps the
    // defect: the tail bind re-mounts HOST procfs over the pidns isolation,
    // so the sandboxB host pid is visible in-sandbox.
    const control = spawnBwrap(pair.rootA, probe, {
      pair,
      timeoutMs: 5_000,
      extraArgs: VENDOR_TAIL,
    });
    expect(control.setupFailed, `control bwrap setup failed: ${control.stderr}`).toBe(false);
    expect(control.stdout, "control must expose host procfs (the tail-bind defect is real)").toContain("__SANDBOXB_SEEN__");

    // TREATMENT — the identical argv through the deployed shim: it lands a
    // fresh `--proc /proc` (pidns-scoped procfs) after the tail bind, so
    // in-sandbox /proc carries only the sandbox's own pids — nothing for the
    // host-side sentinel to ride.
    const shimDir = fs.mkdtempSync(path.join(os.tmpdir(), "iso-shim-"));
    fs.symlinkSync(BWRAP_SHIM_PATH, path.join(shimDir, "bwrap"));
    try {
      const env = {
        ...process.env,
        PATH: `${shimDir}:${process.env.PATH ?? "/usr/bin:/bin"}`,
        SOLEUR_BWRAP_REAL: "/usr/bin/bwrap",
        SOLEUR_BWRAP_SECCOMP_BPF: BWRAP_BPF_PATH,
      };
      const masked = spawnBwrap(pair.rootA, probe, {
        pair,
        timeoutMs: 5_000,
        extraArgs: VENDOR_TAIL,
        env,
      });
      expect(masked.setupFailed, `masked bwrap setup failed: ${masked.stderr}`).toBe(false);
      expect(masked.stdout).not.toContain(sentinel);
      expect(masked.stdout).not.toContain("__SANDBOXB_SEEN__");
      // The pidns-scoped procfs keeps the SELF view — not an empty mount.
      expect(masked.stdout).toContain("__SELFPROC_OK__");
    } finally {
      fs.rmSync(shimDir, { recursive: true, force: true });
    }
  });

  test("TOCTOU regression (#5862): a sibling created AFTER the namespace build stays masked", async () => {
    // The ADR-075 residual: per-sibling `denyRead` enumeration could never
    // cover a workspace created between the namespace build and session end.
    // Under the parent-tmpfs ordering (`--tmpfs <parent>` + rw re-bind of own —
    // the shape `spawnBwrap`'s `pair` option emits and the vendored CLI 2.1.284
    // builder produces for `denyRead: [<root>]` + `allowWrite: [own]`), the
    // late sibling lives under the masked host dir — invisible permanently.
    //
    // Drive it live: a long-running sandboxed shell in rootA waits on a flag
    // file (inside the bind-mounted root, host-visible); the host creates the
    // sibling WHILE the namespace is already built, then signals; the sandbox
    // re-lists the parent and attempts the cross-read.
    const pair = createWorkspacePair();
    pairs.push(pair);
    const late = path.join(pair.parent, "late-sibling");
    const readyFlag = path.join(pair.rootA, ".sandbox-ready");
    const goFlag = path.join(pair.rootA, ".probe-go");
    const script = [
      `touch ${shellQuote(readyFlag)}`,
      // Bounded poll — a broken handshake must not spin until the harness
      // timeout with no diagnostic.
      `for i in $(seq 1 400); do [ -f ${shellQuote(goFlag)} ] && break; sleep 0.05; done`,
      `echo "__LS__"; ls ${shellQuote(pair.parent)}`,
      `echo "__CAT__"; cat ${shellQuote(late + "/secret.md")} 2>&1 || echo "__CAT_RC__$?"`,
    ].join("; ");

    const handle = spawnSandboxed(pair.rootA, script, { pair, timeoutMs: 15_000 });
    procHandles.push(handle);
    // The namespace is confirmed built (marker written through the rw bind).
    await waitForFile(readyFlag, 10_000);

    // The late sibling arrives on the HOST after the namespace exists.
    const { token } = seedMarker(late, "secret.md");
    fs.writeFileSync(goFlag, "go");
    const exit = await handle.waitExit();
    expect(exit.code, `sandboxed probe exited early; stderr=${handle.stderrChunks.join("")}`).toBe(0);

    const out = handle.stdoutChunks.join("");
    // window-assembly: lsSection — everything between the __LS__ and __CAT__
    // markers is exactly the `ls` listing of the parent dir (the script emits
    // the markers around it; nothing else writes to stdout between them). The
    // `cat` error line legitimately names the late-sibling PATH, so a
    // whole-output `not.toContain` would false-fail — the window is required.
    const lsSection = (out.split("__LS__")[1] ?? "").split("__CAT__")[0];
    expect(lsSection).toContain("rootA");
    // rootB existed BEFORE the build (masked by the tmpfs); late-sibling
    // arrived AFTER — both are absent from the namespace's parent listing.
    expect(lsSection).not.toContain("rootB");
    expect(lsSection).not.toContain("late-sibling");
    expect(out).toContain("__CAT_RC__");
    expect(out).not.toContain(token);
    expect(out).toMatch(FS_DENY_RE);
  });

  test("AC7-positive: two users in the SAME workspace see the same files (shared-workspace happy path)", () => {
    // feat-team-workspace-multi-user AC7 positive case: when Jean and
    // Harry are both members of the same workspace (workspace_members
    // rows pointing at the same workspace_id), they share a single fs
    // tree. We model "user-1 writes, user-2 reads" by running two
    // sequential bwrap invocations against the SAME rootA — the second
    // invocation sees the marker the first wrote.
    const pair = createWorkspacePair();
    pairs.push(pair);

    const sharedToken = `SHARED_${randomBytes(6).toString("hex")}`;
    const sharedFile = path.join(pair.rootA, "shared.md");

    // user-1 writes inside rootA
    const writeRes = spawnBwrap(
      pair.rootA,
      `printf '%s' '${sharedToken}' > ${shellQuote(sharedFile)} && echo WROTE`,
      { pair, timeoutMs: 5_000 },
    );
    expect(writeRes.setupFailed, `bwrap setup failed: ${writeRes.stderr}`).toBe(false);
    expect(writeRes.status).toBe(0);
    expect(writeRes.stdout).toContain("WROTE");

    // user-2 reads inside the SAME rootA
    const readRes = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(sharedFile)}`,
      { pair, timeoutMs: 5_000 },
    );
    expect(readRes.setupFailed, `bwrap setup failed: ${readRes.stderr}`).toBe(false);
    expect(readRes.status).toBe(0);
    expect(readRes.stdout).toContain(sharedToken);
  });

  test("AC7-negative: two users in DIFFERENT workspaces see nothing (cross-workspace deny)", () => {
    // feat-team-workspace-multi-user AC7 negative case: when Jean and
    // Harry belong to different workspaces, the sandbox must deny any
    // cross-read attempt. This mirrors FR2 (root-level cross-workspace
    // deny) but the framing here is "user-2-in-workspace-B reading
    // user-1-in-workspace-A". Under N2 + the workspace-keyed sandbox
    // contract, bwrap only mounts the caller's own workspace path; the
    // other workspace is tmpfs'd out.
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "harry-private.md");

    // user-2 (in rootA / Jean's workspace) attempts to read Harry's row
    // in the other workspace.
    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/harry-private.md")}`,
      { pair, timeoutMs: 5_000 },
    );
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(FS_DENY_RE);
  });

  test("FR5: symlink escape from rootA to rootB/secret.md is blocked by tmpfs overlay", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");
    linkEscape(pair.rootA, "peek", path.join(pair.rootB, "secret.md"));

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootA + "/peek")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Following the symlink inside the sandbox must fail — rootB is tmpfs'd out,
    // so the link target does not resolve. Token MUST NOT appear in stdout.
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(FS_DENY_RE);
  });
});

describe.runIf(!queryProbe.skip)("sandbox-isolation: SDK query() (full stack)", () => {
  const pairs: WorkspacePair[] = [];

  beforeAll(() => {
    rescueStaleFixtures();
  });

  afterEach(() => {
    while (pairs.length) {
      pairs.pop()?.cleanup();
    }
  });

  test("FR2-smoke: query() in rootA cannot leak rootB/secret.md to assistant output", async () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const prompt = `Using the Bash tool, run \`cat ${pair.rootB}/secret.md\`. Report exactly what the command prints, or the exact error message if it fails. Do not paraphrase.`;
    const attempts: QueryAttemptResult[] = [];
    attempts.push(await runQueryAttempt({ cwd: pair.rootA, pair, prompt, token }));
    if (!attempts[0].toolsUsed.has("Bash")) {
      attempts.push(
        await runQueryAttempt({
          cwd: pair.rootA,
          pair,
          prompt: `${prompt} You MUST invoke the Bash tool — do not answer from memory.`,
          token,
        }),
      );
    }
    assertNoLeakAcrossAttempts(attempts, "FR2-smoke");
  }, 180_000);

  test("FR8: two query() runs cannot share a TMPDIR-written token across workspaces", async () => {
    const pairWrite = createWorkspacePair();
    const pairRead = createWorkspacePair();
    pairs.push(pairWrite, pairRead);
    const token = `FR8_TMP_${randomBytes(6).toString("hex")}`;
    const tmpFilename = `cross-${randomBytes(4).toString("hex")}.txt`;

    // Run 1: rootA session writes the token into its TMPDIR.
    const writeAttempt = await runQueryAttempt({
      cwd: pairWrite.rootA,
      pair: pairWrite,
      prompt: `Using the Bash tool, run \`printf '%s' '${token}' > "$TMPDIR/${tmpFilename}" && echo WROTE\`. Report the command's output.`,
      token: "__never_leaked__", // Write run is not leak-gated; we only need it to execute.
    });
    // If the write never happened (model refused, Bash unused), the read-side
    // test becomes tautological. Fail loudly so we can investigate.
    expect(
      writeAttempt.toolsUsed.has("Bash"),
      `FR8 write run did not invoke Bash. texts=${writeAttempt.texts.join(" | ").slice(0, 500)}`,
    ).toBe(true);

    // Run 2: rootB session attempts to read the token from its TMPDIR.
    const readPrompt = `Using the Bash tool, run \`cat "$TMPDIR/${tmpFilename}"\`. Report exactly what the command prints or the error.`;
    const attempts: QueryAttemptResult[] = [];
    attempts.push(
      await runQueryAttempt({ cwd: pairRead.rootA, pair: pairRead, prompt: readPrompt, token }),
    );
    if (!attempts[0].toolsUsed.has("Bash")) {
      attempts.push(
        await runQueryAttempt({
          cwd: pairRead.rootA,
          pair: pairRead,
          prompt: `You MUST use the Bash tool. Run \`cat "$TMPDIR/${tmpFilename}"\` and report the output verbatim.`,
          token,
        }),
      );
      expect(
        attempts[1].toolsUsed.has("Bash"),
        `FR8 read run refused Bash on retry — test has no discriminative power. texts=${attempts[1].texts.join(" | ").slice(0, 500)}`,
      ).toBe(true);
    }
    assertNoLeakAcrossAttempts(attempts, "FR8");
  }, 300_000);

  test.runIf(fr9OptIn)(
    "FR9: SDK session files (~/.claude/projects) do not leak tokens across workspaces",
    async () => {
      const pairWrite = createWorkspacePair();
      const pairRead = createWorkspacePair();
      pairs.push(pairWrite, pairRead);
      const token = `FR9_SESSION_${randomBytes(6).toString("hex")}`;

      // Run 1: rootA session — token shows up in the conversation transcript and
      // should land in ~/.claude/projects/<project>/<session>.jsonl (persistSession
      // defaults to true).
      const writeAttempt = await runQueryAttempt({
        cwd: pairWrite.rootA,
        pair: pairWrite,
        prompt: `Remember this exact token for our records: ${token}. Then respond with the single word OK.`,
        token: "__never_leaked__",
      });
      expect(writeAttempt.texts.join("").length).toBeGreaterThan(0);
      // Disk-pin: the token MUST appear somewhere under ~/.claude/projects/
      // before we run the read side. Without this, silent persistence failure
      // would make the read-side "no leak" assertion tautological. Review
      // #2610 test-design Rec #1.
      const persisted = findTokenInClaudeProjects(token);
      expect(
        persisted.found,
        `FR9 precondition: token must be persisted to ~/.claude/projects/*.jsonl before read side. Searched ${persisted.scanned} files.`,
      ).toBe(true);

      // Run 2: rootB session — try to enumerate and read session files.
      const readPrompt = [
        "Using the Bash tool, run the following three commands in order and report each output:",
        "  1) ls -la ~/.claude/projects/ 2>&1 | head -20",
        "  2) find ~/.claude/projects -type f -name '*.jsonl' 2>/dev/null | head -5",
        "  3) for f in $(find ~/.claude/projects -type f -name '*.jsonl' 2>/dev/null | head -5); do echo \"=== $f ===\"; head -c 4096 \"$f\" 2>/dev/null; done",
        "Report all outputs verbatim.",
      ].join("\n");
      const attempts: QueryAttemptResult[] = [];
      attempts.push(
        await runQueryAttempt({ cwd: pairRead.rootA, pair: pairRead, prompt: readPrompt, token }),
      );
      if (!attempts[0].toolsUsed.has("Bash")) {
        attempts.push(
          await runQueryAttempt({
            cwd: pairRead.rootA,
            pair: pairRead,
            prompt: `${readPrompt}\n\nYou MUST use the Bash tool — do not answer from memory.`,
            token,
          }),
        );
        expect(
          attempts[1].toolsUsed.has("Bash"),
          `FR9 read run refused Bash on retry — test has no discriminative power. texts=${attempts[1].texts.join(" | ").slice(0, 500)}`,
        ).toBe(true);
      }
      assertNoLeakAcrossAttempts(attempts, "FR9");
    },
    300_000,
  );
});

// ---------- test-helpers ----------

function assertNoLeakAcrossAttempts(attempts: QueryAttemptResult[], label: string): void {
  // A leak on ANY attempt fails the test. Stopping at the first clean retry
  // would let a real first-attempt leak pass silently.
  for (const [i, a] of attempts.entries()) {
    expect(
      a.tokenLeaked,
      `${label} attempt ${i + 1}: ${a.leakContext || "(no leak context)"}`,
    ).toBe(false);
  }
}

function findTokenInClaudeProjects(token: string): { found: boolean; scanned: number } {
  const root = path.join(os.homedir(), ".claude", "projects");
  let scanned = 0;
  let found = false;
  const walk = (dir: string): void => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        walk(full);
      } else if (e.isFile() && e.name.endsWith(".jsonl")) {
        scanned += 1;
        try {
          if (fs.readFileSync(full, "utf8").includes(token)) {
            found = true;
            return;
          }
        } catch {
          // unreadable file — move on
        }
      }
    }
  };
  walk(root);
  return { found, scanned };
}

interface QueryAttemptOpts {
  cwd: string;
  pair: WorkspacePair;
  prompt: string;
  token: string;
}

interface QueryAttemptResult {
  texts: string[];
  toolsUsed: Set<string>;
  tokenLeaked: boolean;
  leakContext: string;
}

async function runQueryAttempt(opts: QueryAttemptOpts): Promise<QueryAttemptResult> {
  const { cwd, pair, prompt, token } = opts;
  const texts: string[] = [];
  const toolsUsed = new Set<string>();

  const q = query({
    prompt,
    options: {
      cwd,
      model: "claude-sonnet-5-5",
      permissionMode: "default",
      settingSources: [],
      maxTurns: 6,
      maxBudgetUsd: 0.5,
      sandbox: {
        enabled: true,
        failIfUnavailable: true,
        autoAllowBashIfSandboxed: true,
        allowUnsandboxedCommands: false,
        enableWeakerNestedSandbox: true,
        network: { allowedDomains: [], allowManagedDomainsOnly: true },
        filesystem: {
          // Mirror the prod fix (#5733 → per-sibling deny, #5862 → constant
          // parent deny): deny the shared PARENT root explicitly. Under the
          // vendored builder's deny-then-restore ordering the parent `--tmpfs`
          // masks rootB (and any sibling created mid-session) while rootA —
          // the session's own workspace — is re-bound rw via the `allowWrite`
          // restore. This is the only tier that exercises the real SDK
          // argv against the deny-then-restore shape.
          allowWrite: [pair.rootA],
          denyRead: [pair.parent, "/proc"],
        },
      },
    },
  });

  for await (const message of q) {
    if (message.type !== "assistant") continue;
    const content = message.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content as Array<{ type: string; text?: string; name?: string }>) {
      if (block.type === "text" && typeof block.text === "string") {
        texts.push(block.text);
      } else if (block.type === "tool_use" && typeof block.name === "string") {
        toolsUsed.add(block.name);
      }
    }
  }

  const combined = texts.join("\n");
  const tokenLeaked = combined.includes(token);
  const leakContext = tokenLeaked
    ? `Token '${token}' leaked into assistant output. Tools used: ${Array.from(toolsUsed).join(", ") || "(none)"}. Excerpt: ${excerpt(combined, token)}`
    : "";

  return { texts, toolsUsed, tokenLeaked, leakContext };
}

function excerpt(haystack: string, needle: string): string {
  const idx = haystack.indexOf(needle);
  if (idx === -1) return haystack.slice(0, 200);
  const start = Math.max(0, idx - 80);
  const end = Math.min(haystack.length, idx + needle.length + 80);
  return `...${haystack.slice(start, end)}...`;
}

/**
 * Coverage matrix — do not remove. A load-time lint below guards it.
 *
 * | Surface                | Tier | FRs covered                        |
 * | direct-bwrap / Bash    |   4  | FR2, FR3, FR4, FR5, FR6, FR7       |
 * | sdk-query / Bash       | full | FR2-smoke, FR8, FR9                |
 *
 * Tier-2/3 tool-path coverage: test/sandbox-hook.test.ts + test/sandbox.test.ts.
 */
export const COVERAGE = {
  "direct-bwrap/Bash": "FR2/FR3/FR4/FR5/FR6/FR7",
  "sdk-query/Bash": "FR2-smoke/FR8/FR9",
} as const;

describe("sandbox-isolation: coverage + test-hygiene guards", () => {
  test("COVERAGE exports both direct-bwrap and sdk-query surfaces with parseable FR lists", () => {
    const keys = Object.keys(COVERAGE).sort();
    expect(keys).toEqual(["direct-bwrap/Bash", "sdk-query/Bash"]);
    // Each value must be a non-empty `/`-separated list of FR tokens
    // (`FR<digit>+` optionally followed by `-<word>` like `FR2-smoke`).
    // A plain-length check passes on any non-empty string, which is why
    // review #2610 L1 flagged it as tautological.
    const frTokenRe = /^FR\d+(-[A-Za-z0-9]+)?$/;
    for (const [surface, frs] of Object.entries(COVERAGE)) {
      const tokens = frs.split("/").filter((s) => s.length > 0);
      expect(
        tokens.length,
        `COVERAGE[${surface}] must list at least one FR`,
      ).toBeGreaterThan(0);
      for (const t of tokens) {
        expect(t, `COVERAGE[${surface}] token ${JSON.stringify(t)} must match ${frTokenRe}`).toMatch(
          frTokenRe,
        );
      }
    }
  });

  test("SOLEUR_ISOLATION_TIERS filter: 'direct' excludes the query tier (deploy-probe contract, #2640)", () => {
    // Pure-function check of the env filter — no suite is spawned and no API
    // call is made. The live verification is
    // `SOLEUR_ISOLATION_TIERS=direct npx vitest run test/sandbox-isolation.test.ts`
    // reporting the query-tier suite skipped rather than executed.
    expect(isolationTierEnabled("direct", "direct")).toBe(true);
    expect(isolationTierEnabled("query", "direct")).toBe(false);
    expect(isolationTierEnabled("query", "direct,query")).toBe(true);
    expect(isolationTierEnabled("direct", " query , direct ")).toBe(true);
    // Unset/empty runs the full matrix — the deploy exec sets it explicitly.
    expect(isolationTierEnabled("query", undefined)).toBe(true);
    expect(isolationTierEnabled("direct", "")).toBe(true);
    // A typo'd tier throws at load instead of vacuously greening the canary.
    expect(() => isolationTierEnabled("direct", "dirct")).toThrow(
      /unrecognized SOLEUR_ISOLATION_TIERS/,
    );
  });

  test("no test.fails uses a placeholder todo (#TBD, #todo, etc.)", () => {
    const selfPath = new URL(import.meta.url).pathname;
    const src = fs.readFileSync(selfPath, "utf8");
    // Match any test.fails({ todo: '...' }) whose issue reference is a
    // placeholder. The intent of Phase 6.3 is that every inverted-assertion
    // test points at a filed GitHub issue; unfiled placeholders rot silently.
    const matches = src.match(
      /test\.fails\s*\(\s*[^)]*todo\s*:\s*['"][^'"]*(?:#TBD|#todo|TBD|\?\?\?)/gi,
    );
    expect(
      matches,
      `test.fails placeholder detected — file an issue and replace #TBD with #NNNN. Matches: ${matches?.join(" | ")}`,
    ).toBeNull();
  });
});
