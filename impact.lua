-- impact
-- v1.1.0 @Mendrzec
--
-- 8 track drum machine

local ui = require "ui"
local music = require "musicutil"

engine.name = "Impact"

local impact_params = include("lib/impact_params")
local ui_utils = include("lib/ui_utils")
local table_utils = include("lib/table_utils")

--local grid = include("midigrid/lib/mg_128")
local g = grid.connect()

local MIDI_Clock = require "beatclock"
clk = MIDI_Clock.new() -- global for impact_params how to fix that?
local clk_midi = midi.connect()

-- TODO clean up globals
-- globals
local flash_slow = false
local flash_fast = false
local flash_function = function ()
  while true do
    flash_fast = not flash_fast
    if flash_fast then
      flash_slow = not flash_slow
    end
    grid_dirty = true
    clock.sleep(0.125)
  end
end
local flash_timer = clock.run(flash_function)

function cleanup()
  clock.cancel(flash_timer)
end

local utility_mode = {
  NONE = 1,
  ERASE = 2,
  COPY = 3,
  SAVE = 4,
  current = 1,

  is_none = function (self)
    return self.current == self.NONE
  end,
  set_none = function (self)
    self.current = self.NONE
  end,
  is_erase = function (self)
    return self.current == self.ERASE
  end,
  set_erase = function (self)
    self.current = self.ERASE
  end,
  is_copy = function (self)
    return self.current == self.COPY
  end,
  set_copy = function (self)
    self.current = self.COPY
  end
}
local clipboard = {
  track = nil,
  pattern = nil,

  store_track = function (self, track)
    self.track = track
    self.pattern = nil
  end,
  has_track = function (self, track) -- track is optional
    if track then
      return self.track == track
    else
      return self.track ~= nil
    end
  end,
  store_pattern = function (self, pattern)
    self.pattern = pattern
    self.track = nil
  end,
  has_pattern = function (self, pattern) -- pattern is optional
    if pattern then
      return self.pattern == pattern
    else
      return self.pattern ~= nil
    end
  end,
  clear = function (self)
    self.pattern = nil
    self.track = nil
  end,
  empty = function (self)
    return self.pattern == nil and self.track == nil
  end
}

local playback_mode = {
  STOPPED = 4,
  PLAYING = 1,
  PAUSED = 3
}
local recording_mode = {
  NOT_RECORDING = 1,
  RECORDING = 2,
  RECORDING_UNQUANTIZED = 3
}

local color = {
  DISABLED = 0,
  DEFAULT = 1,

  PRESSED = 15,
}

-- merge those vars as done in see. utility_mode
local current_playback_mode = playback_mode.STOPPED
local current_recording_mode = recording_mode.NOT_RECORDING

local tracks_buttons_grid_map = {}
local tracks_data = {}
local currently_focused_track = nil

local shift_pressed = false
local mode = {
    PATTERN_SELECTION = 1,
    STEP_EDIT = 2
}
-- merge those vars as done in see. utility_mode
local current_mode = mode.STEP_EDIT
local pattern_selector = {
  selected_to_play_next_color = 3,
  currently_playing_color = 10,

  current_pattern = 1, -- currently playing end edited pattern
  selected_pattern = 1, -- to be played next
  total_patterns = 16,
  longest_track_in_pattern = {},

  grid_rows = 2,
  grid_row_length = 8,
  grid_start_x = 1,
  grid_start_y = 4,
  pattern_to_grid_xy_map = {},
  grid_xy_to_pattern_map = {},

  init = function (self)
    for i=1,self.total_patterns do
      self.longest_track_in_pattern[i] = 1
    end

    -- init grid_xy_to_pattern_map
    local ptrn_index2 = 1
    local grid_y_end = (self.grid_start_y + self.grid_rows - 1)
    local grid_x_end = (self.grid_start_x + self.grid_row_length - 1)
    for y=self.grid_start_y,grid_y_end do
      for x=self.grid_start_x,grid_x_end do
        if self.grid_xy_to_pattern_map[x] == nil then
          self.grid_xy_to_pattern_map[x] = {}
        end
        self.grid_xy_to_pattern_map[x][y] = ptrn_index2
        ptrn_index2 = ptrn_index2 + 1
      end
    end

    -- init pattern_to_grid_xy_map
    local x = 0
    local y = 0
    for ptrn_index=1,self.total_patterns do
      self.pattern_to_grid_xy_map[ptrn_index] = {x + self.grid_start_x, y + self.grid_start_y}
      x = x + 1
      if ptrn_index % self.grid_row_length == 0 then
        x = 0
        y = y + 1
      end
    end
  end,
  evaluate_longest_track = function (self)
    local highest_last_step = 1
    for _, track in pairs(tracks_data) do
      local track_last_step = track.patterns[self.current_pattern].last_step
      if track_last_step > highest_last_step then
        self.longest_track_in_pattern[self.current_pattern] = track.index
      end
    end
  end,
  is_longest_track_in_current_pattern = function (self, track_index)
    return self.longest_track_in_pattern[self.current_pattern] == track_index
  end,
  index_to_grid_xy = function (self, index)
    local grid_xy = self.pattern_to_grid_xy_map[index]
    return grid_xy[1], grid_xy[2]
  end,
  grid_xy_valid = function (self, x, y)
    return self.grid_start_x <= x and x < (self.grid_start_x + self.grid_row_length)
      and self.grid_start_y <= y and y < (self.grid_start_y + self.grid_rows)
  end,
  grid_xy_to_index = function (self, x, y)
    return self.grid_xy_to_pattern_map[x][y]
  end
}

