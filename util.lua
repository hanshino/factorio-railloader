local M = {}

-- Circuit wire helpers
--
-- 2.0 removed LuaEntity::connect_neighbour, circuit_connection_definitions and
-- defines.circuit_connector_id. Wires are now manipulated through LuaWireConnector
-- obtained from LuaEntity::get_wire_connector(wire_connector_id, create_if_missing).

local circuit_wire_connector_ids = {
  defines.wire_connector_id.circuit_red,
  defines.wire_connector_id.circuit_green,
}

M.circuit_wire_connector_ids = circuit_wire_connector_ids

-- Connects `entity` to `target` with both the red and the green circuit wire.
function M.connect_circuit_wires(entity, target)
  for _, connector_id in ipairs(circuit_wire_connector_ids) do
    entity.get_wire_connector(connector_id, true)
      .connect_to(target.get_wire_connector(connector_id, true))
  end
end

-- Returns an array of {connector_id = ..., target = LuaWireConnector} describing
-- every circuit wire currently attached to `entity`. This is the 2.0 replacement
-- for reading LuaEntity::circuit_connection_definitions.
function M.get_circuit_connections(entity)
  local out = {}
  for _, connector_id in ipairs(circuit_wire_connector_ids) do
    local connector = entity.get_wire_connector(connector_id, false)
    if connector then
      for _, connection in pairs(connector.connections) do
        out[#out+1] = {
          connector_id = connector_id,
          target = connection.target,
        }
      end
    end
  end
  return out
end

-- Applies connections previously returned by M.get_circuit_connections (or by
-- ghostconnections.get_connections) to `entity`.
function M.apply_circuit_connections(entity, connections)
  for _, connection in ipairs(connections) do
    entity.get_wire_connector(connection.connector_id, true)
      .connect_to(connection.target)
  end
end

-- Replicates every circuit wire attached to `from` onto `to`.
function M.copy_circuit_connections(from, to)
  M.apply_circuit_connections(to, M.get_circuit_connections(from))
end

-- 2.0 removed the "flying-text" entity type; LuaPlayer::create_local_flying_text
-- is the replacement. The 1.1 flying-text entity was visible to every player on
-- the surface, so show it to each of them to keep the same behaviour.
function M.flying_text(surface, position, text)
  for _, player in pairs(game.players) do
    if player.valid and player.surface == surface then
      player.create_local_flying_text{
        text = text,
        position = position,
      }
    end
  end
end

-- Position adjustments

function M.moveposition(position, offset)
  return {x=position.x + offset.x, y=position.y + offset.y}
end

function M.offset(direction, longitudinal, orthogonal)
  if direction == defines.direction.north then
    return {x=orthogonal, y=-longitudinal}
  end

  if direction == defines.direction.south then
    return {x=-orthogonal, y=longitudinal}
  end

  if direction == defines.direction.east then
    return {x=longitudinal, y=orthogonal}
  end

  if direction == defines.direction.west then
    return {x=-longitudinal, y=-orthogonal}
  end
end

function M.box_centered_at(position, radius)
  return {
    left_top = M.moveposition(position, M.offset(defines.direction.north, radius, -radius)),
    right_bottom = M.moveposition(position, M.offset(defines.direction.south, radius, -radius)),
  }
end

function M.expand_box(box, delta)
  return {
    left_top = { x = box.left_top.x - delta, y = box.left_top.y - delta },
    right_bottom = { x = box.right_bottom.x + delta, y = box.right_bottom.y + delta },
  }
end

function M.is_empty_box(box)
  local size_x = box.right_bottom.x - box.left_top.x
  local size_y = box.right_bottom.y - box.left_top.y
  return size_x < 0.01 and size_y < 0.01
end

-- 2.0 has 16 directions instead of 8, so a 180 degree turn is +8 instead of +4
function M.opposite_direction(direction)
  return (direction + 8) % 16
end

function M.position_key(entity)
  return entity.surface.name .. "@" .. entity.position.x .. "," .. entity.position.y
end

