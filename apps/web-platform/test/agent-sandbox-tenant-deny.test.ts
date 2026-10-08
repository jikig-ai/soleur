// Focused tests for the CONSTANT tenant deny in `buildAgentSandboxConfig`
// (#5862 — the ADR-075 exit criterion, superseding the per-sibling
// `enumerateSiblingDenyPaths` machinery that followed #5733/PR #5848).
//
// The security contract changed shape: the deny list is now the broad PARENT
// root (`WORKSPACES_ROOT` + C4 staging + `/proc`), which the vendored CLI
// 2.1.284 bwrap builder emits as `--tmpfs <landing>` BEFORE re-binding every
// covered `allowWrite`/`allowRead` path (deny-then-restore). That ordering
// buys three properties enumeration never could:
//   - a sibling workspace created AFTER the session's namespace build is still
//     masked (the residual TOCTOU — you cannot enumerate a dir that does not
//     exist yet, but a parent tmpfs needs no enumeration),
//   - no per-dispatch `readdirSync`, no `degraded` fail-closed arm,
//   - a constant deny list: drift in the emitted set is now a diff, not a
//     function of live directory state.
// Own workspace stays read+write because the vendor re-binds `allowWrite`
// paths rw AFTER the covering tmpfs; the support (`readOnly`) persona keeps
// read access via the `allowWithinDeny` (`allowRead`) `--ro-bind` restore.

import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import * as sandboxConfig from "@/server/agent-runner-sandbox-config";

const { buildAgentSandboxConfig } = sandboxConfig;

