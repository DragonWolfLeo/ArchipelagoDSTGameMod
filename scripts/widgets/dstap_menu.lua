local Widget = require "widgets/widget"
local Templates = require "widgets/redux/templates" 
local Image = require "widgets/image"
local Text = require "widgets/text"
local TextEdit = require "widgets/textedit"
local AP_Status = require "widgets/dstap_status"

local function LabelOverTextbox(labeltext, fieldtext, width, height, spacing, font, font_size, horiz_offset)
    local offset = horiz_offset or 0
    local wdg = Templates.StandardSingleLineTextEntry(fieldtext, width, height, font, font_size)
    wdg.label = wdg:AddChild(Text(font or CHATFONT, font_size or 25))
    wdg.label:SetString(labeltext)
    -- wdg.label:SetHAlign(ANCHOR_RIGHT)
    wdg.label:SetRegionSize(width,height)
    wdg.label:SetPosition(0, height/2 + spacing/2)
    wdg.label:SetColour(UICOLOURS.GOLD)
    -- Reposition relative to label
    wdg.textbox_bg:SetPosition(0, -(height/2 + spacing/2))
    wdg.textbox:SetPosition(0, -(height/2 + spacing/2))
    return wdg
end

local DSTAP_Menu = Class(Widget, function(self, owner, controls)
    Widget._ctor(self, "DSTAP_Menu")
    self.controls = controls
    self.owner = owner
    self.root = self:AddChild(Widget("ROOT"))

    self.bg = self.root:AddChild(Image("images/hud.xml", "craftingsubmenu_fullhorizontal.tex"))
    self.bg:SetRotation(90)
    -- self.bg = self.root:AddChild(Image("images/hud.xml", "craftingsubmenu_fullvertical.tex"))

    -- local isadmin = TheNet:GetClientTableForUser(ThePlayer.userid).admin

    -- if isadmin then
    --     self.name_module = self.root:AddChild(LabelOverTextbox("Slot Name", ThePlayer.name or "Player", 200, 40, -5))
    --     self.name_module:SetPosition(0, 100, 0)
    --     self.name_module.textbox:SetHAlign(ANCHOR_MIDDLE)

    --     self.ip_module = self.root:AddChild(LabelOverTextbox("IP and Port", "localhost", 200, 40, -5))
    --     self.ip_module:SetPosition(0, 30, 0)
    --     self.ip_module.textbox:SetHAlign(ANCHOR_MIDDLE)

    --     self.pass_module = self.root:AddChild(LabelOverTextbox("Password", "", 200, 40, -5))
    --     self.pass_module:SetPosition(0, -40, 0)
    --     self.pass_module.textbox:SetHAlign(ANCHOR_MIDDLE)

    --     local function SendTryConnect()
    --         SendModRPCToServer(
    --             GetModRPC("archipelago", "tryconnectfromclient"), 
    --             self.name_module.textbox:GetString(), 
    --             self.ip_module.textbox:GetString(), 
    --             self.pass_module.textbox:GetString()
    --         )
    --     end
    --     self.connect_btn = self.root:AddChild(Templates.StandardButton(SendTryConnect, "Connect", {200, 50}))
    --     self.connect_btn:SetPosition(0, -110, 0)
    -- else
    --     self.nonadmin_txt = self.root:AddChild(Text(CHATFONT, 38, "Only admins can\nchange connection\nsettings."))
    --     -- self.nonadmin_txt:SetRegionSize(240, 400)
    --     self.nonadmin_txt:SetHAlign(ANCHOR_MIDDLE)
    -- end
    self.details_text = self:AddChild(Text(CHATFONT, 28, "" , UICOLOURS.WHITE))
    self.details_text:SetPosition(0, 20, 0)

    self.status = self.root:AddChild(AP_Status(self, controls))
    self.status:SetPosition(0, -120, 0)
    self.opentrackerfn = function()
        if ThePlayer and ThePlayer.HUD then
            self:Hide()
            ThePlayer.HUD:DSTAP_OpenTrackerScreen()
        end
    end
    self.tracker_btn = self.root:AddChild(Templates.StandardButton(self.opentrackerfn, "Open Tracker", {200, 50}))
    self.tracker_btn:SetPosition(0, -70, 0)
    self:Hide()
    
    TheWorld:ListenForEvent("clientupdateinterfacestate", function() self:ConnectionStatusChange() end)    
    TheWorld:ListenForEvent("clientupdateapstate", function() self:ConnectionStatusChange() end)
    self:ConnectionStatusChange()
end)

function DSTAP_Menu:OpenDSTAPMenu()
    self:Show()
    self:ConnectionStatusChange()
end

function DSTAP_Menu:ConnectionStatusChange()
    if not self:IsVisible() then
        return
    end
    local interfaceping = TheWorld.dstap_interfacestate and tonumber(TheWorld.dstap_interfacestate) or 5000
    local interface_connected = interfaceping < 5000 and true or false
    local ap_connected = TheWorld.dstap_state
    local textwidth = 280
    if interface_connected and ap_connected then
        self.details_text:SetMultilineTruncatedString(STRINGS.UI.DSTAP_MENU_CONNECTED, 4, textwidth)
    elseif interface_connected then
        self.details_text:SetMultilineTruncatedString(STRINGS.UI.DSTAP_MENU_NOT_AP_CONNECTED, 4, textwidth)
    else
        self.details_text:SetMultilineTruncatedString(STRINGS.UI.DSTAP_MENU_NOT_CLIENT_CONNECTED, 4, textwidth)
    end
end

return DSTAP_Menu