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
-- CVar changes are deferred to prevent game freezes. On build 70009 of WoW
-- Forever, calling SetCVar during gameplay triggers "Render Settings Changed"
-- which exhausts the GPU descriptor heap on RTX 4090 and freezes the game.
-- Instead, clicks record what the player wants and apply it on the next fresh
-- login, before the world loads. PLAYER_ENTERING_WORLD with isInitialLogin=true
-- distinguishes a fresh login from a /reload (which keeps the world loaded).

local CVAR = "volumeFog"
-- The right mouse button's setting. Sharpening after the picture has been
-- resampled: it matters whenever the game is not rendering at the monitor's
-- own resolution, which is most of the time once render scale or an upscaler
-- is in play, and there is no tick box for it in the options.
local SHARPEN_CVAR = "ResampleAlwaysSharpen"
local DEFAULT_ANGLE = 198        -- lower left, clear of the tracking button and the clock
local ICON_CLEAR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icon"      -- fog struck through
local ICON_FOG   = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icon-fog"  -- fog, unstruck

-- math.atan2 is in Lua 5.1 and the client still has it, but it is deprecated
-- upstream and a client that drops it would take the button's drag with it and
-- nothing else, which is the kind of breakage that is noticed a month later.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local db
local button
local inWorld = false    -- tracks whether the world is currently loaded

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

local function fogIsOn()
  local value = getCVar(CVAR)
  if value == nil then return nil end       -- the client does not have this setting
  return value ~= "0" and value ~= 0
end

local function sharpenIsOn()
  local value = getCVar(SHARPEN_CVAR)
  if value == nil then return nil end
  return value ~= "0" and value ~= 0
end

local function say(text)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fc5f0ForeverFogBeGone:|r " .. text)
  end
end

local function logDiagnostic(event, cvar, value, detail1, detail2)
  -- Keep a diagnostic log for troubleshooting freezes. Entries include:
  -- time(), build info, what was requested, what was applied and when,
  -- and the value read back. A /ffbg log command prints the last ~50 entries.
  if not db then db = {} end
  if not db.diagnosticLog then db.diagnosticLog = {} end
  local log = db.diagnosticLog
  local entry = {
    time = time(),
    build = select(3, GetBuildInfo()),
    event = event,
    cvar = cvar,
    value = value,
    detail1 = detail1,
    detail2 = detail2,
  }
  table.insert(log, entry)
  -- Keep only the last 50 entries.
  if #log > 50 then
    table.remove(log, 1)
  end
end

