-- Shared public canvas. Tap to select; Place is the explicit publishing action.
local tr=app.tr
local connected,revision,view=false,-1,'intro'
local pixels=string.rep('F',6000)
local cx,cy,color=30,50,3
local status,pending,retry,notice='connecting',0,0,''
local board={}
local function show()
  app.clear();app.title(tr('Pixel Switch','像素画布'));app.canvas()
  local w,h=app.size()
  if view=='intro' then
    app.text(0,24,w,52,tr('One canvas. Everyone.','一张画布，一起创作。'),3,1,0)
    app.text(12,100,w-24,h-210,tr('Draw with other CrossMux readers. Every placed pixel is shared publicly. Select a point and shade, then tap Place. Up to 10 pixels per 10 seconds.','和其他读者共同绘画。每个落笔的像素都会公开共享。先选择位置和灰阶，再点“落笔”；每 10 秒最多 10 个像素。'),1,0,5)
    app.button(1,0,h-68,w,56,tr('Join the canvas','进入公共画布'),3)
    return
  end
  local states={connecting=tr('Connecting…','连接中…'),waiting=tr('Loading canvas…','正在加载画布…'),online=tr('Connected','已连接'),paused=tr('Disconnected','连接已暂停'),error=tr('Could not connect','连接失败')}
  app.text(0,0,w,36,notice~='' and notice or states[status] or status,0,1,0)
  local bh=math.min(h-198,(w-16)*100/60);local bw=bh*60/100
  board={x=(w-bw)/2,y=46,w=bw,h=bh}
  app.box(board.x-2,board.y-2,bw+4,bh+4,0)
  app.raster(board.x,board.y,bw,bh,60,100,pixels)
  app.hit(10,board.x,board.y,bw,bh)
  local x=board.x+cx*bw/60;local y=board.y+cy*bh/100
  local size=math.max(8,bw/60+4)
  app.box(x-size/2,y-size/2,size,size,15,0,2)
  app.box(x-size/2-2,y-size/2-2,size+4,size+4,0,0,1)
  local sw=(w-36)/4
  for i=0,3 do
    app.button(20+i,i*(sw+12),h-128,sw,44,'',i==color and 3 or 0)
    app.box(i*(sw+12)+8,h-120,sw-16,28,15-i*5,4)
  end
  local half=(w-12)/2
  app.button(30,0,h-70,half,54,status=='online' and tr('Place','落笔') or tr('Reconnect','重新连接'),3)
  local value=retry>0 and math.ceil(retry/1000)..tr('s wait','秒后重试') or pending>0 and pending..tr(' pending','点待发送') or string.format('%02d, %02d',cx,cy)
  app.button(31,half+12,h-70,half,54,value,0)
end
local function connect()
  if not app.allowed('network') then notice=tr('Allow network access in Store settings','请在商店设置中允许联网');show();return end
  connected=app.system('pixel.start');view='canvas';notice=''
  if not connected then notice=tr('Could not start; reopen to retry','无法启动，请退出后重试') end
  app.system('power.keep_awake','on');show()
end
local function refresh()
  if not connected then return end
  local ok,state,rev,waiting,delay=app.system('pixel.status')
  if not ok then return end
  local changed=state~=status or waiting~=pending or math.ceil(delay/1000)~=math.ceil(retry/1000)
  status,pending,retry=state,waiting,delay
  if rev~=revision then
    local rows={}
    for row=0,99 do
      local ready,data=app.system('pixel.row','',row)
      if not ready or #data~=60 then return end
      rows[#rows+1]=data
    end
    pixels=table.concat(rows);revision=rev;changed=true
  end
  if changed then show() end
end
return {
  on_start=show,on_resize=show,on_tick=refresh,
  on_network=function(ok) if ok~=1 then status='paused' end;show() end,
  on_select=function(id,_,x,y)
    notice=''
    if id==1 then connect()
    elseif id==10 then
      if x>=0 and y>=0 then
        cx=math.max(0,math.min(59,math.floor((x-board.x)/board.w*60)))
        cy=math.max(0,math.min(99,math.floor((y-board.y)/board.h*100)))
      else cx=(cx+1)%60 end
      show()
    elseif id>=20 and id<=23 then color=id-20;show()
    elseif id==30 then
      if status~='online' then connect();return end
      local ok,reason=app.system('pixel.place',tostring(color),cy*60+cx)
      if not ok then notice=reason=='rate_limited' and tr('10 pixels per 10 seconds','每 10 秒最多 10 个像素') or tr('Not sent; reconnect','未发送，请重新连接') end
      refresh();show()
    elseif id==31 then app.input(tr('Position x,y (0–59,0–99)','位置 x,y（0–59,0–99）'),cx..','..cy)
    end
  end,
  on_input=function(_,text)
    local comma=0
    for i=1,#text do if text:byte(i)==44 then comma=i;break end end
    local x=tonumber(text:sub(1,comma-1));local y=tonumber(text:sub(comma+1))
    if comma>0 and x and y and x%1==0 and y%1==0 and x>=0 and x<60 and y>=0 and y<100 then cx,cy=x,y
    else notice=tr('Use x,y within 0–59,0–99','请输入范围内的 x,y：0–59,0–99') end
    show()
  end,
  on_swipe=function(_,direction)
    if view~='canvas' then return end
    if direction=='left' then cx=math.max(0,cx-1) elseif direction=='right' then cx=math.min(59,cx+1)
    elseif direction=='up' then cy=math.max(0,cy-1) elseif direction=='down' then cy=math.min(99,cy+1) end
    show()
  end,
  on_back=function() app.exit() end,
}
