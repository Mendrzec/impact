-- impact

local ui = require "ui"

engine.name = "Impact"

local impact_params = include("lib/impact_params")
-- local step_editor = include("lib/step_editor")
local ui_utils = include("lib/ui_utils")

local grid = include("midigrid/lib/mg_128")
local g = grid.connect()

local MIDI_Clock = require "beatclock"
clk = MIDI_Clock.new() -- global for impact_params how to fix that?
local clk_midi = midi.connect()

function table.shift(t, n)
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

local shift_pressed = false
local mode = {
    PATTERN_SELECTION = 1,
    STEP_EDIT = 2
}
local current_mode = mode.STEP_EDIT
local pattern_selector = {
  current_pattern = 1
}
step_editor = {
  default_color = 1,
  edited_params_color = 7,
  active_color = 10,
  currently_playing_color = 13,
  pressed_color = 15,

  total_steps = 64,
  steps_per_page = 16,
  page_count = 4,
  current_page = 1,
  current_track = 1,
  currently_pressed_step = nil,

  grid_rows = 2,
  grid_row_length = 8,
  grid_start_x = 1,
  grid_start_y = 3,
  step_to_grid_xy_map = {},
  grid_xy_to_step_map = {}
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
    if x >= self.grid_row_length then
      x = 0
      y = y + 1
    end
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

-- TODO consider renaming to TrackData
InstrumentData = {
  partials_per_step = 4, -- used for higher resolution
  default_color = 1,
  active_color = 5,
  pressed_color = 15,
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
  trigger_button = {},
  focused = false,
  focus_button = {},
  muted = false,
}

function InstrumentData:trigger()
  if not self.muted then
    self.trigger_callback(self)
  end
end

function InstrumentData:prepare_step_params()
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

function InstrumentData:new(index, name, gx, gy, sx, sy, track_params, callback)
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
      dial_x = object.screen_x,
      dial_y = object.screen_y - 6 - (self.max_params_count - key + 1) * 16,
      dial = nil,
      range = params:get_range(value.param_id),
      track_value = params:get(value.param_id),

      set = function(v) params:set(value.param_id, v) end,
      reset = function(self) self.set(self.track_value) end,
      get = function() return params:get(value.param_id) end,
      track_param_delta = function(self, d)
        self.track_value = util.clamp(self.track_value + d, self.range[1], self.range[2])
        self.set(self.track_value)
      end,
      dial_redraw = function(self)
        if self.dial == nil then
          self.dial = ui.Dial.new(self.dial_x, self.dial_y, 8, self.track_value, self.range[1], self.range[2], 1, self.range[1], {}, nil, nil)
        end

        if current_mode == mode.STEP_EDIT and step_editor.currently_pressed_step and step_editor.current_track == object.index then
          self.dial.active = true
          local step_params = object.patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step].step_params
          local param = step_params[key]
          if param ~=nil then
            self.dial:set_value(param.value)
            ui_utils.draw_dot(self.dial_x -2, self.dial_y, 15)
          else
            self.dial:set_value(self.track_value)
          end
          self.dial:redraw()
          return
        end

        self.dial.active = object.focused
        self.dial:set_value(self.get())
        self.dial:redraw()
      end
    }
  end

  object.trigger_button = {
    grid_x = object.grid_x,
    grid_y = object.grid_y,
    pressed = false,

    on_press = function (self)
      self.pressed = true
      object:trigger()
      if current_mode == mode.STEP_EDIT then
        step_editor.current_track = object.index
      end
    end,
    on_release = function (self)
      self.pressed = false
    end,
    get_grid_color = function (self)
      if object.muted then
        return InstrumentData.default_color
      end
      if current_mode == mode.STEP_EDIT and step_editor.current_track == object.index then
        return not self.pressed and InstrumentData.pressed_color or InstrumentData.active_color
      else
        return self.pressed and InstrumentData.pressed_color or InstrumentData.active_color
      end
    end
  }

  object.focus_button = {
    grid_x = object.grid_x,
    grid_y = object.grid_y - 1,
    pressed = false,

    on_press = function (self)
      self.pressed = true
      object.focused = true
      if current_mode == mode.STEP_EDIT then
        step_editor.current_track = object.index
      end
      if shift_pressed then
        object.muted = not object.muted
      end
    end,
    on_release = function (self)
      self.pressed = false
      object.focused = false
    end,
    get_grid_color = function(self)
      return self.pressed and InstrumentData.pressed_color or InstrumentData.default_color
    end
  }

  -- TODO add method to add new patterns
  object.patterns = {}
  object.patterns[1] = {
    current_step = 1,
    begin_step = 1,
    end_step = 16,
    last_step = 16,
    max_step = 64,
    sequence = {},
    reset_to_track_params = true,
    -- roll specific
    roll_enabled = false,
    rolled_steps = 0,

    set_roll = function (self, roll)
      if roll == 4 or roll == 2 then
        local beat_step_base = math.floor(self.current_step / roll) * roll
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
      self.begin_step = 1
      self.end_step = self.last_step
      self.current_step = (self.rolled_steps - 1) % self.last_step + 1
      self.roll_enabled = false
    end
  }

  local pattern = object.patterns[1]
  for i=1,pattern.max_step do
    pattern.sequence[i] = {
      partial_steps = {0,0,0,0, 0,0,0,0}, -- 4 and 4 more to recover from offset
      current_fill = 1,
      current_offset = 0,
      active = false,
      press_timer = nil,
      pressed = false,
      edited_while_pressed = false,
      edited_params = false,
      edited_fill_or_offset = false,
      step_params = {},

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
        table.shift(self.partial_steps, self.current_offset)
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
        if table.shift(self.partial_steps, offset - self.current_offset) then
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
        step_editor.currently_pressed_step = i
        self.press_timer = clock.run(self.long_press, self)
      end,
      on_release = function (self)
        self.pressed = false
        step_editor.currently_pressed_step = nil
        if not self.active then
          self:set()
          return
        end
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
        if self.pressed then
          return step_editor.pressed_color
        elseif self.active and not self.edited_fill_or_offset and next(self.step_params) == nil then
          return step_editor.active_color
        elseif self.active and (self.edited_fill_or_offset or next(self.step_params) ~= nil) then
          return step_editor.edited_params_color
        elseif not self.active then
          return step_editor.default_color
        end
      end
    }
  end

  return object
