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
Assets = {
	Asset("ATLAS", "images/ap_icon.xml"), 
	Asset("IMAGE", "images/ap_icon.tex"), 

	Asset("ATLAS", "images/ap_icon_silho.xml"), 
	Asset("IMAGE", "images/ap_icon_silho.tex"), 

	Asset("ATLAS", "images/connectivity3.xml"), 
	Asset("IMAGE", "images/connectivity3.tex"), 

	Asset("ATLAS", "images/dstap_craftslot.xml"), 
	Asset("IMAGE", "images/dstap_craftslot.tex"), 

	Asset("ATLAS", "images/station_dstap.xml"), 
	Asset("IMAGE", "images/station_dstap.tex"), 

	Asset("ATLAS", "images/inventoryimages/dstap_item.xml"), 
	Asset("IMAGE", "images/inventoryimages/dstap_item.tex"), 

	Asset("ATLAS", "images/dstap_scrapbook_ap.xml"), 
	Asset("IMAGE", "images/dstap_scrapbook_ap.tex"), 

	Asset("ATLAS", "images/dstap_scrapbook_progression.xml"), 
	Asset("IMAGE", "images/dstap_scrapbook_progression.tex"), 

	Asset("ATLAS", "images/dstap_scrapbook_warning.xml"), 
	Asset("IMAGE", "images/dstap_scrapbook_warning.tex"), 

	Asset("ATLAS", "images/dstap_scrapbook_ool.xml"), 
	Asset("IMAGE", "images/dstap_scrapbook_ool.tex"), 
}
PrefabFiles = {
	"dstap_blueprint",
	"dstap_dummies",
}

local Recipes = GLOBAL.AllRecipes
local STRINGS = GLOBAL.STRINGS
local TUNING = GLOBAL.TUNING

GLOBAL.ArchipelagoDST = {
	-- AP_CLIENT_IP = "localhost:8000", -- URL the mod needs to reach the Archipelago client. If some reason you want to reach a client from another machine, you'll need to change the apworld's socket bind to 0.0.0.0
	VERSION = {
		CLIENT_VERSION_COMPATIBLE = "1.3.0.1",
	},
	TUNING = {
		BEE_TRAP_COUNT = 3,
		BEE_TRAP_DISTANCE = 3,

		ICE_TRAP_COUNT = 5,
		ICE_TRAP_SPAWN_TIME = 1,
		ICE_TRAP_RANGE = 7.5,

		SPORE_TRAP_COUNT = 1,

		BOOMERANG_TRAP_COUNT = 3,
		BOOMERANG_TRAP_DELAY = 0.75,
		BOOMERANG_TRAP_DIST = 15,

		COMBAT_LOCATION_RANGE = 30,

		EXTRA_BOSS_DAMAGE_INITIAL = GetModConfigData("extrabossdamage_initial") or 0,
		EXTRA_BOSS_DAMAGE_STACK_MULT = GetModConfigData("extrabossdamage_mult") or 0.1,
		EXTRA_RAIDBOSS_DAMAGE_STACK_MULT = GetModConfigData("extrabossdamage_raid_mult") or 0.25,
		
		DAMAGE_BONUS_INITIAL = GetModConfigData("damagebonus_initial") or 0,
		DAMAGE_BONUS_STACK_MULT = GetModConfigData("damagebonus_mult") or 0.1,

		FARM_PLANT_RANDOMSEED_WEED_CHANCE = TUNING.FARM_PLANT_RANDOMSEED_WEED_CHANCE,

		OVERRIDE_CRAFT_MODE = GetModConfigData("craftingmode_override") ~= "none" and GetModConfigData("craftingmode_override") or false,
		OVERRIDE_DEATH_LINK = GetModConfigData("deathlink_override") ~= "none" and GetModConfigData("deathlink_override") or false,

		TRAP_DECOY_NAME_CHANCE = GetModConfigData("trapdecoyname_chance") or 0.95,

		RECEIVE_OFFLINE_TRAPS = GetModConfigData("receiveofflinetraps") and true or false,
		
		DEATHLINK_PENALTY = GetModConfigData("deathlink_penalty") or 1,
	},
	CRAFT_MODES = {
		VANILLA = "vanilla",
		JOURNEY = "journey",
		FREE_SAMPLES = "freesamples",
		FREE_BUILD = "freebuild",
		LOCKED_INGREDIENTS = "lockedingredients",
	}
}
local DSTAP = GLOBAL.ArchipelagoDST
TUNING.ARCHIPELAGO_DST = DSTAP.TUNING

