// The one chokepoint for the homepage "one brief reaches the departments" data (#9577).
//
// Used by plugins/soleur/docs/_data/fanoutDemo.js (so the Eleventy build throws on bad rows
// or a bad frame) and by plugins/soleur/test/fanout-demo-drift.test.ts. It lives here, not in
// the data file, because a data module must stay default-export-only: a second named export
// makes Eleventy hand the template the export object instead of calling the default function,
// so the throw never runs and the section renders empty on a green build. It lives under
// docs/scripts/, not plugins/soleur/lib/, so the docs CI path filters (critical-css-gate,
// deploy-docs) fire when it changes.
//
// The docs build must not read apps/web-platform, so the status vocabulary is a local closed
// constant. The drift test asserts its KEYS are a subset of STATUS_LABELS in
// apps/web-platform/lib/types.ts, which it reads as text. That proves the vocabulary exists,
// not that the illustration's meaning matches the product's (see the mapping note below).

// Status key -> the word the illustration shows. The KEYS are the product's
// ConversationStatus keys; the WORDS are deliberately illustrative ("failed" is the nearest
// product key to "stopped at a gate", but the product's own label for it is "Needs
// attention"), so the section never reads as the hosted Command Center.
export const STATUS_LABELS = {
  completed: "Done",
  failed: "Stopped",
  waiting_for_user: "Waiting on you",
};

const REQUIRED_FIELDS = ["department", "status", "line"];
const FRAME_STRING_FIELDS = [
  "label",
  "tag",
  "heading",
  "figureName",
  "briefEyebrow",
  "briefText",
  "linkText",
];

export function validateFanout(rows, departmentKeys, statusLabels = STATUS_LABELS) {
  if (!Array.isArray(rows) || rows.length !== 4) {
    throw new Error(
      `fanoutDemo: expected exactly four rows, found ${Array.isArray(rows) ? rows.length : typeof rows}`,
    );
  }
  const seen = new Set();
  rows.forEach((row, i) => {
    const n = i + 1;
    for (const field of REQUIRED_FIELDS) {
      if (typeof row?.[field] !== "string" || row[field].trim() === "") {
        throw new Error(`fanoutDemo: row ${n} is missing field "${field}"`);
      }
    }
    if (!departmentKeys.includes(row.department)) {
      throw new Error(
        `fanoutDemo: row ${n} department "${row.department}" is not a department in agents.js (${departmentKeys.join(", ")})`,
      );
    }
    if (seen.has(row.department)) {
      throw new Error(`fanoutDemo: row ${n} lists department "${row.department}" twice`);
    }
    seen.add(row.department);
    if (!Object.hasOwn(statusLabels, row.status)) {
      throw new Error(
        `fanoutDemo: row ${n} status "${row.status}" is not one of ${Object.keys(statusLabels).join(", ")}`,
      );
    }
  });
}

// The frame is everything around the rows: the label, tag, heading, figure name, brief card,
// link and the two caption lines. The caption carries the "illustrative, not a live run"
// disclosure, so an emptied or renamed caption must fail the build, not render a bare figure.
export function validateFrame(frame) {
  for (const field of FRAME_STRING_FIELDS) {
    if (typeof frame?.[field] !== "string" || frame[field].trim() === "") {
      throw new Error(`fanoutDemo: frame is missing field "${field}"`);
    }
  }
  const caption = frame.captionLines;
  if (
    !Array.isArray(caption) ||
    caption.length !== 2 ||
    caption.some((l) => typeof l !== "string" || l.trim() === "")
  ) {
    throw new Error("fanoutDemo: frame captionLines must be exactly two non-empty strings");
  }
  if (!frame.figureName.startsWith("Illustrative example")) {
    throw new Error('fanoutDemo: frame figureName must start with "Illustrative example"');
  }
  if (!caption[0].startsWith("Illustrative example")) {
    throw new Error('fanoutDemo: first caption line must start with "Illustrative example"');
  }
}
