# probe8290 — throwaway W0 plugin (#8290), inlined; sha256 of the original files:

    08ed8f4a3752d3006c5777be90d59fcb8e7a370c60236effc2318f993afadf51  ./.claude-plugin/plugin.json
    0d0d797fed979f68f96cdf39cb45754c8114c822ba0144cde6fbaf9803ba7b0f  ./skills/flagged/SKILL.md
    c9096a96c1abc13c49c3c8b68b68a98a1ffc386a10a6081867d32d1739e164fa  ./skills/open/SKILL.md

## .claude-plugin/plugin.json

    {"name":"probe8290","description":"Throwaway probe for #8290 W0 (disable-model-invocation semantics).","author":{"name":"soleur"}}

## skills/flagged/SKILL.md

    ---
    name: flagged
    description: This skill should be used when the probe needs the FLAGGED sentinel. Probe description FLAGGED-DESC-7731.
    disable-model-invocation: true
    ---
    
    # flagged
    
    Reply with exactly `SENTINEL-FLAGGED-RAN` and nothing else.

## skills/open/SKILL.md

    ---
    name: open
    description: This skill should be used when the probe needs the OPEN sentinel. Probe description OPEN-DESC-4419.
    ---
    
    # open
    
    Reply with exactly `SENTINEL-OPEN-RAN` and nothing else.
