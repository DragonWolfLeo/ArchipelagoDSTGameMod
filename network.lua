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
--
local DSTAP = GLOBAL.ArchipelagoDST
local json = GLOBAL.json

local function SendCommandFromShard(cmd, data)
	if not GLOBAL.TheWorld.ismastersim then
		return
	end
	local sender = nil
	return SendModRPCToClient(GetClientModRPC("archipelago", "oncommandfromshard"), nil, sender, cmd, data)
end

local RPCCommand = {
	gotitem = function(cmd, data)
		local item = DSTAP.ID_TO_ITEM[data]
		if item then
			DSTAP.collecteditems[item.id] = true
			DSTAP.LockItem(data, false, true)
			SendCommandFromShard(cmd, data)
		end
	end,
	lockeditems = function(cmd, data)
		-- Sets the relevant AP items as locked
		local items = json.decode(data)
		DSTAP.lockableitems = listToSet(items)
		local bundle_items = {}
		for _, v in pairs(DSTAP.ID_TO_ITEM) do
			-- Set this as an AP item
			if DSTAP.lockableitems[v.id] then
				DSTAP.LockItem(v.id, not DSTAP.collecteditems[v.id], false)
			elseif not v.inbundle then
				-- Set this as a non-AP item
				DSTAP.LockItem(v.id, nil, false)
			end
		end
		DSTAP.PushUnlockRecipeEvent()
		if GLOBAL.TheWorld.ismastersim then
			GLOBAL.TheWorld:PushEvent("dstap_lockableitems_set")
			SendCommandFromShard(cmd, data)
		end
	end,
	resetitems = function(cmd, data)
		DSTAP.LockAllRecipes()
		SendCommandFromShard(cmd, data)
	end,
	syncitems = function(cmd, data)
		-- Replace collected items
		DSTAP.collecteditems = {}
		local items = json.decode(data)
		for _, id in pairs(items) do
			local item = DSTAP.ID_TO_ITEM[id]
			if item then				
				DSTAP.LockItem(id, false, true)
				DSTAP.collecteditems[item.id] = true
			end
		end
		SendCommandFromShard(cmd, data)
	end,
	syncabstract = function(cmd, data) -- Only needed on mastersim
		-- Set abstract item amounts
		local item_info = json.decode(data)
		local item = DSTAP.ID_TO_ABSTRACT_ITEM[item_info.id]
		if item and item.prefab and DSTAP.abstractitems[item.prefab] ~= item_info.amount then
			DSTAP.abstractitems[item.prefab] = item_info.amount
			GLOBAL.TheWorld:PushEvent("dstap_"..item.prefab.."_changed", item_info.amount)
		end
	end,
	missinglocations = function(cmd, data)
		local locs = json.decode(data)		
		for _,v in pairs(locs) do
			DSTAP.missinglocations[v] = true
		end
		SendCommandFromShard(cmd, data)
	end,
	all_locations = function(cmd, data) 
		-- Overwrites all_locations
		local locs = json.decode(data)
		DSTAP.all_locations = listToSet(locs)
		GLOBAL.TheWorld:PushEvent("dstap_all_locations_set")
		-- Send to client
		SendCommandFromShard(cmd, data)
	end,
	locationinfo = function(cmd, data)
		local loc_info = json.decode(data)
		DSTAP.SaveAndSetLocationInfo(loc_info)
		-- Sync research locations to client so they appear in the craft menu
		SendCommandFromShard(cmd, data)
	end,
	locationinfoall_syncclient = function(cmd, data) -- Only on client
		if not GLOBAL.TheWorld.ismastersim then
			local loc_info_table = json.decode(data)
			-- Sync research locations to client so they appear in the craft menu
			for _, loc_info in pairs(loc_info_table) do
				DSTAP.SaveAndSetLocationInfo(loc_info)
			end
		end
	end,
	hintinfo = function(cmd, data)
		local hint = json.decode(data)
		DSTAP.SetAndSaveHintInfo(hint)
		-- Send to client
		SendCommandFromShard(cmd, data)
	end,
	hintinfoall_syncclient = function(cmd, data) -- Only on client
		if not GLOBAL.TheWorld.ismastersim then
			local hint_table = json.decode(data)
			for _, hint in pairs(hint_table) do
				DSTAP.SetAndSaveHintInfo(hint)
			end
		end
	end,
	removelocations = function(cmd, data)
		local locs = json.decode(data)
		local pushunlockevent = false
		for _,v in pairs(locs) do
			if DSTAP.missinglocations[v] then
				DSTAP.missinglocations[v] = nil
				DSTAP.LOCATION_INFO[v] = nil
			end
		end
		SendCommandFromShard(cmd, data)
	end,
	resetlocation = function(cmd, data)
		DSTAP.missinglocations = {}
		SendCommandFromShard(cmd, data)
	end,
	synclocations = function(cmd, data) -- From shard to client
		if GLOBAL.TheWorld.ismastersim then
			print("Syncing items and locations to client")
			-- Goal info
			SendCommandFromShard("goalinfo", json.encode(DSTAP.goalinfo))
			-- Global info
			SendCommandFromShard("globalinfo", json.encode(DSTAP.globalinfo))
			-- Collected items
			local collecteditems = setToList(DSTAP.collecteditems)
			if #collecteditems > 0 then
				SendCommandFromShard("syncitems", json.encode(collecteditems))
			end
			-- Lockable items
			local lockeditems = setToList(DSTAP.lockableitems)
			if #lockeditems > 0 then
				SendCommandFromShard("lockeditems", json.encode(lockeditems))
			else
				SendCommandFromShard("resetitems")
			end
			-- Missing locations
			local missinglocations = setToList(DSTAP.missinglocations)
			SendCommandFromShard("missinglocations", json.encode(missinglocations))
			-- All locations
			if DSTAP.all_locations then
				local all_locations = setToList(DSTAP.all_locations)
				SendCommandFromShard("all_locations", json.encode(all_locations))
			end
			-- Research location info
			local locationinfotable = {}
			for id, istrue in pairs(DSTAP.missinglocations) do
				if istrue then
					if DSTAP.ID_TO_RESEARCH_LOCATION[id] then 
						table.insert(locationinfotable, DSTAP.LOCATION_INFO[id])
					end
				end
			end
			SendCommandFromShard("locationinfoall_syncclient", json.encode(locationinfotable))
			local hints = {}
			for _, hint in pairs(DSTAP.LOCATION_HINT_INFO) do
				table.insert(hints, hint)
			end
			for _, hint in pairs(DSTAP.ITEM_HINT_INFO) do
				if not hint.location_is_local then -- Don't send duplicate hints
					table.insert(hints, hint)
				end
			end
			SendCommandFromShard("hintinfoall_syncclient", json.encode(hints))
		end
	end,
	goteffect = function(cmd, data)
		-- Traps and stat changes
		local item = DSTAP.ID_TO_ITEM[data]
		if item then
			local fxfn = DSTAP.Effects[item.prettyname]
			if fxfn then fxfn() end
		end
	end,
	gotphysical = function(cmd, data)
		-- Physical things you get
		local item = DSTAP.ID_TO_ITEM[data]
		if item and item.prefab then
			for _, player in pairs(GLOBAL.AllPlayers) do
				if player.components.inventory then
					local quantity = item.quantity or 1
					for i = 1, quantity do
						local spawned = GLOBAL.SpawnPrefab(item.prefab)
						if spawned then
							player.components.inventory:GiveItem(spawned)
						end
					end
				end
			end
		end
	end,
	deathlink = function(cmd, data)
		for i, player in ipairs(GLOBAL.AllPlayers) do
			if not player:HasTag("playerghost") then
				player.components.health:SetPercent(0, nil, "deathlink")
			end
		end
	end,
	updateapstate = function(cmd, data)
		SendCommandFromShard(cmd, data)
		GLOBAL.TheWorld.dstap_state = data
		GLOBAL.TheWorld:PushEvent("clientupdateapstate")
	end,
	updateinterfacestate = function(cmd, data)
		SendCommandFromShard(cmd, data)
		GLOBAL.TheWorld.dstap_interfacestate = data
		GLOBAL.TheWorld:PushEvent("clientupdateinterfacestate")
	end,
	clientplaytrapsound = function(cmd, data)
		-- Send to clients
		if GLOBAL.TheWorld.ismastersim then
			SendCommandFromShard(cmd, data)
		end
		if GLOBAL.TheFocalPoint then GLOBAL.TheFocalPoint.SoundEmitter:PlaySound("dontstarve/common/chest_trap") end
	end,
	setcraftingmode = function(cmd, data)
		if DSTAP.craftingmode ~= data then
			DSTAP.craftingmode = data
			DSTAP.PushUnlockRecipeEvent()
		end
		SendCommandFromShard(cmd, data)
	end,
	goalinfo = function(cmd, data)
		DSTAP.goalinfo = json.decode(data)
		SendCommandFromShard(cmd, data)
	end,
	globalinfo = function(cmd, data)
		local newinfo = json.decode(data)
		for k, v in pairs(newinfo) do
			DSTAP.globalinfo[k] = v
		end
		SendCommandFromShard(cmd, data)
	end,
}

