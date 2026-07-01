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
export function classifySandboxStartupError(
  err: unknown,
  sdkVersion: string | null = resolveSdkVersion(),
): SandboxStartupClassification {
  const stderr = err instanceof Error ? err.message : String(err);

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
