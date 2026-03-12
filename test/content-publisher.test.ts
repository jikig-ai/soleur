import { describe, test, expect } from "bun:test";
import { join } from "path";

const SCRIPT_PATH = join(import.meta.dirname, "..", "scripts", "content-publisher.sh");
const SAMPLE_CONTENT = join(import.meta.dirname, "helpers", "sample-content.md");
const SAMPLE_NO_MANUAL = join(import.meta.dirname, "helpers", "sample-content-no-manual.md");

const BASE_ENV: Record<string, string> = {
  PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin",
  HOME: process.env.HOME ?? "/tmp",
};

function decode(buf: Buffer | Uint8Array): string {
  return new TextDecoder().decode(buf);
}

/**
 * Runs a bash snippet that sources content-publisher.sh functions.
 * The script uses a BASH_SOURCE guard so sourcing does not execute main().
 */
function runFunction(bashCode: string, env?: Record<string, string>): {
  stdout: string;
  stderr: string;
  exitCode: number;
} {
  const wrapper = `
    set -euo pipefail
    source '${SCRIPT_PATH}'
    ${bashCode}
  `;

  const result = Bun.spawnSync(["bash", "-c", wrapper], {
    env: { ...BASE_ENV, ...env },
  });

  return {
    stdout: decode(result.stdout).trim(),
    stderr: decode(result.stderr).trim(),
    exitCode: result.exitCode ?? 1,
  };
}

// ---------------------------------------------------------------------------
// extract_section
// ---------------------------------------------------------------------------

describe("extract_section", () => {
  test("extracts Discord section with preserved line breaks", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "Discord"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("This is the Discord content for testing.");
    expect(result.stdout).toContain("It has multiple paragraphs");
    expect(result.stdout).toContain("Link: https://example.com");
    // Should NOT contain horizontal rules
    expect(result.stdout).not.toContain("---");
  });

  test("extracts X/Twitter Thread section (contains /)", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "X/Twitter Thread"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("**Tweet 1 (Hook)");
    expect(result.stdout).toContain("hook tweet for the test");
    expect(result.stdout).toContain("**Tweet 4 (Final)");
  });

  test("extracts IndieHackers section", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "IndieHackers"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Test case study for IndieHackers");
    expect(result.stdout).toContain("Has anyone tested this?");
  });

  test("extracts Reddit section", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "Reddit"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("r/testing");
    expect(result.stdout).toContain("Reddit content for the test");
  });

  test("extracts Hacker News section (last section, no trailing ##)", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "Hacker News"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Test Case Study");
    expect(result.stdout).toContain("https://example.com/blog/test-case-study/");
  });

  test("returns empty for 'Not scheduled' placeholder sections", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_NO_MANUAL}" "IndieHackers"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("returns empty for Reddit 'Not scheduled' placeholder", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_NO_MANUAL}" "Reddit"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("returns empty for Hacker News 'Not scheduled' placeholder", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_NO_MANUAL}" "Hacker News"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("returns empty for nonexistent section", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "Nonexistent"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });
});

// ---------------------------------------------------------------------------
// extract_tweets
// ---------------------------------------------------------------------------

