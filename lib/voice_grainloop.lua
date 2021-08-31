-- grainloop synth
-- @classmod voice_grainloop

local voice_grainloop = {}

--- constructor
function voice_grainloop:new(voice_num)
  local o = {}
  self.__index = self
  setmetatable(o, self)

  o.param_prefix = "gl"..voice_num
  o.v = voice_num -- global supercollider voice (synth supports 4 concurrent)
  o.voice_num = voice_num
  o.midi_in_channel = 1 -- input: assume first midi channel

  -- user interface stuff
  o.live_mode = true -- play from files by default
  o.live_buffer_state = 0 -- 0 stopped, 1 play, 2 armed, 3 record, 4 overdub (future)
  o.live_buffer_empty = true
  o.param_shift_key = false -- shift key for selecting params using grid
  o.arc_param_edit = false -- behavior of the arc dial

  -- synth params
  o.synth_param_ids = {"pos", "gain", "speed", "pan",
    "pitch", "spread", "size", "density",
    "lp_freq", "hp_freq", "envscale", "algo_num",
    "jitter", "send", "speed", "pan_rand",
    "pitch_rand", "spread", "size", "density_mod_amt",
    "lp_q",  "hp_q", "envscale", "algo_param"}

  o.curr_synth_param = 1
  o.voice_position = -1
  o.voice_level = 0

  -- snapshots
  o.param_snapshots = {}
  o.num_snapshots = 16

  -- play algorithms
  o.algo_names = {"linear playback", "freeze", "subloop fw", "subloop bf", "subloop glitch", "tides", "midikeys", "off"}

  return o
end

-- get_sample_name
--
-- UI helper function
--
function voice_grainloop:get_sample_name()
  -- strips the path and extension from filenames
  -- if filename is over 15 chars, returns a folded filename
  local long_name = string.match(params:get(self.param_prefix.."sample"), "[^/]*$")
  local short_name = string.match(long_name, "(.+)%..+$")
  if short_name == nil then short_name = "(load file)" end
  if string.len(short_name) >= 15 then
    return string.sub(short_name, 1, 4) .. '...' .. string.sub(short_name, -4)
  else
    return short_name
  end
end

-- init
--
-- main script init
--

function voice_grainloop:init()

  -- engine param polls
  local phase_poll = poll.set('phase_'..self.v, function(pos) self.voice_position = pos end)
  phase_poll.time = 0.025
  phase_poll:start()

  local level_poll = poll.set('level_'..self.v , function(lvl) self.voice_level = lvl end)
  level_poll.time = 0.05
  level_poll:start()
end

function voice_grainloop:cleanup()

end

function voice_grainloop:set_live_mode(m)
  if m == true then self.live_mode = true else self.live_mode = false end
  return
end

function voice_grainloop:set_voice_state(m)
  if m == false then
    params:set(self.param_prefix.."play", "1") -- turn off voice
  else
    params:set(self.param_prefix.."play", "2") -- turn on voice
  end
end

function voice_grainloop:live_buffer_reset()
  if self.live_mode == true then
    self.live_buffer_state = 0 -- empty / clear
    params:set(self.param_prefix.."play", "1") -- turn off voice
    engine.live_mode(self.v)
    self.live_buffer_empty = true
  end
end

function voice_grainloop:live_buffer_play()
  if self.live_mode == true then
    self.live_buffer_state = 1
    engine.speed(self.v, params:get(self.param_prefix.."speed") / 100)
    params:set(self.param_prefix.."play", "2") -- turn on voice
  end
end

function voice_grainloop:live_buffer_stop()
  if self.live_mode == true then
    self.live_buffer_state = 0
    params:set(self.param_prefix.."play", "1") -- turn off voice
    engine.speed(self.v, 0.0)
    params:set(self.param_prefix.."pos", self.voice_position)
  end
end


function voice_grainloop:live_buffer_record_arm()
  if self.live_mode == true then
    self.live_buffer_state = 2
  end
end

function voice_grainloop:live_buffer_record_start()
  if self.live_mode == true then
    engine.live_buffer_record_start(self.v, 30) -- start recording 15ms fadein/out
    self.live_buffer_state = 3
  end
end

function voice_grainloop:live_buffer_record_stop()
  if self.live_mode == true then
     engine.live_buffer_record_end(self.v)
     params:set(self.param_prefix.."speed", 100)
     engine.speed(self.v, 1.0)
     params:set(self.param_prefix.."pitch", 0)
     params:set(self.param_prefix.."gain", 1.0)
     params:set(self.param_prefix.."send", 0.0)
     self.live_buffer_state = 1 -- return to play state
     self.live_buffer_empty = false
  end
end

function voice_grainloop:get_param_id(i)
  return(self.synth_param_ids[i])

end

--
-- get a param value
--
function voice_grainloop:get_param(id)
  return(params:get(self.param_prefix..id))
end

--
-- update param w/ delta value
--
function voice_grainloop:param_delta(id, d)
  params:delta(self.param_prefix..id, d)
end

--
-- hard set a param value
--
function voice_grainloop:set_param(id, v)
  params:set(self.param_prefix..id, v)
end

-- write all params to a snapshot
function voice_grainloop:store_curr_param_to_snapshot(s)
  self.param_snapshots[s][self.curr_synth_param] = params:get(self.param_prefix..self.synth_param_ids[self.curr_synth_param])
end

-- recall a snapshot of params
function voice_grainloop:recall_snapshot(s)
  for p=1, #self.synth_param_ids do
    if self.param_snapshots[s][p] ~= nil then
      params:set(self.param_prefix..self.synth_param_ids[p], self.param_snapshots[s][p])
    end
  end