local pages_buttons_grid_map = {}
step_editor = {
  edited_params_color = 6,
  active_color = 9,
  currently_playing_color = 13,

  total_steps = 64,
  steps_per_page = 16,
  page_count = 4,
  current_page = 1,
  current_track = 1,
  currently_pressed_step = nil,
  pattern_follow = false,
  pattern_follow_tick = function (self)
    if self.pattern_follow then
      local current_step = tracks_data[self.current_track].patterns[pattern_selector.current_pattern].current_step
      -- replace with ifs on perfromance problems
      self.current_page = math.floor((current_step - 1)/ step_editor.steps_per_page) + 1
    end
  end,

  grid_rows = 2,
  grid_row_length = 8,
  grid_start_x = 1,
  grid_start_y = 4,
  step_to_grid_xy_map = {},
  grid_xy_to_step_map = {},
  pages_grid_start_x = 5,
  pages_grid_start_y = 2,
  pages_buttons = {}
}

function step_editor:init()
  -- init grid_xy_to_step_map
  local step_index2 = 1
  local grid_y_end = (self.grid_start_y + self.grid_rows - 1)
  local grid_x_end = (self.grid_start_x + self.grid_row_length - 1)
  for y=self.grid_start_y,grid_y_end do
    for x=self.grid_start_x,grid_x_end do
      if self.grid_xy_to_step_map[x] == nil then
        self.grid_xy_to_step_map[x] = {}
      end
      self.grid_xy_to_step_map[x][y] = step_index2
      step_index2 = step_index2 + 1
    end
  end

  -- init step_to_grid_xy_map
  local x = 0
  local y = 0
  for step_index=1,self.total_steps do
    self.step_to_grid_xy_map[step_index] = {x + self.grid_start_x, y + self.grid_start_y}
    x = x + 1
    if step_index % self.grid_row_length == 0 then
      x = 0
      y = y + 1
    end
    if step_index % self.steps_per_page == 0 then
      y = 0
    end
  end

  for page_button_index=1,self.page_count do
    self.pages_buttons[page_button_index] = {
      grid_x = self.pages_grid_start_x + page_button_index - 1,
      grid_y = self.pages_grid_start_y,
      pressed = false,
      press_timer = nil,
      long_press = function (self)
        clock.sleep(0.5)
        if page_button_index == 1 then
          step_editor.pattern_follow = true
        end
        self.press_timer = nil
      end,
      on_press = function (self)
        self.pressed = true
        self.press_timer = clock.run(self.long_press, self)
      end,
      on_release = function (self)
        self.pressed = false

        if self.press_timer then
          clock.cancel(self.press_timer)
          step_editor.current_page = page_button_index
          step_editor.pattern_follow = false
        end
      end,
      get_grid_color = function (self)
        -- pressed or being viewed page
        if self.pressed or step_editor.current_page == page_button_index then
          return step_editor.pattern_follow and step_editor.currently_playing_color or color.PRESSED
        end
        -- currently playing or active page - active means that it is non empty
        local current_pattern = tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern]
        if current_playback_mode ~= playback_mode.STOPPED
            and (math.floor((current_pattern.current_step - 1)/ step_editor.steps_per_page) + 1) == page_button_index then
          return step_editor.currently_playing_color
        elseif math.floor((current_pattern.last_step - 1)/ step_editor.steps_per_page) + 1 >= page_button_index then
          return step_editor.edited_params_color
        end
        return color.DEFAULT
      end
    }
  end

end

function step_editor:get_current_view_range()
  return 1 + (self.current_page - 1) * self.steps_per_page, self.current_page * self.steps_per_page
end

function step_editor:is_index_in_current_view_range(index)
  local low_bound, high_bound = self:get_current_view_range()
  return low_bound <= index and index <= high_bound
end

function step_editor:index_to_grid_xy(index)
  local grid_xy = self.step_to_grid_xy_map[index]
  return grid_xy[1], grid_xy[2]
end

function step_editor:grid_xy_valid(x, y)
  return self.grid_start_x <= x and x < (self.grid_start_x + self.grid_row_length)
    and self.grid_start_y <= y and y < (self.grid_start_y + self.grid_rows)
end

function step_editor:grid_xy_to_index(x, y)
  return self.grid_xy_to_step_map[x][y] + (self.current_page - 1) * self.steps_per_page
end

TrackData = {
  partials_per_step = 4, -- used for higher resolution
  index = nil,
  name = nil,
  grid_x = nil,
  grid_y = nil,
  screen_x = nil,
  screen_y = nil,
  trigger_callback = nil,
  max_params_count = 3,
  track_params = nil,
  patterns = nil,
  trigger_button = nil,
  focused = false,
  focus_button = nil,
  muted = false,
}

function TrackData:trigger()
  if not self.muted then
    self.trigger_callback(self)
  end
end

function TrackData:prepare_step_params()
  local pattern = self.patterns[pattern_selector.current_pattern]
  local step_params = pattern.sequence[pattern.current_step].step_params

  if pattern.reset_to_track_params then
    for key,param in ipairs(self.track_params) do
      param:reset()
    end
    pattern.reset_to_track_params = false
  end

  if next(step_params) ~= nil then
    for param_index=1,#self.track_params do
      local param = step_params[param_index]
      if param ~= nil then
        self.track_params[param_index].set(param.value)
      end
    end
    pattern.reset_to_track_params = true
  end

end

