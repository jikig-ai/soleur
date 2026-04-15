import fs from "fs";
import path from "path";
import matter from "gray-matter";
import { isPathInWorkspace } from "./sandbox";
import {
  KB_MAX_FILE_SIZE,
  KB_TEXT_EXTENSIONS,
  KB_UPLOAD_EXTENSIONS,
} from "@/lib/kb-constants";
const MAX_QUERY_LENGTH = 200;
const MAX_SEARCH_RESULTS = 100;
const MAX_CONCURRENT_STAT = 50;
// Bound per-file content matches: a 1MB CSV with a common token can yield
// tens of thousands of hits. Results are capped at MAX_SEARCH_RESULTS overall,
// so per-file truncation has no user-visible effect.
const MAX_MATCHES_PER_FILE = 50;

// --- Types ---

export interface TreeNode {
  name: string;
  type: "file" | "directory";
  path?: string;
  modifiedAt?: string;
  size?: number;
  extension?: string; // e.g., ".md", ".png", ".pdf"
  children?: TreeNode[];
}

export interface ContentResult {
  path: string;
  frontmatter: Record<string, unknown>;
  content: string;
}

export interface SearchMatch {
  line: number;
  text: string;
  highlight: [number, number];
}

export interface SearchResult {
  path: string;
  frontmatter: Record<string, unknown>;
  matches: SearchMatch[];
  kind: "content" | "filename";
}

// --- Errors ---

export class KbNotFoundError extends Error {
  constructor(message = "File not found") {
    super(message);
    this.name = "KbNotFoundError";
  }
}

export class KbAccessDeniedError extends Error {
  constructor(message = "Access denied") {
    super(message);
    this.name = "KbAccessDeniedError";
  }
}

export class KbValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "KbValidationError";
  }
}

// --- Helpers ---

function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Run `fn` over every item in `items` with at most `concurrency` in-flight at once. */
async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < items.length) {
      const idx = nextIndex++;
      results[idx] = await fn(items[idx]);
    }
  }

  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    () => worker(),
  );
  await Promise.all(workers);
  return results;
}

function parseFrontmatter(raw: string): {
  frontmatter: Record<string, unknown>;
  content: string;
} {
  try {
    // engines: {} disables custom YAML engines, preventing code injection
    // via gray-matter's historical JS-in-frontmatter feature (CVE in <4.0.3).
    const parsed = matter(raw, { engines: {} });
    return {
      frontmatter:
        parsed.data && Object.keys(parsed.data).length > 0
          ? parsed.data
          : {},
      content: parsed.content.trim(),
    };
  } catch {
    // Malformed YAML — return raw content without attempting to parse
    return { frontmatter: {}, content: raw.trim() };
  }
}

// Lookup sites lowercase ext before the .has check (path.extname preserves case).
const CONTENT_SEARCHABLE = new Set<string>(
  KB_TEXT_EXTENSIONS.map((e) => `.${e}`),
);
const FILENAME_SEARCHABLE = new Set<string>([
  ".md",
  ...KB_UPLOAD_EXTENSIONS.map((e) => `.${e}`),
]);

async function collectSearchableFiles(
  dir: string,
  relativeTo: string,
): Promise<{ relativePath: string; ext: string }[]> {
  const files: { relativePath: string; ext: string }[] = [];
  let entries: fs.Dirent[];
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch {
    return files;
  }
  const dirPromises: Promise<{ relativePath: string; ext: string }[]>[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    // Symlink guard on every branch: prevents enumeration escape via
    // a planted symlink pointing at /etc/ or another workspace.
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      dirPromises.push(collectSearchableFiles(fullPath, relativeTo));
    } else if (entry.isFile() && !entry.isSymbolicLink()) {
      // path.extname preserves case (.PDF !== .pdf) — must lowercase before lookup.
      const ext = path.extname(entry.name).toLowerCase();
      if (FILENAME_SEARCHABLE.has(ext)) {
        files.push({
          relativePath: path.relative(relativeTo, fullPath),
          ext,
        });
      }
    }
  }
  const nestedResults = await Promise.all(dirPromises);
  for (const nested of nestedResults) {
    files.push(...nested);
  }
  return files;
}

function matchFilename(
  relativePath: string,
  escapedQuery: string,
): SearchMatch[] {
  const basename = path.basename(relativePath);
  // Per-callback RegExp: /gi is stateful via lastIndex. Sharing a single
  // instance across concurrent Promise.all callbacks loses matches.
  // matchAll returns a fresh iterator and avoids stateful lastIndex juggling.
  const matches: SearchMatch[] = [];
  for (const found of basename.matchAll(new RegExp(escapedQuery, "gi"))) {
    const start = found.index ?? 0;
    matches.push({
      line: 0,
      text: basename,
      highlight: [start, start + found[0].length],
    });
  }
  return matches;
}

// --- Public API ---

