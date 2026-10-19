/**
 * Typed classification of a sandbox-STARTUP failure caught in the session
 * catch blocks of `agent-runner.ts` (`startAgentSession`) and
 * `cc-dispatcher.ts` (the `sdkQuery` factory).
 *
 * Background (feat-harden-agent-sandbox #5875, PR1 · ADR-079): the 2026-07-01
 * P0 (#5873) was a seccomp EPERM on the split `unshare()` the SDK bump #5849
 * introduced — the container seccomp profile only allowed `unshare` when
 * `CLONE_NEWUSER` was set, so the SDK's second `unshare(CLONE_NEWPID|CLONE_NEWNS)`
 * EPERM'd and every tenant's Concierge Bash sandbox went down. The catch sites
 * only tagged the SDK's missing-binary preflight substring
 * ("sandbox required but unavailable"), so the seccomp EPERM fell through to a
 * bare untagged `captureException` — ZERO on-call signal.
 *
 * Phase-0 spike finding (recorded in #5875): the bwrap/seccomp stderr —
 * including "Operation not permitted" — is merged into the thrown `Error`'s
 * `.message` (plain `Error`, no separate `.stderr`/`.cause`/`.data`). So
 * classification keys on the message text.
 *
 * Mirrors the `abort-classifier.ts` precedent: ONE decoding site, so the
 * substring matching lives in a single obvious place instead of being scattered
 * across the two catch blocks as ad-hoc `.includes()` checks.
 */
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";

/** Category of a sandbox-startup failure. A single enum (not a fan-out of
 *  per-hypothesis booleans) — a human reads the raw stderr; add a value only
 *  when a specific alert route must branch on it. */
export type SandboxKind =
  | "missing_binary" // SDK preflight: the sandbox binary is absent/unavailable
  | "seccomp_or_userns_denial" // the #5873 shape: bwrap/unshare/seccomp EPERM
  | "other"; // not a recognized sandbox-startup signature

/** Stable, low-cardinality code for Sentry tag / alert routing. Refines
 *  `sandboxKind` with the specific matched signature. */
export type SandboxErrorCode =
  | "sandbox_unavailable" // missing_binary
  | "bwrap_eperm" // seccomp_or_userns_denial with an explicit EPERM
  | "bwrap_error" // seccomp_or_userns_denial, sandbox token but no explicit EPERM
  | "unclassified"; // other

export interface SandboxStartupClassification {
  sandboxKind: SandboxKind;
  errorCode: SandboxErrorCode;
  /** Installed `@anthropic-ai/claude-agent-sdk` version (best-effort;
   *  `null` when unresolvable). The bump is what changed the sandbox
   *  codepath, so this is the highest-signal field for triaging a recurrence. */
  sdkVersion: string | null;
  /** Raw stderr / error message, UNREDACTED — a human reads it in Sentry.
   *  (The event's `userId` is pseudonymized at the emit boundary; the stderr
   *  is bwrap/kernel output, not tenant PII.) */
  stderr: string;
}

/** SDK missing-binary preflight — the only signature the pre-PR1 catch sites
 *  recognized. Kept as the `missing_binary` discriminator. */
const SANDBOX_UNAVAILABLE = "sandbox required but unavailable";

/** Bubblewrap / user-namespace / seccomp namespace tokens. A generic EPERM is
 *  NOT enough — require one of these so a mid-conversation file-permission
 *  error elsewhere is never mis-tagged as a sandbox-namespace denial. */
const SANDBOX_NAMESPACE_SIGNATURES: readonly RegExp[] = [
  /\bbwrap\b/i,
  /\bunshare\b/i,
  /\bseccomp\b/i,
  /CLONE_NEW(USER|PID|NS|NET|UTS|IPC)/i,
];

/** The kernel EPERM signature that made #5873 an availability outage. */
const OPERATION_NOT_PERMITTED = /operation not permitted|\bEPERM\b/i;