modimport("strings")
modimport("recipes")
modimport("effects")
modimport("ap_constants") -- Populates DSTAP.RAW with data
---------------------------------------------------------
DSTAP.craftingmode = DSTAP.TUNING.OVERRIDE_CRAFT_MODE or DSTAP.CRAFT_MODES.VANILLA
---------------------------------------------------------
DSTAP.ID_TO_ITEM = {} -- id -> object
DSTAP.ID_TO_ABSTRACT_ITEM = {}
DSTAP.ID_TO_LOCATION = {}
DSTAP.ID_TO_RESEARCH_LOCATION = {}
DSTAP.ID_TO_DEPRECATED_LOCATION = {}
DSTAP.PREFAB_TO_ITEM = {} -- Prefab -> object
DSTAP.PREFAB_TO_RECIPE_ITEM = {}
DSTAP.PREFAB_TO_BUNDLE_ITEM = {}
DSTAP.PREFAB_TO_COMBAT_LOCATION = {}
DSTAP.PREFAB_TO_COOKING_LOCATION = {}
DSTAP.PREFAB_TO_RESEARCH_LOCATION = {}
DSTAP.PREFAB_TO_FARMING_LOCATION = {}
DSTAP.TASK_LOCATIONS = {} -- Pretty name -> object
DSTAP.LOCATION_INFO = {}
DSTAP.ITEM_HINT_INFO = {}
DSTAP.LOCATION_HINT_INFO = {}
DSTAP.missinglocations = {} -- To be filled by DSTAPManager
DSTAP.collecteditems = {}
DSTAP.lockableitems = {}
DSTAP.abstractitems = {}
DSTAP.all_locations = nil
DSTAP.goalinfo = nil
DSTAP.globalinfo = {}

-- Populate item and location lists
for _,v in ipairs(DSTAP.RAW.ITEMS) do
	local item = {
		id = v[1] + DSTAP.RAW.ITEM_ID_OFFSET,
		prettyname = v[2],
		prefab = v[3],
		tags = listToSet(v[4]),
	}
	if item.tags["physical"] then
		item.quantity = v[5] or 1
	elseif item.tags["nounlock"] then
		item.filters = v[5]
	elseif item.tags["abstract"] then
		DSTAP.ID_TO_ABSTRACT_ITEM[item.id] = item
	end
	if item.prefab then DSTAP.PREFAB_TO_ITEM[item.prefab] = item end
	if item.prefab and not item.tags["physical"] then DSTAP.PREFAB_TO_RECIPE_ITEM[item.prefab] = item end
	DSTAP.ID_TO_ITEM[item.id] = item
end
for _,v in ipairs(DSTAP.RAW.LOCATIONS) do
	local loc = {
		id = v[1] + DSTAP.RAW.LOCATION_ID_OFFSET,
		prettyname = v[2],
		prefab = v[3],
		tags = listToSet(v[4]),
	}
	
	if loc.prefab and #loc.prefab > 0 then 
		if loc.tags["creature"] or loc.tags["boss"] or loc.tags["item"] then
			DSTAP.PREFAB_TO_COMBAT_LOCATION[loc.prefab] = loc 
		elseif loc.tags["research"] and not loc.tags["hermitcrab"] then
			DSTAP.PREFAB_TO_RESEARCH_LOCATION[loc.prefab] = loc
		elseif loc.tags["farming"] then
			DSTAP.PREFAB_TO_FARMING_LOCATION[loc.prefab] = loc
		elseif loc.tags["cooking"] then
			DSTAP.PREFAB_TO_COOKING_LOCATION[loc.prefab] = loc
		end
	end
	DSTAP.ID_TO_LOCATION[loc.id] = loc
	if loc.tags["research"] then
		DSTAP.ID_TO_RESEARCH_LOCATION[loc.id] = loc
	end
	if loc.tags["task"] then
		DSTAP.TASK_LOCATIONS[loc.prettyname] = loc
	end
	if loc.tags["deprecated"] then
		DSTAP.ID_TO_DEPRECATED_LOCATION[loc.id] = loc
	end
