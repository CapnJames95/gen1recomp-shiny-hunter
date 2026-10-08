-- Shiny odds: complete PID/IV rerolls for ordinary wild and fresh static encounters.
-- Never changes the game's shiny threshold or existing Pokemon.
local O={values={8192,4096,2048,1024,512,256,128,64,32,16,8,4,2,1}}
O.generated=setmetatable({},{__mode='k'})
local bit=require('bit')
local allowed={};for _,v in ipairs(O.values)do allowed[v]=true end
function O.get(s)
 local data=s and s.modData and s.modData.shiny_hunter
 local value=data and data.wildOdds
 return allowed[value] and value or 8192
end
function O.set(s,value)
 if not s or not allowed[value]then return false end
 s.modData=s.modData or {};s.modData.shiny_hunter=s.modData.shiny_hunter or {}
 s.modData.shiny_hunter.wildOdds=value;return true
end
function O.getDualScreen(s)
 local data=s and s.modData and s.modData.shiny_hunter
 return data and data.dualScreenOdds==true or false
end
function O.setDualScreen(s,value)
 if not s or type(value)~='boolean' then return false end
 s.modData=s.modData or {};s.modData.shiny_hunter=s.modData.shiny_hunter or {}
 s.modData.shiny_hunter.dualScreenOdds=value;return true
end
function O.prepareDualScreen(enc,s,forceShiny)
 if forceShiny~=true and (not O.getDualScreen(s) or O.get(s)==8192) then return enc end
 local Mods=require('src.mods.Runtime')
 if Mods.wantsHook('encounter.roll') or Mods.wantsHook('encounter.species')then return enc end
 if type(enc)~='table' or enc.personality or enc.ivs or enc.foe or enc.roamer or enc.moves or enc.eventDistribution then return enc end
 if not s or not ({firered=true,leafgreen=true,emerald=true,ruby=true,sapphire=true})[s.version]
  or type(s.trainerId)~='number' or type(s.secretId)~='number' or enc.species==201 then return enc end
 if s.frontier and (s.frontier.challengeStatus or 0)~=0 or s.safari and (s.safari.active or (tonumber(s.safari.steps) or 0)>0)then return enc end
 if type(s.map)=='string' and (s.map:find('BATTLE_') or s.map:find('SAFARI'))then return enc end
 local E=require('src.core.game3.encounters');local R=require('src.core.game3.rng')
 local hoenn=s and (s.version=='emerald' or s.version=='ruby' or s.version=='sapphire')
 local rules=hoenn and E.rules() or nil
 local create=rules and rules.createWild
 local first=enc
 if create then
  first={};for k,v in pairs(enc)do first[k]=v end
  local generated=create(enc.species,enc.level)
  first.personality,first.ivs=generated.personality,generated.ivs
 end
 return O.apply(first,s,R,create,hoenn,forceShiny==true and 1 or nil)
end
function O.rolls(odds)
 if not allowed[odds]then return 1 end
 -- Guaranteed mode searches until a complete naturally shiny candidate is found.
 if odds==1 then return math.huge end
 return math.floor(math.log(1-1/odds)/math.log(1-1/8192)+0.5)
end
function O.shiny(pid,s)
 return bit.bxor(math.floor(pid/65536),pid%65536,s.trainerId,s.secretId)<8
end
local function ivs(R)
 local a,b=R.Random(),R.Random()
 return {hp=a%32,atk=math.floor(a/32)%32,def=math.floor(a/1024)%32,spe=b%32,spa=math.floor(b/32)%32,spd=math.floor(b/1024)%32}
end
function O.apply(enc,s,R,createWild,nativeRs,override)
 local odds=allowed[override] and override or O.get(s)
 if odds==8192 or type(enc)~='table' or not s or not ({firered=true,leafgreen=true,emerald=true,ruby=true,sapphire=true})[s.version]then return enc end
 if type(s.trainerId)~='number' or type(s.secretId)~='number' then return enc end
 if enc.foe or enc.roamer or enc.moves or (enc.ivs and not nativeRs) or enc.eventDistribution or enc.wildScripted then return enc end
 if s.frontier and (s.frontier.challengeStatus or 0)~=0 or s.safari and (s.safari.active or (tonumber(s.safari.steps) or 0)>0) then return enc end
 local species=tonumber(enc.species);local level=tonumber(enc.level)
 -- Unown forms and scripted/facility encounters require separate validation.
 if not species or species==201 or not level or level<1 or level>100 then return enc end
 if type(s.map)=='string' and (s.map:find('BATTLE_') or s.map:find('SAFARI'))then return enc end
 local hoenn=s.version=='emerald' or s.version=='ruby' or s.version=='sapphire'
 if hoenn and type(createWild)~='function' then return enc end
 local pid=enc.personality or R.Random32()
 local first={personality=pid,ivs=enc.ivs or ivs(R)};local chosen=first
 local rolls=1
 if not O.shiny(pid,s)then
  for _=2,O.rolls(odds)do
   local candidate
   if hoenn then candidate=createWild(species,level)
   else
    local nature=R.Random()%25
    local p
    repeat p=R.Random32() until p%25==nature
    candidate={personality=p}
   end
   candidate.ivs=candidate.ivs or ivs(R);rolls=rolls+1
   if O.shiny(candidate.personality,s)then chosen=candidate;break end
  end
 end
 local result={};for k,v in pairs(enc)do result[k]=v end
 result.personality=chosen.personality;result.ivs=chosen.ivs
 O.generated[result]=s
 -- Metadata is diagnostic only; the save/export path uses PID and IVs normally.
 O.last={rolls=rolls,odds=odds,shiny=O.shiny(chosen.personality,s),species=species}
 return result
