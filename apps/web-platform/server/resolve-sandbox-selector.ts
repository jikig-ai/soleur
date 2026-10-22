import { readAgentSandboxUnixDenyDetailed } from "@/lib/feature-flags/server";

/** Budget for the runtime synthetic's cold, one-shot read. The dispatcher's hot path races the same read against
 *  `RESOLVE_TIMEOUT_MS` (300 ms); a fresh process has no warm client and routinely loses that race, so the CLI waits long enough
 *  for the SDK's 200 ms first attempt, its 1 s retry delay and a second attempt (there is no hot path here). */
export const CLI_RESOLVE_BUDGET_MS = 3000;

export type SelectorSentinel = "base" | "unixdeny" | "unresolved";

/**
 * Which seccomp artifact would a NO-EGRESS session get right now, as the runtime Bash synthetic needs it (#10455 b).
 * `unixdeny` / `base` only when Flagsmith ANSWERED; `unresolved` when the read fell back to the container's env mirror
 * (lib/feature-flags/server.ts `fellBack`), threw, or lost the race against `budgetMs`. The synthetic then skips the run
 * (`no_ping reason=selector_unresolved`) instead of probing a guessed artifact and pinging green for the wrong one.
 */
export async function selectorSentinel(
  read: () => Promise<{ value: boolean; fellBack: boolean }> = readAgentSandboxUnixDenyDetailed,
  budgetMs: number = CLI_RESOLVE_BUDGET_MS,
): Promise<SelectorSentinel> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("agent-sandbox-unix-deny flag read timed out")), budgetMs);
    });
    const r = await Promise.race([read(), timeout]);
    if (r.fellBack) return "unresolved";
    return r.value === true ? "unixdeny" : "base";
  } catch {
    return "unresolved";
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
