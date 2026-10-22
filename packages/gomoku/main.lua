-- UI, rules, saves and opponent all run in the downloaded Lua package.
local n,board,moves,winner,computer=9,{}, {},0,true
local menu,confirm,thinking=false,false,false
local scan,best,best_score=1,0,-1
local cursor=41
local bx,by,step,side=0,0,0,0
local directions={{1,0},{0,1},{1,1},{1,-1}}
local function at(r,c)
  if r<0 or c<0 or r>=n or c>=n then return -1 end
  return board[r*n+c+1] or 0
end
local function strength(index,color)
  local r,c=math.floor((index-1)/n),(index-1)%n
  local result=0
  for _,d in ipairs(directions) do
    local count,open=1,0
    for _,sign in ipairs({-1,1}) do
      local k=1
      while k<5 and at(r+d[1]*k*sign,c+d[2]*k*sign)==color do count=count+1;k=k+1 end
      if at(r+d[1]*k*sign,c+d[2]*k*sign)==0 then open=open+1 end
    end
    if count>=5 then return 1000000 end
    if open>0 then result=result+({2,15,180,12000})[count]*(open==2 and 5 or 1) end
  end
  return result
end
local function save()
  local data=tostring(n)..","..(computer and "1" or "0")
  for _,i in ipairs(moves) do data=data..","..i end
  app.write("game",data)