local function OnCommand(sender, cmd, data)
	if GLOBAL.TheWorld == nil then return end
	-- print("OnCommand", sender, cmd, data)
	-- GLOBAL.assert(sender ~= "updateapstate")
	if RPCCommand[cmd] then
		return RPCCommand[cmd](cmd, data)
	else
		print("RPCCommand", cmd, "not found.")
	end
end

AddShardModRPCHandler("archipelago", "oncommandfrommaster", OnCommand)
AddClientModRPCHandler("archipelago", "oncommandfromshard", OnCommand)

local RPCQueueThread = nil
local RPCQueue = {}

DSTAP.SendCommandToAllShards = function(cmd, data, instant)
	if instant == true then
		-- print("Sending ShardRPC", cmd, data)
		SendModRPCToShard(GetShardModRPC("archipelago", "oncommandfrommaster"), nil, cmd, data)
	else
		table.insert(RPCQueue, 1, {cmd = cmd, data = data})
		if GLOBAL.TheWorld == nil then return end
		-- print(RPCQueueThread)
		if RPCQueueThread == nil then
			RPCQueueThread = GLOBAL.StartStaticThread(function()
				while #RPCQueue ~= 0 do
					-- print(GLOBAL.PrintTable(RPCQueue))
					local rpc = table.remove(RPCQueue)
					-- print("Running Command on self")
					-- OnCommand(nil, rpc.cmd, rpc.data)
					-- print("Sending ShardRPC", rpc.cmd, rpc.data)
					SendModRPCToShard(GetShardModRPC("archipelago", "oncommandfrommaster"), nil, rpc.cmd, rpc.data)
					GLOBAL.Sleep(0)
				end
				RPCQueueThread = nil
			end)
		end
	end
