-- Pixel buddy portraits adapted from claude-desktop-buddy.
-- Copyright 2026 Anthropic, PBC. SPDX-License-Identifier: MIT
local sprites={
  {"            ","    __      ","  <(? )___  ","   (  ._>   ","    `--'    "},
  {"            ","    (?>     ","    ||      ","  _(__)_    ","   ^^^^     "},
  {"            ","   .----.   ","  ( ?  ? )  ","  (      )  ","   `----'   "},
  {"            ","   /\\_/\\    ","  ( ?   ? ) ","  (  w   )  ","  (\")_(\")   "},
  {"            ","  /^\\  /^\\  "," <  ?    ? >"," (   ww   ) ","  `-vvvv-'  "},
  {"            ","   .----.   ","  ( ?  ? )  ","  (______)  ","  /\\/\\/\\/\\  "},
  {"            ","   /\\  /\\   ","  ((?)(?))  ","  (  ><  )  ","   `----'   "},
  {"   .---.    ","  ( ?>? )   "," /(     )\\  ","  `-----'   ","   J   L    "},
  {"            ","   _,--._   ","  ( ?    ?) "," /[______]\\ ","  ``    ``  "},
  {"  \\\\  /     ","    .--.    ","  _( ?? )_  "," (___@@___) ","  ~~~~~~~~  "},
  {"            ","   .----.   ","  ( ?    ? )","  |   __   |","  ~`~``~`~  "},
  {"            ","}~(______)~{","}~( ?  ? )~{","  ( .--. )  ","  (_/  \\_)  "},
  {"            ","  n______n  "," ( ?    ? ) "," (   oo   ) ","  `------'  "},
  {"            "," n  ____  n "," | |?  ?| | "," |_|    |_| ","   |    |   "},
  {"            ","   .[||].   ","  [ ?    ? ]","  [ ==== ]  ","  `------'  "},
  {"    (\\_/)   ","   ( ? ? )  ","  =(  v  )= ","   (\")_(\")  ","            "},
  {"            "," .-o-OO-o-. ","(__________)","   |?   ?|  ","   |____|   "},
  {"            ","  /\\____/\\  "," ( ?    ? ) "," (   ..   ) ","  `------'  "}
}
local hats={"","    /\\     ","   [___]    ","   _/|\\_    ","   (---)    ","    /\\     ","   (___)    ","    <(')    "}
local eyes={'.','*','x','O','@','o'}
local species_en={'Duck','Goose','Blob','Cat','Dragon','Octopus','Owl','Penguin','Turtle','Snail','Ghost','Axolotl','Capybara','Cactus','Robot','Rabbit','Mushroom','Chonk'}
local species_zh={'鸭子','鹅','团子','猫','龙','章鱼','猫头鹰','企鹅','乌龟','蜗牛','幽灵','美西螈','水豚','仙人掌','机器人','兔子','蘑菇','胖猫'}
local rarity_en={'Common','Uncommon','Rare','Epic','Legendary'}
local rarity_zh={'普通','少见','稀有','史诗','传说'}
local prefixes={'Nib','Pip','Crum','Sprig','Tink','Moss','Quib','Wob','Dusk','Fizz','Plop','Brim','Nox','Sprock','Puck','Mallow'}
local suffixes={'let','bit','bun','wick','puff','pod','kin','mote','zip','snoot','sprout','fuzz','blink','pebble','crumb','bop'}
local function multiply(a,b)
  local al,ah,bl,bh=a&0xffffffff,a>>32,b&0xffffffff,b>>32
  local p00,p01,p10,p11=al*bl,al*bh,ah*bl,ah*bh
  local low,carry=p00,0
  local next=low+(p01<<32)
  if (next~math.mininteger)<(low~math.mininteger) then carry=carry+1 end
  low=next;next=low+(p10<<32)
  if (next~math.mininteger)<(low~math.mininteger) then carry=carry+1 end
  return next,p11+(p01>>32)+(p10>>32)+carry
end
local function mix(a,b) local lo,hi=multiply(a,b);return lo~hi end
local function seed_for(id)
  local secret0,secret1=0xa0761d6478bd642f,0xe7037ed1a0b428db
  local s=id:lower()..'friend-2026-401'..'\0'
  local state=mix(secret0,secret1)
  state=mix(string.unpack('<I8',s,1)~secret1,string.unpack('<I8',s,9)~state)
  local a,b=multiply(string.unpack('<I8',s,12)~secret1,string.unpack('<I8',s,20)~state)
  return mix(a~secret0~27,b~secret1)&0xffffffff
