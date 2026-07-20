// Window event the guided tour dispatches to open/close the New Issue dialog so
// its in-modal controls (manual "Create issue" + "Create with Concierge") can be
// spotlit. Mirrors the RAIL_EXPAND_EVENT pattern: a component-owned piece of UI
// exposes a window CustomEvent the tour can drive without importing its internals.
// detail: { open: boolean }.
export const NEW_ISSUE_DIALOG_EVENT = "soleur:new-issue-dialog";

export interface NewIssueDialogEventDetail {
  open: boolean;
}
