-- ============================================================================
-- AUTO CITY BLOCK: CONVEYOR BELT & RAILWAY MEGABASE EDITION (Factorio 2.1)
-- ============================================================================

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
    ["metallurgy"] = {"foundry", "electric-furnace"},
    ["smelting"] = {"foundry", "electric-furnace", "steel-furnace"},
    ["chemistry"] = {"cryogenic-plant", "chemical-plant"},
    ["oil-processing"] = {"oil-refinery"},
    ["organic"] = {"biochamber", "assembling-machine-3"}
}

script.on_init(function()
    storage.player_state = {}
end)

local function get_state(player_index)
    if not storage.player_state then storage.player_state = {} end
    if not storage.player_state[player_index] then
        storage.player_state[player_index] = {
            item = "artillery-shell", rate = 100, quality_index = 1,
            planet_index = 1, module_index = 2, use_beacons = true,
            use_world_tech = true, add_stations = true, last_calc = nil
        }
    end
    return storage.player_state[player_index]
end

local function create_top_button(player)
    if player and player.valid and player.gui and player.gui.screen then
        if not player.gui.screen.cb_top_toggle_btn then
            player.gui.screen.add{
                type = "button", name = "cb_top_toggle_btn",
                caption = "⚙️ AutoCityBlock", style = "button"
            }
        end
    end
end

