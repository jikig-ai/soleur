/**
 * The words that presume a TERMS text (#12344, CLO ruling C): the card wording for an acknowledgement text and the shared deck may
 * contain none of them. ONE regex, imported by legal-copy.test.ts and card-ack.test.tsx, so the two suites cannot drift (a copy in
 * each file let either side lose an alternative with both suites green).
 */
export const TERMS_PRESUMING = /\bterms?\b|\baccept(ed|s|ance)?\b|\bupdated\b/i;