function TrackData:new(index, name, gx, gy, sx, sy, track_params, callback)
  local object = {}
  setmetatable(object, self)
  self.__index = self

  object.index = index;
  object.name = name;
  object.grid_x = gx
  object.grid_y = gy
  object.screen_x = sx
  object.screen_y = sy
  object.trigger_callback = callback
  object.track_params = {}

  for key,value in ipairs(track_params) do
    object.track_params[key] = {
      param_id = value.param_id,
      draw_note = value.draw_note,
      dial_x = object.screen_x,
      dial_y = object.screen_y - 6 - (self.max_params_count - key + 1) * 16,
      dial = nil,
      range = params:get_range(value.param_id),
      track_value = params:get(value.param_id),

      set = function(v) params:set(value.param_id, v) end,
      reset = function(self) self.set(self.track_value, false) end,
      get = function() return params:get(value.param_id) end,
      track_param_delta = function(self, d)
        self.track_value = util.clamp(self.track_value + d, self.range[1], self.range[2])
        self.set(self.track_value)
      end,
      dial_redraw = function(self)
        if self.dial == nil then
          self.dial = ui.Dial.new(self.dial_x, self.dial_y, 8, self.track_value, self.range[1], self.range[2], 1, self.range[1],
              {}, nil, self.draw_note and music.note_num_to_name(self.track_value) or nil)
        end

        if current_mode == mode.STEP_EDIT and step_editor.currently_pressed_step and step_editor.current_track == object.index then
          self.dial.active = true
          local step_params = object.patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step].step_params
          local param = step_params[key]
          if param ~=nil then
            self.dial.title = self.draw_note and music.note_num_to_name(param.value, true) or nil
            self.dial:set_value(param.value)
            ui_utils.draw_dot(self.dial_x -2, self.dial_y, 15)
          else
            self.dial.title = self.draw_note and music.note_num_to_name(self.track_value, true) or nil
            self.dial:set_value(self.track_value)
          end
          self.dial:redraw()
          return
        end

        self.dial.active = object.focused
        self.dial.title = self.draw_note and music.note_num_to_name(self.track_value, true) or nil
        self.dial:set_value(self.track_value)
        self.dial:redraw()
      end
    }
    -- TODO fix this hack
    -- init engine values hack
    object.track_params[key]:track_param_delta(-1)
    object.track_params[key]:track_param_delta(1)
  end

  object.trigger_button = {
    grid_x = object.grid_x,
    grid_y = object.grid_y,
    pressed = false,

    on_press = function (self)
      self.pressed = true
      object:trigger()
      if current_recording_mode == recording_mode.RECORDING and current_playback_mode == playback_mode.PLAYING then
        local pattern = object.patterns[pattern_selector.current_pattern]
        pattern.sequence[pattern.current_step]:set()
      end
      if current_mode == mode.STEP_EDIT then
        step_editor.current_track = object.index
      end
    end,
    on_release = function (self)
      self.pressed = false
    end,
    get_grid_color = function (self)
      if object.muted then
        return color.DISABLED
      end
      if current_mode == mode.STEP_EDIT and step_editor.current_track == object.index then
        return not self.pressed and color.PRESSED or color.DEFAULT
      else
        return self.pressed and color.PRESSED or color.DEFAULT
      end
    end
  }

  object.focus_button = {
    grid_x = object.grid_x,
    grid_y = object.grid_y - 1,
    pressed = false,
    timer = nil,

    run_timer = function (self)
      self.timer = clock.run(function (self)
        clock.sleep(1.5)
        self.timer = nil
      end, self)
    end,

    on_press = function (self)
      self.pressed = true
      if shift_pressed then
        object.muted = not object.muted
        return
      end
      if utility_mode:is_erase() then
        utility_mode:set_none()
        local current_pattern = pattern_selector.current_pattern
        object.patterns[current_pattern] = Pattern:new(current_pattern)
        self:run_timer()
        return
      end

      if utility_mode:is_copy() then
        if clipboard:empty() then
          clipboard:store_track(object.patterns[pattern_selector.current_pattern])
        elseif clipboard:has_track() then
          -- if clipboard track is different than current then copy
          if not clipboard:has_track(object.patterns[pattern_selector.current_pattern]) then
            object.patterns[pattern_selector.current_pattern] = table_utils.deepcopy(clipboard.track)
            object.patterns[pattern_selector.current_pattern].index = pattern_selector.current_pattern
            object.patterns[pattern_selector.current_pattern]:reset_step_params()

          end

          clipboard:clear()
          utility_mode:set_none()
          self:run_timer()
        end
        return
      end

      object.focused = true
      currently_focused_track = object.index
      if current_mode == mode.STEP_EDIT then
        step_editor.current_track = object.index
      end
    end,
    on_release = function (self)
      self.pressed = false
      object.focused = false
      if currently_focused_track == object.index then
        currently_focused_track = nil
      end
    end,
    get_grid_color = function(self)
      if self.pressed then
        return color.PRESSED
      elseif self.timer then
        return flash_fast and color.PRESSED or color.DEFAULT
      elseif clipboard:has_track(object.patterns[pattern_selector.current_pattern]) then
        return flash_fast and color.PRESSED or color.DEFAULT
      elseif utility_mode:is_erase() then
        return flash_slow and color.PRESSED or color.DEFAULT
      elseif clipboard:has_track() then
        return flash_slow and color.PRESSED or color.DEFAULT
      elseif utility_mode:is_copy() and clipboard:empty() then
        return flash_slow and color.PRESSED or color.DEFAULT
      else
        return color.DEFAULT
      end
    end
  }

  Step = {
    pattern = nil,
    index = nil,
    partial_steps = nil,
    current_fill = 1,
    current_offset = 0,
    active = false,
    press_timer = nil,
    pressed = false,
    edited_while_pressed = false,
    edited_params = false,
    edited_fill_or_offset = false,
    step_params = nil,

    new = function (self, pattern, index)
      local o = {}
      setmetatable(o, self)
      self.__index = self

      o.pattern = pattern
      o.index = index
      o.step_params = {}
      o.partial_steps = {0,0,0,0, 0,0,0,0} -- 4 and 4 more to recover from offset
      return o
    end,

    param_delta = function (self, param_index, delta)
      if self.step_params[param_index] == nil then
        local param = object.track_params[param_index]
        if param ~= nil then
          local param_range = param.range
          self.step_params[param_index] = {
            range = param_range,
            value = util.clamp(param.track_value + delta, param_range[1], param_range[2])
          }
        end
      else
        local step_params = self.step_params[param_index]
        local param_range = step_params.range
        step_params.value = util.clamp(step_params.value + delta, param_range[1], param_range[2])
      end
    end,

    set_fill = function (self, fill)
      if fill == 1 then
        self.partial_steps = {1,0,0,0, 0,0,0,0}
      elseif fill == 2 then
        self.partial_steps = {1,0,1,0, 0,0,0,0}
      elseif fill == 4 then
        self.partial_steps = {1,1,1,1, 0,0,0,0}
      else
        print("Unsupported fill value: " .. tostring(fill))
        return false
      end
      self.current_fill = fill
      table_utils.shift(self.partial_steps, self.current_offset)
      return true
    end,
    edit_fill = function (self, fill)
      if self.current_fill ~= fill then
        if self:set_fill(fill) then
          self.edited_fill_or_offset = true
          self.edited_while_pressed = true
        end
      end
    end,
    set_offset = function (self, offset)
      if table_utils.shift(self.partial_steps, offset - self.current_offset) then
        self.current_offset = offset
      end
    end,
    edit_offset = function (self, offset)
      self.edited_fill_or_offset = self:set_offset(offset)
      self.edited_while_pressed = self.edited_fill_or_offset
    end,

    set = function (self)
      self.partial_steps = {1,0,0,0, 0,0,0,0}
      self.current_offset = 0
      self.current_fill = 1
      self.edited_while_pressed = false
      self.edited_fill_or_offset = false
      self.step_params = {}
      self.active = true
    end,
    reset = function (self)
      self.partial_steps = {0,0,0,0, 0,0,0,0}
      self.current_offset = 0
      self.current_fill = 1
      self.edited_while_pressed = false
      self.edited_fill_or_offset = false
      self.step_params = {}
      self.active = false
    end,
    toggle = function(self)
      if not self.active then
        self:set()
      else
        self:reset()
      end
    end,

    long_press = function (self)
      clock.sleep(0.5)
      -- do nothing for now
      self.press_timer = nil
    end,
    short_press = function (self)
      self:toggle()
    end,

    on_press = function (self)
      self.pressed = true
      if last_step_pressed then
        self.pattern.last_step = self.index
        self.pattern.end_step = self.index

        pattern_selector:evaluate_longest_track()
        return
      end

      step_editor.currently_pressed_step = self.index
      self.press_timer = clock.run(self.long_press, self)
    end,
    on_release = function (self)
      self.pressed = false
      if last_step_pressed then
        return
      end

      if step_editor.currently_pressed_step == self.index then
        step_editor.currently_pressed_step = nil
      end
      -- if not self.active then
      --   self:set()
      --   return
      -- end
      if self.edited_while_pressed then
        self.edited_while_pressed = false
        return
      end
      if self.press_timer then
        clock.cancel(self.press_timer)
        self:short_press()
      end
    end,

    get_grid_color = function (self)
      if self.pressed and self.active then
        return color.PRESSED
      elseif current_playback_mode ~= playback_mode.STOPPED and self.index == self.pattern.current_step then
        return step_editor.currently_playing_color
      elseif last_step_pressed then
        return self.index == self.pattern.last_step and step_editor.active_color or color.DEFAULT
      elseif self.active and not self.edited_fill_or_offset and next(self.step_params) == nil then
        return step_editor.active_color
      elseif self.active and (self.edited_fill_or_offset or next(self.step_params) ~= nil) then
        return step_editor.edited_params_color
      elseif not self.active then
        return color.DEFAULT
      end
    end
  }

  Pattern = {
    index = nil,
    pressed = false,

    current_step = 1,
    begin_step = 1,
    end_step = 16,
    last_step = 16,
    max_step = 64,
    sequence = nil,
    reset_to_track_params = true,

    -- roll specific
    roll_enabled = false,
    rolled_steps = 0,

    timer = nil,
    run_timer = function (self)
      self.timer = clock.run(function (self)
        clock.sleep(1.5)
        self.timer = nil
      end, self)
    end,

    new = function (self, index)
      local o = {}
      setmetatable(o, self)
      self.__index = self

      o.index = index
      o.sequence = {}
      for i=1,o.max_step do
        o.sequence[i] = Step:new(o, i)
      end
      return o
    end,

    extend = function (self)
      local steps_to_copy = self.last_step % 16 == 0 and 16 or self.last_step
      for i=1,steps_to_copy do
        if self.last_step < self.max_step then
          self.last_step = self.last_step + 1
        else
          break
        end
        local dont_copy = {}
        dont_copy[self] = self
        self.sequence[self.last_step] = table_utils.deepcopy(self.sequence[i], dont_copy)
        self.sequence[self.last_step].index = self.last_step
      end
      self.end_step = self.last_step
    end,

    reset_step_params = function (self)
      for _, step in pairs(self.sequence) do
        step.step_params = {}
        step.edited_params = false
      end
    end,

    reset_pattern_data = function (self)
      self.current_step = 1
      self.begin_step = 1
      self.end_step = 16
      self.last_step = 16
      self.max_step = 64
      self.reset_to_track_params = true
      self.roll_enabled = false
      self.rolled_steps = 0
      self.sequence = {}
      for i=1,self.max_step do
        self.sequence[i] = Step:new(self, i)
      end
    end,

    set_roll = function (self, roll)
      if roll == 4 or roll == 2 then
        local beat_step_base = math.floor(self.current_step / roll) * roll
        if self.current_step == beat_step_base then
          beat_step_base = beat_step_base - roll
        end
        self.begin_step = beat_step_base + 1
        self.end_step = util.clamp(beat_step_base + roll, 1, self.last_step)
      elseif roll == 1 then
        self.begin_step = self.current_step
        self.end_step = self.current_step
      else
        print("Unsupported roll value: " .. tostring(roll))
        return false
      end
      self.rolled_steps = self.current_step
      self.roll_enabled = true
      return true
    end,
    reset_roll = function (self)
      if self.roll_enabled then
        self.begin_step = 1
        self.end_step = self.last_step
        self.current_step = (self.rolled_steps - 1) % self.last_step + 1
        self.roll_enabled = false
      end
    end,

    on_press = function (self)
      self.pressed = true

      if utility_mode:is_erase() then
        utility_mode:set_none()
        for _, track_data in pairs(tracks_data) do
          track_data.patterns[self.index]:reset_pattern_data()
        end
        self:run_timer()
        return
      end

      if utility_mode:is_copy() then
        if clipboard:empty() then
          clipboard:store_pattern(self.index)
          return
        elseif clipboard:has_pattern() then
          -- if clipboard pattern is different than this then copy
          if not clipboard:has_pattern(self.index) then
            for _, track_data in pairs(tracks_data) do
              track_data.patterns[self.index] = table_utils.deepcopy(track_data.patterns[clipboard.pattern])
              track_data.patterns[self.index].index = self.index
              track_data.patterns[self.index]:reset_step_params()
            end
          end
          -- after copy, THIS pattern (self) is no longer accessed anywhere therefore
          -- run_timer() must be called on fresh copy
          tracks_data[step_editor.current_track].patterns[self.index]:run_timer()
          clipboard:clear()
          utility_mode:set_none()
          return
        end
      end

      pattern_selector.selected_pattern = self.index
      if current_playback_mode == playback_mode.STOPPED then
        pattern_selector.current_pattern = self.index
      end
    end,
    on_release = function (self)
      self.pressed = false
    end,
    get_grid_color = function (self)
      if self.pressed then
        return color.PRESSED
      elseif self.timer then
        return flash_fast and color.PRESSED or color.DEFAULT
      elseif clipboard:has_pattern(self.index) then
        return flash_fast and color.PRESSED or color.DEFAULT
      elseif utility_mode:is_erase() then
        return flash_slow and color.PRESSED or color.DEFAULT
      elseif clipboard:has_pattern() then
        return flash_slow and color.PRESSED or color.DEFAULT
      elseif utility_mode:is_copy() and clipboard:empty() then
        return flash_slow and color.PRESSED or color.DEFAULT
      elseif pattern_selector.current_pattern == self.index then
        return pattern_selector.currently_playing_color
      elseif pattern_selector.selected_pattern == self.index then
        return flash_slow and pattern_selector.selected_to_play_next_color or color.DEFAULT
      else
        return color.DEFAULT
      end
    end
  }

  object.patterns = {}
  for i=1,pattern_selector.total_patterns do
    object.patterns[i] = Pattern:new(i)
  end
  return object
