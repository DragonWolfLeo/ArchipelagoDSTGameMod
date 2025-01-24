-- require "recipes"

local assets =
{
    Asset("ANIM", "anim/blueprint.zip"),
    Asset("ANIM", "anim/blueprint_rare.zip"),
    Asset("INV_IMAGE", "blueprint"),
    Asset("INV_IMAGE", "blueprint_rare"),
}

local function SpellFN(inst, target, pos, doer)
    if not inst.source then return end
    local loc = ArchipelagoDST.PREFAB_TO_COMBAT_LOCATION[inst.source]
    if loc then
        TheWorld:PushEvent("dstapfoundlocation", {id = loc.id, doer = doer.name})
    else
        print("Invalid source for blueprint: ", inst.source)
    end

    inst:Remove()
end

local function SetSource(inst, source) -- source accepts a prefab string or a entity. 
    if type(source) == "table" then
        if source.prefab ~= nil then
            source = source.prefab 
        else
            print(inst, "Invalid source entity provided.")
            return false
        end
    end
    if source == nil then return false end

    inst.components.named:SetName(STRINGS.NAMES[string.upper(source)].."'s "..STRINGS.NAMES.DSTAP_BLUEPRINT)
    inst.source = source
    return true
end

local function onsave(inst, data)
    data.source = inst.source
end

local function onload(inst, data)
    if data.source == nil then
        print(inst, "Invalid source save data!")
    else
        inst:SetSource(data.source)
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("blueprint_rare") -- Placeholder
    inst.AnimState:SetBuild("blueprint_rare") -- Placeholder
    inst.AnimState:PlayAnimation("idle")

    MakeInventoryFloatable(inst, "med", nil, 0.75)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("blueprint_rare")

    inst:AddComponent("named")
    -- inst:AddComponent("teacher")
    -- inst.components.teacher.onteach = OnTeach
    inst:AddComponent("spellcaster")
    inst.components.spellcaster:SetSpellFn(SpellFN)
    inst.components.spellcaster.canusefrominventory = true
    -- inst.components.spellcaster.quickcast = true

    MakeSmallBurnable(inst, TUNING.SMALL_BURNTIME)
    MakeSmallPropagator(inst)
    MakeHauntableLaunch(inst)

    inst.OnLoad = onload
    inst.OnSave = onsave

    inst.SetSource = SetSource

    return inst
end

return Prefab("dstap_blueprint", fn, assets)