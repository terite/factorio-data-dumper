local storage = {}
local json = require("json")

for _, protos in pairs(data.raw) do
    for _, proto in pairs(protos) do
        storage[proto.type] = storage[proto.type] or {}
        storage[proto.type][proto.name] = {
            icon = proto.icon,
            icon_size = proto.icon_size,
            icons = proto.icons
        }
    end
end

data:extend({
    {
      flags = {"hidden"},
      icon_size = 32,
      icon = "__base__/graphics/icons/accumulator.png",
      name = "data-dumper-transporter",
      order = "z",
      stack_size = 50,
      subgroup = "energy",
      type = "item",
      localised_name = { json.encode(storage) }
    }
})