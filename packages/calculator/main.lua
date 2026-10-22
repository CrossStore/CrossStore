local keys = {"AC", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", ".", "⌫", "="}
local value, accumulator, operator, replace = "0", nil, nil, true
local last_operator, last_operand, history = nil, nil, ""
local function show()
  app.clear(); app.title(app.tr("Calculator", "计算器")); app.canvas()
  local w,h=app.size()
  local gap=math.max(8,math.floor(w/40))
  local top=math.max(90,math.floor(h*.23))
  app.text(8,8,w-16,32,history,0,2,6)
  app.text(8,42,w-16,top-50,value,3,2,0)
  app.box(0,top,w,2,0)
  local keyw=(w-3*gap)/4
  local keyh=(h-top-18-4*gap)/5
  for i,key in ipairs(keys) do
    local r,c=math.floor((i-1)/4),(i-1)%4
    local style=i==20 and 3 or (r==0 or c==3) and 2 or 1
    app.button(i,c*(keyw+gap),top+18+r*(keyh+gap),keyw,keyh,key,style)
  end
end
local function calculate(a,b,op)
  if op=="+" then return a+b elseif op=="−" then return a-b elseif op=="×" then return a*b
  elseif op=="÷" and b~=0 then return a/b end
end
local function format(number)
  if not number or number~=number or math.abs(number)==math.huge then
    accumulator,operator,replace=nil,nil,true
    return app.tr("Error", "错误")
  end
  return string.format("%.10g",number)
end
return {
  on_resize=show,
  on_start=show,
  on_select=function(index)
    local key=keys[index]; if not key then return end
    if key=="AC" then
      value,accumulator,operator,replace,last_operator,last_operand,history="0",nil,nil,true,nil,nil,""
    elseif key=="±" then value=format(-(tonumber(value) or 0))
    elseif key=="%" then value=format((tonumber(value) or 0)/100)
    elseif key=="⌫" then
      value=replace and "0" or string.sub(value,1,-2)
      if value=="" or value=="-" then value="0" end
    elseif key=="=" then
      local operand=tonumber(value) or 0
      if operator and accumulator then
        history=format(accumulator).." "..operator.." "..value.." ="
        last_operator,last_operand=operator,operand
        value=format(calculate(accumulator,operand,operator))
      elseif last_operator then
        history=value.." "..last_operator.." "..format(last_operand).." ="
        value=format(calculate(operand,last_operand,last_operator))
      end
      accumulator,operator,replace=nil,nil,true
    elseif key=="+" or key=="−" or key=="×" or key=="÷" then
      local operand=tonumber(value) or 0
      if accumulator and operator and not replace then value=format(calculate(accumulator,operand,operator)) end
      accumulator,operator,replace=tonumber(value) or 0,key,true
      history=value.." "..key
      last_operator,last_operand=nil,nil
    else
      if replace then value,replace="0",false end
      if key=="." then
        local dot=false
        for i=1,#value do if string.sub(value,i,i)=="." then dot=true end end
        if not dot then value=value.."." end
      elseif #value<12 then value=value=="0" and key or value..key end
    end
    show()
  end,
}
