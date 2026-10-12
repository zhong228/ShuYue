---
title: Auto 與 Legacy 載入量測及下一步
updated: 2026-09-30
tags: [yuedu, browser-layout, performance]
---

# Auto 與 Legacy 載入量測及下一步（2026-09-30）

[目前狀態](STATUS.md) · [歷史台帳](PHASES.md) · [原始 120 筆觀測](loading-benchmark-2026-09-30.json) · [統計與來源校驗](loading-benchmark-2026-09-30-summary.json)

後續已完成 [按需字型第一輪本機實作與重測](loading-benchmark-2026-09-30-font-demand.md)。本文保留優化前基線；正式套件整合仍待發布與普通 project 驗證。

## 結論與文件核對

本次五個原書章節案例的翻頁與捲動首屏中位數，Auto 均慢於純 Legacy。短章節的主要差距是排版前的資源準備，尤其 Browser 提前載入未必需要的嵌入字型；回退章節也先支付這份成本。無嵌入字型的英文案例仍有明顯 scanner 成本，因此只改字型準備無法解決全部差距。

Obsidian 開啟的是 Reader 的 `docs/`。`STATUS.md` 主體的更新日期仍是 9/12，當時記錄 0.3.0／0.4.0 與未完成的 Lexbor 5A；9/13 的英文排版報告及 9/23 的幾何重錄是後续補充。現在正常 `.xcodeproj` 已釘選遠端 **YueduCoreText 0.6.0 / 8cd1bf6f12b2100fdbc1e641ecd7c4459ad2bf03**，並含 viewport 背景排版。當前前端仍是 Current／LegacyCSSFrontend，Lexbor 正式切換仍沒有完成證據。

早期 `BrowserLayoutABHarnessTests` 把 Browser 本身的 layout metrics 當首屏，沒有計入完整 resource/scanner/Reader gate；既有 `BrowserLayoutPerfTests` 的 Legacy 對照只到文字建構，沒有 Legacy 分頁。抽取報告的 40 段 synthetic 結果不能回答這次的 Auto 載入問題。

## 條件與量測邊界

- 原工作目錄、正常 `Yuedu-Reader.xcodeproj`、遠端套件；未改 App 路由或排版行為。
- Xcode 27.0（27A266a），iPhone 18 Pro Max / iOS 27.0 Simulator，Debug。
- 畫布 390 × 800pt，字級 17pt、行高 1.5、水平與垂直 inset 各 12pt；捲動內容區 366 × 776pt。使用同一 `EPUBTestFixtures.renderSettings()`。
- 四本原 EPUB、五個案例、四條路徑。每組一輪暖機及五輪有效樣本，共 120 筆觀測，統計使用 100 筆。交錯正反順序。每次重建 PublicationSession、builder、adapter、document store、engine；OS 檔案及 process 字型註冊快取保持暖狀態。
- 純 Legacy 直接使用 `CoreTextPageEngine`／`CoreTextScrollEngine`；Auto 使用同一 production `BrowserLayoutPageEngine(.browserAuto)`，捲動接同一 adapter。
- 翻頁先用正常 `start()` 處理第 0 章並完成其 Legacy 背景分頁，再單獨計時進入指定正文；全書 byte scan 保留，但每筆觀測結束前等待最後一次 `chapterDataSize` 的實際返回，防止它跑進下一筆。
- `firstReadyMs`：指定章節首次發布可用內容；捲動為初始章節 `start(...loadAdjacentChapters:false)` 返回並有實際 chunk。`requestReturnMs`：載入請求返回，翻頁通常包含剩餘分頁。`openingReturnMs`：第 0 章 startup 返回，也是正常 `EPUBPageRenderer` 設 `isCoreTextReady` 的門檻。
- 不包含點書動畫、首次 UIKit/SwiftUI 畫面合成、書籍匯入／下載；PublicationSession 開啟時間獨立保存在 JSON。這是有暖 process/file cache、冷引擎實例的載入量測。
- 字型 component 數據來自現有 `SourcePerfTrace`（`epub.font.fetch/register`）且只收一次 `[parse]` log；小於 1ms 的 span 可能沒有輸出。scanner 數據是主量測完成後、相同輸入的獨立暖 probe，不能與其他中位數相加當成精確總時間分解。
- 五筆不適合推估穩定的 p95；下面使用中位數與完整範圍。速度差異只涵蓋本次案例與條件。

## 指定章節首屏就緒：中位數（ms）

