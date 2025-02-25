local function setToList(t)
    if not t then return {} end
    local ret = {}
    for k, v in pairs(t) do
        if v then
            table.insert(ret, k)
        end
    end
    return ret
end
local function listToSet(t)
    if not t then return {} end
    local ret = {}
    for _, v in ipairs(t) do
        ret[v] = true
    end
    return ret
end
local function isShutDown()
    return PerformingRestart or not InGamePlay()
end
local function OnTick(inst, self)
    if isShutDown() then return end
    if self.startticking then
        self:DoTick()
    elseif InGamePlay() and not IsSimPaused() and self:ArePlayersOnline() then
        self.startticking = true
        if not self.connected then
            inst:DoTaskInTime(10, function()
                self:AnnounceOfflineStatus()
            end)
        end
        inst:DoTaskInTime(10, function()
            self:AnnounceVictoryStatus()
        end)
    end
end
local function TriangleTrashFill(str)
    if str == nil then return end
    str = str:gsub("\\'","'") -- Remove apostrophe escapes because they cause issues and seem redundant
    local length = string.len(str)
    local num = 0
    local add = 0
    while num < length + 3 do
        add = add + 1
        num = num + add
    end
    str = str..string.rep(" ", ((num - length) - 3)).."EOF"
    return str, add
end

local DSTAPManager = Class(function(self, inst)
    self.inst = inst

    self.startticking = false
    self.connected = false
    self.ping = nil

    self.queue = {}
    self.seed = "None"
    self.slotnum = 0
    self.slotname = "Player"
    self.slotdata = {}
    self.physicalitemsthissession = {}
    self.clientversion = "0"
    self.outputdata = {}
    self.connected_timestamp = os.time()
    self.last_send_time = os.time()
    self.sendqueue_bookmark = 0
    self.sendqueue_lowpriority_bookmark = 0

    -- self.inst:DoStaticPeriodicTask(0.1, OnTick, nil, self)
    self.inst:DoStaticPeriodicTask(2, OnTick, nil, self)

    self:ResetOutputData()
end)


function DSTAPManager:ArePlayersOnline()
    return TheWorld.shard ~= nil and TheWorld.shard.components.shard_players:GetNumAlive() > 0
end

function DSTAPManager:AnnounceOfflineStatus()
    if not self.connected then
        if self.seed == "None" or not self.seed then
            TheNet:Announce(STRINGS.ARCHIPELAGO_DST.WORLD_NOT_LINKED_TO_AP)
        else
            TheNet:Announce(STRINGS.ARCHIPELAGO_DST.WORLD_LINKED_TO_AP_BUT_NOT_CONNECTED)
        end
    end
end

function DSTAPManager:AnnounceVictoryStatus()
    local slotdata = self:GetSlotData()
    if slotdata.victory or slotdata.finishedgame then
        TheNet:Announce(self.slotname.." has already completed their goal.")
    end
end

function DSTAPManager:GetLockedItemsV1_0_2_Pristine()
    --print("Creating V1.0.2 pristine")
    local item_local_id_set = {}
    local setitems
    setitems = function(entry, value)
        value = value or nil
        if entry.INDEX then
            item_local_id_set[entry.INDEX] = value 
        end
        if entry.RANGE then
			for i = entry.RANGE[1], entry.RANGE[2] do
                item_local_id_set[i] = value 
            end
        end
        if entry.EXCEPTIONS then
            for k, v in pairs(entry.EXCEPTIONS) do
                setitems(v, not value)
            end
        end
    end
    setitems(ArchipelagoDST.RAW.ITEM_LOCKS_V1_0_2, true)
    local ret = {}
    for k, v in pairs(item_local_id_set) do
        if v then
            table.insert(ret, k + ArchipelagoDST.RAW.ITEM_ID_OFFSET)
        end
    end
    return ret
end

function DSTAPManager:OnSave()
    local data = {
        slotdata = self.slotdata,
        slotnum = self.slotnum or 0,
        slotname = self.slotname or "Player",
    }
    if self.seed then data.seed = self.seed end
    return data
end

function DSTAPManager:OnLoad(data)
    if data.seed then self.seed = data.seed end
    if data.slotdata then self.slotdata = data.slotdata end
    if data.slotname then self.slotname = data.slotname end
    self.slotnum = data.slotnum or 0
    self:ResetOutputData()

    print("Loaded game. Continuing on slot "..self.slotnum.." ("..self.slotname..") with seed "..(self.seed or "None"))
    
    -- Sync data to shards. Since we're just loading, it might just be on the mastershard and we'll have to resync whenever the player connects on the caves
    self:SyncToShards()
