-- drone science
---multi-voice groovebox

engine.name = "grainloops"
voice_grainloop = include("grainloop/lib/voice_grainloop")

-- input: arc required
local a = arc.connect(1)
local g = grid.connect()
local ui_metro = metro.init()
local flash_metro = metro.init()

-- the looper voices
local num_voices = 3
local voices = {}
local snap_write = {false, false, false} -- one per voice
local snap_curr = {1, 1, 1}
local curr_voice

-- ui stuff
local param_scaling = 0.1
local g1_15 = 0
local g1_16 = 0
local a4_state = 0 -- volume, rate, verb
local flash_state = 0
local ui_flash_grid = 0
local ui_flash_counter = 0 -- thirty refreshes in a second, the refresh interval
local sc_transport = 0
local sc_level = 1
local sc_rev_level = 0
local sc_rate = 1
local curr_file = 1
local filepath = _path.dust.."audio/yoyu2/"
local filenames = {"nepalese bowls 1.1 2x.wav",
      "mori closeup short 4x.wav",
      "mmad/dpa ocean roar.wav",
      "pb mid beach short 4x.wav",
      "mmad/birds1 short.wav",
      "nepalese bowls rev 2.2.wav",
      "nepalese bowls hit.wav",
      "nepalese bowls 2.1.wav",
      "mmad/broken seagulls and waves.wav",
      "mmad/child laughing.wav",
      "mmad/gentle wave loop.wav",
      "mmad/wind chimes.wav",
      "mmad/wind chimes up.wav",
      "mmad/mori splash 1.wav",
      "mmad/mori splash 2.wav",
      "mmad/hospital.wav"}

-- init
--
-- maint script init
--

function init()

  -- init the engine (load wavetables, boot lfos)

  engine.create_grainloop(3)

  -- allocate the voices
  for i = 1, num_voices do
    voices[i] = voice_grainloop:new(i)
  end

  -- boot up each voice
  for i = 1, num_voices do
    voices[i]:init()
  end

  curr_voice = 1

  -- setup the params
  for i = 1, num_voices do
    voices[i]:add_params()
    voices[i]:init_snapshots()
  end

  -- encoder1 sensitivity - make voice selection feel natural
  norns.enc.sens(1,3)

  -- hardware updates @ 30hz refresh
  ui_metro = metro.init()
  ui_metro.time = 0.03
  ui_metro.event = hardware_refresh
  ui_metro:start()

  -- flashing ui leds 500ms
  flash_metro = metro.init()
  flash_metro.time = 0.5
  flash_metro.event = gui_flash
  flash_metro:start()

  -- register grid key grid key handler
  g.key = function(x, y, z)
    grid_key(x, y, z)
  end
  
  -- enable softcut voices for foley sound playback
  softcut.enable(1, 1)
  softcut.enable(2, 1)
  softcut.buffer(1, 1)
  softcut.buffer(2, 2)
  softcut.loop(1, 1)
  softcut.loop(2, 1)
  softcut.pan(1, -1)
  softcut.pan(2, 1) 
  softcut.rate_slew_time(1, 0.03)
  softcut.rate_slew_time(2, 0.03)
  softcut.level_slew_time(1, 0.03)
  softcut.level_slew_time(2, 0.03)
end

-- cleanup
--
-- script cleanup
--

function cleanup()

  -- dealloc and cleanup all voices
  for i = 1, num_voices do
    voices[i]:cleanup()
  end
end

-- key
--
-- process norns keys
--

function key(n, z)

  redraw()

end

-- enc
--
-- process norns encoders
--

function enc(n, d)

end

