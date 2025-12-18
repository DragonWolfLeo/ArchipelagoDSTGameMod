local Recipes = GLOBAL.AllRecipes
local STRINGS = GLOBAL.STRINGS
local ChatTypes = GLOBAL.ChatTypes
local DSTAP = GLOBAL.ArchipelagoDST
local json = GLOBAL.json

local TechTree = require("techtree")
-- Disable Pinchin' Winch blueprint recipe
if Recipes["hermitshop_winch_blueprint"] then
    Recipes["hermitshop_winch_blueprint"].level = TechTree.Create(GLOBAL.TECH.LOST)
end

-- Get locations when you cook
local function StewerPostInit(self, inst)
    local Harvest_prev = self.Harvest
    function self:Harvest(...)
        if self.done and self.product then
            DSTAP.CollectLocationByPrefab(self.product, "cooking")
        end
        return Harvest_prev(self, ...)
    end
end
AddComponentPostInit("stewer", StewerPostInit)

-- Get locations when you pick a giant plant
AddPrefabPostInitAny(function(inst)
    if inst:HasTag("farm_plant") and inst.components.lootdropper then
        inst:ListenForEvent("loot_prefab_spawned",function(inst,data)
            for prefab,v in pairs(DSTAP.PREFAB_TO_FARMING_LOCATION) do
                if prefab == (data.loot and data.loot.prefab) then
                    return DSTAP.CollectLocationByPrefab(prefab,"farming")
                end
            end
        end)
    end
end)

-- Remove research recipes if it's no longer a missing locations
local function CraftingMenuHudPostInit(self)
    local RebuildRecipes_prev = self.RebuildRecipes
    function self:RebuildRecipes(...)
        RebuildRecipes_prev(self, ...)
        for recipename, data in pairs(self.valid_recipes) do
            -- Get rid of research recipe if it's not one of your missing locations
            if data.recipe and data.recipe.dstap_location and not DSTAP.missinglocations[data.recipe.dstap_location.id] then
                self.valid_recipes[recipename] = nil 
            end
            -- Hint recipe if it's one of your hints
            if data.recipe and data.recipe.dstap_item_id and DSTAP.ITEM_HINT_INFO[data.recipe.dstap_item_id] then
                if data.meta.build_state == "hide" then
                    data.meta.build_state = "hint"
                end
            end
        end
    end
end
AddClassPostConstruct("widgets/redux/craftingmenu_hud", CraftingMenuHudPostInit)

-- CRAFTING ORDER
-- Placers:
-- Learn recipe
-- Remove ingredients
-- Buffer

-- Inventory Items:
-- Build anim
-- Remove ingredients
-- Learn recipe

local function CraftingMenuWidgetPostInit(self)
    -- Make inventory items have the AP icon
    if self.recipe_grid and self.recipe_grid.update_fn then
        local ScrollWidgetSetData_prev = self.recipe_grid.update_fn
        self.recipe_grid.update_fn = function(context, widget, data, index,...)
            if data ~= nil and data.recipe ~= nil and data.meta ~= nil and data.recipe.dstap_recipe then
                local ret = ScrollWidgetSetData_prev(context, widget, data, index,...)
                local atlas = GLOBAL.resolvefilepath(GLOBAL.CRAFTING_ATLAS)
                local recipe = data.recipe
                local meta = data.meta
                -- Replace lock icon with ap icon
                if widget and widget.fg and widget.fg.texture == "slot_fg_lock.tex" then
                    widget.fg:SetTexture("images/dstap_craftslot.xml", "dstap_craftslot.tex")
                end
                -- Make free samples appear as buffered
                if widget and widget.bg
                and widget.bg.texture ~= "slot_bg_buffered.tex" 
                and DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_SAMPLES
                and not recipe.placer
                and not recipe.dstap_locked
                and not recipe.dstap_effect
                and self.owner
                and self.owner.replica.builder
                and not self.owner.replica.builder:KnowsRecipe(recipe.name)
                then
                    widget.bg:SetTexture(atlas, "slot_bg_buffered.tex")
                    if widget.fg then widget.fg:Hide() end
                end
                return ret
            else
                return ScrollWidgetSetData_prev(context, widget, data, index,...)
            end
        end
    end
end
AddClassPostConstruct("widgets/redux/craftingmenu_widget", CraftingMenuWidgetPostInit)


local function CraftingMenuPinSlotPostInit(self)
    local Refresh_prev = self.Refresh
    function self:Refresh(...)
        ret = Refresh_prev(self, ...)

        local data = self.craftingmenu:GetRecipeState(self.recipe_name)
        if data ~= nil and data.recipe ~= nil and data.recipe.dstap_recipe then
            local atlas = GLOBAL.resolvefilepath(GLOBAL.CRAFTING_ATLAS)
            local recipe = data.recipe
            local builder = self.owner and self.owner.replica.builder or nil

            -- Replace lock icon with ap icon
            if self.fg 
            and self.fg.texture == "pinslot_fg_lock.tex"
            then
                self.fg:SetTexture("images/dstap_craftslot.xml", "dstap_craftslot.tex")
            end

            -- Make free samples appear as buffered
            if self.craft_button 
            and DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_SAMPLES
            and not recipe.placer
            and not recipe.dstap_locked
            and not recipe.dstap_effect
            and not builder:KnowsRecipe(recipe.name)
            then
                self.craft_button:SetTextures(atlas, "pinslot_bg_buffered.tex", nil, nil, nil, "pinslot_bg_buffered.tex")
                if self.fg then self.fg:Hide() end
            end

            -- Hide ingredients after building in journey crafting mode
            if self.recipe_popup 
            and not recipe.dstap_effect
            and DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY 
            and builder:KnowsRecipe(recipe)
            then
			    self.recipe_popup:HidePopup()
            end
        end

        return ret
    end
    
    -- Hide ingredients if free building
    local ShowRecipe_prev = self.ShowRecipe
    function self:ShowRecipe(...)
        local data = self.craftingmenu:GetRecipeState(self.recipe_name)
        if data ~= nil and data.recipe ~= nil and data.recipe.dstap_recipe and not data.recipe.dstap_effect then
            local recipe = data.recipe
            local builder = self.owner and self.owner.replica.builder or nil
            
            if (DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_BUILD) 
            or (DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY and builder:KnowsRecipe(recipe))
            then
                self.craft_button:Select()
                return
            end
        end

        return ShowRecipe_prev(self, ...)
    end
end
AddClassPostConstruct("widgets/redux/craftingmenu_pinslot", CraftingMenuPinSlotPostInit)


