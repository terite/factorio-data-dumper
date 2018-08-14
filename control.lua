-- for table.deepcopy
require("util")

local json = require("json")

local get_used_items = require("used_items")

local function round2(num, numDecimalPlaces)
  return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local function belt_throughput(belt_speed)
    -- convert speed from tiles-per-tick-per-side to items-per-minute-per-belt
    -- https://wiki.factorio.com/Transport_belts/Physics
    return belt_speed * 60 * 60 * 2 / (9/32)
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

local function len_table(tbl)
    count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
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
    watts = watts * 60 -- convert from joules/tick to joules/sec
    return format_magnitude(watts, {"W", "kW", "MW", "GW", "TW", "PW"})
end

local function format_joules(joules)
    return format_magnitude(joules, {"J", "kJ", "MJ", "GJ", "TJ", "PJ"})
end

local function format_products(products)
    local products = table.deepcopy(products)
    for _, product in pairs(products) do
        if product.amount_min ~= nil and (product.amount_min == product.amount_max) then
            product.amount = product.amount_min
            product.amount_min = nil
            product.amount_max = nil
        end
        if product.probability == 1 then
            product.probability = nil
        end
    end
    return products
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

local function process_entity(entity)
    edata = {
        name = entity.name,
        localised_name = entity.localised_name,
    }

    if entity.energy_usage ~= nil then
        edata.energy_usage = entity.energy_usage * 60 -- convert from tick to sec
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
        edata.allowed_effects = allowed_effects
    end
    
    if entity.production ~= nil then
        edata.production = format_watts(entity.production)
    end
    
    edata.energy_source = get_energy_source(entity)

    if entity.type == "assembling-machine" then
        -- TODO
    elseif entity.type == "furnace" then
        -- TODO
    elseif entity.type == "mining-drill" then
        edata.mining_power = entity.mining_power
        edata.mining_speed = entity.mining_speed
        edata.resource_categories = get_allowed(entity.resource_categories)
    elseif entity.type == "offshore-pump" then
        edata.fluid = entity.fluid.name
        edata.mining_speed = entity.mining_speed
    elseif entity.type == "reactor" then
        -- TODO
    elseif entity.type == "resource" then
        edata.category = entity.resource_category
        local resdata = entity.mineable_properties
        edata.minable = {}
        edata.minable.hardness = resdata.hardness
        edata.minable.mining_time = resdata.mining_time
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
    elseif entity.type == "rocket-silo" then
        edata.rocket_parts_required = entity.rocket_parts_required
    elseif entity.type == "transport-belt" then
        edata.belt_speed = belt_throughput(entity.belt_speed)
    else
        return nil
    end

    return edata
end

local function process_entities(data)
    for _, entity in pairs(game.entity_prototypes) do
        edata = process_entity(entity)

        if edata ~= nil then
            local icon_data = data._icons[entity.type][entity.name]
            assert(icon_data ~= nil) -- entities must have icons
            edata.icon = icon_data.icon
            edata.icon_size = icon_data.icon_size
            edata.icons = icon_data.icons

            data[entity.type] = data[entity.type] or {}
            data[entity.type][entity.name] = edata
        end
    end
end

local function should_collect_item(item)
    if item.subgroup.name == "data-dumper-transporter" then return false end
    if item.subgroup.name == "fill-barrel" then return false end
    if item.subgroup.name == "empty-barrel" then return false end
    return true
end

local function process_items(data, used_items)
    for _, item in pairs(used_items) do
        data.groups[item.group.name] = item.group
        if should_collect_item(item) then
            local icon_data = data._icons[item.type][item.name]
            assert(icon_data ~= nil)
            local idata = {
                group = item.group.name,
                name = item.name,
                localised_name = item.localised_name,
                order = item.order,
                subgroup = item.subgroup.name,
                type = item.type,
                rocket_launch_products = format_products(item.rocket_launch_products),
                
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
                idata.limitation = item.limitations
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
        local icon_data = data._icons["fluid"][fluid.name]
        assert(icon_data ~= nil)
        data.items[fluid.name] = {
            group = fluid.group.name,
            name = fluid.name,
            localised_name = fluid.localised_name,
            order = fluid.order,
            subgroup = fluid.subgroup.name,
            type = "fluid",
            default_temperature = fluid.default_temperature,
            
            icon = icon_data.icon,
            icon_size = icon_data.icon_size,
            icons = icon_data.icons
        }
        
    end
end

local function process_recipes(data, recipes)
    local ignoresubgroup = {
        ["fill-barrel"] = true,
        ["empty-barrel"] = true,

        ["bob-gas-bottle"] = true,
        ["bob-empty-gas-bottle"] = true,
    }
    data.recipes = {}

    for key, recipe in pairs(recipes) do
        data.groups[recipe.group.name] = recipe.group
        if ignoresubgroup[recipe.subgroup.name] == nil then
            
            local products = format_products(recipe.products)
            local ingredients = table.deepcopy(recipe.ingredients)
            
            local icon_data = data._icons['recipe'][recipe.name]
            icon_data = icon_data or {} -- recipe icons need resolved in processing

            data.recipes[key] = {
                category = recipe.category,
                energy_required = recipe.energy,
                ingredients = ingredients,
                name = recipe.name,
                localised_name = recipe.localised_name,
                order = recipe.order,
                results = products,
                main_product = data._main_products[recipe.name],
                group = recipe.group.name,
                subgroup = recipe.subgroup.name,
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

    used_items, used_fluids, possible_recipes = get_used_items()
    game.print("used_items:" .. len_table(used_items))
    game.print("used_fluids:" .. len_table(used_fluids))
    game.print("possible_recipes:" .. len_table(possible_recipes))

    process_recipes(data, possible_recipes)
    process_entities(data)
    process_items(data, used_items)
    process_fluids(data, used_fluids)

    table.sort(data.fluids)
    table.sort(data.fuel)
    table.sort(data.modules)
    
    data._icons = nil
    data._main_products = nil
    
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
