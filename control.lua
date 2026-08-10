local bulk = require "bulk"
local configchange = require "configchange"
local delaydestroy = require "delaydestroy"
local ghostconnections = require "ghostconnections"
local inserter_config = require "inserterconfig"
local util = require "util"

-- constants

local num_inserters = 2

local allowed_items_setting = settings.global["railloader-allowed-items"].value

local function on_init()
  storage.previous_opened_blueprint_for = {}
  delaydestroy.on_init()
  inserter_config.on_init()
end

local function on_load()
  delaydestroy.on_load()
  inserter_config.on_load()
end

local function on_configuration_changed(configuration_changed_data)
  local mod_change = configuration_changed_data.mod_changes["railloader-continued"]
  if mod_change and mod_change.old_version and mod_change.old_version ~= mod_change.new_version then
    configchange.on_mod_version_changed(mod_change.old_version)
  end
end

local function show_error(entity)
  util.flying_text(entity.surface, entity.position, {"railloader.invalid-position"})
end

local function abort_build(event)
  local entity = event.entity
  show_error(entity)
  if event.player_index then
    local player = game.players[event.player_index]
    player.mine_entity(entity, true)
  else
    entity.order_deconstruction(entity.force)
  end
end

local function sync_interface_inserters(loader)
  local type = util.railloader_type(loader.name)
  local interface_chests = util.find_chests_from_railloader(loader)
  for _, interface_chest in ipairs(interface_chests) do
    local inserter = util.find_inserter_for_interface(loader, interface_chest)
    if not inserter then
      local main_chest_position = util.loader_position_for_interface(loader, interface_chest)
      inserter = loader.surface.create_entity{
        name = util.interface_inserter_name_for_loader(loader),
        position = loader.position,
        force = loader.force,
      }
      -- interface inserters are a convenience: if one cannot be placed, skip this
      -- chest rather than erroring out and aborting the whole (un)loader
      if inserter then
        inserter.destructible = false
        inserter.pickup_position = type == "loader" and interface_chest.position or main_chest_position
        inserter.drop_position = type == "unloader" and interface_chest.position or main_chest_position
        inserter.direction = inserter.direction
        inserter_config.connect_and_configure_inserter_control_behavior(inserter, loader)
      end
    end
  end
end

local function remove_interface_inserter(loader, chest, buffer)
  local inserter = util.find_inserter_for_interface(loader, chest)
  if inserter then
    util.insert_or_spill(loader, inserter.held_stack, {loader.get_inventory(defines.inventory.chest), buffer})
    inserter.destroy()
  end
end

local function rail_positions(proxy)
  local direction = proxy.direction
  local position = proxy.position

  if direction == defines.direction.north or direction == defines.direction.south then
    if position.x % 2 ~= 1 then
      return nil
    end
    if position.y % 2 == 1 then
      return {
        util.moveposition(position, {x = 0, y = -2}),
        position,
        util.moveposition(position, {x = 0, y =  2}),
      }
    else
      return {
        util.moveposition(position, {x = 0, y = -1}),
        util.moveposition(position, {x = 0, y =  1}),
      }
    end
  else
    if position.y % 2 ~= 1 then
      return nil
    end
    if position.x % 2 == 1 then
      return {
        util.moveposition(position, {x = -2, y = 0}),
        position,
        util.moveposition(position, {x =  2, y = 0}),
      }
    else
      return {
        util.moveposition(position, {x = -1, y = 0}),
        util.moveposition(position, {x =  1, y = 0}),
      }
    end
  end
end

