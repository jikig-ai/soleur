/**
 * Single read path for synthesized GitHub REST API response-body fixtures
 * (#3415). Tests import `loadGithubFixture(name)` instead of inlining JSON
 * literals or calling `readFileSync` directly, so the mock bodies match
 * GitHub's public response shapes and never drift into prod-shaped data
 * (cq-test-fixtures-synthesized-only).
 *
 * Only the response BODY lives here. The vitest mock wrapper (`ok`/`status`)
 * stays inline at each call site — it is mock mechanics, not API data.
 *
 * Fixtures are SYNTHESIZED: `@example.com`/`@test.local`-class identifiers,
 * small synthetic integer IDs, no prod UUIDs, and token fields use the
 * obvious `ghs_<<synthetic>>` placeholder (the `<<>>` shape is non-alphanumeric
 * so GitHub push-protection cannot mistake it for a real token).
 */
import { readFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";

const FIXTURE_DIR = path.dirname(fileURLToPath(import.meta.url));

/**
 * The synthesized fixture names available under `test/fixtures/github/`.
 * Keep in sync with the `.json` files in this directory.
 */
export type GithubFixtureName =
  | "installation-account-org"
  | "installation-account-user"
  | "installation-access-token"
  | "installation-200"
  | "installations-list"
  | "repo-create-201"
  | "template-generate-201"
  | "repo-metadata-200"
  | "pull-request-201"
  | "issue-201"
  | "error-403"
  | "error-404"
  | "error-422-duplicate"
  | "error-422-not-template";

/**
 * Read + parse a synthesized GitHub API fixture by name. Returns a fresh
 * (deeply independent) object on every call so a test mutating a fixture body
 * never bleeds into another test.
 *
 * @typeParam T - the expected parsed shape (caller-supplied; fixtures are JSON
 *   so this is an unchecked cast, matching `import`-of-JSON ergonomics).
 */
export function loadGithubFixture<T = Record<string, unknown>>(
  name: GithubFixtureName,
): T {
  const raw = readFileSync(path.join(FIXTURE_DIR, `${name}.json`), "utf8");
  return JSON.parse(raw) as T;
}