end

local tracks_buttons_grid_map = {}
local tracks_data = {}

function init_tracks_data()
  tracks_data = {
    InstrumentData:new(1,"BD", 1,8, 11, 64,
      {
        {param_id = "BD level"},
        {param_id = "BD tone"},
        {param_id = "BD decay"}
      },
      function(self)
        engine.kick_trigger()
      end
    ),
    InstrumentData:new(2,"SD", 2,8, 26, 64,
      {
        {param_id = "SD level"},
        -- {param_id = "SD tone"},
        {param_id = "SD decay"},
        {param_id = "SD snappy"}
      },
      function(self)
        engine.snare_trigger()
      end
    ),
    InstrumentData:new(3,"MT", 3,8, 41, 64,
      {
        {param_id = "MT level"},
        {param_id = "MT tone"},
        {param_id = "MT decay"}
      },
      function(self)
        engine.mt_trigger()
      end
    ),
    InstrumentData:new(4,"CH", 4,8, 56, 64,
      {
        {param_id = "CH level"},
        {param_id = "CH tone"},
        {param_id = "CH decay"}
      },
      function(self)
        engine.ch_trigger()
      end
    ),
  InstrumentData:new(5,"OH", 5,8, 71, 64,
      {
        {param_id = "OH level"},
        {param_id = "OH tone"},
        {param_id = "OH decay"}
      },
      function(self)
        engine.oh_trigger()
      end
    ),
    InstrumentData:new(6,"CP", 6,8, 86, 64,
      {
        {param_id = "CP level"}
      },
      function(self)
        engine.clap_trigger()
      end
    ),
    InstrumentData:new(7,"CW", 7,8, 101, 64,
      {
        {param_id = "CW level"}
      },
      function(self)
        engine.cowbell_trigger()
      end
    ),
    InstrumentData:new(8,"RS", 8,8, 116, 64,
      {
        {param_id = "RS level"}
      },
      function(self)
        engine.rimshot_trigger()
      end
    )
  }
end

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

local current_playback_mode = playback_mode.STOPPED
local current_recording_mode = recording_mode.NOT_RECORDING

local utility_buttons_grid_map = {}
local utility_buttons = {}