end

function init_tracks_data()
  tracks_data = {
    TrackData:new(1,"BD", 1,8, 11, 64,
      {
        {param_id = "BD level"},
        {param_id = "BD tone", draw_note = true},
        {param_id = "BD decay"}
      },
      function(self)
        engine.kick_trigger()
      end
    ),
    TrackData:new(2,"SD", 2,8, 26, 64,
      {
        {param_id = "SD level"},
        {param_id = "SD snappy"},
        -- {param_id = "SD tone", draw_note = true},
        {param_id = "SD decay"}
      },
      function(self)
        engine.snare_trigger()
      end
    ),
    TrackData:new(3,"MT", 3,8, 41, 64,
      {
        {param_id = "MT level"},
        {param_id = "MT tone", draw_note = true},
        {param_id = "MT decay"}
      },
      function(self)
        engine.mt_trigger()
      end
    ),
    TrackData:new(4,"CH", 4,8, 56, 64,
      {
        {param_id = "CH level"},
        {param_id = "CH tone", draw_note = true},
        {param_id = "CH decay"}
      },
      function(self)
        engine.ch_trigger()
      end
    ),
  TrackData:new(5,"OH", 5,8, 71, 64,
      {
        {param_id = "OH level"},
        {param_id = "OH tone", draw_note = true},
        {param_id = "OH decay"}
      },
      function(self)
        engine.oh_trigger()
      end
    ),
    TrackData:new(6,"CP", 6,8, 86, 64,
      {
        {param_id = "CP level"}
      },
      function(self)
        engine.clap_trigger()
      end
    ),
    TrackData:new(7,"CW", 7,8, 101, 64,
      {
        {param_id = "CW level"}
      },
      function(self)
        engine.cowbell_trigger()
      end
    ),
    TrackData:new(8,"RS", 8,8, 116, 64,
      {
        {param_id = "RS level"}
      },
      function(self)
        engine.rimshot_trigger()
      end
    )
  }
