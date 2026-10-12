---
title: YueduCoreText 0.6.1 發布與正常 project 驗證
updated: 2026-09-30
tags: [browser-layout, release, fonts]
---

# YueduCoreText 0.6.1 發布與正常 project 驗證

[目前狀態](../STATUS.md) · [按需字型與前後量測](../loading-benchmark-2026-09-30-font-demand.md)

## 發布

- [GitHub release 0.6.1](https://github.com/CHANG-JUI-LIN/YueduCoreText/releases/tag/0.6.1)，正式版本、非 draft／prerelease。
- Commit：`d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7`；annotated tag：`3097f36893cdeb34b97451e5149e0f12ab4c3645`。
- 套件公開 API 直接回歸 2 項、發布 metadata 回歸 9 項皆 `TEST SUCCEEDED`，於原始 checkout 執行，涵蓋提交前最後修改。
- 新增 computed-style font demand 與 configuration-aware scanner；保留原 ordered-input scanner 的雙參數函數簽名與原 HTML/CSS 入口。字型資源與 fallback 政策仍由宿主負責。
- 套件原有未提交的 0.6.0 changelog 補充與本次修改一併納入發布。

## 正式依賴

App 最低版本要求改為 0.6.1，仍限制於 0.6.x。Xcode 使用正常 `Yuedu-Reader.xcodeproj` 從 GitHub 解析並產生 `Package.resolved`：

```json
{"revision":"d7e16bd9aa64b80c4d0bc70fa0fc069409c34ea7","version":"0.6.1"}
```

其餘 27 個遠端 pin 的 identity／location／revision／version 均與發布前相同。正常 project 的 `SourcePackages/checkouts/YueduCoreText` HEAD 與上述 revision 相同，66 個套件 Swift source 與已測試的本機 release 全部逐檔一致，未修改遠端 checkout。

## 正常 project 回歸

普通 `.xcodeproj`、正式遠端 0.6.1、無本機 package override，六類逐類使用 `scripts/xctest.sh` 執行，**59 項全部通過**，每個 log 都有 `TEST SUCCEEDED`；相關 target 已實際編譯。

| 類別 | 通過項數 |
|---|---:|
| BrowserFontDemandTests | 4 |
| EPUBAuthoredFontCascadeTests | 2 |
| BrowserLayoutPageEngineTests | 17 |
| BrowserLayoutFontFallbackTests | 9 |
| CoreTextWritingModeTests | 25 |
| BrowserVerticalReaderRouteTests | 2 |

分頁引擎類別首次正式 run 因其他建置占用 `build.db` 而取消，執行 0 項測試；確認鎖已釋放後以獨立 v2 log 重跑通過，原 run 不計入通過證據。

Xcode 27.0、iPhone 18 Pro Max／iOS 27.0 Simulator。沒有操作個人實機。原始 log／xcresult 路徑及 source hashes 見 [正式整合校驗](release-0.6.1-verification.json)。

## 量測與發布的邊界

100 筆有效觀測在發布前、引用兩個原始 checkout 的本機 workspace 完成。發布整理只為 scanner 加回原雙參數 overload，configuration-aware 的 production scan body 與 App ReaderCore 未變；測試 wrapper 新增 package directory／scheme 支援。量測當時的 source hashes 與 pin 均保留為歷史紀錄，後續正式整合另附結果，不回寫為遠端量測。

這次完成按需字型與正式依賴整合。Auto 仍慢於同輪 Legacy，尚未完成整體載入效能驗收；下一個工作單位先拆量 scanner declaration matching／style tree 與 Current frontend，再依相同原書、路由和等價性回歸驗證縮減多餘工作。

## 遠端 CI

[本次套件 CI](https://github.com/CHANG-JUI-LIN/YueduCoreText/actions/runs/36725839611)已通過。完整 log 確認 iOS device Release build 為 `BUILD SUCCEEDED`，套件核心 142 項、typography 11 項與獨立 public API consumer 8 項均通過，兩個測試階段均有 `TEST SUCCEEDED`。CI 使用 Xcode 16.4／iPhone 16 Pro Simulator；沒有安裝或操作個人實機。
