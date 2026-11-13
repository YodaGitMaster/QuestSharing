# 2026-11-13 — Unreadable cursor treated as empty

**Status**: solved
**Severity**: high
**Tags**: SpellRanks.lua GetCursorInfo pcall cursor drag action bar spell rank data loss

## Symptom
- Observed during unreleased 0.4.10 fault injection: GetCursorInfo threw while the player held an item; the initial updater attempted to pick up a spell anyway.
- Expected: no pickup, placement or cursor clear without a confirmed empty cursor.
- Environment: Lua 5.1, modern/legacy client API mocks; no native game execution.

## Reproduction
- Put item 77 on cursor, make GetCursorInfo throw, enable automatic rank updates; inspect pickup count and original cursor payload.
- New test failed on the working modern enumeration path before correction; the legacy zero-spec defect initially masked its mutation path.

## Root cause
- Shared protected-call helper returned nil for both successful empty reads and thrown errors. Treating both as an empty cursor removed the guard.
- Trap category: falsy/null trap; boundary validation conflated unavailable state with confirmed absence.

## Methodology (reusable)
1. Test the guard with occupied, empty and unreadable states separately; successful-path tests cannot establish safe behavior on API failure.
2. Assert no mutation calls, not merely the final slot value.
3. Preserve pcall's success flag at the decision boundary and fail closed for missing/unreadable combat or cursor APIs.
4. Verify pickup identity and action-slot readback; exercise no-op, refusal, combat transition and unexpected mutation independently.

## Fix
- Files changed: QuestSharing/SpellRanks.lua; tests/test_spell_ranks.py.
- Add cursorState with explicit readability, require combat-read capability, and defer on combat API errors.
- Pause on refused/unconfirmed swaps; retain cursor on unexpected slot mutation for manual recovery.
- Release: v0.4.10; no workaround.

## Verification
- Dedicated suite 44/44 passes across both API styles, including occupied/unreadable cursor, combat beginning during pickup, no-op placement, wrong pickup and unexpected mutation.

| Wanted | Done | Match |
|---|---|---|
| Preserve unreadable occupied cursor | Zero pickups, original item retained | ✅ |
| Apply normal confirmed upgrades | Verified cursor and placement workflow | ✅ |

| Quality check | Result |
|---|---|
| Only planned module/tests affected | ✅ |
| Reproduced before correction | ✅ |
| Modern and legacy paths verified | ✅ |
| No unrelated API/helper refactor | ✅ |

## If it shows up again
- Trace success flags independently from API values. Every cursor-mutating path must prove empty ownership before pickup and read back placement before discarding swapped content.

## Addendum 2026-11-13 — Slot ownership across pickup callbacks
- New unreleased boundary case: a synchronous cursor event handler from another addon replaced slot 1 with a macro during spell pickup; initial implementation still placed into the stale target.
- Original empty-cursor guard remains correct; it did not validate target ownership across pickup's synchronous event boundary.
- Reproduction asserts no PlaceAction call for the intercepted slot, not only the final value (a later callback could restore the macro and mask the overwrite). Both API styles failed before correction.
- Fix: read target type/ID/subtype again after pickup and combat checks; if changed, release our picked-up spell and skip the slot. Modern and legacy workflow checks pass after correction.
- Status: solved; original and added ownership checks are covered in the expanded 48-check suite.
