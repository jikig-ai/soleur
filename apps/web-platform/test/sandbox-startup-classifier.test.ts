// feat-harden-agent-sandbox #5875 PR1 (ADR-079) — deterministic classifier
// tests. The 2026-07-01 P0 (#5873) was a seccomp EPERM on the SDK's split
// unshare() introduced by bump #5849; the catch sites only tagged the SDK's
// missing-binary preflight substring, so the EPERM fell through untagged.
//
// Phase-0 spike (recorded in #5875): the bwrap/seccomp stderr — including
// "Operation not permitted" — is merged into the thrown Error's `.message`
// (plain Error, no `.stderr`/`.cause`). These tests use a SYNTHESIZED signal
// in that exact shape (cq-test-fixtures-synthesized-only) — no LLM in the
// assertion path.
import { describe, it, expect } from "vitest";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll } from "vitest";
import {
  classifySandboxStartupError,
  classifyBashSandboxFailure,
  isPreExecSandboxDenialOutput,
  BASH_UNAVAILABLE_NOTICE,
  HELPER_STEPS,
  HELPER_STEPS_PRE_WORKER_FORK,
  HELPER_NON_STEP_LINES,
} from "@/server/sandbox-startup-classifier";
import {
  assertHelperStepCensus,
  bufferSource,
  fileSource,
  resolveVendoredBinary,
  scanHelperStepStrings,
  shouldSkipRealBinaryRows,
} from "./helpers/vendored-bwrap-tail";

// The #5873 shape: bwrap fails to set up the userns after the split unshare()
// because the container seccomp profile denied the second unshare() call.
const SECCOMP_EPERM_STDERR =
  "Command failed with exit code 1: bwrap --unshare-user --unshare-pid --unshare-ns ...\n" +
  "bwrap: Creating new namespace failed: Operation not permitted";

// The SDK's own missing-binary preflight (the ONLY signature the pre-PR1 catch
// sites recognized).
const MISSING_BINARY_STDERR = "sandbox required but unavailable";

