# 本書覆寫設計：讓一本書有自己的閱讀設定

> 日期：2026-09-15
> 狀態：**大部分尚未實作。** 2026-09-15 已實作 §5 的存放與 §5.1 的固定頁收編（`BookReaderSettingsStore`），其餘仍是設計。
> 起因：對照 Reeden 後定下的優先序——先修「已有但接入不完整」的功能；自定義部分優先做「本書覆寫＋配置管理」（顯示繼承來源、可恢復全域，不先做多層自動規則）。
> 範圍：文字書閱讀器（`ReaderView`）與固定頁閱讀器（`FixedPageReader`：漫畫／PDF／固定版面 EPUB）。

## 0. 一句話

每本書可以只改幾項設定（例如字體和行距），其餘繼續跟著全域走。設定頁看得出每一項現在是「本書設定」還是「跟隨全域」，也能逐項恢復。所有「每本書」的閱讀設定只存在一個地方，合併也只在一個函式裡做。

## 1. 目標與非目標

**目標**

1. 覆寫是**稀疏的**：一本書只記它改過的欄位。沒改的欄位永遠讀全域**目前**的值，之後改全域，這些欄位跟著變。
2. 設定頁每一列用文字標示來源（不只靠顏色），可以逐項「恢復全域」，也可以一次全部恢復。
3. **只有一套每本書的存法**：把現有的 `fixedPage.readingMode.<書ID>` 收進來，之後不再有第二套。
4. **只有一個合併點**：所有需要「生效值」的地方都呼叫同一個合併函式，不各自判斷。
5. 從沒用過本書覆寫的使用者，升級後行為與現在完全相同。

**非目標（第一版不做）**

- 依語言、格式、分類、作者、主題自動套用的多層規則。
- Reeden 的「排版跟隨目前主題」範圍。
- 章節標題樣式、閱讀背景的本書覆寫（第二階段，理由見 §9）。
- 正則高亮、對話氣泡、段評氣泡、頁首頁尾、文字底線的本書覆寫（屬「配置管理」，第三階段）。
- 同步（第三階段，理由見 §7）。
- 依裝置（iPad／iPhone）區分設定。這是另一個維度，本設計不處理。
- 段首縮排：設定畫面與 `GlobalSettings` 裡**沒有**縮排設定，排版時寫死（例如 `NodeAttributedStringBuilder.swift:72`、`OnlineProviderAttributedStringBuilder.swift:614` 都是 `fontSize * 2`）。要先有全域設定，才談得上覆寫。

## 2. 參考：Reeden 怎麼做（只列文件讀得到的）

來源：docs.reeden.app/layout_scope（2026-09-15 讀取）。

- 排版設定的保存範圍分「全局」與「當前主題」兩種。
- 另有「本书专用主题」：開啟後，這本書使用自己的日間與夜間主題，不再完全跟隨全域主題。
- 「同步後沒生效」的排查順序：同步內容開關 → 這本書是否開了本書專用主題 → 兩台裝置是否用同一主題 → 字體與背景圖是否也在另一台 → 是否為 PDF 或 EPUB 自帶樣式。
- 建議先用全局，確定需要時才開本書專用主題。

我們借兩點：**「本書」是例外，不是預設**；以及**要讓使用者看得出為什麼沒生效**。不照搬「整套主題」的做法，改為逐項覆寫，因為要支援的例子是「英文小說只改字體和行距」。

## 3. 現況（程式碼事實）

### 3.1 全域設定存在哪

| 設定 | 存放 | 閱讀器讀的地方 |
|---|---|---|
| 字級、行距倍數、字距、段距倍數、左右／上下邊距、粗體、章節標題樣式、頁首頁尾開關與間距 | `GlobalSettings`（UserDefaults `yd_*`），`ReaderConfig` 另鏡射一份；排版欄位改動後合併 120ms 才寫回 `GlobalSettings`（`GlobalSettings.swift:296-431`） | `readerConfig.*` |
| 閱讀背景 `ReaderTheme` | UserDefaults，`ReaderTheme.persist()`（`GlobalSettings.swift:127-132`） | `readerConfig.theme` |
| 閱讀字體 | `GlobalSettings.selectedReaderFontPostScript`（`yd_reader_font_postscript`） | 見 §3.3 |
| 繁簡轉換、捲動模式、翻頁方式、直排、iPad 單雙頁 | `GlobalSettings` 的 `textConversion`、`scrollMode`、`pageTurnStyle`、`readerWritingMode`、`readerSpreadMode`（`GlobalSettings.swift:659-807`） | `settings.*` |
| 正則高亮、對話氣泡 | `GlobalSettings.regexHighlightConfiguration`、`dialogueBubbleStyle` | `settings.*` |
| 每個閱讀背景各自的文字顏色 | `GlobalSettings.readerTextColorOverrides`，以背景為鍵（`GlobalSettings.swift:688-700`） | `settings.*` |