-- redraw
--
-- handle norns screen updates
--
function redraw()

  screen.clear()

  --local line_width = math.floor((128 + (num_voices - 1 ) * 2) / num_voices)
  local line_width = math.floor(128 / num_voices)

  -- draw current voice indicator
  for i=1, num_voices do
    if i == curr_voice then
      screen.level(15)
      screen.line_width(4)
      yoffset = 0
    else
      screen.level(2)
      screen.line_width(1)
      yoffset = 1
    end
    screen.move( (i - 1) * line_width + 1, 1 + yoffset)
    screen.line( (i * line_width), 1 + yoffset)

    screen.stroke()
  end

  -- voice params
  for i=1, num_voices do
    v = voices[i]
    y_offset = (i - 1) * 10

    if i == curr_voice then
      screen.level(15)
    else
      screen.level(2)
    end

    -- show on/off indicator
    screen.move(1, y_offset + 25)
    if v:get_param("play") == 1 then screen.text("-") else screen.text("o") end

    -- show transport indicator
    screen.move(8, y_offset + 25)
    if voices[i].live_mode == false then
      screen.text("f")
    else
      if v.live_buffer_state == 0 then
        screen.text("-")
      elseif v.live_buffer_state == 1 then
        screen.text("l")
      elseif v.live_buffer_state == 2 then
        screen.text("A")
      elseif v.live_buffer_state == 3 then
        screen.text("R")
      end
    end
    
    -- show param label and value
    screen.move(16, y_offset + 25)
    p = v:get_param_id(v.curr_synth_param)
    screen.text(p)
    screen.move(128, y_offset + 25)
    screen.text_right(string.format("%.3f", v:get_param(p)))
  end
  
  -- show curr filename
  screen.move(16, 55)
  screen.level(15)
  screen.text(filenames[curr_file])

  screen.update()
end

-- a.delta
--
-- process arc encoder input
--
function a.delta(n, d)
  if n >= 1 and n <= 3 then
    v = voices[n]
    v:param_delta(v:get_param_id(v.curr_synth_param), d * param_scaling)
  end
  
  if n == 4 then 
    
    if a4_state == 0 then -- volume
      sc_level = util.clamp(sc_level + d/1000, 0, 1)
      softcut.level(1, sc_level)
      softcut.level(2, sc_level)
    elseif a4_state == 1 then -- rate      
      sc_rate = util.clamp(sc_rate + d/3000, 0, 2)
      softcut.rate(1, sc_rate)
      softcut.rate(2, sc_rate)
    elseif a4_state == 2 then -- verb
      sc_rev_level = util.clamp(sc_rev_level + d/1000, 0, 1)
      audio.level_cut_rev(sc_rev_level)
    end
  end
  
  redraw()
end

-- grid_key
--
-- process grid keys
--

