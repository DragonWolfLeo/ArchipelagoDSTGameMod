local Widget = require "widgets/widget"
local Templates = require "widgets/redux/templates" 
local Image = require "widgets/image"

local AP_Status = Class(Widget, function(self, owner, controls)
    Widget._ctor(self, "AP_Status")
    self.controls = controls
    self.owner = owner
    self.root = self:AddChild(Widget("ROOT"))

    self.dst = self:AddChild(Image("images/global_redux.xml", "button_carny_square_disabled.tex"))
    self.dst:SetHoverText("Don't Starve Together", {offset_y = -40})
    self.dst:SetPosition(-90, 0, 0)
    self.dst:SetScale(0.4, 0.4, 0.4)
    self.dst.icon = self.dst:AddChild(Image("images/button_icons.xml", "survivor_filter_on.tex"))
    self.dst.icon:SetScale(0.3, 0.3, 0.3)

    self.dst_int_status = self:AddChild(Image("images/hud.xml", "connectivity1.tex"))
    self.dst_int_status:SetPosition(-45, 0, 0)
    self.dst_int_status:SetScale(0.85, 0.85, 0.85)
    self.dst_int_status:SetRotation(90)
    self.dst_int_status:SetHoverText("No Connection to AP client.", {offset_y = -40})

    TheWorld:ListenForEvent("clientupdateinterfacestate", function(inst, data) 
        local ping = tonumber(TheWorld.dstap_interfacestate) or 5000
        self:ConnectionStatusChange(self.dst_int_status, ping) 
        ping = ping >= 5000 and "No Connection to AP client." or "Ping: "..string.sub(tostring(ping), 0, 6)
        self.dst_int_status:SetHoverText(ping, {offset_y = -40})
    end)

    self.interface = self:AddChild(Image("images/global_redux.xml", "button_carny_square_disabled.tex"))
    self.interface:SetHoverText("DST Interface", {offset_y = -40})
    self.interface:SetPosition(0, 0, 0)
    self.interface:SetScale(0.4, 0.4, 0.4)
    self.interface.icon = self.interface:AddChild(Image("images/hud.xml", "hostperf2.tex"))
    self.interface.icon:SetScale(1, 1, 1)

    self.int_ap_status = self:AddChild(Image("images/hud.xml", "connectivity1.tex"))
    self.int_ap_status:SetPosition(45, 0, 0)
    self.int_ap_status:SetScale(0.85, 0.85, 0.85)
    self.int_ap_status:SetRotation(90)
    self.int_ap_status:SetHoverText("No Connection to AP server.", {offset_y = -40})

    TheWorld:ListenForEvent("clientupdateapstate", function(inst, data) 
        local status = TheWorld.dstap_state or false
        local ping = status == true and 0 or 5000
        self:ConnectionStatusChange(self.int_ap_status, ping) 
        ping = ping >= 5000 and "No Connection to AP server." or "Connected to AP server"
        self.int_ap_status:SetHoverText(ping, {offset_y = -40})
    end)

    self.ap = self:AddChild(Image("images/global_redux.xml", "button_carny_square_disabled.tex"))
    self.ap:SetHoverText("Archipelago", {offset_y = -40})
    self.ap:SetPosition(90, 0, 0)
    self.ap:SetScale(0.4, 0.4, 0.4)
    self.ap.icon = self.ap:AddChild(Image("images/ap_icon_silho.xml", "ap_icon_silho.tex"))
    self.ap.icon:SetScale(1, 1, 1)

end)

function AP_Status:ConnectionStatusChange(module, ping)
    if ping == nil then return end
    if ping < 2 then
        module:SetTexture("images/connectivity3.xml", "connectivity3.tex")
    elseif ping < 10 then
        module:SetTexture("images/hud.xml", "connectivity2.tex")
    else
        module:SetTexture("images/hud.xml", "connectivity1.tex")
    end
end

return AP_Status