local Text = require "widgets/text"
local function CraftingMenuDetailsPostInit(self)
    -- Change the teaser to hint you can't craft something because of locked ingredients
    local UpdateBuildButton_prev = self.UpdateBuildButton
    function self:UpdateBuildButton(...)
        local ret = UpdateBuildButton_prev(self, ...)
        if self.data ~= nil then
            local recipe = self.data.recipe
            -- No need to hint locked ingredients if the main recipe is locked to begin with
            if recipe.dstap_locked then
                return ret
            end
            if DSTAP.craftingmode == DSTAP.CRAFT_MODES.LOCKED_INGREDIENTS and recipe.dstap_recipe and recipe.ingredients ~= nil then
                for i, v in ipairs(self.ingredients.ingredient_widgets) do
                    if v ~= nil and v.dstap_locked_ingredient then
                        local str = STRINGS.UI.CRAFTING.DSTAP_LOCKED_INGREDIENTS
                        self.build_button_root.teaser:Show()
                        self.build_button_root.button:Hide()
                        self.build_button_root.teaser:SetMultilineTruncatedString(str, 2, (self.panel_width / 2) * 0.8, nil, false, true)
                        return ret
                    end
                end
            end
            local builder = self.owner.replica.builder
            if recipe.dstap_recipe and not recipe.dstap_effect and (
                (DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_BUILD)
                or (DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY and builder:KnowsRecipe(recipe))
            ) then
                -- Hide ingredients since we can make this for free
                if self.ingredients then
                    self.ingredients:Hide()
                    local root = self.ingredients.parent
                    if not root.dstap_freebuild_hint then
	                    root.dstap_freebuild_hint = root:AddChild(Text(GLOBAL.BODYTEXTFONT, 20))
                        root.dstap_freebuild_hint:SetSize(20)
                        root.dstap_freebuild_hint:UpdateOriginalSize()
                        root.dstap_freebuild_hint:SetPosition(self.ingredients:GetPosition())
                        local str = STRINGS.UI.CRAFTING.DSTAP_FREEBUILD_HINT
                        root.dstap_freebuild_hint:SetMultilineTruncatedString(str, 2, (self.panel_width / 2) * 0.8, nil, false, true)
                    end
                end
            end
        end
        return ret
    end
end
AddClassPostConstruct("widgets/redux/craftingmenu_details", CraftingMenuDetailsPostInit)

local Image = require "widgets/image"
local function IngredientUIPostInit(self)
    local recipe = self.recipe_type and GLOBAL.GetValidRecipe(self.recipe_type)
    if recipe ~= nil and recipe.dstap_locked then
        -- Make locked ingredients due to crafting mode red
        if DSTAP.craftingmode == DSTAP.CRAFT_MODES.LOCKED_INGREDIENTS then
            self.dstap_locked_ingredient = true -- Allow ingredients widget to be aware of this being locked
            -- Make background red
            if self.image then
                self.image:SetTexture(GLOBAL.resolvefilepath("images/hud.xml"), "resource_needed.tex")
            end
        end
        -- Replace lock icon with ap icon if it exists
        if self.fg then
            if self.fg.texture == "ingredient_lock.tex" then
                self.fg:SetTexture("images/dstap_craftslot.xml", "dstap_craftslot.tex")
                self.fg:ScaleToSize(self.ing:GetSize())
            end
        elseif DSTAP.craftingmode == DSTAP.CRAFT_MODES.LOCKED_INGREDIENTS then
            -- Make an ap icon
			self.fg = self.image:AddChild(Image("images/dstap_craftslot.xml", "dstap_craftslot.tex"))
			self.fg:ScaleToSize(self.ing:GetSize())
        end
    end
end
AddClassPostConstruct("widgets/ingredientui", IngredientUIPostInit)

require "widgets/widgetutil"
-- Announce that something is ap locked when you click it
local DoRecipeClick_prev = GLOBAL.DoRecipeClick
-- return values: "keep_crafting_menu_open", "error message"
GLOBAL.DoRecipeClick = function(owner, recipe, ...) --widgetutil.lua [38]
    local builder = owner.replica.builder
    local freecrafting = builder:IsFreeBuildMode()

    if recipe.dstap_locked == true 
    and not freecrafting == true 
    and not builder:IsBuildBuffered(recipe.name)
    then
        local stringname = "DSTAP_LOCKED"
        -- Set it to a hint if there is one
        if STRINGS.CHARACTERS.GENERIC.ANNOUNCE_CANNOT_BUILD["DSTAP_HINT_"..recipe.dstap_item_id] then
            stringname = "DSTAP_HINT_"..recipe.dstap_item_id
        end
        --
        return true, stringname
    end

    return DoRecipeClick_prev(owner, recipe, ...)

end

-- Lets unlocked ap recipes be prototypable
local CanPrototypeRecipe_prev = GLOBAL.CanPrototypeRecipe
GLOBAL.CanPrototypeRecipe = function(recipetree, ...)
    local aplevel = recipetree and recipetree.DSTAP_TECH
	if aplevel then
		return aplevel <= 2
	end 
    return CanPrototypeRecipe_prev(recipetree, ...)
end


