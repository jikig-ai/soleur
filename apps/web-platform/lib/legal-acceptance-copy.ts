/**
 * Copy deck for the founder legal-acceptance card and its in-place email check (#12011 PR-C, ADR-319).
 *
 * Source: wireframes 10 to 16 in knowledge-base/product/design/approvals (screenshots), with the variances listed under
 * the plan's Product/UX Gate findings (no password or provider step; "Taken back by your team" dropped).
 *
 * A pure leaf: no runtime imports (a type-only import is erased), so the client card, the dialog and the server pages can
 * all read it. Never import KEY_RE or anything from `server/` here.
 *
 * PROVISIONAL: the CLO agent signed off the wording and the retention period on 2026-11-07 as a v1 internal position that
 * stands in for counsel on the operator's instruction (ruling persisted in
 * knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md). The CPO agent signed off the deck on
 * 2026-11-08 (`signOff.cpo`; the ruling is in knowledge-base/project/specs/feat-one-shot-founder-acceptance-followups-12365/decision-challenges.md).
 * Human lawyer review is still owed: no human lawyer has reviewed it, so `PROVISIONAL` stays true. The two notices below are carried WORD FOR WORD from
 * knowledge-base/legal/audits/2026-11-founder-legal-acceptance-dsar-and-notice-note.md, sections (c) and (c-2), and carry
 * the ruled period. `test/legal-acceptance/legal-copy.test.ts` pins the notices to that file byte for byte, pins
 * `PROVISIONAL` and `signOff`, pins every kind wording word for word, and fails on any string that claims more than
 * happened ("verified", "reviewed", "legally binding", "audit-ready", "compliant"). Changing any wording needs a CLO ruling and the
 * test edit in the same diff.
 *
 * Two deck-owned wordings (#12344): a text of kind `terms` is accepted as terms; a text of kind `acknowledgement` is only
 * acknowledged. The kind is declared per text key in `LEGAL_TEXT_KIND`; a key with no declared kind has NO wording and the
 * card renders nothing (no default, CTO ruling 2026-11-07). The shared `LEGAL_COPY` holds only wording that is neutral for
 * both kinds.
 *
 * Honesty rules: a card says how the answer was given and never claims more than happened. An answer is final: the way
 * to change it is a new version of the text sent by the team (task 6.10), so there is no undo anywhere in this deck.
 */

import type { LegalCardStateWire } from "@/lib/legal-acceptance-wire";

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] as const;

