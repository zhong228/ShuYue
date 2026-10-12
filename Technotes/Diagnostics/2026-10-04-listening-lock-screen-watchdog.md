# 聽書一息屏就崩（2026-10-04）

## 回報

同一位測試者（iPhone 14 Pro Max／iOS 27.2）10-03 20:45 起送出 6 筆 TestFlight 崩潰回饋，全部是 2.0.7 (112)，App 執行 7–18 秒就崩。留言是「额，书多卡崩了」「习以为常的卡崩」。使用者補充：真人有聲、線上 TTS、系統 TTS 都是**一息屏就崩**。

TestFlight 匯出的 6 個 zip 只有 `feedback.json`，沒有崩潰日誌。Organizer 的 build 112 只有 10-03 的兩類崩潰（`uniqueDeviceCountFilteredForLast24Hours = 0`），今天這幾筆還沒彙整進去。Organizer 的「崩潰」也不收看門狗終止。

## 證據

測試者匯出的 `yuedu-diagnostics-20261004-142122.txt`（build 113）裡有一筆 MetricKit 崩潰：

- `0x8BADF00D`，`scene-update watchdog transgression … exhausted real (wall clock) time allowance of 10.00 seconds`
- `ProcessVisibility: Background`，`WatchdogEvent: scene-update`

用 Xcode Cloud build 113 的 archive 符號化。dSYM UUID `376B6CE6-52F8-3071-9A9B-80B1E7136D1B` 與診斷檔完全吻合，主執行緒堆疊如下：

```
FrontBoardServices 場景更新 → CA commit → UIKit layout → SwiftUI graph update
→ yuedu_appApp.body closure #5（yuedu_appApp.swift:221，scenePhase 的 onChange）
→ BookStore.flushPendingMetadataSave() → saveMetaImmediately() → persistMetadataIfChanged()
→ BookStore.encodeBooksMetadata()（BookStore.swift:2327）→ Foundation JSONEncoder → memmove
```

同一份 log 記到 `books_meta` 為 **138,139,871 bytes**，書架只有 110 本。15 分鐘內 iCloud 背景同步上傳了 5 次這 138 MB。

## 根因

每本線上書的完整目錄（`onlineChapters`）都存在 `books_meta.json` 裡。七貓聽書每章 URL 約 2,000 字元，光遇聚合每章是 330 字元的 `data:` URL，一本 2,000 章的書光目錄就 4 MB。任何一本書的任何一點變動，都會在主執行緒把整份重新編碼：

- 閱讀進度
- 聽書每念一段
- 每快取一章的 `cachedFilename`

息屏的那次場景更新裡，`scenePhase` 進入 inactive／background，觸發 `flushPendingMetadataSave()`。同時 `sync(reason: "background")` 也開始編碼並上傳 138 MB。背景 App 的 CPU 與 I/O 優先權又被系統壓低，於是超過 10 秒，被看門狗殺掉。

聽書特別容易崩的原因：

- 聽書會一直排存檔，所以息屏那一刻一定有一筆待寫。
- App 聽書時在背景繼續執行。
- 不聽書時，App 一進背景就被暫停，待寫的存檔通常兩秒前就寫完了。

## 為什麼看起來是 112 才開始

build 與 commit 的對應，依 `origin/main` 的推送紀錄與 archive 的 `CreationDate`：

| build | commit | 時間 |
|---|---|---|
| 111 | `c03877be` | 09-30 01:03 |
| 112 | `8f59789e` | archive 10-02 19:36 |
| 113 | `ac27198b` | archive 10-03 15:53 |

`c03877be..8f59789e` 之間，下列程式碼都沒有改動：

- 存書架、離開前景的強制存檔（`7c06e14d`，09-28 就在 111 裡）
- iCloud 背景同步
- `Modules/Core/TTS`
- 有聲書播放器
- 離線下載

閱讀器深色模式也查過了：舊版 103 進背景時會因淺色／深色快照重排兩次（`layoutGeneration 1→2→3`），113 不會。

所以崩不崩取決於書架檔的大小，不是 112 的退化。沒有這位測試者在 111 上的資料，無法直接證明 111 也會崩。

## legado 的做法（legado-E、legado-with-MD3、huajideshutiao 三個分支一致）

- `books` 表與 `chapters` 表分開。章節主鍵是 `(url, bookUrl)`，`(bookUrl, index)` 唯一，刪書時 `ForeignKey.CASCADE` 一併刪除。
- 存進度只在背景 executor 更新那一本書的那一列（`ReadBook.saveRead` → `book.update()`）。
- 刷新目錄只對那一本做 `delByBook` + `insert`。
- 書本記錄帶摘要（`totalChapterNum`、`latestChapterTitle`），書架不讀目錄；開書時才 `getChapterList(bookUrl)`。
- 備份的 `bookshelf.json` 不含章節表。

