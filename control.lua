local json = require("json")

-- for table.deepcopy
require("util")

-- items that are not part of a recipe but should be copied anyway
local special_items = {
    "space-science-pack",
}

local function round2(num, numDecimalPlaces)
  return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local function pairsByKeys (t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0
  local iter = function ()
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end

local function get_allowed(tbl)
    if tbl == nil then
        return nil
    end
    local keys = {}
    for key, allowed in pairs(tbl) do
        if allowed then table.insert(keys, key) end
    end
    if #keys > 0 then
        return keys
    else
        return nil 
    end
end

local function format_magnitude(amount, suffixes)
    for i, suffix in ipairs(suffixes) do
        if (amount >= 1000) and (i ~= #suffixes) then
            amount = amount / 1000
        else
            return tostring(amount) .. suffix
        end
    end
end

local function format_watts(watts)
    return format_magnitude(watts, {"W", "kW", "MW", "GW", "TW", "PW"})
end

local function format_joules(joules)
    return format_magnitude(joules, {"J", "kJ", "MJ", "GJ", "TJ", "PJ"})
end

local function get_energy_source(entity)
    local burner = entity.burner_prototype
    if burner ~= nil then
        -- we only support 1 fuel category for now
        local fuel_categories = get_allowed(burner.fuel_categories)
        assert(#fuel_categories == 1)
        return {
            fuel_category = fuel_categories[1],
            type = "burner"
        }
    end
    
    return nil
end

local function load_icons(data, paths)
    for _, path in ipairs(paths) do
        local itype = path[1]
        local iname = path[2]
        
        if data._icons[itype] == nil then
            error("No icons at all for type " .. itype)
        end
        
        icons = data._icons[itype][iname]
        if icons ~= nil then
            return icons
        end
    end
    
    error("no icon for " .. serpent.block(paths))

end

local function get_used_items()
    used_items = {}
    used_fluids = {}

    local function add_ingredients(list)
        for _, entry in pairs(list) do
            if entry.type == 'fluid' then
                used_fluids[entry.name] = true
            else
                used_items[entry.name] = true
            end
        end
    end

    local function add_prototypes(list)
        for _, proto in pairs(list) do
            used_items[proto.name] = true
        end
    end

    for _, recipe in pairs(game.recipe_prototypes) do
        add_ingredients(recipe.ingredients)
        add_ingredients(recipe.products)
    end

    for _, item in pairs(game.item_prototypes) do
        if item.burnt_result then
            used_items[item.burnt_result.name] = true
        end
        add_ingredients(item.rocket_launch_products)
    end

    for _, tech in pairs(game.technology_prototypes) do
        add_ingredients(tech.research_unit_ingredients)
    end

    for key, _ in pairs(used_items) do
        used_items[key] = game.item_prototypes[key]
    end
    for key, _ in pairs(used_fluids) do
        used_fluids[key] = game.fluid_prototypes[key]
    end

    return used_items, used_fluids
end

local function process_entities(data)
    local entity_map = {
        ["assembling-machine"] = {},
        ["furnace"] = {},
        ["mining-drill"] = {},
        ["offshore-pump"]= {},
        ["reactor"] = {},
        ["resource"] = {},
        ["rocket-silo"] = {},
        
    }
    for _, entity in pairs(game.entity_prototypes) do
        if entity_map[entity.type] ~= nil then
            local icon_data = load_icons(data, {{entity.type, entity.name}})
            edata = {
                name = entity.name,
                icon = icon_data.icon,
                icon_size = icon_data.icon_size,
                icons = icon_data.icons
            }
            
            if entity.type == "resource" then
                edata.category = entity.resource_category
                local resdata = entity.mineable_properties
                edata.minable = {}
                edata.minable.hardness = resdata.hardness
                edata.minable.mining_time = resdata.mining_time
                edata.minable.mining_particle = resdata.mining_particle
                edata.minable.results = table.deepcopy(resdata.products)
                
                if resdata.required_fluid ~= nil then
                    edata.minable.required_fluid = resdata.required_fluid
                    edata.minable.fluid_amount = resdata.fluid_amount
                end
                
                for _, result in pairs(edata.minable.results) do
                    if result.type == "item" then
                        result.type = nil
                    end
                end
            end
            
            if entity.type == "mining-drill" then
                edata.mining_power = entity.mining_power
                edata.mining_speed = entity.mining_speed
                edata.resource_categories = get_allowed(entity.resource_categories)
            end
            
            if entity.type == "offshore-pump" then
                edata.fluid = entity.fluid.name
                edata.mining_speed = entity.mining_speed
            end
            
            if entity.energy_usage ~= nil then
                edata.energy_usage = entity.energy_usage * 60
            end
            
            if entity.crafting_categories ~= nil then
                local crafting_categories = {}
                for category, allowed in pairs(entity.crafting_categories) do
                    if allowed then table.insert(crafting_categories, category) end
                end
                if #crafting_categories > 0 then
                    edata.crafting_categories = crafting_categories
                end
            end
            
            if entity.crafting_speed ~= nil then
                edata.crafting_speed = entity.crafting_speed
            end
            
            if entity.module_inventory_size ~= nil then
                edata.module_slots = entity.module_inventory_size
            end
            
            if entity.ingredient_count ~= nil then
                edata.ingredient_count = entity.ingredient_count
            end
            
            if entity.allowed_effects ~= nil then
                local allowed_effects = {}
                for effect, allowed in pairs(entity.allowed_effects) do
                    if allowed then table.insert(allowed_effects, effect) end
                end
                if #allowed_effects > 0 then
                    edata.allowed_effects = allowed_effects
                end
            end
            
            if entity.production ~= nil then
                edata.production = format_watts(entity.production * 60)
            end
            
            if entity.rocket_parts_required ~= nil then
                edata.rocket_parts_required = entity.rocket_parts_required
            end
            
            if entity_map[entity.type] ~= nil then
                entity_map[entity.type][entity.name] = edata
            end
            
            edata.energy_source = get_energy_source(entity)
        end
    end
    
    for key, value in pairs(entity_map) do
        if data[key] ~= nil then
            error("Key already exsits in data: " .. key)
        end
        data[key] = value
    end
end

local function ignore_item(item)
    if item.subgroup.name == "data-dumper-transporter" then return true end
    if item.subgroup.name == "fill-barrel" then return true end
    if item.subgroup.name == "empty-barrel" then return true end
    --if item.has_flag("hidden") then return true end
    return false
end

local function process_items(data, used_items)
    for _, item in pairs(used_items) do
        data.groups[item.group.name] = item.group
        if not ignore_item(item) then
            local icon_data = load_icons(data, {{item.type, item.name}})
            local idata = {
                group = item.group.name,
                name = item.name,
                order = item.order,
                subgroup = item.subgroup.name,
                type = item.type,
                
                icon = icon_data.icon,
                icon_size = icon_data.icon_size,
                icons = icon_data.icons
            }
            
            if item.type == "module" then
                local effects = table.deepcopy(item.module_effects)
                for _, v in pairs(effects) do
                    v.bonus = round2(v.bonus, 5)
                end
                
                table.insert(data.modules, item.name)
                idata.effect = effects
                idata.category = item.category
                if #item.limitations > 0 then
                    idata.limitation = item.limitations
                end
            end
            
            if item.fuel_category ~= nil then
                if item.fuel_category == "chemical" then
                    table.insert(data.fuel, item.name)
                end
                idata.fuel_category = item.fuel_category
                idata.fuel_value = item.fuel_value
            end
            
            data.items[item.name] = idata
        end
    end
end

local function process_fluids(data, used_fluids)
    for _, fluid in pairs(used_fluids) do
        assert(data.items[fluid.name] == nil)
        data.groups[fluid.group.name] = fluid.group
        table.insert(data.fluids, fluid.name)
        local icon_data = load_icons(data, {{"fluid", fluid.name}})
        data.items[fluid.name] = {
            group = fluid.group.name,
            name = fluid.name,
            order = fluid.order,
            subgroup = fluid.subgroup.name,
            type = "fluid",
            
            icon = icon_data.icon,
            icon_size = icon_data.icon_size,
            icons = icon_data.icons
        }
        
    end
end

local function process_recipes(data)
    local ignoresubgroup = {
        ["fill-barrel"] = true,
        ["empty-barrel"] = true,
    }
    data.recipes = {}

    for _, name in ipairs(special_items) do
        used_items[name] = game.item_prototypes[name]
    end    
    
    for key, recipe in pairs(game.recipe_prototypes) do
        data.groups[recipe.group.name] = recipe.group
        if ignoresubgroup[recipe.subgroup.name] == nil then
            local pmult = nil
            if recipe.request_paste_multiplier ~= 30 then -- 30 is default
                pmult = recipe.request_paste_multiplier
            end
            
            icon_paths = {{"recipe", recipe.name}}
            if #recipe.products == 1 then
                local product = recipe.products[1]
                if product.type == "fluid" then
                    table.insert(icon_paths, {"fluid", product.name})
                else
                    local proto = game.item_prototypes[product.name]
                    table.insert(icon_paths, {proto.type, proto.name})
                end
            end
            
            local products = table.deepcopy(recipe.products)
            for _, product in pairs(products) do
                if product.amount_min ~= nil and (product.amount_min == product.amount_max) then
                    product.amount = product.amount_min
                    product.amount_min = nil
                    product.amount_max = nil
                end
                if product.probability == 1 then
                    product.probability = nil
                end
                if product.type == "item" then
                    product.type = nil
                end
            end            
            
            local ingredients = table.deepcopy(recipe.ingredients)
            for _, ingredient in pairs(ingredients) do
                if ingredient.type == "item" then
                    ingredient.type = nil
                end
            end
            
            local icon_data = load_icons(data, icon_paths)
            data.recipes[key] = {
                category = recipe.category,
                energy_required = recipe.energy,
                ingredients = ingredients,
                name = recipe.name,
                order = recipe.order,
                results = products,
                main_product = data._main_products[recipe.name],
                subgroup = recipe.subgroup.name,
                requester_paste_multiplier = pmult,
                type = "recipe",
                
                icon = icon_data.icon,
                icon_size = icon_data.icon_size,
                icons = icon_data.icons
                
            }
        end
    end
end

local function format_groups(groups)
    local formatted = {}

    for _, group in pairs(groups) do
        local subgroups = {}
        for _, subgroup in ipairs(group.subgroups) do
            subgroups[subgroup.name] = subgroup.order
        end
        formatted[group.name] = {
            order=group.order,
            subgroups=subgroups,
        }
    end
    return formatted
end

local function generate_data()
    local data = {
        active_mods = game.active_mods,
        items = {},
        groups = {},
        fluids = {},
        fuel = {},
        modules = {},
    }
    
    storage = json.decode(game.item_prototypes["data-dumper-transporter"].localised_name[1])
    data._icons = storage.icons
    data._main_products = storage.main_products

    used_items, used_fluids = get_used_items()

    process_recipes(data)
    process_entities(data)
    process_items(data, used_items)
    process_fluids(data, used_fluids)

    table.sort(data.fluids)
    table.sort(data.fuel)
    table.sort(data.modules)
    
    data._icons = nil
    
    data.groups = format_groups(data.groups)
    
    return json.encode(data)
end

commands.add_command("datadump", "Dump prototype data to a file", function(opts)
    local filename = (opts.parameter or "gamedata") .. ".json"
    game.write_file(filename, generate_data(), false, opts.player_index)
    game.print("Dumped to " .. filename)
end)

script.on_nth_tick(1, function()
    script.on_nth_tick(1, nil)

    game.write_file("gamedata.json", generate_data())
    print("Dumped to gamedata.json")
end)
