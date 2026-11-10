# Healing Log

## [HEAL-20261110-001] guarded_design_marker_replace

**Logged**: 2026-11-10T03:32:30-05:00
**Status**: verified
**Trigger**: tool-failure
**Active-Context**: design review, editing a draft specification
**Area**: documentation tooling
**Priority**: low

### Failure

Two `functions.edit` attempts to insert a design subsection failed with `No replacement was performed ... failed to find the lines to replace`. The first hunk did not supply the full expected surrounding context; the second placed preceding/following lines in the wrong order. No text was changed by either attempt. The initial check for `.learnings/HEALS.md` also found that the file did not exist. On 2026-11-10, two later plan-edit attempts again failed exact-context matching (one had a mismatched task heading; another anchored to a long paragraph); the plan stayed unchanged until guarded replacement.

### Diagnosis

The edit operation uses complete-line context and requires exact existing lines in their actual file order. The chosen anchors did not match the plan's Markdown section context; inspection confirmed the text was present and neither failed patch partially changed the document.

### Fix

Switched away from patch hunks to guarded Python marker replacements. Both recoveries asserted exact marker counts before writing; for the implementation plan, eight unique replacements were applied only after each old marker occurred exactly once.

### Verification

The guarded plan update completed successfully. Automated checks confirmed all 10 task headings in order, the correct nested `FeatureScript::InjectionTime` type, valid `ios_chrome_unittests`/`ios_web_unittests` runner names, the hard initializer gate before Task 9, a final newline, and no trailing whitespace. No product source was changed.

### Metadata

- Related Files: `docs/superpowers/specs/2026-11-10-aloha-ios-userscripts-webextensions-design.md`
- Pattern-Key: `docs.patch_context_mismatch`
- Recurrence-Count: 2
- First-Seen / Last-Seen: 2026-11-10

---
## [HEAL-20261110-002] spec_validation_case_mismatch

**Logged**: 2026-11-10T03:39:30-05:00
**Status**: verified
**Trigger**: tool-failure
**Active-Context**: design review, validating the userscript compatibility floor
**Area**: documentation verification
**Priority**: low

### Failure

The content-update command exited non-zero with `AssertionError: missing required spec item: manual update checks`. The design text had already been written; the immediate post-write verification failed.

### Diagnosis

The assertion was case-sensitive and searched for the lowercase string `manual update checks`, while the document intentionally starts that sentence with `Manual update checks`. This was a false negative in the verification expression, not missing design content.

### Fix

Adjusted the verification input to the exact sentence capitalization (`Manual update checks`) without changing the specification text.

### Verification

Re-read the saved compatibility section and reran all five content checks with the exact capitalization. Every required phrase was present, and the whitespace check reported no trailing whitespace. Workspace status showed only the design and recovery-log files; no product source was edited.

### Metadata

- Related Files: `docs/superpowers/specs/2026-11-10-aloha-ios-userscripts-webextensions-design.md`
- Pattern-Key: `docs.validation_case_mismatch`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---

## [HEAL-20261110-003] scoped_recurrence_marker_update

**Logged**: 2026-11-10T03:51:30-05:00
**Status**: verified
**Trigger**: tool-failure
**Active-Context**: recovery logging after a guarded documentation update
**Area**: documentation verification
**Priority**: low

### Failure

The first attempt to update the existing `docs.patch_context_mismatch` recurrence count aborted with `guard failed: expected one occurrence, found 2: - Recurrence-Count: 1`. The guard ran before file write, so the log was unchanged.

### Diagnosis

Two existing HEAL entries legitimately contain the same recurrence count. A file-global replacement was ambiguous; the guard prevented updating the wrong entry.

### Fix

Anchor the count replacement to the adjacent unique `Pattern-Key: docs.patch_context_mismatch` plus `Recurrence-Count: 1` lines, and keep the ambiguity-catch as a separate entry.

### Verification

The scoped replacement and append completed; assertions confirmed the original pattern count is 2, this entry is present exactly once, and both the plan and log have final newlines with no trailing whitespace.

### Metadata

- Related Files: `.learnings/HEALS.md`, `docs/superpowers/plans/2026-11-10-aloha-ios-userscripts-webextensions.md`
- Pattern-Key: `docs.guarded_replace_ambiguous_marker`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---
## [HEAL-20261110-004] missing_generated_chromium_build_inputs

**Logged**: 2026-11-10T04:02:00-05:00
**Status**: pending-verify
**Trigger**: env-issue
**Active-Context**: userscript parser implementation, host-side syntax verification
**Area**: iOS build environment
**Priority**: medium

### Failure

