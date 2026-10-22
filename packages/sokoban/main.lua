local offsets={0,44,88,144,194,252,326,384,482,526,616,690,764,829,873,938,1020,1064,1129,1195,1269,1313,1378,1429,1480,1531,1581,1632,1683,1784,1828,1879,1930,1981,2037,2099,2176,2250,2322,2414,2458,2508,2566,2649,2666,2710,2768,2847,2913,2995,3067,3125,3175,3226,3324,3406,3450,3524,3575,3694,3796,3888,3968,4084,4176,4259,4387,4445,4517,4607,4689,4808,4920,5002,5092,5164,5276,5355,5445,5507,5619,5675,5741,5823,5945,6068,6142,6234,6368,6460,6532,6589,6741,6864,6938,7004,7127,7269,7431,7653,7719,7890,7980,8046,8129,8252,8344,8410,8532,8651,8734,8844,8976,9160,9261,9359,9431,9543,9645,9737,9860,9983,10117,10284,10412,10518,10604,10696,10786,10876,10962,11041,11123,11205,11327,11406,11480,11612,11746,11940,12068,12160,12243,12380,12526,12649,12732,12854,12961,13083,13205,13327,13464,13596,14091}
local level,steps,pushes,player,rows,cols=1,0,0,1,0,0
local board,undo={},{}
local menu,confirm=false,false
local function save()
  local out=level..","..steps..","..pushes..","..player..":"
  for i=1,#board do out=out..board[i] end
  app.write("game",out)
