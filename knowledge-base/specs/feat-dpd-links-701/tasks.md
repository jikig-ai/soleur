# Tasks: fix DPD intro paragraph links (#701)

## Phase 1: Core Fix

### 1.1 Fix Eleventy source intro links
- [ ] Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` line 29
- [ ] Change `[Terms and Conditions](/docs/legal/terms-and-conditions.md)` to `[Terms and Conditions](/pages/legal/terms-and-conditions.html)`
- [ ] Change `[Privacy Policy](/docs/legal/privacy-policy.md)` to `[Privacy Policy](/pages/legal/privacy-policy.html)`

### 1.2 Fix root source copy intro links
- [ ] Edit `docs/legal/data-processing-agreement.md` line 20
- [ ] Change `[Terms and Conditions](/docs/legal/terms-and-conditions.md)` to `[Terms and Conditions](terms-and-conditions.md)`
- [ ] Change `[Privacy Policy](/docs/legal/privacy-policy.md)` to `[Privacy Policy](privacy-policy.md)`

## Phase 2: Verification

### 2.1 Confirm no residual broken paths
- [ ] Search both DPD files for any remaining `/docs/legal/` paths -- expect zero matches
- [ ] Verify footer "Related Documents" links are unchanged in both files

### 2.2 Build verification
- [ ] Run Eleventy build to confirm no broken link warnings for the DPD page
