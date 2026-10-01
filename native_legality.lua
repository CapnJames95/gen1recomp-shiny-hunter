-- Shared FRLG compatibility corrections. Identical copy shipped in each caller.
-- No existing Pokemon are rerolled; generation changes apply to new records only.
local Fix = {}
function Fix.install(mod)
  local Runtime = require('src.mods.Runtime')
  local Version = require('src.core.GameVersion')
  local Codec = require('src.save_convert.Gen3Save')
  local Pokemon = require('src.core.game3.pokemon')
  local state = Codec.__frlgNativeLegality
  if not state then
    state = { owners = {}, wrappers = {} }
    Codec.__frlgNativeLegality = state
  end
  if state.owner ~= Runtime.events then state.owner = Runtime.events; state.owners = {} end
  local id = mod.id or tostring(mod)
  state.owners[id] = function()
    return (not mod.find or mod.find(mod.id) ~= nil)
      and (not mod.options or mod.options:get('enabled') ~= false)
  end
  local function active()
    local v = Version.get()
    if (v ~= 'firered' and v ~= 'leafgreen') or Runtime.events ~= state.owner then return false end
    for _, enabled in pairs(state.owners) do if enabled() then return true end end
    return false
  end
  local function wrap(target, name, key, handler)
    local record = state.wrappers[key]
    if not record then
      record = { previous = assert(target[name], 'Missing FRLG API: '..name) }
      state.wrappers[key] = record
      target[name] = function(...)
        if record.active() then return record.handler(record.previous, ...) end
        return record.previous(...)
      end
    end
    record.active, record.handler = active, handler
  end
  local function abilitySlot(mon)
    local species = mon.species or mon.speciesId
    local abilities = Pokemon.abilities(species)
    if type(abilities) ~= 'table' or not abilities[1] then return nil end
    return (tonumber(abilities[2]) or 0) == 0 and 0 or (mon.personality or 0) % 2
  end
  wrap(Codec, 'fromPortMon', 'fromPortMon', function(previous, mon, ...)
    local result = previous(mon, ...)
    -- Explicit/imported slots and event bytes remain authoritative.
    if mon.abilityNum == nil then
      local slot = abilitySlot({species=result.species, personality=result.personality})
      if slot ~= nil then result.abilityNum = slot end
    end
    if mon.isEgg and not mon.cartExtra and not mon.eventDistribution and not mon.autoBreederOrigin then
      result._frlgNativeEggPadding = true
    end
    return result
  end)
  wrap(Codec, 'encodeBoxMon', 'encodeBoxMon', function(previous, mon, ...)
    local bytes = previous(mon, ...)
    if mon._frlgNativeEggPadding then
      local layout = require('src.save_convert.Gen3Layout').BOX_MON
      local offset, length = layout.otName, layout.otNameLength
      bytes = bytes:sub(1, offset) .. Codec.encodeString(mon.otName, length, 255) .. bytes:sub(offset + length + 1)
    end
    return bytes
  end)
  local Party = require('src.core.game3.party')
  wrap(Party, 'giveMon', 'giveMon', function(previous, ...)
    local ok, code, mon, box, slot = previous(...)
    if ok and mon and mon.abilityNum == nil then mon.abilityNum = abilitySlot(mon) end
    return ok, code, mon, box, slot
  end)
  wrap(Party, 'giveEgg', 'giveEgg', function(previous, ...)
    local ok, code, mon, box, slot = previous(...)
    if ok and mon then require('src.core.game3.breeding').applyEggData(mon, true) end
    return ok, code, mon, box, slot
  end)
  -- Breeding replaces the initial gift PID; recompute its ability slot afterwards.
  local Breeding = require('src.core.game3.breeding')
  wrap(Breeding, 'setInitialEggData', 'setInitialEggData', function(previous, ...)
    local mon = previous(...)
    if mon then mon.abilityNum = abilitySlot(mon) end
    return mon
  end)
  wrap(Breeding, 'createEgg', 'createEgg', function(previous, ...)
    local mon = previous(...)
    if mon then mon.abilityNum = abilitySlot(mon) end
    return mon
  end)
  local Catching = require('src.core.game3.battle.catching')
  wrap(Catching, 'storeCaught', 'storeCaught', function(previous, ...)
    local result = previous(...)
    if result and result.mon and result.mon.abilityNum == nil then result.mon.abilityNum = abilitySlot(result.mon) end
    return result
  end)
  local Roamer = require('src.core.game3.roamer')
  wrap(Roamer, 'generateMon', 'generateRoamer', function(_, species, level)
    local Rng = require('src.core.game3.rng')
    local pid = Rng.Random32()
    local iv1 = Rng.Random(); Rng.Random() -- retail generation consumes both IV words
    -- Retail FRLG stores just eight IV bits for roamers (HP 0..31, Attack 0..7).
    local mon = {species=species,speciesId=species,level=level or Roamer.ROAMER_LEVEL,
      personality=pid,pid=pid,ivs={hp=iv1%32,atk=math.floor(iv1/32)%8,def=0,spe=0,spa=0,spd=0},
      evs={hp=0,atk=0,def=0,spe=0,spa=0,spd=0},status=0,statusNum=0}
    mon.moves, mon.pp, mon.maxPp = Pokemon.movesAtLevel(species, mon.level)
    mon.abilityNum = abilitySlot(mon)
    Pokemon.applyStats(mon); mon.hp = mon.maxHp
    return mon
  end)
  wrap(Roamer, 'tryEncounter', 'roamerEncounter', function(previous, ...)
    local encounter = previous(...)
    -- Host stores pid but its battle factory consumes personality.
    if encounter and encounter.foe and encounter.foe.personality == nil then
      encounter.foe.personality = encounter.foe.pid
    end
    if encounter and encounter.foe then
      -- The host bridge passes the outer descriptor directly to Battle.start.
      for _, key in ipairs({'personality','ivs','hp','maxHp','status','statusNum','moves','pp'}) do
        if encounter[key] == nil then encounter[key] = encounter.foe[key] end
      end
    end
    return encounter
  end)
  local Trade = require('src.core.game3.scripting.natives_trade')
  wrap(Trade, 'createTradeMon', 'createTradeMon', function(previous, index, ...)
    local mon = previous(index, ...)
    local entry = mon and Trade.entry(tonumber(index) or -1)
    if entry then
      mon.abilityNum = entry.abilityNum
      mon.otId = entry.otId % 65536; mon.otSecretId = math.floor(entry.otId / 65536)
      mon.cartExtra = mon.cartExtra or {}
      local c = entry.conditions or {}
      mon.cartExtra.contest = {cool=c[1] or 0,beauty=c[2] or 0,cute=c[3] or 0,
        smart=c[4] or 0,tough=c[5] or 0,sheen=entry.sheen or 0}
    end
    return mon
  end)
  local function saveAndExport()
    local R = require('src.core.game3.runtime')
    local game, session = R._game, R.getSession()
    if not active() or not game or not session or game.session ~= session
      or game.phase ~= 'field' or require('src.core.game3.battle').isActive()
      or not game.saveOffered or not game:saveOffered() then
      return false, 'Return to the field where saving is available.'
    end
    local ok, saved = pcall(game.saveGame, game)
    if not ok or saved ~= true then return false, 'Game save failed; no export written.' end
    local ran, exported, path = pcall(require('src.import.SaveFileIO').exportActiveSlot, session.version)
    if not ran then return false, tostring(exported) end
    if not exported then return false, tostring(path) end
    return true, path
  end
  if mod.exports then mod.exports.saveAndExport = saveAndExport end
  -- One shared wrapper, one row only on a participating mod's detail page.
  wrap(require('src.mods.ManagerState'), 'detailRows', 'detailRows', function(previous, self, selected)
    local rows = previous(self, selected)
    if selected and selected.enabled and state.owners[selected.id] and state.owners[selected.id]()
      and require('src.ui.game3.mod_manager').isOpen() then
      table.insert(rows, 1, {label='SAVE + EXPORT', action=function()
        local ok, result = saveAndExport()
        if mod.log then
          if ok then mod.log:info('GBA export: %s', result) else mod.log:warn('GBA export: %s', result) end
        end
        self.overlay = {kind='ok', lines=ok and {'SAVE EXPORTED', 'See the log for the file path.'} or {'EXPORT FAILED', result}}
      end})
    end
    return rows
  end)
  return {active=active, saveAndExport=saveAndExport}
end
return Fix