script.on_event(defines.events.on_player_created, function(event)
    create_top_button(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_configuration_changed, function()
    for _, p in pairs(game.players) do create_top_button(p) end
end)

local function is_fluid(name)
    return prototypes.fluid and prototypes.fluid[name] ~= nil
end

local function get_best_unlocked_machine(force, category, use_world_tech)
    local candidates = CATEGORY_MACHINE_PRIORITY[category] or {"assembling-machine-3", "assembling-machine-2"}
    for _, m_name in ipairs(candidates) do
        if prototypes.entity[m_name] then
            if not use_world_tech then return m_name end
            local rec = force.recipes[m_name]
            if not rec or rec.enabled then return m_name end
        end
    end
    return "assembling-machine-1"
end

local function find_recipe_for_item(force, item_name, use_world_tech, planet_id)
    local recipes = force.recipes
    if planet_id == "vulcanus" and recipes["casting-" .. item_name] then
        return prototypes.recipe["casting-" .. item_name], recipes["casting-" .. item_name]
    end
    if recipes[item_name] and (not use_world_tech or recipes[item_name].enabled) then
        return prototypes.recipe[item_name], recipes[item_name]
    end
    for name, f_recipe in pairs(recipes) do
        if not use_world_tech or f_recipe.enabled then
            local proto = prototypes.recipe[name]
            if proto and not proto.hidden then
                for _, product in pairs(proto.products) do
                    if product.name == item_name and (product.amount or 0) > 0 then
                        return proto, f_recipe
                    end
                end
            end
        end
    end
    if prototypes.recipe[item_name] then return prototypes.recipe[item_name], recipes[item_name] end
    return nil, nil
end

local function calculate_chain(force, item_name, rate_per_sec, state, chain_steps, raw_totals, depth)
    depth = depth or 0
    local planet_id = (PLANETS[state.planet_index] or PLANETS[1]).id
    local raw_map = PLANET_RAW[planet_id] or PLANET_RAW.nauvis

    if depth > 14 or raw_map[item_name] then
        raw_totals[item_name] = (raw_totals[item_name] or 0) + rate_per_sec
        return
    end

    local proto, f_recipe = find_recipe_for_item(force, item_name, state.use_world_tech, planet_id)
    if not proto then
        raw_totals[item_name] = (raw_totals[item_name] or 0) + rate_per_sec
        return
    end

    local base_output = 1
    local p_list = proto.products or {}
    for _, p in pairs(p_list) do
        if p.name == item_name then
            local amt = p.amount or ((p.amount_min + p.amount_max) / 2)
            base_output = amt * (p.probability or 1)
            break
        end
    end

    local prod_bonus = 0
    if state.use_world_tech and f_recipe and f_recipe.productivity_bonus then
        prod_bonus = f_recipe.productivity_bonus
    end

    local recipe_category = proto.category or (prototypes.recipe[proto.name] and prototypes.recipe[proto.name].category) or "crafting"
    local machine_name = get_best_unlocked_machine(force, recipe_category, state.use_world_tech)
    
    local machine_proto = prototypes.entity[machine_name]
    local base_speed = (machine_proto and machine_proto.crafting_speed) or 1.0

    if machine_proto and machine_proto.effect_receiver and machine_proto.effect_receiver.base_effect then
        prod_bonus = prod_bonus + (machine_proto.effect_receiver.base_effect.productivity or 0)
    end

    local mod_cfg = MODULE_MODES[state.module_index] or MODULE_MODES[1]
    prod_bonus = prod_bonus + mod_cfg.prod

    local speed_mult = 1.0 + mod_cfg.speed
    if state.use_beacons then speed_mult = speed_mult + 1.5 end
    speed_mult = math.max(0.2, speed_mult)

    local q_data = QUALITIES[state.quality_index] or QUALITIES[1]
    local final_speed = base_speed * q_data.mult * speed_mult

    local effective_output = base_output * (1 + prod_bonus)
    local crafts_per_sec = rate_per_sec / effective_output
    local recipe_time = proto.energy or 0.5
    local exact_machines = (crafts_per_sec * recipe_time) / final_speed

    if not chain_steps[proto.name] then
        chain_steps[proto.name] = {
            recipe_name = proto.name, item_name = item_name, machine_name = machine_name,
            exact_machines = 0, output_per_sec = 0, crafts_per_sec = 0,
            prod_bonus = prod_bonus, speed = final_speed, ingredients = proto.ingredients, order = depth
        }
    end

    local step = chain_steps[proto.name]
    step.exact_machines = step.exact_machines + exact_machines
    step.output_per_sec = step.output_per_sec + rate_per_sec
    step.crafts_per_sec = step.crafts_per_sec + crafts_per_sec

    local ing_list = proto.ingredients or {}
    for _, ing in pairs(ing_list) do
        local ing_rate = crafts_per_sec * ing.amount
        calculate_chain(force, ing.name, ing_rate, state, chain_steps, raw_totals, depth + 1)
    end
end

local function run_calculation(player)
    local state = get_state(player.index)
    if not state.item then return end

    local target_per_sec = (state.rate * 1.01) / 60.0
    local chain_steps = {}
    local raw_totals = {}

    calculate_chain(player.force, state.item, target_per_sec, state, chain_steps, raw_totals, 1)

    local sorted_steps = {}
    for _, step in pairs(chain_steps) do table.insert(sorted_steps, step) end
    table.sort(sorted_steps, function(a, b) return a.order < b.order end)

    state.last_calc = { steps = sorted_steps, raw = raw_totals }
end

local function build_blueprint(player)
    local state = get_state(player.index)
    if not state.last_calc then run_calculation(player) end
    local calc = state.last_calc
    if not calc or #calc.steps == 0 then return end

    local q_name = (QUALITIES[state.quality_index] or QUALITIES[1]).name
    local use_quality = prototypes.quality and prototypes.quality[q_name] ~= nil
    local planet_id = (PLANETS[state.planet_index] or PLANETS[1]).id

    local bp_entities = {}
    local bp_tiles = {}
    local eid = 1
    local half = 48

    for x = -half, half - 1 do
        for y = -half, half - 1 do
            if x == -half or x == half - 1 or y == -half or y == half - 1 then
                table.insert(bp_tiles, {name = "refined-hazard-concrete-left", position = {x = x, y = y}})
            else
                table.insert(bp_tiles, {name = "refined-concrete", position = {x = x, y = y}})
            end
        end
    end

    if state.add_stations then
        for x = -46, 46, 2 do
            table.insert(bp_entities, {entity_number = eid, name = "straight-rail", position = {x = x, y = -46}, direction = 4}); eid = eid + 1
            table.insert(bp_entities, {entity_number = eid, name = "straight-rail", position = {x = x, y = 46}, direction = 4}); eid = eid + 1
        end
        for y = -46, 46, 2 do
            table.insert(bp_entities, {entity_number = eid, name = "straight-rail", position = {x = -46, y = y}, direction = 0}); eid = eid + 1
            table.insert(bp_entities, {entity_number = eid, name = "straight-rail", position = {x = 46, y = y}, direction = 0}); eid = eid + 1
        end

        table.insert(bp_entities, {entity_number = eid, name = "rail-chain-signal", position = {x = -44, y = -44}, direction = 0}); eid = eid + 1
        table.insert(bp_entities, {entity_number = eid, name = "rail-signal", position = {x = -42, y = -44}, direction = 0}); eid = eid + 1
        table.insert(bp_entities, {entity_number = eid, name = "rail-chain-signal", position = {x = 44, y = -44}, direction = 4}); eid = eid + 1
        table.insert(bp_entities, {entity_number = eid, name = "rail-signal", position = {x = 42, y = -44}, direction = 4}); eid = eid + 1

        table.insert(bp_entities, {
            entity_number = eid, name = "train-stop",
            position = {x = -28, y = -44}, direction = 4,
            station = string.format("[item=%s] Вывоз (%d/м +1%%)", state.item, state.rate),
            trains_limit = 2
        }); eid = eid + 1

        local st_x = -38
        for raw_name, raw_rate in pairs(calc.raw) do
            if st_x <= 36 then
                local fluid_flag = is_fluid(raw_name)
                local icon_tag = fluid_flag and "fluid" or "item"
                table.insert(bp_entities, {
                    entity_number = eid, name = "train-stop",
                    position = {x = st_x, y = 44}, direction = 12,
                    station = string.format("[%s=%s] Снабжение (%.0f/м)", icon_tag, raw_name, raw_rate * 60),
                    trains_limit = 2
                }); eid = eid + 1

                if fluid_flag then
                    table.insert(bp_entities, {entity_number = eid, name = "pump", position = {x = st_x + 2, y = 44}, direction = 0}); eid = eid + 1
                    table.insert(bp_entities, {entity_number = eid, name = "storage-tank", position = {x = st_x + 2, y = 41}}); eid = eid + 1
                    table.insert(bp_entities, {entity_number = eid, name = "pipe-to-ground", position = {x = st_x + 2, y = 39}, direction = 0}); eid = eid + 1
                else
                    for offset = 1, 4 do
                        table.insert(bp_entities, {
                            entity_number = eid, name = "passive-provider-chest",
                            position = {x = st_x + offset, y = 44},
                            quality = use_quality and q_name or nil
                        }); eid = eid + 1
                    end
                end
                st_x = st_x + 12
            end
        end
    end

    for x = -36, 36, 18 do
        for y = -36, 36, 18 do
            table.insert(bp_entities, {entity_number = eid, name = "substation", position = {x = x, y = y}, quality = use_quality and q_name or nil}); eid = eid + 1
        end
    end

    local cur_x, cur_y = -36, -32
    local max_y = 32
    local row_step_x = state.use_beacons and 10 or 8

    for _, step in ipairs(calc.steps) do
        local count = math.ceil(step.exact_machines)
        for i = 1, count do
            if cur_y > max_y then
                cur_y = -32
                cur_x = cur_x + row_step_x
            end

            table.insert(bp_entities, {
                entity_number = eid, name = step.machine_name,
                position = {x = cur_x, y = cur_y}, recipe = step.recipe_name,
                quality = use_quality and q_name or nil
            }); eid = eid + 1

            table.insert(bp_entities, {
                entity_number = eid, name = "stack-inserter",
                position = {x = cur_x - 2, y = cur_y - 1}, direction = 12,
                quality = use_quality and q_name or nil
            }); eid = eid + 1
            table.insert(bp_entities, {
                entity_number = eid, name = "turbo-transport-belt",
                position = {x = cur_x - 3, y = cur_y - 1}, direction = 0
            }); eid = eid + 1

            table.insert(bp_entities, {
                entity_number = eid, name = "stack-inserter",
                position = {x = cur_x - 2, y = cur_y + 1}, direction = 4,
                quality = use_quality and q_name or nil
            }); eid = eid + 1
            table.insert(bp_entities, {
                entity_number = eid, name = "turbo-transport-belt",
                position = {x = cur_x - 3, y = cur_y + 1}, direction = 2
            }); eid = eid + 1

            local uses_fluid = false
            for _, ing in pairs(step.ingredients or {}) do
                if is_fluid(ing.name) then uses_fluid = true; break end
            end

            if uses_fluid then
                table.insert(bp_entities, {
                    entity_number = eid, name = "pipe-to-ground",
                    position = {x = cur_x + 2, y = cur_y - 1}, direction = 0
                }); eid = eid + 1
                table.insert(bp_entities, {
                    entity_number = eid, name = "pipe",
                    position = {x = cur_x + 1, y = cur_y}
                }); eid = eid + 1
            end

            if state.use_beacons then
                table.insert(bp_entities, {
                    entity_number = eid, name = "beacon",
                    position = {x = cur_x + 4, y = cur_y},
                    quality = use_quality and q_name or nil
                }); eid = eid + 1
            end

            cur_y = cur_y + 4
        end
    end

    if player.clear_cursor() then
        player.cursor_stack.set_stack({name = "blueprint", count = 1})
        player.cursor_stack.set_blueprint_entities(bp_entities)
        player.cursor_stack.set_blueprint_tiles(bp_tiles)
        player.cursor_stack.label = string.format("ACB Belt [%s]: %s (%d/м)", planet_id, state.item, state.rate)
        player.print("[AutoCityBlock] Чертёж конвейерного сити-блока с ЖД создан!")
    end
end

local function draw_helmod_gui(player)
    if player.gui.screen.cb_helmod_frame then player.gui.screen.cb_helmod_frame.destroy() end

    local state = get_state(player.index)
    run_calculation(player)
    local calc = state.last_calc

    local main_frame = player.gui.screen.add{type = "frame", name = "cb_helmod_frame", direction = "vertical", caption = "AutoCityBlock: Belts & Rails Megabase"}
    main_frame.auto_center = true
    main_frame.style.min_width = 850

    local top_bar = main_frame.add{type = "frame", style = "subheader_frame", direction = "horizontal"}
    top_bar.add{type = "label", caption = "Предмет:", style = "caption_label"}
    top_bar.add{type = "choose-elem-button", name = "cb_elem_item", elem_type = "item", item = state.item}
    top_bar.add{type = "label", caption = "  Кол-во/м (+1%):", style = "caption_label"}
    top_bar.add{type = "textfield", name = "cb_input_rate", text = tostring(state.rate), numeric = true}.style.width = 65

    local q_items = {} for _, q in ipairs(QUALITIES) do table.insert(q_items, q.caption) end
    top_bar.add{type = "label", caption = "  Качество:", style = "caption_label"}
    top_bar.add{type = "drop-down", name = "cb_drop_quality", items = q_items, selected_index = state.quality_index}

    local p_items = {} for _, p in ipairs(PLANETS) do table.insert(p_items, p.caption) end
    top_bar.add{type = "label", caption = "  Планета:", style = "caption_label"}
    top_bar.add{type = "drop-down", name = "cb_drop_planet", items = p_items, selected_index = state.planet_index}

    local opt_bar = main_frame.add{type = "flow", direction = "horizontal"}
    opt_bar.style.padding = 6
    opt_bar.add{type = "checkbox", name = "cb_chk_beacons", caption = "⚡ Ряды маяков", state = state.use_beacons}
    opt_bar.add{type = "empty-widget"}.style.width = 15
    opt_bar.add{type = "checkbox", name = "cb_chk_rail", caption = "🚂 ЖД пути, станции и светофоры", state = state.add_stations}

    local content_frame = main_frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}
    content_frame.style.padding = 8
    local scroll = content_frame.add{type = "scroll-pane", direction = "vertical"}
    scroll.style.max_height = 320

    local tbl = scroll.add{type = "table", column_count = 5, draw_horizontal_lines = true}
    for _, h in ipairs({"Рецепт", "Станок", "Заводов (Точно / Блок)", "Продуктивность", "Выход (/мин)"}) do
        tbl.add{type = "label", caption = h, style = "bold_label"}
    end

    if calc and calc.steps then
        for _, step in ipairs(calc.steps) do
            local r_flow = tbl.add{type = "flow", direction = "horizontal"}
            r_flow.add{type = "sprite-button", sprite = "recipe/" .. step.recipe_name, style = "slot_button", enabled = false}
            r_flow.add{type = "label", caption = step.recipe_name}

            local m_flow = tbl.add{type = "flow", direction = "horizontal"}
            m_flow.add{type = "sprite-button", sprite = "item/" .. step.machine_name, style = "slot_button", enabled = false}
            m_flow.add{type = "label", caption = string.format("x%.1f ск.", step.speed)}

            tbl.add{type = "label", caption = string.format("%.2f -> %d шт.", step.exact_machines, math.ceil(step.exact_machines))}
            tbl.add{type = "label", caption = string.format("+%d%%", math.floor(step.prod_bonus * 100 + 0.5))}
            tbl.add{type = "label", caption = string.format("[item=%s] %.1f/м", step.item_name, step.output_per_sec * 60)}
        end
    end

    local bot_bar = main_frame.add{type = "frame", style = "subheader_frame", direction = "horizontal"}
    bot_bar.add{type = "empty-widget"}.style.horizontally_stretchable = true
    bot_bar.add{type = "button", name = "cb_btn_blueprint", caption = "Создать конвейерный чертеж Сити-Блока (+1%)", style = "confirm_button"}
    bot_bar.add{type = "button", name = "cb_btn_close", caption = "Закрыть"}
