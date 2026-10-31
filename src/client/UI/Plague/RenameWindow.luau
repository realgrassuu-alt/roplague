--!nonstrict
-- RoPlague: "Name your plague" (the 19 Robux Rename pass, Data/Gamepasses.rename). Without the pass
-- the window shows the price and a BUY button; with it, a text field, RANDOM and SAVE. The name goes
-- through server/PlagueRename (length, characters, Roblox's text filter) before it is kept.
-- Signals: renamed(name), closed (from the modal).

local UITheme = require("../UITheme")
local W = require("../Widgets")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")

local RenameWindow = {}
RenameWindow.__index = RenameWindow

RenameWindow.WIDTH = 340

local FIRST = {
	"Crimson", "Silent", "Black", "Pale", "Creeping", "Hollow", "Rotten", "Burning", "Grey", "Weeping",
	"Scarlet", "Toxic", "Iron", "Midnight", "Ashen", "Ghost", "Feral", "Bitter", "Wild", "Shadow",
}
local SECOND = {
	"Fever", "Rot", "Cough", "Blight", "Pox", "Plague", "Flu", "Shivers", "Sweats", "Spore",
	"Mire", "Wilt", "Hex", "Chill", "Curse", "Bloom", "Rash", "Fog", "Bane", "Itch",
}

--- A plague name like "Crimson Fever" (no player text, so it never needs the filter).
function RenameWindow.random_name(rng: Random?): string
	local r = rng or Random.new()
	return FIRST[r:NextInteger(1, #FIRST)] .. " " .. SECOND[r:NextInteger(1, #SECOND)]
end

local function remote(): any
	if not UICtx.IS_ROBLOX then
		return nil
	end
	return game:GetService("ReplicatedStorage"):FindFirstChild("RoPlagueRename")
end

function RenameWindow.new(c: any)
	local self = setmetatable({}, RenameWindow)
	self.ctx = c
	self.renamed = Signal.new()
	self.owned = false
	self.pass_id = 0
	self.price = 19
	local m = PUI.Modal.new(c, "NAME YOUR PLAGUE", { sep = 12 })
	self.modal = m
	self.closed = m.closed
	self._sub = UITheme.label("Give your plague its own name. The whole world will fear it.", 12, 500, UITheme.TEXT_2)
	self._sub:set_autowrap(true)
	self._sub:set_min_size(Vector2.new(RenameWindow.WIDTH, 0))
	m.body:add_child(self._sub)
	-- the text field (a plain Roblox TextBox in a kit node)
	local host = W.Control.new()
	host:set_min_size(Vector2.new(RenameWindow.WIDTH, 46))
	m.body:add_child(host)
	self._host = host
	if UICtx.IS_ROBLOX and host.gui ~= nil then
		local box = Instance.new("TextBox")
		box.Name = "PlagueName"
		box.ClearTextOnFocus = false
		box.Text = ""
		box.PlaceholderText = "Your plague's name"
		box.PlaceholderColor3 = UITheme.TEXT_3
		box.TextColor3 = UITheme.TEXT
		box.FontFace = UITheme.font(800)
		box.TextSize = 20
		box.BackgroundColor3 = Color3.fromRGB(14, 18, 34)
		box.BackgroundTransparency = 0.1
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = 60
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = box
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = PUI.INFECTED
		stroke.Thickness = 1.5
		stroke.Transparency = 0.4
		stroke.Parent = box
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = box
		box.Parent = host.gui
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > 22 then
				box.Text = box.Text:sub(1, 22)
			end
		end)
		box.FocusLost:Connect(function(enter: boolean)
			if enter and self.owned then
				self:_save()
			end
		end)
		self._box = box
	end
	self._msg = UITheme.label("", 11, 700, UITheme.TEXT_3)
	self._msg:set_autowrap(true)
	self._msg:set_min_size(Vector2.new(RenameWindow.WIDTH, 0))
	m.body:add_child(self._msg)
	local btns = UITheme.hbox(8)
	self._random = UITheme.button("RANDOM", "GlassButton", "", 44.0)
	self._random.pressed:Connect(function()
		if self._box then
			self._box.Text = RenameWindow.random_name()
		end
		c:sfx("click")
	end)
	btns:add_child(self._random)
	self._save_btn = UITheme.button("SAVE", "PrimaryButton", "", 44.0)
	self._save_btn.size_flags_horizontal = W.EXPAND_FILL
	self._save_btn.pressed:Connect(function()
		if self.owned then
			self:_save()
		else
			self:_buy()
		end
	end)
	btns:add_child(self._save_btn)
	m.body:add_child(btns)
	if UICtx.IS_ROBLOX then
		game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(_p, id, bought)
			if bought and id == self.pass_id then
				self.owned = true
				self:_paint()
				c:sfx("unlock")
			end
		end)
	end
	self:_paint()
	return self
end

function RenameWindow._paint(self)
	local box = self._box
	if box then
		box.TextEditable = self.owned
		box.TextTransparency = if self.owned then 0 else 0.45
	end
	self._random:set_visible(self.owned)
	if self.owned then
		self._save_btn:set_text("SAVE")
		self._save_btn:set_disabled(false)
		self:_say("3 to 22 letters, numbers or spaces.", UITheme.TEXT_3)
	elseif (self.pass_id or 0) > 0 then
		self._save_btn:set_text(("UNLOCK  %d R$"):format(self.price))
		self._save_btn:set_disabled(false)
		self:_say("Renaming is unlocked by the Rename pass, for good.", UITheme.TEXT_3)
	else
		self._save_btn:set_text("COMING SOON")
		self._save_btn:set_disabled(true)
		self:_say("The Rename pass isn't on sale yet.", UITheme.TEXT_3)
	end
end

function RenameWindow._say(self, text: string, col: Color3)
	self._msg:set_text(text)
	PUI.color(self._msg, col)
end

--- Opens the window (asks the server whether the pass is owned first).
function RenameWindow.request(self)
	local ctx = self.ctx
	if self._box then
		self._box.Text = tostring(ctx:setting("plague_name", "") or "")
	end
	self:_paint()
	self.modal:open()
	local rf = remote()
	if rf == nil then
		return
	end
	task.spawn(function()
		local ok, owned, id, price = pcall(function()
			return rf:InvokeServer("owns")
		end)
		if ok then
			self.owned = owned == true
			self.pass_id = tonumber(id) or 0
			self.price = tonumber(price) or 19
			if self.modal.is_open then
				self:_paint()
				self.modal:center()
			end
		end
	end)
end

function RenameWindow._buy(self)
	if (self.pass_id or 0) <= 0 or not UICtx.IS_ROBLOX then
		return
	end
	game:GetService("MarketplaceService"):PromptGamePassPurchase(game:GetService("Players").LocalPlayer, self.pass_id)
end

function RenameWindow._save(self)
	local rf = remote()
	local box = self._box
	if rf == nil or box == nil or self._saving then
		return
	end
	local name = box.Text
	self._saving = true
	self._save_btn:set_disabled(true)
	self:_say("Checking the name...", UITheme.TEXT_3)
	task.spawn(function()
		local ok, good, out = pcall(function()
			return rf:InvokeServer("set", name)
		end)
		self._saving = false
		self._save_btn:set_disabled(false)
		if ok and good == true and type(out) == "string" then
			self.renamed:Fire(out)
			self.ctx:sfx("confirm")
			self.modal:close(true)
		else
			self:_say(if ok and type(out) == "string" then out else "Couldn't save the name. Try again", UITheme.RED)
			self.ctx:sfx("error", -4.0)
		end
	end)
end

function RenameWindow.apply_layout(self)
	self.modal:apply_layout()
end

return RenameWindow
