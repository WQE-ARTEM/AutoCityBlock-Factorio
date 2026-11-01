-- ============================================================================
-- AUTO CITY BLOCK 1.2.0: MAIN BUS, CONNECTED PIPES & DENSE COLUMNS EDITION
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

-- Габариты зданий, чтобы ставить их вплотную без наслоений
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

-- Направления в Factorio 2.0 / 2.1 (16-dir enum)
local DIR_NORTH = 0
local DIR_EAST  = 4
local DIR_SOUTH = 8
local DIR_WEST  = 12

script.on_init(function()
    storage.player_state = {}
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

script.on_event(defines.events.on_player_created, function(event)
    create_top_button(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_configuration_changed, function()
    for _, p in pairs(game.players) do create_top_button(p) end
end)

local function is_fluid(name)
    return prototypes.fluid and prototypes.fluid[name] ~= nil
end

-- Автовыбор лучших доступных конвейеров и манипуляторов в игре
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
    -- Сортируем от базовых полуфабрикатов к финальной сборке (слева направо вдоль Главной Шины)
    table.sort(sorted_steps, function(a, b) return a.order > b.order end)

    state.last_calc = { steps = sorted_steps, raw = raw_totals }
end

-- ============================================================================
-- ГЕНЕРАТОР ЗАВОДА: ГЛАВНАЯ ШИНА + СПЛИТТЕРЫ + ПЛОТНЫЕ КОЛОННЫ + ТРУБОПРОВОД
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
    local fast_ins, long_ins = get_inserter_names()

    local bp_entities = {}
    local bp_tiles = {}
    local eid = 1

    local function add_ent(t)
        t.entity_number = eid
        if use_quality and not t.no_quality then
            t.quality = q_name
        end
        t.no_quality = nil
        table.insert(bp_entities, t)
        eid = eid + 1
    end

    -- Назначаем каждому ресурсу и полуфабрикату свою выделенную полосу на Главной Шине (Main Bus)
    local solid_lanes = {}
    local fluid_lanes = {}
    local s_idx = 1
    local f_idx = 1

    local function register_bus_item(name)
        if is_fluid(name) then
            if not fluid_lanes[name] then
                fluid_lanes[name] = f_idx
                f_idx = f_idx + 1
            end
        else
            if not solid_lanes[name] then
                solid_lanes[name] = s_idx
                s_idx = s_idx + 1
            end
        end
    end

    for raw_name, _ in pairs(calc.raw) do register_bus_item(raw_name) end
    for _, step in ipairs(calc.steps) do register_bus_item(step.item_name) end

    local total_solid_lanes = math.max(4, s_idx - 1)
    local total_fluid_lanes = math.max(2, f_idx - 1)

    -- Геометрия верхней Главной Шины (Main Bus) как на Фото 2
    local bus_top_y = -32
    local fluid_bus_top_y = bus_top_y + total_solid_lanes + 2
    local col_start_y = fluid_bus_top_y + total_fluid_lanes * 2 + 4
    local max_machines_per_side = 12 -- До 24 заводов в одной двойной колонне

    local start_x = -40
    local cur_x = start_x
    local max_used_y = col_start_y + 36

    -- 1. Строим плотные сдвоенные производственные колонны для каждого этапа
    for _, step in ipairs(calc.steps) do
        local m_size = MACHINE_SIZE[step.machine_name] or 3
        local total_needed = math.ceil(step.exact_machines)
        -- Если заводов очень много (например > 24), автоматически создаем несколько параллельных колонн рядом
        local sub_columns = math.ceil(total_needed / (max_machines_per_side * 2))

        for sc = 1, sub_columns do
            local remaining = total_needed - (sc - 1) * (max_machines_per_side * 2)
            local in_this_col = math.min(max_machines_per_side * 2, remaining)
            local pairs_count = math.ceil(in_this_col / 2)

            local col_width = state.use_beacons and (m_size * 2 + 17) or (m_size * 2 + 11)
            local center_x = cur_x + math.floor(col_width / 2)

            -- Координаты X элементов внутри сдвоенной колонны (симметрично относительно center_x):
            -- center_x: Центральный конвейер ВЫГРУЗКИ готового продукта (идет ВВЕРХ в Главную Шину)
            -- left_in1_x / right_in1_x: Первая лента подачи сырья (идет ВНИЗ из Главной Шины)
            -- left_in2_x / right_in2_x: Вторая лента подачи сырья (через длинный манипулятор)
            -- left_pipe_x / right_pipe_x: Непрерывный трубопровод вдоль внешних сторон заводов
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

            -- A) Подключение ВХОДНЫХ конвейеров колонны к Главной Шине через Сплиттеры и Подземные переходы
            local ing1 = step.solid_ings[1] and step.solid_ings[1].name
            local ing2 = step.solid_ings[2] and step.solid_ings[2].name

            if ing1 and solid_lanes[ing1] then
                local lane_y = bus_top_y + solid_lanes[ing1] - 1
                -- Сплиттер на Главной Шине
                add_ent{name = splitter_name, position = {x = left_belt_in1_x, y = lane_y + 0.5}, direction = DIR_EAST}
                -- Подземный нырок от сплиттера под остальными полосами шины
                add_ent{name = ug_name, position = {x = left_belt_in1_x, y = lane_y + 1}, direction = DIR_SOUTH, type = "input"}
                add_ent{name = ug_name, position = {x = left_belt_in1_x, y = col_start_y - 2}, direction = DIR_SOUTH, type = "output"}
                -- Перемычка на правую половину колонны
                for bx = left_belt_in1_x, right_belt_in1_x do
                    add_ent{name = belt_name, position = {x = bx, y = col_start_y - 1}, direction = (bx < right_belt_in1_x) and DIR_EAST or DIR_SOUTH}
                end
            end

            if ing2 and solid_lanes[ing2] then
                local lane_y = bus_top_y + solid_lanes[ing2] - 1
                add_ent{name = splitter_name, position = {x = left_belt_in2_x, y = lane_y + 0.5}, direction = DIR_EAST}
                add_ent{name = ug_name, position = {x = left_belt_in2_x, y = lane_y + 1}, direction = DIR_SOUTH, type = "input"}
                add_ent{name = ug_name, position = {x = left_belt_in2_x, y = col_start_y - 2}, direction = DIR_SOUTH, type = "output"}
            end

            -- B) Подключение ВЫХОДНОГО конвейера колонны обратно в Главную Шину
            if not step.fluid_out and solid_lanes[step.item_name] then
                local out_lane_y = bus_top_y + solid_lanes[step.item_name] - 1
                add_ent{name = ug_name, position = {x = center_x, y = col_start_y - 1}, direction = DIR_NORTH, type = "input"}
                add_ent{name = ug_name, position = {x = center_x, y = out_lane_y + 1}, direction = DIR_NORTH, type = "output"}
                add_ent{name = splitter_name, position = {x = center_x, y = out_lane_y - 0.5}, direction = DIR_EAST}
            end

            -- C) Подключение ЖИДКОСТНОГО коллектора колонны к жидкостной шине
            if #step.fluid_ings > 0 then
                local f_name = step.fluid_ings[1].name
                local f_lane_idx = fluid_lanes[f_name] or 1
                local f_bus_y = fluid_bus_top_y + (f_lane_idx - 1) * 2
                for py = f_bus_y, col_start_y - 1 do
                    add_ent{name = "pipe", position = {x = left_pipe_x, y = py}, no_quality = true}
                    add_ent{name = "pipe", position = {x = right_pipe_x, y = py}, no_quality = true}
                end
                add_ent{name = "pump", position = {x = left_pipe_x, y = col_start_y - 2}, direction = DIR_SOUTH}
                add_ent{name = "pump", position = {x = right_pipe_x, y = col_start_y - 2}, direction = DIR_SOUTH}
            end

            -- D) Непрерывные конвейерные ленты и трубы вдоль всей высоты колонны (без разрывов!)
            for by = col_start_y, col_bottom_y do
                -- Центральная лента выгрузки (идет на Север к шине)
                add_ent{name = belt_name, position = {x = center_x, y = by}, direction = DIR_NORTH}
                -- Внутренние ленты подачи сырья 1 (идут на Юг от шины)
                add_ent{name = belt_name, position = {x = left_belt_in1_x, y = by}, direction = DIR_SOUTH}
                add_ent{name = belt_name, position = {x = right_belt_in1_x, y = by}, direction = DIR_SOUTH}

                -- Внешние ленты подачи сырья 2 (если в рецепте >= 2 твердых ингредиентов)
                if #step.solid_ings >= 2 then
                    add_ent{name = belt_name, position = {x = left_belt_in2_x, y = by}, direction = DIR_SOUTH}
                    add_ent{name = belt_name, position = {x = right_belt_in2_x, y = by}, direction = DIR_SOUTH}
                end

                -- Непрерывная линия труб (если рецепт использует жидкости)
                if #step.fluid_ings > 0 or step.fluid_out then
                    add_ent{name = "pipe", position = {x = left_pipe_x, y = by}, no_quality = true}
                    add_ent{name = "pipe", position = {x = right_pipe_x, y = by}, no_quality = true}
                end
            end

            -- E) Расстановка самих заводов вплотную друг к другу, манипуляторов, подстанций и маяков
            for p = 0, pairs_count - 1 do
                local m_y = col_start_y + p * m_size + math.floor(m_size / 2)

                -- Левый завод (повернут жидкостным входом к левой трубе)
                add_ent{
                    name = step.machine_name,
                    position = {x = left_m_x, y = m_y},
                    recipe = step.recipe_name,
                    direction = DIR_WEST
                }
                -- Манипуляторы левого завода (вход 1 и выход)
                add_ent{name = fast_ins, position = {x = left_ins_in1_x, y = m_y - 1}, direction = DIR_EAST}
                add_ent{name = fast_ins, position = {x = left_ins_out_x, y = m_y + 1}, direction = DIR_WEST}
                add_ent{name = "medium-electric-pole", position = {x = left_ins_in1_x, y = m_y}}

                if #step.solid_ings >= 2 then
                    add_ent{name = fast_ins, position = {x = left_ins_in2_x, y = m_y}, direction = DIR_WEST}
                end
                if #step.fluid_ings > 0 or step.fluid_out then
                    -- Соединительный патрубок от общей трубы прямо в порт завода
                    for px = left_pipe_x + 1, left_m_x - math.ceil(m_size / 2) do
                        add_ent{name = "pipe", position = {x = px, y = m_y}, no_quality = true}
                    end
                end

                -- Правый завод (если нужен по счету)
                if (p * 2 + 2) <= in_this_col then
                    add_ent{
                        name = step.machine_name,
                        position = {x = right_m_x, y = m_y},
                        recipe = step.recipe_name,
                        direction = DIR_EAST
                    }
                    add_ent{name = fast_ins, position = {x = right_ins_in1_x, y = m_y - 1}, direction = DIR_WEST}
                    add_ent{name = fast_ins, position = {x = right_ins_out_x, y = m_y + 1}, direction = DIR_EAST}
                    add_ent{name = "medium-electric-pole", position = {x = right_ins_in1_x, y = m_y}}

                    if #step.solid_ings >= 2 then
                        add_ent{name = fast_ins, position = {x = right_ins_in2_x, y = m_y}, direction = DIR_EAST}
                    end
                    if #step.fluid_ings > 0 or step.fluid_out then
                        for px = right_m_x + math.ceil(m_size / 2), right_pipe_x - 1 do
                            add_ent{name = "pipe", position = {x = px, y = m_y}, no_quality = true}
                        end
                    end
                end

                -- Ряды маяков и подстанций вдоль колонны
                if state.use_beacons then
                    add_ent{name = "beacon", position = {x = left_beacon_x, y = m_y}}
                    add_ent{name = "beacon", position = {x = right_beacon_x, y = m_y}}
                end
                if p % 3 == 0 then
                    add_ent{name = "substation", position = {x = center_x, y = m_y}}
                end
            end

            cur_x = cur_x + col_width + 2
        end
    end

    local end_x = math.max(46, cur_x + 6)
    local top_border_y = bus_top_y - 8
    local bottom_border_y = max_used_y + 8

    -- 2. Прокладка непрерывной ГЛАВНОЙ ШИНЫ (Main Bus) сверху вдоль всех колонн (как на Фото 2)
    for x = start_x - 4, end_x do
        for lane = 1, total_solid_lanes do
            local ly = bus_top_y + lane - 1
            add_ent{name = belt_name, position = {x = x, y = ly}, direction = DIR_EAST}
        end
        for flane = 1, total_fluid_lanes do
            local fy = fluid_bus_top_y + (flane - 1) * 2
            add_ent{name = "pipe", position = {x = x, y = fy}, no_quality = true}
        end
    end

    -- 3. Бетонная площадка и ЖД-контур со светофорами вокруг всего комплекса (авто-размер под завод)
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
        local rail_top = top_border_y + 2
        local rail_bot = bottom_border_y - 2
        local rail_left = start_x - 6
        local rail_right = end_x + 2

        -- Выравнивание координат рельсов по четной сетке Factorio (шаг 2 клетки)
        rail_top = rail_top - (rail_top % 2)
        rail_bot = rail_bot - (rail_bot % 2)
        rail_left = rail_left - (rail_left % 2)
        rail_right = rail_right - (rail_right % 2)

        for rx = rail_left, rail_right, 2 do
            add_ent{name = "straight-rail", position = {x = rx, y = rail_top}, direction = DIR_EAST, no_quality = true}
            add_ent{name = "straight-rail", position = {x = rx, y = rail_bot}, direction = DIR_EAST, no_quality = true}
            if rx % 16 == 0 then
                add_ent{name = "rail-signal", position = {x = rx, y = rail_top + 2}, direction = DIR_EAST, no_quality = true}
                add_ent{name = "rail-signal", position = {x = rx, y = rail_bot - 2}, direction = DIR_WEST, no_quality = true}
            end
        end

        for ry = rail_top, rail_bot, 2 do
            add_ent{name = "straight-rail", position = {x = rail_left, y = ry}, direction = DIR_NORTH, no_quality = true}
            add_ent{name = "straight-rail", position = {x = rail_right, y = ry}, direction = DIR_NORTH, no_quality = true}
        end

        -- Станция погрузки готового продукта (Север)
        add_ent{
            name = "train-stop",
            position = {x = rail_left + 14, y = rail_top + 2},
            direction = DIR_EAST,
            station = string.format("[item=%s] Вывоз (%d/м +1%%)", state.item, state.rate),
            trains_limit = 2,
            no_quality = true
        }

        -- Станции разгрузки сырья (Юг) с выводом в Главную Шину
        local st_x = rail_left + 10
        for raw_name, raw_rate in pairs(calc.raw) do
            if st_x <= rail_right - 10 then
                local fluid_flag = is_fluid(raw_name)
                local icon_tag = fluid_flag and "fluid" or "item"
                add_ent{
                    name = "train-stop",
                    position = {x = st_x, y = rail_bot - 2},
                    direction = DIR_WEST,
                    station = string.format("[%s=%s] Снабжение (%.0f/м)", icon_tag, raw_name, raw_rate * 60),
                    trains_limit = 2,
                    no_quality = true
                }

                if fluid_flag then
                    add_ent{name = "pump", position = {x = st_x + 2, y = rail_bot - 2}, direction = DIR_NORTH}
                    add_ent{name = "storage-tank", position = {x = st_x + 2, y = rail_bot - 5}}
                else
                    for offset = 1, 4 do
                        add_ent{name = "steel-chest", position = {x = st_x + offset, y = rail_bot - 2}}
                        add_ent{name = fast_ins, position = {x = st_x + offset, y = rail_bot - 3}, direction = DIR_NORTH}
                        add_ent{name = belt_name, position = {x = st_x + offset, y = rail_bot - 4}, direction = DIR_NORTH}
                    end
                end
                st_x = st_x + 16
            end
        end
    end

    -- 4. Выдача готового чертежа в руку (с безопасной очисткой конфликтующих клеток)
    if player.clear_cursor() then
        player.cursor_stack.set_stack({name = "blueprint", count = 1})
        player.cursor_stack.set_blueprint_entities(bp_entities)
        player.cursor_stack.set_blueprint_tiles(bp_tiles)
        player.cursor_stack.label = string.format("ACB MainBus [%s]: %s (%d/м)", planet_id, state.item, state.rate)
        player.print(string.format("[AutoCityBlock 1.2] Плотный конвейерный завод создан! Полос на шине: %d | Труб: %d | Объектов: %d", total_solid_lanes, total_fluid_lanes, #bp_entities))
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
        caption = "AutoCityBlock 1.2: Главная Шина, Плотные Колонны и Трубопровод"
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
    opt_bar.add{type = "checkbox", name = "cb_chk_rail", caption = "🚂 ЖД контур, станции и светофоры", state = state.add_stations}

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

commands.add_command("cb", "Открыть AutoCityBlock 1.2", function(event)
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
