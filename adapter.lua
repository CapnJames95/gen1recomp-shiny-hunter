return function(M,mod)
  local E={}
  local Runtime=require('src.core.game3.runtime')
  local Pokemon=require('src.core.game3.pokemon')
  local Battle=require('src.core.game3.battle')
  local Schema=require('src.core.game3.save_schema_firered')
  local Rng=require('src.core.game3.rng')
  local Space=require('src.core.game3.scripting.space')
  local Player=require('src.core.game3.player')
  local Bag=require('src.core.game3.bag')
  local Field=require('src.core.game3.field')
  local catchTicks,catchState
  E.pokemon=Pokemon
  E.session=Runtime.getSession
  E.isEgg=Pokemon.isEgg
  function E.prepareWild(mon)
    local session=E.session()
    -- Match the OT metadata the engine will assign on capture, so native
    -- battle sprites agree with the PID check. Never alter PID or IVs.
    if mon.otId==nil then mon.otId=session.trainerId or session.id or session.playerId end
    if mon.otSecretId==nil then mon.otSecretId=session.secretId end
  end
  function E.battle() return Battle.isActive() and Battle.getState() or nil end
  function E.press(b) return mod.input:press(E.game,b) end
  function E.release(t) mod.input:release(t) end
  function E.tap(b) mod.input:tap(E.game,b) end
  function E.speed(value) E.requestedSpeed=value end
  local function capacity(s)
    if #(s.party or {})<6 then return true end
    for b=1,14 do
      local box=s.storage and s.storage.boxes and s.storage.boxes[b]
      for i=1,30 do if not box or not box.mons or not box.mons[i] then return true end end
    end
    return false
  end
  function E.canStart(c)
    local s=E.session()
    if not s or (s.version~='firered' and s.version~='leafgreen' and s.version~='emerald') then return false,'FireRed, LeafGreen or Emerald field session required.' end
    if not E.game or E.game.generation~=3 or type(E.game.returnToTitle)~='function' or type(E.game._enterField)~='function' then
      return false,'This engine build lacks the required reset API.'
    end
    if E.game.phase~='field' or Battle.isActive() or Field.locked or Player.moving
      or (Space.vm and Space.vm:isRunning()) or (Space._immediateVm and Space._immediateVm:isRunning()) then
      return false,'Stand still in the overworld before starting.'
    end
    if E.game.speedLocked and E.game:speedLocked() then return false,'Finish the linked activity or minigame first.' end
    if s.version=='emerald' and s.frontier and (s.frontier.challengeStatus or 0)~=0 then return false,'Finish the Battle Frontier challenge first.' end
    if s.secretId==nil or (s.trainerId or s.id)==nil then return false,'Trainer IDs are unavailable.' end
    if not capacity(s) then return false,'Party and PC are full.' end
    if c.mode=='fishing' then
      local rod=tonumber(s.registeredItem)
      if not ({[262]=true,[263]=true,[264]=true})[rod] or not Bag.has(s.bag,rod,1) then return false,'Register an owned Old, Good or Super Rod first.' end
    end
    return true
  end
  function E.capture()
    if mod.storage.context then
      local context,code,why=mod.storage:context(E.game)
      if not context then return nil,why or code end
    end
    if E.game.save and E.game.save.meta then E.session().meta=M.copy(E.game.save.meta) end
    Space.persistSession(nil,E.game)
    if Player.syncSavePosition then Player.syncSavePosition(E.game) end
    local save=M.copy(Schema.toSaveTable(E.session()))
    if not save or not save.map then return nil,'Could not capture the starting point.' end
    return {format=2, avatar={surfing=Player.surfing==true,biking=Player.biking==true,bikeType=Player.bikeType,underwater=Player.underwater==true,elevation=Player.elevation}, safari=M.copy(E.session().safari), save=save, trainerId=E.session().trainerId, secretId=E.session().secretId, version=E.session().version}
  end
  function E.backup(baseline)
    local ok,code,why=mod.storage:write(E.game,'recovery/start',baseline)
    return ok,why or code
  end
  function E.restore(baseline)
    local s=E.session()
    if type(baseline)~='table' or baseline.format~=2 or type(baseline.save)~='table' then return false,'Starting point is missing or from an older version. Start a fresh hunt.' end
    if not s or s.version~=baseline.version or s.trainerId~=baseline.trainerId or s.secretId~=baseline.secretId then return false,'Starting point belongs to a different trainer or game.' end
    local liveRng=Rng.getState()
    local copy=M.copy(baseline.save)
    copy.options=M.copy(E.game.options or s.options)
    copy.rng=liveRng
    -- Reuse the engine soft-reset path so scripts, messages, transitions and tasks
    -- are cleaned together. returnToTitle reads normal saves but never writes one.
    local restored=Schema.fromSaveTable(copy)
    if baseline.format==2 then
      -- A hunt snapshot resumes field control, not the cartridge's Continue
      -- warp. Normal save decoding intentionally exits Safari and drops avatar
      -- state, so restore these captured runtime fields explicitly.
      restored.flags=M.copy(baseline.save.flags)
      restored.vars=M.copy(baseline.save.vars)
      restored.map,restored.x,restored.y,restored.facing=baseline.save.map,baseline.save.x,baseline.save.y,baseline.save.facing
      restored.safari=M.copy(baseline.safari)
      restored._continueWarpDeferred=nil
    end
    E.game:returnToTitle()
    restored.rng=liveRng
    E.game:_enterField(restored,'continue')
    if baseline.format==2 then
      local avatar=baseline.avatar or {}
      Player.surfing=avatar.surfing==true
      Player.biking=avatar.biking==true
      Player.bikeType=avatar.bikeType
      Player.underwater=avatar.underwater==true
      if avatar.elevation~=nil then Player.elevation=avatar.elevation end
    end
    if E.session()~=restored then return false,'Engine did not activate the restored session.' end
    return true
  end
  function E.persist(c)
    local ok,code,why=mod.storage:write(E.game,'hunt/state',{format=1, config=M.copy(c.config), history=M.copy(c.history), attempts=c.attempts, elapsed=c.elapsed})
    if not ok then mod.log:warn('Shiny Hunter history: %s',tostring(why or code)) end
  end
  function E.recover()
    local c=M.defaults()
    local ok,why=E.canStart(c)
    if not ok then return false,why end
    local baseline,code,msg=mod.storage:read(E.game,'recovery/start')
    if not baseline then return false,msg or code end
    return E.restore(baseline)
  end
  function E.load()
    return mod.storage:read(E.game,'hunt/state')
  end
  function E.fishStep(frame)
    local f=Field._fishing
    if f then
      -- Engine currently resolves bites itself; A only advances result text.
      if f.step=='result' and frame%16==0 then E.tap('a') end
    elseif frame%45==1 then E.tap('select') end
  end
  function E.canCatch(c)
    local s=E.session(); local st=E.battle()
    if not st or not st.wild or st.link or st.double or st.ghostBattle then return false,'Auto-catch unavailable here.' end
    if not capacity(s) then return false,'Party and PC are full.' end
    if st.safari then
      if not st.safariState or (st.safariState.balls or 0)<1 then return false,'No Safari Balls remain.' end
    elseif not Bag.has(s.bag,c.ball,1) then return false,'Selected balls are depleted.' end
    if not st.safari and st.player and (st.player.hp or (st.player.mon or {}).hp or 0)<=0 then return false,'Lead Pokemon fainted. Take over manually.' end
    return true
  end
  function E.catchStep(c)
    local st=E.battle()
    if st~=catchState then catchTicks=0; catchState=st end
    catchTicks=(catchTicks or 0)+1
    if not st then
      local result=Battle.getResult()
      catchTicks=0
      return true,result=='catch' and 'Shiny caught! Save normally to keep it.' or ('Battle ended: '..tostring(result)..'. No retry was started.')
    end
    if not st.safari and st.player and (st.player.hp or (st.player.mon or {}).hp or 0)<=0 then
      return true,'Lead Pokemon fainted. Take over manually.'
    end
    if catchTicks>60*600 then catchTicks=0; return true,'Capture timed out. Take over manually.' end
    local Ui=require('src.core.game3.battle.ui')
    local Choice=require('src.ui.game3.choice')
    if Battle._phase=='command' and not Ui.busy() then
      local ok,why=E.canCatch(c)
      if not ok then return true,why end
      if Ui._mode~='menu' then return true,'Unexpected battle menu. Take over manually.' end
      if not Ui._pendingCommand then
        Ui._pendingCommand=st.safari and {kind='safari',action='ball',user='player'} or {kind='bag',itemId=c.ball,user='player'}
      end
    elseif catchTicks%12==0 then
      E.tap(Choice.active and 'b' or 'a')
    end
    return false
  end
  return E
end