end
local function generator(seed)
  return function(count)
    seed=(seed+0x6d2b79f5)&0xffffffff
    local t=((seed~(seed>>15))*(1|seed))&0xffffffff
    t=t~((t+(((t~(t>>7))*(61|t))&0xffffffff))&0xffffffff)
    t=(t~(t>>14))&0xffffffff
    return count and ((t*count)>>32) or t
  end
end
local function generate(id)
  local seed=seed_for(id);local rng=generator(seed);local roll=rng(100)
  local r=roll<60 and 1 or roll<85 and 2 or roll<95 and 3 or roll<99 and 4 or 5
  local t={rarity=r,species=rng(18)+1,eye=rng(6)+1,hat=1,stats={}}
  if r>1 then t.hat=rng(8)+1 end
  t.shiny=rng()<42949673
  local peak,dump=rng(5)+1,0;repeat dump=rng(5)+1 until dump~=peak
  local floor=({5,15,25,35,50})[r]
  for i=1,5 do
    t.stats[i]=i==peak and math.min(100,floor+50+rng(30)) or i==dump and math.max(1,floor-10+rng(15)) or floor+rng(40)
  end
  local names=generator(seed~0x0badd1e5);t.name=prefixes[names(16)+1]..suffixes[names(16)+1]
  return t
end
local traits,claimed,details,blink=nil,false,false,false
local function show()
  app.clear();app.title(app.tr('Buddy','电子宠物'));app.canvas()
  local w,h=app.size()
  if not traits then app.text(0,40,w,h-80,app.tr('Allow device identity in Store settings to meet your buddy.','请在商店设置中允许读取设备标识，领取属于这台设备的宠物。'),1,1);return end
  if not claimed then
    app.text(0,12,w,60,app.tr('A little friend awaits','有位小伙伴在等你'),2,1)
    local z=math.min(w*.45,h*.36);app.circle((w-z)/2,h*.3,z,z*1.2,0)
    app.circle((w-z)/2+z*.25,h*.3+z*.2,z*.18,z*.18,15)
    app.button(1,0,h-70,w,54,app.tr('Meet your buddy','领取我的宠物'),3);return
  end
  app.text(0,0,w,60,traits.name,3,1)
  app.text(0,66,w,32,app.tr(species_en[traits.species],species_zh[traits.species])..' · '..app.tr(rarity_en[traits.rarity],rarity_zh[traits.rarity]),0,1,6)
  if details then
    local labels={{'Focus','专注'},{'Patience','耐心'},{'Luck','幸运'},{'Wisdom','智慧'},{'Courage','勇气'}}
    local step=math.min(82,(h-200)/5)
    for i,value in ipairs(traits.stats) do
      local y=114+(i-1)*step
      app.text(0,y,w*.65,30,app.tr(labels[i][1],labels[i][2]),1,0)
      app.text(w*.72,y,w*.28,30,tostring(value),1,2)
      app.box(0,y+36,w,6,12,3);app.box(0,y+36,math.max(1,w*value/100),6,0,3)
    end
  else
    local cell=math.min(30,w/15,(h-200)/9);local y=126+(h-200-cell*7)/2
    local portrait={}
    if traits.hat>1 then portrait[#portrait+1]=hats[traits.hat] end
    for _,line in ipairs(sprites[traits.species]) do portrait[#portrait+1]=line end
    for r,line in ipairs(portrait) do
      for c=1,#line do local ch=line:sub(c,c);if ch=='?' then ch=blink and '-' or eyes[traits.eye] end
        if ch~=' ' then app.text((w-#line*cell)/2+(c-1)*cell,y+(r-1)*cell,cell,cell+6,ch,1,1) end
      end
    end
    if traits.shiny then app.text(w-50,115,40,40,'*',2,1) end
  end
  app.button(2,0,h-66,w,52,details and app.tr('Back to buddy','看看宠物') or app.tr('Personality','查看属性'),0)
end
return {
  on_start=function()
    local ok,id=app.system('device.id');if ok and #id==12 and tonumber(id,16) then traits=generate(id) end
    claimed=app.read('claimed')=='1';show()
  end,
  on_resize=show,
  on_select=function(i)
    if i==1 then claimed=true;app.write('claimed','1') elseif i==2 then details=not details else blink=not blink end
    show()
  end,
  on_back=function() if details then details=false;show() else app.exit() end end,
}