end
-- Apply aliases (applies only to combat targets right now)
for k, v in pairs(DSTAP.RAW.LOCATION_ALIASES) do
	if DSTAP.PREFAB_TO_COMBAT_LOCATION[v] then 
		DSTAP.PREFAB_TO_COMBAT_LOCATION[k] = DSTAP.PREFAB_TO_COMBAT_LOCATION[v]
	end
end
-- Mark items that are in bundle to avoid double operations
for _, bundle in pairs(DSTAP.RAW.BUNDLE_DEFS) do
	for _, pref in ipairs(bundle) do
		local item = DSTAP.PREFAB_TO_RECIPE_ITEM[pref]
		if item and not item.tags["bundle"] then
			item.inbundle = true
			DSTAP.PREFAB_TO_BUNDLE_ITEM[pref] = item
		end
	end
end
local TechTree = require("techtree")
-- table.insert(TechTree.AVAILABLE_TECH,"DSTAP_TECH")
local DSTAP_TECH_LOCKED = GLOBAL.TECH.LOST
local DSTAP_TECH_UNLOCKED = { DSTAP_TECH = 2 }
TUNING.PROTOTYPER_TREES.DSTAP = TechTree.Create(DSTAP_TECH_UNLOCKED)
DSTAP.LockRecipe = function(recipe, lock, itemid, filters)
	-- Locks a recipe directly
	if not recipe then return end
	if lock == true or lock == false then
		if not recipe.dstap_recipe then
			recipe.dstap_level_prev = recipe.level
			recipe.dstap_station_tag_prev = recipe.station_tag
			recipe.dstap_nounlock_prev = recipe.nounlock
			recipe.dstap_hint_msg_prev = recipe.hint_msg
			recipe.dstap_item_id = itemid
			recipe.dstap_recipe = true
			recipe.hint_msg = "NEEDS_DSTAP_HINT_"..itemid
			if not STRINGS.UI.CRAFTING["NEEDS_DSTAP_HINT_"..itemid] then
				STRINGS.UI.CRAFTING["NEEDS_DSTAP_HINT_"..itemid] = STRINGS.UI.CRAFTING.DSTAP_LOCKED
			end

			if filters then
				recipe.dstap_craftingstation_default_sort_value = GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.default_sort_values[recipe.name]
				-- Remove from crafting station filter
				if table.contains(GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.recipes, recipe.name) then
					table.removearrayvalue(GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.recipes, recipe.name)
					GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.default_sort_values[recipe.name] = nil
				end
				-- Add to new filters
				for _, filter in ipairs(filters) do
					local t = GLOBAL.CRAFTING_FILTERS[filter]
					if t then
						if not table.contains(t.recipes, recipe.name) then
							table.insert(t.recipes, recipe.name)
							t.default_sort_values[recipe.name] = #t.recipes
						end
					else
						print("Failed to add", recipe.name,"into filter", filter)
					end
				end
			end
		end
		recipe.level = TechTree.Create(lock	and DSTAP_TECH_LOCKED or DSTAP_TECH_UNLOCKED)
		recipe.station_tag = nil
		recipe.nounlock = false
		recipe.dstap_locked = lock
	else
		-- Reverse changes
		if recipe.dstap_recipe then
			recipe.level = recipe.dstap_level_prev
			recipe.station_tag = recipe.dstap_station_tag_prev
			recipe.nounlock = recipe.dstap_nounlock_prev
			recipe.hint_msg = recipe.dstap_hint_msg_prev
			recipe.dstap_recipe = nil
			recipe.dstap_locked = nil
			
			if filters then
				-- Add to crafting station filter
				if not table.contains(GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.recipes, recipe.name) then
					table.insert(GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.recipes, recipe.name)
					GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION.default_sort_values[recipe.name] = recipe.dstap_craftingstation_default_sort_value
				end
				-- Remove from new filters
				for _, filter in ipairs(filters) do
					local t = GLOBAL.CRAFTING_FILTERS[filter]
					if t then
						if table.contains(t.recipes, recipe.name) then
							table.removearrayvalue(t.recipes, recipe.name)
							t.default_sort_values[recipe.name] = nil
						end
					end
				end
			end
		end
	end