end

function DSTAPManager:SyncToShards()
    local slotdata = self:GetSlotData()
    
    if slotdata.craftingmode and not ArchipelagoDST.TUNING.OVERRIDE_CRAFT_MODE then
        ArchipelagoDST.SendCommandToAllShards("setcraftingmode", slotdata.craftingmode)
    end
    if slotdata.missinglocations then
        ArchipelagoDST.SendCommandToAllShards("missinglocations", json.encode(setToList(slotdata.missinglocations)))
    end
    if slotdata.all_locations then
        ArchipelagoDST.SendCommandToAllShards("all_locations", json.encode(setToList(slotdata.all_locations)))
    end
    if slotdata.locked_items then
        ArchipelagoDST.SendCommandToAllShards("lockeditems", json.encode(slotdata.locked_items))
    end
    if slotdata.collecteditems then
        ArchipelagoDST.SendCommandToAllShards("syncitems", json.encode(setToList(slotdata.collecteditems)))
    end

    if slotdata.goal and not slotdata.finishedgame then
        self:SetupGoalType()
    end

    local globalinfo = {}
    local worldmeteorshower = TheWorld.components.worldmeteorshower
    if worldmeteorshower ~= nil then
        globalinfo.moonrockseed_exists = worldmeteorshower.moonrockshell_chance and worldmeteorshower.moonrockshell_chance >= 1
    end
    ArchipelagoDST.SendCommandToAllShards("globalinfo", json.encode(globalinfo))

    for id, _ in pairs(ArchipelagoDST.ID_TO_ABSTRACT_ITEM) do
        local amount = self:CountProgressiveItems(id)
        ArchipelagoDST.SendCommandToAllShards("syncabstract", json.encode({id = id, amount = amount}))
    end

    if slotdata.hintinfo then -- Legacy hint table
        for k, v in pairs(slotdata.hintinfo) do
            ArchipelagoDST.SendCommandToAllShards("hintinfo", json.encode(v))
        end
    end
    if slotdata.hintinfo_by_player then -- New hint table
        for _, infotable in pairs(slotdata.hintinfo_by_player) do
            for k, v in pairs(infotable) do
                ArchipelagoDST.SendCommandToAllShards("hintinfo", json.encode(v))
            end
        end
    end
    if slotdata.locationinfo then
        for k, v in pairs(slotdata.locationinfo) do
            ArchipelagoDST.SendCommandToAllShards("locationinfo", json.encode(v))
        end
    end
    
end

function DSTAPManager:ProcessItemQueue()
    if not self:ArePlayersOnline() then
        return
    end
    
    local slotdata = self:GetSlotData()
    if slotdata.physicalitemqueue then 
        while #slotdata.physicalitemqueue > 0 do
            ArchipelagoDST.SendCommandToAllShards("gotphysical", table.remove(slotdata.physicalitemqueue, 1))
        end
    end
    if slotdata.effectitemqueue and #slotdata.effectitemqueue > 0 then 
        while #slotdata.effectitemqueue > 0 do
            ArchipelagoDST.SendCommandToAllShards("goteffect", table.remove(slotdata.effectitemqueue, 1))
        end
    end
end

function DSTAPManager:GetSlotData(seed)
    local seeddata = self.slotdata[seed or self.seed] or {}
    self.slotdata[seed or self.seed] = seeddata
    local slotdata = seeddata[self.slotnum] or {}
    seeddata[self.slotnum] = slotdata
    return slotdata
end

function DSTAPManager:SetupGoalType()
    local onsurvivorage =  function(inst, age)
        local slotdata = self:GetSlotData()
        if slotdata.daystosurvive and age >= slotdata.daystosurvive then
            self:SetVictory()
        end
    end
    local slotdata = self:GetSlotData()
    local goalinfo = { goal = slotdata.goal }
    if slotdata.goal == "survival" then
         -- Send a message to the server about days survived
        self.inst:ListenForEvent("dstap_survivorage", onsurvivorage)
        goalinfo.daystosurvive = slotdata.daystosurvive
    else
		self.inst:RemoveEventCallback("dstap_survivorage", onsurvivorage)
    end

    if slotdata.goal == "bosses_any" or slotdata.goal == "bosses_all" then
        local goallist = {}
        if slotdata.requiredbosses then
            slotdata.defeatedbosses = slotdata.defeatedbosses or {}
            for _, v in pairs(ArchipelagoDST.PREFAB_TO_COMBAT_LOCATION) do
                if slotdata.requiredbosses[v.prettyname] and not slotdata.defeatedbosses[v.prettyname] then
                    table.insert(goallist, v.id)
                end
            end
            goalinfo.goallist = goallist
        else
            goalinfo.goallist = setToList(slotdata.goallocations)
        end
        ArchipelagoDST.SendCommandToAllShards("missinglocations", json.encode(goallist))
    end
    ArchipelagoDST.SendCommandToAllShards("goalinfo", json.encode(goalinfo))
