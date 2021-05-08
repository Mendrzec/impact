-- impact

ui = require "ui"

engine.name = "Hachi"
include("impact/lib/impact_params")

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
    return
  end
end

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
  total_steps = 64, -- use from InstrumentData sequence
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
  default_color = 1,
  pressed_color = 6,
  pressed = false,
  name = nil,
  grid_x = nil,
  grid_y = nil,
  screen_x = nil,
  screen_y = nil,
  trigger_callback = nil,
  max_params_count = 3,
  instrument_params = nil,
  partials_per_step = 4, -- used for higher resolution
  patterns = nil
}

function InstrumentData:trigger()
  self.trigger_callback(self)
end

function InstrumentData:prepare_step_params()
  local pattern = self.patterns[pattern_selector.current_pattern]
  local step_params = pattern.sequence[pattern.current_step].step_params

  if pattern.reset_to_track_params then
    for key,param in ipairs(self.instrument_params) do
      param:reset()
    end
    pattern.reset_to_track_params = false
  end

  if next(step_params) ~= nil then
    for param_index=1,#self.instrument_params do
      local param = step_params[param_index]
      if param ~= nil then
        self.instrument_params[param_index].set(param.value)
      end
    end
    pattern.reset_to_track_params = true
  end

end

function InstrumentData:new(name, gx, gy, sx, sy, instrument_params, callback)
  local object = {}
  setmetatable(object, self)
  self.__index = self

  object.name = name;
  object.grid_x = gx
  object.grid_y = gy
  object.screen_x = sx
  object.screen_y = sy
  object.trigger_callback = callback
  object.instrument_params = {}
  for key,value in ipairs(instrument_params) do
    object.instrument_params[key] = {
      param_id = value.param_id,
      -- TODO replace grid_x, grid_y with single button but three different encoders
      grid_x = object.grid_x,
      grid_y = object.grid_y - self.max_params_count + (key - 1),
      dial_x = object.screen_x,
      dial_y = object.screen_y - 6 - key * 16,
      pressed = false,
      dial = nil,
      range = params:get_range(value.param_id),
      track_value = params:get(value.param_id),

      set = function(v) params:set(value.param_id, v) end,
      reset = function(self) self.set(self.track_value) end,
      get = function() return params:get(value.param_id) end,
      delta = function(self, d)
        self.track_value = util.clamp(self.track_value + d, self.range[1], self.range[2])
        self.set(self.track_value)
      end,
      dial_redraw = function(self)
        if self.dial == nil then
          self.dial = ui.Dial.new(self.dial_x, self.dial_y, 8, self.get(), self.range[1], self.range[2], 1, self.range[1], {}, nil, nil)
        end
        self.dial:set_value(self.get())
        self.dial:redraw()
      end
    }
  end

  -- TODO add method to add new patterns
  object.patterns = {}
  object.patterns[1] = {
    current_step = 1,
    begin_step = 1,
    end_step = 16,
    last_step = 16,
    max_step = 64,
    roll_begin = nil,
    roll_end = nil,
    sequence = {},
    reset_to_track_params = true,

    set_roll = function (self, roll)
      if roll == 4 or roll == 2 then
        local beat_step_base = math.floor(self.current_step / roll) * roll
        print(beat_step_base)
        self.begin_step = beat_step_base + 1
        self.end_step = util.clamp(beat_step_base + roll, 1, self.last_step)
      elseif roll == 1 then
        self.begin_step = self.current_step
        self.end_step = self.current_step
      else
        print("Unsupported roll value: " .. tostring(roll))
        return false
      end
      return true
    end,
    reset_roll = function (self)
      self.begin_step = 1
      self.end_step = self.last_step
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
          local param = object.instrument_params[param_index]
          if param ~= nil then
            local param_range = param.range
            self.step_params[param_index] = {
              range = param_range,
              value = util.clamp(param:get() + delta, param_range[1], param_range[2])
            }
          end
        else
          local param_range = self.step_params[param_index].range
          self.step_params[param_index].value = util.clamp(self.step_params[param_index].value + delta, param_range[1], param_range[2])
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
        self:set_offset(self.current_offset)
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
        table.shift(self.partial_steps, offset - self.current_offset)
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

local instruments_grid_map = {}
local instruments_params_grid_map = {}
local instruments_data = {}

function init_instruments_data()
  instruments_data = {
    InstrumentData:new("BD", 1,8, 10, 64,
      {
        {param_id = "BD level"},
        {param_id = "BD tone"},
        {param_id = "BD decay"}
      },
      function(self)
        engine.kick_trigger()
      end
    ),
    InstrumentData:new("SD", 2,8, 24, 64,
      {
        {param_id = "SD level"},
        -- {param_id = "SD tone"},
        {param_id = "SD decay"},
        {param_id = "SD snappy"}
      },
      function(self)
        engine.snare_trigger(1)
      end
    ),
    InstrumentData:new("CH", 3,8, 38, 64,
      {
        {param_id = "CH level"},
        {param_id = "CH tone"},
        {param_id = "CH decay"}
      },
      function(self)
        engine.ch_trigger(1)
      end
    ),
    InstrumentData:new("OH", 4,8, 52, 64,
      {
        {param_id = "OH level"},
        {param_id = "OH tone"},
        {param_id = "OH decay"}
      },
      function(self)
        engine.oh_trigger(1)
      end
    ),
    InstrumentData:new("CW", 5,8, 66, 64,
      {
        {param_id = "CW level"}
      },
      function(self)
        engine.cowbell_trigger(1)
      end
    ),
    InstrumentData:new("CP", 6,8, 80, 64,
      {
        {param_id = "CP level"}
      },
      function(self)
        engine.clap_trigger(1)
      end
    )
  }
end

local play_mode = {
  STOPPED = 4,
  PLAYING = 1,
  PAUSED = 3,
  RECORDING_ARMED = 5,
  RECORDING = 6
}
local current_play_mode = play_mode.STOPPED
local utility_buttons_grid_map = {}
local utility_buttons = {}

function init_utility_buttons()
  utility_buttons = {
    {
      name = "play/pause",
      grid_x = 2,
      grid_y = 1,
      on_press = function (self)
          -- if current_play_mode == play_mode.PLAYING then
          --   clk:stop()
          --   current_partial_step = 1
          -- else
            clk:start()
            current_play_mode = play_mode.PLAYING
          -- end
      end,
      on_release = function (self) end,
      default_color = 1,
      paused_color = 5,
      playing_color = 15,
      get_grid_color = function (self)
        if current_play_mode == play_mode.PLAYING then
          return self.playing_color
        else
          return self.default_color
        end
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

        current_play_mode = play_mode.STOPPED
        current_partial_step = 1
        for k,instrument in ipairs(instruments_data) do
          local pattern = instrument.patterns[pattern_selector.current_pattern]
          pattern.current_step = 1
          
          -- if pattern.reset_to_track_params then
          --   for key,param in ipairs(instrument.instrument_params) do
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
        if self.pressed then
          return self.pressed_color
        else
          return self.default_color
        end
      end
    }
  }

  local roll_fill_shift_per_button = {
    {4, 1, 1}, {2, 2, 2}, {1, 4, 3}
  }

  for key,data in ipairs(roll_fill_shift_per_button) do
    -- roll over 1 beat OR fill step with 1 partial step OR shift partials steps by 1, etc.
    local roll, fill, shift = data[1], data[2], data[3]
    table.insert(utility_buttons, {
      name = "roll" .. roll,
      grid_x = 6 + key - 1,
      grid_y = 2,
      default_color = 1,
      active_color = 4,
      pressed_color = 15,
      pressed = false,
      on_press = function (self)
        self.pressed = true
        if step_editor.currently_pressed_step ~= nil then
          instruments_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]:edit_fill(fill)
          return
        end

        if current_play_mode == play_mode.PLAYING then
          for key,track_data in ipairs(instruments_data) do
            track_data.patterns[pattern_selector.current_pattern]:set_roll(roll)
          end
        end
      end,

      on_release = function (self)
        self.pressed = false
        if step_editor.currently_pressed_step == nil then
          for key,track_data in ipairs(instruments_data) do
            track_data.patterns[pattern_selector.current_pattern]:reset_roll()
          end
        end
      end,

      get_grid_color = function (self)
        if step_editor.currently_pressed_step ~= nil and
            instruments_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step].current_fill == fill then
          return self.active_color
        elseif self.pressed then
          return self.pressed_color
        else
          return self.default_color
        end
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
  screen.font_face(0)
  screen.font_size(8)
  screen.aa(0)
  screen.line_width(1)

  dials = {}
  for i=1,8 do
    dials[i] = ui.Dial.new(9 + (i - 1) * 14, 17, 8, 10, 0, 100, 1, 50, {}, nil, nil) -- TODO fix this, global for tests only
  end

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
  init_instruments_data() -- TODO move into method like step_editor:init() and other
  init_utility_buttons()

  -- init instruments
  for key,value in ipairs(instruments_data) do
    if instruments_grid_map[value.grid_x] == nil then
      instruments_grid_map[value.grid_x] = {}
    end
    instruments_grid_map[value.grid_x][value.grid_y] = {key, value}

    for pkey,pvalue in ipairs(value.instrument_params) do
      if instruments_params_grid_map[pvalue.grid_x] == nil then
        instruments_params_grid_map[pvalue.grid_x] = {}
      end
      instruments_params_grid_map[pvalue.grid_x][pvalue.grid_y] = pvalue
    end
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
  for key,instrument in ipairs(instruments_data) do
    local pattern = instrument.patterns[1]

    if pattern.sequence[pattern.current_step].partial_steps[current_partial_step] == 1 then
      instrument:trigger()
      instrument.pressed = true
    else
      instrument.pressed = false
    end

    if current_partial_step == InstrumentData.partials_per_step then
      pattern.current_step = pattern.current_step + 1
      instrument:prepare_step_params()
    end

    if pattern.current_step > pattern.end_step then
      pattern.current_step = pattern.begin_step
    end
  end

  if current_partial_step == InstrumentData.partials_per_step then
    current_partial_step = 1
  else
    current_partial_step = current_partial_step + 1
  end

  if current_play_mode == play_mode.PLAYING then
    grid_dirty = true
  end
end

function redraw_clock()
  while true do
    clock.sleep(1 / 30)
    if screen_dirty then
      screen_redraw()
      screen_dirty = false
    end
    if grid_dirty then
      grid_redraw()
      grid_dirty = false
    end
  end
end

-- TODO screen UI
function screen_redraw()
  screen.clear()

  -- TODO move to play_mode
  local playback
  if (current_play_mode < 5) then
    playback = ui.PlaybackIcon.new(1,1,5,current_play_mode)
    playback:redraw()
  end

  for key,instrument_data in ipairs(instruments_data) do
    for pkey, param in ipairs(instrument_data.instrument_params) do
      param:dial_redraw()
    end
    screen.move(instrument_data.screen_x, instrument_data.screen_y)
    screen.text(instrument_data.name)
  end
  screen.update()
end

function grid_redraw()
  g:all(0)

  for key,value in ipairs(instruments_data) do
    if current_mode == mode.STEP_EDIT and step_editor.current_track == key then
      if not value.pressed then
        g:led(value.grid_x, value.grid_y, value.pressed_color)
      else
        g:led(value.grid_x, value.grid_y, value.default_color)
      end
    else
      if value.pressed then
        g:led(value.grid_x, value.grid_y, value.pressed_color)
      else
        g:led(value.grid_x, value.grid_y, value.default_color)
      end
    end

    for pkey,pvalue in ipairs(value.instrument_params) do
      g:led(pvalue.grid_x, pvalue.grid_y, to_grid_birghtness(pvalue.get(), pvalue.range))
    end
  end

  -- TODO consider renaming current into seleted
  if current_mode == mode.STEP_EDIT then
    local current_view_begin, current_view_end = step_editor:get_current_view_range()
    local current_pattern = instruments_data[step_editor.current_track].patterns[pattern_selector.current_pattern]
    for i=current_view_begin,current_view_end do
      local x, y = step_editor:index_to_grid_xy(i)
      g:led(x, y, current_pattern.sequence[i]:get_grid_color())
    end

    if current_play_mode == play_mode.PLAYING then
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
  -- print("touched" .. tostring(x) .. tostring(y) .. tostring(state))

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

  local instrument
  local instrument_key
  if instruments_grid_map[x] then
    local key_value = instruments_grid_map[x][y]
    if key_value ~= nil then
      instrument_key, instrument = key_value[1], key_value[2]
    end
  end
  if instrument ~= nil then
    if state == 1 then
      instrument:trigger()
      instrument.pressed = true
      if current_mode == mode.STEP_EDIT then
        step_editor.current_track = instrument_key
      end
    else
      instrument.pressed = false
    end
    grid_dirty = true
    return
  end

  local parameter
  if instruments_params_grid_map[x] then
    parameter = instruments_params_grid_map[x][y]
  end
  if parameter ~= nil then
    if state == 1 then
      parameter.pressed = true
      -- highlight on screen when pressed
    else
      parameter.pressed = false
    end
    return
  end

  if current_mode == mode.STEP_EDIT then
    if step_editor:grid_xy_valid(x, y) then
      local step_index = step_editor:grid_xy_to_index(x, y)
      if state == 1 then
        instruments_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_index]:on_press()
      else
        instruments_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_index]:on_release()
      end
      grid_dirty = true
      return
    end
  end


end

function enc(n,d)
  if step_editor.currently_pressed_step then
    instruments_data[step_editor.current_track].patterns[pattern_selector.current_pattern].sequence[step_editor.currently_pressed_step]:param_delta(n,d)
  end
  if n == 1 then
    for key,value in ipairs(instruments_data) do
      for pkey,pvalue in ipairs(value.instrument_params) do
        if pvalue.pressed then
          pvalue:delta(d)
          screen_dirty = true
          grid_dirty = true
        end
      end
    end
    return
  end
end