function grid_key(x, y, z)
  -- process voice select keys
  if y==8 and (x>=13 and x<=16) then
    curr_voice = util.clamp(x-12, 1, num_voices)
  end

  -- process parameter scaling keys (15,1) (16,1)
  if x == 16 and y == 1 then
    if z == 1 then param_scaling = 0.01 else param_scaling = 0.1 end
    g1_16 = z
  end
  if x == 15 and y == 1 then
    if z == 1 then param_scaling = 1.0 else param_scaling = 0.1 end
    g1_15 = z
  end
  if g1_15 == 1 and g1_16 == 1 then
    v = voices[curr_voice]
    v:set_param(v:get_param_id(v.curr_synth_param), 0.0)
  end

  -- process parameter select keys (1-12, 1) (1-12, 2)
  if (z == 1) and (y == 1) and (x >= 1) and (x <= 12) then
    voices[curr_voice].curr_synth_param = x
  end
  if (z == 1) and (y == 2) and (x >= 1) and (x <= 12) then
    voices[curr_voice].curr_synth_param = x + 12
  end

  -- process buttons for each machine
  if y >= 3 and y <= 8 and x<= 12 then
    vnum = math.floor((x-1)/4) + 1

    if vnum<=num_voices then
      v = voices[vnum]
      xx = x - (vnum-1)*4

      -- handle audio live audio transport
      if z==1 and v.live_mode == true then
        if xx==1 and y==7 then -- play/stop
          if v.live_buffer_state == 0 then
            v:live_buffer_play()
          elseif v.live_buffer_state == 1 or v.live_buffer_state == 2 then
            v:live_buffer_stop()
          end
        end

        if xx==2 and y==7 then -- play/rec
          if v.live_buffer_state == 0 or v.live_buffer_state == 1 then -- arm the buffer for record
            v:live_buffer_record_arm()
          elseif v.live_buffer_state == 2 then -- start recording
            v:live_buffer_record_start()
          elseif v.live_buffer_state == 3 then -- stop and keep the recording
            v:live_buffer_record_stop()
          end
        end
        
        -- live mode reset buffer + snapshots
        if v.live_buffer_state == 0 and xx==1 and y==8 then -- reset live buffer
          v:live_buffer_reset()
          v:init_snapshots()
          flash_grid()
        end
      end -- live audio transport

      -- handle pattern transport

      -- handle live/record buffer toggle
      if z==1 and xx==3 and y==8 then
        if v.live_mode == true then v:set_live_mode(false) else v:set_live_mode(true) end
      end
      -- handle voice on/off toggle
      if z==1 and xx==4 and y==8 then
        if v:get_param("play") == 2 then v:set_voice_state(false) else v:set_voice_state(true) end
      end

      -- handle snapshot function key for saving and recall
      if xx== 2 and y==8 then
        if z==1 then snap_write[vnum] = true else snap_write[vnum] = false end
      end

      -- handle snapshots, select and saves
      if z==1 and xx>=1 and xx<=4 and y>=3 and y<=6 then
        n = grid2index(xx,y-2)
        if snap_write[vnum] == true then
          store_snapshot(vnum, n)
        else
          select_snapshot(vnum, n)
        end
      end
    end -- for: num voices
  end -- machine buttons
  
  -- handle sc tape file select buttons
  if z==1 and x>=13 and x<=16 and y>=3 and y<=6 then
    if sc_transport==0 then -- playback is stopped, allow selection of a file
      n = grid2index(x-12, y-2)
      curr_file = n
      
      -- load the file and setup sc
      softcut.buffer_clear()
      softcut.buffer_read_stereo(filepath..filenames[curr_file], 0, 0, -1)
      dur = get_file_length(filepath..filenames[curr_file])
      softcut.loop_start(1, 0)
      softcut.loop_start(2, 0)
      softcut.loop_end(1, dur)
      softcut.loop_end(2, dur)
      softcut.level(1, sc_level)
      softcut.level(2, sc_level)
      audio.level_cut_rev(sc_rev_level)
      softcut.voice_sync(1, 2, 0)
      --softcut.fade_time(1, 3)
      --softcut.fade_time(2, 3)
      sc_rate = 1
      sc_rev_level = 0
    end
  end

  -- stop button
  if z==1 and x==13 and y==7 then 
    if sc_transport == 1 then --stop
      sc_transport = 0 
      softcut.play(1,0)
      softcut.play(2,0)
    end
  end
  
  -- play button
  if z==1 and x==16 and y==7 then 
    if sc_transport == 0 then --play
      sc_transport = 1
      audio.level_cut_rev(sc_rev_level)
      softcut.level(1, sc_level)
      softcut.level(2, sc_level)
      softcut.rate(1,sc_rate)
      softcut.rate(2,sc_rate)
      softcut.position(1, 0)
      softcut.position(2, 0)
      softcut.voice_sync(1, 2, 0)
      softcut.play(1,1)
      softcut.play(2,1)
      softcut.voice_sync(1, 2, 0)
    end 
  end
  
  -- rate button
  if x==14 and y==7 and z == 1 then 
    if a4_state == 1 then a4_state = 0 else a4_state = 1 end 
  end

  -- verb button
  if x==15 and y==7 and z == 1 then 
    if a4_state == 2 then a4_state = 0 else a4_state = 2 end 
  end

  redraw()
end

-- convert a 4x4 grid coord to an index number
function grid2index(x, y)
  s = (y-1)*4 + x
  return(s)
end

-- convert an index into a 4x4 grid coord  
function index2grid(i)
  local x
  local y
  x = math.fmod((i-1), 4) + 1
  y = math.floor((i-1) / 4) + 1 
  return x, y
end

-- write all params to selected snapshot
function store_snapshot(v, n)
  flash_grid()
  voices[v]:store_curr_param_to_snapshot(n)

end

-- select this snapshot as current
function select_snapshot(v, n)
  snap_curr[v] = n
  voices[v]:recall_snapshot(n)
end



--  ui flash
--
--- process arc and grid refresh
--
function gui_flash()
  if flash_state == 0 then flash_state = 1 else flash_state = 0 end
  if flash_grid == true then flash_grid = false end
end


--  hardware_refresh
--
--- process arc and grid refresh
--
function hardware_refresh()
  arc_refresh()
  grid_refresh()

  if ui_flash_grid > 0 then
    elapsed_time = util.time() - ui_flash_grid
    ui_flash_counter = ui_flash_counter + 1
    if elapsed_time > 1 then
      ui_flash_grid = 0
      ui_flash_counter = 0
    end
  end
end

--  flash_grid
--
--- make the grid flash once to indicate an event
--
function flash_grid()
  ui_flash_grid = util.time()
  ui_flash_counter = 0
end