外觀主題的 `AppearanceThemeExtras` **不含任何排版欄位**（`AppearanceThemeExtras.swift:152-211`：分頁圖示、啟動圖、預設封面、介面字體、玻璃效果、書架、閱讀介面顏色與圖示）。所以本書覆寫不會碰到「編輯設定時回寫目前主題」那套機制。

### 3.2 已經存在的「每本書」資料

| 資料 | 存放 | 現況問題 |
|---|---|---|
| 固定頁閱讀方向 | UserDefaults `fixedPage.readingMode.<書ID>`，舊鍵 `manga.readingMode.<書ID>`（`FixedPageReadingMode.swift:31-42`） | ① **只存方向**。裁邊、雙頁、封面單頁偏移、切分大圖、寬屏黑邊、原文字選取都不存，每次重開回到預設：`changeConfiguration` 只存 `mode`（`FixedPageReaderViewController.swift:380-388`），重開時用 `recommendedConfiguration`（`FixedPageReaderConfiguration.swift:155-160`）。② 刪書時不清。③ 不同步也不備份。①② 已於 2026-09-15 由 §5 修正。 |
| 渲染器偏好、相容狀態 | `ReadingBook.rendererPreference`／`compatibilityState`，在書籍記錄裡（`Models.swift:229-230`） | 技術狀態，不是閱讀設定，本設計不動。 |
| 多角色朗讀的聲音分配 | `GlobalSettings.ttsRoleVoices` 扁平字典，鍵為書 ID＋分隔字元＋角色名（`TTSRoleVoiceCast.swift:114-128`） | 是這本書的角色資料，不是閱讀顯示設定，不收進來。刪書時原本也不清，只有使用者在 `TTSRoleCastView` 手動清除；2026-09-15 起刪書時一併清除。 |

### 3.3 設定怎麼進排版：合併點，以及繞過它的地方

**主要入口（已經是單一入口）**：`ReaderView.readerRenderSettings(for:)` 組出 `ReaderRenderSettingsSnapshotInput`（`ReaderView+PageBuilding.swift:36-57`）→ `ReaderRenderSettingsSnapshotBuilder.make` → `ReaderRenderSettings`。`.onChanged(of: activeReaderRenderSettings)` 用 `refreshIntent(comparedTo:)` 判斷要重排還是重畫（`ReaderView.swift:2043-2048`、`ReaderRenderRefresh.swift:136-176`）。生效值只要從這裡進去，重排就會自動發生，不必另寫觸發。

**但有三類讀取繞過這個快照**。本書覆寫必須一起處理，否則會「一部分生效、一部分沒生效」。

**第 1 類：排版時直接讀全域字體與粗體（Core 內）。** 快照裡已經有 `fontPostScriptName` 與 `isBold`。EPUB（`EPUBAttributedStringBuilder.swift:140,264,502`）、瀏覽器排版（`BrowserLayoutPageEngine.swift:757-775`）、捲動引擎（`CoreTextScrollEngine.swift:314-315`）用的是快照，但下列地方直接讀全域：

- `UserReaderFontResolver.selectedPostScriptName` 讀 `GlobalSettings.shared.selectedReaderFontPostScript`（`UserReaderFontResolver.swift:29-34`）。用到它的有：
  - TXT 正文，經 `bodyFont`（`TXTLazyAttributedStringBuilder.swift:84`）
  - TXT 節點路徑（`NodeAttributedStringBuilder.swift:78`）
  - 線上書（`OnlineProviderAttributedStringBuilder.swift:617,707,898`）
  - 章節標題：`titleFont` 的 `postScriptName ?? selectedPostScriptName`（`UserReaderFontResolver.swift:62-63`）與 CSS 模板路徑（`ChapterTitleAttributedBuilder.swift:393,420`）
- `bodyBoldRequested(isBold:)` 會再 OR 上全域粗體（`UserReaderFontResolver.swift:44-46`），快照說不粗也沒用（`TXTLazyAttributedStringBuilder.swift:87`、`OnlineProviderAttributedStringBuilder.swift:901`）。
- 段評徽章直接讀全域粗體與字體，快取鍵也用全域值（`ReviewBadgeRenderer.swift:30,38,96-97`）；氣泡 SVG 文字讀全域粗體（`CommentBubbleSVGRecognizer.swift:1131`）。

今天看不到錯誤，因為快照裡的字體就是從全域取的。有了本書覆寫後，**同一本 TXT 會變成正文換了字體、標題沒換**。另外，粗體現在同時從快照（`ReaderConfig`，立即）與全域（120ms 後才寫回）兩處取值，兩者會短暫不一致；沒有實測是否造成可見問題，改成只讀快照後這個不一致就不存在。

