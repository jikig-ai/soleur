import fs from "fs";
import path from "path";

/**
 * Create a minimal vision.md from the founder's first message.
 * No-op if vision.md already exists. Caller should wrap in .catch()
 * to avoid unhandled rejections (Node 22+ terminates on them).
 */
export async function tryCreateVision(
  workspacePath: string,
  content: string,
): Promise<void> {
  const visionPath = path.join(
    workspacePath,
    "knowledge-base",
    "overview",
    "vision.md",
  );

  // Check if vision.md already exists — don't overwrite
  try {
    await fs.promises.access(visionPath);
    return;
  } catch {
    // File doesn't exist — create it below
  }

  await fs.promises.mkdir(path.dirname(visionPath), { recursive: true });
  await fs.promises.writeFile(
    visionPath,
    `# Vision\n\n${content}\n`,
    "utf-8",
  );
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
    if (stat.size >= 500) return null;
  } catch {
    return null;
  }

  return (
    "\n\nThe founder's vision document at knowledge-base/overview/vision.md " +
    "is a stub. Enhance it with structured sections: Mission, Target Audience, " +
    "Value Proposition, Key Differentiators. Write the enhanced version to the same path."
  );
}
