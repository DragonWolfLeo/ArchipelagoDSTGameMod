local Widget = require "widgets/widget"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local DSTAP_Menu = require "widgets/dstap_menu"


local AP_Button = Class(Widget, function(self, owner, controls)
    Widget._ctor(self, "AP_Button")
    self.controls = controls
    self.owner = owner
    self.root = self:AddChild(Widget("ROOT"))

    self.bg = self.root:AddChild(ImageButton("images/global_redux.xml", "char_selection.tex", "char_selection_hover.tex"))
    self.bg:SetScale(0.65, 0.65, 0.65)
    self.bg.scale_on_focus = false
    self.bg.onclick = function() self:ToggleMenu() end

    self.icon = self.bg:AddChild(Image("images/ap_icon.xml", "ap_icon.tex"))
    self.icon:SetScale(1.5, 1.5, 1.5)

    self.menu = self.root:AddChild(DSTAP_Menu(self, controls))
    self.menu:SetScale(0.75, 0.75, 0.75)
    self.menu:SetPosition(0, -200, 0)

    self.hud_focus = owner.HUD.focus
    
    -- Status icon
    self.connectivity_icon = self:AddChild(Image("images/hud.xml", "connectivity1.tex"))
    self.connectivity_icon:SetPosition(28, -28, 0)
    self.connectivity_icon:SetScale(0.75, 0.75, 0.75)
    self.connectivity_icon:SetRotation(90)
    self.connectivity_icon:SetClickable(false)

    TheWorld:ListenForEvent("clientupdateinterfacestate", function() self:ConnectionStatusChange() end)    
    TheWorld:ListenForEvent("clientupdateapstate", function() self:ConnectionStatusChange() end)
    self:ConnectionStatusChange()
end)

function AP_Button:ToggleMenu()
    if self.menu:IsVisible() == true then 
        self.menu:Hide() 
    else
        self.menu:OpenDSTAPMenu()
    end
end

-- function AP_Button:OnClick()
--     if ThePlayer and ThePlayer.HUD then
--         ThePlayer.HUD:DSTAP_OpenTrackerScreen()
--     end
-- end


function AP_Button:ConnectionStatusChange()
    local interfaceping = TheWorld.dstap_interfacestate and tonumber(TheWorld.dstap_interfacestate) or 5000
    local interface_connected = interfaceping < 5000 and true or false
    local ap_connected = TheWorld.dstap_state
    if interface_connected and ap_connected then
        -- self.connectivity_icon:Hide()
        self.connectivity_icon:SetTexture("images/connectivity3.xml", "connectivity3.tex")
    elseif interface_connected then
        -- self.connectivity_icon:Show()
        self.connectivity_icon:SetTexture("images/hud.xml", "connectivity2.tex")
    else
        -- self.connectivity_icon:Show()
        self.connectivity_icon:SetTexture("images/hud.xml", "connectivity1.tex")
    end
end

return AP_Button