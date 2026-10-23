local board,score,best={},0,0
local undo_board,undo_score,confirm_reset
local save_error=false
local dirty,last_move,last_saved,saved_best=false,0,0,0
local function mark_dirty()
  local now=app.millis()
  if not dirty then last_saved=now end
  dirty,last_move=true,now
  if score>best then best=score end
end
local function spawn()
  local empty={}
  for i=1,16 do if board[i]==0 then empty[#empty+1]=i end end
  if #empty>0 then board[empty[math.random(#empty)]]=math.random(10)==1 and 4 or 2 end
end
local function save()
  if not dirty then return true end
  local data=tostring(score)
  for i=1,16 do data=data..","..board[i] end
  if not app.write("game",data) then return false end
  if best>saved_best then
    if not app.write("best",tostring(best)) then return false end
    saved_best=best
  end
  dirty=false;save_error=false;last_saved=app.millis();return true
end
local function reset()
  score=0;undo_board=nil
  for i=1,16 do board[i]=0 end
  spawn();spawn();mark_dirty()
end
local function available()
  for i=1,16 do
    if board[i]==0 or (i%4~=0 and board[i]==board[i+1]) or (i<=12 and board[i]==board[i+4]) then return true end
  end
  return false
end
local function show()
  app.clear();app.title(save_error and app.tr("2048 · Save failed", "2048 · 保存失败") or "2048");app.canvas()
  local w,h=app.size()
  if confirm_reset then
    app.text(0,h*.23,w,100,app.tr("Start a new game?", "开始新的一局？"),2,1)
    app.button(22,0,h*.55,(w-12)/2,58,app.tr("Keep playing", "继续游戏"),0)
    app.button(23,(w+12)/2,h*.55,(w-12)/2,58,app.tr("New game", "重新开始"),3)
    return
  end
  local side=math.max(80,math.min(w,h-190))
  local x=(w-side)/2
  app.text(x,0,side*.48,25,app.tr("SCORE", "本局得分"),0,0,6)
  app.text(x,27,side*.48,45,tostring(score),3,0)
  app.text(x+side*.52,0,side*.48,25,app.tr("BEST", "最高得分"),0,2,6)
  app.text(x+side*.52,27,side*.48,45,tostring(best),3,2)
  local y=80
  local gap=math.max(7,math.floor(side/48))
  local cell=(side-5*gap)/4
  app.box(x,y,side,side,10,14)
  local palette={[0]=12,[2]=15,[4]=12,[8]=10,[16]=7,[32]=5,[64]=3}
  for i=1,16 do
    local value=board[i]
    local cx=x+gap+((i-1)%4)*(cell+gap)
    local cy=y+gap+math.floor((i-1)/4)*(cell+gap)
    local shade=palette[value] or 0
    app.box(cx,cy,cell,cell,shade,9)
    if value>0 then app.text(cx+2,cy+2,cell-4,cell-4,tostring(value),cell>=64 and 3 or 1,1,shade<8 and 15 or 0) end
  end
  local button_y=y+side+10
  local unit=(side-18)/4
  for i,arrow in ipairs({"←","↑","↓","→"}) do
    app.button(i+16,x+(i-1)*(unit+6),button_y,unit,40,arrow,0)
  end
  local footer=button_y+50
  app.button(21,x,footer,(side-10)/2,40,app.tr("New game", "重新开始"),0)
  app.button(24,x+(side+10)/2,footer,(side-10)/2,40,app.tr("Undo", "悔一步"),0)
  if not available() then
    app.text(x,y+side/2-25,side,50,app.tr("Game over", "本局结束"),2,1,15)
  end
end
local function move(direction)
  local before={}; for i=1,16 do before[i]=board[i] end
  local previous_score,changed=score,false
  for line=0,3 do
    local positions,compact,merged={},{},{}
    for j=0,3 do
      local index
      if direction==1 then index=line*4+j+1 elseif direction==4 then index=line*4+4-j
      elseif direction==2 then index=j*4+line+1 else index=(3-j)*4+line+1 end
      positions[#positions+1]=index
      if board[index]~=0 then compact[#compact+1]=board[index] end
    end
    local i=1
    while i<=#compact do
      local value=compact[i]
      if compact[i+1]==value then value=value*2;score=score+value;i=i+1 end
      merged[#merged+1]=value;i=i+1
    end
    for j=1,4 do
      local value=merged[j] or 0
      if board[positions[j]]~=value then changed=true end
      board[positions[j]]=value
    end
  end
  if changed then undo_board,undo_score=before,previous_score;spawn();mark_dirty() end
  show()
end
return {
  on_resize=show,
  on_start=function()
    best=tonumber(app.read("best")) or 0
    saved_best=best;last_saved=app.millis()
    local saved=app.read("game")
    local numbers,token={},""
    if saved then
      for i=1,#saved+1 do
        local ch=string.sub(saved,i,i)
        if ch=="," or ch=="" then numbers[#numbers+1]=tonumber(token) or 0;token="" else token=token..ch end
      end
    end
    if #numbers==17 then score=numbers[1];for i=1,16 do board[i]=numbers[i+1] end
      best=math.max(best,score)
    else reset() end
    show()
  end,
  on_select=function(i)
    if i>=17 and i<=20 then move(i-16)
    elseif i==21 then confirm_reset=true;show()
    elseif i==22 then confirm_reset=false;show()
    elseif i==23 then confirm_reset=false;reset();show()
    elseif i==24 and undo_board then board,score=undo_board,undo_score;undo_board=nil;mark_dirty();show() end
  end,
  on_swipe=function(_,direction)
    if confirm_reset then return end
    local directions={left=1,up=2,down=3,right=4}
    if directions[direction] then move(directions[direction]) end
  end,
  on_tick=function()
    if not dirty then return end
    local now=app.millis()
    if (now-last_move)%4294967296>=2000 or (now-last_saved)%4294967296>=10000 then
      local had_error=save_error
      if not save() then
        last_move,last_saved=app.millis(),app.millis()
        save_error=true
      end
      if had_error~=save_error then show() end
    end
  end,
  on_stop=function() if not save() then error("progress save failed") end end,
  on_back=function()
    if confirm_reset then confirm_reset=false;show()
    elseif save() then app.exit()
    else save_error=true;show() end
  end,
}
