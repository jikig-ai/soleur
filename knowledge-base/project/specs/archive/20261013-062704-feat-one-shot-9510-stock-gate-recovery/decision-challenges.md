# Decision challenges — feat-one-shot-9510-stock-gate-recovery

Headless one-shot run; Taste/User-Challenge findings are recorded here instead of pausing
(pipeline rule). Nothing blocking — one direction note for the record:

- **Item A option choice (per issue instruction "pick one in the plan with rationale"):**
  chose option 2 — documented + tested post-destroy recovery (re-dispatch re-creates from the
  retained volumes, stock gate re-read at failure time, failure class named). Option 1
  (create-before-destroy via a transient second host) was cut: a `hcloud_volume_attachment`
  binds one server, the standby-topology shape was retired at #6575, and it is far beyond the
  issue's ~500-line scope. Rationale is in the plan's Proposed Solution + Cut List.
