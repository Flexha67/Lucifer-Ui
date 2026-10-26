# Lucifer

A full-featured, single-file UI library for Roblox. Dark glass theme, purple accent, zero dependencies.

![Lucifer preview](docs/preview.svg)

```lua
local Lucifer = loadstring(game:HttpGet("https://raw.githubusercontent.com/Flexha67/Lucifer-Ui/refs/heads/main/Lucifer.lua"))()

local Window = Lucifer:CreateWindow({
    Title = "Lucifer",
    Subtitle = "v1.0.0",
    Size = UDim2.fromOffset(600, 440),
    ToggleKey = Enum.KeyCode.RightShift,
})
```

---

## Features

| | |
|---|---|
| **Single file** | One `Lucifer.lua`, no modules, no assets, no require chains |
| **Window** | Drag, resize, minimize, close, toggle key |
| **Tabs** | Sidebar navigation with animated indicator |
| **Sections** | Auto-sizing cards with accent header |
| **Components** | Button, Toggle, Slider, Dropdown, MultiDropdown, Input, Keybind, ColorPicker, Label, Paragraph, Divider, Space, Image, Searchbox |
| **Notifications** | Toast stack, 5 types, slide animation |
| **Tooltips** | Per-element hover tooltips |
| **Color picker** | SV square + hue bar + hex input, live preview |
| **Keybinds** | Click-to-capture, Esc/Backspace to clear, `OnPressed` callback |
| **Configs** | Save/load every flag to disk (or in-memory fallback) |
| **Theming** | Full palette override at runtime |
| **Signals** | Every component exposes `:OnChanged`-style `Changed` signal |

---

## Install

### Remote load

```lua
local Lucifer = loadstring(game:HttpGet("https://raw.githubusercontent.com/LostSky/Lucifer/main/Lucifer.lua"))()
```

### Local

Drop `Lucifer.lua` into your project and `require` it, or paste it into a LocalScript.

---

## Quick start

```lua
local Lucifer = loadstring(game:HttpGet("https://raw.githubusercontent.com/LostSky/Lucifer/main/Lucifer.lua"))()

local Window = Lucifer:CreateWindow({
    Title = "Lucifer",
    Subtitle = "v1.0.0",
})

local Main = Window:AddTab("Main")
local Visuals = Window:AddTab("Visuals")
local Settings = Window:AddTab("Settings")

local General = Main:AddSection("General")

General:AddButton({
    Text = "Click me",
    Callback = function()
        Lucifer:Notify({
            Title = "Lucifer",
            Content = "Button pressed",
            Type = "Success",
        })
    end,
})

General:AddToggle({
    Name = "Enabled",
    Flag = "enabled",
    Default = false,
    Callback = function(value)
        print("enabled:", value)
    end,
})

General:AddSlider({
    Name = "Speed",
    Flag = "speed",
    Min = 16,
    Max = 200,
    Default = 32,
    Decimals = 0,
    Callback = function(value)
        print("speed:", value)
    end,
})
```

---

## Components

Every component takes a config table. `Name` is the display label, `Flag` is the key used by the config system.

### Button

```lua
section:AddButton({
    Text = "Run",
    Tooltip = "optional hover text",
    Callback = function() end,
})
```

### Toggle

```lua
local toggle = section:AddToggle({
    Name = "Aimbot",
    Flag = "aimbot",
    Default = false,
    Callback = function(value) end,
})

toggle:Set(true)
print(toggle:Get())
```

### Slider

```lua
section:AddSlider({
    Name = "FOV",
    Flag = "fov",
    Min = 0,
    Max = 360,
    Default = 90,
    Decimals = 0,   -- 1 or 2 for floats
    Step = nil,     -- optional snap step, overrides Decimals
    Callback = function(value) end,
})
```

### Dropdown

```lua
section:AddDropdown({
    Name = "Mode",
    Flag = "mode",
    Options = { "Legit", "Rage", "Custom" },
    Default = "Legit",
    Callback = function(value) end,
})
```

### MultiDropdown

```lua
section:AddMultiDropdown({
    Name = "Targets",
    Flag = "targets",
    Options = { "Head", "Torso", "Limbs" },
    Default = { Head = true },
    Callback = function(value)
        -- value is a map: { Head = true, Torso = true }
        for option, selected in pairs(value) do
            print(option, selected)
        end
    end,
})
```