function init_utility_buttons()
  utility_buttons = {
    {
      name = "play/pause",
      grid_x = 2,
      grid_y = 1,
      on_press = function (self)
          -- if current_playback_mode == playback_mode.PLAYING then
          --   clk:stop()
          --   current_partial_step = 1
          -- else
            clk:start()
            current_playback_mode = playback_mode.PLAYING
          -- end
      end,
      on_release = function (self) end,
      default_color = 1,
      paused_color = 5,
      playing_color = 15,
      get_grid_color = function (self)
        return current_playback_mode == playback_mode.PLAYING and self.playing_color or self.default_color
      end
    },
    {
      name = "stop",
      grid_x = 1,
      grid_y = 1,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        clk:stop()

        current_playback_mode = playback_mode.STOPPED
        current_partial_step = 1
        for k,instrument in ipairs(tracks_data) do
          local pattern = instrument.patterns[pattern_selector.current_pattern]
          pattern.current_step = 1
          -- if pattern.reset_to_track_params then
          --   for key,param in ipairs(instrument.track_params) do
          --     param:reset()
          --   end
          --   pattern.reset_to_track_params = false
          -- end
        end
      end,
      on_release = function (self)
        self.pressed = false
      end,
      default_color = 1,
      pressed_color = 15,
      get_grid_color = function (self)
        return self.pressed and self.pressed_color or self.default_color
      end
    },
    {
      name = "shift",
      grid_x = 4,
      grid_y = 2,
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
        return self.pressed and 15 or 1
      end
    }
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
      grid_y = 2,
      default_color = 1,
      active_color = 4,
      pressed_color = 15,
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
          for key,track_data in ipairs(tracks_data) do
            track_data.patterns[pattern_selector.current_pattern]:set_roll(roll)
          end
        end
      end,

      on_release = function (self)
        self.pressed = false

        if roll ~= nil and step_editor.currently_pressed_step == nil then
          for key,track_data in ipairs(tracks_data) do
            track_data.patterns[pattern_selector.current_pattern]:reset_roll()
          end
        end
      end,

      get_grid_color = function (self)
        if step_editor.currently_pressed_step ~= nil then
          local step = tracks_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]
          if offset ~= nil and shift_pressed then
              return step.current_offset == offset and self.active_color or self.default_color
          end
          if fill ~= nil then
            return step.current_fill == fill and self.active_color or self.default_color
          end
        end
  
        if roll ~= nil then
          return self.pressed and self.pressed_color or self.default_color
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

  norns.enc.sens(1, 3)
  norns.enc.sens(2, 3)
  norns.enc.sens(3, 3)

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
  init_tracks_data() -- TODO move into method like step_editor:init() and other
  init_utility_buttons()

  -- init instruments
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

  step_editor:init()

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
function execute_partial_step()
  for key,instrument in ipairs(tracks_data) do
    local pattern = instrument.patterns[1]

    if pattern.sequence[pattern.current_step].partial_steps[current_partial_step] == 1 then
      instrument:trigger()
      instrument.pressed = true
    else
      instrument.pressed = false
    end

    if current_partial_step == InstrumentData.partials_per_step then
      if pattern.roll_enabled then
        pattern.rolled_steps = pattern.rolled_steps + 1
      end
      pattern.current_step = pattern.current_step + 1
      if pattern.current_step > pattern.end_step then
        pattern.current_step = pattern.begin_step
      end
      instrument:prepare_step_params()
    end
  end

  if current_partial_step == InstrumentData.partials_per_step then
    current_partial_step = 1
  else
    current_partial_step = current_partial_step + 1
  end

  if current_playback_mode == playback_mode.PLAYING then
    grid_dirty = true
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

  playback = ui.PlaybackIcon.new(0,0,5,current_playback_mode)
  playback:redraw()
  ui_utils.draw_rec(7, 5, current_recording_mode ~= recording_mode.NOT_RECORDING)

  screen.level(4)
  screen.move(0,8)
  screen.line(128,8)
  screen.move(20, 5)
  screen.text("P:" .. tostring(pattern_selector.current_pattern))
  screen.move(45, 5)
  screen.text("BPM:" .. tostring(params:get("bpm")))
  screen.stroke()

  local last_track_x
  for key,track_data in ipairs(tracks_data) do
    last_track_x = track_data.screen_x

    screen.aa(1)
    for pkey, param in ipairs(track_data.track_params) do
      param:dial_redraw()
    end
    screen.aa(0)

    ui_utils.draw_track_vertical_line(track_data.screen_x)
    ui_utils.draw_inv_label(track_data.screen_x, track_data.screen_y, track_data.name, step_editor.current_track == key, track_data.muted)

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

    if current_playback_mode == playback_mode.PLAYING then
      if step_editor:is_index_in_current_view_range(current_pattern.current_step) then
        local x, y = step_editor:index_to_grid_xy(current_pattern.current_step)
        g:led(x, y, step_editor.currently_playing_color)
      end
    end
  end

  -- ligth utility buttons
  for key,value in ipairs(utility_buttons) do
    g:led(value.grid_x, value.grid_y, value:get_grid_color())
  end

  g:refresh()
end

function g.key(x, y, state)
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
