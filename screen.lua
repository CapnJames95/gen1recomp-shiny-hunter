return function(M,C,E,V)
  local S={pages={},controller=C,elapsed=0}
  local Stack=require('src.ui.game3.stack')
  local Pokemon=E.pokemon
  local function push(title,rows,portrait)
    S.notice=nil; S.pages[#S.pages+1]={title=title,rows=rows,cursor=1,portrait=portrait,small=not portrait}
  end
  local function back()
    S.notice=nil
    if #S.pages>1 then table.remove(S.pages) else S.hide() end
  end
  local function choose(title,values,set)
    local rows={}
    for _,entry in ipairs(values) do local v=entry
      rows[#rows+1]={label=v.label,help=v.help,action=function() set(v.value); E.persist(C); back() end}
    end
    push(title,rows)
  end
  local function numbers(title,values,set,fmt)
    local out={}; for _,n in ipairs(values) do out[#out+1]={label=fmt and fmt(n) or tostring(n),value=n} end
    choose(title,out,set)
  end
  local function species()
    local rows={{label='Any species',value=0}}
    for nat=1,386 do
      local id=Pokemon.speciesFromNational(nat)
      if id and Pokemon.name(id) then rows[#rows+1]={label=string.format('%03d %s',nat,Pokemon.name(id)),value=id} end
    end
    choose('TARGET SPECIES',rows,function(v) C.config.species=v; C.config.ability=0 end)
  end
  local function filters()
    local cfg=C.config
    local rows={
      {label=function() return 'Species: '..(cfg.species==0 and 'Any' or Pokemon.name(cfg.species)) end,action=species},
      {label=function() return 'Nature: '..(M.natures[cfg.nature+1] or 'Any') end,action=function()
        local values={{label='Any nature',value=-1}}; for i,n in ipairs(M.natures) do values[#values+1]={label=n,value=i-1} end
        choose('NATURE',values,function(v) cfg.nature=v end)
      end},
      {label=function() return 'Gender: '..cfg.gender end,action=function() choose('GENDER',{{label='Any',value='Any'},{label='Male',value='M'},{label='Female',value='F'},{label='Genderless',value='U'}},function(v) cfg.gender=v end) end},
      {label=function() return 'Ability: '..(cfg.ability==0 and 'Any' or Pokemon.abilityName(cfg.ability)) end,action=function()
        local rows={{label='Any ability',value=0}}
        for id=1,77 do rows[#rows+1]={label=Pokemon.abilityName(id),value=id} end
        choose('ABILITY',rows,function(v) cfg.ability=v end)
      end},
    }
    for _,k in ipairs(M.stats) do local key=k
      rows[#rows+1]={label=function() return key:upper()..' IV minimum: '..cfg.ivs[key] end,action=function()
        local vals={}; for i=0,31 do vals[#vals+1]=i end
        numbers('MINIMUM '..key:upper()..' IV',vals,function(v) cfg.ivs[key]=v end)
      end}
    end
    push('CONFIGURE HUNT',rows)
  end
  local function modes()
    local rows={}
    for _,mode in ipairs(M.modes) do local m=mode
      rows[#rows+1]={label=m.name,help=m.help,action=function() C.config.mode=m.id; E.persist(C); back() end}
    end
    rows[#rows+1]={label='Mode guidance',help='Static, gifts, fossils, eggs, Safari and roamers.',action=function()
      push('ENCOUNTER GUIDE',{
        {label='Static: face target, Interact',help='Legendaries / Snorlax: record if dialogue needs choices.'},
        {label='Grass / cave / surf: Walk',help='Choose horizontal or vertical on clear encounter tiles.'},
        {label='Fishing: register your rod',help='Face fishable water; the game validates the location.'},
        {label='Gifts / fossils / prizes: Record',help='Start BEFORE receiving it. Record menus and dialogue.'},
        {label='Eggs: before new egg creation',help='Existing eggs cannot be rerolled by hatching them again.'},
        {label='Roamer: before it is generated',help='An already released roamer keeps its PID. Record release.'},
        {label='Rock Smash / Safari: Record',help='Record movement and interaction. Safari capture can fail.'},
        {label='Fixed trades / events: excluded',help='No rerolling fixed-identity trades or injected Pokemon.'},
      })
    end}
    push('ENCOUNTER MODES',rows)
  end
  local function begin(record)
    local ok,why=C.start(record)
    if not ok then S.notice=why end
  end
  local function startPage()
    if C.state=='paused' then if not C.resume() then S.notice=C.message end; return end
    if C.state=='found' then S.notice='Shiny preserved. Use Keep result & stop below.'; return end
    push('START HUNT',{
      {label='Start selected mode',help='Captures recovery point. Resets failed attempts in memory.',action=function() begin(false) end},
      {label='Record new route',help='Play ONE attempt. Detection starts automatic replay.',action=function() begin(true) end},
      {label='Back',help='Normal save is never overwritten by the hunter.',action=back},
    })
  end
  local function settings()
    local cfg=C.config
    push('SETTINGS',{
      {label=function() return 'Other shinies: '..(cfg.protectAny and 'Protect' or 'Skip') end,help='Protect stops for any shiny, even outside your filters.',action=function()
        if cfg.protectAny then
          push('SKIP OTHER SHINIES?',{
            {label='Keep protection ON',action=back},
            {label='Skip shinies outside filters',help='These shinies will be lost when their attempts reset.',action=function() cfg.protectAny=false; E.persist(C); back() end},
          })
        else cfg.protectAny=true; E.persist(C) end
      end},
      {label=function() return 'On match: '..(cfg.autoCatch and 'Auto-catch' or 'Stop') end,help='Throws balls only. No attacks; capture is not guaranteed.',action=function() cfg.autoCatch=not cfg.autoCatch; E.persist(C) end},
      {label=function() return 'After catch: '..(cfg.repeatCatch and 'Keep hunting' or 'Stop') end,help='Walking/fishing only. Keeps catches and used balls; returns to starting spot.',action=function() cfg.repeatCatch=not cfg.repeatCatch; E.persist(C) end},
      {label=function() return 'Ball: '..({[1]='Master',[2]='Ultra',[3]='Great',[4]='Poke',[6]='Net',[7]='Dive',[8]='Nest',[9]='Repeat',[10]='Timer',[11]='Luxury',[12]='Premier'})[cfg.ball] end,action=function()
        local rows={}; for id,name in pairs({[1]='Master Ball',[2]='Ultra Ball',[3]='Great Ball',[4]='Poke Ball',[6]='Net Ball',[7]='Dive Ball',[8]='Nest Ball',[9]='Repeat Ball',[10]='Timer Ball',[11]='Luxury Ball',[12]='Premier Ball'}) do rows[#rows+1]={value=id,label=name} end
        table.sort(rows,function(a,b) return a.value<b.value end)
        choose('CAPTURE BALL',rows,function(v) cfg.ball=v end)
      end},
      {label=function() return 'Speed: '..cfg.speed..'x' end,help='Up to 256x; CPU-limited. Recording stays at 1x.',action=function() numbers('HUNT SPEED',{1,2,4,8,16,32,64,128,256},function(v) cfg.speed=v end,function(v) return v..'x' end) end},
      {label=function() return 'Attempt timeout: '..cfg.timeout..'s' end,help='Game time. Longer routes need a larger timeout.',action=function() numbers('TIMEOUT',{30,60,120,300,600,1800},function(v) cfg.timeout=v end) end},
      {label=function() return 'Walk stride: '..cfg.stride..' ticks' end,help='Adjust to your clear patch. One tick is 1/60 game second.',action=function() numbers('WALK STRIDE',{16,24,32,48,64,96},function(v) cfg.stride=v end) end},
      {label='Recover last starting point',help='Restores the saved recovery snapshot in memory.',action=function()
        if C.baseline then S.notice='Stop the current hunt before using recovery.'; return end
        push('RESTORE STARTING POINT?',{
          {label='Cancel',action=back},
          {label='Restore recovery snapshot',help='Unsaved progress after that starting point is discarded.',action=function()
            local ok,why=E.recover()
            if ok then S.hide() else S.notice=why end
          end},
        })
      end},
      {label=function() return 'Attempt limit: '..(cfg.maxAttempts==0 and 'None' or cfg.maxAttempts) end,action=function() numbers('ATTEMPT LIMIT',{0,10,100,1000,10000,100000},function(v) cfg.maxAttempts=v end) end},
    })
  end
  local function history()
    local rows={}
    for i=#C.history,1,-1 do local r=C.history[i]
      rows[#rows+1]={label=Pokemon.name(M.species(r.mon))..' #'..r.attempt,help=r.kind..' | '..tostring(r.outcome)..(r.matched and ' | matched' or ' | outside filters'),action=function()
        local iv={}; for _,k in ipairs(M.stats) do iv[#iv+1]=tostring((r.mon.ivs or {})[k] or '?') end
        push('SHINY RECORD',{
          {label=Pokemon.name(M.species(r.mon))..' / '..r.kind},
          {label='PID: '..string.format('%08X',M.pid(r.mon) or 0)},
          {label='Nature: '..(M.natures[(M.pid(r.mon) or 0)%25+1])},
          {label='IVs: '..table.concat(iv,'/')},
          {label='Attempt '..r.attempt..' / '..math.floor(r.seconds)..' seconds'},
          {label=r.outcome,help='History stores a record, not an extra Pokemon.'},
        })
      end}
    end
    if #rows==0 then rows={{label='No shinies found yet',help='Found Pokemon are recorded here automatically.'}} end
    push('FOUND SHINIES',rows)
  end
  function S.home()
    S.pages={}
    push('SHINY HUNTER',{
      {label='Configure hunt',help='Species, nature, gender, ability and minimum IVs.',action=function() if C.baseline then S.notice='Stop the current hunt before changing filters.' else filters() end end},
      {label=function() return C.state=='paused' and 'Resume hunt' or 'Start hunt' end,help=C.message,action=startPage},
      {label='Encounter modes',help='Choose automatic movement, interaction or a recorded route.',action=function() if C.baseline then S.notice='Stop the current hunt before changing mode.' else modes() end end},
      {label='Found shinies',help='Read found Pokemon, attempts and capture outcomes.',action=history},
      {label=function()local n=E.wildOdds and E.wildOdds.get(E.session()) or 8192;return n==8192 and 'Shiny odds: Vanilla' or n==1 and 'Shiny odds: 1/1' or 'Shiny odds: ~1/'..n end,help='New encounters, gifts and eggs; save normally.',action=function()
        if C.baseline then S.notice='Stop the current hunt before changing odds.';return end
        local values={}
        for _,n in ipairs(E.wildOdds.values)do values[#values+1]={value=n,label=n==8192 and 'Vanilla: 1/8192' or n==1 and 'Guaranteed: 1/1' or 'Approx. 1/'..n,help=n<=32 and 'Extra rolls may pause before battle. Existing Pokemon unchanged.' or 'Extra complete rolls. Only newly generated Pokemon.'}end
        choose('SHINY ODDS',values,function(v)E.wildOdds.set(E.session(),v)end)
      end},
      {label='Settings',help='Protection, capture balls, speed and limits.',action=settings},
      {label=C.baseline and 'Hunt controls' or 'Close',help=C.message,action=function()
        if C.baseline then
          push('HUNT CONTROLS',{
            {label='Keep result & stop',help='Keep the current game state. Save normally afterward.',action=function() C.stop(); S.hide() end},
            {label='Return to game',help='Closes this screen. A paused hunt stays paused.',action=S.hide},
            {label='Back',action=back},
          })
        else S.hide() end
      end},
    },true)
    if E.dualScreenDetected and E.dualScreenDetected() then
      table.insert(S.pages[#S.pages].rows,6,{
        label=function()return 'Dual Screen odds: '..(E.wildOdds.getDualScreen(E.session()) and 'ON' or 'OFF')end,
        help='Use selected odds for the Wild Pokemon button. Save normally.',
        action=function()
          if C.baseline then S.notice='Stop the current hunt before changing odds.';return end
          E.wildOdds.setDualScreen(E.session(),not E.wildOdds.getDualScreen(E.session()));E.persist(C)
        end,
      })
    end
  end
  function S.show()
    S.active=true; S.home()
    Stack.push('shiny_hunter',S,{fullscreen=true})
  end
  function S.hide()
    S.active=false; Stack.pop('shiny_hunter')
    local Start=require('src.ui.game3.start_menu')
    if Start.isOpen() then Start.close(true) end
  end
  function S.handleInput(input)
    if input:wasPressed('b') or input:wasPressed('l') or input:wasPressed('start') then back(); return end
    local p=S.pages[#S.pages]; if not p then return end
    local delta=input:wasPressed('up') and -1 or input:wasPressed('down') and 1 or input:wasPressed('left') and -6 or input:wasPressed('right') and 6 or 0
    if delta~=0 then p.cursor=(p.cursor-1+delta)%#p.rows+1; S.notice=nil end
    if input:wasPressed('a') then local r=p.rows[p.cursor]; if r.action then r.action() end end
  end
  function S.draw() V.draw(S) end
  function S.update(dt) S.elapsed=S.elapsed+(dt or 0) end
  return S
end
