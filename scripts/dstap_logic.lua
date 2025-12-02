
-- Helper functions
local function setToList(t)
    local ret = {}
    for k, v in pairs(t) do
        if v then
            table.insert(ret, k)
        end
    end
    return ret
end
local function listToSet(t)
    local ret = {}
    for _, v in ipairs(t) do
        ret[v] = true
    end
    return ret
end
------------------
local _unsafe_rules = true
------------------
local PRETTYNAME_TO_ITEM_ID = {}
for id, v in pairs(ArchipelagoDST.ID_TO_ITEM) do
    PRETTYNAME_TO_ITEM_ID[v.prettyname] = id
end
local PRETTYNAME_TO_LOCATION_ID = {}
for id, v in pairs(ArchipelagoDST.ID_TO_LOCATION) do
    PRETTYNAME_TO_LOCATION_ID[v.prettyname] = id
end
local ITEM_ADDITIONAL_RULE = {}
local is_character = function(charpref)
    for _, player in pairs(AllPlayers) do
        if player and player.prefab == charpref then
            return true
        end
    end
    return false
end
local CHARACTER_RULES = {}
for k, prettyname in pairs(ArchipelagoDST.RAW.CHARACTER_PREFAB_TO_PRETTYNAME) do
    CHARACTER_RULES[prettyname] = function() return is_character(k) end
end

local function is_locked(item)
    local id = PRETTYNAME_TO_ITEM_ID[item]
    if id then
        return ArchipelagoDST.lockableitems[id]
    else
        print("is_locked: No such item called", item)
    end
end

local HAS_ITEM = {}
local CAN_CRAFT = {}
local PRETTYNAME_ITEM_INGREDIENTS = {}
local ITEM_EVENT_REFERENCES = {}

local function has(item, difficulty)
    difficulty = difficulty or "default"
    local id = PRETTYNAME_TO_ITEM_ID[item]
    if CHARACTER_RULES[item] then
        -- print("has: calling character rule:", item)
        return CHARACTER_RULES[item](difficulty)
    end
    local craftablefn = id and CAN_CRAFT[id]
    local hasfn = id and HAS_ITEM[id]
    local is_craftable = (craftablefn and craftablefn(difficulty)) or (hasfn and hasfn(difficulty))
    if ArchipelagoDST.crafting_mode == ArchipelagoDST.CRAFT_MODES.LOCKED_INGREDIENTS then
        return is_craftable and ArchipelagoDST.collecteditems[id]
    end
    return is_craftable
end
local function combineSets(a,b)
    if not a then return b end
    if not b then return a end
    local c = deepcopy(a)
    for k, _ in pairs(b) do
        c[k] = true
    end
    return c
end

local LogicHelper = Class(function(self) end)

function LogicHelper:toRule(node, difficulty)
    difficulty = difficulty or "default"
    if node == nil then
        -- print("toRule: Error! node is not defined!")
        return nil
    end
    if node == true or node == false then
        -- print("toRule: Converted boolean into fn")
        return function() return node end
    elseif type(node) == "function" then
        -- print("toRule: Rule is already a fn")
        return node
    elseif type(node) == "string" then
        -- print("toRule: Converted string into fn", node)
        return function()
            return has(node, difficulty)
        end
    elseif type(node) == "table" then
        assert(not _unsafe_rules)
        local fn
        if node[difficulty.."_cached"] then
            -- print("> Returning Cached Result <")
            return node[difficulty.."_cached"]
        end
        if node and node.get then
            -- print("toRule: Converting event into node", node and node.type or "unnamed")
            node = self:getNode(node)
        end
        if not node then
            -- print("toRule: Error! Could not get event!")
            return nil
        end

        if node.fn then
            -- print("toRule: Node has fn rule", node and node.type or "unnamed")
            fn = node.fn
        elseif difficulty == "default" then
            -- print("toRule: Getting rule from default node", node and node.type or "unnamed")
            fn = node.default and self:toRule(node.default, difficulty) or nil
        elseif difficulty == "hard" then
            -- print("toRule: Getting rule from hard node", node and node.type or "unnamed")
            fn = (node.hard or node.default) and function()
                local a = self:toRule(node.default, difficulty)
                local b = self:toRule(node.hard, difficulty)
                return (a and a(difficulty)) or (b and b(difficulty)) 
            end or nil
            
        elseif difficulty == "helpful" then
            -- print("toRule: Getting rule from helpful node", node and node.type or "unnamed")
            fn = (node.helpful or node.default) and function()
                local a = self:toRule(node.helpful, difficulty)
                local b = self:toRule(node.default, difficulty)
                return a and a(difficulty) and b and b(difficulty)
            end or nil
        end
        
        if fn then
            -- print("toRule: Calling rule:", node and node.type or "unnamed")
            local result = fn(difficulty)
            -- print("toRule: Returning and caching rule result:", result, node and node.type or "unnamed")
            node[difficulty.."_cached"] = function() return result end
            return node[difficulty.."_cached"]
        end
    end
end

function LogicHelper:toNode(node, difficulty)
    if not node then return nil end
    if type(node) == "function" then
        return {
            fn = node,
        }
    end
    if type(node) == "string" then
        return {
            name = node,
            itemname = node,
            fn = self:toRule(node),
            toReqsFn = function(difficulty)
                return self:toReqsFn(node, difficulty)
            end,
        }
    end
    if type(node) == "table" then
        return node
    end
end

function LogicHelper:getNode(node)
    node = self:toNode(node)
    if node and node.get then
        return self:getNode(node.get())
    end
    if node then
        return node
    end
end

function LogicHelper:toReqsFn(node, difficulty)
    difficulty = difficulty or "default"
    if not node then return end
    if type(node) == "string" then
        -- print("Returning string converted into fillreqs: "..node)
        if CHARACTER_RULES[node] then
            return function(reqs)
                reqs.characters[node] = true
                if CHARACTER_RULES[node]() then
                    reqs.has_characters[node] = true
                end
            end
        else
            return function(reqs, spread)
                reqs.items[node] = true
                local item_id = PRETTYNAME_TO_ITEM_ID[node]
                local ingredients = PRETTYNAME_ITEM_INGREDIENTS[node]
                if ingredients then
                    for prettyname, istrue in pairs(ingredients) do
                        if istrue and not has(prettyname, difficulty) then
                            reqs.items[prettyname] = true
                        end
                    end
                end
                local eventnode = ITEM_EVENT_REFERENCES[node]
                local fillreqs = self:toReqsFn(eventnode, difficulty)
                if fillreqs and spread and eventnode.spread ~= false then
                    fillreqs(reqs, spread)
                end
            end
        end
    end
    if type(node) == "table" then
        if node.hint then
            -- print("Returning hint converted into fillreqs: "..node.hint)
            return function(reqs)
                reqs.events[node.hint] = true
                reqs.has_events[node.hint] = true
            end
        elseif node.comment then
            -- print("Returning comment converted into fillreqs: "..node.comment)
            return function(reqs)
                reqs.comments[node.comment] = true
            end
        elseif node.get then
            local eventnode = self:getNode(node.get())
            if eventnode and eventnode.type then
                -- print("Returning event fillreqs for "..eventnode.type)
                return function(reqs, spread)
                    if not eventnode.hidden and not node.hidden then
                        reqs.events[eventnode.type] = true
                        local rule = self:toRule(node, difficulty)
                        if rule and rule(difficulty) then
                            reqs.has_events[eventnode.type] = true
                        end
                    end
                    local fillreqs = self:toReqsFn(eventnode, difficulty)
                    if fillreqs and spread and eventnode.spread ~= false and node.spread ~= false then
                        fillreqs(reqs, spread)
                    end
                end
            end
            -- print("ERROR! Failed to get eventnode")
        elseif node.spread == false then
            -- print("Node is not allowed to spread:", node.type or "unknown")
            return
        elseif node.fillreqs then
            -- print("Returning predefined fillreqs", node.type or "unknown")
            return node.fillreqs
        elseif node.toReqsFn then
            if node.spread ~= false then
                -- print("Calling fillreqs fn", node.type or "unknown")
                return node.toReqsFn(difficulty)
            end
            -- print("Node is not allowed to spread")
        else
            -- print("Getting fillreqs from difficulty "..difficulty, node.type or "unknown")
            node = self:toNode(node[difficulty]) or self:toNode(node["default"])
            if node and node.spread ~= false then
                -- print("Returning difficulty fillreqs", node.type or "unknown")
                return self:toReqsFn(node, difficulty)
            end
            if not node then
                -- print("Difficulty "..difficulty.." doesn't exist!")
            else
                -- print("Difficulty "..difficulty.." is not allowed to spread", node.type or "unknown")
            end
        end    
    end
end
local logichelper = LogicHelper()
local toRule = function(...) return logichelper:toRule(...) end
local toNode = function(...) return logichelper:toNode(...) end
local getNode = function(...) return logichelper:getNode(...) end
local toReqsFn = function(...) return logichelper:toReqsFn(...) end

---------- Debug fn --------------
local _getnames = function(list)
    local ret = {}
    for _, v in pairs(list) do
        table.insert(ret, (type(v) == "table" and v.type or "Unnamed") or (type(v) == "string" and v) or "Unknown")
    end
    return table.concat(ret, ", ")
end
----------------------------------
local function any_all_common(...)
    local rules = {...}
    local node = {
        toReqsFn = function(difficulty)
            return function(reqs, spread)
                -- if spread == false then return end
                for _, v in pairs(rules) do
                    local fillreqs = toReqsFn(v, difficulty)
                    if fillreqs then
                        fillreqs(reqs, spread)
                    end
                end
            end
        end
    }
    return node
