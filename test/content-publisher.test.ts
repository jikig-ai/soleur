import { describe, test, expect } from "bun:test";
import { join } from "path";

const SCRIPT_PATH = join(import.meta.dirname, "..", "scripts", "content-publisher.sh");
const SAMPLE_CONTENT = join(import.meta.dirname, "helpers", "sample-content.md");
const SAMPLE_NO_MANUAL = join(import.meta.dirname, "helpers", "sample-content-no-manual.md");
const SAMPLE_FRONTMATTER = join(import.meta.dirname, "helpers", "sample-frontmatter.md");

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

  test("extracts Bluesky section", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "Bluesky"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("AI agents");
    expect(result.stdout).toContain("utm_source=bluesky");
  });

  test("extracts LinkedIn Personal without bleeding into LinkedIn Company Page", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "LinkedIn Personal"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("thought leadership");
    expect(result.stdout).not.toContain("official announcement");
  });

  test("extracts LinkedIn Company Page without bleeding into LinkedIn Personal", () => {
    const result = runFunction(
      `extract_section "${SAMPLE_CONTENT}" "LinkedIn Company Page"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("official announcement");
    expect(result.stdout).not.toContain("thought leadership");
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
// parse_frontmatter / get_frontmatter_field
// ---------------------------------------------------------------------------

describe("parse_frontmatter", () => {
  test("extracts YAML block between --- delimiters", () => {
    const result = runFunction(
      `parse_frontmatter "${SAMPLE_FRONTMATTER}"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain('title: "Test Case Study"');
    expect(result.stdout).toContain("type: case-study");
    expect(result.stdout).toContain("status: scheduled");
  });

  test("does not include content after second ---", () => {
    const result = runFunction(
      `parse_frontmatter "${SAMPLE_FRONTMATTER}"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).not.toContain("## Discord");
    expect(result.stdout).not.toContain("Discord content");
  });

  test("returns empty for file without frontmatter", () => {
    const result = runFunction(`
      tmpfile=$(mktemp)
      echo "# No frontmatter here" > "$tmpfile"
      echo "Just content" >> "$tmpfile"
      parse_frontmatter "$tmpfile"
      rm "$tmpfile"
    `);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });
});

describe("get_frontmatter_field", () => {
  test("extracts title with quotes stripped", () => {
    const result = runFunction(
      `get_frontmatter_field "${SAMPLE_FRONTMATTER}" "title"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("Test Case Study");
  });

  test("extracts unquoted field (type)", () => {
    const result = runFunction(
      `get_frontmatter_field "${SAMPLE_FRONTMATTER}" "type"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("case-study");
  });

  test("extracts publish_date", () => {
    const result = runFunction(
      `get_frontmatter_field "${SAMPLE_FRONTMATTER}" "publish_date"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("2026-03-12");
  });

  test("extracts comma-separated channels", () => {
    const result = runFunction(
      `get_frontmatter_field "${SAMPLE_FRONTMATTER}" "channels"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("discord, x, bluesky, linkedin-company");
  });

  test("extracts status field", () => {
    const result = runFunction(
      `get_frontmatter_field "${SAMPLE_FRONTMATTER}" "status"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("scheduled");
  });

  test("returns empty for nonexistent field", () => {
    const result = runFunction(
      `get_frontmatter_field "${SAMPLE_FRONTMATTER}" "nonexistent"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
  });
});

// ---------------------------------------------------------------------------
// channel_to_section
// ---------------------------------------------------------------------------

describe("channel_to_section", () => {
  test("maps discord to Discord", () => {
    const result = runFunction(`channel_to_section "discord"`);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("Discord");
  });

  test("maps x to X/Twitter Thread", () => {
    const result = runFunction(`channel_to_section "x"`);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("X/Twitter Thread");
  });

  test("maps linkedin-personal to LinkedIn Personal", () => {
    const result = runFunction(`channel_to_section "linkedin-personal"`);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("LinkedIn Personal");
  });

  test("maps linkedin-company to LinkedIn Company Page", () => {
    const result = runFunction(`channel_to_section "linkedin-company"`);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("LinkedIn Company Page");
  });

  test("maps bluesky to Bluesky", () => {
    const result = runFunction(`channel_to_section "bluesky"`);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("Bluesky");
  });

  test("returns empty for unknown channel", () => {
    const result = runFunction(`channel_to_section "mastodon"`);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("");
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
// CLI invocation (integration) -- scan-based, no arguments
// ---------------------------------------------------------------------------

describe("content-publisher.sh CLI", () => {
  test("exits 1 when content directory does not exist", () => {
    // Override CONTENT_DIR via sourcing, then call main()
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'
      CONTENT_DIR="/tmp/nonexistent-content-dir-$$"
      main
    `], { env: BASE_ENV });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("Content directory not found");
  });

  test("scans directory and completes with exit 0 when no content matches today", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'
      tmpdir=$(mktemp -d)
      CONTENT_DIR="$tmpdir"
      cat > "$tmpdir/test.md" << 'FRONTMATTER'
---
title: "Future Post"
type: case-study
publish_date: 2099-12-31
channels: discord
status: scheduled
---

## Discord

Future content.
FRONTMATTER
      main
      rm -r "$tmpdir"
    `], { env: BASE_ENV });
    expect(result.exitCode).toBe(0);
    expect(decode(result.stdout)).toContain("Published: 0");
  });
});

// ---------------------------------------------------------------------------
// post_linkedin
// ---------------------------------------------------------------------------

describe("post_linkedin", () => {
  test("skips gracefully when LINKEDIN_ACCESS_TOKEN is unset", () => {
    const result = runFunction(
      `post_linkedin "${SAMPLE_CONTENT}"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("LINKEDIN_ACCESS_TOKEN not set");
    expect(result.stderr).toContain("Skipping LinkedIn posting");
  });

  test("skips gracefully when content file has no LinkedIn section", () => {
    const result = runFunction(
      `
      tmpfile=$(mktemp)
      echo "## Discord" > "$tmpfile"
      echo "Some content" >> "$tmpfile"
      post_linkedin "$tmpfile" "LinkedIn Personal"
      rm "$tmpfile"
    `,
      { LINKEDIN_ACCESS_TOKEN: "test-token" }
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("No LinkedIn Personal content found");
  });

  test("posts successfully when credentials set and script succeeds", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'

      # Create mock script that succeeds
      mock_dir=$(mktemp -d)
      cat > "$mock_dir/linkedin-community.sh" << 'MOCK'
#!/usr/bin/env bash
echo '{"id":"urn:li:share:123456"}'
exit 0
MOCK
      chmod +x "$mock_dir/linkedin-community.sh"
      LINKEDIN_SCRIPT="$mock_dir/linkedin-community.sh"

      post_linkedin "${SAMPLE_CONTENT}" "LinkedIn Personal"
      exit_code=$?
      rm -r "$mock_dir"
      exit $exit_code
    `], {
      env: {
        ...BASE_ENV,
        LINKEDIN_ACCESS_TOKEN: "test-token",
      },
    });
    expect(result.exitCode).toBe(0);
    expect(decode(result.stdout)).toContain("[ok] LinkedIn post published (LinkedIn Personal).");
  });

  test("returns error when linkedin-community.sh fails", () => {
    // Create a mock linkedin-community.sh that always fails
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'

      # Create mock script that fails
      mock_dir=$(mktemp -d)
      cat > "$mock_dir/linkedin-community.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Error: API returned 401" >&2
exit 1
MOCK
      chmod +x "$mock_dir/linkedin-community.sh"
      LINKEDIN_SCRIPT="$mock_dir/linkedin-community.sh"

      # Stub create_dedup_issue to avoid gh CLI dependency
      create_dedup_issue() { echo "[stub] Issue created: $1"; return 0; }
      export -f create_dedup_issue
      CASE_NAME="test-case"

      post_linkedin "${SAMPLE_CONTENT}" "LinkedIn Personal"
      exit_code=$?
      rm -r "$mock_dir"
      exit $exit_code
    `], {
      env: {
        ...BASE_ENV,
        LINKEDIN_ACCESS_TOKEN: "test-token",
      },
    });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("LinkedIn posting failed");
  });
});