/** Cached best-effort resolution of the installed SDK version. `undefined`
 *  means "not yet resolved"; `null` means "resolved, unavailable". */
let _sdkVersion: string | null | undefined;

/** Resolve the installed `@anthropic-ai/claude-agent-sdk` version. The package
 *  restricts its `exports` map (no `./package.json` subpath), so we resolve the
 *  entry point and walk up to its `package.json`. Never throws — best-effort. */
function resolveSdkVersion(): string | null {
  if (_sdkVersion !== undefined) return _sdkVersion;
  _sdkVersion = null;
  try {
    const require = createRequire(import.meta.url);
    let dir = dirname(require.resolve("@anthropic-ai/claude-agent-sdk"));
    for (let i = 0; i < 6; i++) {
      try {
        const pkg = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
        if (
          pkg?.name === "@anthropic-ai/claude-agent-sdk" &&
          typeof pkg.version === "string"
        ) {
          _sdkVersion = pkg.version;
          break;
        }
      } catch {
        // package.json not at this level (or unreadable) — keep walking up.
      }
      const parent = dirname(dir);
      if (parent === dir) break; // reached the filesystem root
      dir = parent;
    }
  } catch {
    _sdkVersion = null;
  }
  return _sdkVersion ?? null;
}

/**
 * Classify a caught session error as a sandbox-startup failure category.
 * Keyed on the error MESSAGE (Phase-0: bwrap/seccomp stderr merges into
 * `.message`). `sdkVersion` is injectable for deterministic tests; the default
 * resolves the installed version best-effort.
 */
/**
 * Extract the classification text from a caught error. Phase-0 confirmed
 * 0.3.197 merges the bwrap/seccomp stderr into `.message`, but a future SDK
 * could relocate it onto `.cause` or a `.stderr` property — so scan those too.
 * Without this, an SDK that moved the text would silently degrade every case to
 * `"other"` (zero signal — a recurrence of the #5873 blind-surface failure).
 * The namespace-token requirement in the classifier keeps the wider scan from
 * introducing false positives.
 */
function extractErrorText(err: unknown): string {
  if (!(err instanceof Error)) return String(err);
  const parts: string[] = [err.message];
  const cause: unknown = (err as { cause?: unknown }).cause;
  if (cause instanceof Error && cause.message) parts.push(cause.message);
  else if (typeof cause === "string" && cause) parts.push(cause);
  const stderrProp: unknown = (err as { stderr?: unknown }).stderr;
  if (typeof stderrProp === "string" && stderrProp) parts.push(stderrProp);
  return parts.join("\n");
}

export function classifySandboxStartupError(
  err: unknown,
  sdkVersion: string | null = resolveSdkVersion(),
): SandboxStartupClassification {
  const stderr = extractErrorText(err);

  if (stderr.toLowerCase().includes(SANDBOX_UNAVAILABLE)) {
    return {
      sandboxKind: "missing_binary",
      errorCode: "sandbox_unavailable",
      sdkVersion,
      stderr,
    };
  }

  const hasNamespaceToken = SANDBOX_NAMESPACE_SIGNATURES.some((re) =>
    re.test(stderr),
  );
  if (hasNamespaceToken) {
    return {
      sandboxKind: "seccomp_or_userns_denial",
      errorCode: OPERATION_NOT_PERMITTED.test(stderr)
        ? "bwrap_eperm"
        : "bwrap_error",
      sdkVersion,
      stderr,
    };
  }

  return { sandboxKind: "other", errorCode: "unclassified", sdkVersion, stderr };
}

/** A sandbox denial found in a Bash `tool_result`'s output (#10032 follow-up). */
export interface BashSandboxFailure {
  errorCode: "proc_mount_eperm" | "bwrap_eperm" | "helper_userns_eperm" | "helper_step_eperm";
  /** ONLY the matched line, scrubbed and capped — never the surrounding tool output. */
  matchedLine: string;
  sdkVersion: string | null;
  /** The helper step literal for `helper_*` codes (an exact member of `HELPER_STEPS`); absent for bwrap codes. */
  helperStep?: string;
}

