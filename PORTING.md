# railloader-continued — Factorio 1.1 → 2.0 移植計畫

本檔是階段一（忠實移植，不加功能）的施工圖。每一項都標明**檔案:行**、**改什麼**、**為什麼**。
目標：行為與上游 1.1.6 一致，但跑在 Factorio 2.0.77。不改玩法、不改平衡、不加新功能。

> ## 施工結果：階段一已完成（2026-08-10）
>
> 載入測試通過（`Prototype list checksum: 2130422175`，`--create` 回報 `Done.`）。
> 施工中發現本檔**有 5 處與 2.0.77 實際行為不符**，已依實機探測修正，補記於此以免日後重踩：
>
> 1. **1-2-f 誤判**：`Recipe.lua` 並非「在 2.0 完全可用」。`Recipe.lua:18` 的
>    `data.raw[type][name]` 會 nil-index crash — 2.0 不為「零個原型的類型」建立
>    `data.raw` key。已加 `data.raw[type] and` 檢查。此檔仍應保留（xander 相容）。
> 2. **1-3-h 誤判**：`show_error()` 不能「保持原樣」。`flying-text` **實體型別已於 2.0 移除**
>    （base changelog L3240），照做會 crash。已改用 `create_local_flying_text`。
>    `inserterconfig.lua` 的 `display_configuration_message()` 同一問題，本檔未列。
> 3. **本檔完全未提的破壞**：`use_filters` 在 2.0 預設 `false`。實測設了濾器但未設此旗標的
>    機械臂**照樣搬運非濾器物品**（coal 被搬 25 個 vs 設 true 後 0 個）。靜默、不 crash。
> 4. **本檔完全未提的破壞**：`circuit_condition` 不可再包一層 `condition`
>    （巢狀寫法不報錯但丟棄 `first_signal`）；`circuit_enable_disable` 預設 false，
>    不設則「Disable rail loader」訊號無效。另 `spill_item_stack` 改單一 table 參數、
>    `max_circuit_wire_distance` 改為 `get_max_circuit_wire_distance()` 方法。
> 5. **行號與處數偏差**：`__railloader__` 是 12 處非 11；`configchange.lua` 的 `global`
>    是 15 處非 12；`get_contents()` 在 `bulk.lua:170` 非 196；`created_entity` 是 3 處非 4。
>    `orthogonal_direction` 已確認無呼叫者並刪除。
>
> **教訓**：本檔「已查證」的項目仍有 2 處誤判，且漏掉 4 個靜默破壞。
> 靜默失效（不 crash 的行為變更）無法靠載入測試發現，只能靠實機斷言。
>
> 尚未驗證、需真人進遊戲操作的項目見「階段 1-5 遊戲內驗證清單」中未打勾者。

## 專案定位

- **上游**：<https://github.com/mspielberg/factorio-railloader> v1.1.6（2022-07-20），LGPLv3
- **本 repo**：保留完整上游 git 歷史，分支 `factorio-2.0`，remote `upstream` 指向原 repo
- **mod 內部名稱**：`railloader-continued`（已確認 portal 上未被使用）
  - 一旦發布**永遠不能改**，且是存檔內的永久識別符
  - 不可用 `railloader`（therax 的）或 `railloader2`（Keeper317 的，已 deprecated）
- **目標版本**：Factorio 2.0（伺服器現為 2.0.77）。2.1 留待階段二
- **參考但不採用**：`IlRomanenko/factorio-railloader` 分支 `factorio_2.0` commit `bbc846ee`
  - 只在 `pictures.lua` 有參考價值，其餘留有 4 個 runtime crash 與 3 個靜默錯誤
  - 詳見文末「為何不從該分支起步」

## 授權合規（動工前必讀）

LGPLv3 允許 fork、修改、再發布，但**衍生作品必須維持同授權**。具體義務：

1. `LICENSE` 檔**原封不動保留**（LGPLv3 全文）
2. `README.md` 的致謝段落**必須保留**：
   > * Arch666Angel for the loader graphics.

   圖檔不是 therax 畫的，是 Arch666Angel 的作品由 therax 以 LGPL 散布。沿用圖檔就繼承這個署名義務。
3. 新增 `NOTICE` 或在 README 明確標示：本 mod 衍生自 mspielberg/factorio-railloader，附原始 repo 連結與 v1.1.6 基準點
4. portal 發布時 license 欄位選 **LGPLv3**，不可改成其他授權