--  arc refresh
--
--- process arc refresh
--
function arc_refresh()
  a:all(0)

  for i = 1, num_voices do
    val = voices[i].voice_position * 2 * math.pi
    a:segment(i, val - 0.1, val + 0.1, 15)
  end
  
  if a4_state == 1 then
    val = math.floor(sc_rate * 32) + 1
    a:led(4, val, 15)
  elseif a4_state == 2 then  
    val = util.clamp(sc_rev_level,0, 0.999) * 2 * math.pi
    a:segment(4, 0, val, 15)
  elseif a4_state == 0 then 
    val = util.clamp(sc_level,0, 0.999) * 2 * math.pi
    a:segment(4, 0, val, 15)
  end 
  a:refresh()
end

--  grid refresh
--
--- process grid refresh
--
function grid_refresh()
  g:all(0)

  -- current voice indicator
  g:led(12+curr_voice, 8, 15)

  -- parameter edit keys
  v = voices[curr_voice]
  s = snap_curr[curr_voice]
  c = v.curr_synth_param
  for p=1, #v.synth_param_ids do
    y = 1 + math.floor((p-1)/12)
    x = 1 + math.fmod((p-1),12)
    if c == p then
      g:led(x, y, 15)
    else
      if v:has_stored_param(s,p) == true then
        g:led(x, y, 4)
      end
    end
  end

  -- param scaling keys
  if g1_15 == 0 then g:led(15, 1, 4) else g:led(15, 1, 15) end
  if g1_16 == 0 then g:led(16, 1, 4) else g:led(16, 1, 15) end

  -- voice specific keys
  for vnum = 1, num_voices do
    x_offset = (vnum-1)*4
    v = voices[vnum]

    -- fill the snapshot quadrant
    for s = 0, 15 do
      y = math.floor(s/4)+1
      x = math.fmod(s, 4)+1
      if (s+1) == snap_curr[vnum] then
        g:led(x_offset+x, 2+y, 15)
      else
        g:led(x_offset+x, 2+y, 4)
      end
    end

    -- live mode
    if v.live_mode == true then
      g:led(3 + x_offset, 8, 15)
      if v.live_buffer_state == 0 then
        if v.live_buffer_empty == true then
          g:led(1 + x_offset, 7, 4)
        else
          g:led(1 + x_offset, 7, 4*flash_state)
        end
      elseif v.live_buffer_state == 1 then
        g:led(1 + x_offset, 7, 15*flash_state)
      elseif v.live_buffer_state == 2 then
        g:led(2 + x_offset, 7, 4*flash_state)
      elseif v.live_buffer_state == 3 then
        g:led(2 + x_offset, 7, 15*flash_state)
      end
    else
      g:led(3 + x_offset, 8, 4)
    end

    -- on/off
    if v:get_param("play") == 2 then g:led(4 + x_offset, 8, 15) else g:led(4 + x_offset, 8, 4) end

    -- snap write button
    if snap_write[vnum] == true then g:led((vnum-1)*4 + 2, 8, 15) end
  end

  -- little ui trick to confirm an action (like save or reset)
  if ui_flash_grid > 0 then
    c = ui_flash_counter
    if c == 0 or c == 3 or (c > 10 and c < 16) or c == 24 or c == 26 or c == 28 then
      for x=1,16 do
        g:led(x,8,15)
        g:led(x,1,15)
      end
      for y=1,8 do
        g:led(1,y,15)
        g:led(16,y,15)
      end
    end
  end
  
  -- sc file selection  
  x, y = index2grid(curr_file)
  if sc_transport == 0 then 
    g:led(12+x, 2+y, 15*flash_state)
    g:led(16, 7, 4)
  elseif sc_transport == 1 then
    g:led(12+x, 2+y, 15)
    g:led(13, 7, 15)
    g:led(16, 7, 15*flash_state)
  end
  
  -- rate button
  if a4_state == 1 then
    g:led(14, 7, 15)
  end
  
  -- lpf button
  if a4_state == 2 then
    g:led(15, 7, 15)
  end

  g:refresh()
end

function get_file_length(file)
  local ch, samples, samplerate = audio.file_info(file)
  local dur = samples/samplerate
  if util.file_exists(file) == true then
    print("loading file: "..file)
    print("  channels:\t"..ch)
    print("  samples:\t"..samples)
    print("  sample rate:\t"..samplerate.."hz")
    print("  duration:\t"..dur.." sec")
  else print "read_wav(): file not found" end
  return dur
end