end

function DSTAPManager:SetVictory()
    self:GetSlotData().victory = true
    self:SendSignal("Victory")
    if not self.connected then
        TheNet:Announce(self.slotname.." has completed their goal! Waiting to connect to Archipelago to claim victory.")
    end
end

function DSTAPManager:OnFindLocation(id)
    local slotdata = self:GetSlotData()
    if not slotdata.missinglocations then
        return 
    end

    local loc = ArchipelagoDST.ID_TO_LOCATION[id]
    if loc and slotdata.requiredbosses and slotdata.requiredbosses[loc.prettyname] then
        self:OnLegacyGoalLocation(id)
    end

    if not slotdata.missinglocations[id] then
        return
    end
    self:SendSignal("Item", {source = id})
    -- if not self.connected then
        ArchipelagoDST.SendCommandToAllShards("removelocations", json.encode({id}))
        slotdata.missinglocations[id] = nil
        if loc then
		    TheNet:Announce("Location checked: "..loc.prettyname)
        end
        if slotdata.goallocations and slotdata.goallocations[id] then
            self:CheckGoalLocationStatus()
        end
    -- end
end
function DSTAPManager:OnLegacyGoalLocation(id)
    local slotdata = self:GetSlotData()
    if slotdata.goal == "bosses_any" or slotdata.goal == "bosses_all" then
        if slotdata.requiredbosses and ArchipelagoDST.ID_TO_LOCATION[id] then
            local locname = ArchipelagoDST.ID_TO_LOCATION[id].prettyname
            -- Legacy boss check (tied only to world)
            slotdata.defeatedbosses = slotdata.defeatedbosses or {}
            if slotdata.requiredbosses[locname] and not slotdata.defeatedbosses[locname] then
                slotdata.defeatedbosses[locname] = true
                self:CheckGoalLocationStatus()
            end
        end
    end
end
function DSTAPManager:CheckGoalLocationStatus()
    local slotdata = self:GetSlotData()
    local victories_have = 0
    local num_victories_needed = 1
    if slotdata.goallocations then
        if not slotdata.missinglocations then 
            return 
        end
        victories_have = #setToList(slotdata.goallocations)
        if slotdata.goal == "bosses_all" then
            num_victories_needed = #setToList(slotdata.goallocations)
        end
        for id, istrue in pairs(slotdata.missinglocations) do
            if istrue and slotdata.goallocations[id] then
                victories_have = victories_have - 1
            end
        end
    else
        if not slotdata.requiredbosses or #setToList(slotdata.requiredbosses) == 0 then
            print("CheckGoalLocationStatus: requiredbosses undefined! Can't determine victory condition")
            return
        end
        if slotdata.goal == "bosses_all" then
            num_victories_needed = #setToList(slotdata.requiredbosses)
        end
        victories_have = #setToList(slotdata.defeatedbosses)
    end
    if victories_have == 0 then
        TheNet:Announce("You have not defeated any required bosses. You have "..(num_victories_needed).." left to go!")
    elseif num_victories_needed <= victories_have then
        self:SetVictory()
    else
        TheNet:Announce(self.slotname.." defeated "..victories_have.." of the required bosses. You have "..(num_victories_needed - victories_have).." left to go!")
    end
end
function DSTAPManager:CountProgressiveItems(id)
    local slotdata = self:GetSlotData()
    return slotdata.physicalitemsgiven and slotdata.physicalitemsgiven[id] or 0
end
function DSTAPManager:GivePhysicalItem(id)
    if self:ArePlayersOnline() then
        ArchipelagoDST.SendCommandToAllShards("gotphysical", id)
    else
        local slotdata = self:GetSlotData()
        slotdata.physicalitemqueue = slotdata.physicalitemqueue or {}
        table.insert(slotdata.physicalitemqueue, id)
    end
end
function DSTAPManager:GiveEffectItem(id)
    if self:ArePlayersOnline() then
        ArchipelagoDST.SendCommandToAllShards("goteffect", id)
    else
        local slotdata = self:GetSlotData()
        slotdata.effectitemqueue = slotdata.effectitemqueue or {}
        table.insert(slotdata.effectitemqueue, id)
    end
