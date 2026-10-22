local count = 0
local function show()
  app.clear(); app.title(app.tr("Woodfish", "木鱼")); app.caption(tostring(count)); app.grid(1)
  app.row(app.tr("Tap", "敲一下")); app.row(app.tr("Reset counter", "清零"))
end
return {
  on_start = function() count = tonumber(app.read("count")) or 0; show() end,
  on_select = function(i)
    if i == 1 then count = count + 1 elseif i == 2 then count = 0 end
    if not app.write("count", tostring(count)) then app.notify(app.tr("Counter could not be saved", "计数保存失败")) end
    show()
  end,
}
