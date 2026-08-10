--[[
  Headless regression tests for railloader-continued.

  These run inside a real Factorio 2.0 instance, so they exercise the actual
  engine behaviour of surface.create_entity (which returns nil when a position is
  occupied) rather than a mock. Run them with spec/run-integration-test.ps1 or the
  docker command documented in that script.

  Coverage focus is the crash reported against 2.0.1:

    control.lua:135: attempt to index local 'rail' (a nil value)
    create_entities -> on_railloader_proxy_built -> on_robot_built_entity

  Limitation: construction robots cannot be driven from a headless scenario, and
  on_robot_built_entity cannot be raised via script.raise_event ("can't be raised
  through script"). The robot path is therefore reproduced through
  LuaEntity::revive{raise_revive = true}, which is what a construction robot
  calls internally and which raises script_raised_revive through the same
  on_built handler. Genuinely manual/robot-driven placement still needs a human.
]]

local rl_util = require("__railloader-continued__.util")

local pass, fail = 0, 0
local failures = {}

local function report(...)
  log("RLTEST " .. table.concat({...}, " "))
end

local function check(cond, label, extra)
  if cond then
    pass = pass + 1
    report("PASS", label, extra or "")
  else
    fail = fail + 1
    failures[#failures+1] = label
    report("FAIL", label, extra or "")
  end
end

local function clean(surface, box)
  for _, e in pairs(surface.find_entities_filtered{area = box}) do
    if e.valid and e.type ~= "character" then
      e.destroy()
    end
  end
end

local function count(surface, filter)
  return #surface.find_entities_filtered(filter)
end

-- Everything create_entities() may leave behind, in one place, so a test can
-- assert "nothing was built".
local function loader_parts(surface, position)
  local box = {
    left_top     = {x = position.x - 3, y = position.y - 4},
    right_bottom = {x = position.x + 3, y = position.y + 4},
  }
  return {
    rails      = count(surface, {name = rl_util.rail_name, area = box}),
    chests     = count(surface, {type = "container", area = box}),
    inserters  = count(surface, {type = "inserter", area = box}),
    structures = count(surface, {type = "simple-entity", area = box}),
  }
end

local function parts_string(p)
  return string.format("rails=%d chests=%d inserters=%d structures=%d",
    p.rails, p.chests, p.inserters, p.structures)
end

local function place_proxy(surface, force, kind, position, direction)
  return surface.create_entity{
    name = "rail" .. kind .. "-placement-proxy",
    position = position,
    direction = direction,
    force = force,
  }
end

-- Emulates a construction robot finishing a ghost. revive() raises
-- script_raised_revive, which railloader registers on the same handler as
-- on_robot_built_entity.
local function robot_build(surface, force, inner_name, position, direction)
  local ghost = surface.create_entity{
    name = "entity-ghost",
    inner_name = inner_name,
    position = position,
    direction = direction,
    force = force,
  }
  if not ghost then return nil, "ghost could not be created" end
  local ok, err = pcall(function() ghost.revive{raise_revive = true} end)
  return ok, err
end

local tests = {}

--------------------------------------------------------------------------
-- A second (un)loader whose rail row overlaps an existing one's. The engine
-- refuses this placement interactively (can_place_entity is false, because the
-- chests would overlap), so it is only reachable through scripted placement --
-- but it used to crash outright, and it must not.
--
-- With rail adoption the shared rail is reused rather than duplicated.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{-6, -10}, {8, 14}}
  clean(surface, box)

  -- first loader at (1,1) owns rails at y = -1, 1, 3
  local first = place_proxy(surface, force, "loader", {1, 1}, defines.direction.north)
  script.raise_event(defines.events.script_raised_built, {entity = first})
  check(surface.find_entity("railloader-chest", {1, 1}) ~= nil,
    "adjacent: first loader builds")

  -- second loader 4 tiles south needs rails at y = 3, 5, 7 -> y=3 is already ours
  local ok, err = pcall(function()
    local proxy = place_proxy(surface, force, "loader", {1, 5}, defines.direction.north)
    if not proxy then
      -- engine refused the proxy outright; that is also an acceptable outcome
      return
    end
    script.raise_event(defines.events.script_raised_built, {entity = proxy})
  end)
  check(ok, "adjacent loader sharing a rail does not crash", tostring(err))

  -- the shared rail must not have been duplicated: positions -1,1,3,5,7 = 5 rails
  local rails = count(surface, {name = rl_util.rail_name, area = {{0, -2}, {2, 8}}})
  check(rails == 5, "adjacent: shared rail reused, not duplicated", "rails=" .. rails)

  -- and no placement proxy may be left stranded
  check(count(surface, {name = "railloader-placement-proxy", area = box}) == 0,
    "adjacent: no stranded placement proxy")
end

--------------------------------------------------------------------------
-- Same overlap, but through the robot/ghost revive path, which is what the
-- user's on_robot_built_entity traceback came from.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{18, -10}, {32, 14}}
  clean(surface, box)

  local first = place_proxy(surface, force, "loader", {21, 1}, defines.direction.north)
  script.raise_event(defines.events.script_raised_built, {entity = first})
  check(surface.find_entity("railloader-chest", {21, 1}) ~= nil,
    "robot: first loader builds")

  local before = loader_parts(surface, {x = 21, y = 5})
  local ok, err = robot_build(surface, force, "railloader-placement-proxy",
    {21, 5}, defines.direction.north)
  -- ok == nil means the engine refused to place the ghost, which is fine
  if ok ~= nil then
    check(ok, "robot build over shared rail does not crash", tostring(err))
  end
  local after = loader_parts(surface, {x = 21, y = 5})
  check(after.chests <= before.chests + 1,
    "robot: no duplicate chest left behind", parts_string(after))
end

--------------------------------------------------------------------------
-- A robot reviving a blueprint-captured railloader-rail must not be treated
-- as "build a whole loader here". This was the direct cause of the reported
-- traceback: blueprints capture railloader-rail, and railloader_type()
-- matched it, so create_entities tried to place a rail on top of itself.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{38, -10}, {52, 14}}
  clean(surface, box)

  local ok, err = robot_build(surface, force, rl_util.rail_name,
    {41, 1}, defines.direction.north)
  if ok ~= nil then
    check(ok, "robot building a captured railloader-rail does not crash", tostring(err))
  end
  -- exactly the one rail should exist; no chest/inserters/structure conjured up
  local p = loader_parts(surface, {x = 41, y = 1})
  check(p.chests == 0, "rail revive did not create a chest", parts_string(p))
  check(p.inserters == 0, "rail revive did not create inserters", parts_string(p))
  check(p.structures == 0, "rail revive did not create a structure", parts_string(p))
