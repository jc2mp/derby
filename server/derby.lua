

--[[
    Wrapper class for each player who joins the derby
]]
class "DerbyPlayer"
function DerbyPlayer:__init(player, derby)
    self.derby = derby
    self.player = player
    self.start_pos = player:GetPosition()
    self.start_world = player:GetWorld()
    self.inventory = player:GetInventory()
end

function DerbyPlayer:Enter()
    self.player:SetWorld(self.derby.world)
    
    local spawn = self.derby.spawns[ math.random(1, #self.derby.spawns) ]
    self.player:Teleport(spawn, Angle())
    self.player:ClearInventory()

    Network:Send( self.player, "DerbyEnter" )
end

function DerbyPlayer:Leave()
    self.player:SetWorld( self.start_world )
    self.player:Teleport( self.start_pos, Angle() )

    self.player:ClearInventory()
    for k,v in pairs(self.inventory) do
        self.player:GiveWeapon( k, v )
    end

    Network:Send( self.player, "DerbyExit" )
end

--[[
    Actual Derby gamemode.
    TODO: Add a name so that you can have many Derby modes running through the single script.
]]
class "Derby"
function table.find(l, f)
  for _, v in ipairs(l) do
    if v == f then
      return _
    end
  end
  return nil
end

local Ids = {
    4,
    8,
    33,
    40,
    41,
    42,
    68,
    71,
    76,
}

-- local Ids = {
    -- 2
-- }

function GetRandomVehicleId()
    return Ids[math.random(1 , #Ids)]
end

function Derby:CreateSpawns()
    local center = Vector3( 6923.261230, 760, 1035.510010 )
    local cnt = 0
    local blacklist = { 0, 174, 19, 18, 17, 16, 170, 171, 172, 173, 151, 152, 153, 154, 155, 129, 128, 127, 126, 125, 110, 109, 108, 107, 84, 83, 82, 81, 80, 64, 63, 62, 61, 39, 38, 36, 35 }
    
    for i=0,360,2 do        
        if table.find(blacklist, cnt) == nil then
            local x = center.x + (math.sin( 2 * i * math.pi/360 ) * 165)
            local y = center.y 
            local z = center.z + (math.cos( 2 * i * math.pi/360 ) * 165)
            
            local radians = math.rad(360 - i)
            
            angle = Angle.AngleAxis(radians , Vector3(0 , -1 , 0))

            local vehicle = Vehicle.Create( GetRandomVehicleId(), Vector3( x, y, z ), angle )
            
            vehicle:SetEnabled( true )
            vehicle:SetWorld( self.world )

            self.vehicles[vehicle:GetId()] = vehicle
            table.insert(self.spawns, Vector3( x, y+4, z ))
        end
        cnt = cnt + 1
    end
end

function Derby:__init( spawn )
    self.world = World.Create()
    self.world:SetTimeStep( 10 )
    self.world:SetTime( 0 )
    
    self.spawn = spawn
    self.spawns = {}

    self.vehicles = {}
    self:CreateSpawns()
    
    self.players = {}
    self.last_broadcast = 0

    Events:Subscribe( "PlayerChat", self, self.ChatMessage )
    Events:Subscribe( "ModuleUnload", self, self.ModuleUnload )
    
    Events:Subscribe( "PlayerJoin", self, self.PlayerJoined )
    Events:Subscribe( "PlayerQuit", self, self.PlayerQuit )
    
    Events:Subscribe( "PlayerDeath", self, self.PlayerDeath )
    Events:Subscribe( "PlayerSpawn", self, self.PlayerSpawn )
    Events:Subscribe( "PostTick", self, self.PostTick )

    Events:Subscribe( "PlayerEnterVehicle", self, self.PlayerEnterVehicle )
    Events:Subscribe( "PlayerExitVehicle", self, self.PlayerExitVehicle )

    Events:Subscribe( "JoinGamemode", self, self.JoinGamemode )
end

function Derby:ModuleUnload()
    -- Remove the vehicles we have spawned
    for k,v in pairs(self.vehicles) do
        v:Remove()
    end
    self.vehicles = {}
    
    -- Restore the players to their original position and world.
    for k,v in pairs(self.players) do
        v:Leave()
        self:MessagePlayer(v.player, "Derby script unloaded. You have been restored to your starting pos.")
    end
    self.players = {}
end

function Derby:PostTick()
    if ( os.difftime(os.time(), self.last_broadcast) >= 5*60 ) then
        self:MessageGlobal( "Derby is underway! /derby to enter." )
        
        self.last_broadcast = os.time()
    end
    
    for k,v in pairs(self.players) do
        if v.timer ~= nil then
            if v.timer:GetSeconds() > 20 then
                v.timer = nil
                v.player:SetHealth(0)
                self:MessagePlayer( v.player, "You were killed for not being in a vehicle!" )
            end
        end
    end
end

function Derby:IsInDerby(player)
    return self.players[player:GetId()] ~= nil
end

function Derby:GetDomePlayer(player)
    return self.players[player:GetId()]
end

function Derby:MessagePlayer(player, message)
    player:SendChatMessage( "[Derby] " .. message, Color(0xfff0b010) )
end

function Derby:MessageGlobal(message)
    Chat:Broadcast( "[Derby] " .. message, Color(0xfff0c5b0) )
end

function Derby:EnterDerby(player)
    --[[if player:GetWorldId() ~= -1 then
        self:MessagePlayer(player, "You must exit all other game modes before joining.")
        return
    end]]--

    local args = {}
    args.name = "Derby"
    args.player = player
    Events:Fire( "JoinGamemode", args )
    
    local p = DerbyPlayer(player, self)
    p:Enter()
    
    self:MessagePlayer(player, "You have entered the derby! Type /derby to leave.") 
    self.players[player:GetId()] = p
end

function Derby:LeaveDerby(player)
    local p = self.players[player:GetId()]
    if p == nil then return end

    p:Leave()
    
    self:MessagePlayer(player, "You have left the derby! Type /derby to enter at any time.")    
    self.players[player:GetId()] = nil
end

function Derby:ChatMessage(args)
    local msg = args.text
    local player = args.player
    
    -- If the string is't a command, we're not interested!
    if ( msg:sub(1, 1) ~= "/" ) then
        return true
    end    
    
    local cmdargs = {}
    for word in string.gmatch(msg, "[^%s]+") do
        table.insert(cmdargs, word)
    end
    
    if ( cmdargs[1] == "/derby" ) then
        if ( self:IsInDerby(player) ) then
            self:LeaveDerby(player, false)
        else        
            self:EnterDerby(player)
        end
    end
    
    return false
end

function Derby:PlayerJoined(args)
    self.players[args.player:GetId()] = nil
end

function Derby:PlayerQuit(args)
    self.players[args.player:GetId()] = nil
end

function Derby:PlayerDeath(args)
    if ( not self:IsInDerby(args.player) ) then
        return true
    end

    self.players[args.player:GetId()].timer = nil
end

function Derby:PlayerSpawn(args)
    if ( not self:IsInDerby(args.player) ) then
        return true
    end
    
    self:MessagePlayer(args.player, 
        "You have spawned in the derby. Type /derby if you wish to leave.")
    
    local spawn = self.spawns[ math.random(1, #self.spawns) ]
    args.player:Teleport(spawn, Angle())
    args.player:ClearInventory()

    self.players[args.player:GetId()].timer = nil
    
    return false
end

function Derby:PlayerEnterVehicle(args)
    if ( not self:IsInDerby(args.player) ) then
        return true
    end

    self.players[args.player:GetId()].timer = nil

    Network:Send( args.player, "DerbyEnterVehicle" )
end

function Derby:PlayerExitVehicle(args)
    if ( not self:IsInDerby(args.player) ) then
        return true
    end

    if args.player:GetHealth() > 0.1 then
        self.players[args.player:GetId()].timer = Timer()
        self:MessagePlayer(args.player, 
            "If you do not enter a vehicle in 20 seconds, you will be killed.")

        Network:Send( args.player, "DerbyExitVehicle" )
    end
end

function Derby:JoinGamemode( args )
    if args.name ~= "Derby" then
        self:LeaveDerby( args.player )
    end
end

local spawn = Vector3(7138.460938, 826.369690, 1097.474609)

derby = Derby( spawn )