沿用的圖檔共 9 個 PNG（全部保留，不需重畫）：

```
graphics/icons/railloader.png              graphics/icons/railunloader.png
graphics/railloader-placement-proxy/horizontal.png   .../vertical.png
graphics/railloader/structure-horizontal.png         .../structure-vertical.png
graphics/railunloader/structure-horizontal.png       .../structure-vertical.png
graphics/technology/railloader.png
```

---

# 階段 1-1：重新命名與路徑

mod 資料夾名與 `info.json` 的 `name` 必須一致，且所有 `__railloader__` 資源路徑都要跟著改。

| 項目 | 動作 |
|---|---|
| `info.json` | `name` → `railloader-continued`；`version` → `2.0.0`；`factorio_version` → `"2.0"` |
| `info.json` | `author` 保留 Therax，新增 `contact`/`homepage` 指向本 fork；`description` 註明是延續版 |
| 全部 `.lua` | `__railloader__` → `__railloader-continued__`（**11 處**，散落在 `prototypes/entity/*.lua`、`prototypes/technology/railloader.lua` 等） |
| `changelog.txt` | 最上方新增 `2.0.0` 區塊，註明「Port to Factorio 2.0. Fork of railloader 1.1.6 by Therax.」 |
| `pack.sh` | 依 `info.json` 的 name 自動命名，**不需改**；但 Windows 上需另備打包方式（見 1-6） |

**不要改的**：所有**原型名稱**（`railloader-chest`、`railloader-rail`、`railloader-placement-proxy` 等）。
理由：改原型名會讓引擎把舊存檔中的實體當成未知原型刪除，且會連帶讓 8 個 locale 檔全部失效。
`IlRomanenko` 把 `railloader-rail` 改名成 `railloader-rail-new`，正是它 migration 失效的根因。

---

# 階段 1-2：data 階段（不通過就無法載入）

## 1-2-a `prototypes/entity/pictures.lua` — 最大的一塊

上游此檔 243 行，是全案最高風險處。已用 `factoriotools/factorio:2.0.77` image 取得權威結構。

### 問題 1：`rail_pictures()` 全域函式在 2.0 不存在

`pictures.lua:13` `local all_base_rail_pictures = rail_pictures()` → **nil call，載入即死**。

2.0 拆成 `legacy_rail_pictures(rail_type)` 與 `new_rail_pictures(rail_type)`
（見 image 內 `/opt/factorio/data/base/prototypes/entity/rail-pictures.lua:110,189`）。

因為本 mod 的 `railloader-rail` 是 `data.raw["straight-rail"]["straight-rail"]` 的 deepcopy，
而 2.0 的 `straight-rail` 用的是 `new_rail_pictures("straight")`，**但**上游的視覺意圖是舊式直軌外觀。
兩個選項：

- **選項 A（建議）**：改用 `legacy_rail_pictures("legacy_straight_rail")`，維持與 1.1 一致的外觀
- 選項 B：改用 `new_rail_pictures("straight")`，與玩家自己鋪的 2.0 軌道外觀一致

建議 A，因為階段一的目標是「行為與 1.1.6 一致」，且 proxy 預覽圖只是輔助定位用。
但**須在遊戲內確認**疊在新式軌道上不會有明顯視覺落差；若有落差則改採 B。

### 問題 2：回傳結構的 key 全變了

| 1.1 | 2.0 |
|---|---|
| `all_base_rail_pictures["straight_rail_vertical"]` | `[...]["north"]` |
| `all_base_rail_pictures["straight_rail_horizontal"]` | `[...]["east"]` |

`pictures.lua:18` 的 `"straight_rail_" .. direction` 拼接必須改成方向名映射
（`vertical` → `north`，`horizontal` → `east`）。

### 問題 3：`hr_version` 已移除

`pictures.lua:31-38`、`60-67`、`77-84`、`93-100`、`111-118`、`126-133` 共 6 個 `hr_version` 區塊全部要攤平。
2.0 的 `legacy_rail_pictures` 回傳值**已內建 `scale = 0.5`**，直接沿用 `l.scale` 即可，不要再自己寫死。

### 問題 4：圖層清單多了一個成員

