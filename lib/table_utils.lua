local table_utils = {}

function table_utils.shift(t, n)
  if n > 0 then
    for i=1,n do
      table.insert(t, 1, table.remove(t, #t))
    end
  elseif n < 0 then
    for i=1,math.abs(n) do
      table.insert(t, table.remove(t, 1))
    end
  else
    return false
  end
  return true
end

function table_utils.contains(t, element)
  for _, value in pairs(t) do
    if value == element then return true end
  end
  return false
end

function table_utils.deepcopy(orig, copies)
  copies = copies or {}
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    if copies[orig] then
      copy = copies[orig]
    else
      copy = {}
      copies[orig] = copy
      for orig_key, orig_value in next, orig, nil do
          copy[table_utils.deepcopy(orig_key, copies)] = table_utils.deepcopy(orig_value, copies)
      end
      setmetatable(copy, table_utils.deepcopy(getmetatable(orig), copies))
    end
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

function table_utils.dump(o, already_printed)
  already_printed = already_printed or {}
  if type(o) == 'table' and not already_printed[o] then
    already_printed[o] = true
    local s = tostring(o) .. '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. table_utils.dump(v, already_printed) .. ','
    end
    local meta = getmetatable(o)
    if meta then
      for k,v in pairs(meta) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s = s .. '['..k..'] = ' .. table_utils.dump(v, already_printed) .. ','
      end
    end
    return s .. '}'
  else
      return tostring(o)
  end
end

return table_utils