describe("extract_tweets", () => {
  test("extracts 4 tweets from sample content", () => {
    const RS = "\\x1e";
    const result = runFunction(`
      count=0
      while IFS= read -r -d $'${RS}' tweet; do
        [[ -n "$tweet" ]] && count=$((count + 1))
      done < <(extract_tweets "${SAMPLE_CONTENT}")
      echo "$count"
    `);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("4");
  });

  test("first tweet is the hook text (no label line)", () => {
    const RS = "\\x1e";
    const result = runFunction(`
      while IFS= read -r -d $'${RS}' tweet; do
        echo "$tweet"
        break
      done < <(extract_tweets "${SAMPLE_CONTENT}")
    `);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("hook tweet for the test");
    // Should NOT contain the label line
    expect(result.stdout).not.toContain("**Tweet 1");
  });

  test("multi-line tweet preserves internal line breaks", () => {
    // Tweet 3 has content followed by a blank line and a URL
    const RS = "\\x1e";
    const result = runFunction(`
      i=0
      while IFS= read -r -d $'${RS}' tweet; do
        i=$((i + 1))
        if [[ $i -eq 3 ]]; then
          echo "$tweet"
          break
        fi
      done < <(extract_tweets "${SAMPLE_CONTENT}")
    `);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Another body tweet");
    expect(result.stdout).toContain("https://example.com");
  });

  test("returns error for missing X/Twitter Thread section", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'
      tmpfile=$(mktemp)
      echo "## Discord" > "$tmpfile"
      echo "Some content" >> "$tmpfile"
      extract_tweets "$tmpfile"
      rm "$tmpfile"
    `], { env: BASE_ENV });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("No X/Twitter Thread section");
  });

  test("extracts 3 tweets from no-manual sample", () => {
    const RS = "\\x1e";
    const result = runFunction(`
      count=0
      while IFS= read -r -d $'${RS}' tweet; do
        [[ -n "$tweet" ]] && count=$((count + 1))
      done < <(extract_tweets "${SAMPLE_NO_MANUAL}")
      echo "$count"
    `);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("3");
  });
});

// ---------------------------------------------------------------------------
// resolve_content -- uses CONTENT_DIR override for testing
// ---------------------------------------------------------------------------

describe("resolve_content", () => {
  test("maps study 1 to legal-document-generation with 3 manual platforms", () => {
    const result = runFunction(`
      tmpdir=$(mktemp -d)
      CONTENT_DIR="$tmpdir"
      touch "$tmpdir/01-legal-document-generation.md"
      resolve_content 1
      echo "FILE=$CONTENT_FILE"
      echo "NAME=$CASE_NAME"
      echo "PLATFORMS=$MANUAL_PLATFORMS"
      rm -r "$tmpdir"
    `);
    expect(result.stdout).toContain("NAME=Legal Document Generation");
    expect(result.stdout).toContain("PLATFORMS=indiehackers,reddit,hackernews");
  });

  test("maps study 2 to operations-management with no manual platforms", () => {
    const result = runFunction(`
      tmpdir=$(mktemp -d)
      CONTENT_DIR="$tmpdir"
      touch "$tmpdir/02-operations-management.md"
      resolve_content 2
      echo "NAME=$CASE_NAME"
      echo "PLATFORMS=$MANUAL_PLATFORMS"
      rm -r "$tmpdir"
    `);
    expect(result.stdout).toContain("NAME=Operations Management");
    expect(result.stdout).toContain("PLATFORMS=");
  });

  test("maps study 3 to competitive-intelligence with 2 manual platforms", () => {
    const result = runFunction(`
      tmpdir=$(mktemp -d)
      CONTENT_DIR="$tmpdir"
      touch "$tmpdir/03-competitive-intelligence.md"
      resolve_content 3
      echo "NAME=$CASE_NAME"
      echo "PLATFORMS=$MANUAL_PLATFORMS"
      rm -r "$tmpdir"
    `);
    expect(result.stdout).toContain("NAME=Competitive Intelligence");
    expect(result.stdout).toContain("PLATFORMS=indiehackers,reddit");
  });

  test("maps study 4 to brand-guide-creation with no manual platforms", () => {
    const result = runFunction(`
      tmpdir=$(mktemp -d)
      CONTENT_DIR="$tmpdir"
      touch "$tmpdir/04-brand-guide-creation.md"
      resolve_content 4
      echo "NAME=$CASE_NAME"
      echo "PLATFORMS=$MANUAL_PLATFORMS"
      rm -r "$tmpdir"
    `);
    expect(result.stdout).toContain("NAME=Brand Guide Creation");
    expect(result.stdout).toContain("PLATFORMS=");
  });

  test("maps study 5 to business-validation with 3 manual platforms", () => {
    const result = runFunction(`
      tmpdir=$(mktemp -d)
      CONTENT_DIR="$tmpdir"
      touch "$tmpdir/05-business-validation.md"
      resolve_content 5
      echo "NAME=$CASE_NAME"
      echo "PLATFORMS=$MANUAL_PLATFORMS"
      rm -r "$tmpdir"
    `);
    expect(result.stdout).toContain("NAME=Business Validation");
    expect(result.stdout).toContain("PLATFORMS=indiehackers,reddit,hackernews");
  });

  test("exits non-zero for invalid input 0", () => {
    // resolve_content calls exit 1 which terminates the bash process
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'
      CONTENT_DIR="/tmp/nonexistent"
      resolve_content 0
    `], { env: BASE_ENV });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("Invalid case study number");
  });

  test("exits non-zero for invalid input 6", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'
      CONTENT_DIR="/tmp/nonexistent"
      resolve_content 6
    `], { env: BASE_ENV });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("Invalid case study number");
  });

  test("exits non-zero for non-numeric input", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'
      CONTENT_DIR="/tmp/nonexistent"
      resolve_content abc
    `], { env: BASE_ENV });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("Invalid case study number");
  });
});

// ---------------------------------------------------------------------------
// post_discord webhook URL resolution
// ---------------------------------------------------------------------------

describe("post_discord webhook URL resolution", () => {
  test("uses DISCORD_BLOG_WEBHOOK_URL when set", () => {
    // Override curl to capture the last argument (webhook URL) to stderr
    // and return a 2xx HTTP code on stdout
    const result = runFunction(
      `
      curl() { echo "CALLED_URL=\${@: -1}" >&2; printf "204"; }
      export -f curl
      post_discord "test content"
    `,
      {
        DISCORD_BLOG_WEBHOOK_URL: "https://blog-webhook",
        DISCORD_WEBHOOK_URL: "https://general-webhook",
      }
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("CALLED_URL=https://blog-webhook");
    expect(result.stdout).toContain("[ok] Discord message posted");
  });

  test("falls back to DISCORD_WEBHOOK_URL when blog URL not set", () => {
    const result = runFunction(
      `
      curl() { echo "CALLED_URL=\${@: -1}" >&2; printf "204"; }
      export -f curl
      post_discord "test content"
    `,
      {
        DISCORD_WEBHOOK_URL: "https://general-webhook",
      }
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("CALLED_URL=https://general-webhook");
    expect(result.stdout).toContain("[ok] Discord message posted");
  });

  test("skips posting when no webhook URLs set", () => {
    const result = runFunction(`post_discord "test content"`);
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("No Discord webhook URL set");
  });
});

// ---------------------------------------------------------------------------
// CLI invocation (integration)
// ---------------------------------------------------------------------------

describe("content-publisher.sh CLI", () => {
  test("exits 1 with no arguments", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH], {
      env: BASE_ENV,
    });
    expect(result.exitCode).not.toBe(0);
  });

  test("exits 1 for invalid case study number", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "99"], {
      env: BASE_ENV,
    });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("Invalid case study number");
  });
});
