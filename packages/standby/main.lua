-- Clock faces and calendar rules belong to the package. No work runs in sleep.
-- Almanac tables/formula ported from CrossMux ChineseAlmanac.cpp (MIT).
local tr=app.tr
local face,inverse,awake,syncing=0,false,false,false
local time,date,weekday,valid='--:--','',0,false
local notice,lastMinute='',nil
local lunarData,calendarDate,calendar='',nil,nil
local months={31,28,31,30,31,30,31,31,30,31,30,31}
local terms={'立春','雨水','惊蛰','春分','清明','谷雨','立夏','小满','芒种','夏至','小暑','大暑','立秋','处暑','白露','秋分','寒露','霜降','立冬','小雪','大雪','冬至','小寒','大寒'}
local monthNames={'正月','二月','三月','四月','五月','六月','七月','八月','九月','十月','冬月','腊月'}
local dayNames={'初一','初二','初三','初四','初五','初六','初七','初八','初九','初十','十一','十二','十三','十四','十五','十六','十七','十八','十九','二十','廿一','廿二','廿三','廿四','廿五','廿六','廿七','廿八','廿九','三十'}
local stems={'甲','乙','丙','丁','戊','己','庚','辛','壬','癸'}
local branches={'子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'}
local c20={4.6295,19.4599,6.3826,21.4155,5.59,20.888,6.318,21.86,6.5,22.2,7.928,23.65,8.35,23.95,8.44,23.822,9.098,24.218,7.218,22.36,7.9,22.6,6.11,20.84}
local c21={3.87,18.73,5.63,20.646,4.81,20.1,5.52,21.04,5.678,21.37,7.108,22.83,7.5,23.13,7.646,23.042,8.318,23.438,7.438,22.36,7.18,21.94,5.4055,20.12}
local function leap(y) return y%4==0 and (y%100~=0 or y%400==0) end
local function days(y,m) return months[m]+((m==2 and leap(y)) and 1 or 0) end
local function absDay(y,m,d)
  local a=y-1
  local n=(y-1900)*365+a//4-a//100+a//400-(1899//4-1899//100+1899//400)+d-1
  for i=1,m-1 do n=n+days(y,i) end
  return n