local function BuilderPostInit(self, inst)
    -- Custom functions    
    function self:DSTAP_GiveFreeSamples()
        if DSTAP.craftingmode ~= DSTAP.CRAFT_MODES.FREE_SAMPLES then
            return
        end
        for recname, recipe in pairs(Recipes) do
            if GLOBAL.IsRecipeValid(recname) 
            and not self:IsBuildBuffered(recname)
            and not self:KnowsRecipe(recname)
            and recipe.dstap_recipe
            and recipe.dstap_locked == false
            and not recipe.dstap_effect
            then
                if recipe.placer ~= nil then
                    -- Manually buffer build
                    self:AddRecipe(recname)
                    self.buffered_builds[recname] = true
                    self.inst.replica.builder:SetIsBuildBuffered(recname, true)
                else
                    -- Make a fake buffer for inventory items
                end
            end
        end
    end
    
    -- Set ap recipes to not known, so you can prototype them
    local KnowsRecipe_prev = self.KnowsRecipe
    function self:KnowsRecipe(recipe, ...)
        local recipe_prev = recipe
        if type(recipe) == "string" then
            recipe = GLOBAL.GetValidRecipe(recipe)
        end

        if recipe ~= nil and recipe.dstap_recipe then
            if self.freebuildmode then
                return true
            elseif recipe.builder_tag ~= nil and not self.inst:HasTag(recipe.builder_tag) then
                return false
            elseif self.station_recipes[recipe.name] or table.contains(self.recipes, recipe.name) then
                return true
            end
            return false
        end
        return KnowsRecipe_prev(self, recipe_prev, ...)
    end
    
    -- Let ap research items give you stuff instead of making an actual thing
    local DoBuild_prev = self.DoBuild
    function self:DoBuild(recname, ...)
        local recipe = GLOBAL.GetValidRecipe(recname)
        -- Research items
        if recipe ~= nil and recipe.dstap_location and self:HasIngredients(recipe) then
            if not DSTAP.missinglocations[recipe.dstap_location.id] then
                return false, "DSTAP_ALREADY_HAVE_LOCATION"
            end
            if recipe.canbuild ~= nil then
                local success, msg = recipe.canbuild(recipe, self.inst, pt, rotation)
                if not success then
                    return false, msg
                end
            end
            self.inst:PushEvent("refreshcrafting")

            DSTAP.CollectLocationByID(recipe.dstap_location.id)
			local materials, discounted = self:GetIngredients(recname)
			self:RemoveIngredients(materials, recname, discounted)
            return true

        -- Season helper items
        elseif recipe ~= nil and recipe.dstap_effect and self:HasIngredients(recipe) then
            local success, failstr = recipe.dstap_effect(self.inst)
            if not success then
                return false, failstr
            end
			local materials, discounted = self:GetIngredients(recname)
			self:RemoveIngredients(materials, recname, discounted)
            return true
        end

        return DoBuild_prev(self, recname,...)
    end
    
    local BufferBuild_prev = self.BufferBuild
    function self:BufferBuild(recname, ...)
        -- Workaround to get journey mode to cost resources when buffering
        local recipe = GLOBAL.GetValidRecipe(recname)
        if DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY
        and not self:KnowsRecipe(recname)
        and recipe.dstap_recipe
        and not recipe.dstap_effect then
            self.dstap_forceingredientcost = true
            self.inst:DoTaskInTime(0,function()
                self.dstap_forceingredientcost = nil
            end)
        end
        return BufferBuild_prev(self, recname, ...)
	end

    local RemoveIngredients_prev = self.RemoveIngredients
    function self:RemoveIngredients(ingredients, recname, ...)
        local recipe = GLOBAL.GetValidRecipe(recname)
        if recipe ~= nil and recipe.dstap_recipe and not recipe.dstap_effect then
            -- Don't remove ingredients on freebuild crafting mode
            if DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_BUILD then
                return
            end

            -- Don't remove ingredients on journey crafting mode if you made the recipe before
            if DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY and self:KnowsRecipe(recipe) and not self.dstap_forceingredientcost then
                return
            end
            
            -- Don't remove ingredients on free sample crafting mode if you haven't made the recipe before
            if DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_SAMPLES and not self:KnowsRecipe(recipe) and not recipe.placer then
                return
            end
        end
        return RemoveIngredients_prev(self, ingredients, recname, ...)
	end

    local HasIngredients_prev = self.HasIngredients
    function self:HasIngredients(recipe, ...)
        local recipe_prev = recipe
        if type(recipe) == "string" then 
            recipe = GLOBAL.GetValidRecipe(recipe)
        end
        if recipe ~= nil and recipe.dstap_recipe then
            if not recipe.dstap_effect then
                -- Always have ingredients on freebuild crafting mode
                if DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_BUILD then
                    return true
                end
                -- Always have ingredients on journey crafting mode if you made the recipe before
                if DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY and self:KnowsRecipe(recipe) then
                    return true
                end
                -- -- Always have ingredients on free sample crafting mode if you haven't made the recipe before
                if DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_SAMPLES and not self:KnowsRecipe(recipe) and not recipe.placer then
                    return true
                end
            end
            -- Lock on lock ingredients crafting mode
            if DSTAP.craftingmode == DSTAP.CRAFT_MODES.LOCKED_INGREDIENTS then
                for _, v in ipairs(recipe.ingredients) do
                    ingredient_recipe = GLOBAL.GetValidRecipe(v.type)
                    if ingredient_recipe and ingredient_recipe.dstap_locked then
                        return false
                    end
                end
            end
        end
        return HasIngredients_prev(self, recipe_prev, ...)
	end
end
AddComponentPostInit("builder", BuilderPostInit)

local function BuilderReplicaPostInit(self, inst)
    -- Set ap recipes to not known, so you can prototype them
    local KnowsRecipe_prev = self.KnowsRecipe
    function self:KnowsRecipe(recipe, ...)
        local recipe_prev = recipe
        if type(recipe) == "string" then
            recipe = GLOBAL.GetValidRecipe(recipe)
        end

        if recipe ~= nil and recipe.dstap_recipe then
            if self.inst.components.builder ~= nil then
                return self.inst.components.builder:KnowsRecipe(recipe, ...)
            elseif self.classified ~= nil then
                if self.classified.isfreebuildmode:value() then
                    return true
                elseif recipe.builder_tag ~= nil and not self.inst:HasTag(recipe.builder_tag) then
                    return false
                elseif self.classified.recipes[recipe.name] ~= nil and self.classified.recipes[recipe.name]:value() then
                    return true
                end
                return false
            end
        end
        return KnowsRecipe_prev(self, recipe_prev, ...)
    end
    local HasIngredients_prev = self.HasIngredients
    function self:HasIngredients(recipe, ...)
        local recipe_prev = recipe
        if self.inst.components.builder ~= nil then
            return HasIngredients_prev(self, recipe_prev, ...)
        elseif self.classified ~= nil then
            if type(recipe) == "string" then 
                recipe = GLOBAL.GetValidRecipe(recipe)
            end
            if recipe ~= nil and recipe.dstap_recipe then
                if not recipe.dstap_effect then
                    -- Always have ingredients on freebuild crafting mode
                    if DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_BUILD then
                        return true
                    end
                    -- Always have ingredients on journey crafting mode if you made the recipe before
                    if DSTAP.craftingmode == DSTAP.CRAFT_MODES.JOURNEY and self:KnowsRecipe(recipe) then
                        return true
                    end
                    -- Always have ingredients on free sample crafting mode if you haven't made the recipe before
                    if DSTAP.craftingmode == DSTAP.CRAFT_MODES.FREE_SAMPLES and not self:KnowsRecipe(recipe) and not recipe.placer then
                        return true
                    end
                end
                -- Lock on lock ingredients crafting mode
                if DSTAP.craftingmode == DSTAP.CRAFT_MODES.LOCKED_INGREDIENTS then
                    for _, v in ipairs(recipe.ingredients) do
                        ingredient_recipe = GLOBAL.GetValidRecipe(v.type)
                        if ingredient_recipe and ingredient_recipe.dstap_locked then
                            return false
                        end
                    end
                end
            end
        end
        return HasIngredients_prev(self, recipe_prev, ...)
    end
end
AddClassPostConstruct("components/builder_replica", BuilderReplicaPostInit)

local function onentitydeath(world, data)
    local loc = DSTAP.PREFAB_TO_COMBAT_LOCATION[data.inst.prefab]
    if loc then
        if loc.tags["boss"] then
            -- Give boss kills regardless of distance
            DSTAP.CollectLocationByInst(data.inst, "combat")
        else
            local nearbyplayer = GLOBAL.FindEntity(data.inst, DSTAP.TUNING.COMBAT_LOCATION_RANGE, function(ent) 
                return ent:HasTag("player")
            end)
            if nearbyplayer then
                DSTAP.CollectLocationByInst(data.inst, "combat")
            end
        end
    end
end