end
function DSTAPManager:SendItems(items, isresync)
    local slotdata = self:GetSlotData()
    local givelast = nil
    local abstractitems = {}
    for _, id in ipairs(items) do
        local item = ArchipelagoDST.ID_TO_ITEM[id] -- Check if valid
        if item then
            if not item.tags["dummy"] then
                local giveitem = ( -- Don't give if it's already free
                    item.tags["giveitem"]
                    and ArchipelagoDST.craftingmode ~= ArchipelagoDST.CRAFT_MODES.FREE_SAMPLES 
                    and ArchipelagoDST.craftingmode ~= ArchipelagoDST.CRAFT_MODES.FREE_BUILD
                )
                local iscounted = item.tags["physical"] or item.tags["trap"] or item.tags["junk"] or item.tags["progressive"] or item.tags["abstract"] or giveitem
                local isrecipe = giveitem or not iscounted
                if iscounted then
                    -- Keep track of what you already got, and don't give duplicates!
                    local t1 = slotdata.physicalitemsgiven or {}
                    slotdata.physicalitemsgiven = t1
                    local t2 = self.physicalitemsthissession

                    local items_given_already = t1[id] or 0
                    local items_given_this_session = t2[id] or 0

                    items_given_this_session = items_given_this_session + 1
                    if items_given_this_session > items_given_already then
                        print("Got physical/trap", item.prettyname)
                        if item.tags["physical"] or giveitem then
                            -- This is a physical item
                            self:GivePhysicalItem(id)
                        elseif item.tags["seasontrap"] then
                            -- Give last season change in the list if any
                            givelast = function() ArchipelagoDST.SendCommandToAllShards("goteffect", id) end
                        elseif item.tags["trap"] then
                            -- This is a regular trap. Don't give if giving a whole resync
                            if not isresync then
                                ArchipelagoDST.SendCommandToAllShards("goteffect", id)
                            end
                        elseif item.tags["junk"] then
                            -- This is a random effect
                            self:GiveEffectItem(id)
                        end

                        if item.tags["abstract"] then
                            abstractitems[id] = true                     
                        end

                        TheNet:Announce("Item received: "..item.prettyname)

                        items_given_already = items_given_this_session
                    else
                        --print("Did not give physical/trap", item.prettyname, "because you already got it! Got", items_given_already,". This one's number",items_given_this_session)
                    end
                    t1[id] = items_given_already
                    t2[id] = items_given_this_session
                end
                if isrecipe then
                    slotdata.collecteditems = slotdata.collecteditems or {}
                    if not slotdata.collecteditems[id] then
                        TheNet:Announce("Recipe received: "..item.prettyname)
                    end
                    slotdata.collecteditems[id] = true
                    ArchipelagoDST.SendCommandToAllShards("gotitem", id)
                end
            end
        else
            print("ERROR! No item with id ", id, " is found!")
        end
    end
    if givelast then givelast() end
    for id, _ in pairs(abstractitems) do
        ArchipelagoDST.SendCommandToAllShards("syncabstract", json.encode({id = id, amount = slotdata.physicalitemsgiven and slotdata.physicalitemsgiven[id] or 0}))
    end
