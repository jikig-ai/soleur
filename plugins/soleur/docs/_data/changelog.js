import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import MarkdownIt from "markdown-it";

const md = new MarkdownIt();

export default function () {
  try {
    const raw = readFileSync(
      resolve("plugins/soleur/CHANGELOG.md"),
      "utf-8"
    );
    // Strip the top-level heading and preamble lines (title + keepachangelog boilerplate)
    const body = raw.replace(
      /^# .+\n(?:.*\n)*?(?=\n## )/,
      ""
    );
    return { html: md.render(body) };
  } catch {
    return { html: "" };
  }
}