AddPrefabPostInitAny(function(inst)
    if inst ~= GLOBAL.TheWorld then return end
    -- We are the world

    if GLOBAL.TheWorld.ismastersim then
        inst:ListenForEvent("entity_death", onentitydeath)
        inst:ListenForEvent("dstapfoundlocation", function(world, data)
            -- print("dstapfoundlocation", data.source)
            DSTAP.OnFindLocation(data.id)
        end)
        
        -- Chess unlocks when getting chesspiece sketches
        local unlockchess = function(chesspiecename)
            return function(world, amount)
                if not amount or amount == 0 then
                    return
                end
                GLOBAL.TheWorld:PushEvent("ms_unlockchesspiece", chesspiecename)
            end
        end

        inst:ListenForEvent("dstap_chesspiece_bishop_sketch_changed", unlockchess("bishop"))
        inst:ListenForEvent("dstap_chesspiece_rook_sketch_changed", unlockchess("rook"))
        inst:ListenForEvent("dstap_chesspiece_knight_sketch_changed", unlockchess("knight"))
    end

    -- Caves
    if not GLOBAL.TheWorld.ismastershard then
        inst:ListenForEvent("ms_newmastersessionid", function(world, data)
            -- Resend scout location
            for loc_id, istrue in pairs(DSTAP._locationscouts) do
                if istrue then 
                    DSTAP._locationscouts[loc_id] = nil
                    DSTAP.ScoutLocation(loc_id)
                end
            end
        end)  
    end

    if not GLOBAL.TheWorld.ismastershard then return end
    -- We are the master shard

    inst:AddComponent("dstapmanager")
    local dstapmanager = inst.components.dstapmanager
   
    inst:DoStaticPeriodicTask(2, function()
        local ping = dstapmanager.ping
        DSTAP.SendCommandToAllShards("updateinterfacestate", tostring(ping), true)
        -- SendModRPCToShard(GetShardModRPC("archipelago", "oncommandfrommaster"), GLOBAL.SHARDID.MASTER, "updateinterfacestate", tostring(ping))
    end)

    GLOBAL.ChatHistory:AddChatHistoryListener(function(chatter)
        -- print(GLOBAL.PrintTable(chatter))
        if chatter.type == ChatTypes.Message then

            if chatter.m_color == GLOBAL.WHISPER_COLOR then return end

            if string.sub(chatter.message, 0, 1) == "!" then -- User is running a AP command
                if string.sub(chatter.message, 0, 8) == "!missing" then --TODO:Do this for !checked as well
                    GLOBAL.TheWorld:DoTaskInTime(0, function()
                        local filter = string.lower(string.sub(chatter.message, 10))
                        local total = 0
                        local found = 0
                        for _, id in pairs(DSTAP.missinglocations) do
                            local loc = DSTAP.ID_TO_LOCATION[id]
                            if loc then
                                local name = string.lower(loc.prettyname)
                                total = total + 1
                                if string.find(k, filter) ~= nil or (name ~= nil and (string.find(name, filter) ~= nil) or false) then
                                    found = found + 1
                                    GLOBAL.TheNet:Announce(name ~= nil and name or k)
                                end
                            end
                        end
                        GLOBAL.TheNet:Announce(tostring(found).."/"..tostring(total).." missing location groups match filter.")
                    end)
                else
                    dstapmanager:SendSignal("Chat", {msg = DSTAP.FilterOutSpecialCharacters(chatter.message)})
                end

            else
                dstapmanager:SendSignal("Chat", {msg = DSTAP.FilterOutSpecialCharacters(chatter.sender..": "..chatter.message)})
            end

        elseif chatter.type == ChatTypes.Announcement then

            if chatter.icondata == "Join_game" then
                dstapmanager:SendSignal("Join", {msg = DSTAP.FilterOutSpecialCharacters(chatter.message)})

            elseif chatter.icondata == "Leave_game" then
                dstapmanager:SendSignal("Leave", {msg = DSTAP.FilterOutSpecialCharacters(chatter.message)})

            -- elseif chatter.icondata == "death" then
            --     dstapmanager:SendSignal("Death", {msg = DSTAP.FilterOutSpecialCharacters(chatter.message)})

            end
        end
    end)
end)

local function NewTaught(inst, doer, diduse, ...)
    if diduse then
        if GLOBAL.TheWorld.ismastershard then
            DSTAP.FreeHint()
        else
            SendModRPCToShard(GetShardModRPC("archipelago", "onfreehint"), GLOBAL.SHARDID.MASTER)
        end
    end

    if inst.oldtaught ~= nil then
        inst.oldtaught(inst, doer, diduse, ...)
    end
end

AddPrefabPostInit("scrapbook_page", function(inst)
    -- if GLOBAL.TheWorld.ismastershard then
        inst.oldtaught = inst.OnScrapbookDataTaught
        inst.OnScrapbookDataTaught = NewTaught
    -- end
end)