| 原書案例 | spine | HTML bytes | Legacy 翻頁 | Auto 翻頁 | 倍率 | Legacy 捲動 | Auto 捲動 | 倍率 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 《全職高手》正文 | 69 | 13,962 | 731.6 | 948.1 | 1.30× | 649.3 | 803.7 | 1.24× |
| 《詭秘之主》正文 | 80 | 10,917 | 451.2 | 1161.8 | 2.57× | 396.0 | 1026.5 | 2.59× |
| Project Hail Mary 正文 | 6 | 33,642 | 146.3 | 284.2 | 1.94× | 188.5 | 245.2 | 1.30× |
| 《全能遊戲設計師》回退章 | 10 | 10,912 | 709.0 | 1582.0 | 2.23× | 641.9 | 1403.5 | 2.19× |
| 《詭秘之主》長章／百科 | 64 | 121,736 | 4491.4 | 5525.8 | 1.23× | 4239.8 | 4975.0 | 1.17× |

除《全能遊戲設計師》因 positioned／unknown-block-display／flex-grid 回退整章 Legacy 外，其他四個案例的 Auto 均選 Browser；翻頁與捲動的決策一致。

### 首屏完整觀測範圍（ms）

| 案例 | 路徑 | 中位數 | min–max |
|---|---|---:|---:|
| 《全職高手》正文 | legacy-paged | 731.6 | 729.1–826.0 |
| 《全職高手》正文 | auto-paged | 948.1 | 944.4–966.6 |
| 《全職高手》正文 | legacy-scroll | 649.3 | 637.2–676.7 |
| 《全職高手》正文 | auto-scroll | 803.7 | 795.7–847.8 |
| 《詭秘之主》正文 | legacy-paged | 451.2 | 444.3–478.4 |
| 《詭秘之主》正文 | auto-paged | 1161.8 | 1144.2–1171.9 |
| 《詭秘之主》正文 | legacy-scroll | 396.0 | 386.1–405.2 |
| 《詭秘之主》正文 | auto-scroll | 1026.5 | 1008.3–1038.5 |
| Project Hail Mary 正文 | legacy-paged | 146.3 | 145.4–168.6 |
| Project Hail Mary 正文 | auto-paged | 284.2 | 280.5–295.2 |
| Project Hail Mary 正文 | legacy-scroll | 188.5 | 185.3–200.6 |
| Project Hail Mary 正文 | auto-scroll | 245.2 | 238.8–255.7 |
| 《全能遊戲設計師》回退章 | legacy-paged | 709.0 | 699.9–724.7 |
| 《全能遊戲設計師》回退章 | auto-paged | 1582.0 | 1542.8–1646.3 |
| 《全能遊戲設計師》回退章 | legacy-scroll | 641.9 | 629.1–654.0 |
| 《全能遊戲設計師》回退章 | auto-scroll | 1403.5 | 1376.1–1458.1 |
| 《詭秘之主》長章／百科 | legacy-paged | 4491.4 | 4447.2–4611.0 |
| 《詭秘之主》長章／百科 | auto-paged | 5525.8 | 5462.5–5642.3 |
| 《詭秘之主》長章／百科 | legacy-scroll | 4239.8 | 4090.0–4299.6 |
| 《詭秘之主》長章／百科 | auto-scroll | 4975.0 | 4893.8–5076.8 |

## 定位到的成本

### 1. CSS ingestion 先載入全部待註冊字型

`EPUBStylesheetIngestion.collect` 的最後一步是 `registerAllPendingFontFaces()`；它在 scanner 判斷是否可用 Browser **之前** 執行。Legacy builder 先分析章節的 styled AST，再呼叫 `registerFontFaces(requests:)`，只取實際字型需求。現有 process 註冊 digest cache 可以省重複註冊，仍需要先讀取／解碼完整 font bytes 才能查 digest，沒有省掉那些資源讀取。

Auto 資源欄位由 forwarding wrapper 在真實 adapter 呼叫外側計時，沒有換 parser、放入替代書籍或預熱 builder。以下 `font fetch` 是整筆觀測內現有 span 的總和；含第 0 章與回退 Legacy 的讀取，故不與 target CSS 當成互斥項目相加。

| 案例 | 路徑 | target CSS 準備（ms） | font fetch 總和（ms） | 有 trace 的 font 讀取數 | target 圖片準備（ms） | scanner 暖 probe（ms） |
|---|---|---:|---:|---:|---:|---:|
| 《全職高手》正文 | legacy-scroll | 0.0 | 124.0 | 2 | 0.0 | 0.0 |
| 《全職高手》正文 | auto-scroll | 459.5 | 242.0 | 4 | 240.7 | 56.4 |
| 《詭秘之主》正文 | legacy-scroll | 0.0 | 57.0 | 1 | 0.0 | 0.0 |
| 《詭秘之主》正文 | auto-scroll | 829.9 | 645.0 | 11 | 117.0 | 40.1 |
| Project Hail Mary 正文 | legacy-scroll | 0.0 | 0.0 | 0 | 0.0 | 0.0 |
| Project Hail Mary 正文 | auto-scroll | 8.1 | 0.0 | 0 | 4.6 | 128.4 |
| 《全能遊戲設計師》回退章 | legacy-scroll | 0.0 | 152.0 | 3 | 0.0 | 0.0 |
| 《全能遊戲設計師》回退章 | auto-scroll | 621.9 | 616.0 | 12 | 0.0 | 139.6 |
| 《詭秘之主》長章／百科 | legacy-scroll | 0.0 | 347.0 | 6 | 0.0 | 0.0 |
| 《詭秘之主》長章／百科 | auto-scroll | 861.5 | 657.0 | 11 | 2422.5 | 848.4 |