`g++ -std=c++20 -I. -fsyntax-only ios/chrome/browser/userscripts/model/userscript_parser.cc` exited 1 because `base/debug/debugging_buildflags.h` was absent. A temporary generated-flag shim outside the checkout exposed a second absent generated header, `base/fuzzing_buildflags.h`; after a temporary shim for that header, compilation stopped at missing `partition_alloc/pointers/raw_ptr_exclusion.h`. There is no `out/` GN build directory, and `gn`, `autoninja`, and `xcodebuild` are unavailable.

### Diagnosis

The checkout has not had its Chromium GN build outputs and required third-party dependency checkout (PartitionAlloc) provisioned. This is an environment/build-graph limitation, not evidence that the parser translation unit compiles or fails under the actual iOS target.

### Fix

No generated or third-party headers were added to the repository. Temporary buildflag shims were kept under `/tmp/aloha-host-generated/` and do not represent the Chromium build configuration. The product build remains pending a macOS/Xcode checkout with dependencies and GN output configured.

### Verification

The real Chromium-header syntax check remains blocked and is not marked passed. As a limited logic check, the parser implementation compiled with a temporary `base::expected` adapter outside the repository and passed 28 assert-based parser smoke checks. Required platform verification: on macOS, configure the simulator output and run `ios/tools/run_unittests.py --out-dir out/Debug-iphonesimulator --test-target ios_chrome_unittests --gtest_filter='UserScriptParserTest.*'`; acceptance is a successful native test run.

### Metadata
- Related Files: `ios/chrome/browser/userscripts/model/userscript_parser.cc`, `ios/chrome/test/BUILD.gn`
- Pattern-Key: `env.missing_chromium_generated_and_third_party_inputs`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---

## [HEAL-20261110-005] avoid_cxx20_keyword_as_field_name

**Logged**: 2026-11-10T04:02:00-05:00
**Status**: verified
**Trigger**: tool-failure
**Active-Context**: userscript parser implementation, portable C++ smoke verification
**Area**: C++ model
**Priority**: low

### Failure

The temporary host parser compile failed because `requires` was used as a field name in `userscript.h` and as a member expression in `userscript_parser.cc`; C++20 reserves `requires` as a language keyword.

### Diagnosis

The parser target uses the repository's C++20 language mode. The metadata field name was invalid independently of the unavailable GN build inputs.

### Fix

Renamed the field to `require_urls` in `userscript.h` and updated the `@require` parser assignment.

### Verification

Compiled `userscript_parser.cc` with g++ 13 using an isolated temporary adapter for the missing Chromium `base::expected` include chain, ran the assert-based host harness, and observed `28 parser smoke assertions passed`; the chained `git diff --check` exited successfully.

### Metadata
- Related Files: `ios/chrome/browser/userscripts/model/userscript.h`, `ios/chrome/browser/userscripts/model/userscript_parser.cc`
- Pattern-Key: `cpp.reserved_keyword_identifier`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---

## [HEAL-20261110-006] checkdeps_baseline_violations

**Logged**: 2026-11-10T04:13:30-05:00
**Status**: pending-verify
**Trigger**: tool-failure
**Active-Context**: userscript matcher implementation, repository dependency validation
**Area**: build/checkdeps
**Priority**: low

### Failure

`python3 buildtools/checkdeps/checkdeps.py --root=.` exited 1 after scanning the full checkout. It reported numerous illegal includes in existing Aloha/Chromium files, including `aloha/src/native/...` with “Because of no rule applying,” and unrelated Blink includes. The full diagnostic was saved at `/home/ubuntu/terminal_full_output/2026-11-10_09-12-12_719741_412.txt`.

### Diagnosis

This repository-wide check is blocked by existing include-rule violations outside the userscripts feature. Filtering the completed output with `rg 'ios/chrome/browser/userscripts'` returned no matches, so none of the new userscripts paths appeared among the reported violations. The check is still not green and the full output does not establish whether all targeted layering constraints are correct.

### Fix

No unrelated Aloha/Chromium include rules or source files were changed. The new userscripts code was left unchanged; a bounded checkdeps mode for only the new paths was not available from the script's CLI.

### Verification

The completed full-repository output was filtered for `ios/chrome/browser/userscripts`; no userscripts-specific violation was present. Required follow-up: on the configured checkout run `python3 buildtools/checkdeps/checkdeps.py --root=.` and resolve/confirm the baseline include-rule failures; acceptance is exit code 0. This entry remains pending because the repository-wide check did not pass.

### Metadata
- Related Files: `ios/chrome/browser/userscripts/model/`, `.learnings/HEALS.md`
- Pattern-Key: `repo.checkdeps_baseline_violations`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---