------------------------
local BlueprintPostInitFnsByRecipe = {}
function TurnBlueprintToLocation(prefab, loc_id)
    if loc_id < DSTAP.RAW.LOCATION_ID_OFFSET then
        loc_id = loc_id + DSTAP.RAW.LOCATION_ID_OFFSET
    end
    
    local reverseBlueprintPostInit = function(inst)
        if inst.dstap_location_set then
            return
        end
        inst.dstap_location_set = true
        inst.dstap_lockable_blueprint = nil
        inst:RemoveComponent("spellcaster")
        if not inst.components.teacher then
            inst:AddComponent("teacher")
        end
        inst.components.teacher:SetRecipe(inst.recipetouse)
        inst.components.teacher.onteach = inst.dstap_old_onteach
        if inst.components.named then 
            inst.components.named:SetName(inst.dstap_old_name)
        end
    end

    local setBlueprintIsLocked = function(inst)
        if not DSTAP.all_locations or DSTAP.all_locations[loc_id] then
            -- Only set if this isn't a check
            return
        end
        local recipe = Recipes[inst.recipetouse]
        local locked = nil
        if recipe then
            locked = recipe.dstap_locked ~= nil
        end
        if inst.dstap_lockable_blueprint == locked then
            return
        end
        if locked then
            if inst.components.teacher then
                inst.components.teacher:SetRecipe(nil)
            end
            if inst.components.named then 
                inst.components.named:SetName(STRINGS.NAMES.DSTAP_BLUEPRINT_LOCKED)
            end
        else
            if inst.components.teacher then
                inst.components.teacher:SetRecipe(inst.recipetouse)
            end
            if inst.components.named then 
                inst.components.named:SetName(inst.dstap_old_name)
            end
        end
        inst.dstap_lockable_blueprint = locked
    end

    BlueprintPostInitFnsByRecipe[prefab] = function(inst)
        if not GLOBAL.TheWorld.ismastersim then
            return
        end

        -- Save old details in case we want to restore this
        inst.dstap_old_onteach = inst.components.teacher.onteach
        inst.dstap_old_name = inst.components.named.name

        if not DSTAP.all_locations or DSTAP.all_locations[loc_id] then
            --
            local loc = DSTAP.ID_TO_LOCATION[loc_id]

            -- Set name when location info is set
            local onlocationinfo = function(wrld, loc_info)
                if loc_info.id == loc_id then
                    inst.components.named:SetName((loc_info.playername or "Someone").."'s "..(loc_info.itemname or "Item").." ("..(loc and loc.prettyname or "Unknown")..")")
                    -- Set description based on item class
                    if inst.components.inspectable then
                        inst.components.inspectable.nameoverride = "dstap_blueprint"
                        local mod = "GENERIC"
                        if not DSTAP.missinglocations[loc_id] then
                            mod = "COLLECTED"
                        elseif loc_info.flags == 1 or loc_info.flags == 3 then
                            mod = "PROGRESSION"
                        elseif loc_info.flags == 2 then
                            mod = "USEFUL"
                        elseif loc_info.flags == 4 then
                            mod = "TRAP"
                        end 
                        inst.components.inspectable.getspecialdescription = function (inst, viewer)
                            if not viewer:HasTag("playerghost") then
                                return GLOBAL.GetDescription(viewer, inst, mod)
                            end
                            return GLOBAL.GetDescription(viewer, inst)
                        end
                    end
                end
            end
            inst:ListenForEvent("dstap_location_info_set", onlocationinfo, GLOBAL.TheWorld)

            -- Set default name
            if not inst.components.named then inst:AddComponent("named") end
            local loc_info = DSTAP.LOCATION_INFO[loc_id]
            if loc_info then
                onlocationinfo(nil, loc_info)
            else
                inst.components.named:SetName(STRINGS.NAMES.DSTAP_BLUEPRINT.." ("..(loc and loc.prettyname or "Unknown")..")")
                DSTAP.ScoutLocation(loc_id)
            end
            
            -- Make into a spell
            inst:AddComponent("spellcaster")
            inst.components.spellcaster:SetSpellFn(function (inst, target, pos, doer)
                -- if not GLOBAL.TheWorld.dstap_state then 
                --     print("Tried to use blueprint while disconnected!")
                --     if doer.components.talker then
                --         doer.components.talker:Say(GLOBAL.GetString(doer, "ANNOUNCE_DSTAP_DISCONNECTED"))
                --     end
                --     return
                -- end
                if not DSTAP.missinglocations[loc_id] then
                    -- We already have this one
                    if doer and doer.components.talker then
                        doer.components.talker:Say(GLOBAL.GetString(doer, "ANNOUNCE_ARCHIVE_OLD_KNOWLEDGE"))
                    end
                end
                DSTAP.CollectLocationByID(loc_id)
                inst:Remove()
            end)
            inst.components.spellcaster.canusefrominventory = true

            inst:RemoveComponent("teacher") -- Make not a learnable blueprint anymore

            -- Since all_locations may or may not be initialized, make restorable if turns out this isn't a location we need
            if not DSTAP.all_locations then
                local callbackfn = function(wrld, data)
                    if DSTAP.all_locations then
                        -- all_locations has been set, so we're certain whether or not we want this or not
                        if not DSTAP.all_locations[loc_id] then
                            reverseBlueprintPostInit(inst)
                            setBlueprintIsLocked(inst)
                        end
                        inst:DoTaskInTime(0.1, inst.dstap_removerestorecallback)
                    end
                end
                inst.dstap_removerestorecallback = function() inst:RemoveEventCallback("dstap_all_locations_set", callbackfn, GLOBAL.TheWorld) end
                inst:ListenForEvent("dstap_all_locations_set", callbackfn, GLOBAL.TheWorld)
            end
        end

        -- Lock this recipe if it's one of our locked items
        local on_lockableitems_set = function()
            setBlueprintIsLocked(inst)
        end
        inst:ListenForEvent("dstap_lockableitems_set", on_lockableitems_set, GLOBAL.TheWorld)
        on_lockableitems_set()

    end
    AddPrefabPostInit(prefab.."_blueprint", BlueprintPostInitFnsByRecipe[prefab]) 
end

function TurnBlueprintToCombatLocationFromPrefab(prefab, loc_prefab)
    local loc = DSTAP.PREFAB_TO_COMBAT_LOCATION[loc_prefab]
    if loc then
        TurnBlueprintToLocation(prefab, loc.id)
    end
end

AddPrefabPostInit("blueprint", function(inst) -- Because it gets converted to a regular blueprint prefab
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    local OnLoad_prev = inst.OnLoad
    inst.OnLoad = function(...)
        local ret = OnLoad_prev(...)
        if inst.recipetouse then
            local fn = BlueprintPostInitFnsByRecipe[inst.recipetouse]
            if fn then fn(inst) end
        end
        return ret
    end
end)

-- Wagstaff blueprints
TurnBlueprintToLocation("moonstorm_goggleshat", 4)
TurnBlueprintToLocation("moon_device_construction1", 4)
-- -- Auto-Mat-O-Chanic
-- TurnBlueprintToLocation("wagpunkbits_kit", abandoned_junk_id) -- Uncomment when Abandoned Junk is added
-- Pearl blueprints
TurnBlueprintToLocation("winch", 851)
TurnBlueprintToLocation("carpentry_station", 851)
-- Moon quay blueprints (turf not included). Don't think it needs anything else special
TurnBlueprintToLocation("boat_cannon_kit", 5)
TurnBlueprintToLocation("cannonball_rock_item", 5)
TurnBlueprintToLocation("dock_kit", 5)
TurnBlueprintToLocation("dock_woodposts_item", 5)
-- Archive blueprints
TurnBlueprintToLocation("turfcraftingstation", 1)
TurnBlueprintToLocation("archive_resonator_item", 2)
TurnBlueprintToLocation("refined_dust", 3)
-- End Table
TurnBlueprintToLocation("endtable", 9)
-- Pirate Stash blueprints
TurnBlueprintToLocation("pirate_flag_pole", 10)
TurnBlueprintToLocation("polly_rogershat", 10)
-- Desert Goggles mapped to Oasis
TurnBlueprintToLocation("deserthat", 12)
-- Bosses
TurnBlueprintToCombatLocationFromPrefab("townportal", "antlion")
TurnBlueprintToCombatLocationFromPrefab("antlionhat", "antlion")
TurnBlueprintToCombatLocationFromPrefab("bundlewrap", "beequeen")
TurnBlueprintToCombatLocationFromPrefab("dragonflyfurnace", "dragonfly")
TurnBlueprintToCombatLocationFromPrefab("trident", "crabking")
TurnBlueprintToCombatLocationFromPrefab("sleepbomb", "toadstool")
TurnBlueprintToCombatLocationFromPrefab("mushroom_light", "toadstool")
TurnBlueprintToCombatLocationFromPrefab("mushroom_light2", "toadstool")
TurnBlueprintToCombatLocationFromPrefab("red_mushroomhat", "toadstool")
TurnBlueprintToCombatLocationFromPrefab("green_mushroomhat", "toadstool")
TurnBlueprintToCombatLocationFromPrefab("blue_mushroomhat", "toadstool")
TurnBlueprintToCombatLocationFromPrefab("support_pillar_scaffold", "minotaur")
TurnBlueprintToCombatLocationFromPrefab("support_pillar_dreadstone_scaffold", "daywalker")
TurnBlueprintToCombatLocationFromPrefab("wall_dreadstone_item", "daywalker")
TurnBlueprintToCombatLocationFromPrefab("armordreadstone", "daywalker")
TurnBlueprintToCombatLocationFromPrefab("dreadstonehat", "daywalker")
-- Replica relic blueprints mapped to Resting Horror
for _, v in ipairs(DSTAP.RAW.BUNDLE_DEFS.replicarelics) do
    TurnBlueprintToCombatLocationFromPrefab(v, "ruins_shadeling")
end