end
function DSTAPManager:ManageEvent(datatype, data)
    -- print("Managing event datatype", datatype)
    if datatype == nil and data == nil then return end
    if type(datatype) == "table" and data == nil then data = datatype datatype = data.datatype end

    if datatype == "Chat" then
        if data.msg == nil then return end
        TheNet:Announce(data.msg)

    elseif datatype == "State" then
        if data.connected ~= nil then
            if self.connected ~= data.connected then
                self.connected = data.connected
                if self.connected then
                    if not self._onconnected then
                        self._onconnected = self.inst:DoTaskInTime("5", function()
                            if self.clientversion < ArchipelagoDST.VERSION.CLIENT_VERSION_COMPATIBLE then
                                TheNet:Announce(STRINGS.ARCHIPELAGO_DST.OUTDATED_CLIENT_VERSION)
                            end
                        end)
                    end
                else
                    self:AnnounceOfflineStatus()
                end
                ArchipelagoDST.SendCommandToAllShards("updateapstate", self.connected, true)
            end
        end
        local warnseedchanged = false
        if data.slot then
            if self.seed and self.seed ~= "None" and self.slotnum ~= data.slot then
                warnseedchanged = true
            end
            self.slotnum = data.slot
        end
        if data.slot_name then self.slotname = data.slot_name end
        if data.seed_name then
            if self.seed and self.seed ~= "None" and self.seed ~= data.seed_name then
                warnseedchanged = true
            end
            self.seed = data.seed_name 
        end
        if data.clientversion then self.clientversion = data.clientversion end


        if warnseedchanged then
            TheNet:Announce(STRINGS.ARCHIPELAGO_DST.WARN_DIFFERENT_SEED_OR_SLOT)
        end
        
        local slotdata = self:GetSlotData()
        if data.finished_game == false then
            if slotdata.victory then
                print("You've managed to get victory while offline!")
                self:SendSignal("Victory")
            else
                if data.goal then slotdata.goal = data.goal end
                if data.days_to_survive then slotdata.daystosurvive = data.days_to_survive end
                if data.required_bosses then 
                    slotdata.requiredbosses = listToSet(data.required_bosses)
                elseif data.goal_locations then
                    slotdata.goallocations = listToSet(data.goal_locations)
                end
                self:SetupGoalType()
            end
        elseif data.finished_game == true then
            slotdata.finishedgame = true
        end

        if data.death_link ~= nil then
            local effective_deathlink = data.death_link
            if ArchipelagoDST.TUNING.OVERRIDE_DEATH_LINK then
                effective_deathlink = ArchipelagoDST.TUNING.OVERRIDE_DEATH_LINK == "enabled"
            end 
            self:SendSignal("DeathLink", {enabled = effective_deathlink})
        end

        if data.crafting_mode and not ArchipelagoDST.TUNING.OVERRIDE_CRAFT_MODE then
            local CRAFT_MODES = {
                vanilla =            ArchipelagoDST.CRAFT_MODES.VANILLA,
                journey =            ArchipelagoDST.CRAFT_MODES.JOURNEY,
                free_samples =       ArchipelagoDST.CRAFT_MODES.FREE_SAMPLES,
                free_build =         ArchipelagoDST.CRAFT_MODES.FREE_BUILD,
                locked_ingredients = ArchipelagoDST.CRAFT_MODES.LOCKED_INGREDIENTS,
            }
            if CRAFT_MODES[data.crafting_mode] and slotdata.craftingmode ~= CRAFT_MODES[data.crafting_mode] then
                slotdata.craftingmode = CRAFT_MODES[data.crafting_mode]
                ArchipelagoDST.SendCommandToAllShards("setcraftingmode", slotdata.craftingmode)
            end
        end

    elseif datatype == "Death" then
        if data.msg then
            TheNet:Announce(data.msg)
        end
        ArchipelagoDST.SendCommandToAllShards("deathlink", true)
        
    elseif datatype == "LocationInfo" then
        -- Update location info
        local slotdata = self:GetSlotData()
        slotdata.locationinfo = slotdata.locationinfo or {}
        local infotable = slotdata.locationinfo
        local loc_info = data.location_info
        if loc_info then
            if ArchipelagoDST.ID_TO_LOCATION[loc_info.location] then
                infotable[loc_info.location] = {
                    id = loc_info.location,
                    flags = loc_info.flags,
                    itemname = loc_info.itemname or "something",
                    playername = loc_info.playername or "someone",
                }
                ArchipelagoDST.SendCommandToAllShards("locationinfo", json.encode(infotable[loc_info.location]))
            end
        else print("There's no location info sent") end
        
    elseif datatype == "HintInfo" then
        -- Update location info
        local slotdata = self:GetSlotData()
        slotdata.hintinfo = slotdata.hintinfo or {} -- Legacy
        slotdata.hintinfo_by_player = slotdata.hintinfo_by_player or {}
        local infotable = slotdata.hintinfo
        local index_by_location = false
        if data.receiving_player and data.item then
            infotable[data.item] = nil -- Erase from legacy table
            slotdata.hintinfo_by_player[data.receiving_player] = slotdata.hintinfo_by_player[data.receiving_player] or {}
            infotable = slotdata.hintinfo_by_player[data.receiving_player]
            local index_by_location = true
        end
        local hint = {
            item = data.item,
            item_is_local = (not data.receiving_player or data.receiving_player == self.slotnum) and true or false,
            location = data.location,
            location_is_local = (not data.finding_player or data.finding_player == self.slotnum) and true or false,
            locationname = data.locationname or "Somewhere",
            itemname = data.itemname or "Something",
            finding_player = data.finding_player,
            findingname = data.findingname or "Someone",
            receiving_player = data.receiving_player,
            receivingname = data.receivingname or "Someone",
        }
        if hint.item and not index_by_location then -- Legacy
            infotable[hint.item] = hint
            ArchipelagoDST.SendCommandToAllShards("hintinfo", json.encode(infotable[hint.item]))
        elseif hint.location and index_by_location then
            infotable[hint.location] = hint
            ArchipelagoDST.SendCommandToAllShards("hintinfo", json.encode(infotable[hint.location]))
        end

    elseif datatype == "Items" then
        local slotdata = self:GetSlotData()
        if data.locked_items_local_id and #data.locked_items_local_id > 0 then
            slotdata.locked_items = {}
            for _, id in pairs(data.locked_items_local_id) do
                id = id + ArchipelagoDST.RAW.ITEM_ID_OFFSET
                local item = ArchipelagoDST.ID_TO_ITEM[id]
                if item then
                    table.insert(slotdata.locked_items, id)
                end
            end
        end
        if data.resync then
            print("RESYNCING ITEMS")
            -- Lock items
            if not slotdata.locked_items or #slotdata.locked_items == 0 then
                slotdata.locked_items = self:GetLockedItemsV1_0_2_Pristine()
            end
            ArchipelagoDST.SendCommandToAllShards("lockeditems", json.encode(slotdata.locked_items))
            -- Track items given
            self.physicalitemsthissession = {}
        end
        if data.items then
            self:SendItems(data.items, data.resync)
        end

    elseif datatype == "Locations" then
        local slotdata = self:GetSlotData()
        if data.resync then
            -- Save all locations
            slotdata.all_locations = {}
            local sendchecks = {}
            if data.missing_locations then
                for _, v in pairs(data.missing_locations) do
                    slotdata.all_locations[v] = true
                    -- Check items that were obtained offline
                    if slotdata.missinglocations and not slotdata.missinglocations[v] then
                        table.insert(sendchecks, v)
                    end
                end
                if #sendchecks > 0 then
                    self:SendSignal("Item", {sources = sendchecks})
                end
            end
            if data.checked_locations then
                for _, v in pairs(data.checked_locations) do 
                    slotdata.all_locations[v] = true
                    -- Check boss conditions for checks completed while offline
                    local loc = ArchipelagoDST.ID_TO_LOCATION[v]
                    if loc then
                        if slotdata.requiredbosses and slotdata.requiredbosses[loc.prettyname] and slotdata.defeatedbosses and not slotdata.defeatedbosses[loc.prettyname] then
                            self:OnLegacyGoalLocation(v)
                        end
                    end
                end
            end
            ArchipelagoDST.SendCommandToAllShards("all_locations", json.encode(setToList(slotdata.all_locations)))
        end
        if data.missing_locations then
            slotdata.missinglocations = slotdata.missinglocations or {}
            -- Send missing locations
            ArchipelagoDST.SendCommandToAllShards("missinglocations", json.encode(data.missing_locations))
            
            for _, v in pairs(data.missing_locations) do
                if ArchipelagoDST.ID_TO_DEPRECATED_LOCATION[v] then
                    -- Check if any of these are deprecated
                    self:SendSignal("Item", {source = v})
                else
                    slotdata.missinglocations[v] = true
                end
            end
        end
        if data.checked_locations then
            local dogoalcheck = false
            -- Remove checked locations
            for _, v in pairs(data.checked_locations) do
                if slotdata.missinglocations[v] then
                    slotdata.missinglocations[v] = nil
                    -- Check new boss goal condition
                    if slotdata.goallocations and slotdata.goallocations[v] then
                        dogoalcheck = true
                    end
                end
            end
            if dogoalcheck then
                self:CheckGoalLocationStatus()
            end
            ArchipelagoDST.SendCommandToAllShards("removelocations", json.encode(data.checked_locations))
        end
    end
