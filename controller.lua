return function(M, env)
  local C = {config=M.defaults(), state='idle', attempts=0, resets=0, elapsed=0, history={}, route={}, routeTicks=0, message='Ready. Choose a mode and start.'}
  local tokens, observed, oldMons, baselineRoamer = {}, {}, {}, nil
  local frame, warmup, routeAt, routeLeft = 0,0,1,0
  function C.running() return C.state=='running' or C.state=='recording' or C.state=='catching' or C.state=='settling' end
  function C.release()
    for _,token in pairs(tokens) do env.release(token) end
    tokens={}
  end
  function C.drive(buttons)
    for b,t in pairs(tokens) do if not buttons[b] then env.release(t); tokens[b]=nil end end
    for b in pairs(buttons) do if not tokens[b] then tokens[b]=env.press(b) end end
  end
  function C.pause(reason)
    C.release(); C.resumeState=C.running() and C.state or C.resumeState
    C.state='paused'; C.message=reason or 'Paused. Current attempt preserved.'; env.speed(nil)
    env.show()
  end
  function C.stop(skipPersist)
    C.release(); C.state='idle'; C.pendingReset=nil; C.baseline=nil; C.resumeState=nil
    C.message='Stopped. Current game state kept.'; env.speed(nil); if not skipPersist then env.persist(C) end
  end
  function C.resume()
    if C.state~='paused' or (not C.baseline and C.resumeState~='settling') then return false end
    if env.session() ~= C.session then C.stop(true); C.message='Session changed. Start a new hunt.'; return false end
    if C.pendingReset and C.config.maxAttempts>0 and C.attempts>=C.config.maxAttempts then C.message='Increase the attempt limit in Settings first.'; return false end
    C.state=C.resumeState or 'running'; C.message='Hunt resumed.'; env.hide(); env.speed(C.state=='recording' and 1 or C.config.speed); return true
  end
  function C.start(record)
    if C.state=='found' then return false, 'Keep the found Pokemon before starting another hunt.' end
    if C.config.repeatCatch and (record or not ({walk=true,vertical=true,fishing=true})[C.config.mode]) then return false,'Repeat catching supports walking and fishing only.' end
    local ok,why=env.canStart(C.config)
    if not ok then return false,why end
    if C.config.mode=='route' and not record then return false,'Choose Record new route first.' end
    local baseline,err=env.capture()
    if not baseline then return false,err end
    local saved,msg=env.backup(baseline)
    if not saved then return false,msg end
    C.origin=M.copy(baseline); C.baseline=baseline; C.session=env.session(); C.attempts=0; C.resets=0; C.elapsed=0
    oldMons=M.collection(C.session); baselineRoamer=C.session.roamer and M.key(C.session.roamer)
    observed={}; C.route={}; C.routeTicks=0; C.emptyCycles=0; frame=0; warmup=record and 0 or 60; routeAt=1; routeLeft=0
    C.state=record and 'recording' or 'running'; C.recorded=record or false; C.pendingReset=nil
    C.found=nil
    C.message=record and 'Recording. Play one attempt; encounter ends recording.' or 'Hunting. START pauses.'
    env.hide(); env.speed(record and 1 or C.config.speed); return true
  end
  function C.queueReset()
    C.release()
    C.pendingReset=true
    if C.config.maxAttempts>0 and C.attempts>=C.config.maxAttempts then C.pause('Attempt limit reached. Increase the limit before resuming.'); return end
  end
  function C.restorePending()
    if not C.pendingReset or not C.running() then return end
    C.pendingReset=nil
    if env.session()~=C.session then C.pause('Session changed; reset cancelled.'); return end
    local ok,why=env.restore(C.baseline)
    if not ok then C.pause('Reset failed: '..tostring(why)); return end
    C.session=env.session(); observed={}; C.resets=C.resets+1
    frame=0; warmup=60; routeAt=1; routeLeft=0; C.message='Attempt '..(C.attempts+1)..'. START pauses.'
  end
  function C.inspect(mon,kind,identity)
    if not C.running() or C.state=='catching' or C.state=='settling' then return false end
    if observed[identity] then return false end
    if (kind=='gift' or kind=='egg') and (tonumber(mon.otId)~=tonumber(C.session.trainerId or C.session.id)
      or tonumber(mon.otSecretId)~=tonumber(C.session.secretId)) then
      C.pause('Foreign-trainer or fixed gift detected. This route is not rerollable.'); return true
    end
    if kind=='battle' and C.baseline.save.roamer and M.pid(mon)==M.pid(C.baseline.save.roamer)
      and M.species(mon)==M.species(C.baseline.save.roamer) then
      local shiny=M.shiny(mon,C.session,true)
      if not shiny then C.pause('Roamer was generated before this starting point. Record its release instead.'); return true end
    end
    C.emptyCycles=0
    local shiny,why=M.shiny(mon,C.session,kind=='battle' or kind=='roamer')
    if shiny==nil then C.pause(why); return true end
    observed[identity]=true
    C.attempts=C.attempts+1
    if kind=='battle' and env.prepareWild then env.prepareWild(mon) end
    C.last=M.copy(mon)
    if C.state=='recording' then
      C.recorded=true; C.state='running'; C.release(); env.speed(C.config.speed)
      if C.routeTicks==0 then C.pause('No route recorded. Record again from before the encounter.'); return true end
    end
    local matches=M.matches(mon,C.config,env.pokemon)
    if shiny then
      local row={mon=M.copy(mon),kind=kind,attempt=C.attempts,seconds=C.elapsed,matched=matches,protected=not matches,outcome='found'}
      C.history[#C.history+1]=row
      if #C.history>100 then table.remove(C.history,1) end
      env.persist(C)
      if matches or C.config.protectAny then
        C.release(); C.pendingReset=nil; C.found=row; C.state='found'; env.speed(nil)
        C.message=matches and 'SHINY FOUND! Attempt preserved.' or 'Other shiny protected. Attempt preserved.'
        if kind=='battle' and matches and C.config.autoCatch then
          local can,reason=env.canCatch(C.config)
          if can then C.repeatEligible=not env.battle().safari and not (C.session.roamer and M.pid(mon)==M.pid(C.session.roamer) and M.species(mon)==M.species(C.session.roamer)); C.state='catching'; C.message='Shiny found. Throwing balls; START pauses.'
          else C.message=C.message..' '..tostring(reason); env.show() end
        else env.show() end
        return true
      end
    end
    C.queueReset(); return true
  end
  function C.scan()
    local st=env.battle()
    if st then
      if not st.wild or st.link or st.double or st.pokedude or st.oldManTutorial or st.ghostBattle then
        C.pause('Unexpected or unsupported battle. Control returned to you.'); return true
      end
      if st.enemy and st.enemy.mon then
        return C.inspect(st.enemy.mon,'battle',st)
      end
    end
    local s=C.session
    local additions,counts={},{}
    local function collect(mon)
      if type(mon)~='table' then return end
      local key=M.key(mon)
      counts[key]=(counts[key] or 0)+1
      if counts[key]>(oldMons[key] or 0) then
        additions[#additions+1]={mon=mon,identity=key..':'..counts[key]}
      end
    end
    for _,mon in pairs(s.party or {}) do collect(mon) end
    for _,box in pairs((s.storage or {}).boxes or {}) do
      for _,mon in pairs(box.mons or {}) do collect(mon) end
    end
    -- Check every new mon for a shiny before a reset, even if several arrived in one tick.
    local function priority(mon)
      if M.shiny(mon,s,false)~=true then return 0 end
      if C.config.protectAny or M.matches(mon,C.config,env.pokemon) then return 2 end
      return 1
    end
    table.sort(additions,function(a,b) return priority(a.mon)>priority(b.mon) end)
    for _,entry in ipairs(additions) do
      local mon=entry.mon
      if C.inspect(mon,env.isEgg(mon) and 'egg' or 'gift',entry.identity) then return true end
    end
    if s.roamer and M.key(s.roamer)~=baselineRoamer then return C.inspect(s.roamer,'roamer','roamer:'..M.key(s.roamer)) end
    return false
  end
  function C.record(buttons,presses)
    if C.state~='recording' or warmup>0 then return end
    presses=presses or {}
    local key=''; for _,b in ipairs({'up','down','left','right','a','b','select'}) do if buttons[b] then key=key..b..',' end end
    for _,b in ipairs({'up','down','left','right','a','b','select'}) do if presses[b] then key=key..'+'..b end end
    local last=C.route[#C.route]
    if last and last.key==key then last.ticks=last.ticks+1
    else C.route[#C.route+1]={key=key,buttons=M.copy(buttons),presses=M.copy(presses),ticks=1} end
    C.routeTicks=C.routeTicks+1
  end
  function C.tick(dt)
    if not C.running() then return end
    if env.session()~=C.session then C.pause('Game session changed. Start a new hunt.'); return end
    C.elapsed=C.elapsed+(dt or 1/60)
    if C.state=='catching' then
      local done,why,caught=env.catchStep(C.config)
      if done then
        C.found.outcome=why; C.state='found'; C.message=why; C.release(); env.speed(nil); env.persist(C)
        if caught and C.config.repeatCatch and C.repeatEligible and not C.recorded and ({walk=true,vertical=true,fishing=true})[C.config.mode] then
          -- Never allow the pre-catch snapshot to reset away a successful catch.
          C.baseline=nil; C.pendingReset=nil; C.state='settling'; C.settleTicks=0
        else env.show() end
      end
      return
    end
    if C.state=='settling' then
      C.settleTicks=C.settleTicks+1
      local ready,why=env.repeatReady(C.config)
      if ready==nil and C.settleTicks<600 then return end
      local function finish(reason)
        C.stop(); C.message='Catch kept. '..tostring(reason)..' Save normally.'; env.show()
      end
      if not ready then finish(why or 'Field did not become ready.'); return end
      local baseline,err=env.capture()
      if not baseline then finish(err); return end
      if baseline.save.map~=C.origin.save.map then finish('Map changed; repeat stopped.'); return end
      -- Refresh the ENTIRE save first, retaining catches, bag, HP and progress.
      -- Only the same-map starting position and avatar are restored.
      for _,key in ipairs({'x','y','facing'})do baseline.save[key]=C.origin.save[key] end
      baseline.avatar=M.copy(C.origin.avatar)
      local saved,msg=env.backup(baseline)
      if not saved then finish('Could not refresh recovery: '..tostring(msg)); return end
      C.baseline=baseline; oldMons=M.collection(C.session)
      baselineRoamer=C.session.roamer and M.key(C.session.roamer)
      observed={}; C.found=nil; C.emptyCycles=0; C.state='running'
      env.speed(C.config.speed); C.queueReset()
      return
    end
    if C.pendingReset then return end
    if C.scan() then return end
    if warmup>0 then warmup=warmup-1; return end
    frame=frame+1
    if frame>C.config.timeout*60 then
      if C.state=='recording' then C.pause('Recording timed out. Increase timeout or shorten the route.')
      elseif C.config.mode=='walk' or C.config.mode=='vertical' or C.config.mode=='fishing' then
        C.emptyCycles=(C.emptyCycles or 0)+1
        if C.emptyCycles>=3 then C.pause('No encounters in three cycles. Check terrain, route and Repel.') else C.queueReset() end
      else C.pause('No new Pokemon detected. Check route or generation point.') end
      return
    end
    if C.state=='recording' then return end
    if C.recorded then
      local row=C.route[routeAt]
      if not row then C.drive({}); return end
      local held={}; for b in pairs(tokens) do held[b]=true end
      C.drive(row.buttons)
      for b in pairs(row.presses or {}) do
        if held[b] or not row.buttons[b] then env.tap(b) end
      end
      routeLeft=routeLeft+1
      if routeLeft>=row.ticks then routeAt=routeAt+1; routeLeft=0 end
    elseif C.config.mode=='walk' or C.config.mode=='vertical' then
      local pair=C.config.mode=='walk' and {'left','right'} or {'up','down'}
      C.drive({[pair[math.floor((frame-1)/C.config.stride)%2+1]]=true})
    elseif C.config.mode=='interact' then
      C.drive({}); if frame%20==1 then env.tap('a') end
    elseif C.config.mode=='fishing' then
      C.drive({}); env.fishStep(frame)
    end
  end
  return C
end