end

--------------------------------------------------------------------------
-- A loader placed onto rails the player laid themselves.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{58, -10}, {72, 14}}
  clean(surface, box)

  for _, y in ipairs{-1, 1, 3} do
    surface.create_entity{
      name = "straight-rail",
      position = {61, y},
      direction = defines.direction.north,
      force = force,
    }
  end
  local proxy = place_proxy(surface, force, "loader", {61, 1}, defines.direction.north)
  if proxy then
    local ok, err = pcall(function()
      script.raise_event(defines.events.script_raised_built, {entity = proxy})
    end)
    check(ok, "loader over player-laid rail does not crash", tostring(err))
    local p = loader_parts(surface, {x = 61, y = 1})
    -- either it built completely, or it built nothing at all
    local complete = p.chests >= 1 and p.inserters >= 2 and p.structures >= 1
    local empty = p.chests == 0 and p.inserters == 0 and p.structures == 0
    check(complete or empty,
      "loader over player rail is all-or-nothing", parts_string(p))
  else
    check(true, "loader over player-laid rail: engine refused proxy (acceptable)")
  end
end

--------------------------------------------------------------------------
-- Rollback completeness.
--
-- A rail the player laid at one of the three rail positions makes that single
-- create_entity return nil. Verified engine behaviour: our railloader-rail
-- cannot be created on top of a foreign straight-rail of the same orientation.
-- Since the blocked position is the *third* rail, the first two were already
-- created and must be cleaned up again, leaving nothing behind -- and crucially
-- leaving the player's own rail untouched.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{78, -10}, {92, 14}}
  clean(surface, box)

  -- foreign rail at the last of the three rail positions (y = 3)
  local blocker = surface.create_entity{
    name = "straight-rail",
    position = {81, 3},
    direction = defines.direction.north,
    force = force,
  }
  check(blocker ~= nil, "rollback: blocking player rail placed")

  local proxy = place_proxy(surface, force, "loader", {81, 1}, defines.direction.north)
  if proxy then
    local ok, err = pcall(function()
      script.raise_event(defines.events.script_raised_built, {entity = proxy})
    end)
    check(ok, "blocked rail position does not crash", tostring(err))

    local rails = count(surface, {name = rl_util.rail_name, area = {{80, -2}, {82, 5}}})
    local chests = count(surface, {name = "railloader-chest", area = {{79, -1}, {83, 3}}})
    local ins = count(surface, {type = "inserter", area = {{79, -1}, {83, 3}}})
    local st = count(surface, {type = "simple-entity", area = {{79, -1}, {83, 3}}})
    check(rails == 0, "rollback removed the rails it had created", "rails=" .. rails)
    check(chests == 0, "rollback left no chest", "chests=" .. chests)
    check(ins == 0, "rollback left no inserters", "inserters=" .. ins)
    check(st == 0, "rollback left no structure", "structures=" .. st)
    -- the player's own rail must survive an aborted build
    check(surface.find_entity("straight-rail", {81, 3}) ~= nil,
      "rollback did not destroy the player's own rail")
  else
    check(true, "rollback: engine refused proxy (acceptable)")
  end