end
-- -- data is optional, will send a GET signal if data is nil, otherwise send a POST signal
-- function DSTAPManager:QueryAP(fn, data)
--     if not ArchipelagoDST.AP_CLIENT_IP then
--         return
--     end
--     local intent = data == nil and "GET" or "POST"
--     local resultfn = function(result, success, resultCode) 
--         if fn ~= nil then
--             fn(result, success, resultCode)
--         end
--         self.pause = false
--     end

--     self.pause = true
--     TheSim:QueryServer(
--         ArchipelagoDST.AP_CLIENT_IP,
--         resultfn,
--         intent,
--         TriangleTrashFill(data)
--     )
-- end


---------------------------Outgoing---------------------------
-- local function defaultfn(result, success, resultCode)
--     if resultCode == 400 or resultCode == 500 then
--         print("Can't connect to AP Client. Result Code:", resultCode)
--     end
-- end

-- function DSTAPManager:PingAPClient()
--     local time = GetStaticTime()
--     self:QueryAP(
--         function(result, success, resultCode)
--             if resultCode == 200 then --Returns this if there is nothing to be updated about, just ping-pong as usual
--                 self.ping = GetStaticTime() - time 
--             elseif resultCode == 100 then --Returns this if not connected to ap or has an event lined up from AP for us
--                 self.ping = GetStaticTime() - time 
--                 local suc, data = pcall( function() return json.decode(result) end )
--                 if suc then
--                     self:ManageEvent(data.datatype, data)
--                 else
--                     print("PingAPClient: Could not parse json", suc, data)
--                 end
--             else --Returns this if it can not connect to the interface at all
--                 self.ping = "5000"
--                 self.connected = false
--                 if TheWorld.dstap_state ~= false and not isShutDown() then
--                     ArchipelagoDST.SendCommandToAllShards("updateapstate", false, true)
--                 end
--             end
--         end,
--         json.encode({datatype = "Ping"})
--     )
-- end

