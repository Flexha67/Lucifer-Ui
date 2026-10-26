--[[
	Lucifer UI Library
	Version 1.2.0 - "Nocturne"
	Author: LostSky
	License: MIT

	A full-featured, single-file Roblox UI library.
	Obsidian glass theme, animated splash loader, tabs, sections,
	15+ components, notifications, keybind capture, color picker,
	config save/load, drag + resize.

	Usage:
		local Lucifer = loadstring(game:HttpGet("https://raw.githubusercontent.com/LostSky/Lucifer/main/Lucifer.lua"))()

		local Window = Lucifer:CreateWindow({
			Title = "Lucifer",
			Subtitle = "v1.2.0",
			Loader = true,          -- cinematic splash screen
			Blur = true,            -- UIBlurEffect behind the window
		})
]]

--=====================================================================
-- SERVICES
--=====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

--=====================================================================
-- UTILITY
--=====================================================================

local Library = {}
Library.Version = "1.2.0"
Library.Flags = {}
Library.Options = {}
Library.Configs = {}
Library.Connections = {}
Library._Listening = false
Library._Windows = {}

local function track(connection)
	table.insert(Library.Connections, connection)
	return connection
end

local function new(class, props)
	local inst = Instance.new(class)
	local parent = nil
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return new("UICorner", {
		CornerRadius = UDim.new(0, radius or 6),
		Parent = parent,
	})
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or Color3.fromRGB(50, 50, 64),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function padding(parent, top, right, bottom, left)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft = UDim.new(0, left or 0),
		Parent = parent,
	})
end

local function tween(obj, props, time, style, dir)
	local info = TweenInfo.new(
		time or 0.15,
		style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function safeFont(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	if ok and value then
		return value
	end
	return Enum.Font[fallback] or Enum.Font.Gotham
end

local Fonts = {
	Regular = safeFont("Gotham", "SourceSans"),
	Medium = safeFont("GothamMedium", "SourceSansSemibold"),
	Bold = safeFont("GothamBold", "SourceSansBold"),
}

local function getGuiParent()
	local ok, hui = pcall(function()
		if gethui then
			return gethui()
		end
		return nil
	end)
	if ok and hui then
		return hui
	end
	local ok2, cg = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok2 and cg then
		return cg
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function roundTo(value, step)
	if not step or step <= 0 then
		return value
	end
	return math.floor(value / step + 0.5) * step
end

local function lerpColor(a, b, alpha)
	return Color3.new(
		a.R + (b.R - a.R) * alpha,
		a.G + (b.G - a.G) * alpha,
		a.B + (b.B - a.B) * alpha
	)
end

-- ColorSequence is a userdata datatype, so `type()` cannot see it
local function isColorSequence(value)
	if value == nil then
		return false
	end
	if typeof then
		local ok, kind = pcall(typeof, value)
		if ok then
			return kind == "ColorSequence"
		end
	end
	local ok, keypoints = pcall(function()
		return value.Keypoints
	end)
	return ok and keypoints ~= nil
end

-- gradient(parent, seq, rotation, transparency)
-- gradient(parent, colorA, colorB, rotation, transparency)
local function gradient(parent, from, to, rotation, transparency)
	local sequence, rot, trans

	if isColorSequence(from) then
		sequence = from
		rot = to
		trans = rotation
	elseif type(from) == "table" and from.Keypoints then
		sequence = ColorSequence.new(from)
		rot = to
		trans = rotation
	else
		sequence = ColorSequence.new(from or Color3.new(1, 1, 1), to or from or Color3.new(1, 1, 1))
		rot = rotation
		trans = transparency
	end

	local ok, g = pcall(function()
		return new("UIGradient", {
			Color = sequence,
			Rotation = rot or 90,
			Parent = parent,
		})
	end)
	if not ok or not g then
		warn("[Lucifer] gradient failed: " .. tostring(g))
		return nil
	end
	if trans then
		g.Transparency = trans
	end
	return g
end

-- neon halo: a wide, faint border stroke sitting outside the shape
local function halo(parent, color, thickness, transparency)
	local h = new("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Thickness = thickness or 4,
		Transparency = transparency or 0.72,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
	return h
end

-- inner hairline: a 1px light stroke on an inset overlay for a glass edge
local function glassEdge(parent, radius, transparency)
	local edge = new("Frame", {
		Name = "GlassEdge",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -2, 1, -2),
		Position = UDim2.fromOffset(1, 1),
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	corner(edge, radius or 8)
	local s = stroke(edge, Color3.new(1, 1, 1), 1, transparency or 0.92)
	return edge, s
end

local function addScale(parent, value)
	return new("UIScale", { Scale = value or 1, Parent = parent })
end

-- manual letter spacing (Roblox text has no tracking property)
local function spaced(text, gap)
	local out = {}
	for i = 1, #text do
		out[i] = string.sub(text, i, i)
	end
	return table.concat(out, string.rep(" ", gap or 1))
end

local function upper(text)
	return string.upper(tostring(text))
end

local function blurGui(gui, size)
	local ok, effect = pcall(function()
		return new("UIBlurEffect", {
			Size = size or 18,
			Parent = gui,
		})
	end)
	return ok and effect or nil
end

local function tweenScale(scaleObj, target, time, style, dir)
	return tween(scaleObj, { Scale = target }, time or 0.35, style or Enum.EasingStyle.Quart, dir)
end

--=====================================================================
-- SIGNAL
--=====================================================================

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	local entry = { fn = fn, Connected = true }
	function entry:Disconnect()
		self.Connected = false
		for i = #handlers, 1, -1 do
			if handlers[i] == self then
				table.remove(handlers, i)
				break
			end
		end
	end
	table.insert(handlers, entry)
	return entry
end

function Signal:Fire(...)
	local snapshot = {}
	for i, entry in ipairs(self._handlers) do
		snapshot[i] = entry
	end
	for _, entry in ipairs(snapshot) do
		if entry.Connected then
			local ok, err = pcall(entry.fn, ...)
			if not ok then
				warn("[Lucifer] callback error: " .. tostring(err))
			end
		end
	end
end

--=====================================================================
-- THEME
--=====================================================================

Library.Theme = {
	-- surfaces (obsidian glass)
	Background = Color3.fromRGB(9, 8, 13),
	Surface = Color3.fromRGB(15, 14, 21),
	SurfaceLight = Color3.fromRGB(22, 20, 30),
	SurfaceHover = Color3.fromRGB(31, 28, 43),
	Elevated = Color3.fromRGB(27, 24, 38),
	Glass = Color3.fromRGB(38, 34, 52),
	Outline = Color3.fromRGB(40, 36, 56),
	OutlineLight = Color3.fromRGB(62, 55, 86),

	-- text
	Text = Color3.fromRGB(240, 238, 248),
	SubText = Color3.fromRGB(150, 144, 170),
	DimText = Color3.fromRGB(100, 94, 122),

	-- accent (Lucifer violet, dual-tone for gradients)
	Accent = Color3.fromRGB(178, 102, 255),
	AccentLight = Color3.fromRGB(214, 168, 255),
	AccentDark = Color3.fromRGB(112, 44, 196),
	AccentAlt = Color3.fromRGB(104, 126, 255),
	Gold = Color3.fromRGB(242, 208, 148),

	-- status
	Success = Color3.fromRGB(88, 226, 150),
	Warning = Color3.fromRGB(250, 206, 84),
	Danger = Color3.fromRGB(255, 118, 132),
	Info = Color3.fromRGB(112, 176, 255),
}

function Library:SetTheme(themeTable)
	for key, value in pairs(themeTable) do
		self.Theme[key] = value
	end
end

function Library:GetTheme()
	return self.Theme
end

--=====================================================================
-- CONFIG SERIALIZATION
--=====================================================================

local function serializeValue(value)
	local kind = typeof(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		return tostring(value)
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "Color3" then
		return string.format(
			"Color3.fromRGB(%d, %d, %d)",
			math.floor(value.R * 255 + 0.5),
			math.floor(value.G * 255 + 0.5),
			math.floor(value.B * 255 + 0.5)
		)
	elseif kind == "EnumItem" then
		local enumName = tostring(value.EnumType)
		enumName = string.gsub(enumName, "Enum%.", "")
		return string.format("Enum.%s.%s", enumName, value.Name)
	elseif kind == "table" then
		local parts = {}
		for k, v in pairs(value) do
			local keyRepr
			if type(k) == "string" then
				keyRepr = string.format("[%q]", k)
			else
				keyRepr = "[" .. tostring(k) .. "]"
			end
			table.insert(parts, keyRepr .. " = " .. serializeValue(v))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return "nil"
end

local function serializeTable(tbl)
	local parts = {}
	for key, value in pairs(tbl) do
		local keyRepr
		if type(key) == "string" then
			keyRepr = string.format("[%q]", key)
		else
			keyRepr = "[" .. tostring(key) .. "]"
		end
		table.insert(parts, keyRepr .. " = " .. serializeValue(value))
	end
	return "{\n\t" .. table.concat(parts, ",\n\t") .. "\n}"
end

local function hasFileIO()
	return type(writefile) == "function"
		and type(readfile) == "function"
		and type(isfile) == "function"
end

local CONFIG_FOLDER = "Lucifer"

local function ensureFolder()
	if not hasFileIO() then
		return false
	end
	local ok = pcall(function()
		if type(isfolder) == "function" and not isfolder(CONFIG_FOLDER) then
			makefolder(CONFIG_FOLDER)
		end
	end)
	return ok
end

function Library:SaveConfig(name)
	name = name or "default"
	local snapshot = {}
	for flag, value in pairs(self.Flags) do
		snapshot[flag] = value
	end

	local payload = "return " .. serializeTable(snapshot)

	if hasFileIO() then
		ensureFolder()
		local ok, err = pcall(function()
			writefile(CONFIG_FOLDER .. "/" .. name .. ".cfg", payload)
		end)
		if not ok then
			self:Notify({
				Title = "Config",
				Content = "Save failed: " .. tostring(err),
				Type = "Danger",
			})
			return false
		end
	else
		self.Configs[name] = snapshot
	end

	self:Notify({
		Title = "Config Saved",
		Content = name,
		Type = "Success",
		Duration = 2,
	})
	return true
end

function Library:LoadConfig(name)
	name = name or "default"
	local payload

	if hasFileIO() then
		local path = CONFIG_FOLDER .. "/" .. name .. ".cfg"
		local ok, data = pcall(function()
			if isfile(path) then
				return readfile(path)
			end
			return nil
		end)
		if not ok or not data then
			self:Notify({
				Title = "Config",
				Content = "Not found: " .. name,
				Type = "Danger",
			})
			return false
		end
		payload = data
	else
		local stored = self.Configs[name]
		if not stored then
			self:Notify({
				Title = "Config",
				Content = "Not found: " .. name,
				Type = "Danger",
			})
			return false
		end
		for flag, value in pairs(stored) do
			local option = self.Options[flag]
			if option and option.Set then
				option.Set(value)
			end
		end
		return true
	end

	local chunk = loadstring or load
	if type(chunk) ~= "function" then
		self:Notify({
			Title = "Config",
			Content = "loadstring unavailable in this environment",
			Type = "Danger",
		})
		return false
	end

	local loader = chunk(payload)
	if not loader then
		self:Notify({
			Title = "Config",
			Content = "Corrupt config: " .. name,
			Type = "Danger",
		})
		return false
	end

	local ok, data = pcall(loader)
	if not ok or type(data) ~= "table" then
		self:Notify({
			Title = "Config",
			Content = "Corrupt config: " .. name,
			Type = "Danger",
		})
		return false
	end

	for flag, value in pairs(data) do
		local option = self.Options[flag]
		if option and option.Set then
			local called = pcall(option.Set, value)
			if not called then
				warn("[Lucifer] failed to apply flag: " .. tostring(flag))
			end
		end
	end

	self:Notify({
		Title = "Config Loaded",
		Content = name,
		Type = "Success",
		Duration = 2,
	})
	return true
end

function Library:ListConfigs()
	local list = {}
	if hasFileIO() then
		local ok, files = pcall(function()
			return listfiles(CONFIG_FOLDER)
		end)
		if ok and files then
			for _, path in ipairs(files) do
				local match = string.match(path, "([^/\\]+)%.cfg$")
				if match then
					table.insert(list, match)
				end
			end
		end
	end
	for name in pairs(self.Configs) do
		table.insert(list, name)
	end
	return list
end

function Library:DeleteConfig(name)
	if hasFileIO() then
		pcall(function()
			local path = CONFIG_FOLDER .. "/" .. name .. ".cfg"
			if isfile(path) then
				delfile(path)
			end
		end)
	end
	self.Configs[name] = nil
end

--=====================================================================
-- TOOLTIP
--=====================================================================

local Tooltip

local function createTooltip(holder)
	local frame = new("Frame", {
		Name = "LuciferTooltip",
		BackgroundColor3 = Library.Theme.SurfaceLight,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 500,
		Parent = holder,
	})
	corner(frame, 5)
	stroke(frame, Library.Theme.Outline, 1)
	padding(frame, 5, 8, 5, 8)

	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Medium,
		Text = "",
		TextColor3 = Library.Theme.Text,
		TextSize = 12,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 501,
		Parent = frame,
	})

	return {
		Frame = frame,
		Label = label,
		Show = function(text)
			if not text or text == "" then
				return
			end
			label.Text = text
			frame.Visible = true
		end,
		Hide = function()
			frame.Visible = false
		end,
		Update = function()
			if not frame.Visible then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			frame.Position = UDim2.fromOffset(mouse.X + 14, mouse.Y + 18)
		end,
	}
end

--=====================================================================
-- NOTIFICATIONS
--=====================================================================

Library.NotificationHolder = nil
Library.NotificationGui = nil

local function ensureNotificationHolder()
	if Library.NotificationHolder and Library.NotificationHolder.Parent then
		return Library.NotificationHolder
	end

	local gui = new("ScreenGui", {
		Name = "LuciferNotificationsGui",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10000,
	})
	local ok = pcall(function()
		gui.Parent = getGuiParent()
	end)
	if not ok or not gui.Parent then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
	Library.NotificationGui = gui

	local container = new("Frame", {
		Name = "LuciferNotifications",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, -18, 0, 18),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 400,
		Parent = gui,
	})

	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = container,
	})

	Library.NotificationHolder = container
	return container
