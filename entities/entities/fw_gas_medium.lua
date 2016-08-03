if SERVER then AddCSLuaFile() end

ENT.Type = "anim"
ENT.Base = "base_entity"

ENT.PrintName		= "Medium Gas Can"
ENT.Author			= "thelastpenguin"
ENT.Category        = "Faction Wars"

ENT.NETWORK_SIZE = 500

ENT.GeneratesResources = {
	["power"] = 5
}

ENT.Spawnable = true
ENT.AdminSpawnable = true

if SERVER then
  function ENT:Initialize()
  	self:SetModel "models/props_junk/gascan001a.mdl"
  	self:PhysicsInit(SOLID_VPHYSICS)
  	self:SetMoveType(MOVETYPE_VPHYSICS)
  	self:SetSolid(SOLID_VPHYSICS)
  	self:SetUseType(SIMPLE_USE)

  	local phys = self:GetPhysicsObject()
  	if (phys:IsValid()) then
  		phys:Wake()
  	end

  	fw.resource.resourceEntity(self)

  	timer.Create('generator-' .. self:EntIndex(), 10, 0, function()
  		self:ConsumeResource('gas', 1)
  	end)
  	self:ConsumeResource('gas', 0)
  end

  function ENT:OnRemove()
    fw.resource.removeEntity(self)
  end

  function ENT:Think()

  end
else
  function ENT:Draw()
  	self:DrawModel()
  end
end