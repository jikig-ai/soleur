import { readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const BLOG_DIR = join(__dirname, "..", "blog");
// Must match glob in scripts/validate-blog-links.sh (redirect validation section)
const DATE_PREFIX_RE = /^(\d{4}-\d{2}-\d{2})-(.+)$/;

export default function () {
  let files;
  try {
    files = readdirSync(BLOG_DIR).filter((f) => f.endsWith(".md"));
  } catch (err) {
    if (err.code === "ENOENT") return [];
    throw err;
  }

  const redirects = [];

  for (const file of files) {
    const slug = file.replace(/\.md$/, "");
    const match = slug.match(DATE_PREFIX_RE);
    if (match) {
      redirects.push({
        dateSlug: slug,
        canonicalSlug: match[2],
      });
    }
  }

  return redirects;
}
