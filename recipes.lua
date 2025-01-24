--------------------------------------------------
-- Season Change Recipes
local setseason = function(season)
	if GLOBAL.TheWorld.state.season == season then
		return false, "DSTAP_SEASONCHANGEFAIL"
	end
	GLOBAL.TheWorld:PushEvent("ms_setseason", season)
	return true
end
local setmoonphase = function(moonphase)
	if GLOBAL.TheWorld.state.moonphase == moonphase then
		return false, "DSTAP_MOONPHASECHANGEFAIL"
	end
	GLOBAL.TheWorld:PushEvent("ms_setmoonphase", {moonphase = moonphase, iswaxing = (moonphase == "new")})
	return true
end
for pref, fn in pairs({
	dstap_seasonchange_autumn = function() return setseason("autumn") end,
	dstap_seasonchange_winter = function() return setseason("winter") end,
	dstap_seasonchange_spring = function() return setseason("spring") end,
	dstap_seasonchange_summer = function() return setseason("summer") end,
	dstap_moonphasechange_full = function() return setmoonphase("full") end,
	dstap_moonphasechange_new = function() return setmoonphase("new") end,
}) do
	table.insert(Assets, Asset("ATLAS", "images/inventoryimages/"..pref..".xml"))
	table.insert(Assets, Asset("IMAGE", "images/inventoryimages/"..pref..".tex"))
	 
	local recipe = AddRecipe2(pref, 
		{
			Ingredient(GLOBAL.CHARACTER_INGREDIENT.SANITY, 15), 
			(pref == "dstap_moonphasechange_full" or pref == "dstap_moonphasechange_new") and Ingredient("moonrockseed", 0) or nil,
		}, 
		GLOBAL.TECH.LOST,
		{ atlas = "images/inventoryimages/"..pref..".xml", manufactured = true}, -- config
		{"MAGIC"} -- filters
	)
	recipe.dstap_effect = fn
end
--------------------------------------------------
-- Add a way to trigger Shadow Pieces even if in a moonstorm
local recipe = AddRecipe2("dstap_awakennearbystatues", 
	{
		Ingredient("nightmarefuel", 1)
	}, 
	GLOBAL.TECH.CELESTIAL_THREE,
	{ 
		nounlock = true, 
		image = "dstap_moonphasechange_new.tex",
		atlas = "images/inventoryimages/dstap_moonphasechange_new.xml", 
		manufactured = true
	}, -- config
	{"MOON_ALTAR"} -- filters
)

local AWAKEN_NEARBY_STATUES_RADIUS = 15
local NEARBYSTATUES_TAGS = { "chess_moonevent" }

local function AwakenNearbyStatues(inst)
	if not inst then
		return false
	end
	if not GLOBAL.TheWorld.state.isnight then
		return false, "DSTAP_AWAKENNEARBYSTATUES_NOT_NIGHT"
	end
    local x, y, z = inst.Transform:GetWorldPosition()
    local ents = GLOBAL.TheSim:FindEntities(x, y, z, AWAKEN_NEARBY_STATUES_RADIUS, NEARBYSTATUES_TAGS)
    for i, v in ipairs(ents) do
        v:PushEvent("shadowchessroar", true)
		return true
    end
	return false, "DSTAP_AWAKENNEARBYSTATUES_NO_STATUES"
end

recipe.dstap_effect = AwakenNearbyStatues
--------------------------------------------------
-- SEEDS
for _, v in ipairs({
	"asparagus_seeds",
	"garlic_seeds",
	"pumpkin_seeds",
	"corn_seeds",
	"onion_seeds",
	"potato_seeds",
	"dragonfruit_seeds",
	"pomegranate_seeds",
	"eggplant_seeds",
	"tomato_seeds",
	"watermelon_seeds",
	"pepper_seeds",
	"durian_seeds",
	"carrot_seeds",
}) do
	AddRecipe2("dstap_"..v, {Ingredient("seeds", 1)}, GLOBAL.TECH.LOST, {product = v, description = "dstap_"..v}, {"GARDENING"})
end