-- ============================================================================
-- AUTO CITY BLOCK 1.3.3: DIRECT DRAW GUARANTEED EDITION
-- ============================================================================

local function safe_get(obj, key, default)
    if not obj then return default end
    local ok, val = pcall(function() return obj[key] end)
    if ok and val ~= nil then return val end
    return default
end

local function safe_set(obj, key, val)
    if not obj then return false end
    local ok = pcall(function() obj[key] = val end)
    return ok
end

local function safe_call(obj, method, arg1, default)
    if not obj then return default end
    local ok, val = pcall(function()
        local fn = obj[method]
        if type(fn) == "function" then
            if arg1 ~= nil then return fn(arg1) else return fn() end
        end
        return nil
    end)
    if ok and val ~= nil then return val end
    return default
end

local function safe_add(parent, spec)
    if not parent then return nil end
    local ok, el = pcall(function() return parent.add(spec) end)
    if ok and el then return el end
    local fallback = {}
    for k, v in pairs(spec) do if k ~= "style" then fallback[k] = v end end
    local ok2, el2 = pcall(function() return parent.add(fallback) end)
    if ok2 and el2 then return el2 end
    return nil
end

local function find_gui_element(parent, target_name)
    if not parent or not safe_get(parent, "valid", false) then return nil end
    if safe_get(parent, "name", "") == target_name then return parent end
    for _, child in pairs(safe_get(parent, "children", {})) do
        local found = find_gui_element(child, target_name)
        if found then return found end
    end
    return nil
end

local PLANET_RAW = {
    nauvis = {["iron-ore"]=true,["copper-ore"]=true,["coal"]=true,["stone"]=true,["uranium-ore"]=true,["crude-oil"]=true,["water"]=true,["steam"]=true,["wood"]=true},
    vulcanus = {["lava"]=true,["calcite"]=true,["coal"]=true,["tungsten-ore"]=true,["sulfuric-acid"]=true,["stone"]=true},
    fulgora = {["scrap"]=true,["heavy-oil"]=true,["water"]=true},
    gleba = {["yumako"]=true,["jellynut"]=true,["stone"]=true,["water"]=true,["spoilage"]=true},
    aquilo = {["lithium-brine"]=true,["fluorine"]=true,["ammoniacal-solution"]=true,["crude-oil"]=true,["water"]=true,["iron-ore"]=true,["copper-ore"]=true}
}

local PLANETS = {
    {id = "nauvis", caption = "Наувис (Nauvis)"},
    {id = "vulcanus", caption = "Вулкан (Vulcanus)"},
    {id = "fulgora", caption = "Фульгора (Fulgora)"},
    {id = "gleba", caption = "Глеба (Gleba)"},
    {id = "aquilo", caption = "Аквило (Aquilo)"}
}

local QUALITIES = {
    {name = "normal", caption = "Обычное (Normal)", mult = 1.0},
    {name = "uncommon", caption = "Необычное (+30%)", mult = 1.3},
    {name = "rare", caption = "Редкое (+60%)", mult = 1.6},
    {name = "epic", caption = "Эпическое (+90%)", mult = 1.9},
    {name = "legendary", caption = "Легендарное (+150%)", mult = 2.5}
}

local MODULE_MODES = {
    {id = "none", caption = "Без модулей", prod = 0.0, speed = 0.0},
    {id = "prod3", caption = "4x Продуктивность 3 (+40% прод)", prod = 0.40, speed = -0.60},
    {id = "speed3", caption = "4x Скорость 3 (+200% ск)", prod = 0.0, speed = 2.00},
    {id = "qual3", caption = "4x Качество 3", prod = 0.0, speed = -0.20}
}

local CATEGORY_MACHINE_PRIORITY = {
    ["crafting"] = {"assembling-machine-3", "assembling-machine-2"},
    ["basic-crafting"] = {"assembling-machine-3", "assembling-machine-2"},
    ["advanced-crafting"] = {"assembling-machine-3", "assembling-machine-2"},
    ["crafting-with-fluid"] = {"assembling-machine-3", "assembling-machine-2"},
    ["electronics"] = {"electromagnetic-plant", "assembling-machine-3"},
    ["pressing"] = {"assembling-machine-3", "assembling-machine-2"},
    ["metallurgy"] = {"foundry", "electric-furnace"},
    ["smelting"] = {"foundry", "electric-furnace", "steel-furnace"},
    ["chemistry"] = {"cryogenic-plant", "chemical-plant"},
    ["oil-processing"] = {"oil-refinery"},
    ["organic"] = {"biochamber", "assembling-machine-3"}
}