function M.railloader_inserters(entity, pattern)
  local out = {}
  local inserters = entity.surface.find_entities_filtered{
    type = "inserter",
    position = entity.position,
    force = entity.force,
  }
  if not pattern then
    return inserters
  end
  for _, e in ipairs(inserters) do
    if string.find(e.name, pattern) ~= nil then
      out[#out+1] = e
    end
  end
  return out
end

function M.railloader_filter_inserters(entity)
  return M.railloader_inserters(entity, "^railu?n?loader%-inserter$")
end

function M.railloader_universal_inserters(entity)
  return M.railloader_inserters(entity, "^railu?n?loader%-universal%-inserter$")
end

function M.railloader_cargo_wagon_inserters(entity)
  local filter_inserters = M.railloader_filter_inserters(entity)
  if next(filter_inserters) then
    return filter_inserters
  end
  return M.railloader_universal_inserters(entity)
end

function M.railloader_interface_inserters(entity)
  return M.railloader_inserters(entity, "^railu?n?loader%-interface%-inserter$")
end

function M.is_railloader_chest(entity)
  return string.find(entity.name, "^railu?n?loader%-chest$") ~= nil
end

function M.is_filter_inserter(inserter)
  return string.find(inserter.name, "loader%-inserter$") ~= nil
end

function M.find_railloaders_from_chest(chest)
  local out = {}
  local area = M.expand_box(chest.bounding_box, 1)
  local es = chest.surface.find_entities_filtered{
    type = "container",
    area = area,
    force = chest.force,
  }
  for _, e in ipairs(es) do
    if M.is_railloader_chest(e) then
      out[#out+1] = e
    end
  end
  return out
end

function M.railloader_type(name)
  return string.match(name, "^rail(u?n?loader)%-")
end

-- the mod's own rail prototype, placed underneath every (un)loader.
-- 2.0 renamed the 1.1 rail prototypes to legacy-straight-rail and introduced a new
-- straight-rail, so filtering by type alone also matches rails the player laid.
-- Always filter by name when looking for our own rail.
M.rail_name = "railloader-rail"

function M.is_railloader_rail(entity)
  return entity.name == M.rail_name
end

function M.loader_direction(loader)
  local rail = loader.surface.find_entities_filtered{
    name = M.rail_name,
    area = M.box_centered_at(loader.position, 0.6),
  }[1]
  if rail and rail.valid then
    return rail.direction
  end
end

function M.interface_inserter_name_for_loader(loader)
  return "rail" .. M.railloader_type(loader.name) .. "-interface-inserter"
end

function M.find_inserter_for_interface(loader, interface)
  local type = M.railloader_type(loader.name)
  local interface_position = interface.position
  local inserters = loader.surface.find_entities_filtered{
    name = M.interface_inserter_name_for_loader(loader),
    position = loader.position,
  }
  for _, inserter in ipairs(inserters) do
    local target_interface_position = inserter[type == "loader" and "pickup_position" or "drop_position"]
    if target_interface_position.x == interface_position.x and
      target_interface_position.y == interface_position.y then
      return inserter
    end
  end
  return nil
end

function M.loader_position_for_interface(loader, interface)
  local offset = { x = 1.5, y = 1.5 }
  for _, axis in ipairs{"x", "y"} do
    if interface.position[axis] < loader.position[axis] then
      offset[axis] = offset[axis] * -1
    end
  end
  return { x = loader.position.x + offset.x, y = loader.position.y + offset.y }
end

function M.find_chests_from_railloader(loader)
  local position = loader.position
  local is_horiz = M.loader_direction(loader) == defines.direction.east
  local area = {
    left_top = {
      x = position.x - (is_horiz and 2.5 or 1.5),
      y = position.y - (is_horiz and 1.5 or 2.5),
    },
    right_bottom = {
      x = position.x + (is_horiz and 2.5 or 1.5),
      y = position.y + (is_horiz and 1.5 or 2.5),
    },
  }
  local entities = loader.surface.find_entities_filtered{
    area = area,
    force = loader.force,
  }
  local out = {}
  for _, e in ipairs(entities) do
    if string.find(e.type, "container$") and not M.is_railloader_chest(e) then
      out[#out+1] = e
    end
  end
  return out
end

function M.insert_or_spill(entity, stack, inventories)
  if not stack or not stack.valid_for_read then
    return
  end

  if stack.prototype.stackable then
    for _, inv in ipairs(inventories) do
      local inserted = inv.insert(stack)
      stack.count = stack.count - inserted
      if not stack.valid_for_read then
        return
      end
    end
  else
    for _, inv in ipairs(inventories) do
      for slot=1,#inv do
        if not inv[slot].valid_for_read then
          inv[slot].swap_stack(stack)
          return
        end
      end
    end
  end

  -- 2.0 changed spill_item_stack to take a single table of parameters
  entity.surface.spill_item_stack{
    position = entity.position,
    stack = stack,
  }
  stack.clear()
end

return M