import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, it, expect } from "vitest";

// Severity-by-cause contract test for the stream-replay resume handler
// (#5290 / ADR-059 false-positive remediation).
//
// Unlike the kb-db-error / kb-sync op-contract tests, there is NO Terraform
// Sentry issue-alert keyed on `op=ownership-mismatch` or `feature=stream-replay`
// (premise-validated: `git grep` over apps/web-platform/infra/sentry/ returns
// zero). So the durable drift-guard here is the EMIT-SIDE severity contract:
// the genuine-attack causes MUST stay error-level (`reportSilentFallback`) and
// the benign reconnect race MUST stay at warning (`warnSilentFallback`). A
// future edit that downgrades a genuine cause to warning/info — re-burying a
// real cross-user/cross-repo attempt under benign-race noise — fails THIS test.
//
// Source-grep (not AST): each emit is a contiguous block with the op + cause as
// inline string literals. A windowed regex over the helper-call site is
// sufficient and needs no TS resolution (mirrors the substring approach in
// sentry-kb-db-error-alert-op-contract.test.ts).

const here = dirname(fileURLToPath(import.meta.url));
const wsHandler = readFileSync(join(here, "../server/ws-handler.ts"), "utf8");
const currentRepoUrl = readFileSync(
  join(here, "../server/current-repo-url.ts"),
  "utf8",
);

// A helper invocation followed (within a bounded window) by the given cause
// literal. `[\s\S]{0,400}?` is non-greedy so it stays inside one call's option
// object — the emit blocks here are well under 400 chars.
function emitsAt(
  src: string,
  helper: "reportSilentFallback" | "warnSilentFallback" | "infoSilentFallback",
  cause: string,
): boolean {
  return new RegExp(
    `${helper}\\([\\s\\S]{0,400}?cause:\\s*"${cause}"`,
  ).test(src);
}

function causeCount(src: string, cause: string): number {
  return (src.match(new RegExp(`cause:\\s*"${cause}"`, "g")) ?? []).length;
}

describe("stream-replay resume handler — severity-by-cause op contract (#5290)", () => {
  it("declares both stable op slugs at the emit site (no rename darks a future alert)", () => {
    expect(wsHandler).toContain('op: "ownership-mismatch"');
    expect(wsHandler).toContain('op: "repo-scope-mismatch"');
    expect(wsHandler).toContain('feature: "stream-replay"');
  });

  // --- Genuine causes MUST stay LOUD (error level / reportSilentFallback) ---

  // Each cause literal must appear EXACTLY ONCE so the windowed `emitsAt`
  // match cannot be satisfied from a duplicate emit in the wrong helper block
  // (defends the 400-char window against a future second emit of the same cause).
  it("each cause literal is emitted exactly once (no duplicate-block window bypass)", () => {
    expect(causeCount(wsHandler, "db-error")).toBe(1);
    expect(causeCount(wsHandler, "not-materialized")).toBe(1);
    expect(causeCount(wsHandler, "url-differs")).toBe(1);
  });

  it("genuine DB error (cause=db-error) stays at ERROR level", () => {
    expect(
      emitsAt(wsHandler, "reportSilentFallback", "db-error"),
      "db-error must be emitted via reportSilentFallback (error level)",
    ).toBe(true);
    // Fail closed: a future downgrade to warning/info re-buries genuine DB errors.
    expect(
      emitsAt(wsHandler, "warnSilentFallback", "db-error"),
      "db-error must NOT be downgraded to warning — would re-bury genuine DB errors",
    ).toBe(false);
    expect(
      emitsAt(wsHandler, "infoSilentFallback", "db-error"),
      "db-error must NOT be downgraded to info",
    ).toBe(false);
  });

  it("genuine cross-repo mismatch (cause=url-differs) stays at ERROR level", () => {
    expect(
      emitsAt(wsHandler, "reportSilentFallback", "url-differs"),
      "url-differs must be emitted via reportSilentFallback (error level)",
    ).toBe(true);
    expect(
      emitsAt(wsHandler, "warnSilentFallback", "url-differs"),
      "url-differs must NOT be downgraded to warning — would silence a real cross-repo replay attempt",
    ).toBe(false);
    expect(
      emitsAt(wsHandler, "infoSilentFallback", "url-differs"),
      "url-differs must NOT be downgraded to info",
    ).toBe(false);
  });

  // --- Benign race MUST stay at WARNING (de-noised, but observable) ---

  it("benign deferred race (cause=not-materialized) is at WARNING level (not error, not silenced)", () => {
    expect(
      emitsAt(wsHandler, "warnSilentFallback", "not-materialized"),
      "not-materialized must be emitted via warnSilentFallback (warning level)",
    ).toBe(true);
    // Not escalated back to error (would recreate the flood)…
    expect(
      emitsAt(wsHandler, "reportSilentFallback", "not-materialized"),
      "not-materialized must NOT be escalated to error — would recreate the false-positive flood",
    ).toBe(false);
    // …and not silenced below warning (it still covers a genuine owned-by-
    // another row pre-enumeration; AC14 gates the escalation decision).
    expect(
      emitsAt(wsHandler, "infoSilentFallback", "not-materialized"),
      "not-materialized must NOT be silenced to info — it still covers genuine owned-by-another rows",
    ).toBe(false);
  });

  // --- Upstream transient-null tenant-mint blip is WARNING, query-error error ---

  it("current-repo-url tenant-mint blip is WARNING; the query-error path stays ERROR", () => {
    // The tenant-mint RuntimeAuthError path (highest-volume false-positive
    // contributor) is downgraded to warning.
    expect(currentRepoUrl).toMatch(
      /warnSilentFallback\([\s\S]{0,200}?op:\s*"read-current-repo-url\.tenant-mint"/,
    );
    // The genuine workspaces-query error path remains error-level.
    expect(currentRepoUrl).toMatch(
      /reportSilentFallback\([\s\S]{0,200}?op:\s*"read-current-repo-url"/,
    );
  });
});