end

local function TryConnect(sender, name, ip, password)
	if GLOBAL.TheWorld.ismastershard then
		GLOBAL.TheWorld.components.dstapmanager:SendSignal("Connect", {name = name, ip = ip, password = password})
	else
		local isadmin = GLOBAL.TheNet:GetClientTableForUser(sender.userid).admin
		if isadmin == false then print(sender.name.." tried sending a connect request but they are not an admin!") return end

		SendModRPCToShard(GetShardModRPC("archipelago", "tryconnectfromshard"), GLOBAL.SHARDID.MASTER, name, ip, password)
	end
end
AddShardModRPCHandler("archipelago", "tryconnectfromshard", TryConnect)
AddModRPCHandler("archipelago", "tryconnectfromclient", TryConnect)

DSTAP.OnFindLocation = function(id)
	-- print("DSTAP.OnFindLocation", id)
	if id == nil then return end
	if GLOBAL.TheWorld.ismastershard then
		if DSTAP.ID_TO_LOCATION[id] then
			GLOBAL.TheWorld.components.dstapmanager:OnFindLocation(id)
		end
	else
		SendModRPCToShard(GetShardModRPC("archipelago", "onlocationfound"), GLOBAL.SHARDID.MASTER, id)
	end
end
AddShardModRPCHandler("archipelago", "onlocationfound", function(sender, id) DSTAP.OnFindLocation(id) end)