end

commands.add_command("cb", "Открыть AutoCityBlock", function(event) draw_helmod_gui(game.get_player(event.player_index)) end)

script.on_event(defines.events.on_gui_click, function(event)
    local name = event.element.name
    local player = game.get_player(event.player_index)
    if name == "cb_top_toggle_btn" then
        draw_helmod_gui(player)
    elseif name == "cb_btn_blueprint" then
        local frame = player.gui.screen.cb_helmod_frame
        if frame and frame.children[1].cb_input_rate then
            get_state(player.index).rate = tonumber(frame.children[1].cb_input_rate.text) or 100
        end
        run_calculation(player)
        build_blueprint(player)
        if frame then frame.destroy() end
    elseif name == "cb_btn_close" then
        if player.gui.screen.cb_helmod_frame then player.gui.screen.cb_helmod_frame.destroy() end
    end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
    if event.element.name == "cb_elem_item" then
        get_state(event.player_index).item = event.element.elem_value
        draw_helmod_gui(game.get_player(event.player_index))
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local name = event.element.name
    local player = game.get_player(event.player_index)
    local state = get_state(player.index)
    if name == "cb_drop_quality" then state.quality_index = event.element.selected_index
    elseif name == "cb_drop_planet" then state.planet_index = event.element.selected_index end
    draw_helmod_gui(player)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local name = event.element.name
    local player = game.get_player(event.player_index)
    local state = get_state(player.index)
    if name == "cb_chk_beacons" then state.use_beacons = event.element.state
    elseif name == "cb_chk_rail" then state.add_stations = event.element.state end
    draw_helmod_gui(player)
end)
