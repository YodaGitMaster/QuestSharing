# 2026-11-13 — Zone ranges were enabled without opting in

**Status**: solved
**Severity**: low
**Tags**: Core.lua zoneLevels optional default SavedVariables migration opt-in Extra tools

## Symptom
- Observed: v0.4.11 enabled world-map questing ranges by default; user clarified "always as optional thing".
- Expected: Extra tools additions remain off until explicitly enabled, including after updating the already auto-enabled install.
- Environment: fresh or existing v0.4.11 SavedVariables; Lua 5.1, modern and legacy harnesses.

## Reproduction
- Start fresh, or start with QuestSharingDB={zoneLevels=true,dbVersion=3}; open the map without choosing the toggle.
- Before correction: fresh default, saved-true migration and Reset checks failed on both API styles (28/34 passed).

## Root cause
- The feature request was interpreted as permission to enable the layer by default; missing-default migration then persisted true. Merely changing the default would retain that saved true value.
- Trap category: scope/lifecycle and persisted-state mismatch.

## Methodology (reusable)
1. Verify both the source default and actual SavedVariables load path; test a fresh install and a previously enabled release separately.
2. Distinguish a one-time migration from a permanent override so future user choices are not erased on every login.
3. Add a dedicated migration marker outside user defaults, reset the old auto-enabled state once, then preserve explicit choices.
4. Verify Reset returns the feature to off while retaining the migration marker; the next opt-in must survive reload.

## Fix
- Files changed: QuestSharing/Core.lua, tests/test_zone_levels.py; docs/version updated for 0.4.12.
- Default zoneLevels=false; once-only zoneLevelsOptInMigrated marker. dbVersion stays 3; rendering and toggle behavior unchanged.
- Standing preference for all future Extra tools additions recorded in context/decisions.md.

## Verification
- 34/34 zone-level workflows pass, including fresh default, old saved true, explicit re-enable/reload, Reset and existing rendering behavior.

| Wanted | Done | Match |
|---|---|---|
| Feature optional on fresh and updated installs | Default off and once-only migration | ✅ |
| Explicit choices survive reload | Migration marker preserves later values | ✅ |
| Reset keeps feature optional | Resets to false without clearing marker | ✅ |

| Quality check | Result |
|---|---|
| Only planned runtime default/load path changed | ✅ |
| Reproduced before correction | ✅ |
| Both API styles verified | ✅ |
| Renderer unchanged; no broad refactor | ✅ |

## If it shows up again
- Check whether a new default was already saved by an earlier release; default-only edits do not migrate old values. Never let a one-time migration overwrite future explicit opt-ins.