-- Ensure that the player gets the blueprint from distilled knowledge
AddPrefabPostInit("archive_lockbox", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return inst
    end
    
    inst:ListenForEvent("onteach", function(inst)
        inst:DoTaskInTime(176/30, function() -- Waiting slightly later than the default
            local recipe = inst.product_orchestrina
            if recipe == "archive_resonator" then
                recipe = "archive_resonator_item"
            end

            -- Check if it gave a blueprint
            local pos = GLOBAL.Vector3(inst.Transform:GetWorldPosition())
            local players = GLOBAL.FindPlayersInRange( pos.x, pos.y, pos.z, 20, true )
            for i,player in ipairs(players) do
                if player and player.components.inventory then
                    if player.components.inventory:FindItem(function(item)
                        if item.prefab == recipe.."_blueprint" or (item.prefab == "blueprint" and item.recipetouse == recipe) then
                            return item
                        end
                    end) then
                        print("Player already has this blueprint for", recipe)
                    else
                        -- Player must've learned it already, so giving it again
                        print("Player didn't get blueprint for", recipe, "Giving it now!")
                        player.components.inventory:GiveItem(GLOBAL.SpawnPrefab(recipe .. "_blueprint"))
                    end
                end
            end
        end)
    end)
end)

-- Ensure that the player gets the blueprint from Wagstaff
AddPlayerPostInit(function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    
    inst:DoTaskInTime(0.1, function()
        if not inst.components.timer then
            print("ERROR: Failed to post init wagstaff timer thingy because no timer on player!")
            return
        end
        local Timer = inst.components.timer
        local StartTimer_prev = Timer.StartTimer
        function Timer:StartTimer(name,...)
            if name == "wagstaff_npc_blueprints" then
                local ent = GLOBAL.FindEntity(inst, 20, function(thing)
                    return thing.prefab == "moonstorm_goggleshat_blueprint" or thing.prefab == "moon_device_construction1_blueprint"
                    or (thing.prefab == "blueprint" and (thing.recipetouse == "moonstorm_goggleshat" or thing.recipetouse == "moon_device_construction1"))
                end)
                if not ent then
                    print("Wagstaff didn't give anything. Here, let me give you this!")
                    local dropper = GLOBAL.FindEntity(inst, 20, function(thing)
                        return thing.prefab == "wagstaff_npc"
                    end) or inst
                    local x, y, z = dropper:GetPosition():Get()
                    local blueprint = GLOBAL.SpawnPrefab("moonstorm_goggleshat_blueprint")
                    blueprint.components.inventoryitem:DoDropPhysics(x, y, z, true)
                else
                    print("You already have the blueprint(s). You get nothing!")
                end
            end

            return StartTimer_prev(self,name,...)
        end
    end)
end)


-- Locations when reaching minhealth
function LocationOnMinHealth(prefab)
    local onminhealth = function(inst, data)
        DSTAP.CollectLocationByInst(inst, "combat")
    end
    AddPrefabPostInit(prefab, function(inst)
        if not GLOBAL.TheWorld.ismastersim then
            return
        end
        inst:ListenForEvent("minhealth", onminhealth)
    end)
end

LocationOnMinHealth("sharkboi")
LocationOnMinHealth("daywalker")
LocationOnMinHealth("daywalker2")

-- Pig King location
AddPrefabPostInit("pigking", function(inst)
    if not GLOBAL.TheWorld.ismastersim or not inst.components.trader then
        return
    end
    local onaccept_prev = inst.components.trader.onaccept
    inst.components.trader.onaccept = function(...)
        DSTAP.CollectTaskLocation("Pig King")
        if onaccept_prev then
            return onaccept_prev(...)
        end
    end
    local onrefuse_prev = inst.components.trader.onrefuse
    -- Allow Wurt to get the check
    inst.components.trader.onrefuse = function(inst, giver)
        if giver:HasTag("merm") then
            DSTAP.CollectTaskLocation("Pig King")
        end
        if onrefuse_prev then
            return onrefuse_prev(inst, giver)
        end
    end
end)

-- Check locations when a trade is accepted
AddComponentPostInit("trader", function (self, inst)
    local AcceptGift_prev = self.AcceptGift
    function self:AcceptGift(...)
        local accepted = AcceptGift_prev(self, ...)
        if accepted then
            local loc = DSTAP.PREFAB_TO_COMBAT_LOCATION[inst.prefab]
            -- Non-boss creatures only
            if loc and loc.tags["creature"] then
                DSTAP.CollectLocationByID(loc.id)
            end
        end
        return accepted
    end
end)

-- Pirate Stash check when dug
AddPrefabPostInit("pirate_stash", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    local onfinish = function(inst, data)
        DSTAP.CollectTaskLocation("Pirate Stash")
    end
    inst:ListenForEvent("workfinished", onfinish)
end)

-- Powder Monkey and Prime Mate checks when diving/sinking
local function LocationOnSink(sg)
    AddStategraphPostInit(sg, function(self)
        local divestate = self.states["dive"]
        if divestate then
            local onenter_prev = divestate.onenter
            divestate.onenter = function(inst, ...)
                --print("Monkey is diving. Awarding check")
                DSTAP.CollectLocationByInst(inst, "combat")
                if onenter_prev then
                    return onenter_prev(inst, ...)
                end
            end
        end
        local onsinkevent = self.events["onsink"]
        if onsinkevent then
            local fn_prev = onsinkevent.fn
            onsinkevent.fn = function(inst, ...)
                --print("Monkey is sinking. Awarding check")
                DSTAP.CollectLocationByInst(inst, "combat")
                if fn_prev then
                    return fn_prev(inst, ...)
                end
            end
        end
    end)
end
LocationOnSink("powdermonkey")
LocationOnSink("primemate")

-- Poison Birchnut Tree
AddPrefabPostInit("deciduoustree", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    local onfinish = function(inst, data)
        if inst.monster then
            DSTAP.CollectTaskLocation("Poison Birchnut Tree")
        end
    end
    inst:ListenForEvent("workfinished", onfinish)
    inst:ListenForEvent("onburnt", onfinish)
end)

-- Mandrake
AddPrefabPostInit("mandrake_active", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    local onpicked_prev = inst.onpicked
    inst.onpicked = function(...)
        DSTAP.CollectLocationByInst(inst, "combat")
        if onpicked_prev then
            onpicked_prev(...)
        end
    end
end)

-- W.O.B.O.T.
AddPrefabPostInit("storage_robot", function(inst)
    if not GLOBAL.TheWorld.ismastersim or not inst.components.forgerepairable then
        return
    end
    -- Give check when repaired
    local onrepaired_prev = inst.components.forgerepairable.onrepaired
    inst.components.forgerepairable.onrepaired = function(...)
        DSTAP.CollectTaskLocation("W.O.B.O.T.")
        if onrepaired_prev then
            return onrepaired_prev(...)
        end
    end
end)