**第 2 類：模式級設定另有觀察者，讀的是全域。**

- `settings.pageTurnStyle`（`ReaderView.swift:2129`）
- `settings.scrollMode`（`:2137`，切換捲動／分頁）
- `settings.readerWritingMode`（`:2140-2150`，更新開書方向並重排）
- `settings.textConversion`（`:2112`，重建 AI 內容）
- `effectiveScrollMode` 直接回傳 `settings.scrollMode`（`ReaderView+TXTVerticalScroll.swift:129-131`）；`effectivePageTurnStyle` 以 `settings.pageTurnStyle` 為基礎（`ReaderView.swift:444-446`）

不改的話，把本書改成捲動不會切換模式，而改全域的捲動會把「本書設定為分頁」的書也切掉。

**第 3 類：閱讀器還沒打開就要知道的值。** 書架開書時要決定卡片翻開方向：固定頁讀 `FixedPageReadingMode.savedConfiguration`（`HomeView.swift:313-318`），TXT／線上書讀全域 `gs.readerWritingMode`（`HomeView.swift:334-336`）。所以存放和合併函式不能只活在 `ReaderView` 裡。

Feature 層直接讀這些欄位的檔案（這些檔案裡的 `settings` 是 `GlobalSettings`；Core 裡同名的 `settings.textConversion` 等是快照欄位，不用改）：

| 欄位 | 檔案 |
|---|---|
| `scrollMode` | ReaderView、ReaderView+Toolbars、ReaderView+TXTVerticalScroll、ReaderSettingsView |
| `pageTurnStyle` | ReaderView、ReaderView+Toolbars |
| `readerWritingMode` | ReaderView、ReaderView+TXTVerticalScroll、HomeView |
| `textConversion` | ReaderView、ReaderView+Toolbars、ReaderView+TXTVerticalScroll、ReaderView+SourceChange、ReaderView+PageBars、ReaderView+PageBuilding、ReaderSettingsView |
| `readerConfig` 的字級／行距／邊距／粗體／章節標題 | ReaderView、ReaderView+PageBuilding、ReaderView+TXTVerticalScroll、ReaderView+Footer、ReaderSettingsView、ChapterTitleStyleSettingsView |

### 3.4 誰會寫這些設定

| 寫入者 | 寫什麼 | 位置 |
|---|---|---|
| 閱讀設定 sheet | 字體、字級、粗體、文字顏色、繁簡、間距、邊距、翻頁手勢、頁首頁尾、裝飾、亮度；子頁有章節標題、頁首頁尾編輯、段評氣泡、正則高亮、對話氣泡 | `ReaderSettingsView`，只從閱讀器打開（`ReaderView.swift:2184-2211`） |
| 快速面板 | 字級、翻頁方式／捲動、亮度、閱讀背景、跟隨系統外觀 | `ReaderQuickThemePanelView`；翻頁經 `applyQuickPageTurnOption`（`ReaderView+Toolbars.swift:498-515`） |
| 跟隨系統／綁定外觀主題 | 閱讀背景 | `applyFollowSystemThemeIfNeeded`、`syncActiveThemePreset`（`ReaderView.swift:338-385`） |
| 匯入閱讀設定 | 排版、章節標題、正則高亮、對話氣泡 | `ReaderSettingsImportService.apply`（`ReaderSettingsImportService.swift:177-256`） |
| 匯入 .qitheme | 閱讀字體 | `QiThemeImportService.swift:318` |
| 登入時套用帳號資料 | 字級、背景、間距、邊距、翻頁、直排、繁簡、捲動、頁首、文字顏色 | `GlobalSettings.applyFirebaseProfile` → `ReaderPreferences.apply`（`GlobalSettings.swift:3446-3454`、`UserProfile.swift:81-115`） |
| 刪除匯入字體 | 選中的字體被刪時清回預設 | `GlobalSettings.deleteUserFont`（`GlobalSettings.swift:3381-3389`） |
| 固定頁選單 | 固定頁全部設定 | `FixedPageReaderSettingsView`（`FixedPageReaderView.swift:341-467`）→ `changeConfiguration` |

App「設定」分頁**沒有**閱讀排版頁（「閱讀工具」只有語音朗讀、AI 助手、替換規則，`ProfileView.swift:152-174`）。換句話說，**全域排版現在只能在某本書裡面改**，所以「全域／本書」的切換必須放在閱讀器的設定頁裡。

### 3.5 直排：底層已有，沒有入口