end

function Library:Notify(config)
	if type(config) == "string" then
		config = { Content = config }
	end

	local theme = self.Theme
	local holder = self.NotificationHolder
	if not holder or not holder.Parent then
		holder = ensureNotificationHolder()
	end

	local accent = theme.Accent
	if config.Type == "Success" then
		accent = theme.Success
	elseif config.Type == "Warning" then
		accent = theme.Warning
	elseif config.Type == "Danger" then
		accent = theme.Danger
	elseif config.Type == "Info" then
		accent = theme.Info
	end

	local toast = new("Frame", {
		Name = "Toast",
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 401,
		ClipsDescendants = true,
		Parent = holder,
	})
	corner(toast, 10)
	stroke(toast, theme.Outline, 1, 0.4)
	gradient(toast, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 22, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 15, 23)),
	}), 90)
	padding(toast, 11, 13, 11, 18)

	local toastStrip = new("Frame", {
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Position = UDim2.fromOffset(-18, 0),
		ZIndex = 402,
		Parent = toast,
	})
	gradient(toastStrip, ColorSequence.new(accent, accent), 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.35),
	}))

	new("UIListLayout", {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toast,
	})

	if config.Title then
		local headerRow = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 1,
			ZIndex = 402,
			Parent = toast,
		})

		local bar = new("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(5, 5),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 403,
			Parent = headerRow,
		})
		local barCorner = corner(bar, 0)
		barCorner.CornerRadius = UDim.new(0.5, 0)
		halo(bar, accent, 5, 0.55)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Bold,
			Text = tostring(config.Title),
			TextColor3 = accent,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -12, 1, 0),
			ZIndex = 403,
			Parent = headerRow,
		})
	end

	if config.Content then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Regular,
			Text = tostring(config.Content),
			TextColor3 = theme.SubText,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = 2,
			ZIndex = 402,
			Parent = toast,
		})
	end

	toast.BackgroundTransparency = 1
	local startPos = UDim2.new(1, 60, 0, 0)
	toast.Position = startPos
	tween(toast, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0 }, 0.22, Enum.EasingStyle.Quart)

	local lifetime = config.Duration or 4
	task.delay(lifetime, function()
		if not toast.Parent then
			return
		end
		local fade = tween(toast, { Position = UDim2.new(1, 60, 0, 0) }, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		fade.Completed:Wait()
		if toast.Parent then
			toast:Destroy()
		end
	end)

	return toast
end

--=====================================================================
-- LOADER (cinematic splash)
--=====================================================================

local LoaderProto = {}
LoaderProto.__index = LoaderProto

local DEFAULT_STEPS = {
	"Establishing secure channel",
	"Mounting interface modules",
	"Compiling obsidian theme",
	"Calibrating motion curves",
	"Finalizing",
}

local function fadeOut(root, duration)
	duration = duration or 0.45
	if root:IsA("CanvasGroup") then
		tween(root, { GroupTransparency = 1 }, duration, Enum.EasingStyle.Quart)
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Frame") or d:IsA("TextButton") then
			tween(d, { BackgroundTransparency = 1 }, duration, Enum.EasingStyle.Quart)
		elseif d:IsA("TextLabel") or d:IsA("TextBox") then
			tween(d, { TextTransparency = 1, TextStrokeTransparency = 1 }, duration, Enum.EasingStyle.Quart)
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			tween(d, { ImageTransparency = 1 }, duration, Enum.EasingStyle.Quart)
		elseif d:IsA("UIStroke") then
			tween(d, { Transparency = 1 }, duration, Enum.EasingStyle.Quart)
		end
	end
end

function Library:CreateLoader(config)
	config = config or {}
	local theme = self.Theme
	local brand = tostring(config.Title or "LUCIFER")

	local gui = new("ScreenGui", {
		Name = "LuciferLoader",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20000,
	})
	local ok = pcall(function()
		gui.Parent = getGuiParent()
	end)
	if not ok or not gui.Parent then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	if config.Blur ~= false then
		blurGui(gui, config.BlurSize or 24)
	end

	local backdrop = new("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.fromRGB(5, 4, 8),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = gui,
	})
	gradient(backdrop, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(17, 12, 26)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(7, 6, 11)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 4, 6)),
	}), 90)

	local vignette = new("Frame", {
		Name = "Vignette",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = gui,
	})
	gradient(vignette, ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)), 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.95),
		NumberSequenceKeypoint.new(1, 0.5),
	}))

	-- content (CanvasGroup when available so the splash fades as one object)
	local content
	local canvasOk, canvas = pcall(function()
		return new("CanvasGroup", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(560, 380),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 10,
			Parent = gui,
		})
	end)
	if canvasOk and canvas then
		content = canvas
	else
		content = new("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(560, 380),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 10,
			Parent = gui,
		})
	end
	local contentScale = addScale(content, 0.985)

	new("UIListLayout", {
		Padding = UDim.new(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})

	--=============================================================
	-- MARK: two counter-rotating arcs over a hairline track
	--=============================================================
	local markHolder = new("Frame", {
		Name = "Mark",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(150, 150),
		LayoutOrder = 1,
		ZIndex = 11,
		Parent = content,
	})

	local function ringFrame(diameter, thickness, transparency, zindex)
		local holder = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(diameter, diameter),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = zindex,
			Parent = markHolder,
		})
		local face = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = zindex,
			Parent = holder,
		})
		local shape = corner(face, 0)
		shape.CornerRadius = UDim.new(0.5, 0)
		local line = new("UIStroke", {
			Color = theme.AccentLight,
			Thickness = thickness,
			Transparency = transparency,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = face,
		})
		return holder, line
	end

	local trackHolder, trackLine = ringFrame(150, 1, 0.86, 12)

	local arcHolderA, arcA = ringFrame(150, 2, 0.05, 13)
	pcall(function()
		gradient(arcA, ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.AccentLight),
			ColorSequenceKeypoint.new(0.5, theme.Accent),
			ColorSequenceKeypoint.new(1, theme.AccentAlt),
		}), 0, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}))
	end)

	local arcHolderB, arcB = ringFrame(122, 1, 0.2, 13)
	pcall(function()
		gradient(arcB, ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.AccentAlt),
			ColorSequenceKeypoint.new(1, theme.Accent),
		}), 0, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}))
	end)

	local badge = new("Frame", {
		Name = "Badge",
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(84, 84),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 14,
		Parent = markHolder,
	})
	corner(badge, 26)
	gradient(badge, ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.Accent),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(143, 92, 240)),
		ColorSequenceKeypoint.new(1, theme.AccentAlt),
	}), 45)
	stroke(badge, Color3.new(1, 1, 1), 1, 0.66)
	glassEdge(badge, 26, 0.84)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Bold,
		Text = string.sub(brand, 1, 1),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 42,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 15,
		Parent = badge,
	})

	--=============================================================
	-- TYPE
	--=============================================================
	local wordmark = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Bold,
		Text = spaced(upper(brand), 1),
		TextColor3 = theme.Text,
		TextSize = 31,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 2,
		ZIndex = 11,
		Parent = content,
	})
	gradient(wordmark, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, theme.Text),
		ColorSequenceKeypoint.new(1, theme.AccentLight),
	}), 90)

	new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Medium,
		Text = spaced(upper(config.Subtitle or "Premium Interface Suite"), 1),
		TextColor3 = theme.DimText,
		TextSize = 10,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 3,
		ZIndex = 11,
		Parent = content,
	})

	local rule = new("Frame", {
		BackgroundColor3 = theme.OutlineLight,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(430, 1),
		LayoutOrder = 4,
		ZIndex = 11,
		Parent = content,
	})
	gradient(rule, ColorSequence.new(theme.OutlineLight, theme.OutlineLight), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	}))

	new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 34),
		LayoutOrder = 5,
		Parent = content,
	})

	--=============================================================
	-- PROGRESS
	--=============================================================
	local barHolder = new("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(340, 4),
		LayoutOrder = 6,
		ZIndex = 11,
		Parent = content,
	})

	local track = new("Frame", {
		BackgroundColor3 = theme.Outline,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 12,
		Parent = barHolder,
	})
	local tc = corner(track, 0)
	tc.CornerRadius = UDim.new(0.5, 0)

	local clip = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 12,
		Parent = track,
	})
	local cc = corner(clip, 0)
	cc.CornerRadius = UDim.new(0.5, 0)

	local fill = new("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 13,
		Parent = track,
	})
	local fc = corner(fill, 0)
	fc.CornerRadius = UDim.new(0.5, 0)
	gradient(fill, ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.AccentDark),
		ColorSequenceKeypoint.new(0.55, theme.Accent),
		ColorSequenceKeypoint.new(1, theme.AccentLight),
	}), 0)

	local head = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(7, 7),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		ZIndex = 14,
		Parent = fill,
	})
	local hc = corner(head, 0)
	hc.CornerRadius = UDim.new(0.5, 0)

	local sheen = new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 60, 1, 0),
		Position = UDim2.new(0, -70, 0, 0),
		ZIndex = 15,
		Parent = clip,
	})
	gradient(sheen, ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	}))

	task.spawn(function()
		while gui.Parent do
			sheen.Position = UDim2.new(0, -70, 0, 0)
			tween(sheen, { Position = UDim2.new(0, 340, 0, 0) }, 1.6, Enum.EasingStyle.Linear)
			task.wait(1.6)
		end
	end)

	--=============================================================
	-- STATUS
	--=============================================================
	local statusRow = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(340, 18),
		LayoutOrder = 7,
		ZIndex = 11,
		Parent = content,
	})

	local statusLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Regular,
		Text = "Initializing",
		TextColor3 = theme.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.78, 0, 1, 0),
		ZIndex = 12,
		Parent = statusRow,
	})

	local percentLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Medium,
		Text = "0%",
		TextColor3 = theme.AccentLight,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0.22, 0, 1, 0),
		Position = UDim2.fromScale(0.78, 0),
		ZIndex = 12,
		Parent = statusRow,
	})

	new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 26),
		LayoutOrder = 8,
		Parent = content,
	})

	local footer = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Regular,
		Text = spaced(upper(config.Footer or ("Lucifer v" .. Library.Version)), 1),
		TextColor3 = theme.DimText,
		TextSize = 9,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 9,
		ZIndex = 11,
		Parent = content,
	})

	local self_ = setmetatable({
		Gui = gui,
		Content = content,
		Fill = fill,
		Track = track,
		Status = statusLabel,
		Percent = percentLabel,
		Progress = 0,
		Finished = false,
	}, LoaderProto)

	function self_:SetStatus(text)
		text = tostring(text)
		if statusLabel.Text == text then
			return
		end
		statusLabel.Text = text
		statusLabel.TextTransparency = 0.6
		tween(statusLabel, { TextTransparency = 0 }, 0.24)
	end

	function self_:SetProgress(alpha, text)
		alpha = clamp(alpha or 0, 0, 1)
		self_.Progress = alpha
		tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, 0.3, Enum.EasingStyle.Quart)
		percentLabel.Text = string.format("%d%%", math.floor(alpha * 100 + 0.5))
		if text then
			self_:SetStatus(text)
		end
	end

	function self_:Auto(duration, onComplete)
		local steps = config.Steps or DEFAULT_STEPS
		local total = duration or 2.4
		local elapsed = 0
		task.spawn(function()
			while elapsed < total and gui.Parent do
				elapsed = elapsed + (task.wait(0.03) or 0.03)
				local t = clamp(elapsed / total, 0, 1)
				local eased = 1 - (1 - t) ^ 2.4
				local index = clamp(math.floor(eased * #steps) + 1, 1, #steps)
				self_:SetProgress(eased, steps[index])
			end
			self_:Finish(onComplete)
		end)
		return self_
	end

	function self_:Finish(onComplete)
		if self_.Finished then
			return self_
		end
		self_.Finished = true
		if not gui.Parent then
			if onComplete then
				onComplete()
			end
			return self_
		end
		self_:SetProgress(1, config.DoneText or "Ready")
		task.delay(config.Hold or 0.45, function()
			tweenScale(contentScale, 1.03, 0.55)
			tween(backdrop, { BackgroundTransparency = 1 }, 0.5, Enum.EasingStyle.Quart)
			tween(vignette, { BackgroundTransparency = 1 }, 0.5, Enum.EasingStyle.Quart)
			fadeOut(content, 0.45)
			if onComplete then
				task.delay(0.2, onComplete)
			end
			task.delay(0.75, function()
				pcall(function()
					gui:Destroy()
				end)
			end)
		end)
		return self_
	end

	function self_:Destroy()
		pcall(function()
			gui:Destroy()
		end)
	end

	-- entrance + idle rotation
	tweenScale(contentScale, 1, 0.7, Enum.EasingStyle.Quart)

	task.spawn(function()
		local angleA, angleB = 0, 0
		while gui.Parent do
			local dt = RunService.RenderStepped:Wait()
			angleA = (angleA + dt * 130) % 360
			angleB = (angleB - dt * 80) % 360
			arcHolderA.Rotation = angleA
			arcHolderB.Rotation = angleB
		end
	end)

	return self_
end

--=====================================================================
-- WINDOW
--=====================================================================

local TabProto = {}

local Window = {}
Window.__index = Window

function Library:CreateWindow(config)
	config = config or {}

	local theme = self.Theme
	local holder = getGuiParent()

	local screenGui = new("ScreenGui", {
		Name = "Lucifer_" .. tostring(config.Title or "UI"),
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
	})

	local guiOk = pcall(function()
		screenGui.Parent = holder
	end)
	if not guiOk or not screenGui.Parent then
		screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	local windowSize = config.Size or UDim2.fromOffset(620, 460)

	if config.Blur ~= false then
		blurGui(screenGui, config.BlurSize or 12)
	end

	local windowPosition = UDim2.new(0.5, 0, 0.5, 0)

	-- The shadow mirrors the window's own Position/AnchorPoint instead of using
	-- AbsolutePosition, which is offset by the GUI inset and made it drift.
	local shadow = new("Frame", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = windowPosition,
		Size = windowSize,
		ZIndex = 1,
		Parent = screenGui,
	})

	local bloom = new("Frame", {
		Name = "Bloom",
		BackgroundColor3 = theme.Accent,
		BackgroundTransparency = 0.955,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(1, 52, 1, 52),
		ZIndex = 1,
		Parent = shadow,
	})
	corner(bloom, 34)

	local shadowLayers = {}
	for _, spec in ipairs({
		{ grow = 30, alpha = 0.935, drop = 9, radius = 20 },
		{ grow = 16, alpha = 0.9, drop = 5, radius = 18 },
		{ grow = 6, alpha = 0.84, drop = 2, radius = 16 },
	}) do
		local layer = new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = spec.alpha,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, spec.drop),
			Size = UDim2.new(1, spec.grow, 1, spec.grow),
			ZIndex = 1,
			Parent = shadow,
		})
		corner(layer, spec.radius)
		table.insert(shadowLayers, { frame = layer, base = spec.alpha })
	end

	local main = new("Frame", {
		Name = "Main",
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		Size = windowSize,
		Position = windowPosition,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = screenGui,
	})
	corner(main, 14)
	stroke(main, theme.Outline, 1, 0.1)
	gradient(main, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 14, 23)),
		ColorSequenceKeypoint.new(1, theme.Background),
	}), 90)
	glassEdge(main, 14, 0.93)

	-- top bar
	local topBar = new("Frame", {
		Name = "TopBar",
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 54),
		ZIndex = 3,
		Parent = main,
	})
	gradient(topBar, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 21, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 12, 19)),
	}), 90)

	local accentLine = new("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		ZIndex = 4,
		Parent = topBar,
	})
	gradient(accentLine, ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.AccentAlt),
		ColorSequenceKeypoint.new(0.5, theme.Accent),
		ColorSequenceKeypoint.new(1, theme.AccentLight),
	}), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	}))

	-- brand badge
	local brand = new("Frame", {
		Name = "Brand",
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 5,
		Parent = topBar,
	})
	corner(brand, 9)
	gradient(brand, ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.AccentLight),
		ColorSequenceKeypoint.new(0.55, theme.Accent),
		ColorSequenceKeypoint.new(1, theme.AccentAlt),
	}), 45)
	halo(brand, theme.Accent, 6, 0.8)

	local brandLetter = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Bold,
		Text = string.sub(tostring(config.Title or "Lucifer"), 1, 1),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = brand,
	})

	-- brand row: title + version pill
	local brandRow = new("Frame", {
		Name = "BrandRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.6, -60, 1, 0),
		Position = UDim2.fromOffset(54, 0),
		ZIndex = 5,
		Parent = topBar,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = brandRow,
	})

	local titleLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Bold,
		Text = tostring(config.Title or "Lucifer"),
		TextColor3 = theme.Text,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 20),
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = brandRow,
	})

	if config.Subtitle then
		local pill = new("Frame", {
			BackgroundColor3 = theme.Glass,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 18),
			LayoutOrder = 2,
			ZIndex = 6,
			Parent = brandRow,
		})
		corner(pill, 5)
		stroke(pill, theme.OutlineLight, 1, 0.6)
		padding(pill, 0, 7, 0, 7)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = upper(config.Subtitle),
			TextColor3 = theme.SubText,
			TextSize = 9,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 7,
			Parent = pill,
		})
	end

	-- window controls
	local controls = new("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(72, 54),
		Position = UDim2.new(1, -14, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 5,
		Parent = topBar,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = controls,
	})

	local self_ = setmetatable({
		Title = config.Title or "Lucifer",
		Gui = screenGui,
		Main = main,
		TopBar = topBar,
		Tabs = {},
		TabOrder = 0,
		ActiveTab = nil,
		Minimized = false,
		ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift,
		Holder = holder,
	}, Window)

	local function chromeButton(order)
		local btn = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.SurfaceLight,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(24, 24),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = controls,
		})
		corner(btn, 12)
		local s = stroke(btn, theme.OutlineLight, 1, 0.55)
		return btn, s
	end

	-- minimize
	local minBtn, minStroke = chromeButton(1)
	local minIcon = new("Frame", {
		BackgroundColor3 = theme.SubText,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(9, 2),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 7,
		Parent = minBtn,
	})
	corner(minIcon, 1)

	-- close
	local closeBtn, closeStroke = chromeButton(2)
	local closeIcon = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = closeBtn,
	})
	local closeBarA = new("Frame", {
		BackgroundColor3 = theme.SubText,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(9, 2),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		ZIndex = 7,
		Parent = closeIcon,
	})
	corner(closeBarA, 1)
	local closeBarB = new("Frame", {
		BackgroundColor3 = theme.SubText,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(9, 2),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -45,
		ZIndex = 7,
		Parent = closeIcon,
	})
	corner(closeBarB, 1)

	minBtn.MouseEnter:Connect(function()
		tween(minBtn, { BackgroundColor3 = theme.SurfaceHover, BackgroundTransparency = 0 }, 0.14)
		tween(minIcon, { BackgroundColor3 = theme.Text }, 0.14)
		tween(minStroke, { Transparency = 0.2 }, 0.14)
	end)
	minBtn.MouseLeave:Connect(function()
		tween(minBtn, { BackgroundColor3 = theme.SurfaceLight, BackgroundTransparency = 0.35 }, 0.14)
		tween(minIcon, { BackgroundColor3 = theme.SubText }, 0.14)
		tween(minStroke, { Transparency = 0.55 }, 0.14)
	end)
	closeBtn.MouseEnter:Connect(function()
		tween(closeBtn, { BackgroundColor3 = theme.Danger, BackgroundTransparency = 0.05 }, 0.14)
		tween(closeBarA, { BackgroundColor3 = Color3.new(1, 1, 1) }, 0.14)
		tween(closeBarB, { BackgroundColor3 = Color3.new(1, 1, 1) }, 0.14)
		tween(closeStroke, { Transparency = 0.4 }, 0.14)
	end)
	closeBtn.MouseLeave:Connect(function()
		tween(closeBtn, { BackgroundColor3 = theme.SurfaceLight, BackgroundTransparency = 0.35 }, 0.14)
		tween(closeBarA, { BackgroundColor3 = theme.SubText }, 0.14)
		tween(closeBarB, { BackgroundColor3 = theme.SubText }, 0.14)
		tween(closeStroke, { Transparency = 0.55 }, 0.14)
	end)

	closeBtn.MouseButton1Click:Connect(function()
		self_:Destroy()
	end)

	minBtn.MouseButton1Click:Connect(function()
		self_:SetMinimized(not self_.Minimized)
	end)

	-- sidebar
	local sidebar = new("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 168, 1, -54),
		Position = UDim2.fromOffset(0, 54),
		ZIndex = 3,
		Parent = main,
	})
	padding(sidebar, 12, 12, 12, 12)
	gradient(sidebar, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 16, 26)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 11, 17)),
	}), 90)

	local sidebarDivider = new("Frame", {
		BackgroundColor3 = theme.Outline,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 1, 1, 24),
		Position = UDim2.new(1, 12, 0, -12),
		ZIndex = 4,
		Parent = sidebar,
	})
	gradient(sidebarDivider, ColorSequence.new(theme.Outline, theme.Outline), 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	}))

	local sectionCaption = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Medium,
		Text = spaced("NAVIGATION", 1),
		TextColor3 = theme.DimText,
		TextSize = 8,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(4, 0),
		ZIndex = 4,
		Parent = sidebar,
	})

	local tabList = new("Frame", {
		Name = "TabList",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 20),
		ZIndex = 4,
		Parent = sidebar,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabList,
	})

	local versionLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Fonts.Regular,
		Text = spaced(upper("Lucifer v" .. Library.Version), 1),
		TextColor3 = theme.DimText,
		TextSize = 8,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, 0),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 4,
		Parent = sidebar,
	})

	-- content area
	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -168, 1, -54),
		Position = UDim2.fromOffset(168, 54),
		ZIndex = 3,
		Parent = main,
	})

	-- resize grip
	if config.Resizable ~= false then
		local grip = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(1, -16, 1, -16),
			ZIndex = 20,
			Parent = main,
		})
		local gripLine1 = new("Frame", {
			BackgroundColor3 = theme.OutlineLight,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(8, 1),
			Position = UDim2.new(1, -10, 1, -5),
			Rotation = -45,
			ZIndex = 21,
			Parent = grip,
		})
		local gripLine2 = new("Frame", {
			BackgroundColor3 = theme.OutlineLight,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(4, 1),
			Position = UDim2.new(1, -6, 1, -9),
			Rotation = -45,
			ZIndex = 21,
			Parent = grip,
		})

		local resizing = false
		local startSize, startMouse

		grip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				resizing = true
				startSize = main.AbsoluteSize
				startMouse = UserInputService:GetMouseLocation()
			end
		end)

		track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				resizing = false
			end
		end))

		track(RunService.RenderStepped:Connect(function()
			if not resizing then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			local delta = mouse - startMouse
			local newWidth = math.max(480, startSize.X + delta.X)
			local newHeight = math.max(320, startSize.Y + delta.Y)
			main.Size = UDim2.fromOffset(newWidth, newHeight)
			shadow.Size = main.Size
		end))
	end

	-- dragging
	local dragging = false
	local dragStart, startPos

	topBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
			self_._lift(true)
		end
	end)

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
			shadow.Position = main.Position
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				self_._lift(false)
			end
		end
	end))

	-- notifications container for this gui
	ensureNotificationHolder()

	-- tooltip
	if not Tooltip then
		Tooltip = createTooltip(screenGui)
		track(RunService.RenderStepped:Connect(function()
			if Tooltip then
				Tooltip.Update()
			end
		end))
	end

	-- window toggle key
	if self_.ToggleKey then
		track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if Library._Listening then
				return
			end
			if input.KeyCode == self_.ToggleKey then
				self_:Toggle()
			end
		end))
	end

	--=============================================================
	-- MOTION
	--=============================================================
	local mainScale = addScale(main, 1)
	local shadowScale = addScale(shadow, 1)

	local function setScale(value, time, style, dir)
		tweenScale(mainScale, value, time, style, dir)
		tweenScale(shadowScale, value, time, style, dir)
	end

	-- subtle "pick up" while the window is being dragged
	function self_._lift(state)
		if self_.Minimized or not self_.Revealed then
			return
		end
		if state then
			setScale(1.014, 0.16, Enum.EasingStyle.Quad)
			for _, layer in ipairs(shadowLayers) do
				tween(layer.frame, { BackgroundTransparency = math.max(layer.base - 0.05, 0.6) }, 0.2)
			end
			tween(bloom, { BackgroundTransparency = 0.9 }, 0.2)
		else
			setScale(1, 0.42, Enum.EasingStyle.Back)
			for _, layer in ipairs(shadowLayers) do
				tween(layer.frame, { BackgroundTransparency = layer.base }, 0.3)
			end
			tween(bloom, { BackgroundTransparency = 0.955 }, 0.3)
		end
	end

	--=============================================================
	-- LAUNCHER (floating show/hide button)
	--=============================================================
	local launcher, launcherScale, launcherRing

	function self_:CreateToggleButton(cfg)
		if launcher then
			return launcher
		end
		cfg = cfg or {}
		local diameter = 46

		launcher = new("TextButton", {
			Name = "LuciferLauncher",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = cfg.Position or UDim2.new(0, 22, 0.5, 0),
			Size = UDim2.fromOffset(diameter, diameter),
			ZIndex = 40,
			Parent = screenGui,
		})
		local shape = corner(launcher, 0)
		shape.CornerRadius = UDim.new(0.5, 0)
		gradient(launcher, ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.AccentLight),
			ColorSequenceKeypoint.new(0.55, theme.Accent),
			ColorSequenceKeypoint.new(1, theme.AccentAlt),
		}), 45)
		launcherRing = halo(launcher, theme.Accent, 8, 0.55)
		glassEdge(launcher, diameter / 2, 0.82)
		launcherScale = addScale(launcher, 1)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Bold,
			Text = string.sub(tostring(cfg.Text or "Lucifer"), 1, 1),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 20,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 41,
			Parent = launcher,
		})

		local draggingBtn = false
		local moved = false
		local dragOrigin, startPos

		launcher.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				draggingBtn = true
				moved = false
				dragOrigin = input.Position
				startPos = launcher.Position
			end
		end)

		track(UserInputService.InputChanged:Connect(function(input)
			if not draggingBtn then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - dragOrigin
				if math.abs(delta.X) > 3 or math.abs(delta.Y) > 3 then
					moved = true
				end
				if moved then
					launcher.Position = UDim2.new(
						startPos.X.Scale,
						startPos.X.Offset + delta.X,
						startPos.Y.Scale,
						startPos.Y.Offset + delta.Y
					)
				end
			end
		end))

		track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingBtn and not moved then
					self_:Toggle()
				end
				draggingBtn = false
			end
		end))

		launcher.MouseEnter:Connect(function()
			tweenScale(launcherScale, 1.09, 0.18, Enum.EasingStyle.Quart)
			tween(launcherRing, { Transparency = 0.22 }, 0.18)
		end)
		launcher.MouseLeave:Connect(function()
			tweenScale(launcherScale, 1, 0.26, Enum.EasingStyle.Back)
			tween(launcherRing, { Transparency = main.Visible and 0.55 or 0.86 }, 0.2)
		end)

		function self_._syncLauncher()
			if not launcher then
				return
			end
			local open = main.Visible and self_.Revealed
			tween(launcher, { BackgroundTransparency = open and 0 or 0.3 }, 0.25)
			if launcherRing then
				tween(launcherRing, { Transparency = open and 0.55 or 0.86 }, 0.25)
			end
		end

		return launcher
	end

	function self_:SetMinimized(state)
		self_.Minimized = state
		if state then
			self_._restoreSize = main.Size
			local collapsed = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, 54)
			tween(main, { Size = collapsed }, 0.34, Enum.EasingStyle.Back)
			tween(shadow, { Size = collapsed }, 0.34, Enum.EasingStyle.Back)
		else
			local target = self_._restoreSize or config.Size or UDim2.fromOffset(620, 460)
			tween(main, { Size = target }, 0.34, Enum.EasingStyle.Back)
			tween(shadow, { Size = target }, 0.34, Enum.EasingStyle.Back)
		end
	end

	function self_:Toggle()
		if main.Visible then
			self_:Hide()
		else
			self_:Show()
		end
	end

	function self_:Show()
		if self_._destroying then
			return
		end
		main.Visible = true
		shadow.Visible = true
		mainScale.Scale = 0.94
		shadowScale.Scale = 0.94
		setScale(1, 0.45, Enum.EasingStyle.Back)
		if self_._syncLauncher then
			self_._syncLauncher()
		end
	end

	function self_:Hide()
		if not main.Visible then
			return
		end
		setScale(0.94, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if self_._destroying then
				return
			end
			main.Visible = false
			shadow.Visible = false
			mainScale.Scale = 1
			shadowScale.Scale = 1
			if self_._syncLauncher then
				self_._syncLauncher()
			end
		end)
	end

	function self_:Destroy(instant)
		if self_._destroying then
			return
		end
		self_._destroying = true

		local function teardown()
			for _, connection in ipairs(Library.Connections) do
				pcall(function()
					connection:Disconnect()
				end)
			end
			Library.Connections = {}
			pcall(function()
				screenGui:Destroy()
			end)
			if Library.NotificationGui then
				pcall(function()
					Library.NotificationGui:Destroy()
				end)
			end
			Library.NotificationHolder = nil
			Library.NotificationGui = nil
			Tooltip = nil
		end

		if instant or not main.Parent then
			teardown()
			return
		end

		setScale(0.9, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.18, teardown)
	end

	function self_:SetTitle(text)
		titleLabel.Text = tostring(text)
	end

	-- tab factory
	function self_:AddTab(name)
		self_.TabOrder = self_.TabOrder + 1
		local order = self_.TabOrder

		local button = new("TextButton", {
			Name = "Tab_" .. tostring(name),
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.Glass,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			ZIndex = 5,
			Parent = tabList,
		})
		corner(button, 9)
		local buttonStroke = stroke(button, theme.Accent, 1, 1)

		local indicator = new("Frame", {
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 0, 0),
			Position = UDim2.new(0, -1, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 6,
			Parent = button,
		})
		corner(indicator, 2)
		halo(indicator, theme.Accent, 4, 0.55)

		local dot = new("Frame", {
			BackgroundColor3 = theme.DimText,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(5, 5),
			Position = UDim2.new(0, 14, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 6,
			Parent = button,
		})
		local dotCorner = corner(dot, 0)
		dotCorner.CornerRadius = UDim.new(0.5, 0)

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(name),
			TextColor3 = theme.SubText,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(27, 0),
			Size = UDim2.new(1, -33, 1, 0),
			ZIndex = 6,
			Parent = button,
		})

		local page = new("ScrollingFrame", {
			Name = "Page_" .. tostring(name),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = theme.OutlineLight,
			ScrollBarImageTransparency = 0.35,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
			ZIndex = 4,
			Parent = content,
		})
		padding(page, 14, 16, 14, 14)
		new("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = page,
		})

		local tab = setmetatable({
			Name = name,
			Button = button,
			ButtonStroke = buttonStroke,
			Label = label,
			Indicator = indicator,
			Dot = dot,
			Page = page,
			SectionOrder = 0,
			Window = self_,
		}, { __index = TabProto })

		function tab:Select()
			self_.ActiveTab = self
			for _, other in pairs(self_.Tabs) do
				other.Page.Visible = false
				tween(other.Button, { BackgroundTransparency = 1 }, 0.14)
				tween(other.ButtonStroke, { Transparency = 1 }, 0.14)
				tween(other.Label, { TextColor3 = theme.SubText }, 0.14)
				tween(other.Dot, { BackgroundColor3 = theme.DimText }, 0.14)
				tween(other.Indicator, { Size = UDim2.new(0, 3, 0, 0) }, 0.14)
			end
			self.Page.Visible = true
			self.Page.Position = UDim2.fromOffset(0, 12)
			tween(self.Page, { Position = UDim2.fromOffset(0, 0) }, 0.3, Enum.EasingStyle.Quart)
			tween(self.Button, { BackgroundTransparency = 0.16 }, 0.16)
			tween(self.ButtonStroke, { Transparency = 0.6 }, 0.16)
			tween(self.Label, { TextColor3 = theme.Text }, 0.16)
			tween(self.Dot, { BackgroundColor3 = theme.Accent }, 0.16)
			tween(self.Indicator, { Size = UDim2.new(0, 3, 0, 16) }, 0.24, Enum.EasingStyle.Quart)
		end

		button.MouseEnter:Connect(function()
			if self_.ActiveTab ~= tab then
				tween(button, { BackgroundColor3 = theme.SurfaceHover, BackgroundTransparency = 0.72 }, 0.12)
				tween(label, { TextColor3 = theme.Text }, 0.12)
			end
		end)
		button.MouseLeave:Connect(function()
			if self_.ActiveTab ~= tab then
				tween(button, { BackgroundTransparency = 1 }, 0.12)
				tween(label, { TextColor3 = theme.SubText }, 0.12)
			end
		end)
		button.MouseButton1Click:Connect(function()
			tab:Select()
		end)

		table.insert(self_.Tabs, tab)
		if #self_.Tabs == 1 then
			tab:Select()
		end

		return tab
	end

	--=============================================================
	-- ENTRANCE
	--=============================================================

	function self_:Reveal(instant)
		if self_.Revealed then
			return
		end
		self_.Revealed = true
		main.Visible = true
		shadow.Visible = true
		if instant then
			mainScale.Scale = 1
			shadowScale.Scale = 1
			return
		end
		mainScale.Scale = 0.9
		shadowScale.Scale = 0.9
		setScale(1, 0.68, Enum.EasingStyle.Back)
		if self_._syncLauncher then
			self_._syncLauncher()
		end
	end

	-- floating launcher button
	if config.ToggleButton ~= false then
		self_:CreateToggleButton({
			Text = config.Title or "Lucifer",
			Key = config.ToggleKey,
			Position = config.ToggleButtonPosition,
		})
	end

	if config.Loader then
		main.Visible = false
		shadow.Visible = false
		local loaderConfig = type(config.Loader) == "table" and config.Loader or {}
		local loader = self:CreateLoader({
			Title = config.Title,
			Subtitle = loaderConfig.Subtitle or "Premium Interface Suite",
			Steps = loaderConfig.Steps,
			Footer = loaderConfig.Footer,
			Blur = config.Blur,
		})
		loader:Auto(loaderConfig.Duration or 2.6, function()
			self_:Reveal()
		end)
	else
		self_:Reveal()
	end

	return self_
