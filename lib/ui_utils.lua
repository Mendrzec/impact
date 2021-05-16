local ui_utils = {}

function ui_utils.draw_dot(x, y, level)
  screen.level(level)
  screen.move(x, y)
  screen.line_rel(1, 0)
  screen.stroke()
end


function ui_utils.draw_rec(x, y, highlight)
  screen.level(highlight == true and 15 or 1)
  screen.move(x, y)
  screen.text("Rec")
end

function ui_utils.draw_bpm(x, y, value, highlight)
  screen.level(highlight == true and 15 or 5)
  screen.rect(x - 2, y - 6, 31, 7) -- 20, 0, 31, 7
  screen.fill()
  screen.stroke()
  screen.blend_mode(13)
  screen.level(highlight == true and 14 or 4)
  screen.move(x, y) -- 22, 6
  screen.text("BPM:" .. tostring(value)) -- params:get("bpm")
  screen.blend_mode(2)
end

local function draw_inv_value(x, y, value, highlight, disabled, margin_l, margin_r)
  local margin_l = margin_l or 1
  local margin_r = margin_r or 1
  if disabled == true then
    screen.level(highlight == true and 15 or 2)
    screen.move(x, y)
    screen.text(value)
    return
  end
  local string_value = tostring(value)
  screen.level(highlight == true and 15 or 5)
  screen.rect(x - margin_l, y - 6, 4 + margin_r + margin_l/2 + (string.len(string_value) - 1) * 4, 7)
  screen.fill()
  screen.stroke()
  screen.blend_mode(13)
  screen.level(highlight == true and 14 or 4)
  screen.move(x, y)
  screen.text(tostring(value))
  screen.blend_mode(2)
end

function ui_utils.draw_inv_value(x, y, value, highlight, disabled, margin_l, margin_r)
  draw_inv_value(x, y, value, highlight, disabled, margin_l, margin_r)
end

function ui_utils.draw_pages(x, y, current_page, current_step, last_step, follow)
  local last_step_page = math.floor((last_step - 1) / 16) + 1
  draw_inv_value(x, y, last_step_page == 1 and last_step or 16, current_page == 1, false)
  draw_inv_value(x + 9, y, last_step_page == 2 and last_step or 32, current_page == 2, last_step_page < 2)
  draw_inv_value(x + 18, y, last_step_page == 3 and last_step or 48, current_page == 3, last_step_page < 3)
  draw_inv_value(x + 27, y, last_step_page == 4 and last_step or 64, current_page == 4, last_step_page < 4)
  draw_inv_value(x + 36, y, ">", follow, not follow)
end

function ui_utils.draw_partial_steps(x, y, partial_steps)
  for index=1,4 do
    screen.level(10)
    screen.rect(x + index * 4, y - 5, 3, 6)
    screen.stroke()
    if partial_steps[index] == 1 then
      screen.level(15)
      screen.rect(x + 1 + index * 4, y - 4, 1, 4)
      screen.stroke()
    end
  end
end

function ui_utils.draw_top_bar()
end

function ui_utils.draw_track_vertical_line(x, first)
  screen.level(5)
  screen.move(x - 3, 64)
  screen.line(x - 3, 8)

  if first then
    screen.move(x - 3, 9)
  else
    screen.move(x - 6, 9)
  end
  screen.line(x - 1, 9)
  screen.stroke()
end

function ui_utils.draw_last_vertical_line(x)
  screen.level(5)
  screen.move(x + 12, 64)
  screen.line(x + 12, 8)
  screen.move(x + 9, 9)
  screen.line(x + 12, 9)
  screen.stroke()
end

function ui_utils.draw_inv_label(x, y, text, highlight, disabled)
  if disabled == true then
    screen.level(highlight == true and 15 or 5)
    screen.move(x, y - 1)
    screen.text(text)
  else
    screen.level(highlight == true and 15 or 5)
    screen.rect(x - 4, y - 7, 16, 7)
    screen.fill()
    screen.stroke()
    screen.blend_mode(13)
    screen.level(highlight == true and 14 or 4)
    screen.move(x, y - 1)
    screen.text(text)
    screen.blend_mode(2)
  end
end

return ui_utils