-- ============================================================================
-- AUTO CITY BLOCK 1.2.1: MAIN BUS, CONNECTED PIPES & DENSE COLUMNS EDITION
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
    {id = "none", caption = "Без модулей", prod = 0.0, speed = 0.0, item = nil},
    {id = "prod3", caption = "4x Продуктивность 3 (+40% прод)", prod = 0.40, speed = -0.60, item = "productivity-module-3"},
    {id = "speed3", caption = "4x Скорость 3 (+200% ск)", prod = 0.0, speed = 2.00, item = "speed-module-3"},
    {id = "qual3", caption = "4x Качество 3", prod = 0.0, speed = -0.20, item = "quality-module-3"}
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

local MACHINE_SIZE = {
    ["assembling-machine-1"] = 3,
    ["assembling-machine-2"] = 3,
    ["assembling-machine-3"] = 3,
    ["electric-furnace"] = 3,
    ["chemical-plant"] = 3,
    ["biochamber"] = 3,
    ["steel-furnace"] = 2,
    ["electromagnetic-plant"] = 4,
    ["foundry"] = 4,
    ["cryogenic-plant"] = 5,
    ["oil-refinery"] = 5
}

local DIR_NORTH = 0
local DIR_EAST  = 4
local DIR_SOUTH = 8
local DIR_WEST  = 12

local function create_top_button(player)
    if player and player.valid and player.gui and player.gui.screen then
        if not player.gui.screen.cb_top_toggle_btn then
            player.gui.screen.add{
                type = "button",
                name = "cb_top_toggle_btn",
                caption = "⚙️ AutoCityBlock 1.2",
                style = "button"
            }
        end
    end
end

script.on_init(function()
    storage.player_state = {}
    for _, p in pairs(game.players) do
        create_top_button(p)
    end
end)

-- ПРАВИЛЬНАЯ регистрация изменения конфигурации (через script.on_configuration_changed, а не on_event!)
script.on_configuration_changed(function()
    if not storage.player_state then storage.player_state = {} end
    for _, p in pairs(game.players) do
        create_top_button(p)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    create_top_button(game.get_player(event.player_index))
end)

local function get_state(player_index)
    if not storage.player_state then storage.player_state = {} end
    if not storage.player_state[player_index] then
        storage.player_state[player_index] = {
            item = "artillery-shell",
            rate = 100,
            quality_index = 1,
            planet_index = 1,
            module_index = 2,
            use_beacons = true,
            use_world_tech = true,
            add_stations = true,
            last_calc = nil
        }
    end
    return storage.player_state[player_index]
end

local function is_fluid(name)
    return prototypes.fluid and prototypes.fluid[name] ~= nil
end

local function get_belt_set()
    if prototypes.entity["turbo-transport-belt"] then
        return "turbo-transport-belt", "turbo-underground-belt", "turbo-splitter"
    end
    return "express-transport-belt", "express-underground-belt", "express-splitter"
end

local function get_inserter_names()
    local fast_ins = prototypes.entity["stack-inserter"] and "stack-inserter" or "bulk-inserter"
    return fast_ins, "long-handed-inserter"
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
    return "assembling-machine-2"
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
                for _, product in pairs(proto.products or {}) do
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
    for _, p in pairs(proto.products or {}) do
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

    local recipe_category = "crafting"
    local ok_cat, cat_val = pcall(function() return proto.category end)
    if ok_cat and cat_val then recipe_category = cat_val end

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

    local solid_ings = {}
    local fluid_ings = {}
    for _, ing in pairs(proto.ingredients or {}) do
        if is_fluid(ing.name) then
            table.insert(fluid_ings, ing)
        else
            table.insert(solid_ings, ing)
        end
    end

    local fluid_out = false
    for _, p in pairs(proto.products or {}) do
        if is_fluid(p.name) then fluid_out = true; break end
    end

    if not chain_steps[proto.name] then
        chain_steps[proto.name] = {
            recipe_name = proto.name,
            item_name = item_name,
            machine_name = machine_name,
            exact_machines = 0,
            output_per_sec = 0,
            crafts_per_sec = 0,
            prod_bonus = prod_bonus,
            speed = final_speed,
            ingredients = proto.ingredients or {},
            solid_ings = solid_ings,
            fluid_ings = fluid_ings,
            fluid_out = fluid_out,
            order = depth
        }
    end

    local step = chain_steps[proto.name]
    step.exact_machines = step.exact_machines + exact_machines
    step.output_per_sec = step.output_per_sec + rate_per_sec
    step.crafts_per_sec = step.crafts_per_sec + crafts_per_sec

    for _, ing in pairs(proto.ingredients or {}) do
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
    table.sort(sorted_steps, function(a, b) return a.order > b.order end)

    state.last_calc = { steps = sorted_steps, raw = raw_totals }
