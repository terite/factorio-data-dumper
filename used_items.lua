
local function len_table(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

local function get_possible_technology()

    local locked_tech = {}
    for name, proto in pairs(game.technology_prototypes) do
        locked_tech[name] = proto
    end
    
    local enabled_tech = {}
    local disabled_tech = {}

    while true do
        local did_anything = false
        
        for name, tech in pairs(game.technology_prototypes) do
            if (enabled_tech[name] == nil) and (disabled_tech[name] == nil) then
                local num_prereqs = len_table(tech.prerequisites)
                if not tech.enabled then
                    -- tech is disabled directly
                    disabled_tech[name] = tech
                    did_anything = true
                elseif num_prereqs == 0 then
                    enabled_tech[name] = tech
                    did_anything = true
                else
                    -- check all its prereqs
                    local any_disabled = false
                    local num_enabled = 0
                    for subname in pairs(tech.prerequisites) do
                        if disabled_tech[subname] ~= nil then
                            any_disabled = true
                        elseif enabled_tech[subname] ~= nil then
                            num_enabled = num_enabled + 1
                        end
                    end
                    
                    if any_disabled then
                        disabled_tech[name] = tech
                        did_anything = true
                    elseif num_enabled == num_prereqs then
                        enabled_tech[name] = tech
                        did_anything = true
                    end
                end
            end
        end
        
        if not did_anything then break end
    end
    
    --[[
    if len_table(disabled_tech) > 0 then
        game.print('has disabled tech')
        names = {""}
        for _, tech in pairs(disabled_tech) do
            table.insert(names, tech.localised_name)
            table.insert(names, ", ")
        end
        game.print(names)
    else
        game.print("all tech enabled")
    end
    ]]--
    
    return enabled_tech
end

local function recipe_consumes_product(recipe, needle)
    for _, row in ipairs(recipe.ingredients) do
        if (row.name == needle.name and row.type == needle.type) then
            return true
        end
    end
    return false
end

local function items_match(ingredients, products)
    if #ingredients ~= #products then
        return false
    end
    item_set = {}
    for _, ing in ipairs(ingredients) do
        item_set[ing.name] = true
    end
    
    for _, prod in ipairs(products) do
        if item_set[prod.name] == nil then
            return false
        end
        item_set[prod.name] = nil
    end
    
    return len_table(item_set) == 0
end

local function circular_recipe_partner(recipe1, all_recipes)
    -- this function expects to be given "barreling" recipes
    -- and will return the cooresponding "unbarreling" recipe
    -- assuming no other recipe uses "barreled X"
    if (#recipe1.products ~= 1) then
        return nil
    end

    local intermediate = recipe1.products[1]

    local recipe2 = nil
    for _, candidate in pairs(all_recipes) do
        if recipe_consumes_product(candidate, intermediate) then
            -- assume "unbarreling" ingredients == "barreling" products
            if not items_match(recipe1.ingredients, candidate.products) then
                return nil
            end
            
            if recipe2 ~= nil then
                -- more than one recipe consumes intermediate, recipe is not part of a solo pair
                return nil
            else
                -- recipe & candidate are a pair, keep searching to ensure a solo pair
                recipe2 = candidate
            end
        end
    end
    
    return recipe2
end

local function remove_circular_recipes(recipes)
    -- remove "circular" recipes, where the only consumer of a recipes products
    -- is a recipe that produces the original inputs
    -- e.g. barreling, bottling (bobs), converter valves (seablock)
    to_remove = {}
    
    for name, recipe in pairs(recipes) do
        if to_remove[name] == nil then
            local partner = circular_recipe_partner(recipe, recipes)
            if (partner ~= nil) then
                to_remove[recipe.name] = true
                to_remove[partner.name] = true
            end
        end
    end
    
    for name, _ in pairs(to_remove) do
        recipes[name] = nil
    end
    
    return recipes
end

local function get_possible_recipes(possible_tech)
    local recipes = {}
    
    -- recipes enabled at game start
    for name, recipe in pairs(game.recipe_prototypes) do
        if recipe.enabled then
            recipes[name] = recipe
        end
    end
    
    -- recipes unlocked by technology
    for _, tech in pairs(possible_tech) do
        for _, effect in ipairs(tech.effects) do
            if effect.type == "unlock-recipe" then
                local recipe = game.recipe_prototypes[effect.recipe]
                recipes[recipe.name] = recipe
            end
        end
    end
    
    -- recipes = remove_circular_recipes(recipes)
    return recipes
end

local function get_used_items()
    local possible_tech = get_possible_technology()
    local possible_recipes = get_possible_recipes(possible_tech)

    local used_items = {}
    local used_fluids = {}

    local add_item = nil
    local add_fluid = nil
    local add_ingredients = nil
    
        
    add_fluid = function(name)
        if used_fluids[name] ~= nil then
            return
        end
        used_fluids[name] = game.fluid_prototypes[name]
    end
    
    add_item = function(name)
        if used_items[name] ~= nil then
            return
        end
        
        local item = game.item_prototypes[name]
        used_items[name] = item
        if item.burnt_result then
            add_item(item.burnt_result.name)
        end
        add_ingredients(item.rocket_launch_products)
    end

    add_ingredients = function(list)
        for _, entry in pairs(list) do
            if entry.type == 'fluid' then
                add_fluid(entry.name)
            else
                add_item(entry.name)
            end
        end
    end

    for _, recipe in pairs(possible_recipes) do
        add_ingredients(recipe.ingredients)
        add_ingredients(recipe.products)
    end

    for _, entity in pairs(game.entity_prototypes) do
        if entity.type == "resource" and entity.mineable_properties.minable then
            add_ingredients(entity.mineable_properties.products)
        end
    end

    for _, tech in pairs(possible_tech) do
        add_ingredients(tech.research_unit_ingredients)
    end

    return used_items, used_fluids, possible_recipes
end

return get_used_items