export async function buildTree(
  kbRoot: string,
  topRoot?: string,
): Promise<TreeNode> {
  const effectiveTopRoot = topRoot ?? kbRoot;
  const rootName = path.basename(kbRoot);
  const root: TreeNode = { name: rootName, type: "directory", children: [] };

  let entries: fs.Dirent[];
  try {
    entries = await fs.promises.readdir(kbRoot, { withFileTypes: true });
  } catch {
    return root;
  }

  const dirPromises: Promise<TreeNode | null>[] = [];
  const fileEntries: { entry: fs.Dirent; fullPath: string }[] = [];

  for (const entry of entries) {
    const fullPath = path.join(kbRoot, entry.name);
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      dirPromises.push(
        buildTree(fullPath, effectiveTopRoot).then((child) => {
          child.name = entry.name;
          return child.children && child.children.length > 0 ? child : null;
        }),
      );
    } else if (entry.isFile() && !entry.isSymbolicLink()) {
      fileEntries.push({ entry, fullPath });
    }
  }

  const [dirResults, fileNodes] = await Promise.all([
    Promise.all(dirPromises),
    mapWithConcurrency(
      fileEntries,
      MAX_CONCURRENT_STAT,
      async ({ entry, fullPath }): Promise<TreeNode> => {
        const ext = path.extname(entry.name);
        const stat = await fs.promises.stat(fullPath).catch(() => null);
        return {
          name: entry.name,
          type: "file" as const,
          path: path.relative(effectiveTopRoot, fullPath),
          modifiedAt: stat?.mtime.toISOString(),
          size: stat?.size,
          extension: ext || undefined,
        };
      },
    ),
  ]);

  const dirs = dirResults.filter((d): d is TreeNode => d !== null);
  dirs.sort((a, b) => a.name.localeCompare(b.name));
  fileNodes.sort((a, b) => a.name.localeCompare(b.name));
  root.children = [...dirs, ...fileNodes];

  return root;
}

export async function readContent(
  kbRoot: string,
  relativePath: string,
): Promise<ContentResult> {
  // Null byte check (CWE-158)
  if (relativePath.includes("\0")) {
    throw new KbAccessDeniedError();
  }

  // Must be .md
  if (!relativePath.endsWith(".md")) {
    throw new KbNotFoundError("Only .md files are supported");
  }

  const fullPath = path.join(kbRoot, relativePath);

  // Path traversal check — boundary is kbRoot, not workspace root
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    throw new KbAccessDeniedError();
  }

  // File size guard
  let stat: fs.Stats;
  try {
    stat = await fs.promises.stat(fullPath);
  } catch {
    throw new KbNotFoundError();
  }

  if (!stat.isFile()) {
    throw new KbNotFoundError();
  }

  if (stat.size > KB_MAX_FILE_SIZE) {
    throw new KbValidationError("File exceeds maximum size limit");
  }

  const raw = await fs.promises.readFile(fullPath, "utf-8");
  const { frontmatter, content } = parseFrontmatter(raw);

  return { path: relativePath, frontmatter, content };
}

export async function searchKb(
  kbRoot: string,
  query: string,
): Promise<{ results: SearchResult[]; total: number }> {
  if (!query) {
    throw new KbValidationError("Search query is required");
  }

  if (query.length > MAX_QUERY_LENGTH) {
    throw new KbValidationError(
      `Search query exceeds maximum length of ${MAX_QUERY_LENGTH} characters`,
    );
  }

  const escapedQuery = escapeRegex(query);
  const files = await collectSearchableFiles(kbRoot, kbRoot);

  // For very large KBs (10,000+ files), the flat Promise.all is the first
  // bottleneck — switch to mapWithConcurrency at that point.
  const searchResults = await Promise.all(
    files.map(async (file): Promise<SearchResult | null> => {
      // Content search runs first on text-native types. Binaries (pdf/docx/images)
      // get filename-only matches until a real text-extraction pipeline lands.
      if (CONTENT_SEARCHABLE.has(file.ext)) {
        const contentResult = await searchContent(
          path.join(kbRoot, file.relativePath),
          file.relativePath,
          escapedQuery,
        );
        if (contentResult) return contentResult;
      }

      // Fallback: filename match only when content search did not hit.
      const filenameMatches = matchFilename(file.relativePath, escapedQuery);
      if (filenameMatches.length > 0) {
        return {
          path: file.relativePath,
          frontmatter: {},
          matches: filenameMatches,
          kind: "filename",
        };
      }
      return null;
    }),
  );

  const results = searchResults.filter(
    (r): r is SearchResult => r !== null,
  );

  // Filename hits never outrank content hits for the same query.
  results.sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === "content" ? -1 : 1;
    if (a.kind === "content") return b.matches.length - a.matches.length;
    return a.path.localeCompare(b.path);
  });

  const total = results.length;
  return {
    results: results.slice(0, MAX_SEARCH_RESULTS),
    total,
  };
}

async function searchContent(
  fullPath: string,
  relativePath: string,
  escapedQuery: string,
): Promise<SearchResult | null> {
  let raw: string;
  try {
    const stat = await fs.promises.stat(fullPath);
    if (stat.size > KB_MAX_FILE_SIZE) return null;
    raw = await fs.promises.readFile(fullPath, "utf-8");
  } catch {
    return null;
  }

  // Per-callback RegExp: /gi is stateful via lastIndex. matchAll returns
  // a fresh iterator so we avoid manual lastIndex juggling.
  const pattern = new RegExp(escapedQuery, "gi");
  const lines = raw.split("\n");
  const matches: SearchMatch[] = [];

  outer: for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    for (const found of line.matchAll(pattern)) {
      const start = found.index ?? 0;
      matches.push({
        line: i + 1,
        text: line,
        highlight: [start, start + found[0].length],
      });
      if (matches.length >= MAX_MATCHES_PER_FILE) break outer;
    }
  }

  if (matches.length === 0) return null;
  const { frontmatter } = parseFrontmatter(raw);
  return { path: relativePath, frontmatter, matches, kind: "content" };
}