/** "Wed 4 Nov 2026, 10:42 UTC". Empty for an unparseable value. Fixed arrays, not Intl: the same string on every runtime. */
export function formatLegalUtc(iso: string | null | undefined): string {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "";
  const d = new Date(t);
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${DAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}, ${hh}:${mm} UTC`;
}

/** "Fri 14 Nov 2026" for a YYYY-MM-DD date. Empty for anything else. */
export function formatLegalDate(ymd: string | null | undefined): string {
  if (!ymd || !/^\d{4}-\d{2}-\d{2}$/.test(ymd)) return "";
  const t = Date.parse(`${ymd}T00:00:00Z`);
  if (Number.isNaN(t)) return "";
  const d = new Date(t);
  return `${DAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

/** "customer-terms" becomes "Customer terms": the registry carries a key, not a title. */
export function legalTextLabel(key: string): string {
  const words = key.split("-").join(" ");
  return words.length === 0 ? words : words.charAt(0).toUpperCase() + words.slice(1);
}

/** The accepted line: from the stored email-code confirmation time. Without a time it never invents one. */
export function confirmedWithCodeLine(reauthAt: string | null | undefined): string {
  const when = formatLegalUtc(reauthAt);
  return when ? `Confirmed with an email code, ${when}` : "Confirmed with an email code.";
}

const CHOICE_WORDS = {
  accept: "said Yes",
  decline: "said No",
  request_changes: "asked for changes",
} as const;

export const LEGAL_COPY = {
  PROVISIONAL: true,
  signOff: {
    cpo: "Ruled by CPO agent, 2026-11-08: card deck wording, states and wireframe variances (structure and copy; no rendered export) for the founder-acceptance-record text; entry point ruled separately" as string | null,
    clo: "Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel" as string | null,
  },

  /** (c) of the counsel note: shown with the Request changes text box, visible without scrolling or clicking. */
  requestChangesNotice:
    "Say only what you want changed in the text. Please do not write names, email addresses or private details about yourself or anyone else here: this note is saved with your decision, up to 1000 characters, and is kept for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open), even if you later delete your account.",
  /** (c-2) of the counsel note: shown on the card above the choices, for every choice. */
  cardNotice:
    "Your decision is saved with your account identifier, the text's version and fingerprint, the time, and (for Yes) the time you confirmed the emailed code. Jikigai keeps this record to be able to show later what was decided, even if you delete your account, for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open). You can ask what we hold, ask for erasure or restriction, or object by writing to <legal@jikigai.com>, and you can complain to the CNIL.",

  signedInLine: "Signed in with your account.",
  /** Task 6.10: an answer cannot be taken back from the card. The way to change it is a new version. */
  finalNote: "An answer is final once recorded. To change it, your team sends a new version of the text.",
  alreadyAnswered: "This card was already answered, possibly in another tab. This is what was recorded.",
  howGivenHeading: "How this answer was given",
  exactTextHeading: "The exact text your answer covers",
  seeTheText: "See the exact text",
  textMeta: (label: string, version: string) => `${label}, version ${version}`,
  versionMeta: (version: string, written?: string) => (written ? `Version ${version}, written ${written}.` : `Version ${version}.`),
  fingerprint: (hash: string) => `Text fingerprint ${hash.slice(0, 12)}`,

  whatYourAnswerDoes: "What your answer does",
  yesRow: { label: "If you say Yes" },
  noRow: { label: "If you say No" },
  changesRow: { label: "If you ask for changes" },

  answerHeading: "Your answer",
  noDefault: "No answer is chosen for you. Pick one.",
  choices: {
    yes: { label: "Yes", hint: "Final once recorded. We check it is you first with an email code." },
    no: { label: "No", hint: "Nothing changes." },
    changes: { label: "Request changes", hint: "Say what you want changed first." },
  },

  scroll: {
    keep: "Keep scrolling to the end of the text.",
    reached: "You reached the end of the text.",
    fits: "The whole text is on screen.",
    checkbox: "I have read the full text.",
    checkboxLocked: "(Unlocks at the end of the text.)",
  },
  lock: {
    atEnd: "Yes is locked. It opens after you scroll to the end of the text and tick the box above.",
    needsTick: "Yes is locked. Tick the box above to open it.",
    open: "Yes is open. We check it is you with an email code before anything is recorded.",
  },

  changes: {
    label: "What should change? (required)",
    placeholder: "Say what you want changed, in your own words.",
    required: "Required. Write what you want changed. We cannot save an empty request.",
    counter: (used: number, max: number) => `${used} / ${max} characters`,
    send: "Save my request",
    cancel: "Cancel",
  },

  decline: {
    heading: "Say No?",
    body: "Nothing changes. This answer is final: to change it later, your team sends a new version of the text.",
    confirm: "Record No",
    cancel: "Cancel",
  },

  pending: {
    badge: "Needs your answer",
    openUntil: (ymd: string) => `Open until ${formatLegalDate(ymd)}, end of day UTC`,
    howGiven: "Not answered yet. If you say Yes, we first check it is you with a code sent to your email.",
  },
  declined: {
    badge: "Declined",
  },
  changesRequested: {
    badge: "Change requested",
    title: "You asked for changes",
    noteHeading: "Your note",
  },
  replaced: {
    badge: "Replaced by a new version",
    title: (version: string, currentVersion: string) => `Version ${version} was replaced by version ${currentVersion}`,
    earlierAnswer: (choice: keyof typeof CHOICE_WORDS) => `Your earlier answer stays on record as you gave it: you ${CHOICE_WORDS[choice]}.`,
    needsOwnAnswer: (currentVersion: string) => `Version ${currentVersion} needs its own answer.`,
    open: (currentVersion: string) => `Open version ${currentVersion}`,
  },
  expired: {
    badge: "Expired",
    title: "Nobody answered in time",
    howGiven: "No answer was given.",
  },

  errors: {
    /** A genuine 4xx from our own route: the request was refused, so nothing was written. Never used for a 5xx, a 429 or a lost reply. */
    nothingRecorded: "Nothing was recorded. Try again shortly, or ask your team for help if this keeps happening.",
    /** A 5xx, a 429, a timeout or a lost or unreadable reply: a row can be committed behind any of them, so the card does not guess. */
    unknownResult: "We could not confirm what happened. Reload this page to see whether your answer was recorded before you try again.",
    replaced: "A new version of this text exists, so nothing was recorded. Reload this page to read the new version.",
    expired: "This text is no longer open for answers. Nothing was recorded.",
    reload: "Reload this page",
  },

  dialog: {
    ariaLabel: "Confirm it is you",
    startKicker: "One quick check before Yes is recorded",
    startTitle: "Confirm it is you",
    startBody: (email: string | null) =>
      email
        ? `We will email a code to ${email}. You stay signed in, and you come back to this same card.`
        : "We will email a code to your account email address. You stay signed in, and you come back to this same card.",
    answerSummary: "Your answer: Yes. Final once recorded.",
    sendCode: "Send me a code",
    sendNewCode: "Send me a new code",
    resendWait: "Please wait a little before asking for a new code.",
    sendingCode: "Sending",
    cannotGetCode: "I cannot get the code",
    help: "If the code does not arrive, check your spam folder, then ask your team for help. There is no other way to confirm it is you from this card, and nothing has been recorded.",
    goBack: "Go back. Do not record anything.",
    codeKicker: "Check your email",
    codeTitle: "Enter the code we emailed you",
    codeBody:
      "The code works for about 10 minutes. The email may say the code is for signing in: use it here. Nothing is recorded until your code is checked.",
    codeSent: "If that address can receive email, a code is on its way.",
    codeLabel: "Code from your email",
    codeHint: "6 to 8 digits",
    confirmAndRecord: "Confirm and record Yes",
    confirming: "Checking",
    sendError: {
      rate_limited: "Too many codes were requested. Please wait about 15 minutes, then try again. Nothing was recorded.",
      already_recorded: "This card already has an answer. Nothing more was recorded. Reload this page to see it.",
      replaced: "A new version of this text exists, so nothing was recorded. Reload this page to read the new version.",
      unavailable: "We could not send the code. Nothing was recorded, try again shortly.",
    },
    verifyError: {
      wrong_code: "That code is wrong or has expired. Codes only work for about 10 minutes. Check it, or send a new one. Nothing was recorded.",
      locked: "Too many tries. Please wait a few minutes before asking for a new code. Nothing was recorded.",
      expired: "That code has expired. Send a new one. Nothing was recorded.",
      replaced: "A new version of this text exists, so nothing was recorded. Reload this page to read the new version.",
      code_stale: "The confirmation is too old. Send a new code. Nothing was recorded.",
      unavailable: "We could not check the code. Nothing was recorded, try again shortly.",
    },
    /** The server no longer counts the email check (HTTP 403 reverify): back to the first step. */
    reverify: "Nothing was recorded. Please ask for a new code and try again.",
    decideError: {
      code_expired: "The confirmation is too old. Send a new code. Nothing was recorded.",
      replaced: "A new version of this text exists, so nothing was recorded. Reload this page to read the new version.",
      expired: "This text is no longer open for answers. Nothing was recorded.",
    },
  },

  page: {
    title: "Your answer on a legal text",
    allTexts: "All texts",
  },

  /** The index page (frame 17 style): one plain line per text. */
  index: {
    title: "Texts waiting for you",
    empty: "Nothing is waiting for you.",
    state: {
      pending: "Needs your answer",
      declined: "You said No",
      changes_requested: "You asked for changes",
      replaced: "Replaced by a new version",
      expired: "Nobody answered in time",
    },
    notAvailable: "Answering is not available yet",
  },
} as const;

/** The kinds of legal text the card can present. Two deck-owned wordings; there is no default (#12344). */
export const LEGAL_TEXT_KINDS = ["terms", "acknowledgement"] as const;
export type LegalTextKind = (typeof LEGAL_TEXT_KINDS)[number];

/** The wording that depends on what a Yes means. Both kinds define every field. */
export interface LegalKindCopy {
  pendingTitle(label: string): string;
  yesBody: string;
  noBody: string;
  changesBody: string;
  changesFooter: string;
  pendingNothing: string;
  pendingNotAvailable: string;
  acceptedBadge: string;
  acceptedTitle(label: string): string;
  acceptedBody: string;
  declinedTitle(label: string): string;
  declinedBody: string;
  changesRequestedBody: string;
  expiredBody: string;
  answerDetail(label: string, version: string): string;
  indexAccepted: string;
}

export const LEGAL_KIND_COPY = {
  terms: {
    pendingTitle: (label: string) => `Accept the ${label}?`,
    yesBody:
      "Soleur treats these terms as accepted by you, starting today. Clicking again does not undo it. To change it later you would ask for a new version.",
    noBody: "Nothing changes. Nothing is accepted. Final once recorded.",
    changesBody: "Your note is saved with your decision. Nothing is accepted by asking for changes. Final once recorded.",
    changesFooter: "Nothing is accepted by saving this. Your note is saved with your decision.",
    pendingNothing: "Nothing has been accepted.",
    pendingNotAvailable: "Answering is not available yet. Nothing has been accepted.",
    acceptedBadge: "Accepted",
    acceptedTitle: (label: string) => `You accepted the ${label}`,
    acceptedBody: "Soleur now treats this version as accepted by you. To change this later, ask for a new version.",
    declinedTitle: (label: string) => `You said No to the ${label}`,
    declinedBody:
      "Nothing changed. Nothing was accepted. This answer is final: to change it, your team sends a new version of the text.",
    changesRequestedBody:
      "Nothing is accepted. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.",
    expiredBody: "Nothing was accepted. Ask your team to send it again if you still want it.",
    answerDetail: (label: string, version: string) =>
      `Accept the ${label}, version ${version}. Nothing is recorded until your code is checked.`,
    indexAccepted: "You accepted it",
  },
  acknowledgement: {
    pendingTitle: (label: string) => `Acknowledge "${label}"?`,
    yesBody:
      "Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version.",
    noBody: "Your No is recorded as your answer. The text stays as it is and nothing is acknowledged. Final once recorded.",
    changesBody: "Your note is saved with your decision. Nothing is acknowledged by asking for changes. Final once recorded.",
    changesFooter: "Nothing is acknowledged by saving this. Your note is saved with your decision.",
    pendingNothing: "Nothing has been acknowledged.",
    pendingNotAvailable: "Answering is not available yet. Nothing has been acknowledged.",
    acceptedBadge: "Acknowledged",
    acceptedTitle: (label: string) => `You acknowledged "${label}"`,
    acceptedBody:
      "Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version.",
    declinedTitle: (label: string) => `You said No to "${label}"`,
    declinedBody:
      "Nothing changed. Your No is recorded and the text stays as it is. This answer is final: to change it, your team sends a new version of the text.",
    changesRequestedBody:
      "Nothing is acknowledged. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.",
    expiredBody: "Nothing was acknowledged. Ask your team to send it again if you still want it.",
    answerDetail: (label: string, version: string) => `Acknowledge "${label}", version ${version}. Nothing is recorded until your code is checked.`,
    indexAccepted: "You acknowledged it",
  },
} as const satisfies Record<LegalTextKind, LegalKindCopy>;

/**
 * The kind of every registered text key. A key not listed has no kind, so no wording and no card. Adding a text to the registry
 * means adding its kind here (registry-pins.test.ts checks the two lists are the same set).
 */
export const LEGAL_TEXT_KIND: Readonly<Record<string, LegalTextKind>> = { "founder-acceptance-record": "acknowledgement" };

/** The declared kind of a key, or null. Own properties only: "constructor" and "__proto__" are valid keys and declare nothing. */
export function legalTextKind(key: string, declared: Readonly<Record<string, LegalTextKind>> = LEGAL_TEXT_KIND): LegalTextKind | null {
  return Object.prototype.hasOwnProperty.call(declared, key) ? declared[key] : null;
}

/** The wording for a key's declared kind (a member of LEGAL_KIND_COPY, never a new object), or null when the key declares none. */
export function legalKindCopy(key: string, declared: Readonly<Record<string, LegalTextKind>> = LEGAL_TEXT_KIND): LegalKindCopy | null {
  const kind = legalTextKind(key, declared);
  return kind === null ? null : LEGAL_KIND_COPY[kind];
}

/** The index line for a row: the kind's own wording for an accepted row, the shared wording for every other state. */
export function legalIndexState(kc: LegalKindCopy, state: LegalCardStateWire): string {
  return state === "accepted" ? kc.indexAccepted : LEGAL_COPY.index.state[state];
}

/** A title line that is safe to quote: starts alphanumeric, printable ASCII without a double quote, 1 to 120 characters. */
const SAFE_TITLE = /^[A-Za-z0-9][\x20\x21\x23-\x7e]{0,119}$/;

/** What the card calls the text. Terms keep the key-derived label; an acknowledgement text is called by its own first line when that line is safe to quote. */
export function legalDisplayLabel(kind: LegalTextKind, key: string, body: string): string {
  if (kind !== "acknowledgement") return legalTextLabel(key);
  const first = body.split("\n").map((l) => l.trim()).find((l) => l.length > 0) ?? "";
  return SAFE_TITLE.test(first) ? first : legalTextLabel(key);
}
