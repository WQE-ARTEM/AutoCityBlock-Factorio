-- ============================================================================
-- AUTO CITY BLOCK 1.0.0: ULTIMATE HELMOD & SPACE AGE EDITION
-- ============================================================================

-- Базовые ресурсы в зависимости от выбранной планеты
local PLANET_RAW = {
    nauvis = {
        ["iron-ore"] = true, ["copper-ore"] = true, ["coal"] = true,
        ["stone"] = true, ["uranium-ore"] = true, ["crude-oil"] = true,
        ["water"] = true, ["steam"] = true, ["wood"] = true
    },
    vulcanus = {
        ["lava"] = true, ["calcite"] = true, ["coal"] = true,
        ["tungsten-ore"] = true, ["sulfuric-acid"] = true, ["stone"] = true
    },
    fulgora = {
        ["scrap"] = true, ["heavy-oil"] = true, ["water"] = true
    },
    gleba = {
        ["yumako"] = true, ["jellynut"] = true, ["stone"] = true,
        ["water"] = true, ["spoilage"] = true
    },
    aquilo = {
        ["lithium-brine"] = true, ["fluorine"] = true, ["ammoniacal-solution"] = true,
        ["crude-oil"] = true, ["water"] = true, ["iron-ore"] = true, ["copper-ore"] = true
    }
}

local PLANETS = {
    {id = "nauvis", caption = "Наувис (Nauvis)"},
    {id = "vulcanus", caption = "Вулкан (Vulcanus - Лава/Кальцит)"},
    {id = "fulgora", caption = "Фульгора (Fulgora - Лом)"},
    {id = "gleba", caption = "Глеба (Gleba - Био)"},
    {id = "aquilo", caption = "Аквило (Aquilo - Теплотрасса)"}
}

local QUALITIES = {
    {name = "normal", caption = "Обычное (Normal)", mult = 1.0},
    {name = "uncommon", caption = "Необычное (Uncommon +30%)", mult = 1.3},
    {name = "rare", caption = "Редкое (Rare +60%)", mult = 1.6},
    {name = "epic", caption = "Эпическое (Epic +90%)", mult = 1.9},
    {name = "legendary", caption = "Легендарное (Legendary +150%)", mult = 2.5}
}

local MODULE_MODES = {
    {id = "none", caption = "Без модулей", prod = 0.0, speed = 0.0, item = nil},
    {id = "prod3", caption = "4x Продуктивность 3 (+40% прод, -60% ск)", prod = 0.40, speed = -0.60, item = "productivity-module-3"},
    {id = "speed3", caption = "4x Скорость 3 (+200% ск)", prod = 0.0, speed = 2.00, item = "speed-module-3"},
    {id = "qual3", caption = "4x Качество 3 (-20% ск, фарм качества)", prod = 0.0, speed = -0.20, item = "quality-module-3"}
}

