local board,history={},{}
local turn,winner,selected=1,0,0
local computer,menu,confirm=false,false,false
local scan,has_move,ai_from,ai_to,ai_score=0,false,0,0,-1e9
local bx,by,cell=0,0,0
local names={[1]={"K","A","E","H","R","C","P"},[-1]={"K","A","E","H","R","C","P"}}
local chinese={[1]={"帅","仕","相","马","车","炮","兵"},[-1]={"将","士","象","马","车","炮","卒"}}
local value={10000,200,200,400,900,450,100}
local function rc(i) return math.floor((i-1)/9),(i-1)%9 end
local function side(v) return v>0 and 1 or v<0 and -1 or 0 end
local function palace(r,c,color) return c>=3 and c<=5 and (color==1 and r>=7 or color==-1 and r<=2) end
local function between(a,b)
  local r,c=rc(a);local rr,cc=rc(b)
  if r~=rr and c~=cc then return -1 end
  local step=r==rr and (cc>c and 1 or -1) or (rr>r and 9 or -9)
  local count=0;for i=a+step,b-step,step do if board[i]~=0 then count=count+1 end end
  return count
end
local function pseudo(a,b)
  if a==b or a<1 or a>90 or b<1 or b>90 then return false end
  local piece,color=math.abs(board[a]),side(board[a]);if piece==0 or side(board[b])==color then return false end
  local r,c=rc(a);local rr,cc=rc(b);local dr,dc=rr-r,cc-c;local ar,ac=math.abs(dr),math.abs(dc)
  if piece==1 then
    if math.abs(board[b])==1 and c==cc and between(a,b)==0 then return true end
    return ar+ac==1 and palace(rr,cc,color)
  elseif piece==2 then return ar==1 and ac==1 and palace(rr,cc,color)
  elseif piece==3 then return ar==2 and ac==2 and (color==1 and rr>=5 or color==-1 and rr<=4) and board[a+dr/2*9+dc/2]==0
  elseif piece==4 then
    if ar==2 and ac==1 then return board[a+(dr>0 and 9 or -9)]==0 end
    if ar==1 and ac==2 then return board[a+(dc>0 and 1 or -1)]==0 end
  elseif piece==5 then return between(a,b)==0
  elseif piece==6 then return between(a,b)==(board[b]==0 and 0 or 1)
  elseif piece==7 then
    if dc==0 and dr==-color then return true end
    return dr==0 and ac==1 and (color==1 and r<=4 or color==-1 and r>=5)
  end
  return false
end
local function check(color)
  local king=0;for i=1,90 do if board[i]==color then king=i;break end end
  if king==0 then return true end
  for i=1,90 do if side(board[i])==-color and pseudo(i,king) then return true end end
  return false
end
local function legal(a,b)
  if side(board[a])~=turn or not pseudo(a,b) then return false end
  local moving,captured=board[a],board[b];board[b]=moving;board[a]=0
  local safe=not check(turn)
  board[a]=moving;board[b]=captured;return safe
end
local function save()
  local data=turn..","..(computer and 1 or 0)
  for i=1,90 do data=data..","..board[i] end
  app.write("game",data)
end
local function evaluate_next()
  scan=1;has_move=false;ai_from=0;ai_to=0;ai_score=-1e9
end
local function reset()
  for i=1,90 do board[i]=0 end
  local back={5,4,3,2,1,2,3,4,5}
  for c=0,8 do board[c+1]=-back[c+1];board[82+c]=back[c+1] end
  board[20]=-6;board[26]=-6;board[65]=6;board[71]=6
  for c=0,8,2 do board[28+c]=-7;board[55+c]=7 end
  turn=1;winner=0;selected=0;history={};scan=0;save()
