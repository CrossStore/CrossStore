-- Original CrossStore AirTune implementation. MIT; see LICENSE and README.md.
local tr=app.tr
local presets={
  {name=tr('Beijing Music','北京音乐广播'),url='http://lhttp.qingting.fm/live/332/64k.mp3',note=tr('Music · 64k MP3','音乐 · 64k MP3')},
  {name=tr('Beijing News','北京新闻广播'),url='http://lhttp.qingting.fm/live/339/64k.mp3',note=tr('News · 64k MP3','新闻 · 64k MP3')},
  {name='Groove Salad',url='http://ice1.somafm.com/groovesalad-128-mp3',note=tr('SomaFM · Downtempo','SomaFM · 舒缓节拍')},
  {name='Drone Zone',url='http://ice1.somafm.com/dronezone-128-mp3',note=tr('SomaFM · Ambient','SomaFM · 氛围音乐')},
  {name='Secret Agent',url='http://ice1.somafm.com/secretagent-128-mp3',note=tr('SomaFM · Cinematic','SomaFM · 电影配乐风格')},
  {name='Beat Blender',url='http://ice1.somafm.com/beatblender-128-mp3',note=tr('SomaFM · Deep house','SomaFM · 深邃浩室')},
}
local favorites,station={},presets[1]
local view,page='now',0
local state,volume,error_code='idle',50,'none'
local initial_error=''
local initialized,last_poll,notice=false,-1000,''
local draft_name,draft_url,input_kind,remove_slot='','','',nil
local visible={}
local errors={
  invalid_url=tr('Enter a valid HTTP(S) address','请输入有效的 HTTP(S) 地址'),
  unsupported=tr('Use a direct MP3 stream','请使用 MP3 直播直链'),
  network=tr('Connection failed. Try again.','连接失败，请重新收听'),
  timeout=tr('Station timed out. Try again.','电台响应超时，请重新收听'),
  no_memory=tr('Not enough playback memory','播放内存不足，请退出后重试'),
  audio=tr('Speaker unavailable','扬声器暂不可用'),
  offline=tr('Wi-Fi is disconnected','Wi-Fi 未连接'),
  permission=tr('Allow network and sound in Store settings','请在商店设置允许网络与声音'),
}
local function valid_name(text)
  if not text or #text==0 or #text>72 then return false end
  for i=1,#text do local c=string.byte(text,i);if c<32 or c==127 then return false end end
  return true