`readerWritingMode` 目前**沒有任何畫面可以改**。會寫入它的只有兩處：啟動時讀 UserDefaults（`GlobalSettings.swift:1815`），以及登入時套用帳號資料（`UserProfile.swift:96`）。章節標題設計器裡的「橫排／直排」只切換設計器的預覽（`ChapterTitleDesignerCanvas.swift:61-64`，綁 `model.previewWritingMode`）。

既有限制：只有 TXT 與線上書能用使用者的直排設定（`ReadingBook.allowsVerticalWritingMode`，`Models.swift:782-787`）；EPUB 照書本身宣告的方向，直排 EPUB 一律 `verticalRTL`（`ReaderView+TXTVerticalScroll.swift:122-127`）。

### 3.6 同步與備份現況

| 管道 | 同步什麼 | 含閱讀設定嗎 |
|---|---|---|
| iCloud 自動合併（`ICloudSyncManager.sync`，`ICloudSyncManager.swift:230-418`） | 書源、替換規則、段評氣泡樣式與選擇、頁首頁尾配置、書籍記錄（整筆以 `lastOpenedDate` 比新舊）、書檔 | **沒有排版設定** |
| 帳號資料（登入後） | `ReaderPreferences`：字級、背景、間距、邊距、翻頁、直排、繁簡、捲動、頁首、文字顏色（`UserProfile.swift:58-79`） | 全域值；不含字體、粗體、章節標題 |
| WebDAV 備份（`WebDAVManager.swift:176-211`） | 書源、書架記錄、替換規則 | 沒有 |

`fixedPage.readingMode` 不在任何同步或備份裡。

## 4. 資料模型

一本書一筆 `BookReaderSettings`。除了書 ID 與修改時間，**每個欄位都可以「沒有值」，意思是跟隨全域**。

| 欄位 | 沒有值的意思 | 適用書種 | 對應的全域來源 |
|---|---|---|---|
| `bookID` | — | 全部 | — |
| `modifiedAt` | — | 全部 | 使用者在本書範圍改設定時更新；套用同步結果時**不**更新（同頁首頁尾同步的規則，`ICloudSyncManager.swift:342-346`） |
| 字級 | 跟隨全域 | 可重排文字 | `readerConfig.fontSize` |
| 閱讀字體 | 跟隨全域 | 允許自選字體的書（`Models.swift:384-388`） | `selectedReaderFontPostScript` |
| 粗體 | 跟隨全域 | 可重排文字 | `readerFontBold` |
| 行距倍數、字距、段距倍數 | 跟隨全域 | 可重排文字 | `readerConfig` 同名欄位 |
| 左右邊距、上下邊距 | 跟隨全域 | 可重排文字 | `pageMarginH`／`pageMarginV` |
| 繁簡轉換 | 跟隨全域 | 可重排文字 | `textConversion` |
| 直排 | 跟隨全域 | 只有 TXT 與線上書 | `readerWritingMode` |
| 捲動、翻頁方式 | 跟隨全域 | 可重排文字 | `scrollMode`／`pageTurnStyle` |
| 固定頁設定 | 用「從右到左」的預設（與現在相同） | 漫畫／PDF／固定版面 EPUB | 沒有全域值，純本書 |

- **字體需要三種狀態**：「沒覆寫」、「覆寫為預設字體」、「覆寫為某個匯入字體」。全域的「沒選字體」本身是有意義的值（EPUB 用書本身的字體，TXT 用系統字體），不能用「沒有值」同時表示兩件事。
- **所有欄位都沒有值、也沒有固定頁設定時，刪掉這筆記錄**，不留空殼。

**為什麼不放進 `ReadingBook`：**

1. 書籍記錄的 iCloud 同步是**整筆**比新舊，時間戳是 `lastOpenedDate`（`ICloudSyncManager.swift:378-385`）。A 裝置改了這本書的字體，B 裝置之後打開這本書、存了進度——B 那筆比較新，A 的字體設定整筆被蓋掉。進度幾乎每次開書都會變，所以這會常常發生。獨立記錄有自己的修改時間，不會和進度互相覆蓋。
2. `ReadingBook` 用手寫的解碼器與 `CodingKeys`（`Models.swift:277-335`），每加一個欄位要改三處，漏一處就靜默遺失。
3. 不在書架上的閱讀記錄存在另一個檔、也不同步（`BookStore.swift:2005-2008`、`2160-2169`），但覆寫在本機仍應生效。

## 5. 存放：只有一個 store

- **名稱**：`BookReaderSettingsStore`，服務層，放 `Modules/Services/LibraryStore/`。
- **擁有者**：由 `BookStore` 持有，對外是**獨立的可觀察物件**。
  - 生命週期跟書籍記錄綁在一起，刪書在同一個類別裡處理。
  - 閱讀器、書架、固定頁閱讀器都已經拿得到 `BookStore`，不必新增單例。
  - 獨立物件可以避免「改一本書的字級」讓整個書架重新繪製。
  - 目前只有固定頁設定，沒有需要 SwiftUI 觀察的值，所以實作是一般類別；加入排版覆寫時再改成可觀察。
