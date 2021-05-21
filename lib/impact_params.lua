local music = require "musicutil"
local impact_params = {}
function impact_params:init()
  params:add_separator("clock parameters")
  clk:add_clock_params()

  params:add_separator("sound parameters")
  params:add {
      type = "number",
      id = "BD tone",
      name = "BD tone",
      min = 24, -- C1
      max = 60, -- C4
      default = 36, -- C2
      action = function(x)
          engine.kick_tone(music.note_num_to_freq(x))
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "BD decay",
      name = "BD decay",
      min = 1,
      max = 35,
      default = 25,
      action = function(x)
          engine.kick_decay(x)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "BD level",
      name = "BD level",
      min = 0,
      max = 100,
      default = 90,
      action = function(x)
          engine.kick_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "MT tone",
      name = "MT tone",
      min = 36, -- C2
      max = 72, -- C5
      default = 48, -- C3
      action = function(x)
          engine.mt_tone(music.note_num_to_freq(x))
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "MT decay",
      name = "MT decay",
      min = 5,
      max = 35,
      default = 12,
      action = function(x)
          engine.mt_decay(x)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "MT level",
      name = "MT level",
      min = 0,
      max = 100,
      default = 50,
      action = function(x)
          engine.mt_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "CH tone",
      name = "CH tone",
      min = 60, -- C4
      max = 96, -- C7
      default = 72, -- C5,
      action = function(x)
          engine.ch_tone(music.note_num_to_freq(x))
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "CH decay",
      name = "CH decay",
      min = 10,
      max = 30,
      default = 15,
      action = function(x)
          engine.ch_decay(x / 10)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "CH level",
      name = "CH level",
      min = 0,
      max = 100,
      default = 75,
      action = function(x)
          engine.ch_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "OH tone",
      name = "OH tone",
      min = 57, -- A3
      max = 96, -- C7
      default = 69, -- A4
      action = function(x)
          engine.oh_tone(music.note_num_to_freq(x))
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "OH decay",
      name = "OH decay",
      min = 10,
      max = 40,
      default = 15,
      action = function(x)
          engine.oh_decay(x / 10)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "OH level",
      name = "OH level",
      min = 0,
      max = 100,
      default = 75,
      action = function(x)
          engine.oh_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "SD tone",
      name = "SD tone",
      min = 45, -- A2
      max = 84, -- C6
      default = 60, -- C4
      action = function(x)
          engine.snare_tone(music.note_num_to_freq(x))
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "SD snappy",
      name = "SD snappy",
      min = 1,
      max = 300,
      default = 130,
      action = function(x)
          engine.snare_snappy(x / 100)
          screen_dirty = true
      end
  }
  params:add {
    type = "number",
    id = "SD decay",
    name = "SD decay",
    min = 5,
    max = 300,
    default = 30,
    action = function(x)
        engine.snare_decay(x/10)
        screen_dirty = true
    end
}
  params:add {
      type = "number",
      id = "SD level",
      name = "SD level",
      min = 0,
      max = 100,
      default = 70,
      action = function(x)
          engine.snare_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "CP level",
      name = "CP level",
      min = 0,
      max = 100,
      default = 75,
      action = function(x)
          engine.clap_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "CW level",
      name = "CW level",
      min = 0,
      max = 100,
      default = 35,
      action = function(x)
          engine.cowbell_level(x/100)
          screen_dirty = true
      end
  }
  params:add {
      type = "number",
      id = "CL level",
      name = "CL level",
      min = 0,
      max = 100,
      default = 30,
      action = function(x)
          engine.claves_level(x/100)
          screen_dirty = true
      end
  }
    params:add {
      type = "number",
      id = "RS level",
      name = "RS level",
      min = 0,
      max = 100,
      default = 50,
      action = function(x)
          engine.rimshot_level(x/100)
          screen_dirty = true
      end
  }
end

return impact_params