// TR9 PR-4 (#4235) — TS unit tests for the pure manifest-diff module.
//
// Ported from the deleted bash contract test at
// apps/web-platform/test/github-app-manifest-drift-guard.test.ts
// (which spawned bin/diff-github-app-manifest.sh + jq). Both the script
// and that contract test were retired in PR-4 once the diff was reimplemented
// in TS so the Next.js container could run drift-check without subprocess.
//
// Six-case matrix preserved verbatim; case 7 (per-installation synthesis)
// is the #4179 contract.

import { describe, test, expect } from "vitest";
import {
  diffGithubAppManifest,
  type ManifestDiffResult,
} from "@/server/github/manifest-diff";

describe("diffGithubAppManifest", () => {
  test("case 1: permission match -> ok", () => {
    const result = diffGithubAppManifest(
      {
        default_permissions: { administration: "write", contents: "read" },
        default_events: ["push"],
      },
      {
        permissions: { administration: "write", contents: "read" },
        events: ["push"],
      },
    );
    expect(result.kind).toBe("ok");
  });

  test("case 2: manifest administration:write, live administration:read -> permission_drift with scope_diff", () => {
    const result = diffGithubAppManifest(
      {
        default_permissions: { administration: "write" },
        default_events: [],
      },
      {
        permissions: { administration: "read" },
        events: [],
      },
    );
    expect(result.kind).toBe("permission_drift");
    if (result.kind !== "permission_drift") return;
    const parsed = JSON.parse(result.detail) as {
      scope_diff: Array<{ key: string; manifest: string; live: string }>;
    };
    expect(parsed.scope_diff).toContainEqual({
      key: "administration",
      manifest: "write",
      live: "read",
    });
  });

  test("case 3: live has events:[repository_dispatch] not in manifest -> permission_unexpected_grant", () => {
    const result = diffGithubAppManifest(
      {
        default_permissions: { metadata: "read" },
        default_events: [],
      },
      {
        permissions: { metadata: "read" },
        events: ["repository_dispatch"],
      },
    );
    expect(result.kind).toBe("permission_unexpected_grant");
    if (result.kind !== "permission_unexpected_grant") return;
    const parsed = JSON.parse(result.detail) as { extra_events: string[] };
    expect(parsed.extra_events).toContain("repository_dispatch");
  });

  test("case 4: response {message:'Not Found'} -> response_shape_unparseable", () => {
    const result = diffGithubAppManifest(
      {
        default_permissions: { metadata: "read" },
        default_events: [],
      },
      { message: "Not Found" } as unknown as { permissions?: unknown; events?: unknown },
    );
    expect(result.kind).toBe("response_shape_unparseable");
    if (result.kind !== "response_shape_unparseable") return;
    // Mirrors bash detail text exactly: keys absent -> "missing".
    expect(result.detail).toContain("response.permissions=missing");
    expect(result.detail).toContain("response.events=missing");
  });

  test("case 5: empty arrays both sides -> ok", () => {
    const result = diffGithubAppManifest(
      {
        default_permissions: {},
        default_events: [],
      },
      {
        permissions: {},
        events: [],
      },
    );
    expect(result.kind).toBe("ok");
  });

  test("case 6: same array content, different ordering -> ok (sorted before compare)", () => {
    const result = diffGithubAppManifest(
      {
        default_permissions: { contents: "read", metadata: "read" },
        default_events: ["push", "pull_request"],
      },
      {
        permissions: { metadata: "read", contents: "read" },
        events: ["pull_request", "push"],
      },
    );
    expect(result.kind).toBe("ok");
  });

  test("case 7: per-installation synthesis (#4179) — flat {permissions, events} object diffs against manifest's default_*", () => {
    const manifest = {
      default_permissions: { contents: "write", metadata: "read" },
      default_events: [],
    };

    // Install #1 matches manifest exactly.
    const install1Result = diffGithubAppManifest(manifest, {
      permissions: { contents: "write", metadata: "read" },
      events: [],
    });
    expect(install1Result.kind).toBe("ok");

    // Install #2 lacks `contents` -> permission_drift (missing in live).
    const install2Result = diffGithubAppManifest(manifest, {
      permissions: { metadata: "read" },
      events: [],
    });
    expect(install2Result.kind).toBe("permission_drift");
    if (install2Result.kind !== "permission_drift") return;
    const parsed = JSON.parse(install2Result.detail) as {
      missing_perms: Record<string, string>;
    };
    expect(parsed.missing_perms.contents).toBe("write");
  });

  test("precedence: permission_drift wins when both drift AND extra grant present", () => {
    // Manifest has `contents:read`; live has `contents:write` (drift direction
    // since manifest declared X and live diverges) + `extra:read` (extra grant).
    // permission_drift should fire (security-regression direction takes precedence).
    const result: ManifestDiffResult = diffGithubAppManifest(
      {
        default_permissions: { contents: "read" },
        default_events: [],
      },
      {
        permissions: { contents: "write", extra: "read" },
        events: [],
      },
    );
    expect(result.kind).toBe("permission_drift");
  });
});
