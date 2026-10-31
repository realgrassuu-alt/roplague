--!nonstrict
-- RoPlague: the window before a match. Pick a pathogen (Data/Traits.PATHOGENS), a difficulty, and a name
-- (generated: players never type text that others could see). Signals: start(pathogen_id, difficulty, name).

local UITheme = require("../UITheme")
local W = require("../Widgets")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")
local Traits = UICtx.data("Traits")

local PathogenPicker = {}
PathogenPicker.__index = PathogenPicker

PathogenPicker.ADJ = {
	"Crimson", "Silent", "Grey", "Pale", "Scarlet", "Hollow", "Creeping", "Midnight", "Rust", "Ashen",
	"Bitter", "Weeping", "Iron", "Violet", "Feral", "Sleeping", "Burning", "Frozen", "Black", "Golden",
}
PathogenPicker.NOUN = {
	"Fever", "Rot", "Blight", "Pox", "Shiver", "Bloom", "Wilt", "Spore", "Chill", "Gloom",
	"Hunger", "Rash", "Mire", "Ember", "Shade", "Drift", "Whisper", "Thorn", "Murk", "Sorrow",
}

function PathogenPicker.random_name(): string
	local a = PathogenPicker.ADJ[math.random(1, #PathogenPicker.ADJ)]
	local n = PathogenPicker.NOUN[math.random(1, #PathogenPicker.NOUN)]
	return a .. " " .. n
end

function PathogenPicker.new(c: any)
	local self = setmetatable({}, PathogenPicker)
	self.ctx = c
	self.start = Signal.new()
	local m = PUI.Modal.new(c, "CHOOSE YOUR PATHOGEN", { sep = 14 })
	self.modal = m
	self.closed = m.closed
	self.pathogen = c:setting("plague_pathogen", "bacterium")
	if Traits.pathogen_by_id[self.pathogen] == nil then
		self.pathogen = "bacterium"
	end
	self.difficulty = math.clamp(tonumber(c:setting("plague_difficulty", 1)) or 1, 0, 2)
	self.name = PathogenPicker.random_name()
	-- cards
	local cards = UITheme.hbox(10)
	self._cards = {}
	for _, p in Traits.PATHOGENS do
		local card = W.Button.new("", "ChipButton")
		card.toggle_mode = true
		card:set_min_size(Vector2.new(170, 132))
		local v = UITheme.vbox(6)
		v:set_mouse_filter(W.MOUSE_IGNORE)
		v:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
		v.offset_left, v.offset_top, v.offset_right, v.offset_bottom = 12, 12, -12, -12
		local name = UITheme.label(string.upper(p.name), 16, 800, UITheme.color3(p.color))
		name:set_mouse_filter(W.MOUSE_IGNORE)
		v:add_child(name)
		local desc = UITheme.label(p.desc, 11, 500, UITheme.TEXT_2)
		desc:set_autowrap(true)
		desc:set_min_size(Vector2.new(146, 0))
		desc:set_mouse_filter(W.MOUSE_IGNORE)
		v:add_child(desc)
		card:add_child(v)
		card.pressed:Connect(function()
			self:_pick(p.id)
		end)
		self._cards[p.id] = card
		cards:add_child(card)
	end
	m.body:add_child(cards)
	-- difficulty
	local drow = UITheme.hbox(8)
	local dl = UITheme.label("DIFFICULTY", 11, 800, UITheme.TEXT_3, 1.6)
	dl.size_flags_vertical = W.SHRINK_CENTER
	dl:set_min_size(Vector2.new(96, 0))
	drow:add_child(dl)
	self._diffs = {}
	for i, name in PUI.DIFFICULTIES do
		local chip = PUI.chip(string.upper(name), 34.0)
		chip:set_min_size(Vector2.new(96, 34))
		chip.pressed:Connect(function()
			self.difficulty = i - 1
			self:_sync()
		end)
		self._diffs[i - 1] = chip
		drow:add_child(chip)
	end
	m.body:add_child(drow)
	-- name
	local nrow = UITheme.hbox(8)
	local nl = UITheme.label("NAME", 11, 800, UITheme.TEXT_3, 1.6)
	nl.size_flags_vertical = W.SHRINK_CENTER
	nl:set_min_size(Vector2.new(96, 0))
	nrow:add_child(nl)
	self._name = UITheme.label(self.name, 17, 800, UITheme.TEXT)
	self._name.size_flags_vertical = W.SHRINK_CENTER
	self._name.size_flags_horizontal = W.EXPAND_FILL
	nrow:add_child(self._name)
	local reroll = UITheme.button("NEW NAME", "GlassButton", "", 36.0)
	reroll:set_font_size(12)
	reroll.pressed:Connect(function()
		self.name = PathogenPicker.random_name()
		self._name:set_text(self.name)
	end)
	nrow:add_child(reroll)
	m.body:add_child(nrow)
	self._hint = UITheme.label("", 12, 500, UITheme.TEXT_2)
	self._hint:set_autowrap(true)
	self._hint:set_min_size(Vector2.new(700, 0))
	m.body:add_child(self._hint)
	local go = UITheme.button("START", "PrimaryButton", "", 52.0)
	go:set_font_size(18)
	go.pressed:Connect(function()
		self.ctx:set_setting("plague_pathogen", self.pathogen)
		self.ctx:set_setting("plague_difficulty", self.difficulty)
		self.modal:close(true)
		self.start:Fire(self.pathogen, self.difficulty, self.name)
	end)
	m.body:add_child(go)
	self:_sync()
	return self
end

local HINTS = {
	[0] = "Casual: governments are slow and the cure takes its time. A good first game.",
	[1] = "Normal: the world reacts like it should. Spread everywhere before you turn deadly.",
	[2] = "Brutal: quick governments and a fast cure. Every choice counts.",
}

function PathogenPicker._pick(self, id: string)
	self.pathogen = id
	self:_sync()
end

function PathogenPicker._sync(self)
	for id, card in self._cards do
		card:set_pressed_no_signal(id == self.pathogen)
	end
	for d, chip in self._diffs do
		chip:set_pressed_no_signal(d == self.difficulty)
	end
	self._hint:set_text(HINTS[self.difficulty] or "")
end

function PathogenPicker.open(self)
	self.name = PathogenPicker.random_name()
	self._name:set_text(self.name)
	self:_sync()
	self.modal:open()
end

function PathogenPicker.close(self)
	self.modal:close()
end

function PathogenPicker.apply_layout(self)
	local compact = self.ctx.compact == true
	for _, card in self._cards do
		card:set_min_size(if compact then Vector2.new(130, 118) else Vector2.new(170, 132))
	end
	self._hint:set_min_size(Vector2.new(if compact then 520 else 700, 0))
	self.modal:apply_layout()
end

return PathogenPicker