2.0 的 `legacy_rail_pictures` 除了原本的 `metals`/`backplates`/`ties`/`stone_path`/`stone_path_background`，
還多了 **`segment_visualisation_middle`**。上游 `all_layers`（`pictures.lua:45`）是白名單列舉，
所以**不受影響**——但若改成迭代全部 key 就會誤包含，不要那樣改。

另注意 2.0 用 `variation_count` 而非 `frame_count`，複製欄位時要對應。

### 問題 5：cargo-wagon 原型結構重組

| 1.1（`pictures.lua:48-49`） | 2.0 |
|---|---|
| `.wheels.filenames[N]` + `.wheels.hr_version.filenames[N]` | `.wheels.rotated`（`util.sprite_load` 產出，`direction_count = 256`） |
| `.pictures.layers[1]` | `.pictures.rotated.layers[1]`（`direction_count = 128`，共 3 層：本體/mask/shadow） |

上游靠 `filenames[N]` 索引挑特定角度的貼圖（`filenames[1]`=垂直、`[3]`=水平等）。
2.0 改成 `util.sprite_load` 的 spritesheet 形式後**這個索引手法不再適用**。

這是本檔最需要在遊戲內反覆試的部分。務實作法：先讓它能載入（用單一 sprite 或簡化圖層），
確認整體流程通了之後，再回頭調整 proxy 預覽圖的精確外觀。**不要為了像素完美卡住整個移植。**

## 1-2-b `prototypes/entity/rail.lua`

```lua
local loader_rail = util.table.deepcopy(data.raw["straight-rail"]["straight-rail"])
```

2.0 仍有 `straight-rail` 原型（新式），deepcopy 本身可用。但需確認：

- 新式 `straight-rail` 帶有 2.0 專屬欄位（`extra_planner_goal_penalty`、`factoriopedia_alternative`），
  deepcopy 後應清掉 `factoriopedia_alternative` 避免指向自己
- 保留 `flags = {"player-creation"}`
- 建議補 `hidden = true`（2.0 新欄位）避免出現在 Factoriopedia
- **不要改原型名**（見 1-1）

## 1-2-c `collision_mask` 格式

1.1 的字串陣列 → 2.0 的 `{layers = {...}}`。

| 檔案:行 | 1.1 | 2.0 |
|---|---|---|
| `railloader.lua:110` / `railunloader.lua` | `{"item-layer","object-layer","water-tile"}` | `{layers = {item = true, object = true, water_tile = true}}` |
| `railloader.lua:38,49,60` 等 6 處 | `collision_mask = {}` | **`collision_mask = {layers = {}}`** |

**關鍵陷阱**：`{}` 與 `nil` 不等價。`{}` = 不與任何東西碰撞；`nil` = 用該原型類型的預設 mask。
那些 structure / inserter 是疊在箱子與軌道上的內部實體，**必須完全不碰撞**。
`IlRomanenko` 把它們改成 `nil`，是靜默的行為變更。

## 1-2-d 機械臂原型

| 項目 | 動作 | 理由 |
|---|---|---|
| `stack = true` | → **`bulk = true`** | 2.0 把 `stack` 改名為 `bulk`。不改的話機械臂變成普通機械臂，吞吐被靜默砍半，且不吃 bulk 研究加成 |
| `uses_inserter_stack_size_bonus` | **不要加** | 預設就是 `true`，加了是 no-op。`IlRomanenko` 加這行反而讓人誤以為已處理 |
| `filter_count = 5` | 保留 | 2.0 仍有效 |

## 1-2-e 電路連接器

| 項目 | 動作 |
|---|---|
| `circuitconnectors.lua:21,31` | `circuit_connector_definitions.create` → **`create_vector`** |
| `railloader.lua:26-27`（proxy） | `circuit_wire_connection_points`/`circuit_connector_sprites` → **`circuit_connector = ...`**（單一欄位）|
| `railloader.lua` 的 inserter / chest | 上游**本來就是註解掉的**，維持註解即可，不是新問題 |

`circuitconnectors.lua:14-16` 引用全域 `universal_connector_template`，需確認 2.0 仍存在。

## 1-2-f 配方格式

`prototypes/recipe/railloader.lua`、`railunloader.lua`：

- `ingredients` 每項改具名 table：`{type = "item", name = "rail", amount = 3}`
- `result` → `results = {{type = "item", name = "railloader", amount = 1}}`

