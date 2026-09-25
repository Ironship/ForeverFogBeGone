-- Run from the addon root:  lua tests/button.test.lua
--
-- The addon is one button, so the test is about what that button has to get
-- right: it exists and is anchored, a click records a choice and writes
-- nothing, the picture shows the choice, and a client without the setting is
-- told so rather than erroring. And above all the write itself: on Forever
-- build 70009 changing the fog in the world froze the game, so the setting is
-- written only on the way out -- never on a click, never on a /reload, once
-- at a logout -- and checked at the next load.
--
-- The stub answers only what the addon actually asks for and records it. A
-- stub that invents a field on demand makes every assertion pass, which is how
-- a test in this project once checked nothing at all; here an unknown call is
-- an error, and each assertion below was proved by breaking Core.lua and
-- watching it fail.
--
-- A game restart is modelled by loading Core.lua again into the same stubs:
-- the saved variables table and the console settings carry over, as they do
-- on disk, and everything else starts from nothing.

local recorded = { cvars = {}, points = {}, messages = {}, textures = {}, reloads = 0 }
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
function GameTooltip:SetOwner(o) self.owner = o; self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) recorded.messages[#recorded.messages + 1] = text end }
GetCursorPosition = function() return 560, 340 end
InCombatLockdown = function() return recorded.inCombat or false end

-- The console settings: what Config.wtf gives the next start.
local store = { volumeFog = "1", ResampleAlwaysSharpen = "0" }
GetCVar = function(name) return store[name] end
SetCVar = function(name, value)
  if store[name] == nil then error("no such cvar: " .. tostring(name)) end
  store[name] = tostring(value)
  recorded.cvars[#recorded.cvars + 1] = { name, tostring(value) }
end
-- The shape the Forever client returns: version, build, date, interface.
GetBuildInfo = function() return "1.60.1", "70009", "Sep 23 2026", 16001 end
time = function() return os.time() end
date = function(fmt) return os.date(fmt) end

-- A post-hook, as the game's own does it: the original runs, then the hook.
hooksecurefunc = function(a, b, c)
  if type(a) == "table" then
    local original = a[b]
    a[b] = function(...) original(...); c(...) end
  else
    local original = _G[a]
    rawset(_G, a, function(...) original(...); b(...) end)
  end
end
local function plainReload() recorded.reloads = recorded.reloads + 1 end

-- The game's own slash-command table, which always exists. The addon may add a
-- key to it and must never assign the global itself: on the modern client that
-- taints it, and the next secure code to read it (the /run prompt, for one) is
-- blocked and blamed on the addon. Kept out of _G so an assignment is caught.
local gameSlashCmdList = {}
setmetatable(_G, {
  __index = function(_, key) if key == "SlashCmdList" then return gameSlashCmdList end end,
  __newindex = function(t, key, value)
    if key == "SlashCmdList" then error("the addon assigns the global SlashCmdList, which taints it", 2) end
    rawset(t, key, value)
  end,
})

local STRUCK = "Interface\\AddOns\\ForeverFogBeGone\\icon"
local FOG    = "Interface\\AddOns\\ForeverFogBeGone\\icon-fog"

local onEvent, button, slash, click, icon

-- One start of the game: a fresh Lua state, the saved variables and the
-- console settings as they were left.
local function start()
  for k in pairs(frames) do frames[k] = nil end
  gameSlashCmdList.FOREVERFOGBEGONE = nil
  rawset(_G, "ReloadUI", plainReload)
  rawset(_G, "C_UI", { Reload = plainReload })
  local chunk = assert(loadfile("Core.lua"))
  chunk("ForeverFogBeGone")
  onEvent = frames.event.handlers.OnEvent
  onEvent(nil, "ADDON_LOADED", "SomethingElse")
  onEvent(nil, "ADDON_LOADED", "ForeverFogBeGone")
  onEvent(nil, "PLAYER_LOGIN")
  button = frames.ForeverFogBeGoneButton
  slash = gameSlashCmdList.FOREVERFOGBEGONE
  click = button.handlers.OnClick
  icon = button.children[1]
end

local function last() return recorded.messages[#recorded.messages] or "" end
local function writes() return #recorded.cvars end
local function logHas(text)
  for _, line in ipairs(ForeverFogBeGoneDB.log or {}) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

-- 0. Loading. Another addon's load is not this one's, and the slash command
-- goes into the game's own table.
local chunk = assert(loadfile("Core.lua"))
chunk("ForeverFogBeGone")
assert(type(gameSlashCmdList.FOREVERFOGBEGONE) == "function", "the slash command is registered in the game's table")
frames.event.handlers.OnEvent(nil, "ADDON_LOADED", "SomethingElse")
assert(ForeverFogBeGoneDB == nil, "another addon's load is not this addon's load")
-- A leftover from a build that never shipped is cleared on load.
ForeverFogBeGoneDB = { angle = 12, diagnosticLog = { { event = "wish" } } }
start()
assert(ForeverFogBeGoneDB.diagnosticLog == nil, "the old log field is cleared")
assert(ForeverFogBeGoneDB.angle == 12, "and nothing else is touched")
ForeverFogBeGoneDB.angle = nil
start()

-- 1. The button exists, is anchored, and shows this addon's icon.
assert(button, "a button was created under a name other addons can find")
assert(button.points and #button.points > 0, "it is anchored -- an unanchored frame is never drawn")
assert(store.volumeFog == "1" and icon.path == FOG, "fog on: plain fog, got " .. tostring(icon.path))

-- 2. A click writes nothing. It records the choice, the picture follows the
-- choice at once, and the chat says when it will happen.
click(button, "LeftButton")
assert(writes() == 0, "a click writes nothing to the running game")
assert(store.volumeFog == "1", "the live setting is untouched")
assert(ForeverFogBeGoneDB.wishes and ForeverFogBeGoneDB.wishes.volumeFog == "0", "the choice is recorded")
assert(icon.path == STRUCK, "the picture shows the choice, got " .. tostring(icon.path))
assert(last():find("next start", 1, true) and last():find("log out or quit", 1, true),
  "the chat says when: " .. last())
assert(icon.colour and icon.colour[1] == 1 and icon.colour[2] == 1 and icon.colour[3] == 1,
  "neither state is dimmed: the button is not a disabled control")

-- 3. The tooltip tells the live state apart from the waiting one.
button.handlers.OnEnter(button)
local tip = table.concat(GameTooltip.lines, "\n")
assert(tip:find("Volumetric fog is", 1, true) and tip:find("From the next start", 1, true),
  "the tooltip shows what is live and what is waiting:\n" .. tip)

-- 4. A second click takes the choice back: nothing waits, nothing is written.
click(button, "LeftButton")
assert(writes() == 0, "still nothing written")
assert(ForeverFogBeGoneDB.wishes == nil, "nothing waits any more")
assert(icon.path == FOG, "the picture is back to the live state")
assert(last():find("stays", 1, true), "and the chat says it stays: " .. last())

-- 5. The right button is the sharpening, and the two must not cross. Crossing
-- them would look like the button simply not working, with a chat line about
-- the right setting and a change to the wrong one.
click(button, "RightButton")
assert(writes() == 0, "a right click writes nothing either")
assert(ForeverFogBeGoneDB.wishes.ResampleAlwaysSharpen == "1", "a right click records the sharpening")
assert(ForeverFogBeGoneDB.wishes.volumeFog == nil, "and not the fog")
assert(icon.path == FOG, "the picture says the fog and only the fog")
slash("sharpen")
assert(ForeverFogBeGoneDB.wishes == nil, "/ffbg sharpen toggles the same choice back")

-- 6. In combat a click still only records; there is nothing to refuse.
recorded.inCombat = true
click(button, "LeftButton")
assert(writes() == 0 and ForeverFogBeGoneDB.wishes.volumeFog == "0", "in combat the choice is recorded")
click(button, "LeftButton")
recorded.inCombat = false

-- 7. A client without the setting is told, not broken, and nothing waits for
-- a setting that is not there.
store.volumeFog = nil
local ok = pcall(click, button, "LeftButton")
assert(ok, "a missing console variable does not raise")
assert(last():find("volumeFog", 1, true) and last():find("nothing to turn off", 1, true),
  "it says the setting is absent: " .. last())
assert(ForeverFogBeGoneDB.wishes == nil, "and records nothing")
store.volumeFog = "1"

-- 8. A /reload writes nothing: it keeps the world loaded, and PLAYER_LOGOUT
-- fires for it all the same. Both ways into a reload are covered.
click(button, "LeftButton")
ReloadUI()
onEvent(nil, "PLAYER_LOGOUT")
assert(recorded.reloads == 1, "the hook leaves the reload itself alone")
assert(writes() == 0, "a /reload writes nothing")
assert(ForeverFogBeGoneDB.lastExit == "reload", "and is remembered as a reload")
start()
assert(ForeverFogBeGoneDB.wishes and ForeverFogBeGoneDB.wishes.volumeFog == "0", "the choice survives the reload")
assert(icon.path == STRUCK, "and the picture still shows it")
assert(not last():find("did not change", 1, true), "a reload is not reported as a failed write")
C_UI.Reload()
onEvent(nil, "PLAYER_LOGOUT")
assert(writes() == 0, "a reload through C_UI.Reload writes nothing either")
start()

-- 9. A logout writes the choice, once, by name.
onEvent(nil, "PLAYER_LOGOUT")
assert(writes() == 1, "a logout writes exactly one setting, got " .. writes())
assert(recorded.cvars[1][1] == "volumeFog" and recorded.cvars[1][2] == "0", "the fog, to off")
assert(ForeverFogBeGoneDB.lastExit == "logout", "and is remembered as a logout")
assert(logHas("set volumeFog=0 at logout"), "and logged")

-- 10. The next start has it. The choice is dropped, the chat says so once,
-- and the log keeps the build beside it.
start()
assert(ForeverFogBeGoneDB.wishes == nil, "a choice the game has is dropped")
assert(ForeverFogBeGoneDB.lastExit == nil, "the exit is forgotten once read")
assert(last():find("as you chose", 1, true), "the chat says it took: " .. last())
assert(logHas("took effect: volumeFog=0") and logHas(" b70009 "), "the log says so, with the build")
assert(icon.path == STRUCK, "the fog is off and the picture says so")
onEvent(nil, "PLAYER_LOGOUT")
assert(writes() == 1, "with nothing waiting, a logout writes nothing")

-- 11. A logout whose write did not stick is noticed, kept and written again.
start()
click(button, "LeftButton")           -- fog back on, from the next start
onEvent(nil, "PLAYER_LOGOUT")
assert(writes() == 2 and store.volumeFog == "1", "the logout wrote it")
store.volumeFog = "0"                  -- but the next start does not have it
start()
assert(ForeverFogBeGoneDB.wishes and ForeverFogBeGoneDB.wishes.volumeFog == "1", "the choice is kept")
assert(last():find("did not change", 1, true) and last():find("cancel", 1, true),
  "and the chat says it did not stick, and how to cancel it: " .. last())
assert(logHas("did not take effect: volumeFog is 0, wanted 1"), "and the log says what it found")
onEvent(nil, "PLAYER_LOGOUT")
assert(writes() == 3 and store.volumeFog == "1", "the next logout writes it again")
start()
assert(ForeverFogBeGoneDB.wishes == nil and icon.path == FOG, "and then it holds")

-- 12. /ffbg now explains and writes nothing; /ffbg now! writes. Nothing
-- waiting, nothing to do; in combat the write is refused and the choice kept.
slash("now")
assert(last():find("nothing is waiting", 1, true), "nothing waiting: " .. last())
click(button, "LeftButton")
slash("now")
assert(writes() == 3, "/ffbg now alone writes nothing")
assert(last():find("/ffbg now!", 1, true), "it says how to do it anyway: " .. last())
recorded.inCombat = true
slash("now!")
assert(writes() == 3 and ForeverFogBeGoneDB.wishes.volumeFog == "0", "in combat /ffbg now! is refused and the choice kept")
assert(last():find("combat", 1, true), "and it says why: " .. last())
recorded.inCombat = false
slash("now!")
assert(writes() == 4 and store.volumeFog == "0", "/ffbg now! writes it")
assert(ForeverFogBeGoneDB.wishes == nil and icon.path == STRUCK, "and nothing waits after")

-- 13. The log prints.
recorded.messages = {}
slash("log")
assert(#recorded.messages > 3, "/ffbg log prints the lines")

-- 14. The picture follows the live setting when the graphics options change
-- it and nothing is waiting.
store.volumeFog = "1"
onEvent(nil, "CVAR_UPDATE", "volumeFog")
assert(icon.path == FOG, "the options turned the fog on: plain fog")

-- 15. The other slash commands.
slash("")
assert(writes() == 4 and ForeverFogBeGoneDB.wishes.volumeFog == "0", "/ffbg records the fog like a click")
slash("")
slash("hide")
assert(button.shown == false and ForeverFogBeGoneDB.hidden == true, "hide hides, and is remembered")
slash("show")
assert(button.shown == true and not ForeverFogBeGoneDB.hidden, "show brings it back")
ForeverFogBeGoneDB.angle = 12
slash("reset")
assert(ForeverFogBeGoneDB.angle ~= 12, "reset puts it back where it started")
assert(SLASH_FOREVERFOGBEGONE1 == "/fogbegone" and SLASH_FOREVERFOGBEGONE2 == "/ffbg", "both names")

-- Every write in this file happened at a logout or on /ffbg now!.
for _, pair in ipairs(recorded.cvars) do
  assert(pair[1] == "volumeFog", "only the fog was ever written here: " .. pair[1])
end

print("button: ok")
