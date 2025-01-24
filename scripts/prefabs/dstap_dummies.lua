-- Just to get the log to not spam about loading fake items
local function fn() end
return unpack({
	Prefab("dstap_science", fn),
	Prefab("dstap_magic", fn),
	Prefab("dstap_seafaring", fn),
	Prefab("dstap_ancient", fn),
	Prefab("dstap_celestial", fn),
	Prefab("dstap_hermitcrab", fn),
	Prefab("dstap_seasonchange_autumn", fn),
	Prefab("dstap_seasonchange_winter", fn),
	Prefab("dstap_seasonchange_spring", fn),
	Prefab("dstap_seasonchange_summer", fn),
	Prefab("dstap_moonphasechange_full", fn),
	Prefab("dstap_moonphasechange_new", fn),
})