**`prototypes/recipe/Recipe.lua` 要保留**。它是純 `data.raw` 檢查（`select_ingredients`），
在 2.0 完全可用，提供 xander-mod 相容。`IlRomanenko` 刪掉它是移植的附帶損害，不是必要。

## 1-2-g pump 原型（placement proxy）

`fluid_box` 在 2.0 **必須有 `volume`**。加 `volume = 1`。

---

# 階段 1-3：control 階段（載入過了才會遇到）

## 1-3-a `global` → `storage`（全域）

| 檔案 | 處數 | 備註 |
|---|---|---|
| `control.lua` | L16, 247, 269 等 | |
| `EntityQueue.lua` | 13 處（L9,14,17,18,32,36,39,40,48,50,51,55,56） | |
| **`configchange.lua`** | **12 處** | L27,29,37,38,73,82,90,96,97,127-129,347,356 — **最容易漏，`IlRomanenko` 就漏了整支** |
| `spec/EntityQueue_spec.lua` | 測試 stub 需同步 | |

## 1-3-b `LuaInventory.get_contents()` 回傳格式（**最高優先**）

`bulk.lua:196`：

```lua
-- 1.1：name → count 的 map
for name in pairs(inventory.get_contents()) do
-- 2.0：array of {name=, count=, quality=}
for _, entry in pairs(inventory.get_contents()) do
  local name = entry.name
```

不改的話 `name` 會是整數 `1,2,3`，`string.find(1, pat)` 直接 crash。
**這是核心迴圈，每次列車進站都觸發**，是最確定會炸的一處。

## 1-3-c 電線 API 全面替換

1.1 的 `connect_neighbour` / `circuit_connection_definitions` / `defines.wire_type` **全部移除**。
2.0 用 `entity.get_wire_connector(defines.wire_connector_id.circuit_red/green, true).connect_to(...)`。

| 檔案:行 | 內容 |
|---|---|
| `control.lua:145-150` | `chest.connect_neighbour(ccd)`（來自 proxy 的連線）|
| `control.lua:151-153` | `ghostconnections.get_connections(proxy)` 迴圈 |
| `inserterconfig.lua:143-148` | `connect_and_configure_inserter_control_behavior` |
| `inserterconfig.lua:166-168` | **`replace_all_inserters`** — `IlRomanenko` 漏掉這處，改 runtime 設定就 crash |
| `ghostconnections.lua:20` | `ghost.circuit_connection_definitions` |

建議做法：寫一個共用 helper（複製連線、連接兩實體），四處都呼叫它，避免像上游那樣散落。

**`ghostconnections.lua` 不要刪**。它處理的是「附近指向本實體的 ghost」，
`IlRomanenko` 刪掉呼叫卻留著 `require`，結果是藍圖/機器人建造時電路連線靜默遺失。

## 1-3-d 方向 8 → 16

| 檔案:行 | 1.1 | 2.0 |
|---|---|---|
| `control.lua:117` | `if direction >= 4 then direction = direction - 4 end` | 需依 16 值重寫正規化 |
| `control.lua:120` | `(direction + (i-1) * 4) % 8` | **`(direction + (i-1) * 8) % 16`** |
| `util.lua:44-48` | `opposite_direction`：`>=4` / `±4` | `(direction + 8) % 16` |
| `util.lua:50-56` | `orthogonal_direction`：`<6` / `+2` | `(direction + 4) % 16`；**先確認有無呼叫者，無則刪除** |

`num_inserters` **保持 2**。上游註解說明用途是「支援半長車廂從兩側伸出」，兩個 180° 對向即可。
`IlRomanenko` 改成 4 且算式寫成 `(i % 2) * 8`，產生兩組完全重複的機械臂——那是為了掩蓋
`stack`/`bulk` 沒改造成的吞吐下降，不是必要。

## 1-3-e 機械臂濾器格式

`inserterconfig.lua:37-45`：`get_filter(i)` 現在回傳 `ItemFilter` table（含 `name`/`quality`/`comparator`），不是字串。

```lua
local filter = inserter.get_filter(i)
local filter_name = filter and filter.name    -- 需要這層
if not item_set[filter_name] then ...
```

不改的話 `item_set[table]` 恆為 nil，`inserter_configuration_changes` 每次都回傳 true，
造成**每次列車進站都跳一次設定提示**（靜默誤動作，不會 crash，所以容易漏掉）。

