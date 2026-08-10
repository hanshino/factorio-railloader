local Recipe = require "prototypes.recipe.Recipe"

local possible_ingredients = {
  -- xander-mod
  {
    {"rail", 3},
    {"mechanism-1", 2},
    {"forging-steel", 20},
    {"electronic-circuit", 2},
  },
  -- base
  {
    {"rail", 3},
    {"iron-gear-wheel", 8},
    {"iron-plate", 40},
    {"electronic-circuit", 2},
  },
}

data:extend{
  {
    type = "recipe",
    name = "railloader",
    enabled = false,
    energy_required = 1,
    ingredients = (function()
      local selected = {}
      for _, ingredient in ipairs(Recipe.select_ingredients(possible_ingredients)) do
        selected[#selected + 1] = {type = "item", name = ingredient[1], amount = ingredient[2]}
      end
      return selected
    end)(),
    results = {{type = "item", name = "railloader", amount = 1}},
  },
}
