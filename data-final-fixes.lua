local json = require("json")

local storage = {
    icons = {},
    main_products = {}
}

for _, protos in pairs(data.raw) do
    for _, proto in pairs(protos) do
        storage.icons[proto.type] = storage.icons[proto.type] or {}
        storage.icons[proto.type][proto.name] = {
            icon = proto.icon,
            icon_size = proto.icon_size,
            icon_mipmaps = proto.icon_mipmaps,
            icons = proto.icons
        }
    end
end

for _, recipe in pairs(data.raw['recipe']) do
    if recipe.main_product ~= nil then
        storage.main_products[recipe.name] = recipe.main_product
    elseif recipe.normal ~= nil and recipe.normal.main_product ~= nil then
        storage.main_products[recipe.name] = recipe.normal.main_product
    elseif recipe.expensive ~= nil and recipe.expensive.main_product ~= nil then
        storage.main_products[recipe.name] = recipe.expensive.main_product
    end
end

local encoded = json.encode(storage)
local startpos = 0
local entitynum = 1
local transport_entities = {}
while ( startpos <= #encoded )
do
    local section = string.sub(encoded, startpos + 1, startpos + 200)

    table.insert(transport_entities, {
      flags = {"hidden"},
      icon_size = 32,
      icon = "__base__/graphics/icons/accumulator.png",
      name = "data-dumper-transporter-" .. entitynum,
      order = "z",
      stack_size = 50,
      subgroup = "energy",
      type = "item",
      localised_name = { section }
    })

    startpos = startpos + 200
    entitynum = entitynum + 1
end

data:extend(transport_entities)