// ---------------------------------------------------------------------------
// post_linkedin_company
// ---------------------------------------------------------------------------

describe("post_linkedin_company", () => {
  test("skips gracefully when LINKEDIN_ACCESS_TOKEN is unset", () => {
    const result = runFunction(
      `post_linkedin_company "${SAMPLE_CONTENT}"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("LINKEDIN_ACCESS_TOKEN not set");
    expect(result.stderr).toContain("Skipping LinkedIn Company Page posting");
  });

  test("skips gracefully when LINKEDIN_ORG_ID is unset", () => {
    const result = runFunction(
      `post_linkedin_company "${SAMPLE_CONTENT}"`,
      { LINKEDIN_ACCESS_TOKEN: "test-token" }
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("LINKEDIN_ORG_ID not set");
    expect(result.stderr).toContain("Skipping LinkedIn Company Page posting");
  });

  test("posts successfully with mock script", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'

      # Create mock script that succeeds
      mock_dir=$(mktemp -d)
      cat > "$mock_dir/linkedin-community.sh" << 'MOCK'
#!/usr/bin/env bash
echo '{"post_urn":"urn:li:share:123456"}'
exit 0
MOCK
      chmod +x "$mock_dir/linkedin-community.sh"
      LINKEDIN_SCRIPT="$mock_dir/linkedin-community.sh"

      post_linkedin_company "${SAMPLE_CONTENT}"
      exit_code=$?
      rm -r "$mock_dir"
      exit $exit_code
    `], {
      env: {
        ...BASE_ENV,
        LINKEDIN_ACCESS_TOKEN: "test-token",
        LINKEDIN_PERSON_URN: "urn:li:person:test",
        LINKEDIN_ORG_ID: "12345",
      },
    });
    expect(result.exitCode).toBe(0);
    expect(decode(result.stdout)).toContain("[ok] LinkedIn Company Page post published.");
  });
});

