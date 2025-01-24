require "util"
require "strings"
require "constants"

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
------------------
local PRETTYNAME_TO_ITEM_ID = {}
for id, v in pairs(ArchipelagoDST.ID_TO_ITEM) do
    PRETTYNAME_TO_ITEM_ID[v.prettyname] = id
end
------------------

local DEBUG_MODE = BRANCH == "dev"

--[[
TheScrapbookPartitions:WasSeenInGame("prefab")
TheScrapbookPartitions:SetSeenInGame("prefab")

TheScrapbookPartitions:WasViewedInScrapbook("prefab")
TheScrapbookPartitions:SetViewedInScrapbook("prefab")

TheScrapbookPartitions:WasInspectedByCharacter(inst, "wilson")
TheScrapbookPartitions:SetInspectedByCharacter(inst, "wilson")

TheScrapbookPartitions:DebugDeleteAllData()
TheScrapbookPartitions:DebugSeenEverything()
TheScrapbookPartitions:DebugUnlockEverything()
]]

local recipes_filter = require("recipes_filter")

local Screen = require "widgets/screen"
local Subscreener = require "screens/redux/subscreener"
local TextButton = require "widgets/textbutton"
local ImageButton = require "widgets/imagebutton"
local Menu = require "widgets/menu"
local Grid = require "widgets/grid"
local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"
local ScrollableList = require "widgets/scrollablelist"
local PopupDialogScreen = require "screens/redux/popupdialog"
local OnlineStatus = require "widgets/onlinestatus"
local TEMPLATES = require "widgets/redux/templates"
local TrueScrollArea = require "widgets/truescrollarea"
local UIAnim = require "widgets/uianim"

local dataset = require("screens/redux/scrapbookdata")
local trackerdataset = {}
local Logic = require("dstap_logic")

local PANEL_WIDTH = 1000
local PANEL_HEIGHT = 530
local SEARCH_BOX_HEIGHT = 40
local SEARCH_BOX_WIDTH = 300

local FILLER = "zzzzzzz"
local UNKNOWN = "unknown"

local UK_TINT = {0.5,0.5,0.5,1}
local CHECKED_TINT = {0.5,0.5,0.5,1}

local LOGIC_LEVELS = {
	NOT_A_CHECK = 0,
	NOT_IN_LOGIC = 1,
	HARD_IN_LOGIC = 2,
	IN_LOGIC = 3,
	CHECKED = 4,
}
local DSTAP_ATLASES = {
	["dstap_scrapbook_ap.tex"] = "images/dstap_scrapbook_ap.xml",
	["dstap_scrapbook_progression.tex"] = "images/dstap_scrapbook_progression.xml",
	["dstap_scrapbook_warning.tex"] = "images/dstap_scrapbook_warning.xml",
	["dstap_scrapbook_ool.tex"] = "images/dstap_scrapbook_ool.xml",
}

---------------------------------------
-- SEEDED RANDOM NUMBER
local A1, A2 = 727595, 798405 -- 5^17=D20*A1+A2
local D20, D40 = 1048576, 1099511627776 -- 2^20, 2^40
local X1, X2 = 0, 1

function rand()
  	local U = X2 * A2
  	local V = (X1 * A2 + X2 * A1) % D20
  	V = (V * D20 + U) % D40
  	X1 = math.floor(V / D20)
  	X2 = V - X1 * D20
  	return V / D40
end

function primeRand(seed)
	X1= seed
 	A1, A2 = 727595, 798405 -- 5^17=D20*A1+A2
	D20, D40 = 1048576, 1099511627776 -- 2^20, 2^40
	X2 = 1
end

--------------------------------------------------

local TrackerScreen = Class(Screen, function( self, prev_screen, default_section )
	Screen._ctor(self, "TrackerScreen")

    self.letterbox = self:AddChild(TEMPLATES.old.ForegroundLetterbox())
	self.root = self:AddChild(TEMPLATES.ScreenRoot("ScrapBook"))
    self.bg = self.root:AddChild(TEMPLATES.PlainBackground())

    -- if not TheScrapbookPartitions:ApplyOnlineProfileData() then
    --     local msg = not TheInventory:HasSupportForOfflineSkins() and (TheFrontEnd ~= nil and TheFrontEnd:GetIsOfflineMode() or not TheNet:IsOnlineMode()) and STRINGS.UI.SCRAPBOOK.ONLINE_DATA_USER_OFFLINE or STRINGS.UI.SCRAPBOOK.ONLINE_DATA_DOWNLOAD_FAILED
    --     self.sync_status = self.root:AddChild(Text(HEADERFONT, 24, msg, UICOLOURS.WHITE))
    --     self.sync_status:SetVAnchor(ANCHOR_TOP)
    --     self.sync_status:SetHAnchor(ANCHOR_RIGHT)
    --     local w, h = self.sync_status:GetRegionSize()
    --     self.sync_status:SetPosition(-w/2 - 2, -h/2 - 2) -- 2 Pixel padding, top right screen justification.
    -- end

	if DEBUG_MODE then
        self.debugentry = self.root:AddChild(TextButton())
        self.debugentry:SetTextSize(12)
        self.debugentry:SetFont(HEADERFONT)
        self.debugentry:SetVAnchor(ANCHOR_BOTTOM)
        self.debugentry:SetHAnchor(ANCHOR_RIGHT)
		self.debugentry:SetScaleMode(SCALEMODE_PROPORTIONAL)
		self.debugentry.clickoffset = Vector3(0, 0, 0)

        self.debugentry:SetOnClick(function()
            nolineprint(self.debugentry.build..".fla")
        end)
	end

	self.logic = Logic()

    self:SetTrackerDataSet()
	self:LinkDeps()

	self.closing = false
	self.columns_setting = Profile:GetScrapbookColumnsSetting()
	self.current_dataset = self:CollectType(trackerdataset,"overview")
	self.current_view_data = self:CollectType(trackerdataset,"overview")

    self:MakeSideBar()

	self.current_dataset = self:CollectType(trackerdataset,"overview")
	self.current_view_data = self:CollectType(trackerdataset,"overview")
    self:SelectSideButton("overview")

    self.title = self.root:AddChild(TEMPLATES.ScreenTitle(STRINGS.DSTAP_TRACKER.TITLE, ""))

	self:MakeBackButton()

    self.dialog = self.root:AddChild(TEMPLATES.RectangleWindow(PANEL_WIDTH, PANEL_HEIGHT))
    self.dialog:SetPosition(0, 0)

    self.detailsroot = self.dialog:AddChild(Widget("details_root"))
    self.detailsroot:SetPosition(-250,0)

    self.gridroot = self.dialog:AddChild(Widget("grid_root"))
    self.gridroot:SetPosition(240,0)

    self.item_grid = self.gridroot:AddChild( self:BuildItemGrid() )
    self.item_grid:SetPosition(0, 0)

    self.item_grid:SetItemsData(self.current_view_data)

	local grid_w, grid_h = self.item_grid:GetScrollRegionSize()

	self.details = self.detailsroot:AddChild(self:PopulateInfoPanel())

	-- self:MakeBottomBar()
	self:MakeTopBar()
	self:SetGrid()

	self.focus_forward = self.item_grid

	if TheInput:ControllerAttached() then
		self:SetFocus()
	end

	SetAutopaused(true)
end)


-- function TrackerScreen:SetPlayerKnowledge()
-- 	for prefab,data in pairs(dataset) do
-- 		data.logiclevel = TheScrapbookPartitions:GetLevelFor(prefab)
-- 	end
-- end