`inserterconfig.lua:66-68` 的 `set_filter(i, items[i])` 傳字串仍可用（ItemFilter 接受 string），
但為一致性建議也改成 table 形式。

## 1-3-f `event.created_entity`

已移除，改用 `event.entity`。`control.lua` 有 4 處（L41, 157, 177 等）。
直接改成 `event.entity`，不要留 `event.created_entity or event.entity` 的相容寫法。

## 1-3-g 其他

| 項目 | 動作 |
|---|---|
| `configchange.lua:293` | `game.entity_prototypes` → `prototypes.entity` |
| `control.lua:295-345` `on_blueprint` | `player.blueprint_to_setup` **在 2.0 仍存在**（已查證），非必改；但建議改用 `event.stack`/`event.record` 以支援藍圖圖書館 |
| `control.lua:335` `on_post_entity_died` | filter 寫法在 2.0 仍有效，不需改 |
| `util.lua:88-99` 之外的 rail 查詢 | `find_entities_filtered{type="straight-rail"}` 在 2.0 會**同時match玩家自己的軌道**，需加 name 過濾 |

## 1-3-h `show_error()` 保持原樣

上游 `control.lua:32-38` 是正常的 flying-text 提示。**不要註解掉**。
`IlRomanenko` 把它清空是 debug 殘留，導致放錯位置時靜默刪除 ghost 無任何回饋。

---

# 階段 1-4：migration 與舊存檔

因為原型名稱全部保留（見 1-1），舊存檔的實體不會被引擎當成未知原型刪除，
所以**不需要 `IlRomanenko` 那種重建軌道的 migration**。

需要處理的只有：

1. `configchange.lua` 的既有 migration 框架改用 `storage`（見 1-3-a），確保從舊版升級不 crash
2. 新增一則 `2.0.0` migration，只做必要的資料結構修正（若有）
3. `migrations/*.lua` 三支舊腳本檢查是否有已移除 API

**明確界定**：從 1.1 存檔直接升到 2.0 是否支援？
建議階段一**只保證新地圖可用**，舊存檔遷移列為階段二。理由是 Factorio 本身的 1.1→2.0 存檔轉換
就有很多變數（軌道系統重寫），與本 mod 的遷移交纏，驗證成本高。在 README 明確聲明。

---

# 階段 1-5：驗證（每一步都要做，不要累積）

## 載入測試（最快的迴圈）

```powershell
# 用與伺服器相同的版本，隔離環境測試載入
docker run --rm -v "D:\workspace\factorio\railloader-mod:/mod:ro" `
  --entrypoint sh factoriotools/factorio:2.0.77 -c `
  "mkdir -p /tmp/m/railloader-continued && cp -r /mod/* /tmp/m/railloader-continued/ && /opt/factorio/bin/x64/factorio --mod-directory /tmp/m --create /tmp/test.zip"
```

能生成地圖 = data 階段通過。**注意此測試無法驗證 locale**（headless 只讀 `en`），
也無法驗證 runtime 行為。

## 遊戲內驗證清單

data 階段過了之後，逐項確認（這些是上游歷史上反覆出 bug 的地方）：

- [ ] 手動放置 loader / unloader，垂直與**水平**兩個方向都要試（Keeper317 的移植版只能垂直）
- [ ] 放在無法對齊軌道的位置 → 應出現「invalid position」flying-text，而非靜默消失
- [ ] 列車進站 → 機械臂自動設定濾器，flying-text **只跳一次**（驗證 1-3-e）
- [ ] 吞吐測到位：滿載 cargo wagon 約 5 秒（驗證 `bulk = true` 生效）
- [ ] 電路：接紅/綠線讀取內容物
- [ ] 送 "Disable rail loader" 訊號 → 停止裝卸
- [ ] Interface chests：四角放箱子 → 自動生成介面機械臂並雙向搬運
- [ ] 藍圖：框選含 loader 的區域 → 貼上 → 電路連線保留、chest bar 保留
- [ ] 機器人建造：放 ghost → 機器人蓋起來 → 電路連線正確（驗證 `ghostconnections`）
- [ ] 拆除：挖掉 loader → 底下軌道一併清除、物品不遺失
- [ ] runtime 設定切換 `allowed items` 到 `any` 再切回 → 不 crash（驗證 1-3-c 的 `replace_all_inserters`）
- [ ] remote interface：`/c remote.call("railloader-continued", "add_bulk_item", "iron-plate")`