-----------------------------Other-----------------------------

-- function DSTAPManager:DoTick_old()
--     if self.pause == true then return end

--     if #self.queue > 0 then        
--         local signal = table.remove(self.queue, 1)
--         self:QueryAP(defaultfn, json.encode(signal))
--     else
--         self:PingAPClient()
--     end
-- end

-- function DSTAPManager:SendSignal_old(datatype, data)
--     local senddata = {datatype = datatype}
--     if data then
--         for k, v in pairs(data) do
--             senddata[k] = v 
--         end
--     end
--     if datatype == "Connect" then
--         self:QueryAP(defaultfn, json.encode(senddata))
--     else
--         table.insert(self.queue, senddata)
--     end
-- end


function DSTAPManager:SetAPDataTaskDirty()
    if not self.setapdata_task then
        self.setapdata_task = function() self:SetAPData() end
    end
end
function DSTAPManager:SendAPDataImmediately()
    self:SetAPData()
    self.setapdata_task = nil
end

function DSTAPManager:ReadAPData(data)
    -- Check if data is valid
    if not data.slot or not data.seed_name then
        print("ReadAPData error! No seed or slot defined!")
        return
    end

    if not data.session_id or data.session_id ~= self.connected_timestamp then
        -- Check if this a fresh world. Acknowledge client's seed and send it back
        if not self.seed or self.seed == "None" then
            -- if not self._fresh_seed_dirty_sent then
            --     self._fresh_seed_dirty_sent = true
                self.outputdata.seed = data.seed_name
                self.outputdata.slotnum = data.slot
                self:SetAPDataTaskDirty()
            -- end
        end
        self.ping = "5000"
        self.connected = false
        if TheWorld.dstap_state ~= false and not isShutDown() then
            ArchipelagoDST.SendCommandToAllShards("updateapstate", false, true)
        end
        self.sendqueue_bookmark = 0
        self.sendqueue_lowpriority_bookmark = 0
        self:Cancel_ProcessDataQueueTask()
        return
    end
    -- self._fresh_seed_dirty_sent = nil

    -- By now we trust the session. We can accept the seed
    self.ping = 1
    if not self.seed or self.seed == "None" then
        -- Accept data. Seed and slot will be set automatically
        self:ProcessDataQueue(data)
    elseif self.slotnum ~= data.slot or self.seed ~= data.seed_name then
        -- Don't accept different seed
        if not self._announced_seed_mismatch then
            self._announced_seed_mismatch = true
            TheNet:Announce(STRINGS.ARCHIPELAGO_DST.WARN_FILEDATA_DIFFERENT_SEED_OR_SLOT)
        end
    else
        -- Okay to proceed
        self._announced_seed_mismatch = nil
        self:ProcessDataQueue(data)
    end
end
function DSTAPManager:Cancel_ProcessDataQueueTask()
    if self._processdataqueue_task then
        self._processdataqueue_task:Cancel()
    end
    self._processdataqueue_task = nil
    self._sendqueue = nil
    self._sendqueue_lowpriority = nil
