# 2026-11-18 — Auto-sell gray items "not implemented" (silent when off)

**Status**: workaround (hint added; not confirmed in game)
**Severity**: low
**Tags**: autoSellGray, sellgray, BagTools.lua, MERCHANT_SHOW, gray items not sold, vendor, sell junk, default off

## Symptom
- Observed: user opened a vendor, no gray items were sold, concluded the feature was not implemented.
- Expected: gray items sold at the vendor.
- Where: QuestSharing/BagTools.lua (MERCHANT_SHOW handler, T.sellGray, sellNext); Core.lua ns.defaults.autoSellGray.
- Environment: 0.4.22 source; private realm, game interface 16001. No SavedVariables on the dev Mac, so the user's real setting value could not be read.

## Reproduction
- Fresh install (autoSellGray = false) → MERCHANT_SHOW → nothing sold, nothing printed.

## Root cause
- The feature works (harness sells with `/qs sellgray on`), but it is off by default and returned silently, so it looked missing.
- Trap category: config/default — silent no-op on a disabled opt-in.

## Methodology (reusable)
1. Confirm the code is in the shipped build (toc + dist zip contents), and check the setting's default in ns.defaults.
2. Read the whole path MERCHANT_SHOW → sellGray → grayItems → sellNext and every guard (enabled, setting, merchantReady, isBlocked, bookmark, quest-item, noValue, sell price 0).
3. Look for user evidence: bug.txt / `/qs doctor` (blocked features, setting values, "sell" log lines). Here bug.txt was 0.4.21, so it was useless.
4. Reproduce both states in the harness; the only silent no-op was "off".
5. Fix pattern: a disabled opt-in that the user can hit says so once (one hint per session, with the command to turn it on).

## Fix
- Files changed: QuestSharing/BagTools.lua (once-per-session hint on MERCHANT_SHOW when off and sellable grays exist), tests/test_bagtools.py.
- Commit / PR: uncommitted.
- Workaround? The real-game cause is unconfirmed (could also be a blocked "autosell" feature).

## Verification
- tests/test_bagtools.py 78/78; whole suite has no FAIL lines.

## If it shows up again
- With the setting ON and still nothing sold: ask for `/qs doctor` and check "features blocked" for autosell (UseContainerItem refused → ADDON_ACTION_BLOCKED), the "sell" log line, and whether MerchantFrame is replaced by another addon (merchantReady checks MerchantFrame:IsShown()).
- Gray items a quest "needs" (ns.bagItemFor) or with no sell price are skipped on purpose.
