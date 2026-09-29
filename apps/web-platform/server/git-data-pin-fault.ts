// #8572 — the git-data host-key pin-fault marker.
//
// One Sentry tag, `pin_fault`, that `sentry_alert.git_data_host_key_pin_fault`
// (infra/sentry/issue-alerts.tf) routes to the operator. It names why a git-data dial was
// refused or failed on the pinned host key, from two surfaces:
//   - boot: `logGitDataHostKeyPinAtStartup` (pin invalid, pin absent while armed, no ssh);
//   - push: `replicateToGitData`'s catch, classified by `classifyGitDataPinFault`. A host
//     identity fault is read only off the provision dial (`via="ssh"`), never off the push.
// `reportGitDataPinFault` below is the ONLY writer of the tag in the app
// (sentry-git-data-pin-fault-alert-op-contract.test.ts holds that).
//
// NOT covered: the Art. 17 erasure path. Its reports already page through
// `sentry_alert.art17_erasure_incomplete`, which routes every outcome; tagging them
// `pin_fault` too would send two emails for one refusal (CLO ruling, #8572).
//
// MESSAGE PATH ON PURPOSE — do not switch this to `reportSilentFallback(new Error(…))`
// "for a stack trace". On the Error path, `reportSilentFallback` logs first, the pino
// mirror (server/logger.ts `mirrorToSentry`) captures the SAME Error instance as
// `feature=pino-mirror`, and @sentry/core's `checkOrSetAlreadyCaught` then drops the
// second, tagged capture, so the event arrives with no `pin_fault` and the alert never
// matches it. With `err = null` the call goes through `captureMessage`, and the pino hook
// has no Error to capture. The fleet-wide defect is tracked in #8629.
//
// Unlike the message-path precedents (server/anthropic-credit.ts,
// server/spawn-dead-letter.ts), the capture runs inside a FORKED isolation scope with its
// breadcrumbs cleared (the fork keeps the parent's tags and contexts; only breadcrumbs are
// dropped). The push reports from the session-end path, which opens no scope of its own,
// so the event would otherwise carry other sessions' breadcrumbs — and those can hold raw
// workspace paths that the scrub (which redacts by key name) does not catch.

import * as Sentry from "@sentry/nextjs";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

/**
 * Sorted, and the alert rule's `in` value is exactly `GIT_DATA_PIN_FAULT_REASONS.join(",")`
 * (sentry-git-data-pin-fault-alert-op-contract.test.ts holds both).
 */
export const GIT_DATA_PIN_FAULT_REASONS = [
  "host_key_mismatch",
  "pin_absent",
  "pin_invalid",
  "ssh_client_absent",
] as const;

export type GitDataPinFault = (typeof GIT_DATA_PIN_FAULT_REASONS)[number];

/**
 * (#7226, H4) Host identity failures: no common host-key algorithm (alg), no key known under
 * the alias (unknown), a changed key / failed verification (changed) — the three classes of
 * git-data-cutover.sh `_access_reason`. Unlike that classifier this is unanchored (it matches
 * mid-line), so it is only ever read off stderr no tenant input reaches: the erasure and
 * provision ssh dials, never the git push (#9152 tracks unifying the two). The erasure path
 * checks it before its auth-failure pattern on a 255. Under `StrictHostKeyChecking=yes` it
 * also matches an absent or unwritable known_hosts file, so a match means "the pinned
 * identity was not established", not strictly "the host presented a different key".
 */
export const SSH_HOST_KEY_MISMATCH =
  /no matching host key type found|no \S+ host key is known for|remote host identification has changed|host key verification failed/i;

/**
 * The pin resolver's refusal. The constructor takes only the reason and the flag state and
 * builds its own fixed message, so no caller can pass text and the pin value can never
 * reach the message (a malformed secret can be anything, a pasted private key included).
 * The two messages are byte-identical to the resolver's strings before #8572.
 */
export class GitDataHostKeyPinError extends Error {
  readonly reason: "pin_absent" | "pin_invalid";