end

--------------------------------------------------------------------------
-- Success path must be unchanged: full set of internals, wires, behaviour.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{98, -10}, {112, 14}}
  clean(surface, box)

  local proxy = place_proxy(surface, force, "loader", {101, 1}, defines.direction.north)
  script.raise_event(defines.events.script_raised_built, {entity = proxy})

  local chest = surface.find_entity("railloader-chest", {101, 1})
  check(chest ~= nil, "success: chest built")
  if not chest then return end

  check(count(surface, {name = rl_util.rail_name, area = {{100, -2}, {102, 4}}}) == 3,
    "success: 3 rails")
  local inserters = surface.find_entities_filtered{type = "inserter", position = chest.position}
  check(#inserters == 2, "success: 2 inserters", "n=" .. #inserters)
  if #inserters == 2 then
    check((inserters[1].direction - inserters[2].direction) % 16 == 8,
      "success: inserters 180 apart",
      inserters[1].direction .. "/" .. inserters[2].direction)
  end
  check(count(surface, {name = "railloader-structure-vertical", position = chest.position}) == 1,
    "success: vertical structure")

  local connector = chest.get_wire_connector(defines.wire_connector_id.circuit_red, false)
  check(connector ~= nil and #connector.connections == 2,
    "success: chest wired to both inserters",
    "conns=" .. tostring(connector and #connector.connections))

  local behavior = inserters[1].get_or_create_control_behavior()
  local condition = behavior.circuit_condition
  check(condition ~= nil and condition.first_signal ~= nil
    and condition.first_signal.name == "railloader-disable",
    "success: disable signal condition intact")
  check(behavior.circuit_enable_disable == true,
    "success: circuit_enable_disable set")

  -- proxy must be gone after a successful build
  check(count(surface, {name = "railloader-placement-proxy", position = {101, 1}}) == 0,
    "success: placement proxy consumed")
end

--------------------------------------------------------------------------
-- Horizontal build still works (regression guard for direction handling).
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{118, -10}, {132, 14}}
  clean(surface, box)

  local proxy = place_proxy(surface, force, "unloader", {121, 1}, defines.direction.east)
  script.raise_event(defines.events.script_raised_built, {entity = proxy})
  local chest = surface.find_entity("railunloader-chest", {121, 1})
  check(chest ~= nil, "horizontal: unloader chest built")
  if chest then
    check(count(surface, {name = "railunloader-structure-horizontal", position = chest.position}) == 1,
      "horizontal: horizontal structure chosen")
    check(rl_util.loader_direction(chest) == defines.direction.east,
      "horizontal: loader_direction reads east")
  end
end

--------------------------------------------------------------------------
-- Rail adoption: a robot builds the blueprint-captured rails first, then the
-- loader itself. The loader must still complete and reuse those rails.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{138, -10}, {152, 14}}
  clean(surface, box)

  for _, y in ipairs{-1, 1, 3} do
    surface.create_entity{
      name = rl_util.rail_name,
      position = {141, y},
      direction = defines.direction.north,
      force = force,
    }
  end
  check(count(surface, {name = rl_util.rail_name, area = {{140, -2}, {142, 4}}}) == 3,
    "adoption: rails pre-built by robot")

  local proxy = place_proxy(surface, force, "loader", {141, 1}, defines.direction.north)
  if proxy then
    local ok, err = pcall(function()
      script.raise_event(defines.events.script_raised_built, {entity = proxy})
    end)
    check(ok, "adoption: build over own pre-built rails does not crash", tostring(err))
    local chest = surface.find_entity("railloader-chest", {141, 1})
    check(chest ~= nil, "adoption: loader completed by reusing existing rails")
    check(count(surface, {name = rl_util.rail_name, area = {{140, -2}, {142, 4}}}) == 3,
      "adoption: still exactly 3 rails (no duplicates)")
  else
    check(true, "adoption: engine refused proxy (acceptable)")
  end
end

--------------------------------------------------------------------------
-- Mining an internal entity must not tear down the whole loader.
--------------------------------------------------------------------------
tests[#tests+1] = function(surface, force)
  local box = {{158, -10}, {172, 14}}
  clean(surface, box)

  local proxy = place_proxy(surface, force, "loader", {161, 1}, defines.direction.north)
  script.raise_event(defines.events.script_raised_built, {entity = proxy})
  local chest = surface.find_entity("railloader-chest", {161, 1})
  check(chest ~= nil, "mine-guard: loader built")
  if not chest then return end

  -- simulate something raising a mined event for one internal rail
  local rail = surface.find_entity(rl_util.rail_name, {161, 1})
  if rail then
    local ok = pcall(function()
      script.raise_event(defines.events.script_raised_destroy, {entity = rail})
    end)
    check(ok, "mine-guard: destroying one rail does not error")
  end
  check(surface.find_entity("railloader-chest", {161, 1}) ~= nil,
    "mine-guard: chest survives an internal rail event")
end

script.on_init(function()
  local surface = game.surfaces[1]
  local force = game.forces.player
  surface.request_to_generate_chunks({80, 0}, 12)
  surface.force_generate_chunk_requests()

  local power = surface.create_entity{
    name = "electric-energy-interface",
    position = {-40, -40},
    force = force,
  }
  if power then
    power.power_production = 10000000
    power.electric_buffer_size = 100000000
    power.energy = 100000000
  end

  for _, test in ipairs(tests) do
    local ok, err = pcall(test, surface, force)
    if not ok then
      fail = fail + 1
      failures[#failures+1] = "test body errored: " .. tostring(err)
      report("FAIL test body errored:", tostring(err))
    end
  end

  report("RESULT pass=" .. pass .. " fail=" .. fail)
  if fail > 0 then
    report("FAILED TESTS: " .. table.concat(failures, " | "))
    error("RLTEST_FAILED fail=" .. fail)
  end
  report("ALL TESTS PASSED")
  -- Deliberately abort so the harness never has to write a save file.
  error("RLTEST_COMPLETE")
end)
