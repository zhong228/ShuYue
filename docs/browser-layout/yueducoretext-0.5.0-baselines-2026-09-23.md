# YueduCoreText 0.5.0 之後的幾何基準重錄（2026-09-23）

## 背景

YueduCoreText 0.5.0（`339b6ff`，2026-09-13）改了三件事：

- 行框改成 CSS 半行距加父字型 strut（`InlineLayout.lineMetrics`）。
- 英文斷行改成符合 CSS：只有設了 `overflow-wrap` / `word-break` 才能在字中間斷行。
- 把 `lang` 交給 CoreText 參與字形排列。

App 在 `62c2656b` 升到 0.5.0 時，只跑了英文排版那幾組測試。下面四組幾何基準因此從那天起一直失敗，共 10 個 issue，而且都是 0.5.0 以前錄的。

環境：Xcode 27.0（27A266a）、iOS Simulator 27.0（24A434）、iPhone 18 Pro Max。套件為工作區（`cfc8e0a` 加未提交改動），App 為 `97c6fa81` 加未提交改動。

| # | 測試 | 失敗原因 | 處理 |
|---|---|---|---|
| 1 | `BrowserLayoutInlineFormattingContextParityTests` 7 個指紋 | 0.5.0 行框模型 | 用 0.4.0／0.5.1 重算證明後重錄 |
| 2 | Corpus 的 same-process legacy oracle | 兩條半行距算式差 1 ULP | 引擎合併成單一函式 `inlineBox` |
| 3 | `laterLinesKeepParagraphStringIndices` | `AVAVAVAV` 在 0.5.0 起不能字中斷行 | fixture 設 `overflowWrap = "anywhere"` |
| 4 | 全書斷行基準 `redchamber.tsv` | 9/09 前就存在的漂移，加上 0.5.0 | 舊檔另存後重錄，逐章歸因 |

## 1. Parity 指紋

**方法。** 把 7 個 fixture 和 `BrowserLayoutGeometryFingerprint` 原樣搬成一個暫時的套件測試，只改了三處：

- 拿掉 App 的 import。
- helper 改名，避免衝突。
- `BrowserChapterLayout.buildPageRanges` 改呼叫它內部轉呼叫的 `BrowserPageGeometry.buildPageRanges`。

再在 scratchpad 的暫時 worktree 用套件 0.4.0（`4a49d31`）和 0.5.1（`cfc8e0a`）各跑一次，和 App 在工作區的實測結果比對。暫時測試、worktree 和它的 DerivedData 都已刪除。

**結果。** 同一環境下，0.4.0 重算出的 7 個雜湊與測試裡存的值完全相同，而那些值是 8/25（6 個）和 9/02（1 個）錄的。0.5.1 重算的結果則與工作區實測完全相同。所以：

- 從 8/25 到 0.4.0，這些 fixture 的幾何都沒變，也沒有環境漂移。
- 差異全部來自 0.5.0 那次提交。
- 未提交的改動（包括我這次的修正和另一個 session 的非同步排版）沒有改到任何一個位元。

| fixture | 原雜湊（＝0.4.0 重算） | 新雜湊（＝0.5.1 重算＝工作區） |
|---|---|---|
| ordinaryProse | `ffde4343…` | `cba5c8c9…` |
| multiRunLink | `1b3cad8d…` | `5749e56c…` |
| horizontalRuby | `487b5140…` | `50cc27c4…` |
| inlineImage | `ed7c8913…` | `1574c8f6…` |
| leftAndRightFloat | `e6ccd971…` | `3aaccfaa…` |
| paginationAndPageSourceRanges | `4b98122d…` | `c1452946…` |
| selectionAndLinkHit | `9ff4b641…` | `00c2be59…` |

**逐列差異（0.4.0 → 0.5.1）。**

- 7 個 fixture 的列數都相同。
- 所有 `run` 列都沒變：字元範圍、x、寬度、字型完全一致，所以斷行和水平位置都沒有任何改變。
- 變的只有 `line` 的基線或高度、文字片段的 y 和高度，以及 ruby、圖片兩個 fixture 的 box 高度。

以 Helvetica 17pt 實測的字型度量：

- `UIFont.ascender` = 15.6403，`CTFontGetAscent` = 13.0903，兩者差 0.15em。
- descender 兩邊都是 3.9097。
- PingFang 的兩套度量完全相同。

代入 0.4.0 與 0.5.0 的算式，每一個變動值都能精確重現：

| 情況 | 0.4.0（CTLine 度量，`max(line-height, 字形高)`） | 0.5.0（UIFont 度量的半行距加 strut） |
|---|---|---|
| 行高 24 的基線 | 13.0903 + (24 − 17)/2 = **16.5903** | 15.6403 + (24 − 19.55)/2 = **17.8653** |
| 行高 23 的基線 | **16.0903** | **17.3653** |
| 行高 25 的基線 | **17.0903** | **18.3653** |
| 72×48 行內圖、行高 25 | max(25, 48 + 3.9097) = **51.9097** | 48 + (3.9097 + 2.725) = **54.6347**（strut 撐開基線以下） |
| ruby、行高 28 | 26.52 + 5.78 = **32.3** | 26.52 + (3.9097 + 4.225) = **34.6547**（strut 撐開基線以下） |

這兩項正是 0.5.0 的設計：半行距改用字型度量，以及 strut 參與行框（見 `english-typography-2026-09-13.md` 裡「166.6 高的圖、行框變 172.04」）。

- 基線移動 1.275pt，只出現在 UIFont 與 CoreText 度量不同的字型（Helvetica），行高不變。
- 字形仍完整落在行框內：字頂在 17.8653 − 13.0903 = 4.775 ≥ 0。

## 2. Corpus legacy oracle