end
local function any(...)
    local rules = {...}
    local node = any_all_common(...)
    node.type = "Any"
    node.fn = function(difficulty)
        -- print("Calling Any rule with "..#rules.." rules: ".._getnames(rules))
        for _, v in pairs(rules) do
            -- print("Getting rule from", v and (type(v) == "table" and v.type or "Unnamed") or (type(v) == "string" and v) or v or "Unknown")
            local rule = toRule(v, difficulty)
            if rule then
                if rule(difficulty) then
                    -- print("Any rule has evaluated as true")
                    return true
                end
            else
                -- print("Empty rule")
            end
        end
        -- print("Any rule has evaluated as false (No valid conditions)")
        return false
    end
    return node
end
local function all(...)
    local rules = {...}
    local node = any_all_common(...)
    node.type = "All"
    node.fn = function(difficulty)
        -- print("Calling All rule with "..#rules.." rules: ".._getnames(rules))
        for _, v in pairs(rules) do
            -- print("Getting rule from", v and (type(v) == "table" and v.type or "Unnamed") or (type(v) == "string" and v) or v or "Unknown")
            local rule = toRule(v, difficulty)
            if rule then
                if not rule(difficulty) then
                    -- print("All rule has evaluated as false")
                    return false
                end
            else
                -- print("Empty rule")
            end
        end
        -- print("All rule has evaluated as true (No invalid conditions)")
        return true
    end
    return node
end
local function comment(commentstring)
    return {
        type = "Comment",
        comment = commentstring,
    }
end
local _self_reference = nil
local function self_reference()
    _self_reference = _self_reference or {}
    return _self_reference
end
local function add_event(name, ruleset)
    assert(type(ruleset) == "table")
    -- Set self referenced item
    if _self_reference then
        local id = PRETTYNAME_TO_ITEM_ID[name]
        _self_reference.fn = id and CAN_CRAFT[id] or nil
    end
    _self_reference = nil
    --
    local node = {
        name = name,
        type = name,
        default = (ruleset.default and toNode(ruleset.default))
            or (not ruleset.fn and function() return true end)
            or nil,
        helpful = toNode(ruleset.helpful),
        hard = toNode(ruleset.hard),
        spread = ruleset.spread,
        hidden = ruleset.hidden,
        fn = ruleset.fn,
    }
    if ruleset.comment then
        node.default = all(comment(ruleset.comment), node.default)
    end
    -- Apply additional rules to items
    if not ruleset.dont_link_to_item then
        local item_id = PRETTYNAME_TO_ITEM_ID[name]
        if ArchipelagoDST.lockableitems[item_id] then
            node.hidden = true
            ITEM_ADDITIONAL_RULE[item_id] = function(difficulty)
                local rule = toRule(node, difficulty)
                return rule and rule(difficulty) or false
            end
            ITEM_EVENT_REFERENCES[name] = node
        end
    end
    
    return node
end
local function cookrecipe(rule, recipe)
    local node = toNode(rule)
    node.recipe = recipe
    return node
end
local function stringhint(prefab)
    return {
        type = "Hint",
        hint = STRINGS.NAMES[string.upper(prefab)] or prefab,
    }
end
local function hard(rule)
    return {
        type = "Hard",
        hard = rule,
    }
end
local function helpful(rule)
    return {
        type = "Helpful",
        helpful = rule,
    }
end
local function no_spread(rule)
    local node = toNode(rule)
    if node then
        node = shallowcopy(node)
        node.spread = false
        return node
    end
end
local function hidden(rule)
    local node = toNode(rule)
    if node then
        node = shallowcopy(node)
        node.hidden = true
        return node
    end
end
local function noop(rule)
    return rule
end

local ALWAYS_TRUE = function() return true end
local ALWAYS_FALSE = function() return false end
local Logic = Class(function(self)
    _unsafe_rules = true
    ITEM_EVENT_REFERENCES = {}
    local function Event(eventname)
        local node = {
            type = eventname.." (Event)",
            get = function()
                -- assert(EVENTS[eventname])
                return self.EVENTS[eventname]
            end,
        }
        return node
    end
    local function NoSpreadEvent(...)
        return no_spread(Event(...))
    end
    local function HiddenEvent(...)
        return hidden(Event(...))
    end
    local FARMPLANT_SEASON_RULES = {
        ["Asparagus"] =     any(NoSpreadEvent("winter"), NoSpreadEvent("spring")),
        ["Garlic"] =        ALWAYS_TRUE,
        ["Pumpkin"] =       any(NoSpreadEvent("autumn"), NoSpreadEvent("winter")),
        ["Corn"] =          any(NoSpreadEvent("autumn"), NoSpreadEvent("spring"), NoSpreadEvent("summer")),
        ["Onion"] =         any(NoSpreadEvent("autumn"), NoSpreadEvent("spring"), NoSpreadEvent("summer")),
        ["Potato"] =        any(NoSpreadEvent("autumn"), NoSpreadEvent("winter"), NoSpreadEvent("spring")),
        ["Dragon Fruit"] =  any(NoSpreadEvent("spring"), NoSpreadEvent("summer")),
        ["Pomegranate"] =   any(NoSpreadEvent("spring"), NoSpreadEvent("summer")),
        ["Eggplant"] =      any(NoSpreadEvent("autumn"), NoSpreadEvent("spring")),
        ["Toma Root"] =     any(NoSpreadEvent("autumn"), NoSpreadEvent("spring"), NoSpreadEvent("summer")),
        ["Watermelon"] =    any(NoSpreadEvent("spring"), NoSpreadEvent("summer")),
        ["Pepper"] =        any(NoSpreadEvent("autumn"), NoSpreadEvent("summer")),
        ["Durian"] =        NoSpreadEvent("spring"),
        ["Carrot"] =        any(NoSpreadEvent("autumn"), NoSpreadEvent("winter"), NoSpreadEvent("spring")),
    }
    
    local function add_farming_event(veggiename, or_condition)
        local veggie_season_rule = FARMPLANT_SEASON_RULES[veggiename] or ALWAYS_TRUE
        return add_event(veggiename.." Farming", {
            default = any(all(HiddenEvent("basic_farming"), is_locked(veggiename.." Seeds") and (veggiename.." Seeds") or veggie_season_rule), or_condition)
        })
    end

    local function add_exist_event(prefab)
        local prettyname = STRINGS.NAMES[string.upper(prefab)] or prefab
        return add_event(prettyname.." Exists", {
            fn = function() return ArchipelagoDST.globalinfo[prefab.."_exists"] or false end,
            comment = ArchipelagoDST.globalinfo[prefab.."_exists"] and (prettyname.." exists in the world.") or nil,
            hidden = true
        })
    end

    local CRAFT_WITH_LOCKED_RECIPES = ArchipelagoDST.craftingmode == ArchipelagoDST.CRAFT_MODES.LOCKED_INGREDIENTS
    -- Right now the client doesn't send region options to DST, so we're implying through all_locations
    local REGION = {
        FOREST = true,
        CAVE = ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[8 + ArchipelagoDST.RAW.LOCATION_ID_OFFSET], -- Hutch
        RUINS = ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[751 + ArchipelagoDST.RAW.LOCATION_ID_OFFSET], -- Pseudoscience (Purple Gem)
        ARCHIVE = ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[1 + ArchipelagoDST.RAW.LOCATION_ID_OFFSET], -- Distilled Knowledge (Yellow)
        OCEAN = ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[851 + ArchipelagoDST.RAW.LOCATION_ID_OFFSET], -- Bottle Exchange (1)
        MOONQUAY = ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[5 + ArchipelagoDST.RAW.LOCATION_ID_OFFSET], -- Queen of Moon Quay
        MOONSTORM = ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[4 + ArchipelagoDST.RAW.LOCATION_ID_OFFSET], -- Wagstaff during Moonstorm
    }
    local SEASON = {
        AUTUMN = true,
        WINTER = true,
        SPRING = true,
        SUMMER = true,
        NONWINTER = true,
        NONSPRING = true,
        NONSUMMER = true,
    }
    local PHASE = {
        DAY = true,
        DUSK = true,
        NIGHT = true,
    }

    self.EVENTS = {
        ----- SEASONS -----
        autumn = SEASON.AUTUMN and add_event("Autumn", 
            is_locked("Autumn")
            and { 
                default = "Autumn",
                dont_link_to_item = true,
            }
            or { fn = function() return TheWorld and TheWorld.state.season == "autumn" end }
        ),
        winter = SEASON.WINTER and add_event("Winter", 
            is_locked("Winter")
            and { 
                default = all("Winter", NoSpreadEvent("winter_survival")),
                hard = "Winter",
                dont_link_to_item = true,
            }
            or { 
                fn = function() return TheWorld and TheWorld.state.season == "winter" end,
            }
        ),
        spring = SEASON.SPRING and add_event("Spring", 
            is_locked("Spring")
            and { 
                default = all("Spring", NoSpreadEvent("spring_survival")),
                hard = "Spring",
                dont_link_to_item = true,
            }
            or {
                fn = function() return TheWorld and TheWorld.state.season == "spring" end,
            }
        ),
        summer = SEASON.SUMMER and add_event("Summer", 
            is_locked("Summer")
            and { 
                default = all("Summer", NoSpreadEvent("summer_survival")),
                hard = "Summer",
                dont_link_to_item = true,
            }
            or {
                fn = function() return TheWorld and TheWorld.state.season == "summer" end,
            }
        ),

        ----- DAY PHASES -----
        day = add_event("Day", {
            fn = function() return PHASE.DAY end
        }),
        dusk = add_event("Dusk", {
            fn = function() return PHASE.DUSK end
        }),
        night = add_event("Night", {
            fn = function() return PHASE.NIGHT end
        }),
        
        ----- SEASONS PASSED -----
        full_moon = add_event("Full Moon", 
            is_locked("Full Moon Phase Change")
            and {
                default = "Full Moon Phase Change",
                dont_link_to_item = true,
            }
            or { fn = function() return TheWorld and TheWorld.state.cycles >= 11 end }
        ),
        seasons_passed_half = add_event("Day 11", {
            fn = function() return TheWorld and TheWorld.state.cycles >= 11 end,
            hidden = true,
        }),
        seasons_passed_1 = add_event("Day 21", {
            fn = function() return TheWorld and TheWorld.state.cycles >= 21 end
        }),
        seasons_passed_2 = add_event("Day 36", {
            fn = function() return TheWorld and TheWorld.state.cycles >= 36 end
        }),
        seasons_passed_3 = add_event("Day 56", {
            fn = function() return TheWorld and TheWorld.state.cycles >= 56 end
        }),
        seasons_passed_4 = add_event("Day 71", {
            fn = function() return TheWorld and TheWorld.state.cycles >= 71 end
        }),
        seasons_passed_5 = add_event("Day 91", {
            fn = function() return TheWorld and TheWorld.state.cycles >= 91 end
        }),

        ----- TOOLS -----
        any_pickaxe = add_event("Any Pickaxe", {
            default = any("Pickaxe", "Opulent Pickaxe"),
            hard    = "Woodie",
            spread  = false,
        }),
        any_axe = add_event("Any Axe", {
            default = any("Axe", "Luxury Axe", "Woodie"),
            spread  = false,
        }),
        any_shovel = add_event("Any Shovel", { 
            default = any("Shovel", "Regal Shovel"),
            hard    = "Woodie",
            spread  = false,
        }),
        any_hoe = add_event("Any Gardening Hoe", { 
            default = any("Garden Hoe", "Splendid Garden Hoe", "Wormwood"),
            spread  = false,
        }),
        bird_caging = add_event("Bird Caging", { 
            default = all("Bird Trap", "Birdcage"),
            hard    = "Birdcage",
        }),
        ice_staff = add_event("Ice Staff", {
            default = self_reference(),
            helpful = Event("any_shovel"),
        }),
        fire_staff = add_event("Fire Staff", {
            default = self_reference(),
            helpful = Event("any_shovel"),
        }),
        firestarting = add_event("Firestarting", {
            default = any("Torch", "Willow", "Fire Staff", "Campfire"),
            helpful = Event("any_axe"),
            spread  = false,
        }),
        morning_star = add_event("Morning Star", {
            default = self_reference(),
            helpful = all(Event("ranged_aggression"), Event("desert"), Event("basic_combat")),
            spread  = false,
        }),
        cannon = add_event("Cannon Kit", {
            default = all(self_reference(), Event("moon_quay"), "Gunpowder", "Cut Stone", "Rope"),
            helpful = all(Event("charcoal"), Event("any_pickaxe"), Event("bird_caging")),
            spread  = false,
        }),
        razor = add_event("Razor", {
            default = ALWAYS_TRUE,
            helpful = self_reference(),
        }),
        telelocator_staff = add_event("Telelocator Staff", {
            default = all(self_reference(), Event("living_log")),
            helpful = "Purple Gem",
            spread  = false,
        }),
        mooncaller_staff = add_event("Mooncaller Staff", {
            default = Event("moon_stone_event"),
        }),
        deconstruction_staff = add_event("Deconstruction Staff", {
            default = all(
                Event("living_log"),
                is_locked("Deconstruction Staff") and Event("ruins_gems") or Event("ancient_altar"),
                is_locked("Deconstruction Staff") and self_reference() or nil
            ),
        }),


        ----- RESOURCES -----
        rng = add_event("RNG", {
            default = ALWAYS_TRUE,
        }),
        nightmare_fuel = add_event("Nightmare Fuel", {
            default = Event("basic_combat"),
            spread  = false,
        }),
        living_log = add_event("Living Log", {
            helpful = any(Event("any_axe"), "Wormwood"),
        }),
        charcoal = add_event("Charcoal", {
            default = all(Event("any_axe"), Event("firestarting")),
            spread  = false,
        }),
        butter = add_event("Butter", {
            default = all(Event("rng"), Event("butterfly")),
        }),
        feathers = add_event("Can Reach Birds", {
            default = any("Bird Trap", "Boomerang", "Ice Staff"),
            hard = ALWAYS_TRUE,
            hidden = true,
        }),
        gears = add_event("Gears", {
            default = Event("desert"),
            helpful = REGION.RUINS and Event("ruins_exploration") or Event("advanced_combat"),
            spread  = false,
        }),
        ruins_gems = add_event("Ruins Gems", {
            default = any(
                REGION.RUINS and NoSpreadEvent("ruins_exploration") or nil,
                (REGION.RUINS and hidden or noop)(NoSpreadEvent("dragonfly")),
                REGION.OCEAN and (REGION.RUINS and hard or noop)(Event("sunken_chest"))
            ),
            helpful = NoSpreadEvent("dragonfly"),
        }),
        purple_gem = add_event("Purple Gem", {
            default = any(Event("ruins_gems"), Event("any_shovel")),
            spread  = false,
        }),
        canary = add_event("Canary", { 
            default = all("Friendly Scarecrow", "Boards", Event("pumpkin_farming")),
        }),
        salt_crystals = add_event("Salt Crystals", {
            default = all(Event("basic_boating"), Event("any_pickaxe")),
            helpful = Event("basic_combat"),
        }),
        thulecite = add_event("Thulecite", {
            default = (REGION.RUINS and Event("ruins_exploration")) 
                or (REGION.ARCHIVE and Event("ancient_archive")) 
                or (REGION.OCEAN and Event("sunken_chest"))
                or Event("ruins_exploration"), -- Player probably chose caves but not ruins or ocean
        }),
        leafy_meat = add_event("Leafy Meat", {
            default = any(
                Event("lureplant_exists"),
                all(
                    NoSpreadEvent("pre_basic_combat"),
                    any(
                        Event("grassgekko_exists"),
                        no_spread(all(Event("seasons_passed_2"), Event("any_shovel"), any(Event("autumn"), Event("spring"), Event("summer"))))
                    )
                ),
                REGION.OCEAN and Event("lunar_island"),
                REGION.CAVE and Event("cave_exploration")
            ),
            helpful = all(Event("any_shovel"), NoSpreadEvent("spring")) -- Grass Gekko and other sources
        }),    
        electrical_doodad = add_event("Electrical Doodad", {
            default = self_reference(),
            helpful = Event("any_pickaxe"),
            hard    = any(self_reference(), NoSpreadEvent("twins_of_terror")),
        }),
        bird_eggs = add_event("Bird Eggs", {
            default = Event("bird_caging"),
            hard    = Event("winter"),
        }),
        any_eggs = add_event("Any Eggs", {
            default = Event("bird_eggs"),
            hard    = all(Event("basic_combat"), stringhint("tallbirdegg")),
            hidden  = true,
        }),
        butterfly = add_event("Butterfly", {
            default = all(Event("day"), any(NoSpreadEvent("autumn"), NoSpreadEvent("spring"), NoSpreadEvent("summer"))),
        }),
        batilisk = add_event("Batilisk", {
            default = all(Event("pre_basic_combat"), Event("any_pickaxe"), any(Event("dusk"), Event("night"), NoSpreadEvent("cave_exploration"))),
        }),
        moleworm = add_event("Moleworm", {
            default = any(Event("any_shovel"), all(any(Event("dusk"), Event("night")), "Hammer")),
        }),
        rabbit = add_event("Rabbit", {
            default = any(all(any(Event("autumn"), Event("winter"), Event("summer")), Event("day")), Event("any_shovel"),  NoSpreadEvent("cave_exploration")),
        }),


        ----- COMBAT -----
        basic_combat = add_event("Basic Combat", {
            default = any(all("Spear", any("Log Suit", "Football Helmet")), "Wigfrid"),
            hard    = ALWAYS_TRUE,
        }),
        pre_basic_combat = add_event("Pre-Basic Combat", {
            default = any(Event("any_axe"), "Spear", "Wigfrid", "Ham Bat"),
            hard    = ALWAYS_TRUE,
            spread  = false,
        }),
        advanced_combat = add_event("Advanced Combat", {
            default = all(any("Spear", "Ham Bat", "Dark Sword", "Glass Cutter"), "Log Suit", "Football Helmet"),
            hard    = ALWAYS_TRUE,
        }),
        advanced_boss_combat = add_event("Advanced Boss Combat", {
            default = HiddenEvent("advanced_combat"),
            helpful = Event("quick_healing"),
        }),
        epic_combat = add_event("Epic Combat", {
            default = HiddenEvent("advanced_boss_combat"),
            helpful = all(Event("speed_boost"),  NoSpreadEvent("arena_building"), Event("resurrecting")),
        }),
        ranged_combat = add_event("Ranged Combat", {
            helpful = any("Blow Dart", all(NoSpreadEvent("canary"), "Electric Dart"), "Walter"),
        }),
        ranged_aggression = add_event("Ranged Aggression", {
            helpful = any(HiddenEvent("ranged_combat"), "Boomerang", "Sleep Dart", "Fire Dart", "Ice Staff", "Fire Staff", "Walter"),
        }),
        dark_magic = add_event("Dark Magic", {
            helpful = any("Dark Sword", "Bat Bat", "Night Armor"),
        }),


        ----- HEALING -----
        nonperishable_quick_healing = add_event("Nonperishable Healing", {
            helpful = any("Healing Salve", "Honey Poultice", "Bat Bat"),
        }),
        quick_healing = add_event("Quick Healing", {
            helpful = is_character("wormwood") and Event("nonperishable_quick_healing") or any(NoSpreadEvent("cooking"), HiddenEvent("nonperishable_quick_healing")),
            spread = true,
        }),
        slow_healing = add_event("Slow Healing", {
            helpful = any("Tent", "Siesta Lean-to", "Straw Roll"),
        }),
        healing = add_event("Healing", {
            helpful = no_spread(any("Booster Shot", HiddenEvent("quick_healing"), HiddenEvent("slow_healing"))),
        }),
        resurrecting = add_event("Resurrecting", {
            default = any("Life Giving Amulet", "Meat Effigy"),
        }),


        ----- SURVIVAL -----
        basic_survival = add_event("Basic Survival", {
            hidden  = true,
        }),
        winter_survival = add_event("Can Survive Winter", {
            default = any(Event("firestarting"), "Campfire", "Fire Pit"),
            helpful = any("Thermal Stone", "Rabbit Earmuffs", "Puffy Vest", "Breezy Vest", "Beefalo Hat", "Winter Hat", "Cat Cap"),
            hidden = true,
        }),
        electric_insulation = add_event("Electric Insulation", {
            default = any("Rain Coat", "Rain Hat", "Eyebrella"),
            helpful = "Hammer",
        }),
        rain_protection = add_event("Rain Protection", {
            default = any("Rain Coat", "Rain Hat", "Eyebrella", "Umbrella"),
            helpful = "Hammer",
        }),
        lightning_rod = add_event("Lightning Rod", {
            default = self_reference(),
            hard    = all("Lightning Conductor", "Mast Kit"),
            spread  = false,
        }),
        spring_survival = add_event("Can Survive Spring", {
            helpful = all(Event("rain_protection"), Event("lightning_rod")),
            hard    = ALWAYS_TRUE,
            hidden = true,
        }),
        cooling_source = add_event("Cooling Source", {
            default = any(all("Thermal Stone", "Ice Box"), "Endothermic Fire", "Chilled Amulet", "Endothermic Fire Pit"),
            spread  = false,
        }),
        summer_insulation = add_event("Summer Insulation", {
            default = any("Umbrella", "Summer Frest", "Thermal Stone", "Floral Shirt", "Eyebrella"),
        }),
        fire_suppression = add_event("Fire Suppression", {
            default = any("Ice Flingomatic", "Luxury Fan", "Empty Watering Can"),
        }),
        summer_survival = add_event("Can Survive Summer", {
            helpful = all(Event("cooling_source"), Event("summer_insulation"), Event("fire_suppression")),
            hard    = ALWAYS_TRUE,
            hidden = true,
        }),


        ----- BASE MAKING -----
        base_making = add_event("Base Making", {
            default = all("Boards", "Cut Stone", "Electrical Doodad", "Rope", Event("any_axe"), Event("any_pickaxe")),
            hidden  = true,
        }),
        beefalo_domestication = add_event("Beefalo Domestication", {
            default = "Saddle",
            helpful = any("Beefalo Hat", "Beefalo Bell"),
        }),
        heavy_lifting = add_event("Heavy Lifting", {
            default = any(
                is_character("walter") and "Walter" or ALWAYS_FALSE,
                is_character("wolfgang") and "Wolfgang" or ALWAYS_FALSE,
                is_character("wanda") and all("Wanda", Event("winter"), "Purple Gem") or ALWAYS_FALSE,
                not(is_character("walter") or is_character("wolfgang")) and Event("beefalo_domestication") or ALWAYS_FALSE
            ),
            helpful = Event("beefalo_domestication")
        }),
        arena_building = add_event("Arena Building", {
            default = all(any("Floorings", "Wurt"), any("Pitchfork", "Snazzy Pitchfork", "Turf-Raiser Helm")),
        }),
        walls = add_event("Walls", {
            default = "Stone Wall",
            hard    = "Thulecite Wall",
        }),


        ----- EXPLORATION -----
        basic_exploration = add_event("Basic Exploration", {
            helpful = all("Torch", "Campfire", Event("basic_survival"), "Backpack", Event("any_axe"), Event("any_pickaxe")),
            hidden = true,
            spread = false,
        }),
        desert = add_event("Desert", {
            helpful = Event("basic_survival"),
        }),
        swamp = add_event("Swamp", {
            helpful = Event("basic_survival"),
        }),
        speed_boost = add_event("Speed Boost", {
            default = any("Walking Cane", "Magiluminescence"),
            hidden = true,
        }),
        light_source = add_event("Light Source", {
            default = any("Lantern", all("Miner Hat", "Bug Net", "Straw Hat"), "Morning Star"),
            hard    = "Torch",
            spread  = false,
        }),
        cave_exploration = REGION.CAVE and add_event("Cave Exploration", {
            default = all(Event("any_pickaxe"), Event("light_source")),
            helpful = (SEASON.WINTER or SEASON.SPRING) and all("Backpack", any(Event("autumn"), Event("summer"),  NoSpreadEvent("rain_protection"))) or "Backpack",
        }),
        ruins_exploration = REGION.RUINS and add_event("Ruins Exploration", {
            default = all(Event("cave_exploration"), HiddenEvent("basic_combat")),
            helpful = all(Event("advanced_combat"), NoSpreadEvent("healing")),
            hard    = Event("cave_exploration"),
        }),
        basic_boating = REGION.OCEAN and add_event("Basic Boating", {
            default = all("Boat Kit", "Oar"),
            helpful = all(Event("basic_exploration", "Grass Raft Kit", "Boat Patch", "Driftwood Oar")),
            hard    = all(any("Grass Raft Kit", "Boat Kit"), any("Oar", "Driftwood Oar")),
            spread = false,
        }),
        advanced_boating = REGION.OCEAN and add_event("Advanced Boating", {
            default = all("Driftwood Oar", HiddenEvent("basic_boating"), Event("light_source")),
            hard    = Event("basic_boating"),
            helpful = all("Anchor Kit", "Steering Wheel Kit", "Mast Kit"),
            spread = false,
        }),
        can_reach_islands = REGION.OCEAN and add_event("Can Reach Islands", {
            default = Event("basic_boating"),
            helpful = Event("advanced_boating"),
            hard    = "Telelocator Staff",
        }),
        lunar_island = REGION.OCEAN and add_event("Lunar Island", {
            default = Event("can_reach_islands"),
        }),
        hermit_island = REGION.OCEAN and add_event("Hermit Island", {
            default = all(Event("base_making"), Event("can_reach_islands")),
        }),
        hermit_sea_quests = REGION.OCEAN and add_event("Hermit Sea Quests", {
            default = all(Event("sea_fishing"), Event("advanced_boating"), "Pinchin' Winch"),
        }),
        hermit_home_upgrades = REGION.OCEAN and add_event("Hermit Home Upgrades", {
            default = noop(all("Bug Net", "Floorings", stringhint("lightbulb"), stringhint("fireflies"), stringhint("marble"), stringhint("moonrocknugget"), stringhint("cookiecuttershell"))),
        }),
        hermit_island_items = REGION.OCEAN and add_event("Hermit Island Items", {
            helpful = all(Event("any_shovel"), Event("seasons_passed_2"), "Sawhorse", any("Umbrella", "Pretty Parasol"), any("Breezy Vest", "Puffy Vest"), Event("cooking")),
            hidden = true,
        }),
        ancient_archive = REGION.ARCHIVE and add_event("Ancient Archive", {
            default = Event("iridescent_gem"),
        }),
        storm_protection = add_event("Storm Protection", {
            default = any(all("Fashion Goggles", "Desert Goggles"), "Astroggles"),
        }),
        moonstorm = REGION.MOONSTORM and add_event("Moonstorm", {
            default = all(Event("unite_celestial_altars"), NoSpreadEvent("storm_protection"), NoSpreadEvent("electric_insulation")),
            helpful = "Astroggles",
        }),
        moon_quay = REGION.MOONQUAY and add_event("Moon Quay", {
            default = Event("can_reach_islands"),
            helpful = stringhint("cave_banana"),
        }),
        pirate_map = REGION.MOONQUAY and add_event("Pirate Map", {
            default = all(Event("basic_boating"), Event("moon_quay")),
            helpful = any("Cannon Kit", "Hostile Flare"),
        }),
        sunken_chest = REGION.OCEAN and add_event("Sunken Chest", {
            default = all("Pinchin' Winch", Event("advanced_boating"), "Hammer"),
        }),


        ----- FARMING -----
        basic_farming = add_event("Basic Farming", {
            default = any("Wormwood", all(Event("any_hoe"), "Garden Digamajig")),
        }),
        advanced_farming = add_event("Advanced Farming", {
            default = all(Event("any_hoe"), "Garden Digamajig", "Empty Watering Can", Event("any_shovel")),
        }),
        asparagus_farming = add_farming_event("Asparagus"),
        garlic_farming = add_farming_event("Garlic"),
        pumpkin_farming = add_farming_event("Pumpkin"),
        corn_farming = add_farming_event("Corn",
            REGION.OCEAN and hard(all(Event("basic_farming"), Event("bird_caging"), Event("sea_fishing"))) or nil -- Corn cod
        ),
        onion_farming = add_farming_event("Onion"),
        potato_farming = add_farming_event("Potato",
            hard(all(Event("basic_farming"), Event("bird_caging"))) -- Junk pile
        ),
        dragonfruit_farming = add_farming_event("Dragon Fruit",
            REGION.OCEAN and hard(all(Event("basic_farming"), Event("dragonfruit_from_saladmander"), Event("bird_caging"))) or nil
        ),
        pomegranate_farming = add_farming_event("Pomegranate"),
        eggplant_farming = add_farming_event("Eggplant"),
        tomaroot_farming = add_farming_event("Toma Root",
            hard(Event("basic_farming")) -- Catcoons
        ),
        watermelon_farming = add_farming_event("Watermelon"),
        pepper_farming = add_farming_event("Pepper"),
        durian_farming = add_farming_event("Durian"),
        carrot_farming = add_farming_event("Carrot", 
            all(Event("basic_farming"), Event("bird_caging"))
        ),
        honey_farming = add_event("Honey", {
            default = ALWAYS_TRUE,
            helpful = all("Bee Box", "Bug Net"),
        }),


        ----- COOKING -----
        cooking = add_event("Cooking", {
            default = is_character("warly") and "Warly" or "Crock Pot",
        }),
        fruits = add_event("Fruits", {
            default = any(Event("pomegranate_farming"), Event("watermelon_farming"), Event("durian_farming")),
            hard    = REGION.RUINS and Event("ruins_exploration") or nil,
        }),
        dragonfruit_from_saladmander = REGION.OCEAN and add_event("Dragon Fruit from Saladmander", {
            default = all(Event("lunar_island"), Event("basic_combat"), "Bath Bomb"),
        }),
        dairy = add_event("Dairy", {
            default = any(Event("eye_of_terror"), all(any("Morning Star", "Electric Dart"), stringhint("lightninggoat"), Event("electric_insulation"))),
            hard = any("Morning Star", "Electric Dart"),
            helpful = Event("Butter"),
        }),


        ----- FISHING -----
        freshwater_fishing = add_event("Freshwater Fishing", {
            default = any(all("Freshwater Fishing Rod", any(Event("autumn"), Event("spring"), Event("summer"), NoSpreadEvent("cave_exploration"))), stringhint("merm")),
        }),
        sea_fishing = REGION.OCEAN and add_event("Sea Fishing", {
            default = all(HiddenEvent("basic_boating"), any("Ocean Trawler Kit", "Sea Fishing Rod")),
        }),
        fishing = add_event("Fishing", {
            default = any(Event("freshwater_fishing"), Event("sea_fishing")),
            hard    = ALWAYS_TRUE,
            hidden  = true,
        }),


        ----- KEY ITEMS -----
        celestial_sanctum_pieces = REGION.MOONSTORM and add_event("Celestial Sanctum Pieces", {
            default = "Astral Detector",
            helpful = Event("heavy_lifting"),
        }),
        moon_stone_event = add_event("Moon Stone Event", {
            default = all(Event("full_moon"), Event("walls"), Event("ruins_gems"), "Star Caller's Staff", Event("living_log")),
        }),
        iridescent_gem = add_event("Iridescent Gem", {
            default = any("Iridescent Gem", all(NoSpreadEvent("mooncaller_staff"), Event("deconstruction_staff"))),
        }),
        unite_celestial_altars = REGION.MOONSTORM and add_event("Unite Celestial Altars", {
            default = all(NoSpreadEvent("lunar_island"), Event("celestial_sanctum_pieces"), Event("inactive_celestial_tribute"), "Pinchin' Winch")
        }),
        inactive_celestial_tribute = REGION.OCEAN and add_event("Inactive Celestial Tribute", {
            default =  NoSpreadEvent("crab_king"),
        }),
        shadow_atrium = add_event("Shadow Atrium", {
            default =  NoSpreadEvent("shadow_pieces"),
            helpful = all("Bishop Figure Sketch", "Rook Figure Sketch", "Knight Figure Sketch"),
        }),
        ancient_key = REGION.RUINS and add_event("Ancient Key", {
            default =  NoSpreadEvent("ancient_guardian"),
        }),


        ----- CRAFTING STATIONS -----
        science_machine = add_event("Science Machine", {
            default = all(Event("basic_survival"), Event("any_axe"), Event("any_pickaxe")),
        }),
        alchemy_engine = add_event("Alchemy Engine", {
            default = all(NoSpreadEvent("science_machine"), "Cut Stone", "Boards", "Electrical Doodad"),
        }),
        prestihatitor = add_event("Prestihatitor", {
            default = all("Top Hat", "Boards", NoSpreadEvent("science_machine"), "Trap", NoSpreadEvent("rabbit")),
        }),
        shadow_manipulator = add_event("Shadow Manipulator", {
            default = all("Purple Gem", "Nightmare Fuel", Event("living_log"),  NoSpreadEvent("prestihatitor")),
        }),
        think_tank = add_event("Think Tank", {
            default = all("Boards", NoSpreadEvent("science_machine")),
        }),
        ancient_altar = add_event("Ancient Pseudoscience Station", {
            default = Event("ruins_exploration"),
        }),
        celestial_orb = add_event("Celestial Orb", {
            default = all(Event("basic_survival"), Event("any_pickaxe"), Event("moonrockseed_exists")),
        }),
        celestial_altar = REGION.OCEAN and add_event("Celestial Altar", {
            default = all(Event("lunar_island"), Event("any_pickaxe")),
        }),


        ----- CRABBY HERMIT -----
        crabby_hermit_friendship = REGION.OCEAN and add_event("Crabby Hermit Friendship", {
            default = Event("hermit_island"),
            helpful = all(
                Event("hermit_home_upgrades"), 
                Event("hermit_island_items"), 
                Event("hermit_sea_quests")
            ),
        }),

        ----- BOSSES -----
        crab_king = REGION.OCEAN and add_event("Crab King", {
            default = all(
                Event("advanced_boating"), 
                Event("advanced_boss_combat")
            ),
            helpful = Event("crabby_hermit_friendship"),
            comment = "Befriend Crabby Hermit to obtain the Inactive Celestial Tribute",
        }),
        shadow_pieces = PHASE.NIGHT and add_event("Shadow Pieces", {
            default = all(Event("advanced_boss_combat"),  "Potter's Wheel"),
            helpful = Event("heavy_lifting"),
        }),
        ancient_guardian = REGION.RUINS and add_event("Ancient Guardian", {
            default = all(Event("ruins_exploration"), Event("advanced_boss_combat")),
        }),
        deerclops = SEASON.WINTER and add_event("Deerclops", {
            default = all(Event("basic_combat"), Event("winter")),
            helpful = "Hostile Flare",
        }),
        moosegoose = SEASON.SPRING and add_event("Moose/Goose", {
            default = all(Event("basic_combat"), Event("spring")),
        }),
        antlion = SEASON.SUMMER and add_event("Antlion", {
            default = any(
                all(Event("summer"), "Freshwater Fishing Rod", "Fashion Goggles", "Desert Goggles"), -- Affects chance of fishing beach toy
                all(Event("summer"), Event("advanced_boss_combat"), "Thermal Stone", Event("storm_protection"))
            ),
            helpful = stringhint("antliontrinket"),
        }),
        bearger = SEASON.AUTUMN and add_event("Bearger", {
            default =  all(Event("basic_combat"), Event("autumn")),
        }),
        dragonfly = add_event("Dragonfly", {
            default = all(Event("advanced_boss_combat"), Event("walls")),
        }),
        bee_queen = add_event("Bee Queen", {
            default = all(Event("epic_combat"), "Hammer"),
            helpful = all("Beekeeper Hat"),
            comment = "Hard to solo even with a high damage multiplier. A full team or a creative strategy is recommended."
        }),
        klaus = SEASON.WINTER and add_event("Klaus", {
            default = all(Event("advanced_boss_combat"), Event("winter"), stringhint("deer_antler")),
            comment = "Killing the deer is not recommended.",
        }),
        malbatross = REGION.OCEAN and add_event("Malbatross", {
            default = all(Event("advanced_boss_combat"), Event("advanced_boating")),
            helpful = "Sea Fishing Rod",
        }),
        toadstool = REGION.CAVE and add_event("Toadstool", {
            default = all(Event("basic_combat"), Event("nonperishable_quick_healing"), Event("cave_exploration")),
            helpful = any("Moon Glass Axe", "Pick/Axe", "Weather Pain", "Fire Staff", "Dark Sword", "Glass Cutter"),
        }),
        ancient_fuelweaver = REGION.RUINS and PHASE.NIGHT and add_event("Ancient Fuelweaver", {
            default = all(Event("shadow_atrium"), Event("ancient_key"), Event("advanced_boss_combat"), stringhint("fossil_piece")),
            helpful = any(Event("dark_magic"), "Nightmare Amulet", "The Lazy Explorer", "Wortox", "Wendy", "Weather Pain"),
        }),
        lord_of_the_fruit_flies = add_event("Lord of the Fruit Flies", {
            default = all(Event("basic_combat"), Event("advanced_farming")),
        }),
        celestial_champion = REGION.MOONSTORM and add_event("Celestial Champion", {
            default = all("Incomplete Experiment", NoSpreadEvent("celestial_orb"), Event("moonstorm"), Event("epic_combat")),
            helpful = Event("ranged_combat"),
        }),
        eye_of_terror = PHASE.NIGHT and add_event("Eye Of Terror", {
            default = all(Event("advanced_boss_combat"), stringhint("terrarium")),
            hard    = Event("basic_combat"),
        }),
        twins_of_terror = PHASE.NIGHT and add_event("Spazmatism and Retinazor", {
            default = all(Event("epic_combat"), stringhint("terrarium"), "Nightmare Fuel"),
        }),
        nightmare_werepig = REGION.CAVE and add_event("Nightmare Werepig", {
            default = all(Event("advanced_boss_combat"), Event("cave_exploration"), "Pick/Axe"),
            helpful = Event("speed_boost"),
        }),
        scrappy_werepig = REGION.CAVE and add_event("Scrappy Werepig", {
            default = Event("nightmare_werepig"),
            helpful = Event("arena_building"),
        }),
        frostjaw = REGION.OCEAN and add_event("Frostjaw", {
            default = all(Event("advanced_boating"), Event("advanced_boss_combat"), "Sea Fishing Rod"),
            helpful = Event("speed_boost"),
        }),
    }
    for _,v in ipairs({"moonrockseed", "grassgekko", "lureplant"}) do
        self.EVENTS[v.."_exists"] = add_exist_event(v)
    end
    
    -- print("----- Events have been defined -----")

    HAS_ITEM = {}
    CAN_CRAFT = {}
    PRETTYNAME_ITEM_INGREDIENTS = {}
    for id, item in pairs(ArchipelagoDST.ID_TO_ITEM) do
        local istrue = ArchipelagoDST.collecteditems[id] or (ArchipelagoDST.lockableitems[id] ~= true)
        if item and (istrue or ITEM_ADDITIONAL_RULE[id]) then
            self:SetIsCraftable(item.prefab, "default")
            self:SetIsCraftable(item.prefab, "hard")
        end
    end
    
    _unsafe_rules = false
    -- print("----- Craftables have been defined -----")

    self.location_rules = {
        -- Tasks
        ["Distilled Knowledge (Yellow)"] =      Event("ancient_archive"),
        ["Distilled Knowledge (Blue)"] =        Event("ancient_archive"),
        ["Distilled Knowledge (Red)"] =         Event("ancient_archive"),
        ["Wagstaff during Moonstorm"] =         Event("moonstorm"),
        ["Queen of Moon Quay"] =                Event("moon_quay"),
        ["Pig King"] =                          Event("basic_survival"),
        ["Chester"] =                           Event("basic_survival"),
        ["Hutch"] =                             Event("cave_exploration"),
        ["Stagehand"] =                         all(Event("basic_survival"), "Hammer"),
        ["Pirate Stash"] =                      all(Event("pirate_map"), Event("any_shovel")),
        ["Moon Stone Event"] =                  Event("moon_stone_event"),
        ["Oasis"] =                             "Freshwater Fishing Rod",
        ["Poison Birchnut Tree"] =              Event("any_axe"),
        ["W.O.B.O.T."] =                        any(NoSpreadEvent("scrappy_werepig"), "Auto-Mat-O-Chanic"),
        ["Friendly Fruit Fly"] =                Event("lord_of_the_fruit_flies"),

        -- Bosses
        ["Deerclops"] =                         Event("deerclops"),
        ["Moose/Goose"] =                       Event("moosegoose"),
        ["Antlion"] =                           Event("antlion"),
        ["Bearger"] =                           Event("bearger"),
        ["Ancient Guardian"] =                  Event("ancient_guardian"),
        ["Dragonfly"] =                         Event("dragonfly"),
        ["Bee Queen"] =                         Event("bee_queen"),
        ["Crab King"] =                         Event("crab_king"),
        ["Klaus"] =                             Event("klaus"),
        ["Malbatross"] =                        Event("malbatross"),
        ["Toadstool"] =                         Event("toadstool"),
        ["Shadow Knight"] =                     all(Event("shadow_pieces"), helpful("Knight Figure Sketch")),
        ["Shadow Bishop"] =                     all(Event("shadow_pieces"), helpful("Bishop Figure Sketch")),
        ["Shadow Rook"] =                       all(Event("shadow_pieces"), helpful("Rook Figure Sketch")),
        ["Ancient Fuelweaver"] =                Event("ancient_fuelweaver"),
        ["Lord of the Fruit Flies"] =           Event("lord_of_the_fruit_flies"),
        ["Celestial Champion"] =                Event("celestial_champion"),
        ["Eye Of Terror"] =                     Event("eye_of_terror"),
        ["Retinazor"] =                         Event("twins_of_terror"),
        ["Spazmatism"] =                        Event("twins_of_terror"),
        ["Nightmare Werepig"] =                 Event("nightmare_werepig"),
        ["Scrappy Werepig"] =                   Event("scrappy_werepig"),
        ["Frostjaw"] =                          Event("frostjaw"),

        -- Creatures
        ["Batilisk"] =                          Event("batilisk"),
        ["Bee"] =                               any(Event("pre_basic_combat"), "Bug Net"),
        ["Beefalo"] =                           any(Event("autumn"), Event("winter"), Event("summer"), Event("basic_combat")),
        ["Clockwork Bishop"] =                  all(Event("advanced_combat"), Event("healing"), helpful(Event("ruins_exploration"))),
        ["Bunnyman"] =                          all(Event("cave_exploration"), helpful(stringhint("carrot"))),
        ["Butterfly"] =                         Event("butterfly"),
        ["Buzzard"] =                           Event("basic_combat"),
        ["Canary"] =                            all(Event("canary"), Event("feathers")),
        ["Carrat"] =                            any(Event("lunar_island"), Event("cave_exploration")),
        ["Catcoon"] =                           Event("basic_survival"),
        ["Cookie Cutter"] =                     Event("advanced_boating"),
        ["Crawling Horror"] =                   Event("advanced_combat"),
        ["Crow"] =                              Event("feathers"),
        ["Red Hound"] =                         Event("basic_combat"),
        ["Frog"] =                              ALWAYS_TRUE,
        ["Saladmander"] =                       Event("lunar_island"),
        ["Ghost"] =                             all(Event("basic_exploration"), Event("any_shovel"), Event("pre_basic_combat")),
        ["Gnarwail"] =                          all(Event("basic_combat"), Event("advanced_boating")),
        ["Grass Gator"] =                       all(Event("basic_combat"), Event("advanced_boating"), Event("ranged_aggression")),
        ["Grass Gekko"] =                       all(
                                                    Event("pre_basic_combat"),
                                                    any(
                                                        Event("grassgekko_exists"),
                                                        no_spread(all(Event("seasons_passed_2"), Event("any_shovel"), any(Event("autumn"), Event("spring"), Event("summer"))))
                                                    ),
                                                    helpful(Event("any_shovel"))
                                                ),
        ["Briar Wolf"] =                        Event("basic_combat"),
        ["Hound"] =                             all(Event("basic_combat"), Event("desert")),
        ["Blue Hound"] =                        all(Event("basic_combat"), any(Event("winter"), all(Event("spring"), Event("seasons_passed_2")))),
        ["Killer Bee"] =                        any(Event("pre_basic_combat"), "Bug Net"),
        ["Clockwork Knight"] =                  all(Event("advanced_combat"), helpful(Event("ruins_exploration"))),
        ["Koalefant"] =                         all(Event("pre_basic_combat"), Event("ranged_aggression")),
        ["Krampus"] =                           all(Event("basic_combat"), helpful(Event("feathers"))),
        ["Treeguard"] =                         all(Event("basic_combat"), Event("any_axe"), Event("basic_survival")),
        ["Crustashine"] =                       all(Event("moon_quay"), Event("ranged_aggression")),
        ["Bulbous Lightbug"] =                  Event("cave_exploration"),
        ["Volt Goat"] =                         all(Event("basic_combat"), Event("ranged_aggression"), Event("desert")),
        ["Merm"] =                              all(Event("basic_combat"), Event("swamp"), Event("merm_exists")),
        ["Moleworm"] =                          any(Event("dusk"), Event("night"), HiddenEvent("any_shovel")),
        ["Naked Mole Bat"] =                    all(Event("basic_combat"), Event("cave_exploration")),
        ["Splumonkey"] =                        Event("ruins_exploration"),
        ["Moon Moth"] =                         all(Event("can_reach_islands"), Event("any_axe")),
        ["Mosquito"] =                          all(Event("swamp"), any(Event("pre_basic_combat"), "Bug Net")),
        ["Mosling"] =                           Event("moosegoose"),
        ["Mush Gnome"] =                        all(Event("basic_combat"), Event("cave_exploration")),
        ["Terrorclaw"] =                        all(Event("advanced_combat"), Event("advanced_boating")),
        ["Pengull"] =                           Event("basic_combat"),
        ["Gobbler"] =                           Event("basic_survival"),
        ["Pig Man"] =                           all(Event("basic_survival"), no_spread(any(Event("day"), "Hammer", "Deconstruction Staff"))),
        ["Powder Monkey"] =                     all(helpful("Cannon Kit"), Event("moon_quay")),
        ["Prime Mate"] =                        Event("pirate_map"),
        ["Puffin"] =                            all(Event("feathers"), Event("basic_boating")),
        ["Rabbit"] =                            Event("rabbit"),
        ["Redbird"] =                           Event("feathers"),
        ["Snowbird"] =                          Event("feathers"),
        ["Rock Lobster"] =                      all(Event("cave_exploration"), helpful(stringhint("rocks"))),
        ["Clockwork Rook"] =                    all(Event("advanced_combat"), Event("healing"), helpful(Event("ruins_exploration"))),
        ["Rockjaw"] =                           all(Event("advanced_combat"), Event("advanced_boating")),
        ["Slurper"] =                           Event("ruins_exploration"),
        ["Slurtle"] =                           all(Event("cave_exploration"), helpful("Torch")),
        ["Snurtle"] =                           all(Event("cave_exploration"), helpful("Torch")),
        ["Ewecus"] =                            Event("advanced_combat"),
        ["Spider"] =                            ALWAYS_TRUE,
        ["Dangling Depth Dweller"] =            all(any(Event("basic_combat"), "Trap", "Webber"), Event("cave_exploration")),
        ["Cave Spider"] =                       all(any(Event("basic_combat"), "Trap", "Webber"), Event("cave_exploration")),
        ["Nurse Spider"] =                      all(any(Event("advanced_combat"), "Webber"), helpful("Trap")),
        ["Shattered Spider"] =                  all(any(Event("basic_combat"), "Trap", "Webber"), Event("lunar_island")),
        ["Spitter"] =                           all(any(Event("basic_combat"), "Trap", "Webber"), Event("cave_exploration")),
        ["Spider Warrior"] =                    any(Event("basic_combat"), "Trap", "Webber"),
        ["Sea Strider"] =                       all(any(Event("basic_combat"), "Trap", "Webber"), Event("advanced_boating")),
        ["Spider Queen"] =                      all(Event("advanced_combat"), helpful(any("Trap", "Webber"))),
        ["Tallbird"] =                          all(Event("basic_combat"), Event("healing")),
        ["Tentacle"] =                          all(Event("basic_combat"), Event("swamp")),
        ["Big Tentacle"] =                      all(Event("advanced_combat"), Event("cave_exploration"), Event("healing")),
        ["Terrorbeak"] =                        Event("advanced_combat"),
        ["MacTusk"] =                           Event("basic_combat"),
        ["Varg"] =                              Event("advanced_combat"),
        ["Varglet"] =                           Event("basic_combat"),
        ["Depths Worm"] =                       Event("ruins_exploration"),
        ["Ancient Sentrypede"] =                all(Event("ancient_archive"), Event("advanced_combat")),
        ["Skittersquid"] =                      all(Event("basic_combat"), Event("advanced_boating")),
        ["Lure Plant"] =                        all(Event("lureplant_exists"), Event("pre_basic_combat")),
        ["Glommer"] =                           Event("full_moon"),
        ["Dust Moth"] =                         Event("ancient_archive"),
        ["No-Eyed Deer"] =                      Event("basic_survival"),
        ["Moonblind Crow"] =                    all(Event("moonstorm"), Event("basic_combat")),
        ["Misshapen Bird"] =                    all(Event("moonstorm"), Event("basic_combat")),
        ["Moonrock Pengull"] =                  all(Event("lunar_island"), Event("basic_combat")),
        ["Horror Hound"] =                      all(any(Event("moonstorm"), hard(Event("lunar_island"))), Event("basic_combat")),
        ["Resting Horror"] =                    Event("ruins_exploration"),
        ["Birchnutter"] =                       Event("any_axe"),
        ["Mandrake"] =                          Event("basic_survival"),
        ["Fruit Fly"] =                         Event("basic_farming"),
        ["Sea Weed"] =                          all(Event("advanced_boating"), helpful(any("Razor", Event("basic_combat"), Event("night")))),
        ["Marotter"] =                          Event("basic_combat"),

        -- Cook foods
        ["Butter Muffin"] =                     cookrecipe(any(Event("butterfly"), hard(all(Event("can_reach_islands"), Event("any_axe"), stringhint("moonbutterfly")))), {"butterflywings", "carrot", "twigs", "twigs"}),
        ["Froggle Bunwich"] =                   cookrecipe(ALWAYS_TRUE, {"froglegs", "carrot", "twigs", "twigs"}),
        ["Taffy"] =                             cookrecipe(Event("honey_farming"), {"honey", "honey", "honey", "twigs"}),
        ["Pumpkin Cookies"] =                   cookrecipe(all(Event("honey_farming"), Event("pumpkin_farming")), {"pumpkin", "honey", "honey", "twigs"}),
        ["Stuffed Eggplant"] =                  cookrecipe(Event("eggplant_farming"), {"eggplant", "carrot", "twigs", "twigs"}),
        ["Fishsticks"] =                        cookrecipe(Event("fishing"), {"fishmeat_small", "berries", "berries", "twigs"}),
        ["Honey Nuggets"] =                     cookrecipe(Event("honey_farming"), {"honey", "smallmeat", "berries", "berries"}),
        ["Honey Ham"] =                         cookrecipe(Event("honey_farming"), {"honey", "meat", "meat", "berries"}),
        ["Dragonpie"] =                         cookrecipe(any(Event("dragonfruit_from_saladmander"), Event("dragonfruit_farming")), {"dragonfruit", "twigs", "twigs", "twigs"}),
        ["Kabobs"] =                            cookrecipe(ALWAYS_TRUE, {"smallmeat", "berries", "berries", "twigs"}),
        ["Mandrake Soup"] =                     cookrecipe(ALWAYS_TRUE, {"mandrake", "twigs", "twigs", "twigs"}),
        ["Bacon and Eggs"] =                    cookrecipe(Event("any_eggs"), {"meat", "smallmeat", "bird_egg", "bird_egg"}),
        ["Meatballs"] =                         cookrecipe(ALWAYS_TRUE, {"smallmeat", "berries", "berries", "berries"}),
        ["Meaty Stew"] =                        cookrecipe(ALWAYS_TRUE, {"meat", "meat", "meat", "berries"}),
        ["Pierogi"] =                           cookrecipe(Event("any_eggs"), {"smallmeat", "carrot", "carrot", "bird_egg"}),
        ["Turkey Dinner"] =                     cookrecipe(Event("pre_basic_combat"), {"drumstick", "drumstick", "smallmeat", "berries"}),
        ["Ratatouille"] =                       cookrecipe(ALWAYS_TRUE, {"carrot", "carrot", "carrot", "carrot"}),
        ["Fist Full of Jam"] =                  cookrecipe(ALWAYS_TRUE, {"berries", "berries", "berries", "berries"}),
        ["Fruit Medley"] =                      cookrecipe(Event("fruits"), {"watermelon", "watermelon", "watermelon", "twigs"}),
        ["Fish Tacos"] =                        cookrecipe(any(Event("sea_fishing"), Event("corn_farming")), {"corn", "fishmeat_small", "twigs", "twigs"}),
        ["Waffles"] =                           cookrecipe(all(Event("any_eggs"), Event("butter")), {"butter", "berries", "berries", "bird_egg"}),
        ["Monster Lasagna"] =                   cookrecipe(all("Crock Pot", Event("pre_basic_combat")), {"monstermeat", "monstermeat", "berries", "berries"}), -- Need basic crock pot, not portable
        ["Powdercake"] =                        cookrecipe(all(Event("honey_farming"), any(hard(Event("sea_fishing")), Event("corn_farming"))), {"corn", "honey", "twigs", "twigs"}),
        ["Unagi"] =                             cookrecipe(all(Event("cave_exploration"), "Freshwater Fishing Rod"), {"eel", "cutlichen", "cutlichen", "cutlichen"}),
        ["Wet Goop"] =                          cookrecipe(ALWAYS_TRUE, {"twigs", "twigs", "twigs", "monstermeat"}),
        ["Flower Salad"] =                      cookrecipe(ALWAYS_TRUE, {"cactus_flower", "carrot", "carrot", "carrot"}),
        ["Ice Cream"] =                         cookrecipe(all(Event("honey_farming"), Event("dairy")), {"ice", "milkywhites", "honey", "berries"}),
        ["Melonsicle"] =                        cookrecipe(Event("watermelon_farming"), {"watermelon", "ice", "twigs", "twigs"}),
        ["Trail Mix"] =                         cookrecipe(Event("any_axe"), {"acorn", "berries", "berries", "twigs"}),
        ["Spicy Chili"] =                       cookrecipe(ALWAYS_TRUE, {"meat", "smallmeat", "carrot", "carrot"}),
        ["Guacamole"] =                         cookrecipe(Event("moleworm"), {"mole", "cactus_meat", "twigs", "twigs"}),
        ["Jellybeans"] =                        cookrecipe(Event("bee_queen"), {"royal_jelly", "berries", "berries", "berries"}),
        ["Fancy Spiralled Tubers"] =            cookrecipe(Event("potato_farming"), {"potato", "berries", "twigs", "twigs"}),
        ["Creamy Potato Purée"] =               cookrecipe(all(Event("potato_farming"), Event("garlic_farming")), {"potato", "potato", "garlic", "berries"}),
        ["Asparagus Soup"] =                    cookrecipe(Event("asparagus_farming"), {"asparagus", "carrot", "carrot", "carrot"}),
        ["Vegetable Stinger"] =                 cookrecipe(any(Event("tomaroot_farming"), Event("asparagus_farming")), {"tomato", "ice", "carrot", "carrot"}),
        ["Banana Pop"] =                        cookrecipe(any(NoSpreadEvent("cave_exploration"), Event("moon_quay")), {"cave_banana", "ice", "twigs", "twigs"}),
        ["Frozen Banana Daiquiri"] =            cookrecipe(any(NoSpreadEvent("cave_exploration"), Event("moon_quay")), {"cave_banana", "ice", "berries", "berries"}),
        ["Banana Shake"] =                      cookrecipe(any(NoSpreadEvent("cave_exploration"), Event("moon_quay")), {"cave_banana", "cave_banana", "twigs", "twigs"}),
        ["Ceviche"] =                           cookrecipe(any(Event("sea_fishing"), REGION.CAVE and all(Event("cave_exploration"), "Freshwater Fishing Rod")), {"ice", REGION.OCEAN and "fishmeat" or "eel", "fishmeat_small", "fishmeat_small"}),
        ["Salsa Fresca"] =                      cookrecipe(all(Event("tomaroot_farming"), Event("onion_farming")), {"tomato", "onion", "berries", "berries"}),
        ["Stuffed Pepper Poppers"] =            cookrecipe(Event("pepper_farming"), {"pepper", "smallmeat", "berries", "berries"}),
        ["California Roll"] =                   cookrecipe(Event("sea_fishing"), {"kelp", "kelp", "fishmeat_small", "fishmeat_small"}),
        ["Seafood Gumbo"] =                     cookrecipe(all(Event("cave_exploration"), "Freshwater Fishing Rod"), {"eel", "fishmeat_small", "fishmeat_small", "fishmeat_small"}),
        ["Surf 'n' Turf"] =                     cookrecipe(Event("fishing"), {"meat", "fishmeat_small", "fishmeat_small", "fishmeat_small"}),
        ["Lobster Bisque"] =                    cookrecipe(Event("sea_fishing"), {"wobster_sheller_land", "ice", "twigs", "twigs"}),
        ["Lobster Dinner"] =                    cookrecipe(all(Event("sea_fishing"), Event("butter")), {"wobster_sheller_land", "butter", "twigs", "twigs"}),
        ["Barnacle Pita"] =                     cookrecipe(all(Event("sea_fishing"), "Razor"), {"barnacle", "carrot", "twigs", "twigs"}),
        ["Barnacle Nigiri"] =                   cookrecipe(all(Event("sea_fishing"), "Razor"), {"barnacle", "kelp", "bird_egg", "twigs"}),
        ["Barnacle Linguine"] =                 cookrecipe(all(Event("sea_fishing"), "Razor"), {"barnacle", "barnacle", "carrot", "carrot"}),
        ["Stuffed Fish Heads"] =                cookrecipe(all(Event("sea_fishing"), "Razor"), {"barnacle", "fishmeat_small", "fishmeat_small", "twigs"}),
        ["Leafy Meatloaf"] =                    cookrecipe(Event("leafy_meat"), {"plantmeat", "plantmeat", "twigs", "twigs"}),
        ["Veggie Burger"] =                     cookrecipe(all(Event("leafy_meat"), Event("onion_farming")), {"plantmeat", "onion", "carrot", "twigs"}),
        ["Jelly Salad"] =                       cookrecipe(all(Event("honey_farming"), Event("leafy_meat")), {"plantmeat", "plantmeat", "honey", "honey"}),
        ["Beefy Greens"] =                      cookrecipe(Event("leafy_meat"), {"plantmeat", "carrot", "carrot", "carrot"}),
        ["Mushy Cake"] =                        cookrecipe(Event("cave_exploration"), {"moon_cap", "red_cap", "blue_cap", "green_cap"}),
        ["Soothing Tea"] =                      cookrecipe(Event("basic_farming"), {"forgetmelots", "honey", "ice", "berries"}),
        ["Fig-Stuffed Trunk"] =                 cookrecipe(Event("advanced_boating"), {"fig", "trunk_summer", "twigs", "twigs"}),
        ["Figatoni"] =                          cookrecipe(Event("advanced_boating"), {"fig", "carrot", "carrot", "twigs"}),
        ["Figkabab"] =                          cookrecipe(Event("advanced_boating"), {"fig", "smallmeat", "smallmeat", "twigs"}),
        ["Figgy Frogwich"] =                    cookrecipe(Event("advanced_boating"), {"fig", "froglegs", "twigs", "twigs"}),
        ["Bunny Stew"] =                        cookrecipe(ALWAYS_TRUE, {"smallmeat", "ice", "ice", "berries"}),
        ["Plain Omelette"] =                    cookrecipe(Event("any_eggs"), {"bird_egg", "bird_egg", "bird_egg", "twigs"}),
        ["Breakfast Skillet"] =                 cookrecipe(Event("bird_eggs"), {"bird_egg", "carrot", "twigs", "twigs"}),
        ["Tall Scotch Eggs"] =                  cookrecipe(Event("basic_combat"), {"tallbirdegg", "carrot", "twigs", "twigs"}),
        ["Steamed Twigs"] =                     cookrecipe(ALWAYS_TRUE, {"twigs", "twigs", "twigs", "twigs"}),
        ["Beefalo Treats"] =                    cookrecipe(Event("basic_farming"), {"forgetmelots", "acorn", "twigs", "twigs"}),
        ["Milkmade Hat"] =                      cookrecipe(all(Event("cave_exploration"), Event("basic_boating"), Event("dairy"), Event("basic_combat")), {"batnose", "kelp", "milkywhites", "twigs"}),
        ["Amberosia"] =                         cookrecipe(all(Event("salt_crystals"), "Collected Dust"), {"refined_dust", "twigs", "twigs", "twigs"}),
        ["Stuffed Night Cap"] =                 cookrecipe(Event("cave_exploration"), {"moon_cap", "moon_cap", "monstermeat", "twigs"}),
        -- Warly Dishes
        ["Grim Galette"] =                      cookrecipe(all(Event("potato_farming"), Event("onion_farming")), {"nightmarefuel", "nightmarefuel", "potato", "onion"}),
        ["Volt Goat Chaud-Froid"] =             cookrecipe(Event("basic_combat"), {"lightninggoathorn", "honey", "honey", "twigs"}),
        ["Glow Berry Mousse"] =                 cookrecipe(Event("cave_exploration"), {"wormlight_lesser", "wormlight_lesser", "berries", "berries"}),
        ["Fish Cordon Bleu"] =                  cookrecipe(Event("fishing"), {"froglegs", "froglegs", "fishmeat_small", "fishmeat_small"}),
        ["Hot Dragon Chili Salad"] =            cookrecipe(all(Event("pepper_farming"), any(Event("dragonfruit_from_saladmander"), Event("dragonfruit_farming"))), {"dragonfruit", "pepper", "berries", "berries"}),
        ["Asparagazpacho"] =                    cookrecipe(Event("asparagus_farming"), {"asparagus", "asparagus", "ice", "ice"}),
        ["Puffed Potato Soufflé"] =             cookrecipe(all(Event("any_eggs"), Event("potato_farming")), {"potato", "potato", "bird_egg", "berries"}),
        ["Monster Tartare"] =                   cookrecipe(Event("pre_basic_combat"), {"monstermeat", "monstermeat", "berries", "berries"}),
        ["Fresh Fruit Crepes"] =                cookrecipe(all(Event("fruits"), Event("butter")), {"watermelon", "berries", "butter", "honey"}),
        ["Bone Bouillon"] =                     cookrecipe(all("Hammer", Event("onion_farming")), {"boneshard", "boneshard", "onion", "berries"}),
        ["Moqueca"] =                           cookrecipe(all(Event("fishing"), Event("tomaroot_farming")), {"onion", "tomato", "fishmeat_small", "berries"}),
        -- Farming
        ["Grow Giant Asparagus"] =              all(Event("asparagus_farming"), FARMPLANT_SEASON_RULES["Asparagus"]),
        ["Grow Giant Garlic"] =                 all(Event("garlic_farming"), FARMPLANT_SEASON_RULES["Garlic"]),
        ["Grow Giant Pumpkin"] =                all(Event("pumpkin_farming"), FARMPLANT_SEASON_RULES["Pumpkin"]),
        ["Grow Giant Corn"] =                   all(Event("corn_farming"), FARMPLANT_SEASON_RULES["Corn"]),
        ["Grow Giant Onion"] =                  all(Event("onion_farming"), FARMPLANT_SEASON_RULES["Onion"]),
        ["Grow Giant Potato"] =                 all(Event("potato_farming"), FARMPLANT_SEASON_RULES["Potato"]),
        ["Grow Giant Dragon Fruit"] =           all(Event("dragonfruit_farming"), FARMPLANT_SEASON_RULES["Dragon Fruit"]),
        ["Grow Giant Pomegranate"] =            all(Event("pomegranate_farming"), FARMPLANT_SEASON_RULES["Pomegranate"]),
        ["Grow Giant Eggplant"] =               all(Event("eggplant_farming"), FARMPLANT_SEASON_RULES["Eggplant"]),
        ["Grow Giant Toma Root"] =              all(Event("tomaroot_farming"), FARMPLANT_SEASON_RULES["Toma Root"]),
        ["Grow Giant Watermelon"] =             all(Event("watermelon_farming"), FARMPLANT_SEASON_RULES["Watermelon"]),
        ["Grow Giant Pepper"] =                 all(Event("pepper_farming"), FARMPLANT_SEASON_RULES["Pepper"]),
        ["Grow Giant Durian"] =                 all(Event("durian_farming"), FARMPLANT_SEASON_RULES["Durian"]),
        ["Grow Giant Carrot"] =                 all(Event("carrot_farming"), FARMPLANT_SEASON_RULES["Carrot"]),
        -- Research
        ["Science (Nitre)"] =                   Event("any_pickaxe"),
        ["Science (Salt Crystals)"] =           Event("salt_crystals"),
        ["Science (Ice)"] =                     Event("any_pickaxe"),
        ["Science (Slurtle Slime)"] =           Event("cave_exploration"),
        ["Science (Gears)"] =                   Event("gears"),
        ["Science (Scrap)"] =                   Event("basic_exploration"),
        ["Science (Azure Feather)"] =           Event("feathers"),
        ["Science (Crimson Feather)"] =         Event("feathers"),
        ["Science (Jet Feather)"] =             Event("feathers"),
        ["Science (Saffron Feather)"] =         all(Event("canary"), Event("feathers")),
        ["Science (Kelp Fronds)"] =             Event("basic_boating"),
        ["Science (Steel Wool)"] =              all(Event("advanced_combat"), stringhint("spat")),
        ["Science (Electrical Doodad)"] =       "Electrical Doodad",
        ["Science (Ashes)"] =                   Event("firestarting"),
        ["Science (Cut Grass)"] =               ALWAYS_TRUE,
        ["Science (Beefalo Horn)"] =            all(Event("basic_combat"), stringhint("beefalo")),
        ["Science (Beefalo Wool)"] =            any(all("Razor", any(Event("autumn"), Event("winter"), Event("summer"), Event("basic_combat"))), Event("basic_combat")),
        ["Science (Cactus Flower)"] =           ALWAYS_TRUE,
        ["Science (Honeycomb)"] =               Event("basic_combat"),
        ["Science (Petals)"] =                  ALWAYS_TRUE,
        ["Science (Succulent)"] =               Event("desert"),
        ["Science (Foliage)"] =                 any(Event("any_pickaxe"), Event("desert")),
        ["Science (Tillweeds)"] =               Event("basic_farming"),
        ["Science (Lichen)"] =                  Event("ruins_exploration"),
        ["Science (Banana)"] =                  any(Event("moon_quay"), Event("cave_exploration")),
        ["Science (Fig)"] =                     Event("advanced_boating"),
        ["Science (Tallbird Egg)"] =            Event("basic_combat"),
        ["Science (Hound's Tooth)"] =           all(Event("basic_combat"), stringhint("hound")),
        ["Science (Bone Shards)"] =             all(Event("desert"), "Hammer"),
        ["Science (Walrus Tusk)"] =             all(Event("basic_combat"), stringhint("walrus")),
        ["Science (Silk)"] =                    stringhint("spider"),
        ["Science (Cut Stone)"] =               "Cut Stone",
        ["Science (Palmcone Sprout)"] =         Event("moon_quay"),
        ["Science (Pine Cone)"] =               Event("any_axe"),
        ["Science (Birchnut)"] =                Event("any_axe"),
        ["Science (Driftwood Piece)"] =         Event("basic_boating"),
        ["Science (Cookie Cutter Shell)"] =     all(Event("basic_boating"), Event("basic_combat")),
        ["Science (Palmcone Scale)"] =          Event("moon_quay"),
        ["Science (Gnarwail Horn)"] =           all(Event("advanced_boating"), Event("basic_combat"), stringhint("gnarwail")),
        ["Science (Barnacles)"] =               all(Event("basic_boating"), "Razor", stringhint("waterplant")),
        ["Science (Frazzled Wires)"] =          any(all(Event("ruins_exploration"), "Hammer"), Event("any_shovel")),
        ["Science (Charcoal)"] =                Event("charcoal"),
        ["Science (Butter)"] =                  Event("butter"),
        ["Science (Asparagus)"] =               Event("asparagus_farming"),
        ["Science (Garlic)"] =                  Event("garlic_farming"),
        ["Science (Pumpkin)"] =                 Event("pumpkin_farming"),
        ["Science (Corn)"] =                    Event("corn_farming"),
        ["Science (Onion)"] =                   Event("onion_farming"),
        ["Science (Potato)"] =                  any(Event("potato_farming"), hard(ALWAYS_TRUE)),
        ["Science (Dragon Fruit)"] =            any(Event("dragonfruit_farming"), Event("dragonfruit_from_saladmander")),
        ["Science (Pomegranate)"] =             Event("pomegranate_farming"),
        ["Science (Eggplant)"] =                Event("eggplant_farming"),
        ["Science (Toma Root)"] =               Event("tomaroot_farming"),
        ["Science (Watermelon)"] =              Event("watermelon_farming"),
        ["Science (Pepper)"] =                  Event("pepper_farming"),
        ["Science (Durian)"] =                  Event("durian_farming"),
        ["Science (Carrot)"] =                  ALWAYS_TRUE,
        ["Science (Stone Fruit)"] =             any(Event("lunar_island"), Event("cave_exploration")),
        ["Science (Marble)"] =                  Event("any_pickaxe"),
        ["Science (Gold Nugget)"] =             Event("any_pickaxe"),
        ["Science (Flint)"] =                   ALWAYS_TRUE,
        ["Science (Honey)"] =                   ALWAYS_TRUE,
        ["Science (Twigs)"] =                   ALWAYS_TRUE,
        ["Science (Log)"] =                     Event("any_axe"),
        ["Science (Rocks)"] =                   Event("any_pickaxe"),
        ["Science (Light Bulb)"] =              REGION.CAVE and Event("any_pickaxe") or Event("sea_fishing"),
        ["Magic (Blue Gem)"] =                  Event("any_shovel"),
        ["Magic (Living Log)"] =                Event("living_log"),     
        ["Magic (Glommer's Goop)"] =            Event("full_moon"),
        ["Magic (Dark Petals)"] =               ALWAYS_TRUE,
        ["Magic (Red Gem)"] =                   Event("any_shovel"),
        ["Magic (Slurper Pelt)"] =              all(Event("ruins_exploration"), stringhint("slurper")),
        ["Magic (Blue Spore)"] =                all(any(Event("cave_exploration"), all("Funcaps", no_spread(any(Event("any_shovel"), Event("night"))))), "Bug Net"),
        ["Magic (Red Spore)"] =                 all(any(Event("cave_exploration"), all("Funcaps", no_spread(any(Event("any_shovel"), Event("day"))))), "Bug Net"),
        ["Magic (Green Spore)"] =               all(any(Event("cave_exploration"), all("Funcaps", no_spread(any(Event("any_shovel"), Event("dusk"))))), "Bug Net"),
        ["Magic (Broken Shell)"] =              Event("cave_exploration"),
        ["Magic (Leafy Meat)"] =                Event("leafy_meat"),
        ["Magic (Canary (Volatile))"] =         all(Event("canary"), Event("cave_exploration"), Event("bird_caging")),
        ["Magic (Life Giving Amulet)"] =        all("Life Giving Amulet", Event("any_shovel"), "Nightmare Fuel"),
        ["Magic (Nightmare Fuel)"] =            all(Event("basic_combat"), "Nightmare Fuel"),
        ["Magic (Cut Reeds)"] =                 Event("swamp"),
        ["Magic (Volt Goat Horn)"] =            all(Event("basic_combat"), stringhint("lightninggoat")),
        ["Magic (Beard Hair)"] =                ALWAYS_TRUE,
        ["Magic (Glow Berry)"] =                all(Event("ruins_exploration"), stringhint("worm")),
        ["Magic (Tentacle Spots)"] =            all(Event("basic_combat"), stringhint("tentacle")),
        ["Magic (Health)"] =                    Event("healing"),
        ["Magic (Sanity)"] =                    ALWAYS_TRUE,
        ["Magic (Telltale Heart)"] =            all(Event("healing"), "Telltale Heart"),
        ["Magic (Forget-Me-Lots)"] =            Event("basic_farming"),
        ["Magic (Cat Tail)"] =                  Event("pre_basic_combat"),
        ["Magic (Bunny Puff)"] =                all(all(Event("cave_exploration"), Event("basic_combat")), any(Event("dusk"), Event("night"), "Hammer", "Deconstruction Staff")),
        ["Magic (Mosquito Sack)"] =             all(Event("swamp"), stringhint("mosquito")),
        ["Magic (Spider Gland)"] =              stringhint("spider"),
        ["Magic (Monster Jerky)"] =             all("Drying Rack", "Rope", Event("charcoal")),
        ["Magic (Pig Skin)"] =                  all(any("Hammer", "Deconstruction Staff", all(Event("day"), Event("basic_combat"))), stringhint("pigman")),
        ["Magic (Batilisk Wing)"] =             all(Event("batilisk"), stringhint("bat")),
        ["Magic (Stinger)"] =                   any(stringhint("bee"), stringhint("killerbee")),
        ["Magic (Papyrus)"] =                   all("Papyrus", Event("swamp")),
        ["Magic (Green Cap)"] =                 any(Event("any_shovel", Event("cave_exploration"), Event("dusk"))),
        ["Magic (Blue Cap)"] =                  any(Event("any_shovel", Event("cave_exploration"), Event("night"))),
        ["Magic (Red Cap)"] =                   any(Event("any_shovel", Event("cave_exploration"), Event("day"))),
        ["Magic (Iridescent Gem)"] =            Event("iridescent_gem"),
        ["Magic (Desert Stone)"] =              helpful(Event("storm_protection")),
        ["Magic (Naked Nostrils)"] =            Event("cave_exploration"),
        ["Magic (Frog Legs)"] =                 any(stringhint("frog"), stringhint("merm")),
        ["Magic (Spoiled Fish)"] =              any(hard(Event("fishing")), Event("sea_fishing")),
        ["Magic (Spoiled Fish Morsel)"] =       Event("fishing"),
        ["Magic (Rot)"] =                       comment("Cooked berries are a good way to get rot quickly."),
        ["Magic (Rotten Egg)"] =                Event("bird_eggs"),
        ["Magic (Carrat)"] =                    all(any(Event("lunar_island"), Event("cave_exploration")), any("Trap", Event("any_shovel"))),
        ["Magic (Moleworm)"] =                  Event("moleworm"),
        ["Magic (Fireflies)"] =                 "Bug Net",
        ["Magic (Bulbous Lightbug)"] =          all(Event("cave_exploration"), "Bug Net"),
        ["Magic (Rabbit)"] =                    all("Trap", Event("rabbit")),
        ["Magic (Butterfly)"] =                 all(Event("butterfly"), "Bug Net"),
        ["Magic (Mosquito)"] =                  all("Bug Net", Event("swamp")),
        ["Magic (Bee)"] =                       "Bug Net",
        ["Magic (Killer Bee)"] =                "Bug Net",
        ["Magic (Crustashine)"] =               Event("moon_quay"),
        ["Magic (Crow)"] =                      "Bird Trap",
        ["Magic (Redbird)"] =                   "Bird Trap",
        ["Magic (Snowbird)"] =                  "Bird Trap",
        ["Magic (Canary)"] =                    all("Bird Trap", Event("canary")),
        ["Magic (Puffin)"] =                    all("Bird Trap", Event("basic_boating")),
        ["Magic (Fossil Fragments)"] =          all(Event("cave_exploration"), Event("any_pickaxe")),
        ["Think Tank (Freshwater Fish)"] =      Event("freshwater_fishing"),
        ["Think Tank (Live Eel)"] =             all(Event("cave_exploration"), "Freshwater Fishing Rod"),
        ["Think Tank (Runty Guppy)"] =          Event("sea_fishing"),
        ["Think Tank (Needlenosed Squirt)"] =   Event("sea_fishing"),
        ["Think Tank (Bitty Baitfish)"] =       Event("sea_fishing"),
        ["Think Tank (Smolt Fry)"] =            Event("sea_fishing"),
        ["Think Tank (Popperfish)"] =           Event("sea_fishing"),
        ["Think Tank (Fallounder)"] =           all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Bloomfin Tuna)"] =        Event("sea_fishing"),
        ["Think Tank (Scorching Sunfish)"] =    all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Spittlefish)"] =          all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Mudfish)"] =              Event("sea_fishing"),
        ["Think Tank (Deep Bass)"] =            all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Dandy Lionfish)"] =       all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Black Catfish)"] =        all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Corn Cod)"] =             all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Ice Bream)"] =            all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Sweetish Fish)"] =        all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Wobster)"] =              all(Event("advanced_boating"), Event("sea_fishing")),
        ["Think Tank (Lunar Wobster)"] =        all(Event("lunar_island"), Event("sea_fishing")),
        ["Pseudoscience (Purple Gem)"] =        "Purple Gem",
        ["Pseudoscience (Yellow Gem)"] =        ALWAYS_TRUE,
        ["Pseudoscience (Thulecite)"] =         Event("thulecite"),
        ["Pseudoscience (Orange Gem)"] =        ALWAYS_TRUE,
        ["Pseudoscience (Green Gem)"] =         ALWAYS_TRUE,
        ["Celestial (Moon Rock)"] =             ALWAYS_TRUE,
        ["Celestial (Moon Shard)"] =            any(Event("cave_exploration"), Event("can_reach_islands")),
        ["Celestial (Moon Shroom)"] =           Event("cave_exploration"),
        ["Celestial (Moon Moth)"] =             all("Bug Net", Event("any_axe")),
        ["Celestial (Lune Tree Blossom)"] =     ALWAYS_TRUE,
        ["Bottle Exchange (1)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (2)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (3)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (4)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (5)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (6)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (7)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (8)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (9)"] =               Event("crabby_hermit_friendship"),
        ["Bottle Exchange (10)"] =              Event("crabby_hermit_friendship"),
    }

    self.examplecookrecipes = {}

    for prettyname, rule in pairs(self.location_rules) do
        local bypass_season_rules = false
        -- Hardcode Grass Gekko to bypass season rules if it exists
        if prettyname == "Grass Gekko" and ArchipelagoDST.globalinfo.grassgekko_exists then
            bypass_season_rules = true
        end
        -- Remove redundant names
        if type(rule) == "table" and rule.get then
            local node = getNode(rule.get())
            if node and node.type == prettyname then
                rule.hidden = true
            end
        end
        --
        local loc = PRETTYNAME_TO_LOCATION_ID[prettyname] and ArchipelagoDST.ID_TO_LOCATION[PRETTYNAME_TO_LOCATION_ID[prettyname]]
        local addedrules = {}
        local addedhelpfulrules = {}
        local addrule = function(newrule)
            table.insert(addedrules, newrule)
        end
        local addhelpfulrule = function(newrule)
            table.insert(addedhelpfulrules, newrule)
        end
        if loc then
            -- Add example recipes
            if type(rule) == "table" and rule.recipe then
                self.examplecookrecipes[loc.id] = rule.recipe
            end
            
            -- Add respective research station rule to research locations
            local tags = deepcopy(loc.tags)
            if tags["research"] then
                if tags["science"] then
                    addrule(tags["tier_2"] and Event("alchemy_engine") or Event("science_machine"))
                elseif tags["magic"] then
                    addrule(tags["tier_2"] and Event("shadow_manipulator") or Event("prestihatitor"))
                elseif tags["celestial"] then
                    addrule(tags["tier_2"] and Event("celestial_altar") or any(Event("celestial_orb"), NoSpreadEvent("celestial_altar")))
                elseif tags["seafaring"] then
                    addrule(Event("think_tank"))
                elseif tags["ancient"] then
                    addrule(Event("ancient_altar"))
                elseif tags["hermitcrab"] then
                    addrule(Event("basic_boating"))
                end
               
            elseif tags["farming"] then
                addrule(HiddenEvent("advanced_farming"))

            elseif tags["cooking"] then
                addrule(Event("cooking"))
            end

            -- Make rules not required and change to helpful when set to bypass season rules
            if bypass_season_rules then
                addrule = addhelpfulrule
            end

            -- Hide season events for non-seasonal and non-farming locations
            local seasonwrapper = (
                tags["seasonal"] and noop
                or tags["cooking"] and function(...) return hidden(no_spread(...)) end
                or no_spread
            )
            local seasonpasswrapper = tags["seasonal"] and noop or hidden

            -- Season rules
            if tags["nonwinter"] then
                tags["autumn"] = true
                tags["spring"] = true
                tags["summer"] = true
            end
            if tags["nonspring"] then
                tags["autumn"] = true
                tags["winter"] = true
                tags["summer"] = true
            end
            if tags["nonsummer"] then
                tags["autumn"] = true
                tags["winter"] = true
                tags["spring"] = true
            end

            local seasonevents = {}
            if tags["autumn"] then table.insert(seasonevents, seasonwrapper(Event("autumn"))) end
            if tags["winter"] then table.insert(seasonevents, seasonwrapper(Event("winter"))) end
            if tags["spring"] then table.insert(seasonevents, seasonwrapper(Event("spring"))) end
            if tags["summer"] then table.insert(seasonevents, seasonwrapper(Event("summer"))) end

            if #seasonevents == 1 then
                local seasonsurvivalrule = tags["seasonal"] and (
                    (tags["winter"] and Event("winter_survival"))
                    or (tags["spring"] and Event("spring_survival"))
                    or (tags["summer"] and Event("summer_survival"))
                    or nil
                )
                addrule(seasonsurvivalrule and all(seasonsurvivalrule, seasonevents[1]) or seasonevents[1])
            elseif #seasonevents > 0 then
                addrule(any(unpack(seasonevents)))
            end

            -- Day phase rules
            local phaseevents = {}
            if tags["day"] then table.insert(phaseevents, Event("day")) end
            if tags["dusk"] then table.insert(phaseevents, Event("dusk")) end
            if tags["night"] then table.insert(phaseevents, Event("night")) end

            if #phaseevents == 1 then
                addrule(phaseevents[1])
            elseif #phaseevents > 0 then
                addrule(any(unpack(phaseevents)))
            end

            -- Season pass rules
            if tags["seasons_passed_half"] then addrule(seasonpasswrapper(Event("seasons_passed_half")))
            elseif tags["seasons_passed_1"] then addrule(seasonpasswrapper(Event("seasons_passed_1")))
            elseif tags["seasons_passed_2"] then addrule(seasonpasswrapper(Event("seasons_passed_2")))
            elseif tags["seasons_passed_3"] then addrule(seasonpasswrapper(Event("seasons_passed_3")))
            elseif tags["seasons_passed_4"] then addrule(seasonpasswrapper(Event("seasons_passed_4")))
            elseif tags["seasons_passed_5"] then addrule(seasonpasswrapper(Event("seasons_passed_5")))
            end
        end

        for _,v in ipairs(addedhelpfulrules) do
            table.insert(addedrules, helpful(v))
        end
        if #addedrules > 0 then
            table.insert(addedrules, rule)
            self.location_rules[prettyname] = all(unpack(addedrules))
        end
    end
