return function(mod)
  assert(load(assert(mod:read("native_legality.lua")), "@shiny-hunter/native_legality.lua"))().install(mod)
  local function module(name) return assert(load(assert(mod:read(name..'.lua')),'@shiny_hunter/'..name..'.lua'))() end
  local Odds=module('odds');Odds.install(mod)
  module('acquisition_odds').install(mod,Odds)
  mod.exports.prepareDualScreenEncounter=function(enc,forceShiny)
    if not mod.find or not mod.find('frlg_dual_screen') or not mod.find(mod.id)
      or mod.options and mod.options:get('enabled')==false then return enc end
    return Odds.prepareDualScreen(enc,require('src.core.game3.runtime').getSession(),forceShiny==true)
  end
  local M=module('model')
  local E=module('adapter')(M,mod);E.wildOdds=Odds
  local C=module('controller')(M,E)
  local V=module('view')(M)
  local S=module('screen')(M,C,E,V)
  E.show=S.show; E.hide=S.hide
  local Help=require('src.ui.game3.help_system')
  local Stack=require('src.ui.game3.stack')
  local FixedStep=require('src.core.FixedStep')
  mod.exports.dualScreenProtocol=1
  mod.exports.dualScreenBusy=function() return C.running() or C.pendingReset~=nil or C.baseline~=nil end
  local loadedSession,helpLease
  local function bind(game)
    E.game=game
    local session=E.session()
    if not session then return end
    if session~=loadedSession and not C.baseline then
      loadedSession=session
      local saved=E.load()
      C.config=M.defaults(); C.history={}; C.attempts=0; C.elapsed=0
      if type(saved)=='table' and saved.format==1 then
        for k,v in pairs(C.config) do if type(saved.config)=='table' and type(saved.config[k])==type(v) then C.config[k]=M.copy(saved.config[k]) end end
        C.history=type(saved.history)=='table' and saved.history or {}
        C.attempts=tonumber(saved.attempts) or 0; C.elapsed=tonumber(saved.elapsed) or 0
      end
    end
  end
  mod.exports.show=function(game)
    local session=E.session()
    if not game or game.generation~=3 or game.phase~='field' or not session
      or (session.version~='firered' and session.version~='leafgreen' and session.version~='emerald' and session.version~='ruby' and session.version~='sapphire') then return false end
    bind(game)
    if C.running() then C.pause() end
    S.show();return true
  end
  local function safe(fn)
    local ok,why=pcall(fn)
    if not ok then
      C.pendingReset=nil; C.pause('Hunter error. Attempt stopped: '..tostring(why))
      mod.log:error('Shiny Hunter: %s',tostring(why))
    end
  end
  local function pauseRequested(input)
    if not C.running() or not input then return false end
    local queued=input.pressQueue or {}
    local requested=false
    for i=#queued,1,-1 do
      if queued[i]=='start' then table.remove(queued,i); requested=true end
    end
    if requested then C.pause() end
    return requested
  end
  mod.hooks:wrap('ui.start_menu.items',function(next,game,items)
    local result=next(game,items)
    local session=E.session()
    if type(result)~='table' or not session or (session.version~='firered' and session.version~='leafgreen' and session.version~='emerald' and session.version~='ruby' and session.version~='sapphire') then return result end
    for _,r in ipairs(result) do if r.id=='shiny_hunter' then return result end end
    local at=#result+1; for i,r in ipairs(result) do if r.id=='save' then at=i; break end end
    table.insert(result,at,{id='shiny_hunter',label='SHINY HUNTER',onSelect=function()
      bind(game)
      if C.running() then C.pause() else S.show() end
    end})
    return result
  end)
  mod.hooks:wrap('core.update',function(next,game,dt)
    if game.generation~=3 then
      if C.baseline then C.stop(true); S.hide() end
      return next(game,dt)
    end
    E.game=game
    if C.baseline and E.session()~=C.session then
      C.stop(true); S.hide(); C.message='Session changed. Hunt stopped.'
    end
    pauseRequested(game.input) -- User pause wins over a reset queued on the previous tick.
    if C.pendingReset then safe(C.restorePending) end
    if S.active and not S._frlgDetached then
      if not Stack.has('shiny_hunter') then S.active=false; return next(game,dt) end
      if not helpLease then helpLease={previous=Help.contextOverride} end
      Help.setContext(0)
      if game.input then
        if game.input.setButtonAlias then game.input:setButtonAlias('l',nil) end
        game.input:step(); safe(function() S.handleInput(game.input) end)
      end
      S.update(dt)
      return -- menu freezes scripts, battle actions and world; drawing remains live
    elseif helpLease then
      Help.setContext(helpLease.previous); helpLease=nil
    end
    if C.running() and E.requestedSpeed then
      local previous=game.speedOverride
      game.speedOverride=E.requestedSpeed
      local ok,result=pcall(next,game,dt)
      game.speedOverride=previous
      if not ok then error(result) end
      return result
    end
    return next(game,dt)
  end)
  mod.hooks:wrap('input.step',function(next,game,dt)
    if game~=E.game or not C.running() or (S.active and not S._frlgDetached) then return next(game,dt) end
    local input=game.input
    local buttons,presses={},{}
    for _,b in ipairs({'up','down','left','right','a','b','select'}) do if input:isDown(b) then buttons[b]=true end end
    local queued=input.pressQueue or {}
    if pauseRequested(input) then FixedStep:endFrame(); return next(game,dt) end
    for _,b in ipairs(queued) do
      if b~='l' and b~='r' then presses[b]=true end
    end
    local previousState=C.state
    safe(function()
      C.record(buttons,presses)
      C.tick(dt)
    end)
    -- Stop the current burst at every attempt/state boundary. All checks still
    -- run on every fixed tick; do not simulate unused ticks before a reset or
    -- keep advancing the world behind the found/paused menu at high speed.
    if C.pendingReset or C.state~=previousState then FixedStep:endFrame() end
    return next(game,dt)
  end)
  mod.hooks:wrap('input.key',function(next,game,event)
    if game==E.game and C.running() and event.phase=='pressed' and event.key=='f10' then C.pause(); return true end
    return next(game,event)
  end)
  mod.hooks:wrap('save.write',function(next,game)
    if game==E.game and C.running() then return false end
    return next(game)
  end)
  mod.hooks:wrap('render.hud',function(next,game,viewport)
    next(game,viewport)
    if game==E.game and S.active and not S._frlgDetached then
      love.graphics.push('all')
      love.graphics.translate(viewport.gameX or 0,viewport.gameY or 0)
      love.graphics.scale((viewport.gameWidth or 240)/240,(viewport.gameHeight or 160)/160)
      S.draw()
      love.graphics.pop()
    elseif game==E.game and C.running() then V.hud(C,viewport) end
  end)
end
