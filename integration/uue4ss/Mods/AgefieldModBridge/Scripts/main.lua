local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("agefield_mod_bridge")
cyberfox1337x.function_signature("bootstrap")
local UEHelpers = require("UEHelpers")

local BRIDGE_VERSION = "1.5.5"
local MONEY_TARGET = 9999.0
local SPEED_TARGET = 1200.0
local LOW_GRAVITY_TARGET = 0.25
local NO_CLIP_INPUT_POLL_MILLISECONDS = 50
local NO_CLIP_TAP_PULSE_TICKS = 2
local NO_CLIP_DIRECTION_CHANGE_DEGREES = 5.0
local NO_CLIP_VELOCITY_READBACK_TOLERANCE = 1.0
local TELEPORT_STAGE_HEIGHT = 2500.0
local TELEPORT_TRACE_DEPTH = 4000.0
local GROUND_CLEARANCE = 3.0
local TELEPORT_WORLD_LOAD_CHECKS = 5
local TELEPORT_TRACE_ATTEMPTS = 6
local TELEPORT_DWELL_CHECKS = 5
local EXPECTED_GAMEPLAY_WORLD_NAME = "World /Game/Level/Main/Game_Level.Game_Level"
local BRIDGE_ROOT = (os.getenv("TEMP") or os.getenv("TMP") or ".") .. "/AgefieldHighModMenuBridge"
local COMMAND_PATH = BRIDGE_ROOT .. "/command.txt"
local RESPONSE_PATH = BRIDGE_ROOT .. "/response.txt"
local READY_PATH = BRIDGE_ROOT .. "/ready.txt"
local BOOT_ID = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local CAPABILITY_TOKENS = {
    "toggle:God Mode",
    "toggle:Infinite Stamina",
    "toggle:Unlimited Money",
    "toggle:No Detection",
    "toggle:Invisible Mode",
    "toggle:Super Speed",
    "toggle:No Clip",
    "toggle:Free Roam",
    "toggle:Low Gravity",
    "quick-action:Heal Player",
    "quick-action:Clear Wanted",
    "quick-action:Restore Spawned Items",
    "teleport:Agefield High",
    "teleport:Home",
    "teleport:Police Station",
    "teleport:General Store",
    "teleport:Cloth Shop",
    "teleport:Return",
    "spawn-item:Burger",
    "spawn-item:Candy",
    "spawn-item:Soda",
    "spawn-item:Blue Power Bar",
    "spawn-item:Red Power Bar",
    "spawn-item:Hot Dog",
    "spawn-item:Newspaper",
    "spawn-item:Parent Note",
    "set-time:*",
    "reset-player:*",
}
local CAPABILITY_SET = {}
for _, capability in ipairs(CAPABILITY_TOKENS) do
    CAPABILITY_SET[capability] = true
end
local CAPABILITIES = table.concat(CAPABILITY_TOKENS, ",")

local function make_input_key(unreal_key_name)
    local ok, key_name = pcall(function() return UEHelpers.FindOrAddFName(unreal_key_name) end)
    if not ok or key_name == nil then return nil end
    return { KeyName = key_name }
end

local FORWARD_INPUT_KEY = make_input_key("W")
local BACKWARD_INPUT_KEY = make_input_key("S")
local LEFT_INPUT_KEY = make_input_key("A")
local RIGHT_INPUT_KEY = make_input_key("D")
local SPACE_INPUT_KEY = make_input_key("SpaceBar")
local DESCEND_INPUT_KEY = make_input_key("Z")

local state = {
    god_mode = false,
    infinite_stamina = false,
    unlimited_money = false,
    invisible_mode = false,
    no_detection = false,
    super_speed = false,
    no_clip = false,
    free_roam = false,
    low_gravity = false,
}

local last_command_id = ""
local last_ready_second = -1
local speed_baseline = nil
local gravity_baseline = nil
local money_baseline = nil
local teleport_baseline = nil
local last_grounded_location = nil
local last_grounded_rotation = nil
local pending_teleport_validation = nil
local last_teleport_status = "idle"
local flight_input_status = "pending"
local flight_velocity_status = "idle"
local last_flight_status = "idle"
local last_movement_status = "unknown"
local last_world_status = "unknown"
local flight_direction_proofs = {
    forward = "untested",
    backward = "untested",
    left = "untested",
    right = "untested",
    diagonal = "untested",
    up = "untested",
    down = "untested",
}
local previous_flight_signature = "idle"
local previous_flight_travel_yaw = nil
local active_flight_sample = nil
local no_clip_input_owner = nil
local no_clip_flight_speed = nil
local flight_edge_pulses = {
    forward = 0,
    backward = 0,
    left = 0,
    right = 0,
    up = 0,
    down = 0,
}
local spawned_item_counts = {}
local god_hook_ready = false
local scheduler = {
    no_clip_loop_running = false,
    no_clip_game_thread_pending = false,
    no_clip_stop_requested = false,
    no_clip_recovery_stop_required = false,
    no_clip_ticks = 0,
    no_clip_game_thread_scheduled = 0,
    no_clip_velocity_writes = 0,
    no_clip_idle_stops = 0,
    no_clip_overlap_skips = 0,
    no_clip_transient_waits = 0,
    no_clip_controller_waits = 0,
    no_clip_hard_world_exits = 0,
    enforcement_loop_running = false,
    enforcement_game_thread_pending = false,
    enforcement_ticks = 0,
    enforcement_game_thread_scheduled = 0,
    enforcement_overlap_skips = 0,
    teleport_loop_running = false,
    teleport_game_thread_pending = false,
    teleport_ticks = 0,
    teleport_game_thread_scheduled = 0,
    teleport_overlap_skips = 0,
    ground_status_generation = 0,
    ground_status_checks = 0,
}
local ensure_active_mod_enforcement
local ensure_teleport_monitor
local schedule_grounded_status_refresh
local apply_no_clip

-- These transforms were returned by the official build's live
-- UMapWorldSubsystem::GetAllMarkers() contract. They are intentionally not
-- aliases for the unproven room-level destinations from the visual mock-up.
cyberfox1337x.function_signature("world_controls")
local TELEPORT_DESTINATIONS = {
    ["Agefield High"] = { x = -14122.449, y = 14185.141, z = -282.133, trace_height = 250.0 },
    ["Home"] = {
        x = -33012.611,
        y = 36110.430,
        z = 24.394,
        stable_location = { X = -32633.694, Y = 36569.839, Z = 702.272 },
    },
    ["Police Station"] = { x = 3395.970, y = -1060.638, z = 88.459, trace_height = 120.0 },
    ["General Store"] = { x = 29324.742, y = 1717.978, z = 88.459, trace_height = 180.0 },
    ["Cloth Shop"] = { x = 29281.805, y = 25780.486, z = 88.459, trace_height = 150.0 },
}
cyberfox1337x.function_signature("inventory_quick_actions")
local ITEM_CLASSES = {
    ["Burger"] = { class_name = "BP_Item_Burger_C", package = "/Game/Blueprints/Items/Consumable/Healing/BP_Item_Burger" },
    ["Candy"] = { class_name = "BP_Item_Candy_C", package = "/Game/Blueprints/Items/Consumable/Healing/BP_Item_Candy" },
    ["Soda"] = { class_name = "BP_Item_DisableStaminaConsuption_SODA_C", package = "/Game/Blueprints/Items/Consumable/Healing/BP_Item_DisableStaminaConsuption_SODA" },
    ["Blue Power Bar"] = { class_name = "BP_Item_PowerBarBlue_C", package = "/Game/Blueprints/Items/Consumable/Healing/BP_Item_PowerBarBlue" },
    ["Red Power Bar"] = { class_name = "BP_Item_PowerBarRed_C", package = "/Game/Blueprints/Items/Consumable/Healing/BP_Item_PowerBarRed" },
    ["Hot Dog"] = { class_name = "BP_Item_Hotdog_C", package = "/Game/Blueprints/Items/Consumable/Healing/BP_Item_Hotdog" },
    ["Newspaper"] = { class_name = "BP_Item_Newspaper_C", package = "/Game/Blueprints/Items/Document/BP_Item_Newspaper" },
    ["Parent Note"] = { class_name = "BP_Item_ParentNote_C", package = "/Game/Blueprints/Items/Consumable/Utils/BP_Item_ParentNote" },
}

local function log(message)
    print(string.format("[AgefieldModBridge] %s\n", tostring(message)))
end

