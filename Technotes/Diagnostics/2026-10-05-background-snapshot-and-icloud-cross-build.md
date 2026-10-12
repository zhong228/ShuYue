# 離開 App 跳夜間、iCloud 新書消失（2026-10-05）

## 回報

TestFlight 測試者，兩台 iPhone：新機用 TF，舊機用 App Store 2.0.6。

1. 更新 TF 後，看書時會突然跳回主頁；離開 App 再回來會跳成夜間模式、排版變位。關掉「主題切換 › 跟隨系統」之後，就不再跳夜間、也不再變位。更新前開著它，只有外觀會跟著系統。
2. 在新機加了幾本書、改了排版，隔天打開，新加的書不見了，頁首頁尾也變回舊機的樣子。
3. 兩台都用商店版時，在新機換書源後，舊機會出現同一本書兩次。
4. 希望同步頁有「上傳」「下載」兩個按鈕。使用者決定先不做。

## 一、離開 App 跳夜間：App 切換器快照

在模擬器重現（iPhone 18 Pro Max／iOS 27）：

- 步驟：跟隨系統開、裝置深色 → 開書（閱讀器跟著變深色）→ 手動按「白天」→ 按 Home → 回到 App → 閱讀器變回深色。
- 重現後，`yd_reader_follow_system_theme` 被改回 true。

log 顯示，進背景後 UIKit 會替 App 切換器拍快照，過程中把 trait 翻成相反外觀再翻回來（`interface style 2 -> 2`、`1 -> 1`、`2 -> 2`，約 0.3 秒內），SwiftUI 把每一次翻轉都送給 View：

- `ReaderView` → `alignReaderDarkMode`：淺色快照被當成「裝置轉成淺色了」，原本手動設定的白天因此恢復跟隨；接著深色快照把閱讀器拉回深色。
- `ContentView` → `appearanceOnScreen` → `synchronizeAppearanceThemeExtras`：穿上另一個外觀的主題與閱讀設定（單獨設定深色主題時差異最大），閱讀器每次進背景都多重排兩次（`layoutGeneration … cause=refreshTransaction`）。

為什麼「更新前只是外觀跟隨」：111 的 `readerFollowSystemTheme` 沒存過時是 false；8f525aef（112 起）改成沒綁定閱讀主題時，閱讀器自己跟裝置深淺色（09-30 的決定）。關掉跟隨系統之後，`.preferredColorScheme` 把外觀釘住，快照翻不動環境裡的深淺色，所以就沒事。

修法：`ScenePhase.showsDeviceAppearance`（`!= .background`）。`GlobalSettings.alignReaderDarkMode(deviceIsDark:in:)` 與 `noteAppearanceOnScreen(_:in:)` 都要帶 phase，背景裡不動作。回到非背景 phase 時再對齊一次，所以在背景期間真的換了外觀，回來時仍會套上。

驗證：

- `ReaderBackgroundBindingTests.leavingTheAppKeepsAModeSetAgainstTheDevice`
- `AppearanceThemeWriteBackTests.snapshotsInTheBackgroundDoNotWearTheOtherAppearancesTheme`

把閘門拿掉時，正好這兩個測試失敗。模擬器照同樣步驟再走一次：回來仍是白天、同一頁，log 裡沒有外觀翻轉，也沒有重排。

XCUITest 版做不成：在測試宿主下，App 進背景 60 秒都沒被暫停（Firebase GDT 的背景工作、WebKit 程序），沒有訊號可以等。

「看書中跳回主頁」**沒有重現**。前景切深淺色、進出背景，閱讀器都還在。

## 二、iCloud：2.0.6 與新版共用同步紀錄

兩個缺陷疊在一起（以 git 歷史核對；2.0.6 ≈ 66d80644，三個 09-13 的 commit 同步程式碼相同）：

1. **2.0.6 的雜湊不穩定。** `stableHash` 沒有 `.sortedKeys`（113 自 09-23 的 14c7a441 起才有），同一個值每次編碼的鍵順序都不同。所以 2.0.6 每次同步都把手上每一項蓋成 `now`：它的副本贏下每一個衝突，對它手上有的項目也不接受遠端刪除。
2. **每個版本（含 HEAD）都先存 shadow、再套用合併結果。** 套用會在這些時候沒發生：
   - 書架在同步往返期間變了，`snapshotForSync` 因 revision 改變而拒絕。翻一頁、聽書每唸一段、啟動時的檢查更新，都會讓 revision 改變。
   - 上傳時拋錯。
   - App 被暫停。

   這時剛到的遠端新書已經記在 shadow 裡、本機卻沒有。下一輪 `resolveMerge` 把它當成「本機刪除」，發出 `now` 時間的墓碑；遠端修改也會被這台的舊副本以 `now` 蓋回去。

兩台都是 2.0.6 時，缺陷 1 掩蓋了缺陷 2：假墓碑贏不了。但真正的刪除也永遠傳不過去，於是換源後留下的那一本（見下）在舊機永遠刪不掉，就是回報 3。

113 修好雜湊之後，開始忠實執行 2.0.6 送來的假墓碑，新機新加的書因此被刪掉，就是回報 2；而 2.0.6 每次都把它的頁首頁尾蓋成 `now`，所以舊機的版面一直贏。

另外，`applyReaderBarLayoutFromSync` 沒有標「同步套用中」，所以對方的版面會被記成這台自己的「頁首頁尾」閱讀設定，並以 `now` 送給其他裝置。

