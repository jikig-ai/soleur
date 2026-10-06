// Homepage section "one brief reaches the departments" (#9577). Static, illustrative,
// fictional: the company, brief and statuses are invented for the illustration and are not a
// live run or a customer result.
//
// DEFAULT EXPORT ONLY. Eleventy unwraps a data module's default export only when it is the
// sole export; a second named export would hand the template the export object, skip this
// function and its validation, and render an empty section on a green build. The validator
// lives in plugins/soleur/lib/fanout-validate.js for that reason.
//
// Status words are illustrative at key level only: each `status` is a product
// ConversationStatus key, each `label` is this section's own word for it (see the mapping in
// fanout-validate.js). A bad row throws here, at Eleventy build time, naming the row and key.

import agentsData from "./agents.js";
import { STATUS_LABELS, validateFanout } from "../../lib/fanout-validate.js";

const ROWS = [
  {
    department: "legal",
    status: "completed",
    label: "Done",
    line: "Draft terms and privacy notice changes, for review by you and a qualified lawyer.",
  },
  {
    department: "marketing",
    status: "completed",
    label: "Done",
    line: "Launch post and customer email drafted for your approval.",
  },
  {
    department: "finance",
    status: "waiting_for_user",
    label: "Waiting on you",
    line: "Needs your answer: set the add-on price from the sample cost figures, or hold it until costs are clearer?",
  },
  {
    department: "engineering",
    status: "failed",
    label: "Stopped",
    line: "Reminders change held back. A test did not pass. You decide what happens next.",
  },
];

export default function () {
  const { domains } = agentsData();
  validateFanout(
    ROWS,
    domains.map((d) => d.key),
    STATUS_LABELS,
  );
  const nameByKey = new Map(domains.map((d) => [d.key, d.name]));
  return {
    label: "How a brief reaches the departments",
    tag: "Illustrative example · sample data",
    heading: "Example: one brief reaches the departments it concerns, and you keep the final say.",
    figureName:
      "Illustrative example with sample data: one founder brief and the status each of four departments reports back",
    briefEyebrow: "Founder brief",
    briefText:
      "A small software company is adding shared reminders to its app. Launch it to current customers as a paid add-on.",
    captionLines: [
      "Illustrative example with sample data. Not a live run, a product screenshot or a customer result.",
      "Agent output is a draft for you to review and approve. Soleur does not guarantee that any test or review will catch every problem.",
    ],
    linkText: "See every department below",
    rows: ROWS.map((r) => ({ ...r, name: nameByKey.get(r.department) })),
  };
}