Legacy 的 target CSS／圖片欄為 0 是因沒有經過 Browser adapter wrapper；Legacy 的相同工作包含在 `legacyBuildMs` 與既有 document/font traces，不表示 Legacy 沒做資源準備。

《全能遊戲設計師》兩條 Auto 路徑最終回退 Legacy，觀测仍有 12 次 font fetch trace；純 Legacy 是 3 次。這證明 Auto 做完 Browser 準備後，又支付 Legacy 需要的資源工作。不能把回退就當作已經省去新引擎成本。

### 2. 同章 scanner 與正式前端重複解析／cascade

`decideEngine` 先取 HTML/CSS 並呼叫 capability scanner；scanner 解析 DOM、CSS、匹配 selector，還建立 ComputedStyle tree。接受後 `BrowserLayoutSession.prepare` 或 viewport owner 再做 Current frontend 的 DOM/CSS/style tree。資源呼叫計數顯示 Browser 章節 HTML/CSS input 各被要求兩次；adapter 的 CSS input cache 使第二次資源取得很便宜，但不會重用 scanner 裡已算出的 DOM/cascade。

英文案例沒有嵌入字型，scanner 暖 probe 仍約百毫秒；長章 probe 更高。這是第二個應處理的成本，不能以移除字型預載代替解決。

### 3. 翻頁第 0 章重複工作，以及首次可用與返回門檻不同

`BrowserLayoutPageEngine.start` 先 `await delegate.start`（實際建構 Legacy 第 0 章），再 `await preloadChapter(0)`。本次 Auto 的第 0 章都選 Browser，但觀測 `legacyBuildCounts[0] == 1`，因此第 0 章先有一份 Legacy build，之後再走 Browser。

Browser 可在 `onChapterReady` 先發布首頁，`preloadChapter` 仍 await 剩餘頁面，`EPUBPageRenderer.load` 又等 `start()` 返回才打開 `isCoreTextReady`。這是源碼確認的結構問題。這批原書的第 0 章很短、正文首頁與請求返回也接近，因此本次未證明等待剩餘分頁是主要耗時；優先序低於字型與前端重複工作。第 0 章先建 Legacy 再建 Browser 的重複資源成本，則由計數與 startup 表直接確認。

| 原書案例 | Legacy 第 0 章首頁（ms） | Legacy startup 返回（ms） | Auto 第 0 章首頁（ms） | Auto startup 返回（ms） | 正文 Legacy 首頁／請求返回（ms） | 正文 Auto 首頁／請求返回（ms） |
|---|---:|---:|---:|---:|---:|---:|
| 《全職高手》正文 | 68.1 | 83.1 | 152.6 | 153.3 | 731.6 / 731.7 | 948.1 / 949.9 |
| 《詭秘之主》正文 | 72.5 | 84.0 | 156.8 | 157.4 | 451.2 / 451.4 | 1161.8 / 1163.2 |
| Project Hail Mary 正文 | 15.7 | 17.7 | 40.7 | 40.7 | 146.3 / 198.7 | 284.2 / 286.2 |
| 《全能遊戲設計師》回退章 | 58.3 | 66.6 | 128.6 | 129.1 | 709.0 / 709.1 | 1582.0 / 1582.4 |
| 《詭秘之主》長章／百科 | 72.2 | 83.4 | 157.4 | 158.1 | 4491.4 / 4798.5 | 5525.8 / 5539.1 |

長章有大量圖片；Browser 的全章圖片資源準備亦列在表內。這筆數據不證明讀取或排版只與可視區大小有關；目前 viewport 背景排版本身不能消除全章資源準備與 scanner。

## 建議下一步：按工作單位分開驗收

本次只新增量測工具與報告。以下是建議，不代表已實作或已達標。

