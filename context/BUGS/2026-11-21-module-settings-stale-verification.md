# 2026-11-21 — Module settings made verification assertions stale

**Status**: solved
**Severity**: low
**Tags**: Modules.lua, Diagnostics.lua, Settings.lua, test_log.py, test_look.py, module_, Tools, stale assertions

## Symptom
- Observed: test_full_report_has_one_setting_per_line_and_complete_messages fails at tests/test_log.py:335 and test_every_tab_has_a_short_intro_and_sections at tests/test_look.py:61, on modern/classic mocks.
- Expected: complete one-per-setting report and General headings including the requested Tools section pass verification.
- Environment: cutpdf source a37c9d7, Lua 5.1 through lupa; v0.4.30 release verification.

## Reproduction
- Run tests/test_log.py and tests/test_look.py; initial results 49/51 and 42/44.

## Root cause
- Test report matcher allowed letters only, excluding all 14 module_<id> keys. Heading expectation predated the Tools section. Runtime report/layout were already correct.
- Trap category: type vs runtime mismatch (test assumptions versus new setting identifiers/layout).

## Methodology (reusable)
1. Read module decision D17 and search prior bug reports before changing code.
2. Reproduce each failure independently with a full Python traceback, not the runners' abbreviated AssertionError.
3. Compare raw report keys against NS.defaults: all 113 keys exist exactly once; old matcher sees 99, excluding exactly the module keys. Inspect actual General headings: Start here, Tools, Messages and sounds, During a fight.
4. Disconfirm a runtime omission before patching. Update identifier grammar and assert exact key set plus uniqueness; update the explicit heading list.
5. Rerun both complete affected suites; retain full-run results for the unchanged suites.

## Fix
- Files changed: tests/test_log.py, tests/test_look.py; runtime unchanged.
- Commit / PR: included in v0.4.30 source release tag.
- Workaround? no.

## Verification
- Full initial run: 72 suites / 3,034 checks, four stale-assertion failures.
- Affected reruns: report 51/51, layout 44/44; combined all 3,034 checks pass. Runtime 69 Lua 5.1 compilations pass; whitespace clean.

## If it shows up again
- Inspect actual keys/headings before assuming runtime output is missing. Keep exact set/uniqueness assertions; do not weaken coverage to a count alone.
