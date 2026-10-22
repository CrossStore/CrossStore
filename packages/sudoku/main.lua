-- A unique-solution seed transformed by digit/row/column symmetries.
local seed="530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local solved="534678912672195348198342567859761423426853791713924856961537284287419635345286179"
local fixed,board,solution,notes={},{},{},{}
local selected,note_mode,confirm=1,false,false
local bx,by,cell=0,0,0
local history={}
local function shuffle(t)
  for i=#t,2,-1 do local j=math.random(i);t[i],t[j]=t[j],t[i] end
  return t
end
local function save()
  local out="";for _,values in ipairs({fixed,board,solution,notes}) do
    for i=1,81 do out=out..tostring(values[i] or 0).."," end
  end
  app.write("game",out)
end
local function reset()
  fixed={};board={};solution={};notes={};history={}
  local digits=shuffle({1,2,3,4,5,6,7,8,9})
  local bands,stacks=shuffle({0,1,2}),shuffle({0,1,2})
  local rows,cols={},{}
  for _,b in ipairs(bands) do for _,r in ipairs(shuffle({0,1,2})) do rows[#rows+1]=b*3+r end end
  for _,b in ipairs(stacks) do for _,c in ipairs(shuffle({0,1,2})) do cols[#cols+1]=b*3+c end end
  local transpose=math.random(2)==1
  for r=0,8 do for c=0,8 do
    local old=transpose and cols[c+1]*9+rows[r+1]+1 or rows[r+1]*9+cols[c+1]+1
    local i=r*9+c+1;local v=tonumber(seed:sub(old,old))
    fixed[i]=v==0 and 0 or digits[v];board[i]=fixed[i];solution[i]=digits[tonumber(solved:sub(old,old))];notes[i]=0
  end end
  selected=1;save()
end
local function conflict(index)
  local value=board[index];if value==0 then return false end
  local r,c=math.floor((index-1)/9),(index-1)%9
  for i=1,81 do if i~=index and board[i]==value then
    local rr,cc=math.floor((i-1)/9),(i-1)%9
    if rr==r or cc==c or (math.floor(rr/3)==math.floor(r/3) and math.floor(cc/3)==math.floor(c/3)) then return true end
  end end
  return false
end
local function show()
  app.clear();app.title(app.tr("Sudoku","数独"));app.canvas()
  local w,h=app.size()
  if confirm then
    app.text(0,h*.2,w,90,app.tr("Start a new puzzle?","开始新的题目？"),2,1)
    app.button(24,0,h*.55,(w-12)/2,54,app.tr("Continue","继续游戏"),0)
    app.button(25,(w+12)/2,h*.55,(w-12)/2,54,app.tr("New puzzle","新的题目"),3)
    return
  end
  local filled,complete=0,true
  for i=1,81 do if board[i]>0 then filled=filled+1 end;if board[i]~=solution[i] then complete=false end end
  app.text(0,0,w,44,complete and app.tr("Puzzle complete!","解题成功！") or app.tr("A little focus, one square at a time.","专注当下，一格一步。"),1,0)
  app.text(0,47,w,25,tostring(filled).." / 81"..app.tr(" filled"," 已填"),0,0,6)
  local side=math.min(w,h-240);cell=side/9;bx=(w-side)/2;by=82
  local sr,sc=math.floor((selected-1)/9),(selected-1)%9
  for i=1,81 do
    local r,c=math.floor((i-1)/9),(i-1)%9;local x,y=bx+c*cell,by+r*cell
    local chosen=i==selected
    if chosen or r==sr or c==sc or (board[selected]>0 and board[selected]==board[i]) then
      app.box(x+1,y+1,cell-2,cell-2,chosen and 0 or 12)
    end
    if board[i]>0 then
      app.text(x+1,y+1,cell-2,cell-2,tostring(board[i]),fixed[i]>0 and 2 or 1,1,chosen and 15 or 0)
      if conflict(i) then app.line(x+cell*.3,y+cell*.84,cell*.4,1,chosen and 15 or 0,0,2) end
    elseif notes[i]>0 then
      local label="";for d=1,9 do if notes[i] & (1<<(d-1))~=0 then label=label..d end end
      app.text(x+2,y+2,cell-4,cell-4,label,0,1,chosen and 15 or 6)
    end
  end
  for i=0,9 do
    app.line(bx,by+i*cell,side,1,0,0,i%3==0 and 3 or 1)
    app.line(bx+i*cell,by,1,side,0,0,i%3==0 and 3 or 1)
  end
  app.hit(1,bx,by,side,side)
  local y=by+side+12
  local gap=6;local kw=(w-4*gap)/5
  for i=1,10 do
    local row=math.floor((i-1)/5);local col=(i-1)%5
    app.button(1+i,col*(kw+gap),y+row*46,kw,40,i==10 and app.tr("Erase","擦除") or tostring(i),i==10 and 0 or 1)
  end
  y=y+100
  for i,label in ipairs({note_mode and app.tr("Notes on","笔记开") or app.tr("Notes","笔记"),app.tr("Undo","撤销"),app.tr("New","新题")}) do
    app.button(i+19,(i-1)*(w+8)/3,y,(w-16)/3,42,label,i==1 and note_mode and 3 or 0)
  end
end
return {
  on_start=function()
    local saved=app.read("game");local values={};local token=""
    if saved then for i=1,#saved do local c=saved:sub(i,i);if c=="," then values[#values+1]=tonumber(token) or -1;token="" else token=token..c end end end
    local valid=#values==324
    for i,v in ipairs(values) do if v<0 or v%1~=0 or v>(i>243 and 511 or 9) then valid=false end end
    if valid then for i=1,81 do fixed[i]=values[i];board[i]=values[i+81];solution[i]=values[i+162];notes[i]=values[i+243] end else reset() end
    show()
  end,
  on_resize=show,
  on_select=function(id,_,x,y)
    if id==1 and x and x>=0 then
      local c,r=math.floor((x-bx)/cell),math.floor((y-by)/cell)
      if c>=0 and r>=0 and c<9 and r<9 then selected=r*9+c+1 end
    elseif id>=2 and id<=11 and fixed[selected]==0 then
      history[#history+1]={selected,board[selected],notes[selected]};if #history>20 then table.remove(history,1) end
      local value=id==11 and 0 or id-1
      if note_mode and value>0 then notes[selected]=notes[selected]~(1<<(value-1));board[selected]=0
      else board[selected]=value;notes[selected]=0 end
      save()
    elseif id==20 then note_mode=not note_mode
    elseif id==21 then local old=table.remove(history);if old then board[old[1]]=old[2];notes[old[1]]=old[3];save() end
    elseif id==22 then confirm=true
    elseif id==24 then confirm=false
    elseif id==25 then confirm=false;reset() end
    show()
  end,
  on_swipe=function(_,direction)
    local d=({left=-1,right=1,up=-9,down=9})[direction];if d then selected=math.max(1,math.min(81,selected+d));show() end
  end,
  on_back=function() if confirm then confirm=false;show() else app.exit() end end,
}
