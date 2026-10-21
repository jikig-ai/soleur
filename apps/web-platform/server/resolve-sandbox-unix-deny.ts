import { isAgentSandboxUnixDenyEnabled } from "@/lib/feature-flags/server";
import { mirrorWarnWithDebounce } from "./observability";

/**
 * Upper bound on ONE resolution. The SDK's first flag-read attempt aborts at 200 ms; waiting longer than ~300 ms only
 * waits for its 1 s retry delay, so the bound is 300 ms (was 2 s). A degraded flag service therefore costs a turn at
 * most this much, and only once per `MEMO_TTL_MS` window (see below), not once per turn.
 */
export const RESOLVE_TIMEOUT_MS = 300;

/** How long a resolved value (true, false, or the false of a failed read) is reused. Same horizon as the flag cache. */
export const MEMO_TTL_MS = 30_000;

let memo: { value: boolean; at: number } | null = null;
let inflight: Promise<boolean> | null = null;

/** Test seam: drop the memo and any in-flight read so tests do not leak state into each other. */
export function __resetResolveMemoForTests(): void {
  memo = null;
  inflight = null;
}

async function resolveOnce(timeoutMs: number): Promise<boolean> {
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

/**
 * Resolve the runtime flag `agent-sandbox-unix-deny` for a query being built (#10455 a).
 *
 * Fail-closed ONLY for this resolver's own failures: the result is `true` only when `isAgentSandboxUnixDenyEnabled()`
 * answers exactly `true`. A thrown error or a timeout of THIS race resolves `false` (the base artifact = today's
 * posture) with one debounced warning. That is not the same as "a failed Flagsmith read resolves OFF": when the
 * Flagsmith read itself fails INSIDE `isAgentSandboxUnixDenyEnabled`, it falls back to the container's runtime-env
 * mirror (`FLAG_AGENT_SANDBOX_UNIX_DENY`, see `runtimeEnvFallback` in lib/feature-flags/server.ts), which can be ON.
 * The flag is global (anonymous identity), so a flip reaches the NEXT query; a live query keeps the artifact it was
 * spawned with.
 *
 * Hot path (awaited before a query is built): the answer is memoised for `MEMO_TTL_MS` and CONCURRENT callers share
 * one read, so a degraded flag service delays at most the first caller per window by `timeoutMs`, and a failed read is
 * negative-cached (false) for the same window. Consequence for a flip: it reaches new queries after the memo window
 * on top of the flag service's own cache.
 */
export async function resolveSandboxUnixDeny(timeoutMs: number = RESOLVE_TIMEOUT_MS): Promise<boolean> {
  if (memo) {
    // `age >= 0`: a backward wall-clock step (NTP slew/step) must not hold a memo for longer than MEMO_TTL_MS.
    const age = Date.now() - memo.at;
    if (age >= 0 && age < MEMO_TTL_MS) return memo.value;
  }
  if (inflight) return inflight;
  const read = resolveOnce(timeoutMs)
    .then((value) => {
      memo = { value, at: Date.now() };
      return value;
    })
    .finally(() => {
      if (inflight === read) inflight = null;
    });
  inflight = read;
  return read;
}