end

-- ============================================================================
-- ГЕНЕРАТОР ЗАВОДА: ГЛАВНАЯ ШИНА + ПЛОТНЫЕ КОЛОННЫ + ТРУБОПРОВОД (БЕЗ КОЛЛИЗИЙ)
-- ============================================================================
local function build_blueprint(player)
    local state = get_state(player.index)
    if not state.last_calc then run_calculation(player) end
    local calc = state.last_calc
    if not calc or #calc.steps == 0 then return end

    local q_name = (QUALITIES[state.quality_index] or QUALITIES[1]).name
    local use_quality = prototypes.quality and prototypes.quality[q_name] ~= nil
    local planet_id = (PLANETS[state.planet_index] or PLANETS[1]).id

    local belt_name, ug_name, splitter_name = get_belt_set()
    local fast_ins = get_inserter_names()

    -- Сетка клеток, исключающая наложение сплиттеров/нырков на обычные конвейеры шины
    local occupied = {}
    local bp_list = {}
    local bp_tiles = {}

    local function mark_area(cx, cy, w, h, idx)
        local x1 = math.floor(cx - w / 2 + 0.01)
        local x2 = math.floor(cx + w / 2 - 0.01)
        local y1 = math.floor(cy - h / 2 + 0.01)
        local y2 = math.floor(cy + h / 2 - 0.01)
        for x = x1, x2 do
            for y = y1, y2 do
                local key = x .. ":" .. y
                if occupied[key] then
                    bp_list[occupied[key]] = nil
                end
                occupied[key] = idx
            end
        end
    end

    local function add_ent(t, w, h)
        w = w or 1
        h = h or 1
        if use_quality and not t.no_quality then
            t.quality = q_name
        end
        t.no_quality = nil
        local idx = #bp_list + 1
        bp_list[idx] = t
        mark_area(t.position.x, t.position.y, w, h, idx)
    end

    local solid_lanes = {}
    local fluid_lanes = {}
    local s_idx = 1
    local f_idx = 1

    local function register_bus_item(name)
        if is_fluid(name) then
            if not fluid_lanes[name] then fluid_lanes[name] = f_idx; f_idx = f_idx + 1 end
        else
            if not solid_lanes[name] then solid_lanes[name] = s_idx; s_idx = s_idx + 1 end
        end
    end

    for raw_name, _ in pairs(calc.raw) do register_bus_item(raw_name) end
    for _, step in ipairs(calc.steps) do register_bus_item(step.item_name) end

    local total_solid_lanes = math.max(4, s_idx - 1)
    local total_fluid_lanes = math.max(2, f_idx - 1)

    local bus_top_y = -32
    local fluid_bus_top_y = bus_top_y + total_solid_lanes + 2
    local col_start_y = fluid_bus_top_y + total_fluid_lanes * 2 + 4
    local max_machines_per_side = 12

    local start_x = -40
    local cur_x = start_x
    local max_used_y = col_start_y + 36

    -- 1. Сначала прокладываем непрерывную Главную Шину (Main Bus)
    -- (Позже сплиттеры и подземные переходы автоматически заменят нужные клетки на шине!)
    local estimated_end_x = start_x + (#calc.steps * 22) + 30
    for x = start_x - 4, estimated_end_x do
        for lane = 1, total_solid_lanes do
            local ly = bus_top_y + lane - 1
            add_ent({name = belt_name, position = {x = x, y = ly}, direction = DIR_EAST}, 1, 1)
        end
        for flane = 1, total_fluid_lanes do
            local fy = fluid_bus_top_y + (flane - 1) * 2
            add_ent({name = "pipe", position = {x = x, y = fy}, no_quality = true}, 1, 1)
        end
    end

    -- 2. Строим плотные сдвоенные производственные колонны и врезаем их в Главную Шину
    for _, step in ipairs(calc.steps) do
        local m_size = MACHINE_SIZE[step.machine_name] or 3
        local total_needed = math.ceil(step.exact_machines)
        local sub_columns = math.ceil(total_needed / (max_machines_per_side * 2))

        for sc = 1, sub_columns do
            local remaining = total_needed - (sc - 1) * (max_machines_per_side * 2)
            local in_this_col = math.min(max_machines_per_side * 2, remaining)
            local pairs_count = math.ceil(in_this_col / 2)

            local col_width = state.use_beacons and (m_size * 2 + 17) or (m_size * 2 + 11)
            local center_x = cur_x + math.floor(col_width / 2)

            local left_m_x  = center_x - 3 - math.floor(m_size / 2)
            local right_m_x = center_x + 3 + math.floor(m_size / 2)

            local left_ins_out_x  = center_x - 1
            local left_ins_in1_x  = center_x - 2
            local left_belt_in1_x = center_x - 3

            local right_ins_out_x  = center_x + 1
            local right_ins_in1_x  = center_x + 2
            local right_belt_in1_x = center_x + 3

            local left_ins_in2_x  = left_m_x - math.ceil(m_size / 2)
            local left_belt_in2_x = left_ins_in2_x - 1
            local left_pipe_x     = left_belt_in2_x - 1
            local left_beacon_x   = left_pipe_x - 2

            local right_ins_in2_x  = right_m_x + math.ceil(m_size / 2)
            local right_belt_in2_x = right_ins_in2_x + 1
            local right_pipe_x     = right_belt_in2_x + 1
            local right_beacon_x   = right_pipe_x + 2

            local col_bottom_y = col_start_y + pairs_count * m_size
            if col_bottom_y > max_used_y then max_used_y = col_bottom_y end

            -- A) Врезка сплиттеров в Главную Шину и спуск сырья в колонну
            local ing1 = step.solid_ings[1] and step.solid_ings[1].name
            local ing2 = step.solid_ings[2] and step.solid_ings[2].name

            if ing1 and solid_lanes[ing1] then
                local lane_y = bus_top_y + solid_lanes[ing1] - 1
                add_ent({name = splitter_name, position = {x = left_belt_in1_x, y = lane_y + 0.5}, direction = DIR_EAST}, 1, 2)
                add_ent({name = belt_name, position = {x = left_belt_in1_x + 1, y = lane_y + 1}, direction = DIR_SOUTH}, 1, 1)
                add_ent({name = ug_name, position = {x = left_belt_in1_x + 1, y = lane_y + 2}, direction = DIR_SOUTH, type = "input"}, 1, 1)
                add_ent({name = ug_name, position = {x = left_belt_in1_x + 1, y = col_start_y - 2}, direction = DIR_SOUTH, type = "output"}, 1, 1)
                for bx = left_belt_in1_x, right_belt_in1_x do
                    add_ent({name = belt_name, position = {x = bx, y = col_start_y - 1}, direction = (bx < right_belt_in1_x) and DIR_EAST or DIR_SOUTH}, 1, 1)
                end
            end

            if ing2 and solid_lanes[ing2] then
                local lane_y = bus_top_y + solid_lanes[ing2] - 1
                add_ent({name = splitter_name, position = {x = left_belt_in2_x, y = lane_y + 0.5}, direction = DIR_EAST}, 1, 2)
                add_ent({name = belt_name, position = {x = left_belt_in2_x + 1, y = lane_y + 1}, direction = DIR_SOUTH}, 1, 1)
                add_ent({name = ug_name, position = {x = left_belt_in2_x + 1, y = lane_y + 2}, direction = DIR_SOUTH, type = "input"}, 1, 1)
                add_ent({name = ug_name, position = {x = left_belt_in2_x + 1, y = col_start_y - 2}, direction = DIR_SOUTH, type = "output"}, 1, 1)
                add_ent({name = belt_name, position = {x = left_belt_in2_x + 1, y = col_start_y - 1}, direction = DIR_WEST}, 1, 1)
                add_ent({name = belt_name, position = {x = left_belt_in2_x, y = col_start_y - 1}, direction = DIR_SOUTH}, 1, 1)
            end

            -- B) Возврат готовой продукции колонны на Главную Шину
            if not step.fluid_out and solid_lanes[step.item_name] then
                local out_lane_y = bus_top_y + solid_lanes[step.item_name] - 1
                add_ent({name = ug_name, position = {x = center_x, y = col_start_y - 1}, direction = DIR_NORTH, type = "input"}, 1, 1)
                add_ent({name = ug_name, position = {x = center_x, y = out_lane_y + 1}, direction = DIR_NORTH, type = "output"}, 1, 1)
                add_ent({name = splitter_name, position = {x = center_x + 1, y = out_lane_y + 0.5}, direction = DIR_EAST}, 1, 2)
            end

            -- C) Врезка трубопровода колонны в жидкостную шину
            if #step.fluid_ings > 0 then
                local f_name = step.fluid_ings[1].name
                local f_lane_idx = fluid_lanes[f_name] or 1
                local f_bus_y = fluid_bus_top_y + (f_lane_idx - 1) * 2
                for py = f_bus_y, col_start_y - 1 do
                    add_ent({name = "pipe", position = {x = left_pipe_x, y = py}, no_quality = true}, 1, 1)
                    add_ent({name = "pipe", position = {x = right_pipe_x, y = py}, no_quality = true}, 1, 1)
                end
            end

            -- D) Сплошные конвейеры и трубы внутри колонны
            for by = col_start_y, col_bottom_y do
                add_ent({name = belt_name, position = {x = center_x, y = by}, direction = DIR_NORTH}, 1, 1)
                add_ent({name = belt_name, position = {x = left_belt_in1_x, y = by}, direction = DIR_SOUTH}, 1, 1)
                add_ent({name = belt_name, position = {x = right_belt_in1_x, y = by}, direction = DIR_SOUTH}, 1, 1)

                if #step.solid_ings >= 2 then
                    add_ent({name = belt_name, position = {x = left_belt_in2_x, y = by}, direction = DIR_SOUTH}, 1, 1)
                    add_ent({name = belt_name, position = {x = right_belt_in2_x, y = by}, direction = DIR_SOUTH}, 1, 1)
                end

                if #step.fluid_ings > 0 or step.fluid_out then
                    add_ent({name = "pipe", position = {x = left_pipe_x, y = by}, no_quality = true}, 1, 1)
                    add_ent({name = "pipe", position = {x = right_pipe_x, y = by}, no_quality = true}, 1, 1)
                end
            end

            -- E) Плотная расстановка заводов спина к спине, манипуляторов, патрубков и маяков
            for p = 0, pairs_count - 1 do
                local m_y = col_start_y + p * m_size + math.floor(m_size / 2)

                add_ent({
                    name = step.machine_name,
                    position = {x = left_m_x, y = m_y},
                    recipe = step.recipe_name,
                    direction = DIR_WEST
                }, m_size, m_size)

                add_ent({name = fast_ins, position = {x = left_ins_in1_x, y = m_y - 1}, direction = DIR_EAST}, 1, 1)
                add_ent({name = fast_ins, position = {x = left_ins_out_x, y = m_y + 1}, direction = DIR_WEST}, 1, 1)
                add_ent({name = "medium-electric-pole", position = {x = left_ins_in1_x, y = m_y}}, 1, 1)

                if #step.solid_ings >= 2 then
                    add_ent({name = fast_ins, position = {x = left_ins_in2_x, y = m_y}, direction = DIR_WEST}, 1, 1)
                end
                if #step.fluid_ings > 0 or step.fluid_out then
                    for px = left_pipe_x + 1, left_m_x - math.ceil(m_size / 2) do
                        add_ent({name = "pipe", position = {x = px, y = m_y}, no_quality = true}, 1, 1)
                    end
                end

                if (p * 2 + 2) <= in_this_col then
                    add_ent({
                        name = step.machine_name,
                        position = {x = right_m_x, y = m_y},
                        recipe = step.recipe_name,
                        direction = DIR_EAST
                    }, m_size, m_size)

                    add_ent({name = fast_ins, position = {x = right_ins_in1_x, y = m_y - 1}, direction = DIR_WEST}, 1, 1)
                    add_ent({name = fast_ins, position = {x = right_ins_out_x, y = m_y + 1}, direction = DIR_EAST}, 1, 1)
                    add_ent({name = "medium-electric-pole", position = {x = right_ins_in1_x, y = m_y}}, 1, 1)

                    if #step.solid_ings >= 2 then
                        add_ent({name = fast_ins, position = {x = right_ins_in2_x, y = m_y}, direction = DIR_EAST}, 1, 1)
                    end
                    if #step.fluid_ings > 0 or step.fluid_out then
                        for px = right_m_x + math.ceil(m_size / 2), right_pipe_x - 1 do
                            add_ent({name = "pipe", position = {x = px, y = m_y}, no_quality = true}, 1, 1)
                        end
                    end
                end

                if state.use_beacons then
                    add_ent({name = "beacon", position = {x = left_beacon_x, y = m_y}}, 3, 3)
                    add_ent({name = "beacon", position = {x = right_beacon_x, y = m_y}}, 3, 3)
                end
            end

            cur_x = cur_x + col_width + 2
        end
    end

    local end_x = math.max(46, cur_x + 6)
    local top_border_y = bus_top_y - 8
    local bottom_border_y = max_used_y + 8

    -- 3. Бетонная площадка и ЖД-контур вокруг всего завода
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
            add_ent({name = "straight-rail", position = {x = rx, y = rail_top}, direction = DIR_EAST, no_quality = true}, 2, 2)
            add_ent({name = "straight-rail", position = {x = rx, y = rail_bot}, direction = DIR_EAST, no_quality = true}, 2, 2)
        end
        for ry = rail_top + 2, rail_bot - 2, 2 do
            add_ent({name = "straight-rail", position = {x = rail_left, y = ry}, direction = DIR_NORTH, no_quality = true}, 2, 2)
            add_ent({name = "straight-rail", position = {x = rail_right, y = ry}, direction = DIR_NORTH, no_quality = true}, 2, 2)
        end

        add_ent({
            name = "train-stop",
            position = {x = rail_left + 14, y = rail_top + 2},
            direction = DIR_EAST,
            station = string.format("[item=%s] Вывоз (%d/м +1%%)", state.item, state.rate),
            trains_limit = 2,
            no_quality = true
        }, 2, 2)

        local st_x = rail_left + 10
        for raw_name, raw_rate in pairs(calc.raw) do
            if st_x <= rail_right - 10 then
                local fluid_flag = is_fluid(raw_name)
                local icon_tag = fluid_flag and "fluid" or "item"
                add_ent({
                    name = "train-stop",
                    position = {x = st_x, y = rail_bot - 2},
                    direction = DIR_WEST,
                    station = string.format("[%s=%s] Снабжение (%.0f/м)", icon_tag, raw_name, raw_rate * 60),
                    trains_limit = 2,
                    no_quality = true
                }, 2, 2)
                st_x = st_x + 16
            end
        end
    end

    -- Собираем финальный плотный массив сущностей с последовательными номерами entity_number
    local final_entities = {}
    local eid = 1
    for _, ent in pairs(bp_list) do
        if ent then
            ent.entity_number = eid
            table.insert(final_entities, ent)
            eid = eid + 1
        end
    end

    if player.clear_cursor() then
        player.cursor_stack.set_stack({name = "blueprint", count = 1})
        player.cursor_stack.set_blueprint_entities(final_entities)
        player.cursor_stack.set_blueprint_tiles(bp_tiles)
        player.cursor_stack.label = string.format("ACB MainBus [%s]: %s (%d/м)", planet_id, state.item, state.rate)
        player.print(string.format("[AutoCityBlock 1.2.1] Чертёж готов! Полос на шине: %d | Труб: %d | Зданий и конвейеров: %d", total_solid_lanes, total_fluid_lanes, #final_entities))
    end
end

-- ============================================================================
-- ГРАФИЧЕСКИЙ ИНТЕРФЕЙС В СТИЛЕ HELMOD
-- ============================================================================
local function draw_helmod_gui(player)
    if player.gui.screen.cb_helmod_frame then player.gui.screen.cb_helmod_frame.destroy() end

    local state = get_state(player.index)
    run_calculation(player)
    local calc = state.last_calc

    local main_frame = player.gui.screen.add{
        type = "frame",
        name = "cb_helmod_frame",
        direction = "vertical",
        caption = "AutoCityBlock 1.2.1: Главная Шина, Плотные Колонны и Трубопровод"
    }
    main_frame.auto_center = true
    main_frame.style.min_width = 880

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
    local m_items = {} for _, m in ipairs(MODULE_MODES) do table.insert(m_items, m.caption) end
    opt_bar.add{type = "label", caption = "Модули:", style = "bold_label"}
    opt_bar.add{type = "drop-down", name = "cb_drop_modules", items = m_items, selected_index = state.module_index}
    opt_bar.add{type = "empty-widget"}.style.width = 12
    opt_bar.add{type = "checkbox", name = "cb_chk_beacons", caption = "⚡ Ряды маяков вдоль колонн", state = state.use_beacons}
    opt_bar.add{type = "empty-widget"}.style.width = 12
    opt_bar.add{type = "checkbox", name = "cb_chk_rail", caption = "🚂 ЖД контур и станции", state = state.add_stations}

    local content_frame = main_frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}
    content_frame.style.padding = 8
    local scroll = content_frame.add{type = "scroll-pane", direction = "vertical"}
    scroll.style.max_height = 340

    local tbl = scroll.add{type = "table", column_count = 6, draw_horizontal_lines = true}
    for _, h in ipairs({"Этап (Колонна)", "Станок", "Заводов (Точно / В ряду)", "Продуктивность", "Поток (/мин)", "Подача (Ленты + Трубы)"}) do
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

            tbl.add{type = "label", caption = string.format("%.2f -> [color=green]%d шт.[/color]", step.exact_machines, math.ceil(step.exact_machines))}
            tbl.add{type = "label", caption = string.format("+%d%%", math.floor(step.prod_bonus * 100 + 0.5))}
            tbl.add{type = "label", caption = string.format("[item=%s] %.1f/м", step.item_name, step.output_per_sec * 60)}

            local ing_flow = tbl.add{type = "flow", direction = "horizontal"}
            for _, ing in pairs(step.ingredients) do
                local spr = is_fluid(ing.name) and ("fluid/" .. ing.name) or ("item/" .. ing.name)
                ing_flow.add{
                    type = "sprite-button",
                    sprite = spr,
                    number = math.ceil(step.crafts_per_sec * 60 * ing.amount),
                    style = "slot_button",
                    enabled = false
                }
            end
        end
    end

    local bot_bar = main_frame.add{type = "frame", style = "subheader_frame", direction = "horizontal"}
    bot_bar.add{type = "empty-widget"}.style.horizontally_stretchable = true
    bot_bar.add{type = "button", name = "cb_btn_blueprint", caption = "Сгенерировать Завод с Главной Шиной и Трубами (+1%)", style = "confirm_button"}
    bot_bar.add{type = "button", name = "cb_btn_close", caption = "Закрыть"}
end

commands.add_command("cb", "Открыть AutoCityBlock 1.2.1", function(event)
    draw_helmod_gui(game.get_player(event.player_index))
end)

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
    elseif name == "cb_drop_planet" then state.planet_index = event.element.selected_index
    elseif name == "cb_drop_modules" then state.module_index = event.element.selected_index end
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