local MACHINE_SPECS = {
    ["assembling-machine-1"] = {size = 3, speed = 0.5, prod = 0.0},
    ["assembling-machine-2"] = {size = 3, speed = 0.75, prod = 0.0},
    ["assembling-machine-3"] = {size = 3, speed = 1.25, prod = 0.0},
    ["electric-furnace"]     = {size = 3, speed = 2.0, prod = 0.0},
    ["steel-furnace"]        = {size = 2, speed = 2.0, prod = 0.0},
    ["chemical-plant"]       = {size = 3, speed = 1.0, prod = 0.0},
    ["biochamber"]           = {size = 3, speed = 2.0, prod = 0.5},
    ["electromagnetic-plant"]= {size = 4, speed = 2.0, prod = 0.5},
    ["foundry"]              = {size = 4, speed = 4.0, prod = 0.5},
    ["cryogenic-plant"]      = {size = 5, speed = 2.0, prod = 0.0},
    ["oil-refinery"]         = {size = 5, speed = 1.0, prod = 0.0}
}

local DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST = 0, 4, 8, 12

local function create_top_button(player)
    if not player or not safe_get(player, "valid", false) then return end
    local screen = safe_get(player.gui, "screen", nil)
    if screen and not safe_get(screen, "cb_top_toggle_btn", nil) then
        safe_add(screen, {type = "button", name = "cb_top_toggle_btn", caption = "⚙️ AutoCityBlock 1.3.3", style = "button"})
    end
end

script.on_init(function()
    storage.player_state = {}
    for _, p in pairs(game.players) do create_top_button(p) end
end)

script.on_configuration_changed(function()
    if not storage.player_state then storage.player_state = {} end
    for _, p in pairs(game.players) do create_top_button(p) end
end)

script.on_event(defines.events.on_player_created, function(event)
    create_top_button(game.get_player(event.player_index))
end)

local function get_state(player_index)
    if not storage.player_state then storage.player_state = {} end
    if not storage.player_state[player_index] then
        storage.player_state[player_index] = {
            item = "battery", rate = 120, quality_index = 1,
            planet_index = 1, module_index = 2, use_beacons = true,
            use_world_tech = true, add_stations = true, last_calc = nil
        }
    end
    return storage.player_state[player_index]
end

local function has_entity(name)
    local ents = safe_get(prototypes, "entity", nil)
    return ents and safe_get(ents, name, nil) ~= nil
end

local function is_fluid(name)
    local fluids = safe_get(prototypes, "fluid", nil)
    return fluids and safe_get(fluids, name, nil) ~= nil
end

local function get_belt_set()
    if has_entity("turbo-transport-belt") then return "turbo-transport-belt", "turbo-underground-belt", "turbo-splitter" end
    return "express-transport-belt", "express-underground-belt", "express-splitter"
end

local function get_inserter_name()
    if has_entity("stack-inserter") then return "stack-inserter" end
    if has_entity("bulk-inserter") then return "bulk-inserter" end
    return "fast-inserter"
end

local function get_machine_info(machine_name)
    local spec = MACHINE_SPECS[machine_name] or {size = 3, speed = 1.0, prod = 0.0}
    local ent_proto = has_entity(machine_name) and prototypes.entity[machine_name] or nil
    local api_speed = safe_call(ent_proto, "get_crafting_speed", "normal", nil) or safe_call(ent_proto, "get_crafting_speed", nil, nil) or safe_get(ent_proto, "crafting_speed", nil)
    return tonumber(api_speed) or spec.speed, spec.size, spec.prod
end

local function get_best_unlocked_machine(force, category, use_world_tech)
    local candidates = CATEGORY_MACHINE_PRIORITY[category] or {"assembling-machine-3", "assembling-machine-2"}
    local f_recipes = safe_get(force, "recipes", {})
    for _, m_name in ipairs(candidates) do
        if has_entity(m_name) then
            if not use_world_tech then return m_name end
            local rec = safe_get(f_recipes, m_name, nil)
            if not rec or safe_get(rec, "enabled", true) then return m_name end
        end
    end
    return "assembling-machine-2"