end

--=====================================================================
-- SECTION
--=====================================================================

local function createSection(tab, title, side)
	local theme = Library.Theme
	tab.SectionOrder = tab.SectionOrder + 1

	local section = new("Frame", {
		Name = "Section_" .. tostring(title or tab.SectionOrder),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = tab.SectionOrder,
		ZIndex = 5,
		Parent = tab.Page,
	})
	corner(section, 12)
	stroke(section, theme.Outline, 1, 0.45)
	gradient(section, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 18, 28)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 13, 20)),
	}), 90)
	padding(section, 12, 12, 12, 12)

	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = section,
	})

	if title then
		local header = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 0,
			ZIndex = 6,
			Parent = section,
		})

		local bar = new("Frame", {
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(3, 11),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 7,
			Parent = header,
		})
		corner(bar, 2)
		gradient(bar, ColorSequence.new(theme.AccentLight, theme.Accent), 90)
		halo(bar, theme.Accent, 4, 0.6)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = spaced(upper(title), 0),
			TextColor3 = theme.SubText,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(11, 0),
			Size = UDim2.new(1, -11, 1, 0),
			ZIndex = 7,
			Parent = header,
		})
	end

	local elementOrder = 0
	local sectionApi = {}

	local function nextOrder()
		elementOrder = elementOrder + 10
		return elementOrder
	end

	local function attachTooltip(element, frame)
		if not frame then
			return
		end
		frame.MouseEnter:Connect(function()
			if element.Tooltip and Tooltip then
				Tooltip.Show(element.Tooltip)
			end
		end)
		frame.MouseLeave:Connect(function()
			if Tooltip then
				Tooltip.Hide()
			end
		end)
	end

	local function register(flag, getter, setter)
		if not flag then
			return
		end
		Library.Options[flag] = {
			Get = getter,
			Set = setter,
		}
	end

	--=============================================================
	-- BUTTON
	--=============================================================
	function sectionApi:AddButton(config)
		config = config or {}
		local order = nextOrder()

		local button = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			ClipsDescendants = true,
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(button, 8)
		local buttonStroke = stroke(button, theme.Outline, 1, 0.5)
		gradient(button, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 25, 39)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 19, 29)),
		}), 90)

		-- hover light sweep
		local sweep = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 46, 1, 0),
			Position = UDim2.new(0, -60, 0, 0),
			Rotation = 12,
			ZIndex = 7,
			Parent = button,
		})
		gradient(sweep, ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)), 0, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}))

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Button"),
			TextColor3 = theme.Text,
			TextSize = 13,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Parent = button,
		})

		local element = { Tooltip = config.Tooltip }
		element.Frame = button
		element.Clicked = Signal.new()

		button.MouseEnter:Connect(function()
			tween(button, { BackgroundColor3 = theme.SurfaceHover }, 0.14)
			tween(buttonStroke, { Color = theme.Accent, Transparency = 0.55 }, 0.16)
			tween(label, { TextColor3 = theme.AccentLight }, 0.14)
			sweep.Position = UDim2.new(0, -60, 0, 0)
			tween(sweep, { Position = UDim2.new(1, 20, 0, 0) }, 0.55, Enum.EasingStyle.Quad)
		end)
		button.MouseLeave:Connect(function()
			tween(button, { BackgroundColor3 = theme.SurfaceLight }, 0.16)
			tween(buttonStroke, { Color = theme.Outline, Transparency = 0.5 }, 0.16)
			tween(label, { TextColor3 = theme.Text }, 0.16)
		end)
		button.MouseButton1Click:Connect(function()
			element.Clicked:Fire()
			if config.Callback then
				local ok, err = pcall(config.Callback)
				if not ok then
					warn("[Lucifer] button callback: " .. tostring(err))
				end
			end
		end)

		function element:SetText(text)
			label.Text = tostring(text)
		end

		attachTooltip(element, button)
		return element
	end

	--=============================================================
	-- TOGGLE
	--=============================================================
	function sectionApi:AddToggle(config)
		config = config or {}
		local order = nextOrder()
		local flag = config.Flag or config.Name

		local container = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 38),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 8)
		gradient(container, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 24, 37)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 18, 28)),
		}), 90)

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Toggle"),
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -70, 1, 0),
			ZIndex = 7,
			Parent = container,
		})

		local switch = new("Frame", {
			BackgroundColor3 = theme.Outline,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(40, 20),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ClipsDescendants = false,
			ZIndex = 7,
			Parent = container,
		})
		corner(switch, 10)
		local switchGlow = halo(switch, theme.Accent, 6, 1)

		local switchTint = new("Frame", {
			BackgroundColor3 = theme.Accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = switch,
		})
		corner(switchTint, 10)
		gradient(switchTint, ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.AccentLight),
			ColorSequenceKeypoint.new(1, theme.Accent),
		}), 0)

		local knob = new("Frame", {
			BackgroundColor3 = theme.SubText,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0, 2, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 9,
			Parent = switch,
		})
		corner(knob, 8)
		local knobStroke = stroke(knob, theme.Outline, 1, 0.2)

		local element = { Tooltip = config.Tooltip }
		element.Frame = container
		element.Value = config.Default == true
		element.Changed = Signal.new()

		local function render(value, animate)
			local duration = animate and 0.18 or 0
			local targetPos = value and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
			local targetTint = value and 0 or 1
			local targetKnob = value and Color3.new(1, 1, 1) or theme.SubText
			local targetGlow = value and 0.45 or 1
			local targetStrokeColor = value and theme.AccentDark or theme.Outline

			if duration > 0 then
				tween(knob, { Position = targetPos, BackgroundColor3 = targetKnob }, duration, Enum.EasingStyle.Quart)
				tween(switchTint, { BackgroundTransparency = targetTint }, duration)
				tween(switchGlow, { Transparency = targetGlow }, duration)
				tween(knobStroke, { Color = targetStrokeColor }, duration)
			else
				knob.Position = targetPos
				knob.BackgroundColor3 = targetKnob
				switchTint.BackgroundTransparency = targetTint
				switchGlow.Transparency = targetGlow
				knobStroke.Color = targetStrokeColor
			end
		end

		function element:Set(value, silent)
			value = value and true or false
			self.Value = value
			render(value, true)
			if flag then
				Library.Flags[flag] = value
			end
			if not silent then
				self.Changed:Fire(value)
				if config.Callback then
					local ok, err = pcall(config.Callback, value)
					if not ok then
						warn("[Lucifer] toggle callback: " .. tostring(err))
					end
				end
			end
		end

		function element:Get()
			return self.Value
		end

		container.MouseButton1Click:Connect(function()
			element:Set(not element.Value)
		end)

		register(flag, function()
			return element.Value
		end, function(value)
			element:Set(value, true)
		end)

		render(element.Value, false)
		if flag then
			Library.Flags[flag] = element.Value
		end

		attachTooltip(element, container)
		return element
	end

	--=============================================================
	-- SLIDER
	--=============================================================
	function sectionApi:AddSlider(config)
		config = config or {}
		local order = nextOrder()
		local flag = config.Flag or config.Name
		local minValue = config.Min or 0
		local maxValue = config.Max or 100
		local decimals = config.Decimals or 0
		local step = config.Step

		local container = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 8)
		gradient(container, ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 24, 37)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 18, 28)),
		}), 90)

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Slider"),
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(0.7, 0, 0, 16),
			ZIndex = 7,
			Parent = container,
		})

		local valueChip = new("Frame", {
			BackgroundColor3 = theme.Accent,
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(1, -12, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 7,
			Parent = container,
		})
		corner(valueChip, 5)
		stroke(valueChip, theme.Accent, 1, 0.7)
		padding(valueChip, 0, 7, 0, 7)

		local valueLabel = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = "0",
			TextColor3 = theme.AccentLight,
			TextSize = 11,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 8,
			Parent = valueChip,
		})

		local hitbox = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -24, 0, 18),
			Position = UDim2.fromOffset(12, 30),
			ZIndex = 8,
			Parent = container,
		})

		local sliderTrack = new("Frame", {
			BackgroundColor3 = theme.Outline,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 5),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 8,
			Parent = hitbox,
		})
		local trackCorner = corner(sliderTrack, 0)
		trackCorner.CornerRadius = UDim.new(0.5, 0)

		local fill = new("Frame", {
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 9,
			Parent = sliderTrack,
		})
		local fillCorner = corner(fill, 0)
		fillCorner.CornerRadius = UDim.new(0.5, 0)
		gradient(fill, ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.AccentDark),
			ColorSequenceKeypoint.new(1, theme.AccentLight),
		}), 0)
		halo(fill, theme.Accent, 5, 0.75)

		local knob = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 10,
			Parent = sliderTrack,
		})
		local knobCorner = corner(knob, 0)
		knobCorner.CornerRadius = UDim.new(0.5, 0)
		local knobRing = stroke(knob, theme.Accent, 2, 0.1)

		hitbox.MouseEnter:Connect(function()
			tween(knob, { Size = UDim2.fromOffset(17, 17) }, 0.16, Enum.EasingStyle.Quart)
			tween(knobRing, { Color = theme.AccentLight, Transparency = 0 }, 0.16)
		end)
		hitbox.MouseLeave:Connect(function()
			tween(knob, { Size = UDim2.fromOffset(14, 14) }, 0.16, Enum.EasingStyle.Quart)
			tween(knobRing, { Color = theme.Accent, Transparency = 0.1 }, 0.16)
		end)

		local element = { Tooltip = config.Tooltip }
		element.Frame = container
		element.Value = config.Default or minValue
		element.Changed = Signal.new()

		local function formatValue(value)
			if decimals > 0 then
				return string.format("%." .. tostring(decimals) .. "f", value)
			end
			return tostring(math.floor(value + 0.5))
		end

		local function render()
			local alpha = 0
			if maxValue ~= minValue then
				alpha = (element.Value - minValue) / (maxValue - minValue)
			end
			alpha = clamp(alpha, 0, 1)
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			knob.Position = UDim2.new(alpha, 0, 0.5, 0)
			valueLabel.Text = formatValue(element.Value)
		end

		local function quantize(raw)
			local value = raw
			if step and step > 0 then
				value = roundTo(value, step)
			elseif decimals == 0 then
				value = math.floor(value + 0.5)
			end
			return clamp(value, minValue, maxValue)
		end

		function element:Set(value, silent)
			value = tonumber(value) or minValue
			value = quantize(value)
			self.Value = value
			render()
			if flag then
				Library.Flags[flag] = value
			end
			if not silent then
				self.Changed:Fire(value)
				if config.Callback then
					local ok, err = pcall(config.Callback, value)
					if not ok then
						warn("[Lucifer] slider callback: " .. tostring(err))
					end
				end
			end
		end

		function element:Get()
			return self.Value
		end

		local draggingSlider = false

		local function updateFromX(x)
			local relative = (x - sliderTrack.AbsolutePosition.X) / math.max(sliderTrack.AbsoluteSize.X, 1)
			relative = clamp(relative, 0, 1)
			element:Set(minValue + (maxValue - minValue) * relative)
		end

		hitbox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				draggingSlider = true
				updateFromX(input.Position.X)
			end
		end)

		track(UserInputService.InputChanged:Connect(function(input)
			if not draggingSlider then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				updateFromX(input.Position.X)
			end
		end))

		track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				draggingSlider = false
			end
		end))

		register(flag, function()
			return element.Value
		end, function(value)
			element:Set(value, true)
		end)

		element:Set(config.Default or minValue, true)
		if flag then
			Library.Flags[flag] = element.Value
		end

		attachTooltip(element, container)
		return element
	end

	--=============================================================
	-- DROPDOWN
	--=============================================================
	local function createDropdownBase(config, multi)
		local order = nextOrder()
		local flag = config.Flag or config.Name
		local options = config.Options or {}
		local open = false

		local container = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 6)

		local header = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = container,
		})

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Dropdown"),
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			ZIndex = 8,
			Parent = container,
		})

		local valueLabel = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Regular,
			Text = "",
			TextColor3 = theme.AccentLight,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0.45, 0, 0, 0),
			Size = UDim2.new(0.55, -32, 1, 0),
			ZIndex = 8,
			Parent = container,
		})

		local arrow = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Bold,
			Text = "v",
			TextColor3 = theme.SubText,
			TextSize = 11,
			Position = UDim2.new(1, -20, 0, 0),
			Size = UDim2.fromOffset(12, 34),
			ZIndex = 8,
			Parent = container,
		})

		local list = new("ScrollingFrame", {
			BackgroundColor3 = theme.Surface,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.fromOffset(0, 0),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = theme.OutlineLight,
			Visible = false,
			LayoutOrder = order + 5,
			ZIndex = 30,
			Parent = section,
		})
		corner(list, 6)
		stroke(list, theme.Outline, 1)
		padding(list, 4, 4, 4, 4)

		local listLayout = new("UIListLayout", {
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})

		local element = { Tooltip = config.Tooltip }
		element.Frame = container
		element.Options = options
		element.Changed = Signal.new()
		element.Multi = multi
		element.Value = multi and {} or nil

		local optionButtons = {}

		local function updateLabel()
			if multi then
				local selected = {}
				for _, optionValue in ipairs(options) do
					if element.Value[optionValue] then
						table.insert(selected, tostring(optionValue))
					end
				end
				if #selected == 0 then
					valueLabel.Text = "None"
					valueLabel.TextColor3 = theme.DimText
				else
					valueLabel.Text = table.concat(selected, ", ")
					valueLabel.TextColor3 = theme.AccentLight
				end
			else
				if element.Value == nil then
					valueLabel.Text = "None"
					valueLabel.TextColor3 = theme.DimText
				else
					valueLabel.Text = tostring(element.Value)
					valueLabel.TextColor3 = theme.AccentLight
				end
			end
		end

		local function refreshButtons()
			for optionValue, button in pairs(optionButtons) do
				local selected
				if multi then
					selected = element.Value[optionValue] == true
				else
					selected = element.Value == optionValue
				end
				if selected then
					button.BackgroundColor3 = theme.AccentDark
					button.TextColor3 = Color3.new(1, 1, 1)
				else
					button.BackgroundColor3 = theme.Surface
					button.TextColor3 = theme.SubText
				end
			end
		end

		local function rebuild()
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			optionButtons = {}

			for index, optionValue in ipairs(options) do
				local optionButton = new("TextButton", {
					Text = tostring(optionValue),
					AutoButtonColor = false,
					BackgroundColor3 = theme.Surface,
					BorderSizePixel = 0,
					Font = Fonts.Regular,
					TextColor3 = theme.SubText,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, 0, 0, 24),
					LayoutOrder = index,
					ZIndex = 31,
					Parent = list,
				})
				corner(optionButton, 4)
				padding(optionButton, 0, 0, 0, 8)

				optionButton.MouseEnter:Connect(function()
					if not (multi and element.Value[optionValue]) and element.Value ~= optionValue then
						tween(optionButton, { BackgroundColor3 = theme.SurfaceHover }, 0.08)
					end
				end)
				optionButton.MouseLeave:Connect(function()
					refreshButtons()
				end)
				optionButton.MouseButton1Click:Connect(function()
					if multi then
						element:ToggleOption(optionValue)
					else
						element:Set(optionValue)
						element:Open(false)
					end
				end)

				optionButtons[optionValue] = optionButton
			end

			list.CanvasSize = UDim2.new(0, 0, 0, #options * 26)
			list.Size = UDim2.new(1, 0, 0, math.min(#options * 26 + 8, 150))
			refreshButtons()
		end

		function element:Open(state)
		open = state
		list.Visible = state
		arrow.Text = state and "^" or "v"
		if state then
			rebuild()
		end
	end

	function element:Set(value, silent)
		if multi then
			if type(value) == "table" then
				self.Value = {}
				for _, optionValue in ipairs(options) do
					if value[optionValue] then
						self.Value[optionValue] = true
					end
				end
			end
		else
			self.Value = value
		end
		updateLabel()
		refreshButtons()
		if flag then
			Library.Flags[flag] = self.Value
		end
		if not silent then
			self.Changed:Fire(self.Value)
			if config.Callback then
				local ok, err = pcall(config.Callback, self.Value)
				if not ok then
					warn("[Lucifer] dropdown callback: " .. tostring(err))
				end
			end
		end
	end

	function element:ToggleOption(optionValue)
		if not multi then
			return
		end
		if self.Value[optionValue] then
			self.Value[optionValue] = nil
		else
			self.Value[optionValue] = true
		end
		self:Set(self.Value)
	end

	function element:Get()
		return self.Value
	end

	function element:SetOptions(newOptions)
		options = newOptions or {}
		element.Options = options
		updateLabel()
		if open then
			rebuild()
		end
	end

	header.MouseButton1Click:Connect(function()
		element:Open(not open)
	end)

	container.MouseEnter:Connect(function()
		tween(container, { BackgroundColor3 = theme.SurfaceHover }, 0.1)
	end)
	container.MouseLeave:Connect(function()
		tween(container, { BackgroundColor3 = theme.SurfaceLight }, 0.1)
	end)

	register(flag, function()
		return element.Value
	end, function(value)
		element:Set(value, true)
	end)

	if multi then
		local default = config.Default
		if type(default) == "table" then
			for _, optionValue in ipairs(options) do
				if default[optionValue] then
					element.Value[optionValue] = true
				end
			end
		end
	else
		element.Value = config.Default or options[1]
	end

	updateLabel()
	if flag then
		Library.Flags[flag] = element.Value
	end

	attachTooltip(element, container)
	return element
	end

	function sectionApi:AddDropdown(config)
		return createDropdownBase(config, false)
	end

	function sectionApi:AddMultiDropdown(config)
		return createDropdownBase(config, true)
	end

	--=============================================================
	-- INPUT (textbox)
	--=============================================================
	function sectionApi:AddInput(config)
		config = config or {}
		local order = nextOrder()
		local flag = config.Flag or config.Name

		local container = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 6)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Input"),
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(0.42, 0, 1, 0),
			ZIndex = 7,
			Parent = container,
		})

		local box = new("TextBox", {
			BackgroundColor3 = theme.Background,
			BorderSizePixel = 0,
			Font = Fonts.Regular,
			Text = tostring(config.Default or ""),
			PlaceholderText = tostring(config.Placeholder or "Type here..."),
			PlaceholderColor3 = theme.DimText,
			TextColor3 = theme.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Position = UDim2.new(0.42, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(0.58, -14, 0, 24),
			ZIndex = 7,
			Parent = container,
		})
		corner(box, 5)
		padding(box, 0, 8, 0, 8)

		local element = { Tooltip = config.Tooltip }
		element.Frame = container
		element.Value = tostring(config.Default or "")
		element.Changed = Signal.new()

		function element:Set(value, silent)
			value = tostring(value or "")
			self.Value = value
			box.Text = value
			if flag then
				Library.Flags[flag] = value
			end
			if not silent then
				self.Changed:Fire(value)
				if config.Callback then
					local ok, err = pcall(config.Callback, value)
					if not ok then
						warn("[Lucifer] input callback: " .. tostring(err))
					end
				end
			end
		end

		function element:Get()
			return self.Value
		end

		box.Focused:Connect(function()
			tween(box, { BackgroundColor3 = theme.SurfaceHover }, 0.1)
		end)
		box.FocusLost:Connect(function(enterPressed)
			tween(box, { BackgroundColor3 = theme.Background }, 0.1)
			element:Set(box.Text)
		end)

		register(flag, function()
			return element.Value
		end, function(value)
			element:Set(value, true)
		end)

		if flag then
			Library.Flags[flag] = element.Value
		end

		attachTooltip(element, container)
		return element
	end

	--=============================================================
	-- KEYBIND
	--=============================================================
	function sectionApi:AddKeybind(config)
		config = config or {}
		local order = nextOrder()
		local flag = config.Flag or config.Name

		local container = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 6)

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Keybind"),
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(0.6, 0, 1, 0),
			ZIndex = 7,
			Parent = container,
		})

		local keyButton = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.Background,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(90, 22),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ZIndex = 7,
			Parent = container,
		})
		corner(keyButton, 5)

		local keyLabel = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = "None",
			TextColor3 = theme.SubText,
			TextSize = 11,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Parent = keyButton,
		})

		local element = { Tooltip = config.Tooltip }
		element.Frame = container
		element.Value = config.Default
		element.Pressed = Signal.new()
		element.Changed = Signal.new()
		local listening = false

		local function keyName(keyCode)
			if not keyCode then
				return "None"
			end
			local ok, name = pcall(function()
				return UserInputService:GetStringForKeyCode(keyCode)
			end)
			if ok and name and name ~= "" then
				return name
			end
			return keyCode.Name
		end

		local function render()
			keyLabel.Text = keyName(element.Value)
			if element.Value then
				keyLabel.TextColor3 = theme.AccentLight
			else
				keyLabel.TextColor3 = theme.SubText
			end
		end

		function element:Set(keyCode, silent)
			self.Value = keyCode
			render()
			if flag then
				Library.Flags[flag] = keyCode
			end
			if not silent then
				self.Changed:Fire(keyCode)
				if config.Callback then
					pcall(config.Callback, keyCode)
				end
			end
		end

		function element:Get()
			return self.Value
		end

		keyButton.MouseButton1Click:Connect(function()
			listening = true
			Library._Listening = true
			keyLabel.Text = "..."
			keyLabel.TextColor3 = theme.Accent
		end)

		track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if listening then
				if input.UserInputType == Enum.UserInputType.Keyboard then
					listening = false
					Library._Listening = false
					if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Escape then
						element:Set(nil)
					else
						element:Set(input.KeyCode)
					end
				elseif input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.MouseButton2 then
					listening = false
					Library._Listening = false
					render()
				end
				return
			end

			if gameProcessed then
				return
			end
			if Library._Listening then
				return
			end
			if element.Value and input.KeyCode == element.Value then
				element.Pressed:Fire()
				if config.OnPressed then
					pcall(config.OnPressed)
				end
			end
		end))

		register(flag, function()
			return element.Value
		end, function(value)
			element:Set(value, true)
		end)

		render()
		if flag then
			Library.Flags[flag] = element.Value
		end

		attachTooltip(element, container)
		return element
	end

	--=============================================================
	-- COLOR PICKER
	--=============================================================
	function sectionApi:AddColorPicker(config)
		config = config or {}
		local order = nextOrder()
		local flag = config.Flag or config.Name

		local container = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 6)

		local header = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = container,
		})

		new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Medium,
			Text = tostring(config.Text or config.Name or "Color"),
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -60, 1, 0),
			ZIndex = 8,
			Parent = container,
		})

		local swatch = new("Frame", {
			BackgroundColor3 = config.Default or Color3.fromRGB(168, 85, 247),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(40, 18),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ZIndex = 8,
			Parent = container,
		})
		corner(swatch, 4)
		stroke(swatch, theme.Outline, 1)

		local panel = new("Frame", {
			BackgroundColor3 = theme.Surface,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 168),
			Visible = false,
			LayoutOrder = order + 5,
			ZIndex = 30,
			Parent = section,
		})
		corner(panel, 6)
		stroke(panel, theme.Outline, 1)
		padding(panel, 10, 10, 10, 10)

		local sv = new("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 0, 0),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 100),
			ClipsDescendants = true,
			ZIndex = 31,
			Parent = panel,
		})
		corner(sv, 4)

		local whiteGradient = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 32,
			Parent = sv,
		})
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = whiteGradient,
		})

		local blackGradient = new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 33,
			Parent = sv,
		})
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Rotation = 90,
			Parent = blackGradient,
		})

		local svCursor = new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(10, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 34,
			Parent = sv,
		})
		corner(svCursor, 5)
		stroke(svCursor, Color3.new(1, 1, 1), 2)

		local hueBar = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 10),
			Position = UDim2.fromOffset(0, 110),
			ZIndex = 31,
			Parent = panel,
		})
		corner(hueBar, 3)
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0.000, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.167, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.333, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.500, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.667, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.833, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1.000, Color3.fromRGB(255, 0, 0)),
			}),
			Parent = hueBar,
		})

		local hueCursor = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 1, 4),
			Position = UDim2.new(0, 0, 0, -2),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 34,
			Parent = hueBar,
		})
		corner(hueCursor, 2)

		local hexBox = new("TextBox", {
			BackgroundColor3 = theme.Background,
			BorderSizePixel = 0,
			Font = Fonts.Regular,
			Text = "A855F7",
			PlaceholderText = "Hex",
			TextColor3 = theme.Text,
			TextSize = 11,
			ClearTextOnFocus = false,
			Position = UDim2.fromOffset(0, 130),
			Size = UDim2.new(1, -46, 0, 24),
			ZIndex = 31,
			Parent = panel,
		})
		corner(hexBox, 4)
		padding(hexBox, 0, 6, 0, 6)

		local preview = new("Frame", {
			BackgroundColor3 = config.Default or Color3.fromRGB(168, 85, 247),
			BorderSizePixel = 0,
			Position = UDim2.new(1, -40, 0, 130),
			Size = UDim2.fromOffset(40, 24),
			ZIndex = 31,
			Parent = panel,
		})
		corner(preview, 4)
		stroke(preview, theme.Outline, 1)

		local element = { Tooltip = config.Tooltip }
		element.Frame = container
		element.Value = config.Default or Color3.fromRGB(168, 85, 247)
		element.Changed = Signal.new()
		element.Open = false

		local hue, sat, val = Color3.toHSV(element.Value)

		local function toHex(color)
			return string.format(
				"%02X%02X%02X",
				math.floor(color.R * 255 + 0.5),
				math.floor(color.G * 255 + 0.5),
				math.floor(color.B * 255 + 0.5)
			)
		end

		local function render(silent)
			element.Value = Color3.fromHSV(hue, sat, val)
			swatch.BackgroundColor3 = element.Value
			preview.BackgroundColor3 = element.Value
			sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			svCursor.Position = UDim2.fromScale(sat, 1 - val)
			hueCursor.Position = UDim2.new(hue, 0, 0, -2)
			if not hexBox:IsFocused() then
				hexBox.Text = toHex(element.Value)
			end
			if flag then
				Library.Flags[flag] = element.Value
			end
		end

		function element:Set(color, silent)
			if typeof(color) ~= "Color3" then
				return
			end
			hue, sat, val = Color3.toHSV(color)
			render()
			if not silent then
				self.Changed:Fire(self.Value)
				if config.Callback then
					local ok, err = pcall(config.Callback, self.Value)
					if not ok then
						warn("[Lucifer] colorpicker callback: " .. tostring(err))
					end
				end
			end
		end

		function element:Get()
			return self.Value
		end

		function element:SetOpen(state)
			element.Open = state
			panel.Visible = state
		end

		local svDragging = false
		local hueDragging = false

		local function updateSV(x, y)
			sat = clamp((x - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
			val = 1 - clamp((y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
			render()
		end

		local function updateHue(x)
			hue = clamp((x - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
			render()
		end

		local function bindSV(obj)
			obj.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					svDragging = true
					updateSV(input.Position.X, input.Position.Y)
				end
			end)
		end

		local function bindHue(obj)
			obj.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					hueDragging = true
					updateHue(input.Position.X)
				end
			end)
		end

		bindSV(sv)
		bindSV(whiteGradient)
		bindSV(blackGradient)
		bindSV(svCursor)
		bindHue(hueBar)
		bindHue(hueCursor)

		track(UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if svDragging then
				updateSV(input.Position.X, input.Position.Y)
			elseif hueDragging then
				updateHue(input.Position.X)
			end
		end))

		track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if svDragging or hueDragging then
					svDragging = false
					hueDragging = false
					element:Set(element.Value)
				end
			end
		end))

		hexBox.FocusLost:Connect(function()
			local raw = string.gsub(hexBox.Text, "#", "")
			if #raw == 6 then
				local r = tonumber(string.sub(raw, 1, 2), 16)
				local g = tonumber(string.sub(raw, 3, 4), 16)
				local b = tonumber(string.sub(raw, 5, 6), 16)
				if r and g and b then
					element:Set(Color3.fromRGB(r, g, b))
					return
				end
			end
			hexBox.Text = toHex(element.Value)
		end)

		header.MouseButton1Click:Connect(function()
			element:SetOpen(not element.Open)
		end)

		register(flag, function()
			return element.Value
		end, function(value)
			element:Set(value, true)
		end)

		render(true)
		if flag then
			Library.Flags[flag] = element.Value
		end

		attachTooltip(element, container)
		return element
	end

	--=============================================================
	-- LABEL / PARAGRAPH / DIVIDER / SPACE / IMAGE
	--=============================================================
	function sectionApi:AddLabel(config)
		config = config or {}
		local order = nextOrder()

		local label = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Regular,
			Text = tostring(config.Text or config.Name or "Label"),
			TextColor3 = config.Color or theme.SubText,
			TextSize = config.Size or 12,
			TextWrapped = true,
			TextXAlignment = config.Align or Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})

		local element = {}
		element.Frame = label

		function element:SetText(text)
			label.Text = tostring(text)
		end

		function element:SetColor(color)
			label.TextColor3 = color
		end

		return element
	end

	function sectionApi:AddParagraph(config)
		config = config or {}
		local order = nextOrder()

		local container = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		new("UIListLayout", {
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = container,
		})

		if config.Title then
			new("TextLabel", {
				BackgroundTransparency = 1,
				Font = Fonts.Medium,
				Text = tostring(config.Title),
				TextColor3 = theme.Text,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				LayoutOrder = 1,
				ZIndex = 7,
				Parent = container,
			})
		end

		local body = new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Fonts.Regular,
			Text = tostring(config.Text or config.Content or ""),
			TextColor3 = theme.SubText,
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = 2,
			ZIndex = 7,
			Parent = container,
		})

		local element = {}
		element.Frame = container

		function element:SetText(text)
			body.Text = tostring(text)
		end

		return element
	end

	function sectionApi:AddDivider()
		local order = nextOrder()
		new("Frame", {
			BackgroundColor3 = theme.Outline,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		return {}
	end

	function sectionApi:AddSpace(height)
		local order = nextOrder()
		new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height or 6),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		return {}
	end

	function sectionApi:AddImage(config)
		config = config or {}
		local order = nextOrder()

		local frame = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, config.Height or 100),
			LayoutOrder = order,
			ClipsDescendants = true,
			ZIndex = 6,
			Parent = section,
		})
		corner(frame, 6)

		new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = tostring(config.Image or ""),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = frame,
		})

		return { Frame = frame }
	end

	--=============================================================
	-- SEARCH / FILTER helper for large option sets
	--=============================================================
	function sectionApi:AddSearchbox(config)
		config = config or {}
		local order = nextOrder()

		local container = new("Frame", {
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = order,
			ZIndex = 6,
			Parent = section,
		})
		corner(container, 6)

		local box = new("TextBox", {
			BackgroundTransparency = 1,
			Font = Fonts.Regular,
			Text = "",
			PlaceholderText = tostring(config.Placeholder or "Search..."),
			PlaceholderColor3 = theme.DimText,
			TextColor3 = theme.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
			Parent = container,
		})
		padding(box, 0, 10, 0, 10)

		local element = { Frame = container }
		element.Changed = Signal.new()

		box:GetPropertyChangedSignal("Text"):Connect(function()
			element.Changed:Fire(box.Text)
			if config.Callback then
				pcall(config.Callback, box.Text)
			end
		end)

		function element:Get()
			return box.Text
		end

		function element:Set(value)
			box.Text = tostring(value or "")
		end

		return element
	end

	return sectionApi
