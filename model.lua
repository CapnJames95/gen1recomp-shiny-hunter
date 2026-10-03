local bit = require('bit')
local M = {}
M.stats = {'hp','atk','def','spe','spa','spd'}
M.natures = {'Hardy','Lonely','Brave','Adamant','Naughty','Bold','Docile','Relaxed','Impish','Lax','Timid','Hasty','Serious','Jolly','Naive','Modest','Mild','Quiet','Bashful','Rash','Calm','Gentle','Sassy','Careful','Quirky'}
M.modes = {
  {id='walk', name='Wild: walk left/right', help='Stand in a clear patch of grass, cave or water.'},
  {id='vertical', name='Wild: walk up/down', help='Walks real steps; encounters use current terrain.'},
  {id='interact', name='Static / gift: interact', help='Face the target. Repeats A; use recording for choices.'},
  {id='fishing', name='Fishing: registered rod', help='Register a rod, face water. Handles bites automatically.'},
  {id='route', name='Recorded route', help='Record inputs up to a battle, gift, egg or new roamer.'},
}
function M.copy(v, seen)
  if type(v) ~= 'table' then return v end
  seen = seen or {}; if seen[v] then return seen[v] end
  local out = {}; seen[v] = out
  for k,x in pairs(v) do out[M.copy(k,seen)] = M.copy(x,seen) end
  return out
end
function M.defaults()
  return {mode='walk', species=0, nature=-1, gender='Any', ability=0,
    ivs={hp=0,atk=0,def=0,spe=0,spa=0,spd=0}, protectAny=true,
    autoCatch=false, repeatCatch=false, ball=2, speed=64, timeout=120, stride=24, maxAttempts=0}
end
function M.pid(mon) return tonumber(mon.personality or mon.pid) end
function M.species(mon) return tonumber(mon.species or mon.speciesId) end
function M.key(mon)
  return tostring(M.species(mon))..':'..tostring(M.pid(mon))..':'..tostring(mon.otId or '')..':'..tostring(mon.otSecretId or '')
end
function M.shiny(mon, session, wild)
  local p = M.pid(mon)
  if not p then return nil, 'Pokemon has no personality value.' end
  local tid,sid
  if wild then tid,sid=session.trainerId or session.id or session.playerId,session.secretId
  else tid,sid=mon.otId,mon.otSecretId end
  if tid == nil or sid == nil then return nil, 'Trainer IDs missing; cannot safely check shininess.' end
  return bit.bxor(tonumber(tid)%65536, tonumber(sid)%65536, math.floor(p/65536), p%65536) < 8
end
function M.matches(mon, c, pokemon)
  local s,p = M.species(mon), M.pid(mon)
  if c.species ~= 0 and c.species ~= s then return false end
  if c.nature >= 0 and p%25 ~= c.nature then return false end
  if c.gender ~= 'Any' and pokemon.gender(s,p) ~= c.gender then return false end
  if c.ability ~= 0 and pokemon.abilityId(s,p) ~= c.ability then return false end
  local aliases = {atk='attack',def='defense',spe='speed',spa='spAtk',spd='spDef'}
  for _,k in ipairs(M.stats) do
    if (tonumber((mon.ivs or {})[k] or (mon.ivs or {})[aliases[k]]) or -1) < (c.ivs[k] or 0) then return false end
  end
  return true
end
function M.collection(session)
  local out = {}
  for _,m in pairs(session.party or {}) do if type(m)=='table' then out[M.key(m)] = (out[M.key(m)] or 0)+1 end end
  for _,box in pairs((session.storage or {}).boxes or {}) do
    for _,m in pairs(box.mons or {}) do if type(m)=='table' then out[M.key(m)] = (out[M.key(m)] or 0)+1 end end
  end
  return out
end
return M
