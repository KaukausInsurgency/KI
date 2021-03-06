if not SLC then
  SLC = {}
end

SLC.CargoInstances = {}      -- collection of tuples CargoInstances[1].Object, CargoInstances[1].Component
SLC.ZoneInstances = {}       -- collection of ZONE
SLC.TransportInstances = {}  -- collection of { TransportUnit, GroupTemplate }
SLC.InfantryInstances = {}   -- collection of { GROUP, SpawnTemplate }
  
--Internal Function
function SLC.RelinkCargo(cargo)
  env.info("SLC.RelinkCargo called")
  if not cargo then
    env.info("SLC.RelinkCargo - ERROR - cargo is nil - exiting")
    return false
  end
  
  -- find the component this belongs to
  local _name = cargo:getName()
  for i, comp in pairs(SLC.Config.ComponentTypes) do
    if string.match(_name, comp.SpawnName) then
      env.info("SLC.RelinkCargo - found matching component (" .. comp.KeyName .. ")")
      table.insert(SLC.CargoInstances, { Object = cargo, Component = comp })
      return true
    end
  end
  
  return false
end



-- Add Infantry Instance to InfantryInstances table
function SLC.AddInfantryInstance(g, st, sn, mn, s, jtac)
  table.insert(SLC.InfantryInstances, { Group = g, SpawnTemplate = st, SpawnName = sn, MenuName = mn, Size = s, IsJTAC = jtac })
end


-- checks if the passed in group is capable of transporting infantry
function SLC.CanTransportInfantry(u)
  env.info("SLC.CanTransportInfantry called")
  if not u or not u:isExist() then return false end
  
  -- if this setting is nil or 0, allow all helos to transport
  if not SLC.Config.InfantryTransportingHelicopters or #SLC.Config.InfantryTransportingHelicopters == 0 then
    env.info("SLC.CanTransportInfantry - WARNING - No definitions exist - All airframes allowed to transport infantry")
    return true
  end
  
  for i = 1, #SLC.Config.InfantryTransportingHelicopters do
    if u:getTypeName() == SLC.Config.InfantryTransportingHelicopters[i] then
      env.info("SLC.CanTransportInfantry - unit " .. u:getName() .. " is capable to transport infantry")
      return true
    end
  end
  
  env.info("SLC.CanTransportInfantry - group " .. u:getName() .. " cannot transport infantry")
  return false
end


-- GenerateName
-- Generates a new name for the spawned group, and increments the spawnID counter
function SLC.GenerateName(n)
  return n .. " Spawn" .. tostring(SLC.IncrementSpawnID())
end


function SLC.IncrementSpawnID()
  env.info("SLC.IncrementSpawnID called")
  SLC.Config.SpawnID = SLC.Config.SpawnID + 1
  env.info("SLC.IncrementSpawnID - New ID: " .. tostring(SLC.Config.SpawnID))
  return SLC.Config.SpawnID
end


function SLC.InAir(obj)
    if obj:inAir() == false then
        return false
    end

    -- less than 5 cm/s a second so landed
    -- BUT AI can hold a perfect hover so ignore AI
    if mist.vec.mag(obj:getVelocity()) < 0.05 and obj:getPlayerName() ~= nil then
        return false
    end
    
    return true
end



function SLC.IsCargoValid(cargo)
  if cargo == nil then
    return false
  elseif cargo.Object == nil then
    return false
  elseif not cargo.Object:isExist() then
    return false
  elseif StaticObject.getByName(cargo.Object:getName()) == nil then
    return false
  else
    return true
  end
end



