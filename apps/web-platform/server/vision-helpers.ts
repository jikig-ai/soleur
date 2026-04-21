import fs from "fs";
import path from "path";
import { FOUNDATION_MIN_CONTENT_BYTES } from "@/lib/kb-constants";

// reject bare @-mentions and /slash-commands that fall below this threshold
const MIN_VISION_SEED_LENGTH = 10;

// code-unit cap (JS string length), not UTF-8 byte count
const MAX_VISION_CHARS = 5000;

/**
 * Create a minimal vision.md from the founder's first message.
 * No-op if vision.md already exists (uses O_EXCL to avoid TOCTOU race).
 * Caller should wrap in .catch() to avoid unhandled rejections
 * (Node 22+ terminates on them).
 */
export async function tryCreateVision(
  workspacePath: string,
  content: string,
): Promise<void> {
  // Content validation: reject non-user content
  const trimmed = content.trim();
  if (trimmed.length < MIN_VISION_SEED_LENGTH) return;
  if (trimmed.startsWith("/")) return;
  if (trimmed.startsWith("@") && !trimmed.includes(" ")) return;
  if (/^###?\s/.test(trimmed) && /\/soleur:/.test(trimmed)) return;

  const visionPath = path.join(
    workspacePath,
    "knowledge-base",
    "overview",
    "vision.md",
  );

  // Truncate runaway content (rogue paste, LLM loop). Note: char count, not byte
  // count — UTF-8 multibyte chars may exceed the byte cap.
  const safe = content.length > MAX_VISION_CHARS
    ? content.slice(0, MAX_VISION_CHARS)
    : content;

  await fs.promises.mkdir(path.dirname(visionPath), { recursive: true });

  // O_EXCL: atomic create — fails if file already exists (no TOCTOU race)
  try {
    await fs.promises.writeFile(
      visionPath,
      `# Vision\n\n${safe}\n`,
      { encoding: "utf-8", flag: "wx" },
    );
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "EEXIST") return;
    throw err;
  }
}

/**
 * Build a system prompt enhancement instruction if vision.md is minimal (< 500 bytes).
 * Returns null if the file is already substantial or doesn't exist.
 * Used to instruct the CPO agent to enhance a stub vision document.
 */
export async function buildVisionEnhancementPrompt(
  workspacePath: string,
): Promise<string | null> {
  const visionPath = path.join(
    workspacePath,
    "knowledge-base",
    "overview",
    "vision.md",
  );

  try {
    const stat = await fs.promises.stat(visionPath);
    if (stat.size >= FOUNDATION_MIN_CONTENT_BYTES) return null;
  } catch {
    return null;
  }

  const relativePath = "knowledge-base/overview/vision.md";
  return (
    `\n\nThe founder's vision document at \`${relativePath}\` ` +
    "is a stub. Enhance it with structured sections: Mission, Target Audience, " +
    `Value Proposition, Key Differentiators. Write the enhanced version to \`${relativePath}\`.`
  );
}