local function printDiagnosticLog()
  if not db or not db.diagnosticLog or #db.diagnosticLog == 0 then
    say("diagnostic log is empty")
    return
  end
  say("diagnostic log (last " .. #db.diagnosticLog .. " entries):")
  for _, entry in ipairs(db.diagnosticLog) do
    local msg = string.format("[%s build %s] %s %s=%s",
      os.date("%H:%M:%S", entry.time), entry.build or "?", entry.event, entry.cvar or "?", entry.value or "?")
    if entry.detail1 then
      msg = msg .. " (" .. tostring(entry.detail1)
      if entry.detail2 then msg = msg .. ": " .. tostring(entry.detail2) end
      msg = msg .. ")"
    end
    say(msg)
  end
end

-- Two pictures, not one picture dimmed. The button shows the state it is in:
-- fog struck through when there is no fog, plain fog when there is.
--
-- The first version greyed the icon out instead, and seen in the game that
-- took the red stroke -- the only part of the drawing that carries the
-- meaning -- and turned it into a third grey bar. Beside Blizzard's own
-- saturated minimap buttons it read as a control that was switched off, which
-- is the wrong thing for a working button to say about itself.
--
-- If a wish is pending (a change requested while in the world), the button
-- shows the live state but is dimmed slightly to indicate a change is waiting.
local function refresh()
  if not button then return end
  local on = fogIsOn()
  if on == nil then
    -- No such setting on this client. Show the fog, unstruck, dimmed a little,
    -- and let the tooltip say why: there is nothing here to turn off.
    button.icon:SetTexture(ICON_FOG)
    button.icon:SetVertexColor(0.7, 0.7, 0.7)
    return
  end
  button.icon:SetTexture(on and ICON_FOG or ICON_CLEAR)
  -- Check if there is a pending wish for the fog.
  local pendingWish = db and db.wishes and db.wishes[CVAR]
  if pendingWish then
    -- Dim slightly to show a change is waiting for next login.
    button.icon:SetVertexColor(0.85, 0.85, 0.85)
  else
    button.icon:SetVertexColor(1, 1, 1)
  end
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

local function applyWish(cvar, value, whenWasRequested)
  -- Apply a single deferred wish. Returns true if successful.
  local ok, err = setCVar(cvar, value)
  if ok then
    logDiagnostic("applied", cvar, value, whenWasRequested)
    return true
  else
    logDiagnostic("failed", cvar, value, whenWasRequested, err)
    return false
  end
end

local function recordWish(cvar, value)
  -- Record what the player wants and show when it will take effect.
  if not db then db = {} end
  if not db.wishes then db.wishes = {} end
  db.wishes[cvar] = value
  logDiagnostic("wish", cvar, value)
end

local function toggle()
  local on = fogIsOn()
  if on == nil then
    say("this client has no |cffffd100" .. CVAR .. "|r setting, so there is nothing to turn off")
    return
  end
  local newValue = on and "0" or "1"
  -- Never call SetCVar while in the world. Record the wish and apply it at login.
  if inWorld then
    recordWish(CVAR, newValue)
    refresh()
    say(on and "volumetric fog |cff7fdc7foff|r (from the next login)" or "volumetric fog |cffdc7f7fback on|r (from the next login)")
  else
    -- Before the world is loaded or during a pure addon load, apply immediately.
    local ok, err = setCVar(CVAR, newValue)
    if not ok then
      say("could not change it: " .. tostring(err))
      return
    end
    refresh()
    say(on and "volumetric fog |cff7fdc7foff|r" or "volumetric fog |cffdc7f7fback on|r")
  end
end

local function toggleSharpen()
  local on = sharpenIsOn()
  if on == nil then
    say("this client has no |cffffd100" .. SHARPEN_CVAR .. "|r setting")
    return
  end
  local newValue = on and "0" or "1"
  -- Never call SetCVar while in the world. Record the wish and apply it at login.
  if inWorld then
    recordWish(SHARPEN_CVAR, newValue)
    say(on and "sharpening |cffdc7f7foff|r (from the next login)" or "sharpening |cff7fdc7fon|r (from the next login)")
  else
    -- Before the world is loaded or during a pure addon load, apply immediately.
    local ok, err = setCVar(SHARPEN_CVAR, newValue)
    if not ok then
      say("could not change it: " .. tostring(err))
      return
    end
    say(on and "sharpening |cffdc7f7foff|r" or "sharpening |cff7fdc7fon|r")
  end
end

local function applyNow(cvar)
  -- Emergency escape hatch: apply a pending wish immediately after a warning.
  -- This is only for cases where deferred application is not feasible.
  if not db or not db.wishes or not db.wishes[cvar] then
    say("no pending " .. cvar .. " change")
    return
  end
  say("|cffff7f00WARNING:|r applying " .. cvar .. " change immediately")
  local ok = applyWish(cvar, db.wishes[cvar], "now command")
  if ok then
    db.wishes[cvar] = nil
    refresh()
  end
end

-- Left for the fog, right for the sharpening. The icon keeps showing the fog
-- and only the fog: one picture cannot say two things, and the fog is the one
-- the addon is named after.
local function onClick(self, mouseButton)
  if mouseButton == "RightButton" then
    toggleSharpen()
  else
    toggle()
  end
end

local function tooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("ForeverFogBeGone!", 1, 1, 1)
  local on = fogIsOn()
  if on == nil then
    GameTooltip:AddLine("This client has no " .. CVAR .. " setting.", 1, 0.5, 0.5, true)
  else
    GameTooltip:AddLine(on and "Volumetric fog is |cffdc7f7fon|r."
                           or "Volumetric fog is |cff7fdc7foff|r.", nil, nil, nil, true)
    -- Check for pending wish and show when it will take effect.
    local pendingFogWish = db and db.wishes and db.wishes[CVAR]
    if pendingFogWish and pendingFogWish ~= (on and "1" or "0") then
      local willBe = (pendingFogWish == "0") and "off" or "on"
      GameTooltip:AddLine("Change to |cffffd100" .. willBe .. "|r pending (applies at next login).",
        1, 1, 0.5, true)
    else
      GameTooltip:AddLine(on and "Click to turn it off." or "Click to turn it back on.",
        0.7, 0.7, 0.7, true)
    end
  end
  local sharp = sharpenIsOn()
  if sharp ~= nil then
    GameTooltip:AddLine(sharp and "Sharpening is |cff7fdc7fon|r."
                            or "Sharpening is |cffdc7f7foff|r.", nil, nil, nil, true)
    -- Check for pending wish for sharpening.
    local pendingSharpenWish = db and db.wishes and db.wishes[SHARPEN_CVAR]
    if pendingSharpenWish and pendingSharpenWish ~= (sharp and "1" or "0") then
      local willBe = (pendingSharpenWish == "0") and "off" or "on"
      GameTooltip:AddLine("Change to |cffffd100" .. willBe .. "|r pending (applies at next login).",
        1, 1, 0.5, true)
    else
      GameTooltip:AddLine("Right-click to turn it " .. (sharp and "off." or "on."),
        0.7, 0.7, 0.7, true)
    end
  end
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- The graphics options can change the setting behind the addon's back, and the
-- button would then show the opposite of the truth until something else made
-- it redraw.
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    if type(ForeverFogBeGoneDB) ~= "table" then ForeverFogBeGoneDB = {} end
    db = ForeverFogBeGoneDB
    if tonumber(db.angle) == nil then db.angle = DEFAULT_ANGLE end
    logDiagnostic("addon_loaded")
  elseif event == "PLAYER_LOGIN" then
    build()
    logDiagnostic("player_login")
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- arg1 is isInitialLogin (true for fresh login), arg2 is isReloadingUi (true for /reload).
    -- We distinguish fresh login from /reload to know when it is safe to apply deferred changes.
    -- Fresh login: isInitialLogin=true, isReloadingUi=false (entering world for first time)
    -- /reload: isInitialLogin=false, isReloadingUi=true (still in same world session)
    -- Zone transition: isInitialLogin=false, isReloadingUi=false (still in same world session)
    --
    -- Apply pending wishes only on fresh login (isInitialLogin == true) before the
    -- world is fully loaded. We set inWorld=true after checking for wishes, so that
    -- clicks during that loading screen are deferred to the next login.
    if arg1 == true or arg1 == "1" then
      -- Fresh login: apply any pending wishes now, while the loading screen is visible
      -- but before the world is fully rendered.
      logDiagnostic("fresh_login")
      if db and db.wishes then
        for cvar, value in pairs(db.wishes) do
          applyWish(cvar, value, "fresh_login")
          -- Clear the wish after it is applied.
          db.wishes[cvar] = nil
        end
      end
    else
      -- /reload or zone transition: world stays loaded, do not apply wishes.
      logDiagnostic("world_transition")
    end
    -- Mark that we are now in the world. After this, clicks will defer changes.
    inWorld = true
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
    toggleSharpen()
  elseif command == "log" then
    printDiagnosticLog()
  elseif command == "now" then
    say("|cffff7f00Emergency escape hatch:|r use only if deferred application fails")
    -- Apply any pending fog wish immediately.
    if db and db.wishes and db.wishes[CVAR] then
      applyNow(CVAR)
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
    toggle()
  end
end