end
function DSTAPManager:ProcessDataQueue(data)
    if not data then return end
    local function onProcessDataQueue()
        local event
        if self._sendqueue and #self._sendqueue > 0 then
            event = table.remove(self._sendqueue, 1)
            self._sendqueue_i = self._sendqueue_i + 1
            if self._sendqueue_i > self.sendqueue_bookmark then
                self.sendqueue_bookmark = self._sendqueue_i
            end
        elseif self._sendqueue_lowpriority and #self._sendqueue_lowpriority > 0 then
            event = table.remove(self._sendqueue_lowpriority, 1)
            self._sendqueue_lowpriority_i = self._sendqueue_lowpriority_i + 1
            if self._sendqueue_lowpriority_i > self.sendqueue_lowpriority_bookmark then
                self.sendqueue_lowpriority_bookmark = self._sendqueue_lowpriority_i
            end
        else
            self:Cancel_ProcessDataQueueTask()
        end
        if event then
            self:ManageEvent(event.datatype, event)
        end
    end
    if not self._processdataqueue_task then -- Let this finish first before starting it again
        self._sendqueue = data.sendqueue
        self._sendqueue_i = 0
        self._sendqueue_lowpriority = data.sendqueue_lowpriority
        self._sendqueue_lowpriority_i = 0
        -- Fast forward queues to the new stuff
        while self._sendqueue_i < self.sendqueue_bookmark do
            if self._sendqueue and #self._sendqueue > 0 then
                table.remove(self._sendqueue, 1)
            end
            self._sendqueue_i = self._sendqueue_i + 1
        end
        while self._sendqueue_lowpriority_i < self.sendqueue_lowpriority_bookmark do
            if self._sendqueue_lowpriority and #self._sendqueue_lowpriority > 0 then
                table.remove(self._sendqueue_lowpriority, 1)
            end
            self._sendqueue_lowpriority_i = self._sendqueue_lowpriority_i + 1
        end
        -- print("Starting a new queue", self._sendqueue ~= nil and #self._sendqueue, self._sendqueue_lowpriority ~= nil and #self._sendqueue_lowpriority)
        -- print("Bookmarks", self.sendqueue_bookmark, self.sendqueue_lowpriority_bookmark)
        self._processdataqueue_task = self.inst:DoStaticPeriodicTask(0.1, onProcessDataQueue, nil, self)
    end
end

function DSTAPManager:DoTick()
    self:ProcessItemQueue()
    if os.time() - self.last_send_time > 2*60 then
        self:SendAPDataImmediately()
    end
    if self.setapdata_task then
        self.setapdata_task()
        self.setapdata_task = nil
    end
    self:GetAPData(function(data) self:ReadAPData(data) end)
end


function DSTAPManager:ResetOutputData()
    self.outputdata = {
        seed = self.seed or "None",
        slotnum = self.slotnum or 0,
        slotname = self.slotname or "Unknown",
    }
    self:SetAPDataTaskDirty()
end

function DSTAPManager:SendSignal(datatype, data)
    if not self.seed or self.seed == "None" then
        return
    end
    local immediate = false
    local SIGNALFN = {
        Victory = function(data)
            self.outputdata[datatype] = true
        end,
        Item = function(data)
            self.outputdata[datatype] = self.outputdata[datatype] or {}
            local sources = {}
            if data.source then
                sources = {data.source}
            elseif data.sources then
                sources = data.sources
            end
            for _, v in ipairs(sources) do
                if not table.contains(self.outputdata[datatype], v) then
                    table.insert(self.outputdata[datatype], v)
                end
            end
            table.insert(self.outputdata[datatype], data.id)
            immediate = true
        end,
        DeathLink = function(data)
            self.outputdata[datatype] = data
        end,
        Death = function(data)
            self.outputdata[datatype] = self.outputdata[datatype] or {}
            table.insert(self.outputdata[datatype], {
                timestamp = os.time(),
                msg = data.msg
            })
        end,
        ScoutLocation = function(data)
            self.outputdata[datatype] = self.outputdata[datatype] or {}
            if not table.contains(self.outputdata[datatype], data.id) then
                table.insert(self.outputdata[datatype], data.id)
            end
        end,
        Hint = function(data)
            self.outputdata[datatype] = self.outputdata[datatype] or {}
            table.insert(self.outputdata[datatype], {
                timestamp = os.time(),
            })
        end,
    }
    if SIGNALFN[datatype] then
        SIGNALFN[datatype](data)
    end

    if immediate then
        self:SendAPDataImmediately()
    else
        self:SetAPDataTaskDirty()
    end
end

function DSTAPManager:SetAPData()
    self.outputdata.timestamp = os.time()
    self.last_send_time = self.outputdata.timestamp
    self.outputdata.connected_timestamp = self.connected_timestamp
    local str = json.encode(self.outputdata)
    SavePersistentString("archipelagorandomizer_outgoing", str)
end

function DSTAPManager:GetAPData(callback)
	TheSim:GetPersistentString("archipelagorandomizer_incoming",
		function(load_success, data)
			if load_success and data ~= nil then
                local status, incomingdata = pcall( function() return json.decode(data) end )
                if status and incomingdata then
                    if callback then
                        callback(incomingdata)
                    end
                else
                    print("Failed to get AP Data!", status, incomingdata)
                end
            end
		end)
end
return DSTAPManager