## 修法

- **`BookChapterStore`**（新）：每本書的目錄是 `books_meta.chapters/<id>.json`。按本讀取，最多快取 8 本，未寫入的變動不會被淘汰。只寫有變動的那本，由下一次書架存檔一起寫入。
- **書架記錄不帶目錄**：`replaceRecords` 是唯一入口，附在書上的目錄一律移進 `chapterStore`，記錄改帶 `totalChapterNum`、`latestChapterTitle`。`ReadingBook` 不再編碼 `onlineChapters`，但仍讀得懂舊格式。
- **按需讀取**：`readingBook(id:)` 開書時掛上目錄。閱讀器、漫畫、聽書、AI 閱讀、線上管線都經由它取書。也可以直接用 `chapters(for:)`。
- **改用摘要或按本讀取的地方**：書架下載進度、下載管理、啟動檢查更新改用摘要；AI 整理書架、離線下載的 reconcile 與 `runBook` 改成按本讀取。
- **搬遷**：載入時遇到內嵌目錄（舊檔，或降版後由舊版寫回）一律以內嵌為準。先把目錄寫出去，再寫不帶目錄的書架。沒有摘要但磁碟上有目錄的書（WebDAV 還原、舊版改寫過的檔），從目錄補回摘要。
- **刪除**：刪書時一併刪除目錄。同步套用或完整載入後，清掉不在書架與閱讀紀錄中的書的目錄；只有這次書架和閱讀紀錄都完整讀到時才清。
- **iCloud**：上傳時不帶目錄與摘要（`withoutTableOfContents`）。同步來的副本不會取代本機目錄；只有本機沒有目錄、而舊版上傳的雲端資料裡帶著時，才收下。Firestore 與 WebDAV 原本就經由 `strippedForSync` 去掉目錄，現在也一併去掉摘要。

## 驗證

測試環境：Xcode 27.0、iPhone 18 Pro Max／iOS 27.0 模擬器，`scripts/xctest.sh`，不平行執行。

- `BookChapterStorageTests`：修前 6 個結構測試中有 5 個失敗（另一個「舊版內嵌優先」修前本來就成立）。修後 11 個行為測試全部通過；基準測試需設 `TEST_RUNNER_YUEDU_SHELF_BENCHMARK=1` 才會跑。
- 相關 49 個 suite 共 490 個 Swift Testing 測試，加上 7 個 XCTest：只有 `yuedu_appTests` 的 `htmlBuilderPreservesDecorativeBlockWithWhitespaceContent` 與 `coreTextPageViewRendersBackgroundImagePixels` 失敗。這兩個是 09-19 起的既有失敗，與本次無關。

基準：同一份合成書架，與測試者同規模（22 本 × 2,000 章 × 約 2,000 字元 URL，加 88 本 × 900 章 × 330 字元 `data:` URL，共 133,099,986 bytes），Debug、模擬器：

| | 修前 | 修後 |
|---|---:|---:|
| 離開前景存檔（`updateCachedChapter` + `flushPendingMetadataSave`） | 417 / 417 / 416 ms | 12 / 12 / 10 ms |
| 重新開啟書架 | 3,851 ms | 2 ms |
| 開一本書（讀出 2,000 章目錄） | 0 ms（已全部常駐記憶體） | 8 ms |
| 第一次載入 | 3,909 ms | 4,194 ms（含一次性搬遷：寫出 110 個目錄檔） |

另以 `swiftc -O` 在 Mac 上量 JSONEncoder：同規模全書架 402 ms，不含目錄的書架 43 KB 小於 1 ms，單本 4.4 MB 目錄 8 ms。

## 界線

- 數字來自模擬器 Debug 與 Mac `-O`。裝置在背景、受 I/O 節流時的實際耗時沒有量到，要等新版的 MetricKit 確認看門狗不再出現。現在每次存書架都會留下 `⏱ library.shelf.save`／`library.chapters.write`（≥5 ms 才記）。
- 升級後第一次啟動會一次性搬遷（解碼舊檔，寫出各本目錄）。
- 降版回舊 build 時，舊版看不到書架檔裡的目錄，開書時會重新抓；再升級時以舊版寫回的內嵌目錄為準。
- 新裝置從 iCloud 還原後，目錄要開書時才從書源抓（舊版上傳過的雲端資料除外）。
- 啟動時的「檢查更新」對每本書仍是先抓網路、再合併舊目錄（保留 `cachedFilename` 與每章變數）。legado 用檔案是否存在來判斷快取（`BookHelp.hasContent`），我們仍記在目錄裡，所以每快取一章就會重寫那一本的目錄。