- **檔案**：書架檔旁邊的 `books_meta.reader-settings.json`，命名方式與閱讀記錄檔 `books_meta.reading.json` 相同（`BookStore.readingMetadataFileURL`）。不在 `StorageLocations` 另訂固定路徑，是因為測試會用暫存目錄開 `BookStore`；固定路徑會讓每個測試都讀寫 App 自己的設定檔。正式環境的書架檔在 Application Support，使用者在「檔案」App 看不到，不會誤刪（`StorageLocations.swift:49-63`）。
- **寫入**：記憶體裡立即生效。固定頁設定來自選單點選，一次一筆，直接寫檔。加入排版覆寫後（拖滑桿會連續送值），才加上合併寫入（沿用 `ReaderConfig` 的 120ms）與進背景時寫出；那是合併磁碟寫入，不是在等狀態穩定。
- **讀檔失敗**：解碼失敗**不可以當成空資料然後覆寫原檔**。先把原檔內容另存為 `…corrupt-<時間>.json`、用 `AppLogger` 記錄，再以空資料啟動；另存也失敗時，這次啟動只在記憶體裡修改，不寫檔。先例：頁首頁尾配置解碼失敗時，會把原資料另存到 `yd_reader_bar_layout_corrupt_backup`（`GlobalSettings.swift:1795-1797`）。
- **刪書**：書籍記錄會在兩個地方被移除。一是使用者刪書的 `BookStore.delete(bookId:)`，這裡直接刪掉這本書的設定。二是套用 iCloud 同步結果的 `replaceBooksFromSync`，它經 `books` 的 setter 重建記錄，別台刪掉的書就在這裡消失；套用完成後，刪掉不在新記錄裡的書的設定。遠端書庫的書只是移出書架、閱讀記錄保留，設定也保留。
- **孤兒清理**：只在拿到確定完整的書籍清單時做：同步套用成功後（上一條），以及啟動時搬移舊鍵（§5.1）。書籍清單是空的不代表真的沒書，可能是讀取失敗（同 `Technotes/OfflineDownloadContract.md` 第一條不變量），所以 `loadMeta`／`loadReadingRecords` 會回報是否真的讀成功——檔案不存在或解碼成功才算。
- **設定頁不自己決定寫到哪**：統一經 `ReaderSettingsEditor`，依範圍寫全域（仍走 `ReaderConfig`／`GlobalSettings`，不另開全域寫入路徑）或寫 store。

### 5.1 收編 `fixedPage.readingMode`

1. 只由 App 自己的 `BookStore` 執行（`yuedu_appApp` 傳入 `UserDefaults.standard`），時機在書籍記錄載入之後；測試與預覽開的 `BookStore` 不碰這些鍵。每次啟動都會檢查，沒有舊鍵就立刻結束。
2. 從 UserDefaults 找出 `fixedPage.readingMode.` 與 `manga.readingMode.` 開頭的鍵。同一本書兩種都有時，以 `fixedPage.` 為準（與舊的 `saved(for:)` 優先順序相同）。
3. 只搬書籍記錄裡有的書，寫入「該方向的預設設定」。其他開關本來就沒存，不會遺失任何東西。這本書在 store 裡已經有設定時，保留 store 的值，只刪舊鍵。
4. **確認新檔寫入成功後，才刪舊鍵**。寫入失敗就保留舊鍵、記 log，下次啟動再搬；順序反過來就是先刪後寫的資料遺失。
5. 找不到對應書的舊鍵：書架與閱讀記錄都確定讀成功時才刪；否則保留，因為可能只是這次讀取失敗。
6. 已刪除 `FixedPageReadingMode` 的 `saved`／`save` 與 `FixedPageReaderConfiguration` 的 `savedConfiguration`；`FixedPageReaderViewController` 與 `HomeView.resolveOpeningDirection` 改讀 store。**不存在第二條路徑。**
7. 舊測試 `fixedPageReaderModeKeepsLegacyFallback` 已刪除，改由 `BookReaderSettingsStoreTests` 與 `BookStoreReaderSettingsTests` 覆蓋（含舊鍵 `manga.readingMode.` 的情況）。

## 6. 合併：只有一個函式

**`ReaderSettingsResolver.resolve(global:book:overrides:)`** 是純函式。它輸入三樣值，輸出 `EffectiveReaderSettings`：每個欄位的生效值，加上「哪些欄位來自本書」的集合（給設定頁顯示來源）。