-- Sea Weed
AddPrefabPostInit("waterplant", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    -- Give check when shaved or harvested
    if inst.components.shaveable then
        local on_shaved_prev = inst.components.shaveable.on_shaved
        inst.components.shaveable.on_shaved = function(...)
            DSTAP.CollectLocationByInst(inst, "combat")
            if on_shaved_prev then
                return on_shaved_prev(...)
            end
        end
    end
    if inst.components.harvestable then
        local onharvestfn_prev = inst.components.harvestable.onharvestfn
        inst.components.harvestable.onharvestfn = function(...)
            DSTAP.CollectLocationByInst(inst, "combat")
            if onharvestfn_prev then
                return onharvestfn_prev(...)
            end
        end
    end
end)

-- Make bosses take more damage when player has Extra Damage Against Bosses
local function ApplyBossDamageMult(prefab, israidboss)
    AddPrefabPostInit(prefab, function(inst)
        if not GLOBAL.TheWorld.ismastersim or not inst.components.combat then
            return
        end
        if inst:HasTag("companion") then
            return -- Don't make friendly grumble bees vulnerable
        end
        inst.dstap_refreshbossdamagemult = function(world)
            local exponential = true
            local multiplier = 1
            local addmult = israidboss and DSTAP.TUNING.EXTRA_RAIDBOSS_DAMAGE_STACK_MULT or DSTAP.TUNING.EXTRA_BOSS_DAMAGE_STACK_MULT
            local stacks = DSTAP.TUNING.EXTRA_BOSS_DAMAGE_INITIAL + (DSTAP.abstractitems["extrabossdamage"] or 0)
            if exponential then
                multiplier = math.pow((1 + addmult), stacks)
            else -- additive
                multiplier = multiplier + (stacks * addmult)
            end
            inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, multiplier, "dstap_extrabossdamage")
        end

        inst:dstap_refreshbossdamagemult()
        inst:ListenForEvent("dstap_extrabossdamage_changed", inst.dstap_refreshbossdamagemult, GLOBAL.TheWorld)

        -- --DEBUG delete this
        -- inst:ListenForEvent("attacked", function(inst, data)
        --     local damage = data.damage or 0
        --     local original_damage = data.original_damage or damage
        --     local stacks = DSTAP.abstractitems["extrabossdamage"] or 0
        --     GLOBAL.TheNet:Announce(inst.prefab.." took "..(damage).." damage! Original: "..original_damage.."; You have "..stacks.." buff stacks.")
        -- end)

    end)
end

-- Give location bosses the multiplier
for pref, loc in pairs(DSTAP.PREFAB_TO_COMBAT_LOCATION) do
    if loc.tags["boss"] then
        ApplyBossDamageMult(pref, loc.tags["raidboss"])
    end
end
-- Give aliases of location bosses the multiplier
for pref, bossalias in pairs(DSTAP.RAW.BOSS_DAMAGE_ALIASES) do
    local loc = DSTAP.PREFAB_TO_COMBAT_LOCATION[bossalias]
    if loc then
        ApplyBossDamageMult(pref, loc.tags["raidboss"])
    end
end


-- Farm plant shuffling
local WEIGHTED_SEED_TABLE = require("prefabs/weed_defs").weighted_seed_table
local function pickweed()
    return GLOBAL.weighted_random_choice(WEIGHTED_SEED_TABLE)
end
AddPrefabPostInit("farm_plant_randomseed", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end
    -- Change the identifying function
    if inst.BeIdentified then
        local BeIdentified_prev = inst.BeIdentified
        inst.BeIdentified = function(inst, ...)
            local veggie = BeIdentified_prev(inst, ...)
            
            -- Check if the identified seeds is a locked item
		    local item = DSTAP.PREFAB_TO_RECIPE_ITEM["dstap_"..veggie.."_seeds"]
			if item and DSTAP.lockableitems[item.id] then
                -- Turn it into weeds
                inst._identified_plant_type = pickweed()
                veggie = inst._identified_plant_type
            end

            return veggie
        end
    end
    -- Change the growth stage
    local GROWTH_STAGES = inst.components.growable and inst.components.growable.stages
    if GROWTH_STAGES then
        for k, v in ipairs(GROWTH_STAGES) do
            if v.name == "sprout" and v.fn and inst.BeIdentified and not v.dstap_modded then
                local fn_prev = v.fn
                v.fn = function(inst, ...)
                    -- Check if carrot is locked, because I can't check fn's result before it creates it
                    local item = DSTAP.PREFAB_TO_RECIPE_ITEM["dstap_carrot_seeds"]
                    if item and DSTAP.lockableitems[item.id] then
                        -- Turn it into weeds
                        inst._identified_plant_type = pickweed()
                    end
                    return fn_prev(inst, ...)
                end
                v.dstap_modded = true -- Because I don't think it's a copy, so let's not modify it again
                break
            end
        end
    end
end)

-- Global info tags
local function setGlobalInfoOnExist(globalinfo_key)
    globalinfo_key = globalinfo_key.."_exists"
    return function(inst)
        if not GLOBAL.TheWorld.ismastersim or DSTAP.globalinfo[globalinfo_key] then
            return
        end
        DSTAP.globalinfo[globalinfo_key] = true
        SendModRPCToClient(GetClientModRPC("archipelago", "oncommandfromshard"), nil, nil, "globalinfo", json.encode({[globalinfo_key] = true}))
    end
end
-- Celestial orb
AddPrefabPostInit("rock_moon_shell", setGlobalInfoOnExist("moonrockseed"))
AddPrefabPostInit("moonrockseed", setGlobalInfoOnExist("moonrockseed"))
AddPrefabPostInit("alterguardian_phase1", setGlobalInfoOnExist("moonrockseed"))
AddPrefabPostInit("alterguardian_phase2", setGlobalInfoOnExist("moonrockseed"))
AddPrefabPostInit("alterguardian_phase3", setGlobalInfoOnExist("moonrockseed"))

-- Grass gekko
AddPrefabPostInit("grassgekko", setGlobalInfoOnExist("grassgekko"))

-- Lure Plant
AddPrefabPostInit("lureplant", setGlobalInfoOnExist("lureplant"))
AddPrefabPostInit("lureplantbulb", setGlobalInfoOnExist("lureplant"))

-- Merm
AddPrefabPostInit("merm", setGlobalInfoOnExist("merm"))
AddPrefabPostInit("mermhouse", setGlobalInfoOnExist("merm"))