/** Longest matched line forwarded to Sentry. */
const BASH_MATCHED_LINE_CAP = 300;
/**
 * Lines are bounded BEFORE any regex runs: a naive path-scrub regex is quadratic on a long slash-heavy line (measured
 * 17 s at 100k chars), and this runs on the event loop shared by every tenant. A real bwrap denial is one short line.
 */
const BASH_LINE_SCAN_CAP = 2000;
const BASH_BWRAP_TOKEN = /\b(?:bwrap|bubblewrap)\b/i;
// The SDK's command-side `apply-seccomp` helper (#10445) prints its own `apply-seccomp: <step>: <errno>` line with no
// bwrap token. Matched as the WHOLE line against an EXACT-step allowlist (no charset): a line that must match end to
// end carries no tenant-chosen tail, so the emitted `matchedLine` is a fixed string a forged line cannot extend.
// Only EPERM counts; EACCES / EINVAL helper failures stay unclassified (a recorded residual, #10455).
//
// The step list is MEASURED, not recalled: the 16 `apply-seccomp: <step>` literals of the helper embedded in the
// vendored `claude` binary (claude-agent-sdk 0.3.284; identical in claude-code 2.1.293), read from its string pool,
// plus the runtime order recorded with an LD_PRELOAD interposer on 2026-10-19. A test (sandbox-startup-classifier
// .test.ts, Guard 2) re-reads the binary and reds when this list and the binary disagree in either direction.
const HELPER_USERNS_STEP = "unshare(CLONE_NEWUSER)";

/**
 * Steps that run strictly BEFORE the helper forks its worker (`fork(worker)`). Runtime order (helper process, then
 * the PID-namespace init it forks): unshare(NEWPID|NEWNS) attempt, unshare(CLONE_NEWUSER), write setgroups / uid_map /
 * gid_map, unshare(NEWPID|NEWNS) after userns, `fork` (the init), then in the init prctl(PR_SET_DUMPABLE),
 * mount(MS_PRIVATE), mount(/proc), prctl(PR_CAP_AMBIENT_CLEAR_ALL), and only then `fork(worker)`.
 * Only these may trigger the user-facing notice: every one of them fails before the tenant command could start.
 */
export const HELPER_STEPS_PRE_WORKER_FORK: readonly string[] = [
  HELPER_USERNS_STEP,
  "write /proc/self/setgroups (nested userns is capability-restricted; caller must provide CAP_SYS_ADMIN)",
  "write /proc/self/uid_map",
  "write /proc/self/gid_map",
  "unshare(CLONE_NEWPID|CLONE_NEWNS)",
  "unshare(CLONE_NEWPID|CLONE_NEWNS) after userns",
  "fork",
  "prctl(PR_SET_DUMPABLE)",
  "mount(MS_PRIVATE)",
  "mount(/proc)",
  "prctl(PR_CAP_AMBIENT_CLEAR_ALL)",
];

/** Steps at or after the worker fork: the worker's pre-exec calls and the waiters. Classified (so they page) but
 *  never rewritten into the notice: `waitpid` is printed AFTER the tenant command ran, so its line can sit behind
 *  real command output and a forged copy proves nothing. */
const HELPER_STEPS_AT_OR_AFTER_WORKER_FORK: readonly string[] = [
  "fork(worker)",
  "prctl(PR_SET_NO_NEW_PRIVS)",
  "prctl(PR_SET_SECCOMP)",
  "execvp",
  "waitpid",
];

/** Every helper step that takes a `: <strerror>` suffix: the exact-match allowlist. */
export const HELPER_STEPS: readonly string[] = [
  ...HELPER_STEPS_PRE_WORKER_FORK,
  ...HELPER_STEPS_AT_OR_AFTER_WORKER_FORK,
];