end

local utility_buttons_grid_map = {}
local utility_buttons = {}

function init_utility_buttons()
  -- TODO make each utility an object and then put into a table for easy access by grid
  -- TODO this will allow to use play_pause_button.pressed in the code, and skip globals
  utility_buttons = {
    {
      name = "rec",
      grid_x = 1,
      grid_y = 1,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        if current_recording_mode == recording_mode.RECORDING then
          current_recording_mode = recording_mode.NOT_RECORDING
        else
          current_recording_mode = recording_mode.RECORDING
        end
      end,
      on_release = function (self)
        self.pressed = false
      end,
      recording_color = 10,
      get_grid_color = function (self)
        if current_recording_mode == recording_mode.RECORDING then
          return self.recording_color
        else
          return color.DEFAULT
        end
      end
    },
    {
      name = "play/pause",
      grid_x = 3,
      grid_y = 1,
      pressed = false,
      on_press = function (self)
        self.pressed = true
          if current_playback_mode == playback_mode.PLAYING then
            clk:stop()
            current_partial_step = 1
            current_playback_mode = playback_mode.PAUSED
          else
            clk:start()
            current_playback_mode = playback_mode.PLAYING
          end
      end,
      on_release = function (self)
        self.pressed = false
      end,
      paused_color = 5,
      playing_color = 15,
      get_grid_color = function (self)
        if current_playback_mode == playback_mode.PLAYING then
          return self.playing_color
        elseif current_playback_mode == playback_mode.PAUSED then
          return self.paused_color
        else
          return color.DEFAULT
        end
      end
    },
    {
      name = "stop",
      grid_x = 2,
      grid_y = 1,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        clk:stop()

        current_playback_mode = playback_mode.STOPPED
        current_partial_step = 1
        for k,track in ipairs(tracks_data) do
          local pattern = track.patterns[pattern_selector.current_pattern]
          pattern.current_step = 1
        end
        pattern_selector.selected_pattern = pattern_selector.current_pattern
      end,
      on_release = function (self)
        self.pressed = false
      end,
      get_grid_color = function (self)
        return self.pressed and color.PRESSED or color.DEFAULT
      end
    },
    {
      name = "shift",
      grid_x = 4,
      grid_y = 3,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        shift_pressed = true
      end,
      on_release = function (self)
        self.pressed = false
        shift_pressed = false
      end,
      get_grid_color = function (self)
        return self.pressed and color.PRESSED or color.DEFAULT
      end
    },
    {
      name = "last_step",
      grid_x = 4,
      grid_y = 2,
      pressed = false,
      -- TODO apply validity_check to other utility buttons
      valid_modes = { mode.STEP_EDIT },
      valid_in_current_mode = function (self)
        -- nil means it is valid in all modes
        if self.valid_modes == nil then
          return true
        end

        return table_utils.contains(self.valid_modes, current_mode)
      end,

      on_press = function (self)
        if not self:valid_in_current_mode() then return end
        if current_playback_mode ~= playback_mode.STOPPED then return end

        self.pressed = true
        last_step_pressed = true
      end,
      on_release = function (self)
        if not self:valid_in_current_mode() then return end
        if current_playback_mode ~= playback_mode.STOPPED then return end

        self.pressed = false
        last_step_pressed = false
      end,
      get_grid_color = function (self)
        if not self:valid_in_current_mode() then return color.DISABLED end
        if current_playback_mode ~= playback_mode.STOPPED then return color.DISABLED end
        return self.pressed and color.PRESSED or color.DEFAULT
      end
    },
    {
      name = "erase",
      grid_x = 6,
      grid_y = 1,
      pressed = false,

      on_press = function (self)
        self.pressed = true
      end,
      on_release = function (self)
        self.pressed = false
        if current_playback_mode ~= playback_mode.STOPPED then
          return
        end

        if not utility_mode:is_erase() then
          utility_mode:set_erase()
        else
          utility_mode:set_none()
        end
      end,
      get_grid_color = function (self)
        if current_playback_mode ~= playback_mode.STOPPED then
          return color.DISABLED
        elseif self.pressed then
          return color.PRESSED
        elseif utility_mode:is_erase() then
          return flash_slow and color.PRESSED or color.DEFAULT
        else
          return color.DEFAULT
        end
      end
    },
    {
      name = "copy",
      grid_x = 7,
      grid_y = 1,
      pressed = false,

      on_press = function (self)
        self.pressed = true
      end,
      on_release = function (self)
        self.pressed = false
        if current_playback_mode ~= playback_mode.STOPPED then
          return
        end

        if not utility_mode:is_copy() then
          utility_mode:set_copy()
        else
          utility_mode:set_none()
        end
        clipboard:clear()
      end,
      get_grid_color = function (self)
        if current_playback_mode ~= playback_mode.STOPPED then
          return color.DISABLED
        elseif self.pressed then
          return color.PRESSED
        elseif utility_mode:is_copy() then
          return flash_slow and color.PRESSED or color.DEFAULT
        else
          return color.DEFAULT
        end
      end
    },
    {
      name = "extend",
      grid_x = 8,
      grid_y = 1,
      pressed = false,
      timer = nil,

      run_timer = function (self)
        self.timer = clock.run(function (self)
          clock.sleep(1)
          self.timer = nil
        end, self)
      end,
      on_press = function (self)
        self.pressed = true
      end,
      on_release = function (self)
        self.pressed = false
        if current_playback_mode ~= playback_mode.STOPPED or current_mode == mode.PATTERN_SELECTION then
          return
        end

        if currently_focused_track ~= nil then
          tracks_data[currently_focused_track].patterns[pattern_selector.current_pattern]:extend()
        else
          for _, track_data in pairs(tracks_data) do
            track_data.patterns[pattern_selector.current_pattern]:extend()
          end
        end
        self:run_timer()
      end,

      get_grid_color = function (self)
        if current_playback_mode ~= playback_mode.STOPPED or current_mode == mode.PATTERN_SELECTION then
          return color.DISABLED
        elseif self.pressed then
          return color.PRESSED
        elseif self.timer then
          return flash_fast and color.PRESSED or color.DEFAULT
        else
          return color.DEFAULT
        end
      end
    },
    {
      name = "pattern_selector",
      grid_x = 1,
      grid_y = 2,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        current_mode = mode.PATTERN_SELECTION
      end,
      on_release = function (self)
        self.pressed = false
      end,
      get_grid_color = function (self)
        if self.pressed or current_mode == mode.PATTERN_SELECTION then
          return color.PRESSED
        else
          return color.DEFAULT
        end
      end
    },
    {
      name = "step_editor",
      grid_x = 2,
      grid_y = 2,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        current_mode = mode.STEP_EDIT
      end,
      on_release = function (self)
        self.pressed = false
      end,
      get_grid_color = function (self)
        if self.pressed or current_mode == mode.STEP_EDIT then
          return color.PRESSED
        else
          return color.DEFAULT
        end
      end
    },

  }

  local roll_fill_offset_per_button = {
    {nil, nil, 0},{4, 1, 1}, {2, 2, 2}, {1, 4, 3}
  }

  for key,data in ipairs(roll_fill_offset_per_button) do
    -- roll over 1 beat OR fill step with 1 partial step OR offset partials steps by 1, etc.
    local roll, fill, offset = data[1], data[2], data[3]
    table.insert(utility_buttons, {
      name = "roll" .. (roll or ""),
      grid_x = 5 + key - 1,
      grid_y = 3,
      active_color = 5,
      pressed = false,
      on_press = function (self)
        self.pressed = true

        if step_editor.currently_pressed_step ~= nil then
          if offset ~= nil and shift_pressed then
            tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]:edit_offset(offset)
            return
          end
          if fill ~= nil then
            tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]:edit_fill(fill)
            return
          end
        end

        if roll ~= nil and current_playback_mode == playback_mode.PLAYING then
          if currently_focused_track ~= nil then
            tracks_data[currently_focused_track].patterns[pattern_selector.current_pattern]:set_roll(roll)
            return
          end
          for key,track_data in ipairs(tracks_data) do
            track_data.patterns[pattern_selector.current_pattern]:set_roll(roll)
          end
        end
      end,

      on_release = function (self)
        self.pressed = false

        if roll ~= nil and step_editor.currently_pressed_step == nil then
          if currently_focused_track ~= nil then
            tracks_data[currently_focused_track].patterns[pattern_selector.current_pattern]:reset_roll(roll)
            return
          end
          for key,track_data in ipairs(tracks_data) do
            track_data.patterns[pattern_selector.current_pattern]:reset_roll()
          end
        end
      end,

      get_grid_color = function (self)
        if step_editor.currently_pressed_step ~= nil then
          local step = tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]
          if offset ~= nil and shift_pressed then
              return step.current_offset == offset and self.active_color or color.DEFAULT
          end
          if fill ~= nil then
            return step.current_fill == fill and self.active_color or color.DEFAULT
          end
        end

        if roll ~= nil then
          return self.pressed and color.PRESSED or color.DEFAULT
        end

        return 0
      end
    })
  end
