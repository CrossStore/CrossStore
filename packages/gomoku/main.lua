-- Phrases are a small asset so Lua compiler memory stays below 64 KiB.
local phrases={}
local function tr(id) return app.tr(phrases[id*2-1],phrases[id*2]) end
local function load_phrases()
  local data=app.asset("assets/strings.txt",0,2048)
  if not data then error("Gomoku language asset unavailable") end
  local start=1
  for i=1,#data do if data:byte(i)==10 then phrases[#phrases+1]=data:sub(start,i-1);start=i+1 end end
end
-- Bounded, incremental Lua AI: heuristic ranking, then optional two-ply replies.
-- Board uses 15 packed rows (two bits per point), history <=225 indices; AI keeps six candidates.
local n,board,moves,winner,computer=9,{},{},0,true
local level,human,page=2,1,"board"
local draft_n,draft_computer,draft_level,draft_human=9,true,2,1
local confirm_from="board"
local thinking,phase=false,"rank"
local scan,best,best_score=1,0,-1
local candidates,scores={},{}
local trial,reply_scan,reply_max,trial_best,trial_score=1,1,0,0,-10000000
local cursor=41
local bx,by,step,side=0,0,0,0
local elapsed,recorded=0,false
local stats={{0,0,0,0,0},{0,0,0,0,0}}
local dirty,last_edit,last_save,last_tick,saved_elapsed=false,0,0,0,0
local save_error=false
local directions={{1,0},{0,1},{1,1},{1,-1}}
local signs={-1,1}
local weights={2,15,180,12000}
local function level_name(value)
  return ({tr(1),tr(2),tr(3)})[value]
end
local function time_text(ms)
  local s=math.floor(ms/1000);return string.format("%02d:%02d",math.floor(s/60),s%60)
end
local function mark_dirty()
  local now=app.millis();if not dirty then last_save=now end
  dirty,last_edit=true,now
end
local function advance()
  local now=app.millis()
  if page=="board" and winner==0 then elapsed=math.min(359999000,elapsed+(now-last_tick)%4294967296) end
  last_tick=now
end
local function at(r,c)
  if r<0 or c<0 or r>=n or c>=n then return -1 end
  return (board[r+1]>>(c*2))&3
