# 2026-11-13 — Visible page count omitted hidden spell slots

**Status**: solved
**Severity**: medium
**Tags**: SpellRanks.lua NUM_ACTIONBAR_PAGES MAX_ACTION_BUTTONS hidden form pages rank update

## Symptom
- Observed during unreleased 0.4.10 boundary tests: without MAX_ACTION_BUTTONS, six visible pages limited the rank scan to 72 slots; lower ranks on bonus/form/hidden slots remained.
- Expected: every normal native action slot participates, including hidden and form pages.
- Environment: Lua 5.1; six visible pages, 12 buttons/page, normal spell actions on slots 73 and 145.

## Reproduction
- Remove MAX_ACTION_BUTTONS, set NUM_ACTIONBAR_PAGES=6 and NUM_ACTIONBAR_BUTTONS=12, put lower-ranked learned spells on slots 73 and 145; enable automatic updates.
- Both API styles failed the new boundary case; initial expanded suite 44/48 before this and the pickup-callback ownership correction.

## Root cause
- The fallback treated visible page count as the complete action-slot domain; bonus/form/hidden slots are separate from the displayed-page count.
- Trap category: boundary / API runtime-shape mismatch.

## Methodology (reusable)
1. Put a valid action just past a reported UI boundary rather than testing only page one.
2. Remove the preferred API constant to exercise the actual fallback.
3. Compare scan limits with primary public action-slot integrations (Myslot scans 180 slots).
4. Read at least 180 standard slots; preserve larger native limits, cap unreasonable values and ignore unsupported read results.

## Fix
- Files changed: QuestSharing/SpellRanks.lua; tests/test_spell_ranks.py.
- Release: v0.4.10; no workaround or changes to action-bar layout.

## Verification
- Both API styles update slots 73 and 145 with the preferred constant absent; all 48 dedicated checks pass.

| Wanted | Done | Match |
|---|---|---|
| Hidden/form normal slots receive upgrades | Scan covers standard native slot range | ✅ |
| No blank or unrelated actions are changed | Existing action-type and learned-rank guards remain | ✅ |

| Quality check | Result |
|---|---|
| Only planned module/tests affected | ✅ |
| Reproduced before correction | ✅ |
| Modern and legacy paths verified | ✅ |
| Minimal boundary correction | ✅ |

## If it shows up again
- Audit slot-domain constants separately from displayed bars/pages; custom secure actions outside native slots are intentionally unsupported.