end

function to_grid_birghtness(value, range)
  local min, max = range[1], range[2]
  local result = math.floor(((value - min) / (max - min) * 14) + 1 + 0.5)
  return result
end

function init()
  screen.blend_mode(2)
  screen.font_face(25)
  screen.font_size(6)
  screen.aa(0)
  screen.line_width(1)

  norns.enc.sens(1, 4)
  norns.enc.sens(2, 6)
  norns.enc.sens(3, 5)

  -- clock management
  clk_midi.event = function(data)
      clk:process_midi(data)
  end

  clk.steps_per_beat = 16
  clk:bpm_change(110)
  clk.on_step = execute_partial_step
  clk.on_select_internal = function()
      clk:start()
  end
  -- clk.on_select_external = reset_sequence
  -- clk.on_start = reset_sequence

  impact_params:init()
  params.action_write = function(filename,name)
    print("finished writing '"..filename.."' as '"..name.."'")
    os.execute("mkdir -p ".._path.data..'/impact/'..name..'/')
    tab.save(tracks_data, _path.data..'/impact/'..name..'/tracks_data.data')
  end
  params.action_read = function(filename)
    print("finished reading '"..filename.."'")
    local loaded_file = io.open(filename, "r")
    if loaded_file then
      io.input(loaded_file)
      local pset_name = string.sub(io.read(), 4, -1) -- grab the PSET name from the top of the PSET file
      io.close(loaded_file)
      init_tracks_data()
      tdata = tab.load(_path.data..'/impact/'..pset_name..'/tracks_data.data')
      table_utils.set_table(tracks_data, tdata)
    end
  end

  init_tracks_data() -- TODO move into method like step_editor:init() and other
  init_utility_buttons()

  -- init tracks
  for key,value in ipairs(tracks_data) do
    if tracks_buttons_grid_map[value.trigger_button.grid_x] == nil then
      tracks_buttons_grid_map[value.trigger_button.grid_x] = {}
    end
    tracks_buttons_grid_map[value.trigger_button.grid_x][value.trigger_button.grid_y] = value.trigger_button

    if tracks_buttons_grid_map[value.focus_button.grid_x] == nil then
      tracks_buttons_grid_map[value.focus_button.grid_x] = {}
    end
    tracks_buttons_grid_map[value.focus_button.grid_x][value.focus_button.grid_y] = value.focus_button
  end

  pattern_selector:init()

  step_editor:init()
  -- init step editor buttons
  for key,value in ipairs(step_editor.pages_buttons) do
    if pages_buttons_grid_map[value.grid_x] == nil then
      pages_buttons_grid_map[value.grid_x] = {}
    end
    pages_buttons_grid_map[value.grid_x][value.grid_y] = value
  end

  -- init utility buttons
  for key,value in ipairs(utility_buttons) do
    if utility_buttons_grid_map[value.grid_x] == nil then
      utility_buttons_grid_map[value.grid_x] = {}
    end
    utility_buttons_grid_map[value.grid_x][value.grid_y] = value
  end

  grid_dirty = true -- TODO decide globals or locals
  screen_dirty = true
  clock.run(redraw_clock)