end

-- returns true if a param is snapped
function voice_grainloop:has_stored_param(s, p)
  r = false
  if self.param_snapshots[s][p] ~= nil then r = true end
  return r
end

-- init snapshots
function voice_grainloop:init_snapshots()
  self.param_snapshots = {}
  for s=1, self.num_snapshots do
    self.param_snapshots[s] = {}
    for p=1, #self.synth_param_ids do
        self.param_snapshots[s][p] = nil
    end
  end
end

-- add_params
--
-- add this voice's params to paramset
--
function voice_grainloop:add_params()
  params:add_group("grainloop"..self.voice_num.." SETTINGS", 22)

  params:add_file(self.param_prefix.."sample", "sample")
  params:set_action(self.param_prefix.."sample", function(file) engine.read(self.v, file) end)

  params:add_option(self.param_prefix.."play", "play", {"off","on"}, 1)
  params:set_action(self.param_prefix.."play", function(x) engine.gate(self.v, x-1) end)

  params:add_control(self.param_prefix.."gain", "gain", controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action(self.param_prefix.."gain", function(value) engine.gain(self.v, value) end)

  params:add_control(self.param_prefix.."pos", "pos", controlspec.new(0, 1, "lin", 0.001, 0, "", 0.001, true))
  params:set_action(self.param_prefix.."pos", function(value) engine.pos(self.v, value) end)

  params:add_taper(self.param_prefix.."speed", "speed", -300, 300, 100, 0, "%")
  params:set_action(self.param_prefix.."speed", function(value) engine.speed(self.v, value / 100) end)

  params:add_taper(self.param_prefix.."jitter", "jitter", 0, 5000, 0, 10, "ms")
  params:set_action(self.param_prefix.."jitter", function(value) engine.jitter(self.v, value / 1000) end)

  params:add_taper(self.param_prefix.."size", "size", 1, 500, 100, 5, "ms")
  params:set_action(self.param_prefix.."size", function(value) engine.size(self.v, value / 1000) end)

  params:add_taper(self.param_prefix.."density", "density", 0, 512, 20, 6, "hz")
  params:set_action(self.param_prefix.."density", function(value) engine.density(self.v, value) end)

  params:add_control(self.param_prefix.."density_mod_amt", "density mod amt", controlspec.new(0, 1, "lin", 0, 0))
  params:set_action(self.param_prefix.."density_mod_amt", function(value) engine.density_mod_amt(self.v, value) end)

  params:add_control(self.param_prefix.."pitch", "pitch", controlspec.new(-36.00, 36.00, "lin", 0.01, 0, "st", 0.001, false))
  params:set_action(self.param_prefix.."pitch", function(value) engine.pitch(self.v, math.pow(0.5, -value / 12)) end)

  params:add_control(self.param_prefix.."pitch_rand", "pitch_rand", controlspec.new(0.0, 1.00, "lin", 0.001, 0))
  params:set_action(self.param_prefix.."pitch_rand", function(value) engine.pitch_rand(self.v, value) end)

  params:add_control(self.param_prefix.."spread", "spread", controlspec.new(0.0, 1.00, "lin", 0.001, 0))
  params:set_action(self.param_prefix.."spread", function(value) engine.spread(self.v, value) end)

  params:add_control(self.param_prefix.."pan", "pan", controlspec.new(-1.00, 1.00, "lin", 0.01, 0))
  params:set_action(self.param_prefix.."pan", function(value) engine.pan(self.v, value) end)

  params:add_control(self.param_prefix.."pan_rand", "pan rand", controlspec.new(0.0, 1.00, "lin", 0.001, 0))
  params:set_action(self.param_prefix.."pan_rand", function(value) engine.pan_rand(self.v, value) end)

  params:add_control(self.param_prefix.."lp_freq", "lpf cutoff", controlspec.new(0.0, 1.0, "lin", 0.01, 1))
  params:set_action(self.param_prefix.."lp_freq", function(value) engine.lp_freq(self.v, value) end)

  params:add_control(self.param_prefix.."lp_q", "lpf q", controlspec.new(0.00, 1.00, "lin", 0.01, 1))
  params:set_action(self.param_prefix.."lp_q", function(value) engine.lp_q(self.v, value) end)

  params:add_control(self.param_prefix.."hp_freq", "hpf cutoff", controlspec.new(0.0, 1.0, "lin", 0.01, 0))
  params:set_action(self.param_prefix.."hp_freq", function(value) engine.hp_freq(self.v, value) end)

  params:add_control(self.param_prefix.."hp_q", "hpf q", controlspec.new(0.00, 1.00, "lin", 0.01, 1))
  params:set_action(self.param_prefix.."hp_q", function(value) engine.hp_q(self.v, value) end)

  params:add_control(self.param_prefix.."send", "delay send", controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action(self.param_prefix.."send", function(value) engine.send(self.v, value) end)

  params:add_control(self.param_prefix.."envscale", "envelope time", controlspec.new(0.0, 60.0, "lin", 0.01, 0.0))
  params:set_action(self.param_prefix.."envscale", function(value) engine.envscale(self.v, value) end)

  params:add_number(self.param_prefix.."algo_num", "algo num", 1, #self.algo_names, 1, 1)
  params:set_action(self.param_prefix.."algo_num", function(value) self.curr_algo = value end)

  params:add_control(self.param_prefix.."algo_param", "algo mod", controlspec.new(0.0, 1.00, "lin", 0.0001, 0))
  params:set_action(self.param_prefix.."algo_param", function(value) self.algo_param = value end)
end


return voice_grainloop