end

DSTAP.LockItem = function(id, lock, pushunlockevent, includeindependentbundleitems)
	-- Locks either a recipe or bundle by its id
	local item = DSTAP.ID_TO_ITEM[id]
	if not item then return end

	local recs = {}
	if item.tags["bundle"] then
		local bundle = DSTAP.RAW.BUNDLE_DEFS[item.prefab]
		if bundle then
			for _,v in ipairs(bundle) do
				local bundleitem = DSTAP.PREFAB_TO_BUNDLE_ITEM[v]
				if not bundleitem or includeindependentbundleitems or not DSTAP.lockableitems[bundleitem.id] then -- Independent bundled items get handled seperately
					table.insert(recs, v)
				end
			end
		else
			print("Error! No bundle named",item.prefab,"found in bundle defs!")
		end
	else
		recs = {item.prefab}
	end
	for _,v in ipairs(recs) do
		local recipe = Recipes[v]
		if recipe then
			DSTAP.LockRecipe(recipe, lock, id, item.filters)
		end
	end
	
	if pushunlockevent then
		DSTAP.PushUnlockRecipeEvent()
	end
end

DSTAP.PushUnlockRecipeEvent = function()
	-- Give free samples for things you haven't made on free sample mode
	if GLOBAL.TheWorld.ismastersim and DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_SAMPLES then
		for _, player in pairs(GLOBAL.AllPlayers) do
			if player.components.builder then
				player.components.builder:DSTAP_GiveFreeSamples()
			end
		end
	end
	-- Set recipes as dirty
	for _, player in pairs(GLOBAL.AllPlayers) do
		player:PushEvent("unlockrecipe")
	end
end
DSTAP.LockAllRecipes = function()
	for _, v in pairs(DSTAP.ID_TO_ITEM) do
		if not v.inbundle then
			DSTAP.LockItem(v.id, true, false, true)
		end
	end
	DSTAP.PushUnlockRecipeEvent()
end

--------------------------------
-- Add recipes for all the research stuff
local SpecialIngredients = {
	health = Ingredient(GLOBAL.CHARACTER_INGREDIENT.HEALTH, 10),
	sanity = Ingredient(GLOBAL.CHARACTER_INGREDIENT.SANITY, 10),
}
local TECH = GLOBAL.TECH
local TECHLOOKUP = {
	science = {tier_1 = TECH.SCIENCE_ONE, tier_2 = TECH.SCIENCE_TWO},
	magic = {tier_1 = TECH.MAGIC_TWO, tier_2 = TECH.MAGIC_THREE},
	seafaring = TECH.SEAFARING_TWO,
	ancient = {tier_1 = TECH.ANCIENT_TWO, tier_2 = TECH.ANCIENT_FOUR},
	celestial = {tier_1 = TECH.CELESTIAL_ONE, tier_2 = TECH.CELESTIAL_THREE},
	hermitcrab = {tier_1 = TECH.HERMITCRABSHOP_ONE, tier_2 = TECH.HERMITCRABSHOP_THREE, tier_3 = TECH.HERMITCRABSHOP_FIVE, tier_4 = TECH.HERMITCRABSHOP_SEVEN },
}
--
local INGREDIENTS_IMAGE_OVERRIDES = {
	tomato = "quagmire_tomato.tex",
	rock_avocado_fruit = "rock_avocado_fruit_rockhard.tex",
	onion = "quagmire_onion.tex",
}
for _, v in pairs(DSTAP.ID_TO_RESEARCH_LOCATION) do
	-- Get the correct tech
	local tech = TECH.NONE
	local techname = "none"
	for techtype, techtiers in pairs(TECHLOOKUP) do
		if v.tags[techtype] then
			techname = techtype
			if techtype == "seafaring" then 
				tech = techtiers
				break 
			end
			for technum, techtier in pairs(techtiers) do
				if v.tags[technum] then
					tech = techtier
					break
				end
			end
			break
		end
	end
	local ingredient = SpecialIngredients[v.prefab] or Ingredient(v.prefab, techname == "hermitcrab" and 1 or 0, nil, nil, INGREDIENTS_IMAGE_OVERRIDES[v.prefab] or nil)
	local config = {
		nounlock = true,
		product = v.prefab,
		image = "dstap_item.tex",
		atlas = "images/inventoryimages/dstap_item.xml",
		nameoverride = "dstap_"..techname,
		description = "dstap_research_"..v.id,
		canbuild = function(recipe)
			if not recipe.dstap_location then return false, "DSTAP_ALREADY_HAVE_LOCATION" end
			return DSTAP.missinglocations[recipe.dstap_location.id]
		end,
	}
	STRINGS.RECIPE_DESC["DSTAP_RESEARCH_"..v.id] = STRINGS.RECIPE_DESC["DSTAP_"..(techname == "hermitcrab" and "TRADE" or "RESEARCH")]
	if v.tags["research"] then
		local recipe = AddRecipe2("dstap_research_"..v.id, {ingredient}, tech, config, GLOBAL.CRAFTING_FILTERS.CRAFTING_STATION)
		recipe.dstap_location = v
	end
