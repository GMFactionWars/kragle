fw.config = fw.config or {} -- for now. todo: make into a module

-- where should data get stored
fw.config.dataDir = 'factionwars_sv'

fw.config.sql = {
	host = '',
	database = '',
	username = '',
	password = '',
	module = 'sqlite',
}

fw.config.dataStore = 'text' -- text OR sql

fw.config.data_cacheUpdateInterval = 60 -- SECONDS
fw.config.data_storeUpdateInterval = 60 * 10 -- SECONDS
assert(fw.config.data_storeUpdateInterval > fw.config.data_cacheUpdateInterval, "defeats the point of caching")

fw.config.dropBlacklist = {
	weapon_physgun = true,
	weapon_physcannon = true,
	gmod_tool = true,
	gmod_camera = true,
	weapon_fists = true,
}


require 'tmysql4'

mysql = setmetatable({
	GetTable = setmetatable({}, {
		__call = function(self)
			return self
		end
	})
}, {
	__call = function(self, ...)
		return self.Connect(...)
	end
})

local DATABASE = {
	__tostring = function(self)
		return self.Database .. '@' .. self.Hostname .. ':' ..  self.Port
	end
}
DATABASE.__concat 	= DATABASE.__tostring
DATABASE.__index 	= DATABASE

local STATEMENT = {
	__tostring = function(self)
		return self.Query
	end,
	__call = function(self, ...)
		return self:Run(...)
	end
}
STATEMENT.__concat 	= STATEMENT.__tostring
STATEMENT.__index 	= STATEMENT

_R.MySQLDatabase 	= DATABASE
_R.MySQLStatement 	= STATEMENT

local tostring 		= tostring
local SysTime 		= SysTime
local pairs 		= pairs
local select 		= select
local isfunction 	= isfunction
local string_gsub 	= string.gsub

local color_purple 	= Color(185,0,255)
local color_white 	= Color(250,250,250)

local query_queue	= {}

function mysql.Connect(hostname, username, password, database, port, optional_socketpath, optional_clientflags)
	local db_obj = setmetatable({
		Hostname = hostname,
		Username = username,
		Password = password,
		Database = database,
		Port 	 = port,
	}, DATABASE)

	if mysql.GetTable[tostring(db_obj)] then
		return mysql.GetTable[tostring(db_obj)]
	end

	db_obj.Handle, db_obj.Error = tmysql.initialize(hostname, username, password, database, port, optional_socketpath, optional_clientflags)

	if db_obj.Error then
		db_obj:Log(db_obj.Error)
	elseif (db_obj.Handle == false) then
		db_obj:Log('Failed to connect to database ' .. db_obj .. '.')
	else
		mysql.GetTable[tostring(db_obj)] = db_obj

		db_obj:Log('Connected to database ' .. db_obj .. ' successfully.')
	end

	--self:SetOption(MYSQL_SET_CLIENT_IP, GetConVarString('ip'))
	--self:Connect()

	return db_obj
end


function DATABASE:Connect()
	return self.Handle:Connect()
end

function DATABASE:Disconnect()
	return self.Handle:Disconnect()
end

function DATABASE:Poll()
	self.Handle:Poll()
end

function DATABASE:Escape(value)
	return self.Handle:Escape(tostring(value))
end

function DATABASE:Log(message)
	MsgC(color_purple, '[MySQL] ', color_white, tostring(message) .. '\n')
end


local retry_errors = {
	['Lost connection to MySQL server during query'] = true,
	[' MySQL server has gone away'] = true,
}

--[[function DATABASE:Query(query, ...)
	local cback
	local varcount = select('#', ...)
	if (varcount > 0) then
		local values = {}
		cback = select(varcount, ...)
		if (varcount > 1) then
			for i = 1, (varcount - 1) do
				local v = select(i, ...)
				values[i] = '"' .. self.Handle:Escape(v) .. '"'
			end
		elseif (not isfunction(cback)) then
			query = string_gsub(query, '?', cback)
		end
	end
	
	print(varcount, query)
	self.Handle:Query(query, function(results)
		if (results[1].error ~= nil) then
			self:Log(results[1].error)
			if retry_errors[results[1].error] then
				if query_queue[query] then
					query_queue[query].Trys = query_queue[query].Trys + 1
				else
					query_queue[query] = {
						Db 		= self, 
						Query 	= query,
						Trys 	= 0,
						Cback 	= cback
					}
				end
			end
		elseif cback then
			cback(results[1].data, results[1].lastid, results[1].affected, results[1].time)
		end
	end)
end]]