  constructor(reason: "pin_absent" | "pin_invalid", opts: { storeEnabled: boolean }) {
    super(
      reason === "pin_invalid"
        ? "git-data: GIT_DATA_SSH_HOST_KEY is malformed — expected exactly one " +
            "`ssh-ed25519 <base64>` key with no host pattern, marker, comment or newline. " +
            "Refusing to dial the git-data host."
        : `git-data: GIT_DATA_SSH_HOST_KEY is unset (${opts.storeEnabled ? "GIT_DATA_STORE_ENABLED=true" : "GIT_DATA_STORE_ENABLED is not true"}) — ` +
            "refusing unpinned SSH to the git-data host. The replace job publishes it to Doppler prd; " +
            "if the secret is already there, the container has not loaded it (dispatch git-data-cutover.yml mode=redeploy to re-load it).",
    );
    this.name = "GitDataHostKeyPinError";
    this.reason = reason;
  }
}

/**
 * Classify a git-data push failure as a pin fault, or `null` for anything else (which the
 * caller reports on its existing Error path). `via` names the transport that was running:
 * `ssh` for the provision dial, `git` for the push. Total: never throws.
 *
 * `host_key_mismatch` is read only on `via="ssh"`, from ssh's own exit status 255 (through
 * ssh any other non-zero is the REMOTE command's status and is never read as a host fault).
 * Never on `via="git"`: git exits 128 on EVERY fatal error, and several of those echo bytes
 * from the tenant's workspace (`fatal: unexpected line in .git/packed-refs: <line>`), so a
 * tenant could forge the page and, sharing its Sentry issue and throttle window, mask a real
 * one. Nothing is lost: the provision dial runs first, on the same host, pin and client, so a
 * genuine host fault surfaces there.
 */
export function classifyGitDataPinFault(err: unknown, via: "ssh" | "git"): GitDataPinFault | null {
  try {
    if (err === null || typeof err !== "object") return null;
    const e = err as { name?: unknown; reason?: unknown; code?: unknown; syscall?: unknown; stderr?: unknown };
    // `name` as well as `instanceof`: a module loaded twice (test isolation, a bundler
    // split) defeats `instanceof`. The reason is re-validated, so a forged one is dropped.
    if (err instanceof GitDataHostKeyPinError || e.name === "GitDataHostKeyPinError") {
      return e.reason === "pin_absent" || e.reason === "pin_invalid" ? e.reason : null;
    }
    // Only the ssh binary. A missing git binary is not a pin fault.
    if (e.code === "ENOENT" && e.syscall === "spawn ssh") return "ssh_client_absent";
    if (via === "ssh" && e.code === 255 && typeof e.stderr === "string" && SSH_HOST_KEY_MISMATCH.test(e.stderr)) {
      return "host_key_mismatch";
    }
    return null;
  } catch {
    // review: swallowed — null falls through to the caller's Error-path report, so the
    // failure still reaches Sentry; only the pin-fault classification is lost.
    return null;
  }
}

/**
 * Pseudonymised or non-identifying values only: the caller hashes every identifier itself
 * (`userIdHash`, `workspaceIdHash`, …), so a raw `userId` cannot be passed — the pino-only
 * fallback below has no emit boundary to hash it at.
 */
export type GitDataPinFaultExtra = Readonly<Record<string, string | number>> & { readonly userId?: never };

/**
 * Report a git-data pin fault on Sentry's message path with the `pin_fault` tag, and copy
 * the reason into `extra.pinFault` (the pino line carries `extra`, not tags, so Better
 * Stack sees the reason too). The only writer of the `pin_fault` tag in the app.
 *
 * Never throws: it runs inside callers' catch blocks, where a throw would replace the
 * error being reported and skip the caller's rethrow.
 */
export function reportGitDataPinFault(
  reason: GitDataPinFault,
  site: { feature: string; op: string; message: string; extra?: GitDataPinFaultExtra },
): void {
  const extra = { ...site.extra, pinFault: reason };
  let reported = false;
  try {
    Sentry.withIsolationScope((scope) => {
      scope.clearBreadcrumbs();
      reported = true;
      reportSilentFallback(null, {
        feature: site.feature,
        op: site.op,
        message: site.message,
        tags: { pin_fault: reason },
        extra,
      });
    });
  } catch {
    // review: swallowed — if the scope could not be opened (an uninitialized Sentry
    // namespace in a dev bundle), the fault still reaches pino and Better Stack below. It
    // is NOT captured in the ambient scope: that event would carry other sessions'
    // breadcrumbs. If the report itself threw, it already logged or never can; stop.
    if (reported) return;
    try {
      logger.error({ feature: site.feature, op: site.op, ...extra }, site.message);
    } catch {
      // review: swallowed — nothing left to report through.
    }
  }
}