end

current_partial_step = 1 -- must bo global for stop button -- TODO FIX THIS
local change_pattern = false
function execute_partial_step()
  local pattern_changed = false
  if change_pattern then
    pattern_selector.current_pattern = pattern_selector.selected_pattern
    pattern_changed = true
    change_pattern = false
  end

  for key,track in ipairs(tracks_data) do
    local pattern = track.patterns[pattern_selector.current_pattern]
    if pattern_changed then
      pattern.current_step = pattern.begin_step
    end

    if pattern.sequence[pattern.current_step].partial_steps[current_partial_step] == 1 then
      track:trigger()
      track.trigger_button.pressed = true
    else
      track.trigger_button.pressed = false
    end

    if current_partial_step == TrackData.partials_per_step then
      if pattern.roll_enabled then
        pattern.rolled_steps = pattern.rolled_steps + 1
      end
      pattern.current_step = pattern.current_step + 1
      if pattern.current_step > pattern.end_step then
        pattern.current_step = pattern.begin_step

        if pattern_selector:is_longest_track_in_current_pattern(track.index) and pattern_selector.selected_pattern ~= pattern_selector.current_pattern then
          change_pattern = true
        end
      end
      track:prepare_step_params()
    end
  end

  if current_partial_step == TrackData.partials_per_step then
    current_partial_step = 1
    step_editor:pattern_follow_tick()
  else
    current_partial_step = current_partial_step + 1
  end

  if current_playback_mode == playback_mode.PLAYING then
    grid_dirty = true
    screen_dirty = true
  end
