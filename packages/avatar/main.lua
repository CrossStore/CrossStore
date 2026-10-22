-- Procedural ink portraits. Generation and drawing live in the package.
local seed=1
local function generator(value)
  return function(lo,hi)
    value=value~((value<<13)&0xffffffff);value=value~(value>>17);value=(value~(value<<5))&0xffffffff
    return lo+(value&0xffffff)/0x1000000*(hi-lo)
  end
end
local function show()
  app.clear();app.title(app.tr('Ink portrait','随机头像'));app.canvas()
  local w,h=app.size();local size=math.min(w-20,h-100);local ox,oy=(w-size)/2,(h-80-size)/2
  local random=generator(seed)
  local function point(x,y) return ox+(x+120)/240*size,oy+(y+140)/280*size end
  local function line(x1,y1,x2,y2,stroke,gray)
    x1,y1=point(x1,y1);x2,y2=point(x2,y2)
    if x1>x2 then x1,x2=x2,x1;y1,y2=y2,y1 end
    app.line(x1,math.min(y1,y2),math.max(1,x2-x1+1),math.max(1,math.abs(y2-y1)+1),gray or 0,y1>y2 and 1 or 0,stroke or 2)
  end
  local function curve(ax,ay,bx,by,cx,cy,steps,stroke)
    local px,py=ax,ay
    for i=1,steps do
      local t=i/steps;local u=1-t
      local x=u*u*ax+2*u*t*bx+t*t*cx;local y=u*u*ay+2*u*t*by+t*t*cy
      line(px,py,x,y,stroke);px,py=x,y
    end
  end
  local a,b,k=random(62,90),random(76,100),random(-.0018,.0018)
  local skew,wobble=random(-10,10),random(1,4)
  local face={}
  for i=0,64 do
    local angle=i*math.pi/32;local y=math.sin(angle)*b
    face[i+1]={math.cos(angle)*a/math.sqrt(1+k*y)+skew*math.sin(angle)+wobble*math.sin(3*angle),y}
    if i>0 then line(face[i][1],face[i][2],face[i+1][1],face[i+1][2]) end
  end
  -- The low-contrast collar anchors the composition without competing with the face.
  curve(-42,b-5,-62,b+9,-82,125,5,2);curve(42,b-5,62,b+9,82,125,5,2)
  curve(-42,b-5,0,b+29,42,b-5,10,2)
  for eye=1,2 do
    local cx=(eye==1 and -1 or 1)*random(27,38);local cy=random(-27,-14)
    local radius=random(15,21);local lift=random(5,13)
    curve(cx-radius,cy,cx,cy-lift,cx+radius,cy,8,2)
    curve(cx-radius,cy,cx,cy+random(5,16),cx+radius,cy,8,2)
    local px,py=point(cx+random(-5,5),cy+random(0,3));local d=size*random(.018,.028)
    app.circle(px-d/2,py-d/2,d,d,0)
  end
  if random(0,1)<.5 then curve(-7,12,19,18,5,-8,8,2)
  else
    for _,x in ipairs({-6,6}) do local px,py=point(x,12);app.circle(px,py,math.max(2,size*.009),math.max(2,size*.009),0) end
  end
  local mouth=random(20,36);local my=random(34,49)
  curve(-mouth,my,random(-7,7),my+random(-15,20),mouth,my+random(-5,5),12,2)
  local strands=math.floor(random(8,19))
  for i=1,strands do
    local x=-a*.82+(i-1)*a*1.64/math.max(1,strands-1)
    local y=-b*math.sqrt(math.max(0,1-x*x/(a*a)))
    curve(x,y+random(0,10),x+random(-20,20),y-random(12,28),x+random(-22,22),y+random(-6,12),5,2)
  end
  app.button(1,0,h-58,(w-12)/2,52,app.tr('Another face','换个头像'),0)
  app.button(2,(w+12)/2,h-58,(w-12)/2,52,app.tr('Save SVG','保存 SVG'),3)
end
local function fresh()
  seed=math.random(1,0x7fffffff);app.write('seed',tostring(seed));show()
end
return {
  on_start=function()
    math.randomseed(app.millis());seed=tonumber(app.read('seed')) or math.random(1,0x7fffffff)
    if seed<1 or seed>0xffffffff then seed=1 end
    show()
  end,
  on_resize=show,
  on_select=function(id)
    if id==1 then fresh()
    elseif id==2 then
      if not app.system('canvas.export','portrait') then
        app.title(app.tr('Allow file exports in Store settings','请在商店设置中允许导出文件'))
      end
    end
  end,
  on_export=function(ok,path)
    if ok==1 then app.title(app.tr('Saved: ','已保存：')..path)
    else app.title(app.tr('Save failed; check storage','保存失败，请检查存储卡')) end
  end,
  on_swipe=function() fresh() end,
  on_back=function() app.exit() end,
}