end

--=====================================================================
-- TAB METHODS
--=====================================================================

function TabProto:AddSection(title)
	return createSection(self, title)
end

function TabProto:SelectTab()
	local tab = self
	tab.Window.ActiveTab = tab
	for _, other in ipairs(tab.Window.Tabs) do
		other.Page.Visible = false
		other.Button.BackgroundTransparency = 1
		other.Label.TextColor3 = Library.Theme.SubText
		other.Indicator.Size = UDim2.new(0, 2, 0, 0)
	end
	tab.Page.Visible = true
	tab.Button.BackgroundTransparency = 0
	tab.Label.TextColor3 = Library.Theme.Text
	tab.Indicator.Size = UDim2.new(0, 2, 0, 16)
end

--=====================================================================
-- GLOBAL HELPERS
--=====================================================================

function Library:GetFlag(flag)
	return self.Flags[flag]
end

function Library:SetFlag(flag, value)
	local option = self.Options[flag]
	if option and option.Set then
		option.Set(value)
		return true
	end
	self.Flags[flag] = value
	return false
end

function Library:Destroy()
	for _, connection in ipairs(self.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	self.Connections = {}
	if self.NotificationHolder then
		self.NotificationHolder:Destroy()
		self.NotificationHolder = nil
	end
	if self.NotificationGui then
		self.NotificationGui:Destroy()
		self.NotificationGui = nil
	end
end

Library.Signal = Signal

return Library