## [HEAL-20261110-007] checkdeps_feature_include_rules

**Logged**: 2026-11-10T05:29:30-05:00
**Status**: pending-verify
**Trigger**: tool-failure
**Active-Context**: Settings and toolbar integration, dependency validation
**Area**: build/checkdeps
**Priority**: low

### Failure

`python3 buildtools/checkdeps/checkdeps.py` exited 1 and reported newly introduced illegal includes from the Settings controllers, profile-pref registration, keyed-service registry, and `ChromeWebClient` into `ios/chrome/browser/userscripts/...`.

### Diagnosis

The parent `ios/chrome/browser/DEPS` rules prohibit broad cross-module includes. The modified subdirectories lacked filename-scoped exceptions for the feature's exact dependency edges. The same full-tree run also reports unrelated existing Aloha/Chromium violations.

### Fix

Added only file-scoped include permissions in `ios/chrome/browser/settings/ui_bundled/DEPS`, `ios/chrome/browser/shared/model/prefs/DEPS`, `ios/chrome/browser/profile/model/DEPS`, and `ios/chrome/browser/web/model/DEPS`; no broad browser-wide allowlist was added.

### Verification

Re-ran `python3 buildtools/checkdeps/checkdeps.py`. It still exited 1 because of unrelated existing Aloha/Blink include violations, but the captured `feature_path_errors` filter for userscripts, Settings, prefs, profile model, and web model was empty. Status remains pending because the full checker did not exit 0 and the repository has no bounded checker target for only the changed paths.

### Metadata
- Related Files: `ios/chrome/browser/settings/ui_bundled/DEPS`, `ios/chrome/browser/shared/model/prefs/DEPS`, `ios/chrome/browser/profile/model/DEPS`, `ios/chrome/browser/web/model/DEPS`
- See Also: HEAL-20261110-006
- Pattern-Key: `repo.checkdeps_feature_include_rules`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---

## [HEAL-20261110-008] invalid_source_view_range

**Logged**: 2026-11-10T05:29:30-05:00
**Status**: verified
**Trigger**: tool-failure
**Active-Context**: WKWebExtension package-load probe
**Area**: source inspection
**Priority**: low

### Failure

Two file reads used requested ranges beyond their file lengths: the plan was read from line 178 although it ends at 161, and `base/files/file_util.h` was read from line 935 although it ends at 797.

### Diagnosis

The assumed line positions were stale/incorrect; the tool rejected the ranges before returning file content.

### Fix

Read the plan's actual Task 8 range (lines 125–134) and used a targeted symbol search for `WriteFile` instead of guessing the utility-header line range. Updated the package test to check the boolean `base::WriteFile` result.

### Verification

The corrected plan read returned Task 8's acceptance criteria. `rg` located the actual declaration at `base/files/file_util.h:588`: `WriteFile(const FilePath&, std::string_view)` returns `bool`; the test assertion now uses `ASSERT_TRUE`.

### Metadata
- Related Files: `docs/superpowers/plans/2026-11-10-aloha-ios-userscripts-webextensions.md`, `base/files/file_util.h`, `ios/chrome/browser/web_extensions/runtime/wk_web_extension_package_load_unittest.mm`
- Pattern-Key: `tool.invalid_source_view_range`
- Recurrence-Count: 2
- First-Seen / Last-Seen: 2026-11-10

---

## [HEAL-20261110-009] file_append_existing_file_fallback

**Logged**: 2026-11-10T05:29:51-05:00
**Status**: verified
**Trigger**: tool-failure
**Active-Context**: recovery logging during package-probe implementation
**Area**: file tooling
**Priority**: low

### Failure

`functions.write` with `append=true` returned `The file that you're trying to overwrite already exists` for the existing `.learnings/HEALS.md`, so the new recovery notes were not written.

### Diagnosis

The append operation did not accept this existing-file target in the current tool call; no partial overwrite occurred.

### Fix

Switched to a V4A patch anchored to the existing final metadata lines and appended the entries without rewriting earlier recovery history.

### Verification

The patch applied. An initial substring-based occurrence check exited 1 because the searched token also matched cross-reference text; a header-anchored check (`^## \\[HEAL-20261110-00[789]\\]`) confirmed entries 007, 008, and 009 each have exactly one heading. The earlier entries 001–006 remain present exactly once.

### Metadata
- Related Files: `.learnings/HEALS.md`
- Pattern-Key: `tool.append_to_existing_file`
- Recurrence-Count: 1
- First-Seen / Last-Seen: 2026-11-10

---
