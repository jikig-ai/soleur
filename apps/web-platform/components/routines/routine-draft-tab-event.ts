// Window event the guided tour dispatches to switch the Routines surface to its
// "Draft a routine with Concierge" tab so the creation composer can be spotlit.
// Same decoupled pattern as NEW_ISSUE_DIALOG_EVENT / RAIL_EXPAND_EVENT: the tour
// drives component-owned UI without importing its state. detail: { open: boolean }
// — open → show the draft tab, close → return to the default Routines tab.
export const ROUTINE_DRAFT_TAB_EVENT = "soleur:routine-draft-tab";

export interface RoutineDraftTabEventDetail {
  open: boolean;
}
