local count,sound_on,confirm=0,true,false
local function show()
  app.clear();app.title(app.tr("Woodfish","木鱼"));app.canvas()
  local w,h=app.size()
  if confirm then
    app.text(0,h*.2,w,90,app.tr("Reset the counter?","将计数清零？"),2,1)
    app.button(4,0,h*.55,(w-12)/2,54,app.tr("Keep count","保留计数"),0)
    app.button(5,(w+12)/2,h*.55,(w-12)/2,54,app.tr("Reset","清零"),3)
    return
  end
  app.text(0,12,w,32,app.tr("ONE TAP, ONE QUIET MOMENT","一声一念，片刻安静"),0,1,6)
  app.text(0,54,w,76,tostring(count),3,1)
  local size=math.min(w*.76,h*.46)
  local x,y=(w-size)/2,h*.32
  app.circle(x,y,size,size*.65,0)
  app.circle(x+size*.07,y+size*.06,size*.86,size*.53,15)
  app.circle(x+size*.17,y+size*.08,size*.66,size*.41,0)
  app.box(x+size*.2,y+size*.4,size*.6,size*.06,15,4)
  app.circle(x+size*.36,y+size*.32,size*.28,size*.2,15)
  app.hit(1,0,140,w,h-232)
  app.text(0,h-154,w,36,app.tr("Tap the woodfish","轻敲木鱼"),1,1)
  local sound_label=not app.has("buzzer") and app.tr("No buzzer","无蜂鸣器") or not app.allowed("sound") and
    app.tr("Sound not allowed","声音未授权") or sound_on and app.tr("Sound on","声音开") or app.tr("Muted","静音")
  app.button(2,0,h-68,(w-12)/2,52,app.tr("Reset","清零"),0)
  app.button(3,(w+12)/2,h-68,(w-12)/2,52,sound_label,sound_on and 2 or 0)
end
return {
  on_start=function() count=tonumber(app.read("count")) or 0;sound_on=app.read("sound")~="0";show() end,
  on_resize=show,
  on_select=function(i)
    if i==1 then
      if sound_on then app.sound("woodfish") end
      count=count+1;app.write("count",tostring(count))
    elseif i==2 then confirm=true
    elseif i==3 then sound_on=not sound_on;app.write("sound",sound_on and "1" or "0")
    elseif i==4 then confirm=false
    elseif i==5 then confirm=false;count=0;app.write("count","0") end
    show()
  end,
  on_back=function() if confirm then confirm=false;show() else app.exit() end end,
}
