local ui_utils = {}

function ui_utils.draw_dot(x, y, level)
  screen.level(level)
  screen.move(x, y)
  screen.line_rel(1, 0)
  -- screen.circle(x, y, 0)
  screen.stroke()
end


function ui_utils.draw_rec(x, y, highlight)
  screen.level(highlight == true and 15 or 1)
  screen.move(x, y)
  screen.text("Rec")
end

function ui_utils.draw_top_bar()
end

function ui_utils.draw_track_vertical_line(x)
  screen.level(5)
  screen.move(x - 3, 64)
  screen.line(x - 3, 8)
  screen.stroke()
end

function ui_utils.draw_last_vertical_line(x)
  screen.level(5)
  screen.move(x + 12, 64)
  screen.line(x + 12, 8)
  screen.stroke()
end

function ui_utils.draw_inv_label(x, y, text, highlight)
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

return ui_utils