DSTAP.SyncFromMasterShard = function()
	if GLOBAL.TheWorld.ismastershard then
		print("SyncFromMasterShard: Command from master")
		GLOBAL.TheWorld.components.dstapmanager:SyncToShards()
	elseif GLOBAL.TheWorld.ismastersim then
		print("SyncFromMasterShard: Command from caves")
		SendModRPCToShard(GetShardModRPC("archipelago", "syncfrommastershard"), GLOBAL.SHARDID.MASTER)
	end
end
AddShardModRPCHandler("archipelago", "syncfrommastershard", function(sender) DSTAP.SyncFromMasterShard() end)

DSTAP.FreeHint = function(sender)
	if GLOBAL.TheWorld.ismastershard then
		GLOBAL.TheWorld.components.dstapmanager:SendSignal("Hint")
	end
end
AddShardModRPCHandler("archipelago", "onfreehint", DSTAP.FreeHint)

DSTAP._locationscouts = {}
DSTAP.ScoutLocation = function(loc_id)
	-- Since all_locations may or may not be initialized, try again once it's set
	if not DSTAP.all_locations then
		local removerestorecallback = function() GLOBAL.assert(false) end
		local callbackfn = function(wrld, data) 
			if DSTAP.all_locations then
				DSTAP.ScoutLocation(loc_id)
				GLOBAL.TheWorld:DoTaskInTime(0.1, removerestorecallback)
			end
		end
		removerestorecallback = function() GLOBAL.TheWorld:RemoveEventCallback("dstap_all_locations_set", callbackfn) end
		GLOBAL.TheWorld:ListenForEvent("dstap_all_locations_set", callbackfn)
	else
		-- Scout if it's an existing location
		if not DSTAP.all_locations[loc_id] or DSTAP._locationscouts[loc_id] or DSTAP.LOCATION_INFO[loc_id] then
			return
		end
		DSTAP._locationscouts[loc_id] = true
		if GLOBAL.TheWorld.ismastershard then
			print("ScoutLocation: Command from master", loc_id)
			GLOBAL.TheWorld.components.dstapmanager:SendSignal("ScoutLocation", {id = loc_id})
		elseif GLOBAL.TheWorld.ismastersim then
			print("ScoutLocation: Command from caves", loc_id)
			SendModRPCToShard(GetShardModRPC("archipelago", "scoutlocation"), GLOBAL.SHARDID.MASTER, loc_id)
		end
	end
end
AddShardModRPCHandler("archipelago", "scoutlocation", function(sender, loc_id) DSTAP.ScoutLocation(loc_id) end)

DSTAP.SendSurvivorAge = function(age)
	if GLOBAL.TheWorld.ismastershard then
		-- print("SendSurvivorAge: Command from master", age)
		GLOBAL.TheWorld:PushEvent("dstap_survivorage", age)
	elseif GLOBAL.TheWorld.ismastersim then
		-- print("SendSurvivorAge: Command from caves", age)
		SendModRPCToShard(GetShardModRPC("archipelago", "sendsurvivorage"), GLOBAL.SHARDID.MASTER, age)
	end
end
AddShardModRPCHandler("archipelago", "sendsurvivorage", function(sender, age) DSTAP.SendSurvivorAge(age) end)

DSTAP.SendDeath = function(msg)
	if GLOBAL.TheWorld.ismastershard then
		GLOBAL.TheWorld.components.dstapmanager:SendSignal("Death", {msg = DSTAP.FilterOutSpecialCharacters(msg)})
	elseif GLOBAL.TheWorld.ismastersim then
		SendModRPCToShard(GetShardModRPC("archipelago", "senddeath"), GLOBAL.SHARDID.MASTER, msg)
	end
end
AddShardModRPCHandler("archipelago", "senddeath", function(sender, msg) DSTAP.SendDeath(msg) end)

DSTAP.FilterOutSpecialCharacters = function(str)
	-- Replace emoji with their raw input
	for _,v in pairs(GLOBAL.EMOJI_ITEMS) do
		str = str:gsub(v.data.utf8_str, "("..v.input_name..")")
	end
	-- Remove controller button icons
	str = str:gsub("[\238\239]..", "")
	return str
end