end

function redraw_clock()
  while true do
    clock.sleep(1 / 30)
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
    if grid_dirty then
      grid_redraw()
      grid_dirty = false
    end
  end
end


function redraw()
  screen.clear()

  playback = ui.PlaybackIcon.new(0,1,5,current_playback_mode)
  playback:redraw()
  ui_utils.draw_rec(7, 6, current_recording_mode ~= recording_mode.NOT_RECORDING)
  ui_utils.draw_bpm(22, 6, params:get("bpm"), false)

  local pressed_step = step_editor.currently_pressed_step
  if pressed_step == nil then
    ui_utils.draw_inv_value(54, 6, string.format("P:%02d", pattern_selector.current_pattern), current_mode == mode.PATTERN_SELECTION, false, 2, 2)
    if current_mode == mode.STEP_EDIT then
      ui_utils.draw_inv_value(74, 6, string.format("T:%d", step_editor.current_track), true, false, 2, 2)
      local current_pattern = tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern]
      ui_utils.draw_pages(89, 6, step_editor.current_page, current_pattern.current_step, current_pattern.last_step, step_editor.pattern_follow)
    end
  else
    ui_utils.draw_inv_value(54, 6, "S:" .. tostring(pressed_step < 10 and "0" or "") .. tostring(pressed_step), true, false, 2, 2)
    ui_utils.draw_inv_value(74, 6, "FILL", true, false, 2, 2)
    local current_step = tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[pressed_step]
    ui_utils.draw_partial_steps(88, 6, current_step.partial_steps)
  end

  screen.stroke()
  local last_track_x
  for key,track_data in ipairs(tracks_data) do
    last_track_x = track_data.screen_x

    screen.aa(1)
    for pkey, param in ipairs(track_data.track_params) do
      param:dial_redraw()
    end
    screen.aa(0)

    ui_utils.draw_track_vertical_line(track_data.screen_x, key == 1)
    ui_utils.draw_inv_label(
        track_data.screen_x,
        track_data.screen_y,
        track_data.name,
        step_editor.current_track == key and current_mode == mode.STEP_EDIT,
        track_data.muted)

    screen.stroke()
  end
  ui_utils.draw_last_vertical_line(last_track_x)

  screen.update()
end

function grid_redraw()
  g:all(0)

  -- light tracks buttons
  for key,track in ipairs(tracks_data) do
    local trigger_button = track.trigger_button
    g:led(trigger_button.grid_x, trigger_button.grid_y, trigger_button:get_grid_color())

    local focus_button = track.focus_button
    g:led(focus_button.grid_x, focus_button.grid_y, focus_button:get_grid_color())
  end

  -- light step editor sequence
  if current_mode == mode.STEP_EDIT then
    local current_view_begin, current_view_end = step_editor:get_current_view_range()
    local current_pattern = tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern]
    for i=current_view_begin,current_view_end do
      local x, y = step_editor:index_to_grid_xy(i)
      g:led(x, y, current_pattern.sequence[i]:get_grid_color())
    end
  -- light pattern selector
  elseif current_mode == mode.PATTERN_SELECTION then
    for i=1,pattern_selector.total_patterns do
      local x, y = pattern_selector:index_to_grid_xy(i)
      g:led(x, y, tracks_data[step_editor.current_track].patterns[i]:get_grid_color())
    end
  end

  -- ligth pages buttons
  if current_mode == mode.STEP_EDIT then
    for key,value in ipairs(step_editor.pages_buttons) do
      g:led(value.grid_x, value.grid_y, value:get_grid_color())
    end
  end

  -- ligth utility buttons
  for key,value in ipairs(utility_buttons) do
    g:led(value.grid_x, value.grid_y, value:get_grid_color())
  end

  g:refresh()
end

function g.key(x, y, state)
  local track
  if tracks_buttons_grid_map[x] then
    track = tracks_buttons_grid_map[x][y]
  end
  if track ~= nil then
    if state == 1 then
      track:on_press()
    else
      track:on_release()
    end
    grid_dirty = true
    screen_dirty = true
    return
  end

  if current_mode == mode.STEP_EDIT then
    local page_button
    if pages_buttons_grid_map[x] then
      page_button = pages_buttons_grid_map[x][y]
    end
    if page_button ~= nil then
      if state == 1 then
        page_button:on_press()
      else
        page_button:on_release()
      end
      grid_dirty = true
      screen_dirty = true
      return
    end
  end


  local utility_button
  if utility_buttons_grid_map[x] then
    utility_button = utility_buttons_grid_map[x][y]
  end
  if utility_button ~= nil then
    if state == 1 then
      utility_button:on_press()
    else
      utility_button:on_release()
    end
    grid_dirty = true
    screen_dirty = true
    return
  end

  if current_mode == mode.STEP_EDIT then
    if step_editor:grid_xy_valid(x, y) then
      local step_index = step_editor:grid_xy_to_index(x, y)
      if state == 1 then
        tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_index]:on_press()
      else
        tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_index]:on_release()
      end
      grid_dirty = true
      screen_dirty = true
      return
    end
  elseif current_mode == mode.PATTERN_SELECTION then
    if pattern_selector:grid_xy_valid(x, y) then
      local pattern_index = pattern_selector:grid_xy_to_index(x, y)
      if state == 1 then
        tracks_data[step_editor.current_track].patterns[pattern_index]:on_press()
      else
        tracks_data[step_editor.current_track].patterns[pattern_index]:on_release()
      end
      grid_dirty = true
      screen_dirty = true
    end
  end
end

function enc(n,d)
  if step_editor.currently_pressed_step then
    tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]:param_delta(n, d)
    screen_dirty = true
    return
  end

  for key,track in ipairs(tracks_data) do
    if track.focused then
      track.track_params[n]:track_param_delta(d)
    end
  end
end