-- Player post init
AddPlayerPostInit(function(inst)
    inst:DoTaskInTime(1, function()
        if GLOBAL.TheWorld.ismastersim then
            print("Syncing the player")
            SendModRPCToClient(GetClientModRPC("archipelago", "oncommandfromshard"), nil, nil, "updateapstate", GLOBAL.TheWorld.dstap_state)
            SendModRPCToClient(GetClientModRPC("archipelago", "oncommandfromshard"), nil, nil, "setcraftingmode", DSTAP.craftingmode)
            if GLOBAL.TheWorld.ismastershard then
                SendModRPCToClient(GetClientModRPC("archipelago", "oncommandfromshard"), nil, nil, "synclocations")
            else
                DSTAP.SyncFromMasterShard()
            end
        end
    end)
    
    if GLOBAL.TheWorld.ismastersim then
        -- Give check when picking up item
        inst:ListenForEvent("gotnewitem", function(inst, data)
            if data.item then
                DSTAP.CollectLocationByInst(data.item, "combat")
            end
        end)

        -- Send a message to the master shard about days survived
        inst:ListenForEvent("cycleschanged", function(world, data)
            if inst.components.age then
                DSTAP.SendSurvivorAge(inst.components.age:GetAgeInDays())
            end
        end, GLOBAL.TheWorld)
        
        -- Send death link
        inst:ListenForEvent("death", function(inst, data)
            local deathcause = data ~= nil and data.cause or "unknown"
            local deathpkname = nil
            local deathbypet = nil
            if deathcause == "deathlink" then
                return
            end

            if data == nil or data.afflicter == nil then
                deathpkname = nil
            elseif data.afflicter.overridepkname ~= nil then
                deathpkname = data.afflicter.overridepkname
                deathbypet = data.afflicter.overridepkpet
            else
                local killer = data.afflicter.components.follower ~= nil and data.afflicter.components.follower:GetLeader() or nil
                if killer ~= nil and
                    killer.components.petleash ~= nil and
                    killer.components.petleash:IsPet(data.afflicter) then
                    deathbypet = true
                else
                    killer = data.afflicter
                end
                deathpkname = killer:HasTag("player") and killer:GetDisplayName() or nil
            end

            local announcement_string = GLOBAL.GetNewDeathAnnouncementString(inst, deathcause, deathpkname, deathbypet)
            DSTAP.SendDeath(DSTAP.FilterOutSpecialCharacters(announcement_string))
        end)

        -- Add damage bonus
        inst.dstap_refreshdamagebonus = function(world)
            local exponential = true
            local multiplier = 1
            local addmult = DSTAP.TUNING.DAMAGE_BONUS_STACK_MULT
            local stacks = DSTAP.TUNING.DAMAGE_BONUS_INITIAL + (DSTAP.abstractitems["damagebonus"] or 0)
            if exponential then
                multiplier = math.pow((1 + addmult), stacks)
            else -- additive
                multiplier = multiplier + (stacks * addmult)
            end
            inst.components.combat.externaldamagemultipliers:SetModifier(inst, multiplier, "dstap_damagebonus")
        end

        inst:dstap_refreshdamagebonus()
        inst:ListenForEvent("dstap_damagebonus_changed", inst.dstap_refreshdamagebonus, GLOBAL.TheWorld)

        -- Give free samples after builder loads
        local OnNewSpawn_prev = inst.OnNewSpawn
        inst.OnNewSpawn = function(inst, ...)
            if inst.components.builder then
                inst.components.builder:DSTAP_GiveFreeSamples()
            end
            if OnNewSpawn_prev then
                return OnNewSpawn_prev(inst, ...)
            end
        end

        local OnLoad_prev = inst.OnLoad
        inst.OnLoad = function(inst, ...)
            if inst.components.builder then
                inst.components.builder:DSTAP_GiveFreeSamples()
            end
            if OnLoad_prev then
                return OnLoad_prev(inst, ...)
            end
        end
    end
end)


local AP_Button = require "widgets/dstap_button"
local function ControlsPostInit(self)
    self.dstap_button = self.topright_over_root:AddChild(AP_Button(self.owner, self))
    self.dstap_button:SetPosition(-590, -45, 0)
end

AddClassPostConstruct("widgets/controls", ControlsPostInit)

-- Helper function to turn id or prefab into id always
local function _resolve_id_or_prefab_to_id(id_or_prefab)
    if type(id_or_prefab) == "number" then
		if id_or_prefab < DSTAP.RAW.LOCATION_ID_OFFSET then
			id_or_prefab = id_or_prefab + DSTAP.RAW.LOCATION_ID_OFFSET
		end
        return id_or_prefab
    end
    if type(id_or_prefab) == "string" then
        for _, v in ipairs({DSTAP.PREFAB_TO_COMBAT_LOCATION, DSTAP.PREFAB_TO_RESEARCH_LOCATION, DSTAP.PREFAB_TO_FARMING_LOCATION}) do
            local loc = v[id_or_prefab]
            if loc and DSTAP.missinglocations[loc.id] then
                return loc and loc.id
            end
        end
    end
end

-- Helper function to get first missing location in a list
local function _get_first_missing_to_id(scoutlist)
    for _, v in ipairs(scoutlist) do
        -- Resolve by id or prefab
        local loc_id = _resolve_id_or_prefab_to_id(v)

        if loc_id and DSTAP.missinglocations[loc_id] then
            return loc_id
        end
    end
    return nil
end

-- Hint information when you examine a location
require "stringutil"
local GetDescription_AddSpecialCases_prev = GLOBAL.GetDescription_AddSpecialCases
GLOBAL.GetDescription_AddSpecialCases = function(ret, charactertable, inst, item, modifier, ...)
    local ret = GetDescription_AddSpecialCases_prev(ret, charactertable, inst, item, modifier, ...)
    if ret == nil then
        return
    end
    local scout = DSTAP.RAW.LOCATION_SCOUTS[item.prefab]
    -- Turn nil into string
    scout = scout or item.prefab
    -- Turn table into an id
    if scout and type(scout) == "table" then
        scout = _get_first_missing_to_id(scout)
    end
    -- Turn string or id into id
    scout = scout and _resolve_id_or_prefab_to_id(scout)
    -- Should have nil or id at this point
    if scout and type(scout) == "number" and DSTAP.missinglocations[scout] then
        local post = {}
        local data = nil
        local loc_info = DSTAP.LOCATION_INFO[scout]
        local loc_hint_info = DSTAP.LOCATION_HINT_INFO[scout]
        if loc_info then -- From scout
            data = {
                playername = loc_info.playername,
                itemname = loc_info.itemname,
            }
        elseif loc_hint_info then -- From hint
            data = {
                playername = loc_hint_info.receivingname,
                itemname = loc_hint_info.itemname,
            }
        end
        if data then
            table.insert(post, "\n"..(data.playername or "Someone").."'s "..(data.itemname or "Item").." is locked behind this!")
        elseif type(inst) == "table" then
            table.insert(post, GLOBAL.GetString(inst, "ANNOUNCE_DSTAP_MISSING_CHECK"))
        end
        if #post > 0 then
            ret = (ret or "") .. table.concat(post, "")
        end
    end
    return ret
end

local TrackerScreen = require "screens/dstap_trackerscreen"
local function PlayerHUDPostInit(self)
    function self:DSTAP_OpenTrackerScreen()
        self:DSTAP_CloseTrackerScreen()
        self.dstap_trackerscreen = TrackerScreen(self.owner)
        self:OpenScreenUnderPause(self.dstap_trackerscreen)
        return true
    end
    
    function self:DSTAP_CloseTrackerScreen()
        if self.dstap_trackerscreen ~= nil then
            if self.dstap_trackerscreen.inst:IsValid() then
                GLOBAL.TheFrontEnd:PopScreen(self.dstap_trackerscreen)
            end
            self.dstap_trackerscreen = nil
        end
    end
end
AddClassPostConstruct("screens/playerhud", PlayerHUDPostInit)