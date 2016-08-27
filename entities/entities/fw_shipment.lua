if SERVER then AddCSLuaFile() end

ENT.PrintName = "Shipment"
ENT.Author = "thelastpenguin"
ENT.Type = "anim"
ENT.Base = "base_entity"

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/items/item_item_crate.mdl")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysWake()

		self:SetUseType(SIMPLE_USE)
		self.Health = 200
	end
end

function ENT:Draw()
	self:DrawModel()
	if self:GetItemTable() then
		self:FWDrawInfo()
	end
end

function ENT:CustomUI(panel)
	local itemTable = self:GetItemTable()
	panel:AddSuperHeader(itemTable.name)

	local count = panel:AddHeader('')

	count:SetRefresh(function(memory)
		if memory.count ~= self:GetCount() then
			return true
		end
		return false
	end, function()
		count:SetText('REMAINING: ' .. tostring(self:GetCount()))
	end)
end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Item")
	self:NetworkVar("Int", 1, "Count")
end

function ENT:GetItemTable()
	return fw.ents.shipment_list[self:GetItem()]
end

function ENT:GetDisplayPosition()
	local obbcenter = self:OBBCenter()
	local obbmax = self:OBBMaxs()
	return Vector(obbcenter.x, obbcenter.y, obbmax.z), Angle(0, 90, 0), 0.15
end


function ENT:Use(activator)
	if not IsValid(activator) or not activator:IsPlayer() then return end

	self:EmitSound('ambient/misc/clank3.wav', 75, 100, 1)

	self:SetCount(self:GetCount() - 1)
	if self:GetCount() == 0 then self:Remove() end
	fw.ents.createWeapon(activator, self:GetItemTable())
end
