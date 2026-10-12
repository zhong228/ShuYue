---
title: Browser 加載量測：按需字型第一輪
updated: 2026-09-30
tags: [browser-layout, performance, fonts]
---

# Browser 加載量測：按需字型第一輪

[改動前基線與方案](loading-benchmark-2026-09-30.md) · [本輪 120 筆原始觀測](loading-benchmark-2026-09-30-font-demand.json) · [統計與來源校驗](loading-benchmark-2026-09-30-font-demand-summary.json)

本輪已把 Browser 字型讀取移到能力判斷之後，並沿用該掃描的 computed-style tree 提供 family／weight／italic。App 按章節需求呼叫既有 `EPUBStyleResolver.registerFontFaces`，準備完字型才建立排版使用的不可變 resolver。能力回退章由 Legacy 原有的需求載入處理。

**按需字型已完成正式整合。** [YueduCoreText 0.6.1](https://github.com/CHANG-JUI-LIN/YueduCoreText/releases/tag/0.6.1) 已發布；App 的版本要求及 Xcode 產生的 pin 已更新為 0.6.1／`d7e16bd`。普通 `.xcodeproj` 的 59 項直接相關回歸全部通過，其餘 27 個依賴 pin 不變。

下方 120 筆原始觀測／100 筆有效量測在發布前的本機 App＋原始套件 checkout 完成；發布整理僅補回原 scanner 雙參數 overload，production scan body 與 ReaderCore 未變。這是模擬器引擎就緒量測，不能當作已發布 App 的點書至第一幀成效。[發布及普通 project 驗證](extraction/release-0.6.1.md)。

## 首屏中位數

單位 ms。每格 5 次有效觀測；同書、同章節、同設定。Auto 降低百分比是本輪 Auto 與基線 Auto 的比較。


### 分頁

| 案例 | 基線 Legacy | 基線 Auto | 本輪 Legacy | 本輪 Auto | Auto 時間降低 |
|---|---:|---:|---:|---:|---:|
| 全職高手短章 | 731.6 | 948.1 | 731.0 | 784.9 | 17.2% |
| 詭秘之主短章 | 451.2 | 1161.8 | 445.8 | 490.3 | 57.8% |
| Project Hail Mary | 146.3 | 284.2 | 143.6 | 278.5 | 2.0% |
| 全能遊戲設計師回退章 | 709.0 | 1582.0 | 707.5 | 1028.1 | 35.0% |
| 詭秘之主長章 | 4491.4 | 5525.8 | 4417.3 | 5117.4 | 7.4% |

### 連續捲動

| 案例 | 基線 Legacy | 基線 Auto | 本輪 Legacy | 本輪 Auto | Auto 時間降低 |
|---|---:|---:|---:|---:|---:|
| 全職高手短章 | 649.3 | 803.7 | 629.4 | 687.6 | 14.4% |
| 詭秘之主短章 | 396.0 | 1026.5 | 393.2 | 435.7 | 57.6% |
| Project Hail Mary | 188.5 | 245.2 | 185.9 | 241.0 | 1.7% |
| 全能遊戲設計師回退章 | 641.9 | 1403.5 | 635.5 | 927.3 | 33.9% |
| 詭秘之主長章 | 4239.8 | 4975.0 | 4101.4 | 4590.0 | 7.7% |


## 字型讀取證據

以下取連續捲動路徑，避免分頁啟動章的字型事件混入目標章。`epub.font.fetch` 是既有 SourcePerfTrace；它有 1 ms 輸出門檻，因此次數是捕捉到的 fetch span 數。回退章的本輪 fetch 屬於 Legacy，Browser 不做字型準備。

| 案例 | 基線 fetch 時間／span | 本輪 fetch 時間／span | 本輪 Browser 字型準備 |
|---|---:|---:|---:|
| 全職高手短章 | 242 ms／4 | 123 ms／2 | 123.5 ms，1 次 |
| 詭秘之主短章 | 645 ms／11 | 58 ms／1 | 58.0 ms，1 次 |
| Project Hail Mary | 0 ms／0 | 0 ms／0 | 0.0 ms，1 次 |
| 全能遊戲設計師回退章 | 616 ms／12 | 152 ms／3 | 0.0 ms，0 次 |
| 詭秘之主長章 | 657 ms／11 | 353 ms／6 | 355.2 ms，1 次 |


字型準備以 `browser.font.prepare` 記錄 requests 數量及時間；CSS ingestion 已不包含字型 bytes。字型內容、字型 asset 註冊與快取仍由既有 resolver/service 負責。`processedCSS` 的舊診斷入口保留其先前完整字型準備語義，production admission 使用 `cssFrontendInput`。

## 改動與回歸

- 掃描結果新增 `BrowserFontRequest`、`fontRequests`，沿用原本的 resolved tree；涵蓋繼承、block strut、ruby、已 materialize 的 `::first-letter`、CSS glyph fallback families，以及讀者粗體設定。
- 能力回退不準備 Browser 字型；接受章節在分頁與捲動排版前都先準備所需的 face。
- 可用的讀者字型覆寫可略過 EPUB 字型需求；失效的選擇仍準備出版物字型。字型／粗體切換會使 admission demand 失效並重新取得。
- 回歸觀察真正 shaping resolver 的需求，並比較按需與原 eager 路徑的版面／字型／來源／互動指紋。一般、粗體、斜體三種 face 均準備；未使用的 face 不註冊，重複準備不重讀。

| 測試類別 | 通過項數 |
|---|---:|
| BrowserFontDemandTests | 4 |
| EPUBAuthoredFontCascadeTests | 2 |
| BrowserLayoutPageEngineTests | 17 |
| BrowserLayoutFontFallbackTests | 9 |
| CoreTextWritingModeTests | 25 |
| BrowserVerticalReaderRouteTests | 2 |

上述各類逐類使用 `scripts/xctest.sh` 執行，均有 `TEST SUCCEEDED`；涵蓋最後相關修改。新增測試最初的編譯／預期問題已修正；早期失敗 run 不列為通過證據。

## 驗收判斷與下一步

- 全職高手短章：Auto 分頁降低 17.2%，捲動降低 14.4%。本輪 Auto／Legacy 比為 1.07 倍、1.09 倍。
- 詭秘之主短章：Auto 分頁降低 57.8%，捲動降低 57.6%。本輪 Auto／Legacy 比為 1.10 倍、1.11 倍。
- Project Hail Mary：Auto 分頁降低 2.0%，捲動降低 1.7%。本輪 Auto／Legacy 比為 1.94 倍、1.30 倍。
- 全能遊戲設計師回退章：Auto 分頁降低 35.0%，捲動降低 33.9%。本輪 Auto／Legacy 比為 1.45 倍、1.46 倍。
- 詭秘之主長章：Auto 分頁降低 7.4%，捲動降低 7.7%。本輪 Auto／Legacy 比為 1.16 倍、1.12 倍。

第一輪提議的「兩個重字型短章與回退章均至少降低 30%」目標未全部達到；不宣稱整體效能驗收完成。


下一個單位先在正式路徑拆量 scanner 的 declaration matching／computed-style tree 與 Current frontend 的對應 SourcePerfTrace 階段。能力掃描目前連只含已支援屬性的規則也執行 selector matching，之後又解析 CSS 建立 style tree；可先限定 matching 到含潛在不支援宣告的規則，並重用已解析的規則。驗收需保持 capability reasons、font demand、來源／版面指紋等價，再重跑相同量測。

接著才沿用同一章節的 DOM／cascade 準備結果給排版，先定義字型準備與 metrics-dependent used values 的邊界，再做 document-owned 的準備產物。長章圖片的提前載入仍需獨立量測處理。

正式套件發布、版本要求與 resolved pin 更新、普通 `.xcodeproj` 的 59 項回歸均已完成。下一個單位仍是 scanner／frontend 的細分量測與等價性優化。

## 量測邊界與重現

- Xcode 27.0、iPhone 18 Pro Max／iOS 27.0 模擬器、Debug，viewport 390×800。與基線相同的 5 案例×4 路徑×6 觀測；剔除 repetition 0，統計 100 筆有效資料。
- 每次 fresh publication／engine，OS 檔案和字型快取暖；分頁每次等待 byte-size scan 最後一章完成再進下一觀測，避免掃描重疊。
- 同時重跑純 Legacy 作為控制組。跨 run 的 Legacy 也會有波動；表格保留它，不能把全部 Auto 時間差都歸因於字型。完整範圍與 scanner warm probe 在 JSON 中；probe 在計時區外，不能當成精確可加總分解。
- 量測 engine first-ready callback／scroll chunk ready；沒有量測點書到螢幕第一幀，也沒有實機驗證。
- 本輪來源雜湊涵蓋 ReaderCore 與套件 sources，測前／測後均相同；原基線 JSON／summary 已保留。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
YUEDU_DEST=id=670FCE12-43E9-444F-ACAD-96AACDB4EAEC \
YUEDU_WORKSPACE=/tmp/YueduFontDemand.xcworkspace \
TEST_RUNNER_YUEDU_LOADING_BENCHMARK=1 \
TEST_RUNNER_YUEDU_LOADING_BENCHMARK_OUTPUT=loading-benchmark-2026-09-30-font-demand.json \
bash scripts/xctest.sh -t 1800 -l /tmp/yuedu-loading-benchmark-font-demand.log -- \
  -only-testing:'yuedu appTests/EPUBEngineLoadingBenchmarkTests' \
  -resultBundlePath /tmp/yuedu-loading-benchmark-font-demand.xcresult \
  -testLanguage zh-Hant -testRegion TW
```

workspace 僅引用原始 App `.xcodeproj` 與 `<repo>/YueduCoreText`。詳細 log／xcresult 路徑及來源驗證在 summary metadata。