- `global`：全域值的快照，由呼叫端從 `GlobalSettings`／`ReaderConfig` 取好傳入。**resolver 內不讀任何單例**，這樣才能單元測試，結果也才固定。
- `book`：這本書的能力，包括書種、`allowsVerticalWritingMode`、是否為直排 EPUB、是否允許自選字體。
- `overrides`：這本書的記錄，可以沒有。

**規則**

- 本書有值、且這本書允許該欄位 → 用本書值；否則用全域值。
- **直排**：EPUB 一律照書本身（直排 EPUB 為 `verticalRTL`，其他為橫排）；書種不允許時忽略本書值。這和今天的 `effectiveWritingMode` 相同，只是搬進 resolver。
- **字體不存在**：本書指定的匯入字體在這台裝置不存在時，改用全域字體，並把「字體不存在」回報給設定頁顯示。**這是兜底。** 它擋的真實情況有兩種：使用者刪了字體；或第三階段開同步後，從另一台裝置同步來的字體在這台沒有。在本機刪字體時，要一併清掉引用它的本書設定（比照 `deleteUserFont` 清全域選擇），所以本機的情況不會長期停在兜底上。

**改讀生效值的地方**

1. `readerRenderSettings(for:)` 的輸入欄位、`effectivePageMarginH`、捲動模式的上下邊距（`ReaderView+PageBuilding.swift:86`）。
2. `effectiveWritingMode`、`effectiveScrollMode`、`effectivePageTurnStyle` 改以生效值為基礎；`effectivePageTurnStyle` 保留原本「雙頁時捲頁改成滑動」的規則（`ReaderView.swift:441-446`）。另新增 `effectiveTextConversion`。
3. §3.3 第 2 類的觀察者，改為觀察生效值。
4. `HomeView.resolveOpeningDirection` 的直排與固定頁方向。
5. 閱讀器外框（chrome）：§3.3 表格列出的 Feature 層檔案。

**Core 不再直接讀全域字體與粗體。** §3.3 第 1 類全部改用快照的 `fontPostScriptName`、`isBold`；段評徽章與氣泡 SVG 從呼叫端傳入字體與粗體，快取鍵也用傳入值。這一步不改變任何現有行為，所以排在最前面，先用測試釘住（§10 階段 0）。

**效能**：每次 SwiftUI 計算 `activeReaderRenderSettings` 都會跑 resolver，所以它只能做欄位合併，不可以有磁碟 I/O 或 JSON 編碼。實作時用 `SourcePerfTrace` 量 store 載入與 resolve 的毫秒數並回報。

## 7. 同步

**建議：第一版只存本機，資料格式先把同步需要的欄位備好；第三階段再接 iCloud。**

理由：

- 全域排版今天就不走 iCloud（§3.6）。只同步本書覆寫，會變成「覆寫的欄位兩台一樣、沒覆寫的欄位兩台不一樣」——正是 Reeden 文件花一整段排查的「同步了卻看起來沒生效」。
- 固定頁閱讀方向今天也不同步。第一版維持同樣行為，使用者不會覺得少了什麼。
- App 已經上架，同步出錯會影響真實使用者的資料。先在本機驗證合併與清理規則，再加同步。

**第三階段接法（格式已預留）**

- 新增 iCloud 記錄 `book_reader_settings`，走既有的 `mergeType`，以書 ID 為鍵、`modifiedAt` 比新舊。
- 時鐘規則同頁首頁尾：**只有使用者編輯才前進，套用遠端結果不前進**，否則兩台裝置每次同步都聲稱自己最新（`ICloudSyncManager.swift:342-346`）。
- 刪書時記錄從本機消失，`mergeType` 會自動轉成刪除標記，傳到其他裝置（`ICloudSyncManager.swift:439-444`）。
- 字體檔不同步，靠 §6 的字體兜底顯示提示。
- 不放進帳號資料 `ReaderPreferences`：那是帳號層的全域偏好。
- WebDAV 備份同時加入 `books_meta.reader-settings.json`。

## 8. 設定畫面

### 8.1 建議的模型：頂端範圍切換＋逐項恢復

閱讀設定 sheet 的預覽區下方、第一個區塊之上，放一個分段選擇器：**「套用到：所有書｜本書」**。

| | 「所有書」 | 「本書」 |
|---|---|---|
| 每列顯示 | 全域值 | 生效值，次要文字標示「本書設定」或「跟隨全域」 |
| 編輯 | 改全域（和今天一樣） | 只改這本書的這一項 |
| 本書已覆寫的列 | 仍可改全域；該區塊 footer 寫「本書已自訂字體大小、行距，這裡的變更不會套用到本書。」 | 列下方出現「恢復全域」按鈕，沿用文字顏色列「跟隨主題文字顏色」的做法（`ReaderSettingsView.swift:406-412`） |
| 一次全部恢復 | — | 有任何覆寫時，在可覆寫的區塊最後提供「全部恢復全域」，用 `confirmationDialog` 確認 |
| 第一版覆寫不到的區塊（翻頁與手勢、頁首頁尾、閱讀裝飾、閱讀設定備份），以及「文字」裡的文字顏色、章節標題樣式兩列 | 照常顯示 | **隱藏**，不顯示成「在本書範圍改了卻套用到所有書」 |
| 亮度 | 照常顯示 | 照常顯示：亮度是裝置狀態，不屬於任何一本書 |

