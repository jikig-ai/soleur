/**
 * Tombstone census machinery (#8364) — derives, from git history alone, the
 * set of public URLs that STOPPED being served under `plugins/soleur/docs/`,
 * so a guard can require each to be covered by an edge redirect, re-served by
 * a live page, or explicitly exempted.
 *
 * Event sources (all enumerated via `git log` over ALL history, never a
 * hand-maintained list):
 *   - `git log --diff-filter=RD -M --name-status` — deletions and renames.
 *   - `git log -p -G'permalink:'` — permalink VALUE changes on files: the
 *     removed-side URL set is diffed against the added-side URL set, so a
 *     reslug executed by ADDING a permalink to a previously path-derived file
 *     is caught the same as a value change or removal.
 *
 * URL derivation rules (mirror what the Eleventy build + the deleted
 * meta-refresh machinery actually served):
 *   - blog/…/YYYY-MM-DD-<slug>.md -> BOTH families: /blog/<slug> and the dated
 *                                  alias /blog/<YYYY-MM-DD-slug> (3 shapes each).
 *                                  blog.json's dir-data permalink applies at
 *                                  any depth and fileSlug strips dir+date.
 *   - blog/…/<slug>.md (undated)  -> /blog/<slug> family (3 shapes), same
 *                                  fileSlug semantics minus the dated alias
 *   - any other page file         -> its `permalink:` frontmatter (dir-style ->
 *                                  3 shapes, file-shaped -> 1 shape), or the
 *                                  Eleventy dir-slug default when absent.
 *                                  `permalink: false` emits nothing.
 *   - template permalinks ({{)    -> underivable: the event's path must carry
 *                                  a TOMBSTONE_EXEMPT entry instead
 *
 * A derived URL classifies as:
 *   live      — a page at HEAD still emits it (permalink restored, or another
 *               file now serves the path). No redirect needed.
 *   covered   — present in the declared redirect source set (literal list
 *               items + pair expansions + zone-ruleset path literals).
 *   exempt    — the event's path is in the exemption map (issue ref required).
 *   uncovered — RED. The gate prints the URL set and a paste-ready
 *               tombstone_redirect_pairs entry.
 *
 * Sharp-edge notes: git *reports* are input shapes — every `--name-status`
 * output shape (D, R###, D+A below the -M threshold, -G change) is exercised
 * by the mutation battery in redirect-tombstones.test.ts. HEAD-state
 * assertions are impossible for deleted files by definition, so per-event
 * blobs are read at <commit>^ — the last live version.
 *
 * KNOWN BLIND SPOTS (declared, not accidental — every one is a URL death the
 * census produces zero events for; covered partially by other guards):
 *   - URLs emitted via `eleventyComputed:` nested YAML, `_data/*.js` emitters,
 *     non-blog directory-data permalinks, pagination changes, or collection
 *     gating — none produce a `-Gpermalink:` col-0 event or a file event.
 *     blog.json is compensated by validate-blog-links.sh pinning its literal.
 *   - Merge-commit-only deletions: `git log --name-status`/`-p` emit no
 *     per-file diff for merge resolutions (rare under squash-merged main).
 *   - The live oracle (liveUrlPaths) is a derivation reimplementation, not a
 *     built site — it shares these blind spots on the "live" side.
 */

import { execFileSync } from "node:child_process";
import { gitFixtureEnv } from "./git-fixture-env";
import { readdirSync, readFileSync, type Dirent } from "node:fs";
import { join } from "node:path";

const PAGE_EXTS = new Set([".md", ".njk", ".html"]);
const NON_PAGE_DIRS = new Set([
  "_data",
  "_includes",
  "images",
  "css",
  "js",
  "fonts",
  "screenshots",
  "scripts",
]);
const NON_PAGE_BASENAMES = new Set([
  "CNAME",
  "robots.txt",
  "sitemap.njk",
  "llms.txt.njk",
]);