end
local function termDay(y,i)
  local m=((i-1)//2+1)%12+1
  local c=y>=2000 and c21 or c20
  return absDay(y,m,math.floor((y%100)*.2422+c[i]-(y%100)//4))
end
local function info(y)
  local n=(y-1900)*3+1
  return lunarData:byte(n)|(lunarData:byte(n+1)<<8)|(lunarData:byte(n+2)<<16)
end
local function almanac(y,m,d)
  local today=absDay(y,m,d)
  if y<1900 or y>2100 or today<30 or #lunarData~=603 then return nil end
  local ly,offset=1900,today-30
  while ly<2100 do
    local bits=info(ly);local total=348
    for bit=4,15 do total=total+((bits>>bit)&1) end
    if bits&15~=0 then total=total+29+((bits>>16)&1) end
    if offset<total then break end
    offset=offset-total;ly=ly+1
  end
  local bits=info(ly);local lm,extra=1,false
  while lm<=12 do
    local count=29+((bits>>(extra and 16 or 16-lm))&1)
    if offset<count then break end
    offset=offset-count
    if not extra and lm==bits&15 then extra=true else extra=false;lm=lm+1 end
  end
  if lm>12 then return nil end
  local current,bestYear,best=1,y,-100000
  for year=y-1,y do
    for i=1,24 do
      local day=termDay(year,i)
      if day<=today and day>best then current,bestYear,best=i,year,day end
    end
  end
  local nextTerm=current%24+1
  local nextYear=bestYear+(nextTerm==23 and 1 or 0)
  local toNext=math.max(1,math.min(30,termDay(nextYear,nextTerm)-today))
  local gz=y-(today<termDay(y,1) and 1 or 0)-1900
  local lunar=(extra and '闰' or '')..monthNames[lm]..dayNames[offset+1]
  return {lunar=lunar,year=stems[(gz+6)%10+1]..branches[gz%12+1]..'年',
    term=terms[current],next=terms[nextTerm],remaining=toNext}
end
local segments={0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f}
local function drawDigits(value,x,y,width,height,ink)
  local cell=width/5.12;local gap=cell*.16;local thick=math.max(4,cell*.12)
  for i=1,5 do
    local char=value:sub(i,i)
    if i==3 then
      app.circle(x+cell*.12,y+height*.32,thick,thick,ink)
      app.circle(x+cell*.12,y+height*.68,thick,thick,ink);x=x+cell*.48
    else
      local number=tonumber(char)
      local mask=number and segments[number+1] or 0x40
      local coords={{thick,0,cell-2*thick,thick},{cell-thick,thick,thick,height/2-thick},
        {cell-thick,height/2,thick,height/2-thick},{thick,height-thick,cell-2*thick,thick},
        {0,height/2,thick,height/2-thick},{0,thick,thick,height/2-thick},{thick,height/2-thick/2,cell-2*thick,thick}}
      for bit=0,6 do
        if mask&(1<<bit)~=0 then local r=coords[bit+1];app.box(x+r[1],y+r[2],r[3],r[4],ink,math.floor(thick/3)) end
      end
      x=x+cell+gap
    end
  end
end
local function show()
  app.clear();app.canvas();app.title(tr('Standby clock','待机时钟'))
  local w,h=app.size();local ink,paper=inverse and 15 or 0,inverse and 0 or 15
  local gray=inverse and 5 or 10
  app.box(0,0,w,h,paper)
  local y=tonumber(date:sub(1,4));local m=tonumber(date:sub(6,7));local d=tonumber(date:sub(9,10))
  if face==0 or not valid then
    local width=math.min(w-24,(h-210)*2.3);local height=width*.42
    drawDigits(time,(w-width)/2,math.max(46,(h-175-height)/2),width,height,ink)
    local week={'Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'}
    local weekZh={'星期日','星期一','星期二','星期三','星期四','星期五','星期六'}
    app.text(0,h-174,w,42,valid and date..'  '..tr(week[weekday+1],weekZh[weekday+1]) or tr('Set the clock to begin','请先联网校时'),1,1,ink)
  else
    app.text(0,4,w,46,string.format('%04d / %02d',y,m),3,1,ink)
    local top=64;local cell=(w-16)/7;local row=math.min(50,(h-250)/7)
    local week={'S','M','T','W','T','F','S'};local weekZh={'日','一','二','三','四','五','六'}
    for i=0,6 do app.text(8+i*cell,top,cell,row,tr(week[i+1],weekZh[i+1]),0,1,gray) end
    local first=(absDay(y,m,1)+1)%7
    for day=1,days(y,m) do
      local i=first+day-1;local cx=8+(i%7)*cell;local cy=top+(1+i//7)*row
      if day==d then app.box(cx+2,cy+2,cell-4,row-4,ink,8) end
      app.text(cx,cy,cell,row,tostring(day),1,1,day==d and paper or ink)
    end
    if calendar then
      local detail=tr('Lunar ','农历 ')..calendar.lunar..'  '..calendar.year
      app.text(0,h-185,w,38,detail,1,1,ink)
      app.text(0,h-147,w,36,tr('Next: ','下个节气：')..calendar.next..'  '..calendar.remaining..tr(' days','天'),0,1,gray)
    end
  end
  local _,_,battery=app.system('device.battery')
  local status=notice~='' and notice or (awake and tr('Awake','保持唤醒') or tr('Auto sleep','自动休眠'))..'  ·  '..tostring(battery or 0)..'%'
  app.text(0,h-108,w,38,status,0,1,gray)
  local button=(w-24)/3
  app.button(1,0,h-60,button,52,face==0 and tr('Calendar','月历') or tr('Clock','时钟'),inverse and 3 or 0)
  app.button(2,button+12,h-60,button,52,tr('Invert','反色'),inverse and 3 or 0)
  app.button(3,2*(button+12),h-60,button,52,tr('Sync','校时'),inverse and 3 or 0)
end
local function readTime()
  local ok,t,wd,seconds,epoch,day=app.system('device.time')
  valid=ok;time=ok and t or '--:--';date=ok and day or '';weekday=ok and wd or 0
  if calendarDate~=date then
    calendarDate=date
    calendar=ok and almanac(tonumber(date:sub(1,4)),tonumber(date:sub(6,7)),tonumber(date:sub(9,10))) or nil
  end
  return time..date
end
local function sync()
  if not app.allowed('network') then notice=tr('Allow network access in Store settings','请在商店设置中允许联网');show();return end
  local ok,state=app.system('device.sync');syncing=ok
  notice=(ok or state=='connecting') and tr('Synchronizing time…','正在校时…') or tr('Sync failed; retry','校时失败，请重试');show()
end
return {
  on_start=function()
    lunarData=app.asset('assets/almanac.bin',0,603) or ''
    face=app.read('face')=='1' and 1 or 0;inverse=app.read('inverse')=='1'
    awake=app.system('power.keep_awake','on');lastMinute=readTime();show()
  end,
  on_select=function(id)
    if id==1 then face=1-face;app.write('face',tostring(face))
    elseif id==2 then inverse=not inverse;app.write('inverse',inverse and '1' or '0')
    elseif id==3 then sync();return end
    notice='';show()
  end,
  on_resize=show,
  on_tick=function()
    local current=readTime()
    if current~=lastMinute then lastMinute=current;show() end
    if syncing then
      local done,state=app.system('device.sync_status')
      if done then syncing=false;notice=state=='success' and tr('Time synchronized','校时成功') or tr('Sync failed; retry','校时失败，请重试');show() end
    end
  end,
  on_network=function(ok)
    if ok==1 then sync() else notice=tr('Network connection cancelled','已取消联网');show() end
  end,
  on_swipe=function() face=1-face;app.write('face',tostring(face));show() end,
  on_back=function() app.exit() end,
}
