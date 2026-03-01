function BNOSwarmGroupInit()
    storage.bno.warn_biter_attack = setGlobalSetting("bno-biter-swarm-attack", true, false)
	if (not storage.swarmGroup) then
		storage.swarmGroup = {}
	end    
end

function OnTickCheckSwarm()
    if storage.bno.warn_biter_attack then
        storage.swarmCheckTick = storage.swarmCheckTick or game.tick
        if (game.tick >= storage.swarmCheckTick) then
            BNOCleanGPSStack()
            storage.swarmCheckTick = game.tick + TICKS_PER_SECOND*2    -- check again in 2 seconds
        end
    end
end

-- Called on_tick to determine if the swarm has just started moving, and to send the ping.
-- also to remove the swarm from the stack if they don't move towards your main and when they die at your main.
function BNOCleanGPSStack()    
    if (storage.swarmGroup == nil) then
        storage.swarmGroup = {}
    end
    if (#storage.swarmGroup > 0) then
        -- Check once a second - not every tick - which is 1/60th of a second
--        for k,swarm in pairs(storage.swarmGroup) do    -- can't do this or we skip items
        for k=#storage.swarmGroup, 1, -1 do
            if (not storage.swarmGroup[k]) or (not storage.swarmGroup[k].group.valid) then
                if (storage.enable_oe_debug) then
                    log("REMOVING swarm tracking " .. k .. " they be dead")
                end
                table.remove(storage.swarmGroup,k)   -- end of swarm tracking
            else
                if (storage.swarmGroup[k]~=nil) then
                    if (storage.swarmGroup[k].group.state ~=nil) then
                        if (storage.enable_oe_debug) then
                            log  ("TICK - swarm " .. k ..":  group.command.type = " .. commandType(storage.swarmGroup[k].group.command.type) .. ", state: " .. groupState(storage.swarmGroup[k].group.state))
                        end
                        -- only do this once, for each group, and wait for them to start moving since every group will start with group_state.pathfinding.
                        -- the groups that never attack will immediately be removed from the stack
                        -- the groups that attack will eventually go to group_state.attacking_target, but first moving
                        if (storage.swarmGroup[k].group.state == defines.group_state.moving) then
                            if (not storage.swarmGroup[k].gpsSent) then
                                storage.swarmGroup[k].target_player.print(storage.swarmGroup[k].target_player.name .. ": Wave of " .. #storage.swarmGroup[k].group.members .. " biters incoming :" .. GetGPStext(storage.swarmGroup[k].startPosition), {sound=defines.print_sound.never})
                                storage.swarmGroup[k].target_player.play_sound { path = 'wave-coming' }
                                storage.swarmGroup[k].gpsSent=true   -- only send this ping once
                            end
                        end
                    end
                end
            end
        end
    end
end


-- called on_unit_group_finished_gathering
function CheckSwarm(group)

    -- Check validity
    if ((group == nil) or (group.command == nil) or (group.force.name ~= "enemy")) then
        log("OarcModifyEnemyGroup ignoring INVALID group/command")
        return
    end
    -- Make sure the attack is of a TYPE that we care about.
    if ((group.command.type == defines.command.attack) or 
        (group.command.type == defines.command.attack_area) or 
        (group.command.type == defines.command.build_base)) then
        log("CheckSwarm ignoring command TYPE=" .. commandType(group.command.type))
    else
        log("OarcModifyEnemyGroup ignoring command TYPE=" .. commandType(group.command.type))
        return
    end
    local destination = group.command.destination
    local distance = CHUNK_SIZE*3

    -- Find some enemies near the attack point.
    local target_entities = group.surface.find_entities_filtered{
                                            position=destination,
                                            radius=distance,
                                            force={"enemy", "neutral"},
                                            limit=50,
                                            invert=true}

    -- Search through them all to find anything with a last_user.
    local target_entity = nil                                   
    for _,target in ipairs(target_entities) do
        if (target.last_user ~= nil) then
            target_entity = target
            break
        end
    end
    -- Most common target will be a built entity with a "last_user"
    local target_player = target_entity.last_user

    -- Target could also be a player character (more rare)
    if (target_player == nil) and (target_entity.type == "character") then
        target_player = target_entity.player
    end

    -- Is the target player online or opted in for attacks while offline ? Then the attack can go through.
    if (target_player.connected) then --  or not storage.ocfg.offline_protect[target_player.index]) then
        if (storage.enable_oe_debug) then
            SendBroadcastMsg("Enemy group released (player): " .. GetGPStext(group.position) .. " Target: " .. GetGPStext(target_entity.position) .. " " .. target_player.name)
            log("OarcModifyEnemyGroup RELEASING enemy group since player " .. target_player.name .. " is ONLINE, " .. GetGPStext(group.position) .. " Target: " .. GetGPStext(target_entity.position))
        end
        configureSwarmPing(target_player, group)
        return
    end
    -- Find the shared spawn that the player is part of.
    -- This could be the own player's spawn (quite likely)
    local sharedSpawnOwnerName = FindPlayerSharedSpawn(target_player.name)


end    

-- adds the swarm/group that is ready to act, to tracking stack (storage.swarmGroup), one entry per swarm
-- we later validate every swarm to determine if we should ping, or just remove the swarm from the stack
-- storage variables
--	storage.swarmGroup	{target_player, group, startPosition}		
--          One stack for all players. When the group finishes gathering, we add them to this stack.
--			One entry per swarm

-- events
--	on_unit_group_finished_gathering		- swarm completed grouping and are acting
--	on_tick									- EVERY TICK this is called - where we track the swarm until they go to a moving state, 
--											when the gps tag is created
--	on_player_clicked_gps_tag				- previously sent GPS tag is clicked on
function configureSwarmPing(target_player, group)
     if (storage.ocfg.warn_biter_setting == nil) then
        storage.ocfg.warn_biter_setting = {}
        
        storage.ocfg.warn_biter_setting[target_player.index] = storage.ocfg.warn_biter_attack -- init individual setting to default
    end
    if (storage.ocfg.warn_biter_setting[target_player.index]) then
        local groupWithStartPosition = {}
        groupWithStartPosition.target_player = target_player
        groupWithStartPosition.startPosition=group.position
        groupWithStartPosition.group = group
        if ((storage.enable_oe_debug) and
            ((group.command.type == defines.command.attack) or 
                (group.command.type == defines.command.attack_area) or
                (group.command.type == defines.command.build_base))) then
            log("spawning swarm " .. GetGPStext(group.position) .. " for " .. target_player.name)
        end
        if ((group.command.type == defines.command.attack) or 
            (group.command.type == defines.command.attack_area)) then
            groupWithStartPosition.gpsSent=false    -- start of swarm tracking
            table.insert(storage.swarmGroup, groupWithStartPosition) -- later in on_player_clicked_gps_tag when the gps is clicked - we want to track the group                
        else
            if (storage.enable_oe_debug) then
                if (group.command.type == defines.command.build_base) then
                    log("The bastards are building a base " .. GetGPStext(group.position) .. target_player.name)
                    log(target_player.name .. "- bastards are building a base : " .. GetGPStext(group.position))
                else
                    if (group.command.type == defines.command.go_to_location) then
                        log(target_player.name .. " WTF - got this command - go_to_location " .. GetGPStext(group.position) .. " " .. target_player.name)
                    elseif (group.command.type == defines.command.wander) then
                        log(target_player.name .. " WTF - got this command - wander " .. GetGPStext(group.position) .. " " .. target_player.name)
                    elseif (group.command.type == defines.command.stop) then
                        log(target_player.name .. " WTF - got this command - stop " .. GetGPStext(group.position) .. " " .. target_player.name)
                    elseif (group.command.type == defines.command.flee) then
                        log(target_player.name .. " WTF - got this command - flee " .. GetGPStext(group.position) .. " " .. target_player.name)
                    end
                end
            end
        end
    end
end

function commandType(type)
    if      (type==defines.command.attack) then       
        return " attack"
    elseif  (type==defines.command.go_to_location) then
        return " go to location"
    elseif  (type==defines.command.compound) then
        return " compound"
    elseif  (type==defines.command.group) then
        return " group"
    elseif  (type==defines.command.attack_area) then
        return " attack area"
    elseif  (type==defines.command.wander) then
        return "wandering"
    elseif  (type==defines.command.flee) then
        return "flee"
    elseif  (type==defines.command.stop) then
        return "stop"
    elseif  (type==defines.command.build_base) then
        return "build base"
    else
        return "unknown"
    end
end

function groupState(state)
    if      (state==defines.group_state.gathering) then       
        return " gathering"
    elseif  (state==defines.group_state.moving) then
        return " moving"
    elseif  (state==defines.group_state.attacking_distraction) then
        return " attacking distraction"
    elseif  (state==defines.group_state.attacking_target) then
        return " attacking target"
    elseif  (state==defines.group_state.finished) then
        return " finished"
    elseif  (state==defines.group_state.pathfinding) then
        return " path finding"
    elseif  (state==defines.group_state.wandering_in_group) then
        return " wandering in group"
    else
        return "unknown"
    end
end

-- Set a value either based on MOD settings or config.lua
-- only use isYesNo true if field returns "yes" and needs conversion to boolean
function setGlobalSetting(settings_startup_name, default_val, isYesNo)
    isYesNo = isYesNo or false    -- set default to false
    local tmpVal = default_val
    local settingVal = settings.startup[settings_startup_name].value
    if ((settingVal ~= "use config.lua setting")) then
        if (isYesNo) then
            tmpVal = settingVal=="yes"      -- convert Yes/No into boolean
        else
            tmpVal = settingVal
        end
    end   
    log("setGlobalSetting: " .. settings_startup_name .. ", isYesNo? " .. tostring(isYesNo) .. ", input value: " .. tostring(default_val) .. ", output value: " .. tostring(tmpVal))
    return tmpVal
end