end
-- Scripted stationary encounters use Method 1, not wild Method H.
-- Only consume fresh descriptors from setWildBattle; never reroll an existing mon.
function O.applyStatic(enc,s,R)
 local odds=O.get(s)
 if odds==8192 or type(enc)~='table' or not s or not ({firered=true,leafgreen=true,emerald=true,ruby=true,sapphire=true})[s.version]then return enc end
 if type(s.trainerId)~='number' or type(s.secretId)~='number' then return enc end
 if enc.personality or enc.ivs or enc.foe or enc.roamer or enc.moves or enc.eventDistribution then return enc end
 local species,level=tonumber(enc.species),tonumber(enc.level)
 if not species or species==201 or not level or level<1 or level>100 then return enc end
 if s.frontier and (s.frontier.challengeStatus or 0)~=0 or s.safari and (s.safari.active or (tonumber(s.safari.steps) or 0)>0) then return enc end
 if type(s.map)=='string' and (s.map:find('BATTLE_') or s.map:find('SAFARI'))then return enc end
 local chosen,rolls
 for i=1,O.rolls(odds)do
  local candidate={personality=R.Random32(),ivs=ivs(R)}
  if i==1 then chosen=candidate end
  rolls=i
  if O.shiny(candidate.personality,s)then chosen=candidate;break end
 end
 local result={};for k,v in pairs(enc)do result[k]=v end
 result.personality,result.ivs=chosen.personality,chosen.ivs
 O.generated[result]=s
 O.last={rolls=rolls,odds=odds,shiny=O.shiny(chosen.personality,s),species=species,kind='static'}
 return result
end
function O.install(mod)
 local E=require('src.core.game3.encounters')
 local R=require('src.core.game3.rng')
 local Runtime=require('src.core.game3.runtime')
 local Mods=require('src.mods.Runtime')
 local state=E._shinyHunterOdds
 if not state then state={};E._shinyHunterOdds=state end
 state.owner=Mods.events;state.mod=mod;state.apply=O.apply;state.applyStatic=O.applyStatic;state.generated=O.generated;state.depth=0
 if E.takePendingWild and not state.staticInstalled then
  state.staticInstalled=true
  local take=E.takePendingWild
  E.takePendingWild=function(...)
   local result=take(...)
   local live=state.owner==Mods.events and (not state.mod.find or state.mod.find(state.mod.id)~=nil) and (not state.mod.options or state.mod.options:get('enabled')~=false)
   if not live or Mods.wantsHook('encounter.roll') or Mods.wantsHook('encounter.species')then return result end
   return state.applyStatic(result,Runtime.getSession(),R)
  end
 end
 if state.installed then return end
 state.installed=true
 local Battle=require('src.core.game3.battle')
 local start=Battle.start
 Battle.start=function(opts,...)
  local ok,why=start(opts,...)
  local s=Runtime.getSession()
  if ok and opts and state.generated[opts.foe]==s and state.owner==Mods.events then
   local st=Battle.getState();local mon=st and st.enemy and st.enemy.mon
   if mon and mon.personality==opts.foe.personality then
    local abilities=require('src.core.game3.pokemon').abilities(mon.species)
    mon.abilityNum=abilities[2]==0 and 0 or mon.personality%2
   end
   state.generated[opts.foe]=nil
  end
  return ok,why
 end
 for _,name in ipairs({'onStep','rollLand','rollWater','rollFishing','rollRocks','rollSweetScent'})do
  local previous=E[name]
  E[name]=function(...)
   local live=state.owner==Mods.events and (not state.mod.find or state.mod.find(state.mod.id)~=nil) and (not state.mod.options or state.mod.options:get('enabled')~=false)
   if not live or state.depth>0 or O.get(Runtime.getSession())==8192 then return previous(...)end
   -- Another encounter replacement may have its own identity/legality rules.
   if Mods.wantsHook('encounter.roll') or Mods.wantsHook('encounter.species')then return previous(...)end
   state.depth=state.depth+1
   local ok,result=pcall(previous,...)
   state.depth=state.depth-1
   if not ok then error(result,0)end
   local s=Runtime.getSession()
   local hoenn=s and (s.version=='emerald' or s.version=='ruby' or s.version=='sapphire')
   local rules=hoenn and E.rules() or nil
   return state.apply(result,s,R,rules and rules.createWild,s and (s.version=='ruby' or s.version=='sapphire'))
  end
 end
end
return O