// ---------------------------------------------------------------------------
// post_bluesky
// ---------------------------------------------------------------------------

describe("post_bluesky", () => {
  test("skips gracefully when BSKY_HANDLE is unset", () => {
    const result = runFunction(
      `post_bluesky "${SAMPLE_CONTENT}"`
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("Bluesky credentials not configured");
    expect(result.stderr).toContain("Skipping Bluesky posting");
  });

  test("skips gracefully when content file has no Bluesky section", () => {
    const result = runFunction(
      `
      tmpfile=$(mktemp)
      echo "## Discord" > "$tmpfile"
      echo "Some content" >> "$tmpfile"
      post_bluesky "$tmpfile"
      rm "$tmpfile"
    `,
      {
        BSKY_HANDLE: "test.bsky.social",
        BSKY_APP_PASSWORD: "test-password",
      }
    );
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("No Bluesky content found");
  });

  test("posts successfully with mock bsky script", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'

      # Create mock script that succeeds
      mock_dir=$(mktemp -d)
      cat > "$mock_dir/bsky-community.sh" << 'MOCK'
#!/usr/bin/env bash
echo '{"uri":"at://did:plc:test/app.bsky.feed.post/abc","cid":"bafytest"}'
exit 0
MOCK
      chmod +x "$mock_dir/bsky-community.sh"
      BSKY_SCRIPT="$mock_dir/bsky-community.sh"

      post_bluesky "${SAMPLE_CONTENT}"
      exit_code=$?
      rm -r "$mock_dir"
      exit $exit_code
    `], {
      env: {
        ...BASE_ENV,
        BSKY_HANDLE: "test.bsky.social",
        BSKY_APP_PASSWORD: "test-password",
        BSKY_ALLOW_POST: "true",
      },
    });
    expect(result.exitCode).toBe(0);
    expect(decode(result.stdout)).toContain("[ok] Bluesky post published.");
  });

  test("returns error when bsky-community.sh fails", () => {
    const result = Bun.spawnSync(["bash", "-c", `
      set -euo pipefail
      source '${SCRIPT_PATH}'

      # Create mock script that fails
      mock_dir=$(mktemp -d)
      cat > "$mock_dir/bsky-community.sh" << 'MOCK'
#!/usr/bin/env bash
echo "Error: Authentication failed" >&2
exit 1
MOCK
      chmod +x "$mock_dir/bsky-community.sh"
      BSKY_SCRIPT="$mock_dir/bsky-community.sh"

      # Stub create_dedup_issue to avoid gh CLI dependency
      create_dedup_issue() { echo "[stub] Issue created: \$1"; return 0; }
      export -f create_dedup_issue
      CASE_NAME="test-case"

      post_bluesky "${SAMPLE_CONTENT}"
      exit_code=$?
      rm -r "$mock_dir"
      exit $exit_code
    `], {
      env: {
        ...BASE_ENV,
        BSKY_HANDLE: "test.bsky.social",
        BSKY_APP_PASSWORD: "test-password",
        BSKY_ALLOW_POST: "true",
      },
    });
    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("Bluesky posting failed");
  });
});