describe("buildAgentSandboxConfig — constant tenant deny", () => {
  let root: string;
  let own: string;
  let staging: string;
  const extraDirs: string[] = [];

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-tenant-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    staging = `${root}-c4-staging`;
    mkdirSync(own);
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", staging);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    rmSync(staging, { recursive: true, force: true });
    while (extraDirs.length) {
      rmSync(extraDirs.pop()!, { recursive: true, force: true });
    }
  });

  it("the enumeration export is gone — no per-dispatch readdirSync path remains", () => {
    expect(
      (sandboxConfig as Record<string, unknown>).enumerateSiblingDenyPaths,
    ).toBeUndefined();
  });

  it("denyRead is the constant parent set regardless of which siblings exist", () => {
    mkdirSync(join(root, "00000000-0000-0000-0000-0000000000a1"));
    mkdirSync(join(root, "00000000-0000-0000-0000-0000000000b2"));
    mkdirSync(join(root, ".cron")); // infra sibling — also covered by the parent
    writeFileSync(join(root, "stray.txt"), "not a dir");

    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toEqual([root, staging, "/proc"]);
  });

  it("a sibling created AFTER the config is built is covered without appearing in denyRead", () => {
    const before = buildAgentSandboxConfig(own);
    const lateSibling = join(root, "00000000-0000-0000-0000-0000000000cc");
    mkdirSync(lateSibling);
    const after = buildAgentSandboxConfig(own);

    expect(after.filesystem.denyRead).toEqual(before.filesystem.denyRead);
    // The coverage is structural: the parent root is the deny landing, so the
    // late sibling is masked by the same `--tmpfs` — no entry needed. Pin the
    // precondition that makes "covered" non-vacuous: the sibling IS under root.
    expect(lateSibling.startsWith(`${root}/`)).toBe(true);
    expect(after.filesystem.denyRead).not.toContain(lateSibling);
    expect(after.filesystem.denyRead).toContain(root);
  });

  it("an ENOENT (unmounted) root still emits the deny entry — the vendored builder skips a landing that mounts nothing", () => {
    const missing = join(root, "vanished");
    vi.stubEnv("WORKSPACES_ROOT", missing);
    const result = buildAgentSandboxConfig(own);
    // Same constant list whether or not the root exists; the builder's
    // "mounts nothing this wrap can place (absent, …)" skip reproduces the old
    // benign-ENOENT posture with no code. In production a missing root is a
    // vanished-mount fault — reported via reportSilentFallback, not silently.
    expect(result.filesystem.denyRead).toEqual([missing, staging, "/proc"]);
  });

  it("a symlinked workspacePath does not change the deny set (no realpath classification)", () => {
    const ownLink = join(root, "own-link");
    symlinkSync(own, ownLink);
    const viaLink = buildAgentSandboxConfig(ownLink);
    const viaReal = buildAgentSandboxConfig(own);
    expect(viaLink.filesystem.denyRead).toEqual(viaReal.filesystem.denyRead);
    expect(viaLink.filesystem.allowWrite).toEqual([ownLink]);
  });

  it("workspacePath outside the root still emits the same deny set (own simply isn't covered — siblings stay masked regardless)", () => {
    const elsewhere = mkdtempSync(join(tmpdir(), "sbx-elsewhere-"));
    extraDirs.push(elsewhere);
    const result = buildAgentSandboxConfig(join(elsewhere, "own"));
    expect(result.filesystem.denyRead).toEqual([root, staging, "/proc"]);
    expect(result.filesystem.allowWrite).toEqual([join(elsewhere, "own")]);
  });

  it("refuses the catastrophic shape — workspacePath that IS or CONTAINS the deny root", () => {
    // Equal or ancestor wsPath would make the vendor's restore re-bind the
    // whole root rw after the tmpfs, unmasking every sibling. Fail loud.
    expect(() => buildAgentSandboxConfig(root)).toThrow(/equals\/contains deny root/);
    const ancestor = join(root, "..");
    expect(() => buildAgentSandboxConfig(ancestor)).toThrow(/equals\/contains deny root/);
  });

  it("denyReadExtra merges after the constant base, deduped", () => {
    const kb = join(root, "knowledge-base");
    const result = buildAgentSandboxConfig(own, {
      denyReadExtra: [kb, root], // duplicate root must collapse
    });
    expect(result.filesystem.denyRead).toEqual([root, staging, "/proc", kb]);
  });

  it("readOnly (ADR-113 support persona): no write grant, allowRead restore inside the masked parent", () => {
    const result = buildAgentSandboxConfig(own, { readOnly: true });
    expect(result.filesystem.allowWrite).toEqual([]);
    expect(result.filesystem.allowRead).toEqual([own]);
  });

  it("non-readOnly carries no allowRead key (the read-only restore stays persona-scoped)", () => {
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem).not.toHaveProperty("allowRead");
  });

  // ---- #9725: deny must cover the root workspaces ACTUALLY live under ----
  // After the ADR-068 git-data cutover, workspacePathForWorkspaceId resolves
  // under WORKTREE_ROOT — denying only WORKSPACES_ROOT would mask a directory
  // no workspace lives under while every sibling sits readable elsewhere.

  it("flag OFF: the deny set is byte-identical to the pre-cutover posture", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "false");
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toEqual([root, staging, "/proc"]);
  });

  it("flag ON: BOTH the volume root and the worktree root are denied", () => {
    const worktree = mkdtempSync(join(tmpdir(), "sbx-worktree-"));
    extraDirs.push(worktree);
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", worktree);
    const result = buildAgentSandboxConfig(join(worktree, "00000000-0000-0000-0000-000000000002"));
    expect(result.filesystem.denyRead).toEqual([root, worktree, staging, "/proc"]);
  });

  it("flag ON: worktree root that does not exist on disk is still emitted (constant list; builder skips the landing)", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", join(root, "unborn-worktree-root"));
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toEqual([
      root,
      join(root, "unborn-worktree-root"),
      staging,
      "/proc",
    ]);
  });

  it("flag ON: identical volume + worktree roots collapse to one deny entry", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", root); // same dir via env — dedupe must hold
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).toEqual([root, staging, "/proc"]);
  });

  it("flag ON: own workspace under the worktree root is still restored (deny covers siblings, not self)", () => {
    const worktree = mkdtempSync(join(tmpdir(), "sbx-worktree-"));
    extraDirs.push(worktree);
    const ownWt = join(worktree, "00000000-0000-0000-0000-000000000002");
    mkdirSync(ownWt);
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", worktree);
    const result = buildAgentSandboxConfig(ownWt);
    expect(result.filesystem.allowWrite).toEqual([ownWt]);
    expect(result.filesystem.denyRead).toContain(worktree);
  });

  it("flag ON: catastrophic guard covers EVERY deny root — workspacePath containing the worktree root refuses", () => {
    const worktree = mkdtempSync(join(tmpdir(), "sbx-worktree-"));
    extraDirs.push(worktree);
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", worktree);
    // workspacePath == the worktree root itself → vendor restore would re-bind
    // the whole masked parent rw → unmasks every tenant. Fail loud.
    expect(() => buildAgentSandboxConfig(worktree)).toThrow(/equals\/contains deny root/);
    // …and a workspacePath that CONTAINS the worktree root is the same shape.
    expect(() => buildAgentSandboxConfig(join(worktree, ".."))).toThrow(/equals\/contains deny root/);
  });

  it("a '/' or empty deny root can never enter the set (misconfigured env must not become a catastrophic mask)", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", "/");
    const result = buildAgentSandboxConfig(own);
    expect(result.filesystem.denyRead).not.toContain("/");
    expect(result.filesystem.denyRead).toContain(root);
  });
});