-- Returns list of cargo near the player/pilot in format (Parameter groupTransport is MOOSE:GROUP)
-- { Object{DCSStaticObject}, Component{KeyName, ParentMenu, MenuName, SpawnName, Type, Weight, Assembler}, Distance }
function SLC.GetNearbyCargo(groupTransport)
  local crate_results = {}
  local gPos = groupTransport:GetVec3()
  local cratesToRemove = {}
  for i, cargo in pairs(SLC.CargoInstances) do
    if SLC.IsCargoValid(cargo) then
      local cPos = cargo.Object:getPoint()
      local distance = Spatial.Distance(cPos, gPos)
      env.info("SLC.GetNearbyCargo distance : " .. tostring(distance) .. " metres")
      if distance < SLC.Config.CrateQueryDistance and not SLC.InAir(cargo.Object) then
        env.info("SLC.GetNearbyCargo - crate is inside query distance - adding to results")
        table.insert(crate_results, { Object = cargo.Object, Component = cargo.Component, Distance = distance })
      else
        env.info("SLC.GetNearbyCargo - crate is outside query distance - ignore")
      end
    else
      env.info("SLC.GetNearbyCargo - nil entry found in CargoInstances")
      table.insert(cratesToRemove, i)
    end
  end
  
  for i = 1, #cratesToRemove do
    env.info("SLC.GetNearbyCargo - removing invalid entries from CargoInstances")
    table.remove(SLC.CargoInstances, cratesToRemove[i])
  end
  return crate_results
end



-- returns a list of { Group{MOOSE:GROUP}, SpawnTemplate, Distance } 
function SLC.GetNearbyInfantryGroups(groupTransport)
  local inf_results = {}
  local gPos = groupTransport:GetVec3()
  local infToRemove = {}
  for i, inf in pairs(SLC.InfantryInstances) do
    if inf.Group:IsAlive() then
      local iPos = inf.Group:GetVec3()
      local distance = Spatial.Distance(iPos, gPos)
      env.info("SLC.GetNearbyInfantryGroups distance : " .. tostring(distance) .. " metres")
      if distance < SLC.Config.CrateQueryDistance and not inf.Group:InAir() then
        env.info("SLC.GetNearbyInfantryGroups - infantry is inside query distance - adding to results")
        table.insert(inf_results, 
          { 
            Group = inf.Group, 
            SpawnTemplate = inf.SpawnTemplate, 
            SpawnName = inf.SpawnName, 
            MenuName = inf.MenuName, 
            Size = inf.Size,
            IsJTAC = inf.IsJTAC,
            Distance = distance 
          })
      else
        env.info("SLC.GetNearbyInfantryGroups - infantry is outside query distance - ignore")
      end
    else
      env.info("SLC.GetNearbyInfantryGroups - nil entry found in InfantryInstances")
      table.insert(infToRemove, i)
    end
  end
  
  for i = 1, #infToRemove do
    env.info("SLC.GetNearbyInfantryGroups - removing invalid entries from InfantryInstances")
    table.remove(SLC.InfantryInstances, infToRemove[i])
  end
  
  return inf_results
end



-- Checks to see if the provided assembler and list of cargo crates is valid (can be built)
-- Returns true or false, if the assembler can be built, and the list of CargoInstance crates that can be used with the provided assembler
-- returns { result=boolean, crates{CargoInstance} }
function SLC.IsAssemblyValid(assembler, crates)
  env.info("SLC.IsAssemblyValid - required component count : " .. tostring(assembler.Count))
  local crate_count = 0
  local found = {}
  local dist = 0
  for i, cargo in pairs(crates) do
    if assembler.Components[cargo.Component.KeyName] then
      env.info("SLC.IsAssemblyValid - found matching component " .. cargo.Component.KeyName .. " for assembler")
      if not found[cargo.Component.KeyName] then
        env.info("SLC.IsAssemblyValid - matching component is a unique item - incrementing counter")
        crate_count = crate_count + 1
        found[cargo.Component.KeyName] = cargo
        dist = cargo.Distance
      else
        env.info("SLC.IsAssemblyValid - matching component is a duplicate item - ignoring")
      end
    else
      env.info("SLC.IsAssemblyValid - component " .. cargo.Component.KeyName .. " does not exist for assembler - ignoring")
    end
  end
  
  if crate_count == assembler.Count then
    env.info("SLC.IsAssemblyValid - Assembler is valid")
    return { result = true, crates = found, distance = dist }
  else
    env.info("SLC.IsAssemblyValid - Assembler is not valid")
    return { result = false, crates = found, distance = dist }
  end
