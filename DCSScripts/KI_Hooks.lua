if not KI then
  KI = {}
end




KI.Hooks = {}

function KI.Hooks.DWMOnDepotResupplied(depot)
  local success, result = xpcall(function()

      env.info("KI.Hooks.DWMOnDepotResupplied called")

      KI.GameUtils.MessageCoalition(KI.Config.AllySide, "A convoy has successfully reached and resupplied " .. depot.Name .. "!", 30)
  end, function(err) env.info("KI.Hooks.DWMOnDepotResupplied - ERROR - " .. err) end)
end

function KI.Hooks.DWMOnSpawnGroup(moosegrp, fromdepot, todepot)
  local success, result = xpcall(function()

      env.info("KI.Hooks.DWMOnSpawnGroup called")

      -- the reason we dont store a referene to the moosegrp object or the depot object is that this data is exported to file.
      -- when it's exported the object is fragmented and methods lost, so when we read from file and respawn/reinit everything
      -- we can search and match on group name and depot name
      KI.Data.Convoys[moosegrp.GroupName] =
        {
          DestinationDepotName = todepot.Name
        }

      -- save the group name and waypoint information
      -- need to flip the X, and Y values here, because Position flips them originally for website to location calculations to work
      -- DCS requires the x and y values to be in their original position, so we are flipping them back
      -- Note to self - find some way of standardizing this stuff as it's very confusing having to translate DCS coordinates for some reason
      KI.Data.Waypoints[moosegrp.GroupName] =
        {
          x = todepot.Position.Y,
          y = todepot.Position.X,
          formation = "On Road",
          speed = 60
        }

      todepot.IsSuppliesEnRoute = true  -- should update the reference in KI.Data.Depots

      moosegrp:TaskRouteToZone(todepot.Zone, false, 60, "On Road")
      
      KI.GameUtils.MessageCoalition(KI.Config.AllySide, "A supply convoy from " .. fromdepot.Name .. " is enroute to " .. todepot.Name .. " - Protect the convoy!")

      KI.GameUtils.TryDisableAIDispersion(moosegrp)
      
  end, function(err) env.info("KI.Hooks.DWMOnSpawnGroup - ERROR - " .. err) end)

end

function KI.Hooks.AICOMOnSpawnGroup(moosegrp, spawntype, atkzone, grpconfig)
  local success, result = xpcall(function()

      env.info("KI.Hooks.AICOMOnSpawnGroup called")

      if spawntype == "MOVING" then
        env.info("KI.Hooks.AICOMOnSpawnGroup - MOVING Spawn called")
        local vec2 = atkzone:GetRandomVec2()
        env.info("AICOM._SpawnGroups vec2: Group " .. moosegrp.GroupName .. " {x = " .. vec2.x .. ", y = " .. vec2.y .. "}")
        moosegrp:TaskRouteToVec2(vec2, grpconfig.Speed, grpconfig.Formation)

        -- save the group name and waypoint information
        KI.Data.Waypoints[moosegrp.GroupName] =
          {
            x = vec2.x,
            y = vec2.y,
            formation = grpconfig.Formation,
            speed = grpconfig.Speed
          }
        KI.UTDATA.UT_AICOM_ONSPAWNGROUP_CALLED = true  -- this has no function in game, but is used in Unit Tests

      elseif spawntype == "AMBUSH" then
        env.info("KI.Hooks.AICOMOnSpawnGroup - AMBUSH Spawn called - adding to GC queue")
        local gc_item = GCItem:New(moosegrp.GroupName,
          moosegrp,
          function(obj)
            return obj:IsAlive()
          end,
          function(obj)
            return obj:Destroy()
          end,
          nil, nil, nil, nil, AICOM.Config.AmbushTime)

        GC.Add(gc_item)
      end
      
      KI.GameUtils.TryDisableAIDispersion(moosegrp)

  end, function(err) env.info("KI.Hooks.AICOMOnSpawnGroup - ERROR - " .. err) end)
end


