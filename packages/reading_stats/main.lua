-- Read-only analytics. Keep at most one visible page in Lua; the core owns history.
local view,page,selected,book_parent="summary",0,1,"books"
local month,month_first,month_days,chosen="",0,0,0
local calendar_grid
local row_ids={}
local day_cursor,day_reverse,day_first,day_last=1,false,1,0
local detail_dates=false
local badge_filter,badge_page="pending",0
local badge_count,book_pages=0,1
local function tr(en,zh) return app.tr(en,zh) end
local function duration(ms)
  local minutes=math.floor(ms/60000)
  if ms>0 and minutes==0 then return tr("<1m","不足1分钟") end
  return minutes>=60 and math.floor(minutes/60).."h "..(minutes%60).."m" or minutes.."m"
end
local function text(x,y,w,h,value,font,gray,align)
  app.text(x,y,w,h,value,font or 0,align or 0,gray or 0)
end
local function empty(w,h,message) text(0,70,w,h-150,message,1,6,1) end
local function nav(w,h,previous,next)
  if previous then app.button(4,0,h-52,(w-10)/2,46,tr("Previous","上一页"),0) end
  if next then app.button(5,(w+10)/2,h-52,(w-10)/2,46,tr("Next","下一页"),0) end
end
local function row(w,y,book_index,title,subtitle)
  row_ids[#row_ids+1]=book_index
  local action=20+#row_ids
  text(10,y,w-20,32,title,1)
  text(10,y+34,w-20,27,subtitle,0,6)
  app.hit(action,0,y,w,64)
  app.box(0,y+69,w,1,12)
end
local function refresh_month(value)
  local ok,label,first,days,today=app.system("reading.calendar",value or "")
  if not ok then month="";month_first=0;return false end
  month,month_first,month_days=label,first,days
  if chosen<first or chosen>=first+days then chosen=math.max(first,math.min(first+days-1,today)) end
  return true
end
local function change_month(delta)
  if month=="" then return end
  local year=tonumber(string.sub(month,1,4));local number=tonumber(string.sub(month,6,7))+delta
  if number==0 then number=12;year=year-1 elseif number==13 then number=1;year=year+1 end
  if year>=1970 and year<=2106 then refresh_month(string.format("%04d-%02d",year,number)) end
end
local function summary(w,h,finished,streak)
  local _,_,total,today,week=app.system("reading.summary")
  local _,_,goal=app.system("reading.goal")
  text(0,0,w,24,tr("TODAY","今日阅读"),0,6)
  text(0,30,w,58,duration(today),3)
  app.box(0,100,w,6,12,3)
  if goal>0 and today>0 then app.box(0,100,math.max(1,w*math.min(1,today/goal)),6,0,3) end
  text(0,114,w,28,tr("Daily goal ","每日目标 ")..duration(goal),0,6)
  local values={{tr("Last 7 days","近七天"),duration(week)},{tr("All time","累计阅读"),duration(total)},
    {tr("Finished books","读完书籍"),tostring(finished)},{tr("Goal streak","连续达标"),streak..tr(" days"," 天")}}
  local block=math.max(72,(h-246)/2)
  for i,item in ipairs(values) do
    local x=(i-1)%2*(w+12)/2;local y=156+math.floor((i-1)/2)*block
    text(x,y,(w-12)/2,24,item[1],0,6);text(x,y+27,(w-12)/2,42,item[2],2)
  end
  local bw=(w-20)/3
  app.button(1,0,h-52,bw,46,tr("Books","书籍"),0)
  app.button(2,bw+10,h-52,bw,46,tr("Calendar","日历"),0)
  app.button(3,2*(bw+10),h-52,bw,46,tr("Badges","成就"),0)
end
local function books(w,h,started)
  text(0,0,w,40,tr("Your books","读过的书"),2)
  local per=math.min(7,math.max(1,math.floor((h-124)/78)))
  book_pages=math.max(1,math.ceil(started/per));page=math.min(page,book_pages-1)
  text(0,42,w,24,(page+1).." / "..book_pages,0,6)
  for i=0,per-1 do
    local index=page*per+i+1;if index>started then break end
    local ok,title,time,progress=app.system("reading.book","",index)
    if ok then row(w,72+i*78,index,title,duration(time).."  ·  "..progress.."%") end
  end
  if started==0 then empty(w,h,tr("Open a book to begin your reading history.","打开一本书，开始积累阅读记录。")) end
  nav(w,h,page>0,page+1<book_pages)
end
local function book(w,h)
  local ok,title,time,progress,completed,author=app.system("reading.book","",selected)
  if not ok then empty(w,h,tr("This reading record is no longer available.","这条阅读记录已不存在。"));return end
  local detail,chapter,sessions,last_session,chapter_progress,dates=app.system("reading.book_detail","",selected)
  text(0,0,w,66,title,2);text(0,72,w,28,author,0,6)
  if detail_dates then
    local parts={};local start=1
    for pos=1,#dates+1 do
      if pos==#dates+1 or string.byte(dates,pos)==124 then
        parts[#parts+1]=string.sub(dates,start,pos-1);start=pos+1
      end
    end
    local first,last,finish=parts[1] or "",parts[2] or "",parts[3] or ""
    local values={{tr("First read","开始阅读"),first},{tr("Last read","最近阅读"),last},
      {tr("Completed","读完日期"),finish},{tr("Last session","上次阅读"),detail and duration(last_session) or ""}}
    local step=math.floor((h-174)/4)
    for i,item in ipairs(values) do
      local y=112+(i-1)*step
      text(0,y,w*.43,26,item[1],0,6)
      text(w*.43,y,w*.57,32,item[2]~="" and item[2] or tr("Not recorded","未记录"),1,0,2)
    end
  else
    text(0,116,w,60,duration(time),3)
    text(0,186,w,32,progress.."%"..(completed==1 and tr(" · Finished"," · 已读完") or ""),1)
    app.box(0,230,w,6,12,3)
    if progress>0 then app.box(0,230,math.max(1,w*math.min(100,progress)/100),6,0,3) end
    if detail then
      text(0,254,w,30,sessions..tr(" reading sessions"," 次阅读"),1)
      if chapter~="" then text(0,296,w,math.max(24,h-358),chapter.."  ·  "..chapter_progress.."%",0,6) end
    end
  end
  app.button(7,0,h-52,(w-10)/2,46,detail_dates and tr("Overview","概览") or tr("Dates","日期记录"),0)
  app.button(6,(w+10)/2,h-52,(w-10)/2,46,tr("Read","继续阅读"),3)
end
local function calendar(w,h)
  if month=="" and not refresh_month("") then
    empty(w,h,tr("No dated history yet. Set the device clock, then start reading.","尚无日期记录。校准设备时间后，开始阅读即可积累。"));return
  end
  app.button(10,0,0,48,42,"<",0);text(56,2,w-112,38,month,2,0,1)
  app.button(11,w-48,0,48,42,">",0)
  local _,_,goal=app.system("reading.goal")
  local total,active=0,0
  local offset=(month_first+3)%7 -- Monday first; day 0 is Thursday, 1970-01-01.
  local step_x=(w+6)/7;local step_y=math.floor((h-218)/6);local top=108
  calendar_grid={x=0,y=top,sx=step_x,sy=step_y,offset=offset}
  local names=tr("MTWTFSS","一二三四五六日")
  for i=0,6 do
    local label=app.tr(string.sub(names,i+1,i+1),string.sub(names,i*3+1,i*3+3))
    text(i*step_x,78,step_x-6,24,label,0,6,1)
  end
  for day=1,month_days do
    local ordinal=month_first+day-1
    local _,_,_,elapsed=app.system("reading.date","",ordinal)
    total=total+elapsed;if elapsed>0 then active=active+1 end
    local index=offset+day-1;local x=index%7*step_x;local y=top+math.floor(index/7)*step_y
    local gray=15
    if elapsed>0 then gray=elapsed>=goal and 0 or (elapsed>=goal/2 and 6 or 12) end
    app.box(x,y,step_x-6,step_y-6,gray,4)
    if ordinal==chosen then
      app.box(x,y,step_x-6,step_y-6,0,4,2)
      if gray<=6 then app.box(x+3,y+3,step_x-12,step_y-12,15,2,1) end
    elseif elapsed==0 then app.box(x,y,step_x-6,step_y-6,12,4,1) end
    text(x,y,step_x-6,step_y-6,tostring(day),0,gray<=6 and 15 or 0,1)
  end
  text(0,48,w,26,duration(total).."  ·  "..active..tr(" reading days"," 天阅读"),0,6,1)
  app.hit(12,0,top,w,step_y*6-6)
  local _,date,_,elapsed=app.system("reading.date","",chosen)
  text(0,h-99,w,34,date.."  ·  "..duration(elapsed),0,0,1)
  app.button(13,0,h-52,48,46,"<",0)
  app.button(14,58,h-52,w-116,46,tr("Day details","日期详情"),0)
  app.button(15,w-48,h-52,48,46,">",0)
end
local function date_books(w,h,started)
  local _,date,_,elapsed=app.system("reading.date","",chosen)
  text(0,0,w,40,date,2);text(0,42,w,26,duration(elapsed)..tr(" read on this day"," · 当日阅读"),0,6)
  if elapsed==0 then
    day_first,day_last=1,started
    empty(w,h,tr("No reading recorded on this date.","这一天没有阅读记录。"));return
  end
  local per=math.min(7,math.max(1,math.floor((h-124)/78)))
  local cursor=math.max(1,math.min(started,day_cursor));local rows={}
  day_first,day_last=cursor,cursor-1
  for i=1,per do
    if cursor<1 or cursor>started then break end
    local ok,_,index,time,next_cursor=app.system("reading.date_book",(day_reverse and "-" or "")..chosen,cursor)
    if not ok then break end
    if day_reverse then day_first=next_cursor==0 and 1 or next_cursor+1;day_last=math.max(day_last,cursor)
    else day_first=math.min(day_first,cursor);day_last=next_cursor==0 and started or next_cursor-1 end
    if index>0 then
      local found,title=app.system("reading.book","",index)
      if found then table.insert(rows,{index=index,title=title,time=time}) end
    end
    cursor=next_cursor;if cursor==0 then break end
  end
  for i=1,#rows do
    local item=rows[day_reverse and #rows-i+1 or i]
    row(w,72+(i-1)*78,item.index,item.title,duration(item.time))
  end
  if #rows==0 then
    empty(w,h,tr("No book in this group. Older history may only have a daily total.","此组没有对应书籍；旧版记录可能只有每日总时长。"))
  end
  nav(w,h,day_first>1,day_last<started)
end
local function achievements(w,h)
  local ok,_,count,unlocked,enabled=app.system("reading.achievements")
  if not ok or enabled==0 then empty(w,h,tr("Achievements are disabled in the reader's settings.","阅读器设置中尚未开启成就。"));return end
  local bw=(w-10)/2
  app.button(16,0,0,bw,44,tr("Pending","未完成").." "..(count-unlocked),badge_filter=="pending" and 2 or 0)
  app.button(17,bw+10,0,bw,44,tr("Unlocked","已解锁").." "..unlocked,badge_filter=="unlocked" and 2 or 0)
  local per=math.min(7,math.max(1,math.floor((h-110)/78)))
  local matched,shown=0,0
  badge_count=badge_filter=="unlocked" and unlocked or count-unlocked
  badge_page=math.min(badge_page,math.max(0,math.ceil(badge_count/per)-1))
  for index=1,math.min(count,128) do
    local exists,title,metric,target,done,date=app.system("reading.achievement","",index)
    if exists and ((done==1)==(badge_filter=="unlocked")) then
      if matched>=badge_page*per and shown<per then
        local y=62+shown*78
        text(10,y,w-20,32,title,1)
        local subtitle=done==1 and tr("Unlocked","已解锁")..(date~="" and " · "..date or "") or tr("Target: ","目标：")..((metric==3 or metric==7) and duration(target) or tostring(target))
        text(10,y+35,w-20,28,subtitle,0,6);app.box(0,y+69,w,1,12);shown=shown+1
      end
      matched=matched+1
    end
  end
  if shown==0 then empty(w,h,badge_filter=="unlocked" and tr("Keep reading to earn your first achievement.","继续阅读，解锁你的第一个成就。") or tr("All achievements unlocked.","所有成就都已解锁。")) end
  nav(w,h,badge_page>0,(badge_page+1)*per<badge_count)
end
local function show()
  row_ids={}
  app.clear();app.title(tr("Reading statistics","阅读统计"));app.canvas()
  local w,h=app.size()
  if not app.allowed("reading_data") then
    empty(w,h,tr("Allow reading statistics in Store settings → Application permissions.","请在商店设置的应用权限中允许读取阅读统计。"));return
  end
  local _,_,started,finished,streak=app.system("reading.counts")
  if view=="book" then book(w,h)
  elseif view=="books" then books(w,h,started)
  elseif view=="calendar" then calendar(w,h)
  elseif view=="day" then date_books(w,h,started)
  elseif view=="achievements" then achievements(w,h)
  else summary(w,h,finished,streak) end
end
return {
  on_start=show,on_resize=show,
  on_select=function(id,gesture,x,y)
    if not app.allowed("reading_data") then return end
    if id==1 then view="books";page=0
    elseif id==2 then view="calendar"
    elseif id==3 then view="achievements";badge_page=0
    elseif id==4 or id==5 then
      local delta=id==4 and -1 or 1
      if view=="day" then day_reverse=delta<0;day_cursor=delta<0 and day_first-1 or day_last+1
      elseif view=="achievements" then badge_page=math.max(0,badge_page+delta)
      else page=math.max(0,page+delta) end
    elseif id==6 then app.system("reading.open","",selected)
    elseif id==7 then detail_dates=not detail_dates
    elseif id==10 or id==11 then change_month(id==10 and -1 or 1)
    elseif id==12 and calendar_grid then
      if x and x>=0 and y>=0 then
        local g=calendar_grid;local dx,dy=x-g.x,y-g.y
        local column,line=math.floor(dx/g.sx),math.floor(dy/g.sy)
        if column>=0 and column<7 and line>=0 and line<6 and dx%g.sx<g.sx-6 and dy%g.sy<g.sy-6 then
          local day=line*7+column-g.offset+1
          if day>=1 and day<=month_days then chosen=month_first+day-1 end
        end
      else view="day";day_cursor=1;day_reverse=false end
    elseif id==13 then chosen=math.max(month_first,chosen-1)
    elseif id==15 then chosen=math.min(month_first+month_days-1,chosen+1)
    elseif id==14 then view="day";day_cursor=1;day_reverse=false
    elseif id==16 or id==17 then badge_filter=id==16 and "pending" or "unlocked";badge_page=0
    elseif row_ids[id-20] then selected=row_ids[id-20];book_parent=view;view="book";detail_dates=false end
    show()
  end,
  on_back=function()
    if view=="book" then view=book_parent
    elseif view=="day" then view="calendar"
    elseif view~="summary" then view="summary"
    else app.exit();return end
    show()
  end,
}