/** Is `rel` (path under the docs root) a page-emitting Eleventy input? */
export function isPageEmitting(rel: string): boolean {
  const base = rel.split("/").pop()!;
  const dot = base.lastIndexOf(".");
  const ext = dot === -1 ? "" : base.slice(dot);
  if (!PAGE_EXTS.has(ext)) return false;
  if (NON_PAGE_DIRS.has(rel.split("/")[0])) return false;
  if (NON_PAGE_BASENAMES.has(base)) return false;
  return true;
}

function git(repoDir: string, args: string[]): string {
  // -c core.quotePath=false: without it git C-quotes non-ASCII paths in
  // --name-status and diff --git output ("blog/caf\303\251.md"), and the
  // quoted form silently fails the docsPrefix filter — an invisible event,
  // the worst direction for a coverage census.
  return execFileSync("git", ["-c", "core.quotePath=false", ...args], {
    cwd: repoDir,
    // env bound via gitFixtureEnv: an inherited GIT_DIR/GIT_WORK_TREE would
    // redirect the census onto a different repository and read as a silent
    // green — the exact failure class this guard exists to prevent. The
    // fixture-oriented extras (identity, ceiling at dirname(repoDir)) are
    // inert for read-only calls.
    env: gitFixtureEnv(repoDir),
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

/** Fail loudly (never vacuously) when the census baseline is unreachable —
 *  e.g. a shallow clone or a rewritten history. A clone deep enough to hold
 *  the baseline yet truncated above it would pass `cat-file -e` while the
 *  census silently missed pre-baseline events, so shallowness is asserted
 *  too — the census enumerates ALL history, not baseline..HEAD. */
export function assertBaselineReachable(repoDir: string, baseline: string): void {
  try {
    git(repoDir, ["cat-file", "-e", `${baseline}^{commit}`]);
  } catch {
    throw new Error(
      `tombstone baseline ${baseline} is not a commit in this repository — refusing to run a vacuous census (shallow clone? rewritten history?)`,
    );
  }
  if (git(repoDir, ["rev-parse", "--is-shallow-repository"]).trim() === "true") {
    throw new Error(
      `this clone is shallow — the tombstone census enumerates all history and a truncated one reads as "nothing died"`,
    );
  }
}

export type FileEvent = {
  commit: string;
  subject: string;
  kind: "D" | "R";
  /** Repo-relative path that lost content (the old side of a rename). */
  oldPath: string;
  /** Repo-relative new path, for renames. */
  newPath?: string;
};

/** A path git still emitted C-quoted (control chars, quotes, backslashes —
 *  core.quotePath only unquotes non-ASCII) is a shape the census cannot
 *  parse: fail loud rather than silently skip the event. */
function assertUnquotedPath(path: string, context: string): void {
  if (path.startsWith('"')) {
    throw new Error(
      `git emitted a C-quoted path in ${context}: ${path} — the census cannot parse it; a silent skip would hide a dead URL`,
    );
  }
}

/** Enumerate D/R events under docsPrefix across all of history. */
export function enumerateFileEvents(
  repoDir: string,
  docsPrefix: string,
): FileEvent[] {
  const args = [
    "log",
    "--diff-filter=RD",
    "-M",
    "--name-status",
    "--format=COMMIT%x09%H%x09%s",
  ];
  args.push("--", docsPrefix);
  const out = git(repoDir, args);
  const events: FileEvent[] = [];
  let commit = "";
  let subject = "";
  for (const line of out.split("\n")) {
    const c = line.match(/^COMMIT\t([0-9a-f]+)\t(.*)$/);
    if (c) {
      commit = c[1];
      subject = c[2];
      continue;
    }
    const d = line.match(/^D\t(.+)$/);
    if (d) {
      assertUnquotedPath(d[1], "--name-status D record");
      events.push({ commit, subject, kind: "D", oldPath: d[1] });
      continue;
    }
    const r = line.match(/^R\d+\t(.+)\t(.+)$/);
    if (r) {
      assertUnquotedPath(r[1], "--name-status R record");
      assertUnquotedPath(r[2], "--name-status R record");
      events.push({
        commit,
        subject,
        kind: "R",
        oldPath: r[1],
        newPath: r[2],
      });
    }
  }
  return events;
}

export type PermalinkEvent = {
  commit: string;
  subject: string;
  path: string;
};

/** Every (commit, file) pair whose diff touches a `permalink:` line —
 *  additions, removals, and value changes alike. The consumer diffs the
 *  file's derived URL set at commit^ vs commit, so reslug-by-ADDITION (a
 *  path-derived file gaining a permalink) is caught, not just removals. */
export function enumeratePermalinkEvents(
  repoDir: string,
  docsPrefix: string,
): PermalinkEvent[] {
  const args = ["log", "-p", "-Gpermalink:", "--format=COMMIT%x09%H%x09%s"];
  args.push("--", docsPrefix);
  const out = git(repoDir, args);
  const events: PermalinkEvent[] = [];
  let commit = "";
  let subject = "";
  let path = "";
  let touched = false;
  for (const line of out.split("\n")) {
    const c = line.match(/^COMMIT\t([0-9a-f]+)\t(.*)$/);
    if (c) {
      if (touched && path) events.push({ commit, subject, path });
      commit = c[1];
      subject = c[2];
      path = "";
      touched = false;
      continue;
    }
    const d = line.match(/^diff --git a\/.+ b\/(.+)$/);
    if (d) {
      if (touched && path) events.push({ commit, subject, path });
      path = d[1];
      touched = false;
      assertUnquotedPath(path, "diff --git header");
      continue;
    }
    // A +/- line carrying `permalink:` — col-0 frontmatter, an indented
    // eleventyComputed key, or a quoted JSON key all count here; the
    // before/after URL diff in collectNeeds decides what actually died.
    if (/^[+-].*permalink:/.test(line) && !/^[+-]{3}/.test(line)) {
      touched = true;
    }
  }
  if (touched && path) events.push({ commit, subject, path });
  return events;
}

/** Blob at `rev:path`, or null when the file is genuinely absent there.
 *  Operational failures (git missing, corrupt repo, bad rev) rethrow — a
 *  read error must not silently shrink a dead URL's derived set. */
function blobAt(repoDir: string, rev: string, path: string): string | null {
  try {
    return git(repoDir, ["show", `${rev}:${path}`]);
  } catch (e) {
    const stderr =
      e !== null && typeof e === "object" && "stderr" in e
        ? String((e as { stderr: unknown }).stderr)
        : String(e);
    if (
      /does not exist|exists on disk, but not in|not found in|invalid object name/i.test(
        stderr,
      )
    ) {
      return null;
    }
    throw e;
  }
}

/** Frontmatter-scoped permalink read — a `permalink:` line inside a markdown
 *  body is not an override (same convention as validate-blog-links.sh). */
export function frontmatterPermalink(blob: string): string | null {
  if (!blob.startsWith("---")) return null;
  const end = blob.indexOf("\n---", 3);
  const fm = end === -1 ? blob : blob.slice(0, end);
  const m = fm.match(/^permalink:\s*(.+?)\s*$/m);
  if (!m) return null;
  let v = m[1];
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    v = v.slice(1, -1);
  }
  return v;
}

/**
 * The URL shapes a permalink value serves. Directory-style (`x/`) and
 * `/index.html`-suffixed permalinks serve three shapes (dir, index.html,
 * bare — Bulk Redirects match full_uri exactly). Other file-shaped
 * permalinks (`x.html`) serve exactly one. Template values (`{{`) are
 * underivable and return null.
 */
export function permalinkUrls(perm: string): string[] | null {
  if (perm.includes("{{") || perm.includes("}}")) return null;
  // `permalink: false` disables emission entirely — the file serves nothing.
  if (perm === "false") return [];
  let p = perm.startsWith("/") ? perm : `/${perm}`;
  if (p === "/") return ["/"];
  if (p === "/index.html") return ["/", "/index.html"];
  const last = p.split("/").pop()!;
  if (last === "index.html") {
    const dir = p.slice(0, -"index.html".length);
    return [dir, `${dir}index.html`, dir.slice(0, -1)];
  }
  if (last.includes(".")) return [p];
  const dir = p.endsWith("/") ? p : `${p}/`;
  return [dir, `${dir}index.html`, dir.slice(0, -1)];
}

function dirShapes(dir: string): string[] {
  return [dir, `${dir}index.html`, dir.slice(0, -1)];
}

// blog.json's `blog/{{ page.fileSlug }}/index.html` dir-data permalink
// applies at ANY depth under blog/, and fileSlug strips both the directory
// portion and the YYYY-MM-DD- prefix — a nested dated post serves
// /blog/<slug>/, never /blog/<sub>/<slug>/.
const DATED_POST = /^blog\/(?:[^/]+\/)*(\d{4}-\d{2}-\d{2})-([^/]+)\.md$/;
const BLOG_POST = /^blog\/(?:[^/]+\/)*([^/]+)\.(md|njk|html)$/;

/**
 * Eleventy default URL for a page file with no permalink override —
 * dir-slug output (`x.md` -> `/x/`, `x/index.njk` -> `/x/`, root `index.*` ->
 * `/`), except `.html` files which serve their literal path and blog files
 * which serve fileSlug under /blog/ at any nesting depth.
 */
export function pathDerivedUrls(rel: string): string[] {
  const dated = rel.match(DATED_POST);
  if (dated) {
    return [
      ...dirShapes(`/blog/${dated[2]}/`),
      ...dirShapes(`/blog/${dated[1]}-${dated[2]}/`),
    ];
  }
  const blogFile = rel.match(BLOG_POST);
  if (blogFile) {
    const slug = blogFile[1].replace(/^\d{4}-\d{2}-\d{2}-/, "");
    return dirShapes(`/blog/${slug}/`);
  }
  const stem = rel.replace(/\.(md|njk|html)$/, "");
  if (stem === "index") return ["/"];
  if (stem.endsWith("/index")) return dirShapes(`/${stem.slice(0, -6)}/`);
  if (rel.endsWith(".html")) return [`/${rel}`];
  return dirShapes(`/${stem}/`);
}

export type Derivation = { urls: string[]; underivable: boolean };

function relUnder(path: string, docsPrefix: string): string {
  return path.startsWith(`${docsPrefix}/`)
    ? path.slice(docsPrefix.length + 1)
    : path;
}

/** Blob → URL set. A null blob falls back to path-derived derivation (the
 *  file event side, where git already reported the file existed — an absent
 *  parent blob is anomalous history and the loud direction is to demand). */
function deriveFromBlob(blob: string | null, rel: string): Derivation {
  const perm = blob === null ? null : frontmatterPermalink(blob);
  const urls = new Set<string>();
  if (perm !== null) {
    const derived = permalinkUrls(perm);
    if (derived === null) return { urls: [], underivable: true };
    for (const u of derived) urls.add(u);
  } else {
    for (const u of pathDerivedUrls(rel)) urls.add(u);
  }
  const dated = rel.match(DATED_POST);
  if (dated) {
    for (const u of dirShapes(`/blog/${dated[1]}-${dated[2]}/`)) urls.add(u);
  }
  return { urls: [...urls], underivable: false };
}

/**
 * The public URL set a file served at `rev`. Blob permalink wins over the
 * filename default; dated blog posts ALWAYS emit the dated-alias family on
 * top (the meta-refresh machinery served it independent of canonical).
 */
export function deriveUrlsAtRev(
  repoDir: string,
  rev: string,
  path: string,
  docsPrefix: string,
): Derivation {
  return deriveFromBlob(blobAt(repoDir, rev, path), relUnder(path, docsPrefix));
}

/** Same derivation, but a file absent at `rev` serves NOTHING — the
 *  permalink-event side, where "the file was created in this commit" is a
 *  legitimate shape and a path-derived fallback would invent URLs it never
 *  served. */
function urlsIfFileExists(
  repoDir: string,
  rev: string,
  path: string,
  docsPrefix: string,
): Derivation {
  const blob = blobAt(repoDir, rev, path);
  if (blob === null) return { urls: [], underivable: false };
  return deriveFromBlob(blob, relUnder(path, docsPrefix));
}

/** The URL set the docs tree serves at HEAD (working tree read — the census
 *  only needs "is this URL still emitted", not a full Eleventy build). */
export function liveUrlPaths(repoDir: string, docsPrefix: string): Set<string> {
  const live = new Set<string>();
  const root = join(repoDir, docsPrefix);
  const walk = (dir: string) => {
    let entries: Dirent[];
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const ent of entries) {
      const full = join(dir, ent.name);
      if (ent.isDirectory()) {
        walk(full);
        continue;
      }
      const rel = full.slice(root.length + 1).replaceAll("\\", "/");
      if (!isPageEmitting(rel)) continue;
      let blob: string;
      try {
        blob = readFileSync(full, "utf8");
      } catch {
        continue;
      }
      const perm = frontmatterPermalink(blob);
      const urls = perm === null ? pathDerivedUrls(rel) : permalinkUrls(perm);
      for (const u of urls ?? []) live.add(u);
      const dated = rel.match(DATED_POST);
      if (dated) {
        for (const u of dirShapes(`/blog/${dated[1]}-${dated[2]}/`)) {
          live.add(u);
        }
      }
    }
  };
  walk(root);
  return live;
}

export type UrlNeed = {
  url: string;
  commit: string;
  subject: string;
  kind: "delete" | "rename" | "permalink-change";
  path: string;
};

export type Census = {
  /** URLs needing an edge redirect or a live emitter, with their origin. */
  needs: UrlNeed[];
  /** Paths whose permalink was a template ({{) — derivation impossible, so
   *  the path MUST carry an exemption entry. */
  underivablePaths: { path: string; commit: string }[];
  /** Raw event counts for diagnostics. */
  fileEvents: number;
  permalinkEvents: number;
};

/**
 * The full tombstone census: every URL that stopped being served under
 * docsPrefix across all history, with the event that stranded it. Rename
 * events contribute only the shapes the NEW file does not re-serve (a
 * date-only rename of a dated post keeps the canonical but strands the old
 * dated alias); a rename that lands OUTSIDE docsPrefix re-serves nothing.
 */
export function collectNeeds(
  repoDir: string,
  docsPrefix: string,
): Census {
  const needs = new Map<string, UrlNeed>();
  const underivablePaths: { path: string; commit: string }[] = [];
  const underivableSeen = new Set<string>();
  const pushUnderivable = (path: string, commit: string) => {
    // A template-permalink deletion surfaces twice (the D event AND the
    // -permalink: removal line in its diff) — one entry per path.
    if (underivableSeen.has(path)) return;
    underivableSeen.add(path);
    underivablePaths.push({ path, commit });
  };
  const seen = new Set<string>();

  const addNeed = (n: UrlNeed) => {
    if (!seen.has(n.url)) {
      seen.add(n.url);
      needs.set(n.url, n);
    }
  };

  const fileEvents = enumerateFileEvents(repoDir, docsPrefix);
  for (const ev of fileEvents) {
    if (!ev.oldPath.startsWith(`${docsPrefix}/`)) continue;
    const oldRel = ev.oldPath.slice(docsPrefix.length + 1);
    if (!isPageEmitting(oldRel)) continue;
    const parent = `${ev.commit}^`;
    const old = deriveUrlsAtRev(repoDir, parent, ev.oldPath, docsPrefix);
    if (old.underivable) {
      pushUnderivable(ev.oldPath, ev.commit);
      continue;
    }
    let newUrls = new Set<string>();
    // A rename whose new path lands OUTSIDE the docs tree re-serves nothing —
    // the file left Eleventy's input entirely. Only subtract when the new
    // path is a page-emitting file still under docsPrefix.
    if (
      ev.kind === "R" &&
      ev.newPath &&
      ev.newPath.startsWith(`${docsPrefix}/`)
    ) {
      const newRel = ev.newPath.slice(docsPrefix.length + 1);
      if (isPageEmitting(newRel)) {
        const nu = deriveUrlsAtRev(repoDir, ev.commit, ev.newPath, docsPrefix);
        newUrls = new Set(nu.urls);
      }
    }
    for (const url of old.urls) {
      if (newUrls.has(url)) continue;
      addNeed({
        url,
        commit: ev.commit,
        subject: ev.subject,
        kind: ev.kind === "D" ? "delete" : "rename",
        path: ev.oldPath,
      });
    }
  }

  // Permalink events: for every file whose diff touched a `permalink:` line,
  // demand the URL set it served at commit^ minus the set it serves at
  // commit. Value changes, removals, AND reslug-by-addition all collapse into
  // this one diff; a restore surfaces as a need that classifies `live` (HEAD
  // re-declares the value), matching the old value-redeclare semantics.
  const permalinkEvents = enumeratePermalinkEvents(repoDir, docsPrefix);
  for (const ev of permalinkEvents) {
    if (!ev.path.startsWith(`${docsPrefix}/`)) continue;
    const rel = ev.path.slice(docsPrefix.length + 1);
    if (!isPageEmitting(rel)) continue;
    const before = urlsIfFileExists(
      repoDir,
      `${ev.commit}^`,
      ev.path,
      docsPrefix,
    );
    if (before.underivable) {
      pushUnderivable(ev.path, ev.commit);
      continue;
    }
    const after = urlsIfFileExists(repoDir, ev.commit, ev.path, docsPrefix);
    const afterSet = new Set(after.urls);
    for (const url of before.urls) {
      if (afterSet.has(url)) continue;
      addNeed({
        url,
        commit: ev.commit,
        subject: ev.subject,
        kind: "permalink-change",
        path: ev.path,
      });
    }
  }

  return {
    needs: [...needs.values()],
    underivablePaths,
    fileEvents: fileEvents.length,
    permalinkEvents: permalinkEvents.length,
  };
}

export type Classified = {
  uncovered: UrlNeed[];
  underivableUnexempt: { path: string; commit: string }[];
  /** Exemption keys no event consumed — a stale exemption rots silently. */
  staleExempt: string[];
  counts: { covered: number; live: number; exempt: number; uncovered: number };
};

/**
 * Classify every census need: exempt (path-keyed) -> live (still emitted at
 * HEAD) -> covered (declared redirect source) -> uncovered.
 */
export function classifyCensus(
  census: Census,
  coverage: Set<string>,
  live: Set<string>,
  exempt: Set<string>,
): Classified {
  const uncovered: UrlNeed[] = [];
  const counts = { covered: 0, live: 0, exempt: 0, uncovered: 0 };
  const consumedExempt = new Set<string>();
  for (const need of census.needs) {
    if (exempt.has(need.path)) {
      consumedExempt.add(need.path);
      counts.exempt++;
      continue;
    }
    if (live.has(need.url)) {
      counts.live++;
      continue;
    }
    if (coverage.has(need.url)) {
      counts.covered++;
      continue;
    }
    counts.uncovered++;
    uncovered.push(need);
  }
  const underivableUnexempt = census.underivablePaths.filter((u) => {
    if (exempt.has(u.path)) {
      consumedExempt.add(u.path);
      return false;
    }
    return true;
  });
  const staleExempt = [...exempt].filter((p) => !consumedExempt.has(p));
  return { uncovered, underivableUnexempt, staleExempt, counts };
}

/** Extract the brace-balanced body of `resource "<type>" "<name>"` — the same
 *  technique as the seo-rulesets-noindex.ts precedent, duplicated here
 *  because plugins/soleur/test cannot import apps/web-platform/test/lib. */
export function extractResourceBody(
  tf: string,
  type: string,
  name: string,
): string {
  const marker = `resource "${type}" "${name}"`;
  const markerIdx = tf.indexOf(marker);
  if (markerIdx === -1) {
    throw new Error(`resource "${type}" "${name}" not found`);
  }
  const openIdx = tf.indexOf("{", markerIdx);
  if (openIdx === -1) {
    throw new Error(`resource "${type}" "${name}" has no opening brace`);
  }
  let depth = 0;
  for (let i = openIdx; i < tf.length; i++) {
    if (tf[i] === "{") depth++;
    else if (tf[i] === "}") {
      depth--;
      if (depth === 0) return tf.slice(openIdx + 1, i);
    }
  }
  throw new Error(`resource "${type}" "${name}" has no closing brace`);
}