end
local function get(i) return (board[(i-1)//n+1]>>(((i-1)%n)*2))&3 end
local function put(i,color)
  local row,shift=(i-1)//n+1,((i-1)%n)*2
  board[row]=(board[row]&~(3<<shift))|(color<<shift)
end
local function strength(index,color)
  local r,c=math.floor((index-1)/n),(index-1)%n
  local result=0
  for _,d in ipairs(directions) do
    local count,open=1,0
    for _,sign in ipairs(signs) do
      local k=1
      while k<5 and at(r+d[1]*k*sign,c+d[2]*k*sign)==color do count=count+1;k=k+1 end
      if at(r+d[1]*k*sign,c+d[2]*k*sign)==0 then open=open+1 end
    end
    if count>=5 then return 1000000 end
    if open>0 then result=result+weights[count]*(open==2 and 5 or 1) end
  end
  return result
end
local function nearby(i)
  local r,c=math.floor((i-1)/n),(i-1)%n
  for dr=-1,1 do for dc=-1,1 do if at(r+dr,c+dc)>0 then return true end end end
  return false
end
local function save()
  if not dirty and elapsed==saved_elapsed then return true end
  local data={3,n,computer and 1 or 0,level,human,elapsed,recorded and 1 or 0}
  for _,row in ipairs(stats) do for i=1,5 do data[#data+1]=row[i] end end
  local value=table.concat(data,",")
  if #moves>0 then value=value..","..table.concat(moves,",") end
  if not app.write("game",value) then save_error=true;return false end
  dirty=false;save_error=false;last_save=app.millis();saved_elapsed=elapsed;return true
end
local function place(i)
  if winner~=0 or i<1 or i>n*n or get(i)~=0 then return false end
  local color=#moves%2+1
  put(i,color);moves[#moves+1]=i;cursor=i
  if strength(i,color)>=1000000 then winner=color elseif #moves==n*n then winner=3 end
  return true
end
local function record_result()
  if winner==0 or recorded then return end
  recorded=true
  local row=stats[n==9 and 1 or 2];row[winner+1]=row[winner+1]+1
  local seconds=math.max(1,math.floor(elapsed/1000))
  if row[5]==0 or seconds<row[5] then row[5]=seconds end
end
local function begin_ai()
  thinking=computer and #moves%2+1~=human and winner==0
  phase="rank";scan,best,best_score=1,0,-1;candidates={};scores={}
end
local function reset()
  board={};moves={};winner=0;thinking=false;elapsed=0;recorded=false
  for i=1,n do board[i]=0 end
  cursor=math.floor(n*n/2)+1;local row=stats[n==9 and 1 or 2];row[1]=row[1]+1
  page="board";last_tick=app.millis();mark_dirty();begin_ai()
end
local function show()
  app.clear();app.title(save_error and tr(4) or tr(5));app.canvas()
  local w,h=app.size()
  if page=="confirm" then
    app.text(0,h*.2,w,90,tr(6),2,1)
    app.button(20,0,h*.55,(w-12)/2,54,tr(7),0)
    app.button(21,(w+12)/2,h*.55,(w-12)/2,54,tr(8),3);return
  elseif page=="options" then
    app.text(0,0,w,42,tr(9),2,0)
    local labels={tostring(draft_n).." × "..draft_n..tr(10),
      draft_computer and tr(11) or tr(12),
      tr(13)..level_name(draft_level),
      draft_human==1 and tr(14) or tr(15)}
    local ids={22,23,25,26}
    for i,label in ipairs(labels) do app.button(ids[i],0,50+(i-1)*56,w,46,label,0) end
    app.button(27,0,h-106,(w-12)/2,44,tr(16),0)
    app.button(20,(w+12)/2,h-106,(w-12)/2,44,tr(17),0)
    app.button(24,0,h-52,w,46,tr(18),3);return
  elseif page=="stats" then
    app.text(0,0,w,42,tr(19),2,0)
    for i,row in ipairs(stats) do
      local y=58+(i-1)*132
      app.text(0,y,w,32,(i==1 and "9 × 9" or "15 × 15").." · "..row[1]..tr(20),1,0)
      app.text(0,y+36,w,32,tr(21)..row[2].." / "..row[3].." / "..row[4],0,0,6)
      app.text(0,y+72,w,32,tr(22)..(row[5]>0 and time_text(row[5]*1000) or tr(23)),0,0,6)
    end
    app.button(20,0,h-48,w,42,tr(24),0);return
  end
  local turn=winner==1 and tr(25) or winner==2 and tr(26) or
    winner==3 and tr(27) or thinking and tr(28) or
    (#moves%2==0 and tr(29) or tr(30))
  app.circle(0,10,20,20,#moves%2==0 and 0 or 15);app.circle(0,10,20,20,0,0,1)
  app.text(32,0,w-32,40,turn,2,0)
  app.text(0,42,w,28,tr(31)..#moves..tr(32)..time_text(elapsed)..(computer and " · "..level_name(level) or ""),0,0,6)
  local landscape=w>h*1.3
  side=math.floor(math.min(landscape and w*.6 or w,h-(landscape and 84 or 196)))
  bx=landscape and 0 or (w-side)/2;by=76
  local margin=math.max(15,side/(n+1));step=(side-2*margin)/(n-1)
  app.box(bx,by,side,side,15,8)
  local gx,gy=bx+margin,by+margin
  for j=0,n-1 do
    app.line(gx,gy+j*step,side-2*margin,1,6);app.line(gx+j*step,gy,1,side-2*margin,6)
  end
  for _,r in ipairs(n==9 and {2,4,6} or {3,7,11}) do
    for _,c in ipairs(n==9 and {2,4,6} or {3,7,11}) do app.circle(gx+c*step-2,gy+r*step-2,4,4,0) end
  end
  local diameter=step*.81
  for i=1,n*n do
    local x,y=gx+(i-1)%n*step,gy+math.floor((i-1)/n)*step
    if get(i)~=0 then
      app.circle(x-diameter/2,y-diameter/2,diameter,diameter,get(i)==1 and 0 or 15)
      if get(i)==2 then app.circle(x-diameter/2,y-diameter/2,diameter,diameter,0,0,2) end
      if i==moves[#moves] then app.box(x-2,y-2,4,4,get(i)==1 and 15 or 0) end
    elseif i==cursor then app.box(x-diameter/2,y-diameter/2,diameter,diameter,6,3,1) end
  end
  app.hit(1,bx,by,side,side)
  local px=landscape and side+16 or 0;local pw=landscape and w-px or w
  local y=landscape and by+30 or by+side+10
  for i,label in ipairs({"←","↑","↓","→"}) do app.button(i+1,px+(i-1)*(pw+6)/4,y,(pw-18)/4,38,label,0) end
  y=y+48
  for i,label in ipairs({tr(33),tr(34),tr(35)}) do
    app.button(i+5,px+(i-1)*(pw+8)/3,y,(pw-16)/3,44,label,i==3 and 2 or 0)
  end
end
local function finish_ai(i)
  if i>0 and place(i) then record_result();mark_dirty() end
  thinking=false;show()
end
local function ai_tick()
  if not thinking or page~="board" then return end
  if #moves==0 then finish_ai(math.floor(n*n/2)+1);return end
  local color=3-human
  if phase=="rank" then
    -- At most 18 evaluated squares per callback, independent of board size.
    local checked=0
    while scan<=n*n and checked<18 do
      local i=scan;scan=scan+1
      if get(i)==0 and nearby(i) then
        local r,c=math.floor((i-1)/n),(i-1)%n
        local attack,defend=strength(i,color),strength(i,human)
        local score=attack>=1000000 and 3000000 or defend>=1000000 and 2000000 or attack+defend*1.2
        if level==1 and score<2000000 then score=score*(.7+math.random()*.6) end
        score=score-math.abs(r-(n-1)/2)-math.abs(c-(n-1)/2)
        if score>best_score then best,best_score=i,score end
        if level==3 then
          local position=#scores+1
          while position>1 and score>scores[position-1] do position=position-1 end
          if position<=6 then
            table.insert(candidates,position,i);table.insert(scores,position,score)
            if #candidates>6 then table.remove(candidates);table.remove(scores) end
          end
        end
        checked=checked+1
      end
    end
    if scan>n*n then
      if level<3 or best_score>1900000 or #candidates==0 then finish_ai(best)
      else phase="reply";trial,reply_scan,reply_max,trial_best,trial_score=1,1,0,0,-10000000 end
    end
  else
    -- Evaluate opponent replies in bounded slices, undoing each simulated stone
    -- before returning to the host. A checkpoint always sees the actual game.
    local candidate=candidates[trial];put(candidate,color)
    local checked=0
    while reply_scan<=n*n and checked<24 do
      local i=reply_scan;reply_scan=reply_scan+1
      if get(i)==0 and nearby(i) then reply_max=math.max(reply_max,strength(i,human));checked=checked+1 end
    end
    put(candidate,0)
    if reply_scan>n*n then
      local score=scores[trial]-reply_max*1.2
      if score>trial_score then trial_best,trial_score=candidate,score end
      trial=trial+1;reply_scan,reply_max=1,0
      if trial>#candidates then finish_ai(trial_best) end
    end
  end
end
local function load()
  local data=app.read("game");if not data then return false end
  -- Keep only the 17-field header; replay moves directly into their final arrays.
  -- A 225-move CSV table alongside the board would exceed the 64 KiB VM.
  local header,token,count,fields={},"",0,0
  for i=1,#data+1 do local c=data:sub(i,i)
    if c=="," or c=="" then
      local value=tonumber(token);token="";count=count+1
      if not value or value<0 or value%1~=0 or value>359999000 then return false end
      if count==1 then fields=value==3 and 17 or 2 end
      if count<=fields then
        header[count]=value
        if count==fields then
          if fields==17 then
            n,computer,level,human,elapsed,recorded=header[2],header[3]==1,header[4],header[5],header[6],header[7]==1
            if level<1 or level>3 or (human~=1 and human~=2) then return false end
            for r=1,2 do for j=1,5 do stats[r][j]=header[7+(r-1)*5+j] end end
          else n,computer=header[1],header[2]~=0 end
          if n~=9 and n~=15 then return false end
          for j=1,n do board[j]=0 end
        end
      else
        if value<1 or value>n*n or get(value)~=0 then return false end
        put(value,#moves%2+1);moves[#moves+1]=value;cursor=value
      end
    else token=token..c end
  end
  if count<fields then return false end
  local color=(#moves-1)%2+1
  if #moves>0 and strength(moves[#moves],color)>=1000000 then winner=color
  elseif #moves==n*n then winner=3 end
  if fields==2 then stats[n==9 and 1 or 2][1]=1;record_result();mark_dirty() end
  saved_elapsed=elapsed;begin_ai();return true
end

return {
  on_start=function()
    load_phrases()
    last_save,last_tick=app.millis(),app.millis()
    if not load() then stats={{0,0,0,0,0},{0,0,0,0,0}};n,computer,level,human=9,true,2,1;reset() end
    show()
  end,
  on_resize=show,
  on_tick=function()
    local previous=math.floor(elapsed/10000);advance();ai_tick()
    local now=app.millis();local had_error=save_error
    if (dirty and ((now-last_edit)%4294967296>=2000 or (now-last_save)%4294967296>=10000)) or
      (not dirty and elapsed~=saved_elapsed and (now-last_save)%4294967296>=10000) then
      if not save() then dirty=true;last_edit,last_save=app.millis(),app.millis() end
    end
    if had_error~=save_error or (page=="board" and math.floor(elapsed/10000)~=previous) then show() end
  end,
  on_select=function(id,_,x,y)
    advance()
    if page=="confirm" then
      if id==20 then page=confirm_from
      elseif id==21 then
        if confirm_from=="options" then n,computer,level,human=draft_n,draft_computer,draft_level,draft_human end
        reset()
      end
    elseif page=="stats" then if id==20 then page="board" end
    elseif page=="options" then
      if id==20 then page="board"
      elseif id==22 then draft_n=draft_n==9 and 15 or 9
      elseif id==23 then draft_computer=not draft_computer
      elseif id==25 then draft_level=draft_level%3+1
      elseif id==26 then draft_human=3-draft_human
      elseif id==27 then page="stats"
      elseif id==24 then confirm_from="options";page="confirm" end
    elseif id==6 and winner==0 then
      thinking=false
      local count=computer and (#moves%2+1)==human and 2 or 1
      -- If the computer started, preserve its opening move when no human move exists.
      if computer and human==2 and #moves==1 then count=0 end
      for _=1,count do local i=table.remove(moves);if i then put(i,0);mark_dirty() end end
      begin_ai()
    elseif id==7 then confirm_from="board";page="confirm"
    elseif id==8 then
      draft_n,draft_computer,draft_level,draft_human=n,computer,level,human;page="options"
    elseif id>=2 and id<=5 then
      local delta=({-1,-n,n,1})[id-1];cursor=math.max(1,math.min(n*n,cursor+delta))
    elseif id==1 and not thinking then
      if x and x>=0 then
        local margin=(side-step*(n-1))/2
        local c=math.floor((x-bx-margin)/step+.5);local r=math.floor((y-by-margin)/step+.5)
        if r<0 or c<0 or r>=n or c>=n then return end
        cursor=r*n+c+1
      end
      if place(cursor) then record_result();mark_dirty();begin_ai() end
    end
    last_tick=app.millis();show()
  end,
  on_stop=function() advance();if not save() then error("progress save failed") end end,
  on_back=function()
    advance()
    if page~="board" then page="board";last_tick=app.millis();show()
    elseif save() then app.exit() else show() end
  end,
}
