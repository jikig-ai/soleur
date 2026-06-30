import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// #5733 AC6 — the never-destroy-a-populated-`.git` invariant is structural: this
// PR adds a host `rev-parse` confirm + an honest-block for a populated-corrupt
// `dir-valid`, and MUST NOT add a third `.git`-targeting `rm`. A populated
// `dir-valid` satisfies neither destroy fingerprint (`isStrandingFilePointer` /
// `isEmptyCorruptGitDir`), so it can only hit the `:207` no-op or the honest
// block — never an `rm`. This is a write-boundary sentinel sweep
// (`hr-write-boundary-sentinel-sweep-all-write-sites`): assert exactly TWO
// `.git`-targeting `rm` sites remain, scoped to `.git` paths so the tmp-clone
// cleanup `rm(tmp, …)` is correctly excluded.
describe("ensure-workspace-repo destroy boundary (#5733 AC6)", () => {
  const source = readFileSync(
    join(__dirname, "..", "..", "server", "ensure-workspace-repo.ts"),
    "utf8",
  );

  it("has exactly TWO `.git`-targeting `rm` sites (the stale-pointer FILE + the empty-corrupt dir)", () => {
    // Match `rm(` whose first argument resolves the workspace `.git` path. The
    // tmp-clone cleanup `rm(tmp, …)` does NOT target `.git`, so it is excluded.
    const gitTargetingRm = source.match(
      /rm\(\s*join\(\s*workspacePath\s*,\s*"\.git"\s*\)/g,
    );
    expect(gitTargetingRm).not.toBeNull();
    expect(gitTargetingRm).toHaveLength(2);
  });

  it("the total `rm(` count is 3 (two `.git` + one tmp-clone cleanup) — no destroy site was added unscoped", () => {
    const allRm = source.match(/\brm\(/g) ?? [];
    expect(allRm).toHaveLength(3);
  });

  it("each `.git` `rm` is positively fingerprint-gated (isStrandingFilePointer / isEmptyCorruptGitDir), never the negation of validity", () => {
    // The populated-corrupt `dir-valid` honest-block must NEVER reach an `rm`.
    // Both destroy sites are guarded by a POSITIVE fingerprint, not `!isValid…`.
    expect(source).toMatch(/isStrandingFilePointer\(probeGitWorktreeShape/);
    expect(source).toMatch(/isEmptyCorruptGitDir\(workspacePath\)/);
  });
});