修法：

- **只在套用之後才提交 shadow**（`ICloudSyncManager.shadowToCommit`）。`mergeType` 改為接收 `applyLocally`。套用被拒時，只提交本機快照已經跟合併結果一致的項目，也就是這台自己隨上傳送出的新增、修改、刪除；遠端來、還沒套用的項目維持舊的 shadow，下一輪再套。測試：`ICloudSyncShadowCommitTests`。修法拿掉時其中三個失敗：兩種情境下遠端新書被刪，一種情境下遠端修改被蓋回。
- **同步套用頁首頁尾時不記成本機編輯**（`isApplyingReadingSettingsSync`）。測試：`ReadingSettingsSyncTests.aLayoutFromAnotherDeviceIsNotNotedAsSetHere`。
- **新版改用 `_v2` 同步紀錄**（使用者選擇）。合併的 8 份紀錄與 shadow 鍵都換新名字：書源、替換規則、氣泡樣式、氣泡選擇、閱讀背景、閱讀設定、頁首頁尾、書架。2.0.6 與 TF ≤113 繼續用舊紀錄，彼此照舊同步，但影響不到新版。
- **單向收下舊版新加的書**（`adoptBooksAddedByOlderBuilds`，相容層）。
  - 只收 `books_meta` 裡活著、而且這台從沒見過的 id：不在本機紀錄、不在舊 shadow、不在新 shadow。舊紀錄的墓碑、修改、時間戳一律不收。
  - 書以原本的 id 放上書架，舊機升級後就是同一本。
  - 先抓不含附件的 change tag（`desiredKeys = []`），有變才下載；先只解碼 id，有新書才完整解碼。
  - 進背景時不跑。
  - 失敗時記 log、不擋這次同步。
  - **刪除條件**：沒有任何拆分前的 build 還會寫 `books_meta`。
  - 測試：`OlderBuildBooksTests`。
- **「立即閱讀」的試讀書不進書架、不同步**（使用者選擇）。
  - 試讀書改為書架外的閱讀紀錄。開始離線下載時，它會被放上書架並留下（`ensureOnlineBookForDownload`）。
  - App 在閱讀中被結束而留下的試讀紀錄，下次會重用，不會再另建一筆。
  - `onlineBook(sourceId:bookInfoURL:)` 只找書架上的書，符合它原本的註解。
  - 測試：`TrialReadingRecordTests`。

### 代價

- 舊機升級之前，兩台的修改互不相通；新版只會收下舊機新加的書。
- 舊機升級後第一次同步會合併兩邊書架。期間在新機刪掉、舊機還有的書，若舊機最後開啟它的時間比刪除晚，會再回來。
- 測試者在新機被刪掉的書救不回來：雲端是墓碑，舊機也從沒套用過。頁首頁尾要在新機重新設定。

## 三、順手發現：766702ba 讓有聲書載不到章節（未推送，已修）

目錄拆到 `BookChapterStore` 之後，書架紀錄不帶 `onlineChapters`。

但 `AudiobookPlayer.currentBook()` 從 `store.books` 取書，而 `ChapterFetchManager.fetchChapter` 與 `LocalChapterAudioProvider` 都要讀 `book.onlineChapters`。所以書架上的有聲書（線上與本機）每一章都會失敗：線上是「找不到章節」，本機是 missingAudio。

改成 `AudiobookPlayer.playingBook` → `readingBook(id:)`。測試：`BookChapterStorageTests.audiobookPlayerSeesTheTableOfContents`。

已逐一檢查專案裡所有讀 `onlineChapters` 的地方，其餘的書都取自 `readingBook(id:)`、啟動時傳入的副本或剛建立的書。

## 四、下載失敗不再當成雲端是空的

`downloadRecords` 原本用 `try?`，以下三種情況都回空陣列：

- 抓取失敗
- 附件拿不到
- 兩種格式都讀不懂

同步於是把「雲端什麼都沒有」拿去合併，再用這台的內容蓋掉雲端那份。只存在其他裝置的項目，要等它們下次上傳才回來。

現在只有「紀錄不存在」才算空的：

- 抓取失敗會拋錯，那一步同步中止，什麼都不上傳、不提交。
- 附件拿不到（CloudKit `assetFileNotFound`／`assetNotAvailable`，或紀錄沒有附件）拋 `missingAsset`。
- 讀不懂拋新的 `unreadableSyncData`，五種語言都有訊息，並記下兩種格式各自的解碼錯誤。

解讀這一段抽成 `decodeCloudSyncBlob`，測試是 `ICloudSyncBlobDecodingTests`：用舊行為時，「讀不懂要拋錯」那個測試失敗。

「刪除 iCloud 上的資料」：

- 抓取失敗：中止，免得以為全刪了。
- 某份資料讀不懂或缺附件：列不出它記錄的書檔，但仍刪掉它本身，那些書檔會留在雲端。讀不懂的資料會讓每次同步失敗，刪除是唯一出路，不能也被它擋住。

## 沒做／未驗證

- 兩台真機 iCloud 互傳：模擬器沒有登入 iCloud，只用合併邏輯的單元測試與程式碼核對。
- Firestore 的 `pullCollection` 也是先存 shadow，但資料同步已關閉（`dataSyncEnabled = false`），不會執行。
- `ICloudSyncManager` 的 `backup()`／`restore()`／`syncAfterSignIn()` 沒有呼叫點，是死碼。
