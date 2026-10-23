-- Offline-verified seed bank; only bounded Sudoku symmetries run on the device.
-- Four 81-cell arrays and at most 20 undo records stay within the 64 KiB VM.
local fixed,board,solution,notes={},{},{},{}
local selected,note_mode,page=1,false,"board"
local bx,by,cell=0,0,0
local history={}
local difficulty,mistakes,hints,elapsed=1,0,3,0
local completed=false
local started,finished,best={0,0,0},{0,0,0},{0,0,0}
local dirty,last_edit,last_save,last_tick,saved_elapsed=false,0,0,0,0
local save_error=false
local function name(d)
  return ({app.tr("Easy","简单"),app.tr("Medium","中等"),app.tr("Hard","困难")})[d]
end
local function time_text(ms)
  local s=math.floor(ms/1000);return string.format("%02d:%02d",math.floor(s/60),s%60)
end
local function mark_dirty()
  local now=app.millis()
  if not dirty then last_save=now end
  dirty,last_edit=true,now
end
local function advance()
  local now=app.millis()
  if page=="board" and not completed then elapsed=math.min(359999000,elapsed+(now-last_tick)%4294967296) end
  last_tick=now
end
local function save()
  if not dirty and elapsed==saved_elapsed then return true end
  -- One bounded record keeps board, timer and statistics consistent on retry.
  local out={3,difficulty,mistakes,hints,elapsed,selected,note_mode and 1 or 0,completed and 1 or 0}
  for _,values in ipairs({started,finished,best}) do for i=1,3 do out[#out+1]=values[i] end end
  local data=table.concat(out,",").."|"..table.concat(fixed).."|"..table.concat(board).."|"..table.concat(solution).."|"..table.concat(notes,",")
  if not app.write("game",data) then save_error=true;return false end
  dirty=false;save_error=false;last_save=app.millis();saved_elapsed=elapsed;return true
end
local function shuffle(t)
  for i=#t,2,-1 do local j=math.random(i);t[i],t[j]=t[j],t[i] end
  return t
end
local function reset(tier)
  -- Nine fixed-length records, three per tier; no solver/search in a callback.
  local offset=((tier-1)*3+math.random(3)-1)*163
  local data=app.asset("assets/puzzles.txt",offset,162)
  if not data or #data~=162 then error("Sudoku seed asset unavailable") end
  fixed={};board={};solution={};notes={};history={}
  local digits=shuffle({1,2,3,4,5,6,7,8,9})
  local bands,stacks=shuffle({0,1,2}),shuffle({0,1,2})
  local rows,cols={},{}
  for _,b in ipairs(bands) do for _,r in ipairs(shuffle({0,1,2})) do rows[#rows+1]=b*3+r end end
  for _,b in ipairs(stacks) do for _,c in ipairs(shuffle({0,1,2})) do cols[#cols+1]=b*3+c end end
  local transpose=math.random(2)==1
  for r=0,8 do for c=0,8 do
    local old=transpose and cols[c+1]*9+rows[r+1]+1 or rows[r+1]*9+cols[c+1]+1
    local i=r*9+c+1;local v=tonumber(data:sub(old,old))
    fixed[i]=v==0 and 0 or digits[v];board[i]=fixed[i]
    solution[i]=digits[tonumber(data:sub(old+81,old+81))];notes[i]=0
  end end
  difficulty=tier;started[tier]=started[tier]+1
  selected,note_mode,mistakes,hints,elapsed,completed=1,false,0,3,0,false
  page="board";last_tick=app.millis();mark_dirty()
end
local function check_complete()
  if completed then return end
  for i=1,81 do if board[i]~=solution[i] then return end end
  completed=true;finished[difficulty]=finished[difficulty]+1
  local seconds=math.max(1,math.floor(elapsed/1000))
  if best[difficulty]==0 or seconds<best[difficulty] then best[difficulty]=seconds end
end
local function remember()
  history[#history+1]={selected,board[selected],notes[selected]}
  if #history>20 then table.remove(history,1) end
end
local function edit(value,as_hint)
  if fixed[selected]>0 or completed then return end
  if as_hint and hints==0 then return end
  if not note_mode and board[selected]==value and notes[selected]==0 then return end
  remember()
  if note_mode and value>0 and not as_hint then notes[selected]=notes[selected]~(1<<(value-1));board[selected]=0
  else
    if as_hint then hints=hints-1
    elseif value>0 and value~=solution[selected] then mistakes=mistakes+1 end
    board[selected]=value;notes[selected]=0
  end
  check_complete();mark_dirty()
end
local function hint()
  if hints==0 or completed then return end
  if fixed[selected]>0 or board[selected]==solution[selected] then
    for i=1,81 do if fixed[i]==0 and board[i]~=solution[i] then selected=i;break end end
  end
  edit(solution[selected],true)
end
local function show()
  app.clear();app.title(save_error and app.tr("Sudoku · Save failed","数独 · 保存失败") or app.tr("Sudoku","数独"));app.canvas()
  local w,h=app.size()
  if page=="new" then
    app.text(0,0,w,42,app.tr("Choose a new puzzle","选择新题难度"),2,0)
    app.text(0,44,w,40,app.tr("This replaces the current puzzle.","开始后将替换当前题目。"),0,0,6)
    for d=1,3 do
      app.button(29+d,0,94+(d-1)*56,w,46,name(d).." · "..({43,35,29})[d]..app.tr(" clues"," 个已知数"),d==difficulty and 2 or 0)
    end
    app.button(24,0,h-48,w,42,app.tr("Keep playing","继续当前题目"),0);return
  elseif page=="restart" then
    app.text(0,h*.18,w,90,app.tr("Restart this puzzle?","重做当前题目？"),2,1)
    app.button(24,0,h*.55,(w-12)/2,50,app.tr("Cancel","取消"),0)
    app.button(36,(w+12)/2,h*.55,(w-12)/2,50,app.tr("Restart","重新开始"),3);return
  elseif page=="stats" then
    app.text(0,0,w,42,app.tr("Your record","解题记录"),2,0)
    for d=1,3 do
      local y=58+(d-1)*90
      app.text(0,y,w,32,name(d).." · "..finished[d].." / "..started[d],1,0)
      app.text(0,y+34,w,32,app.tr("Best: ","最快：")..(best[d]>0 and time_text(best[d]*1000) or app.tr("No record","暂无记录")),0,0,6)
    end
    app.button(24,0,h-48,w,42,app.tr("Back to puzzle","返回题目"),0);return
  elseif page=="menu" then
    local labels={app.tr("Use hint · ","使用提示 · 剩余 ")..hints,app.tr("New puzzle","选择新题"),app.tr("Restart puzzle","重做当前题目"),app.tr("Statistics","解题记录")}
    local ids={34,25,35,33}
    app.text(0,0,w,42,name(difficulty).." · "..time_text(elapsed),2,0)
    for i,label in ipairs(labels) do app.button(ids[i],0,58+(i-1)*58,w,48,label,0) end
    app.button(24,0,h-48,w,42,app.tr("Continue","继续游戏"),3);return
  end
  local filled=0;for i=1,81 do if board[i]>0 then filled=filled+1 end end
  app.text(0,0,w,36,completed and app.tr("Puzzle complete!","解题成功！") or name(difficulty).." · "..time_text(elapsed),2,0)
  app.text(0,38,w,28,filled.." / 81"..app.tr(" · Errors "," · 错误 ")..mistakes..app.tr(" · Hints "," · 提示 ")..hints,0,0,6)
  local landscape=w>h*1.3
  local side=math.floor(math.min(landscape and w*.55 or w,h-(landscape and 84 or 222)))
  cell=side/9;bx=landscape and 0 or (w-side)/2;by=76
  local sr,sc=math.floor((selected-1)/9),(selected-1)%9
  for i=1,81 do
    local r,c=math.floor((i-1)/9),(i-1)%9;local x,y=bx+c*cell,by+r*cell
    local chosen=i==selected
    if chosen or r==sr or c==sc or (board[selected]>0 and board[selected]==board[i]) then
      app.box(x+1,y+1,cell-2,cell-2,chosen and 10 or 13)
    end
    if board[i]>0 then
      app.text(x+1,y+1,cell-2,cell-2,tostring(board[i]),fixed[i]>0 and cell>=36 and 2 or 1,1,0)
      if board[i]~=solution[i] then app.line(x+cell*.3,y+cell*.85,cell*.4,1,0,0,2) end
    elseif notes[i]>0 then
      local label="";for d=1,9 do if notes[i] & (1<<(d-1))~=0 then label=label..d end end
      app.text(x+2,y+2,cell-4,cell-4,label,0,1,6)
    end
  end
  for i=0,9 do
    app.line(bx,by+i*cell,side,1,0,0,i%3==0 and 3 or 1)
    app.line(bx+i*cell,by,1,side,0,0,i%3==0 and 3 or 1)
  end
  app.hit(1,bx,by,side,side)
  local px=landscape and side+16 or 0
  local pw=landscape and w-px or w
  local y=landscape and by+20 or by+side+10
  local kh=landscape and 50 or 36
  local kw=(pw-24)/5
  for i=1,10 do
    local row=math.floor((i-1)/5);local col=(i-1)%5
    app.button(1+i,px+col*(kw+6),y+row*(kh+6),kw,kh,i==10 and app.tr("Erase","擦除") or tostring(i),i==10 and 0 or 1)
  end
  y=y+2*(kh+6)+8
  for i,label in ipairs({note_mode and app.tr("Notes on","笔记开") or app.tr("Notes","笔记"),app.tr("Undo","撤销"),app.tr("More","更多")}) do
    app.button(i+19,px+(i-1)*(pw+8)/3,y,(pw-16)/3,36,label,i==1 and note_mode and 2 or 0)
  end
end
local function parse(data)
  local values,token={},""
  if data then for i=1,#data+1 do local c=data:sub(i,i)
    if c=="," or c=="" then
      if token~="" then values[#values+1]=tonumber(token) or -1 end;token=""
    else token=token..c end
  end end
  return values
end
local function load()
  local data=app.read("game");if not data then return false end
  local parts,token={},""
  for i=1,#data+1 do local c=data:sub(i,i)
    if c=="|" or c=="" then parts[#parts+1]=token;token="" else token=token..c end
  end
  if #parts==5 then
    local values=parse(parts[1])
    if #values~=17 or values[1]~=3 then return false end
    difficulty,mistakes,hints,elapsed,selected=values[2],values[3],values[4],values[5],values[6]
    note_mode,completed=values[7]==1,values[8]==1
    for _,v in ipairs(values) do if v<0 or v%1~=0 or v>359999000 then return false end end
    if difficulty<1 or difficulty>3 or hints>3 or selected<1 or selected>81 then return false end
    for i=1,3 do started[i]=values[8+i];finished[i]=values[11+i];best[i]=values[14+i] end
    for block,values_array in ipairs({fixed,board,solution}) do
      if #parts[block+1]~=81 then return false end
      for i=1,81 do values_array[i]=tonumber(parts[block+1]:sub(i,i)) or -1 end
    end
    notes=parse(parts[5]);if #notes~=81 then return false end
  elseif #parts==1 then
    -- Read the original 324 CSV values directly into the four reused arrays.
    local arrays={fixed,board,solution,notes};local count=0;token=""
    for i=1,#data+1 do local c=data:sub(i,i)
      if c=="," or c=="" then
        if token~="" then
          count=count+1;if count>324 then return false end
          arrays[math.floor((count-1)/81)+1][(count-1)%81+1]=tonumber(token) or -1
        end
        token=""
      else token=token..c end
    end
    if count~=324 then return false end
    started[1]=1
  else return false end
  for block,values in ipairs({fixed,board,solution,notes}) do
    for i=1,81 do local v=values[i]
      if v<0 or v%1~=0 or v>(block==4 and 511 or 9) then return false end
    end
  end
  for i=1,81 do
    if solution[i]==0 or (fixed[i]>0 and (board[i]~=fixed[i] or solution[i]~=fixed[i])) or (completed and board[i]~=solution[i]) then return false end
  end
  -- Reject corrupt solution rows/columns/boxes instead of showing an unsolvable save.
  for r=0,8 do
    local row,col,box=0,0,0
    for c=0,8 do
      row=row|(1<<solution[r*9+c+1]);col=col|(1<<solution[c*9+r+1])
      local i=(math.floor(r/3)*3+math.floor(c/3))*9+(r%3)*3+c%3+1
      box=box|(1<<solution[i])
    end
    if row~=1022 or col~=1022 or box~=1022 then return false end
  end
  if #parts==1 then completed=false;check_complete();mark_dirty() end
  saved_elapsed=elapsed;return true
end

return {
  on_start=function()
    last_save,last_tick=app.millis(),app.millis()
    if not load() then started,finished,best={0,0,0},{0,0,0},{0,0,0};reset(1) end
    show()
  end,
  on_resize=show,
  on_select=function(id,_,x,y)
    advance()
    if page=="board" then
      if id==1 and x and x>=0 then
        local c,r=math.floor((x-bx)/cell),math.floor((y-by)/cell)
        if c>=0 and r>=0 and c<9 and r<9 then selected=r*9+c+1 end
      elseif id>=2 and id<=11 then edit(id==11 and 0 or id-1,false)
      elseif id==20 then note_mode=not note_mode;mark_dirty()
      elseif id==21 and not completed then
        local old=table.remove(history);if old then board[old[1]]=old[2];notes[old[1]]=old[3];selected=old[1];mark_dirty() end
      elseif id==22 then page="menu" end
    elseif id==24 then page="board"
    elseif page=="menu" then
      if id==25 then page="new" elseif id==33 then page="stats"
      elseif id==34 then hint();page="board" elseif id==35 then page="restart" end
    elseif page=="new" and id>=30 and id<=32 then reset(id-29)
    elseif page=="restart" and id==36 then
      for i=1,81 do board[i]=fixed[i];notes[i]=0 end
      history={};mistakes,hints,elapsed,completed=0,3,0,false;started[difficulty]=started[difficulty]+1;page="board";mark_dirty()
    end
    last_tick=app.millis();show()
  end,
  on_swipe=function(_,direction)
    if page~="board" then return end
    local d=({left=-1,right=1,up=-9,down=9})[direction]
    if d then selected=math.max(1,math.min(81,selected+d));show() end
  end,
  on_tick=function()
    local previous=math.floor(elapsed/10000);advance()
    local now=app.millis();local had_error=save_error
    if (dirty and ((now-last_edit)%4294967296>=2000 or (now-last_save)%4294967296>=10000)) or
      (not dirty and elapsed~=saved_elapsed and (now-last_save)%4294967296>=10000) then
      if not save() then dirty=true;last_edit,last_save=app.millis(),app.millis() end
    end
    if had_error~=save_error or (page=="board" and math.floor(elapsed/10000)~=previous) then show() end
  end,
  on_stop=function() advance();if not save() then error("progress save failed") end end,
  on_back=function()
    advance()
    if page~="board" then page="board";last_tick=app.millis();show()
    elseif save() then app.exit() else show() end
  end,
}