## 單元測試

`spec/EntityQueue_spec.lua` 是 busted 測試。需同步改 `global` → `storage` 的 stub。
執行方式待確認（上游無 CI 設定）。

## 與本伺服器 mod set 的相容性

伺服器現跑 LTN 堆疊（`LogisticTrainNetwork` + `LTN_Combinator_Modernized` + `LtnManager` + `flib`）。
BRL 是 circuit-connectable 的 container，LTN 靠讀取箱子內容運作，理論上相容
（上游 README 明確提到可接 LTN stop）。**需實測**，但不是階段一的阻塞項。

---

# 階段 1-6：打包與部署

`pack.sh` 依賴 `7z` 與 POSIX shell。本工作站是 Windows，且依 CLAUDE.md 不建議在 WSL 跑
（Docker 路徑問題）。需要一支 PowerShell 版打包腳本，或用 `Compress-Archive`。

打包後部署到本伺服器的注意事項（依 CLAUDE.md）：

1. **本地自建 mod 不在 portal 上**，`UPDATE_MODS_ON_START` 會跳過並記錄
   `Custom mod not on mods.factorio.com`，必須手動複製 zip 進 `_data/mods/`
2. `_data/` 由 uid **845** 擁有，寫入需透過 `--user 845` 的一次性容器，host user 無法直接建檔
3. zip 檔名必須是 `railloader-continued_<version>.zip`，與 `info.json` 的 name/version 一致
4. **`mod-list.json` 的編輯順序陷阱**：Factorio 在正常關閉時會重寫該檔並刪除無對應 zip 的項目。
   必須先 `docker compose down`，再加 zip 與 `mod-list.json` 項目，最後啟動
5. 上線前先在單機測試地圖驗證，不要直接丟上正在跑的 card-tech-draft 季

---

# 為何不從 `IlRomanenko/factorio_2.0` 起步

該分支（單一 commit `bbc846ee`，2025-10-10，15 檔 +297/−344）已完整審查。結論是**當參考、不當基底**。

**留下的 runtime crash（4 處）**：
`bulk.lua` 的 `get_contents()` 完全沒改、`configchange.lua` 整支 12 處 `global`、
`inserterconfig.lua:166-168` 的舊電線 API、`configchange.lua:293` 的 `game.entity_prototypes`。

**做一半的靜默錯誤（3 處）**：
方向算式改成 `(i % 2) * 8` 產生重複機械臂、`stack` 沒改 `bulk` 卻加了 no-op 的
`uses_inserter_stack_size_bonus`、`collision_mask` 從 `{}` 改成語意不同的 `nil`。

**功能倒退**：`show_error()` 被清空、ghost 電路連線被丟棄、`Recipe.lua` 被刪（xander 相容沒了）、
`railloader-rail` 改名導致 migration 找不到前身且 8 個 locale 檔失效。

**核心判斷**：它的「已改過」不是可信的訊號——三個 crash 就在它動過的檔案裡。
若以它為基底，仍須逐檔重審，等於沒省下工，卻多了假信心與兩個看起來像深思熟慮的有害改動。
從乾淨上游開始，把上面的 checklist 當作施工清單，總成本更低。

**唯一值得參考的**：`pictures.lua` 的 2.0 改寫方向（該處重新推導成本高）。但仍須以
本檔 1-2-a 節從 2.0.77 image 取得的權威結構為準，不可照抄。

---

# 施工順序建議

1. 1-1 重新命名 → 立刻跑載入測試（會失敗在 pictures，預期內）
2. 1-2-b/c/d/e/f/g（除 pictures 外的 data 階段）→ 再跑載入測試
3. 1-2-a pictures → **載入測試應通過**，這是第一個里程碑
4. 1-3-a/b（storage + get_contents）→ 這兩項是 runtime 最致命的
5. 1-3-c/d/e（電線、方向、濾器）→ 進遊戲跑驗證清單
6. 1-3-f/g/h + 1-4 收尾
7. 1-5 完整驗證 → 1-6 打包

每完成一個編號就 commit，訊息標明對應本檔章節，方便回溯。