end
local function move(a,b)
  if not legal(a,b) then return false end
  history[#history+1]={a,b,board[a],board[b]};if #history>24 then table.remove(history,1) end
  local captured=board[b];board[b]=board[a];board[a]=0;selected=0
  if math.abs(captured)==1 then winner=turn;scan=0 else turn=-turn;evaluate_next() end
  save();return true
end
local function show()
  app.clear();app.title(app.tr("Chinese chess","中国象棋"));app.canvas()
  local w,h=app.size()
  if confirm then
    app.text(0,h*.2,w,90,app.tr("Start a new game?","重新开一局？"),2,1)
    app.button(10,0,h*.55,(w-12)/2,54,app.tr("Continue","继续对局"),0)
    app.button(11,(w+12)/2,h*.55,(w-12)/2,54,app.tr("New game","新对局"),3);return
  end
  if menu then
    app.text(0,20,w,70,app.tr("Opponent","选择对手"),2,1)
    app.button(12,0,120,w,56,computer and app.tr("Computer · casual","人机 · 休闲") or app.tr("Two players","双人对弈"),0)
    app.text(0,192,w,70,app.tr("Changing the opponent starts a new game.","切换对手后开始新的一局。"),0,0,6)
    app.button(13,0,290,w,54,app.tr("Play","开始对局"),3);return
  end
  local title=winner~=0 and (winner==1 and app.tr("Red wins","红方获胜") or app.tr("Black wins","黑方获胜")) or
    (computer and turn==-1 and scan>0) and app.tr("Thinking…","正在思考…") or
    turn==1 and app.tr("Red to play","轮到红方") or app.tr("Black to play","轮到黑方")
  app.text(0,0,w,44,title,2,0)
  app.text(0,46,w,28,check(turn) and app.tr("Check!","将军！") or app.tr("Tap a piece, then its destination","点击棋子，再点击目标位置"),0,0,6)
  cell=math.floor(math.min(w/9,(h-170)/10));bx=(w-cell*9)/2;by=86
  local gx,gy=bx+cell/2,by+cell/2
  for r=0,9 do app.line(gx,gy+r*cell,8*cell,1,6) end
  for c=0,8 do
    app.line(gx+c*cell,gy,1,4*cell,6);app.line(gx+c*cell,gy+5*cell,1,4*cell,6)
  end
  app.line(gx,gy,1,9*cell,0);app.line(gx+8*cell,gy,1,9*cell,0)
  app.text(gx,gy+4*cell,8*cell,cell,app.tr("R I V E R","楚 河                         汉 界"),0,1,6)
  for _,row in ipairs({0,7}) do
    app.line(gx+3*cell,gy+row*cell,2*cell,2*cell,6)
    app.line(gx+3*cell,gy+row*cell,2*cell,2*cell,6,1)
  end
  local diameter=cell*.83
  for i=1,90 do if board[i]~=0 then
    local r,c=rc(i);local x,y=gx+c*cell-diameter/2,gy+r*cell-diameter/2
    local black=board[i]<0
    app.circle(x,y,diameter,diameter,black and 0 or 15)
    app.circle(x,y,diameter,diameter,0,0,1)
    app.text(x+1,y+1,diameter-2,diameter-2,app.tr(names[side(board[i])][math.abs(board[i])],chinese[side(board[i])][math.abs(board[i])]),2,1,black and 15 or 0)
    if i==selected then app.box(x-2,y-2,diameter+4,diameter+4,0,3,2) end
  end end
  app.hit(1,bx,by,9*cell,10*cell)
  local y=by+10*cell+10
  for i,label in ipairs({app.tr("Undo","悔棋"),app.tr("New game","新对局"),app.tr("Opponent","对手")}) do
    app.button(i+1,(i-1)*(w+8)/3,y,(w-16)/3,44,label,0)
  end
end
local function tick()
  if scan==0 or menu or confirm or winner~=0 then return end
  -- One source piece per callback keeps move validation inside the VM quota.
  while scan<=90 do
    local a=scan;scan=scan+1
    if side(board[a])==turn then
      for b=1,90 do if legal(a,b) then
        has_move=true
        if computer and turn==-1 then
          local r,c=rc(b);local score=(value[math.abs(board[b])] or 0)*10-math.abs(c-4)
          if math.abs(board[a])==7 then score=score+r*2 end
          if score>ai_score then ai_score=score;ai_from=a;ai_to=b end
        else scan=0;show();return end
      end end
      break
    end
  end
  if scan>90 then
    scan=0
    if not has_move then winner=-turn
    elseif computer and turn==-1 and ai_from>0 then move(ai_from,ai_to) end
    show()
  end
end
return {
  on_start=function()
    local saved=app.read("game");local values={};local token=""
    if saved then for i=1,#saved+1 do local c=saved:sub(i,i);if c=="," or c=="" then values[#values+1]=tonumber(token) or 99;token="" else token=token..c end end end
    reset()
    local valid=#values==92 and (values[1]==1 or values[1]==-1)
    for i=3,#values do if values[i]%1~=0 or math.abs(values[i])>7 then valid=false end end
    if valid then turn=values[1];computer=values[2]==1;for i=1,90 do board[i]=values[i+2] end;evaluate_next();save() end
    show()
  end,
  on_resize=show,on_tick=tick,
  on_select=function(id,_,x,y)
    if id==10 then confirm=false
    elseif id==11 then confirm=false;reset()
    elseif id==12 then computer=not computer;reset()
    elseif id==13 then menu=false
    elseif id==2 then
      local repeats=computer and turn==1 and 2 or 1
      for j=1,repeats do local old=table.remove(history);if old then board[old[1]]=old[3];board[old[2]]=old[4];turn=side(old[3]) end end
      winner=0;scan=0;selected=0;save()
    elseif id==3 then confirm=true
    elseif id==4 then menu=true
    elseif id==1 and x and x>=0 and winner==0 and not(computer and turn==-1) then
      local c,r=math.floor((x-bx)/cell),math.floor((y-by)/cell)
      if c<0 or r<0 or c>8 or r>9 then return end
      local i=r*9+c+1
      if side(board[i])==turn then selected=i elseif selected>0 then move(selected,i) end
    end
    show()
  end,
  on_back=function() if menu or confirm then menu=false;confirm=false;show() else app.exit() end end,
}