- **修正前**：body 高度差 1 ULP。舊路徑（沒有 strut）算出 `22.999999999999996`，現行路徑算出 `23.0`。原因是 strut 用 `(lh − asc + desc)/2`，文字用 `(lh − (asc − desc))/2`，兩式代數相等，但運算順序不同。
- **修正**：套件 `InlineLayout.lineMetrics` 新增 `inlineBox(_:lineHeight:)`，strut 和每個文字區段共用。文字區段原本的運算順序不變，只有 strut 改走同一條算式。
- **修正後**：oracle 逐位元一致並通過。7 個指紋的新雜湊在修正前後完全相同，這項修正沒有改到它們任何一個位元。

## 3. `laterLinesKeepParagraphStringIndices`

- **修正前**：`lines.count` = 1。`AVAVAVAV` 是一個沒有斷點的單字，0.5.0 起只有作者允許時才在字中間斷行，符合 CSS 的 `overflow-wrap: normal`。
- **修正**：fixture 設 `style.overflowWrap = "anywhere"`。保留字偶距（AV），測試的原本目的「後續行保留段落字串索引、片段位置對應 CTLine」維持不變。
- **修正後**：通過，`lines.count > 1`，其餘斷言也都通過。

## 4. 全書斷行基準 `redchamber.tsv`

**決策。** 9/09 的調查決定「在歸因完成前不覆寫」（見 `line-break-baseline/attribution-2026-09-09.md`）。之後沒有人繼續查，差異從 272 章累積到 422 章，而且這份基準在現在的系統上連當時的程式都重現不出來，所以會一直失敗，也就抓不到新的回歸。使用者 2026-09-23 選擇：舊檔另存，重錄成新基準，並寫清楚哪些差異已確認、哪些來源不明。

- 舊基準：`line-break-baseline/redchamber-2026-09-02.tsv`（與重錄前的 `redchamber.tsv` 逐位元相同）。
- 新基準：`line-break-baseline/redchamber.tsv`，用測試內建的 `YUEDU_LINEBREAK_REGEN=1` 重錄。
- 逐章資料：`line-break-baseline/attribution-2026-09-23.tsv`，每章都列出新舊頁數、片段數、首尾行幾何與雜湊。

**比較的狀態。**

- **G**：9/02 的舊基準。
- **C2**：9/09 當天的狀態。由 `attribution-2026-09-09.tsv` 的 current 欄，加上 `attribution-2026-09-09-run-geometry.tsv` 列出的 163 章還原而成。163 章的 before 與 current 逐一相符，C2 與 G 有 272 章不同，與 9/09 文件記載一致。
- **T**：現行程式，也就是新基準。
- **開關版本**：在套件暫時加入預設關閉的開關，把 0.5.0 的機制逐項切回 0.4.0 後重排全書。四項機制是：行框算法、兩端對齊的 7 成填滿限制、交給 CoreText 的 `zh-CN` 語言屬性、英文單字保護。開關已全部移除。

**結果。**

| 分類 | 章數 | 判定 |
|---|---:|---|
| `UNCHANGED` | 36 | T = G |
| `V050_LINE_BOX` | 99 | 9/09 時與 G 相同。只把行框算法切回 0.4.0，就逐字回到 C2：**確定是 0.5.0 行框模型** |
| `V050_VERTICAL+HORIZONTAL_RESIDUAL`（9/09 已不同） | 272 | 9/09 調查中來源不明的那批，之後又變。四項機制都切回後，頁數、片段數、首尾行 y 與高度都等於 C2，只剩水平量寬或內部片段不同 |
| `V050_VERTICAL+HORIZONTAL_RESIDUAL`（9/09 相同） | 51 | 9/09 後才變。同上，四項機制切回後只剩水平或內部差異（47 章只有內部片段不同，4 章首尾行寬度不同） |

- 總頁數由 3,820 變 4,022，文字片段由 137,294 變 138,805。
- **9/09 之後**的頁數、行數和垂直位置變化，都已確認來自 0.5.0：行高與 y 由行框模型造成；116 章的片段數變化由 `zh-CN` 語言屬性造成，切回後行數即回到 C2。那 272 章在 9/09 以前與 G 的差異不在此列，來源仍如 9/09 文件所述未明。
- 兩端對齊的 7 成限制對這本書幾乎沒有影響：323 章中有 322 章與只切行框時相同。
- 這本書的 CSS 沒有 `*`、`+`、`~`、`:first-of-type` 選擇器，0.5.0 的選擇器改動與它無關。

**尚未解釋。** 323 章在四項機制都切回後，仍與 C2 有水平差異：首尾行寬度（131 章）、首行 x 以整數 pt 位移（21 章，例如 −12、−15、−9），或只有內部片段不同（171 章）。

候選來源包括：

- 9/09 之後的模擬器版本變更（24A5423a → 24A434）。
- App 端字型解析的改動（`EPUBStyleResolver` 已註冊字型快照、`BrowserDocumentFontResolver`）。
- 套件 0.3.0 抽出與 0.4.0 的其他改動。

這次沒有逐項證明，不宣稱已解釋。其中 272 章在 9/09 就已經對不上 G，與 9/09 文件的結論一致。

**舊的更新路徑。** 測試裡的 `updateApprovedRows`（2026-08-31 attribution，寫死 433 列）和 `updateCoreTextNormalizationRows`（2026-09-02，18 列），都是針對舊基準的一次性更新；重錄之後它們一執行就會報錯。依使用者決定已刪除，連同 `/tmp` 核准標記的檢查。舊的 attribution 文件保留作為歷史紀錄。之後要更新基準，一律使用測試內建的 `YUEDU_LINEBREAK_REGEN=1`，並比照本文件補一份逐章 attribution。
