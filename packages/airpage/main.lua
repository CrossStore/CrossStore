-- Upload, history and settings are Lua UI. Native services decode images and
-- preserve transactional cache recovery while the package owns interactions.
local tr=app.tr
local view,ready,live='home',false,false
local status,revision,count,historyPage,historyOffset='empty',-1,0,0,0
local selected=0
local function show()
  app.clear();app.canvas();app.title('AirPage')
  if view=='image' then return end
  local w,h=app.size()
  if not ready then
    app.text(8,60,w-16,160,tr('Allow network and device identity access in Store settings to use AirPage.','请在商店设置中允许联网和读取设备标识，才能使用 AirPage。'),1,0,0)
    return
  end
  if view=='history' then
    local rows=math.min(6,math.floor((h-140)/72))
    for i=1,rows do
      local index=historyOffset+i
      local ok,name,iw,ih,current=app.system('airpage.history','',index)
      if not ok then break end
      local label=current==1 and tr('Current image','当前图片') or name
      if current~=1 and #name>=16 then label=name:sub(1,4)..'-'..name:sub(5,6)..'-'..name:sub(7,8)..' '..name:sub(9,10)..':'..name:sub(11,12) end
      app.button(100+i,0,12+(i-1)*72,w,60,label..'  '..iw..'×'..ih,0)
    end
    local half=(w-12)/2
    app.button(8,0,h-110,half,44,tr('Previous','上一页'),0)
    app.button(9,half+12,h-110,half,44,tr('Next','下一页'),0)
    app.button(7,0,h-54,w,48,tr('Back','返回'),0)
    return
  end
  local ok,url=app.system('airpage.url')
  local size=math.min(w-32,h-260,260)
  if ok and size>=90 then app.qr((w-size)/2,4,size,url) end
  app.text(0,size+12,w,48,tr('Scan to send an image here','扫码，把图片发送到这里'),1,1,0)
  local states={ready=tr('Image ready · tap it to return','图片已就绪 · 点屏幕可返回'),empty=tr('No images yet','还没有图片'),downloading=tr('Downloading…','下载中…'),offline=tr('Offline · tap Refresh to reconnect','未联网 · 点刷新重新连接'),invalid=tr('Invalid image; previous image kept','图片无效，已保留之前的图片'),failed=tr('Could not finish; please retry','操作失败，请重试'),wallpaper=tr('Sleep wallpaper saved','已设为休眠壁纸')}
  app.text(0,size+62,w,44,states[status] or status,0,1,5)
  local half=(w-12)/2
  app.button(1,0,h-148,half,44,tr('Refresh','刷新'),3)
  app.button(2,half+12,h-148,half,44,tr('View image','查看图片'),0)
  app.button(3,0,h-96,half,44,tr('History','历史图片'),0)
  app.button(4,half+12,h-96,half,44,live and tr('Live: on','实时接收：开') or tr('Live: off','实时接收：关'),0)
  app.button(5,0,h-44,w,44,tr('Use as sleep wallpaper','设为休眠壁纸'),0)
end
local function refresh()
  local ok,state,items,version,image=app.system('airpage.status')
  if not ok then return end
  local changed=version~=revision or not ready
  ready=true;status=state;count=items;revision=version
  if image==1 then view='image'
  elseif view=='image' then view='home';changed=true end
  if changed and view~='image' then show() end
end
local function home()
  app.system('airpage.hide');view='home';show()
end
local function image(index)
  if app.system('airpage.show','',index) then selected=index;view='image'
  else app.title(tr('No image to show','没有可查看的图片')) end
end
return {
  on_start=function() app.system('airpage.start');show() end,
  on_tick=refresh,on_service=refresh,on_resize=show,on_network=refresh,
  on_select=function(id)
    if id==1 then app.system('airpage.fetch')
    elseif id==2 then image(0)
    elseif id==3 then app.system('airpage.page','first');historyOffset=0;view='history';show()
    elseif id==4 then
      if app.system('airpage.live',live and 'off' or 'on') then live=not live;show()
      else app.title(tr('Allow keeping awake in Store settings','请在商店设置中允许保持唤醒')) end
    elseif id==5 then
      if not app.system('airpage.wallpaper') then app.title(tr('Allow wallpaper access in Store settings','请在商店设置中允许设置壁纸')) end
    elseif id==7 then home()
    elseif id==8 or id==9 then
      local _,h=app.size();local rows=math.min(6,math.floor((h-140)/72))
      if id==9 then
        if historyOffset+rows<count then historyOffset=historyOffset+rows
        elseif app.system('airpage.page','next') then historyOffset=0 end
      else
        if historyOffset>0 then historyOffset=math.max(0,historyOffset-rows)
        elseif app.system('airpage.page','previous') then historyOffset=0 end
      end
      refresh();show()
    elseif id>=101 and id<=106 then image(historyOffset+id-100) end
  end,
  on_image=home,
  on_back=function() if view~='home' then home() else app.exit() end end,
  on_swipe=function(_,direction)
    if view=='image' then image(math.max(0,math.min(count,selected+(direction=='left' and 1 or -1)))) end
  end,
}