function TrackerScreen:SetTrackerDataSet()
	local hinted_locations = {}
	for _, infotable in pairs(ArchipelagoDST.LOCATION_HINT_INFO) do
		if infotable.location and ArchipelagoDST.missinglocations[infotable.location] then
			hinted_locations[infotable.location] = infotable
		end
	end
	for id, location in pairs(ArchipelagoDST.ID_TO_LOCATION) do
		if ArchipelagoDST.all_locations and ArchipelagoDST.all_locations[id] then
			local logiclevel = LOGIC_LEVELS.NOT_IN_LOGIC
			if ArchipelagoDST.missinglocations[id] then
				if self.logic:IsInLogic(id, "default") then
					logiclevel = LOGIC_LEVELS.IN_LOGIC
				elseif self.logic:IsInLogic(id, "hard") then
					logiclevel = LOGIC_LEVELS.HARD_IN_LOGIC
				end
			else
				logiclevel = LOGIC_LEVELS.CHECKED
			end
			-- Prefer the scrapbook alias if it exists otherwise use the location prefab
			local scrapbookalias = (
				ArchipelagoDST.RAW.LOCATION_SCRAPBOOK_ALIASES[id - ArchipelagoDST.RAW.LOCATION_ID_OFFSET]
				or (location.prefab and #location.prefab and ArchipelagoDST.RAW.LOCATION_SCRAPBOOK_ALIASES[location.prefab])
				or location.prefab
			)
			local set = deepcopy(dataset[scrapbookalias])
			if not set then print("WARNING: NO SET FOUND FOR : "..scrapbookalias) end
			if set then
				trackerdataset[id] = set
				set.id = id
				set.prettyname = location.prettyname
				set.scrapbooktype = set.type
				set.type = (
					((location.tags["task"] or location.tags["item"]) and "misc")
					or (location.tags["cooking"] and "cooking")
					or (location.tags["boss"] and "boss")
					or (location.tags["creature"] and "creature")
					or (location.tags["farming"] and "farming")
					or (location.tags["research"] and "research")
				)
				set.logiclevel = logiclevel
				set.hint = hinted_locations[id] or nil
			end
		end
	end
end

function TrackerScreen:LinkDeps()
	for entry, data in pairs(trackerdataset) do
		data.entry = entry -- Overwrite scrapbook's entry
	end
end

function TrackerScreen:FilterData(search_text, search_set)
	if not search_set then
		search_set = self:CollectType(trackerdataset)
	end

	if not search_text or search_text == "" then
		-- Return to last selected filter!
		self:SelectSideButton(self.last_filter)
		self.current_view_data = self:CollectType(trackerdataset, self.last_filter)
		return
	end

	local newset = {}
	for i,set in ipairs( search_set ) do
		local name = nil
		if set.type ~= UNKNOWN then
			-- name = TrimString(string.lower(STRINGS.NAMES[string.upper(set.name)])):gsub(" ", "")
			name = TrimString(string.lower(set.prettyname)):gsub(" ", "")

			local num = string.find(name, search_text, 1, true)
			if num then
				table.insert(newset,set)
			end
		end
	end

	self.current_view_data = newset
end

function TrackerScreen:SetSearchText(search_text)
	search_text = TrimString(string.lower(search_text)):gsub(" ", "")

	self:FilterData(search_text)

	self:SetGrid()
end

function TrackerScreen:MakeSearchBox(box_width, box_height)
    local searchbox = Widget("search")
	searchbox:SetHoverText(STRINGS.UI.CRAFTING_MENU.SEARCH, {offset_y = 30, attach_to_parent = self })

    searchbox.textbox_root = searchbox:AddChild(TEMPLATES.StandardSingleLineTextEntry(nil, box_width, box_height))
    searchbox.textbox = searchbox.textbox_root.textbox
    searchbox.textbox:SetTextLengthLimit(200)
    searchbox.textbox:SetForceEdit(true)
    searchbox.textbox:EnableWordWrap(false)
    searchbox.textbox:EnableScrollEditWindow(true)
    searchbox.textbox:SetHelpTextEdit("")
    searchbox.textbox:SetHelpTextApply(STRINGS.UI.SERVERCREATIONSCREEN.SEARCH)
    searchbox.textbox:SetTextPrompt(STRINGS.UI.SERVERCREATIONSCREEN.SEARCH, UICOLOURS.GREY)
    searchbox.textbox.prompt:SetHAlign(ANCHOR_MIDDLE)
    searchbox.textbox.OnTextInputted = function(keydown)
		if keydown then
			self:SelectSideButton()
			self:SetSearchText(self.searchbox.textbox:GetString())
		end
    end

     -- If searchbox ends up focused, highlight the textbox so we can tell something is focused.
    searchbox:SetOnGainFocus( function() searchbox.textbox:OnGainFocus() end )
    searchbox:SetOnLoseFocus( function() searchbox.textbox:OnLoseFocus() end )

    searchbox.focus_forward = searchbox.textbox

    return searchbox
end

function TrackerScreen:CollectType(set, filter)
	local newset = {}
	local blankset = {}
	local blank = {type=UNKNOWN, name=FILLER}
	for i,data in pairs(set)do
		local ok = false
		if filter and self.menubuttons then
			for i, button in ipairs (self.menubuttons) do
				if filter == button.filter and button.fn and button.fn(data) then
					ok = true
					break
				end
			end
		else
			ok = true
		end

		if data.logiclevel >= LOGIC_LEVELS.NOT_IN_LOGIC and ok then
			table.insert(newset,data)
			-- table.insert(newset,deepcopy(data))
		elseif ok then
			table.insert(blankset,deepcopy(blank))
		end
	end

	for i,blank in ipairs(blankset)do
		table.insert(newset,blank)
	end
	return newset
end

-- function TrackerScreen:updatemenubuttonflashes()

-- 	-- for i,button in ipairs(self.menubuttons)do
-- 	-- 	button.flash:Hide()
-- 	-- end
-- 	-- local noflash = true
-- 	-- for prefab,data in pairs(dataset)do
-- 	-- 	if not TheScrapbookPartitions:WasViewedInScrapbook(prefab) and data.logiclevel > 0 then
-- 	-- 		for i,button in ipairs(self.menubuttons)do
-- 	-- 			if button.filter == dataset[prefab].type then
-- 	-- 				button.flash:Show()
-- 	-- 				noflash = false
-- 	-- 			end
-- 	-- 		end
-- 	-- 	end
--  	-- end

--  	-- self.flashestoclear = true
--  	-- if noflash then
--  	-- 	self.flashestoclear = nil
--  	-- end

--  	-- if self.clearflash then
-- 	-- 	self.clearflash:Show()
-- 	--  	if noflash then
-- 	-- 		self.clearflash:Hide()
-- 	--  	end
--  	-- end
-- end

function TrackerScreen:SetGrid()
	if self.item_grid then
		self.gridroot:KillAllChildren()
	end
	self.item_grid = nil
	self.item_grid = self.gridroot:AddChild( self:BuildItemGrid(self.columns_setting) )
	self.item_grid:SetPosition(0, 0)
	local griddata = deepcopy(self.current_view_data)

	local setfocus = true
	if #griddata <= 0 then
		setfocus = false

		for i=1,self.columns_setting do
			table.insert(griddata,{name=FILLER})
		end
	end

	if #griddata%self.columns_setting > 0 then
		for i=1,self.columns_setting -(#self.current_view_data%self.columns_setting) do
			table.insert(griddata,{name=FILLER})
		end
	end

	self.item_grid:SetItemsData( griddata )
	local grid_w, grid_h = self.item_grid:GetScrollRegionSize()

	-- self:updatemenubuttonflashes()
	self:DoFocusHookups()
	self.focus_forward = self.item_grid

	TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/scrapbook_pageflip")

	if TheInput:ControllerAttached() then
		if setfocus and not self.searchbox.focus then
			self:SetFocus()
		else
			self.searchbox:SetFocus()
		end
	end
end

function TrackerScreen:SelectMenuItem(dir)
	local cat = "overview"
	if self.menubuttons_selected then
		local selected = nil
		for i,button in ipairs(self.menubuttons) do
			if button.filter ==  self.menubuttons_selected then
				selected = i
			end
		end
		if dir == "down" then
			if selected == #self.menubuttons then
				selected = 1
			else
				selected = selected +1
			end
		else
			if selected == 1 then
				selected = #self.menubuttons
			else
				selected = selected -1
			end
		end
		cat = self.menubuttons[selected].filter
	end

	self:SelectSideButton(cat)
	self.current_dataset = self:CollectType(trackerdataset,cat)
	self.current_view_data = self:CollectType(trackerdataset,cat)
	self:SetGrid()
end

function TrackerScreen:SelectSideButton(category)
	self.last_filter = self.menubuttons_selected or self.last_filter -- No nil value!
	self.menubuttons_selected = category

	for i, button in ipairs(self.menubuttons) do
		if button.filter == category then
			button.selectimg:Show()
		else
			button.selectimg:Hide()
		end

	end
end

function TrackerScreen:MakeSideBar()

	self.menubuttons = {}
	local colors = {
		{114/255,56/255,56/255},
		{111/255,85/255,47/255},
		{137/255,126/255,89/255},
		{177/255,159/255,73/255}, -- {195/255,179/255,109/255}
		{95/255,123/255,87/255},
		{113/255,127/255,126/255},
		{74/255,84/255,99/255},
		{79/255,73/255,107/255},
	}

	local goallocations = {}
	if ArchipelagoDST.goalinfo and ArchipelagoDST.goalinfo.goallist then
		for _, id in ipairs(ArchipelagoDST.goalinfo.goallist) do
			goallocations[id] = true
		end
	end
	local buttons = {
		{name="Overview",		filter="overview",		fn=function(tdata) return goallocations[tdata.id] or false end},
		{name="InLogic",		filter="inlogic",		fn=function(tdata) return ArchipelagoDST.missinglocations[tdata.id] and tdata.logiclevel >= LOGIC_LEVELS.IN_LOGIC end},
		{name="InHardLogic",	filter="inhardlogic",	fn=function(tdata) return ArchipelagoDST.missinglocations[tdata.id] and tdata.logiclevel == LOGIC_LEVELS.HARD_IN_LOGIC end},
		-- {name="All",			filter="all",			fn=function(tdata) return true end},
		{name="Missing",		filter="missing",		fn=function(tdata) return ArchipelagoDST.missinglocations[tdata.id] and true or false end},
		{name="Checked",		filter="checked",		fn=function(tdata) return not ArchipelagoDST.missinglocations[tdata.id] end},
		{name="Hinted",			filter="hinted",		fn=function(tdata) return tdata.hint and true or false end},
		{name="Misc",			filter="misc",			fn=function(tdata) return tdata.type == "misc" or tdata.type == "farming" end},
		{name="Dishes",			filter="cooking",		fn=function(tdata) return tdata.type == "cooking" end},
		{name="Creatures",		filter="creature",		fn=function(tdata) return tdata.type == "creature" or tdata.type == "boss" end},
		{name="Research",		filter="research",		fn=function(tdata) return tdata.type == "research" end},
	}

	for i, button in ipairs(buttons)do
		local idx = i % #colors
		if idx == 0 then idx = #colors end
		button.color = colors[idx]
	end

	local buttonwidth = 252/2.2--75
	local buttonheight = 112/2.2--30

	-- PANEL_HEIGHT

	local totalheight = PANEL_HEIGHT - 100

	local MakeButton = function(idx,data)

		local y = totalheight/2 - ((totalheight/9) * idx-1) + 50

		local buttonwidget = self.root:AddChild(Widget())

		local button = buttonwidget:AddChild(ImageButton("images/scrapbook.xml", "tab.tex"))
		button:ForceImageSize(buttonwidth,buttonheight)
		button.scale_on_focus = false
		button.basecolor = {data.color[1],data.color[2],data.color[3]}
		button:SetImageFocusColour(math.min(1,data.color[1]*1.2),math.min(1,data.color[2]*1.2),math.min(1,data.color[3]*1.2),1)
		button:SetImageNormalColour(data.color[1],data.color[2],data.color[3],1)
		button:SetImageSelectedColour(data.color[1],data.color[2],data.color[3],1)
		button:SetImageDisabledColour(data.color[1],data.color[2],data.color[3],1)
		button:SetOnClick(function()
				self:SelectSideButton(data.filter)
				self.current_dataset = self:CollectType(trackerdataset,data.filter)
				self.current_view_data = self:CollectType(trackerdataset,data.filter)
				if data.filter == "overview" then
					self:SelectEntry()
				end
				self:SetGrid()
			end)

		buttonwidget.focusimg = button:AddChild(Image("images/scrapbook.xml", "tab_over.tex"))
		buttonwidget.focusimg:ScaleToSize(buttonwidth,buttonheight)
		buttonwidget.focusimg:SetClickable(false)
		buttonwidget.focusimg:Hide()

		buttonwidget.selectimg = button:AddChild(Image("images/scrapbook.xml", "tab_selected.tex"))
		buttonwidget.selectimg:ScaleToSize(buttonwidth,buttonheight)
		buttonwidget.selectimg:SetClickable(false)
		buttonwidget.selectimg:Hide()

		buttonwidget:SetOnGainFocus(function()
			buttonwidget.focusimg:Show()
		end)
		buttonwidget:SetOnLoseFocus(function()
			buttonwidget.focusimg:Hide()
		end)

		local text = button:AddChild(Text(HEADERFONT, 12, STRINGS.DSTAP_TRACKER.CATS[string.upper(data.name)] , UICOLOURS.WHITE))
		text:SetPosition(10,-8)
		buttonwidget:SetPosition(522+buttonwidth/2, y)

		local total = 0
		local count = 0
		for i,set in pairs(trackerdataset)do
			if data.fn(set) then -- set.type == data.filter
				total = total +1
				-- if set.logiclevel >= LOGIC_LEVELS.IN_LOGIC then
					count = count+1
				-- end
			end
		end
		if total > 0 then

 			-- local percent = (count/total)*100
			-- if percent < 1 then
			-- 	percent = math.floor(percent*100)/100
			-- else
			-- 	percent = math.floor(percent)
			-- end

			local progress = buttonwidget:AddChild(Text(HEADERFONT, 14, count , UICOLOURS.GOLD))
			progress:SetPosition(15,15)
		end

		buttonwidget.newcreatures = {}

		buttonwidget.flash = buttonwidget:AddChild(UIAnim())
		buttonwidget.flash:GetAnimState():SetBank("cookbook_newrecipe")
		buttonwidget.flash:GetAnimState():SetBuild("cookbook_newrecipe")
		buttonwidget.flash:GetAnimState():PlayAnimation("anim", true)
		buttonwidget.flash:GetAnimState():SetDeltaTimeMultiplier(1.25)
		buttonwidget.flash:SetScale(.8, .8, .8)
		buttonwidget.flash:SetPosition(40, 0, 0)
		buttonwidget.flash:Hide()
		buttonwidget.flash:SetClickable(false)

		buttonwidget.filter = data.filter
		buttonwidget.fn = data.fn
		buttonwidget.focus_forward = button

		table.insert(self.menubuttons,buttonwidget)
	end

	for i,data in ipairs(buttons)do
		MakeButton(i,data)
	end
end

-- function TrackerScreen:ClearFlashes()
-- 	-- for prefab,data in pairs(dataset)do
--     --     if TheScrapbookPartitions:GetLevelFor(prefab) > 0 then
-- 	-- 	    TheScrapbookPartitions:SetViewedInScrapbook(prefab)
--     --     end
-- 	-- end
-- 	self:SetGrid()
-- end



function TrackerScreen:MakeTopBar()
	self.search_text = ""

	self.searchbox = self.root:AddChild(self:MakeSearchBox(300, SEARCH_BOX_HEIGHT))
	self.searchbox:SetPosition(220, PANEL_HEIGHT/2 +33)

	self.display_col_1_button = self.root:AddChild(ImageButton("images/scrapbook.xml", "sort1.tex"))
	self.display_col_1_button:SetPosition(220+(SEARCH_BOX_WIDTH/2)+28, PANEL_HEIGHT/2 +33)
	self.display_col_1_button:ForceImageSize(25,25)
	self.display_col_1_button.scale_on_focus = false
	self.display_col_1_button.focus_scale = {1.1,1.1,1.1}
	self.display_col_1_button.ignore_standard_scaling = true
	self.display_col_1_button:SetOnClick(function()
		if self.columns_setting ~= 1 then
			self.columns_setting = 1
			self:SetGrid()

			Profile:SetScrapbookColumnsSetting(self.columns_setting)
		end
	end)

	self.display_col_2_button = self.root:AddChild(ImageButton("images/scrapbook.xml", "sort2.tex"))
	self.display_col_2_button:SetPosition(220+(SEARCH_BOX_WIDTH/2)+28+28, PANEL_HEIGHT/2 +33)
	self.display_col_2_button:ForceImageSize(25,25)
	self.display_col_2_button.scale_on_focus = false
	self.display_col_2_button.focus_scale = {1.1,1.1,1.1}
	self.display_col_2_button.ignore_standard_scaling = true
	self.display_col_2_button:SetOnClick(function()
		if self.columns_setting ~= 2 then
			self.columns_setting = 2
			self:SetGrid()

			Profile:SetScrapbookColumnsSetting(self.columns_setting)
		end
	end)

	self.display_col_3_button = self.root:AddChild(ImageButton("images/scrapbook.xml", "sort3.tex"))
	self.display_col_3_button:SetPosition(220+(SEARCH_BOX_WIDTH/2)+28+28+28, PANEL_HEIGHT/2 +33)
	self.display_col_3_button:ForceImageSize(25,25)
	self.display_col_3_button.scale_on_focus = false
	self.display_col_3_button.focus_scale = {1.1,1.1,1.1}
	self.display_col_3_button.ignore_standard_scaling = true
	self.display_col_3_button:SetOnClick(function()
		if self.columns_setting ~= 3 then
			self.columns_setting = 3
			self:SetGrid()

			Profile:SetScrapbookColumnsSetting(self.columns_setting)
		end
	end)

	self.display_col_grid_button = self.root:AddChild(ImageButton("images/scrapbook.xml", "sort4.tex"))
	self.display_col_grid_button:SetPosition(220+(SEARCH_BOX_WIDTH/2)+28+28+28+28, PANEL_HEIGHT/2 +33)
	self.display_col_grid_button:ForceImageSize(25,25)
	self.display_col_grid_button.scale_on_focus = false
	self.display_col_grid_button.focus_scale = {1.1,1.1,1.1}
	self.display_col_grid_button.ignore_standard_scaling = true
	self.display_col_grid_button:SetOnClick(function()
		if self.columns_setting ~= 7 then
			self.columns_setting = 7
			self:SetGrid()

			Profile:SetScrapbookColumnsSetting(self.columns_setting)
		end
	end)

	self.topbuttons = {}
	table.insert(self.topbuttons, self.searchbox)
	table.insert(self.topbuttons, self.display_col_1_button)
	table.insert(self.topbuttons, self.display_col_2_button)
	table.insert(self.topbuttons, self.display_col_3_button)
	table.insert(self.topbuttons, self.display_col_grid_button)
end

function TrackerScreen:MakeBackButton()
	self.cancel_button = self.root:AddChild(TEMPLATES.BackButton(
		function()
			self:Close() --go back
		end))
end

function TrackerScreen:Close(fn)
    TheFrontEnd:FadeBack(nil, nil, fn)
end

function TrackerScreen:GetData(id)
	if trackerdataset[id] then
		return trackerdataset[id]
	end
end

function TrackerScreen:BuildItemGrid()
	self.MISSING_STRINGS = {}
	local totalwidth = 465
	local columns = self.columns_setting
	local imagesize = 32
	local bigimagesize = 64
	local imagebuffer = 6
	local row_w = totalwidth/columns

	if columns > 3 then
 		imagesize = bigimagesize
 		imagebuffer = 12
 		row_w = imagesize
	end

	local row_h = imagesize

    local row_spacing = 5
    local bg_padding = 3
    local name_pos = -5
    local catname_pos = 8

	table.sort(self.current_view_data, function(a, b) return a.id < b.id end)

	for i, data in ipairs(self.current_view_data) do
		data.index = i
	end

    local function ScrollWidgetsCtor(context, index)
        local w = Widget("recipe-cell-".. index)

		----------------
		w.item_root = w:AddChild(Widget("item_root"))

		w.item_root.bg = w.item_root:AddChild(Image("images/global.xml", "square.tex"))
		w.item_root.bg:ScaleToSize(totalwidth+((row_spacing+bg_padding)*columns), row_h+bg_padding)
		w.item_root.bg:SetPosition(-(((columns-1)*.5) * row_w),0)
		w.item_root.bg:SetTint(1,1,1,0.1)

		w.item_root.button = w.item_root:AddChild(ImageButton("images/global.xml", "square.tex"))
		w.item_root.button:SetImageNormalColour(1,1,1,0)
		w.item_root.button:SetImageFocusColour(1,1,1,0.3)
		w.item_root.button.scale_on_focus = false
		w.item_root.button.clickoffset = Vector3(0, 0, 0)
		w.item_root.button:ForceImageSize(row_w+bg_padding, row_h+bg_padding)

		w.item_root.image = w.item_root:AddChild(Image(GetScrapbookIconAtlas("cactus.tex"), "cactus.tex"))
		w.item_root.image:ScaleToSize(imagesize, imagesize)
		w.item_root.image:SetPosition((-row_w/2)+imagesize/2,0 )
		w.item_root.image:SetClickable(false)

		w.item_root.inv_image = w.item_root:AddChild(Image(GetScrapbookIconAtlas("cactus.tex"), "cactus.tex"))
		w.item_root.inv_image:ScaleToSize(imagesize-imagebuffer, imagesize-imagebuffer)
		w.item_root.inv_image:SetPosition((-row_w/2)+imagesize/2,0 )
		w.item_root.inv_image:SetClickable(false)
		w.item_root.inv_image:Hide()

		w.item_root.name = w.item_root:AddChild(Text(HEADERFONT, 18, "NAME OF CRITTER", UICOLOURS.WHITE))
		w.item_root.name:SetPosition((-row_w/2)+imagesize + 5 ,name_pos)

		w.item_root.catname = w.item_root:AddChild(Text(HEADERFONT, 10, "NAME OF CRITTER", UICOLOURS.GOLD))
		w.item_root.catname:SetPosition((-row_w/2)+imagesize + 5 ,catname_pos)

		w.item_root.flash =w.item_root:AddChild(UIAnim())
		w.item_root.flash:GetAnimState():SetBank("cookbook_newrecipe")
		w.item_root.flash:GetAnimState():SetBuild("cookbook_newrecipe")
		w.item_root.flash:GetAnimState():PlayAnimation("anim", true)
		w.item_root.flash:GetAnimState():PlayAnimation("anim", true)
		w.item_root.flash:GetAnimState():SetDeltaTimeMultiplier(1.25)
		w.item_root.flash:SetScale(.5, .5, .5)
		w.item_root.flash:SetPosition((-row_w/2)+imagesize-(imagesize*0.1), (-row_h/2)+imagesize-(imagesize*0.1))
		w.item_root.flash:Hide()
		w.item_root.flash:SetClickable(false)

		w.item_root.button:SetOnClick(function()

			-- if ThePlayer and ThePlayer.scrapbook_seen then
			-- 	if ThePlayer.scrapbook_seen[w.data.prefab] then
			-- 		ThePlayer.scrapbook_seen[w.data.prefab] = nil
			-- 		w.item_root.flash:Hide()
			-- 	end
			-- end

			-- self:updatemenubuttonflashes()

			if self.details.entry ~= w.data.entry then
				self.detailsroot:KillAllChildren()
				self.details = nil
				self.details = self.detailsroot:AddChild(self:PopulateInfoPanel(w.data.entry))
				self:DoFocusHookups()
			end
		end)


		w.item_root.ongainfocusfn = function()
			self.lastselecteditem = w.item_root.button
		end

		w.focus_forward = w.item_root.button

		w.item_root.button:SetOnGainFocus(function()
			self.item_grid:OnWidgetFocus(w)
		end)

		----------------
		return w
    end

    local function ScrollWidgetSetData(context, widget, data, index)
		widget.item_root.image:SetTint(1,1,1,1)
		widget.item_root.inv_image:SetTint(1,1,1,1)
		widget.item_root.flash:Hide()

		widget.data = data

		if data ~= nil and data.name ~= FILLER and data.type ~= UNKNOWN then
			widget.item_root.image:Show()
			widget.item_root.button:Show()
			if not widget.item_root.button:IsEnabled() then
				widget.item_root.button:Enable()
			end

			if columns <= 3 then
				widget.item_root.name:Show()
			else
				widget.item_root.name:Hide()
			end
			widget.item_root.catname:Hide()
			widget.item_root.inv_image:Hide()

			if data.scrapbooktype == "item" or data.scrapbooktype == "food" then
				widget.item_root.image:SetTexture("images/scrapbook.xml", "inv_item_background.tex")
				widget.item_root.image:ScaleToSize(imagesize, imagesize)
				widget.item_root.inv_image:Show()
				widget.item_root.inv_image:SetTexture(GetInventoryItemAtlas(data.tex), data.tex)
				widget.item_root.inv_image:ScaleToSize(imagesize-imagebuffer, imagesize-imagebuffer)
			else
				widget.item_root.image:SetTexture(GetScrapbookIconAtlas(data.tex) or GetScrapbookIconAtlas("cactus.tex"), data.tex or "cactus.tex")
			end

			-- if data.logiclevel <= LOGIC_LEVELS.HARD_IN_LOGIC then
			-- 	widget.item_root.inv_image:SetTint(unpack(UK_TINT))
			-- 	widget.item_root.image:SetTint(unpack(UK_TINT))
			-- end
			if not ArchipelagoDST.missinglocations[data.id] then
				widget.item_root.inv_image:SetTint(unpack(CHECKED_TINT))
				widget.item_root.image:SetTint(unpack(CHECKED_TINT))
			end

			if columns <= 3 then
				-- local name = STRINGS.NAMES[string.upper(data.name)]
				local name = data.prettyname
				local maxwidth = row_w - imagesize - 15

				--maxcharsperline, ellipses, shrink_to_fit, min_shrink_font_size, linebreak_string)
				widget.item_root.name:SetTruncatedString(name, maxwidth, nil, true)
				local tw, th = widget.item_root.name:GetRegionSize()
				widget.item_root.name:SetPosition((-row_w/2)+imagesize + 5 +(tw/2) ,name_pos)

				-- if data.subcat  then
				-- 	widget.item_root.catname:Show()
				-- 	local subcat = STRINGS.SCRAPBOOK.SUBCATS[string.upper(data.subcat)]
				-- 	widget.item_root.catname:SetTruncatedString(subcat.."/", maxwidth, nil, true)
				-- 	local tw, th = widget.item_root.catname:GetRegionSize()
				-- 	widget.item_root.catname:SetPosition((-row_w/2)+imagesize + 5 +(tw/2) ,catname_pos)
				-- end
			end

			widget.item_root.button:SetOnClick(function()
				widget.item_root.flash:Hide()
				-- self:updatemenubuttonflashes()

				if self.details.entry ~= widget.data.entry then
					self.detailsroot:KillAllChildren()
					self.details = nil
					self.details = self.detailsroot:AddChild(self:PopulateInfoPanel(widget.data.entry))
					self:DoFocusHookups()
					TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/scrapbook_pageflip")
				end
			end)
		else
			if data and data.type == UNKNOWN then
				widget.item_root.image:SetTexture(GetScrapbookIconAtlas("unknown.tex"), "unknown.tex")
				widget.item_root.image:Show()
				widget.item_root.button:Show()
				widget.item_root.image:SetTint(1,1,1,1)
				widget.item_root.flash:Hide()
				widget.item_root.image:ScaleToSize(imagesize, imagesize)
			else
				widget.item_root.image:Hide()

				if not TheInput:ControllerAttached() then
					widget.item_root.button:Hide()
				end
			end

			widget.item_root.button:SetOnClick(function()
			end)

			widget.item_root.name:Hide()
			widget.item_root.catname:Hide()
			widget.item_root.inv_image:Hide()
		end

		if data and data.name ~= FILLER and data.type ~= UNKNOWN then
			-- if not TheScrapbookPartitions:WasViewedInScrapbook(data.prefab) then
			-- 	widget.item_root.flash:Show()
			-- else
				widget.item_root.flash:Hide()
			-- end
		end

		if columns > 3 then
			widget.item_root.bg:Hide()
		else
			if index % (columns *2) ~= 0 then
				widget.item_root.bg:Hide()
			else
				widget.item_root.bg:Show()
			end
		end

    end

    local grid = TEMPLATES.ScrollingGrid(
        {},
        {
            context = {},
            widget_width  = row_w+row_spacing,
            widget_height = row_h+row_spacing,
			force_peek    = true,
            num_visible_rows = imagesize == bigimagesize and 7 or 13,
            num_columns      = columns,
            item_ctor_fn = ScrollWidgetsCtor,
            apply_fn     = ScrollWidgetSetData,
            scrollbar_offset = 20,
            scrollbar_height_offset = -60
        })

    return grid
end

function calculteRotatedHeight(angle,w,h)
	return math.sin(angle*DEGREES)*w  +  math.sin((90-angle)*DEGREES)*h
end

function calculteRotatedWidth(angle,w,h)
	return math.cos(angle*DEGREES)*w  +  math.cos((90-angle)*DEGREES)*h
end

function TrackerScreen:PopulateInfoPanel(entry, showoverview)
	local data = self:GetData(entry)

	primeRand(hash((data and data.name or "")..ThePlayer.userid))

    local page = Widget("page")
    -- if data then TheScrapbookPartitions:SetViewedInScrapbook(data.prefab) end
	-- self:updatemenubuttonflashes()

	page.entry = entry -- data and data.scrapbookalias or nil

    page:SetPosition(-PANEL_WIDTH/4 - 20,0)

    local sub_root = Widget("text_root")

	local width = PANEL_WIDTH/2-40

	local left = 0
	local height = 0
	local title_space = 5
	local section_space = 22

	local applytexturesize = function(widget,w,h, tex, source)
		local suffix = "_square"
		local ratio = w/h
		if ratio > 5 then
			suffix = "_thin"
		elseif ratio > 1 then
			suffix = "_wide"
		elseif ratio < 0.75 then
			suffix = "_tall"
		end

		local materials = {
			"scrap",
			"scrap2",
		}
		if not tex then
			tex = materials[math.ceil(rand()*#materials)]..suffix.. ".tex"
		end
		if not source then
			source = "images/scrapbook.xml"
		end

		widget:SetTexture(source, tex, tex)
		widget:ScaleToSize(w,h)
	end

	local setattachmentdetils = function (widget,w,h, shortblock)
		local choice = rand()

		if choice < 0.4 and not shortblock then
			-- picture tabs
			local mat = "corner.tex"
			if rand() < 0.5 then
				mat = "corner2.tex"
			end
			local tape1 = widget:AddChild(Image("images/scrapbook.xml", mat))
			tape1:SetScale(0.5)
			tape1:SetClickable(false)
			tape1:SetPosition(-w/2+15,-h/2+15)
			tape1:SetRotation(0)

			local tape2 = widget:AddChild(Image("images/scrapbook.xml", mat))
			tape2:SetScale(0.5)
			tape2:SetClickable(false)
			tape2:SetPosition(-w/2+15,h/2-15)
			tape2:SetRotation(90)

			local tape3 = widget:AddChild(Image("images/scrapbook.xml", mat))
			tape3:SetScale(0.5)
			tape3:SetClickable(false)
			tape3:SetPosition(w/2-15,h/2-15)
			tape3:SetRotation(180)

			local tape4 = widget:AddChild(Image("images/scrapbook.xml", mat))
			tape4:SetScale(0.5)
			tape4:SetClickable(false)
			tape4:SetPosition(w/2-15,-h/2+15)
			tape4:SetRotation(270)
		elseif choice < 0.7 then
			local tape1 = widget:AddChild(Image("images/scrapbook.xml", "tape".. math.ceil(rand()*2).."_centre.tex"))
			tape1:SetScale(0.5)
			tape1:SetClickable(false)
			tape1:SetPosition(0,h/2)
			tape1:SetRotation(rand()*3- 1.5)
		elseif choice < 0.8 then
			--tape
			local diagonal = false
			local right = true
			if shortblock then
				if rand()<0.3 then
					diagonal = true
					if rand()<0.5 then
						right = false
					end
				end
			end
			if (rand() < 0.5 and not shortblock) or (diagonal==true and right==false) then
				local tape1 = widget:AddChild(Image("images/scrapbook.xml", "tape".. math.ceil(rand()*2).."_corner.tex"))
				tape1:SetScale(0.5)
				tape1:SetClickable(false)
				tape1:SetPosition(-w/2+5,-h/2+5)
				local rotation = -45
				tape1:SetRotation(rotation)
			end

			if not diagonal or right then
				local tape2 = widget:AddChild(Image("images/scrapbook.xml", "tape".. math.ceil(rand()*2).."_corner.tex"))
				tape2:SetScale(0.5)
				tape2:SetClickable(false)
				tape2:SetPosition(-w/2+5,h/2-5)
				local rotation = 45
				tape2:SetRotation(rotation)
			end

			if not diagonal or right == false then
				local tape3 = widget:AddChild(Image("images/scrapbook.xml", "tape".. math.ceil(rand()*2).."_corner.tex"))
				tape3:SetScale(0.5)
				tape3:SetClickable(false)
				tape3:SetPosition(w/2-5,h/2-5)
				local rotation = 90 +45
				tape3:SetRotation(rotation)
			end

			if (rand() < 0.5 and not shortblock) or (diagonal==true and right==true) then
				local tape4 = widget:AddChild(Image("images/scrapbook.xml", "tape".. math.ceil(rand()*2).."_corner.tex"))
				tape4:SetScale(0.5)
				tape4:SetClickable(false)
				tape4:SetPosition(w/2-5,-h/2+5)
				local rotation = -90 - 45
				tape4:SetRotation(rotation)
			end
		else
			local ropechoice = math.ceil(rand()*3)
			local rope = widget:AddChild(Image("images/scrapbook.xml", "rope".. ropechoice.."_corner.tex"))
			rope:SetScale(0.5)
			rope:SetClickable(false)
			if ropechoice == 1 then
				rope:SetPosition(-w/2+5,h/2-10)
			elseif ropechoice == 3 then
				rope:SetPosition(-w/2+5,h/2-13)
			else
				rope:SetPosition(-w/2+13,h/2-16)
			end
		end
	end

	local settextblock = function (height, data) -- font, size, str, color,leftmargin,rightmargin, leftoffset, ignoreheightchange, widget
		assert(data.font and data.size and data.str and data.color, "Missing String Data")
		local targetwidget = data.widget and data.widget or sub_root
		local txt = targetwidget:AddChild(Text(data.font, data.size, data.str, data.color))
		txt:SetHAlign(ANCHOR_LEFT)
		txt:SetVAlign(ANCHOR_TOP)
		local subwidth = data.width or width
		local adjustedwidth = subwidth - (data.leftmargin and data.leftmargin or 0) - (data.rightmargin and data.rightmargin or 0)
		txt:SetMultilineTruncatedString(data.str, 100, adjustedwidth)
		local x, y = txt:GetRegionSize()
		local adjustedleft = left + (data.leftmargin and data.leftmargin or 0) + (data.leftoffset and data.leftoffset or 0)
		txt:SetPosition(adjustedleft + (0.5 * x) , height - (0.5 * y))
		if not data.ignoreheightchange then
			height = height - y - section_space
		end

		return height, txt
	end

	local setimageblock = function(height, data) -- source, tex, w,h,rotation,leftoffset, ignoreheightchange, widget)
		assert(data.source and data.tex, "Missing Image Data")
		local targetwidget = data.widget and data.widget or sub_root
		local img = targetwidget:AddChild(Image(data.source, data.tex))
		if data.w and data.h then
			applytexturesize(img,w,h, data.source, data.tex)
		end
		if data.rotation then
			img:SetRotation(data.rotation)
		end
		local x, y = img:GetSize()
		local truewidth = calculteRotatedWidth(data.rotation and data.rotation or 0,x,y)
		local trueheight = calculteRotatedHeight(data.rotation and data.rotation or 0,x,y)
		local adjustedoffset = data.leftoffset and data.leftoffset or  0
		img:SetPosition(left + truewidth + adjustedoffset, height - (0.5 * trueheight))
		img:SetClickable(false)
		if not data.ignoreheightchange then
			height = height - trueheight - section_space
		end

		return height, img
	end

	local setcustomblock = function(height,data)
		local panel = sub_root:AddChild(Widget("custompanel"))
		local bg
		height, bg = setimageblock(height,{ignoreheightchange=true, widget=panel, source="images/scrapbook.xml", tex="scrap_square.tex"})

		local shade = 0.8 + rand()*0.2
		bg:SetTint(shade,shade,shade,1)

		local MARGIN = data.margin and data.margin or 15
		local textblock
		height, textblock = settextblock(height, {str=data.str, width=data.width or nil, font=data.font or CHATFONT, size=data.size or 15, color=data.fontcolor or UICOLOURS.BLACK, leftmargin=MARGIN+50, rightmargin=MARGIN+50, leftoffset = -width/2, ignoreheightchange=true, widget=panel})
		local pos_t = textblock:GetPosition()
		textblock:SetPosition(0,0)

		local w,h= textblock:GetRegionSize()
		local boxwidth = w+(MARGIN*2)
		local widthdiff = 0
		if data.minwidth and boxwidth < data.minwidth then
			widthdiff = data.minwidth - boxwidth
			boxwidth = data.minwidth
		end

		applytexturesize(bg, boxwidth,h+(MARGIN*2))

		local angle =  data.norotation and 0 or rand()*3- 1.5
 		panel:SetRotation(angle)

		pos_t = textblock:GetPosition()
		bg:SetPosition(0,0)

 		local attachments = panel:AddChild(Widget("attachments"))
 		attachments:SetPosition(0,0)
 		setattachmentdetils(attachments, boxwidth,h+(MARGIN*2), data.shortblock)
 		local newheight = calculteRotatedHeight(angle,boxwidth,h+(MARGIN*2))
 		--
		panel:SetPosition( boxwidth/2 + (data.leftoffset or 0) ,height - (newheight/2) - (data.topoffset or 0))
		if not data.ignoreheightchange then
			height = height - newheight - section_space
		end
 		return height, panel, newheight
	end
	---------------------------------
	-- set the title
	local cattitle
	-- if data and data.subcat then
	-- 	local subcat = STRINGS.SCRAPBOOK.SUBCATS[string.upper(data.subcat)]
	-- 	height, cattitle = settextblock(height, {font=HEADERFONT, size=25, str= subcat.."/  ", color=UICOLOURS.GOLD,  ignoreheightchange=true})
	-- end

	local title
	local leftoffset = 0
	if cattitle then
		leftoffset = cattitle:GetRegionSize()
	end

	-- local name = data ~= nil and STRINGS.NAMES[string.upper(data.name)] or ""
	local goalinfo = ArchipelagoDST.goalinfo or {goal="unknown"}
	local goalname = (
		(goalinfo.goal == "survival" and "Survival Goal")
		or ((goalinfo.goal == "bosses_any" or goalinfo.goal == "bosses_all") and "Boss Goal")
	)
	local name = data ~= nil and data.prettyname or goalname or ""

	height, title = settextblock(height, {font=HEADERFONT, size=25, str=name, color=UICOLOURS.WHITE, leftoffset=leftoffset})

	------------------------------------

	height = height  - 10

	-- set the photo
	local rotation = (rand() * 5)-2.5

	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--------------------------------------------------------------------------------------------------------------------------------------------------------------

	local CUSTOM_SIZE = Vector3(150,250,0)
	local CUSTOM_ANIMOFFSET = Vector3(0,-40,0)
	local CUSTOM_INDENT = 40 + (rand() * 25)

	local STAT_PANEL_WIDTH = 220
	local STAT_PANEL_INDENT = 30
	local STAT_GAP_SMALL = 5
	local STAT_ICONSIZE = 32

	local stats,statsheight

	local statwidget = 	sub_root:AddChild(Widget("statswidget"))
	local statbg = statwidget:AddChild(Image("images/fepanel_fills.xml", "panel_fill_large.tex"))
	local statsheight = 0
	statsheight = statsheight - STAT_PANEL_INDENT

	local showstats = false
	local makeentry = function(tex,text)
		showstats = true
		if tex then
			local atlas = DSTAP_ATLASES[tex] or GetScrapbookIconAtlas(tex) or GetScrapbookIconAtlas("cactus.tex")
			local icon = statwidget:AddChild(Image(atlas, tex))
			icon:ScaleToSize(STAT_ICONSIZE,STAT_ICONSIZE)
			icon:SetPosition(STAT_PANEL_INDENT+(STAT_ICONSIZE/2), statsheight-STAT_ICONSIZE/2)
		end
		local txt = statwidget:AddChild(Text(HEADERFONT, 18, text, UICOLOURS.BLACK))
		local tw, th = txt:GetRegionSize()
		txt:SetPosition(STAT_PANEL_INDENT+STAT_ICONSIZE + STAT_GAP_SMALL + (tw/2), statsheight-(STAT_ICONSIZE/2)-2)
		txt:SetHAlign(ANCHOR_LEFT)
		statsheight = statsheight - STAT_ICONSIZE - STAT_GAP_SMALL
	end
	local makesubentry = function(text)
		showstats = true
		local txt = statwidget:AddChild(Text(HEADERFONT, 12, text, UICOLOURS.BLACK))
		local tw, th = txt:GetRegionSize()
		txt:SetPosition(STAT_PANEL_INDENT+STAT_ICONSIZE + STAT_GAP_SMALL + (tw/2), statsheight+STAT_GAP_SMALL)
		statsheight = statsheight - STAT_GAP_SMALL
	end

	local makesubiconentry = function(tex,subwidth,text)
		showstats = true
		local icon = statwidget:AddChild(Image(GetScrapbookIconAtlas(tex) or GetScrapbookIconAtlas("cactus.tex"), tex))
		icon:ScaleToSize(STAT_ICONSIZE,STAT_ICONSIZE)
		icon:SetPosition(STAT_PANEL_INDENT+ subwidth +(STAT_ICONSIZE/2), statsheight+STAT_GAP_SMALL+(STAT_ICONSIZE/2) )
		local txt = statwidget:AddChild(Text(HEADERFONT, 18, text, UICOLOURS.BLACK))
		local tw, th = txt:GetRegionSize()
		txt:SetPosition(STAT_PANEL_INDENT+ subwidth +STAT_ICONSIZE + (tw/2), statsheight+STAT_GAP_SMALL+(STAT_ICONSIZE/2)-2)		--+ STAT_GAP_SMALL
		subwidth = subwidth + STAT_ICONSIZE+ tw
		return subwidth
	end

	local makelistentry = function(textures, texts, iconsize, maxgap)
		local x = 75
		local addedtext = false

		statsheight = statsheight - 5

		for i, iconname in ipairs(textures) do
			local tex = iconname .. ".tex"
			local icon = statwidget:AddChild(Image(GetScrapbookIconAtlas(tex) or GetInventoryItemAtlas(tex), tex))
			icon:ScaleToSize(iconsize, iconsize)
			icon:SetPosition(x, statsheight)

			if texts ~= nil and texts[i] ~= nil then
				addedtext = true

				local txt = statwidget:AddChild(Text(HEADERFONT, 13, texts[i], UICOLOURS.BLACK))
				txt:SetPosition(x, statsheight - iconsize)
			end

			x =  x + math.min((140/#textures), maxgap or math.huge)
		end

		statsheight = statsheight - iconsize - STAT_GAP_SMALL * (addedtext and 3 or 0)
	end

	---------------------------------------------
	if data then
		-- AP logic tags
		if ArchipelagoDST.missinglocations[data.id] then
			if data.logiclevel == LOGIC_LEVELS.NOT_IN_LOGIC then
				makeentry("dstap_scrapbook_ool.tex", STRINGS.DSTAP_TRACKER.DATA_NOT_IN_LOGIC)
			elseif data.logiclevel == LOGIC_LEVELS.HARD_IN_LOGIC then
				makeentry("dstap_scrapbook_warning.tex", STRINGS.DSTAP_TRACKER.DATA_HARD_IN_LOGIC)
			elseif data.logiclevel >= LOGIC_LEVELS.IN_LOGIC then
				makeentry("dstap_scrapbook_progression.tex", STRINGS.DSTAP_TRACKER.DATA_IN_LOGIC)
			end
		else
			makeentry("dstap_scrapbook_ap.tex", STRINGS.DSTAP_TRACKER.DATA_CHECKED)
		end

		-- Stats
		if data.health then
			makeentry("icon_health.tex", tostring(checknumber(data.health) and math.floor(data.health) or data.health))
		end

		if data.damage then
			makeentry("icon_damage.tex", tostring(checknumber(data.damage) and math.floor(data.damage) or data.damage))
			if data.planardamage then
				makesubentry("+"..math.floor(data.planardamage) .. STRINGS.SCRAPBOOK.DATA_PLANAR_DAMAGE)
			end
		end

		if data.sanityaura then
			local sanitystr = ""
			if data.sanityaura >= TUNING.SANITYAURA_HUGE then
				sanitystr = STRINGS.SCRAPBOOK.SANITYDESC.POSHIGH
			elseif data.sanityaura >= TUNING.SANITYAURA_MED then
				sanitystr = STRINGS.SCRAPBOOK.SANITYDESC.POSMED
			elseif data.sanityaura > 0 then
				sanitystr = STRINGS.SCRAPBOOK.SANITYDESC.POSSMALL
			elseif data.sanityaura == 0 then
				sanitystr = nil
			elseif data.sanityaura < 0 and data.sanityaura > -TUNING.SANITYAURA_MED then
				sanitystr = STRINGS.SCRAPBOOK.SANITYDESC.NEGSMALL
			elseif data.sanityaura > -TUNING.SANITYAURA_HUGE then
				sanitystr = STRINGS.SCRAPBOOK.SANITYDESC.NEGMED
			else
				sanitystr = STRINGS.SCRAPBOOK.SANITYDESC.NEGHIGH
			end
			if sanitystr then
				makeentry("icon_sanity.tex",sanitystr)
			end
		end
		
		local showfood = true
		if data.hungervalue and data.hungervalue == 0 and
			data.healthvalue and data.healthvalue == 0 and
			data.sanityvalue and data.sanityvalue == 0 then
			showfood = false
		end
--[[
		if data.foodtype == FOODTYPE.ELEMENTAL or data.foodtype == FOODTYPE.ROUGHAGE or data.foodtype == FOODTYPE.HORRIBLE then
			showfood = false
		end
]]
		if showfood and data.foodtype then
			local str = STRINGS.SCRAPBOOK.FOODTYPE[data.foodtype]
			makeentry("icon_food.tex",str)
			if not table.contains(FOODGROUP.OMNI.types, data.foodtype) then
				makesubentry(STRINGS.SCRAPBOOK.DATA_NON_PLAYER_FOOD)
				statsheight = statsheight - (STAT_GAP_SMALL * 2)
			end
		end

		if showfood and
			data.hungervalue ~= nil and
			data.healthvalue ~= nil and
			data.sanityvalue ~= nil
		then
			local icons = {
				"icon_hunger",
				"icon_health",
				"icon_sanity",
			}

			local texts = {
				(data.hungervalue > 0 and "+" or "")..(data.hungervalue % 1 > 0 and string.format("%.1f", data.hungervalue) or math.floor(data.hungervalue)),
				(data.healthvalue > 0 and "+" or "")..(data.healthvalue % 1 > 0 and string.format("%.1f", data.healthvalue) or math.floor(data.healthvalue)),
				(data.sanityvalue > 0 and "+" or "")..(data.sanityvalue % 1 > 0 and string.format("%.1f", data.sanityvalue) or math.floor(data.sanityvalue)),
			}

			makelistentry(icons, texts, STAT_ICONSIZE - 10)
		end
		
		-- NOTES
		if data.notes then
			if data.notes.shadow_aligned then
				makeentry("icon_shadowaligned.tex",STRINGS.SCRAPBOOK.NOTE_SHADOW_ALIGNED)
			end
			if data.notes.lunar_aligned then
				makeentry("icon_moonaligned.tex",STRINGS.SCRAPBOOK.NOTE_LUNAR_ALIGNED)
			end
		end

		-- AP Tags
		local loc = ArchipelagoDST.ID_TO_LOCATION[data.id]
		if data.type == "boss" and loc and loc.tags["boss"] then
			if loc and loc.tags["raidboss"] then
				makeentry("icon_damage.tex", STRINGS.DSTAP_TRACKER.DATA_RAIDBOSS)
			elseif loc and loc.tags["boss"] then
				makeentry("icon_damage.tex", STRINGS.DSTAP_TRACKER.DATA_BOSS)
			end
		end
		
		if loc and loc.tags["peaceful"] then
			makeentry("icon_health.tex", STRINGS.DSTAP_TRACKER.DATA_PEACEFUL)
		end
	end

	---------------------------------------------

	statsheight = statsheight - (STAT_PANEL_INDENT - STAT_GAP_SMALL)

	applytexturesize(statbg,STAT_PANEL_WIDTH,math.abs(statsheight))

	local attachments = statwidget:AddChild(Widget("attachments"))
	attachments:SetPosition(STAT_PANEL_WIDTH/2,-math.abs(statsheight)/2)
	statbg:SetPosition(STAT_PANEL_WIDTH/2,-math.abs(statsheight)/2)
	setattachmentdetils(attachments, STAT_PANEL_WIDTH,math.abs(statsheight))

	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--------------------------------------------------------------------------------------------------------------------------------------------------------------

	local photostack = sub_root:AddChild(Widget("photostack"))
	local photo = photostack:AddChild(Image("images/fepanel_fills.xml", "panel_fill_large.tex"))

	photo:SetClickable(false)
	local BUFFER = 35
	local ACTUAL_X = CUSTOM_SIZE.x
	local ACTUAL_Y = CUSTOM_SIZE.y
	local offsety = 0
	local offsetx = 0
	local animal = nil

	if data then
    	animal = photostack:AddChild(UIAnim())
		local animstate = animal:GetAnimState()

		animstate:SetBuild(data.build)
		animstate:SetBank(data.bank)
		animstate:SetPercent(data.anim or "", data.animpercent or rand())

		if data.facing then
			animal:SetFacing(data.facing)
			animstate:MakeFacingDirty()
		end

		if data.alpha or data.multcolour then
			local r, g, b = unpack(data.multcolour or {1, 1, 1})
			animstate:SetMultColour(r, g, b, data.alpha or 1)
		end

		if data.overridebuild then
			animstate:AddOverrideBuild(data.overridebuild)
		end

		animstate:Hide("snow")

		if data.hide then
			for i,hide in ipairs(data.hide) do
				animstate:Hide(hide)
			end
		end

		if data.hidesymbol then
			for i,hide in ipairs(data.hidesymbol) do
				animstate:HideSymbol(hide)
			end
		end

		if data.overridesymbol then
			if type(data.overridesymbol[1]) ~= "table" then
				animstate:OverrideSymbol(data.overridesymbol[1], data.overridesymbol[2], data.overridesymbol[3])

				if data.overridesymbol[4] then
					animstate:SetSymbolMultColour(data.overridesymbol[1], 1, 1, 1, tonumber(data.overridesymbol[4]))
				end
			else
				for i, set in ipairs( data.overridesymbol ) do
					animstate:OverrideSymbol(set[1], set[2], set[3])

					if set[4] then
						animstate:SetSymbolMultColour(set[1], 1, 1, 1, tonumber(set[4]))
					end
				end
			end
		end

		local x1, y1, x2, y2 = animstate:GetVisualBB()

		local ax,ay = animal:GetBoundingBoxSize()

		local SCALE = CUSTOM_SIZE.x/ax

		if ay*SCALE >= ACTUAL_Y then
			SCALE = ACTUAL_Y/ay
			ACTUAL_X = ax*SCALE
		else
			ACTUAL_Y = ay*SCALE
		end

		SCALE = SCALE*(data.scale or 1)

		animal:SetScale(math.min(0.5,SCALE))
 		offsety = ACTUAL_Y/2 -(y2*SCALE)
 		offsetx = ACTUAL_X/2 -(x2*SCALE)

		if data.floater ~= nil then
			local size, vert_offset, xscale, yscale = unpack(data.floater)

			local floater = animal:AddChild(UIAnim())
			local floater_animstate = floater:GetAnimState()

			floater_animstate:SetBuild("float_fx")
			floater_animstate:SetBank("float_front")
			floater_animstate:SetPercent("idle_front_" .. size, rand())
			floater_animstate:SetFloatParams(-0.05, 1.0, 0)

			floater:SetPosition(0, tonumber(vert_offset), 0)
			floater:SetScale(tonumber(xscale) - .05, tonumber(yscale) - .05)
			floater:SetClickable(false)
		end

	else
		animal = photostack:AddChild(Image("images/scrapbook.xml", "icon_empty.tex"))
		ACTUAL_X = CUSTOM_SIZE.x
		ACTUAL_Y = CUSTOM_SIZE.x/379*375
		animal:ScaleToSize(ACTUAL_X,ACTUAL_Y)
		offsetx = 0
		offsety = 0
	end

    local extraoffsetbgx = data and data.animoffsetbgx or 0
    local extraoffsetbgy = data and data.animoffsetbgy or 0

	-- if extraoffsetbgx > 0 then
	-- 	offsetx = offsetx + extraoffsetbgx/2
	-- end

    local BG_X = (ACTUAL_X + BUFFER+ extraoffsetbgx)
    local BG_Y = (ACTUAL_Y + BUFFER+ extraoffsetbgy)

	applytexturesize(photo,BG_X, BG_Y)
	setattachmentdetils(photostack, BG_X, BG_Y)

    animal:SetClickable(false)

    CUSTOM_ANIMOFFSET = Vector3(offsetx,-offsety,0)
    local extraoffsetx = data and data.animoffsetx or 0
    local extraoffsety = data and data.animoffsety or 0

    local posx =(CUSTOM_ANIMOFFSET.x+extraoffsetx) *(data and data.scale and data.scale * .5 or 1)
    local posy =(CUSTOM_ANIMOFFSET.y+extraoffsety) *(data and data.scale and data.scale or 1)

    animal:SetPosition(posx,posy)

    if data and data.logiclevel <= LOGIC_LEVELS.HARD_IN_LOGIC then
    	animal:GetAnimState():SetSaturation(0)
    	photo:SetTint(unpack(UK_TINT))
    end

	self.animal = animal

    photostack:SetRotation(rotation)

	local ROT_X = ACTUAL_X + extraoffsetbgx
	local ROT_Y = ACTUAL_Y + extraoffsetbgy

    local rotheight = calculteRotatedHeight(rotation, ROT_X, ROT_Y)
	local rotwidth = calculteRotatedWidth(rotation, ROT_X, ROT_Y)

	if statwidget then
	    local pos_s = statwidget:GetPosition()

	   statwidget:SetPosition(rotwidth+ CUSTOM_INDENT +30 ,height)
	end
	if not showstats --[[or (data and data.logiclevel < 2) ]]then
		statwidget:Hide()
	end

	if data then
		height = height - 20
    	photostack:SetPosition(left + (rotwidth/2) + CUSTOM_INDENT, height - (0.5 * rotheight))
	else
		photostack:Hide() -- Overview page
	end

	local finalheight = ( (rotheight+20 > math.abs(statsheight)) or not showstats ) and rotheight+20 or math.abs(statsheight)

	if data then
    	height = height - finalheight - section_space
	end

------------------------- RESEARCHABLE INFO -------------------------

if data then
	local loc = ArchipelagoDST.ID_TO_LOCATION[data.id]
	if loc and loc.tags then
		local tags = loc.tags
		local researchinfo
		if tags["research"] then
			if tags["hermitcrab"] then
				researchinfo = "This can be traded with "..STRINGS.NAMES.HERMITCRAB.." at friendship level "..(
					(tags["tier_1"] and 1)
					or (tags["tier_2"] and 3)
					or (tags["tier_3"] and 6)
					or 8
				).."."
			else
				if tags["science"] then
					researchinfo = tags["tier_2"] and STRINGS.NAMES.RESEARCHLAB2 or STRINGS.NAMES.RESEARCHLAB
				elseif tags["magic"] then
					researchinfo = tags["tier_2"] and STRINGS.NAMES.RESEARCHLAB3 or STRINGS.NAMES.RESEARCHLAB4
				elseif tags["celestial"] then
					researchinfo = tags["tier_2"] and STRINGS.NAMES.MOON_ALTAR or STRINGS.NAMES.MOONROCKSEED
				elseif tags["seafaring"] then
					researchinfo = STRINGS.NAMES.SEAFARING_PROTOTYPER
				elseif tags["ancient"] then
					researchinfo = tags["tier_2"] and STRINGS.NAMES.ANCIENT_ALTAR or STRINGS.NAMES.ANCIENT_ALTAR_BROKEN
				end
				researchinfo = "This can be researched at "..researchinfo.."."
			end
			if researchinfo then
				local inspectbody
				height, inspectbody = setcustomblock(height,{str=researchinfo, minwidth=width-100, leftoffset=40, shortblock=true})
			end
		end
	end
end

------------------------ SPECIAL INFO -------------------------------
	local specialinfo = data and (data.specialinfo and STRINGS.SCRAPBOOK.SPECIALINFO[data.specialinfo] or STRINGS.SCRAPBOOK.SPECIALINFO[string.upper(data.prefab)])
	
	if data and data.hint then
		specialinfo = (specialinfo and specialinfo.."\n\n" or "")..(data.hint.receivingname or "Someone").."'s "..(data.hint.itemname or "Item").." is locked behind this!"
	end

	local reqs = data and self.logic:GetRequirements(data.id, "default")
	if reqs then
		local helpful_reqs = self.logic:GetRequirements(data.id, "helpful")
		local hard_reqs = self.logic:GetRequirements(data.id, "hard")

		-- List events required
		if reqs.events then
			local list = setToList(reqs.events)
			if #list > 0 then
				specialinfo = (specialinfo and specialinfo.."\n\n" or "").."Requires "..table.concat(list, ", ")
			end
		end
		--
		if reqs.items then
			local have_items_list = {}
			local missing_items_list = {}
			-- Put all relevant playing characters in the have list
			if reqs.characters then
				local have_items = {}
				for k, _ in pairs(reqs.characters) do
					for _, player in pairs(AllPlayers) do
						local character_prettyname = player and player.prefab and ArchipelagoDST.RAW.CHARACTER_PREFAB_TO_PRETTYNAME[player.prefab]
						if character_prettyname and reqs.characters[character_prettyname] then
							have_items[character_prettyname] = true
							break
						end
					end
				end
				have_items_list = setToList(have_items)
			end
			-- List relevant items you have or are missing
			for k, _ in pairs(reqs.items) do
				local item_id = PRETTYNAME_TO_ITEM_ID[k]
				if item_id and ArchipelagoDST.lockableitems[item_id] then
					if ArchipelagoDST.collecteditems[item_id] then
						table.insert(have_items_list, k)
					else
						table.insert(missing_items_list, k)
					end
				end
			end 
			if #have_items_list > 0 then
				specialinfo = (specialinfo and specialinfo.."\n\n" or "").."Have: "..table.concat(have_items_list, ", ")
			end
			if #missing_items_list > 0 then
				specialinfo = (specialinfo and specialinfo.."\n\n" or "").."Missing: "..table.concat(missing_items_list, ", ")
			end
		end
		-- List helpful events, items, and characters
		if helpful_reqs then
			local set = {}
			for _, tablename in ipairs({"items", "events", "has_characters"}) do
				if helpful_reqs[tablename] then
					for k, _ in pairs(helpful_reqs[tablename]) do
						if not reqs[tablename] or not reqs[tablename][k] then
							set[k] = true
						end
					end
				end
			end
			local list = setToList(set)
			if #list > 0 then
				specialinfo = (specialinfo and specialinfo.."\n\n" or "").."Helpful: "..table.concat(list, ", ")
			end
		end
		-- List hard events, items, and characters if in hard logic
		if data.logiclevel == LOGIC_LEVELS.HARD_IN_LOGIC and hard_reqs then
			local set = {}
			for _, tablename in ipairs({"items", "has_events", "has_characters"}) do
				if hard_reqs[tablename] then
					for k, _ in pairs(hard_reqs[tablename]) do
						if not reqs[tablename] or not reqs[tablename][k] then
							if tablename == "items" then
								local item_id = PRETTYNAME_TO_ITEM_ID[k]
								if item_id and ArchipelagoDST.lockableitems[item_id] and ArchipelagoDST.collecteditems[item_id] then
									set[k] = true
								end
							else
								set[k] = true
							end
						end
					end
				end
			end
			local list = setToList(set)
			if #list > 0 then
				specialinfo = (specialinfo and specialinfo.."\n\n" or "").."Hard: "..table.concat(list, ", ")
			end
		end
		-- List comments
		if reqs.comments then
			local list = setToList(reqs.comments)
			if #list > 0 then
				specialinfo = (specialinfo and specialinfo.."\n\n" or "")..table.concat(list, " ")
			end
		end
	end

	if specialinfo then
		local body
		local shortblock = string.len(specialinfo) < 110
		height, body = setcustomblock(height,{str=specialinfo, minwidth=width-100, leftoffset=40, shortblock=shortblock})
	end

	if not data and ArchipelagoDST.goalinfo then
		local goaltext
		if goalinfo.goal == "survival" then
			goaltext = "Your goal is to survive for a total of "..(goalinfo.daystosurvive or "ERROR").." days."
		elseif goalinfo.goal == "bosses_any" then
			local goallist = goalinfo.goallist or {}
			if #goallist == 1 then
				local loc = ArchipelagoDST.ID_TO_LOCATION[goallist[1]]
				goaltext = "Your goal is to defeat "..(loc and loc.prettyname or "ERROR").."."
			else
				goaltext = "Your goal is to defeat any of these bosses."
			end
		elseif goalinfo.goal == "bosses_all" then
			local bosscount = 0
			local goallist = goalinfo.goallist or {}
			for _, id in ipairs(goallist) do
				if not ArchipelagoDST.missinglocations[id] then
					bosscount = bosscount + 1
				end
			end
			goaltext = "Your goal is to defeat all of these bosses. You've defeated "..bosscount.." so far!"
		end
		if goaltext then
			local body
			local shortblock = string.len(goaltext) < 110
			height, body = setcustomblock(height,{str=goaltext, minwidth=width-100, leftoffset=40, shortblock=shortblock})
		end
	end

	----------------------------------------------------------------------------------------------------------
	----------------------------------------------------------------------------------------------------------
	----------------------------------------------------------------------------------------------------------
	-- EXAMPLE RECIPES
	if data then
		local cookrecipe = self.logic:GetExampleCookRecipe(data.id)
		if cookrecipe then
			local loc = ArchipelagoDST.ID_TO_LOCATION[data.id]
			local iswarlyrecipe = loc and loc.tags and loc.tags["warly"] or false

			local STAT_PANEL_WIDTH = width -40
			local STAT_PANEL_INDENT = 20
			local STAT_GAP_SMALL = 5
			local STAT_ICONSIZE = 40

			local recipewidget,recipeheight

			local recipewidget = sub_root:AddChild(Widget("statswidget"))
			local recipebg = recipewidget:AddChild(Image("images/fepanel_fills.xml", "panel_fill_large.tex"))
			local recipeheight = 0

			recipeheight = recipeheight - STAT_PANEL_INDENT

			local atlas = resolvefilepath(CRAFTING_ICONS_ATLAS)
			local tex = "filter_cooking.tex"

			local makerecipeentry = function(tex,text)
				local icon = recipewidget:AddChild(Image(atlas, tex))
				icon:ScaleToSize(STAT_ICONSIZE,STAT_ICONSIZE)
				icon:SetPosition(STAT_PANEL_INDENT+(STAT_ICONSIZE/2), recipeheight-STAT_ICONSIZE/2)
				local txt = recipewidget:AddChild(Text(CHATFONT, 15, text, UICOLOURS.BLACK))
				txt:SetMultilineTruncatedString(text, 100, STAT_PANEL_WIDTH-(STAT_PANEL_INDENT*2) - STAT_ICONSIZE - STAT_GAP_SMALL)
				local tw, th = txt:GetRegionSize()
				txt:SetPosition(STAT_PANEL_INDENT+STAT_ICONSIZE + STAT_GAP_SMALL + (tw/2), recipeheight-STAT_ICONSIZE/2 )
				txt:SetHAlign(ANCHOR_LEFT)
				recipeheight = recipeheight - STAT_ICONSIZE - STAT_GAP_SMALL
			end

			local maketextentry = function(text)
				local txt = recipewidget:AddChild(Text(HEADERFONT, 15, text, UICOLOURS.BLACK))
				local tw, th = txt:GetRegionSize()
				txt:SetPosition(STAT_PANEL_WIDTH/2, recipeheight- (th/2) - STAT_GAP_SMALL)
				recipeheight = recipeheight - STAT_GAP_SMALL - th
			end

			---------------------------------------------

			maketextentry(STRINGS.DSTAP_TRACKER.DATA_EXAMPLE_COOK_RECIPE)

			makerecipeentry(tex,"Can be cooked using a "..(iswarlyrecipe and STRINGS.NAMES.PORTABLECOOKPOT_ITEM or STRINGS.NAMES.COOKPOT or "")..".")


			recipeheight = recipeheight - (STAT_PANEL_INDENT - STAT_GAP_SMALL)

			----------------------- Recipe ingredients ---------------------
			if cookrecipe then

				local idx = 1
				local gaps = 7 --10
				local imagesize = 32
				local imagebuffer = 32 -- 5

				-- local dep_imgsize = imagesize - imagebuffer
				local needs_img_types = { "item", "food" }

				for i, dep in ipairs(cookrecipe) do
					local depdata = dataset[dep]

					if depdata ~= nil then
						local tex = depdata.tex
						local atlas = GetScrapbookIconAtlas(tex)
						local icon = sub_root:AddChild(Image(atlas or GetScrapbookIconAtlas("cactus.tex"), atlas ~= nil and tex or "cactus.tex" ))

						local frame = sub_root:AddChild(Image("images/skilltree.xml","frame.tex" ))
						frame:ScaleToSize(imagesize+13,imagesize+13)
						frame:SetPosition(75+((imagesize+gaps)*(i-1)),height + recipeheight -imagesize/2 )
						frame:Hide()

						icon:SetPosition(75+((imagesize+gaps)*(i-1)),height + recipeheight -imagesize/2 )
						icon:ScaleToSize(imagesize+2,imagesize+2)

						local iconimg
						if table.contains(needs_img_types, depdata.type) then
							icon:SetTexture("images/scrapbook.xml", "inv_item_background.tex")

							atlas = GetInventoryItemAtlas(tex)

							local img = icon:AddChild(Image(atlas, tex))
							local _x, _y = icon:GetSize()
							img:ScaleToSize(_x - imagebuffer, _y - imagebuffer)
							-- img:ScaleToSize(dep_imgsize, dep_imgsize)

							iconimg = img
						end
					end
				end

				recipeheight = recipeheight - (imagesize+gaps) -section_space
			end


			---------------------------------------------


			applytexturesize(recipebg,STAT_PANEL_WIDTH,math.abs(recipeheight))

			local attachments = recipewidget:AddChild(Widget("attachments"))
			attachments:SetPosition(STAT_PANEL_WIDTH/2,-math.abs(recipeheight)/2)
			recipebg:SetPosition(STAT_PANEL_WIDTH/2,-math.abs(recipeheight)/2)
			setattachmentdetils(attachments, STAT_PANEL_WIDTH,math.abs(recipeheight))

			recipewidget:SetPosition( STAT_PANEL_INDENT ,height)  --rotwidth+ CUSTOM_INDENT +30

			local rotation = (rand() * 5)-2.5
			recipewidget:SetRotation(rotation)

		    local rotheight = calculteRotatedHeight(rotation,STAT_PANEL_WIDTH, math.abs(recipeheight))

		 	height = height - math.abs(rotheight) - (section_space*2)
		end
	end
	----------------------------------------------------------------------------------------------------------
	----------------------------------------------------------------------------------------------------------
	----------------------------------------------------------------------------------------------------------


	height = height - 200

	height = math.abs(height)

	local max_visible_height = PANEL_HEIGHT -60  -- -20
	local padding = 5

	local top = math.min(height, max_visible_height)/2 - padding

	local scissor_data = {x = 0, y = -max_visible_height/2, width = width, height = max_visible_height}
	local context = {widget = sub_root, offset = {x = 0, y = top}, size = {w = width, height = height + padding} }
	local scrollbar = { scroll_per_click = 20*3 }
	self.scroll_area = page:AddChild(TrueScrollArea(context, scissor_data, scrollbar))

	if height < (PANEL_HEIGHT-60) then
		self.scroll_area:SetPosition(0,(((PANEL_HEIGHT-60)/2) - (height/2)) )
	end

	page.focus_forward = self.scroll_area
	if self.depsbuttons then
		self.scroll_area.focus_forward = self.depsbuttons[1]
	end

	if self.debugentry ~= nil and data ~= nil then
		local msg = string.format("DEBUG - Entry:\n%s\n%s.fla", tostring(page.entry or "???"), tostring(data.build or "???"))

		self.debugentry.entry = page.entry
		self.debugentry.build = data.build
		self.debugentry:SetText(msg)

        local w, h = self.debugentry.text:GetRegionSize()
        self.debugentry:SetPosition(-w*2 - 5, h*2 + 5)
	end
	self.scroll_area.maximum_height = height
    return page
end


function TrackerScreen:OnControl(control, down)
    if TrackerScreen._base.OnControl(self, control, down) then return true end

    if not down and not self.closing then
	    if control == CONTROL_CANCEL then
			self.closing = true

			self:Close() --go back

			TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
			return true
		end

		 if control == CONTROL_MENU_L2 and TheInput:ControllerAttached() and self.details.entry then
		 	self.details:SetFocus()

			if TheInput:ControllerAttached() and self.depsbuttons[1] ~= nil then
				local x,y,z = self.depsbuttons[1]:GetPositionXYZ()
				local scrollpos = (math.abs(y)/math.abs(self.scroll_area.maximum_height)) * self.scroll_area.scroll_pos_end
				self.scroll_area.target_scroll_pos = scrollpos

				self.depsbuttons[1]:SetFocus()

			elseif TheInput:ControllerAttached() and self.character_pannel_first ~= nil then
				local x,y,z = self.character_pannel_first:GetPositionXYZ()
				local scrollpos = (math.abs(y)/math.abs(self.scroll_area.maximum_height)) * self.scroll_area.scroll_pos_end
				self.scroll_area.target_scroll_pos = scrollpos

				self.character_pannel_first:SetFocus()
			end
		 end
		 if control == CONTROL_MENU_R2 and TheInput:ControllerAttached() then
		 	if self.lastselecteditem then
		 		self.lastselecteditem:SetFocus()
		 	else
		 		self.item_grid:SetFocus()
		 	end
		 end

	    if control == CONTROL_MENU_START and TheInput:ControllerAttached() then
			if self.columns_setting == 1 then
				self.columns_setting = 2
			elseif self.columns_setting == 2 then
				self.columns_setting = 3
			elseif self.columns_setting == 3 then
				self.columns_setting = 7
			elseif self.columns_setting == 7 then
				self.columns_setting = 1
			end

			TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")

			self:SetGrid()

			Profile:SetScrapbookColumnsSetting(self.columns_setting)

			return true
		end

	    if control == CONTROL_MENU_MISC_2 then
			TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
			self:SelectMenuItem("down")
			return true
		end

	    if control == CONTROL_MENU_BACK then
			TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
			-- self:CycleChraterQuotes("right")
			return true
		end

		-- if self.flashestoclear then
  		-- 	if control == CONTROL_MENU_MISC_1 then
  		-- 		self.flashestoclear = nil
  		-- 		self:ClearFlashes()
		-- 		return true
		-- 	end
		-- end

	end
end

--CONTROL_MENU_L2  --CONTROL_MENU_R2
function TrackerScreen:GetHelpText()
	local t = {}
	local controller_id = TheInput:GetControllerID()

	table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_CANCEL) .. " " .. STRINGS.UI.HELP.BACK)

	table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_MISC_2) .. " " .. STRINGS.SCRAPBOOK.CYCLE_CAT)

	if self.character_panels and self.character_panels_total>1 and self.details.focus == true then
		table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_BACK).. " " .. STRINGS.SCRAPBOOK.CYCLE_QUOTES)
	end

	table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_START) .. " " .. STRINGS.SCRAPBOOK.CYCLE_VIEW)

	if self.searchbox.focus then
		table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.SCRAPBOOK.SEARCH)
	end

	-- if self.flashestoclear then
	-- 	table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_MISC_1) .. " " .. STRINGS.SCRAPBOOK.CLEARFLASH)
	-- end

	if self.details.entry and not self.details.focus then
		table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_L2) .. " " .. STRINGS.SCRAPBOOK.SELECT_INFO_PAGE)
	end
	if not self.item_grid.focus then
		table.insert(t, TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_R2) .. " " .. STRINGS.SCRAPBOOK.SELECT_ITEM_PAGE)
	end



	return table.concat(t, "  ")
