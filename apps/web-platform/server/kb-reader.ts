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
    const parsed = matter(raw, { engines: {} });
    return {
      frontmatter:
        parsed.data && Object.keys(parsed.data).length > 0
          ? parsed.data
          : {},
      content: parsed.content.trim(),
    };
  } catch {
    // Malformed YAML — return content without frontmatter
    // Strip the frontmatter block manually if present
    const stripped = raw.replace(/^---[\s\S]*?---\n*/, "").trim();
    return { frontmatter: {}, content: stripped || raw.trim() };
  }
}

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
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const nested = await collectMdFiles(fullPath, relativeTo);
      files.push(...nested);
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      files.push(path.relative(relativeTo, fullPath));
    }
  }
  return files;
}

// --- Public API ---

export async function buildTree(kbRoot: string): Promise<TreeNode> {
  const rootName = path.basename(kbRoot);
  const root: TreeNode = { name: rootName, type: "directory", children: [] };

  let entries: fs.Dirent[];
  try {
    entries = await fs.promises.readdir(kbRoot, { withFileTypes: true });
  } catch {
    return root;
  }

  const dirs: TreeNode[] = [];
  const fileNodes: TreeNode[] = [];

  for (const entry of entries) {
    const fullPath = path.join(kbRoot, entry.name);
    if (entry.isDirectory()) {
      const child = await buildTree(fullPath);
      child.name = entry.name;
      // Exclude empty directories
      if (child.children && child.children.length > 0) {
        dirs.push(child);
      }
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      // Compute path relative to the top-level KB root
      const kbTopRoot = kbRoot.includes("knowledge-base")
        ? kbRoot.substring(
            0,
            kbRoot.indexOf("knowledge-base") + "knowledge-base".length,
          )
        : kbRoot;
      fileNodes.push({
        name: entry.name,
        type: "file",
        path: path.relative(kbTopRoot, fullPath),
      });
    }
  }

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
  const regex = new RegExp(escapedQuery, "gi");
  const mdFiles = await collectMdFiles(kbRoot, kbRoot);

  const results: SearchResult[] = [];

  for (const relativePath of mdFiles) {
    const fullPath = path.join(kbRoot, relativePath);
    let raw: string;
    try {
      raw = await fs.promises.readFile(fullPath, "utf-8");
    } catch {
      continue;
    }

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
      results.push({ path: relativePath, frontmatter, matches });
    }
  }

  // Sort by match count descending
  results.sort((a, b) => b.matches.length - a.matches.length);

  const total = results.length;
  return {
    results: results.slice(0, MAX_SEARCH_RESULTS),
    total,
  };
}
