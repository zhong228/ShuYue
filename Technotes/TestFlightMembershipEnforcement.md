# TestFlight 永久會員驗證

## 生效規則

- Release 的 `AppTransaction` 經驗證為 Sandbox 時，每次啟動／回到 active 都透過帳號後端執行 `verifyTestFlightAccess`。正式 App Store 版本不套用此限制，DEBUG 本機開發仍可測試沙盒購買。
- Firebase 直連與 Gateway `/v1/subscription/testflight-access` 都呼叫同一 Cloud Function。只接受登入 token 的 UID，不接受客戶端提交 UID、會員旗標或快取放行。
- Function 逐筆向 Apple Production API 查詢已綁定的永久購買並驗證 JWS，再讀取最新 binding；Sandbox、月會員、未登入、退款、查詢失敗均不能通過。沒有離線寬限。
- TF 通過驗證後取得 Pro；Sandbox 交易、Keychain、iCloud 快取不能越過此閘門。未通過時顯示登入／重試／切換帳號入口，保留本機資料。舊前景／舊帳號的非同步成功不能解除新閘門。
- Apple 通知更新 binding 後，Firestore trigger 重算會員並移除該帳號邀請郵箱對 **MoYue 這一個 App** 的測試權限。失敗保留 `revocationPending` 並由事件重試；每小時稽核也會向 Apple 查核歷史名單。稽核保存游標，超時預算前交棒給下次排程。
- `signedDate` 在 Firestore transaction 內排序，舊通知不能覆蓋較新的退款。正式版重新綁定也先向 Apple 取現況，防止重送退款前 JWS。退款撤回或重新購買後可重新申請同一郵箱，不新增第二個名額。

## 部署前必要設定

App Store Server API 使用 **In-App Purchase Key**，不要拿目前寄 TF 邀請的 App Store Connect API Key 混用。

1. 在 App Store Connect → 使用者與存取權限 → 整合 → App 內購買項目建立金鑰，保存下載的 `.p8`、Key ID、Issuer ID。不要放進 Git 或聊天訊息。
2. 對 `yuedu-readerr` 設定三個 Firebase Secrets：
   - `APP_STORE_SERVER_ISSUER_ID`
   - `APP_STORE_SERVER_KEY_ID`
   - `APP_STORE_SERVER_PRIVATE_KEY`（`.p8` PEM 的 Base64，與現有 ASC secret 的編碼方式相同）
3. 先部署 Functions。新增 `verifyTestFlightAccess`、`reconcileTestFlightMembership`、`auditTestFlightMembership`，並更新綁定、邀請、刪除帳號與 Apple 通知函式。新金鑰未配置時不得部署；正式版購買綁定也需要此金鑰。
4. 確認 Production 的 App Store Server Notifications V2 URL 指向 `appStoreServerNotifications`；用 Apple 測試通知確認可達，再用受控帳號驗證實際退款／撤權流程。測試通知成功本身不等於退款流程已驗證。
5. 更新 Gateway，實測已登入帳號的新端點。確認中轉只會代表登入 UID 呼叫同一 Function。
6. 發布包含此閘門的新 TF build，再以正式永久會員測試啟動、前背景、斷線、切換帳號與退款。不得只部署 App；後端或中轉缺少新接口時，TF 會依嚴格規則暫停使用。

## 範圍與驗證邊界

新閘門無法注入已安裝的舊 TF binary。需另行處理舊 TF build 的發布／停止測試；不能把「已從名單移除」描述為已驗證所有離線舊版立即停用。手動邀請且未經 `testflightProRequests` 記錄的舊測試者不會由此名單稽核移除，但新 TF build 仍要求正式永久會員。

本機回歸涵蓋會員查核、退款／重送／亂序、ASC App 關聯移除、中轉 UID 與不快取、App 閘門的離線／背景／切換帳號競態，以及覆蓋已開啟的閱讀頁／彈窗並保留導覽狀態。

## 2026-09-28 部署紀錄

- 三項 App Store Server API secrets 已設定；使用真實 In-App Purchase Key 呼叫 Production 通知歷史 API 成功。私鑰存放於工作區外的 `~/.config/yuedu/private-keys/`，目錄權限 0700、私鑰 0600，未放入 Git。
- 七項相關 Cloud Functions 均已部署並確認為 ACTIVE。Firebase 直連實測未登入 401；臨時登入帳號即使提交偽造 UID／會員旗標仍得到 `allowed: false`，測試帳號隨後刪除。
- Gateway 已部署 `yuedu-gateway:membership-20260928`，沿用原環境檔、憑證掛載、127.0.0.1:8080 與 Caddy。正式域名健康／就緒檢查成功；已登入無會員帳號回傳 200、`allowed: false`、`Cache-Control: no-store`，未登入 401。舊容器與映像保留為 `yuedu-gateway-before-membership-20260928`／`yuedu-gateway:before-membership-20260928`，原 source 另有備份。
- App Store Connect 的 Production／Sandbox URL 均已設定到 `https://asia-east1-yuedu-readerr.cloudfunctions.net/appStoreServerNotifications`，版本 V2，重新讀取確認保存。設定剛保存時 Apple 測試 API 暫時回傳 `4040007`；後續兩個環境均成功請求測試通知，查詢送達狀態皆為 `SUCCESS`。啟動查核直接查 Apple 交易，不依賴通知送達。
- Functions 24 項、中轉 46 項、iOS `TestFlightAccessTests` 7 項回歸通過；最後一版修改的 Release 模擬器編譯成功。實際 Production 退款通知、Firestore 撤權觸發及新 TF 安裝的端到端流程仍需受控帳號驗證；尚未發布新的 TF binary。

Apple 文件：[API 金鑰](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)、[移除 App 測試權限](https://developer.apple.com/documentation/appstoreconnectapi/delete-v1-betatesters-_id_-relationships-apps)、[退款通知](https://developer.apple.com/documentation/storekit/handling-refund-notifications)。