end
local function place(i)
  if winner~=0 or i<1 or i>n*n or board[i]~=0 then return false end
  local color=#moves%2+1
  board[i]=color;moves[#moves+1]=i;cursor=i
  if strength(i,color)>=1000000 then winner=color elseif #moves==n*n then winner=3 end
  return true
end
local function begin_ai()
  thinking=computer and #moves%2==1 and winner==0
  scan,best,best_score=1,0,-1
end
local function reset()
  board={};moves={};winner=0;thinking=false
  for i=1,n*n do board[i]=0 end
  cursor=math.floor(n*n/2)+1;save()
end
local function show()
  app.clear();app.title(app.tr("Gomoku","五子棋"));app.canvas()
  local w,h=app.size()
  if confirm then
    app.text(0,h*.2,w,90,app.tr("Start a new game?","重新开一局？"),2,1)
    app.button(20,0,h*.55,(w-12)/2,54,app.tr("Continue","继续对局"),0)
    app.button(21,(w+12)/2,h*.55,(w-12)/2,54,app.tr("New game","重新开始"),3)
    return
  end
  if menu then
    app.text(0,0,w,52,app.tr("Next game","下一局设置"),2,0)
    app.button(22,0,72,w,54,(n==9 and "9 × 9" or "15 × 15")..app.tr("  · Board size","  · 棋盘大小"),0)
    app.button(23,0,142,w,54,computer and app.tr("Play the computer","人机对弈") or app.tr("Two players","双人对弈"),0)
    app.text(0,212,w,70,app.tr("Changing these options starts a new game.","切换设置后将开始新的一局。"),0,0,6)
    app.button(24,0,300,w,54,app.tr("Play","开始对局"),3)
    return
  end
  local turn=winner==1 and app.tr("Black wins","黑棋获胜") or winner==2 and app.tr("White wins","白棋获胜") or
    winner==3 and app.tr("Draw","和棋") or thinking and app.tr("Thinking…","正在思考…") or
    (#moves%2==0 and app.tr("Black to play","轮到黑棋") or app.tr("White to play","轮到白棋"))
  app.circle(0,13,20,20,#moves%2==0 and 0 or 15)
  app.circle(0,13,20,20,0,0,1)
  app.text(32,0,w-32,46,turn,2,0)
  app.text(0,48,w,28,app.tr("MOVE ","第 ")..#moves..app.tr(" · Five in a row"," 手 · 连成五子获胜"),0,0,6)
  side=math.floor(math.min(w,h-225));bx=(w-side)/2;by=86
  local margin=math.max(15,side/(n+1));step=(side-2*margin)/(n-1)
  app.box(bx,by,side,side,15,8)
  local gx,gy=bx+margin,by+margin
  for j=0,n-1 do
    app.line(gx,gy+j*step,side-2*margin,1,6)
    app.line(gx+j*step,gy,1,side-2*margin,6)
  end
  for _,r in ipairs(n==9 and {2,4,6} or {3,7,11}) do
    for _,c in ipairs(n==9 and {2,4,6} or {3,7,11}) do app.circle(gx+c*step-2,gy+r*step-2,4,4,0) end
  end
  local diameter=step*.81
  for i=1,n*n do
    local x,y=gx+(i-1)%n*step,gy+math.floor((i-1)/n)*step
    if board[i]~=0 then
      app.circle(x-diameter/2,y-diameter/2,diameter,diameter,board[i]==1 and 0 or 15)
      if board[i]==2 then app.circle(x-diameter/2,y-diameter/2,diameter,diameter,0,0,2) end
      if i==moves[#moves] then app.box(x-2,y-2,4,4,board[i]==1 and 15 or 0) end
    elseif i==cursor then
      app.box(x-diameter/2,y-diameter/2,diameter,diameter,6,3,1)
    end
  end
  app.hit(1,bx,by,side,side)
  local y=by+side+10
  for i,label in ipairs({"←","↑","↓","→"}) do app.button(i+1,(i-1)*(w+6)/4,y,(w-18)/4,38,label,0) end
  y=y+48
  for i,label in ipairs({app.tr("Undo","悔棋"),app.tr("New game","新对局"),app.tr("Options","设置")}) do
    app.button(i+5,(i-1)*(w+8)/3,y,(w-16)/3,44,label,i==3 and 2 or 0)
  end
end
local function ai_tick()
  if not thinking or menu or confirm then return end
  -- Bounded incremental search; yields between batches so e-ink input stays responsive.
  local checked=0
  while scan<=n*n and checked<18 do
    local i=scan;scan=scan+1
    if board[i]==0 then
      local r,c=math.floor((i-1)/n),(i-1)%n
      local nearby=false
      for dr=-1,1 do for dc=-1,1 do if at(r+dr,c+dc)>0 then nearby=true end end end
      if nearby then
        local attack,defend=strength(i,2),strength(i,1)
        local score=attack>=1000000 and 3000000 or defend>=1000000 and 2000000 or attack+defend*.95
        score=score-math.abs(r-(n-1)/2)-math.abs(c-(n-1)/2)
        if score>best_score then best,best_score=i,score end
        checked=checked+1
      end
    end
  end
  if scan>n*n then if best>0 then place(best);save() end;thinking=false;show() end
end
return {
  on_start=function()
    local data=app.read("game");local values={};local token=""
    if data then for i=1,#data+1 do local c=data:sub(i,i);if c=="," or c=="" then values[#values+1]=tonumber(token) or -1;token="" else token=token..c end end end
    if values[1]==9 or values[1]==15 then n=values[1];computer=values[2]~=0 end
    reset()
    for i=3,#values do if values[i]%1~=0 or not place(values[i]) then break end end
    save();begin_ai();show()
  end,
  on_resize=show,
  on_tick=ai_tick,
  on_select=function(id,_,x,y)
    if id==20 then confirm=false
    elseif id==21 then confirm=false;reset()
    elseif id==22 then n=n==9 and 15 or 9;reset()
    elseif id==23 then computer=not computer;reset()
    elseif id==24 then menu=false
    elseif id==6 then
      thinking=false
      local count=computer and #moves%2==0 and 2 or 1
      for j=1,count do local i=table.remove(moves);if i then board[i]=0 end end
      winner=0;save()
    elseif id==7 then confirm=true
    elseif id==8 then menu=true
    elseif id>=2 and id<=5 then
      local delta=({-1,-n,n,1})[id-1];cursor=math.max(1,math.min(n*n,cursor+delta))
    elseif id==1 and not thinking then
      if x and x>=0 then
        local margin=(side-step*(n-1))/2
        local c=math.floor((x-bx-margin)/step+.5);local r=math.floor((y-by-margin)/step+.5)
        if r<0 or c<0 or r>=n or c>=n then return end
        cursor=r*n+c+1
      end
      if place(cursor) then save();begin_ai() end
    end
    show()
  end,
  on_back=function() if menu or confirm then menu=false;confirm=false;begin_ai();show() else app.exit() end end,
}