end



function SLC.GetAssemblers(crates)
  env.info("SLC.GetAssemblers called")
  local assemblies = {}

  -- get unique assemblers
  for i, cargo in pairs(crates) do
    if assemblies[cargo.Component.Assembler] == nil then
      env.info("SLC.GetAssemblers - New Assembler Found : " .. tostring(cargo.Component.Assembler))
      assemblies[cargo.Component.Assembler] = SLC.Config.Assembler[cargo.Component.Assembler]
    else
      env.info("SLC.GetAssemblers - Existing Assembler Found - skipping")
    end
  end
  
  local results = {}
  -- find which assemblies are valid and can be completed
  for name, _assembler in pairs(assemblies) do
    local res = SLC.IsAssemblyValid(_assembler, crates)
    if res.result then
      env.info("SLC.GetAssemblers - valid assembler found - inserting results")
      table.insert(results, { assembler = _assembler, objects = res.crates, distance = res.distance })
    else
      env.info("SLC.GetAssemblers - invalid assembler found - skipping")
    end
  end
  
  return results
end


function SLC.ShowDepotContents(g, pilotName)
  env.info("SLC.ShowDepotContents Called")
  local _depot = KI.Query.FindDepot_Group(g)
  local _groupID = g:GetDCSObject():getID()
  if _depot then
    trigger.action.outTextForGroup(_groupID, _depot:ViewResources(), 30, false)
    return true
  else
    trigger.action.outTextForGroup(_groupID, "You must be near a Depot to view its contents!", 30, false)
    return false
  end
end


-- SpawnGroup
-- Spawns a new group, using an existing Groups Position, a group template structure, and the passed in spawn name
function SLC.SpawnGroup(g, pilotName, infcomp)
  env.info("SLC.SpawnGroup Called")
  local spawnpos = Spatial.PositionAt12Oclock(g, 25)
  local SpawnVeh = SPAWN:NewWithAlias(infcomp.SpawnTemplate, SLC.GenerateName(infcomp.SpawnName))
  --env.info("SLC.SpawnGroup gVec3 (x = " .. tostring(g:GetVec3().x) .. ", y = " .. tostring(g:GetVec3().y) .. ", z = " .. tostring(g:GetVec3().z) .. ")")
  --env.info("SLC.SpawnGroup spVec3 (x = " .. tostring(spawnpos.x) .. ", y = " .. tostring(spawnpos.y) .. ", z = " .. tostring(spawnpos.z) .. ")")
  local NewGroup = SpawnVeh:SpawnFromVec3(spawnpos)
  KI.GameUtils.TryDisableAIDispersion(NewGroup)
  -- add to map of infantry instances
  SLC.AddInfantryInstance(NewGroup, infcomp.SpawnTemplate, infcomp.SpawnName, infcomp.MenuName, NewGroup:GetSize(), infcomp.IsJTAC)
  env.info("SLC.Infantry Spawned as Group " .. NewGroup.GroupName)
  local _groupID = g:GetDCSObject():getID()
  trigger.action.outTextForGroup(_groupID, "SLC - Infantry has been spawned at your 12 O'clock position", 10, false)
  return NewGroup
end




function SLC.SpawnCrate(g, pilotName, comp)
  env.info("SLC.SpawnCrate Called")
  local raw_cargo = SLC.Config.CargoTypes[comp.Type]
  if raw_cargo then
    env.info("SLC.SpawnCrate rawtype found")
    env.info("SLC.SpawnCrate - rawtype: " .. tostring(raw_cargo.Name))
  else
    env.info("SLC.SpawnCrate rawtype not found")
  end
  
  local p = Spatial.PositionAt12Oclock(g, SLC.Config.ObjectSpawnDistance)
  local obj = SLC.SpawnSlingLoadableCargo(raw_cargo.Name, comp, p)
  local _groupID = g:GetDCSObject():getID()
  trigger.action.outTextForGroup(_groupID, "SLC - Crate has been spawned at your 12 O'clock position", 10, false) 
  return obj
