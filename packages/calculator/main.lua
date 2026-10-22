local keys = {"AC", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", ".", "⌫", "="}
local value, accumulator, operator, replace = "0", nil, nil, true
local last_operator, last_operand
local function show()
  app.clear(); app.title(app.tr("Calculator", "计算器")); app.caption(value); app.grid(4)
  for _, key in ipairs(keys) do app.row(key) end
end
local function calculate(a, b, op)
  if op == "+" then return a+b end
  if op == "−" then return a-b end
  if op == "×" then return a*b end
  if op == "÷" and b ~= 0 then return a/b end
end
local function format(number)
  if not number or number ~= number or math.abs(number) == math.huge then
    accumulator, operator, replace = nil, nil, true
    return app.tr("Error", "错误")
  end
  return string.format("%.10g", number)
end
return {
  on_start = show,
  on_select = function(index)
    local key = keys[index]; if not key then return end
    if key == "AC" then
      value, accumulator, operator, replace, last_operator, last_operand = "0", nil, nil, true, nil, nil
    elseif key == "±" then value = format(-(tonumber(value) or 0))
    elseif key == "%" then value = format((tonumber(value) or 0) / 100)
    elseif key == "⌫" then
      value = replace and "0" or string.sub(value, 1, -2)
      if value == "" or value == "-" then value = "0" end
    elseif key == "=" then
      local operand = tonumber(value) or 0
      if operator and accumulator then
        last_operator, last_operand = operator, operand
        value = format(calculate(accumulator, operand, operator))
      elseif last_operator then value = format(calculate(operand, last_operand, last_operator)) end
      accumulator, operator, replace = nil, nil, true
    elseif key == "+" or key == "−" or key == "×" or key == "÷" then
      local operand = tonumber(value) or 0
      if accumulator and operator and not replace then value = format(calculate(accumulator, operand, operator)) end
      accumulator, operator, replace = tonumber(value) or 0, key, true
      last_operator, last_operand = nil, nil
    else
      if replace then value, replace = "0", false end
      if key == "." then
        local has_dot = false
        for i=1,#value do if string.sub(value,i,i)=="." then has_dot=true end end
        if not has_dot then value=value.."." end
      elseif #value < 12 then value = value == "0" and key or value..key end
    end
    show()
  end,
}