describe("classifySandboxStartupError — sandboxKind (Phase-0 shape, #5875)", () => {
  it("tags the #5873 seccomp/userns EPERM as seccomp_or_userns_denial", () => {
    const c = classifySandboxStartupError(
      new Error(SECCOMP_EPERM_STDERR),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.errorCode).toBe("bwrap_eperm");
    expect(c.sdkVersion).toBe("0.3.197");
    // Raw stderr is preserved verbatim for the human reading Sentry.
    expect(c.stderr).toBe(SECCOMP_EPERM_STDERR);
  });

  it("tags the SDK missing-binary preflight as missing_binary", () => {
    const c = classifySandboxStartupError(
      new Error(MISSING_BINARY_STDERR),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("missing_binary");
    expect(c.errorCode).toBe("sandbox_unavailable");
  });

  it("recognizes a bwrap/unshare token even without an explicit EPERM", () => {
    const c = classifySandboxStartupError(
      new Error("bwrap: setting up uid map failed"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.errorCode).toBe("bwrap_error");
  });

  it("tags the #8752 PATH-shim refusal marker as a sandbox-namespace denial", () => {
    // The shim fails closed with `bwrap-shim: <cause>` + exit 65 — the
    // `bwrap` token inside the marker routes it to seccomp_or_userns_denial,
    // not a generic environment error.
    const c = classifySandboxStartupError(
      new Error("Command failed with exit code 65: bwrap-shim: seccomp artifact not readable: /app/infra/bwrap-userns-clone3-deny.bpf"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
  });

  it("does NOT mis-tag a generic model/API error (no sandbox token)", () => {
    const c = classifySandboxStartupError(
      new Error("Anthropic API 529 overloaded_error"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("other");
    expect(c.errorCode).toBe("unclassified");
  });

  it("does NOT mis-tag a bare EPERM with no bubblewrap/namespace token", () => {
    // A mid-conversation file-permission EPERM must not read as a sandbox
    // startup failure — the whole point of the incident-class narrowing.
    const c = classifySandboxStartupError(
      new Error("EACCES: permission denied, open '/etc/shadow' — Operation not permitted"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("other");
  });

  it("also scans err.cause when the sandbox text is not on .message", () => {
    // Future-proofing: an SDK that moves bwrap/seccomp stderr onto `.cause`
    // must not degrade to "other" (silent #5873 recurrence).
    const err = new Error("Command failed with exit code 1", {
      cause: new Error("bwrap: Operation not permitted"),
    });
    const c = classifySandboxStartupError(err, "0.3.197");
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.errorCode).toBe("bwrap_eperm");
    expect(c.stderr).toContain("bwrap: Operation not permitted");
  });

  it("also scans a string .stderr property", () => {
    const err = Object.assign(new Error("Command failed"), {
      stderr: "bwrap: setting up uid map: Operation not permitted",
    });
    const c = classifySandboxStartupError(err, "0.3.197");
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
  });

  it("tolerates a non-Error thrown value (stringifies into stderr)", () => {
    const c = classifySandboxStartupError("bwrap: Operation not permitted", null);
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.stderr).toBe("bwrap: Operation not permitted");
    expect(c.sdkVersion).toBeNull();
  });

  it("resolves the installed SDK version by default (best-effort: string|null)", () => {
    const c = classifySandboxStartupError(new Error(SECCOMP_EPERM_STDERR));
    expect(c.sdkVersion === null || typeof c.sdkVersion === "string").toBe(true);
  });
});

// Tagging-decision contract (CTO ruling, ADR-079): both catch sites tag
// `feature:"agent-sandbox"` IFF `sandboxKind !== "other"` — the SIGNATURE, not a
// stream-phase gate. `streamStartSent` is always true at the catch (set before
// the iterator loop) and the seccomp denial surfaces mid-stream, so a phase gate
// would silently suppress the real signal. The signature axis is exercised by
// the `sandboxKind` cases above; the emit wiring (per-user, tag/extra shape) is
// covered end-to-end by test/agent-runner-sandbox-config.test.ts (positive:
// iterator-throw still tags with streamStartSent===true) and
// test/cc-dispatcher-real-factory.test.ts (T16).

// #10032 (ADR-075 addendum 2026-10-11) — a Bash tool_result whose output carries a bwrap denial. The session-start
// classifier above only sees errors THROWN out of the SDK iterator; a failed sandbox spawn that the SDK returns to
// the model as a tool_result (the shape the shim's fresh `--proc /proc` refusal takes under docker's masked /proc)
// reached Sentry as nothing. Fixtures use bwrap's REAL stderr text, never a paraphrase.
describe("classifyBashSandboxFailure — Bash tool_result sandbox denial (#10032)", () => {
  const PROC_MOUNT_EPERM = "bwrap: Can't mount proc on /newroot/proc: Operation not permitted";

  it("classifies the shim's fresh-procfs refusal as proc_mount_eperm and returns ONLY the matched line", () => {
    const f = classifyBashSandboxFailure(PROC_MOUNT_EPERM, "0.3.284");
    expect(f).not.toBeNull();
    expect(f?.errorCode).toBe("proc_mount_eperm");
    expect(f?.sdkVersion).toBe("0.3.284");
    expect(f?.matchedLine).toBe(PROC_MOUNT_EPERM);
  });

  it("data minimisation: a secret-looking neighbour line never reaches the result (Art. 5(1)(c))", () => {
    const secretLine = "DATABASE_URL=postgres://user:hunter2@db.internal/prod";
    const out = `${secretLine}\n${PROC_MOUNT_EPERM}\nsk-ant-api03-notarealkeynotarealkeynotarealkey\n`;
    const f = classifyBashSandboxFailure(out, "0.3.284");
    expect(f?.matchedLine).toBe(PROC_MOUNT_EPERM);
    expect(JSON.stringify(f)).not.toContain("hunter2");
    expect(JSON.stringify(f)).not.toContain("sk-ant-api03");
  });

  it("scrubs every absolute path root, opaque tokens and control characters, keeping bwrap's /newroot targets", () => {
    const line = "bwrap: \u0007Can't mount proc on /newroot/proc: Operation not permitted /home/soleur/.ssh/id_rsa /var/lib/soleur/x " +
      "sk-ant-api03-notarealkeynotarealkeynotarealkey";
    const f = classifyBashSandboxFailure(line, null);
    expect(f?.matchedLine).toContain("/newroot/proc");
    for (const leaked of ["/home/", "/var/lib/", "sk-ant-api03", "id_rsa", "\u0007"]) {
      expect(f?.matchedLine).not.toContain(leaked);
    }
  });

  it("is linear on a hostile 100k-char slash-heavy line (shared event loop; measured 17s on a quadratic scrub)", () => {
    for (const hostile of ["/a".repeat(50_000), "/".repeat(100_000), "/a/a/a/a/".repeat(12_000)]) {
      const t0 = performance.now();
      const f = classifyBashSandboxFailure(`bwrap EPERM ${hostile}`, null);
      expect(performance.now() - t0).toBeLessThan(250);
      expect(f?.matchedLine.length).toBeLessThanOrEqual(300);
    }
  });

  it("scrubs workspace paths and uuids out of the matched line", () => {
    const uuid = "754ee124-706a-4f21-a4f4-e828257b0380";
    const line = `bwrap: Can't bind mount /workspaces/${uuid}/repo on /newroot/workspaces/${uuid}/repo: Operation not permitted`;
    const f = classifyBashSandboxFailure(line, null);
    expect(f).not.toBeNull();
    expect(f?.matchedLine).not.toContain(uuid);
    expect(f?.matchedLine).not.toContain("/workspaces/");
    expect(f?.matchedLine).toContain("Operation not permitted");
  });

  it("caps the matched line (no unbounded tool output reaches Sentry)", () => {
    const f = classifyBashSandboxFailure(`bwrap: Operation not permitted ${"x y ".repeat(2000)}`, null);
    expect(f).not.toBeNull();
    expect(f!.matchedLine.length).toBeLessThanOrEqual(300);
  });

  it("classifies a generic bwrap namespace EPERM as bwrap_eperm", () => {
    const f = classifyBashSandboxFailure("bwrap: Creating new namespace failed: Operation not permitted", null);
    expect(f?.errorCode).toBe("bwrap_eperm");
  });

  it("returns null for an ordinary permission error with no sandbox token", () => {
    expect(classifyBashSandboxFailure("cat: /etc/shadow: Permission denied", null)).toBeNull();
    expect(classifyBashSandboxFailure("rm: cannot remove 'x': Operation not permitted", null)).toBeNull();
  });

  it("near-miss negatives: an agent's own unshare/seccomp EPERM, and a denial on a DIFFERENT line than the token", () => {
    expect(classifyBashSandboxFailure("unshare: unshare failed: Operation not permitted", null)).toBeNull();
    expect(classifyBashSandboxFailure("seccomp: EPERM", null)).toBeNull();
    expect(classifyBashSandboxFailure("bwrap: starting\nrm: x: Operation not permitted", null)).toBeNull();
  });

  it("scrubs a bare uuid and caps at exactly 300", () => {
    const uuid = "754ee124-706a-4f21-a4f4-e828257b0380";
    const f = classifyBashSandboxFailure(`bwrap: Operation not permitted for ${uuid} ${"w ".repeat(400)}`, null);
    expect(f?.matchedLine).toContain("<uuid>");
    expect(f?.matchedLine).not.toContain(uuid);
    expect(f?.matchedLine.length).toBe(300);
  });

  it("returns null when the output merely MENTIONS bwrap without a denial on the same line", () => {
    expect(classifyBashSandboxFailure("$ which bwrap\n/usr/local/bin/bwrap\n", null)).toBeNull();
    expect(classifyBashSandboxFailure("bubblewrap 0.8.0", null)).toBeNull();
  });

  it("returns null for empty input", () => {
    expect(classifyBashSandboxFailure("", null)).toBeNull();
  });
});

// #10445 — the SDK's command-side `apply-seccomp` helper dies with EPERM on `unshare(CLONE_NEWUSER)` when the shim's
// seccomp filter is inherited; the helper prints its OWN line, which carries no bwrap token. Guard 2 mutation matrix.
describe("classifyBashSandboxFailure — apply-seccomp helper arm (#10445, Guard 2)", () => {
  // The exact line from the issue, and the shape pinned from the helper binary's strings.
  const ISSUE_LINE = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
  const BARE_UNSHARE = "unshare: unshare failed: Operation not permitted";

  it("row 1: the exact issue line classifies as helper_userns_eperm and returns ONLY the matched line", () => {
    const f = classifyBashSandboxFailure(ISSUE_LINE, "0.3.284");
    expect(f).not.toBeNull();
    expect(f?.errorCode).toBe("helper_userns_eperm");
    expect(f?.matchedLine).toBe(ISSUE_LINE);
    expect(f?.sdkVersion).toBe("0.3.284");
  });

  it("row 1: the EPERM spelling of the same step also classifies", () => {
    expect(classifyBashSandboxFailure("apply-seccomp: unshare(CLONE_NEWUSER): EPERM", null)?.errorCode).toBe(
      "helper_userns_eperm",
    );
  });

  it("another helper step failing with EPERM is NOT helper_userns_eperm: it is helper_step_eperm (#10455 e)", () => {
    expect(classifyBashSandboxFailure("apply-seccomp: prctl(PR_SET_NO_NEW_PRIVS): EPERM", null)?.errorCode).toBe(
      "helper_step_eperm",
    );
    // Not a step the helper prints: still unclassified (exact-step allowlist, no charset).
    expect(classifyBashSandboxFailure("apply-seccomp: seccomp(SET_MODE_FILTER): Operation not permitted", null)).toBeNull();
  });

  it("the line must match end to end: a tenant-chosen tail or prefix word does not classify", () => {
    expect(classifyBashSandboxFailure(`${ISSUE_LINE} and then some tenant-chosen text`, null)).toBeNull();
    expect(classifyBashSandboxFailure(`error: ${ISSUE_LINE}`, null)).toBeNull();
  });

  it("row 2: empty output and only-benign lines return null, while a positive control in the same shape is non-null", () => {
    expect(classifyBashSandboxFailure("", null)).toBeNull();
    expect(classifyBashSandboxFailure("hello\nworld\nexit 0\n", null)).toBeNull();
    // Positive control: the same benign scaffold plus the helper line must be non-null (guards a vacuous null).
    expect(classifyBashSandboxFailure(`hello\nworld\n${ISSUE_LINE}\n`, null)).not.toBeNull();
  });

  it("row 3: benign first line, helper line second, bare unshare third classifies line 2 only (no stop-at-first-line)", () => {
    const out = `ls: ok\n${ISSUE_LINE}\n${BARE_UNSHARE}\n`;
    const f = classifyBashSandboxFailure(out, null);
    expect(f?.errorCode).toBe("helper_userns_eperm");
    expect(f?.matchedLine).toBe(ISSUE_LINE);
    expect(f?.matchedLine).not.toContain("unshare failed");
  });

  it("row 3: CRLF line endings are split the same way", () => {
    const f = classifyBashSandboxFailure(`ls: ok\r\n${ISSUE_LINE}\r\n`, null);
    expect(f?.matchedLine).toBe(ISSUE_LINE);
  });

  it("row 4: an agent's own `unshare -U` output (bare unshare / seccomp token) stays non-matching", () => {
    expect(classifyBashSandboxFailure(BARE_UNSHARE, null)).toBeNull();
    expect(classifyBashSandboxFailure("unshare: unshare(CLONE_NEWUSER): Operation not permitted", null)).toBeNull();
    expect(classifyBashSandboxFailure("seccomp: EPERM", null)).toBeNull();
  });

  it("the arm anchors on the line START: a line that merely mentions apply-seccomp mid-line does not match", () => {
    expect(classifyBashSandboxFailure("grep apply-seccomp: Operation not permitted", null)).toBeNull();
    expect(classifyBashSandboxFailure("echo 'see apply-seccomp: EPERM'", null)).toBeNull();
  });

  it("the arm needs a denial on the SAME line: apply-seccomp alone or a denial on another line is null", () => {
    expect(classifyBashSandboxFailure("apply-seccomp: starting", null)).toBeNull();
    expect(classifyBashSandboxFailure("apply-seccomp: starting\nrm: x: Operation not permitted", null)).toBeNull();
  });

  it("a bwrap line before the helper line is the one returned, with its own code", () => {
    const f = classifyBashSandboxFailure(`bwrap: Can't mount proc on /newroot/proc: Operation not permitted\n${ISSUE_LINE}`, null);
    expect(f?.errorCode).toBe("proc_mount_eperm");
  });

  it("the matched line is the fixed helper line, whatever surrounds it", () => {
    const f = classifyBashSandboxFailure(`/workspaces/x says:\n${ISSUE_LINE}\n`, null);
    expect(f?.matchedLine).toBe(ISSUE_LINE);
  });
});

// #10455 e — every step line the vendored helper can print is classified or deliberately excluded (Guard 2).
// Step list MEASURED on claude-agent-sdk 0.3.284 (strings of the embedded helper; runtime order recorded with an
// LD_PRELOAD interposer on 2026-10-19): 16 `<step>: <strerror>` literals + the errno-less `observe sendmsg failed`.
describe("apply-seccomp helper steps — classification (#10455 e, Guard 2)", () => {
  const USERNS = "unshare(CLONE_NEWUSER)";
  const NON_USERNS = HELPER_STEPS.filter((s) => s !== USERNS);
  const POST_FORK = ["fork(worker)", "prctl(PR_SET_NO_NEW_PRIVS)", "prctl(PR_SET_SECCOMP)", "execvp", "waitpid"];
  const line = (step: string, errno = "Operation not permitted") => `apply-seccomp: ${step}: ${errno}`;

  it("floor: the allowlist is the 16 measured steps, userns among them, with no duplicates", () => {
    expect(HELPER_STEPS).toHaveLength(16);
    expect(new Set(HELPER_STEPS).size).toBe(16);
    expect(HELPER_STEPS).toContain(USERNS);
    expect(NON_USERNS).toHaveLength(15);
  });

  it.each(HELPER_STEPS)("step %s: EPERM (both spellings) classifies; the matched line is the fixed line", (step) => {
    for (const errno of ["Operation not permitted", "EPERM"]) {
      const f = classifyBashSandboxFailure(line(step, errno), null);
      expect(f?.errorCode, `${step} / ${errno}`).toBe(step === USERNS ? "helper_userns_eperm" : "helper_step_eperm");
      expect(f?.matchedLine).toBe(line(step, errno));
    }
  });

  it.each(HELPER_STEPS)("step %s: EACCES / EINVAL / a tenant-chosen tail / a prefix stay unclassified", (step) => {
    expect(classifyBashSandboxFailure(line(step, "Permission denied"), null)).toBeNull();
    expect(classifyBashSandboxFailure(line(step, "Invalid argument"), null)).toBeNull();
    expect(classifyBashSandboxFailure(`${line(step)} then tenant text`, null)).toBeNull();
    expect(classifyBashSandboxFailure(`error: ${line(step)}`, null)).toBeNull();
    // A tail hidden past the scan cap behind padding must not slip through the line-end anchor.
    expect(classifyBashSandboxFailure(`${line(step)}${" ".repeat(2100)}tenant`, null)).toBeNull();
  });

  it("an unknown or wrapped step is not classified (exact-match allowlist, no charset)", () => {
    expect(classifyBashSandboxFailure("apply-seccomp: prctl(PR_FOO): EPERM", null)).toBeNull();
    expect(classifyBashSandboxFailure(`apply-seccomp: ${USERNS} after userns: EPERM`, null)).toBeNull();
    expect(classifyBashSandboxFailure("apply-seccomp: observe sendmsg failed", null)).toBeNull();
    expect(classifyBashSandboxFailure("apply-seccomp: : EPERM", null)).toBeNull();
  });

  it("the errno-less helper message is deliberately excluded, and the exclusions are not allowlisted", () => {
    expect(HELPER_NON_STEP_LINES).toEqual(["observe sendmsg failed"]);
    for (const x of HELPER_NON_STEP_LINES) expect(HELPER_STEPS).not.toContain(x);
  });

  it("the pre-worker-fork subset is exactly the 11 steps that run before fork(worker); the 5 others never trigger the notice", () => {
    expect(HELPER_STEPS_PRE_WORKER_FORK).toHaveLength(11);
    for (const s of HELPER_STEPS_PRE_WORKER_FORK) expect(HELPER_STEPS).toContain(s);
    expect([...HELPER_STEPS].filter((s) => !HELPER_STEPS_PRE_WORKER_FORK.includes(s)).sort()).toEqual([...POST_FORK].sort());
  });

  it("Guard 2 row 5: a post-worker-fork line never triggers the notice, even as a single error line", () => {
    for (const step of POST_FORK) {
      expect(isPreExecSandboxDenialOutput(line(step), true), step).toBe(false);
    }
    // ...while it is still classified, so the page still fires.
    expect(classifyBashSandboxFailure(line("waitpid"), null)?.errorCode).toBe("helper_step_eperm");
  });
});

describe("isPreExecSandboxDenialOutput — the notice predicate (#10455 c, Guard 2)", () => {
  const HELPER = "apply-seccomp: prctl(PR_SET_DUMPABLE): Operation not permitted";
  const USERNS_LINE = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
  const BWRAP = "bwrap: Can't mount proc on /newroot/proc: Operation not permitted";

  it("every pre-fork step line, alone and error-flagged, qualifies", () => {
    expect(HELPER_STEPS_PRE_WORKER_FORK.length).toBeGreaterThan(0); // floor: an empty table must not pass vacuously
    for (const step of HELPER_STEPS_PRE_WORKER_FORK) {
      expect(isPreExecSandboxDenialOutput(`apply-seccomp: ${step}: Operation not permitted`, true), step).toBe(true);
    }
    expect(isPreExecSandboxDenialOutput(BWRAP, true)).toBe(true);
  });

  it("requires an error result: a non-error or unknown-flag result never qualifies (forged-line guard)", () => {
    expect(isPreExecSandboxDenialOutput(USERNS_LINE, false)).toBe(false);
    expect(isPreExecSandboxDenialOutput(USERNS_LINE, undefined)).toBe(false);
  });

  it("Guard 2 row 6: mixed output (a helper line plus an ordinary line) does not qualify", () => {
    expect(isPreExecSandboxDenialOutput(`${HELPER}\nhello`, true)).toBe(false);
    expect(isPreExecSandboxDenialOutput(`hello\n${HELPER}`, true)).toBe(false);
    expect(isPreExecSandboxDenialOutput(`${HELPER}\n${USERNS_LINE}`, true)).toBe(false);
    expect(isPreExecSandboxDenialOutput(`${BWRAP}\nrm: x: Operation not permitted`, true)).toBe(false);
  });

  it("Guard 2 row 7 (must-PASS): CRLF, leading whitespace and blank lines around the one line are permitted", () => {
    expect(isPreExecSandboxDenialOutput(`  ${HELPER}\r\n`, true)).toBe(true);
    expect(isPreExecSandboxDenialOutput(`\n\n\t${HELPER}  \r\n\r\n`, true)).toBe(true);
  });

  it("a tenant-chosen tail, a prefix, an empty string, or an oversized line never qualifies", () => {
    expect(isPreExecSandboxDenialOutput(`${HELPER} extra`, true)).toBe(false);
    expect(isPreExecSandboxDenialOutput(`echo ${HELPER}`, true)).toBe(false);
    expect(isPreExecSandboxDenialOutput("", true)).toBe(false);
    expect(isPreExecSandboxDenialOutput(`${BWRAP} ${"x ".repeat(2000)}`, true)).toBe(false);
  });

  it("an ordinary EPERM that is not a sandbox line does not qualify", () => {
    expect(isPreExecSandboxDenialOutput("rm: cannot remove 'x': Operation not permitted", true)).toBe(false);
    expect(isPreExecSandboxDenialOutput("unshare: unshare failed: Operation not permitted", true)).toBe(false);
  });

  it("the notice is the agreed plain sentence and does NOT claim the command did not run", () => {
    expect(BASH_UNAVAILABLE_NOTICE).toBe(
      "Platform notice: command execution is temporarily unavailable on our side. This is a platform issue, not a problem with your project.",
    );
    expect(BASH_UNAVAILABLE_NOTICE).not.toMatch(/did not run|not run|never ran|apply-seccomp|bwrap/i);
  });

  it("a 5000-character slash-heavy single line is rejected without a long scan", () => {
    const t0 = Date.now();
    expect(isPreExecSandboxDenialOutput(`bwrap: ${"/a".repeat(2500)} Operation not permitted`, true)).toBe(false);
    expect(Date.now() - t0).toBeLessThan(200);
  });
});

// Guard 2 vs the REAL helper: the allowlist is derived from, and checked against, the vendored binary's own strings.
describe("apply-seccomp helper steps — census against the vendored binary (Guard 2)", () => {
  const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
  const SKIP_REAL = shouldSkipRealBinaryRows(process.platform, process.arch, process.env.CI);
  const PINS = { classified: HELPER_STEPS, excluded: HELPER_NON_STEP_LINES, minStrings: 17 };
  let realRowsRun = 0;

  // Independent of SKIP_REAL (a floor that reads the skip flag would be satisfied by the very skip it guards).
  const MUST_RUN_REAL = (process.platform === "linux" && process.arch === "x64") || Boolean(process.env.CI);

  afterAll(() => {
    // A skip must not pass vacuously: on linux-x64, or under CI, at least one real-binary row has to have run.
    if (MUST_RUN_REAL) expect(realRowsRun, "no real-binary helper-step row ran").toBeGreaterThanOrEqual(1);
  });

  it.skipIf(SKIP_REAL)(
    "the claude-agent-sdk binary carries exactly the allowlisted steps plus the excluded errno-less message",
    () => {
      const bin = resolveVendoredBinary("claude-agent-sdk", join(APP_ROOT, "node_modules"));
      const fs = fileSource(bin.path);
      try {
        const found = scanHelperStepStrings(fs.source);
        realRowsRun += 1;
        assertHelperStepCensus(found, PINS, `claude-agent-sdk ${bin.version}`);
      } finally {
        fs.close();
      }
    },
    90_000,
  );

  // Harness rows (synthetic buffers): the census itself reds on each drift direction.
  const synth = (steps: readonly string[]) => bufferSource(Buffer.from(steps.map((s) => `apply-seccomp: ${s}`).join("\0") + "\0"));
  const FULL = [...HELPER_STEPS, ...HELPER_NON_STEP_LINES];
  const failureOf = (fn: () => void): string => {
    try {
      fn();
      return "";
    } catch (e) {
      return (e as Error).message;
    }
  };

  it("harness: the complete step set passes the census (must-PASS control, order independent)", () => {
    expect(failureOf(() => assertHelperStepCensus(scanHelperStepStrings(synth([...FULL].reverse())), PINS, "synthetic"))).toBe("");
  });

  it("Guard 2 row 1: an allowlisted step absent from the binary reds HELPER_STEP_ABSENT", () => {
    const without = FULL.filter((s) => s !== "prctl(PR_SET_DUMPABLE)");
    expect(failureOf(() => assertHelperStepCensus(scanHelperStepStrings(synth(without)), PINS, "synthetic"))).toMatch(
      /HELPER_STEP_ABSENT.*PR_SET_DUMPABLE/,
    );
  });

  it("Guard 2 row 3: a scan that reads zero strings reds the floor (never passes vacuously)", () => {
    expect(scanHelperStepStrings(bufferSource(Buffer.alloc(0)))).toEqual([]);
    expect(failureOf(() => assertHelperStepCensus([], PINS, "synthetic"))).toMatch(/HELPER_STEP_FLOOR/);
  });

  it("Guard 2 row 4: a new step in the binary that is neither classified nor excluded reds HELPER_STEP_NEW", () => {
    const withNew = [...FULL, "prctl(PR_SET_NEW_THING)"];
    expect(failureOf(() => assertHelperStepCensus(scanHelperStepStrings(synth(withNew)), PINS, "synthetic"))).toMatch(
      /HELPER_STEP_NEW.*PR_SET_NEW_THING/,
    );
  });

  it("a string that only mentions the prefix mid-text is read bounded and never throws", () => {
    const found = scanHelperStepStrings(bufferSource(Buffer.from(`xx apply-seccomp: ${"y".repeat(500)}\0`)));
    expect(found).toHaveLength(1);
    expect(found[0].length).toBeLessThanOrEqual(200);
  });
});
