local board, score = {}, 0
local function spawn()
  local empty = {}
  for i=1,16 do if board[i]==0 then empty[#empty+1]=i end end
  if #empty>0 then board[empty[math.random(#empty)]]=math.random(10)==1 and 4 or 2 end
end
local function reset()
  score=0
  for i=1,16 do board[i]=0 end
  spawn(); spawn()
end
local function show()
  app.clear(); app.title("2048"); app.caption(app.tr("Score: ", "得分：")..score); app.grid(4)
  for i=1,16 do app.row(board[i]==0 and "·" or tostring(board[i])) end
  for _,s in ipairs({"←", "↑", "↓", "→", app.tr("New game", "重新开始")}) do app.row(s) end
end
local function save()
  local data=tostring(score)
  for i=1,16 do data=data..","..board[i] end
  app.write("game", data)
end
local function move(direction)
  local changed=false
  for line=0,3 do
    local positions, compact, merged = {}, {}, {}
    for j=0,3 do
      local index
      if direction==1 then index=line*4+j+1
      elseif direction==4 then index=line*4+4-j
      elseif direction==2 then index=j*4+line+1
      else index=(3-j)*4+line+1 end
      positions[#positions+1]=index
      if board[index]~=0 then compact[#compact+1]=board[index] end
    end
    local i=1
    while i<=#compact do
      local value=compact[i]
      if compact[i+1]==value then value=value*2; score=score+value; i=i+1 end
      merged[#merged+1]=value; i=i+1
    end
    for j=1,4 do
      local value=merged[j] or 0
      if board[positions[j]]~=value then changed=true end
      board[positions[j]]=value
    end
  end
  if changed then spawn() end
  save()
end
return {
  on_start=function()
    reset()
    local saved=app.read("game")
    if saved then
      local numbers,token={},""
      for i=1,#saved+1 do
        local ch=string.sub(saved,i,i)
        if ch=="," or ch=="" then numbers[#numbers+1]=tonumber(token) or 0;token="" else token=token..ch end
      end
      if #numbers==17 then score=numbers[1];for i=1,16 do board[i]=numbers[i+1] end end
    end
    show()
  end,
  on_select=function(i)
    if i>=17 and i<=20 then move(i-16) elseif i==21 then reset(); save() end
    show()
  end,
}