local CATEGORY_MACHINE_PRIORITY = {
    ["crafting"] = {"assembling-machine-3", "assembling-machine-2", "assembling-machine-1"},
    ["basic-crafting"] = {"assembling-machine-3", "assembling-machine-2", "assembling-machine-1"},
    ["advanced-crafting"] = {"assembling-machine-3", "assembling-machine-2"},
    ["crafting-with-fluid"] = {"assembling-machine-3", "assembling-machine-2"},
    ["electronics"] = {"electromagnetic-plant", "assembling-machine-3", "assembling-machine-2"},
    ["metallurgy"] = {"foundry", "electric-furnace"},
    ["smelting"] = {"foundry", "electric-furnace", "steel-furnace", "stone-furnace"},
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
            item = "artillery-shell",
            rate = 100,
            quality_index = 1,
            planet_index = 1,
            module_index = 2, -- По умолчанию Продуктивность 3
            use_beacons = true,
            use_upcycler = false,
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

local function get_best_unlocked_machine(force, category, use_world_tech)
    local candidates = CATEGORY_MACHINE_PRIORITY[category] or {"assembling-machine-3", "assembling-machine-2", "assembling-machine-1"}
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
    -- На Вулкане предпочитаем литье из лавы, если доступно
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
    if prototypes.recipe[item_name] then
        return prototypes.recipe[item_name], recipes[item_name]
    end
    return nil, nil
end

-- Рекурсивный расчет матрицы производства
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
    for _, p in pairs(proto.products) do
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

    local machine_name = get_best_unlocked_machine(force, proto.category, state.use_world_tech)
    local machine_proto = prototypes.entity[machine_name]
    local base_speed = (machine_proto and machine_proto.crafting_speed) or 1.0

    if machine_proto and machine_proto.effect_receiver and machine_proto.effect_receiver.base_effect then
        prod_bonus = prod_bonus + (machine_proto.effect_receiver.base_effect.productivity or 0)
    end

    -- Учет модулей и маяков
    local mod_cfg = MODULE_MODES[state.module_index] or MODULE_MODES[1]
    prod_bonus = prod_bonus + mod_cfg.prod

    local speed_mult = 1.0 + mod_cfg.speed
    if state.use_beacons then
        speed_mult = speed_mult + 1.5 -- Бонус от ряда маяков со Скоростью 3
    end
    speed_mult = math.max(0.2, speed_mult)

    local q_data = QUALITIES[state.quality_index] or QUALITIES[1]
    local final_speed = base_speed * q_data.mult * speed_mult

    local effective_output = base_output * (1 + prod_bonus)
    local crafts_per_sec = rate_per_sec / effective_output
    local recipe_time = proto.energy or 0.5
    local exact_machines = (crafts_per_sec * recipe_time) / final_speed

    -- Проверяем, использует ли рецепт жидкости
    local uses_fluid = false
    for _, ing in pairs(proto.ingredients) do
        if is_fluid(ing.name) then uses_fluid = true; break end
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
            ingredients = proto.ingredients,
            uses_fluid = uses_fluid,
            order = depth
        }
    end

    local step = chain_steps[proto.name]
    step.exact_machines = step.exact_machines + exact_machines
    step.output_per_sec = step.output_per_sec + rate_per_sec
    step.crafts_per_sec = step.crafts_per_sec + crafts_per_sec

    for _, ing in pairs(proto.ingredients) do
        local ing_rate = crafts_per_sec * ing.amount
        calculate_chain(force, ing.name, ing_rate, state, chain_steps, raw_totals, depth + 1)
    end
end

local function run_calculation(player)
    local state = get_state(player.index)
    if not state.item then return end

    -- Запас +1% (и x2.5 запас входа, если включена ферма переработки качества Upcycler)
    local upcycler_factor = state.use_upcycler and 2.5 or 1.0
    local target_per_sec = ((state.rate * 1.01) * upcycler_factor) / 60.0
    local chain_steps = {}
    local raw_totals = {}

    calculate_chain(player.force, state.item, target_per_sec, state, chain_steps, raw_totals, 1)

    local sorted_steps = {}
    for _, step in pairs(chain_steps) do
        table.insert(sorted_steps, step)
    end
    table.sort(sorted_steps, function(a, b) return a.order < b.order end)

    state.last_calc = {
        steps = sorted_steps,
        raw = raw_totals,
        upcycler_machines = state.use_upcycler and math.ceil((state.rate / 60.0) * 4) or 0
    }
end

