local util = require "util"

local M = {}

-- Finds circuit connections that nearby ghosts have made to `entity`, and returns
-- them in the form expected by util.apply_circuit_connections.
--
-- This exists because the placement proxy is destroyed and replaced by a chest:
-- wires that ghosts point at the proxy would otherwise be lost when it goes away.
--
-- 2.0 notes: LuaEntity::circuit_connection_definitions was removed. Wires are read
-- through LuaWireConnector, whose connections list holds the *target* connector,
-- so the ghost side is reached via connection.target.owner.
function M.get_connections(entity)
  local position = entity.position
  -- 2.0 replaced LuaEntityPrototype::max_circuit_wire_distance (read) with the
  -- get_max_circuit_wire_distance() method
  local distance = entity.prototype.get_max_circuit_wire_distance()
  local area = {
    left_top = { x = position.x - distance, y = position.y - distance },
    right_bottom = { x = position.x + distance, y = position.y + distance }
  }
  local ghosts = entity.surface.find_entities_filtered{
    type = "entity-ghost",
    area = area,
  }

  local out = {}
  for _, ghost in pairs(ghosts) do
    for _, connector_id in ipairs(util.circuit_wire_connector_ids) do
      local ghost_connector = ghost.get_wire_connector(connector_id, false)
      if ghost_connector then
        for _, connection in pairs(ghost_connector.connections) do
          if connection.target.owner == entity then
            -- reconnect our replacement entity to the ghost's connector,
            -- on the same wire the ghost used
            out[#out+1] = {
              connector_id = connection.target.wire_connector_id,
              target = ghost_connector,
            }
          end
        end
      end
    end
  end

  return out
end

return M