end

local function find_recipe_for_item(force, item_name, use_world_tech, planet_id)
    local f_recipes = safe_get(force, "recipes", {})
    local p_recipes = safe_get(prototypes, "recipe", {})
    local direct_proto = safe_get(p_recipes, item_name, nil)
    if direct_proto then return direct_proto, safe_get(f_recipes, item_name, nil) end

    for name, proto in pairs(p_recipes) do
        for _, product in pairs(safe_get(proto, "products", {})) do
            if safe_get(product, "name", nil) == item_name then
                return proto, safe_get(f_recipes, name, nil)
            end
        end
    end
    return nil, nil
end

local function calculate_chain(force, item_name, rate_per_sec, state, chain_steps, raw_totals, depth)
    depth = depth or 0
    local raw_map = PLANET_RAW[PLANETS[state.planet_index].id] or PLANET_RAW.nauvis
    if depth > 10 or raw_map[item_name] then
        raw_totals[item_name] = (raw_totals[item_name] or 0) + rate_per_sec
        return
    end

    local proto, f_recipe = find_recipe_for_item(force, item_name, state.use_world_tech, PLANETS[state.planet_index].id)
    if not proto then
        raw_totals[item_name] = (raw_totals[item_name] or 0) + rate_per_sec
        return
    end

    local r_name = safe_get(proto, "name", item_name)
    local base_output = 1
    for _, p in pairs(safe_get(proto, "products", {})) do
        if safe_get(p, "name", nil) == item_name then
            local amt = safe_get(p, "amount", nil) or ((safe_get(p, "amount_min", 1) + safe_get(p, "amount_max", 1)) / 2)
            base_output = amt * safe_get(p, "probability", 1)
            break
        end
    end

    local machine_name = get_best_unlocked_machine(force, safe_get(proto, "category", "crafting"), state.use_world_tech)
    local base_speed, m_size, innate_prod = get_machine_info(machine_name)

    local prod_bonus = innate_prod + (state.use_world_tech and f_recipe and (tonumber(safe_get(f_recipe, "productivity_bonus", 0)) or 0) or 0)
    prod_bonus = prod_bonus + (MODULE_MODES[state.module_index] or MODULE_MODES[1]).prod

    local speed_mult = math.max(0.25, 1.0 + (MODULE_MODES[state.module_index] or MODULE_MODES[1]).speed + (state.use_beacons and 1.5 or 0))
    local final_speed = base_speed * QUALITIES[state.quality_index].mult * speed_mult
    local exact_machines = ((rate_per_sec / math.max(0.01, base_output * (1 + prod_bonus))) * (tonumber(safe_get(proto, "energy", 0.5)) or 0.5)) / final_speed

    local clean_ings = {}
    for _, ing in pairs(safe_get(proto, "ingredients", {})) do
        local iname = safe_get(ing, "name", nil)
        local iamt = tonumber(safe_get(ing, "amount", 1)) or 1
        if iname then table.insert(clean_ings, {name = iname, amount = iamt}) end
    end

    if not chain_steps[r_name] then
        chain_steps[r_name] = {
            recipe_name = r_name, item_name = item_name, machine_name = machine_name,
            machine_size = m_size, exact_machines = 0, output_per_sec = 0,
            crafts_per_sec = 0, prod_bonus = prod_bonus, speed = final_speed,
            ingredients = clean_ings, order = depth
        }
    end

    local step = chain_steps[r_name]
    step.exact_machines = step.exact_machines + exact_machines
    step.output_per_sec = step.output_per_sec + rate_per_sec
    step.crafts_per_sec = step.crafts_per_sec + (rate_per_sec / math.max(0.01, base_output * (1 + prod_bonus)))

    for _, ing in ipairs(clean_ings) do
        calculate_chain(force, ing.name, (rate_per_sec / math.max(0.01, base_output * (1 + prod_bonus))) * ing.amount, state, chain_steps, raw_totals, depth + 1)
    end
end

