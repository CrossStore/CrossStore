local n,mines=9,10
local bomb,open,flag={},{},{}
local started,lost,won,flag_mode=false,false,false,false
local bx,by,cell=0,0,0
local elapsed,start_time=0,0
local confirm=false
local function neighbors(i,callback)
  local r,c=math.floor((i-1)/n),(i-1)%n
  for dr=-1,1 do for dc=-1,1 do
    local rr,cc=r+dr,c+dc
    if (dr~=0 or dc~=0) and rr>=0 and cc>=0 and rr<n and cc<n then callback(rr*n+cc+1) end
  end end
end
local function count(i)
  local value=0;neighbors(i,function(j) if bomb[j] then value=value+1 end end);return value
end
local function reset()
  bomb={};open={};flag={};started=false;lost=false;won=false;elapsed=0
end
local function seed(first)
  local safe={[first]=true};neighbors(first,function(j) safe[j]=true end)
  local choices={};for i=1,n*n do if not safe[i] then choices[#choices+1]=i end end
  for k=1,mines do local j=math.random(#choices);bomb[table.remove(choices,j)]=true end
  started=true;start_time=app.millis()
end
local function reveal(first)
  if flag[first] or open[first] or lost or won then return end
  if not started then seed(first) end
  if bomb[first] then lost=true;return end
  local queue={first};open[first]=true;local head=1
  while head<=#queue do
    local i=queue[head];head=head+1
    if count(i)==0 then neighbors(i,function(j)
      if not open[j] and not flag[j] and not bomb[j] then open[j]=true;queue[#queue+1]=j end
    end) end
  end
  local total=0;for i=1,n*n do if open[i] then total=total+1 end end
  won=total==n*n-mines
end
local function show()
  app.clear();app.title(app.tr("Minesweeper","扫雷"));app.canvas()
  local w,h=app.size()
  if confirm then
    app.text(0,h*.2,w,90,app.tr("Start a new field?","开始新的一局？"),2,1)
    app.button(4,0,h*.55,(w-12)/2,54,app.tr("Continue","继续游戏"),0)
    app.button(5,(w+12)/2,h*.55,(w-12)/2,54,app.tr("New game","重新开始"),3)
    return
  end
  local flags=0;for i=1,n*n do if flag[i] then flags=flags+1 end end
  app.text(0,0,w*.5,26,app.tr("MINES LEFT","剩余地雷"),0,0,6)
  app.text(0,28,w*.5,44,tostring(mines-flags),3,0)
  app.text(w*.5,0,w*.5,26,app.tr("TIME","用时"),0,2,6)
  app.text(w*.5,28,w*.5,44,tostring(elapsed).."s",3,2)
  local side=math.min(w,h-205);cell=side/n;bx=(w-side)/2;by=86
  app.box(bx,by,side,side,10,6)
  for i=1,n*n do
    local x=bx+(i-1)%n*cell;local y=by+math.floor((i-1)/n)*cell
    if open[i] then
      app.box(x+2,y+2,cell-4,cell-4,15,2)
      local value=count(i)
      if value>0 then app.text(x+2,y+2,cell-4,cell-4,tostring(value),2,1) end
    else
      app.box(x+3,y+3,cell-6,cell-6,flag[i] and 0 or 12,4)
      if flag[i] then app.text(x+2,y+2,cell-4,cell-4,"!",2,1,15)
      elseif lost and bomb[i] then
        app.circle(x+cell*.3,y+cell*.3,cell*.4,cell*.4,0)
        app.line(x+cell*.18,y+cell*.5,cell*.64,1,0)
        app.line(x+cell*.5,y+cell*.18,1,cell*.64,0)
      end
    end
  end
  app.hit(1,bx,by,side,side)
  local y=by+side+12
  app.text(0,y,w,30,lost and app.tr("Mine hit · Try again","踩到地雷，再来一局") or won and app.tr("All clear!","排雷成功！") or
    flag_mode and app.tr("Tap a cell to place a flag","点击格子插旗") or app.tr("Tap to reveal · Hold to flag","点击翻开 · 长按插旗"),0,1,6)
  app.button(2,0,y+42,(w-12)/2,48,flag_mode and app.tr("Flag mode","插旗模式") or app.tr("Reveal mode","翻开模式"),flag_mode and 3 or 0)
  app.button(3,(w+12)/2,y+42,(w-12)/2,48,app.tr("New game","新游戏"),0)
end
return {
  on_start=function() reset();show() end,
  on_resize=show,
  on_tick=function()
    if started and not lost and not won then
      local seconds=math.floor((app.millis()-start_time)/1000)
      -- Avoid a full e-ink refresh every second. Update the timer with moves.
      elapsed=seconds
    end
  end,
  on_select=function(id,gesture,x,y)
    if id==2 then flag_mode=not flag_mode
    elseif id==3 then confirm=true
    elseif id==4 then confirm=false
    elseif id==5 then confirm=false;reset()
    elseif id==1 and x and x>=0 and not lost and not won then
      local c,r=math.floor((x-bx)/cell),math.floor((y-by)/cell)
      if c<0 or r<0 or c>=n or r>=n then return end
      local i=r*n+c+1
      if flag_mode or gesture=="long" then if not open[i] then flag[i]=not flag[i] end else reveal(i) end
    end
    show()
  end,
  on_back=function() if confirm then confirm=false;show() else app.exit() end end,
}