function DATABASE:Query(query, ...)
	local args = {...}
	local count = 0
	query = query:gsub('?', function()
		count = count + 1
		return '"' .. self:Escape(args[count]) .. '"'
	end)

	self.Handle:Query(query, function(results)
		if (results[1].error ~= nil) then
			self:Log(results[1].error)
			if retry_errors[results[1].error] then
				if query_queue[query] then
					query_queue[query].Trys = query_queue[query].Trys + 1
				else
					query_queue[query] = {
						Db 		= self, 
						Query 	= query,
						Trys 	= 0,
						Cback 	= args[count + 1]
					}
				end
			end
		elseif (isfunction(args[count + 1])) then
			args[count + 1](results[1].data, results[1].lastid, results[1].affected, results[1].time)
		end
	end)
end

function DATABASE:QuerySync(query, ...)
	local data, lastid, affected, time
	local start = SysTime() + 0.3
	if (... == nil) then
		self:Query(query, function(_data, _lastid, _affected, _time)
			data, lastid, affected, time = _data, _lastid, _affected, _time
		end)
	else
		self:Query(query, ..., function(_data, _lastid, _affected, _time)
			data, lastid, affected, time = _data, _lastid, _affected, _time
		end)
	end
	
	while (not data) and (start >= SysTime()) do
		self:Poll()
	end
	return data, lastid, affected, time
end

function DATABASE:Prepare(query)
	local sep 			= '?'
	local quo 			= '"'
	local _, varcount 	= string_gsub(query, sep, sep)
	local dbhandle 		= self.Handle
	local db 			= self
	local values		= {}

	local function escapeHelper(count, a, ...)
		if not a or count == 0 then return end 
		return quo .. db:Escape(a) .. quo, escapeHelper(count - 1, ...) 
	end 
	local fastQuery = query:gsub('?', '%s')

	return setmetatable({
		Handle = self.Handle,
		Query = query,
		Count = varcount,
		Values = values,
		Run = function(self, ...)
			local count = 0
			local cback = select(varcount + 1, ...)
			local query = string.format(fastQuery, escapeHelper(varcount, ...))
			dbhandle:Query(query, function(results)
				if (results[1].error ~= nil) then
					db:Log(results[1].error)
					if retry_errors[results[1].error] then
						if query_queue[query] then
							query_queue[query].Trys = query_queue[query].Trys + 1
						elseif cback then
							query_queue[query] = {
								Db 		= db, 
								Query 	= query,
								Trys 	= 0,
								Cback 	= cback
							}
						end
					end
				elseif cback then
					cback(results[1].data, results[1].lastid, results[1].affected, results[1].time)
				end
			end)
		end,
	}, STATEMENT)
end


function DATABASE:SetCharacterSet(charset)
	self.Handle:SetCharacterSet(charset)
end

function DATABASE:SetOption(opt, value)
	self.Handle:SetOption(opt, value)
end


function DATABASE:GetServerInfo()
	return self.Handle:GetServerInfo()
end

function DATABASE:GetHostInfo()
	return self.Handle:GetHostInfo()
end

function DATABASE:GetServerVersion()
	return self.Handle:GetServerVersion()
end

function STATEMENT:RunSync(...)
	local data, lastid, affected, time
	local start = SysTime() + 0.3

	if (... == nil) then
		self:Run(..., function(_data, _lastid, _affected, _time)
			data, lastid, affected, time = _data, _lastid, _affected, _time
		end)
	else
		self:Run(function(_data, _lastid, _affected, _time)
			data, lastid, affected, time = _data, _lastid, _affected, _time
		end)
	end

	while (not data) and (start >= SysTime()) do
		self.Handle:Poll()
	end
	return data, lastid, affected, time
end

function STATEMENT:GetQuery()
	return self.Query
end

function STATEMENT:GetCount()
	return self.Count
end

function STATEMENT:GetDatabase()
	return self.Handle
end



timer.Create('mysql.QueryQueue', 0.5, 0, function()
	for k, v in pairs(query_queue) do
		if (v.Trys < 5) then
			v.Db:Query(v.Query, v.Cback)
			v.Trys = v.Trys + 1
		else
			query_queue[k] = nil
		end
	end
end)