end)
function Logic:SetIsCraftable(prefab)
    local item = ArchipelagoDST.PREFAB_TO_RECIPE_ITEM[prefab]
    if not item or HAS_ITEM[item.id] ~= nil then
        return
    end
    local recipe = AllRecipes[prefab]
    if recipe then
        local is_unlocked = not recipe.dstap_locked -- false: received item; nil: not shuffled
        local hasitemrules = {}
        local cancraftrules = {function() return is_unlocked end}
        local itemadditionalrule = ITEM_ADDITIONAL_RULE[item.id]
        if ArchipelagoDST.craftingmode == ArchipelagoDST.CRAFT_MODES.FREE_BUILD then
            CAN_CRAFT[item.id] = function() return is_unlocked end
            if itemadditionalrule then
                HAS_ITEM[item.id] = itemadditionalrule and function(difficulty)
                    return is_unlocked or itemadditionalrule(difficulty)
                end or CAN_CRAFT[item.id]
            end
            -- Freebuild doesn't need ingredient logic
            return
        end
        if itemadditionalrule then
            table.insert(hasitemrules, itemadditionalrule)
        end
        -- if not itemadditionalrule or ArchipelagoDST.craftingmode == ArchipelagoDST.CRAFT_MODES.LOCKED_INGREDIENTS then
        --     table.insert(hasitemrules, function() return is_unlocked end)
        -- end
        for _, v in ipairs(recipe.ingredients) do
            local ingredient_recipe = AllRecipes[v.type]
            if ingredient_recipe and ingredient_recipe.dstap_locked ~= nil then
                self:SetIsCraftable(v.type)
                -- local ingcraftablerule = HAS_ITEM[ingredient_recipe.dstap_item_id]
                -- if ingcraftablerule then
                --     table.insert(cancraftrules, ingcraftablerule)
                -- end
                local ing_item = ArchipelagoDST.PREFAB_TO_ITEM[v.type]
                if ing_item then
                    table.insert(cancraftrules, function(difficulty)
                        return has(ing_item.prettyname, difficulty)
                    end)
                    PRETTYNAME_ITEM_INGREDIENTS[item.prettyname] = PRETTYNAME_ITEM_INGREDIENTS[item.prettyname] or {}
                    PRETTYNAME_ITEM_INGREDIENTS[item.prettyname][ing_item.prettyname] = true
                end
            end
        end
        if #hasitemrules == 1 then
            HAS_ITEM[item.id] = hasitemrules[1]
        elseif #hasitemrules > 1 then
            HAS_ITEM[item.id] = function(difficulty)
                for _,v in ipairs(hasitemrules) do
                    if not v(difficulty) then
                        return false
                    end
                end
                return true
            end
        end
        if #cancraftrules == 1 then
            CAN_CRAFT[item.id] = cancraftrules[1]
        elseif #cancraftrules > 1 then
            CAN_CRAFT[item.id] = function(difficulty)
                for _,v in ipairs(cancraftrules) do
                    if not v(difficulty) then
                        return false
                    end
                end
                return true
            end
        end
        -- print(prefab.." craftable has been set to ", HAS_ITEM[item.id])
    end
