-- The package owns bookshelf/navigation/options. Native services keep the
-- existing authenticated protocol, transactional cache and reader integration.
local tr=app.tr
local view,job,state='home','sync','idle'
local ready,images,range=false,true,false
local count,page,selected,revision=0,0,1,-1
local book,author,publisher='', '', ''
local words,rating,introSize=0,0,0
local downloaded,cacheState,cacheCount,cachePage,savedImages=false,'missing',0,0,-1
local progressKey,notice='', ''
local first,last,chapterCount,chapterPage,choosing=0,0,0,0,'first'
local introOffset,introNext,introStack=0,0,{}
local disclaimerPage=1
local disclaimerOffset,disclaimerNext=1,1
local termsEn={
  'This application is an unofficial client and is not affiliated with, authorized by, endorsed by, or otherwise connected to WeRead or its operator.',
  'This application is intended solely for personal study, technical research, and discussion. Do not use it for commercial or other improper purposes.',
  'Follow applicable laws and platform rules, respect the intellectual property rights of authors, publishers, and other right holders, and do not copy, distribute, circumvent protections for, or misuse protected content.',
  'You assume all account, data, and other risks arising from use of this application. If you disagree, choose Cancel. Choosing Confirm means that you have read, understood, and accepted this disclaimer.'}
local termsZh={
  '本应用为非官方客户端，与微信读书及其运营方不存在隶属、合作、授权或认可关系。',
  '本应用仅供个人学习、技术研究与交流使用，请勿用于商业或其他不当用途。',
  '使用过程中，请遵守相关法律法规及平台规则，尊重作者、出版社及其他权利人的知识产权，不得以任何形式复制、传播、破解或滥用受保护的内容。',
  '因使用本应用产生的账号、数据及其他风险由使用者自行承担。不同意请选择取消；选择确定即表示您已阅读、理解并同意本免责声明。'}
local function two(id1,id2,y,w,height,a,b)
  local half=(w-12)/2
  app.button(id1,0,y,half,height,a,0);app.button(id2,half+12,y,half,height,b,0)
end
local function shelfSize(w,h)
  local columns=math.max(1,math.min(4,math.floor(w/150)))
  local rows=math.max(1,math.min(3,math.floor((h-150)/158)))
  return columns,rows,columns*rows
