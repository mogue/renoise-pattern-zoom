--[[============================================================================
main.lua
============================================================================]]--

local multiplier = 2

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function run()
  local rs = renoise.song()
  local error_log = ""

  local tpl = rs.transport.tpl

  -- Set LPB
  local new_lpb = rs.transport.lpb * multiplier
  if (new_lpb > 256) then
    renoise.app():show_error("ERROR: Could not set lines per beat for the song (value too large: " .. new_lpb .. " max: 256).")
    return false
  else
    rs.transport.lpb = new_lpb
  end

  -- Beat sync
  for _, instrument in ipairs(rs.instruments) do
    for _, sample in ipairs(instrument.samples) do
      if (sample.beat_sync_enabled == true) then
        local new_sync = sample.beat_sync_lines * multiplier
	if (new_sync > 512) then
          error_log = error_log .. "ERROR: Could not resync beat sync for sample '" .. sample.name .. "' (value too large: " .. new_sync .. " max: 512).\n"
	else
	  sample.beat_sync_lines = sample.beat_sync_lines * multiplier
        end
      end
    end
  end

  -- Pattern Editor
  for patternIdx, pattern in ipairs(rs.patterns) do
   local old_number_of_lines = pattern.number_of_lines

   -- Pattern size
   local new_nol = pattern.number_of_lines * multiplier
   if (new_nol > 512) then
     error_log = error_log .. "ERROR: Could not resize pattern '" .. patternIdx .. "' (value too large: " .. new_nol .. " max: 512).\n"
     break
   else
     pattern.number_of_lines = new_nol
   end

   -- Lines
   for _, track in ipairs(pattern.tracks) do
    for line_index = old_number_of_lines, 1, -1 do
      local src_line = track:line(line_index)

      if (not src_line.is_empty) then
        local dest_line_index = line_index * multiplier - (multiplier -1)
       
        -- Effect commands
	for effect_column_index, effect_column in ipairs (src_line.effect_columns) do

          local nr_str = effect_column.number_string

          -- Slides, Glides and Fades
          if (nr_str == '0U') or (nr_str == '0D') or (nr_str == '0G') or (nr_str == '0I') or (nr_str == '0O') then
            local amt = effect_column.amount_value
            local excess = amt % multiplier
            amt = math.floor(amt / multiplier)
            effect_column.amount_value = amt + excess

            for add_line_index = dest_line_index, dest_line_index + (multiplier-1), 1 do
              track:line(add_line_index):effect_column(effect_column_index):copy_from(effect_column)
            end            
          end

          -- Cut after Ticks
          if (nr_str == '0C') then
            local x = math.floor(effect_column.amount_value / 16) * 16
            local ticks = (effect_column.amount_value % 16) * multiplier
            effect_column.amount_value = x + ticks        

            if (ticks > tpl) then
              local delay = math.floor(ticks / tpl)
              ticks = ticks % tpl

              effect_column.amount_value = x + ticks
              track:line(dest_line_index + delay):effect_column(effect_column_index):copy_from(effect_column)
              effect_column:clear()
            end
          end

          -- Lines Per Beat and Pause Pattern
          if (nr_str == 'ZL') or (nr_str == 'ZD') then
            effect_column.amount_value = effect_column.amount_value * multiplier
          end

          -- Ticks Per Line
          if (nr_str == 'ZK') then
            tpl = effect_column.amount_value
          end

          -- Delay by Ticks
          if (nr_str == '0Q') then
            local amt = effect_column.amount_value * multiplier
            local mov = 0
            if (amt > tpl) then
               mov = math.floor(amt/tpl)
               amt = amt%tpl
            end
            effect_column.amount_value = amt
            dest_line_index = dest_line_index + mov
          end

        end
        
        local dest_line = src_line

        if (dest_line_index ~= line_index) then
          dest_line = track:line(dest_line_index)
          dest_line:copy_from(src_line)
          src_line:clear()
        end    
   
	-- Note columns 
        for note_column_index, note_column in ipairs (dest_line.note_columns) do
          local mov = 0

          -- Volume column
          local vol_val = note_column.volume_value
          if (vol_val ~= 255 and vol_val >= 0x80) then
            local number_value = math.floor(vol_val/256)
            local amount_value = (vol_val % 256)

            -- IX & OX
            if (number_value == 0x12) or (number_value == 0x18) then
              local step = math.floor(amount_value / multiplier)
              local excess = amount_value % multiplier
              note_column.volume_value = (number_value * 256) + step + excess

              if (step > 0) then
                for add_line_index = dest_line_index, dest_line_index + (multiplier - 2), 1 do
                  track:line(add_line_index + 1):note_column(note_column_index).volume_value = (number_value * 256) + step
                end
              end
            end

            -- QX
            if (number_value == 0x1A) then
              local amt = amount_value * multiplier
              if (amt > tpl) then
                mov = mov + math.floor(amt/tpl)
                amt = amt%tpl
              end
              note_column.volume_value = 0x1A00 + amt  
            end

            -- RX
            if (number_value == 0x1B) then

            end

            -- CX
            if (number_value == 0x0C) then
              local ticks = amount_value * multiplier
              note_column.volume_value = 0x0C00 + (ticks % 16)

              if (ticks > tpl) then
                local delay = math.floor(ticks / tpl)
                ticks = ticks % tpl

                track:line(dest_line_index + delay):note_column(note_column_index).volume_value = 0x0C00 + ticks
                note_column.volume_value = 0xFF
              end
            end
          end

          -- Panning column
          local pan_val = note_column.panning_value
          if (pan_val ~= 255 and pan_val >= 0x80) then
            local number_value = math.floor(pan_val/256)
            local amount_value = (pan_val % 256)

            -- JX & KX
            if (number_value == 0x13) or (number_value == 0x14) then
              local step = math.floor(amount_value / multiplier)
              local excess = amount_value % multiplier
              note_column.panning_value = (number_value * 256) + step + excess

              if (step > 0) then
                for add_line_index = dest_line_index, dest_line_index + (multiplier - 2), 1 do
                  track:line(add_line_index + 1):note_column(note_column_index).panning_value = (number_value * 256) + step
                end
              end
            end

            -- QX
            if (number_value == 0x1A) then
              local amt = amount_value * multiplier
              if (amt > tpl) then
                mov = mov + math.floor(amt / tpl)
                amt = amt % tpl
              end
              note_column.panning_value = 0x1A00 + amt
            end

            -- RX
            if (number_value == 0x1B) then

            end

            -- CX
            if (number_value == 0x0C) then
              local ticks = amount_value * multiplier
              note_column.panning_value = 0x0C00 + (ticks % 16)

              if (ticks > tpl) then
                local delay = math.floor(ticks / tpl)
                ticks = ticks % tpl

                track:line(dest_line_index + delay):note_column(note_column_index).panning_value = 0x0C00 + ticks
                note_column.panning_value = 0xFF
              end
            end
          end

          -- Delay column
          local delay_val = note_column.delay_value
          if (delay_val ~= 0) then
            delay_val = delay_val * multiplier
            note_column.delay_value = delay_val % 256

            if (delay_val >= 256) then
              local delay_lines = math.floor(delay_val / 256)
              local delayed_line = track:line(dest_line_index + delay_lines + mov)
              local dest_note_column = delayed_line:note_column(note_column_index)
              dest_note_column:copy_from(note_column);
              note_column:clear();
            end
          elseif (mov > 0) then
            track:line(dest_line_index + mov):note_column(note_column_index):copy_from(note_column)
            note_column:clear();
          end

        end

      end
    end
    
    -- Automation Points
    for _, automation in ipairs(track.automation) do
      for _, point in ripairs(automation.points) do
        if (point.time > old_number_of_lines) then
	  automation:remove_point_at(point.time)
          error_log = error_log .. "WARNING: Automation point removed as it was out of pattern scope (pattern: " .. patternIdx .. " time: " .. point.time .. ").\n"

        elseif (point.time == old_number_of_lines) then
          automation:add_point_at(point.time * multiplier, point.value)
          automation:remove_point_at(point.time)
	
        elseif (point.time > 1) then
          automation:add_point_at(point.time * multiplier - (multiplier -1), point.value)
          automation:remove_point_at(point.time)
        end
      end
    end

   end

  end

  -- Update error log
  if (error_log ~= "") then
    renoise.app():show_warning(error_log)
  end

end

--------------------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------------------

local function show_gui()
  local vb = renoise.ViewBuilder()

  local content_view = vb:column {
    id = "dialog_content",
    uniform = true,
    margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,

    vb:valuebox { min = 2, max = 100, value=2, notifier = function (number) multiplier = number end },
    vb:button { text = 'kick it!', released = function () run() end }
  }

  local current_dialog = renoise.app():show_custom_dialog(
    "LPBx", content_view)
end


--------------------------------------------------------------------------------
-- menu registration
--------------------------------------------------------------------------------

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:LPBx",
  invoke = show_gui
}
