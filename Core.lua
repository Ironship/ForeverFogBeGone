local ADDON_NAME = ...

-- One button on the minimap that turns the volumetric fog off, and on again.
--
-- The whole addon. It exists because `/console volumeFog 0` is the difference
-- between seeing a zone and looking at soup, and typing it every session --
-- and again after every wipe of the console settings -- is the sort of small
-- friction that is worth a button.
--
-- The button is drawn here rather than through LibDBIcon. That library would
-- be four files and a dependency for one icon, and this addon is one icon.
--
-- The button never changes the setting while you play. It records what you
-- chose, and the choice is written when you log out or quit, so the game
-- starts with it next time. That is not caution for its own sake. On Forever
-- build 1.60.1.70009 (September 2026) a click that turned the fog on in the
-- world froze the game until it was closed: the client's gx.log shows "Render
-- Settings Changed", then "OutOfMemory: AllocDescriptors Failed", a lost
-- device, and a recovery that failed the same way. The same clicks had worked
-- for days on the build before. What never froze was a game that started with
-- the setting already in Config.wtf, and the client writes Config.wtf on the
-- way out -- even in that broken state it shut down cleanly and saved. So the
-- way out is where the setting is set.
--
-- The world is still loaded when PLAYER_LOGOUT fires, so the write can still
-- hang the way out, once. It is the better place all the same: the game is
-- leaving anyway, the client saves on shutdown even then, and the next start
-- has the setting.

local CVAR = "volumeFog"
-- The right mouse button's setting. Sharpening after the picture has been
-- resampled: it matters whenever the game is not rendering at the monitor's
-- own resolution, which is most of the time once render scale or an upscaler
-- is in play, and there is no tick box for it in the options. It is a render
-- setting too, so it waits for the way out like the fog does.
local SHARPEN_CVAR = "ResampleAlwaysSharpen"
local LABEL = { [CVAR] = "volumetric fog", [SHARPEN_CVAR] = "sharpening" }
local DEFAULT_ANGLE = 198        -- lower left, clear of the tracking button and the clock
local ICON_CLEAR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icon"      -- fog struck through
local ICON_FOG   = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icon-fog"  -- fog, unstruck
local LOG_SIZE = 50

-- math.atan2 is in Lua 5.1 and the client still has it, but it is deprecated
-- upstream and a client that drops it would take the button's drag with it and
-- nothing else, which is the kind of breakage that is noticed a month later.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local db
local button
-- Set when this session asks for a UI reload. PLAYER_LOGOUT fires on a
-- /reload as well, and a reload keeps the world loaded -- the one time the
-- setting must not be written.
local reloading = false
-- What the load found out about the last change, said once the chat is up.
local greetings = {}

-- The CVar accessors moved namespace; both names exist on some clients and one
-- on others, so neither is assumed.
local function getCVar(name)
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  return get and get(name) or nil
end

local function setCVar(name, value)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  if not set then return false, "this client has no way to set a console variable" end
  -- Protected in combat on some builds, and a graphics setting is never worth
  -- an error in the middle of a fight.
  if InCombatLockdown and InCombatLockdown() then
    return false, "not while you are in combat -- try again afterwards"
  end
  local ok, err = pcall(set, name, value)
  if not ok then return false, tostring(err) end
  return true
end

local function isOn(value)
  return value ~= nil and value ~= "0" and value ~= 0
end

-- Fog on is the bad news and reads red; sharpening on is the good news.
local function stateText(name, on)
  if (name == SHARPEN_CVAR) == (on and true or false) then
    return on and "|cff7fdc7fon|r" or "|cff7fdc7foff|r"
  end
  return on and "|cffdc7f7fon|r" or "|cffdc7f7foff|r"
end

local function say(text)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fc5f0ForeverFogBeGone:|r " .. text)
  end
end