end
local function load(index)
  level=math.max(1,math.min(#offsets,index));steps=0;pushes=0;undo={}
  local data=app.asset("assets/levels.bin",offsets[level],2048)
  assert(data and #data>=2,"Level data unavailable")
  rows,cols=data:byte(1,2);board={}
  for i=1,rows*cols do board[i]=data:byte(i+2);if board[i]==6 or board[i]==7 then player=i end end
  save()
end
local function won()
  for i=1,#board do if board[i]==4 then return false end end
  return true
end
local function show()
  app.clear();app.title(app.tr("Sokoban","推箱子"));app.canvas()
  local w,h=app.size()
  if confirm then
    app.text(0,h*.2,w,90,app.tr("Restart this level?","重新开始本关？"),2,1)
    app.button(10,0,h*.55,(w-12)/2,54,app.tr("Continue","继续游戏"),0)
    app.button(11,(w+12)/2,h*.55,(w-12)/2,54,app.tr("Restart","重来"),3);return
  end
  if menu then
    app.text(0,20,w,70,app.tr("Choose a level","选择关卡"),2,1)
    app.text(0,110,w,70,tostring(level).." / "..#offsets,3,1)
    app.button(12,0,210,(w-12)/2,54,app.tr("Previous","上一关"),0)
    app.button(13,(w+12)/2,210,(w-12)/2,54,app.tr("Next","下一关"),0)
    app.button(14,0,288,w,54,app.tr("Play","开始"),3);return
  end
  app.text(0,0,w,45,app.tr("LEVEL ","第 ")..level..app.tr(" / "," 关 / ")..#offsets,2,0)
  app.text(0,48,w,30,app.tr("Moves ","步数 ")..steps.."   ·   "..app.tr("Pushes ","推动 ")..pushes,0,0,6)
  local cell=math.floor(math.min(w/cols,(h-250)/rows));local x0=(w-cols*cell)/2;local y0=86
  for r=0,rows-1 do
    local c=0
    while c<cols do
      local i=r*cols+c+1;local value=board[i];local x,y=x0+c*cell,y0+r*cell
      if value==1 then
        local run=1;while c+run<cols and board[i+run]==1 do run=run+1 end
        app.box(x+1,y+1,run*cell-2,cell-2,5,3);c=c+run
      else
        if value==3 or value==7 then app.circle(x+cell*.35,y+cell*.35,cell*.3,cell*.3,6,0,2) end
        if value==4 or value==5 then
          app.box(x+cell*.1,y+cell*.1,cell*.8,cell*.8,value==5 and 6 or 0,4)
          app.line(x+cell*.25,y+cell*.25,cell*.5,cell*.5,15,0,2)
          app.box(x+cell*.22,y+cell*.22,cell*.56,cell*.56,15,2,1)
        elseif value==6 or value==7 then
          app.circle(x+cell*.36,y+cell*.14,cell*.28,cell*.28,0)
          app.box(x+cell*.23,y+cell*.47,cell*.54,cell*.37,0,4)
        end
        c=c+1
      end
    end
  end
  local y=math.min(h-152,y0+rows*cell+12)
  if won() then app.text(0,y,w,35,app.tr("Complete! Choose the next level.","过关！可以挑战下一关了。"),1,1);y=y+40 end
  for i,label in ipairs({"←","↑","↓","→"}) do app.button(i,(i-1)*(w+6)/4,y,(w-18)/4,40,label,0) end
  y=y+50
  for i,label in ipairs({app.tr("Undo","撤销"),app.tr("Restart","重来"),app.tr("Levels","选关")}) do
    app.button(i+4,(i-1)*(w+8)/3,y,(w-16)/3,42,label,0)
  end
end
local function move(id)
  if won() then return end
  local delta=({-1,-cols,cols,1})[id];local dest=player+delta
  if dest<1 or dest>#board or (math.abs(delta)==1 and math.floor((dest-1)/cols)~=math.floor((player-1)/cols)) then return end
  local target=board[dest]
  if target==1 or target==0 then return end
  local push=target==4 or target==5;local beyond=dest+delta
  if push and math.abs(delta)==1 and math.floor((beyond-1)/cols)~=math.floor((dest-1)/cols) then return end
  if push and (beyond<1 or beyond>#board or (board[beyond]~=2 and board[beyond]~=3)) then return end
  local old="";for i=1,#board do old=old..board[i] end
  undo[#undo+1]={old,player,steps,pushes};if #undo>10 then table.remove(undo,1) end
  if push then board[beyond]=board[beyond]==3 and 5 or 4;pushes=pushes+1 end
  board[player]=board[player]==7 and 3 or 2
  board[dest]=(target==3 or target==5) and 7 or 6
  player=dest;steps=steps+1;save()
end
return {
  on_start=function()
    local saved=app.read("game");local values={};local token="";local split=0
    if saved then for i=1,#saved do local c=saved:sub(i,i);if c=="," or c==":" then values[#values+1]=tonumber(token) or 0;token="";if c==":" then split=i;break end else token=token..c end end end
    load(values[1] or 1)
    if saved and #values==4 and #saved-split==#board and values[4]>=1 and values[4]<=#board then
      local good=true;local restored={}
      for i=1,#board do local v=tonumber(saved:sub(split+i,split+i));if not v or v<0 or v>7 then good=false;break end;restored[i]=v end
      if good then board=restored;steps,pushes,player=values[2],values[3],values[4];save() end
    end
    show()
  end,
  on_resize=show,
  on_select=function(id)
    if id<=4 then move(id)
    elseif id==5 then local old=table.remove(undo);if old then for i=1,#board do board[i]=tonumber(old[1]:sub(i,i)) end;player,steps,pushes=old[2],old[3],old[4];save() end
    elseif id==6 then confirm=true
    elseif id==7 then menu=true
    elseif id==10 then confirm=false
    elseif id==11 then confirm=false;load(level)
    elseif id==12 then load(level-1)
    elseif id==13 then load(level+1)
    elseif id==14 then menu=false end
    show()
  end,
  on_swipe=function(_,direction) local id=({left=1,up=2,down=3,right=4})[direction];if id and not menu and not confirm then move(id);show() end end,
  on_back=function() if menu or confirm then menu=false;confirm=false;show() else app.exit() end end,
}