end




-- SpawnSlingLoadableCargo
-- Spawns a new cargo crate that can be sling loaded
-- The name of the spawned cargo is a combination of 'CargoSpawn' + Category + SpawnID
-- The cargo name is important and is used in searching
function SLC.SpawnSlingLoadableCargo(rawtype, comp, pos)
  env.info("SLC.SpawnSlingLoadableCargo Called")
	local cargo_name = SLC.GenerateName(comp.SpawnName)
	local obj = coalition.addStaticObject(KI.Config.AllyCountryID, {
		country = "Russia",
		category = "Cargos",
		x = pos.x,
		y = pos.z,
		type = rawtype,
		name = cargo_name,
		mass = comp.Weight,
		canCargo = true
	})

	table.insert(SLC.CargoInstances, { Object = obj, Component = comp })
  env.info("SLC.SpawnSlingLoadableCargo - Adding CargoInstance for " .. cargo_name)
  return obj
end




-- Unpacks nearest crate(s) that can be assembled
function SLC.Unpack(transportGroup, pilotname)
  env.info("SLC.Unpack called")
  local crates = SLC.GetNearbyCargo(transportGroup)
  local _groupID = transportGroup:GetDCSObject():getID()
  if #crates == 0 then
    env.info("SLC.Unpack No Nearby Crates Found")
    trigger.action.outTextForGroup(_groupID, "SLC - No Crates Found To Unpack!", 10, false)
    return nil
  end
  local assemblers = SLC.GetAssemblers(crates)
  env.info("SLC.Unpack GetAssembler count : " .. tostring(#assemblers))
  if #assemblers > 0 then
    env.info("SLC.Unpack - Valid Assemblers found - getting closest assembly")
    local assembly = nil
    for i, a in pairs(assemblers) do
      if assembly then
        if a.distance < assembly.distance then
          env.info("SLC.Unpack - assembly is closer than previous - setting")
          assembly = a
        else
          env.info("SLC.Unpack - assembly is not closest - ignoring")
        end
      else
        env.info("SLC.Unpack - first time in loop - setting first item as closest assembler")
        assembly = a
      end
    end
    
    assert(assembly, "ASSERT FAILED: Assembly is nil after finding closest valid assembly - terminating")
    
    local i = 0
    local NewGroup = nil
    for name, crate in pairs(assembly.objects) do
      if i == 0 then
        env.info("SLC.Unpack - spawning object on first crate position")
        local SpawnVeh = SPAWN:NewWithAlias(assembly.assembler.SpawnTemplate, SLC.GenerateName(assembly.assembler.SpawnName))
        if assembly.assembler.IsJTAC then
          env.info("SLC.Unpack - Group is JTAC")
          SpawnVeh:OnSpawnGroup(
            function( spawngrp ) 
              env.info("SLC.Unpack:OnSpawnGroup Callback - initializing JTAC")
              JTACAutoLase(spawngrp.GroupName)                
            end
          )
        end
        NewGroup = SpawnVeh:SpawnFromVec3(crate.Object:getPoint())
        KI.GameUtils.TryDisableAIDispersion(NewGroup)
        env.info("SLC.Unpack Spawned Group " .. NewGroup.GroupName)
        i = i + 1
      end
      crate.Object:destroy()
      env.info("SLC.Unpack destroying crate")
    end
    trigger.action.outTextForGroup(_groupID, "SLC - Successfully Unpacked Unit!", 10, false)
    return { Result = NewGroup, Assembler = assembly.assembler.SpawnName }
  else
    trigger.action.outTextForGroup(_groupID, "SLC - Cannot Unpack Crate(s) - Missing Components!", 10, false)
    env.info("SLC.Unpack - no valid assemblies found")
    return nil
  end
end




function SLC.UnloadTroops(g, p)
  env.info("SLC.UnloadTroops called")
  local troopInfo = SLC.TransportInstances[p]
  if troopInfo == nil then
    env.info("SLC.UnloadTroops - pilot " .. p .. " is not carrying any troops - aborting")
    return nil
  end
  
  local pos = Spatial.PositionAt12Oclock(g, SLC.Config.ObjectSpawnDistance)
  local SpawnVeh = SPAWN:NewWithAlias(troopInfo.SpawnTemplate, SLC.GenerateName(troopInfo.SpawnName))
  if troopInfo.IsJTAC then
    env.info("SLC.UnloadTroops - Group is JTAC")
    SpawnVeh:OnSpawnGroup(
      function( spawngrp ) 
        env.info("SLC.Unpack:OnSpawnGroup Callback - initializing JTAC")
        JTACAutoLase(spawngrp.GroupName)                
      end
    )
  end
  
  local NewGroup = SpawnVeh:SpawnFromVec3(pos, SLC.IncrementSpawnID())
  KI.GameUtils.TryDisableAIDispersion(NewGroup)
  
  env.info("SLC.UnloadTroops - spawned unloaded group " .. NewGroup.GroupName .. " - adding to instance map")
  SLC.AddInfantryInstance(NewGroup, troopInfo.SpawnTemplate, troopInfo.SpawnName, troopInfo.MenuName, NewGroup:GetSize(), troopInfo.IsJTAC)
  env.info("SLC.UnloadTroops - removing TransportInstance for " .. p)
  SLC.TransportInstances[p] = nil
  local _groupID = g:GetDCSObject():getID()
  trigger.action.outTextForGroup(_groupID, "SLC - Troops deployed", 10, false)
  return NewGroup
end





function SLC.LoadTroops(g, p)
  env.info("SLC.LoadTroops Called")
  if SLC.TransportInstances[p] then
    env.info("SLC.LoadTroops - Pilot " .. p .. " already has troop cargo - exiting")
    return false
  end
  -- check if g is in zone
  -- get infantry groups inside zone
  local _groupID = g:GetDCSObject():getID()
  local infantryGroups = SLC.GetNearbyInfantryGroups(g)
  
  if #infantryGroups > 0 then
    env.info("SLC.LoadTroops - found infantry groups")
    local closestGroup = nil
    for i = 1, #infantryGroups do
      local ig = infantryGroups[i]
      if closestGroup then
        if ig.Distance < closestGroup.Distance then
          env.info("SLC.LoadTroops - Group is closer than previous - setting")
          closestGroup = ig
        else
          env.info("SLC.LoadTroops - Group is not closest - ignoring")
        end
      else
        env.info("SLC.LoadTroops - first time in loop - setting first item as closest Group")
        closestGroup = ig
      end
    end
    env.info("SLC.LoadTroops - found closest group - destroying and saving info")
    SLC.TransportInstances[p] = closestGroup
    closestGroup.Group:Destroy()
    trigger.action.outTextForGroup(_groupID, "SLC - Infantry has been loaded", 10, false)
    return true
  else
    trigger.action.outTextForGroup(_groupID, "SLC - No nearby troops to load!", 10, false)
    env.info("SLC.LoadTroops - no infantry groups found")
    return false
  end
end





-- LoadUnload
-- Handles the loading/unloading of troops
function SLC.LoadUnload(g, pilot)
  env.info("SLC.LoadUnload called")
  if SLC.TransportInstances[pilot] then
    env.info("SLC.LoadUnload - " .. pilot .. " already has troop cargo")
    return { Action = "DISMOUNT", Result = SLC.UnloadTroops(g, pilot) }
  else
    env.info("SLC.LoadUnload - " .. pilot .. " has no troop cargo")
    local _result = SLC.LoadTroops(g, pilot)
    return { Action = "MOUNT", Result = _result }
  end
end


function SLC.ViewCargoContents(g, pilot)
  env.info("SLC.ViewCargoContents called")
  local _groupID = g:GetDCSObject():getID()
  local _ti = SLC.TransportInstances[pilot]
  if _ti then
    trigger.action.outTextForGroup(_groupID, "You are currently transporting : " .. _ti.MenuName, 15, false)
  else
    trigger.action.outTextForGroup(_groupID, "You have no cargo", 15, false)
  end
end


--Performs menu action
--Uses command pattern to feed the action/command and its arguments
function SLC.PerformAction(action, actionName, parentAction, transportGroup, pilotname, comp)
  env.info("SLC.PerformAction called")
  -- verify that pilot is on ground
  local u = transportGroup:GetDCSUnit(1)
  if SLC.InAir(u) and actionName ~= "Check Cargo" then
    local _groupID = transportGroup:GetDCSObject():getID()
    trigger.action.outTextForGroup(_groupID, "SLC - You must be landed in order to perform an action", 10, false)
  else
    -- If there is a PreOnRadioAction handler, call it and if the result is true, call action normally
    if SLC.Config.PreOnRadioAction then
      env.info("SLC.PerformAction - Found PreOnRadioAction callback - invoking")
      if SLC.Config.PreOnRadioAction(actionName, parentAction, transportGroup, pilotname, comp) then
        env.info("SLC.PerformAction - PreOnRadioAction callback returned true, executing action")
        local ok, actionResult = xpcall(function() return action(transportGroup, pilotname, comp) end, 
                                        function(err) env.info("SLC.PerformAction ERROR - " .. err) end)
        if not ok then return end
        
        if SLC.Config.PostOnRadioAction then
          SLC.Config.PostOnRadioAction(actionName, actionResult, parentAction, transportGroup, pilotname, comp)
        end
      end
    else
      env.info("SLC.PerformAction - No PreOnRadioAction callback found - executing action normally")
      local actionResult = action(transportGroup, pilotname, comp)
      if SLC.Config.PostOnRadioAction then
          SLC.Config.PostOnRadioAction(actionName, actionResult, parentAction, transportGroup, pilotname, comp)
      end
    end
  end
end




--AddSLCRadioItems
--Adds the necessary SLC Radio Menu Options for the group
--Accepts parameter MOOSE:GROUP Object
function SLC.AddSLCRadioItems(g, u, pilotname)
  env.info("SLC.AddSLCRadioItems Group name - " .. g.GroupName)
  local m_main = MENU_GROUP:New(g, "SLC Menu")
  
  -- Depot Management Sub Menu
  local m_depot = MENU_GROUP:New(g, "Depot Management", m_main)
  
  -- Inject view depot contents menu item
  MENU_GROUP_COMMAND:New(g, "View Depot Contents", m_depot,
                           SLC.PerformAction,
                           SLC.ShowDepotContents, "View Depot Contents", "Depot Management", g, pilotname, nil)
                         
  local submenus = {}
  -- generate menu items based on component types config (components are radio items that can be spawned in for pickup)

  for _, c in ipairs(SLC.Config.ComponentTypesOrder) do
    local comp = SLC.Config.ComponentTypes[c]
    env.info("SLC.AddSLCRadioItems - looping through component types for " .. comp.MenuName)
    
    local submenu = m_depot
    
    if comp.ParentMenu then
      env.info("SLC.AddSLCRadioItems - component has a parent menu")
      if submenus[comp.ParentMenu] then
        env.info("SLC.AddSLCRadioItems - parent menu already exists - adding to existing")
        submenu = submenus[comp.ParentMenu]
      else
        env.info("SLC.AddSLCRadioItems - parent menu does not exist - creating sub menu")
        submenu = MENU_GROUP:New(g, comp.ParentMenu, m_depot)
        submenus[comp.ParentMenu] = submenu
      end
    else
      env.info("SLC.AddSLCRadioItems - component does not have a parent menu - adding normally")
    end

    MENU_GROUP_COMMAND:New(g, comp.MenuName, submenu,
                           SLC.PerformAction,
                           SLC.SpawnCrate, comp.MenuName, "Depot Management", g, pilotname, comp)
  end

  local m_troops = MENU_GROUP:New(g, "Troop Management", m_main)
  
  for _, i in ipairs(SLC.Config.InfantryTypesOrder) do
    local inf = SLC.Config.InfantryTypes[i]
    env.info("SLC.AddSLCRadioItems - looping through infantry types for " .. inf.MenuName)
    MENU_GROUP_COMMAND:New(g, inf.MenuName, m_troops,
                           SLC.PerformAction,
                           SLC.SpawnGroup, inf.MenuName, "Troop Management", g, pilotname, inf)
  end
  
  local m_crate = MENU_GROUP:New(g, "Crate Management", m_main)
  
    local m_unpack = MENU_GROUP_COMMAND:New(g, "Unpack Nearest", m_crate, 
                                            SLC.PerformAction,
                                            SLC.Unpack, "Unpack Nearest", "Crate Management", g, pilotname)
    
    local m_pack = MENU_GROUP_COMMAND:New(g, "Pack Nearest", m_crate, 
                                            SLC.PerformAction,
                                            SLC.Pack, "Pack Nearest", g, pilotname)
    
  -- this menu will only be available if the airframe is capable of transporting infantry
  if SLC.CanTransportInfantry(u) then
    local m_deploy = MENU_GROUP:New(g, "Deploy Management", m_main)
      
      local m_loadunload = MENU_GROUP_COMMAND:New(g, "Load/Unload Troops", m_deploy, 
                                                  SLC.PerformAction,
                                                  SLC.LoadUnload, "Load/Unload Troops", "Deploy Management", g, pilotname)
      
      local m_viewcargo = MENU_GROUP_COMMAND:New(g, "Check Cargo", m_deploy, 
                                                  SLC.PerformAction,
                                                  SLC.ViewCargoContents, "Check Cargo", "Deploy Management", g, pilotname)
  end  
  
  env.info("SLC.AddSLCRadioItems Items Added")
end


function SLC.IsSLCUnit(unit_name)
  if string.match(unit_name, "SLCPilot") then
    return true
  else
    return false
  end
end



-- Init SLC by pilotname
function SLC.InitSLCForUnit(unitName)
  env.info("SLC.InitSLCForUnit() called")
  local _dcsUnit = Unit.getByName(unitName)
  
  -- If the unit has not been found
  if not _dcsUnit then 
  	env.info("SLC.InitSLCForUnit - unit does not exist - aborting")
  	return false 
  end
  
  if SLC.IsSLCUnit(unitName) then   
    env.info("SLC.InitSLCForUnit - SLC Pilot " .. unitName .. " found, initializing")
    local _mooseGroup = KI.GameUtils.SyncWithMoose(_dcsUnit)  -- Issue #208 workaround
    SLC.AddSLCRadioItems(_mooseGroup, _dcsUnit, unitName)
    return true
  else
    env.info("SLC.InitSLCForUnit - Pilot Name does not match 'SLCPilot' - aborting")
    return false
  end 
end



-- Zone Functions
function SLC.SlingLoadableCargoInZone(cargo_name, zone)
	local cargoObj = StaticObject.getByName(cargo_name)
	if cargoObj == nil or zone == nil then
		env.info("Cargo is dead/inactive or zone is nil")
		return false
	end
  local distance = Spatial.Distance(zone:GetVec3(0), cargoObj:getPoint()) 
  env.info("Distance for " .. cargo_name .. " - " .. tostring(distance) .. " metres")
  env.info("Zone Radius for " .. cargo_name .. " - " .. tostring(zone:GetRadius()) .. " metres")
	if distance < zone:GetRadius() then
		env.info("Cargo Inside Zone")
		return true
	else
		env.info("Cargo Outside Zone")
		return false
	end
end