function KI.Hooks.CSCIPreOnRadioAction(actionName, parentAction, mooseGroup, supportType, capturePoint)
  local success, result = xpcall(
    function()
      env.info("CSCI.Config.PreOnRadioAction called")
      
      if parentAction == CSCI.AirdropParentMenu then
          
        local spawncp = KI.Query.FindFriendlyCPAirport()
        local _groupID = mooseGroup:GetDCSObject():getID()
        if spawncp == nil then
          
          trigger.action.outTextForGroup(_groupID, "Unable to call in support! Allies do not own any friendly airports!", 15, false)
          return false
        elseif spawncp.Name == capturePoint.Name then
          trigger.action.outTextForGroup(_groupID, "Unable to call in support! Cannot call airdrop on this airbase!", 15, false)
          return false
        else
          return true
        end   
      
      end
    end,
    function(err) env.info("CSCI.Config.PreOnRadioAction ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
  
end


function KI.Hooks.CSCIOnSupportRequestCalled(actionname, parentaction, spawncp, destcp, supporttype)
  env.info("CSCI.Config.CSCIOnSupportRequestCalled called")
  xpcall(function() 
    KI.GameUtils.MessageCoalition(KI.Config.AllySide, parentaction .. " - " .. actionname .. 
         " has been requested for " .. destcp.Name .. " - aircraft on route from friendly airbase " .. spawncp.Name)
  end, function(err) env.info("CSCI.Config.CSCIOnSupportRequestCalled ERROR - " .. err) end)
end


-- KI Hooks into SLC and integration with DWM Depots
function KI.Hooks.SLCPreOnRadioAction(actionName, parentAction, transGroup, pilotname, comp)
  local success, result = xpcall(
    function()
      env.info("SLC.Config.PreOnRadioAction called")
      local _groupID = transGroup:GetDCSObject():getID()

      -- check if this is a depot call
      if parentAction == "Depot Management" or parentAction == "Troop Management" then
        -- immediately return if the player is trying to view the depot contents
        if actionName == "View Depot Contents" then
          return true
        end

        local _depot = KI.Query.FindDepot_Group(transGroup)
        if _depot then
          env.info("SLC.Config.PreOnRadioAction - Group " .. transGroup.GroupName .. " inside zone " .. _depot.Zone.ZoneName)
          local result = false
          local msg = ""
          
          -- if in zone, try to take content
          result, msg = _depot:Take(actionName, 1)

          if not result then
            trigger.action.outTextForGroup(_groupID, msg, 15, false)
          end
          return result
        else
          env.info("SLC.Config.OnRadioAction - Group " .. transGroup.GroupName .. " is not inside a zone")
          trigger.action.outTextForGroup(_groupID, "SLC - This action is only available when near a depot!", 15, false)
          return false
        end
      elseif parentAction == "Crate Management" then
        local _cp = KI.Query.FindCP_Group(transGroup)
        if not _cp and not SLC.Config.AllowCrateUnpackInWild then
          env.info("SLC.Config.PreOnRadioAction - Crate Unpacking cannot be called outside of a capture zone")
          trigger.action.outTextForGroup(_groupID, "SLC - You cannot unpack crates in the wild or at depots! Unpack this crate in a capture zone!", 15, false)
          return false
        elseif _cp ~= nil then
          local result, msg = _cp:Fortify("Vehicle")
          trigger.action.outTextForGroup(_groupID, msg, 15, false)
          return result
        else
          env.info("SLC.Config.PreOnRadioAction - Crate Unpacked in wild")
          trigger.action.outTextForGroup(_groupID, "Successfully unpacked crate in the wild!", 15, false)
          return true
        end
      elseif parentAction == "Deploy Management" then
        -- pass through if check cargo was called
        if actionName == "Check Cargo" then
          return true
        end
      
        local _cp = KI.Query.FindCP_Group(transGroup)
        local _grp = SLC.TransportInstances[pilotname]
      
        -- if the pilot has troops already loaded and not in capture point, disallow
        if not _cp and _grp and not SLC.Config.AllowInfantryUnloadInWild then
          env.info("SLC.Config.PreOnRadioAction - Troop Deployment cannot be called outside of a capture zone")
          trigger.action.outTextForGroup(_groupID, "SLC - You cannot deploy infantry in the wild or at depots! Bring them to a capture zone!", 15, false)
          return false
        elseif _cp and _grp then
          env.info("SLC.Config.PreOnRadioAction - Troop Deployment is valid and inside a capture zone")
          local result, msg = _cp:Fortify("Infantry", _grp.Size)
          trigger.action.outTextForGroup(_groupID, msg, 15, false)
          return result
        elseif _grp then
          env.info("SLC.Config.PreOnRadioAction - Troop Deployment in wild")
          trigger.action.outTextForGroup(_groupID, "Successfully unloaded troops in the wild!", 15, false)
          return true
        else
          env.info("SLC.Config.PreOnRadioAction - Pilot is trying to load troops")
          return true
        end   
      else
        return true
      end

    end,
    function(err) env.info("SLC.Config.PreOnRadioAction ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end




function KI.Hooks.SLCPostOnRadioAction(actionName, actionResult, parentAction, transportGroup, pilotname, comp)
  local success, result = xpcall(
    function()

      env.info("SLC.Config.PostOnRadioAction called (actionName: " .. actionName .. ", parentAction: " .. parentAction .. ")")
      -- create a timer function that will despawn the crate and put it back into the warehouse if left inactive
      if parentAction == "Depot Management" then
        -- add to despawn queue
        --KI.DespawnQueue[actionResult:getName()] = { lastPosition = actionResult:getPoint(), inDepotZone = false, timesChecked = 0 }

        if actionName == "View Depot Contents" then
          return
        end

        env.info("SLC.Config.PostOnRadioAction - adding Depot item to GC Queue")

        local gc_item = GCItem:New(actionResult:getName(),
          actionResult,
          function(obj)
            return obj:isExist()
          end,
          function(obj)
            return obj:destroy()
          end,
          KI.Hooks.GCOnLifeExpiredCrate,
          { 
            LastPosition = actionResult:getPoint(), 
            Depot = nil, 
            Object = actionResult, 
            DepotIdleTime = 0, 
            WasMoved = false, 
            PlayerUnit = transportGroup:GetDCSUnit(1),
            Component = comp
          },
          KI.Hooks.GC_Crate_IsIdle, KI.Hooks.GC_Crate_DepotExpired, KI.Config.CrateDespawnTime_Wild)

        GC.Add(gc_item)

        -- action result returned from unPack is the staticobject
        --timer.scheduleFunction(KI.Scheduled.DespawnHandler, actionResult, timer.getTime() + 60) -- end embedded timer function
      elseif parentAction == "Troop Management" then
        env.info("SLC.Config.PostOnRadioAction - adding troop group to GC Queue")
        if actionResult then
          env.info("SLC.Config.PostOnRadioAction - troop instance found - adding to GC Queue")
          local gc_item = GCItem:New(actionResult.GroupName,
            actionResult,
            function(obj)
              return obj:IsAlive()
            end,
            function(obj)
              return obj:Destroy()
            end,
            KI.Hooks.GCOnLifeExpiredTroops,
            { Depot = nil, Object = actionResult, Component = comp },
            KI.Hooks.GC_Troops_IsIdle, nil, KI.Config.CrateDespawnTime_Depot)

          GC.Add(gc_item)
        else
          env.info("SLC.Config.PostOnRadioAction - troop instance was not found - doing nothing")
        end
      elseif parentAction == "Deploy Management" then
        if actionName == "Check Cargo" then
          return true
        end
        env.info("SLC.Config.PostOnRadioAction - creating transport event")
        -- create the dismount event and raise it
        -- get the location - since you can only unload troops at a capture point, look for capture point
        local _p = KI.Query.FindCP_Group(transportGroup) or KI.Query.FindDepot_Group(transportGroup)

        local _place = {}

        -- need to spoof the location into a DCS Airbase object,
        -- this is done so that our DCS Event Handler can process it like a normal event.place object
        -- both CP and DWM have a .Name property, so lets use that
        if not _p then
          _p = {}
          _place = CustomEventCaster.CastToAirbase(_p, function(o) return "Ground" end)
        else
          _place = CustomEventCaster.CastToAirbase(_p, function(o) return o.Name end)
        end

        -- the reason we have the actionResult return the action name, is because mount/unmount is the same action menu item in game
        -- So we need to verify what actual action was performed when that menu item was selected
        if actionResult.Action == "MOUNT" and actionResult.Result then
          env.info("SLC.Config.PostOnRadioAction - creating KI_EVENT_TRANSPORT_MOUNT event")
          local _e = CustomEvent:New(KI.Defines.Event.KI_EVENT_TRANSPORT_MOUNT, transportGroup:GetDCSUnit(1), _place)
          KI.Hooks.GameEventHandler:onEvent(_e) -- raise the event
        elseif actionResult.Action == "DISMOUNT" and actionResult.Result then
          env.info("SLC.Config.PostOnRadioAction - creating KI_EVENT_TRANSPORT_DISMOUNT event")
          local _e = CustomEvent:New(KI.Defines.Event.KI_EVENT_TRANSPORT_DISMOUNT, transportGroup:GetDCSUnit(1), _place)
          _e.unloaded = actionResult.Result:GetInitialSize() -- actionResult.Result is MOOSE GROUP when Action is DISMOUNT
          KI.Hooks.GameEventHandler:onEvent(_e) -- raise the event
        else
          env.info("SLC.Config.PostOnRadioAction - INVALID ACTION - doing nothing")
        end

      elseif parentAction == "Crate Management" then
        -- since it's possible unpack can fail when player tries to use it (ie. no valid assemblies / no crates nearby)
        -- exit this handler gracefully if that is the case
        if actionResult == nil then return end
        
        env.info("SLC.Config.PostOnRadioAction - creating crate event")
        -- create the crate event and raise it
        -- get the location - since you can only unpack/pack at a capture point, look for capture point
        local _p = KI.Query.FindCP_Group(transportGroup)

        local _place = {}

        -- need to spoof the location into a DCS Airbase object,
        -- this is done so that our DCS Event Handler can process it like a normal event.place object
        -- both CP and DWM have a .Name property, so lets use that
        if not _p then
          _p = {}
          _place = CustomEventCaster.CastToAirbase(_p, function(o) return "Ground" end)
        else
          _place = CustomEventCaster.CastToAirbase(_p, function(o) return o.Name end)
        end

        if actionName == "Pack Nearest" and actionResult.Result then
          env.info("SLC.Config.PostOnRadioAction - creating KI_EVENT_CARGO_PACKED event")
          local _e = CustomEvent:New(KI.Defines.Event.KI_EVENT_CARGO_PACKED, transportGroup:GetDCSUnit(1), _place)
          KI.Hooks.GameEventHandler:onEvent(_e) -- raise the event
        elseif actionName == "Unpack Nearest" and actionResult.Result then
          env.info("SLC.Config.PostOnRadioAction - creating KI_EVENT_CARGO_UNPACKED event")
          local _e = CustomEvent:New(KI.Defines.Event.KI_EVENT_CARGO_UNPACKED, transportGroup:GetDCSUnit(1), _place)
          _e.cargo = actionResult.Assembler     -- actionResult.Assembler is the assembly name as string
          KI.Hooks.GameEventHandler:onEvent(_e) -- raise the event
        else
          env.info("SLC.Config.PostOnRadioAction - INVALID ACTION - doing nothing")
        end
      else
        env.info("SLC.PostOnRadioAction - doing nothing")
      end

    end,
    function(err) env.info("SLC.Config.SLCPostOnRadioAction ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end






-- KI HOOKS INTO GC
function KI.Hooks.GCOnLifeExpiredCrate(gc_item)
  local success, result = xpcall(
    function()

      env.info("KI.Hooks.GCOnLifeExpiredCrate callback called")
      -- if the item is a crate and is inside a depot zone - despawn it and put contents back into depot
      local _args = gc_item.PredicateArgs
      local n = _args.Object:getName()
      if _args.Depot then
        env.info("KI.Hooks.GCOnLifeExpiredCrate - crate is in depot and is being despawned")
        local _depot = _args.Depot
        if _args.WasMoved then
          KI.GameUtils.MessageCoalition(KI.Config.AllySide, _depot.Name .. " was resupplied with cargo (" .. n .. ") by " .. _args.PlayerUnit:getPlayerName())
          local _place = {}

          -- need to spoof the location into a DCS Airbase object,
          -- this is done so that our DCS Event Handler can process it like a normal event.place object
          -- both CP and DWM have a .Name property, so lets use that
          _place = CustomEventCaster.CastToAirbase(_depot, function(o) return o.Name end)
          local _e = CustomEvent:New(KI.Defines.Event.KI_EVENT_DEPOT_RESUPPLY, _args.PlayerUnit, _place)
          _e.cargo = n
          KI.Hooks.GameEventHandler:onEvent(_e) -- raise the event
        else
          KI.GameUtils.MessageCoalition(KI.Config.AllySide, "Crate " .. n .. " has been despawned and contents put back into depot!")
        end

        if _args.Component == nil then
          env.info("KI.Hooks.GCOnLifeExpiredCrate - ERROR - args.Component is nil")
        else
          _depot:Give(_args.Component.MenuName, 1)     
        end
        
      else
        env.info("GC.OnLifeExpired - crate is in wild and is being despawned")
        KI.GameUtils.MessageCoalition(KI.Config.AllySide, "Crate " .. n .. " in the wild has been despawned!")
      end

    end,
    function(err) env.info("GC.GCOnLifeExpiredCrate ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end

-- KI HOOKS INTO GC
function KI.Hooks.GCOnLifeExpiredTroops(gc_item)
  local success, result = xpcall(
    function()

      env.info("GC.GCOnLifeExpiredTroops callback called")
      -- if the item is a crate and is inside a depot zone - despawn it and put contents back into depot
      --if gc_item == nil then env.info("GC.GCOnLifeExpiredTroops gc_item is nil") end
      local n = gc_item.Name
      local _args = gc_item.PredicateArgs
      --if _args == nil then env.info("GC.GCOnLifeExpiredTroops _args is nil") end

      if _args.Depot then
        env.info("GC.GCOnLifeExpiredTroops - troop is in depot and is being despawned")
        local _depot = _args.Depot
        KI.GameUtils.MessageCoalition(KI.Config.AllySide, "Infantry " .. n .. " has been despawned!")

        local result = false
        local msg = ""
        if _args.Component == nil then
          env.info("KI.Hooks.GCOnLifeExpiredCrate - ERROR - args.Component is nil")
        else
          result, msg = _depot:Give(_args.Component.MenuName, 1)
        end

        if not result then
          KI.GameUtils.MessageCoalition(KI.Config.AllySide, msg)
        end
      else
        env.info("GC.GCOnLifeExpiredTroops - troops is in wild and is being despawned")
        KI.GameUtils.MessageCoalition(KI.Config.AllySide, "Infantry " .. n .. " in the wild has been despawned!")
      end

    end,
    function(err) env.info("GC.GCOnLifeExpiredTroops ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end



-- args is a table, which is passed by reference to functions according to lua 5.1 Reference Manual
-- https://stackoverflow.com/questions/6128152/function-variable-scope-pass-by-value-or-reference
function KI.Hooks.GC_Crate_IsIdle(args)
  local success, result = xpcall(
    function()

      env.info("KI.Hooks.GC_Crate_IsIdle called for " .. args.Object:getName())
      local _lastPos = args.LastPosition
      local _newPos = args.Object:getPoint()

      -- check if in a depot zone, depot zone idle time is far less than a crate in the wild
      local _depot = KI.Query.FindDepot_Static(args.Object)
      if _depot then
        env.info("KI.Hooks.GC_Crate_IsIdle - " .. args.Object:getName() .. " is inside depot zone " .. _depot.Name)
        args.Depot = _depot
      else
        env.info("KI.Hooks.GC_Crate_IsIdle - " .. args.Object:getName() .. " is not inside a depot zone")
        args.Depot = nil
      end
      
      -- need to see if there are any players nearby
      local _isPlayerNear = false
      local _punit, _pdistance = KI.Query.FindNearestPlayer_Static(args.Object)
      
      if _punit ~= nil and _pdistance < 50 then
        _isPlayerNear = true
      end
      
      -- compute crate distance
      local crate_distance = Spatial.Distance(_newPos, _lastPos) 
      
      -- if the distance is less than 5 metres and no players are nearby, increment count
      if crate_distance < 5 and not _isPlayerNear then
        env.info("KI.Hooks.GC_Crate_IsIdle - crate position has not changed since last check and no players nearby")
        if args.Depot then
          args.DepotIdleTime = args.DepotIdleTime + GC.LoopRate
        else
          args.DepotIdleTime = 0
        end
        return true
      elseif crate_distance >= 5 then
        env.info("KI.Hooks.GC_Crate_IsIdle - crate position has changed, resetting")
        args.LastPosition = _newPos
        args.WasMoved = true
        
        if _punit then
          env.info("KI.Hooks.GC_Crate_IsIdle - closest player found that changed crate")
          args.PlayerUnit = _punit -- assume that the closest player to the cargo is the one that is slingloading it / should get credit for resupply
          args.PlayerDistance = _pdistance
        end
        return false
      end
    end,
    function(err) env.info("KI.Hooks.GC_Crate_IsIdle ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end

-- this function is only called when troops are first spawned in from depot (but not picked up/dropped)
-- once the troops are loaded/unloaded in SLC the GC is removed entirely for them
function KI.Hooks.GC_Troops_IsIdle(args)
  local success, result = xpcall(
    function()
      env.info("KI.Hooks.GC_Troops_IsIdle called for " .. args.Object.GroupName)
      -- check if in a depot zone
      local _depot = KI.Query.FindDepot_Group(args.Object)
      if _depot then
        env.info("KI.Hooks.GC_Troops_IsIdle - " .. args.Object.GroupName .. " is inside depot zone " .. _depot.Name)
        args.Depot = _depot
      else
        env.info("KI.Hooks.GC_Troops_IsIdle - " .. args.Object.GroupName .. " is not inside a depot zone")
        args.Depot = nil
      end

      return true
    end,
    function(err) env.info("KI.Hooks.GC_Troops_IsIdle ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end

function KI.Hooks.GC_Crate_DepotExpired(args)
  local success, result = xpcall(
    function()
      if args.Depot and args.DepotIdleTime >= KI.Config.CrateDespawnTime_Depot then
        local should_expire = false
        -- in order to expire a crate, it be inside a depot zone, been idle for the configurable limit,
        -- and no players can be within 50 metres from it
        -- the 50 metre check is to prevent server CTD caused by DCS bug when invoking destroy cargo that is hooked to a helicopter
        if args.PlayerDistance and args.PlayerDistance > 50 then
          should_expire = true
        else
          -- if we dont have this argument value, search for the nearest player and compare distance
          local _punit, _pdistance = KI.Query.FindNearestPlayer_Static(args.Object)
          if not _punit or (_punit ~= nil and _pdistance > 50) then
            should_expire = true
          end
        end

        env.info("KI.Hooks.GC_Crate_DepotExpired returned " .. tostring(should_expire))
        return should_expire
      else
        env.info("KI.Hooks.GC_Crate_DepotExpired returned false")
        return false
      end
    end,
    function(err) env.info("KI.Hooks.GC_Crate_DepotExpired ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end
end

function KI.Hooks.GCOnDespawn(name)
  env.info("GC.OnDespawn called for " .. name)
  return
end


-- Handlers for GameEvents
KI.Hooks.GameEventHandler = {}

function KI.Hooks.GameEventHandler:onEvent(event)
  local success, result = xpcall(
    function()

      env.info("KI.Hooks.GameEventHandler:onEvent(event) called")

      if event.id == world.event.S_EVENT_MISSION_END then
        if trigger.misc.getUserFlag("9000") ~= 3 and trigger.misc.getUserFlag("9000") ~= 4 then
          env.info("KI.Hooks.GameEventHandler - Mission End Event raised")
          -- this has no function, but it is here so that we can unit test this behaviour
          KI.UTDATA.UT_MISSION_END_CALLED = true
  
          -- Save all mission data to file
          KI.Loader.SaveData()
          -- Finish receive/send of data between server mod
          KI.Scheduled.DataTransmissionPlayers({}, 0)
          KI.Scheduled.DataTransmissionGeneral({}, 0)
          KI.Scheduled.DataTransmissionGameEvents({}, 0)
          trigger.action.setUserFlag("9000", 3) -- notify server mod that the mission has restarted
        end
        return
      end

      if not event.initiator then return end
      local playerName = nil
      if event.initiator.getPlayerName then
        playerName = event.initiator:getPlayerName() or nil
      end

      -- catch all forms of shooting events from a player
      if (event.id == world.event.S_EVENT_SHOT or
        event.id == world.event.S_EVENT_SHOOTING_START or
        event.id == world.event.S_EVENT_SHOOTING_END) and
        playerName then
        env.info("KI.Hooks.GameEventHandler - SHOT / SHOOTING START / SHOOTING END")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
        return
        -- catch all hit events that were initiated by a player
      elseif event.id == world.event.S_EVENT_HIT and playerName then
        env.info("KI.Hooks.GameEventHandler - PLAYER HIT SOMEONE")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
        return
      elseif event.id == world.event.S_EVENT_TAKEOFF and playerName then
        env.info("KI.Hooks.GameEventHandler - PLAYER TAKE OFF")
        for pid, op in pairs(KI.Data.OnlinePlayers) do
          if op.Name == playerName then
            -- start a new sortie, and decrement lives counter
            op.SortieID = KI.IncrementSortieID()
            op.Lives = op.Lives - 1

            table.insert(KI.Data.GameEventQueue,
              GameEvent.CreateGameEvent(KI.Data.SessionID,
                KI.Data.ServerID,
                event,
                timer.getTime())
            )


            local placeName = "Ground"
            if event.place and event.place.getName then
              placeName = event.place:getName()
            end

            local _group = event.initiator:getGroup()
            if _group then
              local _groupID = _group:getID()
              local msg = "_______________________________________________________________________________________________________\n\n"
              msg = msg .. "  Have a good flight "..playerName.."\n\n"
              msg = msg .. "  You took off from "..placeName..".\n\n"
              msg = msg .. "  Lives - "..op.Lives.."/".."5".."\n"
              msg = msg .. "  Land your aircraft on a base to get your life back.\n"
              msg = msg .. "_______________________________________________________________________________________________________\n"

              trigger.action.outTextForGroup(_groupID, msg, 30, false)
            end
            return
          end
        end

        return
      elseif event.id == world.event.S_EVENT_LAND and playerName then
        env.info("KI.Hooks.GameEventHandler - PLAYER LANDED")
        for pid, op in pairs(KI.Data.OnlinePlayers) do
          if op.Name == playerName then
            -- increment lives counter
            op.Lives = op.Lives + 1

            table.insert(KI.Data.GameEventQueue,
              GameEvent.CreateGameEvent(KI.Data.SessionID,
                KI.Data.ServerID,
                event,
                timer.getTime())
            )
            
            local _group = event.initiator:getGroup()
            if _group then
              local _groupID = _group:getID()
              local msg = "_______________________________________________________________________________________________________\n\n"
              msg = msg .. "  You have Landed and regained your life\n\n"
              msg = msg .. "  Lives - "..op.Lives.."/".."5".."\n"
              msg = msg .. "_______________________________________________________________________________________________________\n"

              trigger.action.outTextForGroup(_groupID, msg, 30, false)
            end
            
            return
          end
        end

        return
        -- catch all forms of death / airframe destruction
      elseif event.id == world.event.S_EVENT_CRASH or
        event.id == world.event.S_EVENT_DEAD or
        event.id == world.event.S_EVENT_EJECTION or
        event.id == world.event.S_EVENT_PILOT_DEAD or
        event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
        env.info("KI.Hooks.GameEventHandler - DEATH EVENT")

        -- doing something sneaky - modify the event object so that if the unit that died is AI, add a .target property and set it to the AI unit that died - this will capture the category, unit type information and store it in the target columns, rather than the player columns (we'll set those to "AI")
        if not playerName then
          event.target = event.initiator
        end

        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
        
        -- if a helicopter died/left slot remove the cargo contents from the heli
        SLC.TransportInstances[event.initiator:getName()] = nil
        return
      elseif (event.id == world.event.S_EVENT_REFUELING or
        event.id == world.event.S_EVENT_REFUELING_STOP) and playerName then
        env.info("KI.Hooks.GameEventHandler - Refueling Event raised")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
        return
        -- elseif event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT and playerName then
        -- elseif event.id == world.event.S_EVENT_MISSION_START then
      elseif event.id == world.event.S_EVENT_BIRTH and playerName then
        local unitname = event.initiator:getName()
        env.info("KI.Hooks.GameEventHandler - BIRTH for " .. unitname)
        
        -- Initialize any radio menu items for the player
        SLC.InitSLCForUnit(unitname)
        CSCI.InitCSCIForUnit(unitname)
        KI.InitSideMissionMenu(unitname)
        
        -- we track the unitID so that we can link slingload hook/unhook events to a player
        KI.Data.UnitIDs[tostring(event.initiator.id_)] = event.initiator

        -- set the unit property on the OnlinePlayers object
        for pid, op in pairs(KI.Data.OnlinePlayers) do
          if op.Name == playerName then
            op.Unit = event.initiator
            break
          end
        end

        --elseif event.id == world.event.S_EVENT_PLAYER_COMMENT  then
      elseif (event.id == KI.Defines.Event.KI_EVENT_TRANSPORT_DISMOUNT or
        event.id == KI.Defines.Event.KI_EVENT_TRANSPORT_MOUNT) and playerName then
        env.info("KI.Hooks.GameEventHandler - Transport Event raised")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
      elseif (event.id == KI.Defines.Event.KI_EVENT_CARGO_UNPACKED or
        event.id == KI.Defines.Event.KI_EVENT_CARGO_PACKED) and playerName then
        env.info("KI.Hooks.GameEventHandler - Cargo Event raised")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
      elseif event.id == KI.Defines.Event.KI_EVENT_DEPOT_RESUPPLY and playerName then
        env.info("KI.Hooks.GameEventHandler - Depot Resupply Event raised")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
      elseif (event.id == KI.Defines.Event.KI_EVENT_SLING_HOOK or
        event.id == KI.Defines.Event.KI_EVENT_SLING_UNHOOK or
        event.id == KI.Defines.Event.KI_EVENT_SLING_UNHOOK_DESTROYED) and playerName then
        env.info("KI.Hooks.GameEventHandler - Slingload Event raised")
        table.insert(KI.Data.GameEventQueue,
          GameEvent.CreateGameEvent(KI.Data.SessionID,
            KI.Data.ServerID,
            event,
            timer.getTime())
        )
      end
    end,
    function(err) env.info("KI.Hooks.GameEventHandler ERROR - " .. err) end)

  if success then
    return result
  else
    return false
  end

end




























