- **打開 sheet 時的預設範圍**：這本書有任何覆寫 → 「本書」；否則 → 「所有書」。從沒用過本書覆寫的人，打開時和今天完全一樣。
- **「自訂間距」開關**（`ReaderSettingsView.swift:576-616`，關閉時行距、字距、段距回 App 預設值）：兩種範圍都保持原意，「本書」範圍關閉＝這本書用 App 預設間距。它和「恢復全域」是兩件不同的事，文案要分開。
- **快速面板**：字級與翻頁跟隨這次閱讀的範圍（規則同上；在 sheet 裡切換範圍後跟著變）。範圍是「本書」時，在字級與翻頁那一列旁邊標示「本書設定」。閱讀背景那一列第一版仍然是全域，所以標示不放在整個面板標題上。
- **直排入口**：在「文字」區塊新增「直排」列，只對 TXT／線上書顯示，跟著範圍切換走。這是直排第一次有畫面入口（§3.5）。

**替代方案（不建議）**：不放範圍切換，每一列各自有「只套用本書」的選單。缺點是每列的行為取決於它當下的狀態、選單藏在長按裡看不到，而滑桿列也不好放選單。

### 8.2 固定頁閱讀器

固定頁設定沒有全域值，本來就是每本書各自的，所以選單不加範圍切換。只改兩點：整組設定存進 store（解決 §3.2 的問題 ①），以及書架開書方向改讀 store。

### 8.3 無障礙

- 分段選擇器保留原生標籤「套用到」，不 `labelsHidden` 後自己拼。
- 來源放進控制項本身的 `accessibilityValue`（例：「18 pt，本書設定」），不做成另一個可聚焦的文字；不加在包住整列的 `HStack` 上（`docs/design.md` §7.1）。
- 「恢復全域」按鈕名稱帶欄位名，例如「字體大小恢復全域」，VoiceOver 使用者才知道恢復的是哪一項。
- 「全部恢復全域」完成後發 VoiceOver 公告，說明恢復了幾項。
- 來源一律用文字標示，不只靠顏色。

### 8.4 新增本地化字串（候選，三個 lproj 都要加）

套用到、所有書、本書、本書設定、跟隨全域、恢復全域、%@恢復全域、全部恢復全域、直排、「本書已自訂%@，這裡的變更不會套用到本書。」、「這台裝置沒有「%@」字體，目前使用全域字體。」

## 9. 第二、第三階段要注意的事（先記下，第一版不做）

**閱讀背景（第二階段）**

- 閱讀背景有三個寫入者：手動選、跟隨系統外觀、綁定外觀主題（§3.4）。後兩者會在系統切換深淺色時改寫 `readerConfig.theme`。本書若只存一個背景，系統一切深色就會和它們打架。
- 所以本書的閱讀背景要存「淺色、深色」一對（和 Reeden 本書日夜主題的結論相同）。生效時依系統深淺色挑一個，並優先於跟隨系統與綁定外觀主題。
- `readerTheme` 在閱讀器裡被大量直接讀取（工具列配色、文字顏色），要先有 `effectiveReaderTheme`。
- 自訂背景圖／純色（`readerCustomBackgroundMode`）與每個背景的文字顏色維持全域。

**章節標題樣式（第二階段）**：`ChapterTitleStyleSettingsView` 與設計器直接改 `readerConfig.chapterTitleStyle`（`ChapterTitleStyleSettingsView.swift:337,341`）。要先改成「傳入值＋onChange」的形式，才能指向本書。

**正則高亮、對話氣泡（第三階段，配置管理）**：這兩個設定頁已經是「傳入值＋onChange」（`ReaderSettingsView.swift:666-684`），接到 store 的成本低。但要和「規則分組、整組開關、只套用本書」一起設計，不單獨做。

## 10. 分階段與測試

每個階段都先寫會失敗的測試，再改程式。測試一律用 `scripts/xctest.sh` 跑指定 suite；動到直排解析時加跑 `CoreTextWritingModeTests`。

### 階段 0：前置整理，不改任何行為

