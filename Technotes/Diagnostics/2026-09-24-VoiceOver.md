# 2026-09-24 VoiceOver diagnostics and repairs

Input: `yuedu-diagnostics-20260924-203554.txt`, app 2.0.7 (103), iPhone17,5, iOS 27.2 (24B5089g).

## Confirmed findings

- The two exported crash payloads are identical, including PID 2382 and the complete call stack. They are duplicate records of one watchdog event, not evidence of two independent crashes.
- At the exported crash timestamp 20:35:39, the recorded reason is `0x8BADF00D`, `WatchdogEvent: process-exit`, `WatchdogVisibility: Background`, signal 9: the app failed to terminate gracefully within 5 seconds. This confirms forced termination. It does not identify the start or cause of the user's preceding foreground stalls.
- The initial local device dSYM did not match. The subsequently downloaded Xcode Cloud Build 103 Archive contains the exact app image UUID `1F34E945-6DCF-317E-83F6-01EDD2137065`, confirmed with `dwarfdump --uuid`.
- Symbolicating the attributed thread with that dSYM identifies `ReaderView.buildBody` (ReaderView.swift:2515) → `detectedTTSSpeakers` (ReaderView+SourceChange.swift:1086) → `aiBookAdapter` (line 1200) → `AISourceManifest.digest` (AISourceSnapshot.swift:25) → Foundation / Swift allocation / malloc. This identifies synchronous AI/TTS source preparation during SwiftUI evaluation in the captured watchdog stack. It does not establish a memory leak or every cause of foreground lag.
- Symbolication evidence is saved at `/tmp/yuedu-build103-symbolicated.txt`. The extracted DWARF binary is under `/tmp/yuedu-build103-symbols/`; the original archive remains in Downloads/Xcode Cloud Artifacts.
- The log explicitly records `voiceOver=true` for a 45 ms TTS switch. That measurement does not explain the reported severe continuous lag.
- QQ TOC parsing reached 2280 ms at 20:24:44; a loaded online book later reports 13,209 total pages. `books_meta` upload size reached 19,001,920 bytes, and launch sync reports 995 sources. These establish the workload, but none proves the watchdog's root cause.
- Gateway session restoration failed at 20:34:25. `/v1/subscription/bind` repeatedly failed decoding, including 20:19:49 and 20:35:50. The latter is a subscription response problem; it is not evidence that a nickname PUT failed. External source APIs also returned HTTP 502.

## Repairs

- Shelf list books use the same single semantic description as grid books. Default activation opens the book; detail, edit, and delete are custom accessibility actions. Native List multi-selection is retained in edit mode.
- Explore used to overlay its NavigationStack on a still-mounted browser. A real Explore → detail → reader UI test exposed the covered browser's URL field/WebView alongside reader controls; Contents existed but was not hittable. The browser now mounts only when foreground; BrowserState retains its WKWebView so its page survives switching home. The final UI regression requires the covered address field to be absent, bottom controls to be hittable, and tapping Contents to open the chapter list.
- The profile sync cloud is decorative and the badge is one status element.
- Nickname edits are persisted per account before publication. Auth refresh preserves the profile name; pending edits win over remote pulls. Pulls arriving after an intervening edit/acknowledgement cannot overwrite the name. Uploads snapshot their inputs and are serialized; only an acknowledgement of the matching revision clears pending status. The Firebase direct route waits for the server acknowledgement. An edit left pending after failure is retried through the existing push path on the next foreground activation or sign-in. Failure is surfaced through sync state/logs, and no duplicate view-owned upload is issued.

## Verification boundaries

Use simulator regression evidence for UI hierarchy, hit testing, navigation, and persistence/race behavior. These checks do not establish real-device VoiceOver speech, rotor gesture behavior, or a measured improvement in all reported continuous stalls. The later symbolicated-stack repair below removes a confirmed synchronous hot path; an end-to-end absence of watchdogs on the reporting device has not been verified. No physical device was used.

Final simulator run: `/tmp/yuedu-accessibility-final.log`, `xcodebuild` exit 0 and `** TEST SUCCEEDED **`; 14 tests passed (5 AccountDisplayNameTests, 6 ReaderSettingsPublicationTests, and 3 production-path UI tests for Explore controls, search/detail return/re-entry, and a combined shelf-list book opening). This run built the normal project against its resolved dependencies. Localization validation passed for all three languages, and `git diff --check` passed. The later BrowserState comment correction changes no runtime behavior.

## Build 103 symbolicated-stack repair

When no gathered source existed, `aiBookAdapter()` synchronously built an entire manifest from the TOC. The TTS sheet evaluated it twice for detected speakers, once for the panel adapter, and once for progress. Each manifest hashed every title, formatted digest bytes through Foundation, and serialized/hashes the whole manifest again. With thousands of entries this work repeats during UI updates. Even a valid gathered source required repeated serialization of the entire source context just to test identity.

The presentation path now returns an explicit pending state with no source evidence until acquisition completes, and uses the existing value-based source identity to reuse the gathered snapshot. It never creates a whole-book manifest during body evaluation. Full snapshot construction runs in a detached task from frozen input, with cancellation and generation/source checks before publication. Role detection runs in a lifecycle task keyed by chapter, reading position, and source fingerprint; it no longer reads/publishes character-card state during body construction. The role destination shows loading while source evidence is pending; ordinary playback controls remain available. Hash semantics and source boundaries are unchanged.

Before/after workload: 13,209 empty online TOC entries, four unprepared presentation reads, same simulator/toolchain Debug configuration. The original production constructor took 984.735 ms (`/tmp/yuedu-ai-presentation-before.log`). The repaired production presentation resolver took 0.588 ms (`/tmp/yuedu-ai-presentation-after.log`). `SourcePerfTrace` records both measurements. This measures removal of redundant UI work, not a real-device frame-rate guarantee. The prepared-source regression verifies the background builder produces exactly the same manifest and fingerprint, respects the read prefix, rejects mismatched source/book identities, and propagates cancellation. Background trace reports `main=false`.

Final repair verification: `/tmp/yuedu-ai-watchdog-final.log`, exit 0 and `** TEST SUCCEEDED **`. All 27 tests passed: 3 presentation/snapshot XCTest cases, 22 source-identity/AI-boundary/TTS-cast tests, and 2 production-path UI tests (Explore reader controls and TTS panel → role destination). The final four-read benchmark measured 0.274 ms; background snapshot logging again showed `main=false`. Localization validation and `git diff --check` passed. No claim is made about device-wide VoiceOver latency outside this measured path.