/** Helper strings deliberately NOT classified: a fixed message with no errno suffix. */
export const HELPER_NON_STEP_LINES: readonly string[] = ["observe sendmsg failed"];

const HELPER_STEP_SET: ReadonlySet<string> = new Set(HELPER_STEPS);
const HELPER_PRE_FORK_SET: ReadonlySet<string> = new Set(HELPER_STEPS_PRE_WORKER_FORK);
// Captures the step; membership in HELPER_STEP_SET is the exact-match check, so no charset reasoning is needed.
const BASH_APPLY_SECCOMP_LINE = /^[ \t]*apply-seccomp: (.{1,160}): (?:Operation not permitted|EPERM)[ \t]*$/;
const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
// EVERY absolute path token (a solo workspace's id IS the user id, and /home, /var/lib, /tmp paths are tenant-adjacent
// too) except bwrap's own `/newroot/{proc,dev,sys,tmp}` targets, which carry the diagnostic. Linear: it only starts at
// a `/` and consumes a maximal run, so a long slash-heavy line cannot backtrack.
const ABS_PATH_RE = /(?<![\w./-])\/(?!newroot\/(?:proc|dev|sys|tmp)\b)[^\s:'"]+/g;
// Opaque long tokens (API keys, hashes, base64) that share the line with the denial.
const OPAQUE_TOKEN_RE = /[A-Za-z0-9_+=-]{32,}/g;
// Control characters and line/paragraph separators, so a forwarded line cannot forge log rows.
const CONTROL_RE = /[\p{Cc}\u2028\u2029]/gu;

/**
 * Classify a Bash `tool_result` output as a sandbox denial.
 *
 * Why this exists: `classifySandboxStartupError` only sees errors THROWN out of the SDK iterator. A sandbox
 * spawn that the SDK returns to the model as a tool_result — the shape a bwrap refusal takes mid-session —
 * reached Sentry as nothing, so a fleet-wide sandbox outage with no thrown error was invisible (#10032 left
 * tenant impact unobservable).
 *
 * Data minimisation (Art. 5(1)(c)): a tool_result is ARBITRARY command output, which can carry tenant file
 * contents next to the bwrap line. The result carries ONLY the single matched line — scrubbed of paths, uuids,
 * opaque tokens and control characters, capped at 300 chars — never the surrounding output and never the command.
 *
 * A line matches only when ONE line carries both a sandbox namespace token (or starts with the SDK helper's
 * `apply-seccomp:` prefix, #10445) and a denial (`Operation not
 * permitted` / `EPERM`): a command that merely prints "bwrap", or an unrelated EPERM, never matches.
 */
export function classifyBashSandboxFailure(
  output: string,
  sdkVersion: string | null = resolveSdkVersion(),
): BashSandboxFailure | null {
  if (output.length === 0) return null;
  for (const full of output.split(/\r?\n/)) {
    const raw = full.slice(0, BASH_LINE_SCAN_CAP);
    // `bwrap`/`bubblewrap` or the line-anchored `apply-seccomp:` helper only: a bare `unshare` or `seccomp` line is
    // what an agent's OWN `unshare -U` under the sandbox prints (the canary expects that EPERM), not a sandbox failure.
    // A helper line longer than the scan cap is never a helper line: the cap would otherwise hide a tail behind padding.
    const helperStep =
      full.length <= BASH_LINE_SCAN_CAP ? (BASH_APPLY_SECCOMP_LINE.exec(raw)?.[1] ?? null) : null;
    const isHelperLine = helperStep !== null && HELPER_STEP_SET.has(helperStep);
    if (!isHelperLine && !BASH_BWRAP_TOKEN.test(raw)) continue;
    if (!OPERATION_NOT_PERMITTED.test(raw)) continue;
    // An allowlisted helper line is a FIXED string (exact step, exact errno, nothing else on the line): nothing in it
    // is tenant data, so it is forwarded as is rather than path-scrubbed (the scrub would turn `/proc/self/uid_map`
    // into `<path>` and blur which step failed).
    const matchedLine = isHelperLine
      ? raw.trim()
      : raw
          .replace(CONTROL_RE, " ")
          .replace(UUID_RE, "<uuid>")
          .replace(ABS_PATH_RE, "<path>")
          .replace(OPAQUE_TOKEN_RE, "<token>")
          .trim()
          .slice(0, BASH_MATCHED_LINE_CAP);
    return {
      errorCode: isHelperLine
        ? helperStep === HELPER_USERNS_STEP
          ? "helper_userns_eperm"
          : "helper_step_eperm"
        : /can't mount proc/i.test(raw)
          ? "proc_mount_eperm"
          : "bwrap_eperm",
      matchedLine,
      sdkVersion,
      ...(isHelperLine ? { helperStep: helperStep as string } : {}),
    };
  }
  return null;
}

/**
 * The fixed sentence a tenant sees in place of a raw sandbox error line (#10455 c). It names no mechanism and does
 * NOT claim the command did not run: a tenant, or a prompt-injected file, can print an exact helper line after a
 * command that ran (`rm -rf x && echo "<line>"`), so "did not run" would be a false statement in that case.
 */
export const BASH_UNAVAILABLE_NOTICE =
  "Platform notice: command execution is temporarily unavailable on our side. This is a platform issue, not a problem with your project.";

/**
 * True only when a Bash tool_result is, as a whole, ONE pre-exec platform denial the user should see as the notice:
 *   - the result is flagged as an error (`is_error`), so a command that exited 0 can never be rewritten,
 *   - the trimmed output is exactly ONE non-blank line (mixed or multi-line output falls through unchanged),
 *   - that line is a classified helper line from the PRE-worker-fork subset, or a bwrap-token EPERM line,
 *   - the line fits the scan cap (a longer line is never rewritten).
 * A forged single line from a command that ran and exited non-zero can still satisfy this: the residual is accepted
 * and recorded in the runbook, which is why the notice makes no claim about whether the command ran. The mirror event
 * (and its page) is independent of this predicate.
 */
export function isPreExecSandboxDenialOutput(output: string, isError: boolean | undefined): boolean {
  if (isError !== true) return false;
  // Bound before any split: a denial line is short; anything this long is real command output.
  if (output.length === 0 || output.length > BASH_LINE_SCAN_CAP * 2) return false;
  const lines = output.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.length !== 1 || lines[0].length > BASH_LINE_SCAN_CAP) return false;
  const failure = classifyBashSandboxFailure(lines[0], null);
  if (!failure) return false;
  if (failure.errorCode === "proc_mount_eperm" || failure.errorCode === "bwrap_eperm") return true;
  return failure.helperStep !== undefined && HELPER_PRE_FORK_SET.has(failure.helperStep);
}

// NOTE (CTO ruling, ADR-079): there is deliberately NO stream-phase gate here.
// A caught session error is tagged `feature:"agent-sandbox"` at both catch sites
// IFF `classifySandboxStartupError(err).sandboxKind !== "other"`. The signature
// match (a bwrap/unshare/seccomp/CLONE_NEW* namespace token, or the SDK's
// missing-binary preflight phrase) is necessary AND sufficient to exclude
// model/API errors — those carry no such token. A `streamStartSent`-style gate
// was rejected: `streamStartSent` is set unconditionally BEFORE the SDK iterator
// loop (agent-runner.ts:2111), so it is always `true` at the catch, and the
// #5873 seccomp denial surfaces AFTER `stream_start` (the sandbox wraps the
// model-driven Bash tool, Phase-0 §0.2) — the gate produced a silent no-op on
// the exact incident shape.