- Core 的字體與粗體只讀快照（§3.3 第 1 類）。
- 觀察者與閱讀器外框改讀 `effective*` 計算屬性；此時它們仍等於全域值（§3.3 第 2 類）。
- 測試：
  - 全域字體 A、快照字體 B → TXT 正文、TXT 節點路徑、線上書正文、章節標題都用 B（現在會失敗）。
  - 全域粗體開、快照粗體關 → 不是粗體（現在會失敗，因為 OR）。
  - 既有 `ReaderRenderSettingsSnapshotTests` 全綠，快照內容不變。

### 階段 1：本書覆寫第一版

- 內容：store、resolver、§4 的欄位、設定畫面（§8.1）、快速面板、直排入口、刪書與孤兒清理、收編固定頁。
- 測試：
  - resolver：沒有覆寫時每個欄位等於全域；逐欄覆寫；書種不允許時忽略（EPUB 直排、不允許自選字體的書）；字體三種狀態；字體不存在時用全域並回報。
  - 沒有任何覆寫時，`readerRenderSettings` 的輸出與階段 0 完全相同。
  - 覆寫字級 → `refreshIntent` 為 `.layout`；只切換範圍、值沒變 → 不重排。
  - store：存讀往返；全空記錄被刪；刪書時一併刪；遠端書移出書架時保留；書籍載入失敗時不清孤兒；解碼失敗時原檔被保留。
  - 遷移：兩種舊鍵、優先順序、寫入成功才刪舊鍵、第二次啟動不重複執行。
  - 固定頁：設定重開後保留；書架開書方向使用 store 裡的方向。
  - 直排：本書直排搭配分頁、捲動兩種情況，開書方向、翻頁方向、選字與劃線位置都正確。
- 每個新畫面加 `#Preview`；VoiceOver 照 §8.3 手動檢查。

### 階段 2：閱讀背景（淺深一對）、章節標題樣式

見 §9。

### 階段 3：iCloud 同步、WebDAV 備份、配置管理

同步見 §7；配置管理指正則高亮、對話氣泡的「只套用本書」，見 §9。

## 11. 驗收情境

1. 中文小說沿用日常排版；英文小說只改字體與行距。換書後各自保留，互不影響。
2. 在「所有書」把字級調大：沒覆寫字級的書全部變大；覆寫過的書不變，而且設定頁的 footer 說得出原因。
3. 某本 TXT 改成直排：書架開書的卡片方向、翻頁方向、書內搜尋、選字、劃線位置都正確；其他 TXT 仍是橫排。
4. 按「恢復全域」後，該項立刻變成全域**目前**的值，不是當初覆寫前的值。
5. 刪除一本有覆寫的書，它的記錄一起消失；遠端書只是移出書架時保留。
6. 漫畫的閱讀方向、裁邊、雙頁重開後都保留；舊版存的閱讀方向升級後不遺失。
7. 刪除一本書正在用的匯入字體：這本書回到跟隨全域字體，設定頁不再顯示本書字體。
8. VoiceOver 念得出每一列是「本書設定」還是「跟隨全域」，以及恢復的是哪一項。
9. 從沒用過本書覆寫的使用者，升級後所有行為與升級前相同。

## 12. 待決策（附建議）

| # | 問題 | 建議 | 理由 |
|---|---|---|---|
| 1 | 第一版覆寫哪些欄位 | §4 的表格：排版、字體、繁簡、直排、翻頁／捲動、固定頁 | 對應「英文書改字體行距、日文書直排」兩個例子；閱讀背景牽涉三個寫入者，要另外設計 |
| 2 | 設定畫面模型 | 頂端範圍切換＋逐項恢復（§8.1） | 範圍看得見，每一列的行為一致 |
| 3 | 打開設定時的預設範圍 | 有覆寫就「本書」，沒有就「所有書」 | 沒用過的人完全不受影響 |
| 4 | 快速面板寫到哪 | 字級與翻頁跟隨這次閱讀的範圍，並標示「本書設定」 | 和 sheet 同一套規則 |
| 5 | 直排入口 | 在「文字」區塊新增，只對 TXT／線上書顯示，跟著範圍走 | 設定早就存在，只是沒有入口 |
| 6 | 固定頁開關重開後保留 | 保留（2026-09-15 已實作） | 原本每次重開都回預設，裁邊等於每次都要重新打開 |
| 7 | 同步時程 | 第一版只存本機，第三階段接 iCloud | 全域排版本身不走 iCloud，只同步覆寫會造成「看起來沒生效」 |
| 8 | 本書字體在這台裝置不存在 | 用全域字體，並在設定頁提示（明示的兜底） | 字體檔不同步，這是外部狀態，不是程式錯誤 |
| 9 | 閱讀設定備份在「本書」範圍 | 不顯示，只處理全域 | 備份檔格式是全域的，混入本書值後，匯入到別台時意思不清楚 |
