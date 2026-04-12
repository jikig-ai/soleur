import fs from "fs";
import path from "path";
import matter from "gray-matter";
import { isPathInWorkspace } from "./sandbox";

const MAX_FILE_SIZE = 1024 * 1024; // 1MB
const MAX_QUERY_LENGTH = 200;
const MAX_SEARCH_RESULTS = 100;

// --- Types ---

export interface TreeNode {
  name: string;
  type: "file" | "directory";
  path?: string;
  modifiedAt?: string;
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

// Search only indexes .md files — binary files are not text-searchable.
// This is intentional even though buildTree now includes all file types.
async function collectMdFiles(
  dir: string,
  relativeTo: string,
): Promise<string[]> {
  const files: string[] = [];
  let entries: fs.Dirent[];
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch {
    return files;
  }
  const dirPromises: Promise<string[]>[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      dirPromises.push(collectMdFiles(fullPath, relativeTo));
    } else if (entry.isFile() && !entry.isSymbolicLink() && entry.name.endsWith(".md")) {
      files.push(path.relative(relativeTo, fullPath));
    }
  }
  const nestedResults = await Promise.all(dirPromises);
  for (const nested of nestedResults) {
    files.push(...nested);
  }
  return files;
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
  const filePromises: Promise<TreeNode>[] = [];

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
      // The .md filter was removed to support file uploads (images, PDFs, etc.).
      // All file types are included in the tree; search remains .md-only.
      const ext = path.extname(entry.name);
      filePromises.push(
        fs.promises
          .stat(fullPath)
          .then((stat) => stat.mtime.toISOString())
          .catch(() => undefined)
          .then((modifiedAt) => ({
            name: entry.name,
            type: "file" as const,
            path: path.relative(effectiveTopRoot, fullPath),
            modifiedAt,
            extension: ext || undefined,
          })),
      );
    }
  }

  const [dirResults, fileNodes] = await Promise.all([
    Promise.all(dirPromises),
    Promise.all(filePromises),
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

  if (stat.size > MAX_FILE_SIZE) {
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
  const mdFiles = await collectMdFiles(kbRoot, kbRoot);

  // Flat-parallel: every file is read concurrently via Promise.all, unlike collectMdFiles
  // and buildTree which use tree-recursive parallelism (bounded by directory depth).
  // For very large KBs (10,000+ files), this is the first bottleneck — apply p-limit here.
  const searchResults = await Promise.all(
    mdFiles.map(async (relativePath): Promise<SearchResult | null> => {
      const fullPath = path.join(kbRoot, relativePath);
      let raw: string;
      try {
        const stat = await fs.promises.stat(fullPath);
        if (stat.size > MAX_FILE_SIZE) return null;
        raw = await fs.promises.readFile(fullPath, "utf-8");
      } catch {
        return null;
      }

      // Created per-callback to avoid lastIndex contention across concurrent callbacks.
      // Do not hoist — RegExp with /g flag is stateful and shared instances would skip matches.
      const regex = new RegExp(escapedQuery, "gi");
      const lines = raw.split("\n");
      const matches: SearchMatch[] = [];

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        let match: RegExpExecArray | null;
        regex.lastIndex = 0;
        while ((match = regex.exec(line)) !== null) {
          matches.push({
            line: i + 1,
            text: line,
            highlight: [match.index, match.index + match[0].length],
          });
        }
      }

      if (matches.length > 0) {
        const { frontmatter } = parseFrontmatter(raw);
        return { path: relativePath, frontmatter, matches };
      }
      return null;
    }),
  );

  const results = searchResults.filter(
    (r): r is SearchResult => r !== null,
  );

  // Sort by match count descending
  results.sort((a, b) => b.matches.length - a.matches.length);

  const total = results.length;
  return {
    results: results.slice(0, MAX_SEARCH_RESULTS),
    total,
  };
}
