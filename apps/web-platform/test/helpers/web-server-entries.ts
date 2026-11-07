import { readFileSync } from "node:fs";
import { join } from "node:path";
import { stripComments } from "./strip-comments";

/**
 * Shared parser for `playwright.config.ts`'s `webServer:` array, for the
 * config-text assertion suites (playwright-dev-server-distdir,
 * playwright-web-server-exit-marker). Comments are stripped before parsing so
 * a commented-out key cannot satisfy an assertion
 * (cq-assert-anchor-not-bare-token).
 *
 * The block is bounded at the array's close bracket so keys landing below the
 * `webServer:` array never enter the census. Each `command:` marks a new
 * entry — per-entry assertions read the text after it.
 */
export function parseWebServerEntries(configPath: string): {
  text: string;
  block: string;
  entries: string[];
} {
  const text = stripComments(readFileSync(configPath, "utf-8"));
  const raw = text.slice(text.indexOf("webServer:"));
  // The array's close bracket sits on its own line; a bare indexOf("]") would
  // truncate on a `]` inside an entry value (array field, indexed expr).
  const block = raw.slice(0, raw.search(/\n\s*\]/));
  return { text, block, entries: block.split(/\bcommand:\s/).slice(1) };
}

export const playwrightConfigPath = (dir: string) =>
  join(dir, "..", "playwright.config.ts");