-- ============================================================================
-- ПРОЦЕДУРНЫЙ ГЕНЕРАТОР ЧЕРТЕЖА СИТИ-БЛОКА (96x96)
-- ============================================================================
local function build_city_block_blueprint(player)
    local state = get_state(player.index)
    if not state.last_calc then run_calculation(player) end
    local calc = state.last_calc
    if not calc or #calc.steps == 0 then
        player.print("[AutoCityBlock] Выберите предмет для генерации!")
        return
    end

    local q_name = (QUALITIES[state.quality_index] or QUALITIES[1]).name
    local use_quality = prototypes.quality and prototypes.quality[q_name] ~= nil
    local planet_id = (PLANETS[state.planet_index] or PLANETS[1]).id
    local is_aquilo = (planet_id == "aquilo")

    local bp_entities = {}
    local bp_tiles = {}
    local eid = 1
    local half = 48

    -- 1. Плитка: на Аквило бетон обязателен поверх льда по всей площади блока
    for x = -half, half - 1 do
        for y = -half, half - 1 do
            if x == -half or x == half - 1 or y == -half or y == half - 1 then
                table.insert(bp_tiles, {name = "refined-hazard-concrete-left", position = {x = x, y = y}})
            elseif is_aquilo then
                table.insert(bp_tiles, {name = "refined-concrete", position = {x = x, y = y}})
            end
        end
    end

    -- 2. ЖД-контур, Грузовые и Жидкостные станции + Комбинаторы
    if state.add_stations then
        for x = -46, 46, 2 do
            table.insert(bp_entities, {entity_number = eid, name = "straight-rail", position = {x = x, y = -46}, direction = 4}); eid = eid + 1
            table.insert(bp_entities, {entity_number = eid, name = "straight-rail", position = {x = x, y = 46}, direction = 4}); eid = eid + 1
        end

        -- Север: Погрузка готового продукта + Комбинатор управления
        table.insert(bp_entities, {
            entity_number = eid, name = "train-stop",
            position = {x = -30, y = -44}, direction = 4,
            station = string.format("[item=%s] Вывоз (%d/м +1%%)", state.item, state.rate),
            trains_limit = 1
        }); eid = eid + 1

        table.insert(bp_entities, {
            entity_number = eid, name = "decider-combinator",
            position = {x = -27, y = -44}, direction = 4
        }); eid = eid + 1

        for cx = -38, -33 do
            table.insert(bp_entities, {
                entity_number = eid, name = "requester-chest",
                position = {x = cx, y = -44},
                quality = use_quality and q_name or nil
            }); eid = eid + 1
        end

        -- Юг: Разгрузка сырья (Разделение на Твердые грузы и Жидкости)
        local st_x = -40
        for raw_name, raw_rate in pairs(calc.raw) do
            if st_x <= 38 then
                local fluid_flag = is_fluid(raw_name)
                local icon_tag = fluid_flag and "fluid" or "item"
                table.insert(bp_entities, {
                    entity_number = eid, name = "train-stop",
                    position = {x = st_x, y = 44}, direction = 12,
                    station = string.format("[%s=%s] Снабжение (%.0f/м)", icon_tag, raw_name, raw_rate * 60),
                    trains_limit = 1
                }); eid = eid + 1

                if fluid_flag then
                    -- Жидкостная станция: Помпа + Резервуар + Подземный трубопровод
                    table.insert(bp_entities, {
                        entity_number = eid, name = "pump",
                        position = {x = st_x + 3, y = 44}, direction = 0
                    }); eid = eid + 1
                    table.insert(bp_entities, {
                        entity_number = eid, name = "storage-tank",
                        position = {x = st_x + 3, y = 41}
                    }); eid = eid + 1
                    table.insert(bp_entities, {
                        entity_number = eid, name = "pipe-to-ground",
                        position = {x = st_x + 3, y = 39}, direction = 0
                    }); eid = eid + 1
                else
                    -- Твердотельная станция: Сундуки снабжения + Комбинатор
                    table.insert(bp_entities, {
                        entity_number = eid, name = "constant-combinator",
                        position = {x = st_x + 1, y = 43}
                    }); eid = eid + 1
                    for offset = 2, 5 do
                        table.insert(bp_entities, {
                            entity_number = eid, name = "passive-provider-chest",
                            position = {x = st_x + offset, y = 44},
                            quality = use_quality and q_name or nil
                        }); eid = eid + 1
                    end
                end
                st_x = st_x + 14
            end
        end
    end

    -- 3. Энергосеть, Дронстанции и Обогрев для Аквило
    for x = -36, 36, 18 do
        for y = -36, 36, 18 do
            table.insert(bp_entities, {
                entity_number = eid, name = "substation",
                position = {x = x, y = y},
                quality = use_quality and q_name or nil
            }); eid = eid + 1
        end
    end

    for _, coords in pairs({{-27, -27}, {27, -27}, {-27, 27}, {27, 27}}) do
        table.insert(bp_entities, {
            entity_number = eid, name = "roboport",
            position = {x = coords[1], y = coords[2]},
            quality = use_quality and q_name or nil
        }); eid = eid + 1
    end

    if is_aquilo and prototypes.entity["heating-tower"] then
        table.insert(bp_entities, {
            entity_number = eid, name = "heating-tower",
            position = {x = 0, y = -41}
        }); eid = eid + 1
    end

    -- 4. Производственные ряды + Маяки + Жидкостные трубы + Тепловые трубы
    local cur_x, cur_y = -38, -34
    local max_y = 34
    local row_step_x = state.use_beacons and 10 or 7

    for _, step in ipairs(calc.steps) do
        local count = math.ceil(step.exact_machines)
        local per_machine_crafts = step.crafts_per_sec / count

        -- Формируем логистические фильтры для синего сундука (запас на 30 секунд работы станка)
        local req_filters = {}
        local f_idx = 1
        for _, ing in pairs(step.ingredients) do
            if not is_fluid(ing.name) then
                local req_count = math.max(10, math.ceil(per_machine_crafts * ing.amount * 30))
                table.insert(req_filters, {
                    index = f_idx,
                    name = ing.name,
                    quality = use_quality and q_name or "normal",
                    comparator = "=",
                    count = req_count
                })
                f_idx = f_idx + 1
            end
        end

        for i = 1, count do
            if (math.abs(cur_x) % 18 <= 2 and math.abs(cur_y) % 18 <= 2) or
               (math.abs(math.abs(cur_x) - 27) <= 3 and math.abs(math.abs(cur_y) - 27) <= 3) then
                cur_y = cur_y + 5
            end
            if cur_y > max_y then
                cur_y = -34
                cur_x = cur_x + row_step_x
            end

            -- Станок
            table.insert(bp_entities, {
                entity_number = eid,
                name = step.machine_name,
                position = {x = cur_x, y = cur_y},
                recipe = step.recipe_name,
                recipe_quality = use_quality and q_name or nil,
                quality = use_quality and q_name or nil
            }); eid = eid + 1

            -- Вход: Манипулятор + Синий сундук с авто-запросами
            table.insert(bp_entities, {
                entity_number = eid, name = "bulk-inserter",
                position = {x = cur_x - 2, y = cur_y - 1}, direction = 12,
                quality = use_quality and q_name or nil
            }); eid = eid + 1

            table.insert(bp_entities, {
                entity_number = eid, name = "requester-chest",
                position = {x = cur_x - 3, y = cur_y - 1},
                quality = use_quality and q_name or nil,
                request_filters = (#req_filters > 0) and {sections = {{index = 1, filters = req_filters}}} or nil
            }); eid = eid + 1

            -- Выход: Манипулятор + Красный сундук
            table.insert(bp_entities, {
                entity_number = eid, name = "bulk-inserter",
                position = {x = cur_x - 2, y = cur_y + 1}, direction = 4,
                quality = use_quality and q_name or nil
            }); eid = eid + 1

            table.insert(bp_entities, {
                entity_number = eid, name = "passive-provider-chest",
                position = {x = cur_x - 3, y = cur_y + 1},
                quality = use_quality and q_name or nil
            }); eid = eid + 1

            -- Если рецепт требует жидкость: ставим подземные трубы сзади завода
            if step.uses_fluid then
                table.insert(bp_entities, {
                    entity_number = eid, name = "pipe",
                    position = {x = cur_x + 2, y = cur_y}
                }); eid = eid + 1
            end

            -- Если планета Аквило: прокладываем тепловую трубу вдоль каждого станка
            if is_aquilo then
                for hy = -1, 2 do
                    table.insert(bp_entities, {
                        entity_number = eid, name = "heat-pipe",
                        position = {x = cur_x - 4, y = cur_y + hy}
                    }); eid = eid + 1
                end
            end

            -- Если включены Маяки: ставим маяк справа от станка
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

    -- 5. Контур Переработчиков (Upcycler / Ферма Качества)
    if state.use_upcycler and calc.upcycler_machines > 0 then
        local rec_entity = prototypes.entity["recycler"] and "recycler" or "assembling-machine-3"
        cur_x = cur_x + row_step_x
        cur_y = -34
        for i = 1, calc.upcycler_machines do
            if cur_y <= max_y then
                table.insert(bp_entities, {
                    entity_number = eid, name = rec_entity,
                    position = {x = cur_x, y = cur_y},
                    quality = use_quality and q_name or nil
                }); eid = eid + 1

                table.insert(bp_entities, {
                    entity_number = eid, name = "bulk-inserter",
                    position = {x = cur_x - 2, y = cur_y - 1}, direction = 12
                }); eid = eid + 1

                table.insert(bp_entities, {
                    entity_number = eid, name = "requester-chest",
                    position = {x = cur_x - 3, y = cur_y - 1}
                }); eid = eid + 1

                table.insert(bp_entities, {
                    entity_number = eid, name = "bulk-inserter",
                    position = {x = cur_x - 2, y = cur_y + 1}, direction = 4
                }); eid = eid + 1

                table.insert(bp_entities, {
                    entity_number = eid, name = "active-provider-chest",
                    position = {x = cur_x - 3, y = cur_y + 1}
                }); eid = eid + 1

                cur_y = cur_y + 4
            end
        end
    end

    -- 6. Выдача чертежа игроку (с защитной оберткой pcall для 100% надежности)
    if player.clear_cursor() then
        player.cursor_stack.set_stack({name = "blueprint", count = 1})
        local ok = pcall(function()
            player.cursor_stack.set_blueprint_entities(bp_entities)
        end)
        if not ok then
            -- Если версия игры не поддерживает расширенные поля фильтра, очищаем их и выдаем чистый чертеж
            for _, ent in ipairs(bp_entities) do ent.request_filters = nil end
            player.cursor_stack.set_blueprint_entities(bp_entities)
        end
        player.cursor_stack.set_blueprint_tiles(bp_tiles)
        player.cursor_stack.label = string.format("CB [%s/%s]: %s (%d/m +1%%)", planet_id, q_name, state.item, state.rate)
        player.print(string.format("[AutoCityBlock] Чертеж создан! Сущностей: %d | Планета: %s | Качество: %s", #bp_entities, planet_id, q_name))
    end
end

-- ============================================================================
-- ГРАФИЧЕСКИЙ ИНТЕРФЕЙС В СТИЛЕ HELMOD
-- ============================================================================
local function draw_helmod_gui(player)
    if player.gui.screen.cb_helmod_frame then
        player.gui.screen.cb_helmod_frame.destroy()
    end

    local state = get_state(player.index)
    run_calculation(player)
    local calc = state.last_calc

    local main_frame = player.gui.screen.add{
        type = "frame", name = "cb_helmod_frame",
        direction = "vertical", caption = "AutoCityBlock 1.0: Helmod & Space Age Planner"
    }
    main_frame.auto_center = true
    main_frame.style.minimal_width = 880

    -- Ряд 1: Предмет, Кол-во, Качество, Планета
    local top_bar = main_frame.add{type = "frame", style = "subheader_frame", direction = "horizontal"}
    top_bar.style.horizontally_stretchable = true
    top_bar.style.vertical_align = "center"
    top_bar.style.padding = 6

    top_bar.add{type = "label", caption = "Предмет:", style = "caption_label"}
    top_bar.add{type = "choose-elem-button", name = "cb_elem_item", elem_type = "item", item = state.item}

    top_bar.add{type = "label", caption = "  /мин (+1%):", style = "caption_label"}
    local rate_box = top_bar.add{type = "textfield", name = "cb_input_rate", text = tostring(state.rate), numeric = true}
    rate_box.style.width = 65

    top_bar.add{type = "label", caption = "  Качество:", style = "caption_label"}
    local q_items = {}
    for _, q in ipairs(QUALITIES) do table.insert(q_items, q.caption) end
    top_bar.add{type = "drop-down", name = "cb_drop_quality", items = q_items, selected_index = state.quality_index}

    top_bar.add{type = "label", caption = "  Планета:", style = "caption_label"}
    local p_items = {}
    for _, p in ipairs(PLANETS) do table.insert(p_items, p.caption) end
    top_bar.add{type = "drop-down", name = "cb_drop_planet", items = p_items, selected_index = state.planet_index}

    -- Ряд 2: Модули и чекбоксы (Маяки, Upcycler, Технологии мира, ЖД)
    local mod_bar = main_frame.add{type = "flow", direction = "horizontal"}
    mod_bar.style.padding = {6, 8, 6, 8}
    mod_bar.style.vertical_align = "center"

    mod_bar.add{type = "label", caption = "Модули в станках:", style = "bold_label"}
    local m_items = {}
    for _, m in ipairs(MODULE_MODES) do table.insert(m_items, m.caption) end
    mod_bar.add{type = "drop-down", name = "cb_drop_modules", items = m_items, selected_index = state.module_index}

    mod_bar.add{type = "empty-widget"}.style.width = 12
    mod_bar.add{type = "checkbox", name = "cb_chk_beacons", caption = "Ряды Маяков (Скорость 3)", state = state.use_beacons}
    mod_bar.add{type = "empty-widget"}.style.width = 12
    mod_bar.add{type = "checkbox", name = "cb_chk_upcycler", caption = "Ферма Качества (Upcycler)", state = state.use_upcycler}

    local opts_bar = main_frame.add{type = "flow", direction = "horizontal"}
    opts_bar.style.padding = {2, 8, 6, 8}
    opts_bar.add{type = "checkbox", name = "cb_chk_tech", caption = "Учитывать технологии и бонусы мира (force)", state = state.use_world_tech}
    opts_bar.add{type = "empty-widget"}.style.width = 16
    opts_bar.add{type = "checkbox", name = "cb_chk_rail", caption = "Генерировать ЖД-станции (Грузовые + Жидкостные) и комбинаторы", state = state.add_stations}

    -- Таблица Helmod
    local content_frame = main_frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}
    content_frame.style.padding = 8
    content_frame.style.horizontally_stretchable = true

    local scroll = content_frame.add{type = "scroll-pane", direction = "vertical"}
    scroll.style.maximal_height = 360
    scroll.style.horizontally_stretchable = true

    local tbl = scroll.add{type = "table", column_count = 6, draw_horizontal_lines = true, draw_vertical_lines = true}
    tbl.style.horizontally_stretchable = true
    tbl.style.cell_padding = 4

    local headers = {"Рецепт", "Станок + Маяки", "Заводов (Точно / Блок)", "Продуктивность", "Выход (/мин)", "Ингредиенты (/мин)"}
    for _, h in ipairs(headers) do
        local lbl = tbl.add{type = "label", caption = h, style = "bold_label"}
        lbl.style.minimal_width = 105
    end

    if calc and calc.steps then
        for _, step in ipairs(calc.steps) do
            local r_flow = tbl.add{type = "flow", direction = "horizontal"}
            r_flow.add{type = "sprite-button", sprite = "recipe/" .. step.recipe_name, style = "slot_button", enabled = false}
            r_flow.add{type = "label", caption = step.recipe_name}

            local m_flow = tbl.add{type = "flow", direction = "horizontal"}
            m_flow.add{type = "sprite-button", sprite = "item/" .. step.machine_name, style = "slot_button", enabled = false}
            m_flow.add{type = "label", caption = string.format("x%.1f ск.", step.speed)}

            tbl.add{
                type = "label",
                caption = string.format("%.2f -> [color=green][font=default-bold]%d шт.[/font][/color]", step.exact_machines, math.ceil(step.exact_machines))
            }

            tbl.add{type = "label", caption = string.format("+%d%%", math.floor(step.prod_bonus * 100 + 0.5))}

            local out_spr = is_fluid(step.item_name) and "fluid" or "item"
            tbl.add{type = "label", caption = string.format("[%s=%s] %.1f/м", out_spr, step.item_name, step.output_per_sec * 60)}

            local ing_flow = tbl.add{type = "flow", direction = "horizontal"}
            for _, ing in pairs(step.ingredients) do
                local spr = is_fluid(ing.name) and ("fluid/" .. ing.name) or ("item/" .. ing.name)
                ing_flow.add{
                    type = "sprite-button", sprite = spr,
                    number = math.ceil(step.crafts_per_sec * 60 * ing.amount),
                    style = "slot_button", enabled = false
                }
            end
        end
    end

    -- Нижняя сводка сырья для ЖД-станций
    local raw_frame = main_frame.add{type = "frame", style = "subheader_frame", direction = "horizontal"}
    raw_frame.style.horizontally_stretchable = true
    raw_frame.style.padding = 6
    raw_frame.add{type = "label", caption = "Входные ЖД станции (/мин): ", style = "bold_label"}

    if calc and calc.raw then
        for raw_name, raw_sec in pairs(calc.raw) do
            local spr = is_fluid(raw_name) and ("fluid/" .. raw_name) or ("item/" .. raw_name)
            raw_frame.add{
                type = "sprite-button", sprite = spr,
                number = math.ceil(raw_sec * 60),
                tooltip = string.format("%s: %.1f/мин (%s)", raw_name, raw_sec * 60, is_fluid(raw_name) and "Жидкостная ЖД" or "Грузовая ЖД"),
                style = "slot_button", enabled = false
            }
        end
    end

    local bottom_flow = main_frame.add{type = "flow", direction = "horizontal"}
    bottom_flow.style.padding = 6
    bottom_flow.add{type = "button", name = "cb_btn_recalc", caption = "Пересчитать матрицу"}
    bottom_flow.add{type = "button", name = "cb_btn_blueprint", caption = "Выдать чертеж Сити-Блока (+1%)", style = "confirm_button"}
    bottom_flow.add{type = "button", name = "cb_btn_close", caption = "Закрыть"}
end

commands.add_command("cb", "Открыть планер AutoCityBlock 1.0", function(event)
    local player = game.get_player(event.player_index)
    draw_helmod_gui(player)
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
    if event.element.name == "cb_elem_item" then
        local player = game.get_player(event.player_index)
        get_state(player.index).item = event.element.elem_value
        draw_helmod_gui(player)
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local name = event.element.name
    local player = game.get_player(event.player_index)
    local state = get_state(player.index)
    if name == "cb_drop_quality" then
        state.quality_index = event.element.selected_index
        draw_helmod_gui(player)
    elseif name == "cb_drop_planet" then
        state.planet_index = event.element.selected_index
        draw_helmod_gui(player)
    elseif name == "cb_drop_modules" then
        state.module_index = event.element.selected_index
        draw_helmod_gui(player)
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local name = event.element.name
    local player = game.get_player(event.player_index)
    local state = get_state(player.index)
    if name == "cb_chk_tech" then state.use_world_tech = event.element.state
    elseif name == "cb_chk_rail" then state.add_stations = event.element.state
    elseif name == "cb_chk_beacons" then state.use_beacons = event.element.state
    elseif name == "cb_chk_upcycler" then state.use_upcycler = event.element.state
    else return end
    draw_helmod_gui(player)
end)

script.on_event(defines.events.on_gui_click, function(event)
    local name = event.element.name
    local player = game.get_player(event.player_index)
    local frame = player.gui.screen.cb_helmod_frame
    if not frame then return end

    local state = get_state(player.index)
    local top_bar = frame.children[1]
    if top_bar and top_bar.cb_input_rate then
        state.rate = tonumber(top_bar.cb_input_rate.text) or 100
    end

    if name == "cb_btn_recalc" then
        draw_helmod_gui(player)
    elseif name == "cb_btn_blueprint" then
        run_calculation(player)
        build_city_block_blueprint(player)
        frame.destroy()
    elseif name == "cb_btn_close" then
        frame.destroy()
    end
end)
