local M = {}

local function flatten(ts)
  local out = {}
  for _, t in ipairs(ts) do
    for _, elem in ipairs(t) do
      out[#out+1] = elem
    end
  end
  return out
end

-- 2.0：全域 rail_pictures() 已不存在，拆成 legacy_rail_pictures(rail_type) 與
-- new_rail_pictures(rail_type)（base/prototypes/entity/rail-pictures.lua:110,189）。
-- 沿用 legacy 直軌以維持與 1.1 一致的外觀（PORTING.md 1-2-a 問題 1，選項 A）。
local all_base_rail_pictures = legacy_rail_pictures("legacy_straight_rail")

-- 2.0：回傳值改以方向名為 key（1.1 是 straight_rail_vertical / straight_rail_horizontal）。
local rail_direction_key = {
  vertical = "north",
  horizontal = "east",
}

local function triple_rail_pictures(direction, layers)
  local out = {}
  local rail_key = rail_direction_key[direction]
  for _, layer in ipairs(layers) do
    local l = all_base_rail_pictures[rail_key][layer]
    for i=-1,1 do
      local shift = { i * 2, 0 }
      if direction == "vertical" then
        shift = { 0, i * 2 }
      end

      -- 2.0：hr_version 已移除，圖層本身就是高解析度並自帶 scale = 0.5，
      -- 直接攤平並沿用 l.scale（不要寫死）。
      out[#out+1] = {
        filename = l.filename,
        priority = l.priority,
        flags = l.flags,
        width = l.width,
        height = l.height,
        -- 2.0 的 rail 圖層用 variation_count（ties / stone_path* 各有 3 種變體），
        -- 這裡只要第一種。frame_count 是同一張表被當作 Animation 圖層時的對應欄位。
        variation_count = 1,
        frame_count = 1,
        shift = shift,
        scale = l.scale,
      }
    end
  end
  return out
end

-- 保持白名單列舉。2.0 的 legacy_rail_pictures 另有 segment_visualisation_middle，
-- 若改成迭代全部 key 會誤把它（以及 rail_endings / render_layers /
-- segment_visualisation_endings）包進來。
local all_layers = {"stone_path_background", "stone_path", "ties", "backplates", "metals"}
local rail_only_layers = {"backplates", "metals"}

-- 2.0 cargo-wagon 結構重組：
--   .wheels.filenames[N]  → .wheels.rotated（util.sprite_load，direction_count = 256）
--   .pictures.layers[1]   → .pictures.rotated.layers[1]（direction_count = 128，共 3 層）
--
-- 兩者都是多檔 spritesheet：line_length = 4、lines_per_file = 8，即每個檔 32 格。
-- 上游用 filenames[N] 挑角度的手法因此仍可用來挑「檔案」，而所需的角度剛好都是
-- 各檔的第 0 格，所以取 x = 0, y = 0 的單格即可：
--   wheels（256 格 = 360°）：0° = frame 0 = 檔 1；90° = frame 64 = 檔 3；270° = frame 192 = 檔 7
--   body（back_equals_front，128 格 = 180°）：0° = frame 0 = 檔 1；90° = frame 64 = 檔 3
-- 這與上游 1.1 選用的 filenames[1]/[3]/[7] 完全一致。
local wheels_layer = data.raw["cargo-wagon"]["cargo-wagon"].wheels.rotated
local wagon_layer = data.raw["cargo-wagon"]["cargo-wagon"].pictures.rotated.layers[1]

-- 從 util.sprite_load 產出的 spritesheet 取單一靜態格。
local function wagon_sprite(sheet, file_index, shift)
  return {
    filename = sheet.filenames[file_index],
    priority = sheet.priority,
    x = 0,
    y = 0,
    width = sheet.width,
    height = sheet.height,
    frame_count = 1,
    shift = shift,
    scale = sheet.scale,
  }
end

local cargo_wagon_layers = {
  horizontal = {
    -- left wheel
    wagon_sprite(wheels_layer, 3, {-2, -0.25}),
    -- right wheel
    wagon_sprite(wheels_layer, 7, {2, -0.25}),
    -- wagon body
    wagon_sprite(wagon_layer, 3, {wagon_layer.shift[1], wagon_layer.shift[2]}),
  },
  vertical = {
    wagon_sprite(wheels_layer, 1, {0, 2.5}),
    wagon_sprite(wagon_layer, 1, {0, 0}),
  },
}

M.railloader_structure_horizontal = {
  filename = "__railloader-continued__/graphics/railloader/structure-horizontal.png",
  priority = "extra-high",
  width = 188,
  height = 210,
  frame_count = 1,
}

M.railloader_structure_vertical = {
  filename = "__railloader-continued__/graphics/railloader/structure-vertical.png",
  priority = "extra-high",
  width = 188,
  height = 210,
  frame_count = 1,
}

local railloader_horizontal = {
  layers = flatten{
    triple_rail_pictures("horizontal", all_layers),
    cargo_wagon_layers.horizontal,
    { M.railloader_structure_horizontal },
  }
}

local railloader_vertical = {
  layers = flatten{
    triple_rail_pictures("vertical", all_layers),
    cargo_wagon_layers.vertical,
    { M.railloader_structure_vertical },
  }
}

M.railloader_proxy_animations = {
  north = railloader_vertical,
  east = railloader_horizontal,
  south = railloader_vertical,
  west = railloader_horizontal,
}

M.railunloader_horizontal = {
  layers = flatten{
    {
      {
        filename = "__railloader-continued__/graphics/railunloader/structure-horizontal.png",
        width = 384,
        height = 256,
        frame_count = 1,
        scale = 0.5,
      }
    },
    triple_rail_pictures("horizontal", rail_only_layers),
  }
}

M.railunloader_vertical = {
  layers = flatten{
    {
      {
        filename = "__railloader-continued__/graphics/railunloader/structure-vertical.png",
        width = 256,
        height = 384,
        frame_count = 1,
        scale = 0.5,
      }
    },
    triple_rail_pictures("vertical", rail_only_layers),
  }
}

local railunloader_proxy_horizontal = {
  layers = flatten{
    M.railunloader_horizontal.layers,
    cargo_wagon_layers.horizontal,
  }
}

local railunloader_proxy_vertical = {
  layers = flatten{
    M.railunloader_vertical.layers,
    cargo_wagon_layers.vertical,
  }
}

M.railunloader_proxy_animations = {
  north = railunloader_proxy_vertical,
  east = railunloader_proxy_horizontal,
  south = railunloader_proxy_vertical,
  west = railunloader_proxy_horizontal,
}

M.empty_sheet = {
  filename = "__core__/graphics/add-icon.png",
  priority = "very-low",
  width = 1,
  height = 1,
}

M.empty_animation = {
  filename = "__core__/graphics/add-icon.png",
  priority = "very-low",
  width = 1,
  height = 1,
  frame_count = 0,
}

return M