end
local function valid_url(text,maximum)
  if not text or #text<10 or #text>maximum then return false end
  local prefix=string.sub(text,1,7)=='http://' and 7 or string.sub(text,1,8)=='https://' and 8 or 0
  if prefix==0 or string.sub(text,prefix+1,prefix+1)=='/' then return false end
  local path=''
  for i=1,#text do
    local c=string.byte(text,i)
    if c<=32 or c==127 or c==92 or c==64 or c==35 then return false end
    if c==63 and path=='' then path=string.sub(text,1,i-1) end
  end
  if path=='' then path=text end
  path=string.lower(path)
  for _,suffix in ipairs({'.m3u8','.m3u','.pls','.aac','.mp4'}) do
    if string.sub(path,-#suffix)==suffix then return false end
  end
  return true
end
local function encode(item) return item.name..'\n'..item.url end
local function decode(text)
  if not text then return nil end
  for i=1,#text do
    if string.byte(text,i)==10 then
      local name,url=string.sub(text,1,i-1),string.sub(text,i+1)
      if valid_name(name) and valid_url(url,511) then return {name=name,url=url} end
      return nil
    end
  end
end
local function key(slot) return string.format('favorite_%02d',slot) end
local function save(key_name,text)
  if app.write(key_name,text) then notice='';return true end
  notice=tr('Save failed. Nothing was changed; retry.','保存失败，未更改记录，请重试')
  return false
end
local function favorite_slot(url)
  for i=1,12 do if favorites[i] and favorites[i].url==url then return i end end
end
local function add_favorite(item)
  if favorite_slot(item.url) then notice=tr('Already in favorites','已在收藏中');return true end
  for i=1,12 do
    if not favorites[i] then
      if not save(key(i),encode(item)) then return false end
      favorites[i]={name=item.name,url=item.url}
      notice=tr('Added to favorites','已加入收藏');return true
    end
  end
  notice=tr('12 favorites maximum. Remove one first.','最多收藏 12 台，请先移除一台');return false
end
local function playing() return state=='playing' or state=='buffering' or state=='connecting' end
local function status_text()
  if not initialized then return tr('UNAVAILABLE','暂不可用') end
  if state=='error' then return errors[error_code] or tr('Playback failed. Try again.','播放失败，请重新收听') end
  if state=='connecting' then return tr('CONNECTING','正在连接') end
  if state=='buffering' then return tr('BUFFERING','正在缓冲') end
  if state=='playing' then return tr('ON AIR','正在播放') end
  return tr('READY TO LISTEN','准备收听')
end
local function sync()
  local ok,next_state,next_volume,_,_,code=app.system('radio.status')
  if not ok then
    next_state='error';code=code~='' and code or 'permission'
  end
  if next_state~='idle' and next_state~='connecting' and next_state~='buffering' and next_state~='playing' and next_state~='error' then
    next_state='error';code='audio'
  end
  next_volume=math.max(0,math.min(100,tonumber(next_volume) or volume))
  local changed=state~=next_state or volume~=next_volume or error_code~=code
  state,volume,error_code=next_state,next_volume,code
  return changed
end
local function initialize()
  if not app.has('radio_audio') or not app.has('psram') or not app.has('wifi') then
    notice=tr('This device does not support radio playback','此设备不支持网络电台播放');initial_error=notice;initialized=false;return false
  end
  if not app.allowed('network') or not app.allowed('sound') then notice=errors.permission;initial_error=notice;initialized=false;return false end
  initialized=app.system('radio.start')
  if initialized then initialized=app.system('radio.volume','',volume) end
  initial_error=initialized and '' or errors.permission
  if not initialized then notice=initial_error end
  return initialized
end
local function play(item)
  if not initialized and not initialize() then return end
  if not save('last_station',encode(item)) then return end
  -- Native playback is queued and owns Wi-Fi selection/connection state.
  local ok,_,_,_,_,code=app.system('radio.play',item.url)
  if ok then station={name=item.name,url=item.url,note=item.note}
  else notice=errors[code] or tr('Unable to start this station','暂时无法播放此电台') end
  sync();view='now'
end
local function compact(text,limit)
  if #text<=limit then return text end
  local stop=limit-3
  while stop>0 and string.byte(text,stop+1)>=128 and string.byte(text,stop+1)<192 do stop=stop-1 end
  return string.sub(text,1,stop)..'...'
end
local function text(x,y,w,h,label,font,align,gray) app.text(x,y,w,h,label,font or 1,align or 0,gray or 0) end
local function tabs(w)
  local width=(w-16)/3
  app.button(1,0,0,width,44,tr('Playing','正在播放'),view=='now' and 2 or 0)
  app.button(2,width+8,0,width,44,tr('Stations','选台'),view=='stations' and 2 or 0)
  app.button(3,2*(width+8),0,width,44,tr('Favorites','收藏'),view=='favorites' and 2 or 0)
end
local function radio_art(x,y,w,h)
  if h<90 then return end
  local height,width=math.min(h,180),math.min(w,330)
  x=x+(w-width)/2;y=y+(h-height)/2
  app.box(x,y,width,height,13,12)
  app.box(x+8,y+8,width-16,height-16,15,8)
  local speaker=math.floor(width*.46)
  for row=0,5 do app.box(x+20,y+20+row*(height-40)/6,speaker-20,2,7) end
  local dial=math.min(height-32,width*.29)
  app.circle(x+width-dial-20,y+(height-dial)/2,dial,dial,0)
  app.circle(x+width-dial-15,y+(height-dial)/2+5,dial-10,dial-10,15)
  app.box(x+width-dial/2-21,y+(height-dial)/2+12,3,math.max(8,dial*.28),0)
end
local function volume_control(x,y,w)
  app.button(12,x,y,44,44,'-',0)
  app.button(13,x+w-44,y,44,44,'+',0)
  local inner=w-104
  text(x+52,y,inner,20,tr('Volume ','音量 ')..volume..'%',0,1)
  app.box(x+52,y+28,inner,8,12,2)
  if volume>0 then app.box(x+52,y+28,math.max(2,math.floor(inner*volume/100)),8,0,2) end
end
local function now_view(w,h)
  local wide=w>=600 and w>h
  local hero_w=wide and math.floor(w*.52)-8 or w
  local action_y=wide and 92 or h-148
  local hero_bottom=wide and h-40 or action_y-8
  text(6,62,hero_w-12,38,station.name,2,1)
  text(6,104,hero_w-12,24,station.note or tr('YOUR STATION · MP3','我的电台 · MP3'),0,1,6)
  if hero_bottom>230 then radio_art(8,140,hero_w-16,hero_bottom-172) end
  if not wide then text(6,hero_bottom-28,hero_w-12,24,status_text(),0,1) end
  local x=wide and hero_w+16 or 0
  local controls=wide and w-x or w
  local label=playing() and tr('Stop','停止') or tr('Listen','收听')
  local favorite=favorite_slot(station.url)
  if wide then
    text(x,60,controls,24,status_text(),0,1)
    app.button(10,x,action_y,controls,44,label,3)
    app.button(11,x,action_y+52,controls,44,favorite and tr('Saved','已收藏') or tr('Save station','收藏电台'),favorite and 2 or 0)
    volume_control(x,action_y+104,controls)
  else
    app.button(10,0,action_y,(w-8)/2,48,label,3)
    app.button(11,(w+8)/2,action_y,(w-8)/2,48,favorite and tr('Saved','已收藏') or tr('Save','收藏'),favorite and 2 or 0)
    volume_control(0,action_y+56,w)
  end
end
local function list_view(w,h)
  local items={}
  if view=='stations' then
    for _,item in ipairs(presets) do items[#items+1]={item=item} end
  else
    for i=1,12 do if favorites[i] then items[#items+1]={item=favorites[i],slot=i} end end
  end
  local capacity=math.max(1,math.floor((h-176)/68))
  local pages=math.max(1,math.ceil(#items/capacity));page=math.min(page,pages-1)
  text(0,52,w,22,view=='stations' and tr('HANDPICKED · MP3 LIVE','精选电台 · MP3 直播') or tr('YOUR DIAL · ','我的电台 · ')..#items..'/12',0,0,6)
  visible={}
  for row=1,capacity do
    local source=items[page*capacity+row]
    if not source then break end
    visible[row]=source
    local y=80+(row-1)*68
    local width=source.slot and w-52 or w
    app.box(0,y,width,60,11,6,1)
    app.hit(100+row,0,y,width,60)
    text(12,y+6,width-24,25,source.item.name,1)
    local subtitle=source.item.note or tr('Saved station · MP3','已收藏电台 · MP3')
    text(12,y+33,width-24,20,subtitle,0,0,6)
    if source.slot then app.button(200+row,w-44,y+8,44,44,'-',0) end
  end
  if #items==0 then
    text(8,98,w-16,56,tr('Keep your favorite frequencies here.','把喜欢的声音，留在这里。'),1,1,6)
    text(8,158,w-16,48,tr('Save a station, or add its MP3 address.','收听时点收藏，或添加 MP3 地址。'),0,1,6)
  end
  text(0,h-112,w,20,tostring(page+1)..' / '..pages,0,1,6)
  if page>0 then app.button(20,0,h-84,44,44,'←',0) end
  app.button(30,52,h-84,w-104,44,tr('Add address','添加地址'),0)
  if page+1<pages then app.button(21,w-44,h-84,44,44,'→',0) end
end
local function custom_view(w,h)
  if h<320 then
    app.button(31,0,64,w,44,draft_name~='' and draft_name or tr('Station name','电台名称'),0)
    app.button(32,0,116,w,44,draft_url~='' and compact(draft_url,70) or tr('MP3 address','MP3 直播地址'),0)
    app.button(34,0,h-92,(w-8)/2,48,tr('Cancel','取消'),0)
    app.button(33,(w+8)/2,h-92,(w-8)/2,48,tr('Save','加入收藏'),3)
    return
  end
  text(0,54,w,22,tr('STATION NAME','电台名称'),0,0,6)
  app.button(31,0,80,w,44,draft_name~='' and draft_name or tr('Name this station','为电台起个名字'),0)
  text(0,132,w,22,tr('DIRECT MP3 ADDRESS','MP3 直播直链'),0,0,6)
  app.button(32,0,158,w,48,draft_url~='' and compact(draft_url,70) or 'http:// ...',0)
  app.button(34,0,h-92,(w-8)/2,48,tr('Cancel','取消'),0)
  app.button(33,(w+8)/2,h-92,(w-8)/2,48,tr('Save','加入收藏'),3)
end
local function show()
  app.clear();app.title('AirTune');app.canvas()
  local w,h=app.size();tabs(w)
  if view=='now' then now_view(w,h)
  elseif view=='stations' or view=='favorites' then list_view(w,h)
  elseif view=='custom' then custom_view(w,h)
  elseif view=='remove' then
    text(8,80,w-16,58,tr('Remove from favorites?','从收藏中移除此电台？'),2,1)
    text(8,148,w-16,40,favorites[remove_slot].name,1,1,6)
    app.button(40,0,h-92,(w-8)/2,48,tr('Keep','保留'),0)
    app.button(41,(w+8)/2,h-92,(w-8)/2,48,tr('Remove','移除'),3)
  end
  text(2,h-32,w-4,30,notice~='' and notice or initial_error~='' and initial_error or tr('Live radio · Stops when you leave','直播电台 · 离开应用即停止'),0,1,6)
end
local function tick(force)
  local now=app.millis()
  if not force and now-last_poll<500 then return end
  last_poll=now
  if initialized and sync() then show() end
end
local function adjust_volume(delta)
  if not initialized or not app.allowed('network') or not app.allowed('sound') then
    notice=errors.permission;return
  end
  sync()
  local next_volume=math.max(0,math.min(100,volume+delta))
  if next_volume==volume then return end
  if save('volume',tostring(next_volume)) then
    local ok=app.system('radio.volume','',next_volume)
    if not ok then notice=errors.audio end
    sync()
  end
end
return {
  on_start=function()
    for i=1,12 do favorites[i]=decode(app.read(key(i))) end
    station=decode(app.read('last_station')) or presets[1]
    local saved=tonumber(app.read('volume'))
    if saved and saved>=0 and saved<=100 then volume=math.floor(saved) end
    if initialize() then sync() end
    show()
  end,
  on_resize=show,
  on_tick=function() tick(false) end,
  on_service=function() tick(true) end,
  on_key=function(_,direction)
    if view~='now' or (direction~='up' and direction~='down') then return false end
    adjust_volume(direction=='up' and 10 or -10)
    show()
    return true
  end,
  on_network=function(ok)
    if ok==0 then notice=tr('Connection cancelled. Tap Listen to retry.','连接已取消，可点收听重试') end
    if initialized then sync() end
    show()
  end,
  on_input=function(_,value)
    local field=input_kind;input_kind=''
    if view~='custom' then return end
    if field=='name' then
      if valid_name(value) then draft_name=value;notice='' else notice=tr('Use a name up to 72 bytes','名称不能为空，最多 24 个汉字') end
    elseif field=='url' then
      if valid_url(value,191) then draft_url=value;notice='' else notice=tr('Use a direct HTTP(S) MP3 URL, up to 191 bytes','请输入不超过 191 字节的 HTTP(S) MP3 直链') end
    end
    show()
  end,
  on_select=function(id)
    if id>=1 and id<=3 then view=({'now','stations','favorites'})[id];page=0;input_kind='';notice=''
    elseif id==10 then
      if playing() then app.system('radio.stop');sync();notice='' else play(station) end
    elseif id==11 then
      local slot=favorite_slot(station.url)
      if slot then remove_slot=slot;view='remove' else add_favorite(station) end
    elseif id==12 or id==13 then
      adjust_volume(id==12 and -10 or 10)
    elseif id==20 then page=math.max(0,page-1)
    elseif id==21 then page=page+1
    elseif id==30 then draft_name='';draft_url='';view='custom';notice=''
    elseif id==31 then input_kind='name';app.input(tr('Station name','电台名称'),draft_name)
    elseif id==32 then input_kind='url';app.input(tr('MP3 stream URL','MP3 直播地址'),draft_url)
    elseif id==33 then
      if valid_name(draft_name) and valid_url(draft_url,191) then
        if add_favorite({name=draft_name,url=draft_url}) then view='favorites';page=0;input_kind='' end
      else notice=tr('Enter a name and an MP3 stream address','请填写电台名称和 MP3 直播地址') end
    elseif id==34 or id==40 then view='favorites';input_kind='';notice=''
    elseif id==41 and remove_slot then
      if save(key(remove_slot),'') then favorites[remove_slot]=nil;remove_slot=nil;view='favorites' end
    elseif id>100 and id<200 and visible[id-100] then play(visible[id-100].item)
    elseif id>200 and id<300 and visible[id-200] then remove_slot=visible[id-200].slot;view='remove' end
    show()
  end,
  on_back=function()
    input_kind=''
    if view~='now' then view='now';notice='';show()
    else app.system('radio.stop');app.exit() end
  end,
  on_stop=function() app.system('radio.stop') end,
}
