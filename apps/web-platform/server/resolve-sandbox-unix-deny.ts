import { isAgentSandboxUnixDenyEnabled } from "@/lib/feature-flags/server";
import { mirrorWarnWithDebounce } from "./observability";

/** Upper bound on the resolution: a hung flag read must not delay a turn start. */
export const RESOLVE_TIMEOUT_MS = 2000;

/**
 * Resolve the runtime flag `agent-sandbox-unix-deny` for a query being built (#10455 a).
 *
 * FAIL-CLOSED TO OFF: the result is `true` only when the flag service answers exactly `true`. A thrown
 * error, a timeout, a missing flag or an absent flag service all resolve `false` (the base artifact =
 * today's posture) with one debounced warning. The flag is global (anonymous identity), so a flip
 * reaches the NEXT query; a live query keeps the artifact it was spawned with.
 */
export async function resolveSandboxUnixDeny(timeoutMs: number = RESOLVE_TIMEOUT_MS): Promise<boolean> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("agent-sandbox-unix-deny flag resolve timed out")), timeoutMs);
    });
    const v = await Promise.race([isAgentSandboxUnixDenyEnabled(), timeout]);
    return v === true;
  } catch (err) {
    mirrorWarnWithDebounce(
      err,
      {
        feature: "agent-sandbox",
        op: "unix-deny-flag-unresolved",
        message: "agent-sandbox-unix-deny flag unresolved; using the base seccomp artifact for this query",
      },
      "global",
      "agent-sandbox-unix-deny-unresolved",
    );
    return false;
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