end

function Logic:IsInLogic(loc_id, difficulty)
    difficulty = difficulty or "default"
    local loc = ArchipelagoDST.ID_TO_LOCATION[loc_id]
    if not loc then
        return false
    end
    local rule = self.location_rules[loc.prettyname]
    if not rule then
        return true
    end
    -- print("--- Getting rule for", loc.prettyname, difficulty, "---")
    rule = toRule(rule, difficulty)
    if rule then
        return rule(difficulty)
    else
        print("Error! No rule for", loc.prettyname)
    end
end
function Logic:GetRequirements(loc_id, difficulty)
    difficulty = difficulty or "default"
    local loc = ArchipelagoDST.ID_TO_LOCATION[loc_id]
    if not loc then
        return
    end
    -- print("--- Getting reqs for", loc.prettyname, "---")
    local node = self.location_rules[loc.prettyname]
    if not node then
        print("No rule for", loc.prettyname)
        return
    end
    -- node = getNode(node)
    -- print("Got node", node and node.type or "nil")
    local reqs = {
        items = {},
        events = {},
        has_events = {},
        characters = {},
        has_characters = {},
        comments = {},
    }
    local fillreqs = toReqsFn(node, difficulty)
    if not fillreqs then return end
    fillreqs(reqs, true)
    return reqs
end

function Logic:GetExampleCookRecipe(loc_id)
    return self.examplecookrecipes[loc_id]
end

return Logic