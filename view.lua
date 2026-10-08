-- RS native small-font atlases do not render reliably in these compact mod menus.
-- Keep measurement and drawing on the same readable native face.
local function collectionFont()
 local v=require('src.core.GameVersion').get()
 return (v=='ruby' or v=='sapphire') and 'normal' or nil
end
return function(M)
  local V={}
  local Window=require('src.ui.game3.window')
  local Font=require('src.ui.game3.frlg_font')
  local Pokemon=require('src.core.game3.pokemon')
  local function text(value,x,y,width,small,colors)
    value=tostring(value or '')
    if Font.measure(value,{small=collectionFont()==nil and small})>width then
      while #value>0 and Font.measure(value..'...',{small=collectionFont()==nil and small})>width do value=value:sub(1,-2) end
      value=value..'...'
    end
    Window.printPx(value,x,y,{maxWidth=width,small=collectionFont()==nil and small,colors=colors})
  end
  local function frame(x,y,w,h,s) Window.userFrame(Window.template(x,y,w,h),s.frameType or 0) end
  function V.draw(s)
    local c,p=s.controller,s.pages[#s.pages]
    love.graphics.setColor(.78,.88,.9,1); love.graphics.rectangle('fill',0,0,240,160)
    love.graphics.setColor(0,123/255,197/255,1); love.graphics.rectangle('fill',0,0,240,16)
    love.graphics.setColor(1,1,1,1)
    text(p.title,8,0,181,false,Font.COLOR.WHITE)
    text(c.state=='found' and 'FOUND' or c.state=='paused' and 'PAUSE' or 'READY',199,0,35,true,Font.COLOR.WHITE)
    local left,width=1,28
    if p.portrait then
      frame(1,3,10,13,s); left,width=13,16
      local mon=(c.found and c.found.mon) or c.last
      local species=c.config.species~=0 and c.config.species or mon and M.species(mon) or 1
      local pid=mon and M.pid(mon) or 0
      local pic=Pokemon.frontPic(species,0,true,pid)
      if pic and pic.image then love.graphics.draw(pic.image,16,26) end
      text(Pokemon.name(species),12,90,74,true)
      text('Checks: '..c.attempts,12,102,74,true)
      text(string.format('%dm %02ds',math.floor(c.elapsed/60),math.floor(c.elapsed%60)),12,114,74,true)
    end
    frame(left,3,width,13,s)
    local first=math.max(1,math.min(p.cursor-5,#p.rows-5))
    for i=first,math.min(#p.rows,first+5) do
      local row=p.rows[i]; local y=28+(i-first)*16
      if i==p.cursor then
        love.graphics.setColor(.82,.91,.96,1); love.graphics.rectangle('fill',left*8+1,y,width*8-2,16)
        love.graphics.setColor(1,1,1,1); Window.cursorPx(left*8+2,y)
      end
      text(type(row.label)=='function' and row.label() or row.label,left*8+11,y,width*8-16,p.small)
    end
    frame(1,17,28,2,s)
    local row=p.rows[p.cursor]
    text(s.notice or (row and row.help) or 'A: choose   B/L: back   Left/Right: page',12,136,216,true)
  end
  function V.hud(c,viewport)
    love.graphics.push('all')
    love.graphics.translate(viewport.gameX or 0,viewport.gameY or 0)
    love.graphics.scale((viewport.gameWidth or 240)/240,(viewport.gameHeight or 160)/160)
    love.graphics.setColor(0,.32,.55,.93); love.graphics.rectangle('fill',0,0,240,13)
    love.graphics.setColor(1,1,1,1)
    text((c.state=='recording' and 'REC ' or 'HUNT ')..c.attempts..' | '..math.floor(c.elapsed)..'s | START: pause',5,0,230,true,Font.COLOR.WHITE)
    love.graphics.pop()
  end
  return V
end
