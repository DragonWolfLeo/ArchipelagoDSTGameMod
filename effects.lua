local DSTAP = GLOBAL.ArchipelagoDST

local function PlayerAnnounceTrap(player, stringname)
	if player.components.talker then
		player.components.talker:Say(GLOBAL.GetString(player, stringname or "ANNOUNCE_TRAP_WENT_OFF"))
	end
end

local function IceTrap()
	local count = DSTAP.TUNING.ICE_TRAP_COUNT
	local spawntime = DSTAP.TUNING.ICE_TRAP_SPAWN_TIME
	local spellrange = DSTAP.TUNING.ICE_TRAP_RANGE
	for k, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player)
			local spells = {}
			local function spawnnearby(_, range)
				local pt = GLOBAL.Point(player:GetPosition():Get())
				local offset = GLOBAL.FindWalkableOffset(pt, math.random() * 2 * GLOBAL.PI, range, 12, false, true, function() return not GLOBAL.TheWorld.Map:IsPointNearHole(pt) end) 
				if offset == nil then offset = GLOBAL.Point(0, 0, 0) end
				local spell = GLOBAL.SpawnPrefab("deer_ice_circle")
				spell.Transform:SetPosition(pt.x + offset.x, 0, pt.z + offset.z)
				table.insert(spells, spell)
			end
			spawnnearby("", 0)
			for i = 1, count - 1 do
				player:DoTaskInTime(((spawntime - 0.1) / (count-1)) * i, spawnnearby, (i / (count-1)) * spellrange) --Range starts at 0 then linearly creeps towards the max
			end -- Use player for the DoTask as to MAYBE avoid issues caused by them disconnecting during the spell.
			GLOBAL.TheWorld:DoTaskInTime(spawntime, function()
				for k, spell in pairs(spells) do
					spell:DoTaskInTime(1.5, spell.TriggerFX)
					spell:DoTaskInTime(3.5, spell.KillFX)
				end
			end)
		end
	end
end

local function DropInv()
	for k, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player)
			-- player.components.inventory:DropEverything(true)
			local items = player.components.inventory:FindItems(function(_)return true end)
			if #items > 0 then
				player.components.inventory:DropItem(items[math.random(#items)], true, true) -- Drop a random item from your inventory
			end
		end
	end
end

local function Slurp()
	for k, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player)
			local inventory = player.components.inventory
			local headitem = inventory:GetEquippedItem(GLOBAL.EQUIPSLOTS.HEAD)
			if headitem ~= nil then inventory:DropItem(headitem, true, true) end -- Drop the item instead of returning it to their inventory

			local slurper = GLOBAL.SpawnPrefab("slurper")
			slurper.Transform:SetPosition(player:GetPosition():Get())
			inventory:Equip(slurper, nil, true)
		end
	end
end

local function StatSwap()
	for k, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player)
			local health = player.components.health:GetPercent()
			local sanity = player.components.sanity:GetPercent()
			local hunger = player.components.hunger:GetPercent()

			-- Unless I am mistaken there are only 2 outcomes that don't include a stat staying the same
			if math.random() > 0.5 then --Shift Down
				player.components.health:SetPercent(hunger, false, "statswap")
				player.components.sanity:SetPercent(health)
				player.components.hunger:SetPercent(sanity)
			else -- Shift Up
				player.components.health:SetPercent(sanity, false, "statswap")
				player.components.sanity:SetPercent(hunger)
				player.components.hunger:SetPercent(health)
			end
		end
	end
end

local function SporeTrap()
	local count = DSTAP.TUNING.SPORE_TRAP_COUNT
	for k, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player)
			local function spawnspore()
				player:AddDebuff("sporebomb", "sporebomb")
			end
			spawnspore()
			if count > 1 then
				for i = 1, count - 1 do
					player:DoTaskInTime(i * (TUNING.TOADSTOOL_SPOREBOMB_TIMER + 0.1), spawnspore)
				end
			end
		end
	end
end

