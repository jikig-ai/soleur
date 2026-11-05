/**
 * #12011 PR-D: the verify route reads its token through lib/internal-auth-named.ts (a closed-union name), and
 * lib/internal-auth.ts stays untouched (it is a CLO-bound census path, discharged at sha 8c77db1).
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { readInternalBearerSecret } from "@/lib/internal-auth";
import { readNamedBearerSecret } from "@/lib/internal-auth-named";

const WEB = path.join(__dirname, "../..");
const REPO = path.join(WEB, "../..");

afterEach(() => vi.unstubAllEnvs());

describe("readNamedBearerSecret", () => {
  it("reads LEGAL_ACCEPTANCE_VERIFY_TOKEN and never falls back to the Inngest secret", () => {
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", "inngest-fixture");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "verify-fixture");
    expect(readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN")).toBe("verify-fixture");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    expect(readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN")).toBeNull();
    expect(readInternalBearerSecret()).toBe("inngest-fixture");
  });

  it("an unset value is null", () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    expect(readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN")).toBeNull();
  });

  it("the name is a closed union (a free string, and the Inngest secret name, do not type-check)", () => {
    // @ts-expect-error not a member of NamedBearerSecretName
    readNamedBearerSecret("SUPABASE_SERVICE_ROLE_KEY");
    // @ts-expect-error the Inngest secret is read by readInternalBearerSecret, not by the named reader
    readNamedBearerSecret("INNGEST_MANUAL_TRIGGER_SECRET");
  });
});

describe("readInternalBearerSecret (unchanged by this PR)", () => {
  it("takes no argument and reads INNGEST_MANUAL_TRIGGER_SECRET (the existing callers pass none)", () => {
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", "inngest-fixture");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "verify-fixture");
    expect(readInternalBearerSecret()).toBe("inngest-fixture");
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", "");
    expect(readInternalBearerSecret()).toBeNull();
  });
});

describe("the CLO-bound census path lib/internal-auth.ts", () => {
  const SRC = readFileSync(path.join(WEB, "lib/internal-auth.ts"), "utf8");
  it("does not know the status token (it lives in internal-auth-named.ts)", () => {
    expect(SRC).not.toMatch(/LEGAL_ACCEPTANCE/);
    expect(SRC).not.toMatch(/InternalBearerSecretName/);
  });
  it("is byte-identical to the CLO-discharged sha (8c77db1) when that commit is reachable", () => {
    let discharged: string;
    try {
      discharged = execFileSync("git", ["show", "8c77db1:apps/web-platform/lib/internal-auth.ts"], {
        cwd: REPO,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
    } catch {
      return; // shallow clone: the CI gate is `git diff --quiet 8c77db1 HEAD -- CENSUS_PATHS` in home-census-trigger.sh
    }
    expect(SRC).toBe(discharged);
  });
});

describe("every caller of the status token goes through the named reader", () => {
  it("the verify route imports readNamedBearerSecret and not readInternalBearerSecret", () => {
    const route = readFileSync(path.join(WEB, "app/api/internal/legal-acceptance/[key]/route.ts"), "utf8");
    expect(route).toMatch(/readNamedBearerSecret\(\s*"LEGAL_ACCEPTANCE_VERIFY_TOKEN"\s*\)/);
    expect(route).not.toMatch(/readInternalBearerSecret/);
  });
});