end
local function cacheRows(h) return math.max(1,math.min(7,math.floor((h-208)/64))) end
local function clip(text,bytes)
  local n=math.min(#text,bytes)
  while n>0 and n<#text and (text:byte(n+1)&0xc0)==0x80 do n=n-1 end
  return text:sub(1,n)
end
local function fitted(text,w,h,font)
  local lo,hi=1,math.min(255,#text)
  local best=''
  while lo<=hi do
    local middle=(lo+hi)//2;local part=clip(text,middle)
    local _,height=app.measure(part,w,font)
    if height<=h then best=part;lo=middle+1 else hi=middle-1 end
  end
  return best
end
local function show()
  app.clear();app.canvas();app.title(tr('WeRead','微信读书'))
  local w,h=app.size()
  if not ready then
    app.text(8,56,w-16,200,tr('Allow network and reading data access in Store settings to open your bookshelf.','请在商店设置中允许联网和读取阅读数据，才能打开书架。'),1,0,0);return
  end
  if view=='disclaimer' then
    app.text(0,8,w,44,tr('Disclaimer','免责声明')..'  '..disclaimerPage..'/4',2,1,0)
    local paragraph=tr(termsEn[disclaimerPage],termsZh[disclaimerPage])
    local text=fitted(paragraph:sub(disclaimerOffset),w-16,h-152,1)
    disclaimerNext=disclaimerOffset+#text
    app.text(8,68,w-16,h-152,text,1,0,0)
    two(80,81,h-60,w,52,tr('Cancel','取消'),disclaimerPage==4 and disclaimerNext>#paragraph and tr('Confirm','确定') or tr('Continue','继续'))
    return
  end
  if view=='logout' then
    app.text(12,60,w-24,180,tr('Sign out of WeRead on this device? Downloaded books remain on the card.','退出这台设备上的微信读书账号？已下载的书籍会保留在卡中。'),1,0,0)
    two(7,82,h-60,w,52,tr('Cancel','取消'),tr('Sign out','退出账号'));return
  end
  if view=='busy' then
    if state=='qr' then
      local parts={}
      for i=0,2 do local ok,text=app.system('weread.qr','',i);if ok then parts[#parts+1]=text end end
      local url=table.concat(parts);local size=math.min(w-24,h-148,300)
      if #url>0 and #url<=384 then app.qr((w-size)/2,8,size,url) end
      app.text(0,size+24,w,44,tr('Scan with WeRead to sign in','用微信读书扫码登录'),1,1,0)
    else
      local _,title,done,total,stage=app.system('weread.progress')
      local stageNames={tr('Downloading chapters','下载章节'),tr('Preparing','准备中'),tr('Downloading images','下载图片'),tr('Packaging book','整理书籍')}
      local label=state=='connecting' and tr('Connecting…','连接中…') or stageNames[(stage or 0)+1]
      app.text(0,30,w,52,label,2,1,0)
      app.text(12,100,w-24,100,title or '',1,1,5)
      local y=math.min(h-145,240);local fraction=(total and total>0) and math.min(1,done/total) or 0
      app.box(12,y,w-24,12,10,6)
      if fraction>0 then app.box(12,y,(w-24)*fraction,12,0,6) end
      app.text(0,y+22,w,42,tostring(done or 0)..' / '..tostring(total or 0),1,1,0)
    end
    app.button(900,0,h-58,w,52,tr('Cancel','取消'),0);return
  end
  if view=='chapters' then
    local rows=math.max(1,math.min(7,math.floor((h-168)/58)))
    app.text(0,0,w,40,choosing=='first' and tr('Choose first chapter','选择起始章节') or tr('Choose last chapter','选择结束章节'),2,0,0)
    for i=1,rows do
      local index=chapterPage*rows+i-1
      local ok,title=app.system('weread.chapter','',index)
      if not ok then break end
      app.button(200+i,0,50+(i-1)*58,w,50,(index+1)..'. '..clip(title,60),0)
    end
    two(30,31,h-112,w,44,tr('Previous','上一页'),tr('Next','下一页'))
    two(32,33,h-56,w,48,tr('Cancel','取消'),tr('Download','下载')..' '..(first+1)..'–'..(last+1));return
  end
  if view=='intro' then
    local ok,text,bytes=app.system('weread.intro','',introOffset)
    text=ok and fitted(text,w-8,h-190,1) or tr('No introduction cached. Fetch details first.','暂无缓存的简介，请先获取详情。')
    introNext=ok and introOffset+#text or introOffset
    app.text(0,2,w,46,tr('Introduction','简介'),2,0,0)
    app.text(4,60,w-8,h-190,text,1,0,0)
    two(40,41,h-112,w,44,tr('Previous','上一页'),tr('Next','下一页'))
    app.button(42,0,h-56,w,48,tr('Back','返回'),0);return
  end
  if view=='options' then
    app.text(0,8,w,44,tr('Download options','下载选项'),2,0,0)
    app.text(0,64,w,80,clip(book,96),1,0,5)
    app.button(14,0,152,w,52,images and tr('Images: included','图片：保留') or tr('Images: text only','图片：纯文字'),0)
    app.button(15,0,216,w,52,range and tr('Chapters: choose a range','章节：选择范围') or tr('Chapters: whole book','章节：全书'),0)
    if savedImages>=0 and images~=(savedImages==0) then
      app.text(0,280,w,math.max(32,h-350),tr('The new image option takes effect on the next download.','图片选项会在下次下载时生效。'),0,0,5)
    end
    app.button(42,0,h-56,w,48,tr('Back to book','返回图书'),0);return
  end
  if view=='cache' then
    local rows=cacheRows(h)
    cachePage=math.min(cachePage,math.max(0,math.ceil(cacheCount/rows)-1))
    app.text(0,0,w,42,tr('Local chapters','本地章节'),2,0,0)
    local summary=notice~='' and notice or downloaded and tr('Book ready to read','书籍可离线阅读') or tr('No readable book downloaded','尚无可阅读的离线书籍')
    app.text(0,48,w,38,summary,0,0,5)
    if cacheCount==0 then
      local empty=cacheState=='invalid' and tr('The chapter index cannot be read. Download again to rebuild it; existing books are kept.','章节目录无法读取。可重新下载重建目录，现有书籍会保留。') or tr('No chapter index is cached yet. Download the book or a chapter range first.','尚未缓存章节目录，请先下载全书或选择章节范围。')
      app.text(8,110,w-16,h-240,empty,1,0,5)
    else
      for i=1,rows do
        local index=cachePage*rows+i-1
        if index>=cacheCount then break end
        local ok,title,cached,paid=app.system('weread.cached_chapter','',index)
        local y=100+(i-1)*64
        local heading=ok and (index+1)..'. '..clip(title,90) or tr('Chapter unavailable','章节无法读取')
        app.text(0,y,w,32,heading,0,0,0)
        local status=not ok and tr('Read error; retry or download again','读取失败，请重试或重新下载') or cached==1 and tr('Chapter file saved','章节文件已缓存') or tr('Not cached','尚未缓存')
        if ok and paid==1 then status=status..' · '..tr('Paid chapter','付费章节') end
        app.text(0,y+34,w,24,status,0,0,5)
      end
    end
    two(50,51,h-104,w,44,tr('Previous','上一页'),tr('Next','下一页'))
    two(42,10,h-52,w,44,tr('Back to book','返回图书'),tr('Read book','阅读书籍'));return
  end
  if view=='detail' then
    app.box(0,8,6,100,5)
    app.text(20,4,w-24,80,book,2,0,0)
    app.text(20,88,w-24,42,author,1,0,5)
    local meta=notice~='' and notice or (downloaded and tr('Saved for offline reading','已下载，可离线阅读') or tr('Not downloaded','尚未下载'))
    if notice=='' and publisher~='' then meta=meta..'\n'..publisher end
    if words>0 then meta=meta..'  '..words..tr(' words','字') end
    app.text(8,138,w-16,math.max(36,h-356),meta,0,0,5)
    two(10,11,h-204,w,44,tr('Read cached','阅读缓存'),tr('Download','下载'))
    two(12,13,h-152,w,44,tr('Fetch details','获取详情'),tr('Introduction','简介'))
    two(16,17,h-100,w,44,tr('Download options','下载选项'),tr('Local chapters','本地章节'))
    app.button(7,0,h-48,w,44,tr('Bookshelf','返回书架'),0);return
  end
  local columns,rows,perPage=shelfSize(w,h)
  page=math.min(page,math.max(0,math.ceil(count/perPage)-1))
  two(1,2,0,w,44,tr('Sync bookshelf','同步书架'),tr('Account','账号'))
  if count==0 then
    app.text(16,96,w-32,h-196,notice~='' and notice or tr('Your books, ready to read. Sync your bookshelf to sign in and load titles.','让书架随身而行。点“同步书架”，登录并载入你的书籍。'),2,1,5)
  else
    local cw=(w-16*(columns-1))/columns;local ch=(h-136-12*(rows-1))/rows
    for i=1,perPage do
      local index=page*perPage+i
      local ok,title,downloaded,_,_,by=app.system('weread.book','',index)
      if not ok then break end
      local x=((i-1)%columns)*(cw+16);local y=64+((i-1)//columns)*(ch+12)
      app.box(x,y,cw,ch,15,5,1);app.box(x+1,y+1,6,ch-2,10,0)
      app.text(x+16,y+16,cw-26,ch-72,title,1,0,0)
      app.text(x+16,y+ch-50,cw-26,34,downloaded==1 and tr('Saved','已缓存') or by,0,0,5)
      app.hit(100+i,x,y,cw,ch)
    end
  end
  two(3,4,h-52,w,48,tr('Previous','上一页'),tr('Next','下一页'))
end
local function detail(restoreOptions)
  local ok,title,_,_,_,by=app.system('weread.book','',selected)
  if ok then book,author=title,by end
  local have,_,wc,rate,intro,pub=app.system('weread.detail','',selected)
  words,rating,introSize,publisher=have and wc or 0,have and rate or 0,have and intro or 0,have and pub or ''
  local cacheOk,status,haveBook,n,imagePolicy=app.system('weread.cache','',selected)
  downloaded=cacheOk and haveBook==1;cacheState=cacheOk and status or 'invalid'
  cacheCount=cacheOk and n or 0;savedImages=cacheOk and imagePolicy or -1
  if restoreOptions then images=savedImages~=1;range=false end
  view='detail';show()
end
local function begin(which,command,argument)
  if app.system(command,argument or '',selected) then
    job=which;state='connecting';view='busy';notice='';progressKey=''
    app.system('power.keep_awake','on');show()
  else notice=tr('Could not start; retry after the current task','无法开始，请稍后重试');show() end
end
local function refresh()
  local ok,nextState,books,rev,errorCode=app.system('weread.status')
  if not ok then return end
  local changed=not ready or rev~=revision
  ready=true;state=nextState;count=books;revision=rev
  if view=='busy' and state~='qr' then
    local _,_,done,total,stage=app.system('weread.progress')
    local key=tostring(stage)..':'..tostring(total>0 and (done*10)//total or done)
    changed=changed or key~=progressKey;progressKey=key
  end
  if not changed then return end
  if state=='disclaimer' then view='disclaimer'
  elseif state=='range' then
    local _,_,n=app.system('weread.chapter_count');chapterCount=n;first=0;last=math.max(0,n-1);chapterPage=0;choosing='first';view='chapters'
  elseif state=='done' and view=='busy' then
    app.system('power.keep_awake','off')
    if job=='sync' then view='home' else detail(job=='download');return end
  elseif state=='error' then
    app.system('power.keep_awake','off')
    local messages={ [2]=tr('Network error. Retry the connection.','网络异常，请重新连接。'),[3]=tr('Session expired. Sync to sign in again.','登录已过期，请同步书架重新登录。'),[6]=tr('Storage error. Check the card.','存储错误，请检查卡。'),[10]=tr('Not enough memory. Close and retry.','内存不足，请退出后重试。'),[11]=tr('This title requires a whole-book download.','这本书需要整本下载。') }
    notice=messages[errorCode] or tr('Operation failed. Please retry.','操作失败，请重试。')
    view=job=='sync' and 'home' or 'detail'
  elseif state=='idle' and view=='busy' then view='home';app.system('power.keep_awake','off') end
  show()
end
return {
  on_start=function() app.system('weread.start');show() end,
  on_tick=refresh,on_service=refresh,on_network=refresh,on_resize=show,
  on_select=function(id)
    notice=''
    local w,h=app.size();local _,_,perPage=shelfSize(w,h)
    if id==1 then begin('sync','weread.sync')
    elseif id==2 then view='logout';show()
    elseif id==3 then page=math.max(0,page-1);show()
    elseif id==4 then if (page+1)*perPage<count then page=page+1 end;show()
    elseif id>=101 and id<=112 then selected=page*perPage+id-100;detail(true)
    elseif id==7 then view='home';show()
    elseif id==10 then if not app.system('weread.open','',selected) then notice=tr('Download this book first','请先下载这本书');show() end
    elseif id==11 then begin('download','weread.download',(images and 'images' or 'no_images')..(range and ',range' or ''))
    elseif id==12 then begin('detail','weread.fetch_detail')
    elseif id==13 then introOffset=0;introStack={};view='intro';show()
    elseif id==14 then images=not images;show()
    elseif id==15 then range=not range;show()
    elseif id==16 then view='options';show()
    elseif id==17 then cachePage=0;view='cache';show()
    elseif id==50 then cachePage=math.max(0,cachePage-1);show()
    elseif id==51 then if (cachePage+1)*cacheRows(h)<cacheCount then cachePage=cachePage+1 end;show()
    elseif id==30 then chapterPage=math.max(0,chapterPage-1);show()
    elseif id==31 then local rows=math.max(1,math.min(7,math.floor((h-168)/58)));if (chapterPage+1)*rows<chapterCount then chapterPage=chapterPage+1 end;show()
    elseif id>=201 and id<=207 then
      local rows=math.max(1,math.min(7,math.floor((h-168)/58)));local n=chapterPage*rows+id-201
      if choosing=='first' then first=n;last=math.max(last,n);choosing='last'
      else last=math.max(first,n);choosing='first' end
      show()
    elseif id==33 then
      if app.system('weread.range',first..':'..last) then view='busy';state='busy';show() end
    elseif id==32 or id==900 then app.system('weread.cancel');app.system('power.keep_awake','off');view='home';show()
    elseif id==40 then if #introStack>0 then introOffset=table.remove(introStack) end;show()
    elseif id==41 then if introNext>introOffset and introNext<introSize then if #introStack>=64 then table.remove(introStack,1) end;introStack[#introStack+1]=introOffset;introOffset=introNext end;show()
    elseif id==42 then detail()
    elseif id==80 then app.exit()
    elseif id==81 then
      local paragraph=tr(termsEn[disclaimerPage],termsZh[disclaimerPage])
      if disclaimerNext<=#paragraph then disclaimerOffset=disclaimerNext
      elseif disclaimerPage<4 then disclaimerPage=disclaimerPage+1;disclaimerOffset=1
      elseif app.system('weread.accept') then view='home' end
      show()
    elseif id==82 then app.system('weread.logout');view='home';show() end
  end,
  on_back=function()
    if view=='busy' or view=='chapters' then app.system('weread.cancel');app.system('power.keep_awake','off') end
    if view=='home' or view=='disclaimer' then app.exit()
    elseif view=='cache' or view=='options' or view=='intro' then detail()
    else view='home';show() end
  end,
}
