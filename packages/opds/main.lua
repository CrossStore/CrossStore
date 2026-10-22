return { on_start = function()
  if app.open("opds") then return end
  app.title(app.tr("OPDS Browser", "网络书库"))
  app.row(app.tr("Network permission required", "需要网络权限"), app.tr("Enable it in Store settings.", "请在商店设置中开启。"))
end }