end

function TrackerScreen:DoFocusHookups()

	self.item_grid:SetFocusChangeDir(MOVE_UP,							function(w) return self.searchbox end)


	self.searchbox:SetFocusChangeDir(MOVE_DOWN,							function(w) return self.item_grid end)

	--self.depsbuttons:SetFocusChangeDir(MOVE_DOWN,							function(w) return self.character_panels end)
	--self.character_panels:SetFocusChangeDir(MOVE_UP,							function(w) return self.depsbuttons end)

end

function TrackerScreen:OnDestroy()
	SetAutopaused(false)
	self._base.OnDestroy(self)
end

function TrackerScreen:OnBecomeActive()
    TrackerScreen._base.OnBecomeActive(self)

    ThePlayer:PushEvent("scrapbookopened")
end

function TrackerScreen:OnBecomeInactive()
    TrackerScreen._base.OnBecomeInactive(self)
end

function TrackerScreen:SelectEntry(entry)
	-- self:updatemenubuttonflashes()

	if self.details.entry ~= entry then
		self.detailsroot:KillAllChildren()
		self.details = nil
		self.details = self.detailsroot:AddChild(self:PopulateInfoPanel(entry))
		self:DoFocusHookups()
		TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/scrapbook_pageflip")
	end
end

return TrackerScreen