local function sanitize(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

cyberfox1337x.function_signature("keybind_transport")
local function write_atomic(path, contents)
    local temporary_path = path .. ".tmp"
    local file = io.open(temporary_path, "w")
    if file then
        file:write(contents)
        file:flush()
        file:close()
        os.remove(path)
        if os.rename(temporary_path, path) ~= nil then return true end
    end
    local fallback = io.open(path, "w")
    if not fallback then return false end
    fallback:write(contents)
    fallback:flush()
    fallback:close()
    return true
end

local function read_fields(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local fields = {}
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then fields[key] = value end
    end
    file:close()
    return fields
end

local function active_feature_list()
    local active = {}
    for name, enabled in pairs(state) do
        if enabled then table.insert(active, name) end
    end
    table.sort(active)
    return table.concat(active, ",")
end

local function has_active_mods()
    return state.god_mode or state.infinite_stamina or state.unlimited_money
        or state.invisible_mode or state.no_detection or state.super_speed
        or state.no_clip or state.free_roam or state.low_gravity
end

local function write_ready()
    local now = os.time()
    if now == last_ready_second then return end
    last_ready_second = now
    return write_atomic(READY_PATH, table.concat({
        "protocol=1",
        "boot_id=" .. BOOT_ID,
        "version=" .. BRIDGE_VERSION,
        "heartbeat=" .. tostring(now),
        "god_hook=" .. (god_hook_ready and "1" or "0"),
        "capabilities=" .. CAPABILITIES,
        "active=" .. active_feature_list(),
        "teleport_status=" .. sanitize(last_teleport_status),
        "flight_input=" .. sanitize(flight_input_status),
        "flight_velocity=" .. sanitize(flight_velocity_status),
        "flight_status=" .. sanitize(last_flight_status),
        "movement_status=" .. sanitize(last_movement_status),
        "world_status=" .. sanitize(last_world_status),
        "scheduler=" .. string.format(
            "no_clip=%s;enforcement=%s;teleport=%s;pending=%d",
            scheduler.no_clip_loop_running and "active" or "idle",
            scheduler.enforcement_loop_running and "active" or "idle",
            scheduler.teleport_loop_running and "active" or "idle",
            (scheduler.no_clip_game_thread_pending and 1 or 0)
                + (scheduler.enforcement_game_thread_pending and 1 or 0)
                + (scheduler.teleport_game_thread_pending and 1 or 0)
        ),
        "scheduler_counts=" .. string.format(
            "no_clip_ticks=%d;no_clip_game_thread=%d;no_clip_velocity_writes=%d;no_clip_idle_stops=%d;no_clip_overlap_skips=%d;no_clip_transient_waits=%d;no_clip_controller_waits=%d;no_clip_hard_world_exits=%d;enforcement_ticks=%d;enforcement_game_thread=%d;enforcement_overlap_skips=%d;teleport_ticks=%d;teleport_game_thread=%d;teleport_overlap_skips=%d;ground_checks=%d",
            scheduler.no_clip_ticks,
            scheduler.no_clip_game_thread_scheduled,
            scheduler.no_clip_velocity_writes,
            scheduler.no_clip_idle_stops,
            scheduler.no_clip_overlap_skips,
            scheduler.no_clip_transient_waits,
            scheduler.no_clip_controller_waits,
            scheduler.no_clip_hard_world_exits,
            scheduler.enforcement_ticks,
            scheduler.enforcement_game_thread_scheduled,
            scheduler.enforcement_overlap_skips,
            scheduler.teleport_ticks,
            scheduler.teleport_game_thread_scheduled,
            scheduler.teleport_overlap_skips,
            scheduler.ground_status_checks
        ),
        "flight_forward_proof=" .. sanitize(flight_direction_proofs.forward),
        "flight_backward_proof=" .. sanitize(flight_direction_proofs.backward),
        "flight_left_proof=" .. sanitize(flight_direction_proofs.left),
        "flight_right_proof=" .. sanitize(flight_direction_proofs.right),
        "flight_diagonal_proof=" .. sanitize(flight_direction_proofs.diagonal),
        "flight_up_proof=" .. sanitize(flight_direction_proofs.up),
        "flight_down_proof=" .. sanitize(flight_direction_proofs.down),
        "",
    }, "\n"))
end

local function write_response(id, accepted, message, readback)
    write_atomic(RESPONSE_PATH, table.concat({
        "protocol=1",
        "boot_id=" .. BOOT_ID,
        "id=" .. sanitize(id),
        "accepted=" .. (accepted and "1" or "0"),
        "message=" .. sanitize(message),
        "readback=" .. sanitize(readback),
        "",
    }, "\n"))
end

local function is_live_object(object)
    if not object then return false end
    local ok, address = pcall(function() return object:GetAddress() end)
    return ok and type(address) == "number" and address > 0
end

cyberfox1337x.function_signature("player_controls")
local function find_player()
    local ok, player = pcall(function() return FindFirstOf("BP_PlayerCharacter_C") end)
    if not ok or not is_live_object(player) then return nil end
    return player
end

local function gameplay_world_status()
    local world_ok, world = pcall(UEHelpers.GetWorld)
    if not world_ok or not is_live_object(world) then return false, "world-unavailable" end
    local name_ok, world_name = pcall(function() return world:GetFullName() end)
    if not name_ok then return false, "world-name-unavailable" end
    local normalized_name = tostring(world_name):lower()
    if normalized_name:find("mainmenu", 1, true) or normalized_name:find("main_menu", 1, true) then
        return false, "menu;world=" .. tostring(world_name)
    end

    local map_ok, map_system = pcall(function() return FindFirstOf("MapWorldSubsystem") end)
    if not map_ok or not is_live_object(map_system) then
        return false, "gameplay-subsystem-unavailable;world=" .. tostring(world_name)
    end
    local same_world_ok, same_world = pcall(function()
        local subsystem_world = map_system:GetWorld()
        return is_live_object(subsystem_world) and subsystem_world:GetAddress() == world:GetAddress()
    end)
    if not same_world_ok or same_world ~= true then
        return false, "gameplay-subsystem-world-mismatch;world=" .. tostring(world_name)
    end
    return true, "gameplay;world=" .. tostring(world_name)
end

local function flight_world_status()
    local world_ok, world = pcall(UEHelpers.GetWorld)
    if not world_ok or not is_live_object(world) then return false, "world-unavailable" end
    local name_ok, world_name = pcall(function() return world:GetFullName() end)
    if not name_ok then return false, "world-name-unavailable" end
    if tostring(world_name) == EXPECTED_GAMEPLAY_WORLD_NAME then
        return true, "gameplay;world=" .. tostring(world_name)
    end
    local normalized_name = tostring(world_name):lower()
    if normalized_name:find("mainmenu", 1, true) or normalized_name:find("main_menu", 1, true) then
        return false, "menu;world=" .. tostring(world_name)
    end
    return false, "non-gameplay;world=" .. tostring(world_name)
end

local function names_expected_gameplay_world(world_status)
    return type(world_status) == "string"
        and world_status:find(EXPECTED_GAMEPLAY_WORLD_NAME, 1, true) ~= nil
end

local function is_confirmed_no_clip_world_exit(world_status)
    if type(world_status) ~= "string" then return false end
    if world_status:sub(1, 5) == "menu;" then return true end
    return world_status:find(";world=", 1, true) ~= nil
        and not names_expected_gameplay_world(world_status)
end

local function find_time_system()
    local ok, system = pcall(function() return FindFirstOf("TimeWorldSubsystem") end)
    if not ok or not is_live_object(system) then return nil end
    return system
end

local function find_authority_system()
    local ok, system = pcall(function() return FindFirstOf("AuthoritySubsystem") end)
    if not ok or not is_live_object(system) then return nil end
    return system
end

local function get_movement(player)
    local ok, movement = pcall(function() return player.CharacterMovement end)
    if not ok or not is_live_object(movement) then return nil end
    return movement
end

local function array_like_count(container)
    if container == nil then return nil end
    if type(container) == "table" then return #container end
    local method_ok, method_count = pcall(function() return container:GetArrayNum() end)
    if method_ok and type(method_count) == "number" then return method_count end
    local length_ok, length_count = pcall(function() return #container end)
    if length_ok and type(length_count) == "number" then return length_count end
    return nil
end

local function resolve_item_class(item_definition)
    local object_path = item_definition.package .. "." .. item_definition.class_name
    local found_ok, class_object = pcall(function() return StaticFindObject(object_path) end)
    if not found_ok or not is_live_object(class_object) then
        local loaded_ok = pcall(function() LoadAsset(item_definition.package) end)
        if not loaded_ok then return nil end
        found_ok, class_object = pcall(function() return StaticFindObject(object_path) end)
    end
    if not found_ok or not is_live_object(class_object) or not class_object:IsClass() then return nil end
    if class_object:GetFName():ToString() ~= item_definition.class_name then return nil end
    return class_object
end

local function item_count(player, class_object)
    local count_ok, items = pcall(function() return player:GetAllItemOfClass(class_object) end)
    if not count_ok then return nil end
    return array_like_count(items)
end

local function copy_vector(vector)
    return { X = tonumber(vector.X), Y = tonumber(vector.Y), Z = tonumber(vector.Z) }
end

local function copy_rotator(rotator)
    return {
        Pitch = tonumber(rotator.Pitch),
        Yaw = tonumber(rotator.Yaw),
        Roll = tonumber(rotator.Roll),
    }
end

local function horizontal_distance(first, second)
    local delta_x = first.X - second.X
    local delta_y = first.Y - second.Y
    return math.sqrt((delta_x * delta_x) + (delta_y * delta_y))
end

local function format_location(location)
    return string.format("X=%.1f Y=%.1f Z=%.1f", location.X, location.Y, location.Z)
end

local function set_flight_status(status)
    if last_flight_status == status then return end
    last_flight_status = status
    last_ready_second = -1
end

local function read_input_key(controller, input_key)
    if not input_key then return nil, "input-key-unavailable" end
    local ok, is_down = pcall(function() return controller:IsInputKeyDown(input_key) end)
    if not ok then return nil, tostring(is_down) end
    return is_down == true
end

local function normalize_angle_degrees(angle)
    local normalized = angle % 360.0
    if normalized > 180.0 then normalized = normalized - 360.0 end
    return normalized
end

local function normalize_vector(vector)
    local magnitude = math.sqrt((vector.X * vector.X) + (vector.Y * vector.Y) + (vector.Z * vector.Z))
    if magnitude <= 0.0001 then return nil end
    return { X = vector.X / magnitude, Y = vector.Y / magnitude, Z = vector.Z / magnitude }
end

local function vector_dot(first, second)
    return (first.X * second.X) + (first.Y * second.Y) + (first.Z * second.Z)
end

local function horizontal_unit_vector(vector)
    return normalize_vector({ X = vector.X, Y = vector.Y, Z = 0.0 })
end

local function horizontal_direction_from_control(control_rotation, forward_axis, right_axis)
    if forward_axis == 0 and right_axis == 0 then return nil, tonumber(control_rotation.Yaw) end
    local yaw_radians = math.rad(tonumber(control_rotation.Yaw))
    local forward = { X = math.cos(yaw_radians), Y = math.sin(yaw_radians), Z = 0.0 }
    local right = { X = -math.sin(yaw_radians), Y = math.cos(yaw_radians), Z = 0.0 }
    local direction = normalize_vector({
        X = (forward.X * forward_axis) + (right.X * right_axis),
        Y = (forward.Y * forward_axis) + (right.Y * right_axis),
        Z = 0.0,
    })
    local travel_yaw = tonumber(control_rotation.Yaw) + math.deg(math.atan(right_axis, forward_axis))
    return direction, normalize_angle_degrees(travel_yaw)
end

local function angle_distance_degrees(first, second)
    return math.abs(normalize_angle_degrees(first - second))
end

local function stop_flight_movement(player, movement)
    player:ConsumeMovementInputVector()
    movement:StopMovementImmediately()
    flight_velocity_status = "stopped"
end

local function capture_no_clip_flight_speed(movement)
    local ok, speed = pcall(function() return tonumber(movement.MaxFlySpeed) end)
    if not ok or not speed or speed ~= speed or speed <= 0.0 or speed > 100000.0 then
        return nil, "invalid MaxFlySpeed readback"
    end
    return speed
end

local function apply_continuous_flight_velocity(movement, desired_direction)
    local speed = no_clip_flight_speed
    if not speed or speed <= 0.0 then return false, "flight speed was not captured" end

    local target_velocity = {
        X = desired_direction.X * speed,
        Y = desired_direction.Y * speed,
        Z = desired_direction.Z * speed,
    }
    local previous_ok, previous_velocity = pcall(function() return copy_vector(movement.Velocity) end)
    local write_ok, readback_or_failure = pcall(function()
        movement.Velocity = target_velocity
        local readback = copy_vector(movement.Velocity)
        local maximum_error = math.max(
            math.abs(readback.X - target_velocity.X),
            math.abs(readback.Y - target_velocity.Y),
            math.abs(readback.Z - target_velocity.Z)
        )
        if maximum_error > NO_CLIP_VELOCITY_READBACK_TOLERANCE then
            error(string.format("Velocity readback differed by %.3f", maximum_error))
        end
        return readback
    end)
    if not write_ok then
        if previous_ok then pcall(function() movement.Velocity = previous_velocity end) end
        pcall(function() movement:StopMovementImmediately() end)
        flight_velocity_status = "error;reason=" .. sanitize(readback_or_failure)
        return false, tostring(readback_or_failure)
    end

    flight_velocity_status = string.format(
        "active;speed=%.1f;velocity[X=%.1f Y=%.1f Z=%.1f]",
        speed,
        readback_or_failure.X,
        readback_or_failure.Y,
        readback_or_failure.Z
    )
    scheduler.no_clip_velocity_writes = scheduler.no_clip_velocity_writes + 1
    return true
end

local function release_no_clip_input_owner()
    local owner = no_clip_input_owner
    no_clip_input_owner = nil
    if not owner or not owner.owns_ignore or not is_live_object(owner.controller) then
        flight_input_status = "released;owned-ignore=false"
        return true
    end
    local ok, failure = pcall(function() owner.controller:SetIgnoreMoveInput(false) end)
    if not ok then
        flight_input_status = "error;release-failed"
        log("No Clip input release failed: " .. tostring(failure))
        return false, tostring(failure)
    end
    flight_input_status = "released;owned-ignore=true"
    return true
end

local function acquire_no_clip_input_owner(controller)
    local address = controller:GetAddress()
    if no_clip_input_owner and no_clip_input_owner.address == address then return true end
    -- A different controller means the previous world/controller lifetime has
    -- ended. Drop that reference without dereferencing it during recovery.
    no_clip_input_owner = nil

    local ok, failure = pcall(function()
        local already_ignored = controller:IsMoveInputIgnored() == true
        if not already_ignored then controller:SetIgnoreMoveInput(true) end
        no_clip_input_owner = {
            address = address,
            controller = controller,
            owns_ignore = not already_ignored,
        }
        flight_input_status = "captured;owns-ignore=" .. tostring(not already_ignored)
    end)
    if not ok then return false, tostring(failure) end
    return true
end

local function classify_flight_direction(sample)
    if sample.forward_axis > 0 and sample.right_axis == 0 and sample.vertical_axis == 0 then return "forward" end
    if sample.forward_axis < 0 and sample.right_axis == 0 and sample.vertical_axis == 0 then return "backward" end
    if sample.right_axis < 0 and sample.forward_axis == 0 and sample.vertical_axis == 0 then return "left" end
    if sample.right_axis > 0 and sample.forward_axis == 0 and sample.vertical_axis == 0 then return "right" end
    if sample.forward_axis ~= 0 and sample.right_axis ~= 0 and sample.vertical_axis == 0 then return "diagonal" end
    if sample.vertical_axis > 0 and sample.forward_axis == 0 and sample.right_axis == 0 then return "up" end
    if sample.vertical_axis < 0 and sample.forward_axis == 0 and sample.right_axis == 0 then return "down" end
    return "combined"
end

local function finish_flight_sample(player)
    local sample = active_flight_sample
    active_flight_sample = nil
    if not sample or sample.address ~= player:GetAddress() then return end

    local after = copy_vector(player:K2_GetActorLocation())
    local proof_direction = classify_flight_direction(sample)
    local delta = {
        X = after.X - sample.before.X,
        Y = after.Y - sample.before.Y,
        Z = after.Z - sample.before.Z,
    }
    local proof
    local passed
    if proof_direction == "up" or proof_direction == "down" then
        passed = (proof_direction == "up" and delta.Z > 5.0) or (proof_direction == "down" and delta.Z < -5.0)
        proof = string.format(
            "verified;direction=%s;before_z=%.1f;after_z=%.1f;delta_z=%.1f;passed=%s",
            proof_direction,
            sample.before.Z,
            after.Z,
            delta.Z,
            tostring(passed)
        )
    else
        local actual_direction = horizontal_unit_vector(delta)
        local actor_forward = horizontal_unit_vector(player:GetActorForwardVector())
        local expected_dot = actual_direction and sample.expected_horizontal
            and vector_dot(actual_direction, sample.expected_horizontal) or -1.0
        local facing_dot = actual_direction and actor_forward and vector_dot(actual_direction, actor_forward) or -1.0
        local distance = math.sqrt((delta.X * delta.X) + (delta.Y * delta.Y))
        passed = proof_direction ~= "combined" and distance > 5.0 and expected_dot >= 0.75 and facing_dot >= 0.75
        proof = string.format(
            "verified;direction=%s;before[%s];after[%s];distance=%.1f;expected_dot=%.3f;facing_dot=%.3f;passed=%s",
            proof_direction,
            format_location(sample.before),
            format_location(after),
            distance,
            expected_dot,
            facing_dot,
            tostring(passed)
        )
    end
    if proof_direction ~= "combined"
        and (passed or flight_direction_proofs[proof_direction] == "untested") then
        flight_direction_proofs[proof_direction] = proof
    end
    set_flight_status(proof)
end

local function read_flight_axes(controller)
    local key_states = {}
    local keys = {
        forward = FORWARD_INPUT_KEY,
        backward = BACKWARD_INPUT_KEY,
        left = LEFT_INPUT_KEY,
        right = RIGHT_INPUT_KEY,
        up = SPACE_INPUT_KEY,
        down = DESCEND_INPUT_KEY,
    }
    for name, input_key in pairs(keys) do
        local is_down, failure = read_input_key(controller, input_key)
        if is_down == nil then return nil, failure end
        local remaining_pulse_ticks = flight_edge_pulses[name] or 0
        if not is_down and remaining_pulse_ticks > 0 then is_down = true end
        if remaining_pulse_ticks > 0 then flight_edge_pulses[name] = remaining_pulse_ticks - 1 end
        key_states[name] = is_down
    end
    return {
        forward = (key_states.forward and 1 or 0) - (key_states.backward and 1 or 0),
        right = (key_states.right and 1 or 0) - (key_states.left and 1 or 0),
        vertical = (key_states.up and 1 or 0) - (key_states.down and 1 or 0),
    }
end

local function clear_flight_edge_pulses()
    for name in pairs(flight_edge_pulses) do flight_edge_pulses[name] = 0 end
end

local function flight_signature(axes)
    return string.format("forward=%d;right=%d;vertical=%d", axes.forward, axes.right, axes.vertical)
end

local function disable_no_clip_for_confirmed_world_exit(world_status)
    state.no_clip = false
    no_clip_input_owner = nil
    no_clip_flight_speed = nil
    scheduler.no_clip_stop_requested = false
    scheduler.no_clip_recovery_stop_required = false
    scheduler.no_clip_hard_world_exits = scheduler.no_clip_hard_world_exits + 1
    clear_flight_edge_pulses()
    previous_flight_signature = "idle"
    previous_flight_travel_yaw = nil
    active_flight_sample = nil
    flight_input_status = "released;reason=confirmed-menu-transition"
    flight_velocity_status = "stopped;reason=confirmed-menu-transition"
    set_flight_status("disabled;reason=confirmed-menu-transition")
    last_movement_status = "unknown;reason=confirmed-menu-transition"
    last_world_status = world_status
end

local function poll_no_clip_flight_input()
    scheduler.no_clip_ticks = scheduler.no_clip_ticks + 1
    if not state.no_clip then
        scheduler.no_clip_stop_requested = false
        scheduler.no_clip_recovery_stop_required = false
        previous_flight_signature = "idle"
        previous_flight_travel_yaw = nil
        active_flight_sample = nil
        scheduler.no_clip_loop_running = false
        return true
    end
    if scheduler.no_clip_stop_requested and not scheduler.no_clip_game_thread_pending then
        scheduler.no_clip_stop_requested = false
        scheduler.no_clip_loop_running = false
        return true
    end

    -- An input-edge-armed monitor only needs exact world identity. Full
    -- subsystem discovery stays at activation/enforcement boundaries.
    local gameplay_ready, world_status = flight_world_status()
    last_world_status = world_status
    if not gameplay_ready then
        if is_confirmed_no_clip_world_exit(world_status) then
            -- A confirmed menu transition ends No Clip. Never dereference the
            -- old controller because Unreal may already be destroying it.
            disable_no_clip_for_confirmed_world_exit(world_status)
            scheduler.no_clip_loop_running = false
            return true
        end

        -- MapWorldSubsystem and controller discovery can miss for a poll while
        -- the same Game_Level remains live. Keep the requested state and loop;
        -- a later poll reacquires current objects without retaining a Pawn.
        scheduler.no_clip_transient_waits = scheduler.no_clip_transient_waits + 1
        scheduler.no_clip_recovery_stop_required = true
        previous_flight_signature = "idle"
        previous_flight_travel_yaw = nil
        active_flight_sample = nil
        flight_input_status = "waiting-for-gameplay"
        set_flight_status("waiting;reason=" .. sanitize(world_status))
        last_movement_status = "unknown;reason=transient-gameplay-unavailable"
        return false
    end

    if scheduler.no_clip_game_thread_pending then
        scheduler.no_clip_overlap_skips = scheduler.no_clip_overlap_skips + 1
        return false
    end
    scheduler.no_clip_game_thread_pending = true
    scheduler.no_clip_game_thread_scheduled = scheduler.no_clip_game_thread_scheduled + 1

    ExecuteInGameThread(function()
        scheduler.no_clip_game_thread_pending = false
        local ok, error_message = pcall(function()
            -- The scheduled closure may run after a disable command. Recheck
            -- before touching input ownership, collision, or movement mode.
            if not state.no_clip then return end
            local player = find_player()
            local movement = player and get_movement(player) or nil
            local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
            if not player or not movement or not controller_ok or not is_live_object(controller) then
                scheduler.no_clip_controller_waits = scheduler.no_clip_controller_waits + 1
                if player and movement then stop_flight_movement(player, movement) end
                clear_flight_edge_pulses()
                previous_flight_signature = "idle"
                previous_flight_travel_yaw = nil
                active_flight_sample = nil
                flight_input_status = "waiting-for-player"
                set_flight_status("waiting-for-player")
                return
            end

            if scheduler.no_clip_recovery_stop_required then
                stop_flight_movement(player, movement)
                scheduler.no_clip_recovery_stop_required = false
            end

            local input_acquired, input_failure = acquire_no_clip_input_owner(controller)
            if not input_acquired then
                flight_input_status = "error"
                set_flight_status("error;reason=" .. sanitize(input_failure))
                return
            end
            local axes, axes_failure = read_flight_axes(controller)
            if not axes then
                flight_input_status = "error"
                set_flight_status("error;reason=" .. sanitize(axes_failure))
                return
            end
            flight_input_status = "ready;mode=exclusive;tap-pulse=100ms"

            local signature = flight_signature(axes)
            local has_input = axes.forward ~= 0 or axes.right ~= 0 or axes.vertical ~= 0
            local control_rotation = copy_rotator(controller:GetControlRotation())
            local horizontal_direction, travel_yaw = horizontal_direction_from_control(
                control_rotation,
                axes.forward,
                axes.right
            )
            local facing_changed = has_input and previous_flight_travel_yaw ~= nil
                and angle_distance_degrees(travel_yaw, previous_flight_travel_yaw) >= NO_CLIP_DIRECTION_CHANGE_DEGREES
            local direction_changed = signature ~= previous_flight_signature or facing_changed
            if direction_changed then
                if previous_flight_signature ~= "idle" then
                    finish_flight_sample(player)
                    stop_flight_movement(player, movement)
                end
                if has_input then
                    active_flight_sample = {
                        address = player:GetAddress(),
                        before = copy_vector(player:K2_GetActorLocation()),
                        forward_axis = axes.forward,
                        right_axis = axes.right,
                        vertical_axis = axes.vertical,
                        expected_horizontal = horizontal_direction,
                    }
                    set_flight_status(string.format(
                        "active;%s;before[%s]",
                        signature,
                        format_location(active_flight_sample.before)
                    ))
                end
                previous_flight_signature = signature
                previous_flight_travel_yaw = has_input and travel_yaw or nil
            end

            if not has_input then
                scheduler.no_clip_idle_stops = scheduler.no_clip_idle_stops + 1
                scheduler.no_clip_stop_requested = true
                flight_input_status = "idle;monitor=stopping"
                return
            end
            scheduler.no_clip_stop_requested = false
            if not direction_changed then return end

            player:SetActorEnableCollision(false)
            movement:SetMovementMode(5, 0)
            player:K2_SetActorRotation({ Pitch = 0.0, Yaw = travel_yaw, Roll = 0.0 }, false)

            local desired_direction = normalize_vector({
                X = horizontal_direction and horizontal_direction.X or 0.0,
                Y = horizontal_direction and horizontal_direction.Y or 0.0,
                Z = axes.vertical,
            })
            if desired_direction then
                local velocity_applied, velocity_failure = apply_continuous_flight_velocity(
                    movement,
                    desired_direction
                )
                if not velocity_applied then
                    state.no_clip = false
                    stop_flight_movement(player, movement)
                    flight_velocity_status = "error;reason=" .. sanitize(velocity_failure)
                    release_no_clip_input_owner()
                    clear_flight_edge_pulses()
                    previous_flight_signature = "idle"
                    previous_flight_travel_yaw = nil
                    active_flight_sample = nil
                    no_clip_flight_speed = nil
                    apply_no_clip(player)
                    last_movement_status = state.free_roam
                        and "flying;collision=false;reason=no-clip-velocity-contract-failed"
                        or "walking;collision=true;reason=velocity-contract-failed"
                    set_flight_status("disabled;reason=velocity-contract-failed;detail=" .. sanitize(velocity_failure))
                    if not state.free_roam then schedule_grounded_status_refresh() end
                end
            end
        end)
        if not ok then
            flight_input_status = "error"
            set_flight_status("error;reason=" .. sanitize(error_message))
            log("No Clip input failed: " .. tostring(error_message))
        end
    end)
    return false
end

local function ensure_no_clip_input_loop()
    if not state.no_clip then return end
    scheduler.no_clip_stop_requested = false
    if scheduler.no_clip_loop_running then return end
    scheduler.no_clip_loop_running = true
    LoopAsync(NO_CLIP_INPUT_POLL_MILLISECONDS, poll_no_clip_flight_input)
end

schedule_grounded_status_refresh = function()
    scheduler.ground_status_generation = scheduler.ground_status_generation + 1
    local generation = scheduler.ground_status_generation
    local attempts = 0
    local schedule_next
    schedule_next = function()
        ExecuteWithDelay(250, function()
            if generation ~= scheduler.ground_status_generation then return end
            ExecuteInGameThread(function()
                if generation ~= scheduler.ground_status_generation then return end
                attempts = attempts + 1
                scheduler.ground_status_checks = scheduler.ground_status_checks + 1
                local player = find_player()
                local movement = player and get_movement(player) or nil
                if not player or not movement then
                    last_movement_status = "unknown;ground-check=player-unavailable"
                    return
                end
                local location = copy_vector(player:K2_GetActorLocation())
                if state.no_clip or state.free_roam then
                    last_movement_status = "flying;collision=false;location=" .. format_location(location)
                    return
                end
                if movement:IsMovingOnGround() then
                    last_grounded_location = location
                    last_grounded_rotation = copy_rotator(player:K2_GetActorRotation())
                    last_movement_status = "grounded;collision=true;location=" .. format_location(location)
                    last_ready_second = -1
                    return
                end
                last_movement_status = "walking;grounded=false;collision=true;location=" .. format_location(location)
                if attempts < 8 then schedule_next() end
            end)
        end)
    end
    schedule_next()
end

local function location_matches_landing(actual, expected)
    return horizontal_distance(actual, expected) <= 75.0 and math.abs(actual.Z - expected.Z) <= 75.0
end

local function movement_uses_flying_mode()
    return state.no_clip or state.free_roam
end

local function teleport_actor(player, location, rotation)
    local accepted = player:K2_TeleportTo(location, rotation)
    local movement = get_movement(player)
    if accepted == true and movement then
        movement:StopMovementImmediately()
        movement:SetMovementMode(movement_uses_flying_mode() and 5 or 1, 0)
        player:SetActorEnableCollision(not movement_uses_flying_mode())
    end
    local readback = copy_vector(player:K2_GetActorLocation())
    return accepted == true, readback
end

local function vector_is_finite(vector)
    local read_ok, components = pcall(function() return { vector.X, vector.Y, vector.Z } end)
    if not read_ok then return false end
    for _, component in ipairs(components) do
        if type(component) ~= "number" or component ~= component or math.abs(component) == math.huge then return false end
    end
    return true
end

local function get_capsule_half_height(player)
    local capsule_ok, capsule = pcall(function() return player.CapsuleComponent end)
    if not capsule_ok or not is_live_object(capsule) then return nil end
    local half_height = tonumber(capsule:GetScaledCapsuleHalfHeight())
    if not half_height or half_height <= 0.0 then return nil end
    return half_height
end

local function trace_grounded_landing(player, marker)
    local system_library = UEHelpers.GetKismetSystemLibrary()
    local half_height = get_capsule_half_height(player)
    if not is_live_object(system_library) or not half_height then return nil, "trace-prerequisite-unavailable" end
    local trace_start = {
        X = marker.x,
        Y = marker.y,
        -- The staged actor loads the destination partition. The trace itself
        -- starts near the map marker so it finds the intended street/floor,
        -- not the top of a tall building above that marker.
        Z = marker.z + marker.trace_height,
    }
    local trace_end = {
        X = marker.x,
        Y = marker.y,
        Z = marker.z - TELEPORT_TRACE_DEPTH,
    }
    local hit_result = {}
    local transparent = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }
    local trace_ok, was_hit = pcall(function()
        return system_library:LineTraceSingle(
            player,
            trace_start,
            trace_end,
            0,
            false,
            {},
            0,
            hit_result,
            true,
            transparent,
            transparent,
            0.0
        )
    end)
    if not trace_ok or was_hit ~= true then return nil, "blocking-floor-not-found" end
    if not vector_is_finite(hit_result.ImpactPoint) or not vector_is_finite(hit_result.ImpactNormal) then
        return nil, "invalid-trace-hit"
    end
    local impact = copy_vector(hit_result.ImpactPoint)
    local normal = copy_vector(hit_result.ImpactNormal)
    if normal.Z < 0.55 then return nil, "trace-hit-not-walkable" end
    return {
        X = marker.x,
        Y = marker.y,
        Z = impact.Z + half_height + GROUND_CLEARANCE,
    }, string.format("trace-impact-z=%.1f normal-z=%.2f capsule-half-height=%.1f", impact.Z, normal.Z, half_height)
end

local function stage_teleport(player, location, rotation)
    local accepted = player:K2_TeleportTo(location, rotation)
    local movement = get_movement(player)
    if accepted == true and movement then
        movement:StopMovementImmediately()
        player:SetActorEnableCollision(false)
        movement:SetMovementMode(5, 0)
    end
    return accepted == true, copy_vector(player:K2_GetActorLocation())
end

local function queue_teleport_validation(player, label, expected, fallback_location, fallback_rotation, clear_baseline_on_success)
    pending_teleport_validation = {
        address = player:GetAddress(),
        label = label,
        expected = copy_vector(expected),
        fallback_location = copy_vector(fallback_location),
        fallback_rotation = copy_rotator(fallback_rotation),
        clear_baseline_on_success = clear_baseline_on_success == true,
        response_id = nil,
        phase = "dwell",
        checks = 0,
    }
    last_teleport_status = "pending;label=" .. label .. ";location=" .. format_location(expected)
end

local function handle_teleport(detail)
    local player = find_player()
    if not player then return false, "Start or resume the official game before teleporting." end

    local player_address = player:GetAddress()
    if detail == "Return" then
        if not teleport_baseline or teleport_baseline.address ~= player_address then
            teleport_baseline = nil
            return false, "No teleport return point is available."
        end
        local accepted, readback = teleport_actor(player, teleport_baseline.location, teleport_baseline.rotation)
        if not accepted or not location_matches_landing(readback, teleport_baseline.location) then
            return false, "Return was rejected; the saved return point was kept for retry.", format_location(readback)
        end
        queue_teleport_validation(
            player,
            "Return",
            teleport_baseline.location,
            readback,
            teleport_baseline.rotation,
            true
        )
        return true, "Return landing validation is in progress.", format_location(readback), true
    end

    local marker = TELEPORT_DESTINATIONS[detail]
    if not marker then return false, "Unsupported command." end
    local original_location = copy_vector(player:K2_GetActorLocation())
    local original_rotation = copy_rotator(player:K2_GetActorRotation())
    local movement = get_movement(player)
    local origin_is_grounded = movement and movement:IsMovingOnGround()
    local fallback_location = origin_is_grounded and original_location or last_grounded_location
    local fallback_rotation = origin_is_grounded and original_rotation or last_grounded_rotation
    if not fallback_location or not fallback_rotation then
        fallback_location = copy_vector(TELEPORT_DESTINATIONS["Home"].stable_location)
        fallback_rotation = original_rotation
    end

    if not teleport_baseline or teleport_baseline.address ~= player_address then
        teleport_baseline = {
            address = player_address,
            location = copy_vector(fallback_location),
            rotation = copy_rotator(fallback_rotation),
        }
    end

    if marker.stable_location then
        local destination = copy_vector(marker.stable_location)
        local accepted, readback = teleport_actor(player, destination, original_rotation)
        if not accepted or not location_matches_landing(readback, destination) then
            teleport_actor(player, fallback_location, fallback_rotation)
            return false, "Teleport was rejected and the last grounded location was restored.", format_location(readback)
        end
        queue_teleport_validation(player, detail, destination, fallback_location, fallback_rotation, false)
        return true, string.format("%s landing validation is in progress.", detail), string.format(
            "origin[%s] destination[%s] ground[verified-stable]",
            format_location(original_location),
            format_location(readback)
        ), true
    end

    local stage_location = { X = marker.x, Y = marker.y, Z = marker.z + TELEPORT_STAGE_HEIGHT }
    local accepted, readback = stage_teleport(player, stage_location, original_rotation)
    if not accepted or not location_matches_landing(readback, stage_location) then
        teleport_actor(player, fallback_location, fallback_rotation)
        return false, "Teleport staging was rejected and the last grounded location was restored.", format_location(readback)
    end
    pending_teleport_validation = {
        address = player_address,
        label = detail,
        marker = marker,
        stage_location = stage_location,
        expected = stage_location,
        fallback_location = copy_vector(fallback_location),
        fallback_rotation = copy_rotator(fallback_rotation),
        clear_baseline_on_success = false,
        response_id = nil,
        phase = "loading",
        checks = 0,
    }
    last_teleport_status = "loading;label=" .. detail .. ";location=" .. format_location(readback)
    return true, string.format("%s landing validation is in progress.", detail), string.format(
        "origin[%s] stage[%s]",
        format_location(original_location),
        format_location(readback)
    ), true
end

local function apply_perception(player)
    local ok, perception = pcall(function() return player.AIPerceptionStimuliSource end)
    if not ok or not is_live_object(perception) then return false end
    if state.invisible_mode or state.no_detection or state.free_roam then
        perception:UnregisterFromPerceptionSystem()
    else
        perception:RegisterWithPerceptionSystem()
    end
    return true
end

local function set_god_mode(player, enabled)
    if enabled and not god_hook_ready then
        return false, "God Mode is unavailable because the damage hook did not load."
    end
    state.god_mode = enabled
    player:EnableNotifyDeath(not enabled)
    if enabled then player:Heal(player:GetMaxHealth()) end
    return true, string.format("God Mode %s. Health %.0f/%.0f.", enabled and "enabled" or "disabled", player:GetHealth(), player:GetMaxHealth())
end

local function set_infinite_stamina(player, enabled)
    state.infinite_stamina = enabled
    player:SetCanConsumeStamina(not enabled)
    player:EnableConsumeStamina(not enabled)
    if enabled then player:SetStamina(player:GetMaxStamina()) end
    return true, string.format("Infinite Stamina %s. Stamina %.0f/%.0f.", enabled and "enabled" or "disabled", player:GetStamina(), player:GetMaxStamina())
end

local function set_currency_exact(player, target_balance)
    local current_balance = player:GetCurrency()
    local difference = target_balance - current_balance
    if difference > 0 then
        player:AddCurrency(difference)
    elseif difference < 0 then
        player:RemoveCurrency(-difference)
    end
    return player:GetCurrency()
end

local function set_unlimited_money(player, enabled)
    local address = player:GetAddress()
    if enabled then
        if not money_baseline or money_baseline.address ~= address then
            money_baseline = { address = address, balance = math.max(0.0, player:GetCurrency()) }
        end
        set_currency_exact(player, MONEY_TARGET)
    elseif money_baseline and money_baseline.address == address then
        set_currency_exact(player, money_baseline.balance)
    end
    state.unlimited_money = enabled
    return true, string.format("Unlimited Money %s. Balance %.0f.", enabled and "enabled" or "disabled", player:GetCurrency())
end

local function set_super_speed(player, enabled)
    local movement = get_movement(player)
    if not movement then return false, "Super Speed is unavailable until the player movement component is loaded." end
    local address = movement:GetAddress()
    if enabled then
        if not speed_baseline or speed_baseline.address ~= address then
            speed_baseline = {
                address = address,
                walk = movement.MaxWalkSpeed,
                crouched = movement.MaxWalkSpeedCrouched,
                fly = movement.MaxFlySpeed,
            }
        end
        movement.MaxWalkSpeed = SPEED_TARGET
        movement.MaxWalkSpeedCrouched = SPEED_TARGET * 0.5
        movement.MaxFlySpeed = SPEED_TARGET
    elseif speed_baseline and speed_baseline.address == address then
        movement.MaxWalkSpeed = speed_baseline.walk
        movement.MaxWalkSpeedCrouched = speed_baseline.crouched
        movement.MaxFlySpeed = speed_baseline.fly
    end
    state.super_speed = enabled
    return true, string.format("Super Speed %s. Walk speed %.0f.", enabled and "enabled" or "disabled", movement.MaxWalkSpeed)
end

local function set_invisible_mode(player, enabled)
    state.invisible_mode = enabled
    player:SetActorHiddenInGame(enabled)
    if not apply_perception(player) then
        state.invisible_mode = false
        player:SetActorHiddenInGame(false)
        return false, "Invisible Mode is unavailable until the perception component is loaded."
    end
    return true, string.format("Invisible Mode %s.", enabled and "enabled" or "disabled")
end

local function set_no_detection(player, enabled)
    state.no_detection = enabled
    if not apply_perception(player) then
        state.no_detection = false
        return false, "No Detection is unavailable until the perception component is loaded."
    end
    if enabled or state.free_roam then
        local authority = find_authority_system()
        if not authority then
            state.no_detection = false
            apply_perception(player)
            return false, "No Detection is unavailable until the authority subsystem is loaded."
        end
        authority:ClearSuspectLevel()
    end
    return true, string.format("No Detection %s.", enabled and "enabled" or "disabled")
end

apply_no_clip = function(player)
    local movement = get_movement(player)
    if not movement then return false, "No Clip is unavailable until the player movement component is loaded." end
    local effective_enabled = state.no_clip or state.free_roam
    player:SetActorEnableCollision(not effective_enabled)
    if not effective_enabled then stop_flight_movement(player, movement) end
    movement:SetMovementMode(effective_enabled and 5 or 1, 0)
    return true
end

local function set_no_clip(player, enabled)
    local previous = state.no_clip
    if enabled then
        local gameplay_ready, world_status = gameplay_world_status()
        last_world_status = world_status
        if not gameplay_ready and not names_expected_gameplay_world(world_status) then
            return false, "No Clip requires the loaded offline gameplay world."
        end
        local movement = get_movement(player)
        if not movement then return false, "No Clip is unavailable until the player movement component is loaded." end
        local captured_speed, speed_failure = capture_no_clip_flight_speed(movement)
        if not captured_speed then return false, "No Clip flight speed validation failed: " .. tostring(speed_failure) end
        no_clip_flight_speed = captured_speed
        flight_velocity_status = string.format("armed;speed=%.1f", captured_speed)
    end
    state.no_clip = enabled
    local applied, failure = apply_no_clip(player)
    if not applied then
        state.no_clip = previous
        if not previous then no_clip_flight_speed = nil end
        return false, failure
    end
    if enabled then
        local movement = get_movement(player)
        if movement then stop_flight_movement(player, movement) end
        flight_velocity_status = string.format("armed;speed=%.1f", no_clip_flight_speed)
        clear_flight_edge_pulses()
        local controller_ok, controller = pcall(UEHelpers.GetPlayerController)
        local input_acquired, input_failure = false, "player-controller-unavailable"
        if controller_ok and is_live_object(controller) then
            input_acquired, input_failure = acquire_no_clip_input_owner(controller)
        end
        if not input_acquired then
            release_no_clip_input_owner()
            state.no_clip = previous
            if not previous then no_clip_flight_speed = nil end
            apply_no_clip(player)
            return false, "No Clip input capture failed: " .. tostring(input_failure)
        end
        last_movement_status = "flying;collision=false"
        scheduler.no_clip_stop_requested = false
        scheduler.no_clip_recovery_stop_required = false
        set_flight_status("armed;monitor=key-edge;wasd=control-relative;space=up;z=down")
    else
        if active_flight_sample then finish_flight_sample(player) end
        local movement = get_movement(player)
        if movement then stop_flight_movement(player, movement) end
        no_clip_flight_speed = nil
        release_no_clip_input_owner()
        clear_flight_edge_pulses()
        previous_flight_signature = "idle"
        previous_flight_travel_yaw = nil
        scheduler.no_clip_stop_requested = false
        scheduler.no_clip_recovery_stop_required = false
        last_movement_status = "walking;ground-check=pending;collision=true"
        if not state.free_roam then schedule_grounded_status_refresh() end
    end
    return true, string.format("No Clip %s.", enabled and "enabled" or "disabled")
end

local function set_free_roam(player, enabled)
    local movement = get_movement(player)
    local authority = find_authority_system()
    if not movement or (enabled and not authority) then
        return false, "Free Roam requires the loaded movement and authority systems."
    end

    local previous = state.free_roam
    state.free_roam = enabled
    if not apply_perception(player) then
        state.free_roam = previous
        apply_perception(player)
        return false, "Free Roam requires the loaded perception system."
    end
    local applied, failure = apply_no_clip(player)
    if not applied then
        state.free_roam = previous
        apply_perception(player)
        return false, failure
    end
    if enabled then authority:ClearSuspectLevel() end
    return true, string.format(
        "Free Roam %s. Collision %s, wanted level %s.",
        enabled and "enabled" or "disabled",
        (state.no_clip or state.free_roam) and "disabled" or "enabled",
        tostring(authority and authority:GetSuspectLevel() or 0)
    )
end

local function set_low_gravity(player, enabled)
    local movement = get_movement(player)
    if not movement then return false, "Low Gravity requires the loaded movement component." end
    local address = movement:GetAddress()
    if enabled then
        if not gravity_baseline or gravity_baseline.address ~= address then
            gravity_baseline = { address = address, scale = tonumber(movement.GravityScale) }
        end
        movement.GravityScale = LOW_GRAVITY_TARGET
    elseif gravity_baseline and gravity_baseline.address == address then
        movement.GravityScale = gravity_baseline.scale
    elseif state.low_gravity then
        return false, "Low Gravity could not restore because the player movement component changed."
    end
    state.low_gravity = enabled
    return true, string.format("Low Gravity %s. Gravity scale %.2f.", enabled and "enabled" or "disabled", movement.GravityScale)
end

local function reset_supported_player_state(player)
    state.god_mode = false
    state.infinite_stamina = false
    state.unlimited_money = false
    state.invisible_mode = false
    state.no_detection = false
    state.no_clip = false
    state.free_roam = false
    if active_flight_sample then finish_flight_sample(player) end
    release_no_clip_input_owner()
    clear_flight_edge_pulses()
    previous_flight_signature = "idle"
    previous_flight_travel_yaw = nil
    no_clip_flight_speed = nil
    player:EnableNotifyDeath(true)
    player:SetCanConsumeStamina(true)
    player:EnableConsumeStamina(true)
    player:SetStamina(player:GetMaxStamina())
    player:Heal(player:GetMaxHealth())
    player:SetActorHiddenInGame(false)
    player:SetActorEnableCollision(true)
    apply_perception(player)
    local movement = get_movement(player)
    if movement then
        stop_flight_movement(player, movement)
        movement:SetMovementMode(1, 0)
    end
    if state.super_speed then set_super_speed(player, false) end
    state.super_speed = false
    if state.low_gravity then set_low_gravity(player, false) end
    state.low_gravity = false
    schedule_grounded_status_refresh()
    return true, string.format("Supported player mods reset. Health %.0f/%.0f, stamina %.0f/%.0f.", player:GetHealth(), player:GetMaxHealth(), player:GetStamina(), player:GetMaxStamina())
end

local function handle_toggle(detail, enabled)
    local player = find_player()
    if not player then return false, "Start or resume the official game before using player mods." end
    if detail == "God Mode" then return set_god_mode(player, enabled) end
    if detail == "Infinite Stamina" then return set_infinite_stamina(player, enabled) end
    if detail == "Unlimited Money" then return set_unlimited_money(player, enabled) end
    if detail == "Invisible Mode" then return set_invisible_mode(player, enabled) end
    if detail == "No Detection" then return set_no_detection(player, enabled) end
    if detail == "Super Speed" then return set_super_speed(player, enabled) end
    if detail == "No Clip" then return set_no_clip(player, enabled) end
    if detail == "Free Roam" then return set_free_roam(player, enabled) end
    if detail == "Low Gravity" then return set_low_gravity(player, enabled) end
    return false, "Unsupported command."
end

local function handle_quick_action(detail)
    local player = find_player()
    if not player then return false, "Start or resume the official game before using quick actions." end
    if detail == "Heal Player" then
        player:Heal(player:GetMaxHealth())
        return true, string.format("Player healed to %.0f/%.0f.", player:GetHealth(), player:GetMaxHealth())
    end
    if detail == "Clear Wanted" then
        local authority = find_authority_system()
        if not authority then return false, "Clear Wanted is unavailable until the authority subsystem is loaded." end
        authority:ClearSuspectLevel()
        return true, string.format("Wanted level cleared. Current level: %s.", tostring(authority:GetSuspectLevel()))
    end
    if detail == "Restore Spawned Items" then
        local removed = 0
        for item_detail, recorded_count in pairs(spawned_item_counts) do
            local class_object = resolve_item_class(ITEM_CLASSES[item_detail])
            if not class_object then return false, "A spawned item class is no longer loaded; no further items were changed." end
            local before = item_count(player, class_object)
            if before == nil then return false, "Spawned item count could not be read safely." end
            local attempts = math.min(recorded_count, before)
            for _ = 1, attempts do player:RemoveItemByClass(class_object, true) end
            local after = item_count(player, class_object)
            if after == nil or after ~= before - attempts then
                return false, "Spawned item restoration stopped because item-count read-back did not match."
            end
            removed = removed + attempts
            spawned_item_counts[item_detail] = nil
        end
        return true, string.format("Restored spawned items. Removed %d menu-added item(s).", removed)
    end
    return false, "Unsupported command."
end

local function handle_spawn_item(detail)
    local player = find_player()
    if not player then return false, "Start or resume the official game before spawning items." end
    local item_definition = ITEM_CLASSES[detail]
    if not item_definition then return false, "Unsupported command." end
    local class_object = resolve_item_class(item_definition)
    if not class_object then return false, "The verified item class is not loaded in the current level." end
    local before = item_count(player, class_object)
    if before == nil then return false, "Item count could not be read safely." end
    local accepted = player:AddItemByClass(class_object)
    local after = item_count(player, class_object)
    if accepted ~= true or after ~= before + 1 then
        return false, "The game rejected the item or its count did not increase."
    end
    spawned_item_counts[detail] = (spawned_item_counts[detail] or 0) + 1
    return true, string.format("Spawned %s. Count %d.", detail, after), string.format("before=%d after=%d", before, after)
end

local function parse_display_time(detail)
    local hour, minute, period = detail:match("^(%d%d):(%d%d) ([AP]M)$")
    hour, minute = tonumber(hour), tonumber(minute)
    if not hour or not minute or hour < 1 or hour > 12 or minute < 0 or minute > 59 then return nil end
    if period == "AM" then
        if hour == 12 then hour = 0 end
    elseif hour ~= 12 then
        hour = hour + 12
    end
    return hour, minute
end

local function handle_command(command)
    if command.protocol ~= "1" or command.boot_id ~= BOOT_ID then
        return false, "The mod menu session changed. Retry the command."
    end
    local action = command.action or ""
    local detail = command.detail or ""
    if pending_teleport_validation then return false, "A teleport landing is still validating." end
    if not CAPABILITY_SET[action .. ":" .. detail] and not CAPABILITY_SET[action .. ":*"] then
        return false, "Unsupported command."
    end
    if command.action == "toggle" then
        if command.enabled ~= "1" and command.enabled ~= "0" then return false, "Invalid toggle state." end
        return handle_toggle(command.detail or "", command.enabled == "1")
    end
    if command.action == "quick-action" then return handle_quick_action(command.detail or "") end
    if command.action == "teleport" then return handle_teleport(command.detail or "") end
    if command.action == "spawn-item" then return handle_spawn_item(command.detail or "") end
    if command.action == "set-time" then
        local hour, minute = parse_display_time(command.detail or "")
        if not hour then return false, "Invalid time value." end
        local time_system = find_time_system()
        if not time_system then return false, "Time controls are unavailable until the time subsystem is loaded." end
        local day = time_system:GetDay()
        time_system:SetTime(day, hour, minute)
        return true, string.format("Time set to day %d, %02d:%02d.", time_system:GetDay(), time_system:GetHour(), time_system:GetMinute())
    end
    if command.action == "reset-player" then
        local player = find_player()
        if not player then return false, "Start or resume the official game before resetting player mods." end
        return reset_supported_player_state(player)
    end
    return false, "Unsupported command."
end

local function poll_command()
    write_ready()
    local command = read_fields(COMMAND_PATH)
    if not command or not command.id or command.id == last_command_id then return false end
    last_command_id = command.id
    ExecuteInGameThread(function()
        local ok, accepted, message, readback, deferred = pcall(handle_command, command)
        if not ok then
            log("command failed: " .. tostring(accepted))
            write_response(command.id, false, "The game rejected this command safely.", tostring(accepted))
            return
        end
        if deferred == true and accepted == true then
            if not pending_teleport_validation then
                write_response(command.id, false, "Teleport validation could not start.", "")
                return
            end
            pending_teleport_validation.response_id = command.id
            if ensure_teleport_monitor then ensure_teleport_monitor() end
            if ensure_active_mod_enforcement then ensure_active_mod_enforcement() end
            write_ready()
            return
        end
        write_response(command.id, accepted == true, message or "Command completed.", readback or "")
        if accepted == true and ensure_active_mod_enforcement then ensure_active_mod_enforcement() end
        write_ready()
    end)
    return false
end

local function enforce_active_mods()
    scheduler.enforcement_ticks = scheduler.enforcement_ticks + 1
    if not has_active_mods() then
        scheduler.enforcement_loop_running = false
        return true
    end
    if scheduler.enforcement_game_thread_pending then
        scheduler.enforcement_overlap_skips = scheduler.enforcement_overlap_skips + 1
        return false
    end
    scheduler.enforcement_game_thread_pending = true
    scheduler.enforcement_game_thread_scheduled = scheduler.enforcement_game_thread_scheduled + 1
    ExecuteInGameThread(function()
        scheduler.enforcement_game_thread_pending = false
        local ok, error_message = pcall(function()
            if state.no_clip then
                local flight_ready, world_status = flight_world_status()
                last_world_status = world_status
                if not flight_ready and is_confirmed_no_clip_world_exit(world_status) then
                    disable_no_clip_for_confirmed_world_exit(world_status)
                    return
                end
            end
            local player = find_player()
            if not player then return end
            if state.god_mode then
                player:EnableNotifyDeath(false)
                player:Heal(player:GetMaxHealth())
            end
            if state.infinite_stamina then
                player:SetCanConsumeStamina(false)
                player:EnableConsumeStamina(false)
                player:SetStamina(player:GetMaxStamina())
            end
            if state.unlimited_money and player:GetCurrency() < MONEY_TARGET then set_currency_exact(player, MONEY_TARGET) end
            if state.super_speed then set_super_speed(player, true) end
            if state.no_clip or state.free_roam then
                local gameplay_ready = gameplay_world_status()
                if gameplay_ready then
                    player:SetActorEnableCollision(false)
                    local movement = get_movement(player)
                    if movement then movement:SetMovementMode(5, 0) end
                end
            end
            if state.low_gravity then
                local movement = get_movement(player)
                if movement then movement.GravityScale = LOW_GRAVITY_TARGET end
            end
            if state.invisible_mode then player:SetActorHiddenInGame(true) end
            if state.invisible_mode or state.no_detection or state.free_roam then apply_perception(player) end
            if state.no_detection or state.free_roam then
                local authority = find_authority_system()
                if authority then authority:ClearSuspectLevel() end
            end
        end)
        if not ok then log("enforcement failed: " .. tostring(error_message)) end
    end)
    return false
end

ensure_active_mod_enforcement = function()
    if not has_active_mods() or scheduler.enforcement_loop_running then return end
    scheduler.enforcement_loop_running = true
    LoopAsync(500, enforce_active_mods)
end

local function monitor_teleport_landing()
    scheduler.teleport_ticks = scheduler.teleport_ticks + 1
    if not pending_teleport_validation then
        scheduler.teleport_loop_running = false
        return true
    end
    if scheduler.teleport_game_thread_pending then
        scheduler.teleport_overlap_skips = scheduler.teleport_overlap_skips + 1
        return false
    end
    scheduler.teleport_game_thread_pending = true
    scheduler.teleport_game_thread_scheduled = scheduler.teleport_game_thread_scheduled + 1
    ExecuteInGameThread(function()
        scheduler.teleport_game_thread_pending = false
        local ok, error_message = pcall(function()
            if not pending_teleport_validation then return end
            local player = find_player()
            local movement = player and get_movement(player) or nil
            if not player or not movement then return end

            local validation = pending_teleport_validation
            if validation.address ~= player:GetAddress() then
                last_teleport_status = "cancelled;reason=player-instance-changed"
                if validation.response_id then
                    write_response(validation.response_id, false, "Teleport cancelled because the player instance changed.", "")
                end
                pending_teleport_validation = nil
                return
            end

            validation.checks = validation.checks + 1
            local location = copy_vector(player:K2_GetActorLocation())

            if validation.phase == "loading" then
                local stage_drift = horizontal_distance(location, validation.stage_location)
                if stage_drift > 100.0 or math.abs(location.Z - validation.stage_location.Z) > 100.0 then
                    local restored, restored_location = teleport_actor(
                        player,
                        validation.fallback_location,
                        validation.fallback_rotation
                    )
                    last_teleport_status = string.format(
                        "restored;label=%s;reason=staging-drift;location=%s;accepted=%s",
                        validation.label,
                        format_location(restored_location),
                        tostring(restored)
                    )
                    if validation.response_id then
                        write_response(validation.response_id, false, "Teleport staging became unstable; the last grounded location was restored.", last_teleport_status)
                    end
                    pending_teleport_validation = nil
                    return
                end
                if validation.checks < TELEPORT_WORLD_LOAD_CHECKS then return end

                local landing, ground_readback = trace_grounded_landing(
                    player,
                    validation.marker
                )
                if not landing then
                    last_teleport_status = string.format(
                        "loading;label=%s;trace-attempt=%d;reason=%s",
                        validation.label,
                        validation.checks - TELEPORT_WORLD_LOAD_CHECKS + 1,
                        ground_readback
                    )
                    if validation.checks < TELEPORT_WORLD_LOAD_CHECKS + TELEPORT_TRACE_ATTEMPTS - 1 then return end
                    local restored, restored_location = teleport_actor(
                        player,
                        validation.fallback_location,
                        validation.fallback_rotation
                    )
                    last_teleport_status = string.format(
                        "restored;label=%s;reason=%s;location=%s;accepted=%s",
                        validation.label,
                        ground_readback,
                        format_location(restored_location),
                        tostring(restored)
                    )
                    if validation.response_id then
                        write_response(validation.response_id, false, "No stable ground loaded at the destination; the last grounded location was restored.", last_teleport_status)
                    end
                    pending_teleport_validation = nil
                    return
                end

                local landed, landing_readback = teleport_actor(player, landing, validation.fallback_rotation)
                if not landed or not location_matches_landing(landing_readback, landing) then
                    local restored, restored_location = teleport_actor(
                        player,
                        validation.fallback_location,
                        validation.fallback_rotation
                    )
                    last_teleport_status = string.format(
                        "restored;label=%s;reason=landing-rejected;location=%s;accepted=%s",
                        validation.label,
                        format_location(restored_location),
                        tostring(restored)
                    )
                    if validation.response_id then
                        write_response(validation.response_id, false, "The grounded landing was rejected; the last grounded location was restored.", last_teleport_status)
                    end
                    pending_teleport_validation = nil
                    return
                end
                validation.phase = "dwell"
                validation.expected = landing
                validation.ground_readback = ground_readback
                validation.checks = 0
                last_teleport_status = "dwell;label=" .. validation.label .. ";location=" .. format_location(landing_readback)
                return
            end

            local vertical_drop = validation.expected.Z - location.Z
            if vertical_drop > 200.0 then
                local restored, restored_location = teleport_actor(
                    player,
                    validation.fallback_location,
                    validation.fallback_rotation
                )
                last_teleport_status = string.format(
                    "restored;label=%s;reason=vertical-drop-%.1f;location=%s;accepted=%s",
                    validation.label,
                    vertical_drop,
                    format_location(restored_location),
                    tostring(restored)
                )
                if validation.response_id then
                    write_response(validation.response_id, false, "The landing became unstable; the last grounded location was restored.", last_teleport_status)
                end
                pending_teleport_validation = nil
                return
            end

            if validation.checks < TELEPORT_DWELL_CHECKS then return end

            local horizontal_drift = horizontal_distance(location, validation.expected)
            local vertical_drift = math.abs(location.Z - validation.expected.Z)
            local stable_mode = movement_uses_flying_mode() or movement:IsMovingOnGround()
            local stable = stable_mode and horizontal_drift <= 1500.0 and vertical_drift <= 400.0
            if stable then
                last_teleport_status = string.format(
                    "stable;label=%s;checks=%d;mode=%s;location=%s",
                    validation.label,
                    validation.checks,
                    movement_uses_flying_mode() and "flying" or "grounded",
                    format_location(location)
                )
                if not movement_uses_flying_mode() then
                    last_grounded_location = location
                    last_grounded_rotation = copy_rotator(player:K2_GetActorRotation())
                end
                if validation.clear_baseline_on_success then teleport_baseline = nil end
                if validation.response_id then
                    local message = validation.label == "Return"
                        and "Returned to the saved location and remained stable."
                        or string.format("Teleported to %s and remained stable.", validation.label)
                    write_response(validation.response_id, true, message, last_teleport_status .. ";ground=" .. tostring(validation.ground_readback or "verified-stable"))
                end
            else
                local restored, restored_location = teleport_actor(
                    player,
                    validation.fallback_location,
                    validation.fallback_rotation
                )
                last_teleport_status = string.format(
                    "restored;label=%s;reason=dwell-failed-grounded-%s-horizontal-%.1f-vertical-%.1f-after-%d-checks;location=%s;accepted=%s",
                    validation.label,
                    tostring(stable_mode),
                    horizontal_drift,
                    vertical_drift,
                    validation.checks,
                    format_location(restored_location),
                    tostring(restored)
                )
                if validation.response_id then
                    write_response(validation.response_id, false, "The destination was not grounded after the dwell check; the last grounded location was restored.", last_teleport_status)
                end
            end
            pending_teleport_validation = nil
        end)
        if not ok then
            last_teleport_status = "error;reason=" .. sanitize(error_message)
            if pending_teleport_validation and pending_teleport_validation.response_id then
                write_response(pending_teleport_validation.response_id, false, "Teleport validation failed safely.", last_teleport_status)
            end
            pending_teleport_validation = nil
            log("teleport monitor failed: " .. tostring(error_message))
        end
    end)
    return false
end

ensure_teleport_monitor = function()
    if not pending_teleport_validation or scheduler.teleport_loop_running then return end
    scheduler.teleport_loop_running = true
    LoopAsync(500, monitor_teleport_landing)
end

local hook_ok, hook_error = pcall(function()
    RegisterHook("/Script/Project_HighSchool.HealthComponent:OnTakeAnyDamage", function(self, _damaged_actor, damage)
        if not state.god_mode then return end
        local component = self:get()
        local player = find_player()
        if not is_live_object(component) or not player then return end
        local health_component = player.HealthComponent
        if is_live_object(health_component) and component:GetAddress() == health_component:GetAddress() then
            damage:set(0.0)
        end
    end)
end)
god_hook_ready = hook_ok
if not hook_ok then log("damage hook unavailable: " .. tostring(hook_error)) end

local flight_edge_bindings = {
    forward = Key.W,
    backward = Key.S,
    left = Key.A,
    right = Key.D,
    up = Key.SPACE,
    down = Key.Z,
}
for direction_name, input_key in pairs(flight_edge_bindings) do
    local captured_direction = direction_name
    local binding_ok, binding_error = pcall(function()
        RegisterKeyBind(input_key, function()
            if state.no_clip then
                flight_edge_pulses[captured_direction] = NO_CLIP_TAP_PULSE_TICKS
                ensure_no_clip_input_loop()
            end
        end)
    end)
    if not binding_ok then
        flight_input_status = "error;tap-binding=" .. captured_direction
        log("No Clip tap binding unavailable for " .. captured_direction .. ": " .. tostring(binding_error))
    end
end

log("loaded version " .. BRIDGE_VERSION .. " boot=" .. BOOT_ID)
if write_ready() == false then log("ready handshake write failed: " .. READY_PATH) end
LoopAsync(150, poll_command)