### Input

```lua
section:AddInput({
    Name = "Webhook",
    Flag = "webhook",
    Placeholder = "https://...",
    Default = "",
    Callback = function(text) end,
})
```

### Keybind

```lua
section:AddKeybind({
    Name = "Toggle UI",
    Flag = "ui_key",
    Default = Enum.KeyCode.RightShift,
    OnPressed = function() end,
})
```

Click the key button, then press any key. `Escape` or `Backspace` clears it.

### ColorPicker

```lua
section:AddColorPicker({
    Name = "Accent",
    Flag = "accent",
    Default = Color3.fromRGB(168, 85, 247),
    Callback = function(color) end,
})
```

### Label / Paragraph / Divider / Space / Image / Searchbox

```lua
section:AddLabel({ Text = "Plain text", Color = Color3.new(1, 1, 1), Size = 12 })

section:AddParagraph({
    Title = "Info",
    Content = "A longer body of text that wraps automatically.",
})

section:AddDivider()
section:AddSpace(8)

section:AddImage({
    Image = "rbxassetid://123456789",
    Height = 120,
})

local search = section:AddSearchbox({
    Placeholder = "Filter...",
    Callback = function(text) end,
})
```

---

## Notifications

```lua
Lucifer:Notify({
    Title = "Saved",
    Content = "Config written to disk",
    Type = "Success",   -- Success | Warning | Danger | Info | nil (accent)
    Duration = 4,       -- seconds
})

Lucifer:Notify("Shorthand works too")
```

---

## Config system

Flags are saved as a serialized Lua table. When an executor exposes `writefile` / `readfile`, configs persist to `Lucifer/<name>.cfg`. Otherwise they live in memory for the session.

```lua
Lucifer:SaveConfig("main")
Lucifer:LoadConfig("main")
Lucifer:ListConfigs()
Lucifer:DeleteConfig("main")
```

Wire it to UI:

```lua
local Config = Settings:AddSection("Config")

Config:AddInput({ Name = "Config name", Flag = "cfg_name", Default = "main" })

Config:AddButton({
    Text = "Save",
    Callback = function()
        Lucifer:SaveConfig(Lucifer:GetFlag("cfg_name"))
    end,
})

Config:AddButton({
    Text = "Load",
    Callback = function()
        Lucifer:LoadConfig(Lucifer:GetFlag("cfg_name"))
    end,
})
```

Serialization supports `number`, `string`, `boolean`, `Color3`, `EnumItem`, and tables of those.

---

## Flags

```lua
Lucifer:GetFlag("speed")        -- read
Lucifer:SetFlag("speed", 64)    -- write, fires the component callback
Lucifer.Flags                   -- raw table
```

---

## Theming

```lua
Lucifer:SetTheme({
    Accent = Color3.fromRGB(255, 64, 64),
    AccentLight = Color3.fromRGB(255, 120, 120),
    AccentDark = Color3.fromRGB(180, 40, 40),
    Background = Color3.fromRGB(10, 10, 12),
    Surface = Color3.fromRGB(16, 16, 20),
    SurfaceLight = Color3.fromRGB(24, 24, 30),
})
```

Call it before `CreateWindow` for the window chrome, or after for components created later. Full key list is in [`docs/API.md`](docs/API.md#theme).

---

## Window methods

```lua
Window:AddTab(name)
Window:SetTitle(text)
Window:Toggle()
Window:Show()
Window:Hide()
Window:SetMinimized(bool)
Window:Destroy()
```

---

## Repo layout

```
Lucifer/
├── Lucifer.lua            the whole library
├── examples/
│   ├── basic.lua          minimal working script
│   └── advanced.lua       every component, config panel, theming
├── docs/
│   ├── API.md             full reference
│   └── preview.svg        theme preview
├── LICENSE
└── README.md
```

---

## Notes

- Built for Roblox Luau. Uses `CoreGui` when available, falls back to `PlayerGui`.
- No external assets — everything is drawn with Frames, UICorner and UIStroke.
- `Lucifer:Destroy()` disconnects every tracked connection and tears down both GUIs.
- Elements are laid out with `UIListLayout` in `LayoutOrder` steps of 10; expanded panels (dropdown, color picker) slot in at `+5` so they open inline.

## License

MIT — see [LICENSE](LICENSE).