-- Builds every internal entity of a (un)loader, or nothing at all.
--
-- surface.create_entity returns nil when something already occupies the target
-- position -- most importantly another railloader-rail belonging to a neighbouring
-- (un)loader, or a rail the player laid themselves. Every created entity is
-- therefore recorded so a later failure can be rolled back completely: a partially
-- built (un)loader (rails but no chest, or a chest with no inserters) is not
-- recoverable by the player and corrupts later mining/blueprint logic.
--
-- Returns true on success, or false if nothing was left behind.
local function create_entities(proxy, tags, rail_poss)
  local type = util.railloader_type(proxy.name)
  local surface = proxy.surface
  local direction = proxy.direction
  -- normalize to north/east; 2.0 doubled every direction value (south 4 -> 8, west 6 -> 12)
  if direction >= defines.direction.south then
    direction = direction - defines.direction.south
  end
  local position = proxy.position
  local force = proxy.force
  local last_user = proxy.last_user

  -- Snapshot everything we need off the proxy *before* creating anything, because
  -- rollback may destroy entities and the proxy itself must stay untouched until
  -- we know the build succeeded.
  local proxy_connections = util.get_circuit_connections(proxy)
  local ghost_connections = ghostconnections.get_connections(proxy)

  local created = {}
  local function create(spec)
    local entity = surface.create_entity(spec)
    if entity then
      created[#created+1] = entity
    end
    return entity
  end
  local function rollback()
    -- destroy in reverse creation order
    for i = #created, 1, -1 do
      local entity = created[i]
      if entity.valid then
        entity.destroy()
      end
    end
  end

  -- place rails
  for _, rail_position in ipairs(rail_poss) do
    -- A blueprint of a built (un)loader captures the hidden railloader-rail, so a
    -- robot may already have built one of our own rails here before reviving the
    -- proxy/chest ghost. Such a rail is indistinguishable from one we would place,
    -- so adopt it instead of failing the whole build. It is deliberately not added
    -- to `created`: it existed before us, so a rollback must leave it alone.
    local rail = surface.find_entity(util.rail_name, rail_position)
    if rail and rail.direction ~= direction then
      -- wrong orientation: not usable for this (un)loader
      rail = nil
    end
    if not rail then
      rail = create{
        name = util.rail_name,
        position = rail_position,
        direction = direction,
        force = force,
      }
    end
    if not rail then
      rollback()
      return false
    end
    rail.destructible = false
    rail.minable = false
  end

  -- place chest
  local chest = create{
    name = "rail" .. type .. "-chest",
    position = position,
    force = force,
  }
  if not chest then
    rollback()
    return false
  end
  chest.last_user = last_user
  if tags and tags.bar then
    chest.get_inventory(defines.inventory.chest).set_bar(tags.bar)
  end

  -- recreate circuit connections
  util.apply_circuit_connections(chest, proxy_connections)
  util.apply_circuit_connections(chest, ghost_connections)

  -- place cargo wagon inserters
  local inserter_name =
    "rail" .. type .. (allowed_items_setting == "any" and "-universal" or "") .. "-inserter"
  for i=1,num_inserters do
    -- alternate direction to support half-size wagons sticking out both sides of the (un)loader
    -- 2.0 has 16 directions, so a 180 degree turn is +8 instead of +4
    local inserter_direction = (direction + (i-1) * 8) % 16
    local inserter = create{
      name = inserter_name,
      position = position,
      direction = inserter_direction,
      force = force,
    }
    if not inserter then
      rollback()
      return false
    end
    inserter.destructible = false
    inserter_config.connect_and_configure_inserter_control_behavior(inserter, chest)
  end

  -- place structure
  local structure_name = "rail" .. type .. "-structure-vertical"
  if direction == defines.direction.east or direction == defines.direction.west then
    structure_name = "rail" .. type .. "-structure-horizontal"
  end
  local placed = create{
    name = structure_name,
    position = position,
    force = force,
  }
  if not placed then
    rollback()
    return false
  end
  placed.destructible = false

  -- From here on the (un)loader is complete; only bookkeeping is left. Registering
  -- the loader is deferred until after the structure so a rollback never leaves a
  -- destroyed chest sitting in the work queue.
  inserter_config.configure_or_register_loader(chest)

  -- place interface inserters for pre-existing chests
  sync_interface_inserters(chest)

  return true
end

local function on_railloader_proxy_built(event)
  local proxy = event.entity
  local tags = event.tags
  local rail_pos = rail_positions(proxy)
  if not rail_pos then
    return abort_build(event)
  end
  if not create_entities(proxy, tags, rail_pos) then
    -- Something (usually a rail belonging to an adjacent (un)loader, or one the
    -- player laid) blocks a position we need. Nothing was built; refund the proxy
    -- through the normal path instead of leaving a half-built (un)loader.
    return abort_build(event)
  end
  proxy.destroy()
end

local function on_ghost_built(ghost)
  local rail_pos = rail_positions(ghost)
  if not rail_pos then
    show_error(ghost)
    ghost.destroy()
  end
end

local function on_container_built(entity)
  for _, loader in ipairs(util.find_railloaders_from_chest(entity)) do
    sync_interface_inserters(loader)
  end
end

local function on_built(event)
  local entity = event.entity
  local type = util.railloader_build_type(entity.name)
  if type then
    return on_railloader_proxy_built(event)
  elseif entity.type == "entity-ghost" then
    type = util.railloader_build_type(entity.ghost_name)
    if type then
      return on_ghost_built(entity)
    end
  elseif string.find(entity.type, "container$") then
    return on_container_built(entity)
  end
end

local function on_railloader_mined(entity, buffer)
  local entities = entity.surface.find_entities_filtered{
    area = entity.bounding_box,
  }
  for _, ent in ipairs(entities) do
    if ent.type == "inserter" then
      if buffer and ent.held_stack.valid_for_read then
        buffer.insert(ent.held_stack)
      end
      ent.destroy()
    elseif string.find(ent.name, "^railu?n?loader%-structure") then
      ent.destroy()
    elseif util.is_railloader_rail(ent) then
      local success = ent.destroy()
      if not success then
        delaydestroy.register_to_destroy(ent)
      end
    end
  end
end

local function on_container_mined(entity, buffer)
  for _, loader in ipairs(util.find_railloaders_from_chest(entity)) do
    remove_interface_inserter(loader, entity, buffer)
  end
end

local died_direction

local function on_post_entity_died(event)
  local ghost = event.ghost
  if ghost then
    local loader_type = util.railloader_build_type(ghost.ghost_name)
    if loader_type then
      local new_ghost = ghost.surface.create_entity{
        name = "entity-ghost",
        inner_name = "rail" .. loader_type .. "-placement-proxy",
        force = ghost.force,
        direction = died_direction,
        position = ghost.position,
      }
      -- only replace the chest ghost once the proxy ghost actually exists,
      -- otherwise the player silently loses the ghost entirely
      if new_ghost then
        new_ghost.last_user = ghost.last_user
        ghost.destroy()
      end
    end
  end
end

local function on_mined(event)
  local entity = event.entity
  -- only the chest (or a not-yet-converted proxy) represents a whole (un)loader;
  -- matching the "rail(un)loader-" prefix loosely here would make a single mined
  -- internal entity tear down everything in its bounding box
  local type = util.railloader_build_type(entity.name)
  if type then
    died_direction = util.loader_direction(entity)
    return on_railloader_mined(entity, event.buffer)
  elseif string.find(entity.type, "container$") then
    return on_container_mined(entity, event.buffer)
  end
end

local function on_robot_pre_mined(event)
  if event.instant_deconstruction then
    on_mined(event)
  end
end

local function on_gui_closed(event)
  if event.gui_type == defines.gui_type.item
  and event.item
  and event.item.is_blueprint
  and event.item.is_blueprint_setup()
  then
    storage.previous_opened_blueprint_for[event.player_index] = {
      blueprint = event.item,
      tick = event.tick,
    }
  end
end

local function get_blueprint_to_setup(player_index)
  local opened_blueprint = storage.previous_opened_blueprint_for[player_index]
  if opened_blueprint and opened_blueprint.tick == game.tick then
    return opened_blueprint.blueprint
  end

  local player = game.players[player_index]

  local blueprint_to_setup = player.blueprint_to_setup
  if blueprint_to_setup
  and blueprint_to_setup.valid_for_read then
    return blueprint_to_setup
  end

  local cursor_stack = player.cursor_stack
  if cursor_stack
  and cursor_stack.valid_for_read
  and cursor_stack.is_blueprint
  and cursor_stack.is_blueprint_setup() then
    return cursor_stack
  end
end

local function on_blueprint(event)
  local bp = get_blueprint_to_setup(event.player_index)
  if not bp then return end
  local player = game.players[event.player_index]
  local entities = bp.get_blueprint_entities()
  if not entities then return end

  for _, bp_entity in pairs(entities) do
    if bp_entity.name == "railloader-chest" or bp_entity.name == "railunloader-chest" then
      local chest_entity = player.surface.find_entities_filtered{
        type = "container",
        position = bp_entity.position,
      }[1]
      if not chest_entity then goto continue end

      local rail = player.surface.find_entities_filtered{
        name = util.rail_name,
        area = chest_entity.bounding_box,
      }[1]
      if not rail then goto continue end

      bp_entity.name = (bp_entity.name == "railloader-chest")
        and "railloader-placement-proxy"
        or "railunloader-placement-proxy"
      -- base direction on direction of rail
      bp_entity.direction = rail.direction
      -- preserve chest limit
      bp_entity.tags = { bar = chest_entity.get_inventory(defines.inventory.chest).get_bar() }
    end
    ::continue::
  end

  bp.set_blueprint_entities(entities)
end

local function on_setting_changed(event)
  allowed_items_setting = settings.global["railloader-allowed-items"].value
  inserter_config.on_setting_changed(event)
end

-- setup remotes

remote.add_interface("railloader-continued", {
  add_bulk_item = bulk.add_bulk_item,
  add_bulk_item_pattern = bulk.add_bulk_item_pattern,
})

-- setup event handlers

script.on_init(on_init)
script.on_load(on_load)
script.on_configuration_changed(on_configuration_changed)

local es = defines.events
script.on_event({es.on_built_entity, es.on_robot_built_entity, es.script_raised_built, es.script_raised_revive}, on_built)
script.on_event({es.on_player_mined_entity, es.on_robot_mined_entity, es.script_raised_destroy}, on_mined)
script.on_event(es.on_robot_pre_mined, on_robot_pre_mined)
script.on_event(es.on_entity_died, on_mined)
script.on_event(es.on_post_entity_died, on_post_entity_died, {{filter = "type", type = "container"}})

script.on_event(es.on_gui_closed, on_gui_closed)
script.on_event(es.on_player_setup_blueprint, on_blueprint)

script.on_event(es.on_train_changed_state, inserter_config.on_train_changed_state)

script.on_event(defines.events.on_runtime_mod_setting_changed, on_setting_changed)