-- A few lines kept in the saved variables, so the next freeze -- or the next
-- change that does not stick -- can be laid beside the client's own logs.
-- Each line carries the build, because the build is what decided all this.
local function note(text)
  if not db then return end
  if type(db.log) ~= "table" then db.log = {} end
  local _, build = GetBuildInfo()
  local stamp = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or "")
  db.log[#db.log + 1] = stamp .. " b" .. tostring(build or "?") .. " " .. text
  while #db.log > LOG_SIZE do table.remove(db.log, 1) end
end

local function waiting(name)
  local list = db and db.wishes
  return type(list) == "table" and list[name] or nil
end

-- What the player will have from the next start: the waiting choice if there
-- is one, the live setting otherwise. nil when the client has no such setting.
local function chosen(name)
  local live = getCVar(name)
  if live == nil then return nil end
  local wish = waiting(name)
  if wish ~= nil then return isOn(wish) end
  return isOn(live)
end

local function pending(name)
  local wish, live = waiting(name), getCVar(name)
  return wish ~= nil and live ~= nil and isOn(wish) ~= isOn(live)
end

-- Two pictures, not one picture dimmed. The button shows the fog you chose:
-- struck through when there will be none, plain fog when there will be. The
-- choice rather than the live setting, so a click changes the picture at once,
-- which is what a button is expected to do; the tooltip says when it happens.
--
-- The first version greyed the icon out instead, and seen in the game that
-- took the red stroke -- the only part of the drawing that carries the
-- meaning -- and turned it into a third grey bar. Beside Blizzard's own
-- saturated minimap buttons it read as a control that was switched off, which
-- is the wrong thing for a working button to say about itself.
local function refresh()
  if not button then return end
  local on = chosen(CVAR)
  if on == nil then
    -- No such setting on this client. Show the fog, unstruck, dimmed a little,
    -- and let the tooltip say why: there is nothing here to turn off.
    button.icon:SetTexture(ICON_FOG)
    button.icon:SetVertexColor(0.7, 0.7, 0.7)
    return
  end
  button.icon:SetTexture(on and ICON_FOG or ICON_CLEAR)
  button.icon:SetVertexColor(1, 1, 1)
end

local function position()
  if not button or not Minimap then return end
  local angle = math.rad(tonumber(db and db.angle) or DEFAULT_ANGLE)
  local radius = (Minimap:GetWidth() / 2) + 8
  button:ClearAllPoints()
  -- Frames that are never given a point are never drawn, and raise nothing.
  button:SetPoint("CENTER", Minimap, "CENTER",
    math.cos(angle) * radius, math.sin(angle) * radius)
end

-- A click. Nothing is written to the game here; see the top of the file.
local function request(name)
  local live = getCVar(name)
  if live == nil then
    say("this client has no |cffffd100" .. name .. "|r setting"
      .. (name == CVAR and ", so there is nothing to turn off" or ""))
    return
  end
  local target = not chosen(name)
  if type(db.wishes) ~= "table" then db.wishes = {} end
  if target == isOn(live) then
    -- Back to what the game already has: nothing is waiting any more.
    db.wishes[name] = nil
    if next(db.wishes) == nil then db.wishes = nil end
    note("cancel " .. name .. ", stays " .. tostring(live))
    say(LABEL[name] .. " stays " .. stateText(name, target) .. " -- nothing to change")
  else
    db.wishes[name] = target and "1" or "0"
    note("want " .. name .. "=" .. db.wishes[name] .. ", live " .. tostring(live))
    say(LABEL[name] .. " " .. stateText(name, target) .. " from the next start of the game."
      .. " It is saved when you log out or quit: changing it while you play"
      .. " freezes this version of Forever.")
  end
  refresh()
end

-- Writes every waiting choice that differs from the live setting, and returns
-- a line for each, for the log and, when asked for by hand, for the chat.
local function write(when)
  local lines = {}
  if type(db.wishes) ~= "table" then return lines end
  for name, value in pairs(db.wishes) do
    local live = getCVar(name)
    if live == nil then
      db.wishes[name] = nil
    elseif isOn(live) ~= isOn(value) then
      local ok, err = setCVar(name, value)
      local line = (ok and "set " or "could not set ") .. name .. "=" .. value
        .. " at " .. when .. (ok and "" or (": " .. tostring(err)))
      note(line)
      lines[#lines + 1] = line
    end
  end
  return lines
end

-- Drops the choices the game already has.
local function settle()
  if type(db.wishes) ~= "table" then db.wishes = nil; return end
  for name, value in pairs(db.wishes) do
    local live = getCVar(name)
    if live == nil or isOn(live) == isOn(value) then db.wishes[name] = nil end
  end
  if next(db.wishes) == nil then db.wishes = nil end
end

-- On load: did the last change stick? A choice the game now has is dropped
-- and announced. One that a real logout should have written and did not is
-- kept, logged and announced, and is written again at the next one.
local function check()
  if type(db.wishes) ~= "table" then db.wishes = nil; return end
  for name, value in pairs(db.wishes) do
    local live = getCVar(name)
    if live ~= nil and isOn(live) == isOn(value) then
      note("took effect: " .. name .. "=" .. tostring(live))
      greetings[#greetings + 1] = LABEL[name] .. " is " .. stateText(name, isOn(live)) .. " now, as you chose"
    elseif live ~= nil and db.lastExit == "logout" then
      note("did not take effect: " .. name .. " is " .. tostring(live) .. ", wanted " .. value)
      greetings[#greetings + 1] = LABEL[name] .. " did not change at the last logout;"
        .. " it will be written again at the next one, or click the button to"
        .. " cancel it (|cffffd100/ffbg log|r)"
    end
  end
  settle()
end

-- Left for the fog, right for the sharpening. The icon keeps showing the fog
-- and only the fog: one picture cannot say two things, and the fog is the one
-- the addon is named after.
local function onClick(self, mouseButton)
  if mouseButton == "RightButton" then
    request(SHARPEN_CVAR)
  else
    request(CVAR)
  end
end

local function tooltipFor(name, verb)
  local live = getCVar(name)
  if live == nil then return false end
  local label = LABEL[name]:gsub("^%l", string.upper)
  GameTooltip:AddLine(label .. " is " .. stateText(name, isOn(live)) .. ".", nil, nil, nil, true)
  if pending(name) then
    GameTooltip:AddLine("From the next start: " .. stateText(name, chosen(name))
      .. ". It is saved when you log out or quit.", 1, 0.82, 0, true)
  end
  GameTooltip:AddLine(verb .. " to turn it " .. (chosen(name) and "off" or "on")
    .. " from the next start.", 0.7, 0.7, 0.7, true)
  return true
end

local function tooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("ForeverFogBeGone!", 1, 1, 1)
  if not tooltipFor(CVAR, "Click") then
    GameTooltip:AddLine("This client has no " .. CVAR .. " setting.", 1, 0.5, 0.5, true)
  end
  tooltipFor(SHARPEN_CVAR, "Right-click")
  GameTooltip:AddLine("Drag to move around the minimap.", 0.5, 0.5, 0.5, true)
  GameTooltip:Show()
end

local function onDrag(self)
  if not Minimap then return end
  local cx, cy = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not cx or not scale or scale == 0 then return end
  db.angle = math.deg(atan2(py / scale - cy, px / scale - cx)) % 360
  position()
end

local function build()
  if button or not Minimap then return end
  button = CreateFrame("Button", "ForeverFogBeGoneButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON_CLEAR)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", button, "CENTER", 0, 1)
  -- Trim the artwork edges beneath the minimap border.
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", tooltip)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDrag) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  position()
  refresh()
  if db.hidden then button:Hide() end
end

-- A reload has to be recognised before PLAYER_LOGOUT, which it also fires.
-- The slash command, the AddOns list and other addons reach it through one of
-- these two names, so both are hooked; a post-hook leaves the call itself
-- alone. `/console reloadui` goes round both and would still write the
-- setting into the loaded world; nothing else is known to.
local function markReload() reloading = true end
if hooksecurefunc then
  if type(ReloadUI) == "function" then hooksecurefunc("ReloadUI", markReload) end
  if type(C_UI) == "table" and type(C_UI.Reload) == "function" then
    hooksecurefunc(C_UI, "Reload", markReload)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
-- The graphics options can change the setting behind the addon's back, and the
-- button would then show the opposite of the truth until something else made
-- it redraw.
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    if type(ForeverFogBeGoneDB) ~= "table" then ForeverFogBeGoneDB = {} end
    db = ForeverFogBeGoneDB
    if tonumber(db.angle) == nil then db.angle = DEFAULT_ANGLE end
    -- A log under another name, from a build that was on GitHub for an hour.
    db.diagnosticLog = nil
    check()
    db.lastExit = nil
  elseif event == "PLAYER_LOGIN" then
    build()
    for _, text in ipairs(greetings) do say(text) end
    greetings = {}
  elseif event == "PLAYER_LOGOUT" then
    if not db then return end
    if reloading then
      db.lastExit = "reload"
    else
      db.lastExit = "logout"
      write("logout")
    end
  elseif event == "CVAR_UPDATE" then
    -- arg1 is the variable's name on most builds and its display name on some,
    -- so the comparison is loose and a needless redraw costs nothing.
    -- Only the fog changes the picture, so only the fog has to redraw it.
    if button and (arg1 == nil or tostring(arg1):lower():find("fog")) then refresh() end
  end
end)

SLASH_FOREVERFOGBEGONE1 = "/fogbegone"
SLASH_FOREVERFOGBEGONE2 = "/ffbg"
-- Only a key of the game's own table is written. Assigning the global itself
-- ("SlashCmdList = SlashCmdList or {}") taints it, and the next secure code to
-- read it is blocked and blamed on this addon.
SlashCmdList["FOREVERFOGBEGONE"] = function(input)
  local command = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if command == "show" then
    db.hidden = nil
    if button then button:Show() end
    say("button shown")
  elseif command == "hide" then
    db.hidden = true
    if button then button:Hide() end
    say("button hidden -- |cffffd100/ffbg show|r brings it back, |cffffd100/ffbg|r still toggles the fog")
  elseif command == "sharpen" then
    request(SHARPEN_CVAR)
  elseif command == "log" then
    if type(db.log) ~= "table" or #db.log == 0 then
      say("nothing logged yet")
      return
    end
    for _, line in ipairs(db.log) do say(line) end
  elseif command == "now" or command == "now!" then
    -- For a client where writing it in the world is safe again. Never the
    -- default, and it takes a second, deliberate word to do it.
    if not (pending(CVAR) or pending(SHARPEN_CVAR)) then
      say("nothing is waiting")
    elseif command == "now" then
      say("this writes the waiting change into the running game. On Forever"
        .. " 1.60.1.70009 that froze the game until it was closed."
        .. " Type |cffffd100/ffbg now!|r to do it anyway.")
    else
      local lines = write("now")
      for _, line in ipairs(lines) do say(line) end
      settle()
      refresh()
    end
  elseif command:match("^cvars") then
    -- What else is there? Nothing on disk knows: Config.wtf holds only the
    -- settings somebody has already changed. The client knows the whole list
    -- and this asks it.
    local filter = command:match("^cvars%s+(.+)$")
    local all = C_Console and C_Console.GetAllCommands and C_Console.GetAllCommands()
    if type(all) ~= "table" then
      say("this client will not list its console variables")
      return
    end
    local shown = 0
    for _, entry in ipairs(all) do
      local name = entry and entry.command
      if type(name) == "string" and (not filter or name:lower():find(filter, 1, true)) then
        -- commandType 0 is a variable; anything else is a command, which has
        -- no value to read and nothing to put on a button.
        if entry.commandType == nil or entry.commandType == 0 then
          shown = shown + 1
          if shown <= 40 then
            say(("|cffffd100%s|r = %s  %s"):format(
              name, tostring(getCVar(name)), tostring(entry.help or "")))
          end
        end
      end
    end
    if shown == 0 then
      say("nothing matches " .. tostring(filter))
    elseif shown > 40 then
      say(("...and %d more -- narrow it with |cffffd100/ffbg cvars <text>|r"):format(shown - 40))
    end
  elseif command == "reset" then
    db.angle = DEFAULT_ANGLE
    db.hidden = nil
    if button then button:Show() end
    position()
    say("button back where it started")
  else
    request(CVAR)
  end
end
