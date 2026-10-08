-- Newly generated acquisitions only. Delivery, parent inheritance and story
-- state are left to the engine; existing records and fixed gifts are untouched.
local A={}
function A.install(mod,O)
 local R=require('src.core.game3.rng')
 local Runtime=require('src.core.game3.runtime')
 local Mods=require('src.mods.Runtime')
 local P=require('src.core.game3.pokemon')
 local Party=require('src.core.game3.party')
 local Breed=require('src.core.game3.breeding')
 local Roamer=require('src.core.game3.roamer')
 local state=Party._shinyHunterAcquisitions or {wrappers={}}
 Party._shinyHunterAcquisitions=state
 state.owner,state.mod=Mods.events,mod
 local function active(s)
  if not s or s~=Runtime.getSession() or not ({firered=true,leafgreen=true,emerald=true,ruby=true,sapphire=true})[s.version] then return false end
  if state.owner~=Mods.events or O.get(s)==8192 or type(s.trainerId)~='number' or type(s.secretId)~='number' then return false end
  if mod.find and not mod.find(mod.id) or mod.options and mod.options:get('enabled')==false then return false end
  if s.frontier and (s.frontier.challengeStatus or 0)~=0 then return false end
  return not (Mods.wantsHook('encounter.roll') or Mods.wantsHook('encounter.species'))
 end
 local function wrap(target,key,handler)
  local rec=state.wrappers[key]
  if not rec then
   rec={previous=assert(target[key])};state.wrappers[key]=rec
   target[key]=function(...)return rec.handler(rec.previous,...)end
  end
  rec.handler=handler
 end
 local function method1()
  local pid=R.Random32();local a,b=R.Random(),R.Random()
  return {personality=pid,ivs={hp=a%32,atk=math.floor(a/32)%32,def=math.floor(a/1024)%32,spe=b%32,spa=math.floor(b/32)%32,spd=math.floor(b/1024)%32}}
 end
 local function choose(first,s,nextCandidate)
  if O.shiny(first.personality,s)then return first end
  for _=2,O.rolls(O.get(s))do
   local candidate=nextCandidate()
   if candidate and O.shiny(candidate.personality,s)then return candidate end
  end
  return first
 end
 local function identity(mon,candidate)
  mon.personality=candidate.personality;mon.ivs=candidate.ivs
  mon.nature=P.natureId(mon.personality);mon.gender=P.gender(mon.species,mon.personality)
  local abilities=P.abilities(mon.species)
  mon.abilityNum=abilities[2]==0 and 0 or mon.personality%2
  mon.ability=P.abilityId(mon.species,mon.personality);mon.abilityId=mon.ability
  mon.isShiny=nil
  P.applyStats(mon);mon.hp=mon.maxHp
 end
 wrap(Party,'giveMon',function(previous,s,species,level,nickname,opts)
  local ok,code,mon,box,slot=previous(s,species,level,nickname,opts)
  if ok and mon and active(s) and not (opts and (opts.fixedPersonality~=nil or opts.eventDistribution)) then
   identity(mon,choose(mon,s,method1))
  end
  return ok,code,mon,box,slot
 end)
 for _,name in ipairs({'init','initRse'})do
  wrap(Roamer,name,function(previous,s,...)
   local result=previous(s,...)
   if result and active(s) and s.roamer then
    local mon=s.roamer
    local first={personality=mon.personality or mon.pid,ivs=mon.ivs}
    local chosen=choose(first,s,method1)
    -- FRLG and RS retain only the low eight bits of the stored IV word.
    if s.version~='emerald' then
     chosen={personality=chosen.personality,ivs={hp=chosen.ivs.hp,atk=(chosen.ivs.atk or chosen.ivs.attack or 0)%8,def=0,spe=0,spa=0,spd=0}}
    end
    identity(mon,chosen);mon.pid=mon.personality
   end
   return result
  end)
 end
 wrap(Breed,'setInitialEggData',function(previous,s,species,dc)
  local egg=previous(s,species,dc)
  -- Emerald stores its complete PID when the egg is produced. FRLG/RS
  -- generate the high word and base IVs at pickup, before inheritance.
  if egg and active(s) and s.version~='emerald' then
   egg=choose(egg,s,function()return previous(s,species,dc)end)
   identity(egg,egg)
  end
  return egg
 end)
 wrap(Breed,'triggerPendingEgg',function(previous,s,dc)
  local Daycare=require('src.core.game3.daycare')
  s=Daycare.sessionOf(s);dc=dc or Daycare.stateOf(s)
  local wasPending=dc and Daycare.isEggPending(dc)
  local first=previous(s,dc)
  if not active(s) or s.version~='emerald' or not dc or wasPending or O.shiny(first,s) then return first end
  local clock=Runtime._vblankCounter
  local ok,chosen=pcall(function()
   local selected=choose({personality=first},s,function()
    -- Advance the virtual generation frame, not the player's actual clock.
    Runtime._vblankCounter=(tonumber(Runtime._vblankCounter) or 0)+1
    return {personality=Breed.rsePersonality(s,dc)}
   end)
   return selected.personality
  end)
  Runtime._vblankCounter=clock
  if not ok then dc.offspringPersonality=first;error(chosen,0)end
  dc.offspringPersonality=chosen;return chosen
 end)
 wrap(Breed,'createEgg',function(previous,s,...)
  local args={...};local egg=previous(s,unpack(args))
  if egg and active(s)then
   -- Native createEgg may consume a discarded gift PID between its PID
   -- and IV words. Supply a complete Method 1 gift-egg candidate.
   identity(egg,choose(method1(),s,method1))
  end
  return egg
 end)
end
return A