local function run_calculation(player)
    local state = get_state(player.index)
    if not state.item then state.item = "battery" end
    local chain_steps, raw_totals = {}, {}
    calculate_chain(player.force, state.item, ((state.rate * 1.01) / 60.0), state, chain_steps, raw_totals, 1)

    if next(chain_steps) == nil then
        chain_steps[state.item] = {
            recipe_name = state.item, item_name = state.item, machine_name = "assembling-machine-3",
            machine_size = 3, exact_machines = math.max(1, state.rate / 60), output_per_sec = state.rate / 60,
            crafts_per_sec = state.rate / 60, prod_bonus = 0, speed = 1.25,
            ingredients = {}, order = 1
        }
        raw_totals["iron-plate"] = state.rate / 60
    end

    local sorted_steps = {}
    for _, step in pairs(chain_steps) do table.insert(sorted_steps, step) end
    table.sort(sorted_steps, function(a, b) return a.order > b.order end)
    state.last_calc = { steps = sorted_steps, raw = raw_totals }
end

local function build_blueprint(player)
    local state = get_state(player.index)
    run_calculation(player)
    local calc = state.last_calc
    if not calc or #calc.steps == 0 then return end

    local belt_name = get_belt_set()
    local fast_ins = get_inserter_name()
    local bp_list, bp_tiles = {}, {}

    local function add_ent(t)
        if not has_entity(t.name) then return end
        table.insert(bp_list, t)
    end

    local bus_top_y, col_start_y = -32, -20
    local start_x, cur_x, max_used_y = -40, -40, col_start_y + 40

    -- Главная шина сверху
    local estimated_end_x = start_x + (#calc.steps * 24) + 40
    for x = start_x - 4, estimated_end_x do
        for lane = 1, 4 do
            add_ent({name = belt_name, position = {x = x, y = bus_top_y + lane - 1}, direction = DIR_EAST})
        end
    end

    -- Колонны заводов
    for _, step in ipairs(calc.steps) do
        local m_size = step.machine_size or 3
        local pairs_count = math.ceil(math.max(1, math.ceil(step.exact_machines)) / 2)
        local col_width = state.use_beacons and (m_size * 2 + 17) or (m_size * 2 + 11)
        local center_x = cur_x + math.floor(col_width / 2)

        local left_m_x = center_x - 3 - math.floor(m_size / 2)
        local right_m_x = center_x + 3 + math.floor(m_size / 2)
        local col_bottom_y = col_start_y + pairs_count * m_size
        if col_bottom_y > max_used_y then max_used_y = col_bottom_y end

        for by = col_start_y, col_bottom_y do
            add_ent({name = belt_name, position = {x = center_x, y = by}, direction = DIR_NORTH})
            add_ent({name = belt_name, position = {x = center_x - 3, y = by}, direction = DIR_SOUTH})
            add_ent({name = belt_name, position = {x = center_x + 3, y = by}, direction = DIR_SOUTH})
        end

        for p = 0, pairs_count - 1 do
            local m_y = col_start_y + p * m_size + math.floor(m_size / 2)
            add_ent({name = step.machine_name, position = {x = left_m_x, y = m_y}, recipe = step.recipe_name, direction = DIR_WEST})
            add_ent({name = fast_ins, position = {x = center_x - 2, y = m_y - 1}, direction = DIR_EAST})
            add_ent({name = fast_ins, position = {x = center_x - 1, y = m_y + 1}, direction = DIR_WEST})
            add_ent({name = "medium-electric-pole", position = {x = center_x - 2, y = m_y}})

            add_ent({name = step.machine_name, position = {x = right_m_x, y = m_y}, recipe = step.recipe_name, direction = DIR_EAST})
            add_ent({name = fast_ins, position = {x = center_x + 2, y = m_y - 1}, direction = DIR_WEST})
            add_ent({name = fast_ins, position = {x = center_x + 1, y = m_y + 1}, direction = DIR_EAST})
            add_ent({name = "medium-electric-pole", position = {x = center_x + 2, y = m_y}})

            if state.use_beacons then
                add_ent({name = "beacon", position = {x = left_m_x - 3, y = m_y}})
                add_ent({name = "beacon", position = {x = right_m_x + 3, y = m_y}})
            end
        end
        cur_x = cur_x + col_width + 4
    end

    local end_x = math.max(46, cur_x + 6)
    local top_border_y, bottom_border_y = bus_top_y - 10, max_used_y + 10

    for x = start_x - 8, end_x + 4 do
        for y = top_border_y, bottom_border_y do
            if x == start_x - 8 or x == end_x + 4 or y == top_border_y or y == bottom_border_y then
                table.insert(bp_tiles, {name = "refined-hazard-concrete-left", position = {x = x, y = y}})
            else
                table.insert(bp_tiles, {name = "refined-concrete", position = {x = x, y = y}})
            end
        end
    end

    if state.add_stations then
        local rail_top = top_border_y + 2 - ((top_border_y + 2) % 2)
        local rail_bot = bottom_border_y - 2 - ((bottom_border_y - 2) % 2)
        local rail_left = start_x - 6 - ((start_x - 6) % 2)
        local rail_right = end_x + 2 - ((end_x + 2) % 2)

        for rx = rail_left, rail_right, 2 do
            add_ent({name = "straight-rail", position = {x = rx, y = rail_top}, direction = DIR_EAST, no_quality = true})
            add_ent({name = "straight-rail", position = {x = rx, y = rail_bot}, direction = DIR_EAST, no_quality = true})
        end
        for ry = rail_top + 2, rail_bot - 2, 2 do
            add_ent({name = "straight-rail", position = {x = rail_left, y = ry}, direction = DIR_NORTH, no_quality = true})
            add_ent({name = "straight-rail", position = {x = rail_right, y = ry}, direction = DIR_NORTH, no_quality = true})
        end
        add_ent({name = "train-stop", position = {x = rail_left + 14, y = rail_top + 2}, direction = DIR_EAST, station = string.format("[item=%s] Вывоз (%d/м)", state.item, state.rate), trains_limit = 2, no_quality = true})
    end

    local final_entities = {}
    for i, ent in ipairs(bp_list) do
        ent.entity_number = i
        table.insert(final_entities, ent)
    end

    if player.clear_cursor() then
        player.cursor_stack.set_stack({name = "blueprint", count = 1})
        pcall(function() player.cursor_stack.set_blueprint_entities(final_entities) end)
        pcall(function() player.cursor_stack.set_blueprint_tiles(bp_tiles) end)
        safe_set(player.cursor_stack, "label", string.format("ACB Megabase [%s]", state.item))
        player.print("[AutoCityBlock 1.3.3] Завод успешно создан со всеми заводами и конвейерами!")
    end
end

local function draw_helmod_gui(player)
    if not player or not safe_get(player, "valid", false) then return end
    local screen = safe_get(player.gui, "screen", nil)
    if not screen then return end
    local old_frame = safe_get(screen, "cb_helmod_frame", nil)
    if old_frame then pcall(function() old_frame.destroy() end) end

    local state = get_state(player.index)
    run_calculation(player)
    local calc = state.last_calc

    local main_frame = safe_add(screen, {type = "frame", name = "cb_helmod_frame", direction = "vertical", caption = "AutoCityBlock 1.3.3: Мегабаза"})
    if not main_frame then return end
    safe_set(main_frame, "auto_center", true)
    safe_set(main_frame.style, "minimal_width", 850)

    local top_bar = safe_add(main_frame, {type = "flow", direction = "horizontal"})
    safe_add(top_bar, {type = "label", caption = "Предмет:"})
    safe_add(top_bar, {type = "choose-elem-button", name = "cb_elem_item", elem_type = "item", item = state.item})
    safe_add(top_bar, {type = "label", caption = "  Кол-во/м:"})
    local tf = safe_add(top_bar, {type = "textfield", name = "cb_input_rate", text = tostring(state.rate), numeric = true})
    if tf then safe_set(tf.style, "width", 65) end

    local q_items = {} for _, q in ipairs(QUALITIES) do table.insert(q_items, q.caption) end
    safe_add(top_bar, {type = "label", caption = "  Качество:"})
    safe_add(top_bar, {type = "drop-down", name = "cb_drop_quality", items = q_items, selected_index = state.quality_index})

    local p_items = {} for _, p in ipairs(PLANETS) do table.insert(p_items, p.caption) end
    safe_add(top_bar, {type = "label", caption = "  Планета:"})
    safe_add(top_bar, {type = "drop-down", name = "cb_drop_planet", items = p_items, selected_index = state.planet_index})

    local opt_bar = safe_add(main_frame, {type = "flow", direction = "horizontal"})
    local m_items = {} for _, m in ipairs(MODULE_MODES) do table.insert(m_items, m.caption) end
    safe_add(opt_bar, {type = "label", caption = "Модули:"})
    safe_add(opt_bar, {type = "drop-down", name = "cb_drop_modules", items = m_items, selected_index = state.module_index})
    safe_add(opt_bar, {type = "checkbox", name = "cb_chk_beacons", caption = "  ⚡ Маяки", state = state.use_beacons})
    safe_add(opt_bar, {type = "checkbox", name = "cb_chk_rail", caption = "  🚂 ЖД периметр", state = state.add_stations})

    local scroll = safe_add(main_frame, {type = "scroll-pane", direction = "vertical"})
    if scroll then safe_set(scroll.style, "maximal_height", 320) end

    local tbl = safe_add(scroll or main_frame, {type = "table", column_count = 5, draw_horizontal_lines = true})
    if tbl then
        for _, h in ipairs({"Этап", "Станок", "Заводов", "Продуктивность", "Выход"}) do
            safe_add(tbl, {type = "label", caption = " " .. h .. " "})
        end
        if calc and calc.steps then
            for _, step in ipairs(calc.steps) do
                local r_flow = safe_add(tbl, {type = "flow", direction = "horizontal"})
                safe_add(r_flow, {type = "sprite-button", sprite = "recipe/" .. step.recipe_name, enabled = false})
                safe_add(r_flow, {type = "label", caption = step.recipe_name})
                local m_flow = safe_add(tbl, {type = "flow", direction = "horizontal"})
                safe_add(m_flow, {type = "sprite-button", sprite = "item/" .. step.machine_name, enabled = false})
                safe_add(m_flow, {type = "label", caption = string.format("x%.2f", step.speed)})
                safe_add(tbl, {type = "label", caption = string.format("%d шт.", math.ceil(step.exact_machines))})
                safe_add(tbl, {type = "label", caption = string.format("+%d%%", math.floor(step.prod_bonus * 100))})
                safe_add(tbl, {type = "label", caption = string.format("%.1f/м", step.output_per_sec * 60)})
            end
        end
    end

    local bot_bar = safe_add(main_frame, {type = "flow", direction = "horizontal"})
    safe_add(bot_bar, {type = "button", name = "cb_btn_recalc", caption = "🔄 Пересчитать"})
    safe_add(bot_bar, {type = "button", name = "cb_btn_blueprint", caption = "📐 Создать чертеж завода (+1%)", style = "confirm_button"})
    safe_add(bot_bar, {type = "button", name = "cb_btn_close", caption = "Закрыть"})
end

commands.add_command("cb", "Открыть", function(event) draw_helmod_gui(game.get_player(event.player_index)) end)

script.on_event(defines.events.on_gui_click, function(event)
    pcall(function()
        local el = event.element
        if not el or not safe_get(el, "valid", false) then return end
        local name = safe_get(el, "name", "")
        local player = game.get_player(event.player_index)
        local frame = safe_get(player.gui.screen, "cb_helmod_frame", nil)
        if frame then
            local ri = find_gui_element(frame, "cb_input_rate")
            if ri then get_state(player.index).rate = tonumber(safe_get(ri, "text", "120")) or 120 end
        end
        if name == "cb_top_toggle_btn" or name == "cb_btn_recalc" then draw_helmod_gui(player)
        elseif name == "cb_btn_blueprint" then build_blueprint(player); if frame and frame.valid then frame.destroy() end
        elseif name == "cb_btn_close" then if frame and frame.valid then frame.destroy() end end
    end)
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
    pcall(function()
        local el = event.element
        if el and el.valid and el.name == "cb_elem_item" and el.elem_value then
            get_state(event.player_index).item = el.elem_value
            draw_helmod_gui(game.get_player(event.player_index))
        end
    end)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    pcall(function()
        local el = event.element
        if not el or not safe_get(el, "valid", false) then return end
        local st = get_state(event.player_index)
        if el.name == "cb_drop_quality" then st.quality_index = el.selected_index
        elseif el.name == "cb_drop_planet" then st.planet_index = el.selected_index
        elseif el.name == "cb_drop_modules" then st.module_index = el.selected_index end
        draw_helmod_gui(game.get_player(event.player_index))
    end)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    pcall(function()
        local el = event.element
        if not el or not safe_get(el, "valid", false) then return end
        local st = get_state(event.player_index)
        if el.name == "cb_chk_beacons" then st.use_beacons = el.state
        elseif el.name == "cb_chk_rail" then st.add_stations = el.state end
        draw_helmod_gui(game.get_player(event.player_index))
    end)
end)