local function BoomerangTrap()
	for k, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player)
			local function spawnboomerang()
				local pt = GLOBAL.Point(player:GetPosition():Get())
				local offset = GLOBAL.FindWalkableOffset(pt, math.random() * 2 * GLOBAL.PI, DSTAP.TUNING.BOOMERANG_TRAP_DIST, 12, false, true, function() return not GLOBAL.TheWorld.Map:IsPointNearHole(pt) end, true, true) 
				local boomerang = GLOBAL.SpawnPrefab("boomerang")
				boomerang.Transform:SetPosition(pt.x + offset.x, 0, pt.z + offset.z)        
				player.SoundEmitter:PlaySound("dontstarve/wilson/boomerang_return")
				boomerang.components.finiteuses:SetUses(1)
				boomerang.components.projectile:Throw(player, player)
			end
			spawnboomerang()
			for i = 1, DSTAP.TUNING.BOOMERANG_TRAP_COUNT - 1 do
				player:DoTaskInTime((i * DSTAP.TUNING.BOOMERANG_TRAP_DELAY) + (math.random() - 0.5), spawnboomerang)
			end
		end
	end
end

local function BeeTrap()
	for _, player in pairs(GLOBAL.AllPlayers) do
		if not player:HasTag("playerghost") then
			PlayerAnnounceTrap(player,"ANNOUNCE_BEES")
			local function spawnbee()
				local pt = GLOBAL.Point(player:GetPosition():Get())
				local offset = GLOBAL.FindWalkableOffset(pt, math.random() * 2 * GLOBAL.PI, DSTAP.TUNING.BEE_TRAP_DISTANCE, 12, false, true, function() return not GLOBAL.TheWorld.Map:IsPointNearHole(pt) end, true, true) 
				local bee = GLOBAL.SpawnPrefab("killerbee")
				bee.Transform:SetPosition(pt.x + offset.x, 0, pt.z + offset.z)        
			end
			for i = 1, DSTAP.TUNING.BEE_TRAP_COUNT do
				spawnbee()
			end
		end
	end
end

local function SeasonTrap(season)
	return function()
		if season == GLOBAL.TheWorld.state.season then
			-- It's already this season!
			return
		end
		for _, player in pairs(GLOBAL.AllPlayers) do
			if not player:HasTag("playerghost") then
				PlayerAnnounceTrap(player)
			end
		end
		-- All clients hear the spooky sound from their focal point
		DSTAP.SendCommandToAllShards("clientplaytrapsound")

		if GLOBAL.TheWorld.ismastershard then
			-- Change the season
			GLOBAL.TheWorld:PushEvent("ms_setseason", season)
		end
	end
end

local function StatChange(type, amount)
	return function()
		for _, player in pairs(GLOBAL.AllPlayers) do
			local targetstat = player.components[type]
			if targetstat then
				targetstat:DoDelta(amount)
			end
		end
	end
end

DSTAP.Effects = {
	["Ice Trap"] = IceTrap,
	["Drop Item"] = DropInv,
	["Slurper Trap"] = Slurp,
	["Stat Swap"] = StatSwap,
	["Spore Trap"] = SporeTrap,
	["Boomerang Trap"] = BoomerangTrap,
	["Bee Trap"] = BeeTrap,
	["Autumn Trap"] = SeasonTrap(GLOBAL.SEASONS.AUTUMN),
	["Winter Trap"] = SeasonTrap(GLOBAL.SEASONS.WINTER),
	["Spring Trap"] = SeasonTrap(GLOBAL.SEASONS.SPRING),
	["Summer Trap"] = SeasonTrap(GLOBAL.SEASONS.SUMMER),
	["20 Health"] = StatChange("health", GLOBAL.TUNING.HEALING_MED),
	["15 Sanity"] = StatChange("sanity", GLOBAL.TUNING.SANITY_MED),
	["25 Food"] = StatChange("hunger", GLOBAL.TUNING.CALORIES_MED),
	["60 Health"] = StatChange("health", GLOBAL.TUNING.HEALING_HUGE),
	["50 Sanity"] = StatChange("sanity", GLOBAL.TUNING.SANITY_HUGE),
	["75 Food"] = StatChange("hunger", GLOBAL.TUNING.CALORIES_HUGE),
}