1. **先修 admission 與字型準備的次序／範圍（推薦的第一個實作單位）。** stylesheet 發現／語義解析與字型 bytes 讀取分開：Auto 先做能力判斷；拒絕章節直接交既有 Legacy，只載它要求的字型。接受章節從章節實際的 cascade 得到字型需求，再沿用 `EPUBStyleResolver.registerFontFaces(requests:)` 與現有 font registry。需求要含字重、斜體、ruby、first-letter、strut、字型 fallback 與使用者覆寫。需用真實配置區分語義 style 與依字型度量的 used values，不能只刪掉預載後讓 UIKit 靜默替代字型，也不新增另一套全域 font cache。
2. **把 scanner／Current 前端改成同章節共用 evaluation。** 使用文件與 generation 所有的一份 DOM-neutral 語義／CSS 結果輸出能力 facts 與排版輸入，避免 scanner 和 layout 各算一次。這與 5A 原先共用 evaluation 的方向相符，但先在 Current 前端驗證，不依賴 Lexbor cutover。跨 viewport／字級／writing mode 的 computed/used values 必須按配置重算，不能把舊 geometry 套到新 viewport。只重用有明確生命週期的章節資料，不加第二個相同鍵的 cache。
3. **拆開 metadata startup 與章節排版，讓首頁訊號解除開書 gate。** 保留全書進度／offset bookkeeping，但第 0 章只讓選中的引擎建構；legacy delegation 到真正回退時才需要排該章。首頁已可用就發布 ready，完整分頁繼續由原載入工作完成；用真實可用／取消訊號，不能新增睡眠、重試或變相空白 placeholder。
4. **以上完成後再決定長章圖片工作。** 保持圖片原始尺寸、inline/float 幾何與錨點正確；若圖片階段仍主導長章首屏，再做尺寸 metadata 與繪製資源的分離設計及量測。這是獨立工作，不在第一輪改動中順便重寫整個 viewport／paint 架構。

### 驗收要求

- 第一個單位直接回歸 `EPUBStyleResolverPerformanceTests`、新加的 Browser ingestion 字型需求／回退零預載計數測試，以及相關 `BrowserReaderTypographyTests`、`BrowserLayoutFontFallbackTests`、真實 EPUB 字型與頁面案例。
- 共用 evaluation 回歸 capability scanner、typed stylesheet ingestion、頁面／捲動決策、CSS override/important、ruby/float/text-indent 和 cancellation/generation；只跑改動觸及的直接類別，不重開無關完整 sweep。
- startup 工作直接回歸 `EPUBAutoRoutingTests`、`BrowserLayoutPageEngineTests`、startup readiness／chapter supply／取消；必要時再測實際 Reader 還原入口。
- 每個單位後，用本次相同檔案、章節、設定、測量方法重跑。提議的第一輪速度目標：兩個重字型短章與回退章的 Auto 首屏中位數至少降低 30%，其他案例沒有可重現退步；這是待驗收目標，不是預測結果。
- 回退章的 Browser admission 階段 font bytes 讀取必須為 0；接受章節只載實際需求及其有效字型 cascade。閱讀字型、字重／斜體、glyph、頁面內容與位置不能為了速度退化。
- simulator 的 before/after 通過後，產品體感驗收另量 Release 裝置上的點書→首個包含文字的畫面，與當前修正後的 engine-ready 數據分列；裝置使用依當次授權。

## 可重跑入口與產物

`Tests/iOS/yuedu appTests/EPUBEngineLoadingBenchmarkTests.swift` 是 opt-in 的原書量測入口；未設旗標時不執行本機私有 corpus。

```bash
export DEVELOPER_DIR="$(bash scripts/sim.sh xcode)"
export YUEDU_DEST="$(bash scripts/sim.sh dest)"
TEST_RUNNER_YUEDU_LOADING_BENCHMARK=1 bash scripts/xctest.sh \
  -t 1800 -l /tmp/yuedu-loading-benchmark.log -- \
  -only-testing:'yuedu appTests/EPUBEngineLoadingBenchmarkTests' \
  -resultBundlePath /tmp/yuedu-loading-benchmark.xcresult \
  -testLanguage zh-Hant -testRegion TW
```

結果固定寫到本報告同目錄的原始 JSON。這個入口使用 machine-local 原書路徑；不提交書籍內容。

本次最終 `TEST SUCCEEDED`：1 個量測測試方法，120 個內部路徑觀測，0 issue。正常 test action 同時完成 App 與測試 target 編譯，沒有額外 `clean`。詳細 log、xcresult 路徑與本輪源碼 SHA-256 校驗保存在 summary metadata；所有納入校驗的效能相關程式碼及量測入口於前後一致。

最初稽核輪因通用 `onChapterReady(nil)` 也可能代表頁數變更，確認有背景掃描延續後已停止並棄用；後兩次嘗試因其他測試佔用 `build.db` 在測試開始前失敗，未列入本次結果。最終輪等待共用建置結束才執行，沒有換 DerivedData、建立 worktree 或使用手機。
