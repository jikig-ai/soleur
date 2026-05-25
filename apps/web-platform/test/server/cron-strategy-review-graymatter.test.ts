import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below, including the chain
// `cron-strategy-review` → `client` → startup throw. The client checks
// NEXT_PHASE === "phase-production-build" to short-circuit the env checks
// (same path Next.js's `next build` uses).
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import matter from "gray-matter";
import {
  coerceFrontmatterDate,
  collectStrategyFiles,
  parseISODate,
} from "@/server/inngest/functions/cron-strategy-review";

// Lock the contract that the multi-agent review caught:
// gray-matter parses YAML 1.1, which coerces unquoted ISO dates
// (`last_reviewed: 2026-05-25`) into JavaScript `Date` objects, NOT strings.
// Hand-mocking `{ data: { last_reviewed: "2026-05-25" } }` masks the trap
// because String(Date) is a no-op on a string. Every test below uses REAL
// `matter()` against literal YAML so a regression to `String(rawDate)` would
// re-fail. See `knowledge-base/project/learnings/2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md`.

describe("coerceFrontmatterDate — gray-matter YAML 1.1 contract", () => {
  it("normalises unquoted YAML date (the production shape) to YYYY-MM-DD", () => {
    const raw = "---\nlast_reviewed: 2026-05-25\nreview_cadence: weekly\n---\nbody";
    const parsed = matter(raw);
    // Assert the trap is real: gray-matter DOES coerce to Date.
    expect(parsed.data.last_reviewed).toBeInstanceOf(Date);
    // Assert the fix: coerceFrontmatterDate normalises back to ISO string.
    expect(coerceFrontmatterDate(parsed.data.last_reviewed)).toBe("2026-05-25");
  });

  it("passes through quoted YAML strings unchanged", () => {
    const raw = '---\nlast_reviewed: "2026-05-25"\n---\nbody';
    const parsed = matter(raw);
    expect(typeof parsed.data.last_reviewed).toBe("string");
    expect(coerceFrontmatterDate(parsed.data.last_reviewed)).toBe("2026-05-25");
  });

  it("returns undefined for missing fields", () => {
    const raw = "---\nreview_cadence: weekly\n---\nbody";
    const parsed = matter(raw);
    expect(coerceFrontmatterDate(parsed.data.last_reviewed)).toBeUndefined();
  });

  it("returns undefined for explicit null", () => {
    const raw = "---\nlast_reviewed: null\n---\nbody";
    const parsed = matter(raw);
    expect(coerceFrontmatterDate(parsed.data.last_reviewed)).toBeUndefined();
  });

  it("returns undefined for an invalid Date object", () => {
    expect(coerceFrontmatterDate(new Date("not-a-date"))).toBeUndefined();
  });

  it("returns the raw string for unrecognized non-Date shapes (so parseISODate routes them into the errors++ branch)", () => {
    // Arbitrary non-date string in last_reviewed — bash's `date -d` would fail.
    const result = coerceFrontmatterDate("definitely not a date");
    expect(result).toBe("definitely not a date");
    expect(parseISODate(result!)).toBeNull();
  });

  it("integration: full pipe from gray-matter Date through parseISODate yields a valid epoch", () => {
    const raw = "---\nlast_reviewed: 2026-05-25\n---\nbody";
    const parsed = matter(raw);
    const normalized = coerceFrontmatterDate(parsed.data.last_reviewed);
    expect(normalized).toBe("2026-05-25");
    const epoch = parseISODate(normalized!);
    expect(epoch).not.toBeNull();
    // Sanity-check: 2026-05-25 UTC midnight in unix ms.
    expect(new Date(epoch!).toISOString()).toBe("2026-05-25T00:00:00.000Z");
  });
});

describe("collectStrategyFiles — file discovery contract", () => {
  it("discovers .md files in STRATEGY_DIRS and skips symlinks (security hardening)", async () => {
    const root = await mkdtemp(join(tmpdir(), "cron-strategy-test-"));
    try {
      // Synthesize a minimal strategy tree.
      const productDir = join(root, "knowledge-base", "product");
      const marketingDir = join(root, "knowledge-base", "marketing");
      await mkdir(productDir, { recursive: true });
      await mkdir(marketingDir, { recursive: true });
      const realFile = join(productDir, "roadmap.md");
      await writeFile(
        realFile,
        "---\nreview_cadence: weekly\nlast_reviewed: 2026-05-25\n---\nbody\n",
      );
      const otherReal = join(marketingDir, "content-strategy.md");
      await writeFile(otherReal, "---\nreview_cadence: weekly\n---\nbody\n");
      // Plant a symlink pointing to /etc/passwd — handler must skip it
      // (lstat + isSymbolicLink guard from the security-sentinel finding).
      const malicious = join(productDir, "leak.md");
      try {
        await symlink("/etc/passwd", malicious);
      } catch {
        // Some test environments may not allow symlink creation; skip the
        // assertion silently in that case.
      }
      // Plant a non-.md file — should be filtered.
      await writeFile(join(productDir, "notes.txt"), "ignore me");

      const found = await collectStrategyFiles(root);
      const basenames = found.map((p) => p.split("/").slice(-2).join("/")).sort();
      expect(basenames).toContain("product/roadmap.md");
      expect(basenames).toContain("marketing/content-strategy.md");
      // The symlink must NOT be discovered.
      expect(basenames).not.toContain("product/leak.md");
      // The .txt file must NOT be discovered.
      expect(basenames.every((n) => n.endsWith(".md"))).toBe(true);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("silently skips missing strategy directories (matches bash `find ... 2>/dev/null` behavior)", async () => {
    const root = await mkdtemp(join(tmpdir(), "cron-strategy-test-empty-"));
    try {
      // No knowledge-base/ tree at all.
      const found = await collectStrategyFiles(root);
      expect(found).toEqual([]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("parseISODate — strict-YYYY-MM-DD contract (matches bash `date -d` failure path for non-strict)", () => {
  it("accepts canonical YYYY-MM-DD", () => {
    expect(parseISODate("2026-05-25")).toBe(Date.UTC(2026, 4, 25));
  });

  it("rejects ISO with timezone", () => {
    expect(parseISODate("2026-05-25T00:00:00Z")).toBeNull();
  });

  it("rejects forward-slash forms", () => {
    expect(parseISODate("2026/05/25")).toBeNull();
  });

  it("rejects two-digit-year shorthand", () => {
    expect(parseISODate("26-05-25")).toBeNull();
  });

  it("rejects empty string", () => {
    expect(parseISODate("")).toBeNull();
  });
});
