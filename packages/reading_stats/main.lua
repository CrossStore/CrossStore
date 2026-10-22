local view,page,selected="summary",0,1
local function duration(ms)
  local minutes=math.floor(ms/60000)
  return minutes>=60 and math.floor(minutes/60).."h "..(minutes%60).."m" or minutes.."m"
end
local function show()
  app.clear();app.title(app.tr("Reading statistics","阅读统计"));app.canvas()
  local w,h=app.size()
  if not app.allowed("reading_data") then
    app.text(0,40,w,h-100,app.tr("Allow reading statistics in Store settings → Application permissions.","请在商店设置的应用权限中允许读取阅读统计。"),1,1);return
  end
  local _,_,started,finished,streak=app.system("reading.counts")
  if view=="book" then
    local ok,title,time,progress,completed,author=app.system("reading.book","",selected)
    if not ok then view="books";return show() end
    app.text(0,10,w,100,title,2,0);app.text(0,120,w,50,author,0,0,6)
    app.text(0,h*.38,w,70,duration(time),3,0)
    app.text(0,h*.57,w,45,tostring(progress).."%"..(completed==1 and app.tr(" · Finished"," · 已读完") or ""),1,0)
    app.box(0,h*.73,w,6,12,3);if progress>0 then app.box(0,h*.73,w*progress/100,6,0,3) end
    app.button(6,0,h-58,w,52,app.tr("Continue reading","继续阅读"),3);return
  end
  if view=="books" then
    app.text(0,0,w,44,app.tr("Your books","读过的书"),2,0)
    local per=math.max(1,math.floor((h-130)/82));local first=page*per+1
    if first>started then page=0;first=1 end
    for i=0,per-1 do
      local index=first+i;if index>started then break end
      local ok,title,time,progress=app.system("reading.book","",index)
      if ok then
        local y=62+i*82
        app.text(0,y,w,34,title,1,0)
        app.text(0,y+36,w,26,duration(time).."  ·  "..progress.."%",0,0,6)
        app.hit(20+index,0,y,w,70)
      end
    end
    if started==0 then app.text(0,80,w,h-170,app.tr("Open a book to begin your reading history.","打开一本书，开始积累阅读记录。"),1,1) end
    app.button(4,0,h-58,(w-10)/2,50,app.tr("Previous","上一页"),0)
    app.button(5,(w+10)/2,h-58,(w-10)/2,50,app.tr("Next","下一页"),0);return
  end
  local _,_,total,today,week=app.system("reading.summary")
  local _,_,goal,longest,days=app.system("reading.goal")
  app.text(0,0,w,28,app.tr("TODAY","今日阅读"),0,0,6)
  app.text(0,36,w,62,duration(today),3,0)
  app.box(0,114,w,7,12,3)
  if goal>0 and today>0 then app.box(0,114,math.max(1,w*math.min(1,today/goal)),7,0,3) end
  app.text(0,132,w,32,app.tr("Daily goal ","每日目标 ")..duration(goal),0,0,6)
  local values={{app.tr("This week","近七天"),duration(week)},{app.tr("All time","累计阅读"),duration(total)},
    {app.tr("Finished books","读完书籍"),tostring(finished)},{app.tr("Reading streak","连续阅读"),streak..app.tr(" days"," 天")}}
  local block=math.max(76,(h-260)/2)
  for i,item in ipairs(values) do
    local x=(i-1)%2*(w+12)/2;local y=174+math.floor((i-1)/2)*block
    app.text(x,y,(w-12)/2,30,item[1],0,0,6)
    app.text(x,y+30,(w-12)/2,44,item[2],2,0)
  end
  app.button(1,0,h-58,w,52,app.tr("Browse reading history","查看阅读记录"),0)
end
return {
  on_start=show,on_resize=show,
  on_select=function(id)
    if id==1 then view="books";page=0
    elseif id==4 then page=math.max(0,page-1)
    elseif id==5 then page=page+1
    elseif id==6 then app.system("reading.open","",selected)
    elseif id>=21 then selected=id-20;view="book" end
    show()
  end,
  on_back=function() if view=="book" then view="books";show() elseif view=="books" then view="summary";show() else app.exit() end end,
}
