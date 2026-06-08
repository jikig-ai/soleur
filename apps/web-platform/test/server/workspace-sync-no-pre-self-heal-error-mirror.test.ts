import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// #4906 AC6 — regression guard for the part-2 stale-premise finding.
//
// Issue #4906 part 2 claimed `syncWorkspace` calls `reportSilentFallback`
// BEFORE the self-heal runs, so a self-healed ff-only abort still pages an
// error-level Sentry issue every push. That was already fixed by #4972/#4979:
// the `non_fast_forward` branch now records an info breadcrumb only and
// delegates escalation to `selfHealNonFastForward` (which warns on recovery,
// errors only on genuine failure).
//
// The behavioral coverage lives in kb-route-helpers.test.ts (the "de-noise"
// tests). This is a complementary NEGATIVE-SPACE source guard: it asserts the
// structural invariant directly so a future edit that re-introduces a
// pre-self-heal `reportSilentFallback` is caught even if the git-mock-based
// behavioral tests are refactored. Trimmed to the single negative assertion per
// the regex-on-source-delegation-tests learning (no positive source asserts).

const SRC = readFileSync(
  join(__dirname, "..", "..", "server", "workspace-sync.ts"),
  "utf8",
);

describe("workspace-sync — no pre-self-heal error mirror (#4906 AC6 / #4972 regression)", () => {
  it("the non_fast_forward branch delegates to selfHealNonFastForward with no reportSilentFallback before it", () => {
    const branchStart = SRC.indexOf(
      "if (errorClass === ERROR_CLASS_NON_FAST_FORWARD)",
    );
    expect(branchStart).toBeGreaterThan(-1);

    const delegationIdx = SRC.indexOf(
      "return await selfHealNonFastForward",
      branchStart,
    );
    expect(delegationIdx).toBeGreaterThan(branchStart);

    // The self-healable branch, from entry to the delegation call. A
    // `reportSilentFallback` here is the exact error-level page #4972 removed.
    const preSelfHeal = SRC.slice(branchStart, delegationIdx);
    expect(preSelfHeal).not.toContain("reportSilentFallback");
  });
});
