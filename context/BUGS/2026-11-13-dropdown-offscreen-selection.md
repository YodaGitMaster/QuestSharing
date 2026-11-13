# 2026-11-13 — Dropdown wheel left keyboard selection off screen

**Status**: solved
**Severity**: low
**Tags**: EquipmentUI.lua dropdown drawMenu cursor offset viewport wheel Enter keyboard

## Symptom
- In new 0.4.7 dropdowns, wheel scrolling could move the focused option off screen; Enter selected that hidden option.
- Expected: Enter selects a visibly focused option.

## Reproduction
- Open the Slot dropdown, wheel down, then Enter without clicking an option.
- Both modern/classic workflow cases failed before correction (28/30 passed).

## Root cause
- Viewport offset and keyboard cursor were independently clamped only to the whole list.
- Trap category: state/lifecycle mismatch between navigation modes.

## Methodology (reusable)
1. Mix input modes in one workflow: wheel, then keyboard confirmation.
2. Compare the visible first option with the value committed by Enter.
3. Clamp keyboard focus to the visible slice whenever the dropdown redraws; preserve list bounds for empty/short results.

## Fix
- EquipmentUI.lua drawMenu clamps cursor to offset+1 through offset+10 and available options.
- Regression in tests/test_usability.py; 30/30 usability checks passed after correction.
- No workaround; released with v0.4.7.

## Verification
- Released at `13d718f8212f084b7748c8f311d8ea5a2113664d`, v0.4.7; 29 suites / 1,121 checks passed and published ZIP byte-matched.
- Failed-before/passed-after cases on both API styles; full suite and release verification in context/state.md.

## If it shows up again
- Audit viewport, selection and confirmation together whenever another navigation mode is introduced.