end
-------------------------------
-- Create decoy names for traps
function GenerateDecoyName()
	local words = STRINGS.ARCHIPELAGO_DST.DECOY_WORDS or {"Thing"}
	return(words[math.random(#words)].." "..words[math.random(#words)])
end
-------------------------------
-- Allow science/magic/thinktank prototypes to be crafting stations and have the icon for it
local approtodef = {icon_atlas = "images/station_dstap.xml", icon_image = "station_dstap.tex", is_crafting_station = true, filter_text = STRINGS.UI.CRAFTING_STATION_FILTERS.DSTAP_RESEARCH}
GLOBAL.PROTOTYPER_DEFS.researchlab = approtodef
GLOBAL.PROTOTYPER_DEFS.researchlab2 = approtodef
GLOBAL.PROTOTYPER_DEFS.researchlab4 = approtodef
GLOBAL.PROTOTYPER_DEFS.researchlab3 = approtodef
GLOBAL.PROTOTYPER_DEFS.seafaring_prototyper = approtodef

--------------------------------
local function _resolve_location(name)
	if not name or name == "" then
		return
	end
	-- Search by id
	if type(name) == "number" then
		local loc_id = name
		if loc_id < DSTAP.RAW.LOCATION_ID_OFFSET then
			loc_id = loc_id + DSTAP.RAW.LOCATION_ID_OFFSET
		end
		return DSTAP.ID_TO_LOCATION[loc_id]
	end
	if type(name) ~= "string" then
		return
	end
	name = string.lower(name)

	-- Search by pretty name
	for _, v in pairs(DSTAP.ID_TO_LOCATION) do
		if string.lower(v.prettyname) == name then
			return v
		end
	end

	-- Check if it's a combat location, including aliases
	if DSTAP.PREFAB_TO_COMBAT_LOCATION[name] then
		return DSTAP.PREFAB_TO_COMBAT_LOCATION[name]
	end

	-- Search by prefab, whichever matches first
	for _, v in pairs(DSTAP.ID_TO_LOCATION) do
		if string.lower(v.prefab) == name then
			return v
		end
	end
end

-- Debug function to collect a location by its name
DSTAP.CollectLocation = function(name)
	local loc = _resolve_location(name)

    if not loc then 
        print(name, "is not a valid location name or ID!")
		return
	end
	DSTAP.CollectLocationByID(loc.id)
end

-- Collect a location by its id
DSTAP.CollectLocationByID = function(id)
	local loc = DSTAP.ID_TO_LOCATION[id]
    if not loc then 
        print(id, "is not a valid ID!")
	end
    -- Check if location is one we're missing
    if not DSTAP.missinglocations[loc.id] then
		-- print(loc.prettyname, "is not one of our missing locations!")
        return 
    end
    local doer = (#GLOBAL.AllPlayers>0) and GLOBAL.AllPlayers[1].name or "You"
    GLOBAL.TheWorld:PushEvent("dstapfoundlocation", {id = loc.id, doer})
end

-- Collect a location by its prefab
DSTAP.CollectLocationByPrefab = function(prefab, loc_type)
    -- Get appropriate table
    local t = loc_type == "combat" and DSTAP.PREFAB_TO_COMBAT_LOCATION
        or loc_type == "cooking" and DSTAP.PREFAB_TO_COOKING_LOCATION
        or loc_type == "farming" and DSTAP.PREFAB_TO_FARMING_LOCATION
    if not t then 
        print("Did not find a table for ", prefab, "for category ", loc_type)
        return 
    end
    -- Check if location is valid
    local loc = t[prefab] 
    if not loc then 
        -- print(prefab, " is not a location in the ", loc_type, " table!")
        return 
    end
	DSTAP.CollectLocationByID(loc.id)
end

-- Special location functions
DSTAP.SpecialLocationChecks = {
    stalker_atrium = function(inst)
        return not inst.atriumdecay
    end
}

-- Get a location by its inst
DSTAP.CollectLocationByInst = function(inst, loc_type)
    -- Check special conditions
    local specialfn = DSTAP.SpecialLocationChecks[inst.prefab]
    if specialfn then
        if not specialfn(inst) then return end
    end
    return DSTAP.CollectLocationByPrefab(inst.prefab, loc_type)
end

-- Get a task location by its name
DSTAP.CollectTaskLocation = function(name)
	-- Check if location is valid
	local loc = DSTAP.TASK_LOCATIONS[name] 
	if not loc then 
		print(name, " is not a task location!")
		return 
	end
	DSTAP.CollectLocationByID(loc.id)
end

DSTAP.SetLocationInfo = function(loc_info)
	local loc = DSTAP.ID_TO_RESEARCH_LOCATION[loc_info.id]
	if loc then
		-- This is a research location
		local important = loc_info.flags == 1 or loc_info.flags == 3
		local useful = loc_info.flags == 2
		local trap = loc_info.flags == 4
		local itemname = trap and (math.random() < DSTAP.TUNING.TRAP_DECOY_NAME_CHANCE) and GenerateDecoyName() or loc_info.itemname
		local ending = ""
		if trap then
			if math.random() < 0.3 then 
				important = true
			elseif trap and math.random() < 0.5 then
				useful = true
			end
		end
		if important then ending = ". This looks important to them" end
		if useful then ending = ". Seems like it could be useful" end
		STRINGS.RECIPE_DESC["DSTAP_RESEARCH_"..loc_info.id] = "This will give "..itemname.." to "..loc_info.playername..ending..(trap and math.random() < 0.5 and "?" or ".")
	end
end

DSTAP.SaveAndSetLocationInfo = function(loc_info)
	if not DSTAP.LOCATION_INFO[loc_info.id] then
		DSTAP.LOCATION_INFO[loc_info.id] = loc_info
		DSTAP.SetLocationInfo(loc_info)
		if GLOBAL.TheWorld.ismastersim then
			GLOBAL.TheWorld:PushEvent("dstap_location_info_set", loc_info)
		end
	end
end

DSTAP.SetAndSaveHintInfo = function(hint)
	if hint.item and hint.item_is_local and not DSTAP.ITEM_HINT_INFO[hint.item] then -- Items may potentially not be unique, but only recipes really matter
		DSTAP.ITEM_HINT_INFO[hint.item] = hint
		DSTAP.SetItemHintInfo(hint)
	end
	if hint.location and hint.location_is_local and not DSTAP.LOCATION_HINT_INFO[hint.location] then
		DSTAP.LOCATION_HINT_INFO[hint.location] = hint
	end
end

DSTAP.SetItemHintInfo = function(hint)
	local hintstr = "This is at "..hint.locationname.." in "..hint.findingname.."'s world."
	STRINGS.CHARACTERS.GENERIC.ANNOUNCE_CANNOT_BUILD["DSTAP_HINT_"..hint.item] = hintstr
	STRINGS.UI.CRAFTING["NEEDS_DSTAP_HINT_"..hint.item] = hintstr
end

modimport("network")
modimport("postinits")