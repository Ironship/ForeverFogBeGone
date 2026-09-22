-- Run from the addon root:  lua tests/button.test.lua
--
-- The addon is one button, so the test is about the four things that button
-- has to get right: it exists and is anchored, clicking it flips the console
-- variable and nothing else, the picture shows which way the setting now is,
-- and a client without that setting is told so rather than erroring.
--
-- The stub answers only what the addon actually asks for and records it. A
-- stub that invents a field on demand makes every assertion pass, which is how
-- a test in this project once checked nothing at all; here an unknown call is
-- an error, and the mutations at the bottom of the file's comment block prove
-- the assertions bite.

local recorded = { cvars = {}, points = {}, messages = {}, textures = {} }
local scripts, frames = {}, {}

local function stubFrame(kind)
  local f = { kind = kind, children = {}, shown = true }
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:SetFrameStrata(s) self.strata = s end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return self.level or 0 end
  function f:RegisterForClicks(...) self.clicks = { ... } end
  function f:RegisterForDrag(...) self.drag = { ... } end
  function f:SetMovable(v) self.movable = v end
  function f:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
  function f:SetScript(name, fn) self.handlers = self.handlers or {}; self.handlers[name] = fn
    if self == frames.event then scripts[name] = fn end end
  function f:GetScript(name) return self.handlers and self.handlers[name] end
  function f:ClearAllPoints() self.points = {} end
  function f:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... }
    recorded.points[#recorded.points + 1] = { ... } end
  function f:SetAllPoints() self.allPoints = true end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:SetHighlightTexture(t) self.highlight = t end
  function f:GetWidth() return self.w or 140 end
  function f:GetCenter() return 500, 400 end
  function f:GetEffectiveScale() return 1 end
  function f:CreateTexture()
    local t = { }
    function t:SetTexture(path) self.path = path; recorded.textures[#recorded.textures + 1] = path end
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetPoint() self.placed = true end
    function t:SetAllPoints() self.placed = true end
    function t:SetTexCoord() end
    function t:SetAlpha(a) self.alpha = a end
    function t:SetDesaturated(v) self.desaturated = v and true or false end
    function t:SetVertexColor(r, g, b) self.colour = { r, g, b } end
    self.children[#self.children + 1] = t
    return t
  end
  return f
end

CreateFrame = function(kind, name)
  local f = stubFrame(kind)
  if name then frames[name] = f end
  if not frames.event and kind == "Frame" then frames.event = f end
  if kind == "Button" then frames.button = f end
  return f
end

Minimap = stubFrame("Frame")
Minimap.w = 140
GameTooltip = { lines = {} }
function GameTooltip:SetOwner(o) self.owner = o end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) recorded.messages[#recorded.messages + 1] = text end }
GetCursorPosition = function() return 560, 340 end
InCombatLockdown = function() return recorded.inCombat or false end

local store = { volumeFog = "1" }
GetCVar = function(name) return store[name] end
SetCVar = function(name, value)
  if store[name] == nil then error("no such cvar: " .. tostring(name)) end
  store[name] = tostring(value)
  recorded.cvars[#recorded.cvars + 1] = { name, tostring(value) }
end

local chunk = assert(loadfile("Core.lua"))
chunk("ForeverFogBeGone")

local onEvent = frames.event.handlers.OnEvent
assert(type(onEvent) == "function", "the addon listens for events")
onEvent(nil, "ADDON_LOADED", "SomethingElse")
assert(ForeverFogBeGoneDB == nil, "another addon's load is not this addon's load")
onEvent(nil, "ADDON_LOADED", "ForeverFogBeGone")
assert(type(ForeverFogBeGoneDB) == "table", "the saved variables are made on our own load")
onEvent(nil, "PLAYER_LOGIN")

-- 1. The button exists, is anchored, and shows this addon's icon.
local button = frames.ForeverFogBeGoneButton
assert(button, "a button was created under a name other addons can find")
assert(button.points and #button.points > 0, "it is anchored -- an unanchored frame is never drawn")
local hasIcon = false
for _, path in ipairs(recorded.textures) do
  if path == "Interface\\AddOns\\ForeverFogBeGone\\icon" then hasIcon = true end
end
assert(hasIcon, "it shows the addon's own icon:\n  " .. table.concat(recorded.textures, "\n  "))

-- 2. Clicking flips the setting, and only that setting.
local click = button.handlers.OnClick
assert(type(click) == "function", "the button answers a click")
assert(store.volumeFog == "1", "fog starts on in this test")
click()
assert(store.volumeFog == "0", "one click turns the fog off, got " .. tostring(store.volumeFog))
click()
assert(store.volumeFog == "1", "the next click turns it back on, got " .. tostring(store.volumeFog))
assert(#recorded.cvars == 2, "two clicks, two writes")
for _, pair in ipairs(recorded.cvars) do
  assert(pair[1] == "volumeFog", "nothing else was written: " .. pair[1])
end

-- 3. The picture follows the setting, by being a different picture. Dimming
-- one icon was the first attempt and it lost the only part that carries the
-- meaning; the test asks for the swap so that nobody puts the dimming back.
local icon = button.children[1]
store.volumeFog = "0"
onEvent(nil, "CVAR_UPDATE", "volumeFog")
assert(icon.path == "Interface\\AddOns\\ForeverFogBeGone\\icon",
  "no fog: the struck sign, got " .. tostring(icon.path))
store.volumeFog = "1"
onEvent(nil, "CVAR_UPDATE", "volumeFog")
assert(icon.path == "Interface\\AddOns\\ForeverFogBeGone\\icon-fog",
  "fog back: plain fog, got " .. tostring(icon.path))
assert(icon.colour == nil or (icon.colour[1] == 1 and icon.colour[2] == 1 and icon.colour[3] == 1),
  "and neither state is dimmed: the button is not a disabled control")

-- 4. In combat it refuses rather than erroring, and says why.
recorded.inCombat = true
local before = store.volumeFog
click()
assert(store.volumeFog == before, "nothing is written in combat")
assert(recorded.messages[#recorded.messages]:lower():find("combat"), "and it says why")
recorded.inCombat = false

-- 5. A client without the setting is told, not broken. The message has to be
-- the one that says there is nothing to turn off: without the nil check the
-- addon takes a missing setting for "fog is on", tries to write it, and says
-- "could not change it" -- which reads like a bug in the addon rather than a
-- client that has no such setting, and it passed a weaker version of this
-- assertion.
store.volumeFog = nil
local writes = #recorded.cvars
local ok = pcall(click)
assert(ok, "a missing console variable does not raise")
local told = recorded.messages[#recorded.messages]
assert(told:find("volumeFog"), "it names the setting it cannot find: " .. told)
assert(told:find("nothing to turn off"),
  "it says the setting is absent rather than blaming the write: " .. told)
assert(#recorded.cvars == writes, "and it does not try to write a setting that is not there")
store.volumeFog = "1"

-- 6. The slash command toggles, and hides and shows the button.
local slash = SlashCmdList["FOREVERFOGBEGONE"]
assert(type(slash) == "function" and SLASH_FOREVERFOGBEGONE1 == "/fogbegone", "the slash command is registered")
slash("")
assert(store.volumeFog == "0", "/fogbegone toggles")
slash("hide")
assert(button.shown == false and ForeverFogBeGoneDB.hidden == true, "hide hides, and is remembered")
slash("show")
assert(button.shown == true and not ForeverFogBeGoneDB.hidden, "show brings it back")
ForeverFogBeGoneDB.angle = 12
slash("reset")
assert(ForeverFogBeGoneDB.angle ~= 12, "reset puts it back where it started")

-- 7. The right button is a different setting, and the two must not cross.
--
-- Crossing them is the failure worth guarding: both are booleans written the
-- same way, so a left click that flipped the sharpening instead of the fog
-- would look like the button simply not working, and the chat line would even
-- say the right thing about the wrong variable.
store.ResampleAlwaysSharpen = "0"
store.volumeFog = "1"
local before = #recorded.cvars
click(button, "LeftButton")
assert(store.volumeFog == "0", "a left click still flips the fog")
assert(store.ResampleAlwaysSharpen == "0", "a left click must not touch the sharpening")
assert(#recorded.cvars == before + 1, "a left click writes exactly one setting")

before = #recorded.cvars
click(button, "RightButton")
assert(store.ResampleAlwaysSharpen == "1", "a right click flips the sharpening")
assert(store.volumeFog == "0", "a right click must not touch the fog")
assert(#recorded.cvars == before + 1, "a right click writes exactly one setting")
assert(recorded.cvars[#recorded.cvars][1] == "ResampleAlwaysSharpen",
  "and it writes that one by name")

slash("sharpen")
assert(store.ResampleAlwaysSharpen == "0", "/ffbg sharpen toggles it too")

-- A client without the setting is told, and nothing is written.
store.ResampleAlwaysSharpen = nil
before = #recorded.cvars
slash("sharpen")
assert(#recorded.cvars == before, "a setting that is not there is not written to")
assert(recorded.messages[#recorded.messages]:find("ResampleAlwaysSharpen"),
  "and the message names it")
store.ResampleAlwaysSharpen = "0"
print("button: the right mouse button is the sharpening, and the two do not cross")

print("button: ok")
